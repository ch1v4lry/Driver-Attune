import 'package:driver_attune/features/motion/automatic_driving_mode_detector.dart';
import 'package:driver_attune/features/motion/vehicle_activity_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const inVehicle = VehicleActivity(
    type: VehicleActivityType.inVehicle,
    confidence: 100,
  );
  const leftVehicle = VehicleActivity(
    type: VehicleActivityType.notInVehicle,
    confidence: 100,
  );

  test('enables driving mode after a sustained vehicle reading', () {
    fakeAsync((async) {
      var driving = false;
      final detector = AutomaticDrivingModeDetector(
        isDriving: () => driving,
        onDrivingModeChanged: (value) => driving = value,
      );

      detector.record(inVehicle);
      async.elapse(const Duration(seconds: 4));
      expect(driving, isFalse);

      async.elapse(const Duration(seconds: 1));
      expect(driving, isTrue);
    });
  });

  test('does not disable at a stop or on an unknown reading', () {
    fakeAsync((async) {
      var driving = false;
      final detector = AutomaticDrivingModeDetector(
        isDriving: () => driving,
        onDrivingModeChanged: (value) => driving = value,
      );

      detector.record(inVehicle);
      async.elapse(const Duration(seconds: 5));
      detector.record(
        const VehicleActivity(
          type: VehicleActivityType.unknown,
          confidence: 100,
        ),
      );
      async.elapse(const Duration(minutes: 1));

      expect(driving, isTrue);
    });
  });

  test('disables only after a sustained vehicle exit', () {
    fakeAsync((async) {
      var driving = false;
      final detector = AutomaticDrivingModeDetector(
        isDriving: () => driving,
        onDrivingModeChanged: (value) => driving = value,
      );

      detector.record(inVehicle);
      async.elapse(const Duration(seconds: 5));
      detector.record(leftVehicle);
      async.elapse(const Duration(seconds: 29));
      expect(driving, isTrue);

      async.elapse(const Duration(seconds: 1));
      expect(driving, isFalse);
    });
  });

  test('manual off suppresses re-enabling until vehicle exit', () {
    fakeAsync((async) {
      var driving = false;
      final detector = AutomaticDrivingModeDetector(
        isDriving: () => driving,
        onDrivingModeChanged: (value) => driving = value,
      );

      detector.record(inVehicle);
      async.elapse(const Duration(seconds: 5));
      driving = false;
      detector.manualDrivingModeChanged(false);

      detector.record(inVehicle);
      async.elapse(const Duration(minutes: 1));
      expect(driving, isFalse);

      detector.record(leftVehicle);
      async.elapse(const Duration(seconds: 30));
      detector.record(inVehicle);
      async.elapse(const Duration(seconds: 5));
      expect(driving, isTrue);
    });
  });

  test('low-confidence readings do not change the mode', () {
    fakeAsync((async) {
      var driving = false;
      final detector = AutomaticDrivingModeDetector(
        isDriving: () => driving,
        onDrivingModeChanged: (value) => driving = value,
      );

      detector.record(
        const VehicleActivity(
          type: VehicleActivityType.inVehicle,
          confidence: 60,
        ),
      );
      async.elapse(const Duration(minutes: 1));

      expect(driving, isFalse);
    });
  });

  test('does not claim ownership of a manually enabled mode', () {
    fakeAsync((async) {
      var driving = true;
      final detector = AutomaticDrivingModeDetector(
        isDriving: () => driving,
        onDrivingModeChanged: (value) => driving = value,
      );

      detector.record(inVehicle);
      async.elapse(const Duration(seconds: 5));
      detector.record(leftVehicle);
      async.elapse(const Duration(seconds: 30));

      expect(driving, isTrue);
      expect(detector.automaticallyEnabled, isFalse);
    });
  });
}
