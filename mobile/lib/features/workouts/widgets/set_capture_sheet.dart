import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../shared/widgets/app_buttons.dart';
import '../../../shared/widgets/glass.dart';
import '../../../core/theme/app_semantic_colors.dart';

/// What the user actually lifted. Null fields mean "declined to say".
typedef SetCapture = ({double? weightKg, int? reps});

/// Modal sheet shown when "Mark complete" is tapped, before the log is
/// written.
///
/// ## Why this exists
///
/// `WorkoutLogEntry` has carried `weightKg` and `repsCompleted` since it was
/// written, `suggestNextWeight` reads both, and nothing in the app ever set
/// them — so the whole progression engine (`progression.dart`, four rules, its
/// own tests) was unreachable in production. Every logged set was a timestamp
/// and a title.
///
/// ## Why a sheet rather than fields on the page
///
/// Same pattern as `DifficultyRatingSheet`: `StatelessWidget` plus a static
/// `show()`, result returned through `Navigator.pop` and piped into the entry
/// with `copyWith`. `workout_player_page.dart` is already ~1,000 lines and the
/// plan deliberately declines to split it; growing `_MarkCompleteButton`
/// inline would have added a form to the file with the most reasons to change.
///
/// Skipping is a real answer. Body-weight and mobility work carries no load,
/// and forcing a number would make the field lie rather than stay empty.
class SetCaptureSheet extends StatefulWidget {
  const SetCaptureSheet({
    super.key,
    required this.exerciseTitle,
    this.initialWeightKg,
    this.initialReps,
  });

  final String exerciseTitle;

  /// Pre-filled when re-opening for an already-logged set, so an edit starts
  /// from what is stored rather than from blank.
  final double? initialWeightKg;
  final int? initialReps;

  static Future<SetCapture?> show(
    BuildContext context, {
    required String exerciseTitle,
    double? initialWeightKg,
    int? initialReps,
  }) {
    return showModalBottomSheet<SetCapture>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SetCaptureSheet(
        exerciseTitle: exerciseTitle,
        initialWeightKg: initialWeightKg,
        initialReps: initialReps,
      ),
    );
  }

  @override
  State<SetCaptureSheet> createState() => _SetCaptureSheetState();
}

class _SetCaptureSheetState extends State<SetCaptureSheet> {
  late final TextEditingController _weight = TextEditingController(
    text: widget.initialWeightKg == null
        ? ''
        : _trimZero(widget.initialWeightKg!),
  );
  late final TextEditingController _reps =
      TextEditingController(text: widget.initialReps?.toString() ?? '');

  static String _trimZero(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';

  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    super.dispose();
  }

  void _submit() {
    // Parsed leniently and never coerced. An unparseable weight becomes null —
    // "declined to say" — rather than 0, which `suggestNextWeight` would read
    // as a real lift and divide by.
    final weight = double.tryParse(_weight.text.trim().replaceAll(',', '.'));
    final reps = int.tryParse(_reps.text.trim());
    Navigator.of(context).pop((
      weightKg: weight != null && weight > 0 ? weight : null,
      reps: reps != null && reps > 0 ? reps : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: GlassCard(
        floating: true,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.workoutsLogYourSet,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(widget.exerciseTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colors.textSecondary,
                )),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _weight,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: InputDecoration(
                      labelText: l10n.workoutsWeightKg,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _reps,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: l10n.workoutsReps,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(l10n.workoutsLeaveBlankIfNoLoad,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colors.textSecondary,
                )),
            const SizedBox(height: 16),
            Row(
              children: [
                AppTertiaryButton(
                  // Distinct from submitting two blanks: pop(null) means the
                  // caller keeps whatever is already stored, which is what an
                  // edit that changed its mind should do.
                  onPressed: () => Navigator.of(context).pop(),
                  label: l10n.commonSkip,
                ),
                const SizedBox(width: 12),
                // `Expanded`, and no `Spacer`, because `AppTheme` gives every
                // FilledButton `minimumSize: Size.fromHeight(54)` — and
                // `Size.fromHeight` is `Size(double.infinity, 54)`. A Row hands
                // unbounded width to its non-flex children, so the button
                // resolved to an infinite width and threw "BoxConstraints
                // forces an infinite width" the moment this sheet opened.
                // Expanded is what bounds it; the button filling the rest of
                // the row is the ordinary shape for a sheet's primary action.
                Expanded(
                  child: AppPrimaryButton(
                    onPressed: _submit,
                    label: l10n.commonSave,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
