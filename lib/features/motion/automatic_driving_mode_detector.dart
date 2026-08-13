import 'dart:async';

import 'vehicle_activity_service.dart';

/// Converts noisy activity classifications into conservative mode changes.
class AutomaticDrivingModeDetector {
  AutomaticDrivingModeDetector({
    required this.isDriving,
    required this.onDrivingModeChanged,
    this.enableAfter = const Duration(seconds: 5),
    this.disableAfter = const Duration(seconds: 30),
    this.minimumConfidence = 75,
  });

  final bool Function() isDriving;
  final void Function(bool enabled) onDrivingModeChanged;
  final Duration enableAfter;
  final Duration disableAfter;
  final int minimumConfidence;

  Timer? _enableTimer;
  Timer? _disableTimer;
  bool _isInVehicle = false;
  bool _automaticallyEnabled = false;
  bool _suppressedUntilVehicleExit = false;

  bool get automaticallyEnabled => _automaticallyEnabled;

  void record(VehicleActivity activity) {
    if (activity.confidence < minimumConfidence) {
      return;
    }

    switch (activity.type) {
      case VehicleActivityType.inVehicle:
        _isInVehicle = true;
        _disableTimer?.cancel();
        _disableTimer = null;
        if (_suppressedUntilVehicleExit ||
            _automaticallyEnabled ||
            isDriving() ||
            _enableTimer != null) {
          return;
        }
        _enableTimer = Timer(enableAfter, () {
          _enableTimer = null;
          if (!_isInVehicle || _suppressedUntilVehicleExit || isDriving()) {
            return;
          }
          _automaticallyEnabled = true;
          onDrivingModeChanged(true);
        });
        return;
      case VehicleActivityType.notInVehicle:
        _isInVehicle = false;
        _enableTimer?.cancel();
        _enableTimer = null;
        if (_disableTimer != null) {
          return;
        }
        _disableTimer = Timer(disableAfter, () {
          _disableTimer = null;
          if (_isInVehicle) {
            return;
          }
          _suppressedUntilVehicleExit = false;
          if (_automaticallyEnabled) {
            _automaticallyEnabled = false;
            onDrivingModeChanged(false);
          }
        });
        return;
      case VehicleActivityType.unknown:
        return;
    }
  }

  /// Records an explicit user choice so automation never fights the switch.
  void manualDrivingModeChanged(bool enabled) {
    _enableTimer?.cancel();
    _enableTimer = null;
    _disableTimer?.cancel();
    _disableTimer = null;
    _automaticallyEnabled = false;
    if (!enabled && _isInVehicle) {
      _suppressedUntilVehicleExit = true;
    }
  }

  /// Stops pending automatic changes without changing the current mode.
  void pause() {
    _enableTimer?.cancel();
    _enableTimer = null;
    _disableTimer?.cancel();
    _disableTimer = null;
    _isInVehicle = false;
  }

  /// Turns automation off without changing the current driving mode.
  void suspend() {
    pause();
    _automaticallyEnabled = false;
    _suppressedUntilVehicleExit = false;
  }

  void dispose() {
    _enableTimer?.cancel();
    _disableTimer?.cancel();
  }
}
