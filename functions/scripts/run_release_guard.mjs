#!/usr/bin/env node
/**
 * MVP1.G4 Step 9 -- CLI entry point for the AI Gateway release guard.
 * Wired into the `predeploy` array of EVERY deploy target in `firebase.json`
 * (both `functions` codebases, `firestore`, `hosting`; a future `storage`
 * block must carry it too), so `firebase deploy --only <any target>` runs this
 * for real, on the releasing operator/session's own `gcloud`/git credentials,
 * before anything is uploaded or released. The supported operator path is
 * `scripts/deploy/guarded_deploy.mjs`, which runs this first and then deploys.
 *
 * The core logic lives in `functions/src/release_guard.ts` (deps-injected,
 * unit-tested with fake deps -- see `functions/src/__tests__/
 * release_guard.test.ts`). The real deps (gcloud/git runner, file reader,
 * branch reader, Phase 1 provenance reader) live in `./guard_deps.mjs`.
 *
 * Effective project (fail CLOSED): inside a `predeploy` hook the firebase CLI
 * exports the RESOLVED deploy project id as `GCLOUD_PROJECT` (verified in
 * firebase-tools `lib/deploy/lifecycleHooks.js`; an explicit `--project <alias>`
 * is already mapped through `.firebaserc`), so `GCLOUD_PROJECT` is
 * authoritative. For a standalone run an explicit `--project <alias-or-id>` /
 * `--project=` / `-P` flag is accepted (alias resolved via `.firebaserc`). If
 * both are present and differ, or neither is present, the guard BLOCKS -- it
 * never falls back to a hardcoded or `.firebaserc`-default project, because the
 * CLI's own active-project store is per-user and not visible here.
 * `resolveEffectiveProject` (release_guard.ts) holds the pure logic;
 * `checkDeployTarget` then requires the project to match the deploy line.
 *
 * Usage: node functions/scripts/run_release_guard.mjs [--project=<alias-or-id>]
 * Exit code 0 = PASS (release may proceed). Exit code 1 = BLOCK (release
 * guard failed -- do not deploy).
 */
import { readFile, runCommand, currentBranch, loadGuardLib, makeIsCommitOnProtectedLine } from "./guard_deps.mjs";

const lib = await loadGuardLib();
const { runReleaseGuard, resolveEffectiveProject, PROTECTED_PHASE1_REFS } = lib;

async function main() {
  const resolved = resolveEffectiveProject({
    env: process.env,
    argv: process.argv.slice(2),
    firebaserc: await readFile(".firebaserc"),
  });
  if (!resolved.ok) {
    console.log("\nMVP1.G4 Step 9 -- AI Gateway release guard");
    console.log(`[FAIL] Effective deploy project could not be determined`);
    console.log(`       ${resolved.detail}`);
    console.log("\nVERDICT: BLOCK\n");
    console.error("Release guard BLOCKED this release. Fix the failing/unavailable check(s) above before deploying.");
    process.exitCode = 1;
    return;
  }
  const project = resolved.project;

  const result = await runReleaseGuard({
    project,
    runCommand,
    readFile,
    now: () => Date.now(),
    currentBranch,
    isCommitOnProtectedLine: makeIsCommitOnProtectedLine(PROTECTED_PHASE1_REFS),
  });

  console.log(`\nMVP1.G4 Step 9 -- AI Gateway release guard (${project}, from ${resolved.source})`);
  console.log(`deploy line: ${result.line} (branch: ${result.branch ?? "unknown"}), project: ${result.project}`);
  console.log(`generatedAt: ${result.generatedAt}\n`);
  for (const check of result.checks) {
    const marker = check.status === "OK" ? "OK  " : check.status === "FAILED" ? "FAIL" : "N/A ";
    console.log(`[${marker}] ${check.name}`);
    console.log(`       ${check.detail}`);
  }
  console.log(`\nVERDICT: ${result.verdict}\n`);

  if (result.verdict !== "PASS") {
    console.error("Release guard BLOCKED this release. Fix the failing/unavailable check(s) above before deploying.");
    process.exitCode = 1;
    return;
  }
  console.log("Release guard PASSED. Proceeding.");
}

main().catch((e) => {
  // Any unexpected failure blocks the release (fail closed).
  console.error(`Release guard crashed: ${e && e.stack ? e.stack : e}`);
  process.exitCode = 1;
});
