import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/body_scan/widgets/setup_status_panel.dart';
import 'package:fitness_app/features/progress_photos/scan/readiness_evaluator.dart';
import '../../../helpers/test_app.dart';

ReadinessResult _r({
  CheckStatus d = CheckStatus.pass,
  CheckStatus l = CheckStatus.pass,
  CheckStatus p = CheckStatus.pass,
  CheckStatus o = CheckStatus.pass,
  ReadinessHint hint = ReadinessHint.none,
}) =>
    ReadinessResult(
        distance: d, lighting: l, position: p, orientation: o, hint: hint);

Future<void> _pump(WidgetTester tester, ReadinessResult? r,
    {Locale locale = kTestLocale}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark(),
    locale: locale,
    localizationsDelegates: kTestLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SetupStatusPanel(result: r)),
  ));
}

Finder _row(String name, String status) =>
    find.byKey(Key('scan.check.$name.$status'));

String _rowText(WidgetTester tester, String name, String status) {
  final texts = tester.widgetList<Text>(
      find.descendant(of: _row(name, status), matching: find.byType(Text)));
  return texts.single.data!;
}

IconData _rowIcon(WidgetTester tester, String name, String status) =>
    tester
        .widget<Icon>(
            find.descendant(of: _row(name, status), matching: find.byType(Icon)))
        .icon!;

void main() {
  group('rows', () {
    testWidgets('four rows in the order Distance, Lighting, Position, Pose',
        (tester) async {
      await _pump(tester, _r());
      final ys = [
        for (final n in ['distance', 'lighting', 'position', 'orientation'])
          tester.getTopLeft(_row(n, 'pass')).dy,
      ];
      expect([...ys]..sort(), ys, reason: 'top to bottom in declared order');
      expect(ys.toSet(), hasLength(4));
      expect(find.byKey(const Key('scan.statusPanel')), findsOneWidget);
    });

    testWidgets('all pass: every row says OK with a check icon', (tester) async {
      await _pump(tester, _r());
      expect(_rowText(tester, 'distance', 'pass'), 'Distance: OK');
      expect(_rowText(tester, 'lighting', 'pass'), 'Light: OK');
      expect(_rowText(tester, 'position', 'pass'), 'Position: OK');
      expect(_rowText(tester, 'orientation', 'pass'), 'Turn: OK');
      for (final n in ['distance', 'lighting', 'position', 'orientation']) {
        expect(_rowIcon(tester, n, 'pass'), Icons.check_circle);
      }
    });

    testWidgets('no result yet: every row is waiting with an hourglass',
        (tester) async {
      await _pump(tester, null);
      for (final n in ['distance', 'lighting', 'position', 'orientation']) {
        expect(_rowText(tester, n, 'unknown').endsWith(': Checking'), isTrue);
        expect(_rowIcon(tester, n, 'unknown'), Icons.hourglass_empty);
      }
    });

    testWidgets('a status is never colour alone: each state has its own icon and text',
        (tester) async {
      await _pump(
          tester,
          _r(
              d: CheckStatus.fail,
              l: CheckStatus.unknown,
              p: CheckStatus.pass,
              hint: ReadinessHint.stepBack));
      expect(_rowIcon(tester, 'distance', 'fail'), Icons.error_outline);
      expect(_rowIcon(tester, 'lighting', 'unknown'), Icons.hourglass_empty);
      expect(_rowIcon(tester, 'position', 'pass'), Icons.check_circle);
      final texts = {
        _rowText(tester, 'distance', 'fail'),
        _rowText(tester, 'lighting', 'unknown'),
        _rowText(tester, 'position', 'pass'),
      };
      expect(texts, hasLength(3));
    });
  });

  group('failing rows show the specific prompt of their own hint', () {
    final cases = <ReadinessHint, (String, String, String)>{
      ReadinessHint.showFullBody: (
        'distance',
        'Distance: Step into view so your whole body is in the frame.',
        'd'
      ),
      ReadinessHint.stepBack: ('distance', 'Distance: Step back a little.', 'd'),
      ReadinessHint.stepCloser:
          ('distance', 'Distance: Step a little closer.', 'd'),
      ReadinessHint.moreLight:
          ('lighting', 'Light: It is too dark. Add more light.', 'l'),
      ReadinessHint.lessLight:
          ('lighting', 'Light: It is too bright. Reduce the glare.', 'l'),
      ReadinessHint.centerYourself:
          ('position', 'Position: Move to the middle of the frame.', 'p'),
      ReadinessHint.turnSideways:
          ('orientation', 'Turn: Turn sideways to the camera.', 'o'),
      ReadinessHint.turnAround:
          ('orientation', 'Turn: Turn your back to the camera.', 'o'),
      ReadinessHint.faceCamera: ('orientation', 'Turn: Face the camera.', 'o'),
    };
    for (final e in cases.entries) {
      testWidgets(e.key.name, (tester) async {
        final (row, text, which) = e.value;
        await _pump(
            tester,
            _r(
              d: which == 'd' ? CheckStatus.fail : CheckStatus.pass,
              l: which == 'l' ? CheckStatus.fail : CheckStatus.pass,
              p: which == 'p' ? CheckStatus.fail : CheckStatus.pass,
              o: which == 'o' ? CheckStatus.fail : CheckStatus.pass,
              hint: e.key,
            ));
        expect(_rowText(tester, row, 'fail'), text);
      });
    }

    testWidgets('a failing row whose hint belongs to another row says Adjust',
        (tester) async {
      await _pump(
          tester,
          _r(
              d: CheckStatus.fail,
              p: CheckStatus.fail,
              hint: ReadinessHint.centerYourself));
      expect(_rowText(tester, 'distance', 'fail'), 'Distance: Adjust');
      expect(_rowText(tester, 'position', 'fail'),
          'Position: Move to the middle of the frame.');
    });

    testWidgets('trackingProblem and none name no single row', (tester) async {
      await _pump(tester, _r(d: CheckStatus.fail, hint: ReadinessHint.trackingProblem));
      expect(_rowText(tester, 'distance', 'fail'), 'Distance: Adjust');
      await _pump(tester, _r(l: CheckStatus.fail, hint: ReadinessHint.none));
      expect(_rowText(tester, 'lighting', 'fail'), 'Light: Adjust');
    });
  });

  group('hint -> row mapping (pure)', () {
    test('every hint maps to exactly the row that can fix it', () {
      expect(checkOfHint(ReadinessHint.showFullBody), SetupCheck.distance);
      expect(checkOfHint(ReadinessHint.stepBack), SetupCheck.distance);
      expect(checkOfHint(ReadinessHint.stepCloser), SetupCheck.distance);
      expect(checkOfHint(ReadinessHint.moreLight), SetupCheck.lighting);
      expect(checkOfHint(ReadinessHint.lessLight), SetupCheck.lighting);
      expect(checkOfHint(ReadinessHint.centerYourself), SetupCheck.position);
      expect(checkOfHint(ReadinessHint.turnSideways), SetupCheck.orientation);
      expect(checkOfHint(ReadinessHint.turnAround), SetupCheck.orientation);
      expect(checkOfHint(ReadinessHint.faceCamera), SetupCheck.orientation);
      expect(checkOfHint(ReadinessHint.none), isNull);
      expect(checkOfHint(ReadinessHint.trackingProblem), isNull);
    });

    test('statusOfCheck reads the matching field and null without a result', () {
      final r = _r(
          d: CheckStatus.fail,
          l: CheckStatus.unknown,
          p: CheckStatus.pass,
          o: CheckStatus.fail);
      expect(statusOfCheck(r, SetupCheck.distance), CheckStatus.fail);
      expect(statusOfCheck(r, SetupCheck.lighting), CheckStatus.unknown);
      expect(statusOfCheck(r, SetupCheck.position), CheckStatus.pass);
      expect(statusOfCheck(r, SetupCheck.orientation), CheckStatus.fail);
      expect(statusOfCheck(null, SetupCheck.distance), isNull);
    });

    test('every ReadinessHint is mapped (no hint can be forgotten)', () {
      for (final h in ReadinessHint.values) {
        // Must not throw; the switch is exhaustive.
        checkOfHint(h);
      }
    });
  });

  group('accessibility and localisation', () {
    testWidgets('each row is one semantics node "label: state"', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _r(d: CheckStatus.fail, hint: ReadinessHint.stepBack));
      final labels = <String>[];
      void walk(SemanticsNode n) {
        if (n.label.isNotEmpty) labels.add(n.label);
        n.visitChildren((c) {
          walk(c);
          return true;
        });
      }

      walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
      expect(labels, containsAll([
        'Distance: Step back a little.',
        'Light: OK',
        'Position: OK',
        'Turn: OK',
      ]));
      // The icon and the text are not announced a second time.
      expect(labels.where((l) => l.contains('Light')), hasLength(1));
      handle.dispose();
    });

    testWidgets('Russian labels and states', (tester) async {
      await _pump(tester, _r(l: CheckStatus.fail, hint: ReadinessHint.moreLight),
          locale: const Locale('ru'));
      expect(_rowText(tester, 'distance', 'pass'), 'Расстояние: Готово');
      expect(_rowText(tester, 'position', 'pass'), 'Положение: Готово');
      expect(_rowText(tester, 'orientation', 'pass'), 'Поворот: Готово');
      expect(_rowText(tester, 'lighting', 'fail').startsWith('Свет: '), isTrue);
      expect(_rowText(tester, 'lighting', 'fail'), isNot('Свет: Поправьте'),
          reason: 'its own hint, not the generic text');
    });

    testWidgets('large text wraps instead of overflowing at 320 dp',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('ru'),
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!),
        home: Scaffold(
            body: SingleChildScrollView(
                child: SetupStatusPanel(
                    result: _r(
                        d: CheckStatus.fail, hint: ReadinessHint.showFullBody)))),
      ));
      expect(tester.takeException(), isNull);
    });
  });
}
