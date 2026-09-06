import 'package:driver_attune/features/alerts/alert_service.dart';
import 'package:driver_attune/features/distraction_detection/distraction_analyzer.dart';
import 'package:driver_attune/features/distraction_detection/driver_state.dart';
import 'package:driver_attune/features/distraction_detection/drowsiness_tracker.dart';
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
    double pitch = 0,
    double leftEye = 0.9,
    double rightEye = 0.9,
  }) {
    return FaceObservation(
      timestamp: at,
      faceVisible: true,
      headYawDegrees: 0,
      headPitchDegrees: pitch,
      headRollDegrees: 0,
      leftEyeOpenProbability: leftEye,
      rightEyeOpenProbability: rightEye,
    );
  }

  /// A controller whose PERCLOS window is [alreadyDrowsy] or not.
  ///
  /// The window is seeded on the tracker directly rather than by feeding closed
  /// eyes through the controller: that route reaches "drowsy" on its own and
  /// resets the window, which would leave nothing for the head-drop rule to
  /// see.
  DriveSessionController controller(
    _RecordingAlertService alerts, {
    bool alreadyDrowsy = false,
  }) {
    final tracker = DrowsinessTracker();
    if (alreadyDrowsy) {
      var at = t0;
      for (var i = 0; i < 12; i++) {
        tracker.record(at: at, eyesClosed: true);
        at = at.add(const Duration(milliseconds: 250));
      }
    }
    return DriveSessionController(
      analyzer: const DistractionAnalyzer(),
      alertService: alerts,
      sensitivity: GlanceSensitivity.lenient,
      drowsinessTracker: tracker,
    )..yawnDetectionEnabled = false;
  }

  test('a sustained head-drop with drooping eyes reads as drowsy', () async {
    final alerts = _RecordingAlertService();
    final c = controller(alerts, alreadyDrowsy: true);

    // Head falls forward and stays there past the glance limit.
    var at = t0.add(const Duration(seconds: 4));
    await c.processObservation(obs(at, pitch: -30), isDriving: true);
    at = at.add(const Duration(seconds: 3));
    final state = await c.processObservation(
      obs(at, pitch: -30),
      isDriving: true,
    );

    expect(state, DriverState.drowsy);
    expect(alerts.warnings, contains(DriverState.drowsy));
  });

  test('a head-drop alone, with alert eyes, is only looking away', () async {
    final alerts = _RecordingAlertService();
    final c = controller(alerts);

    // Plenty of wide-awake samples first, so PERCLOS stays low.
    var at = t0;
    for (var i = 0; i < 12; i++) {
      await c.processObservation(obs(at), isDriving: true);
      at = at.add(const Duration(milliseconds: 250));
    }

    await c.processObservation(obs(at, pitch: -30), isDriving: true);
    at = at.add(const Duration(seconds: 3));
    final state = await c.processObservation(
      obs(at, pitch: -30),
      isDriving: true,
    );

    expect(state, DriverState.lookingAway);
    expect(alerts.warnings, isNot(contains(DriverState.drowsy)));
  });

  test('a brief downward glance is not drowsy, even when tired', () async {
    final alerts = _RecordingAlertService();
    final c = controller(alerts, alreadyDrowsy: true);

    // Down for well under the glance limit, checking the speedometer.
    var at = t0.add(const Duration(seconds: 4));
    await c.processObservation(obs(at, pitch: -30), isDriving: true);
    at = at.add(const Duration(milliseconds: 800));
    final state = await c.processObservation(
      obs(at, pitch: -30),
      isDriving: true,
    );

    expect(state, DriverState.glancingAway);
  });

  test('head-down while stopped is not drowsy', () async {
    final alerts = _RecordingAlertService();
    final c = controller(alerts, alreadyDrowsy: true);

    var at = t0.add(const Duration(seconds: 4));
    await c.processObservation(
      obs(at, pitch: -30),
      isDriving: true,
      isVehicleMoving: false,
    );
    at = at.add(const Duration(seconds: 3));
    final state = await c.processObservation(
      obs(at, pitch: -30),
      isDriving: true,
      isVehicleMoving: false,
    );

    expect(state, DriverState.lookingAway);
  });

  test('the analyzer reports a head-drop relative to the baseline', () {
    const a = DistractionAnalyzer();
    expect(a.isHeadDown(obs(t0, pitch: -30)), isTrue);
    expect(a.isHeadDown(obs(t0, pitch: -5)), isFalse);
    // A driver whose road pose is already tilted down isn't nodding off.
    final tilted = a.withBaseline(
      yawDegrees: 0,
      pitchDegrees: -25,
      rollDegrees: 0,
    );
    expect(tilted.isHeadDown(obs(t0, pitch: -30)), isFalse);
  });

  group('closed eyes are seen through a tilted head', () {
    const analyzer = DistractionAnalyzer();

    FaceObservation tilted({
      double pitch = 0,
      double roll = 0,
      double yaw = 0,
      double eye = 0.05,
    }) {
      return FaceObservation(
        timestamp: t0,
        faceVisible: true,
        headYawDegrees: yaw,
        headPitchDegrees: pitch,
        headRollDegrees: roll,
        leftEyeOpenProbability: eye,
        rightEyeOpenProbability: eye,
      );
    }

    test('head down with eyes shut reads as eyes closed, not looking away', () {
      expect(analyzer.analyze(tilted(pitch: -30)), DriverState.eyesClosed);
    });

    test('head lolled sideways with eyes shut reads as eyes closed', () {
      expect(analyzer.analyze(tilted(roll: 40)), DriverState.eyesClosed);
      expect(analyzer.analyze(tilted(roll: -40)), DriverState.eyesClosed);
    });

    test('head down with eyes open is still looking away', () {
      expect(
        analyzer.analyze(tilted(pitch: -30, eye: 0.9)),
        DriverState.glancingAway,
      );
    });

    test('head tilted diagonally down with eyes shut reads as eyes closed', () {
      // A diagonal droop carries a yaw component alongside the pitch and roll.
      // That yaw clears the looking-away threshold long before the eyes stop
      // being visible, so it must not suppress the eye check.
      expect(
        analyzer.analyze(tilted(pitch: -35, roll: 30, yaw: 30)),
        DriverState.eyesClosed,
      );
      expect(
        analyzer.analyze(tilted(pitch: -35, roll: -30, yaw: -30)),
        DriverState.eyesClosed,
      );
    });

    test('a big head turn is judged as a turn, not as closed eyes', () {
      // In profile ML Kit reports unreliable eye values, so a shoulder check
      // must not masquerade as drowsiness.
      expect(analyzer.analyze(tilted(yaw: 60)), DriverState.glancingAway);
    });

    test('unreadable eyes are not treated as closed', () {
      expect(
        analyzer.analyze(
          FaceObservation(
            timestamp: t0,
            faceVisible: true,
            headYawDegrees: 0,
            headPitchDegrees: -30,
            headRollDegrees: 0,
          ),
        ),
        DriverState.glancingAway,
      );
    });
  });

  test('drowsiness builds up while the head is down', () async {
    final alerts = _RecordingAlertService();
    final c = controller(alerts);

    // Head already down and eyes shut from the start, nothing seeded. This used
    // to be impossible to detect: the pose short-circuited before the eyes were
    // looked at, so PERCLOS never moved.
    var at = t0;
    DriverState? last;
    for (var i = 0; i < 20; i++) {
      last = await c.processObservation(
        obs(at, pitch: -30, leftEye: 0.05, rightEye: 0.05),
        isDriving: true,
      );
      if (last == DriverState.drowsy) {
        break;
      }
      at = at.add(const Duration(milliseconds: 500));
    }

    expect(last, DriverState.drowsy);
    expect(alerts.warnings, contains(DriverState.drowsy));
  });

  test('drowsiness builds up while the head lolls sideways', () async {
    final alerts = _RecordingAlertService();
    final c = controller(alerts);

    var at = t0;
    DriverState? last;
    for (var i = 0; i < 20; i++) {
      last = await c.processObservation(
        FaceObservation(
          timestamp: at,
          faceVisible: true,
          headYawDegrees: 0,
          headPitchDegrees: 0,
          headRollDegrees: 40,
          leftEyeOpenProbability: 0.05,
          rightEyeOpenProbability: 0.05,
        ),
        isDriving: true,
      );
      if (last == DriverState.drowsy) {
        break;
      }
      at = at.add(const Duration(milliseconds: 500));
    }

    expect(last, DriverState.drowsy);
  });
}
