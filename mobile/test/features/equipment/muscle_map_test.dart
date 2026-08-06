import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

import 'package:fitness_app/features/equipment/data/anatomy_map.dart';
import 'package:fitness_app/features/equipment/widgets/muscle_map.dart';
import 'package:fitness_app/core/theme/app_palette.dart';
import 'package:fitness_app/core/theme/app_semantic_colors.dart';

/// Guards the anatomical chart.
///
/// The old suite asserted on hand-authored `Path` geometry, which no longer
/// exists: the chart is real artwork now, and its muscles are addressed by
/// element id. The useful assertions moved with it — every id the mapping
/// references must exist in the shipped SVG, and every muscle tag the catalog
/// can emit must be either drawable or explicitly declared undrawable.
void main() {

  TestWidgetsFlutterBinding.ensureInitialized();

  late String frontSvg;
  late String backSvg;
  late Set<String> catalogTags;

  Set<String> pathIds(String svg) => RegExp(r'<path\b[^>]*\bid="([^"]+)"')
      .allMatches(svg)
      .map((m) => m.group(1)!)
      .toSet();

  setUpAll(() async {
    frontSvg = await rootBundle.loadString('assets/anatomy/muscle_front.svg');
    backSvg = await rootBundle.loadString('assets/anatomy/muscle_back.svg');
    // Derived from the real catalog, NOT hand-typed. The previous version of
    // this test kept its own literal set and it had already drifted: it omitted
    // `adductors`, so nobody noticed that tag had no shape at all.
    final raw = await rootBundle.loadString('assets/data/exercises_vendor.json');
    catalogTags = <String>{
      for (final e in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
        ...List<String>.from(e['muscles'] as List? ?? const []),
    };
  });

  group('MuscleMap.loadFor', () {
    test('primary wins over secondary', () {
      expect(
        MuscleMap.loadFor('chest', primary: ['chest'], secondary: ['chest']),
        MuscleLoad.primary,
      );
    });

    test('secondary is reported when not primary', () {
      expect(
        MuscleMap.loadFor('triceps',
            primary: ['chest'], secondary: ['triceps']),
        MuscleLoad.secondary,
      );
    });

    test('anything else is unworked', () {
      expect(
        MuscleMap.loadFor('calves', primary: ['chest'], secondary: ['triceps']),
        MuscleLoad.none,
      );
    });
  });

  group('anatomy mapping vs the shipped artwork', () {
    test('every catalog tag is drawable or declared undrawable', () {
      final unaccounted = catalogTags
          .difference(kDrawableTags)
          .difference(kTagsWithoutShape)
          .toList()
        ..sort();
      expect(unaccounted, isEmpty,
          reason: 'these muscles would silently never highlight');
    });

    test('nothing is both drawable and declared undrawable', () {
      expect(kDrawableTags.intersection(kTagsWithoutShape), isEmpty);
    });

    test('every declared undrawable tag is really in the catalog', () {
      // Otherwise the exception list outlives the reason for it.
      expect(kTagsWithoutShape.difference(catalogTags), isEmpty);
    });

    test('every mapped id prefix exists in the front chart', () {
      final ids = pathIds(frontSvg);
      final missing = <String>[];
      kFrontMuscleIds.forEach((tag, prefixes) {
        for (final p in prefixes) {
          if (!ids.any((id) => id.startsWith(p))) missing.add('$tag -> $p');
        }
      });
      expect(missing, isEmpty,
          reason: 'a renamed element would silently stop highlighting');
    });

    test('every mapped id prefix exists in the back chart', () {
      final ids = pathIds(backSvg);
      final missing = <String>[];
      kBackMuscleIds.forEach((tag, prefixes) {
        for (final p in prefixes) {
          if (!ids.any((id) => id.startsWith(p))) missing.add('$tag -> $p');
        }
      });
      expect(missing, isEmpty);
    });

    test('the artwork is uniform in the way the recolouring assumes', () {
      // Highlighting keys off the source fill to tell a muscle from the body
      // underlayer. If a future asset update breaks that, the chart would tint
      // hands and faces as muscles.
      for (final svg in [frontSvg, backSvg]) {
        final fills = RegExp(r'\bfill="([^"]*)"')
            .allMatches(svg)
            .map((m) => m.group(1)!.trim())
            .toSet();
        expect(fills.difference({'#BDBDBD', '#E0E0E0', 'none'}), isEmpty);
      }
    });
  });

  group('recolourChart', () {
    const svg = '<svg>'
        '<path fill="#E0E0E0" id="underlayer"/>'
        '<path fill="#BDBDBD" id="pectoralis_major_l"/>'
        '<path fill="#BDBDBD" id="pectoralis_major_r"/>'
        '<path fill="#BDBDBD" id="rectus_abdominis_1_l"/>'
        '<path fill="#BDBDBD" id="gastrocnemius_l"/>'
        '</svg>';

    String run({
      List<String> primary = const [],
      List<String> secondary = const [],
    }) =>
        recolourChart(svg,
            ids: kFrontMuscleIds,
            primary: primary,
            secondary: secondary,
            primaryHex: '#111111',
            secondaryHex: '#222222',
            restingHex: '#333333',
            bodyHex: '#444444');

    test('colours both sides of a primary muscle', () {
      final out = run(primary: ['chest']);
      expect(out, contains('fill="#111111" id="pectoralis_major_l"'));
      expect(out, contains('fill="#111111" id="pectoralis_major_r"'));
    });

    test('numbered segments are covered by the prefix', () {
      final out = run(primary: ['core']);
      expect(out, contains('fill="#111111" id="rectus_abdominis_1_l"'));
    });

    test('unworked muscles get the resting tone, the body gets its own', () {
      final out = run(primary: ['chest']);
      expect(out, contains('fill="#333333" id="gastrocnemius_l"'));
      expect(out, contains('fill="#444444" id="underlayer"'));
    });

    test('secondary is distinct from primary', () {
      final out = run(primary: ['chest'], secondary: ['calves']);
      expect(out, contains('fill="#111111" id="pectoralis_major_l"'));
      expect(out, contains('fill="#222222" id="gastrocnemius_l"'));
    });

    test('a muscle listed twice reads as primary', () {
      final out = run(primary: ['chest'], secondary: ['chest']);
      expect(out, contains('fill="#111111" id="pectoralis_major_l"'));
      expect(out, isNot(contains('fill="#222222"')));
    });

    test('nothing worked leaves every muscle resting', () {
      final out = run();
      expect(out, isNot(contains('#111111')));
      expect(out, isNot(contains('#222222')));
      expect(out, contains('fill="#333333" id="pectoralis_major_l"'));
    });

    test('the element count is preserved', () {
      final before = RegExp(r'<path\b').allMatches(svg).length;
      final after =
          RegExp(r'<path\b').allMatches(run(primary: ['chest'])).length;
      expect(after, before);
    });
  });

  group('MuscleMap widget', () {
    /// Pumps, then lets the REAL event loop run so the asset load can finish.
    ///
    /// `testWidgets` runs inside fake async, where a `rootBundle.loadString`
    /// future never completes — the chart would stay blank and the test would
    /// look like a rendering failure instead of a scheduling one.
    Future<void> settleWithAssets(WidgetTester tester) async {
      await tester.pump();
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }

    /// The tokens, not `AppTheme` — the one widget test that has to make this
    /// substitution, and it is the `runAsync` above that forces it.
    ///
    /// `AppTheme` resolves Inter through Google Fonts. Every other widget test
    /// runs entirely in fake async, where that lookup's future never completes
    /// and so never fails. This file runs the REAL loop so the SVG artwork can
    /// load, which also lets the font lookup finish — and with no network it
    /// finishes by throwing, several times, some of it after the test body has
    /// returned where `takeException` cannot reach it. Consuming those would
    /// have meant giving up the `takeException(), isNull` assertions below,
    /// which are the point of the file.
    ///
    /// Only the letterforms are lost: the widget reads its colours from the
    /// extension installed here, which is what G1.2c routed it through.
    ///
    /// The underlying fact is worth a gate of its own: the shipped app fetches
    /// Inter over the network at runtime, so a cold start with no connection
    /// gets the platform font. Bundling it as an asset would fix that and this
    /// substitution at once.
    Widget wrap(Widget child) => MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppPalette.auroraViolet,
              brightness: Brightness.dark,
              surface: AppSemanticColors.dark.backgroundPrimary,
              onSurface: AppSemanticColors.dark.textPrimary,
            ),
            extensions: const <ThemeExtension<dynamic>>[
              AppSemanticColors.dark
            ],
          ),
          locale: kTestLocale,
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(width: 360, height: 320, child: child),
          ),
        );

    testWidgets('renders both views from the real artwork', (tester) async {
      await tester.pumpWidget(
          wrap(const MuscleMap(primary: ['chest'], secondary: ['triceps'])));
      await settleWithAssets(tester);

      expect(find.byType(SvgPicture), findsNWidgets(2));
      expect(find.text('Front'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('names worked muscles the artwork cannot show', (tester) async {
      await tester.pumpWidget(wrap(const MuscleMap(primary: ['lower_back'])));
      await settleWithAssets(tester);

      expect(find.textContaining('Also worked'), findsOneWidget);
      expect(find.textContaining('Lower back'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('says nothing extra when every muscle is drawable',
        (tester) async {
      await tester.pumpWidget(wrap(const MuscleMap(primary: ['quads'])));
      await settleWithAssets(tester);

      expect(find.textContaining('Also worked'), findsNothing);
    });

    testWidgets('an empty muscle list still renders', (tester) async {
      await tester.pumpWidget(wrap(const MuscleMap(primary: [])));
      await settleWithAssets(tester);
      expect(find.byType(SvgPicture), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  });
}
