import 'package:driver_focus/features/distraction_detection/yawn_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  YawnTracker newTracker() => YawnTracker(
        openThreshold: 0.22,
        minOpenDuration: const Duration(milliseconds: 1200),
      );

  test('does not confirm a yawn from a brief mouth opening', () {
    final tracker = newTracker();
    final t = DateTime(2026, 1, 1);
    expect(tracker.update(at: t, mouthOpenRatio: 0.4), isFalse);
    expect(
      tracker.update(
        at: t.add(const Duration(milliseconds: 500)),
        mouthOpenRatio: 0.4,
      ),
      isFalse,
    );
  });

  test('confirms a yawn once the mouth stays open long enough', () {
    final tracker = newTracker();
    final t = DateTime(2026, 1, 1);
    tracker.update(at: t, mouthOpenRatio: 0.4);
    expect(
      tracker.update(
        at: t.add(const Duration(milliseconds: 1300)),
        mouthOpenRatio: 0.4,
      ),
      isTrue,
    );
  });

  test('resets when the mouth closes', () {
    final tracker = newTracker();
    final t = DateTime(2026, 1, 1);
    tracker.update(at: t, mouthOpenRatio: 0.4);
    // Mouth closes, resetting the timer.
    tracker.update(
      at: t.add(const Duration(milliseconds: 800)),
      mouthOpenRatio: 0.05,
    );
    // Reopen, duration counts from here, so not yet a yawn.
    expect(
      tracker.update(
        at: t.add(const Duration(milliseconds: 1600)),
        mouthOpenRatio: 0.4,
      ),
      isFalse,
    );
  });

  test('treats a missing mouth measurement as closed', () {
    final tracker = YawnTracker(
      minOpenDuration: const Duration(milliseconds: 500),
    );
    final t = DateTime(2026, 1, 1);
    tracker.update(at: t, mouthOpenRatio: 0.4);
    expect(
      tracker.update(
          at: t.add(const Duration(seconds: 1)), mouthOpenRatio: null),
      isFalse,
    );
  });

  test('calibrate raises the threshold relative to the resting mouth', () {
    final tracker = YawnTracker(
      calibrationMargin: 0.2,
      minOpenDuration: const Duration(milliseconds: 1200),
    );
    tracker.calibrate(0.3); // resting 0.3 -> threshold 0.5
    final t = DateTime(2026, 1, 1);

    // 0.45 is below the new threshold, so it never counts as open.
    tracker.update(at: t, mouthOpenRatio: 0.45);
    expect(
      tracker.update(
        at: t.add(const Duration(seconds: 2)),
        mouthOpenRatio: 0.45,
      ),
      isFalse,
    );

    // 0.6 is above it: opens, and after the duration it's a yawn.
    tracker.reset();
    tracker.update(at: t, mouthOpenRatio: 0.6);
    expect(
      tracker.update(
        at: t.add(const Duration(milliseconds: 1300)),
        mouthOpenRatio: 0.6,
      ),
      isTrue,
    );
  });
}
