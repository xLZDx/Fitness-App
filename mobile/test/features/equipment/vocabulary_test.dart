import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/settings/state/settings_providers.dart';
import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/equipment/state/safety_coverage_providers.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';

/// The safety-tag vocabulary, held to one definition across two languages.
///
/// `InjuryRegion` is the source of truth and lives in Dart.
/// `scripts/catalog/injury_regions.json` is its projection, so the Python
/// catalog builder can validate a tagging batch without a Dart toolchain.
/// Two lists of the same thing in two places is precisely the shape that
/// silently unbound four Stripe price secrets earlier in this remediation —
/// so they are pinned to each other here rather than kept in step by care.
///
/// This is the S3a half of the tagging work. S3b writes the tags; this makes
/// "which tags are legal" answerable, mechanically, before a single row is
/// written.

const _vocabularyFile = '../scripts/catalog/injury_regions.json';

List<String> _fileTags() {
  final raw = jsonDecode(File(_vocabularyFile).readAsStringSync())
      as Map<String, dynamic>;
  return (raw['tags'] as List).cast<String>();
}

void main() {
  group('the vocabulary', () {
    test('the enum and the file say exactly the same thing', () {
      // Order included. It is not load-bearing for matching, but a diff that
      // reorders is a diff someone should look at, and a set comparison would
      // hide a swap.
      expect(
        _fileTags(),
        InjuryRegion.values.map((r) => r.tag).toList(),
        reason: 'scripts/catalog/injury_regions.json has drifted from '
            'InjuryRegion. Regenerate it from the enum — the enum is the '
            'source of truth, the file is the projection Python reads.',
      );
    });

    test('every tag is distinct', () {
      expect(_fileTags().toSet(), hasLength(_fileTags().length));
    });

    test('is not empty, so the checks below cannot pass vacuously', () {
      expect(_fileTags(), isNotEmpty);
    });
  });

  group('the shipped catalog', () {
    late List<ExerciseItem> catalog;

    setUpAll(() {
      final raw = File('assets/data/exercises_vendor.json').readAsStringSync();
      catalog = (jsonDecode(raw) as List)
          .map((e) => ExerciseItem.fromJson(e as Map<String, dynamic>))
          .toList();
    });

    test('carries no tag outside the vocabulary', () {
      // At 0 of 1,887 this passes trivially today, which is why the test below
      // exists. It starts doing real work with S3b's first batch, and that is
      // the moment a typo'd tag would otherwise ship: a tag that matches no
      // region screens nobody, and screens them silently.
      final legal = _fileTags().toSet();
      final offenders = <String>{};
      for (final e in catalog) {
        for (final tag in e.contraindications) {
          if (!legal.contains(tag)) offenders.add('${e.id}: $tag');
        }
      }
      expect(offenders, isEmpty,
          reason: 'these tags match no InjuryRegion, so they filter for '
              'nobody: ${offenders.take(10).join(", ")}');
    });

    test('the vocabulary check would actually catch one', () {
      // The check above is vacuous while coverage is 0, and a vacuous test
      // reads exactly like a passing one. This runs it against a row that is
      // deliberately wrong, so the assertion itself is under test rather than
      // the empty catalog.
      final legal = _fileTags().toSet();
      const typo = 'kneee';
      expect(legal.contains(typo), isFalse);
      expect(legal.contains('knee'), isTrue);
    });

    test('a tag is stored in the form the region emits', () {
      // "lower back" and "lower_back" are the same region to a human and
      // different strings to a Set. The region's own `tag` is the only form
      // that may be written, and S3b writes from this list.
      for (final region in InjuryRegion.values) {
        expect(region.tag, isNot(contains(' ')));
        expect(region.tag, region.tag.toLowerCase());
      }
    });
  });

  group('the claim gate', () {
    // What the vocabulary is FOR. `filteringCanFire` is global -- one tagged
    // exercise anywhere makes it true -- and that was correct while the answer
    // was zero for everyone. S3b tags in batches and cannot cover eight regions
    // at once, so the first batch of 50 knees would disarm the honesty banner
    // for a user whose only injury is a shoulder. That is the S0a claim again,
    // in its harder form: true for most users, so nobody re-checks it.
    const knee = CatalogSafetyCoverage(
      tagged: 50,
      total: 1887,
      byRegion: {InjuryRegion.knee: 50, InjuryRegion.shoulder: 0},
    );

    test('a covered region may be claimed', () {
      expect(knee.coversAllOf([InjuryRegion.knee]), isTrue);
    });

    test('an uncovered region may not', () {
      expect(knee.coversAllOf([InjuryRegion.shoulder]), isFalse);
    });

    test('one uncovered region among several sinks the claim', () {
      expect(knee.coversAllOf([InjuryRegion.knee, InjuryRegion.shoulder]),
          isFalse,
          reason: 'the claim is made about the whole list the user gave');
    });

    test('a region the map has never seen counts as uncovered', () {
      expect(knee.coversAllOf([InjuryRegion.ankle]), isFalse);
    });

    test('no regions is not a claim anyone can make', () {
      expect(knee.coversAllOf(const []), isFalse);
    });

    test('the global form still says the catalog can filter at all', () {
      // Kept, and still used as the fallback for a user whose injuries are
      // free text with no region yet -- which, until S1b runs, is all of them.
      expect(knee.filteringCanFire, isTrue);
      expect(const CatalogSafetyCoverage(tagged: 0, total: 1887).filteringCanFire,
          isFalse);
    });
  });

  group('the shipped disclosure', () {
    ProviderContainer container({UserProfile? profile}) {
      final repo = AssetEquipmentRepository()
        ..seedForTests(
          equipment: const [
            EquipmentItem(
              id: 'rack',
              name: 'Rack',
              manufacturer: 'Any',
              category: 'strength',
              description: 'd',
            ),
          ],
          exercises: const [
            ExerciseItem(
              id: 'squat',
              title: 'Squat',
              equipmentId: 'rack',
              muscles: ['quads'],
              difficulty: ExerciseDifficulty.beginner,
              durationMinutes: 10,
              summary: 's',
              steps: ['a'],
              videoUrl: 'https://example.test/s.mp4',
              contraindications: ['knee'],
            ),
          ],
        );
      final c = ProviderContainer(overrides: [
        effectiveLanguageCodeProvider.overrideWithValue('en'),
        equipmentRepositoryProvider.overrideWithValue(repo),
        screeningProfileProvider.overrideWith((ref) async => profile),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    UserProfile withInjury(InjuryRegion region) => UserProfile(
          uid: 'u1',
          health: HealthHistory(injuries: [
            Injury(bodyPart: region.tag, type: 'x', region: region),
          ]),
        );

    test('disarms for the region a batch actually covered', () async {
      final c = container(profile: withInjury(InjuryRegion.knee));
      await c.read(catalogSafetyCoverageProvider.future);
      await c.read(screeningProfileProvider.future);
      expect(c.read(injuryFilteringIsRealProvider), isTrue);
    });

    test('stays up for a region the batch did not cover', () async {
      // The whole point. One tagged knee must not tell a shoulder injury it
      // was screened for.
      final c = container(profile: withInjury(InjuryRegion.shoulder));
      await c.read(catalogSafetyCoverageProvider.future);
      await c.read(screeningProfileProvider.future);
      expect(c.read(injuryFilteringIsRealProvider), isFalse);
    });

    test('falls back to the global question for unmapped injuries', () async {
      // Until S1b runs, every stored injury is free text with no region, so
      // this is the path all existing users take. It is the old behaviour
      // exactly -- the change can stop the claim early, never start it early.
      final c = container(
        profile: const UserProfile(
          uid: 'u1',
          health: HealthHistory(
            injuries: [Injury(bodyPart: 'left knee', type: 'x')],
          ),
        ),
      );
      await c.read(catalogSafetyCoverageProvider.future);
      await c.read(screeningProfileProvider.future);
      expect(c.read(injuryFilteringIsRealProvider), isTrue);
    });

    test('no injuries at all falls back to the global form', () async {
      final c = container(profile: null);
      await c.read(catalogSafetyCoverageProvider.future);
      await c.read(screeningProfileProvider.future);
      expect(c.read(injuryFilteringIsRealProvider), isTrue);
    });

    test('claims nothing while the profile is still unknown', () async {
      // Not the same as "no profile". Sampling `.valueOrNull` collapses the
      // two, and the first version of this provider did -- a test caught it
      // telling a shoulder injury it had been screened, because the profile
      // had not resolved and the code fell back to the global answer.
      final c = container(profile: withInjury(InjuryRegion.shoulder));
      await c.read(catalogSafetyCoverageProvider.future);
      expect(c.read(injuryFilteringIsRealProvider), isFalse,
          reason: 'silence is recoverable; a false safety claim is not');
    });
  });
}
