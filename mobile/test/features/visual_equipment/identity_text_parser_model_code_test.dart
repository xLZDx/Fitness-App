import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/visual_equipment/data/identity_text_parser.dart';

void main() {
  group('tokenize', () {
    test('splits on whitespace and drops empty fragments', () {
      expect(tokenize('LEG   PRESS\tMAX 200 KG'),
          ['LEG', 'PRESS', 'MAX', '200', 'KG']);
    });

    test('keeps a hyphenated/slashed token intact', () {
      expect(tokenize('MODEL SKU-4521 GX/40'), ['MODEL', 'SKU-4521', 'GX/40']);
    });

    test('empty string tokenizes to no tokens', () {
      expect(tokenize(''), isEmpty);
      expect(tokenize('   '), isEmpty);
    });
  });

  group('stripPunctuation', () {
    test('strips leading/trailing punctuation only', () {
      expect(stripPunctuation('LEG,'), 'LEG');
      expect(stripPunctuation('"9NPL."'), '9NPL');
      expect(stripPunctuation('-8TRx-'), '8TRx');
    });

    test('preserves an internal delimiter', () {
      expect(stripPunctuation('SKU-4521,'), 'SKU-4521');
      expect(stripPunctuation('(GX/40)'), 'GX/40');
    });
  });

  group('looksLikeModelCode: positive fixtures', () {
    test('short mixed alpha+digit token needs no delimiter', () {
      final tokens = ['LEG', 'PRESS', '8TRx'];
      expect(looksLikeModelCode(tokens, 2), isTrue);
    });

    test('another short mixed alpha+digit token', () {
      final tokens = ['STAR', 'TRAC', '9NPL'];
      expect(looksLikeModelCode(tokens, 2), isTrue);
    });

    test('longer mixed alpha+digit token within length 10', () {
      final tokens = ['MODEL', 'EFX885'];
      expect(looksLikeModelCode(tokens, 1), isTrue);
    });

    test('pure-numeric token with a hyphen delimiter qualifies', () {
      final tokens = ['RANGE', '40-100'];
      expect(looksLikeModelCode(tokens, 1), isTrue);
    });

    test('pure-numeric token preceded by MODEL context word qualifies', () {
      final tokens = ['MODEL', '200'];
      expect(looksLikeModelCode(tokens, 1), isTrue);
    });

    test('pure-numeric token followed by SKU context word qualifies', () {
      final tokens = ['200', 'SKU'];
      expect(looksLikeModelCode(tokens, 0), isTrue);
    });

    test('mixed token with an internal slash delimiter qualifies', () {
      final tokens = ['GX/40'];
      expect(looksLikeModelCode(tokens, 0), isTrue);
    });
  });

  group('looksLikeModelCode: negative fixtures', () {
    test('bare pure-numeric token with no context is not a model code', () {
      final tokens = ['REST', '90', 'SECONDS'];
      expect(looksLikeModelCode(tokens, 1), isFalse);
    });

    test('a number immediately followed by a unit word is a measurement', () {
      final tokens = ['MAX', '200', 'KG'];
      expect(looksLikeModelCode(tokens, 1), isFalse);
    });

    test('a number immediately preceded by MAX is excluded regardless of shape', () {
      final tokens = ['MAX', '200'];
      expect(looksLikeModelCode(tokens, 1), isFalse);
    });

    test('a number immediately preceded by MIN is excluded', () {
      final tokens = ['MIN', '10', 'KG'];
      expect(looksLikeModelCode(tokens, 1), isFalse);
    });

    test('a rep count next to REPS is excluded', () {
      final tokens = ['DO', '12', 'REPS'];
      expect(looksLikeModelCode(tokens, 1), isFalse);
    });

    test('a set count next to SETS is excluded', () {
      final tokens = ['3', 'SETS'];
      expect(looksLikeModelCode(tokens, 0), isFalse);
    });

    test('a token with letters but no digit is never a model code', () {
      final tokens = ['LEG', 'PRESS'];
      expect(looksLikeModelCode(tokens, 0), isFalse);
      expect(looksLikeModelCode(tokens, 1), isFalse);
    });

    test('an empty (post-strip) token is not a model code', () {
      final tokens = ['---', '200'];
      expect(looksLikeModelCode(tokens, 0), isFalse);
    });

    test('weight-adjacent LBS number is excluded', () {
      final tokens = ['MAX', '440', 'LBS'];
      expect(looksLikeModelCode(tokens, 1), isFalse);
    });

    test('voltage-adjacent number is excluded', () {
      final tokens = ['RATED', '220', 'V'];
      expect(looksLikeModelCode(tokens, 1), isFalse);
    });
  });

  group('looksLikeModelCode: compact (no-separator) measurement fixtures', () {
    test('a fused voltage token is excluded even though it is mixed alpha+digit', () {
      final tokens = ['RATED', '220V'];
      expect(looksLikeModelCode(tokens, 1), isFalse);
    });

    test('a fused horsepower token is excluded', () {
      final tokens = ['MOTOR', '2HP'];
      expect(looksLikeModelCode(tokens, 1), isFalse);
    });

    test('a fused weight-in-kg token is excluded', () {
      final tokens = ['MAX', '150KG'];
      expect(looksLikeModelCode(tokens, 1), isFalse);
    });

    test('a fused millimetre token is excluded', () {
      final tokens = ['STROKE', '10MM'];
      expect(looksLikeModelCode(tokens, 1), isFalse);
    });

    test('a fused set-count token is excluded', () {
      final tokens = ['DO', '3SETS'];
      expect(looksLikeModelCode(tokens, 1), isFalse);
    });

    test('a fused pound token is excluded', () {
      final tokens = ['MAX', '440LBS'];
      expect(looksLikeModelCode(tokens, 1), isFalse);
    });

    test('a real short mixed-alpha-digit code is still accepted (not over-filtered)', () {
      final tokens = ['MODEL', '8TRx'];
      expect(looksLikeModelCode(tokens, 1), isTrue);
    });

    test('a code ending in letters that are not a recognized unit is still accepted', () {
      final tokens = ['MODEL', '100SL'];
      expect(looksLikeModelCode(tokens, 1), isTrue);
    });
  });

  group('looksLikeModelCode: decimal/range compact measurement fixtures (round-2 fix)', () {
    test('a fused decimal horsepower token is excluded', () {
      final tokens = ['MOTOR', '2.5HP'];
      expect(looksLikeModelCode(tokens, 1), isFalse);
    });

    test('a fused decimal kilowatt token is excluded', () {
      final tokens = ['RATED', '1.5KW'];
      expect(looksLikeModelCode(tokens, 1), isFalse);
    });

    test('a fused voltage range token is excluded', () {
      final tokens = ['INPUT', '220-240V'];
      expect(looksLikeModelCode(tokens, 1), isFalse);
    });

    test('a fused weight range token is excluded', () {
      final tokens = ['RANGE', '50-100KG'];
      expect(looksLikeModelCode(tokens, 1), isFalse);
    });

    test('a decimal-shaped code ending in a non-unit letter is still accepted', () {
      final tokens = ['MODEL', '2.5T'];
      expect(looksLikeModelCode(tokens, 1), isTrue);
    });
  });

  group('isOcrConfusionVariant', () {
    test('O/0 and I/1 confusions are treated as the same code', () {
      expect(isOcrConfusionVariant('9NP1', '9NPI'), isTrue);
      expect(isOcrConfusionVariant('GX40', 'GX4O'), isTrue);
    });

    test('genuinely different codes are not confusion variants', () {
      expect(isOcrConfusionVariant('9NPL', '8TRX'), isFalse);
      expect(isOcrConfusionVariant('EFX885', 'EFX886'), isFalse);
    });

    test('is case-insensitive', () {
      expect(isOcrConfusionVariant('9npl', '9NPL'), isTrue);
    });
  });
}
