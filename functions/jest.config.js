/**
 * Jest config for the Cloud Functions unit tests (ticket #9).
 *
 * Pure unit tests: firebase-admin and stripe are jest-mocked, secrets are
 * fake env values set in jest.setup.js. No emulator, no network.
 *
 * Test files live in src/__tests__/ and are excluded from the production
 * tsc build via tsconfig.json "exclude" (so `npm run build` never emits
 * them into lib/).
 */
/** @type {import("ts-jest").JestConfigWithTsJest} */
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  roots: ["<rootDir>/src"],
  testMatch: ["**/__tests__/**/*.test.ts"],
  setupFiles: ["<rootDir>/jest.setup.js"],
};
