import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../../../shared/widgets/app_buttons.dart';

/// Asks, once per account, before the camera opens for the first progress
/// photo.
///
/// ## Why a sheet and not a banner
///
/// `SafetyDisclosure` argues in its own doc comment against using a dialog for
/// a disclosure, and it is right for the case it describes: a disclosure that
/// stays true has to stay on screen, and one dismissed becomes invisible
/// exactly when it matters. That argument does not reach this widget, because
/// this is not the disclosure. The disclosure is the privacy strip at the top
/// of the photos page, which is permanent and unchanged. This is the question,
/// and a question that cannot be answered by scrolling past it has to
/// interrupt.
///
/// ## What it says, and why those three things
///
/// Each line is something the code actually does, checkable today:
///
/// - encrypted here, no server copy, nothing can share or export one —
///   `LocalProgressPhotosRepository` has no network path and the feature has
///   no export by an earlier recorded decision;
/// - therefore no backup — the same property, told from the side that costs
///   the user something. A reinstall loses the key and the photos with it,
///   which is what `progressphotosKeyMissing` exists to explain after the
///   fact. Saying it beforehand is the difference between a promise and a
///   sales pitch;
/// - the preview is not recorded — `CameraSession` streams frames into an
///   in-memory controller (`camera_session.dart:443-461`) and writes none of
///   them; a picture exists only after the shutter.
///
/// Nothing here claims the photos are analysed, scored or compared by anything
/// off the phone, because nothing does that.
///
/// ## What it deliberately does NOT say
///
/// The third line ended "...and you can delete any photo at any time" until
/// the gate's own review checked it against the build. It is not true today:
/// `ProgressPhotosController.delete` exists
/// (`state/progress_photos_providers.dart:335-344`) and no widget calls it,
/// `_PhotoTile` has no tap or long-press, and the `progressphotosDelete`
/// string sits in both ARB files with zero readers. A consent screen that
/// promises a control the build does not have is the exact failure this whole
/// gate exists to prevent, so the clause was removed rather than the missing
/// screen quietly added — wiring delete is a feature, and this gate is not it.
/// Do not restore the sentence before the button exists.
class PhotoConsentSheet extends StatelessWidget {
  const PhotoConsentSheet({super.key});

  /// Resolves true only on an explicit accept.
  ///
  /// A swipe-down or a tap outside resolves null and is read as "no". Reading
  /// a dismissal as anything else would let a mistaken tap open the camera,
  /// which is the one outcome this gate exists to prevent.
  static Future<bool> show(BuildContext context) async {
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PhotoConsentSheet(),
    );
    return accepted ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Container(
      key: const Key('photos.consent'),
      decoration: BoxDecoration(
        color: theme.colors.surfaceElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      // Scrollable because the three lines are long, and at a doubled text
      // scale a fixed sheet would push the accept button off the bottom — the
      // one control the sheet exists for.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.photosConsentTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            _Point(
              icon: Icons.lock_outline,
              text: l10n.photosConsentOnDevice,
            ),
            _Point(
              icon: Icons.cloud_off_outlined,
              text: l10n.photosConsentNoBackup,
            ),
            _Point(
              icon: Icons.photo_camera_outlined,
              text: l10n.photosConsentCamera,
            ),
            const SizedBox(height: 20),
            AppPrimaryButton(
              key: const Key('photos.consent.accept'),
              onPressed: () => Navigator.of(context).pop(true),
              label: l10n.photosConsentAccept,
            ),
            const SizedBox(height: 4),
            TextButton(
              key: const Key('photos.consent.decline'),
              // Pops false rather than null so the two ways of saying no are
              // the same value at the call site, and neither can be mistaken
              // for "the sheet never opened".
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.photosConsentDecline),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of the promise. Icon and text are merged into a single accessibility
/// node so a screen reader reads a sentence rather than stopping on a
/// decorative glyph.
class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: theme.colors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text, style: theme.textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}
