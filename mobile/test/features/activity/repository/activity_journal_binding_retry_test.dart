// S02 remediation F2 (test epic 12b): the always-on journal binding provider
// retries a failed bind on a fixed schedule, skips the account being deleted and
// never logs a raw uid. Oracles: docs/phase2/s02/S02_REMEDIATION_F_TEST_NOTES.md
// F2 item 3 and S02_DESIGN.md section 17 item 22, not the code under test.
//
// A scripted AccountScopedJournal (no disk) and a fake timer factory: no real
// waiting, every timer is recorded and fired by the test.
import 'dart:async';

import 'package:fitness_app/core/config/activity_flags.dart';
import 'package:fitness_app/core/wiring/activity_wiring.dart';
import 'package:fitness_app/features/account_deletion/state/account_deletion_providers.dart';
import 'package:fitness_app/features/activity/repository/activity_journal.dart';
import 'package:fitness_app/features/activity/repository/uid_scoped_activity_journal.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every `bindUid` call is recorded; results come from [script] (true when the
/// script is empty). A script entry that is an Exception is thrown.
class _Scripted extends Fake implements ActivityJournal, AccountScopedJournal {
  final List<String?> calls = [];
  final List<Object> script = [];
  String? _uid;

  @override
  Future<bool> bindUid(String? uid) async {
    calls.add(uid);
    final r = script.isEmpty ? true : script.removeAt(0);
    if (r is Exception) throw r;
    if (r == true) _uid = uid;
    return r as bool;
  }

  @override
  String? get boundUid => _uid;

  @override
  bool get isBound => _uid != null;
}

class _FakeTimer implements Timer {
  _FakeTimer(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  bool _active = true;

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  /// Runs the callback; [force] fires even a cancelled timer (a stale callback).
  void fire({bool force = false}) {
    if (!_active && !force) return;
    _active = false;
    _callback();
  }
}

class _Timers {
  final List<_FakeTimer> all = [];

  _FakeTimer call(Duration d, void Function() cb) {
    final t = _FakeTimer(d, cb);
    all.add(t);
    return t;
  }

  int get active => all.where((t) => t.isActive).length;
  _FakeTimer get last => all.last;
}

AuthUser _user(String uid, {String name = 'n'}) =>
    AuthUser(uid: uid, displayName: name, provider: AuthProvider.google);

void main() {
  late _Scripted journal;
  late _Timers timers;
  late StreamController<AuthUser?> auth;
  late List<String> logs;
  late void Function(String? message, {int? wrapWidth}) savedDebugPrint;

  setUp(() {
    journal = _Scripted();
    timers = _Timers();
    auth = StreamController<AuthUser?>();
    logs = [];
    savedDebugPrint = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
  });

  tearDown(() {
    debugPrint = savedDebugPrint;
    unawaited(auth.close());
  });

  ProviderContainer make({bool teardown = true}) {
    final c = ProviderContainer(overrides: [
      activityFlagsProvider.overrideWithValue(
          const ActivityFlags(localJournal: true)),
      activityJournalProvider.overrideWithValue(journal),
      authUserProvider.overrideWith((ref) => auth.stream),
      activityBindRetryTimerFactoryProvider.overrideWithValue(timers.call),
    ]);
    if (teardown) addTearDown(c.dispose);
    c.read(activityJournalBindingProvider);
    return c;
  }

  Future<void> emit(AuthUser? u) async {
    auth.add(u);
    await pumpEventQueue();
  }

  Future<void> fireLast() async {
    timers.last.fire();
    await pumpEventQueue();
  }

  group('retry of a failed bind', () {
    test('no timer before a failure; a failed bind schedules exactly one 5 s '
        'timer; firing it binds without any auth event', () async {
      journal.script.add(false);
      make();
      expect(timers.all, isEmpty);
      await emit(_user('A'));
      expect(journal.calls, ['A']);
      expect(timers.all, hasLength(1));
      expect(timers.last.delay, const Duration(seconds: 5));
      expect(timers.active, 1);

      await fireLast();
      expect(journal.calls, ['A', 'A'], reason: 'retried with no auth event');
      expect(journal.boundUid, 'A');
      expect(timers.all, hasLength(1), reason: 'no further timer after success');
      expect(timers.active, 0);
    });

    test('a bind that THROWS is retried the same way', () async {
      journal.script.add(StateError('keystore'));
      make();
      await emit(_user('A'));
      expect(timers.all, hasLength(1));
      expect(timers.last.delay, const Duration(seconds: 5));
      await fireLast();
      expect(journal.boundUid, 'A');
      expect(timers.active, 0);
    });

    test('delays 5 s, 15 s, 60 s, 5 min, 5 min, then stop: six binds in total',
        () async {
      journal.script.addAll(List<Object>.filled(10, false));
      make();
      await emit(_user('A'));
      const expected = [
        Duration(seconds: 5),
        Duration(seconds: 15),
        Duration(seconds: 60),
        Duration(minutes: 5),
        Duration(minutes: 5),
      ];
      for (var i = 0; i < expected.length; i++) {
        expect(timers.all, hasLength(i + 1), reason: 'timer $i exists');
        expect(timers.last.delay, expected[i], reason: 'delay of retry $i');
        expect(timers.active, 1, reason: 'never two pending retries');
        await fireLast();
      }
      expect(journal.calls, hasLength(6));
      expect(timers.all, hasLength(5), reason: 'no sixth timer');
      expect(timers.active, 0);
      expect(logs.any((l) => l.contains('gave up')), isTrue,
          reason: 'giving up is visible in the log');
      await pumpEventQueue();
      expect(journal.calls, hasLength(6), reason: 'never more');
    });

    test('a new auth value (other uid) cancels the pending retry; the stale '
        'callback binds nothing', () async {
      journal.script.add(false);
      make();
      await emit(_user('A'));
      final stale = timers.last;
      expect(stale.isActive, isTrue);

      await emit(_user('B'));
      expect(stale.isActive, isFalse);
      expect(journal.calls, ['A', 'B']);
      stale.fire(force: true);
      await pumpEventQueue();
      expect(journal.calls, ['A', 'B'], reason: 'the old callback is inert');
      expect(timers.active, 0);
    });

    test('sign-out cancels the pending retry and unbinds', () async {
      journal.script.add(false);
      make();
      await emit(_user('A'));
      final stale = timers.last;
      await emit(null);
      expect(stale.isActive, isFalse);
      expect(journal.calls, ['A', null]);
      stale.fire(force: true);
      await pumpEventQueue();
      expect(journal.calls, ['A', null]);
    });

    test('A fails then B fails: only B has a pending retry (never two)',
        () async {
      journal.script.addAll([false, false]);
      make();
      await emit(_user('A'));
      final a = timers.last;
      await emit(_user('B'));
      expect(a.isActive, isFalse);
      expect(timers.all, hasLength(2));
      expect(timers.active, 1);
      expect(timers.last.delay, const Duration(seconds: 5),
          reason: 'B starts its own schedule');
    });

    test('a retry that fires after the signed-in uid changed does not bind the '
        'old uid', () async {
      journal.script.add(false);
      make();
      await emit(_user('A'));
      final t = timers.last;
      // The auth value changes but the stale callback is forced anyway.
      await emit(null);
      t.fire(force: true);
      await pumpEventQueue();
      expect(journal.calls.where((c) => c == 'A'), hasLength(1));
    });

    test('provider disposal cancels the pending retry', () async {
      journal.script.add(false);
      final c = make(teardown: false);
      await emit(_user('A'));
      final t = timers.last;
      expect(t.isActive, isTrue);
      c.dispose();
      expect(t.isActive, isFalse);
      t.fire(force: true);
      await pumpEventQueue();
      expect(journal.calls, ['A'], reason: 'a disposed wiring binds nothing');
    });

    test('a failed unbind (null) is final: no timer', () async {
      journal.script.add(false);
      make();
      await emit(null);
      expect(timers.all, isEmpty);
    });

    test('no raw uid in any log line, even when the error message holds it',
        () async {
      const secret = 'uid-secret-7f3a91';
      journal.script
        ..add(StateError('failed for $secret'))
        ..addAll(List<Object>.filled(8, false));
      make();
      await emit(_user(secret));
      for (var i = 0; i < 5; i++) {
        await fireLast();
      }
      expect(logs, isNotEmpty, reason: 'positive control: something was logged');
      expect(logs.any((l) => l.contains('bind failed')), isTrue);
      for (final l in logs) {
        expect(l.contains(secret), isFalse, reason: 'leaked in: $l');
      }
    });
  });

  group('the account being deleted', () {
    test('an auth value equal to the deleting uid unbinds and never binds it',
        () async {
      final c = make();
      c.read(accountBeingDeletedUidProvider.notifier).state = 'A';
      await emit(_user('A'));
      expect(journal.calls, [null]);
      expect(journal.isBound, isFalse);
      expect(timers.all, isEmpty);
    });

    test('control: another uid is bound normally while A is being deleted',
        () async {
      final c = make();
      c.read(accountBeingDeletedUidProvider.notifier).state = 'A';
      await emit(_user('B'));
      expect(journal.calls, ['B']);
    });

    test('A bound, then deleted: the re-emitted A unbinds it', () async {
      final c = make();
      await emit(_user('A'));
      expect(journal.boundUid, 'A');
      c.read(accountBeingDeletedUidProvider.notifier).state = 'A';
      await emit(_user('A', name: 'again'));
      expect(journal.calls, ['A', null]);
      expect(journal.isBound, isFalse);
    });

    test('a pending retry for a uid that became the deleting one does not bind',
        () async {
      journal.script.add(false);
      final c = make();
      await emit(_user('A'));
      final t = timers.last;
      c.read(accountBeingDeletedUidProvider.notifier).state = 'A';
      t.fire();
      await pumpEventQueue();
      expect(journal.calls, ['A'], reason: 'no second bind of A');
      expect(journal.isBound, isFalse);
    });
  });
}
