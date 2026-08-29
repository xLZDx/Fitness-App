#!/usr/bin/env node
/**
 * MVP1.G4 Step 9 -- CLI entry point for the AI Gateway release guard.
 * Wired into `firebase.json`'s `functions` "default" codebase `predeploy`
 * array, so `firebase deploy --only functions:<anything>` runs this for
 * real, on the releasing operator/session's own `gcloud`/git credentials,
 * before any function is actually uploaded -- the guard's "runs in the
 * canonical release path" DoD requirement, mechanically enforced rather
 * than left as a step someone has to remember.
 *
 * The core logic lives in `functions/src/release_guard.ts` (deps-injected,
 * unit-tested with fake deps -- see `functions/src/__tests__/
 * release_guard.test.ts`). This file supplies the REAL deps: a `gcloud`/git
 * child-process runner, a real filesystem reader, and `Date.now`.
 *
 * Usage: node functions/scripts/run_release_guard.mjs [--project=<id>]
 * Exit code 0 = PASS (release may proceed). Exit code 1 = BLOCK (release
 * guard failed -- do not deploy).
 */
import { spawn } from "node:child_process";
import { readFile as fsReadFile } from "node:fs/promises";
import { fileURLToPath, pathToFileURL } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "..", "..");

// `pathToFileURL` -- a raw Windows drive-letter path ("D:\...") is not a
// valid ESM specifier; dynamic `import()` needs a real `file://` URL.
const { runReleaseGuard } = await import(
  pathToFileURL(path.join(__dirname, "..", "lib", "release_guard.js")).href
);

/**
 * Project resolution order, in priority: `GCLOUD_PROJECT` (the env var
 * Firebase's own CLI sets for predeploy hooks to the ACTUAL resolved deploy
 * target -- the same variable `functions/src/scaling.ts`'s own `projectId()`
 * already reads) > an explicit `--project=` flag (manual/standalone
 * diagnostic runs only) > the hardcoded default (bare `node
 * run_release_guard.mjs` with neither, e.g. a developer poking at it
 * outside any real deploy). GPT-PM round-1 MAJOR: without this, `firebase
 * deploy --project=<some other alias>` would have validated
 * fitness-app-korostelev while Firebase deployed somewhere else entirely --
 * this repo's own `.firebaserc` genuinely has a second, unrelated alias.
 * `release_guard.ts`'s own `checkDeployTarget` is the second half of this
 * fix: it fails the whole gate outright if the resolved project is not this
 * project's one real target, so a wrong project can never silently pass.
 */
function parseArgs(argv) {
  // GCLOUD_PROJECT genuinely takes precedence over an explicit --project=,
  // matching the doc comment above -- round-2 GPT-PM review (INFO) caught
  // an earlier version of this function where --project= always won
  // regardless, contradicting what was already written here.
  const explicit = argv.find((a) => a.startsWith("--project="))?.slice("--project=".length);
  const project = process.env.GCLOUD_PROJECT || explicit || "fitness-app-korostelev";
  return { project };
}

/**
 * On Windows, `gcloud` resolves through a `.cmd` shim, which Node's `spawn`
 * can only execute with `shell: true` (a bare, non-shell spawn of a `.cmd`
 * file fails with `EINVAL` -- confirmed live). `shell: true` does not
 * auto-escape an args ARRAY (Node's own DEP0190 warning), which mis-split a
 * filter argument containing `:` and spaces (`gcloud logging read`'s
 * `INVALID_ARGUMENT: Unparseable filter`). Quoting EVERY token including the
 * command name itself was tried and made things worse -- confirmed live,
 * cmd.exe's resolution of a QUOTED command name stopped finding the real
 * `gcloud.cmd` at all and fell through to an unrelated sibling project's
 * Python venv shim instead. The fix that actually works: leave the command
 * name and simple flag tokens bare (so cmd.exe's normal PATH/PATHEXT search
 * finds the real `gcloud.cmd`), and quote ONLY the specific arguments that
 * contain whitespace or embedded quotes -- exactly what a human typing this
 * command by hand would do.
 */
function needsQuoting(arg) {
  return /[\s"]/.test(arg);
}

function quoteArg(arg) {
  return `"${arg.replace(/"/g, '\\"')}"`;
}

function runCommand(cmd, args, timeoutMs = 30_000) {
  return new Promise((resolve) => {
    const quotedArgs = args.map((a) => (needsQuoting(a) ? quoteArg(a) : a));
    const child = spawn(cmd, quotedArgs, { cwd: REPO_ROOT, shell: true });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => {
      child.kill("SIGKILL");
      resolve({ ok: false, stdout, stderr: stderr || `timed out after ${timeoutMs}ms` });
    }, timeoutMs);
    child.stdout.on("data", (d) => (stdout += d.toString()));
    child.stderr.on("data", (d) => (stderr += d.toString()));
    child.on("error", (e) => {
      clearTimeout(timer);
      resolve({ ok: false, stdout, stderr: String(e) });
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      resolve({ ok: code === 0, stdout, stderr });
    });
  });
}

async function readFile(relPath) {
  try {
    return await fsReadFile(path.join(REPO_ROOT, relPath), "utf8");
  } catch {
    return null;
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const result = await runReleaseGuard({
    project: args.project,
    runCommand,
    readFile,
    now: () => Date.now(),
  });

  console.log(`\nMVP1.G4 Step 9 -- AI Gateway release guard (${args.project})`);
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

main();
