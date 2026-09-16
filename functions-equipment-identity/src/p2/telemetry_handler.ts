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
 * boundary). This is never retried by the mobile outbox regardless (a
 * malformed request stays malformed no matter how many times it is resent),
 * so it is a genuinely terminal failure from the client's perspective.
 *
 * A VALID request whose merge write itself fails throws `unavailable` --
 * GPT-PM BLOCKER, P2.G5-readiness step 3b review, 2026-09-16, correcting
 * this handler's own prior behavior (which used to swallow the failure and
 * still answer `{ ok: true }`, on the stated premise that "the client has
 * no ability to usefully retry"). That premise held for step 3a, when it
 * was written, and stopped holding the moment step 3b shipped a durable
 * client-side outbox specifically built to retry a failed send -- an outbox
 * that can only ever activate on a send the CLIENT observes as having
 * failed. `recordMobileTelemetryFragment`'s own doc comment explains why
 * retrying is always safe here (the merge rules make an identical resend an
 * idempotent no-op) and why `recordServerTerminalTelemetry`'s OWN sibling
 * callable is deliberately left on its old swallow-and-succeed behavior
 * (its caller is synchronously waiting on the user's actual scan result,
 * with no outbox of its own to hand a retryable failure to).
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

  const persisted = await recordMobileTelemetryFragment(uid, parsed.data);
  if (!persisted) {
    // `recordMobileTelemetryFragment` already logged the underlying cause
    // (`equipment_identity_telemetry_mobile_write_failed`) -- this is
    // purely about turning that into a client-visible, retryable signal.
    // "unavailable" (not e.g. "internal") is the callable-client-recognized
    // code for "the caller may reasonably retry this."
    throw new HttpsError(
      "unavailable",
      "Equipment identity telemetry fragment could not be persisted; retry.",
    );
  }
  return { ok: true };
}
