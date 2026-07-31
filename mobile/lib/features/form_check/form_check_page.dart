import 'package:camera/camera.dart';
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
    with WidgetsBindingObserver {
  bool _started = false;
  Object? _startError;

  /// Captured at first use so dispose() can release the camera WITHOUT touching
  /// `ref`. Reading a provider from dispose() throws "Cannot use ref after the
  /// widget was disposed" — found by the on-device suite, invisible to the
  /// widget tests because they never unmount this page.
  PoseDetectorService? _service;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startDetector();
  }

  void _startDetector() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final svc = ref.read(poseDetectorServiceProvider);
        _service = svc;
        await svc.start();
        if (!mounted) return;
        setState(() {
          _started = true;
          _startError = null;
        });
      } catch (e) {
        if (!mounted) return;
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
      svc.stop();
      if (mounted) setState(() => _started = false);
    } else if (state == AppLifecycleState.resumed && mounted && !_started) {
      _startDetector();
    }
  }

  @override
  void dispose() {
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
    final feedback = ref.watch(formFeedbackControllerProvider);
    final svc = ref.watch(poseDetectorServiceProvider);
    final session = ref.watch(repSessionControllerProvider);
    final muted = ref.watch(voiceMutedProvider);
    final gateVerdict = ref.watch(poseGateVerdictProvider);
    // Either the camera never opened, or the native detector died mid-stream.
    // Both mean "no reps will be counted", so both belong in the same slot.
    final failure = _startError ?? ref.watch(poseErrorProvider);

    return FrostedScaffold(
      appBar: GlassAppBar(
        title: AppLocalizations.of(context).formcheckFormCoach,
        actions: [
          IconButton(
            icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
            tooltip: muted ? AppLocalizations.of(context).formcheckUnmuteCues : AppLocalizations.of(context).formcheckMuteCues,
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
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            AppLocalizations.of(context).formcheckCameraUnavailable(failure),
                            key: const Key('form-check-error'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      )
                    else if (!_started)
                      const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    else
                      _CameraPreview(svc: svc),
                    Positioned(
                      left: 12,
                      top: 12,
                      child: _RepBadge(session: session),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: _CueCard(
                        feedback: feedback,
                        gateVerdict: gateVerdict,
                      ),
                    ),
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
          if (ref.watch(voiceCoachProvider).lastErrorMessage != null) ...[
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
                color:
                    theme.colorScheme.onSurface.withValues(alpha: 0.70),
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
        child: Icon(Icons.videocam_outlined,
            color: Colors.white24, size: 80),
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
          Text(
            AppLocalizations.of(context)
                .formcheckReps(repPhaseText(AppLocalizations.of(context), session.phase)),
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
            AppLocalizations.of(context).formcheckCleanNeedWorkTotal(session.cleanReps, session.sloppyReps, session.reps.length),
            key: const Key('form_check.summary_tally'),
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (offenders.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              AppLocalizations.of(context).formcheckFlagged(offenders.join(', ')),
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
  const _CueCard({this.feedback, this.gateVerdict = PoseGateVerdict.ok});

  final FormFeedback? feedback;

  /// Why the last frame was unscorable. Drives the placeholder text, so
  /// "step back" and "too dark to read your position" are told apart instead
  /// of both showing the same generic line.
  final PoseGateVerdict gateVerdict;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    if (feedback == null) {
      final hint = poseGateHint(l10n, gateVerdict);
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          hint.isEmpty ? l10n.formcheckStandBackSoYourFullBody : hint,
          key: const Key('form_check.gate_hint'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    final colour = feedback!.severity >= 2
        ? AppPalette.auroraPink
        : feedback!.severity == 1
            ? AppPalette.auroraPeach
            : AppPalette.auroraTeal;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        formCueText(l10n, feedback!.cueKey),
        key: const Key('form_check.cue'),
        style: theme.textTheme.titleSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
