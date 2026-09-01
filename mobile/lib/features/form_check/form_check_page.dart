import 'dart:async' show TimeoutException;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show debugPrint, mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/background/hud_sky.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../core/theme/hud_tokens.dart' show HudMotionX;
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/experimental_banner.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/hud/hud_surface.dart';
import 'data/cue_text.dart';
import 'data/form_classifier.dart';
import 'data/mlkit_pose_detector_service.dart';
import 'data/pose_detector_service.dart';
import 'data/pose_landmark.dart';
import 'data/pose_projection.dart';
import 'data/pose_silhouette.dart';
import 'data/pose_target.dart';
import 'data/rep_counter.dart';
import 'data/coach_phases.dart';
import 'state/coach_phase_providers.dart';
import 'state/form_check_providers.dart';
import 'widgets/camera_flip_button.dart';
import 'widgets/coach_hud.dart';
import 'widgets/coach_intro_cards.dart';
import 'widgets/coach_readiness_band.dart';

/// Live form-check page. Starts the pose-detection service in
/// initState, renders the camera preview behind the cue overlay, and
/// stops the service on dispose.
///
/// Marketing line per the assessment: "form feedback on commodity
/// Android — no $2,500 hardware required."
class FormCheckPage extends ConsumerStatefulWidget {
  const FormCheckPage({super.key});

  @override
  ConsumerState<FormCheckPage> createState() => _FormCheckPageState();
}

class _FormCheckPageState extends ConsumerState<FormCheckPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  /// Drives the demonstration loop: down on the way out, up on the way back.
  ///
  /// One second each way. Slower reads as a stretch rather than a repetition;
  /// faster is hard to follow while also trying to copy it.
  /// Built in [initState], not lazily on first use.
  ///
  /// It was `late final ... = AnimationController(...)`, which constructs on
  /// first read. That was harmless while `build` always reached `_syncDemo`,
  /// and became a crash the moment R11h gave the page a branch that returns
  /// before it: a user who backs out on the intro card never touches `_demo`,
  /// so `dispose()`'s `_demo.dispose()` was the FIRST read — constructing a
  /// ticker against a deactivated element, mid-unmount. Caught by the lifecycle
  /// suite, not by reasoning.
  late final AnimationController _demo;

  /// Run the demonstration only while it is on screen.
  ///
  /// A repeating controller ticks whether or not anything is listening, so
  /// leaving it running would keep the vsync alive for the whole set — next to
  /// a camera and a pose detector, on a phone the user is not holding.
  ///
  /// Also gated on reduce motion: a continuously looping silhouette is
  /// exactly the ambient motion that setting exists to suppress, and the
  /// static top-of-rep silhouette (`_demo.value == 0`) still shows the target
  /// pose to copy, just without the up/down cycle demonstrating it.
  void _syncDemo(bool wanted) {
    final bool animate = wanted && !context.reduceMotion;
    if (animate == _demo.isAnimating) return;
    if (animate) {
      _demo.repeat(reverse: true);
    } else {
      _demo.stop();
      if (!wanted || context.reduceMotion) _demo.value = 0;
    }
  }

  bool _started = false;
  Object? _startError;

  /// How long `start()` may take before the screen stops waiting.
  ///
  /// Opening a camera and loading the ML Kit model takes a second or two on a
  /// slow device. Fifteen is generous for that and still finite, which is the
  /// point: there was no bound at all, so a native call that never returned —
  /// the camera held by another app, a permission dialog that never resolved —
  /// left a spinner turning forever, with no message and no way out.
  static const _startTimeout = Duration(seconds: 15);

  /// Invalidates in-flight starts. Every start captures the value; a start
  /// whose token has moved on discards its own result instead of writing it.
  int _lifecycle = 0;

  /// A teardown still running. Starting the camera on top of one is how the
  /// preview comes back as a permanently black rectangle while `_started` says
  /// everything is fine.
  Future<void>? _stopping;

  /// Captured at first use so dispose() can release the camera WITHOUT touching
  /// `ref`. Reading a provider from dispose() throws "Cannot use ref after the
  /// widget was disposed" — found by the on-device suite, invisible to the
  /// widget tests because they never unmount this page.
  PoseDetectorService? _service;

  @override
  void initState() {
    super.initState();
    _demo = AnimationController(
      vsync: this,
      // Halved, operator: "надо снизить скорость силуета в двое" -- was
      // 1000ms each way (2s per full up-down cycle), now 2000ms (4s/cycle).
      duration: const Duration(milliseconds: 2000),
    );
    WidgetsBinding.instance.addObserver(this);
    // The rep session and the match readout are app-scoped, so they outlive
    // this page. Walking back in showed the last set's count and the verdict
    // banner from a repetition performed minutes ago, over a camera that had
    // not yet delivered a frame. Cleared on a fresh mount only — a lifecycle
    // resume goes through `didChangeAppLifecycleState`, and wiping the count
    // because someone glanced at a notification would be worse than stale.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(repSessionControllerProvider.notifier).resetSet();
      ref.read(poseMatchProvider.notifier).state = null;
      // A different scene each time the coach is opened, which is what the
      // operator asked for. Here rather than in the provider's own `build`
      // because the provider is app-scoped: built once per process, it would
      // hold the same picture for a whole day of training. This is the same
      // fresh-mount hook the reset above uses, and for the same reason — a
      // lifecycle resume goes through `didChangeAppLifecycleState` and must NOT
      // change the scene under someone mid-set.
      ref.read(coachBackdropProvider.notifier).shuffle();
    });
    // R11h: arriving on this page is NOT asking for the camera any more. The
    // intro card comes first, and `_openCamera` below is the
    // single place the hardware is requested — by a tap that says so.
  }

  /// True once the user has asked for the camera on this visit.
  ///
  /// Guards the lifecycle-resume path: coming back from the background while
  /// still on the intro card must not open a camera the user has not asked
  /// for, and `_started` alone cannot tell "not started yet" from "stopped
  /// when we backgrounded".
  bool _cameraRequested = false;

  /// The intro card's primary button: ask for the camera, then choose a
  /// movement.
  ///
  /// The PERMISSION is asked here and the hardware is not. That split is the
  /// operator's own (2026-09-01): the intro card is the screen that explains
  /// why a camera is needed, so it is the only honest place to ask — while the
  /// camera itself must stay off until the start button one screen later.
  ///
  /// The ask is deliberately not awaited. `ensurePermission` reports nothing
  /// by design (`pose_detector_service.dart:36`) — a refusal surfaces from the
  /// later `start()` as the same typed failure every other refusal does, and
  /// is rendered in one place. Blocking the screen transition on a dialog
  /// would leave the user looking at the card they just dismissed.
  void _continueToSelection() {
    ref.read(coachPhaseControllerProvider.notifier).continueToSelection();
    final svc = ref.read(poseDetectorServiceProvider);
    _service = svc;
    // Kept, not fire-and-forgotten. The screen moves on immediately — a
    // transition that waited on a dialog would leave the user looking at the
    // card they just dismissed — but `_startDetector` awaits this before it
    // touches the camera. Without that, pressing the start button inside the
    // window where the ask is still resolving reaches
    // `CameraSession.start(requestPermission: false)`, which READS the status
    // and throws on a still-denied one rather than waiting: the user grants
    // permission and lands on the camera-failure card anyway. Caught by
    // GPT-PM's review of this gate.
    //
    // Swallowed rather than left unhandled: a platform-channel failure in
    // here is already re-raised by the next `start()` with its cause attached
    // (`camera_session.dart:186-191`), and an unawaited throw would otherwise
    // reach the zone's error handler as an unexplained crash.
    _permissionAsk = svc.ensurePermission().catchError((Object _) {});
  }

  /// The permission ask started on the intro card, while it is still resolving.
  ///
  /// Cleared once awaited: it is a one-time handshake per visit, not a latch.
  Future<void>? _permissionAsk;

  /// The selection screen's primary button — «Нажмите когда готовы».
  ///
  /// Moves the phase and nothing else. Opening the camera is [build]'s job, on
  /// the rule "past the selection screen means the camera belongs open" — so
  /// the phase is the single source of truth, and anything else that
  /// legitimately puts the session into a camera phase (a test starting at the
  /// screen it is actually about; a future deep link into a set) gets a camera
  /// without having to know this method exists.
  void _startSet() =>
      ref.read(coachPhaseControllerProvider.notifier).openCamera();

  /// Back out of the live screen to the movement picker, camera off.
  ///
  /// Operator, point 3. "Back" here does NOT leave the coach, so it cannot be
  /// a `Navigator.pop` — and it has to release the camera itself, because the
  /// page is not being unmounted and `dispose` will not run.
  void _backToSelection() {
    final PoseDetectorService svc =
        _service ?? ref.read(poseDetectorServiceProvider);
    _service = svc;
    // Any start still in flight belongs to the session being left behind.
    _lifecycle++;
    _stopping = svc.stop();
    // So the next press of the start button opens the camera again. Without
    // this the flag would still read "already asked for on this visit" and
    // `build` would never re-arm the detector.
    _cameraRequested = false;
    // The set is over, and the numbers from it belong to it. This is the same
    // clearing `initState` performs on a fresh mount, for the same reason: a
    // count from a set the user has walked away from, sitting over a preview
    // that has not delivered a frame yet, is stale in the way that reads as a
    // bug.
    ref.read(repSessionControllerProvider.notifier).resetSet();
    ref.read(poseMatchProvider.notifier).state = null;
    ref.read(coachPhaseControllerProvider.notifier).backToSelection();
    if (mounted) {
      setState(() {
        _started = false;
        _startError = null;
      });
    }
  }

  void _startDetector({bool requestPermission = false}) {
    final token = ++_lifecycle;
    _started = false;
    _startError = null;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        // Let any teardown finish first. Backgrounding the app fires stop()
        // and resuming fires start(); nothing sequenced them, so a fast
        // switch away and back could run the two against the same camera.
        final stopping = _stopping;
        if (stopping != null) {
          await stopping;
          _stopping = null;
        }
        if (!mounted || token != _lifecycle) return;

        // And any permission ask started on the intro card. Deliberately
        // OUTSIDE the timeout below, for the same reason `ensurePermission`
        // itself is: this waits on a person reading a dialog, and that must
        // not share a deadline meant to catch a hung platform call.
        final ask = _permissionAsk;
        if (ask != null) {
          await ask;
          _permissionAsk = null;
          if (!mounted || token != _lifecycle) return;
        }

        final svc = ref.read(poseDetectorServiceProvider);
        _service = svc;
        // Deliberately OUTSIDE the timeout below. That bound exists to catch a
        // platform call that hung; this step waits for a person to read a
        // dialog, and the two must not share a deadline. Fifteen seconds is
        // right for the first and absurd for the second.
        if (requestPermission) {
          await svc.ensurePermission();
          if (!mounted || token != _lifecycle) return;
        }
        await svc.start().timeout(_startTimeout);
        // Two guards, not one. `mounted` catches the page being closed;
        // the token catches a newer start or a stop that overtook this one,
        // which would otherwise flip `_started` to true over a dead camera.
        if (!mounted || token != _lifecycle) return;
        setState(() {
          _started = true;
          _startError = null;
        });
      } catch (e) {
        if (!mounted || token != _lifecycle) return;
        setState(() => _startError = e);
      }
    });
  }

  /// Release the camera when the app leaves the foreground and pick it back
  /// up on resume — a CameraController held across backgrounding comes back
  /// frozen, and on some devices the OS revokes it outright.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      final PoseDetectorService svc =
          _service ?? ref.read(poseDetectorServiceProvider);
      _service = svc;
      // Any start still in flight belongs to the session being torn down.
      _lifecycle++;
      _stopping = svc.stop();
      if (mounted) setState(() => _started = false);
    } else if (state == AppLifecycleState.resumed &&
        mounted &&
        !_started &&
        // Not while the user is still on the intro card.
        _cameraRequested) {
      _startDetector();
    }
  }

  @override
  void dispose() {
    // Observer first. It used to be second, behind `_demo.dispose()`, and when
    // that line threw the page stayed registered as a lifecycle observer after
    // being disposed — so the NEXT screen's background/resume arrived at a dead
    // widget and failed with "Cannot use ref after the widget was disposed".
    // One throw, two unrelated-looking failures.
    WidgetsBinding.instance.removeObserver(this);
    _demo.dispose();
    // stop() releases the camera AND leaves the service restartable, so a
    // second visit to this page works. (It used to leave `_initialised` true,
    // which made every later start() a silent no-op — the feature was dead
    // after the first visit and the front camera stayed held.)
    _service?.stop();
    super.dispose();
  }

  /// Phase [CoachPhase.selection]: which movement, what it looks like, and the
  /// button that turns the camera on.
  ///
  /// Operator, point 2: «оставить только подогнать силуэт под вас и выбор
  /// упражнений и кнопку начать». So exactly those three things, plus the
  /// looping demonstration that replaces the preview — no banners (they moved
  /// to the intro card), no camera controls in the bar (there is no camera to
  /// control), no counters, no cue card.
  ///
  /// The demonstration panel deliberately shares the live preview's shape:
  /// same 9:16, same radius, same ground. It is standing in for the thing the
  /// button opens, so a different frame would read as a different screen.
  Widget _selectionScreen(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return HudSkyBackground(
      selection: HudSkySelection(phase: HudSkyPhase.forTime(DateTime.now())),
      child: FrostedScaffold(
        appBar: GlassAppBar(title: l10n.formcheckFormCoach),
        body: HudQuality(
          frostedGlass: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
            children: [
              const _CompleteProfileCard(),
              const _ExercisePicker(),
              const SizedBox(height: 12),
              // Labelled, not excluded. A `CustomPaint` emits no semantics of
              // its own, so without this the panel is a silent hole in the
              // middle of the screen — and it is the screen's main content,
              // not decoration. One static label rather than a live
              // description of the pose: a screen reader re-announcing a
              // looping animation would talk over everything else.
              Semantics(
                container: true,
                label: l10n.formcheckSelectionDemoSemantics,
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.85),
                      child: _Silhouette(
                        key: const Key('coach.selection.demo'),
                        demo: _demo,
                        demonstrating: true,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AppPrimaryButton(
                key: const Key('coach.selection.start'),
                label: l10n.formcheckSelectionStart,
                onPressed: _startSet,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // R11h. One card before anything opens. Deliberately ABOVE every provider
    // watch below, `formFeedbackControllerProvider` in particular: watching it
    // is what subscribes to the frame stream, so returning early here is also
    // what guarantees nothing is listening for frames while the user is still
    // reading.
    final phase = ref.watch(coachSessionProvider).phase;
    if (phase == CoachPhase.launch) {
      return CoachIntroCard(onContinue: _continueToSelection);
    }

    // Same argument one screen further on: the movement picker has no camera
    // either, so it returns before anything below subscribes to frames.
    if (phase == CoachPhase.selection) {
      // The demonstration is the whole point of this screen, so it runs
      // unconditionally here rather than being derived from a set that has not
      // started. `_syncDemo` still honours reduce-motion.
      _syncDemo(true);
      return _selectionScreen(context);
    }

    // Past the selection screen, so the camera belongs open. Once per visit: the flag
    // is what stops a rebuild from starting a second one, and it is also what
    // the lifecycle-resume path reads to tell "stopped" from "never asked
    // for". Deferred to a post-frame callback because starting a camera is a
    // side effect and build must not have one mid-frame.
    if (!_cameraRequested) {
      _cameraRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // NOT `requestPermission: true` any more. The ask moved one screen
        // earlier, to `_continueToSelection`, and asking a second time here
        // would be actively harmful rather than merely redundant: a user who
        // just refused is still in the ANDROID `denied` state, which is
        // "askable" (`camera_session.dart:184`), so they would get the same
        // dialog again immediately — and a second refusal on Android 13+ is
        // close to permanent. The failure card's retry button still asks,
        // because pressing it is an unambiguous request.
        if (mounted) _startDetector();
      });
    }

    // Watched for its side effects, not its value: building this controller is
    // what subscribes to the frame stream, which is what feeds the gate verdict
    // and the coordinate probe. The card itself now reads the rep verdict
    // instead of the current frame's feedback.
    ref.watch(formFeedbackControllerProvider);
    final svc = ref.watch(poseDetectorServiceProvider);
    final session = ref.watch(repSessionControllerProvider);
    final showRepCount = showRepCountFor(ref.watch(selectedExerciseProvider));
    final muted = ref.watch(voiceMutedProvider);
    // Whether the strip above is currently telling the user that the coach
    // cannot see them. Computed once, here, and consumed by the two surfaces
    // that must not talk over it — which is the whole of the fix: the page
    // decides who speaks, instead of each widget deciding for itself from its
    // own private signal and all of them deciding "me".
    final instructing = ref.watch(coachIsInstructingProvider);
    // Either the camera never opened, or the native detector died mid-stream.
    // Both mean "no reps will be counted", so both belong in the same slot.
    final failure = _startError ?? ref.watch(poseErrorProvider);

    // Avatar mode: a continuous pacer, not a one-off cue. The target
    // silhouette loops the correct rep for as long as the coach is open,
    // standing in for the design reference's own auto-looping demo
    // (`Fitness Form Coach Phone.dc.html`'s `componentDidMount` timer)
    // before the user has even stepped into frame, and continuing alongside
    // the live tracked skeleton once they have — the two are independent
    // readouts (silhouette = the shape to match, skeleton = how the user is
    // actually doing), not a hand-off from one to the other. Operator,
    // twice, after this used to stop the loop the instant a rep started:
    // "силуэт и скелет всегда видны... силуэт показывает как правильно
    // надо приседать, человек повторяет это, а скелет показывает как
    // правильно человек это делает."
    //
    // Non-avatar mode keeps the original behaviour: demonstrate until the
    // movement starts, then get out of the way — that mode draws a SOLID,
    // STILL target over the raw camera (`_SilhouettePainter`'s non-demo
    // branch) that the match score is read against, and an outline that
    // keeps moving is not one you can hit (see `_Silhouette`'s own doc).
    // Never over a spinner or an error — there is nothing to copy it onto.
    final demonstrating = failure == null &&
        (ref.watch(avatarModeProvider) ||
            (_started && session.repCount == 0 && session.phase == RepPhase.top));
    _syncDemo(demonstrating);

    // Two switches, one held frame. Dropping it on the way out of either mode
    // stops a pose from a minute ago flashing over a live camera on the way
    // back in — but only the mode being left gets to decide that, and only when
    // nothing else is still drawing from it.
    //
    // Written once rather than as a condition in each callback: the first
    // version had the avatar toggle check its neighbour and the skeleton toggle
    // clear unconditionally, so turning the skeleton off blanked the avatar
    // mid-set. A rule split across two call sites is a rule that drifts, which
    // is exactly how that happened.
    void dropHeldPoseIfUnwatched() {
      if (!ref.read(showSkeletonProvider) && !ref.read(avatarModeProvider)) {
        ref.read(latestPoseFrameProvider.notifier).state = null;
      }
    }

    // The gate's first pass wrapped only the intro card
    // (`coach_intro_cards.dart`) in `HudSkyBackground` and missed this
    // branch -- `/form-check` is a root route outside `MainShell`
    // (`app_router.dart:399-402`), so the live-coach and summary phases
    // rendered here fell back to the flat theme colour behind
    // `FrostedScaffold`'s transparency exactly the same way the intro
    // cards used to. The camera preview itself already owns its own
    // backdrop (`Colors.black.withValues(alpha: 0.85)` a few hundred
    // lines below) and is unaffected -- this only puts the sky behind
    // the surrounding content cards (banner, upgrade, exercise picker,
    // set summary) that were sitting on flat colour either side of it.
    return PopScope(
      // Operator, point 3: back from the live screen returns to the movement
      // picker, not out of the coach. Both the bar's arrow (`leading` below)
      // and the system gesture have to mean the same thing, and only this
      // handles the gesture — `leading` alone would give Android Back a
      // different destination from the arrow sitting next to it.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _backToSelection();
      },
      child: HudSkyBackground(
      selection: HudSkySelection(phase: HudSkyPhase.forTime(DateTime.now())),
      child: FrostedScaffold(
      appBar: GlassAppBar(
        title: AppLocalizations.of(context).formcheckFormCoach,
        leading: IconButton(
          key: const Key('coach.live.back'),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: _backToSelection,
        ),
        actions: [
          // First, because it is the control that decides whether the coach
          // can see the user at all. The skeleton and the mute switch adjust
          // what is reported about a body already in frame.
          CameraFlipButton(svc: svc),
          AppIconButton(
            icon: ref.watch(showSkeletonProvider)
                ? Icons.accessibility_new
                : Icons.accessibility_outlined,
            tooltip: AppLocalizations.of(context).formcheckShowSkeleton,
            onPressed: () {
              ref.read(showSkeletonProvider.notifier).state =
                  !ref.read(showSkeletonProvider);
              dropHeldPoseIfUnwatched();
            },
          ),
          AppIconButton(
            icon: ref.watch(avatarModeProvider)
                ? Icons.person
                : Icons.person_outline,
            tooltip: ref.watch(avatarModeProvider)
                ? AppLocalizations.of(context).formcheckAvatarOff
                : AppLocalizations.of(context).formcheckAvatarOn,
            onPressed: () {
              ref.read(avatarModeProvider.notifier).state =
                  !ref.read(avatarModeProvider);
              dropHeldPoseIfUnwatched();
            },
          ),
          AppIconButton(
            icon: muted ? Icons.volume_off : Icons.volume_up,
            tooltip: muted
                ? AppLocalizations.of(context).formcheckUnmuteCues
                : AppLocalizations.of(context).formcheckMuteCues,
            onPressed: () =>
                ref.read(voiceMutedProvider.notifier).state = !muted,
          ),
        ],
      ),
      // The set is over: the numbers get the screen. Not an early `return`
      // above — every provider watched further up stays watched, so the frame
      // subscription and the camera survive the summary and "new set" resumes
      // instantly instead of walking back through the intro card and the gate.
      //
      // `HudPanel` frosts its backdrop with `BackdropFilter` by default
      // (`HudQuality.frostedOf` falls back to true with no ancestor), and this
      // screen is a genuine per-frame-repaint page, not a static one:
      // `formFeedbackControllerProvider` is watched above (`:271`) purely for
      // its side effect of subscribing to the pose-frame stream, and its
      // `_onFrame` (`form_check_providers.dart:563-616`) unconditionally
      // reassigns `state` on every camera frame — `FormFeedback` has no `==`
      // override, so this rebuilds the whole body at camera-frame cadence
      // (tens of Hz) whenever the camera is running, not once a second like
      // M5's set/rest timers. Every `HudPanel` in this body (the on-device
      // disclaimer, the optional complete-profile/upgrade/voice-error cards,
      // the rep summary) sits inside that same rebuilding subtree, so it is
      // opted out the same way `workout_player_page.dart` opts out M5.
      body: HudQuality(
        frostedGlass: false,
        child: phase == CoachPhase.summary
            ? ListView(
                padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
                children: [
                  // A1. Here as well as on the live screen, and deliberately not
                  // only there: the summary is where the rep count stops being a
                  // number ticking on a preview and becomes a result the user
                  // reads as what they did. That is the strongest version of the
                  // claim, so it is the one that most needs qualifying.
                  ExperimentalBanner(
                      message:
                          AppLocalizations.of(context).experimentalFormCoach),
                  _SetSummaryCard(
                    session: session,
                    onReset: () => ref
                        .read(repSessionControllerProvider.notifier)
                        .resetSet(),
                  ),
                  const SizedBox(height: 16),
                  AppPrimaryButton(
                    key: const Key('form_check.new_set'),
                    label: AppLocalizations.of(context).formcheckNewSet,
                    onPressed: () {
                      // Reset first, then unpause. The other order would let the
                      // frames that arrive between the two land on the previous
                      // set's counter.
                      ref
                          .read(repSessionControllerProvider.notifier)
                          .resetSet();
                      ref.read(coachPhaseControllerProvider.notifier).start();
                    },
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
                children: [
                  // The experimental banner and the sustainer card used to open
                  // this list. Both moved to `CoachIntroCard` on 2026-09-01:
                  // this screen sits PAST the camera, so a warning here reached
                  // the user after they had already granted the permission it
                  // was supposed to inform.
                  //
                  // Asked for here rather than left to the profile tab, because this
                  // is the one screen where the answers visibly change something: the
                  // outline the user is about to aim at. Operator: "если етих данных
                  // нет в анкете то как только кто то заходит к тренеру тот должен
                  // предложить дозаполнить нехватающих деталей."
                  const _CompleteProfileCard(),
                  // Which movement is being coached. Above the camera on purpose: the
                  // rules that will judge you are chosen here, so it should be read
                  // before the set, not discovered after it.
                  const _ExercisePicker(),
                  const SizedBox(height: 12),
                  // The set controls used to sit HERE, above the preview, to keep
                  // them away from the cue card at the bottom of the picture. G3
                  // moved them below the counters panel, where the reference puts
                  // them — which does not reintroduce that defect, because the cue
                  // card is inside the preview and everything below it is not.
                  AspectRatio(
                    aspectRatio: 9 / 16,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.85),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (failure != null)
                              Center(
                                child: _StartFailure(
                                  failure: failure,
                                  // Pressing "try again" on a permission failure is
                                  // the clearest possible ask for the camera, so this
                                  // one always requests. Passing the tear-off would
                                  // silently take the `false` default -- it type-checks
                                  // (optional named parameters are droppable in Dart),
                                  // which is exactly why it would not have been caught.
                                  onRetry: () =>
                                      _startDetector(requestPermission: true),
                                ),
                              )
                            else if (!_started)
                              const Center(
                                child: CircularProgressIndicator(
                                    color: Colors.white),
                              )
                            // The camera keeps running either way — detection reads the
                            // image stream, not this widget. What changes is only what
                            // the user is shown in its place.
                            else if (ref.watch(avatarModeProvider))
                              const _AvatarBackdrop()
                            else
                              _CameraPreview(svc: svc),
                            // Everything below is a readout of a running camera. With
                            // no camera there is nothing to read out, and the bottom
                            // card sat directly on top of the retry button — an error
                            // screen whose one useful control could not be pressed.
                            if (failure == null) ...[
                              // Directly over the preview and under everything else:
                              // it is a picture of the camera's input, so it belongs
                              // against the input rather than on top of the verdicts.
                              // Under the skeleton, which is a diagnostic drawn ON the
                              // picture — and in avatar mode this IS the picture.
                              const Positioned.fill(
                                child: IgnorePointer(child: _PoseAvatar()),
                              ),
                              const Positioned.fill(
                                child: IgnorePointer(child: _SkeletonOverlay()),
                              ),
                              // Over the preview, under the readouts: what to do, then
                              // the shape to arrive at.
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: _Silhouette(
                                    demo: _demo,
                                    demonstrating: demonstrating,
                                  ),
                                ),
                              ),
                              // One strip, laid out top-down. Previously these were
                              // three independently positioned children of this Stack,
                              // and two of them claimed the same corner -- see
                              // `CoachTopStrip`.
                              // MVP1.G2: was `top: 12` with no SafeArea --
                              // a latent missing-inset defect surfaced during
                              // this gate's Android-16 verification, not
                              // necessarily created by the 35->36 move itself
                              // (Android already enforces edge-to-edge by
                              // default from API 35; API 36 additionally
                              // removes the app's own opt-out). Same defect
                              // and same fix as `ScanTopBar`'s sibling in
                              // scanner_page.dart.
                              Positioned(
                                left: 0,
                                right: 0,
                                top: 0,
                                child: SafeArea(
                                  bottom: false,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: CoachTopStrip(
                                      session: session,
                                      showRepCount: showRepCount,
                                    ),
                                  ),
                                ),
                              ),
                              // Silent while the strip above is telling the user the
                              // coach cannot see them. A verdict on the last rep is
                              // still true in that moment and is still the wrong thing
                              // to read: the question on screen has become "why has it
                              // stopped", and answering a different one underneath is
                              // how three messages ended up disagreeing in one frame.
                              if (!instructing)
                                Positioned(
                                  left: 12,
                                  right: 12,
                                  bottom: 12,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _PassedRuleChips(session: session),
                                      _CueCard(
                                        feedback: session.lastRepCue,
                                        verdict: session.lastRepVerdict,
                                        reject: session.lastReject,
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // The four counters, under the picture, exactly where the
                  // reference has them. G3 built the panel; G4 measures what
                  // goes in it — and leaves «—» wherever the measurement does
                  // not exist for this movement, which for symmetry is most of
                  // the time. See `coach_counters.dart`.
                  const _CoachCounters(),
                  const SizedBox(height: 12),
                  _SetControls(phase: phase),
                  const SizedBox(height: 4),
                  // A coach that has gone silent because the device has no voice
                  // installed is indistinguishable from a coach with nothing to say.
                  // `lastErrorMessage` existed for exactly this and nothing read it —
                  // the same wiring `health_sync_card.dart` already uses for health.
                  if (ref.watch(voiceErrorProvider) != null) ...[
                    HudPanel(
                      child: Text(
                        AppLocalizations.of(context).formcheckVoiceUnavailable,
                        key: const Key('form_check.voice_error'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppPalette.auroraPeach,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // The coordinate diagnostic, now behind a debug flag.
                  //
                  // It shipped in release on purpose: the measurement could only be
                  // taken on a real phone, in a gym, with a real body in frame, and a
                  // value that never leaves a debug build is a value nobody reads. That
                  // argument expired the moment the number arrived —
                  // `pose[pixels] n=807 x -0.466..1.968 (bound 0.667) y -2.173..3.015`,
                  // recorded in the R0 audit §7.5. The instrument stays; only its
                  // exposure to users goes.
                  //
                  // What that line MEANS is still open, and this comment used to call
                  // it an open defect on the strength of the extents alone. It cannot
                  // be: BlazePose extrapolates the joints that leave the frame and the
                  // service forwards them unfiltered, so those numbers fit a broken
                  // conversion and a perfectly healthy session equally well. The probe
                  // now reports the extent restricted to landmarks above
                  // `minLikelihood` beside the full one, which is the measurement that
                  // separates the two — see `pose_unit_probe.dart`. Until that second
                  // line has been read off a real device, neither verdict is earned.
                  if (ref.watch(poseDebugOverlayProvider) &&
                      !ref.watch(poseUnitReportProvider).isEmpty) ...[
                    Text(
                      ref.watch(poseUnitReportProvider).summary,
                      key: const Key('form-check-unit-probe'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white38,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Mid-set the summary is a running tally under the preview; once the
                  // user calls the set finished it is the whole screen, and the tally
                  // stops being something to glance past.
                  if (showRepCount && phase != CoachPhase.summary) ...[
                    _SetSummaryCard(
                      session: session,
                      onReset: () => ref
                          .read(repSessionControllerProvider.notifier)
                          .resetSet(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  HudPanel(
                    child: Text(
                      AppLocalizations.of(context)
                          .formcheckFormCoachRunsOnDeviceUsing,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
      ),
      ),
      ),
    );
  }
}

/// Start, pause, resume, finish — the four taps the phase machine was built for
/// and had no caller for.
///
/// `CoachPhaseController` has shipped `start`/`pause`/`resume`/`finish` since
/// R11h and nothing in the app called any of them, so `active` was unreachable
/// and `paused` was a value the enum could hold but the product could not. That
/// is worse than a missing feature: every reader of the phase, including the
/// guard in `RepSessionController._onFrame`, was correct about a state that
/// could not occur.
class _SetControls extends ConsumerWidget {
  const _SetControls({required this.phase});

  final CoachPhase phase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final coach = ref.read(coachPhaseControllerProvider.notifier);

    switch (phase) {
      case CoachPhase.ready:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppPrimaryButton(
            key: const Key('form_check.start_set'),
            label: l10n.formcheckStartSet,
            icon: Icons.play_arrow,
            onPressed: coach.start,
          ),
        );
      case CoachPhase.active:
      case CoachPhase.paused:
        final paused = phase == CoachPhase.paused;
        // Not two equal buttons any more. The reference weights them: pause is
        // a square icon, closing the set is the wide pill with the arrow —
        // because one of them is a step in the set and the other one ends it,
        // and two identical halves said they were the same kind of choice.
        // Both keep their keys and their callbacks.
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              _RoundIconButton(
                key: Key(paused
                    ? 'form_check.resume_set'
                    : 'form_check.pause_set'),
                icon: paused ? Icons.play_arrow : Icons.pause,
                // Still labelled for anyone not looking at it: an icon-only
                // control with no semantics is a control a screen reader
                // cannot name.
                tooltip:
                    paused ? l10n.formcheckResumeSet : l10n.formcheckPauseSet,
                onPressed: paused ? coach.resume : coach.pause,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppPrimaryButton(
                  key: const Key('form_check.finish_set'),
                  label: l10n.formcheckCloseSet,
                  icon: Icons.arrow_forward,
                  onPressed: coach.finish,
                ),
              ),
            ],
          ),
        );
      // Nothing to control: the camera is not open, or the view is not usable
      // yet and the readiness band is already saying why.
      case CoachPhase.launch:
      case CoachPhase.selection:
      case CoachPhase.qualityCheck:
      case CoachPhase.calibration:
      case CoachPhase.summary:
        return const SizedBox.shrink();
    }
  }
}

/// A square, icon-only control, sized to stand beside a full-height pill.
/// The four trainer counters, formatted for the panel.
///
/// Formatting only. What each number MEANS, and whether it exists at all, is
/// [coachCountersFor]'s business — this widget cannot invent a reading, which
/// is why every field here is a null-check and none of them is a fallback.
class _CoachCounters extends ConsumerWidget {
  const _CoachCounters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = ref.watch(coachCountersProvider);
    String? seconds(double? v) =>
        v == null ? null : l10n.formcheckHudSeconds(v.toStringAsFixed(1));
    final split = c.symmetryLeftPercent;
    final off = c.symmetryOffBy;
    return CoachCountersPanel(
      key: const Key('form_check.hud.counters'),
      tempo: seconds(c.tempoSeconds),
      amplitude:
          c.amplitude == null ? null : '${(c.amplitude! * 100).round()}%',
      // Written as the reference writes it — both halves, so it reads as a
      // split rather than as a score for one leg.
      symmetry: split == null ? null : '$split/${100 - split}',
      // Five points off even is the same band `SquatDepthClassifier` treats as
      // a nudge rather than a fault, and ten is where it stops being posture
      // and starts being a limp. A `PRODUCT_HEURISTIC`: no measurement of real
      // lifters set these, and they colour a number without changing it.
      symmetryTone: off == null
          ? CoachTone.neutral
          : off < 5
              ? CoachTone.good
              : off < 10
                  ? CoachTone.warn
                  : CoachTone.fault,
      pause: seconds(c.pauseSeconds),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Material(
            color: theme.colors.surfaceElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: theme.colors.outline),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: Icon(icon, color: theme.colors.textPrimary, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraPreview extends StatelessWidget {
  const _CameraPreview({required this.svc});

  /// Typed, not `dynamic`. The old signature defeated type promotion, so the
  /// controller had to be fished out with an `as` cast.
  final PoseDetectorService svc;

  @override
  Widget build(BuildContext context) {
    // Copied to a local: Dart promotes locals, not instance fields, so the
    // `is!` check below would not narrow `this.svc`.
    final svc = this.svc;
    if (svc is! MlKitPoseDetectorService) {
      // Mock service in test/dev — show the static placeholder.
      return const Center(
        child: Icon(Icons.videocam_outlined, color: Colors.white24, size: 80),
      );
    }
    // Watches the session's controller instead of reading it once. The old code
    // took `svc.cameraController as CameraController?` through a `dynamic`, so
    // it saw whatever value happened to be there at build time and had no way
    // to learn that the camera had become ready — the same defect that left the
    // Scan tab's viewfinder a permanent black square.
    return ValueListenableBuilder<CameraController?>(
      valueListenable: svc.session.surface,
      builder: (context, ctl, _) {
        if (ctl == null) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        return ValueListenableBuilder<CameraValue>(
          valueListenable: ctl,
          builder: (context, value, __) => value.isInitialized
              ? CameraPreview(ctl)
              : const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
        );
      },
    );
  }
}

/// The body as the detector sees it, drawn over the preview.
///
/// Every other readout on this page is a conclusion — a count, a verdict, a
/// percentage — and a wrong conclusion has two very different causes: the rule
/// misjudged a good repetition, or the detector never found the body. Those
/// want opposite responses from the user, and nothing on screen told them
/// apart. This does, in one glance.
class _SkeletonOverlay extends ConsumerWidget {
  const _SkeletonOverlay();

  /// Drawn as a body rather than as thirteen dots: a stick figure is legible at
  /// arm's length mid-set, a scatter of points is not.
  static const _bones = <(LandmarkType, LandmarkType)>[
    (LandmarkType.leftShoulder, LandmarkType.rightShoulder),
    (LandmarkType.leftHip, LandmarkType.rightHip),
    (LandmarkType.leftShoulder, LandmarkType.leftHip),
    (LandmarkType.rightShoulder, LandmarkType.rightHip),
    (LandmarkType.leftShoulder, LandmarkType.leftElbow),
    (LandmarkType.leftElbow, LandmarkType.leftWrist),
    (LandmarkType.rightShoulder, LandmarkType.rightElbow),
    (LandmarkType.rightElbow, LandmarkType.rightWrist),
    (LandmarkType.leftHip, LandmarkType.leftKnee),
    (LandmarkType.leftKnee, LandmarkType.leftAnkle),
    (LandmarkType.rightHip, LandmarkType.rightKnee),
    (LandmarkType.rightKnee, LandmarkType.rightAnkle),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(showSkeletonProvider)) return const SizedBox.shrink();
    // Never over the avatar. The avatar IS a skeleton — a lit one, inside the
    // body it belongs to — so drawing this on top adds a second, thinner,
    // differently-coloured copy of the same joints half a pixel away from the
    // first. On a real phone that read as a tracking failure rather than as a
    // diagnostic: two skeletons that never quite agree look like one skeleton
    // that cannot hold still. The toggle still governs the camera view, which
    // is the view the diagnostic was built for.
    if (ref.watch(avatarModeProvider)) return const SizedBox.shrink();
    final frame = ref.watch(latestPoseFrameProvider);
    if (frame == null) return const SizedBox.shrink();
    return CustomPaint(
      key: const Key('form_check.skeleton'),
      painter: _SkeletonPainter(frame: frame, bones: _bones),
    );
  }
}

class _SkeletonPainter extends CustomPainter {
  const _SkeletonPainter({required this.frame, required this.bones});

  final PoseFrame frame;
  final List<(LandmarkType, LandmarkType)> bones;

  Offset? _at(LandmarkType t, Size size) {
    final lm = frame.landmarks[t];
    if (lm == null) return null;
    return projectLandmark(lm.x, lm.y,
        frameAspect: frame.aspectRatio, canvas: size);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = AppPalette.auroraViolet.withValues(alpha: 0.85);

    for (final (a, b) in bones) {
      final pa = _at(a, size);
      final pb = _at(b, size);
      // A bone is drawn only when both ends exist. Reaching for a missing
      // joint's coordinate would put it at the origin, and a limb running to
      // the top-left corner looks like a detector that has lost its mind
      // rather than one that simply cannot see an ankle.
      if (pa != null && pb != null) canvas.drawLine(pa, pb, stroke);
    }

    for (final entry in frame.landmarks.entries) {
      final p = _at(entry.key, size);
      if (p == null) continue;
      // Confidence is the point of showing this at all: a joint the detector
      // is guessing at is drawn faint, so "it sees me but is unsure about my
      // left ankle" is visible without reading a number.
      canvas.drawCircle(
        p,
        4,
        Paint()
          ..color = Colors.white.withValues(
              alpha: 0.25 + 0.7 * entry.value.likelihood.clamp(0, 1)),
      );
    }
  }

  @override
  bool shouldRepaint(_SkeletonPainter old) =>
      old.frame.timestampMs != frame.timestampMs;
}

/// The scene the avatar stands in.
///
/// A photograph since 2026-08-15, chosen at random from ten each time the coach
/// is opened. It replaces `_AvatarBackdropPainter`, which was a painted dusk
/// gradient standing in for exactly this and said so in its own comment.
///
/// Three layers, and each earns its place:
///
/// 1. **A flat near-black underneath.** `Image.asset` resolves from the bundle
///    without a network, but not within the same frame as the first build. One
///    frame of white behind a dark figure is a flash, and this screen opens on
///    it every time.
/// 2. **The photograph, cover-fitted.** The assets are 1440x2560, the same 9:16
///    the panel is, so cover crops almost nothing — it is there for the phones
///    that are taller or shorter than 16:9, not as a framing decision.
/// 3. **A scrim, dark towards the bottom.** This is the layer that makes the
///    figure legible rather than the layer that makes the picture pretty. The
///    body is drawn near-black with a lit skeleton on it, and the ten scenes
///    were measured before being accepted: in the band the body occupies, mean
///    luminance runs 58 to 147 out of 255, with `04_fuji_sakura` at 147 (95th
///    percentile 244) and `09_forest_lake` at 135 (243). A white skeleton over
///    pale sakura or a bright lake is unreadable, and three of the ten are
///    bright enough for that to matter. Darkening the lower band fixes all
///    three without touching the seven that were already fine — which is why
///    the fix is a scrim and not a re-pick of the scenes.
class _AvatarBackdrop extends ConsumerWidget {
  const _AvatarBackdrop();

  @override
  Widget build(BuildContext context, WidgetRef ref) => RepaintBoundary(
        child: Stack(
          key: const Key('form_check.backdrop'),
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF0B0A14)),
            Image.asset(
              ref.watch(coachBackdropProvider),
              key: const Key('form_check.backdrop_photo'),
              fit: BoxFit.cover,
              // A missing or corrupt asset must not take the whole coach down
              // with it: the layer under this one is already a usable ground,
              // and the figure is what the user came for.
              //
              // Reported, though, rather than absorbed. Ten backdrops are
              // declared in `pubspec.yaml` and picked from at random, so a
              // dropped or misnamed one fails on roughly one launch in ten and
              // looks exactly like a design choice from the outside. Without
              // this line the only evidence would be a user saying the
              // background "sometimes" goes plain.
              errorBuilder: (_, error, __) {
                debugPrint('coach backdrop failed to load: '
                    '${ref.read(coachBackdropProvider)}: $error');
                return const SizedBox.shrink();
              },
            ),
            const DecoratedBox(
              key: Key('form_check.backdrop_scrim'),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  // Light at the top, where only sky sits behind the chrome, and
                  // heavy from the middle down, where the body is.
                  colors: [
                    Color(0x33000000),
                    Color(0x59000000),
                    Color(0xA6000000),
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ],
        ),
      );
}

/// The user, drawn as a figure instead of shown on camera.
class _PoseAvatar extends ConsumerWidget {
  const _PoseAvatar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(avatarModeProvider)) return const SizedBox.shrink();
    final frame = ref.watch(latestPoseFrameProvider);
    // Null is the detector saying it cannot see anyone — see
    // `mlkit_pose_detector_service.dart`'s empty frame. Drawing the last known
    // pose here would be the one failure this mode cannot afford: with the
    // camera image gone, a frozen figure and a tracking one look identical.
    // The gate has already turned that frame into a cue on the strip above, so
    // this draws nothing and lets the cue speak.
    if (frame == null) return const SizedBox.shrink();

    // Read, not built. The figure is derived once in `avatarFigureProvider`, so
    // that the status band above and this painter cannot reach different
    // conclusions about whether there is a body — which is precisely what
    // happened while this widget owned the answer and announced it in its own
    // centred box.
    final figure = ref.watch(avatarFigureProvider);
    if (figure == null) return const SizedBox.shrink();

    // A pose arrived and still produced no body: the avatar needs a shoulder
    // AND a hip to have a spine to mirror about, while
    // `SquatDepthClassifier.requiredLandmarks` needs neither — hips and knees
    // only. So on a squat framed low the gate reports `ok`, the counter counts
    // reps, and this has nothing to draw. Saying so is the status band's job
    // now (`avatarCannotPlaceBodyProvider`); here it is simply nothing to
    // paint.
    if (figure.torso.isEmpty) return const SizedBox.shrink();

    // See `avatarVerdictSeverity` for why this is gated on `canFault`, not
    // read from the feedback's severity alone, and why `matchScore` is the
    // fallback for the movements that gate excludes.
    final severity = avatarVerdictSeverity(
      ref.watch(activeClassifiersProvider),
      ref.watch(formFeedbackControllerProvider),
      matchScore: ref.watch(poseMatchProvider),
    );
    final colors = Theme.of(context).colors;

    return RepaintBoundary(
      child: CustomPaint(
        key: const Key('form_check.avatar'),
        painter: _PoseAvatarPainter(
          figure: figure,
          frame: frame,
          severity: severity,
          colorCorrect: colors.poseCorrect,
          colorError: colors.poseError,
        ),
      ),
    );
  }
}

/// A dark body with a lit skeleton inside it.
///
/// Deliberately the inverse of [_SilhouettePainter], which draws a translucent
/// shape for the user to stand INSIDE while the camera shows them through it.
/// This one is not something to aim at — it is the user, so it is opaque, and
/// the bones read as light because that is what distinguishes a body from a
/// shadow on a dusk backdrop.
class _PoseAvatarPainter extends CustomPainter {
  const _PoseAvatarPainter({
    required this.figure,
    required this.frame,
    required this.severity,
    required this.colorCorrect,
    required this.colorError,
  });

  /// Already built, by the widget above, which had to look at it anyway to
  /// decide between drawing a body and explaining why it cannot.
  final SilhouetteFigure figure;

  /// Carried for its aspect ratio, which the projection needs, and its
  /// timestamp, which is what makes one frame different from the last.
  final PoseFrame frame;

  /// 0/1/2 from the active classifier's worst [FormFeedback], or null when
  /// no active classifier is entitled to fault this movement
  /// ([FormClassifier.canFault]) — see [avatarVerdictSeverity] and the
  /// caller in `_PoseAvatar.build`. Null keeps the figure exactly as it
  /// painted before this feature existed: plain white, no glow, no verdict
  /// implied. This is deliberate for squat depth and hip-hinge, which are
  /// camera-angle-confounded and must not be shown as "correct" or "wrong"
  /// until the silhouette-match rule exists (`form_classifier.dart` —
  /// `SquatDepthClassifier`, `DeadliftHipHingeClassifier`).
  final int? severity;

  final Color colorCorrect;
  final Color colorError;

  /// The reference (`core/design/reference/full_handoff_v1/README.md:109`)
  /// defines exactly two pose-overlay glow states — correct (green) and
  /// error (red) — not a three-way traffic light; the "corrective nudge"
  /// colour belongs to the cue card, not the skeleton. So severity 1
  /// ("nudge") and 2 ("stop") both read as the error glow; only severity 0
  /// gets the correct one.
  Color? get _glowColor => switch (severity) {
        null => null,
        0 => colorCorrect,
        _ => colorError,
      };

  @override
  void paint(Canvas canvas, Size size) {
    // The same projection the skeleton uses, so the avatar lands exactly where
    // the body is rather than being re-fitted to the panel. `fitSilhouette` is
    // right for a target — a fixed shape centred in the box — and wrong here:
    // scaling to the figure's own bounds every frame would make the avatar
    // grow when the user raised their arms.
    Offset place(Offset p) => projectLandmark(
          p.dx,
          p.dy,
          frameAspect: frame.aspectRatio,
          canvas: size,
        );

    // Read off the projection rather than recomputing its formula: two points
    // exactly one unit apart in y come back exactly `scale` apart on screen.
    // Duplicating `projectLandmark`'s arithmetic here is how the two would
    // drift the next time it changes.
    final scale = (place(const Offset(0, 1)) - place(Offset.zero)).distance;
    final limbWidth = (figure.limbThickness * scale).clamp(4.0, 40.0);

    // One body, unioned — the B4 lesson. Adding parts as separate subpaths
    // strokes every internal seam, which is what made the target outline read
    // as a lattice of quadrilaterals on a real phone.
    var body = Path();
    void merge(Path part) {
      body = Path.combine(PathOperation.union, body, part);
    }

    merge(Path()..addPolygon([for (final p in figure.torso) place(p)], true));
    for (final limb in figure.limbs) {
      if (limb.length < 3) continue;
      merge(Path()..addPolygon([for (final p in limb) place(p)], true));
    }
    final head = figure.head;
    if (head != null) {
      merge(Path()
        ..addOval(
          Rect.fromCircle(center: place(head.$1), radius: head.$2 * scale),
        ));
    }

    canvas.drawPath(body, Paint()..color = const Color(0xE60A0912));
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (limbWidth * 0.14).clamp(1.5, 4.0)
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withValues(alpha: 0.45),
    );

    // Every bone in ONE path, so the glow is a single blurred draw rather than
    // one per limb. A blur is the most expensive thing on this canvas and this
    // runs at the camera's frame rate.
    final bones = Path();
    for (final (a, b) in figure.segments) {
      final pa = place(a);
      final pb = place(b);
      bones
        ..moveTo(pa.dx, pa.dy)
        ..lineTo(pb.dx, pb.dy);
    }
    final boneWidth = (limbWidth * 0.20).clamp(2.0, 6.0);

    // The verdict is a GLOW behind the bone, not a recolour of it — the
    // reference keeps the skeleton itself white in every state
    // (`full_handoff_v1/README.md:109`: "кости 3-3.4 px, цвет #FFFFFF").
    // Drawn before the white strokes below so the white line sits on top of
    // its own halo. Two blurred passes approximate the reference's stacked
    // `drop-shadow(0 0 5px)` + `drop-shadow(0 0 14px)`; the exact rgba
    // literals it specifies are single-theme, so this uses the app's own
    // theme-reactive `poseCorrect`/`poseError` tokens instead (already the
    // same green/red family), the same adaptation already made for the nav
    // icons against this same reference.
    final glowColor = _glowColor;
    if (glowColor != null) {
      canvas.drawPath(
        bones,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = boneWidth
          ..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, boneWidth * 2.3)
          ..color = glowColor.withValues(alpha: 0.55),
      );
      canvas.drawPath(
        bones,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = boneWidth
          ..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, boneWidth * 0.9)
          ..color = glowColor.withValues(alpha: 0.85),
      );
    }

    canvas.drawPath(
      bones,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = boneWidth * 2.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, boneWidth * 1.4)
        ..color = Colors.white.withValues(alpha: 0.45),
    );
    canvas.drawPath(
      bones,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = boneWidth
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.95),
    );

    // Joints last, so an articulation reads as a bright point rather than as a
    // thickening of the bone that runs through it.
    //
    // NOT IMPLEMENTED: the reference also marks the specific faulty joint
    // with a pulsing dashed ring (r=26, dash `4 6`, 1.1s cycle -- same doc).
    // `SilhouetteFigure.joints` is a flat `List<Offset>` with no landmark
    // identity by the time it reaches this painter (`pose_silhouette.dart`
    // discards the `LandmarkType` keys `PoseTarget.joints` carried), so
    // there is no way from here to know WHICH of these points is the one
    // `FormFeedback.rule`/`FormClassifier.requiredLandmarks` implicates.
    // Threading that identity through `buildSilhouette` is real surgery on
    // carefully-reasoned, already-tested geometry code (mirroring, the B4
    // union fix) and deliberately out of this pass -- see the DECISION_LOG
    // entry this change belongs to.
    final jointCore = Paint()..color = Colors.white;
    for (final j in figure.joints) {
      canvas.drawCircle(place(j), boneWidth * 0.62, jointCore);
    }
  }

  @override
  bool shouldRepaint(_PoseAvatarPainter old) =>
      old.frame.timestampMs != frame.timestampMs ||
      old.severity != severity;
}

/// The camera did not start, and what to do about it.
///
/// Three separate fixes live in this one widget, and they are related. The
/// screen used to render `"Камера недоступна: $e"` — a Russian sentence with a
/// platform exception spliced into the middle of it, which is neither Russian
/// nor useful. It offered no way to try again, so a transient failure ended the
/// session. And the most common failure of all, a `start()` that never returns,
/// did not reach here at all: it showed a spinner, forever.
class _StartFailure extends StatelessWidget {
  const _StartFailure({required this.failure, required this.onRetry});

  final Object failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final timedOut = failure is TimeoutException;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            timedOut
                ? l10n.formcheckCameraTimedOut
                : l10n.formcheckCameraUnavailable,
            key: const Key('form-check-error'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          // The raw error on its own line, and only when it says something the
          // headline does not. A timeout's `toString()` is "TimeoutException
          // after 0:00:15.000000" — the sentence above already covers it.
          if (!timedOut) ...[
            const SizedBox(height: 8),
            Text(
              l10n.formcheckErrorDetail(failure),
              key: const Key('form-check-error-detail'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
          const SizedBox(height: 12),
          AppTertiaryButton(
            key: const Key('form-check-retry'),
            onPressed: onRetry,
            label: l10n.formcheckTryAgain,
          ),
        ],
      ),
    );
  }
}

/// Everything drawn across the top of the camera preview, in one column.
///
/// ## Why this exists as a widget rather than three Stack children
///
/// It used to be three: `Align(topCenter)` for [CoachReadinessBand], and two
/// `Positioned(top: 12)` readouts. The band supplied its own `Padding(all: 12)`,
/// so its card began at (12, 12) — the exact origin of
/// `Positioned(left: 12, top: 12)`. Before a set starts, both are on screen at
/// once, and they drew one on top of the other: "Встаньте в кадр так, чтобы вас
/// было видно целиком" across the rep counter.
///
/// A Stack does not complain about that. Overlapping children are its entire
/// purpose — there is no overflow, no exception, no failing assertion. The host
/// suite cannot see it, and neither could the device suite: both read the widget
/// tree, and the tree was correct. It took a screenshot from a real phone.
///
/// The fix is not a larger offset. Two siblings positioned independently from
/// the same edge will collide again the moment either one's height changes.
/// Laid out in a column, they cannot overlap at all — the guarantee comes from
/// the layout, not from a number someone tuned once.
///
/// Public so the arrangement can be pumped without a camera. [ScanTopBar] is
/// public for the same reason and after the same class of bug.
/// The movement's own name.
///
/// Lifted out of the exercise picker in G3, where the live HUD's movement strip
/// became a second caller: two switches over the same enum drift, and the one
/// that drifts is the one nobody is looking at. It lives here rather than
/// beside the other l10n mappings in `data/cue_text.dart` because
/// [FormExercise] is declared in the state layer, and a data-layer file
/// reaching up into state to name it would invert the dependency for the sake
/// of one switch.
String formExerciseName(AppLocalizations l10n, FormExercise e) => switch (e) {
      FormExercise.squat => l10n.formcheckExerciseSquat,
      FormExercise.pushup => l10n.formcheckExercisePushup,
      FormExercise.deadlift => l10n.formcheckExerciseDeadlift,
      FormExercise.curl => l10n.formcheckExerciseCurl,
      FormExercise.hinge => l10n.formcheckExerciseHinge,
      FormExercise.lunge => l10n.formcheckExerciseLunge,
      FormExercise.situp => l10n.formcheckExerciseSitup,
      FormExercise.overheadPress => l10n.formcheckExerciseOverheadPress,
    };

class CoachTopStrip extends ConsumerWidget {
  const CoachTopStrip({
    super.key,
    required this.session,
    required this.showRepCount,
  });

  final RepSessionState session;
  final bool showRepCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Whether the band below is about to report something blocking. The rep
    // badge's second line yields to it: "reps — ready" under the counter,
    // directly above "Step into frame so your whole body is visible", is the
    // same two-voices defect this gate exists to remove, one surface further
    // out than the first pass looked.
    final instructing = ref.watch(coachIsInstructingProvider);
    final l10n = AppLocalizations.of(context);
    final exercise = ref.watch(selectedExerciseProvider);
    final phase = ref.watch(coachSessionProvider).phase;
    final match = ref.watch(poseMatchProvider);

    // G3. The two badges that used to float in opposite corners are now the
    // reference's two ring gauges, under a strip naming the movement. What is
    // shown in them is unchanged — a rep count the counter is entitled to keep,
    // and the live silhouette match — because this gate is the LAYOUT; G4 is
    // what puts real values behind the four counters below the picture.
    final last = session.reps.isEmpty ? null : session.reps.last;
    // The cause tag under the technique number. Off the last COMPLETED rep, not
    // off the live frame: a caption recomputed thirty times a second is not
    // readable, and the reference's tag is a verdict on a repetition.
    String? cause;
    if (last != null && last.maxSeverity > 0) {
      var worstRule = '';
      var worst = 0;
      last.severityByRule.forEach((rule, severity) {
        if (severity > worst) {
          worst = severity;
          worstRule = rule;
        }
      });
      if (worstRule.isNotEmpty) cause = formRuleName(l10n, worstRule);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CoachExerciseStrip(
          key: const Key('form_check.hud.strip'),
          movement: formExerciseName(l10n, exercise),
          live: phase == CoachPhase.active,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: CoachRingGauge(
                key: const Key('form_check.hud.reps'),
                // Two keys, not one, and deliberately: everything downstream
                // of this gauge — tests, and a reader glancing at it — has to
                // be able to tell a COUNT from the absence of one. A single
                // key on a field that reads "3" in one branch and an em-dash
                // in the other says "there is a number here" in both.
                valueKey: showRepCount
                    ? const Key('form_check.rep_count')
                    : const Key('form_check.rep_count_not_tracked'),
                captionKey: const Key('form_check.phase'),
                label: l10n.formcheckHudReps,
                // A movement the counter cannot follow gets an em-dash and the
                // reason, not a zero. A zero on a gauge is a measurement.
                value: showRepCount
                    ? '${session.repCount}'
                    : l10n.formcheckHudNotMeasured,
                caption: showRepCount
                    ? (session.isArmed && !instructing
                        ? repPhaseText(l10n, session.phase)
                        : null)
                    : l10n.formcheckRepCountNotTracked,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CoachRingGauge(
                key: const Key('form_check.hud.technique'),
                // Same rule as the counter above: `form_check.match` means a
                // percentage is on screen. An unmeasured gauge is a different
                // key, so "no percentage is being shown" stays a checkable
                // claim rather than becoming a string comparison.
                valueKey: match == null
                    ? const Key('form_check.match_not_measured')
                    : const Key('form_check.match'),
                label: l10n.formcheckHudTechnique,
                value: match == null
                    ? l10n.formcheckHudNotMeasured
                    : '${(match * 100).round()}',
                suffix: match == null ? null : '%',
                caption: cause,
                tone: match == null
                    ? CoachTone.neutral
                    : match >= kPoseMatchPassing
                        ? CoachTone.good
                        : CoachTone.warn,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Below the readouts, not beside them: it is an instruction, and the
        // numbers above it are what the instruction is about. Removes itself
        // once the set is running and there is nothing left to instruct — an
        // instruction band mid-rep competes with the cue card.
        //
        // Both flags are computed here rather than inside the band, because
        // this is the widget that already holds the rep session and sits under
        // the provider scope. The band stays renderable on its own.
        IgnorePointer(
          child: CoachReadinessBand(
            avatarCannotPlaceBody: ref.watch(avatarCannotPlaceBodyProvider),
            // Only when a count is actually being kept. On a movement
            // `showRepCountFor` refuses, "stand tall to start counting" is an
            // instruction to reach a number that was never going to appear.
            waitingForTop: showRepCount && !session.isArmed,
            repVerdictShowing: coachStatusHasRepVerdict(session),
          ),
        ),
      ],
    );
  }
}

/// Post-set tally: how many reps were clean, how many the rules complained
/// about, and which rules did the complaining.
class _SetSummaryCard extends StatelessWidget {
  const _SetSummaryCard({required this.session, required this.onReset});

  final RepSessionState session;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (session.reps.isEmpty) {
      return HudPanel(
        child: Text(
          // Which way to face, said out loud. The targets are authored as side
          // views and the outline is drawn from the side, but nothing on the
          // screen said so — the operator filmed himself head-on and the coach
          // repeatedly told him he had not reached a shape that, from that
          // angle, he could not reach. The instruction costs one line.
          '${AppLocalizations.of(context).formcheckStandSideOn}\n'
          '${AppLocalizations.of(context).formcheckNoRepsYetStandTallTo}',
          key: const Key('form_check.summary_empty'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colors.textSecondary,
          ),
        ),
      );
    }

    // Rule ids are internal. They reached the operator's screen verbatim as
    // "Ошибки: squat.depth, deadlift.back_angle, pushup.alignment" — English
    // identifiers on a Russian page. Translate at the boundary.
    final offenders = <String>{
      for (final rep in session.reps)
        for (final rule in rep.offendingRules)
          formRuleName(AppLocalizations.of(context), rule),
    };

    return HudPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  AppLocalizations.of(context).formcheckThisSet,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              AppTertiaryButton(
                onPressed: onReset,
                label: AppLocalizations.of(context).formcheckResetSet,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            AppLocalizations.of(context).formcheckCleanNeedWorkTotal(
                session.cleanReps, session.sloppyReps, session.reps.length),
            key: const Key('form_check.summary_tally'),
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (offenders.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              AppLocalizations.of(context)
                  .formcheckFlagged(offenders.join(', ')),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The reference's «✓ Лопатки» chip: what the coach checked on the last
/// repetition and had nothing to say about.
///
/// Only the rules that PASSED. The one that did not is already the cue chip
/// below and the cause tag under the technique gauge, and this screen has spent
/// three gates removing surfaces that repeat each other. A tick is the half of
/// the verdict nothing else on screen carries — without it, a rule the coach
/// watched and approved is indistinguishable from a rule it never ran.
///
/// Severity 0 means "watched and clean", not "no data": every shipped rule
/// emits a severity-0 observation on the frames it runs, which is what
/// [RepQuality.severityByRule] records. See [coachToneForSeverity].
class _PassedRuleChips extends StatelessWidget {
  const _PassedRuleChips({required this.session});

  final RepSessionState session;

  /// At most two. The picture behind them is the thing the user is actually
  /// looking at, and a full list of every rule in the movement would cover it.
  static const _limit = 2;

  @override
  Widget build(BuildContext context) {
    final last = session.reps.isEmpty ? null : session.reps.last;
    if (last == null) return const SizedBox.shrink();
    final passed = [
      for (final e in last.severityByRule.entries)
        if (e.value <= 0) e.key,
    ]..sort();
    if (passed.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        key: const Key('form_check.hud.passed_rules'),
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final rule in passed.take(_limit))
            CoachCueChip(
              key: Key('form_check.hud.passed_rule.$rule'),
              text: formRuleName(l10n, rule),
              tone: CoachTone.good,
            ),
        ],
      ),
    );
  }
}

class _CueCard extends StatelessWidget {
  const _CueCard({
    required this.verdict,
    this.feedback,
    this.reject,
  });

  /// Why the most recent attempt was thrown away, or null when the last thing
  /// that happened was a counted repetition.
  ///
  /// This outranks the previous rep's verdict: a green "clean rep" banner
  /// sitting over a count that just refused to move is the screen actively
  /// misleading the user about what it saw.
  final RepRejectReason? reject;

  /// What the coach is entitled to say about the last completed repetition.
  ///
  /// This card is a **verdict on a repetition**, not a readout of the current
  /// frame. Green when the rep was clean, red when it was not, and it changes
  /// once per rep. It used to re-render whatever the latest frame produced —
  /// several times a second, cycling between messages for the whole movement.
  ///
  /// A [RepVerdict] rather than a `bool?` because a boolean could not carry the
  /// case that was actually shipping: a repetition finished with nothing in a
  /// position to judge it, and the card painted that green.
  final RepVerdict verdict;

  final FormFeedback? feedback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    // An attempt that was started and discarded. It produced no count, and
    // silence here is what makes that look like the detector losing the body.
    if (reject != null) {
      return _band(
        theme,
        AppPalette.auroraPeach.withValues(alpha: 0.92),
        switch (reject!) {
          RepRejectReason.incomplete => l10n.formcheckRepNotCounted,
          RepRejectReason.tooFast => l10n.formcheckRepNotCountedTooFast,
        },
        const Key('form_check.rep_rejected'),
      );
    }

    // Nothing has finished yet, so this card has nothing to be a verdict on and
    // renders nothing at all.
    //
    // It used to say "Ready - do a rep." here. That is not a verdict on a
    // repetition, it is a statement that the coach is ready — which the status
    // band above says, in its own words, from a different signal, at the same
    // time. Two "ready" sentences at opposite ends of the preview, and on the
    // frame the operator screenshotted, a third message between them saying the
    // body could not be found at all.
    if (verdict == RepVerdict.none) return const SizedBox.shrink();

    // A repetition nothing was allowed to judge. Said plainly, in its own
    // colour, because the alternative shipped and was worse than silence: the
    // card painted it the same green as a rep the coach had actually watched
    // and approved, so a set performed badly came back faultless and the user
    // had no way to know the coach was not looking.
    if (verdict == RepVerdict.notEvaluated) {
      return _band(
        theme,
        AppPalette.auroraViolet.withValues(alpha: 0.92),
        l10n.formcheckRepNotEvaluated,
        const Key('form_check.rep_not_evaluated'),
      );
    }

    // Two colours, one per repetition. Red carries the one cue; green says the
    // rep was clean and says it in three words, because a green banner that
    // explains itself at length is just noise wearing a friendly colour.
    if (verdict == RepVerdict.clean) {
      return _band(theme, AppPalette.auroraTeal.withValues(alpha: 0.92),
          l10n.formcheckRepClean, const Key('form_check.rep_clean'));
    }
    return _band(
      theme,
      AppPalette.auroraPink.withValues(alpha: 0.92),
      feedback == null
          ? l10n.formcheckRepFaulted
          : formCueText(l10n, feedback!.cueKey),
      const Key('form_check.cue'),
    );
  }

  /// The card itself carries a key as well as the message inside it.
  ///
  /// So that "at most one surface is speaking" can be asserted structurally,
  /// on the two surfaces, rather than by enumerating every message key either
  /// of them might contain. An enumeration goes stale the moment a message is
  /// added — which is exactly how a screen grows a second voice back.
  ///
  /// G3 changed its SHAPE and nothing else. It was a full-width solid slab of
  /// verdict colour across the bottom of the picture; the reference puts a
  /// chip there — dark, bordered in the verdict's colour, only as wide as its
  /// own sentence — so the body behind it stays visible while it speaks. The
  /// keys, the messages and the one-voice rule are untouched: this is the
  /// layout gate, not a rewrite of what the coach is allowed to say.
  Widget _band(ThemeData theme, Color colour, String text, Key key) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          key: const Key('form_check.cue_card'),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colour.withValues(alpha: 0.7), width: 1.4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  text,
                  key: key,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

/// Choose the movement, and with it the rules that will judge it.
///
/// Before this existed every rule ran on every frame, so a squatting user was
/// also graded by the push-up rule — which is how a set of eight squats came
/// back reporting "Ошибки: Глубина приседа, Линия корпуса". Half of that was a
/// rule for a different exercise entirely, and no amount of tuning it would
/// have helped.
class _ExercisePicker extends ConsumerWidget {
  const _ExercisePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(selectedExerciseProvider);
    String label(FormExercise e) => formExerciseName(l10n, e);
    // Every other surface asks `formCoachSupports` before offering a movement
    // — the Train tab's chip, the exercise page, the player. This picker did
    // not, so the screen the feature is named after was the one place its own
    // support gate never ran: `pushup` drew a silhouette over a counter that
    // cannot move, and `deadlift` had no shape to stand in at all.
    //
    // Disabled rather than hidden. A movement missing from the list reads as
    // "this app does not know about push-ups"; a movement greyed out with a
    // reason reads as what is true, and is the only version that tells the
    // user why the list is short.
    final unsupported =
        FormExercise.values.where((e) => !formCoachTeaches(e)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in FormExercise.values)
              if (formCoachTeaches(e))
                HudChip(
                  key: Key('form_check.exercise.${e.name}'),
                  label: label(e),
                  selected: e == selected,
                  onTap: () =>
                      ref.read(selectedExerciseProvider.notifier).state = e,
                )
              else
                Opacity(
                  // Same "disabled rather than hidden" intent as before
                  // (comment above `unsupported`) -- `HudChip`'s `enabled`
                  // covers the semantic (screen-reader) side of disabled,
                  // not the visual one, so the dimming still has to be
                  // added here.
                  opacity: 0.5,
                  child: HudChip(
                    key: Key('form_check.exercise.${e.name}'),
                    label: '${label(e)} · ${l10n.formcheckExerciseNotTaught}',
                    selected: false,
                    onTap: null,
                    enabled: false,
                  ),
                ),
          ],
        ),
        if (unsupported.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            l10n.formcheckNotTaughtHint,
            key: const Key('form_check.not-taught-hint'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

/// The shape to stand in, painted over the camera.
///
/// This is the part that makes the match score legitimate. The score is
/// invariant to where the user stands and how big they appear, but NOT to the
/// angle they are filmed from — a squat from the front and the same squat from
/// the side are different shapes on a flat image. Drawing the target is what
/// turns that from a hidden assumption into an instruction the user can follow.
/// A target the user could not see would repeat the exact mistake that made two
/// earlier rules wrong: judging against a reference nobody agreed to.
/// The outline over the camera: a looping demonstration of the movement before
/// the set, and the shape to arrive at once it has started.
///
/// The two are drawn differently on purpose. A demonstration is a suggestion —
/// thin, dimmer, and moving. A target is an instruction — solid, and still, so
/// that "get 80% of the way into this" is a question with an answer. Drawing
/// both the same way would invite the user to chase the animation, which is
/// exactly the shape they cannot match, because it is never in one place.
class _Silhouette extends ConsumerWidget {
  const _Silhouette(
      {super.key, required this.demo, required this.demonstrating});

  final Animation<double> demo;
  final bool demonstrating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Drawn together with the avatar now, deliberately (operator instruction,
    // 2026-08-31 — see `demonstrating`'s comment above): the silhouette is
    // the shape to match, the avatar is the user's own tracked body, and the
    // design reference shows both at once.
    //
    // This used to be "avoided by construction, not by coordinate
    // unification" — a claim that turned out to be wrong. A real device video
    // (operator, same day, second video) showed the two figures at wildly
    // different scales the instant a real body was tracked: the avatar,
    // projected through `projectLandmark` at the camera's real scale, next to
    // a silhouette fitted independently to fill the panel margin
    // (`fitSilhouette`) — unrelated coordinate systems that only coincide by
    // accident. `pose_target.dart`'s own doc comment already said the fix:
    // targets are "authored at plausible screen positions so the same numbers
    // can be drawn as the on-screen outline without a second source of
    // truth" — i.e. target joints live in the SAME isotropic, per-image-height
    // space real landmarks do, and were always meant to be projected the same
    // way. `_SilhouettePainter` now does that instead of calling
    // `fitSilhouette`, which unifies the two coordinate systems for real
    // rather than hoping they never appear together at a clashing scale.
    final target = ref.watch(poseTargetProvider);
    final pair = ref.watch(poseDemoProvider);
    final build = ref.watch(silhouetteBuildProvider);
    // The empty-frame case still carries a real aspect ratio (`_emptyFrame`
    // in `mlkit_pose_detector_service.dart`) from the moment the camera
    // starts, so this is null only in the brief window before the first
    // camera frame has been processed at all. `9 / 16` matches the panel's
    // own fallback aspect ratio elsewhere on this page.
    final frameAspect = ref.watch(latestPoseFrameProvider)?.aspectRatio ?? 9 / 16;

    if (demonstrating && pair != null) {
      final (from, to) = pair;
      return AnimatedBuilder(
        animation: demo,
        builder: (_, __) => CustomPaint(
          key: const Key('form_check.demo'),
          painter: _SilhouettePainter(
            // Eased rather than linear: a real repetition does not travel at a
            // constant speed, and a constant-speed stick figure reads as a
            // machine rather than as a movement to copy.
            target: lerpPoseTarget(
                from, to, Curves.easeInOutCubic.transform(demo.value)),
            match: null,
            build: build,
            isDemo: true,
            frameAspect: frameAspect,
          ),
        ),
      );
    }

    if (target == null) return const SizedBox.shrink();
    return CustomPaint(
      key: const Key('form_check.silhouette'),
      painter: _SilhouettePainter(
        target: target,
        match: ref.watch(poseMatchProvider),
        build: build,
        frameAspect: frameAspect,
      ),
    );
  }
}

/// Offers to fill in the intake answers the outline would use.
///
/// Renders nothing when there is nothing missing, which includes the user who
/// answered "prefer not to say" — that is an answer, and asking again would
/// make it look like it had not been heard.
class _CompleteProfileCard extends ConsumerWidget {
  const _CompleteProfileCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missing = ref.watch(missingBodyAnswersProvider);
    if (missing.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final names = [
      if (missing.contains(BodyAnswer.gender)) l10n.formcheckBodyGender,
      if (missing.contains(BodyAnswer.height)) l10n.formcheckBodyHeight,
      if (missing.contains(BodyAnswer.weight)) l10n.formcheckBodyWeight,
    ].join(', ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: HudPanel(
        key: const Key('form_check.complete_profile'),
        onTap: () => GoRouter.of(context).push('/profile'),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                gradient: const LinearGradient(colors: [
                  AppPalette.auroraViolet,
                  AppPalette.auroraBlue,
                ]),
              ),
              child: const Icon(Icons.straighten_rounded,
                  color: AppSemanticColors.onGradientInk),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.formcheckTuneTheOutline,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.formcheckMissingAnswers(names),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: theme.colors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _SilhouettePainter extends CustomPainter {
  const _SilhouettePainter({
    required this.target,
    required this.match,
    required this.build,
    required this.frameAspect,
    this.isDemo = false,
  });

  final PoseTarget target;

  /// Live match, 0..1, or null when the body cannot be read.
  final double? match;

  /// How broad to draw it, from the intake.
  final BodyBuild build;

  /// Drawing the movement rather than the position to reach.
  final bool isDemo;

  /// The live camera frame's aspect ratio — the same value
  /// `_SkeletonPainter` and `_PoseAvatarPainter` project against, so a target
  /// authored in the joints' own isotropic space lands at the same scale a
  /// real body would. See `_Silhouette.build`'s comment for why this replaced
  /// `fitSilhouette`.
  final double frameAspect;

  @override
  void paint(Canvas canvas, Size size) {
    // A two-sided body, and ONE scale for both axes. Drawing straight from
    // `target.joints` gave half a skeleton, and multiplying x by the panel
    // width while multiplying y by its height squeezed that half horizontally
    // by 1.78x on a 9:16 panel — together, the "закорючка" the operator saw
    // twice. Both faults live in `pose_silhouette.dart` now, with tests.
    //
    // No aspect correction here any more. Until
    // `FORMCOACH_TARGET_ISOTROPIC_2026-09-01` this passed `xScale: frameAspect`
    // because target x was authored as a fraction of frame WIDTH while
    // `projectLandmark` expects this app's isotropic space. The targets
    // themselves now hold isotropic x, so the correction has nothing left to
    // correct -- and applying it twice would shove the outline off-panel again,
    // which is the bug that correction was introduced to fix.
    final figure = buildSilhouette(target, build: build);
    if (figure.segments.isEmpty) return;
    // The same projection `_SkeletonPainter`/`_PoseAvatarPainter` use, not
    // `fitSilhouette` — see `_Silhouette.build`'s comment. This also means the
    // demo loop no longer needs a `fixedBounds` union-of-endpoints hack to
    // hold a stable scale: `projectLandmark`'s transform depends only on
    // `frameAspect` and `size`, never on the pose's own bounds, so it cannot
    // rescale from one animation frame to the next in the first place.
    Offset place(Offset p) =>
        projectLandmark(p.dx, p.dy, frameAspect: frameAspect, canvas: size);
    final scale = (place(const Offset(0, 1)) - place(Offset.zero)).distance;

    // Green once the shape is reached, so the user gets the answer while they
    // are still in the position and can feel what it corresponds to.
    final reached = (match ?? 0) >= kPoseMatchPassing;
    final colour = reached ? AppPalette.auroraTeal : Colors.white;
    final alpha = isDemo
        ? 0.45
        : reached
            ? 0.95
            : 0.65;

    final limbWidth = (figure.limbThickness * scale).clamp(4.0, 30.0);

    // B4 — ONE body, not a set of parts.
    //
    // This used to stroke each bone as a thick round-capped line and outline
    // the head separately. However wide the strokes, that is a stick figure —
    // the operator rejected it three times and was right: limbs of constant
    // width joined by visible caps do not read as a person. Every part now
    // arrives as a closed outline (`SilhouetteFigure.limbs`, plus the trunk
    // and the head) and they are unioned into a single non-zero path, so what
    // is filled is one continuous silhouette with no seams where an arm meets
    // a shoulder.
    // UNION, not a path with many subpaths.
    //
    // The first version added each part as its own subpath under
    // `PathFillType.nonZero`. That merges what is FILLED and does nothing to
    // what is STROKED: `drawPath` outlines every subpath separately, so the
    // seams where an arm enters a shoulder and a thigh enters the hip were all
    // drawn. On a real camera at 0.28 fill the faint interior vanished and only
    // that lattice remained — the figure read as a heap of overlapping
    // quadrilaterals, which is worse than the sticks it replaced. Found by
    // opening it on a phone; the emulator has no camera to show it, and every
    // geometric test passed the whole time because the geometry was right.
    //
    // `Path.combine` resolves the overlaps into ONE outline, so the rim traces
    // the body and nothing else.
    var body = Path();
    void merge(Path part) {
      body = Path.combine(PathOperation.union, body, part);
    }

    if (figure.torso.isNotEmpty) {
      merge(Path()..addPolygon([for (final p in figure.torso) place(p)], true));
    }
    for (final limb in figure.limbs) {
      if (limb.length < 3) continue;
      merge(Path()..addPolygon([for (final p in limb) place(p)], true));
    }
    final head = figure.head;
    if (head != null) {
      merge(Path()
        ..addOval(
          Rect.fromCircle(center: place(head.$1), radius: head.$2 * scale),
        ));
    }

    // Translucent fill, opaque rim. The rim is what the user actually lines
    // themselves up against; the fill only has to say which side is body. A
    // solid fill over a live camera would hide the person trying to match it —
    // the same reason the head used to be drawn as an outline rather than a
    // disc, kept now that the head is part of the filled body.
    // 0.34, up from 0.28: measured on a phone against a white wall, where the
    // interior was effectively invisible and the outline had to carry the whole
    // shape on its own. Still translucent — a solid fill over a live camera
    // would hide the person trying to match it, which is the reason the head
    // used to be an empty circle.
    //
    // The demonstration is the exception, and on the device it was the whole
    // problem. It is painted on an OPAQUE dark panel with nobody behind it, so
    // there is nothing for translucency to protect — and 0.45 x 0.34 is a 15%
    // white body, which disappears into the panel and leaves the rim carrying
    // the entire figure on its own. That is exactly the thin geometric outline
    // the operator rejected («квадраты»), reintroduced by an alpha rather than
    // by the geometry: G5 fixed the shape, and the shape was then invisible.
    // The reference clip is a FILLED body with the skeleton glowing on top of
    // it, so the demonstration gets a filled body.
    final fillAlpha = isDemo ? 0.58 : alpha * 0.34;
    final rimAlpha = isDemo ? 0.85 : alpha;
    canvas.drawPath(body, Paint()..color = colour.withValues(alpha: fillAlpha));
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (limbWidth * 0.22).clamp(2.0, 5.0)
        ..strokeJoin = StrokeJoin.round
        ..color = colour.withValues(alpha: rimAlpha),
    );

    if (isDemo) _paintDemoSkeleton(canvas, place, limbWidth);
  }

  /// The glowing skeleton the reference clip carries INSIDE the silhouette.
  ///
  /// Operator, point 2: «человекоподобный силуэт с светящимся скелетом
  /// приседает». The silhouette on its own is a shape; the skeleton is what
  /// makes it read as the same figure the live screen will draw over the user,
  /// so the demonstration and the thing it is demonstrating look like one
  /// system rather than two drawings that happen to share a screen.
  ///
  /// Copied from the reference's own SVG rather than invented: white line,
  /// round caps, two drop-shadow glows (5px and 14px there), filled joint dots
  /// — `Fitness Form Coach Phone.dc.html:45-68`. The widths are derived from
  /// [SilhouetteFigure.limbThickness] instead of transcribing that file's pixel
  /// values, because those are pixels in a 390x844 artboard and this paints
  /// into whatever panel it is given.
  ///
  /// Demo only. Over a live camera the skeleton drawn from the USER's own
  /// landmarks is the one that means something (`_SkeletonOverlay`), and a
  /// second one tracing the target would put two skeletons on one body.
  void _paintDemoSkeleton(
      Canvas canvas, Offset Function(Offset) place, double limbWidth) {
    Offset? at(LandmarkType j) {
      final c = target.joints[j];
      return c == null ? null : place(Offset(c.$1, c.$2));
    }

    final line = Path();
    var drew = false;
    for (final (a, b) in target.bones) {
      final pa = at(a);
      final pb = at(b);
      if (pa == null || pb == null) continue;
      line
        ..moveTo(pa.dx, pa.dy)
        ..lineTo(pb.dx, pb.dy);
      drew = true;
    }
    if (!drew) return;

    // 0.15, down from 0.28 (2026-09-01). Once the body was actually filled and
    // drawn at a real chest's depth, the bones at the old weight were the
    // brightest thing on the panel and the figure read as a glowing wireframe
    // with a grey shadow behind it — the reference has it the other way round:
    // a body, with the skeleton glowing INSIDE it.
    final width = (limbWidth * 0.15).clamp(2.0, 4.5);
    // Two passes, widening and fading, standing in for the reference's two
    // stacked drop-shadows. `MaskFilter.blur` rather than a wider opaque
    // stroke: a hard-edged halo reads as a second, thicker skeleton.
    for (final (mul, a, blur) in [
      (3.2, 0.14, 7.0),
      (1.9, 0.24, 3.0),
    ]) {
      canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width * mul
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur)
          ..color = Colors.white.withValues(alpha: a),
      );
    }
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width
        ..color = Colors.white.withValues(alpha: 0.92),
    );
    // The dots sit on the joints the bones connect, not on every authored
    // landmark: an endpoint nothing links to is a coordinate, not a joint.
    final dots = Paint()..color = Colors.white.withValues(alpha: 0.92);
    for (final j in {
      for (final (a, b) in target.bones) ...[a, b],
    }) {
      final p = at(j);
      if (p != null) canvas.drawCircle(p, width * 0.7, dots);
    }
  }

  @override
  bool shouldRepaint(_SilhouettePainter old) =>
      old.target.id != target.id ||
      old.isDemo != isDemo ||
      old.build != build ||
      old.frameAspect != frameAspect ||
      // A demonstration is a new pose every frame and its id never changes, so
      // it has to be compared by content or the animation would render as a
      // single frozen frame.
      (isDemo && !mapEquals(old.target.joints, target.joints)) ||
      // Otherwise only when the score crosses the line: repainting on every
      // decimal of a live score would rebuild this overlay on every camera
      // frame for no visible difference.
      ((old.match ?? 0) >= kPoseMatchPassing) !=
          ((match ?? 0) >= kPoseMatchPassing);
}
