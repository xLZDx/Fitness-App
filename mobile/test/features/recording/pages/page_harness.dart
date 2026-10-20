// Page harness of the EP_F_G_J group: the REAL GpsRecordingPage (and its views)
// on the REAL RecorderController, with scripted seams, a real consent notifier
// on mocked preferences, a navigator observer and an announcement spy.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/core/config/recording_defaults.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/recording/consent/location_consent.dart';
import 'package:fitness_app/features/recording/consent/location_consent_providers.dart';
import 'package:fitness_app/features/recording/pages/gps_recording_page.dart';
import 'package:fitness_app/features/recording/state/recorder_controller.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart';
import 'package:fitness_app/features/recording/state/recorder_providers.dart';
import 'package:fitness_app/features/recording/state/recorder_state.dart';

import 'recorder_harness.dart';

/// A recorder whose state a test may force, for display-only projections that
/// the real flow cannot reach (for example the never-set `offline` flag).
class ForceableRecorder extends RecorderController {
  void force(RecorderState Function(RecorderState) edit) =>
      state = edit(state);
}

final NotifierProvider<ForceableRecorder, RecorderState> forceableRecorder =
    NotifierProvider<ForceableRecorder, RecorderState>(ForceableRecorder.new);

/// Records every pushed route so a test can prove "no dialog, no sheet".
class RouteSpy extends NavigatorObserver {
  final List<Route<dynamic>> pushed = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }

  /// Popup-style routes (dialogs, bottom sheets, menus) pushed after the first.
  List<Route<dynamic>> get popups =>
      pushed.where((r) => r is PopupRoute).toList();
}

class PageWorld {
  PageWorld(this.t, this.seams, this.spy, this.announced, this.closed,
      this.manual, this.privacy, this.workout);
  final WidgetTester t;
  final Seams seams;
  final RouteSpy spy;

  /// Raw announce payloads: `message` and optional `assertiveness`.
  final List<Map<Object?, Object?>> announced;
  final List<String> closed;
  final List<String> manual;
  final List<String> privacy;
  final List<String> workout;

  ProviderContainer get c =>
      ProviderScope.containerOf(t.element(find.byType(GpsRecordingPage)));
  RecorderController get ctl => c.read(recorderControllerProvider.notifier);
  RecorderState get state => c.read(recorderControllerProvider);
  RecorderPhase get phase => state.phase;

  List<String> get messages =>
      announced.map((m) => m['message'] as String).toList();

  /// Lets real async work finish and pumps the fake clock.
  Future<void> settle([int n = 3]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(() => Future<void>.delayed(Duration.zero));
      await t.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> advance(Duration d) async {
    var left = d.inMilliseconds;
    while (left > 0) {
      final step = left > 1000 ? 1000 : left;
      left -= step;
      seams.env.now += step;
      await t.pump(Duration(milliseconds: step));
      await t.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    await settle(1);
  }

  Future<void> fix({double accuracy = 5, double speed = 2.5}) async {
    seams.emitFix(accuracy: accuracy, speed: speed);
    await settle(2);
  }

  /// Taps the Start button (the full permission journey runs) and settles.
  Future<void> tapStart() async {
    await t.tap(find.byKey(const ValueKey<String>('gps.start.button')));
    await settle(4);
  }

  /// Start through the screen, then two fixes: the phase is `recording`.
  Future<void> startRecording() async {
    await tapStart();
    await fix();
    await advance(const Duration(seconds: 1));
    await fix();
    await advance(const Duration(seconds: 1));
  }

  Future<void> tapKey(String k) async {
    await t.tap(find.byKey(ValueKey<String>(k)));
    await settle(3);
  }

  Future<void> tapText(String text) async {
    await t.tap(find.text(text));
    await settle(3);
  }
}

Future<PageWorld> pumpPage(
  WidgetTester t, {
  Size size = const Size(360, 800),
  double textScale = 1.0,
  Locale locale = const Locale('en'),
  bool resumeMode = false,
  ConsentState consent = ConsentState.granted,
  bool withWorkout = false,
  List<Override> extra = const <Override>[],
  Seams? seams,
  bool forceable = false,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final s = seams ?? Seams();
  s.env.ownerUid = 'uid-a';
  s.env.consent = consent == ConsentState.granted;

  final stored = <String, Object>{};
  if (consent != ConsentState.none) {
    stored[locationConsentKeyFor('uid-a')] = LocationConsent(
      <LocationConsentPurpose, ConsentRecord>{
        LocationConsentPurpose.locationWhileRecording: ConsentRecord(
          purpose: LocationConsentPurpose.locationWhileRecording,
          state: consent,
          textVersion: kLocationConsentTextVersion,
          timestampUtcMs: 1700000000000,
          grantedAtUtcMs: 1700000000000,
        ),
      },
    ).encode();
  }
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();

  final announced = <Map<Object?, Object?>>[];
  t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility, (dynamic m) async {
    if (m is Map && m['type'] == 'announce') {
      announced.add(Map<Object?, Object?>.from(m['data'] as Map));
    }
  });
  addTearDown(() => t.binding.defaultBinaryMessenger
      .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null));

  final spy = RouteSpy();
  final closed = <String>[];
  final manual = <String>[];
  final privacy = <String>[];
  final workout = <String>[];
  await t.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: <Override>[
      authUserProvider.overrideWith((ref) => Stream<AuthUser?>.value(
          const AuthUser(uid: 'uid-a', displayName: 'A'))),
      locationConsentPrefsProvider
          .overrideWithValue(Future<SharedPreferences>.value(prefs)),
      ...s.overrides,
      if (forceable) recorderControllerProvider.overrideWith(ForceableRecorder.new),
      ...extra,
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      navigatorObservers: <NavigatorObserver>[spy],
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child ?? const SizedBox.shrink(),
      ),
      home: GpsRecordingPage(
        resumeMode: resumeMode,
        onClose: () => closed.add('close'),
        onAddManually: () => manual.add('manual'),
        onOpenPrivacySettings: () => privacy.add('privacy'),
        onOpenWorkout: withWorkout ? () => workout.add('workout') : null,
      ),
    ),
  ));
  final w = PageWorld(t, s, spy, announced, closed, manual, privacy, workout);
  // The running app keeps auth and consent alive; so does the test.
  w.c.listen(authUserProvider, (_, __) {});
  w.c.listen(locationConsentProvider, (_, __) {});
  await w.settle(3);
  return w;
}

const SportType kRun = SportType.running;
