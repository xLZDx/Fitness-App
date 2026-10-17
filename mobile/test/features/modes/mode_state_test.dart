// S03-01 (EP-1) mode state: load, coercion, availability gate, events, account
// scoping, read-only runs after unreadable values, stale-reference safety, the
// storage K scan. Oracle: S03_TEST_PLAN.md section 2.2 and S03_DESIGN 2.2 / 5.
import 'dart:io';

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
