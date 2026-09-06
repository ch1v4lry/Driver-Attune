import 'package:driver_attune/features/distraction_detection/glance_sensitivity.dart';
import 'package:driver_attune/features/motion/automatic_driving_mode_store.dart';
import 'package:driver_attune/features/motion/gps_accuracy.dart';
import 'package:driver_attune/features/settings/drive_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('named safety and record-related settings default to enabled', () async {
    SharedPreferences.setMockInitialValues({});

    final driveSettings = await DriveSettingsStore().load();
    final automaticDrivingMode = await AutomaticDrivingModeStore().load();

    expect(automaticDrivingMode, isTrue);
    expect(driveSettings.drowsinessAlarmEnabled, isTrue);
    expect(driveSettings.evidencePhotosEnabled, isFalse);
    expect(driveSettings.yawnEnabled, isTrue);
    expect(driveSettings.evidenceAutoDeleteEnabled, isFalse);
    expect(driveSettings.sensitivity, GlanceSensitivity.lenient);
    expect(driveSettings.gpsAccuracy, GpsAccuracyMode.balanced);
  });

  test('all Drive settings persist user selections', () async {
    SharedPreferences.setMockInitialValues({});
    final store = DriveSettingsStore();

    await store.saveYawnEnabled(false);
    await store.saveDrowsinessAlarmEnabled(false);
    await store.saveEvidencePhotosEnabled(false);
    await store.saveEvidenceAutoDeleteEnabled(true);
    await store.saveSensitivity(GlanceSensitivity.safest);
    await store.saveGpsAccuracy(GpsAccuracyMode.batterySaver);

    final loaded = await store.load();
    expect(loaded.yawnEnabled, isFalse);
    expect(loaded.drowsinessAlarmEnabled, isFalse);
    expect(loaded.evidencePhotosEnabled, isFalse);
    expect(loaded.evidenceAutoDeleteEnabled, isTrue);
    expect(loaded.sensitivity, GlanceSensitivity.safest);
    expect(loaded.gpsAccuracy, GpsAccuracyMode.batterySaver);
  });

  test('automatic Driving mode persists an explicit opt-out', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AutomaticDrivingModeStore();

    await store.save(false);

    expect(await store.load(), isFalse);
  });
}
