import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/privacy/data_notice.dart';
import 'data/check_these.dart';
import 'data/food_entry.dart';
import 'data/portion_math.dart';
import 'state/diary_providers.dart';
import 'state/diary_repository.dart';
import 'widgets/check_these_chips.dart';
import 'widgets/food_format.dart';
import 'widgets/macro_bars.dart';
import 'widgets/portion_editor.dart';
import 'widgets/source_badge.dart';

/// The slot a meal most likely belongs to at [now].
MealSlot defaultSlotFor(DateTime now) {
  final h = now.hour;
  if (h >= 5 && h < 11) return MealSlot.breakfast;
  if (h >= 11 && h < 16) return MealSlot.lunch;
  if (h >= 17 && h < 22) return MealSlot.dinner;
  return MealSlot.snack;
}

/// Shows the add/edit sheet for [draft]; resolves true when the entry was
/// saved. A framework modal route: focus moves into it, semantics outside are
/// blocked and focus returns to the trigger on close (a11y F14).
Future<bool> showFoodDetailSheet(BuildContext context, FoodEntry draft) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FoodDetailSheet(draft: draft),
  );
  return saved ?? false;
}

class FoodDetailSheet extends ConsumerStatefulWidget {
  const FoodDetailSheet({super.key, required this.draft});

  final FoodEntry draft;

  @override
  ConsumerState<FoodDetailSheet> createState() => _FoodDetailSheetState();
}

class _FoodDetailSheetState extends ConsumerState<FoodDetailSheet> {
  late FoodEntry _entry = widget.draft;
  final FocusNode _headingFocus = FocusNode(debugLabel: 'detail.heading');
  bool _saving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _headingFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _headingFocus.dispose();
    super.dispose();
  }

  void _setGrams(int i, double g) =>
      setState(() => _entry = editItemGrams(_entry, i, g));

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _saving = true;
      _message = null;
    });
    final ok = await ensureDataNoticeAcknowledged(context, ref);
    if (!ok) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    final status = await ref.read(foodDiaryActionsProvider).saveEntry(_entry);
    if (!mounted) return;
    if (status == DiaryWriteStatus.saved) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = false;
        _message = l10n.foodDiaryWriteFailed;
      });
    }
  }

  Future<void> _saveFood() async {
    final l10n = AppLocalizations.of(context);
    final item = _entry.items.first;
    final ok = await ensureDataNoticeAcknowledged(context, ref);
    if (!ok || !mounted) return;
    final status = await ref.read(foodDiaryActionsProvider).saveFood(SavedFood(
          id: item.foodRef.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_'),
          name: item.name,
          per100g: item.per100g,
        ));
    if (!mounted) return;
    setState(() => _message = status == DiaryWriteStatus.saved
        ? l10n.foodDetailFoodSaved
        : l10n.foodDiaryWriteFailed);
  }

  Future<void> _resolve(CheckItem chip) async {
    final result = await showModalBottomSheet<FoodEntry>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ResolveSheet(entry: _entry, chip: chip),
    );
    if (result != null && mounted) setState(() => _entry = result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = _entry.totals;
    final hasEstimate = _entry.items.any((i) => i.source.isEstimate);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Focus(
            focusNode: _headingFocus,
            child: Semantics(
              header: true,
              child: Text(l10n.foodDetailTitle, style: theme.textTheme.titleLarge),
            ),
          ),
          const SizedBox(height: 4),
          Text(_entry.name.isEmpty ? _entry.items.first.name : _entry.name,
              style: theme.textTheme.titleMedium),
          Text(confidenceLabel(l10n, _entry.confidence),
              style: theme.textTheme.bodySmall),
          if (hasEstimate)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(l10n.foodDetailEstimateNote,
                  style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 12),
          Text(l10n.foodDetailSlot, style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final s in MealSlot.values)
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: ChoiceChip(
                    key: Key('detail.slot.${s.name}'),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    label: Text(slotLabel(l10n, s)),
                    selected: _entry.slot == s,
                    onSelected: (_) =>
                        setState(() => _entry = _entry.copyWith(slot: s)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(l10n.foodDetailItems, style: theme.textTheme.labelLarge),
          for (var i = 0; i < _entry.items.length; i++) ...[
            const SizedBox(height: 8),
            Text(_entry.items[i].name, style: theme.textTheme.titleSmall),
            SourceBadge(source: _entry.items[i].source),
            Text(
              l10n.foodDetailPer100(
                fmtInt(context, _entry.items[i].per100g.kcal),
                fmtGrams(context, _entry.items[i].per100g.proteinG),
                fmtGrams(context, _entry.items[i].per100g.carbsG),
                fmtGrams(context, _entry.items[i].per100g.fatG),
              ),
              style: theme.textTheme.bodySmall,
            ),
            PortionEditor(
              key: Key('detail.portion.$i'),
              grams: _entry.items[i].grams,
              onChanged: (g) => _setGrams(i, g),
            ),
          ],
          const SizedBox(height: 16),
          CheckTheseChips(items: _entry.checkThese, onTap: _resolve),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(
              l10n.foodDetailTotals(
                fmtInt(context, t.kcal.mid),
                fmtInt(context, t.kcal.low),
                fmtInt(context, t.kcal.high),
              ),
              style: theme.textTheme.titleSmall,
            ),
          ),
          MacroBars(totals: t),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(liveRegion: true, child: Text(_message!)),
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('detail.save'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            onPressed: _saving ? null : _save,
            child: Text(l10n.foodDetailSave),
          ),
          if (_entry.items.length == 1)
            TextButton(
              key: const Key('detail.saveFood'),
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _saving ? null : _saveFood,
              child: Text(l10n.foodDetailSaveFood),
            ),
        ],
      ),
    );
  }
}

/// Resolution of one chip: its help text, the oil choice for hidden
/// ingredients, and "Mark as checked". Pops the updated entry.
class _ResolveSheet extends ConsumerWidget {
  const _ResolveSheet({required this.entry, required this.chip});

  final FoodEntry entry;
  final CheckItem chip;

  FoodEntry _markDone() => entry.copyWith(
        checkThese: CheckThese.markResolved(entry.checkThese, chip.code),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final oil = chip.code == CheckCode.hiddenIngredients
        ? ref.watch(genericFoodTableProvider).valueOrNull?.search('olive oil',
            limit: 1)
        : null;
    final oilFood = oil == null || oil.isEmpty ? null : oil.first.food;

    String oilLabel(OilChoice c) => switch (c) {
          OilChoice.none => l10n.foodOilNone,
          OilChoice.teaspoon => l10n.foodOilTeaspoon,
          OilChoice.tablespoon => l10n.foodOilTablespoon,
        };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(checkTitle(l10n, chip.code),
                style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: 8),
          Text(checkHelp(l10n, chip.code)),
          const SizedBox(height: 16),
          if (oilFood != null)
            for (final c in OilChoice.values)
              OutlinedButton(
                key: Key('resolve.oil.${c.name}'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
                onPressed: () {
                  final updated = applyHiddenOil(
                    entry,
                    c,
                    oilFoodRef: oilFood.id,
                    oilName: oilFood.name,
                    oilPer100g: Per100g(
                      kcal: oilFood.per100g.kcal,
                      proteinG: oilFood.per100g.proteinG,
                      carbsG: oilFood.per100g.carbsG,
                      fatG: oilFood.per100g.fatG,
                    ),
                  );
                  Navigator.of(context).pop(updated ?? _markDone());
                },
                child: Text(oilLabel(c)),
              )
          else
            FilledButton(
              key: const Key('resolve.done'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              onPressed: () => Navigator.of(context).pop(_markDone()),
              child: Text(l10n.foodCheckMarkDone),
            ),
        ],
      ),
    );
  }
}
