/// What the Form Coach shows when there is nobody to coach yet.
///
/// G17, amended 2026-09-09. Three sources, one host, one look:
///
/// - the **squat** has no demonstration at the moment ([CoachDemoUnavailable]).
///   It used to play the design reference's own clip, and G1.2 established that
///   the clip is a screen recording of an older prototype: its UI is burned into
///   the pixels, including an English "stand tall to start counting" that
///   duplicates this app's own localized string, a rep counter frozen at 0 for
///   all 240 frames, and a toast reading "Too dark or too blurry to read your
///   position". None of it is removable — the line crosses the figure's head, so
///   no crop reaches it; inpainting smeared the face; no background plate exists;
///   and the reference's own compositing amplifies the chrome rather than hiding
///   it, because its `contrast(7)` glow layer keeps the white UI text exactly as
///   it keeps the skeleton. GPT-PM's ruling (2026-09-09, recorded in
///   `core/DECISION_LOG.md`) is that an honest empty state ships until real
///   chrome-free footage exists, and specifically NOT the drawn figure below:
///   substituting it here would silently reverse the operator's 2026-09-04
///   decision, which had already rejected three drawn stand-ins on a real phone;
/// - every other movement that has authored targets is demonstrated by
///   [DemoFigurePainter]: the same body the avatar draws for the user (dark
///   fill, faint rim, white glowing bones, joint dots), animated between the
///   two ends of the movement. It is the avatar's drawing, through the same
///   helpers, so the demonstration and the figure the user then sees of
///   themselves are one visual language rather than two.
///
/// The white filled target outline this replaces is gone from every screen.
/// It was authored for scoring and drawn for aiming, and on a phone it read as
/// an abstract shape — the operator's word was «квадраты» — not as a person.
/// Scoring still uses the same targets; only the drawing changed.
library;

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/pose_silhouette.dart';
import '../data/pose_target.dart';
import '../state/form_check_providers.dart';
import 'coach_demo_clip.dart';
import 'coach_figure_paint.dart';

/// Where a movement's demonstration comes from.
sealed class CoachDemoSource {
  const CoachDemoSource();
}

/// A bundled clip and its poster.
class CoachDemoClipSource extends CoachDemoSource {
  const CoachDemoClipSource({required this.asset, required this.poster});
  final String asset;
  final String poster;
}

/// The two ends of the movement, drawn and interpolated.
class CoachDemoFigureSource extends CoachDemoSource {
  const CoachDemoFigureSource(this.from, this.to);
  final PoseTarget from;
  final PoseTarget to;
}

/// A movement whose demonstration is knowingly missing, said out loud.
///
/// Distinct from `null`, and the distinction is the whole point. `null` means
/// "nothing is authored for this movement", which renders nothing and is
/// correct for a movement the coach does not teach. This means "this movement
/// IS taught and its demonstration is deliberately absent", which has to be
/// visible on the panel and audible to a screen reader instead of leaving a
/// silent hole where a demonstration used to be.
class CoachDemoUnavailableSource extends CoachDemoSource {
  const CoachDemoUnavailableSource();
}

/// An explicit absence for the squat; the authored figure for everything else
/// that has one; null when nothing is authored at all.
///
/// A plain function rather than only a provider, so the mapping is tested
/// without a container and the page can ask it while deciding whether the
/// demonstration's animation clock needs to run.
CoachDemoSource? coachDemoFor(FormExercise e) {
  // Explicit, and it has to be. `poseTargetsByTag` holds a squat pair
  // (`pose_target.dart`), so simply deleting this branch would fall through to
  // `CoachDemoFigureSource` and quietly produce the drawn stand-in the
  // 2026-09-09 ruling rejects. The absence is stated, not arrived at.
  if (e == FormExercise.squat) return const CoachDemoUnavailableSource();
  final pair = poseTargetsFor(e);
  if (pair == null) return null;
  return CoachDemoFigureSource(pair.$1, pair.$2);
}

/// Hosts whichever demonstration the selected movement has.
///
/// Keyed `form_check.demo` as the one structural answer to "is a
/// demonstration on screen"; the clip, the figure and the stated absence carry
/// their own keys underneath (`form_check.demo_clip`, `form_check.demo_figure`,
/// `form_check.demo_unavailable`) for tests that need to know which.
class CoachDemo extends ConsumerWidget {
  const CoachDemo({super.key, required this.animation, required this.active});

  /// The page's demonstration clock, 0..1 and back, for the figure source.
  final Animation<double> animation;

  /// Whether the demonstration is what the user is looking at. Passed through
  /// to the clip's lifecycle contract; the figure is driven by [animation],
  /// whose owner stops it on the same condition.
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = coachDemoFor(ref.watch(selectedExerciseProvider));
    // Nothing authored, nothing on screen — and no `form_check.demo` key
    // either, so "is a demonstration on screen" stays a true/false question.
    if (source == null) return const SizedBox.shrink();
    final child = switch (source) {
      CoachDemoClipSource(:final asset, :final poster) => CoachDemoClip(
          key: const Key('form_check.demo_clip'),
          asset: asset,
          poster: poster,
          active: active,
        ),
      CoachDemoFigureSource(:final from, :final to) => _DemoFigure(
          from: from,
          to: to,
          animation: animation,
          bodyBuild: ref.watch(silhouetteBuildProvider),
        ),
      CoachDemoUnavailableSource() => const _DemoUnavailable(),
    };
    return KeyedSubtree(key: const Key('form_check.demo'), child: child);
  }
}

/// The stated absence: a movement the coach teaches, whose demonstration is
/// knowingly missing.
///
/// A sentence rather than an empty box, because an empty box is indistinguish-
/// able from a panel that failed to load — and this panel is the main content
/// of the screen it sits on. It says nothing about WHY: the reason is a
/// repository decision, not something a user in a gym needs read to them.
///
/// It carries no semantics suppression of its own. On the selection screen the
/// wrapper excludes descendant semantics and announces the absence once itself;
/// on the live screen there is no wrapper and no label, so this text is the
/// only thing a screen reader has, which is the correct outcome there.
class _DemoUnavailable extends StatelessWidget {
  const _DemoUnavailable();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('form_check.demo_unavailable'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          AppLocalizations.of(context).formcheckDemoUnavailable,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.62),
              ),
        ),
      ),
    );
  }
}

class _DemoFigure extends StatelessWidget {
  const _DemoFigure({
    required this.from,
    required this.to,
    required this.animation,
    required this.bodyBuild,
  });

  final PoseTarget from;
  final PoseTarget to;
  final Animation<double> animation;
  final BodyBuild bodyBuild;

  @override
  Widget build(BuildContext context) {
    // Fixed for the whole loop, from both endpoints together — not recomputed
    // per frame from whatever the interpolated figure currently spans, or the
    // fit would visibly grow and shrink as the pose morphs between the ends.
    final fitBounds = buildSilhouette(from, build: bodyBuild)
        .bounds
        .expandToInclude(buildSilhouette(to, build: bodyBuild).bounds);
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) => CustomPaint(
        key: const Key('form_check.demo_figure'),
        painter: DemoFigurePainter(
          // Eased rather than linear: a real repetition does not travel at a
          // constant speed, and a constant-speed figure reads as a machine
          // rather than as a movement to copy.
          target: lerpPoseTarget(
              from, to, Curves.easeInOutCubic.transform(animation.value)),
          build: bodyBuild,
          fitBounds: fitBounds,
        ),
      ),
    );
  }
}

/// The avatar's look, fitted to the panel instead of projected onto a body.
///
/// Public because `coach_selection_screen_test.dart` compares painters across
/// frames to prove the demonstration moves.
class DemoFigurePainter extends CustomPainter {
  const DemoFigurePainter({
    required this.target,
    required this.build,
    required this.fitBounds,
  });

  final PoseTarget target;
  final BodyBuild build;

  /// Where to fit the figure, in figure space — the union of both ends of the
  /// movement, so the scale holds still while the pose changes.
  final Rect fitBounds;

  @override
  void paint(Canvas canvas, Size size) {
    final figure = buildSilhouette(target, build: build);
    if (figure.segments.isEmpty) return;
    // One scale for both axes, centred, with a margin — `fitSilhouette`. A
    // per-axis scale squeezes a person 1.78x on a 9:16 panel, and projecting
    // an authored pose through the camera transform crops it into a corner;
    // both were shipped and both were rejected on device.
    final (scale, offset) = fitSilhouette(fitBounds, size);
    Offset place(Offset p) => p * scale + offset;
    final limbWidth = (figure.limbThickness * scale).clamp(4.0, 40.0);

    paintFigureBody(
      canvas,
      buildFigureBody(figure, place, scale),
      limbWidth: limbWidth,
    );
    final boneWidth = (limbWidth * 0.20).clamp(2.0, 6.0);
    // No verdict glow: a demonstration has nothing to judge.
    paintSkeleton(canvas, buildBonePaths(figure, place), boneWidth: boneWidth);
    paintJointDots(canvas, figure.joints.map(place), radius: boneWidth * 0.62);
  }

  @override
  bool shouldRepaint(DemoFigurePainter oldDelegate) =>
      oldDelegate.build != build ||
      oldDelegate.fitBounds != fitBounds ||
      // A demonstration is a new pose every frame and its id never changes,
      // so it has to be compared by content or the animation would render as
      // a single frozen frame.
      oldDelegate.target.id != target.id ||
      !mapEquals(oldDelegate.target.joints, target.joints);
}
