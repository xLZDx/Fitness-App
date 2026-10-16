// Test double world for the client stream upload and consent-withdrawal tests
// (S02 test epic 7b: plan I15-I17, I27, I28). Test-only.
//
// [FakeStreamCloud] plays the server side of design 5.2 closely enough that a
// wrong client sequence FAILS instead of passing silently: a commit is refused
// unless a COMPLETE PUT of that very upload id with the announced hash exists,
// a second create for bytes the server already stored answers `already_stored`,
// and every call is appended to one ordered log. The journal is the real
// `FileActivityJournal` on the in-memory file system of the shared harness, so
// restarts read what was written to disk. Time is the harness [FakeClock]; the
// uploader's delay callback advances it, so backoff is measured, not slept.
import 'dart:typed_data';

import 'package:fitness_app/core/config/activity_flags.dart';
import 'package:fitness_app/features/activity/repository/activity_cloud_settings_client.dart';
import 'package:fitness_app/features/activity/repository/activity_stream_uploader.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';

import 'fake_summary_backend.dart';
import 'journal_harness.dart';

/// Thrown by a hook to simulate the app process being killed. It is an
/// [Error], not an [Exception], so the uploader's own `on Exception` retry
/// handling cannot swallow it: nothing after the kill point runs.
class KilledMidUpload extends Error {
  @override
  String toString() => 'KilledMidUpload';
}

class CreateCall {
  CreateCall(this.n, this.activityId, this.bytes, this.sha, this.at);
  final int n;
  final String activityId;
  final int bytes;
  final String sha;
  final DateTime at;
}

class CommitCall {
  CommitCall(this.n, this.activityId, this.uploadId);
  final int n;
  final String activityId;
  final String uploadId;
}

class PutCall {
  PutCall(this.n, this.url, this.headers, this.body);
  final int n;
  final Uri url;
  final Map<String, String> headers;
  final Uint8List body;

  /// True when the server received the whole body and answered 2xx.
  bool completed = false;
  String get uploadId => url.pathSegments.last;
}

class FakeStreamCloud implements ActivityStreamCallableClient {
  FakeStreamCloud(this.clock);

  final FakeClock clock;

  /// Every network step in order: `create`, `put`, `commit`, `delay`.
  final List<String> log = [];
  final List<CreateCall> creates = [];
  final List<CommitCall> commits = [];
  final List<PutCall> puts = [];

  /// Activity id -> the bytes the cloud holds after a successful commit.
  final Map<String, Uint8List> stored = {};

  final Map<String, String> _uploadActivity = {};
  final Map<String, String> _uploadSha = {};
  final Map<String, Uint8List> _putDone = {};

  /// Returns an exception to throw for the n-th (1-based) call, or null.
  Object? Function(int n)? createFault;
  Object? Function(int n)? commitFault;
  Object? Function(int n)? putFault;

  /// HTTP status of the n-th PUT.
  int Function(int n) putStatus = (_) => 200;

  /// Fake time one create call takes.
  Duration createTakes = Duration.zero;

  /// Hooks that run inside the call (they may await a gate or throw
  /// [KilledMidUpload]).
  Future<void> Function(int n, String activityId)? duringCreate;
  Future<void> Function(int n, PutCall put)? duringPut;
  Future<void> Function(int n, String uploadId)? duringCommit;

  /// Runs after the server stored the object and before the client sees the
  /// answer (a kill here is the "lost acknowledgement" case).
  Future<void> Function(int n, String uploadId)? afterCommit;

  static String shaOf(Uint8List b) => sha256Hex(b);

  @override
  Future<CreateUploadResult> create({
    required String activityId,
    required int bytes,
    required String contentSha256,
  }) async {
    final n = creates.length + 1;
    log.add('create');
    creates.add(CreateCall(n, activityId, bytes, contentSha256, clock.now));
    clock.advance(createTakes);
    final fault = createFault?.call(n);
    if (fault != null) throw fault;
    if (duringCreate != null) await duringCreate!(n, activityId);
    final held = stored[activityId];
    if (held != null && shaOf(held) == contentSha256) {
      return const CreateUploadResult.alreadyStored();
    }
    final uploadId = 'upl$n';
    _uploadActivity[uploadId] = activityId;
    _uploadSha[uploadId] = contentSha256;
    return CreateUploadResult.upload(
      uploadId: uploadId,
      url: 'https://storage.example/quarantine/uid/$activityId/$uploadId',
      headers: const {'content-type': 'application/gzip'},
    );
  }

  /// The [StreamPutSender] of the uploader.
  Future<int> put(Uri url, Map<String, String> headers, Uint8List body) async {
    final n = puts.length + 1;
    log.add('put');
    final call = PutCall(n, url, headers, Uint8List.fromList(body));
    puts.add(call);
    if (duringPut != null) await duringPut!(n, call);
    final fault = putFault?.call(n);
    if (fault != null) throw fault;
    final status = putStatus(n);
    if (status >= 200 && status < 300) {
      call.completed = true;
      _putDone[call.uploadId] = call.body;
    }
    return status;
  }

  @override
  Future<void> commit({
    required String activityId,
    required String uploadId,
  }) async {
    final n = commits.length + 1;
    log.add('commit');
    commits.add(CommitCall(n, activityId, uploadId));
    if (duringCommit != null) await duringCommit!(n, uploadId);
    final fault = commitFault?.call(n);
    if (fault != null) throw fault;
    final body = _putDone[uploadId];
    if (_uploadActivity[uploadId] != activityId ||
        body == null ||
        shaOf(body) != _uploadSha[uploadId]) {
      // The real server reads the quarantine object and finds nothing, or a
      // body whose hash is not the announced one.
      throw const StreamUploadRefused('upload_missing');
    }
    stored[activityId] = body;
    if (afterCommit != null) await afterCommit!(n, uploadId);
  }
}

class FakeConsent implements CloudStreamsConsentView {
  FakeConsent(this.granted);
  bool granted;
  @override
  bool get isGranted => granted;
}

/// Fake of `setActivityCloudSettings`: records every request, keeps the
/// "cloud streams" it would hold and applies `deleteExisting`.
class FakeSettingsServer {
  final List<Map<String, Object?>> requests = [];
  final Set<String> cloudStreams = {};

  /// Fails the n-th (1-based) request when it returns an object.
  Object? Function(int n)? fault;

  Future<Map<String, Object?>> call(Map<String, Object?> request) async {
    final n = requests.length + 1;
    requests.add(request);
    final f = fault?.call(n);
    if (f != null) throw f;
    final cs = request['cloudStreams'];
    if (cs is Map && cs['deleteExisting'] == true) cloudStreams.clear();
    return const {'ok': true};
  }

  List<Map<String, Object?>> get deleteRequests => [
        for (final r in requests)
          if ((r['cloudStreams'] as Map)['deleteExisting'] == true) r,
      ];
}

class StreamUploadWorld {
  StreamUploadWorld._(this.h, this.backend, this.cloud, this.consent, this.flags);

  final JournalHarness h;
  final FakeSummaryBackend backend;
  final FakeStreamCloud cloud;
  final FakeConsent consent;
  final ActivityFlags flags;

  /// Every delay the uploader asked for, in order.
  final List<Duration> delays = [];
  late ActivityStreamUploader uploader;

  static Future<StreamUploadWorld> open({
    bool flagOn = true,
    bool granted = true,
  }) async {
    final h = JournalHarness.memory();
    await h.open();
    final w = StreamUploadWorld._(
      h,
      FakeSummaryBackend(),
      FakeStreamCloud(h.clock),
      FakeConsent(granted),
      ActivityFlags(cloudSync: flagOn),
    );
    w.uploader = w.makeUploader();
    return w;
  }

  ActivityStreamUploader makeUploader({CloudStreamsConsentView? consentView}) =>
      ActivityStreamUploader(
        journal: h.journal,
        callables: cloud,
        consent: consentView ?? consent,
        put: cloud.put,
        flags: flags,
        now: h.clock.call,
        delay: (d) async {
          delays.add(d);
          cloud.log.add('delay');
          h.clock.advance(d);
        },
      );

  /// The real summary sync pass (`syncAll`), as the app root runs it before
  /// the stream upload.
  Future<void> summarySync() async {
    final repo = ActivitySyncRepository(
        journal: h.journal, backend: backend, clock: h.clock.call);
    try {
      await repo.syncAll();
    } finally {
      await repo.dispose();
    }
  }

  /// A new app start: a new journal instance on the same files and a new
  /// uploader (nothing survives but what is on disk).
  Future<void> restartApp() async {
    await h.restart();
    uploader = makeUploader();
  }

  Future<JournalState> stateOf(String id) async =>
      (await h.journal.read(id))!.state;

  Future<void> dispose() => h.dispose();
}
