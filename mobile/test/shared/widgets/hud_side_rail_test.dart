import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fitness_app/features/workouts/state/set_timer_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/hud_tokens.dart';
import 'package:fitness_app/core/theme/hud_typography.dart';
import 'package:fitness_app/shared/widgets/hud/hud_scaffold.dart';
import 'package:fitness_app/shared/widgets/hud/hud_surface.dart';
import 'package:fitness_app/shared/widgets/shell_destinations.dart';
import 'package:fitness_app/shared/widgets/shell_layout.dart';

import '../../support/s03_shell_harness.dart';
import '../../support/wcag_contrast.dart';

const Key _rail = ValueKey<String>('shell.rail');
const Key _record = ValueKey<String>('shell.rail.record');
const Key _bar = ValueKey<String>('shell.bottomBar');

double _railWidth(WidgetTester t) => t.getSize(find.byKey(_rail)).width;

/// Contract rule (10.4), written independently of the production function.
double _expectedForm(double window, double widest) =>
    (window >= 1200 || widest + 16 > 96) ? 240 : 96;

Future<double> _measuredWidest(
    WidgetTester t, Locale locale) async {
  final ctx = t.element(find.byKey(_rail));
  final l10n = await AppLocalizations.delegate.load(locale);
  final tok = ctx.hud;
  final style = HudType.navLabel(tok, color: tok.textSecondary);
  final scaler = MediaQuery.textScalerOf(ctx);
  double widest = 0;
  for (final d in kShellDestinations) {
    final p = TextPainter(
      text: TextSpan(text: d.labelOf(l10n).toUpperCase(), style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    widest = math.max(widest, p.width);
    p.dispose();
  }
  return widest;
}

List<Override> _stub(double w) => <Override>[
      railLabelMeasurerProvider.overrideWithValue((l, s, sc) => w),
    ];

/// Pumps one rail case and returns the resolved width.
Future<double> _railCase(WidgetTester t,
    {required Size size,
    Locale locale = const Locale('ru'),
    double scale = 1.0,
    List<Override> overrides = const <Override>[]}) async {
  await pumpShell(t,
      size: size, locale: locale, textScale: scale, overrides: overrides);
  expect(find.byKey(_rail), findsOneWidget);
  expect(t.takeException(), isNull, reason: 'overflow or error while pumping');
  return _railWidth(t);
}

Future<void> _tabTo(WidgetTester t, bool Function() done, {int max = 12}) async {
  for (int i = 0; i < max && !done(); i++) {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
  }
}

void main() {
  group('AC-WS-2 presentation by window', () {
    for (final s in const [Size(360, 800), Size(700, 900)]) {
      testWidgets('AC-WS-2a/${s.width.toInt()}x${s.height.toInt()} bar, no rail',
          (t) async {
        await pumpShell(t, size: s, locale: const Locale('en'));
        expect(find.byKey(_bar), findsOneWidget);
        expect(find.byKey(_rail), findsNothing);
        if (s.width == 700) {
          final w = t
              .getSize(find
                  .descendant(of: find.byKey(_bar), matching: find.byType(HudSurface))
                  .first)
              .width;
          expect(w, lessThanOrEqualTo(560));
          expect(w, greaterThan(300));
        }
      });
    }
    for (final s in const [Size(700, 420), Size(900, 400), Size(1100, 800)]) {
      testWidgets('AC-WS-2b/${s.width.toInt()}x${s.height.toInt()} rail, no bar',
          (t) async {
        await pumpShell(t, size: s, locale: const Locale('en'));
        expect(find.byKey(_rail), findsOneWidget);
        expect(find.byKey(_bar), findsNothing);
        expect(t.takeException(), isNull);
      });
    }
  });

  group('AC-WS-3 rail form', () {
    for (final scale in const [1.0, 1.15, 1.29]) {
      testWidgets('AC-WS-3a/ru/1100x800/scale$scale (font measured)', (t) async {
        final w = await _railCase(t, size: const Size(1100, 800), scale: scale);
        final widest = await _measuredWidest(t, const Locale('ru'));
        expect(w, _expectedForm(1100, widest),
            reason: 'widest label measured $widest dp, rail resolved $w dp');
      });
    }
    for (final v in const [70.0, 90.0]) {
      testWidgets('AC-WS-3b/seam${v.toInt()}', (t) async {
        final w = await _railCase(t,
            size: const Size(1100, 800), overrides: _stub(v));
        expect(w, v + 16 > 96 ? 240 : 96,
            reason: 'stub label width $v + 16 vs 96');
      });
    }
    testWidgets('AC-WS-3c 1200x800 is always extended', (t) async {
      final w = await _railCase(t,
          size: const Size(1200, 800), overrides: _stub(10));
      expect(w, 240);
    });
    testWidgets('AC-WS-3d ru scale 2.0 is extended by measurement', (t) async {
      final w = await _railCase(t, size: const Size(1100, 800), scale: 2.0);
      final widest = await _measuredWidest(t, const Locale('ru'));
      expect(widest + 16, greaterThan(96), reason: 'measured $widest');
      expect(w, 240);
    });
  });

  group('AC-WS-4 destinations', () {
    testWidgets('AC-WS-4/fiveItems order and Record above', (t) async {
      await pumpShell(t, size: const Size(1100, 800), locale: const Locale('en'));
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final list = find.descendant(
          of: find.byKey(_rail), matching: find.byType(SingleChildScrollView));
      final tiles = find.descendant(of: list, matching: find.byType(InkResponse));
      expect(tiles, findsNWidgets(5));
      final texts = <String>[];
      double lastTop = -1;
      for (int i = 0; i < 5; i++) {
        final tile = tiles.at(i);
        final txt = t.widget<Text>(
            find.descendant(of: tile, matching: find.byType(Text)).first);
        texts.add(txt.data!);
        final top = t.getTopLeft(tile).dy;
        expect(top, greaterThan(lastTop), reason: 'tiles must run top to bottom');
        lastTop = top;
      }
      expect(texts, [
        for (final d in kShellDestinations) d.labelOf(l10n).toUpperCase()
      ]);
      expect(t.getBottomLeft(find.byKey(_record)).dy,
          lessThanOrEqualTo(t.getTopLeft(tiles.first).dy + 1));
    });
  });

  testWidgets('AC-WS-5 presentation swap keeps route, selection and timer',
      (t) async {
    final clock = TestClock();
    final f = await pumpShell(t,
        size: const Size(1100, 800),
        initial: '/progress',
        clock: clock,
        overrides: realTimerOverrides(clock));
    f.container.read(setTimerProvider.notifier).start(kTestSetPlan);
    await t.pump(const Duration(seconds: 4));
    // Focus the Progress rail destination (index 3) by Tab.
    await _tabTo(t, () => FocusManager.instance.primaryFocus?.debugLabel == 'shell.destination.3');
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'shell.destination.3');

    var before = f.container.read(setTimerProvider);
    for (final s in const [Size(360, 800), Size(1100, 800)]) {
      await resizeTo(t, s);
      expect(f.location, '/progress');
      final after = f.container.read(setTimerProvider);
      expect(after.phase, before.phase);
      expect(after.running, isTrue);
      await t.pump(const Duration(seconds: 5));
      final later = f.container.read(setTimerProvider);
      expect(later.secondsLeft, lessThan(after.secondsLeft),
          reason: 'the clock must still tick after the swap');
      before = later;
      if (s.width < 600) {
        expect(t.widget<HudNavBar>(find.byType(HudNavBar)).selectedIndex, 3);
      } else {
        final sel = find.descendant(
            of: find.byKey(_rail),
            matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.selected == true));
        expect(sel, findsOneWidget);
      }
      // Focus on the Progress destination in this presentation.
      final label = FocusManager.instance.primaryFocus?.debugLabel ?? '';
      final inBar = find.descendant(
          of: find.byKey(_bar), matching: find.text('PROGRESS'));
      final onProgress = s.width < 600
          ? focusIsWithin(const ValueKey<String>('shell.bottomBar'))
          : label == 'shell.destination.3';
      expect(onProgress, isTrue,
          reason: 'focus must stay on the Progress destination after the swap '
              '(primary focus now: "$label", bar tab found: ${inBar.evaluate().isNotEmpty})');
    }
  });

  group('focus across the rail to bar swap', () {
    String lbl() => FocusManager.instance.primaryFocus?.debugLabel ?? '';

    testWidgets('focus on a destination that is not the active route is restored',
        (t) async {
      final f = await pumpShell(t,
          size: const Size(1100, 800), initial: '/progress', locale: const Locale('en'));
      await _tabTo(t, () => lbl() == 'shell.destination.4');
      expect(lbl(), 'shell.destination.4', reason: 'precondition: Profile focused');
      expect(f.location, '/progress', reason: 'focusing must not activate it');
      await resizeTo(t, const Size(360, 800));
      expect(f.location, '/progress');
      expect(lbl(), 'shell.destination.4',
          reason: 'focus must follow the destination, not the active route');
      expect(focusIsWithin(_bar), isTrue);
    });

    testWidgets('nothing is focused after the swap when no destination had focus',
        (t) async {
      await pumpShell(t,
          size: const Size(1100, 800), initial: '/progress', locale: const Locale('en'));
      expect(lbl().startsWith('shell.destination.'), isFalse);
      await resizeTo(t, const Size(360, 800));
      expect(lbl().startsWith('shell.destination.'), isFalse,
          reason: 'no focus may be requested: "${lbl()}"');
    });
  });

  group('AC-WS-6 pushed routes have no chrome', () {
    for (final route in const ['/workout/x1', '/settings']) {
      testWidgets('AC-WS-6/$route', (t) async {
        final f = await pumpShell(t, size: const Size(1100, 800));
        expect(find.byKey(_rail), findsOneWidget);
        f.router.push(route);
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.textContaining('-stub'), findsOneWidget);
        expect(find.byKey(_rail), findsNothing);
        expect(find.byKey(_bar), findsNothing);
      });
    }
  });

  group('AC-WS-8 insets', () {
    testWidgets('AC-WS-8/endClearance', (t) async {
      await pumpShell(t, size: const Size(1100, 800), rows: 40);
      final pos = t
          .state<ScrollableState>(find
              .ancestor(of: find.byKey(const Key('row.0')), matching: find.byType(Scrollable))
              .first)
          .position;
      for (int i = 0; i < 4; i++) {
        pos.jumpTo(pos.maxScrollExtent);
        await t.pump();
      }
      final last = find.byKey(const Key('row.39'));
      expect(last, findsOneWidget);
      final gap = 800 - t.getBottomLeft(last).dy;
      expect(gap, lessThanOrEqualTo(24 + 0.5),
          reason: 'no dock space may be reserved while the rail shows');
      expect(gap, greaterThan(0));
    });
    testWidgets('AC-WS-8/startInset', (t) async {
      await pumpShell(t, size: const Size(1100, 800), locale: const Locale('en'));
      final w = _railWidth(t);
      final left = t.getTopLeft(find.byKey(const Key('page.title./home'))).dx;
      expect(left, greaterThanOrEqualTo(w + 12 + 16),
          reason: 'content starts at $left under a $w dp rail');
    });
  });

  group('AC-WS-9 landscape', () {
    testWidgets('AC-WS-9/overflow every tab at 800x360 and 360x800 (ru)',
        (t) async {
      for (final s in const [Size(800, 360), Size(360, 800)]) {
        final f = await pumpShell(t, size: s, locale: const Locale('ru'));
        for (final p in kTabPaths) {
          await f.go(p);
          expect(t.takeException(), isNull, reason: '$p at $s');
        }
      }
    });
    testWidgets('AC-WS-9/orientation never locked', (t) async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (c) async {
        calls.add(c.method);
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance
          .defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      final f = await pumpShell(t, size: const Size(800, 360));
      await f.go('/progress');
      await resizeTo(t, const Size(360, 800));
      expect(calls.where((m) => m.contains('setPreferredOrientations')), isEmpty);
    });
  });

  group('AC-WS-10 short windows', () {
    const cases = <(Size, double)>[
      (Size(640, 360), 1.0),
      (Size(640, 360), 2.0),
      (Size(800, 360), 1.3),
      (Size(800, 360), 2.0),
    ];
    for (final (s, scale) in cases) {
      testWidgets('AC-WS-10/${s.width.toInt()}x${s.height.toInt()}@$scale',
          (t) async {
        await pumpShell(t, size: s, locale: const Locale('ru'), textScale: scale);
        expect(t.takeException(), isNull);
        final tiles = find.descendant(
            of: find.descendant(
                of: find.byKey(_rail),
                matching: find.byType(SingleChildScrollView)),
            matching: find.byType(InkResponse));
        expect(tiles, findsNWidgets(5));
        for (int i = 0; i < 5; i++) {
          expect(t.getSize(tiles.at(i)).height, greaterThanOrEqualTo(48));
        }
        final recordTop = t.getTopLeft(find.byKey(_record));
        // Tab reaches the Record slot and all five destinations.
        final seen = <String>{};
        bool recordSeen = false;
        for (int i = 0; i < 9; i++) {
          await t.sendKeyEvent(LogicalKeyboardKey.tab);
          await t.pump();
          final lbl = FocusManager.instance.primaryFocus?.debugLabel ?? '';
          if (lbl.startsWith('shell.destination.')) {
            seen.add(lbl);
            final r = t.getRect(tiles.at(int.parse(lbl.split('.').last)));
            expect(Rect.fromLTWH(0, 0, s.width, s.height).contains(r.topLeft) &&
                    Rect.fromLTWH(0, 0, s.width, s.height).contains(r.bottomRight),
                isTrue,
                reason: 'focused destination $lbl at $r outside the window');
          }
          if (focusIsWithin(_record)) recordSeen = true;
        }
        expect(recordSeen, isTrue, reason: 'Record slot unreachable by Tab');
        expect(seen.length, 5, reason: 'reached by Tab: $seen');
        expect(t.getTopLeft(find.byKey(_record)), recordTop,
            reason: 'Record slot moved while the list scrolled');
        // Arrow keys step through the five destinations.
        await _tabTo(t, () => FocusManager.instance.primaryFocus?.debugLabel == 'shell.destination.0', max: 14);
        final order = <String>[FocusManager.instance.primaryFocus?.debugLabel ?? ''];
        for (int i = 0; i < 4; i++) {
          await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await t.pump();
          order.add(FocusManager.instance.primaryFocus?.debugLabel ?? '');
        }
        expect(order, [for (int i = 0; i < 5; i++) 'shell.destination.$i']);
      });
    }
  });

  group('AC-WS-11 semantics', () {
    testWidgets('AC-WS-11/rail', (t) async {
      final h = t.ensureSemantics();
      await pumpShell(t, size: const Size(1100, 800), locale: const Locale('en'));
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final cont = t.getSemantics(find.byKey(_rail));
      expect(cont.label, l10n.navMainLabel);
      int selected = 0;
      for (final d in kShellDestinations) {
        final n = t.getSemantics(find.bySemanticsLabel(d.labelOf(l10n)).first);
        final data = n.getSemanticsData();
        expect(data.hasFlag(SemanticsFlag.isButton), isTrue, reason: d.path);
        expect(data.hasAction(SemanticsAction.tap), isTrue, reason: d.path);
        expect(data.label, isNotEmpty);
        if (data.hasFlag(SemanticsFlag.isSelected)) selected++;
      }
      expect(selected, 1);
      final rec = t
          .getSemantics(find
              .descendant(of: find.byKey(_record), matching: find.bySemanticsLabel(l10n.recordPill))
              .first)
          .getSemanticsData();
      expect(rec.label, l10n.recordPill);
      expect(rec.hasFlag(SemanticsFlag.isButton), isTrue);
      h.dispose();
    });
    testWidgets('AC-WS-11/bar', (t) async {
      final h = t.ensureSemantics();
      await pumpShell(t, size: const Size(360, 800), locale: const Locale('en'));
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(t.getSemantics(find.bySemanticsLabel(l10n.navMainLabel).first).label,
          l10n.navMainLabel);
      int selected = 0;
      for (final d in kShellDestinations) {
        final f = find.descendant(
            of: find.byKey(_bar),
            matching: find.bySemanticsLabel(RegExp('^${d.labelOf(l10n)}\$', caseSensitive: false)));
        expect(f, findsWidgets, reason: d.path);
        final data = t.getSemantics(f.first).getSemanticsData();
        expect(data.hasFlag(SemanticsFlag.isButton), isTrue, reason: d.path);
        expect(data.hasAction(SemanticsAction.tap), isTrue, reason: d.path);
        if (data.hasFlag(SemanticsFlag.isSelected)) selected++;
      }
      expect(selected, 1);
      h.dispose();
    });
  });

  testWidgets('AC-KB-2 arrows, Home/End, Enter, Tab leaves the rail',
      (t) async {
    final f = await pumpShell(t, size: const Size(1100, 800), locale: const Locale('en'));
    String lbl() => FocusManager.instance.primaryFocus?.debugLabel ?? '';
    await _tabTo(t, () => lbl() == 'shell.destination.0');
    expect(lbl(), 'shell.destination.0');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(lbl(), 'shell.destination.1');
    await t.sendKeyEvent(LogicalKeyboardKey.end);
    await t.pump();
    expect(lbl(), 'shell.destination.4');
    await t.sendKeyEvent(LogicalKeyboardKey.home);
    await t.pump();
    expect(lbl(), 'shell.destination.0');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(f.location, '/workouts');
    await t.sendKeyEvent(LogicalKeyboardKey.end);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(focusIsWithin(_rail), isFalse, reason: 'Tab must not trap focus');
    expect(FocusManager.instance.primaryFocus, isNotNull);
  });

  group('AC-KB-9 token contrast', () {
    for (final dark in const [true, false]) {
      test('AC-KB-9/ratios/${dark ? 'dark' : 'light'}', () {
        final tk = dark ? HudTokens.dark : HudTokens.light;
        // Rail surface: the glass fill flattened over the page backdrop floor.
        final backdrop =
            dark ? const Color(0xFF14182C) : const Color(0xFFEEF0F6);
        final surface = flatten(tk.navBar.fill, backdrop);
        final inactive = flatten(tk.textSecondary, surface);
        final selected = flatten(tk.textPrimary, surface);
        expect(contrast(inactive, surface), greaterThanOrEqualTo(4.5),
            reason: 'inactive rail ink');
        expect(contrast(selected, surface), greaterThanOrEqualTo(4.5),
            reason: 'selected rail ink');
        expect(contrast(tk.accent, surface), greaterThanOrEqualTo(3.0),
            reason: 'accent dot');
      });
    }
  });

  group('DT-05 helpers', () {
    test('DT-05-1 threshold is width + 16 > 96', () {
      expect(resolveRailWidth(windowWidth: 1100, widestLabel: 79.9), 96);
      expect(resolveRailWidth(windowWidth: 1100, widestLabel: 80.0), 96);
      expect(resolveRailWidth(windowWidth: 1100, widestLabel: 80.1), 240);
      expect(resolveRailWidth(windowWidth: 1199.9, widestLabel: 0), 96);
      expect(resolveRailWidth(windowWidth: 1200, widestLabel: 0), 240);
    });

    testWidgets('DT-05-2 both rail forms are reached by the AC-WS-3 cases',
        (t) async {
      final seen = <double>{};
      seen.add(await _railCase(t, size: const Size(1100, 800), overrides: _stub(70)));
      seen.add(await _railCase(t, size: const Size(1100, 800), overrides: _stub(90)));
      seen.add(await _railCase(t, size: const Size(1200, 800), overrides: _stub(10)));
      seen.add(await _railCase(t, size: const Size(1100, 800), scale: 2.0));
      expect(seen, containsAll(<double>[96, 240]),
          reason: 'resolved widths: $seen');
    });

    for (final (name, from, to) in const <(String, Size, Size)>[
      ('across840', Size(1100, 800), Size(700, 900)),
      ('acrossShort', Size(700, 900), Size(700, 420)),
    ]) {
      testWidgets('DT-05-3/$name page State survives the swap', (t) async {
        final marker = GlobalKey<_MarkerState>();
        final f = await pumpShell(t,
            size: from,
            locale: const Locale('en'),
            pageFor: (p) => _Marker(key: marker));
        final stateBefore = t.state<_MarkerState>(find.byType(_Marker));
        await t.enterText(find.byType(TextField), 'abc');
        await t.pump();
        stateBefore.scroll.jumpTo(300);
        await t.pump();
        for (final s in [to, from]) {
          await resizeTo(t, s);
          final now = t.state<_MarkerState>(find.byType(_Marker));
          expect(identical(now, stateBefore), isTrue,
              reason: 'State was rebuilt at $s');
          expect(now.scroll.offset, 300);
          expect(find.text('abc'), findsOneWidget);
          expect(f.location, '/home');
        }
      });
    }

    testWidgets('DT-05-5 label measurement is cached per key, not per pixel',
        (t) async {
      int calls = 0;
      final spy = <Override>[
        railLabelMeasurerProvider.overrideWithValue((l, s, sc) {
          calls++;
          return measureRailLabel(l, s, sc);
        }),
      ];
      final scale = ValueNotifier<double>(1.0);
      await pumpShell(t,
          size: const Size(900, 800),
          locale: const Locale('en'),
          scaleNotifier: scale,
          overrides: spy);
      for (int i = 0; i < 20; i++) {
        await resizeTo(t, Size(900.0 + i * 13, 800));
      }
      expect(calls, 5, reason: 'one measurement per label for one key');
      // A different text scale is a new key: measured once more, not per pixel.
      scale.value = 1.3;
      await t.pump();
      for (int i = 0; i < 20; i++) {
        await resizeTo(t, Size(900.0 + i * 13, 800));
      }
      expect(calls, 10, reason: 'one more measurement per label for the new key');
    });
  });
}

class _Marker extends StatefulWidget {
  const _Marker({super.key});
  @override
  State<_Marker> createState() => _MarkerState();
}

class _MarkerState extends State<_Marker> {
  final ScrollController scroll = ScrollController();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          const TextField(),
          Expanded(
            child: ListView(
              controller: scroll,
              children: <Widget>[
                for (int i = 0; i < 60; i++)
                  SizedBox(height: 60, child: Text('m$i')),
              ],
            ),
          ),
        ],
      );
}
