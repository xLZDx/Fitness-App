// S03-01 (EP-1) mode state: load, coercion, availability gate, events, account
// scoping, read-only runs after unreadable values, stale-reference safety, the
// storage K scan. Oracle: S03_TEST_PLAN.md section 2.2 and S03_DESIGN 2.2 / 5.
import 'dart:io';

import 'dart:async';

import 'package:fitness_app/features/modes/data/mode_codec.dart';
import 'package:fitness_app/features/modes/data/mode_models.dart';
import 'package:fitness_app/features/modes/data/mode_store.dart';
import 'package:fitness_app/features/modes/state/mode_flags.dart';
import 'package:fitness_app/features/modes/state/mode_migration.dart';
import 'package:fitness_app/features/modes/state/mode_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/mode_fakes.dart';

void main() {
  group('DT-01-1 corrupt stored values never crash, never write', () {
    const cases = <String, String>{
      'unknown mode string':
          '{"v":1,"mode":"swim","chooser":"resolved","answers":{}}',
      'wrong json type': '[1,2,3]',
      'wrong field type': '{"v":1,"mode":5,"chooser":7}',
      'truncated json': '{"v":1,"mode":"bo',
      'empty string': '',
    };
    for (final e in cases.entries) {
      test(e.key, () async {
        final env = ModeEnv(initialUid: 'u1');
        env.fake.seedRaw('u1', e.value);
        final s = await env.load();
        expect(s.selectedMode, AppMode.train);
        expect(ChooserStatus.values, contains(s.chooserStatus));
        expect(env.fake.writeCalls, 0);
        final read = decodeModeState(e.value);
        if (e.key == 'unknown mode string') {
          expect(read, isA<ModeReadValue>(),
              reason: 'an unknown mode name falls back to train in memory');
          expect(s.chooserStatus, ChooserStatus.resolved);
        } else {
          expect(read, isA<ModeReadUnreadable>());
          expect((read as ModeReadUnreadable).reason, isNotNull);
          // The migration and the onboarding hook do nothing on an
          // unreadable value, and a repair is never silent.
          expect(await env.notifier.initIfAbsent(InitSource.migration),
              ModeSaveResult.unchanged);
          expect(await env.notifier.initIfAbsent(InitSource.onboarding),
              ModeSaveResult.unchanged);
          expect(env.fake.writeCalls, 0);
          expect(s.chooserStatus, ChooserStatus.absent,
              reason: 'never both chooser and intro card: nothing is set');
        }
      });
    }

    test('codec classification of the corrupt values', () {
      expect((decodeModeState('{"v":1,"mode":"bo') as ModeReadUnreadable).reason,
          UnreadableReason.corrupt);
      expect((decodeModeState('[1]') as ModeReadUnreadable).reason,
          UnreadableReason.unknownShape);
      expect(decodeModeState(null), isA<ModeReadMissing>());
    });
  });

  test('DT-01-2 a stored unavailable mode is coerced to train in memory only',
      () async {
    for (final mode in [AppMode.ride, AppMode.explore]) {
      final env = ModeEnv(initialUid: 'u1');
      env.fake.stored['u1'] = ModeReadValue(ModeState(
          selectedMode: mode, chooserStatus: ChooserStatus.resolved));
      env.recordEvents();
      final before = env.fake.stored['u1'];
      final s = await env.load();
      expect(s.selectedMode, AppMode.train, reason: mode.name);
      expect(env.events, isEmpty, reason: 'no modeChanged event');
      expect(env.fake.writeCalls, 0, reason: 'RV-2: not rewritten');
      expect(env.fake.stored['u1'], same(before));
    }
  });

  test('DT-01-3 a missing store reads as absent defaults', () async {
    final env = ModeEnv(initialUid: 'u1');
    final s = await env.load();
    expect(s, ModeState.initial());
    expect(env.fake.writeCalls, 0);
    // The migration decision for a missing value belongs to AC-CH-8: an
    // explicit initIfAbsent writes exactly once.
    expect(await env.notifier.initIfAbsent(InitSource.migration),
        ModeSaveResult.saved);
    expect(env.fake.writes, hasLength(1));
    expect(env.fake.writes.single.state.chooserStatus, ChooserStatus.migrated);
  });

  test('DT-01-19 / DT-01-3 a read that throws gives the default state, no '
      'chooser, zero writes, no exception', () async {
    final env = ModeEnv(initialUid: 'u1');
    env.fake.readError = StateError('platform read failed');
    final s = await env.load();
    expect(s, ModeState.initial());
    expect(s.chooserStatus, isNot(ChooserStatus.pending));
    expect(await env.notifier.initIfAbsent(InitSource.migration),
        ModeSaveResult.unchanged);
    expect(await env.notifier.initIfAbsent(InitSource.onboarding),
        ModeSaveResult.unchanged);
    expect(env.fake.writeCalls, 0);
    // A user choice stays in memory for the session and is not persisted.
    expect(await env.notifier.selectMode(AppMode.body),
        ModeSaveResult.saveFailed);
    expect(env.state.selectedMode, AppMode.body);
    expect(env.fake.writeCalls, 0, reason: 'a failed load is read-only');
  });

  test('DT-01-4 the availability table is the only gate', () async {
    final env = ModeEnv(initialUid: 'u1');
    await env.load();
    env.recordEvents();
    expect(await env.notifier.selectMode(AppMode.body), ModeSaveResult.saved);
    final writesAfterBody = env.fake.writeCalls;
    expect(await env.notifier.selectMode(AppMode.ride),
        ModeSaveResult.unavailable);
    expect(await env.notifier.selectMode(AppMode.explore),
        ModeSaveResult.unavailable);
    expect(env.fake.writeCalls, writesAfterBody, reason: 'no write');
    expect(env.events, hasLength(1), reason: 'no event for a rejected mode');
    expect(env.state.selectedMode, AppMode.body);
    expect(await env.notifier.selectMode(AppMode.train), ModeSaveResult.saved);

    // A test table with ride available: one place to change for S05.
    final env2 = ModeEnv(
        initialUid: 'u2', flags: const ModeFlags(rideEnabled: true));
    await env2.load();
    expect(await env2.notifier.selectMode(AppMode.ride), ModeSaveResult.saved);
    expect(env2.state.selectedMode, AppMode.ride);
    expect(await env2.notifier.selectMode(AppMode.explore),
        ModeSaveResult.unavailable);
  });

  test('DT-01-5 events: one per real change, none for a repeat; a failed '
      'write still changes the session lens', () async {
    final env = ModeEnv(initialUid: 'u1');
    await env.load();
    env.recordEvents();
    await env.notifier.selectMode(AppMode.body);
    expect(await env.notifier.selectMode(AppMode.body),
        ModeSaveResult.unchanged);
    await env.notifier.selectMode(AppMode.train);
    expect(env.events.map((e) => '${e.from.name}>${e.to.name}'),
        ['train>body', 'body>train']);

    env.fake.failWrites = true;
    expect(await env.notifier.selectMode(AppMode.body),
        ModeSaveResult.saveFailed);
    expect(env.state.selectedMode, AppMode.body,
        reason: 'the session lens changes even when the write fails');
    expect(env.events, hasLength(3), reason: 'event emitted once');

    // A throwing store is survived too.
    env.fake.failWrites = false;
    env.fake.throwOnWrite = true;
    expect(await env.notifier.selectMode(AppMode.train),
        ModeSaveResult.saveFailed);
    expect(env.state.selectedMode, AppMode.train);
    expect(env.events, hasLength(4));
  });

  test('DT-01-6 state of one account never leaks into another (real prefs '
      'store)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PrefsModeStore();
    final env = ModeEnv(realStore: prefs, initialUid: 'A');
    await env.load();
    await env.notifier.selectMode(AppMode.body);
    await env.notifier.resolveChooser(AppMode.body);
    expect(env.state.chooserStatus, ChooserStatus.resolved);

    await env.signOut();
    await env.signIn('B');
    final b = await env.load();
    expect(b, ModeState.initial(), reason: 'B starts absent, no field of A');
    expect(await env.notifier.initIfAbsent(InitSource.onboarding),
        ModeSaveResult.saved);
    expect(env.state.chooserStatus, ChooserStatus.pending);

    await env.signOut();
    await env.signIn('A');
    final a = await env.load();
    expect(a.selectedMode, AppMode.body);
    expect(a.chooserStatus, ChooserStatus.resolved);
    final p = await SharedPreferences.getInstance();
    expect(p.getKeys(),
        {modeStorageKeyFor('A'), modeStorageKeyFor('B')});
    expect(p.getString(modeStorageKeyFor('B')), contains('"pending"'));
    expect(p.getString(modeStorageKeyFor('A')), isNot(contains('pending')));
  });

  test('DT-01-11 answers: three-state pattern, per mode, skipped survives a '
      'restart and a mode change', () async {
    final store = FakeModeStore();
    final env = ModeEnv(store: store, initialUid: 'u1');
    await env.load();
    expect(env.state.answerFor(AppMode.body), ModeAnswer.unanswered);
    await env.notifier.skipQuestion(AppMode.body);
    expect(env.state.answerFor(AppMode.body), ModeAnswer.skipped);
    await env.notifier.selectMode(AppMode.body);
    await env.notifier.answerQuestion(AppMode.body, ModeAnswer.answered('food'));
    expect(env.state.answerFor(AppMode.body).value, 'food');
    await env.notifier.selectMode(AppMode.train);
    expect(env.state.answerFor(AppMode.body).value, 'food',
        reason: 'a mode change keeps the answers');
    expect(env.state.answerFor(AppMode.train), ModeAnswer.unanswered,
        reason: 'an answer of one mode never lands on another');
    await env.notifier.skipQuestion(AppMode.body);
    expect(env.state.answerFor(AppMode.body), ModeAnswer.skipped);
    // A non-answered value through answerQuestion is a no-op.
    expect(await env.notifier.answerQuestion(AppMode.body, ModeAnswer.skipped),
        ModeSaveResult.unchanged);

    // App start never clears `skipped`.
    final env2 = ModeEnv(store: store, initialUid: 'u1');
    final s = await env2.load();
    expect(s.answerFor(AppMode.body), ModeAnswer.skipped);
    expect(store.writes.last.state.answerFor(AppMode.body), ModeAnswer.skipped);
  });

  test('DT-01-17 a newer-version value is read-only for the whole run',
      () async {
    final env = ModeEnv(initialUid: 'u1');
    env.fake.seedRaw('u1', '{"v":2,"mode":"body","chooser":"resolved"}');
    final raw = env.fake.stored['u1'];
    expect(raw, isA<ModeReadUnreadable>());
    await env.load();
    expect(await env.notifier.selectMode(AppMode.body),
        ModeSaveResult.saveFailed);
    expect(env.state.selectedMode, AppMode.body, reason: 'in memory');
    await env.notifier.answerQuestion(AppMode.body, ModeAnswer.answered('x'));
    expect(env.fake.writeCalls, 0);
    // Restart: the stored value is untouched.
    final env2 = ModeEnv(store: env.fake, initialUid: 'u1');
    await env2.load();
    expect(env.fake.stored['u1'], same(raw));
    expect(env.fake.writeCalls, 0);
  });

  test('DT-01-18 a corrupt value is replaced only by an explicit action',
      () async {
    final env = ModeEnv(initialUid: 'u1');
    env.fake.seedRaw('u1', 'not json at all');
    await env.load();
    expect(env.fake.writeCalls, 0, reason: 'start-up never replaces it');
    expect(await env.notifier.selectMode(AppMode.body), ModeSaveResult.saved);
    expect(env.fake.writes, hasLength(1));
    expect(env.fake.stored['u1'], isA<ModeReadValue>());
    await env.notifier.answerQuestion(AppMode.body, ModeAnswer.answered('x'));
    expect(env.fake.writes, hasLength(2));
  });

  test('DT-01-23 a stale notifier reference after an account switch writes '
      'nothing under A or B', () async {
    final env = ModeEnv(initialUid: 'A');
    await env.load();
    final stale = env.notifier;
    await env.signIn('B');
    final r = await stale.selectMode(AppMode.body);
    expect(r, ModeSaveResult.saveFailed);
    expect(env.fake.writeCalls, 0);
    expect(env.fake.stored.containsKey('A'), isFalse);
    expect(env.fake.stored.containsKey('B'), isFalse);
    final b = await env.load();
    expect(b, ModeState.initial(), reason: "B's own state after the rebuild");
  });

  testWidgets('DT-01-21 a mode choice does not rebuild the app root: the '
      'warm-up provider is not recomputed', (tester) async {
    final env = ModeEnv(initialUid: 'u1');
    var rootBuilds = 0;
    var watcherBuilds = 0;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: env.container,
      child: Column(children: [
        Consumer(builder: (context, ref, _) {
          // What FitnessApp.build does: watch the warm-up provider only.
          ref.watch(modeWarmUpProvider);
          rootBuilds++;
          return const SizedBox();
        }),
        Consumer(builder: (context, ref, _) {
          // Positive control: a widget that watches the state DOES rebuild.
          ref.watch(modeStateProvider);
          watcherBuilds++;
          return const SizedBox();
        }),
      ]),
    ));
    await tester.pumpAndSettle();
    final before = rootBuilds;
    final beforeWatcher = watcherBuilds;
    await env.notifier.selectMode(AppMode.body);
    await env.notifier.selectMode(AppMode.train);
    await env.notifier.selectMode(AppMode.body);
    await tester.pumpAndSettle();
    expect(rootBuilds, before, reason: 'the app root must not rebuild');
    expect(watcherBuilds, greaterThan(beforeWatcher),
        reason: 'control: the counter can see rebuilds');
  });

  test('RV selectedModeProvider is null while the state loads and after an '
      'account switch until the new state is read', () async {
    final env = ModeEnv(initialUid: 'A');
    env.fake.stored['A'] = ModeReadValue(ModeState(
        selectedMode: AppMode.body, chooserStatus: ChooserStatus.resolved));
    expect(env.container.read(selectedModeProvider), isNull,
        reason: 'loading: the lens must not be guessed');
    await env.load();
    expect(env.container.read(selectedModeProvider), AppMode.body);

    // Account switch: B's read is held; the previous value (body) is kept by
    // Riverpod during the reload and must NOT be exposed.
    final gate = Completer<void>();
    env.fake.readGate = gate;
    env.emitAuth('B');
    await pumpEventQueue();
    expect(env.container.read(selectedModeProvider), isNull,
        reason: "A's mode must not show for B while B's state loads");
    gate.complete();
    await env.load();
    expect(env.container.read(selectedModeProvider), AppMode.train,
        reason: "B's own (default) mode once read");
  });

  group('rollback: a stored mode that is unavailable in this build', () {
    ModeEnv rolledBack() {
      final env = ModeEnv(initialUid: 'u1'); // ride is off by default
      env.fake.stored['u1'] = ModeReadValue(ModeState(
          selectedMode: AppMode.ride, chooserStatus: ChooserStatus.migrated));
      return env;
    }

    test('in memory it is train; markResolved keeps the raw mode on disk',
        () async {
      final env = rolledBack();
      final s = await env.load();
      expect(s.selectedMode, AppMode.train);
      expect(await env.notifier.markResolved(), ModeSaveResult.saved);
      final w = env.fake.writes.last.state;
      expect(w.chooserStatus, ChooserStatus.resolved);
      expect(w.selectedMode, AppMode.ride,
          reason: 'a rollback must not destroy the stored choice');
      expect(env.state.selectedMode, AppMode.train);
    });

    test('an answer write keeps the raw mode on disk', () async {
      final env = rolledBack();
      await env.load();
      expect(await env.notifier.answerQuestion(
              AppMode.body, ModeAnswer.answered('food')),
          ModeSaveResult.saved);
      final w = env.fake.writes.last.state;
      expect(w.selectedMode, AppMode.ride);
      expect(w.answerFor(AppMode.body).value, 'food');
    });

    test('an explicit selectMode of another mode overwrites it, and later '
        'writes keep the new choice', () async {
      final env = rolledBack();
      await env.load();
      expect(await env.notifier.selectMode(AppMode.body), ModeSaveResult.saved);
      expect(env.fake.writes.last.state.selectedMode, AppMode.body);
      await env.notifier.skipQuestion(AppMode.body);
      expect(env.fake.writes.last.state.selectedMode, AppMode.body,
          reason: 'the raw value must be forgotten after an explicit choice');
    });

    test('selectMode(train) on the coerced train persists train, sends no '
        'event, and a repeat is unchanged', () async {
      final env = rolledBack();
      await env.load();
      env.recordEvents();
      expect(env.state.selectedMode, AppMode.train);
      final r = await env.notifier.selectMode(AppMode.train);
      expect(r, ModeSaveResult.saved);
      expect(env.fake.writes, hasLength(1));
      expect(env.fake.stateOf('u1')!.selectedMode, AppMode.train,
          reason: 'the store must hold train, not the rolled-back ride');
      expect(env.events, isEmpty, reason: 'the shown mode did not change');
      final writesBefore = env.fake.writeCalls;
      expect(await env.notifier.selectMode(AppMode.train),
          ModeSaveResult.unchanged);
      expect(env.fake.writeCalls, writesBefore, reason: 'no second write');
      // Later writes keep train.
      await env.notifier.skipQuestion(AppMode.body);
      expect(env.fake.writes.last.state.selectedMode, AppMode.train);
    });

    test('an explicit chooser choice of train replaces the raw mode',
        () async {
      final env = rolledBack();
      await env.load();
      expect(await env.notifier.resolveChooser(AppMode.train),
          ModeSaveResult.saved);
      expect(env.fake.writes.last.state.selectedMode, AppMode.train);
    });
  });

  group('DT-01-26 store writes are serialised in call order (MAJOR-02)', () {
    test('write #2 reaches the store only after write #1 completes, even when '
        'its gate is released first; the last accepted mutation is stored',
        () async {
      final store = GatedModeStore();
      final env = ModeEnv(store: store, initialUid: 'u1');
      await env.load();
      final f1 = env.notifier.selectMode(AppMode.body);
      final f2 = env.notifier.answerQuestion(
          AppMode.body, ModeAnswer.answered('food'));
      var done2 = false;
      // ignore: unawaited_futures
      f2.then((_) => done2 = true);
      await pumpEventQueue();
      expect(store.started, hasLength(1),
          reason: 'write #2 must wait for write #1');
      // Release the SECOND gate first (out of order completion).
      store.gate(1).complete();
      await pumpEventQueue();
      expect(store.started, hasLength(1),
          reason: 'write #2 must not start while write #1 is pending');
      expect(done2, isFalse);
      expect(store.writes, isEmpty);
      store.gate(0).complete();
      expect(await f1, ModeSaveResult.saved);
      expect(await f2, ModeSaveResult.saved);
      expect(store.started, hasLength(2));
      expect(store.started[0].state.selectedMode, AppMode.body);
      expect(store.started[0].state.answerFor(AppMode.body),
          ModeAnswer.unanswered);
      expect(store.started[1].state.answerFor(AppMode.body).value, 'food');
      expect(store.writes.map((w) => w.state.answerFor(AppMode.body).value),
          [null, 'food'],
          reason: 'completion order equals call order');
      final persisted = store.stateOf('u1')!;
      expect(persisted.selectedMode, AppMode.body);
      expect(persisted.answerFor(AppMode.body).value, 'food',
          reason: 'the latest accepted write is persisted last');

      // A rebuilt container reads the same final value from the store.
      final env2 = ModeEnv(store: store, initialUid: 'u1');
      final s = await env2.load();
      expect(s.selectedMode, AppMode.body);
      expect(s.answerFor(AppMode.body).value, 'food');
    });

    test('two selectMode calls in a row: the last mode wins on disk even '
        'when the second gate is released first', () async {
      final store = GatedModeStore();
      final env = ModeEnv(
          store: store,
          initialUid: 'u1',
          flags: const ModeFlags(rideEnabled: true));
      await env.load();
      final f1 = env.notifier.selectMode(AppMode.body);
      final f2 = env.notifier.selectMode(AppMode.ride);
      await pumpEventQueue();
      store.gate(1).complete();
      await pumpEventQueue();
      expect(store.started, hasLength(1));
      store.gate(0).complete();
      expect(await f1, ModeSaveResult.saved);
      expect(await f2, ModeSaveResult.saved);
      expect(store.writes.map((w) => w.state.selectedMode),
          [AppMode.body, AppMode.ride]);
      expect(store.stateOf('u1')!.selectedMode, AppMode.ride);
      expect(env.state.selectedMode, AppMode.ride);
      final env2 = ModeEnv(
          store: store,
          initialUid: 'u1',
          flags: const ModeFlags(rideEnabled: true));
      expect((await env2.load()).selectedMode, AppMode.ride);
    });

    test('a failing first write (failed result) does not block the second; '
        'each call has its own result', () async {
      final store = GatedModeStore()..outcomes[0] = WriteOutcome.fail;
      final env = ModeEnv(store: store, initialUid: 'u1');
      await env.load();
      final f1 = env.notifier.selectMode(AppMode.body);
      final f2 = env.notifier.skipQuestion(AppMode.body);
      store.gate(0).complete();
      store.gate(1).complete();
      expect(await f1, ModeSaveResult.saveFailed);
      expect(await f2, ModeSaveResult.saved);
      expect(store.started, hasLength(2));
      expect(store.writes, hasLength(1), reason: 'only write #2 took effect');
      final persisted = store.stateOf('u1')!;
      expect(persisted.selectedMode, AppMode.body,
          reason: 'the second payload carries the first in-memory change');
      expect(persisted.answerFor(AppMode.body), ModeAnswer.skipped);
      // The newest result (saved) cleared the retry flag.
      expect(await env.notifier.selectMode(AppMode.body),
          ModeSaveResult.unchanged);
    });

    test('a throwing first write does not block the second', () async {
      final store = GatedModeStore()..outcomes[0] = WriteOutcome.throwError;
      final env = ModeEnv(store: store, initialUid: 'u1');
      await env.load();
      final f1 = env.notifier.selectMode(AppMode.body);
      final f2 = env.notifier.skipQuestion(AppMode.body);
      store.gate(0).complete();
      store.gate(1).complete();
      expect(await f1, ModeSaveResult.saveFailed);
      expect(await f2, ModeSaveResult.saved);
      expect(store.stateOf('u1')!.answerFor(AppMode.body), ModeAnswer.skipped);
    });

    test('retry on the next call is unchanged: a failed last write makes an '
        'identical call persist again', () async {
      final store = GatedModeStore()
        ..outcomes[0] = WriteOutcome.fail
        ..outcomes[1] = WriteOutcome.fail;
      final env = ModeEnv(store: store, initialUid: 'u1');
      await env.load();
      final f1 = env.notifier.selectMode(AppMode.body);
      final f2 = env.notifier.skipQuestion(AppMode.body);
      store.gate(0).complete();
      store.gate(1).complete();
      expect(await f1, ModeSaveResult.saveFailed);
      expect(await f2, ModeSaveResult.saveFailed);
      expect(store.writes, isEmpty);
      // Identical mode, but the last save failed: it is a retry, not unchanged.
      final f3 = env.notifier.selectMode(AppMode.body);
      store.gate(2).complete();
      expect(await f3, ModeSaveResult.saved);
      final persisted = store.stateOf('u1')!;
      expect(persisted.selectedMode, AppMode.body);
      expect(persisted.answerFor(AppMode.body), ModeAnswer.skipped);
      expect(await env.notifier.selectMode(AppMode.body),
          ModeSaveResult.unchanged);
    });

    test('an account switch while a write is queued never writes the old '
        "account's state into the new account's key", () async {
      final store = GatedModeStore();
      final env = ModeEnv(store: store, initialUid: 'A');
      await env.load();
      final stale = env.notifier;
      final f1 = stale.selectMode(AppMode.body);
      final f2 = stale.answerQuestion(AppMode.body, ModeAnswer.answered('x'));
      await pumpEventQueue();
      expect(store.started, hasLength(1));
      await env.signIn('B'); // rebuild while write #1 is in flight, #2 queued
      final b = await env.load();
      expect(b, ModeState.initial(), reason: "B starts with its own state");
      // B's own write is queued behind A's two writes.
      final fb = env.notifier.selectMode(AppMode.body);
      store.gate(2).complete();
      store.gate(1).complete();
      await pumpEventQueue();
      expect(store.started, hasLength(1),
          reason: 'still waiting for A write #1');
      store.gate(0).complete();
      await f1;
      await f2;
      expect(await fb, ModeSaveResult.saved);
      expect(store.started.map((w) => w.uid), ['A', 'A', 'B'],
          reason: 'call order is kept across the switch');
      final a = store.stateOf('A')!;
      expect(a.answerFor(AppMode.body).value, 'x');
      final bs = store.stateOf('B')!;
      expect(bs.selectedMode, AppMode.body);
      expect(bs.answerFor(AppMode.body), ModeAnswer.unanswered,
          reason: "A's answer never lands under B");
    });

    test('a queued write for an old account that is only switched away from '
        'is never written to B when B has no mutation', () async {
      final store = GatedModeStore();
      final env = ModeEnv(store: store, initialUid: 'A');
      await env.load();
      final f1 = env.notifier.selectMode(AppMode.body);
      final f2 = env.notifier.skipQuestion(AppMode.body);
      await pumpEventQueue();
      await env.signIn('B');
      await env.load();
      store.gate(0).complete();
      store.gate(1).complete();
      await f1;
      await f2;
      expect(store.started.map((w) => w.uid), ['A', 'A']);
      expect(store.stored.containsKey('B'), isFalse);
      expect(store.writes.every((w) => w.uid == 'A'), isTrue);
    });

    test('a uid marked deleted while writes are queued is still refused by '
        'the store', () async {
      final store = GatedModeStore();
      final env = ModeEnv(store: store, initialUid: 'A');
      await env.load();
      final f1 = env.notifier.selectMode(AppMode.body);
      final f2 = env.notifier.skipQuestion(AppMode.body);
      await pumpEventQueue();
      store.markUidWiped('A'); // account deletion starts
      store.gate(0).complete();
      store.gate(1).complete();
      expect(await f1, ModeSaveResult.saveFailed);
      expect(await f2, ModeSaveResult.saveFailed);
      expect(store.writes, isEmpty);
      expect(store.stored.containsKey('A'), isFalse,
          reason: 'nothing recreated the deleted key');
      // New calls for the deleted uid are refused before the store.
      final before = store.started.length;
      expect(await env.notifier.selectMode(AppMode.train),
          ModeSaveResult.saveFailed);
      expect(store.started.length, before);
    });

    test('rollback: queued writes keep the raw stored mode, and an explicit '
        'selection after them replaces it only for later writes', () async {
      final store = GatedModeStore();
      final env = ModeEnv(store: store, initialUid: 'u1');
      store.stored['u1'] = ModeReadValue(ModeState(
          selectedMode: AppMode.ride, chooserStatus: ChooserStatus.migrated));
      await env.load();
      final f1 = env.notifier.markResolved();
      final f2 = env.notifier
          .answerQuestion(AppMode.body, ModeAnswer.answered('food'));
      final f3 = env.notifier.selectMode(AppMode.body);
      await pumpEventQueue();
      store.gate(2).complete();
      store.gate(1).complete();
      await pumpEventQueue();
      expect(store.started, hasLength(1));
      store.gate(0).complete();
      expect(await f1, ModeSaveResult.saved);
      expect(await f2, ModeSaveResult.saved);
      expect(await f3, ModeSaveResult.saved);
      expect(store.writes.map((w) => w.state.selectedMode),
          [AppMode.ride, AppMode.ride, AppMode.body],
          reason: 'raw ride survives queued writes; body is written last');
      expect(store.writes[0].state.chooserStatus, ChooserStatus.resolved);
      expect(store.writes[1].state.answerFor(AppMode.body).value, 'food');
      expect(store.stateOf('u1')!.selectedMode, AppMode.body);
    });
  });

  group('DT-01-25 storage K scan', () {
    List<File> files() => [
          for (final e in Directory('lib/features/modes')
              .listSync(recursive: true))
            if (e is File && e.path.endsWith('.dart')) e
        ];

    final forbidden = RegExp(
        r"SharedPreferences|flutter_secure_storage|dart:io|AppSettings|settingsRepositoryProvider|File\(");

    test('the scanner finds a planted token (it can fail)', () {
      expect(forbidden.hasMatch('final p = SharedPreferences.getInstance();'),
          isTrue);
      expect(forbidden.hasMatch('final x = 1;'), isFalse);
    });

    test('only PrefsModeStore touches storage; the scan set is not empty', () {
      final fs = files();
      final names = fs.map((f) => f.path.replaceAll('\\', '/')).toList();
      expect(fs.length, greaterThanOrEqualTo(10));
      expect(names.any((n) => n.endsWith('data/mode_store.dart')), isTrue);
      expect(names.any((n) => n.endsWith('pages/mode_chooser_page.dart')),
          isTrue);
      final offenders = <String>[];
      for (final f in fs) {
        final n = f.path.replaceAll('\\', '/');
        if (n.endsWith('data/mode_store.dart')) continue;
        final code = f
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        if (forbidden.hasMatch(code)) offenders.add(n);
      }
      expect(offenders, isEmpty,
          reason: 'storage outside PrefsModeStore: $offenders');
    });
  });
}

enum WriteOutcome { ok, fail, throwError }

/// A store whose write number N completes only when the test completes
/// `gate(N)`. `started` records every write that REACHED the store, in order.
class GatedModeStore extends FakeModeStore {
  final List<WriteRec> started = [];
  final Map<int, Completer<void>> _gates = {};
  final Map<int, WriteOutcome> outcomes = {};

  Completer<void> gate(int i) => _gates.putIfAbsent(i, Completer<void>.new);

  @override
  Future<ModeWriteResult> write(String uid, ModeState state) async {
    final i = started.length;
    started.add(WriteRec(i, uid, state));
    await gate(i).future;
    switch (outcomes[i] ?? WriteOutcome.ok) {
      case WriteOutcome.throwError:
        throw StateError('gated write threw');
      case WriteOutcome.fail:
        return ModeWriteResult.failed;
      case WriteOutcome.ok:
        return super.write(uid, state);
    }
  }
}
