import 'driving_session_summary.dart';

enum AttentionTrend { improving, steady, declining, insufficientData }

enum DailyConsistency {
  consistent,
  somewhatVariable,
  variable,
  insufficientData
}

class SevenDayDrivingReport {
  const SevenDayDrivingReport({
    required this.periodStart,
    required this.periodEnd,
    required this.sessionCount,
    required this.drivingDayCount,
    required this.movingDuration,
    required this.reliableObservationDuration,
    required this.attentiveDuration,
    required this.attentionReminderCount,
    required this.drowsinessEventCount,
    required this.possiblePhoneUseDuration,
    required this.attentionTrend,
    required this.attentionTrendChange,
    required this.dailyConsistency,
    required this.dailyAttentionSpread,
    required this.qualifiedDrivingDayCount,
  });

  static const double minimumReliableCoverage = 0.7;
  static const Duration minimumTrendMovingDuration = Duration(minutes: 10);
  static const double steadyTrendThreshold = 0.03;
  static const double consistentDailySpread = 0.05;
  static const double somewhatVariableDailySpread = 0.15;

  final DateTime periodStart;
  final DateTime periodEnd;
  final int sessionCount;
  final int drivingDayCount;
  final Duration movingDuration;
  final Duration reliableObservationDuration;
  final Duration attentiveDuration;
  final int attentionReminderCount;
  final int drowsinessEventCount;
  final Duration possiblePhoneUseDuration;
  final AttentionTrend attentionTrend;

  /// Current-period attentive fraction minus the preceding period's fraction.
  final double? attentionTrendChange;
  final DailyConsistency dailyConsistency;

  /// Highest qualified daily attentive fraction minus the lowest.
  final double? dailyAttentionSpread;
  final int qualifiedDrivingDayCount;

  double get reliableCoverage => _fraction(
        reliableObservationDuration,
        movingDuration,
      );

  double? get estimatedAttentiveFraction {
    if (movingDuration < minimumTrendMovingDuration ||
        reliableCoverage < minimumReliableCoverage ||
        reliableObservationDuration == Duration.zero) {
      return null;
    }
    return _fraction(attentiveDuration, reliableObservationDuration);
  }

  static SevenDayDrivingReport build(
    Iterable<DrivingSessionSummary> sessions, {
    DateTime? now,
  }) {
    final localNow = (now ?? DateTime.now()).toLocal();
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    final currentStart = today.subtract(const Duration(days: 6));
    final currentEnd = today.add(const Duration(days: 1));
    final previousStart = currentStart.subtract(const Duration(days: 7));

    final current = _PeriodAggregate.fromSessions(
      sessions,
      start: currentStart,
      end: currentEnd,
    );
    final previous = _PeriodAggregate.fromSessions(
      sessions,
      start: previousStart,
      end: currentStart,
    );

    final currentAttention = current.qualifiedAttentionFraction;
    final previousAttention = previous.qualifiedAttentionFraction;
    final change = currentAttention != null && previousAttention != null
        ? currentAttention - previousAttention
        : null;
    final trend = switch (change) {
      null => AttentionTrend.insufficientData,
      > steadyTrendThreshold => AttentionTrend.improving,
      < -steadyTrendThreshold => AttentionTrend.declining,
      _ => AttentionTrend.steady,
    };

    final dailyFractions = current.daily.values
        .map((day) => day.qualifiedAttentionFraction)
        .whereType<double>()
        .toList();
    double? spread;
    DailyConsistency consistency;
    if (dailyFractions.length < 2) {
      consistency = DailyConsistency.insufficientData;
    } else {
      dailyFractions.sort();
      spread = dailyFractions.last - dailyFractions.first;
      consistency = spread <= consistentDailySpread
          ? DailyConsistency.consistent
          : spread <= somewhatVariableDailySpread
              ? DailyConsistency.somewhatVariable
              : DailyConsistency.variable;
    }

    return SevenDayDrivingReport(
      periodStart: currentStart,
      periodEnd: currentEnd,
      sessionCount: current.sessionCount,
      drivingDayCount: current.daily.length,
      movingDuration: current.moving,
      reliableObservationDuration: current.reliable,
      attentiveDuration: current.attentive,
      attentionReminderCount: current.reminders,
      drowsinessEventCount: current.drowsiness,
      possiblePhoneUseDuration: current.phoneUse,
      attentionTrend: trend,
      attentionTrendChange: change,
      dailyConsistency: consistency,
      dailyAttentionSpread: spread,
      qualifiedDrivingDayCount: dailyFractions.length,
    );
  }

  static double _fraction(Duration numerator, Duration denominator) {
    final total = denominator.inMilliseconds;
    return total == 0 ? 0 : numerator.inMilliseconds / total;
  }
}

class _PeriodAggregate {
  _PeriodAggregate();

  int sessionCount = 0;
  Duration moving = Duration.zero;
  Duration reliable = Duration.zero;
  Duration attentive = Duration.zero;
  int reminders = 0;
  int drowsiness = 0;
  Duration phoneUse = Duration.zero;
  final Map<DateTime, _DayAggregate> daily = {};

  double? get qualifiedAttentionFraction {
    if (moving < SevenDayDrivingReport.minimumTrendMovingDuration ||
        _coverage(reliable, moving) <
            SevenDayDrivingReport.minimumReliableCoverage ||
        reliable == Duration.zero) {
      return null;
    }
    return attentive.inMilliseconds / reliable.inMilliseconds;
  }

  static _PeriodAggregate fromSessions(
    Iterable<DrivingSessionSummary> sessions, {
    required DateTime start,
    required DateTime end,
  }) {
    final aggregate = _PeriodAggregate();
    for (final session in sessions) {
      final localStart = session.startedAt.toLocal();
      if (localStart.isBefore(start) || !localStart.isBefore(end)) {
        continue;
      }
      aggregate.sessionCount++;
      aggregate.moving += session.movingDuration;
      aggregate.reliable += session.reliableObservationDuration;
      aggregate.attentive += session.attentiveDuration;
      aggregate.reminders += session.attentionReminderCount;
      aggregate.drowsiness += session.drowsinessEventCount;
      aggregate.phoneUse += session.possiblePhoneUseDuration;
      final day = DateTime(localStart.year, localStart.month, localStart.day);
      aggregate.daily.putIfAbsent(day, _DayAggregate.new).add(session);
    }
    return aggregate;
  }
}

class _DayAggregate {
  Duration moving = Duration.zero;
  Duration reliable = Duration.zero;
  Duration attentive = Duration.zero;

  void add(DrivingSessionSummary session) {
    moving += session.movingDuration;
    reliable += session.reliableObservationDuration;
    attentive += session.attentiveDuration;
  }

  double? get qualifiedAttentionFraction {
    if (moving < SevenDayDrivingReport.minimumTrendMovingDuration ||
        _coverage(reliable, moving) <
            SevenDayDrivingReport.minimumReliableCoverage ||
        reliable == Duration.zero) {
      return null;
    }
    return attentive.inMilliseconds / reliable.inMilliseconds;
  }
}

double _coverage(Duration reliable, Duration moving) {
  final total = moving.inMilliseconds;
  return total == 0 ? 0 : reliable.inMilliseconds / total;
}
