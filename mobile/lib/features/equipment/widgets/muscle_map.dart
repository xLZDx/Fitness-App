import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/anatomy_map.dart';
import '../data/catalog_labels.dart';

/// Which muscles a movement loads, and how hard.
enum MuscleLoad { none, secondary, primary }

/// Front/back anatomical chart that lights up the muscles an exercise works —
/// primary in full colour, supporting muscles dimmer.
///
/// Draws real anatomical artwork (see `assets/anatomy/`, CC BY 4.0, credited on
/// the licences screen) rather than hand-authored shapes. The previous version
/// was a CustomPainter of hand-placed blobs; it scaled and themed nicely but it
/// looked like hand-placed blobs, which was the complaint.
///
/// Highlighting works by rewriting the `fill` of the chart's per-muscle paths.
/// The artwork is uniform in a way that makes this safe: every muscle path ships
/// `fill="#BDBDBD"` and every non-muscle part (body underlayer, hands, face)
/// ships `#E0E0E0`, so an element's role is readable from the source without
/// walking the group structure.
class MuscleMap extends StatefulWidget {
  const MuscleMap({
    super.key,
    required this.primary,
    this.secondary = const [],
  });

  /// Muscle keys as used in the catalog (`quads`, `lats`, `core`, ...).
  final List<String> primary;
  final List<String> secondary;

  /// Resolves how hard a region is worked. Pure and exported for tests.
  static MuscleLoad loadFor(
    String region, {
    required List<String> primary,
    required List<String> secondary,
  }) {
    if (primary.contains(region)) return MuscleLoad.primary;
    if (secondary.contains(region)) return MuscleLoad.secondary;
    return MuscleLoad.none;
  }

  @override
  State<MuscleMap> createState() => _MuscleMapState();
}

/// Source fill of a muscle in the shipped artwork.
const _muscleFill = '#BDBDBD';

const _frontAsset = 'assets/anatomy/muscle_front.svg';
const _backAsset = 'assets/anatomy/muscle_back.svg';

/// Raw SVG text, read once per asset for the life of the process.
final Map<String, Future<String>> _rawSvg = <String, Future<String>>{};

Future<String> _loadSvg(String asset) =>
    _rawSvg[asset] ??= rootBundle.loadString(asset);

String _hex(Color c) =>
    '#${((c.r * 255).round() << 16 | (c.g * 255).round() << 8 | (c.b * 255).round()).toRadixString(16).padLeft(6, '0')}';

/// Rewrites every muscle fill in [svg] according to how hard it is worked.
///
/// Pure, and the only place colour decisions happen, so the mapping can be
/// tested against the real asset without a render.
@visibleForTesting
String recolourChart(
  String svg, {
  required Map<String, List<String>> ids,
  required List<String> primary,
  required List<String> secondary,
  required String primaryHex,
  required String secondaryHex,
  required String restingHex,
  required String bodyHex,
}) {
  // id prefix -> replacement colour, strongest claim winning: a muscle listed
  // as both primary and secondary reads as primary.
  final claims = <String, String>{};
  void claim(List<String> tags, String colour) {
    for (final tag in tags) {
      for (final prefix in ids[tag] ?? const <String>[]) {
        claims[prefix] = colour;
      }
    }
  }

  claim(secondary, secondaryHex);
  claim(primary, primaryHex);

  return svg.replaceAllMapped(RegExp(r'<path\b[^>]*>'), (m) {
    final element = m.group(0)!;
    final idMatch = RegExp(r'\bid="([^"]+)"').firstMatch(element);
    final fillMatch = RegExp(r'\bfill="([^"]*)"').firstMatch(element);
    if (fillMatch == null) return element;

    final id = idMatch?.group(1) ?? '';
    final wasMuscle = fillMatch.group(1)!.trim() == _muscleFill;

    String? claimed;
    for (final entry in claims.entries) {
      if (id.startsWith(entry.key)) {
        claimed = entry.value;
        break;
      }
    }

    final colour = claimed ?? (wasMuscle ? restingHex : bodyHex);
    return element.replaceRange(
      fillMatch.start,
      fillMatch.end,
      'fill="$colour"',
    );
  });
}

class _MuscleMapState extends State<MuscleMap> {
  String? _front;
  String? _back;

  /// What [_front]/[_back] were built for. Recolouring a 180 KB string and
  /// letting flutter_svg recompile it on every frame would be wasteful, and the
  /// inputs only change when the exercise or the theme does.
  String? _signature;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primaryHex = _hex(scheme.primary);
    final secondaryHex =
        _hex(Color.lerp(scheme.surface, scheme.primary, 0.42)!);
    final restingHex = _hex(Color.lerp(scheme.surface, scheme.onSurface, 0.16)!);
    final bodyHex = _hex(Color.lerp(scheme.surface, scheme.onSurface, 0.07)!);

    final signature = [
      widget.primary.join(','),
      widget.secondary.join(','),
      primaryHex,
      secondaryHex,
      restingHex,
      bodyHex,
    ].join('|');

    if (signature != _signature) {
      _signature = signature;
      _front = null;
      _back = null;
      _rebuild(
        primaryHex: primaryHex,
        secondaryHex: secondaryHex,
        restingHex: restingHex,
        bodyHex: bodyHex,
        forSignature: signature,
      );
    }

    final unmapped = <String>[
      for (final m in [...widget.primary, ...widget.secondary])
        if (kTagsWithoutShape.contains(m)) m,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The aspect ratio belongs OUT here, around the pair. Putting it on each
        // figure inside an Expanded gave them a tight width, so height was
        // forced to width x 1137/587 with no room to shrink and the column
        // overflowed on short boxes.
        Flexible(
          child: AspectRatio(
            aspectRatio: (2 * 587) / 1137,
            child: Row(
              children: [
                Expanded(child: _Chart(svg: _front)),
                Expanded(child: _Chart(svg: _back)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: _Caption(AppLocalizations.of(context).muscleMapFront),
            ),
            Expanded(
              child: _Caption(AppLocalizations.of(context).muscleMapBack),
            ),
          ],
        ),
        // Worked muscles the artwork cannot show. Saying so beats colouring an
        // approximate neighbour, which would teach the user something false.
        if (unmapped.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)
                .muscleMapAlsoWorked(_nameFor(context, unmapped)),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  String _nameFor(BuildContext context, List<String> tags) {
    final l = AppLocalizations.of(context);
    return tags.toSet().map((t) => CatalogLabels.muscle(l, t)).join(', ');
  }

  Future<void> _rebuild({
    required String primaryHex,
    required String secondaryHex,
    required String restingHex,
    required String bodyHex,
    required String forSignature,
  }) async {
    final front = await _loadSvg(_frontAsset);
    final back = await _loadSvg(_backAsset);
    if (!mounted || _signature != forSignature) return;
    setState(() {
      _front = recolourChart(
        front,
        ids: kFrontMuscleIds,
        primary: widget.primary,
        secondary: widget.secondary,
        primaryHex: primaryHex,
        secondaryHex: secondaryHex,
        restingHex: restingHex,
        bodyHex: bodyHex,
      );
      _back = recolourChart(
        back,
        ids: kBackMuscleIds,
        primary: widget.primary,
        secondary: widget.secondary,
        primaryHex: primaryHex,
        secondaryHex: secondaryHex,
        restingHex: restingHex,
        bodyHex: bodyHex,
      );
    });
  }

  @override
  void didUpdateWidget(MuscleMap old) {
    super.didUpdateWidget(old);
    // Compared by CONTENT: the parent rebuilds these lists on every build, so
    // reference comparison would rebuild the chart every frame.
    if (!listEquals(old.primary, widget.primary) ||
        !listEquals(old.secondary, widget.secondary)) {
      _signature = null;
    }
  }
}

class _Chart extends StatelessWidget {
  const _Chart({required this.svg});
  final String? svg;

  @override
  Widget build(BuildContext context) {
    if (svg == null) return const SizedBox.shrink();
    // BoxFit.contain, so the figure keeps the artwork's own proportions even
    // though the enclosing half-box is only approximately that shape.
    return SvgPicture.string(svg!, fit: BoxFit.contain);
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      textAlign: TextAlign.center,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
      ),
    );
  }
}
