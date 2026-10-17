// S03-15 Sources panel S-8 (test plan 6.1). Real SourcesPage, fake journals.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/state/activity_dashboard_providers.dart';
import 'package:fitness_app/features/modes/pages/sources_page.dart';
import 'package:fitness_app/shared/widgets/hud/hud_surface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../support/s03_step4_support.dart';

Finder key(String k) => find.byKey(Key(k));

Future<void> settle(WidgetTester t, [int n = 5]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
}

Future<void> pumpSources(
  WidgetTester t,
  List<Override> overrides, {
  double w = 360,
  double h = 1800,
  Locale locale = const Locale('en'),
}) async {
  t.view.physicalSize = Size(w, h);
  t.view.devicePixelRatio = 1.0;
  addTearDown(() {
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
  await t.pumpWidget(
      appHost(const SourcesPage(), overrides: overrides, locale: locale));
  await settle(t);
}

/// The label of the row's container semantics node.
String rowLabel(WidgetTester t, String id) {
  final f = find.descendant(
      of: key('sources.row.$id'),
      matching: find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.label ?? '').isNotEmpty));
  expect(f, findsWidgets, reason: 'row $id has a labelled semantics node');
  return (t.widget(f.first) as Semantics).properties.label!;
}

JournalEntry runEntry(String id) =>
    entry(sess(id, start: kNow, dist: 1000, time: 60));

Future<ScopedFakeJournal> toGaveUp(WidgetTester t, FakeTimers timers) async {
  final j = ScopedFakeJournal();
  await pumpSources(t, dashOverrides(journal: j, timers: timers));
  for (var i = 0; i < 5; i++) {
    j.complete(false);
    await settle(t, 2);
    timers.all.last.fire();
    await settle(t, 2);
  }
  j.complete(false);
  await settle(t);
  return j;
}

void main() {
  group('AC-SRC-1 app row follows the journal', () {
    testWidgets('AC-SRC-1/emptyOpen', (t) async {
      await pumpSources(t, dashOverrides(journal: FakeJournal()));
      expect(rowLabel(t, 'app'), contains('Ready'));
    });
    testWidgets('AC-SRC-1/oneSession', (t) async {
      await pumpSources(t, dashOverrides(journal: FakeJournal([runEntry('a')])));
      expect(rowLabel(t, 'app'), contains('In use'));
    });
  });

  testWidgets('AC-SRC-2 notEnabled: not-active line, no retry, no Problem',
      (t) async {
    await pumpSources(t, dashOverrides(localJournal: false));
    expect(rowLabel(t, 'app'),
        contains('Activity history is not active in this build.'));
    expect(key('sources.app.retry'), findsNothing);
    expect(find.textContaining('Problem'), findsNothing);
  });

  testWidgets('AC-SRC-3 gaveUp: Problem and exactly one attempt per tap',
      (t) async {
    final timers = FakeTimers();
    final j = await toGaveUp(t, timers);
    expect(j.bindCalls, hasLength(6));
    expect(rowLabel(t, 'app'), contains('Problem'));
    expect(key('sources.app.retry'), findsOneWidget);
    await t.tap(key('sources.app.retry'));
    await settle(t, 2);
    expect(j.bindCalls, hasLength(7));
    await t.tap(key('sources.app.retry'), warnIfMissed: false);
    await settle(t, 2);
    expect(j.bindCalls, hasLength(7), reason: 'no concurrent second attempt');
    j.complete(true);
    await settle(t);
  });

  testWidgets('AC-SRC-4 other rows: Not connected and not actionable',
      (t) async {
    final sem = t.ensureSemantics();
    await pumpSources(t, dashOverrides(journal: FakeJournal()));
    for (final id in ['health_connect', 'ble', 'wear_os', 'vendor_cloud']) {
      expect(rowLabel(t, id), contains('Not connected'), reason: id);
      expect(
          find.descendant(
              of: key('sources.row.$id'), matching: find.byType(HudButton)),
          findsNothing,
          reason: id);
      final node = find.descendant(
          of: key('sources.row.$id'),
          matching: find.byWidgetPredicate(
              (w) => w is Semantics && (w.properties.label ?? '').isNotEmpty));
      final data = t.getSemantics(node.first).getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isFalse, reason: id);
    }
    sem.dispose();
  });

  for (final loc in ['en', 'ru']) {
    testWidgets('AC-SRC-5/$loc dedup note exists', (t) async {
      await pumpSources(t, dashOverrides(journal: FakeJournal()),
          locale: Locale(loc));
      expect(key('sources.dedupNote'), findsOneWidget);
    });
  }

  test('AC-SRC-5k no promise of merging or a Health Connect sync in copy', () {
    final banned = [
      RegExp('merged', caseSensitive: false),
      RegExp('deduplicated', caseSensitive: false),
      RegExp('synced with Health Connect', caseSensitive: false),
      RegExp('объединен|объединён|дедуплицир', caseSensitive: false),
      RegExp('синхронизирован\\w* с Health Connect', caseSensitive: false),
    ];
    final prefixes = RegExp(
        r'^(mode|home|progress|activity|source|sources|strip|rail|record|signOut|sportGroup|syncChip|nav)');
    var scanned = 0;
    for (final f in ['lib/l10n/app_en.arb', 'lib/l10n/app_ru.arb']) {
      final text = File(f).readAsStringSync();
      final entries = RegExp(r'^\s*"([A-Za-z0-9_]+)":\s*"((?:[^"\\]|\\.)*)"',
              multiLine: true)
          .allMatches(text);
      for (final m in entries) {
        final k = m.group(1)!;
        if (k.startsWith('@') || !prefixes.hasMatch(k)) continue;
        scanned++;
        for (final b in banned) {
          expect(b.hasMatch(m.group(2)!), isFalse, reason: '$f $k');
        }
      }
    }
    expect(scanned, greaterThan(100), reason: 'the scan must read real keys');
    // The allowed stem: the English dedup note says "merge".
    expect(File('lib/l10n/app_en.arb').readAsStringSync(),
        contains('we do not yet merge them automatically'));
  });

  testWidgets('AC-SRC-7 one semantics node per row with name and status',
      (t) async {
    final sem = t.ensureSemantics();
    await pumpSources(t, dashOverrides(journal: FakeJournal()));
    final names = {
      'app': 'Ready',
      'health_connect': 'Not connected',
      'ble': 'Not connected',
      'wear_os': 'Not connected',
      'vendor_cloud': 'Not connected',
    };
    for (final e in names.entries) {
      final label = rowLabel(t, e.key);
      expect(label, contains(e.value));
      expect(label, contains(', '), reason: 'name, status in one label');
      final nodes = find.descendant(
          of: key('sources.row.${e.key}'),
          matching: find.byWidgetPredicate((w) =>
              w is Semantics &&
              (w.properties.label ?? '').contains(e.value)));
      expect(nodes, findsOneWidget, reason: '${e.key}: one labelled node');
    }
    sem.dispose();
  });

  group('AC-LS-6 layout', () {
    testWidgets('AC-LS-6/1100x800', (t) async {
      await pumpSources(t, dashOverrides(journal: FakeJournal()),
          w: 1100, h: 1800);
      final note = t.getTopLeft(key('sources.dedupNote'));
      for (final id in ['app', 'health_connect', 'ble', 'wear_os', 'vendor_cloud']) {
        expect(t.getTopLeft(key('sources.row.$id')).dx, lessThan(note.dx),
            reason: id);
      }
      final left = t.getTopLeft(key('sources.row.app')).dx;
      final right = t.getBottomRight(key('sources.dedupNote')).dx;
      expect(right - left, lessThanOrEqualTo(880));
      expect(rowLabel(t, 'app'), contains('Ready'));
    });
    testWidgets('AC-LS-6/700x900', (t) async {
      await pumpSources(t, dashOverrides(journal: FakeJournal()),
          w: 700, h: 1800);
      expect(t.getTopLeft(key('sources.dedupNote')).dy,
          greaterThan(t.getTopLeft(key('sources.row.vendor_cloud')).dy));
      expect(t.getTopLeft(key('sources.dedupNote')).dx,
          t.getTopLeft(key('sources.row.app')).dx);
    });
  });

  testWidgets('DT-15-1 binding: plain Checking text, no spinner, then final',
      (t) async {
    final j = ScopedFakeJournal([runEntry('a')]);
    await pumpSources(t, dashOverrides(journal: j, timers: FakeTimers()));
    expect(rowLabel(t, 'app'), contains('Checking'));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    j.complete(true);
    await settle(t);
    expect(rowLabel(t, 'app'), contains('In use'));
  });

  for (final p in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    testWidgets('DT-15-2/${p.name} no Apple Health row', (t) async {
      debugDefaultTargetPlatformOverride = p;
      try {
        await pumpSources(t, dashOverrides(journal: FakeJournal()));
        expect(key('sources.row.healthkit'), findsNothing);
        expect(find.textContaining('Apple'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  test('DT-15-3 the page touches no source adapter or permission (source scan)',
      () {
    final src = File('lib/features/modes/pages/sources_page.dart')
        .readAsStringSync();
    for (final bad in [
      'healthStatus',
      'requestPermission',
      'permission_handler',
      'health_connect_adapter',
      'package:health',
    ]) {
      expect(src.contains(bad), isFalse, reason: bad);
    }
    expect(src, contains('refreshIfStale'));
  });

  group('DT-15-4 recovery notice', () {
    testWidgets('DT-15-4/2 lost', (t) async {
      final j = ScopedFakeJournal([runEntry('a')])
        ..autoSucceed = true
        ..report = (JournalRecoveryReport()..absent.addAll(['x', 'y']));
      await pumpSources(t, dashOverrides(journal: j, timers: FakeTimers()));
      expect(key('sources.recoveryNotice'), findsOneWidget);
      expect(find.text('2 activities could not be fully restored on this device'),
          findsOneWidget);
    });
    testWidgets('DT-15-4/0 lost', (t) async {
      final j = ScopedFakeJournal([runEntry('a')])..autoSucceed = true;
      await pumpSources(t, dashOverrides(journal: j, timers: FakeTimers()));
      expect(key('sources.recoveryNotice'), findsNothing);
    });
  });

  testWidgets('DT-15-5 a failed refresh is shown as Problem, not In use',
      (t) async {
    final j = FakeJournal([runEntry('a')]);
    await pumpSources(t, dashOverrides(journal: j));
    expect(rowLabel(t, 'app'), contains('In use'));
    j.listError = StateError('x');
    await ProviderScope.containerOf(t.element(find.byType(SourcesPage)))
        .read(activityDigestsProvider.notifier)
        .refresh();
    await settle(t);
    final label = rowLabel(t, 'app');
    expect(label, contains('Problem'),
        reason: 'stale data after a failed refresh must not read as healthy; '
            'label is "$label"');
    expect(label, isNot(contains('In use')));
  });

  for (final loc in ['en', 'ru']) {
    testWidgets('DT-15-6/$loc Health Connect row claims no integration',
        (t) async {
      await pumpSources(t, dashOverrides(journal: FakeJournal()),
          locale: Locale(loc));
      final label = rowLabel(t, 'health_connect');
      if (loc == 'en') {
        expect(label, contains('Not connected'));
        expect(label, isNot(matches(RegExp(r'(?<!Not )(Connected|synced)'))));
      } else {
        expect(label, contains('Не подключ'));
      }
    });
  }
}
