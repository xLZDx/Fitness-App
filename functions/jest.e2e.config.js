/**
 * Jest config for the account-deletion e2e (P1f).
 *
 * Third config, and the reason is the same one that split the rules tests out
 * of `jest.config.js`: what each suite is allowed to mock is the whole point of
 * it.
 *
 *   - `jest.config.js`      mocks firebase-admin. Fast, offline, and unable to
 *                           say anything about what Firestore actually does.
 *   - `jest.rules.config.js` mocks nothing and drives the emulator as a CLIENT.
 *   - this one              mocks only `stripe`, and runs the real Admin SDK
 *                           against a real emulator. `recursiveDelete` is a
 *                           server-side traversal; the unit test replaces it
 *                           with `jest.fn()`, so nothing anywhere proved it
 *                           reaches a nested subcollection — or stopped at one
 *                           user's data.
 *
 * Requires the Firestore and Auth emulators — `npm run test:e2e` starts both.
 */
/** @type {import("ts-jest").JestConfigWithTsJest} */
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  roots: ["<rootDir>/src"],
  testMatch: ["**/__e2e__/**/*.test.ts"],
  setupFiles: ["<rootDir>/jest.e2e.setup.js"],
  // Seeding, deleting and re-reading several collections per test against a
  // cold emulator is slower than an in-memory mock by orders of magnitude.
  testTimeout: 60000,
  // The suite shares one emulator and one project id. Parallel workers would
  // delete each other's fixtures and fail in ways that read as deletion bugs.
  maxWorkers: 1,
};
