import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/data/exercise_filter.dart';
import 'package:fitness_app/features/equipment/state/safety_coverage_providers.dart';
import 'package:fitness_app/features/profile/data/injury_regions.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';

/// Injuries as a closed vocabulary instead of free text.
///
/// `bodyPart` was typed into one comma-and-colon-delimited field, so the same
/// knee arrived as "knee", "Knee (right)", "левое колено" and "kneee", and
/// `_injuryHits` compensated with symmetric substring matching. That is a
/// reasonable rule for free text and the wrong one for the tag vocabulary S3b
/// is about to write onto 1,887 exercises: it cannot say no.

ExerciseItem _ex(List<String> contraindications) => ExerciseItem(
      id: 'x',
      title: 'x',
      equipmentId: 'rack',
      muscles: const ['quads'],
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 10,
      summary: '',
      steps: const [],
      contraindications: contraindications,
    );

void main() {
  group('proposing a region', () {
    test('maps the obvious English words', () {
      expect(suggestRegion('knee'), InjuryRegion.knee);
      expect(suggestRegion('Shoulder'), InjuryRegion.shoulder);
      expect(suggestRegion('lower back'), InjuryRegion.lowerBack);
      expect(suggestRegion('ankle'), InjuryRegion.ankle);
    });

    test('maps Russian, because the app ships Russian', () {
      // Without this, a Russian user gets no proposal and every injury lands
      // in "needs a human" -- which would make `confirmed` meaningless: they
      // would be declining a match the app never offered.
      expect(suggestRegion('колено'), InjuryRegion.knee);
      expect(suggestRegion('поясница'), InjuryRegion.lowerBack);
      expect(suggestRegion('плечо'), InjuryRegion.shoulder);
    });

    test('reads a qualified body part by its tokens', () {
      expect(suggestRegion('Left knee'), InjuryRegion.knee);
      expect(suggestRegion('Knee (right)'), InjuryRegion.knee);
      expect(suggestRegion('левое колено'), InjuryRegion.knee);
    });

    test('returns null for a part that is none of the nine', () {
      // A real answer, not a failure. Forcing "rib" onto the nearest region
      // would be a safety claim about a body part the tag does not describe.
      expect(suggestRegion('rib'), isNull);
      expect(suggestRegion('jaw'), isNull);
      expect(suggestRegion(''), isNull);
    });

    test('does not match on a shared substring', () {
      // The failure mode of the matcher this replaces: "hip" inside "ship".
      expect(suggestRegion('ship'), isNull);
      expect(suggestRegion('kneecapitulate'), isNull);
    });
  });

  group('screening on a mapped region', () {
    const knee = Injury(
      bodyPart: 'Left knee',
      type: 'meniscus',
      region: InjuryRegion.knee,
    );

    test('matches the exact tag', () {
      expect(isContraindicated(_ex(['knee']), [knee]), isTrue);
    });

    test('does not match a different region', () {
      expect(isContraindicated(_ex(['shoulder']), [knee]), isFalse);
    });

    test('does not match a tag that merely contains it', () {
      // Exactness is the point of a closed vocabulary: the tags S3b writes are
      // drawn from InjuryRegion.tag, so a partial hit means the tag is wrong,
      // not that the match should be loosened.
      expect(isContraindicated(_ex(['ship']), [knee]), isFalse);
    });

    test('lower_back is the region tag, not "back"', () {
      const back = Injury(
        bodyPart: 'back',
        type: 'strain',
        region: InjuryRegion.lowerBack,
      );
      expect(isContraindicated(_ex(['lower_back']), [back]), isTrue);
      expect(isContraindicated(_ex(['lower back']), [back]), isTrue,
          reason: 'normalisation collapses the space, as it does everywhere');
    });
  });

  group('screening on legacy free text', () {
    // Every stored injury is free text until S1b migrates it, so the old
    // behaviour has to keep working for users who have not opened the new
    // screen.
    const legacy = Injury(bodyPart: 'knee', type: 'sprain');

    test('still matches by substring', () {
      expect(isContraindicated(_ex(['knee']), [legacy]), isTrue);
    });

    test('and still matches the loose way it always did', () {
      const backish = Injury(bodyPart: 'back', type: 'strain');
      expect(isContraindicated(_ex(['lower_back']), [backish]), isTrue);
    });
  });

  group('the note', () {
    test('is never matched, however well it would have matched', () {
      // The whole reason a separate field exists. Text the user wanted
      // recorded is not text the app may make a safety decision on.
      const injury = Injury(
        bodyPart: 'rib',
        type: 'bruise',
        note: 'knee also clicks sometimes',
        confirmed: true,
      );
      expect(isContraindicated(_ex(['knee']), [injury]), isFalse);
    });
  });

  group('needs a human', () {
    test('unmapped and undeclined is unresolved', () {
      const i = Injury(bodyPart: 'rib', type: 'bruise');
      expect(i.isResolved, isFalse);
      expect(unresolvedInjuries([i]), hasLength(1));
    });

    test('declining resolves it, permanently', () {
      // Without `confirmed`, an injury that structurally cannot map is
      // indistinguishable on every future load from one nobody has looked at,
      // so the app would ask about it forever.
      const i = Injury(bodyPart: 'rib', type: 'bruise', confirmed: true);
      expect(i.isResolved, isTrue);
      expect(unresolvedInjuries([i]), isEmpty);
    });

    test('mapping resolves it too', () {
      const i =
          Injury(bodyPart: 'knee', type: 'sprain', region: InjuryRegion.knee);
      expect(i.isResolved, isTrue);
    });
  });

  group('serialization', () {
    test('the old shape reads back without a version field', () {
      // Absence IS the discriminator, the same structural trick `completedAt`
      // already uses. A version number would have to have been written by a
      // migration that has not run, onto documents that already exist.
      final old = Injury.fromJson({'bodyPart': 'knee', 'type': 'sprain'});
      expect(old.region, isNull);
      expect(old.confirmed, isFalse);
      expect(old.bodyPart, 'knee');
    });

    test('the new shape round-trips', () {
      const i = Injury(
        bodyPart: 'Left knee',
        type: 'meniscus',
        region: InjuryRegion.knee,
        note: 'clicks',
        confirmed: false,
      );
      expect(Injury.fromJson(i.toJson()), i);
    });

    test('a declined injury round-trips its decision', () {
      const i = Injury(bodyPart: 'rib', type: 'bruise', confirmed: true);
      final back = Injury.fromJson(i.toJson());
      expect(back.confirmed, isTrue);
      expect(back.region, isNull);
    });

    test('the original words survive a mapping', () {
      // S1b migrates by ADDING region beside bodyPart, never replacing it, so
      // a mapping that turns out wrong can still be undone from what the user
      // actually typed.
      const i = Injury(
        bodyPart: 'левое колено',
        type: 'растяжение',
        region: InjuryRegion.knee,
      );
      expect(Injury.fromJson(i.toJson()).bodyPart, 'левое колено');
    });

    test('a malformed row degrades instead of throwing', () {
      // The repository used to cast e['bodyPart'] straight into a required
      // String, so a document missing the field threw on load rather than
      // degrading -- and the load path is the whole profile.
      final i = Injury.fromJson(const {'type': 'sprain'});
      expect(i.bodyPart, '');
    });

    test('an unknown region name is null, not a crash', () {
      final i = Injury.fromJson(const {
        'bodyPart': 'knee',
        'type': 'x',
        'region': 'elbowww',
      });
      expect(i.region, isNull);
      expect(i.isResolved, isFalse, reason: 'so the user is asked again');
    });
  });

  group('the ninth region, upper back', () {
    // Added for the redesign's body diagram, which offers upper back as its
    // own zone. Not merged into `neck`: an overhead press is a neck question,
    // a bent-over row is a thoracic one, and one tag cannot answer both.

    test('"upper back" is upper back, not lower back', () {
      // The trap this pins. "upper back" normalises to `upper_back`, whose
      // tokens are {upper, back} -- and `back` is a lowerBack synonym. Match
      // order is declaration order, so a `upperBack` entry declared after
      // `lowerBack` would lose every time and file it as lumbar. Reordering
      // the map turns this red.
      expect(suggestRegion('upper back'), InjuryRegion.upperBack);
      expect(suggestRegion('Upper Back'), InjuryRegion.upperBack);
      expect(suggestRegion('thoracic'), InjuryRegion.upperBack);
      expect(suggestRegion('traps'), InjuryRegion.upperBack);
    });

    test('and in Russian', () {
      expect(suggestRegion('верх спины'), InjuryRegion.upperBack);
      expect(suggestRegion('лопатка'), InjuryRegion.upperBack);
      expect(suggestRegion('трапеция'), InjuryRegion.upperBack);
    });

    test('bare "спина" still proposes lower back, deliberately', () {
      // Documented rather than fixed. The word is genuinely ambiguous now, and
      // moving it to upperBack would only move the wrong guess. The proposal
      // is shown for confirmation, and the body diagram replaces typing with
      // tapping -- which is what actually removes the ambiguity.
      expect(suggestRegion('спина'), InjuryRegion.lowerBack);
      expect(suggestRegion('back'), InjuryRegion.lowerBack);
    });

    test('screens on its own tag, and not on the lower back one', () {
      const upper = Injury(
        bodyPart: 'верх спины',
        type: 'strain',
        region: InjuryRegion.upperBack,
      );
      expect(isContraindicated(_ex(['upper_back']), [upper]), isTrue);
      expect(isContraindicated(_ex(['lower_back']), [upper]), isFalse,
          reason: 'the two regions are separate or there was no point adding '
              'the ninth');
    });

    test('ships with no tagged exercises, and the app says so', () {
      // The honest half of adding a region to a catalog that is already
      // tagged for the other eight. `coversAllOf` is what stops the app
      // claiming a screening it cannot perform, so a user who reports an upper
      // back keeps the disclosure until a tagging batch runs.
      const coverage = CatalogSafetyCoverage(
        tagged: 1435,
        total: 1887,
        byRegion: {InjuryRegion.knee: 362, InjuryRegion.upperBack: 0},
      );
      expect(coverage.filteringCanFire, isTrue,
          reason: 'the catalog as a whole is tagged');
      expect(coverage.coversAllOf([InjuryRegion.upperBack]), isFalse,
          reason: 'but not for this user');
      expect(coverage.coversAllOf([InjuryRegion.knee]), isTrue);
    });
  });

  group('the region tags', () {
    test('every region has a distinct tag', () {
      final tags = InjuryRegion.values.map((r) => r.tag).toList();
      expect(tags.toSet(), hasLength(InjuryRegion.values.length));
    });

    test('every tag is already in normalised form', () {
      // S3b writes these onto exercises verbatim. A tag that normalises to
      // something else would match nothing, silently.
      for (final r in InjuryRegion.values) {
        expect(normaliseInjuryText(r.tag), r.tag, reason: r.name);
      }
    });
  });
}
