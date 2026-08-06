import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../../shared/widgets/glass.dart';
import '../../equipment/data/equipment_models.dart';
import '../data/set_session.dart';
import '../state/set_timer_providers.dart';

/// The timed set: a ring, a clock, and three controls.
///
/// Operator's list, in order: a button to begin, a sound at the start, ticking
/// for the last five seconds, a gong at the end, a rest, ticking again, a gong,
/// a pause, and a spoken explanation before any of it.
class SetTimerCard extends ConsumerWidget {
  const SetTimerCard({super.key, required this.exercise});

  final ExerciseItem exercise;

  /// What the coach says before the first repetition.
  ///
  /// The exercise's own first step, not a generated summary: the catalog
  /// already carries written instructions, and reading them aloud is both
  /// truthful and free. Trimmed to one sentence because a coach that recites
  /// four paragraphs while the user is holding a plank is not helping.
  String _intro(BuildContext context, SetPlan plan) {
    final l10n = AppLocalizations.of(context);
    final head = l10n.timerSpokenIntro(
        exercise.title, plan.sets, plan.workSeconds, plan.restSeconds);
    final first = exercise.steps.isEmpty ? '' : exercise.steps.first.trim();
    if (first.isEmpty) return head;
    final sentence = first.split(RegExp(r'(?<=[.!?])\s')).first;
    return '$head $sentence';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final plan = ref.watch(setPlanProvider(exercise));
    final timer = ref.watch(setTimerProvider);
    final controller = ref.read(setTimerProvider.notifier);

    final (label, colour) = switch (timer.phase) {
      SetPhase.gettingReady => (l10n.timerGetReady, AppPalette.auroraPeach),
      SetPhase.work => (l10n.timerWork, AppPalette.auroraTeal),
      SetPhase.rest => (l10n.timerRest, AppPalette.auroraBlue),
      SetPhase.done => (l10n.timerDone, AppPalette.auroraLime),
      SetPhase.idle => (l10n.timerReady, AppPalette.auroraViolet),
    };

    return GlassCard(
      key: const Key('workout.set_timer'),
      child: Column(
        children: [
          Row(
            children: [
              Text(l10n.timerTitle,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              _MuteButton(),
              _VoiceButton(),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            timer.isIdle
                ? l10n.timerPlanSummary(
                    plan.sets, plan.workSeconds, plan.restSeconds)
                : l10n.timerSetOf(
                    timer.setNumber == 0 ? 1 : timer.setNumber, plan.sets),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.60),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: 176,
            height: 176,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 176,
                  height: 176,
                  child: TweenAnimationBuilder<double>(
                    // Animated between ticks so the ring sweeps rather than
                    // stepping once a second — a stepping ring reads as a
                    // stopwatch that is lagging.
                    tween: Tween(end: timer.isIdle ? 0.0 : timer.progress),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.linear,
                    builder: (_, value, __) => CircularProgressIndicator(
                      value: value,
                      strokeWidth: 12,
                      strokeCap: StrokeCap.round,
                      backgroundColor:
                          theme.colorScheme.onSurface.withValues(alpha: 0.08),
                      valueColor: AlwaysStoppedAnimation(colour),
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timer.isIdle
                          ? _clock(plan.workSeconds)
                          : _clock(timer.secondsLeft),
                      key: const Key('workout.set_timer.clock'),
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 2,
                        fontWeight: FontWeight.w900,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (!timer.isIdle && !timer.isDone) ...[
                Expanded(
                  child: _Secondary(
                    key: const Key('workout.set_timer.skip'),
                    icon: Icons.skip_next_rounded,
                    label: l10n.timerSkip,
                    onTap: controller.skip,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: 2,
                child: _Primary(
                  key: const Key('workout.set_timer.primary'),
                  label: switch (timer.phase) {
                    SetPhase.idle => l10n.timerStart,
                    SetPhase.done => l10n.timerAgain,
                    _ => timer.running ? l10n.timerPause : l10n.timerResume,
                  },
                  icon: timer.running
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  colour: colour,
                  onTap: () {
                    if (timer.isDone) {
                      controller.reset();
                      controller.start(plan, spokenIntro: _intro(context, plan));
                    } else if (timer.running) {
                      controller.pause();
                    } else {
                      controller.start(
                        plan,
                        spokenIntro: timer.isIdle ? _intro(context, plan) : null,
                      );
                    }
                  },
                ),
              ),
              if (!timer.isIdle) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _Secondary(
                    key: const Key('workout.set_timer.reset'),
                    icon: Icons.stop_rounded,
                    label: l10n.timerStop,
                    onTap: controller.reset,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static String _clock(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _MuteButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = ref.watch(setCuesMutedProvider);
    return IconButton(
      key: const Key('workout.set_timer.mute'),
      visualDensity: VisualDensity.compact,
      tooltip: AppLocalizations.of(context).timerSounds,
      icon: Icon(muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
      onPressed: () =>
          ref.read(setCuesMutedProvider.notifier).state = !muted,
    );
  }
}

class _VoiceButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(setVoiceEnabledProvider);
    return IconButton(
      key: const Key('workout.set_timer.voice'),
      visualDensity: VisualDensity.compact,
      tooltip: AppLocalizations.of(context).timerVoice,
      icon: Icon(on ? Icons.record_voice_over_rounded : Icons.voice_over_off),
      onPressed: () =>
          ref.read(setVoiceEnabledProvider.notifier).state = !on,
    );
  }
}

class _Primary extends StatelessWidget {
  const _Primary({
    super.key,
    required this.label,
    required this.icon,
    required this.colour,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
              colors: [colour, colour.withValues(alpha: 0.72)]),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppSemanticColors.onGradientInk, size: 22),
            const SizedBox(width: 8),
            Text(label,
                style: theme.textTheme.titleMedium?.copyWith(
                    color: AppSemanticColors.onGradientInk, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _Secondary extends StatelessWidget {
  const _Secondary({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: theme.colorScheme.onSurface.withValues(alpha: 0.09),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}
