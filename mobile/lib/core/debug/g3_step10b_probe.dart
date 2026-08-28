import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// MVP1.G3 Step 10B fault-injection harness -- see DECISION_LOG.md.
///
/// Every flag below is `const`, derived from a `--dart-define` that defaults
/// to off. In every normal build (debug, profile, the real shipped release)
/// [kEnabled] folds to `false` at compile time, which makes every
/// `if (G3Step10bProbe.kEnabled && ...)` guard in the app dead code the
/// compiler removes -- this file changes nothing about a production build's
/// behavior, size, or reachable surface.
///
/// This is NOT a shortcut that calls Crashlytics directly for a scenario.
/// Each flag injects a fault at the real dependency boundary (the camera
/// controller, the on-device OCR call, the cloud recognition call) so the
/// app's OWN production catch/report logic -- the exact code this step
/// exists to prove -- is what decides whether, and how, to tell Crashlytics.
/// A probe build that skipped that and called `recordError` straight from a
/// test button would prove Crashlytics works, not that this app's telemetry
/// wiring works. GPT-PM's own words, MVP1.G3 Step 10B methodology round.
class G3Step10bProbe {
  const G3Step10bProbe._();

  /// Master switch. Every other flag below is `&& kEnabled`, so a probe build
  /// that forgets to also pass a specific fault flag still behaves exactly
  /// like production -- there is no way to reach an injected fault from a
  /// normal build no matter which defines are missing.
  static const bool kEnabled =
      bool.fromEnvironment('G3_STEP10B_PROBE', defaultValue: false);

  /// Throws inside `CameraSession._open()`, immediately before the real
  /// `CameraController.initialize()` call. Caught by the same code a genuine
  /// hardware/init failure would hit, classified by the app's own
  /// `classifyCameraFailure` as `initializationFailed` -- indistinguishable,
  /// from that point on, from a real failure.
  static const bool forceCameraInitFailure = kEnabled &&
      bool.fromEnvironment('G3_STEP10B_CAMERA_INIT_FAIL', defaultValue: false);

  /// Throws inside `MlKitLiveEquipmentService`'s live OCR anchor, immediately
  /// before the real ML Kit `readFrame` call. The service's own
  /// once-per-session dedupe (`_ocrAnchorFailureReported`) is untouched --
  /// this only makes the underlying call fail, every time it is attempted.
  static const bool forceOcrFailure = kEnabled &&
      bool.fromEnvironment('G3_STEP10B_OCR_FAIL', defaultValue: false);

  /// Throws inside `GeminiVisualEquipmentService.classifyFile`, before the
  /// real cloud call -- exercises the same catch/report path a genuine
  /// network or API failure would.
  static const bool forceInferenceFailure = kEnabled &&
      bool.fromEnvironment('G3_STEP10B_INFERENCE_FAIL', defaultValue: false);

  /// Delay injected AT the `_askCloud()` dependency boundary, standing in
  /// for real network/Gemini latency -- the real `aiEquipmentRecognition`
  /// Cloud Function is not deployed in this environment (an AI Gateway
  /// callable deliberately held back for a future gate), so there is no
  /// real successful call to pad. After the delay, a well-formed canned
  /// success is returned so the real production Stopwatch/threshold/parse/
  /// display path downstream runs unmodified and genuinely completes.
  static const int injectedInferenceDelaySeconds =
      kEnabled ? int.fromEnvironment('G3_STEP10B_INFERENCE_DELAY_S') : 0;

  /// When true, [recordError] below throws instead of forwarding to the real
  /// Crashlytics SDK. Every production call site now goes through
  /// [recordError] rather than `FirebaseCrashlytics.instance.recordError`
  /// directly, so this proves the app survives its OWN telemetry call
  /// failing -- isolated from Crashlytics' real, unforgeable internals,
  /// which cannot be made to throw from application code.
  static const bool forceTelemetryFacadeFailure = kEnabled &&
      bool.fromEnvironment('G3_STEP10B_TELEMETRY_FAIL', defaultValue: false);

  /// The exact working-tree identity this probe build was compiled from --
  /// GPT-PM's MVP1.G3 Step 10B review found that several probe APKs were
  /// rebuilt across a live production fix (the 20s/20s timeout defect,
  /// `core/DECISION_LOG.md`) with no way to tell, from a backend event alone,
  /// which build produced it. Passed via `--dart-define=G3_STEP10B_SOURCE_SHA=...`
  /// at build time (a working-tree identity, e.g. `git rev-parse HEAD` plus a
  /// `-dirty` suffix if uncommitted -- never a later commit that did not exist
  /// when the APK was actually compiled). Empty in every normal build.
  static const String sourceSha =
      String.fromEnvironment('G3_STEP10B_SOURCE_SHA', defaultValue: '');

  /// Attaches [sourceSha] (and a run id, if the caller wants one distinct per
  /// launch) as Crashlytics custom keys, so a backend event carries its own
  /// build provenance instead of relying on out-of-band correlation. Only
  /// meaningful -- and only called -- when [kEnabled] is true; a normal build
  /// has an empty [sourceSha] and no reason to set the key at all.
  static Future<void> attachBuildProvenance() async {
    if (!kEnabled || sourceSha.isEmpty) return;
    await FirebaseCrashlytics.instance
        .setCustomKey('g3_step10b_source_sha', sourceSha);
  }

  /// Routes the three non-fatal Crashlytics `recordError` call sites this
  /// step actually exercises (camera-init failure, OCR anchor failure, cloud
  /// recognition failure/slow-inference). main.dart's fatal-error handlers
  /// are untouched -- outside this step's scope. Identical to calling the
  /// SDK directly whenever [kEnabled] is false (i.e. every real build) or
  /// [forceTelemetryFacadeFailure] is false.
  static Future<void> recordError(
    dynamic exception,
    StackTrace? stack, {
    bool fatal = false,
    String? reason,
  }) {
    if (forceTelemetryFacadeFailure) {
      return Future<void>.error(
        StateError('G3_STEP10B_PROBE: injected Crashlytics facade failure'),
      );
    }
    return FirebaseCrashlytics.instance.recordError(
      exception,
      stack,
      fatal: fatal,
      reason: reason,
    );
  }
}
