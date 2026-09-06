import 'package:driver_attune/features/driving_record/driving_session_summary.dart';
import 'package:driver_attune/features/driving_record/seven_day_driving_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 7, 30, 12);

  DrivingSessionSummary session({
    required DateTime startedAt,
    int movingMinutes = 20,
    int reliableMinutes = 18,
    int attentiveMinutes = 15,
    int reminders = 0,
    int drowsiness = 0,
    int phoneUseSeconds = 0,
  }) {
    return DrivingSessionSummary(
      startedAt: startedAt,
      endedAt: startedAt.add(Duration(minutes: movingMinutes)),
      movingDuration: Duration(minutes: movingMinutes),
      reliableObservationDuration: Duration(minutes: reliableMinutes),
      attentiveDuration: Duration(minutes: attentiveMinutes),
      lookingAwayDuration:
          Duration(minutes: reliableMinutes - attentiveMinutes),
      drowsinessEventCount: drowsiness,
      attentionReminderCount: reminders,
      possiblePhoneUseDuration: Duration(seconds: phoneUseSeconds),
      faceNotVisibleDuration:
          Duration(minutes: movingMinutes - reliableMinutes),
      lowQualityDuration: Duration.zero,
    );
  }

  test('aggregates the current seven calendar days', () {
    final report = SevenDayDrivingReport.build(
      [
        session(
          startedAt: DateTime(2026, 7, 25, 8),
          reminders: 2,
          drowsiness: 1,
          phoneUseSeconds: 30,
        ),
        session(
          startedAt: DateTime(2026, 7, 29, 8),
          attentiveMinutes: 14,
          reminders: 1,
          phoneUseSeconds: 15,
        ),
        // Outside both report periods.
        session(startedAt: DateTime(2026, 7, 10, 8)),
      ],
      now: now,
    );

    expect(report.periodStart, DateTime(2026, 7, 24));
    expect(report.sessionCount, 2);
    expect(report.drivingDayCount, 2);
    expect(report.movingDuration, const Duration(minutes: 40));
    expect(
      report.reliableObservationDuration,
      const Duration(minutes: 36),
    );
    expect(report.attentiveDuration, const Duration(minutes: 29));
    expect(report.reliableCoverage, closeTo(0.9, 0.0001));
    expect(report.attentionReminderCount, 3);
    expect(report.drowsinessEventCount, 1);
    expect(report.possiblePhoneUseDuration, const Duration(seconds: 45));
  });

  test('compares attention with the preceding seven days', () {
    final report = SevenDayDrivingReport.build(
      [
        session(
          startedAt: DateTime(2026, 7, 25, 8),
          attentiveMinutes: 16,
        ),
        session(
          startedAt: DateTime(2026, 7, 29, 8),
          attentiveMinutes: 15,
        ),
        session(
          startedAt: DateTime(2026, 7, 20, 8),
          attentiveMinutes: 12,
        ),
      ],
      now: now,
    );

    expect(report.attentionTrend, AttentionTrend.improving);
    expect(report.attentionTrendChange, closeTo(31 / 36 - 12 / 18, 0.0001));
    expect(report.dailyConsistency, DailyConsistency.somewhatVariable);
    expect(report.qualifiedDrivingDayCount, 2);
    expect(report.dailyAttentionSpread, closeTo(1 / 18, 0.0001));
  });

  test('withholds trends and consistency when evidence is insufficient', () {
    final report = SevenDayDrivingReport.build(
      [
        session(
          startedAt: DateTime(2026, 7, 30, 8),
          movingMinutes: 5,
          reliableMinutes: 3,
          attentiveMinutes: 3,
        ),
      ],
      now: now,
    );

    expect(report.estimatedAttentiveFraction, isNull);
    expect(report.attentionTrend, AttentionTrend.insufficientData);
    expect(report.attentionTrendChange, isNull);
    expect(report.dailyConsistency, DailyConsistency.insufficientData);
  });
}
