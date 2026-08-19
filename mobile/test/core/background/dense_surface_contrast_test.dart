import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/background/hud_sky.dart';
import 'package:fitness_app/core/theme/hud_tokens.dart';

/// The readability contract for `HudPanel(dense: true)`.
///
/// These are not style assertions. A review of the shipped Workouts screen
/// measured body copy at 1.39:1 and its call-to-action at 2.51:1 against the
/// photograph -- both far under WCAG AA's 4.5:1 for body text -- while the
/// filter chips a few hundred pixels higher measured 6-7.75:1. This pins the
/// arithmetic that closes that gap, so a later token edit that quietly
/// re-opens it fails here instead of on a device.

double _srgbToLinear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

/// Relative luminance of an opaque colour, per WCAG 2.x.
double _luminance(Color c) =>
    0.2126 * _srgbToLinear(c.r) +
    0.7152 * _srgbToLinear(c.g) +
    0.0722 * _srgbToLinear(c.b);

double _contrast(double a, double b) {
  final double hi = math.max(a, b);
  final double lo = math.min(a, b);
  return (hi + 0.05) / (lo + 0.05);
}

/// `src` at [alpha] over `dst`, in linear light — what the compositor does.
double _over(double src, double dst, double alpha) =>
    alpha * src + (1 - alpha) * dst;

/// The weakest veil the dark theme can put over the content band: the lowest
/// phase alpha times the 0.74 dip at `veilPositions`' 82% stop. Everything
/// below assumes this worst case, so a pass here is a pass for every phase.
const double _weakestVeil = 0.44 * 0.74;
const double _veilInk = 0.0043; // #0A0C16 in linear light

/// The luminance a dense card actually presents, over a given picture.
double _denseComposite(double contentP95) {
  final double photo = _srgbToLinear(contentP95 / 255.0);
  final double veiled = _over(_veilInk, photo, _weakestVeil);
  final double alpha = HudBackgroundProfile.denseAlphaForP95(contentP95);
  return _over(_veilInk, veiled, alpha);
}

void main() {
  group('dense surface alpha', () {
    test('every bundled background clears AA for body copy, or is clamped '
        'to keep the photograph and says so', () {
      final HudTokens t = HudTokens.dark;
      // textSecondary is white @ .80 in the shared tiers; a dense card raises
      // the effective figure because the surface under it is darker, so the
      // check below composites the real token rather than assuming white.
      final double secAlpha = t.textSecondary.a;

      // The two brightest bundled scenes hit `maxDenseAlpha` by design. They
      // are named here rather than excluded silently: the cap is a deliberate
      // trade of contrast for the photograph, and if a future asset swap
      // changes which scenes hit it, this list is what fails.
      const Set<String> clampedByDesign = <String>{
        'assets/coach_bg/04_fuji_sakura.webp',
        'assets/coach_bg/09_forest_lake.webp',
      };

      for (final MapEntry<String, HudBackgroundProfile> e
          in HudSky.backgroundProfiles.entries) {
        final double composite = _denseComposite(e.value.contentZoneP95Luminance);
        final double secondary = _over(1.0, composite, secAlpha);
        final double titleRatio = _contrast(1.0, composite);
        final double bodyRatio = _contrast(secondary, composite);

        if (clampedByDesign.contains(e.key)) {
          expect(e.value.denseSurfaceAlpha, HudBackgroundProfile.maxDenseAlpha,
              reason: '${e.key} is documented as hitting the cap');
          // Still has to be a real improvement on the 1.39:1 that started this.
          expect(bodyRatio, greaterThan(3.5), reason: e.key);
        } else {
          expect(titleRatio, greaterThanOrEqualTo(4.5), reason: '${e.key} title');
          expect(bodyRatio, greaterThanOrEqualTo(4.5), reason: '${e.key} body');
        }
      }
    });

    test('a darker picture keeps more of its photograph than a bright one',
        () {
      final double dark = HudBackgroundProfile.denseAlphaForP95(150.65);
      final double bright = HudBackgroundProfile.denseAlphaForP95(242.84);
      expect(dark, lessThan(bright),
          reason: 'the whole point of measuring is that a dark scene should '
              'not pay the bright scene\'s scrim');
      // The darkest bundled scene sits above the floor rather than on it --
      // i.e. the clamp is not what is producing this number, the measurement
      // is. If a token change ever pushes every asset onto the floor, the
      // adaptation has silently stopped happening and this catches it.
      expect(dark, greaterThan(HudBackgroundProfile.minDenseAlpha));
      expect(dark, lessThan(0.40),
          reason: 'a dark scene should keep most of its photograph');
      expect(bright, HudBackgroundProfile.maxDenseAlpha);
    });

    test('an unmeasured picture gets the protective end, never the middle',
        () {
      // A user-chosen photo (D9) could be a white wall. Assuming otherwise is
      // how a dense card puts white text on white.
      expect(HudBackgroundProfile.neutral.denseSurfaceAlpha,
          HudBackgroundProfile.maxDenseAlpha);
      expect(HudSky.profileFor('/some/user/photo.jpg').denseSurfaceAlpha,
          HudBackgroundProfile.maxDenseAlpha);
    });

    test('stays inside its clamp for absurd inputs rather than throwing', () {
      expect(HudBackgroundProfile.denseAlphaForP95(0),
          HudBackgroundProfile.minDenseAlpha);
      expect(HudBackgroundProfile.denseAlphaForP95(255),
          HudBackgroundProfile.maxDenseAlpha);
    });
  });

  group('what the fix was measured against', () {
    test('the plain panel tier could not have carried this copy', () {
      // `panel.fill` is white at 1.4%. Over the brightest content band, that
      // leaves body text essentially on the bare photograph -- this is the
      // 1.39:1 the review found, reproduced as arithmetic so the reason the
      // dense tier exists cannot be lost.
      final HudTokens t = HudTokens.dark;
      final double photo = _srgbToLinear(242.84 / 255.0);
      final double veiled = _over(_veilInk, photo, _weakestVeil);
      final double onPanel = _over(_luminance(const Color(0xFFFFFFFF)), veiled,
          t.panel.fill.a);
      expect(_contrast(1.0, onPanel), lessThan(2.0),
          reason: 'a 1.4% white fill adds no separation over a bright photo');
    });
  });
}
