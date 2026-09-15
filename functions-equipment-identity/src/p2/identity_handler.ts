/**
 * P2.G3/P2.G5-readiness -- the request-shape validation -> orchestrator ->
 * telemetry wiring behind `equipmentIdentityResolveFromText`, factored out
 * of `index.ts` so it is directly testable (GPT-PM MAJOR, retrospective
 * review of commit afca346, 2026-09-15: `index.ts` calls
 * `admin.initializeApp()` unconditionally at module load, so importing it
 * from a plain, non-e2e `jest` unit test -- the only way to prove the
 * telemetry call is genuinely reachable from the exported callable, and
 * that a telemetry failure never turns a real identity response into a
 * 500 -- would either throw or require faking real credentials. This
 * module has no such side effect: it is safe to import from both the
 * mocked unit suite (`p2/__tests__/identity_handler.test.ts`) and the real
 * Firestore e2e suite (`__e2e__/identity_handler.e2e.test.ts`, where
 * `jest.e2e.setup.js` already calls `admin.initializeApp()` once for the
 * whole run).
 *
 * `index.ts` stays the thin `onCall` wrapper: it owns auth/App-Check and
 * the Cloud Functions module-load side effect; this file owns everything
 * that is pure application logic.
 */
import { HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { EquipmentIdentityRequestSchema, type EquipmentIdentityResponse } from "./contract";
import { resolveEquipmentIdentityFromText } from "./orchestrator";
import { recordServerTerminalTelemetry } from "./telemetry_repository";

/**
 * `uid` must already be authenticated (`request.auth.uid` at the call
 * site) -- this function does not itself check authentication, exactly as
 * `index.ts`'s own header describes: auth is the `onCall` wrapper's job.
 * `rawData` is the callable's raw, unvalidated `request.data`.
 */
export async function resolveEquipmentIdentityAndRecordTelemetry(
  uid: string,
  rawData: unknown,
): Promise<EquipmentIdentityResponse> {
  const parsed = EquipmentIdentityRequestSchema.safeParse(rawData);
  if (!parsed.success) {
    logger.warn("equipment_identity_request_schema_invalid", {
      uid,
      issues: parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`),
    });
    throw new HttpsError("invalid-argument", "Malformed equipment identity request.");
  }

  const response = await resolveEquipmentIdentityFromText({ uid, request: parsed.data });

  // P2.G5-readiness step 2: records the server's own terminal identity
  // decision for every real response path. `recordServerTerminalTelemetry`
  // itself already never throws (see that file's own doc comment), but a
  // telemetry write failing must not turn a real identity response the
  // caller is waiting on into a 500 even if that guarantee is ever
  // weakened by a future change there -- this is the same swallow-and-log
  // discipline applied again at the call site, defense in depth for a
  // property this design doc states as an explicit invariant, not an
  // incidental one.
  try {
    await recordServerTerminalTelemetry(uid, response.scanId, response);
  } catch (e) {
    logger.error("equipment_identity_telemetry_call_failed", {
      uid,
      scanId: response.scanId,
      err: e instanceof Error ? (e.stack ?? e.message) : String(e),
    });
  }

  return response;
}
