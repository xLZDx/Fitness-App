// S03-17 keyboard shortcuts (AC-KB-1a..1g, 1f, DT-17-3, DT-17-4).
//
// The shared harness mounts MainShell but not AppShortcuts, and AppShortcuts
// reads the router through appRouterProvider, so this file builds its own
// MaterialApp.router with the same router both in the provider override and in
// routerConfig (exactly the shape of main.dart).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/core/router/app_router.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/workouts/state/active_session_status.dart';
import 'package:fitness_app/shared/widgets/adaptive_surface.dart';
import 'package:fitness_app/shared/widgets/app_shortcuts.dart';
import 'package:fitness_app/shared/widgets/shell_dock.dart';
import 'package:fitness_app/shared/widgets/window_size.dart';

import '../../support/s03_shell_harness.dart' show kTabPaths;

class _World {
  _World(this.tester, this.router, this.recordCalls, this.switcherCalls);
  final WidgetTester tester;
  final GoRouter router;
  final List<String> recordCalls;
  final List<String> switcherCalls;

  /// The TOPMOST route (a pushed page counts); `uri.path` is only the base
  /// location of the match list and ignores imperatively pushed pages.
  String get location =>
      router.routerDelegate.currentConfiguration.last.matchedLocation;

  ProviderContainer get container =>
      ProviderScope.containerOf(tester.element(find.byType(AppShortcuts)));
}

Future<_World> _pump(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.android,
  String initial = '/home',
  bool withTextField = false,
  bool openers = true,
  ActiveSessionStatus? session,
}) async {
  tester.view.physicalSize = const Size(1100, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final List<String> record = <String>[];
  final List<String> switcher = <String>[];

  Widget page(String p) => Scaffold(
        body: Column(children: <Widget>[
          Text('page:$p'),
          if (withTextField) const TextField(key: Key('kb.field')),
        ]),
      );

  final GoRouter router = GoRouter(
    initialLocation: initial,
    routes: <RouteBase>[
      GoRoute(
        path: '/workout/:id',
        builder: (_, GoRouterState s) => Scaffold(body: Text('workout:${s.uri}')),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const Scaffold(body: Text('settings-stub')),
      ),
      for (final String p in kTabPaths)
        GoRoute(path: p, builder: (_, __) => page(p)),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(ProviderScope(
    overrides: <Override>[
      appRouterProvider.overrideWithValue(router),
      if (openers)
        shellRecordSheetOpenerProvider.overrideWithValue(
            (BuildContext c, {GlobalKey? anchorKey}) => record.add('record')),
      if (openers)
        modeSwitcherOpenerProvider
            .overrideWithValue((BuildContext c) => switcher.add('switcher')),
      activeSessionStatusProvider.overrideWithValue(session),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark().copyWith(platform: platform),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (BuildContext ctx, Widget? child) => WindowSizeScope(
        child: AppShortcuts(child: child ?? const SizedBox.shrink()),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return _World(tester, router, record, switcher);
}

/// Presses [mods] then [key], then releases everything.
Future<void> _chord(WidgetTester tester, List<LogicalKeyboardKey> mods,
    LogicalKeyboardKey key) async {
  for (final LogicalKeyboardKey m in mods) {
    await tester.sendKeyDownEvent(m);
  }
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  for (final LogicalKeyboardKey m in mods.reversed) {
    await tester.sendKeyUpEvent(m);
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

const LogicalKeyboardKey _ctrl = LogicalKeyboardKey.controlLeft;
const LogicalKeyboardKey _meta = LogicalKeyboardKey.metaLeft;
const LogicalKeyboardKey _shift = LogicalKeyboardKey.shiftLeft;

const List<LogicalKeyboardKey> _digits = <LogicalKeyboardKey>[
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
];

void main() {
  group('AC-KB-1a tab shortcuts and the platform modifier', () {
    for (final (TargetPlatform p, LogicalKeyboardKey mod, LogicalKeyboardKey wrong)
        in <(TargetPlatform, LogicalKeyboardKey, LogicalKeyboardKey)>[
      (TargetPlatform.android, _ctrl, _meta),
      (TargetPlatform.macOS, _meta, _ctrl),
      (TargetPlatform.iOS, _meta, _ctrl),
    ]) {
      testWidgets('$p: modifier + 1..5 reaches the five tabs in order',
          (WidgetTester tester) async {
        final _World w = await _pump(tester, platform: p, initial: '/profile');
        // Visit in reverse of the order first so every target is a real change.
        for (int i = 0; i < 5; i++) {
          await _chord(tester, <LogicalKeyboardKey>[mod], _digits[i]);
          expect(w.location, kTabPaths[i], reason: '$p modifier+${i + 1}');
        }
      });

      testWidgets('$p: the other platform modifier does nothing',
          (WidgetTester tester) async {
        final _World w = await _pump(tester, platform: p);
        for (int i = 1; i < 5; i++) {
          await _chord(tester, <LogicalKeyboardKey>[wrong], _digits[i]);
          expect(w.location, '/home', reason: '$p wrong modifier+${i + 1}');
        }
      });

      testWidgets('$p: a bare digit does nothing', (WidgetTester tester) async {
        final _World w = await _pump(tester, platform: p);
        await _chord(tester, <LogicalKeyboardKey>[], _digits[2]);
        expect(w.location, '/home');
      });
    }
  });

  group('AC-KB-1b/1c Record and mode switcher', () {
    testWidgets('idle: modifier+Shift+R calls the Record opener once, no nav',
        (WidgetTester tester) async {
      final _World w = await _pump(tester, platform: TargetPlatform.macOS);
      await _chord(tester, <LogicalKeyboardKey>[_meta, _shift],
          LogicalKeyboardKey.keyR);
      expect(w.recordCalls, <String>['record']);
      expect(w.switcherCalls, isEmpty);
      expect(w.location, '/home');
    });

    testWidgets('modifier+Shift+M calls the switcher opener, not Record',
        (WidgetTester tester) async {
      final _World w = await _pump(tester, platform: TargetPlatform.macOS);
      await _chord(tester, <LogicalKeyboardKey>[_meta, _shift],
          LogicalKeyboardKey.keyM);
      expect(w.switcherCalls, <String>['switcher']);
      expect(w.recordCalls, isEmpty);
    });

    testWidgets('Record without Shift is not bound', (WidgetTester tester) async {
      final _World w = await _pump(tester, platform: TargetPlatform.macOS);
      await _chord(tester, <LogicalKeyboardKey>[_meta], LogicalKeyboardKey.keyR);
      expect(w.recordCalls, isEmpty);
    });

    testWidgets('Android uses Ctrl+Shift+R', (WidgetTester tester) async {
      final _World w = await _pump(tester);
      await _chord(tester, <LogicalKeyboardKey>[_meta, _shift],
          LogicalKeyboardKey.keyR);
      expect(w.recordCalls, isEmpty);
      await _chord(tester, <LogicalKeyboardKey>[_ctrl, _shift],
          LogicalKeyboardKey.keyR);
      expect(w.recordCalls, <String>['record']);
    });

    testWidgets('a null switcher opener is a safe no-op',
        (WidgetTester tester) async {
      final _World w = await _pump(tester, openers: false);
      await _chord(tester, <LogicalKeyboardKey>[_ctrl, _shift],
          LogicalKeyboardKey.keyM);
      await _chord(tester, <LogicalKeyboardKey>[_ctrl, _shift],
          LogicalKeyboardKey.keyR);
      expect(w.location, '/home');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'running session: Record opens the strip destination and never the '
        'start surface', (WidgetTester tester) async {
      final _World w = await _pump(
        tester,
        initial: '/progress',
        session: const ActiveSessionStatus(
          kind: ActiveSessionKind.gymWorkout,
          state: ActiveSessionState.running,
        ),
      );
      await _chord(tester, <LogicalKeyboardKey>[_ctrl, _shift],
          LogicalKeyboardKey.keyR);
      expect(w.recordCalls, isEmpty);
      expect(w.location, kActiveSessionDefaultDestination);
    });

  });

  group('AC-KB-1d modifier + [ (Back)', () {
    testWidgets('non-home tab goes to /home', (WidgetTester tester) async {
      final _World w = await _pump(tester, initial: '/progress');
      await _chord(tester, <LogicalKeyboardKey>[_ctrl],
          LogicalKeyboardKey.bracketLeft);
      expect(w.location, '/home');
    });

    testWidgets('on /home it does nothing and never quits',
        (WidgetTester tester) async {
      final _World w = await _pump(tester);
      await _chord(tester, <LogicalKeyboardKey>[_ctrl],
          LogicalKeyboardKey.bracketLeft);
      expect(w.location, '/home');
      expect(tester.takeException(), isNull);
    });

    testWidgets('pushed page is popped, returning to the page below',
        (WidgetTester tester) async {
      final _World w = await _pump(tester, initial: '/progress');
      w.router.push('/settings');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(w.location, '/settings');
      await _chord(tester, <LogicalKeyboardKey>[_ctrl],
          LogicalKeyboardKey.bracketLeft);
      await tester.pump(const Duration(milliseconds: 400));
      expect(w.location, '/progress');
    });

    testWidgets('page pushed over /progress: tab shortcuts do nothing',
        (WidgetTester tester) async {
      final _World w = await _pump(tester, initial: '/progress');
      w.router.push('/settings');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _chord(tester, <LogicalKeyboardKey>[_ctrl], _digits[1]);
      await tester.pump(const Duration(milliseconds: 400));
      expect(w.location, '/settings');
      expect(find.text('settings-stub'), findsOneWidget);
    });

    testWidgets('macOS uses Cmd+[ and ignores Ctrl+[', (WidgetTester tester) async {
      final _World w =
          await _pump(tester, platform: TargetPlatform.macOS, initial: '/scan');
      await _chord(tester, <LogicalKeyboardKey>[_ctrl],
          LogicalKeyboardKey.bracketLeft);
      expect(w.location, '/scan');
      await _chord(tester, <LogicalKeyboardKey>[_meta],
          LogicalKeyboardKey.bracketLeft);
      expect(w.location, '/home');
    });
  });

  group('AC-KB-1e guards', () {
    testWidgets('focused TextField: modifier + digit does not navigate',
        (WidgetTester tester) async {
      final _World w = await _pump(tester, withTextField: true);
      await tester.tap(find.byKey(const Key('kb.field')));
      await tester.pump();
      await _chord(tester, <LogicalKeyboardKey>[_ctrl], _digits[1]);
      expect(w.location, '/home');
      await _chord(tester, <LogicalKeyboardKey>[_ctrl, _shift],
          LogicalKeyboardKey.keyR);
      expect(w.recordCalls, isEmpty);
    });

    testWidgets('after the field loses focus the shortcut works again',
        (WidgetTester tester) async {
      final _World w = await _pump(tester, withTextField: true);
      await tester.tap(find.byKey(const Key('kb.field')));
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await _chord(tester, <LogicalKeyboardKey>[_ctrl], _digits[1]);
      expect(w.location, '/workouts');
    });

    testWidgets('open surface depth > 0 blocks tabs, Record and Back; closing '
        'restores them', (WidgetTester tester) async {
      final _World w = await _pump(tester, initial: '/progress');
      final OpenSurfaceDepth depth =
          w.container.read(openSurfaceDepthProvider.notifier);
      final int token = depth.opened();
      await tester.pump();

      await _chord(tester, <LogicalKeyboardKey>[_ctrl], _digits[1]);
      await _chord(tester, <LogicalKeyboardKey>[_ctrl, _shift],
          LogicalKeyboardKey.keyR);
      await _chord(tester, <LogicalKeyboardKey>[_ctrl],
          LogicalKeyboardKey.bracketLeft);
      expect(w.location, '/progress');
      expect(w.recordCalls, isEmpty);

      depth.closed(token);
      await tester.pump();
      await _chord(tester, <LogicalKeyboardKey>[_ctrl], _digits[1]);
      expect(w.location, '/workouts');
    });
  });

  group('AC-KB-1f settings shortcut', () {
    for (final (TargetPlatform p, bool expectPush)
        in <(TargetPlatform, bool)>[
      (TargetPlatform.iOS, true),
      (TargetPlatform.macOS, true),
      (TargetPlatform.android, false),
    ]) {
      testWidgets('$p: Cmd+, pushes /settings = $expectPush',
          (WidgetTester tester) async {
        final _World w = await _pump(tester, platform: p);
        await _chord(tester, <LogicalKeyboardKey>[_meta],
            LogicalKeyboardKey.comma);
        expect(w.location, expectPush ? '/settings' : '/home');
      });
    }

    testWidgets('Android Ctrl+, does nothing', (WidgetTester tester) async {
      final _World w = await _pump(tester);
      await _chord(tester, <LogicalKeyboardKey>[_ctrl], LogicalKeyboardKey.comma);
      expect(w.location, '/home');
    });
  });

  group('AC-KB-1g Escape', () {
    testWidgets('Esc with nothing open never navigates back',
        (WidgetTester tester) async {
      final _World w = await _pump(tester, initial: '/progress');
      await _chord(tester, <LogicalKeyboardKey>[], LogicalKeyboardKey.escape);
      expect(w.location, '/progress');
      w.router.push('/settings');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _chord(tester, <LogicalKeyboardKey>[], LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 400));
      expect(w.location, '/settings');
    });
  });

  group('DT-17-3 first-frame focus', () {
    testWidgets('modifier + 2 works with nothing clicked after the first pump',
        (WidgetTester tester) async {
      final _World w = await _pump(tester);
      await _chord(tester, <LogicalKeyboardKey>[_ctrl], _digits[1]);
      expect(w.location, '/workouts');
    });

    testWidgets('the autofocus root is not a tab stop (skipTraversal)',
        (WidgetTester tester) async {
      await _pump(tester, withTextField: true);
      await tester.tap(find.byKey(const Key('kb.field')));
      await tester.pump();
      // The text field keeps focus; the root did not steal it back.
      expect(FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>() ??
          FocusManager.instance.primaryFocus?.context?.widget,
          isA<EditableText>());
    });
  });

  group('DT-17-4 tab shortcuts only act on a shell route', () {
    testWidgets('on a pushed workout page modifier + 1..5 do nothing',
        (WidgetTester tester) async {
      final _World w = await _pump(tester, initial: '/workout/abc');
      for (int i = 0; i < 5; i++) {
        await _chord(tester, <LogicalKeyboardKey>[_ctrl], _digits[i]);
        expect(w.location, '/workout/abc', reason: 'modifier+${i + 1}');
      }
    });

    testWidgets('on /settings they do nothing either',
        (WidgetTester tester) async {
      final _World w = await _pump(tester, initial: '/settings');
      await _chord(tester, <LogicalKeyboardKey>[_ctrl], _digits[3]);
      expect(w.location, '/settings');
    });
  });
}
