import '../distraction_detection/driver_state.dart';

abstract interface class AlertService {
  Future<void> warn(DriverState state);
}

class ConsoleAlertService implements AlertService {
  const ConsoleAlertService();

  @override
  Future<void> warn(DriverState state) async {
    // Replace with vibration, sound, or notification once device testing
    // starts.
  }
}
