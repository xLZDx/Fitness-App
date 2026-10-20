/**
 * S02-08 and the operations part of S02-05b/06b: F38, F39, F40, F42, F43, F92.
 * The two lifecycle checkers are plain node scripts (`scripts/ci`); they are run as real
 * processes, on the repository files and on mutated copies in a throw-away fixture root.
 */
jest.mock("firebase-admin", () => require("./support/fakes").adminMock());
jest.mock("firebase-functions/logger", () => require("./support/fakes").loggerMock());

import { spawnSync } from "child_process";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import * as logger from "firebase-functions/logger";
import { runActivityLateSweep } from "../../activity_streams/late_sweep";
import { runActivityStreamPurge } from "../../activity_streams/purge";
import { runActivityReconcile } from "../../activity_streams/reconcile";
import { T0, createWorld, firestoreInstance, loggedText, releaseClock, resetAll, useClock, type World } from "./support/fakes";

jest.setTimeout(180_000);

const REPO = path.resolve(__dirname, "../../../../");
const POLICY_REL = "scripts/ci/data_lifecycle_policy.json";
const read = (rel: string): string => fs.readFileSync(path.join(REPO, rel), "utf8");

function runChecker(root: string, script: "check_data_lifecycle_coverage.js" | "check_data_access_policy.js") {
  const r = spawnSync(process.execPath, [path.join(root, "scripts/ci", script)], { encoding: "utf8", cwd: root, timeout: 120_000 });
  return { code: r.status, out: `${r.stdout}\n${r.stderr}` };
}

/** Violations that exist on the repository for reasons outside S02 (Body Scan and nutrition cache call sites). */
const NON_S02_RESIDUE = [
  "functions/src/body_scan/manage.ts:218",
  "functions/src/body_scan/manage.ts:317",
  "functions/src/body_scan/manage.ts:355",
  "functions/src/nutrition_cache.ts:109",
  "functions/src/nutrition_cache.ts:74",
];
describe("F38 the repository files pass the S02 part of both checkers", () => {
  test("the lifecycle coverage checker exits 0 on the repository", () => {
    const r = runChecker(REPO, "check_data_lifecycle_coverage.js");
    expect(r.out).toContain("OK -- every in-use collection has a lifecycle policy entry.");
    expect(r.code).toBe(0);
  });
  test("the access policy checker reports nothing about any S02 file or collection; only the pinned non-S02 residue remains", () => {
    const r = runChecker(REPO, "check_data_access_policy.js");
    const lines = r.out.split("\n").filter((l) => /UNRESOLVED|NO clientAccess/.test(l));
    expect(lines.filter((l) => /activit|account_export/i.test(l))).toEqual([]);
    const found = lines.map((l) => /(functions\/src\/[\w/]+\.ts:\d+)/.exec(l)?.[1]).filter(Boolean).sort();
    expect(found).toEqual([...NON_S02_RESIDUE].sort());
  });
});

describe("F39 checker sensitivity on mutated copies of the policy", () => {
  let root: string;
  const policyPath = (): string => path.join(root, POLICY_REL);
  beforeAll(() => {
    root = fs.mkdtempSync(path.join(os.tmpdir(), "s02-lifecycle-"));
    const skipTests = (src: string): boolean => !/__tests__|node_modules|[\\/]\.dart_tool|[\\/]build[\\/]/.test(src);
    fs.cpSync(path.join(REPO, "scripts/ci"), path.join(root, "scripts/ci"), { recursive: true });
    fs.copyFileSync(path.join(REPO, "firestore.rules"), path.join(root, "firestore.rules"));
    for (const d of ["functions/src", "functions-equipment-identity/src", "mobile/lib"]) {
      fs.cpSync(path.join(REPO, d), path.join(root, d), { recursive: true, filter: skipTests });
    }
  });
  afterAll(() => fs.rmSync(root, { recursive: true, force: true }));
  const original = read(POLICY_REL);
  afterEach(() => fs.writeFileSync(policyPath(), original));
  const without = (key: string): void => {
    const j = JSON.parse(original);
    delete j.collections[key];
    fs.writeFileSync(policyPath(), JSON.stringify(j, null, 2));
  };

  test("the unmutated copy behaves exactly like the repository (the instrument works)", () => {
    expect(runChecker(root, "check_data_lifecycle_coverage.js").code).toBe(0);
  });
  test.each(["activities", "activity_streams", "activity_settings", "activity_tombstones", "activity_account_state"])(
    "removing the %s row makes the lifecycle checker fail and name it",
    (key) => {
      without(key);
      const r = runChecker(root, "check_data_lifecycle_coverage.js");
      expect(r.code).not.toBe(0);
      expect(r.out).toContain(key);
    },
  );
  test.each(["activities", "activity_streams", "activity_settings", "activity_tombstones", "activity_account_state"])(
    "removing the %s row adds a violation to the access checker",
    (key) => {
      without(key);
      const r = runChecker(root, "check_data_access_policy.js");
      expect(r.code).not.toBe(0);
      expect(r.out).toMatch(new RegExp(`NO clientAccess DECLARATION[^\\n]*${key}`));
    },
  );
  test("the policy file carries the tombstone and account-state rows with the declared access, and no withdrawn late-sweeps row", () => {
    const c = JSON.parse(original).collections;
    expect(c.activity_late_sweeps).toBeUndefined();
    expect(c.activity_tombstones.clientAccess[0].access).toEqual({ read: "OWNER", create: "NONE", update: "NONE", delete: "NONE" });
    // Plan F39 says BOTH; the policy row records the decision to NOT export tombstones (classification DELETE).
    expect(c.activity_tombstones.classification).toBe("DELETE");
    expect(c.activity_account_state.clientAccess[0].path).toBe("/activity_account_state/{docId}");
    expect(c.activity_account_state.clientAccess[0].access).toEqual({ read: "NONE", create: "NONE", update: "NONE", delete: "NONE" });
    expect(c.activity_account_state.classification).toBe("EXEMPT");
    for (const k of ["activities", "activity_streams", "activity_settings"]) expect(c[k]).toBeDefined();
    expect(c.activity_streams.clientAccess[0].access.read).toBe("OWNER");
  });
});

describe("F40 indexes for purge and recompute queries", () => {
  const idx = JSON.parse(read("firestore.indexes.json"));
  test("entry 1: activity_streams collection-group state ASC + expiresAt ASC", () => {
    expect(
      idx.indexes.some(
        (i: any) =>
          i.collectionGroup === "activity_streams" && i.queryScope === "COLLECTION_GROUP" &&
          JSON.stringify(i.fields.map((f: any) => [f.fieldPath, f.order])) === JSON.stringify([["state", "ASCENDING"], ["expiresAt", "ASCENDING"]]),
      ),
    ).toBe(true);
  });
  test("entry 2: activity_settings.recomputePending single-field collection-group exemption", () => {
    const o = idx.fieldOverrides.find((x: any) => x.collectionGroup === "activity_settings" && x.fieldPath === "recomputePending");
    expect(o.indexes.some((i: any) => i.queryScope === "COLLECTION_GROUP" && i.order === "ASCENDING")).toBe(true);
  });
  test("the withdrawn cross-field index on settingsGeneration is absent", () => {
    expect(JSON.stringify(idx)).not.toMatch(/"fieldPath":\s*"settingsGeneration"/);
  });
  test("the pre-existing index entries are still present", () => {
    const names = idx.indexes.map((i: any) => `${i.collectionGroup}:${i.queryScope}:${i.fields.map((f: any) => f.fieldPath).join(",")}`);
    for (const old of [
      "equipment_model_text_keys:COLLECTION:catalogVersion,lookupKey",
      "accountDeletionRetries:COLLECTION:status,nextAttemptAt",
      "body_scans:COLLECTION_GROUP:photosState,photosExpireAt",
      "body_scans:COLLECTION_GROUP:status,pendingExpiresAt",
    ]) expect(names).toContain(old);
    expect(idx.fieldOverrides.some((o: any) => o.collectionGroup === "accountDeletionRetries" && o.fieldPath === "expireAt" && o.ttl === true)).toBe(true);
    expect(idx.fieldOverrides.some((o: any) => o.collectionGroup === "nutrition_cache" && o.ttl === true)).toBe(true);
  });
  test("the reconciler and bulk-delete single-field group queries have their overrides too", () => {
    for (const [g, f] of [["activity_streams", "pendingSince"], ["activity_settings", "streamDeletePending"]]) {
      const o = idx.fieldOverrides.find((x: any) => x.collectionGroup === g && x.fieldPath === f);
      expect(o?.indexes.some((i: any) => i.queryScope === "COLLECTION_GROUP")).toBe(true);
    }
  });
});

describe("F42/F43 privacy text and lifecycle matrix rows (weak string checks by nature)", () => {
  test("public/privacy.html states GPS upload, the expiry setting and that heart rate stays on the device", () => {
    const html = read("public/privacy.html").replace(/&#x27;/g, "'");
    expect(html).toMatch(/GPS/);
    expect(html).toMatch(/upload/i);
    expect(html).toMatch(/expire automatically after the expiry period you choose/);
    expect(html).toMatch(/Heart rate stays on the device/);
  });
  test("DATA_LIFECYCLE_MATRIX.md has rows for activities, activity_streams and streams/<uid>/", () => {
    const md = read("docs/phase2/s01/DATA_LIFECYCLE_MATRIX.md");
    expect(md).toMatch(/`users\/\{uid\}\/activities`/);
    expect(md).toMatch(/`users\/\{uid\}\/activity_streams`/);
    expect(md).toMatch(/Storage `streams\/\{uid\}\/\.\.\.`/);
    expect(md).toMatch(/sweepActivityStreamObjects/);
  });
});

describe("F92 structured-log metrics, no uid", () => {
  let w: World;
  beforeEach(() => {
    resetAll();
    useClock(T0);
    w = createWorld();
    for (const l of ["info", "warn", "error", "debug"] as const) (logger[l] as jest.Mock).mockClear();
  });
  afterEach(() => releaseClock());
  const events = (): Array<[string, any]> =>
    (["info", "warn", "error"] as const).flatMap((l) => (logger[l] as jest.Mock).mock.calls as Array<[string, any]>).filter((c) => /_event$/.test(c[0]));

  test("an EMPTY run of each scheduled job emits one run-complete entry with a fixed name and zero counts", async () => {
    await runActivityStreamPurge({ firestore: () => firestoreInstance as never, bucket: () => w.bucket, nowMs: () => Date.now() });
    await runActivityReconcile({ ...w.deps, listing: () => w.bucket });
    await runActivityLateSweep({ firestore: w.deps.firestore, authUserExists: w.deps.authUserExists, nowMs: w.deps.nowMs, bucket: w.deps.bucket });
    const done = events().filter((c) => c[1].outcome === "run-complete");
    expect(done.map((c) => c[0]).sort()).toEqual(["activity_late_sweep_event", "activity_purge_event", "activity_reconcile_event"]);
    for (const [, f] of done) {
      const numeric = Object.entries(f).filter(([, v]) => typeof v === "number");
      expect(numeric.length).toBeGreaterThan(2);
      for (const [k, v] of numeric) { if (!/latency/i.test(k)) expect([k, v]).toEqual([k, 0]); }
    }
  });
  test("a run that processed things still carries only counts, ages and bare codes (no uid, id, path or signed URL)", async () => {
    const UIDS = "uid_alice_1";
    w.bucket.put(`quarantine/${UIDS}/act_${"a".repeat(40)}/up_${"0".repeat(32)}`, Buffer.from("x"));
    w.bucket.failOn = (op) => (op === "delete" ? Object.assign(new Error(`gs://secret/${UIDS}`), { code: 500 }) : null);
    await runActivityReconcile({ ...w.deps, listing: () => w.bucket });
    const text = loggedText(logger);
    expect(text).toContain("activity_reconcile_event");
    for (const banned of [UIDS, "act_aaaa", "quarantine/", "gs://", "SIGNED_URL_SENTINEL"]) expect(text).not.toContain(banned);
  });
  test("the event names are the pinned constants and every name the runbook alerts on is emitted by code", () => {
    const pinned = ["activity_purge_event", "activity_reconcile_event", "activity_late_sweep_event", "activity_commit_event", "debug_telemetry_event", "debug_telemetry_dropped"];
    const dir = path.join(REPO, "functions/src/activity_streams");
    const code = fs.readdirSync(dir).map((f) => fs.readFileSync(path.join(dir, f), "utf8")).join("\n");
    for (const n of pinned) expect(code).toContain(`"${n}"`);
    const runbook = read("runbooks/activity_stream_bucket.md");
    const used = [...new Set(runbook.match(/`((?:activity|debug_telemetry)_[a-z_]+)`/g) ?? [])].map((s) => s.replace(/`/g, ""));
    const alertNames = used.filter((n) => /_(event|dropped)$/.test(n));
    expect(alertNames.length).toBeGreaterThanOrEqual(5);
    for (const n of alertNames) expect(code).toContain(`"${n}"`);
    for (const n of pinned.slice(0, 3)) expect(runbook).toContain(n);
  });
});
