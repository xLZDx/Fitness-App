/// Everything that DESCRIBES an exercise, shared by the two screens that show
/// one.
///
/// ## Why this file exists
///
/// The audit's §7.3: "`/workout/:id` already renders the full Exercise Page
/// content: hero, video with poster, muscle map, technique steps,
/// contraindications, suggested weight. Creating `/exercise/:id` as a *new*
/// page while the player keeps that content would fork 'how to show an
/// exercise' into two sources of truth. The correct work is a **split**, not
/// an addition."
///
/// So this is a move, not a rewrite. Every widget below was lifted verbatim
/// out of `workout_player_page.dart` — which was 1,192 lines against a
/// convention of about 300 — and made public so a second screen can render the
/// same thing rather than a lookalike that drifts.
///
/// What stayed behind is the DOING: marking a set complete, the tools row, the
/// schedule button, the suggested weight. Those belong to a workout in
/// progress, not to the description of a movement.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../../shared/widgets/app_buttons.dart';
import '../../../shared/widgets/glass.dart';
import '../data/video_failure.dart';
import '../../workouts/state/offline_video_providers.dart';
import '../data/catalog_labels.dart';
import '../../form_check/state/form_check_providers.dart';
import '../../profile/state/profile_providers.dart';
import '../../safety/widgets/eligibility_notice.dart';
import '../data/equipment_models.dart';
import '../state/equipment_providers.dart';
import 'exercise_thumb.dart';
import 'muscle_map.dart';

class ExerciseHero extends StatelessWidget {
  const ExerciseHero({super.key, required this.exercise});
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
                    ExercisePill(
                        text: AppLocalizations.of(context)
                            .exerciseMinutes(exercise.durationMinutes)),
                    ExercisePill(
                        text: CatalogLabels.difficulty(
                            AppLocalizations.of(context), exercise.difficulty)),
                    for (final m in exercise.muscles.take(3))
                      ExercisePill(
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

/// The design's 260px immersive header: the movement's own still, a scrim, and
/// the name in display type over it.
///
/// R11d. `ExerciseHero` above is a 56px thumbnail in a card — a list row, not a
/// header — and the prototype (`App.tsx:2818-2856`) opens the screen with the
/// picture at full bleed. Kept as a separate widget rather than a mode on
/// `ExerciseHero` because the player still wants the compact row: a screen you
/// are DOING an exercise on should not spend 260px re-introducing it.
class ExerciseImmersiveHero extends StatelessWidget {
  const ExerciseImmersiveHero({
    super.key,
    required this.exercise,
    this.body,
    this.onBack,
  });

  final ExerciseItem exercise;

  /// Which filmed body to take the still from — same values as
  /// [ExerciseItem.video].
  final String? body;

  /// Null uses the router's own pop. Injectable so a test can drive it
  /// without a GoRouter in the tree.
  final VoidCallback? onBack;

  static const double height = 260;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colors;
    final poster = exercise.posterFor(body);
    final top = MediaQuery.paddingOf(context).top;

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (poster != null)
            // White bed for the same reason `ExerciseThumb` uses one: the clips
            // are rendered on flat white, so anything else frames the figure in
            // a grey letterbox.
            ColoredBox(
              color: Colors.white,
              child: Image.asset(poster, fit: BoxFit.cover),
            )
          else
            // The design calls this state "Анимация недоступна". 168 of the
            // catalogue's exercises have no clip and so no still; a gradient
            // with an explanation beats a blank rectangle.
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colors.backgroundSecondary,
                    colors.accentPrimary.withValues(alpha: 0.10),
                  ],
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.movie_outlined,
                        size: 30, color: colors.textDisabled),
                    const SizedBox(height: 8),
                    Text(
                      l10n.exerciseNoAnimation,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          // Bottom scrim, so the title reads over any still.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    colors.backgroundPrimary,
                    colors.backgroundPrimary.withValues(alpha: 0),
                  ],
                ),
              ),
              child: Text(
                exercise.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ),
          Positioned(
            top: top + 8,
            left: 12,
            child: _ScrimCircleButton(
              icon: Icons.arrow_back_ios_new_rounded,
              semanticLabel: l10n.commonBack,
              onTap: onBack ?? () => GoRouter.of(context).pop(),
            ),
          ),
          if (exercise.muscles.isNotEmpty)
            Positioned(
              top: top + 12,
              left: 64,
              right: 20,
              child: Align(
                alignment: Alignment.topCenter,
                child: _ScrimChip(
                  label: exercise.muscles
                      .take(2)
                      .map((m) => CatalogLabels.muscle(l10n, m))
                      .join(' · '),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A control drawn over artwork this app does not control.
///
/// `Colors.white` here is the sanctioned scrim-foreground case, the same one
/// `form_check_page.dart` uses over a camera frame: the fill is
/// [AppSemanticColors.cameraOverlay] (black at 0.55) in both themes, so a
/// theme-reactive foreground would be wrong half the time.
class _ScrimCircleButton extends StatelessWidget {
  const _ScrimCircleButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colors.cameraOverlay,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon,
              size: 16, color: Colors.white, semanticLabel: semanticLabel),
        ),
      ),
    );
  }
}

class _ScrimChip extends StatelessWidget {
  const _ScrimChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colors.cameraOverlay,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Level / equipment / type, as the design's three-up row
/// (`App.tsx:2874-2885`).
///
/// Every value is already on [ExerciseItem]; nothing here is derived or
/// guessed. `equipmentLabel` is the vendor's own free text — shown verbatim
/// rather than mapped, because the mapping onto this app's 52 machine ids does
/// not exist yet and inventing one per label would be worse than quoting.
class ExerciseQuickStats extends ConsumerWidget {
  const ExerciseQuickStats({super.key, required this.exercise});
  final ExerciseItem exercise;

  /// The equipment name, in the language the rest of the card is written in.
  ///
  /// `equipmentLabel` is the vendor's own English free text, and rendering it
  /// verbatim left this tile as the one untranslated string on a Russian card —
  /// "Cable Pulley Machine" under "ОБОРУДОВАНИЕ". Found while repairing the 78
  /// rows that labelled a machine "None" (C3), which is when it became the only
  /// wrong thing left in this tile rather than the second-worst.
  ///
  /// The registry already carries the translation (`equipment.ru.json`); this
  /// surface simply never asked it. Resolved by `equipmentId`, so it is the
  /// same lookup the machine pages do rather than a second mapping to keep in
  /// step.
  ///
  /// Three fallbacks, in order, and each is a different fact:
  ///   * no `equipmentId` — the row needs no machine, and the vendor's own
  ///     words ("Yoga Mat", "Wall") are the best thing to show;
  ///   * the id does not resolve, or the registry is still loading — the label
  ///     is stale English rather than nothing, which beats an empty tile;
  ///   * no label either — the exercise is bodyweight, and says so.
  String _equipment(WidgetRef ref, AppLocalizations l10n) {
    final id = exercise.equipmentId;
    if (id != null) {
      final name = ref.watch(equipmentByIdProvider(id)).valueOrNull?.name;
      if (name != null && name.trim().isNotEmpty) return name;
    }
    return exercise.equipmentLabel ?? l10n.exerciseBodyweight;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: _QuickStat(
            label: l10n.exerciseStatLevel,
            value: CatalogLabels.difficulty(l10n, exercise.difficulty),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickStat(
            label: l10n.exerciseStatEquipment,
            value: _equipment(ref, l10n),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickStat(
            label: l10n.exerciseStatType,
            value: exercise.isStretch
                ? l10n.exerciseTypeMobility
                : l10n.exerciseTypeStrength,
          ),
        ),
      ],
    );
  }
}

class _QuickStat extends StatelessWidget {
  const _QuickStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      borderRadius: 12,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colors.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class ExercisePill extends StatelessWidget {
  const ExercisePill({super.key, required this.text});
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
class ExerciseVideoBlock extends ConsumerStatefulWidget {
  const ExerciseVideoBlock(
      {super.key, required this.url, required this.poster});
  final String url;

  /// Bundled asset path, or null for the handful of clips cut before posters
  /// existed.
  final String? poster;

  @override
  ConsumerState<ExerciseVideoBlock> createState() => ExerciseVideoBlockState();
}

class ExerciseVideoBlockState extends ConsumerState<ExerciseVideoBlock> {
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
          if (mounted) setState(() => _error = kUnresolvedClip);
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
              // Оверлей play/pause — иконка поверх видео и ничего больше.
              // Метки у него не было вообще: пока клип играет, потомок —
              // `SizedBox.shrink()`, то есть скринридер не находил здесь
              // ни кнопки, ни текста, и остановить воспроизведение было
              // нечем. `excludeSemantics` глушит саму иконку, чтобы метка
              // осталась одна и менялась вместе с состоянием.
              Semantics(
                button: true,
                excludeSemantics: true,
                label: ctrl.value.isPlaying
                    ? AppLocalizations.of(context).videoPause
                    : AppLocalizations.of(context).videoPlay,
                child: GestureDetector(
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
              ),
            if (playing)
              // Left edge, vertical, and small (operator, 2026-08-13). The
              // chips used to be a horizontal `ChoiceChip` row along the
              // bottom, which is where the demonstrated movement actually
              // happens — feet, the bottom of a squat, the floor in a plank —
              // so the control covered the thing it exists to help you watch.
              // A column down one side crosses only the background.
              Positioned(
                left: 6,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Column(
                    key: const Key('workout.speeds'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final s in _speeds.keys)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: _SpeedPip(
                            label: s,
                            selected: _speed == s,
                            onTap: () => _setSpeed(s),
                          ),
                        ),
                    ],
                  ),
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
                child: ExerciseVideoFailedNote(
                    hasPoster: poster != null, error: _error!),
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

/// One playback-rate button, sized to sit over a video without owning it.
///
/// Not a `ChoiceChip`: Material sizes that one for a form row — it carries the
/// list tile's touch padding and a full-height label, and four of them stacked
/// were taller than the clip. This is 30x26, which is small enough to stay out
/// of the picture and still inside the 48dp column the `Semantics` below
/// reports, so a switch or screen-reader user is not asked to hit 30 pixels.
class _SpeedPip extends StatelessWidget {
  const _SpeedPip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 30,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // `cameraOverlay`, not a hand-rolled black: this file already
            // solves "a control floating over media" twice (`_ScrimCircleButton`,
            // `_ScrimChip`) and both use that token. A second literal here
            // would be the same decision made twice, free to drift.
            color: selected
                ? AppPalette.auroraLime.withValues(alpha: 0.92)
                : theme.colors.cameraOverlay,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              // Plain white on the scrim, exactly as `_ScrimChip` does it —
              // category 1 of the hardcoded-white ratchet, and the one the
              // ratchet's own doc calls correct.
              color: selected ? AppSemanticColors.onGradientInk : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// Says the clip did not arrive, without taking the picture away.
///
/// Names the reason it actually has. Until 2026-08-08 this picked its text
/// from `hasPoster` alone and announced "Нет сети — показан кадр" for every
/// failure, network or not -- which is what a 1 Gb connection was told.
class ExerciseVideoFailedNote extends StatelessWidget {
  const ExerciseVideoFailedNote(
      {super.key, required this.hasPoster, required this.error});
  final bool hasPoster;
  final Object error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reason = classifyVideoFailure(error);
    final headline = switch (reason) {
      VideoFailureReason.linkUnavailable => l10n.equipmentClipLinkUnavailable,
      VideoFailureReason.offline => hasPoster
          ? l10n.equipmentClipOfflineStillShown
          : l10n.equipmentClipOfflineNoStill,
      VideoFailureReason.playbackFailed => l10n.equipmentClipCouldNotLoad,
    };
    // Only for the case we could not name. Under a headline that already
    // says what happened it is noise; under "did not load" it is the whole
    // difference between a bug report and a shrug.
    final detail = reason == VideoFailureReason.playbackFailed
        ? videoFailureDetail(error)
        : null;

    return Container(
      key: const Key('workout.video_failed'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(headline,
              style: const TextStyle(color: Colors.white, fontSize: 11)),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                detail,
                key: const Key('workout.video_failed.detail'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                // Full white, not white70. This sits on a 0.62 black scrim
                // over arbitrary video content, where a dimmed white at this
                // size stops being readable on a light frame -- and an error
                // detail nobody can read is the same as not printing it.
                // Secondary by size and position instead.
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ExerciseNoVideoFallback extends StatelessWidget {
  const ExerciseNoVideoFallback({super.key});

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
                    color: AppSemanticColors.onGradientInk, size: 24),
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
            child: AppTertiaryButton(
              key: const Key('workout.contribute_video'),
              onPressed: () => context.push('/contribute'),
              icon: Icons.add_link,
              label: AppLocalizations.of(context).catalogContributeAVideo,
            ),
          ),
        ],
      ),
    );
  }
}

/// Entry into the Form Coach from an exercise the coach understands.
class ExerciseFormCoachCard extends StatelessWidget {
  const ExerciseFormCoachCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return GlassCard(
      key: const Key('exercise-form-coach'),
      onTap: () => GoRouter.of(context).push('/form-check'),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(colors: [
                AppPalette.auroraPeach,
                AppPalette.auroraPink,
              ]),
            ),
            child: const Icon(Icons.center_focus_strong_outlined,
                color: AppSemanticColors.onGradientInk),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.formcheckFormCoach,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(l10n.formcheckLiveCameraAnalysis,
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

class ExerciseStepsCard extends StatelessWidget {
  const ExerciseStepsCard({super.key, required this.exercise});
  final ExerciseItem exercise;

  /// True when this card has nothing to show.
  ///
  /// `summary` is derived as `steps[0]` by every catalog builder
  /// (`build_vendor_catalog.py:291`, `build_catalog.py:109`,
  /// `build_library.py:136`), so the two are empty on exactly the same rows —
  /// measured, not assumed: 403 of the 1,887 vendor exercises lack both, and
  /// the two sets are identical.
  bool get _isBlank => exercise.summary.trim().isEmpty && exercise.steps.isEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // What the exercise is FOR, when someone has written it.
          //
          // Above the technique, not below it, because it answers the question
          // a user asks first — "why would I do this one" — and because the
          // catalogue had no field for it at all until B3: `summary` is a
          // byte-identical copy of `steps.first` by construction, so every
          // screen that wanted to say what an exercise trains could only repeat
          // an instruction. Absent for the 1,484 rows nobody has written it for
          // yet, and absent means absent: no heading over blank space, same
          // rule as the missing-steps case below.
          if (exercise.purpose case final purpose?) ...[
            Text(l10n.equipmentWhyThisMatters,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(purpose,
                key: const Key('exercise-purpose'),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colors.textSecondary)),
            const SizedBox(height: 14),
          ],
          Text(l10n.equipmentHowToDoIt,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          // Says so, rather than rendering a heading over blank space.
          //
          // 21% of the vendor catalogue ships without a technique description
          // — their metadata sheet is ~79% filled, which the builder's own
          // header states — so this is not an edge case, it is one exercise in
          // five. The card used to draw `Text('')` and zero steps, which reads
          // as the app having lost the text rather than never having had it.
          //
          // Not hidden entirely: a section that silently disappears on some
          // exercises and not others looks like a rendering bug, and it also
          // hides the gap from whoever could fill it. Nothing here invents
          // technique — a fabricated instruction on a fitness app is an injury
          // risk, not a nicer empty state.
          if (_isBlank)
            Text(
              l10n.equipmentNoStepsYet,
              key: const Key('exercise-steps-missing'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            Text(exercise.summary,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colors.textSecondary,
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
                          color: AppSemanticColors.onGradientInk,
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

class ExerciseCautionCard extends StatelessWidget {
  const ExerciseCautionCard({super.key, required this.item});
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
            child: const Icon(Icons.warning_amber_rounded,
                color: AppSemanticColors.onGradientInk),
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
                      .map((c) => CatalogLabels.contraindication(
                          AppLocalizations.of(context), c))
                      .join(', '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colors.textSecondary,
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

/// The description of an exercise, as a list of sections both screens splat
/// into their own scroll view.
///
/// A list rather than a widget so the spacing between sections stays the
/// property of this file. Returning a Column would have let each caller wrap
/// it differently, and "the exercise page has slightly different padding" is
/// precisely the drift a shared source of truth is meant to prevent.
List<Widget> exerciseReferenceSections(
  BuildContext context,
  ExerciseItem item,
  String? body,
) {
  final theme = Theme.of(context);
  final demoVideo = item.playableVideoFor(body) ?? item.videoUrl;
  return [
    // R11d: the name and the picture moved OUT of this list and into
    // `ExerciseImmersiveHero`, which the page renders edge-to-edge above the
    // padding. What is left here is the design's three-up stats row
    // (`App.tsx:2874`), which the old 56px card hero folded into pills.
    ExerciseQuickStats(exercise: item),
    const SizedBox(height: 16),
    // A clip or nothing. The two photograph fallbacks that used to sit here
    // are gone: `frames` and `imageUrls` are both stills of a man in a gym,
    // and putting either in front of an exercise made the catalog look like
    // two different apps stitched together.
    if (demoVideo != null)
      ExerciseVideoBlock(url: demoVideo, poster: item.posterFor(body))
    else
      const ExerciseNoVideoFallback(),
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
    // Right under the technique steps, which is where the design puts it and
    // where it belongs: you have just read how the movement should look, and
    // this offers to watch you do it.
    //
    // Shown ONLY where the coach can actually judge the movement --
    // `formCoachSupports`, not merely `poseTargetId != null`.
    if (formCoachSupports(item.poseTargetId)) ...[
      const SizedBox(height: 16),
      const ExerciseFormCoachCard(),
    ],
    if (item.contraindications.isNotEmpty) ...[
      const SizedBox(height: 16),
      ExerciseCautionCard(item: item),
    ],
  ];
}

/// Resolves an exercise id and renders the three states that are not the
/// exercise: still loading, failed to load, and withheld by the user's own
/// injury list.
///
/// Shared because those states carry wording that must not diverge. The
/// injury one especially: telling someone "we couldn't find that exercise"
/// when their own settings are hiding it is false, and it conceals the single
/// fact they can act on.
class ExerciseResolutionView extends ConsumerWidget {
  const ExerciseResolutionView({
    super.key,
    required this.exerciseId,
    required this.builder,
  });

  final String exerciseId;
  final Widget Function(BuildContext, ExerciseItem, String? body) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return ref.watch(exerciseResolutionProvider(exerciseId)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(l10n.equipmentCouldNotLoad(e))),
          data: (resolution) {
            if (resolution.hiddenForInjury) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 92, 20, 24),
                child: GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.equipmentHiddenForInjury(
                            resolution.exercise!.title),
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(l10n.equipmentHiddenForInjuryHint,
                          style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              );
            }
            // Withheld for something other than an injury — a screening
            // answer, a movement restriction, a clinician's instruction. This
            // used to fall through to the branch below and tell the user the
            // exercise did not exist, which is both false and unactionable:
            // the one thing they could do about it is the one thing the
            // message hid from them.
            if (resolution.withheldFor.isNotEmpty) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 92, 20, 24),
                child: EligibilityNotice(
                  key: const Key('exercise.withheld'),
                  reasons: resolution.withheldFor,
                  onReviewProfile: () =>
                      GoRouter.of(context).push('/onboarding'),
                ),
              );
            }
            final item = resolution.visible;
            if (item == null) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 92, 20, 24),
                child: GlassCard(
                  child: Text(l10n.equipmentWeCouldnTFindThatExercise,
                      style: theme.textTheme.titleMedium),
                ),
              );
            }
            // Which body to demonstrate on. Null when the user has not said,
            // or said they would rather not — there is nothing to infer from,
            // and the model falls back to whichever clip exists.
            final body = ExerciseItem.bodyForGender(
                ref.watch(currentProfileProvider).valueOrNull?.personal.gender);
            return builder(context, item, body);
          },
        );
  }
}
