import 'dart:async' show TimeoutException;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_palette.dart';
import '../../shared/widgets/glass.dart';
import 'data/cue_text.dart';
import 'data/form_classifier.dart';
import 'data/mlkit_pose_detector_service.dart';
import 'data/pose_detector_service.dart';
import 'data/pose_gate.dart';
import 'data/pose_landmark.dart';
import 'data/pose_projection.dart';
import 'data/pose_target.dart';
import 'data/rep_counter.dart';
import '../subscription/data/subscription_models.dart';
import '../subscription/state/subscription_providers.dart';
import 'state/form_check_providers.dart';

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
  late final AnimationController _demo = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

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
    _startDetector();
  }

  void _startDetector() {
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
    } else if (state == AppLifecycleState.resumed && mounted && !_started) {
      _startDetector();
    }
  }

  @override
  void dispose() {
    _demo.dispose();
    WidgetsBinding.instance.removeObserver(this);
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
    final tier = ref.watch(effectiveTierProvider);
    final isPremium = tier == SubscriptionTier.celebrityTrainer;
    // Watched for its side effects, not its value: building this controller is
    // what subscribes to the frame stream, which is what feeds the gate verdict
    // and the coordinate probe. The card itself now reads the rep verdict
    // instead of the current frame's feedback.
    ref.watch(formFeedbackControllerProvider);
    final svc = ref.watch(poseDetectorServiceProvider);
    final session = ref.watch(repSessionControllerProvider);
    final muted = ref.watch(voiceMutedProvider);
    final gateVerdict = ref.watch(poseGateVerdictProvider);
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

    return FrostedScaffold(
      appBar: GlassAppBar(
        title: AppLocalizations.of(context).formcheckFormCoach,
        actions: [
          IconButton(
            icon: Icon(ref.watch(showSkeletonProvider)
                ? Icons.accessibility_new
                : Icons.accessibility_outlined),
            tooltip: AppLocalizations.of(context).formcheckShowSkeleton,
            onPressed: () {
              final on = !ref.read(showSkeletonProvider);
              ref.read(showSkeletonProvider.notifier).state = on;
              // Drop the held frame on the way out, so switching back on
              // cannot flash a pose from a minute ago over a live camera.
              if (!on) ref.read(latestPoseFrameProvider.notifier).state = null;
            },
          ),
          IconButton(
            icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
            tooltip: muted
                ? AppLocalizations.of(context).formcheckUnmuteCues
                : AppLocalizations.of(context).formcheckMuteCues,
            onPressed: () =>
                ref.read(voiceMutedProvider.notifier).state = !muted,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          if (!isPremium) ...[
            _UpgradeCard(),
            const SizedBox(height: 16),
          ],
          // Which movement is being coached. Above the camera on purpose: the
          // rules that will judge you are chosen here, so it should be read
          // before the set, not discovered after it.
          const _ExercisePicker(),
          const SizedBox(height: 12),
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
                          onRetry: _startDetector,
                        ),
                      )
                    else if (!_started)
                      const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
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
                      Positioned(
                        left: 12,
                        top: 12,
                        child: _RepBadge(session: session),
                      ),
                      const Positioned(
                        right: 12,
                        top: 12,
                        child: _MatchReadout(),
                      ),
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: _CueCard(
                          feedback: session.lastRepCue,
                          clean: session.lastRepClean,
                          gateVerdict: gateVerdict,
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
          // The coordinate diagnostic. Deliberately on screen in a release
          // build rather than behind `kDebugMode`: the measurement it exists to
          // produce can only be taken on the operator's own phone, in the gym,
          // with a real body in frame — a value that never leaves a debug build
          // is a value nobody ever reads. It disappears once V0c has the number.
          if (!ref.watch(poseUnitReportProvider).isEmpty) ...[
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
          _SetSummaryCard(
            session: session,
            onReset: () =>
                ref.read(repSessionControllerProvider.notifier).resetSet(),
          ),
          const SizedBox(height: 16),
          GlassCard(
            child: Text(
              AppLocalizations.of(context).formcheckFormCoachRunsOnDeviceUsing,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.70),
              ),
            ),
          ),
        ],
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
          TextButton(
            key: const Key('form-check-retry'),
            onPressed: onRetry,
            child: Text(l10n.formcheckTryAgain),
          ),
        ],
      ),
    );
  }
}

/// Live rep count + phase, over the camera preview. Deliberately the largest
/// text on the screen — mid-set, at arm's length, this is the only thing the
/// user can actually read.
class _RepBadge extends StatelessWidget {
  const _RepBadge({required this.session});
  final RepSessionState session;

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
          const SizedBox(height: 2),
          // Before the counter has seen the lifter standing it will not start
          // a lap, so the number cannot move however hard the user works. Say
          // what is being waited for; the phase word ("ready") was true and
          // useless, because it looks identical to a counter that has died.
          if (!session.isArmed)
            Text(
              AppLocalizations.of(context).formcheckWaitingForTop,
              key: const Key('form_check.waiting_for_top'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppPalette.auroraPeach,
                fontWeight: FontWeight.w700,
              ),
            )
          else
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
          AppLocalizations.of(context).formcheckNoRepsYetStandTallTo,
          key: const Key('form_check.summary_empty'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.70),
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
              TextButton(
                onPressed: onReset,
                child: Text(AppLocalizations.of(context).formcheckResetSet),
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
                color: theme.colorScheme.onSurface.withValues(alpha: 0.70),
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
    this.gateVerdict = PoseGateVerdict.ok,
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

  /// Why the last frame was unscorable. Drives the placeholder text, so
  /// "step back" and "too dark to read your position" are told apart instead
  /// of both showing the same generic line.
  final PoseGateVerdict gateVerdict;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // A blocked frame always wins the card: whatever the last rep scored, the
    // user needs to know the coach cannot currently see them.
    if (!gateVerdict.isScorable) {
      final hint = poseGateHint(l10n, gateVerdict);
      return _band(
        theme,
        Colors.white.withValues(alpha: 0.18),
        hint.isEmpty ? l10n.formcheckStandBackSoYourFullBody : hint,
        const Key('form_check.gate_hint'),
      );
    }

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

    // Nothing finished yet. Say so rather than showing a colour that would be
    // read as a verdict on a rep that has not happened.
    if (clean == null) {
      return _band(
        theme,
        Colors.white.withValues(alpha: 0.18),
        l10n.formcheckReadyPrompt,
        const Key('form_check.ready'),
      );
    }

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

  Widget _band(ThemeData theme, Color colour, String text, Key key) =>
      Container(
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
    final target = ref.watch(poseTargetProvider);
    final pair = ref.watch(poseDemoProvider);

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
      ),
    );
  }
}

class _SilhouettePainter extends CustomPainter {
  const _SilhouettePainter({
    required this.target,
    required this.match,
    this.isDemo = false,
  });

  final PoseTarget target;

  /// Live match, 0..1, or null when the body cannot be read.
  final double? match;

  /// Drawing the movement rather than the position to reach.
  final bool isDemo;

  @override
  void paint(Canvas canvas, Size size) {
    // Green once the shape is reached, so the user gets the answer while they
    // are still in the position and can feel what it corresponds to.
    final reached = (match ?? 0) >= kPoseMatchPassing;
    final colour = reached ? AppPalette.auroraTeal : Colors.white;
    final alpha = isDemo
        ? 0.45
        : reached
            ? 0.95
            : 0.65;

    // Limbs are drawn as thick round-capped strokes rather than hairlines, and
    // a head is drawn above the shoulders. Six dots joined by five thin lines
    // is geometrically the same figure and reads as a squiggle — operator, on
    // his phone: "человеческий силует привратился а закорючку". The whole
    // instruction is "stand inside this shape", so it has to look like a body
    // from across a room, in motion, at a glance.
    final limbWidth =
        (size.shortestSide * (isDemo ? 0.035 : 0.045)).clamp(6, 26).toDouble();
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = limbWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = colour.withValues(alpha: alpha * 0.55);

    Offset at(LandmarkType t) {
      final j = target.joints[t]!;
      return Offset(j.$1 * size.width, j.$2 * size.height);
    }

    for (final (a, b) in target.bones) {
      canvas.drawLine(at(a), at(b), stroke);
    }

    final head = target.head;
    if (head != null) {
      // Outlined, not filled: a solid disc over a live camera hides the face
      // of the person trying to line themselves up with it.
      canvas.drawCircle(
        Offset(head.$1 * size.width, head.$2 * size.height),
        head.$3 * size.height,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = limbWidth * 0.55
          ..color = colour.withValues(alpha: alpha),
      );
    }

    // The joints on top of the limbs, so the shape reads as articulated rather
    // than as one bent tube.
    final joint = Paint()..color = colour.withValues(alpha: alpha);
    for (final t in target.joints.keys) {
      canvas.drawCircle(at(t), limbWidth * 0.34, joint);
    }
  }

  @override
  bool shouldRepaint(_SilhouettePainter old) =>
      old.target.id != target.id ||
      old.isDemo != isDemo ||
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
