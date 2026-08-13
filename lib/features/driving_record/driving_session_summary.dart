class DrivingSessionSummary {
  const DrivingSessionSummary({
    required this.startedAt,
    required this.endedAt,
    required this.movingDuration,
    required this.reliableObservationDuration,
    required this.attentiveDuration,
    required this.lookingAwayDuration,
    required this.drowsinessEventCount,
    required this.attentionReminderCount,
    required this.possiblePhoneUseDuration,
    required this.faceNotVisibleDuration,
    required this.lowQualityDuration,
  });

  final DateTime startedAt;
  final DateTime endedAt;

  /// Confirmed moving time. Stops remain part of the session but add no time.
  final Duration movingDuration;

  /// Moving time for which the face signal and mount quality were usable.
  final Duration reliableObservationDuration;
  final Duration attentiveDuration;
  final Duration lookingAwayDuration;
  final int drowsinessEventCount;
  final int attentionReminderCount;
  final Duration possiblePhoneUseDuration;
  final Duration faceNotVisibleDuration;
  final Duration lowQualityDuration;

  double get reliableCoverage {
    final total = movingDuration.inMilliseconds;
    if (total == 0) {
      return 0;
    }
    return reliableObservationDuration.inMilliseconds / total;
  }

  double? get estimatedAttentiveFraction {
    final reliable = reliableObservationDuration.inMilliseconds;
    if (reliable == 0) {
      return null;
    }
    return attentiveDuration.inMilliseconds / reliable;
  }

  Map<String, Object> toJson() => {
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'movingMs': movingDuration.inMilliseconds,
        'reliableMs': reliableObservationDuration.inMilliseconds,
        'attentiveMs': attentiveDuration.inMilliseconds,
        'lookingAwayMs': lookingAwayDuration.inMilliseconds,
        'drowsinessEvents': drowsinessEventCount,
        'attentionReminders': attentionReminderCount,
        'possiblePhoneUseMs': possiblePhoneUseDuration.inMilliseconds,
        'faceNotVisibleMs': faceNotVisibleDuration.inMilliseconds,
        'lowQualityMs': lowQualityDuration.inMilliseconds,
      };

  static DrivingSessionSummary? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }
    final startedAt = DateTime.tryParse(value['startedAt'] as String? ?? '');
    final endedAt = DateTime.tryParse(value['endedAt'] as String? ?? '');
    if (startedAt == null || endedAt == null) {
      return null;
    }

    int readInt(String key) => (value[key] as num?)?.toInt() ?? 0;

    return DrivingSessionSummary(
      startedAt: startedAt,
      endedAt: endedAt,
      movingDuration: Duration(milliseconds: readInt('movingMs')),
      reliableObservationDuration:
          Duration(milliseconds: readInt('reliableMs')),
      attentiveDuration: Duration(milliseconds: readInt('attentiveMs')),
      lookingAwayDuration: Duration(milliseconds: readInt('lookingAwayMs')),
      drowsinessEventCount: readInt('drowsinessEvents'),
      attentionReminderCount: readInt('attentionReminders'),
      possiblePhoneUseDuration:
          Duration(milliseconds: readInt('possiblePhoneUseMs')),
      faceNotVisibleDuration:
          Duration(milliseconds: readInt('faceNotVisibleMs')),
      lowQualityDuration: Duration(milliseconds: readInt('lowQualityMs')),
    );
  }
}
