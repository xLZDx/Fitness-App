// C16 functional tests: the photo privacy / retention view (PRIV-08, PRIV-09,
// design s9, s17, D-62, D-77). Cloud sections only with BODY_SCAN_CLOUD; each
// bulk action calls the right port once and only after confirmation; the copy
// says photos are deleted within 48 hours.
import 'dart:async';

import 'package:fitness_app/core/config/body_scan_flags.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_manage_api.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_providers.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_settings.dart';
import 'package:fitness_app/features/body_scan/widgets/retention_settings_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/test_app.dart';

class _Manage implements BodyScanManageApi {
  final calls = <String>[];
  Object? error;
  Completer<int>? gate;

  Future<int> _do(String name) async {
    calls.add(name);
    if (gate != null) return gate!.future;
    if (error != null) throw error!;
    return 1;
  }

  @override
  Future<int> applyRetention(int retentionDays) =>
      _do('applyRetention:$retentionDays');
  @override
  Future<int> deleteAllPhotos() => _do('deleteAllPhotos');
  @override
  Future<int> deleteAllScans() => _do('deleteAllScans');
}

class _Env {
  _Env(this.manage, this.store);
  final _Manage manage;
  final InMemoryBodyScanSettingsStore store;
}

Future<_Env> _pump(
  WidgetTester t, {
  bool cloud = true,
  BodyScanSettings settings = const BodyScanSettings(),
  Locale locale = kTestLocale,
}) async {
  t.view.physicalSize = const Size(900, 3200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final manage = _Manage();
  final store = InMemoryBodyScanSettingsStore(settings);
  await t.pumpWidget(ProviderScope(
    overrides: [
      authUserProvider.overrideWith(
          (ref) => Stream.value(const AuthUser(uid: 'u1', displayName: 'T'))),
      bodyScanFlagsProvider.overrideWithValue(BodyScanFlags(cloudPhotos: cloud)),
      bodyScanSettingsStoreProvider.overrideWithValue(store),
      bodyScanManageApiProvider.overrideWithValue(manage),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: RetentionSettingsView()),
    ),
  ));
  await t.pump();
  await t.pump();
  return _Env(manage, store);
}

AppLocalizations _l10n(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(RetentionSettingsView)));

Future<BodyScanSettings> _current(_Env e) => e.store.watch().first;

void main() {
  group('cloud sections follow BODY_SCAN_CLOUD', () {
    testWidgets('cloud ON: retention, consent and delete sections are shown',
        (t) async {
      await _pump(t);
      expect(find.byKey(const Key('bodyScan.privacy.retentionCard')),
          findsOneWidget);
      expect(find.byKey(const Key('bodyScan.privacy.consentCard')),
          findsOneWidget);
      expect(find.byKey(const Key('bodyScan.privacy.deleteCard')),
          findsOneWidget);
      expect(find.byKey(const Key('bodyScan.privacy.pause')), findsOneWidget);
      expect(find.text(_l10n(t).bodyScanPrivacyIntroCloud), findsOneWidget);
    });

    testWidgets('cloud OFF: only the pause switch and the local-only intro',
        (t) async {
      final e = await _pump(t, cloud: false);
      expect(find.byKey(const Key('bodyScan.privacy.retentionCard')),
          findsNothing);
      expect(find.byKey(const Key('bodyScan.privacy.consentCard')), findsNothing);
      expect(find.byKey(const Key('bodyScan.privacy.deleteCard')), findsNothing);
      expect(find.byKey(const Key('bodyScan.privacy.apply')), findsNothing);
      expect(find.byKey(const Key('bodyScan.privacy.pause')), findsOneWidget);
      expect(find.text(_l10n(t).bodyScanPrivacyIntroLocal), findsOneWidget);
      expect(find.text(_l10n(t).bodyScanPrivacyIntroCloud), findsNothing);
      expect(e.manage.calls, isEmpty);
    });
  });

  group('retention choices', () {
    testWidgets('offers exactly 0/30/90/365 with the default 0 selected',
        (t) async {
      await _pump(t);
      for (final d in [0, 30, 90, 365]) {
        expect(find.byKey(Key('bodyScan.privacy.retention.$d')), findsOneWidget);
      }
      expect(
          find.byWidgetPredicate((w) =>
              w.key is Key &&
              (w.key as Key).toString().contains('bodyScan.privacy.retention.')),
          findsNWidgets(4));
      final l10n = _l10n(t);
      expect(find.text(l10n.bodyScanRetention0), findsOneWidget);
      expect(find.text(l10n.bodyScanRetentionDays(30)), findsOneWidget);
      expect(find.text('365 days'), findsOneWidget);
      // Only the default row carries the check mark.
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('bodyScan.privacy.retention.0')),
              matching: find.byIcon(Icons.check)),
          findsOneWidget);
    });

    testWidgets('a stored 90 days shows its check mark, not the default',
        (t) async {
      await _pump(t, settings: const BodyScanSettings(retentionDays: 90));
      expect(
          find.descendant(
              of: find.byKey(const Key('bodyScan.privacy.retention.90')),
              matching: find.byIcon(Icons.check)),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('bodyScan.privacy.retention.0')),
              matching: find.byIcon(Icons.check)),
          findsNothing);
    });

    testWidgets('tapping a choice stores it and moves the check mark',
        (t) async {
      final e = await _pump(t);
      await t.tap(find.byKey(const Key('bodyScan.privacy.retention.365')));
      await t.pump();
      await t.pump();
      expect((await _current(e)).retentionDays, 365);
      expect(
          find.descendant(
              of: find.byKey(const Key('bodyScan.privacy.retention.365')),
              matching: find.byIcon(Icons.check)),
          findsOneWidget);
    });

    testWidgets('the copy says photos are deleted within 48 hours (EN)',
        (t) async {
      await _pump(t);
      final honest = t.widget<Text>(find.byKey(const Key('bodyScan.privacy.honest')));
      expect(honest.data, contains('within 48 hours'));
      expect(honest.data, contains('Photos kept on this phone are not affected'));
      expect(_l10n(t).bodyScanPrivacyApplyDone, contains('within 48 hours'));
      expect(_l10n(t).bodyScanPrivacyDeleteDone, contains('within 48 hours'));
      expect(_l10n(t).bodyScanPrivacyDeletePhotosBody,
          contains('within 48 hours'));
      expect(_l10n(t).bodyScanPrivacyIntroCloud, contains('within 48 hours'));
    });

    testWidgets('the Russian copy states the same 48-hour bound', (t) async {
      await _pump(t, locale: const Locale('ru'));
      final honest = t.widget<Text>(find.byKey(const Key('bodyScan.privacy.honest')));
      expect(honest.data, contains('48'));
      expect(honest.data, isNot(contains('within')));
    });
  });

  group('apply to existing photos', () {
    testWidgets('calls applyRetention once with the CURRENT choice, then '
        'confirms', (t) async {
      final e = await _pump(t, settings: const BodyScanSettings(retentionDays: 30));
      await t.tap(find.byKey(const Key('bodyScan.privacy.apply')));
      await t.pumpAndSettle();
      expect(e.manage.calls, ['applyRetention:30']);
      expect(find.text(_l10n(t).bodyScanPrivacyApplyDone), findsOneWidget);
    });

    testWidgets('a failure shows the generic failure text, never the raw error',
        (t) async {
      final e = await _pump(t);
      e.manage.error = StateError('secret-internal-detail');
      await t.tap(find.byKey(const Key('bodyScan.privacy.apply')));
      await t.pumpAndSettle();
      expect(find.text(_l10n(t).bodyScanPrivacyFailed), findsOneWidget);
      expect(find.textContaining('secret-internal-detail'), findsNothing);
    });
  });

  group('delete all cloud photos / scans', () {
    testWidgets('photos: confirm first, port called ONCE after confirm',
        (t) async {
      final e = await _pump(t);
      await t.tap(find.byKey(const Key('bodyScan.privacy.deletePhotos')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('bodyScan.privacy.confirmDialog')),
          findsOneWidget);
      expect(e.manage.calls, isEmpty, reason: 'nothing before the confirmation');
      expect(find.text(_l10n(t).bodyScanPrivacyDeletePhotosTitle), findsOneWidget);
      await t.tap(find.byKey(const Key('bodyScan.privacy.confirmOk')));
      await t.pumpAndSettle();
      expect(e.manage.calls, ['deleteAllPhotos']);
      expect(find.text(_l10n(t).bodyScanPrivacyDeleteDone), findsOneWidget);
    });

    testWidgets('scans: its own dialog and its own port', (t) async {
      final e = await _pump(t);
      await t.tap(find.byKey(const Key('bodyScan.privacy.deleteScans')));
      await t.pumpAndSettle();
      expect(find.text(_l10n(t).bodyScanPrivacyDeleteScansTitle), findsOneWidget);
      await t.tap(find.byKey(const Key('bodyScan.privacy.confirmOk')));
      await t.pumpAndSettle();
      expect(e.manage.calls, ['deleteAllScans']);
    });

    testWidgets('cancel calls nothing (photos and scans)', (t) async {
      final e = await _pump(t);
      for (final k in ['deletePhotos', 'deleteScans']) {
        await t.tap(find.byKey(Key('bodyScan.privacy.$k')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('bodyScan.privacy.confirmCancel')));
        await t.pumpAndSettle();
      }
      expect(e.manage.calls, isEmpty);
      expect(find.byKey(const Key('bodyScan.privacy.confirmDialog')),
          findsNothing);
    });

    testWidgets('while an action runs the buttons are disabled and a progress '
        'bar shows; a double tap cannot start a second call', (t) async {
      final e = await _pump(t);
      e.manage.gate = Completer<int>();
      await t.tap(find.byKey(const Key('bodyScan.privacy.deletePhotos')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('bodyScan.privacy.confirmOk')));
      await t.pump();
      await t.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
          t
              .widget<OutlinedButton>(
                  find.byKey(const Key('bodyScan.privacy.deleteScans')))
              .onPressed,
          isNull);
      expect(
          t
              .widget<OutlinedButton>(
                  find.byKey(const Key('bodyScan.privacy.apply')))
              .onPressed,
          isNull);
      e.manage.gate!.complete(3);
      await t.pumpAndSettle();
      expect(e.manage.calls, ['deleteAllPhotos']);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('failure: generic message and the buttons come back',
        (t) async {
      final e = await _pump(t);
      e.manage.error = StateError('boom');
      await t.tap(find.byKey(const Key('bodyScan.privacy.deleteScans')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('bodyScan.privacy.confirmOk')));
      await t.pumpAndSettle();
      expect(find.text(_l10n(t).bodyScanPrivacyFailed), findsOneWidget);
      expect(
          t
              .widget<OutlinedButton>(
                  find.byKey(const Key('bodyScan.privacy.deleteScans')))
              .onPressed,
          isNotNull);
    });
  });

  group('consent and pause', () {
    testWidgets('no consent: off text and no withdraw button', (t) async {
      await _pump(t);
      expect(find.text(_l10n(t).bodyScanPrivacyConsentOff), findsOneWidget);
      expect(find.byKey(const Key('bodyScan.privacy.withdraw')), findsNothing);
    });

    testWidgets('current consent: on text; withdraw clears it', (t) async {
      final e = await _pump(t,
          settings: BodyScanSettings(
              cloudConsentVersion: kBodyScanCloudConsentVersion));
      expect(find.text(_l10n(t).bodyScanPrivacyConsentOn), findsOneWidget);
      await t.tap(find.byKey(const Key('bodyScan.privacy.withdraw')));
      await t.pump();
      await t.pump();
      expect((await _current(e)).cloudConsentVersion, isNull);
      expect(find.text(_l10n(t).bodyScanPrivacyConsentOff), findsOneWidget);
      expect(find.byKey(const Key('bodyScan.privacy.withdraw')), findsNothing);
    });

    testWidgets('pause switch persists, also with cloud OFF', (t) async {
      final e = await _pump(t, cloud: false);
      expect(
          t
              .widget<SwitchListTile>(find.byKey(const Key('bodyScan.privacy.pause')))
              .value,
          isFalse);
      await t.tap(find.byKey(const Key('bodyScan.privacy.pause')));
      await t.pump();
      await t.pump();
      expect((await _current(e)).paused, isTrue);
      expect(
          t
              .widget<SwitchListTile>(find.byKey(const Key('bodyScan.privacy.pause')))
              .value,
          isTrue);
    });
  });
}
