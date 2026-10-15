/// App-root wiring between Body Scan and the Nutrition Coach (D-71, SD-9).
///
/// body_scan never imports the nutrition review state and the nutrition
/// feature never imports body_scan internals, so every bridge between them
/// lives here, at the root, and is the ONLY place that knows both sides:
///
///  * ports: the scan plan context, the body-fat trend and the scan result
///    source are bound to their real implementations;
///  * `scanCompletedProvider` (body_scan) -> `scanDoneSignalProvider`
///    (nutrition weekly review);
///  * the job runner is resumed on sign-in, on app foreground
///    ([resumeBodyScanRunner]) and when the Progress tab opens;
///  * the Firestore repository and settings store replace the in-memory
///    defaults only when the cloud path is compiled in (`BODY_SCAN_CLOUD`).
library;

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/state/auth_providers.dart';
import '../../features/body_scan/data/body_scan_repository.dart';
import '../../features/body_scan/state/body_scan_providers.dart';
import '../../features/body_scan/state/body_scan_settings.dart';
import '../../features/body_scan/state/firestore_body_scan_repository.dart';
import '../../features/body_scan/state/scan_plan_context_provider.dart';
import '../../features/body_scan/state/scan_result_source.dart';
import '../../features/nutrition_plan/state/nutrition_providers.dart'
    show bodyFatTrendSourceProvider;
import '../../features/nutrition_plan/state/review_scheduler.dart'
    show scanDoneSignalProvider, weeklyReviewTriggersProvider;
import '../../features/nutrition_plan/state/scan_plan_context_source.dart';
import '../config/body_scan_flags.dart';
import '../router/app_router.dart';

/// Provider overrides for the `ProviderScope` in `main.dart`.
List<Override> bodyScanRootOverrides({
  BodyScanFlags flags = BodyScanFlags.compileTime,
}) {
  return [
    // The real plan context replaces the measurement-only placeholder.
    scanPlanContextProvider
        .overrideWith((ref) => ref.watch(nutritionScanPlanContextSourceProvider)),
    bodyFatTrendSourceProvider
        .overrideWith((ref) => ref.watch(scanBodyFatTrendSourceProvider)),
    scanResultSourceProvider
        .overrideWith((ref) => ref.watch(dataScanResultSourceProvider)),
    // Server history and settings exist only on the cloud path; without the
    // flag the in-memory defaults stay and nothing touches Firestore.
    if (flags.cloudPhotos) ...[
      bodyScanRepositoryProvider.overrideWith((ref) {
        final uid = ref.watch(authUserProvider).valueOrNull?.uid;
        if (uid == null || uid.isEmpty) {
          final repo = InMemoryBodyScanRepository();
          ref.onDispose(repo.dispose);
          return repo;
        }
        return FirestoreBodyScanRepository(uid: uid);
      }),
      bodyScanSettingsStoreProvider.overrideWith((ref) {
        final uid = ref.watch(authUserProvider).valueOrNull?.uid;
        if (uid == null || uid.isEmpty) return InMemoryBodyScanSettingsStore();
        return FirestoreBodyScanSettingsStore(uid: uid);
      }),
    ],
  ];
}

/// Resumes the queued scans of the signed-in account. Never throws.
void resumeBodyScanRunner(WidgetRef ref) {
  try {
    _observe(ref.read(bodyScanRunnerProvider)?.resume());
  } catch (e) {
    debugPrint('body scan: resume skipped (${e.runtimeType})');
  }
}

/// A fire-and-forget runner call must never fail unobserved.
void _observe(Future<void>? call) {
  if (call == null) return;
  unawaited(call.catchError((Object e) {
    debugPrint('body scan: resume failed (${e.runtimeType})');
  }));
}

/// Keep-alive wiring: watch it once from the app root widget.
final bodyScanRootWiringProvider = Provider<void>((ref) {
  // Keeps the weekly-review scan trigger listening (nobody else watches it).
  ref.watch(weeklyReviewTriggersProvider);

  // A finished scan runs the weekly review once (idempotent per week).
  ref.listen<int>(scanCompletedProvider, (previous, next) {
    ref.read(scanDoneSignalProvider.notifier).state++;
  });

  void resume() {
    try {
      _observe(ref.read(bodyScanRunnerProvider)?.resume());
    } catch (e) {
      debugPrint('body scan: resume skipped (${e.runtimeType})');
    }
  }

  // Sign-in (the runner appears) and account or flag changes.
  ref.listen(bodyScanRunnerProvider, (previous, next) {
    if (next != null) resume();
  }, fireImmediately: true);

  // "Progress opens": one place, no edit to the page. The router location is
  // watched and the runner resumes on entering /progress.
  final router = ref.watch(appRouterProvider);
  final location = router.routeInformationProvider;
  var inProgress = false;
  void onRoute() {
    final now = location.value.uri.path == '/progress';
    if (now && !inProgress) resume();
    inProgress = now;
  }

  location.addListener(onRoute);
  ref.onDispose(() => location.removeListener(onRoute));
});
