// EP-J Start screen panels on the REAL page, flow and recorder (S04-33, S04-34
// surface half): consentWithdrawn with zero requests, batteryTooLow,
// gymTimerRunning, blockedByJournal, noGps, the permission panels, the
// pre-prompt, one start per tap.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/recording/consent/location_consent.dart';
import 'package:fitness_app/features/recording/consent/location_consent_providers.dart';
import 'package:fitness_app/features/recording/permissions/location_permission_status.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart';
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';
import 'package:fitness_app/features/recording/widgets/gps_start_flow.dart';

import 'page_harness.dart';
import 'recorder_harness.dart';

Finder panel(String id) => find.byKey(ValueKey<String>('gps.start.panel.$id'));
Finder get startButton => find.byKey(const ValueKey<String>('gps.start.button'));

AppLocalizations l(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(Scaffold).first));

void main() {
  group('the Start screen before any tap', () {
    testWidgets('RS-1: opening the screen makes no permission, location or service call',
        (t) async {
      final w = await pumpPage(t);
      expect(startButton, findsOneWidget);
      expect(w.seams.perms.requestCount, 0);
      expect(w.seams.perms.openSettingsCount, 0);
      expect(w.seams.location.startCount, 0);
      expect(w.phase, RecorderPhase.idle);
    });
  });

  group('consentWithdrawn (DT-33-2)', () {
    testWidgets('/start-blocked: zero requests, zero service starts, Add manually',
        (t) async {
      final w = await pumpPage(t, consent: ConsentState.withdrawn);
      await w.tapStart();
      expect(panel('consentWithdrawn'), findsOneWidget);
      expect(w.seams.perms.totalCalls, 0, reason: 'no permission call at all');
      expect(w.seams.location.startCount, 0);
      expect(w.seams.journal.calls, isNot(contains('begin')));
      await w.tapText(l(t).gpsAddManually);
      expect(w.manual, <String>['manual']);
      await w.tapText(l(t).gpsOpenPrivacySettings);
      expect(w.privacy, <String>['privacy']);
    });

    testWidgets('/allow-again-restores-start: the real consent notifier', (t) async {
      final w = await pumpPage(t, consent: ConsentState.withdrawn);
      await w.tapStart();
      expect(panel('consentWithdrawn'), findsOneWidget);
      final f = w.c.read(locationConsentProvider.notifier).grant();
      await w.settle(5);
      await f;
      w.seams.env.consent = true;
      await w.tapStart();
      expect(panel('consentWithdrawn'), findsNothing);
      expect(w.phase, RecorderPhase.acquiring);
    });
  });

  group('device and journal panels', () {
    testWidgets('/batteryTooLow at 3 percent and not charging: no start', (t) async {
      final s = Seams()..battery.emit(3);
      final w = await pumpPage(t, seams: s);
      await w.tapStart();
      expect(panel('batteryTooLow'), findsOneWidget);
      expect(find.text(l(t).gpsBatteryTooLow), findsOneWidget);
      expect(s.location.startCount, 0);
      expect(s.perms.requestCount, 0);
    });

    testWidgets('battery 3 percent but charging does not block', (t) async {
      final s = Seams()..battery.emit(3, charging: true);
      final w = await pumpPage(t, seams: s);
      await w.tapStart();
      expect(panel('batteryTooLow'), findsNothing);
      expect(w.phase, RecorderPhase.acquiring);
    });

    testWidgets('battery 4 percent does not block', (t) async {
      final s = Seams()..battery.emit(4);
      final w = await pumpPage(t, seams: s);
      await w.tapStart();
      expect(panel('batteryTooLow'), findsNothing);
      expect(w.phase, RecorderPhase.acquiring);
    });

    testWidgets('/gymTimerRunning: own gym timer blocks with Add manually',
        (t) async {
      final s = Seams();
      s.env.gymTimer = true;
      final w = await pumpPage(t, seams: s);
      s.env.gymTimer = true; // pumpPage sets owner and consent only
      await w.tapStart();
      expect(panel('gymTimerRunning'), findsOneWidget);
      expect(s.location.startCount, 0);
      await w.tapText(l(t).gpsAddManually);
      expect(w.manual, hasLength(1));
    });

    testWidgets('/blockedByJournal: an unfinished recording blocks Start',
        (t) async {
      final s = Seams();
      s.journal.unfinished = <UnfinishedRecording>[readableRecording()];
      final w = await pumpPage(t, seams: s);
      await w.tapStart();
      expect(panel('blockedByJournal'), findsOneWidget);
      expect(s.location.startCount, 0);
      expect(s.journal.calls, isNot(contains('begin')));
    });

    testWidgets('/noGps: a device without GPS gets noGps and Add manually',
        (t) async {
      final w = await pumpPage(t, extra: <Override>[
        gpsDeviceHasGpsProvider.overrideWithValue(false),
      ]);
      await w.tapStart();
      expect(panel('noGps'), findsOneWidget);
      expect(w.seams.perms.requestCount, 0);
      expect(w.seams.location.startCount, 0);
    });

    testWidgets('/servicesOff: location services off, Open location settings',
        (t) async {
      final w = await pumpPage(t, extra: <Override>[
        gpsLocationServicesEnabledProvider
            .overrideWithValue(() async => false),
      ]);
      await w.tapStart();
      expect(panel('servicesOff'), findsOneWidget);
      expect(w.seams.location.startCount, 0);
      await w.tapText(l(t).gpsOpenLocationSettings);
      expect(w.seams.perms.openSettingsCount, 1);
    });

    testWidgets('/cannotStart when the journal owner is missing', (t) async {
      final s = Seams();
      final w = await pumpPage(t, seams: s);
      s.env.ownerUid = null;
      await w.tapStart();
      expect(panel('cannotStart'), findsOneWidget);
      expect(s.location.startCount, 0);
      // Try again after the journal opens.
      s.env.ownerUid = 'uid-a';
      await w.tapText(l(t).gpsTryAgain);
      expect(panel('cannotStart'), findsNothing);
      expect(w.phase, RecorderPhase.acquiring);
    });
  });

  group('permission panels', () {
    testWidgets('/deniedOnce: the system asked once, Try again asks once more',
        (t) async {
      final s = Seams();
      s.perms.location = LocationPermissionStatus.denied;
      s.perms.locationRequestResult = LocationPermissionStatus.denied;
      final w = await pumpPage(t, seams: s);
      await w.tapStart();
      // Consent is granted, but a request is needed: the pre-prompt first.
      expect(panel('preprompt'), findsOneWidget);
      expect(s.perms.requestCount, 0);
      await w.tapText(l(t).gpsContinue);
      expect(panel('deniedOnce'), findsOneWidget);
      expect(s.perms.locationRequestCount, 1);
      await w.tapText(l(t).gpsTryAgain);
      expect(s.perms.locationRequestCount, 2);
      expect(panel('deniedOnce'), findsOneWidget);
    });

    testWidgets('/deniedForever: no request, Open settings opens settings once',
        (t) async {
      final s = Seams();
      s.perms.location = LocationPermissionStatus.permanentlyDenied;
      final w = await pumpPage(t, seams: s);
      await w.tapStart();
      expect(panel('deniedForever'), findsOneWidget);
      expect(s.perms.requestCount, 0);
      await w.tapText(l(t).gpsOpenSettings);
      expect(s.perms.openSettingsCount, 1);
    });

    testWidgets('/restricted: no Open settings, only Add manually', (t) async {
      final s = Seams();
      s.perms.location = LocationPermissionStatus.restricted;
      final w = await pumpPage(t, seams: s);
      await w.tapStart();
      expect(panel('restricted'), findsOneWidget);
      expect(find.text(l(t).gpsOpenSettings), findsNothing);
      expect(find.text(l(t).gpsAddManually), findsOneWidget);
      expect(s.perms.requestCount, 0);
    });

    testWidgets('/approximateOnly: refused, Open settings', (t) async {
      final s = Seams();
      s.perms.location = LocationPermissionStatus.grantedApproximate;
      final w = await pumpPage(t, seams: s);
      await w.tapStart();
      expect(panel('approximateOnly'), findsOneWidget);
      expect(s.location.startCount, 0);
    });

    testWidgets('/notifOff: asked once, then Allow notifications asks again',
        (t) async {
      final s = Seams();
      s.perms.notification = NotificationPermissionStatus.denied;
      s.perms.notificationRequestResult = NotificationPermissionStatus.denied;
      final w = await pumpPage(t, seams: s);
      await w.tapStart();
      expect(panel('notifOff'), findsOneWidget);
      expect(s.perms.notificationRequestCount, 1);
      expect(s.location.startCount, 0);
      await w.tapText(l(t).gpsAllowNotif);
      expect(s.perms.notificationRequestCount, 2);
    });

    testWidgets('/notifOff permanently denied offers Open settings', (t) async {
      final s = Seams();
      s.perms.notification = NotificationPermissionStatus.permanentlyDenied;
      final w = await pumpPage(t, seams: s);
      await w.tapStart();
      expect(panel('notifOff'), findsOneWidget);
      expect(find.text(l(t).gpsAllowNotif), findsNothing);
      expect(find.text(l(t).gpsOpenSettings), findsOneWidget);
      expect(s.perms.notificationRequestCount, 0);
    });

    testWidgets('/preprompt Not now writes nothing and sends no request',
        (t) async {
      final s = Seams();
      s.perms.location = LocationPermissionStatus.denied;
      final w = await pumpPage(t, seams: s);
      await w.tapStart();
      expect(panel('preprompt'), findsOneWidget);
      await w.tapText(l(t).gpsNotNow);
      expect(panel('preprompt'), findsNothing);
      expect(s.perms.requestCount, 0);
      expect(s.location.startCount, 0);
    });

    testWidgets('/preprompt Continue grants, asks the system and then starts',
        (t) async {
      final s = Seams();
      s.perms.location = LocationPermissionStatus.denied;
      s.perms.locationRequestResult = LocationPermissionStatus.grantedPrecise;
      final w = await pumpPage(t, seams: s);
      await w.tapStart();
      await w.tapText(l(t).gpsContinue);
      expect(s.perms.locationRequestCount, 1);
      expect(w.phase, RecorderPhase.acquiring);
      expect(w.c.read(locationConsentGrantedProvider), isTrue);
    });

    testWidgets('first run (no consent record): Continue records the consent',
        (t) async {
      final s = Seams();
      s.perms.location = LocationPermissionStatus.denied;
      s.perms.locationRequestResult = LocationPermissionStatus.grantedPrecise;
      final w = await pumpPage(t, seams: s, consent: ConsentState.none);
      expect(w.c.read(locationConsentGrantedProvider), isFalse);
      s.env.consent = true; // the environment reads the notifier in production
      await w.tapStart();
      expect(panel('preprompt'), findsOneWidget);
      expect(s.perms.requestCount, 0, reason: 'no request before Continue');
      await w.tapText(l(t).gpsContinue);
      final rec = w.c
          .read(locationConsentProvider)
          .valueOrNull!
          .recordOf(LocationConsentPurpose.locationWhileRecording);
      expect(rec?.state, ConsentState.granted);
    });
  });

  group('one start per tap (DT-34-3 surface)', () {
    testWidgets('/button reads gpsStarting and is disabled; a second tap starts nothing',
        (t) async {
      final s = Seams();
      s.journal.beginGate = Completer<void>();
      final w = await pumpPage(t, seams: s);
      await t.tap(startButton);
      await w.settle(3);
      expect(w.phase, RecorderPhase.preparing);
      expect(find.text(l(t).gpsStarting), findsWidgets);
      await t.tap(startButton, warnIfMissed: false);
      await w.settle(2);
      expect(s.journal.calls.where((c) => c == 'begin'), hasLength(1));
      s.journal.beginGate!.complete();
      await w.settle(4);
      expect(w.phase, RecorderPhase.acquiring);
      expect(s.location.startCount, 1);
    });

    testWidgets('/startFailed panel after the begin timeout, Try again once',
        (t) async {
      final s = Seams();
      s.journal.beginGate = Completer<void>();
      final w = await pumpPage(t, seams: s);
      await t.tap(startButton);
      await w.settle(3);
      await t.pump(const Duration(seconds: 15));
      await w.settle(3);
      expect(panel('startFailed'), findsOneWidget);
      expect(s.location.startCount, 0);
      s.journal.beginGate = null;
      await w.tapText(l(t).gpsTryAgain);
      expect(panel('startFailed'), findsNothing);
      expect(w.phase, RecorderPhase.acquiring);
    });
  });

  group('panel precedence (RS-11)', () {
    test('the table is total over the panel ids that can show', () {
      for (final id in GpsStartPanelId.values) {
        if (id == GpsStartPanelId.none) continue;
        expect(kGpsPanelPrecedence, contains(id), reason: '$id has a rank');
      }
    });
    test('consentWithdrawn outranks everything; startFailed is last', () {
      expect(kGpsPanelPrecedence.first, GpsStartPanelId.consentWithdrawn);
      expect(kGpsPanelPrecedence.last, GpsStartPanelId.startFailed);
    });
  });
}
