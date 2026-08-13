/// Decides whether the vehicle is actually moving.
///
/// This gates which distractions make sense to judge: with the car moving, the
/// driver should be facing the road and only glancing away briefly. Stopped at
/// a light there is nothing wrong with looking around.
///
/// Two signals, in order of preference:
///
/// GPS speed is used whenever a recent fix is available. It answers the
/// question directly, so it needs only a short confirmation and settles at a
/// stop sign in seconds.
///
/// Accelerometer vibration is the fallback for when GPS is unavailable, denied,
/// or stale: a tunnel, a parking garage, the first seconds of a drive. It is a
/// poor proxy on its own, since an idling engine shakes the car about as much
/// as driving does, so a stop can read as movement and take a long time to
/// settle. That is why speed is preferred whenever it exists.
class VehicleMotionDetector {
  VehicleMotionDetector({
    this.movingSpeed = 3.1,
    this.stoppedSpeed = 2.2,
    this.speedFreshness = const Duration(seconds: 5),
    this.confirmMovingBySpeed = const Duration(milliseconds: 800),
    this.confirmStoppedBySpeed = const Duration(seconds: 3),
    this.movingVibration = 0.9,
    this.stationaryVibration = 0.5,
    this.confirmMoving = const Duration(seconds: 2),
    this.confirmStationary = const Duration(seconds: 5),
  });

  /// Speed (m/s) at or above which the vehicle reads as moving. 3.1 m/s is
  /// about 11 km/h.
  final double movingSpeed;

  /// Speed at or below which it reads as stopped: 2.2 m/s, about 8 km/h.
  ///
  /// Well above walking pace on purpose. GPS speed lags reality by a second or
  /// so, so a car that has actually stopped keeps reporting a small speed for a
  /// moment. Treating anything below a slow crawl as stopped absorbs that tail.
  /// Lower than [movingSpeed] so noise around a single threshold can't flip the
  /// state repeatedly.
  final double stoppedSpeed;

  /// How long a speed reading stays usable. Past this the fix is stale, signal
  /// may have been lost, and the accelerometer takes over.
  final Duration speedFreshness;

  /// Speed answers the question directly, so it needs far less confirmation
  /// than vibration does.
  final Duration confirmMovingBySpeed;
  final Duration confirmStoppedBySpeed;

  /// Fallback thresholds, used only when there is no fresh speed.
  ///
  /// Measured in a real car rather than guessed: driving sits at about 0.9 and
  /// usually higher, while a stop with the engine running hovers around 0.9
  /// too. The two overlap at the boundary, which is the reason GPS leads.
  ///
  /// The wide gap between the two does real work. An idling car lands between
  /// them, where the detector holds whatever it already decided, so a stop
  /// mid-drive stays "moving" (the safe assumption when the signal cannot
  /// tell), while an app opened in a parked car stays "stopped" until the
  /// vibration climbs past driving level.
  final double movingVibration;
  final double stationaryVibration;
  final Duration confirmMoving;
  final Duration confirmStationary;

  bool _isMoving = false;
  DateTime? _pendingSince;
  bool? _pendingValue;

  double? _speed;
  DateTime? _speedAt;

  /// Whether the vehicle currently reads as moving.
  bool get isMoving => _isMoving;

  /// Whether the decision is currently being made from GPS rather than from
  /// vibration. Surfaced in the debug readout so a recording shows which signal
  /// was in charge.
  bool get isUsingSpeed => _speedAt != null && _speed != null;

  /// The most recent usable speed in m/s, or null when there isn't one.
  double? get speedMetersPerSecond => _speed;

  /// Records a GPS speed. Pass null when a fix arrives without a usable speed.
  void updateSpeed({
    required DateTime at,
    required double? speedMetersPerSecond,
  }) {
    if (speedMetersPerSecond == null || speedMetersPerSecond.isNaN) {
      return;
    }
    // Some platforms report a small negative value to mean "unknown".
    _speed = speedMetersPerSecond < 0 ? 0 : speedMetersPerSecond;
    _speedAt = at;
    _apply(at: at, wants: _speedVerdict(), fromSpeed: true);
  }

  /// Records an accelerometer vibration sample. Used only when there is no
  /// fresh speed, since speed is the better answer.
  void update({required DateTime at, required double vibration}) {
    _expireStaleSpeed(at);
    if (isUsingSpeed) {
      // Re-evaluate anyway, so a pending transition can confirm on the clock
      // even if no new fix has arrived yet.
      _apply(at: at, wants: _speedVerdict(), fromSpeed: true);
      return;
    }
    _apply(at: at, wants: _vibrationVerdict(vibration), fromSpeed: false);
  }

  /// What the current speed says, or null inside the dead band between the two
  /// thresholds.
  bool? _speedVerdict() {
    final speed = _speed;
    if (speed == null) {
      return null;
    }
    if (speed >= movingSpeed) {
      return true;
    }
    if (speed <= stoppedSpeed) {
      return false;
    }
    return null;
  }

  bool? _vibrationVerdict(double vibration) {
    if (vibration >= movingVibration) {
      return true;
    }
    if (vibration <= stationaryVibration) {
      return false;
    }
    // In the dead band between the two thresholds: hold the current state.
    return null;
  }

  void _expireStaleSpeed(DateTime at) {
    final speedAt = _speedAt;
    if (speedAt != null && at.difference(speedAt) > speedFreshness) {
      _speed = null;
      _speedAt = null;
    }
  }

  void _apply({
    required DateTime at,
    required bool? wants,
    required bool fromSpeed,
  }) {
    if (wants == null || wants == _isMoving) {
      _pendingSince = null;
      _pendingValue = null;
      return;
    }

    if (_pendingValue != wants) {
      _pendingValue = wants;
      _pendingSince = at;
      return;
    }

    final since = _pendingSince;
    if (since == null) {
      _pendingSince = at;
      return;
    }

    final needed = fromSpeed
        ? (wants ? confirmMovingBySpeed : confirmStoppedBySpeed)
        : (wants ? confirmMoving : confirmStationary);
    if (at.difference(since) >= needed) {
      _isMoving = wants;
      _pendingSince = null;
      _pendingValue = null;
    }
  }

  /// Forgets any in-progress transition and the last fix, e.g. when detection
  /// restarts.
  void reset() {
    _pendingSince = null;
    _pendingValue = null;
    _speed = null;
    _speedAt = null;
  }
}
