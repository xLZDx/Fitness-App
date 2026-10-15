import { HttpsError } from "firebase-functions/v2/https";

/**
 * The machine-readable `message` slug a flagged-off callable answers with. The
 * client maps it to a calm "not available yet" state and never retries it
 * (sprint plan section 4).
 */
export const FEATURE_DISABLED_MESSAGE = "feature-disabled";

/**
 * Throws `failed-precondition: feature-disabled` when `enabled` is false.
 *
 * Takes the flag's VALUE, not its name, so the caller reads it through the one
 * flag module that owns it (`foodAiEnabled()`, `foodLookupEnabled()`,
 * `bodyScanCloudEnabled()`) and no other code path touches an environment
 * variable.
 *
 * ORDER MATTERS: call it after auth, App Check note, the non-anonymous check
 * and `enforceAiGatewayEnabled`, and BEFORE `enforceDailyQuota` -- a call
 * refused because the feature is off must charge nothing (design s7.5). It
 * carries no user data and logs nothing: a flag-off call is the expected state
 * of the default build, not an event.
 */
export function assertFeatureEnabled(enabled: boolean): void {
  if (!enabled) {
    throw new HttpsError("failed-precondition", FEATURE_DISABLED_MESSAGE);
  }
}
