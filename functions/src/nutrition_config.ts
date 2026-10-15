/**
 * Configuration for the nutrition upstreams (design s17.4-17.5, sprint plan
 * section 4 / Q-4).
 *
 * Nothing here is a secret. The USDA key is NOT read here: it lives in Secret
 * Manager and is fetched at runtime by `nutrition_sources/usda_fdc.ts`, so a
 * missing secret never fails a deploy.
 */

/** Used until the operator supplies a contact (Q-4); `FOOD_LOOKUP_ENABLED` is off by default anyway. */
export const DEFAULT_OFF_CONTACT = "contact-not-configured";
export const DEFAULT_APP_VERSION = "1.0";

/** Secret Manager secret holding the registered USDA FoodData Central key (never `DEMO_KEY`). */
export const USDA_SECRET_ID = "USDA_FDC_API_KEY";

/** A header-safe token: ASCII letters, digits and a few separators, bounded. */
function headerSafe(value: string | undefined, fallback: string, max: number): string {
  const cleaned = (value ?? "").replace(/[^A-Za-z0-9@._:/+ -]/g, "").trim().slice(0, max);
  return cleaned === "" ? fallback : cleaned;
}

/** Operator contact for the OFF `User-Agent` (`OFF_CONTACT`, e.g. a mailbox or a URL). */
export function offContact(): string {
  return headerSafe(process.env.OFF_CONTACT, DEFAULT_OFF_CONTACT, 80);
}

export function appVersion(): string {
  return headerSafe(process.env.APP_VERSION, DEFAULT_APP_VERSION, 20);
}

/** `FitnessApp/<version> (<contact>)` -- mandatory for Open Food Facts (their API policy). */
export function offUserAgent(): string {
  return `FitnessApp/${appVersion()} (${offContact()})`;
}
