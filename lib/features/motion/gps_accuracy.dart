import 'package:geolocator/geolocator.dart';

/// How precisely, and how expensively, to ask the phone for speed.
///
/// GPS is the biggest battery draw in the app, and speed doesn't need the same
/// precision as turn-by-turn navigation: the detector only asks "is this above
/// or below a walking pace". So the accuracy is worth letting the driver trade
/// against battery on a long trip.
enum GpsAccuracyMode {
  /// No GPS at all, falls back to the accelerometer.
  off(null),

  /// Coarse fixes, least battery.
  batterySaver(LocationAccuracy.low),

  /// Plenty for deciding moving vs. stopped.
  balanced(LocationAccuracy.high),

  /// Navigation-grade, most responsive and most battery.
  precise(LocationAccuracy.bestForNavigation);

  const GpsAccuracyMode(this.accuracy);

  /// The geolocator setting, or null when GPS is off entirely.
  final LocationAccuracy? accuracy;

  String get label {
    return switch (this) {
      GpsAccuracyMode.off => 'Off',
      GpsAccuracyMode.batterySaver => 'Battery saver',
      GpsAccuracyMode.balanced => 'Balanced',
      GpsAccuracyMode.precise => 'Precise',
    };
  }

  String get description {
    return switch (this) {
      GpsAccuracyMode.off =>
        'No location at all. Movement is guessed from the accelerometer, which '
            'cannot tell an idling engine from driving.',
      GpsAccuracyMode.batterySaver =>
        'Coarse fixes. Lightest on battery, and a little slower to notice that '
            'you have stopped.',
      GpsAccuracyMode.balanced =>
        'Accurate enough to tell moving from stopped, without navigation-grade '
            'battery use.',
      GpsAccuracyMode.precise =>
        'Navigation-grade. Quickest to notice a stop, and the heaviest on '
            'battery.',
    };
  }
}
