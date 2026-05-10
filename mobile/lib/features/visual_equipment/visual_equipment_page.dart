import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/glass.dart';
import 'data/visual_equipment_match.dart';
import 'state/visual_equipment_providers.dart';

/// "Photo recognise equipment" page (TX.2).
///
/// Wires the camera capture (or a placeholder) into the on-device
/// classifier. Top-3 matches surface as tappable cards that route to
/// `/equipment/{id}`.
class VisualEquipmentPage extends ConsumerWidget {
  const VisualEquipmentPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final matches = ref.watch(visualEquipmentControllerProvider);
    return FrostedScaffold(
      appBar: const GlassAppBar(title: 'Recognise equipment'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          GlassCard(
            child: Text(
              "Use this when the gym hasn't put up QR stickers yet — "
              "snap a photo of the machine, we'll guess the model on-"
              "device. Nothing leaves your phone.",
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => ref
                .read(visualEquipmentControllerProvider.notifier)
                .classifyBytes(_demoImageBytes()),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Take photo'),
          ),
          const SizedBox(height: 16),
          matches.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => GlassCard(
              tint: theme.colorScheme.error,
              child: Text('Could not classify: $e'),
            ),
            data: (list) {
              if (list.isEmpty) {
                return const SizedBox.shrink();
              }
              return Column(
                children: [
                  Text(
                    'Best matches',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  for (final m in list) ...[
                    _MatchCard(match: m),
                    const SizedBox(height: 8),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Placeholder image bytes for the "take photo" flow before the real
  /// camera is plumbed. Length is the only thing the mock classifier
  /// reads, so this gives a deterministic preview.
  Uint8List _demoImageBytes() => Uint8List.fromList(List.filled(48, 0));
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match});
  final VisualMatch match;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      onTap: () =>
          GoRouter.of(context).go('/equipment/${match.equipmentId}'),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  match.equipmentId.replaceAll('_', ' '),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${(match.confidence * 100).toStringAsFixed(0)}% confidence',
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
    );
  }
}
