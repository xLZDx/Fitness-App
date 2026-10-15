/// Client of the three body-scan callables (design s7; server contracts in
/// `functions/src/body_scan/{create,estimate,delete}.ts`). Reached ONLY when
/// `BODY_SCAN_CLOUD` is on and the provider needs photos; with the flags off no
/// callable is ever called (SD-12).
///
/// Every failure is mapped to a [BodyScanApiException] carrying a CLOSED slug
/// (D-67), never the raw SDK message.
library;

import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/firebase/functions_region.dart';
import '../../progress_photos/scan/scan_pose.dart';
import '../data/body_fat_estimate.dart';

/// One signed upload target for one pose.
class BodyScanUploadTarget {
  const BodyScanUploadTarget({
    required this.url,
    required this.headers,
    required this.expiresAtMs,
  });

  final String url;
  final Map<String, String> headers;
  final int expiresAtMs;
}

class BodyScanProviderInfo {
  const BodyScanProviderInfo({
    required this.id,
    required this.version,
    required this.provisional,
    required this.requiresPhotos,
  });

  final String id;
  final String version;
  final bool provisional;
  final bool requiresPhotos;
}

/// Result of `createBodyScan`: `pending` carries upload targets, `done` carries
/// the stored estimate (an idempotent replay).
class CreateScanResult {
  const CreateScanResult({
    required this.scanId,
    required this.done,
    required this.provider,
    this.uploads = const {},
    this.estimate,
  });

  final String scanId;
  final bool done;
  final BodyScanProviderInfo provider;
  final Map<ScanPose, BodyScanUploadTarget> uploads;
  final BodyFatEstimate? estimate;
}

/// Result of `estimateBodyScan` (`done` with an estimate).
class EstimateResult {
  const EstimateResult({required this.scanId, required this.estimate});

  final String scanId;
  final BodyFatEstimate estimate;
}

/// A callable failure reduced to a closed slug.
class BodyScanApiException implements Exception {
  const BodyScanApiException(this.slug, {this.retriable = true, this.code});

  final String slug;

  /// False for refusals that retrying cannot fix (consent, feature off,
  /// provider missing, account deleting, invalid input).
  final bool retriable;

  /// The callable error code, for example `failed-precondition`.
  final String? code;

  /// The server tombstoned this scan id: rotate `remoteId` and re-queue.
  bool get isScanCancelled => slug == 'scan-cancelled';

  /// The objects are missing or invalid: upload again.
  bool get isMissingUpload => slug.startsWith('missing-upload');

  @override
  String toString() => 'BodyScanApiException($slug)';
}

abstract class BodyScanApi {
  Future<CreateScanResult> createBodyScan({
    required String scanId,
    required DateTime takenAt,
    required String sexAtBirth,
    required int heightCm,
    required double weightKg,
    required Map<ScanPose, bool> manualOverride,
  });

  Future<EstimateResult> estimateBodyScan(String scanId);

  Future<void> deleteBodyScan(String scanId, {required bool photosOnly});
}

/// Slugs for which a later retry can succeed.
const Set<String> _retriableSlugs = {
  'estimate-in-progress',
  'scan-not-ready',
  'scan-create-conflict',
  'scan-create-failed',
  'scan-estimate-failed',
  'scan-delete-failed',
  'upload-url-failed',
  'scan-failed',
};

const Set<String> _retriableCodes = {
  'unavailable',
  'deadline-exceeded',
  'internal',
  'aborted',
  'unknown',
  'cancelled',
};

BodyScanApiException mapCallableError(FirebaseFunctionsException e) {
  final raw = e.message ?? '';
  final slug = RegExp(r'^[a-z0-9][a-z0-9:_,-]{0,59}$').hasMatch(raw)
      ? raw
      : (e.code.isEmpty ? 'callable-error' : e.code);
  final retriable = _retriableSlugs.contains(slug) ||
      slug.startsWith('missing-upload') ||
      (_retriableCodes.contains(e.code) && slug != 'scan-cancelled');
  return BodyScanApiException(slug, retriable: retriable, code: e.code);
}

/// The real client, region `europe-west1` like every other callable.
class CallableBodyScanApi implements BodyScanApi {
  CallableBodyScanApi([FirebaseFunctions? functions])
      : _functions = functions ?? functionsForRegion;

  final FirebaseFunctions _functions;

  Future<Map<String, dynamic>> _call(
      String name, Map<String, Object?> data) async {
    try {
      final res = await _functions.httpsCallable(name).call<Object?>(data);
      final body = res.data;
      if (body is Map) return Map<String, dynamic>.from(body);
      throw const BodyScanApiException('bad-response', retriable: true);
    } on FirebaseFunctionsException catch (e) {
      throw mapCallableError(e);
    }
  }

  BodyFatEstimate? _estimate(Object? raw, Object? provider) {
    if (raw is! Map) return null;
    final prov = provider is Map && provider['provisional'] == true;
    return BodyFatEstimate.tryFromJson({...raw, 'provisional': prov});
  }

  BodyScanProviderInfo _provider(Object? raw) {
    final m = raw is Map ? raw : const {};
    return BodyScanProviderInfo(
      id: m['id'] is String ? m['id'] as String : '',
      version: m['version'] is String ? m['version'] as String : '',
      provisional: m['provisional'] == true,
      requiresPhotos: m['requiresPhotos'] == true,
    );
  }

  @override
  Future<CreateScanResult> createBodyScan({
    required String scanId,
    required DateTime takenAt,
    required String sexAtBirth,
    required int heightCm,
    required double weightKg,
    required Map<ScanPose, bool> manualOverride,
  }) async {
    final body = await _call('createBodyScan', {
      'scanId': scanId,
      'takenAtMs': takenAt.millisecondsSinceEpoch,
      'subject': {
        'sexAtBirth': sexAtBirth,
        'heightCm': heightCm,
        'weightKg': weightKg,
      },
      'capture': {
        'manualOverride': {
          for (final p in ScanPose.ordered) p.name: manualOverride[p] ?? false,
        },
      },
    });
    final done = body['status'] == 'done';
    final uploads = <ScanPose, BodyScanUploadTarget>{};
    final rawUploads = body['uploads'];
    if (rawUploads is Map) {
      for (final p in ScanPose.ordered) {
        final u = rawUploads[p.name];
        if (u is Map && u['url'] is String) {
          final h = u['headers'];
          uploads[p] = BodyScanUploadTarget(
            url: u['url'] as String,
            headers: {
              if (h is Map)
                for (final e in h.entries) '${e.key}': '${e.value}',
            },
            expiresAtMs: u['expiresAtMs'] is num
                ? (u['expiresAtMs'] as num).toInt()
                : 0,
          );
        }
      }
    }
    final provider = body['provider'];
    return CreateScanResult(
      scanId: scanId,
      done: done,
      provider: _provider(provider),
      uploads: uploads,
      estimate: done ? _estimate(body['estimate'], provider) : null,
    );
  }

  @override
  Future<EstimateResult> estimateBodyScan(String scanId) async {
    final body = await _call('estimateBodyScan', {'scanId': scanId});
    final est = _estimate(body['estimate'], body['provider']);
    if (body['status'] != 'done' || est == null) {
      throw const BodyScanApiException('scan-estimate-failed');
    }
    return EstimateResult(scanId: scanId, estimate: est);
  }

  @override
  Future<void> deleteBodyScan(String scanId, {required bool photosOnly}) async {
    await _call('deleteBodyScan', {'scanId': scanId, 'photosOnly': photosOnly});
  }
}
