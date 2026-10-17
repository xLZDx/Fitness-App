import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/shared/widgets/hud/hud_scaffold.dart';
import 'package:fitness_app/shared/widgets/shell_destinations.dart';

import '../../support/s03_shell_harness.dart';

void main() {
  test('AC-SH-1 exactly five destinations in order with the contract labels',
      () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(kShellDestinations.map((d) => d.path).toList(), kTabPaths);
    expect(kShellDestinations.map((d) => d.labelOf(l10n)).toList(), <String>[
      l10n.homeHome,
      l10n.navWorkouts,
      l10n.navScan,
      l10n.progressProgress,
      l10n.profileProfile,
    ]);
    final ru = await AppLocalizations.delegate.load(const Locale('ru'));
    expect(kShellDestinations[1].labelOf(ru), ru.navWorkouts);
    expect(kShellDestinations[2].labelOf(ru), ru.navScan);
  });

  group('AC-SH-2 system Back', () {
    late List<MethodCall> calls;
    setUp(() {
      calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    int pops() => calls.where((c) => c.method == 'SystemNavigator.pop').length;

    for (final tab in const ['workouts', 'scan', 'progress', 'profile']) {
      testWidgets('AC-SH-2/from${tab[0].toUpperCase()}${tab.substring(1)}',
          (t) async {
        final f = await pumpShell(t, initial: '/$tab');
        expect(f.location, '/$tab');
        await t.binding.handlePopRoute();
        await t.pump();
        await t.pump(const Duration(milliseconds: 50));
        expect(f.location, '/home');
        expect(pops(), 0, reason: 'Back from a tab must not leave the app');
      });
    }

    testWidgets('AC-SH-2/onHome', (t) async {
      final f = await pumpShell(t);
      await t.binding.handlePopRoute();
      await t.pump();
      expect(f.location, '/home');
      expect(pops(), 1, reason: 'Back on /home is handed to the system once');
    });
  });

  testWidgets('AC-SH-3 (PARTIAL: widget level) bar is built from its list',
      (t) async {
    // The shell has no injection seam for the destination list (see findings);
    // the bar widget itself must render exactly the list it is given.
    int? tapped;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: HudNavBar(
          items: const <HudNavItem>[
            HudNavItem(icon: Icons.home, label: 'A'),
            HudNavItem(icon: Icons.build, label: 'B'),
            HudNavItem(icon: Icons.cake, label: 'C'),
            HudNavItem(icon: Icons.dns, label: 'D'),
          ],
          selectedIndex: 0,
          onSelect: (i) => tapped = i,
        ),
      ),
    ));
    expect(find.text('A'), findsOneWidget);
    expect(find.text('D'.toUpperCase()), findsOneWidget);
    for (final i in <String>['A', 'B', 'C', 'D']) {
      await t.tap(find.text(i.toUpperCase()));
      expect(tapped, 'ABCD'.indexOf(i));
    }
  });

  for (final lang in const ['en', 'ru']) {
    testWidgets('DT-04-1/$lang container label and tab navigation', (t) async {
      final handle = t.ensureSemantics();
      final l10n = await AppLocalizations.delegate.load(Locale(lang));
      final f = await pumpShell(t, locale: Locale(lang));
      final bar = find.byKey(const ValueKey<String>('shell.bottomBar'));
      expect(bar, findsOneWidget);
      expect(find.bySemanticsLabel(l10n.navMainLabel), findsWidgets);
      final node = t.getSemantics(find.bySemanticsLabel(l10n.navMainLabel).first);
      expect(node.label, l10n.navMainLabel);
      for (int i = 0; i < kShellDestinations.length; i++) {
        final label = kShellDestinations[i].labelOf(l10n).toUpperCase();
        await t.tap(find.descendant(of: bar, matching: find.text(label)));
        await t.pump();
        await t.pump(const Duration(milliseconds: 50));
        expect(f.location, kShellDestinations[i].path);
        expect(t.widget<HudNavBar>(find.byType(HudNavBar)).selectedIndex, i);
      }
      handle.dispose();
    });
  }

  test('DT-04-2 (PARTIAL: pure) selection derives from the path', () {
    expect(shellDestinationIndexFor('/progress'), 3);
    expect(shellDestinationIndexFor('/progress/detail'), 3);
    expect(shellDestinationIndexFor('/profile'), 4);
    expect(shellDestinationIndexFor('/unknown'), 0);
  });
}
