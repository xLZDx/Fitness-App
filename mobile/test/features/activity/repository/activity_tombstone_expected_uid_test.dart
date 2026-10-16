// S02 test epic 16c: tombstone push and remediation J2 / J3 B3. Oracles:
// S02_DESIGN.md 17 item 25 and S02_REMEDIATION_J_TEST_NOTES.md (CLIENT J2,
// CLIENT J3b B3), not the code under test.
//
// Real `ActivitySyncRepository` over the harness journal, fake backend, fake
// pusher that records (id, expectedUid), and a fake retry-timer factory that
// records the delay (the same approach as activity_tombstone_continuation_test).
import 'dart:async';

import 'package:fitness_app/features/activity/repository/account_changed.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_summary_backend.dart';
import '../../../support/journal_harness.dart';

class _FakeTimer implements Timer {
  _FakeTimer(this.delay, this._cb);
  final Duration delay;
  final void Function() _cb;
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
    _cb();
  }
}

Future<void> settle() async {
  for (var i = 0; i < 300; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late JournalHarness h;
  late FakeSummaryBackend backend;
  late ActivitySyncRepository repo;
  late List<(String, String?)> pushes;
  late List<_FakeTimer> timers;
  late String? uid;
  late Future<void> Function(String id, String? expectedUid) onPush;

  setUp(() async {
    h = JournalHarness.memory();
    await h.open();
    backend = FakeSummaryBackend();
    pushes = [];
    timers = [];
    uid = 'A';
    onPush = (id, _) async {};
    repo = ActivitySyncRepository(
      journal: h.journal,
      backend: backend,
      clock: h.clock.call,
      authUid: () => uid,
      tombstonePusher: (id, expectedUid) async {
        pushes.add((id, expectedUid));
        await onPush(id, expectedUid);
        backend.tombstones.add(id);
      },
      retryTimerFactory: (d, cb) {
        final t = _FakeTimer(d, cb);
        timers.add(t);
        return t;
      },
    );
  });

  tearDown(() async {
    await repo.dispose();
    await h.dispose();
  });

  Future<void> owe(List<int> seeds) async {
    for (final s in seeds) {
      await h.journal.put(journalSession(idFor(s), seed: s));
      await h.journal.delete(idFor(s));
    }
  }

  Future<int> pending() async => (await repo.refreshState()).pendingTombstones;

  test('authUid of the pass is passed as expectedUid', () async {
    await owe([1]);
    await repo.syncAll();
    expect(pushes, [(idFor(1), 'A')]);
  });

  test('the value follows the pass uid (not a constant)', () async {
    uid = 'Zed';
    await owe([1]);
    await repo.syncAll();
    expect(pushes, [(idFor(1), 'Zed')]);
  });

  group('ConsentAccountChangedException while the pass is alive (J3 B3)', () {
    test('the id stays owed, no confirmation, no error text, a normal 60 s '
        'retry is scheduled', () async {
      await owe([1]);
      onPush = (_, __) async => throw const ConsentAccountChangedException();
      await repo.syncAll();
      expect(pushes, hasLength(1));
      expect(await pending(), 1, reason: 'still owed, not confirmed');
      expect(repo.lastTombstonePushError, isNull);
      expect(timers, hasLength(1));
      expect(timers.single.delay, const Duration(seconds: 60));
    });

    test('the id is not demoted as failed: the retry tries it first again, and '
        'the budget advances by exactly one (next delay 2 minutes)', () async {
      await owe([1, 2]);
      var first = true;
      onPush = (id, _) async {
        if (first) {
          first = false;
          throw const ConsentAccountChangedException();
        }
      };
      await repo.syncAll();
      expect(pushes.map((p) => p.$1), [idFor(1)],
          reason: 'the pass stops at the first refusal');
      timers.single.fire();
      await settle();
      expect(pushes.map((p) => p.$1).take(2), [idFor(1), idFor(1)],
          reason: 'a failed-set id would have been sorted after idFor(2)');
      expect(await pending(), 0);
    });

    test('the retry budget advances by exactly one per refusal (60 s, then '
        '2 minutes)', () async {
      await owe([1]);
      onPush = (_, __) async => throw const ConsentAccountChangedException();
      await repo.syncAll();
      expect(timers.single.delay, const Duration(seconds: 60));
      timers.single.fire();
      await settle();
      expect(timers, hasLength(2));
      expect(timers.last.delay, const Duration(minutes: 2));
    });

    test('lastTombstonePushError keeps an earlier generic failure unchanged',
        () async {
      await owe([1]);
      var n = 0;
      onPush = (_, __) async {
        n++;
        if (n == 1) throw StateError('boom');
        throw const ConsentAccountChangedException();
      };
      await repo.syncAll();
      final before = repo.lastTombstonePushError;
      expect(before, isNotNull, reason: 'a generic failure is recorded');
      timers.single.fire();
      await settle();
      expect(n, 2);
      expect(repo.lastTombstonePushError, before);
      expect(await pending(), 1);
    });

    test('control: a generic failure DOES record an error and demote the id',
        () async {
      await owe([1, 2]);
      var first = true;
      onPush = (id, _) async {
        if (first) {
          first = false;
          throw StateError('boom');
        }
      };
      await repo.syncAll();
      expect(repo.lastTombstonePushError, isNotNull);
    });
  });

  test('a push under A, then a flip to B before the next push: nothing is '
      'sent for B and the pass ends', () async {
    await owe([1, 2, 3]);
    onPush = (id, _) async {
      if (id == idFor(1)) uid = 'B';
    };
    await repo.syncAll();
    expect(pushes, [(idFor(1), 'A')]);
    expect(pushes.where((p) => p.$2 == 'B'), isEmpty);
    expect(await pending(), 2);
  });
}
