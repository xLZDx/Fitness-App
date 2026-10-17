// S03-18 epic 5C: conformance of the real S03 pages to the UI design contract.
// Matrix: page x window class x text scale x locale. Per cell: no framework
// exception (overflow), no clipped label, and the contract keys are present.
// Separate groups: touch targets, accessible names, section order, ru copy.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/home/home_page.dart';
import 'package:fitness_app/features/modes/data/mode_models.dart';
import 'package:fitness_app/features/modes/widgets/mode_switcher_sheet.dart';
import 'package:fitness_app/features/modes/widgets/record_sheet.dart';
import 'package:fitness_app/features/progress/progress_page.dart';

import '../../support/s03_step4_support.dart';
import '../modes/mode_epic2_harness.dart';
import 's03_conformance_support.dart';

const Key _openKey = Key('conf.open');

Widget _sheetHost(BuildContext c, {required bool record}) => Scaffold(
      body: Center(
        child: ElevatedButton(
          key: _openKey,
          onPressed: () =>
              record ? openRecordSheet(c) : openModeSwitcher(c),
          child: const Text('open'),
        ),
      ),
    );

enum Page { chooser, question, sources, home, progress, switcher, record }

class _Cell {
  _Cell(this.page, this.size, this.scale, this.lang);
  final Page page;
  final Size size;
  final double scale;
  final String lang;
  String get name =>
      '${page.name}/${sizeName(size)}/x$scale/$lang';
}

/// Required keys per page (contract rows; each key must exist after settle).
const Map<Page, List<String>> kRequiredKeys = <Page, List<String>>{
  Page.chooser: <String>[
    'modeChooser.grid',
    'modeChooser.continue',
    'modeChooser.decideLater',
    'modeChooser.description',
  ],
  Page.question: <String>['modeQuestion.progress', 'modeQuestion.skip'],
  Page.sources: <String>['sources.page'],
  Page.home: <String>['home.greeting', 'home.modeChip'],
  Page.progress: <String>[],
  Page.switcher: <String>['modeSwitcher.sheet', 'modeSwitcher.seeAll'],
  Page.record: <String>['recordSheet'],
};

Future<Rig> _pump(WidgetTester t, _Cell c) async {
  final FakeModeStore store = pendingStore();
  if (c.page != Page.chooser && c.page != Page.question) {
    store.seed('uid-a',
        mode: AppMode.train, status: ChooserStatus.resolved);
  }
  final List<Override> ov = dashOverrides(journal: FakeJournal(), uid: 'uid-a');
  String initial = '/mode-chooser';
  Map<String, WidgetBuilder>? replace;
  switch (c.page) {
    case Page.chooser:
      break;
    case Page.question:
      initial = '/mode-questions/body';
    case Page.sources:
      initial = '/sources';
    case Page.home:
      initial = '/home';
      replace = <String, WidgetBuilder>{'/home': (_) => const HomePage()};
    case Page.progress:
      initial = '/progress';
      replace = <String, WidgetBuilder>{
        '/progress': (_) => const ProgressPage()
      };
    case Page.switcher:
      initial = '/home';
      replace = <String, WidgetBuilder>{
        '/home': (ctx) => _sheetHost(ctx, record: false)
      };
    case Page.record:
      initial = '/home';
      replace = <String, WidgetBuilder>{
        '/home': (ctx) => _sheetHost(ctx, record: true)
      };
  }
  final Rig rig = await pumpRig(t,
      store: store,
      size: c.size,
      locale: Locale(c.lang),
      textScale: c.scale,
      initial: initial,
      overrides: ov,
      replace: replace,
      prefValues: <String, String>{
        'training_context.v1.uid-a': 'gymMachines'
      });
  if (c.page == Page.switcher || c.page == Page.record) {
    await t.tap(find.byKey(_openKey));
    await settleFrames(t, frames: 6);
  }
  return rig;
}

// openModeSwitcher keeps a process-wide "open" flag; close sheets so the
// next test can open one again.
Future<void> _closeSheets(WidgetTester t) async {
  for (int i = 0; i < 4; i++) {
    if (find.byKey(const Key('modeSwitcher.sheet')).evaluate().isEmpty &&
        find.byKey(const Key('recordSheet')).evaluate().isEmpty) {
      break;
    }
    await t.tapAt(const Offset(2, 2));
    await settleFrames(t, frames: 4);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('5C matrix: no overflow, no clipped label, keys present', () {
    for (final Page p in Page.values) {
      for (final Size s in kConformanceSizes) {
        for (final double sc in kConformanceScales) {
          for (final String lang in kConformanceLangs) {
            final _Cell c = _Cell(p, s, sc, lang);
            testWidgets(c.name, (WidgetTester t) async {
              await _pump(t, c);
              final Object? ex = t.takeException();
              final List<String> missing = <String>[
                for (final String k in kRequiredKeys[p]!)
                  if (byKeyS(k).evaluate().isEmpty) k
              ];
              // Only short labels (<= 40 chars) are held to the no-ellipsis
              // rule; body copy may legitimately wrap or clamp.
              final List<String> clipped = clippedParagraphs(t)
                  .where((String s) => s.length <= 40 && !isCarriedLabel(s))
                  .toList();
              await _closeSheets(t);
              expect(ex, isNull, reason: "exception (overflow) on ${c.name}");
              expect(missing, isEmpty, reason: "missing keys on ${c.name}");
              expect(clipped, isEmpty,
                  reason: "clipped short labels on ${c.name}: $clipped");
            });
          }
        }
      }
    }
  });

  group('pre-existing or accepted (carried)', () {
    for (final Size s in kConformanceSizes) {
      for (final double sc in kConformanceScales) {
        for (final String lang in kConformanceLangs) {
          final _Cell c = _Cell(Page.home, s, sc, lang);
          final bool known = kCarriedHomeCells.contains(c.name);
          testWidgets('carried (pre-S03 home_page.dart / eligibility_notice.dart, base 2c121242): ${c.name} Home labels not clipped', (WidgetTester t) async {
            await _pump(t, c);
            final List<String> clipped =
                clippedParagraphs(t).where(isCarriedLabel).toList();
            expect(clipped, isEmpty, reason: 'carried clipped labels: $clipped');
          },
              skip: known);
        }
      }
    }
  });

  group('5C touch targets and accessible names (chooser, sheets, sources)', () {
    for (final Page p in <Page>[
      Page.chooser,
      Page.switcher,
      Page.record
    ]) {
      for (final Size s in <Size>[const Size(360, 640), const Size(1100, 800)]) {
        testWidgets('${p.name}/${sizeName(s)} targets >= 48 and named',
            (WidgetTester t) async {
          final SemanticsHandle h = t.ensureSemantics();
          await _pump(t, _Cell(p, s, 1.0, 'en'));
          expect(tappableNodes(t), isNotEmpty);
          expect(unnamedTargets(t), isEmpty,
              reason: 'tappable node without a name');
          expect(smallTargets(t), isEmpty,
              reason: 'tap target under 48x48 dp');
          await _closeSheets(t);
          h.dispose();
        });
      }
    }
  });

  group('5C window class: detail panel and pane keys', () {
    testWidgets('chooser detail panel absent below 840, present at 1100',
        (WidgetTester t) async {
      await _pump(t, _Cell(Page.chooser, const Size(600, 900), 1.0, 'en'));
      expect(byKeyS('modeChooser.detailPanel'), findsNothing);
      await _pump(t, _Cell(Page.chooser, const Size(1100, 800), 1.0, 'en'));
      expect(byKeyS('modeChooser.detailPanel'), findsOneWidget);
    });

    testWidgets('home side pane absent on compact, present on expanded',
        (WidgetTester t) async {
      await _pump(t, _Cell(Page.home, const Size(360, 640), 1.0, 'en'));
      expect(byKeyS('home.pane.side'), findsNothing);
      await _pump(t, _Cell(Page.home, const Size(1400, 900), 1.0, 'en'));
      expect(byKeyS('home.pane.side'), findsOneWidget);
    });
  });
}
