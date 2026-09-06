import 'dart:async';

import 'package:flutter/services.dart';

enum VehicleActivityType { inVehicle, notInVehicle, unknown }

class VehicleActivity {
  const VehicleActivity({
    required this.type,
    required this.confidence,
  });

  final VehicleActivityType type;
  final int confidence;
}

/// Thin bridge to iOS Core Motion and Android Activity Recognition. Runs only
/// while the setting is enabled and the app is in the foreground.
class VehicleActivityService {
  static const MethodChannel _channel =
      MethodChannel('driver_attune/vehicle_activity');

  void Function(VehicleActivity activity)? _onActivity;
  bool _running = false;

  bool get isRunning => _running;

  Future<bool> start(
    void Function(VehicleActivity activity) onActivity,
  ) async {
    _onActivity = onActivity;
    _channel.setMethodCallHandler(_handleMethodCall);
    if (_running) {
      return true;
    }
    // Native APIs may deliver their current classification immediately.
    _running = true;
    try {
      final started = await _channel.invokeMethod<bool>('start') ?? false;
      _running = started;
      return started;
    } on PlatformException {
      _running = false;
      return false;
    } on MissingPluginException {
      _running = false;
      return false;
    }
  }

  Future<void> stop() async {
    _running = false;
    _onActivity = null;
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Activity recognition is optional.
    } on MissingPluginException {
      // Unsupported platforms simply leave automatic mode unavailable.
    }
    _channel.setMethodCallHandler(null);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'activityChanged' || !_running) {
      return;
    }
    final arguments = Map<Object?, Object?>.from(call.arguments as Map);
    final type = switch (arguments['type']) {
      'inVehicle' => VehicleActivityType.inVehicle,
      'notInVehicle' => VehicleActivityType.notInVehicle,
      _ => VehicleActivityType.unknown,
    };
    final confidence = (arguments['confidence'] as num?)?.round() ?? 0;
    _onActivity?.call(
      VehicleActivity(
        type: type,
        confidence: confidence.clamp(0, 100),
      ),
    );
  }
}
