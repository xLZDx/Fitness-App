import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/config/body_scan_flags.dart';
import '../nutrition_plan/data/nutrition_eligibility.dart';
import '../nutrition_plan/state/nutrition_providers.dart';
import '../nutrition_plan/state/weight_providers.dart' show nutritionClockProvider;
import 'data/food_entry.dart';
import 'food_detail_sheet.dart';
import 'state/diary_providers.dart';
import 'widgets/day_summary_ring.dart';
import 'widgets/meal_slot_section.dart';

/// `/nutrition/diary`: the day's food by meal slot with the day summary.
///
/// States (D-78): loading, error with retry, empty day (calm, no "below range"
/// colouring), AI-off note, hidden for `referProfessional`, and a pointer to
/// the nutrition profile while answers are missing.
class FoodDiaryPage extends ConsumerWidget {
  const FoodDiaryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final verdict = ref.watch(nutritionEligibilityProvider);
    return Scaffold(
      appBar: AppBar(
        title: Semantics(header: true, child: Text(l10n.foodDiaryTitle)),
      ),
      body: SafeArea(
        child: switch (verdict) {
          null => _Loading(label: l10n.foodDiaryLoading),
          Eligible() => const _DiaryBody(),
          ReferProfessional() => _Notice(
              title: l10n.foodDiaryHiddenTitle,
              body: l10n.foodDiaryHiddenBody,
            ),
          _ => _Notice(
              title: l10n.foodDiaryNeedsProfileTitle,
              body: l10n.foodDiaryNeedsProfileBody,
              actionLabel: l10n.foodDiaryNeedsProfileAction,
              onAction: () => context.push('/nutrition/profile'),
            ),
        },
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Center(
        child: Semantics(
          liveRegion: true,
          label: label,
          child: const CircularProgressIndicator(),
        ),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center),
              if (actionLabel != null) ...[
                const SizedBox(height: 16),
                FilledButton(
                  style:
                      FilledButton.styleFrom(minimumSize: const Size(48, 54)),
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      );
}

class _DiaryBody extends ConsumerWidget {
  const _DiaryBody();

  DateTime _parse(String day) => DateTime.tryParse(day) ?? DateTime.now();

  Future<void> _delete(
      BuildContext context, WidgetRef ref, FoodEntry e) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final actions = ref.read(foodDiaryActionsProvider);
    final status = await actions.deleteEntry(e.id);
    if (status != DiaryWriteStatus.saved) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.foodDiaryWriteFailed)));
      return;
    }
    messenger.showSnackBar(SnackBar(
      content: Text(l10n.foodDiaryEntryRemoved),
      action: SnackBarAction(
        label: l10n.foodDiaryUndo,
        onPressed: () => actions.saveEntry(e),
      ),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final day = ref.watch(selectedDiaryDayProvider);
    final entriesAsync = ref.watch(diaryDayEntriesProvider(day));
    final flags = ref.watch(bodyScanFlagsProvider);
    final today = dayKeyOf(ref.watch(nutritionClockProvider)());
    final date = _parse(day);

    void shift(int d) => ref.read(selectedDiaryDayProvider.notifier).state =
        dayKeyOf(date.add(Duration(days: d)));

    void add(MealSlot? slot) {
      final s = slot ?? defaultSlotFor(ref.read(nutritionClockProvider)());
      context.push('/nutrition/add?day=$day&slot=${s.name}');
    }

    return entriesAsync.when(
      loading: () => _Loading(label: l10n.foodDiaryLoading),
      error: (_, __) => _Notice(
        title: l10n.foodDiaryError,
        body: l10n.foodDiaryErrorBody,
        actionLabel: l10n.commonRetry,
        onAction: () => ref.invalidate(diaryDayEntriesProvider(day)),
      ),
      data: (entries) {
        final totals = ref.watch(dayTotalsProvider(day));
        final targets = ref.watch(dayTargetsProvider);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Row(
              children: [
                IconButton(
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  tooltip: l10n.foodDiaryPrevDay,
                  onPressed: () => shift(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: day == today
                        ? null
                        : () => ref
                            .read(selectedDiaryDayProvider.notifier)
                            .state = today,
                    child: Text(
                      day == today
                          ? l10n.foodDiaryToday
                          : DateFormat.yMMMEd(locale).format(date),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                IconButton(
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  tooltip: l10n.foodDiaryNextDay,
                  onPressed: day == today ? null : () => shift(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            if (totals != null)
              DaySummaryRing(
                totals: totals,
                targets: targets,
                hasEntries: entries.isNotEmpty,
              ),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    Semantics(
                      header: true,
                      child: Text(l10n.foodDiaryEmptyTitle,
                          style: theme.textTheme.titleMedium),
                    ),
                    const SizedBox(height: 4),
                    Text(l10n.foodDiaryEmptyBody, textAlign: TextAlign.center),
                  ],
                ),
              ),
            if (!flags.foodAi)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(l10n.foodDiaryAiOff, style: theme.textTheme.bodySmall),
              ),
            for (final slot in MealSlot.values)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: MealSlotSection(
                  slot: slot,
                  entries: [for (final e in entries) if (e.slot == slot) e],
                  onAdd: () => add(slot),
                  onOpen: (e) => showFoodDetailSheet(context, e),
                  onDelete: (e) => _delete(context, ref, e),
                ),
              ),
            const SizedBox(height: 16),
            TextButton.icon(
              key: const Key('diary.weightLink'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => context.push('/nutrition/weight'),
              icon: const Icon(Icons.monitor_weight_outlined),
              label: Text(l10n.foodDiaryWeightLink),
            ),
          ],
        );
      },
    );
  }
}
