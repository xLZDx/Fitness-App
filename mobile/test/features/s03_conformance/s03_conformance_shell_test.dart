// S03-18 epic 5C: shell navigation per window class (bar vs rail, dock),
// no overflow at text scale 2.0, tap target size of the navigation items.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsHandle;
import 'package:flutter_test/flutter_test.dart';

import '../../support/s03_shell_harness.dart';
import 's03_conformance_support.dart';

Finder _k(String k) => find.byKey(ValueKey<String>(k));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // usesRail = expanded (>= 840) or medium and short; 600x900 is a bar.
  const Map<String, bool> rail = <String, bool>{
    '360x640': false,
    '600x900': false,
    '1100x800': true,
    '1400x900': true,
  };

  for (final Size s in kConformanceSizes) {
    for (final double sc in kConformanceScales) {
      for (final String lang in kConformanceLangs) {
        final String name = '${sizeName(s)}/x$sc/$lang';
        testWidgets('shell $name: rail xor bottom bar, no overflow',
            (WidgetTester t) async {
          await pumpShell(t, size: s, textScale: sc, locale: Locale(lang));
          expect(t.takeException(), isNull, reason: 'overflow on $name');
          final bool wantRail = rail[sizeName(s)]!;
          expect(_k('shell.rail').evaluate().isNotEmpty, wantRail,
              reason: 'rail presence on $name');
          expect(_k('shell.bottomBar').evaluate().isNotEmpty, !wantRail,
              reason: 'bottom bar presence on $name');
          expect(_k('shell.rail.record').evaluate().isNotEmpty, wantRail,
              reason: 'rail record slot on $name');
          if (wantRail) {
            expect(_k('shell.dock'), findsNothing,
                reason: 'the dock is not shown beside a rail ($name)');
          }
          expect(clippedParagraphs(t).where((String x) => x.length <= 40 && !isCarriedLabel(x)),
              isEmpty,
              reason: 'clipped rail/bar labels on $name');
        });
      }
    }
  }

  for (final Size s in kConformanceSizes) {
    for (final double sc in kConformanceScales) {
      for (final String lang in kConformanceLangs) {
        final String name = '${sizeName(s)}/x$sc/$lang';
        testWidgets('carried (accepted ellipsis, hud_scaffold.dart:375, base 2c121242): shell $name bar labels not clipped',
            (WidgetTester t) async {
          await pumpShell(t, size: s, textScale: sc, locale: Locale(lang));
          final List<String> clipped =
              clippedParagraphs(t).where(isCarriedLabel).toList();
          expect(clipped, isEmpty, reason: 'clipped bar labels: $clipped');
        },
            skip: kCarriedShellCells.contains(name));
      }
    }
  }

  for (final Size s in <Size>[const Size(360, 640), const Size(1100, 800)]) {
    testWidgets('shell ${sizeName(s)}: navigation targets >= 48 and named',
        (WidgetTester t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await pumpShell(t, size: s);
      expect(unnamedTargets(t), isEmpty);
      expect(smallTargets(t), isEmpty);
      h.dispose();
    });
  }
}
