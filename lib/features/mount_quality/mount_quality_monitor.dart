import '../distraction_detection/face_observation.dart';

/// A mount/environment quality problem, in priority order (highest first).
enum MountIssue {
  none,
  noFace,
  eyesNotReadable,
  unstable,
  lowVisibility,
  faceTooSmall,
  faceOffCenter;

  String get message {
    return switch (this) {
      MountIssue.none => '',
      MountIssue.noFace => 'Point the camera at your face',
      MountIssue.eyesNotReadable =>
        "Can't see your eyes — check the angle or remove sunglasses",
      MountIssue.unstable => 'Unsteady mount — secure the phone',
      MountIssue.lowVisibility =>
        'Low visibility — the camera cannot see you clearly',
      MountIssue.faceTooSmall => 'Move the phone closer',
      MountIssue.faceOffCenter =>
        'Keep your full face in view for reliable detection',
    };
  }
}

/// Continuously judges phone-mount/environment quality from a rolling window of
/// frame observations and reports the single highest-priority active issue.
///
/// Uses fraction-based hysteresis: an issue turns on once it's bad for
/// [activateFraction] of the window, and only clears once it drops below
/// [deactivateFraction], so the warning bar doesn't flicker.
class MountQualityMonitor {
  MountQualityMonitor({
    this.window = const Duration(seconds: 3),
    this.clearGrace = const Duration(milliseconds: 500),
    this.activateFraction = 0.6,
    this.deactivateFraction = 0.3,
    this.minSamples = 3,
    this.darkThreshold = 0.18,
    this.brightThreshold = 0.92,
    this.minFaceFraction = 0.04,
    this.minEyeOpenVariation = 0.08,
    this.noBlinkTimeout = const Duration(seconds: 30),
    this.unstableVibration = 4.0,
    this.unstableClearVibration = 2.5,
  });

  final Duration window;

  /// Once an issue is shown, clear it right away if it's been resolved for at
  /// least this long (e.g. the face reappeared), instead of waiting for its bad
  /// samples to age out of the window.
  final Duration clearGrace;

  final double activateFraction;
  final double deactivateFraction;
  final int minSamples;

  /// Average brightness below this (0..1) is too dark.
  final double darkThreshold;

  /// Average brightness above this (0..1) is washed out.
  final double brightThreshold;

  /// Face bounding-box area below this fraction of the frame is too small.
  final double minFaceFraction;

  /// How much the eye-open reading must move over [noBlinkTimeout] for the eyes
  /// to count as readable.
  ///
  /// A measure of variation, not of catching a blink, on purpose. Frames are
  /// sampled a few times a second while a blink lasts a couple hundred
  /// milliseconds, so most blinks fall between samples, and waiting to catch
  /// one flagged readable eyes as unreadable on any unlucky stretch. Sunglasses
  /// instead make ML Kit report a nearly constant value, and real eyes jitter
  /// frame to frame whether or not a blink is caught, so the spread separates
  /// the two without sampling the blink itself.
  final double minEyeOpenVariation;

  /// How long the reading may stay flat before the eyes count as unreadable.
  final Duration noBlinkTimeout;

  /// Accelerometer vibration (m/s² RMS) at or above which the mount counts as
  /// shaky. Well above ordinary road vibration on purpose: a mount that is
  /// already loose when the drive begins has to be caught too, so this can't be
  /// measured relative to how much the ride is currently shaking. Raised from
  /// 1.4 after that value false-fired throughout a drive.
  final double unstableVibration;

  /// Below this the shaky-mount warning clears (hysteresis).
  final double unstableClearVibration;

  final List<_Sample> _samples = [];
  MountIssue _current = MountIssue.none;
  double _lastVibration = 0;
  double? _eyeOpenLow;
  double? _eyeOpenHigh;
  DateTime? _eyeVariationAt;

  MountIssue get quality => _current;

  void record(FaceObservation o, {double vibration = 0}) {
    _lastVibration = vibration;
    final brightness = o.frameBrightness;
    final bounds = o.faceBoundsFraction;
    final left = o.leftEyeOpenProbability;
    final right = o.rightEyeOpenProbability;

    // Eye readability: a visible face whose eye-open reading never moves means
    // the eyes aren't really being measured. That's sunglasses, which ML Kit
    // reports as steadily open.
    // Tracks how long the reading has stayed within a narrow band rather than
    // waiting to catch a blink. Frames are sampled a few times a second and a
    // blink lasts a couple hundred milliseconds, so most blinks fall between
    // samples, and waiting for one flagged readable eyes as unreadable on any
    // unlucky stretch. Real eyes wander frame to frame regardless.
    if (!o.faceVisible || left == null || right == null) {
      _eyeOpenLow = null;
      _eyeOpenHigh = null;
      _eyeVariationAt = null;
    } else {
      // Both eyes together: sunglasses hold both steady, and a real blink moves
      // both.
      final open = (left + right) / 2;
      _eyeVariationAt ??= o.timestamp;
      _eyeOpenLow =
          _eyeOpenLow == null || open < _eyeOpenLow! ? open : _eyeOpenLow;
      _eyeOpenHigh =
          _eyeOpenHigh == null || open > _eyeOpenHigh! ? open : _eyeOpenHigh;
      if (_eyeOpenHigh! - _eyeOpenLow! >= minEyeOpenVariation) {
        // The reading moved enough to prove the eyes are being measured. Start
        // a fresh band from here.
        _eyeVariationAt = o.timestamp;
        _eyeOpenLow = open;
        _eyeOpenHigh = open;
      }
    }

    final variationAt = _eyeVariationAt;
    final eyesUnreadable = (o.faceVisible && left == null && right == null) ||
        (o.faceVisible &&
            variationAt != null &&
            o.timestamp.difference(variationAt) >= noBlinkTimeout);

    _samples.add(
      _Sample(
        at: o.timestamp,
        noFace: !o.faceVisible,
        eyesUnreadable: eyesUnreadable,
        badLight: brightness != null &&
            (brightness < darkThreshold || brightness > brightThreshold),
        tooSmall: o.faceVisible && bounds != null && bounds < minFaceFraction,
        offCenter: o.faceVisible && o.faceNearEdge,
      ),
    );
    final cutoff = o.timestamp.subtract(window);
    _samples.removeWhere((s) => s.at.isBefore(cutoff));
    _current = _evaluate();
  }

  /// Whether the phone is shaking hard enough to call the mount unstable.
  bool get _vibrationIsUnstable {
    final threshold = _current == MountIssue.unstable
        ? unstableClearVibration
        : unstableVibration;
    return _lastVibration >= threshold;
  }

  static const List<MountIssue> _priority = [
    MountIssue.noFace,
    MountIssue.eyesNotReadable,
    MountIssue.unstable,
    MountIssue.lowVisibility,
    MountIssue.faceTooSmall,
    MountIssue.faceOffCenter,
  ];

  MountIssue _evaluate() {
    final n = _samples.length;
    if (n < minSamples) {
      return MountIssue.none;
    }

    for (final issue in _priority) {
      if (issue == MountIssue.unstable) {
        if (_vibrationIsUnstable) {
          return MountIssue.unstable;
        }
        continue;
      }
      // Skip anything that's fine right now (no bad sample within the last
      // [clearGrace]) so a fixed problem clears immediately instead of
      // lingering on its stale window.
      if (_recentlyClear(issue)) {
        continue;
      }
      final fraction = _samples.where((s) => _isBad(issue, s)).length / n;
      final threshold =
          _current == issue ? deactivateFraction : activateFraction;
      if (fraction >= threshold) {
        return issue;
      }
    }
    return MountIssue.none;
  }

  bool _recentlyClear(MountIssue issue) {
    final cutoff = _samples.last.at.subtract(clearGrace);
    final recent = _samples.where((s) => !s.at.isBefore(cutoff));
    return recent.isNotEmpty && !recent.any((s) => _isBad(issue, s));
  }

  bool _isBad(MountIssue issue, _Sample s) {
    return switch (issue) {
      MountIssue.none => false,
      MountIssue.noFace => s.noFace,
      MountIssue.eyesNotReadable => s.eyesUnreadable,
      MountIssue.unstable => false,
      MountIssue.lowVisibility => s.badLight,
      MountIssue.faceTooSmall => s.tooSmall,
      MountIssue.faceOffCenter => s.offCenter,
    };
  }

  void reset() {
    _samples.clear();
    _eyeOpenLow = null;
    _eyeOpenHigh = null;
    _eyeVariationAt = null;
    _current = MountIssue.none;
    _lastVibration = 0;
  }
}

class _Sample {
  _Sample({
    required this.at,
    required this.noFace,
    required this.eyesUnreadable,
    required this.badLight,
    required this.tooSmall,
    required this.offCenter,
  });

  final DateTime at;
  final bool noFace;
  final bool eyesUnreadable;
  final bool badLight;
  final bool tooSmall;
  final bool offCenter;
}
