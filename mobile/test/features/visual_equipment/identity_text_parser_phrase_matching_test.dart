import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/visual_equipment/data/identity_text_parser.dart';
import 'package:fitness_app/features/visual_equipment/data/machine_text_evidence.dart';
import 'package:fitness_app/features/visual_equipment/data/parsed_identity_text.dart';

/// Phrase matching is exercised through [parseIdentityText] on evidence with
/// no line geometry (`lines: []`), which takes the single-cluster path and
/// lets these tests stay focused on brand/product-line/type-hint matching
/// without also exercising the clustering/ownership machinery.
const _lexicon = IdentityLexicon(
  brandAliases: {'Star Trac', 'Nautilus', 'Life Fitness'},
  productLineAliases: {'Inspiration', '9NPL'},
  typeHintPhrases: {'leg press', 'treadmill'},
);

ParsedIdentityText _parse(String text) => parseIdentityText(
      MachineTextEvidence(fullText: text, lines: const []),
      lexicon: _lexicon,
    );

void main() {
  group('brand matching', () {
    test('matches a known brand phrase case-insensitively', () {
      final result = _parse('star trac LEG PRESS');
      expect(result.brandCandidates, contains('Star Trac'));
    });

    test('does not match a brand phrase not present in the text', () {
      final result = _parse('LEG PRESS MAX 200 KG');
      expect(result.brandCandidates, isEmpty);
    });

    test('matches a multi-word brand only as a whole phrase, not a fragment', () {
      final result = _parse('FITNESS EQUIPMENT CO');
      expect(result.brandCandidates, isEmpty);
    });
  });

  group('product-line matching', () {
    test('matches a known product-line phrase', () {
      final result = _parse('NAUTILUS INSPIRATION SERIES');
      expect(result.productLineCandidates, contains('Inspiration'));
    });

    test('a product-line alias that looks like a model code still matches as a phrase', () {
      final result = _parse('NAUTILUS 9NPL SERIES');
      expect(result.productLineCandidates, contains('9NPL'));
    });
  });

  group('type-hint matching', () {
    test('matches a known type-hint phrase', () {
      final result = _parse('STAR TRAC LEG PRESS UNIT');
      expect(result.typeHints, contains('leg press'));
    });

    test('matches a different type-hint phrase in the same text', () {
      final result = _parse('LIFE FITNESS TREADMILL T5');
      expect(result.typeHints, contains('treadmill'));
    });

    test('no type-hint phrase present yields an empty typeHints list', () {
      final result = _parse('RANDOM OCR NOISE TEXT');
      expect(result.typeHints, isEmpty);
    });
  });

  group('combined matching', () {
    test('brand, product line and type hint all match together', () {
      final result = _parse('STAR TRAC INSPIRATION LEG PRESS 9NPL');
      expect(result.brandCandidates, contains('Star Trac'));
      expect(result.productLineCandidates, contains('Inspiration'));
      expect(result.typeHints, contains('leg press'));
    });

    test('an empty lexicon never matches anything', () {
      final result = parseIdentityText(
        const MachineTextEvidence(
          fullText: 'STAR TRAC INSPIRATION LEG PRESS',
          lines: [],
        ),
        lexicon: const IdentityLexicon(),
      );
      expect(result.brandCandidates, isEmpty);
      expect(result.productLineCandidates, isEmpty);
      expect(result.typeHints, isEmpty);
    });
  });

  group('punctuation-separated OCR forms still match (normalizePhraseText)', () {
    test('a hyphen-joined brand still matches', () {
      final result = _parse('STAR-TRAC LEG PRESS UNIT');
      expect(result.brandCandidates, contains('Star Trac'));
    });

    test('a slash-joined brand still matches', () {
      final result = _parse('STAR/TRAC LEG PRESS UNIT');
      expect(result.brandCandidates, contains('Star Trac'));
    });

    test('a hyphen-joined type-hint phrase still matches', () {
      final result = _parse('STAR TRAC LEG-PRESS UNIT');
      expect(result.typeHints, contains('leg press'));
    });

    test('a comma-separated brand still matches', () {
      final result = _parse('NAUTILUS, INSPIRATION SERIES');
      expect(result.brandCandidates, contains('Nautilus'));
      expect(result.productLineCandidates, contains('Inspiration'));
    });

    test('normalizePhraseText collapses punctuation runs to single spaces', () {
      expect(normalizePhraseText('STAR-TRAC'), 'star trac');
      expect(normalizePhraseText('STAR/TRAC'), 'star trac');
      expect(normalizePhraseText('  Leg,  Press!! '), 'leg press');
      expect(normalizePhraseText('9NPL'), '9npl');
    });
  });

  group('Cyrillic (RU) alias support (normalizePhraseText, round-2 fix)', () {
    test('a real RU alias from equipment_aliases.json normalizes without degenerating to empty', () {
      expect(normalizePhraseText('беговая дорожка'), 'беговая дорожка');
      expect(normalizePhraseText('беговая дорожка'), isNotEmpty);
    });

    test('ё is folded to е, matching the EquipmentAliasIndex convention', () {
      expect(normalizePhraseText('тренажёр'), 'тренажер');
    });

    test('RU punctuation forms still collapse to single spaces', () {
      expect(normalizePhraseText('Гакк-Машина!'), 'гакк машина');
    });

    test('a RU type-hint phrase actually matches through parseIdentityText', () {
      const lexicon = IdentityLexicon(typeHintPhrases: {'беговая дорожка'});
      final result = parseIdentityText(
        const MachineTextEvidence(
          fullText: 'БЕГОВАЯ ДОРОЖКА T5',
          lines: [],
        ),
        lexicon: lexicon,
      );
      expect(result.typeHints, contains('беговая дорожка'));
    });

    test('a degenerate all-punctuation alias never matches everything', () {
      const lexicon = IdentityLexicon(brandAliases: {'---'});
      final result = parseIdentityText(
        const MachineTextEvidence(fullText: 'LEG PRESS MAX 200 KG', lines: []),
        lexicon: lexicon,
      );
      expect(result.brandCandidates, isEmpty);
    });
  });
}
