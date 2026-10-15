/// The scan job runner (design s10, D-52, D-69): executes the effects of the
/// scan flow for the persisted queue.
///
/// The queue IS the set of v2 [ScanRecord]s whose `analysis.status` is not
/// terminal; legacy (v1) scans are never touched (D-6). The runner is
/// re-entered on app foreground, when Progress opens and from its own retry
/// timer (`connectivity_plus` is not a dependency); it never runs in a
/// background isolate. ONE scan at a time; a second scan taken meanwhile waits.
///
/// Two paths:
///  * LOCAL (default; `BODY_SCAN_CLOUD` off, no consent, or no photo provider):
///    the provisional estimate is computed on the device with ZERO callable and
///    ZERO PUT calls, works offline and never reads a photo (D-52).
///  * CLOUD (only when the flag is on AND consent is current AND the server
///    reports a provider that needs photos): create, blur on device, face-check
///    the BLURRED bytes (fail closed, D-69), PUT, estimate, verify. A scan that
///    the server tombstoned (`scan-cancelled`) rotates its `remoteId` and is
///    re-queued, never a permanent error.
///
/// Every write is fenced by [accountChanged] and a per-scan cancel set, so a
/// sign-out, an account deletion or a user cancel mid-run can neither recreate
/// data nor overwrite a cancel. Errors are stored as closed slugs (D-67).
library;

import 'dart:async';
import 'dart:typed_data';

import '../../../core/config/body_scan_flags.dart';
import '../../progress_photos/scan/scan_models.dart';
import '../../progress_photos/scan/scan_pose.dart';
import '../../progress_photos/scan/scan_repository.dart';
import '../data/body_fat_estimate.dart';
import '../data/body_scan_job.dart';
import '../data/check_items.dart';
import '../data/face_check_port.dart';
import '../data/plausibility.dart';
import '../data/provisional_estimator.dart';
import 'blur_service.dart';
import 'body_scan_api.dart';
import 'body_scan_settings.dart';
import 'photo_upload_port.dart';
import 'scrubbed_error.dart';

class _Stop implements Exception {
  const _Stop();
}

/// The inputs of the estimate (profile, weight) are still loading: the scan
/// stays queued and untouched, it is never failed for data that has not
/// arrived yet.
class _NotReady implements Exception {
  const _NotReady();
}

/// Everything the runner needs, injected so tests drive it without a device.
class BodyScanJobRunner {
  BodyScanJobRunner({
    required this.scans,
    required this.readPhoto,
    required this.api,
    required this.uploader,
    required this.blur,
    required this.faceCheck,
    required this.flags,
    required this.settings,
    required this.resolveSubject,
    required this.accountChanged,
    required this.now,
    this.onChanged,
    this.onScanDone,
    this.onError,
    this.subjectPending,
    this.onRemoteDeleteFlushed,
    this.estimator = const ProvisionalEstimator(),
  });

  final ScanRepository scans;

  /// Decrypted pixels of a stored photo id; null when it cannot be read.
  final Future<Uint8List?> Function(String photoId) readPhoto;
  final BodyScanApi api;
  final PhotoUploadPort uploader;
  final BlurService blur;
  final FaceCheckPort faceCheck;
  final BodyScanFlags flags;
  final BodyScanSettings Function() settings;

  /// The subject for [record]: its recorded weight, else the current weight.
  /// Null when height, age or sex is missing (the run then fails closed).
  final Future<EstimatorSubject?> Function(ScanRecord record) resolveSubject;

  /// True when the initiating account is gone or being deleted.
  final bool Function() accountChanged;
  final DateTime Function() now;

  /// Called after any record changed (invalidate the history provider).
  final void Function()? onChanged;

  /// Called once per scan that reached `done` (the weekly review signal).
  final void Function(String scanId)? onScanDone;

  /// Receives ONLY a scrubbed slug wrapped in an exception, never the raw one.
  final void Function(Object scrubbed)? onError;

  /// True while the profile or weight that [resolveSubject] needs is still
  /// loading. A null subject is then "not ready" (the scan stays queued) and
  /// never `subject-missing`, which is reserved for a loaded profile that lacks
  /// data. The app root resumes the runner once the inputs have loaded.
  final bool Function(ScanRecord record)? subjectPending;

  /// Called after an owed PHOTOS-ONLY server delete succeeded: removes the
  /// phone copy of the scan (photos and record). Without it the owed flag is
  /// just cleared.
  final Future<void> Function(ScanRecord record)? onRemoteDeleteFlushed;
  final BodyCompositionEstimator estimator;

  bool _busy = false;
  bool _rerun = false;
  bool _disposed = false;
  Timer? _timer;
  final Set<String> _stopped = {};

  bool get isBusy => _busy;

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }

  // ---- public entry points ---------------------------------------------

  /// Resumes the queue. Safe to call often: a second call while one runs only
  /// asks the running one to take another pass when it finishes (one scan at a
  /// time), so a retry timer that fires while the runner is busy is never lost.
  /// Never throws: a failure becomes a failed/requeued scan or a scrubbed
  /// [onError] report.
  Future<void> resume() async {
    if (_disposed) return;
    if (_busy) {
      _rerun = true;
      return;
    }
    _busy = true;
    try {
      do {
        _rerun = false;
        await _runOnce();
      } while (_rerun && !_disposed);
    } finally {
      _busy = false;
    }
  }

  Future<void> _runOnce() async {
    try {
      await _flushPendingDeletes();
      final all = await scans.list();
      final queue = [
        for (final r in all)
          if (_resumable(r)) r,
      ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (final rec in queue) {
        if (_disposed || accountChanged()) return;
        final due = _dueAt(rec);
        if (due != null && due.isAfter(now())) continue;
        try {
          await _process(rec, all);
        } on _Stop {
          // This scan was cancelled or deleted, or the account changed (the
          // next iteration then ends the run): carry on with the others.
        }
      }
    } catch (e) {
      _report(e);
    } finally {
      await _rescheduleFromQueue();
    }
  }

  /// User pressed Retry on a failed scan: attempts reset.
  Future<void> retry(String scanId) async {
    try {
      final rec = await _find(scanId);
      if (rec == null ||
          rec.analysis == null ||
          rec.pendingRemoteDelete ||
          accountChanged()) {
        return;
      }
      _stopped.remove(scanId);
      await scans.save(rec.copyWith(
        analysis: rec.analysis!.copyWith(
          status: JobStatus.queued,
          attempt: 0,
          clearLastError: true,
          updatedAt: now(),
        ),
      ));
      onChanged?.call();
      unawaited(resume());
    } catch (e) {
      _report(e);
    }
  }

  /// User cancel. Aborts any PUT in flight, asks the server to delete what was
  /// uploaded (queued as `pendingRemoteDelete` when that fails or the device is
  /// offline) and marks the scan cancelled. The local photos are untouched.
  Future<void> cancel(String scanId) async {
    _stopped.add(scanId);
    uploader.abortInFlight();
    try {
      final rec = await _find(scanId);
      if (rec == null || rec.analysis == null || accountChanged()) return;
      var owed = rec.pendingRemoteDelete;
      final mayHaveUploaded = flags.cloudPhotos &&
          (rec.analysis!.status == JobStatus.uploading ||
              rec.analysis!.status == JobStatus.analysing ||
              rec.analysis!.remoteStatus != null);
      if (mayHaveUploaded) {
        try {
          await api.deleteBodyScan(rec.remoteId, photosOnly: false);
          owed = false;
        } catch (e) {
          _report(e);
          owed = true;
        }
      }
      // Re-read: the record may have changed while the delete call ran, and a
      // locally deleted scan must not be written back.
      final latest = await _find(scanId);
      if (latest == null || latest.analysis == null || accountChanged()) return;
      final job = BodyScanJob(
        status: latest.analysis!.status,
        attempt: latest.analysis!.attempt,
      ).cancel();
      await scans.save(latest.copyWith(
        analysis: latest.analysis!.copyWith(
          status: job.status,
          updatedAt: now(),
        ),
        pendingRemoteDelete: owed,
        pendingPhotosOnly: false,
      ));
      onChanged?.call();
    } catch (e) {
      _report(e);
    }
  }

  /// The scan was deleted locally: no write may resurrect it.
  void forget(String scanId) {
    _stopped.add(scanId);
    uploader.abortInFlight();
  }

  // ---- queue helpers ----------------------------------------------------

  bool _resumable(ScanRecord r) {
    final a = r.analysis;
    if (a == null) return false; // legacy: never auto-uploaded (D-6)
    if (a.status.isTerminal) return false;
    // An owed server delete means the user cancelled or deleted this scan: it
    // must never run again, whatever its stored status says.
    if (r.pendingRemoteDelete) return false;
    return !_stopped.contains(r.id);
  }

  /// When a queued scan that failed before may run again.
  DateTime? _dueAt(ScanRecord r) {
    final a = r.analysis!;
    if (a.attempt <= 0 || a.updatedAt == null) return null;
    return a.updatedAt!.add(Duration(seconds: backoffSeconds(a.attempt - 1)));
  }

  void _scheduleAt(DateTime at) {
    _timer?.cancel();
    final wait = at.difference(now());
    _timer = Timer(wait.isNegative ? Duration.zero : wait, () => unawaited(resume()));
  }

  /// Arms the retry timer for the earliest backing-off scan, computed from the
  /// stored queue AFTER a pass, so a scan that failed during the pass (or one
  /// skipped as not yet due) always has a timer and none overwrites another.
  Future<void> _rescheduleFromQueue() async {
    try {
      if (_disposed || accountChanged()) return;
      DateTime? earliest;
      for (final r in await scans.list()) {
        if (!_resumable(r)) continue;
        final due = _dueAt(r);
        if (due == null) continue;
        if (earliest == null || due.isBefore(earliest)) earliest = due;
      }
      if (earliest != null && !_disposed) _scheduleAt(earliest);
    } catch (e) {
      _report(e);
    }
  }

  Future<ScanRecord?> _find(String id) async {
    for (final r in await scans.list()) {
      if (r.id == id) return r;
    }
    return null;
  }

  void _report(Object error) {
    final slug = scrubbedError(error);
    onError?.call(Exception(slug));
  }

  void _guard(String scanId) {
    if (_disposed || accountChanged() || _stopped.contains(scanId)) {
      throw const _Stop();
    }
  }

  Future<ScanRecord> _save(ScanRecord rec) async {
    _guard(rec.id);
    // Re-read before every write: a cancel or delete that landed meanwhile
    // (pendingRemoteDelete, a terminal cancelled record, or no record at all)
    // must never be overwritten by this run's older copy.
    final latest = await _find(rec.id);
    if (latest == null ||
        latest.pendingRemoteDelete ||
        latest.analysis?.status == JobStatus.cancelled) {
      throw const _Stop();
    }
    _guard(rec.id);
    await scans.save(rec);
    onChanged?.call();
    return rec;
  }

  Future<void> _flushPendingDeletes() async {
    final all = await scans.list();
    for (final r in all) {
      if (!r.pendingRemoteDelete || _disposed || accountChanged()) continue;
      try {
        await api.deleteBodyScan(r.remoteId, photosOnly: r.pendingPhotosOnly);
      } catch (e) {
        // Stays owed; retried on the next resume.
        _report(e);
        continue;
      }
      try {
        // Re-read: only the flags are cleared, never an older copy of the rest.
        final fresh = await _find(r.id);
        if (fresh == null) continue;
        final flush = onRemoteDeleteFlushed;
        if (fresh.pendingPhotosOnly && flush != null) {
          await flush(fresh);
        } else {
          // An unfinished scan whose delete was owed stays terminal: clearing
          // the flag must not make it resumable (it would recreate a remote
          // scan the user deleted).
          final a = fresh.analysis;
          await scans.save(fresh.copyWith(
            pendingRemoteDelete: false,
            pendingPhotosOnly: false,
            analysis: (a != null && !a.status.isTerminal)
                ? a.copyWith(status: JobStatus.cancelled, updatedAt: now())
                : a,
          ));
        }
        onChanged?.call();
      } catch (e) {
        // The server copy is gone but the local follow-up failed: the flag
        // stays set, so the (idempotent) delete and the follow-up repeat.
        _report(e);
      }
    }
  }

  // ---- one scan ---------------------------------------------------------

  Future<void> _process(ScanRecord start, List<ScanRecord> all) async {
    var rec = start;
    try {
      final useCloud = flags.cloudPhotos && settings().hasCurrentConsent;
      if (!useCloud) {
        await _processLocal(rec, all);
        return;
      }
      try {
        await _processCloud(rec, all);
      } on BodyScanApiException catch (e) {
        if (e.slug == 'provider-not-configured' ||
            e.slug == 'feature-disabled') {
          // Documented fallback: no photo provider, so the on-device estimate.
          await _processLocal(await _find(rec.id) ?? rec, all);
        } else {
          rethrow;
        }
      }
    } on _Stop {
      rethrow;
    } on _NotReady {
      return; // inputs still loading: stays queued, picked up on the next resume
    } catch (e) {
      _report(e);
      rec = await _find(rec.id) ?? rec;
      await _failOrRequeue(rec, e);
    }
  }

  Future<void> _failOrRequeue(ScanRecord rec, Object error) async {
    final a = rec.analysis ?? const ScanAnalysis.queued();
    final slug = scrubbedError(error);
    final retriable = error is BodyScanApiException ? error.retriable : true;
    final job = BodyScanJob(status: JobStatus.queued, attempt: a.attempt);
    final next = retriable ? job.onRetriableError(slug) : job.onFatalError(slug);
    await _save(rec.copyWith(
      analysis: a.copyWith(
        status: next.status,
        attempt: next.attempt,
        lastError: next.lastError,
        updatedAt: now(),
      ),
    ));
    // The retry timer is armed from the stored queue after the pass.
  }

  // ---- LOCAL path (D-52): no callable, no upload, works offline ----------

  Future<void> _processLocal(ScanRecord rec, List<ScanRecord> all) async {
    _guard(rec.id);
    final subject = await resolveSubject(rec);
    if (subject == null) {
      if (subjectPending?.call(rec) ?? false) throw const _NotReady();
      await _save(rec.copyWith(
        analysis: (rec.analysis ?? const ScanAnalysis.queued()).copyWith(
          status: JobStatus.failed,
          lastError: 'subject-missing',
          updatedAt: now(),
        ),
      ));
      return;
    }
    final raw = estimator is ProvisionalEstimator
        ? (estimator as ProvisionalEstimator).estimateNow(subject)
        : await estimator.estimate(
            EstimatorInput(scanId: rec.id, subject: subject));
    await _finish(rec, all, raw, remoteStatus: null);
  }

  /// Plausibility (pure) then persist `done` with the verified estimate.
  Future<void> _finish(
    ScanRecord rec,
    List<ScanRecord> all,
    BodyFatEstimate raw, {
    required String? remoteStatus,
  }) async {
    final previous = _previousOf(rec, all);
    final plaus = evaluatePlausibility(PlausibilityInput(
      estimate: raw,
      recordedWeightKg: rec.weightKg,
      previousScanWeightKg: previous?.weightKg,
      daysSincePreviousScan: previous == null
          ? null
          : rec.createdAt.difference(previous.createdAt).inHours / 24.0,
      manualOverride: rec.anyManualOverride,
    ));
    final a = rec.analysis ?? const ScanAnalysis.queued();
    if (plaus.rejected) {
      await _save(rec.copyWith(
        analysis: a.copyWith(
          status: JobStatus.failed,
          lastError: 'estimate-out-of-range',
          updatedAt: now(),
        ),
      ));
      return;
    }
    final verified =
        raw.copyWith(confidence: plaus.confidence, checkCodes: plaus.codes);
    await _save(rec.copyWith(
      analysis: a.copyWith(
        status: JobStatus.done,
        estimate: verified,
        remoteStatus: remoteStatus,
        clearLastError: true,
        updatedAt: now(),
      ),
    ));
    onScanDone?.call(rec.id);
  }

  ScanRecord? _previousOf(ScanRecord rec, List<ScanRecord> all) {
    ScanRecord? best;
    for (final r in all) {
      if (r.id == rec.id || r.analysis?.estimate == null) continue;
      if (!r.createdAt.isBefore(rec.createdAt)) continue;
      if (best == null || r.createdAt.isAfter(best.createdAt)) best = r;
    }
    return best;
  }

  // ---- CLOUD path --------------------------------------------------------

  Future<void> _processCloud(ScanRecord start, List<ScanRecord> all) async {
    var rec = start;
    var rotations = 0;
    while (true) {
      try {
        await _cloudAttempt(rec, all);
        return;
      } on BodyScanApiException catch (e) {
        if (e.isScanCancelled && rotations < 3) {
          rotations++;
          rec = await _rotateRemoteId(rec);
          continue;
        }
        rethrow;
      }
    }
  }

  Future<ScanRecord> _rotateRemoteId(ScanRecord rec) async {
    final a = rec.analysis ?? const ScanAnalysis.queued();
    final m = RegExp(r'^(.*)_r(\d+)$').firstMatch(rec.remoteId);
    final base = m == null ? rec.remoteId : m.group(1)!;
    final n = m == null ? 1 : int.parse(m.group(2)!) + 1;
    return _save(rec.copyWith(
      analysis: a.copyWith(
        remoteId: '${base}_r$n',
        status: JobStatus.queued,
        updatedAt: now(),
      ),
    ));
  }

  Future<void> _cloudAttempt(ScanRecord start, List<ScanRecord> all) async {
    var rec = start;
    final subject = await resolveSubject(rec);
    if (subject == null) {
      if (subjectPending?.call(rec) ?? false) throw const _NotReady();
      await _save(rec.copyWith(
        analysis: (rec.analysis ?? const ScanAnalysis.queued()).copyWith(
          status: JobStatus.failed,
          lastError: 'subject-missing',
          updatedAt: now(),
        ),
      ));
      return;
    }
    rec = await _save(rec.copyWith(
      analysis: rec.analysis!.copyWith(status: JobStatus.uploading, updatedAt: now()),
    ));

    Future<CreateScanResult> create() {
      _guard(rec.id);
      return api.createBodyScan(
        scanId: rec.remoteId,
        takenAt: rec.createdAt,
        sexAtBirth: subject.sex.name,
        heightCm: subject.heightCm.round(),
        weightKg: subject.weightKg,
        manualOverride: rec.manualOverride,
      );
    }

    var created = await create();
    rec = await _save(rec.copyWith(
      analysis: rec.analysis!.copyWith(remoteStatus: 'pending', updatedAt: now()),
    ));
    if (created.done && created.estimate != null) {
      await _finish(rec, all, created.estimate!, remoteStatus: 'done');
      return;
    }
    if (!created.provider.requiresPhotos) {
      // Nothing to upload for this provider; go straight to the estimate.
    } else {
      for (final pose in ScanPose.ordered) {
        var urlRetries = 0;
        while (true) {
          _guard(rec.id);
          try {
            await _uploadPose(rec, pose, created);
            break;
          } on BodyScanApiException catch (e) {
            if (e.slug == 'upload-url-expired' && urlRetries < 1) {
              urlRetries++;
              created = await create(); // fresh URLs, idempotent
              continue;
            }
            rethrow;
          }
        }
      }
    }

    rec = await _save(rec.copyWith(
      analysis: rec.analysis!.copyWith(status: JobStatus.analysing, updatedAt: now()),
    ));
    _guard(rec.id);
    final result = await api.estimateBodyScan(rec.remoteId);
    await _finish(rec, all, result.estimate, remoteStatus: 'done');
  }

  Future<void> _uploadPose(
    ScanRecord rec,
    ScanPose pose,
    CreateScanResult created,
  ) async {
    final shot = rec.shots[pose];
    final target = created.uploads[pose];
    if (shot == null || target == null) {
      throw const BodyScanApiException('photo-missing', retriable: false);
    }
    final photo = await readPhoto(shot.photoId);
    if (photo == null) {
      throw const BodyScanApiException('photo-missing', retriable: false);
    }
    final outcome = await blur.blur(photo: photo, landmarks: shot.landmarks);
    if (outcome is! BlurSuccess) {
      // Fail closed: never upload what could not be protected (D-4).
      throw const BodyScanApiException('blur-unavailable', retriable: false);
    }
    _guard(rec.id);
    FaceCheckResult faces;
    try {
      faces = await faceCheck.countFaces(outcome.jpeg);
    } catch (_) {
      faces = const FaceCheckUnavailable();
    }
    if (!faceCheckAllowsUpload(faces)) {
      // "Cannot verify" is a refusal too (D-69): the default detector says so.
      throw const BodyScanApiException('blur-unavailable', retriable: false);
    }
    _guard(rec.id);
    await uploader.put(target, outcome.jpeg);
  }
}

/// The check code a refusal slug maps to on the result screen.
CheckCode? checkCodeForSlug(String? slug) =>
    slug == 'blur-unavailable' ? CheckCode.blurUnavailable : null;
