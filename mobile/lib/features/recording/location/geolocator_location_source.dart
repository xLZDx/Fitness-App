// Geolocator adapter of the location seam (S04 design 2.3, decision D-1
// option A). This is the ONE file allowed to import a location package
// (S04-R-003).
//
// NOTE: `geolocator` is not yet declared in `mobile/pubspec.yaml`, so nothing
// may import this file until lane R2 adds the dependency and the plugin
// field names (AndroidSettings / ForegroundNotificationConfig, and that
// `Position.speed` is -1 / 0 when unavailable) are verified against the version
// that resolves.
//
// All stream lifecycle logic (serialized setInterval/stop, no awaited close in
// onCancel) lives in the plugin-free `StreamLocationSource` and is unit tested
// there; this file only builds the plugin stream.

// (integration 2026-10-20: this line lost its leading // on phase2/s04; restored) import a location package (S04-R-003). The
// extension keeps it out of the Dart analysis until the dependency exists.
//
// Verify against the version that actually resolves before renaming (design 2.3
// first steps 2 and 4): AndroidSettings / ForegroundNotificationConfig field
// names, and that `Position.speed` is -1 / 0 when unavailable.
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
