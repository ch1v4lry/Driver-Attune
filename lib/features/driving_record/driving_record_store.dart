import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'driving_session_summary.dart';

/// Persists the driving-record totals and toggle to on-device storage. Nothing
/// here leaves the phone, it is a thin wrapper over shared_preferences.
class DrivingRecordStore {
  static const _distractedKey = 'driving_record.distracted_ms';
  static const _attentiveKey = 'driving_record.attentive_ms';
  static const _enabledKey = 'driving_record.enabled';
  static const _sessionsKey = 'driving_record.sessions';

  Future<
      ({
        Duration distracted,
        Duration attentive,
        bool enabled,
        List<DrivingSessionSummary> sessions,
      })> load() async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = <DrivingSessionSummary>[];
    final encodedSessions = prefs.getString(_sessionsKey);
    if (encodedSessions != null) {
      try {
        final decoded = jsonDecode(encodedSessions);
        if (decoded is List) {
          sessions.addAll(
            decoded
                .map(DrivingSessionSummary.fromJson)
                .whereType<DrivingSessionSummary>(),
          );
        }
      } on FormatException {
        // A malformed history must not prevent lifetime totals from loading.
      }
    }
    return (
      distracted: Duration(milliseconds: prefs.getInt(_distractedKey) ?? 0),
      attentive: Duration(milliseconds: prefs.getInt(_attentiveKey) ?? 0),
      enabled: prefs.getBool(_enabledKey) ?? true,
      sessions: sessions,
    );
  }

  Future<void> save({
    required Duration distracted,
    required Duration attentive,
    required bool enabled,
    required List<DrivingSessionSummary> sessions,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_distractedKey, distracted.inMilliseconds);
    await prefs.setInt(_attentiveKey, attentive.inMilliseconds);
    await prefs.setBool(_enabledKey, enabled);
    await prefs.setString(
      _sessionsKey,
      jsonEncode(sessions.map((session) => session.toJson()).toList()),
    );
  }
}
