/// Providers of the body-scan data layer (C14). Defaults are the safe,
/// device-only ones (in-memory stores, the callable client constructed lazily,
/// the fail-closed face check), so a default build performs no network call;
/// the app root overrides the repository, settings and plan/trend ports with
/// the real implementations.
///
/// Bridging that body_scan deliberately does NOT do (D-71): it never imports
/// the nutrition review state. [scanCompletedProvider] is bumped when a scan
/// reaches `done`; the app root listens to it and bumps
/// `scanDoneSignalProvider`.
library;

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/body_scan_flags.dart';
import '../../account_deletion/state/account_deletion_providers.dart'
    show accountBeingDeletedUidProvider;
import '../../auth/state/auth_providers.dart';
import '../../nutrition_plan/data/energy_math.dart';
import '../../nutrition_plan/data/weight_entry.dart';
import '../../nutrition_plan/state/weight_providers.dart';
import '../../profile/state/profile_providers.dart';
import '../../progress_photos/scan/scan_models.dart';
import '../../progress_photos/scan/scan_repository.dart';
import '../../progress_photos/scan/ui/scan_compare_screen.dart'
    show deleteScanFiles;
import '../../progress_photos/state/progress_photos_providers.dart';
import '../data/body_scan_entry.dart';
import '../data/body_scan_repository.dart';
import '../data/face_check_port.dart';
import '../data/provisional_estimator.dart';
import '../data/scan_trend.dart';
import 'blur_service.dart';
import 'body_scan_api.dart';
import 'body_scan_job_runner.dart';
import 'body_scan_settings.dart';
import 'firestore_body_scan_repository.dart';
import 'photo_upload_port.dart';
import 'scan_result_source.dart';
import 'scan_trend_source.dart';

// ---- ports with safe defaults -------------------------------------------

/// Server scan history. Default: in-memory (empty). The app root overrides it
/// with `FirestoreBodyScanRepository(uid: ...)` when the cloud path is built.
final bodyScanRepositoryProvider = Provider<BodyScanRepository>((ref) {
  final repo = InMemoryBodyScanRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// The callable client. Constructing it touches no Firebase API.
final bodyScanApiProvider =
    Provider<BodyScanApi>((_) => CallableBodyScanApi());

final photoUploadPortProvider =
    Provider<PhotoUploadPort>((_) => DioPhotoUploadPort());

final blurServiceProvider =
    Provider<BlurService>((_) => const IsolateBlurService());

/// FAIL CLOSED default (D-69): "cannot verify", so no PUT ever happens until a
/// real detector is bound.
final faceCheckPortProvider =
    Provider<FaceCheckPort>((_) => const UnavailableFaceCheck());

/// Settings storage. Default: in-memory; the app root overrides it with the
/// Firestore store.
final bodyScanSettingsStoreProvider =
    Provider<BodyScanSettingsStore>((_) => InMemoryBodyScanSettingsStore());

/// The settings (retention, consent, paused); defaults while signed out.
final bodyScanSettingsProvider =
    StreamProvider<BodyScanSettings>((ref) async* {
  final user = await ref.watch(authUserProvider.future);
  if (user == null) {
    yield const BodyScanSettings();
    return;
  }
  yield* ref.watch(bodyScanSettingsStoreProvider).watch();
});

/// Server scan documents, newest first; empty while signed out.
final bodyScanEntriesProvider =
    StreamProvider<List<BodyScanEntry>>((ref) async* {
  final user = await ref.watch(authUserProvider.future);
  if (user == null) {
    yield const [];
    return;
  }
  yield* ref.watch(bodyScanRepositoryProvider).watchEntries();
});

// ---- trend ---------------------------------------------------------------

/// The segmented, smoothed trend over every scan, local and server, one series
/// per estimator (D-54).
final scanTrendProvider = Provider<ScanTrend>((ref) {
  final records = ref.watch(scanHistoryProvider).valueOrNull ?? const <ScanRecord>[];
  final entries =
      ref.watch(bodyScanEntriesProvider).valueOrNull ?? const <BodyScanEntry>[];
  return computeScanTrend(readingsFrom(records: records, entries: entries));
});

/// The `BodyFatTrendSource` for the weekly review (D-71). Bound at the app
/// root: `bodyFatTrendSourceProvider.overrideWith((ref) =>
/// ref.watch(scanBodyFatTrendSourceProvider))`.
final scanBodyFatTrendSourceProvider = Provider<ScanBodyFatTrendSource>(
  (ref) => ScanBodyFatTrendSource(ref.watch(scanTrendProvider)),
);

// ---- completion signal ----------------------------------------------------

/// Bumped once per scan that reaches `done`. The app root bridges it to the
/// nutrition `scanDoneSignalProvider`.
final scanCompletedProvider = StateProvider<int>((_) => 0);

// ---- runner ----------------------------------------------------------------

/// The one job runner of the signed-in account; null while signed out. Call
/// `ref.read(bodyScanRunnerProvider)?.resume()` on app foreground and when
/// Progress opens. It rebuilds (and the old one is disposed) when the account
/// or the flags change.
final bodyScanRunnerProvider = Provider<BodyScanJobRunner?>((ref) {
  final uid = ref.watch(authUserProvider).valueOrNull?.uid;
  if (uid == null || uid.isEmpty) return null;
  final flags = ref.watch(bodyScanFlagsProvider);
  final scans = ref.watch(scanRepositoryProvider);

  bool accountChanged() {
    try {
      if (ref.read(accountBeingDeletedUidProvider) == uid) return true;
      return ref.read(authUserProvider).valueOrNull?.uid != uid;
    } catch (_) {
      // A disposed scope is as good as a changed account.
      return true;
    }
  }

  final runner = BodyScanJobRunner(
    scans: scans,
    flags: flags,
    api: ref.read(bodyScanApiProvider),
    uploader: ref.read(photoUploadPortProvider),
    blur: ref.read(blurServiceProvider),
    faceCheck: ref.read(faceCheckPortProvider),
    now: ref.read(nutritionClockProvider),
    settings: () =>
        ref.read(bodyScanSettingsProvider).valueOrNull ?? const BodyScanSettings(),
    accountChanged: accountChanged,
    readPhoto: (photoId) async {
      final repo = ref.read(progressPhotosRepositoryProvider);
      final photos = await repo.watch().first;
      for (final p in photos) {
        if (p.id == photoId) return repo.bytesOf(p);
      }
      return null;
    },
    resolveSubject: (rec) async => _subjectFor(ref, rec),
    subjectPending: (rec) => _subjectInputsLoading(ref, rec),
    // An owed photos-only server delete finished: the phone copy goes too.
    onRemoteDeleteFlushed: (rec) => deleteScanFiles(ref.read, rec),
    onChanged: () {
      try {
        ref.invalidate(scanHistoryProvider);
      } catch (e) {
        debugPrint('body scan: history refresh skipped (${e.runtimeType})');
      }
    },
    onScanDone: (_) {
      try {
        ref.read(scanCompletedProvider.notifier).state++;
      } catch (_) {}
    },
    // Only a scrubbed slug arrives here (D-67); it is logged, never the raw
    // exception.
    onError: (scrubbed) => debugPrint('body scan: $scrubbed'),
  );
  ref.onDispose(runner.dispose);
  // The estimate needs the profile (and the weight log): a scan that waited
  // for them (`subjectPending`) is picked up as soon as they have loaded.
  void resumeWhenLoaded(bool wasLoaded, bool isLoaded) {
    if (isLoaded && !wasLoaded) {
      unawaited(runner.resume().catchError((Object e) {
        debugPrint('body scan: resume failed (${e.runtimeType})');
      }));
    }
  }

  ref.listen(currentProfileProvider, (previous, next) =>
      resumeWhenLoaded(previous?.hasValue ?? false, next.hasValue));
  ref.listen(weightEntriesProvider, (previous, next) =>
      resumeWhenLoaded(previous?.hasValue ?? false, next.hasValue));
  return runner;
});

/// True while the profile (or, for a scan without a recorded weight, the weight
/// log) is still loading: the run must wait, not fail with `subject-missing`.
bool _subjectInputsLoading(Ref ref, ScanRecord rec) {
  try {
    final profile = ref.read(currentProfileProvider);
    if (profile.isLoading && !profile.hasValue) return true;
    if (rec.weightKg == null) {
      final weights = ref.read(weightEntriesProvider);
      if (weights.isLoading && !weights.hasValue) return true;
    }
  } catch (_) {
    // A disposed scope: the account fence handles it.
  }
  return false;
}

/// Height, age, sex and weight for the estimate; null when any is missing
/// (the run then fails closed with `subject-missing`). Weight: the one recorded
/// for the scan, else the single current weight (D-72).
EstimatorSubject? _subjectFor(Ref ref, ScanRecord rec) {
  final profile = ref.read(currentProfileProvider).valueOrNull;
  if (profile == null) return null;
  final height = profile.personal.heightCm;
  final age = profile.personal.ageAt(rec.createdAt.year);
  final sex = resolveSexBasis(profile);
  final weight = rec.weightKg ?? ref.read(currentWeightProvider)?.kg;
  if (height == null || age == null || sex == null || weight == null) {
    return null;
  }
  if (!WeightEntry.isValidKg(weight)) return null;
  return EstimatorSubject(
    heightCm: height.toDouble(),
    weightKg: weight,
    ageYears: age,
    sex: sex,
  );
}

// ---- result source ---------------------------------------------------------

/// Resolves one scan result from the local record and, on the cloud path, the
/// server document (the server copy wins). Bound at the app root:
/// `scanResultSourceProvider.overrideWith((ref) =>
/// ref.watch(dataScanResultSourceProvider))`. Strength-session counts come
/// from the training feature and stay null here.
class DataScanResultSource extends ScanResultSource {
  const DataScanResultSource(this._ref);

  final Ref _ref;

  @override
  Future<ScanResultData?> load(String scanId) async {
    final records = await _ref.read(scanRepositoryProvider).list();
    final entries = _ref.read(bodyScanEntriesProvider).valueOrNull ??
        const <BodyScanEntry>[];
    ScanRecord? rec;
    for (final r in records) {
      if (r.id == scanId || r.remoteId == scanId) rec = r;
    }
    BodyScanEntry? entry;
    for (final e in entries) {
      if (e.scanId == scanId || (rec != null && e.scanId == rec.remoteId)) {
        entry = e;
      }
    }
    final estimate =
        (entry != null && entry.hasResult ? entry.estimate : null) ??
            rec?.analysis?.estimate;
    final takenAt = entry?.takenAt ?? rec?.createdAt;
    // No estimate yet (queued or failed): there is no result to show; the
    // resume card and the terminal-failure actions (D-78) read the record.
    if (estimate == null || takenAt == null) return null;
    final weights =
        _ref.read(weightEntriesProvider).valueOrNull ?? const <WeightEntry>[];
    return ScanResultData(
      scanId: scanId,
      takenAt: takenAt,
      estimate: estimate,
      weightKg: entry?.weightKg ?? rec?.weightKg,
      readings: readingsFrom(records: records, entries: entries),
      weightSlopeKgPerWeek: weightSlopeKgPerWeek(weights),
    );
  }
}

final dataScanResultSourceProvider =
    Provider<ScanResultSource>((ref) => DataScanResultSource(ref));
