/// One location fix delivered by a [LocationSource].
///
/// S04 design 2.2. A plain value: no plugin type crosses the location seam, so
/// the pipeline, journal and state machine never see a `Position`-style class
/// (S04-R-003).
///
/// Units are fixed here and must not be converted by adapters beyond what the
/// field names state: time in UTC milliseconds since the epoch, coordinates in
/// decimal degrees, accuracy and altitude in metres, speed in metres/second.
class Fix {
  const Fix({
    required this.timeUtcMs,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    this.altitudeMeters,
    this.speedMps,
  });

  /// Fix time, UTC milliseconds since the epoch.
  final int timeUtcMs;

  final double latitude;
  final double longitude;

  /// Horizontal accuracy radius, metres. Always present: the accuracy gate
  /// (S04-R-006) cannot judge a fix without it.
  final double accuracyMeters;

  /// Altitude in metres, or null when the platform did not report one.
  final double? altitudeMeters;

  /// Ground speed in metres/second, or null when the platform did not report
  /// one.
  final double? speedMps;

  @override
  bool operator ==(Object other) =>
      other is Fix &&
      other.timeUtcMs == timeUtcMs &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.accuracyMeters == accuracyMeters &&
      other.altitudeMeters == altitudeMeters &&
      other.speedMps == speedMps;

  @override
  int get hashCode => Object.hash(timeUtcMs, latitude, longitude,
      accuracyMeters, altitudeMeters, speedMps);

  /// Deliberately content-free: coordinates must never reach a log line
  /// (S04 design 12, privacy rules).
  @override
  String toString() => 'Fix(timeUtcMs: $timeUtcMs)';
}
