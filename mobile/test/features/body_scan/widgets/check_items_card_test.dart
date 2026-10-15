import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/body_scan/data/check_items.dart';
import 'package:fitness_app/features/body_scan/widgets/check_items_card.dart';

import '../support/scan_test_support.dart';

Finder _chip(CheckCode c) => find.byKey(Key('bodyScan.checks.chip.${c.name}'));
Finder _heading() => find.byKey(const Key('bodyScan.checks.heading'));

List<SemanticsNode> _nodes(WidgetTester tester) {
  final out = <SemanticsNode>[];
  void walk(SemanticsNode n) {
    out.add(n);
    n.visitChildren((c) {
      walk(c);
      return true;
    });
  }

  walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return out;
}

int _liveRegions(WidgetTester t) => _nodes(t)
    .where((n) => n.getSemanticsData().hasFlag(SemanticsFlag.isLiveRegion))
    .length;

Future<void> _pump(WidgetTester tester, List<CheckCode> items,
    {void Function(CheckAction)? onAction,
    Locale locale = const Locale('en')}) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(scanHost(
      CheckItemsCard(items: items, onAction: onAction),
      locale: locale));
  await tester.pump();
}

void main() {
  group('text mapping', () {
    test('every closed code has a distinct non-empty EN and RU text', () async {
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      final ru = await AppLocalizations.delegate.load(const Locale('ru'));
      final enTexts = <String>{};
      for (final c in CheckCode.values) {
        final e = checkCodeText(en, c);
        final r = checkCodeText(ru, c);
        expect(e, isNotEmpty, reason: c.name);
        expect(r, isNotEmpty, reason: c.name);
        expect(r, isNot(e), reason: '${c.name} untranslated');
        enTexts.add(e);
      }
      expect(enTexts, hasLength(CheckCode.values.length));
    });

    test('action labels', () async {
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      expect(checkActionLabel(en, CheckAction.none), '');
      expect(checkActionLabel(en, CheckAction.retakeLighting), 'Retake photos');
      expect(checkActionLabel(en, CheckAction.retakeFraming), 'Retake photos');
      expect(checkActionLabel(en, CheckAction.retakePose), 'Retake photos');
      expect(checkActionLabel(en, CheckAction.logWeight), 'Log weight');
      expect(checkActionLabel(en, CheckAction.confirmWeight), 'Check weight');
    });
  });

  group('chips', () {
    testWidgets('empty list renders nothing', (tester) async {
      await _pump(tester, const []);
      expect(find.byKey(const Key('bodyScan.checks.card')), findsNothing);
    });

    testWidgets('each chip has icon, text and an explicit state label',
        (tester) async {
      await _pump(tester, [CheckCode.poorLighting, CheckCode.wideRange]);
      expect(find.text('The lighting was poor. Retake in even light.'),
          findsOneWidget);
      expect(find.text('needs checking'), findsNWidgets(2));
      expect(find.byIcon(Icons.error_outline), findsNWidgets(2));
      expect(find.text('resolved'), findsNothing);
    });

    testWidgets('semantics: "<item>, needs checking" and is a button',
        (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester, [CheckCode.wideRange]);
      final node = tester.getSemantics(_chip(CheckCode.wideRange));
      expect(node.label,
          'The likely range is wide, so this reading is less certain., needs checking');
      expect(node.hint, 'Mark as checked');
      expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
      h.dispose();
    });

    testWidgets('tapping resolves: label, icon, button flag and hint change',
        (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester, [CheckCode.wideRange]);
      await tester.tap(_chip(CheckCode.wideRange));
      await tester.pump();
      await tester.pump();
      final node = tester.getSemantics(_chip(CheckCode.wideRange));
      expect(node.label, endsWith(', resolved'));
      expect(node.hasFlag(SemanticsFlag.isButton), isFalse);
      expect(node.hint, isEmpty);
      expect(find.text('resolved'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      h.dispose();
    });

    testWidgets('a resolved chip cannot be toggled back', (tester) async {
      await _pump(tester, [CheckCode.wideRange, CheckCode.poorLighting]);
      await tester.tap(_chip(CheckCode.wideRange));
      await tester.pump();
      await tester.tap(_chip(CheckCode.wideRange));
      await tester.pump();
      expect(find.text('resolved'), findsOneWidget);
      expect(_heading(), findsOneWidget);
      expect(tester.widget<Text>(_heading()).data,
          'Check these: 1 item to check');
    });

    testWidgets('chips are at least 48 dp tall', (tester) async {
      await _pump(tester, [CheckCode.wideRange, CheckCode.weightStale]);
      for (final c in [CheckCode.wideRange, CheckCode.weightStale]) {
        expect(tester.getSize(_chip(c)).height, greaterThanOrEqualTo(48));
      }
    });
  });

  group('heading count', () {
    testWidgets('plural forms and the all-resolved text', (tester) async {
      await _pump(tester, [CheckCode.wideRange, CheckCode.poorLighting]);
      expect(tester.widget<Text>(_heading()).data,
          'Check these: 2 items to check');
      await tester.tap(_chip(CheckCode.wideRange));
      await tester.pump();
      expect(tester.widget<Text>(_heading()).data,
          'Check these: 1 item to check');
      await tester.tap(_chip(CheckCode.poorLighting));
      await tester.pump();
      expect(
          tester.widget<Text>(_heading()).data, 'Check these: All items checked');
    });
  });

  group('one announcement', () {
    testWidgets('heading is the only live region while nothing is resolved',
        (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester, [CheckCode.wideRange, CheckCode.poorLighting]);
      expect(_liveRegions(tester), 1);
      final head = tester.getSemantics(_heading());
      expect(head.hasFlag(SemanticsFlag.isHeader), isTrue);
      h.dispose();
    });

    testWidgets('after the first resolve there is no live region and no '
        'announce message is sent', (tester) async {
      final h = tester.ensureSemantics();
      final sent = <dynamic>[];
      tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
          SystemChannels.accessibility, (m) async {
        sent.add(m);
        return null;
      });
      await _pump(tester, [CheckCode.wideRange, CheckCode.poorLighting]);
      await tester.tap(_chip(CheckCode.wideRange));
      await tester.pump();
      await tester.pump();
      expect(_liveRegions(tester), 0);
      expect(sent.where((m) => m is Map && m['type'] == 'announce'), isEmpty);
      tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(
              SystemChannels.accessibility, null);
      h.dispose();
    });
  });

  group('focus after resolve (D-85)', () {
    InkWell? focusedInk() => FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<InkWell>();

    testWidgets('resolving the first chip focuses the next unresolved one',
        (tester) async {
      await _pump(tester, [
        CheckCode.wideRange,
        CheckCode.poorLighting,
        CheckCode.weightStale,
      ]);
      await tester.tap(_chip(CheckCode.wideRange));
      await tester.pump();
      await tester.pump();
      expect(focusedInk()?.key, const Key('bodyScan.checks.chip.poorLighting'));
    });

    testWidgets('resolving out of order skips resolved ones', (tester) async {
      await _pump(tester, [
        CheckCode.wideRange,
        CheckCode.poorLighting,
        CheckCode.weightStale,
      ]);
      await tester.tap(_chip(CheckCode.poorLighting));
      await tester.pump();
      await tester.pump();
      // First unresolved in list order is wideRange.
      expect(focusedInk()?.key, const Key('bodyScan.checks.chip.wideRange'));
      await tester.tap(_chip(CheckCode.wideRange));
      await tester.pump();
      await tester.pump();
      expect(focusedInk()?.key, const Key('bodyScan.checks.chip.weightStale'));
    });

    testWidgets('resolving the last chip moves focus to the card heading',
        (tester) async {
      await _pump(tester, [CheckCode.wideRange]);
      await tester.tap(_chip(CheckCode.wideRange));
      await tester.pump();
      await tester.pump();
      final ctx = FocusManager.instance.primaryFocus!.context!;
      expect(find.descendant(of: find.byWidget(ctx.widget), matching: _heading()),
          findsOneWidget);
    });
  });

  group('actions', () {
    testWidgets('an item with an action offers a button that reports it',
        (tester) async {
      final got = <CheckAction>[];
      await _pump(tester, [CheckCode.weightStale, CheckCode.poorLighting],
          onAction: got.add);
      expect(find.text('Log weight'), findsOneWidget);
      expect(find.text('Retake photos'), findsOneWidget);
      await tester.tap(find.byKey(const Key('bodyScan.checks.action.weightStale')));
      await tester.tap(find.byKey(const Key('bodyScan.checks.action.poorLighting')));
      expect(got, [CheckAction.logWeight, CheckAction.retakeLighting]);
    });

    testWidgets('informational items have no action button', (tester) async {
      await _pump(tester, [CheckCode.wideRange, CheckCode.provisionalEstimator],
          onAction: (_) {});
      expect(find.byKey(const Key('bodyScan.checks.action.wideRange')),
          findsNothing);
      expect(
          find.byKey(const Key('bodyScan.checks.action.provisionalEstimator')),
          findsNothing);
    });

    testWidgets('no host callback means no action buttons', (tester) async {
      await _pump(tester, [CheckCode.weightStale]);
      expect(find.text('Log weight'), findsNothing);
    });

    testWidgets('resolving an item removes its action button', (tester) async {
      await _pump(tester, [CheckCode.weightStale], onAction: (_) {});
      await tester.tap(_chip(CheckCode.weightStale));
      await tester.pump();
      expect(find.text('Log weight'), findsNothing);
    });
  });

  testWidgets('RU at text scale 2.0 does not overflow', (tester) async {
    await _pump(tester, CheckCode.values, locale: const Locale('ru'));
    tester.view.physicalSize = const Size(360, 3000);
    await tester.pumpWidget(scanHost(
        SingleChildScrollView(
            child: CheckItemsCard(items: CheckCode.values, onAction: (_) {})),
        locale: const Locale('ru'),
        textScale: 2.0));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
