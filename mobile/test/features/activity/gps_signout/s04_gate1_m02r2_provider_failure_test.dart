// S04 gate 1, round 2, finding M-02-R2-01: a failed read of
// recordingJournalPortProvider / recorderPhaseProvider used to count as "no
// recordings" and let sign-out skip the pre-unbind hook. Round 3 (M-02-R3-01):
// "not wired" is now the explicit recorderWiredProvider flag (default false), not
// the type of an exception. Flag false: "no recordings", no recorder provider is
// read. Flag true: ANY failure, UnimplementedError included, is the cannot-check
// outcome (explicit "Sign out anyway" choice, which still runs the leave path
// with the hook). The throwing/working modes below therefore set the flag true.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/wiring/activity_wiring.dart';
import 'package:fitness_app/features/activity/state/sign_out_guard.dart';
import 'package:fitness_app/features/recording/journal/pre_unbind_hook.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart';
import 'package:fitness_app/features/recording/state/recorder_ports.dart'
    show recorderWiredProvider;
import 'package:fitness_app/features/recording/state/recorder_providers.dart';
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';

import '../../../support/s03_step4_support.dart';

Finder key(String k) => find.byKey(Key(k));

const String _cannotCheckTitle =
    'We could not check the activity stored on this device';

class _Port extends Fake implements RecordingJournalPort {
  /// Throws on every call from the [failFrom]-th (1-based) on; 0 = never.
  int failFrom = 0;
  int lists = 0;
  @override
  Future<List<UnfinishedRecording>> listUnfinished() async {
    lists++;
    if (failFrom > 0 && lists >= failFrom) throw StateError('io');
    return const <UnfinishedRecording>[];
  }
}

class _Hook implements PreUnbindHook {
  final List<String> uids = <String>[];
  final List<UnbindReason> reasons = <UnbindReason>[];
  @override
  Future<void> run(String ownerUid, UnbindReason reason) async {
    uids.add(ownerUid);
    reasons.add(reason);
  }
}

class _Host extends ConsumerWidget {
  const _Host(this.results);
  final List<bool> results;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const Key('host.signOut'),
            onPressed: () async =>
                results.add(await confirmSignOutWithLocalData(context, ref)),
            child: const Text('go'),
          ),
        ),
      );
}

Future<void> settle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 80));
  }
}

/// unwired: flag false (default), port not overridden.
/// unwiredSpy: flag false, port and phase overridden with providers that count
///   every read (the not-wired path must never read them).
/// wiredUnimplemented: flag true, port left at its default UnimplementedError.
/// throwing / working: flag true with a throwing / working port.
enum _PortMode { unwired, unwiredSpy, wiredUnimplemented, throwing, working }

enum _PhaseMode { idle, throwing }

class _W {
  _W(this.results, this.hook, this.port, this.reads);
  final List<bool> results;
  final _Hook hook;
  final _Port port;
  final List<String> reads;
}

Future<_W> pumpGuard(
  WidgetTester t, {
  required _PortMode portMode,
  _PhaseMode phaseMode = _PhaseMode.idle,
  bool withActivity = false,
  int portFailFrom = 0,
}) async {
  t.view.physicalSize = const Size(800, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final journal = FakeJournal(withActivity
      ? [entry(sess('a1', start: DateTime.utc(2026, 10, 1, 8)))]
      : const []);
  final port = _Port()..failFrom = portFailFrom;
  final hook = _Hook();
  final registry = PreUnbindHookRegistry()..register(hook);
  final results = <bool>[];
  final reads = <String>[];
  final bool wired = portMode != _PortMode.unwired &&
      portMode != _PortMode.unwiredSpy;
  await t.pumpWidget(appHost(_Host(results), overrides: [
    ...dashOverrides(journal: journal),
    // Only the explicit flag marks a wired recorder (main.dart does the same
    // under GPS_RECORDER); the default stays false.
    if (wired) recorderWiredProvider.overrideWithValue(true),
    switch (portMode) {
      // Not overridden at all: the flag is false and the default body stays.
      _PortMode.unwired => null,
      _PortMode.unwiredSpy => recordingJournalPortProvider.overrideWith((ref) {
          reads.add('port');
          throw UnimplementedError('spy');
        }),
      // Flag true, port provider left at its default UnimplementedError.
      _PortMode.wiredUnimplemented => null,
      _PortMode.throwing => recordingJournalPortProvider
          .overrideWith((ref) => throw StateError('x')),
      _PortMode.working => recordingJournalPortProvider.overrideWithValue(port),
    },
    switch (phaseMode) {
      _PhaseMode.idle => portMode == _PortMode.unwiredSpy
          ? recorderPhaseProvider.overrideWith((ref) {
              reads.add('phase');
              return RecorderPhase.idle;
            })
          : recorderPhaseProvider.overrideWithValue(RecorderPhase.idle),
      _PhaseMode.throwing =>
        recorderPhaseProvider.overrideWith((ref) => throw StateError('p')),
    },
    activityPreUnbindHookRegistryProvider.overrideWithValue(registry),
  ].whereType<Override>().toList()));
  await settle(t);
  return _W(results, hook, port, reads);
}

Future<void> trigger(WidgetTester t) async {
  await t.tap(key('host.signOut'));
  await settle(t);
}

/// The cannot-check sheet is up, nothing was decided and the hook did not run.
void expectCannotCheckPending(_W w) {
  expect(find.text(_cannotCheckTitle), findsOneWidget);
  expect(key('signOut.anyway'), findsOneWidget);
  expect(w.results, isEmpty, reason: 'no silent sign-out');
  expect(w.hook.uids, isEmpty, reason: 'hook waits for the explicit choice');
}

Future<void> pickAnywayAndExpectLeave(WidgetTester t, _W w) async {
  await t.tap(key('signOut.anyway'));
  await settle(t);
  expect(w.hook.uids, ['A'], reason: 'leave path runs the hook while bound');
  expect(w.hook.reasons, [UnbindReason.signOut]);
  expect(w.results, [true]);
}

void main() {
  group('M-02-R2-01 provider failures, zero activities', () {
    testWidgets('port provider throws StateError: cannot-check sheet, hook '
        'only after Sign out anyway', (t) async {
      final w = await pumpGuard(t, portMode: _PortMode.throwing);
      await trigger(t);
      expectCannotCheckPending(w);
      await pickAnywayAndExpectLeave(t, w);
    });

    testWidgets('port provider throws StateError: Cancel keeps the user signed '
        'in and never runs the hook', (t) async {
      final w = await pumpGuard(t, portMode: _PortMode.throwing);
      await trigger(t);
      await t.tap(key('signOut.cancel'));
      await settle(t);
      expect(w.results, [false]);
      expect(w.hook.uids, isEmpty);
    });

    testWidgets('working port, recorderPhaseProvider throws: cannot-check, hook '
        'only after Sign out anyway', (t) async {
      final w = await pumpGuard(t,
          portMode: _PortMode.working, phaseMode: _PhaseMode.throwing);
      await trigger(t);
      expectCannotCheckPending(w);
      expect(w.port.lists, 0, reason: 'the phase failed before listing');
      await pickAnywayAndExpectLeave(t, w);
    });

    testWidgets('default UnimplementedError (recorder not wired): sign-out '
        'proceeds at once, no sheet, no hook', (t) async {
      final w = await pumpGuard(t, portMode: _PortMode.unwired);
      await trigger(t);
      expect(w.results, [true]);
      expect(w.hook.uids, isEmpty);
      expect(find.text(_cannotCheckTitle), findsNothing);
      expect(key('signOut.anyway'), findsNothing);
      expect(key('signOut.cancel'), findsNothing);
    });

    testWidgets('the not-wired path ignores a throwing phase provider (it is '
        'never read)', (t) async {
      final w = await pumpGuard(t,
          portMode: _PortMode.unwired, phaseMode: _PhaseMode.throwing);
      await trigger(t);
      expect(w.results, [true]);
      expect(w.hook.uids, isEmpty);
      expect(find.text(_cannotCheckTitle), findsNothing);
    });

    testWidgets('count succeeds but the second listing (any-files check) '
        'throws: cannot-check, hook only after Sign out anyway', (t) async {
      final w = await pumpGuard(t, portMode: _PortMode.working, portFailFrom: 2);
      await trigger(t);
      expect(w.port.lists, 2, reason: 'count then any-files listing');
      expectCannotCheckPending(w);
      await pickAnywayAndExpectLeave(t, w);
    });
  });

  group('M-02-R3-01 explicit wired flag, zero activities (any-files path)', () {
    testWidgets('flag true + port provider throws UnimplementedError: '
        'cannot-check sheet, not a silent true; hook only after Sign out '
        'anyway', (t) async {
      final w = await pumpGuard(t, portMode: _PortMode.wiredUnimplemented);
      await trigger(t);
      expectCannotCheckPending(w);
      await pickAnywayAndExpectLeave(t, w);
    });

    testWidgets('flag true + port provider throws UnimplementedError: Cancel '
        'returns false and never runs the hook', (t) async {
      final w = await pumpGuard(t, portMode: _PortMode.wiredUnimplemented);
      await trigger(t);
      expect(find.text(_cannotCheckTitle), findsOneWidget);
      await t.tap(key('signOut.cancel'));
      await settle(t);
      expect(w.results, [false]);
      expect(w.hook.uids, isEmpty);
    });

    testWidgets('flag true + working port but UnimplementedError from the '
        'phase provider: cannot-check', (t) async {
      final w = await pumpGuard(t,
          portMode: _PortMode.working, phaseMode: _PhaseMode.throwing);
      await trigger(t);
      expectCannotCheckPending(w);
    });

    testWidgets('flag false (default), nothing overridden: true, no sheet, no '
        'hook, and neither the port nor the phase provider is ever read',
        (t) async {
      final w = await pumpGuard(t, portMode: _PortMode.unwiredSpy);
      await trigger(t);
      expect(w.results, [true]);
      expect(w.hook.uids, isEmpty);
      expect(find.text(_cannotCheckTitle), findsNothing);
      expect(key('signOut.anyway'), findsNothing);
      expect(w.reads, isEmpty,
          reason: 'not wired: no recorder provider is read');
      expect(w.port.lists, 0);
    });
  });

  group('M-02-R3-01 explicit wired flag, account with local activities '
      '(count path)', () {
    testWidgets('flag true + port provider throws UnimplementedError: '
        'cannot-check, not the warning sheet; hook only after Sign out anyway',
        (t) async {
      final w = await pumpGuard(t,
          portMode: _PortMode.wiredUnimplemented, withActivity: true);
      await trigger(t);
      expectCannotCheckPending(w);
      expect(key('signOut.keep'), findsNothing,
          reason: 'a failed count must not fall through to a warning with 0');
      await pickAnywayAndExpectLeave(t, w);
    });

    testWidgets('flag true + port provider throws UnimplementedError: Cancel '
        'returns false', (t) async {
      final w = await pumpGuard(t,
          portMode: _PortMode.wiredUnimplemented, withActivity: true);
      await trigger(t);
      await t.tap(key('signOut.cancel'));
      await settle(t);
      expect(w.results, [false]);
      expect(w.hook.uids, isEmpty);
    });

    testWidgets('flag false (default): normal warning sheet with activities '
        'only, no recorder provider is read', (t) async {
      final w = await pumpGuard(t,
          portMode: _PortMode.unwiredSpy, withActivity: true);
      await trigger(t);
      expect(find.text(_cannotCheckTitle), findsNothing);
      expect(key('signOut.keep'), findsOneWidget);
      expect(w.reads, isEmpty,
          reason: 'not wired: the count path reads no recorder provider');
      await t.tap(key('signOut.keep'));
      await settle(t);
      expect(w.results, [true]);
      // The post-hook check of the leave path may read the port (its failure is
      // swallowed); that is outside the count/any-files decision under test.
    });
  });

  group('M-02-R2-01 provider failures, account with local activities (count '
      'path)', () {
    testWidgets('port provider throws StateError: cannot-check, not the '
        'warning sheet, hook only after Sign out anyway', (t) async {
      final w = await pumpGuard(t,
          portMode: _PortMode.throwing, withActivity: true);
      await trigger(t);
      expectCannotCheckPending(w);
      expect(key('signOut.keep'), findsNothing,
          reason: 'a failed count must not fall through to a warning with 0');
      await pickAnywayAndExpectLeave(t, w);
    });

    testWidgets('working port, phase provider throws: cannot-check, hook only '
        'after Sign out anyway', (t) async {
      final w = await pumpGuard(t,
          portMode: _PortMode.working,
          phaseMode: _PhaseMode.throwing,
          withActivity: true);
      await trigger(t);
      expectCannotCheckPending(w);
      expect(key('signOut.keep'), findsNothing);
      await pickAnywayAndExpectLeave(t, w);
    });

    testWidgets('default UnimplementedError: the normal warning sheet with '
        'activities only, Sign out keeps data and offers the hand-off to the hook', (t) async {
      final w = await pumpGuard(t,
          portMode: _PortMode.unwired, withActivity: true);
      await trigger(t);
      expect(find.text(_cannotCheckTitle), findsNothing);
      expect(key('signOut.keep'), findsOneWidget);
      expect(w.results, isEmpty);
      await t.tap(key('signOut.keep'));
      await settle(t);
      expect(w.results, [true]);
      expect(w.hook.uids, ['A'],
          reason: 'leaving always offers the bounded hand-off to a registered '
              'hook');
    });
  });
}
