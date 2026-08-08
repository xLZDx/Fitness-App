import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/camera/camera_session.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../visual_equipment/widgets/live_equipment_preview.dart';
import '../data/progress_photo.dart';
import '../state/progress_photos_providers.dart';

/// Choose an angle, see yourself, then shoot.
///
/// ## The bug this closes
///
/// "Take a new photo" called `capture()` with no arguments: no angle, so every
/// shot was filed as [ProgressPhotoAngle.front], and no preview, so the user
/// pressed a button and a picture was taken of whatever the phone happened to
/// be pointing at. The feature's whole value is comparing two shots taken the
/// same way, and both halves of "the same way" were unaskable.
///
/// The angle is not cosmetic either: `defaultComparePair` refuses to pair
/// across angles, so a library where everything is silently `front` cannot
/// tell a genuine front-to-front comparison from two unrelated pictures.
///
/// ## Returns the angle, does not capture
///
/// The sheet hands its caller the chosen angle and closes; the repository
/// takes the still. Keeping the capture out of here means the sheet has no
/// opinion about storage, encryption or what happens on failure — all of
/// which already have an owner.
class PhotoCaptureSheet extends ConsumerStatefulWidget {
  const PhotoCaptureSheet({super.key});

  /// Opens the sheet. Resolves to the chosen angle, or null if the user
  /// backed out — the same "null means cancelled" contract
  /// `PhotoSource.take` uses one layer down.
  static Future<ProgressPhotoAngle?> show(BuildContext context) {
    return showModalBottomSheet<ProgressPhotoAngle>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PhotoCaptureSheet(),
    );
  }

  @override
  ConsumerState<PhotoCaptureSheet> createState() => _PhotoCaptureSheetState();
}

class _PhotoCaptureSheetState extends ConsumerState<PhotoCaptureSheet> {
  ProgressPhotoAngle _angle = ProgressPhotoAngle.front;

  /// Held from `initState` so `dispose` can release the camera without
  /// touching `ref` — reading a provider after the element unmounts throws,
  /// which is the exact bug the posture page hit at R10.
  CameraSession? _session;

  @override
  void initState() {
    super.initState();
    // Started here rather than by the page: the camera is only wanted while
    // this sheet is open, and the progress-photo session is deliberately its
    // own (`progressPhotoCameraProvider`) so a capture is never coupled to
    // whether the user had recently scanned a machine.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final session = ref.read(progressPhotoCameraProvider);
      _session = session;
      session.start(requestPermission: true);
    });
  }

  @override
  void dispose() {
    // Stopped, not disposed: `progressPhotoCameraProvider` owns the object and
    // disposes it with the scope. Leaving it running would hold the camera
    // open behind a closed sheet — the phone's torch-adjacent "why is the
    // green dot on" problem.
    _session?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final session = ref.watch(progressPhotoCameraProvider);

    return Container(
      decoration: BoxDecoration(
        color: theme.colors.surfaceElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.photosPickAngle,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.photosAngleWhy,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colors.textSecondary),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final a in ProgressPhotoAngle.values)
                ChoiceChip(
                  key: Key('photos.angle.${a.name}'),
                  label: Text(angleLabel(l10n, a)),
                  selected: _angle == a,
                  onSelected: (_) => setState(() => _angle = a),
                ),
            ],
          ),
          const SizedBox(height: 14),
          // Flexible, not a fixed 3:4 box. A 3:4 preview plus the chips plus
          // the controls is taller than the sheet on a short viewport, and an
          // overflowing Column does not shrink -- it clips the shutter off the
          // bottom, which is the one control the sheet exists for. The
          // viewfinder gives up height first because it is the only child that
          // can.
          Flexible(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: ColoredBox(
                color: theme.colors.cameraOverlay,
                child: SizedBox(
                  width: double.infinity,
                  child: LiveEquipmentPreview(session: session),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                key: const Key('photos.captureCancel'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonCancel),
              ),
              const SizedBox(width: 24),
              Semantics(
                button: true,
                label: l10n.photosShoot,
                child: Material(
                  color: theme.colors.accentPrimary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    key: const Key('photos.shutter'),
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(context).pop(_angle),
                    child: SizedBox(
                      width: 68,
                      height: 68,
                      child: Icon(Icons.photo_camera_outlined,
                          size: 28, color: theme.colors.onAccent),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The angle, in the interface language.
///
/// Top-level rather than a method on the enum: the enum lives in the data
/// layer and must not import localisations.
String angleLabel(AppLocalizations l10n, ProgressPhotoAngle a) => switch (a) {
      ProgressPhotoAngle.front => l10n.photosAngleFront,
      ProgressPhotoAngle.side => l10n.photosAngleSide,
      ProgressPhotoAngle.back => l10n.photosAngleBack,
      ProgressPhotoAngle.custom => l10n.photosAngleOther,
    };
