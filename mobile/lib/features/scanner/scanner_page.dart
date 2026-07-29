import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_palette.dart';
import '../../shared/widgets/glass.dart';
import '../equipment/data/equipment_models.dart';
import '../visual_equipment/data/live_recognition.dart';
import '../visual_equipment/data/recognition_history.dart';
import '../visual_equipment/data/visual_equipment_match.dart';
import '../visual_equipment/state/live_equipment_providers.dart';
import '../visual_equipment/state/recognition_history_providers.dart';
import '../visual_equipment/state/visual_equipment_providers.dart';
import '../visual_equipment/widgets/live_equipment_preview.dart';

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

  /// Distinguishes "you haven't tried yet" from "we looked and found
  /// nothing" — the two used to render the same hint card.
  bool _attempted = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Every confident identification is remembered, whatever found it.
  void _remember(String equipmentId, double confidence,
      RecognitionSource source) {
    unawaited(
      ref.read(recognitionHistoryRepositoryProvider).record(
            RecognitionEntry(
              equipmentId: equipmentId,
              recognisedAt: DateTime.now(),
              confidence: confidence,
              source: source,
            ),
          ),
    );
  }

  /// Background QR watcher — fires only for our own stickers.
  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final result = ScanResult.tryParse(capture.barcodes.firstOrNull?.rawValue);
    if (result == null) return; // not ours — keep watching quietly
    _handling = true;
    await _controller.stop();
    // A QR code names the machine exactly, so it is recorded at full
    // confidence rather than a model score.
    _remember(result.equipmentId, 1, RecognitionSource.qr);
    if (!mounted) return;
    await context.push('/equipment/${result.equipmentId}');
    if (!mounted) return;
    _handling = false;
    await _controller.start();
  }

  /// Live mode and the QR viewfinder both want the camera, and only one can
  /// hold it. Stop the QR controller before handing the camera over, and
  /// restart it when live mode is switched off.
  Future<void> _setLiveMode(bool on) async {
    if (on) {
      await _controller.stop();
    }
    ref.read(liveModeEnabledProvider.notifier).state = on;
    if (!on) {
      // The live service releases the camera in its own stop(); give it the
      // frame to finish before the QR scanner grabs the device again.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      await _controller.start();
    }
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
      setState(() => _attempted = true);
      await ref
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath(picked.path);
      final top = ref
          .read(visualEquipmentControllerProvider)
          .valueOrNull
          ?.firstOrNull;
      if (top != null) {
        _remember(top.equipmentId, top.confidence, RecognitionSource.photo);
      }
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
    final liveOn = ref.watch(liveModeEnabledProvider);
    final live = ref.watch(liveRecognitionProvider).valueOrNull;
    // Record settled live readings. The repository's 5-minute dedup keeps a
    // camera held on one machine from writing a row per frame.
    ref.listen<AsyncValue<LiveRecognition?>>(liveRecognitionProvider,
        (prev, next) {
      final r = next.valueOrNull;
      if (r == null) return;
      _remember(r.equipmentId, r.confidence, RecognitionSource.live);
    });
    return FrostedScaffold(
      appBar: GlassAppBar(
        title: 'Scan',
        actions: [
          // Live mode is opt-in: a continuous camera stream is the most
          // battery-expensive thing here.
          Row(
            children: [
              Text('Live', style: theme.textTheme.labelLarge),
              Switch(
                key: const Key('scan-live-toggle'),
                value: liveOn,
                onChanged: _setLiveMode,
              ),
            ],
          ),
        ],
      ),
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
                    if (liveOn)
                      const LiveEquipmentPreview()
                    else
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
                // The app theme gives buttons minimumSize Size.fromHeight(54),
                // i.e. minWidth == infinity. In a Row's non-flex slot the
                // width constraint is unbounded, so an unwrapped button forces
                // an infinite width and the whole page fails to lay out
                // (blank screen, no red error). Always bound button width
                // outside Expanded.
                SizedBox(
                  width: 56,
                  child: OutlinedButton(
                    key: const Key('scan-recognise-gallery'),
                    onPressed: () => _recognise(ImageSource.gallery),
                    child: const Icon(Icons.photo_library_outlined),
                  ),
                ),
              ],
            ),
            if (liveOn) ...[
              const SizedBox(height: 14),
              _LiveCard(recognition: live),
            ],
            const SizedBox(height: 14),
            matches.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => GlassCard(
                tint: theme.colorScheme.error,
                child: Text('Recognition failed: $e'),
              ),
              data: (list) => list.isEmpty
                  ? _HintCard(theme: theme, noMatch: _attempted)
                  : _Matches(matches: list),
            ),
          ],
        ),
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.theme, this.noMatch = false});
  final ThemeData theme;

  /// True once a photo has been classified with no confident match, so the
  /// copy stops reading like the user never pressed the button.
  final bool noMatch;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            noMatch
                ? "Couldn't tell what that is"
                : 'Point at a machine and tap Recognise',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            noMatch
                ? "Try filling the frame with one machine, straight on, and "
                    "avoid people or clutter in the shot."
                : "We identify the equipment on-device and pull up exercises "
                    "tuned to your intake and past injuries. Equipment QR "
                    "stickers are picked up automatically while the camera "
                    "is open.",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live-mode readout. Shows what the camera has settled on, how much of the
/// vote agreed, and a way straight into the exercises.
class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.recognition});
  final LiveRecognition? recognition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = recognition;
    if (r == null) {
      return GlassCard(
        key: const Key('scan-live-searching'),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Looking… hold the camera on one machine',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }
    return GlassCard(
      key: const Key('scan-live-result'),
      onTap: () => context.push('/equipment/${r.equipmentId}'),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.equipmentId.replaceAll('_', ' '),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  '${(r.confidence * 100).toStringAsFixed(0)}% · '
                  '${(r.agreement * 100).toStringAsFixed(0)}% of frames agree',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
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
