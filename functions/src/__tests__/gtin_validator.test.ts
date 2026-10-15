/**
 * T107 gtin_validator (FOOD-12): the GS1 mod-10 check digit and the fixed input rules
 * (digits only, lengths 8/12/13/14, no trimming, leading zeros significant). The Dart twin
 * (`gtin_validator_test.dart`) must reject exactly the same inputs.
 */
import { GTIN_LENGTHS, gtinCheckDigit, isValidGtin } from "../gtin_validator";

/** Real-world valid codes of each accepted length. */
const VALID: Array<[string, string]> = [
  ["EAN-13 (Nutella)", "3017620422003"],
  ["EAN-13 (Coca-Cola)", "5449000000996"],
  ["EAN-13 (generic)", "4006381333931"],
  ["UPC-A", "036000291452"],
  ["EAN-8", "96385074"],
  ["GTIN-14", "10012345678902"],
];

const withLastDigit = (code: string, d: number): string => code.slice(0, -1) + String(d);

describe("isValidGtin: valid codes", () => {
  test.each(VALID)("%s %s passes", (_label, code) => {
    expect(isValidGtin(code)).toBe(true);
  });

  test.each(VALID)("%s: every wrong check digit fails (exactly one of ten digits passes)", (_label, code) => {
    const lastDigit = Number(code.slice(-1));
    let passing = 0;
    for (let d = 0; d <= 9; d++) {
      const ok = isValidGtin(withLastDigit(code, d));
      if (ok) passing++;
      expect(ok).toBe(d === lastDigit);
    }
    expect(passing).toBe(1);
  });

  test("the check digit helper agrees with the last digit of each valid code", () => {
    for (const [, code] of VALID) {
      expect(gtinCheckDigit(code.slice(0, -1))).toBe(Number(code.slice(-1)));
    }
  });

  test("a payload digit change (transposition) is caught", () => {
    expect(isValidGtin("3017620422030")).toBe(false); // last two digits swapped
    expect(isValidGtin("3017620422103")).toBe(false);
  });
});

describe("isValidGtin: lengths", () => {
  test("accepted lengths are exactly 8, 12, 13, 14", () => {
    expect([...GTIN_LENGTHS]).toEqual([8, 12, 13, 14]);
  });

  test.each([7, 9, 10, 11, 15, 1, 0, 20])("length %i is refused even with a correct check digit", (len) => {
    // Build a code of that length whose last digit is a correct check digit.
    const payload = "1234567890123456789".slice(0, Math.max(0, len - 1));
    const code = len === 0 ? "" : payload + String(gtinCheckDigit(payload));
    expect(code.length).toBe(len);
    expect(isValidGtin(code)).toBe(false);
  });
});

describe("isValidGtin: hostile and malformed input", () => {
  test.each([
    ["letters", "301762042200A"],
    ["leading space", " 3017620422003"],
    ["trailing space", "3017620422003 "],
    ["inner space", "30176 20422003"],
    ["hyphens", "3017-6204-22003"],
    ["newline", "3017620422003\n"],
    ["plus sign", "+3017620422003"],
    ["unicode digits (Arabic-Indic)", "٣٠١٧٦٢٠٤٢٢٠٠٣"],
    ["full-width digits", "３０１７６２０４２２００３"],
    ["empty string", ""],
    ["sql-ish", "1; DROP TABLE"],
  ])("%s is refused", (_label, code) => {
    expect(isValidGtin(code)).toBe(false);
  });

  test.each([null, undefined, 3017620422003, {}, [], ["3017620422003"], true])("non-string %p is refused", (v) => {
    expect(isValidGtin(v)).toBe(false);
  });

  test("leading zeros are significant: the UPC-A and its zero-padded EAN-13 are both valid, distinct strings", () => {
    expect(isValidGtin("036000291452")).toBe(true);
    expect(isValidGtin("0036000291452")).toBe(true);
    // A code truncated by one leading zero changes length class and check validity.
    expect(isValidGtin("36000291452")).toBe(false);
  });

  test("an all-zero code of a valid length is arithmetically valid (check digit 0), documenting the rule", () => {
    expect(isValidGtin("00000000")).toBe(true);
    expect(isValidGtin("00000001")).toBe(false);
  });
});
