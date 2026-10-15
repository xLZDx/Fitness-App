// C23 diary_providers_test (FOOD-25 state half, SAFE-07 diary half, PRIV-14
// diary writer): visibility per eligibility verdict, entries of one day, day
// targets and totals against the stored plan, and the write actions (deletion
// fence, validation, closed status). The data-notice gate (D-79) is the UI's
// job and is proven in the detail sheet / add-food page tests.
import 'dart:async';

import 'package:fitness_app/features/account_deletion/state/account_deletion_providers.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/food_diary/data/day_totals.dart';
import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:fitness_app/features/food_diary/state/diary_providers.dart';
import 'package:fitness_app/features/food_diary/state/diary_repository.dart';
import 'package:fitness_app/features/nutrition_plan/data/nutrition_eligibility.dart';
import 'package:fitness_app/features/nutrition_plan/data/missing_inputs.dart';
import 'package:fitness_app/features/nutrition_plan/state/nutrition_providers.dart';
import 'package:fitness_app/features/nutrition_plan/state/weight_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../nutrition_plan/plan_state_fixtures.dart';
import '../food_diary_fixtures.dart';

ProviderContainer _container({
  String? uid = kDiaryUid,
  NutritionEligibility? verdict = const Eligible(),
  bool withPlan = true,
  DateTime? now,
  List<Override> extra = const [],
}) {
  final c = ProviderContainer(overrides: [
    authUserProvider.overrideWith((ref) => Stream.value(
        uid == null ? null : AuthUser(uid: uid, displayName: 'T'))),
    nutritionEligibilityProvider.overrideWithValue(verdict),
    storedNutritionPlanProvider.overrideWith(
        (ref) => Stream.value(withPlan ? storedPlan() : null)),
    nutritionClockProvider.overrideWithValue(() => now ?? kDiaryNow),
    ...extra,
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<FoodDiaryActions> _actions(ProviderContainer c) async {
  await c.read(authUserProvider.future);
  return c.read(foodDiaryActionsProvider);
}

InMemoryDiaryRepository _diary(ProviderContainer c) =>
    c.read(diaryRepositoryProvider) as InMemoryDiaryRepository;

void main() {
  // `dayKeyOf` formats with the 'en' locale data; the app initialises it at
  // start-up (and the localization delegates do in widget tests).
  setUpAll(() => initializeDateFormatting('en'));

  group('diaryVisibleProvider (D-9, D-55)', () {
    test('only Eligible shows the diary', () {
      expect(_container().read(diaryVisibleProvider), isTrue);
    });

    test('referProfessional hides it', () {
      final c = _container(verdict: const ReferProfessional(ReferReason.guidance));
      expect(c.read(diaryVisibleProvider), isFalse);
    });

    test('needsAnswer and needsProfile hide it (profile flow instead)', () {
      expect(
          _container(
                  verdict: const NeedsAnswer(NutritionQuestion.nutritionGuidance))
              .read(diaryVisibleProvider),
          isFalse);
      expect(
          _container(verdict: const NeedsProfile([NutritionInput.height]))
              .read(diaryVisibleProvider),
          isFalse);
    });

    test('an unknown verdict fails closed', () {
      expect(_container(verdict: null).read(diaryVisibleProvider), isFalse);
    });
  });

  group('selected day and day keys', () {
    test('dayKeyOf is yyyy-MM-dd with zero padding', () {
      expect(dayKeyOf(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
      expect(dayKeyOf(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('the diary starts on the clock day and can be moved', () {
      final c = _container(now: DateTime(2026, 3, 9, 23, 30));
      expect(c.read(selectedDiaryDayProvider), '2026-03-09');
      c.read(selectedDiaryDayProvider.notifier).state = '2026-03-08';
      expect(c.read(selectedDiaryDayProvider), '2026-03-08');
    });
  });

  group('diaryDayEntriesProvider', () {
    test('signed out: an empty day, no repository read', () async {
      final c = _container(uid: null);
      expect(await c.read(diaryDayEntriesProvider(kToday).future), isEmpty);
    });

    test('returns only that day, oldest first', () async {
      final c = _container();
      final repo = _diary(c);
      await repo.put(kDiaryUid,
          quickEntry(id: 'late', at: DateTime(2026, 10, 15, 20)));
      await repo.put(kDiaryUid,
          quickEntry(id: 'early', at: DateTime(2026, 10, 15, 8)));
      await repo.put(kDiaryUid, quickEntry(id: 'other', day: '2026-10-14'));
      final list = await c.read(diaryDayEntriesProvider(kToday).future);
      expect(list.map((e) => e.id), ['early', 'late']);
    });

    test('a write after the first read is delivered to the stream', () async {
      final c = _container();
      final seen = <List<String>>[];
      c.listen(diaryDayEntriesProvider(kToday), (_, next) {
        final v = next.valueOrNull;
        if (v != null) seen.add([for (final e in v) e.id]);
      }, fireImmediately: true);
      await c.read(diaryDayEntriesProvider(kToday).future);
      await (await _actions(c)).saveEntry(quickEntry(id: 'a'));
      await pumpEventQueue();
      expect(seen.last, ['a']);
    });
  });

  group('dayTargetsProvider', () {
    test('built from the stored plan: low, midpoint, high, protein minimum',
        () async {
      final c = _container();
      await c.read(storedNutritionPlanProvider.future);
      final t = c.read(dayTargetsProvider)!;
      expect(t.kcalLow, 2000);
      expect(t.kcalHigh, 2200);
      expect(t.kcalTarget, 2100);
      expect(t.proteinMinG, storedPlan().protein.minG.toDouble());
      expect(t.proteinMinG, greaterThan(0));
    });

    test('null without a plan', () async {
      final c = _container(withPlan: false);
      await c.read(storedNutritionPlanProvider.future);
      expect(c.read(dayTargetsProvider), isNull);
    });

    test('null for referProfessional even when a plan document exists',
        () async {
      final c =
          _container(verdict: const ReferProfessional(ReferReason.underAge));
      await c.read(storedNutritionPlanProvider.future);
      expect(c.read(dayTargetsProvider), isNull);
    });
  });

  group('dayTotalsProvider', () {
    test('null until the entries have loaded', () {
      expect(_container().read(dayTotalsProvider(kToday)), isNull);
    });

    test('sums the mids and compares them with the plan range', () async {
      final c = _container();
      final repo = _diary(c);
      await repo.put(kDiaryUid, quickEntry(id: 'a', kcal: 1000, protein: 60));
      await repo.put(kDiaryUid, quickEntry(id: 'b', kcal: 1100, protein: 50));
      await c.read(diaryDayEntriesProvider(kToday).future);
      await c.read(storedNutritionPlanProvider.future);
      final d = c.read(dayTotalsProvider(kToday))!;
      expect(d.totals.kcal.mid, 2100);
      expect(d.totals.proteinG.mid, 110);
      expect(d.status, KcalStatus.within);
      expect(d.remainingKcal, 100, reason: '2200 - 2100');
      expect(d.belowRangeBy, 0);
    });

    test('below the range reports the gap to the lower end', () async {
      final c = _container();
      await _diary(c).put(kDiaryUid, quickEntry(kcal: 500));
      await c.read(diaryDayEntriesProvider(kToday).future);
      await c.read(storedNutritionPlanProvider.future);
      final d = c.read(dayTotalsProvider(kToday))!;
      expect(d.status, KcalStatus.below);
      expect(d.belowRangeBy, 1500);
      expect(d.remainingKcal, 1700);
    });

    test('above the range has no remaining room and never a negative', () async {
      final c = _container();
      await _diary(c).put(kDiaryUid, quickEntry(kcal: 900));
      await _diary(c).put(kDiaryUid, quickEntry(id: 'b', kcal: 900));
      await _diary(c).put(kDiaryUid, quickEntry(id: 'c', kcal: 900));
      await c.read(diaryDayEntriesProvider(kToday).future);
      await c.read(storedNutritionPlanProvider.future);
      final d = c.read(dayTotalsProvider(kToday))!;
      expect(d.status, KcalStatus.above);
      expect(d.remainingKcal, 0);
    });

    test('without a plan: a plain sum and no invented "below range"', () async {
      final c = _container(withPlan: false);
      await _diary(c).put(kDiaryUid, quickEntry(kcal: 300));
      await c.read(diaryDayEntriesProvider(kToday).future);
      await c.read(storedNutritionPlanProvider.future);
      final d = c.read(dayTotalsProvider(kToday))!;
      expect(d.totals.kcal.mid, 300);
      expect(d.status, KcalStatus.within);
      expect(d.belowRangeBy, 0);
    });

    test('a different day does not leak into the totals', () async {
      final c = _container();
      await _diary(c).put(kDiaryUid, quickEntry(day: '2026-10-14', kcal: 800));
      await c.read(diaryDayEntriesProvider(kToday).future);
      expect(c.read(dayTotalsProvider(kToday))!.totals.kcal.mid, 0);
    });
  });

  group('FoodDiaryActions.saveEntry', () {
    test('saved: the entry is in the repository under the signed-in uid',
        () async {
      final c = _container();
      final s = await (await _actions(c)).saveEntry(quickEntry());
      expect(s, DiaryWriteStatus.saved);
      expect(_diary(c).writes, 1);
      final list = await c.read(diaryDayEntriesProvider(kToday).future);
      expect(list.single.id, 'e1');
    });

    test('signed out: unavailable, nothing written', () async {
      final c = _container(uid: null);
      expect(await (await _actions(c)).saveEntry(quickEntry()),
          DiaryWriteStatus.unavailable);
      expect(_diary(c).writes, 0);
    });

    test('deletion fence: unavailable for the account being deleted (PRIV-14)',
        () async {
      final c = _container();
      await c.read(authUserProvider.future);
      c.read(accountBeingDeletedUidProvider.notifier).state = kDiaryUid;
      final a = (await _actions(c));
      expect(await a.saveEntry(quickEntry()), DiaryWriteStatus.unavailable);
      expect(await a.deleteEntry('e1'), DiaryWriteStatus.unavailable);
      expect(
          await a.saveFood(const SavedFood(
              id: 's',
              name: 'x',
              per100g: Per100g(kcal: 1, proteinG: 0, carbsG: 0, fatG: 0))),
          DiaryWriteStatus.unavailable);
      expect(await a.deleteSavedFood('s'), DiaryWriteStatus.unavailable);
      expect(_diary(c).writes, 0);
    });

    test('a deletion fence for ANOTHER uid does not block this user', () async {
      final c = _container();
      await c.read(authUserProvider.future);
      c.read(accountBeingDeletedUidProvider.notifier).state = 'someone-else';
      expect(await (await _actions(c)).saveEntry(quickEntry()),
          DiaryWriteStatus.saved);
    });

    test('an entry the rules would refuse is invalid and not written', () async {
      final c = _container();
      final a = (await _actions(c));
      final empty = quickEntry().copyWith(items: const []);
      expect(await a.saveEntry(empty), DiaryWriteStatus.invalid);
      expect(await a.saveEntry(quickEntry(day: '15-10-2026')),
          DiaryWriteStatus.invalid);
      expect(await a.saveEntry(quickEntry(name: 'n' * 81)),
          DiaryWriteStatus.invalid);
      expect(_diary(c).writes, 0);
    });

    test('a degraded entry (unknown enum on read) is never written back',
        () async {
      final c = _container();
      final degraded = FoodEntry.fromJson('d1', {
        'day': kToday,
        'slot': 'brunch',
        'source': 'search',
        'confidence': 'high',
        'name': 'x',
        'items': [
          {
            'foodRef': 'gen:1',
            'name': 'x',
            'grams': {'low': 1, 'mid': 1, 'high': 1},
            'per100g': {'kcal': 1, 'proteinG': 0, 'carbsG': 0, 'fatG': 0},
            'matchQuality': 'exact',
            'sourceId': 'usda_fdc'
          }
        ],
      });
      expect(degraded.degraded, isTrue);
      expect(await (await _actions(c)).saveEntry(degraded),
          DiaryWriteStatus.invalid);
      expect(_diary(c).writes, 0);
    });

    test('a repository failure is the closed status failed, not a throw',
        () async {
      final c = _container();
      await c.read(authUserProvider.future);
      _diary(c).offline = true;
      expect(await (await _actions(c)).saveEntry(quickEntry()),
          DiaryWriteStatus.failed);
    });

    test('saving twice under one id is idempotent (retry safe)', () async {
      final c = _container();
      final a = (await _actions(c));
      await a.saveEntry(quickEntry(kcal: 100));
      await a.saveEntry(quickEntry(kcal: 150));
      final list = await c.read(diaryDayEntriesProvider(kToday).future);
      expect(list, hasLength(1));
      expect(list.single.totals.kcal.mid, 150);
    });
  });

  group('FoodDiaryActions.deleteEntry', () {
    test('removes the entry; undo (saveEntry again) restores it', () async {
      final c = _container();
      final a = await _actions(c);
      c.listen(diaryDayEntriesProvider(kToday), (_, __) {});
      final e = quickEntry();
      await a.saveEntry(e);
      expect(await a.deleteEntry('e1'), DiaryWriteStatus.saved);
      await pumpEventQueue();
      expect(c.read(diaryDayEntriesProvider(kToday)).valueOrNull, isEmpty);
      expect(await a.saveEntry(e), DiaryWriteStatus.saved);
      await pumpEventQueue();
      expect(c.read(diaryDayEntriesProvider(kToday)).valueOrNull!.single.id,
          'e1');
    });

    test('offline: failed', () async {
      final c = _container();
      await c.read(authUserProvider.future);
      _diary(c).offline = true;
      expect(await (await _actions(c)).deleteEntry('e1'),
          DiaryWriteStatus.failed);
    });
  });

  group('FoodDiaryActions saved foods', () {
    const per = Per100g(kcal: 100, proteinG: 5, carbsG: 10, fatG: 2);

    test('save, list and delete', () async {
      final c = _container();
      final a = (await _actions(c));
      expect(await a.saveFood(const SavedFood(id: 's1', name: 'Oats', per100g: per)),
          DiaryWriteStatus.saved);
      final list = await c.read(savedFoodsProvider.future);
      expect(list.map((f) => f.name), ['Oats']);
      expect(await a.deleteSavedFood('s1'), DiaryWriteStatus.saved);
    });

    test('invalid foods are refused with invalid, nothing stored', () async {
      final c = _container();
      final a = (await _actions(c));
      expect(await a.saveFood(const SavedFood(id: 's', name: '  ', per100g: per)),
          DiaryWriteStatus.invalid);
      expect(
          await a.saveFood(const SavedFood(
              id: 's',
              name: 'x',
              per100g: Per100g(kcal: 1001, proteinG: 0, carbsG: 0, fatG: 0))),
          DiaryWriteStatus.invalid);
      expect(
          await a.saveFood(const SavedFood(
              id: 's', name: 'x', per100g: per, servingG: 0)),
          DiaryWriteStatus.invalid);
      expect(await c.read(savedFoodsProvider.future), isEmpty);
    });

    test('the 500-food cap: the 501st NEW food fails, replacing one is fine',
        () async {
      final c = _container();
      final a = (await _actions(c));
      for (var i = 0; i < SavedFood.maxCount; i++) {
        expect(await a.saveFood(SavedFood(id: 's$i', name: 'f$i', per100g: per)),
            DiaryWriteStatus.saved);
      }
      expect(await a.saveFood(const SavedFood(id: 'extra', name: 'x', per100g: per)),
          DiaryWriteStatus.failed);
      expect(await a.saveFood(const SavedFood(id: 's0', name: 'renamed', per100g: per)),
          DiaryWriteStatus.saved);
      expect((await c.read(savedFoodsProvider.future)), hasLength(500));
    });

    test('signed out saved foods list is empty', () async {
      expect(await _container(uid: null).read(savedFoodsProvider.future), isEmpty);
    });
  });

  group('newEntryId', () {
    test('differs for different instants and is stable for one', () {
      final a = newEntryId(DateTime(2026, 10, 15, 9, 0, 0, 0, 1));
      final b = newEntryId(DateTime(2026, 10, 15, 9, 0, 0, 0, 2));
      expect(a, isNot(b));
      expect(a, newEntryId(DateTime(2026, 10, 15, 9, 0, 0, 0, 1)));
    });

    test('is a safe document id (letters and digits only, starts with e)', () {
      final id = newEntryId(DateTime(2026, 10, 15, 9));
      expect(RegExp(r'^e[a-z0-9]+$').hasMatch(id), isTrue, reason: id);
      expect(id.length, lessThan(40));
    });
  });
}
