import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'gps_accuracy.dart';

/// Supplies vehicle speed from GPS, when the driver allows it.
///
/// Best-effort on purpose: location can be denied, switched off, or unavailable
/// in a tunnel or garage. Every failure path ends in "no speed" rather than an
/// error, because the motion detector falls back to the accelerometer and the
/// app must keep working either way.
class SpeedService {
  StreamSubscription<Position>? _subscription;
  void Function(double speedMetersPerSecond)? _onSpeed;

  /// How precisely to ask for location. Changing it restarts the stream.
  GpsAccuracyMode accuracy = GpsAccuracyMode.balanced;

  /// Whether a usable location stream is currently running.
  bool get isRunning => _subscription != null;

  /// The reason speed isn't available, for showing in the UI. Null while it is
  /// working or hasn't been started.
  String? unavailableReason;

  /// Switches accuracy, restarting the stream if it is already running.
  Future<void> setAccuracy(GpsAccuracyMode mode) async {
    if (mode == accuracy) {
      return;
    }
    accuracy = mode;
    final onSpeed = _onSpeed;
    await dispose();
    if (onSpeed != null) {
      _onSpeed = onSpeed;
      await start(onSpeed);
    }
  }

  /// Starts listening, asking for permission if needed. [onSpeed] receives
  /// metres per second. Safe to call more than once.
  Future<void> start(void Function(double speedMetersPerSecond) onSpeed) async {
    _onSpeed = onSpeed;
    if (_subscription != null) {
      return;
    }
    final requested = accuracy.accuracy;
    if (requested == null) {
      unavailableReason = 'Location turned off in Settings';
      return;
    }
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        unavailableReason = 'Location is turned off';
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        unavailableReason = 'Location permission denied';
        return;
      }

      unavailableReason = null;
      _subscription = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: requested,
          // Keep updates coming while stopped, so a standstill is noticed
          // promptly rather than waiting for the car to move again.
          distanceFilter: 0,
        ),
      ).listen(
        (position) => onSpeed(position.speed),
        onError: (_) {
          unavailableReason = 'Location unavailable';
        },
      );
    } catch (_) {
      // Includes platforms with no location support at all.
      unavailableReason = 'Location unavailable';
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _onSpeed = null;
  }
}
