import 'package:flutter_test/flutter_test.dart';
import 'package:throughline/features/meet/touch_detector.dart';

void main() {
  const prefix = '7e1a0c4e';
  const code = '0123456789abcdef01234567';
  final t0 = DateTime(2026, 10, 31, 12);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  TouchDetector detector() => TouchDetector(prefix: prefix, threshold: -40, touchFor: const Duration(milliseconds: 800));

  group('codeFromUuid', () {
    test('reads the code out of a Throughline service UUID', () {
      expect(TouchDetector.codeFromUuid('7E1A0C4E-0123-4567-89AB-CDEF01234567', prefix), code);
    });
    test('ignores other devices', () {
      expect(TouchDetector.codeFromUuid('0000180f-0000-1000-8000-00805f9b34fb', prefix), isNull);
      expect(TouchDetector.codeFromUuid('180f', prefix), isNull);
    });
  });

  group('touch rule', () {
    test('strong signal held long enough -> touch', () {
      final d = detector();
      expect(d.sample(code, -35, at(0)), isNull);
      expect(d.sample(code, -34, at(400)), isNull);
      expect(d.sample(code, -33, at(850)), code);
    });

    test('phone across the table (weak signal) never counts', () {
      final d = detector();
      for (var ms = 0; ms <= 5000; ms += 200) {
        expect(d.sample(code, -62, at(ms)), isNull);
      }
    });

    test('a weaker sample in between resets the clock', () {
      final d = detector();
      d.sample(code, -35, at(0));
      d.sample(code, -55, at(500)); // pulled apart
      expect(d.sample(code, -35, at(900)), isNull);
      expect(d.sample(code, -35, at(1800)), code);
    });

    test('while touching, repeats about once a second (not every sample)', () {
      final d = detector();
      final reports = <int>[];
      for (var ms = 0; ms <= 3000; ms += 100) {
        if (d.sample(code, -30, at(ms)) != null) reports.add(ms);
      }
      expect(reports, [800, 1800, 2800]);
    });

    test('the same advertisement delivered twice is counted once', () {
      final d = detector();
      d.sample(code, -35, at(0), sampleId: 1);
      expect(d.sample(code, -35, at(900), sampleId: 1), isNull);
      expect(d.sample(code, -35, at(950), sampleId: 2), code);
    });

    test('threshold comes from the server and can be changed live', () {
      final d = detector()..threshold = -55;
      d.sample(code, -50, at(0));
      expect(d.sample(code, -50, at(900)), code);
    });
  });

  test('holdProgress fills while held, resets when pulled apart or silent', () {
    final d = detector();
    expect(d.holdProgress(at(0)), 0);
    d.sample(code, -35, at(0));
    expect(d.holdProgress(at(400)), closeTo(0.5, 0.01));
    expect(d.holdProgress(at(1200)), 1.0);
    d.sample(code, -60, at(1300));
    expect(d.holdProgress(at(1300)), 0);
    d.sample(code, -35, at(2000));
    expect(d.holdProgress(at(4000)), 0); // nothing heard for 2 s
  });

  test('nearest: strongest recent signal, forgets stale phones', () {
    final d = detector();
    d.sample('a' * 24, -70, at(0));
    d.sample('b' * 24, -45, at(1000));
    expect(d.nearest(at(1500)), -45);
    expect(d.nearest(at(5000)), isNull); // nothing heard in the last 2 s
  });
}
