import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../data/equipment_models.dart';

/// An exercise, as a square you can recognise.
///
/// Every list in the app used to show the same thing: a gradient tile with a
/// white play triangle, coloured by `id.hashCode % 5`. Five colours across a
/// 511-row catalog means five exercises in a row look interchangeable, and the
/// picture told you nothing about the movement. Operator, on the interface in
/// general: *"у нас очень топорный интерфэйс"*.
///
/// The fix cost nothing to source. 653 posters were already bundled for the
/// video player, cut from the clips themselves — so 343 exercises can show
/// what they actually look like, on the first frame, with no network. The
/// gradient survives as the fallback for the 168 that have no clip, which is
/// also a quiet honest signal: a coloured tile means "no demonstration yet".
///
/// One widget rather than the same edit in five files. The five call sites had
/// already drifted — 44, 48 and 56 pixels, radius 14, 15 and 18, two of them
/// computing the gradient inline and two taking it as a parameter — which is
/// how a "consistent" design ends up not being one.
class ExerciseThumb extends StatelessWidget {
  const ExerciseThumb({
    super.key,
    required this.exercise,
    this.size = 48,
    this.body,
  });

  /// Null renders the fallback tile, for call sites that only have an id.
  final ExerciseItem? exercise;

  final double size;

  /// Which body to show, when the exercise was filmed on both. Same values as
  /// [ExerciseItem.video]: `'girl'`, `'men'`, or null for "not told".
  final String? body;

  /// Radius scales with the tile so a 44px thumb and a 56px one are the same
  /// shape rather than two different roundings.
  double get _radius => size * 0.31;

  @override
  Widget build(BuildContext context) {
    final poster = exercise?.posterFor(body);
    if (poster == null) return _Fallback(id: exercise?.id ?? '', size: size);

    return ClipRRect(
      borderRadius: BorderRadius.circular(_radius),
      child: Container(
        width: size,
        height: size,
        // The clips are rendered on flat white, so a white bed keeps the
        // letterboxing invisible instead of framing every figure in grey.
        color: Colors.white,
        child: Image.asset(
          poster,
          // H4, finished. This tile is decorative at every call site, and that
          // was checked rather than assumed: five of the six put it in a Row
          // directly beside a `Text` carrying the exercise title, so a label
          // here would make a screen reader say the name twice. The sixth --
          // the programme card's tile strip (`workouts_page.dart:1169`) -- is
          // the one row with no text per tile, and it supplies its own
          // `Semantics(label: title)` wrapper for exactly that reason.
          //
          // Without this flag `Image` still contributes a node with
          // `image: true` and no label, which announces as an unnamed graphic:
          // noise between the title and the next control, on every list in the
          // app. Silent is the correct behaviour for a picture whose name is
          // already being read out beside it.
          excludeFromSemantics: true,
          fit: BoxFit.cover,
          // The frame is wider than it is tall (400x230) and these tiles are
          // square, so `cover` crops the sides. Aligning to the top keeps the
          // head in frame — centring cut it off on standing exercises.
          alignment: const Alignment(0, -0.35),
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) =>
              _Fallback(id: exercise?.id ?? '', size: size),
        ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.id, required this.size});
  final String id;
  final double size;

  @override
  Widget build(BuildContext context) {
    final gradient = AppPalette
        .tileGradients[id.hashCode.abs() % AppPalette.tileGradients.length];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.31),
        gradient: LinearGradient(colors: gradient),
      ),
      child: Icon(Icons.fitness_center_rounded,
          color: AppSemanticColors.onGradientInk, size: size * 0.5),
    );
  }
}
