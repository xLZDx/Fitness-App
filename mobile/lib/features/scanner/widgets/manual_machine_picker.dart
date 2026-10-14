import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../equipment/data/catalog_labels.dart';
import '../../equipment/data/equipment_alias_index.dart';
import '../../equipment/data/equipment_models.dart';
import '../../equipment/state/equipment_providers.dart';
import 'machine_thumb.dart';

/// "Not it -- choose manually": every catalogue machine, searchable, so a
/// wrong scan always has a way out.
///
/// The model names the right machine as its top answer only about half the
/// time (16/33 on the labelled photos), and in the top 4 about 60%. The
/// candidates on the Scan screen are therefore a confirmation surface, and
/// this sheet is the exit for the cases where the machine is not listed.
///
/// Returns the picked `equipmentId` through `Navigator.pop`; the caller
/// records it (source manual) and navigates. A flat, name-sorted list; the
/// search matches the localised display name AND any alias of the machine
/// (en + ru) through [EquipmentAliasIndex.idsMatching].
Future<String?> showManualMachinePicker(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const ManualMachinePicker(),
    );

class ManualMachinePicker extends ConsumerStatefulWidget {
  const ManualMachinePicker({super.key});

  @override
  ConsumerState<ManualMachinePicker> createState() =>
      _ManualMachinePickerState();
}

class _ManualMachinePickerState extends ConsumerState<ManualMachinePicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final List<EquipmentItem> all =
        ref.watch(equipmentListProvider).valueOrNull ?? const <EquipmentItem>[];
    // While the alias asset is still loading the name match alone is used.
    final EquipmentAliasIndex? aliases =
        ref.watch(equipmentAliasIndexProvider).valueOrNull;

    final String q = EquipmentAliasIndex.normalise(_query);
    final Set<String> aliasHits =
        aliases == null ? const <String>{} : aliases.idsMatching(_query);
    final List<EquipmentItem> shown = <EquipmentItem>[
      for (final eq in all)
        if (q.isEmpty ||
            EquipmentAliasIndex.normalise(eq.name).contains(q) ||
            aliasHits.contains(eq.id))
          eq,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return SizedBox(
      key: const Key('scan-manual-picker'),
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l10n.scannerManualPickerTitle,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                key: const Key('scan-manual-search'),
                autofocus: false,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: l10n.scannerManualPickerSearchHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? Center(
                      child: Text(
                        l10n.scannerManualPickerNoResults,
                        key: const Key('scan-manual-empty'),
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  : ListView.builder(
                      key: const Key('scan-manual-list'),
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final eq = shown[i];
                        return ListTile(
                          key: Key('scan-manual-pick-${eq.id}'),
                          leading: MachineThumb(equipmentId: eq.id, size: 48),
                          title: Text(eq.name),
                          subtitle: Text(CatalogLabels.category(l10n, eq.category)),
                          onTap: () => Navigator.of(context).pop(eq.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
