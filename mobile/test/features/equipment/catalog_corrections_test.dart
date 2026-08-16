import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// C1 — the four cards whose text was wrong, and the claims that must not
/// come back.
///
/// The 2026-08-15 audit read every one of the 1,887 cards it flagged and found
/// five that are wrong rather than merely thin. One of them is not an exercise
/// at all and is withheld (`exercise_quarantine_test.dart`). These are the other
/// four, corrected in place by `tools/catalog/correct_exercise_text.py`.
///
/// Each assertion is written against the specific false claim rather than
/// against the corrected paragraph. Pinning the whole paragraph would fail on
/// any later rewording, which trains people to update the expected string
/// without reading it — and the string is the only thing under test. Pinning the
/// claim fails only when the claim comes back.
///
/// Every group carries a control, because "the sentence is absent" is also true
/// of an empty card, and an empty card is worse than a wrong one.
///
/// Both languages throughout. The Russian text is not a translation artifact
/// here: `ea_criss_cross_bow_tie_pose`'s Russian title described a completely
/// different exercise from its own Russian steps.

Map<String, Map<String, dynamic>> _en() {
  final rows = (jsonDecode(
              File('assets/data/exercises_vendor.json').readAsStringSync())
          as List)
      .cast<Map<String, dynamic>>();
  return {for (final r in rows) r['id'] as String: r};
}

Map<String, dynamic> _ru() =>
    (jsonDecode(File('assets/data/exercises_vendor.ru.json').readAsStringSync())
            as Map)
        .cast<String, dynamic>();

void main() {
  final en = _en();
  final ru = _ru();

  String enPurpose(String id) => en[id]!['purpose'] as String? ?? '';
  String ruPurpose(String id) =>
      (ru[id] as Map)['purpose'] as String? ?? '';

  group('cable wrist extension', () {
    const id = 'ea_cable_wrist_extension';

    /// Two defects in one sentence. "Keeping the extensors as strong as the
    /// flexors" asserts a parity that does not exist — the wrist flexors are
    /// substantially the stronger group in a normal forearm — and "is what
    /// protects the outer elbow from the ache" is an unhedged causal claim
    /// about a named body part, in an app whose own Terms say nothing in it is
    /// medical advice and whose library no physiotherapist has reviewed.
    test('no longer claims flexor/extensor parity', () {
      expect(enPurpose(id), isNot(contains('as strong as the flexors')));
      expect(ruPurpose(id), isNot(contains('такими же сильными')));
      expect(ruPurpose(id), isNot(contains('равные по силе')));
    });

    test('no longer promises protection from elbow pain', () {
      expect(enPurpose(id), isNot(contains('is what protects')));
      expect(ruPurpose(id), isNot(contains('это то, что защищает')));
    });

    test('CONTROL: it still says what the movement trains', () {
      expect(enPurpose(id), contains('forearm'));
      expect(ruPurpose(id), contains('предплечь'));
      expect(enPurpose(id).length, greaterThan(120));
      expect(ruPurpose(id).length, greaterThan(120));
    });
  });

  group('puppy pose', () {
    const id = 'ea_puppy_pose';

    /// Backwards, and in the direction that costs. Holding the hips over the
    /// knees while the chest sinks EXTENDS the lumbar spine — the lower back is
    /// not kept out of it, it arches. A reader with a sensitive lower back was
    /// being told the opposite of what the shape does to them.
    test('no longer says the lower back is uninvolved', () {
      expect(enPurpose(id), isNot(contains('lower back is not involved')));
      expect(ruPurpose(id), isNot(contains('поясница не вовлекается')));
      expect(ruPurpose(id), isNot(contains('поясница не участвует')));
    });

    test('CONTROL: it still says what the pose stretches', () {
      expect(enPurpose(id), contains('shoulders'));
      expect(ruPurpose(id), contains('плеч'));
    });
  });

  group('sissy squat', () {
    const id = 'ea_sissy_squat_bodyweight';

    /// "the knees need time to adapt to this position" tells every reader that
    /// their knee adapts if they are patient enough. Some do not, and a
    /// catalogue card is not in a position to know which kind the reader has.
    test('no longer implies every knee adapts', () {
      expect(enPurpose(id), isNot(contains('the knees need time to adapt')));
      expect(ruPurpose(id), isNot(contains('коленям нужно время')));
    });

    test('CONTROL: it still warns rather than going quiet', () {
      // The fix must not be "delete the caveat".
      expect(enPurpose(id).toLowerCase(), contains('not every knee'));
      expect(ruPurpose(id), contains('не каждое колено'));
    });
  });

  group('criss cross bow tie pose', () {
    const id = 'ea_criss_cross_bow_tie_pose';
    String ruTitle() => (ru[id] as Map)['title'] as String;

    /// The Russian title read "поза «бабочка» со скрещенными ногами" — with
    /// crossed LEGS, which is a seated hip opener. The exercise is a shoulder
    /// stretch with the arms crossed behind the back, and the card's own Russian
    /// steps say so. A Russian-speaking user searching for a hip stretch found
    /// this card; one looking for a shoulder stretch did not.
    test('the Russian title no longer describes crossed legs', () {
      expect(ruTitle(), isNot(contains('ногами')));
    });

    test('the Russian title names what the steps actually describe', () {
      expect(ruTitle(), contains('за спиной'));
      // The steps were always right; this pins the thing the title has to agree
      // with, so a future title change cannot drift away from it again.
      final steps = ((ru[id] as Map)['steps'] as List).cast<String>();
      expect(steps.join(' '), contains('за спину'));
    });

    test('CONTROL: the English title is untouched', () {
      expect(en[id]!['title'], 'Criss Cross Bow Tie Pose');
    });
  });
}
