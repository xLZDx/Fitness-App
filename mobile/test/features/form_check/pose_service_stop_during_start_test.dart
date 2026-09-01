import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    as mlkit;

import 'package:fitness_app/core/camera/camera_availability.dart';
import 'package:fitness_app/core/camera/camera_session.dart';
import 'package:fitness_app/features/form_check/data/mlkit_pose_detector_service.dart';

/// The window between "the user asked for a camera" and "the camera is open".
///
/// It is one to two seconds on a real phone, and until 2026-09-01
/// `MlKitPoseDetectorService.stop()` did nothing at all inside it: its first
/// line was `if (!_initialised) return`, and `_initialised` does not flip until
/// `session.start()` has returned. So a stop arriving in that window released
/// nothing, the start went on to finish, and a live camera was left running
/// behind a screen the user had already left.
///
/// Reachable two ways, both of them ordinary: the Form Coach's back control is
/// on screen while the preview is still a spinner, and backgrounding the app
/// during the same window takes the identical path
/// (`form_check_page.dart`'s `didChangeAppLifecycleState`).
///
/// Found in review of the selection-screen gate, which is what put a back
/// control on that spinner in the first place. The first repair — an unbounded
/// `await` on the in-flight start — fixed the slow case and broke the HUNG one,
/// which GPT-PM caught: the page bounds its own start at 15 s and offers a
/// retry, so a teardown that waits longer turns a recoverable timeout into a
/// permanently dead screen. Both exits are pinned below.

/// A session whose `start()` hangs until the test says otherwise.
///
/// Subclassed rather than faked behind an interface because
/// `MlKitPoseDetectorService` takes a `CameraSession` directly, and the three
/// methods it calls on one are all overridable.
class _SlowSession extends CameraSession {
  _SlowSession() : super(facing: SessionFacing.front);

  /// One completer per `start()`, so a test can settle each attempt on its own.
  final opens = <Completer<void>>[];
  int stops = 0;

  int get starts => opens.length;

  @override
  Future<void> start({bool requestPermission = false}) {
    final c = Completer<void>();
    opens.add(c);
    return c.future;
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Stream<InputImage> frames() => const Stream.empty();
}

/// A session that coalesces concurrent opens onto ONE platform attempt, the way
/// the real [CameraSession.start] does (`camera_session.dart:211`).
///
/// The difference is not cosmetic and it is why this double exists: with a
/// fresh completer per call, a retry after a hung open looks like a second,
/// independent open — the opposite of production, where the retry JOINS the
/// attempt that hung. GPT-PM's round-2 review rejected a regression test whose
/// double bypassed exactly the lower-layer behaviour the code under test has to
/// survive.
class _CoalescingSession extends CameraSession {
  _CoalescingSession() : super(facing: SessionFacing.front);

  Completer<void>? _open;
  int starts = 0;
  int stops = 0;

  /// The single in-flight platform open, or null when none is pending.
  Completer<void>? get open => _open;

  @override
  Future<void> start({bool requestPermission = false}) {
    final pending = _open;
    if (pending != null) return pending.future;
    starts++;
    final c = Completer<void>();
    _open = c;
    return c.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    _open = null;
  }

  @override
  Stream<InputImage> frames() => const Stream.empty();
}

/// Counts its own closes. The real one reaches a method channel on `close()`,
/// so there is no other way to observe that a failed start released it.
class _CountingDetector extends mlkit.PoseDetector {
  _CountingDetector()
      : super(
          options: mlkit.PoseDetectorOptions(
            mode: mlkit.PoseDetectionMode.stream,
            model: mlkit.PoseDetectionModel.base,
          ),
        );

  int closes = 0;

  @override
  Future<void> close() async => closes++;
}

/// Short enough that a test does not sit through the production bound, long
/// enough to be a real wait rather than a zero-duration one that would settle
/// in the same microtask drain as the thing it is supposed to outlive.
const _shortWait = Duration(milliseconds: 20);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a stop that arrives while the camera is still opening still releases it',
      () async {
    final session = _SlowSession();
    final svc = MlKitPoseDetectorService(
        session: session, detectorFactory: _CountingDetector.new);

    // Asked for, not yet open. This is the state the old guard read as
    // "nothing to stop".
    final starting = svc.start();
    await Future<void>.delayed(Duration.zero);
    expect(session.stops, 0, reason: 'nothing has been released yet');

    // The user presses back, or the app goes to the background.
    final stopping = svc.stop();

    // The camera finishes opening a moment later, as it always would have.
    session.opens.single.complete();
    await starting;
    await stopping;

    expect(session.stops, 1,
        reason: 'the camera the user walked away from is released. Before the '
            'fix this was 0 and the camera stayed on');
  });

  test('an open that never returns does not wedge the service', () async {
    // The exit the first version of this fix broke. An unbounded wait here
    // leaves the page's `_stopping` pending forever, and the page awaits it
    // before every later start — so a platform open that hangs would turn the
    // 15 s timeout the coach explicitly recovers from into a dead screen.
    final session = _SlowSession();
    final svc = MlKitPoseDetectorService(
      session: session,
      detectorFactory: _CountingDetector.new,
      startSettleWait: _shortWait,
    );

    // Hangs: `session.start()`'s completer is never completed by anyone.
    unawaited(svc.start());
    await pumpEventQueue();
    expect(session.starts, 1);

    // The page has timed out and shown its retry card; the user presses back.
    await svc.stop().timeout(const Duration(seconds: 2),
        onTimeout: () => fail('teardown never finished'));
    expect(session.stops, 0,
        reason: 'the open never settled, so there was nothing yet to release');

    // The hung open eventually settling must not resurrect itself: its
    // generation has moved on and nothing newer has claimed the camera, so
    // releasing it is its own job.
    //
    // Deliberately NO retry in this case. `_SlowSession` hands out a fresh
    // completer per call and the real `CameraSession` does not — a retry there
    // JOINS the attempt that hung. Asserting "the retry opened a second
    // camera" against this double would be asserting the opposite of
    // production, which is what GPT-PM's round-2 review rejected. The retry
    // path is covered below, against a double that coalesces like the real one.
    session.opens.first.complete();
    await pumpEventQueue();
    expect(session.stops, 1);
  });

  test('a disowned open does not shut down the camera a retry has adopted',
      () async {
    // The regression the first version of the hung-open fix introduced, in the
    // shape it actually takes in production.
    //
    // A hangs; the page times out; back disowns A; the user retries as B; B's
    // `session.start()` JOINS A's still-pending platform open, because that is
    // what `CameraSession` does. When the one shared open finally succeeds,
    // BOTH continuations resume — and A, seeing itself stale, must not stop
    // the camera B is at that moment adopting, or the coach ends up
    // "initialised" over a dead stream.
    final session = _CoalescingSession();
    final svc = MlKitPoseDetectorService(
      session: session,
      detectorFactory: _CountingDetector.new,
      startSettleWait: _shortWait,
    );

    unawaited(svc.start()); // A
    await pumpEventQueue();
    expect(session.starts, 1);

    await svc.stop().timeout(const Duration(seconds: 2),
        onTimeout: () => fail('teardown never finished'));
    expect(session.stops, 0);

    unawaited(svc.start()); // B, which joins A's open
    await pumpEventQueue();
    expect(session.starts, 1,
        reason: 'the real CameraSession coalesces, and this double says so');

    session.open!.complete();
    await pumpEventQueue();

    expect(session.stops, 0,
        reason: 'the stale generation left B the camera it had just adopted');

    // And B genuinely owns a running service: a stop now actually tears one
    // down, which it would not if `_initialised` had never been set.
    await svc.stop();
    expect(session.stops, 1);
  });

  test('a failed open closes the detector it had already built', () async {
    // The detector is constructed BEFORE the camera opens, and the teardown
    // path that closes one sits below `stop()`'s `_initialised` guard — which
    // a failed start never gets past. So every refused permission used to leak
    // one, and a user tapping retry a few times accumulated them natively.
    // Invisible without a seam: `close()` is a method channel.
    final session = _SlowSession();
    final detectors = <_CountingDetector>[];
    final svc = MlKitPoseDetectorService(
      session: session,
      detectorFactory: () {
        final d = _CountingDetector();
        detectors.add(d);
        return d;
      },
    );

    final starting = svc.start();
    await Future<void>.delayed(Duration.zero);
    session.opens.single.completeError(
        const CameraUnavailable(CameraUnavailableReason.permissionDenied));

    await expectLater(starting, throwsA(isA<CameraUnavailable>()),
        reason: 'the start still reports the refusal — that is its job');

    expect(detectors, hasLength(1));
    expect(detectors.single.closes, 1, reason: 'released exactly once');

    // And a retry builds a fresh one rather than reusing a closed one.
    unawaited(svc.start());
    await Future<void>.delayed(Duration.zero);
    expect(detectors, hasLength(2));
    expect(detectors.first.closes, 1, reason: 'not closed a second time');
  });

  test('a start that fails while a stop is waiting does not make the stop throw',
      () async {
    // The other exit from that window. A failed start has nothing left to
    // release, and the stop must not surface its error either: "leave this
    // screen" is not a request the caller has any recovery to offer for.
    final session = _SlowSession();
    final detectors = <_CountingDetector>[];
    final svc = MlKitPoseDetectorService(
      session: session,
      detectorFactory: () {
        final d = _CountingDetector();
        detectors.add(d);
        return d;
      },
    );

    final starting = svc.start();
    await Future<void>.delayed(Duration.zero);
    final stopping = svc.stop();

    session.opens.single.completeError(
        const CameraUnavailable(CameraUnavailableReason.permissionDenied));

    await expectLater(starting, throwsA(isA<CameraUnavailable>()));
    await expectLater(stopping, completes);
    expect(detectors.single.closes, 1,
        reason: 'still released exactly once, with a stop racing the failure');
  });

  test('two starts inside the same window open one camera, not two', () async {
    // The re-entrancy half of the same fix. `_initialised` cannot separate
    // "not started" from "starting", so without coalescing, the page's own
    // several arming paths (post-frame callback, retry, lifecycle resume)
    // could each build a detector over the field the previous one is still
    // initialising — exactly what `CameraSession.start`'s own guard exists to
    // prevent one layer down.
    final session = _SlowSession();
    final svc = MlKitPoseDetectorService(
        session: session, detectorFactory: _CountingDetector.new);

    final a = svc.start();
    final b = svc.start();
    session.opens.single.complete();
    await Future.wait([a, b]);

    expect(session.starts, 1,
        reason: 'the second caller joined the first attempt rather than '
            'opening a camera of its own');

    // And the service is genuinely running afterwards: a third start is now a
    // no-op rather than a fourth attempt.
    await svc.start();
    expect(session.stops, 0);

    await svc.stop();
    expect(session.stops, 1);
  });
}
