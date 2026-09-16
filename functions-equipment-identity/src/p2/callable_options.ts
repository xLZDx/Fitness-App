/**
 * Shared `onCall` options for every callable in this package. Introduced for
 * P2.G5-readiness step 3a (GPT-PM MAJOR, round 2 of that gate's review): the
 * new `equipmentIdentityRecordTelemetry` callable writes evaluation evidence
 * and must not have a weaker ingress posture than `equipmentIdentityResolveFromText` --
 * sharing this ONE constant (not restating the same two values in two files)
 * is what a regression test can assert never drifts.
 */
import { loadAppCheckPlatformReadiness, resolveAppCheckEnforcement } from "./app_check_readiness";

/** Matches `functions/src/scaling.ts`'s own `REGION` constant -- kept as a
 * local literal rather than imported, since P0.G6 deliberately keeps this
 * package free of any import from the default `functions/` codebase. */
export const REGION = "europe-west1";

/**
 * `enforceAppCheck` is a STATIC option Firebase reads once when a function is
 * defined/deployed, never per-request. So App Check enforcement is derived
 * from the platform-owned readiness signal, computed once here, at module
 * load: while P0.G0 is not READY_FOR_PRODUCTION, callables in this package do
 * not hard-enforce App Check either -- enforcing it early, on a deployment
 * nothing has verified is actually attesting real clients yet, would fail
 * closed for every caller instead of gathering shadow evidence.
 */
export const APP_CHECK_ENFORCED = resolveAppCheckEnforcement(
  loadAppCheckPlatformReadiness().status,
  "PRODUCTION",
);

export const EQUIPMENT_IDENTITY_CALLABLE_OPTIONS = {
  region: REGION,
  enforceAppCheck: APP_CHECK_ENFORCED,
} as const;
