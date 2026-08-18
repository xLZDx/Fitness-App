import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/core/theme/hud_tokens.dart';
import 'package:fitness_app/core/theme/hud_typography.dart';

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

  group('the Cyrillic gap in the display family', () {
    // Measured 2026-08-19 with fontTools over every bundled face:
    //   Barlow Condensed  525 glyphs, 0/64 of А-я, no Ё
    //   Archivo           653 glyphs, 0/64 of А-я, no Ё
    //   Inter            2849 glyphs, 64/64 of А-я, Ё present
    //   Roboto Mono       876 glyphs, 64/64 of А-я, Ё present
    // Russian is this app's default language, so the first two cannot set it.

    testWidgets('every display role names a fallback that can set Russian',
        (tester) async {
      late TextTheme text;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(builder: (c) {
          text = Theme.of(c).textTheme;
          return const SizedBox.shrink();
        }),
      ));

      final roles = <String, TextStyle?>{
        'displayLarge': text.displayLarge,
        'displayMedium': text.displayMedium,
        'displaySmall': text.displaySmall,
        'headlineLarge': text.headlineLarge,
        'headlineMedium': text.headlineMedium,
        'headlineSmall': text.headlineSmall,
      };
      for (final entry in roles.entries) {
        expect(entry.value?.fontFamily, kDisplayFont, reason: entry.key);
        // Without this, a Russian heading falls back to the PLATFORM font --
        // a different face on every device, and silent, because a missing
        // glyph never throws.
        expect(entry.value?.fontFamilyFallback, contains(kBodyFont),
            reason: '${entry.key} has no Cyrillic-capable fallback');
      }
    });

    test('the fallback family is itself bundled at every display weight', () {
      // A fallback missing the weight the role asked for is a synthesized
      // face, which is the same silent degradation one level down.
      expect(declared.keys, containsAll(kDisplayFontFallback));
      for (final family in kDisplayFontFallback) {
        expect(declared[family], containsAll(declared[kDisplayFont]!));
      }
    });

    test('body roles need no fallback because Inter already covers them', () {
      // Stated so the asymmetry reads as a decision rather than an omission.
      expect(kBodyFont, isNot(kDisplayFont));
      expect(declared.keys, contains(kBodyFont));
    });
  });

  group('the HUD families', () {
    test('both are declared and their files ship', () {
      // The generic "every declared file exists" case above already checks the
      // bytes; this pins that the two families the HUD names are DECLARED at
      // all, which is what a `fontFamily: 'Archivo'` with no pubspec entry
      // silently fails at.
      expect(declared.keys, contains(kHudFont));
      expect(declared.keys, contains(kHudMonoFont));
    });

    test('Archivo covers every weight the HUD type scale asks of it', () {
      // Derived by scanning the type scale rather than hardcoded: a role added
      // at a weight the bundle lacks must fail here, not synthesize a fake
      // face at run time.
      final source =
          File('lib/core/theme/hud_typography.dart').readAsStringSync();
      final used = RegExp(r'FontWeight\.w([1-9]00)')
          .allMatches(source)
          .map((m) => int.parse(m.group(1)!))
          .toSet();
      expect(used, isNotEmpty, reason: 'the scan itself found nothing');
      expect(declared[kHudFont], containsAll(used));
    });

    test('Roboto Mono covers the weights the mono role defaults to', () {
      // The mono role's default is w600 and callers pass w400; the family only
      // goes to 700, so a w800 mono anywhere would be a fake face.
      expect(declared[kHudMonoFont], containsAll(<int>[400, 500, 600, 700]));
      expect(declared[kHudMonoFont], isNot(contains(800)));
    });

    test('the Cyrillic fallback is bundled at every weight Archivo is', () {
      // Archivo has NO Cyrillic — 0 of 256 codepoints, and Google's own
      // METADATA.pb declares only latin/latin-ext/vietnamese. Russian is this
      // app's default language, so every Russian glyph resolves through the
      // fallback named in `hud_typography.dart`. A fallback that is missing the
      // weight the style asked for is a synthesized face, which is the same
      // silent degradation as no fallback at all.
      for (final family in kHudFontFallback) {
        expect(declared.keys, contains(family),
            reason: '$family is named as a fallback but is not bundled');
        expect(declared[family], containsAll(declared[kHudFont]!),
            reason: '$family cannot serve every weight Archivo declares');
      }
    });

    test('the mono role deliberately has no proportional fallback', () {
      // Falling back to Inter for a glyph Roboto Mono lacks would break the
      // digit column the role exists for, silently.
      expect(HudType.mono(HudTokens.dark).fontFamilyFallback,
          anyOf(isNull, isEmpty));
    });
  });

  test('nothing still depends on google_fonts', () {
    // The point of the gate is that no code path can reach the network for a
    // typeface. Leaving the dependency in place would let one come back
    // without anyone noticing.
    final deps = pubspec['dependencies'] as YamlMap;
    expect(deps.keys, isNot(contains('google_fonts')));
  });
}
