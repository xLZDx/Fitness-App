// Functional tests of the resumable, uncapped server export collector.
//
// A fake server with real paging semantics (per-section cursors, rows served
// once per cursor) stands in for the callable. Every completeness assertion
// compares the EXACT id list of a section, so a duplicated or dropped row
// fails the test.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/data_export/data_export_providers.dart';
import 'package:fitness_app/features/data_export/data_export_sink.dart';
import 'package:fitness_app/features/data_export/export_progress_store.dart';
import 'package:fitness_app/features/data_export/server_export.dart';
import 'package:fitness_app/features/profile/data/local_sensitive_store.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/data/profile_repository.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session_repository.dart';
import 'package:fitness_app/features/workouts/data/workout_log_totals.dart';
import 'package:fitness_app/features/workouts/data/workout_session.dart';
import 'package:fitness_app/features/workouts/data/workout_session_repository.dart';
import 'package:fitness_app/features/workouts/state/scheduled_session_providers.dart';
import 'package:fitness_app/features/workouts/state/workout_session_providers.dart';

// ---------------------------------------------------------------------------
// Fake server
// ---------------------------------------------------------------------------

class _Interrupted implements Exception {
  @override
  String toString() => 'interrupted';
}

/// Serves `totals[section]` rows per section, [pageSize] rows per page, with
/// cursors `c<offset>`. Hooks (1-based over continuation calls) inject faults.
class PagedServer extends ServerExport {
  PagedServer(this.totals, {this.pageSize = 1, this.uid = 'u1'});

  final Map<String, int> totals;

  /// The authenticated uid every response carries (the real callable does).
  final String uid;
  final int pageSize;

  int fetchCalls = 0;
  int pageCalls = 0;
  final List<Map<String, String>> requested = <Map<String, String>>[];

  /// Throw (process death / network exception) when this call is reached.
  int? throwOnCall;

  /// Answer {'pageError': code} on this call.
  int? errorOnCall;
  String errorCode = 'stale_cursor';

  /// Answer {'pageError': code} on every call from this one on.
  int? errorFromCall;

  /// From this call on, answer with the same cursors and rows (no movement)
  /// for [stallLength] consecutive calls, then behave normally.
  int? stallOnCall;
  int stallLength = 1000;

  /// Warnings added to the response of the given call (0 = first response).
  final Map<int, List<Map<String, Object?>>> warningsOnCall =
      <int, List<Map<String, Object?>>>{};

  static String idOf(String section, int i) => '$section-$i';

  static List<String> expectedIds(String section, int total) =>
      <String>[for (var i = 0; i < total; i++) idOf(section, i)];

  Map<String, Object?> _info(String section, int end) {
    final more = end < totals[section]!;
    return <String, Object?>{
      'returned': 0,
      'hasMore': more,
      'nextCursor': more ? 'c$end' : null,
    };
  }

  List<Map<String, Object?>> _rows(String section, int from, int to) => [
        for (var i = from; i < to; i++) <String, Object?>{'id': idOf(section, i)},
      ];

  @override
  Future<Map<String, dynamic>?> fetch() async {
    fetchCalls++;
    final out = <String, dynamic>{
      'uid': uid,
      'profile': <String, Object?>{'name': 'server'},
    };
    final paging = <String, dynamic>{};
    for (final s in totals.keys) {
      final end = pageSize < totals[s]! ? pageSize : totals[s]!;
      out[s] = _rows(s, 0, end);
      paging[s] = _info(s, end);
    }
    out['paging'] = paging;
    final w = warningsOnCall[0];
    if (w != null) out['warnings'] = w;
    return out;
  }

  @override
  Future<Map<String, dynamic>?> fetchPage(Map<String, String> cursors) async {
    pageCalls++;
    requested.add(Map<String, String>.of(cursors));
    if (throwOnCall == pageCalls) throw _Interrupted();
    if (errorOnCall == pageCalls ||
        (errorFromCall != null && pageCalls >= errorFromCall!)) {
      return <String, dynamic>{'pageError': errorCode};
    }
    final stalling = stallOnCall != null &&
        pageCalls >= stallOnCall! &&
        pageCalls < stallOnCall! + stallLength;
    final out = <String, dynamic>{'uid': uid};
    final paging = <String, dynamic>{};
    cursors.forEach((section, cursor) {
      final from = int.parse(cursor.substring(1));
      final to = (from + pageSize) < totals[section]! ? from + pageSize : totals[section]!;
      out[section] = _rows(section, from, to);
      paging[section] = stalling
          ? <String, Object?>{'returned': to - from, 'hasMore': true, 'nextCursor': cursor}
          : _info(section, to);
    });
    out['paging'] = paging;
    final w = warningsOnCall[pageCalls];
    if (w != null) out['warnings'] = w;
    return out;
  }
}

/// A store whose manifest write can be made to fail (a crash after the part
/// was written but before the manifest was).
class CrashingStore extends InMemoryExportProgressStore {
  int manifestWrites = 0;
  int? failManifestWrite;
  int partWrites = 0;
  int? failPartWrite;

  @override
  Future<void> writeManifest(Map<String, dynamic> m) async {
    manifestWrites++;
    if (failManifestWrite == manifestWrites) {
      throw const FileSystemException('crash before manifest');
    }
    await super.writeManifest(m);
  }

  @override
  Future<void> writePart(int index, Map<String, dynamic> part) async {
    partWrites++;
    if (failPartWrite == partWrites) {
      throw const FileSystemException('crash during part');
    }
    await super.writePart(index, part);
  }
}

// ---------------------------------------------------------------------------
// Assertions
// ---------------------------------------------------------------------------

List<String> idsOf(Map<String, dynamic> result, String section) =>
    ((result[section] as List?) ?? const <Object>[])
        .map((r) => (r as Map)['id'] as String)
        .toList();

/// Every section holds EXACTLY the expected ids, in order: no duplicate, no gap.
void expectExactRows(Map<String, dynamic> result, Map<String, int> totals) {
  for (final e in totals.entries) {
    final got = idsOf(result, e.key);
    expect(got.length, e.value, reason: '${e.key} row count');
    expect(got.toSet().length, got.length, reason: '${e.key} has duplicates');
    expect(got, PagedServer.expectedIds(e.key, e.value),
        reason: '${e.key} rows differ from the served rows');
  }
}

/// The server never saw the same (section, cursor) twice and never asked for a
/// finished section.
void expectNoRepeatedCursors(PagedServer s) {
  final seen = <String>{};
  for (final req in s.requested) {
    for (final e in req.entries) {
      expect(seen.add('${e.key}@${e.value}'), isTrue,
          reason: 'cursor ${e.value} of ${e.key} was requested twice');
    }
  }
}

const Map<String, int> _threeSections = <String, int>{
  'foodEntries': 130,
  'weightEntries': 70,
  'workoutCommandOutcomes': 20,
};

void main() {
  group('no page cap', () {
    test('130 pages across 3 sections complete with every row exactly once',
        () async {
      final server = PagedServer(_threeSections);
      final store = InMemoryExportProgressStore();
      final res = await server.fetchAll(store: store, uid: 'u1');

      expect(res, isNotNull);
      expectExactRows(res!, _threeSections);
      expect(server.fetchCalls, 1);
      expect(server.pageCalls, 129); // 130 pages in all, one of them the first
      expect(res.containsKey('pagingIncomplete'), isFalse);
      expectNoRepeatedCursors(server);
      // A finished section is never asked for again.
      for (var i = 0; i < server.requested.length; i++) {
        final req = server.requested[i];
        if (i >= 19) expect(req.containsKey('workoutCommandOutcomes'), isFalse);
        if (i >= 69) expect(req.containsKey('weightEntries'), isFalse);
      }
      expect(server.requested.last.keys, <String>['foodEntries']);
    });

    test('without a store the same uncapped loop still completes', () async {
      final server = PagedServer(_threeSections);
      final res = await server.fetchAll();
      expectExactRows(res!, _threeSections);
    });

    test('rows are not lost when a page carries several rows (page size 7)', () async {
      final totals = <String, int>{'a': 100, 'b': 33};
      final server = PagedServer(totals, pageSize: 7);
      final res = await server.fetchAll(store: InMemoryExportProgressStore(), uid: 'u1');
      expectExactRows(res!, totals);
    });

    test('the persisted parts, concatenated, equal the final rows (one part per page)',
        () async {
      final totals = <String, int>{'a': 12, 'b': 5};
      final server = PagedServer(totals);
      final store = InMemoryExportProgressStore();
      final res = await server.fetchAll(store: store, uid: 'u1');
      expect(store.manifest!['parts'], 12);
      final rebuilt = <String, List<String>>{'a': [], 'b': []};
      for (var i = 0; i < 12; i++) {
        final p = store.parts[i]!;
        for (final k in rebuilt.keys) {
          rebuilt[k]!.addAll(((p[k] as List?) ?? const <Object>[])
              .map((r) => (r as Map)['id'] as String));
        }
      }
      expect(rebuilt['a'], idsOf(res!, 'a'));
      expect(rebuilt['b'], idsOf(res, 'b'));
      // Parts hold rows only; the rest of the first response is the base.
      expect(store.parts[0]!.containsKey('profile'), isFalse);
      expect(store.base!.containsKey('profile'), isTrue);
    });
  });

  group('resume after an interruption', () {
    for (final n in <int>[1, 2, 40, 100]) {
      test('interrupted on continuation call $n: a NEW collector resumes with no first call, no duplicates, no gaps',
          () async {
        final store = InMemoryExportProgressStore();
        final s1 = PagedServer(_threeSections)..throwOnCall = n;
        await expectLater(s1.fetchAll(store: store, uid: 'u1'),
            throwsA(isA<_Interrupted>()));
        expect(s1.fetchCalls, 1);
        expect(store.manifest, isNotNull);
        expect(store.manifest!['parts'], n); // first response + n-1 pages

        final s2 = PagedServer(_threeSections);
        final res = await s2.fetchAll(store: store, uid: 'u1');
        expect(s2.fetchCalls, 0, reason: 'a resume must not make a new first call');
        expect(s2.requested.first, s1.requested[n - 1],
            reason: 'the call that died is the first one repeated');
        expectExactRows(res!, _threeSections);
        expect(res.containsKey('pagingIncomplete'), isFalse);
        expect(s1.pageCalls + s2.pageCalls, 129 + 1,
            reason: 'only the interrupted call is repeated');
        // The two runs never asked for the same cursor except the one that died.
        final seen = <String>{};
        var repeated = 0;
        for (final req in [...s1.requested, ...s2.requested]) {
          for (final e in req.entries) {
            if (!seen.add('${e.key}@${e.value}')) repeated++;
          }
        }
        expect(repeated, lessThanOrEqualTo(_threeSections.length));
        final manifest = res['exportManifest'] as Map;
        expect(manifest['resumedFromEarlierRun'], isTrue);
      });
    }

    test('a resume continues from the saved cursors (the first request of run 2 equals the first unserved cursors)',
        () async {
      final store = InMemoryExportProgressStore();
      final s1 = PagedServer(<String, int>{'a': 10, 'b': 4})..throwOnCall = 6;
      await expectLater(s1.fetchAll(store: store, uid: 'u1'), throwsA(isA<_Interrupted>()));
      final s2 = PagedServer(<String, int>{'a': 10, 'b': 4});
      await s2.fetchAll(store: store, uid: 'u1');
      // Calls 1..5 of run 1 served offsets 1..5 of a; call 6 died asking for c6? No:
      // call k asks for offset k, so the dead call asked for offset 6 of a.
      expect(s1.requested.last, <String, String>{'a': 'c6'});
      expect(s2.requested.first, <String, String>{'a': 'c6'});
    });

    test('a resumed run interrupted again resumes again, still exact', () async {
      final store = InMemoryExportProgressStore();
      final totals = <String, int>{'a': 30, 'b': 12};
      for (final dieAt in <int>[5, 7, 3]) {
        final s = PagedServer(totals)..throwOnCall = dieAt;
        await expectLater(s.fetchAll(store: store, uid: 'u1'), throwsA(isA<_Interrupted>()));
      }
      final last = PagedServer(totals);
      final res = await last.fetchAll(store: store, uid: 'u1');
      expect(last.fetchCalls, 0);
      expectExactRows(res!, totals);
    });

    test('resume works through real files too (FileExportProgressStore)', () async {
      final tmp = await Directory.systemTemp.createTemp('export_progress_');
      addTearDown(() async {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      });
      FileExportProgressStore mk() => FileExportProgressStore(baseDir: () async => tmp);
      final s1 = PagedServer(_threeSections)..throwOnCall = 60;
      await expectLater(s1.fetchAll(store: mk(), uid: 'u1'), throwsA(isA<_Interrupted>()));
      final s2 = PagedServer(_threeSections);
      final res = await s2.fetchAll(store: mk(), uid: 'u1');
      expect(s2.fetchCalls, 0);
      expectExactRows(res!, _threeSections);
      final dir = Directory('${tmp.path}/server_export_progress/${exportProgressUserKey('u1')}');
      expect(dir.listSync().any((e) => e.path.endsWith('.tmp')), isFalse,
          reason: 'temp files are renamed away');
    });
  });

  group('crash between the part write and the manifest write', () {
    test('the orphan part is overwritten by the refetched page: no duplicate, no loss',
        () async {
      final totals = <String, int>{'a': 10, 'b': 6};
      final store = CrashingStore();
      // Write 1 = first response, 2.. = pages. Fail the manifest of page 4.
      store.failManifestWrite = 4;
      final s1 = PagedServer(totals);
      // A failed manifest write stops the export before another page is fetched.
      await expectLater(s1.fetchAll(store: store, uid: 'u1'), throwsA(isA<ExportStorageException>()));
      // Part 3 (page 4) is on disk but the manifest still lists 3 parts.
      expect(store.parts.containsKey(3), isTrue);
      expect(store.manifest!['parts'], 3);

      store.failManifestWrite = null;
      final s2 = PagedServer(totals);
      final res = await s2.fetchAll(store: store, uid: 'u1');
      expect(s2.fetchCalls, 0);
      expectExactRows(res!, totals);
      // The page whose manifest was lost is requested again.
      expect(s2.requested.first, s1.requested[2]);
    });

    test('a crash while writing the PART itself (manifest not touched) is recoverable',
        () async {
      final totals = <String, int>{'a': 10, 'b': 6};
      final store = CrashingStore()..failPartWrite = 5;
      final s1 = PagedServer(totals);
      await expectLater(s1.fetchAll(store: store, uid: 'u1'), throwsA(isA<ExportStorageException>()));
      expect(s1.pageCalls, 4, reason: 'no further server quota is used after a failed write');
      store.failPartWrite = null;
      final s2 = PagedServer(totals);
      final res = await s2.fetchAll(store: store, uid: 'u1');
      expectExactRows(res!, totals);
    });

    test('an orphan part with an index beyond the manifest is ignored by the loader',
        () async {
      final totals = <String, int>{'a': 6};
      final store = InMemoryExportProgressStore();
      final s1 = PagedServer(totals)..throwOnCall = 3;
      await expectLater(s1.fetchAll(store: store, uid: 'u1'), throwsA(isA<_Interrupted>()));
      // A stray, WRONG orphan part (rows that would duplicate if it were read).
      store.parts[store.manifest!['parts'] as int] = <String, dynamic>{
        'a': <Object>[<String, Object?>{'id': 'a-2'}, <String, Object?>{'id': 'a-2'}],
      };
      final res = await PagedServer(totals).fetchAll(store: store, uid: 'u1');
      expectExactRows(res!, totals);
    });

    test('a failing store stops the export with ExportStorageException (never silently disabled)', () async {
      final store = CrashingStore()..failPartWrite = 3;
      await expectLater(PagedServer(<String, int>{'a': 8}).fetchAll(store: store, uid: 'u1'),
          throwsA(isA<ExportStorageException>()));
    });

    test('resume through real files with an orphan part file on disk', () async {
      final tmp = await Directory.systemTemp.createTemp('export_progress_');
      addTearDown(() async {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      });
      final totals = <String, int>{'a': 9, 'b': 4};
      final fileStore = FileExportProgressStore(baseDir: () async => tmp);
      final s1 = PagedServer(totals)..throwOnCall = 4;
      await expectLater(s1.fetchAll(store: fileStore, uid: 'u1'), throwsA(isA<_Interrupted>()));
      // Orphan: part 3 exists with the rows of the page the manifest does not list.
      final dir = '${tmp.path}/server_export_progress/${exportProgressUserKey('u1')}';
      File('$dir/part_00003.a.ndjson').writeAsStringSync('${jsonEncode(<String, Object?>{'id': 'a-3'})}\n');
      File('$dir/part_00003.b.ndjson').writeAsStringSync('${jsonEncode(<String, Object?>{'id': 'b-3'})}\n');
      final res = await PagedServer(totals).fetchAll(store: fileStore, uid: 'u1');
      expectExactRows(res!, totals);
    });
  });

  group('whose progress it is, and for how long', () {
    test('a different user does not resume (or see) another user\'s progress',
        () async {
      final store = InMemoryExportProgressStore();
      final totalsA = <String, int>{'a': 10};
      final s1 = PagedServer(totalsA)..throwOnCall = 5;
      await expectLater(s1.fetchAll(store: store, uid: 'u1'), throwsA(isA<_Interrupted>()));

      final totalsB = <String, int>{'a': 7};
      final s2 = PagedServer(totalsB, uid: 'u2');
      final res = await s2.fetchAll(store: store, uid: 'u2');
      expect(s2.fetchCalls, 1, reason: 'user 2 starts from the beginning');
      expectExactRows(res!, totalsB);
      expect((res['exportManifest'] as Map)['resumedFromEarlierRun'], isFalse);
      // user 1's rows never leak into user 2's file
      expect(jsonEncode(res), isNot(contains('a-9')));
    });

    test('after user 2 started, user 1\'s old progress is gone (the store holds one export)',
        () async {
      final store = InMemoryExportProgressStore();
      final s1 = PagedServer(<String, int>{'a': 10})..throwOnCall = 5;
      await expectLater(s1.fetchAll(store: store, uid: 'u1'), throwsA(isA<_Interrupted>()));
      await PagedServer(<String, int>{'a': 3}, uid: 'u2')
          .fetchAll(store: store, uid: 'u2');
      final s3 = PagedServer(<String, int>{'a': 10});
      final res = await s3.fetchAll(store: store, uid: 'u1');
      expect(s3.fetchCalls, 1);
      expectExactRows(res!, <String, int>{'a': 10});
    });

    test('fetchAll without a uid never reads or writes progress', () async {
      final store = InMemoryExportProgressStore();
      await PagedServer(<String, int>{'a': 3}).fetchAll(store: store);
      expect(store.manifest, isNull);
      expect(store.parts, isEmpty);
    });

    test('progress older than 7 days is discarded: a new first call, rows exact',
        () async {
      final store = InMemoryExportProgressStore();
      final totals = <String, int>{'a': 10, 'b': 4};
      final s1 = PagedServer(totals)..throwOnCall = 5;
      await expectLater(s1.fetchAll(store: store, uid: 'u1'), throwsA(isA<_Interrupted>()));
      final eightDays = DateTime.now()
          .subtract(const Duration(days: 8))
          .millisecondsSinceEpoch;
      store.manifest!['savedAtMs'] = eightDays;

      final s2 = PagedServer(totals);
      final res = await s2.fetchAll(store: store, uid: 'u1');
      expect(s2.fetchCalls, 1);
      expectExactRows(res!, totals);
      expect((res['exportManifest'] as Map)['resumedFromEarlierRun'], isFalse);
    });

    test('progress just inside 7 days is still resumed', () async {
      final store = InMemoryExportProgressStore();
      final totals = <String, int>{'a': 10};
      final s1 = PagedServer(totals)..throwOnCall = 5;
      await expectLater(s1.fetchAll(store: store, uid: 'u1'), throwsA(isA<_Interrupted>()));
      store.manifest!['savedAtMs'] = DateTime.now()
          .subtract(const Duration(days: 6, hours: 23))
          .millisecondsSinceEpoch;
      final s2 = PagedServer(totals);
      final res = await s2.fetchAll(store: store, uid: 'u1');
      expect(s2.fetchCalls, 0);
      expectExactRows(res!, totals);
    });

    test('loadExportResume honours an injected clock (7 day boundary)', () async {
      final store = InMemoryExportProgressStore();
      final s1 = PagedServer(<String, int>{'a': 10})..throwOnCall = 4;
      await expectLater(s1.fetchAll(store: store, uid: 'u1'), throwsA(isA<_Interrupted>()));
      final saved = DateTime.fromMillisecondsSinceEpoch(store.manifest!['savedAtMs'] as int);
      expect(await loadExportResume(store, 'u1', now: saved.add(const Duration(days: 7) - const Duration(seconds: 1))),
          isNotNull);
      expect(await loadExportResume(store, 'u1', now: saved.add(const Duration(days: 7) + const Duration(seconds: 1))),
          isNull);
      expect(store.manifest, isNull, reason: 'a discarded progress is cleared');
    });

    test('unreadable progress (missing part, garbage manifest) is discarded and the export restarts cleanly',
        () async {
      final totals = <String, int>{'a': 8};
      // missing part
      var store = InMemoryExportProgressStore();
      var s1 = PagedServer(totals)..throwOnCall = 5;
      await expectLater(s1.fetchAll(store: store, uid: 'u1'), throwsA(isA<_Interrupted>()));
      store.parts.remove(2);
      var s2 = PagedServer(totals);
      var res = await s2.fetchAll(store: store, uid: 'u1');
      expect(s2.fetchCalls, 1);
      expectExactRows(res!, totals);
      // manifest of another version / without cursors
      store = InMemoryExportProgressStore();
      s1 = PagedServer(totals)..throwOnCall = 5;
      await expectLater(s1.fetchAll(store: store, uid: 'u1'), throwsA(isA<_Interrupted>()));
      store.manifest!['version'] = 99;
      s2 = PagedServer(totals);
      res = await s2.fetchAll(store: store, uid: 'u1');
      expect(s2.fetchCalls, 1);
      expectExactRows(res!, totals);
    });

    test('a truncated part FILE on disk is discarded, not merged', () async {
      final tmp = await Directory.systemTemp.createTemp('export_progress_');
      addTearDown(() async {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      });
      final totals = <String, int>{'a': 8};
      final st = FileExportProgressStore(baseDir: () async => tmp);
      final s1 = PagedServer(totals)..throwOnCall = 5;
      await expectLater(s1.fetchAll(store: st, uid: 'u1'), throwsA(isA<_Interrupted>()));
      File('${tmp.path}/server_export_progress/${exportProgressUserKey('u1')}/part_00002.a.ndjson')
          .writeAsStringSync('{"id"');
      final s2 = PagedServer(totals);
      final res = await s2.fetchAll(store: st, uid: 'u1');
      expect(s2.fetchCalls, 1);
      expectExactRows(res!, totals);
    });
  });

  group('rejected cursor', () {
    test('a saved cursor the server rejects on the first resumed page restarts cleanly from page 1',
        () async {
      final store = InMemoryExportProgressStore();
      final totals = <String, int>{'a': 12, 'b': 5};
      final s1 = PagedServer(totals)..throwOnCall = 6;
      await expectLater(s1.fetchAll(store: store, uid: 'u1'), throwsA(isA<_Interrupted>()));

      final s2 = PagedServer(totals)..errorOnCall = 1; // stale_cursor
      final res = await s2.fetchAll(store: store, uid: 'u1');
      expect(s2.fetchCalls, 1, reason: 'one fresh first call after the rejection');
      expectExactRows(res!, totals);
      expect(res.containsKey('pagingIncomplete'), isFalse);
      expect((res['exportManifest'] as Map)['resumedFromEarlierRun'], isFalse);
      // The restart did not reuse the rejected parts: the whole export was
      // fetched again exactly once.
      final seen = <String>{};
      for (final req in s2.requested.skip(1)) {
        for (final e in req.entries) {
          expect(seen.add('${e.key}@${e.value}'), isTrue);
        }
      }
    });

    test('a rejected cursor in a fresh run (not a resume) ends incomplete with stale_cursor and keeps progress',
        () async {
      final store = InMemoryExportProgressStore();
      final totals = <String, int>{'a': 10};
      final s = PagedServer(totals)..errorOnCall = 4;
      final res = await s.fetchAll(store: store, uid: 'u1');
      expect(res!['pagingIncomplete'], isTrue);
      expect(res['pagingStopReason'], 'stale_cursor');
      expect(idsOf(res, 'a'), PagedServer.expectedIds('a', 4)); // pages 0..3 served
      expect(store.manifest, isNotNull);
    });

    test('quota stop keeps progress and a later run finishes it exactly', () async {
      final store = InMemoryExportProgressStore();
      final totals = <String, int>{'a': 10, 'b': 6};
      final s1 = PagedServer(totals)
        ..errorFromCall = 4
        ..errorCode = 'quota';
      final r1 = await s1.fetchAll(store: store, uid: 'u1');
      expect(r1!['pagingIncomplete'], isTrue);
      expect(r1['pagingStopReason'], 'quota');
      expect((r1['exportManifest'] as Map)['incompleteSections'], <String>['a', 'b']);

      final s2 = PagedServer(totals);
      final r2 = await s2.fetchAll(store: store, uid: 'u1');
      expect(s2.fetchCalls, 0);
      expectExactRows(r2!, totals);
      expect(r2.containsKey('pagingIncomplete'), isFalse);
    });
  });

  group('stall detection', () {
    test('3 consecutive pages without cursor movement throw ServerExportStalledException',
        () async {
      final store = InMemoryExportProgressStore();
      final server = PagedServer(<String, int>{'a': 20, 'b': 20})..stallOnCall = 4;
      await expectLater(
        server.fetchAll(store: store, uid: 'u1'),
        throwsA(isA<ServerExportStalledException>()
            .having((e) => e.sections, 'sections', <String>['a', 'b'])),
      );
      expect(server.pageCalls, 3 + 3); // 3 moving pages, then exactly 3 stalled
    });

    test('stalled pages are never persisted or merged: a later run has no duplicates',
        () async {
      final store = InMemoryExportProgressStore();
      final totals = <String, int>{'a': 12};
      final s1 = PagedServer(totals)..stallOnCall = 4;
      await expectLater(s1.fetchAll(store: store, uid: 'u1'),
          throwsA(isA<ServerExportStalledException>()));
      final persisted = <String>[];
      for (final p in store.parts.values) {
        persisted.addAll(((p['a'] as List?) ?? const <Object>[])
            .map((r) => (r as Map)['id'] as String));
      }
      expect(persisted.toSet().length, persisted.length);
      expect(persisted, PagedServer.expectedIds('a', persisted.length));

      final s2 = PagedServer(totals); // the server recovered
      final res = await s2.fetchAll(store: store, uid: 'u1');
      expectExactRows(res!, totals);
    });

    test('two stalled pages followed by movement do not throw, and the duplicate rows of the stalled pages are not merged',
        () async {
      final totals = <String, int>{'a': 10};
      final server = PagedServer(totals)
        ..stallOnCall = 3
        ..stallLength = 2;
      final res = await server.fetchAll(store: InMemoryExportProgressStore(), uid: 'u1');
      expectExactRows(res!, totals);
      expect(res.containsKey('pagingIncomplete'), isFalse);
    });

    test('the stall counter resets after movement (2 stalls, move, 2 stalls, move)',
        () async {
      final totals = <String, int>{'a': 20};
      var calls = 0;
      // custom server: stall on calls 3,4 and 6,7
      final server = _ScriptedStall(totals, stallCalls: {3, 4, 6, 7}, onCall: () => calls++);
      final res = await server.fetchAll();
      expectExactRows(res!, totals);
      expect(calls, greaterThan(0));
    });

    test('kMaxStalledPages is 3', () {
      expect(kMaxStalledPages, 3);
    });
  });

  group('warnings make the section incomplete', () {
    final warning = <String, Object?>{
      'section': 'workoutCommandOutcomes',
      'id': 'wco-3',
      'code': 'CORRUPT_ENTRY_MAP',
    };

    test('a warning on a continuation page names its section in exportManifest.incompleteSections',
        () async {
      final totals = <String, int>{'foodEntries': 4, 'workoutCommandOutcomes': 4};
      final server = PagedServer(totals)..warningsOnCall[2] = [warning];
      final res = await server.fetchAll(store: InMemoryExportProgressStore(), uid: 'u1');
      expectExactRows(res!, totals); // rows are still delivered exactly once
      expect(res['warnings'], hasLength(1));
      final manifest = res['exportManifest'] as Map;
      expect(manifest['incompleteSections'], contains('workoutCommandOutcomes'));
      expect(manifest['incompleteSections'], isNot(contains('foodEntries')));
      // A damaged record is not a paging problem: nothing to resume.
      expect(res.containsKey('pagingIncomplete'), isFalse);
      expect(manifest['pagingIncompleteSections'], isEmpty);
      expect(manifest['incompleteSections'], <String>['workoutCommandOutcomes']);
    });

    test('a warning in the FIRST response also marks its section incomplete', () async {
      final totals = <String, int>{'foodEntries': 2, 'workoutCommandOutcomes': 2};
      final server = PagedServer(totals)..warningsOnCall[0] = [warning];
      final res = await server.fetchAll(store: InMemoryExportProgressStore(), uid: 'u1');
      expect((res!['exportManifest'] as Map)['incompleteSections'],
          contains('workoutCommandOutcomes'));
    });

    test('a warning on a single-page export (no continuation) still marks the section',
        () async {
      final totals = <String, int>{'workoutCommandOutcomes': 1};
      final server = PagedServer(totals)..warningsOnCall[0] = [warning];
      final res = await server.fetchAll(store: InMemoryExportProgressStore(), uid: 'u1');
      expect((res!['exportManifest'] as Map)['incompleteSections'],
          <String>['workoutCommandOutcomes']);
    });

    test('warnings survive a resume (they were saved with their part)', () async {
      final totals = <String, int>{'workoutCommandOutcomes': 8};
      final store = InMemoryExportProgressStore();
      final s1 = PagedServer(totals)
        ..warningsOnCall[2] = [warning]
        ..throwOnCall = 5;
      await expectLater(s1.fetchAll(store: store, uid: 'u1'), throwsA(isA<_Interrupted>()));
      final res = await PagedServer(totals).fetchAll(store: store, uid: 'u1');
      expect(res!['warnings'], hasLength(1));
      expect((res['exportManifest'] as Map)['incompleteSections'],
          contains('workoutCommandOutcomes'));
    });
  });

  group('manifest counts', () {
    test('sectionRowCounts equal the rows, pages equal the calls, nothing incomplete',
        () async {
      final server = PagedServer(_threeSections);
      final res = await server.fetchAll(store: InMemoryExportProgressStore(), uid: 'u1');
      final m = res!['exportManifest'] as Map;
      expect(m['pages'], 1 + server.pageCalls);
      expect(m['pages'], 130);
      expect(m['resumedFromEarlierRun'], isFalse);
      expect(m['incompleteSections'], isEmpty);
      final counts = Map<String, Object?>.from(m['sectionRowCounts'] as Map);
      for (final e in _threeSections.entries) {
        expect(counts[e.key], e.value);
        expect(counts[e.key], idsOf(res, e.key).length);
      }
    });

    test('after a resume the counts and pages still equal what the user receives',
        () async {
      final store = InMemoryExportProgressStore();
      final s1 = PagedServer(_threeSections)..throwOnCall = 77;
      await expectLater(s1.fetchAll(store: store, uid: 'u1'), throwsA(isA<_Interrupted>()));
      final s2 = PagedServer(_threeSections);
      final res = await s2.fetchAll(store: store, uid: 'u1');
      final m = res!['exportManifest'] as Map;
      expect(m['resumedFromEarlierRun'], isTrue);
      expect(m['pages'], 130);
      final counts = Map<String, Object?>.from(m['sectionRowCounts'] as Map);
      for (final e in _threeSections.entries) {
        expect(counts[e.key], e.value);
        expect(counts[e.key], idsOf(res, e.key).length);
      }
    });

    test('an incomplete export reports the rows it really holds and names the sections',
        () async {
      final totals = <String, int>{'a': 10, 'b': 3};
      final server = PagedServer(totals)
        ..errorFromCall = 5
        ..errorCode = 'quota';
      final res = await server.fetchAll(store: InMemoryExportProgressStore(), uid: 'u1');
      final m = res!['exportManifest'] as Map;
      expect(m['incompleteSections'], <String>['a']);
      expect(m['sectionRowCounts']['a'], idsOf(res, 'a').length);
      expect(m['sectionRowCounts']['a'], 5);
      expect(m['sectionRowCounts']['b'], 3);
    });
  });

  group('controller: one file, note, and when progress is cleared', () {
    late MockDataExportSink sink;
    late InMemoryExportProgressStore store;

    ProviderContainer container(ServerExport server, DataExportSink theSink,
        {ExportProgressStore? progress}) {
      final c = ProviderContainer(overrides: [
        authUserProvider.overrideWith(
            (ref) => Stream.value(const AuthUser(uid: 'u1', displayName: 'U'))),
        profileRepositoryProvider.overrideWithValue(_Repo()),
        workoutSessionRepositoryProvider.overrideWithValue(_Sessions()),
        scheduledSessionRepositoryProvider.overrideWithValue(_Scheduled()),
        serverExportProvider.overrideWithValue(server),
        localSensitiveStoreProvider.overrideWithValue(InMemorySensitiveStore()),
        dataExportSinkProvider.overrideWithValue(theSink),
        exportProgressStoreProvider.overrideWithValue(progress ?? store),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    setUp(() {
      sink = MockDataExportSink();
      store = InMemoryExportProgressStore();
    });

    Map<String, dynamic> delivered(int i) =>
        jsonDecode(sink.delivered[i].contents) as Map<String, dynamic>;

    String noteText(Map<String, dynamic> file) => (file['notes'] as List).join(' | ');

    test('a complete export: ONE file, exact rows, manifest in the file, progress cleared after delivery',
        () async {
      final server = PagedServer(_threeSections);
      final c = container(server, sink);
      await c.read(dataExportActionProvider.notifier).export();
      expect(c.read(dataExportActionProvider).hasError, isFalse);

      expect(sink.delivered, hasLength(1));
      final file = delivered(0);
      final srv = file['server'] as Map<String, dynamic>;
      expectExactRows(srv, _threeSections);
      expect((srv['exportManifest'] as Map)['pages'], 130);
      expect(noteText(file), isNot(contains('INCOMPLETE')));
      expect(file['serverIncomplete'], isFalse);
      expect(store.manifest, isNull, reason: 'cleared after a complete delivery');
      expect(store.parts, isEmpty);
    });

    test('progress is NOT cleared when delivery fails; the next run delivers the same rows with no server call',
        () async {
      final failing = _FailingSink();
      final server = PagedServer(_threeSections);
      final c1 = container(server, failing);
      await c1.read(dataExportActionProvider.notifier).export();
      expect(c1.read(dataExportActionProvider).hasError, isTrue);
      expect(store.manifest, isNotNull, reason: 'nothing was delivered yet');

      final callsBefore = server.fetchCalls + server.pageCalls;
      final c2 = container(server, sink);
      await c2.read(dataExportActionProvider.notifier).export();
      expect(c2.read(dataExportActionProvider).hasError, isFalse);
      expect(server.fetchCalls + server.pageCalls, callsBefore,
          reason: 'the saved, finished export is delivered without new calls');
      expectExactRows(delivered(0)['server'] as Map<String, dynamic>, _threeSections);
      expect(store.manifest, isNull);
    });

    test('an incomplete (quota) file keeps the progress; the note names the sections and says to run again',
        () async {
      final totals = <String, int>{'foodEntries': 10, 'weightEntries': 3};
      final server = PagedServer(totals)
        ..errorFromCall = 4
        ..errorCode = 'quota';
      final c = container(server, sink);
      await c.read(dataExportActionProvider.notifier).export();
      final file = delivered(0);
      final note = noteText(file);
      expect(note, contains('INCOMPLETE'));
      expect(note, contains('foodEntries'));
      expect(note, isNot(contains('weightEntries')));
      expect(note.toLowerCase(), contains('run the export'));
      expect(note.toLowerCase(), contains('resume'));
      expect(store.manifest, isNotNull, reason: 'the delivered file is incomplete');

      // Next day: the quota is back, the second run resumes and completes.
      final server2 = PagedServer(totals);
      final c2 = container(server2, sink);
      await c2.read(dataExportActionProvider.notifier).export();
      expect(server2.fetchCalls, 0);
      final file2 = delivered(1);
      expectExactRows(file2['server'] as Map<String, dynamic>, totals);
      expect(noteText(file2), isNot(contains('INCOMPLETE')));
      expect(store.manifest, isNull);
    });

    test('a warning names its section in the delivered note and the file is not treated as complete',
        () async {
      final totals = <String, int>{'foodEntries': 3, 'workoutCommandOutcomes': 3};
      final server = PagedServer(totals)
        ..warningsOnCall[1] = [
          <String, Object?>{
            'section': 'workoutCommandOutcomes',
            'id': 'wco-1',
            'code': 'CORRUPT_ENTRY_MAP',
          }
        ];
      final c = container(server, sink);
      await c.read(dataExportActionProvider.notifier).export();
      final file = delivered(0);
      final note = noteText(file);
      expect(note, contains('workoutCommandOutcomes'));
      expect(((file['server'] as Map)['exportManifest'] as Map)['incompleteSections'],
          contains('workoutCommandOutcomes'));
      // Wording of a damaged record: section, record id and code are named,
      // and the user is NOT told that running again would fix it.
      expect(note, contains('wco-1'));
      expect(note, contains('CORRUPT_ENTRY_MAP'));
      expect(note.toLowerCase(), contains('contact support'));
      expect(note.toLowerCase(), contains('will not fix'));
      expect(store.manifest, isNull,
          reason: 'nothing resumable is left once the paging finished');
    });

    test('the stalled server surfaces as an export error, nothing is delivered',
        () async {
      final server = PagedServer(<String, int>{'a': 20})..stallOnCall = 2;
      final c = container(server, sink);
      await c.read(dataExportActionProvider.notifier).export();
      expect(c.read(dataExportActionProvider).error,
          isA<ServerExportStalledException>());
      expect(sink.delivered, isEmpty);
      expect(store.manifest, isNotNull, reason: 'progress is kept after a stall');
    });

    test('a failed first call: the file is delivered as server-incomplete and no progress is stored',
        () async {
      final c = container(FakeServerExport(null), sink);
      await c.read(dataExportActionProvider.notifier).export();
      expect(delivered(0)['serverIncomplete'], isTrue);
      expect(store.manifest, isNull);
    });
  });
}

class _ScriptedStall extends PagedServer {
  _ScriptedStall(super.totals, {required this.stallCalls, required this.onCall});
  final Set<int> stallCalls;
  final void Function() onCall;

  @override
  Future<Map<String, dynamic>?> fetchPage(Map<String, String> cursors) async {
    onCall();
    final call = pageCalls + 1;
    if (!stallCalls.contains(call)) return super.fetchPage(cursors);
    pageCalls++;
    requested.add(Map<String, String>.of(cursors));
    final out = <String, dynamic>{};
    final paging = <String, dynamic>{};
    cursors.forEach((section, cursor) {
      out[section] = [
        <String, Object?>{'id': 'DUPLICATE-of-$cursor'}
      ];
      paging[section] = <String, Object?>{
        'returned': 1,
        'hasMore': true,
        'nextCursor': cursor,
      };
    });
    out['paging'] = paging;
    return out;
  }
}

class _FailingSink implements DataExportSink {
  @override
  Future<void> deliverStreamed({
    required String filename,
    required Future<void> Function(ExportTextSink out) write,
  }) async {
    throw StateError('share sheet failed');
  }

  @override
  Future<void> deliver({required String filename, required String contents}) async {
    throw StateError('share sheet failed');
  }
}

class _Repo implements ProfileRepository {
  @override
  Stream<UserProfile?> watch(String uid) => Stream.value(null);
  @override
  UserProfile? cached(String uid) => null;
  @override
  Future<UserProfile?> load(String uid) async =>
      UserProfile(uid: uid, personal: const PersonalInfo(age: 40));
  @override
  Future<void> save(UserProfile profile) async {}
  @override
  Future<void> delete(String uid) async {}
}

class _Sessions implements WorkoutSessionRepository {
  @override
  Stream<List<WorkoutSession>> watch(String uid) => Stream.value(const []);
  @override
  List<WorkoutSession> cached(String uid) => const [];
  @override
  Future<WorkoutLogTotals> totals(String uid) async =>
      const WorkoutLogTotals(total: 0, longestStreakDays: 0);
  @override
  Future<void> recordStreak(String uid, int days) async {}
  @override
  Future<void> save(String uid, WorkoutSession session) async {}
  @override
  Future<void> delete(String uid, String sessionId) async {}
  @override
  Future<void> clear(String uid) async {}
  @override
  Future<List<WorkoutSession>> exportAll(String uid) async => const [];
}

class _Scheduled implements ScheduledSessionRepository {
  @override
  Stream<List<ScheduledSession>> watch(String uid) => Stream.value(const []);
  @override
  List<ScheduledSession> cached(String uid) => const [];
  @override
  Future<void> save(String uid, ScheduledSession session) async {}
  @override
  Future<void> delete(String uid, String sessionId) async {}
  @override
  Future<void> clear(String uid) async {}
  @override
  Future<List<ScheduledSession>> exportAll(String uid) async => const [];
}
