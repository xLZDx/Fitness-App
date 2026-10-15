import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/body_scan/widgets/intro_view.dart';

import '../support/scan_test_support.dart';

const _rough = 'Rough estimate from height, weight and age';
const _bodyRough =
    'This version gives a rough estimate from your height, weight and age. It does not measure your body from the photos. The photos stay on this phone.';
const _bodyPhotos =
    'Three photos are blurred on your phone, then sent to be analysed once you agree. You can delete them at any time.';
const _measurementOnly =
    'Photos and history only. Goal figures are not shown here.';

class _Calls {
  int start = 0;
  int close = 0;
}

Future<_Calls> _pump(
  WidgetTester tester, {
  required bool provisional,
  required bool measurementOnly,
  Locale locale = const Locale('en'),
  double textScale = 1.0,
}) async {
  final c = _Calls();
  await tester.pumpWidget(scanHost(
    IntroView(
      provisional: provisional,
      measurementOnly: measurementOnly,
      onStart: () => c.start++,
      onClose: () => c.close++,
    ),
    locale: locale,
    textScale: textScale,
  ));
  await tester.pump();
  return c;
}

void main() {
  testWidgets('provisional: plain-language rough-estimate label and copy',
      (tester) async {
    await _pump(tester, provisional: true, measurementOnly: false);
    expect(find.byKey(const Key('bodyScan.intro.roughLabel')), findsOneWidget);
    expect(find.text(_rough), findsOneWidget);
    expect(find.text(_bodyRough), findsOneWidget);
    expect(find.text(_bodyPhotos), findsNothing);
  });

  testWidgets('photo estimator: photo copy and no rough label', (tester) async {
    await _pump(tester, provisional: false, measurementOnly: false);
    expect(find.text(_bodyPhotos), findsOneWidget);
    expect(find.text(_bodyRough), findsNothing);
    expect(find.text(_rough), findsNothing);
    expect(find.byIcon(Icons.info_outline), findsNothing);
  });

  testWidgets('measurement only note appears only in that mode',
      (tester) async {
    await _pump(tester, provisional: false, measurementOnly: true);
    expect(find.text(_measurementOnly), findsOneWidget);
    await _pump(tester, provisional: false, measurementOnly: false);
    expect(find.text(_measurementOnly), findsNothing);
  });

  testWidgets('provisional and measurement only combine', (tester) async {
    await _pump(tester, provisional: true, measurementOnly: true);
    expect(find.text(_rough), findsOneWidget);
    expect(find.text(_measurementOnly), findsOneWidget);
  });

  testWidgets('shows the time expectation and a header title', (tester) async {
    final h = tester.ensureSemantics();
    await _pump(tester, provisional: false, measurementOnly: false);
    expect(find.text('The guided capture takes about 20 seconds.'),
        findsOneWidget);
    final title = tester.getSemantics(find.byKey(const Key('bodyScan.intro.title')));
    expect(title.hasFlag(SemanticsFlag.isHeader), isTrue);
    expect(find.text('Estimate your body composition'), findsOneWidget);
    h.dispose();
  });

  testWidgets('Start and Close each fire exactly their own callback once',
      (tester) async {
    final c = await _pump(tester, provisional: false, measurementOnly: false);
    await tester.tap(find.byKey(const Key('bodyScan.intro.start')));
    expect((c.start, c.close), (1, 0));
    await tester.tap(find.byKey(const Key('bodyScan.intro.close')));
    expect((c.start, c.close), (1, 1));
    expect(find.text('Start scan'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('both buttons are at least 48 dp', (tester) async {
    await _pump(tester, provisional: true, measurementOnly: true);
    for (final k in ['bodyScan.intro.start', 'bodyScan.intro.close']) {
      final s = tester.getSize(find.byKey(Key(k)));
      expect(s.height, greaterThanOrEqualTo(48), reason: k);
      expect(s.width, greaterThanOrEqualTo(48), reason: k);
    }
  });

  testWidgets('RU renders translated copy', (tester) async {
    await _pump(tester,
        provisional: true,
        measurementOnly: true,
        locale: const Locale('ru'));
    expect(find.text(_rough), findsNothing);
    expect(find.text('Start scan'), findsNothing);
    expect(find.byKey(const Key('bodyScan.intro.roughLabel')), findsOneWidget);
  });

  testWidgets('RU at text scale 2.0 scrolls without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester,
        provisional: true,
        measurementOnly: true,
        locale: const Locale('ru'),
        textScale: 2.0);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
        find.byKey(const Key("bodyScan.intro.close")), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('bodyScan.intro.close')), findsOneWidget);
  });
}
