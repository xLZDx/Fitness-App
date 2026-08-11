import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/state/auth_providers.dart';
import '../profile/data/profile_models.dart';
import '../profile/state/profile_providers.dart';
import '../programmes/state/programme_providers.dart';
import '../progress_photos/data/progress_photo.dart';
import '../progress_photos/state/progress_photos_providers.dart';
import '../workouts/data/workout_session.dart'
    show WorkoutSessionLogView, WorkoutSessionStatus;
import '../workouts/state/scheduled_session_providers.dart';
import '../workouts/state/workout_session_providers.dart';
import 'data_export.dart';
import 'server_export.dart';
import 'data_export_sink.dart';

/// Runs L0c: gathers everything about the signed-in user and hands it to
/// [DataExportSink].
///
/// A [Notifier] rather than a bare async function so the settings tile can
/// show a spinner and an error state the same way every other action on that
/// page already does (`ProfileSubmit`, `ScheduleSessionAction`).
/// A3 — the server-side assembler. Overridden in `main.dart` with the real
/// callable client; the default is the fake so a widget test never reaches the
/// network, the same shape as `dataExportSinkProvider` beside it.
final serverExportProvider = Provider<ServerExport>((_) => FakeServerExport());

class DataExportAction extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> export() async {
    state = const AsyncValue.loading();
    try {
      // `await ... .future`, not `ref.read(...).valueOrNull`. The bare read
      // was the same collapse S2 removed from the catalog providers: on a
      // container where nothing has warmed `authUserProvider` up yet, its
      // first synchronous read is `AsyncLoading`, `valueOrNull` is null, and
      // "not resolved yet" reads as "signed out" -- a caught-by-test bug
      // here, and a real race in production for whoever taps Export in the
      // same frame auth settles.
      final user = await ref.read(authUserProvider.future);
      if (user == null) {
        throw StateError('Cannot export data while signed out');
      }

      final profileRepo = ref.read(profileRepositoryProvider);
      final profile = await ref.read(currentProfileProvider.future) ??
          await profileRepo.load(user.uid) ??
          UserProfile.empty(user.uid);

      // Bounded, unlike a bare `await`. Without a timeout here a stalled
      // network call (not an error -- a call that simply never resolves)
      // left `exportState.isLoading` true forever: the settings tile disables
      // its own `onTap` while loading, so a user in that state has no error,
      // no retry, and no way to back out except leaving the screen.
      const readTimeout = Duration(seconds: 30);
      // F3.3 read-convergence: workout_sessions is the superset of
      // workout_logs after the backfill, and the only collection new
      // completions write to after F3.4 -- reading workout_logs here would
      // silently start missing every workout logged after that point.
      // Expanded through the same WorkoutLogEntry adapter every other
      // consumer uses (R11e: `expand`, not `map` -- a multi-exercise session
      // contributes one export row per exercise, not just its first). Filtered
      // to completed sessions first -- exportAll() is deliberately unwindowed
      // and unfiltered (every session, any status), but asLogEntries()
      // synthesizes completedAt = startedAt for a session with none; without
      // this filter a pending/abandoned session would export as an ordinary
      // finished workout with a fabricated completion time. Same filter
      // workoutSessionHistoryProvider applies for every other consumer.
      final workoutLogs = (await ref
              .read(workoutSessionRepositoryProvider)
              .exportAll(user.uid)
              .timeout(readTimeout))
          .where((s) =>
              s.status == WorkoutSessionStatus.completed &&
              s.completedAt != null)
          .expand((s) => s.asLogEntries())
          .toList();
      final scheduledSessions = await ref
          .read(scheduledSessionRepositoryProvider)
          .exportAll(user.uid)
          .timeout(readTimeout);
      final programmes = await ref
          .read(programmeRepositoryProvider)
          .exportAll(user.uid)
          .timeout(readTimeout);

      // A snapshot of whatever the mock currently holds -- see
      // ProgressPhotosRepository's own doc comment (M0) for why that is
      // honest rather than a gap: this feature has no real backend yet, so
      // there is nothing more durable to read.
      //
      // Falls back to empty on timeout rather than failing the whole export,
      // because profile + workout history is still worth delivering when only
      // photos stall. `photosIncomplete` is what stops that fallback from
      // reading as "you have no photos" -- see buildExport's own doc comment.
      var photosIncomplete = false;
      final progressPhotos = await ref
          .read(progressPhotosRepositoryProvider)
          .watch()
          .first
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              photosIncomplete = true;
              return const <ProgressPhoto>[];
            },
          );

      // A3. The server half, fetched in parallel with nothing else because it
      // is the last thing needed. Null on failure rather than an exception:
      // losing the local export too would punish the user twice for one
      // callable being down.
      final server = await ref.read(serverExportProvider).fetch();

      final json = buildExportJson(
        profile: profile,
        workoutLogs: workoutLogs,
        scheduledSessions: scheduledSessions,
        programmes: programmes,
        progressPhotos: progressPhotos,
        progressPhotosIncomplete: photosIncomplete,
        server: server,
      );

      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      await ref.read(dataExportSinkProvider).deliver(
            filename: 'fitness-app-export-$stamp.json',
            contents: json,
          );

      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final dataExportActionProvider =
    NotifierProvider<DataExportAction, AsyncValue<void>>(
        DataExportAction.new);
