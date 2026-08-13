/// How long a look away from the road is tolerated before it counts as a
/// distraction.
///
/// A shorter limit catches more, but also flags more ordinary driving. A
/// thorough shoulder check can take a couple of seconds, so this is the
/// driver's own trade-off to make rather than a fixed number.
enum GlanceSensitivity {
  safest(Duration(milliseconds: 1500)),
  lenient(Duration(milliseconds: 2500)),
  lax(Duration(milliseconds: 3500));

  const GlanceSensitivity(this.maxGlanceDuration);

  /// How long a glance away may last at this setting.
  final Duration maxGlanceDuration;

  String get label {
    return switch (this) {
      GlanceSensitivity.safest => 'Safest',
      GlanceSensitivity.lenient => 'Lenient',
      GlanceSensitivity.lax => 'Lax',
    };
  }

  String get description {
    return switch (this) {
      GlanceSensitivity.safest =>
        'Warns after 1.5s away from the road. Catches the most, but may flag '
            'long shoulder checks.',
      GlanceSensitivity.lenient =>
        'Warns after 2.5s away from the road. A balance for everyday driving.',
      GlanceSensitivity.lax =>
        'Warns after 3.5s away from the road. Fewest warnings, and the slowest '
            'to react.',
    };
  }

  /// Seconds, for compact display (e.g. "1.5s").
  String get secondsLabel =>
      '${(maxGlanceDuration.inMilliseconds / 1000).toStringAsFixed(1)}s';
}
