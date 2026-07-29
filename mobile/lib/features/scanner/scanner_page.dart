import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_palette.dart';
import '../../shared/widgets/glass.dart';
import '../equipment/data/equipment_models.dart';
import '../visual_equipment/data/visual_equipment_match.dart';
import '../visual_equipment/state/visual_equipment_providers.dart';

/// The Scan tab.
///
/// Primary job: **photograph a machine and recognise it** — the user
/// points the phone at any piece of equipment, taps Recognise, and we
/// classify it on-device, then route to the exercises tuned to their
/// intake + injuries.
///
/// Secondary job: QR. The same live viewfinder keeps watching for our
/// `fitness://equipment/<id>` stickers and jumps straight there when one
/// enters frame — no mode switch, no extra tap.
class ScannerPage extends ConsumerStatefulWidget {
  const ScannerPage({super.key});

  @override
  ConsumerState<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends ConsumerState<ScannerPage> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  bool _handling = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Background QR watcher — fires only for our own stickers.
  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final result = ScanResult.tryParse(capture.barcodes.firstOrNull?.rawValue);
    if (result == null) return; // not ours — keep watching quietly
    _handling = true;
    await _controller.stop();
    if (!mounted) return;
    await context.push('/equipment/${result.equipmentId}');
    if (!mounted) return;
    _handling = false;
    await _controller.start();
  }

  /// Primary action: take (or pick) a photo and classify the machine.
  Future<void> _recognise(ImageSource source) async {
    if (_handling) return;
    _handling = true;
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        imageQuality: 88,
      );
      if (picked == null) return;
      await ref
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath(picked.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not capture: $e')));
    } finally {
      _handling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matches = ref.watch(visualEquipmentControllerProvider);
    return FrostedScaffold(
      appBar: const GlassAppBar(title: 'Scan'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 88, 20, 110),
          children: [
            SizedBox(
              height: 300,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _controller,
                      onDetect: _onDetect,
                      errorBuilder: (context, error, child) =>
                          _CameraUnavailable(error: error),
                    ),
                    Center(
                      child: Container(
                        width: 220,
                        height: 200,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.85),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('scan-recognise-camera'),
                    onPressed: () => _recognise(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Recognise machine'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const Key('scan-recognise-gallery'),
                  onPressed: () => _recognise(ImageSource.gallery),
                  child: const Icon(Icons.photo_library_outlined),
                ),
              ],
            ),
            const SizedBox(height: 14),
            matches.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => GlassCard(
                tint: theme.colorScheme.error,
                child: Text('Could not recognise: $e'),
              ),
              data: (list) => list.isEmpty
                  ? _HintCard(theme: theme)
                  : _Matches(matches: list),
            ),
          ],
        ),
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Point at a machine and tap Recognise',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            "We identify the equipment on-device and pull up exercises tuned "
            "to your intake and past injuries. Equipment QR stickers are "
            "picked up automatically while the camera is open.",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
}

class _Matches extends StatelessWidget {
  const _Matches({required this.matches});
  final List<VisualMatch> matches;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Best matches',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        for (final m in matches) ...[
          GlassCard(
            onTap: () => context.push('/equipment/${m.equipmentId}'),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.equipmentId.replaceAll('_', ' '),
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${(m.confidence * 100).toStringAsFixed(0)}% confidence',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({required this.error});
  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: Colors.black.withValues(alpha: 0.65),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(colors: [
                  AppPalette.auroraViolet,
                  AppPalette.auroraBlue,
                ]),
              ),
              child: const Icon(Icons.camera_alt_outlined,
                  color: Colors.white, size: 36),
            ),
            const SizedBox(height: 14),
            Text(
              'Camera unavailable',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              '${error.errorCode.name} — you can still pick a photo from the '
              'gallery below.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
