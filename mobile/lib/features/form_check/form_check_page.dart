import 'dart:async' show TimeoutException;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/experimental_banner.dart';
import '../../shared/widgets/glass.dart';
import 'data/cue_text.dart';
import 'data/form_classifier.dart';
import 'data/mlkit_pose_detector_service.dart';
import 'data/pose_detector_service.dart';
import 'data/pose_landmark.dart';
import 'data/pose_projection.dart';
import 'data/pose_silhouette.dart';
import 'data/pose_target.dart';
import 'data/rep_counter.dart';
import '../subscription/data/subscription_models.dart';
import '../subscription/state/subscription_providers.dart';
import 'data/coach_phases.dart';
import 'state/coach_phase_providers.dart';
import 'state/form_check_providers.dart';
import 'widgets/camera_flip_button.dart';
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
  void _syncDemo(bool wanted) {
    if (wanted == _demo.isAnimating) return;
    if (wanted) {
      _demo.repeat(reverse: true);
    } else {
      _demo.stop();
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
      duration: const Duration(milliseconds: 1000),
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
    });
    // R11h: arriving on this page is NOT asking for the camera any more. The
    // intro and preparation cards come first, and `_openCamera` below is the
    // single place the hardware is requested — by a tap that says so.
  }

  /// True once the user has asked for the camera on this visit.
  ///
  /// Guards the lifecycle-resume path: coming back from the background while
  /// still on the intro card must not open a camera the user has not asked
  /// for, and `_started` alone cannot tell "not started yet" from "stopped
  /// when we backgrounded".
  bool _cameraRequested = false;

  /// The preparation card's only button.
  ///
  /// Moves the phase and nothing else. Opening the camera is [build]'s job, on
  /// the rule "past preparation means the camera belongs open" — so the phase
  /// is the single source of truth, and anything else that legitimately puts
  /// the session into a camera phase (a test starting at the screen it is
  /// actually about; a future deep link into a set) gets a camera without
  /// having to know this method exists.
  void _openCamera() =>
      ref.read(coachPhaseControllerProvider.notifier).openCamera();

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
        // Not while the user is still on the intro or preparation card.
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // R11h. Two cards before anything opens. Deliberately ABOVE every provider
    // watch below, `formFeedbackControllerProvider` in particular: watching it
    // is what subscribes to the frame stream, so returning early here is also
    // what guarantees nothing is listening for frames while the user is still
    // reading.
    final phase = ref.watch(coachSessionProvider).phase;
    if (phase == CoachPhase.launch) return const CoachLaunchCard();
    if (phase == CoachPhase.preparation) {
      return CoachPreparationCard(onOpenCamera: _openCamera);
    }

    // Past preparation, so the camera belongs open. Once per visit: the flag
    // is what stops a rebuild from starting a second one, and it is also what
    // the lifecycle-resume path reads to tell "stopped" from "never asked
    // for". Deferred to a post-frame callback because starting a camera is a
    // side effect and build must not have one mid-frame.
    if (!_cameraRequested) {
      _cameraRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startDetector(requestPermission: true);
      });
    }

    final tier = ref.watch(effectiveTierProvider);
    final isPremium = tier == SubscriptionTier.celebrityTrainer;
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
    final instructing = ref.watch(avatarCannotPlaceBodyProvider) ||
        ref.watch(coachSessionProvider).blocker != CoachBlocker.none;
    // Either the camera never opened, or the native detector died mid-stream.
    // Both mean "no reps will be counted", so both belong in the same slot.
    final failure = _startError ?? ref.watch(poseErrorProvider);

    // Demonstrate until the movement starts, and get out of the way the
    // instant it does: an outline that keeps moving is not one you can hit.
    // Never over a spinner or an error — there is nothing to copy it onto.
    final demonstrating = failure == null &&
        _started &&
        session.repCount == 0 &&
        session.phase == RepPhase.top;
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

    return FrostedScaffold(
      appBar: GlassAppBar(
        title: AppLocalizations.of(context).formcheckFormCoach,
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
      // instantly instead of walking back through preparation and the gate.
      body: phase == CoachPhase.summary
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
                    ref.read(repSessionControllerProvider.notifier).resetSet();
                    ref.read(coachPhaseControllerProvider.notifier).start();
                  },
                ),
              ],
            )
          : ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          // A1. Above the upgrade card on purpose: what the coach can and
          // cannot tell you is not a detail below the offer to pay for it.
          ExperimentalBanner(
              message: AppLocalizations.of(context).experimentalFormCoach),
          if (!isPremium && ref.watch(entitlementResolvedProvider)) ...[
            _UpgradeCard(),
            const SizedBox(height: 16),
          ],
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
          // Above the preview, not overlaid on it. The bottom of the preview is
          // already the cue card's, and a control that shares space with the
          // one sentence telling you what you did wrong is a control that will
          // be pressed by accident mid-rep.
          _SetControls(phase: phase),
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
                          onRetry: () => _startDetector(requestPermission: true),
                        ),
                      )
                    else if (!_started)
                      const Center(
                        child: CircularProgressIndicator(color: Colors.white),
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
                      Positioned(
                        left: 12,
                        right: 12,
                        top: 12,
                        child: CoachTopStrip(
                          session: session,
                          showRepCount: showRepCount,
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
                          child: _CueCard(
                            feedback: session.lastRepCue,
                            clean: session.lastRepClean,
                            reject: session.lastReject,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // A coach that has gone silent because the device has no voice
          // installed is indistinguishable from a coach with nothing to say.
          // `lastErrorMessage` existed for exactly this and nothing read it —
          // the same wiring `health_sync_card.dart` already uses for health.
          if (ref.watch(voiceErrorProvider) != null) ...[
            GlassCard(
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
          // recorded in the R0 audit §7.5. What it measured is still an open
          // defect (those extents are outside the contract
          // `pose_coordinate_space.dart` declares), so the instrument stays;
          // only its exposure to users goes.
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
              onReset: () =>
                  ref.read(repSessionControllerProvider.notifier).resetSet(),
            ),
            const SizedBox(height: 16),
          ],
          GlassCard(
            child: Text(
              AppLocalizations.of(context).formcheckFormCoachRunsOnDeviceUsing,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colors.textSecondary,
              ),
            ),
          ),
        ],
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
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Expanded(
                child: AppSecondaryButton(
                  key: Key(paused
                      ? 'form_check.resume_set'
                      : 'form_check.pause_set'),
                  label: paused ? l10n.formcheckResumeSet : l10n.formcheckPauseSet,
                  icon: paused ? Icons.play_arrow : Icons.pause,
                  onPressed: paused ? coach.resume : coach.pause,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppPrimaryButton(
                  key: const Key('form_check.finish_set'),
                  label: l10n.formcheckFinishSet,
                  icon: Icons.check,
                  onPressed: coach.finish,
                ),
              ),
            ],
          ),
        );
      // Nothing to control: the camera is not open, or the view is not usable
      // yet and the readiness band is already saying why.
      case CoachPhase.launch:
      case CoachPhase.preparation:
      case CoachPhase.qualityCheck:
      case CoachPhase.calibration:
      case CoachPhase.summary:
        return const SizedBox.shrink();
    }
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

/// The scene the avatar stands in, in place of the room.
///
/// Painted rather than a bundled photograph, and that is a decision rather than
/// a shortcut. A photograph costs three things this does not: a licence and a
/// credit on the licences screen (the anatomy chart already carries both), a
/// few hundred kilobytes in an APK where 8.1 MB of demo photographs were
/// deleted in August for being dead weight, and a choice of image that belongs
/// to whoever is designing the app, not to whoever is wiring the mode up.
///
/// It is also the seam: swapping this widget for an `Image.asset` is one file
/// and one licence line, and nothing else on this page has to know.
class _AvatarBackdrop extends StatelessWidget {
  const _AvatarBackdrop();

  @override
  Widget build(BuildContext context) => const RepaintBoundary(
        child: CustomPaint(
          key: Key('form_check.backdrop'),
          painter: _AvatarBackdropPainter(),
          size: Size.infinite,
        ),
      );
}

class _AvatarBackdropPainter extends CustomPainter {
  const _AvatarBackdropPainter();

  // Dusk, because the figure is drawn as a dark body with a light skeleton and
  // needs a ground that is neither. Over a bright scene the body disappears;
  // over the app's own near-black the whole point of leaving the camera behind
  // is lost.
  static const _sky = Color(0xFF241A3A);
  static const _horizonGlow = Color(0xFFE8925A);
  static const _ground = Color(0xFF0B0A14);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final horizon = size.height * 0.62;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF120E22), _sky, Color(0xFF6B3F52)],
          stops: [0.0, 0.38, 1.0],
        ).createShader(rect),
    );

    // A low sun behind where the body stands. Off-centre: dead centre would sit
    // exactly behind the torso and be hidden by it for the whole set.
    canvas.drawCircle(
      Offset(size.width * 0.68, horizon),
      size.height * 0.34,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _horizonGlow.withValues(alpha: 0.55),
            _horizonGlow.withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromCircle(
            center: Offset(size.width * 0.68, horizon),
            radius: size.height * 0.34,
          ),
        ),
    );

    canvas.drawRect(
      Rect.fromLTRB(0, horizon, size.width, size.height),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_ground.withValues(alpha: 0.86), _ground],
        ).createShader(Rect.fromLTRB(0, horizon, size.width, size.height)),
    );
  }

  // Nothing about it moves.
  @override
  bool shouldRepaint(_AvatarBackdropPainter old) => false;
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

    return RepaintBoundary(
      child: CustomPaint(
        key: const Key('form_check.avatar'),
        painter: _PoseAvatarPainter(figure: figure, frame: frame),
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
  const _PoseAvatarPainter({required this.figure, required this.frame});

  /// Already built, by the widget above, which had to look at it anyway to
  /// decide between drawing a body and explaining why it cannot.
  final SilhouetteFigure figure;

  /// Carried for its aspect ratio, which the projection needs, and its
  /// timestamp, which is what makes one frame different from the last.
  final PoseFrame frame;

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
    final jointCore = Paint()..color = Colors.white;
    for (final j in figure.joints) {
      canvas.drawCircle(place(j), boneWidth * 0.62, jointCore);
    }
  }

  @override
  bool shouldRepaint(_PoseAvatarPainter old) =>
      old.frame.timestampMs != frame.timestampMs;
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
    final instructing = ref.watch(avatarCannotPlaceBodyProvider) ||
        ref.watch(coachSessionProvider).blocker != CoachBlocker.none;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          // `spaceBetween` + `Flexible`, not `Spacer`: a Spacer makes the row's
          // minimum width the sum of its children, so a long enough readout
          // pushes the other pill off a narrow screen instead of shrinking it.
          // That is precisely how `/scan` overflowed 142px at 320dp, in Russian
          // only, invisibly to a suite that renders English.
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: showRepCount
                  ? _RepBadge(session: session, showPhase: !instructing)
                  : const _RepCountNotTrackedBadge(),
            ),
            const SizedBox(width: 8),
            const Flexible(child: _MatchReadout()),
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

/// Sits where [_RepBadge] would, for a movement `showRepCountFor` refuses.
///
/// Silent omission was the first draft and was wrong: the operator's own R8
/// decision (`core/SESSION_STATE_2026-08-08.md`) is that a movement with
/// counting turned off says so on screen, rather than leaving a blank corner
/// that reads as a bug. The silhouette coaching underneath keeps running
/// either way — this replaces only the number, not the feature.
class _RepCountNotTrackedBadge extends StatelessWidget {
  const _RepCountNotTrackedBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          AppLocalizations.of(context).formcheckRepCountNotTracked,
          key: const Key('form_check.rep_count_not_tracked'),
          style: theme.textTheme.labelSmall?.copyWith(
            color: Colors.white70,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Live rep count + phase, over the camera preview. Deliberately the largest
/// text on the screen — mid-set, at arm's length, this is the only thing the
/// user can actually read.
class _RepBadge extends StatelessWidget {
  const _RepBadge({required this.session, this.showPhase = true});
  final RepSessionState session;

  /// Whether to draw the phase line under the number.
  ///
  /// False while the status band is reporting that the coach cannot see the
  /// user. The phase is a readout of the counter rather than an instruction, so
  /// it does not belong in the band's priority ladder — but "ready" sitting
  /// under the count while the band says the body is out of frame is still two
  /// things being said at once, and the count is the half that can wait.
  final bool showPhase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${session.repCount}',
            key: const Key('form_check.rep_count'),
            style: theme.textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
          // Only once the counter has armed. Before that the badge is the
          // number and nothing else: what is being waited for is said once, by
          // the status band, because it is a statement about whether the coach
          // is ready rather than about the set. Saying it here as well put
          // "stand tall to start counting" directly above "Ready. Start when
          // you are." — the screen telling the user both that it was waiting
          // for them and that it was not.
          if (session.isArmed && showPhase) ...[
            const SizedBox(height: 2),
            Text(
              AppLocalizations.of(context).formcheckReps(
                  repPhaseText(AppLocalizations.of(context), session.phase)),
              key: const Key('form_check.phase'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
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
      return GlassCard(
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

    return GlassCard(
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

class _UpgradeCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      onTap: () => GoRouter.of(context).push('/subscription'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context).formcheckFormCoachIsASustainerBenefit,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          // Was a raw English literal quoting a competitor's hardware price.
          // Localized, and the unverifiable price claim dropped — what the
          // feature actually does is the honest version of the same pitch.
          Text(
            AppLocalizations.of(context).formcheckUpgradeSubtitle,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _CueCard extends StatelessWidget {
  const _CueCard({
    this.feedback,
    this.clean,
    this.reject,
  });

  /// Why the most recent attempt was thrown away, or null when the last thing
  /// that happened was a counted repetition.
  ///
  /// This outranks the previous rep's verdict: a green "clean rep" banner
  /// sitting over a count that just refused to move is the screen actively
  /// misleading the user about what it saw.
  final RepRejectReason? reject;

  /// Whether the last completed repetition was faultless. Null before the
  /// first one finishes.
  ///
  /// This card is now a **verdict on a repetition**, not a readout of the
  /// current frame. Green when the rep was clean, red when it was not, and it
  /// changes once per rep. It used to re-render whatever the latest frame
  /// produced — several times a second, cycling between messages for the whole
  /// movement.
  final bool? clean;

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
    if (clean == null) return const SizedBox.shrink();

    // Two colours, one per repetition. Red carries the one cue; green says the
    // rep was clean and says it in three words, because a green banner that
    // explains itself at length is just noise wearing a friendly colour.
    if (clean!) {
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
  Widget _band(ThemeData theme, Color colour, String text, Key key) =>
      Container(
        key: const Key('form_check.cue_card'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colour,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          key: key,
          style: theme.textTheme.titleSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
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
    String label(FormExercise e) => switch (e) {
          FormExercise.squat => l10n.formcheckExerciseSquat,
          FormExercise.pushup => l10n.formcheckExercisePushup,
          FormExercise.deadlift => l10n.formcheckExerciseDeadlift,
          FormExercise.curl => l10n.formcheckExerciseCurl,
          FormExercise.hinge => l10n.formcheckExerciseHinge,
          FormExercise.lunge => l10n.formcheckExerciseLunge,
          FormExercise.situp => l10n.formcheckExerciseSitup,
          FormExercise.overheadPress => l10n.formcheckExerciseOverheadPress,
        };
    return Wrap(
      spacing: 8,
      children: [
        for (final e in FormExercise.values)
          ChoiceChip(
            key: Key('form_check.exercise.${e.name}'),
            label: Text(label(e)),
            selected: e == selected,
            onSelected: (_) =>
                ref.read(selectedExerciseProvider.notifier).state = e,
          ),
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
  const _Silhouette({required this.demo, required this.demonstrating});

  final Animation<double> demo;
  final bool demonstrating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Not in avatar mode. This outline is a TARGET: a fixed shape fitted to the
    // panel with `fitSilhouette`, for the user to walk into while the camera
    // shows them through it. The avatar is the opposite — the user's own body,
    // placed where the detector says the body is. Drawn together they are two
    // human figures at two unrelated scales in the same box, and the operator's
    // screenshot shows what that looks like: a full-height ghost standing
    // through a message explaining that no body could be found at all.
    if (ref.watch(avatarModeProvider)) return const SizedBox.shrink();

    final target = ref.watch(poseTargetProvider);
    final pair = ref.watch(poseDemoProvider);
    final build = ref.watch(silhouetteBuildProvider);

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
      child: GlassCard(
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
    this.isDemo = false,
  });

  final PoseTarget target;

  /// Live match, 0..1, or null when the body cannot be read.
  final double? match;

  /// How broad to draw it, from the intake.
  final BodyBuild build;

  /// Drawing the movement rather than the position to reach.
  final bool isDemo;

  @override
  void paint(Canvas canvas, Size size) {
    // A two-sided body, and ONE scale for both axes. Drawing straight from
    // `target.joints` gave half a skeleton, and multiplying x by the panel
    // width while multiplying y by its height squeezed that half horizontally
    // by 1.78x on a 9:16 panel — together, the "закорючка" the operator saw
    // twice. Both faults live in `pose_silhouette.dart` now, with tests.
    final figure = buildSilhouette(target, build: build);
    if (figure.segments.isEmpty) return;
    final (scale, origin) = fitSilhouette(figure.bounds, size);
    Offset place(Offset p) => p * scale + origin;

    // Green once the shape is reached, so the user gets the answer while they
    // are still in the position and can feel what it corresponds to.
    final reached = (match ?? 0) >= kPoseMatchPassing;
    final colour = reached ? AppPalette.auroraTeal : Colors.white;
    final alpha = isDemo
        ? 0.45
        : reached
            ? 0.95
            : 0.65;

    final limbWidth =
        (figure.limbThickness * scale * (isDemo ? 0.85 : 1.0)).clamp(4.0, 30.0);

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
    canvas.drawPath(
        body, Paint()..color = colour.withValues(alpha: alpha * 0.34));
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (limbWidth * 0.22).clamp(2.0, 5.0)
        ..strokeJoin = StrokeJoin.round
        ..color = colour.withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(_SilhouettePainter old) =>
      old.target.id != target.id ||
      old.isDemo != isDemo ||
      old.build != build ||
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

/// Live match readout. Small, and only while there is something to report.
class _MatchReadout extends ConsumerWidget {
  const _MatchReadout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Nothing to report while the avatar is on: there is no target being
    // scored against there, so `poseMatchProvider` simply holds whatever the
    // last camera-mode frame left in it. A percentage that stopped moving is
    // worse than no percentage — it looks like a live number that has frozen.
    if (ref.watch(avatarModeProvider)) return const SizedBox.shrink();
    final match = ref.watch(poseMatchProvider);
    if (match == null) return const SizedBox.shrink();
    final pct = (match * 100).round();
    final reached = match >= kPoseMatchPassing;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (reached ? AppPalette.auroraTeal : Colors.black)
            .withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        AppLocalizations.of(context).formcheckSilhouetteMatch(pct),
        key: const Key('form_check.match'),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}
