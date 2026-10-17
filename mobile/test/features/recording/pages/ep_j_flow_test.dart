// EP-J flow tests on the REAL RecorderController with scripted seams:
// S04-34 start preconditions (DT-34-1 .. 34-6), S04-35 automatic-stop notices
// (DT-35-1, 35-2), S04-36 manual pause (DT-36-1, 36-2, 36-4), S04-37 engine
// detach (DT-37-1, 37-2) and the recovery entry used after a detach.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/recording/permissions/location_permission_status.dart';
import 'package:fitness_app/features/recording/pipeline/recording_constants.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart';
import 'package:fitness_app/features/recording/state/recorder_ports.dart';
import 'package:fitness_app/features/recording/state/recorder_environment.dart';
import 'package:fitness_app/features/recording/state/recorder_state.dart';
import 'package:fitness_app/features/recording/state/recorder_state_constants.dart';
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';

import 'recorder_harness.dart';

Future<void> _jump(Rig r, Duration d) async {
  // One big step: the 1 s tick timer fires once per second inside the pump.
  r.env.now += d.inMilliseconds;
  await r.t.pump(d);
  await r.flush();
}

/// Runs an async controller call to completion without awaiting it in the
/// fake-async zone (stream cancels need the real event loop).
Future<void> _run(Rig r, Future<void> Function() call) async {
  unawaited(call());
  for (var i = 0; i < 3; i++) {
    await r.flush();
  }
}

void main() {
  group('DT-34-1 preparing while the checks run', () {
    rigTest('/unfinished-check-pending-shows-preparing: nothing started',
        (r) async {
      r.journal.listGate = Completer<List<UnfinishedRecording>>();
      await r.start();
      expect(r.phase, RecorderPhase.preparing);
      expect(r.state.startPanel, StartPanel.preparing);
      expect(r.location.startCount, 0, reason: 'no service while preparing');
      expect(r.perms.requestCount, 0, reason: 'no permission request');
      expect(r.journal.calls, isNot(contains('begin')));
      r.journal.listGate!.complete(<UnfinishedRecording>[]);
      await r.flush();
      expect(r.phase, RecorderPhase.acquiring);
      expect(r.location.startCount, 1);
    });

    rigTest('/both-complete-start-works: acquiring with a recording id',
        (r) async {
      await r.start();
      expect(r.phase, RecorderPhase.acquiring);
      expect(r.state.recordingId, isNotNull);
      expect(r.state.startPanel, StartPanel.none);
      expect(r.journal.calls.take(2), <String>['listUnfinished', 'begin']);
      expect(r.journal.lastMeta!.ownerUid, 'uidA');
      expect(r.journal.lastMeta!.sport, SportType.running);
      expect(r.location.activeSubscriptions, 1);
    });

    rigTest('/second Start while preparing is ignored', (r) async {
      r.journal.listGate = Completer<List<UnfinishedRecording>>();
      await r.start();
      await r.start();
      expect(r.journal.listCalls, 1);
      r.journal.listGate!.complete(<UnfinishedRecording>[]);
      await r.flush();
      expect(r.journal.calls.where((c) => c == 'begin'), hasLength(1));
    });
  });

  group('DT-34-2 / 34-6 the 5 s preparing bound', () {
    rigTest('/preparing-becomes-cannotStart-after-5-s-and-not-before (4.9 s)',
        (r) async {
      r.journal.listGate = Completer<List<UnfinishedRecording>>();
      await r.start();
      await r.t.pump(const Duration(milliseconds: 4900));
      await r.flush();
      expect(r.phase, RecorderPhase.preparing, reason: '4.9 s is still preparing');
      await r.t.pump(const Duration(milliseconds: 100));
      await r.flush();
      expect(r.phase, RecorderPhase.idle);
      expect(r.state.startPanel, StartPanel.cannotStart);
      expect(r.state.refusal, StartRefusal.checkIncomplete);
      expect(r.location.startCount, 0, reason: 'nothing was started');
      expect(r.location.activeSubscriptions, 0);
    });

    rigTest(
        '/late completion is ignored: no late start after the user saw an error',
        (r) async {
      r.journal.listGate = Completer<List<UnfinishedRecording>>();
      await r.start();
      await r.t.pump(const Duration(milliseconds: 5000));
      await r.flush();
      expect(r.state.startPanel, StartPanel.cannotStart);
      r.journal.listGate!.complete(<UnfinishedRecording>[]);
      await r.flush();
      await r.t.pump(const Duration(seconds: 2));
      await r.flush();
      expect(r.phase, RecorderPhase.idle);
      expect(r.state.startPanel, StartPanel.cannotStart);
      expect(r.location.startCount, 0, reason: 'a late start must not fire');
      expect(r.journal.calls, isNot(contains('begin')));
    });

    rigTest('/journal-open-fails-shows-cannotStart (no owner)', (r) async {
      r.env.ownerUid = null;
      await r.start();
      expect(r.phase, RecorderPhase.idle);
      expect(r.state.startPanel, StartPanel.cannotStart);
      expect(r.state.refusal, StartRefusal.journalNotOpen);
      expect(r.location.startCount, 0);
    });

    rigTest('/try-again retries once and then works', (r) async {
      r.env.ownerUid = null;
      await r.start();
      expect(r.state.startPanel, StartPanel.cannotStart);
      r.env.ownerUid = 'uidA';
      r.controller.dismissStartPanel();
      expect(r.state.startPanel, StartPanel.none);
      await r.start();
      expect(r.phase, RecorderPhase.acquiring);
      expect(r.location.startCount, 1);
    });

    rigTest('the list call failing is cannotStart, not a start', (r) async {
      r.journal.listError = StateError('io');
      await r.start();
      expect(r.phase, RecorderPhase.idle);
      expect(r.state.refusal, StartRefusal.checkIncomplete);
      expect(r.location.startCount, 0);
    });
  });

  group('DT-34-3 starting and startFailed', () {
    rigTest('/second-tap-starts-nothing and 14.9 s is still preparing',
        (r) async {
      r.journal.beginGate = Completer<void>();
      await r.start();
      await r.start(); // the second tap
      expect(r.journal.calls.where((c) => c == 'begin'), hasLength(1));
      await r.t.pump(const Duration(milliseconds: 14900));
      await r.flush();
      expect(r.phase, RecorderPhase.preparing);
      r.journal.beginGate!.complete();
      await r.flush();
      expect(r.phase, RecorderPhase.acquiring);
    });

    rigTest('/startFailed-15-s and no service left', (r) async {
      r.journal.beginGate = Completer<void>();
      await r.start();
      await r.t.pump(const Duration(milliseconds: 15000));
      await r.flush();
      expect(r.phase, RecorderPhase.idle);
      expect(r.state.startPanel, StartPanel.startFailed);
      expect(r.state.refusal, StartRefusal.serviceStartFailed);
      expect(r.location.activeSubscriptions, 0);
      expect(r.location.startCount, 0);
      // A late begin completion must not resurrect the start.
      r.journal.beginGate!.complete();
      await r.flush();
      expect(r.phase, RecorderPhase.idle);
      expect(r.location.startCount, 0);
    });

    rigTest('/begin throws: cannotStart with beginFailed', (r) async {
      r.journal.beginError = StateError('disk');
      await r.start();
      expect(r.phase, RecorderPhase.idle);
      expect(r.state.startPanel, StartPanel.cannotStart);
      expect(r.state.refusal, StartRefusal.beginFailed);
      expect(r.location.startCount, 0);
    });

    rigTest('/the location service throwing on start is startFailed',
        (r) async {
      r.location.startError = StateError('no service');
      await r.start();
      expect(r.phase, RecorderPhase.idle);
      expect(r.state.startPanel, StartPanel.startFailed);
      expect(r.state.refusal, StartRefusal.serviceStartFailed);
      expect(r.location.activeSubscriptions, 0);
    });
  });

  group('DT-34-4 refusal reasons', () {
    Future<void> expectRefusal(Rig r, StartRefusal reason, StartPanel panel) async {
      await r.start();
      expect(r.phase, RecorderPhase.idle);
      expect(r.state.refusal, reason);
      expect(r.state.startPanel, panel);
      expect(r.location.startCount, 0, reason: 'never started: $reason');
      expect(r.journal.calls, isNot(contains('begin')));
    }

    rigTest('/journal-not-open', (r) async {
      r.env.ownerUid = null;
      await expectRefusal(r, StartRefusal.journalNotOpen, StartPanel.cannotStart);
    });
    rigTest('/unfinished-recording-found-offers-recovery', (r) async {
      r.journal.unfinished = <UnfinishedRecording>[readableRecording()];
      await expectRefusal(
          r, StartRefusal.unfinishedRecording, StartPanel.none);
      expect(r.state.unfinished, hasLength(1));
    });
    rigTest('/consent-withdrawn', (r) async {
      r.env.consent = false;
      await expectRefusal(r, StartRefusal.consentMissing, StartPanel.none);
      expect(r.perms.requestCount, 0);
    });
    rigTest('/permission-missing', (r) async {
      r.perms.location = LocationPermissionStatus.denied;
      await expectRefusal(r, StartRefusal.permissionNotGranted, StartPanel.none);
      expect(r.perms.requestCount, 0, reason: 'the recorder never asks itself');
    });
    rigTest('/approximate-only is refused too', (r) async {
      r.perms.location = LocationPermissionStatus.grantedApproximate;
      await expectRefusal(r, StartRefusal.permissionNotGranted, StartPanel.none);
    });
    rigTest('/notification-denied', (r) async {
      r.perms.notification = NotificationPermissionStatus.denied;
      await expectRefusal(r, StartRefusal.notificationDenied, StartPanel.none);
    });
    rigTest('/notification not required: start proceeds', (r) async {
      r.perms.notification = NotificationPermissionStatus.denied;
      r.env.requireNotif = false;
      await r.start();
      expect(r.phase, RecorderPhase.acquiring);
    });
    rigTest('/own-gym-timer-running', (r) async {
      r.env.gymTimer = true;
      await expectRefusal(r, StartRefusal.gymTimerRunning, StartPanel.none);
    });
    rigTest('/foreign-session', (r) async {
      r.env.foreign = true;
      await expectRefusal(r, StartRefusal.foreignSession, StartPanel.none);
    });
    rigTest('/permission status read failing is checkIncomplete', (r) async {
      r.perms.locationStatusError = StateError('platform');
      await expectRefusal(r, StartRefusal.checkIncomplete, StartPanel.cannotStart);
    });
    rigTest('precedence: journal, gym, foreign, consent come in that order',
        (r) async {
      r.env.gymTimer = true;
      r.env.foreign = true;
      r.env.consent = false;
      await r.start();
      expect(r.state.refusal, StartRefusal.gymTimerRunning);
      r.controller.dismissStartPanel();
      r.env.gymTimer = false;
      await r.start();
      expect(r.state.refusal, StartRefusal.foreignSession);
      r.controller.dismissStartPanel();
      r.env.foreign = false;
      await r.start();
      expect(r.state.refusal, StartRefusal.consentMissing);
    });
  });

  group('DT-34-5 what does not block a start', () {
    rigTest('/preparing-timeout-calls-releaseAll: nothing is left running',
        (r) async {
      r.journal.listGate = Completer<List<UnfinishedRecording>>();
      await r.start();
      await r.t.pump(const Duration(milliseconds: 5000));
      await r.flush();
      expect(r.location.activeSubscriptions, 0);
    });
    rigTest('/quarantined-recording-does-not-block-start', (r) async {
      r.journal.unfinished = <UnfinishedRecording>[
        const UnfinishedRecording(
            recordingId: 'q', status: UnfinishedStatus.quarantined),
      ];
      await r.start();
      expect(r.phase, RecorderPhase.acquiring);
    });
    rigTest('/pending-revoked-decision-does-not-block-start', (r) async {
      r.journal.unfinished = <UnfinishedRecording>[
        const UnfinishedRecording(
            recordingId: 'p',
            status: UnfinishedStatus.readable,
            pendingDecision: true),
      ];
      await r.start();
      expect(r.phase, RecorderPhase.acquiring);
    });
  });

  group('DT-35-1 automatic stops and their notice', () {
    rigTest('/battery-3-percent: one notice, content-free', (r) async {
      await r.startRecording();
      for (var i = 0; i < 6; i++) {
        await r.advance(const Duration(seconds: 1));
        await r.fix();
      }
      await r.emitBattery(3);
      await r.advance(const Duration(seconds: 1));
      expect(r.phase, RecorderPhase.finished);
      expect(r.state.stopReason, StopReason.battery);
      final n = r.state.autoStopNotice;
      expect(n, isNotNull);
      expect(n!.reason, StopReason.battery);
      expect(n.movingTimeMs, greaterThan(0));
      expect(n.distanceM, greaterThan(0));
      expect(r.journal.calls, contains('seal:battery'));
      expect(r.journal.calls, contains('handOff'));
      expect(r.location.activeSubscriptions, 0);
    });

    rigTest('/storage-failure-60s: storageGaveUp stops with a notice',
        (r) async {
      await r.startRecording();
      r.journal.faultController.add(JournalFault.storageGaveUp);
      await r.flush();
      await r.flush();
      expect(r.phase, RecorderPhase.finished);
      expect(r.state.stopReason, StopReason.storage);
      expect(r.state.autoStopNotice?.reason, StopReason.storage);
    });

    rigTest('storageFailing only sets the chip flag, it does not stop',
        (r) async {
      await r.startRecording();
      r.journal.faultController.add(JournalFault.storageFailing);
      await r.flush();
      expect(r.phase, RecorderPhase.recording);
      expect(r.state.flags.storageWriteFailing, isTrue);
      r.journal.faultController.add(JournalFault.storageRecovered);
      await r.flush();
      expect(r.state.flags.storageWriteFailing, isFalse);
    });

    rigTest('/consent-withdrawal-stop: notice with the consent reason',
        (r) async {
      await r.startRecording();
      await _run(r, () => r.controller.stopAutomatically(StopReason.consentWithdrawn));
      await r.flush();
      expect(r.phase, RecorderPhase.finished);
      expect(r.state.autoStopNotice?.reason, StopReason.consentWithdrawn);
      expect(r.journal.calls, contains('event:stoppedConsent'));
    });

    rigTest('/account stop (owner scope lost): NO notice, reason account',
        (r) async {
      await r.startRecording();
      r.journal.faultController.add(JournalFault.ownerScopeLost);
      await r.flush();
      await r.flush();
      expect(r.state.stopReason, StopReason.account);
      expect(r.state.autoStopNotice, isNull);
      expect(r.journal.calls, contains('event:stoppedAccount'));
    });

    rigTest('/permission-loss-posts-gpsRevokedNotif-instead: no stop notice',
        (r) async {
      await r.startRecording();
      r.perms.location = LocationPermissionStatus.permanentlyDenied;
      r.location.emitError(StateError('lost'));
      await r.flush();
      await r.flush();
      await r.advance(const Duration(seconds: 2));
      expect(r.phase, RecorderPhase.permissionRevoked);
      expect(r.state.autoStopNotice, isNull);
      expect(r.state.stopReason, StopReason.permissionRevoked);
      expect(StopReason.permissionRevoked.postsAutoStopNotification, isFalse);
    });

    rigTest('a user stop has no notice', (r) async {
      await r.startRecording();
      await _run(r, () => r.controller.stop());
      await r.flush();
      expect(r.phase, RecorderPhase.finished);
      expect(r.state.autoStopNotice, isNull);
    });

    test('/the notice set is exactly battery, storage, sampleCap, consent', () {
      final posts = StopReason.values
          .where((e) => e.postsAutoStopNotification)
          .toSet();
      expect(posts, <StopReason>{
        StopReason.battery,
        StopReason.storage,
        StopReason.sampleCap,
        StopReason.consentWithdrawn,
      });
    });

    rigTest('auto stop before any fix discards the empty recording with the reason',
        (r) async {
      await r.start();
      await _run(r, () => r.controller.stopAutomatically(StopReason.battery));
      await r.flush();
      expect(r.phase, RecorderPhase.idle);
      expect(r.state.stopReason, StopReason.battery);
      expect(r.state.autoStopNotice, isNull);
      expect(r.journal.calls, contains('decideDelete'));
    });
  });

  group('DT-35-2 the notice carries no coordinate, pace or sport', () {
    test('AutoStopNotice has exactly reason, moving time and distance', () {
      const n = AutoStopNotice(
          reason: StopReason.battery, movingTimeMs: 1, distanceM: 2);
      expect(n.reason, StopReason.battery);
      expect(n.movingTimeMs, 1);
      expect(n.distanceM, 2);
    });
  });

  group('DT-36 manual pause', () {
    rigTest('/interval-10s-during-manual-pause and 1 s after resume', (r) async {
      await r.startRecording();
      r.controller.pause();
      await r.flush();
      expect(r.phase, RecorderPhase.pausedManual);
      expect(r.location.intervalCalls.last, 10);
      expect(r.location.activeSubscriptions, 1,
          reason: 'one subscription throughout');
      r.controller.resume();
      await r.flush();
      expect(r.phase, RecorderPhase.recording);
      expect(r.location.intervalCalls.last, 1);
      expect(r.location.activeSubscriptions, 1);
      expect(r.location.startCount, 1);
    });

    rigTest(
        '/no-sample-reaches-the-track-and-distance-and-moving-time-unchanged',
        (r) async {
      await r.startRecording();
      await r.advance(const Duration(seconds: 3));
      r.controller.pause();
      await r.flush();
      final dist = r.state.totalDistanceM;
      final moving = r.state.totalMovingTimeMs;
      final samples = r.journal.samples.length;
      for (var i = 0; i < 5; i++) {
        await r.advance(const Duration(seconds: 1));
        await r.fix();
      }
      await r.advance(const Duration(seconds: 20));
      expect(r.phase, RecorderPhase.pausedManual);
      expect(r.journal.samples.length, samples);
      expect(r.state.totalDistanceM, dist);
      expect(r.state.totalMovingTimeMs, moving);
    });

    rigTest('/prompt-at-30-minutes-exactly-once: 29:59 none, 30:00 one',
        (r) async {
      await r.startRecording();
      r.controller.pause();
      await r.flush();
      expect(r.state.pausePromptDue, isFalse);
      await _jump(r, const Duration(minutes: 29, seconds: 59));
      expect(r.state.pausePromptDue, isFalse, reason: '29:59');
      await _jump(r, const Duration(seconds: 1));
      expect(r.state.pausePromptDue, isTrue, reason: '30:00');
      expect(r.phase, RecorderPhase.pausedManual, reason: 'still paused');
      expect(r.journal.calls.any((c) => c.startsWith('seal:')), isFalse,
          reason: 'nothing stops or is discarded');
      expect(r.journal.calls, isNot(contains('decideDelete')));
      // Still one flag on later ticks; resume clears it.
      await _jump(r, const Duration(minutes: 5));
      expect(r.state.pausePromptDue, isTrue);
      r.controller.resume();
      await r.flush();
      expect(r.state.pausePromptDue, isFalse);
      expect(r.state.manualPauseSinceMs, isNull);
    });

    test('/the prompt bound is 30 minutes and the pause interval 10 s', () {
      expect(kManualPausePromptAfterMs, 30 * 60 * 1000);
      expect(kManualPauseIntervalMs, 10000);
    });

    rigTest('/never-for-auto-pause: a long auto-pause shows no prompt',
        (r) async {
      await r.startRecording();
      for (var i = 0; i < 12; i++) {
        await r.advance(const Duration(seconds: 1));
        await r.fix(speed: 0);
      }
      if (r.phase != RecorderPhase.pausedAuto) {
        // Standing still needs a few more seconds in the pipeline.
        for (var i = 0; i < 20 && r.phase != RecorderPhase.pausedAuto; i++) {
          await r.advance(const Duration(seconds: 1));
          await r.fix(speed: 0);
        }
      }
      expect(r.phase, RecorderPhase.pausedAuto);
      await _jump(r, const Duration(minutes: 31));
      expect(r.state.pausePromptDue, isFalse);
      expect(r.state.manualPauseSinceMs, isNull);
    });

    rigTest('/manual pause from an auto-pause is allowed and counted from then',
        (r) async {
      await r.startRecording();
      for (var i = 0; i < 40 && r.phase != RecorderPhase.pausedAuto; i++) {
        await r.advance(const Duration(seconds: 1));
        await r.fix(speed: 0);
      }
      expect(r.phase, RecorderPhase.pausedAuto);
      r.controller.pause();
      await r.flush();
      expect(r.phase, RecorderPhase.pausedManual);
      expect(r.state.manualPauseSinceMs, isNotNull);
    });

    rigTest('/pause ignored while acquiring and after stop', (r) async {
      await r.start();
      r.controller.pause();
      expect(r.phase, RecorderPhase.acquiring);
      await r.fix();
      await r.advance(const Duration(seconds: 1));
      await r.fix();
      await _run(r, () => r.controller.stop());
      await r.flush();
      r.controller.pause();
      expect(r.phase, RecorderPhase.finished);
    });
  });

  group('DT-37 engine detach', () {
    rigTest('/default stopImmediately: collection released, nothing sealed, '
        'recording kept for recovery', (r) async {
      await r.startRecording();
      final samples = r.journal.samples.length;
      r.location.emitEngineDetached();
      await r.flush();
      await r.flush();
      expect(r.phase, RecorderPhase.idle);
      expect(r.location.activeSubscriptions, 0);
      expect(r.journal.calls.any((c) => c.startsWith('seal:')), isFalse,
          reason: 'the log stays unfinished for recovery');
      expect(r.journal.calls, isNot(contains('handOff')));
      expect(r.journal.calls, isNot(contains('decideDelete')));
      expect(r.journal.samples.length, samples);
      expect(r.state.claimsRecording, isFalse);
    });

    rigTest('/never-says-Recording-while-no-fix-is-consumed (graceThenStop)',
        (r) async {
      await r.startRecording();
      expect(r.state.claimsRecording, isTrue);
      r.location.emitEngineDetached();
      await r.flush();
      expect(r.state.engineDetached, isTrue);
      expect(r.state.claimsRecording, isFalse);
      expect(r.phase, RecorderPhase.recording, reason: 'not stopped yet');
    }, extra: [
      engineDetachPolicyProvider.overrideWithValue(EngineDetachPolicy.graceThenStop),
    ]);

    rigTest('/nothing-journaled-while-detached', (r) async {
      await r.startRecording();
      r.location.emitEngineDetached();
      await r.flush();
      final samples = r.journal.samples.length;
      final dist = r.state.totalDistanceM;
      for (var i = 0; i < 5; i++) {
        await r.advance(const Duration(seconds: 1));
        await r.fix();
      }
      expect(r.journal.samples.length, samples);
      expect(r.state.totalDistanceM, dist);
      r.controller.pause();
      expect(r.phase, RecorderPhase.recording, reason: 'pause refused');
    }, extra: [
      engineDetachPolicyProvider.overrideWithValue(EngineDetachPolicy.graceThenStop),
    ]);

    rigTest('/service-released-after-the-grace-period (60 s)', (r) async {
      await r.startRecording();
      r.location.emitEngineDetached();
      await r.flush();
      await _jump(r, const Duration(milliseconds: kEngineDetachGraceMs - 1000));
      expect(r.phase, RecorderPhase.recording, reason: '59 s');
      expect(r.location.activeSubscriptions, 1);
      await _jump(r, const Duration(seconds: 1));
      await r.flush();
      expect(r.phase, RecorderPhase.idle, reason: '60 s');
      expect(r.location.activeSubscriptions, 0);
      expect(r.journal.calls.any((c) => c.startsWith('seal:')), isFalse);
    }, extra: [
      engineDetachPolicyProvider.overrideWithValue(EngineDetachPolicy.graceThenStop),
    ]);

    rigTest('/restart-offers-recovery-with-a-marked-gap', (r) async {
      await r.startRecording();
      final id = r.state.recordingId!;
      r.location.emitEngineDetached();
      await r.flush();
      await r.flush();
      expect(r.phase, RecorderPhase.idle);

      // The "restart": the journal lists the unsealed recording.
      r.journal.unfinished = <UnfinishedRecording>[readableRecording(id)];
      await _run(r, () => r.controller.checkUnfinished());
      await r.flush();
      expect(r.phase, RecorderPhase.restoring);
      expect(r.state.unfinished.map((u) => u.recordingId), <String>[id]);

      final meta = RecordingMeta(
        recordingId: id,
        startUtcMs: r.env.now - 600000,
        utcOffsetMinutes: 0,
        sport: SportType.running,
        autoPauseEnabled: true,
        ownerUid: 'uidA',
      );
      r.journal.resumeResult = RecoveredRecording(
        meta: meta,
        lastOffsetMs: 540000,
        distanceM: 1500,
        movingTimeMs: 500000,
        keptCount: 100,
      );
      await _run(r, () => r.controller.resumeRecovered(id));
      await r.flush();
      expect(r.phase, RecorderPhase.acquiring);
      expect(r.state.hasRecoveredData, isTrue);
      expect(r.state.recoveredDistanceM, 1500);
      expect(r.state.recoveredMovingTimeMs, 500000);
      expect(r.location.activeSubscriptions, 1);
    });
  });

  group('recovery entry guards', () {
    rigTest('checkUnfinished: empty list returns to idle', (r) async {
      await _run(r, () => r.controller.checkUnfinished());
      await r.flush();
      expect(r.phase, RecorderPhase.idle);
    });
    rigTest('checkUnfinished: an unreadable recording is recoveryFailed',
        (r) async {
      r.journal.unfinished = <UnfinishedRecording>[
        const UnfinishedRecording(
            recordingId: 'u', status: UnfinishedStatus.unreadable),
      ];
      await _run(r, () => r.controller.checkUnfinished());
      await r.flush();
      expect(r.phase, RecorderPhase.recoveryFailed);
    });
    rigTest('resume is refused with consent withdrawn (DT-33-3)', (r) async {
      r.journal.unfinished = <UnfinishedRecording>[readableRecording('x')];
      await _run(r, () => r.controller.checkUnfinished());
      await r.flush();
      r.env.consent = false;
      await _run(r, () => r.controller.resumeRecovered('x'));
      await r.flush();
      expect(r.phase, RecorderPhase.restoring);
      expect(r.state.refusal, StartRefusal.consentMissing);
      expect(r.location.startCount, 0);
    });
    rigTest('save-as-finished and discard still work with consent withdrawn '
        '(DT-33-3)', (r) async {
      r.env.consent = false;
      r.journal.unfinished = <UnfinishedRecording>[readableRecording('x')];
      await _run(r, () => r.controller.checkUnfinished());
      await r.flush();
      await _run(r, () => r.controller.saveRecoveredAsFinished('x'));
      await r.flush();
      expect(r.phase, RecorderPhase.finished);
      expect(r.journal.calls, contains('handOff'));
    });
    rigTest('discard works with consent withdrawn', (r) async {
      r.env.consent = false;
      r.journal.unfinished = <UnfinishedRecording>[readableRecording('x')];
      await _run(r, () => r.controller.checkUnfinished());
      await r.flush();
      await _run(r, () => r.controller.discardRecovered('x'));
      await r.flush();
      expect(r.phase, RecorderPhase.idle);
      expect(r.journal.calls, contains('decideDelete'));
    });
  });
}
