import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/camera/camera_session.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../visual_equipment/widgets/live_equipment_preview.dart';
import '../data/progress_photo.dart';
import '../state/progress_photos_providers.dart';

/// One shot, framed the way the user chose.
class PhotoShot {
  const PhotoShot({required this.bytes, required this.angle});

  final Uint8List bytes;
  final ProgressPhotoAngle angle;
}

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
/// ## The shutter fires HERE, and that is load-bearing
///
/// It used to return the angle and let the page call `capture()` afterwards.
/// That was already a race: closing the sheet runs [dispose], which stops the
/// camera, while the page was starting a capture on it — `captureStill` has a
/// guard for exactly that collision. It happened to win often enough to look
/// like it worked.
///
/// R11f made it certain to lose. With a review screen between the shot and
/// the write, the camera would have been stopped for seconds before anyone
/// asked it for a picture, and `awaitReady` would have timed out and returned
/// null — indistinguishable, one layer up, from "the user backed out".
///
/// So the sheet takes the picture while its own camera is demonstrably open,
/// and hands back the pixels. It still has no opinion about storage or
/// encryption: [ProgressPhotosController.takeShot] goes through the repository
/// as before, which is what deletes the plaintext temp file.
class PhotoCaptureSheet extends ConsumerStatefulWidget {
  const PhotoCaptureSheet({super.key});

  /// Opens the sheet. Resolves to the shot, or null if the user backed out —
  /// the same "null means cancelled" contract `PhotoSource.take` uses one
  /// layer down.
  static Future<PhotoShot?> show(BuildContext context) {
    return showModalBottomSheet<PhotoShot>(
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

  /// A capture in flight. Blocks the shutter, because `takePicture()` takes
  /// long enough on a real phone for a second tap to land, and two taps used
  /// to mean two photos of the same pose.
  bool _shooting = false;

  /// Why the last attempt produced nothing. Shown in the sheet rather than
  /// thrown away: the camera failing is the one moment the user is standing
  /// still waiting for a result.
  Object? _shotError;

  Future<void> _shoot() async {
    setState(() {
      _shooting = true;
      _shotError = null;
    });
    try {
      final bytes =
          await ref.read(progressPhotosControllerProvider.notifier).takeShot();
      if (!mounted) return;
      if (bytes == null) {
        // The camera declined without failing — nothing to hand back, and
        // nothing to apologise for either.
        setState(() => _shooting = false);
        return;
      }
      Navigator.of(context).pop(PhotoShot(bytes: bytes, angle: _angle));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _shooting = false;
        _shotError = e;
      });
    }
  }

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
          if (_shotError != null) ...[
            const SizedBox(height: 10),
            Text(
              l10n.photosCaptureFailed(_shotError!),
              key: const Key('photos.shotError'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Flexible because this Row now carries a third control. A Row
              // neither wraps nor scrolls, and the label is the only child
              // whose width depends on the language and the text scale -- so
              // it is the one that has to give, rather than the shutter being
              // pushed off the edge. Same failure the programme-card chips hit
              // (bug 5, `725c215`).
              Flexible(
                child: TextButton(
                  key: const Key('photos.captureCancel'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    l10n.commonCancel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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
                    onTap: _shooting ? null : _shoot,
                    child: SizedBox(
                      width: 68,
                      height: 68,
                      child: _shooting
                          ? Padding(
                              padding: const EdgeInsets.all(22),
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: theme.colors.onAccent,
                              ),
                            )
                          : Icon(Icons.photo_camera_outlined,
                              size: 28, color: theme.colors.onAccent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              // A progress shot is of the user, and this sheet opens the BACK
              // camera -- so without this the only way to take one was to hand
              // the phone to somebody else or shoot blind. The front lens
              // frames a torso at arm's length, the back lens at a mirror
              // frames all of you: both are the right answer to different
              // rooms, so the choice belongs to the user rather than to a
              // default.
              ValueListenableBuilder<SessionFacing>(
                valueListenable: session.activeFacing,
                builder: (context, facing, _) => IconButton(
                  key: const Key('photos.flipCamera'),
                  tooltip: l10n.photosFlipCamera,
                  icon: Icon(
                    facing == SessionFacing.front
                        ? Icons.cameraswitch_outlined
                        : Icons.cameraswitch,
                    color: theme.colors.textSecondary,
                  ),
                  onPressed: session.flip,
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
