import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/glass.dart';

/// Celebrates the first time the user uses the injury-aware exercise
/// filter — the app's strongest moat feature — and reframes it as a
/// safety-first promise that needs donor support to keep free.
class InjuryFilterCelebrationModal extends StatelessWidget {
  const InjuryFilterCelebrationModal({super.key});

  static Future<void> show(BuildContext context) async {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: SafeArea(
          top: false,
          child: InjuryFilterCelebrationModal(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(colors: [
                AppPalette.auroraTeal,
                AppPalette.auroraLime,
              ]),
            ),
            child: const Icon(Icons.shield_outlined,
                color: Colors.white, size: 30),
          ),
          const SizedBox(height: 14),
          Text(
            'You just dodged a flare-up.',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            "Injury-aware filtering is the safety promise we pin our "
            "mission to — every exercise is screened against your "
            "logged conditions before it surfaces. It will stay free, "
            "always. If you can, help keep it that way.",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.75),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Got it'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    GoRouter.of(context).go('/subscription');
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Help keep it free'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
