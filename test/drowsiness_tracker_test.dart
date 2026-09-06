import 'package:driver_attune/features/distraction_detection/drowsiness_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('is not drowsy before enough samples', () {
    final tracker = DrowsinessTracker(minSamples: 8, perclosThreshold: 0.2);
    var t = DateTime(2026, 1, 1);
    for (var i = 0; i < 4; i++) {
      tracker.record(at: t, eyesClosed: true);
      t = t.add(const Duration(milliseconds: 500));
    }
    expect(tracker.isDrowsy, isFalse);
  });

  test('becomes drowsy when the closed fraction exceeds the threshold', () {
    final tracker = DrowsinessTracker(minSamples: 8, perclosThreshold: 0.2);
    var t = DateTime(2026, 1, 1);
    const closed = [
      true,
      true,
      false,
      false,
      true,
      false,
      true,
      false,
      false,
      false,
    ];
    for (final c in closed) {
      tracker.record(at: t, eyesClosed: c);
      t = t.add(const Duration(milliseconds: 500));
    }
    expect(tracker.perclos, closeTo(0.4, 0.001));
    expect(tracker.isDrowsy, isTrue);
  });

  test('stays alert when the eyes are mostly open', () {
    final tracker = DrowsinessTracker(minSamples: 8, perclosThreshold: 0.2);
    var t = DateTime(2026, 1, 1);
    for (var i = 0; i < 12; i++) {
      tracker.record(at: t, eyesClosed: i == 0);
      t = t.add(const Duration(milliseconds: 500));
    }
    expect(tracker.isDrowsy, isFalse);
  });

  test('drops samples that fall outside the window', () {
    final tracker = DrowsinessTracker(
      window: const Duration(seconds: 2),
      minSamples: 1,
    );
    final start = DateTime(2026, 1, 1);
    tracker.record(at: start, eyesClosed: true);
    tracker.record(
        at: start.add(const Duration(seconds: 3)), eyesClosed: false);
    expect(tracker.perclos, 0);
  });
}
