import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/smooth_scroll_list.dart';
import '../form_check/state/form_check_providers.dart';
import 'widgets/exercise_reference.dart';
import '../workouts/data/progression.dart';
import '../workouts/data/scheduled_session.dart';
import '../workouts/data/workout_session.dart';
import '../profile/state/profile_providers.dart';
import '../workouts/state/scheduled_session_providers.dart';
import '../workouts/state/workout_session_providers.dart';
import '../workouts/widgets/difficulty_rating_sheet.dart';
import '../workouts/widgets/plate_calculator.dart';
import '../workouts/state/rest_timer_providers.dart';
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
  const WorkoutPlayerPage({super.key, required this.exerciseId});

  final String exerciseId;

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
                      AppLocalizations.of(context).equipmentHiddenForInjury(
                          resolution.exercise!.title),
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
          final body = ExerciseItem.bodyForGender(ref
              .watch(currentProfileProvider)
              .valueOrNull
              ?.personal
              .gender);
          final demoVideo = item.playableVideoFor(body) ?? item.videoUrl;
          return SmoothScrollList(
            padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
            children: [
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
              _MarkCompleteButton(exercise: item),
              const SizedBox(height: 12),
              _ScheduleButton(exercise: item),
            ],
          );
        },
      ),
    );
  }
}

class _MarkCompleteButton extends ConsumerWidget {
  const _MarkCompleteButton({required this.exercise});
  final ExerciseItem exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(logSessionActionProvider);
    final theme = Theme.of(context);
    final loading = action.isLoading;

    Future<void> onTap() async {
      final already = ref.read(_loggedEntryProvider(exercise.id));
      final alreadySet =
          already != null && already.exercises.first.sets.isNotEmpty
              ? already.exercises.first.sets.last
              : null;

      // Asked BEFORE the write, so the first row that reaches Firestore
      // already carries the numbers. Writing an empty row and filling it in
      // afterwards would leave the progression engine reading a set with no
      // load for as long as the sheet is open, and a dismissed sheet would
      // leave it that way for good.
      final captured = await SetCaptureSheet.show(
        context,
        exerciseTitle: exercise.title,
        initialWeightKg: alreadySet?.weightKg,
        initialReps: alreadySet?.reps,
      );
      if (!context.mounted) return;

      // F3.4: one exercise, at most one set per session -- same shape the
      // F3.3 backfill produces (see backfill_workout_sessions.mjs's own
      // toSession()) and the one asLogEntryView() assumes throughout. A
      // repeat tap overwrites this one set rather than appending a second,
      // same behavior as the old WorkoutLogEntry.copyWith did.
      //
      // `captured == null` (Skip) keeps the stored values, per
      // SetCaptureSheet's own contract (set_capture_sheet.dart:171-174).
      // `captured != null` (Save) uses exactly what was submitted, INCLUDING
      // a null field the user cleared on purpose ("declined to say") -- a
      // `captured?.weightKg ?? alreadySet?.weightKg` here would silently
      // restore the old weight the moment the user tried to blank it out on
      // a re-edit, contradicting the sheet's own "leave blank if no load"
      // hint.
      final weightKg = captured == null ? alreadySet?.weightKg : captured.weightKg;
      final reps = captured == null ? alreadySet?.reps : captured.reps;
      final sets = (weightKg != null || reps != null)
          ? [(weightKg: weightKg, reps: reps)]
          : const <SetCapture>[];
      final exerciseEntry = (already?.exercises.first ??
              WorkoutSessionExercise(
                exerciseId: exercise.id,
                exerciseTitle: exercise.title,
              ))
          .copyWith(sets: sets);

      // Same id on a repeat tap, so `save()` -- `doc(id).set(...)` -- updates
      // the row instead of adding a second one for the same set.
      final entry = (already ??
              WorkoutSession(
                id: '${DateTime.now().microsecondsSinceEpoch}_${exercise.id}',
                title: exercise.title,
                exercises: const [],
                startedAt: DateTime.now(),
              ))
          .copyWith(
        exercises: [exerciseEntry],
        completedAt: DateTime.now(),
        status: WorkoutSessionStatus.completed,
        durationMinutes: exercise.durationMinutes,
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
      ref.read(_loggedEntryProvider(exercise.id).notifier).state = entry;

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
        final rated = entry.copyWith(
          exercises: [entry.exercises.first.copyWith(difficulty: rating)],
        );
        await ref.read(logSessionActionProvider.notifier).log(rated);
        ref.read(_loggedEntryProvider(exercise.id).notifier).state = rated;
      }
    }

    return GlassCard(
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
                  valueColor: AlwaysStoppedAnimation<Color>(AppSemanticColors.onGradientInk),
                ),
              ),
              const SizedBox(width: 10),
            ] else ...[
              const Icon(Icons.check_rounded, color: AppSemanticColors.onGradientInk),
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
              content: Text(AppLocalizations.of(context)
                  .equipmentScheduledFor(exercise.title,
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
