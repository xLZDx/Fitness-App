/**
 * P2.G3 -- the first real Cloud Function this codebase exports. P0.G6
 * (`core/equipment_identity/p0/P0_G6_DEPLOYMENT_ISOLATION.md`) closed on the
 * strategy that this package is deployed as its OWN Firebase Functions
 * codebase (`firebase.json`'s `equipment-identity` entry), specifically so a
 * broken build here can never block the default codebase's own deploys
 * (Stripe, AI coaching, etc). This file is the thin `onCall` wrapper: it
 * owns only auth and the Cloud Functions module-load side effect
 * (`admin.initializeApp()` below). Request-shape validation, the
 * orchestrator call, and the telemetry write live in
 * `p2/identity_handler.ts`, which -- like `p2/orchestrator.ts` -- is
 * deliberately framework-agnostic so it can be exercised directly in
 * tests (GPT-PM MAJOR, retrospective review of commit afca346,
 * 2026-09-15: importing THIS file from a test unconditionally runs
 * `admin.initializeApp()` at module load, which a plain mocked unit test
 * cannot safely do).
 */
import * as admin from "firebase-admin";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { resolveEquipmentIdentityAndRecordTelemetry } from "./p2/identity_handler";
import { recordEquipmentIdentityTelemetryFragment } from "./p2/telemetry_handler";
import { EQUIPMENT_IDENTITY_CALLABLE_OPTIONS } from "./p2/callable_options";

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

/**
 * Both callables below share `EQUIPMENT_IDENTITY_CALLABLE_OPTIONS`
 * (`p2/callable_options.ts`) -- `enforceAppCheck`/`region` are STATIC
 * options Firebase reads once when a function is defined/deployed, never
 * per-request, so deriving them from one shared constant (rather than a
 * second local computation here) is what
 * `__tests__/callable_options_parity.test.ts` can assert never drifts
 * between them (design doc §7, plan step 4: the new telemetry callable must
 * not have a weaker ingress posture than the identity callable it sits
 * beside).
 */
export const equipmentIdentityResolveFromText = onCall(
  EQUIPMENT_IDENTITY_CALLABLE_OPTIONS,
  async (request: CallableRequest) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in to identify equipment.");
    }
    return resolveEquipmentIdentityAndRecordTelemetry(request.auth.uid, request.data);
  },
);

/**
 * P2.G5-readiness step 3a: the mobile-originated telemetry-report callable
 * (design doc §6/§7). See `p2/telemetry_handler.ts` for the request-schema
 * validation and `p2/telemetry_repository.ts`'s `recordMobileTelemetryFragment`
 * for the merge-rule implementation.
 */
export const equipmentIdentityRecordTelemetry = onCall(
  EQUIPMENT_IDENTITY_CALLABLE_OPTIONS,
  async (request: CallableRequest) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in to record equipment identity telemetry.");
    }
    return recordEquipmentIdentityTelemetryFragment(request.auth.uid, request.data);
  },
);
