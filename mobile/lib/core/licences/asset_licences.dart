import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/foundation.dart' show LicenseEntryWithLineBreaks;
import 'package:flutter/foundation.dart' show LicenseRegistry;

/// One piece of third-party content the app ships, and the terms it ships under.
///
/// Bundled ASSETS are the gap this closes. `LicenseRegistry` collects package
/// licences automatically, but a JPEG, an SVG or a JSON file copied into
/// `assets/` brings its own obligations and nothing surfaces them. Both of the
/// licences below require attribution visible to the user, and CC-BY-SA also
/// requires naming the licence itself — so shipping the content without a
/// credits surface is a licence breach, not a missing nicety.
class AssetAttribution {
  const AssetAttribution({
    required this.what,
    required this.author,
    required this.licence,
    required this.url,
    this.note,
  });

  /// Which bundled content this covers, in the user's terms.
  final String what;
  final String author;

  /// The licence's own name, spelled the way the licence requires.
  final String licence;

  /// Where the original lives, so the credit is checkable.
  final String url;

  /// Anything a reader needs to know beyond the credit — a share-alike
  /// obligation, say.
  final String? note;

  /// Rendered into `showLicensePage` under [what].
  String get body => <String>[
        'Author: $author',
        'Licence: $licence',
        'Source: $url',
        if (note != null) '', if (note != null) note!,
      ].join('\n');
}

/// Every bundled asset that carries a licence obligation.
///
/// Kept as data, not prose in a widget, so a test can assert that nothing is
/// half-credited and that adding an asset pack without its credit fails.
const List<AssetAttribution> kAssetAttributions = <AssetAttribution>[
  AssetAttribution(
    what: 'Exercise catalogue and demonstration frames',
    author: 'yuhonas and contributors (free-exercise-db)',
    licence: 'The Unlicense (public domain)',
    url: 'https://github.com/yuhonas/free-exercise-db',
    note: 'Instruction text was translated into Russian for this app; the '
        'source text is public domain.',
  ),
  AssetAttribution(
    what: 'Anatomical muscle chart (front and back)',
    author: 'Ryan Graves, with element ids restructured by Kit G.',
    licence: 'Creative Commons Attribution 4.0 International (CC BY 4.0)',
    url: 'https://creativecommons.org/licenses/by/4.0/',
    note: 'Original artwork: '
        'https://www.figma.com/community/file/1320468164820924031 — '
        'redistributed here with per-muscle element ids, and recoloured at '
        'runtime to show which muscles an exercise works.',
  ),
];

/// Publishes [kAssetAttributions] into Flutter's licence registry.
///
/// Call once during startup. `LicenseRegistry.addLicense` takes a factory that
/// is invoked lazily, only when the licence page is actually opened.
void registerAssetLicences() {
  LicenseRegistry.addLicense(() async* {
    for (final a in kAssetAttributions) {
      yield LicenseEntryWithLineBreaks(<String>[a.what], a.body);
    }
  });
}

/// Test seam: the paragraphs [registerAssetLicences] would publish.
@visibleForTesting
List<String> debugLicenceBodies() =>
    kAssetAttributions.map((a) => a.body).toList(growable: false);
