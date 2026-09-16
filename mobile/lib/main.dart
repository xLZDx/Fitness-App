import 'dart:async';
import 'dart:ui';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/assets/asset_bootstrap.dart';
import 'core/debug/g3_step10b_probe.dart';
import 'core/health/platform_health_service.dart';
import 'core/licences/asset_licences.dart';
import 'core/health/state/health_providers.dart';
import 'core/notifications/local_notification_service.dart';
import 'core/notifications/notification_providers.dart';
import 'core/notifications/notification_service.dart';
import 'core/router/app_router.dart';
// Imported for the AppThemeModeX / AppLanguageX extensions used below —
// extension methods are only visible where their library is imported.
import 'core/settings/app_settings.dart';
import 'core/settings/settings_repository.dart';
import 'core/settings/state/settings_providers.dart';
import 'core/theme/app_theme.dart';
import 'core/wear/state/wear_providers.dart';
import 'core/wear/wear_sync_service.dart';
import 'features/auth/data/firebase_auth_repository.dart';
import 'features/auth/state/auth_providers.dart';
import 'features/donor_wall/data/cloud_donor_wall_repository.dart';
import 'features/donor_wall/state/donor_wall_providers.dart';
import 'features/account_deletion/data/cloud_functions_account_deletion_service.dart';
import 'features/account_deletion/data/local_data_wipe.dart';
import 'features/account_deletion/state/account_deletion_providers.dart';
import 'features/data_export/data_export_sink.dart';
import 'features/data_export/data_export_providers.dart';
import 'features/data_export/server_export.dart';
import 'features/equipment/data/cloud_functions_equipment_report_service.dart';
import 'features/equipment/state/equipment_providers.dart';
import 'features/form_check/data/cue_text.dart';
import 'features/form_check/data/mlkit_pose_detector_service.dart';
import 'features/form_check/data/tts_voice_coach.dart';
import 'features/form_check/state/form_check_providers.dart';
import 'features/marketplace/data/coach_marketplace_service.dart';
import 'features/marketplace/state/marketplace_providers.dart';
import 'features/moments/data/prefs_moment_repository.dart';
import 'features/moments/state/moment_providers.dart';
import 'features/profile/data/device_health_profile_repository.dart';
import 'features/profile/data/firestore_profile_repository.dart';
import 'features/profile/data/local_sensitive_store.dart';
import 'features/profile/state/profile_providers.dart';
import 'features/subscription/data/cloud_functions_stripe_service.dart';
import 'features/subscription/data/firestore_subscription_repository.dart';
import 'features/subscription/state/subscription_providers.dart';
import 'features/visual_equipment/data/cloud_equipment_identity_telemetry_service.dart';
import 'features/visual_equipment/data/equipment_identity_telemetry_outbox.dart';
import 'features/visual_equipment/data/firestore_recognition_history.dart';
import 'features/visual_equipment/state/equipment_identity_providers.dart'
    show drainEquipmentIdentityTelemetryOutbox, equipmentIdentityTelemetryOutboxProvider;
import 'features/visual_equipment/data/mlkit_live_equipment_service.dart';
import 'features/ai_coach/generated_exercise_repository.dart';
import 'features/visual_equipment/data/gemini_equipment_service.dart';
import 'features/visual_equipment/data/mlkit_text_recogniser.dart';
import 'features/visual_equipment/data/mlkit_visual_equipment_service.dart';
import 'features/visual_equipment/state/live_equipment_providers.dart';
import 'features/equipment/data/firestore_equipment_setup_notes.dart';
import 'features/equipment/state/equipment_setup_note_providers.dart';
import 'features/visual_equipment/data/firestore_machine_cards.dart';
import 'features/visual_equipment/data/machine_describer.dart';
import 'features/visual_equipment/state/machine_card_providers.dart';
import 'features/visual_equipment/state/recognition_history_providers.dart';
import 'features/visual_equipment/state/visual_equipment_providers.dart';
import 'features/programmes/data/firestore_programme_repository.dart';
import 'features/programmes/state/programme_providers.dart';
import 'features/workouts/data/firestore_scheduled_session_repository.dart';
import 'features/workouts/data/firestore_workout_log_repository.dart';
import 'features/workouts/data/firestore_workout_session_repository.dart';
import 'features/workouts/data/offline_video_cache.dart';
import 'features/workouts/state/offline_video_providers.dart';
import 'features/workouts/state/scheduled_session_providers.dart';
import 'features/workouts/state/workout_log_providers.dart';
import 'features/workouts/state/workout_session_providers.dart';
import 'firebase_options.dart';
import 'core/diagnostics/debug_telemetry.dart';
import 'core/diagnostics/debug_telemetry_sink.dart';
import 'shared/widgets/aurora_background.dart';

/// Session log for this run, or null in release / when the define is off.
///
/// Top-level rather than passed down: `captureDebugPrint` hooks a global, so
/// pretending the owner is local would be a lie about its lifetime.
DebugTelemetry? _telemetry;

/// Held only to keep the listener alive for the process lifetime.
///
/// Nothing reads it, and that is correct: an `AppLifecycleListener` that goes
/// out of scope is collected and stops delivering, so dropping the reference
/// would silently disable the flush. Named with a leading underscore and
/// ignored rather than deleted.
// ignore: unused_element
AppLifecycleListener? _lifecycle;

/// Uploads the session log, swallowing its own failures deliberately.
///
/// A diagnostics upload that throws into a lifecycle callback would take down
/// the app it exists to observe, and it fires exactly when the user is leaving
/// — the worst possible moment for a crash. The failure still gets a line in
/// the console, which is where a developer running this build is looking.
Future<void> _flushTelemetry() async {
  final t = _telemetry;
  if (t == null || t.events.isEmpty) return;
  // No uid, no upload. The rule for `debug_sessions` requires the document to
  // stamp its own author, so a signed-out session cannot be written — and
  // trying anyway would turn every pre-login run into a permission-denied line
  // that reads like a broken pipeline rather than the expected state it is.
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  try {
    await FirestoreDebugTelemetrySink(uid: uid).send(t.toJson());
  } catch (e) {
    // Not debugPrint: that is captured back into the very log we failed to
    // send, which would grow the buffer on every retry.
    // ignore: avoid_print
    print('B6: session log upload failed: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // R0 -- Crashlytics. Both handlers wired immediately after Firebase
  // itself is up, before any of the bootstrap work below (asset copy,
  // prefs open, notification init) runs -- a crash during THAT bootstrap
  // is exactly the kind of early, hard-to-repro failure this exists to
  // catch. `recordFlutterFatalError` covers framework-level errors (widget
  // build/layout/paint); `PlatformDispatcher.instance.onError` covers
  // everything outside the Flutter framework's own error zone (async gaps,
  // platform channel callbacks) -- Flutter's own crash-reporting guidance
  // wires both because neither alone is a superset of the other.
  //
  // Disabled in debug builds on purpose: an ordinary `flutter run` session
  // hitting a hot-reload edge case would otherwise report as a production
  // crash, which is exactly the kind of noise the operator's "clean
  // banner" standard exists to keep out of a signal that real users'
  // crashes need to stand out against.
  //
  // The collection toggle is wrapped on its own, separately from installing
  // the handlers below: two independent reviewers (flutter-reviewer,
  // silent-failure-hunter) converged on the same defect from different
  // angles -- if this specific call throws (traced live in the installed
  // package source: any native-side failure reaches Dart as a rethrown
  // `PlatformException`, never swallowed) and the handlers were installed
  // only after it in an unguarded sequence, `main()` would abort before
  // `runApp()` ever ran, and before the two lines whose entire purpose is
  // to catch exactly that kind of failure ever executed. Installing the
  // handlers unconditionally, right after, closes that gap: a failed
  // collection toggle degrades to "crash reporting is off", not "the app
  // never boots".
  try {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      !kDebugMode,
    );
  } catch (e) {
    debugPrint('R0: Crashlytics collection toggle failed, continuing: $e');
  }
  // MVP1.G3 Step 10B -- tags probe-build backend events with their exact
  // source tree so a Crashlytics event can be matched to the APK that
  // produced it. A no-op (empty sourceSha, dead code) in every normal build.
  try {
    await G3Step10bProbe.attachBuildProvenance();
  } catch (e) {
    debugPrint('R0: G3Step10bProbe provenance tagging failed, continuing: $e');
  }
  // B6 -- session diagnostics, debug builds only.
  //
  // Crashlytics above reports crashes and is OFF in debug on purpose. This is
  // the other half: a session that did not crash and still did the wrong
  // thing, on the operator's own phone, where the emulator cannot follow.
  //
  // Installed here, right after Crashlytics and before the bootstrap below,
  // for the same reason Crashlytics is: the asset copy, prefs open and
  // notification init are exactly where an early failure hides, and a log
  // that starts after them cannot describe them.
  if (kDebugMode && kDebugTelemetryEnabled) {
    _telemetry = DebugTelemetry(
      identity: SessionIdentity(
        appVersion: const String.fromEnvironment('APP_VERSION',
            defaultValue: '1.0.0'),
        buildNumber:
            const String.fromEnvironment('BUILD_NUMBER', defaultValue: '14'),
        // Pass these from the build command:
        //   --dart-define=GIT_SHA=$(git rev-parse --short HEAD)
        //   --dart-define=BUILT_AT=$(date -u +%FT%TZ)
        // 'unknown' is not a placeholder to ignore -- it means this APK cannot
        // be traced to a commit, which is the exact question that cost a
        // session on 2026-08-07.
        gitSha:
            const String.fromEnvironment('GIT_SHA', defaultValue: 'unknown'),
        platform: defaultTargetPlatform.name,
        builtAt:
            const String.fromEnvironment('BUILT_AT', defaultValue: 'unknown'),
      ),
    );
    captureDebugPrint(_telemetry!);
    // Flushed when the app leaves the foreground, not on a timer: that is the
    // moment the operator has finished doing the thing they wanted logged, and
    // a timer would either upload half a session or burn battery uploading
    // nothing. Fire-and-forget with its own catch -- diagnostics that can
    // crash the app they observe are worse than no diagnostics.
    _lifecycle = AppLifecycleListener(
      onPause: () => unawaited(_flushTelemetry()),
      onDetach: () => unawaited(_flushTelemetry()),
    );
    debugPrint('B6: session log armed — build ${_telemetry!.identity.gitSha} '
        'built ${_telemetry!.identity.builtAt}');
  }

  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    // Debug-only console echo: `setCrashlyticsCollectionEnabled(false)`
    // above means a `flutter run` session reports nothing to the Firebase
    // Console by design -- without this, an uncaught error during local
    // dev/QA could produce no output anywhere at all.
    if (kDebugMode) debugPrint('Uncaught error: $error\n$stack');
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // R0 -- App Check, monitor-before-enforce by design, not cold
  // enforcement. `activate()` starts attaching a verification token to
  // every Firestore/Functions/Storage request this client makes from this
  // moment on -- that's what populates the App Check metrics tab in the
  // Firebase Console (Play Integrity on Android, Device Check on Apple;
  // both are this package's own current, non-deprecated defaults, not
  // chosen here).
  //
  // Turning ENFORCEMENT on per product -- Firestore, every callable in
  // functions/src/index.ts including deleteAccount, Storage -- is a
  // separate, later, deliberate step the operator takes only after that
  // console tab shows real traffic passing verification. Flipping it on
  // cold, day one, with no observed baseline, risks locking out genuine
  // users on any provider mismatch (a fresh install before Play Integrity
  // attestation has warmed up, a rooted device, an emulator used for real
  // testing) -- indistinguishable at that point from an actual attacker.
  // No Cloud Function in this change sets `enforceAppCheck: true`.
  //
  // Wrapped for the same reason as the Crashlytics toggle above, and for
  // this call the risk is concrete rather than hypothetical: Play Integrity
  // needs Google Play Services (absent on plain AOSP emulator images), so
  // `activate()` throwing on exactly the images used for routine dev/QA
  // testing is a realistic, not edge-case, outcome. Monitoring is explicitly
  // the non-critical half of this gate -- losing it must never cost boot.
  //
  // F0·6: debug builds attest through the debug provider instead of Play
  // Integrity. This is not convenience — it is what makes enforcement
  // possible at all. A `flutter run` debug build is neither Play- nor
  // App-Distribution-signed, so it cannot pass Play Integrity under any
  // App Check console config (a build-signing gap, not the
  // outside-Play/App-Distribution distribution-channel question corrected
  // in `functions/src/scaling.ts:91-107` -- that correction is about
  // release builds shipped via Firebase App Distribution, which DOES have a
  // documented attestation path; it does not extend to a raw local debug
  // build). Once enforcement is on, a locally-built debug APK without the
  // debug token is indistinguishable from an attacker and every Gemini call
  // from it is refused. The debug provider prints a token on first run;
  // registering that token in the console (App Check -> Apps -> Manage
  // debug tokens) is what keeps development working after enforcement.
  //
  // Release builds are untouched by this branch and keep Play Integrity,
  // which is the whole point: the exemption cannot ship to users, because
  // `kDebugMode` is compiled out of a release build entirely.
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          // Token passed in rather than auto-generated: one token,
          // registered once via the App Check API, is reused by every
          // debug build on every machine.
          //
          // Supplied at run time, never committed:
          //   flutter run --dart-define=APP_CHECK_DEBUG_TOKEN=<value>
          // Empty by default. Verified on-device (MVP1.G4 Step 5, S8,
          // 2026-08-29): an empty string is NOT a documented "generate one
          // for me" signal on the current `firebase_app_check` Android
          // plugin — it is sent to the backend as-is and rejected
          // (`400 the debug_token cannot be empty`). A developer without a
          // token must generate a real value (e.g. `crypto.randomUUID()`)
          // and register it via the App Check Admin API or Console before
          // App Check calls will succeed on a debug build; leaving this
          // empty degrades to "App Check calls fail" (caught above), not a
          // working manual path.
          ? const AndroidDebugProvider(
              debugToken: String.fromEnvironment('APP_CHECK_DEBUG_TOKEN'),
            )
          : const AndroidPlayIntegrityProvider(),
    );
  } catch (e, st) {
    debugPrint('R0: App Check activate() failed, continuing without it: $e');
    FirebaseCrashlytics.instance.recordError(e, st, fatal: false);
  }

  // Warm up notifications. Warm-up ONLY -- no permission prompt: this runs
  // before the first frame, and an "Allow notifications?" dialog over a blank
  // screen is a dialog the user denies. The prompt now happens in
  // `scheduleReminder`, where the user has just asked to be reminded of
  // something. We keep a single instance and inject it into Riverpod so
  // reminders are de-duped and cancellable across restarts.
  final NotificationService notifications = LocalNotificationService();
  await notifications.init();

  // Open SharedPreferences-backed nurture-moments repository up-front so
  // the first cold-start launch counts.
  final momentRepo = await PrefsMomentRepository.open();

  // H1a. The device-only half of the profile -- health history, plus smoking
  // and alcohol. Opened here rather than lazily because the repository that
  // wraps Firestore needs it at construction, and the profile is watched from
  // the first authenticated frame.
  final sensitiveStore = await PrefsSensitiveStore.open();

  // P2.G5-readiness step 3b: durable retry-on-failure delivery for
  // equipment-identity telemetry. Opened up-front like the repositories
  // above -- see `equipment_identity_telemetry_outbox.dart`'s own doc
  // comment for why blind retry is safe against the server's merge rules.
  final equipmentIdentityTelemetryOutbox =
      await FileEquipmentIdentityTelemetryOutbox.open();
  // Cold-start drain, in addition to the resume-triggered one in
  // `_FitnessAppState.didChangeAppLifecycleState`. `WidgetsBindingObserver`
  // only reports lifecycle CHANGES from here on -- it is never invoked for
  // the state the app is already in when the observer is registered -- so a
  // queue populated in a prior, now-dead process (the common case on
  // Android: the OS kills a backgrounded app, the user later taps the icon
  // into a brand new process) would otherwise sit un-drained until the user
  // backgrounds and resumes THIS run at least once. Unawaited and
  // constructed directly (no `ProviderScope`/`ref` exists yet, this runs
  // before `runApp`) -- same real `CloudEquipmentIdentityTelemetryService`
  // the app's own provider default would hand out, since nothing here
  // overrides that provider.
  unawaited(equipmentIdentityTelemetryOutbox
      .drainPending(CloudEquipmentIdentityTelemetryService().send));

  // Settings must be resolved BEFORE the first frame: theme and locale are
  // read during the initial build, and loading them asynchronously would
  // flash the wrong theme and the wrong language before settling.
  final settingsRepo = await PrefsSettingsRepository.open();
  final settings = await settingsRepo.load();

  // Publish bundled-asset licences so they appear in showLicensePage. Cheap:
  // the entries are generated lazily, only when that page is opened.
  registerAssetLicences();

  // Copy any bundled ML models out of the APK into the docs dir so
  // ML Kit's LocalLabelerOptions can read them by absolute path.
  await AssetBootstrap().ensureBundledAssets();

  runApp(
    ProviderScope(
      overrides: [
        // Auth + profile + subscriptions
        authRepositoryProvider.overrideWith((_) => FirebaseAuthRepository()),
        // Firestore for everything except the health block, which never
        // leaves the device -- see DeviceHealthProfileRepository. Nothing on
        // the server read it, so holding it there bought GDPR Article 9
        // exposure and a Play "Health info" declaration for nothing.
        //
        // The store is overridden as well as passed in, so that restore (H2b)
        // writes into the same instance this repository reads from.
        localSensitiveStoreProvider.overrideWithValue(sensitiveStore),
        equipmentIdentityTelemetryOutboxProvider
            .overrideWithValue(equipmentIdentityTelemetryOutbox),
        profileRepositoryProvider.overrideWith(
          (_) => DeviceHealthProfileRepository(
            FirestoreProfileRepository(),
            sensitiveStore,
          ),
        ),
        subscriptionRepositoryProvider
            .overrideWith((_) => FirestoreSubscriptionRepository()),
        stripeCheckoutServiceProvider
            .overrideWith((_) => CloudFunctionsStripeService()),

        // Workouts
        workoutLogRepositoryProvider
            .overrideWith((_) => FirestoreWorkoutLogRepository()),
        // F3.2 -- infrastructure only, nothing reads workoutSessionsProvider
        // yet. Overridden here so F3.3's backfill and F3.4's write-path
        // repoint land against the real collection without a second wiring
        // step.
        workoutSessionRepositoryProvider
            .overrideWith((_) => FirestoreWorkoutSessionRepository()),
        scheduledSessionRepositoryProvider
            .overrideWith((_) => FirestoreScheduledSessionRepository()),
        offlineVideoCacheProvider
            .overrideWith((_) => FileOfflineVideoCache()),
        programmeRepositoryProvider
            .overrideWith((_) => FirestoreProgrammeRepository()),

        // Equipment
        equipmentReportServiceProvider
            .overrideWith((_) => CloudFunctionsEquipmentReportService()),

        // Donor wall (server-side write via Cloud Function)
        donorWallRepositoryProvider
            .overrideWith((_) => CloudDonorWallRepository()),

        // Health Connect (Android) / HealthKit (iOS) — falls back to
        // unsupported gracefully on web/desktop.
        healthServiceProvider
            .overrideWith((_) => PlatformHealthService()),

        // Form check — bind ML Kit pose detector. The page calls
        // start()/stop() in initState/dispose; defaults to mock for
        // tests so widget tests don't need a real camera.
        poseDetectorServiceProvider
            .overrideWith((_) => MlKitPoseDetectorService()),

        // Spoken form cues. Defaults to MockVoiceCoach so widget tests never
        // open a TTS MethodChannel; the throttling policy is identical in
        // both, it lives in the shared CueGate.
        voiceCoachProvider.overrideWith((ref) {
          // The coach speaks whatever language the app is in. Both halves of
          // that matter and both were broken: the cues were English literals
          // baked into the classifiers, and the engine was pinned to en-US, so
          // even translated text would have been read by an English voice.
          final lang = ref.watch(effectiveLanguageCodeProvider);
          AppLocalizations? l10n;
          Object? l10nError;
          // `unawaited` silences the lint, not the error — without an explicit
          // handler a failed load left `l10n` null forever and every cue
          // resolved to nothing. A coach that goes permanently, invisibly mute
          // is the exact defect this whole gate exists to remove.
          unawaited(AppLocalizations.delegate.load(Locale(lang)).then(
            (loaded) => l10n = loaded,
            onError: (Object e, StackTrace st) {
              l10nError = e;
              debugPrint('form-coach localisation failed to load: $e');
            },
          ));
          final coach = TtsVoiceCoach(
            languageTag: lang == 'ru' ? 'ru-RU' : 'en-US',
            // Empty until the bundle lands (a few milliseconds at startup).
            // GatedVoiceCoach skips empty text, so the coach is briefly silent
            // rather than reading a raw key like "squat.depth.half" out loud.
            resolveText: (key) {
              final loaded = l10n;
              if (loaded != null) return formCueText(loaded, key);
              // Still loading (a few milliseconds at startup): stay quiet, the
              // next frame will resolve. Failed outright: say the key. It is
              // ugly on purpose — a broken coach the user can hear is
              // recoverable, a silent one is not.
              return l10nError == null ? '' : key.name;
            },
          );
          ref.onDispose(() => coach.dispose());
          return coach;
        }),

        // Visual equipment recognition — Gemini (Firebase AI Logic, key
        // server-side) first, the bundled 10-class TFLite model as the
        // offline fallback. The registry alias index pins cloud answers to
        // catalog ids, so the model cannot route to a page we don't have.
        visualEquipmentServiceProvider.overrideWith(
          (_) => HybridVisualEquipmentService(
            cloud: GeminiVisualEquipmentService(),
            local: MlKitVisualEquipmentService(),
          ),
        ),

        // B5b — the text anchor. Runs before the classifier and reads the
        // machine's own printed name. On the operator's 30 gym photos, 18
        // carry that name legibly and the v2 classifier scored 5 of those
        // same 18; when the text is in frame it is simply the better signal.
        // It stays silent when there is no text, so the classifier path is
        // unchanged for every other photo.
        machineTextRecogniserProvider.overrideWith((ref) {
          final r = MlKitMachineTextRecogniser();
          ref.onDispose(r.dispose);
          return r;
        }),

        // Live (continuous) recognition. Attaches the labeler to the Scan
        // tab's camera session -- it owns no camera of its own, so the
        // viewfinder keeps working when it detaches.
        liveEquipmentServiceProvider.overrideWith((ref) {
          final svc = MlKitLiveEquipmentService(
            session: ref.watch(scanCameraSessionProvider),
            // B5b, live. Reads the machine's printed name off the viewfinder
            // every 8th frame and answers immediately when it names exactly
            // one machine. This is where the anchor is worth the most: the
            // user is standing in front of the shroud with the camera on it.
            //
            // Both are null/empty until the catalogue loads, and the service
            // treats that as "no anchor" and runs the classifier alone — the
            // same standing-down it does everywhere else.
            textRecogniser: ref.watch(machineTextRecogniserProvider),
            catalogue: {
              for (final e in ref.watch(equipmentListProvider).valueOrNull ??
                  const [])
                e.id: e.name,
            },
          );
          ref.onDispose(svc.dispose);
          return svc;
        }),

        // Every machine the user identifies is remembered (one row per
        // machine, newest sighting wins).
        recognitionHistoryRepositoryProvider
            .overrideWith((_) => FirestoreRecognitionHistoryRepository()),

        // A machine the catalog has no page for still gets an answer: a
        // second question to the model about the same photo, turned into a
        // card the user sees marked «контент готовится». The same rows tell
        // us what people actually stand in front of, which is what decides
        // the order we film missing clips in.
        machineDescriberProvider.overrideWith((_) => GeminiMachineDescriber()),
        machineCardRepositoryProvider
            .overrideWith((_) => FirestoreMachineCardRepository()),

        // Gate G / MRD-03-05: the user's own setup reminders, per
        // (equipment type, gym).
        equipmentSetupNoteRepositoryProvider
            .overrideWith((_) => FirestoreEquipmentSetupNoteRepository()),

        // AI-generated exercises for machines the vendored catalog has
        // nothing for -- cached per (user, machine, language) so a machine
        // is billed to Gemini once, not on every page visit.
        generatedExerciseRepositoryProvider
            .overrideWith((_) => FirestoreGeneratedExerciseRepository()),

        // Marketplace — Stripe Connect via Cloud Functions.
        //
        // `coachListingRepositoryProvider` is deliberately NOT overridden
        // here yet (M0). It stays `MockCoachListingRepository`, and
        // `marketplaceListingsAreDemoProvider` checks that binding to show
        // the demo banner and disable booking taps. When a real listing
        // repository is wired, override it in the SAME change as this one —
        // wiring only one of the two would leave the demo banner claiming
        // "booking is disabled" while a real backend call is reachable, or
        // real listings tappable against a service that still 404s.
        coachMarketplaceServiceProvider
            .overrideWith((_) => CloudCoachMarketplaceService()),

        // Wear OS — phone-side bridge to the watch APK.
        wearSyncServiceProvider
            .overrideWith((_) => MethodChannelWearSyncService()),

        // Data export (L0c) — writes a temp file and opens the OS share
        // sheet. Mock by default so widget tests never touch the
        // share_plus/path_provider platform channels.
        dataExportSinkProvider.overrideWith((_) => ShareDataExportSink()),

        // A3 — the server half of the export. Real only here: the default
        // provider returns nothing, so a widget test can never reach the
        // backend, the same shape as the sink override above.
        serverExportProvider.overrideWith((_) => CloudFunctionsServerExport()),

        // Account deletion (L0b) — calls the deleteAccount Cloud Function.
        accountDeletionServiceProvider
            .overrideWith((_) => CloudFunctionsAccountDeletionService()),

        // A1 — the on-device half of the same operation. Real implementation
        // only here: the default provider records instead of deleting, so a
        // widget test can never wipe the host machine's documents directory.
        localDataWipeProvider.overrideWith((_) => DeviceLocalDataWipe()),

        // Nurture moments + notifications.
        momentRepositoryProvider.overrideWithValue(momentRepo),
        notificationServiceProvider.overrideWithValue(notifications),

        // Device preferences (theme, language, reminders).
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        initialSettingsProvider.overrideWithValue(settings),
      ],
      child: const FitnessApp(),
    ),
  );
}

class FitnessApp extends ConsumerStatefulWidget {
  const FitnessApp({super.key});

  @override
  ConsumerState<FitnessApp> createState() => _FitnessAppState();
}

/// Stateful to observe [didChangeLocales] and, since P2.G5-readiness step 3b,
/// [didChangeAppLifecycleState].
///
/// Without the locale observer, changing the device language while the app is
/// running would move the interface but not the bundled exercise text,
/// because the content side reads a cached device-locale list. That is the
/// same half-translated failure `resolvedLocaleCode` exists to prevent, just
/// triggered at runtime.
class _FitnessAppState extends ConsumerState<FitnessApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    ref.read(deviceLocalesProvider.notifier).state =
        List<Locale>.unmodifiable(locales ?? const <Locale>[]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retry every queued equipment-identity telemetry report on resume --
    // see `drainEquipmentIdentityTelemetryOutbox`'s own doc comment for why
    // resume is the signal this app uses in place of a real connectivity
    // event. Fire-and-forget, same posture as the sends themselves: a
    // drain must never block or fail the resume it is riding on.
    if (state == AppLifecycleState.resumed) {
      unawaited(drainEquipmentIdentityTelemetryOutbox(ref));
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final settings = ref.watch(settingsControllerProvider);
    // Resolved, never nullable: one source of truth shared with the exercise
    // catalog. Passing `null` here would hand resolution to Flutter alone and
    // leave the content layer guessing what it decided.
    final localeCode = ref.watch(effectiveLanguageCodeProvider);
    return MaterialApp.router(
      // NOT localised, on purpose twice over: it is the brand name, and
      // this widget builds the MaterialApp, so there is no Localizations
      // ancestor here yet — AppLocalizations.of(context) returns null and
      // the non-nullable getter crashes on launch. Use onGenerateTitle if a
      // translated title is ever wanted.
      title: 'Fitness App',
      // Russian is the product default (the launch market is RU/CIS), but the
      // user can override it in Settings; "system" is resolved against the
      // device locales by `effectiveLanguageCodeProvider`.
      locale: Locale(localeCode),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales:
          kSupportedLocaleCodes.map((c) => Locale(c)).toList(growable: false),
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode.material,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _GlassScrollBehavior(),
      builder: (context, child) => _InputTraceListener(
        child: AuroraBackground(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

/// TEMPORARY -- re-added live first-interaction trace (D-03/D-05B/MainShell
/// bottom-nav first-tap failures, SPTR_FINAL_AUTONOMOUS_PROGRAM section 5;
/// re-added per core/DECISION_LOG.md's 2026-08-21 correction entry after this
/// investigation's premature closure).
///
/// STAGE A/B only: confirms a raw pointer event reached the Flutter engine at
/// all, independent of which widget it eventually hits. Debug-only -- remove
/// once the failing stage is identified and fixed, this is not meant to ship.
class _InputTraceListener extends StatelessWidget {
  const _InputTraceListener({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => debugPrint(
          'TRACE stageA down id=${e.pointer} t=${e.timeStamp.inMilliseconds}'),
      onPointerUp: (e) => debugPrint(
          'TRACE stageA up   id=${e.pointer} t=${e.timeStamp.inMilliseconds}'),
      child: child,
    );
  }
}

class _GlassScrollBehavior extends ScrollBehavior {
  const _GlassScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}
