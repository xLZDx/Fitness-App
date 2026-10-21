// S03-12 Home: chip, lens, activity today, intro card, two-pane (test plan 5.1).
// Real HomePage; the mode state is a fake ModeNotifier (in-memory), the journal
// a fake with a fixed clock and zone.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/core/router/s03_routes.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart' show JournalEntry;
import 'package:fitness_app/features/home/home_page.dart';
import 'package:fitness_app/features/modes/data/mode_models.dart';
import 'package:fitness_app/features/modes/state/mode_providers.dart';
import 'package:fitness_app/features/moments/data/moment.dart';
import 'package:fitness_app/features/moments/data/moment_repository.dart';
import 'package:fitness_app/features/moments/state/moment_providers.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/safety/state/eligibility_providers.dart';
import 'package:fitness_app/features/training_context/data/training_context.dart';
import 'package:fitness_app/features/training_context/state/training_context_providers.dart';

import '../../support/s03_step4_support.dart';

class _Ctx extends TrainingContextNotifier {
  @override
  Future<TrainingContextAnswer> build() async => TrainingContextAnswer.skipped;
  @override
  Future<void> select(TrainingContextAnswer a) async => state = AsyncData(a);
}

class FakeMode extends ModeNotifier {
  FakeMode(this.initial, {this.gate});
  final ModeState initial;
  final Completer<void>? gate;
  int resolvedCalls = 0;
  @override
  Future<ModeState> build() async {
    if (gate != null) await gate!.future;
    return initial;
  }

  @override
  Future<ModeSaveResult> markResolved() async {
    resolvedCalls++;
    state = AsyncData(state.value!.copyWith(chooserStatus: ChooserStatus.resolved));
    return ModeSaveResult.saved;
  }
}

class _Moments extends Fake implements MomentRepository {
  _Moments({required this.day3});
  final bool day3;
  @override
  Future<void> bumpLaunchCount() async {}
  @override
  Future<bool> hasShown(MomentId id) async => false;
  @override
  Future<void> markShown(MomentId id) async {}
  @override
  Future<int> launchCount() async => day3 ? 5 : 0;
  @override
  Future<DateTime?> firstLaunchAt() async =>
      day3 ? DateTime.now().subtract(const Duration(days: 10)) : DateTime.now();
}

const List<String> kTrainOrder = [
  'greeting', 'identity', 'dayPanel', 'week', 'recovery', 'quickScan',
  'bodyScan', 'nutrition', 'deload', 'summary', 'upcoming', 'more',
  'suggestions',
];

ModeState ms(AppMode m, ChooserStatus c, {Map<AppMode, ModeAnswer>? a}) =>
    ModeState(selectedMode: m, chooserStatus: c, answers: a ?? const {});

Future<FakeMode> pumpHome(
  WidgetTester t, {
  ModeState? mode,
  FakeJournal? journal,
  Completer<void>? gate,
  double w = 800,
  double h = 3600,
  double scale = 1.0,
  Locale locale = const Locale('en'),
  bool day3 = false,
  List<Override> extra = const [],
}) async {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(() {
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
  t.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  final fake = FakeMode(mode ?? ms(AppMode.train, ChooserStatus.resolved),
      gate: gate);
  final router = GoRouter(initialLocation: '/home', routes: [
    GoRoute(path: '/home', builder: (_, __) => const HomePage()),
    GoRoute(
        path: kModeChooserPath,
        builder: (_, __) => const Scaffold(body: Text('chooser-stub'))),
    GoRoute(
        path: '/onboarding/edit',
        builder: (_, __) => const Scaffold(body: Text('edit-stub'))),
  ]);
  await t.pumpWidget(appHost(const SizedBox(),
        locale: locale,
        router: router,
        overrides: [
          ...dashOverrides(journal: journal ?? FakeJournal()),
          modeStateProvider.overrideWith(() => fake),
          momentRepositoryProvider.overrideWithValue(_Moments(day3: day3)),
          // v1 scope: the Day-3 modal is off by default; day3: true means the
          // scenario that exercises it.
          day3WelcomeModalEnabledProvider.overrideWithValue(day3),
          trainingContextProvider.overrideWith(() => _Ctx()),
          safetyContextProvider.overrideWith((_) async => SafetyContext(
              screening:
                  screen({for (final q in ParQQuestion.values) q: false}))),
          ...extra,
        ]));
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
  return fake;
}

/// `home.section.*` names ordered by position (top, then left).
List<String> sectionOrder(WidgetTester t) {
  final found = <(String, Offset)>[];
  for (final w in t.widgetList(find.byWidgetPredicate((w) =>
      w.key is Key && (w.key.toString()).contains('home.section.')))) {
    final k = w.key.toString();
    final name = RegExp(r"home\.section\.(\w+)").firstMatch(k)!.group(1)!;
    if (found.any((e) => e.$1 == name)) continue;
    final f = find.byKey(w.key!);
    found.add((name, t.getTopLeft(f.first)));
  }
  found.sort((a, b) => a.$2.dy != b.$2.dy
      ? a.$2.dy.compareTo(b.$2.dy)
      : a.$2.dx.compareTo(b.$2.dx));
  return [for (final e in found) e.$1];
}

Finder key(String k) => find.byKey(Key(k));

JournalEntry today(String id, {SportType s = SportType.running, DateTime? at}) =>
    entry(sess(id, sport: s, start: at ?? kNow, dist: 5000, time: 1500));

void main() {
  setUp(() {
    // The Home page logs nothing relevant; keep the log quiet.
  });

  group('lens order', () {
    testWidgets('AC-HM-1 TRAIN keeps the Phase 1 order and gains only the chip',
        (t) async {
      // The literal list below is the pre-S03 child order (golden, TP-m2).
      for (final j in [FakeJournal(), null]) {
        await pumpHome(t, journal: j, mode: ms(AppMode.train, ChooserStatus.resolved));
        final order = sectionOrder(t);
        expect(order, kTrainOrder.where(order.contains).toList());
        expect(order.first, 'greeting');
        expect(key('home.modeChip'), findsOneWidget);
        expect(find.textContaining('could not be opened'), findsNothing);
        await t.pumpWidget(const SizedBox());
      }
    });

    testWidgets('AC-HM-2 BODY puts body scan and nutrition before quick scan',
        (t) async {
      await pumpHome(t, mode: ms(AppMode.body, ChooserStatus.resolved));
      final order = sectionOrder(t);
      expect(order.indexOf('bodyScan'), lessThan(order.indexOf('quickScan')));
      expect(order.indexOf('nutrition'), lessThan(order.indexOf('quickScan')));
      expect(order.toSet(), kTrainOrder.where(order.contains).toSet());
      expect(order, contains('quickScan'));
    });
  });

  group('AC-HM-3 activity today', () {
    testWidgets('AC-HM-3/startsToday', (t) async {
      await pumpHome(t, journal: FakeJournal([today('r1')]));
      expect(key('home.activityToday'), findsOneWidget);
    });
    testWidgets('AC-HM-3/startsYesterday', (t) async {
      await pumpHome(t,
          journal: FakeJournal(
              [today('r1', at: kNow.subtract(const Duration(days: 1)))]));
      expect(key('home.activityToday'), findsNothing);
    });
    testWidgets('AC-HM-3/strengthToday', (t) async {
      await pumpHome(t,
          journal: FakeJournal([today('s1', s: SportType.strength)]));
      expect(key('home.activityToday'), findsNothing);
    });
    testWidgets('DT-12 more line carries a word, not a bare +n (known gap)',
        (t) async {
      await pumpHome(t, journal: FakeJournal([
        for (var i = 0; i < 5; i++) today('r$i'),
      ]));
      final more = t.widget<Text>(key('home.activityToday.more'));
      expect(more.data, startsWith('+2'));
      expect(more.data, matches(RegExp(r'^\+\d+\s+\S')),
          reason: 'the line is a bare "${more.data}" (no ARB key for "more")');
    });
  });

  group('AC-HM-4 intro card', () {
    testWidgets('AC-HM-4/migrated: card, Not now resolves, card gone',
        (t) async {
      final m = await pumpHome(t, mode: ms(AppMode.train, ChooserStatus.migrated));
      expect(key('home.modeIntro'), findsOneWidget);
      await t.tap(key('home.modeIntro.dismiss'));
      for (var i = 0; i < 3; i++) {
        await t.pump(const Duration(milliseconds: 60));
      }
      expect(m.resolvedCalls, 1);
      expect(key('home.modeIntro'), findsNothing);
    });
    for (final c in [
      ChooserStatus.pending,
      ChooserStatus.resolved,
      ChooserStatus.absent
    ]) {
      testWidgets('AC-HM-4/${c.name}: never shown', (t) async {
        await pumpHome(t, mode: ms(AppMode.train, c));
        expect(key('home.modeIntro'), findsNothing);
      });
    }
    testWidgets('AC-HM-4/day3Modal: no card beside the Day-3 sheet', (t) async {
      await pumpHome(t,
          mode: ms(AppMode.train, ChooserStatus.migrated), day3: true);
      expect(find.byType(BottomSheet), findsOneWidget,
          reason: 'the Day-3 modal is open');
      expect(key('home.modeIntro'), findsNothing);
    });
  });

  testWidgets('AC-HM-5 a throwing journal adds no text and loses no section',
      (t) async {
    await pumpHome(t, journal: FakeJournal()..listError = StateError('boom'));
    expect(find.textContaining('could not be opened'), findsNothing);
    expect(find.text('No data'), findsNothing);
    expect(find.textContaining('boom'), findsNothing);
    final order = sectionOrder(t);
    for (final s in ['greeting', 'identity', 'dayPanel', 'week', 'quickScan']) {
      expect(order, contains(s));
    }
    expect(key('home.activityToday'), findsNothing);
  });

  group('AC-HM-6 chip vs greeting', () {
    testWidgets('AC-HM-6/scale2 ru: chip below greeting, no overflow',
        (t) async {
      await pumpHome(t, scale: 2.0, locale: const Locale('ru'), w: 360, h: 3600);
      expect(t.takeException(), isNull);
      final chip = key('home.modeChip');
      expect(chip, findsOneWidget);
      final name = find.byKey(const Key('home.greeting'));
      expect(t.getRect(chip).overlaps(t.getRect(find.text('Ivan').first)),
          isFalse);
      expect(name, findsOneWidget);
    });
    testWidgets('AC-HM-6/traversal: Tab from the greeting reaches the chip',
        (t) async {
      await pumpHome(t);
      // The chip is focusable (showFocusRing); focus it and check it holds.
      final chipFocus = find.descendant(
          of: key('home.modeChip'), matching: find.byType(Focus));
      expect(chipFocus, findsWidgets);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      final primary = FocusManager.instance.primaryFocus;
      expect(primary, isNotNull);
      // Walk Tab until the chip subtree owns focus (bounded).
      var reached = false;
      for (var i = 0; i < 6 && !reached; i++) {
        final ctx = FocusManager.instance.primaryFocus?.context;
        if (ctx != null &&
            find
                .descendant(
                    of: key('home.modeChip'),
                    matching: find.byElementPredicate((e) => e == ctx))
                .evaluate()
                .isNotEmpty) {
          reached = true;
        } else {
          await t.sendKeyEvent(LogicalKeyboardKey.tab);
          await t.pump();
        }
      }
      expect(reached, isTrue, reason: 'the chip is in the tab order');
    });
  });

  group('AC-LS-1 two panes', () {
    testWidgets('AC-LS-1/1100x800', (t) async {
      await pumpHome(t, w: 1100, h: 3600);
      expect(key('home.pane.main'), findsOneWidget);
      expect(key('home.pane.side'), findsOneWidget);
      expect(t.getSize(key('home.pane.side')).width, 340);
      expect(t.getSize(key('home.pane.main')).width +
          t.getSize(key('home.pane.side')).width, lessThanOrEqualTo(1120));
      expect(t.getTopLeft(key('home.pane.main')).dx,
          lessThan(t.getTopLeft(key('home.pane.side')).dx));
      final wide = sectionOrder(t).toSet();
      await t.pumpWidget(const SizedBox());
      await pumpHome(t, w: 360, h: 3600);
      expect(wide, sectionOrder(t).toSet());
    });
    for (final w in [700.0, 360.0]) {
      testWidgets('AC-LS-1/${w.toInt()}', (t) async {
        await pumpHome(t, w: w, h: 3600);
        expect(key('home.pane.main'), findsNothing);
        expect(key('home.pane.side'), findsNothing);
        expect(sectionOrder(t),
            kTrainOrder.where(sectionOrder(t).contains).toList());
      });
    }
  });

  group('AC-LS-2 lens in the wide layout', () {
    List<String> pane(WidgetTester t, String paneKey) {
      final box = find.byKey(Key(paneKey));
      final names = <String>[];
      for (final n in kTrainOrder) {
        if (find.descendant(of: box, matching: key('home.section.$n'))
            .evaluate()
            .isNotEmpty) {
          names.add(n);
        }
      }
      return names;
    }

    testWidgets('AC-LS-2/body', (t) async {
      await pumpHome(t,
          w: 1100, h: 3600, mode: ms(AppMode.body, ChooserStatus.resolved));
      final main = pane(t, 'home.pane.main');
      expect(main, containsAll(['bodyScan', 'nutrition']));
      expect(pane(t, 'home.pane.side'), contains('quickScan'));
    });
    testWidgets('AC-LS-2/train', (t) async {
      await pumpHome(t, w: 1100, h: 3600);
      final side = pane(t, 'home.pane.side');
      expect(side, containsAll(['bodyScan', 'nutrition', 'quickScan']));
      expect(side, kTrainOrder.where(side.contains).toList(),
          reason: 'relative order inside a pane equals the pre-S03 order');
    });
  });

  testWidgets('AC-LS-3 900 wide at scale 2.0 ru: single column, no overflow',
      (t) async {
    await pumpHome(t,
        w: 900, h: 4000, scale: 2.0, locale: const Locale('ru'));
    expect(t.takeException(), isNull);
    expect(key('home.pane.side'), findsNothing,
        reason: 'the side pane must fall below the main column at large text');
  });

  testWidgets('DT-12-1 intro card waits for the next build after Day-3',
      (t) async {
    await pumpHome(t,
        mode: ms(AppMode.train, ChooserStatus.migrated), day3: true);
    expect(key('home.modeIntro'), findsNothing);
    await t.tapAt(const Offset(10, 10)); // barrier closes the sheet
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(BottomSheet), findsNothing);
    // Same Home session that showed the modal: still no card (finding U8).
    expect(key('home.modeIntro'), findsNothing);
  });

  for (final c in [(450.0, true), (100.0, false)]) {
    testWidgets(
        'DT-12-2/offset${c.$1.toInt()} card ${c.$2 ? 'above' : 'inside'} the viewport edge',
        (t) async {
      final j = FakeJournal([today('r1')]);
      final g = Completer<List<JournalEntry>>();
      j.gateQueue.add(g);
      await pumpHome(t, journal: j, w: 400, h: 900);
      final s = t.state<ScrollableState>(find.byType(Scrollable).first);
      expect(s.position.maxScrollExtent, greaterThan(c.$1 + 100));
      s.position.jumpTo(c.$1);
      await t.pump(const Duration(milliseconds: 60));
      Finder anchor = key('home.section.recovery');
      for (final n in ['recovery', 'quickScan', 'bodyScan']) {
        final f = key('home.section.$n');
        if (f.evaluate().isNotEmpty &&
            t.getTopLeft(f).dy > 0 &&
            t.getTopLeft(f).dy < 800) {
          anchor = f;
          break;
        }
      }
      final before = t.getTopLeft(anchor).dy;
      g.complete([today('r1')]);
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 60));
      }
      if (!c.$2) expect(key('home.activityToday'), findsOneWidget);
      if (c.$2) {
        // Arrival above the edge: compensated, the reading position holds.
        expect(s.position.pixels, greaterThan(c.$1));
        final after = t.getTopLeft(anchor).dy;
        expect(after, closeTo(before, 1.0),
            reason: 'content below the card jumped by ${after - before}');
      } else {
        // Arrival inside the viewport: no compensation (review rule).
        expect(s.position.pixels, c.$1);
      }
    });
  }

  testWidgets('DT-12-3 Choose a mode opens the chooser and resolves',
      (t) async {
    final m = await pumpHome(t, mode: ms(AppMode.train, ChooserStatus.migrated));
    await t.tap(key('home.modeIntro.choose'));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
    expect(find.text('chooser-stub'), findsOneWidget);
    expect(m.resolvedCalls, 1);
  });

  testWidgets('DT-12-4 loading mode state: greeting only, no chip, no flash',
      (t) async {
    final gate = Completer<void>();
    await pumpHome(t,
        mode: ms(AppMode.body, ChooserStatus.resolved), gate: gate);
    expect(key('home.modeChip'), findsNothing);
    expect(find.text('chooser-stub'), findsNothing);
    // fe67291b: while the mode is unknown only the greeting shows (the plan
    // said "TRAIN order"; the stricter rule also rules out any flash).
    expect(sectionOrder(t), ['greeting']);
    gate.complete();
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
    final after = sectionOrder(t);
    expect(after.indexOf('bodyScan'), lessThan(after.indexOf('quickScan')));
    expect(key('home.modeChip'), findsOneWidget);
  });

  testWidgets('DT-12-5 card scrolled out of the cache extent and back: offset kept',
      (t) async {
    await pumpHome(t, journal: FakeJournal([today('r1')]), w: 400, h: 500);
    expect(key('home.activityToday'), findsOneWidget);
    final s = t.state<ScrollableState>(find.byType(Scrollable).first);
    final far = s.position.maxScrollExtent;
    expect(far, greaterThan(900), reason: 'Home is long enough to evict the card');
    s.position.jumpTo(far);
    await t.pump(const Duration(milliseconds: 60));
    await t.pump(const Duration(milliseconds: 60));
    expect(key('home.activityToday'), findsNothing,
        reason: 'the card is out of the cache extent (unbuilt)');
    s.position.jumpTo(80);
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
    expect(key('home.activityToday'), findsOneWidget);
    expect(s.position.pixels, 80,
        reason: 'rebuilding the card is not an arrival and must not compensate');
  });
}
