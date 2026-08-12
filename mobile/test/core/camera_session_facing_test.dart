import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/camera/camera_session.dart';

/// A session that reports itself running without a platform camera behind it.
///
/// [CameraSession.isRunning] is a getter over a private field that only a real
/// `_open()` ever sets, so the reopen path — the interesting half of a camera
/// switch — is unreachable from a host test otherwise. Overriding the getter
/// reaches it without adding a test-only seam to production code.
class _FakeRunning extends CameraSession {
  _FakeRunning({super.facing});

  bool running = true;
  final List<String> calls = [];

  @override
  bool get isRunning => running;

  @override
  Future<void> start({bool requestPermission = false}) async {
    calls.add('start(request=$requestPermission)');
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }
}

void main() {
  group('which way the camera points', () {
    test('defaults to the back lens, and takes an explicit one', () {
      expect(CameraSession().facing, SessionFacing.back);
      expect(CameraSession(facing: SessionFacing.front).facing,
          SessionFacing.front);
    });

    test('switching an idle session touches no camera', () async {
      final session = CameraSession();
      await session.setFacing(SessionFacing.front);

      expect(session.facing, SessionFacing.front);
      expect(session.isRunning, isFalse,
          reason: 'recording a preference must not open anything');
      expect(session.surface.value, isNull);
    });

    test('flip goes both ways', () async {
      final session = CameraSession();
      await session.flip();
      expect(session.facing, SessionFacing.front);
      await session.flip();
      expect(session.facing, SessionFacing.back);
    });

    test('asking for the camera that is already open does nothing', () async {
      final session = _FakeRunning(facing: SessionFacing.back);
      await session.setFacing(SessionFacing.back);

      expect(session.calls, isEmpty,
          reason: 'a no-op switch that still tore the camera down would drop '
              'frames for no reason at all');
    });

    test('switching a running session stops before it starts', () async {
      final session = _FakeRunning(facing: SessionFacing.back);
      await session.setFacing(SessionFacing.front);

      expect(session.calls, ['stop', 'start(request=false)'],
          reason: 'a CameraController is bound to one physical camera for its '
              'lifetime, so the old one has to go first');
    });

    test('a switch never raises the permission dialog', () async {
      // The camera was running a moment ago, so permission is already granted.
      // Asking again mid-session would put a system dialog over a viewfinder.
      final session = _FakeRunning(facing: SessionFacing.back);
      await session.setFacing(SessionFacing.front);

      expect(session.calls.last, 'start(request=false)');
    });

    test('overlapping switches run one after another, not on top of each other',
        () async {
      // Two quick taps. Each swap is a stop AND a start; interleaved, that is
      // the same orphaned-controller failure `start`'s own re-entrancy guard
      // exists to stop, one level up.
      final session = _FakeRunning(facing: SessionFacing.back);

      final first = session.setFacing(SessionFacing.front);
      final second = session.setFacing(SessionFacing.back);
      await Future.wait([first, second]);

      expect(session.calls, [
        'stop',
        'start(request=false)',
        'stop',
        'start(request=false)',
      ]);
      expect(session.facing, SessionFacing.back);
    });

    test('a switch that failed rolls back, so the retry really retries',
        () async {
      // Both halves matter. Without the rollback the session claims the lens
      // it never opened — so the control mislabels itself, AND an identical
      // retry hits the "already there" check and returns without trying,
      // which makes the button permanently dead after one failure.
      final session = _ThrowingOnce(facing: SessionFacing.back);

      await expectLater(
          session.setFacing(SessionFacing.front), throwsA(isA<StateError>()));
      expect(session.facing, SessionFacing.back,
          reason: 'nothing opened, so nothing changed');

      // The chain's own link swallows the failure so later swaps still run;
      // the caller above still saw it.
      await session.setFacing(SessionFacing.front);

      expect(session.facing, SessionFacing.front);
      expect(session.starts, 2);
    });

    test('activeFacing is what a widget can rebuild on', () async {
      final session = CameraSession();
      final seen = <SessionFacing>[];
      session.activeFacing.addListener(() => seen.add(session.facing));

      await session.flip();
      await session.flip();

      expect(seen, [SessionFacing.front, SessionFacing.back],
          reason: 'a getter cannot tell a switch control that the camera it '
              'is labelling has changed');
    });
  });
}

class _ThrowingOnce extends CameraSession {
  _ThrowingOnce({super.facing});

  int starts = 0;

  @override
  bool get isRunning => true;

  @override
  Future<void> stop() async {}

  @override
  Future<void> start({bool requestPermission = false}) async {
    starts++;
    if (starts == 1) throw StateError('camera held by another app');
  }
}
