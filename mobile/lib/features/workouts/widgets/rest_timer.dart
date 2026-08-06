import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/glass.dart';
import '../state/rest_timer_providers.dart';

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
    _repaint = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // Asking the controller rather than deciding here: the widget can be
      // repainted for a dozen reasons and only the state knows whether the
      // deadline actually passed.
      ref.read(restTimerProvider.notifier).completeIfElapsed();
      setState(() {});
    });
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
    final scheme = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final rest = ref.watch(restTimerProvider);
    final now = ref.read(restClockProvider)();

    final outcome = rest.outcome;
    if (outcome != null) {
      // After the frame: firing a haptic and a callback from inside build would
      // mutate state during a build.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _announce(outcome));
    } else {
      _announced = null;
    }

    final remaining = rest.remaining(now);
    final done = rest.isFinished;

    return GlassCard(
      key: const Key('rest-timer'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: rest.progress(now),
                      strokeWidth: 4,
                      backgroundColor: scheme.onSurface.withValues(alpha: 0.10),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        done ? AppPalette.auroraLime : AppPalette.auroraBlue,
                      ),
                    ),
                    Text(
                      _format(remaining),
                      key: const Key('rest-timer.remaining'),
                      style: theme.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
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
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              if (!done)
                IconButton(
                  key: const Key('rest-timer.pause'),
                  tooltip: rest.isPaused ? l.restTimerResume : l.workoutsPause,
                  icon: Icon(rest.isPaused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded),
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
                  child: OutlinedButton.icon(
                    key: const Key('rest-timer.add'),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(l.restTimerAddTime),
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
                  child: FilledButton.icon(
                    key: const Key('rest-timer.skip'),
                    icon: const Icon(Icons.skip_next_rounded, size: 18),
                    label: Text(l.restTimerSkip),
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
