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
  Future<void> warn(DriverState state) async {
    warnings.add(state);
  }
}

void main() {
  final t0 = DateTime(2026, 1, 1, 12);

  FaceObservation observation({
    required DateTime at,
    double yaw = 0,
    double pitch = 0,
    double roll = 0,
  }) {
    return FaceObservation(
      timestamp: at,
      faceVisible: true,
      headYawDegrees: yaw,
      headPitchDegrees: pitch,
      headRollDegrees: roll,
      leftEyeOpenProbability: 0.9,
      rightEyeOpenProbability: 0.9,
    );
  }

  DriveSessionController controller(_RecordingAlertService alerts) {
    return DriveSessionController(
      analyzer: const DistractionAnalyzer(),
      alertService: alerts,
      sensitivity: GlanceSensitivity.lenient,
    );
  }

  group('glances while moving', () {
    test('a brief look away is a glance and never alerts', () async {
      final alerts = _RecordingAlertService();
      final c = controller(alerts);

      final first = await c.processObservation(
        observation(at: t0, yaw: -40),
        isDriving: true,
      );
      final second = await c.processObservation(
        observation(at: t0.add(const Duration(seconds: 2)), yaw: -40),
        isDriving: true,
      );

      expect(first, DriverState.glancingAway);
      expect(second, DriverState.glancingAway);
      expect(alerts.warnings, isEmpty);
    });

    test('any direction counts, not just a known mirror', () async {
      final alerts = _RecordingAlertService();
      final c = controller(alerts);

      // Opposite side, no calibration of any kind, still just a glance.
      final state = await c.processObservation(
        observation(at: t0, yaw: 45),
        isDriving: true,
      );
      expect(state, DriverState.glancingAway);
    });

    test('a look held past the limit becomes looking away and alerts',
        () async {
      final alerts = _RecordingAlertService();
      final c = controller(alerts);

      await c.processObservation(
        observation(at: t0, yaw: -40),
        isDriving: true,
      );
      final held = await c.processObservation(
        observation(at: t0.add(const Duration(milliseconds: 3400)), yaw: -40),
        isDriving: true,
      );
      final later = await c.processObservation(
        observation(at: t0.add(const Duration(seconds: 6)), yaw: -40),
        isDriving: true,
      );

      expect(held, DriverState.lookingAway);
      expect(later, DriverState.lookingAway);
      expect(alerts.warnings, contains(DriverState.lookingAway));
    });

    test('returning to the road resets the glance clock', () async {
      final alerts = _RecordingAlertService();
      final c = controller(alerts);

      await c.processObservation(
        observation(at: t0, yaw: -40),
        isDriving: true,
      );
      await c.processObservation(
        observation(at: t0.add(const Duration(seconds: 2))),
        isDriving: true,
      );
      final again = await c.processObservation(
        observation(at: t0.add(const Duration(seconds: 4)), yaw: -40),
        isDriving: true,
      );

      expect(again, DriverState.glancingAway);
      expect(alerts.warnings, isEmpty);
    });
  });

  group('while stopped', () {
    test('turning to look around is not flagged at all', () async {
      final alerts = _RecordingAlertService();
      final c = controller(alerts);

      // Well past the glance limit, but the car is not moving.
      await c.processObservation(
        observation(at: t0, yaw: 60),
        isDriving: true,
        isVehicleMoving: false,
      );
      final later = await c.processObservation(
        observation(at: t0.add(const Duration(seconds: 10)), yaw: 60),
        isDriving: true,
        isVehicleMoving: false,
      );

      expect(later, DriverState.attentive);
      expect(alerts.warnings, isEmpty);
    });

    test('looking sharply down is still flagged when stopped', () async {
      final alerts = _RecordingAlertService();
      final c = controller(alerts);

      final state = await c.processObservation(
        observation(at: t0, pitch: -30),
        isDriving: true,
        isVehicleMoving: false,
      );
      expect(state, DriverState.glancingAway);
    });

    test('an extreme sideways slump is still flagged when stopped', () async {
      final alerts = _RecordingAlertService();
      final c = controller(alerts);

      final state = await c.processObservation(
        observation(at: t0, roll: 35),
        isDriving: true,
        isVehicleMoving: false,
      );
      expect(state, DriverState.glancingAway);
    });

    test('a sustained downward look still escalates when stopped', () async {
      final alerts = _RecordingAlertService();
      final c = controller(alerts);

      await c.processObservation(
        observation(at: t0, pitch: -30),
        isDriving: true,
        isVehicleMoving: false,
      );
      final held = await c.processObservation(
        observation(at: t0.add(const Duration(seconds: 4)), pitch: -30),
        isDriving: true,
        isVehicleMoving: false,
      );

      expect(held, DriverState.lookingAway);
    });
  });
}
