/// Confirms a yawn only when the mouth stays open past [openThreshold] for at
/// least [minOpenDuration]. The duration requirement is what separates a yawn
/// from briefly opening the mouth to talk.
class YawnTracker {
  YawnTracker({
    double openThreshold = 0.45,
    this.calibrationMargin = 0.2,
    this.minOpenDuration = const Duration(milliseconds: 1200),
  }) : _openThreshold = openThreshold;

  /// Added to the resting mouth-open ratio when calibrated, to set the line a
  /// yawn must cross.
  final double calibrationMargin;

  /// How long the mouth must stay open before it's called a yawn.
  final Duration minOpenDuration;

  double _openThreshold;
  DateTime? _openSince;

  /// Mouth-open ratio at or above which the mouth counts as "open".
  double get openThreshold => _openThreshold;

  /// Sets the yawn threshold relative to the driver's resting mouth-open ratio,
  /// so people who rest with their mouth slightly open aren't flagged.
  void calibrate(double restingRatio) {
    _openThreshold = restingRatio + calibrationMargin;
  }

  /// Feed each frame's mouth-open ratio. Returns true once the mouth has been
  /// continuously open long enough to be a yawn. Pass null when the mouth can't
  /// be measured (no face), which resets the timer.
  bool update({required DateTime at, required double? mouthOpenRatio}) {
    final isOpen = mouthOpenRatio != null && mouthOpenRatio >= _openThreshold;
    if (!isOpen) {
      _openSince = null;
      return false;
    }
    final since = _openSince ??= at;
    return at.difference(since) >= minOpenDuration;
  }

  void reset() => _openSince = null;
}
