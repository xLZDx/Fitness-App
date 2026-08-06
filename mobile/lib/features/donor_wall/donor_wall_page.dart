import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/glass.dart';
import 'data/donor_wall_entry.dart';
import 'state/donor_wall_providers.dart';

/// Public donor wall. Anyone can browse — opt-in is gated by an active
/// donation status (enforced server-side by `optInDonorWall`).
class DonorWallPage extends ConsumerWidget {
  const DonorWallPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entriesAsync = ref.watch(donorWallProvider);

    return FrostedScaffold(
      appBar:
          GlassAppBar(title: AppLocalizations.of(context).donorwallDonorWall),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    gradient: const LinearGradient(colors: [
                      AppPalette.auroraTeal,
                      AppPalette.auroraLime,
                    ]),
                  ),
                  child: const Icon(Icons.celebration_outlined,
                      color: AppSemanticColors.onGradientInk),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)
                            .donorwallMadePossibleByTheseDonors,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppLocalizations.of(context)
                            .donorwallAnyoneCanBrowseThisListDonors,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          entriesAsync.when(
            data: (list) => _DonorList(entries: list),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => GlassCard(
              tint: scheme.error,
              child: Text(
                AppLocalizations.of(context).donorwallCouldNotLoadWall(e),
                style:
                    theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: TextButton.icon(
              onPressed: () => GoRouter.of(context).push('/subscription'),
              icon: const Icon(Icons.favorite_outline, size: 18),
              label: Text(AppLocalizations.of(context).donorwallBecomeADonor),
            ),
          ),
        ],
      ),
    );
  }
}

class _DonorList extends StatelessWidget {
  const _DonorList({required this.entries});
  final List<DonorWallEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      final theme = Theme.of(context);
      return GlassCard(
        padding: const EdgeInsets.all(20),
        child: Text(
          AppLocalizations.of(context).donorwallBeTheFirstToOptIn,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.70),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final e in entries) ...[
          _DonorTile(entry: e),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _DonorTile extends StatelessWidget {
  const _DonorTile({required this.entry});
  final DonorWallEntry entry;

  IconData get _icon {
    if (entry.isLifetime) return Icons.workspace_premium_rounded;
    switch (entry.tier) {
      case 'sustainer':
        return Icons.auto_awesome_rounded;
      case 'champion':
        return Icons.emoji_events_outlined;
      default:
        return Icons.favorite_rounded;
    }
  }

  List<Color> get _gradient {
    if (entry.isLifetime) {
      return const [AppPalette.auroraPeach, AppPalette.auroraPink];
    }
    switch (entry.tier) {
      case 'sustainer':
        return const [AppPalette.auroraViolet, AppPalette.auroraBlue];
      case 'champion':
        return const [AppPalette.auroraPeach, AppPalette.auroraPink];
      default:
        return const [AppPalette.auroraTeal, AppPalette.auroraLime];
    }
  }

  String _label(AppLocalizations l10n) {
    if (entry.isLifetime) return l10n.donorwallLifetime;
    return entry.tier.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: LinearGradient(colors: _gradient),
            ),
            child:
                Icon(_icon, color: AppSemanticColors.onGradientInk, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.displayName,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white.withValues(alpha: 0.30),
                      ),
                      child: Text(
                        _label(l10n),
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
                if (entry.message != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '"${entry.message!}"',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: scheme.onSurface.withValues(alpha: 0.70),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
