import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/visual_equipment/data/identity_text_parser.dart';
import 'package:fitness_app/features/visual_equipment/data/machine_text_evidence.dart';
import 'package:fitness_app/features/visual_equipment/data/parsed_identity_text.dart';

/// End-to-end [parseIdentityText] coverage for the six Story AC hard cases
/// from `SPTR_EQUIPMENT_RECOGNITION_V4_4_GATE_CONTRACTS_AND_AC_DOD_2026-08-22.md`
/// lines 586-624 (P2.G2), plus the GPT-PM ownership ruling this gate's plan
/// was built against.
MachineTextLine _line(String text, double left, double top, double width, double height) =>
    MachineTextLine(
      text: text,
      bounds: Rect.fromLTWH(left, top, width, height),
    );

const _lexicon = IdentityLexicon(
  brandAliases: {'Star Trac', 'Precor', 'Nautilus'},
  productLineAliases: {'Inspiration'},
  typeHintPhrases: {'leg press', 'treadmill'},
);

void main() {
  group('Story AC hard case 1: two machines in frame', () {
    test('the neighbour machine\'s model code never leaks into modelCodeCandidates', () {
      final primary = [
        _line('STAR TRAC', 0, 0, 220, 40),
        _line('LEG PRESS 9NPL', 0, 50, 220, 40),
      ];
      final neighbour = [
        _line('PRECOR EFX885', 0, 900, 150, 30),
      ];
      final result = parseIdentityText(
        MachineTextEvidence(
          fullText: '${primary.map((l) => l.text).join(' ')} '
              '${neighbour.map((l) => l.text).join(' ')}',
          lines: [...primary, ...neighbour],
        ),
        lexicon: _lexicon,
      );

      expect(result.modelCodeCandidates, ['9NPL']);
      expect(result.modelCodeCandidates, isNot(contains('EFX885')));
    });

    test('a confidently-secondary neighbour\'s brand and type never leak either', () {
      final primary = [
        _line('STAR TRAC', 0, 0, 220, 40),
        _line('LEG PRESS 9NPL', 0, 50, 220, 40),
      ];
      final neighbour = [
        _line('PRECOR TREADMILL', 0, 900, 150, 30),
      ];
      final result = parseIdentityText(
        MachineTextEvidence(
          fullText: '${primary.map((l) => l.text).join(' ')} '
              '${neighbour.map((l) => l.text).join(' ')}',
          lines: [...primary, ...neighbour],
        ),
        lexicon: _lexicon,
      );

      expect(result.brandCandidates, ['Star Trac']);
      expect(result.brandCandidates, isNot(contains('Precor')));
      expect(result.typeHints, contains('leg press'));
      expect(result.typeHints, isNot(contains('treadmill')));
    });
  });

  group('Story AC hard case 2: neighbour placard suppression with no primary code', () {
    test('a neighbour\'s code is suppressed even when the primary has none of its own', () {
      final primary = [
        _line('STAR TRAC', 0, 0, 220, 40),
        _line('LEG PRESS', 0, 50, 220, 40),
      ];
      final neighbour = [
        _line('PRECOR EFX885', 0, 900, 150, 30),
      ];
      final result = parseIdentityText(
        MachineTextEvidence(
          fullText: '${primary.map((l) => l.text).join(' ')} '
              '${neighbour.map((l) => l.text).join(' ')}',
          lines: [...primary, ...neighbour],
        ),
        lexicon: _lexicon,
      );

      expect(result.modelCodeCandidates, isEmpty);
      expect(result.typeHints, contains('leg press'));
    });

    test('the neighbour\'s brand is also suppressed, not just its model code', () {
      final primary = [
        _line('STAR TRAC', 0, 0, 220, 40),
        _line('LEG PRESS', 0, 50, 220, 40),
      ];
      final neighbour = [
        _line('PRECOR EFX885', 0, 900, 150, 30),
      ];
      final result = parseIdentityText(
        MachineTextEvidence(
          fullText: '${primary.map((l) => l.text).join(' ')} '
              '${neighbour.map((l) => l.text).join(' ')}',
          lines: [...primary, ...neighbour],
        ),
        lexicon: _lexicon,
      );

      expect(result.brandCandidates, ['Star Trac']);
      expect(result.brandCandidates, isNot(contains('Precor')));
    });
  });

  group('Story AC hard case 3: two model codes on the same placard', () {
    test('both codes are kept and a conflict is recorded', () {
      final result = parseIdentityText(
        const MachineTextEvidence(
          fullText: 'MODEL 9NPL / 8TRX MISMATCH PLATE',
          lines: [],
        ),
        lexicon: _lexicon,
      );

      expect(result.modelCodeCandidates, containsAll(['9NPL', '8TRX']));
      expect(result.conflicts, isNotEmpty);
    });

    test('an OCR digit/letter confusion pair is NOT reported as a conflict', () {
      final result = parseIdentityText(
        const MachineTextEvidence(
          fullText: 'MODEL 9NP1 9NPI DUPLICATE READ',
          lines: [],
        ),
        lexicon: _lexicon,
      );

      expect(result.conflicts, isEmpty);
    });
  });

  group('Story AC hard case 4: OCR noise', () {
    test('garbled non-lexicon, non-code-shaped noise yields no candidates and no crash', () {
      final result = parseIdentityText(
        const MachineTextEvidence(
          fullText: 'QWERTY ZXCVB ASDFG MMMMM',
          lines: [],
        ),
        lexicon: _lexicon,
      );

      expect(result.brandCandidates, isEmpty);
      expect(result.productLineCandidates, isEmpty);
      expect(result.typeHints, isEmpty);
      expect(result.modelCodeCandidates, isEmpty);
      expect(result.conflicts, isEmpty);
    });

    test('noise around a real brand does not suppress the real match', () {
      final result = parseIdentityText(
        const MachineTextEvidence(
          fullText: 'ZZXV NAUTILUS QPQP TREADMILL WWWW',
          lines: [],
        ),
        lexicon: _lexicon,
      );

      expect(result.brandCandidates, contains('Nautilus'));
      expect(result.typeHints, contains('treadmill'));
    });
  });

  group('Story AC hard case 5: brand-only text, no model code', () {
    test('a brand-only read has brandCandidates but an empty modelCodeCandidates', () {
      final result = parseIdentityText(
        const MachineTextEvidence(fullText: 'NAUTILUS', lines: []),
        lexicon: _lexicon,
      );

      expect(result.brandCandidates, contains('Nautilus'));
      expect(result.modelCodeCandidates, isEmpty);
      expect(result.isEmpty, isFalse);
    });
  });

  group('Story AC hard case 6 / OP-01: OCR succeeds but finds zero readable text', () {
    test('empty fullText and no lines is an ordinary successful empty result', () {
      final result = parseIdentityText(
        const MachineTextEvidence(fullText: '', lines: []),
        lexicon: _lexicon,
      );

      expect(result.isEmpty, isTrue);
      expect(result, equals(const ParsedIdentityText()));
    });

    test('whitespace-only fullText is the same empty result', () {
      final result = parseIdentityText(
        const MachineTextEvidence(fullText: '   ', lines: []),
        lexicon: _lexicon,
      );

      expect(result.isEmpty, isTrue);
    });

    test(
        'zero-readable-text and brand-only-with-no-model share the same '
        'no-model subshape, differing only in brandCandidates', () {
      final zeroText = parseIdentityText(
        const MachineTextEvidence(fullText: '', lines: []),
        lexicon: _lexicon,
      );
      final brandOnly = parseIdentityText(
        const MachineTextEvidence(fullText: 'NAUTILUS', lines: []),
        lexicon: _lexicon,
      );

      expect(zeroText.productLineCandidates, brandOnly.productLineCandidates);
      expect(zeroText.modelCodeCandidates, brandOnly.modelCodeCandidates);
      expect(zeroText.typeHints, brandOnly.typeHints);
      expect(zeroText.conflicts, brandOnly.conflicts);
      expect(zeroText.brandCandidates, isNot(equals(brandOnly.brandCandidates)));
    });
  });

  group('ambiguous ownership (near-tied clusters)', () {
    test('both codes are preserved and a conflict names the ambiguity', () {
      final clusterA = [_line('9NPL', 0, 0, 200, 40)];
      final clusterB = [_line('8TRX', 0, 400, 175, 40)];
      final result = parseIdentityText(
        MachineTextEvidence(
          fullText: '9NPL 8TRX',
          lines: [...clusterA, ...clusterB],
        ),
        lexicon: _lexicon,
      );

      expect(result.modelCodeCandidates, containsAll(['9NPL', '8TRX']));
      expect(
        result.conflicts.any((c) => c.contains('ambiguous placard ownership')),
        isTrue,
      );
    });

    test('an OCR digit/letter confusion pair across near-tied clusters is NOT a conflict', () {
      final clusterA = [_line('9NP1', 0, 0, 200, 40)];
      final clusterB = [_line('9NPI', 0, 400, 175, 40)];
      final result = parseIdentityText(
        MachineTextEvidence(
          fullText: '9NP1 9NPI',
          lines: [...clusterA, ...clusterB],
        ),
        lexicon: _lexicon,
      );

      expect(result.conflicts, isEmpty);
    });
  });

  group('deterministic output regardless of lexicon Set insertion order', () {
    test('two lexicons with reversed insertion order produce an equal result', () {
      const forward = IdentityLexicon(
        brandAliases: {'Nautilus', 'Precor', 'Star Trac'},
        productLineAliases: {'9NPL', 'Inspiration'},
        typeHintPhrases: {'leg press', 'treadmill'},
      );
      const reversed = IdentityLexicon(
        brandAliases: {'Star Trac', 'Precor', 'Nautilus'},
        productLineAliases: {'Inspiration', '9NPL'},
        typeHintPhrases: {'treadmill', 'leg press'},
      );
      const evidence = MachineTextEvidence(
        fullText: 'STAR TRAC NAUTILUS PRECOR INSPIRATION 9NPL LEG PRESS TREADMILL',
        lines: [],
      );

      final resultForward = parseIdentityText(evidence, lexicon: forward);
      final resultReversed = parseIdentityText(evidence, lexicon: reversed);

      expect(resultForward, equals(resultReversed));
      expect(resultForward.brandCandidates, ['Nautilus', 'Precor', 'Star Trac']);
    });
  });
}
