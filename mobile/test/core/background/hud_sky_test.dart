import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/background/hud_sky.dart';
import 'package:fitness_app/core/theme/hud_tokens.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

import '../../support/wcag_contrast.dart';

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
      final LinearGradient heavier = hudVeil(t, base.copyWith(veilScale: 1.4));
      expect(heavier.colors.first.a, greaterThan(plain.colors.first.a));
    });

    test('it refuses to thin below the readability floor', () {
      // Not a style preference: below ~55% of the handoff's own alpha, a bright
      // sky puts white text on white and the app's own refusals stop being
      // readable. Asking for 0 yields the floor.
      //
      // Pinned to an image key with no profile (neutral 1.0 multiplier) so
      // this test is only about the floor's own clamp, not about R-D1-04's
      // per-image boost -- `veilScale: 0.55` genuinely sits AT the floor only
      // when nothing else is scaling it further, which the day phase's own
      // real assigned image (now boosted ~1.34x) no longer does.
      final HudTokens t = HudTokens.dark;
      const HudSkySelection base = HudSkySelection(
        phase: HudSkyPhase.day,
        userPhotoPath: '/data/user/0/no_profile.jpg',
      );
      final LinearGradient floored = hudVeil(t, base.copyWith(veilScale: 0.0));
      final LinearGradient atFloor = hudVeil(t, base.copyWith(veilScale: 0.55));
      expect(floored.colors.first.a, closeTo(atFloor.colors.first.a, 0.001));
      expect(floored.colors.first.a, greaterThan(0.3));
    });

    test('the floor holds even when a bright image would push past it', () {
      // The absolute invariant R-D1-04 must not weaken: whatever the image
      // multiplier, the combined scale can never read below 0.55.
      final HudTokens t = HudTokens.dark;
      const HudSkySelection brightAtZero = HudSkySelection(
        phase: HudSkyPhase.day,
        userPhotoPath:
            'assets/coach_bg/04_fuji_sakura.webp', // multiplier ~1.42
        veilScale: 0.0,
      );
      final LinearGradient g = hudVeil(t, brightAtZero);
      final List<Color> dayFloor = HudTokens.dark.veilStops['day']!;
      for (int i = 0; i < g.colors.length; i++) {
        // The floored value must equal the phase's own raw stop times
        // exactly 0.55 -- not the multiplier at all, since 0 * anything is
        // still 0 and the clamp is what supplies the 0.55.
        expect(g.colors[i].a, closeTo(dayFloor[i].a * 0.55, 0.001));
      }
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
      final LinearGradient g = hudVeil(
          HudTokens.dark, const HudSkySelection(phase: HudSkyPhase.dawn));
      expect(g.begin, Alignment.topCenter);
      expect(g.end, Alignment.bottomCenter);
      expect(g.stops, <double>[0.0, 0.58, 0.82, 1.0]);
    });

    test('a brighter picture gets more veil than a dimmer one, same phase', () {
      // R-D1-04: before this, every image assigned to a phase shared that
      // phase's flat alpha regardless of how bright it actually measures.
      // `userPhotoPath` here is a test device to decouple the image from the
      // phase -- both selections are nominally `day`, so the token lookup is
      // identical; only the per-image profile differs.
      const HudSkySelection dim = HudSkySelection(
        phase: HudSkyPhase.day,
        userPhotoPath: 'assets/coach_bg/02_volcano.webp', // p95 145.08
      );
      const HudSkySelection bright = HudSkySelection(
        phase: HudSkyPhase.day,
        userPhotoPath: 'assets/coach_bg/04_fuji_sakura.webp', // p95 242.26
      );
      final LinearGradient gDim = hudVeil(HudTokens.dark, dim);
      final LinearGradient gBright = hudVeil(HudTokens.dark, bright);
      expect(gBright.colors.first.a, greaterThan(gDim.colors.first.a));
    });

    test('an unrecognised image key gets the neutral, pre-fix veil', () {
      // `base` (no explicit image) is NOT itself a neutral comparison point
      // any more -- its phase resolves to a real cataloged asset
      // (`06_greek_terrace`) which now carries its own real, non-1.0
      // multiplier. The genuinely neutral case is compared against the raw
      // phase alpha directly, computed independently of `hudVeil` itself.
      const HudSkySelection unknown = HudSkySelection(
        phase: HudSkyPhase.day,
        userPhotoPath: '/data/user/0/some_picked_photo.jpg',
      );
      final LinearGradient g = hudVeil(HudTokens.dark, unknown);
      final List<Color> dayStops = HudTokens.dark.veilStops['day']!;
      for (int i = 0; i < g.colors.length; i++) {
        expect(g.colors[i].a, closeTo(dayStops[i].a, 0.001));
      }
    });
  });

  group('background readability profiles', () {
    test('multiplierForP95 is 1.0 at or below the measured baseline', () {
      expect(HudBackgroundProfile.multiplierForP95(140), 1.0);
      expect(HudBackgroundProfile.multiplierForP95(0), 1.0);
    });

    test('multiplierForP95 caps at the boost ceiling', () {
      expect(HudBackgroundProfile.multiplierForP95(250), closeTo(1.45, 0.001));
      expect(HudBackgroundProfile.multiplierForP95(999), closeTo(1.45, 0.001));
    });

    test('multiplierForP95 is monotonic between the bounds', () {
      double prev = 1.0;
      for (final double p95 in <double>[140, 170, 200, 230, 250]) {
        final double m = HudBackgroundProfile.multiplierForP95(p95);
        expect(m, greaterThanOrEqualTo(prev));
        prev = m;
      }
    });

    test('every bundled scene has a profile derived from its measured p95', () {
      for (final String path in HudSky.catalogue) {
        final HudBackgroundProfile? profile = HudSky.backgroundProfiles[path];
        expect(profile, isNotNull, reason: path);
        expect(
          profile!.recommendedVeilMultiplier,
          HudBackgroundProfile.multiplierForP95(profile.topZoneP95Luminance),
          reason: 'must be DERIVED from the raw measurement, not a second, '
              'independently hand-typed number that could drift from it',
        );
      }
    });

    test('the darkest and brightest measured scenes bound the multiplier', () {
      // Ground-truths this test file's own numbers against the catalogue:
      // if a future asset swap changes which scene is darkest/brightest,
      // this fails loudly rather than silently protecting a stale image.
      final Iterable<double> multipliers = HudSky.backgroundProfiles.values
          .map((p) => p.recommendedVeilMultiplier);
      expect(
          multipliers.reduce(math.min),
          HudSky.backgroundProfiles['assets/coach_bg/02_volcano.webp']!
              .recommendedVeilMultiplier);
      expect(
          multipliers.reduce(math.max),
          HudSky.backgroundProfiles['assets/coach_bg/04_fuji_sakura.webp']!
              .recommendedVeilMultiplier);
    });

    test('profileFor falls back to neutral for a key with no profile', () {
      final HudBackgroundProfile p =
          HudSky.profileFor('/data/user/0/picked.jpg');
      expect(p.recommendedVeilMultiplier, 1.0);
    });
  });

  group('worst-case veil contrast (WCAG)', () {
    // An accessibility review round confirmed the per-image multiplier
    // formula's "closes the contrast BLOCKER" claim was unevidenced -- the
    // formula's own bounds (baseline/ceiling/maxBoost) were justified by
    // reasoning, not by a computed contrast number anywhere in the repo, and
    // per-project instruction, WCAG compliance must not be claimed from
    // average luminance alone. This group computes the real thing, using the
    // same gamma-correct formula `app_semantic_colors_test.dart` already
    // maintains for the flat-colour token set (`test/support/wcag_contrast.dart`).
    //
    // Two backgrounds are checked, deliberately not one:
    //  - the theoretical pure-white (255) scene -- the SAME worst-case
    //    assumption the original accessibility review used, which is what
    //    actually separates "boost helps" from "boost doesn't matter": the
    //    dimmest phase (.44 base alpha) against pure white, at the OLD flat
    //    per-phase alpha with no per-image boost, computes to 4.18:1 -- a
    //    real, if narrow, AA failure. Independently reproduced here as the
    //    regression this whole gate exists to prevent (mutation-verified:
    //    forcing the multiplier to a no-op fails this exact test).
    //  - the brightest bundled asset's own measured p95 (242.26) -- proof
    //    the fix is not merely theoretical but covers a real shipped scene.
    //
    // The background's real per-pixel colour isn't retained past either
    // measurement -- only its Rec.709 luminance is. Standing in a neutral
    // grey of that same luminance is the standard simplification for this
    // kind of check and is not more forgiving than a real photograph would
    // be: the veil colour is near-black, so the blend is dominated by the
    // veil regardless of the image's own hue at equal luminance.
    const Color pureWhiteBg = Color(0xFFFFFFFF);
    const double brightestMeasuredP95 = 242.26; // 04_fuji_sakura.webp
    final Color brightestMeasuredBg = Color.fromARGB(
        255,
        brightestMeasuredP95.round(),
        brightestMeasuredP95.round(),
        brightestMeasuredP95.round());

    Color topStopOver(
      HudTokens tokens,
      HudSkyPhase phase,
      Color bg, {
      String? userPhotoPath,
    }) {
      final LinearGradient g = hudVeil(
        tokens,
        HudSkySelection(phase: phase, userPhotoPath: userPhotoPath),
      );
      return flatten(g.colors.first, bg);
    }

    test(
        'REGRESSION: the dimmest phase against a theoretical pure-white '
        'scene fails AA without the per-image boost, and passes with it',
        () {
      // Isolates the one variable R-D1-04 actually changed -- the scale
      // applied to the phase's own flat top stop -- from asset-catalogue
      // lookup, since no bundled scene measures a literal 255. `1.0` is
      // exactly what every phase's scale was before this gate (no image
      // multiplier existed); `multiplierForP95(255)` is what it is now for
      // a picked photo that bright. The dimmest phase (dawn/dusk, .44 base
      // alpha) is the case a review round confirmed as a real, if narrow,
      // AA failure under the pre-fix flat alpha.
      Color scaledTopStop(double scale) {
        final Color raw = HudTokens.dark.veilStops[HudSkyPhase.dawn.key]!.first;
        return raw.withValues(alpha: (raw.a * scale).clamp(0.0, 1.0));
      }

      final double noBoostRatio = contrast(HudTokens.dark.textPrimary,
          flatten(scaledTopStop(1.0), pureWhiteBg));
      expect(noBoostRatio, lessThan(4.5),
          reason: 'sanity check on the test itself: the pre-R-D1-04 flat '
              'alpha (no image boost) must actually fail AA here (computed '
              '$noBoostRatio), or this test is not exercising the '
              'regression it claims to');

      final double withBoostScale =
          HudBackgroundProfile.multiplierForP95(255).clamp(0.55, 1.6);
      final double withBoostRatio = contrast(HudTokens.dark.textPrimary,
          flatten(scaledTopStop(withBoostScale), pureWhiteBg));
      expect(withBoostRatio, greaterThanOrEqualTo(4.5),
          reason: 'primary text (contrast $withBoostRatio) must clear WCAG '
              'AA once the per-image profile for a photo this bright is '
              'applied (${withBoostScale.toStringAsFixed(2)}x scale, not '
              '1.0x)');
    });

    test(
        'primary text clears WCAG AA (4.5:1) over the brightest bundled '
        'scene, densest phase', () {
      // 'day' carries the highest base veil alpha (.56) of the six phases --
      // the phase where the veil itself is thinnest before the per-image
      // multiplier is what would fail first if anything does.
      final Color bg = topStopOver(
        HudTokens.dark,
        HudSkyPhase.day,
        brightestMeasuredBg,
        userPhotoPath: 'assets/coach_bg/04_fuji_sakura.webp',
      );
      final double ratio = contrast(HudTokens.dark.textPrimary, bg);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'primary status text over $bg (contrast $ratio) must clear '
              'WCAG AA for normal-size text');
    });

    test(
        'secondary text clears WCAG AA (4.5:1) over the brightest bundled '
        'scene, densest phase', () {
      // textSecondary is itself semi-transparent (white @ .80 on dark), so
      // the glyph it actually paints is its OWN blend onto the
      // already-veiled background, not the raw (still-translucent) token --
      // WCAG luminance is only meaningful for an opaque colour, and the
      // token's alpha has to be resolved before comparing it to anything.
      final Color veiledBg = topStopOver(
        HudTokens.dark,
        HudSkyPhase.day,
        brightestMeasuredBg,
        userPhotoPath: 'assets/coach_bg/04_fuji_sakura.webp',
      );
      final Color paintedGlyph = flatten(HudTokens.dark.textSecondary, veiledBg);
      final double ratio = contrast(paintedGlyph, veiledBg);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'secondary text ($paintedGlyph) over $veiledBg (contrast '
              '$ratio) must clear WCAG AA for normal-size text');
    });

    test(
        'the dimmest phase (dawn/dusk, .44 base alpha) clears WCAG AA over '
        'the brightest bundled scene', () {
      final Color bg = topStopOver(
        HudTokens.dark,
        HudSkyPhase.dawn,
        brightestMeasuredBg,
        userPhotoPath: 'assets/coach_bg/04_fuji_sakura.webp',
      );
      final double ratio = contrast(HudTokens.dark.textPrimary, bg);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'primary text over $bg (contrast $ratio) must clear WCAG '
              'AA for normal-size text');
    });
  });

  group('sampleBackgroundProfile — on-device, no network', () {
    // `sampleBackgroundProfile` itself is two steps: decode a `ui.Image` to
    // raw RGBA bytes, then run pure luminance math over those bytes. Step
    // one cannot be exercised in this suite -- `ui.instantiateImageCodec`
    // and even a trivial `ui.decodeImageFromPixels` both hang indefinitely
    // under `flutter test` on this host (confirmed with isolated diagnostic
    // scripts, stack trace bottoming out in `dart:isolate
    // _RawReceivePort._handleMessage`, well after the real function had
    // already returned and its image/codec had already been disposed) -- an
    // environment limitation, not a defect. It WAS cross-validated manually
    // against the real `04_fuji_sakura.webp` asset outside the suite: 108ms,
    // p95 242.265 against a Pillow-measured ground truth of 242.26. Recorded
    // in DECISION_LOG.md alongside this.
    //
    // Step two -- `profileFromRgbaBytes`, the actual luminance/percentile
    // math -- has no decode dependency and IS exercised here directly, with
    // synthetic buffers standing in for a decoded image.
    test('a uniform bright buffer measures its own known luminance', () {
      // Rec.709: 0.213*255 + 0.715*255 + 0.072*255 = 255 exactly (white).
      final Uint8List white = _solidRgba(width: 4, height: 4, r: 255, g: 255, b: 255);
      final HudBackgroundProfile p =
          profileFromRgbaBytes(white, width: 4, height: 4, stride: 1);
      expect(p.topZoneP95Luminance, closeTo(255, 0.01));
      expect(p.recommendedVeilMultiplier,
          HudBackgroundProfile.multiplierForP95(255));
    });

    test('the luminance weights are Rec.709, not an equal or Rec.601 mix', () {
      // A grey-looking (R=200,G=100,B=50) buffer pins the exact coefficients:
      // an equal-weight or Rec.601 (0.299/0.587/0.114) mix would both give a
      // measurably different number. White/black buffers can't tell these
      // apart -- every channel weighting agrees on the achromatic endpoints.
      final Uint8List mixed = _solidRgba(width: 4, height: 4, r: 200, g: 100, b: 50);
      final HudBackgroundProfile p =
          profileFromRgbaBytes(mixed, width: 4, height: 4, stride: 1);
      // 0.213*200 + 0.715*100 + 0.072*50 = 42.6 + 71.5 + 3.6 = 117.7
      expect(p.topZoneP95Luminance, closeTo(117.7, 0.01));
    });

    test('a uniform dark buffer measures its own known luminance', () {
      final Uint8List black = _solidRgba(width: 4, height: 4, r: 0, g: 0, b: 0);
      final HudBackgroundProfile p =
          profileFromRgbaBytes(black, width: 4, height: 4, stride: 1);
      expect(p.topZoneP95Luminance, closeTo(0, 0.01));
      expect(p.recommendedVeilMultiplier, 1.0);
    });

    test('only the top fraction is sampled, not the whole image', () {
      // Bright top half, black bottom half. A `topFraction` of 0.5 must read
      // the bright half's luminance, not an average that a whole-image scan
      // would produce.
      final Uint8List halfBright = _verticalSplitRgba(
        width: 4,
        height: 4,
        topRgb: (255, 255, 255),
        bottomRgb: (0, 0, 0),
      );
      final HudBackgroundProfile p = profileFromRgbaBytes(
        halfBright,
        width: 4,
        height: 4,
        topFraction: 0.5,
        stride: 1,
      );
      expect(p.topZoneP95Luminance, closeTo(255, 0.01));
    });

    test('an empty byte buffer returns the neutral profile, not a crash', () {
      final HudBackgroundProfile p =
          profileFromRgbaBytes(Uint8List(0), width: 4, height: 4);
      expect(p.recommendedVeilMultiplier, 1.0);
      expect(p, same(HudBackgroundProfile.neutral));
    });

    test('a zero width or height returns the neutral profile, not a crash',
        () {
      final Uint8List some = _solidRgba(width: 4, height: 4, r: 128, g: 128, b: 128);
      expect(profileFromRgbaBytes(some, width: 0, height: 4).recommendedVeilMultiplier, 1.0);
      expect(profileFromRgbaBytes(some, width: 4, height: 0).recommendedVeilMultiplier, 1.0);
    });

    test(
        'a buffer shorter than width*height*4 is read safely, not indexed '
        'out of range', () {
      // toByteData for a corrupted/mid-dispose image is not a contract this
      // function controls -- a short buffer must degrade gracefully rather
      // than throw a RangeError from inside a background paint.
      final Uint8List truncated = _solidRgba(width: 4, height: 4, r: 200, g: 200, b: 200)
          .sublist(0, 20);
      expect(
        () => profileFromRgbaBytes(truncated, width: 4, height: 4, stride: 1),
        returnsNormally,
      );
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

    testWidgets(
        'reverting to the settled picture mid-fade cancels the stale one',
        (t) async {
      // Two phase changes inside one 1.6s crossfade window: night -> day
      // starts a fade, and day -> night (back to what is already settled)
      // arrives before it finishes. `didUpdateWidget` used to compare only
      // against `_settled`, so a target equal to it was treated as "nothing
      // to do" even with an unrelated fade still in flight -- that stale fade
      // would still run to completion and silently re-settle on `day`, the
      // picture nobody wants anymore, with nothing left to correct it.
      Widget app(HudSkySelection s) => MaterialApp(
            home: HudSkyBackground(selection: s, child: const SizedBox()),
          );
      const HudSkySelection night = HudSkySelection(phase: HudSkyPhase.night);
      const HudSkySelection day = HudSkySelection(phase: HudSkyPhase.day);

      await t.pumpWidget(app(night));
      await t.pump();
      expect(find.byType(Image), findsOneWidget);

      await t.pumpWidget(app(day));
      await t.pump();
      expect(find.byType(Image), findsNWidgets(2),
          reason: 'day is fading in over the settled night');

      await t.pumpWidget(app(night));
      await t.pump();
      expect(find.byType(Image), findsOneWidget,
          reason: 'the stale fade toward day must be cancelled outright');

      // Let any in-flight animation/timer run to completion. If the stale
      // fade were still alive, its `onEnd` fires here and re-settles on day.
      await t.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('normally crossfades photo swaps over HudSky.crossfade',
        (t) async {
      await t.pumpWidget(const MaterialApp(
        home: HudSkyBackground(
          selection: HudSkySelection(phase: HudSkyPhase.night),
          child: SizedBox(),
        ),
      ));
      final AnimatedOpacity layer =
          t.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first);
      expect(layer.duration, HudSky.crossfade);
    });

    testWidgets('reduce motion collapses the photo crossfade to zero duration',
        (t) async {
      await t.pumpWidget(const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: HudSkyBackground(
            selection: HudSkySelection(phase: HudSkyPhase.night),
            child: SizedBox(),
          ),
        ),
      ));
      final AnimatedOpacity layer =
          t.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first);
      expect(layer.duration, Duration.zero);
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

/// A synthetic RGBA8888 buffer of one solid colour, standing in for a
/// decoded `ui.Image` in [profileFromRgbaBytes] tests.
Uint8List _solidRgba({
  required int width,
  required int height,
  required int r,
  required int g,
  required int b,
}) {
  final Uint8List bytes = Uint8List(width * height * 4);
  for (int i = 0; i < bytes.length; i += 4) {
    bytes[i] = r;
    bytes[i + 1] = g;
    bytes[i + 2] = b;
    bytes[i + 3] = 255;
  }
  return bytes;
}

/// A synthetic RGBA8888 buffer, bright in the top half and dark in the
/// bottom half, for testing that only [topFraction] is sampled.
Uint8List _verticalSplitRgba({
  required int width,
  required int height,
  required (int, int, int) topRgb,
  required (int, int, int) bottomRgb,
}) {
  final Uint8List bytes = Uint8List(width * height * 4);
  final int splitRow = height ~/ 2;
  for (int y = 0; y < height; y++) {
    final (int, int, int) rgb = y < splitRow ? topRgb : bottomRgb;
    for (int x = 0; x < width; x++) {
      final int i = (y * width + x) * 4;
      bytes[i] = rgb.$1;
      bytes[i + 1] = rgb.$2;
      bytes[i + 2] = rgb.$3;
      bytes[i + 3] = 255;
    }
  }
  return bytes;
}
