import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../core/firebase/functions_region.dart';
import 'export_progress_store.dart';

/// A3 — the server half of the GDPR export.
///
/// Rows never accumulate in memory: every page is spilled to the per-user
/// [ExportProgressStore] and streamed back out when the file is written (see
/// [ServerExportOutcome]). Peak memory of the collector is ONE page (the server
/// caps a response at about 9.5 MB) plus cursors, counts and warnings.
///
/// The client can assemble profile, workouts, schedule, programmes and photo
/// metadata on its own, and does. It cannot assemble the rest: `debug_sessions`
/// is `allow read: if false` in `firestore.rules`, and `coach_bookings` /
/// `equipment_reports` have no client query for "all of mine". Those live
/// behind the `exportAccountData` callable, which runs with Admin credentials.
///
/// Returns `null` rather than throwing when the first page fails. The export
/// that survives is the local one, marked incomplete.
abstract class ServerExport {
  Future<Map<String, dynamic>?> fetch();

  /// A continuation page (C25, D-61): the callable is repeated with
  /// `cursors: {section: nextCursor}` and returns only those sections.
  /// Null when the page could not be read. Implementations that do not page
  /// (the fake) keep this default.
  Future<Map<String, dynamic>?> fetchPage(Map<String, String> cursors) async =>
      null;

  /// The first page plus every continuation page, spilled to disk. Null only
  /// when the first page failed.
  ///
  /// With a [store] and the signed-in [uid], progress is persisted after every
  /// page and an unfinished earlier run for the same uid is RESUMED. Every page
  /// must carry that uid or the run aborts with [ExportAccountChangedException].
  Future<ServerExportOutcome?> collect({
    ExportProgressStore? store,
    String? uid,
  }) async {
    final scoped = (store != null && uid != null) ? store.forUser(uid) : null;
    if (store != null && uid != null) {
      try {
        await store.purgeStale(keepUid: uid);
      } catch (e) {
        debugPrint('export progress purge failed: ${e.runtimeType}');
      }
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      final resume = scoped != null ? await loadExportResume(scoped, uid!) : null;
      final Map<String, dynamic>? first;
      if (resume != null) {
        first = resume.first;
      } else {
        first = await fetch();
        if (first == null) return null;
        _requireUid(first, uid);
      }
      try {
        return await collectServerPages(first, fetchPage,
            store: scoped, uid: uid, resume: resume);
      } on StaleExportResume {
        // The saved cursors no longer exist on the server: drop them and run
        // once from the beginning.
        try {
          await scoped?.clear();
        } catch (e) {
          throw ExportStorageException(e);
        }
      }
    }
    return null;
  }

  /// [collect] materialised into one map (all rows in memory). For tests and
  /// small payloads only; the export action streams instead.
  Future<Map<String, dynamic>?> fetchAll({
    ExportProgressStore? store,
    String? uid,
  }) async =>
      (await collect(store: store, uid: uid))?.materialize();
}

void _requireUid(Map<String, dynamic> page, String? uid) {
  if (uid != null && page['uid'] != uid) {
    throw const ExportAccountChangedException();
  }
}

/// Raised when the server keeps answering with the same cursors, so the export
/// can never finish. An explicit error, never a silently partial file.
class ServerExportStalledException implements Exception {
  ServerExportStalledException(this.sections);
  final List<String> sections;

  @override
  String toString() =>
      'The server stopped advancing the export for: ${sections.join(', ')}. '
      'Your progress is saved; try again later.';
}

/// A saved cursor was rejected by the server on the first resumed page.
class StaleExportResume implements Exception {
  const StaleExportResume();
}

/// A page (or the file about to be delivered) belongs to another account than
/// the one the export was started for. Nothing of it is merged or delivered.
class ExportAccountChangedException implements Exception {
  const ExportAccountChangedException();

  @override
  String toString() =>
      'The signed-in account changed during the export, so it was cancelled. '
      'Start the export again.';
}

/// A part, the base or the manifest could not be written to the device (full
/// disk, permissions). The export stops BEFORE more server quota is used.
class ExportStorageException implements Exception {
  ExportStorageException([this.cause]);
  final Object? cause;

  @override
  String toString() =>
      'The export could not store its data on this device. Free up storage '
      'space and try again.';
}

/// Consecutive pages without any cursor movement before the export gives up.
const int kMaxStalledPages = 3;

const int _kProgressVersion = 2;

/// An earlier, unfinished export described by its manifest and base.
class ExportResume {
  ExportResume(this.first, this.parts, this.pages, this.rowCounts, this.warnings);

  /// The saved first response without paged rows, with the saved `paging`.
  final Map<String, dynamic> first;
  final int parts;
  final int pages;
  final Map<String, int> rowCounts;
  final List<Object?> warnings;
}

/// The saved export for [uid], or null (and the user's progress cleared) when
/// there is none, it belongs to another user, it is too old, it was already
/// delivered, or any part is unreadable. Rows are NOT read here.
Future<ExportResume?> loadExportResume(
  ExportProgressStore store,
  String uid, {
  DateTime? now,
}) async {
  final s = store.forUser(uid);
  try {
    final m = await s.readManifest();
    if (m == null) return null;
    final parts = m['parts'];
    final savedAt = m['savedAtMs'];
    final age = (now ?? DateTime.now()).millisecondsSinceEpoch -
        (savedAt is int ? savedAt : 0);
    if (m['delivered'] != true &&
        m['version'] == _kProgressVersion &&
        m['uid'] == uid &&
        parts is int &&
        parts > 0 &&
        savedAt is int &&
        m['paging'] is Map &&
        m['rowCounts'] is Map &&
        m['warnings'] is List &&
        age < kExportProgressMaxAge.inMilliseconds) {
      var intact = true;
      for (var i = 0; i < parts && intact; i++) {
        intact = await s.hasPart(i);
      }
      final base = intact ? await s.readBase() : null;
      if (base != null) {
        final pages = m['pages'];
        final first = Map<String, dynamic>.from(base)
          ..['paging'] = Map<String, dynamic>.from(m['paging'] as Map)
          ..['warnings'] = List<Object?>.from(m['warnings'] as List);
        return ExportResume(
          first,
          parts,
          pages is int ? pages : parts,
          {
            for (final e in (m['rowCounts'] as Map).entries)
              if (e.value is int) e.key as String: e.value as int,
          },
          List<Object?>.from(m['warnings'] as List),
        );
      }
    }
  } catch (_) {
    // Unreadable progress is as good as none.
  }
  try {
    await s.clear();
  } catch (_) {}
  return null;
}

/// Marks the user's saved export as delivered (terminal state): it is never
/// resumed or reused again, even if deleting it fails afterwards.
Future<void> markExportDelivered(ExportProgressStore store, String uid) async {
  final s = store.forUser(uid);
  final m = await s.readManifest();
  if (m == null) return;
  await s.writeManifest({...m, 'delivered': true});
}

/// The result of a collection: everything except the rows of the paged
/// sections (`header`), plus access to those rows on disk.
class ServerExportOutcome {
  ServerExportOutcome(this.header, this.sections, this._store, this._parts,
      {required this.persisted});

  /// The server response without paged rows, plus `paging`, `warnings`,
  /// `pagingIncomplete`/`pagingStopReason` and `exportManifest`.
  final Map<String, dynamic> header;

  /// Paged section names, in served order.
  final List<String> sections;

  /// True when the progress was durably written to the user's store (so a note
  /// may say it is saved).
  final bool persisted;

  final ExportProgressStore _store;
  final int _parts;

  /// The rows of [section] in served order, decoded one at a time.
  Stream<Object?> rows(String section) => _store.readRows(section, _parts);

  /// Header plus every section's rows in one map (all rows in memory).
  Future<Map<String, dynamic>> materialize() async {
    final out = Map<String, dynamic>.from(header);
    for (final s in sections) {
      out[s] = await rows(s).toList();
    }
    return out;
  }
}

/// Follows the server's per-section cursors until every section reports done,
/// spilling each page to [store] (newest first, as served).
///
/// There is NO fixed page cap: completeness is decided by the server's
/// `hasMore` per section. Instead:
///  - with a [store] and [uid] every page is persisted before the next is
///    requested; a write failure throws [ExportStorageException];
///  - a page that cannot be read, or a section still `hasMore` without a usable
///    cursor, sets `pagingIncomplete: true` and `pagingStopReason` (`quota`,
///    `stale_cursor` or `failed`);
///  - [kMaxStalledPages] consecutive pages in which no requested cursor moved
///    throw [ServerExportStalledException]; the stalled pages' rows are NOT
///    stored, so nothing is duplicated;
///  - with a [uid], a page whose `uid` differs throws
///    [ExportAccountChangedException] and is discarded.
///
/// Per page the order is: part files, part commit record, manifest. When any
/// paged section exists the header carries `exportManifest`.
Future<ServerExportOutcome> collectServerPages(
  Map<String, dynamic> first,
  Future<Map<String, dynamic>?> Function(Map<String, String> cursors) next, {
  ExportProgressStore? store,
  String? uid,
  ExportResume? resume,
}) async {
  final persisted = store != null && uid != null;
  final ExportProgressStore st =
      persisted ? store!.forUser(uid!) : InMemoryExportProgressStore();
  final paging = Map<String, dynamic>.from((first['paging'] as Map?) ?? {});
  final base = <String, dynamic>{
    for (final e in first.entries)
      if (e.key != 'paging' && e.key != 'warnings' && !paging.containsKey(e.key))
        e.key: e.value,
  };
  final rowCounts = <String, int>{...?resume?.rowCounts};
  final warnings = <Object?>[...?resume?.warnings];
  final firstWarnings = first['warnings'];
  final hadWarningsKey = first.containsKey('warnings');
  Map<String, String> pending() => {
        for (final e in paging.entries)
          if (e.value is Map &&
              (e.value as Map)['hasMore'] == true &&
              (e.value as Map)['nextCursor'] is String)
            e.key: (e.value as Map)['nextCursor'] as String,
      };
  var parts = resume?.parts ?? 0;
  var pages = resume?.pages ?? 1;
  var stalled = 0;
  String? stopReason;

  Future<void> commit(
    Map<String, dynamic> rows,
    Map<String, int> counts,
    List<Object?> newWarnings, {
    bool writeBase = false,
  }) async {
    final nextCounts = {...rowCounts};
    counts.forEach((k, v) => nextCounts[k] = (nextCounts[k] ?? 0) + v);
    final nextWarnings = [...warnings, ...newWarnings];
    try {
      if (writeBase) await st.writeBase(base);
      await st.writePart(parts, rows);
      await st.writeManifest({
        'version': _kProgressVersion,
        'uid': uid,
        'savedAtMs': DateTime.now().millisecondsSinceEpoch,
        'parts': parts + 1,
        'pages': pages,
        'paging': paging,
        'rowCounts': nextCounts,
        'warnings': nextWarnings,
      });
    } catch (e) {
      throw ExportStorageException(e);
    }
    parts++;
    rowCounts
      ..clear()
      ..addAll(nextCounts);
    warnings
      ..clear()
      ..addAll(nextWarnings);
  }

  if (resume == null && paging.isNotEmpty) {
    final rows = <String, dynamic>{};
    final counts = <String, int>{};
    for (final key in paging.keys) {
      final r = first[key];
      if (r is List) {
        rows[key] = r;
        counts[key] = r.length;
      }
    }
    await commit(rows, counts,
        firstWarnings is List ? List<Object?>.from(firstWarnings) : const [],
        writeBase: true);
  }

  for (;;) {
    final cursors = pending();
    if (cursors.isEmpty) break;
    final page = await next(cursors);
    final error = page?['pageError'];
    if (page == null || error is String) {
      if (error == 'stale_cursor' && resume != null && pages == resume.pages) {
        throw const StaleExportResume();
      }
      stopReason = error is String ? error : 'failed';
      break;
    }
    _requireUid(page, uid);
    pages++;
    final pagePaging = (page['paging'] as Map?) ?? const {};
    final rows = <String, dynamic>{};
    final counts = <String, int>{};
    final newPaging = <String, dynamic>{};
    var progressed = false;
    for (final key in cursors.keys) {
      final info = pagePaging[key];
      // A section moved only if the server says it is done or hands out a
      // different cursor; anything else is not stored (no duplicate rows).
      if (info is Map &&
          (info['hasMore'] != true || info['nextCursor'] != cursors[key])) {
        progressed = true;
        final r = page[key];
        if (r is List) {
          rows[key] = r;
          counts[key] = r.length;
        }
        newPaging[key] = Map<String, dynamic>.from(info);
      }
    }
    if (!progressed) {
      stalled++;
      if (stalled >= kMaxStalledPages) {
        throw ServerExportStalledException(cursors.keys.toList()..sort());
      }
      continue;
    }
    stalled = 0;
    paging.addAll(newPaging);
    final w = page['warnings'];
    await commit(rows, counts, w is List ? List<Object?>.from(w) : const []);
  }

  final incomplete = <String>[
    for (final e in paging.entries)
      if (e.value is Map && (e.value as Map)['hasMore'] == true) e.key,
  ]..sort();
  // A section named by any response warning (e.g. a corrupt fence shard) is
  // incomplete too, but resuming cannot fix it, so it is kept apart from the
  // paging-based `incomplete` list that drives `pagingIncomplete`.
  final warned = <String>{
    for (final w in warnings)
      if (w is Map && w['section'] is String) w['section'] as String,
  };
  final incompleteAll = <String>{...incomplete, ...warned}.toList()..sort();
  final header = Map<String, dynamic>.from(base);
  if (warnings.isNotEmpty || hadWarningsKey || resume != null) {
    header['warnings'] = List<Object?>.from(warnings);
  }
  if (stopReason != null || incomplete.isNotEmpty) {
    header['pagingIncomplete'] = true;
  }
  if (stopReason != null) header['pagingStopReason'] = stopReason;
  header['paging'] = paging;
  if (paging.isNotEmpty) {
    header['exportManifest'] = {
      'pages': pages,
      'resumedFromEarlierRun': resume != null,
      'sectionRowCounts': {
        for (final key in paging.keys) key: rowCounts[key] ?? 0,
      },
      'incompleteSections': incompleteAll,
      'pagingIncompleteSections': incomplete,
    };
  }
  return ServerExportOutcome(header, paging.keys.toList(), st, parts,
      persisted: persisted);
}

/// [collectServerPages] materialised into one map (all rows in memory), for
/// callers that hold a first page and a pager but no streaming consumer.
Future<Map<String, dynamic>> mergeServerPages(
  Map<String, dynamic> first,
  Future<Map<String, dynamic>?> Function(Map<String, String> cursors) next, {
  ExportProgressStore? store,
  String? uid,
  ExportResume? resume,
}) async =>
    (await collectServerPages(first, next,
            store: store, uid: uid, resume: resume))
        .materialize();

class CloudFunctionsServerExport extends ServerExport {
  CloudFunctionsServerExport({FirebaseFunctions? functions})
      : _functions = functions ?? functionsForRegion;

  final FirebaseFunctions _functions;

  @override
  Future<Map<String, dynamic>?> fetchPage(Map<String, String> cursors) async {
    try {
      final res = await _functions
          .httpsCallable('exportAccountData')
          .call<Map<String, dynamic>>({'cursors': cursors}).timeout(
              const Duration(seconds: 20));
      return Map<String, dynamic>.from(res.data);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unauthenticated') rethrow;
      // The daily continuation quota and a cursor the server no longer knows
      // are told apart from a plain failure, so the export can say how to resume.
      if (e.code == 'resource-exhausted') return {'pageError': 'quota'};
      if (e.code == 'failed-precondition') return {'pageError': 'stale_cursor'};
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> fetch() async {
    try {
      final res = await _functions
          .httpsCallable('exportAccountData')
          .call<Map<String, dynamic>>()
          .timeout(const Duration(seconds: 20));
      return Map<String, dynamic>.from(res.data);
    } on FirebaseFunctionsException catch (e) {
      // One error class is not "there is no server part": a stale token means
      // the user must sign in again, and the export file's own note would tell
      // them to "re-run the export", which fails identically every time. Let
      // it out so the export reports a failure the user can actually act on.
      if (e.code == 'unauthenticated') rethrow;
      return null;
    } catch (_) {
      // Everything else stays opaque: the caller only needs "there is no
      // server part", and the failure is already logged server-side with the
      // uid that produced it.
      return null;
    }
  }
}

/// Test double. Returns whatever it was constructed with.
class FakeServerExport extends ServerExport {
  FakeServerExport([this.payload]);

  final Map<String, dynamic>? payload;
  int calls = 0;

  @override
  Future<Map<String, dynamic>?> fetch() async {
    calls++;
    return payload;
  }
}
