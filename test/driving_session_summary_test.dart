import 'package:driver_attune/features/distraction_detection/driver_state.dart';
import 'package:driver_attune/features/driving_record/driving_record.dart';
import 'package:driver_attune/features/driving_record/driving_record_store.dart';
import 'package:driver_attune/features/driving_record/driving_session_summary.dart';
import 'package:driver_attune/features/mount_quality/mount_quality_monitor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final start = DateTime(2026, 7, 30, 8);

  test('builds one summary across a temporary stop', () {
    final record = DrivingRecord(enabled: true);

    record.update(
      state: DriverState.attentive,
      at: start,
      isDriving: true,
    );
    for (var second = 1; second <= 40; second++) {
      record.update(
        state: DriverState.attentive,
        at: start.add(Duration(seconds: second)),
        isDriving: true,
      );
    }

    // Count the final moving interval, then pause at a traffic light. The long
    // wall-clock stop must add no duration and must not split the session.
    record.update(
      state: DriverState.attentive,
      at: start.add(const Duration(seconds: 41)),
      isDriving: false,
    );
    record.update(
      state: DriverState.attentive,
      at: start.add(const Duration(seconds: 50)),
      isDriving: false,
    );

    record.update(
      state: DriverState.lookingAway,
      at: start.add(const Duration(seconds: 51)),
      isDriving: true,
    );
    for (var second = 52; second <= 71; second++) {
      record.update(
        state: DriverState.lookingAway,
        at: start.add(Duration(seconds: second)),
        isDriving: true,
      );
    }
    record.update(
      state: DriverState.drowsy,
      at: start.add(const Duration(seconds: 72)),
      isDriving: true,
    );
    record.update(
      state: DriverState.drowsy,
      at: start.add(const Duration(seconds: 73)),
      isDriving: true,
    );
    record.update(
      state: DriverState.faceNotVisible,
      at: start.add(const Duration(seconds: 74)),
      isDriving: true,
      quality: MountIssue.noFace,
    );
    record.update(
      state: DriverState.faceNotVisible,
      at: start.add(const Duration(seconds: 75)),
      isDriving: true,
      quality: MountIssue.noFace,
    );
    record.update(
      state: DriverState.faceNotVisible,
      at: start.add(const Duration(seconds: 76)),
      isDriving: true,
      quality: MountIssue.noFace,
    );

    record.endSession(at: start.add(const Duration(seconds: 77)));

    expect(record.sessions, hasLength(1));
    final session = record.latestSession!;
    expect(session.startedAt, start);
    expect(session.movingDuration, const Duration(seconds: 66));
    expect(
      session.reliableObservationDuration,
      const Duration(seconds: 64),
    );
    expect(session.attentiveDuration, const Duration(seconds: 41));
    expect(session.lookingAwayDuration, const Duration(seconds: 21));
    expect(session.faceNotVisibleDuration, const Duration(seconds: 2));
    expect(session.lowQualityDuration, Duration.zero);
    expect(session.attentionReminderCount, 1);
    expect(session.drowsinessEventCount, 1);
  });

  test('discards an accidental short session', () {
    final record = DrivingRecord(enabled: true);
    record.update(
      state: DriverState.attentive,
      at: start,
      isDriving: true,
    );
    record.update(
      state: DriverState.attentive,
      at: start.add(const Duration(seconds: 10)),
      isDriving: true,
    );
    record.endSession(at: start.add(const Duration(seconds: 11)));

    expect(record.sessions, isEmpty);
  });

  test('keeps background phone use separate from observed driving time', () {
    final record = DrivingRecord(enabled: true);
    record.update(
      state: DriverState.attentive,
      at: start,
      isDriving: true,
    );
    for (var second = 1; second <= 61; second++) {
      record.update(
        state: DriverState.attentive,
        at: start.add(Duration(seconds: second)),
        isDriving: true,
      );
    }

    record.recordPhoneUse(const Duration(seconds: 12));
    record.endSession(at: start.add(const Duration(seconds: 74)));

    final session = record.latestSession!;
    expect(session.movingDuration, const Duration(seconds: 61));
    expect(
      session.reliableObservationDuration,
      const Duration(seconds: 61),
    );
    expect(session.attentiveDuration, const Duration(seconds: 61));
    expect(session.possiblePhoneUseDuration, const Duration(seconds: 12));
    expect(record.attentiveDuration, const Duration(seconds: 61));
    expect(record.distractedDuration, Duration.zero);
  });

  test('persists and restores completed summaries', () async {
    SharedPreferences.setMockInitialValues({});
    final store = DrivingRecordStore();
    final summary = DrivingSessionSummary(
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 20)),
      movingDuration: const Duration(minutes: 18),
      reliableObservationDuration: const Duration(minutes: 16),
      attentiveDuration: const Duration(minutes: 15),
      lookingAwayDuration: const Duration(minutes: 1),
      drowsinessEventCount: 1,
      attentionReminderCount: 2,
      possiblePhoneUseDuration: const Duration(seconds: 5),
      faceNotVisibleDuration: const Duration(minutes: 1),
      lowQualityDuration: const Duration(minutes: 1),
    );

    await store.save(
      distracted: const Duration(minutes: 3),
      attentive: const Duration(minutes: 15),
      enabled: true,
      sessions: [summary],
    );
    final loaded = await store.load();

    expect(loaded.enabled, isTrue);
    expect(loaded.sessions, hasLength(1));
    expect(loaded.sessions.single.startedAt, start);
    expect(
      loaded.sessions.single.possiblePhoneUseDuration,
      const Duration(seconds: 5),
    );
    expect(loaded.sessions.single.attentionReminderCount, 2);
  });

  test('driving record defaults to enabled', () async {
    SharedPreferences.setMockInitialValues({});

    final loaded = await DrivingRecordStore().load();

    expect(DrivingRecord().enabled, isTrue);
    expect(loaded.enabled, isTrue);
  });
}
