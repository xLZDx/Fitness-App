import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';

import 'scan_record.dart';

/// Folder under the app documents directory. The account-deletion wipe
/// (`DeviceLocalDataWipe`) deletes `<this>/<uid>`, and the Android backup rules
/// exclude `app_flutter/<this>`; `backup_rules_test.dart` pins both names.
const String kScanHistoryDir = 'scan_history';

/// Retention: whichever limit is hit first, the OLDEST scans go.
const int kScanHistoryMaxScans = 500;
const int kScanHistoryMaxBytes = 1024 * 1024 * 1024; // 1 GiB

final RegExp _safeId = RegExp(r'^[A-Za-z0-9_\-]{1,80}$');

/// The on-phone scan history.
///
/// Layout: `<docs>/scan_history/<uid>/<scanId>/record.json` plus, for a scan
/// with a picture, `photo.jpg` next to it -- one folder per scan, so deleting a
/// scan, enforcing the retention cap and wiping an account are all a directory
/// delete. App-private storage only; nothing here is ever uploaded.
///
/// NOT encrypted at rest (unlike progress photos): these are pictures of gym
/// machines, the folder sits in the app sandbox, is excluded from backup and
/// device transfer, and the operator must be able to export them in the clear.
/// That is a stated limit (`core/DATA_INVENTORY_2026-08-11.md`), not an
/// oversight.
///
/// Writes are serialised through one chain so a rating tapped while the scan's
/// own record is still being written cannot be lost or interleave.
class ScanHistoryStore {
  ScanHistoryStore({
    Directory? documents,
    this.maxScans = kScanHistoryMaxScans,
    this.maxBytes = kScanHistoryMaxBytes,
  }) : _documents = documents;

  final Directory? _documents;
  final int maxScans;
  final int maxBytes;

  Future<void> _chain = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() op) {
    final Future<T> run = _chain.then((_) => op());
    _chain = run.then((_) {}, onError: (Object _, StackTrace __) {});
    return run;
  }

  static bool isSafeId(String id) => _safeId.hasMatch(id);

  static void _requireSafe(String uid, [String? id]) {
    if (!isSafeId(uid) || (id != null && !isSafeId(id))) {
      throw ArgumentError('unsafe scan history path component');
    }
  }

  Future<Directory> userDir(String uid) async {
    _requireSafe(uid);
    final docs = _documents ?? await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/$kScanHistoryDir/$uid');
  }

  Future<Directory> _scanDir(String uid, String id) async {
    _requireSafe(uid, id);
    return Directory('${(await userDir(uid)).path}/$id');
  }

  /// Writes [record] (and [photo], when there is one) and then applies the
  /// retention cap. The record's `hasPhoto` is what is trusted on read, so a
  /// photo is only declared when its bytes were written.
  Future<ScanRecord> save(String uid, ScanRecord record, {Uint8List? photo}) {
    return _serial(() async {
      final dir = await _scanDir(uid, record.id);
      await dir.create(recursive: true);
      final bool withPhoto = photo != null && photo.isNotEmpty;
      if (withPhoto) {
        await File('${dir.path}/${ScanRecord.photoFileName}')
            .writeAsBytes(photo, flush: true);
      }
      final saved = ScanRecord(
        id: record.id,
        timestamp: record.timestamp,
        source: record.source,
        outcome: record.outcome,
        answeredBy: record.answeredBy,
        rawAnswer: record.rawAnswer,
        candidates: record.candidates,
        openedEquipmentId: record.openedEquipmentId,
        pickedManually: record.pickedManually,
        hasPhoto: withPhoto,
        appGitSha: record.appGitSha,
        appVersion: record.appVersion,
      );
      await _writeRecord(dir, saved);
      await _enforceRetention(uid);
      return saved;
    });
  }

  Future<void> _writeRecord(Directory dir, ScanRecord r) async {
    // Written beside, then renamed over: a crash mid-write leaves the previous
    // record, never half a JSON document.
    final tmp = File('${dir.path}/record.json.tmp');
    await tmp.writeAsString(r.encode(), flush: true);
    // A reader (the history screen) can hold record.json open for a moment;
    // on Windows that makes the rename-over fail. Retry briefly.
    for (var attempt = 1;; attempt++) {
      try {
        await tmp.rename('${dir.path}/record.json');
        return;
      } on FileSystemException {
        if (attempt >= 5) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 40 * attempt));
      }
    }
  }

  Future<ScanRecord?> _read(Directory dir) async {
    final f = File('${dir.path}/record.json');
    try {
      if (!await f.exists()) return null;
      return ScanRecord.fromJson(
          (jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>());
    } catch (e) {
      debugPrint('scan history: unreadable record skipped (${e.runtimeType})');
      return null;
    }
  }

  Future<ScanRecord?> get(String uid, String id) async =>
      _read(await _scanDir(uid, id));

  /// Newest first. An unreadable folder is skipped, not fatal.
  Future<List<ScanRecord>> list(String uid) async {
    final root = await userDir(uid);
    if (!await root.exists()) return const <ScanRecord>[];
    final out = <ScanRecord>[];
    await for (final e in root.list()) {
      if (e is! Directory) continue;
      final r = await _read(e);
      if (r != null) out.add(r);
    }
    out.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return out;
  }

  Future<File?> photoFile(String uid, String id) async {
    final f =
        File('${(await _scanDir(uid, id)).path}/${ScanRecord.photoFileName}');
    return await f.exists() ? f : null;
  }

  /// Sets or clears (null) the rating of one candidate. Returns the updated
  /// record, or null when the scan or the candidate no longer exists.
  Future<ScanRecord?> setRating(
      String uid, String id, String equipmentId, CandidateRating? rating) {
    return _serial(() async {
      final dir = await _scanDir(uid, id);
      final r = await _read(dir);
      if (r == null) return null;
      var found = false;
      final next = <ScanCandidate>[];
      for (final c in r.candidates) {
        if (c.equipmentId == equipmentId) {
          found = true;
          next.add(c.withRating(rating));
        } else {
          next.add(c);
        }
      }
      if (!found) return null;
      final updated = r.copyWith(candidates: next);
      await _writeRecord(dir, updated);
      return updated;
    });
  }

  /// Records which machine the user opened from this scan's list, or chose by
  /// hand ([manual]).
  Future<ScanRecord?> setChoice(String uid, String id, String equipmentId,
      {bool manual = false}) {
    return _serial(() async {
      final dir = await _scanDir(uid, id);
      final r = await _read(dir);
      if (r == null) return null;
      final updated =
          r.copyWith(openedEquipmentId: equipmentId, pickedManually: manual);
      await _writeRecord(dir, updated);
      return updated;
    });
  }

  /// "Очистить историю": removes every scan of this account.
  Future<void> clear(String uid) => _serial(() async {
        final root = await userDir(uid);
        if (await root.exists()) await _deleteDir(root);
      });

  /// Recursive delete with a short bounded retry. On Windows (and on phones
  /// with an indexer or antivirus) a file written a moment ago can stay locked
  /// for a few tens of milliseconds; "Clear history" and the retention cap must
  /// not fail on that. Rethrows the last error if it never lets go.
  Future<void> _deleteDir(Directory d) async {
    for (var attempt = 1;; attempt++) {
      try {
        if (await d.exists()) await d.delete(recursive: true);
        return;
      } on FileSystemException {
        if (attempt >= 6) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 60 * attempt));
      }
    }
  }

  Future<void> _enforceRetention(String uid) async {
    final root = await userDir(uid);
    if (!await root.exists()) return;
    final entries = <_Entry>[];
    await for (final e in root.list()) {
      if (e is! Directory) continue;
      final r = await _read(e);
      // A folder with no readable record is junk (an interrupted write); it
      // counts as the oldest so it is the first to go.
      entries.add(_Entry(
          e,
          r?.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0),
          await _sizeOf(e)));
    }
    entries.sort((a, b) => a.when.compareTo(b.when)); // oldest first
    var count = entries.length;
    var bytes = entries.fold<int>(0, (s, e) => s + e.bytes);
    var i = 0;
    while ((count > maxScans || bytes > maxBytes) && i < entries.length - 1) {
      // Never the newest: the scan just saved always survives its own cap.
      final victim = entries[i++];
      try {
        await _deleteDir(victim.dir);
        count--;
        bytes -= victim.bytes;
      } catch (e) {
        debugPrint(
            'scan history: retention could not delete (${e.runtimeType})');
      }
    }
  }

  Future<int> _sizeOf(Directory d) async {
    var n = 0;
    await for (final e in d.list(recursive: true)) {
      if (e is File) n += await e.length();
    }
    return n;
  }

  /// Writes ONE JSON file plus a `photos/` folder into [target] for the
  /// operator to hand over, and returns what it wrote. The JSON holds every
  /// record (with the app build that made it) and, per scan, the relative path
  /// of its photo. Nothing is uploaded by this; sharing is the caller's step.
  Future<ScanHistoryExport> export(String uid, Directory target,
      {DateTime? now}) async {
    final records = await list(uid);
    final out = Directory('${target.path}/scan_history_export');
    if (await out.exists()) await out.delete(recursive: true);
    final photosDir = Directory('${out.path}/photos');
    await photosDir.create(recursive: true);
    final photos = <File>[];
    final scans = <Map<String, Object?>>[];
    for (final r in records) {
      final json = r.toJson();
      final src = r.hasPhoto ? await photoFile(uid, r.id) : null;
      if (src != null) {
        final dst = File('${photosDir.path}/${r.id}.jpg');
        await src.copy(dst.path);
        photos.add(dst);
        json['photo'] = 'photos/${r.id}.jpg';
      } else {
        json['photo'] = null;
      }
      scans.add(json);
    }
    final file = File('${out.path}/scan_history.json');
    await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'schema': 'scan_history_export/v1',
      'exportedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'count': scans.length,
      'scans': scans,
    }));
    return ScanHistoryExport(directory: out, json: file, photos: photos);
  }
}

class _Entry {
  _Entry(this.dir, this.when, this.bytes);
  final Directory dir;
  final DateTime when;
  final int bytes;
}

class ScanHistoryExport {
  const ScanHistoryExport(
      {required this.directory, required this.json, required this.photos});
  final Directory directory;
  final File json;
  final List<File> photos;

  List<File> get files => <File>[json, ...photos];
}
