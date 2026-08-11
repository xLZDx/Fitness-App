/**
 * Jest config for the Firestore RULES tests (P1a).
 *
 * Separate from `jest.config.js` on purpose. That one mocks `firebase-admin`
 * and stripe and runs with no emulator and no network — mocks are exactly what
 * a rules test must not have, because the thing under test is the emulator's
 * own evaluation of `firestore.rules`. Sharing a config would mean one of the
 * two suites running under the wrong assumptions.
 *
 * It also skips `jest.setup.js`: those fake secrets exist for the Stripe unit
 * tests and mean nothing here.
 *
 * Requires the Firestore emulator on 127.0.0.1:8080 — `npm run test:rules`
 * starts one via `firebase emulators:exec`.
 */
/** @type {import("ts-jest").JestConfigWithTsJest} */
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  roots: ["<rootDir>/src"],
  testMatch: ["**/__rules__/**/*.test.ts"],
  // The emulator's first cold start is slow, and a rules test that times out
  // reads as a failing rule.
  testTimeout: 30000,
};
