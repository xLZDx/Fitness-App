import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/state/settings_providers.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../../shared/widgets/app_buttons.dart';

/// What the user recorded alongside a shot. Both fields optional — the photo
/// is the point, the numbers are context.
class PhotoDetails {
  const PhotoDetails({this.weightKg, this.note});

  final double? weightKg;
  final String? note;
}

/// Asks what the user weighed, and lets them leave a line about the shot.
///
/// ## The gap this closes
///
/// [PhotoStore.put] has taken `weightKg` and `note` since R7 — it stores them
/// and reads them back — and the single call site never passed either. So the
/// columns existed, the plumbing existed, and every photo in every timeline
/// had nulls in them. That is also why the compare card so rarely had a weight
/// delta to show: not because the user had not weighed themselves, but because
/// nothing had ever asked.
///
/// ## Asked after the photo is kept, not before
///
/// Prototype order (`ProgressPhotoModule:3909`): shoot, look, keep, then
/// describe. Asking first would put a form in front of somebody standing in
/// front of a camera, about a picture that may not survive the next screen.
///
/// ## No prefill from the profile
///
/// Tempting, and wrong. The profile carries a weight from whenever it was last
/// edited; the field here means "what the scale said today", and those differ
/// by exactly the amount the feature exists to track. A prefilled stale number
/// that the user saves without reading is a false record, which is worse than
/// the null it replaced — an empty field at least says "unknown" honestly.
class PhotoDetailsSheet extends ConsumerStatefulWidget {
  const PhotoDetailsSheet({super.key});

  /// Resolves to the details, or null if the user backed out — which discards
  /// the shot, because nothing has been written yet.
  static Future<PhotoDetails?> show(BuildContext context) {
    return showModalBottomSheet<PhotoDetails>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PhotoDetailsSheet(),
    );
  }

  @override
  ConsumerState<PhotoDetailsSheet> createState() => _PhotoDetailsSheetState();
}

class _PhotoDetailsSheetState extends ConsumerState<PhotoDetailsSheet> {
  final _weight = TextEditingController();
  final _note = TextEditingController();

  /// Set when the weight box holds something that is not a weight. Blocks the
  /// save rather than silently filing a null, which would look identical to
  /// "did not answer" and lose what the user actually typed.
  bool _weightInvalid = false;

  @override
  void dispose() {
    _weight.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final raw = _weight.text.trim().replaceAll(',', '.');
    double? kg;
    if (raw.isNotEmpty) {
      kg = double.tryParse(raw);
      // Rejected as a range, not just as a parse: `0` and `900` both parse and
      // neither is a body weight, and a stray digit is the likeliest typo on a
      // numeric keyboard.
      if (kg == null || kg <= 20 || kg >= 400) {
        setState(() => _weightInvalid = true);
        return;
      }
    }
    final note = _note.text.trim();
    Navigator.of(context).pop(
      PhotoDetails(weightKg: kg, note: note.isEmpty ? null : note),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      // Lifts the sheet clear of the keyboard. Without it the note field sits
      // under the keys that are typing into it.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colors.surfaceElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.photosDetailsTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.photosDetailsWhy,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colors.textSecondary),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('photos.details.weight'),
                controller: _weight,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                onChanged: (_) {
                  if (_weightInvalid) setState(() => _weightInvalid = false);
                },
                decoration: InputDecoration(
                  labelText: l10n.photosDetailsWeight,
                  errorText: _weightInvalid ? l10n.photosDetailsWeightBad : null,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('photos.details.note'),
                controller: _note,
                maxLines: 2,
                maxLength: 140,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: l10n.photosDetailsNote),
              ),
              const SizedBox(height: 8),
              AppPrimaryButton(
                key: const Key('photos.details.save'),
                onPressed: _save,
                icon: Icons.check,
                // One button, and it works with both fields empty. A separate
                // "skip" would imply the fields are required, which they are
                // not — leaving them blank IS the skip.
                label: l10n.photosDetailsSave,
              ),
              // The reminder is promised BEFORE it is scheduled, and saving is
              // what raises the notification-permission dialog on Android.
              // Without this line that dialog arrives unexplained, which is
              // the one thing the design brief forbids outright ("no
              // notification permission before contextual explanation").
              //
              // Shown only when reminders are actually on, or it would be a
              // promise the app has already decided not to keep.
              if (ref.watch(settingsControllerProvider).notificationsEnabled)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    l10n.photosDetailsReminderPromise,
                    key: const Key('photos.details.reminderPromise'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colors.textSecondary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
