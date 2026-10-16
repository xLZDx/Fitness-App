/**
 * S02 test epic 8b -- policy, privacy-text, TTL-declaration and access-checker tests for
 * remediation batch A (A5, A6, A9, A12 text side, F38, F42). Plain node/jest, no emulator.
 *
 * Oracles: docs/phase2/s02/S02_REMEDIATION_A_TEST_NOTES.md and design sections 6.1, 6.2, 8, 17.
 * Mutations are applied to throw-away COPIES; the tracked files are never edited.
 */
jest.mock("firebase-admin", () => require("./activity/support/fakes").adminMock());
jest.mock("firebase-functions/logger", () => require("./activity/support/fakes").loggerMock());

import { spawnSync } from "child_process";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { ACTIVITY_USER_COLLECTIONS } from "../activity_streams/late_sweep";

jest.setTimeout(180_000);

const REPO = path.resolve(__dirname, "../../../");
const read = (rel: string): string => fs.readFileSync(path.join(REPO, rel), "utf8");
const run = (script: string, cwd: string, args: string[] = []) => {
  const r = spawnSync(process.execPath, [script, ...args], { encoding: "utf8", cwd, timeout: 120_000 });
  return { code: r.status, out: `${r.stdout}\n${r.stderr}` };
};

// ---------------------------------------------------------------------------------------------
// A6: tombstone TTL is declared in firestore.indexes.json and the checker notices its absence
// ---------------------------------------------------------------------------------------------
describe("A6 TTL override checker (scripts/ci/check_ttl_overrides.js)", () => {
  const CHECKER = path.join(REPO, "scripts/ci/check_ttl_overrides.js");
  let dir: string;
  beforeAll(() => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), "s02-ttl-"));
  });
  afterAll(() => fs.rmSync(dir, { recursive: true, force: true }));

  const original = JSON.parse(read("firestore.indexes.json"));
  const clone = () => JSON.parse(JSON.stringify(original));
  /** Writes a mutated copy of the indexes file and runs the real checker on it. */
  const check = (mutate: (j: any) => void) => {
    const j = clone();
    mutate(j);
    const file = path.join(dir, "indexes.json");
    fs.writeFileSync(file, JSON.stringify(j, null, 2));
    return run(CHECKER, dir, [file]);
  };
  const tomb = (j: any) => j.fieldOverrides.find((o: any) => o.collectionGroup === "activity_tombstones" && o.fieldPath === "expireAt");

  test("the real firestore.indexes.json carries the tombstone ttl entry and passes", () => {
    expect(tomb(original)).toBeDefined();
    expect(tomb(original).ttl).toBe(true);
    const r = run(CHECKER, REPO);
    expect(r.out).toContain("OK");
    expect(r.code).toBe(0);
  });

  test("an unmodified copy passes (the instrument works on a copy)", () => {
    expect(check(() => undefined).code).toBe(0);
  });

  test("removing the activity_tombstones entry FAILS and names the collection", () => {
    const r = check((j) => { j.fieldOverrides = j.fieldOverrides.filter((o: any) => o.collectionGroup !== "activity_tombstones"); });
    expect(r.code).toBe(1);
    expect(r.out).toContain("activity_tombstones");
    expect(r.out).toContain("expireAt");
  });

  test("ttl set to false FAILS", () => {
    const r = check((j) => { tomb(j).ttl = false; });
    expect(r.code).toBe(1);
    expect(r.out).toContain("activity_tombstones");
  });

  test("the ttl key deleted FAILS", () => {
    const r = check((j) => { delete tomb(j).ttl; });
    expect(r.code).toBe(1);
  });

  test("ttl declared on a different field FAILS", () => {
    const r = check((j) => { tomb(j).fieldPath = "deletedAt"; });
    expect(r.code).toBe(1);
    expect(r.out).toContain("expireAt");
  });

  test("ttl declared on a different collection group FAILS", () => {
    const r = check((j) => { tomb(j).collectionGroup = "activity_tombstones_v2"; });
    expect(r.code).toBe(1);
    expect(r.out).toContain("activity_tombstones");
  });

  test("a missing fieldOverrides section FAILS (all required entries are named)", () => {
    const r = check((j) => { delete j.fieldOverrides; });
    expect(r.code).toBe(1);
    expect(r.out).toContain("activity_tombstones");
    expect(r.out).toContain("accountDeletionRetries");
    expect(r.out).toContain("nutrition_cache");
  });

  test("removing only the pre-existing accountDeletionRetries entry FAILS and names only that one", () => {
    const r = check((j) => { j.fieldOverrides = j.fieldOverrides.filter((o: any) => o.collectionGroup !== "accountDeletionRetries"); });
    expect(r.code).toBe(1);
    expect(r.out).toContain("accountDeletionRetries");
    expect(r.out).not.toContain("collectionGroup activity_tombstones");
  });

  test("an unreadable or non-JSON file FAILS", () => {
    const file = path.join(dir, "broken.json");
    fs.writeFileSync(file, "{ not json");
    expect(run(CHECKER, dir, [file]).code).toBe(1);
    expect(run(CHECKER, dir, [path.join(dir, "does_not_exist.json")]).code).toBe(1);
  });
});

// ---------------------------------------------------------------------------------------------
// A6: corrected lifecycle-policy text for activity_tombstones (and the runbook)
// ---------------------------------------------------------------------------------------------
describe("A6 lifecycle policy text for activity_tombstones", () => {
  const policy = JSON.parse(read("scripts/ci/data_lifecycle_policy.json")).collections;
  const reason: string = policy.activity_tombstones.reason;

  test("the reason no longer calls the TTL an operator step outside the repository", () => {
    expect(reason).not.toMatch(/outside the repository/i);
    expect(reason).not.toMatch(/OPERATOR step/);
  });

  test("the reason says the TTL is a fieldOverride in firestore.indexes.json, and that file really declares it", () => {
    expect(reason).toContain("firestore.indexes.json");
    expect(reason).toMatch(/ttl fieldOverride/);
    const idx = JSON.parse(read("firestore.indexes.json"));
    expect(idx.fieldOverrides.some((o: any) => o.collectionGroup === "activity_tombstones" && o.fieldPath === "expireAt" && o.ttl === true)).toBe(true);
  });

  test("the classification, owner-only read and closed writes are unchanged by the text fix", () => {
    expect(policy.activity_tombstones.classification).toBe("DELETE");
    expect(policy.activity_tombstones.clientAccess[0].access).toEqual({ read: "OWNER", create: "NONE", update: "NONE", delete: "NONE" });
    expect(reason).toContain("400 days");
  });

  test("the runbook describes the TTL as deployed with the indexes, not as a manual-only console step", () => {
    const rb = read("runbooks/activity_stream_bucket.md");
    const sec = rb.slice(rb.indexOf("## 5. Tombstone TTL policy"), rb.indexOf("## 6."));
    expect(sec.length).toBeGreaterThan(100);
    expect(sec).toContain("fieldOverrides");
    expect(sec).toContain("firestore.indexes.json");
    expect(sec).not.toMatch(/outside the repository/i);
  });

  test("the lifecycle coverage checker still passes on the repository", () => {
    const r = run(path.join(REPO, "scripts/ci/check_data_lifecycle_coverage.js"), REPO);
    expect(r.code).toBe(0);
  });
});

// ---------------------------------------------------------------------------------------------
// A9 / F42: privacy page text, tied to what the code and the rules actually do
// ---------------------------------------------------------------------------------------------
describe("A9/F42 public/privacy.html summary-sync disclosure (DRAFT wording, English only)", () => {
  const raw = read("public/privacy.html");
  const full = raw.replace(/&#x27;/g, "'").replace(/&quot;/g, '"');
  const en = full.slice(0, full.indexOf("<h2>Кто отвечает"));
  const para = (startsWith: string): string => {
    const m = new RegExp(`<p>(?:<strong>)?${startsWith}[\\s\\S]*?</p>`).exec(en);
    return m ? m[0] : "";
  };
  const summaryPara = para("Activity summaries in your account");

  test("the English section is found and the page has the summary paragraph exactly once as a heading", () => {
    expect(en.length).toBeGreaterThan(1000);
    expect(summaryPara).not.toBe("");
    expect(en.match(/<strong>Activity summaries in your account\.<\/strong>/g)).toHaveLength(1);
  });

  test("the paragraph names Health Connect and Apple Health sourced steps and active calories", () => {
    expect(summaryPara).toMatch(/steps/);
    expect(summaryPara).toMatch(/active calories/);
    expect(summaryPara).toMatch(/Health Connect/);
    expect(summaryPara).toMatch(/Apple Health/);
  });

  test("the paragraph states there is no separate switch and that it follows the app's activity sync", () => {
    expect(summaryPara).toMatch(/There is no separate switch/);
    expect(summaryPara).toMatch(/follows the activity sync/);
  });

  test("the paragraph keeps heart rate and routes out of the summary and promises deletion", () => {
    expect(summaryPara).toMatch(/Heart rate values and routes are not part of the summary/);
    expect(summaryPara).toMatch(/deleted when you delete the activity or your account/);
  });

  test("the Health Connect exception sentence qualifies the 'never leave your phone' claim", () => {
    const sentence = en.match(/<p>Apart from the activity summaries[\s\S]*?<\/p>/);
    expect(sentence).not.toBeNull();
    expect(sentence![0]).toContain('described under "Activity summaries in your account"');
    expect(sentence![0]).toMatch(/those readings never leave your phone/);
    expect(sentence![0]).toMatch(/not written to this app's servers/);
  });

  test("every English 'never leave your phone' claim about the readings is the qualified one (no unqualified copy remains)", () => {
    const hits = [...en.matchAll(/[^.<>]*readings never leave your phone/g)].map((m) => m[0]);
    expect(hits.length).toBeGreaterThanOrEqual(1);
    for (const h of hits) expect(h).toMatch(/Apart from the activity summaries/);
  });

  test("the cross-reference title in the exception sentence equals the real paragraph title", () => {
    const ref = /described under "([^"]+)" below/.exec(en);
    expect(ref?.[1]).toBe("Activity summaries in your account");
    expect(en).toContain(`<strong>${ref![1]}.</strong>`);
  });

  test("the GPS paragraph from epic 6b is intact (GPS upload, expiry choice, heart rate stays on the device)", () => {
    expect(en).toMatch(/Heart rate stays on the device/);
    expect(en).toMatch(/90 days, 1 year, 2 years or never/);
  });

  // The page must not claim what the code does not do: every field the paragraph lists is an
  // allowlisted summary key, and no heart-rate or geometry key can be stored.
  const rules = read("firestore.rules");
  const allow = (() => {
    const start = rules.indexOf("function activitySummaryOk");
    const m = /hasOnly\(\[([\s\S]*?)\]\)/.exec(rules.slice(start));
    return [...(m ? m[1] : "").matchAll(/'([A-Za-z]+)'/g)].map((x) => x[1]);
  })();
  // Literal mapping from the paragraph's wording to the design 3.2 keys.
  const CLAIMED: Array<[RegExp, string]> = [
    [/\bsport\b/, "sport"],
    [/start and end time/, "startUtc"],
    [/start and end time/, "endUtc"],
    [/\bduration\b/, "movingTimeS"],
    [/\bdistance\b/, "distanceM"],
    [/\bpower\b/, "avgPowerW"],
    [/\bcadence\b/, "avgCadence"],
    [/\bsteps\b/, "steps"],
    [/calories/, "activeEnergyKcal"],
  ];
  test.each(CLAIMED)("claim %s is backed by the summary key %s in the rules allowlist", (re, key) => {
    expect(summaryPara).toMatch(re);
    expect(allow).toContain(key);
  });
  test("the rules allowlist parsed here is the real 32-key list", () => {
    expect(allow).toHaveLength(32);
  });
  test("no heart-rate or route-geometry key is in the rules allowlist (the 'not part of the summary' claim holds)", () => {
    const FORBIDDEN = ["avgHrBpm", "maxHrBpm", "heartRate", "hr", "polyline", "points", "bbox", "startLat", "startLon", "lats", "lons", "route", "geohash", "placeName", "laps", "provenance", "extras"];
    expect(allow.filter((k) => FORBIDDEN.includes(k))).toEqual([]);
    expect(allow).toContain("hasRoute"); // a flag only, no geometry
  });
  test("the activity cloud settings callable has no separate summary switch (the 'no separate switch' claim holds)", () => {
    const src = read("functions/src/activity_streams/set_settings.ts");
    expect(src).not.toMatch(/summarySync|syncSummar|summariesEnabled|summaryConsent/i);
  });
});

// ---------------------------------------------------------------------------------------------
// A5 / F38: access-policy checker allowlist and the pinned pre-S02 violations
// ---------------------------------------------------------------------------------------------
describe("A5/F38 data access policy checker", () => {
  const CHECKER = "scripts/ci/check_data_access_policy.js";
  const PRE_S02 = [
    "functions/src/body_scan/manage.ts:218",
    "functions/src/body_scan/manage.ts:317",
    "functions/src/body_scan/manage.ts:355",
    "functions/src/nutrition_cache.ts:109",
    "functions/src/nutrition_cache.ts:74",
  ];
  const violations = (out: string): string[] =>
    out.split("\n").filter((l) => /UNRESOLVED|NO clientAccess/.test(l))
      .map((l) => /(functions(?:-equipment-identity)?\/src\/[\w/]+\.ts:\d+)/.exec(l)?.[1] ?? l.slice(0, 160)).sort();

  test("ACTIVITY_USER_COLLECTIONS has exactly the five entries, usage last (A5)", () => {
    expect([...ACTIVITY_USER_COLLECTIONS]).toEqual(["activities", "activity_streams", "activity_settings", "activity_tombstones", "usage"]);
  });

  test("every entry of ACTIVITY_USER_COLLECTIONS is declared in the lifecycle policy", () => {
    const c = JSON.parse(read("scripts/ci/data_lifecycle_policy.json")).collections;
    for (const name of ACTIVITY_USER_COLLECTIONS) expect(c[name]).toBeDefined();
  });

  test("the repository run reports exactly the five pre-S02 violations and nothing from S02 (F38)", () => {
    const r = run(path.join(REPO, CHECKER), REPO);
    expect(r.code).toBe(1); // still FAILED because of the five
    expect(violations(r.out)).toEqual([...PRE_S02].sort());
    expect(violations(r.out).filter((l) => /activit|account_export/i.test(l))).toEqual([]);
  });

  describe("on a copy of the tree", () => {
    let root: string;
    beforeAll(() => {
      root = fs.mkdtempSync(path.join(os.tmpdir(), "s02-access-"));
      const skip = (src: string): boolean => !/__tests__|node_modules|[\\/]\.dart_tool|[\\/]build[\\/]/.test(src);
      fs.cpSync(path.join(REPO, "scripts/ci"), path.join(root, "scripts/ci"), { recursive: true });
      fs.copyFileSync(path.join(REPO, "firestore.rules"), path.join(root, "firestore.rules"));
      for (const d of ["functions/src", "functions-equipment-identity/src", "mobile/lib"]) {
        fs.cpSync(path.join(REPO, d), path.join(root, d), { recursive: true, filter: skip });
      }
    });
    afterAll(() => fs.rmSync(root, { recursive: true, force: true }));
    const lateSweep = (): string => path.join(root, "functions/src/activity_streams/late_sweep.ts");
    const original = fs.readFileSync(path.join(REPO, "functions/src/activity_streams/late_sweep.ts"), "utf8");
    afterEach(() => fs.writeFileSync(lateSweep(), original));

    test("the unmutated copy gives the same five violations (the instrument works)", () => {
      expect(violations(run(path.join(root, CHECKER), root).out)).toEqual([...PRE_S02].sort());
    });

    test("the audited late_sweep.ts entry points at the real dynamic call and names usage", () => {
      const checker = read(CHECKER);
      const m = /file: path\.join\(REPO_ROOT, 'functions\/src\/activity_streams\/late_sweep\.ts'\),\s*line: (\d+),\s*arg: '([^']+)',\s*reason: '([^']+)'/.exec(checker);
      expect(m).not.toBeNull();
      const line = Number(m![1]);
      expect(original.split("\n")[line - 1]).toContain("fs.collection(`users/${uid}/${name}`)");
      expect(m![3]).toContain("usage");
    });

    test("moving the audited call by one line makes the checker flag late_sweep.ts (the allowlist is line-exact)", () => {
      fs.writeFileSync(lateSweep(), `// shifted by one line\n${original}`);
      const r = run(path.join(root, CHECKER), root);
      expect(r.code).toBe(1);
      expect(violations(r.out)).toContain("functions/src/activity_streams/late_sweep.ts:204");
    });

    test("a NEW unaudited dynamic collection call in an S02 file is flagged", () => {
      fs.writeFileSync(lateSweep(), `${original}\nexport const extraProbe = (fs: any, uid: string, n: string) => fs.collection(\`users/\${uid}/\${n}\`);\n`);
      const r = run(path.join(root, CHECKER), root);
      expect(r.code).toBe(1);
      expect(violations(r.out).some((v) => v.startsWith("functions/src/activity_streams/late_sweep.ts:"))).toBe(true);
    });

    test("removing the usage row from the policy copy adds a violation that names usage", () => {
      const p = path.join(root, "scripts/ci/data_lifecycle_policy.json");
      const saved = fs.readFileSync(p, "utf8");
      try {
        const j = JSON.parse(saved);
        delete j.collections.usage;
        fs.writeFileSync(p, JSON.stringify(j, null, 2));
        const r = run(path.join(root, CHECKER), root);
        expect(r.code).toBe(1);
        expect(r.out).toMatch(/NO clientAccess DECLARATION[^\n]*usage/);
      } finally {
        fs.writeFileSync(p, saved);
      }
    });
  });
});
