import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/config/body_scan_flags.dart';

/// T01 (SCAN-40, client half): the three Body Scan / Nutrition Coach switches
/// default OFF, every flag is independent, and a test can drive both states
/// through [bodyScanFlagsProvider].
///
/// `bool.fromEnvironment` only works as a compile-time constant, so the three
/// defines are read here with their own literal names. If the production code
/// mapped a field to the wrong define (cloudPhotos <- FOOD_AI, say) a run with
/// `--dart-define=FOOD_AI=true` fails the "each flag reads its own define" test.
/// The default run proves OFF-by-default; the extra runs recorded in the change
/// record prove the mapping (see core/changes/2026-10-15-e0-tests.md).
void main() {
  const bool cloudDefine = bool.fromEnvironment('BODY_SCAN_CLOUD');
  const bool foodAiDefine = bool.fromEnvironment('FOOD_AI');
  const bool foodLookupDefine = bool.fromEnvironment('FOOD_LOOKUP');

  group('defaults', () {
    test('the const constructor with no arguments has every flag OFF', () {
      const flags = BodyScanFlags();
      expect(flags.cloudPhotos, isFalse);
      expect(flags.foodAi, isFalse);
      expect(flags.foodLookup, isFalse);
    });

    test('a build without any --dart-define is entirely OFF', () {
      // Skipped (vacuously true) only on the extra runs that define a flag; the
      // default run is the one that guards OFF-by-default.
      if (cloudDefine || foodAiDefine || foodLookupDefine) return;
      expect(BodyScanFlags.compileTime.cloudPhotos, isFalse);
      expect(BodyScanFlags.compileTime.foodAi, isFalse);
      expect(BodyScanFlags.compileTime.foodLookup, isFalse);
      expect(BodyScanFlags.compileTime, const BodyScanFlags());
    });

    test('each flag reads its own define and no other', () {
      expect(BodyScanFlags.compileTime.cloudPhotos, cloudDefine,
          reason: 'cloudPhotos <- BODY_SCAN_CLOUD');
      expect(BodyScanFlags.compileTime.foodAi, foodAiDefine,
          reason: 'foodAi <- FOOD_AI');
      expect(BodyScanFlags.compileTime.foodLookup, foodLookupDefine,
          reason: 'foodLookup <- FOOD_LOOKUP');
    });
  });

  group('copyWith', () {
    test('turning one flag on leaves the other two untouched', () {
      const off = BodyScanFlags();
      final cloud = off.copyWith(cloudPhotos: true);
      expect([cloud.cloudPhotos, cloud.foodAi, cloud.foodLookup],
          [true, false, false]);
      final ai = off.copyWith(foodAi: true);
      expect([ai.cloudPhotos, ai.foodAi, ai.foodLookup], [false, true, false]);
      final lookup = off.copyWith(foodLookup: true);
      expect([lookup.cloudPhotos, lookup.foodAi, lookup.foodLookup],
          [false, false, true]);
    });

    test('with no arguments it keeps every value, including ON ones', () {
      const all = BodyScanFlags(
          cloudPhotos: true, foodAi: true, foodLookup: true);
      expect(all.copyWith(), all);
    });

    test('an ON flag can be switched back OFF explicitly', () {
      const all = BodyScanFlags(
          cloudPhotos: true, foodAi: true, foodLookup: true);
      final back = all.copyWith(foodAi: false);
      expect([back.cloudPhotos, back.foodAi, back.foodLookup],
          [true, false, true]);
    });
  });

  group('value equality', () {
    test('equal values are == and share a hashCode', () {
      const a = BodyScanFlags(cloudPhotos: true, foodLookup: true);
      const b = BodyScanFlags(cloudPhotos: true, foodLookup: true);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a difference in ANY single field breaks equality', () {
      const base = BodyScanFlags();
      expect(base == const BodyScanFlags(cloudPhotos: true), isFalse);
      expect(base == const BodyScanFlags(foodAi: true), isFalse);
      expect(base == const BodyScanFlags(foodLookup: true), isFalse);
    });

    test('swapped flags are not equal (field order is not interchangeable)',
        () {
      expect(
          const BodyScanFlags(cloudPhotos: true) ==
              const BodyScanFlags(foodAi: true),
          isFalse);
      expect(
          const BodyScanFlags(foodAi: true) ==
              const BodyScanFlags(foodLookup: true),
          isFalse);
    });

    test('equality is false against a non-flags object', () {
      // ignore: unrelated_type_equality_checks
      expect(const BodyScanFlags() == Object(), isFalse);
    });

    test('toString names every flag with its value', () {
      expect(
        const BodyScanFlags(foodAi: true).toString(),
        'BodyScanFlags(cloudPhotos: false, foodAi: true, foodLookup: false)',
      );
    });
  });

  group('bodyScanFlagsProvider', () {
    test('defaults to the compile-time flags', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(bodyScanFlagsProvider), BodyScanFlags.compileTime);
    });

    test('can be overridden to drive the flag-on path', () {
      final c = ProviderContainer(overrides: [
        bodyScanFlagsProvider.overrideWithValue(const BodyScanFlags(
            cloudPhotos: true, foodAi: true, foodLookup: true)),
      ]);
      addTearDown(c.dispose);
      final flags = c.read(bodyScanFlagsProvider);
      expect(flags.cloudPhotos, isTrue);
      expect(flags.foodAi, isTrue);
      expect(flags.foodLookup, isTrue);
    });

    test('can be overridden to force the flag-off path', () {
      final c = ProviderContainer(overrides: [
        bodyScanFlagsProvider.overrideWithValue(const BodyScanFlags()),
      ]);
      addTearDown(c.dispose);
      expect(c.read(bodyScanFlagsProvider), const BodyScanFlags());
    });
  });
}
