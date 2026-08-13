import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_providers.dart';
import '../../equipment/state/equipment_providers.dart';
import '../data/scheduled_session.dart';
import 'scheduled_session_providers.dart';

/// A scheduled session plus whether it is still safe for this user.
///
/// [ScheduledSession] stores an id, a title, a time and a duration
/// (`scheduled_session.dart:17-22`) — nothing about the exercise itself. So a
/// session is a snapshot taken at scheduling time and never re-examined:
/// `filterUpcoming` screens on status and date window only
/// (`scheduled_session_providers.dart:42-58`). Log a knee injury today and
/// yesterday's scheduled squat still renders on Home, and still fires its
/// reminder tomorrow.
///
/// Re-resolving at render time rather than storing a safety verdict on the
/// session is deliberate: the verdict changes when the *user* changes, not
/// when the session does, so a stored copy would be stale from the moment it
/// was written and would need its own invalidation to be correct.
class ScreenedSession {
  const ScreenedSession({
    required this.session,
    required this.hiddenExerciseIds,
  });

  final ScheduledSession session;

  /// Which of the day's exercises now conflict with a logged injury.
  ///
  /// A set rather than a single flag since B5b: a day holds several exercises,
  /// and screening only `session.exerciseId` — which is what this did — left
  /// exercises two onward unscreened on every surface that renders a scheduled
  /// day. The set is what lets the UI strike the offending row instead of
  /// striking the whole day or, worse, none of it.
  final Set<String> hiddenExerciseIds;

  /// True when ANY exercise of the day conflicts.
  ///
  /// Any, not all, and the day is flagged rather than dropped — the same
  /// choice this provider already made for the single-exercise case. A day
  /// containing one exercise the user must not do is a day they need to look
  /// at, even if the other three are fine.
  bool get hiddenForInjury => hiddenExerciseIds.isNotEmpty;

  /// True when nothing in the day is left to do.
  bool get hiddenEntirely => hiddenExerciseIds.length == session.exerciseCount;
}

/// [upcomingSessionsProvider], with each session's exercise re-resolved
/// through the catalog's safety boundary.
///
/// Flagged rather than dropped. The user put these on their own calendar; a
/// session that silently disappears looks like a bug in the app, while one
/// that says why it is struck through is a fact they can act on.
final screenedUpcomingSessionsProvider =
    FutureProvider<List<ScreenedSession>>((ref) async {
  final upcoming = ref.watch(upcomingSessionsProvider);
  final out = <ScreenedSession>[];
  for (final session in upcoming) {
    final hidden = <String>{};
    for (final exercise in session.exercises) {
      final resolution = await ref
          .watch(exerciseResolutionProvider(exercise.exerciseId).future);
      if (resolution.hiddenForInjury) hidden.add(exercise.exerciseId);
    }
    out.add(ScreenedSession(session: session, hiddenExerciseIds: hidden));
  }
  return List.unmodifiable(out);
});

/// Cancels reminders for sessions that have become contraindicated.
///
/// ## What this covers, and what it does not
///
/// A local notification fires from the OS with the app closed, so there is no
/// render pass to screen it — the only way to stop one is to cancel it before
/// it fires, which means reacting to the moment the user's injuries change.
/// That moment is a profile save, and [ProfileSubmit.submit] calls this.
///
/// Today that path is reachable exactly once, at the end of onboarding, when
/// the user has no scheduled sessions yet — so in the shipped app this
/// cancels nothing. It is written now because the gate that makes injuries
/// editable (S1a) routes through the same save, and because the alternative —
/// discovering later that reminders were the one surface the boundary did not
/// cover — is how the deep link stayed unscreened through the last round.
class SessionReminderReconciler {
  const SessionReminderReconciler(this._ref);

  final Ref _ref;

  /// Returns how many reminders were cancelled.
  Future<int> reconcile() async {
    final sessions =
        _ref.read(scheduledSessionsProvider).valueOrNull ?? const [];
    var cancelled = 0;
    for (final session in sessions) {
      if (session.status != ScheduledSessionStatus.pending) continue;
      // Every exercise of the day, not just the first: a reminder for a day
      // whose third exercise is now contraindicated is exactly as wrong as one
      // whose first is, and the OS fires it with the app closed either way.
      var conflicts = false;
      for (final exercise in session.exercises) {
        final resolution = await _ref
            .read(exerciseResolutionProvider(exercise.exerciseId).future);
        if (resolution.hiddenForInjury) {
          conflicts = true;
          break;
        }
      }
      if (!conflicts) continue;
      try {
        await _ref.read(notificationServiceProvider).cancelReminder(session.id);
        cancelled++;
      } catch (e) {
        // Best-effort, like every other reminder call in this feature — but
        // logged, because a silently un-cancelled reminder for a
        // contraindicated exercise is precisely the failure this exists to
        // prevent, and a bare swallow would make it invisible.
        debugPrint('could not cancel reminder for ${session.id}: $e');
      }
    }
    return cancelled;
  }
}

final sessionReminderReconcilerProvider =
    Provider<SessionReminderReconciler>(SessionReminderReconciler.new);
