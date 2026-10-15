// T99 check_these_chips_test (FOOD-20 chips half, A11Y-09; a11y F13): every
// chip says its state in TEXT (not colour), the unresolved count is announced
// ONCE, 48 dp targets, and focus moves to the next unresolved chip (or the
// heading) after a chip is resolved.
import 'package:fitness_app/features/food_diary/data/check_these.dart';
import 'package:fitness_app/features/food_diary/widgets/check_these_chips.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../food_diary_harness.dart';

class _Host extends StatefulWidget {
  const _Host({required this.initial, required this.taps});
  final List<CheckItem> initial;
  final List<CheckItem> taps;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late List<CheckItem> items = widget.initial;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          CheckTheseChips(
            items: items,
            onTap: widget.taps.add,
          ),
          TextButton(
            key: const Key('resolveFirst'),
            onPressed: () {
              final first = CheckThese.unresolved(items).first;
              setState(() => items = CheckThese.markResolved(items, first.code));
            },
            child: const Text('resolve first'),
          ),
          TextButton(
            key: const Key('resolveLast'),
            onPressed: () {
              final last = CheckThese.unresolved(items).last;
              setState(() => items = CheckThese.markResolved(items, last.code));
            },
            child: const Text('resolve last'),
          ),
        ],
      );
}

List<CheckItem> _two() => const [
      CheckItem(code: CheckCode.portionUnclear),
      CheckItem(code: CheckCode.hiddenIngredients),
    ];

List<String> _captureAnnouncements(WidgetTester tester) {
  final out = <String>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility, (message) async {
    final m = message as Map?;
    if (m != null && m['type'] == 'announce') {
      out.add((m['data'] as Map)['message'] as String);
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null));
  return out;
}

String? _focusLabel() => FocusManager.instance.primaryFocus?.debugLabel;

void main() {
  testWidgets('each chip shows title AND state as text with an icon',
      (tester) async {
    await pumpWidgetOnly(
        tester,
        _Host(initial: const [
          CheckItem(code: CheckCode.portionUnclear),
          CheckItem(code: CheckCode.hiddenIngredients, resolved: true),
        ], taps: []));
    expect(find.text('Check these'), findsOneWidget);
    expect(find.text('Portion size - Needs checking'), findsOneWidget);
    expect(find.text('Cooking oil or sauce - Checked'), findsOneWidget);
    expect(find.byIcon(Icons.help_outline), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets('screen-reader label is "title, state" and the chip is a button',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpWidgetOnly(tester, _Host(initial: _two(), taps: []));
    expect(find.bySemanticsLabel('Portion size, Needs checking'), findsOneWidget);
    expect(find.bySemanticsLabel('Cooking oil or sauce, Needs checking'),
        findsOneWidget);
    expect(
        tester.getSemantics(
            find.bySemanticsLabel('Portion size, Needs checking')),
        matchesSemantics(
            label: 'Portion size, Needs checking',
            isButton: true,
            hasTapAction: true));
    handle.dispose();
  });

  testWidgets('state words follow the locale (RU differs from EN)',
      (tester) async {
    await pumpWidgetOnly(tester, _Host(initial: _two(), taps: []),
        locale: const Locale('ru'));
    final ru = lookupAppLocalizations(const Locale('ru'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(ru.foodCheckNeeds, isNot(en.foodCheckNeeds));
    expect(
        find.text('${ru.foodCheckPortionUnclear} - ${ru.foodCheckNeeds}'),
        findsOneWidget);
    expect(find.text('Portion size - Needs checking'), findsNothing);
  });

  testWidgets('tapping a chip reports that chip', (tester) async {
    final taps = <CheckItem>[];
    await pumpWidgetOnly(tester, _Host(initial: _two(), taps: taps));
    await tester.tap(find.text('Cooking oil or sauce - Needs checking'));
    await tester.pump();
    expect(taps.map((c) => c.code), [CheckCode.hiddenIngredients]);
  });

  testWidgets('targets are at least 48 dp tall', (tester) async {
    await pumpWidgetOnly(tester, _Host(initial: _two(), taps: []));
    for (final chip in tester.widgetList(find.byType(ActionChip))) {
      final h = tester.getSize(find.byWidget(chip)).height;
      expect(h, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('an empty list renders nothing (no heading)', (tester) async {
    await pumpWidgetOnly(tester, _Host(initial: const [], taps: []));
    expect(find.text('Check these'), findsNothing);
    expect(find.byType(ActionChip), findsNothing);
  });

  group('announcement', () {
    testWidgets('the open count is announced exactly once', (tester) async {
      final said = _captureAnnouncements(tester);
      await pumpWidgetOnly(tester, _Host(initial: _two(), taps: []));
      await tester.pump();
      expect(said, ['2 items to check']);
      await tester.tap(find.byKey(const Key('resolveFirst')));
      await tester.pump();
      await tester.pump();
      expect(said, hasLength(1), reason: 'resolving must not re-announce');
    });

    testWidgets('singular wording for one open chip', (tester) async {
      final said = _captureAnnouncements(tester);
      await pumpWidgetOnly(
          tester,
          _Host(initial: const [
            CheckItem(code: CheckCode.portionUnclear),
            CheckItem(code: CheckCode.hiddenIngredients, resolved: true),
          ], taps: []));
      await tester.pump();
      expect(said, ['1 item to check']);
    });

    testWidgets('nothing is announced when every chip is already resolved',
        (tester) async {
      final said = _captureAnnouncements(tester);
      await pumpWidgetOnly(
          tester,
          _Host(initial: const [
            CheckItem(code: CheckCode.portionUnclear, resolved: true),
          ], taps: []));
      await tester.pump();
      expect(said, isEmpty);
    });
  });

  group('focus after resolve (F13)', () {
    testWidgets('resolving the first chip focuses the next unresolved one',
        (tester) async {
      await pumpWidgetOnly(tester, _Host(initial: _two(), taps: []));
      await tester.tap(find.byKey(const Key('resolveFirst')));
      await tester.pump();
      await tester.pump();
      expect(_focusLabel(), 'check.hiddenIngredients');
    });

    testWidgets('resolving the last open chip moves focus to the heading',
        (tester) async {
      await pumpWidgetOnly(
          tester,
          _Host(initial: const [
            CheckItem(code: CheckCode.portionUnclear),
          ], taps: []));
      await tester.tap(find.byKey(const Key('resolveFirst')));
      await tester.pump();
      await tester.pump();
      expect(_focusLabel(), 'check.heading');
      expect(find.text('Portion size - Checked'), findsOneWidget);
    });

    testWidgets('focus skips chips that are already resolved', (tester) async {
      await pumpWidgetOnly(
          tester,
          _Host(initial: const [
            CheckItem(code: CheckCode.portionUnclear),
            CheckItem(code: CheckCode.liquidUnknown, resolved: true),
            CheckItem(code: CheckCode.cookingMethod),
          ], taps: []));
      await tester.tap(find.byKey(const Key('resolveFirst')));
      await tester.pump();
      await tester.pump();
      expect(_focusLabel(), 'check.cookingMethod');
    });

    testWidgets('no focus jump when nothing was resolved by the update',
        (tester) async {
      await pumpWidgetOnly(tester, _Host(initial: _two(), taps: []));
      final before = _focusLabel();
      await tester.pump();
      expect(_focusLabel(), before);
      expect(_focusLabel(), isNot('check.heading'));
    });
  });
}
