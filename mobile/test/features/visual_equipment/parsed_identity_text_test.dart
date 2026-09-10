import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/visual_equipment/data/parsed_identity_text.dart';

void main() {
  group('ParsedIdentityText construction', () {
    test('defaults to all-empty lists', () {
      const evidence = ParsedIdentityText();

      expect(evidence.brandCandidates, isEmpty);
      expect(evidence.productLineCandidates, isEmpty);
      expect(evidence.modelCodeCandidates, isEmpty);
      expect(evidence.typeHints, isEmpty);
      expect(evidence.conflicts, isEmpty);
    });

    test('holds every field exactly as constructed', () {
      const evidence = ParsedIdentityText(
        brandCandidates: ['Star Trac'],
        productLineCandidates: ['Inspiration'],
        modelCodeCandidates: ['9NPL', '8TRx'],
        typeHints: ['leg press'],
        conflicts: ['9NPL vs 8TRx'],
      );

      expect(evidence.brandCandidates, ['Star Trac']);
      expect(evidence.productLineCandidates, ['Inspiration']);
      expect(evidence.modelCodeCandidates, ['9NPL', '8TRx']);
      expect(evidence.typeHints, ['leg press']);
      expect(evidence.conflicts, ['9NPL vs 8TRx']);
    });
  });

  group('ParsedIdentityText.isEmpty', () {
    test('true when every field is empty', () {
      expect(const ParsedIdentityText().isEmpty, isTrue);
    });

    test('false when any single field is non-empty', () {
      expect(const ParsedIdentityText(brandCandidates: ['Nautilus']).isEmpty,
          isFalse);
      expect(const ParsedIdentityText(modelCodeCandidates: ['9NPL']).isEmpty,
          isFalse);
      expect(const ParsedIdentityText(conflicts: ['x vs y']).isEmpty, isFalse);
    });
  });

  group('ParsedIdentityText equality', () {
    test('two identical instances are equal', () {
      const a = ParsedIdentityText(
        brandCandidates: ['Nautilus'],
        modelCodeCandidates: ['9NPL'],
      );
      const b = ParsedIdentityText(
        brandCandidates: ['Nautilus'],
        modelCodeCandidates: ['9NPL'],
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('a different brandCandidates makes two instances unequal', () {
      const a = ParsedIdentityText(brandCandidates: ['Nautilus']);
      const b = ParsedIdentityText(brandCandidates: ['Precor']);

      expect(a, isNot(equals(b)));
    });

    test('a different conflicts list makes two instances unequal', () {
      const a = ParsedIdentityText(conflicts: ['a vs b']);
      const b = ParsedIdentityText(conflicts: []);

      expect(a, isNot(equals(b)));
    });

    test('field order within a list matters', () {
      const a = ParsedIdentityText(modelCodeCandidates: ['A', 'B']);
      const b = ParsedIdentityText(modelCodeCandidates: ['B', 'A']);

      expect(a, isNot(equals(b)));
    });
  });

  group('IdentityLexicon construction', () {
    test('defaults to all-empty sets', () {
      const lexicon = IdentityLexicon();

      expect(lexicon.brandAliases, isEmpty);
      expect(lexicon.productLineAliases, isEmpty);
      expect(lexicon.typeHintPhrases, isEmpty);
    });

    test('holds every field exactly as constructed', () {
      const lexicon = IdentityLexicon(
        brandAliases: {'Star Trac', 'Nautilus'},
        productLineAliases: {'Inspiration'},
        typeHintPhrases: {'leg press', 'treadmill'},
      );

      expect(lexicon.brandAliases, {'Star Trac', 'Nautilus'});
      expect(lexicon.productLineAliases, {'Inspiration'});
      expect(lexicon.typeHintPhrases, {'leg press', 'treadmill'});
    });
  });
}
