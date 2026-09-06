import 'package:driver_attune/features/alerts/alert_service.dart';
import 'package:driver_attune/features/distraction_detection/distraction_analyzer.dart';
import 'package:driver_attune/features/distraction_detection/driver_state.dart';
import 'package:driver_attune/features/distraction_detection/face_observation.dart';
import 'package:driver_attune/features/distraction_detection/glance_sensitivity.dart';
import 'package:driver_attune/features/drive_session/drive_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingAlertService implements AlertService {
  final List<DriverState> warnings = [];

  @override
  Future<void> warn(DriverState state) async => warnings.add(state);
}

void main() {
  final t0 = DateTime(2026, 1, 1, 12);

  FaceObservation obs(
    DateTime at, {
    double yaw = 0,
    double pitch = 0,
    double eye = 0.9,
  }) {
    return FaceObservation(
      timestamp: at,
      faceVisible: true,
      headYawDegrees: yaw,
      headPitchDegrees: pitch,
      headRollDegrees: 0,
      leftEyeOpenProbability: eye,
      rightEyeOpenProbability: eye,
    );
  }

  DriveSessionController controller(_RecordingAlertService alerts) {
    return DriveSessionController(
      analyzer: const DistractionAnalyzer(),
      alertService: alerts,
      sensitivity: GlanceSensitivity.lenient,
    )..yawnDetectionEnabled = false;
  }

  test('a blink while looking away does not read as attentive', () async {
    final alerts = _RecordingAlertService();
    final c = controller(alerts);

    await c.processObservation(obs(t0, yaw: 30), isDriving: true);
    // Eye closure is judged before pose, so this frame comes back as
    // eyesClosed. The blink filter must fall back to the pose, not to
    // attentive.
    final blink = await c.processObservation(
      obs(t0.add(const Duration(milliseconds: 200)), yaw: 30, eye: 0.05),
      isDriving: true,
    );

    expect(blink, DriverState.glancingAway);
  });

  test('blinking cannot hold off the looking-away escalation', () async {
    final alerts = _RecordingAlertService();
    final c = controller(alerts);

    // Look away and blink repeatedly throughout. Each blink used to reset the
    // glance timer, so the driver could look away indefinitely without
    // alerting.
    var at = t0;
    DriverState? last;
    // Long enough to clear the 2.5s glance limit and then the 2s alert debounce
    // that follows it.
    for (var i = 0; i < 20; i++) {
      final blinking = i.isOdd;
      last = await c.processObservation(
        obs(at, yaw: 30, eye: blinking ? 0.05 : 0.9),
        isDriving: true,
      );
      at = at.add(const Duration(milliseconds: 300));
    }

    expect(last, DriverState.lookingAway);
    expect(alerts.warnings, contains(DriverState.lookingAway));
  });

  test('a blink while facing the road is still attentive', () async {
    final alerts = _RecordingAlertService();
    final c = controller(alerts);

    await c.processObservation(obs(t0), isDriving: true);
    final blink = await c.processObservation(
      obs(t0.add(const Duration(milliseconds: 200)), eye: 0.05),
      isDriving: true,
    );

    expect(blink, DriverState.attentive);
  });

  test('a sustained closure is still eyes closed, not downgraded', () async {
    final alerts = _RecordingAlertService();
    final c = controller(alerts);

    await c.processObservation(obs(t0, eye: 0.05), isDriving: true);
    final held = await c.processObservation(
      obs(t0.add(const Duration(milliseconds: 900)), eye: 0.05),
      isDriving: true,
    );

    expect(held, DriverState.eyesClosed);
  });

  test('poseState ignores the eyes entirely', () {
    const a = DistractionAnalyzer();
    // Eyes shut but facing forward: pose alone says attentive.
    expect(a.poseState(obs(t0, eye: 0.05)), DriverState.attentive);
    // Eyes shut and head turned: pose alone says glancing away.
    expect(a.poseState(obs(t0, yaw: 30, eye: 0.05)), DriverState.glancingAway);
    // Stopped, so yaw is not judged.
    expect(
      a.poseState(obs(t0, yaw: 30, eye: 0.05), isVehicleMoving: false),
      DriverState.attentive,
    );
  });
}
