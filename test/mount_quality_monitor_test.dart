import 'package:driver_attune/features/distraction_detection/face_observation.dart';
import 'package:driver_attune/features/mount_quality/mount_quality_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FaceObservation obs(
    DateTime at, {
    bool faceVisible = true,
    double? leftEye = 0.9,
    double? rightEye = 0.9,
    double? brightness = 0.5,
    double? bounds = 0.15,
    bool nearEdge = false,
  }) {
    return FaceObservation(
      timestamp: at,
      faceVisible: faceVisible,
      leftEyeOpenProbability: leftEye,
      rightEyeOpenProbability: rightEye,
      frameBrightness: brightness,
      faceBoundsFraction: bounds,
      faceNearEdge: nearEdge,
    );
  }

  void feed(
    MountQualityMonitor m,
    int n,
    FaceObservation Function(DateTime) build,
  ) {
    var t = DateTime(2026, 1, 1);
    for (var i = 0; i < n; i++) {
      m.record(build(t));
      t = t.add(const Duration(milliseconds: 300));
    }
  }

  test('good frames report no issue', () {
    final m = MountQualityMonitor();
    feed(m, 10, (t) => obs(t));
    expect(m.quality, MountIssue.none);
  });

  test('no issue before enough samples', () {
    final m = MountQualityMonitor(minSamples: 6);
    feed(m, 3, (t) => obs(t, faceVisible: false));
    expect(m.quality, MountIssue.none);
  });

  test('face missing most of the window -> noFace', () {
    final m = MountQualityMonitor();
    feed(m, 10, (t) => obs(t, faceVisible: false));
    expect(m.quality, MountIssue.noFace);
  });

  test('face visible but eyes unreadable (null) -> eyesNotReadable', () {
    final m = MountQualityMonitor();
    feed(m, 10, (t) => obs(t, leftEye: null, rightEye: null));
    expect(m.quality, MountIssue.eyesNotReadable);
  });

  test('eyes reported open but never blinking -> eyesNotReadable (sunglasses)',
      () {
    final m = MountQualityMonitor(noBlinkTimeout: const Duration(seconds: 12));
    var t = DateTime(2026, 1, 1);
    // ~14s of a visible face with the eyes reported wide open and never
    // dipping.
    for (var i = 0; i < 48; i++) {
      m.record(obs(t, leftEye: 0.95, rightEye: 0.9));
      t = t.add(const Duration(milliseconds: 300));
    }
    expect(m.quality, MountIssue.eyesNotReadable);
  });

  test('too dark or washed out -> lowVisibility', () {
    final dark = MountQualityMonitor();
    feed(dark, 10, (t) => obs(t, brightness: 0.05));
    expect(dark.quality, MountIssue.lowVisibility);

    final bright = MountQualityMonitor();
    feed(bright, 10, (t) => obs(t, brightness: 0.98));
    expect(bright.quality, MountIssue.lowVisibility);
  });

  test('tiny face -> faceTooSmall', () {
    final m = MountQualityMonitor();
    feed(m, 10, (t) => obs(t, bounds: 0.01));
    expect(m.quality, MountIssue.faceTooSmall);
  });

  test('face near an edge -> faceOffCenter', () {
    final m = MountQualityMonitor();
    feed(m, 10, (t) => obs(t, nearEdge: true));
    expect(m.quality, MountIssue.faceOffCenter);
    expect(
      m.quality.message,
      'Keep your full face in view for reliable detection',
    );
  });

  test('no-face outranks other issues by priority', () {
    final m = MountQualityMonitor();
    feed(
      m,
      10,
      (t) => obs(t, faceVisible: false, brightness: 0.02),
    );
    expect(m.quality, MountIssue.noFace);
  });

  test('clears fast once the face is reliably back', () {
    final m = MountQualityMonitor();
    var t = DateTime(2026, 1, 1);
    void rec(FaceObservation o) {
      m.record(o);
      t = t.add(const Duration(milliseconds: 250));
    }

    for (var i = 0; i < 12; i++) {
      rec(obs(t, faceVisible: false));
    }
    expect(m.quality, MountIssue.noFace);

    // Face back and steady past the clear grace, clears without waiting the
    // whole window out.
    for (var i = 0; i < 4; i++) {
      rec(obs(t));
    }
    expect(m.quality, MountIssue.none);
  });

  test('a single good frame does not clear an active issue', () {
    final m = MountQualityMonitor();
    var t = DateTime(2026, 1, 1);
    void rec(FaceObservation o) {
      m.record(o);
      t = t.add(const Duration(milliseconds: 250));
    }

    for (var i = 0; i < 12; i++) {
      rec(obs(t, faceVisible: false));
    }
    expect(m.quality, MountIssue.noFace);

    rec(obs(t)); // a brief blip of one good frame
    rec(obs(t, faceVisible: false));
    expect(m.quality, MountIssue.noFace);
  });

  test('hard shaking -> unstable (shaky mount)', () {
    final m = MountQualityMonitor();
    var t = DateTime(2026, 1, 1);
    for (var i = 0; i < 8; i++) {
      m.record(obs(t), vibration: 6.0);
      t = t.add(const Duration(milliseconds: 250));
    }
    expect(m.quality, MountIssue.unstable);
  });

  test('a mount already loose at the start is still caught', () {
    // The reason this stays an absolute threshold: with a baseline-relative
    // measure, a mount that rattles from the first frame would fold its own
    // rattle into the baseline and never warn.
    final m = MountQualityMonitor();
    var t = DateTime(2026, 1, 1);
    for (var i = 0; i < 40; i++) {
      m.record(obs(t), vibration: 5.5);
      t = t.add(const Duration(milliseconds: 250));
    }
    expect(m.quality, MountIssue.unstable);
  });

  test('ordinary road vibration does not warn', () {
    final m = MountQualityMonitor();
    var t = DateTime(2026, 1, 1);
    // Normal driving shake, which used to trip the old 1.4 threshold and warn
    // for an entire drive.
    for (var i = 0; i < 40; i++) {
      m.record(obs(t), vibration: 2.0);
      t = t.add(const Duration(milliseconds: 250));
    }
    expect(m.quality, MountIssue.none);
  });

  test('low phone vibration -> no unstable warning', () {
    final m = MountQualityMonitor();
    var t = DateTime(2026, 1, 1);
    for (var i = 0; i < 8; i++) {
      m.record(obs(t), vibration: 0.2);
      t = t.add(const Duration(milliseconds: 250));
    }
    expect(m.quality, MountIssue.none);
  });

  test('a driver whose blinks never reach a fixed threshold still counts', () {
    // Wide eyes reading ~0.95 that dip to 0.4 on a blink: never below the old
    // fixed 0.35 line, so the eyes were wrongly reported unreadable.
    final m = MountQualityMonitor(noBlinkTimeout: const Duration(seconds: 10));
    var t = DateTime(2026, 1, 1);
    for (var i = 0; i < 60; i++) {
      final blinking = i % 12 == 0;
      m.record(
        obs(t, leftEye: blinking ? 0.4 : 0.95, rightEye: blinking ? 0.4 : 0.95),
      );
      t = t.add(const Duration(milliseconds: 250));
    }
    expect(m.quality, MountIssue.none);
  });

  test('eyes that never dip at all are still reported unreadable', () {
    final m = MountQualityMonitor(noBlinkTimeout: const Duration(seconds: 10));
    var t = DateTime(2026, 1, 1);
    for (var i = 0; i < 60; i++) {
      m.record(obs(t, leftEye: 0.95, rightEye: 0.95));
      t = t.add(const Duration(milliseconds: 250));
    }
    expect(m.quality, MountIssue.eyesNotReadable);
  });

  group('eye readability judges variation, not caught blinks', () {
    test('jittering eyes are readable even if no blink is ever sampled', () {
      // The real-world false flag: frames are sampled every few hundred ms and
      // a blink lasts ~150ms, so most blinks land between samples. These
      // readings never dip anywhere near a blink, but they do move, which is
      // what shows the eyes are actually being measured.
      final m =
          MountQualityMonitor(noBlinkTimeout: const Duration(seconds: 10));
      var t = DateTime(2026, 1, 1);
      const wander = [0.94, 0.88, 0.91, 0.83, 0.96, 0.86, 0.90, 0.79];
      for (var i = 0; i < 80; i++) {
        final v = wander[i % wander.length];
        m.record(obs(t, leftEye: v, rightEye: v));
        t = t.add(const Duration(milliseconds: 300));
      }

      expect(m.quality, MountIssue.none);
    });

    test('a perfectly flat reading is unreadable (sunglasses)', () {
      final m =
          MountQualityMonitor(noBlinkTimeout: const Duration(seconds: 10));
      var t = DateTime(2026, 1, 1);
      for (var i = 0; i < 80; i++) {
        m.record(obs(t, leftEye: 0.95, rightEye: 0.95));
        t = t.add(const Duration(milliseconds: 300));
      }

      expect(m.quality, MountIssue.eyesNotReadable);
    });

    test('a barely-moving reading is unreadable too', () {
      // Sunglasses do not give a bit-identical number every frame; they give a
      // number that hardly moves.
      final m =
          MountQualityMonitor(noBlinkTimeout: const Duration(seconds: 10));
      var t = DateTime(2026, 1, 1);
      const barely = [0.95, 0.96, 0.95, 0.97];
      for (var i = 0; i < 80; i++) {
        final v = barely[i % barely.length];
        m.record(obs(t, leftEye: v, rightEye: v));
        t = t.add(const Duration(milliseconds: 300));
      }

      expect(m.quality, MountIssue.eyesNotReadable);
    });

    test('nothing is concluded before a full window has elapsed', () {
      final m =
          MountQualityMonitor(noBlinkTimeout: const Duration(seconds: 30));
      var t = DateTime(2026, 1, 1);
      for (var i = 0; i < 20; i++) {
        m.record(obs(t, leftEye: 0.95, rightEye: 0.95));
        t = t.add(const Duration(milliseconds: 300));
      }

      // Only ~6s of history against a 30s window.
      expect(m.quality, MountIssue.none);
    });
  });
}
