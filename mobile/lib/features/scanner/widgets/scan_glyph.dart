import 'package:flutter/widgets.dart';

/// One glyph from the design reference's icon font, drawn as the reference
/// draws it.
///
/// SCAN-G1 (core/SCAN_G1_SCOPE.md, R6). The reference sets its Scan icons in
/// Google's *Material Symbols Sharp* (`Sunset.dc.html:193,216,222`: a
/// `data-icon` span with `font-family:'Material Symbols Sharp'`), which is a
/// different drawing from Flutter's `Icons.*` -- the same name in the two
/// fonts has different stroke widths, corner treatments and optical sizes.
/// The app used `Icons.center_focus_weak` and friends, which is one reason
/// its Scan screen never matched the reference pixel for pixel. This draws
/// from a six-glyph subset of the reference's own font
/// (`assets/fonts/MaterialSymbolsSharp-scan.ttf`, built by
/// `tools/design/build_symbols_subset.py`), with the variation axes the
/// reference's Google Fonts request pins: `wght 300, FILL 0, GRAD 0`, and
/// `opsz` following the size, which is what `font-optical-sizing: auto`
/// does in the browser.
///
/// It is a [Text], not an [Icon]: [Icon] has no `fontVariations` and would
/// draw the font's default 400 weight. Decorative on every call site (the
/// button that holds it carries the label), so it is excluded from semantics.
class ScanGlyph extends StatelessWidget {
  const ScanGlyph({
    super.key,
    required this.codePoint,
    required this.size,
    required this.color,
  });

  /// `center_focus_weak` -- the viewfinder's centre mark.
  static const int centerFocusWeak = 0xE3B5;

  /// `center_focus_strong` -- the Recognise button.
  static const int centerFocusStrong = 0xE3B4;

  /// `refresh` -- the Scan again button.
  static const int refresh = 0xE5D5;

  /// `arrow_forward` -- the match card's call to action.
  static const int arrowForward = 0xE5C8;

  /// `photo_library` -- From gallery (production row).
  static const int photoLibrary = 0xE413;

  /// `videocam` -- the live labeler toggle (production row).
  static const int videocam = 0xE04B;

  /// The family as declared in `pubspec.yaml`.
  static const String fontFamily = 'Material Symbols Sharp';

  final int codePoint;

  /// Font size == box size: the reference span is `font-size:36px` in a
  /// 36x36 box (`scan_anchors.json` `centre_glyph`).
  final double size;
  final Color color;

  /// The exact style, exposed so a test can assert identity on the rendered
  /// [Text] rather than on this widget's fields.
  static TextStyle style({required double size, required Color color}) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: size,
      // 1.0: the glyph box is the em box, as in the reference span.
      height: 1.0,
      color: color,
      fontVariations: <FontVariation>[
        const FontVariation('wght', 300),
        FontVariation('opsz', size.clamp(20, 48).toDouble()),
        const FontVariation('FILL', 0),
        const FontVariation('GRAD', 0),
      ],
      leadingDistribution: TextLeadingDistribution.even,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(
            String.fromCharCode(codePoint),
            style: style(size: size, color: color),
            textAlign: TextAlign.center,
            maxLines: 1,
            softWrap: false,
            // The size IS the design; user text scaling must not grow an icon.
            textScaler: TextScaler.noScaling,
          ),
        ),
      ),
    );
  }
}
