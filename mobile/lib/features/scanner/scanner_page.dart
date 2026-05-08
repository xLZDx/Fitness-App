import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_palette.dart';
import '../../shared/widgets/glass.dart';
import '../equipment/data/equipment_models.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
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

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    final result = ScanResult.tryParse(raw);
    if (result == null) {
      // Not one of ours — ignore quietly so the user can keep aiming.
      return;
    }
    _handling = true;
    await _controller.stop();
    if (!mounted) return;
    context.go('/equipment/${result.equipmentId}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FrostedScaffold(
      appBar: const GlassAppBar(title: 'Scan'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 88, 20, 110),
          child: Column(
            children: [
              Expanded(
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
                      // Subtle scan-guide frame.
                      Center(
                        child: Container(
                          width: 220,
                          height: 220,
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
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Point at any equipment QR',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "We'll pull up exercises tuned to your profile and any past injuries.",
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(colors: [
                  AppPalette.auroraViolet,
                  AppPalette.auroraBlue,
                ]),
              ),
              child: const Icon(Icons.camera_alt_outlined,
                  color: Colors.white, size: 48),
            ),
            const SizedBox(height: 16),
            Text(
              'Camera unavailable',
              style: theme.textTheme.titleLarge
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              error.errorCode.name,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
