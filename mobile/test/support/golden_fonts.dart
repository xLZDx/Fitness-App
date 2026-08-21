import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// M8 -- font determinism for golden-image tests.
///
/// `flutter test` never rasterizes the app's real fonts by default; without
/// this, every `Text` in a golden paints with `flutter_test`'s built-in
/// placeholder glyphs. Those are actually already IDENTICAL on every host
/// (they ship inside the Flutter SDK's own Skia build, not read from the OS),
/// so a golden generated against them is stable across machines -- but it is
/// also stable against the WRONG thing: it cannot catch a font-family/weight
/// regression, and every panel of text looks like uniform tofu, which makes a
/// diff useless for a human comparing two PNGs.
///
/// Loading the app's real bundled fonts (Inter, Barlow Condensed, Archivo,
/// Roboto Mono) trades that for the real risk golden tests are known for:
/// font rendering can differ across host platforms. It does NOT, here,
/// because `flutter test` renders through the Skia build embedded in the
/// Flutter SDK (`flutter_tester`), not the operating system's font/text
/// stack -- so two machines on the same Flutter SDK version, with the same
/// font bytes loaded, produce the same pixels. The caveat that remains is
/// documented in `test/golden/README.md`: it is the SDK version and
/// build/OS pairing that must match between whoever generates a golden and
/// whoever verifies it (this repo's CI always runs `ubuntu-latest`), not the
/// glyphs.
///
/// Reads `pubspec.yaml`'s `flutter: fonts:` block as data instead of a second,
/// hardcoded copy of the family list -- the same reasoning
/// `test/theme/font_bundle_test.dart` already gives for parsing it there:
/// two independently-maintained copies of "which fonts this app ships" is a
/// second, worse source of truth, and the two would drift apart exactly when
/// a face is added, renamed, or dropped.
Future<void> loadHudGoldenFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final YamlMap pubspec =
      loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
  final YamlList families = pubspec['flutter']['fonts'] as YamlList;

  for (final dynamic family in families) {
    final String name = (family as YamlMap)['family'] as String;
    final FontLoader loader = FontLoader(name);
    for (final dynamic face in (family['fonts'] as YamlList)) {
      final String asset = (face as YamlMap)['asset'] as String;
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }
}

/// Pins the test surface a golden pumps into.
///
/// `WidgetTester`'s default surface size is an implementation detail of
/// `flutter_test`, not something this suite controls -- if a future Flutter
/// upgrade changes it, every golden that relied on the default would shift
/// for a reason that has nothing to do with the widget under test. Setting it
/// explicitly, and resetting it via [addTearDown] so it cannot leak into the
/// next test in the same file, removes that dependency.
///
/// `devicePixelRatio` is pinned to `1.0` so a golden's pixel dimensions equal
/// its logical size -- readable file sizes, and one less axis that could
/// silently move the comparison.
void pinGoldenSurface(
  WidgetTester tester, {
  Size size = const Size(800, 600),
  double devicePixelRatio = 1.0,
}) {
  tester.view.physicalSize = size * devicePixelRatio;
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
