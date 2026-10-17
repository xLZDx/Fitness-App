// EP-J S04-33 consent surface (DT-33-1, 33-4, 33-5, 33-6, 33-7). The REAL
// GpsConsentRow on the REAL LocationConsentNotifier over mocked preferences;
// withdrawal during a recording uses the real page and the real recorder.
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/core/config/recording_defaults.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/recording/consent/location_consent.dart';
import 'package:fitness_app/features/recording/consent/location_consent_providers.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart';
import 'package:fitness_app/features/recording/widgets/gps_consent_row.dart';

import '../pages/page_harness.dart';

class RowWorld {
  RowWorld(this.t, this.prefs, this.privacy, this.deletes, this.clock);
  final WidgetTester t;
  final SharedPreferences prefs;
  final List<String> privacy;
  final List<String> deletes;
  final List<int> clock;
  ProviderContainer get c =>
      ProviderScope.containerOf(t.element(find.byType(GpsConsentRow)));
  LocationConsent get stored =>
      LocationConsent.decode(prefs.getString(locationConsentKeyFor('uid-a')));
  /// Awaits [f] while the real async work and the fake clock both advance.
  Future<T> drive<T>(Future<T> f) async {
    var done = false;
    T? out;
    // ignore: unawaited_futures
    f.then((v) {
      out = v;
      done = true;
    });
    for (var i = 0; i < 200 && !done; i++) {
      await t.runAsync(() => Future<void>.delayed(Duration.zero));
      await t.pump(const Duration(milliseconds: 20));
    }
    expect(done, isTrue, reason: 'the future must complete');
    return out as T;
  }

  Future<void> settle([int n = 3]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(() => Future<void>.delayed(Duration.zero));
      await t.pump(const Duration(milliseconds: 20));
    }
  }
}

LocationConsent _consent(ConsentState s, {int ts = 1700000000000}) =>
    LocationConsent(<LocationConsentPurpose, ConsentRecord>{
      LocationConsentPurpose.locationWhileRecording: ConsentRecord(
        purpose: LocationConsentPurpose.locationWhileRecording,
        state: s,
        textVersion: kLocationConsentTextVersion,
        timestampUtcMs: ts,
        grantedAtUtcMs: 1700000000000,
      ),
    });

Future<RowWorld> pumpRow(
  WidgetTester t, {
  ConsentState? state,
  bool links = true,
  Locale locale = const Locale('en'),
}) async {
  t.view.physicalSize = const Size(360, 800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{
    if (state != null)
      locationConsentKeyFor('uid-a'): _consent(state).encode(),
  });
  final prefs = await SharedPreferences.getInstance();
  final privacy = <String>[];
  final deletes = <String>[];
  final clock = <int>[1800000000000];
  await t.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: <Override>[
      authUserProvider.overrideWith((ref) => Stream<AuthUser?>.value(
          const AuthUser(uid: 'uid-a', displayName: 'A'))),
      locationConsentPrefsProvider
          .overrideWithValue(Future<SharedPreferences>.value(prefs)),
      locationConsentClockProvider.overrideWith((ref) {
        return () => DateTime.fromMillisecondsSinceEpoch(clock[0], isUtc: true);
      }),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: GpsConsentRow(
            onOpenPrivacyText: links ? () => privacy.add('open') : null,
            onDeleteData: links ? () => deletes.add('open') : null,
          ),
        ),
      ),
    ),
  ));
  final w = RowWorld(t, prefs, privacy, deletes, clock);
  w.c.listen(authUserProvider, (_, __) {});
  w.c.listen(locationConsentProvider, (_, __) {});
  await w.settle();
  return w;
}

Finder get _toggle => find.byType(Switch).evaluate().isNotEmpty
    ? find.byType(Switch)
    : find.byWidgetPredicate((w) => w.runtimeType.toString() == 'HudToggle');

AppLocalizations _l(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(GpsConsentRow)));

void main() {
  group('DT-33-1 / 33-7 the Settings row S4-11', () {
    testWidgets('/row-shows-state-and-text-version (granted)', (t) async {
      final w = await pumpRow(t, state: ConsentState.granted);
      final l = _l(t);
      expect(find.text(l.gpsConsentTitle), findsOneWidget);
      expect(find.text(l.gpsConsentOn(kLocationConsentTextVersion)),
          findsOneWidget);
      expect(_toggle, findsOneWidget);
      expect(w.stored.recordingState, ConsentState.granted);
    });

    testWidgets('/withdrawn shows the off text and an Allow again switch',
        (t) async {
      await pumpRow(t, state: ConsentState.withdrawn);
      final l = _l(t);
      expect(find.text(l.gpsConsentOff), findsOneWidget);
      expect(_toggle, findsOneWidget);
    });

    testWidgets(
        '/never-consented-shows-gpsConsentNone-no-switch-and-the-links',
        (t) async {
      await pumpRow(t); // no record at all
      final l = _l(t);
      expect(find.text(l.gpsConsentNone), findsOneWidget);
      expect(_toggle, findsNothing, reason: 'no switch before consent');
      expect(find.text(l.gpsConsentLinks), findsOneWidget);
      expect(find.text(l.gpsConsentDeleteData), findsOneWidget);
    });

    testWidgets('the links are hidden when their callbacks are null',
        (t) async {
      await pumpRow(t, state: ConsentState.granted, links: false);
      final l = _l(t);
      expect(find.text(l.gpsConsentLinks), findsNothing);
      expect(find.text(l.gpsConsentDeleteData), findsNothing);
    });

    testWidgets('the links call their callbacks', (t) async {
      final w = await pumpRow(t, state: ConsentState.granted);
      final l = _l(t);
      await t.tap(find.text(l.gpsConsentLinks));
      await w.settle(1);
      await t.tap(find.text(l.gpsConsentDeleteData));
      await w.settle(1);
      expect(w.privacy, <String>['open']);
      expect(w.deletes, <String>['open']);
    });

    testWidgets(
        '/withdraw-opens-an-inline-confirmation-no-dialog-route; Keep cancels',
        (t) async {
      final w = await pumpRow(t, state: ConsentState.granted);
      final l = _l(t);
      expect(find.text(l.gpsConsentWithdrawConfirm), findsNothing);
      await t.tap(_toggle);
      await w.settle(1);
      expect(find.text(l.gpsConsentWithdrawConfirm), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      // Nothing is written by opening the confirmation.
      expect(w.stored.recordingState, ConsentState.granted);
      await t.tap(find.text(l.gpsKeep));
      await w.settle(1);
      expect(find.text(l.gpsConsentWithdrawConfirm), findsNothing);
      expect(w.stored.recordingState, ConsentState.granted);
    });

    testWidgets(
        '/withdraw confirmed records the new state and timestamp; no data deleted (DT-33-5)',
        (t) async {
      final w = await pumpRow(t, state: ConsentState.granted);
      final l = _l(t);
      await t.tap(_toggle);
      await w.settle(1);
      await t.tap(find.text(l.gpsConsentWithdraw).last);
      await w.settle(4);
      final rec = w.stored
          .recordOf(LocationConsentPurpose.locationWhileRecording)!;
      expect(rec.state, ConsentState.withdrawn);
      expect(rec.timestampUtcMs, 1800000000000);
      // The earlier grant time and the text version are kept: nothing deleted.
      expect(rec.grantedAtUtcMs, 1700000000000);
      expect(rec.textVersion, kLocationConsentTextVersion);
      expect(find.text(l.gpsConsentOff), findsWidgets);
      expect(find.text(l.gpsConsentWithdrawConfirm), findsNothing);
    });

    testWidgets('/allow-again-records-a-new-version', (t) async {
      final w = await pumpRow(t, state: ConsentState.withdrawn);
      final l = _l(t);
      w.clock[0] = 1900000000000;
      await t.tap(_toggle);
      await w.settle(4);
      final rec = w.stored
          .recordOf(LocationConsentPurpose.locationWhileRecording)!;
      expect(rec.state, ConsentState.granted);
      expect(rec.timestampUtcMs, 1900000000000);
      expect(rec.textVersion, kLocationConsentTextVersion);
      expect(find.text(l.gpsConsentOn(kLocationConsentTextVersion)),
          findsOneWidget);
    });

    testWidgets('row text renders in ru without overflow', (t) async {
      await pumpRow(t, state: ConsentState.granted, locale: const Locale('ru'));
      expect(t.takeException(), isNull);
      expect(find.byType(GpsConsentRow), findsOneWidget);
    });
  });

  group('DT-33-6 idempotent and ordered writes', () {
    testWidgets('/withdraw twice in a row: still withdrawn, state is stable',
        (t) async {
      final w = await pumpRow(t, state: ConsentState.granted);
      final n = w.c.read(locationConsentProvider.notifier);
      var ok = <bool>[];
      n.withdraw().then(ok.add);
      await w.settle(4);
      expect(ok, <bool>[true]);
      final first = w.stored.recordOf(LocationConsentPurpose.locationWhileRecording)!;
      ok = <bool>[];
      n.withdraw().then(ok.add);
      await w.settle(4);
      expect(ok, <bool>[true]);
      final second = w.stored.recordOf(LocationConsentPurpose.locationWhileRecording)!;
      expect(first.state, ConsentState.withdrawn);
      expect(second.state, ConsentState.withdrawn);
      expect(second.grantedAtUtcMs, first.grantedAtUtcMs,
          reason: 'the original grant time survives repeated withdrawals');
      expect(w.c.read(locationConsentGrantedProvider), isFalse);
    });

    testWidgets('/withdrawn then granted: the last write wins and is persisted',
        (t) async {
      final w = await pumpRow(t, state: ConsentState.granted);
      final n = w.c.read(locationConsentProvider.notifier);
      // Fired without awaiting in between: the queue orders them.
      final a = n.withdraw();
      final b = n.grant();
      await w.settle(5);
      expect(await a, isA<bool>());
      expect(await b, isA<bool>());
      expect(w.stored.recordingState, ConsentState.granted);
      expect(w.c.read(locationConsentGrantedProvider), isTrue);
    });

    testWidgets('/granted then withdrawn queued: ends withdrawn', (t) async {
      final w = await pumpRow(t, state: ConsentState.withdrawn);
      final n = w.c.read(locationConsentProvider.notifier);
      final a = n.grant();
      final b = n.withdraw();
      await w.settle(5);
      expect(await a, isA<bool>());
      expect(await b, isA<bool>());
      expect(w.stored.recordingState, ConsentState.withdrawn);
      expect(w.c.read(locationConsentGrantedProvider), isFalse);
    });
  });

  group('DT-33-4 / 33-5 withdrawal during a recording (real page, real recorder)',
      () {
    Future<void> doWithdraw(PageWorld w) async {
      final n = w.c.read(locationConsentProvider.notifier);
      final f = n.withdraw();
      await w.settle(6);
      await f;
    }

    testWidgets('/withdraw-during-a-recording: sealed, kept, reason consent',
        (t) async {
      final w = await pumpPage(t);
      await w.startRecording();
      expect(w.phase, RecorderPhase.recording);
      final before = w.seams.journal.calls.length;
      await doWithdraw(w);
      expect(w.phase.isActive, isFalse, reason: 'collection has stopped');
      expect(w.state.stopReason, StopReason.consentWithdrawn);
      final calls = w.seams.journal.calls.skip(before).toList();
      expect(calls.any((c) => c.startsWith('seal:')), isTrue);
      expect(calls.any((c) => c.startsWith('handOff')), isTrue,
          reason: 'the recording is handed off, i.e. kept');
      expect(w.seams.journal.calls.contains('decideDelete'), isFalse,
          reason: 'nothing is deleted');
      expect(w.seams.location.activeSubscriptions, 0,
          reason: 'no location subscription remains');
      expect(w.c.read(locationConsentGrantedProvider), isFalse);
      // The finished screen names the consent reason.
      final l = AppLocalizations.of(t.element(find.byType(Scaffold).first));
      expect(find.text(l.gpsReasonConsent), findsWidgets);
    });

    testWidgets('/withdraw-while-paused: also sealed and kept', (t) async {
      final w = await pumpPage(t);
      await w.startRecording();
      w.ctl.pause();
      await w.settle(2);
      expect(w.phase, RecorderPhase.pausedManual);
      await doWithdraw(w);
      expect(w.phase.isActive, isFalse);
      expect(w.state.stopReason, StopReason.consentWithdrawn);
      expect(w.seams.journal.calls.any((c) => c.startsWith('seal:')), isTrue);
      expect(w.seams.journal.calls.contains('decideDelete'), isFalse);
      expect(w.seams.location.activeSubscriptions, 0);
    });

    testWidgets('withdrawal when nothing records only changes the consent',
        (t) async {
      final w = await pumpPage(t);
      final before = w.seams.journal.calls.length;
      await doWithdraw(w);
      expect(w.seams.journal.calls.skip(before).where((c) => c.startsWith('seal:')),
          isEmpty);
      expect(w.c.read(locationConsentGrantedProvider), isFalse);
    });

    testWidgets('after the withdrawal Start is refused with zero requests',
        (t) async {
      final w = await pumpPage(t, consent: ConsentState.withdrawn);
      await w.tapStart();
      final l = AppLocalizations.of(t.element(find.byType(Scaffold).first));
      expect(find.text(l.gpsConsentOffTitle), findsOneWidget,
          reason: 'the consentWithdrawn panel');
      expect(w.seams.perms.requestCount, 0);
      expect(w.seams.location.startCount, 0);
    });
  });
}
