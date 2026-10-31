import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../theme.dart';
import 'meet_api.dart';
import 'meet_models.dart';

/// QR fallback: show my code or scan theirs. Works on any phone (and pairs
/// with the web app), for when Bluetooth can't be used. Pops with the
/// [MeetEncounter] once one side scans -- the Meet screen then runs the same
/// "Share?" step as a Bluetooth touch.
class MeetQrScreen extends StatefulWidget {
  final bool startOnScan;

  const MeetQrScreen({super.key, this.startOnScan = false});

  @override
  State<MeetQrScreen> createState() => _MeetQrScreenState();
}

class _MeetQrScreenState extends State<MeetQrScreen> {
  final _api = MeetApi();
  MeetQr? _qr;
  String? _error;
  Timer? _poll;
  Timer? _refresh;
  bool _scanning = false; // a scan is being sent -- ignore further frames

  @override
  void initState() {
    super.initState();
    _newCode();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _newCode() async {
    try {
      final qr = await _api.startQr();
      if (!mounted) return;
      setState(() {
        _qr = qr;
        _error = null;
      });
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) => _checkScanned());
      // Swap in a fresh code a little before this one expires.
      _refresh?.cancel();
      _refresh = Timer(qr.expiresIn - const Duration(seconds: 15), _newCode);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't make your code. Check your connection.");
    }
  }

  Future<void> _checkScanned() async {
    final qr = _qr;
    if (qr == null) return;
    try {
      final r = await _api.qrStatus(qr.token);
      if (r.status == 'scanned' && r.encounter != null && mounted) {
        _poll?.cancel();
        Navigator.of(context).pop(r.encounter);
      }
    } catch (_) {}
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_scanning) return;
    final value = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstWhere(
          (v) => v.startsWith('throughline-meet:'),
          orElse: () => '',
        );
    if (value.isEmpty) return;
    _scanning = true;
    try {
      final r = await _api.scanQr(value);
      if (!mounted) return;
      if (r.status == 'matched' && r.encounter != null) {
        Navigator.of(context).pop(r.encounter);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.error ?? "That code didn't work. Try again.")));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't send that. Check your connection.")));
      }
    }
    await Future<void>.delayed(const Duration(seconds: 2)); // don't re-fire on the same frame
    _scanning = false;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: widget.startOnScan ? 1 : 0,
      child: Scaffold(
        backgroundColor: AppColors.bgApp,
        appBar: AppBar(
          backgroundColor: AppColors.bgApp,
          title: const Text('Meet with a QR code'),
          bottom: TabBar(
            labelColor: AppColors.text,
            indicatorColor: AppColors.accent,
            tabs: const [Tab(text: 'My code'), Tab(text: 'Scan')],
          ),
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(), // the camera view shouldn't swipe away mid-scan
          children: [_myCode(), _scanner()],
        ),
      ),
    );
  }

  Widget _myCode() {
    final qr = _qr;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft)),
              const SizedBox(height: 12),
              FilledButton(onPressed: _newCode, child: const Text('Try again')),
            ] else if (qr == null)
              const CircularProgressIndicator()
            else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: QrImageView(data: qr.payload, size: 240, backgroundColor: Colors.white),
              ),
              const SizedBox(height: 24),
              Text('Let them scan this', style: appHeadlineFont(color: AppColors.text, fontSize: 20)),
              const SizedBox(height: 8),
              Text(
                'From Meet in their Throughline app, or the web app. Nothing is shared until you both tap Share.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSoft, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _scanner() {
    return Stack(
      children: [
        MobileScanner(
          controller: MobileScannerController(formats: const [BarcodeFormat.qrCode]),
          onDetect: _onDetect,
          errorBuilder: (_, __) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Camera unavailable. Allow camera access for Throughline in Settings, or ask them to scan your code instead.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSoft),
              ),
            ),
          ),
        ),
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 3),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 40,
          child: Text(
            "Point at the code on their screen",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 15, shadows: [Shadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 6)]),
          ),
        ),
      ],
    );
  }
}
