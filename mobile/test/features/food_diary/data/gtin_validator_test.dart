// T93 gtin_validator_test (FOOD-12). Check digits are the public GS1 values
// from the coverage map V-GTIN row, not computed by the implementation.
import 'package:fitness_app/features/food_diary/data/gtin_validator.dart';
import 'package:flutter_test/flutter_test.dart';

const Map<String, String> _valid = {
  'EAN-13': '4006381333931',
  'EAN-8': '96385074',
  'UPC-A': '036000291452',
  'ITF-14': '10012345678902',
  'EAN-13 (Nutella)': '3017620422003',
};

void main() {
  group('valid codes (V-GTIN)', () {
    _valid.forEach((label, code) {
      test('$label $code is valid', () {
        expect(GtinValidator.isValid(code), isTrue);
      });
    });
  });

  group('wrong check digit', () {
    _valid.forEach((label, code) {
      test('$label: every other last digit is invalid', () {
        final body = code.substring(0, code.length - 1);
        final correct = code[code.length - 1];
        var tried = 0;
        for (var d = 0; d <= 9; d++) {
          if ('$d' == correct) continue;
          tried++;
          expect(GtinValidator.isValid('$body$d'), isFalse,
              reason: '$body$d must be refused');
        }
        expect(tried, 9);
      });
    });

    test('a body digit changed (check digit kept) is invalid', () {
      // 4006381333931 -> change the first digit 4 to 5
      expect(GtinValidator.isValid('5006381333931'), isFalse);
      // 96385074 -> change the 2nd digit
      expect(GtinValidator.isValid('90385074'), isFalse);
    });

    test('adjacent transposition with different weights is detected', () {
      // swap the 9 and 3 before the check digit of 4006381333931
      expect(GtinValidator.isValid('4006381333391'), isFalse);
    });
  });

  group('length', () {
    test('lengths 8, 12, 13, 14 are the only accepted lengths', () {
      expect(GtinValidator.validLengths, {8, 12, 13, 14});
      expect(GtinValidator.isValid('96385074'), isTrue); // 8
      expect(GtinValidator.isValid('036000291452'), isTrue); // 12
      expect(GtinValidator.isValid('4006381333931'), isTrue); // 13
      expect(GtinValidator.isValid('10012345678902'), isTrue); // 14
    });

    for (final bad in <String>[
      '', // 0
      '9638507', // 7
      '963850740', // 9
      '4006381333', // 10
      '40063813339', // 11
      '400638133393100', // 15
    ]) {
      test('length ${bad.length} is refused ("$bad")', () {
        expect(GtinValidator.isValid(bad), isFalse);
      });
    }

    test('a 15 digit code whose digits would otherwise checksum is refused',
        () {
      expect(GtinValidator.isValid('0${_valid['ITF-14']}'), isFalse);
    });
  });

  group('non-digit input', () {
    for (final bad in <String>[
      '40063813339 1',
      '400638133393a',
      '-4006381333931',
      '4006381333931.',
      '4006-3813-3393-1',
      'abcdefgh',
      '96385O74', // letter O
      // Arabic-Indic digits for 4006381333931 must not pass as digits.
      '٤٠٠٦٣٨١٣٣٣٩٣١',
    ]) {
      test('"$bad" is refused', () {
        expect(GtinValidator.isValid(bad), isFalse);
      });
    }
  });

  group('whitespace and leading zeros are NOT normalised by isValid', () {
    test('surrounding whitespace is refused by isValid', () {
      expect(GtinValidator.isValid(' 4006381333931'), isFalse);
      expect(GtinValidator.isValid('4006381333931 '), isFalse);
      expect(GtinValidator.isValid('4006381333931\n'), isFalse);
    });

    test('leading zeros are kept: UPC-A padded to 13 is a distinct valid GTIN',
        () {
      expect(GtinValidator.isValid('0036000291452'), isTrue);
      expect(GtinValidator.isValid('00036000291452'), isTrue);
    });

    test('stripping a leading zero changes the length and is refused', () {
      // 036000291452 (12) -> 36000291452 (11)
      expect(GtinValidator.isValid('36000291452'), isFalse);
    });
  });

  group('normaliseValid', () {
    test('trims whitespace and returns the digits when valid', () {
      expect(GtinValidator.normaliseValid('  4006381333931 \n'),
          '4006381333931');
      expect(GtinValidator.normaliseValid('\t96385074'), '96385074');
    });

    test('keeps leading zeros as typed', () {
      expect(GtinValidator.normaliseValid(' 0036000291452 '), '0036000291452');
    });

    test('returns null for invalid input', () {
      expect(GtinValidator.normaliseValid('4006381333932'), isNull);
      expect(GtinValidator.normaliseValid('   '), isNull);
      expect(GtinValidator.normaliseValid(''), isNull);
      expect(GtinValidator.normaliseValid('40063 81333931'), isNull,
          reason: 'inner whitespace is not trimmed');
    });
  });

  test('all-zero 8 digit code satisfies the algorithm (check digit 0)', () {
    expect(GtinValidator.isValid('00000000'), isTrue);
    expect(GtinValidator.isValid('00000001'), isFalse);
  });
}
