import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/workouts/workouts_page.dart';
import 'package:fitness_app/shared/widgets/aurora_background.dart';

/// Bug 5 — "right-edge chip clipping", reported from the operator's own device
/// walkthrough and carried unfixed since 2026-08-09.
///
/// The programme card's header is a `Row(spaceBetween)` holding a level chip
/// and a goal chip, each sizing itself to its text. Nothing in that row can
/// give: a `Row` does not wrap and does not scroll, so once the two chips want
/// more width than the card has, the second one is clipped at the right edge
/// and the user sees a tag cut in half. It is silent — a `RenderFlex` overflow
/// paints stripes in debug and simply clips in a release build, which is why a
/// walkthrough caught it and no test did.
///
/// Two conditions push it over on hardware people actually own, and this file
/// pins both:
///
///  * a 320dp-wide screen, which is what the project's own `Pixel_API_34`
///    emulator reports (`docs/Redisign/reference/emulator/README.md`), and
///  * a large-text accessibility setting, which scales the chip text but not
///    the card.
///
/// Rendered in **Russian** on purpose, against this repo's usual `kTestLocale`
/// of `en`: `lib/main.dart` pins `ru` in production, so Russian is the width
/// the shipped app has to survive. Asserting in English would test a string
/// nobody sees.

AssetEquipmentRepository _seededRepo() {
  return AssetEquipmentRepository()
    ..seedForTests(
      equipment: const [
        EquipmentItem(
          id: 'rack',
          name: 'Rack',
          manufacturer: 'Y',
          category: 'strength',
          description: '',
        ),
      ],
      exercises: const [
        ExerciseItem(
          id: 'rack_squat',
          title: 'Back squat',
          equipmentId: 'rack',
          muscles: ['quads'],
          difficulty: ExerciseDifficulty.intermediate,
          durationMinutes: 25,
          summary: 'Compound lower body',
          steps: [],
          video: {'men': 'https://cdn.example.com/squat.mp4'},
        ),
      ],
    );
}

Widget _harness(AssetEquipmentRepository repo, {required double textScale}) {
  final router = GoRouter(
    initialLocation: '/workouts',
    routes: [
      GoRoute(path: '/workouts', builder: (_, __) => const WorkoutsPage()),
      GoRoute(
        path: '/workout/:id',
        builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/exercise/:id',
        builder: (_, __) => const Scaffold(body: SizedBox.shrink()),
      ),
    ],
  );
  return ProviderScope(
    overrides: [equipmentRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      locale: const Locale('ru'),
      localizationsDelegates: kAppLocalizationDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: AuroraBackground(child: child ?? const SizedBox.shrink()),
      ),
    ),
  );
}

const List<LocalizationsDelegate<dynamic>> kAppLocalizationDelegates =
    AppLocalizations.localizationsDelegates;

/// The narrowest screen the project has actually rendered on.
const Size _kNarrowPhone = Size(320, 640);

Future<void> _pumpPrograms(
  WidgetTester tester, {
  required double textScale,
}) async {
  tester.view.physicalSize = _kNarrowPhone;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_harness(_seededRepo(), textScale: textScale));
  await tester.pumpAndSettle();
  // R11i/L1: WorkoutsPage now opens on the Library sub-tab by default, so
  // every test in this file (which pins the Programs-tab template cards)
  // must switch to it first -- see workouts_page_test.dart's own note on
  // the same change.
  await tester.tap(find.text('Программы'));
  await tester.pumpAndSettle();
}

void main() {
  group('programme card header chips (bug 5)', () {
    testWidgets('do not overflow at 320dp with default text size',
        (tester) async {
      await _pumpPrograms(tester, textScale: 1.0);

      expect(find.byKey(const Key('programme.template.strength_base')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('do not overflow at 320dp with large accessibility text',
        (tester) async {
      // 1.6 is inside what Android's own Display size + Font size settings
      // reach; it is not a synthetic extreme.
      await _pumpPrograms(tester, textScale: 1.6);

      expect(tester.takeException(), isNull);
    });

    testWidgets('keep both tags legible rather than clipping the second one',
        (tester) async {
      await _pumpPrograms(tester, textScale: 1.6);

      // «Средний» + «Похудение» is the worst pair the shipped template set
      // produces (`programme_templates.dart`, "Рельеф и выносливость").
      // Both must still be in the tree AND inside the card's own width --
      // a clipped chip stays in the tree, which is exactly why this asserts
      // on geometry and not on `findsOneWidget` alone.
      // The programme list is lazy, so the worst-pair card is not built until
      // it is scrolled to. Finding "0 widgets" here would be an artefact of
      // that, not evidence the chips are fine.
      final card =
          find.byKey(const Key('programme.template.shred_endurance'));
      // Named explicitly: the page also holds the horizontal goal-filter
      // row, and `scrollUntilVisible` without a `scrollable` cannot choose
      // between two of them.
      await tester.scrollUntilVisible(
        card,
        200,
        scrollable: find
            .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
            .first,
      );
      await tester.pumpAndSettle();
      expect(card, findsOneWidget);
      expect(tester.takeException(), isNull);

      final cardRect = tester.getRect(card);
      for (final label in ['Средний', 'Похудение']) {
        final chip = find.descendant(of: card, matching: find.text(label));
        expect(chip, findsOneWidget, reason: '$label missing from the card');
        final chipRect = tester.getRect(chip);
        expect(
          chipRect.right,
          lessThanOrEqualTo(cardRect.right),
          reason: '$label is drawn past the card\'s right edge',
        );
      }
    });
  });
}
