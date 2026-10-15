#!/usr/bin/env node
/**
 * Supported way to deploy anything from this repository.
 *
 *   node scripts/deploy/guarded_deploy.mjs [firebase deploy args...]
 *   e.g. node scripts/deploy/guarded_deploy.mjs --only firestore:rules
 *
 * What it does, in order (any failure blocks, nothing is deployed):
 *   1. Builds the guard library (`npm --prefix functions run build`) so the
 *      guard that runs is the current source, not a stale `functions/lib`.
 *   2. Refuses `--config`/`-c` (a different firebase config carries different,
 *      possibly missing, guard hooks).
 *   3. Determines the project the deploy will hit. An explicit
 *      `--project`/`-P` is honoured (alias resolved via `.firebaserc`); when
 *      absent, the project is derived from the deploy line (phase1 ->
 *      production, phase2 -> alias `phase2`) and passed to the CLI explicitly,
 *      so the CLI's per-user active-project store can never redirect the deploy.
 *   4. Runs `functions/scripts/run_release_guard.mjs` with `GCLOUD_PROJECT` set
 *      to that project (the same variable the CLI sets for predeploy hooks).
 *   5. Only on PASS runs `firebase deploy --project <id> <args>` using the
 *      repo-pinned firebase-tools. The `predeploy` guard hooks in
 *      `firebase.json` then run again inside the CLI as an independent
 *      backstop (deliberate duplication).
 *
 * Residual limit: this is a local guard. It cannot stop someone who calls the
 * firebase CLI directly with a different config or credentials; real
 * enforcement needs separate production deploy credentials / protected CI
 * (operator-owned, open item in docs/phase2/split/BACKEND_SEPARATION.md).
 */
import { spawn, spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import {
  REPO_ROOT,
  readFile,
  currentBranch,
  runCommand,
  loadGuardLib,
  makeIsCommitOnProtectedLine,
} from "../../functions/scripts/guard_deps.mjs";

const FIREBASE_BIN = path.join(REPO_ROOT, "functions", "node_modules", "firebase-tools", "lib", "bin", "firebase.js");
const GUARD_SCRIPT = path.join(REPO_ROOT, "functions", "scripts", "run_release_guard.mjs");

function block(message) {
  console.error(`\nguarded_deploy: BLOCKED -- ${message}\n`);
  process.exit(1);
}

function run(cmd, args, options) {
  return new Promise((resolve) => {
    const child = spawn(cmd, args, { cwd: REPO_ROOT, stdio: "inherit", ...options });
    child.on("error", () => resolve(1));
    child.on("exit", (code) => resolve(code === null ? 1 : code));
  });
}

async function main() {
  // 1. Build the guard library (npm is a .cmd shim on Windows -> shell).
  const build = spawnSync("npm", ["--prefix", "functions", "run", "build"], {
    cwd: REPO_ROOT,
    stdio: "inherit",
    shell: true,
  });
  if (build.status !== 0) block("could not build functions/lib (the guard library); fix the build first");

  const lib = await loadGuardLib();
  const { parseDeployArgs, resolveEffectiveProject, resolveDeployTarget, PROTECTED_PHASE1_REFS } = lib;

  // 2. Arguments.
  const parsed = parseDeployArgs(process.argv.slice(2));
  if (parsed.hasConfigFlag) block("--config/-c is not allowed: a different firebase config bypasses the guard hooks");
  if (!existsSync(FIREBASE_BIN)) block(`repo-pinned firebase-tools not found at ${FIREBASE_BIN} (run npm ci in functions)`);

  // 3. Project.
  const firebaserc = await readFile(".firebaserc");
  let project;
  if (parsed.projects.length === 0) {
    const target = await resolveDeployTarget({
      project: "",
      runCommand,
      readFile,
      now: () => Date.now(),
      currentBranch,
      isCommitOnProtectedLine: makeIsCommitOnProtectedLine(PROTECTED_PHASE1_REFS),
    });
    if (!target.ok) block(target.detail);
    project = target.allowedProject;
    console.log(`guarded_deploy: no --project given; using the ${target.line} line project "${project}" explicitly`);
  } else {
    const resolved = resolveEffectiveProject({ env: {}, argv: process.argv.slice(2), firebaserc });
    if (!resolved.ok) block(resolved.detail);
    project = resolved.project;
  }

  // 4. Guard (same code as the predeploy hooks).
  const guardCode = await run(process.execPath, [GUARD_SCRIPT], { env: { ...process.env, GCLOUD_PROJECT: project } });
  if (guardCode !== 0) block("the release guard did not pass (see output above)");

  // 5. Deploy with the project passed explicitly.
  const deployCode = await run(process.execPath, [FIREBASE_BIN, "deploy", "--project", project, ...parsed.rest]);
  process.exitCode = deployCode;
}

main().catch((e) => block(`unexpected failure: ${e && e.stack ? e.stack : e}`));
