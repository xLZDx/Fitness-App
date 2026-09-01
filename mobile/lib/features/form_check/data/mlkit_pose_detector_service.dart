import 'dart:async';

import 'package:google_mlkit_commons/google_mlkit_commons.dart'
    show InputImage, InputImageMetadata, InputImageRotation;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    as mlkit;

import 'package:flutter/foundation.dart'
    show ValueListenable, debugPrint;
import 'package:flutter/services.dart' show PlatformException;

import '../../../core/camera/camera_session.dart';
import 'pose_coordinate_space.dart';
import 'pose_detector_service.dart';
import 'pose_landmark.dart';

/// Real, on-device pose detector binding the [camera] plugin to
/// `google_mlkit_pose_detection`. Frames are processed at the camera's
/// native rate (typically 15-30 FPS depending on device); rule
/// classifiers downstream consume the [PoseFrame] stream.
///
/// Lifecycle: callers MUST call [start] before subscribing to [frames]
/// and [dispose] when leaving the screen — otherwise the camera stays
/// hot and the detector leaks resources.
/// Builds the ML Kit detector this service drives.
///
/// A seam, not an abstraction: `mlkit.PoseDetector` reaches a method channel
/// the moment it is used, so a test that wants to prove the detector is CLOSED
/// on a failed start has no other way to observe it. Production never passes
/// one.
typedef PoseDetectorFactory = mlkit.PoseDetector Function();

class MlKitPoseDetectorService implements PoseDetectorService {
  MlKitPoseDetectorService({
    CameraSession? session,
    PoseDetectorFactory? detectorFactory,
    Duration startSettleWait = const Duration(seconds: 5),
  })  : session = session ?? CameraSession(facing: SessionFacing.front),
        _newDetector = detectorFactory ?? _defaultDetector,
        _startSettleWait = startSettleWait;

  static mlkit.PoseDetector _defaultDetector() => mlkit.PoseDetector(
        options: mlkit.PoseDetectorOptions(
          mode: mlkit.PoseDetectionMode.stream,
          model: mlkit.PoseDetectionModel.base,
        ),
      );

  final PoseDetectorFactory _newDetector;

  /// The front camera, owned by the session rather than by this detector.
  ///
  /// It used to build its own controller and expose it so the page could draw a
  /// preview via `svc.cameraController as CameraController?` — a downcast of a
  /// detector to get at a camera. The frame-format handling was also a second,
  /// near-identical copy of the equipment recogniser's, which is two places for
  /// the NV21 bug to come back.
  final CameraSession session;

  StreamSubscription<InputImage>? _sub;
  // Nullable, not `late final`: stop() has to be able to release the detector
  // and let a later start() build a new one. A `late final` field made the
  // service single-use, which is what broke Form Check on any second visit.
  mlkit.PoseDetector? _detector;
  final StreamController<PoseFrame> _ctrl =
      StreamController<PoseFrame>.broadcast();
  bool _busy = false;
  bool _initialised = false;

  /// A [start] that has not finished opening the camera yet.
  ///
  /// The window it names is the whole point: opening a camera and loading the
  /// ML Kit model takes a second or two, and until it finishes `_initialised`
  /// is still false. See [stop].
  Future<void>? _starting;

  /// Which generation [_starting] belongs to.
  ///
  /// Bumped by every [start] and every [stop]. Two jobs, both of which the
  /// bare `_starting` future could not do:
  ///
  /// 1. An open whose generation has moved on is UNWANTED, and cleaning up
  ///    after itself is its own job — nobody else can do it without racing the
  ///    half-finished open (`CameraSession` assigns `_camera` before
  ///    `initialize()`, so a concurrent teardown disposes a controller the open
  ///    then initialises and streams from).
  /// 2. A [start] only joins an in-flight one from its OWN generation. A
  ///    platform open that hangs forever would otherwise be joined by every
  ///    later attempt, so a hung first visit would kill the feature for the
  ///    life of the process — which is exactly the failure this service's
  ///    `_initialised` latch used to cause and was fixed for.
  int _generation = 0;
  int _startingGeneration = -1;

  /// How long [stop] waits for an in-flight open before returning.
  ///
  /// Bounded on purpose, and the bound does NOT license a teardown afterwards
  /// — see [stop]. The page bounds its own `start()` at 15 s and then offers a
  /// retry, so a teardown that waits longer than that turns a recoverable
  /// timeout into a dead screen.
  ///
  /// A constructor parameter only so a test can shorten it. Driving the same
  /// case under a fake clock was tried first and abandoned: `FakeAsync` drains
  /// microtasks only while it is firing timers, so a subscription cancel that
  /// resolves off the timer queue left the teardown mid-flight and the test
  /// read a state the code never reached. A real 20 ms wait tests the real
  /// asynchrony.
  final Duration _startSettleWait;

  /// Frames lost in a row to an unexpected error.
  ///
  /// The generic catch below drops a bad frame on the assumption that the next
  /// one recovers, which is right for a one-off and wrong for a permanent
  /// condition wearing a transient's clothes. `MissingPluginException` is the
  /// clearest example: it is not a `PlatformException`, so it misses the arm
  /// that surfaces and stops, and it is thrown for every frame forever.
  ///
  /// Nothing else would notice. The camera session's stall watchdog keys off
  /// its own delivery, upstream of here — the camera is healthy, it is this
  /// stage that is dead — so it stays quiet, no error is ever recorded, and the
  /// screen falls back to telling the user to stand back. Forever, at a working
  /// live preview.
  int _consecutiveFailures = 0;

  /// About a second of frames at a typical rate. High enough that a burst of
  /// genuinely unlucky frames recovers silently, low enough that a permanent
  /// fault is named while the user is still looking at the screen.
  static const int _maxConsecutiveFailures = 30;



  @override
  Stream<PoseFrame> frames() => _ctrl.stream;

  @override
  Future<void> ensurePermission() => session.ensurePermission();

  @override
  ValueListenable<SessionFacing> get facing => session.activeFacing;

  /// Swaps the lens without disturbing the detector.
  ///
  /// Deliberately NOT `stop()` + `start()` on this service: that would close
  /// the ML Kit detector and cancel the frame subscription, and the broadcast
  /// stream every downstream Notifier is listening to would go quiet for the
  /// duration. [CameraSession.setFacing] reopens only the camera, and the
  /// subscription rides through it — the frames simply resume from the other
  /// lens.
  @override
  Future<void> flipCamera() => session.flip();

  @override
  Future<void> start() async {
    if (_initialised) return;
    // Re-entrancy, exactly as `CameraSession.start` handles it one layer down
    // and for the same reason: `_initialised` does not flip until the camera
    // has finished opening, so two callers arriving inside that window would
    // each build a detector and each open a session. Coalescing here is also
    // what gives [stop] something to wait for.
    //
    // Only within one generation, though. See [_generation]: joining an open
    // that a [stop] has already disowned would hand this caller a future that
    // tears itself down on completion, and joining one that never completes
    // would make the feature permanently dead after a single hung open.
    final pending = _starting;
    if (pending != null && _startingGeneration == _generation) return pending;

    final token = ++_generation;
    final attempt = _startOnce(token);
    _starting = attempt;
    _startingGeneration = token;
    try {
      await attempt;
    } finally {
      // Only if nothing newer has claimed the slot. A start that overtook this
      // one owns `_starting` now, and clearing it here would hide it from the
      // next [stop].
      if (identical(_starting, attempt)) _starting = null;
    }
  }

  Future<void> _startOnce(int token) async {
    final detector = _newDetector();
    _detector = detector;
    try {
      await session.start();
    } catch (_) {
      // The detector is built BEFORE the camera opens, so a refused permission
      // or a failed initialisation leaves one alive that nothing else will
      // ever close: [stop] returns at its `_initialised` guard, and the next
      // attempt overwrites `_detector` with a fresh one. Repeat that a few
      // times and the native side is holding several. Closed here, where the
      // failure is, rather than in a teardown path that cannot be reached.
      await _closeDetector(detector);
      rethrow;
    }
    if (token != _generation) {
      // A [stop] arrived while this open was in flight and could not release
      // anything itself without racing it, so undoing it falls to this method.
      // The detector is unconditionally ours and is closed either way.
      await _closeDetector(detector);
      // The CAMERA is not unconditionally ours, and that distinction is the
      // whole of this branch.
      //
      // `CameraSession.start` coalesces its own concurrent callers onto ONE
      // platform open (`camera_session.dart:211`). So after a stop disowns
      // this generation and the user retries, the newer generation's
      // `session.start()` may be *this very open* — and stopping it here would
      // tear the camera out from under a start that is about to report
      // success, leaving an `_initialised` service subscribed to a dead
      // stream. That is the exact lifecycle class this fix exists to remove,
      // and the first version of the fix reintroduced it; caught by GPT-PM's
      // round-2 review of this gate.
      //
      // The rule is: the NEWEST start generation owns the release. If one
      // exists it runs this same branch itself when it is superseded in turn,
      // so nothing is left holding a camera nobody wants.
      if (_startingGeneration <= token) await session.stop();
      return;
    }
    _initialised = true;
    _sub = session.frames().listen(
          _onFrame,
          onError: (Object e, StackTrace st) {
            if (!_ctrl.isClosed) _ctrl.addError(e, st);
          },
        );
  }

  /// Closes [detector] and clears the field if it is still the current one.
  ///
  /// Never throws: `close()` is a platform call, and a failure to release
  /// something is not a reason to fail the operation that was releasing it.
  Future<void> _closeDetector(mlkit.PoseDetector detector) async {
    if (identical(_detector, detector)) _detector = null;
    try {
      await detector.close();
    } catch (e) {
      debugPrint('pose detector close: $e');
    }
  }

  Future<void> _onFrame(InputImage inputImage) async {
    if (_busy) return;
    _busy = true;
    try {
      final detector = _detector;
      if (detector == null) return; // stopped mid-frame
      final poses = await detector.processImage(inputImage);
      // The call succeeded, whatever it found. `_consecutiveFailures` counts
      // frames lost to an unexpected error, and a frame with nobody in it was
      // not lost — it was answered.
      _consecutiveFailures = 0;
      if (poses.isEmpty) {
        _ctrl.add(_emptyFrame(inputImage.metadata));
        return;
      }
      _ctrl.add(_convert(poses.first, inputImage.metadata));
    } on PlatformException catch (e) {
      // The native detector rejected the call outright — a bad frame format,
      // a dead detector. This never recovers on the next frame, so surface it
      // and stop instead of spinning silently forever. Swallowing this is why
      // the form coach looked like "the camera works but nothing counts".
      debugPrint('pose detection failed natively: ${e.code} ${e.message}');
      if (!_ctrl.isClosed) {
        _ctrl.addError(
          StateError('Pose detection failed: ${e.message ?? e.code}'),
        );
      }
      unawaited(stop());
    } catch (e) {
      // A single frame that fails is not worth surfacing — the next one
      // recovers. A run of them is not a run of accidents.
      debugPrint('pose frame dropped: $e');
      _consecutiveFailures++;
      if (_consecutiveFailures >= _maxConsecutiveFailures) {
        if (!_ctrl.isClosed) {
          _ctrl.addError(StateError(
            'Pose detection failed on '
            '$_consecutiveFailures frames in a row: $e',
          ));
        }
        unawaited(stop());
      }
    } finally {
      _busy = false;
    }
  }

  /// Translate ML Kit's joint set into [PoseFrame], converting coordinates into
  /// the isotropic contract in `pose_coordinate_space.dart`. We only forward the
  /// joints our classifiers actually read, so the wire stays light.
  ///
  /// This is the **only** place raw detector coordinates exist. Everything
  /// downstream — gate, rep counter, every classifier — is written against the
  /// converted unit, and had been since before anything converted anything.
  PoseFrame _convert(mlkit.Pose pose, InputImageMetadata? metadata) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final norm = _normaliserFor(pose, metadata);
    final out = <LandmarkType, PoseLandmark>{};
    void add(LandmarkType t, mlkit.PoseLandmarkType src,
        {LandmarkSide side = LandmarkSide.center}) {
      final lm = pose.landmarks[src];
      if (lm == null) return;
      final (x, y) = norm.normalise(lm.x, lm.y);
      out[t] = PoseLandmark(
        type: t,
        x: x,
        y: y,
        z: norm.normaliseDepth(lm.z),
        likelihood: lm.likelihood,
        side: side,
      );
    }

    add(LandmarkType.nose, mlkit.PoseLandmarkType.nose);
    add(LandmarkType.leftShoulder, mlkit.PoseLandmarkType.leftShoulder,
        side: LandmarkSide.left);
    add(LandmarkType.rightShoulder, mlkit.PoseLandmarkType.rightShoulder,
        side: LandmarkSide.right);
    add(LandmarkType.leftElbow, mlkit.PoseLandmarkType.leftElbow,
        side: LandmarkSide.left);
    add(LandmarkType.rightElbow, mlkit.PoseLandmarkType.rightElbow,
        side: LandmarkSide.right);
    add(LandmarkType.leftWrist, mlkit.PoseLandmarkType.leftWrist,
        side: LandmarkSide.left);
    add(LandmarkType.rightWrist, mlkit.PoseLandmarkType.rightWrist,
        side: LandmarkSide.right);
    add(LandmarkType.leftHip, mlkit.PoseLandmarkType.leftHip,
        side: LandmarkSide.left);
    add(LandmarkType.rightHip, mlkit.PoseLandmarkType.rightHip,
        side: LandmarkSide.right);
    add(LandmarkType.leftKnee, mlkit.PoseLandmarkType.leftKnee,
        side: LandmarkSide.left);
    add(LandmarkType.rightKnee, mlkit.PoseLandmarkType.rightKnee,
        side: LandmarkSide.right);
    add(LandmarkType.leftAnkle, mlkit.PoseLandmarkType.leftAnkle,
        side: LandmarkSide.left);
    add(LandmarkType.rightAnkle, mlkit.PoseLandmarkType.rightAnkle,
        side: LandmarkSide.right);
    // R10: posture's forward-head metric.
    add(LandmarkType.leftEar, mlkit.PoseLandmarkType.leftEar,
        side: LandmarkSide.left);
    add(LandmarkType.rightEar, mlkit.PoseLandmarkType.rightEar,
        side: LandmarkSide.right);

    return PoseFrame(
      timestampMs: ts,
      landmarks: out,
      aspectRatio: norm.aspectRatio,
      sourceSpace: norm.space,
    );
  }

  /// "We looked at this frame and found nobody" — said as a frame, not as
  /// silence.
  ///
  /// Returning early instead made that indistinguishable from "no frame has
  /// been processed yet", and that difference IS tracking loss. Nothing
  /// downstream was notified, so `latestPoseFrameProvider` kept the last live
  /// pose and `poseGateVerdictProvider` kept the last verdict: the overlay went
  /// on drawing a body that had left the room, and the gate went on reporting
  /// about a frame from before it did.
  ///
  /// That was survivable only because the camera image sat underneath it — the
  /// user was their own tracking indicator. This exists because the avatar mode
  /// takes that indicator away, and a frozen figure over a still backdrop is
  /// indistinguishable from a working one.
  ///
  /// Downstream needs no new vocabulary for it: `gatePose` finds none of the
  /// joints a rule requires and already answers `missingJoints`, which
  /// `cue_text.dart` already renders as an instruction to step back into view.
  ///
  /// Carries the aspect ratio because the gate's edge check is per-axis — an
  /// empty frame still has to describe the space it found nothing in.
  PoseFrame _emptyFrame(InputImageMetadata? metadata) => PoseFrame(
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        landmarks: const {},
        aspectRatio: _aspectFor(metadata),
      );

  /// Post-rotation frame size, in pixels.
  ///
  /// Shared by [_normaliserFor] and [_aspectFor] so the two cannot come to
  /// different conclusions about which way round the frame is.
  ///
  /// ML Kit reports landmarks in the upright image, so a sensor mounted at 90°
  /// or 270° means the frame the coordinates live in has the camera's width and
  /// height swapped. Getting this backwards does not corrupt the angles — both
  /// axes still share one divisor — but it does put the x bound in the wrong
  /// place, which is the gate's edge check.
  ///
  /// Falls back to a square frame when metadata is absent, which cannot happen
  /// for a camera-stream image (`camera_session.dart` always supplies it) but is
  /// possible for an `InputImage` built from a file path. A square frame is the
  /// identity for the aspect correction, so the fallback degrades to "no
  /// horizontal correction" instead of to a wrong one.
  (double, double) _frameSize(InputImageMetadata? metadata) {
    var w = metadata?.size.width ?? 1.0;
    var h = metadata?.size.height ?? 1.0;
    final rotation = metadata?.rotation;
    if (rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg) {
      final swap = w;
      w = h;
      h = swap;
    }
    if (w <= 0 || h <= 0) return (1.0, 1.0);
    return (w, h);
  }

  double _aspectFor(InputImageMetadata? metadata) {
    final (w, h) = _frameSize(metadata);
    return w / h;
  }

  /// Builds the converter for one frame: the post-rotation frame size, plus the
  /// space the raw values are actually in, measured rather than assumed.
  PoseCoordinateNormaliser _normaliserFor(
    mlkit.Pose pose,
    InputImageMetadata? metadata,
  ) {
    final (w, h) = _frameSize(metadata);
    return PoseCoordinateNormaliser(
      space: detectCoordinateSpace(
        pose.landmarks.values.expand((lm) => [lm.x, lm.y]),
      ),
      imageWidth: w,
      imageHeight: h,
    );
  }

  /// Releases the camera and the detector, leaving the service **restartable**.
  ///
  /// This used to only stop the image stream and leave `_initialised` true,
  /// so a later [start] returned early and Form Check was dead on every
  /// second visit — with the front camera still held. The broadcast
  /// controller deliberately stays open: listeners re-subscribe across visits.
  @override
  Future<void> stop() async {
    // Disown any open still in flight, FIRST and unconditionally.
    //
    // The `_initialised` check below used to be this method's first line,
    // which made stop() a silent no-op in exactly the window where a camera is
    // being handed over: `_initialised` only flips once `session.start()` has
    // returned, so a stop arriving during the one-to-two seconds an open takes
    // released nothing and the open went on to finish — leaving a live camera
    // and a live detector behind a screen the user had already left. Reachable
    // from the coach's own back control (pressed while the preview is still a
    // spinner) and from backgrounding the app in the same window. Found in
    // review of the selection-screen gate, 2026-09-01.
    //
    // Bumping [_generation] is what actually releases it: the open re-reads
    // the token when it settles and undoes itself. This method must NOT tear
    // down under an unsettled open — `CameraSession` assigns `_camera` before
    // `initialize()` (`camera_session.dart:276,294`), so disposing it here
    // would be disposing a controller that `_open` then initialises and
    // streams from.
    final token = ++_generation;
    final pending = _starting;
    if (pending != null) {
      // Waited on so that this future means "released" for the ordinary case,
      // where the open is merely slow. BOUNDED, because the page bounds its
      // own start at 15 s and then offers a retry: an unbounded wait here
      // turns that recoverable timeout into a screen whose next start is
      // queued forever behind a teardown that never finishes. GPT-PM caught
      // exactly that in the first version of this fix.
      try {
        await pending.timeout(_startSettleWait);
      } catch (_) {
        // A start that FAILED has nothing left to release, and one that is
        // still hung will release itself if it ever settles. Neither is this
        // caller's problem, and neither is an error about leaving a screen.
      }
      // Something newer owns the service now, or the open is still running.
      // Either way the teardown below is not ours to perform.
      if (token != _generation) return;
      if (_starting != null) return;
    }
    if (!_initialised) return;
    _initialised = false;
    // Cleared here because the in-flight frame's `finally` may never run: stop()
    // closes the detector out from under `processImage`, and a future that never
    // completes leaves the latch set. A stuck `_busy` makes every frame after
    // the next start() return at the guard — no log, no error, no verdict. Same
    // shape as the `_initialised` latch that once killed every second visit.
    _busy = false;
    _consecutiveFailures = 0;
    await _sub?.cancel();
    _sub = null;
    await session.stop();
    final detector = _detector;
    if (detector != null) await _closeDetector(detector);
  }

  /// Terminal: releases everything and closes the stream. After this the
  /// instance cannot be restarted — use [stop] when leaving a screen.
  @override
  Future<void> dispose() async {
    await stop();
    await _ctrl.close();
  }
}

