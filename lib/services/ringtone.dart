import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// Beeps every 2s while an incoming call is pending, matching the web
/// client's ring interval. Synthesizes a short WAV tone in memory rather
/// than shipping a bundled asset -- Flutter's SystemSound API is not a
/// reliable audible alert on Android (it's effectively a no-op there).
class Ringtone {
  static final AudioPlayer _player = AudioPlayer();
  static Timer? _timer;
  static Uint8List? _tone;

  static Future<void> start() async {
    if (_timer != null) return;
    _tone ??= _buildTone();
    _ring();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _ring());
  }

  static void _ring() {
    _player.play(BytesSource(_tone!));
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
    _player.stop();
  }

  static Uint8List _buildTone() {
    const sampleRate = 44100;
    const durationMs = 400;
    const freq = 950.0;
    final sampleCount = (sampleRate * durationMs / 1000).round();
    final fadeSamples = (sampleCount * 0.1).round();
    final samples = Int16List(sampleCount);
    for (var i = 0; i < sampleCount; i++) {
      final t = i / sampleRate;
      double envelope = 1.0;
      if (i < fadeSamples) envelope = i / fadeSamples;
      if (i > sampleCount - fadeSamples) envelope = (sampleCount - i) / fadeSamples;
      samples[i] = (32767 * 0.5 * envelope * sin(2 * pi * freq * t)).round();
    }
    final dataBytes = samples.buffer.asUint8List();
    return Uint8List.fromList([..._wavHeader(dataBytes.length, sampleRate), ...dataBytes]);
  }

  static List<int> _wavHeader(int dataLength, int sampleRate) {
    const bitsPerSample = 16;
    const channels = 1;
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    const blockAlign = channels * bitsPerSample ~/ 8;
    return [
      ..._ascii('RIFF'),
      ..._le32(36 + dataLength),
      ..._ascii('WAVE'),
      ..._ascii('fmt '),
      ..._le32(16),
      ..._le16(1),
      ..._le16(channels),
      ..._le32(sampleRate),
      ..._le32(byteRate),
      ..._le16(blockAlign),
      ..._le16(bitsPerSample),
      ..._ascii('data'),
      ..._le32(dataLength),
    ];
  }

  static List<int> _ascii(String s) => s.codeUnits;
  static List<int> _le32(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
  static List<int> _le16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
}
