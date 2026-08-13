import 'package:shared_preferences/shared_preferences.dart';

class AutomaticDrivingModeStore {
  static const _enabledKey = 'automatic_driving_mode_enabled';

  Future<bool> load() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_enabledKey) ?? true;
  }

  Future<void> save(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, enabled);
  }
}
