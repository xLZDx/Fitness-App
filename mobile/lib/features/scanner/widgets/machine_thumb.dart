import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../equipment/state/equipment_providers.dart';

/// The flat white the clips are rendered on (same bed `ExerciseThumb` uses, so
/// letterboxing stays invisible). A named constant, not a foreground white.
const Color _posterBed = Color(0xFFFFFFFF);

/// A small picture of a catalogue machine, so a candidate on the Scan screen
/// can be recognised by sight and not only by name.
///
/// Uses the machine's own hero image ([equipmentHeroImageProvider]: the poster
/// of the clip that demonstrates it). A machine with no hero -- or one still
/// resolving, or an image that fails to load -- shows a neutral icon tile, so
/// the row never jumps and never shows somebody else's picture.
///
/// Keys: the tile is `machine-thumb-<id>`; when a hero image exists the
/// `Image` itself is `machine-thumb-image-<id>`, which is what tests (and only
/// tests) use to tell "has a picture" from "neutral icon".
class MachineThumb extends ConsumerWidget {
  const MachineThumb({super.key, required this.equipmentId, this.size = 52});

  final String equipmentId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? hero =
        ref.watch(equipmentHeroImageProvider(equipmentId)).valueOrNull;
    final double radius = size * 0.24;

    // The same gradient tile ExerciseThumb uses for "no picture", keyed on the
    // id so a machine keeps its colour; onGradientInk is the AA-checked ink.
    final gradient = AppPalette
        .tileGradients[equipmentId.hashCode.abs() % AppPalette.tileGradients.length];
    Widget fallback() => DecoratedBox(
          decoration: BoxDecoration(gradient: LinearGradient(colors: gradient)),
          child: Icon(Icons.fitness_center_rounded,
              size: size * 0.46, color: AppSemanticColors.onGradientInk),
        );

    // Decode at the size it is drawn at, not at the poster's full resolution:
    // a list of dozens of thumbnails would otherwise keep dozens of full-size
    // bitmaps in the image cache.
    final int decodePx =
        (size * MediaQuery.devicePixelRatioOf(context)).round();

    final Widget child;
    if (hero == null) {
      child = fallback();
    } else if (hero.startsWith('http')) {
      child = Image.network(
        hero,
        key: Key('machine-thumb-image-$equipmentId'),
        cacheWidth: decodePx,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        errorBuilder: (_, __, ___) => fallback(),
      );
    } else {
      child = Image.asset(
        hero,
        key: Key('machine-thumb-image-$equipmentId'),
        cacheWidth: decodePx,
        fit: BoxFit.cover,
        alignment: const Alignment(0, -0.35),
        excludeFromSemantics: true,
        errorBuilder: (_, __, ___) => fallback(),
      );
    }

    // Decorative: the machine's name is always printed beside it.
    return ExcludeSemantics(
      child: ClipRRect(
        key: Key('machine-thumb-$equipmentId'),
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: size,
          height: size,
          // Posters are cut from clips shot on flat white.
          child: ColoredBox(color: _posterBed, child: child),
        ),
      ),
    );
  }
}
