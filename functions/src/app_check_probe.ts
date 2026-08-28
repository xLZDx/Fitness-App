/**
 * MVP1.G4 Step 2, Option D: a temporary, no-Vertex callable whose sole job is
 * proving whether a REAL release APK — signed and installed through the
 * actual outside-Play channel this project ships testers through (Firebase
 * App Distribution / a direct install of that same signed artifact, not a
 * Play Store install and not a local debug build) — can pass Play Integrity
 * attestation under `enforceAppCheck: true`.
 *
 * Deliberately excludes any Vertex AI call, quota check, or auth requirement:
 * the only variable under test is App Check attestation itself. A failure
 * here throws before this handler body ever runs (Cloud Functions rejects an
 * unattested call at the platform level when `enforceAppCheck: true`), so a
 * client-visible success/failure on this one callable IS the proof.
 *
 * Not part of the permanent API surface. Delete this file, its export in
 * `index.ts`, its mobile trigger, and undeploy the function once Option D's
 * proof is recorded in `core/G4_STEP2_APP_CHECK_BOUNDARY_2026-08-28.md`.
 */

import { onCall } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

// `scaling.ts`'s own REGION constant is module-private (not exported); kept
// as a literal here since this whole file is temporary and deleted with the
// rest of Option D's scaffolding -- must match `scaling.ts:74` for the
// deployed function to sit alongside the others.
const REGION = "europe-west1";

const APP_CHECK_PROBE_EVENT = "g4_step2_app_check_probe";

export const appCheckProbe = onCall(
  { region: REGION, maxInstances: 2, enforceAppCheck: true },
  async (request) => {
    // Reached only if App Check attestation already passed -- enforcement
    // rejects the call before this body runs otherwise. `request.app` is
    // therefore always defined here; the fields are recorded for the record,
    // not because the handler needs to branch on them.
    logger.info(APP_CHECK_PROBE_EVENT, {
      attested: request.app !== undefined,
      appId: request.app?.appId,
    });
    return { ok: true, attested: request.app !== undefined };
  },
);
