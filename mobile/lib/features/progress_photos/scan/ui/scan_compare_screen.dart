/// Before/after comparison of two guided scans, pose by pose.
///
/// Three views: side by side, a wipe slider and a ghost overlay. Photos are
/// lined up with [BodyAlignment] from the landmarks stored at the shutter frame;
/// when the points are not enough the photos are shown as taken, with a plain
/// message. Strictly visual: no measurements, no scores, no statements about
/// the body.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../state/progress_photos_providers.dart';
import '../../widgets/photo_bitmap.dart';
import '../body_alignment.dart';
import '../scan_access.dart';
import '../scan_models.dart';
import '../scan_pose.dart';
import '../scan_reminder.dart';
import '../scan_repository.dart';
import 'scan_gate_view.dart';
import 'scan_landmark_mapper.dart';
import 'scan_text.dart';

enum ScanCompareMode { sideBySide, slider, ghost }

/// Decrypted pixels of the photo behind one scan shot, or null when the photo
/// is gone (deleted, key unavailable). Overridable in tests.
final scanShotBytesProvider =
    FutureProvider.autoDispose.family<Uint8List?, String>((ref, photoId) async {
  final photos = await ref.watch(progressPhotosProvider.future);
  for (final p in photos) {
    if (p.id == photoId) {
      try {
        return await ref.watch(photoBytesProvider(p).future);
      } catch (_) {
        return null;
      }
    }
  }
  return null;
});

/// Result of lining up [earlier] onto [later] for one pose.
class ScanAlignmentView {
  const ScanAlignmentView(this.transform, this.failure);

  /// Maps the earlier photo onto the later one; null = show as taken.
  final SimilarityTransform? transform;
  final AlignmentFailure failure;

  bool get aligned => transform != null;

  static ScanAlignmentView compute(ScanShot later, ScanShot earlier) {
    final a = keypointsFromLandmarks(later.landmarks);
    final b = keypointsFromLandmarks(earlier.landmarks);
    final r = BodyAlignment.align(a, b);
    return ScanAlignmentView(r.isUsable ? r.transform : null, r.failure);
  }
}

/// Reads a provider from either a `Ref` (`ref.read`) or a container
/// (`container.read`).
typedef ScanProviderReader = T Function<T>(ProviderListenable<T> provider);

/// Deletes one scan's photos (through the existing progress-photo delete path)
/// and then its landmark sidecar. Throws at the first failure without touching
/// what is left, so a retry can finish the job (deleting an already-removed
/// photo is a no-op). Shared by [confirmAndDeleteScan] and the body-scan
/// "delete this scan's photos" flow (C16).
Future<void> deleteScanFiles(ScanProviderReader read, ScanRecord scan) async {
  final photos = read(progressPhotosControllerProvider.notifier);
  final scans = read(scanRepositoryProvider);
  for (final shot in scan.shots.values) {
    await photos.delete(shot.photoId);
    // The controller reports failure through its state instead of throwing.
    final st = read(progressPhotosControllerProvider);
    if (st.hasError) throw st.error!;
  }
  await scans.delete(scan.id);
}

/// Asks for confirmation, then deletes one scan: its photos first (through the
/// existing progress-photo delete path), then the landmark sidecar, then the
/// history and the reminder are brought up to date. Stops at the first failure
/// without touching what is left, so a retry can finish the job (deleting an
/// already-removed photo is a no-op).
Future<void> confirmAndDeleteScan(
    BuildContext context, WidgetRef ref, ScanRecord scan) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('scan.delete.dialog'),
      title: Text(l10n.scanDeleteTitle),
      content: Text(l10n.scanDeleteBody),
      actions: [
        TextButton(
          key: const Key('scan.delete.cancel'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.scanDeleteCancel),
        ),
        FilledButton(
          key: const Key('scan.delete.confirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.scanDeleteConfirm),
        ),
      ],
    ),
  );
  if (ok != true) return;
  // `ref` is not safe to use once this widget may have been unmounted while
  // the deletes run, so everything is resolved up front from the container.
  if (!context.mounted) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final reminder = container.read(scanReminderEnabledProvider.notifier);
  try {
    await deleteScanFiles(container.read, scan);
    container.invalidate(scanHistoryProvider);
    unawaited(reminder.sync().catchError((Object e) {
      debugPrint('scan: reminder sync after delete failed: $e');
      return null;
    }));
    messenger.showSnackBar(SnackBar(content: Text(l10n.scanDeleted)));
  } catch (e, st) {
    debugPrint('scan: delete failed: $e\n$st');
    // Whatever was removed stays removed; show the real state of the list.
    container.invalidate(scanHistoryProvider);
    messenger.showSnackBar(SnackBar(content: Text(l10n.scanDeleteFailed)));
  }
}

class _DeleteScanButton extends ConsumerWidget {
  const _DeleteScanButton({required this.keyName, required this.scan});
  final String keyName;
  final ScanRecord scan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return IconButton(
      key: Key('scan.compare.delete.$keyName'),
      tooltip: l10n.scanDeleteAction,
      icon: const Icon(Icons.delete_outline),
      onPressed: () => confirmAndDeleteScan(context, ref, scan),
    );
  }
}

/// Which pair the compare screen opens with (`/photos/compare?mode=...`).
enum ScanCompareStart {
  /// The newest scan against the first one (the baseline).
  baseline,

  /// The newest scan against the one before it.
  previous;

  /// Unknown or missing names open on the baseline pair.
  static ScanCompareStart parse(String? name) =>
      name == 'previous' ? ScanCompareStart.previous : ScanCompareStart.baseline;
}

class ScanCompareScreen extends ConsumerWidget {
  const ScanCompareScreen({super.key, this.start = ScanCompareStart.baseline});

  final ScanCompareStart start;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final access = ref.watch(scanAccessProvider);
    if (access != ScanAccess.allowed) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.scanCompareTitle)),
        body: ScanGateView(access: access),
      );
    }
    final history = ref.watch(scanHistoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scanCompareTitle)),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) {
          debugPrint('scan: history failed to load: $e\n$st');
          return Center(child: Text(l10n.commonSomethingWentWrong));
        },
        data: (scans) => scans.length < 2
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.scanCompareNeedTwo,
                        key: const Key('scan.compare.needTwo'),
                        textAlign: TextAlign.center,
                      ),
                      if (scans.length == 1) ...[
                        // Only the baseline exists: say so and offer the
                        // second scan (C16).
                        const SizedBox(height: 8),
                        Text(
                          l10n.bodyScanCompareBaselineOnly,
                          key: const Key('scan.compare.baselineOnly'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        FilledButton(
                          key: const Key('scan.compare.takeSecond'),
                          style: FilledButton.styleFrom(
                              minimumSize: const Size(48, 48)),
                          onPressed: () => context.push('/body-scan'),
                          child: Text(l10n.bodyScanCompareTakeSecond),
                        ),
                        _DeleteScanButton(
                            keyName: 'single', scan: scans.first),
                      ],
                    ],
                  ),
                ),
              )
            : _CompareBody(scans: scans, start: start),
      ),
    );
  }
}

class _CompareBody extends ConsumerStatefulWidget {
  const _CompareBody({required this.scans, required this.start});
  final List<ScanRecord> scans; // newest first
  final ScanCompareStart start;

  @override
  ConsumerState<_CompareBody> createState() => _CompareBodyState();
}

class _CompareBodyState extends ConsumerState<_CompareBody> {
  late String _earlierId;
  late String _laterId;
  ScanPose _pose = ScanPose.front;
  ScanCompareMode _mode = ScanCompareMode.sideBySide;
  double _slider = 0.5;
  double _ghost = 0.5;

  @override
  void initState() {
    super.initState();
    // Default: the newest scan against the oldest one (the baseline); the
    // `previous` start picks the scan just before the newest instead.
    _laterId = widget.scans.first.id;
    _earlierId = widget.start == ScanCompareStart.previous
        ? widget.scans[1].id
        : widget.scans.last.id;
  }

  ScanRecord? _byId(String id) {
    for (final s in widget.scans) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final earlier = _byId(_earlierId) ?? widget.scans.last;
    final later = _byId(_laterId) ?? widget.scans.first;
    final eShot = earlier.shots[_pose];
    final lShot = later.shots[_pose];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: _ScanPicker(
                keyName: 'earlier',
                label: l10n.scanCompareEarlier,
                value: earlier.id,
                scans: widget.scans,
                onChanged: (id) => setState(() => _earlierId = id),
              ),
            ),
            _DeleteScanButton(keyName: 'earlier', scan: earlier),
            const SizedBox(width: 4),
            Expanded(
              child: _ScanPicker(
                keyName: 'later',
                label: l10n.scanCompareLatest,
                value: later.id,
                scans: widget.scans,
                onChanged: (id) => setState(() => _laterId = id),
              ),
            ),
            _DeleteScanButton(keyName: 'later', scan: later),
          ],
        ),
        const SizedBox(height: 12),
        SegmentedButton<ScanPose>(
          key: const Key('scan.compare.poses'),
          segments: [
            for (final p in ScanPose.ordered)
              ButtonSegment(value: p, label: Text(poseLabel(l10n, p))),
          ],
          selected: {_pose},
          onSelectionChanged: (s) => setState(() => _pose = s.first),
        ),
        const SizedBox(height: 8),
        SegmentedButton<ScanCompareMode>(
          key: const Key('scan.compare.modes'),
          segments: [
            ButtonSegment(
                value: ScanCompareMode.sideBySide,
                label: Text(l10n.scanCompareModeSideBySide)),
            ButtonSegment(
                value: ScanCompareMode.slider,
                label: Text(l10n.scanCompareModeSlider)),
            ButtonSegment(
                value: ScanCompareMode.ghost,
                label: Text(l10n.scanCompareModeGhost)),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        const SizedBox(height: 16),
        if (eShot == null || lShot == null)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.scanCompareMissingPose,
              key: const Key('scan.compare.missingPose'),
              textAlign: TextAlign.center,
            ),
          )
        else
          _CompareView(
            earlier: eShot,
            later: lShot,
            mode: _mode,
            slider: _slider,
            ghost: _ghost,
            onSlider: (v) => setState(() => _slider = v),
            onGhost: (v) => setState(() => _ghost = v),
            earlierDate: earlier.createdAt,
            laterDate: later.createdAt,
          ),
        const SizedBox(height: 12),
        Text(
          l10n.scanVisualOnly,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ScanPicker extends StatelessWidget {
  const _ScanPicker({
    required this.keyName,
    required this.label,
    required this.value,
    required this.scans,
    required this.onChanged,
  });

  final String keyName;
  final String label;
  final String value;
  final List<ScanRecord> scans;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fmt = DateFormat.yMMMd(l10n.localeName);
    return DropdownButtonFormField<String>(
      key: Key('scan.compare.pick.$keyName'),
      value: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final s in scans)
          DropdownMenuItem(
            value: s.id,
            child: Text(l10n.scanScanLabel(fmt.format(s.createdAt)),
                overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _CompareView extends StatelessWidget {
  const _CompareView({
    required this.earlier,
    required this.later,
    required this.mode,
    required this.slider,
    required this.ghost,
    required this.onSlider,
    required this.onGhost,
    required this.earlierDate,
    required this.laterDate,
  });

  final ScanShot earlier;
  final ScanShot later;
  final ScanCompareMode mode;
  final double slider;
  final double ghost;
  final ValueChanged<double> onSlider;
  final ValueChanged<double> onGhost;
  final DateTime earlierDate;
  final DateTime laterDate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = ScanAlignmentView.compute(later, earlier);
    final fmt = DateFormat.yMMMd(l10n.localeName);

    Widget framed(Widget child) => AspectRatio(
          aspectRatio: kScanDisplayAspect,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ColoredBox(color: Colors.black12, child: child),
          ),
        );

    final earlierImage = _AlignedImage(
      photoId: earlier.photoId,
      transform: view.transform,
    );
    final laterImage = _AlignedImage(photoId: later.photoId);

    final Widget body = switch (mode) {
      ScanCompareMode.sideBySide => Row(
          key: const Key('scan.compare.sideBySide'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(children: [
                framed(earlierImage),
                const SizedBox(height: 4),
                Text('${l10n.scanCompareEarlier} · ${fmt.format(earlierDate)}',
                    style: Theme.of(context).textTheme.labelSmall),
              ]),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(children: [
                framed(laterImage),
                const SizedBox(height: 4),
                Text('${l10n.scanCompareLatest} · ${fmt.format(laterDate)}',
                    style: Theme.of(context).textTheme.labelSmall),
              ]),
            ),
          ],
        ),
      ScanCompareMode.slider => Column(
          key: const Key('scan.compare.slider'),
          children: [
            framed(Stack(
              fit: StackFit.expand,
              children: [
                laterImage,
                // The earlier photo covers the left `slider` share of the frame.
                ClipRect(
                  clipper: _LeftShareClipper(slider),
                  child: earlierImage,
                ),
                Align(
                  alignment: Alignment(slider * 2 - 1, 0),
                  child: Container(width: 2, color: Colors.white),
                ),
              ],
            )),
            Semantics(
              label: l10n.scanCompareSliderSemantics,
              child: Slider(
                key: const Key('scan.compare.sliderControl'),
                value: slider,
                onChanged: onSlider,
              ),
            ),
          ],
        ),
      ScanCompareMode.ghost => Column(
          key: const Key('scan.compare.ghost'),
          children: [
            framed(Stack(
              fit: StackFit.expand,
              children: [
                laterImage,
                Opacity(opacity: ghost, child: earlierImage),
              ],
            )),
            Semantics(
              label: l10n.scanCompareOpacity,
              child: Slider(
                key: const Key('scan.compare.ghostControl'),
                value: ghost,
                onChanged: onGhost,
              ),
            ),
          ],
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        body,
        const SizedBox(height: 8),
        Text(
          view.aligned ? l10n.scanCompareAligned : l10n.scanCompareUnaligned,
          key: Key(view.aligned
              ? 'scan.compare.alignedNote'
              : 'scan.compare.unalignedNote'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _LeftShareClipper extends CustomClipper<Rect> {
  _LeftShareClipper(this.share);
  final double share;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * share, size.height);

  @override
  bool shouldReclip(_LeftShareClipper old) => old.share != share;
}

/// One photo, optionally moved by an alignment transform. The transform works
/// in the isotropic display space of [kScanDisplayAspect] (height = 1), so the
/// pixel matrix is `translate(H*t) * rotate * scale` on a box of height H.
class _AlignedImage extends ConsumerWidget {
  const _AlignedImage({required this.photoId, this.transform});

  final String photoId;
  final SimilarityTransform? transform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final bytes = ref.watch(scanShotBytesProvider(photoId));
    return bytes.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _missing(l10n),
      data: (data) {
        if (data == null) return _missing(l10n);
        final image = PhotoBitmap(bytes: data);
        final t = transform;
        if (t == null) return image;
        return LayoutBuilder(builder: (context, c) {
          final h = c.maxHeight;
          final m = Matrix4.identity()
            ..translate(h * t.tx, h * t.ty)
            ..rotateZ(t.rotation)
            ..scale(t.scale, t.scale);
          // Guard against a degenerate matrix reaching the painter.
          if (!t.scale.isFinite || !h.isFinite || math.max(h, 0) == 0) {
            return image;
          }
          return Transform(
            transform: m,
            alignment: Alignment.topLeft,
            child: SizedBox(width: c.maxWidth, height: h, child: image),
          );
        });
      },
    );
  }

  Widget _missing(AppLocalizations l10n) => Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(l10n.scanShotMissing,
              key: const Key('scan.compare.shotMissing'),
              textAlign: TextAlign.center),
        ),
      );
}
