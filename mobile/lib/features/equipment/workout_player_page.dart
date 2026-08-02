import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/settings/state/settings_providers.dart';
import '../../core/theme/app_palette.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/smooth_scroll_list.dart';
import '../workouts/data/progression.dart';
import '../workouts/data/scheduled_session.dart';
import '../workouts/data/workout_log.dart';
import '../profile/state/profile_providers.dart';
import '../workouts/state/offline_video_providers.dart';
import '../workouts/state/scheduled_session_providers.dart';
import '../workouts/state/workout_log_providers.dart';
import '../workouts/widgets/difficulty_rating_sheet.dart';
import '../workouts/widgets/plate_calculator.dart';
import '../workouts/widgets/rest_timer.dart';
import '../home/home_page.dart' show formatScheduleLabel;
import '../workouts/widgets/set_timer_card.dart';
import '../workouts/widgets/warmup_calculator.dart';
import 'data/catalog_labels.dart';
import 'data/equipment_models.dart';
import 'state/equipment_providers.dart';
import 'widgets/exercise_demo.dart';
import 'widgets/muscle_map.dart';
import 'widgets/exercise_thumb.dart';

/// Shows the rest timer after a successful "Mark complete". Local to this
/// page — clears on rebuild via a StateProvider.autoDispose so navigating
/// away resets it.
final _restTimerVisibleProvider = StateProvider.autoDispose<bool>((_) => false);

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

/// Looks up an exercise from the (preloaded) equipment catalog. Internal
/// helper so we don't need a separate FutureProvider just for this page.
final _exerciseByIdProvider =
    FutureProvider.family<ExerciseItem?, String>((ref, id) async {
  // AI-generated exercise ids are 'ai::<equipmentId>::<index>' — they live
  // only in the generated-exercise cache, never in the base repo, so they
  // need their own lookup path rather than the linear scan below.
  if (id.startsWith('ai::')) {
    final parts = id.split('::');
    if (parts.length != 3) return null;
    final equipmentId = parts[1];
    final lang = ref.watch(effectiveLanguageCodeProvider);
    final cached = await ref
        .watch(generatedExerciseRepositoryProvider)
        .get(equipmentId, lang);
    if (cached == null) return null;
    for (final e in cached) {
      if (e.id == id) return e;
    }
    return null;
  }

  final repo = ref.watch(equipmentRepositoryProvider);
  // Iterate every equipment + bodyweight pool — we only have a few hundred.
  final all = <ExerciseItem>[
    ...await repo.bodyweightExercises(),
    for (final eq in await repo.listEquipment())
      ...await repo.exercisesFor(eq.id),
  ];
  for (final e in all) {
    if (e.id == id) return e;
  }
  return null;
});

class WorkoutPlayerPage extends ConsumerWidget {
  const WorkoutPlayerPage({super.key, required this.exerciseId});

  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final exercise = ref.watch(_exerciseByIdProvider(exerciseId));

    return FrostedScaffold(
      appBar: GlassAppBar(title: AppLocalizations.of(context).equipmentWorkout),
      body: exercise.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
            child: Text(AppLocalizations.of(context).equipmentCouldNotLoad(e))),
        data: (item) {
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
              _Hero(exercise: item),
              const SizedBox(height: 16),
              // A real clip wins when the catalog has one; otherwise the
              // start/end frames loop as the demo -- bundled assets for the
              // original 66, network stills (same public-domain source) for
              // everything added in the round-4 catalog expansion. Only when
              // there is neither do we show the "no demo" card.
              //
              // `playableVideoFor` returns null while the library's host is
              // unchosen, so the 343 exercises that carry a clip keep showing
              // whatever they showed before rather than a player that spins
              // and then fails. The day the host is set, they switch over with
              // no further change here.
              if (demoVideo != null)
                _VideoBlock(url: demoVideo, poster: item.posterFor(body))
              else if (item.frames.isNotEmpty)
                ExerciseDemo(frames: item.frames)
              else if (item.imageUrls.isNotEmpty)
                ExerciseDemo(frames: item.imageUrls)
              else
                _NoVideoFallback(),
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
              _StepsCard(exercise: item),
              if (item.contraindications.isNotEmpty) ...[
                const SizedBox(height: 16),
                _CautionCard(item: item),
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
              if (ref.watch(_restTimerVisibleProvider)) ...[
                const SizedBox(height: 12),
                RestTimer(
                  seconds: _restSecondsFor(item),
                  onComplete: () {},
                ),
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

class _Hero extends StatelessWidget {
  const _Hero({required this.exercise});
  final ExerciseItem exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      child: Row(
        children: [
          ExerciseThumb(exercise: exercise, size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exercise.title,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Pill(
                        text: AppLocalizations.of(context)
                            .exerciseMinutes(exercise.durationMinutes)),
                    _Pill(
                        text: CatalogLabels.difficulty(
                            AppLocalizations.of(context), exercise.difficulty)),
                    for (final m in exercise.muscles.take(3))
                      _Pill(
                          text: CatalogLabels.muscle(
                              AppLocalizations.of(context), m)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The clip, with its own first frame underneath it.
///
/// Two operator reports, one block. *"видео загружается за секунды, но мы
/// договаривались что превью картинка будет сразу а видео подтягивать потом,
/// но этого нет"* — there was nothing to show first, so it showed a spinner.
/// And *"если нет интернета то даже изначальной картинки не будет"* — with no
/// connection the block resolved to an error card and the exercise had no
/// picture at all.
///
/// The poster is a bundled asset cut from the clip itself, so it paints on the
/// first frame, costs no request, and survives aeroplane mode. The video fades
/// in over it when it is ready; if it never becomes ready, the poster simply
/// stays, with a quiet line saying the clip could not be fetched. A still
/// picture of the exercise plus an explanation is a far better failure than a
/// grey card containing an exception.
class _VideoBlock extends ConsumerStatefulWidget {
  const _VideoBlock({required this.url, required this.poster});
  final String url;

  /// Bundled asset path, or null for the handful of clips cut before posters
  /// existed.
  final String? poster;

  @override
  ConsumerState<_VideoBlock> createState() => _VideoBlockState();
}

class _VideoBlockState extends ConsumerState<_VideoBlock> {
  /// Playback rates. Operator asked for x1/x2/x3; 0.5 is kept because slowing
  /// a movement down is the thing people actually do when learning one.
  static const _speeds = <String, double>{
    '0.5x': 0.5,
    '1x': 1.0,
    '2x': 2.0,
    '3x': 3.0,
  };

  VideoPlayerController? _ctrl;
  bool _ready = false;
  Object? _error;
  bool _fromCache = false;
  String _speed = '1x';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// Cache-first init. Checks the offline video cache for a local copy
  /// of [widget.url]; falls back to network streaming if the cache
  /// misses. Premium-tier users prefetch via the Schedule page so this
  /// path almost always hits during a planned session.
  Future<void> _bootstrap() async {
    try {
      // Cache lookup uses the catalog REFERENCE, not the resolved URL. A
      // signed URL carries an expiry and a signature, so it is different on
      // every request — keying the cache on it would mean nothing was ever
      // found and the same clip downloaded forever.
      final cache = ref.read(offlineVideoCacheProvider);
      final cached = await cache.localFile(widget.url);
      VideoPlayerController controller;
      if (cached != null) {
        controller = VideoPlayerController.file(cached);
        _fromCache = true;
      } else {
        final playable =
            await ref.read(clipUrlResolverProvider).resolve(widget.url);
        if (playable == null) {
          // Signing failed or the object is gone. The poster is already on
          // screen; leave it there and say why rather than replacing a
          // picture of the exercise with an exception.
          if (mounted) setState(() => _error = 'unresolved');
          return;
        }
        if (!mounted) return;
        controller = VideoPlayerController.networkUrl(Uri.parse(playable));
      }
      controller.setLooping(true);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _ctrl = controller;
        _ready = true;
      });
      controller.play();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  void _setSpeed(String s) {
    setState(() => _speed = s);
    _ctrl?.setPlaybackSpeed(_speeds[s]!);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    final playing = _ready && ctrl != null;
    final poster = widget.poster;

    // The clip's own aspect once known; the library's own 400x230 poster ratio
    // until then. Guessing 16:9 made the block jump on the frame the video
    // arrived, which is exactly the flicker a poster exists to remove.
    final aspect = playing && ctrl.value.aspectRatio != 0
        ? ctrl.value.aspectRatio
        : 400 / 230;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: AspectRatio(
        aspectRatio: aspect,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black12),
            if (poster != null)
              Image.asset(poster,
                  key: const Key('workout.poster'),
                  fit: BoxFit.contain,
                  gaplessPlayback: true),
            if (playing)
              // Faded in rather than swapped: the poster is the clip's own
              // first frame, so a cut would be invisible except for the
              // single-frame flash of a decode.
              AnimatedOpacity(
                opacity: 1,
                duration: const Duration(milliseconds: 180),
                child: VideoPlayer(ctrl),
              ),
            if (playing)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(
                    () => ctrl.value.isPlaying ? ctrl.pause() : ctrl.play()),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: ctrl.value.isPlaying
                      ? const SizedBox.shrink()
                      : Container(
                          color: Colors.black.withValues(alpha: 0.30),
                          child: const Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 80),
                        ),
                ),
              ),
            if (playing)
              Positioned(
                right: 8,
                bottom: 8,
                child: Row(
                  key: const Key('workout.speeds'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final s in _speeds.keys)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: ChoiceChip(
                          label: Text(s),
                          selected: _speed == s,
                          onSelected: (_) => _setSpeed(s),
                        ),
                      ),
                  ],
                ),
              ),
            // Only while there is neither a picture nor a clip. With a poster
            // up there is nothing to wait for on screen, and a spinner over a
            // perfectly good still just says "broken".
            if (!playing && poster == null && _error == null)
              const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: _VideoFailedNote(hasPoster: poster != null),
              ),
            if (_fromCache && playing)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    AppLocalizations.of(context).equipmentOffline,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Says the clip did not arrive, without taking the picture away.
class _VideoFailedNote extends StatelessWidget {
  const _VideoFailedNote({required this.hasPoster});
  final bool hasPoster;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('workout.video_failed'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        hasPoster
            ? AppLocalizations.of(context).equipmentClipOfflineStillShown
            : AppLocalizations.of(context).equipmentClipCouldNotLoad,
        style: const TextStyle(color: Colors.white, fontSize: 11),
      ),
    );
  }
}

class _NoVideoFallback extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: const LinearGradient(colors: [
                    AppPalette.auroraTeal,
                    AppPalette.auroraLime,
                  ]),
                ),
                child: const Icon(Icons.menu_book_outlined,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)
                      .equipmentNoVideoYetFollowTheSteps,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          // `/contribute` was a finished, translated, routed page that nothing
          // in the app linked to — a submission form nobody could open. This
          // is where it belongs: the one moment a user is looking at a gap in
          // the catalog is the moment to ask them to fill it.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('workout.contribute_video'),
              onPressed: () => context.push('/contribute'),
              icon: const Icon(Icons.add_link, size: 18),
              label: Text(AppLocalizations.of(context).catalogContributeAVideo),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepsCard extends StatelessWidget {
  const _StepsCard({required this.exercise});
  final ExerciseItem exercise;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.of(context).equipmentHowToDoIt,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(exercise.summary,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              )),
          const SizedBox(height: 10),
          for (var i = 0; i < exercise.steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: const LinearGradient(colors: [
                        AppPalette.auroraViolet,
                        AppPalette.auroraBlue,
                      ]),
                    ),
                    child: Center(
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(exercise.steps[i],
                        style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MarkCompleteButton extends ConsumerWidget {
  const _MarkCompleteButton({required this.exercise});
  final ExerciseItem exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(logWorkoutActionProvider);
    final theme = Theme.of(context);
    final loading = action.isLoading;

    Future<void> onTap() async {
      final entry = WorkoutLogEntry(
        id: '${DateTime.now().microsecondsSinceEpoch}_${exercise.id}',
        exerciseId: exercise.id,
        exerciseTitle: exercise.title,
        completedAt: DateTime.now(),
        durationMinutes: exercise.durationMinutes,
      );
      await ref.read(logWorkoutActionProvider.notifier).log(entry);
      if (!context.mounted) return;
      final newState = ref.read(logWorkoutActionProvider);
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
      ref.read(_restTimerVisibleProvider.notifier).state = true;

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
        await ref
            .read(logWorkoutActionProvider.notifier)
            .log(entry.copyWith(difficulty: rating));
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
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(width: 10),
            ] else ...[
              const Icon(Icons.check_rounded, color: Colors.white),
              const SizedBox(width: 8),
            ],
            Text(
              loading
                  ? AppLocalizations.of(context).equipmentSaving
                  : AppLocalizations.of(context).equipmentMarkComplete,
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
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
    final logsAsync = ref.watch(workoutLogsProvider);
    final logs = logsAsync.valueOrNull ?? const <WorkoutLogEntry>[];
    final history = logs.where((l) => l.exerciseId == exerciseId).toList();
    final suggestion = suggestNextWeight(historyForExercise: history);
    if (suggestion == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
              color: Colors.white,
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
                        color: scheme.onSurface.withValues(alpha: 0.65),
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
                    color: scheme.onSurface.withValues(alpha: 0.60),
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

class _CautionCard extends StatelessWidget {
  const _CautionCard({required this.item});
  final ExerciseItem item;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(colors: [
                AppPalette.auroraPeach,
                AppPalette.auroraPink,
              ]),
            ),
            child: const Icon(Icons.warning_amber_rounded, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLocalizations.of(context).equipmentTakeCareIfYouHave,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  item.contraindications
                      .map((c) => c.replaceAll('_', ' '))
                      .join(', '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
