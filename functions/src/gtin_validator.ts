/**
 * GTIN check-digit validation for `lookupBarcode` (design s17.4).
 *
 * Re-implemented from the public GS1 algorithm (the mod-10 check digit over
 * GTIN-8/12/13/14); no third-party code is used. The client has the same rule in
 * `gtin_validator.dart`, and both reject the same inputs: only ASCII digits,
 * exactly 8, 12, 13 or 14 of them, and a correct last digit. Whitespace and
 * punctuation are NOT stripped here (the callable receives digits only, and a
 * lenient parser would make "same on both sides" harder to prove); leading
 * zeros are significant, because they are part of the fixed length.
 */

/** The lengths a GS1 trade item number can have (EAN-8, UPC-A, EAN-13, ITF-14). */
export const GTIN_LENGTHS: readonly number[] = [8, 12, 13, 14];

/** The mod-10 check digit for the payload (every digit but the last). */
export function gtinCheckDigit(payload: string): number {
  let sum = 0;
  // Weights 3,1,3,1,... counted from the digit next to the check digit.
  for (let i = 0; i < payload.length; i++) {
    const digit = payload.charCodeAt(payload.length - 1 - i) - 48;
    sum += digit * (i % 2 === 0 ? 3 : 1);
  }
  return (10 - (sum % 10)) % 10;
}

/** True only for a digits-only string of a valid GTIN length with a correct check digit. */
export function isValidGtin(code: unknown): boolean {
  if (typeof code !== "string") return false;
  if (!GTIN_LENGTHS.includes(code.length)) return false;
  if (!/^[0-9]+$/.test(code)) return false;
  return gtinCheckDigit(code.slice(0, -1)) === code.charCodeAt(code.length - 1) - 48;
}
