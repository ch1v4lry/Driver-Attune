import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

/// Measures how much the phone itself is vibrating, from the accelerometer,
/// independent of the driver's head movement. High values indicate a loose or
/// shaky mount.
class ShakeDetector {
  ShakeDetector({this.window = const Duration(milliseconds: 1200)});

  /// How much recent accelerometer history to average over.
  final Duration window;

  final List<_Reading> _readings = [];
  StreamSubscription<UserAccelerometerEvent>? _subscription;

  /// Begins listening to the accelerometer. Safe to call more than once.
  void start() {
    _subscription ??=
        userAccelerometerEventStream().listen(_onEvent, onError: (_) {});
  }

  void _onEvent(UserAccelerometerEvent event) {
    final now = DateTime.now();
    final magnitude = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    _readings.add(_Reading(now, magnitude));
    final cutoff = now.subtract(window);
    _readings.removeWhere((r) => r.at.isBefore(cutoff));
  }

  /// RMS of the recent gravity-removed acceleration magnitude (m/s²). Near zero
  /// when the phone is held/mounted still, larger the more it vibrates.
  double get vibration {
    // Age readings out here as well as on arrival. The stream stops while the
    // app is backgrounded, and without this the last values before it stopped
    // would be reported as current, so a phone that was moving when it was put
    // away still reads as moving when it comes back.
    final cutoff = DateTime.now().subtract(window);
    _readings.removeWhere((r) => r.at.isBefore(cutoff));
    if (_readings.isEmpty) {
      return 0;
    }
    var sumSquares = 0.0;
    for (final reading in _readings) {
      sumSquares += reading.magnitude * reading.magnitude;
    }
    return math.sqrt(sumSquares / _readings.length);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}

class _Reading {
  _Reading(this.at, this.magnitude);

  final DateTime at;
  final double magnitude;
}
