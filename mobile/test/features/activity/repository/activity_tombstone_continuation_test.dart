// S02 test epic 11b: remediation E2 (MAJOR-03), bulk local deletions must reach
// the cloud promptly and be observable. Oracles: docs/phase2/s02/
// S02_REMEDIATION_E_TEST_NOTES.md heading E2, S02_DESIGN.md section 17 item 21
// and sections 5.4 / 6.2, and the MAJOR-03 text of the gate report, NOT the
// code under test.
//
// Real `FileActivityJournal` (in-memory file system of the journal harness) with
// a counting subclass, a fake backend, a fake pusher and a fake timer factory.
// A "round" is a run of pusher calls with no journal tombstone listing in
// between (the repository lists the owed tombstones once per round).
import 'dart:async';

import 'package:fitness_app/core/config/activity_flags.dart';
import 'package:fitness_app/core/wiring/activity_wiring.dart';
import 'package:fitness_app/features/activity/repository/activity_cloud_settings_client.dart';
import 'package:fitness_app/features/activity/repository/activity_summary_backend.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/file_activity_journal.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:fitness_app/features/activity/state/sync_conflict_presenter.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';
import '../../../support/two_device_world.dart';

/// A failure carrying a `code` like `FirebaseFunctionsException`.
class _CodeError implements Exception {
  _CodeError(this.code);
  final String code;
}

class _FakeTimer implements Timer {
  _FakeTimer(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  bool cancelled = false;
  bool fired = false;

  @override
  bool get isActive => !cancelled && !fired;

  @override
  int get tick => 0;

  @override
  void cancel() => cancelled = true;

  void fire() {
    fired = true;
    _callback();
  }
}

class _Timers {
  final List<_FakeTimer> list = [];

  /// Timers created while another one was still active.
  int overlaps = 0;

  Timer create(Duration delay, void Function() cb) {
    if (list.any((t) => t.isActive)) overlaps++;
    final t = _FakeTimer(delay, cb);
    list.add(t);
    return t;
  }

  List<_FakeTimer> get active => [for (final t in list) if (t.isActive) t];
}

class _CountingJournal extends FileActivityJournal {
  _CountingJournal({
    required super.rootPath,
    required super.fileSystem,
    required super.keyProvider,
    required super.clock,
    required this.events,
  });

  final List<String> events;

  @override
  Future<List<JournalEntry>> listTombstones() {
    events.add('L');
    return super.listTombstones();
  }
}

class _Backend implements ActivitySummaryBackend {
  final Set<String> tombstones = {};
  bool listOffline = false;
  int lists = 0;

  @override
  Future<Set<String>> listTombstoneIds() async {
    lists++;
    if (listOffline) throw const SummaryBackendUnavailable('offline');
    return {...tombstones};
  }

  @override
  Future<bool> tombstoneExists(String id) async => tombstones.contains(id);

  @override
  Future<Map<String, Object?>?> readSummary(String id) async => null;

  @override
  Future<void> writeSummary(String id, Map<String, Object> summary,
      {required bool create}) async {}
}

class _Rig {
  final h = JournalHarness.memory();
  final events = <String>[];
  final timers = _Timers();
  final backend = _Backend();

  /// Every pusher call (including failing ones), in order.
  final calls = <String>[];

  /// Ids the fake server accepted (also listed by `listTombstoneIds`).
  final okIds = <String>[];

  /// Decides a failure for call number `n` (1-based, per rig) of `id`.
  Object? Function(String id, int n)? failure;

  /// Awaited inside the pusher before it decides (in-flight tests).
  Future<void> Function(String id)? beforePush;

  late _CountingJournal journal;
  late ActivitySyncRepository repo;

  Future<void> open() async {
    await h.open();
    await h.journal.close();
    await _startJournal();
    repo = newRepo();
  }

  Future<void> _startJournal() async {
    journal = _CountingJournal(
      rootPath: h.root,
      fileSystem: h.fs,
      keyProvider: h.keys,
      clock: h.clock.call,
      events: events,
    );
    await journal.start();
  }

  Future<void> push(String id) async {
    events.add('P');
    calls.add(id);
    await beforePush?.call(id);
    final err = failure?.call(id, calls.length);
    if (err != null) throw err;
    okIds.add(id);
    backend.tombstones.add(id);
  }

  ActivitySyncRepository newRepo({bool withPusher = true}) =>
      ActivitySyncRepository(
        journal: journal,
        backend: backend,
        tombstonePusher: withPusher ? push : null,
        clock: h.clock.call,
        retryTimerFactory: timers.create,
      );

  /// A restart: new journal instance and new repository over the same files.
  Future<void> restart() async {
    await repo.dispose();
    await journal.close();
    await _startJournal();
    repo = newRepo();
  }

  Future<void> deleteMany(int n, {int from = 1}) async {
    for (var i = from; i < from + n; i++) {
      await journal.delete(idFor(i));
    }
  }

  /// Sizes of the pusher call runs between tombstone listings = rounds.
  List<int> rounds() {
    final out = <int>[];
    String? prev;
    for (final e in events) {
      if (e == 'P') {
        if (prev == 'P') {
          out[out.length - 1]++;
        } else {
          out.add(1);
        }
      }
      prev = e;
    }
    return out;
  }

  Future<int> pending() async => (await repo.refreshState()).pendingTombstones;

  Future<void> dispose() async {
    await repo.dispose();
    try {
      await journal.close();
    } catch (_) {}
    await h.dispose();
  }
}

/// Lets queued work run; never a fixed sleep.
Future<void> until(bool Function() done, [String why = '']) async {
  for (var i = 0; i < 50000 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: 'condition not reached $why');
}

const _slow = Timeout(Duration(minutes: 5));

class _Settings extends Fake implements ActivityCloudSettingsClient {
  @override
  Future<void> load() async {}
}

class _Consent extends AccountScopedConsentStore {
  @override
  Future<void> signIn(String uid) async {}
}

AuthUser _user(String uid) =>
    AuthUser(uid: uid, displayName: uid, provider: AuthProvider.google);

void main() {
  late _Rig r;
  setUp(() async {
    r = _Rig();
    await r.open();
  });
  tearDown(() async => r.dispose());

  group('backlog completes inside one syncAll call', () {
    for (final c in const [(9, 2), (30, 4), (100, 13), (1000, 125)]) {
      test('${c.$1} offline deletions: ${c.$2} rounds, every id pushed once, '
          'pending 0, no retry timer', () async {
        await r.deleteMany(c.$1);
        expect(await r.pending(), c.$1, reason: 'owed before the pass');
        r.events.clear();
        await r.repo.syncAll();
        expect(r.calls, hasLength(c.$1));
        expect(r.calls.toSet(), hasLength(c.$1), reason: 'each id exactly once');
        expect(r.calls.toSet(), {for (var i = 1; i <= c.$1; i++) idFor(i)});
        final rounds = r.rounds();
        expect(rounds, hasLength(c.$2));
        expect(rounds.take(rounds.length - 1), everyElement(8));
        expect(rounds.last, c.$1 - 8 * (c.$2 - 1));
        expect(await r.pending(), 0);
        expect(r.timers.list, isEmpty, reason: 'nothing left, no timer');
        expect(r.repo.lastTombstonePushError, isNull);
        expect(r.backend.tombstones, hasLength(c.$1));
      }, timeout: _slow);
    }

    test('exactly 8 is one round; exactly 1024 is 128 rounds, pending 0 and '
        'no timer (the cap is not hit)', () async {
      await r.deleteMany(8);
      await r.repo.syncAll();
      expect(r.rounds(), [8]);
      expect(r.timers.list, isEmpty);

      final r2 = _Rig();
      await r2.open();
      addTearDown(r2.dispose);
      await r2.deleteMany(1024);
      await r2.repo.syncAll();
      expect(r2.calls, hasLength(1024));
      expect(r2.rounds(), hasLength(128));
      expect(await r2.pending(), 0);
      expect(r2.timers.list, isEmpty);
    }, timeout: _slow);

    test('a second syncAll after completion pushes nothing (quota stays '
        'untouched by repeated passes)', () async {
      await r.deleteMany(30);
      await r.repo.syncAll();
      final n = r.calls.length;
      await r.repo.syncAll();
      await r.repo.syncAll();
      expect(r.calls, hasLength(n));
    });
  });

  group('1100 deletions: the per-call cap, then the timer', () {
    test('first call pushes exactly 1024, 76 stay pending, ONE timer of 60 s; '
        'firing it pushes the remaining 76', () async {
      await r.deleteMany(1100);
      await r.repo.syncAll();
      expect(r.calls, hasLength(1024));
      expect(r.calls.toSet(), hasLength(1024));
      expect(r.rounds(), hasLength(128));
      expect(await r.pending(), 76);
      expect(r.timers.list, hasLength(1));
      expect(r.timers.list.single.delay, const Duration(seconds: 60));
      expect(r.timers.list.single.isActive, isTrue);
      expect(r.repo.lastTombstonePushError, isNull,
          reason: 'the cap is not a failure');

      r.events.clear();
      r.timers.list.single.fire();
      await until(() => r.calls.length == 1100, 'remaining 76 pushed');
      await r.repo.syncAll(); // serialised behind the timer pass
      expect(r.calls.toSet(), {for (var i = 1; i <= 1100; i++) idFor(i)});
      expect(r.calls, hasLength(1100), reason: 'no id pushed twice');
      expect(r.rounds(), [8, 8, 8, 8, 8, 8, 8, 8, 8, 4]);
      expect(await r.pending(), 0);
      expect(r.timers.list, hasLength(1), reason: 'no further timer');
    }, timeout: _slow);
  });

  group('restart resumes only the unconfirmed ids', () {
    test('a new repository over the same journal pushes only what the server '
        'does not list', () async {
      await r.deleteMany(20);
      r.failure = (id, n) => n > 12 ? _CodeError('unavailable') : null;
      await r.repo.syncAll();
      expect(r.okIds, hasLength(12));
      expect(await r.pending(), 8);
      final listed = {...r.backend.tombstones};
      expect(listed, hasLength(12));

      await r.restart();
      expect(r.timers.list.first.cancelled, isTrue,
          reason: 'dispose of the old repository cancels its timer');
      r.failure = null;
      r.calls.clear();
      await r.repo.syncAll();
      expect(r.calls, hasLength(8));
      expect(r.calls.toSet().intersection(listed), isEmpty,
          reason: 'ids the server lists are never pushed again');
      expect(r.calls.toSet().union(listed), {for (var i = 1; i <= 20; i++) idFor(i)});
      expect(await r.pending(), 0);
    });

    test('a fresh process whose pass is all confirmed pushes nothing', () async {
      await r.deleteMany(12);
      await r.repo.syncAll();
      await r.restart();
      r.calls.clear();
      await r.repo.syncAll();
      expect(r.calls, isEmpty);
      expect(await r.pending(), 0);
    });
  });

  group('quota and systemic refusals end the pass at once', () {
    test('resource-exhausted on call 11 (a continuation round): no further '
        'push in that pass, error exposed, 15 min timer, tombstones stay',
        () async {
      await r.deleteMany(30);
      r.failure =
          (id, n) => n == 11 ? _CodeError('resource-exhausted') : null;
      await r.repo.syncAll();
      expect(r.calls, hasLength(11), reason: 'no hot loop after the refusal');
      expect(r.repo.lastTombstonePushError, 'resource-exhausted');
      expect((await r.repo.refreshState()).lastTombstonePushError,
          'resource-exhausted');
      expect(r.timers.list, hasLength(1));
      expect(r.timers.list.single.delay, const Duration(minutes: 15));
      expect(await r.pending(), 30 - 10);
      expect(await r.journal.listTombstones(), hasLength(30),
          reason: 'local tombstones stay');
    });

    test('resource-exhausted on call 3 of the FIRST round also stops the '
        'batch (the other 5 ids of the round are not tried)', () async {
      await r.deleteMany(30);
      r.failure =
          (id, n) => n == 3 ? _CodeError('resource-exhausted') : null;
      await r.repo.syncAll();
      expect(r.calls, hasLength(3));
      expect(r.timers.list.single.delay, const Duration(minutes: 15));
    });

    test('still exhausted when the timer fires: exactly one more attempt per '
        'firing, again 15 min', () async {
      await r.deleteMany(30);
      r.failure = (id, n) => _CodeError('resource-exhausted');
      await r.repo.syncAll();
      expect(r.calls, hasLength(1));
      r.timers.list.last.fire();
      await until(() => r.timers.list.length == 2, 'second timer');
      expect(r.calls, hasLength(2));
      expect(r.timers.list.last.delay, const Duration(minutes: 15));
      expect(r.timers.overlaps, 0);
    });

    for (final code in const [
      'unavailable',
      'permission-denied',
      'unauthenticated',
      'deadline-exceeded'
    ]) {
      test('$code on call 2 stops the round at once; timer is the first '
          'backoff step (60 s)', () async {
        await r.deleteMany(30);
        r.failure = (id, n) => n == 2 ? _CodeError(code) : null;
        await r.repo.syncAll();
        expect(r.calls, hasLength(2));
        expect(r.repo.lastTombstonePushError, code);
        expect(r.timers.list.single.delay, const Duration(seconds: 60));
        expect(await r.pending(), 29);
      });
    }
  });

  group('partial failures', () {
    test('round 1: a non-systemic failure on one id does not stop the other '
        'ids of the batch but starts no continuation round', () async {
      await r.deleteMany(30);
      r.failure = (id, n) => n == 3 ? _CodeError('internal') : null;
      await r.repo.syncAll();
      expect(r.calls, hasLength(8), reason: 'whole batch tried, nothing more');
      expect(r.rounds(), [8]);
      expect(r.okIds, hasLength(7));
      expect(await r.pending(), 23);
      expect(r.repo.lastTombstonePushError, 'internal');
      expect(r.timers.list.single.delay, const Duration(seconds: 60));
    });

    test('a failure inside a continuation round stops the pass at once',
        () async {
      await r.deleteMany(30);
      r.failure = (id, n) => n == 12 ? _CodeError('internal') : null;
      await r.repo.syncAll();
      expect(r.calls, hasLength(12), reason: 'ids 13..16 of round 2 not tried');
      expect(r.rounds(), [8, 4]);
      expect(await r.pending(), 30 - 11);
      expect(r.timers.list, hasLength(1));
    });

    test('an id that failed earlier is tried LAST: one bad id never starves '
        'the rest', () async {
      await r.deleteMany(100);
      String? bad;
      r.failure = (id, n) {
        bad ??= id; // the very first id of the first pass is poisoned
        return id == bad ? _CodeError('internal') : null;
      };
      await r.repo.syncAll();
      expect(r.calls, hasLength(8), reason: 'round 1 only');
      expect(r.okIds, hasLength(7));

      r.calls.clear();
      r.events.clear();
      r.timers.list.single.fire();
      await until(() => r.calls.length >= 93, 'second pass');
      await r.repo.syncAll(); // serialised behind the timer pass
      // Pass 2 (timer) pushed all 92 healthy ids in 12 rounds and tried the
      // bad id last; the explicit pass above tried it once more.
      expect(r.okIds.toSet(), hasLength(99));
      expect(r.okIds, isNot(contains(bad)));
      final firstPass = r.calls.take(93).toList();
      expect(firstPass.last, bad, reason: 'bad id is the last one tried');
      expect(firstPass.where((e) => e == bad), hasLength(1));
      expect(await r.pending(), 1);
    });
  });

  group('unknown server tombstone list', () {
    test('nothing is pushed and a 60 s retry is scheduled; when the list '
        'works again the timer pass pushes everything', () async {
      await r.deleteMany(10);
      r.backend.listOffline = true;
      await r.repo.syncAll();
      expect(r.calls, isEmpty);
      expect(r.timers.list, hasLength(1));
      expect(r.timers.list.single.delay, const Duration(seconds: 60));
      expect(await r.pending(), 10);

      r.backend.listOffline = false;
      r.timers.list.single.fire();
      await until(() => r.calls.length == 10, 'timer pass');
      await r.repo.syncAll();
      expect(await r.pending(), 0);
    });

    test('an unknown list with nothing owed schedules nothing, and an unknown '
        'state never deletes a live local entry', () async {
      final id = idFor(7000);
      await r.journal.put(baseSession(id));
      r.backend.tombstones.add(id); // server knows it, but the list is unknown
      r.backend.listOffline = true;
      await r.repo.syncAll();
      expect(r.timers.list, isEmpty);
      expect(await r.journal.read(id), isNotNull,
          reason: 'unknown is never deletion');
    });
  });

  group('backoff schedule', () {
    test('60 s, 2, 4, 8, 15, 15 min then no seventh attempt; one timer at a '
        'time', () async {
      await r.deleteMany(3);
      r.failure = (id, n) => _CodeError('unavailable');
      await r.repo.syncAll();
      for (var i = 1; i < 6; i++) {
        expect(r.timers.list, hasLength(i));
        r.timers.list.last.fire();
        await until(() => r.timers.list.length == i + 1, 'timer ${i + 1}');
      }
      expect([for (final t in r.timers.list) t.delay], const [
        Duration(seconds: 60),
        Duration(minutes: 2),
        Duration(minutes: 4),
        Duration(minutes: 8),
        Duration(minutes: 15),
        Duration(minutes: 15),
      ]);
      final before = r.calls.length;
      r.timers.list.last.fire(); // the sixth timer pass fails again
      await until(() => r.calls.length == before + 1, 'sixth pass');
      await r.repo.syncAll(); // serialised; a manual pass after the budget
      await r.repo.syncAll();
      // Remediation F1 (design 17 item 23): after the six scheduled attempts
      // exactly ONE slow fallback timer keeps the owed deletions alive.
      expect(r.timers.list, hasLength(7),
          reason: 'six scheduled attempts plus one fallback timer');
      expect(r.timers.list.last.delay, kTombstoneFallbackDelay);
      expect(r.timers.list.last.delay, const Duration(minutes: 60));
      expect(r.timers.active, hasLength(1),
          reason: 'only the fallback timer is pending');
      expect(r.timers.overlaps, 0, reason: 'never two timers at once');
    });

    test('passes while a timer is pending never create a second timer',
        () async {
      await r.deleteMany(3);
      r.failure = (id, n) => _CodeError('unavailable');
      for (var i = 0; i < 4; i++) {
        await r.repo.syncAll();
      }
      expect(r.timers.list, hasLength(1));
      expect(r.timers.overlaps, 0);
    });

    test('no timer when the pusher is null, and none when nothing is owed',
        () async {
      await r.repo.dispose();
      r.repo = r.newRepo(withPusher: false);
      await r.deleteMany(5);
      r.backend.listOffline = true;
      await r.repo.syncAll();
      expect(r.timers.list, isEmpty, reason: 'pusher null: nobody can push');
      expect(await r.pending(), 5);

      final r2 = _Rig();
      await r2.open();
      addTearDown(r2.dispose);
      r2.backend.listOffline = true;
      await r2.repo.syncAll();
      expect(r2.timers.list, isEmpty, reason: 'nothing owed');
    });
  });

  group('timer cancellation', () {
    test('dispose() cancels the pending timer and a late callback never runs '
        'the pass', () async {
      await r.deleteMany(3);
      r.failure = (id, n) => _CodeError('unavailable');
      await r.repo.syncAll();
      final t = r.timers.list.single;
      expect(t.isActive, isTrue);
      await r.repo.dispose();
      expect(t.cancelled, isTrue);
      final n = r.calls.length;
      final lists = r.backend.lists;
      t.fire(); // a callback that was already queued
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(r.calls, hasLength(n));
      expect(r.backend.lists, lists);
      r.repo = r.newRepo(); // tearDown disposes a live instance
    });

    test('cancelTombstoneRetry() cancels the timer', () async {
      await r.deleteMany(3);
      r.failure = (id, n) => _CodeError('unavailable');
      await r.repo.syncAll();
      final t = r.timers.list.single;
      r.repo.cancelTombstoneRetry();
      expect(t.cancelled, isTrue);
      expect(t.isActive, isFalse);
    });
  });

  group('observability through watch()', () {
    test('pendingTombstones goes N -> 0 and the error code is carried',
        () async {
      await r.deleteMany(10);
      final states = <ActivitySyncState>[];
      final sub = r.repo.watch().listen(states.add);
      addTearDown(sub.cancel);
      await until(() => states.isNotEmpty, 'first state');
      expect(states.first.pendingTombstones, 10);
      expect(states.first.lastTombstonePushError, isNull);

      r.failure = (id, n) => _CodeError('unavailable');
      await r.repo.syncAll();
      await until(
          () => states.any((s) =>
              s.pendingTombstones == 10 &&
              s.lastTombstonePushError == 'unavailable'),
          'state with the error');

      r.failure = null;
      await r.repo.syncAll();
      await until(() => states.last.pendingTombstones == 0, 'pending 0');
      expect(states.last.isEmpty, isTrue,
          reason: 'a progress counter is not something the user resolves');
    });

    test('equality includes both fields; isEmpty ignores them', () {
      const base = ActivitySyncState();
      expect(base, const ActivitySyncState());
      expect(base, isNot(const ActivitySyncState(pendingTombstones: 1)));
      expect(base,
          isNot(const ActivitySyncState(lastTombstonePushError: 'internal')));
      expect(const ActivitySyncState(pendingTombstones: 2),
          const ActivitySyncState(pendingTombstones: 2));
      expect(
          const ActivitySyncState(
              pendingTombstones: 5, lastTombstonePushError: 'x').isEmpty,
          isTrue);
      expect(ActivitySyncState.empty.pendingTombstones, 0);
    });
  });

  group('existing semantics kept', () {
    late World w;
    setUp(() async => w = await World.open());
    tearDown(() async => w.dispose());

    test('a server tombstone deletes the live local entry in the same pass '
        'that pushes a bulk backlog; the id the server already lists is never '
        'pushed', () async {
      final id = await w.bothSynced();
      final pushed = <String>[];
      w.b.pusher = (x) async {
        pushed.add(x);
        w.server.tombstones.add(x);
      };
      await w.b.restart();
      for (var i = 100; i < 120; i++) {
        await w.b.h.journal.delete(idFor(i));
      }
      w.server.tombstones.add(id);
      final out = await w.b.repo.syncAll();
      expect(out[id], SyncOutcome.deletedLocal);
      expect(pushed.toSet(), {for (var i = 100; i < 120; i++) idFor(i)});
      expect(pushed, hasLength(20));
      pushed.clear();
      await w.b.repo.syncAll();
      expect(pushed, isEmpty,
          reason: 'the local delete caused by the server tombstone is listed '
              'by the server and is not pushed back');
    });

    test('an account-deletion fence refusal never deletes local data '
        '(conflict, entry intact)', () async {
      final id = await w.bothSynced();
      w.server.accountFence = true;
      expect(await w.b.change(id, distanceM: 5200), SyncOutcome.conflict);
      expect(await w.b.h.listIds(), [id]);
      expect(await w.b.h.journal.listTombstones(), isEmpty);
    });

    test('permission-denied without a tombstone is never deletion', () async {
      final id = await w.bothSynced();
      await w.a.change(id, distanceM: 5000);
      expect(await w.b.change(id, distanceM: 5200), SyncOutcome.conflict);
      expect(await w.b.h.listIds(), [id]);
    });
  });

  group('account change cancels the retry and drops account state', () {
    test('onAccountChanged() cancels the timer and forgets confirmed ids: a '
        'tombstone the previous account confirmed is pushed for the new one',
        () async {
      await r.deleteMany(3);
      await r.repo.syncAll(); // account A: all three confirmed
      expect(r.calls, hasLength(3));
      r.failure = (id, n) => _CodeError('unavailable');
      await r.deleteMany(2, from: 50);
      await r.repo.syncAll();
      final t = r.timers.list.single;
      expect(t.isActive, isTrue);

      r.repo.onAccountChanged();
      expect(t.cancelled, isTrue);
      expect(r.repo.lastTombstonePushError, isNull);

      // Account B: its server knows nothing yet; the same ids are B's own
      // local tombstones (ids are deterministic).
      r.backend.tombstones.clear();
      r.failure = null;
      r.calls.clear();
      await r.repo.syncAll();
      expect(r.calls.toSet(), {idFor(1), idFor(2), idFor(3), idFor(50), idFor(51)});
      expect(await r.pending(), 0);
    });

    test('a pass in flight when the account changes pushes nothing more and '
        'confirms nothing', () async {
      await r.deleteMany(20);
      final gate = Completer<void>();
      r.beforePush = (id) async {
        if (r.calls.length == 3) await gate.future;
      };
      final pass = r.repo.syncAll();
      await until(() => r.calls.length == 3, 'third push in flight');
      r.repo.onAccountChanged();
      gate.complete();
      await pass;
      expect(r.calls, hasLength(3), reason: 'no push for the next account');
      expect(r.timers.list, isEmpty, reason: 'no retry for the old account');
    });

    test('wiring: sign-out cancels the timer; a switch cancels it and the new '
        'account starts at the first backoff step', () async {
      await r.deleteMany(4);
      r.failure = (id, n) => _CodeError('unavailable');
      final auth = StreamController<AuthUser?>();
      addTearDown(() => unawaited(auth.close()));
      final c = ProviderContainer(overrides: [
        activityFlagsProvider
            .overrideWithValue(const ActivityFlags(cloudSync: true)),
        activityJournalProvider.overrideWithValue(r.journal),
        activitySyncRepositoryProvider.overrideWithValue(r.repo),
        activityStreamUploaderProvider.overrideWithValue(null),
        activityCloudSettingsClientProvider.overrideWithValue(_Settings()),
        activityConsentStoreProvider.overrideWithValue(_Consent()),
        authUserProvider.overrideWith((ref) => auth.stream),
      ]);
      addTearDown(c.dispose);
      c.read(activityCloudSyncWiringProvider);

      auth.add(_user('A'));
      await until(() => r.timers.list.length == 1, 'timer for A');
      final a = r.timers.list.first;
      expect(a.isActive, isTrue);

      auth.add(null); // sign-out
      await until(() => a.cancelled, 'timer of A cancelled by sign-out');
      expect(r.timers.active, isEmpty);

      auth.add(_user('A'));
      await until(() => r.timers.list.length == 2, 'timer for A again');
      final a2 = r.timers.list.last;
      auth.add(_user('B')); // switch A -> B
      await until(() => a2.cancelled, 'timer cancelled by the switch');
      await until(() => r.timers.list.length == 3, 'timer for B');
      expect(r.timers.list.last.delay, const Duration(seconds: 60),
          reason: 'the backoff of the old account is not inherited');
      expect(r.timers.overlaps, 0);
    });
  });
}
