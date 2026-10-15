import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/body_scan/widgets/weight_prompt_sheet.dart';

import '../support/scan_test_support.dart';

class _Host extends StatefulWidget {
  const _Host({this.staleDays});
  final int? staleDays;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String result = 'pending';
  @override
  Widget build(BuildContext context) => Center(
        child: ElevatedButton(
          key: const Key('opener'),
          onPressed: () async {
            final r = await WeightPromptSheet.show(context,
                staleDays: widget.staleDays);
            setState(() => result = r == null
                ? 'dismissed'
                : r.skipped
                    ? 'skipped'
                    : 'logged ${r.kg}');
          },
          child: Text('open:$result'),
        ),
      );
}

Future<void> _open(WidgetTester tester,
    {int? staleDays, Locale locale = const Locale('en')}) async {
  await tester.pumpWidget(scanHost(_Host(staleDays: staleDays), locale: locale));
  await tester.tap(find.byKey(const Key('opener')));
  await tester.pumpAndSettle();
}

String _result(WidgetTester tester) => tester
    .widget<Text>(find.descendant(
        of: find.byKey(const Key('opener')), matching: find.byType(Text)))
    .data!;

Finder _field() => find.byKey(const Key('bodyScan.weight.field'));

void main() {
  group('parseBodyScanWeight', () {
    test('accepts point and comma decimals and trims', () {
      expect(parseBodyScanWeight('80'), 80);
      expect(parseBodyScanWeight('80,5'), 80.5);
      expect(parseBodyScanWeight('80.5'), 80.5);
      expect(parseBodyScanWeight('  75.3 '), 75.3);
    });

    test('20 and 400 are valid, just outside is not', () {
      expect(parseBodyScanWeight('20'), 20);
      expect(parseBodyScanWeight('400'), 400);
      expect(parseBodyScanWeight('19.9'), isNull);
      expect(parseBodyScanWeight('400.1'), isNull);
    });

    test('empty, text, double separators and non-finite are rejected', () {
      for (final bad in ['', ' ', 'abc', '8,0,5', '8..5', 'NaN', 'Infinity', '-80', '0']) {
        expect(parseBodyScanWeight(bad), isNull, reason: bad);
      }
    });
  });

  group('sheet', () {
    testWidgets('missing weight copy', (tester) async {
      await _open(tester);
      expect(find.text('Log your weight first'), findsOneWidget);
      expect(
          find.text(
              'There is no recent weight on file. A current weight makes the estimate more reliable.'),
          findsOneWidget);
    });

    testWidgets('stale weight copy is plural aware', (tester) async {
      await _open(tester, staleDays: 5);
      expect(
          find.text(
              'Your last weight is 5 days old. A current weight makes the estimate more reliable.'),
          findsOneWidget);
    });

    testWidgets('one day old is singular', (tester) async {
      await _open(tester, staleDays: 1);
      expect(find.textContaining('Your last weight is 1 day old.'),
          findsOneWidget);
    });

    testWidgets('a comma decimal is saved as a point value', (tester) async {
      await _open(tester);
      await tester.enterText(_field(), '81,4');
      await tester.tap(find.byKey(const Key('bodyScan.weight.save')));
      await tester.pumpAndSettle();
      expect(_result(tester), 'open:logged 81.4');
    });

    testWidgets('a point decimal is saved', (tester) async {
      await _open(tester);
      await tester.enterText(_field(), '70.25');
      await tester.tap(find.byKey(const Key('bodyScan.weight.save')));
      await tester.pumpAndSettle();
      expect(_result(tester), 'open:logged 70.25');
    });

    testWidgets('an out of range weight shows the error and keeps the sheet',
        (tester) async {
      await _open(tester);
      await tester.enterText(_field(), '19');
      await tester.tap(find.byKey(const Key('bodyScan.weight.save')));
      await tester.pump();
      expect(find.text('Enter a weight between 20 and 400 kg.'),
          findsOneWidget);
      expect(find.byType(WeightPromptSheet), findsOneWidget);
      expect(_result(tester), 'open:pending');
    });

    testWidgets('an empty field is invalid, not zero', (tester) async {
      await _open(tester);
      await tester.tap(find.byKey(const Key('bodyScan.weight.save')));
      await tester.pump();
      expect(find.text('Enter a weight between 20 and 400 kg.'),
          findsOneWidget);
      expect(_result(tester), 'open:pending');
    });

    testWidgets('typing clears the error', (tester) async {
      await _open(tester);
      await tester.enterText(_field(), '500');
      await tester.tap(find.byKey(const Key('bodyScan.weight.save')));
      await tester.pump();
      expect(find.text('Enter a weight between 20 and 400 kg.'),
          findsOneWidget);
      await tester.enterText(_field(), '50');
      await tester.pump();
      expect(find.text('Enter a weight between 20 and 400 kg.'), findsNothing);
    });

    testWidgets('the field only accepts digits, point and comma',
        (tester) async {
      await _open(tester);
      await tester.enterText(_field(), 'a8b0,c5-');
      expect(tester.widget<TextField>(_field()).controller!.text, '80,5');
    });

    testWidgets('Skip returns skipped with no weight', (tester) async {
      await _open(tester);
      await tester.enterText(_field(), '80');
      await tester.tap(find.byKey(const Key('bodyScan.weight.skip')));
      await tester.pumpAndSettle();
      expect(_result(tester), 'open:skipped');
    });

    testWidgets('dismissing by barrier tap returns null (not skipped)',
        (tester) async {
      await _open(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(_result(tester), 'open:dismissed');
    });

    testWidgets('keyboard submit saves like the button', (tester) async {
      await _open(tester);
      await tester.enterText(_field(), '66');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_result(tester), 'open:logged 66.0');
    });
  });

  group('modal and accessibility (D-85)', () {
    testWidgets('initial focus is on the heading', (tester) async {
      await _open(tester);
      final ctx = FocusManager.instance.primaryFocus!.context!;
      expect(
          find.descendant(
              of: find.byWidget(ctx.widget),
              matching: find.byKey(const Key('bodyScan.weight.title'))),
          findsOneWidget);
    });

    testWidgets('heading is a header and the page behind is blocked',
        (tester) async {
      final h = tester.ensureSemantics();
      await _open(tester);
      final title =
          tester.getSemantics(find.byKey(const Key('bodyScan.weight.title')));
      expect(title.hasFlag(SemanticsFlag.isHeader), isTrue);
      final labels = <String>[];
      void walk(SemanticsNode n) {
        if (n.label.isNotEmpty) labels.add(n.label);
        n.visitChildren((c) {
          walk(c);
          return true;
        });
      }

      walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
      expect(labels.any((l) => l.startsWith('open:')), isFalse);
      h.dispose();
    });

    testWidgets('focus returns to the keyboard-focused trigger',
        (tester) async {
      await tester.pumpWidget(scanHost(const _Host()));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bodyScan.weight.skip')));
      await tester.pumpAndSettle();
      final owner = FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<ElevatedButton>();
      expect(owner?.key, const Key('opener'));
    });

    testWidgets('Save and Skip are at least 48 dp', (tester) async {
      await _open(tester);
      for (final k in ['bodyScan.weight.save', 'bodyScan.weight.skip']) {
        expect(tester.getSize(find.byKey(Key(k))).height,
            greaterThanOrEqualTo(48),
            reason: k);
      }
    });

    testWidgets('RU error text and decimal comma input at scale 2.0',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(scanHost(const _Host(),
          locale: const Locale('ru'), textScale: 2.0));
      await tester.tap(find.byKey(const Key('opener')));
      await tester.pumpAndSettle();
      await tester.enterText(_field(), '81,4');
      await tester.ensureVisible(find.byKey(const Key("bodyScan.weight.save")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key("bodyScan.weight.save")));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_result(tester), 'open:logged 81.4');
    });
  });
}
