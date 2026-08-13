import 'driver_state.dart';
import 'face_observation.dart';

/// Judges a single camera frame: where the head is pointed and whether the eyes
/// are shut.
///
/// Stateless and frame-at-a-time. Everything that depends on time, how long a
/// glance has lasted, PERCLOS, yawn duration, is layered on by
/// [DriveSessionController], which keeps this class testable.
///
/// Every angle is measured as a deviation from the calibrated "looking at the
/// road" pose rather than from facing the camera, so the phone's mounting angle
/// drops out. Call [withBaseline] to set that pose.
class DistractionAnalyzer {
  const DistractionAnalyzer({
    this.awayYawThresholdDegrees = 22,
    this.downPitchThresholdDegrees = 15,
    this.upPitchThresholdDegrees = 30,
    this.awayRollThresholdDegrees = 20,
    this.rollCombinedYawThresholdDegrees = 15,
    this.awayRollSoloThresholdDegrees = 30,
    this.eyeReadingYawLimitDegrees = 50,
    this.eyeClosedThreshold = 0.35,
    this.poorLightDarkThreshold = 0.22,
    this.poorLightGlareThreshold = 0.88,
    this.poorLightEyeStrictness = 0.7,
    this.baselineYawDegrees = 0,
    this.baselinePitchDegrees = 0,
    this.baselineRollDegrees = 0,
  });

  /// How far the head may turn left/right from the road baseline before it
  /// counts as looking away.
  final double awayYawThresholdDegrees;

  /// How far the head may tilt down from the road baseline before looking away.
  /// Smaller than the up threshold because looking down (toward a lap or phone)
  /// is the more dangerous case.
  final double downPitchThresholdDegrees;

  /// How far the head may tilt up from the road baseline before looking away.
  final double upPitchThresholdDegrees;

  /// How far the head may tilt sideways (roll) from the road baseline before
  /// the roll counts toward looking away. A roll on its own is not enough, it
  /// only trips when paired with a head turn (see below).
  final double awayRollThresholdDegrees;

  /// When the head is also rolled past [awayRollThresholdDegrees], a yaw this
  /// far from the road baseline is enough to count as looking away. Lower than
  /// [awayYawThresholdDegrees] because a tilt plus turn together is a clearer
  /// off-road/slumping posture than either alone.
  final double rollCombinedYawThresholdDegrees;

  /// A sideways tilt this far from the road baseline counts as looking away on
  /// its own, no head turn needed, since a roll this large is a head-slump.
  final double awayRollSoloThresholdDegrees;

  /// Past this much head turn the face is near enough to profile that ML Kit's
  /// eye-open probabilities can't be trusted, so eye closure is not judged.
  ///
  /// Larger than [awayYawThresholdDegrees] on purpose: that one marks when a
  /// glance counts as off-road, which is well before the eyes stop being
  /// visible. Using the off-road angle here would blind the detector to a head
  /// tilted diagonally down, where the yaw component alone clears it.
  final double eyeReadingYawLimitDegrees;

  /// Both eyes at or below this open-probability count as eyes closed.
  final double eyeClosedThreshold;

  /// Average frame brightness (0..1) below this is "too dark", and above
  /// [poorLightGlareThreshold] is "glare". In either case ML Kit's eye-open
  /// probability is unreliable, so eye-closed detection is tightened. These sit
  /// just inside the mount-quality low-visibility band (0.18/0.92) so the
  /// stricter judging kicks in a little before that warning does.
  final double poorLightDarkThreshold;
  final double poorLightGlareThreshold;

  /// Multiplier applied to [eyeClosedThreshold] in poor light (<1 = stricter):
  /// the eyes must read this much more clearly closed before it counts, which
  /// avoids false eyes-closed/drowsy readings when the image is unreliable.
  final double poorLightEyeStrictness;

  /// The head yaw the driver holds when looking at the road. Calibration sets
  /// this to cancel out a phone mounted off to the side.
  final double baselineYawDegrees;

  /// The head pitch the driver holds when looking at the road.
  final double baselinePitchDegrees;

  /// The head roll the driver holds when looking at the road.
  final double baselineRollDegrees;

  /// Per-frame, geometric classification. Temporal states (drowsy via PERCLOS,
  /// yawning via sustained mouth-open) are layered on top by the controller.
  ///
  /// [isVehicleMoving] gates which head poses even count. Turning to look
  /// around is only a problem when the car is moving, so yaw is ignored while
  /// stopped. Looking sharply down or slumping sideways is judged either way.
  DriverState analyze(
    FaceObservation observation, {
    bool isVehicleMoving = true,
  }) {
    if (!observation.faceVisible) {
      return DriverState.faceNotVisible;
    }

    // Closed eyes outrank head pose. A sleepy driver's head droops forward or
    // lolls to one side, so checking the pose first would return "looking away"
    // and never look at the eyes at all, hiding drowsiness in exactly the
    // posture that signals it. Shut eyes are also the more urgent finding: a
    // driver looking away is still awake.
    // A near-profile head turn is the exception: side-on, ML Kit's eye-open
    // probabilities stop being trustworthy and a shoulder check can read as
    // shut. That limit is much larger than the looking-away one, since at the
    // angle where a glance counts as off-road, both eyes are still visible, so
    // the two are separate numbers.
    final yawDelta = _yawDelta(observation);
    final eyesUnreadableFromAngle =
        yawDelta != null && yawDelta >= eyeReadingYawLimitDegrees;
    if (!eyesUnreadableFromAngle && _eyesAreClosed(observation)) {
      return DriverState.eyesClosed;
    }

    return poseState(observation, isVehicleMoving: isVehicleMoving);
  }

  /// Classification from head pose alone, ignoring the eyes entirely.
  ///
  /// Split out so the controller can fall back to it when it discards a brief
  /// eye closure as a blink: a blink says nothing about where the driver is
  /// looking, so it must not read as attentive while the head is still turned
  /// away.
  DriverState poseState(
    FaceObservation observation, {
    bool isVehicleMoving = true,
  }) {
    if (!observation.faceVisible) {
      return DriverState.faceNotVisible;
    }

    // Judge the head as a deviation from the calibrated "looking at road" pose,
    // not from facing the camera.
    final yawDelta = _yawDelta(observation);
    final pitch = observation.headPitchDegrees;
    final signedPitchDelta =
        pitch == null ? null : pitch - baselinePitchDegrees;

    // Yaw only matters while moving: parked or stopped at a light, looking
    // around is just looking around.
    if (isVehicleMoving &&
        yawDelta != null &&
        yawDelta >= awayYawThresholdDegrees) {
      return DriverState.glancingAway;
    }

    if (signedPitchDelta != null) {
      // On this device ML Kit reports a more negative pitch as the head tilts
      // down and a more positive pitch as it tilts up. Down trips sooner.
      if (signedPitchDelta <= -downPitchThresholdDegrees ||
          signedPitchDelta >= upPitchThresholdDegrees) {
        return DriverState.glancingAway;
      }
    }

    // A moderate sideways head tilt (roll) can be innocent (e.g. leaning on the
    // headrest), so on its own it isn't enough. It only counts when paired with
    // a head turn, at a lower yaw threshold than yaw would trip alone. A large
    // tilt, though, is a head-slump and counts by itself.
    final roll = observation.headRollDegrees;
    if (roll != null) {
      final rollDelta = (roll - baselineRollDegrees).abs();
      // The tilt-plus-turn rule needs a meaningful yaw, so it only applies
      // while moving. A large tilt on its own is a slump either way.
      if (rollDelta >= awayRollSoloThresholdDegrees ||
          (isVehicleMoving &&
              rollDelta >= awayRollThresholdDegrees &&
              yawDelta != null &&
              yawDelta >= rollCombinedYawThresholdDegrees)) {
        return DriverState.glancingAway;
      }
    }

    return DriverState.attentive;
  }

  /// How far the head is turned from the calibrated road pose, or null when the
  /// yaw isn't measurable.
  double? _yawDelta(FaceObservation observation) {
    final yaw = observation.headYawDegrees;
    return yaw == null ? null : (yaw - baselineYawDegrees).abs();
  }

  /// Whether both eyes read as shut this frame.
  ///
  /// Only judged when both are visible. ML Kit reports null probabilities when
  /// it cannot see them, and an unknown eye is not a closed one.
  bool _eyesAreClosed(FaceObservation observation) {
    final leftEye = observation.leftEyeOpenProbability;
    final rightEye = observation.rightEyeOpenProbability;
    if (leftEye == null || rightEye == null) {
      return false;
    }
    final closedThreshold = _eyeClosedThresholdFor(observation.frameBrightness);
    return leftEye <= closedThreshold && rightEye <= closedThreshold;
  }

  /// Whether the head is pitched down far enough to count as looking away.
  ///
  /// Exposed separately from [analyze] because a head hanging down means
  /// something different from a head turned aside: paired with drowsiness it is
  /// the nodding-off posture, not just eyes off the road.
  bool isHeadDown(FaceObservation observation) {
    final pitch = observation.headPitchDegrees;
    if (pitch == null) {
      return false;
    }
    return pitch - baselinePitchDegrees <= -downPitchThresholdDegrees;
  }

  /// The eye-closed threshold to use for this frame. In poor lighting (too dark
  /// or glare) the eye-open probability can't be trusted, so the threshold is
  /// tightened by [poorLightEyeStrictness]. When the brightness is fine, or
  /// unknown (null), the plain [eyeClosedThreshold] is used.
  double _eyeClosedThresholdFor(double? brightness) {
    if (brightness != null &&
        (brightness < poorLightDarkThreshold ||
            brightness > poorLightGlareThreshold)) {
      return eyeClosedThreshold * poorLightEyeStrictness;
    }
    return eyeClosedThreshold;
  }

  /// Returns a copy of this analyzer with the road baseline replaced.
  DistractionAnalyzer withBaseline({
    required double yawDegrees,
    required double pitchDegrees,
    required double rollDegrees,
    double? eyeClosedThreshold,
  }) {
    return DistractionAnalyzer(
      awayYawThresholdDegrees: awayYawThresholdDegrees,
      downPitchThresholdDegrees: downPitchThresholdDegrees,
      upPitchThresholdDegrees: upPitchThresholdDegrees,
      awayRollThresholdDegrees: awayRollThresholdDegrees,
      rollCombinedYawThresholdDegrees: rollCombinedYawThresholdDegrees,
      awayRollSoloThresholdDegrees: awayRollSoloThresholdDegrees,
      eyeReadingYawLimitDegrees: eyeReadingYawLimitDegrees,
      eyeClosedThreshold: eyeClosedThreshold ?? this.eyeClosedThreshold,
      poorLightDarkThreshold: poorLightDarkThreshold,
      poorLightGlareThreshold: poorLightGlareThreshold,
      poorLightEyeStrictness: poorLightEyeStrictness,
      baselineYawDegrees: yawDegrees,
      baselinePitchDegrees: pitchDegrees,
      baselineRollDegrees: rollDegrees,
    );
  }
}
