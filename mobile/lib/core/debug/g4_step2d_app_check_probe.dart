import 'package:flutter/foundation.dart' show debugPrint;

import '../firebase/functions_region.dart';

/// MVP1.G4 Step 2, Option D -- real-device App Check attestation proof. Same
/// dead-code-when-off shape as [G3Step10bProbe] (`core/debug/g3_step10b_probe.dart`):
/// [kEnabled] is a `const` folded from `--dart-define`, defaulting to `false`,
/// so every normal build -- debug, profile, and the real shipped release --
/// compiles this out entirely and calls nothing.
///
/// What it proves: whether a release-signed APK, installed through the
/// actual outside-Play channel this project ships testers through (Firebase
/// App Distribution, or a direct install of that same signed artifact), can
/// pass Play Integrity attestation once `enforceAppCheck: true` is on for a
/// callable. `functions/src/app_check_probe.ts` is the temporary no-Vertex
/// callable this calls -- it rejects at the platform level before its
/// handler body runs if attestation fails, so a client-visible
/// success/failure on this one call IS the proof. Neither file is part of
/// the permanent surface; both are deleted once
/// `core/G4_STEP2_APP_CHECK_BOUNDARY_2026-08-28.md` records the result.
class G4Step2dAppCheckProbe {
  const G4Step2dAppCheckProbe._();

  static const bool kEnabled = bool.fromEnvironment(
    'G4_STEP2D_APP_CHECK_PROBE',
    defaultValue: false,
  );

  /// Working-tree identity this probe build was compiled from -- same
  /// provenance discipline G3 Step 10B's review required, after that gate
  /// found probe APKs rebuilt across a live fix with no way to tell which
  /// build produced a given result. Passed via
  /// `--dart-define=G4_STEP2D_SOURCE_SHA=<git rev-parse HEAD, +-dirty>`.
  static const String sourceSha = String.fromEnvironment(
    'G4_STEP2D_SOURCE_SHA',
    defaultValue: '',
  );

  /// Fires once, shortly after `FirebaseAppCheck.instance.activate()`
  /// resolves in `main()`. `debugPrint` reaches `adb logcat` (tag `flutter`)
  /// on a real device in every build mode, including release -- it is not
  /// gated by `kDebugMode` the way `print` guidance elsewhere in this file
  /// might suggest.
  static Future<void> run() async {
    if (!kEnabled) return;
    debugPrint('G4_STEP2D_PROBE: calling appCheckProbe (sourceSha=$sourceSha)');
    try {
      final result =
          await functionsForRegion.httpsCallable('appCheckProbe').call();
      debugPrint('G4_STEP2D_PROBE: RESULT ok=${result.data}');
    } catch (e, st) {
      debugPrint('G4_STEP2D_PROBE: FAILED $e');
      debugPrint('G4_STEP2D_PROBE: STACK $st');
    }
  }
}
