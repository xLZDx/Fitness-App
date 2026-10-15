import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../nutrition_plan/state/weight_providers.dart';
import 'data/food_entry.dart';
import 'data/food_source.dart';
import 'data/portion_math.dart';
import 'food_detail_sheet.dart';
import 'state/diary_providers.dart';
import 'widgets/food_format.dart';
import 'widgets/source_badge.dart';

/// `/nutrition/add/search?day=&slot=&saved=1`: bundled generic foods answer
/// while typing (offline); packaged/USDA results come only after an explicit
/// submit, never for fewer than 3 characters (see [FoodSearchController]).
/// `saved=1` lists the user's saved foods.
class FoodSearchPage extends ConsumerStatefulWidget {
  const FoodSearchPage({super.key, this.day, this.slot, this.savedOnly = false});

  final String? day;
  final MealSlot? slot;
  final bool savedOnly;

  @override
  ConsumerState<FoodSearchPage> createState() => _FoodSearchPageState();
}

class _FoodSearchPageState extends ConsumerState<FoodSearchPage> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String get _lang =>
      Localizations.localeOf(context).languageCode == 'ru' ? 'ru' : 'en';

  Future<void> _pick({
    required String foodRef,
    required String name,
    required Per100g per100g,
    required FoodSource source,
    double? servingG,
  }) async {
    final now = ref.read(nutritionClockProvider)();
    final day = (widget.day != null &&
            RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(widget.day!))
        ? widget.day!
        : dayKeyOf(now);
    final shortName =
        name.length > FoodItem.maxNameLength ? name.substring(0, 80) : name;
    final entry = buildEntry(
      id: newEntryId(now),
      day: day,
      slot: widget.slot ?? defaultSlotFor(now),
      loggedAt: now,
      name: shortName,
      source: EntrySource.search,
      confidence: EntryConfidence.high,
      items: [
        FoodItem(
          foodRef: foodRef,
          name: shortName,
          grams: MacroRange.exact(servingG ?? quickLogGrams),
          per100g: per100g,
          matchQuality: MatchQuality.exact,
          source: source,
        ),
      ],
    );
    final saved = await showFoodDetailSheet(context, entry);
    if (saved && mounted) context.go('/nutrition/diary');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(foodSearchControllerProvider(_lang));
    final ctrl = ref.read(foodSearchControllerProvider(_lang).notifier);
    final saved = ref.watch(savedFoodsProvider).valueOrNull ?? const [];
    final q = state.query.toLowerCase();
    final savedShown = [
      for (final s in saved)
        if (widget.savedOnly || (q.length >= 3 && s.name.toLowerCase().contains(q))) s,
    ];

    String? message;
    switch (state.phase) {
      case SearchPhase.tooShort:
        message = l10n.foodSearchTooShort;
      case SearchPhase.loading:
        message = l10n.foodSearchLoading;
      case SearchPhase.empty:
        message = savedShown.isEmpty ? l10n.foodSearchEmpty : null;
      case SearchPhase.notAvailable:
        message = l10n.foodSearchNotAvailable;
      case SearchPhase.error:
        message = l10n.foodSearchError;
      case SearchPhase.results:
        message = state.rateLimited ? l10n.foodSearchRateLimited : null;
      case SearchPhase.idle:
        message = null;
    }

    Widget heading(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Semantics(header: true, child: Text(t, style: theme.textTheme.titleSmall)),
        );

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          child: Text(widget.savedOnly ? l10n.foodAddSaved : l10n.foodSearchTitle),
        ),
      ),
      body: SafeArea(
        child: ListView(
          children: [
            if (!widget.savedOnly)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('search.field'),
                        controller: _c,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        decoration:
                            InputDecoration(labelText: l10n.foodSearchHint),
                        onChanged: ctrl.onChanged,
                        onSubmitted: ctrl.submit,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      key: const Key('search.submit'),
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      tooltip: l10n.foodSearchSubmit,
                      onPressed: () => ctrl.submit(_c.text),
                      icon: const Icon(Icons.search),
                    ),
                  ],
                ),
              ),
            if (message != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(message, key: const Key('search.message')),
                ),
              ),
            if (savedShown.isNotEmpty) ...[
              heading(l10n.foodSearchSavedHeading),
              for (final s in savedShown)
                _tile(
                  context,
                  key: 'search.saved.${s.id}',
                  title: s.name,
                  per: s.per100g,
                  source: FoodSource.user,
                  onTap: () => _pick(
                    foodRef: 'user:${s.id}',
                    name: s.name,
                    per100g: s.per100g,
                    source: FoodSource.user,
                    servingG: s.servingG,
                  ),
                ),
            ],
            if (state.local.isNotEmpty) ...[
              heading(l10n.foodSearchGenericHeading),
              for (final h in state.local)
                _tile(
                  context,
                  key: 'search.gen.${h.food.id}',
                  title: h.food.displayName(_lang),
                  per: Per100g(
                    kcal: h.food.per100g.kcal,
                    proteinG: h.food.per100g.proteinG,
                    carbsG: h.food.per100g.carbsG,
                    fatG: h.food.per100g.fatG,
                  ),
                  source: FoodSource.usda,
                  onTap: () => _pick(
                    foodRef: h.food.id,
                    name: h.food.displayName(_lang),
                    per100g: Per100g(
                      kcal: h.food.per100g.kcal,
                      proteinG: h.food.per100g.proteinG,
                      carbsG: h.food.per100g.carbsG,
                      fatG: h.food.per100g.fatG,
                    ),
                    source: FoodSource.usda,
                  ),
                ),
            ],
            if (state.remote.isNotEmpty) ...[
              heading(l10n.foodSearchPackagedHeading),
              for (final r in state.remote)
                _tile(
                  context,
                  key: 'search.remote.${r.foodRef}',
                  title: r.brand == null ? r.name : '${r.name} - ${r.brand}',
                  per: r.per100g,
                  source: r.source,
                  note: r.complete ? null : l10n.foodSearchPartialData,
                  onTap: () => _pick(
                    foodRef: r.foodRef,
                    name: r.name,
                    per100g: r.per100g,
                    source: r.source,
                    servingG: r.servingG,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required String key,
    required String title,
    required Per100g per,
    required FoodSource source,
    required VoidCallback onTap,
    String? note,
  }) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      key: Key(key),
      minTileHeight: 56,
      title: Text(title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${l10n.foodUnitKcal(fmtInt(context, per.kcal))} ${l10n.foodSearchPer100}'),
          if (note != null) Text(note),
          SourceBadge(source: source),
        ],
      ),
      onTap: onTap,
    );
  }
}
