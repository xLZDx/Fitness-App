import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/visual_equipment/data/machine_text_anchor.dart';

/// A slice of the real catalogue. Passed in the same shape the production
/// call site passes it, so the fallback-by-display-name path is exercised
/// against real ids rather than invented ones.
const _catalogue = <String, String>{
  'treadmill': 'Treadmill',
  'rowing_machine': 'Rowing machine',
  'leg_press': 'Leg press',
  'pec_deck': 'Pec deck',
  'hip_abductor_adductor': 'Hip abductor / adductor',
  'ab_crunch_machine': 'Ab crunch machine',
  'lat_pulldown': 'Lat pulldown',
  'adjustable_bench': 'Adjustable bench',
  'cable_machine': 'Cable machine',
};

List<TextAnchorMatch> _all(String text) =>
    matchMachineText(text, catalogue: _catalogue);

/// The single answer, or null when the anchor returned nothing OR more than
/// one candidate. Ambiguity is not an answer, and a helper that hid it behind
/// `.first` would let every test below pass on a guess.
TextAnchorMatch? _m(String text) {
  final r = _all(text);
  return r.length == 1 ? r.single : null;
}

void main() {
  group('matchMachineText — strings actually printed on the operator\'s '
      'machines (photos 2026-07-30 / 2026-08-06)', () {
    // Each of these is transcribed from a frame in
    // D:\Downloads\Photos-1-001 (1). They are the reason this anchor exists:
    // the v2 classifier got 5 of these 18 frames; the text names them
    // outright.
    test('20260730_135634 — ABDUCTION / ADDUCTION', () {
      final r = _m('INSPIRATION\nABDUCTION / ADDUCTION\nNAUTILUS');
      expect(r?.equipmentId, 'hip_abductor_adductor');
    });

    test('20260730_135638 + _135643 — PEC FLY / REAR DELT', () {
      final r = _m('PEC FLY / REAR DELT\nINSPIRATION STRENGTH');
      expect(r?.equipmentId, 'pec_deck');
      // The longer phrase must win: 'pec fly' and 'rear delt' both map to
      // pec_deck here, but a future split would silently pick whichever
      // sorted first without the longest-first rule.
      expect(r?.matchedPhrase, 'pec fly rear delt');
    });

    test('20260730_141731/_141736/_141743 — ABDOMINAL', () {
      final r = _m('NAUTILUS\nINSPIRATION STRENGTH\nABDOMINAL');
      expect(r?.equipmentId, 'ab_crunch_machine');
    });

    test('20260730_135552 — Leg Curl', () {
      expect(_m('INSPIRATION Leg Curl')?.equipmentId, 'leg_curl');
      expect(_m('INSPIRATION Leg Extension')?.equipmentId, 'leg_extension');
    });

    test('20260806_140016 — ROW', () {
      // 'ROW' alone is deliberately NOT a phrase: too short and too common.
      // The placard on that machine reads 'SEATED ROW'.
      expect(_m('INSPIRATION\nSEATED ROW')?.equipmentId,
          'seated_row_machine');
    });

    test('20260806_140007 — SHOULDER PRESS', () {
      expect(_m('INSPIRATION STRENGTH SHOULDER PRESS')?.equipmentId,
          'shoulder_press_machine');
    });

    test('20260730_135318 — POWER CAGE', () {
      expect(_m('POWER CAGE')?.equipmentId, 'squat_rack');
    });
  });

  group('matchMachineText — a multi-exercise station is not any one of its '
      'exercises', () {
    // The defect this group exists for: longest-phrase-wins answered
    // `shoulder_press_machine` at 0.92 for the operator's cable station,
    // because "Shoulder Press" is one of the six exercises on its decal.
    test('20260730_134401 — Nautilus Instinct, six exercises on one decal',
        () {
      final r = _m('NAUTILUS INSTINCT\n'
          'Lunge  Pulldown  Shoulder Press  Biceps Curl  Torso Twist  '
          'Ab Crunch');
      expect(r?.equipmentId, 'cable_machine');
      expect(r!.confidence, lessThan(0.92),
          reason: 'inferred from the placard, not read off the shroud');
    });

    test('20260730_134404 — the other side names only two, so it refuses to '
        'pick one', () {
      // This side reads "Squat / Chest Press / Push Press / High Row / Push
      // Down / Hip Glute Press". Only two of those are machines the catalogue
      // knows, so the >=3 station rule does not fire — and the code used to
      // answer `chest_press_machine` at 0.92 for a cable station.
      //
      // Two candidates is the honest output. What must never happen is one
      // confident wrong one.
      final r = _all('NAUTILUS INSTINCT\n'
          'Squat  Chest Press  Push Press  High Row  Push Down  '
          'Hip Glute Press');
      expect(r, hasLength(2));
      expect(r.map((m) => m.equipmentId),
          containsAll(['chest_press_machine', 'seated_row_machine']));
      for (final m in r) {
        expect(m.confidence, lessThan(0.92));
      }
    });

    test('two phrases naming ONE machine is not ambiguity', () {
      // A dual-purpose single machine is the norm: both halves map to the same
      // id, so the count of DISTINCT ids stays at one and the answer stays
      // confident.
      expect(_m('PEC FLY / REAR DELT')?.equipmentId, 'pec_deck');
      expect(_m('ABDUCTION / ADDUCTION')?.equipmentId,
          'hip_abductor_adductor');
    });

    test('two DIFFERENT machines side by side come back as two candidates',
        () {
      // Photo 20260730_135552: the Leg Curl and the Leg Extension stand next
      // to each other and both placards are legible. Text alone genuinely
      // cannot say which one the photo is of.
      final r = _all('INSPIRATION LEG CURL   INSPIRATION LEG EXTENSION');
      expect(r, hasLength(2));
      expect(r.map((m) => m.equipmentId),
          containsAll(['leg_curl', 'leg_extension']));
      // _m returns null on ambiguity, which is what stops a caller treating
      // one of two as the answer.
      expect(_m('INSPIRATION LEG CURL   INSPIRATION LEG EXTENSION'), isNull);
    });
  });

  group('matchMachineText — refuses to answer', () {
    test('brand-only text anchors nothing', () {
      // Every Nautilus machine in the gym carries these words. If they could
      // anchor, every photo would resolve to whichever phrase sorted first.
      expect(_all('NAUTILUS'), isEmpty);
      expect(_all('INSPIRATION STRENGTH'), isEmpty);
      expect(_all('STAR TRAC'), isEmpty);
      expect(_m('NAUTILUS INSTINCT\nSTRENGTH SERIES'), isNull);
    });

    test('safety boilerplate anchors nothing', () {
      expect(_all('WARNING — READ INSTRUCTIONS BEFORE USE'), isEmpty);
      expect(_m('MAX CAPACITY 150 KG\nLOCK N LOAD TECHNOLOGY'), isNull);
    });

    test('empty and punctuation-only input', () {
      expect(_all(''), isEmpty);
      expect(_m('   \n\n  '), isNull);
      expect(_all('--- /// ***'), isEmpty);
      expect(_all('12345 67'), isEmpty);
    });

    test('a partial word does not match inside a longer one', () {
      // 'row' inside 'rowing', 'ab' inside 'abdominal'. Substring matching
      // on OCR output is how one stray word becomes a confident wrong
      // machine.
      expect(_m('ARROW')?.equipmentId, isNot('seated_row_machine'));
      expect(_m('CABLE')?.equipmentId, isNot('ab_crunch_machine'));
    });
  });

  group('matchMachineText — OCR reality', () {
    test('separators on a curved shroud do not break the match', () {
      // The same phrase as OCR variously returns it.
      for (final variant in [
        'ABDUCTION / ADDUCTION',
        'ABDUCTION/ADDUCTION',
        'ABDUCTION  ADDUCTION',
        'abduction\nadduction',
        'Abduction - Adduction',
      ]) {
        expect(_m(variant)?.equipmentId, 'hip_abductor_adductor',
            reason: 'failed on: $variant');
      }
    });

    test('the matched phrase is reported so the user can check it', () {
      final r = _m('NAUTILUS INSPIRATION\nLEG PRESS');
      expect(r?.equipmentId, 'leg_press');
      expect(r?.matchedPhrase, 'leg press');
    });

    test('confidence is high but never certain', () {
      final r = _m('LEG PRESS');
      expect(r!.confidence, greaterThan(0.85));
      expect(r.confidence, lessThan(1.0));
    });
  });

  group('matchMachineText — catalogue fallback', () {
    test('a machine named exactly as the catalogue names it still matches',
        () {
      // No row in the phrase table for this; the catalogue display name
      // carries it. This is what stops the phrase table having to be
      // exhaustive over 69 machines.
      final r = _m('ADJUSTABLE BENCH');
      expect(r?.equipmentId, 'adjustable_bench');
      expect(r!.confidence, lessThan(0.92));
    });

    test('single-word catalogue names are not used as fallback anchors', () {
      // 'Treadmill' is one word and IS in the phrase table on purpose. The
      // fallback path requires two words precisely so a lone common noun
      // cannot anchor by accident.
      final r = _m('TREADMILL');
      expect(r?.equipmentId, 'treadmill');
      expect(r!.confidence, 0.92, reason: 'came from the phrase table');
    });
  });

  group('normaliseText', () {
    test('collapses everything that is not a letter into single spaces', () {
      expect(normaliseText('PEC FLY / REAR DELT'), 'pec fly rear delt');
      expect(normaliseText('  Leg   Curl\n\n'), 'leg curl');
      expect(normaliseText('ABDUCTION/ADDUCTION'), 'abduction adduction');
      expect(normaliseText('123'), '');
    });
  });
}
