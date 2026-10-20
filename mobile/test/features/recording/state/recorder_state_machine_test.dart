// S04-03 Recorder state machine (R-004, R-013): rows DT-03-1 .. DT-03-13.
import 'dart:async';
import 'dart:io';

import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/recording/state/recorder_display.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart';
import 'package:fitness_app/features/recording/state/recorder_state.dart';
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recording/recorder_world.dart';

const _thirteen = <String>[
  'idle',
  'acquiring',
  'recording',
  'poorAccuracy',
  'offline',
  'pausedManual',
  'pausedAuto',
  'background',
  'restoring',
  'recoveryFailed',
  'batteryCritical',
  'permissionRevoked',
  'finished',
];

/// An independent oracle for the headline channel (Contract 5.3 order).
RecorderDisplayState _headline(RecorderPhase p, bool poor) {
  switch (p) {
    case RecorderPhase.permissionRevoked:
      return RecorderDisplayState.permissionRevoked;
    case RecorderPhase.recoveryFailed:
      return RecorderDisplayState.recoveryFailed;
    case RecorderPhase.restoring:
      return RecorderDisplayState.restoring;
    case RecorderPhase.pausedManual:
      return RecorderDisplayState.pausedManual;
    case RecorderPhase.pausedAuto:
      return RecorderDisplayState.pausedAuto;
    case RecorderPhase.acquiring:
      return RecorderDisplayState.acquiring;
    case RecorderPhase.recording:
      return poor
          ? RecorderDisplayState.poorAccuracy
          : RecorderDisplayState.recording;
    case RecorderPhase.stopping:
      return RecorderDisplayState.recording;
    case RecorderPhase.finished:
      return RecorderDisplayState.finished;
    case RecorderPhase.idle:
    case RecorderPhase.preparing:
      return RecorderDisplayState.idle;
  }
}

Iterable<RecorderFlags> _allFlags() sync* {
  for (var m = 0; m < 32; m++) {
    yield RecorderFlags(
      poorAccuracy: m & 1 != 0,
      offline: m & 2 != 0,
      background: m & 4 != 0,
      batteryCritical: m & 8 != 0,
      storageWriteFailing: m & 16 != 0,
    );
  }
}

void main() {
  group('DT-03-1 legal transitions', () {
    test('every legal transition is accepted and yields exactly the table target',
        () {
      var checked = 0;
      for (final e in kLegalTransitions.entries) {
        for (final to in e.value) {
          expect(isLegalTransition(e.key, to), isTrue,
              reason: '${e.key} -> $to must be legal');
          checked++;
        }
      }
      // The Design 5.2 table has exactly this many arrows; a silent addition
      // or removal changes the count.
      expect(checked, 32);
      expect(kLegalTransitions.keys.toSet(), RecorderPhase.values.toSet(),
          reason: 'every phase has a row');
    });

    test('live flows only ever take legal transitions', () async {
        final w = RecorderWorld.create();
        await w.start();
        expect(w.phase, RecorderPhase.acquiring);
        await w.walk(3);
        expect(w.phase, RecorderPhase.recording);
        await w.pause();
        expect(w.phase, RecorderPhase.pausedManual);
        await w.resume();
        await w.stop();
        await w.advance(const Duration(seconds: 1));
        expect(w.phase, RecorderPhase.finished);
        await w.acknowledge();
        expect(w.phase, RecorderPhase.idle);
        final trail = w.phaseTrail;
        expect(trail, [
          RecorderPhase.idle,
          RecorderPhase.preparing,
          RecorderPhase.acquiring,
          RecorderPhase.recording,
          RecorderPhase.pausedManual,
          RecorderPhase.recording,
          RecorderPhase.stopping,
          RecorderPhase.finished,
          RecorderPhase.idle,
        ]);
        for (var i = 1; i < trail.length; i++) {
          expect(isLegalTransition(trail[i - 1], trail[i]), isTrue,
              reason: '${trail[i - 1]} -> ${trail[i]}');
        }
        await w.dispose();
    });
  });

  group('DT-03-2 illegal transitions', () {
    test('every ordered pair not in the table is rejected', () {
      var illegal = 0;
      for (final from in RecorderPhase.values) {
        for (final to in RecorderPhase.values) {
          final inTable = kLegalTransitions[from]!.contains(to);
          expect(isLegalTransition(from, to), inTable);
          if (!inTable) illegal++;
        }
      }
      expect(illegal, 121 - 32);
    });

    test('no phase may transition to itself and finished only goes to idle', () {
      for (final p in RecorderPhase.values) {
        expect(isLegalTransition(p, p), isFalse);
      }
      expect(kLegalTransitions[RecorderPhase.finished], {RecorderPhase.idle});
    });

    test('rejected calls leave the state and every counter unchanged', () async {
        final w = RecorderWorld.create();
        // idle: pause / resume / stop / discard are ignored.
        final before = w.state;
        await w.pause();
        await w.resume();
        await w.stop();
        await w.discard();
        await w.acknowledge();
        await w.settle();
        expect(identical(w.state, before), isTrue);
        expect(w.location.startCount, 0);
        expect(w.location.stopCount, 0);
        expect(w.journal.calls, isEmpty);
        await w.dispose();
    });
  });

  group('DT-03-3 display states', () {
    test('the display enum lists the 13 contract names in order', () {
      expect(RecorderDisplayState.values.map((e) => e.name).toList(),
          _thirteen);
    });

    test('headline outputs are exactly the ten primary names; three are '
        'conditions on other channels', () {
      final seen = <RecorderDisplayState>{};
      for (final p in RecorderPhase.values) {
        for (final f in _allFlags()) {
          seen.add(displayOf(RecorderState(phase: p, flags: f)).headline);
        }
      }
      expect(seen.map((e) => e.name).toSet(), {
        'idle',
        'acquiring',
        'recording',
        'poorAccuracy',
        'pausedManual',
        'pausedAuto',
        'restoring',
        'recoveryFailed',
        'permissionRevoked',
        'finished',
      });
      // offline, background and batteryCritical never become a headline.
      for (final n in ['offline', 'background', 'batteryCritical']) {
        expect(seen.map((e) => e.name), isNot(contains(n)));
      }
    });
  });

  group('DT-03-4 contract list vs code', () {
    test('the Contract section "The 13 states" equals the code list', () {
      final f = File('../docs/phase2/s04/S04D_UI_DESIGN_CONTRACT.md');
      expect(f.existsSync(), isTrue, reason: 'contract must be readable');
      final lines = f.readAsLinesSync();
      final h = lines.indexWhere((l) => l.contains('The 13 states'));
      expect(h, greaterThanOrEqualTo(0), reason: 'heading must exist');
      // First non-empty line after the heading holds the backticked list.
      var i = h + 1;
      while (lines[i].trim().isEmpty) {
        i++;
      }
      final names = RegExp(r'`([A-Za-z]+)`')
          .allMatches(lines[i])
          .map((m) => m.group(1)!)
          .toList();
      expect(names, _thirteen);
      expect(RecorderDisplayState.values.map((e) => e.name).toList(), names);
    });
  });

  group('DT-03-5 / DT-03-13 priority channels over every cell', () {
    test('headline, banner and chips follow the priority order for every '
        'phase and flag combination', () {
      for (final p in RecorderPhase.values) {
        for (final f in _allFlags()) {
          final d = displayOf(RecorderState(phase: p, flags: f));
          final tag = '$p $f';
          // Headline channel.
          expect(d.headline, _headline(p, f.poorAccuracy && p == RecorderPhase.recording),
              reason: tag);
          // Banner channel: storage first, then battery (collecting phases).
          final wantBanner = f.storageWriteFailing
              ? RecorderBanner.storageWriteFailing
              : (f.batteryCritical && p.isCollecting
                  ? RecorderBanner.batteryCritical
                  : null);
          expect(d.banner, wantBanner, reason: tag);
          // Chips channel: offline then background, at most two.
          expect(d.chips, [
            if (f.offline) RecorderChip.offline,
            if (f.background) RecorderChip.background,
          ], reason: tag);
          expect(d.chips.length, lessThanOrEqualTo(2));
          expect(d.busy, p == RecorderPhase.preparing || p == RecorderPhase.stopping,
              reason: tag);
        }
      }
    });

    test('battery plus poor accuracy: headline weak signal, banner battery', () {
      final d = displayOf(const RecorderState(
          phase: RecorderPhase.recording,
          flags: RecorderFlags(poorAccuracy: true, batteryCritical: true)));
      expect(d.headline, RecorderDisplayState.poorAccuracy);
      expect(d.banner, RecorderBanner.batteryCritical);
    });

    test('paused manual plus offline plus battery keeps all three facts', () {
      final d = displayOf(const RecorderState(
          phase: RecorderPhase.pausedManual,
          flags: RecorderFlags(offline: true, batteryCritical: true)));
      expect(d.headline, RecorderDisplayState.pausedManual);
      expect(d.banner, RecorderBanner.batteryCritical);
      expect(d.chips, [RecorderChip.offline]);
    });

    test('a higher-priority headline is never hidden by a lower one', () {
      final d = displayOf(const RecorderState(
          phase: RecorderPhase.permissionRevoked,
          flags: RecorderFlags(
              poorAccuracy: true, batteryCritical: true, offline: true)));
      expect(d.headline, RecorderDisplayState.permissionRevoked);
      // battery banner only while collecting: permissionRevoked is not.
      expect(d.banner, isNull);
    });
  });

  group('DT-03-6 manual pause wins over the auto rule', () {
    test('auto triggers while pausedManual do not change the phase; Resume '
        'returns to recording', () async {
        final w = RecorderWorld.create();
        await w.start();
        final x = await await w.walk(5);
        expect(w.phase, RecorderPhase.recording);
        await w.pause();
        expect(w.phase, RecorderPhase.pausedManual);
        // Fixes that would trigger both auto rules (slow for >8 s, fast >3 s).
        for (var i = 0; i < 12; i++) {
          await w.advance(const Duration(seconds: 1));
          await w.emitNow(x, speed: 0.1);
        }
        expect(w.phase, RecorderPhase.pausedManual);
        for (var i = 0; i < 6; i++) {
          await w.advance(const Duration(seconds: 1));
          await w.emitNow(x + 2.0 * i, speed: 2.0);
        }
        expect(w.phase, RecorderPhase.pausedManual);
        expect(w.journal.eventKinds,
            isNot(contains(JournalEventKind.autoPause)));
        expect(w.journal.eventKinds,
            isNot(contains(JournalEventKind.autoResume)));
        await w.resume();
        expect(w.phase, RecorderPhase.recording);
        await w.dispose();
    });

    test('pausedAuto -> pausedManual is legal and the controller takes it', () async {
        final w = RecorderWorld.create();
        await w.start(sport: SportType.walking);
        var x = await w.walk(4);
        // Standing still for 10 s (provider speed 0) enters pausedAuto.
        for (var i = 0; i < 10; i++) {
          await w.advance(const Duration(seconds: 1));
          await w.emitNow(x, speed: 0.0);
        }
        expect(w.phase, RecorderPhase.pausedAuto);
        await w.pause();
        expect(w.phase, RecorderPhase.pausedManual);
        expect(isLegalTransition(RecorderPhase.pausedAuto,
            RecorderPhase.pausedManual), isTrue);
        expect(isLegalTransition(RecorderPhase.pausedManual,
            RecorderPhase.pausedAuto), isFalse);
        x += 0; // position unchanged
        await w.dispose();
    });
  });

  group('DT-03-7 manual pause keeps the subscription', () {
    test('120 s of pause: subscription 1, not stopped, no fix journaled, '
        'pause and resume events journaled with offsets', () async {
        final w = RecorderWorld.create();
        await w.start();
        final x = await await w.walk(10);
        final samplesBefore = w.journal.samples.length;
        await w.pause();
        final pausedOff = w.nowMs - w.startMs;
        for (var i = 0; i < 120; i++) {
          await w.advance(const Duration(seconds: 1));
          await w.emitNow(x, speed: 0.0);
        }
        expect(w.location.activeSubscriptions, 1);
        expect(w.location.stopCount, 0);
        expect(w.journal.samples.length, samplesBefore,
            reason: 'no fix is journaled during the manual pause');
        expect(w.location.intervalCalls, contains(10),
            reason: 'reduced interval of 10 s while paused');
        await w.resume();
        final resumedOff = w.nowMs - w.startMs;
        final pause = w.journal.events
            .singleWhere((e) => e.kind == JournalEventKind.pause);
        final resume = w.journal.events
            .singleWhere((e) => e.kind == JournalEventKind.resume);
        expect(pause.offsetMs, pausedOff);
        expect(resume.offsetMs, resumedOff);
        expect(resume.offsetMs - pause.offsetMs, greaterThanOrEqualTo(120000));
        expect(w.location.intervalCalls.last, 1,
            reason: 'interval returns to normal at resume');
        expect(w.location.activeSubscriptions, 1);
        await w.dispose();
    });

    test('the 30 minute prompt becomes due after 30 minutes of manual pause',
        () async {
        final w = RecorderWorld.create();
        await w.start();
        await w.walk(3);
        await w.pause();
        await w.advance(const Duration(minutes: 29));
        expect(w.state.pausePromptDue, isFalse);
        await w.advance(const Duration(minutes: 1, seconds: 2));
        expect(w.state.pausePromptDue, isTrue);
        await w.resume();
        expect(w.state.pausePromptDue, isFalse);
        await w.dispose();
    });
  });

  group('DT-03-8 repeated and equal events', () {
    test('Pause while paused, Resume while recording, Stop twice, Start while '
        'recording are idempotent', () async {
        final w = RecorderWorld.create();
        await w.start();
        await w.walk(4);
        await w.resume(); // resume while recording: ignored
        await w.settle();
        expect(w.journal.eventKinds, isNot(contains(JournalEventKind.resume)));
        await w.pause();
        await w.pause(); // second pause while pausedManual
        await w.settle();
        expect(
            w.journal.eventKinds
                .where((k) => k == JournalEventKind.pause)
                .length,
            1,
            reason: 'never a second pause frame');
        await w.resume();
        await w.resume();
        expect(
            w.journal.eventKinds
                .where((k) => k == JournalEventKind.resume)
                .length,
            1);
        // Start while recording: ignored, no second service start.
        final starts = w.location.startCount;
        await w.start();
        expect(w.location.startCount, starts);
        expect(w.journal.begun.length, 1);
        // Stop twice.
        await w.stop();
        await w.stop();
        await w.advance(const Duration(seconds: 1));
        expect(w.journal.seals.length, 1);
        expect(w.journal.handOffCount, 1);
        expect(w.location.stopCount, 1);
        // Start while finished is also ignored.
        await w.start();
        expect(w.journal.begun.length, 1);
        await w.dispose();
    });

    test('Start twice quickly in idle starts the service once', () async {
        final w = RecorderWorld.create();
        await w.run(() {
          unawaited(w.controller.requestStart(sport: SportType.walking));
          unawaited(w.controller.requestStart(sport: SportType.walking));
        });
        expect(w.journal.begun.length, 1);
        expect(w.location.startCount, 1);
        await w.dispose();
    });

    test('resumeRecovered twice starts the service once', () async {
        final w = RecorderWorld.create();
        w.journal.unfinished = const [
          UnfinishedRecording(
              recordingId: 'old-1',
              status: UnfinishedStatus.readable,
              startUtcMs: 1,
              sport: SportType.walking,
              lastOffsetMs: 5000,
              sampleCount: 5)
        ];
        w.journal.recovered = RecoveredRecording(
            meta: const RecordingMeta(
                recordingId: 'old-1',
                startUtcMs: 1700000000000 - 60000,
                utcOffsetMinutes: 0,
                sport: SportType.walking,
                autoPauseEnabled: true,
                ownerUid: 'user-1'),
            lastOffsetMs: 5000,
            distanceM: 10,
            movingTimeMs: 5000,
            keptCount: 5);
        await w.run(() => unawaited(w.controller.checkUnfinished()));
        expect(w.phase, RecorderPhase.restoring);
        await w.run(() {
          unawaited(w.controller.resumeRecovered('old-1'));
          unawaited(w.controller.resumeRecovered('old-1'));
        });
        expect(w.phase, RecorderPhase.acquiring);
        expect(w.location.startCount, 1);
        expect(w.state.hasRecoveredData, isTrue);
        await w.dispose();
    });
  });

  group('DT-03-9 flags only where they can occur', () {
    test('flags set while idle do not survive; a new recording starts clean',
        () async {
        final w = RecorderWorld.create();
        // Battery critical arrives while idle: ignored.
        await w.run(() => w.battery.emit(5));
        expect(w.state.flags.batteryCritical, isFalse);
        // Record, hit poor accuracy + battery critical, then discard.
        await w.start();
        await w.walk(3);
        await w.run(() => w.battery.emit(8));
        expect(w.state.flags.batteryCritical, isTrue);
        await w.advance(const Duration(seconds: 12)); // no fix: poor accuracy
        expect(w.state.flags.poorAccuracy, isTrue);
        await w.discard();
        await w.advance(const Duration(seconds: 1));
        expect(w.phase, RecorderPhase.idle);
        expect(w.state.flags.poorAccuracy, isFalse);
        expect(w.state.flags.batteryCritical, isFalse);
        expect(w.state.flags.storageWriteFailing, isFalse);
        expect(w.state.flags.offline, isFalse);
        // The battery is charged again; the old critical reading must not
        // be replayed into the new recording.
        await w.run(() => w.battery.emit(80));
        await w.start();
        expect(w.phase, RecorderPhase.acquiring);
        expect(w.state.flags.poorAccuracy, isFalse);
        expect(w.state.flags.batteryCritical, isFalse);
        await w.dispose();
    });

    test('poorAccuracy exists only while recording: pause clears it and it is '
        'never set while paused', () async {
        final w = RecorderWorld.create();
        await w.start();
        await w.walk(3);
        await w.advance(const Duration(seconds: 12));
        expect(w.state.flags.poorAccuracy, isTrue);
        await w.pause();
        expect(w.state.flags.poorAccuracy, isFalse);
        await w.advance(const Duration(seconds: 30));
        expect(w.state.flags.poorAccuracy, isFalse);
        await w.dispose();
    });
  });

  group('DT-03-10 illegal pause', () {
    test('Pause in acquiring is rejected', () async {
        final w = RecorderWorld.create();
        await w.start();
        expect(w.phase, RecorderPhase.acquiring);
        await w.pause();
        expect(w.phase, RecorderPhase.acquiring);
        expect(w.journal.eventKinds, isEmpty);
        await w.dispose();
    });

    test('table: pausedAuto->pausedManual legal, pausedManual->pausedAuto '
        'illegal, acquiring->pausedManual illegal', () {
      expect(isLegalTransition(RecorderPhase.pausedAuto,
          RecorderPhase.pausedManual), isTrue);
      expect(isLegalTransition(RecorderPhase.pausedManual,
          RecorderPhase.pausedAuto), isFalse);
      expect(isLegalTransition(RecorderPhase.acquiring,
          RecorderPhase.pausedManual), isFalse);
    });
  });

  group('DT-03-11 Contract diagram vs Design table', () {
    test('every arrow of the Contract state diagram has a path in the table '
        'through internal phases only', () {
      final f = File('../docs/phase2/s04/S04D_UI_DESIGN_CONTRACT.md');
      final text = f.readAsStringSync();
      final start = text.indexOf('stateDiagram-v2');
      expect(start, greaterThanOrEqualTo(0));
      final end = text.indexOf('```', start);
      final block = text.substring(start, end);
      final arrows = RegExp(r'^\s*(\w+)\s*-->\s*(\w+)', multiLine: true)
          .allMatches(block)
          .map((m) => (m.group(1)!, m.group(2)!))
          .where((a) => a.$1 != '[*]')
          .toList();
      expect(arrows.length, greaterThan(20), reason: 'diagram was parsed');
      final names = {for (final p in RecorderPhase.values) p.name: p};
      const internal = {RecorderPhase.preparing, RecorderPhase.stopping};
      bool path(RecorderPhase a, RecorderPhase b) {
        if (isLegalTransition(a, b)) return true;
        for (final mid in internal) {
          if (isLegalTransition(a, mid) && path(mid, b)) {
            if (mid == a) continue;
            return true;
          }
        }
        return false;
      }

      for (final a in arrows) {
        final from = names[a.$1];
        final to = names[a.$2];
        expect(from, isNotNull, reason: 'unknown phase ${a.$1}');
        expect(to, isNotNull, reason: 'unknown phase ${a.$2}');
        expect(path(from!, to!), isTrue, reason: '${a.$1} --> ${a.$2}');
      }
    });
  });

  group('DT-03-12 poor accuracy while paused', () {
    test('the headline is never poorAccuracy in pausedManual or pausedAuto',
        () {
      for (final p in [RecorderPhase.pausedManual, RecorderPhase.pausedAuto]) {
        final d = displayOf(RecorderState(
            phase: p, flags: const RecorderFlags(poorAccuracy: true)));
        expect(d.headline, isNot(RecorderDisplayState.poorAccuracy));
        expect(
            d.headline,
            p == RecorderPhase.pausedManual
                ? RecorderDisplayState.pausedManual
                : RecorderDisplayState.pausedAuto);
      }
    });

    test('live: 40 s without fixes while pausedManual never shows poor '
        'accuracy', () async {
        final w = RecorderWorld.create();
        await w.start();
        await w.walk(3);
        await w.pause();
        await w.advance(const Duration(seconds: 40));
        expect(w.state.flags.poorAccuracy, isFalse);
        expect(displayOf(w.state).headline, RecorderDisplayState.pausedManual);
        await w.dispose();
    });
  });

  group('state helpers', () {
    test('phase predicates', () {
      expect(RecorderPhase.acquiring.isCollecting, isTrue);
      expect(RecorderPhase.recording.isCollecting, isTrue);
      expect(RecorderPhase.pausedManual.isCollecting, isTrue);
      expect(RecorderPhase.pausedAuto.isCollecting, isTrue);
      for (final p in [
        RecorderPhase.idle,
        RecorderPhase.preparing,
        RecorderPhase.stopping,
        RecorderPhase.restoring,
        RecorderPhase.recoveryFailed,
        RecorderPhase.finished,
        RecorderPhase.permissionRevoked,
      ]) {
        expect(p.isCollecting, isFalse, reason: '$p');
      }
      expect(RecorderPhase.stopping.isActive, isTrue);
      expect(RecorderPhase.idle.isActive, isFalse);
    });

    test('auto stop reasons: only four post a notification', () {
      expect(
          StopReason.values.where((r) => r.postsAutoStopNotification).toSet(),
          {
            StopReason.battery,
            StopReason.storage,
            StopReason.sampleCap,
            StopReason.consentWithdrawn
          });
      expect(StopReason.user.isAutomatic, isFalse);
      expect(StopReason.account.isAutomatic, isTrue);
    });

    test('claimsRecording is false while the engine is detached', () {
      const s = RecorderState(phase: RecorderPhase.recording);
      expect(s.claimsRecording, isTrue);
      expect(s.copyWith(engineDetached: true).claimsRecording, isFalse);
      expect(const RecorderState(phase: RecorderPhase.idle).claimsRecording,
          isFalse);
    });
  });
}
