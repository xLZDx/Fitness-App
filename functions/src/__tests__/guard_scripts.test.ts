/**
 * Real-process tests for the three ESM entry points of the deploy guard:
 *
 *   - functions/scripts/guard_deps.mjs       (git/gcloud runner, branch + provenance readers)
 *   - functions/scripts/run_release_guard.mjs (predeploy hook / standalone CLI)
 *   - scripts/deploy/guarded_deploy.mjs      (supported deploy wrapper)
 *
 * Nothing here deploys anything and nothing touches the real repository's git
 * state or a real GCP project:
 *
 *   - The scripts are COPIED into a throw-away fixture root (their REPO_ROOT is
 *     derived from their own location), next to a throw-away git repository, so
 *     branch names, remote-tracking refs and HEAD ancestry are fully controlled.
 *   - The guard library the scripts load (`functions/lib/release_guard.js`) is the
 *     REAL guard source, transpiled per file with `ts.transpileModule` into the
 *     fixture (same compiler ts-jest uses; no `tsc` build of the repository).
 *   - `gcloud` is a fake executable placed first on PATH that logs its call and
 *     exits 1, so a run that reaches the gcloud checks can never hit real GCP
 *     (those checks come back UNAVAILABLE -> verdict BLOCK) and the log proves
 *     whether gcloud was reached at all.
 *   - The firebase CLI the wrapper spawns is a fake `firebase.js` that records its
 *     argv and exits with a configurable code. For wrapper tests that need the guard
 *     step to PASS, the fixture's `run_release_guard.mjs` is replaced by a stub that
 *     records `GCLOUD_PROJECT` and exits with a configurable code; tests that prove
 *     the guard blocks use the REAL `run_release_guard.mjs`.
 *
 * NOT covered here: a real `firebase deploy --dry-run` predeploy hook run, real
 * gcloud output, or the CLI setting GCLOUD_PROJECT itself (see the change record).
 */
import { execFileSync, spawnSync } from "child_process";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import * as ts from "typescript";

jest.setTimeout(120_000);

const SRC_DIR = path.resolve(__dirname, "..");
const FUNCTIONS_DIR = path.resolve(SRC_DIR, "..");
const REPO_DIR = path.resolve(FUNCTIONS_DIR, "..");

const PROD = "fitness-app-korostelev";
const PHASE2_PROJECT = "fitness-app-phase2-test";
const PHASE1_REF = "refs/remotes/origin/phase1/main";
const MASTER_REF = "refs/remotes/origin/master";

const tmpRoots: string[] = [];
let libTemplate = "";

function mkTmp(prefix: string): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  tmpRoots.push(dir);
  return dir;
}

function transpileTree(srcDir: string, outDir: string): void {
  for (const entry of fs.readdirSync(srcDir, { withFileTypes: true })) {
    if (entry.name === "__tests__") continue;
    const from = path.join(srcDir, entry.name);
    if (entry.isDirectory()) {
      transpileTree(from, path.join(outDir, entry.name));
    } else if (entry.name.endsWith(".ts") && !entry.name.endsWith(".d.ts")) {
      const out = ts.transpileModule(fs.readFileSync(from, "utf8"), {
        compilerOptions: {
          module: ts.ModuleKind.CommonJS,
          target: ts.ScriptTarget.ES2020,
          esModuleInterop: true,
        },
      });
      fs.mkdirSync(outDir, { recursive: true });
      fs.writeFileSync(path.join(outDir, entry.name.replace(/\.ts$/, ".js")), out.outputText);
    }
  }
}

beforeAll(() => {
  libTemplate = mkTmp("guard-lib-");
  transpileTree(SRC_DIR, libTemplate);
});

afterAll(() => {
  for (const dir of tmpRoots) fs.rmSync(dir, { recursive: true, force: true });
});

// ---------------------------------------------------------------- fixture

interface Fixture {
  root: string;
  bin: string;
  gcloudLog: string;
  firebaseLog: string;
  guardSeen: string;
}

const STUB_GUARD = `
import fs from "node:fs";
fs.writeFileSync(new URL("../../guard_seen.json", import.meta.url), JSON.stringify({ gcloudProject: process.env.GCLOUD_PROJECT ?? null, argv: process.argv.slice(2) }));
process.exit(Number(process.env.FAKE_GUARD_EXIT ?? 0));
`;

const FAKE_FIREBASE = `
const fs = require("fs");
const path = require("path");
const root = path.resolve(__dirname, "..", "..", "..", "..", "..");
fs.appendFileSync(path.join(root, "firebase_calls.jsonl"), JSON.stringify(process.argv.slice(2)) + "\\n");
process.exit(Number(process.env.FAKE_FIREBASE_EXIT || 0));
`;

const DRIVER = `
import * as d from "./functions/scripts/guard_deps.mjs";
const [cmd, arg] = process.argv.slice(2);
let r;
if (cmd === "provenance") r = await d.makeIsCommitOnProtectedLine(JSON.parse(arg))();
else if (cmd === "branch") r = await d.currentBranch();
else if (cmd === "readFile") r = await d.readFile(arg);
else if (cmd === "root") r = d.REPO_ROOT;
console.log("RESULT=" + JSON.stringify(r === undefined ? null : r));
`;

function makeFixture(opts: { stubGuard?: boolean; firebase?: boolean; lib?: boolean; buildExit?: number } = {}): Fixture {
  const root = mkTmp("guard-fx-");
  const w = (rel: string, content: string): void => {
    const p = path.join(root, rel);
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, content);
  };
  const copy = (fromAbs: string, rel: string): void => w(rel, fs.readFileSync(fromAbs, "utf8"));

  copy(path.join(FUNCTIONS_DIR, "scripts", "guard_deps.mjs"), "functions/scripts/guard_deps.mjs");
  copy(path.join(FUNCTIONS_DIR, "scripts", "run_release_guard.mjs"), "functions/scripts/run_release_guard.mjs");
  copy(path.join(REPO_DIR, "scripts", "deploy", "guarded_deploy.mjs"), "scripts/deploy/guarded_deploy.mjs");
  if (opts.stubGuard) w("functions/scripts/run_release_guard.mjs", STUB_GUARD);
  if (opts.lib !== false) fs.cpSync(libTemplate, path.join(root, "functions", "lib"), { recursive: true });

  w("functions/package.json", JSON.stringify({ name: "fx-functions", private: true, scripts: { build: "node build.js" } }));
  w("functions/build.js", `require("fs").appendFileSync("build.log", "x"); process.exit(${opts.buildExit ?? 0});\n`);
  if (opts.firebase !== false) w("functions/node_modules/firebase-tools/lib/bin/firebase.js", FAKE_FIREBASE);
  w("driver.mjs", DRIVER);

  const bin = path.join(root, "bin");
  w("bin/gcloud.cmd", '@echo off\r\necho %~1 %~2 >> "%~dp0..\\gcloud_calls.log"\r\nexit /b 1\r\n');
  w("bin/gcloud", '#!/bin/sh\necho "$1 $2" >> "$(dirname "$0")/../gcloud_calls.log"\nexit 1\n');
  fs.chmodSync(path.join(bin, "gcloud"), 0o755);

  return {
    root,
    bin,
    gcloudLog: path.join(root, "gcloud_calls.log"),
    firebaseLog: path.join(root, "firebase_calls.jsonl"),
    guardSeen: path.join(root, "guard_seen.json"),
  };
}

function git(root: string, ...args: string[]): string {
  return execFileSync(
    "git",
    ["-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgsign=false", ...args],
    { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
  ).trim();
}

function initRepo(fx: Fixture, branch: string): void {
  git(fx.root, "init", "-q");
  git(fx.root, "symbolic-ref", "HEAD", `refs/heads/${branch}`);
  git(fx.root, "commit", "-q", "--allow-empty", "-m", "A");
}

const commit = (fx: Fixture, msg: string): string => {
  git(fx.root, "commit", "-q", "--allow-empty", "-m", msg);
  return git(fx.root, "rev-parse", "HEAD");
};
const head = (fx: Fixture): string => git(fx.root, "rev-parse", "HEAD");
const setRef = (fx: Fixture, ref: string, sha: string): void => {
  git(fx.root, "update-ref", ref, sha);
};

function childEnv(fx: Fixture, extra: Record<string, string> = {}): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = {};
  for (const [k, v] of Object.entries(process.env)) {
    const upper = k.toUpperCase();
    if (upper === "PATH" || upper === "GCLOUD_PROJECT" || upper === "FIREBASE_PROJECT" || upper === "NODE_PATH") continue;
    if (upper.startsWith("FAKE_")) continue;
    env[k] = v;
  }
  const pathKey = Object.keys(process.env).find((k) => k.toUpperCase() === "PATH") ?? "PATH";
  env[pathKey] = `${fx.bin}${path.delimiter}${process.env[pathKey] ?? ""}`;
  env.NODE_PATH = path.join(FUNCTIONS_DIR, "node_modules");
  return { ...env, ...extra };
}

interface Run {
  status: number | null;
  stdout: string;
  stderr: string;
}

function runNode(fx: Fixture, script: string, args: string[], extraEnv: Record<string, string> = {}): Run {
  const r = spawnSync(process.execPath, [path.join(fx.root, script), ...args], {
    cwd: fx.root,
    env: childEnv(fx, extraEnv),
    encoding: "utf8",
    timeout: 90_000,
  });
  return { status: r.status, stdout: r.stdout ?? "", stderr: r.stderr ?? "" };
}

const runGuard = (fx: Fixture, args: string[] = [], env: Record<string, string> = {}): Run =>
  runNode(fx, "functions/scripts/run_release_guard.mjs", args, env);
const runDeploy = (fx: Fixture, args: string[] = [], env: Record<string, string> = {}): Run =>
  runNode(fx, "scripts/deploy/guarded_deploy.mjs", args, env);

function driver(fx: Fixture, cmd: string, arg = ""): { result: unknown; stderr: string; status: number | null } {
  const r = runNode(fx, "driver.mjs", [cmd, arg]);
  const line = r.stdout.split(/\r?\n/).find((l) => l.startsWith("RESULT="));
  if (line === undefined) throw new Error(`driver produced no RESULT line: ${r.stdout} ${r.stderr}`);
  return { result: JSON.parse(line.slice("RESULT=".length)), stderr: r.stderr, status: r.status };
}

const readLines = (file: string): string[] =>
  fs.existsSync(file) ? fs.readFileSync(file, "utf8").split(/\r?\n/).filter((l) => l.trim().length > 0) : [];
const firebaseCalls = (fx: Fixture): string[][] => readLines(fx.firebaseLog).map((l) => JSON.parse(l) as string[]);
const writeRc = (fx: Fixture, projects: Record<string, string>): void =>
  fs.writeFileSync(path.join(fx.root, ".firebaserc"), JSON.stringify({ projects }));

// ------------------------------------------------------------- guard_deps.mjs

describe("guard_deps.mjs", () => {
  test("REPO_ROOT is derived from the script location (two levels above functions/scripts)", () => {
    const fx = makeFixture();
    const { result } = driver(fx, "root");
    expect(path.resolve(result as string)).toBe(path.resolve(fx.root));
  });

  describe("makeIsCommitOnProtectedLine (real git in a throw-away repo)", () => {
    const prove = (fx: Fixture, refs: string[]) => driver(fx, "provenance", JSON.stringify(refs));

    test("HEAD equals the protected ref -> true", () => {
      const fx = makeFixture();
      initRepo(fx, "phase1/main");
      setRef(fx, PHASE1_REF, head(fx));
      expect(prove(fx, [PHASE1_REF]).result).toBe(true);
    });

    test("HEAD is an ancestor of the protected ref (ref is ahead) -> true", () => {
      const fx = makeFixture();
      initRepo(fx, "phase1/main");
      const a = head(fx);
      const b = commit(fx, "B");
      setRef(fx, PHASE1_REF, b);
      git(fx.root, "checkout", "-q", "--detach", a);
      expect(prove(fx, [PHASE1_REF]).result).toBe(true);
    });

    test("HEAD has a commit the protected ref lacks (a local branch called phase1/x holding extra work) -> false", () => {
      const fx = makeFixture();
      initRepo(fx, "phase1/x");
      setRef(fx, PHASE1_REF, head(fx));
      commit(fx, "phase2-only work");
      const r = prove(fx, [PHASE1_REF]);
      expect(r.result).toBe(false);
      expect(r.stderr).toContain(`provenance: HEAD is not contained in ${PHASE1_REF}`);
    });

    test("diverged history (HEAD and the ref are siblings) -> false", () => {
      const fx = makeFixture();
      initRepo(fx, "phase1/main");
      const a = head(fx);
      const c = commit(fx, "C");
      setRef(fx, PHASE1_REF, c);
      git(fx.root, "checkout", "-q", "--detach", a);
      commit(fx, "D");
      expect(prove(fx, [PHASE1_REF]).result).toBe(false);
    });

    test("the protected ref does not exist -> false, reported as 'could not evaluate' (not as 'not contained')", () => {
      const fx = makeFixture();
      initRepo(fx, "phase1/main");
      const r = prove(fx, [PHASE1_REF]);
      expect(r.result).toBe(false);
      expect(r.stderr).toContain(`provenance: could not evaluate ${PHASE1_REF}`);
      expect(r.stderr).not.toContain("is not contained");
    });

    test("any one protected ref is enough: first missing, second contains HEAD -> true", () => {
      const fx = makeFixture();
      initRepo(fx, "master");
      setRef(fx, MASTER_REF, head(fx));
      expect(prove(fx, [PHASE1_REF, MASTER_REF]).result).toBe(true);
    });

    test("first ref does not contain HEAD, second does -> true; neither contains -> false", () => {
      const fx = makeFixture();
      initRepo(fx, "phase1/main");
      const a = head(fx);
      setRef(fx, MASTER_REF, a);
      const b = commit(fx, "B");
      git(fx.root, "update-ref", PHASE1_REF, a); // HEAD (B) is NOT in this one
      setRef(fx, MASTER_REF, b); // but is in this one
      expect(prove(fx, [PHASE1_REF, MASTER_REF]).result).toBe(true);
      setRef(fx, MASTER_REF, a);
      expect(prove(fx, [PHASE1_REF, MASTER_REF]).result).toBe(false);
    });

    test("an empty protected-ref list can never verify -> false", () => {
      const fx = makeFixture();
      initRepo(fx, "phase1/main");
      expect(prove(fx, []).result).toBe(false);
    });

    test("a local branch with the protected NAME is not a remote-tracking ref -> false", () => {
      const fx = makeFixture();
      initRepo(fx, "phase1/main"); // refs/heads/phase1/main exists, refs/remotes/origin/phase1/main does not
      expect(prove(fx, [PHASE1_REF]).result).toBe(false);
    });

    test("not a git repository -> false (never throws)", () => {
      const fx = makeFixture(); // no git init
      const r = prove(fx, [PHASE1_REF]);
      expect(r.status).toBe(0);
      expect(r.result).toBe(false);
    });
  });

  describe("currentBranch / readFile", () => {
    test("returns the checked-out branch name", () => {
      const fx = makeFixture();
      initRepo(fx, "phase2/s00-split-docs");
      expect(driver(fx, "branch").result).toBe("phase2/s00-split-docs");
    });

    test("a detached HEAD is reported as the literal HEAD (classified as an unknown line by the guard)", () => {
      const fx = makeFixture();
      initRepo(fx, "phase1/main");
      git(fx.root, "checkout", "-q", "--detach", head(fx));
      expect(driver(fx, "branch").result).toBe("HEAD");
    });

    test("not a git repository -> null", () => {
      const fx = makeFixture();
      expect(driver(fx, "branch").result).toBeNull();
    });

    test("readFile returns the content of an existing repo file and null for a missing one", () => {
      const fx = makeFixture();
      writeRc(fx, { default: PROD });
      expect(JSON.parse(driver(fx, "readFile", ".firebaserc").result as string)).toEqual({ projects: { default: PROD } });
      expect(driver(fx, "readFile", "does/not/exist.json").result).toBeNull();
    });
  });
});

// ------------------------------------------------------- run_release_guard.mjs

describe("run_release_guard.mjs (real script, real guard library, fake gcloud)", () => {
  test("no GCLOUD_PROJECT and no --project: BLOCK, exit 1, project-undeterminable, gcloud never reached", () => {
    const fx = makeFixture();
    initRepo(fx, "phase1/main");
    const r = runGuard(fx);
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("project-undeterminable");
    expect(r.stdout).toContain("VERDICT: BLOCK");
    expect(readLines(fx.gcloudLog)).toEqual([]);
  });

  test("it does not fall back to the .firebaserc default alias (which maps to production)", () => {
    const fx = makeFixture();
    initRepo(fx, "phase1/main");
    writeRc(fx, { default: PROD });
    const r = runGuard(fx);
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("project-undeterminable");
    expect(readLines(fx.gcloudLog)).toEqual([]);
  });

  test("a --project flag without a value blocks even when GCLOUD_PROJECT is set", () => {
    const fx = makeFixture();
    initRepo(fx, "phase1/main");
    const r = runGuard(fx, ["--project"], { GCLOUD_PROJECT: PROD });
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("project-undeterminable");
    expect(readLines(fx.gcloudLog)).toEqual([]);
  });

  test("GCLOUD_PROJECT disagreeing with --project blocks with project-conflict, gcloud never reached", () => {
    const fx = makeFixture();
    initRepo(fx, "phase1/main");
    const r = runGuard(fx, ["--project=other-project"], { GCLOUD_PROJECT: PROD });
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("project-conflict");
    expect(readLines(fx.gcloudLog)).toEqual([]);
  });

  test("phase1 branch whose HEAD is on the protected ref: deploy-target check is OK, source is GCLOUD_PROJECT; verdict still BLOCK only because fake gcloud is unavailable", () => {
    const fx = makeFixture();
    initRepo(fx, "phase1/main");
    setRef(fx, PHASE1_REF, head(fx));
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.stdout).toContain(`(${PROD}, from GCLOUD_PROJECT)`);
    expect(r.stdout).toMatch(/\[OK {2}\] Deploy target is this project's real Firebase project/);
    expect(r.stdout).toContain(`line = phase1, project = ${PROD}`);
    expect(r.stdout).toContain("VERDICT: BLOCK");
    expect(r.status).toBe(1);
    // The guard really went on to the gcloud checks, and only ever through the fake.
    expect(readLines(fx.gcloudLog).length).toBeGreaterThan(0);
  });

  test("explicit --project <alias> is mapped through .firebaserc and reported as the --project source", () => {
    const fx = makeFixture();
    initRepo(fx, "phase2/x");
    writeRc(fx, { default: PROD, phase2: PHASE2_PROJECT });
    const r = runGuard(fx, ["--project", "phase2"]);
    expect(r.stdout).toContain(`(${PHASE2_PROJECT}, from --project)`);
    expect(r.stdout).toContain(`line = phase2, project = ${PHASE2_PROJECT}`);
  });

  test("phase1-named branch whose HEAD has commits outside the protected ref -> phase1-provenance-unverified, exit 1", () => {
    const fx = makeFixture();
    initRepo(fx, "phase1/x");
    setRef(fx, PHASE1_REF, head(fx));
    commit(fx, "phase2 work hidden under a phase1 branch name");
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.status).toBe(1);
    expect(r.stdout).toMatch(/\[FAIL\] Deploy target is this project's real Firebase project/);
    expect(r.stdout).toContain("phase1-provenance-unverified");
    expect(r.stderr).toContain("provenance: HEAD is not contained in");
  });

  test("phase1 branch with no protected remote-tracking ref at all -> phase1-provenance-unverified", () => {
    const fx = makeFixture();
    initRepo(fx, "phase1/main");
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("phase1-provenance-unverified");
  });

  test("an explicit production project from a phase2/* branch is blocked (phase2-project-mismatch)", () => {
    const fx = makeFixture();
    initRepo(fx, "phase2/x");
    writeRc(fx, { default: PROD, phase2: PHASE2_PROJECT });
    for (const [args, env] of [
      [[], { GCLOUD_PROJECT: PROD }],
      [["--project", "default"], {}],
      [[`--project=${PROD}`], {}],
    ] as const) {
      const r = runGuard(fx, [...args], { ...env });
      expect(r.status).toBe(1);
      expect(r.stdout).toMatch(/\[FAIL\] Deploy target is this project's real Firebase project/);
      expect(r.stdout).toContain("phase2-project-mismatch");
    }
  });

  test("a branch that is not on any deploy line -> deploy-line-unknown", () => {
    const fx = makeFixture();
    initRepo(fx, "feature/x");
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("deploy-line-unknown");
  });

  test("an unexpected crash (guard library missing) fails closed with a non-zero exit and never reaches gcloud", () => {
    const fx = makeFixture({ lib: false });
    initRepo(fx, "phase1/main");
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.status).not.toBe(0);
    expect(readLines(fx.gcloudLog)).toEqual([]);
  });
});

// -------------------------------------------------------- guarded_deploy.mjs

describe("guarded_deploy.mjs (real wrapper, fake firebase CLI)", () => {
  test.each([
    ["--config x.json", ["--config", "x.json"]],
    ["--config=x.json", ["--config=x.json"]],
    ["-c x.json", ["-c", "x.json"]],
  ] as const)("refuses %s and does not spawn firebase", (_label, args) => {
    const fx = makeFixture({ stubGuard: true });
    initRepo(fx, "phase1/main");
    setRef(fx, PHASE1_REF, head(fx));
    const r = runDeploy(fx, [...args, "--only", "hosting"]);
    expect(r.status).toBe(1);
    expect(r.stderr).toContain("guarded_deploy: BLOCKED");
    expect(r.stderr).toContain("--config/-c is not allowed");
    expect(firebaseCalls(fx)).toEqual([]);
    expect(fs.existsSync(fx.guardSeen)).toBe(false);
  });

  test("fails closed when the project is undeterminable (--project without a value); neither guard nor firebase runs", () => {
    const fx = makeFixture({ stubGuard: true });
    initRepo(fx, "phase1/main");
    setRef(fx, PHASE1_REF, head(fx));
    const r = runDeploy(fx, ["--only", "hosting", "--project"]);
    expect(r.status).toBe(1);
    expect(r.stderr).toContain("project-undeterminable");
    expect(firebaseCalls(fx)).toEqual([]);
    expect(fs.existsSync(fx.guardSeen)).toBe(false);
  });

  test("fails closed on conflicting --project values", () => {
    const fx = makeFixture({ stubGuard: true });
    initRepo(fx, "phase1/main");
    const r = runDeploy(fx, ["--project", "a", "--project", "b"]);
    expect(r.status).toBe(1);
    expect(r.stderr).toContain("project-conflict");
    expect(firebaseCalls(fx)).toEqual([]);
  });

  test("no --project on a branch that is not on a deploy line: deploy-line-unknown, nothing spawned", () => {
    const fx = makeFixture({ stubGuard: true });
    initRepo(fx, "feature/x");
    const r = runDeploy(fx, ["--only", "hosting"]);
    expect(r.status).toBe(1);
    expect(r.stderr).toContain("deploy-line-unknown");
    expect(firebaseCalls(fx)).toEqual([]);
    expect(fs.existsSync(fx.guardSeen)).toBe(false);
  });

  test("no --project on a phase1-named branch with unverified provenance: blocked before the guard and before firebase", () => {
    const fx = makeFixture({ stubGuard: true });
    initRepo(fx, "phase1/x");
    setRef(fx, PHASE1_REF, head(fx));
    commit(fx, "extra");
    const r = runDeploy(fx, ["--only", "functions:default"]);
    expect(r.status).toBe(1);
    expect(r.stderr).toContain("phase1-provenance-unverified");
    expect(firebaseCalls(fx)).toEqual([]);
    expect(fs.existsSync(fx.guardSeen)).toBe(false);
  });

  test("REAL guard blocks an explicit production project from a phase2 branch, so firebase is never spawned", () => {
    const fx = makeFixture(); // real run_release_guard.mjs + fake gcloud
    initRepo(fx, "phase2/x");
    writeRc(fx, { default: PROD, phase2: PHASE2_PROJECT });
    const r = runDeploy(fx, ["--project", PROD, "--only", "functions:default"]);
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("phase2-project-mismatch");
    expect(r.stderr).toContain("the release guard did not pass");
    expect(firebaseCalls(fx)).toEqual([]);
  });

  test("a missing repo-pinned firebase CLI blocks (nothing to run) instead of falling back to a global firebase", () => {
    const fx = makeFixture({ stubGuard: true, firebase: false });
    initRepo(fx, "phase1/main");
    setRef(fx, PHASE1_REF, head(fx));
    const r = runDeploy(fx, ["--only", "hosting"]);
    expect(r.status).toBe(1);
    expect(r.stderr).toContain("repo-pinned firebase-tools not found");
    expect(fs.existsSync(fx.guardSeen)).toBe(false);
  });

  test("a failing build blocks before anything else", () => {
    const fx = makeFixture({ stubGuard: true, buildExit: 1 });
    initRepo(fx, "phase1/main");
    setRef(fx, PHASE1_REF, head(fx));
    const r = runDeploy(fx, ["--only", "hosting"]);
    expect(r.status).toBe(1);
    expect(r.stderr).toContain("could not build");
    expect(firebaseCalls(fx)).toEqual([]);
    expect(fs.existsSync(fx.guardSeen)).toBe(false);
  });

  test("guard step fails (stub exits 1): firebase is not spawned and the wrapper exits 1", () => {
    const fx = makeFixture({ stubGuard: true });
    initRepo(fx, "phase1/main");
    setRef(fx, PHASE1_REF, head(fx));
    const r = runDeploy(fx, ["--only", "hosting"], { FAKE_GUARD_EXIT: "1" });
    expect(r.status).toBe(1);
    expect(r.stderr).toContain("the release guard did not pass");
    expect(fs.existsSync(fx.guardSeen)).toBe(true); // the guard really ran...
    expect(firebaseCalls(fx)).toEqual([]); // ...and deploy did not
  });

  test("phase1 branch on the protected line, no --project: guard gets GCLOUD_PROJECT = production, firebase deploys with that project passed explicitly", () => {
    const fx = makeFixture({ stubGuard: true });
    initRepo(fx, "phase1/main");
    setRef(fx, PHASE1_REF, head(fx));
    const r = runDeploy(fx, ["--only", "functions:default"]);
    expect(r.status).toBe(0);
    expect(JSON.parse(fs.readFileSync(fx.guardSeen, "utf8"))).toMatchObject({ gcloudProject: PROD });
    expect(firebaseCalls(fx)).toEqual([["deploy", "--project", PROD, "--only", "functions:default"]]);
  });

  test("an ambient GCLOUD_PROJECT cannot redirect the wrapper: the derived project overrides it for the guard", () => {
    const fx = makeFixture({ stubGuard: true });
    initRepo(fx, "phase1/main");
    setRef(fx, PHASE1_REF, head(fx));
    const r = runDeploy(fx, ["--only", "hosting"], { GCLOUD_PROJECT: "ambient-other-project" });
    expect(r.status).toBe(0);
    expect(JSON.parse(fs.readFileSync(fx.guardSeen, "utf8"))).toMatchObject({ gcloudProject: PROD });
    expect(firebaseCalls(fx)).toEqual([["deploy", "--project", PROD, "--only", "hosting"]]);
  });

  test("phase2 branch, no --project: the project behind alias phase2 is used", () => {
    const fx = makeFixture({ stubGuard: true });
    initRepo(fx, "phase2/x");
    writeRc(fx, { default: PROD, phase2: PHASE2_PROJECT });
    const r = runDeploy(fx, ["--only", "hosting"]);
    expect(r.status).toBe(0);
    expect(JSON.parse(fs.readFileSync(fx.guardSeen, "utf8"))).toMatchObject({ gcloudProject: PHASE2_PROJECT });
    expect(firebaseCalls(fx)).toEqual([["deploy", "--project", PHASE2_PROJECT, "--only", "hosting"]]);
  });

  test("explicit -P<alias> is resolved, stripped and re-passed exactly once as --project <id>", () => {
    const fx = makeFixture({ stubGuard: true });
    initRepo(fx, "phase2/x");
    writeRc(fx, { default: PROD, phase2: PHASE2_PROJECT });
    const r = runDeploy(fx, ["-Pphase2", "--only", "hosting", "--force"]);
    expect(r.status).toBe(0);
    expect(firebaseCalls(fx)).toEqual([["deploy", "--project", PHASE2_PROJECT, "--only", "hosting", "--force"]]);
  });

  test("the firebase CLI's exit code is propagated", () => {
    const fx = makeFixture({ stubGuard: true });
    initRepo(fx, "phase1/main");
    setRef(fx, PHASE1_REF, head(fx));
    const r = runDeploy(fx, ["--only", "hosting"], { FAKE_FIREBASE_EXIT: "3" });
    expect(r.status).toBe(3);
    expect(firebaseCalls(fx)).toHaveLength(1);
  });
});

// --------------------------------------------- repository wiring (real files)

describe("repository wiring of the real files", () => {
  test("functions/package.json deploy script goes through the guarded wrapper, never bare firebase deploy", () => {
    const pkg = JSON.parse(fs.readFileSync(path.join(FUNCTIONS_DIR, "package.json"), "utf8")) as {
      scripts: Record<string, string>;
    };
    expect(pkg.scripts.deploy).toContain("scripts/deploy/guarded_deploy.mjs");
    expect(pkg.scripts.deploy).not.toMatch(/\bfirebase\s+deploy\b/);
    expect(fs.existsSync(path.join(REPO_DIR, "scripts", "deploy", "guarded_deploy.mjs"))).toBe(true);
  });
});
