/// Guided self-timer body scan: phone on a tripod, three poses (front, side,
/// back), automatic shutter after a 3-2-1 countdown once the person is ready.
///
/// Flow: camera preview + pose frames -> [ReadinessEvaluator] -> [AutoShutterMachine]
/// -> still capture. Guidance is visual (readiness chips, hint line, big
/// countdown), spoken (through the app's voice coach, so the mute switch
/// applies) and haptic. A manual shutter is always available because pose
/// detection can fail in a gym (hair, loose clothes, backlight), and the back
/// step needs an explicit "I am facing away" because a detector cannot tell a
/// back view from a front view by geometry.
///
/// Photos stay in memory until the final review is confirmed; only then are
/// they written through the existing encrypted photo store and the scan record
/// (with the landmarks measured at the shutter frame) is saved. Leaving the
/// screen earlier writes nothing and deletes nothing.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../account_deletion/state/account_deletion_providers.dart'
    show accountBeingDeletedUidProvider;
import '../../../auth/state/auth_providers.dart';
import '../../../body_scan/data/body_scan_job.dart' show JobStatus;
import '../../../body_scan/widgets/setup_status_panel.dart';
import '../../../body_scan/widgets/skeleton_overlay.dart';
import '../../../form_check/data/pose_landmark.dart';
import '../../../form_check/state/form_check_providers.dart'
    show voiceMutedProvider;
import '../../data/progress_photo.dart';
import '../../state/progress_photos_providers.dart';
import '../auto_shutter_machine.dart';
import '../readiness_evaluator.dart';
import '../scan_access.dart';
import '../scan_models.dart';
import '../scan_pose.dart';
import '../scan_reminder.dart';
import '../scan_repository.dart';
import '../scan_session.dart';
import 'scan_gate_view.dart';
import 'scan_landmark_mapper.dart';
import 'scan_ports.dart';
import 'scan_text.dart';

class ScanCaptureScreen extends ConsumerWidget {
  /// [weightKg] is the weight recorded for this scan (the body-scan flow asks
  /// for it before capture); it is stored in the v2 record. The screen pops
  /// with the new scan id (a `String`) once the scan is saved, and with null
  /// when it is left without saving.
  const ScanCaptureScreen({super.key, this.weightKg});

  final double? weightKg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(scanAccessProvider);
    if (access != ScanAccess.allowed) {
      return Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context).scanEntryTitle)),
        body: ScanGateView(access: access),
      );
    }
    return _ScanCaptureBody(weightKg: weightKg);
  }
}

enum _Phase { capture, review, saving }

/// Thrown inside `_save` when the initiating account is gone mid-transaction.
class _SaveAborted implements Exception {
  const _SaveAborted();
}

class _ScanCaptureBody extends ConsumerStatefulWidget {
  const _ScanCaptureBody({this.weightKg});

  final double? weightKg;

  @override
  ConsumerState<_ScanCaptureBody> createState() => _ScanCaptureBodyState();
}

class _ScanCaptureBodyState extends ConsumerState<_ScanCaptureBody>
    with WidgetsBindingObserver {
  late final ScanCamera _camera;
  late final ScanSpeaker _speaker;
  late final ScanHaptics _haptics;
  late final ScanClock _clock;
  final AutoShutterMachine _machine = AutoShutterMachine();
  final ReadinessEvaluator _evaluator = const ReadinessEvaluator();

  StreamSubscription<PoseFrame>? _sub;
  // Keeps the auto-dispose camera provider alive while this screen is mounted;
  // `ref.read` alone would let Riverpod dispose the camera under the screen.
  ProviderSubscription<ScanCamera>? _cameraLink;
  ScanSession _session = ScanSession.start();
  final Map<ScanPose, Uint8List> _bytes = {};
  final Map<ScanPose, List<ScanLandmark>> _landmarks = {};
  final Map<ScanPose, String> _savedPhotoIds = {};

  _Phase _phase = _Phase.capture;
  ReadinessResult? _result;
  PoseFrame? _lastFrame;
  int? _countdown;
  bool _confirmAway = false;
  bool _capturing = false;
  bool _starting = true;
  Object? _startError;
  Object? _saveError;

  ReadinessHint _lastHint = ReadinessHint.none;
  int _lastHintAtMs = 0;
  static const int _hintRepeatMs = 9000;

  /// Per pose: the manual shutter fired while readiness was not green. Cleared
  /// for a pose when it is retaken.
  final Map<ScanPose, bool> _manualOverride = {};

  // Manual-shutter timer (D-80): visible, announced, cancellable.
  Timer? _manualTimer;
  int _manualLeft = 0;

  /// The hint text the polite live region currently carries. It changes at most
  /// once per [_liveHintMinGapMs] so a flickering readiness never floods a
  /// screen reader (D-80).
  String _liveHint = '';
  int _liveHintAtMs = 0;
  static const int _liveHintMinGapMs = 2000;

  bool _wasReady = false;
  ScanHapticPattern? _lastFailPattern;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cameraLink = ref.listenManual(scanCameraProvider, (_, __) {});
    _camera = ref.read(scanCameraProvider);
    _speaker = ref.read(scanSpeakerProvider);
    _haptics = ref.read(scanHapticsProvider);
    _clock = ref.read(scanClockProvider);
    _sub = _camera.frames().listen(_onFrame, onError: _onFrameError);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startCamera();
    });
  }

  void _onFrameError(Object error, StackTrace st) {
    debugPrint('scan: pose frame stream failed: $error\n$st');
    if (!mounted) return;
    _machine.reset();
    setState(() {
      _countdown = null;
      _starting = false;
      _startError = error;
    });
  }

  Future<void> _startCamera() async {
    setState(() {
      _starting = true;
      _startError = null;
    });
    try {
      await _camera.start();
      if (!mounted) return;
      setState(() => _starting = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _startError = e;
      });
    }
  }

  /// A countdown must never survive the app leaving the foreground: the user
  /// is no longer posing, and a shutter that fires on return would capture an
  /// unprepared body. Anything but `resumed` resets the machine and clears the
  /// digit; the user has to be ready again to start a new countdown.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed || !mounted) return;
    _machine.reset();
    _cancelManualTimer();
    unawaited(_speaker.stop());
    if (_countdown != null) setState(() => _countdown = null);
  }

  @override
  void dispose() {
    _manualTimer?.cancel();
    _manualTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_sub?.cancel());
    unawaited(_camera.stop());
    unawaited(_speaker.stop());
    _cameraLink?.close();
    super.dispose();
  }

  AppLocalizations get _l10n => AppLocalizations.of(context);

  // ---- frame loop -------------------------------------------------------

  void _onFrame(PoseFrame frame) {
    if (!mounted || _phase != _Phase.capture || _capturing) return;
    final pose = _session.currentPose;
    if (pose == null) return;
    final now = _clock();
    final result = _evaluator.evaluate(
      frame: frame,
      // The real frame brightness when the camera measures it (so over-exposure
      // is detected); otherwise only the "sustained dark" verdict is known and
      // the evaluator treats the mid value as fine.
      luminance: _camera.luminance ?? (_camera.lowLight.value ? 0.1 : 0.5),
      pose: pose,
      userConfirmsFacingAway: _confirmAway,
    );
    final previous = _result;
    _lastFrame = frame;
    _result = result;

    // While the manual-shutter timer runs it owns the countdown: the auto
    // machine is not fed, so two countdowns can never overlap (D-80).
    if (_manualTimer != null) {
      if (previous == null || _readinessChanged(previous, result)) {
        setState(() {});
      }
      return;
    }

    final wasCounting = _countdown != null;
    final liveBefore = _liveHint;
    final events = _machine.update(now, ready: result.isReady);
    int? countdown = _countdown;
    var shutter = false;
    for (final e in events) {
      switch (e.type) {
        case ShutterEventType.tick:
          countdown = e.value;
          _haptics.tick();
          // ONE channel per tick (D-80): with a screen reader the countdown
          // live region carries it; otherwise only the speech engine does.
          if (!_screenReaderOn) unawaited(_speaker.say('${e.value}'));
        case ShutterEventType.shutter:
          shutter = true;
          countdown = null;
        case ShutterEventType.cancelled:
          countdown = null;
          if (wasCounting) {
            _haptics.warn();
            _announceCue(_l10n.scanCancelledSpoken, now);
            _lastHint = ReadinessHint.none;
          }
        case ShutterEventType.holdStart:
        case ShutterEventType.poseDone:
          break;
      }
    }
    if (!shutter) _maybeSpeakHint(result, now);
    // Rebuild only when something the UI shows has changed.
    final changed = previous == null ||
        _readinessChanged(previous, result) ||
        _countdown != countdown ||
        // A cue that was throttled earlier reaches the live region on a later
        // frame; without a rebuild it would stay stale until readiness changed.
        _liveHint != liveBefore;
    _countdown = countdown;
    if (changed) setState(() {});
    if (shutter) unawaited(_capture(pose, frame));
  }

  bool _readinessChanged(ReadinessResult a, ReadinessResult b) =>
      a.distance != b.distance ||
      a.lighting != b.lighting ||
      a.position != b.position ||
      a.orientation != b.orientation ||
      a.hint != b.hint;

  bool get _screenReaderOn =>
      mounted && MediaQuery.of(context).accessibleNavigation;

  ScanHapticPattern? _patternOfHint(ReadinessHint h) =>
      switch (checkOfHint(h)) {
        SetupCheck.distance => ScanHapticPattern.distance,
        SetupCheck.lighting => ScanHapticPattern.lighting,
        SetupCheck.position => ScanHapticPattern.position,
        SetupCheck.orientation => ScanHapticPattern.pose,
        null => null,
      };

  /// Puts [text] on the polite live region, at most once per
  /// [_liveHintMinGapMs]. Always the channel for a screen-reader user, and the
  /// fallback when speech failed.
  void _announceCue(String text, int now) {
    if (text == _liveHint) return;
    if (now - _liveHintAtMs < _liveHintMinGapMs) return;
    _liveHint = text;
    _liveHintAtMs = now;
  }

  /// Non-visual cues for the current readiness: a named haptic pattern for
  /// every transition and the hint on the throttled live region; speech only
  /// when no screen reader is active (one channel), repeated after a pause so
  /// the person is not nagged on every analysed frame.
  void _maybeSpeakHint(ReadinessResult r, int now) {
    if (_machine.state == ShutterState.cooldown) return;
    if (r.isReady) {
      if (!_wasReady) {
        _wasReady = true;
        _lastFailPattern = null;
        _haptics.pattern(ScanHapticPattern.ready);
        _announceCue(_l10n.scanAllChecksOk, now);
        if (!_screenReaderOn) {
          unawaited(_sayOrFallBack(_l10n.scanAllChecksOk, now));
        }
      }
      _lastHint = ReadinessHint.none;
      return;
    }
    if (_wasReady) {
      _wasReady = false;
      _haptics.pattern(ScanHapticPattern.lost);
    }
    if (r.hint == ReadinessHint.none) {
      _lastHint = ReadinessHint.none;
      return;
    }
    final text = hintText(_l10n, r.hint);
    _announceCue(text, now);
    final pattern = _patternOfHint(r.hint);
    if (pattern != null && pattern != _lastFailPattern) {
      _lastFailPattern = pattern;
      _haptics.pattern(pattern);
    }
    if (r.hint == _lastHint && now - _lastHintAtMs < _hintRepeatMs) return;
    _lastHint = r.hint;
    _lastHintAtMs = now;
    if (!_screenReaderOn) unawaited(_sayOrFallBack(text, now));
  }

  /// Speaks [text]; when speech failed, the live region carries it instead
  /// (speech failure is swallowed but observable, D-80).
  Future<void> _sayOrFallBack(String text, int now) async {
    final ok = await _speaker.say(text);
    if (!ok && mounted) {
      _liveHint = '';
      _announceCue(text, _clock());
      setState(() {});
    }
  }

  // ---- manual shutter timer (D-80) -------------------------------------

  int get _manualSeconds {
    final chosen = ref.read(scanManualTimerSecondsProvider);
    return kScanManualTimerChoices.contains(chosen)
        ? chosen
        : kScanManualTimerDefault;
  }

  /// Starts the visible, announced, cancellable timer; the photo is taken when
  /// it reaches zero. A second press cancels it.
  void _manualShutter() {
    final pose = _session.currentPose;
    if (pose == null || _capturing) return;
    if (_manualTimer != null) {
      _cancelManualTimer();
      return;
    }
    _machine.reset();
    _manualLeft = _manualSeconds;
    _haptics.tick();
    if (!_screenReaderOn) {
      unawaited(_speaker.say(_l10n.scanManualTimerStarted(_manualLeft)));
    }
    setState(() => _countdown = _manualLeft);
    _manualTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      _manualLeft--;
      if (_manualLeft <= 0) {
        t.cancel();
        _manualTimer = null;
        setState(() => _countdown = null);
        unawaited(_fireManual(pose));
        return;
      }
      _haptics.tick();
      if (!_screenReaderOn) unawaited(_speaker.say('$_manualLeft'));
      setState(() => _countdown = _manualLeft);
    });
  }

  /// Aborts a running manual timer. Nothing is captured or recorded.
  void _cancelManualTimer() {
    final running = _manualTimer != null;
    _manualTimer?.cancel();
    _manualTimer = null;
    _manualLeft = 0;
    if (running && mounted) {
      _haptics.warn();
      unawaited(_speaker.stop());
      setState(() => _countdown = null);
    }
  }

  Future<void> _fireManual(ScanPose pose) async {
    if (_capturing) return;
    // Recorded when the shutter fires: it lowers this scan's confidence one
    // level only when the checks were not all green at that moment.
    final ready = _result?.isReady ?? false;
    if (!ready) _manualOverride[pose] = true;
    _haptics.shutter();
    await _capture(pose, _lastFrame);
  }

  // ---- capture ----------------------------------------------------------

  Future<void> _capture(ScanPose pose, PoseFrame? frame) async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      _haptics.shutter();
      Uint8List? bytes;
      Object? error;
      try {
        bytes = await _camera.captureStill();
      } catch (e) {
        error = e;
      }
      if (!mounted) return;
      _machine.reset();
      if (bytes == null) {
        _showCaptureFailure(error);
        return;
      }
      _bytes[pose] = bytes;
      _landmarks[pose] = landmarksFromFrame(frame);
      _session = _session.markCaptured(pose, 'pending_${pose.name}');
      _confirmAway = false;
      _lastHint = ReadinessHint.none;
      final next = _session.currentPose;
      setState(() {
        _capturing = false;
        _countdown = null;
        _phase = next == null ? _Phase.review : _Phase.capture;
      });
      if (next == null) {
        unawaited(_camera.stop());
        unawaited(_speaker.say(_l10n.scanAllDone));
      } else {
        unawaited(_speaker.say(_l10n.scanNextPose(poseLabel(_l10n, next))));
      }
    } catch (e, st) {
      debugPrint('scan: capture failed: $e\n$st');
      if (mounted) _showCaptureFailure(e);
    } finally {
      // Never leave the shutter locked, whatever happened above.
      if (_capturing) {
        _capturing = false;
        if (mounted) setState(() {});
      }
    }
  }

  void _showCaptureFailure(Object? error) {
    setState(() {
      _capturing = false;
      _countdown = null;
    });
    final l10n = AppLocalizations.of(context);
    final text = error != null
        ? l10n.photosCaptureFailed(error)
        : l10n.scanCameraFailed('-');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _retake(ScanPose pose) async {
    _bytes.remove(pose);
    _landmarks.remove(pose);
    _manualOverride.remove(pose);
    _session = _session.retake(pose);
    _machine.reset();
    _wasReady = false;
    _lastFailPattern = null;
    setState(() {
      _phase = _Phase.capture;
      _result = null;
      _countdown = null;
      _confirmAway = false;
    });
    await _startCamera();
  }

  // ---- save -------------------------------------------------------------

  Future<void> _save() async {
    if (_phase == _Phase.saving) return;
    // Everything that needs `ref`/`context` is resolved BEFORE the first await,
    // so leaving the screen mid-save cannot make a disposed ref throw.
    final photos = ref.read(progressPhotosRepositoryProvider);
    final scans = ref.read(scanRepositoryProvider);
    final reminder = ref.read(scanReminderEnabledProvider.notifier);
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final savedText = _l10n.scanSaved;
    void invalidate() {
      try {
        container.invalidate(scanHistoryProvider);
        container.invalidate(progressPhotosProvider);
      } catch (e) {
        debugPrint('scan: invalidate after save failed: $e');
      }
    }

    // The whole transaction is bound to the account that started it: the
    // repositories above belong to it, and every write is re-checked against
    // the live uid so a sign-out / deletion / switch mid-save cannot recreate
    // or commit data after the local wipe, nor write under the new account.
    final initiatingUid = container.read(authUserProvider).valueOrNull?.uid;
    bool accountChanged() {
      try {
        // Account deletion flags the uid BEFORE its local wipe, while auth
        // still reports the same uid: without this a write finishing after
        // the wipe would recreate the deleted account's photos.
        if (initiatingUid != null &&
            container.read(accountBeingDeletedUidProvider) == initiatingUid) {
          return true;
        }
        return container.read(authUserProvider).valueOrNull?.uid !=
            initiatingUid;
      } catch (_) {
        // A disposed scope is as good as a changed account.
        return true;
      }
    }

    String? writtenScanId;
    // Best effort, through the ORIGINAL account's repositories only; never
    // resolves a repository for the current user and never throws.
    Future<void> abortSave() async {
      final scanId = writtenScanId;
      if (scanId != null) {
        try {
          await scans.delete(scanId);
        } catch (e) {
          debugPrint('scan: could not remove aborted scan $scanId: $e');
        }
      }
      for (final id in _savedPhotoIds.values.toList()) {
        try {
          await photos.delete(id);
        } catch (e) {
          debugPrint('scan: could not remove aborted photo $id: $e');
        }
      }
      _savedPhotoIds.clear();
    }

    setState(() {
      _phase = _Phase.saving;
      _saveError = null;
    });
    try {
      for (final pose in ScanPose.ordered) {
        // A retry after a partial failure reuses photos already written.
        if (_savedPhotoIds.containsKey(pose)) continue;
        if (accountChanged()) throw const _SaveAborted();
        final photo = await photos.save(
          _bytes[pose]!,
          angle: _angleOf(pose),
        );
        // Recorded before the re-check so the abort cleanup removes it too.
        _savedPhotoIds[pose] = photo.id;
        if (accountChanged()) throw const _SaveAborted();
      }
      if (accountChanged()) throw const _SaveAborted();
      final now = DateTime.now();
      final record = ScanRecord(
        id: 'scan_${now.microsecondsSinceEpoch}',
        createdAt: now,
        shots: {
          for (final pose in ScanPose.ordered)
            pose: ScanShot(
              photoId: _savedPhotoIds[pose]!,
              landmarks: _landmarks[pose] ?? const [],
            ),
        },
        // v2: the scan joins the offline queue; the job runner (C14) decides
        // between the local provisional estimate and the cloud path.
        analysis: ScanAnalysis(status: JobStatus.queued, updatedAt: now),
        weightKg: widget.weightKg,
        manualOverride: {
          for (final p in ScanPose.ordered)
            if (_manualOverride[p] == true) p: true,
        },
      );
      try {
        await scans.save(record);
      } catch (_) {
        // The sidecar was not written: do not leave its photos orphaned in
        // the timeline. Best effort; a failed delete is logged, not hidden.
        for (final id in _savedPhotoIds.values) {
          try {
            await photos.delete(id);
          } catch (e) {
            debugPrint('scan: could not remove orphan photo $id: $e');
          }
        }
        _savedPhotoIds.clear();
        invalidate();
        rethrow;
      }
      writtenScanId = record.id;
      if (accountChanged()) throw const _SaveAborted();
      invalidate();
      try {
        unawaited(reminder.sync().catchError((Object e) {
          debugPrint('scan: reminder sync failed: $e');
          return null;
        }));
      } catch (e) {
        debugPrint('scan: reminder sync failed: $e');
      }
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(savedText)));
      // Pops with the new scan id so the caller can open its result.
      navigator.maybePop(record.id);
    } catch (e, st) {
      if (e is _SaveAborted || accountChanged()) {
        // Another account owns the app now: clean up quietly, report nothing.
        debugPrint('scan: save aborted, account changed');
        await abortSave();
        // A screen that survives the switch must not keep the old account's
        // photos or ids. Silent: no snackbar, no error.
        if (mounted) {
          setState(() {
            _bytes.clear();
            _landmarks.clear();
            _savedPhotoIds.clear();
            _phase = _Phase.capture;
            _saveError = null;
            _countdown = null;
          });
          navigator.maybePop();
        }
        return;
      }
      debugPrint('scan: save failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _phase = _Phase.review;
        _saveError = e;
      });
    }
  }

  ProgressPhotoAngle _angleOf(ScanPose p) => switch (p) {
        ScanPose.front => ProgressPhotoAngle.front,
        ScanPose.side => ProgressPhotoAngle.side,
        ScanPose.back => ProgressPhotoAngle.back,
      };

  // ---- UI ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _phase == _Phase.capture ? _buildCapture(context) : _buildReview(context),
    );
  }

  Widget _buildCapture(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pose = _session.currentPose ?? ScanPose.back;
    final result = _result;
    final muted = ref.watch(voiceMutedProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_startError == null) _camera.buildPreview(context),
        if (_startError == null && _phase == _Phase.capture)
          Positioned.fill(
            child: SkeletonOverlay(
              frame: _lastFrame,
              ready: _result?.isReady ?? false,
            ),
          ),
        if (_starting)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Reduced motion: static text instead of a spinner.
                if (!MediaQuery.of(context).disableAnimations) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                ],
                Text(l10n.scanStarting,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: Colors.white)),
              ],
            ),
          ),
        if (_startError != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  l10n.scanCameraFailed(_startError!),
                  key: const Key('scan.cameraError'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: Colors.white),
                ),
              ),
            ),
          ),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      key: const Key('scan.close'),
                      tooltip: l10n.scanClose,
                      color: Colors.white,
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    // Takes the space between the icon buttons and scales down
                    // instead of overflowing at large text sizes (D-80).
                    Expanded(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _PosePill(
                            pose: pose,
                            index: _session.capturedCount + 1,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('scan.voice'),
                      tooltip: muted ? l10n.scanVoiceOff : l10n.scanVoiceOn,
                      color: Colors.white,
                      icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
                      onPressed: () {
                        final next = !muted;
                        ref.read(voiceMutedProvider.notifier).state = next;
                        if (next) unawaited(_speaker.stop());
                      },
                    ),
                    IconButton(
                      key: const Key('scan.flip'),
                      tooltip: l10n.scanFlipCamera,
                      color: Colors.white,
                      icon: const Icon(Icons.cameraswitch_outlined),
                      onPressed: _starting || _capturing ? null : _flip,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              _ReadinessPanel(
                result: result,
                pose: pose,
                countdown: _countdown,
                confirmAway: _confirmAway,
                capturing: _capturing,
                manualTimerRunning: _manualTimer != null,
                liveHint: _liveHint,
                onManual: _starting || _startError != null ? null : _manualShutter,
                onCancelManual: _cancelManualTimer,
                onFacingAway: () => setState(() => _confirmAway = true),
              ),
            ],
          ),
        ),
        if (_countdown != null)
          Center(
            child: Semantics(
              liveRegion: true,
              label: l10n.scanCountdownSemantics(_countdown!),
              child: ExcludeSemantics(
                child: Text(
                  '$_countdown',
                  key: const Key('scan.countdown'),
                  // Theme style instead of a hard-coded 160 px literal; the
                  // display style scales with the user's text size.
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    shadows: const [Shadow(blurRadius: 16, color: Colors.black87)],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _flip() async {
    _machine.reset();
    _cancelManualTimer();
    setState(() => _countdown = null);
    try {
      await _camera.flip();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_l10n.scanCameraFailed(e))),
      );
    }
  }

  Widget _buildReview(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final saving = _phase == _Phase.saving;
    return SafeArea(
      key: const Key('scan.review'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.scanReviewTitle,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(l10n.scanReviewBody,
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final pose in ScanPose.ordered)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          children: [
                            Text(poseLabel(l10n, pose),
                                style: const TextStyle(color: Colors.white)),
                            const SizedBox(height: 6),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: _bytes[pose] == null
                                    ? const ColoredBox(color: Colors.black26)
                                    : Image.memory(
                                        _bytes[pose]!,
                                        fit: BoxFit.cover,
                                        gaplessPlayback: true,
                                        errorBuilder: (_, __, ___) => Center(
                                          child: Text(l10n.scanShotMissing,
                                              style: const TextStyle(
                                                  color: Colors.white54)),
                                        ),
                                      ),
                              ),
                            ),
                            TextButton(
                              key: Key('scan.retake.${pose.name}'),
                              onPressed: saving ? null : () => _retake(pose),
                              // Pose-specific label so a screen reader hears
                              // which photo a button retakes.
                              child: Text(
                                l10n.scanRetakePose(poseLabel(l10n, pose)),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_saveError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    l10n.scanSaveFailed(_saveError!),
                    key: const Key('scan.saveError'),
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ),
            FilledButton(
              key: const Key('scan.save'),
              onPressed: saving ? null : _save,
              child: saving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, semanticsLabel: l10n.scanSaving),
                    )
                  : Text(l10n.scanSave),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosePill extends StatelessWidget {
  const _PosePill({required this.pose, required this.index});
  final ScanPose pose;
  final int index;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      key: const Key('scan.pose'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            poseLabel(l10n, pose),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white, fontWeight: FontWeight.w800),
          ),
          Text(
            l10n.scanStepOf(index.clamp(1, 3), 3),
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

/// The bottom panel: hint, four status rows, facing-away note and the actions.
///
/// Bounded and scrollable (D-80): the hint, the four rows and the facing-away
/// button live in an internally scrollable area capped at half the screen, so
/// large text sizes never push the controls off screen. The shutter and the
/// timer Cancel sit OUTSIDE the scroll area and are at least 48 dp high. The
/// hint is the throttled polite live region; with a screen reader the countdown
/// and the cues go through live regions only (one channel).
class _ReadinessPanel extends StatelessWidget {
  const _ReadinessPanel({
    required this.result,
    required this.pose,
    required this.countdown,
    required this.confirmAway,
    required this.capturing,
    required this.manualTimerRunning,
    required this.liveHint,
    required this.onManual,
    required this.onCancelManual,
    required this.onFacingAway,
  });

  final ReadinessResult? result;
  final ScanPose pose;
  final int? countdown;
  final bool confirmAway;
  final bool capturing;
  final bool manualTimerRunning;

  /// The throttled text of the live region ('' until the first cue).
  final String liveHint;
  final VoidCallback? onManual;
  final VoidCallback onCancelManual;
  final VoidCallback onFacingAway;

  static const ButtonStyle _tall =
      ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(48, 48)));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final r = result;
    final hint = r == null
        ? l10n.scanTripodTip
        : r.isReady
            ? l10n.scanHintReady
            : (r.hint == ReadinessHint.none
                ? l10n.scanHintShowFullBody
                : hintText(l10n, r.hint));
    final maxHeight = MediaQuery.of(context).size.height * 0.5;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        // Near-opaque so chip text stays >= 4.5:1 over a bright scene (C26
        // contrast table: 0.65 failed for orangeAccent/white70 over white).
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              key: const Key('scan.panelScroll'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    liveRegion: true,
                    // The live region carries the throttled cue, not every
                    // frame's hint.
                    label: liveHint.isEmpty ? hint : liveHint,
                    child: ExcludeSemantics(
                      child: Text(
                        hint,
                        key: const Key('scan.hint'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SetupStatusPanel(result: r),
                  if (pose == ScanPose.back) ...[
                    const SizedBox(height: 8),
                    OutlinedButton(
                      key: const Key('scan.facingAway'),
                      style: _tall,
                      onPressed: confirmAway ? null : onFacingAway,
                      child: Text(l10n.scanFacingAway),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton.icon(
                key: const Key('scan.shutter'),
                style: _tall,
                onPressed: capturing || manualTimerRunning ? null : onManual,
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(l10n.scanShutterNow),
              ),
              if (manualTimerRunning)
                OutlinedButton.icon(
                  key: const Key('scan.manualCancel'),
                  style: _tall,
                  onPressed: onCancelManual,
                  icon: const Icon(Icons.timer_off_outlined),
                  label: Text(l10n.scanManualTimerCancel),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
