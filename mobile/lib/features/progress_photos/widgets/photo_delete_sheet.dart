import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../../../shared/widgets/app_buttons.dart';

/// Asks before a long-press on a tile actually deletes the photo.
///
/// Same sheet shape as [PhotoConsentSheet] on purpose — one bottom-sheet
/// convention for the feature, not two. The accept button carries
/// [AppButtonTone.destructive] because this action is exactly what that tone
/// exists for: irreversible, per `PhotoConsentSheet`'s own promise that there
/// is no backup, so a delete here is not a soft-delete anywhere else either.
class PhotoDeleteSheet extends StatelessWidget {
  const PhotoDeleteSheet({super.key});

  /// Resolves true only on an explicit confirm. A swipe-down or a tap outside
  /// resolves null and is read as "no" — the same reasoning as
  /// `PhotoConsentSheet.show`, sharpened here because the outcome this guards
  /// is not "open the camera" but "destroy the only copy that exists".
  static Future<bool> show(BuildContext context) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PhotoDeleteSheet(),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Container(
      key: const Key('photos.delete'),
      decoration: BoxDecoration(
        color: theme.colors.surfaceElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.progressphotosDeleteConfirmTitle,
            textAlign: TextAlign.center,
            style:
                theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.progressphotosDeleteConfirmBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colors.textSecondary),
          ),
          const SizedBox(height: 20),
          AppPrimaryButton(
            key: const Key('photos.delete.confirm'),
            tone: AppButtonTone.destructive,
            onPressed: () => Navigator.of(context).pop(true),
            label: l10n.progressphotosDelete,
          ),
          const SizedBox(height: 4),
          TextButton(
            key: const Key('photos.delete.cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
        ],
      ),
    );
  }
}
