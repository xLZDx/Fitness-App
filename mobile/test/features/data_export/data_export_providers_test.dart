import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/data_export/data_export_providers.dart';
import 'package:fitness_app/features/data_export/data_export_sink.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/data/profile_repository.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:fitness_app/features/progress_photos/data/progress_photo.dart';
import 'package:fitness_app/features/progress_photos/state/progress_photos_providers.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session_repository.dart';
import 'package:fitness_app/features/workouts/data/workout_log_totals.dart';
import 'package:fitness_app/features/workouts/data/workout_session.dart';
import 'package:fitness_app/features/workouts/data/workout_session_repository.dart';
import 'package:fitness_app/features/workouts/state/scheduled_session_providers.dart';
import 'package:fitness_app/features/workouts/state/workout_session_providers.dart';

/// The controller that turns "signed in as u1" into a delivered file.
///
/// Everything here is faked deliberately: the point is that `export()` reads
/// exportAll() -- the unwindowed method -- not watch()/cached(), and that it
/// reaches the sink at all. The shape of the JSON itself is
/// `data_export_test.dart`'s job.

class _FakeProfileRepo implements ProfileRepository {
  const _FakeProfileRepo();
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

class _FakeWorkoutSessionRepo implements WorkoutSessionRepository {
  final List<WorkoutSession> all;
  final Duration exportDelay;
  const _FakeWorkoutSessionRepo(this.all, {this.exportDelay = Duration.zero});
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
  Future<List<WorkoutSession>> exportAll(String uid) async {
    if (exportDelay > Duration.zero) await Future<void>.delayed(exportDelay);
    return all;
  }
}

class _FakeScheduledSessionRepo implements ScheduledSessionRepository {
  final List<ScheduledSession> all;
  const _FakeScheduledSessionRepo(this.all);
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
  Future<List<ScheduledSession>> exportAll(String uid) async => all;
}

WorkoutSession _session(String id) => WorkoutSession(
      id: id,
      title: 'Squat',
      exercises: const [
        WorkoutSessionExercise(exerciseId: 'squat', exerciseTitle: 'Squat'),
      ],
      startedAt: DateTime(2026, 1, 1),
      completedAt: DateTime(2026, 1, 1),
      status: WorkoutSessionStatus.completed,
      durationMinutes: 30,
    );

const _user = AuthUser(uid: 'u1', displayName: 'U');

void main() {
  late MockDataExportSink sink;

  ProviderContainer container({int logCount = 12}) {
    sink = MockDataExportSink();
    final c = ProviderContainer(overrides: [
      authUserProvider.overrideWith((ref) => Stream.value(_user)),
      profileRepositoryProvider.overrideWithValue(const _FakeProfileRepo()),
      workoutSessionRepositoryProvider.overrideWithValue(
        _FakeWorkoutSessionRepo(
            List.generate(logCount, (i) => _session('log_$i'))),
      ),
      scheduledSessionRepositoryProvider
          .overrideWithValue(const _FakeScheduledSessionRepo([])),
      dataExportSinkProvider.overrideWithValue(sink),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('reaches the sink with a filename and non-empty JSON', () async {
    final c = container();
    await c.read(dataExportActionProvider.notifier).export();

    expect(sink.delivered, hasLength(1));
    expect(sink.delivered.single.filename, endsWith('.json'));
    final decoded =
        jsonDecode(sink.delivered.single.contents) as Map<String, dynamic>;
    expect(decoded['profile']['uid'], 'u1');
  });

  test('carries more than the windowed view could -- exportAll, not watch',
      () async {
    // kWorkoutHistoryWindow is 200; this asserts the plumbing, not the
    // constant, so a smaller number that still exceeds nothing meaningful
    // would be a false pass. 12 is simply "more than watch() would emit from
    // an empty Stream.value(const [])" -- proving export() did not fall back
    // to the live listener.
    final c = container(logCount: 12);
    await c.read(dataExportActionProvider.notifier).export();

    final decoded =
        jsonDecode(sink.delivered.single.contents) as Map<String, dynamic>;
    expect(decoded['workoutLogs'], hasLength(12));
  });

  test('does not read "not signed in yet" as "signed out"', () async {
    // The bug this locks in: `ref.read(authUserProvider).valueOrNull` on a
    // container where nothing has warmed the stream up yet is `AsyncLoading`,
    // `valueOrNull` is null, and the old code threw "signed out" for a user
    // who was, in fact, signed in -- caught by this exact test failing before
    // the fix, without any deliberate delay or fake stream, just a fresh
    // container and an immediate call.
    final c = container();
    await c.read(dataExportActionProvider.notifier).export();
    expect(c.read(dataExportActionProvider).hasError, isFalse);
    expect(sink.delivered, isNotEmpty);
  });

  test('refuses to run signed out', () async {
    final c = ProviderContainer(overrides: [
      authUserProvider.overrideWith((ref) => Stream.value(null)),
    ]);
    addTearDown(c.dispose);

    await c.read(dataExportActionProvider.notifier).export();

    expect(c.read(dataExportActionProvider).hasError, isTrue);
  });

  test('ends in a data state on success, not stuck loading', () async {
    final c = container();
    await c.read(dataExportActionProvider.notifier).export();
    expect(c.read(dataExportActionProvider).isLoading, isFalse);
    expect(c.read(dataExportActionProvider).hasError, isFalse);
  });

  test('a stalled photo read is marked incomplete, not read as "none"',
      () {
    // fakeAsync: the photo timeout is 5 real seconds, and a unit test must
    // not actually wait that long. A stream that never emits is the stall;
    // advancing virtual time past 5s is what proves the fallback -- and the
    // flag -- actually fire, rather than merely compiling.
    fakeAsync((async) {
      final sink = MockDataExportSink();
      final c = ProviderContainer(overrides: [
        authUserProvider.overrideWith((ref) => Stream.value(_user)),
        profileRepositoryProvider.overrideWithValue(const _FakeProfileRepo()),
        workoutSessionRepositoryProvider
            .overrideWithValue(const _FakeWorkoutSessionRepo([])),
        scheduledSessionRepositoryProvider
            .overrideWithValue(const _FakeScheduledSessionRepo([])),
        progressPhotosRepositoryProvider
            .overrideWithValue(const _NeverEmitsPhotosRepo()),
        dataExportSinkProvider.overrideWithValue(sink),
      ]);
      addTearDown(c.dispose);

      c.read(dataExportActionProvider.notifier).export();
      async.elapse(const Duration(seconds: 6));

      expect(sink.delivered, hasLength(1));
      final decoded =
          jsonDecode(sink.delivered.single.contents) as Map<String, dynamic>;
      expect(decoded['progressPhotosIncomplete'], isTrue,
          reason: 'a stalled read must not look like "you have no photos"');
    });
  });

  test('a stalled Firestore read ends in an error, not a permanent spinner',
      () {
    // The bug this closes: exportAll() had no timeout of its own, so a call
    // that stalls without throwing left `isLoading` true forever -- and the
    // settings tile disables its own onTap while loading, so there was no
    // error, no retry, and no way out except leaving the screen.
    fakeAsync((async) {
      final c = ProviderContainer(overrides: [
        authUserProvider.overrideWith((ref) => Stream.value(_user)),
        profileRepositoryProvider.overrideWithValue(const _FakeProfileRepo()),
        workoutSessionRepositoryProvider.overrideWithValue(
          const _FakeWorkoutSessionRepo([],
              exportDelay: Duration(minutes: 5)),
        ),
        scheduledSessionRepositoryProvider
            .overrideWithValue(const _FakeScheduledSessionRepo([])),
        dataExportSinkProvider.overrideWithValue(MockDataExportSink()),
      ]);
      addTearDown(c.dispose);

      c.read(dataExportActionProvider.notifier).export();
      async.elapse(const Duration(seconds: 31));

      expect(c.read(dataExportActionProvider).hasError, isTrue);
      expect(c.read(dataExportActionProvider).isLoading, isFalse);
    });
  });
}

class _NeverEmitsPhotosRepo implements ProgressPhotosRepository {
  const _NeverEmitsPhotosRepo();
  @override
  Stream<List<ProgressPhoto>> watch() =>
      // NOT `Stream.empty()` -- that one closes immediately with no
      // elements, so `.first` throws a StateError right away instead of
      // stalling. A stream built on a Completer's future that is never
      // completed neither emits nor closes, which is the actual stall this
      // test needs to model.
      Stream.fromFuture(Completer<List<ProgressPhoto>>().future);
  @override
  Future<Uint8List?> takeShot() async => throw UnimplementedError();
  @override
  Future<ProgressPhoto> save(
    Uint8List bytes, {
    required ProgressPhotoAngle angle,
    double? weightKg,
    String? note,
  }) async =>
      throw UnimplementedError();
  @override
  Future<void> delete(String id) async {}
  @override
  Future<Uint8List> bytesOf(ProgressPhoto photo) async =>
      throw UnimplementedError();
}
