/**
 * Real (non-test) dependencies shared by the release-guard entry points:
 * `functions/scripts/run_release_guard.mjs` (the predeploy hook / standalone
 * CLI) and `scripts/deploy/guarded_deploy.mjs` (the supported deploy wrapper).
 * The guard logic itself lives in `functions/src/release_guard.ts`; this file
 * only supplies the gcloud/git child-process runner, a file reader, the current
 * branch reader and the Phase 1 commit-provenance reader.
 */
import { execFileSync, spawn } from "node:child_process";
import { readFile as fsReadFile } from "node:fs/promises";
import { fileURLToPath, pathToFileURL } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const REPO_ROOT = path.resolve(__dirname, "..", "..");

/** Loads the compiled guard library (`functions/lib/release_guard.js`).
 * `pathToFileURL` -- a raw Windows drive-letter path ("D:\...") is not a valid
 * ESM specifier; dynamic `import()` needs a real `file://` URL. */
export async function loadGuardLib() {
  return import(pathToFileURL(path.join(__dirname, "..", "lib", "release_guard.js")).href);
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

export function runCommand(cmd, args, timeoutMs = 30_000) {
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

export async function readFile(relPath) {
  try {
    return await fsReadFile(path.join(REPO_ROOT, relPath), "utf8");
  } catch {
    return null;
  }
}

/** Current git branch via `git rev-parse --abbrev-ref HEAD`; `null` on any
 * failure or empty output. A detached HEAD prints "HEAD", which the guard
 * classifies as an unknown deploy line. Never throws. */
export async function currentBranch() {
  const res = await runCommand("git", ["rev-parse", "--abbrev-ref", "HEAD"], 15_000);
  if (!res.ok) return null;
  const branch = res.stdout.trim();
  return branch.length > 0 ? branch : null;
}

/**
 * Phase 1 commit provenance: true only when HEAD is an ancestor of (or equal
 * to) at least one protected Phase 1 remote-tracking ref, using
 * `git merge-base --is-ancestor HEAD <ref>` (exit 0 = ancestor, 1 = not an
 * ancestor, anything else = git error / missing ref). `execFileSync` with an
 * args array -- no shell. Fails closed: a missing ref, a git failure or a
 * non-contained HEAD all yield false. Does not fetch (no network); a stale
 * remote-tracking ref can only make the check stricter for newer commits.
 * Diagnostics go to stderr. Never throws.
 */
export function makeIsCommitOnProtectedLine(protectedRefs) {
  return async function isCommitOnProtectedLine() {
    for (const ref of protectedRefs) {
      try {
        execFileSync("git", ["merge-base", "--is-ancestor", "HEAD", ref], {
          cwd: REPO_ROOT,
          stdio: "ignore",
          timeout: 15_000,
          windowsHide: true,
        });
        return true;
      } catch (e) {
        const status = e && typeof e === "object" ? e.status : undefined;
        console.error(
          status === 1
            ? `provenance: HEAD is not contained in ${ref}`
            : `provenance: could not evaluate ${ref} (ref missing or git failed)`,
        );
      }
    }
    return false;
  };
}
