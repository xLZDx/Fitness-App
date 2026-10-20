import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../auth/state/auth_providers.dart';
import '../../visual_equipment/data/gemini_equipment_service.dart'
    show resizeForCloud;
import '../../visual_equipment/data/scan_outcome.dart';
import '../../visual_equipment/data/visual_equipment_match.dart';
import 'scan_history_store.dart';
import 'scan_record.dart';

/// The on-phone scan history store. Overridden in tests with a temp directory.
final scanHistoryStoreProvider =
    Provider<ScanHistoryStore>((_) => ScanHistoryStore());

/// Which app build made a record (`--dart-define=GIT_SHA=... APP_VERSION=...`,
/// the same defines the debug telemetry reads). 'unknown' means the build
/// cannot be traced to a commit, which is itself worth reading in the export.
class ScanBuildInfo {
  const ScanBuildInfo({required this.gitSha, required this.version});
  final String gitSha;
  final String version;
}

final scanBuildInfoProvider = Provider<ScanBuildInfo>((_) => ScanBuildInfo(
      gitSha: const String.fromEnvironment('GIT_SHA', defaultValue: 'unknown'),
      version:
          '${const String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0')}'
          '+${const String.fromEnvironment('BUILD_NUMBER', defaultValue: '14')}',
    ));

/// The signed-in account's id, or null. History is per account (the wipe
/// deletes `scan_history/<uid>`), so with no account nothing is recorded.
final scanHistoryUidProvider = Provider<String?>((ref) {
  final uid = ref.watch(authUserProvider).valueOrNull?.uid;
  return uid != null && ScanHistoryStore.isSafeId(uid) ? uid : null;
});

/// Every saved scan of this account, newest first. Invalidated after every
/// write so the history screen and the rating marks stay current.
final scanHistoryProvider =
    FutureProvider.autoDispose<List<ScanRecord>>((ref) async {
  final uid = ref.watch(scanHistoryUidProvider);
  if (uid == null) return const <ScanRecord>[];
  return ref.watch(scanHistoryStoreProvider).list(uid);
});

/// Writes to the history on behalf of the Scan screen. Every method is
/// best-effort and never throws: a history that cannot be written must not
/// break recognition, rating or navigation.
class ScanHistoryRecorder {
  ScanHistoryRecorder(this._ref);
  final Ref _ref;

  /// The save in flight per scan. A rating or a choice made before the photo
  /// is resized and written must wait for the record to exist, or it would be
  /// applied to nothing and silently lost.
  final Map<String, Future<ScanRecord?>> _saves = <String, Future<ScanRecord?>>{};

  Future<void> _afterSave(String scanId) async {
    final pending = _saves[scanId];
    if (pending != null) await pending;
  }

  String? get _uid => _ref.read(scanHistoryUidProvider);
  ScanHistoryStore get _store => _ref.read(scanHistoryStoreProvider);

  /// Saves one scan automatically and returns the saved record, or null.
  ///
  /// [photoPath] is the file that was classified. What is stored is the SAME
  /// resized JPEG the cloud was sent ([resizeForCloud] is deterministic on that
  /// file), so the export shows what the model actually saw.
  Future<ScanRecord?> saveScan({
    required String scanId,
    required ScanSource source,
    required ScanResult result,
    String? photoPath,
    DateTime? now,
  }) {
    final Future<ScanRecord?> run = _saveScan(
        scanId: scanId,
        source: source,
        result: result,
        photoPath: photoPath,
        now: now);
    _saves[scanId] = run;
    return run;
  }

  Future<ScanRecord?> _saveScan({
    required String scanId,
    required ScanSource source,
    required ScanResult result,
    String? photoPath,
    DateTime? now,
  }) async {
    try {
      final uid = _uid;
      if (uid == null || !ScanHistoryStore.isSafeId(scanId)) return null;
      final build = _ref.read(scanBuildInfoProvider);
      Uint8List? photo;
      if (photoPath != null) {
        try {
          photo = await compute(resizeForCloud, photoPath);
        } catch (e) {
          debugPrint('scan history: photo not stored (${e.runtimeType})');
        }
      }
      final record = ScanRecord(
        id: scanId,
        timestamp: (now ?? DateTime.now()).toUtc(),
        source: source,
        outcome: result.outcome,
        answeredBy: answeredByOf(result),
        rawAnswer: result.rawAnswer,
        candidates: <ScanCandidate>[
          for (final m in result.matches)
            ScanCandidate(
              equipmentId: m.equipmentId,
              confidence: m.confidence,
              labelHint: m.labelHint,
              matchSource: m.source,
            ),
        ],
        appGitSha: build.gitSha,
        appVersion: build.version,
      );
      final saved = await _store.save(uid, record, photo: photo);
      _ref.invalidate(scanHistoryProvider);
      return saved;
    } catch (e) {
      debugPrint('scan history: scan not saved (${e.runtimeType})');
      return null;
    }
  }

  /// Sets (or clears, with null) the user's rating of one candidate.
  Future<ScanRecord?> rate(
      String scanId, String equipmentId, CandidateRating? rating) async {
    try {
      final uid = _uid;
      if (uid == null) return null;
      await _afterSave(scanId);
      final r = await _store.setRating(uid, scanId, equipmentId, rating);
      _ref.invalidate(scanHistoryProvider);
      return r;
    } catch (e) {
      debugPrint('scan history: rating not saved (${e.runtimeType})');
      return null;
    }
  }

  /// Remembers which machine the user opened (or chose by hand) for a scan.
  Future<void> choose(String scanId, String equipmentId,
      {bool manual = false}) async {
    try {
      final uid = _uid;
      if (uid == null) return;
      await _afterSave(scanId);
      await _store.setChoice(uid, scanId, equipmentId, manual: manual);
      _ref.invalidate(scanHistoryProvider);
    } catch (e) {
      debugPrint('scan history: choice not saved (${e.runtimeType})');
    }
  }

  /// "Очистить историю".
  Future<void> clear() async {
    final uid = _uid;
    if (uid == null) return;
    await _store.clear(uid);
    _ref.invalidate(scanHistoryProvider);
  }
}

final scanHistoryRecorderProvider =
    Provider<ScanHistoryRecorder>((ref) => ScanHistoryRecorder(ref));

/// Who produced the answer: printed text read off the machine, the on-device
/// fallback, the cloud model, or nobody (timeout, failure, nothing found).
ScanAnsweredBy answeredByOf(ScanResult r) {
  if (r.matches.isEmpty) return ScanAnsweredBy.none;
  if (r.matches.first.source == MatchSource.printedText) {
    return ScanAnsweredBy.printedText;
  }
  return r.answeredOffline ? ScanAnsweredBy.onDevice : ScanAnsweredBy.cloud;
}

/// The saved photo of one scan, or null (live readings have none).
final scanPhotoFileProvider =
    FutureProvider.autoDispose.family<File?, String>((ref, scanId) async {
  final uid = ref.watch(scanHistoryUidProvider);
  if (uid == null) return null;
  return ref.watch(scanHistoryStoreProvider).photoFile(uid, scanId);
});

/// Where an export is written before it is handed to the share sheet. App-private
/// temp storage; overridden in tests.
final scanExportDirProvider = Provider<Future<Directory> Function()>(
    (_) => getTemporaryDirectory);

/// Hands the exported files to the system share sheet. The ONLY place the
/// history can leave the phone, and only because the user tapped Export.
/// Overridden in tests (a real share sheet is a platform channel).
final scanShareProvider = Provider<Future<void> Function(List<File> files)>(
  (_) => (List<File> files) async {
    await Share.shareXFiles(<XFile>[
      for (final f in files)
        XFile(f.path,
            mimeType: f.path.endsWith('.json') ? 'application/json' : 'image/jpeg'),
    ]);
  },
);
