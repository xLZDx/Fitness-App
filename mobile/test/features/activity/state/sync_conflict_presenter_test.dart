// S02-12 I42: the sync-conflict UI state and choice wiring, over the REAL
// repository and journal with the two-device fake server, plus one widget test
// of the choice sheet. No pixel assertions (layout is NOT_RUN by design).
import 'dart:async';

import 'package:fitness_app/features/activity/data/summary_projection.dart'
    show CandidateChoice;
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:fitness_app/features/activity/state/sync_conflict_presenter.dart';
import 'package:fitness_app/features/activity/widgets/sync_conflict_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import '../../../helpers/test_app.dart';
import '../../../support/two_device_world.dart';

Future<void> until(bool Function() cond, {int ms = 4000}) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('condition not reached in ${ms}ms');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

ProviderContainer containerFor(Device d) {
  final c = ProviderContainer(
      overrides: [activitySyncRepositoryProvider.overrideWithValue(d.repo)]);
  c.listen(syncConflictPresenterProvider, (_, __) {}); // keep alive
  return c;
}

/// Device B in same-field conflict (A 5000, B 5200).
Future<String> sameFieldConflict(World w) async {
  final id = await w.bothSynced();
  await w.a.change(id, distanceM: 5000);
  await w.b.change(id, distanceM: 5200);
  return id;
}

/// Device B with a source candidate under an explicit value (G33).
Future<String> sourceCandidate(World w) async {
  final id = await w.bothSynced();
  await w.b.repo.applyExplicitEdit(id, {'distanceM': 4800});
  await w.b.change(id, distanceM: 5100, replaceStreams: true);
  return id;
}

void main() {
  late World w;
  setUp(() async => w = await World.open());
  tearDown(() async => w.dispose());

  group('presenter state', () {
    test('a conflict is shown with the device AND the cloud value of each '
        'conflicting field, not as a generic error', () async {
      final id = await sameFieldConflict(w);
      final c = containerFor(w.b);
      addTearDown(c.dispose);
      await until(() => c.read(syncConflictPresenterProvider).conflicts.isNotEmpty);
      final v = c.read(syncConflictPresenterProvider);
      expect(v.conflicts.single.id, id);
      final f = v.conflicts.single.fields.single;
      expect([f.field, f.deviceValue, f.cloudValue], ['distanceM', 5200, 5000]);
      expect(v.conflicts.single.cloudKnown, isTrue);
      expect(v.candidates, isEmpty);
      expect(v.lastFailed, isFalse);
    });

    test('keep this device: one call even on a double tap, conflict gone only '
        'after the value is stored, server holds 5200', () async {
      final id = await sameFieldConflict(w);
      final c = containerFor(w.b);
      addTearDown(c.dispose);
      await until(() => c.read(syncConflictPresenterProvider).hasItems);
      final p = c.read(syncConflictPresenterProvider.notifier);
      final writes = w.server.accepted.length;
      await Future.wait([p.keepDevice(id), p.keepDevice(id)]);
      await until(() => !c.read(syncConflictPresenterProvider).hasItems);
      expect(w.server.accepted.length, writes + 1, reason: 'exactly one write');
      expect(w.server.docs[id]!['distanceM'], 5200);
      expect(await w.b.syncState(id), JournalSyncState.synced);
      expect(c.read(syncConflictPresenterProvider).busy, isEmpty);
    });

    test('keep cloud is NOT swapped with keep device: no server write, the '
        'cloud value wins locally', () async {
      final id = await sameFieldConflict(w);
      final c = containerFor(w.b);
      addTearDown(c.dispose);
      await until(() => c.read(syncConflictPresenterProvider).hasItems);
      final writes = w.server.accepted.length;
      await c.read(syncConflictPresenterProvider.notifier).keepCloud(id);
      await until(() => !c.read(syncConflictPresenterProvider).hasItems);
      expect(w.server.accepted.length, writes);
      expect(w.server.docs[id]!['distanceM'], 5000);
      expect(await w.b.effectiveOf(id, 'distanceM'), 5000);
    });

    test('an offline choice keeps the entry and flags the failure', () async {
      final id = await sameFieldConflict(w);
      final c = containerFor(w.b);
      addTearDown(c.dispose);
      await until(() => c.read(syncConflictPresenterProvider).hasItems);
      w.b.backend.offline = true;
      await c.read(syncConflictPresenterProvider.notifier).keepDevice(id);
      expect(c.read(syncConflictPresenterProvider).lastFailed, isTrue);
      expect(c.read(syncConflictPresenterProvider).conflicts, hasLength(1));
      expect(await w.b.syncState(id), JournalSyncState.syncConflict);
    });

    test('the unresolved conflict reappears after a restart', () async {
      final id = await sameFieldConflict(w);
      await w.b.restart();
      final c = containerFor(w.b);
      addTearDown(c.dispose);
      await until(() => c.read(syncConflictPresenterProvider).hasItems);
      expect(c.read(syncConflictPresenterProvider).conflicts.single.id, id);
    });

    test('a conflict never offers a delete path: local data and tombstones stay '
        'untouched', () async {
      final id = await sameFieldConflict(w);
      expect(await w.b.h.journal.listTombstones(), isEmpty);
      final c = containerFor(w.b);
      addTearDown(c.dispose);
      await until(() => c.read(syncConflictPresenterProvider).hasItems);
      expect(c.read(syncConflictPresenterProvider).conflicts.single.id, id);
      expect(await w.b.h.listIds(), [id]);
    });

    test('candidates: a source candidate of an explicit value is listed '
        'although the activity is synced, with the right actions', () async {
      final id = await sourceCandidate(w);
      expect(await w.b.syncState(id), JournalSyncState.synced);
      final c = containerFor(w.b);
      addTearDown(c.dispose);
      await until(() => c.read(syncConflictPresenterProvider).candidates.isNotEmpty);
      final cand = c.read(syncConflictPresenterProvider).candidates.single;
      expect(cand.reason, CandidateReason.source);
      expect([cand.explicitValue, cand.computedValue, cand.cloudValue],
          [4800, 5100, null]);
      expect(cand.choices, {CandidateChoice.useComputed, CandidateChoice.keepMine});
      expect(c.read(syncConflictPresenterProvider).conflicts, isEmpty);
    });

    test('keep my value: one call; the entry leaves only after the resolution '
        'is stored, keeps the explicit entry and does not reappear after a '
        'restart', () async {
      final id = await sourceCandidate(w);
      final c = containerFor(w.b);
      addTearDown(c.dispose);
      await until(() => c.read(syncConflictPresenterProvider).candidates.isNotEmpty);
      final p = c.read(syncConflictPresenterProvider.notifier);
      await Future.wait([
        p.resolveCandidate(id, 'distanceM', CandidateChoice.keepMine),
        p.resolveCandidate(id, 'distanceM', CandidateChoice.keepMine),
      ]);
      await until(() => c.read(syncConflictPresenterProvider).candidates.isEmpty);
      expect(((await w.b.explicit(id))['distanceM'] as Map)['value'], 4800);
      await w.b.restart();
      final c2 = containerFor(w.b);
      addTearDown(c2.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(c2.read(syncConflictPresenterProvider).candidates, isEmpty);
    });

    test('use the new computed value is wired to its own action (labels not '
        'swapped): the explicit entry is REMOVED and 5100 is written', () async {
      final id = await sourceCandidate(w);
      final c = containerFor(w.b);
      addTearDown(c.dispose);
      await until(() => c.read(syncConflictPresenterProvider).candidates.isNotEmpty);
      await c
          .read(syncConflictPresenterProvider.notifier)
          .resolveCandidate(id, 'distanceM', CandidateChoice.useComputed);
      await until(() => c.read(syncConflictPresenterProvider).candidates.isEmpty);
      expect(await w.b.explicit(id), isEmpty);
      expect(w.server.docs[id]!['distanceM'], 5100);
    });

    test('a recalculation candidate (override path) offers exactly the two '
        'recalculation actions with the adopted cloud value', () async {
      final id = await w.adopted();
      w.b.versions = kV2;
      await w.b.change(id, distanceM: 4830);
      final c = containerFor(w.b);
      addTearDown(c.dispose);
      await until(() => c.read(syncConflictPresenterProvider).candidates.isNotEmpty);
      final cand = c.read(syncConflictPresenterProvider).candidates.single;
      expect(cand.reason, CandidateReason.recalculation);
      expect([cand.cloudValue, cand.computedValue, cand.explicitValue], [5000, 4830, null]);
      expect(cand.choices, {CandidateChoice.useComputed, CandidateChoice.useCloud});
    });

    test('no candidate entry for a field without a candidate', () async {
      await w.adopted();
      final c = containerFor(w.b);
      addTearDown(c.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(c.read(syncConflictPresenterProvider).hasItems, isFalse);
    });
  });

  group('the choice sheet', () {
    testWidgets('shows both values and only the choice actions (no delete, '
        'no coordinates, no heart rate); a repeated show does not stack; the '
        'conflict leaves after the choice is stored', (tester) async {
      late String id;
      await tester.runAsync(() async => id = await sameFieldConflict(w));
      await tester.pumpWidget(ProviderScope(
        overrides: [activitySyncRepositoryProvider.overrideWithValue(w.b.repo)],
        child: MaterialApp(
          locale: kTestLocale,
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: const [Locale('en')],
          theme: _theme(),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () {
                  SyncConflictSheet.show(ctx);
                  SyncConflictSheet.show(ctx);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pump();
      await settle(tester);

      expect(find.byType(SyncConflictSheet), findsOneWidget);
      expect(find.byKey(Key('activitySync.conflict.$id')), findsOneWidget);
      expect(find.byKey(Key('activitySync.field.$id.distanceM')), findsOneWidget);
      expect(find.textContaining('5200'), findsOneWidget);
      expect(find.textContaining('5000'), findsOneWidget);
      expect(find.byKey(Key('activitySync.keepDevice.$id')), findsOneWidget);
      expect(find.byKey(Key('activitySync.keepCloud.$id')), findsOneWidget);
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
          .join(' | ');
      final buttonLabels = [
        for (final b in [
          ...tester.widgetList<OutlinedButton>(find.byType(OutlinedButton)),
          ...tester.widgetList<FilledButton>(find.byType(FilledButton)),
        ])
          ((b.child as Text).data ?? '').toLowerCase()
      ];
      expect(buttonLabels, hasLength(2));
      for (final l in buttonLabels) {
        expect(l, isNot(contains('delete')));
        expect(l, isNot(contains('remove')));
      }
      expect(texts, isNot(contains('7351')));
      expect(texts, isNot(contains('173.25')));
      expect(texts.toLowerCase(), isNot(contains('heart')));
      expect(texts.toLowerCase(), isNot(contains('latitude')));
      expect(find.byType(OutlinedButton).evaluate().length +
              find.byType(FilledButton).evaluate().length,
          2, reason: 'only the two resolution actions exist');

      await tapReal(tester, find.byKey(Key('activitySync.keepDevice.$id')));
      expect(w.server.docs[id]!['distanceM'], 5200);
      expect(find.byKey(Key('activitySync.conflict.$id')), findsNothing);
      expect(find.byKey(const Key('activitySync.empty')), findsOneWidget);
    });

    testWidgets('a candidate card offers three actions with an override and '
        'each reaches its own repository operation', (tester) async {
      late String id;
      await tester.runAsync(() async {
        id = await w.bothSynced();
        await w.b.repo.applyExplicitEdit(id, {'distanceM': 4800});
        await w.b.change(id, distanceM: 5100, replaceStreams: true);
        await w.a.change(id, distanceM: 5400);
        await w.b.change(id, ascentM: 33);
      });
      await tester.pumpWidget(ProviderScope(
        overrides: [activitySyncRepositoryProvider.overrideWithValue(w.b.repo)],
        child: MaterialApp(
          locale: kTestLocale,
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: const [Locale('en')],
          theme: _theme(),
          home: const Scaffold(body: SyncConflictSheet()),
        ),
      ));
      await settle(tester);
      for (final n in ['useComputed', 'keepMine', 'useCloud']) {
        expect(find.byKey(Key('activitySync.choice.$n.$id.distanceM')), findsOneWidget,
            reason: n);
      }
      await tapReal(tester, find.byKey(Key('activitySync.choice.useCloud.$id.distanceM')));
      expect(find.byKey(Key('activitySync.candidate.$id.distanceM')), findsNothing);
      expect(await tester.runAsync(() => w.b.explicit(id)), isEmpty,
          reason: 'use the cloud value removes the explicit entry');
    });
  });
}

/// Taps inside the real-async zone so the repository's futures run there.
Future<void> tapReal(WidgetTester tester, Finder f) async {
  await tester.runAsync(() async {
    await tester.tap(f);
    await Future<void>.delayed(const Duration(milliseconds: 400));
  });
  await tester.pump(const Duration(milliseconds: 50));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await settle(tester);
}

/// Lets the real-async repository and the fake-async widget zone alternate.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  }
  await tester.pump(const Duration(milliseconds: 400));
}

ThemeData _theme() => AppTheme.light();
