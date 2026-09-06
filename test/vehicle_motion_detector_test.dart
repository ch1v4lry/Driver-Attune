import 'package:driver_attune/features/motion/vehicle_motion_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 12);

  /// Feeds [seconds] of steady [vibration] at 4 Hz.
  void feed(
    VehicleMotionDetector d,
    DateTime from,
    int seconds,
    double vibration,
  ) {
    var t = from;
    for (var i = 0; i < seconds * 4; i++) {
      d.update(at: t, vibration: vibration);
      t = t.add(const Duration(milliseconds: 250));
    }
  }

  test('starts out stationary', () {
    expect(VehicleMotionDetector().isMoving, isFalse);
  });

  test('sustained vibration reads as moving', () {
    final d = VehicleMotionDetector();
    // Real driving measured around 0.9 and up.
    feed(d, t0, 4, 1.4);
    expect(d.isMoving, isTrue);
  });

  test('a brief jolt while parked does not read as moving', () {
    final d = VehicleMotionDetector();
    // Someone bumps the phone for well under the confirmation window.
    feed(d, t0, 1, 2.0);
    expect(d.isMoving, isFalse);
  });

  test('going quiet for long enough reads as stopped', () {
    final d = VehicleMotionDetector();
    feed(d, t0, 4, 1.2);
    expect(d.isMoving, isTrue);

    feed(d, t0.add(const Duration(seconds: 4)), 8, 0.05);
    expect(d.isMoving, isFalse);
  });

  test('a short smooth stretch does not read as stopped', () {
    final d = VehicleMotionDetector();
    feed(d, t0, 4, 1.2);
    expect(d.isMoving, isTrue);

    // Briefly glassy road, shorter than the stop confirmation window.
    feed(d, t0.add(const Duration(seconds: 4)), 3, 0.05);
    expect(d.isMoving, isTrue);
  });

  test('values between the thresholds hold the current state', () {
    final d = VehicleMotionDetector();
    feed(d, t0, 4, 1.2);
    expect(d.isMoving, isTrue);

    // An idling engine at a stop lands here: ambiguous, so nothing changes
    // however long it lasts.
    feed(d, t0.add(const Duration(seconds: 4)), 20, 0.7);
    expect(d.isMoving, isTrue);
  });

  test('an app opened in a parked, idling car stays stopped', () {
    // The other half of the wide dead band: with no prior state to hold, an
    // idling engine must not be mistaken for driving just because the car
    // shakes.
    final d = VehicleMotionDetector();
    feed(d, t0, 30, 0.85);
    expect(d.isMoving, isFalse);
  });

  group('GPS speed', () {
    test('a clear driving speed reads as moving', () {
      final d = VehicleMotionDetector();
      var t = t0;
      for (var i = 0; i < 6; i++) {
        d.updateSpeed(at: t, speedMetersPerSecond: 14);
        t = t.add(const Duration(milliseconds: 400));
      }
      expect(d.isMoving, isTrue);
      expect(d.isUsingSpeed, isTrue);
    });

    test('an idling engine at a stop reads as stopped', () {
      // The case the accelerometer alone gets wrong: the car shakes as much at
      // a stop sign as it does driving, so vibration says "moving" while GPS
      // correctly says the car is standing still.
      final d = VehicleMotionDetector();
      var t = t0;
      for (var i = 0; i < 8; i++) {
        d.updateSpeed(at: t, speedMetersPerSecond: 14);
        t = t.add(const Duration(milliseconds: 400));
      }
      expect(d.isMoving, isTrue);

      // Now stopped, but the engine is still running and shaking the phone.
      for (var i = 0; i < 12; i++) {
        d.updateSpeed(at: t, speedMetersPerSecond: 0.2);
        d.update(at: t, vibration: 0.9);
        t = t.add(const Duration(milliseconds: 400));
      }
      expect(d.isMoving, isFalse);
    });

    test('settles at a stop in seconds, not a minute', () {
      final d = VehicleMotionDetector();
      var t = t0;
      for (var i = 0; i < 8; i++) {
        d.updateSpeed(at: t, speedMetersPerSecond: 14);
        t = t.add(const Duration(milliseconds: 400));
      }

      final stoppedAt = t;
      var settledAfter = Duration.zero;
      for (var i = 0; i < 30; i++) {
        d.updateSpeed(at: t, speedMetersPerSecond: 0.0);
        if (!d.isMoving) {
          settledAfter = t.difference(stoppedAt);
          break;
        }
        t = t.add(const Duration(milliseconds: 400));
      }

      expect(settledAfter, lessThanOrEqualTo(const Duration(seconds: 4)));
    });

    test('speed between the thresholds holds the current state', () {
      final d = VehicleMotionDetector();
      var t = t0;
      for (var i = 0; i < 8; i++) {
        d.updateSpeed(at: t, speedMetersPerSecond: 14);
        t = t.add(const Duration(milliseconds: 400));
      }
      expect(d.isMoving, isTrue);

      // Crawling in traffic, in the dead band: stays moving.
      for (var i = 0; i < 20; i++) {
        d.updateSpeed(at: t, speedMetersPerSecond: 2.6);
        t = t.add(const Duration(milliseconds: 400));
      }
      expect(d.isMoving, isTrue);
    });

    test('falls back to vibration once the fix goes stale', () {
      final d = VehicleMotionDetector();
      var t = t0;
      d.updateSpeed(at: t, speedMetersPerSecond: 0.0);
      expect(d.isUsingSpeed, isTrue);

      // No further fixes, a tunnel or lost signal. Past the freshness window
      // the accelerometer takes over again.
      t = t.add(const Duration(seconds: 30));
      for (var i = 0; i < 20; i++) {
        d.update(at: t, vibration: 0.9);
        t = t.add(const Duration(milliseconds: 400));
      }
      expect(d.isUsingSpeed, isFalse);
      expect(d.isMoving, isTrue);
    });

    test('a negative speed is treated as zero, not as movement', () {
      // Some platforms report a negative value to mean "unknown".
      final d = VehicleMotionDetector();
      d.updateSpeed(at: t0, speedMetersPerSecond: -1);
      expect(d.speedMetersPerSecond, 0);
      expect(d.isMoving, isFalse);
    });

    test('a null speed leaves the previous decision alone', () {
      final d = VehicleMotionDetector();
      var t = t0;
      for (var i = 0; i < 8; i++) {
        d.updateSpeed(at: t, speedMetersPerSecond: 14);
        t = t.add(const Duration(milliseconds: 400));
      }
      expect(d.isMoving, isTrue);

      d.updateSpeed(at: t, speedMetersPerSecond: null);
      expect(d.isMoving, isTrue);
    });
  });
}
