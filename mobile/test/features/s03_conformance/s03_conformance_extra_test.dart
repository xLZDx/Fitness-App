// S03-18 epic 5C, second batch: K scans of S03 sources, RTL smoke, safe-area
// insets on the shell, pane widths (AC-LS-9), rotation with a sheet open
// (DT-18-4), narrow Russian layout at 320 dp (DT-18-3).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' show FakeViewPadding;
import 'package:flutter_riverpod/flutter_riverpod.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/home/home_page.dart';
import 'package:fitness_app/features/modes/data/mode_models.dart';
import 'package:fitness_app/features/modes/widgets/mode_switcher_sheet.dart';
import 'package:fitness_app/features/progress/progress_page.dart';

import '../../support/s03_shell_harness.dart' as sh;
import '../../support/s03_step4_support.dart';
import '../modes/mode_epic2_harness.dart';
import 's03_conformance_support.dart';

/// Source files and directories that S03 added (anchor files included).
const List<String> kS03Dirs = <String>['lib/features/modes'];
const List<String> kS03Files = <String>[
  'lib/core/router/s03_routes.dart',
  'lib/shared/widgets/dock_widgets.dart',
  'lib/shared/widgets/shell_dock.dart',
  'lib/shared/widgets/shell_layout.dart',
  'lib/shared/widgets/shell_insets.dart',
  'lib/shared/widgets/hud/hud_side_rail.dart',
];

List<File> s03Sources() {
  final List<File> out = <File>[];
  for (final String d in kS03Dirs) {
    out.addAll(Directory(d)
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart')));
  }
  for (final String f in kS03Files) {
    out.add(File(f));
  }
  return out;
}

/// Lines (path:line) of [files] matching [re], comment lines skipped.
List<String> scan(List<File> files, RegExp re) {
  final List<String> hits = <String>[];
  for (final File f in files) {
    final List<String> lines = f.readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].trimLeft().startsWith('//')) continue;
      if (re.hasMatch(lines[i])) {
        hits.add('${f.path}:${i + 1}: ${lines[i].trim()}');
      }
    }
  }
  return hits;
}

Future<void> _home(WidgetTester t, Size size,
    {double scale = 1.0,
    String lang = 'en',
    TextDirection dir = TextDirection.ltr}) async {
  final FakeModeStore store = FakeModeStore()
    ..seed('uid-a', mode: AppMode.train, status: ChooserStatus.resolved);
  await pumpRig(t,
      store: store,
      size: size,
      locale: Locale(lang),
      textScale: scale,
      initial: '/home',
      overrides: <Override>[
        ...dashOverrides(journal: FakeJournal(), uid: 'uid-a')
      ],
      replace: <String, WidgetBuilder>{
        '/home': (_) =>
            Directionality(textDirection: dir, child: const HomePage())
      },
      prefValues: <String, String>{'training_context.v1.uid-a': 'gymMachines'});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('K scans of the S03 source set', () {
    test('DT-18-7 scan set not empty or truncated; scanner sees a sentinel', () {
      final List<File> files = s03Sources();
      expect(files.length, greaterThanOrEqualTo(20));
      final Set<String> names =
          files.map((File f) => f.path.replaceAll('\\', '/')).toSet();
      for (final String a in <String>[
        'lib/features/modes/pages/mode_chooser_page.dart',
        'lib/features/modes/pages/sources_page.dart',
        'lib/shared/widgets/hud/hud_side_rail.dart',
        'lib/shared/widgets/dock_widgets.dart',
      ]) {
        expect(names.any((String n) => n.endsWith(a)), isTrue, reason: a);
      }
      for (final String d in kS03Dirs) {
        expect(Directory(d).listSync(recursive: true), isNotEmpty);
      }
      final File tmp =
          File('${Directory.systemTemp.path}/s03_sentinel_scan.dart')
            ..writeAsStringSync('final x = onLongPress;\n');
      addTearDown(() => tmp.deleteSync());
      expect(scan(<File>[tmp], RegExp(r'onLongPress')), hasLength(1));
    });

    test('AC-SH-6b no permission or location package is imported', () {
      expect(
          scan(
              s03Sources(),
              RegExp(
                  r"^import 'package:(permission_handler|geolocator|location|camera|image_picker)")),
          isEmpty);
    });

    test('AC-KB-6 no gesture-only path', () {
      expect(
          scan(
              s03Sources(),
              RegExp(
                  r'onLongPress|onHorizontalDrag|onScale|Dismissible|onPan')),
          isEmpty);
    });

    test('AC-FAM-2k no Cupertino widget', () {
      expect(scan(s03Sources(), RegExp(r'Cupertino')), isEmpty);
    });

    test('AC-A11Y-8 no raw colour literal or Colors.* (except transparent) in S03 files', () {
      expect(scan(s03Sources(), RegExp(r'Color\(0x|Colors\.(?!transparent)')), isEmpty);
    });

    test('AC-RET-1a no forbidden retention wording in S03 en strings', () {
      final String arb = File('lib/l10n/app_en.arb').readAsStringSync();
      final RegExp key = RegExp(
          r'^\s*"((mode|source|sources|strip|record)[A-Za-z0-9]*)":\s*"(.*)",?\s*$');
      final List<String> bad = <String>[];
      for (final String l in arb.split('\n')) {
        final RegExpMatch? m = key.firstMatch(l);
        if (m == null) continue;
        final String v = m.group(3)!.toLowerCase();
        if (RegExp(r'never keep|forever|indefinitely').hasMatch(v) ||
            (v.contains('retention') && v.contains('never'))) {
          bad.add(m.group(1)!);
        }
      }
      expect(bad, isEmpty);
    });
  });

  group('RTL smoke', () {
    for (final Size s in <Size>[const Size(360, 800), const Size(1100, 800)]) {
      testWidgets('Home rtl ${sizeName(s)}: no exception',
          (WidgetTester t) async {
        await _home(t, s, dir: TextDirection.rtl);
        expect(t.takeException(), isNull);
        expect(byKeyS('home.greeting'), findsWidgets);
      });
    }
    testWidgets('Home rtl 1100x800: side pane is left of the main pane',
        (WidgetTester t) async {
      await _home(t, const Size(1100, 800), dir: TextDirection.rtl);
      expect(t.takeException(), isNull);
      final double main = t.getCenter(byKeyS('home.pane.main')).dx;
      final double side = t.getCenter(byKeyS('home.pane.side')).dx;
      expect(side, lessThan(main));
    });
  });

  group('Safe-area insets on the shell (AC-FAM-3)', () {
    testWidgets('iPhone insets: bottom bar stays above the home indicator',
        (WidgetTester t) async {
      t.view.padding = const FakeViewPadding(top: 59, bottom: 34);
      t.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
      addTearDown(t.view.resetPadding);
      addTearDown(t.view.resetViewPadding);
      await sh.pumpShell(t, size: const Size(390, 844));
      expect(t.takeException(), isNull);
      final Rect label = t.getRect(find.text('HOME'));
      expect(label.bottom, lessThanOrEqualTo(844 - 34 + 0.5));
    });

    testWidgets('mac title area: rail record slot starts below the top inset',
        (WidgetTester t) async {
      t.view.padding = const FakeViewPadding(top: 28);
      t.view.viewPadding = const FakeViewPadding(top: 28);
      addTearDown(t.view.resetPadding);
      addTearDown(t.view.resetViewPadding);
      await sh.pumpShell(t, size: const Size(1100, 760));
      expect(t.takeException(), isNull);
      final Rect rec =
          t.getRect(find.byKey(const ValueKey<String>('shell.rail.record')));
      expect(rec.top, greaterThanOrEqualTo(28 - 0.5));
    });
  });

  group('AC-LS-9 panes', () {
    testWidgets('chooser has its detail panel at exactly 840 (scale 1.0)',
        (WidgetTester t) async {
      await pumpRig(t, store: pendingStore(), size: const Size(840, 800));
      expect(t.takeException(), isNull);
      expect(byKeyS('modeChooser.detailPanel'), findsOneWidget);
    });
    testWidgets('chooser has no detail panel at 839', (WidgetTester t) async {
      await pumpRig(t, store: pendingStore(), size: const Size(839, 800));
      expect(t.takeException(), isNull);
      expect(byKeyS('modeChooser.detailPanel'), findsNothing);
    });
    for (final double w in <double>[1100, 1200]) {
      testWidgets('home ${w.toInt()}x800 scale 1.0 has two panes, no overflow',
          (WidgetTester t) async {
        await _home(t, Size(w, 800));
        expect(t.takeException(), isNull);
        expect(byKeyS('home.pane.main'), findsOneWidget);
        expect(byKeyS('home.pane.side'), findsOneWidget);
      });
    }
    testWidgets('home 840 scale 2.0 ru: no overflow, no side pane',
        (WidgetTester t) async {
      await _home(t, const Size(840, 800), scale: 2.0, lang: 'ru');
      expect(t.takeException(), isNull);
      expect(byKeyS('home.pane.side'), findsNothing);
    });
    testWidgets('progress 900 scale 1.3 ru: no exception',
        (WidgetTester t) async {
      final FakeModeStore store = FakeModeStore()
        ..seed('uid-a', mode: AppMode.train, status: ChooserStatus.resolved);
      await pumpRig(t,
          store: store,
          size: const Size(900, 800),
          locale: const Locale('ru'),
          textScale: 1.3,
          initial: '/progress',
          overrides: <Override>[
            ...dashOverrides(journal: FakeJournal(), uid: 'uid-a')
          ],
          replace: <String, WidgetBuilder>{
            '/progress': (_) => const ProgressPage()
          });
      expect(t.takeException(), isNull);
    });
  });

  group('DT-18-3 / DT-18-4', () {
    testWidgets('DT-18-3 chooser ru 320 dp scale 2.0: no exception',
        (WidgetTester t) async {
      await pumpRig(t,
          store: pendingStore(),
          size: const Size(320, 640),
          locale: const Locale('ru'),
          textScale: 2.0);
      expect(t.takeException(), isNull);
    });

    testWidgets('DT-18-4 rotation with the switcher open keeps one surface',
        (WidgetTester t) async {
      final FakeModeStore store = FakeModeStore()
        ..seed('uid-a', mode: AppMode.train, status: ChooserStatus.resolved);
      await pumpRig(t,
          store: store,
          initial: '/home',
          replace: <String, WidgetBuilder>{
            '/home': (BuildContext c) => Scaffold(
                body: Center(
                    child: ElevatedButton(
                        key: const Key('conf.open'),
                        onPressed: () => openModeSwitcher(c),
                        child: const Text('open'))))
          },
          prefValues: <String, String>{
            'training_context.v1.uid-a': 'gymMachines'
          });
      await t.tap(find.byKey(const Key('conf.open')));
      await settleFrames(t, frames: 6);
      expect(byKeyS('modeSwitcher.sheet'), findsOneWidget);
      t.view.physicalSize = const Size(800, 360);
      await settleFrames(t, frames: 6);
      final Object? ex = t.takeException();
      final int sheets = byKeyS('modeSwitcher.sheet').evaluate().length;
      for (int i = 0; i < 3; i++) {
        if (byKeyS('modeSwitcher.sheet').evaluate().isEmpty) break;
        await t.tapAt(const Offset(2, 2));
        await settleFrames(t, frames: 4);
      }
      expect(ex, isNull);
      expect(sheets, 1);
      expect(store.writes, isEmpty);
    });
  });
}
