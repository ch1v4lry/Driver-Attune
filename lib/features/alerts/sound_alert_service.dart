import 'package:audioplayers/audioplayers.dart';

import '../distraction_detection/driver_state.dart';
import 'alert_service.dart';

/// Whether a warning for [state] should sound the drowsiness alarm.
bool shouldSoundDrowsinessAlarm({
  required DriverState state,
  required bool enabled,
}) {
  return enabled && state == DriverState.drowsy;
}

/// Plays a loud ~3-second alarm when drowsiness is detected, if enabled.
class SoundAlertService implements AlertService {
  SoundAlertService({this.alarmCooldown = const Duration(seconds: 8)}) {
    // Route through the loud alarm channel and keep playing even when the phone
    // is on silent.
    _player.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {},
        ),
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
      ),
    );
  }

  /// Minimum gap between alarm sounds, so it doesn't re-blare during the
  /// driver's reaction/recovery window. Only re-fires if still drowsy after it.
  final Duration alarmCooldown;

  final AudioPlayer _player = AudioPlayer();

  /// Toggled from the Settings screen.
  bool drowsinessAlarmEnabled = true;

  DateTime? _lastAlarmAt;

  @override
  Future<void> warn(DriverState state) async {
    if (!shouldSoundDrowsinessAlarm(
      state: state,
      enabled: drowsinessAlarmEnabled,
    )) {
      return;
    }

    final now = DateTime.now();
    final last = _lastAlarmAt;
    if (last != null && now.difference(last) < alarmCooldown) {
      return;
    }
    _lastAlarmAt = now;
    await _player.play(AssetSource('sounds/alarm.wav'), volume: 1);
  }

  Future<void> dispose() => _player.dispose();
}
