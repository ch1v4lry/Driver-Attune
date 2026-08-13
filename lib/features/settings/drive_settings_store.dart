import 'package:shared_preferences/shared_preferences.dart';

import '../distraction_detection/glance_sensitivity.dart';
import '../motion/gps_accuracy.dart';

class StoredDriveSettings {
  const StoredDriveSettings({
    required this.yawnEnabled,
    required this.drowsinessAlarmEnabled,
    required this.evidencePhotosEnabled,
    required this.evidenceAutoDeleteEnabled,
    required this.sensitivity,
    required this.gpsAccuracy,
  });

  final bool yawnEnabled;
  final bool drowsinessAlarmEnabled;
  final bool evidencePhotosEnabled;
  final bool evidenceAutoDeleteEnabled;
  final GlanceSensitivity sensitivity;
  final GpsAccuracyMode gpsAccuracy;
}

/// Persists Drive settings that are not owned by another feature store.
class DriveSettingsStore {
  static const _yawnEnabledKey = 'drive_settings.yawn_enabled';
  static const _drowsinessAlarmEnabledKey =
      'drive_settings.drowsiness_alarm_enabled';
  static const _evidencePhotosEnabledKey =
      'drive_settings.evidence_photos_enabled';
  static const _evidenceAutoDeleteEnabledKey =
      'drive_settings.evidence_auto_delete_enabled';
  static const _sensitivityKey = 'drive_settings.glance_sensitivity';
  static const _gpsAccuracyKey = 'drive_settings.gps_accuracy';

  Future<StoredDriveSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    return StoredDriveSettings(
      yawnEnabled: preferences.getBool(_yawnEnabledKey) ?? true,
      drowsinessAlarmEnabled:
          preferences.getBool(_drowsinessAlarmEnabledKey) ?? true,
      evidencePhotosEnabled:
          preferences.getBool(_evidencePhotosEnabledKey) ?? false,
      evidenceAutoDeleteEnabled:
          preferences.getBool(_evidenceAutoDeleteEnabledKey) ?? false,
      sensitivity: _enumValue(
        GlanceSensitivity.values,
        preferences.getString(_sensitivityKey),
        GlanceSensitivity.lenient,
      ),
      gpsAccuracy: _enumValue(
        GpsAccuracyMode.values,
        preferences.getString(_gpsAccuracyKey),
        GpsAccuracyMode.balanced,
      ),
    );
  }

  Future<void> saveYawnEnabled(bool value) => _saveBool(_yawnEnabledKey, value);

  Future<void> saveDrowsinessAlarmEnabled(bool value) =>
      _saveBool(_drowsinessAlarmEnabledKey, value);

  Future<void> saveEvidencePhotosEnabled(bool value) =>
      _saveBool(_evidencePhotosEnabledKey, value);

  Future<void> saveEvidenceAutoDeleteEnabled(bool value) =>
      _saveBool(_evidenceAutoDeleteEnabledKey, value);

  Future<void> saveSensitivity(GlanceSensitivity value) =>
      _saveString(_sensitivityKey, value.name);

  Future<void> saveGpsAccuracy(GpsAccuracyMode value) =>
      _saveString(_gpsAccuracyKey, value.name);

  Future<void> _saveBool(String key, bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(key, value);
  }

  Future<void> _saveString(String key, String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(key, value);
  }

  static T _enumValue<T extends Enum>(
    List<T> values,
    String? saved,
    T fallback,
  ) {
    for (final value in values) {
      if (value.name == saved) {
        return value;
      }
    }
    return fallback;
  }
}
