// S03-01 start-up migration (AC-CH-8a, 8b, DT-01-10, 12, 13, 14, 16, 22):
// decided once per uid from the FIRST profile value loaded in the process.
// Provider-level seam: the app root watches `modeWarmUpProvider`, which starts
// `modeMigrationProvider`. Oracle: S03_TEST_PLAN.md 2.2, S03_DESIGN 2.2 (RV-1).
import 'dart:async';

import 'package:fitness_app/features/modes/data/mode_models.dart';
import 'package:fitness_app/features/modes/state/mode_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/mode_fakes.dart';

void main() {
  late List<String> logs;
  late void Function(String? message, {int? wrapWidth}) savedDebugPrint;

  setUp(() {
    logs = [];
    savedDebugPrint = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
  });
  tearDown(() => debugPrint = savedDebugPrint);

  test('AC-CH-8a an onboarded Phase 1 user with an absent field is migrated '
      'before any Home frame (store holds migrated + train)', () async {
    final env = ModeEnv(initialUid: 'u1');
    env.warmUp();
    env.profiles.emitOnboarded('u1');
    await env.load();
    await pumpEventQueue();
    final s = env.fake.stateOf('u1');
    expect(s, isNotNull, reason: 'a migration write must have happened');
    expect(s!.chooserStatus, ChooserStatus.migrated);
    expect(s.selectedMode, AppMode.train);
    expect(env.fake.writes, hasLength(1));
    expect(env.state.chooserStatus, ChooserStatus.migrated,
        reason: 'in-memory state agrees, so Home never offers the chooser');
  });

  test('AC-CH-8b a NOT onboarded user is never migrated', () async {
    final env = ModeEnv(initialUid: 'u1');
    env.warmUp();
    env.profiles.emitNotOnboarded('u1');
    await env.load();
    await pumpEventQueue();
    expect(env.state.chooserStatus, ChooserStatus.absent);
    expect(env.fake.writeCalls, 0);
    // No profile at all behaves the same.
    final env2 = ModeEnv(initialUid: 'u2');
    env2.warmUp();
    env2.profiles.emit('u2', null);
    await env2.load();
    await pumpEventQueue();
    expect(env2.state.chooserStatus, ChooserStatus.absent);
    expect(env2.fake.writeCalls, 0);
  });

  test('DT-01-10 migration is idempotent: migrated, resolved and pending '
      'survive a second start; absent becomes migrated once', () async {
    for (final status in [
      ChooserStatus.migrated,
      ChooserStatus.resolved,
      ChooserStatus.pending
    ]) {
      final store = FakeModeStore();
      store.stored['u1'] = ModeReadValue(
          ModeState(selectedMode: AppMode.body, chooserStatus: status));
      for (var run = 0; run < 2; run++) {
        final env = ModeEnv(store: store, initialUid: 'u1');
        env.warmUp();
        env.profiles.emitOnboarded('u1');
        await env.load();
        await pumpEventQueue();
        expect(env.state.chooserStatus, status, reason: '${status.name} run $run');
      }
      expect(store.writeCalls, 0, reason: status.name);
    }
    final store = FakeModeStore();
    for (var run = 0; run < 2; run++) {
      final env = ModeEnv(store: store, initialUid: 'u1');
      env.warmUp();
      env.profiles.emitOnboarded('u1');
      await env.load();
      await pumpEventQueue();
      expect(env.state.chooserStatus, ChooserStatus.migrated);
    }
    expect(store.writes, hasLength(1), reason: 'absent becomes migrated once');
  });

  test('DT-01-13 a first loaded profile that is already onboarded gives '
      'migrated with one write', () async {
    final env = ModeEnv(initialUid: 'u1');
    env.profiles.emitOnboarded('u1'); // present BEFORE the first listener
    env.warmUp();
    await env.load();
    await pumpEventQueue();
    expect(env.fake.writes, hasLength(1));
    expect(env.state.chooserStatus, ChooserStatus.migrated);
  });

  test('DT-01-14 a mid-session flip to onboarded is NOT migrated (the '
      'onboarding hook owns that transition)', () async {
    final env = ModeEnv(initialUid: 'u1');
    env.warmUp();
    env.profiles.emitNotOnboarded('u1');
    await env.load();
    await pumpEventQueue();
    env.profiles.emitOnboarded('u1');
    await pumpEventQueue();
    expect(env.fake.writeCalls, 0);
    expect(env.state.chooserStatus, ChooserStatus.absent);
  });

  for (final order in ['migrationFirst', 'hookFirst']) {
    test('DT-01-12 /$order: a profile that flips to onboarded during the '
        'onboarding submit ends as pending with exactly one write', () async {
      final env = ModeEnv(initialUid: 'u1');
      env.warmUp();
      env.profiles.emitNotOnboarded('u1');
      await env.load();
      if (order == 'migrationFirst') {
        // The migration event (profile flip) is delivered first, then the hook.
        env.profiles.emitOnboarded('u1');
        await pumpEventQueue();
        await env.notifier.initIfAbsent(InitSource.onboarding);
      } else {
        // The hook runs before the flip event reaches the migration.
        final hook = env.notifier.initIfAbsent(InitSource.onboarding);
        env.profiles.emitOnboarded('u1');
        await hook;
        await pumpEventQueue();
      }
      expect(env.fake.writes, hasLength(1));
      expect(env.state.chooserStatus, ChooserStatus.pending);
      expect(env.fake.stateOf('u1')!.chooserStatus, ChooserStatus.pending);
    });
  }

  test('DT-01-12 two concurrent initIfAbsent calls: the first wins, the '
      'second sees the status set, one write', () async {
    final env = ModeEnv(initialUid: 'u1');
    await env.load();
    final gate = Completer<void>();
    env.fake.writeGate = gate;
    final first = env.notifier.initIfAbsent(InitSource.onboarding);
    final second = env.notifier.initIfAbsent(InitSource.migration);
    expect(await second, ModeSaveResult.unchanged);
    gate.complete();
    expect(await first, ModeSaveResult.saved);
    expect(env.fake.writes, hasLength(1));
    expect(env.state.chooserStatus, ChooserStatus.pending);
  });

  for (final entry in {
    '/corrupt': 'definitely not json',
    '/v2': '{"v":2,"mode":"body","chooser":"pending"}',
  }.entries) {
    for (final profile in ['missing', 'onboarded']) {
      test('DT-01-16 ${entry.key} with a $profile profile: zero writes, no '
          'chooser, content-free log', () async {
        final env = ModeEnv(initialUid: 'u1');
        env.fake.seedRaw('u1', entry.value);
        env.warmUp();
        if (profile == 'onboarded') {
          env.profiles.emitOnboarded('u1');
        } else {
          env.profiles.emit('u1', null);
        }
        await env.load();
        await pumpEventQueue();
        expect(env.fake.writeCalls, 0);
        expect(env.state.chooserStatus, ChooserStatus.absent);
        expect(logs.any((l) => l.startsWith('mode state: unreadable')), isTrue,
            reason: 'a reason code is logged: $logs');
        for (final l in logs) {
          expect(l.contains('definitely'), isFalse);
          expect(l.contains('u1'), isFalse, reason: 'no uid in the log: $l');
        }
      });
    }
  }

  test('DT-01-22 /neverLoads: the migration does not decide without a '
      'profile', () async {
    final env = ModeEnv(initialUid: 'u1');
    env.warmUp();
    await env.load();
    await pumpEventQueue();
    expect(env.state.chooserStatus, ChooserStatus.absent);
    expect(env.fake.writeCalls, 0);
  });

  test('DT-01-22 /arrivesLate: when the first (onboarded) profile arrives the '
      'migration writes migrated once', () async {
    final env = ModeEnv(initialUid: 'u1');
    env.warmUp();
    await env.load();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(env.fake.writeCalls, 0, reason: 'nothing before the profile');
    env.profiles.emitOnboarded('u1');
    await pumpEventQueue();
    expect(env.fake.writes, hasLength(1));
    expect(env.state.chooserStatus, ChooserStatus.migrated);
  });
}
