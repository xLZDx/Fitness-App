/// GPX 1.1 export of an [ActivitySession] (S02 design 7, 7.1; GPS-PRIV-051).
/// A pure function: no file writing, no sharing, no dart:io, no Flutter.
///
/// - One `trk` with one `trkseg`; one `trkpt` per GPS sample with `lat`, `lon`,
///   `ele` (nearest altitude sample within 5 s, when the session has one) and
///   `time` (session start plus the sample offset, UTC, strictly increasing).
/// - [GpxAudience.owner] is the full series (GPS-PRIV-051) and carries heart
///   rate in the Garmin TrackPointExtension when present: it is the user's own
///   data on their own device. [GpxAudience.shared] drops the first and last
///   `privacy.routeTrimMeters` of the route and never carries heart rate.
/// - A session without usable geometry (indoor, no GPS stream, or a shared
///   export trimmed to nothing) yields [GpxNoGeometry]: no file, no invented
///   points, no empty track (design DQ-3).
/// - Laps have no GPX 1.1 representation; they are in the FIT export.
library;

import 'activity_merger.dart' show haversineMeters;
import 'activity_session.dart';
import 'export_sampling.dart';
import 'sample_stream.dart';

/// Who receives the file; decides route trimming and heart rate.
enum GpxAudience { owner, shared }

/// Typed result of [GpxEncoder.encode].
sealed class GpxResult {
  const GpxResult();
}

/// The encoded document.
class GpxDocument extends GpxResult {
  const GpxDocument(this.xml, {required this.pointCount});

  final String xml;

  /// Number of `trkpt` elements written.
  final int pointCount;
}

/// There is nothing to export as a route.
class GpxNoGeometry extends GpxResult {
  const GpxNoGeometry();
}

class GpxEncoder {
  const GpxEncoder._();

  static const String creator = 'Fitness App';

  /// Encodes [session]. Never throws for a valid session.
  static GpxResult encode(
    ActivitySession session, {
    GpxAudience audience = GpxAudience.owner,
  }) {
    final gps = session.streams[StreamKind.gps];
    if (gps == null ||
        gps.isEmpty ||
        gps.lats.length != gps.length ||
        gps.lons.length != gps.length) {
      return const GpxNoGeometry();
    }
    final keep = audience == GpxAudience.owner
        ? List<int>.generate(gps.length, (i) => i)
        : _trimmedIndexes(gps, session.privacy.routeTrimMeters);
    if (keep.isEmpty) return const GpxNoGeometry();

    final altitude = session.streams[StreamKind.altitude];
    final heartRate =
        audience == GpxAudience.owner ? session.streams[StreamKind.heartRate] : null;
    final hasHr = heartRate != null && !heartRate.isEmpty;

    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..write('<gpx version="1.1" creator="${_esc(creator)}" '
          'xmlns="http://www.topografix.com/GPX/1/1" '
          'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ')
      ..write(hasHr
          ? 'xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1" '
          : '')
      ..writeln('xsi:schemaLocation="http://www.topografix.com/GPX/1/1 '
          'http://www.topografix.com/GPX/1/1/gpx.xsd">')
      ..writeln('  <metadata>')
      ..writeln('    <name>${_esc(session.sport.name)}</name>')
      ..writeln('    <time>${_time(session, 0)}</time>')
      ..writeln('  </metadata>')
      ..writeln('  <trk>')
      ..writeln('    <name>${_esc(session.sport.name)}</name>')
      ..writeln('    <type>${_esc(session.sport.name)}</type>')
      ..writeln('    <trkseg>');

    for (final i in keep) {
      final offset = gps.offsetsMs[i];
      b.write('      <trkpt lat="${_deg(gps.lats[i])}" lon="${_deg(gps.lons[i])}">');
      final ele = nearestStreamValue(altitude, offset);
      if (ele != null) b.write('<ele>${ele.toStringAsFixed(2)}</ele>');
      b.write('<time>${_time(session, offset)}</time>');
      if (hasHr) {
        final hr = nearestStreamValue(heartRate, offset);
        if (hr != null && hr > 0) {
          b.write('<extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>'
              '${hr.round()}</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions>');
        }
      }
      b.writeln('</trkpt>');
    }
    b
      ..writeln('    </trkseg>')
      ..writeln('  </trk>')
      ..writeln('</gpx>');
    return GpxDocument(b.toString(), pointCount: keep.length);
  }

  /// Indexes of the points at least [trimM] metres (along the route) from both
  /// ends. A non-positive [trimM] keeps everything.
  static List<int> _trimmedIndexes(SampleStream gps, double trimM) {
    final n = gps.length;
    if (!(trimM > 0)) return List<int>.generate(n, (i) => i);
    final along = List<double>.filled(n, 0);
    for (var i = 1; i < n; i++) {
      along[i] = along[i - 1] +
          haversineMeters(gps.lats[i - 1], gps.lons[i - 1], gps.lats[i], gps.lons[i]);
    }
    final total = along[n - 1];
    return [
      for (var i = 0; i < n; i++)
        if (along[i] >= trimM && total - along[i] >= trimM) i,
    ];
  }

  /// Fixed-point degrees (GPX `decimal`: no exponent notation), about 1 mm.
  static String _deg(double v) => v.toStringAsFixed(8);

  static String _time(ActivitySession s, int offsetMs) => s.startUtc
      .add(Duration(milliseconds: offsetMs))
      .toUtc()
      .toIso8601String();

  static String _esc(String v) => v
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
