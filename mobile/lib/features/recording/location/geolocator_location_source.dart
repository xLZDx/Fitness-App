// Geolocator adapter of the location seam (S04 design 2.3, decision D-1
// option A). This is the ONE file allowed to import a location package
// (S04-R-003).
//
// `geolocator` ^13.0.4 is declared in `mobile/pubspec.yaml`, and this is the
// only file under `mobile/lib` allowed to import a location package.
//
// The plugin field names used below (AndroidSettings /
// ForegroundNotificationConfig, and that `Position.speed` is negative when
// unavailable) must be re-verified against the version that actually resolves
// whenever the dependency constraint changes.
//
// All stream lifecycle logic (serialized setInterval/stop, no awaited close in
// onCancel) lives in the plugin-free `StreamLocationSource` and is unit tested
// there; this file only builds the plugin stream.

import 'package:geolocator/geolocator.dart';

import 'fix.dart';
import 'location_source.dart';
import 'stream_location_source.dart';

class GeolocatorLocationSource extends StreamLocationSource {
  GeolocatorLocationSource() : super(_positions);

  static Stream<Fix> _positions(LocationRequest request, int intervalSeconds) {
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: request.distanceFilterMeters,
      intervalDuration: Duration(seconds: intervalSeconds),
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: request.notificationTitle ?? '',
        notificationText: request.notificationText ?? '',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
    return Geolocator.getPositionStream(locationSettings: settings).map(_toFix);
  }

  static Fix _toFix(Position p) => Fix(
        timeUtcMs: p.timestamp.toUtc().millisecondsSinceEpoch,
        latitude: p.latitude,
        longitude: p.longitude,
        accuracyMeters: p.accuracy,
        altitudeMeters: p.altitude,
        speedMps: p.speed < 0 ? null : p.speed,
      );
}
