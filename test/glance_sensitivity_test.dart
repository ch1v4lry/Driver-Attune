import 'package:driver_attune/features/alerts/alert_service.dart';
import 'package:driver_attune/features/distraction_detection/distraction_analyzer.dart';
import 'package:driver_attune/features/distraction_detection/driver_state.dart';
import 'package:driver_attune/features/distraction_detection/face_observation.dart';
import 'package:driver_attune/features/distraction_detection/glance_sensitivity.dart';
import 'package:driver_attune/features/drive_session/drive_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _SilentAlertService implements AlertService {
  @override
  Future<void> warn(DriverState state) async {}
}

void main() {
  final t0 = DateTime(2026, 1, 1, 12);

  FaceObservation lookingAway(DateTime at) {
    return FaceObservation(
      timestamp: at,
      faceVisible: true,
      headYawDegrees: 40,
      headPitchDegrees: 0,
      headRollDegrees: 0,
      leftEyeOpenProbability: 0.9,
      rightEyeOpenProbability: 0.9,
    );
  }

  /// The state after holding a look away for [heldFor] at [sensitivity].
  Future<DriverState> stateAfterHolding(
    GlanceSensitivity sensitivity,
    Duration heldFor,
  ) async {
    final c = DriveSessionController(
      analyzer: const DistractionAnalyzer(),
      alertService: _SilentAlertService(),
      sensitivity: sensitivity,
    );
    await c.processObservation(lookingAway(t0), isDriving: true);
    return c.processObservation(
      lookingAway(t0.add(heldFor)),
      isDriving: true,
    );
  }

  test('the three tiers use the intended limits', () {
    expect(
      GlanceSensitivity.safest.maxGlanceDuration,
      const Duration(milliseconds: 1500),
    );
    expect(
      GlanceSensitivity.lenient.maxGlanceDuration,
      const Duration(milliseconds: 2500),
    );
    expect(
      GlanceSensitivity.lax.maxGlanceDuration,
      const Duration(milliseconds: 3500),
    );
  });

  test('a 2 second look is judged differently by each tier', () async {
    const held = Duration(seconds: 2);
    // Past safest's 1.5s limit...
    expect(
      await stateAfterHolding(GlanceSensitivity.safest, held),
      DriverState.lookingAway,
    );
    // ...but still within lenient's 2.5s and lax's 3.5s.
    expect(
      await stateAfterHolding(GlanceSensitivity.lenient, held),
      DriverState.glancingAway,
    );
    expect(
      await stateAfterHolding(GlanceSensitivity.lax, held),
      DriverState.glancingAway,
    );
  });

  test('a 3 second look only survives the laxest tier', () async {
    const held = Duration(seconds: 3);
    expect(
      await stateAfterHolding(GlanceSensitivity.safest, held),
      DriverState.lookingAway,
    );
    expect(
      await stateAfterHolding(GlanceSensitivity.lenient, held),
      DriverState.lookingAway,
    );
    expect(
      await stateAfterHolding(GlanceSensitivity.lax, held),
      DriverState.glancingAway,
    );
  });

  test('a 4 second look is a distraction at every tier', () async {
    const held = Duration(seconds: 4);
    for (final tier in GlanceSensitivity.values) {
      expect(
        await stateAfterHolding(tier, held),
        DriverState.lookingAway,
        reason: '${tier.label} should not tolerate 4s',
      );
    }
  });

  test('changing the tier mid-session takes effect immediately', () async {
    final c = DriveSessionController(
      analyzer: const DistractionAnalyzer(),
      alertService: _SilentAlertService(),
      sensitivity: GlanceSensitivity.lax,
    );
    await c.processObservation(lookingAway(t0), isDriving: true);

    // 2s in, still a glance under lax.
    expect(
      await c.processObservation(
        lookingAway(t0.add(const Duration(seconds: 2))),
        isDriving: true,
      ),
      DriverState.glancingAway,
    );

    // Tighten to safest: the same ongoing look is now over the limit.
    c.sensitivity = GlanceSensitivity.safest;
    expect(
      await c.processObservation(
        lookingAway(t0.add(const Duration(milliseconds: 2100))),
        isDriving: true,
      ),
      DriverState.lookingAway,
    );
  });

  test('every tier is presented with a label and a seconds value', () {
    for (final tier in GlanceSensitivity.values) {
      expect(tier.label, isNotEmpty);
      expect(tier.description, isNotEmpty);
      expect(tier.secondsLabel, endsWith('s'));
    }
  });
}
