import 'package:cloud_functions/cloud_functions.dart';

import '../../core/firebase/functions_region.dart';

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
  Future<Map<String, dynamic>?> fetchAll() async {
    final first = await fetch();
    if (first == null) return null;
    return mergeServerPages(first, fetchPage);
  }
}

/// The export screen loops at most this many pages (design 20.3).
const int kMaxExportPages = 50;

/// Concatenates continuation pages into [first] (newest first, as served).
///
/// A page that cannot be read, or a section that still has `hasMore` after
/// [kMaxExportPages], sets `pagingIncomplete: true` so the file says so
/// instead of reading as complete.
Future<Map<String, dynamic>> mergeServerPages(
  Map<String, dynamic> first,
  Future<Map<String, dynamic>?> Function(Map<String, String> cursors) next,
) async {
  final merged = Map<String, dynamic>.from(first);
  final paging = Map<String, dynamic>.from((first['paging'] as Map?) ?? {});
  Map<String, String> pending() => {
        for (final e in paging.entries)
          if (e.value is Map &&
              (e.value as Map)['hasMore'] == true &&
              (e.value as Map)['nextCursor'] is String)
            e.key: (e.value as Map)['nextCursor'] as String,
      };
  var pages = 1;
  while (pages < kMaxExportPages) {
    final cursors = pending();
    if (cursors.isEmpty) break;
    final page = await next(cursors);
    pages++;
    if (page == null) {
      merged['pagingIncomplete'] = true;
      merged['paging'] = paging;
      return merged;
    }
    final pagePaging = (page['paging'] as Map?) ?? const {};
    for (final key in cursors.keys) {
      final rows = page[key];
      if (rows is List) {
        merged[key] = [...((merged[key] as List?) ?? const []), ...rows];
      }
      paging[key] = pagePaging[key] ?? const {'hasMore': false};
    }
  }
  if (pending().isNotEmpty) merged['pagingIncomplete'] = true;
  merged['paging'] = paging;
  return merged;
}

class CloudFunctionsServerExport implements ServerExport {
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
class FakeServerExport implements ServerExport {
  FakeServerExport([this.payload]);

  final Map<String, dynamic>? payload;
  int calls = 0;

  @override
  Future<Map<String, dynamic>?> fetch() async {
    calls++;
    return payload;
  }
}
