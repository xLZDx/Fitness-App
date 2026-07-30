import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

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
      appBar: GlassAppBar(title: AppLocalizations.of(context).visualequipmentRecogniseEquipment),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          GlassCard(
            child: Text(
              AppLocalizations.of(context).visualequipmentUseThisWhenTheGymHasn,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _capture(context, ref,
                      source: ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(AppLocalizations.of(context).visualequipmentTakePhoto),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _capture(context, ref,
                      source: ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(AppLocalizations.of(context).visualequipmentPickPhoto),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          matches.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => GlassCard(
              tint: theme.colorScheme.error,
              child: Text(AppLocalizations.of(context).visualequipmentCouldNotClassify(e)),
            ),
            data: (list) {
              if (list.isEmpty) {
                return const SizedBox.shrink();
              }
              return Column(
                children: [
                  Text(
                    AppLocalizations.of(context).scannerBestMatches,
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

  /// Pick an image (camera or gallery) and run it through the on-device
  /// classifier. Image-picker returns an `XFile`; we read the bytes and
  /// hand them to the controller, which routes through ML Kit.
  Future<void> _capture(
    BuildContext context,
    WidgetRef ref, {
    required ImageSource source,
  }) async {
    final picker = ImagePicker();
    try {
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        imageQuality: 88,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      await ref
          .read(visualEquipmentControllerProvider.notifier)
          .classifyBytes(bytes);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).scannerCouldNotCapture(e))),
      );
    }
  }
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
                  AppLocalizations.of(context).scannerConfidence((match.confidence * 100).toStringAsFixed(0)),
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
