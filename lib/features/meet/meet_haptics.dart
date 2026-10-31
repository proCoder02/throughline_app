import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// Meet's vibrations -- real patterns rather than Android's generic touch
/// feedback, which some phones (confirmed on a Realme) play as a faint tick
/// that's easy to miss. Each one marks a step the user can't see while the
/// phones are pressed together. Falls back to system haptics if the phone
/// has no controllable vibrator.
class MeetHaptics {
  static bool? _hasVibrator;
  static bool? _hasAmplitude;

  static Future<bool> _ready() async {
    try {
      _hasVibrator ??= await Vibration.hasVibrator();
      _hasAmplitude ??= await Vibration.hasAmplitudeControl();
    } catch (_) {
      _hasVibrator = false;
    }
    return _hasVibrator ?? false;
  }

  static Future<void> _pulse(int ms, int amplitude, Future<void> Function() fallback) async {
    if (!await _ready()) return fallback();
    try {
      await Vibration.vibrate(duration: ms, amplitude: _hasAmplitude == true ? amplitude : -1);
    } catch (_) {
      await fallback();
    }
  }

  /// Another phone just came into range: one soft tap.
  static Future<void> detected() => _pulse(20, 70, HapticFeedback.selectionClick);

  /// Hold-still ring completed: one crisp tap.
  static Future<void> touched() => _pulse(35, 160, HapticFeedback.lightImpact);

  /// "You met …": tap, pause, tap.
  static Future<void> matched() async {
    if (!await _ready()) return HapticFeedback.mediumImpact();
    try {
      await Vibration.vibrate(
        pattern: const [0, 40, 70, 60],
        intensities: _hasAmplitude == true ? const [0, 180, 0, 255] : const [],
      );
    } catch (_) {
      await HapticFeedback.mediumImpact();
    }
  }

  /// Cards revealed: one longer, strong pulse.
  static Future<void> revealed() => _pulse(120, 255, HapticFeedback.heavyImpact);
}
