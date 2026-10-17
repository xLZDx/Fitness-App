// PENDING ADAPTER (not compiled): rename to `geolocator_location_source.dart`
// once lane R2 has added `geolocator` to `mobile/pubspec.yaml` and the package
// resolves against the pinned toolchain (S04 design 2.3, decision D-1 option A).
//
// This is the ONE file allowed to import a location package (S04-R-003). The
// extension keeps it out of the Dart analysis until the dependency exists.
//
// Verify against the version that actually resolves before renaming (design 2.3
// first steps 2 and 4): AndroidSettings / ForegroundNotificationConfig field
// names, and that `Position.speed` is -1 / 0 when unavailable.

import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'fix.dart';
import 'location_source.dart';

class GeolocatorLocationSource implements LocationSource {
  StreamController<Fix>? _out;
  StreamSubscription<Position>? _inner;
  LocationRequest? _request;

  @override
  int get activeSubscriptions => _out == null ? 0 : 1;

  /// The plugin gives no engine-detach signal (design 5.6); the platform study
  /// test T2 decides whether D-1 option A is acceptable.
  @override
  Stream<void> get engineDetached => const Stream<void>.empty();

  @override
  Stream<Fix> start(LocationRequest request) {
    if (_out != null) throw StateError('LocationSource already started');
    _request = request;
    final out = StreamController<Fix>(onCancel: stop);
    _out = out;
    _attach(request.intervalSeconds);
    return out.stream;
  }

  void _attach(int intervalSeconds) {
    final request = _request!;
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
    _inner = Geolocator.getPositionStream(locationSettings: settings).listen(
      (p) => _out?.add(_toFix(p)),
      onError: (Object e, StackTrace s) => _out?.addError(e, s),
    );
  }

  static Fix _toFix(Position p) => Fix(
        timeUtcMs: p.timestamp.toUtc().millisecondsSinceEpoch,
        latitude: p.latitude,
        longitude: p.longitude,
        accuracyMeters: p.accuracy,
        altitudeMeters: p.altitude,
        speedMps: p.speed < 0 ? null : p.speed,
      );

  /// The plugin cannot change the interval of a live stream, so the underlying
  /// stream is re-created while the outward stream (and its single counted
  /// subscription) stays the same.
  @override
  Future<void> setInterval(int seconds) async {
    if (_out == null) return;
    await _inner?.cancel();
    _attach(seconds);
  }

  @override
  Future<void> stop() async {
    final out = _out;
    _out = null;
    _request = null;
    final inner = _inner;
    _inner = null;
    await inner?.cancel();
    if (out != null && !out.isClosed) await out.close();
  }
}
