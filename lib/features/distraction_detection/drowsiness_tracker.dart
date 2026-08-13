/// Tracks PERCLOS, the fraction of recent time the eyes were closed, over a
/// rolling window. A sustained high fraction indicates drowsiness, which is a
/// stronger signal than any single closed-eye frame.
class DrowsinessTracker {
  DrowsinessTracker({
    this.window = const Duration(seconds: 30),
    this.perclosThreshold = 0.2,
    this.minSamples = 8,
  });

  /// How far back to look when computing the closed fraction.
  final Duration window;

  /// Closed-fraction at or above this counts as drowsy.
  final double perclosThreshold;

  /// Don't declare drowsiness until at least this many samples exist, so a
  /// single early closed frame can't trip it.
  final int minSamples;

  final List<_Sample> _samples = [];

  /// Records one observation: whether the eyes were closed at [at].
  void record({required DateTime at, required bool eyesClosed}) {
    _samples.add(_Sample(at, eyesClosed));
    final cutoff = at.subtract(window);
    _samples.removeWhere((sample) => sample.at.isBefore(cutoff));
  }

  /// Fraction of samples in the window where the eyes were closed (0..1).
  double get perclos {
    if (_samples.isEmpty) {
      return 0;
    }
    final closed = _samples.where((sample) => sample.eyesClosed).length;
    return closed / _samples.length;
  }

  bool get isDrowsy =>
      _samples.length >= minSamples && perclos >= perclosThreshold;

  void reset() => _samples.clear();
}

class _Sample {
  _Sample(this.at, this.eyesClosed);

  final DateTime at;
  final bool eyesClosed;
}
