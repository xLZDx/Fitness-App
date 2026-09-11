/**
 * Same shape as functions/jest.config.js. Pure unit tests only -- every
 * collaborator that does real Firestore I/O is mocked in this suite
 * (`p2/__tests__/orchestrator.test.ts` et al.); the real Admin SDK path is
 * exercised only under `jest.e2e.config.js`, against a real emulator.
 */
/** @type {import("ts-jest").JestConfigWithTsJest} */
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  roots: ["<rootDir>/src"],
  testMatch: ["**/__tests__/**/*.test.ts"],
};
