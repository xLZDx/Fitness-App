import 'dart:async';

import 'permission_service.dart';

/// Result of one revocation check.
enum RevocationCheck {
  /// Precise location is still granted.
  stillGranted,

  /// Permission is no longer precise-granted (revoked or downgraded).
  revoked,

  /// The platform read failed; nothing can be concluded. The caller must not
  /// treat this as revoked (a transient channel error would otherwise stop a
  /// healthy recording) and re-checks on the next tick or stream error.
  unknown,
}

/// Detects loss of location permission during a recording (S04-19, S04-R-024).
///
/// The Study found no documented revocation callback, so polling the
/// [PermissionService] is the portable mechanism (S04 design 6.1). Two entry
/// points:
/// - [check]: one read, for the controller to call per fix, on resume and on a
///   location stream error.
/// - [start]/[stop] with [onRevoked]: a timer so a stationary user with no
///   incoming fixes is still detected within [period] (default 1 s, inside the
///   2 s bound of S04-19 AC-1).
///
/// This class only detects. Stopping collection, sealing the recording and the
/// Keep/Delete decision belong to the recorder controller and journal lanes.
class PermissionRevocationWatcher {
  PermissionRevocationWatcher(
    this._permissions, {
    this.period = const Duration(seconds: 1),
  });

  final PermissionService _permissions;
  final Duration period;

  final StreamController<void> _revoked = StreamController<void>.broadcast();
  Timer? _timer;
  bool _checking = false;
  bool _fired = false;

  /// Emits once per [start] when revocation is detected by the timer.
  Stream<void> get onRevoked => _revoked.stream;

  /// True while the timer is running.
  bool get isRunning => _timer != null;

  /// One permission read, classified. Never throws.
  Future<RevocationCheck> check() async {
    try {
      final status = await _permissions.locationStatus();
      return status.allowsRecording
          ? RevocationCheck.stillGranted
          : RevocationCheck.revoked;
    } catch (_) {
      // Content-free by design: the exception text is not propagated.
      return RevocationCheck.unknown;
    }
  }

  /// Starts periodic checking. Safe to call twice (second call is a no-op).
  void start() {
    if (_timer != null) return;
    _fired = false;
    _timer = Timer.periodic(period, (_) => _tick());
  }

  Future<void> _tick() async {
    // Skip a tick while a read is still in flight: no overlapping checks.
    if (_checking || _fired) return;
    _checking = true;
    try {
      if (await check() == RevocationCheck.revoked && _timer != null) {
        _fired = true;
        _revoked.add(null);
      }
    } finally {
      _checking = false;
    }
  }

  /// Stops periodic checking. Idempotent.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Stops the timer and closes [onRevoked].
  Future<void> dispose() async {
    stop();
    await _revoked.close();
  }
}
