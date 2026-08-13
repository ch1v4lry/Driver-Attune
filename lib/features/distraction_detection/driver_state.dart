enum DriverState {
  unknown,
  attentive,
  faceNotVisible,
  lookingAway,

  /// A short look away from the road: a mirror, a head check, the instruments.
  /// Normal driving, so long as it stays short. Escalates to [lookingAway] once
  /// held past the glance limit.
  glancingAway,

  eyesClosed,
  yawning,
  usingPhone,
  drowsy,
}

extension DriverStateLabel on DriverState {
  String get label {
    return switch (this) {
      DriverState.unknown => 'Unknown',
      DriverState.attentive => 'Attentive',
      DriverState.faceNotVisible => 'Face not visible',
      DriverState.lookingAway => 'Looking away',
      DriverState.glancingAway => 'Glancing away',
      DriverState.eyesClosed => 'Eyes closed',
      DriverState.yawning => 'Yawning',
      DriverState.usingPhone => 'Using phone',
      DriverState.drowsy => 'Drowsy',
    };
  }
}
