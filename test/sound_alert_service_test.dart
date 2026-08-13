import 'package:driver_focus/features/alerts/sound_alert_service.dart';
import 'package:driver_focus/features/distraction_detection/driver_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('alarm sounds only for drowsy, and only when enabled', () {
    expect(
      shouldSoundDrowsinessAlarm(state: DriverState.drowsy, enabled: true),
      isTrue,
    );
    expect(
      shouldSoundDrowsinessAlarm(state: DriverState.drowsy, enabled: false),
      isFalse,
    );
    expect(
      shouldSoundDrowsinessAlarm(state: DriverState.eyesClosed, enabled: true),
      isFalse,
    );
    expect(
      shouldSoundDrowsinessAlarm(state: DriverState.usingPhone, enabled: true),
      isFalse,
    );
  });
}
