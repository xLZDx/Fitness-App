import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/onboarding/data/step_answered.dart';
import 'package:fitness_app/features/onboarding/widgets/body_zone_map.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';

/// O6 — the body screen.
///
/// Two things here can be wrong without looking wrong, and both are asserted
/// directly: where a tap on the drawing lands, and whether the two vocabularies
/// (avoid vs prioritise) stay apart.
void main() {
  group('the drawing answers the question that was tapped', () {
    // Rendered at a deliberately odd size: the answer must come from the design
    // box, not from whatever pixels the phone happened to give the widget.
    const rendered = Size(190, 418);

    Offset centreOf(InjuryRegion region, {int shape = 0}) {
      final r = kBodyZoneRects[region]![shape];
      return Offset(
        r.center.dx * rendered.width / kBodyMapDesignSize.width,
        r.center.dy * rendered.height / kBodyMapDesignSize.height,
      );
    }

    test('every region is reachable by a tap at its own centre', () {
      for (final region in kBodyZoneRects.keys) {
        expect(bodyZoneAt(centreOf(region), rendered), region,
            reason: '$region could not be selected by tapping it');
      }
    });

    test('the paired regions are reachable from either side', () {
      // Shoulders, elbows, wrists, knees and ankles are drawn twice. A hit test
      // that only ever finds the left one is invisible in a screenshot.
      for (final region in kBodyZoneRects.entries.where((e) => e.value.length > 1)) {
        expect(bodyZoneAt(centreOf(region.key, shape: 1), rendered), region.key);
      }
    });

    test('no two regions share pixels', () {
      // Overlapping zones would make a tap answer whichever happened to be
      // first in the map — a silent wrong answer to a safety question.
      final rects = [
        for (final entry in kBodyZoneRects.entries)
          for (final r in entry.value) MapEntry(entry.key, r),
      ];
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].value.overlaps(rects[j].value), isFalse,
              reason: '${rects[i].key} overlaps ${rects[j].key}');
        }
      }
    });

    test('a tap on empty canvas selects nothing rather than the nearest zone', () {
      expect(bodyZoneAt(const Offset(2, 2), rendered), isNull);
    });

    test('a zero-sized widget cannot divide by zero', () {
      expect(bodyZoneAt(Offset.zero, Size.zero), isNull);
    });

    test('every screenable region has a place on the figure', () {
      // A region missing from the map is one the user cannot report at all.
      expect(kBodyZoneRects.keys.toSet(), InjuryRegion.values.toSet());
    });
  });

  // B1. The priorities tab used to be chips only, while limitations got the
  // figure. Same drawing, second zone map — so the same three faults that can
  // hide in geometry are asserted again rather than assumed to be impossible.
  group('the priorities figure', () {
    const rendered = Size(190, 418);

    Offset centreOf(FocusZone zone, {int shape = 0}) {
      final r = kFocusZoneRects[zone]![shape];
      return Offset(
        r.center.dx * rendered.width / kBodyMapDesignSize.width,
        r.center.dy * rendered.height / kBodyMapDesignSize.height,
      );
    }

    test('every drawn zone is reachable by a tap at its own centre', () {
      for (final zone in kFocusZoneRects.keys) {
        expect(zoneAt(centreOf(zone), rendered, kFocusZoneRects), zone,
            reason: '$zone could not be selected by tapping it');
      }
    });

    test('the paired zones are reachable from either side', () {
      for (final e in kFocusZoneRects.entries.where((e) => e.value.length > 1)) {
        expect(zoneAt(centreOf(e.key, shape: 1), rendered, kFocusZoneRects),
            e.key);
      }
    });

    test('no two zones share pixels', () {
      final rects = [
        for (final entry in kFocusZoneRects.entries)
          for (final r in entry.value) MapEntry(entry.key, r),
      ];
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].value.overlaps(rects[j].value), isFalse,
              reason: '${rects[i].key} overlaps ${rects[j].key}');
        }
      }
    });

    test('fullBody is the only zone without a place on the figure', () {
      // "Everything" is not a location. Any OTHER zone missing here would be
      // one the drawing silently cannot offer, which is a real gap.
      expect(
        FocusZone.values.toSet().difference(kFocusZoneRects.keys.toSet()),
        {FocusZone.fullBody},
      );
    });

    test('the two figures answer with their own vocabulary, not each other\'s',
        () {
      // Both maps live in the same design box. A tap that lands on "knee" in
      // one must not be able to return a FocusZone in the other -- the generic
      // hit test takes the map it is given and nothing else.
      final onLegs = centreOf(FocusZone.legs);
      expect(zoneAt(onLegs, rendered, kFocusZoneRects), FocusZone.legs);
      expect(zoneAt(onLegs, rendered, kBodyZoneRects), isNot(FocusZone.legs));
    });
  });

  group('avoid and prioritise stay separate vocabularies', () {
    test('a focus zone is not an injury region and vice versa', () {
      // The reason the enums were not merged: neither list is a subset of the
      // other, so one enum would offer "train your wrist" and "protect your
      // full body".
      final focus = FocusZone.values.map((z) => z.name).toSet();
      final injury = InjuryRegion.values.map((r) => r.name).toSet();
      expect(focus.contains('wrist'), isFalse);
      expect(focus.contains('ankle'), isFalse);
      expect(injury.contains('core'), isFalse);
      expect(injury.contains('fullBody'), isFalse);
    });

    test('focus zones round-trip through serialisation', () {
      const profile = UserProfile(
        uid: 'u',
        goals: FitnessGoals(focusZones: [FocusZone.core, FocusZone.legs]),
      );
      final json = profile.toJson()['goals'] as Map<String, dynamic>;
      expect(json['focusZones'], ['core', 'legs']);
    });
  });

  group('isOnboardingStepAnswered after O6', () {
    test('a priority alone marks the body step touched', () {
      const p = UserProfile(
        uid: 'u',
        goals: FitnessGoals(focusZones: [FocusZone.glutes]),
      );
      expect(isOnboardingStepAnswered(OnboardingStep.body, p), isTrue);
    });

    test('a priority does NOT mark the goal-and-level step touched', () {
      // Both live on `FitnessGoals`, and `hasAny` counts them together. If this
      // step reused it, answering the body screen would silently mark the first
      // screen done and a returning user would never be shown it.
      const p = UserProfile(
        uid: 'u',
        goals: FitnessGoals(focusZones: [FocusZone.glutes]),
      );
      expect(isOnboardingStepAnswered(OnboardingStep.goalAndLevel, p), isFalse);
    });

    test('a real goal still marks the goal step touched', () {
      const p = UserProfile(uid: 'u', goals: FitnessGoals(strength: true));
      expect(isOnboardingStepAnswered(OnboardingStep.goalAndLevel, p), isTrue);
    });

    test('the body step replaced health in the flow, it was not added beside it',
        () {
      expect(kOnboardingOrder.contains(OnboardingStep.body), isTrue);
      expect(kOnboardingOrder.toSet().length, kOnboardingOrder.length,
          reason: 'a duplicated step would show the same screen twice');
    });
  });
}
