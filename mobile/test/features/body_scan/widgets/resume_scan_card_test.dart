import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/body_scan/widgets/resume_scan_card.dart';

import '../support/scan_test_support.dart';

class _Taps {
  final List<String> log = [];
  VoidCallback cb(String n) => () => log.add(n);
}

Finder _k(String key) => find.byKey(Key(key));

Future<_Taps> _pending(WidgetTester tester,
    {Locale locale = const Locale('en'), double scale = 1.0}) async {
  final t = _Taps();
  await tester.pumpWidget(scanHost(
    ResumeScanCard.pending(onResume: t.cb('resume'), onCancel: t.cb('cancel')),
    locale: locale,
    textScale: scale,
  ));
  return t;
}

Future<_Taps> _failed(WidgetTester tester,
    {Locale locale = const Locale('en'), double scale = 1.0}) async {
  final t = _Taps();
  await tester.pumpWidget(scanHost(
    SingleChildScrollView(
      child: ResumeScanCard.failed(
          onRetry: t.cb("retry"),
          onKeep: t.cb("keep"),
          onDelete: t.cb("delete")),
    ),
    locale: locale,
    textScale: scale,
  ));
  return t;
}

void main() {
  group('pending variant', () {
    testWidgets('shows the finish-your-scan card with Resume and Cancel only',
        (tester) async {
      await _pending(tester);
      expect(_k('bodyScan.resumeCard'), findsOneWidget);
      expect(_k('bodyScan.failedCard'), findsNothing);
      expect(find.text('Finish your scan'), findsOneWidget);
      expect(find.text('A scan is waiting to be completed.'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(_k('bodyScan.failed.retry'), findsNothing);
      expect(_k('bodyScan.failed.keep'), findsNothing);
      expect(_k('bodyScan.failed.delete'), findsNothing);
    });

    testWidgets('Resume and Cancel each fire only their callback',
        (tester) async {
      final t = await _pending(tester);
      await tester.tap(_k('bodyScan.resume.resume'));
      expect(t.log, ['resume']);
      await tester.tap(_k('bodyScan.resume.cancel'));
      expect(t.log, ['resume', 'cancel']);
    });
  });

  group('terminal failure variant (D-78)', () {
    testWidgets('offers Retry, Keep on this device and Delete scan',
        (tester) async {
      await _failed(tester);
      expect(_k('bodyScan.failedCard'), findsOneWidget);
      expect(_k('bodyScan.resumeCard'), findsNothing);
      expect(find.text('The scan could not be completed'), findsOneWidget);
      expect(
          find.text(
              'Your photos are still on this phone. You can try again, keep them here, or delete the scan.'),
          findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Keep on this device'), findsOneWidget);
      expect(find.text('Delete scan'), findsOneWidget);
      expect(_k('bodyScan.resume.resume'), findsNothing);
    });

    testWidgets('each of the three actions reaches its own callback',
        (tester) async {
      final t = await _failed(tester);
      await tester.tap(_k('bodyScan.failed.retry'));
      await tester.tap(_k('bodyScan.failed.keep'));
      await tester.tap(_k('bodyScan.failed.delete'));
      expect(t.log, ['retry', 'keep', 'delete']);
    });

    testWidgets('failure is shown by icon plus text, not colour only',
        (tester) async {
      await _failed(tester);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      await _pending(tester);
      expect(find.byIcon(Icons.pending_actions), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });
  });

  group('accessibility', () {
    testWidgets('both titles are headers', (tester) async {
      final h = tester.ensureSemantics();
      await _pending(tester);
      expect(
          tester
              .getSemantics(find.text('Finish your scan'))
              .hasFlag(SemanticsFlag.isHeader),
          isTrue);
      await _failed(tester);
      expect(
          tester
              .getSemantics(find.text('The scan could not be completed'))
              .hasFlag(SemanticsFlag.isHeader),
          isTrue);
      h.dispose();
    });

    testWidgets('all five actions are at least 48 dp', (tester) async {
      await _pending(tester);
      for (final k in ['bodyScan.resume.resume', 'bodyScan.resume.cancel']) {
        expect(tester.getSize(_k(k)).height, greaterThanOrEqualTo(48),
            reason: k);
      }
      await _failed(tester);
      for (final k in [
        'bodyScan.failed.retry',
        'bodyScan.failed.keep',
        'bodyScan.failed.delete'
      ]) {
        expect(tester.getSize(_k(k)).height, greaterThanOrEqualTo(48),
            reason: k);
      }
    });

    testWidgets('RU failed card at scale 2.0 wraps its buttons, no overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _failed(tester, locale: const Locale('ru'), scale: 2.0);
      expect(tester.takeException(), isNull);
      expect(find.text('Delete scan'), findsNothing);
      expect(_k('bodyScan.failed.delete'), findsOneWidget);
    });
  });
}
