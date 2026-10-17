// S03-14 Progress dashboard (test plan 5.3). Real ProgressPage, real providers,
// fake journals and a fake timer factory. Surfaces are tall (the page is a lazy
// ListView), widths follow the plan.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/wiring/activity_wiring.dart';
import 'package:fitness_app/features/activity/data/activity_aggregates.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/state/activity_dashboard_providers.dart';
import 'package:fitness_app/features/activity/widgets/activity_sync_entry_card.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/body_scan/widgets/body_scan_entry_card.dart';
import 'package:fitness_app/features/modes/data/mode_models.dart';
import 'package:fitness_app/features/modes/state/mode_providers.dart';
import 'package:fitness_app/features/progress/progress_page.dart';
import 'package:fitness_app/features/progress/widgets/progress_activity_widgets.dart';
import 'package:fitness_app/shared/widgets/hud/hud_surface.dart';
import 'package:fitness_app/shared/widgets/shell_layout.dart';
import 'package:fitness_app/shared/widgets/window_size.dart';

import '../../support/s03_step4_support.dart';

Future<void> surface(WidgetTester t, double w, double h) async {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(() {
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
}

Future<void> settle(WidgetTester t, [int n = 5]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
}

Future<void> pumpProgress(
  WidgetTester t,
  List<Override> overrides, {
  double w = 800,
  double h = 2400,
  Locale locale = const Locale('en'),
  Widget Function(Widget)? wrap,
}) async {
  await surface(t, w, h);
  await t.pumpWidget(const SizedBox());
  Widget page = const ProgressPage();
  if (wrap != null) page = wrap(page);
  await t.pumpWidget(appHost(page, overrides: overrides, locale: locale));
  await settle(t);
}

ProviderContainer containerOf(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(ProgressPage)));

double top(WidgetTester t, Finder f) => t.getTopLeft(f.first).dy;

JournalEntry runEntry(String id,
        {double? dist = 5000, double? time = 1500, DateTime? at}) =>
    entry(sess(id, start: at ?? kNow, dist: dist, time: time));

Finder key(String k) => find.byKey(Key(k));

class FakeModeN extends ModeNotifier {
  FakeModeN(this.initial);
  final ModeState initial;
  @override
  Future<ModeState> build() async => initial;

  /// An account switch reload: loading, previous value kept.
  void reloadKeepingPrevious() {
    state = const AsyncLoading<ModeState>().copyWithPrevious(state);
  }
}

void main() {
  group('AC-PR-1 notEnabled', () {
    testWidgets('AC-PR-1 Sources slot only, no empty or error text',
        (t) async {
      await pumpProgress(t, dashOverrides(localJournal: false));
      expect(key('progress.slot.sources'), findsOneWidget);
      expect(key('progress.allActivity'), findsNothing);
      expect(key('progress.journalError'), findsNothing);
      expect(find.textContaining(RegExp('unavailable|empty|could not',
          caseSensitive: false)), findsNothing);
      // Existing blocks keep their order.
      expect(top(t, find.text('Last 8 weeks')),
          lessThan(top(t, find.text('Recent activity'))));
    });
  });

  group('AC-PR-2 Try again', () {
    Future<(ScopedFakeJournal, FakeTimers)> toGaveUp(WidgetTester t) async {
      final j = ScopedFakeJournal();
      final timers = FakeTimers();
      await pumpProgress(t, dashOverrides(journal: j, timers: timers));
      for (var i = 0; i < 5; i++) {
        j.complete(false);
        await settle(t, 2);
        timers.all.last.fire();
        await settle(t, 2);
      }
      j.complete(false);
      await settle(t);
      return (j, timers);
    }

    testWidgets('AC-PR-2/once: one tap is exactly one attempt', (t) async {
      final (j, timers) = await toGaveUp(t);
      expect(j.bindCalls, hasLength(6));
      expect(key('progress.journalError'), findsOneWidget);
      await t.tap(key('progress.journalRetry'));
      await settle(t, 2);
      expect(j.bindCalls, hasLength(7));
      expect(key('progress.journalError'), findsOneWidget,
          reason: 'the panel stays while the attempt runs');
      j.complete(false);
      await settle(t);
      expect(key('progress.journalError'), findsOneWidget);
      expect(timers.active, 0, reason: 'a manual failure arms no timer');
    });

    testWidgets('AC-PR-2/doubleTap: the second tap adds no attempt',
        (t) async {
      final (j, _) = await toGaveUp(t);
      await t.tap(key('progress.journalRetry'));
      await settle(t, 2);
      await t.tap(key('progress.journalRetry'), warnIfMissed: false);
      await settle(t, 2);
      expect(j.bindCalls, hasLength(7));
      j.complete(true);
      await settle(t);
    });
  });

  group('AC-PR-3 placement', () {
    testWidgets('AC-PR-3/zeroSessions looks like AC-PR-1', (t) async {
      await pumpProgress(t, dashOverrides(journal: FakeJournal()));
      expect(key('progress.slot.sources'), findsOneWidget);
      expect(key('progress.allActivity'), findsNothing);
      expect(key('progress.journalError'), findsNothing);
    });
    testWidgets('AC-PR-3/oneSession block sits between sync card and scan card',
        (t) async {
      await pumpProgress(
          t, dashOverrides(journal: FakeJournal([runEntry('r1')])));
      expect(key('progress.allActivity'), findsOneWidget);
      expect(key('progress.slot.sources'), findsNothing);
      final sync = top(t, find.byType(ActivitySyncEntryCard));
      final all = top(t, key('progress.allActivity'));
      final scan = top(t, find.byType(BodyScanEntryCard));
      expect(sync, lessThanOrEqualTo(all));
      expect(all, lessThan(scan));
    });
  });

  testWidgets('AC-PR-4 unknown is No data, never zero, no calories',
      (t) async {
    final j = FakeJournal([
      runEntry('r1'),
      entry(sess('w1',
          sport: SportType.walking, start: kNow, time: 600)),
    ]);
    await pumpProgress(t, dashOverrides(journal: j));
    final run = find.descendant(
        of: key('progress.tile.run'), matching: find.byType(Text));
    final runText = t.widgetList<Text>(run).map((e) => e.data).join('|');
    expect(runText, contains('5.0 km'));
    expect(runText, contains('25 min'));
    final walk = t
        .widgetList<Text>(find.descendant(
            of: key('progress.tile.walk'), matching: find.byType(Text)))
        .map((e) => e.data)
        .join('|');
    expect(walk, contains('No data'));
    expect(walk, contains('10 min'));
    expect(walk, isNot(contains('0.0 km')));
    expect(find.textContaining(RegExp('kcal|calor', caseSensitive: false)),
        findsNothing);
  });

  testWidgets('AC-PR-6 one session id is one recent row (upserted journal)',
      (t) async {
    // The journal upserts by id, so the second put replaces the first.
    final first = runEntry('same', dist: 1000);
    final second = runEntry('same', dist: 2000);
    final upserted = {first.id: first}..[second.id] = second;
    await pumpProgress(
        t, dashOverrides(journal: FakeJournal(upserted.values.toList())));
    expect(find.byKey(const Key('progress.recent.row.same')), findsOneWidget);
    expect(find.textContaining('2.0 km'), findsWidgets);
  });

  testWidgets('AC-PR-8 the gym dashboard children keep first and last place',
      (t) async {
    await pumpProgress(t, dashOverrides(localJournal: false));
    final before = [
      top(t, find.text('day streak')),
      top(t, find.text('Last 8 weeks')),
      top(t, find.textContaining('start your history')),
    ];
    await pumpProgress(
        t, dashOverrides(journal: FakeJournal([runEntry('r1')])));
    final after = [
      top(t, find.text('day streak')),
      top(t, find.text('Last 8 weeks')),
      top(t, find.textContaining('start your history')),
    ];
    // Headline first, history text last in both states, same order.
    expect(before[0], lessThan(before[1]));
    expect(before[1], lessThan(before[2]));
    expect(after[0], lessThan(after[1]));
    expect(after[1], lessThan(after[2]));
    expect(after[0], before[0], reason: 'the headline does not move');
    expect(find.text('workouts'), findsOneWidget);
    expect(find.text('records'), findsOneWidget);
  });

  group('AC-PR-9 clearance above the strip', () {
    Widget dock(double h) => ShellLayout(
          info: WindowSizeInfo.forClass(WindowSizeClass.compact),
          navigation: ShellNavigation.bar,
          railWidth: 0,
          railFootprint: 0,
          contentStartInset: 0,
          bottomClearance: 100 + h,
          dockHeight: h,
          child: const ProgressPage(),
        );

    Future<double> lastBottom(WidgetTester t, double h) async {
      await surface(t, 400, 700);
      await t.pumpWidget(appHost(dock(h), overrides: dashOverrides(
          journal: FakeJournal([runEntry('r1')]))));
      await settle(t, 8);
      final s = t.state<ScrollableState>(find.byType(Scrollable).first);
      s.position.jumpTo(s.position.maxScrollExtent);
      await settle(t, 8);
      return t.getBottomLeft(find.textContaining('start your history')).dy;
    }

    testWidgets('AC-PR-9 the foot grows by the dock height', (t) async {
      final without = await lastBottom(t, 0);
      final withDock = await lastBottom(t, 56);
      expect(without - withDock, closeTo(56, 1.0),
          reason: 'content clears the strip by exactly the dock height');
      expect(withDock, lessThanOrEqualTo(700 - 56));
    });
  });

  group('AC-PR-10 distance format', () {
    for (final loc in ['en', 'ru']) {
      testWidgets('AC-PR-10/$loc', (t) async {
        await pumpProgress(
            t, dashOverrides(journal: FakeJournal([runEntry('r', dist: 5200)])),
            locale: Locale(loc));
        final tile = t
            .widgetList<Text>(find.descendant(
                of: key('progress.tile.run'), matching: find.byType(Text)))
            .map((e) => e.data ?? '')
            .join('|');
        if (loc == 'en') {
          expect(tile, contains('5.2 km'));
        } else {
          expect(tile, contains('5,2'));
          expect(tile, isNot(contains('5.2')));
          expect(tile, isNot(contains('km')));
        }
      });
    }
  });

  group('AC-LS-4 two columns and tile columns', () {
    JournalEntry g(String id, SportType s) =>
        entry(sess(id, sport: s, start: kNow, dist: 1000, time: 60));
    int expectedCols(double avail) {
      final c = ((avail + 12) / 172).floor();
      return c < 1 ? 1 : (c > 3 ? 3 : c);
    }

    for (final size in [(1100.0, 'wide'), (700.0, 'medium'), (360.0, 'compact')]) {
      testWidgets('AC-LS-4/${size.$1.toInt()}', (t) async {
        final j = FakeJournal([
          g('a', SportType.running),
          g('b', SportType.cycling),
          g('c', SportType.rowing),
        ]);
        await pumpProgress(t, dashOverrides(journal: j), w: size.$1, h: 3000);
        final block = find.byType(ProgressActivityBlock);
        final avail = t.getSize(block).width;
        final lefts = {
          for (final k in ['run', 'ride', 'row'])
            t.getTopLeft(key('progress.tile.$k')).dx.round()
        };
        expect(lefts.length, expectedCols(avail),
            reason: 'available $avail');
        final tileW = t.getSize(key('progress.tile.run')).width;
        expect(tileW, greaterThanOrEqualTo(160));
        if (size.$1 == 1100) {
          expect(t.getTopLeft(key('progress.allActivity')).dx,
              lessThan(t.getTopLeft(find.byType(BodyScanEntryCard)).dx));
        } else {
          expect(top(t, key('progress.allActivity')),
              lessThan(top(t, find.byType(BodyScanEntryCard))));
        }
      });
    }
  });

  group('AC-LS-5 state mapping in two columns (1100 wide)', () {
    testWidgets('AC-LS-5/failed: error panel in the left column', (t) async {
      final j = FakeJournal()..listError = StateError('x');
      await pumpProgress(t, dashOverrides(journal: j), w: 1100, h: 3000);
      expect(key('progress.journalError'), findsOneWidget);
      expect(key('progress.journalRetry'), findsOneWidget);
      expect(t.getTopLeft(key('progress.journalError')).dx,
          lessThan(t.getTopLeft(find.byType(BodyScanEntryCard)).dx));
    });
    testWidgets('AC-LS-5/zero: only the Sources slot, right column',
        (t) async {
      await pumpProgress(t, dashOverrides(journal: FakeJournal()),
          w: 1100, h: 3000);
      expect(key('progress.slot.sources'), findsOneWidget);
      expect(key('progress.allActivity'), findsNothing);
      expect(t.getTopLeft(key('progress.slot.sources')).dx,
          greaterThanOrEqualTo(t.getTopLeft(find.byType(BodyScanEntryCard)).dx));
    });
    testWidgets('AC-LS-5/loading: the Sources row is shown first', (t) async {
      final j = ScopedFakeJournal();
      await pumpProgress(t, dashOverrides(journal: j, timers: FakeTimers()),
          w: 1100, h: 3000);
      expect(key('progress.slot.sources'), findsOneWidget);
      expect(key('progress.journalError'), findsNothing);
      expect(key('progress.allActivity'), findsNothing);
    });
  });

  group('DT-14-1 error panel states', () {
    testWidgets('DT-14-1/failedToOpen: message, no Try again', (t) async {
      // Flag on, no journal object: failedToOpen.
      await pumpProgress(t, dashOverrides());
      expect(key('progress.journalError'), findsOneWidget);
      expect(key('progress.journalRetry'), findsNothing);
      expect(find.text('Activity history on this device could not be opened.'),
          findsOneWidget);
    });
    testWidgets('DT-14-1/binding shows loading, never this panel', (t) async {
      await pumpProgress(
          t, dashOverrides(journal: ScopedFakeJournal(), timers: FakeTimers()));
      expect(key('progress.journalError'), findsNothing);
    });
  });

  testWidgets('DT-14-2 the new block does not move the viewport offset',
      (t) async {
    final j = FakeJournal([runEntry('r1')]);
    final g = Completer<List<JournalEntry>>();
    j.gateQueue.add(g);
    await surface(t, 400, 1000);
    await t.pumpWidget(
        appHost(const ProgressPage(), overrides: dashOverrides(journal: j)));
    await settle(t);
    final s = t.state<ScrollableState>(find.byType(Scrollable).first);
    expect(s.position.maxScrollExtent, greaterThan(450));
    s.position.jumpTo(400);
    await settle(t, 2);
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'no skeleton');
    final yBefore = t.getTopLeft(find.text('Last 8 weeks')).dy;
    g.complete([runEntry('r1')]);
    await settle(t);
    // The offset is compensated by design (e35a3f66); the visible content is
    // what must not move.
    expect(s.position.pixels, greaterThan(400));
    final yAfter = t.getTopLeft(find.text('Last 8 weeks')).dy;
    // The user-visible reading of "no jump": the content under the finger stays.
    expect(yAfter, closeTo(yBefore, 1.0),
        reason: 'content below the inserted block jumped by ${yAfter - yBefore}');
  });

  testWidgets('DT-14-3 the tree follows each state (A data, B error, B ok)',
      (t) async {
    final j = FakeJournal([runEntry('a1')]);
    final auth = StreamController<AuthUser?>.broadcast();
    addTearDown(auth.close);
    await surface(t, 800, 2400);
    await t.pumpWidget(appHost(const ProgressPage(),
        overrides: dashOverrides(journal: j, auth: auth)));
    auth.add(user('A'));
    await settle(t);
    expect(key('progress.allActivity'), findsOneWidget);
    j.listError = StateError('b');
    auth.add(user('B'));
    await settle(t);
    expect(key('progress.allActivity'), findsNothing,
        reason: 'no stale block of A under B');
    expect(key('progress.journalError'), findsOneWidget);
    j
      ..listError = null
      ..entries = [runEntry('b1')];
    await t.tap(key('progress.journalRetry'));
    await settle(t);
    expect(key('progress.journalError'), findsNothing);
    expect(key('progress.allActivity'), findsOneWidget);
    expect(key('progress.recent.row.b1'), findsOneWidget);
    expect(key('progress.recent.row.a1'), findsNothing);
  });

  group('DT-14-4 Estimate marker', () {
    Widget tile(bool Function(String) pred) => appHost(Scaffold(
          body: ProgressWeekTile(
            tile: const WeekTile(
                group: SportGroup.run,
                sessions: 1,
                timeSeconds: 600,
                timeContributing: 1,
                distanceM: 1000,
                distanceContributing: 1),
            isEstimateField: pred,
          ),
        ));
    testWidgets('DT-14-4/real predicate: never rendered', (t) async {
      await t.pumpWidget(tile((f) => isEstimate(f, sess('x', start: kNow))));
      await t.pump();
      expect(find.textContaining('Estimate'), findsNothing);
    });
    testWidgets('DT-14-4/forced true: marker renders', (t) async {
      await t.pumpWidget(tile((_) => true));
      await t.pump();
      expect(find.textContaining('Estimate'), findsWidgets);
    });
  });

  group('DT-14-5 recovery notice', () {
    testWidgets('DT-14-5/2 lost: notice and may be incomplete', (t) async {
      final j = ScopedFakeJournal([runEntry('r1')])
        ..autoSucceed = true
        ..report = (JournalRecoveryReport()..absent.addAll(['x', 'y']));
      await pumpProgress(t, dashOverrides(journal: j, timers: FakeTimers()));
      expect(find.text('2 activities could not be fully restored on this device'),
          findsOneWidget);
      expect(find.text('Totals may be incomplete'), findsOneWidget);
    });
    testWidgets('DT-14-5/0 lost: absent', (t) async {
      final j = ScopedFakeJournal([runEntry('r1')])..autoSucceed = true;
      await pumpProgress(t, dashOverrides(journal: j, timers: FakeTimers()));
      expect(find.textContaining('could not be fully restored'), findsNothing);
      expect(find.text('Totals may be incomplete'), findsNothing);
    });
  });

  testWidgets('DT-14-6 failed refresh keeps values and shows a stale line',
      (t) async {
    final j = FakeJournal([runEntry('r1')]);
    await pumpProgress(t, dashOverrides(journal: j));
    expect(key('progress.stale'), findsNothing);
    j.listError = StateError('x');
    await containerOf(t).read(activityDigestsProvider.notifier).refresh();
    await settle(t);
    expect(key('progress.recent.row.r1'), findsOneWidget);
    expect(key('progress.stale'), findsOneWidget);
    expect(find.textContaining('Showing data from'), findsOneWidget);
    expect(key('progress.staleRetry'), findsOneWidget);
  });

  testWidgets('DT-14-7 a deleted activity leaves only after a refresh',
      (t) async {
    final j = FakeJournal([runEntry('a'), runEntry('b'), runEntry('c')]);
    await pumpProgress(t, dashOverrides(journal: j));
    expect(find.byKey(const Key('progress.recent.row.b')), findsOneWidget);
    j.entries = [runEntry('a'), runEntry('c')];
    await settle(t);
    expect(find.byKey(const Key('progress.recent.row.b')), findsOneWidget,
        reason: 'stays until a refresh');
    await containerOf(t).read(activityDigestsProvider.notifier).refresh();
    await settle(t);
    expect(find.byKey(const Key('progress.recent.row.b')), findsNothing);
    expect(j.tombstoneCalls, 0);
  });

  testWidgets('DT-14-9 refreshIfStale: entry only, 60 s rule, never build',
      (t) async {
    final j = FakeJournal([runEntry('r1')]);
    var now = kNow;
    final overrides = dashOverrides(journal: j, clock: () => now);
    final show = ValueNotifier<bool>(true);
    addTearDown(show.dispose);
    await surface(t, 800, 2400);
    await t.pumpWidget(appHost(
        ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, v, __) =>
                v ? const ProgressPage() : const SizedBox()),
        overrides: overrides));
    await settle(t);
    expect(j.listCalls, 1);
    // Rebuild the page five times without any lifecycle change.
    for (var i = 0; i < 5; i++) {
      t.view.physicalSize = Size(800 + i.toDouble(), 2400);
      await settle(t, 2);
    }
    expect(j.listCalls, 1, reason: 'rebuilds do not load');
    Future<void> reenter() async {
      show.value = false;
      await settle(t, 2);
      show.value = true;
      await settle(t);
    }

    // Re-enter within 60 s: fresh, no load.
    now = kNow.add(const Duration(seconds: 59));
    await reenter();
    expect(j.listCalls, 1);
    // Re-enter after 61 s: exactly one refresh.
    now = kNow.add(const Duration(seconds: 61));
    await reenter();
    expect(j.listCalls, 2);
  });

  testWidgets('DT-14-10 loading to errorRetry at a non-zero offset: heading stays',
      (t) async {
    final j = FakeJournal();
    final g = Completer<List<JournalEntry>>();
    j.gateQueue.add(g);
    await surface(t, 400, 1000);
    await t.pumpWidget(
        appHost(const ProgressPage(), overrides: dashOverrides(journal: j)));
    await settle(t);
    final s = t.state<ScrollableState>(find.byType(Scrollable).first);
    expect(s.position.maxScrollExtent, greaterThan(450));
    s.position.jumpTo(400);
    await settle(t, 2);
    final yBefore = t.getTopLeft(find.text('Last 8 weeks')).dy;
    g.completeError(StateError('boom'));
    await settle(t);
    final yAfter = t.getTopLeft(find.text('Last 8 weeks')).dy;
    s.position.jumpTo(0);
    await settle(t, 3);
    expect(key('progress.journalError'), findsOneWidget);
    expect(yAfter, closeTo(yBefore, 1.0),
        reason: 'the Sources slot stays in errorRetry, so no slot height may '
            'be subtracted: shifted by ${yAfter - yBefore}');
  });

  testWidgets('DT-14-11 gaveUp: Try again is disabled while the attempt runs',
      (t) async {
    final j = ScopedFakeJournal();
    final timers = FakeTimers();
    await pumpProgress(t, dashOverrides(journal: j, timers: timers));
    for (var i = 0; i < 5; i++) {
      j.complete(false);
      await settle(t, 2);
      timers.all.last.fire();
      await settle(t, 2);
    }
    j.complete(false);
    await settle(t);
    HudButton retry() => t.widget<HudButton>(key('progress.journalRetry'));
    expect(retry().onPressed, isNotNull);
    await t.tap(key('progress.journalRetry'));
    await settle(t, 2);
    expect(retry().onPressed, isNull, reason: 'busy while bindBusy');
    j.complete(false);
    await settle(t);
    expect(retry().onPressed, isNotNull);
  });

  testWidgets('DT-14-12 account switch: no tile order of the previous mode',
      (t) async {
    final fake = FakeModeN(ModeState(
        selectedMode: AppMode.ride, chooserStatus: ChooserStatus.resolved));
    final j = FakeJournal([
      runEntry('run1'),
      entry(sess('ride1',
          sport: SportType.cycling, start: kNow, dist: 1000, time: 60)),
    ]);
    await pumpProgress(t, [
      ...dashOverrides(journal: j),
      modeStateProvider.overrideWith(() => fake),
    ], w: 800);
    double dx(String k) => t.getTopLeft(key('progress.tile.$k')).dx;
    expect(dx('ride'), lessThan(dx('run')), reason: 'RIDE lens puts ride first');
    fake.reloadKeepingPrevious();
    await settle(t);
    expect(dx('run'), lessThan(dx('ride')),
        reason: 'while the next mode loads the fixed order is used');
  });
}
