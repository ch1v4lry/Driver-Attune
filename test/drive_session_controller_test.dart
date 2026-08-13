import 'package:driver_focus/features/alerts/alert_service.dart';
import 'package:driver_focus/features/distraction_detection/distraction_analyzer.dart';
import 'package:driver_focus/features/distraction_detection/driver_state.dart';
import 'package:driver_focus/features/distraction_detection/face_observation.dart';
import 'package:driver_focus/features/distraction_detection/yawn_tracker.dart';
import 'package:driver_focus/features/drive_session/drive_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingAlertService implements AlertService {
  final List<DriverState> warnings = [];

  @override
  Future<void> warn(DriverState state) async {
    warnings.add(state);
  }
}

void main() {
  final now = DateTime(2026, 1, 1);

  FaceObservation observation({double yaw = 0}) {
    return FaceObservation(
      timestamp: now,
      faceVisible: true,
      headYawDegrees: yaw,
      headPitchDegrees: 0,
      leftEyeOpenProbability: 0.9,
      rightEyeOpenProbability: 0.9,
    );
  }

  test('phone interaction while driving flags using phone and alerts',
      () async {
    final alerts = _RecordingAlertService();
    final controller = DriveSessionController(
      analyzer: const DistractionAnalyzer(),
      alertService: alerts,
    );

    final state = await controller.registerPhoneInteraction(isDriving: true);

    expect(state, DriverState.usingPhone);
    expect(alerts.warnings, [DriverState.usingPhone]);
  });

  test('phone interaction while parked flags using phone but does not alert',
      () async {
    final alerts = _RecordingAlertService();
    final controller = DriveSessionController(
      analyzer: const DistractionAnalyzer(),
      alertService: alerts,
    );

    final state = await controller.registerPhoneInteraction(isDriving: false);

    expect(state, DriverState.usingPhone);
    expect(alerts.warnings, isEmpty);
  });

  test('calibration changes which head pose counts as attentive', () async {
    final controller = DriveSessionController(
      analyzer: const DistractionAnalyzer(),
      alertService: _RecordingAlertService(),
    );

    // Before calibration, facing the camera is attentive.
    expect(
      await controller.processObservation(observation(yaw: 0),
          isDriving: false),
      DriverState.attentive,
    );

    // Calibrate so the road sits at a 25-degree mount offset.
    controller.calibrate(yawDegrees: 25, pitchDegrees: 0);

    // Facing the camera is now off-road, a glance, until it is held too long.
    expect(
      await controller.processObservation(observation(yaw: 0),
          isDriving: false),
      DriverState.glancingAway,
    );
    // ...and the calibrated road pose is attentive.
    expect(
      await controller.processObservation(observation(yaw: 25),
          isDriving: false),
      DriverState.attentive,
    );
  });

  test('escalates to drowsy after sustained eye closure (PERCLOS)', () async {
    final controller = DriveSessionController(
      analyzer: const DistractionAnalyzer(),
      alertService: _RecordingAlertService(),
    );

    var t = DateTime(2026, 1, 1);
    final states = <DriverState>[];
    for (var i = 0; i < 12; i++) {
      states.add(
        await controller.processObservation(
          FaceObservation(
            timestamp: t,
            faceVisible: true,
            headYawDegrees: 0,
            headPitchDegrees: 0,
            leftEyeOpenProbability: 0.1,
            rightEyeOpenProbability: 0.1,
          ),
          isDriving: false,
        ),
      );
      t = t.add(const Duration(milliseconds: 500));
    }

    // Drowsiness fires as a one-shot event (the window resets after), so assert
    // it was reached rather than that it's the final state.
    expect(states, contains(DriverState.drowsy));
  });

  test('confirms yawning only after the mouth stays open long enough',
      () async {
    final controller = DriveSessionController(
      analyzer: const DistractionAnalyzer(),
      alertService: _RecordingAlertService(),
      yawnTracker: YawnTracker(
        openThreshold: 0.3,
        minOpenDuration: const Duration(milliseconds: 1200),
      ),
    );

    var t = DateTime(2026, 1, 1);
    FaceObservation openMouth() => FaceObservation(
          timestamp: t,
          faceVisible: true,
          headYawDegrees: 0,
          headPitchDegrees: 0,
          leftEyeOpenProbability: 0.9,
          rightEyeOpenProbability: 0.9,
          mouthOpenRatio: 0.4,
        );

    // Mouth just opened, not a yawn yet.
    expect(
      await controller.processObservation(openMouth(), isDriving: false),
      DriverState.attentive,
    );

    // Still open past the minimum duration, now it's a yawn.
    t = t.add(const Duration(milliseconds: 1500));
    expect(
      await controller.processObservation(openMouth(), isDriving: false),
      DriverState.yawning,
    );
  });

  test('does not flag yawning when yawn detection is disabled', () async {
    final controller = DriveSessionController(
      analyzer: const DistractionAnalyzer(),
      alertService: _RecordingAlertService(),
      yawnTracker: YawnTracker(
        openThreshold: 0.3,
        minOpenDuration: const Duration(milliseconds: 1200),
      ),
    )..yawnDetectionEnabled = false;

    var t = DateTime(2026, 1, 1);
    FaceObservation openMouth() => FaceObservation(
          timestamp: t,
          faceVisible: true,
          headYawDegrees: 0,
          headPitchDegrees: 0,
          leftEyeOpenProbability: 0.9,
          rightEyeOpenProbability: 0.9,
          mouthOpenRatio: 0.4,
        );

    await controller.processObservation(openMouth(), isDriving: false);
    t = t.add(const Duration(milliseconds: 1500));
    expect(
      await controller.processObservation(openMouth(), isDriving: false),
      DriverState.attentive,
    );
  });

  test('filters a brief blink but reports a sustained eye closure', () async {
    final controller = DriveSessionController(
      analyzer: const DistractionAnalyzer(),
      alertService: _RecordingAlertService(),
    );

    var t = DateTime(2026, 1, 1);
    FaceObservation eyes(double open) => FaceObservation(
          timestamp: t,
          faceVisible: true,
          headYawDegrees: 0,
          headPitchDegrees: 0,
          leftEyeOpenProbability: open,
          rightEyeOpenProbability: open,
        );

    // A single closed frame then open, a blink, never reads as eyes closed.
    expect(
      await controller.processObservation(eyes(0.1), isDriving: false),
      DriverState.attentive,
    );
    t = t.add(const Duration(milliseconds: 200));
    expect(
      await controller.processObservation(eyes(0.9), isDriving: false),
      DriverState.attentive,
    );

    // Eyes held shut across the min-closure window, now it's a real closure.
    t = t.add(const Duration(milliseconds: 200));
    expect(
      await controller.processObservation(eyes(0.1), isDriving: false),
      DriverState.attentive,
    );
    t = t.add(const Duration(milliseconds: 500));
    expect(
      await controller.processObservation(eyes(0.1), isDriving: false),
      DriverState.eyesClosed,
    );
  });

  test('calibration lowers the eye-closed threshold for narrower eyes',
      () async {
    final controller = DriveSessionController(
      analyzer: const DistractionAnalyzer(),
      alertService: _RecordingAlertService(),
    );

    var t = DateTime(2026, 1, 1);
    FaceObservation eyes(double open) => FaceObservation(
          timestamp: t,
          faceVisible: true,
          headYawDegrees: 0,
          headPitchDegrees: 0,
          leftEyeOpenProbability: open,
          rightEyeOpenProbability: open,
        );

    // Sustained 0.3 reads as closed at the default 0.35 threshold.
    await controller.processObservation(eyes(0.3), isDriving: false);
    t = t.add(const Duration(milliseconds: 600));
    expect(
      await controller.processObservation(eyes(0.3), isDriving: false),
      DriverState.eyesClosed,
    );

    // Calibrate with comfortably-open eyes at 0.6 -> threshold 0.24.
    controller.calibrate(
      yawDegrees: 0,
      pitchDegrees: 0,
      leftEyeOpen: 0.6,
      rightEyeOpen: 0.6,
    );

    // Now the same sustained 0.3 sits above the calibrated threshold ->
    // attentive.
    t = t.add(const Duration(milliseconds: 600));
    await controller.processObservation(eyes(0.3), isDriving: false);
    t = t.add(const Duration(milliseconds: 600));
    expect(
      await controller.processObservation(eyes(0.3), isDriving: false),
      DriverState.attentive,
    );
  });
}
