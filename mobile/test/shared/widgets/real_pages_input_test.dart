// S03-17 input behaviour on the REAL S03 pages (AC-KB-8 on S-1, S-2, S-8;
// AC-KB-1g Esc on the real mode switcher; AC-KB-5 on the real Progress page).
import 'package:flutter/gestures.dart' show TestPointer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'dart:ui' show PointerDeviceKind;

import 'package:fitness_app/core/router/s03_routes.dart';
import 'package:fitness_app/features/modes/data/mode_models.dart';
import 'package:fitness_app/features/modes/widgets/mode_switcher_sheet.dart';
import 'package:fitness_app/features/progress/progress_page.dart';
import 'package:fitness_app/shared/widgets/shell_back_button.dart';

import '../../features/modes/mode_epic2_harness.dart';
import '../../support/s03_step4_support.dart';

const Key _openKey = Key('test.openSwitcher');

Widget _host(BuildContext c) => Scaffold(
      body: Center(
        child: ElevatedButton(
            key: _openKey,
            onPressed: () => openModeSwitcher(c),
            child: const Text('open')),
      ),
    );

FakeModeStore _store() => FakeModeStore()
  ..seed('uid-a', mode: AppMode.train)
  ..seed('uid-b', mode: AppMode.body);

void main() {
  group('AC-KB-8 Back on the real pages (macOS)', () {
    for (final (String name, String path) in <(String, String)>[
      ('chooser S-1', kModeChooserPath),
      ('questions S-2', '/mode-questions/body'),
      ('sources S-8', kSourcesPath),
    ]) {
      testWidgets('$name shows shell.back labelled Back on macOS',
          (WidgetTester tester) async {
        await pumpRig(tester,
            store: _store(),
            initial: path,
            size: const Size(1100, 760),
            platform: TargetPlatform.macOS,
            prefValues: <String, String>{
              'training_context.v1.uid-a': 'gymMachines'
            });
        expect(find.byKey(kShellBackKey), findsOneWidget);
        expect(
            find.descendant(
                of: find.byKey(kShellBackKey), matching: find.text('Back')),
            findsOneWidget);
      });

      testWidgets('$name has no Back control on Android (touch layout kept)',
          (WidgetTester tester) async {
        await pumpRig(tester,
            store: _store(),
            initial: path,
            size: const Size(360, 800),
            prefValues: <String, String>{
              'training_context.v1.uid-a': 'gymMachines'
            });
        expect(find.byKey(kShellBackKey), findsNothing);
      });
    }

    testWidgets('Russian chooser shows "Назад" on macOS',
        (WidgetTester tester) async {
      await pumpRig(tester,
          store: _store(),
          initial: kModeChooserPath,
          size: const Size(1100, 760),
          locale: const Locale('ru'),
          platform: TargetPlatform.macOS);
      expect(find.text('Назад'), findsOneWidget);
    });

    testWidgets('Sources Back pops to the page below',
        (WidgetTester tester) async {
      final Rig rig = await pumpRig(tester,
          store: _store(),
          initial: '/home',
          size: const Size(1100, 760),
          platform: TargetPlatform.macOS,
          replace: <String, WidgetBuilder>{'/home': _host});
      rig.router.push(kSourcesPath);
      await settleFrames(tester);
      expect(find.byKey(kShellBackKey), findsOneWidget);
      await tester.tap(find.byKey(kShellBackKey));
      await settleFrames(tester);
      expect(find.byKey(kShellBackKey), findsNothing);
      expect(find.byKey(_openKey), findsOneWidget);
    });
  });

  group('AC-KB-1g Esc on the real mode switcher', () {
    for (final Size size in <Size>[const Size(1100, 800), const Size(360, 800)]) {
      testWidgets('Esc closes the switcher alone at ${size.width.toInt()} wide',
          (WidgetTester tester) async {
        final Rig rig = await pumpRig(tester,
            store: _store(),
            initial: '/home',
            size: size,
            prefValues: <String, String>{
              'training_context.v1.uid-a': 'gymMachines'
            },
            replace: <String, WidgetBuilder>{'/home': _host});
        await tester.tap(find.byKey(_openKey));
        await settleFrames(tester, frames: 6);
        expect(byKeyS('modeSwitcher.sheet'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settleFrames(tester, frames: 6);
        expect(byKeyS('modeSwitcher.sheet'), findsNothing);
        // The page below stays; Esc did not navigate.
        expect(find.byKey(_openKey), findsOneWidget);
        expect(rig.router.routerDelegate.currentConfiguration.last.matchedLocation,
            '/home');

        // Esc again with nothing open does nothing.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settleFrames(tester, frames: 3);
        expect(find.byKey(_openKey), findsOneWidget);
      });
    }
  });

  group('AC-KB-5 real Progress page', () {
    Future<ScrollableState> pump(WidgetTester t, double w) async {
      t.view.physicalSize = Size(w, 500);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(appHost(const ProgressPage(),
          overrides: dashOverrides(journal: FakeJournal())));
      for (int i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 60));
      }
      return t.state<ScrollableState>(find.byType(Scrollable).first);
    }

    testWidgets('mouse wheel scrolls it and Expanded shows a Scrollbar',
        (WidgetTester tester) async {
      final ScrollableState s = await pump(tester, 1100);
      expect(find.byType(Scrollbar), findsWidgets);
      expect(s.position.pixels, 0);
      final TestPointer wheel = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(wheel.hover(const Offset(500, 250)));
      await tester.sendEventToBinding(wheel.scroll(const Offset(0, 200)));
      await tester.pump();
      expect(s.position.pixels, greaterThan(0));
    });

    testWidgets('touch-only phone has no Scrollbar', (WidgetTester tester) async {
      await pump(tester, 360);
      expect(find.byType(Scrollbar), findsNothing);
    });
  });
}
