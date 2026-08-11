import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'package:fitness_app/core/theme/app_theme.dart';

/// P2a — the fonts are shipped, and the theme asks for the ones that are.
///
/// The failure this guards is silent by construction. A wrong family string, a
/// weight the bundle does not contain, or a file removed from `assets/fonts/`
/// does not throw: Flutter falls back to the platform font and the app renders
/// in the wrong typeface at a different width. That is exactly what
/// `google_fonts` did on every offline first launch, and the reason the
/// download was removed rather than merely made unlikely.
///
/// So the pubspec is read as data and compared against the constants the theme
/// actually uses. Neither side can drift without failing here.
///
/// **What this does NOT cover.** `flutter test` does not rasterize bundled
/// fonts — there is no `flutter_test_config.dart` and no `loadAppFonts()`, so
/// the widget test below reads the family NAME off `ThemeData` and proves
/// nothing about glyphs. This is metadata coverage. Whether the six faces
/// parse and render is only answerable on a device, and is not claimed here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
  final declared = <String, Set<int>>{};
  final assetPaths = <String>[];
  for (final family in (pubspec['flutter']['fonts'] as YamlList)) {
    final name = family['family'] as String;
    declared[name] = {};
    for (final face in (family['fonts'] as YamlList)) {
      declared[name]!.add(face['weight'] as int);
      assetPaths.add(face['asset'] as String);
    }
  }

  test('every declared font file is present and is really a font', () {
    expect(assetPaths, isNotEmpty);
    for (final path in assetPaths) {
      final f = File(path);
      expect(f.existsSync(), isTrue, reason: '$path is declared but missing');
      // These were fetched over the network, and an error page or a truncated
      // download is still a file of plausible size. Check the sfnt version tag
      // the spec puts in the first four bytes: 0x00010000 for TrueType
      // outlines, or the ASCII tags 'true' / 'ttcf' / 'OTTO'.
      final head = f.openSync().readSync(4);
      final tag = String.fromCharCodes(head);
      final isSfnt = tag == 'true' ||
          tag == 'ttcf' ||
          tag == 'OTTO' ||
          (head[0] == 0x00 &&
              head[1] == 0x01 &&
              head[2] == 0x00 &&
              head[3] == 0x00);
      expect(isSfnt, isTrue, reason: '$path is not a font file');
    }
  });

  test('the theme names the two families the pubspec ships', () {
    expect(declared.keys, containsAll(<String>[kBodyFont, kDisplayFont]));
  });

  test('every weight the app asks for anywhere is a face that exists', () {
    // NOT just the weights `app_theme.dart` names. `lib/` reaches for weights
    // through `.copyWith(fontWeight:)` at hundreds of call sites, and the
    // first version of the bundle missed w800 — the single most-used weight in
    // the app. A missing face is synthesized silently by the engine, so this
    // has to be checked against what the code actually asks for.
    //
    // Derived by scanning `lib/` here rather than hardcoding the list, so a
    // feature that introduces a new weight fails this test instead of quietly
    // rendering a fake one.
    final used = <int>{};
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      for (final m
          in RegExp(r'FontWeight\.w([1-9]00)').allMatches(f.readAsStringSync())) {
        used.add(int.parse(m.group(1)!));
      }
    }
    expect(used, isNotEmpty, reason: 'the scan itself found nothing');

    // Both families must cover every weight, because a `.copyWith` on a
    // display role and one on a body role are indistinguishable from here.
    for (final family in [kBodyFont, kDisplayFont]) {
      expect(declared[family], containsAll(used),
          reason: '$family is missing a weight the app requests');
    }
    // Inter additionally carries w400: it is Material's default for body
    // roles, which no `.copyWith` mentions precisely because it is the
    // default.
    expect(declared[kBodyFont], contains(400));
  });

  testWidgets('the built theme uses the bundled families, not a fallback',
      (tester) async {
    late ThemeData realised;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Builder(builder: (c) {
        realised = Theme.of(c);
        return const SizedBox.shrink();
      }),
    ));

    final text = realised.textTheme;
    // Body roles read; display roles are the condensed face. Asserting BOTH
    // matters: an earlier version of this theme applied one family to
    // everything, which is why headings rendered in the body font.
    expect(text.bodyMedium?.fontFamily, kBodyFont);
    expect(text.titleLarge?.fontFamily, kBodyFont);
    expect(text.displayLarge?.fontFamily, kDisplayFont);
    expect(text.headlineSmall?.fontFamily, kDisplayFont);
    // The button styles were separate `GoogleFonts.inter()` calls and are the
    // easiest thing to leave behind in a migration like this.
    expect(
      realised.filledButtonTheme.style?.textStyle
          ?.resolve(<WidgetState>{})?.fontFamily,
      kBodyFont,
    );
    expect(
      realised.outlinedButtonTheme.style?.textStyle
          ?.resolve(<WidgetState>{})?.fontFamily,
      kBodyFont,
    );
  });

  test('nothing still depends on google_fonts', () {
    // The point of the gate is that no code path can reach the network for a
    // typeface. Leaving the dependency in place would let one come back
    // without anyone noticing.
    final deps = pubspec['dependencies'] as YamlMap;
    expect(deps.keys, isNot(contains('google_fonts')));
  });
}
