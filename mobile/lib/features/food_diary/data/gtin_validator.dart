/// GTIN check-digit validator, re-implemented from the public GS1 algorithm
/// (design s17.4, FOOD-12). No code from OpenNutriTracker or any GPL source.
/// Pure Dart.
///
/// Contract (fixed here and mirrored by the server-side TypeScript twin):
/// the input must be digits only, NO trimming and NO leading-zero stripping,
/// with length 8, 12, 13 or 14 (EAN-8, UPC-A, EAN-13, ITF-14/GTIN-14).
/// UPC-E (6/8 digits compressed form) is accepted only as its 8-digit form,
/// which is checked like EAN-8.
library;

class GtinValidator {
  const GtinValidator._();

  static const Set<int> validLengths = {8, 12, 13, 14};

  static final RegExp _digits = RegExp(r'^[0-9]+$');

  /// True when [code] is a well-formed GTIN with a correct check digit.
  static bool isValid(String code) {
    if (!validLengths.contains(code.length)) return false;
    if (!_digits.hasMatch(code)) return false;
    final units = code.codeUnits;
    final body = units.length - 1;
    var sum = 0;
    // Weights alternate 3,1,3,... starting at the digit next to the check
    // digit and moving left.
    for (var i = 0; i < body; i++) {
      final digit = units[body - 1 - i] - 0x30;
      sum += digit * (i.isEven ? 3 : 1);
    }
    final expected = (10 - (sum % 10)) % 10;
    return expected == units[body] - 0x30;
  }

  /// Convenience for scanner/typed input: trims surrounding whitespace, then
  /// returns the digits when the result passes [isValid], else null. Leading
  /// zeros are kept as typed.
  static String? normaliseValid(String raw) {
    final t = raw.trim();
    return isValid(t) ? t : null;
  }
}
