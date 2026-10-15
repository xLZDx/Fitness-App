/**
 * Server-side age and tier gate for `createBodyScan` (design s7.1, D-58).
 *
 * The client sends an `ageYears` value; it is IGNORED. The server derives the
 * age from `users/{uid}/profile/main` `personal.birthYear` with the same
 * conservative formula the app uses (`PersonalInfo.lowestAgeAt`: the LOWEST age
 * the stored birth year allows, so someone turning 18 in December does not pass
 * on 1 January) and refuses an unknown or under-18 age.
 *
 * Honest limit (recorded in D-58): `birthYear` is client-writable, so a modified
 * client can lie in its own profile. This gate closes the "direct callable with
 * ageYears: 25" hole and gives the server the same rule as the app; it does not
 * prove age.
 */
import { HttpsError } from "firebase-functions/v2/https";
import { db, millisOf } from "./shared";

/** Same minimum as `SafetyClamps.minAdultAge` on the client. */
export const MIN_ADULT_AGE = 18;
const MAX_PLAUSIBLE_AGE = 120;

export const AGE_REQUIRED = "age-required";
export const TIER_REQUIRED = "tier-required";

/**
 * The lowest age the stored birth year allows, or `failed-precondition:
 * age-required` when it is absent, malformed, implausible or under 18.
 */
export async function resolveAdultAge(uid: string, nowMs: number): Promise<number> {
  const snap = await db().doc(`users/${uid}/profile/main`).get();
  const birthYear: unknown = snap.data()?.personal?.birthYear;
  if (typeof birthYear !== "number" || !Number.isInteger(birthYear)) {
    throw new HttpsError("failed-precondition", AGE_REQUIRED);
  }
  const age = new Date(nowMs).getUTCFullYear() - birthYear - 1;
  if (age < MIN_ADULT_AGE || age > MAX_PLAUSIBLE_AGE) {
    throw new HttpsError("failed-precondition", AGE_REQUIRED);
  }
  return age;
}

const PAID_TIERS: ReadonlySet<string> = new Set(["standard", "celebrityTrainer"]);

/**
 * Port of the client `effectiveTier` for the one question the server needs:
 * does this account currently hold a paid tier? Unknown values are FREE (never
 * a silent grant); an expired trial/period is FREE.
 */
export function hasPaidTier(
  sub: FirebaseFirestore.DocumentData | undefined,
  nowMs: number,
): boolean {
  if (!sub) return false;
  const tier = sub.tier;
  if (typeof tier !== "string" || !PAID_TIERS.has(tier)) return false;
  const endMs = (value: unknown): number | undefined => {
    const direct = millisOf(value);
    if (direct !== undefined) return direct;
    if (typeof value === "string") {
      const parsed = Date.parse(value);
      return Number.isNaN(parsed) ? undefined : parsed;
    }
    return undefined;
  };
  switch (sub.status) {
    case "trial": {
      const end = endMs(sub.trialEndsAt);
      return end === undefined || nowMs <= end;
    }
    case "active":
    case "cancelled": {
      const end = endMs(sub.currentPeriodEndsAt);
      return end === undefined || nowMs <= end;
    }
    default:
      return false;
  }
}

/** `permission-denied: tier-required` for a free account (the existing scan gate, D-26). */
export async function assertScanTier(uid: string, nowMs: number): Promise<void> {
  const snap = await db().doc(`users/${uid}/subscription/main`).get();
  if (!hasPaidTier(snap.data(), nowMs)) {
    throw new HttpsError("permission-denied", TIER_REQUIRED);
  }
}
