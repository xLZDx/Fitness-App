// ProfessionalNotice (SAFE-12, D-55): one calm notice, never a reason, no
// numbers, no diagnosis words. EN and RU.
import 'package:fitness_app/features/nutrition_plan/widgets/professional_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'plan_widget_host.dart';

void main() {
  Future<void> pump(WidgetTester tester, Locale locale) async {
    tallSurface(tester);
    await tester.pumpWidget(
        planApp(const Scaffold(body: ProfessionalNotice()), locale: locale));
    await tester.pump();
  }

  List<String> allTexts(WidgetTester tester) => [
        for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? ''
      ];

  testWidgets('EN: title and body only, two texts', (tester) async {
    await pump(tester, const Locale('en'));
    final texts = allTexts(tester);
    expect(texts.length, 2);
    expect(texts.first, 'We cannot set nutrition targets for you here');
    expect(texts.last, startsWith('For your situation, a doctor or registered dietitian'));
  });

  testWidgets('the notice carries no digits (no kcal, no grams, no steps)',
      (tester) async {
    for (final l in const [Locale('en'), Locale('ru')]) {
      await pump(tester, l);
      for (final t in allTexts(tester)) {
        expect(RegExp(r'\d').hasMatch(t), isFalse, reason: '$l: $t');
      }
    }
  });

  testWidgets('the notice states no reason (no age, pregnancy, diagnosis)',
      (tester) async {
    await pump(tester, const Locale('en'));
    final joined = allTexts(tester).join(' ').toLowerCase();
    for (final w in [
      'pregnan',
      'under 18',
      'age',
      'eating disorder',
      'surgery',
      'because',
      'diagnos'
    ]) {
      expect(joined.contains(w), isFalse, reason: w);
    }
  });

  testWidgets('RU: Russian title, body mentions doctor or dietitian',
      (tester) async {
    await pump(tester, const Locale('ru'));
    final texts = allTexts(tester);
    expect(texts.first, 'Мы не можем задать здесь цели по питанию');
    expect(texts.last, startsWith('В вашей ситуации цели по питанию лучше определит врач или диетолог.'));
  });

  testWidgets('the title is a semantics header', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, const Locale('en'));
    final node = tester
        .getSemantics(find.text('We cannot set nutrition targets for you here'));
    // ignore: deprecated_member_use
    expect(node.hasFlag(SemanticsFlag.isHeader), isTrue);
    handle.dispose();
  });

  testWidgets('offers no action: no buttons', (tester) async {
    await pump(tester, const Locale('en'));
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });
}
