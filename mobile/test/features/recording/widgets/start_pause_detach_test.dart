// EP-J recorder-level stories on the REAL RecorderController with scripted
// seams: S04-34 start preconditions (DT-34-1 state side, 34-2, 34-3, 34-4,
// 34-5, 34-6), S04-35 automatic-stop state (DT-35-1, 35-2 table), S04-36 manual
// pause (DT-36-1, 36-2, 36-4, 36-5), S04-37 engine detach (DT-37-1, 37-2).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/recording/permissions/location_permission_status.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart';
import 'package:fitness_app/features/recording/state/recorder_providers.dart';
import 'package:fitness_app/features/recording/state/recorder_state_constants.dart';
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';

import 'package:fitness_app/features/recording/state/recorder_environment.dart';

import '../pages/recorder_harness.dart';

/// Runs an async controller call without awaiting it in the fake-async zone.
Future<void> runCall(Rig r, Future<void> Function() call) async {
  unawaited(call());
  for (var i = 0; i < 3; i++) {
    await r.flush();
  }
}

void expectRefused(Rig r, StartRefusal why) {
  expect(r.phase, RecorderPhase.idle);
  expect(r.state.refusal, why);
  expect(r.location.startCount, 0, reason: 'no location request on a refusal');
  expect(r.journal.calls, isNot(contains('begin')));
}

void main() {
  group('DT-34-4 refusal reason codes (no silent no-op)', () {
    rigTest('/journal-not-open', (r) async {
      r.env.ownerUid = null;
      await r.start();
      expectRefused(r, StartRefusal.journalNotOpen);
      expect(r.state.startPanel, StartPanel.cannotStart);
    });
    rigTest('/unfinished-recording-found-offers-recovery', (r) async {
      r.journal.unfinished = [readableRecording()];
      await r.start();
      expectRefused(r, StartRefusal.unfinishedRecording);
      expect(r.state.unfinished.map((u) => u.recordingId), ['old-1']);
    });
    rigTest('/consent-withdrawn', (r) async {
      r.env.consent = false;
      await r.start();
      expectRefused(r, StartRefusal.consentMissing);
      expect(r.perms.requestCount, 0, reason: 'zero permission requests');
    });
    rigTest('/permission-missing (denied, approximate)', (r) async {
      r.perms.location = LocationPermissionStatus.denied;
      await r.start();
      expectRefused(r, StartRefusal.permissionNotGranted);
    });
    rigTest('/permission approximate does not allow recording', (r) async {
      r.perms.location = LocationPermissionStatus.grantedApproximate;
      await r.start();
      expectRefused(r, StartRefusal.permissionNotGranted);
    });
    rigTest('/notification denied', (r) async {
      r.perms.notification = NotificationPermissionStatus.denied;
      await r.start();
      expectRefused(r, StartRefusal.notificationDenied);
    });
    rigTest('/own-gym-timer-running', (r) async {
      r.env.gymTimer = true;
      await r.start();
      expectRefused(r, StartRefusal.gymTimerRunning);
    });
    rigTest('/foreign-session-running', (r) async {
      r.env.foreign = true;
      await r.start();
      expectRefused(r, StartRefusal.foreignSession);
    });
    rigTest('/begin-fails -> beginFailed, nothing started', (r) async {
      r.journal.beginError = StateError('disk');
      await r.start();
      expect(r.phase, RecorderPhase.idle);
      expect(r.state.refusal, StartRefusal.beginFailed);
      expect(r.location.startCount, 0);
    });
    rigTest('/location start throws -> serviceStartFailed and released',
        (r) async {
      r.location.startError = StateError('service');
      await r.start();
      expect(r.phase, RecorderPhase.idle);
      expect(r.state.refusal, StartRefusal.serviceStartFailed);
      expect(r.state.startPanel, StartPanel.startFailed);
      expect(r.location.activeSubscriptions, 0);
    });
    rigTest('/unfinished check throws -> checkIncomplete', (r) async {
      r.journal.listError = StateError('io');
      await r.start();
      expectRefused(r, StartRefusal.checkIncomplete);
    });
    rigTest('all preconditions hold -> acquiring and one subscription',
        (r) async {
      await r.start();
      expect(r.phase, RecorderPhase.acquiring);
      expect(r.state.refusal, isNull);
      expect(r.location.activeSubscriptions, 1);
      expect(r.journal.calls, contains('begin'));
    });
  });

  group('DT-34-1 / 34-2 / 34-5 / 34-6 preparing and its timeout', () {
    rigTest('/unfinished-check-pending-shows-preparing, then both complete',
        (r) async {
      final gate = Completer<List<UnfinishedRecording>>();
      r.journal.listGate = gate;
      await r.start();
      expect(r.phase, RecorderPhase.preparing);
      expect(r.state.startPanel, StartPanel.preparing);
      expect(r.location.startCount, 0);
      gate.complete(<UnfinishedRecording>[]);
      await r.flush();
      expect(r.phase, RecorderPhase.acquiring);
    });

    rigTest('/preparing-becomes-cannotStart-after-5-s-and-not-before',
        (r) async {
      expect(kPreparingTimeoutMs, 5000);
      r.journal.listGate = Completer<List<UnfinishedRecording>>();
      await r.start();
      await r.advance(const Duration(milliseconds: 4900 - 4900 % 1000 + 900));
      // 4.9 s elapsed in whole steps of 1 s plus a remainder: still preparing.
      expect(r.phase, RecorderPhase.preparing, reason: 'not before 5 s');
      await r.advance(const Duration(milliseconds: 1100));
      expect(r.phase, RecorderPhase.idle);
      expect(r.state.startPanel, StartPanel.cannotStart);
      expect(r.state.refusal, StartRefusal.checkIncomplete);
      expect(r.location.startCount, 0);
    });

    rigTest('/preparing-timeout-calls-releaseAll: no subscription left',
        (r) async {
      r.journal.listGate = Completer<List<UnfinishedRecording>>();
      await r.start();
      await r.advance(const Duration(seconds: 6));
      expect(r.location.activeSubscriptions, 0);
      expect(r.phase, RecorderPhase.idle);
    });

    rigTest('/late completion after the timeout is ignored: no late start',
        (r) async {
      final gate = Completer<List<UnfinishedRecording>>();
      r.journal.listGate = gate;
      await r.start();
      await r.advance(const Duration(seconds: 6));
      expect(r.state.startPanel, StartPanel.cannotStart);
      gate.complete(<UnfinishedRecording>[]);
      await r.flush();
      await r.advance(const Duration(seconds: 2));
      expect(r.phase, RecorderPhase.idle);
      expect(r.location.startCount, 0);
      expect(r.journal.calls, isNot(contains('begin')));
      expect(r.state.startPanel, StartPanel.cannotStart,
          reason: 'the error the user saw stays');
    });

    rigTest('/second Start while preparing starts nothing more', (r) async {
      r.journal.listGate = Completer<List<UnfinishedRecording>>();
      await r.start();
      final before = r.journal.listCalls;
      await r.start();
      expect(r.journal.listCalls, before);
      expect(r.phase, RecorderPhase.preparing);
    });

    rigTest('/quarantined-recording-does-not-block-start', (r) async {
      r.journal.unfinished = const [
        UnfinishedRecording(
            recordingId: 'q', status: UnfinishedStatus.quarantined)
      ];
      await r.start();
      expect(r.phase, RecorderPhase.acquiring);
    });

    rigTest('/pending-revoked-decision-does-not-block-start', (r) async {
      r.journal.unfinished = const [
        UnfinishedRecording(
            recordingId: 'p',
            status: UnfinishedStatus.readable,
            pendingDecision: true)
      ];
      await r.start();
      expect(r.phase, RecorderPhase.acquiring);
    });
  });

  group('DT-34-3 startFailed timing', () {
    rigTest('/startFailed-15-s-after-begin-and-no-service-left', (r) async {
      expect(kStartFailedTimeoutMs, 15000);
      r.journal.beginGate = Completer<void>();
      await r.start();
      await r.advance(const Duration(seconds: 14));
      expect(r.phase, RecorderPhase.preparing, reason: 'not before 15 s');
      await r.advance(const Duration(seconds: 2));
      expect(r.phase, RecorderPhase.idle);
      expect(r.state.startPanel, StartPanel.startFailed);
      expect(r.state.refusal, StartRefusal.serviceStartFailed);
      expect(r.location.startCount, 0);
    });
  });

  group('DT-35-1 automatic stops (state side)', () {
    test('only battery, storage, sample cap and consent post the notification',
        () {
      const posts = {
        StopReason.battery,
        StopReason.storage,
        StopReason.sampleCap,
        StopReason.consentWithdrawn,
      };
      for (final s in StopReason.values) {
        expect(s.postsAutoStopNotification, posts.contains(s), reason: '$s');
      }
    });
    rigTest('/battery-3-percent finishes with a notice and a sealed record',
        (r) async {
      await r.startRecording();
      await r.advance(const Duration(seconds: 5));
      await r.emitBattery(3);
      await r.flush();
      expect(r.phase, isNot(RecorderPhase.recording));
      expect(r.state.autoStopNotice?.reason, StopReason.battery);
      expect(r.state.stopReason, StopReason.battery);
      expect(r.journal.calls, contains('seal:battery'));
      expect(r.journal.calls, contains('handOff'));
      expect(r.location.activeSubscriptions, 0);
    });
    rigTest('/consent-withdrawal-stop', (r) async {
      await r.startRecording();
      await runCall(r, () => r.controller.stopAutomatically(StopReason.consentWithdrawn));
      await r.flush();
      expect(r.state.autoStopNotice?.reason, StopReason.consentWithdrawn);
      expect(r.journal.calls, contains('seal:consentWithdrawn'));
    });
    rigTest('/a user stop has no automatic-stop notice', (r) async {
      await r.startRecording();
      await runCall(r, () => r.controller.stop());
      await r.flush();
      expect(r.state.autoStopNotice, isNull);
      expect(r.state.stopReason, StopReason.user);
    });
  });

  group('DT-36 manual pause', () {
    rigTest('/interval-10s-during-manual-pause then 1s after resume',
        (r) async {
      await r.startRecording();
      final subs = r.location.activeSubscriptions;
      r.controller.pause();
      await r.flush();
      expect(r.phase, RecorderPhase.pausedManual);
      expect(r.location.intervalCalls.last, 10);
      expect(r.location.activeSubscriptions, subs, reason: 'one subscription');
      r.controller.resume();
      await r.flush();
      expect(r.phase, RecorderPhase.recording);
      expect(r.location.intervalCalls.last, 1);
      expect(r.location.activeSubscriptions, subs);
    });

    rigTest('/no sample reaches the track; distance and moving time unchanged',
        (r) async {
      await r.startRecording();
      await r.advance(const Duration(seconds: 3));
      await r.fix();
      r.controller.pause();
      await r.flush();
      final d = r.state.metrics!.distanceM;
      final m = r.state.metrics!.movingTimeMs;
      final kept = r.journal.samples.length;
      for (var i = 0; i < 5; i++) {
        await r.advance(const Duration(seconds: 1));
        await r.fix();
      }
      expect(r.state.metrics!.distanceM, d);
      expect(r.state.metrics!.movingTimeMs, m);
      expect(r.journal.samples.length, kept);
      expect(r.journal.eventKinds, contains('pause'));
    });

    rigTest('/prompt-at-30-minutes-exactly (29:59 none, 30:00 one), still paused',
        (r) async {
      await r.startRecording();
      r.controller.pause();
      await r.flush();
      expect(r.state.pausePromptDue, isFalse);
      final base = r.env.now;
      r.env.now = base + const Duration(minutes: 29, seconds: 59).inMilliseconds;
      await r.t.pump(const Duration(minutes: 29, seconds: 59));
      await r.flush();
      expect(r.state.pausePromptDue, isFalse, reason: '29:59 has no prompt');
      r.env.now = base + const Duration(minutes: 30).inMilliseconds;
      await r.t.pump(const Duration(seconds: 1));
      await r.flush();
      expect(r.state.pausePromptDue, isTrue);
      expect(r.phase, RecorderPhase.pausedManual, reason: 'nothing stops');
      expect(r.journal.calls.where((c) => c.startsWith('seal')), isEmpty);
    });

    rigTest('/resume clears the prompt and returns to recording', (r) async {
      await r.startRecording();
      r.controller.pause();
      r.env.now += const Duration(minutes: 31).inMilliseconds;
      await r.t.pump(const Duration(minutes: 31));
      await r.flush();
      expect(r.state.pausePromptDue, isTrue);
      r.controller.resume();
      await r.flush();
      expect(r.state.pausePromptDue, isFalse);
      expect(r.phase, RecorderPhase.recording);
      expect(r.state.manualPauseSinceMs, isNull);
    });

    rigTest('/pause only while recording or auto-paused; no-op when idle',
        (r) async {
      r.controller.pause();
      await r.flush();
      expect(r.phase, RecorderPhase.idle);
      expect(r.location.intervalCalls, isEmpty);
    });

    rigTest('/battery critical while manual-paused: the 10 s pause interval '
        'wins, 5 s after resume', (r) async {
      await r.startRecording();
      r.controller.pause();
      await r.flush();
      await r.emitBattery(10);
      expect(r.state.flags.batteryCritical, isTrue);
      expect(r.location.intervalCalls.last, 10);
      r.controller.resume();
      await r.flush();
      expect(r.location.intervalCalls.last, 5);
    });
  });

  group('DT-37 engine detach', () {
    rigTest('stopImmediately (default): the service is released, nothing '
        'sealed, the log stays unfinished', (r) async {
      await r.startRecording();
      r.location.emitEngineDetached();
      await r.flush();
      expect(r.phase, RecorderPhase.idle);
      expect(r.location.activeSubscriptions, 0);
      expect(r.journal.calls.where((c) => c.startsWith('seal')), isEmpty);
      expect(r.journal.calls, isNot(contains('handOff')));
    });

    rigTest('graceThenStop: notification must not claim Recording, nothing '
        'journaled while detached, released after 60 s', (r) async {
      await r.startRecording();
      expect(r.state.claimsRecording, isTrue);
      final samples = r.journal.samples.length;
      r.location.emitEngineDetached();
      await r.flush();
      expect(r.state.engineDetached, isTrue);
      expect(r.state.claimsRecording, isFalse);
      expect(r.phase.isCollecting, isTrue);
      for (var i = 0; i < 3; i++) {
        await r.advance(const Duration(seconds: 1));
        await r.fix();
      }
      expect(r.journal.samples.length, samples,
          reason: 'no sample is journaled while detached');
      await r.advance(const Duration(seconds: 50));
      expect(r.phase.isCollecting, isTrue, reason: 'inside the 60 s grace');
      await r.advance(const Duration(seconds: 12));
      expect(r.phase, RecorderPhase.idle);
      expect(r.location.activeSubscriptions, 0);
      expect(r.journal.calls.where((c) => c.startsWith('seal')), isEmpty);
    }, extra: [
      engineDetachPolicyProvider.overrideWithValue(EngineDetachPolicy.graceThenStop)
    ]);

    rigTest('graceThenStop: pause is ignored while detached', (r) async {
      await r.startRecording();
      r.location.emitEngineDetached();
      await r.flush();
      r.controller.pause();
      await r.flush();
      expect(r.phase, RecorderPhase.recording);
    }, extra: [
      engineDetachPolicyProvider.overrideWithValue(EngineDetachPolicy.graceThenStop)
    ]);

    rigTest('restart after a detach offers recovery (unfinished log)',
        (r) async {
      await r.startRecording();
      r.location.emitEngineDetached();
      await r.flush();
      r.journal.unfinished = [readableRecording('rec-1')];
      final starts = r.location.startCount;
      final begins = r.journal.calls.where((c) => c == 'begin').length;
      await r.start();
      expect(r.phase, RecorderPhase.idle);
      expect(r.state.refusal, StartRefusal.unfinishedRecording);
      expect(r.location.startCount, starts, reason: 'no new location request');
      expect(r.journal.calls.where((c) => c == 'begin').length, begins);
    });

    rigTest('a detach while idle changes nothing', (r) async {
      r.location.emitEngineDetached();
      await r.flush();
      expect(r.phase, RecorderPhase.idle);
      expect(r.state.engineDetached, isFalse);
    });
  });
}
