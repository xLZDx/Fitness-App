// S03-17 scroll behaviour and the visible Back control
// (AC-KB-5, AC-KB-7 touch-only part, AC-KB-8, AC-KB-1h helper scrollToTop).
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart' show TestPointer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/shared/widgets/shell_back_button.dart';
import 'package:fitness_app/shared/widgets/shell_scroll.dart';
import 'package:fitness_app/shared/widgets/window_size.dart';

Widget _app(Widget home,
    {TargetPlatform platform = TargetPlatform.android,
    bool disableAnimations = false}) {
  return ProviderScope(child: MaterialApp(
    theme: AppTheme.dark().copyWith(platform: platform),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (BuildContext ctx, Widget? child) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(disableAnimations: disableAnimations),
      child: WindowSizeScope(child: child ?? const SizedBox.shrink()),
    ),
    home: home,
  ));
}

class _ScrollPage extends StatefulWidget {
  const _ScrollPage(this.controller);
  final ScrollController controller;
  @override
  State<_ScrollPage> createState() => _ScrollPageState();
}

class _ScrollPageState extends State<_ScrollPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ShellScrollbar(
        controller: widget.controller,
        child: ListView.builder(
          controller: widget.controller,
          itemCount: 60,
          itemBuilder: (_, int i) => SizedBox(height: 80, child: Text('r$i')),
        ),
      ),
    );
  }
}

void _size(WidgetTester t, Size s) {
  t.view.physicalSize = s;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

void main() {
  group('AC-KB-5 scrollbar and wheel', () {
    testWidgets('Expanded window shows a Scrollbar', (WidgetTester tester) async {
      _size(tester, const Size(1100, 800));
      final ScrollController c = ScrollController();
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(_ScrollPage(c)));
      await tester.pump();
      expect(find.byType(Scrollbar), findsOneWidget);
    });

    testWidgets('touch-only Compact phone adds nothing', (WidgetTester tester) async {
      _size(tester, const Size(360, 800));
      final ScrollController c = ScrollController();
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(_ScrollPage(c)));
      await tester.pump();
      expect(find.byType(Scrollbar), findsNothing);
    });

    testWidgets('Compact window with a mouse attached shows a Scrollbar',
        (WidgetTester tester) async {
      _size(tester, const Size(360, 800));
      final ScrollController c = ScrollController();
      addTearDown(c.dispose);
      final TestGesture mouse =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(10, 10));
      addTearDown(mouse.removePointer);
      await tester.pumpWidget(_app(_ScrollPage(c)));
      await tester.pump();
      expect(find.byType(Scrollbar), findsOneWidget);
    });

    testWidgets('mouse wheel scrolls the page', (WidgetTester tester) async {
      _size(tester, const Size(1100, 800));
      final ScrollController c = ScrollController();
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(_ScrollPage(c)));
      await tester.pump();
      expect(c.offset, 0);
      final TestPointer wheel = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(wheel.hover(const Offset(500, 400)));
      await tester.sendEventToBinding(wheel.scroll(const Offset(0, 200)));
      await tester.pump();
      expect(c.offset, greaterThan(0));
    });

    testWidgets('trackpad scroll-kind devices are allowed by kShellScrollDevices',
        (WidgetTester tester) async {
      expect(kShellScrollDevices, contains(PointerDeviceKind.mouse));
      expect(kShellScrollDevices, contains(PointerDeviceKind.trackpad));
      expect(kShellScrollDevices, contains(PointerDeviceKind.touch));
    });
  });

  group('scrollToTop (re-select of the selected destination)', () {
    testWidgets('animates back to the top', (WidgetTester tester) async {
      _size(tester, const Size(360, 800));
      final ScrollController c = ScrollController();
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(_ScrollPage(c)));
      c.jumpTo(900);
      await tester.pump();
      expect(c.offset, 900);
      final BuildContext ctx = tester.element(find.byType(_ScrollPage));
      scrollToTop(ctx, c);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(c.offset, lessThan(900), reason: 'animation started');
      expect(c.offset, greaterThan(0), reason: 'animated, not a jump');
      await tester.pumpAndSettle();
      expect(c.offset, 0);
    });

    testWidgets('reduced motion jumps instantly', (WidgetTester tester) async {
      _size(tester, const Size(360, 800));
      final ScrollController c = ScrollController();
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(_ScrollPage(c), disableAnimations: true));
      c.jumpTo(900);
      await tester.pump();
      final BuildContext ctx = tester.element(find.byType(_ScrollPage));
      scrollToTop(ctx, c);
      await tester.pump();
      expect(c.offset, 0);
    });

    testWidgets('a controller with no clients is a no-op',
        (WidgetTester tester) async {
      _size(tester, const Size(360, 800));
      final ScrollController c = ScrollController();
      addTearDown(c.dispose);
      await tester.pumpWidget(_app(const SizedBox()));
      final BuildContext ctx = tester.element(find.byType(SizedBox).first);
      await scrollToTop(ctx, c);
      expect(tester.takeException(), isNull);
    });
  });

  group('AC-KB-8 ShellBackButton', () {
    testWidgets('macOS shows Back as a button labelled "Back"',
        (WidgetTester tester) async {
      _size(tester, const Size(1100, 760));
      await tester.pumpWidget(_app(
          const Scaffold(body: ShellBackButton()),
          platform: TargetPlatform.macOS));
      await tester.pump();
      expect(find.byKey(kShellBackKey), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
      final SemanticsHandle h = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.byKey(kShellBackKey)),
        matchesSemantics(
            label: 'Back',
            isButton: true,
            isEnabled: true,
            hasEnabledState: true,
            isFocusable: true,
            hasTapAction: true,
            hasFocusAction: true),
      );
      expect(tester.getSize(find.byKey(kShellBackKey)).height,
          greaterThanOrEqualTo(48));
      h.dispose();
    });

    for (final TargetPlatform p in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      testWidgets('$p: takes no space and no node (AC-KB-7)',
          (WidgetTester tester) async {
        _size(tester, const Size(360, 800));
        await tester.pumpWidget(_app(
            const Scaffold(body: Center(child: ShellBackButton())),
            platform: p));
        await tester.pump();
        expect(find.byKey(kShellBackKey), findsNothing);
        expect(tester.getSize(find.byType(ShellBackButton)), Size.zero);
      });
    }

    testWidgets('alwaysVisible shows it on Android', (WidgetTester tester) async {
      _size(tester, const Size(1100, 760));
      await tester.pumpWidget(
          _app(const Scaffold(body: ShellBackButton(alwaysVisible: true))));
      await tester.pump();
      expect(find.byKey(kShellBackKey), findsOneWidget);
    });

    testWidgets('default action pops the pushed page',
        (WidgetTester tester) async {
      _size(tester, const Size(1100, 760));
      final GoRouter router = GoRouter(routes: <RouteBase>[
        GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(body: Text('below'))),
        GoRoute(
            path: '/pushed',
            builder: (_, __) => const Scaffold(
                body: ShellBackButton(alwaysVisible: true))),
        GoRoute(
            path: '/home',
            builder: (_, __) => const Scaffold(body: Text('home-page'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ));
      await tester.pump();
      router.push('/pushed');
      await tester.pumpAndSettle();
      expect(find.byKey(kShellBackKey), findsOneWidget);
      await tester.tap(find.byKey(kShellBackKey));
      await tester.pumpAndSettle();
      expect(find.text('below'), findsOneWidget);
      expect(find.byKey(kShellBackKey), findsNothing);
    });

    testWidgets('deep-linked page (nothing to pop) goes to /home',
        (WidgetTester tester) async {
      _size(tester, const Size(1100, 760));
      final GoRouter router = GoRouter(initialLocation: '/pushed', routes: <RouteBase>[
        GoRoute(
            path: '/pushed',
            builder: (_, __) => const Scaffold(
                body: ShellBackButton(alwaysVisible: true))),
        GoRoute(
            path: '/home',
            builder: (_, __) => const Scaffold(body: Text('home-page'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(kShellBackKey));
      await tester.pumpAndSettle();
      expect(find.text('home-page'), findsOneWidget);
    });

    testWidgets('a custom onPressed replaces the default',
        (WidgetTester tester) async {
      _size(tester, const Size(1100, 760));
      int calls = 0;
      await tester.pumpWidget(_app(Scaffold(
          body: ShellBackButton(alwaysVisible: true, onPressed: () => calls++))));
      await tester.pump();
      await tester.tap(find.byKey(kShellBackKey));
      await tester.pump();
      expect(calls, 1);
    });

    testWidgets('Russian label is "Назад"', (WidgetTester tester) async {
      _size(tester, const Size(1100, 760));
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark().copyWith(platform: TargetPlatform.macOS),
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: ShellBackButton()),
      ));
      await tester.pump();
      expect(find.text('Назад'), findsOneWidget);
    });

    testWidgets('Enter on the focused Back activates it (keyboard path)',
        (WidgetTester tester) async {
      _size(tester, const Size(1100, 760));
      int calls = 0;
      await tester.pumpWidget(_app(Scaffold(
          body: ShellBackButton(alwaysVisible: true, onPressed: () => calls++))));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(calls, 1);
    });
  });
}
