/// What the Form Coach shows when there is nobody to coach yet.
///
/// G17. Two sources, one host, one look:
///
/// - the **squat** plays the design reference's own clip ([CoachDemoClip]) —
///   a real person, dark against a dusk lake, lit skeleton on the body;
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

/// The reference clip for the squat; the authored figure for everything else
/// that has one; null when nothing is authored at all.
///
/// A plain function rather than only a provider, so the mapping is tested
/// without a container and the page can ask it while deciding whether the
/// demonstration's animation clock needs to run.
CoachDemoSource? coachDemoFor(FormExercise e) {
  if (e == FormExercise.squat) {
    return const CoachDemoClipSource(
      asset: 'assets/coach_demo/squat_side.mp4',
      poster: 'assets/coach_demo/squat_side_poster.jpg',
    );
  }
  final pair = poseTargetsFor(e);
  if (pair == null) return null;
  return CoachDemoFigureSource(pair.$1, pair.$2);
}

/// Hosts whichever demonstration the selected movement has.
///
/// Keyed `form_check.demo` as the one structural answer to "is a
/// demonstration on screen"; the clip and the figure carry their own keys
/// underneath (`form_check.demo_clip`, `form_check.demo_figure`) for tests
/// that need to know which.
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
    };
    return KeyedSubtree(key: const Key('form_check.demo'), child: child);
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
