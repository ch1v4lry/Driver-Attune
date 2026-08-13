import 'package:flutter/foundation.dart';

import '../distraction_detection/driver_state.dart';
import '../mount_quality/mount_quality_monitor.dart';
import 'driving_session_summary.dart';

enum _RecordBucket { distracted, attentive, ignored }

/// Accumulates lifetime totals and completed driving-session summaries.
///
/// A session begins on the first confirmed-moving sample. Stopped samples pause
/// its counters without ending it. The owner ends it when Driving mode turns
/// off. All data remains in memory until persisted by [DrivingRecordStore].
class DrivingRecord extends ChangeNotifier {
  DrivingRecord({bool enabled = true}) : _enabled = enabled;

  static const Duration _maxSampleGap = Duration(seconds: 2);
  static const Duration _minNotifyInterval = Duration(seconds: 1);
  static const Duration minimumSessionDuration = Duration(minutes: 1);
  static const int _maxSavedSessions = 100;

  Duration _distracted = Duration.zero;
  Duration _attentive = Duration.zero;
  final List<DrivingSessionSummary> _sessions = [];
  _ActiveSession? _activeSession;
  bool _enabled;
  bool _enabledChangedSinceCreation = false;
  DateTime? _lastAt;
  _RecordBucket? _lastBucket;
  DriverState? _lastState;
  MountIssue _lastQuality = MountIssue.none;
  bool _lastSampleWasMoving = false;
  DriverState? _lastEventState;
  DateTime? _lastNotifiedAt;

  Duration get distractedDuration => _distracted;
  Duration get attentiveDuration => _attentive;
  Duration get totalDuration => _distracted + _attentive;
  List<DrivingSessionSummary> get sessions =>
      List<DrivingSessionSummary>.unmodifiable(_sessions);
  DrivingSessionSummary? get latestSession =>
      _sessions.isEmpty ? null : _sessions.first;
  bool get hasActiveSession => _activeSession != null;

  double get distractedFraction {
    final total = totalDuration.inMilliseconds;
    if (total == 0) {
      return 0;
    }
    return _distracted.inMilliseconds / total;
  }

  bool get enabled => _enabled;
  set enabled(bool value) {
    if (value == _enabled) {
      return;
    }
    _enabled = value;
    _enabledChangedSinceCreation = true;
    if (!value) {
      endSession(at: _lastAt ?? DateTime.now());
    }
    _resetSample();
    notifyListeners();
  }

  /// Merges persisted values into changes made while asynchronous loading ran.
  void restore({
    required Duration distracted,
    required Duration attentive,
    bool? enabled,
    List<DrivingSessionSummary> sessions = const [],
  }) {
    _distracted += distracted;
    _attentive += attentive;
    final knownStarts = _sessions.map((session) => session.startedAt).toSet();
    _sessions.addAll(
      sessions.where((session) => knownStarts.add(session.startedAt)),
    );
    _sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    if (_sessions.length > _maxSavedSessions) {
      _sessions.removeRange(_maxSavedSessions, _sessions.length);
    }
    if (enabled != null && !_enabledChangedSinceCreation) {
      _enabled = enabled;
    }
    notifyListeners();
  }

  /// Adds an inferred interval of possible phone use while the app was
  /// backgrounded.
  ///
  /// The camera and motion services are suspended during this interval, so it
  /// must not increase confirmed-moving, reliable-observation, or all-time
  /// attentive/distracted durations.
  void recordPhoneUse(Duration duration) {
    if (!_enabled || duration <= Duration.zero) {
      return;
    }
    final active = _activeSession;
    if (active == null) {
      return;
    }
    active.possiblePhoneUseDuration += duration;
    _resetSample();
    notifyListeners();
  }

  /// Records the current signal. [isDriving] means confirmed vehicle movement,
  /// not merely that Driving mode is switched on.
  void update({
    required DriverState state,
    required DateTime at,
    required bool isDriving,
    MountIssue quality = MountIssue.none,
  }) {
    if (!_enabled) {
      _resetSample();
      return;
    }

    final lastAt = _lastAt;
    if (lastAt != null && _lastSampleWasMoving) {
      final delta = at.difference(lastAt);
      if (delta > Duration.zero && delta <= _maxSampleGap) {
        _recordInterval(delta, at);
      }
    }

    if (isDriving) {
      _activeSession ??= _ActiveSession(startedAt: at);
      if (state != _lastEventState) {
        if (state == DriverState.drowsy) {
          _activeSession!.drowsinessEventCount++;
        } else if (state == DriverState.lookingAway) {
          _activeSession!.attentionReminderCount++;
        }
      }
      _lastEventState = state;
    }

    _lastAt = at;
    _lastSampleWasMoving = isDriving;
    _lastState = state;
    _lastQuality = quality;
    _lastBucket = isDriving ? _bucketFor(state) : null;
  }

  /// Ends the drive. Short stops never call this; they only pause accumulation.
  void endSession({required DateTime at}) {
    final active = _activeSession;
    _activeSession = null;
    _resetSample();
    _lastEventState = null;
    if (active == null || active.movingDuration < minimumSessionDuration) {
      return;
    }
    _sessions.insert(0, active.finish(at));
    if (_sessions.length > _maxSavedSessions) {
      _sessions.removeRange(_maxSavedSessions, _sessions.length);
    }
    notifyListeners();
  }

  void clear() {
    _distracted = Duration.zero;
    _attentive = Duration.zero;
    _sessions.clear();
    _activeSession = null;
    _resetSample();
    _lastEventState = null;
    notifyListeners();
  }

  void _recordInterval(Duration duration, DateTime at) {
    final lastBucket = _lastBucket;
    if (lastBucket == _RecordBucket.distracted) {
      _distracted += duration;
      _maybeNotify(at);
    } else if (lastBucket == _RecordBucket.attentive) {
      _attentive += duration;
      _maybeNotify(at);
    }

    final active = _activeSession;
    final state = _lastState;
    if (active == null || state == null) {
      return;
    }
    active.movingDuration += duration;

    final faceMissing = state == DriverState.faceNotVisible ||
        _lastQuality == MountIssue.noFace;
    if (faceMissing) {
      active.faceNotVisibleDuration += duration;
      return;
    }
    if (_lastQuality != MountIssue.none) {
      active.lowQualityDuration += duration;
      return;
    }
    if (state == DriverState.unknown) {
      return;
    }

    active.reliableObservationDuration += duration;
    if (lastBucket == _RecordBucket.attentive) {
      active.attentiveDuration += duration;
    }
    if (state == DriverState.lookingAway) {
      active.lookingAwayDuration += duration;
    }
  }

  void _resetSample() {
    _lastAt = null;
    _lastBucket = null;
    _lastState = null;
    _lastQuality = MountIssue.none;
    _lastSampleWasMoving = false;
  }

  void _maybeNotify(DateTime at) {
    final last = _lastNotifiedAt;
    if (last == null || at.difference(last) >= _minNotifyInterval) {
      _lastNotifiedAt = at;
      notifyListeners();
    }
  }

  static _RecordBucket _bucketFor(DriverState state) {
    return switch (state) {
      DriverState.lookingAway ||
      DriverState.eyesClosed ||
      DriverState.drowsy ||
      DriverState.usingPhone =>
        _RecordBucket.distracted,
      // A brief mirror/head check is normal driving. Yawning is retained in the
      // legacy attentive total but is counted separately as an event elsewhere.
      DriverState.attentive ||
      DriverState.yawning ||
      DriverState.glancingAway =>
        _RecordBucket.attentive,
      DriverState.unknown ||
      DriverState.faceNotVisible =>
        _RecordBucket.ignored,
    };
  }
}

class _ActiveSession {
  _ActiveSession({required this.startedAt});

  final DateTime startedAt;
  Duration movingDuration = Duration.zero;
  Duration reliableObservationDuration = Duration.zero;
  Duration attentiveDuration = Duration.zero;
  Duration lookingAwayDuration = Duration.zero;
  int drowsinessEventCount = 0;
  int attentionReminderCount = 0;
  Duration possiblePhoneUseDuration = Duration.zero;
  Duration faceNotVisibleDuration = Duration.zero;
  Duration lowQualityDuration = Duration.zero;

  DrivingSessionSummary finish(DateTime endedAt) => DrivingSessionSummary(
        startedAt: startedAt,
        endedAt: endedAt.isBefore(startedAt) ? startedAt : endedAt,
        movingDuration: movingDuration,
        reliableObservationDuration: reliableObservationDuration,
        attentiveDuration: attentiveDuration,
        lookingAwayDuration: lookingAwayDuration,
        drowsinessEventCount: drowsinessEventCount,
        attentionReminderCount: attentionReminderCount,
        possiblePhoneUseDuration: possiblePhoneUseDuration,
        faceNotVisibleDuration: faceNotVisibleDuration,
        lowQualityDuration: lowQualityDuration,
      );
}
