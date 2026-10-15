// T100 food_diary_page_test (FOOD-25, SAFE-07 diary half, ux.md diary states):
// loading, error with Retry, calm empty day, AI-off note, referProfessional
// hides every number, missing answers point to the nutrition profile, day
// navigation, add/delete/undo, neutral "room left" wording.
import 'package:fitness_app/core/config/body_scan_flags.dart';
import 'package:fitness_app/features/food_diary/data/food_entry.dart';
import 'package:fitness_app/features/food_diary/food_detail_sheet.dart';
import 'package:fitness_app/features/food_diary/food_diary_page.dart';
import 'package:fitness_app/features/food_diary/state/diary_providers.dart';
import 'package:fitness_app/features/food_diary/state/diary_repository.dart';
import 'package:fitness_app/features/nutrition_plan/data/missing_inputs.dart';
import 'package:fitness_app/features/nutrition_plan/data/nutrition_eligibility.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'food_diary_fixtures.dart';
import 'food_diary_harness.dart';

/// First subscription fails (a load error), later ones work: proves Retry
/// re-subscribes.
class _FlakyRepo extends InMemoryDiaryRepository {
  int subscriptions = 0;

  @override
  Stream<List<FoodEntry>> watchDay(String uid, String day) {
    subscriptions++;
    if (subscriptions == 1) {
      return Stream<List<FoodEntry>>.error(StateError('network down'));
    }
    return super.watchDay(uid, day);
  }
}

Future<PumpedPage> _open(
  WidgetTester tester, {
  NutritionEligibility? verdict = const Eligible(),
  BodyScanFlags flags = const BodyScanFlags(),
  bool withPlan = true,
  InMemoryDiaryRepository? repo,
  Locale locale = const Locale('en'),
  List<FoodEntry> seed = const [],
}) async {
  final r = repo ?? InMemoryDiaryRepository();
  for (final e in seed) {
    await r.put(kDiaryUid, e);
  }
  return pumpPage(
    tester,
    const FoodDiaryPage(),
    locale: locale,
    overrides: diaryOverrides(
      verdict: verdict,
      flags: flags,
      withPlan: withPlan,
      extra: [diaryRepositoryProvider.overrideWithValue(r)],
    ),
  );
}

List<String> _texts(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        if (t.data != null) t.data!,
    ];

final _gameWords = RegExp(
    r'budget|cheat|behind|fail|bad|good|points|score|allowance|exceed|earn|burn',
    caseSensitive: false);

void main() {
  group('states', () {
    testWidgets('unknown verdict: a labelled loading indicator, no numbers',
        (tester) async {
      await _open(tester, verdict: null);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.bySemanticsLabel('Loading your diary'), findsOneWidget);
      expect(find.textContaining('kcal'), findsNothing);
    });

    testWidgets('empty day: calm title and body, every slot, no failure tone',
        (tester) async {
      await _open(tester);
      expect(find.text('Nothing logged for this day'), findsOneWidget);
      expect(
          find.text(
              'Add a meal when you are ready. You do not need to fill every slot.'),
          findsOneWidget);
      for (final slot in MealSlot.values) {
        expect(find.byKey(Key('diary.slot.${slot.name}')), findsOneWidget);
      }
      expect(find.text('Nothing here yet'), findsNWidgets(4));
      expect(find.textContaining('Room left'), findsNothing,
          reason: 'no remaining text for an empty day');
      expect(find.text('Today'), findsOneWidget);
      expect(find.byType(Icon).evaluate().any((e) {
        final i = e.widget as Icon;
        return i.icon == Icons.warning || i.icon == Icons.error;
      }), isFalse);
    });

    testWidgets('error: calm message with Retry; Retry loads the day',
        (tester) async {
      final repo = _FlakyRepo();
      await _open(tester, repo: repo);
      expect(find.text('We could not load your diary.'), findsOneWidget);
      expect(find.text('Your entries are safe. Check your connection and try again.'),
          findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(repo.subscriptions, 2);
      expect(find.text('We could not load your diary.'), findsNothing);
      expect(find.text('Nothing logged for this day'), findsOneWidget);
    });

    testWidgets('AI off: the note shows; AI on: it is gone', (tester) async {
      await _open(tester);
      expect(
          find.text(
              'Meal recognition is not available yet. Search and quick log still work.'),
          findsOneWidget);
      await _open(tester, flags: const BodyScanFlags(foodAi: true));
      expect(find.textContaining('Meal recognition is not available'),
          findsNothing);
    });
  });

  group('referProfessional and missing answers (D-9, SAFE-07)', () {
    testWidgets('referProfessional: the neutral notice and no numbers at all',
        (tester) async {
      await _open(tester,
          verdict: const ReferProfessional(ReferReason.guidance),
          seed: [quickEntry(kcal: 700)]);
      expect(find.text('Food diary is not shown'), findsOneWidget);
      expect(find.byKey(const Key('diary.slot.lunch')), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      for (final t in _texts(tester)) {
        expect(RegExp(r'\d').hasMatch(t), isFalse, reason: 'digit in "$t"');
        expect(t.toLowerCase(), isNot(contains('kcal')));
      }
      // The reason is never stated.
      final all = _texts(tester).join(' ').toLowerCase();
      for (final w in ['pregnan', 'eating', 'disorder', 'age', 'under 18']) {
        expect(all, isNot(contains(w)), reason: w);
      }
    });

    testWidgets('each refer reason gives the identical notice', (tester) async {
      for (final r in ReferReason.values) {
        await _open(tester, verdict: ReferProfessional(r));
        expect(find.text('Food diary is not shown'), findsOneWidget);
      }
    });

    testWidgets('needsAnswer points to the nutrition profile', (tester) async {
      final p = await _open(tester,
          verdict: const NeedsAnswer(NutritionQuestion.nutritionGuidance));
      expect(find.text('Finish your nutrition profile first'), findsOneWidget);
      expect(find.byKey(const Key('diary.slot.lunch')), findsNothing);
      await tester.tap(find.text('Open nutrition profile'));
      await settle(tester);
      expect(p.stubUri, '/nutrition/profile');
    });

    testWidgets('needsProfile also points to the profile', (tester) async {
      final p = await _open(tester,
          verdict: const NeedsProfile([NutritionInput.height]));
      await tester.tap(find.text('Open nutrition profile'));
      await settle(tester);
      expect(p.stubUri, '/nutrition/profile');
    });
  });

  group('day content', () {
    testWidgets('entries by slot with the day summary against the plan',
        (tester) async {
      await _open(tester, seed: [
        quickEntry(id: 'a', slot: MealSlot.breakfast, name: 'Oats', kcal: 1000),
        quickEntry(id: 'b', slot: MealSlot.dinner, name: 'Stew', kcal: 1100),
      ]);
      expect(find.byKey(const Key('diary.entry.a')), findsOneWidget);
      expect(find.byKey(const Key('diary.entry.b')), findsOneWidget);
      expect(find.text('Nothing logged for this day'), findsNothing);
      expect(find.text('In your range today.'), findsOneWidget);
      // 2200 (top of range) - 2100 eaten
      expect(find.text('Room left in your range: about 100 kcal'),
          findsOneWidget);
      expect(find.text('Nothing here yet'), findsNWidgets(2),
          reason: 'lunch and snacks are empty');
    });

    testWidgets('below the range uses "room left" as secondary, calm text',
        (tester) async {
      await _open(tester, seed: [quickEntry(kcal: 500)]);
      expect(find.text('The day is not over. Eat what suits you.'),
          findsOneWidget);
      expect(find.text('Room left in your range: about 1,700 kcal'),
          findsOneWidget);
    });

    testWidgets('no budget-game wording anywhere on the page (ux)',
        (tester) async {
      for (final kcal in [0.0, 500.0, 2100.0, 3500.0]) {
        await _open(tester, seed: kcal == 0 ? [] : [quickEntry(kcal: kcal)]);
        for (final t in _texts(tester)) {
          expect(_gameWords.hasMatch(t), isFalse, reason: '"$t" at $kcal');
        }
      }
    });

    testWidgets('without a plan only the eaten amount is shown', (tester) async {
      await _open(tester, withPlan: false, seed: [quickEntry(kcal: 500)]);
      expect(find.textContaining('Room left'), findsNothing);
      expect(find.textContaining('your range'), findsNothing);
      expect(find.text('500'), findsOneWidget);
    });

    testWidgets('tapping an entry opens the detail sheet for it',
        (tester) async {
      await _open(tester, seed: [quickEntry(name: 'Soup')]);
      await tester.tap(find.byKey(const Key('diary.entry.e1')));
      await settle(tester);
      expect(find.byType(FoodDetailSheet), findsOneWidget);
      expect(find.text('Soup'), findsWidgets);
    });
  });

  group('day navigation', () {
    testWidgets('previous day shows that day only; next is disabled on today',
        (tester) async {
      final p = await _open(tester, seed: [
        quickEntry(id: 'today', name: 'Today meal'),
        quickEntry(id: 'yday', day: '2026-10-14', name: 'Old meal'),
      ]);
      expect(find.text('Today meal'), findsOneWidget);
      expect(find.text('Old meal'), findsNothing);
      expect(
          tester
              .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right))
              .onPressed,
          isNull);
      await tester.tap(find.byTooltip('Previous day'));
      await settle(tester);
      expect(p.container.read(selectedDiaryDayProvider), '2026-10-14');
      expect(find.text('Old meal'), findsOneWidget);
      expect(find.text('Today meal'), findsNothing);
      expect(find.text('Wed, Oct 14, 2026'), findsOneWidget);
      expect(find.text('Today'), findsNothing);
      // Next goes forward to today again.
      await tester.tap(find.byTooltip('Next day'));
      await settle(tester);
      expect(p.container.read(selectedDiaryDayProvider), '2026-10-15');
    });

    testWidgets('the date button jumps back to today from an older day',
        (tester) async {
      final p = await _open(tester);
      await tester.tap(find.byTooltip('Previous day'));
      await settle(tester);
      await tester.tap(find.byTooltip('Previous day'));
      await settle(tester);
      expect(p.container.read(selectedDiaryDayProvider), '2026-10-13');
      await tester.tap(find.text('Tue, Oct 13, 2026'));
      await settle(tester);
      expect(p.container.read(selectedDiaryDayProvider), '2026-10-15');
    });

    testWidgets('on today the date button is disabled', (tester) async {
      await _open(tester);
      final b = tester.widget<TextButton>(
          find.ancestor(of: find.text('Today'), matching: find.byType(TextButton)));
      expect(b.onPressed, isNull);
    });

    testWidgets('day arrows are at least 48 dp', (tester) async {
      await _open(tester);
      for (final tip in ['Previous day', 'Next day']) {
        final s = tester.getSize(find.byTooltip(tip));
        expect(s.width, greaterThanOrEqualTo(48));
        expect(s.height, greaterThanOrEqualTo(48));
      }
    });
  });

  group('navigation out', () {
    testWidgets('slot add goes to /nutrition/add with day and slot',
        (tester) async {
      final p = await _open(tester);
      await tester.tap(find.byKey(const Key('diary.add.dinner')));
      await settle(tester);
      expect(p.stubUri, '/nutrition/add?day=2026-10-15&slot=dinner');
    });

    testWidgets('the weight link opens /nutrition/weight', (tester) async {
      final p = await _open(tester);
      await tester.tap(find.byKey(const Key('diary.weightLink')));
      await settle(tester);
      expect(p.stubUri, '/nutrition/weight');
    });
  });

  group('delete and undo', () {
    testWidgets('delete removes the entry; Undo puts it back', (tester) async {
      final repo = InMemoryDiaryRepository();
      await _open(tester, repo: repo, seed: [quickEntry(name: 'Soup')]);
      await tester.tap(find.byTooltip('Delete entry'));
      await settle(tester);
      expect(find.byKey(const Key('diary.entry.e1')), findsNothing);
      expect(find.text(l10nOf(tester).foodDiaryEntryRemoved), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(find.byKey(const Key('diary.entry.e1')), findsOneWidget);
    });

    testWidgets('a failed delete says so and keeps the entry', (tester) async {
      final repo = InMemoryDiaryRepository();
      await _open(tester, repo: repo, seed: [quickEntry()]);
      repo.offline = true;
      await tester.tap(find.byTooltip('Delete entry'));
      await settle(tester);
      expect(find.text('Could not save. Try again.'), findsOneWidget);
      expect(find.byKey(const Key('diary.entry.e1')), findsOneWidget);
    });
  });

  testWidgets('RU: the empty state and notices come from the RU strings',
      (tester) async {
    await _open(tester, locale: const Locale('ru'));
    final ru = l10nOf(tester);
    expect(find.text(ru.foodDiaryEmptyTitle), findsOneWidget);
    expect(ru.foodDiaryEmptyTitle, isNot('Nothing logged for this day'));
    await _open(tester,
        locale: const Locale('ru'),
        verdict: const ReferProfessional(ReferReason.underAge));
    expect(find.text(ru.foodDiaryHiddenTitle), findsOneWidget);
  });
}
