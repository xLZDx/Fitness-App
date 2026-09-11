/**
 * Environment for the e2e suite, set before any p2 module (which lazily
 * calls `admin.firestore()`) is imported -- mirrors functions/jest.e2e.setup.js.
 *
 * This package has no index.ts-level `admin.initializeApp()` call yet
 * (src/index.ts is still the P0 `export {}` scaffold), so this file does
 * both jobs: point the Admin SDK at the emulator, and initialize the app.
 */
// Port is overridable (matches functions/src/__rules__/firestore_rules.test.ts's
// own FIRESTORE_EMULATOR_PORT convention) -- default 8080 matches
// firebase.json's declared emulator port; a machine where 8080 is taken by
// something unrelated (observed: Docker Desktop's backend) can run
// `FIRESTORE_EMULATOR_PORT=8090 FIREBASE_EMULATOR_CONFIG=<alt-config> npm run test:e2e`
// instead, without changing the committed default anyone else relies on.
process.env.FIRESTORE_EMULATOR_HOST = `127.0.0.1:${process.env.FIRESTORE_EMULATOR_PORT || "8080"}`;
process.env.GCLOUD_PROJECT = "demo-equipment-identity-e2e";

const admin = require("firebase-admin");
if (admin.apps.length === 0) {
  admin.initializeApp({ projectId: "demo-equipment-identity-e2e" });
}
