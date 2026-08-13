import 'package:driver_focus/features/distraction_detection/distraction_analyzer.dart';
import 'package:driver_focus/features/distraction_detection/driver_state.dart';
import 'package:driver_focus/features/distraction_detection/face_observation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const analyzer = DistractionAnalyzer();
  final now = DateTime(2026, 1, 1);

  FaceObservation observation({
    bool faceVisible = true,
    double? yaw = 0,
    double? pitch = 0,
    double? leftEye = 0.9,
    double? rightEye = 0.9,
    double? mouth = 0,
    double? roll = 0,
    double? brightness,
  }) {
    return FaceObservation(
      timestamp: now,
      faceVisible: faceVisible,
      headYawDegrees: yaw,
      headPitchDegrees: pitch,
      headRollDegrees: roll,
      leftEyeOpenProbability: leftEye,
      rightEyeOpenProbability: rightEye,
      mouthOpenRatio: mouth,
      frameBrightness: brightness,
    );
  }

  test('reports attentive when face is visible and aligned', () {
    expect(analyzer.analyze(observation()), DriverState.attentive);
  });

  test('reports a glance for large yaw', () {
    expect(analyzer.analyze(observation(yaw: 28)), DriverState.glancingAway);
  });

  test('a moderate head roll on its own is not a glance', () {
    // A moderate sideways tilt alone (leaning on the headrest, etc.) is
    // tolerated as long as it stays under the solo threshold.
    expect(analyzer.analyze(observation(roll: 25)), DriverState.attentive);
    expect(analyzer.analyze(observation(roll: -25)), DriverState.attentive);
  });

  test('an extreme head roll on its own is a glance', () {
    // Past the solo threshold, a tilt is a slump, no turn needed.
    expect(analyzer.analyze(observation(roll: 32)), DriverState.glancingAway);
    expect(analyzer.analyze(observation(roll: -32)), DriverState.glancingAway);
  });

  test('roll combined with a moderate head turn is a glance', () {
    // Yaw 18 is below the 22 standalone threshold, but with a >=20 roll the two
    // together trip the lower combined yaw threshold (15).
    expect(
      analyzer.analyze(observation(roll: 25, yaw: 18)),
      DriverState.glancingAway,
    );
    expect(
      analyzer.analyze(observation(roll: -25, yaw: -18)),
      DriverState.glancingAway,
    );
  });

  test('a big roll with only a slight head turn stays attentive', () {
    // Yaw 10 is below the combined threshold, so the roll doesn't count.
    expect(
      analyzer.analyze(observation(roll: 25, yaw: 10)),
      DriverState.attentive,
    );
  });

  test('a moderate head turn without much roll stays attentive', () {
    // Yaw 18 is below the standalone threshold and the roll is too small to
    // pair with it.
    expect(
      analyzer.analyze(observation(roll: 8, yaw: 18)),
      DriverState.attentive,
    );
  });

  test('reports a glance when looking down past the threshold', () {
    // Down reads as negative pitch on device; trips at -15.
    expect(analyzer.analyze(observation(pitch: -20)), DriverState.glancingAway);
  });

  test('reports a glance when looking far up', () {
    // Up reads as positive pitch; trips at +30.
    expect(analyzer.analyze(observation(pitch: 32)), DriverState.glancingAway);
  });

  test('uses asymmetric up/down pitch thresholds', () {
    // 20 degrees down is looking away, but the same 20 up is still attentive.
    expect(analyzer.analyze(observation(pitch: -20)), DriverState.glancingAway);
    expect(analyzer.analyze(observation(pitch: 20)), DriverState.attentive);
  });

  test('tolerates a small downward glance', () {
    expect(analyzer.analyze(observation(pitch: -8)), DriverState.attentive);
  });

  group('while the vehicle is stopped', () {
    test('yaw is ignored — looking around is fine when parked', () {
      expect(
        analyzer.analyze(observation(yaw: 60), isVehicleMoving: false),
        DriverState.attentive,
      );
    });

    test('looking sharply down is still a distraction', () {
      expect(
        analyzer.analyze(observation(pitch: -30), isVehicleMoving: false),
        DriverState.glancingAway,
      );
    });

    test('an extreme sideways slump is still a distraction', () {
      expect(
        analyzer.analyze(observation(roll: 35), isVehicleMoving: false),
        DriverState.glancingAway,
      );
    });

    test('the tilt-plus-turn rule needs motion, since it leans on yaw', () {
      expect(
        analyzer.analyze(
          observation(roll: 25, yaw: 18),
          isVehicleMoving: false,
        ),
        DriverState.attentive,
      );
    });
  });

  test('reports eyes closed when both eyes are below threshold', () {
    expect(
      analyzer.analyze(observation(leftEye: 0.1, rightEye: 0.2)),
      DriverState.eyesClosed,
    );
  });

  test('skips drowsiness when the eyes are not visible', () {
    expect(
      analyzer.analyze(observation(leftEye: null, rightEye: null)),
      DriverState.attentive,
    );
  });

  test('tightens the eye-closed threshold in poor light', () {
    // Eyes reading 0.30 count as closed under the default 0.35 threshold in
    // normal light...
    expect(
      analyzer.analyze(
        observation(leftEye: 0.3, rightEye: 0.3, brightness: 0.5),
      ),
      DriverState.eyesClosed,
    );
    // ...but the same 0.30 is tolerated when it's too dark (threshold drops to
    // ~0.245), since the reading can't be trusted.
    expect(
      analyzer.analyze(
        observation(leftEye: 0.3, rightEye: 0.3, brightness: 0.1),
      ),
      DriverState.attentive,
    );
    // Glare (too bright) tightens it the same way.
    expect(
      analyzer.analyze(
        observation(leftEye: 0.3, rightEye: 0.3, brightness: 0.95),
      ),
      DriverState.attentive,
    );
  });

  test('still detects clearly closed eyes in poor light', () {
    // A firmly closed eye (0.1) is below even the tightened threshold, so real
    // drowsiness still registers in the dark.
    expect(
      analyzer.analyze(
        observation(leftEye: 0.1, rightEye: 0.1, brightness: 0.1),
      ),
      DriverState.eyesClosed,
    );
  });

  test('uses the calibrated baseline to decide a glance', () {
    const angledMount = DistractionAnalyzer(baselineYawDegrees: 25);

    // Facing straight at the camera now means looking away from the road.
    expect(angledMount.analyze(observation(yaw: 0)), DriverState.glancingAway);
    // Holding the calibrated road pose is attentive.
    expect(angledMount.analyze(observation(yaw: 25)), DriverState.attentive);
  });

  test('a lower calibrated eye threshold avoids false eye-closed', () {
    const calibrated = DistractionAnalyzer(eyeClosedThreshold: 0.2);

    // Eyes reading 0.3 are "closed" at the default 0.35 threshold...
    expect(
      analyzer.analyze(observation(leftEye: 0.3, rightEye: 0.3)),
      DriverState.eyesClosed,
    );
    // ...but attentive once the threshold is calibrated lower for narrow eyes.
    expect(
      calibrated.analyze(observation(leftEye: 0.3, rightEye: 0.3)),
      DriverState.attentive,
    );
  });
}
