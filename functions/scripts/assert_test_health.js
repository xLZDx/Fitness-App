#!/usr/bin/env node
/**
 * MVP1.G3 OBS-1 item 1 (CI: Functions test-health enforcement).
 *
 * `npm test` already fails on a Jest-config-level "no tests found" (no
 * `--passWithNoTests`), but that only catches a full-zero suite. A CI
 * pipeline where `npm ci` silently no-ops, or a test discovery pattern
 * regresses to matching only some files, can still report a Jest exit code
 * of 0 while running far fewer tests than exist -- exit code alone does not
 * prove the *expected* test set ran. This script reads Jest's own JSON
 * report and asserts explicit floors on suite/test count, not just "greater
 * than zero".
 *
 * Floors are set below the real current count (15 suites / 382 tests as of
 * 2026-08-27) with a buffer generous enough to tolerate an intentional
 * suite/test removal during refactors, but tight enough to catch "half the
 * suite silently didn't run" -- the exact failure class recorded in
 * core/MASTER_PLAN_2026-08-26.md's OBS-1 history table ("Cloud Functions
 * Jest suite had never actually run in this worktree... every 'full suite
 * green' claim covered mobile/ only").
 */
const fs = require("fs");

const REPORT_PATH = process.argv[2] || "jest_result.json";
const MIN_TEST_SUITES = 12;
const MIN_TESTS = 300;

if (!fs.existsSync(REPORT_PATH)) {
  console.error(
    `assert_test_health: ${REPORT_PATH} not found -- Jest did not produce a ` +
      "JSON report at all, which itself means the expected test run did not happen."
  );
  process.exit(1);
}

const report = JSON.parse(fs.readFileSync(REPORT_PATH, "utf8"));
const {
  numTotalTestSuites = 0,
  numTotalTests = 0,
  numPassedTests = 0,
  success,
} = report;

const failures = [];
if (!success) {
  failures.push("Jest itself reported success=false.");
}
if (numTotalTestSuites < MIN_TEST_SUITES) {
  failures.push(
    `only ${numTotalTestSuites} test suite(s) ran, expected at least ${MIN_TEST_SUITES}.`
  );
}
if (numTotalTests < MIN_TESTS) {
  failures.push(
    `only ${numTotalTests} test(s) ran, expected at least ${MIN_TESTS}.`
  );
}
if (numPassedTests !== numTotalTests) {
  failures.push(
    `${numTotalTests - numPassedTests} test(s) did not pass ` +
      `(${numPassedTests}/${numTotalTests} passed).`
  );
}

if (failures.length > 0) {
  console.error("assert_test_health: FAIL");
  for (const f of failures) {
    console.error(`  - ${f}`);
  }
  process.exit(1);
}

console.log(
  `assert_test_health: OK -- ${numTotalTestSuites} suites, ${numTotalTests} tests, all passed.`
);
