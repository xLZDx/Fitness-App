/**
 * Same shape as functions/jest.config.js. Pure unit tests only -- this
 * package makes no network/SDK calls at all yet (see src/index.ts), so
 * there is nothing here to mock.
 */
/** @type {import("ts-jest").JestConfigWithTsJest} */
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  roots: ["<rootDir>/src"],
  testMatch: ["**/__tests__/**/*.test.ts"],
};
