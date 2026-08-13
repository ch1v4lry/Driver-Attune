class FaceObservation {
  const FaceObservation({
    required this.timestamp,
    required this.faceVisible,
    this.headYawDegrees,
    this.headPitchDegrees,
    this.headRollDegrees,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
    this.mouthOpenRatio,
    this.faceBoundsFraction,
    this.faceNearEdge = false,
    this.frameBrightness,
  });

  final DateTime timestamp;
  final bool faceVisible;
  final double? headYawDegrees;
  final double? headPitchDegrees;

  /// Head roll (sideways tilt) in degrees. A large deviation is a
  /// head-slump/nodding-off posture.
  final double? headRollDegrees;

  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;

  /// Inner-lip gap ratio used for yawn detection; null when not measurable.
  final double? mouthOpenRatio;

  /// Face bounding-box area as a fraction of the frame (mount quality). Null
  /// when there's no face or no frame dimensions.
  final double? faceBoundsFraction;

  /// Whether the face bounding box sits near/over a frame edge (mount quality).
  final bool faceNearEdge;

  /// Average frame brightness, 0..1 (mount quality). Null when there's no
  /// image.
  final double? frameBrightness;
}
