// EP-F S04-22 battery-critical behaviour (rows DT-22-1, DT-22-2, DT-22-4,
// DT-22-6, DT-22-7, DT-22-8, DT-36-5) against the REAL RecorderController with
// a scripted battery, location source and journal. The widget-test clock
// drives the recorder timers.
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/recording/state/battery_monitor.dart';
import 'package:fitness_app/features/recording/state/recorder_display.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart';
import 'package:fitness_app/features/recording/state/recorder_providers.dart';
import 'package:fitness_app/features/recording/state/recorder_state_constants.dart';
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';

import '../pages/recorder_harness.dart';

void main() {
  group('BatteryPolicy pure thresholds', () {
    BatteryReading r(int p, {bool c = false}) =>
        BatteryReading(percent: p, charging: c);

    test('constants are 10, 12 and 3', () {
      expect(kBatteryCriticalPercent, 10);
      expect(kBatteryCriticalExitPercent, 12);
      expect(kBatteryFinishPercent, 3);
      expect(kBatteryCriticalFlushIntervalMs, 1000);
      expect(kFlushIntervalMs, 5000);
    });

    test('entersCritical: 11 no, 10 yes, 9 yes, charging never', () {
      expect(BatteryPolicy.entersCritical(r(11)), isFalse);
      expect(BatteryPolicy.entersCritical(r(10)), isTrue);
      expect(BatteryPolicy.entersCritical(r(9)), isTrue);
      expect(BatteryPolicy.entersCritical(r(10, c: true)), isFalse);
      expect(BatteryPolicy.entersCritical(r(1, c: true)), isFalse);
    });

    test('leavesCritical: 11 no, 12 yes, charging yes at any level', () {
      expect(BatteryPolicy.leavesCritical(r(11)), isFalse);
      expect(BatteryPolicy.leavesCritical(r(12)), isTrue);
      expect(BatteryPolicy.leavesCritical(r(5, c: true)), isTrue);
      expect(BatteryPolicy.leavesCritical(r(9)), isFalse);
    });

    test('finishes: 4 no, 3 yes, 2 yes, charging never', () {
      expect(BatteryPolicy.finishes(r(4)), isFalse);
      expect(BatteryPolicy.finishes(r(3)), isTrue);
      expect(BatteryPolicy.finishes(r(2)), isTrue);
      expect(BatteryPolicy.finishes(r(3, c: true)), isFalse);
      expect(BatteryPolicy.finishes(r(0, c: true)), isFalse);
    });

    test('BatteryReading value equality and toString carry no extras', () {
      expect(r(5), r(5));
      expect(r(5) == r(5, c: true), isFalse);
      expect(r(5).hashCode, r(5).hashCode);
      expect(r(5).toString(), 'BatteryReading(5, charging=false)');
    });
  });

  group('FakeBatteryMonitor', () {
    test('current() is null until a value is emitted, then the last value',
        () async {
      final m = FakeBatteryMonitor();
      expect(await m.current(), isNull);
      final got = <BatteryReading>[];
      final sub = m.readings.listen(got.add);
      m.emit(42, charging: true);
      await Future<void>.delayed(Duration.zero);
      expect(await m.current(),
          const BatteryReading(percent: 42, charging: true));
      expect(got, [const BatteryReading(percent: 42, charging: true)]);
      await sub.cancel();
      await m.dispose();
    });
  });

  group('DT-22-1 thresholds on a recording', () {
    for (final p in [11, 12, 50]) {
      rigTest('/$p percent unplugged: no critical state', (rig) async {
        await rig.startRecording();
        await rig.emitBattery(p);
        expect(rig.state.flags.batteryCritical, isFalse);
        expect(rig.phase, RecorderPhase.recording);
        expect(rig.journal.flushIntervals, [kFlushIntervalMs]);
        expect(rig.location.intervalCalls, isEmpty);
        expect(rig.container.read(recorderDisplayProvider).banner, isNull);
      });
    }

    for (final p in [10, 9, 4]) {
      rigTest('/$p percent unplugged: critical, 5 s requests, 1 s flush, banner',
          (rig) async {
        await rig.startRecording();
        await rig.emitBattery(p);
        expect(rig.state.flags.batteryCritical, isTrue);
        expect(rig.phase, RecorderPhase.recording,
            reason: '$p percent keeps recording');
        expect(rig.location.intervalCalls.last, 5);
        expect(rig.journal.flushIntervals.last, kBatteryCriticalFlushIntervalMs);
        expect(rig.container.read(recorderDisplayProvider).banner,
            RecorderBanner.batteryCritical);
        expect(rig.journal.eventKinds, contains('batteryCritical'));
        expect(rig.location.activeSubscriptions, 1);
      });
    }

    for (final p in [3, 2, 0]) {
      rigTest('/$p percent unplugged: finish and save with reason battery',
          (rig) async {
        await rig.startRecording();
        await rig.emitBattery(p);
        expect(rig.phase, RecorderPhase.finished);
        expect(rig.state.stopReason, StopReason.battery);
        expect(rig.state.autoStopNotice?.reason, StopReason.battery);
        expect(rig.journal.calls,
            containsAllInOrder(['event:stoppedBattery', 'seal:battery', 'handOff']));
        expect(rig.journal.lastSeal?.reason, StopReason.battery);
        expect(rig.location.activeSubscriptions, 0);
        expect(rig.location.stopCount, greaterThanOrEqualTo(1));
      });
    }

    rigTest('/3 percent also stops from the critical state (10 then 3)',
        (rig) async {
      await rig.startRecording();
      await rig.emitBattery(10);
      expect(rig.state.flags.batteryCritical, isTrue);
      await rig.emitBattery(3);
      expect(rig.phase, RecorderPhase.finished);
      expect(rig.state.stopReason, StopReason.battery);
    });
  });

  group('DT-22-2 charging, hysteresis, jumps', () {
    rigTest('/charging-at-8 does not enter critical', (rig) async {
      await rig.startRecording();
      await rig.emitBattery(8, charging: true);
      expect(rig.state.flags.batteryCritical, isFalse);
      expect(rig.journal.flushIntervals, [kFlushIntervalMs]);
      expect(rig.location.intervalCalls, isEmpty);
    });

    rigTest('/charging at 2 percent does not finish the recording', (rig) async {
      await rig.startRecording();
      await rig.emitBattery(2, charging: true);
      expect(rig.phase, RecorderPhase.recording);
      expect(rig.journal.calls.where((c) => c.startsWith('seal')), isEmpty);
    });

    rigTest('/charging-starts-after-critical exits and restores 1 s and 5 s flush',
        (rig) async {
      await rig.startRecording();
      await rig.emitBattery(9);
      expect(rig.state.flags.batteryCritical, isTrue);
      await rig.emitBattery(9, charging: true);
      expect(rig.state.flags.batteryCritical, isFalse);
      expect(rig.location.intervalCalls, [5, 1]);
      expect(rig.journal.flushIntervals,
          [kFlushIntervalMs, kBatteryCriticalFlushIntervalMs, kFlushIntervalMs]);
      expect(rig.container.read(recorderDisplayProvider).banner, isNull);
    });

    rigTest('/exit-at-12 but not at 11', (rig) async {
      await rig.startRecording();
      await rig.emitBattery(9);
      await rig.emitBattery(11);
      expect(rig.state.flags.batteryCritical, isTrue, reason: '11 stays');
      await rig.emitBattery(12);
      expect(rig.state.flags.batteryCritical, isFalse);
      expect(rig.location.intervalCalls, [5, 1]);
    });

    rigTest('/oscillate-and-repeat-equal 9,10,11,12,10,10,10 enters twice, '
        'no chatter', (rig) async {
      await rig.startRecording();
      for (final p in [9, 10, 11, 12, 10, 10, 10]) {
        await rig.emitBattery(p);
      }
      expect(rig.state.flags.batteryCritical, isTrue);
      expect(
          rig.journal.events
              .where((e) => e.kind == JournalEventKind.batteryCritical)
              .length,
          2,
          reason: 'one event per entry, none for repeated equal values');
      expect(rig.location.intervalCalls, [5, 1, 5]);
      expect(rig.journal.flushIntervals, [
        kFlushIntervalMs,
        kBatteryCriticalFlushIntervalMs,
        kFlushIntervalMs,
        kBatteryCriticalFlushIntervalMs,
      ]);
    });

    rigTest('repeated 9 percent while critical writes nothing more', (rig) async {
      await rig.startRecording();
      for (var i = 0; i < 5; i++) {
        await rig.emitBattery(9);
      }
      expect(
          rig.journal.events
              .where((e) => e.kind == JournalEventKind.batteryCritical)
              .length,
          1);
      expect(rig.location.intervalCalls, [5]);
    });

    rigTest('/jump-15-to-2 still finishes and saves', (rig) async {
      await rig.startRecording();
      await rig.emitBattery(15);
      expect(rig.state.flags.batteryCritical, isFalse);
      await rig.emitBattery(2);
      expect(rig.phase, RecorderPhase.finished);
      expect(rig.state.stopReason, StopReason.battery);
      expect(rig.journal.calls, containsAllInOrder(['seal:battery', 'handOff']));
    });

    rigTest('a reading while idle changes nothing', (rig) async {
      await rig.emitBattery(2);
      expect(rig.phase, RecorderPhase.idle);
      expect(rig.state.flags.batteryCritical, isFalse);
      expect(rig.journal.calls, isEmpty);
    });
  });

  group('DT-22-4 reason stored, save failure keeps the journal', () {
    rigTest('/reason-visible-and-stored: stop event, seal request and state '
        'agree', (rig) async {
      await rig.startRecording();
      await rig.emitBattery(3);
      expect(rig.state.stopReason, StopReason.battery);
      expect(rig.journal.lastSeal?.reason, StopReason.battery);
      expect(rig.journal.eventKinds, contains('stoppedBattery'));
      expect(journalStopEventFor(StopReason.battery),
          JournalEventKind.stoppedBattery);
      expect(rig.state.autoStopNotice?.movingTimeMs, isNonNegative);
      expect(rig.state.autoStopNotice?.distanceM, isNonNegative);
    });

    rigTest('/save-fails-at-3-percent: hand-off failed keeps the recording, '
        'reason shown', (rig) async {
      rig.journal.handOffResult = HandOffResult.failedKept;
      await rig.startRecording();
      await rig.emitBattery(3);
      expect(rig.phase, RecorderPhase.idle);
      expect(rig.state.handOffFailed, isTrue);
      expect(rig.state.stopReason, StopReason.battery);
      expect(rig.journal.calls.contains('decideDelete'), isFalse,
          reason: 'a failed save never deletes the journal');
      expect(rig.location.activeSubscriptions, 0);
    });

    rigTest('/seal throws at 3 percent: nothing deleted, kept, reason shown',
        (rig) async {
      rig.journal.sealError = StateError('disk full');
      await rig.startRecording();
      await rig.emitBattery(3);
      expect(rig.phase, RecorderPhase.idle);
      expect(rig.state.handOffFailed, isTrue);
      expect(rig.state.stopReason, StopReason.battery);
      expect(rig.journal.calls.contains('decideDelete'), isFalse);
      expect(rig.journal.calls.contains('handOff'), isFalse);
    });

    rigTest('3 percent while acquiring with nothing recorded drops the empty '
        'run, reason battery stays visible', (rig) async {
      await rig.start();
      expect(rig.phase, RecorderPhase.acquiring);
      await rig.emitBattery(3);
      expect(rig.phase, RecorderPhase.idle);
      expect(rig.state.stopReason, StopReason.battery);
      expect(rig.journal.calls.contains('seal:battery'), isFalse);
      expect(rig.location.activeSubscriptions, 0);
    });
  });

  group('DT-22-6 battery source failures never kill the recording', () {
    rigTest('/monitor-throws: current() throws and the stream errors; '
        'recording continues', (rig) async {
      await rig.startRecording();
      expect(rig.phase, RecorderPhase.recording);
      expect(rig.state.flags.batteryCritical, isFalse);
      await rig.advance(const Duration(seconds: 5));
      expect(rig.location.activeSubscriptions, 1);
      expect(rig.t.takeException(), isNull);
    }, extra: [
      batteryMonitorProvider.overrideWithValue(ThrowingBattery()),
    ]);

    rigTest('/monitor-unavailable: null reading and silent stream', (rig) async {
      await rig.startRecording();
      await rig.advance(const Duration(seconds: 30));
      expect(rig.phase, RecorderPhase.recording);
      expect(rig.state.flags.batteryCritical, isFalse);
      expect(rig.journal.calls.contains('event:batteryCritical'), isFalse);
    });

    rigTest('/start primes the battery: a current() of 9 percent is critical '
        'at once', (rig) async {
      rig.battery.emit(9);
      await rig.start();
      expect(rig.phase, RecorderPhase.acquiring);
      expect(rig.state.flags.batteryCritical, isTrue);
      expect(rig.location.intervalCalls, [5]);
    });

    rigTest('/start primes the battery: current() of 3 percent unplugged ends '
        'the empty run', (rig) async {
      rig.battery.emit(3);
      await rig.start();
      expect(rig.phase, RecorderPhase.idle);
      expect(rig.state.stopReason, StopReason.battery);
    });
  });

  group('DT-22-7 request interval across a 600 s replay', () {
    rigTest('1 s outside the critical window, 5 s inside; request count equals '
        'the sum', (rig) async {
      await rig.start();
      await rig.fix();
      var delivered = 1;
      var interval = 1; // seconds, as the source was started with
      expect(rig.location.startRequests.single.intervalSeconds, 1);
      for (var t = 0; t < 600;) {
        if (t == 200) {
          await rig.emitBattery(9);
          interval = rig.location.intervalCalls.last;
          expect(interval, 5);
        }
        if (t == 400) {
          await rig.emitBattery(12);
          interval = rig.location.intervalCalls.last;
          expect(interval, 1);
        }
        await rig.advance(Duration(seconds: interval));
        t += interval;
        await rig.fix();
        delivered++;
      }
      expect(delivered, 1 + 200 + 40 + 200,
          reason: 'first fix + 200 s at 1 s + 40 fixes at 5 s + 200 s at 1 s');
      expect(rig.location.intervalCalls, [5, 1]);
      expect(rig.phase, RecorderPhase.recording,
          reason: 'a 5 s cadence must not trigger a gap or auto-pause');
      expect(rig.journal.samples.length, delivered,
          reason: 'every delivered fix was kept and journaled');
    });
  });

  group('DT-22-8 and DT-36-5 critical while paused or acquiring', () {
    rigTest('acquiring: banner state shown, 5 s requests', (rig) async {
      await rig.start();
      await rig.emitBattery(9);
      expect(rig.phase, RecorderPhase.acquiring);
      expect(rig.state.flags.batteryCritical, isTrue);
      expect(rig.container.read(recorderDisplayProvider).banner,
          RecorderBanner.batteryCritical);
      expect(rig.location.intervalCalls, [5]);
    });

    rigTest('manual pause: the 10 s pause rate wins; resume applies 5 s while '
        'critical', (rig) async {
      await rig.startRecording();
      rig.controller.pause();
      await rig.flush();
      expect(rig.phase, RecorderPhase.pausedManual);
      expect(rig.location.intervalCalls.last, 10);
      await rig.emitBattery(9);
      expect(rig.state.flags.batteryCritical, isTrue);
      expect(rig.location.intervalCalls.last, 10,
          reason: 'critical while manually paused keeps 10 s');
      expect(rig.container.read(recorderDisplayProvider).banner,
          RecorderBanner.batteryCritical);
      rig.controller.resume();
      await rig.flush();
      expect(rig.location.intervalCalls.last, 5);
      await rig.emitBattery(13);
      expect(rig.location.intervalCalls.last, 1);
    });

    rigTest('3 percent while manually paused finishes and saves', (rig) async {
      await rig.startRecording();
      rig.controller.pause();
      await rig.flush();
      await rig.emitBattery(3);
      expect(rig.phase, RecorderPhase.finished);
      expect(rig.state.stopReason, StopReason.battery);
    });
  });
}
