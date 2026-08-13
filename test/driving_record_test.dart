import 'package:driver_focus/features/distraction_detection/driver_state.dart';
import 'package:driver_focus/features/driving_record/driving_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 12);

  test('accumulates attentive driving time', () {
    final record = DrivingRecord(enabled: true);
    record.update(state: DriverState.attentive, at: t0, isDriving: true);
    record.update(
      state: DriverState.attentive,
      at: t0.add(const Duration(milliseconds: 500)),
      isDriving: true,
    );
    record.update(
      state: DriverState.attentive,
      at: t0.add(const Duration(seconds: 1)),
      isDriving: true,
    );

    expect(record.attentiveDuration, const Duration(seconds: 1));
    expect(record.distractedDuration, Duration.zero);
  });

  test('accumulates distracted driving time for unsafe states', () {
    final record = DrivingRecord(enabled: true);
    record.update(state: DriverState.lookingAway, at: t0, isDriving: true);
    record.update(
      state: DriverState.drowsy,
      at: t0.add(const Duration(milliseconds: 800)),
      isDriving: true,
    );

    expect(record.distractedDuration, const Duration(milliseconds: 800));
    expect(record.attentiveDuration, Duration.zero);
  });

  test('computes the distracted fraction', () {
    final record = DrivingRecord(enabled: true);
    // 1s attentive, then 1s distracted -> 50%.
    record.update(state: DriverState.attentive, at: t0, isDriving: true);
    record.update(
      state: DriverState.usingPhone,
      at: t0.add(const Duration(seconds: 1)),
      isDriving: true,
    );
    record.update(
      state: DriverState.attentive,
      at: t0.add(const Duration(seconds: 2)),
      isDriving: true,
    );

    expect(record.totalDuration, const Duration(seconds: 2));
    expect(record.distractedFraction, closeTo(0.5, 1e-9));
  });

  test('does not count time when recording is disabled', () {
    final record = DrivingRecord(enabled: false);
    record.update(state: DriverState.attentive, at: t0, isDriving: true);
    record.update(
      state: DriverState.attentive,
      at: t0.add(const Duration(seconds: 1)),
      isDriving: true,
    );

    expect(record.totalDuration, Duration.zero);
  });

  test('does not count time when not driving', () {
    final record = DrivingRecord(enabled: true);
    record.update(state: DriverState.attentive, at: t0, isDriving: false);
    record.update(
      state: DriverState.attentive,
      at: t0.add(const Duration(seconds: 1)),
      isDriving: false,
    );

    expect(record.totalDuration, Duration.zero);
  });

  test('drops a gap longer than the max sample interval', () {
    final record = DrivingRecord(enabled: true);
    record.update(state: DriverState.attentive, at: t0, isDriving: true);
    // 5s later (e.g. app was backgrounded), too long to attribute.
    record.update(
      state: DriverState.attentive,
      at: t0.add(const Duration(seconds: 5)),
      isDriving: true,
    );

    expect(record.totalDuration, Duration.zero);
  });

  test('face-not-visible / unknown frames are not counted', () {
    final record = DrivingRecord(enabled: true);
    record.update(state: DriverState.faceNotVisible, at: t0, isDriving: true);
    record.update(
      state: DriverState.unknown,
      at: t0.add(const Duration(milliseconds: 500)),
      isDriving: true,
    );
    record.update(
      state: DriverState.attentive,
      at: t0.add(const Duration(seconds: 1)),
      isDriving: true,
    );

    expect(record.totalDuration, Duration.zero);
  });

  test('toggling recording off then on does not bridge the gap', () {
    final record = DrivingRecord(enabled: true);
    record.update(state: DriverState.attentive, at: t0, isDriving: true);
    record.enabled = false;
    record.enabled = true;
    // First sample after re-enabling only re-seeds the interval.
    record.update(
      state: DriverState.attentive,
      at: t0.add(const Duration(milliseconds: 600)),
      isDriving: true,
    );
    record.update(
      state: DriverState.attentive,
      at: t0.add(const Duration(milliseconds: 1100)),
      isDriving: true,
    );

    expect(record.attentiveDuration, const Duration(milliseconds: 500));
  });

  test('restore seeds totals from persisted values', () {
    final record = DrivingRecord()
      ..restore(
        distracted: const Duration(minutes: 2),
        attentive: const Duration(minutes: 8),
      );

    expect(record.totalDuration, const Duration(minutes: 10));
    expect(record.distractedFraction, closeTo(0.2, 1e-9));
  });

  test('restore preserves updates and setting change made while loading', () {
    final record = DrivingRecord(enabled: false)
      ..enabled = true
      ..update(state: DriverState.attentive, at: t0, isDriving: true)
      ..update(
        state: DriverState.attentive,
        at: t0.add(const Duration(seconds: 1)),
        isDriving: true,
      )
      ..restore(
        distracted: const Duration(minutes: 2),
        attentive: const Duration(minutes: 8),
        enabled: false,
      );

    expect(record.enabled, isTrue);
    expect(record.attentiveDuration, const Duration(minutes: 8, seconds: 1));
    expect(record.distractedDuration, const Duration(minutes: 2));
  });

  test('does not treat unobserved phone-use time as driving time', () {
    final record = DrivingRecord(enabled: true)
      ..recordPhoneUse(const Duration(seconds: 12));

    expect(record.distractedDuration, Duration.zero);
    expect(record.attentiveDuration, Duration.zero);
  });

  test('clear wipes the totals', () {
    final record = DrivingRecord(enabled: true);
    record.update(state: DriverState.attentive, at: t0, isDriving: true);
    record.update(
      state: DriverState.attentive,
      at: t0.add(const Duration(seconds: 1)),
      isDriving: true,
    );
    expect(record.totalDuration, greaterThan(Duration.zero));

    record.clear();

    expect(record.totalDuration, Duration.zero);
    expect(record.distractedFraction, 0);
  });
}
