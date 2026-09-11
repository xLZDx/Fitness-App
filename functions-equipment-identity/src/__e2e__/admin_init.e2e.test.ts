/**
 * BLOCKER regression (P2.G3 pre-commit review, 2026-09-11): every other
 * e2e suite in this package runs under `jest.e2e.setup.js`, which calls
 * `admin.initializeApp()` itself for test-harness convenience -- that
 * pre-init silently masked the fact that `src/index.ts`, the real
 * production entrypoint, never called it at all. A real deployment would
 * have failed on its very first Firestore-touching request while every
 * unit and e2e test stayed green. This file runs under its OWN Jest
 * "project" (`jest.e2e.config.js`'s `e2e-admin-init`), with no
 * `setupFiles` -- nothing but importing `../index` below can make
 * Firestore reachable here. If `admin.initializeApp()` is ever removed
 * from index.ts again, this specific assertion fails with a real
 * "no Firebase App" / connection error, not a silent pass.
 *
 *     npm run test:e2e
 */
// Set before any p2 module is imported -- deliberately everything
// jest.e2e.setup.js does EXCEPT the admin.initializeApp() call itself,
// since proving THAT call is unnecessary here is the entire point.
process.env.FIRESTORE_EMULATOR_HOST = `127.0.0.1:${process.env.FIRESTORE_EMULATOR_PORT || "8080"}`;
process.env.GCLOUD_PROJECT = "demo-equipment-identity-e2e";

import * as admin from "firebase-admin";

describe("production entrypoint initializes the Admin SDK itself (BLOCKER regression)", () => {
  afterAll(async () => {
    if (admin.apps.length > 0) {
      await admin.app().delete();
    }
  });

  it("makes Firestore reachable after importing index.ts, with no external pre-init", async () => {
    expect(admin.apps.length).toBe(0);

    await import("../index");

    expect(admin.apps.length).toBeGreaterThan(0);

    // The actual failure mode the BLOCKER describes: without
    // admin.initializeApp() somewhere before this point, this call throws
    // ("The default Firebase app does not exist" / no credentials), not a
    // normal Firestore-level response. (Collection names bracketed in
    // double underscores are reserved by Firestore itself -- avoided here
    // so the probe query is valid, not just present.)
    const snap = await admin.firestore().doc("admin_init_probe/x").get();
    expect(snap.exists).toBe(false);
  });
});
