/// Decides when another phone counts as "touching" this one, from a stream
/// of (code, signal strength) samples. Pure Dart -- no Bluetooth here -- so
/// the rule can be unit-tested and tuned without two phones.
///
/// Rule: a code is touching once its signal has stayed at or above
/// [threshold] dBm for [touchFor]. While the touch lasts it is reported
/// again about once a second (the server pairs both phones' reports within
/// a few seconds, so repeats matter). Any weaker sample resets the clock.
class TouchDetector {
  String prefix;
  int threshold;
  Duration touchFor;
  final Duration repeatEvery;
  final Map<String, _Track> _tracks = {};

  TouchDetector({
    required this.prefix,
    this.threshold = -40,
    this.touchFor = const Duration(milliseconds: 800),
    this.repeatEvery = const Duration(seconds: 1),
  });

  /// The Meet code inside a 128-bit service UUID, or null if the UUID isn't
  /// a Throughline one.
  static String? codeFromUuid(String uuid, String prefix) {
    final hex = uuid.replaceAll('-', '').toLowerCase();
    final p = prefix.toLowerCase();
    if (hex.length != 32 || p.isEmpty || !hex.startsWith(p)) return null;
    return hex.substring(p.length);
  }

  /// Feeds one sample. Returns [code] when it should be reported as a touch.
  /// [sampleId] lets a re-delivered advertisement be ignored.
  String? sample(String code, int rssi, DateTime at, {Object? sampleId}) {
    final t = _tracks.putIfAbsent(code, () => _Track(at));
    if (sampleId != null && sampleId == t.lastSampleId) return null;
    t.lastSampleId = sampleId;
    t.lastRssi = rssi;
    t.lastHeard = at;
    if (rssi < threshold) {
      t.strongSince = null;
      return null;
    }
    t.strongSince ??= at;
    final held = at.difference(t.strongSince!);
    final sinceReport = t.lastReport == null ? null : at.difference(t.lastReport!);
    if (held >= touchFor && (sinceReport == null || sinceReport >= repeatEvery)) {
      t.lastReport = at;
      return code;
    }
    return null;
  }

  /// Strongest signal heard within [window] of [now], or null. Also forgets
  /// phones not heard for 30 s.
  int? nearest(DateTime now, {Duration window = const Duration(seconds: 2)}) {
    _tracks.removeWhere((_, t) => now.difference(t.lastHeard) > const Duration(seconds: 30));
    int? best;
    for (final t in _tracks.values) {
      if (now.difference(t.lastHeard) <= window && (best == null || t.lastRssi > best)) best = t.lastRssi;
    }
    return best;
  }

  /// How far into the hold the closest touching phone is, 0..1 -- drives the
  /// ring that fills while the user holds still. 0 once the signal drops or
  /// nothing has been heard for 1.5 s.
  double holdProgress(DateTime now) {
    var best = 0.0;
    for (final t in _tracks.values) {
      final since = t.strongSince;
      if (since == null || now.difference(t.lastHeard) > const Duration(milliseconds: 1500)) continue;
      final p = now.difference(since).inMilliseconds / touchFor.inMilliseconds.clamp(1, 1 << 30);
      if (p > best) best = p;
    }
    return best.clamp(0.0, 1.0);
  }

  void clear() => _tracks.clear();
}

class _Track {
  DateTime? strongSince;
  DateTime? lastReport;
  Object? lastSampleId;
  DateTime lastHeard;
  int lastRssi = -127;

  _Track(this.lastHeard);
}
