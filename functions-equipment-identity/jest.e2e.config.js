/**
 * Jest config for functions-equipment-identity's Firestore-emulator e2e
 * suite (P2.G3). Same split rationale as functions/jest.e2e.config.js:
 * jest.config.js (the default, `npm test`) never touches a real SDK; this
 * config runs the real Admin SDK against a real Firestore emulator, for
 * the parts of P2.G3 that a mock cannot honestly prove -- the derived
 * lookup index, the ported quota primitive, and the session-repository
 * immutability/revocation tests.
 *
 * Requires the Firestore emulator -- `npm run test:e2e` starts it via
 * scripts/run_emulator_tests.js (a verbatim copy of functions/'s own
 * script; P0.G6 deliberately keeps this codebase's dependency tree
 * separate, so this is a duplicated file rather than a cross-package
 * require).
 */
/**
 * Two Jest "projects" (BLOCKER regression, P2.G3 pre-commit review,
 * 2026-09-11): every suite here except one shares `jest.e2e.setup.js`,
 * which calls `admin.initializeApp()` itself for test-harness convenience
 * -- exactly the pre-init that silently masked `src/index.ts` never
 * calling it in production. `admin_init.e2e.test.ts` runs under its own
 * project with NO setupFiles, so nothing but importing `../index` can
 * make Firestore reachable in that one file -- a real regression, not a
 * pass-for-the-wrong-reason green riding the other project's setup.
 */
/** @type {import("ts-jest").JestConfigWithTsJest} */
module.exports = {
  // `testTimeout` is a top-level-only option under Jest's `projects` mode
  // (a per-project copy is silently ignored, with only a "Unknown option"
  // warning to notice by -- confirmed live: the admin-init project's own
  // copy below was accepted by neither jest nor the warning, and its one
  // test then failed against the DEFAULT 5000ms timeout against a real
  // emulator). Set once here so both projects actually get it.
  testTimeout: 60000,
  projects: [
    {
      displayName: "e2e",
      preset: "ts-jest",
      testEnvironment: "node",
      rootDir: __dirname,
      roots: ["<rootDir>/src"],
      testMatch: ["**/__e2e__/**/*.test.ts", "!**/__e2e__/admin_init.e2e.test.ts"],
      setupFiles: ["<rootDir>/jest.e2e.setup.js"],
    },
    {
      displayName: "e2e-admin-init",
      preset: "ts-jest",
      testEnvironment: "node",
      rootDir: __dirname,
      roots: ["<rootDir>/src"],
      testMatch: ["**/__e2e__/admin_init.e2e.test.ts"],
    },
  ],
  // One emulator, one project id -- parallel workers would race each
  // other's fixtures (same reasoning as functions/jest.e2e.config.js).
  maxWorkers: 1,
};
