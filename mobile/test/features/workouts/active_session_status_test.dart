import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/workouts/data/set_session.dart';
import 'package:fitness_app/features/workouts/state/active_session_status.dart';
import 'package:fitness_app/features/workouts/state/rest_timer_providers.dart';
import 'package:fitness_app/features/workouts/state/set_timer_providers.dart';

import '../../support/s03_shell_harness.dart';

class _SpyTimer implements Timer {
  _SpyTimer(this.delay, this.callback);
  final Duration delay;
  final void Function() callback;
  bool cancelled = false;
  @override
  void cancel() => cancelled = true;
  @override
  bool get isActive => !cancelled;
  @override
  int get tick => 0;
}

final DateTime _t0 = DateTime.utc(2026, 10, 17, 12);

SetTimerState _set(SetPhase p, {bool running = true}) => SetTimerState(
    phase: p,
    setNumber: 1,
    secondsLeft: 30,
    totalSets: 2,
    progress: 0.1,
    running: running);

void main() {
  group('table of contract S-4 (pure derivation)', () {
    ActiveSessionStatus? d(SetTimerState s, RestTimerState r, [DateTime? now]) =>
        deriveActiveSessionStatus(
            setTimer: s, rest: r, now: now ?? _t0);
    final idleSet = SetTimerState.idle;

    test('set phases map to running or paused; done and idle hide', () {
      for (final p in [SetPhase.gettingReady, SetPhase.work, SetPhase.rest]) {
        expect(d(_set(p), RestTimerState.idle)!.state,
            ActiveSessionState.running, reason: '$p');
        expect(d(_set(p, running: false), RestTimerState.idle)!.state,
            ActiveSessionState.paused, reason: '$p');
      }
      expect(d(_set(SetPhase.done), RestTimerState.idle), isNull);
      expect(d(idleSet, RestTimerState.idle), isNull);
    });

    test('DT-07-3 finished rest: visible at 9:59, hidden at 10:00 and 10:01', () {
      final end = _t0;
      final rest = RestTimerState(total: const Duration(seconds: 30), endsAt: end);
      expect(d(idleSet, rest, end.add(const Duration(minutes: 9, seconds: 59)))!.state,
          ActiveSessionState.restFinished);
      expect(d(idleSet, rest, end.add(const Duration(minutes: 10))), isNull,
          reason: 'exactly endsAt + 10 min is hidden (RV-8)');
      expect(d(idleSet, rest, end.add(const Duration(minutes: 10, seconds: 1))), isNull);
    });

    test('rest states: resting, paused, skipped, and set timer wins', () {
      final run = RestTimerState(
          total: const Duration(seconds: 60),
          endsAt: _t0.add(const Duration(seconds: 60)));
      expect(d(idleSet, run)!.state, ActiveSessionState.resting);
      expect(d(idleSet, const RestTimerState(
              total: Duration(seconds: 60), pausedRemaining: Duration(seconds: 20)))!
          .state, ActiveSessionState.paused);
      expect(d(idleSet, const RestTimerState(skipped: true)), isNull);
      // DT-07-2: paused set timer wins over a finished rest.
      final fin = RestTimerState(total: const Duration(seconds: 30), endsAt: _t0);
      expect(d(_set(SetPhase.work, running: false), fin,
              _t0.add(const Duration(minutes: 1)))!
          .state, ActiveSessionState.paused);
    });

    test('DT-07-4 same instant in UTC or local zone gives the same answer', () {
      final end = DateTime.utc(2026, 3, 29, 0, 59); // around a DST change
      final rest = RestTimerState(total: const Duration(seconds: 30), endsAt: end);
      final now = end.add(const Duration(minutes: 5));
      final a = d(idleSet, rest, now);
      final b = d(idleSet, RestTimerState(total: const Duration(seconds: 30), endsAt: end.toLocal()),
          now.toLocal());
      expect(a, isNotNull);
      expect(b!.state, a!.state);
      expect(b.restEndsAt!.isAtSameMomentAs(a.restEndsAt!), isTrue);
    });
  });

  group('driven transitions and ownership (real controllers)', () {
    ProviderContainer mk(TestClock clock,
        {StreamController<AuthUser?>? auth,
        List<_SpyTimer>? spies,
        List<String>? logs}) {
      final c = ProviderContainer(overrides: [
        ...realTimerOverrides(clock),
        authUserProvider.overrideWith((ref) async* {
          yield kUserA;
          if (auth != null) yield* auth.stream;
        }),
        if (spies != null)
          activeSessionTimerFactoryProvider.overrideWithValue((delay, cb) {
            final t = _SpyTimer(delay, cb);
            spies.add(t);
            return t;
          }),
      ]);
      addTearDown(c.dispose);
      c.listen(activeSessionStatusProvider, (_, __) {});
      return c;
    }

    test('DT-07-10 one-shot timers are armed per state, re-armed, cancelled on dispose', () {
      fakeAsync((async) {
        final clock = TestClock();
        final spies = <_SpyTimer>[];
        final c = mk(clock, spies: spies);
        async.flushMicrotasks();
        expect(spies, isEmpty, reason: 'idle: nothing to arm');
        c.read(restTimerProvider.notifier).start(const Duration(seconds: 30));
        async.flushMicrotasks();
        c.read(activeSessionStatusProvider); // a frame reads the provider
        expect(spies.map((s) => s.delay).toList(),
            [const Duration(seconds: 30), const Duration(seconds: 30, minutes: 10)]);
        final first = List<_SpyTimer>.of(spies);
        c.read(restTimerProvider.notifier).pause();
        async.flushMicrotasks();
        c.read(activeSessionStatusProvider);
        expect(first.every((s) => s.cancelled), isTrue,
            reason: 'a state change cancels the old one-shots');
        c.read(restTimerProvider.notifier).resume();
        async.flushMicrotasks();
        c.read(activeSessionStatusProvider);
        final armed = spies.where((s) => !s.cancelled).toList();
        expect(armed.length, 2, reason: 'resume re-arms both');
        c.dispose();
        expect(spies.every((s) => s.cancelled), isTrue,
            reason: 'dispose leaves zero pending timers');
      });
    });

    test('DT-07-12 neither timer provider is auto-dispose', () async {
      final clock = TestClock();
      final c = ProviderContainer(overrides: realTimerOverrides(clock));
      addTearDown(c.dispose);
      final s1 = c.read(setTimerProvider.notifier);
      final r1 = c.read(restTimerProvider.notifier);
      final sub1 = c.listen(setTimerProvider, (_, __) {});
      final sub2 = c.listen(restTimerProvider, (_, __) {});
      sub1.close();
      sub2.close();
      await Future<void>.delayed(Duration.zero);
      expect(identical(c.read(setTimerProvider.notifier), s1), isTrue);
      expect(identical(c.read(restTimerProvider.notifier), r1), isTrue);
    });

    test('DT-07-5 owner is cleared when the session ends and replaced on the next',
        () {
      fakeAsync((async) {
        final clock = TestClock();
        final c = mk(clock);
        async.flushMicrotasks();
        c.read(activeSessionOwnerProvider.notifier)
            .capture(uid: 'uidA', destination: '/workout/ex1?day=d1');
        c.read(setTimerProvider.notifier).start(kTestSetPlan);
        async.flushMicrotasks();
        final st = c.read(activeSessionStatusProvider);
        expect(st, isNotNull);
        expect(st!.destination, '/workout/ex1?day=d1');
        expect(c.read(activeSessionDestinationProvider), '/workout/ex1?day=d1');
        c.read(setTimerProvider.notifier).reset();
        async.flushMicrotasks();
        expect(c.read(activeSessionStatusProvider), isNull);
        expect(c.read(activeSessionOwnerProvider), isNull,
            reason: 'owner must not outlive the session');
        expect(c.read(activeSessionDestinationProvider), kActiveSessionDefaultDestination);
        c.read(activeSessionOwnerProvider.notifier)
            .capture(uid: 'uidA', destination: '/workout/ex2');
        c.read(setTimerProvider.notifier).start(kTestSetPlan);
        async.flushMicrotasks();
        expect(c.read(activeSessionStatusProvider)!.destination, '/workout/ex2');
      });
    });

    test('DT-07-8 (provider level) foreign owner hides the session, owner kept', () {
      fakeAsync((async) {
        final clock = TestClock();
        final auth = StreamController<AuthUser?>.broadcast();
        final c = mk(clock, auth: auth);
        async.flushMicrotasks();
        c.read(activeSessionOwnerProvider.notifier)
            .capture(uid: 'uidA', destination: '/workout/ex1');
        c.read(setTimerProvider.notifier).start(kTestSetPlan);
        async.flushMicrotasks();
        expect(c.read(activeSessionStatusProvider)!.ownerUid, 'uidA');
        auth.add(kUserB);
        async.flushMicrotasks();
        expect(c.read(activeSessionStatusProvider), isNull,
            reason: 'owner uid is read from the owner, not the current auth');
        final timerBefore = c.read(setTimerProvider);
        async.elapse(const Duration(seconds: 5));
        final timerAfter = c.read(setTimerProvider);
        expect(timerAfter.running, isTrue);
        expect(
            timerAfter.phase != timerBefore.phase ||
                timerAfter.secondsLeft != timerBefore.secondsLeft,
            isTrue,
            reason: 'timers are untouched and still tick');
        expect(c.read(activeSessionForeignOwnerProvider), isTrue,
            reason: 'the shell must know the session belongs to another account');
        expect(c.read(activeSessionOwnerProvider), isNotNull,
            reason: 'decision: the owner is kept while the timer runs');
        auth.add(kUserA);
        async.flushMicrotasks();
        expect(c.read(activeSessionForeignOwnerProvider), isFalse);
        expect(c.read(activeSessionStatusProvider), isNotNull,
            reason: 'the owner account sees its session again');
        auth.close();
      });
    });

    test('DT-07-1 a throwing timer hides the strip and logs only the type', () {
      final logs = <String>[];
      final old = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
      addTearDown(() => debugPrint = old);
      final c = ProviderContainer(overrides: [
        setTimerProvider.overrideWith(() => FakeSetTimer(SetTimerState.idle, throwOnBuild: true)),
        restClockProvider.overrideWithValue(TestClock().call),
        authUserProvider.overrideWith((ref) => Stream.value(kUserA)),
      ]);
      addTearDown(c.dispose);
      expect(c.read(activeSessionStatusProvider), isNull);
      final joined = logs.join('\n');
      expect(joined, contains('derive_failed'));
      expect(joined, contains('StateError'));
      expect(joined, isNot(contains('SECRET')),
          reason: 'the exception message must never be logged');
    });
  });
}
