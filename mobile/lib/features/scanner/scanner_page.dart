import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../shared/widgets/glass.dart';

class ScannerPage extends StatelessWidget {
  const ScannerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FrostedScaffold(
      appBar: const GlassAppBar(title: 'Scan'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 96, 20, 120),
        children: [
            GlassCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(36),
                      gradient: const LinearGradient(
                        colors: [
                          AppPalette.auroraViolet,
                          AppPalette.auroraBlue,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              AppPalette.auroraBlue.withValues(alpha: 0.45),
                          blurRadius: 40,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.qr_code_2,
                        color: Colors.white, size: 84),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Camera scanner coming up',
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We will wire up live camera + QR detection in the next milestone. Flow: scan → equipment detail → personalized recommendations.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GlassCard(
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        colors: [
                          AppPalette.auroraPeach,
                          AppPalette.auroraPink,
                        ],
                      ),
                    ),
                    child: const Icon(Icons.history_rounded,
                        color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Recent scans', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          'Your scan history will appear here.',
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
        ],
      ),
    );
  }
}
