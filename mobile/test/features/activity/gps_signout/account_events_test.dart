// S04-30 account events on the REAL bind controller (activityJournalBindingProvider)
// with the REAL registry and the REAL scoped journal over temp files:
// DT-30-2 (sign-out, uid change, deletion), DT-30-9 (what counts as an event),
// DT-30-10 (the controller awaits the hook, the scope is still bound while it
// runs, the 5 s bound, failure and no-hook outcomes).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/config/activity_flags.dart';
import 'package:fitness_app/core/wiring/activity_wiring.dart';
import 'package:fitness_app/features/account_deletion/state/account_deletion_providers.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/recording/journal/pre_unbind_hook.dart';

import '../../../support/scoped_journal_world.dart';

class _Hook implements PreUnbindHook {
  _Hook(this.world, this.log, {this.mode = 'ok'});
  final ScopedJournalWorld world;
  final List<String> log;
  String mode; // ok | throw | hang | gate
  Completer<void>? gate;

  @override
  Future<void> run(String ownerUid, UnbindReason reason) async {
    log.add('hook:$ownerUid:${reason.name}:bound=${world.journal.boundUid}');
    if (mode == 'throw') throw StateError('boom');
    if (mode == 'hang') await Completer<void>().future;
    if (mode == 'gate') await gate!.future;
    log.add('hook-done');
  }
}

AuthUser user(String uid) =>
    AuthUser(uid: uid, displayName: uid, provider: AuthProvider.google);

void main() {
  late ScopedJournalWorld w;
  late StreamController<AuthUser?> auth;
  late List<String> log;
  late PreUnbindHookRegistry registry;
  late ProviderContainer c;

  setUp(() async {
    w = await ScopedJournalWorld.create();
    auth = StreamController<AuthUser?>();
    log = <String>[];
    registry = PreUnbindHookRegistry();
    c = ProviderContainer(overrides: [
      activityFlagsProvider.overrideWithValue(const ActivityFlags(localJournal: true)),
      activityJournalProvider.overrideWithValue(w.journal),
      authUserProvider.overrideWith((ref) => auth.stream),
      activityPreUnbindHookRegistryProvider.overrideWithValue(registry),
    ]);
    c.listen(activityJournalBindingProvider, (_, __) {});
  });

  tearDown(() async {
    c.dispose();
    unawaited(auth.close());
    await w.dispose();
  });

  Future<void> until(bool Function() done, [String? why]) async {
    for (var i = 0; i < 1000 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(done(), isTrue, reason: 'condition not reached: $why $log');
  }

  Future<void> emit(AuthUser? u) async {
    auth.add(u);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 120));

  Future<void> signInA() async {
    await emit(user('A'));
    await until(() => w.journal.boundUid == 'A', 'A bound');
  }

  group('DT-30-2 / 30-10 events that run the hook', () {
    test('/explicit-sign-out: hook for the owner, scope still bound, then unbound',
        () async {
      registry.register(_Hook(w, log));
      await signInA();
      await emit(null);
      await until(() => w.journal.boundUid == null, 'unbound');
      expect(log, <String>['hook:A:signOut:bound=A', 'hook-done']);
    });

    test('the unbind WAITS for the hook (gate held, scope stays bound)',
        () async {
      final h = _Hook(w, log, mode: 'gate')..gate = Completer<void>();
      registry.register(h);
      await signInA();
      await emit(null);
      await settle();
      expect(log, <String>['hook:A:signOut:bound=A']);
      expect(w.journal.boundUid, 'A', reason: 'not unbound while the hook runs');
      h.gate!.complete();
      await until(() => w.journal.boundUid == null, 'unbound after the hook');
      expect(log.last, 'hook-done');
    });

    test('/different-nonnull-uid: uidChanged for A, then B is bound', () async {
      registry.register(_Hook(w, log));
      await signInA();
      await emit(user('B'));
      await until(() => w.journal.boundUid == 'B', 'B bound');
      expect(log, <String>['hook:A:uidChanged:bound=A', 'hook-done']);
    });

    test('A -> B -> null runs the hook for each departing owner', () async {
      registry.register(_Hook(w, log));
      await signInA();
      await emit(user('B'));
      await until(() => w.journal.boundUid == 'B');
      log.clear();
      await emit(null);
      await until(() => w.journal.boundUid == null);
      expect(log.first, 'hook:B:signOut:bound=B');
    });

    test('/deletion-event: accountDeleted once for the bound uid', () async {
      registry.register(_Hook(w, log));
      await signInA();
      c.read(accountBeingDeletedUidProvider.notifier).state = 'A';
      await until(() => log.contains('hook:A:accountDeleted:bound=A'), 'deleted');
      await settle();
      expect(log.where((e) => e.startsWith('hook:')), hasLength(1));
    });

    test('a deletion for ANOTHER uid runs nothing', () async {
      registry.register(_Hook(w, log));
      await signInA();
      c.read(accountBeingDeletedUidProvider.notifier).state = 'Z';
      await settle();
      expect(log, isEmpty);
      expect(w.journal.boundUid, 'A');
    });
  });

  group('DT-30-1 / 30-9 what is NOT an event', () {
    test('/null-then-same-uid with no bound scope runs nothing', () async {
      registry.register(_Hook(w, log));
      await emit(null);
      await settle();
      expect(log, isEmpty, reason: 'nothing was bound, nothing to hand off');
    });

    test('a repeated emission of the same uid runs nothing and keeps the scope',
        () async {
      registry.register(_Hook(w, log));
      await signInA();
      await emit(user('A'));
      await emit(user('A'));
      await settle();
      expect(log, isEmpty);
      expect(w.journal.boundUid, 'A');
    });

    test('a stream error (no new value) changes nothing', () async {
      registry.register(_Hook(w, log));
      await signInA();
      auth.addError(StateError('auth glitch'));
      await settle();
      expect(log, isEmpty);
      expect(w.journal.boundUid, 'A');
    });

    test('first sign-in never runs the hook (nothing departs)', () async {
      registry.register(_Hook(w, log));
      await signInA();
      await settle();
      expect(log, isEmpty);
    });
  });

  group('DT-30-10 outcomes of the bounded run', () {
    test('/no hook registered: sign-out still unbinds', () async {
      await signInA();
      await emit(null);
      await until(() => w.journal.boundUid == null);
      expect(log, isEmpty);
    });

    test('/a throwing hook still unbinds', () async {
      registry.register(_Hook(w, log, mode: 'throw'));
      await signInA();
      await emit(null);
      await until(() => w.journal.boundUid == null);
      expect(log.first, 'hook:A:signOut:bound=A');
    });

    test('/hook-times-out-at-5-s: still bound at 4 s, unbound after the bound',
        () async {
      registry.register(_Hook(w, log, mode: 'hang'));
      await signInA();
      final started = DateTime.now();
      await emit(null);
      await Future<void>.delayed(const Duration(seconds: 4));
      expect(w.journal.boundUid, 'A', reason: 'inside the 5 s bound');
      await until(() => w.journal.boundUid == null, 'unbound after the timeout');
      final waited = DateTime.now().difference(started);
      expect(waited, greaterThanOrEqualTo(const Duration(seconds: 4, milliseconds: 800)));
      expect(waited, lessThan(const Duration(seconds: 8)));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('a newer auth value while the hook runs drops the old continuation',
        () async {
      final h = _Hook(w, log, mode: 'gate')..gate = Completer<void>();
      registry.register(h);
      await signInA();
      await emit(null); // hook for A starts and waits
      await settle();
      await emit(user('B')); // a newer value arrives meanwhile
      await settle();
      h.gate!.complete();
      await until(() => w.journal.boundUid == 'B', 'B bound');
      // The null continuation was dropped: the final state is B, not unbound.
      await settle();
      expect(w.journal.boundUid, 'B');
    });
  });
}
