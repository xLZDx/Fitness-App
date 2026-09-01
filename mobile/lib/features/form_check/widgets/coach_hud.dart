// FORM_COACH_REDESIGN G3 — the live heads-up display.
//
// The screen the operator's two reference screenshots are OF. Until this gate
// the live view carried a rep badge, a match percentage and one verdict card,
// all of them floating over the preview in whatever corner was free; the
// reference is a laid-out instrument panel — two ring gauges, a movement strip,
// severity-coloured chips, and a counters panel under the picture.
//
// Every value drawn here is one the app already measures. The four counters in
// [CoachCountersPanel] are the exception and they are drawn as em-dashes on
// purpose: they are gate G4's subject, and a placeholder number on an
// instrument is worse than an empty one, because an empty slot reads as "not
// measured yet" and a plausible number reads as a measurement.

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../data/rep_counter.dart';

/// How a readout should be coloured: by what it means, not by its number.
enum CoachTone {
  /// Nothing is wrong. The reference's green.
  good,

  /// Worth correcting, not worth stopping for.
  warn,

  /// A real fault.
  fault,

  /// No verdict — a value with no judgement attached, or none yet.
  neutral,
}

Color _toneColour(BuildContext context, CoachTone tone) => switch (tone) {
      CoachTone.good => AppPalette.auroraTeal,
      CoachTone.warn => AppPalette.auroraPeach,
      CoachTone.fault => AppPalette.auroraPeach,
      // The absence of a verdict is the theme's own ink, not a literal —
      // this one IS text colour, unlike the three tone colours above it,
      // which are the reference's fixed signal palette.
      CoachTone.neutral => Theme.of(context).colors.textPrimary,
    };

/// One of the two circles at the top of the reference.
///
/// A ring, not a filled dial and not a progress arc — the reference draws both
/// gauges as plain outline circles with the number inside, and a partial arc
/// would be claiming a denominator. [ПОВТОРЫ] has no target to be a fraction of
/// (the coach is not driven by a set plan), so drawing 7/10 would invent one.
class CoachRingGauge extends StatelessWidget {
  const CoachRingGauge({
    super.key,
    required this.label,
    required this.value,
    this.suffix,
    this.caption,
    this.tone = CoachTone.neutral,
    this.valueKey,
    this.captionKey,
  });

  /// Key on the number itself, so a test can read the value rather than the
  /// gauge. The keys the old floating badges carried live on here, which is
  /// what lets the suite keep asserting on what the screen SAYS across a
  /// change to how it is laid out.
  final Key? valueKey;
  final Key? captionKey;

  /// Small uppercase word above the number: «ПОВТОРЫ», «ТЕХНИКА».
  final String label;

  /// The number itself, already formatted.
  final String value;

  /// Unit or denominator, set smaller and beside the number: «%», «/ 10».
  final String? suffix;

  /// One short line under the number saying WHY it reads the way it does —
  /// the reference's «тяга вниз» under a technique score.
  final String? caption;

  final CoachTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = _toneColour(context, tone);
    return AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          color: Colors.black.withValues(alpha: 0.30),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colors.textSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 4),
              // The number and its unit share one baseline, so a two-digit and
              // a three-digit value do not shift the unit up and down.
              Flexible(
                child: FittedBox(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        value,
                        key: valueKey,
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: colour,
                          fontWeight: FontWeight.w400,
                          height: 1.0,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (suffix != null) ...[
                        const SizedBox(width: 4),
                        Text(
                          suffix!,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (caption != null) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration:
                          BoxDecoration(shape: BoxShape.circle, color: colour),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        caption!,
                        key: captionKey,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The strip above the gauges: which movement is being coached, and whether the
/// coach is watching right now.
///
/// The dot is the reference's, and it means something rather than decorating:
/// filled while a set is running, hollow while it is paused or not started. A
/// user who has walked back to the phone needs to know which of those they are
/// looking at before they read anything else on the screen.
class CoachExerciseStrip extends StatelessWidget {
  const CoachExerciseStrip({
    super.key,
    required this.movement,
    required this.live,
    this.trailing,
  });

  final String movement;
  final bool live;

  /// Right-hand text, e.g. a set position when one exists.
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: live
                  ? AppPalette.auroraPeach
                  : Colors.white.withValues(alpha: 0.30),
              border: live
                  ? null
                  : Border.all(color: Colors.white.withValues(alpha: 0.55)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              movement,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            Text(
              trailing!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colors.textSecondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One rule's outcome for the last repetition.
///
/// Several at once, which is the point: the reference shows a green tick and an
/// amber correction side by side, because a repetition can be right about one
/// thing and wrong about another and a single worst-cue banner cannot say so.
class CoachCueChip extends StatelessWidget {
  const CoachCueChip({
    super.key,
    required this.text,
    required this.tone,
  });

  final String text;
  final CoachTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = _toneColour(context, tone);
    final icon = switch (tone) {
      CoachTone.good => Icons.check,
      CoachTone.warn => Icons.south_east,
      CoachTone.fault => Icons.priority_high,
      CoachTone.neutral => Icons.remove,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colour.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colour),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Turns a rule's worst severity during a repetition into a tone.
///
/// Severity 0 is not "no data": every shipped rule returns a severity-0
/// observation on the frames it runs, so a rule present in
/// [RepQuality.severityByRule] at 0 is a rule that watched this repetition and
/// had nothing to complain about. That is what earns the green tick — it is a
/// pass, not an absence.
/// Which rules earned a tick on a repetition, worst-name-order, capped.
///
/// Pulled out of the widget that renders them so the CAP is testable. It was
/// asserted through the page — "no more than two chips on screen" — and that
/// assertion could not fail: exactly one classifier is active per movement
/// (`activeClassifiersProvider`), so a rep's [RepQuality.severityByRule] never
/// holds more than one entry and a limit of 2, 10 or none at all produces the
/// same screen. A cap nothing can exceed is not a cap that has been tested.
///
/// Sorted, so the two that survive the cap are the same two every time rather
/// than whichever order a Map happened to yield.
List<String> passedRules(Map<String, int> severityByRule, {int limit = 2}) {
  final passed = [
    for (final e in severityByRule.entries)
      if (e.value <= 0) e.key,
  ]..sort();
  return passed.length <= limit ? passed : passed.sublist(0, limit);
}

CoachTone coachToneForSeverity(int severity) => switch (severity) {
      <= 0 => CoachTone.good,
      1 => CoachTone.warn,
      _ => CoachTone.fault,
    };

/// The reference's «Счётчики тренера» block, under the picture.
///
/// The four values are gate G4's. Until then they are em-dashes, and the panel
/// says which of its numbers are not being measured yet rather than filling
/// them with something plausible — the same rule the exercise picker already
/// follows for movements the coach cannot judge («Тренер не станет делать вид,
/// что оценивает их»).
class CoachCountersPanel extends StatelessWidget {
  const CoachCountersPanel({
    super.key,
    this.tempo,
    this.amplitude,
    this.symmetry,
    this.pause,
    this.symmetryTone = CoachTone.neutral,
  });

  /// Seconds per repetition, or null when not measured.
  final String? tempo;

  /// Percentage of the target range reached, or null.
  final String? amplitude;

  /// Left/right split as the reference writes it («49/51»), or null.
  final String? symmetry;

  /// Seconds held at the bottom, or null.
  final String? pause;

  final CoachTone symmetryTone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    Widget column(String label, String? value, CoachTone tone, Key key) =>
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colors.textSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value ?? l10n.formcheckHudNotMeasured,
                key: key,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: value == null
                      ? theme.colors.textSecondary
                      : _toneColour(context, tone),
                  fontWeight: FontWeight.w400,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.formcheckHudCounters,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              l10n.formcheckHudOnDevice,
              key: const Key('form_check.hud.on_device'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colors.textSecondary,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            column(l10n.formcheckHudTempo, tempo, CoachTone.neutral,
                const Key('form_check.hud.tempo')),
            column(l10n.formcheckHudAmplitude, amplitude, CoachTone.neutral,
                const Key('form_check.hud.amplitude')),
            column(l10n.formcheckHudSymmetry, symmetry, symmetryTone,
                const Key('form_check.hud.symmetry')),
            column(l10n.formcheckHudPause, pause, CoachTone.neutral,
                const Key('form_check.hud.pause')),
          ],
        ),
      ],
    );
  }
}
