import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';

import 'meet_models.dart';
import 'touch_detector.dart';

/// Why Meet can't run right now -- each maps to one thing the user can fix.
enum MeetBlockReason { bluetoothOff, locationOff, permissionDenied, cannotBroadcast, noBluetooth, notResponding }

/// What the screen animates from: the strongest nearby Throughline phone
/// (null = none heard) and how far into the hold-still the touch is (0..1).
class MeetSignal {
  final int? rssi;
  final double hold;

  const MeetSignal(this.rssi, this.hold);

  static const none = MeetSignal(null, 0);
}

class MeetBlocked implements Exception {
  final MeetBlockReason reason;
  const MeetBlocked(this.reason);
}

/// Bluetooth half of Meet: broadcasts my code inside a service UUID, scans
/// for other Throughline phones, and reports a "touch" when one stays very
/// close (signal at or above the threshold) for long enough.
///
/// Only a random code ever goes over the air -- no name, no account id --
/// and it changes every few minutes (see MeetSession.rotateAfter).
class MeetProximity {
  final _peripheral = FlutterBlePeripheral();
  final _touches = StreamController<String>.broadcast();
  final _signal = StreamController<MeetSignal>.broadcast();
  final _detector = TouchDetector(prefix: '');
  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _signalTimer;

  /// Codes of phones that are touching this one. Repeats about once a
  /// second for as long as the touch lasts.
  Stream<String> get touches => _touches.stream;

  /// About 6 times a second while scanning: strongest Throughline signal
  /// heard in the last 2 s, and the hold progress -- drives the glow, the
  /// "getting closer" hint and the fill ring.
  Stream<MeetSignal> get signal => _signal.stream;

  /// Runs one Bluetooth step with a time limit and a log line, so a plugin
  /// call that never answers shows up as "Bluetooth isn't responding" (with
  /// Try again) instead of an endless spinner -- confirmed on a Realme
  /// Android 11 phone that one of these can hang.
  Future<T> _step<T>(String name, Future<T> Function() run, Duration limit) async {
    debugPrint('[meet] $name...');
    try {
      final value = await run().timeout(limit);
      debugPrint('[meet] $name ok');
      return value;
    } on TimeoutException {
      debugPrint('[meet] $name timed out after ${limit.inSeconds}s');
      throw const MeetBlocked(MeetBlockReason.notResponding);
    }
  }

  Future<void> _quietly(String name, Future<void> Function() run) async {
    try {
      await run().timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('[meet] $name: $e');
    }
  }

  Future<int> _androidSdk() async =>
      Platform.isAndroid ? (await DeviceInfoPlugin().androidInfo).version.sdkInt : 0;

  /// Checks everything Meet needs before starting, in the order the user
  /// would have to fix them. Throws [MeetBlocked].
  Future<void> preflight() async {
    if (!await _step('bluetooth supported', () => FlutterBluePlus.isSupported, const Duration(seconds: 5))) {
      throw const MeetBlocked(MeetBlockReason.noBluetooth);
    }
    final adapter = await FlutterBluePlus.adapterState
        .where((s) => s != BluetoothAdapterState.unknown)
        .first
        .timeout(const Duration(seconds: 3), onTimeout: () => BluetoothAdapterState.unknown);
    if (adapter != BluetoothAdapterState.on) throw const MeetBlocked(MeetBlockReason.bluetoothOff);
    // Android 11 and older only report nearby Bluetooth devices to apps
    // while the phone's Location switch is on.
    final sdk = await _step('android version', _androidSdk, const Duration(seconds: 5));
    if (Platform.isAndroid &&
        sdk <= 30 &&
        !await _step('location on', Geolocator.isLocationServiceEnabled, const Duration(seconds: 5))) {
      throw const MeetBlocked(MeetBlockReason.locationOff);
    }
    // Long limit: this may be waiting on the user answering a permission prompt.
    final perm = await _step('permission', _peripheral.requestPermission, const Duration(seconds: 60));
    debugPrint('[meet] permission state: $perm');
    if (perm != PeripheralBluetoothState.granted && perm != PeripheralBluetoothState.ready) {
      throw const MeetBlocked(MeetBlockReason.permissionDenied);
    }
  }

  Future<void> start(MeetSession session) async {
    _apply(session);
    await _advertise(session.serviceUuid);
    await _scan();
  }

  /// Switch to a fresh code without stopping the scan.
  Future<void> rotate(MeetSession session) async {
    _apply(session);
    await _advertise(session.serviceUuid);
  }

  Future<void> stop() async {
    await _scanSub?.cancel();
    _scanSub = null;
    _signalTimer?.cancel();
    _signalTimer = null;
    _detector.clear();
    await _quietly('stop scan', FlutterBluePlus.stopScan);
    await _quietly('stop broadcast', _peripheral.stop);
  }

  Future<void> dispose() async {
    await stop();
    await _touches.close();
    await _signal.close();
  }

  void _apply(MeetSession s) {
    _detector
      ..prefix = s.uuidPrefix
      ..threshold = s.rssiThreshold
      ..touchFor = s.touchFor;
  }

  Future<void> _advertise(String serviceUuid) async {
    await _quietly('stop broadcast', _peripheral.stop);
    try {
      final state = await _step(
        'start broadcast',
        () => _peripheral.start(
          advertiseData: AdvertiseDataCore(serviceUuid: serviceUuid),
          androidSettings: const AndroidAdvertiseSettings(
            advertiseSettings: AdvertiseSettings(connectable: false, timeout: 0),
          ),
        ),
        const Duration(seconds: 8),
      );
      debugPrint('[meet] broadcast state: $state');
    } on MeetBlocked {
      rethrow;
    } catch (e) {
      // Some budget phones can scan but not broadcast.
      debugPrint('[meet] advertise failed: $e');
      throw const MeetBlocked(MeetBlockReason.cannotBroadcast);
    }
  }

  Future<void> _scan() async {
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.onScanResults.listen(_onResults, onError: (e) => debugPrint('[meet] scan error: $e'));
    try {
      await _step(
        'start scan',
        () => FlutterBluePlus.startScan(
          continuousUpdates: true,
          androidScanMode: AndroidScanMode.lowLatency,
          androidCheckLocationServices: false, // checked in preflight(), only where Android needs it
        ),
        const Duration(seconds: 10),
      );
    } on MeetBlocked {
      rethrow;
    } catch (e) {
      debugPrint('[meet] scan failed: $e');
      final msg = e.toString().toLowerCase();
      if (msg.contains('location')) throw const MeetBlocked(MeetBlockReason.locationOff);
      if (msg.contains('permission')) throw const MeetBlocked(MeetBlockReason.permissionDenied);
      if (msg.contains('turned on') || msg.contains('adapter')) throw const MeetBlocked(MeetBlockReason.bluetoothOff);
      rethrow;
    }
    _signalTimer ??= Timer.periodic(const Duration(milliseconds: 160), (_) => _emitSignal());
  }

  void _onResults(List<ScanResult> results) {
    for (final r in results) {
      for (final uuid in r.advertisementData.serviceUuids) {
        final code = TouchDetector.codeFromUuid(uuid.str128, _detector.prefix);
        if (code == null) continue;
        final touched = _detector.sample(code, r.rssi, DateTime.now(), sampleId: r.timeStamp);
        if (touched != null && !_touches.isClosed) _touches.add(touched);
      }
    }
  }

  void _emitSignal() {
    final now = DateTime.now();
    if (!_signal.isClosed) _signal.add(MeetSignal(_detector.nearest(now), _detector.holdProgress(now)));
  }
}
