import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/data_export/data_export.dart';
import 'package:fitness_app/features/data_export/data_export_providers.dart';
import 'package:fitness_app/features/data_export/data_export_sink.dart';
import 'package:fitness_app/features/data_export/server_export.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/data/profile_repository.dart';
import 'package:fitness_app/features/profile/data/local_sensitive_store.dart';
import 'package:fitness_app/features/profile/data/sensitive_profile.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session_repository.dart';
import 'package:fitness_app/features/workouts/data/workout_log_totals.dart';
import 'package:fitness_app/features/workouts/data/workout_session.dart';
import 'package:fitness_app/features/workouts/data/workout_session_repository.dart';
import 'package:fitness_app/features/workouts/state/scheduled_session_providers.dart';
import 'package:fitness_app/features/workouts/state/workout_session_providers.dart';

/// C25 / D-61 (PRIV-25, PRIV-13): the client export loop that concatenates the
/// server's continuation pages, and the device-only `excludedFoods` merge.

Map<String, dynamic> _info(int returned, {String? next}) => {
      'returned': returned,
      'hasMore': next != null,
      'nextCursor': next,
    };

List<Map<String, dynamic>> _rows(String prefix, int from, int count) => [
      for (var i = from; i < from + count; i++) {'id': '$prefix$i'},
    ];

void main() {
  group('mergeServerPages', () {
    test('a first page with nothing left is returned as is and next is never called', () async {
      var calls = 0;
      final first = {
        'foodEntries': _rows('f', 0, 3),
        'paging': {'foodEntries': _info(3)},
      };
      final merged = await mergeServerPages(first, (_) async {
        calls++;
        return null;
      });
      expect(calls, 0);
      expect(merged['foodEntries'], hasLength(3));
      expect(merged.containsKey('pagingIncomplete'), isFalse);
    });

    test('a legacy export without a paging key is returned untouched', () async {
      final merged = await mergeServerPages({'profile': {'a': 1}}, (_) async {
        fail('must not page');
      });
      expect(merged['profile'], {'a': 1});
      expect(merged.containsKey('pagingIncomplete'), isFalse);
    });

    test('pages are concatenated per section in served order, and only sections with hasMore are requested', () async {
      final seen = <Map<String, String>>[];
      final first = {
        'foodEntries': _rows('f', 0, 2),
        'weightEntries': _rows('w', 0, 2),
        'paging': {
          'foodEntries': _info(2, next: 'f1'),
          'weightEntries': _info(2, next: 'w1'),
          'bodyScans': _info(0),
        },
      };
      final merged = await mergeServerPages(first, (cursors) async {
        seen.add(Map.of(cursors));
        if (seen.length == 1) {
          return {
            'foodEntries': _rows('f', 2, 2),
            'weightEntries': _rows('w', 2, 1),
            'paging': {
              'foodEntries': _info(2, next: 'f3'),
              'weightEntries': _info(1), // weights finish here
            },
          };
        }
        return {
          'foodEntries': _rows('f', 4, 1),
          'paging': {'foodEntries': _info(1)},
        };
      });

      expect(seen, [
        {'foodEntries': 'f1', 'weightEntries': 'w1'},
        {'foodEntries': 'f3'}, // weights are not asked for again
      ]);
      expect((merged['foodEntries'] as List).map((r) => r['id']),
          ['f0', 'f1', 'f2', 'f3', 'f4']);
      expect((merged['weightEntries'] as List).map((r) => r['id']),
          ['w0', 'w1', 'w2']);
      expect(merged.containsKey('pagingIncomplete'), isFalse);
      expect((merged['paging'] as Map)['foodEntries']['hasMore'], isFalse);
      expect((merged['paging'] as Map)['weightEntries']['hasMore'], isFalse);
    });

    test('the input map is not mutated', () async {
      final first = {
        'foodEntries': _rows('f', 0, 1),
        'paging': {'foodEntries': _info(1, next: 'f0')},
      };
      await mergeServerPages(first, (_) async => {
            'foodEntries': _rows('f', 1, 1),
            'paging': {'foodEntries': _info(1)},
          });
      expect(first['foodEntries'], hasLength(1));
      expect((first['paging'] as Map)['foodEntries']['hasMore'], isTrue);
    });

    test('a failed page keeps what was fetched, marks the export incomplete and stops', () async {
      var calls = 0;
      final merged = await mergeServerPages({
        'foodEntries': _rows('f', 0, 2),
        'paging': {'foodEntries': _info(2, next: 'f1')},
      }, (_) async {
        calls++;
        return calls == 1
            ? {
                'foodEntries': _rows('f', 2, 2),
                'paging': {'foodEntries': _info(2, next: 'f3')},
              }
            : null;
      });
      expect(calls, 2);
      expect(merged['pagingIncomplete'], isTrue);
      expect(merged['foodEntries'], hasLength(4));
    });

    test('a failure on the very first continuation marks it incomplete too', () async {
      final merged = await mergeServerPages({
        'weightEntries': _rows('w', 0, 2),
        'paging': {'weightEntries': _info(2, next: 'w1')},
      }, (_) async => null);
      expect(merged['pagingIncomplete'], isTrue);
      expect(merged['weightEntries'], hasLength(2));
    });

    test('there is no fixed page cap: 120 continuations complete the export', () async {
      var calls = 0;
      final merged = await mergeServerPages({
        'foodEntries': _rows('f', 0, 1),
        'paging': {'foodEntries': _info(1, next: 'f0')},
      }, (cursors) async {
        calls++;
        return {
          'foodEntries': _rows('f', calls, 1),
          'paging': {
            'foodEntries': calls == 120 ? _info(1) : _info(1, next: 'f$calls'),
          },
        };
      });
      expect(calls, 120);
      expect(merged.containsKey('pagingIncomplete'), isFalse);
      expect(merged['foodEntries'], hasLength(121));
    });

    test('finishing exactly on the last allowed page is complete, not incomplete', () async {
      var calls = 0;
      final merged = await mergeServerPages({
        'foodEntries': _rows('f', 0, 1),
        'paging': {'foodEntries': _info(1, next: 'f0')},
      }, (cursors) async {
        calls++;
        return {
          'foodEntries': _rows('f', calls, 1),
          'paging': {
            'foodEntries': calls == 49 ? _info(1) : _info(1, next: 'f$calls'),
          },
        };
      });
      expect(calls, 49);
      expect(merged.containsKey('pagingIncomplete'), isFalse);
      expect(merged['foodEntries'], hasLength(50));
    });

    test('a hasMore section whose cursor is missing is not looped on', () async {
      var calls = 0;
      final merged = await mergeServerPages({
        'foodEntries': _rows('f', 0, 1),
        'paging': {
          'foodEntries': {'returned': 1, 'hasMore': true, 'nextCursor': null},
        },
      }, (_) async {
        calls++;
        return null;
      });
      expect(calls, 0);
      // hasMore without a usable cursor can never be completed: not "complete".
      expect(merged['pagingIncomplete'], isTrue);
    });
  });

  group('ServerExport.fetchAll', () {
    test('null when the first page failed', () async {
      expect(await FakeServerExport(null).fetchAll(), isNull);
    });

    test('a server that cannot serve continuation pages yields an incomplete export', () async {
      final res = await FakeServerExport({
        'foodEntries': _rows('f', 0, 1),
        'paging': {'foodEntries': _info(1, next: 'f0')},
      }).fetchAll();
      expect(res!['pagingIncomplete'], isTrue);
      expect(res['foodEntries'], hasLength(1));
    });
  });

  group('export file', () {
    test('pagingIncomplete is declared in the notes, a complete paged export is not', () {
      Map<String, dynamic> build(Map<String, dynamic> server) => buildExport(
            profile: const UserProfile(uid: 'u1'),
            workoutLogs: const [],
            scheduledSessions: const [],
            programmes: const [],
            progressPhotos: const [],
            server: server,
          );
      final bad = (build({'pagingIncomplete': true})['notes'] as List).join(' ');
      expect(bad, contains('INCOMPLETE'));
      expect(bad, contains('resume'));
      final ok = (build({'foodEntries': <Object>[]})['notes'] as List).join(' ');
      expect(ok, isNot(contains('INCOMPLETE')));
    });
  });

  group('export controller', () {
    ProviderContainer container({
      required ServerExport server,
      required LocalSensitiveStore store,
      required MockDataExportSink sink,
    }) {
      final c = ProviderContainer(overrides: [
        authUserProvider.overrideWith(
            (ref) => Stream.value(const AuthUser(uid: 'u1', displayName: 'U'))),
        profileRepositoryProvider.overrideWithValue(_Repo()),
        workoutSessionRepositoryProvider.overrideWithValue(_Sessions()),
        scheduledSessionRepositoryProvider.overrideWithValue(_Scheduled()),
        serverExportProvider.overrideWithValue(server),
        localSensitiveStoreProvider.overrideWithValue(store),
        dataExportSinkProvider.overrideWithValue(sink),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<Map<String, dynamic>> run(ProviderContainer c, MockDataExportSink sink) async {
      await c.read(dataExportActionProvider.notifier).export();
      expect(c.read(dataExportActionProvider).hasError, isFalse);
      return jsonDecode(sink.delivered.single.contents) as Map<String, dynamic>;
    }

    test('the delivered file carries every server page and device-only excludedFoods', () async {
      final sink = MockDataExportSink();
      final store = InMemorySensitiveStore();
      await store.write('u1',
          const SensitiveProfile(excludedFoods: ['peanuts', 'shellfish']));
      final c = container(
        server: _PagedServer(),
        store: store,
        sink: sink,
      );

      final file = await run(c, sink);

      final server = file['server'] as Map<String, dynamic>;
      expect((server['foodEntries'] as List).map((r) => r['id']),
          ['f0', 'f1', 'f2']);
      expect(server.containsKey('pagingIncomplete'), isFalse);
      expect(file['serverIncomplete'], isFalse);
      expect(file['profile']['nutrition']['excludedFoods'],
          ['peanuts', 'shellfish']);
    });

    test('an empty device store leaves the loaded profile as is', () async {
      final sink = MockDataExportSink();
      final c = container(
          server: _PagedServer(), store: InMemorySensitiveStore(), sink: sink);
      final file = await run(c, sink);
      expect(file['profile']['personal']['age'], 40);
      final nutrition = file['profile']['nutrition'];
      expect((nutrition as Map?)?['excludedFoods'] ?? const [], isEmpty);
    });

    test('an unreadable device store does not fail the export', () async {
      final sink = MockDataExportSink();
      final c = container(
          server: _PagedServer(), store: _ThrowingStore(), sink: sink);
      final file = await run(c, sink);
      expect(file['profile']['uid'], 'u1');
      expect(file['profile']['personal']['age'], 40);
    });
  });
}

/// A server whose first page has more, continued by exactly one more page.
class _PagedServer extends ServerExport {
  @override
  Future<Map<String, dynamic>?> fetch() async => {
        'uid': 'u1',
        'foodEntries': _rows('f', 0, 2),
        'paging': {'foodEntries': _info(2, next: 'f1')},
      };

  @override
  Future<Map<String, dynamic>?> fetchPage(Map<String, String> cursors) async {
    expect(cursors, {'foodEntries': 'f1'});
    return {
      'uid': 'u1',
      'foodEntries': _rows('f', 2, 1),
      'paging': {'foodEntries': _info(1)},
    };
  }
}

class _ThrowingStore extends InMemorySensitiveStore {
  @override
  Future<SensitiveProfile> read(String uid) async =>
      throw StateError('prefs unavailable');
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
