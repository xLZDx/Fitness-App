import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../shared/widgets/app_buttons.dart';
import '../../../shared/widgets/glass.dart';
import '../data/progress_photo.dart';
import 'photo_bitmap.dart';
import 'photo_capture_sheet.dart' show angleLabel;

/// What the user decided about the shot they just took.
enum PhotoReviewChoice {
  /// File it. The metadata step comes next.
  keep,

  /// Go back to the camera and take another.
  retake,
}

/// Look at the shot before it is filed.
///
/// ## Why this exists
///
/// Progress photos are the one feature where a bad frame is invisible until
/// weeks later: the point is comparing two pictures taken the same way, and
/// nothing told the user whether THIS one matched the last. The shutter wrote
/// straight to disk, so a shot with a cut-off head or a thumb over the lens
/// joined the timeline with the same authority as a good one, and the only
/// remedy was to delete it from the grid afterwards — by which time the user
/// had put their clothes back on.
///
/// ## A route, not a dialog
///
/// Full-screen because the decision is about detail: whether the framing
/// matches the last shot is not answerable from a thumbnail. Pushed with
/// [Navigator], not registered with `go_router`, because it is a step inside
/// one action rather than a destination — a route for it would be
/// deep-linkable to a screen with no photo to review.
class PhotoReviewScreen extends StatelessWidget {
  const PhotoReviewScreen({
    super.key,
    required this.bytes,
    required this.angle,
  });

  final Uint8List bytes;
  final ProgressPhotoAngle angle;

  /// Resolves to the choice, or null if the user dismissed the screen — which
  /// discards the shot, since nothing has been written yet.
  static Future<PhotoReviewChoice?> show(
    BuildContext context, {
    required Uint8List bytes,
    required ProgressPhotoAngle angle,
  }) {
    return Navigator.of(context).push<PhotoReviewChoice>(
      MaterialPageRoute<PhotoReviewChoice>(
        fullscreenDialog: true,
        builder: (_) => PhotoReviewScreen(bytes: bytes, angle: angle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return FrostedScaffold(
      appBar: GlassAppBar(title: l10n.photosReviewTitle),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 24),
        child: Column(
          children: [
            Text(
              // Says which framing this was taken as, because that is the
              // thing the next shot has to match and the user chose it a
              // screen ago.
              l10n.photosReviewAngle(angleLabel(l10n, angle)),
              key: const Key('photos.review.angle'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  width: double.infinity,
                  // Contain, not cover. A crop here would hide exactly the
                  // edges the user is checking — whether their feet and head
                  // made it into the frame.
                  child: PhotoBitmap(bytes: bytes, fit: BoxFit.contain),
                ),
              ),
            ),
            const SizedBox(height: 20),
            AppPrimaryButton(
              key: const Key('photos.review.keep'),
              onPressed: () =>
                  Navigator.of(context).pop(PhotoReviewChoice.keep),
              icon: Icons.check,
              label: l10n.photosReviewKeep,
            ),
            const SizedBox(height: 10),
            AppSecondaryButton(
              key: const Key('photos.review.retake'),
              onPressed: () =>
                  Navigator.of(context).pop(PhotoReviewChoice.retake),
              label: l10n.photosReviewRetake,
            ),
          ],
        ),
      ),
    );
  }
}
