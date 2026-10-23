import 'package:cloud_functions/cloud_functions.dart';

import '../../core/firebase/functions_region.dart';
import 'export_progress_store.dart';

/// A3 — the server half of the GDPR export.
///
/// The client can assemble profile, workouts, schedule, programmes and photo
/// metadata on its own, and does. It cannot assemble the rest: `debug_sessions`
/// is `allow read: if false` in `firestore.rules`, and `coach_bookings` /
/// `equipment_reports` have no client query for "all of mine". Those live
/// behind the `exportAccountData` callable, which runs with Admin credentials.
///
/// Returns `null` rather than throwing when the call fails. The export that
/// survives is the local one, marked incomplete — the same choice the photo
/// timeout already makes, and for the same reason: a partial export a user can
/// read beats an error they cannot.
abstract class ServerExport {
  Future<Map<String, dynamic>?> fetch();

  /// A continuation page (C25, D-61): the callable is repeated with
  /// `cursors: {section: nextCursor}` and returns only those sections.
  /// Null when the page could not be read. Implementations that do not page
  /// (the fake) keep this default.
  Future<Map<String, dynamic>?> fetchPage(Map<String, String> cursors) async =>
      null;

  /// The first page plus every continuation page, concatenated per section.
  /// Null only when the first page failed.
  ///
  /// With a [store] and the signed-in [uid], progress is persisted after every
  /// page and an unfinished earlier run for the same uid is RESUMED (the first
  /// page is not fetched again, so a resume costs no full-export quota).
  Future<Map<String, dynamic>?> fetchAll({
    ExportProgressStore? store,
    String? uid,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final resume = (store != null && uid != null)
          ? await loadExportResume(store, uid)
          : null;
      final Map<String, dynamic>? first = resume?.merged ?? await fetch();
      if (first == null) return null;
      try {
        return await mergeServerPages(first, fetchPage,
            store: store, uid: uid, resume: resume);
      } on StaleExportResume {
        // The saved cursors no longer exist on the server: drop them and run
        // once from the beginning.
        await store?.clear();
      }
    }
    return null;
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

/// Consecutive pages without any cursor movement before the export gives up.
const int kMaxStalledPages = 3;

/// Saved progress older than this is discarded (cursors may be stale).
const Duration kExportProgressMaxAge = Duration(days: 7);

const int _kProgressVersion = 1;

/// An earlier, unfinished export rebuilt from the [ExportProgressStore].
class ExportResume {
  ExportResume(this.merged, this.parts, this.pages);
  final Map<String, dynamic> merged;
  final int parts;
  final int pages;
}

void _appendPart(Map<String, dynamic> merged, Map<String, dynamic> part) {
  for (final e in part.entries) {
    if (e.value is List) {
      merged[e.key] = [...((merged[e.key] as List?) ?? const []), ...e.value];
    }
  }
}

/// The saved export for [uid], or null (and the store cleared) when there is
/// none, it belongs to another user, it is too old or any part is unreadable.
Future<ExportResume?> loadExportResume(
  ExportProgressStore store,
  String uid, {
  DateTime? now,
}) async {
  try {
    final m = await store.readManifest();
    if (m == null) return null;
    final parts = m['parts'];
    final savedAt = m['savedAtMs'];
    final age = (now ?? DateTime.now()).millisecondsSinceEpoch -
        (savedAt is int ? savedAt : 0);
    if (m['version'] == _kProgressVersion &&
        m['uid'] == uid &&
        parts is int &&
        parts > 0 &&
        savedAt is int &&
        m['paging'] is Map &&
        age < kExportProgressMaxAge.inMilliseconds) {
      Map<String, dynamic>? merged;
      for (var i = 0; i < parts; i++) {
        final part = await store.readPart(i);
        if (part == null) {
          merged = null;
          break;
        }
        if (merged == null) {
          merged = Map<String, dynamic>.from(part);
        } else {
          _appendPart(merged, part);
        }
      }
      if (merged != null) {
        merged['paging'] = Map<String, dynamic>.from(m['paging'] as Map);
        final pages = m['pages'];
        return ExportResume(merged, parts, pages is int ? pages : parts);
      }
    }
  } catch (_) {
    // Unreadable progress is as good as none.
  }
  try {
    await store.clear();
  } catch (_) {}
  return null;
}

/// Follows the server's per-section cursors until every section reports done,
/// concatenating continuation pages into [first] (newest first, as served).
///
/// There is NO fixed page cap: completeness is decided by the server's
/// `hasMore` per section. Instead:
///  - with a [store] (and [uid]) every page is persisted before the next is
///    requested, so an interrupted run or a quota stop is resumed later by
///    passing the [resume] rebuilt with [loadExportResume];
///  - a page that cannot be read, or a section still `hasMore` without a usable
///    cursor, sets `pagingIncomplete: true` (progress stays saved) and
///    `pagingStopReason` (`quota`, `stale_cursor` or `failed`);
///  - [kMaxStalledPages] consecutive pages in which no requested cursor moved
///    throw [ServerExportStalledException] (a server that never finishes);
///    the stalled pages' rows are NOT merged, so nothing is duplicated.
///
/// When any paged section exists the result carries `exportManifest` (pages,
/// resumed flag, per-section row counts, still-incomplete sections).
Future<Map<String, dynamic>> mergeServerPages(
  Map<String, dynamic> first,
  Future<Map<String, dynamic>?> Function(Map<String, String> cursors) next, {
  ExportProgressStore? store,
  String? uid,
  ExportResume? resume,
}) async {
  final merged = Map<String, dynamic>.from(first);
  final paging = Map<String, dynamic>.from((first['paging'] as Map?) ?? {});
  Map<String, String> pending() => {
        for (final e in paging.entries)
          if (e.value is Map &&
              (e.value as Map)['hasMore'] == true &&
              (e.value as Map)['nextCursor'] is String)
            e.key: (e.value as Map)['nextCursor'] as String,
      };
  var parts = resume?.parts ?? 0;
  var pages = resume?.pages ?? 1;
  var persisting = store != null && uid != null;
  var stalled = 0;
  String? stopReason;

  Future<void> persist(Map<String, dynamic> part) async {
    if (!persisting) return;
    try {
      await store!.writePart(parts, part);
      parts++;
      await store.writeManifest({
        'version': _kProgressVersion,
        'uid': uid,
        'savedAtMs': DateTime.now().millisecondsSinceEpoch,
        'parts': parts,
        'pages': pages,
        'paging': paging,
      });
    } catch (_) {
      // Best effort: the in-memory run continues, it just cannot be resumed.
      persisting = false;
    }
  }

  if (resume == null && pending().isNotEmpty) await persist(first);

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
    pages++;
    final pagePaging = (page['paging'] as Map?) ?? const {};
    final part = <String, dynamic>{};
    var progressed = false;
    for (final key in cursors.keys) {
      final info = pagePaging[key];
      // A section moved only if the server says it is done or hands out a
      // different cursor; anything else is not merged (no duplicate rows).
      if (info is Map &&
          (info['hasMore'] != true || info['nextCursor'] != cursors[key])) {
        progressed = true;
        final rows = page[key];
        if (rows is List) {
          merged[key] = [...((merged[key] as List?) ?? const []), ...rows];
          part[key] = rows;
        }
        paging[key] = Map<String, dynamic>.from(info);
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
    final warnings = page['warnings'];
    if (warnings is List && warnings.isNotEmpty) {
      merged['warnings'] = [...((merged['warnings'] as List?) ?? const []), ...warnings];
      part['warnings'] = warnings;
    }
    await persist(part);
  }

  final incomplete = <String>[
    for (final e in paging.entries)
      if (e.value is Map && (e.value as Map)['hasMore'] == true) e.key,
  ]..sort();
  // A section named by any response warning (e.g. a corrupt fence shard) is
  // incomplete too, but resuming cannot fix it, so it is kept apart from the
  // paging-based `incomplete` list that drives `pagingIncomplete`.
  final allWarnings = merged['warnings'];
  final warned = <String>{
    if (allWarnings is List)
      for (final w in allWarnings)
        if (w is Map && w['section'] is String) w['section'] as String,
  };
  final incompleteAll = <String>{...incomplete, ...warned}.toList()..sort();
  if (stopReason != null || incomplete.isNotEmpty) {
    merged['pagingIncomplete'] = true;
  }
  if (stopReason != null) merged['pagingStopReason'] = stopReason;
  merged['paging'] = paging;
  if (paging.isNotEmpty) {
    merged['exportManifest'] = {
      'pages': pages,
      'resumedFromEarlierRun': resume != null,
      'sectionRowCounts': {
        for (final key in paging.keys) key: ((merged[key] as List?) ?? const []).length,
      },
      'incompleteSections': incompleteAll,
      'pagingIncompleteSections': incomplete,
    };
  }
  return merged;
}

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
