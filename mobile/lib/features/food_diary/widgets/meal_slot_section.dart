import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../data/food_entry.dart';
import 'food_format.dart';
import 'source_badge.dart';

/// One meal slot of the day: heading with the slot total, its entries (tap to
/// edit, delete button) and an "Add to <slot>" button. An empty slot is a calm
/// one-line hint, never a gap to be filled.
class MealSlotSection extends StatelessWidget {
  const MealSlotSection({
    super.key,
    required this.slot,
    required this.entries,
    required this.onAdd,
    required this.onOpen,
    required this.onDelete,
  });

  final MealSlot slot;
  final List<FoodEntry> entries;
  final VoidCallback onAdd;
  final ValueChanged<FoodEntry> onOpen;
  final ValueChanged<FoodEntry> onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final name = slotLabel(l10n, slot);
    final kcal = entries.fold<double>(0, (s, e) => s + e.totals.kcal.mid);
    return Column(
      key: Key('diary.slot.${slot.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(name, style: theme.textTheme.titleMedium),
              ),
            ),
            if (entries.isNotEmpty)
              Flexible(
                child: Text(l10n.foodUnitKcal(fmtInt(context, kcal)),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium),
              ),
            IconButton(
              key: Key('diary.add.${slot.name}'),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              tooltip: l10n.foodDiarySlotAdd(name),
              onPressed: onAdd,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(l10n.foodDiarySlotEmpty, style: theme.textTheme.bodySmall),
          ),
        for (final e in entries)
          ListTile(
            key: Key('diary.entry.${e.id}'),
            minVerticalPadding: 12,
            contentPadding: EdgeInsets.zero,
            title: Text(e.name.isEmpty ? e.items.first.name : e.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: SourceBadge(source: e.items.first.source)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(confidenceLabel(l10n, e.confidence),
                          style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
                Text(l10n.foodUnitKcal(fmtInt(context, e.totals.kcal.mid))),
              ],
            ),
            trailing: IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              tooltip: l10n.foodDiaryDeleteEntry,
              onPressed: () => onDelete(e),
              icon: const Icon(Icons.delete_outline),
            ),
            onTap: () => onOpen(e),
          ),
      ],
    );
  }
}
