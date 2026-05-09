import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/glass.dart';
import '../data/workout_log.dart';

/// Modal bottom sheet shown right after "Mark complete" succeeds. Single
/// 1-tap question: was that set too easy / right / too hard? Result
/// returns to the caller via Navigator.pop with a `DifficultyRating?`.
///
/// Skipping the sheet (drag-to-dismiss / outside tap) returns null, which
/// the caller treats as "user declined to rate" and leaves
/// `difficulty: null` on the log.
class DifficultyRatingSheet extends StatelessWidget {
  const DifficultyRatingSheet({super.key, required this.exerciseTitle});
  final String exerciseTitle;

  static Future<DifficultyRating?> show(
    BuildContext context, {
    required String exerciseTitle,
  }) {
    return showModalBottomSheet<DifficultyRating>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DifficultyRatingSheet(exerciseTitle: exerciseTitle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: GlassCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How did that feel?',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              exerciseTitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _RatingPill(
                  emoji: '😅',
                  label: 'Too easy',
                  gradient: const [
                    AppPalette.auroraTeal,
                    AppPalette.auroraLime,
                  ],
                  onTap: () => Navigator.of(context)
                      .pop(DifficultyRating.tooEasy),
                ),
                const SizedBox(width: 8),
                _RatingPill(
                  emoji: '👍',
                  label: 'Right',
                  gradient: const [
                    AppPalette.auroraViolet,
                    AppPalette.auroraBlue,
                  ],
                  onTap: () => Navigator.of(context)
                      .pop(DifficultyRating.justRight),
                ),
                const SizedBox(width: 8),
                _RatingPill(
                  emoji: '🥵',
                  label: 'Too hard',
                  gradient: const [
                    AppPalette.auroraPeach,
                    AppPalette.auroraPink,
                  ],
                  onTap: () => Navigator.of(context)
                      .pop(DifficultyRating.tooHard),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Your rating tunes future workouts — both the suggested weight '
              'and the recommended-for-you feed adjust to keep the challenge '
              'right where it should be.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingPill extends StatelessWidget {
  const _RatingPill({
    required this.emoji,
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final List<Color> gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(colors: gradient),
          ),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 32)),
              const SizedBox(height: 6),
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
