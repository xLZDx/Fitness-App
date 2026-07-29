import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
import '../../shared/widgets/glass.dart';
import 'data/form_classifier.dart';
import 'data/mlkit_pose_detector_service.dart';
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
    with WidgetsBindingObserver {
  bool _started = false;
  Object? _startError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startDetector();
  }

  void _startDetector() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(poseDetectorServiceProvider).start();
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
      ref.read(poseDetectorServiceProvider).stop();
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
    ref.read(poseDetectorServiceProvider).stop();
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

    return FrostedScaffold(
      appBar: GlassAppBar(
        title: 'Form coach',
        actions: [
          IconButton(
            icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
            tooltip: muted ? 'Unmute cues' : 'Mute cues',
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
                    if (_startError != null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'Camera unavailable: $_startError',
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
                      child: _CueCard(feedback: feedback),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SetSummaryCard(
            session: session,
            onReset: () =>
                ref.read(repSessionControllerProvider.notifier).resetSet(),
          ),
          const SizedBox(height: 16),
          GlassCard(
            child: Text(
              'Form coach runs on-device using MediaPipe pose detection. '
              'No frames are uploaded — your camera stays private.',
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
  final dynamic svc; // PoseDetectorService

  @override
  Widget build(BuildContext context) {
    if (svc is! MlKitPoseDetectorService) {
      // Mock service in test/dev — show the static placeholder.
      return const Center(
        child: Icon(Icons.videocam_outlined,
            color: Colors.white24, size: 80),
      );
    }
    final ctl = svc.cameraController as CameraController?;
    if (ctl == null || !ctl.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return CameraPreview(ctl);
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
            'reps - ${repPhaseLabel(session.phase)}',
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

/// Human-readable name for a [RepPhase].
String repPhaseLabel(RepPhase phase) => switch (phase) {
      RepPhase.top => 'ready',
      RepPhase.descending => 'lowering',
      RepPhase.bottom => 'bottom',
      RepPhase.ascending => 'driving up',
    };

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
          'No reps yet. Stand tall to start — reps are counted from the top '
          'of the movement.',
          key: const Key('form_check.summary_empty'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.70),
          ),
        ),
      );
    }

    final offenders = <String>{
      for (final rep in session.reps) ...rep.offendingRules,
    };

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'This set',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                onPressed: onReset,
                child: const Text('Reset set'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${session.cleanReps} clean - ${session.sloppyReps} need work '
            '(${session.reps.length} total)',
            key: const Key('form_check.summary_tally'),
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (offenders.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Flagged: ${offenders.join(', ')}',
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
            'Form coach is a Sustainer benefit',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            r'Free of $2,500 hardware. Works on your phone — no '
            'depth-camera required.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _CueCard extends StatelessWidget {
  const _CueCard({this.feedback});
  final FormFeedback? feedback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (feedback == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          'Stand back so your full body fits in the frame.',
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
        feedback!.cue,
        style: theme.textTheme.titleSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
