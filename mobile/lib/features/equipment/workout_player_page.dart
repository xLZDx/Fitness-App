import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/smooth_scroll_list.dart';
import '../form_check/state/form_check_providers.dart';
import '../programmes/data/programme_labels.dart';
import '../programmes/state/programme_providers.dart';
import '../safety/data/eligibility.dart' show eligibleExercises;
import '../safety/state/eligibility_providers.dart' show safetyContextProvider;
import '../safety/widgets/eligibility_notice.dart';
import 'widgets/exercise_reference.dart';
import 'widgets/safety_disclosure.dart';
import '../workouts/data/progression.dart';
import '../workouts/data/scheduled_session.dart';
import '../workouts/data/workout_session.dart';
import '../profile/state/profile_providers.dart';
import '../workouts/state/scheduled_session_providers.dart';
import '../workouts/state/workout_session_providers.dart';
import '../workouts/widgets/difficulty_rating_sheet.dart';
import '../workouts/widgets/plate_calculator.dart';
import '../workouts/state/rest_timer_providers.dart';
import '../workouts/state/set_timer_providers.dart';
import '../workouts/widgets/rest_timer.dart';
import '../workouts/widgets/set_capture_sheet.dart';
import '../home/home_page.dart' show formatScheduleLabel;
import '../workouts/widgets/set_timer_card.dart';
import '../workouts/widgets/warmup_calculator.dart';
import 'data/equipment_models.dart';
import 'state/equipment_providers.dart';
import 'widgets/muscle_map.dart';

// The rest card's visibility used to be a page-local
// `StateProvider.autoDispose<bool>` here. It was the second half of a defect
// two reviewers found independently: the rest itself survives navigation by
// design, but the flag reset when the page was popped, so a rest in progress
// had no way back onto the screen and simply vanished. Visibility is now
// derived from the rest — `restTimerVisibleProvider`, next to the state it
// describes.

/// The log this visit has already written, if any.
///
/// `entry.id` was minted fresh on every tap
/// (`'${DateTime.now().microsecondsSinceEpoch}_...'`) and nothing deduplicated,
/// so a double-tap wrote two rows. That was harmless while every row was a
/// timestamp and a title; the moment weight and reps are captured it is not.
/// `suggestNextWeight` reads the last three sessions for this exercise
/// (`progression.dart`), so one set logged twice counts as two — and the rules
/// that fire on "three sessions in a row" fire a session early, suggesting a
/// heavier bar off a repeat tap.
///
/// The existing `loading` flag only blocks CONCURRENT taps. This blocks the
/// sequential one, and gives the edit path its identity for free: the second
/// tap reuses the id, and `save()` is `doc(id).set(...)` — an upsert.
///
/// `autoDispose` scopes it to the visit. Coming back to the same exercise
/// tomorrow is a new set and must write a new row.
final _loggedEntryProvider =
    StateProvider.autoDispose.family<WorkoutSession?, String>((_, __) => null);

/// The id a scheduled day's log is written under.
///
/// Deterministic, unlike the single-exercise case above, which mints
/// `'<microseconds>_<exerciseId>'` once and then relies on the provider to hand
/// it back. A day cannot rely on that. `_loggedEntryProvider` is `autoDispose`
/// and scoped to the visit, so a day finished across two visits — interrupted,
/// phone locked, app killed, opened again in the evening — has no id to hand
/// back on the second one. A fresh timestamp there opens a SECOND row for a day
/// that is supposed to be one workout, which is precisely what keying the
/// session by the day was meant to stop. Derived from the day instead,
/// `save()`'s `doc(id).set(...)` lands back on the same document however many
/// times the page is rebuilt.
String daySessionId(String dayId) => 'day_$dayId';

/// The day's log as it currently stands: what this visit wrote, or what is
/// already persisted when this visit has not written yet.
///
/// The fallback is not defensive padding. `save()` writes the whole document,
/// so logging exercise three against an empty `already` would replace exercises
/// one and two with three alone — a stable id with stale content is worse than
/// the duplicate row it was meant to prevent. The case that needs it is
/// finishing a day across two visits: on the second one the in-memory copy is
/// gone by design and only the persisted session knows what the day holds.
///
/// It returns null both for "this day has nothing logged" and for "the stream
/// has not delivered yet", and the caller has to tell those apart before
/// writing — see `_MarkCompleteButton.onTap`, which waits rather than guess.
///
/// [watch] because the callers split: `build` must rebuild when the stream
/// delivers, a tap callback must not subscribe.
WorkoutSession? _daySession(WidgetRef ref, String dayId, {bool watch = false}) {
  final live = watch
      ? ref.watch(_loggedEntryProvider(dayId))
      : ref.read(_loggedEntryProvider(dayId));
  if (live != null) return live;
  final id = daySessionId(dayId);
  final stored = watch
      ? ref.watch(workoutSessionsProvider)
      : ref.read(workoutSessionsProvider);
  return stored.valueOrNull?.where((s) => s.id == id).firstOrNull;
}

/// Compound lifts get a longer rest window than accessories. Read off
/// muscle tags so we don't have to maintain a parallel list.
int _restSecondsFor(ExerciseItem item) {
  final muscles = item.muscles.toSet();
  final isCompound = muscles.intersection({
        'quads',
        'hamstrings',
        'glutes',
        'chest',
        'back',
        'lats',
        'core',
      }).length >=
      2;
  return isCompound ? 180 : 90;
}

// The lookup this page used to own moved to `exerciseResolutionProvider` in
// `state/equipment_providers.dart`. Its scan read `equipmentRepositoryProvider`
// directly, which meant a deep link to `/workout/:id` never passed the safety
// filter the lists apply — and privatising the list providers would not have
// changed that by one line, because this branch never read them.

class WorkoutPlayerPage extends ConsumerWidget {
  const WorkoutPlayerPage({
    super.key,
    required this.exerciseId,
    this.dayId,
  });

  final String exerciseId;

  /// The scheduled day this visit belongs to, or null when the player was
  /// opened on a single exercise (a scan, a deep link, the AI planner).
  ///
  /// Nullable rather than a second page, because the two differ in exactly two
  /// things: whether the day strip is drawn, and what the session is keyed by.
  /// Everything else on this 970-line page — the clip, the technique, the
  /// timer, the rest, the rating — is identical, and a copy of it would have to
  /// be kept identical by hand forever.
  final String? dayId;

  /// What the logged session is keyed by, and therefore what counts as ONE
  /// workout.
  ///
  /// Inside a day this is the day, so exercises two, three and four write into
  /// the session exercise one created instead of each starting their own. That
  /// is the whole point of the gate: a four-exercise day was being recorded as
  /// four separate workouts, which made every streak, count and weekly total
  /// read four times too high.
  ///
  /// Outside a day it stays the exercise id — unchanged behaviour for the scan
  /// and deep-link paths, which have no day to belong to.
  String get _sessionKey => dayId ?? exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final exercise = ref.watch(exerciseResolutionProvider(exerciseId));

    return FrostedScaffold(
      appBar: GlassAppBar(title: AppLocalizations.of(context).equipmentWorkout),
      body: exercise.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: Text(AppLocalizations.of(context).equipmentCouldNotLoad(e))),
        data: (resolution) {
          // Withheld, not missing. Saying "we couldn't find that exercise" to
          // someone who was linked to it — from their own scheduled session,
          // or a friend, or a plan — is false, and it hides the one fact they
          // can act on: it is their own injury list doing this, and they can
          // change it.
          if (resolution.hiddenForInjury) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 92, 20, 24),
              child: GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)
                          .equipmentHiddenForInjury(resolution.exercise!.title),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.of(context).equipmentHiddenForInjuryHint,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            );
          }
          // Withheld for a reason that is not an injury — the screening, a
          // movement restriction, post-operative restrictions. Before Gate N
          // this fell through to "we couldn't find that exercise", which is
          // the exact lie the branch above exists to avoid, told for a
          // different reason.
          if (resolution.visible == null && resolution.exercise != null) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 92, 20, 24),
              child: EligibilityNotice(
                key: const Key('player.withheld'),
                reasons: resolution.withheldFor,
                onReviewProfile: () => GoRouter.of(context).push('/onboarding'),
              ),
            );
          }
          final item = resolution.visible;
          if (item == null) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 92, 20, 24),
              child: GlassCard(
                child: Text(
                  AppLocalizations.of(context)
                      .equipmentWeCouldnTFindThatExercise,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            );
          }
          // Which body to demonstrate on. Read from the profile, and null when
          // the user has not said or has said they would rather not — in which
          // case there is nothing to infer from, and the model falls back to
          // whichever clip exists.
          final body = ExerciseItem.bodyForGender(
              ref.watch(currentProfileProvider).valueOrNull?.personal.gender);
          final demoVideo = item.playableVideoFor(body) ?? item.videoUrl;
          return SmoothScrollList(
            padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
            children: [
              // F020: this screen builds its own list rather than calling
              // `exerciseReferenceSections`, so it needs the same
              // catalog-wide "screened by rules, not a clinician" disclosure
              // inserted separately -- see that function's own comment.
              const SafetyDisclosure(compact: true),
              const SizedBox(height: 16),
              // Above the exercise, not below it: the first question someone
              // who tapped a day has is "what am I doing today and where am I
              // in it", and that has to be answerable without scrolling past
              // a video.
              if (dayId != null) ...[
                _DayStrip(dayId: dayId!, currentExerciseId: exerciseId),
                const SizedBox(height: 16),
              ],
              ExerciseHero(exercise: item),
              const SizedBox(height: 16),
              // A clip or nothing. The two photograph fallbacks that used to sit
              // here are gone: `frames` and `imageUrls` are both stills of a man
              // in a gym, and putting either in front of an exercise made the
              // catalog look like two different apps stitched together.
              //
              // Lists cannot reach this state at all — `withDemonstration`
              // removes those exercises upstream. This page can still be opened
              // by deep link or from a logged workout, so the honest card has to
              // exist here too rather than relying on nobody arriving.
              if (demoVideo != null)
                ExerciseVideoBlock(url: demoVideo, poster: item.posterFor(body))
              else
                ExerciseNoVideoFallback(),
              if (item.muscles.isNotEmpty) ...[
                const SizedBox(height: 16),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppLocalizations.of(context).equipmentMusclesWorked,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      MuscleMap(
                        primary: item.primaryMuscles.isEmpty
                            ? item.muscles.take(1).toList()
                            : item.primaryMuscles,
                        secondary: item.muscles
                            .where((m) => !item.primaryMuscles.contains(m))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ExerciseStepsCard(exercise: item),
              // Right under the technique steps, which is where the design
              // puts it and where it belongs: you have just read how the
              // movement should look, and this offers to watch you do it.
              //
              // Shown ONLY where the coach can actually judge the movement --
              // `formCoachSupports`, not merely `poseTargetId != null`. 570
              // catalog rows carry a pattern tag; one pattern has authored
              // targets AND a rep signal. Offering the other seven would teach
              // users the feature is broken, and that lesson is expensive to
              // undo.
              if (formCoachSupports(item.poseTargetId)) ...[
                const SizedBox(height: 16),
                ExerciseFormCoachCard(),
              ],
              if (item.contraindications.isNotEmpty) ...[
                const SizedBox(height: 16),
                ExerciseCautionCard(item: item),
              ],
              const SizedBox(height: 12),
              _SuggestedWeightChip(exerciseId: item.id),
              const SizedBox(height: 16),
              // Above the tools and below the instructions: you read how to do
              // it, then you do it. Operator: "к упражнения нужно добавить
              // таймер... нужна кнопка начать упражнение".
              SetTimerCard(exercise: item),
              const SizedBox(height: 12),
              _ToolsRow(),
              if (ref.watch(restTimerVisibleProvider)) ...[
                const SizedBox(height: 12),
                // The duration is set where the set is logged, not here: the
                // card renders whatever rest is in progress, and a widget that
                // took a duration would restart one on every rebuild.
                const RestTimer(),
              ],
              const SizedBox(height: 20),
              _MarkCompleteButton(
                exercise: item,
                sessionKey: _sessionKey,
                inDay: dayId != null,
              ),
              const SizedBox(height: 12),
              _AddExerciseButton(
                entryExercise: item,
                sessionKey: _sessionKey,
                inDay: dayId != null,
              ),
              const SizedBox(height: 12),
              _ScheduleButton(exercise: item),
              const SizedBox(height: 12),
              _AddToProgrammeButton(exercise: item),
            ],
          );
        },
      ),
    );
  }
}

/// The day this visit belongs to: where you are in it, and what is left.
///
/// Reads the plan from [scheduledSessionsProvider] and what has actually been
/// logged from the session keyed by the day, so a tick means "this exercise is
/// in today's record", not "you tapped it". Those differ — a tap that failed to
/// save must not be shown as done.
///
/// Renders nothing at all when the day cannot be resolved (still streaming, or
/// the day was cancelled from another device mid-workout). An empty box is the
/// right answer there: the exercise below is still perfectly usable, and a
/// spinner or an error card above it would suggest the workout itself is
/// broken when it is not.
class _DayStrip extends ConsumerWidget {
  const _DayStrip({required this.dayId, required this.currentExerciseId});

  final String dayId;
  final String currentExerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final day = ref
        .watch(scheduledSessionsProvider)
        .valueOrNull
        ?.where((s) => s.id == dayId)
        .firstOrNull;
    if (day == null) return const SizedBox.shrink();

    final planned = day.exercises;
    if (planned.length < 2) return const SizedBox.shrink();

    final logged = _daySession(ref, dayId, watch: true);
    final doneIds = {
      for (final e in logged?.exercises ?? const []) e.exerciseId,
    };
    final position =
        planned.indexWhere((e) => e.exerciseId == currentExerciseId);

    return GlassCard(
      key: const Key('player.dayStrip'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // `position + 1` only when the current exercise is actually part of
            // the plan. It is not always: the add-exercise button can put an
            // off-plan movement on screen inside a day, and "exercise 0 of 4"
            // is worse than just naming the day's size.
            position >= 0
                ? l.equipmentDayProgress(position + 1, planned.length)
                : l.equipmentDayExercises(planned.length),
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          for (final (index, e) in planned.indexed) ...[
            if (index > 0) const SizedBox(height: 2),
            _DayStripRow(
              title: e.exerciseTitle,
              done: doneIds.contains(e.exerciseId),
              current: e.exerciseId == currentExerciseId,
              // Tapping the exercise you are already on would push a second
              // copy of this page onto the stack, so it is inert.
              onTap: e.exerciseId == currentExerciseId
                  ? null
                  : () => GoRouter.of(context)
                      .replace('/workout/${e.exerciseId}?day=$dayId'),
            ),
          ],
        ],
      ),
    );
  }
}

class _DayStripRow extends StatelessWidget {
  const _DayStripRow({
    required this.title,
    required this.done,
    required this.current,
    required this.onTap,
  });

  final String title;
  final bool done;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = Theme.of(context).extension<AppSemanticColors>();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(
              done
                  ? Icons.check_circle_rounded
                  : current
                      ? Icons.play_circle_fill_rounded
                      : Icons.circle_outlined,
              size: 20,
              color: done
                  ? semantic?.success ?? theme.colorScheme.primary
                  : current
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.35),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: current ? FontWeight.w800 : FontWeight.w500,
                  // Struck through rather than greyed out: a finished exercise
                  // still has to be readable, because re-opening it to fix a
                  // mistyped weight is a normal thing to want.
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkCompleteButton extends ConsumerWidget {
  const _MarkCompleteButton({
    required this.exercise,
    required this.sessionKey,
    required this.inDay,
  });
  final ExerciseItem exercise;

  /// See [WorkoutPlayerPage._sessionKey] — the day inside a day, the exercise
  /// otherwise.
  final String sessionKey;

  /// Selects how this exercise is merged into the session. Inside a day it is
  /// matched by `exerciseId`, because it may be exercise three of four and must
  /// not overwrite exercise one.
  final bool inDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(logSessionActionProvider);
    final theme = Theme.of(context);
    final loading = action.isLoading;

    Future<void> onTap() async {
      var already = inDay
          ? _daySession(ref, sessionKey)
          : ref.read(_loggedEntryProvider(sessionKey));

      // Nothing known about the day AND no snapshot has arrived yet: WAIT for
      // one before writing.
      //
      // This is the cold-start race, and it is a data-loss bug rather than a
      // cosmetic one. `save()` is `doc(id).set(...)` with no merge
      // (`firestore_workout_session_repository.dart:61-63`), so a tap that
      // lands before the first Firestore snapshot would build the day's
      // document out of THIS exercise alone and overwrite the two already
      // logged — silently, with "Logged! Nice work" on screen. The window is
      // invisible on a warm start and entirely plausible on a cold one.
      //
      // Awaiting the stream rather than disabling the button: a disabled
      // button that never re-enables (a history stream that errors) is its own
      // silent failure, and the error path below already knows how to tell the
      // user that saving did not happen.
      if (inDay &&
          already == null &&
          !ref.read(workoutSessionsProvider).hasValue) {
        try {
          await ref.read(workoutSessionsProvider.future);
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  AppLocalizations.of(context).equipmentCouldNotSave('$e')),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        if (!context.mounted) return;
        already = _daySession(ref, sessionKey);
      }
      // Inside a day the row to re-edit is THIS exercise's, which is not
      // necessarily the first one in the session — `.exercises.first` would
      // have read exercise one's weight back onto exercise three.
      final stored = already == null
          ? null
          : inDay
              ? already.exercises
                  .where((e) => e.exerciseId == exercise.id)
                  .firstOrNull
              : already.exercises.first;
      final alreadySet =
          stored != null && stored.sets.isNotEmpty ? stored.sets.last : null;

      // B8. No sheet here any more. The weight is collected when the set is
      // STARTED (`SetTimerCard`), and only for movements that take one --
      // operator, 2026-08-13: *"не спрашивать вес вообще если для упражнения
      // вес не нужен"*. Finishing a press-up used to open a weight form and
      // then a rating sheet back to back, and the only way through the first
      // was Skip, every time.
      //
      // Whatever the timer collected wins; an exercise finished without ever
      // starting the timer keeps whatever was already stored, which is what a
      // re-tap on an already-logged exercise should do.
      final captured = ref.read(setLoadProvider(exercise.id));

      // F3.4: one exercise, at most one set per session -- same shape the
      // F3.3 backfill produces (see backfill_workout_sessions.mjs's own
      // toSession()) and the one asLogEntryView() assumes throughout. A
      // repeat tap overwrites this one set rather than appending a second,
      // same behavior as the old WorkoutLogEntry.copyWith did.
      //
      // `captured == null` (the timer was never started, or the movement takes
      // no load) keeps the stored values. `captured != null` uses exactly what
      // was submitted, INCLUDING a null field the user cleared on purpose
      // ("declined to say") -- a `captured?.weightKg ?? alreadySet?.weightKg`
      // here would silently restore the old weight the moment the user tried
      // to blank it out, contradicting the sheet's own "leave blank if no
      // load" hint.
      final weightKg =
          captured == null ? alreadySet?.weightKg : captured.weightKg;
      final reps = captured == null ? alreadySet?.reps : captured.reps;
      final sets = (weightKg != null || reps != null)
          ? [(weightKg: weightKg, reps: reps)]
          : const <SetCapture>[];
      final exerciseEntry = (stored ??
              WorkoutSessionExercise(
                exerciseId: exercise.id,
                exerciseTitle: exercise.title,
              ))
          .copyWith(sets: sets);

      // Same id on a repeat tap, so `save()` -- `doc(id).set(...)` -- updates
      // the row instead of adding a second one for the same set.
      final entry = (already ??
              WorkoutSession(
                // See `daySessionId` — a day's row must be findable again
                // after the provider holding it has been disposed.
                id: inDay
                    ? daySessionId(sessionKey)
                    : '${DateTime.now().microsecondsSinceEpoch}_$sessionKey',
                title: exercise.title,
                exercises: const [],
                startedAt: DateTime.now(),
              ))
          .copyWith(
        // R11e: replaceEntryExercise keeps any exercise `_AddExerciseButton`
        // has appended after index 0 -- `exercises: [exerciseEntry]` here
        // used to drop them the moment this entry exercise's set was
        // re-edited.
        //
        // Inside a day, position no longer identifies "the exercise being
        // logged": this can be exercise three, and index 0 belongs to exercise
        // one. Keyed by id there, by position everywhere else — see
        // `upsertExerciseById`'s doc comment for why both exist.
        exercises: inDay
            ? upsertExerciseById(already?.exercises ?? const [], exerciseEntry)
            : replaceEntryExercise(
                already?.exercises ?? const [], exerciseEntry),
        completedAt: DateTime.now(),
        status: WorkoutSessionStatus.completed,
        // `already?.durationMinutes` when a session already exists --
        // `_AddExerciseButton` is what grows this number when it appends an
        // exercise (each exercise's own `durationMinutes` lives on
        // `ExerciseItem`, not on the stored `WorkoutSessionExercise`, so
        // there is nothing to re-sum from the tail here; re-editing THIS
        // exercise's set does not change how many exercises are in the
        // session). Falls back to this exercise's own duration only on the
        // very first tap, when no session exists yet.
        //
        // Inside a day there is a third case the original two did not cover:
        // this exercise may be NEW to an existing session (exercise two of the
        // day, logged into the session exercise one opened). Then its minutes
        // have to be added, exactly as `_AddExerciseButton` adds them — without
        // this a four-exercise day would report the length of its first
        // exercise. `stored != null` is the re-edit case and must add nothing,
        // or every re-tap would inflate the number.
        durationMinutes: already == null
            ? exercise.durationMinutes
            : (inDay && stored == null)
                ? (already.durationMinutes ?? 0) + exercise.durationMinutes
                : already.durationMinutes,
      );
      await ref.read(logSessionActionProvider.notifier).log(entry);
      if (!context.mounted) return;
      final newState = ref.read(logSessionActionProvider);
      if (newState.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)
                .equipmentCouldNotSave(newState.error ?? '')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      // Success — confirm + show rest timer.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)
              .equipmentLoggedNiceWork(exercise.title)),
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Strictly after the await above and after the error check, which is the
      // ordering §17 asks for: Complete Set -> Persist Set -> Rest Timer. A
      // rest that started optimistically would count down over a set that
      // never got written.
      ref
          .read(restTimerProvider.notifier)
          .start(Duration(seconds: _restSecondsFor(exercise)));
      ref.read(_loggedEntryProvider(sessionKey).notifier).state = entry;

      // Ask for a 1-tap perceived-effort rating. Skipping is fine — the
      // rating is optional, and Freeletics' AI Coach reads a similar
      // signal, but only this app combines it with injury filtering and
      // progressive overload (P1.1 + P1.2 of the roadmap).
      if (!context.mounted) return;
      final rating = await DifficultyRatingSheet.show(
        context,
        exerciseTitle: exercise.title,
      );
      if (rating != null) {
        // Same replaceEntryExercise as above -- rating exercise #1 must not
        // erase exercises #2+. And inside a day the rating belongs to the
        // exercise that was just finished, which `.first` would have pinned to
        // exercise one: rating exercise three would have relabelled exercise
        // one's difficulty and left three unrated.
        final justLogged = inDay
            ? entry.exercises.firstWhere((e) => e.exerciseId == exercise.id)
            : entry.exercises.first;
        final rated = entry.copyWith(
          exercises: inDay
              ? upsertExerciseById(
                  entry.exercises, justLogged.copyWith(difficulty: rating))
              : replaceEntryExercise(
                  entry.exercises, justLogged.copyWith(difficulty: rating)),
        );
        await ref.read(logSessionActionProvider.notifier).log(rated);
        ref.read(_loggedEntryProvider(sessionKey).notifier).state = rated;
      }
    }

    return GlassCard(
      // Keyed so a test can drive the write path rather than only the pure
      // merge function beneath it. The invariant this gate exists for -- a day
      // is ONE session -- lives in what this button assembles, not in
      // `upsertExerciseById`, and a unit test of the latter passes happily
      // while the former overwrites the day.
      key: const Key('player.markComplete'),
      padding: EdgeInsets.zero,
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(colors: [
            AppPalette.auroraTeal,
            AppPalette.auroraBlue,
          ]),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading) ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      AppSemanticColors.onGradientInk),
                ),
              ),
              const SizedBox(width: 10),
            ] else ...[
              const Icon(Icons.check_rounded,
                  color: AppSemanticColors.onGradientInk),
              const SizedBox(width: 8),
            ],
            Text(
              loading
                  ? AppLocalizations.of(context).equipmentSaving
                  : AppLocalizations.of(context).equipmentMarkComplete,
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppSemanticColors.onGradientInk,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// R11e: lets a session grow past its entry exercise -- "один поход в
/// тренажерный зал это одна тренировка на разных тренажерах", the
/// operator's own resolution of R11e's blocking question (a session is one
/// workout no matter how many exercises it holds; see
/// `WorkoutSessionLogView.asLogEntries`'s doc comment for how that is kept
/// true in the stats).
///
/// Hidden until [entryExercise] itself has been logged
/// (`_loggedEntryProvider(entryExercise.id)` non-null) -- there is no session
/// to add a second exercise TO before the first one exists. Reuses the exact
/// [SetCaptureSheet] / [DifficultyRatingSheet] flow [_MarkCompleteButton]
/// already uses, so a second exercise is captured exactly like the first.
class _AddExerciseButton extends ConsumerWidget {
  const _AddExerciseButton({
    required this.entryExercise,
    required this.sessionKey,
    required this.inDay,
  });
  final ExerciseItem entryExercise;

  /// See [WorkoutPlayerPage._sessionKey]. Inside a day this is the day, so an
  /// exercise added by hand joins the day's session rather than opening a
  /// second one alongside it.
  final String sessionKey;

  /// See [_MarkCompleteButton.inDay]. Here it selects where the session is read
  /// from: inside a day the persisted row counts, so the button stays available
  /// on exercise two of a day whose first exercise was logged before the last
  /// route replace — without it the button would vanish exactly when the
  /// session it appends to does exist.
  final bool inDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final already = inDay
        ? _daySession(ref, sessionKey, watch: true)
        : ref.watch(_loggedEntryProvider(sessionKey));
    if (already == null) return const SizedBox.shrink();

    final action = ref.watch(logSessionActionProvider);
    final theme = Theme.of(context);
    final loading = action.isLoading;

    Future<void> onTap() async {
      final exclude = already.exercises.map((e) => e.exerciseId).toSet();
      // N02 (G-B/B2). `safeCatalogProvider` applies `safeFor`, which is the
      // INJURY filter and nothing else — it reads `health.injuries` and stops.
      // This picker is the one unscreened list in the app whose tap is
      // terminal: what the user chooses is written straight into the logged
      // session, so there is no later screen that re-evaluates it and no
      // refusal card that could catch it afterwards. A user under a movement
      // restriction, post-operative restrictions or a clinician's advice was
      // offered every exercise those rules exist to remove.
      //
      // `eligibleExercises` is the whole layer rather than one of its rules.
      // It deliberately does NOT apply the whole-person gate (see its own
      // doc): that gate is a screen state, and this screen already answers it
      // upstream — `exerciseResolutionProvider` withholds the entry exercise
      // itself for a whole-person block, so a refused user never reaches this
      // button.
      final catalog = await ref.read(safeCatalogProvider.future);
      final safety = await ref.read(safetyContextProvider.future);
      final candidates = eligibleExercises(catalog, safety)
          .where((e) => !exclude.contains(e.id))
          .toList();
      if (!context.mounted) return;
      final picked = await _ExercisePickerSheet.show(context, candidates);
      if (picked == null || !context.mounted) return;

      // B8 applies here too. This one keeps its sheet — an exercise appended
      // by hand is never "started", so there is no earlier moment to ask at —
      // but it is skipped entirely for a movement that takes no load, which is
      // the half of the complaint that was about press-ups and crunches.
      final captured = exerciseUsesLoad(
        equipmentId: picked.equipmentId,
        isStretch: picked.isStretch,
      )
          ? await SetCaptureSheet.show(context, exerciseTitle: picked.title)
          : null;
      if (!context.mounted) return;

      final sets = (captured?.weightKg != null || captured?.reps != null)
          ? [(weightKg: captured?.weightKg, reps: captured?.reps)]
          : const <SetCapture>[];
      var newExercise = WorkoutSessionExercise(
        exerciseId: picked.id,
        exerciseTitle: picked.title,
        sets: sets,
      );

      if (!context.mounted) return;
      final rating = await DifficultyRatingSheet.show(
        context,
        exerciseTitle: picked.title,
      );
      if (rating != null) {
        newExercise = newExercise.copyWith(difficulty: rating);
      }
      if (!context.mounted) return;

      final updated = already.copyWith(
        exercises: [...already.exercises, newExercise],
        completedAt: DateTime.now(),
        // Parenthesized deliberately: `??` binds looser than `+`, so
        // `already.durationMinutes ?? 0 + picked.durationMinutes` would have
        // ignored the addition entirely whenever `durationMinutes` was
        // already non-null -- i.e. always, since `already` is a session that
        // has already completed once.
        durationMinutes:
            (already.durationMinutes ?? 0) + picked.durationMinutes,
      );
      await ref.read(logSessionActionProvider.notifier).log(updated);
      if (!context.mounted) return;
      final newState = ref.read(logSessionActionProvider);
      if (newState.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)
                .equipmentCouldNotSave(newState.error ?? '')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      ref.read(_loggedEntryProvider(sessionKey).notifier).state = updated;
      // Same ordering as _MarkCompleteButton: persist THEN rest, never the
      // reverse.
      ref
          .read(restTimerProvider.notifier)
          .start(Duration(seconds: _restSecondsFor(picked)));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)
              .equipmentLoggedNiceWork(picked.title)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    return GlassCard(
      key: const Key('player.addExercise'),
      padding: EdgeInsets.zero,
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Colors.white.withValues(alpha: 0.32),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading) ...[
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                  const SizedBox(width: 10),
                ] else ...[
                  Icon(Icons.add_circle_outline,
                      color: theme.colorScheme.onSurface),
                  const SizedBox(width: 8),
                ],
                // `Flexible`, so the label wraps on a narrow screen instead of
                // overflowing the card. It really did overflow — by 31px at
                // 400px wide, which is an ordinary phone. Nothing had caught it
                // because this button only appears once a session exists, and
                // until the day gate no test could reach that state. Wrapping
                // rather than ellipsising: half a button label is not a label.
                Flexible(
                  child: Text(
                    AppLocalizations.of(context).equipmentAddAnotherExercise,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context)
                  .equipmentSessionExerciseCount(already.exercises.length),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet listing exercises not yet in the current session. Returns the
/// tapped [ExerciseItem], or null on dismiss.
class _ExercisePickerSheet extends StatelessWidget {
  const _ExercisePickerSheet({required this.candidates});
  final List<ExerciseItem> candidates;

  static Future<ExerciseItem?> show(
      BuildContext context, List<ExerciseItem> candidates) {
    return showModalBottomSheet<ExerciseItem>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ExercisePickerSheet(candidates: candidates),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context).equipmentPickAnotherExercise,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: candidates.isEmpty
                  ? Center(
                      child: Text(AppLocalizations.of(context)
                          .equipmentNoOtherExercises))
                  : ListView.builder(
                      controller: controller,
                      itemCount: candidates.length,
                      itemBuilder: (context, i) {
                        final e = candidates[i];
                        return ListTile(
                          key: Key('picker.exercise.${e.id}'),
                          title: Text(e.title),
                          subtitle: e.muscles.isEmpty
                              ? null
                              : Text(e.muscles.take(3).join(' · ')),
                          onTap: () => Navigator.of(context).pop(e),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Row of small "tool" chips below the steps card. Opens a bottom sheet
/// with the plate calculator + warm-up calculator. Cheap utility every
/// lifter app has; we used to ship without.
class _ToolsRow extends StatelessWidget {
  const _ToolsRow();

  void _openSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          child: const Column(
            children: [
              PlateCalculator(),
              SizedBox(height: 14),
              WarmupCalculator(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ActionChip(
          avatar: const Icon(Icons.fitness_center_rounded, size: 18),
          label: Text(AppLocalizations.of(context).equipmentPlates),
          labelStyle: theme.textTheme.labelLarge,
          onPressed: () => _openSheet(context),
        ),
        ActionChip(
          avatar: const Icon(Icons.local_fire_department_rounded, size: 18),
          label: Text(AppLocalizations.of(context).equipmentWarmUp),
          labelStyle: theme.textTheme.labelLarge,
          onPressed: () => _openSheet(context),
        ),
      ],
    );
  }
}

class _ScheduleButton extends ConsumerWidget {
  const _ScheduleButton({required this.exercise});
  final ExerciseItem exercise;

  Future<DateTime?> _pick(BuildContext context) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !context.mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 7, minute: 0),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(scheduleSessionActionProvider);
    final theme = Theme.of(context);
    final loading = action.isLoading;

    Future<void> onTap() async {
      final when = await _pick(context);
      if (when == null || !context.mounted) return;
      final session = ScheduledSession(
        id: '${DateTime.now().microsecondsSinceEpoch}_${exercise.id}',
        exerciseId: exercise.id,
        exerciseTitle: exercise.title,
        scheduledFor: when,
        durationMinutes: exercise.durationMinutes,
      );
      await ref.read(scheduleSessionActionProvider.notifier).schedule(session);
      if (!context.mounted) return;
      final newState = ref.read(scheduleSessionActionProvider);
      newState.when(
        data: (_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).equipmentScheduledFor(
                  exercise.title,
                  formatScheduleLabel(AppLocalizations.of(context), when))),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        error: (e, _) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  AppLocalizations.of(context).equipmentCouldNotSchedule(e)),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        loading: () {},
      );
    }

    return GlassCard(
      padding: EdgeInsets.zero,
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Colors.white.withValues(alpha: 0.32),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading) ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(width: 10),
            ] else ...[
              Icon(Icons.event_outlined, color: theme.colorScheme.onSurface),
              const SizedBox(width: 8),
            ],
            Text(
              loading
                  ? AppLocalizations.of(context).equipmentScheduling
                  : AppLocalizations.of(context).equipmentScheduleForLater,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gate P: "add this exercise to my programme" — the button R11d's own doc
/// comment named as wanting "nothing to add to" before the programme entity
/// existed (`programmes/data/programme.dart`).
///
/// Two states, not a picker: with an active programme, tapping schedules
/// [exercise] at [nextProgrammeSlot] under it (`programme_providers.dart`) —
/// same one-tap shape as [_ScheduleButton], minus the date/time pickers,
/// since the programme already owns the cadence. With none active, tapping
/// routes to Workouts (where R11i's Programs tab lets the user enrol)
/// instead of showing a dead control — the same choice this page already
/// made for the notification bell it does not have (`home_page.dart`'s own
/// doc comment on fabrication).
class _AddToProgrammeButton extends ConsumerWidget {
  const _AddToProgrammeButton({required this.exercise});
  final ExerciseItem exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final programme = ref.watch(activeProgrammeProvider);
    final action = ref.watch(programmeActionProvider);
    final theme = Theme.of(context);
    final loading = action.isLoading;

    Future<void> onTap() async {
      if (programme == null) {
        GoRouter.of(context).push('/workouts');
        return;
      }
      await ref
          .read(programmeActionProvider.notifier)
          .addExerciseToActiveProgramme(exercise);
      if (!context.mounted) return;
      final newState = ref.read(programmeActionProvider);
      newState.when(
        data: (_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              // `Programme.title` is the raw stored id, not a display name —
              // B2a made it a fallback and moved the real names into the ARB
              // files behind `ProgrammeLabels` (`programme_providers.dart:119-125`).
              // This was the one reader left holding the raw value, so the
              // snackbar has been reading "Added to strength_base". B5d-2's
              // sentinel would have turned that into "Added to from_answers",
              // which is what made it visible.
              content: Text(AppLocalizations.of(context)
                  .programmeAddedToSchedule(ProgrammeLabels.title(
                      AppLocalizations.of(context), programme.templateId,
                      stored: programme.title))),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        error: (e, _) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  AppLocalizations.of(context).equipmentCouldNotSchedule(e)),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        loading: () {},
      );
    }

    return GlassCard(
      key: const Key('player.addToProgramme'),
      padding: EdgeInsets.zero,
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Colors.white.withValues(alpha: 0.32),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading) ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(width: 10),
            ] else ...[
              Icon(Icons.playlist_add, color: theme.colorScheme.onSurface),
              const SizedBox(width: 8),
            ],
            Text(
              AppLocalizations.of(context).equipmentAddToProgramme,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reads the user's recent logs for [exerciseId] and surfaces the next
/// suggested weight via [suggestNextWeight]. Tap to copy the value into
/// the clipboard. Hidden when there's no log history yet.
class _SuggestedWeightChip extends ConsumerWidget {
  const _SuggestedWeightChip({required this.exerciseId});
  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // F3.4: sourced from workout_sessions, the only collection new
    // completions now write to -- see progress_page.dart's convergence note.
    final logs = ref.watch(workoutSessionHistoryProvider);
    final history = logs.where((l) => l.exerciseId == exerciseId).toList();
    final suggestion = suggestNextWeight(historyForExercise: history);
    if (suggestion == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = suggestion.isDecrease
        ? const [AppPalette.auroraPeach, AppPalette.auroraPink]
        : const [AppPalette.auroraTeal, AppPalette.auroraLime];
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              gradient: LinearGradient(colors: colors),
            ),
            child: Icon(
              suggestion.isDecrease
                  ? Icons.south_rounded
                  : Icons.north_east_rounded,
              color: AppSemanticColors.onGradientInk,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      AppLocalizations.of(context).equipmentSuggested,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colors.textSecondary,
                      ),
                    ),
                    Text(
                      AppLocalizations.of(context).commonKilograms(
                          suggestion.suggestedKg.toStringAsFixed(
                              suggestion.suggestedKg % 1 == 0 ? 0 : 1)),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  suggestion.reason,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
