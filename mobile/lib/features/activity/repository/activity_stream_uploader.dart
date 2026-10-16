/// Phone-side upload of the private stream object (S02 design 3.1, 5.1, 5.2
/// item 4; test plan I15, I16, I17, I27).
///
/// One run for one activity is: build the CLOSED payload (`heartRate` is
/// hard-denied inside [ActivityStreamPayload.fromSession]), gzip it, hash the
/// gzip bytes (`contentSha256`, the bytes the server hashes after reading the
/// quarantine object), `createActivityStreamUpload`, HTTP PUT to the signed URL,
/// `commitActivityStream`, then the journal `synced` marker (only after the
/// commit succeeded).
///
/// Retry policy (design 5.2 item 4, as pinned by I27): at most
/// [kStreamUploadMaxAttempts] attempts per run; deterministic exponential delays
/// (1 s, 2 s, 4 s, 8 s) with NO jitter; the whole run, delays included, is
/// bounded by [kStreamUploadBudget] of the injected clock. Nothing is persisted
/// between app starts except the journal state: a restart always starts a NEW
/// upload (it never resumes at commit and never resumes a half-done PUT). After
/// the cap the entry is marked `upload_failed` and is tried again only at the
/// next app start (never a hot loop: an id that failed is not retried by this
/// instance).
///
/// Nothing is sent unless the flag is on AND consent is granted
/// ([CloudStreamsConsentView]); cancelling ([cancelQueued]) stops every queued
/// and every in-flight run before its next network step.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show GZipCodec, HttpClient;
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/config/activity_flags.dart';
import '../../../core/firebase/functions_region.dart';
import '../data/activity_stream_payload.dart';
import 'activity_journal.dart';
import 'journal_models.dart';

/// At most this many attempts per run (design 5.2 item 4).
const int kStreamUploadMaxAttempts = 5;

/// Total budget of one run, measured on the injected clock.
const Duration kStreamUploadBudget = Duration(minutes: 10);

/// Delay before attempt `n + 1` after attempt `n` failed: 1 s * 2^(n-1). Pure,
/// no randomness (I27: two runs give identical delays).
Duration streamUploadBackoff(int failedAttempt) =>
    Duration(seconds: 1 << (failedAttempt - 1));

/// Server limit on the compressed object (design 5.4).
const int kMaxCompressedStreamBytes = 5 * 1024 * 1024;

/// Read-only view of the consent the client knows (implemented by the settings
/// client). Unknown or missing is `false`.
abstract class CloudStreamsConsentView {
  bool get isGranted;
}

/// A server refusal with a bare code (never retried, except none).
class StreamUploadRefused implements Exception {
  const StreamUploadRefused(this.code);
  final String code;
  @override
  String toString() => 'StreamUploadRefused($code)';
}

/// A failure worth retrying (network, 5xx, timeout).
class StreamUploadTransient implements Exception {
  const StreamUploadTransient([this.reason = 'transient']);
  final String reason;
  @override
  String toString() => 'StreamUploadTransient($reason)';
}

/// Result of `createActivityStreamUpload`.
class CreateUploadResult {
  const CreateUploadResult.alreadyStored()
      : uploadId = null,
        url = null,
        headers = const {};
  const CreateUploadResult.upload({
    required String this.uploadId,
    required String this.url,
    required this.headers,
  });

  final String? uploadId;
  final String? url;
  final Map<String, String> headers;
  bool get alreadyStored => uploadId == null;
}

/// Callable seam for create and commit.
abstract class ActivityStreamCallableClient {
  Future<CreateUploadResult> create({
    required String activityId,
    required int bytes,
    required String contentSha256,
  });

  /// Throws [StreamUploadRefused] / [StreamUploadTransient]; returns normally
  /// for `stored` and `already_stored`.
  Future<void> commit({required String activityId, required String uploadId});
}

/// PUT seam: returns the HTTP status code; throws on transport failure.
typedef StreamPutSender = Future<int> Function(
    Uri url, Map<String, String> headers, Uint8List body);

typedef StreamUploadDelay = Future<void> Function(Duration d);

enum StreamUploadOutcome {
  uploaded,
  skipped,
  refused,
  failed,
  cancelled,
}

class ActivityStreamUploader {
  ActivityStreamUploader({
    required ActivityJournal journal,
    required ActivityStreamCallableClient callables,
    required CloudStreamsConsentView consent,
    required StreamPutSender put,
    ActivityFlags flags = ActivityFlags.compileTime,
    DateTime Function()? now,
    StreamUploadDelay? delay,
  })  : _journal = journal,
        _callables = callables,
        _consent = consent,
        _put = put,
        _flags = flags,
        _now = now ?? DateTime.now,
        _delay = delay ?? ((d) => Future<void>.delayed(d));

  final ActivityJournal _journal;
  final ActivityStreamCallableClient _callables;
  final CloudStreamsConsentView _consent;
  final StreamPutSender _put;
  final ActivityFlags _flags;
  final DateTime Function() _now;
  final StreamUploadDelay _delay;

  bool _cancelled = false;
  final Set<String> _failedThisStart = {};

  /// Stops every queued entry and every in-flight run before its next network
  /// step (consent withdrawal, design 9.1).
  void cancelQueued() => _cancelled = true;

  /// Lifts [cancelQueued] (consent granted again).
  void resume() => _cancelled = false;

  bool get _mayUpload => _flags.cloudSync && _consent.isGranted && !_cancelled;

  /// Uploads every `pending` or `upload_failed` entry once. An id that failed
  /// in this instance is not retried (next app start retries it).
  Future<void> runPending() async {
    if (!_mayUpload) return;
    final entries = await _journal.list();
    for (final e in entries) {
      if (!_mayUpload) return;
      if (e.state.tombstone || e.streamLost) continue;
      final s = e.state.syncState;
      if (s != JournalSyncState.pending && s != JournalSyncState.uploadFailed) {
        continue;
      }
      if (_failedThisStart.contains(e.id)) continue;
      try {
        await uploadEntry(e.id);
      } catch (err) {
        debugPrint('activity: stream upload errored (${err.runtimeType})');
      }
    }
  }

  /// One run for one activity (attempts, delays and budget as documented in
  /// the library comment).
  Future<StreamUploadOutcome> uploadEntry(String id) async {
    if (!_mayUpload) return StreamUploadOutcome.skipped;
    final entry = await _journal.read(id);
    if (entry == null ||
        entry.state.tombstone ||
        entry.streamLost ||
        !entry.streamsLoaded) {
      return StreamUploadOutcome.skipped;
    }
    final payload = ActivityStreamPayload.fromSession(entry.session);
    if (payload.kinds.isEmpty) return StreamUploadOutcome.skipped;
    final bytes = Uint8List.fromList(
        GZipCodec().encode(utf8.encode(jsonEncode(payload.toJson()))));
    if (bytes.isEmpty || bytes.length > kMaxCompressedStreamBytes) {
      return StreamUploadOutcome.skipped;
    }
    final sha = sha256Hex(bytes);
    final startedAt = _now();

    for (var attempt = 1; attempt <= kStreamUploadMaxAttempts; attempt++) {
      if (_cancelled) return StreamUploadOutcome.cancelled;
      if (!_mayUpload) return StreamUploadOutcome.skipped;
      try {
        final created = await _callables.create(
            activityId: id, bytes: bytes.length, contentSha256: sha);
        if (!created.alreadyStored) {
          if (_cancelled) return StreamUploadOutcome.cancelled;
          final status = await _put(Uri.parse(created.url!), created.headers, bytes);
          if (status < 200 || status >= 300) {
            throw StreamUploadTransient('put_$status');
          }
          if (_cancelled) return StreamUploadOutcome.cancelled;
          await _callables.commit(activityId: id, uploadId: created.uploadId!);
        }
        await _journal.markSynced(id, expectedGeneration: entry.generation);
        return StreamUploadOutcome.uploaded;
      } on StreamUploadRefused {
        return StreamUploadOutcome.refused;
      } on StreamUploadTransient {
        // fall through to the backoff below
      } on Exception {
        // Transport errors of the PUT sender count as transient.
      }
      if (attempt == kStreamUploadMaxAttempts) break;
      final wait = streamUploadBackoff(attempt);
      if (_now().difference(startedAt) + wait > kStreamUploadBudget) break;
      await _delay(wait);
      if (_now().difference(startedAt) >= kStreamUploadBudget) break;
    }
    _failedThisStart.add(id);
    await _journal.updateSyncState(id, JournalSyncState.uploadFailed,
        expectedGeneration: entry.generation);
    return StreamUploadOutcome.failed;
  }
}

/// Default PUT over `dart:io`; returns the status code.
Future<int> httpClientPutSender(
    Uri url, Map<String, String> headers, Uint8List body) async {
  final client = HttpClient();
  try {
    final req = await client.putUrl(url);
    headers.forEach(req.headers.set);
    req.contentLength = body.length;
    req.add(body);
    final res = await req.close();
    await res.drain<void>();
    return res.statusCode;
  } finally {
    client.close(force: true);
  }
}

/// Firebase implementation of [ActivityStreamCallableClient]. The server's
/// error text is a bare code; `unavailable`, `internal`, `deadline-exceeded`
/// and `aborted` are transient, everything else is a refusal.
class CloudFunctionsActivityStreamClient implements ActivityStreamCallableClient {
  CloudFunctionsActivityStreamClient({FirebaseFunctions? functions})
      : _functions = functions ?? functionsForRegion;

  final FirebaseFunctions _functions;

  static const _transientCodes = {
    'unavailable',
    'internal',
    'deadline-exceeded',
    'aborted',
  };

  Never _rethrow(FirebaseFunctionsException e) {
    if (_transientCodes.contains(e.code)) throw const StreamUploadTransient();
    throw StreamUploadRefused(e.message ?? e.code);
  }

  @override
  Future<CreateUploadResult> create({
    required String activityId,
    required int bytes,
    required String contentSha256,
  }) async {
    try {
      final res = await _functions
          .httpsCallable('createActivityStreamUpload')
          .call<Map<Object?, Object?>>({
        'activityId': activityId,
        'bytes': bytes,
        'contentSha256': contentSha256,
      });
      final d = res.data;
      if (d['status'] == 'already_stored') {
        return const CreateUploadResult.alreadyStored();
      }
      final uploadId = d['uploadId'];
      final url = d['url'];
      final headers = d['headers'];
      if (d['status'] != 'upload' ||
          uploadId is! String ||
          url is! String ||
          headers is! Map) {
        throw const StreamUploadTransient('bad_response');
      }
      return CreateUploadResult.upload(
        uploadId: uploadId,
        url: url,
        headers: {for (final e in headers.entries) '${e.key}': '${e.value}'},
      );
    } on FirebaseFunctionsException catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> commit({required String activityId, required String uploadId}) async {
    try {
      await _functions
          .httpsCallable('commitActivityStream')
          .call<Map<Object?, Object?>>({
        'activityId': activityId,
        'uploadId': uploadId,
      });
    } on FirebaseFunctionsException catch (e) {
      _rethrow(e);
    }
  }
}
