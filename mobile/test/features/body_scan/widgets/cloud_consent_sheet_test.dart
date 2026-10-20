import 'package:flutter/material.dart';
import "package:flutter/semantics.dart";
import "package:flutter/services.dart";
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/body_scan/widgets/cloud_consent_sheet.dart';

import '../support/scan_test_support.dart';

List<String> _labels(WidgetTester tester) {
  final out = <String>[];
  void walk(SemanticsNode n) {
    if (n.label.isNotEmpty) out.add(n.label);
    n.visitChildren((c) {
      walk(c);
      return true;
    });
  }

  walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  return out;
}

class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool? result;
  int shown = 0;
  @override
  Widget build(BuildContext context) => Center(
        child: ElevatedButton(
          key: const Key('opener'),
          onPressed: () async {
            shown++;
            final r = await CloudConsentSheet.show(context);
            setState(() => result = r);
          },
          child: Text('Open consent ${result ?? "none"}'),
        ),
      );
}

Future<void> _open(WidgetTester tester, {Locale locale = const Locale('en')}) async {
  await tester.pumpWidget(scanHost(const _Host(), locale: locale));
  await tester.tap(find.byKey(const Key('opener')));
  await tester.pumpAndSettle();
}

String _result(WidgetTester tester) => tester
    .widget<Text>(find.descendant(
        of: find.byKey(const Key('opener')), matching: find.byType(Text)))
    .data!;

void main() {
  testWidgets('shows the separate upload consent with the honest caveats',
      (tester) async {
    await _open(tester);
    expect(find.text('Send photos for analysis?'), findsOneWidget);
    expect(find.textContaining('The server cannot verify the blurring'),
        findsOneWidget);
    expect(find.textContaining('tattoos or scars'), findsOneWidget);
    expect(find.text('Agree and upload'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('Agree resolves true', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const Key('bodyScan.cloud.agree')));
    await tester.pumpAndSettle();
    expect(find.text('Send photos for analysis?'), findsNothing);
    expect(_result(tester), 'Open consent true');
  });

  testWidgets('Not now resolves false', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const Key('bodyScan.cloud.decline')));
    await tester.pumpAndSettle();
    expect(_result(tester), 'Open consent false');
  });

  testWidgets('dismissing by tapping the barrier is a refusal, not consent',
      (tester) async {
    await _open(tester);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Send photos for analysis?'), findsNothing);
    expect(_result(tester), 'Open consent false');
  });

  testWidgets('system back dismisses as a refusal', (tester) async {
    await _open(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_result(tester), 'Open consent false');
  });

  testWidgets('initial focus is on the heading', (tester) async {
    await _open(tester);
    final focus = FocusManager.instance.primaryFocus;
    expect(focus, isNotNull);
    final ctx = focus!.context!;
    expect(
        find.descendant(
            of: find.byWidget(ctx.widget),
            matching: find.byKey(const Key('bodyScan.cloud.title'))),
        findsOneWidget);
  });

  testWidgets('the heading is a semantics header', (tester) async {
    final h = tester.ensureSemantics();
    await _open(tester);
    final node = tester.getSemantics(find.byKey(const Key('bodyScan.cloud.title')));
    expect(node.hasFlag(SemanticsFlag.isHeader), isTrue);
    h.dispose();
  });

  testWidgets("the page behind is excluded from semantics while open",
      (tester) async {
    final h = tester.ensureSemantics();
    bool behind() => _labels(tester).any((l) => l.contains("Open consent"));
    await tester.pumpWidget(scanHost(const _Host()));
    expect(behind(), isTrue);
    await tester.tap(find.byKey(const Key("opener")));
    await tester.pumpAndSettle();
    expect(behind(), isFalse);
    expect(_labels(tester), contains("Agree and upload"));
    await tester.tap(find.byKey(const Key("bodyScan.cloud.decline")));
    await tester.pumpAndSettle();
    expect(behind(), isTrue);
    h.dispose();
  });

  testWidgets("focus returns to the keyboard-focused trigger after closing",
      (tester) async {
    await tester.pumpWidget(scanHost(const _Host()));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(CloudConsentSheet), findsOneWidget);
    await tester.tap(find.byKey(const Key("bodyScan.cloud.decline")));
    await tester.pumpAndSettle();
    final owner = FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<ElevatedButton>();
    expect(owner?.key, const Key("opener"));
  });

  testWidgets('buttons are at least 48 dp', (tester) async {
    await _open(tester);
    for (final k in ['bodyScan.cloud.agree', 'bodyScan.cloud.decline']) {
      final s = tester.getSize(find.byKey(Key(k)));
      expect(s.height, greaterThanOrEqualTo(48), reason: k);
      expect(s.width, greaterThanOrEqualTo(48), reason: k);
    }
  });

  testWidgets('each show opens one sheet', (tester) async {
    await _open(tester);
    expect(find.byType(CloudConsentSheet), findsOneWidget);
    await tester.tap(find.byKey(const Key('bodyScan.cloud.agree')));
    await tester.pumpAndSettle();
    expect(find.byType(CloudConsentSheet), findsNothing);
    await tester.tap(find.byKey(const Key('opener')));
    await tester.pumpAndSettle();
    expect(find.byType(CloudConsentSheet), findsOneWidget);
  });

  testWidgets('RU at scale 2.0 scrolls instead of overflowing',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        scanHost(const _Host(), locale: const Locale('ru'), textScale: 2.0));
    await tester.tap(find.byKey(const Key('opener')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('bodyScan.cloud.title')), findsOneWidget);
  });
}
