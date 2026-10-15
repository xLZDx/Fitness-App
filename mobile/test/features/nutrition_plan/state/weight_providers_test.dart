// C18 weight_providers_test. The ONE current-weight definition (D-72: newest
// weigh-in within 14 days, else the profile weight flagged stale, else null),
// the weigh-in actions (validation, the account-deletion fence, a scan weight
// that never silently replaces an equal same-day manual entry) and the link
// from the current weight to the eligibility verdict.
import 'package:fitness_app/features/nutrition_plan/data/nutrition_eligibility.dart';
import 'package:fitness_app/features/nutrition_plan/data/weight_entry.dart';
import 'package:fitness_app/features/nutrition_plan/data/weight_repository.dart';
import 'package:fitness_app/features/nutrition_plan/state/nutrition_providers.dart';
import 'package:fitness_app/features/nutrition_plan/state/weight_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../plan_state_fixtures.dart';
import '../plan_state_harness.dart';

WeightEntry _at(Duration ago, double kg,
        {WeightSource source = WeightSource.manual}) =>
    WeightEntry(at: kNow.subtract(ago), kg: kg, source: source);

void main() {
  late PlanHarness h;
  tearDown(() => h.dispose());

  Future<void> put(WeightEntry e) async {
    await h.weights.put(kUid, e);
    await h.settle();
  }

  WeightLogActions actions() => h.container.read(weightLogActionsProvider);

  Future<List<WeightLogItem>> log() => h.weights.loadLog(kUid);

  group('currentWeightProvider (D-72)', () {
    test('no weigh-in: the profile weight, flagged stale', () async {
      h = await makeHarness(profile: eligibleProfile(weightKg: 82));
      final w = h.container.read(currentWeightProvider)!;
      expect(w.kg, 82);
      expect(w.stale, isTrue);
    });

    test('a weigh-in within 14 days wins over the profile, not stale', () async {
      h = await makeHarness(profile: eligibleProfile(weightKg: 82));
      await put(_at(const Duration(days: 3), 79.5));
      final w = h.container.read(currentWeightProvider)!;
      expect(w.kg, 79.5);
      expect(w.stale, isFalse);
    });

    test('the NEWEST weigh-in is used, not the largest or the last written',
        () async {
      h = await makeHarness();
      await put(_at(const Duration(days: 1), 80.5));
      await put(_at(const Duration(days: 6), 83));
      await put(_at(const Duration(days: 10), 78));
      expect(h.container.read(currentWeightProvider)!.kg, 80.5);
    });

    test('exactly 14 days old is still fresh', () async {
      h = await makeHarness(profile: eligibleProfile(weightKg: 82));
      await put(_at(const Duration(days: 14), 79));
      final w = h.container.read(currentWeightProvider)!;
      expect(w.kg, 79);
      expect(w.stale, isFalse);
    });

    test('15 days old falls back to the stale profile weight', () async {
      h = await makeHarness(profile: eligibleProfile(weightKg: 82));
      await put(_at(const Duration(days: 15), 79));
      final w = h.container.read(currentWeightProvider)!;
      expect(w.kg, 82);
      expect(w.stale, isTrue);
    });

    test('nothing at all (no profile weight, no entry) is null', () async {
      h = await makeHarness(profile: eligibleProfile(weightKg: null));
      expect(h.container.read(currentWeightProvider), isNull);
    });

    test('a stale weigh-in and no profile weight is null, not the old entry',
        () async {
      h = await makeHarness(profile: eligibleProfile(weightKg: null));
      await put(_at(const Duration(days: 30), 79));
      expect(h.container.read(currentWeightProvider), isNull);
    });

    test('eligibility reads the SAME definition: a weigh-in completes a profile',
        () async {
      h = await makeHarness(profile: eligibleProfile(weightKg: null));
      expect(h.container.read(nutritionEligibilityProvider),
          isA<NeedsProfile>());
      expect(await actions().add(80), WeightWriteStatus.saved);
      await h.settle();
      expect(h.container.read(nutritionEligibilityProvider), isA<Eligible>());
    });
  });

  group('weight log providers', () {
    test('weightEntriesProvider lists entries oldest first', () async {
      h = await makeHarness();
      await put(_at(const Duration(days: 1), 80));
      await put(_at(const Duration(days: 5), 81));
      final list = h.container.read(weightEntriesProvider).valueOrNull!;
      expect(list.map((e) => e.kg), [81, 80]);
    });

    test('signed out: the log is empty', () async {
      h = await makeHarness(uid: null);
      expect(h.container.read(weightLogItemsProvider).valueOrNull, isEmpty);
    });
  });

  group('WeightLogActions.add', () {
    test('stores a manual entry keyed by the local day', () async {
      h = await makeHarness();
      expect(await actions().add(80.4), WeightWriteStatus.saved);
      final items = await log();
      expect(items.single.id, '2026-10-15');
      expect(items.single.entry.kg, 80.4);
      expect(items.single.entry.source, WeightSource.manual);
      expect(items.single.entry.at, kNow);
    });

    test('a second add on the same day overwrites it', () async {
      h = await makeHarness();
      await actions().add(80);
      await actions().add(79.2);
      final items = await log();
      expect(items, hasLength(1));
      expect(items.single.entry.kg, 79.2);
    });

    test('an explicit date is honoured', () async {
      h = await makeHarness();
      await actions().add(81, at: DateTime(2026, 10, 10, 7));
      expect((await log()).single.id, '2026-10-10');
    });

    for (final bad in [29.9, 300.1, 0.0, -1.0, double.nan, double.infinity]) {
      test('$bad kg is invalid and nothing is stored', () async {
        h = await makeHarness();
        expect(await actions().add(bad), WeightWriteStatus.invalid);
        expect(await log(), isEmpty);
      });
    }

    test('30 and 300 kg are accepted', () async {
      h = await makeHarness();
      expect(await actions().add(30), WeightWriteStatus.saved);
      expect(
          await actions().add(300, at: kNow.subtract(const Duration(days: 1))),
          WeightWriteStatus.saved);
    });

    test('signed out: unavailable, nothing stored', () async {
      h = await makeHarness(uid: null);
      expect(await actions().add(80), WeightWriteStatus.unavailable);
      expect(await log(), isEmpty);
    });

    test('deletion fence: no write while this account is being deleted',
        () async {
      h = await makeHarness(deletingUid: kUid);
      expect(await actions().add(80), WeightWriteStatus.unavailable);
      expect(await actions().saveScanWeight(80), WeightWriteStatus.unavailable);
      expect(await log(), isEmpty);
    });
  });

  group('WeightLogActions.saveScanWeight', () {
    test('no entry that day: stored with source scan', () async {
      h = await makeHarness();
      expect(await actions().saveScanWeight(79.8), WeightWriteStatus.saved);
      final e = (await log()).single.entry;
      expect(e.kg, 79.8);
      expect(e.source, WeightSource.scan);
    });

    test('an EQUAL same-day manual entry is kept untouched (keptManual)',
        () async {
      h = await makeHarness();
      final manualAt = DateTime(2026, 10, 15, 7, 15);
      await actions().add(80, at: manualAt);
      expect(await actions().saveScanWeight(80), WeightWriteStatus.keptManual);
      final e = (await log()).single.entry;
      expect(e.source, WeightSource.manual);
      expect(e.at, manualAt, reason: 'the manual entry is not rewritten');
    });

    test('a DIFFERENT value over a same-day manual entry is the explicit edit',
        () async {
      h = await makeHarness();
      await actions().add(80);
      expect(await actions().saveScanWeight(79.4), WeightWriteStatus.saved);
      final items = await log();
      expect(items, hasLength(1));
      expect(items.single.entry.kg, 79.4);
      expect(items.single.entry.source, WeightSource.scan);
    });

    test('an equal weight over an earlier SCAN entry is rewritten (not manual)',
        () async {
      h = await makeHarness();
      await actions().saveScanWeight(80, at: DateTime(2026, 10, 15, 6));
      expect(await actions().saveScanWeight(80), WeightWriteStatus.saved);
      expect((await log()).single.entry.at, kNow);
    });

    test('an equal manual entry on ANOTHER day does not block the scan weight',
        () async {
      h = await makeHarness();
      await actions().add(80, at: DateTime(2026, 10, 14, 8));
      expect(await actions().saveScanWeight(80), WeightWriteStatus.saved);
      expect(await log(), hasLength(2));
    });

    test('an invalid scan weight is refused', () async {
      h = await makeHarness();
      expect(await actions().saveScanWeight(12), WeightWriteStatus.invalid);
      expect(await log(), isEmpty);
    });

    test('signed out: unavailable', () async {
      h = await makeHarness(uid: null);
      expect(await actions().saveScanWeight(80), WeightWriteStatus.unavailable);
    });
  });

  group('WeightLogActions.edit and delete', () {
    test('edit changes the weight and keeps the day', () async {
      h = await makeHarness();
      await actions().add(80);
      final item = (await log()).single;
      expect(await actions().edit(item, kg: 79), WeightWriteStatus.saved);
      final items = await log();
      expect(items.single.id, item.id);
      expect(items.single.entry.kg, 79);
      expect(items.single.entry.source, WeightSource.manual);
    });

    test('edit with a new date moves the entry (old id removed)', () async {
      h = await makeHarness();
      await actions().add(80);
      final item = (await log()).single;
      await actions().edit(item, kg: 80, at: DateTime(2026, 10, 12, 8));
      final items = await log();
      expect(items.map((i) => i.id), ['2026-10-12']);
    });

    test('edit with an invalid weight keeps the original', () async {
      h = await makeHarness();
      await actions().add(80);
      final item = (await log()).single;
      expect(await actions().edit(item, kg: 500), WeightWriteStatus.invalid);
      expect((await log()).single.entry.kg, 80);
    });

    test('delete removes the entry', () async {
      h = await makeHarness();
      await actions().add(80);
      final item = (await log()).single;
      expect(await actions().delete(item), WeightWriteStatus.saved);
      expect(await log(), isEmpty);
    });

    test('deletion fence: edit and delete are refused for a deleting account',
        () async {
      h = await makeHarness(deletingUid: kUid);
      await h.weights.put(kUid, _at(Duration.zero, 80));
      final item = (await log()).single;
      expect(await actions().edit(item, kg: 70), WeightWriteStatus.unavailable);
      expect(await actions().delete(item), WeightWriteStatus.unavailable);
      expect((await log()).single.entry.kg, 80);
    });

    test('signed out: edit and delete are unavailable', () async {
      h = await makeHarness(uid: null);
      final item = WeightLogItem(id: '2026-10-15', entry: _at(Duration.zero, 80));
      expect(await actions().edit(item, kg: 70), WeightWriteStatus.unavailable);
      expect(await actions().delete(item), WeightWriteStatus.unavailable);
    });
  });
}
