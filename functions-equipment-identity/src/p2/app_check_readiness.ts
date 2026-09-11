/**
 * P2.G3 T3 / P0.G0 T1-T2 (SPTR Equipment Recognition v4.4) -- consumer of
 * the platform/P0-owned `APP_CHECK_PLATFORM_READINESS` status.
 *
 * GPT-PM round-2 review of the P2.G3 plan (2026-09-10) found the original
 * design let this package OWN the current readiness value (a hardcoded
 * "authoritative current value" constant) -- a source-of-truth duplication
 * risk: once the real external App Check/Play Integrity platform migration
 * actually completes, nothing would force this package's own copy to
 * change, and a future edit here could silently assert production-ready
 * with no real platform evidence behind it.
 *
 * This module never owns the value. It reads a generated copy
 * (src/generated/p0_g0_app_check_platform_readiness.json, synced from the
 * single P0-owned source core/equipment_identity/p0/
 * p0_g0_app_check_platform_readiness.json by
 * scripts/sync_p0_app_check_readiness.js -- same pattern as
 * type_snapshot.ts's loadGeneratedSnapshot) and fails closed to
 * BLOCKED_EXTERNAL_PLATFORM_MIGRATION on any missing/unreadable/invalid
 * case. There is exactly one bare "BLOCKED_EXTERNAL_PLATFORM_MIGRATION"
 * literal in this file, and it exists only as that fail-closed fallback --
 * never as an assertion that the platform is actually in that state.
 */
import { z } from "zod";
import { IsoTimestampSchema } from "../p1/contracts";
import generatedReadiness from "../generated/p0_g0_app_check_platform_readiness.json";

/**
 * P0.G0 Story AC: "APP_CHECK_PLATFORM_READINESS status exists with exactly
 * the three defined values." Binding, not P2's to extend.
 */
export const AppCheckPlatformReadinessStatusSchema = z.enum([
  "BLOCKED_EXTERNAL_PLATFORM_MIGRATION",
  "READY_FOR_SHADOW",
  "READY_FOR_PRODUCTION",
]);
export type AppCheckPlatformReadinessStatus = z.infer<
  typeof AppCheckPlatformReadinessStatusSchema
>;

export const AppCheckPlatformReadinessArtifactSchema = z
  .object({
    schemaVersion: z.literal(1),
    status: AppCheckPlatformReadinessStatusSchema,
    updatedAt: IsoTimestampSchema,
    evidenceRef: z.string().min(1),
  })
  .strict();
export type AppCheckPlatformReadinessArtifact = z.infer<
  typeof AppCheckPlatformReadinessArtifactSchema
>;

/** The only fail-closed fallback value in this module. Never an assertion. */
const FAIL_CLOSED_STATUS: AppCheckPlatformReadinessStatus =
  "BLOCKED_EXTERNAL_PLATFORM_MIGRATION";

/**
 * Pure validation/fail-closed core, separated from the static import below
 * so a test can exercise "missing", "malformed" and "unknown status value"
 * inputs directly -- `undefined`/a broken object/a bad status string --
 * without needing to fake a missing file on disk at import time (the
 * generated JSON is a compile-time `import`, same as type_snapshot.ts's
 * loadGeneratedSnapshot; there is no runtime file read to mock here).
 *
 * ANY failure -- the input is missing, the shape does not match the
 * schema, the status is not one of the 3 defined values -- resolves to the
 * fail-closed status rather than throwing, because a broken/missing
 * readiness artifact must behave exactly like "migration not done yet",
 * never like "unknown, so allow".
 */
export function resolveReadinessArtifact(
  candidate: unknown,
): AppCheckPlatformReadinessArtifact {
  const parsed = AppCheckPlatformReadinessArtifactSchema.safeParse(candidate);
  if (!parsed.success) {
    return {
      schemaVersion: 1,
      status: FAIL_CLOSED_STATUS,
      updatedAt: new Date(0).toISOString(),
      evidenceRef: `fail-closed: generated readiness artifact failed validation (${parsed.error.issues
        .map((i) => `${i.path.join(".")}: ${i.message}`)
        .join("; ")})`,
    };
  }
  return parsed.data;
}

/** Reads and validates the generated copy synced from the P0 source. */
export function loadAppCheckPlatformReadiness(): AppCheckPlatformReadinessArtifact {
  return resolveReadinessArtifact(generatedReadiness);
}

export type EnforcementLane = "SHADOW" | "PRODUCTION";

/**
 * P0.G0 Task T2 ("split shadow vs. production enforcement... mechanical
 * check, not a comment") applied at the P2.G3 consumer site.
 *
 * SHADOW may always run with App Check enforcement off, regardless of
 * platform readiness -- P0.G0's own rollback/failure mode is "remain
 * shadow-only indefinitely."
 *
 * PRODUCTION can never independently assert enforcement true: it is true
 * if and only if the platform-owned status is READY_FOR_PRODUCTION. This
 * function has no other path to `true` for the PRODUCTION lane -- there is
 * no override parameter, no env var read here, nothing a caller can pass
 * to force it.
 */
export function resolveAppCheckEnforcement(
  status: AppCheckPlatformReadinessStatus,
  lane: EnforcementLane,
): boolean {
  if (lane === "SHADOW") return false;
  return status === "READY_FOR_PRODUCTION";
}

/**
 * Convenience wrapper combining the two above -- what a callable actually
 * wants to know: "given the CURRENT tracked platform state, should this
 * request's lane require a valid App Check token?"
 */
export function isAppCheckEnforcedForLane(lane: EnforcementLane): boolean {
  const { status } = loadAppCheckPlatformReadiness();
  return resolveAppCheckEnforcement(status, lane);
}
