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
import {
  aiGatewayCallsMetricJson,
  aiGatewayLatencyMetricJson,
  aiGatewayQuotaExhaustionsMetricJson,
  aiGatewayTokensMetricJson,
} from "../monitoring/ai_gateway_definitions";

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

/** Fake gcloud: logs argv as one JSON line, then answers from gcloud_responses.json (first rule whose `match` is a
 * substring of the space-joined argv); with no matching rule it exits 1, so it can never succeed by accident. */
const FAKE_GCLOUD = `
const fs = require("fs");
const path = require("path");
const root = path.resolve(__dirname, "..");
const argv = process.argv.slice(2);
fs.appendFileSync(path.join(root, "gcloud_calls.log"), JSON.stringify(argv) + "\\n");
let rules = [];
try { rules = JSON.parse(fs.readFileSync(path.join(root, "gcloud_responses.json"), "utf8")); } catch (e) { rules = []; }
const line = argv.join(" ");
const rule = rules.find((r) => line.includes(r.match));
if (!rule) {
  process.stderr.write("fake gcloud: no canned response for: " + line + "\\n");
  process.exitCode = 1;
} else {
  const finish = () => {
    if (rule.stdout) process.stdout.write(rule.stdout);
    if (rule.stderr) process.stderr.write(rule.stderr);
    process.exitCode = rule.exit || 0;
  };
  if (rule.sleepMs) setTimeout(finish, rule.sleepMs); else finish();
}
`;

const DRIVER = `
import * as d from "./functions/scripts/guard_deps.mjs";
const [cmd, arg] = process.argv.slice(2);
let r;
if (cmd === "run") { const [c, a, t] = JSON.parse(arg); const t0 = Date.now(); const res = await d.runCommand(c, a, t); r = { ...res, elapsedMs: Date.now() - t0 }; }
else if (cmd === "provenance") r = await d.makeIsCommitOnProtectedLine(JSON.parse(arg))();
else if (cmd === "branch") r = await d.currentBranch();
else if (cmd === "readFile") r = await d.readFile(arg);
else if (cmd === "root") r = d.REPO_ROOT;
console.log("RESULT=" + JSON.stringify(r === undefined ? null : r));
`;

const GUARD_CMD = "node functions/scripts/run_release_guard.mjs";
const GUARDED_FIREBASE_JSON = {
  firestore: { rules: "firestore.rules", indexes: "firestore.indexes.json", predeploy: ["npm --prefix functions run build", GUARD_CMD] },
  storage: { rules: "storage.rules", predeploy: ["npm --prefix functions run build", GUARD_CMD] },
  hosting: { public: "public", predeploy: ["npm --prefix functions run build", GUARD_CMD] },
  functions: [
    { source: "functions", codebase: "default", predeploy: [GUARD_CMD] },
    { source: "functions-equipment-identity", codebase: "equipment-identity", predeploy: [GUARD_CMD] },
  ],
};

function makeFixture(
  opts: {
    stubGuard?: boolean;
    firebase?: boolean;
    lib?: boolean;
    buildExit?: number;
    /** string = raw file content; object = JSON-stringified; null = no firebase.json at all; undefined = guarded default. */
    firebaseJson?: string | object | null;
  } = {},
): Fixture {
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
  w("functions/build.js", `require("fs").appendFileSync(require("path").join(__dirname, "..", "build.log"), "x"); process.exit(${opts.buildExit ?? 0});\n`);
  if (opts.firebase !== false) w("functions/node_modules/firebase-tools/lib/bin/firebase.js", FAKE_FIREBASE);
  w("driver.mjs", DRIVER);

  // firebase.json: guarded by default (the wrapper refuses to run when a target lacks the guard or the file is unreadable).
  if (opts.firebaseJson !== null) {
    const fj = opts.firebaseJson === undefined ? GUARDED_FIREBASE_JSON : opts.firebaseJson;
    w("firebase.json", typeof fj === "string" ? fj : JSON.stringify(fj));
  }

  const bin = path.join(root, "bin");
  w("bin/fake_gcloud.js", FAKE_GCLOUD);
  w("bin/gcloud.cmd", `@echo off\r\n"${process.execPath}" "%~dp0fake_gcloud.js" %*\r\nexit /b %ERRORLEVEL%\r\n`);
  w("bin/gcloud", `#!/bin/sh\nexec "${process.execPath}" "$(dirname "$0")/fake_gcloud.js" "$@"\n`);
  fs.chmodSync(path.join(bin, "gcloud"), 0o755);

  return {
    root,
    bin,
    gcloudLog: path.join(root, "gcloud_calls.log"),
    firebaseLog: path.join(root, "firebase_calls.jsonl"),
    guardSeen: path.join(root, "guard_seen.json"),
  };
}

/** Environment for every git child: all GIT_* variables dropped (an ambient GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE
 * would redirect the fixture's git at another repository) and discovery capped at the fixture's parent directory. */
function cleanGitEnv(root: string): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = {};
  for (const [k, v] of Object.entries(process.env)) {
    if (k.toUpperCase().startsWith("GIT_")) continue;
    env[k] = v;
  }
  env.GIT_CEILING_DIRECTORIES = path.dirname(root);
  return env;
}

function git(root: string, ...args: string[]): string {
  return execFileSync(
    "git",
    ["-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgsign=false", ...args],
    { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], env: cleanGitEnv(root) },
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
    if (upper === "PATH" || upper === "GCLOUD_PROJECT" || upper === "FIREBASE_PROJECT" || upper === "NODE_PATH" || upper === "BODY_SCAN_BUCKET") continue;
    if (upper.startsWith("FAKE_") || upper.startsWith("GIT_")) continue;
    env[k] = v;
  }
  const pathKey = Object.keys(process.env).find((k) => k.toUpperCase() === "PATH") ?? "PATH";
  env[pathKey] = `${fx.bin}${path.delimiter}${process.env[pathKey] ?? ""}`;
  env.NODE_PATH = path.join(FUNCTIONS_DIR, "node_modules");
  // F7: git inside the scripts must never discover a repository above the fixture.
  env.GIT_CEILING_DIRECTORIES = path.dirname(fx.root);
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

// =====================================================================
// Review-fix tests (round 2): process-runner semantics, full PASS run,
// working-tree scope, flag clusters, project-id validation, firebase.json
// coverage in the wrapper, throwing checks.
// =====================================================================

type GcloudRule = { match: string; stdout?: string; stderr?: string; exit?: number; sleepMs?: number };

function setGcloud(fx: Fixture, rules: GcloudRule[]): void {
  fs.writeFileSync(path.join(fx.root, "gcloud_responses.json"), JSON.stringify(rules));
}

const gcloudCalls = (fx: Fixture): string[][] => readLines(fx.gcloudLog).map((l) => JSON.parse(l) as string[]);

const AI_NAMES = [
  "aiCoachAdvice",
  "aiEquipmentRecognition",
  "aiMachineDescription",
  "aiExerciseGeneration",
  "analyzeMealPhoto",
  "parseNutritionLabel",
];
const REAL_SOURCE_FILES = [
  "functions/src/scaling.ts",
  "functions/src/ai_coach_advice.ts",
  "functions/src/ai_equipment_recognition.ts",
  "functions/src/ai_machine_description.ts",
  "functions/src/ai_exercise_generation.ts",
  "functions/src/analyze_meal_photo.ts",
  "functions/src/parse_nutrition_label.ts",
];

/** Canned gcloud answers for a fully healthy release of `project` (one rule per command the guard issues). */
function healthyGcloudRules(project: string): GcloudRule[] {
  const sa = `fn-ai-runtime@${project}.iam.gserviceaccount.com`;
  const j = (v: unknown): string => JSON.stringify(v);
  const metric = (name: string, build: () => object): GcloudRule => {
    const canonical = build() as Record<string, unknown>;
    const descriptor = canonical.metricDescriptor as Record<string, unknown>;
    return {
      match: `logging metrics describe ${name} `,
      stdout: j({
        ...canonical,
        createTime: "2026-08-27T12:52:35Z",
        updateTime: "2026-08-27T12:52:35Z",
        resourceName: `projects/${project}/metrics/${name}`,
        metricDescriptor: {
          ...descriptor,
          name: `projects/${project}/metricDescriptors/logging.googleapis.com/user/${name}`,
          type: `logging.googleapis.com/user/${name}`,
          unit: "1",
        },
      }),
    };
  };
  return [
    {
      match: "functions list",
      stdout: j(
        AI_NAMES.map((n) => ({
          name: `projects/${project}/locations/europe-west1/functions/${n}`,
          serviceConfig: { serviceAccountEmail: sa },
        })),
      ),
    },
    {
      match: "functions describe",
      stdout: j({ serviceConfig: { serviceAccountEmail: sa, environmentVariables: { APP_CHECK_ENFORCED_AI: "true" } } }),
    },
    { match: "secrets describe", stdout: j({ name: "x" }) },
    {
      match: "secrets get-iam-policy",
      stdout: j({ bindings: [{ role: "roles/secretmanager.secretAccessor", members: [`serviceAccount:${sa}`] }] }),
    },
    { match: "projects get-iam-policy", stdout: j({ bindings: [] }) },
    { match: "secrets versions access", stdout: j({ enabled: false, reason: null }) },
    metric("ai_gateway_calls", aiGatewayCallsMetricJson),
    metric("ai_gateway_latency_ms", aiGatewayLatencyMetricJson),
    metric("ai_gateway_quota_exhaustions", aiGatewayQuotaExhaustionsMetricJson),
    metric("ai_gateway_total_tokens_per_call", aiGatewayTokensMetricJson),
    { match: "logging read", stdout: j([{ x: 1 }]) },
  ];
}

/**
 * A fixture on which the REAL run_release_guard.mjs + REAL guard library can reach verdict PASS: real candidate
 * sources copied from the repository, healthy evidence, a committed clean tree with every deploy-input file, a
 * correct protected ref (phase1) or phase2 alias, and canned gcloud answers. gcloud is still the fake.
 */
function makePassFixture(
  project: string,
  branch: string,
  opts: { firebaseJson?: object | string; extraFiles?: Record<string, string>; evidence?: string } = {},
): Fixture {
  const fx = makeFixture({ firebaseJson: opts.firebaseJson });
  const w = (rel: string, content: string): void => {
    const p = path.join(fx.root, rel);
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, content);
  };
  for (const rel of REAL_SOURCE_FILES) w(rel, fs.readFileSync(path.join(REPO_DIR, rel), "utf8"));
  w(
    "core/state/g4_release_evidence.json",
    opts.evidence ??
      JSON.stringify({ step8KillSwitch: { status: "closed" }, s23PlayIntegrityProof: { status: "closed" } }),
  );
  w("firestore.rules", "rules_version = '2';\n");
  w("firestore.indexes.json", "{}\n");
  w("storage.rules", "rules_version = '2';\n");
  w("public/index.html", "<html></html>\n");
  w(".firebaserc", JSON.stringify({ projects: { default: PROD, "legacy-shared": "traidingbot-b4061", phase2: PHASE2_PROJECT } }));
  for (const [rel, content] of Object.entries(opts.extraFiles ?? {})) w(rel, content);
  initRepo(fx, branch);
  git(fx.root, "add", "-A");
  git(fx.root, "commit", "-q", "-m", "fixture files");
  if (branch.startsWith("phase1/") || branch === "master") setRef(fx, PHASE1_REF, head(fx));
  setGcloud(fx, healthyGcloudRules(project));
  return fx;
}

const okLines = (stdout: string): number => (stdout.match(/^\[OK {2}\]/gm) ?? []).length;

const carriesProject = (argv: string[], project: string): boolean =>
  argv.includes(`--project=${project}`) ||
  (argv[0] === "projects" && argv[1] === "get-iam-policy" && argv[2] === project);

// -------------------------------------------------- F1: process runner semantics

describe("guard_deps.mjs runCommand semantics (F1)", () => {
  const run = (fx: Fixture, cmd: string, args: string[], timeoutMs: number) =>
    driver(fx, "run", JSON.stringify([cmd, args, timeoutMs])).result as {
      ok: boolean;
      stdout: string;
      stderr: string;
      elapsedMs: number;
    };

  test("exit 0 with canned JSON -> ok true and the stdout is returned verbatim", () => {
    const fx = makeFixture();
    setGcloud(fx, [{ match: "functions list", stdout: '[{"name":"a"}]', exit: 0 }]);
    const r = run(fx, "gcloud", ["functions", "list", "--format=json"], 20_000);
    expect(r.ok).toBe(true);
    expect(JSON.parse(r.stdout)).toEqual([{ name: "a" }]);
  });

  test("non-zero exit with VALID JSON on stdout -> ok false (stdout and stderr preserved, never mistaken for success)", () => {
    const fx = makeFixture();
    setGcloud(fx, [{ match: "functions list", stdout: '[{"name":"a"}]', stderr: "PERMISSION_DENIED", exit: 3 }]);
    const r = run(fx, "gcloud", ["functions", "list", "--format=json"], 20_000);
    expect(r.ok).toBe(false);
    expect(JSON.parse(r.stdout)).toEqual([{ name: "a" }]);
    expect(r.stderr).toContain("PERMISSION_DENIED");
  });

  test("a command that sleeps past the timeout resolves ok false with a timeout message, without waiting for it", () => {
    const fx = makeFixture();
    setGcloud(fx, [{ match: "slow", stdout: "[]", exit: 0, sleepMs: 4000 }]);
    const r = run(fx, "gcloud", ["slow", "--format=json"], 600);
    expect(r.ok).toBe(false);
    expect(r.stderr).toContain("timed out after 600ms");
    expect(r.elapsedMs).toBeLessThan(3500);
  });

  test("a command that does not exist -> ok false", () => {
    const fx = makeFixture();
    const r = run(fx, "definitely-not-a-real-command-xyz", ["a"], 20_000);
    expect(r.ok).toBe(false);
  });

  test("a logging filter with spaces and embedded quotes arrives at the process as ONE exact argument", () => {
    const fx = makeFixture();
    setGcloud(fx, [{ match: "logging read", stdout: "[]", exit: 0 }]);
    const args = [
      "logging",
      "read",
      'jsonPayload.message="ai_gateway: call"',
      "--project=some-project",
      "--freshness=30d",
      "--label",
      "two words",
      "--format=json",
    ];
    const r = run(fx, "gcloud", args, 20_000);
    expect(r.ok).toBe(true);
    expect(gcloudCalls(fx)).toEqual([args]);
  });
});

// ------------------------------------- full PASS run of the real script (F1 e2e)

describe("run_release_guard.mjs end to end: PASS and what blocks it (real script + real guard, fake gcloud)", () => {
  test("phase1 line, everything healthy: every check OK, VERDICT PASS, exit 0, prints PASSED", () => {
    const fx = makePassFixture(PROD, "phase1/main");
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.stdout).toContain("VERDICT: PASS");
    expect(r.stdout).toContain("Release guard PASSED. Proceeding.");
    expect(r.stdout).not.toMatch(/^\[(FAIL|N\/A )\]/m);
    expect(okLines(r.stdout)).toBe(10);
    expect(r.status).toBe(0);
    expect(gcloudCalls(fx).length).toBeGreaterThan(5);
  });

  test("F6: on a NON-default project every gcloud call carries that project and none mentions production", () => {
    const fx = makePassFixture(PHASE2_PROJECT, "phase2/s00-split-docs");
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PHASE2_PROJECT });
    expect(r.stdout).toContain("VERDICT: PASS");
    expect(r.status).toBe(0);
    const calls = gcloudCalls(fx);
    expect(calls.length).toBeGreaterThan(5);
    for (const argv of calls) {
      expect({ argv, carriesProject: carriesProject(argv, PHASE2_PROJECT) }).toEqual({ argv, carriesProject: true });
      expect(argv.join(" ")).not.toContain(PROD);
    }
  });

  test("the same healthy fixture from a phase2 branch with the PRODUCTION project is blocked with zero gcloud calls", () => {
    const fx = makePassFixture(PROD, "phase2/s00-split-docs");
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("phase2-project-mismatch");
    expect(r.stdout).toContain("VERDICT: BLOCK");
    expect(r.stdout).toContain("not run: the deploy-target check did not pass");
    expect(gcloudCalls(fx)).toEqual([]);
  });

  test("a blocked deploy target (unverified provenance) makes ZERO gcloud calls and reports the nine other checks as not run", () => {
    const fx = makePassFixture(PROD, "phase1/x");
    commit(fx, "work outside the protected line");
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("phase1-provenance-unverified");
    expect((r.stdout.match(/not run: the deploy-target check did not pass/g) ?? []).length).toBe(9);
    expect(gcloudCalls(fx)).toEqual([]);
  });

  test.each([["x&calc"], ["Fitness-App-Korostelev"], ["abc"], ["abcde-"], ["a".repeat(31)]])(
    "malformed project %j from GCLOUD_PROJECT -> project-invalid, exit 1, zero gcloud calls",
    (bad) => {
      const fx = makePassFixture(PROD, "phase1/main");
      const r = runGuard(fx, [], { GCLOUD_PROJECT: bad });
      expect(r.status).toBe(1);
      expect(r.stdout).toContain("project-invalid");
      expect(gcloudCalls(fx)).toEqual([]);
    },
  );

  test("malformed project from the --project flag -> project-invalid, zero gcloud calls", () => {
    const fx = makePassFixture(PROD, "phase1/main");
    const r = runGuard(fx, ["--project=X&calc"]);
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("project-invalid");
    expect(gcloudCalls(fx)).toEqual([]);
  });

  test("a throwing check (evidence file is the JSON literal null) becomes UNAVAILABLE with its message; the report is complete and has a VERDICT line", () => {
    const fx = makePassFixture(PROD, "phase1/main", { evidence: "null" });
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("check threw an unexpected error");
    expect(r.stdout).toContain("VERDICT: BLOCK");
    // Other checks still ran and were reported.
    expect(r.stdout).toMatch(/\[OK {2}\] AI callables match the intended fn-ai-runtime deployed set/);
    expect(r.stdout).toMatch(/\[OK {2}\] Release comes from a clean, committed working tree/);
  });

  describe("working-tree scope against real git (review fix A)", () => {
    test.each([
      ["firestore.rules"],
      ["firestore.indexes.json"],
      ["storage.rules"],
      ["public/index.html"],
    ])("a modified %s blocks on the clean-tree check", (rel) => {
      const fx = makePassFixture(PROD, "phase1/main");
      fs.appendFileSync(path.join(fx.root, rel), "\n// dirty\n");
      const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
      expect(r.status).toBe(1);
      expect(r.stdout).toMatch(/\[FAIL\] Release comes from a clean, committed working tree/);
      expect(r.stdout).toContain("uncommitted changes under");
    });

    test("an untracked file under public/ also blocks", () => {
      const fx = makePassFixture(PROD, "phase1/main");
      fs.writeFileSync(path.join(fx.root, "public", "new.html"), "x");
      const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
      expect(r.status).toBe(1);
      expect(r.stdout).toMatch(/\[FAIL\] Release comes from a clean, committed working tree/);
    });

    test("debris OUTSIDE every deploy input (an untracked file in docs/) does not block a clean release", () => {
      const fx = makePassFixture(PROD, "phase1/main");
      fs.mkdirSync(path.join(fx.root, "docs"), { recursive: true });
      fs.writeFileSync(path.join(fx.root, "docs", "note.md"), "x");
      const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
      expect(r.stdout).toContain("VERDICT: PASS");
      expect(r.status).toBe(0);
    });

    test("a rules file renamed in firebase.json is covered under its NEW name", () => {
      const fx = makePassFixture(PROD, "phase1/main", {
        firebaseJson: {
          ...GUARDED_FIREBASE_JSON,
          firestore: { ...GUARDED_FIREBASE_JSON.firestore, rules: "rules/custom.rules" },
        },
        extraFiles: { "rules/custom.rules": "rules_version = '2';\n" },
      });
      // control: clean tree passes
      expect(runGuard(fx, [], { GCLOUD_PROJECT: PROD }).status).toBe(0);
      fs.appendFileSync(path.join(fx.root, "rules", "custom.rules"), "// dirty\n");
      const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
      expect(r.status).toBe(1);
      expect(r.stdout).toMatch(/\[FAIL\] Release comes from a clean, committed working tree/);
      expect(r.stdout).toContain("rules/custom.rules");
    });

    test("unsafe paths in firebase.json (absolute, .., backslash, pathspec magic) are ignored: no git error, the clean release still passes", () => {
      const fx = makePassFixture(PROD, "phase1/main", {
        firebaseJson: {
          ...GUARDED_FIREBASE_JSON,
          firestore: { ...GUARDED_FIREBASE_JSON.firestore, rules: "../outside.rules", indexes: "/abs/indexes.json" },
          storage: { ...GUARDED_FIREBASE_JSON.storage, rules: ":(top)storage.rules" },
          hosting: { ...GUARDED_FIREBASE_JSON.hosting, public: "a\\b" },
        },
      });
      const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
      expect(r.stdout).toContain("VERDICT: PASS");
      expect(r.status).toBe(0);
    });
  });
});

// ------------------------------------------------ guarded_deploy.mjs round 2

describe("guarded_deploy.mjs review fixes (real wrapper, fake firebase CLI)", () => {
  const stubbed = (branch = "phase1/main", firebaseJson?: string | object | null): Fixture => {
    const fx = makeFixture({ stubGuard: true, firebaseJson });
    initRepo(fx, branch);
    if (branch.startsWith("phase1/")) setRef(fx, PHASE1_REF, head(fx));
    writeRc(fx, { default: PROD, phase2: PHASE2_PROJECT });
    return fx;
  };

  describe("(D) firebase.json coverage", () => {
    const expectBlocked = (fx: Fixture, r: Run, text: string): void => {
      expect(r.status).toBe(1);
      expect(r.stderr).toContain("guarded_deploy: BLOCKED");
      expect(r.stderr).toContain(text);
      expect(firebaseCalls(fx)).toEqual([]);
      expect(fs.existsSync(fx.guardSeen)).toBe(false);
    };

    test("a deploy target without the guard blocks and names it", () => {
      const fx = stubbed("phase1/main", {
        ...GUARDED_FIREBASE_JSON,
        hosting: { public: "public", predeploy: ["npm --prefix functions run build"] },
      });
      expectBlocked(fx, runDeploy(fx, ["--only", "hosting"]), "without the release guard in predeploy: hosting");
    });

    test("(E) a predeploy that only MENTIONS the guard file name is not a guard", () => {
      const fx = stubbed("phase1/main", {
        ...GUARDED_FIREBASE_JSON,
        storage: { rules: "storage.rules", predeploy: ["node x || true # run_release_guard.mjs"] },
      });
      expectBlocked(fx, runDeploy(fx, ["--only", "storage"]), "storage");
    });

    test("an unreadable firebase.json (invalid JSON) blocks", () => {
      const fx = stubbed("phase1/main", "{not json");
      expectBlocked(fx, runDeploy(fx, ["--only", "hosting"]), "firebase.json:unreadable");
    });

    test("a missing firebase.json blocks", () => {
      const fx = stubbed("phase1/main", null);
      expectBlocked(fx, runDeploy(fx, ["--only", "hosting"]), "firebase.json:unreadable");
    });

    test("control: the fully guarded firebase.json deploys", () => {
      const fx = stubbed();
      expect(runDeploy(fx, ["--only", "hosting"]).status).toBe(0);
      expect(firebaseCalls(fx)).toHaveLength(1);
    });
  });

  describe("(B) short-flag clusters", () => {
    test.each([
      ["-ic x.json", ["-ic", "x.json"]],
      ["-jc x.json", ["-jc", "x.json"]],
      ["-iPprod", ["-iPprod"]],
    ] as const)("%s is refused and firebase is not spawned", (_label, args) => {
      const fx = stubbed();
      const r = runDeploy(fx, [...args, "--only", "hosting"]);
      expect(r.status).toBe(1);
      expect(r.stderr).toContain("combined short-flag token");
      expect(firebaseCalls(fx)).toEqual([]);
      expect(fs.existsSync(fx.guardSeen)).toBe(false);
    });

    test("legitimate forms still work and are forwarded: -m 'msg', --only, --force, --dry-run", () => {
      const fx = stubbed();
      const r = runDeploy(fx, ["-m", "release note with spaces", "--only", "hosting", "--force", "--dry-run"]);
      expect(r.status).toBe(0);
      expect(firebaseCalls(fx)).toEqual([
        ["deploy", "--project", PROD, "-m", "release note with spaces", "--only", "hosting", "--force", "--dry-run"],
      ]);
    });

    test.each([
      ["--project <alias>", ["--project", "phase2"]],
      ["-P <alias>", ["-P", "phase2"]],
      ["-P<alias>", ["-Pphase2"]],
      ["--project=<id>", [`--project=${PHASE2_PROJECT}`]],
      ["-P <id>", ["-P", PHASE2_PROJECT]],
      ["-P<id>", [`-P${PHASE2_PROJECT}`]],
    ] as const)("project selector form %s still works", (_label, args) => {
      const fx = stubbed("phase2/x");
      const r = runDeploy(fx, [...args, "--only", "hosting"]);
      expect(r.status).toBe(0);
      expect(firebaseCalls(fx)).toEqual([["deploy", "--project", PHASE2_PROJECT, "--only", "hosting"]]);
    });
  });

  describe("(C) malformed project ids", () => {
    test.each([["X&calc"], ["UPPER-case-project"], ["abc"], ["abcde-"]])("--project %j is refused as project-invalid", (bad) => {
      const fx = stubbed();
      const r = runDeploy(fx, ["--project", bad, "--only", "hosting"]);
      expect(r.status).toBe(1);
      expect(r.stderr).toContain("project-invalid");
      expect(firebaseCalls(fx)).toEqual([]);
      expect(fs.existsSync(fx.guardSeen)).toBe(false);
    });
  });
});

// =====================================================================
// git-ignored deployable files, against REAL git with a real .gitignore
// =====================================================================

describe("git-ignored deployable files (real git, real .gitignore, real guard and wrapper)", () => {
  const IGNORE_LIST_FUNCTIONS = ["node_modules", ".git", "firebase-debug.log", "firebase-debug.*.log", "*.local"];
  const FIREBASE_JSON_WITH_IGNORES = {
    ...GUARDED_FIREBASE_JSON,
    hosting: { ...GUARDED_FIREBASE_JSON.hosting, ignore: ["firebase.json", "**/.*", "**/node_modules/**"] },
    functions: GUARDED_FIREBASE_JSON.functions.map((f) => ({ ...f, ignore: IGNORE_LIST_FUNCTIONS })),
  };
  const GITIGNORE = [
    "node_modules/",
    "functions/lib/",
    "functions-equipment-identity/lib/",
    "ignored_*",
    ".hidden",
    ".cache/",
    ".env",
    ".env.*",
    "*.local",
    "docs/tmp.log",
    "",
  ].join("\n");

  const make = (opts: { gitignore?: string; firebaseJson?: object | string } = {}): Fixture =>
    makePassFixture(PROD, "phase1/main", {
      firebaseJson: opts.firebaseJson ?? FIREBASE_JSON_WITH_IGNORES,
      extraFiles: { ".gitignore": opts.gitignore ?? GITIGNORE },
    });

  const mk = (fx: Fixture, rel: string, content = "x"): void => {
    const p = path.join(fx.root, rel);
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, content);
  };

  const provenanceLine = (stdout: string): string =>
    stdout.split(/\r?\n/).find((l) => l.includes("Release comes from a clean, committed working tree")) ?? "";

  test("control: the fixture with a real .gitignore (ignored node_modules and functions/lib on disk) PASSes", () => {
    const fx = make();
    // The fixture really has ignored entries in scope: they are on disk but not in the commit.
    expect(git(fx.root, "ls-files", "functions/lib")).toBe("");
    expect(fs.existsSync(path.join(fx.root, "functions", "lib", "release_guard.js"))).toBe(true);
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.stdout).toContain("VERDICT: PASS");
    expect(r.status).toBe(0);
    expect(okLines(r.stdout)).toBe(10);
  });

  test("ignored public/ignored_app.js (not excluded by hosting.ignore): FAILED 'ignored-deployable-files:', BLOCK, exit 1", () => {
    const fx = make();
    mk(fx, "public/ignored_app.js");
    expect(git(fx.root, "status", "--porcelain", "--", "public", "functions")).toBe(""); // plain status (the old check) sees nothing: that was the hole
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.status).toBe(1);
    expect(r.stdout).toMatch(/\[FAIL\] Release comes from a clean, committed working tree/);
    expect(r.stdout).toContain("ignored-deployable-files:");
    expect(r.stdout).toContain("public/ignored_app.js");
    expect(r.stdout).toContain("VERDICT: BLOCK");
  });

  test("guarded_deploy.mjs: the same ignored file blocks BEFORE firebase is spawned; control without it deploys", () => {
    const control = make();
    const ok = runDeploy(control, ["--only", "hosting"]);
    expect({ status: ok.status, stderr: ok.stderr }).toEqual({ status: 0, stderr: expect.any(String) });
    expect(firebaseCalls(control)).toEqual([["deploy", "--project", PROD, "--only", "hosting"]]);

    const fx = make();
    mk(fx, "public/ignored_app.js");
    const r = runDeploy(fx, ["--only", "hosting"]);
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("ignored-deployable-files:");
    expect(r.stderr).toContain("the release guard did not pass");
    expect(firebaseCalls(fx)).toEqual([]);
  });

  test("every allowed kind of ignored entry together (dot files, nested dot dir, node_modules, lib dirs, env files, *.local, out-of-scope docs/tmp.log) still PASSes", () => {
    const fx = make();
    mk(fx, "public/.hidden");
    mk(fx, "public/a/b/.cache/x.js");
    mk(fx, "public/node_modules/pkg/index.js");
    mk(fx, "functions/node_modules/pkg/index.js");
    mk(fx, "functions-equipment-identity/lib/index.js");
    mk(fx, "functions/.env");
    mk(fx, "functions/.env.fitness-app-phase2-korostelev");
    mk(fx, "functions/foo.local");
    mk(fx, "docs/tmp.log");
    const status = git(fx.root, "status", "--porcelain", "--ignored=matching");
    for (const expected of ["public/.hidden", "functions/.env", "functions/foo.local", "functions-equipment-identity/lib/"]) {
      expect(status).toContain(expected); // the ignored entries really exist from git's point of view
    }
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.stdout).toContain("VERDICT: PASS");
    expect(r.status).toBe(0);
  });

  test.each([
    ["functions/src/ignored_evil.ts"],
    ["functions-equipment-identity/src/ignored_evil.ts"],
    ["public/sub/ignored_app.js"],
    ["functions/ignored_.runtimeconfig.json"],
  ])("ignored %s blocks", (rel) => {
    const fx = make();
    mk(fx, rel);
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.status).toBe(1);
    expect(provenanceLine(r.stdout)).toContain("[FAIL]");
    expect(r.stdout).toContain("ignored-deployable-files:");
    expect(r.stdout).toContain(rel);
  });

  test("an ignored storage.rules (deploy input outside the uploaded directories) blocks", () => {
    const fx = make({ gitignore: `${GITIGNORE}storage.rules\n` });
    expect(git(fx.root, "ls-files", "storage.rules")).toBe("");
    expect(fs.existsSync(path.join(fx.root, "storage.rules"))).toBe(true);
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("ignored-deployable-files:");
    expect(r.stdout).toContain("storage.rules");
  });

  test("an ignored firestore.rules blocks", () => {
    const fx = make({ gitignore: `${GITIGNORE}firestore.rules\n` });
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("ignored-deployable-files:");
    expect(r.stdout).toContain("firestore.rules");
  });

  test("a path with special characters (git quotes it) blocks", () => {
    const fx = make();
    mk(fx, "public/ignored_pubé file.js");
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("ignored-deployable-files:");
  });

  test("unreadable firebase.json: strict classification -- ignored public/.hidden AND the ignored functions/node_modules block (empty ignore lists); lib stays allowed", () => {
    const fx = make({ firebaseJson: "{not json" });
    mk(fx, "public/.hidden");
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("ignored-deployable-files:");
    const detail = r.stdout.split("not in the verified commit: ")[1]?.split(/\r?\n/)[0] ?? "";
    expect(detail).toBe("functions/node_modules/, public/.hidden");
  });

  test("unreadable firebase.json: with no extra file the ignored functions/node_modules alone now blocks (allowed only via the ignore list); functions/lib is not reported", () => {
    const fx = make({ firebaseJson: "{not json" });
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(provenanceLine(r.stdout)).toContain("[FAIL]");
    expect(r.stdout.split("not in the verified commit: ")[1]?.split(/\r?\n/)[0]).toBe("functions/node_modules/");
  });

  test("mixed: an uncommitted change plus an allowed ignored entry reports the uncommitted change", () => {
    const fx = make();
    mk(fx, "functions/.env");
    fs.appendFileSync(path.join(fx.root, "firestore.rules"), "// dirty\n");
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("uncommitted changes under");
    expect(r.stdout).not.toContain("ignored-deployable-files:");
  });

  test("without a usable git repository the guard blocks at the deploy target (no branch), before any gcloud call", () => {
    const fx = make();
    // The branch cannot be read, so the deploy target fails first (unit tests cover git status itself failing -> UNAVAILABLE).
    fs.rmSync(path.join(fx.root, ".git"), { recursive: true, force: true });
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("VERDICT: BLOCK");
    expect(gcloudCalls(fx)).toEqual([]); // blocked at the deploy target (no branch) before any provenance/gcloud work
  });
});

// =====================================================================
// node_modules is allowed only through the deploy target's own ignore list
// =====================================================================

describe("ignored node_modules: allowed only via the target's own ignore list (real git, real wrapper)", () => {
  const FN_IGNORE = ["node_modules", ".git", "firebase-debug.log", "firebase-debug.*.log", "*.local"];
  const GITIGNORE_NM = [
    "node_modules/",
    "functions/lib/",
    "functions-equipment-identity/lib/",
    ".env",
    ".env.*",
    "",
  ].join("\n");

  const fj = (parts: { hostingIgnore?: string[]; fn0?: Record<string, unknown>; fn1?: Record<string, unknown> }): object => ({
    ...GUARDED_FIREBASE_JSON,
    hosting: {
      ...GUARDED_FIREBASE_JSON.hosting,
      ...(parts.hostingIgnore === undefined ? {} : { ignore: parts.hostingIgnore }),
    },
    functions: [
      { ...GUARDED_FIREBASE_JSON.functions[0], ...(parts.fn0 ?? { ignore: FN_IGNORE }) },
      { ...GUARDED_FIREBASE_JSON.functions[1], ...(parts.fn1 ?? { ignore: FN_IGNORE }) },
    ],
  });

  const make = (firebaseJson: object | string, gitignore = GITIGNORE_NM): Fixture =>
    makePassFixture(PROD, "phase1/main", { firebaseJson, extraFiles: { ".gitignore": gitignore } });

  const mk = (fx: Fixture, rel: string): void => {
    const p = path.join(fx.root, rel);
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, "x");
  };

  const offenders = (stdout: string): string =>
    stdout.split("not in the verified commit: ")[1]?.split(/\r?\n/)[0] ?? "";

  test("hosting.ignore [] + ignored public/node_modules/pkg/index.js: BLOCK through the real wrapper, firebase never spawned", () => {
    const fx = make(fj({ hostingIgnore: [] }));
    mk(fx, "public/node_modules/pkg/index.js");
    const r = runDeploy(fx, ["--only", "hosting"]);
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("ignored-deployable-files:");
    expect(offenders(r.stdout)).toBe("public/node_modules/");
    expect(r.stderr).toContain("the release guard did not pass");
    expect(firebaseCalls(fx)).toEqual([]);
  });

  test("control: the SAME file with hosting.ignore ['**/node_modules/**'] is allowed and the wrapper deploys", () => {
    const fx = make(fj({ hostingIgnore: ["**/node_modules/**"] }));
    mk(fx, "public/node_modules/pkg/index.js");
    const r = runDeploy(fx, ["--only", "hosting"]);
    expect(r.status).toBe(0);
    expect(firebaseCalls(fx)).toEqual([["deploy", "--project", PROD, "--only", "hosting"]]);
  });

  test("hosting has no matchBase: ignore ['node_modules'] excludes public/node_modules but NOT public/sub/node_modules; '**/node_modules/**' excludes both", () => {
    const whole = make(fj({ hostingIgnore: ["node_modules"] }));
    mk(whole, "public/node_modules/a.js");
    expect(runGuard(whole, [], { GCLOUD_PROJECT: PROD }).status).toBe(0);
    mk(whole, "public/sub/node_modules/a.js");
    const blocked = runGuard(whole, [], { GCLOUD_PROJECT: PROD });
    expect(blocked.status).toBe(1);
    expect(offenders(blocked.stdout)).toBe("public/sub/node_modules/");

    const deep = make(fj({ hostingIgnore: ["**/node_modules/**"] }));
    mk(deep, "public/node_modules/a.js");
    mk(deep, "public/sub/node_modules/a.js");
    expect(runGuard(deep, [], { GCLOUD_PROJECT: PROD }).status).toBe(0);
  });

  test("functions config WITHOUT an ignore key: ignored functions/node_modules is allowed (firebase default ['node_modules', '.git'])", () => {
    const fx = make(fj({ fn0: {}, fn1: {} }));
    expect(fs.existsSync(path.join(fx.root, "functions", "node_modules"))).toBe(true); // really on disk and ignored
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.stdout).toContain("VERDICT: PASS");
    expect(r.status).toBe(0);
  });

  test("functions config without an ignore key does NOT get the extra patterns of the real config: an ignored functions/ignored.local blocks (real config lists *.local, so it is allowed there)", () => {
    const withDefault = make(fj({ fn0: {}, fn1: {} }), GITIGNORE_NM + "*.local\n");
    mk(withDefault, "functions/ignored.local");
    const r = runGuard(withDefault, [], { GCLOUD_PROJECT: PROD });
    expect(r.status).toBe(1);
    expect(offenders(r.stdout)).toBe("functions/ignored.local");
    const withList = make(fj({}), GITIGNORE_NM + "*.local\n");
    mk(withList, "functions/ignored.local");
    expect(runGuard(withList, [], { GCLOUD_PROJECT: PROD }).status).toBe(0);
  });

  test("functions ignore [] : the ignored functions/node_modules now BLOCKS (an explicit empty list uploads node_modules)", () => {
    const fx = make(fj({ fn0: { ignore: [] } }));
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("ignored-deployable-files:");
    expect(offenders(r.stdout)).toBe("functions/node_modules/");
  });

  test("only the second codebase has ignore []: only ITS node_modules is reported", () => {
    const fx = make(fj({ fn1: { ignore: [] } }));
    mk(fx, "functions-equipment-identity/node_modules/pkg/index.js");
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.status).toBe(1);
    expect(offenders(r.stdout)).toBe("functions-equipment-identity/node_modules/");
  });

  test("functions nested node_modules (functions/src/node_modules) is allowed by basename matching when 'node_modules' is listed", () => {
    const fx = make(fj({}));
    mk(fx, "functions/src/node_modules/pkg/index.js");
    mk(fx, "functions/a/b/c/node_modules/pkg/index.js");
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.stdout).toContain("VERDICT: PASS");
    expect(r.status).toBe(0);
  });

  test("unreadable firebase.json (invalid JSON): the ignored functions/node_modules blocks (strict, empty ignore lists)", () => {
    const fx = make("{not json");
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("ignored-deployable-files:");
    expect(offenders(r.stdout)).toContain("functions/node_modules/");
  });

  test("lib dirs and env files are allowed independently of the functions ignore list", () => {
    const fx = make(fj({ fn0: { ignore: ["node_modules"] }, fn1: { ignore: ["node_modules"] } }));
    mk(fx, "functions-equipment-identity/lib/index.js");
    mk(fx, "functions/.env");
    mk(fx, "functions/.env.fitness-app-phase2-korostelev");
    mk(fx, "functions-equipment-identity/.env.fitness-app-korostelev");
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.stdout).toContain("VERDICT: PASS");
    expect(r.status).toBe(0);
  });

  test("functions/firebase-debug.log and firebase-debug.1.log are allowed implicitly even when the configured ignore list omits them", () => {
    const fx = make(fj({ fn0: { ignore: ["node_modules"] } }), GITIGNORE_NM + "firebase-debug*.log\n");
    mk(fx, "functions/firebase-debug.log");
    mk(fx, "functions/firebase-debug.1.log");
    expect(git(fx.root, "status", "--porcelain", "--ignored=matching", "--", "functions")).toContain("firebase-debug.1.log");
    const r = runGuard(fx, [], { GCLOUD_PROJECT: PROD });
    expect(r.stdout).toContain("VERDICT: PASS");
    expect(r.status).toBe(0);
  });
});
