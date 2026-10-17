import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/core/theme/hud_tokens.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/shared/widgets/adaptive_surface.dart';
import 'package:fitness_app/shared/widgets/hud/hud_surface.dart';
import 'package:fitness_app/shared/widgets/window_size.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../support/s03_shell_harness.dart';

const Key _open = ValueKey<String>('host.open');
const Key _content = ValueKey<String>('surface.content');
const Key _title = ValueKey<String>('surface.title');

class _Content extends StatefulWidget {
  const _Content();
  @override
  State<_Content> createState() => _ContentState();
}

class _ContentState extends State<_Content> {
  static _ContentState? last;
  int selected = -1;
  final ScrollController scroll = ScrollController();
  final List<FocusNode> nodes = List<FocusNode>.generate(30, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    last = this;
  }

  @override
  void dispose() {
    scroll.dispose();
    for (final n in nodes) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        key: _content,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Focus(
              key: _title,
              autofocus: true,
              child: Semantics(
                header: true,
                child: const Padding(
                    padding: EdgeInsets.all(12), child: Text('Surface title')),
              ),
            ),
            Flexible(
              child: ListView(
                controller: scroll,
                shrinkWrap: true,
                children: <Widget>[
                  for (int i = 0; i < 30; i++)
                    InkWell(
                      key: Key('surface.row.$i'),
                      focusNode: nodes[i],
                      onTap: () => setState(() {
                        selected = i;
                        nodes[i].requestFocus();
                      }),
                      child: SizedBox(
                          height: 56,
                          child: Text(i == selected ? 'row $i *' : 'row $i')),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _Fix {
  _Fix(this.t, this.router, this.auth, this.writes, this.openNode, this.anchorKey);
  final WidgetTester t;
  final GoRouter router;
  final StreamController<AuthUser?> auth;
  final List<String> writes;
  final FocusNode openNode;
  final GlobalKey anchorKey;
  ProviderContainer get container =>
      ProviderScope.containerOf(t.element(find.byKey(_open)));
  int get depth => container.read(openSurfaceDepthProvider);
  Rect get sheet => t.getRect(find
      .ancestor(of: find.byKey(_content), matching: find.byType(HudSheet))
      .first);
  Rect get anchor => t.getRect(find.byKey(anchorKey));
  Future<void> open() async {
    openNode.requestFocus();
    await t.pump();
    await t.tap(find.byKey(_open));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }
}

Future<_Fix> _pumpHost(
  WidgetTester t, {
  required Size size,
  AdaptiveSurfaceKind kind = AdaptiveSurfaceKind.anchored,
  Offset anchorAt = const Offset(100, 100),
  bool reduce = false,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final auth = StreamController<AuthUser?>.broadcast();
  addTearDown(auth.close);
  final writes = <String>[];
  final openNode = FocusNode();
  addTearDown(openNode.dispose);
  final anchorKey = GlobalKey();
  final router = GoRouter(routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (_, __) => Scaffold(
        body: Consumer(
          builder: (ctx, ref, _) {
            // The shell watches auth in the real app; keep it loaded here.
            ref.watch(authUserProvider);
            return Stack(children: <Widget>[
            Positioned(
              left: anchorAt.dx,
              top: anchorAt.dy,
              child: SizedBox(key: anchorKey, width: 120, height: 40),
            ),
            Positioned(
              left: 0,
              bottom: 0,
              child: ElevatedButton(
                key: _open,
                focusNode: openNode,
                onPressed: () => AdaptiveSurface.show<void>(
                  ctx,
                  (c) => const _Content(),
                  anchorKey: anchorKey,
                  kind: kind,
                  semanticLabel: 'Test surface',
                ),
                child: const Text('open'),
              ),
            ),
          ]);
          },
        ),
      ),
    ),
  ]);
  addTearDown(router.dispose);
  await t.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: <Override>[
      authUserProvider.overrideWith((ref) async* {
        yield kUserA;
        yield* auth.stream;
      }),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(disableAnimations: reduce),
        child: WindowSizeScope(child: child!),
      ),
    ),
  ));
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
  return _Fix(t, router, auth, writes, openNode, anchorKey);
}

String _sz(Size s) => '${s.width.toInt()}x${s.height.toInt()}';

bool _inside(Size win, Rect r) =>
    r.left >= 0 && r.top >= 0 && r.right <= win.width && r.bottom <= win.height;

void main() {
  group('AC-LS-8a anchored surface by class', () {
    testWidgets('AC-LS-8a/360x800 bottom sheet', (t) async {
      final f = await _pumpHost(t, size: const Size(360, 800));
      await f.open();
      expect(find.byKey(_content), findsOneWidget);
      expect(f.sheet.bottom, greaterThan(800 - 24));
      expect(f.sheet.width, greaterThan(300));
    });
    testWidgets('AC-LS-8a/700x900 bottom sheet at most 560', (t) async {
      final f = await _pumpHost(t, size: const Size(700, 900));
      await f.open();
      expect(f.sheet.width, lessThanOrEqualTo(560));
      expect(f.sheet.bottom, greaterThan(900 - 24));
    });
    testWidgets('AC-LS-8a/1100x800 popover under the anchor', (t) async {
      final f = await _pumpHost(t, size: const Size(1100, 800));
      await f.open();
      final r = f.sheet;
      expect(r.top, greaterThanOrEqualTo(f.anchor.bottom));
      expect(r.width, lessThanOrEqualTo(360));
      expect(_inside(const Size(1100, 800), r), isTrue, reason: '$r');
      expect(r.left, f.anchor.left,
          reason: 'a popover hangs from its anchor; a sheet would be centred');
    });
  });

  for (final s in const [Size(700, 900), Size(1100, 800)]) {
    testWidgets('AC-LS-8b/${_sz(s)} dialog centred, at most 480', (t) async {
      final f = await _pumpHost(t, size: s, kind: AdaptiveSurfaceKind.dialog);
      await f.open();
      final r = f.sheet;
      expect(r.width, lessThanOrEqualTo(480));
      expect((r.center.dx - s.width / 2).abs(), lessThan(1));
      expect((r.center.dy - s.height / 2).abs(), lessThan(s.height * 0.2));
    });
  }

  testWidgets('AC-LS-8d Esc closes popover and dialog, no write, focus returns',
      (t) async {
    for (final kind in AdaptiveSurfaceKind.values) {
      final f = await _pumpHost(t, size: const Size(1100, 800), kind: kind);
      await f.open();
      expect(find.byKey(_content), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byKey(_content), findsNothing, reason: '$kind');
      expect(f.writes, isEmpty);
      expect(f.openNode.hasPrimaryFocus, isTrue, reason: '$kind focus return');
      expect(f.depth, 0);
    }
  });

  testWidgets('AC-WS-14a reduced motion: final state after one pump', (t) async {
    final f = await _pumpHost(t, size: const Size(360, 800), reduce: true);
    f.openNode.requestFocus();
    await t.pump();
    await t.tap(find.byKey(_open));
    await t.pump();
    expect(find.byKey(_content), findsOneWidget);
    expect(f.sheet.bottom, greaterThan(800 - 24),
        reason: 'must already sit at its final position');
  });

  testWidgets('AC-WS-14b resize with the surface open keeps scroll and focus',
      (t) async {
    final f = await _pumpHost(t, size: const Size(360, 800), reduce: true);
    await f.open();
    _ContentState.last!.scroll.jumpTo(200);
    await t.pump();
    expect(focusIsWithin(_title), isTrue, reason: 'precondition: title focused');
    t.view.physicalSize = const Size(1100, 800);
    await t.pump();
    await t.pump();
    expect(find.byKey(_content), findsOneWidget);
    expect(f.sheet.top, greaterThanOrEqualTo(f.anchor.bottom),
        reason: 'must have become a popover');
    expect(_ContentState.last!.scroll.offset, 200);
    expect(focusIsWithin(_title), isTrue);
  });

  testWidgets('AC-A11Y-6a hudMotionDuration under reduced motion', (t) async {
    final f = await _pumpHost(t, size: const Size(360, 800), reduce: true);
    final ctx = t.element(find.byKey(_open));
    expect(ctx.hudMotionDuration(const Duration(milliseconds: 220)), Duration.zero);
    await f.open();
    final route = ModalRoute.of(t.element(find.byKey(_content)))!;
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
    final f2 = await _pumpHost(t, size: const Size(360, 800));
    await f2.open();
    final route2 = ModalRoute.of(t.element(find.byKey(_content)))!;
    expect(route2.transitionDuration, greaterThan(Duration.zero),
        reason: 'without reduced motion the surface does animate');
  });

  test('AC-A11Y-6b K: no indeterminate progress indicator in S03 files', () {
    final files = <String>[
      'lib/shared/widgets/shell_layout.dart',
      'lib/shared/widgets/shell_destinations.dart',
      'lib/shared/widgets/hud/hud_side_rail.dart',
      'lib/shared/widgets/shell_dock.dart',
      'lib/shared/widgets/dock_widgets.dart',
      'lib/shared/widgets/adaptive_surface.dart',
      'lib/shared/widgets/main_shell.dart',
      'lib/features/workouts/state/active_session_status.dart',
    ];
    final dir = Directory('lib/features/modes');
    expect(dir.existsSync(), isTrue);
    final all = <String>[
      ...files,
      ...dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.path.replaceAll('\\', '/')),
    ];
    expect(all.length, greaterThanOrEqualTo(15));
    final hits = <String>[];
    final re = RegExp(r'(Circular|Linear)ProgressIndicator\s*\(');
    for (final p in all) {
      final src = File(p).readAsStringSync();
      for (final m in re.allMatches(src)) {
        int depth = 0, i = m.end - 1;
        do {
          if (src[i] == '(') depth++;
          if (src[i] == ')') depth--;
          i++;
        } while (depth > 0 && i < src.length);
        if (!src.substring(m.end, i).contains('value:')) hits.add('$p@${m.start}');
      }
    }
    expect(hits, isEmpty);
  });

  testWidgets('DT-06-1 popover stays inside the window at every anchor',
      (t) async {
    const win = Size(1100, 800);
    for (final at in const [
      Offset(900, 700),
      Offset(980, 10),
      Offset(10, 700),
      Offset(980, 380),
      Offset(10, 10),
      Offset(500, 300),
    ]) {
      final f = await _pumpHost(t, size: win, anchorAt: at);
      await f.open();
      final r = f.sheet;
      expect(_inside(win, r), isTrue, reason: 'anchor $at -> $r');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
    }
  });

  for (final (name, from, to) in const <(String, Size, Size)>[
    ('across600', Size(590, 800), Size(610, 800)),
    ('across840', Size(830, 800), Size(850, 800)),
  ]) {
    testWidgets('DT-06-2/$name placement changes while open', (t) async {
      final f = await _pumpHost(t, size: from);
      await f.open();
      await t.tap(find.byKey(const Key('surface.row.3')));
      await t.pump();
      expect(_ContentState.last!.selected, 3);
      t.view.physicalSize = to;
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(_content), findsOneWidget);
      expect(_ContentState.last!.selected, 3);
      expect(_ContentState.last!.nodes[3].hasPrimaryFocus, isTrue);
      expect(f.depth, 1);
    });
  }

  testWidgets('DT-06-3 system Back closes the surface, not the page', (t) async {
    final f = await _pumpHost(t, size: const Size(360, 800));
    await f.open();
    expect(f.depth, 1);
    await t.binding.handlePopRoute();
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(_content), findsNothing);
    expect(f.depth, 0);
    expect(f.router.routerDelegate.currentConfiguration.uri.path, '/');
    expect(find.byKey(_open), findsOneWidget);
  });

  group('DT-06-4 depth returns to 0', () {
    for (final how in const ['back', 'scrim', 'esc', 'programmatic', 'accountChange']) {
      testWidgets('DT-06-4/$how', (t) async {
        final f = await _pumpHost(t, size: const Size(360, 800));
        await f.open();
        expect(f.depth, 1);
        switch (how) {
          case 'back':
            await t.binding.handlePopRoute();
          case 'scrim':
            await t.tapAt(const Offset(180, 40));
          case 'esc':
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
          case 'programmatic':
            Navigator.of(t.element(find.byKey(_content)), rootNavigator: true).pop();
          case 'accountChange':
            f.auth.add(kUserB);
            await t.pump();
            await t.pump();
            expect(f.depth, 1,
                reason: 'an account change must not zero the depth while the surface is open');
            await t.binding.handlePopRoute();
        }
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.byKey(_content), findsNothing, reason: how);
        expect(f.depth, 0, reason: how);
        await f.open();
        expect(find.byKey(_content), findsOneWidget, reason: 'second open works');
        expect(f.depth, 1);
      });
    }
  });
}
