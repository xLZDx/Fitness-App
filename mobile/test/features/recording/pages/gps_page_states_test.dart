// EP-G S04-25 the GPS recording page and its 13 display states (DT-25-3 to
// DT-25-15, DT-22-3, DT-22-5, DT-36-3, DT-32-4 page half). The REAL
// GpsRecordingPage runs on the REAL RecorderController with scripted seams.
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/recording/state/recorder_display.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart';
import 'package:fitness_app/features/recording/state/recorder_providers.dart';
import 'package:fitness_app/features/recording/state/recorder_state.dart';
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';
import 'package:fitness_app/features/recording/permissions/location_permission_status.dart';
import 'package:fitness_app/features/recording/widgets/gps_common_widgets.dart';
import 'package:fitness_app/features/recording/widgets/gps_start_flow.dart';

import 'page_harness.dart';
import 'recorder_harness.dart' show readableRecording;

Finder k(String key) => find.byKey(ValueKey<String>(key));
Future<AppLocalizations> en() =>
    AppLocalizations.delegate.load(const Locale('en'));
Future<AppLocalizations> ru() =>
    AppLocalizations.delegate.load(const Locale('ru'));

/// The headline text (the key sits on the Text itself).
String headline(WidgetTester t) =>
    t.widget<Text>(k('gps.rec.headline')).data ?? '';

String textOf(WidgetTester t, String key) {
  final txt = find.descendant(of: k(key), matching: find.byType(Text));
  return t.widgetList<Text>(txt).map((e) => e.data ?? '').join('|');
}

bool buttonEnabled(WidgetTester t, String key) => t
    .widget<GpsButton>(find.descendant(of: k(key), matching: find.byType(GpsButton)))
    .enabled;

void main() {
  group('state 1 idle: the Start screen', () {
    testWidgets('opening performs no permission, location or journal call '
        '(RS-1)', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      expect(k('gps.start.screen'), findsOneWidget);
      expect(find.text(l10n.gpsStartTitle), findsOneWidget);
      expect(find.text(l10n.gpsStartButton), findsOneWidget);
      expect(find.text(l10n.gpsPrivacyLine), findsOneWidget);
      expect(w.seams.perms.totalCalls, 0);
      expect(w.seams.location.startCount, 0);
      expect(w.seams.journal.calls, isEmpty);
      expect(w.phase, RecorderPhase.idle);
      expect(w.spy.popups, isEmpty);
    });

    testWidgets('four sports, auto-pause default follows the sport', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      for (final id in ['walking', 'running', 'hiking', 'cycling']) {
        expect(k('gps.start.sport.$id'), findsOneWidget, reason: id);
      }
      await t.tap(k('gps.start.sport.hiking'));
      await w.settle(1);
      await w.tapStart();
      expect(w.seams.journal.lastMeta?.sport.name, 'hiking');
      expect(w.seams.journal.lastMeta?.autoPauseEnabled, isFalse,
          reason: 'hike: auto-pause off by default');
      expect(find.text(l10n.gpsHeadAcquiring), findsOneWidget);
    });

    testWidgets('Start with a ready phone enters acquiring and the live view',
        (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      await w.tapStart();
      expect(w.phase, RecorderPhase.acquiring);
      expect(k('gps.rec.screen'), findsOneWidget);
      expect(k('gps.start.screen'), findsNothing);
      expect(find.text(l10n.gpsHeadAcquiring), findsOneWidget);
      expect(w.seams.location.startCount, 1);
      expect(w.seams.location.activeSubscriptions, 1);
      expect(w.seams.journal.calls, containsAllInOrder(['listUnfinished', 'begin']));
    });
  });

  group('state 2 acquiring (DT-25-3, DT-25-4)', () {
    testWidgets('/time-and-no-data /pause-disabled', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      await w.tapStart();
      expect(textOf(t, 'gps.rec.time'), '0:00');
      expect(find.text(l10n.gpsNoData), findsWidgets);
      expect(buttonEnabled(t, 'gps.rec.pause'), isFalse);
      expect(find.text(l10n.gpsAcquiringHint), findsOneWidget);
      await w.advance(const Duration(seconds: 20));
      expect(textOf(t, 'gps.rec.time'), '0:00', reason: 'time stays frozen');
    });

    testWidgets('/stop-with-zero-fixes saves nothing and shows '
        'gpsNothingRecorded', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      await w.tapStart();
      await w.tapKey('gps.rec.stop');
      expect(w.phase, RecorderPhase.idle);
      expect(w.seams.journal.calls.where((c) => c.startsWith('seal')), isEmpty);
      expect(w.seams.journal.calls, contains('decideDelete'));
      expect(k('gps.rec.stopPanel'), findsNothing, reason: 'no panel for an empty run');
      expect(find.text(l10n.gpsNothingRecorded), findsOneWidget);
      expect(k('gps.start.screen'), findsOneWidget);
    });

    testWidgets('60 s without a fix: the long hint, the recording is not '
        'cancelled', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      await w.tapStart();
      await w.advance(const Duration(seconds: 59));
      expect(find.text(l10n.gpsAcquiringHint), findsOneWidget);
      await w.advance(const Duration(seconds: 2));
      expect(find.text(l10n.gpsAcquiringLong), findsOneWidget);
      expect(w.phase, RecorderPhase.acquiring);
      expect(w.seams.location.activeSubscriptions, 1);
    });
  });

  group('states 3 and 4 recording and poorAccuracy', () {
    testWidgets('recording: headline, live numbers and the pace', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      await w.startRecording();
      for (var i = 0; i < 6; i++) {
        await w.advance(const Duration(seconds: 1));
        await w.fix();
      }
      expect(w.phase, RecorderPhase.recording);
      expect(headline(t), l10n.gpsHeadRecording);
      expect(textOf(t, 'gps.rec.time'), isNot('0:00'));
      expect(find.textContaining(' km'), findsWidgets);
      expect(buttonEnabled(t, 'gps.rec.pause'), isTrue);
      expect(w.messages, contains(l10n.gpsAnnStarted));
      expect(w.messages.where((m) => m == l10n.gpsAnnStarted).length, 1);
    });

    testWidgets('/headline-weak-and-distance-frozen then '
        '/repeat-within-30s-not-announced', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      await w.startRecording();
      await w.advance(const Duration(seconds: 12));
      expect(w.state.flags.poorAccuracy, isTrue);
      expect(headline(t), l10n.gpsHeadWeak);
      expect(find.text(l10n.gpsWeakHint), findsOneWidget);
      // The smoother lag is flushed when the gap opens (the segment end keeps
      // its true length), so the distance is read once the gap is open.
      final before = w.state.totalDistanceM;
      await w.advance(const Duration(seconds: 3));
      expect(w.state.totalDistanceM, before, reason: 'distance frozen in a gap');
      expect(w.messages.where((m) => m == l10n.gpsAnnWeak).length, 1);
      // signal back, lost again inside 30 s: not announced a second time
      await w.fix();
      await w.advance(const Duration(seconds: 1));
      await w.fix();
      expect(w.state.flags.poorAccuracy, isFalse);
      await w.advance(const Duration(seconds: 12));
      expect(w.state.flags.poorAccuracy, isTrue);
      expect(w.messages.where((m) => m == l10n.gpsAnnWeak).length, 1,
          reason: 'repeat within 30 s is suppressed');
    });

    testWidgets('weak for 30 s: the long hint with an Open location settings '
        'link', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      await w.startRecording();
      await w.advance(const Duration(seconds: 11));
      expect(find.text(l10n.gpsWeakHint), findsOneWidget);
      await w.advance(const Duration(seconds: 32));
      expect(find.text(l10n.gpsWeakLongHint), findsOneWidget);
      expect(find.text(l10n.gpsOpenLocationSettings), findsOneWidget);
    });
  });

  group('states 6 and 7 paused (manual and auto)', () {
    testWidgets('manual pause: headline, Resume button, frozen time, hint '
        '(DT-36-3)', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      await w.startRecording();
      await w.tapKey('gps.rec.pause');
      expect(w.phase, RecorderPhase.pausedManual);
      expect(headline(t), l10n.gpsHeadPaused);
      expect(find.text(l10n.gpsResume), findsOneWidget);
      expect(find.text(l10n.gpsPausedHint), findsOneWidget,
          reason: 'the hint says location stays on');
      expect(w.messages, contains(l10n.gpsAnnPaused));
      final frozen = textOf(t, 'gps.rec.time');
      await w.advance(const Duration(seconds: 20));
      expect(textOf(t, 'gps.rec.time'), frozen);
      await w.tapKey('gps.rec.pause');
      expect(w.phase, RecorderPhase.recording);
      expect(find.text(l10n.gpsPause), findsOneWidget);
      expect(w.messages, contains(l10n.gpsAnnResumed));
    });

    testWidgets('/gpsPausedLongBanner-with-one-polite-announcement at 30 '
        'minutes, non-modal, offers Resume or Finish', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      await w.startRecording();
      await w.tapKey('gps.rec.pause');
      await w.advance(const Duration(minutes: 29, seconds: 55));
      expect(find.text(l10n.gpsPausedLongBanner), findsNothing);
      expect(w.state.pausePromptDue, isFalse);
      await w.advance(const Duration(seconds: 10));
      expect(w.state.pausePromptDue, isTrue);
      expect(find.text(l10n.gpsPausedLongBanner), findsOneWidget);
      expect(w.messages.where((m) => m == l10n.gpsAnnPausedLong).length, 1);
      expect(find.text(l10n.gpsResume), findsOneWidget);
      expect(find.text(l10n.gpsStop), findsOneWidget);
      expect(w.phase, RecorderPhase.pausedManual);
      expect(w.spy.popups, isEmpty);
      await w.advance(const Duration(minutes: 5));
      expect(w.messages.where((m) => m == l10n.gpsAnnPausedLong).length, 1,
          reason: 'never repeats');
    });

    testWidgets('auto-paused word, hint, one announcement; Resume forces '
        'recording', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      await w.startRecording();
      for (var i = 0; i < 14; i++) {
        await w.advance(const Duration(seconds: 1));
        w.seams.emitFix(speed: 0);
        await w.settle(1);
      }
      expect(w.phase, RecorderPhase.pausedAuto);
      expect(headline(t), l10n.gpsHeadAutoPaused);
      expect(find.text(l10n.gpsAutoPausedHint), findsOneWidget);
      expect(w.messages.where((m) => m == l10n.gpsAnnAutoPaused).length, 1);
      await w.tapKey('gps.rec.pause');
      expect(w.phase, RecorderPhase.recording,
          reason: 'Resume from auto-pause records again');
    });

    testWidgets('/auto-off-never: with the switch off the screen never shows '
        'the auto-paused word', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      await t.tap(k('gps.start.autoPause'));
      await w.settle(1);
      await w.tapStart();
      expect(w.seams.journal.lastMeta?.autoPauseEnabled, isFalse);
      await w.fix();
      await w.advance(const Duration(seconds: 1));
      await w.fix(speed: 0);
      for (var i = 0; i < 20; i++) {
        await w.advance(const Duration(seconds: 1));
        w.seams.emitFix(speed: 0);
        await w.settle(1);
      }
      expect(w.phase, isNot(RecorderPhase.pausedAuto));
      expect(find.text(l10n.gpsHeadAutoPaused), findsNothing);
    });
  });

  group('states 5 and 8 chips: offline and background', () {
    testWidgets('/chip-only offline: chip, unchanged headline, no error',
        (t) async {
      final l10n = await en();
      final w = await pumpPage(t, forceable: true);
      await w.startRecording();
      (w.ctl as ForceableRecorder)
          .force((s) => s.copyWith(flags: s.flags.copyWith(offline: true)));
      await w.settle(2);
      expect(find.text(l10n.gpsChipOffline), findsOneWidget);
      expect(headline(t), l10n.gpsHeadRecording);
      expect(w.messages, contains(l10n.gpsAnnOffline));
      expect(w.phase, RecorderPhase.recording);
      expect(w.seams.location.activeSubscriptions, 1);
    });

    testWidgets('background chip, return announcement once, chip clears '
        'after 10 s', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      await w.startRecording();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await w.settle(2);
      expect(w.state.flags.background, isTrue);
      expect(w.c.read(recorderDisplayProvider).chips, contains(RecorderChip.background));
      expect(find.text(l10n.gpsChipBackground), findsOneWidget);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await w.settle(2);
      expect(w.state.flags.background, isFalse);
      expect(find.text(l10n.gpsChipBackground), findsOneWidget,
          reason: 'return chip stays 10 s');
      expect(w.messages.where((m) => m == l10n.gpsAnnBackgroundReturn).length, 1);
      await w.advance(const Duration(seconds: 11));
      expect(find.text(l10n.gpsChipBackground), findsNothing);
      expect(w.phase, RecorderPhase.recording, reason: 'recording never paused');
    });
  });

  group('state 11 batteryCritical: banner only (DT-22-3, DT-22-5, DT-25-11)', () {
    testWidgets('/not-a-dialog /not-dismissible /percentage-updates', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      await w.startRecording();
      final pauseBefore = t.getRect(k('gps.rec.pause'));
      final stopBefore = t.getRect(k('gps.rec.stop'));
      w.seams.battery.emit(9);
      await w.settle(3);
      expect(w.state.flags.batteryCritical, isTrue);
      expect(k('gps.rec.banner'), findsOneWidget);
      expect(find.text(l10n.gpsBatteryBanner(9)), findsOneWidget);
      expect(w.spy.popups, isEmpty, reason: 'banner only, no dialog or sheet');
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      // not dismissible: no close control inside the banner
      expect(find.descendant(of: k('gps.rec.banner'), matching: find.byType(IconButton)),
          findsNothing);
      // the banner does not move the controls
      expect(t.getRect(k('gps.rec.pause')), pauseBefore);
      expect(t.getRect(k('gps.rec.stop')), stopBefore);
      // percentage updates once per percent
      w.seams.battery.emit(8);
      await w.settle(2);
      expect(find.text(l10n.gpsBatteryBanner(8)), findsOneWidget);
      expect(find.text(l10n.gpsBatteryBanner(9)), findsNothing);
    });

    testWidgets('/gpsAnnBattery once and assertive', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      await w.startRecording();
      w.seams.battery.emit(9);
      await w.settle(3);
      w.seams.battery.emit(8);
      await w.settle(3);
      final hits = w.announced
          .where((m) => m['message'] == l10n.gpsAnnBattery(9))
          .toList();
      expect(hits.length, 1);
      expect(w.messages.where((m) => m == l10n.gpsAnnBattery(8)), isEmpty,
          reason: 'one announcement per entry, not per percent');
      // assertive: the payload carries the assertiveness (or the fallback text)
      final a = hits.single['assertiveness'];
      expect(a == null || a == 1, isTrue, reason: 'assertive or fallback: $a');
    });

    testWidgets('/gpsAnnBatteryFinish once when the battery finishes the '
        'recording', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      await w.startRecording();
      w.seams.battery.emit(3);
      await w.settle(4);
      expect(w.phase, RecorderPhase.finished);
      expect(w.messages.where((m) => m == l10n.gpsAnnBatteryFinish).length, 1);
    });
  });

  group('stop panel S4-3 (inline, never a dialog)', () {
    testWidgets('Stop opens the inline panel; recording continues; Keep '
        'recording closes it', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      await w.startRecording();
      await w.tapKey('gps.rec.stop');
      expect(k('gps.rec.stopPanel'), findsOneWidget);
      expect(find.text(l10n.gpsStopStillRecording), findsOneWidget);
      expect(w.phase, RecorderPhase.recording, reason: 'still recording');
      expect(w.spy.popups, isEmpty);
      expect(find.byType(Dialog), findsNothing);
      await w.tapText(l10n.gpsKeepRecording);
      expect(k('gps.rec.stopPanel'), findsNothing);
      expect(w.phase, RecorderPhase.recording);
    });

    testWidgets('Finish and save: seal, hand-off, the saved screen', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      await w.startRecording();
      await w.tapKey('gps.rec.stop');
      await w.tapText(l10n.gpsFinishSave);
      expect(w.phase, RecorderPhase.finished);
      expect(w.seams.journal.calls, containsAllInOrder(['seal:user', 'handOff']));
      expect(k('gps.finish.screen'), findsOneWidget);
      expect(find.text(l10n.gpsSavedTitle), findsOneWidget);
    });

    testWidgets('Discard needs a second inline confirmation; Keep goes back; '
        'Delete deletes, announces and leaves', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      await w.startRecording();
      await w.tapKey('gps.rec.stop');
      await w.tapText(l10n.gpsDiscard);
      expect(k('gps.rec.discardConfirm'), findsOneWidget);
      expect(w.seams.journal.calls.contains('decideDelete'), isFalse,
          reason: 'nothing deleted by the first tap');
      await w.tapText(l10n.gpsKeep);
      expect(k('gps.rec.stopPanel'), findsOneWidget);
      await w.tapText(l10n.gpsDiscard);
      await w.tapText(l10n.gpsDelete);
      expect(w.seams.journal.calls, contains('decideDelete'));
      expect(w.phase, RecorderPhase.idle);
      expect(w.messages, contains(l10n.gpsAnnDiscarded));
      expect(w.closed, ['close']);
      expect(w.spy.popups, isEmpty);
    });
  });

  group('state 9 restoring: the recovery offer S4-5', () {
    testWidgets('offer with Resume, Save as finished, Discard and no Export',
        (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      w.seams.journal.unfinished = [readableRecording()];
      await w.ctl.checkUnfinished();
      await w.settle(3);
      expect(w.phase, RecorderPhase.restoring);
      expect(k('gps.recovery.offer'), findsOneWidget);
      expect(find.text(l10n.gpsRecoveryTitle), findsWidgets);
      expect(find.text(l10n.gpsRecoveryResume), findsOneWidget);
      expect(find.text(l10n.gpsRecoverySaveFinished), findsOneWidget);
      expect(find.text(l10n.gpsDiscard), findsOneWidget);
      expect(find.textContaining('Export'), findsNothing);
      expect(find.text(l10n.gpsRecoveryCaveat), findsOneWidget);
      expect(find.text(l10n.gpsResumeGapNote), findsOneWidget);
    });

    testWidgets('Save as finished seals and hands off the recovered data',
        (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      w.seams.journal.unfinished = [readableRecording('old-7')];
      await w.ctl.checkUnfinished();
      await w.settle(3);
      await w.tapText(l10n.gpsRecoverySaveFinished);
      expect(w.seams.journal.calls, containsAllInOrder(['seal:user', 'handOff']));
      expect(w.phase, RecorderPhase.finished);
    });

    testWidgets('Discard is confirmed inline, then durably deleted', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      w.seams.journal.unfinished = [readableRecording()];
      await w.ctl.checkUnfinished();
      await w.settle(3);
      await w.tapText(l10n.gpsDiscard);
      expect(k('gps.rec.discardConfirm'), findsOneWidget);
      expect(w.seams.journal.calls.contains('decideDelete'), isFalse);
      await w.tapText(l10n.gpsDelete);
      expect(w.seams.journal.calls, contains('decideDelete'));
      expect(w.phase, RecorderPhase.idle);
      expect(w.spy.popups, isEmpty);
    });

    testWidgets('Resume reaches acquiring with the recovered numbers and a '
        'marked gap', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      final rec = readableRecording('old-1');
      w.seams.journal
        ..unfinished = [rec]
        ..resumeResult = RecoveredRecording(
          meta: RecordingMeta(
            recordingId: 'old-1',
            startUtcMs: w.seams.env.now - 600000,
            utcOffsetMinutes: 0,
            sport: rec.sport!,
            autoPauseEnabled: true,
            ownerUid: 'uid-a',
          ),
          lastOffsetMs: 540000,
          distanceM: 1500,
          movingTimeMs: 540000,
          keptCount: 100,
        );
      await w.ctl.checkUnfinished();
      await w.settle(3);
      await w.tapText(l10n.gpsRecoveryResume);
      expect(w.phase, RecorderPhase.acquiring);
      expect(w.state.hasRecoveredData, isTrue);
      expect(w.state.totalDistanceM, 1500);
      expect(w.state.totalMovingTimeMs, 540000);
      expect(textOf(t, 'gps.rec.time'), '9:00');
      expect(find.text(l10n.gpsResumeGapNote), findsOneWidget);
      expect(w.seams.location.startCount, 1);
    });

    testWidgets('resumeMode (?mode=resume) shows the Start screen in resume '
        'mode', (t) async {
      final l10n = await en();
      final w = await pumpPage(t, resumeMode: true);
      w.seams.journal.unfinished = [readableRecording()];
      await w.ctl.checkUnfinished();
      await w.settle(3);
      expect(k('gps.start.screen'), findsOneWidget);
      expect(find.text(l10n.gpsResumeModeTitle), findsOneWidget);
      expect(find.text(l10n.gpsRecoveryResume), findsOneWidget);
      expect(k('gps.start.sport.walking'), findsNothing,
          reason: 'resume mode has no sport row');
    });
  });

  group('state 10 recoveryFailed: Keep or Delete, never Export', () {
    testWidgets('panel, assertive announcement, keep quarantines', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      w.seams.journal.unfinished = [
        const UnfinishedRecording(
            recordingId: 'bad-1', status: UnfinishedStatus.unreadable)
      ];
      await w.ctl.checkUnfinished();
      await w.settle(4);
      expect(w.phase, RecorderPhase.recoveryFailed);
      expect(k('gps.recoveryFailed.panel'), findsOneWidget);
      expect(find.text(l10n.gpsRecoveryFailedTitle), findsOneWidget);
      expect(find.textContaining('Export'), findsNothing);
      expect(w.messages.where((m) => m == l10n.gpsAnnRecoveryFailed).length, 1);
      await w.tapText(l10n.gpsKeepFile);
      expect(w.seams.journal.calls, contains('quarantine'));
      expect(w.phase, RecorderPhase.idle);
    });

    testWidgets('Delete file needs a confirmation, then deletes', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      w.seams.journal.unfinished = [
        const UnfinishedRecording(
            recordingId: 'bad-1', status: UnfinishedStatus.unreadable)
      ];
      await w.ctl.checkUnfinished();
      await w.settle(4);
      await w.tapText(l10n.gpsDeleteFile);
      expect(k('gps.recoveryFailed.confirm'), findsOneWidget);
      expect(w.seams.journal.calls.contains('decideDelete'), isFalse);
      await w.tapText(l10n.gpsDelete);
      expect(w.seams.journal.calls, contains('decideDelete'));
      expect(w.phase, RecorderPhase.idle);
    });
  });

  group('state 12 permissionRevoked S4-6', () {
    Future<PageWorld> revoked(WidgetTester t) async {
      final w = await pumpPage(t);
      await w.startRecording();
      w.seams.perms.location = LocationPermissionStatus.denied;
      await w.advance(const Duration(seconds: 3));
      return w;
    }

    testWidgets('the recording is sealed, the panel offers Keep, Delete and '
        'Open settings', (t) async {
      final l10n = await en();
      final w = await revoked(t);
      expect(w.phase, RecorderPhase.permissionRevoked);
      expect(k('gps.revoked.panel'), findsOneWidget);
      expect(find.text(l10n.gpsRevokedTitle), findsOneWidget);
      expect(find.text(l10n.gpsKeep), findsOneWidget);
      expect(find.text(l10n.gpsDelete), findsOneWidget);
      expect(find.text(l10n.gpsOpenSettings), findsOneWidget);
      expect(w.seams.journal.calls, containsAllInOrder(['event:permissionRevoked', 'seal:permissionRevoked']));
      expect(w.seams.location.activeSubscriptions, 0);
      expect(w.state.autoStopNotice, isNull,
          reason: 'its own notification, not the automatic-stop one');
    });

    testWidgets('Open settings is a link: no permission request', (t) async {
      final l10n = await en();
      final w = await revoked(t);
      final requestsBefore = w.seams.perms.requestCount;
      await w.tapText(l10n.gpsOpenSettings);
      expect(w.seams.perms.openSettingsCount, 1);
      expect(w.seams.perms.requestCount, requestsBefore);
    });

    testWidgets('Keep: durable keep, then hand-off', (t) async {
      final l10n = await en();
      final w = await revoked(t);
      await w.tapText(l10n.gpsKeep);
      expect(w.seams.journal.calls, containsAllInOrder(['decideKeep', 'handOff']));
      expect(w.phase, RecorderPhase.finished);
    });

    testWidgets('Delete needs an inline confirmation', (t) async {
      final l10n = await en();
      final w = await revoked(t);
      await w.tapText(l10n.gpsDelete);
      expect(k('gps.rec.discardConfirm'), findsOneWidget);
      expect(w.seams.journal.calls.contains('decideDelete'), isFalse);
      await w.tapText(l10n.gpsDelete);
      expect(w.seams.journal.calls, contains('decideDelete'));
      expect(w.phase, RecorderPhase.idle);
    });
  });

  group('state 13 finished: S4-4', () {
    testWidgets('saved screen, the reason line for an automatic stop, Done '
        'acknowledges', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      await w.startRecording();
      w.seams.battery.emit(3);
      await w.settle(4);
      expect(w.phase, RecorderPhase.finished);
      expect(find.text(l10n.gpsSavedTitle), findsOneWidget);
      expect(find.text(l10n.gpsReasonBattery), findsOneWidget);
      expect(find.text(l10n.gpsSavedOnDevice), findsOneWidget);
      expect(k('gps.finish.summary'), findsOneWidget);
      expect(find.textContaining('Export'), findsNothing);
      await w.tapKey('gps.finish.done');
      expect(w.phase, RecorderPhase.idle);
      expect(w.closed, ['close']);
    });

    testWidgets('a user stop shows no reason line', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      await w.startRecording();
      await w.tapKey('gps.rec.stop');
      await w.tapText(l10n.gpsFinishSave);
      expect(find.text(l10n.gpsReasonBattery), findsNothing);
      expect(find.text(l10n.gpsReasonStorage), findsNothing);
      expect(find.text(l10n.gpsReasonConsent), findsNothing);
    });

    testWidgets('save failed keeps the recording and says so', (t) async {
      final l10n = await en();
      final w = await pumpPage(t);
      w.seams.journal.handOffResult = HandOffResult.failedKept;
      await w.startRecording();
      await w.tapKey('gps.rec.stop');
      await w.tapText(l10n.gpsFinishSave);
      expect(w.phase, RecorderPhase.idle);
      expect(k('gps.saveFailed.screen'), findsOneWidget);
      expect(find.text(l10n.gpsSaveFailed), findsOneWidget);
      expect(w.seams.journal.calls.contains('decideDelete'), isFalse);
    });
  });

  group('layout contract (DT-25-11, DT-25-12, DT-25-13, DT-25-15)', () {
    testWidgets('/geometry Pause and Stop: 72 dp high, 120 dp wide, 16 dp '
        'apart, in the bottom 40 percent', (t) async {
      final w = await pumpPage(t);
      await w.startRecording();
      final pause = t.getRect(k('gps.rec.pause'));
      final stop = t.getRect(k('gps.rec.stop'));
      for (final r in [pause, stop]) {
        expect(r.height, greaterThanOrEqualTo(72));
        expect(r.width, greaterThanOrEqualTo(120));
        expect(r.top, greaterThan(800 * 0.6), reason: 'bottom 40 percent');
      }
      expect(stop.left - pause.right, greaterThanOrEqualTo(16));
    });

    testWidgets('no dialog, sheet or snackbar over every live state', (t) async {
      final w = await pumpPage(t);
      await w.startRecording();
      w.seams.battery.emit(9);
      await w.settle(2);
      await w.tapKey('gps.rec.pause');
      await w.advance(const Duration(minutes: 31));
      await w.tapKey('gps.rec.pause');
      await w.tapKey('gps.rec.stop');
      expect(w.spy.popups, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('no looping animation and no indeterminate progress on the live '
        'screen', (t) async {
      final w = await pumpPage(t);
      await w.startRecording();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      // time passing schedules no frame by itself beyond the 1 s tick: a pump
      // of nothing leaves no transient callbacks behind
      await t.pump(const Duration(milliseconds: 16));
      expect(t.binding.transientCallbackCount, 0,
          reason: 'no AnimationController is running on the live screen');
    });

    for (final loc in ['en', 'ru']) {
      for (final size in [const Size(360, 640), const Size(640, 360)]) {
        testWidgets('/text scale 2.0 at ${size.width.toInt()}x${size.height.toInt()} '
            '$loc: the controls stay visible without scrolling', (t) async {
          final w = await pumpPage(t,
              size: size, textScale: 2.0, locale: Locale(loc));
          await w.startRecording();
          for (final key in ['gps.rec.pause', 'gps.rec.stop']) {
            final r = t.getRect(k(key));
            expect(r.top, greaterThanOrEqualTo(0), reason: '$key top');
            expect(r.bottom, lessThanOrEqualTo(size.height), reason: '$key bottom');
            expect(k(key).hitTestable(), findsOneWidget, reason: key);
          }
          expect(t.takeException(), isNull);
        });
      }
    }
  });

  group('13 display states are one total projection', () {
    test('the enum has exactly the 13 names in the contract order', () {
      expect(RecorderDisplayState.values.map((e) => e.name).toList(), [
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
      ]);
    });

    test('displayOf maps every phase; banner only while collecting', () {
      for (final p in RecorderPhase.values) {
        final d = displayOf(RecorderState(
            phase: p, flags: const RecorderFlags(batteryCritical: true)));
        if (p.isCollecting) {
          expect(d.banner, RecorderBanner.batteryCritical, reason: '$p');
        } else {
          expect(d.banner, isNull, reason: '$p');
        }
        expect(d.chips.length, lessThanOrEqualTo(2));
      }
    });

    test('headline priority: revoked > failed > restoring > paused > '
        'acquiring > weak > recording', () {
      RecorderDisplayState h(RecorderPhase p, {bool poor = false}) => displayOf(
          RecorderState(phase: p, flags: RecorderFlags(poorAccuracy: poor)))
          .headline;
      expect(h(RecorderPhase.permissionRevoked), RecorderDisplayState.permissionRevoked);
      expect(h(RecorderPhase.recoveryFailed), RecorderDisplayState.recoveryFailed);
      expect(h(RecorderPhase.restoring), RecorderDisplayState.restoring);
      expect(h(RecorderPhase.pausedManual), RecorderDisplayState.pausedManual);
      expect(h(RecorderPhase.pausedAuto), RecorderDisplayState.pausedAuto);
      expect(h(RecorderPhase.acquiring), RecorderDisplayState.acquiring);
      expect(h(RecorderPhase.recording, poor: true), RecorderDisplayState.poorAccuracy);
      expect(h(RecorderPhase.recording), RecorderDisplayState.recording);
      expect(h(RecorderPhase.finished), RecorderDisplayState.finished);
      expect(h(RecorderPhase.idle), RecorderDisplayState.idle);
      expect(h(RecorderPhase.preparing), RecorderDisplayState.idle);
    });

    test('storage banner outranks battery; chips offline then background', () {
      final d = displayOf(const RecorderState(
          phase: RecorderPhase.recording,
          flags: RecorderFlags(
              storageWriteFailing: true,
              batteryCritical: true,
              offline: true,
              background: true)));
      expect(d.banner, RecorderBanner.storageWriteFailing);
      expect(d.chips, [RecorderChip.offline, RecorderChip.background]);
    });
  });

  test('gpsEffectivePanel precedence picks consentWithdrawn over everything',
      () {
    const flow = GpsStartFlowState(panel: GpsStartPanelId.consentWithdrawn);
    expect(gpsEffectivePanel(flow, StartPanel.cannotStart),
        GpsStartPanelId.consentWithdrawn);
    expect(gpsEffectivePanel(const GpsStartFlowState(), StartPanel.preparing),
        GpsStartPanelId.preparing);
    expect(gpsEffectivePanel(const GpsStartFlowState(), StartPanel.none),
        GpsStartPanelId.none);
  });
}
