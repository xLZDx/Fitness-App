import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:fitness_app/core/camera/camera_availability.dart';
import 'package:fitness_app/core/camera/camera_session.dart';

/// A gate whose `status()` the test can hold open, to model the real thing:
/// a permission decision the user sits on for seconds while the page keeps
/// arming itself from route changes and lifecycle callbacks.
class _SlowGate extends CameraPermissionGate {
  _SlowGate(this._status);

  final PermissionStatus _status;
  final Completer<void> release = Completer<void>();
  int statusCalls = 0;
  int requestCalls = 0;

  @override
  Future<PermissionStatus> status() async {
    statusCalls++;
    await release.future;
    return _status;
  }

  @override
  Future<PermissionStatus> request() async {
    requestCalls++;
    return _status;
  }
}

void main() {
  group('CameraSession.start re-entrancy', () {
    test('concurrent starts join one attempt instead of opening two cameras',
        () async {
      // The bug this pins: `_running` does not flip until the very end of a
      // successful open, and start() now awaits a permission dialog. Two
      // overlapping callers each built a CameraController over the field the
      // other was still initialising, orphaning the first — a leaked platform
      // camera with its indicator light on that no teardown path could reach.
      final gate = _SlowGate(PermissionStatus.denied);
      final session = CameraSession(permissions: gate);

      final first = session.start();
      final second = session.start();
      final third = session.start();
      gate.release.complete();

      // Denied, so all three land on the same typed refusal.
      for (final attempt in [first, second, third]) {
        await expectLater(attempt, throwsA(isA<CameraUnavailable>()));
      }
      expect(gate.statusCalls, 1,
          reason: 'the later callers must join the in-flight attempt, '
              'not run their own permission check and camera open');
    });

    test('a failed start does not wedge later attempts', () async {
      // The in-flight guard must clear on the failure path too, or one refusal
      // would make the retry button permanently inert.
      final gate = _SlowGate(PermissionStatus.denied);
      final session = CameraSession(permissions: gate);
      gate.release.complete();

      await expectLater(session.start(), throwsA(isA<CameraUnavailable>()));
      await expectLater(session.start(), throwsA(isA<CameraUnavailable>()));

      expect(gate.statusCalls, 2,
          reason: 'a second, sequential attempt must really run');
    });

    test('the permission prompt is opt-in per call', () async {
      final gate = _SlowGate(PermissionStatus.denied);
      final session = CameraSession(permissions: gate);
      gate.release.complete();

      await expectLater(session.start(), throwsA(isA<CameraUnavailable>()));
      expect(gate.requestCalls, 0,
          reason: 'automatic arming must never raise the system dialog');

      await expectLater(session.start(requestPermission: true),
          throwsA(isA<CameraUnavailable>()));
      expect(gate.requestCalls, 1);
    });

    test('a permanently-denied permission is never prompted for', () async {
      // The platform returns immediately without a dialog; asking anyway just
      // burns a call and teaches the UI nothing.
      final gate = _SlowGate(PermissionStatus.permanentlyDenied);
      final session = CameraSession(permissions: gate);
      gate.release.complete();

      await expectLater(
        session.start(requestPermission: true),
        throwsA(isA<CameraUnavailable>().having((e) => e.reason, 'reason',
            CameraUnavailableReason.permissionPermanentlyDenied)),
      );
      expect(gate.requestCalls, 0);
    });

    test('a throwing permission channel still yields a typed reason',
        () async {
      // MissingPluginException and friends must not escape as an untyped
      // crash past the whole typed-reason mechanism.
      final session = CameraSession(permissions: _ThrowingGate());

      await expectLater(
        session.start(),
        throwsA(isA<CameraUnavailable>().having((e) => e.reason, 'reason',
            CameraUnavailableReason.initializationFailed)),
      );
    });
  });
}

class _ThrowingGate extends CameraPermissionGate {
  @override
  Future<PermissionStatus> status() async =>
      throw Exception('MissingPluginException(camera permission)');
}
