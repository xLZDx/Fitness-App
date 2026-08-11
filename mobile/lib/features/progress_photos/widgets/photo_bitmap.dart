import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// The widest a progress photo is ever decoded to.
///
/// Progress shots are captured at `ResolutionPreset.medium`
/// (`lib/core/camera/camera_session.dart:185`), which is 480p — about 720x480
/// as the sensor reports it. Asking the decoder for more than the source has
/// does not add detail, it upscales, and an upscaled bitmap costs exactly the
/// memory this file exists to save.
///
/// This is a CEILING, not the true source width. A photo taken with the phone
/// upright is portrait, and its real pixel width is the shorter side — so
/// between roughly 480 and 720 this cap stops nothing. It is not tightened to
/// 480 because a genuinely landscape shot in the compare pane would then be
/// decoded below what it has, which is a visible loss to avoid an invisible
/// one. The tile sizes that matter are far below either number; the cap only
/// binds on a wide tablet pane.
///
/// If the capture preset changes, this changes with it — that is why the
/// number lives next to the reason and not inline at a call site.
const int kMaxPhotoDecodeWidth = 720;

/// Decrypted photo pixels, decoded at the size the layout actually needs.
///
/// A bare `Image.memory` decodes at the source's full resolution no matter how
/// small it is drawn. In a three-across grid that is a ~1.4 MB bitmap held for
/// a tile about a fifth of that area, and the bitmap of a photo the widget is
/// showing cannot be evicted from Flutter's image cache — it is live. Thirty
/// tiles was tens of megabytes to draw thumbnails.
///
/// [cacheWidth] moves the resize into the decoder, so the large version is
/// never allocated at all. It is measured from the real constraints rather
/// than assumed, because the same widget serves a grid tile and a compare pane
/// that is several times wider.
class PhotoBitmap extends StatelessWidget {
  const PhotoBitmap({super.key, required this.bytes, this.fit = BoxFit.cover});

  final Uint8List bytes;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Image.memory(
          bytes,
          fit: fit,
          cacheWidth: decodeWidthFor(constraints.maxWidth, dpr),
          // The third failure mode, and the only one that was invisible.
          // Callers already tell a missing blob apart from a key this device
          // no longer holds, because those need different answers from the
          // user. Bytes that decrypt cleanly and then will not decode reach
          // neither branch: they are a successful read of something that is
          // not an image, and without this they render as nothing at all —
          // the one outcome this screen twice went out of its way to avoid.
          errorBuilder: (context, error, stack) => ColoredBox(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Center(
                child: Text(
                  AppLocalizations.of(context).progressphotosUnreadable,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Physical pixels to decode to for a pane [logicalWidth] wide, or null when
  /// the width is unbounded or degenerate.
  ///
  /// Null rather than a fallback guess: `cacheWidth` asserts on zero, and an
  /// unbounded pane genuinely has no target — full-resolution decode is the
  /// honest answer there, not an invented number.
  static int? decodeWidthFor(double logicalWidth, double devicePixelRatio) {
    if (!logicalWidth.isFinite || logicalWidth <= 0) return null;
    final physical = (logicalWidth * devicePixelRatio).round();
    if (physical <= 0) return null;
    return physical < kMaxPhotoDecodeWidth ? physical : kMaxPhotoDecodeWidth;
  }
}
