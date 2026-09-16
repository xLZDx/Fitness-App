/**
 * P2.G5-readiness step 3a -- the request-shape validation -> repository
 * wiring behind `equipmentIdentityRecordTelemetry`, factored out of
 * `index.ts` for the same testability reason `identity_handler.ts`'s own
 * header already documents for its sibling callable: importing `index.ts`
 * directly runs `admin.initializeApp()` at module load, which a plain
 * mocked unit test cannot safely do.
 */
import { HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { EquipmentIdentityTelemetryReportRequestSchema } from "./telemetry_contract";
import { recordMobileTelemetryFragment } from "./telemetry_repository";

/**
 * `uid` must already be authenticated (`request.auth.uid` at the call
 * site) -- this function does not itself check authentication, exactly as
 * `identity_handler.ts`'s own sibling function describes: auth is the
 * `onCall` wrapper's job. `rawData` is the callable's raw, unvalidated
 * `request.data`.
 *
 * A schema-invalid request is rejected outright with `invalid-argument` --
 * the mobile client has no authority to submit anything outside the 3
 * contract shapes (design doc §6's authority split, enforced here at the
 * boundary). A VALID request whose merge write itself fails is swallowed by
 * `recordMobileTelemetryFragment` the same way `recordServerTerminalTelemetry`
 * already is for the sibling callable (that function's own doc comment) --
 * so this handler still returns success to the client even on a persistence
 * failure; a lost telemetry fragment is a data-quality gap for step 5's
 * report, never a user-facing error for a report the client has no ability
 * to usefully retry (retrying would just resend the identical fragment).
 */
export async function recordEquipmentIdentityTelemetryFragment(
  uid: string,
  rawData: unknown,
): Promise<{ ok: true }> {
  const parsed = EquipmentIdentityTelemetryReportRequestSchema.safeParse(rawData);
  if (!parsed.success) {
    logger.warn("equipment_identity_telemetry_report_schema_invalid", {
      uid,
      issues: parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`),
    });
    throw new HttpsError("invalid-argument", "Malformed equipment identity telemetry report.");
  }

  // `recordMobileTelemetryFragment` already never throws (see that
  // function's own doc comment) -- this is the same defense-in-depth
  // swallow-and-log discipline `identity_handler.ts` applies a second time
  // at its own call site, for a property this design doc states as an
  // explicit invariant, not an incidental one.
  try {
    await recordMobileTelemetryFragment(uid, parsed.data);
  } catch (e) {
    logger.error("equipment_identity_telemetry_fragment_call_failed", {
      uid,
      scanId: parsed.data.scanId,
      err: e instanceof Error ? (e.stack ?? e.message) : String(e),
    });
  }
  return { ok: true };
}
