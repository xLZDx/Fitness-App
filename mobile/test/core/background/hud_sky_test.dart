import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/background/hud_sky.dart';
import 'package:fitness_app/core/theme/hud_tokens.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

void main() {
  group('phase boundaries', () {
    test('every stated boundary lands on the right side', () {
      // The source is a chain of `<` comparisons, so each boundary hour
      // belongs to the LATER phase. Both sides of all six are checked, because
      // an off-by-one here is invisible except for a few minutes a day.
      const List<(double, HudSkyPhase)> cases = <(double, HudSkyPhase)>[
        (0.0, HudSkyPhase.night),
        (4.99, HudSkyPhase.night),
        (5.0, HudSkyPhase.dawn),
        (6.99, HudSkyPhase.dawn),
        (7.0, HudSkyPhase.morning),
        (10.99, HudSkyPhase.morning),
        (11.0, HudSkyPhase.day),
        (15.99, HudSkyPhase.day),
        (16.0, HudSkyPhase.golden),
        (18.99, HudSkyPhase.golden),
        (19.0, HudSkyPhase.dusk),
        (21.99, HudSkyPhase.dusk),
        (22.0, HudSkyPhase.night),
        (23.99, HudSkyPhase.night),
      ];
      for (final (double h, HudSkyPhase want) in cases) {
        expect(HudSkyPhase.forHour(h), want, reason: 'hour $h');
      }
    });

    test('night wraps midnight rather than being two phases', () {
      // The one property a naive range table gets wrong.
      expect(HudSkyPhase.forHour(23.5), HudSkyPhase.night);
      expect(HudSkyPhase.forHour(0.5), HudSkyPhase.night);
      expect(
        HudSky.assetFor(HudSkyPhase.night, HudPhotoSet.a),
        HudSky.assetFor(HudSkyPhase.night, HudPhotoSet.b),
      );
    });

    test('out-of-range input is clamped, not wrapped', () {
      // A negative hour is the prototype's "use live time" sentinel, and it
      // must never silently become a phase here — the caller resolves it.
      expect(HudSkyPhase.forHour(-1), HudSkyPhase.night);
      expect(HudSkyPhase.forHour(99), HudSkyPhase.night);
    });

    test('forTime reads minutes, not just the hour', () {
      expect(
        HudSkyPhase.forTime(DateTime(2026, 8, 19, 4, 59)),
        HudSkyPhase.night,
      );
      expect(
        HudSkyPhase.forTime(DateTime(2026, 8, 19, 5, 0)),
        HudSkyPhase.dawn,
      );
    });
  });

  group('the photo sets', () {
    test('both sets assign all six phases', () {
      for (final HudPhotoSet set in HudPhotoSet.values) {
        for (final HudSkyPhase phase in HudSkyPhase.values) {
          expect(HudSky.assignments(set)[phase], isNotNull,
              reason: '${set.name}/${phase.key}');
        }
      }
    });

    test('the two sets genuinely differ', () {
      // Non-vacuity: an A/B switch that shows the same ten pictures is not a
      // choice. FIVE of the six phases differ; night is `02_volcano` in both,
      // and that is the only shared assignment.
      //
      // This assertion said four when it was written, on the reasoning that
      // `08_coast_turquoise` "appears in both sets" — it does, but at DIFFERENT
      // phases (A/golden, B/day), so it differs at every phase like the rest.
      // Measured rather than reasoned about.
      final Set<HudSkyPhase> same = HudSkyPhase.values
          .where((HudSkyPhase p) =>
              HudSky.assetFor(p, HudPhotoSet.a) ==
              HudSky.assetFor(p, HudPhotoSet.b))
          .toSet();
      expect(same, <HudSkyPhase>{HudSkyPhase.night});
    });

    test('every assigned file is in the catalogue and exists on disk', () {
      for (final HudPhotoSet set in HudPhotoSet.values) {
        for (final String path in HudSky.assignments(set).values) {
          expect(HudSky.catalogue, contains(path));
          expect(File(path).existsSync(), isTrue, reason: path);
        }
      }
    });

    test('the catalogue and the form coach name the same ten scenes', () {
      // These are two lists of the same files in two places, and they will
      // stay that way until the coach moves onto the shared one. Pinned rather
      // than left free: a picture added to one and not the other is exactly
      // the drift nobody would notice.
      expect(HudSky.catalogue.toSet(), kCoachBackdrops.toSet());
      expect(HudSky.catalogue, hasLength(10));
    });
  });

  group('the veil', () {
    test('density scales the phase alpha', () {
      final HudTokens t = HudTokens.dark;
      const HudSkySelection base = HudSkySelection(phase: HudSkyPhase.day);
      final LinearGradient plain = hudVeil(t, base);
      final LinearGradient heavier =
          hudVeil(t, base.copyWith(veilScale: 1.4));
      expect(heavier.colors.first.a, greaterThan(plain.colors.first.a));
    });

    test('it refuses to thin below the readability floor', () {
      // Not a style preference: below ~55% of the handoff's own alpha, a bright
      // sky puts white text on white and the app's own refusals stop being
      // readable. Asking for 0 yields the floor.
      final HudTokens t = HudTokens.dark;
      const HudSkySelection base = HudSkySelection(phase: HudSkyPhase.day);
      final LinearGradient floored =
          hudVeil(t, base.copyWith(veilScale: 0.0));
      final LinearGradient atFloor =
          hudVeil(t, base.copyWith(veilScale: 0.55));
      expect(floored.colors.first.a, closeTo(atFloor.colors.first.a, 0.001));
      expect(floored.colors.first.a, greaterThan(0.3));
    });

    test('no stop can be pushed past fully opaque', () {
      final LinearGradient g = hudVeil(
        HudTokens.dark,
        const HudSkySelection(phase: HudSkyPhase.day, veilScale: 99),
      );
      for (final Color c in g.colors) {
        expect(c.a, lessThanOrEqualTo(1.0));
      }
    });

    test('it runs top to bottom with the handoff stop positions', () {
      final LinearGradient g =
          hudVeil(HudTokens.dark, const HudSkySelection(phase: HudSkyPhase.dawn));
      expect(g.begin, Alignment.topCenter);
      expect(g.end, Alignment.bottomCenter);
      expect(g.stops, <double>[0.0, 0.58, 0.82, 1.0]);
    });
  });

  group('selection identity', () {
    test('a user photo wins over the phase asset', () {
      const HudSkySelection s = HudSkySelection(
        phase: HudSkyPhase.day,
        userPhotoPath: '/data/user/0/pic.jpg',
      );
      expect(s.usesUserPhoto, isTrue);
      expect(s.imageKey, '/data/user/0/pic.jpg');
    });

    test('two phases sharing one picture do not trigger a crossfade', () {
      // set A golden and set B day are both `08_coast_turquoise`. Fading a
      // picture into itself is a 1.6s dip to nothing.
      const HudSkySelection a =
          HudSkySelection(phase: HudSkyPhase.golden, photoSet: HudPhotoSet.a);
      const HudSkySelection b =
          HudSkySelection(phase: HudSkyPhase.day, photoSet: HudPhotoSet.b);
      expect(a.imageKey, b.imageKey);
    });

    test('clearing a user photo returns to the curated asset', () {
      const HudSkySelection s = HudSkySelection(
        phase: HudSkyPhase.dusk,
        userPhotoPath: '/tmp/x.jpg',
      );
      expect(s.copyWith(clearUserPhoto: true).imageKey, s.assetPath);
    });
  });

  group('the background widget', () {
    testWidgets('paints a base colour, a veil and the child', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: HudSkyBackground(
          selection: HudSkySelection(phase: HudSkyPhase.night),
          child: Text('content', textDirection: TextDirection.ltr),
        ),
      ));
      expect(find.text('content'), findsOneWidget);
      // The veil must actually be painted, not merely computed.
      final Iterable<DecoratedBox> boxes =
          t.widgetList<DecoratedBox>(find.byType(DecoratedBox));
      final bool veiled = boxes.any((DecoratedBox b) {
        final Decoration d = b.decoration;
        return d is BoxDecoration &&
            d.gradient is LinearGradient &&
            (d.gradient! as LinearGradient).stops?.length == 4;
      });
      expect(veiled, isTrue, reason: 'the four-stop veil must be on screen');
    });

    testWidgets('holds two layers at most while crossfading', (t) async {
      Widget app(HudSkySelection s) => MaterialApp(
            home: HudSkyBackground(selection: s, child: const SizedBox()),
          );
      await t.pumpWidget(app(const HudSkySelection(phase: HudSkyPhase.night)));
      expect(find.byType(Image), findsOneWidget);

      await t.pumpWidget(app(const HudSkySelection(phase: HudSkyPhase.day)));
      await t.pump();
      // The prototype mounts all six phase images at once; at 1440x2560 that
      // is ~84 MB resident for five pictures nobody is looking at.
      expect(find.byType(Image), findsNWidgets(2));
    });

    testWidgets('the decorative streaks are hidden from screen readers',
        (t) async {
      final SemanticsHandle handle = t.ensureSemantics();
      await t.pumpWidget(const MaterialApp(
        home: HudSkyBackground(
          selection: HudSkySelection(phase: HudSkyPhase.dawn),
          child: Text('only this', textDirection: TextDirection.ltr),
        ),
      ));
      expect(find.bySemanticsLabel('only this'), findsOneWidget);
      handle.dispose();
    });
  });
}
