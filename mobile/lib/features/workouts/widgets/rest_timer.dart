import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../shared/widgets/app_buttons.dart';
import '../../../shared/widgets/hud/hud_metric.dart';
import '../../../shared/widgets/hud/hud_surface.dart';
import '../state/rest_timer_providers.dart';
import '../../../core/theme/app_semantic_colors.dart';

/// Glass-card rest timer.
///
/// Holds no countdown of its own. The rest lives in [restTimerProvider] as a
/// deadline, and this widget renders it and owns a 1 Hz repaint — see that
/// file for why the two were separated.
///
/// The repaint timer is the only clock here, and it is honestly a repaint
/// timer: if it fires late, or twice, or not at all while the app is
/// backgrounded, the displayed number is still correct the moment a frame is
/// drawn, because it is computed from the deadline rather than accumulated.
class RestTimer extends ConsumerStatefulWidget {
  const RestTimer({super.key, this.onFinished});

  /// Fired once when the rest ends, either way. The outcome distinguishes the
  /// two, because a skip should not be reported as a completed rest.
  final void Function(RestOutcome outcome)? onFinished;

  @override
  ConsumerState<RestTimer> createState() => _RestTimerState();
}

class _RestTimerState extends ConsumerState<RestTimer> {
  Timer? _repaint;
  RestOutcome? _announced;

  @override
  void initState() {
    super.initState();
    // Repaint only. It does not decide anything and nothing waits on it: the
    // rest ends by the clock passing the deadline, whether or not this widget
    // is alive to see it. An earlier version called a `completeIfElapsed()`
    // into the controller from here, which made this ticker the only thing in
    // the app that could finish a rest — and popping the page cancelled it.
    _repaint = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _repaint?.cancel();
    super.dispose();
  }

  String _format(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _announce(RestOutcome outcome) {
    if (_announced == outcome) return;
    _announced = outcome;
    // Only an elapsed rest buzzes. Confirming a button press with a haptic is
    // noise, and the user who pressed Skip is already looking at the phone.
    if (outcome == RestOutcome.elapsed) HapticFeedback.heavyImpact();
    widget.onFinished?.call(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colors;
    final l = AppLocalizations.of(context);
    final rest = ref.watch(restTimerProvider);
    final now = ref.read(restClockProvider)();

    final outcome = rest.outcomeAt(now);
    if (outcome != null) {
      // After the frame: firing a haptic and a callback from inside build would
      // mutate state during a build.
      WidgetsBinding.instance.addPostFrameCallback((_) => _announce(outcome));
    } else {
      _announced = null;
    }

    final remaining = rest.remaining(now);
    final done = outcome != null;

    return HudPanel(
      key: const Key('rest-timer'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Reconciled onto the Session ring's own language (GPT-PM,
              // 2026-08-30 gate decision: "RestTimer -> HudRing -- GO"),
              // scaled down to a compact indicator rather than the hero
              // Session-150 geometry -- this ring sits in a 56px row icon,
              // not the exercise player's own full-size timer.
              // done/in-progress reuse the same success/accentPrimary split
              // SetTimerCard now uses for its own ring, so a completed rest
              // and a completed set read as the same colour everywhere.
              // GPT-PM round 1 (2026-08-30): `CircularProgressIndicator`
              // exposed a progress-role semantic value automatically; a bare
              // `HudRing` does not unless given `semanticsLabel`, and that
              // path excludes the child's own semantics (`hud_metric.dart`),
              // which would silence the countdown text `SetTimerCard`'s own
              // ring is deliberately built to keep audible. Merging both into
              // one explicit node here keeps a screen reader informed of
              // both what this is and what it currently reads -- and reads
              // as one stop instead of two disconnected ones the old
              // Stack-sibling layout produced.
              //
              // Round 2: the value also carries the percentage the stock
              // widget's own semantics used to compute
              // (`ProgressIndicator._buildSemanticsWrapper`, this project's
              // pinned Flutter 3.27.1 -- `expandedSemanticsValue ??=
              // '${(value! * 100).round()}%'`), alongside the countdown
              // rather than instead of it. GPT-PM's round-2 finding named a
              // `SemanticsRole.progressBar` + `minValue`/`maxValue` API that
              // does not exist in this SDK (`grep -rl SemanticsRole
              // /d/flutter/packages/flutter/lib/` -- zero matches; that API
              // was added to Flutter after this project's pinned version) --
              // this restores the actual thing the old widget emitted, not
              // the newer-Flutter API GPT-PM's citation assumed was
              // available here.
              Semantics(
                label: l.restTimerTitle,
                value:
                    '${_format(remaining)}, ${(rest.progress(now).clamp(0.0, 1.0) * 100).round()}%',
                excludeSemantics: true,
                child: HudRing(
                  size: 56,
                  radius: 24,
                  strokeWidth: 4,
                  glowBlur: 6,
                  progress: rest.progress(now),
                  color: done ? colors.success : colors.accentPrimary,
                  child: Text(
                    _format(remaining),
                    key: const Key('rest-timer.remaining'),
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      switch (outcome) {
                        RestOutcome.elapsed => l.restTimerDone,
                        RestOutcome.skipped => l.restTimerSkipped,
                        null => l.restTimerTitle,
                      },
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      done ? l.restTimerDoneHint : l.restTimerHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!done)
                AppIconButton(
                  key: const Key('rest-timer.pause'),
                  tooltip: rest.isPaused ? l.restTimerResume : l.workoutsPause,
                  icon: rest.isPaused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  onPressed: () {
                    final c = ref.read(restTimerProvider.notifier);
                    rest.isPaused ? c.resume() : c.pause();
                  },
                ),
            ],
          ),
          if (!done) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: AppSecondaryButton(
                    key: const Key('rest-timer.add'),
                    icon: Icons.add_rounded,
                    label: l.restTimerAddTime,
                    // Both controls are full-width halves rather than icons:
                    // §25 asks for 44-48 logical pixels, and these are pressed
                    // mid-set by someone who is out of breath.
                    onPressed: () => ref
                        .read(restTimerProvider.notifier)
                        .addTime(const Duration(seconds: 30)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppPrimaryButton(
                    key: const Key('rest-timer.skip'),
                    icon: Icons.skip_next_rounded,
                    label: l.restTimerSkip,
                    onPressed: () =>
                        ref.read(restTimerProvider.notifier).skip(),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
