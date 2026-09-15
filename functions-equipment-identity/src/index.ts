/**
 * P2.G3 -- the first real Cloud Function this codebase exports. P0.G6
 * (`core/equipment_identity/p0/P0_G6_DEPLOYMENT_ISOLATION.md`) closed on the
 * strategy that this package is deployed as its OWN Firebase Functions
 * codebase (`firebase.json`'s `equipment-identity` entry), specifically so a
 * broken build here can never block the default codebase's own deploys
 * (Stripe, AI coaching, etc). This file is the thin `onCall` wrapper: it
 * owns auth/App-Check/request-shape concerns; `p2/orchestrator.ts` owns the
 * actual quota -> catalog -> policy -> session pipeline and is deliberately
 * framework-agnostic so it can be exercised directly in tests.
 */
import * as admin from "firebase-admin";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { EquipmentIdentityRequestSchema } from "./p2/contract";
import { resolveEquipmentIdentityFromText } from "./p2/orchestrator";
import { loadAppCheckPlatformReadiness, resolveAppCheckEnforcement } from "./p2/app_check_readiness";
import { recordServerTerminalTelemetry } from "./p2/telemetry_repository";

// BLOCKER, P2.G3 pre-commit review, 2026-09-11: this call was missing
// entirely. `p2/firestore_admin.ts`'s `db()` is a lazy per-call
// `admin.firestore()` accessor -- its own doc comment already says
// `admin.initializeApp()` must have run first, but nothing in this
// package's production path ever called it. Every internal test suite
// stayed green regardless, because `jest.e2e.setup.js` independently
// calls `admin.initializeApp()` for test-harness convenience, masking the
// gap -- a real deployment would have failed on its very first
// Firestore-touching request. Mirrors `functions/src/index.ts`'s own
// bare, unguarded call (this file is a Cloud Functions module entrypoint,
// loaded once per process by the runtime, exactly like that one). See
// `src/__e2e__/admin_init.e2e.test.ts` for the regression test that
// proves this without relying on the e2e harness's own pre-init.
admin.initializeApp();

/** Matches `functions/src/scaling.ts`'s own `REGION` constant -- kept as a
 * local literal rather than imported, since P0.G6 deliberately keeps this
 * package free of any import from the default `functions/` codebase. */
const REGION = "europe-west1";

/**
 * `enforceAppCheck` is a STATIC option Firebase reads once when this
 * function is defined/deployed, never per-request (there is no per-call
 * "lane" field in the v4.4 request schema to branch on even if it were).
 * So App Check enforcement and the SHADOW/PRODUCTION exact-match lane
 * (`orchestrator.ts`) are both derived from the exact same platform-owned
 * readiness signal, computed once here, at module load: while P0.G0 is not
 * READY_FOR_PRODUCTION, this callable does not hard-enforce App Check
 * either -- enforcing it early, on a deployment nothing has verified is
 * actually attesting real clients yet, would fail closed for every caller
 * instead of gathering shadow evidence.
 */
const APP_CHECK_ENFORCED =
  resolveAppCheckEnforcement(loadAppCheckPlatformReadiness().status, "PRODUCTION");

export const equipmentIdentityResolveFromText = onCall(
  { region: REGION, enforceAppCheck: APP_CHECK_ENFORCED },
  async (request: CallableRequest) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in to identify equipment.");
    }

    const parsed = EquipmentIdentityRequestSchema.safeParse(request.data);
    if (!parsed.success) {
      logger.warn("equipment_identity_request_schema_invalid", {
        uid: request.auth.uid,
        issues: parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`),
      });
      throw new HttpsError("invalid-argument", "Malformed equipment identity request.");
    }

    const response = await resolveEquipmentIdentityFromText({ uid: request.auth.uid, request: parsed.data });
    // P2.G5-readiness step 2: records the server's own terminal identity
    // decision for every real response path. Never throws (see
    // `telemetry_repository.ts`'s own doc comment) -- a telemetry write
    // failing must not turn a real identity response the caller is waiting
    // on into a 500.
    await recordServerTerminalTelemetry(request.auth.uid, response.scanId, response);
    return response;
  },
);
