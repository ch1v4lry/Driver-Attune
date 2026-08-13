import '../alerts/alert_service.dart';
import '../distraction_detection/distraction_analyzer.dart';
import '../distraction_detection/driver_state.dart';
import '../distraction_detection/drowsiness_tracker.dart';
import '../distraction_detection/face_observation.dart';
import '../distraction_detection/glance_sensitivity.dart';
import '../distraction_detection/yawn_tracker.dart';

/// Turns the analyzer's per-frame verdicts into a driver state over time, and
/// raises alerts.
///
/// This is where duration matters: filtering blinks, tolerating a brief glance
/// before calling it a distraction, accumulating PERCLOS, and confirming a
/// yawn. It holds no Flutter dependencies so the whole state machine can be
/// tested with synthetic observations and a fake clock.
class DriveSessionController {
  DriveSessionController({
    required DistractionAnalyzer analyzer,
    required this.alertService,
    this.alertAfter = const Duration(seconds: 2),
    this.minEyeClosure = const Duration(milliseconds: 400),
    this.sensitivity = GlanceSensitivity.lenient,
    DrowsinessTracker? drowsinessTracker,
    YawnTracker? yawnTracker,
  })  : _analyzer = analyzer,
        _drowsiness = drowsinessTracker ?? DrowsinessTracker(),
        _yawn = yawnTracker ?? YawnTracker();

  DistractionAnalyzer _analyzer;
  final AlertService alertService;
  final Duration alertAfter;
  final Duration minEyeClosure;

  /// How tolerant to be of looks away from the road.
  GlanceSensitivity sensitivity;

  /// How long a look away from the road may last before it stops being a glance
  /// and becomes a distraction. Mirror checks, head checks, and instrument
  /// glances are all brief. Anything sustained is eyes-off-road regardless of
  /// which direction it is in.
  Duration get maxGlanceDuration => sensitivity.maxGlanceDuration;

  final DrowsinessTracker _drowsiness;
  final YawnTracker _yawn;

  /// Whether to surface the (experimental) yawn state.
  bool yawnDetectionEnabled = true;

  DriverState _currentState = DriverState.unknown;
  DateTime? _stateStartedAt;
  DateTime? _eyesClosedSince;
  DateTime? _glanceStartedAt;

  DriverState get currentState => _currentState;

  /// Fraction of recent time the eyes were closed (PERCLOS), 0..1.
  double get perclos => _drowsiness.perclos;

  /// Records the driver's current "looking at the road" head pose so later
  /// observations are judged as deviations from it, not from facing the camera.
  void calibrate({
    required double yawDegrees,
    required double pitchDegrees,
    double rollDegrees = 0,
    double? mouthOpenRatio,
    double? leftEyeOpen,
    double? rightEyeOpen,
  }) {
    double? eyeClosedThreshold;
    if (leftEyeOpen != null && rightEyeOpen != null) {
      // Set the eye-closed line relative to this driver's resting openness, so
      // narrower eyes aren't read as closed. Clamp so it only ever drops below
      // the default, never above it.
      final restingOpen = (leftEyeOpen + rightEyeOpen) / 2;
      eyeClosedThreshold = (restingOpen * 0.4).clamp(0.15, 0.35).toDouble();
    }
    _analyzer = _analyzer.withBaseline(
      yawDegrees: yawDegrees,
      pitchDegrees: pitchDegrees,
      rollDegrees: rollDegrees,
      eyeClosedThreshold: eyeClosedThreshold,
    );
    if (mouthOpenRatio != null) {
      _yawn.calibrate(mouthOpenRatio);
    }
  }

  Future<DriverState> processObservation(
    FaceObservation observation, {
    required bool isDriving,
    bool isVehicleMoving = true,
  }) async {
    var nextState = _analyzer.analyze(
      observation,
      isVehicleMoving: isVehicleMoving,
    );

    // Blink filter: a normal blink is too brief to count. Require the eyes to
    // stay closed for a short window before reporting "eyes closed".
    // A discarded blink falls back to what the head is doing, not to attentive.
    // Eye closure is judged ahead of pose, so a driver who blinks while looking
    // away would otherwise read as attentive for that frame, and worse, reset
    // the glance timer below, letting a periodic blink hold off the
    // looking-away alert indefinitely.
    if (nextState == DriverState.eyesClosed) {
      _eyesClosedSince ??= observation.timestamp;
      if (observation.timestamp.difference(_eyesClosedSince!) < minEyeClosure) {
        nextState = _analyzer.poseState(
          observation,
          isVehicleMoving: isVehicleMoving,
        );
      }
    } else {
      _eyesClosedSince = null;
    }

    // A look away is excused only while it stays brief. Held past the limit it
    // is a sustained eyes-off-road event.
    if (nextState == DriverState.glancingAway) {
      _glanceStartedAt ??= observation.timestamp;
      if (observation.timestamp.difference(_glanceStartedAt!) >
          maxGlanceDuration) {
        nextState = DriverState.lookingAway;
      }
    } else {
      _glanceStartedAt = null;
    }

    // Feed the rolling PERCLOS tracker whenever the eyes were readable,
    // whatever the head was doing. Gating this on the driver state instead
    // would stop the window advancing the moment the head tips off axis, which
    // is where a drowsy driver's head is, so drowsiness could never build up in
    // the posture that signals it.
    if (_eyesWereReadable(observation)) {
      _drowsiness.record(
        at: observation.timestamp,
        eyesClosed: nextState == DriverState.eyesClosed,
      );
      // Only escalate when the eyes are actually closed now (not merely off a
      // stale window), so opening the eyes during recovery isn't re-flagged.
      if (_drowsiness.isDrowsy && nextState == DriverState.eyesClosed) {
        nextState = DriverState.drowsy;
        // Fire drowsiness as a one-shot event: clear the window so the state
        // recovers as soon as the driver is alert again, and only re-fires if
        // drowsiness actually rebuilds (rather than off stale samples).
        _drowsiness.reset();
      }
    }

    // Nodding off: a head hanging down, held long enough to have stopped being
    // a glance, while the recent PERCLOS window already says the eyes are
    // drooping. Neither signal is conclusive alone: a driver can look down at
    // the controls, and PERCLOS can be elevated while still alert. But a
    // sustained head-drop on top of drooping eyes is the microsleep posture,
    // and it is exactly when the eyes are hardest to read directly.
    if (isVehicleMoving &&
        nextState == DriverState.lookingAway &&
        _drowsiness.isDrowsy &&
        _analyzer.isHeadDown(observation)) {
      nextState = DriverState.drowsy;
      // One-shot, like the eyes-closed route: recover as soon as the driver
      // lifts their head rather than re-firing off the same stale window.
      _drowsiness.reset();
    }

    // Yawn: a sustained wide-open mouth while otherwise attentive.
    if (yawnDetectionEnabled) {
      final yawning = _yawn.update(
        at: observation.timestamp,
        mouthOpenRatio:
            observation.faceVisible ? observation.mouthOpenRatio : null,
      );
      if (yawning && nextState == DriverState.attentive) {
        nextState = DriverState.yawning;
      }
    }

    _updateState(nextState, observation.timestamp);

    if (isDriving && _shouldAlert(nextState, observation.timestamp)) {
      await alertService.warn(nextState);
    }

    return nextState;
  }

  /// Called when the driver leaves the app to use the phone. Treated as an
  /// immediate distraction while driving (no sustained-time threshold).
  Future<DriverState> registerPhoneInteraction({
    required bool isDriving,
  }) async {
    _updateState(DriverState.usingPhone, DateTime.now());
    if (isDriving) {
      await alertService.warn(DriverState.usingPhone);
    }
    return _currentState;
  }

  /// Whether ML Kit could actually see both eyes this frame.
  static bool _eyesWereReadable(FaceObservation observation) {
    return observation.faceVisible &&
        observation.leftEyeOpenProbability != null &&
        observation.rightEyeOpenProbability != null;
  }

  void _updateState(DriverState nextState, DateTime timestamp) {
    if (nextState == _currentState) {
      return;
    }

    _currentState = nextState;
    _stateStartedAt = timestamp;
  }

  bool _shouldAlert(DriverState state, DateTime timestamp) {
    if (state == DriverState.attentive ||
        state == DriverState.unknown ||
        // A brief glance is normal driving. If it runs long it has already been
        // rewritten to lookingAway above, which does alert.
        state == DriverState.glancingAway) {
      return false;
    }

    // Drowsiness is already a sustained (PERCLOS-window) condition, so alert
    // right away instead of waiting out the debounce.
    if (state == DriverState.drowsy) {
      return true;
    }

    final startedAt = _stateStartedAt;
    if (startedAt == null) {
      return false;
    }

    return timestamp.difference(startedAt) >= alertAfter;
  }
}
