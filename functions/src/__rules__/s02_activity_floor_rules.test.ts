/**
 * S02 test epic 5 -- the PERMANENT FLOOR of the activity rules (design 12.1):
 * the four owner-wildcard exclusions and the closed blocks. Plan ids: R17, R18,
 * R31.
 *
 * Falsification method: the exclusion is removed from a COPY of the rules text
 * (`removeExclusion`) which is loaded into a second emulator project. In that
 * mutated copy a write the real rules refuse must be ALLOWED -- which proves the
 * probe writes of the other files can detect the removal. `firestore.rules`
 * itself is never edited.
 *
 * Independent of the `debug_sessions` rule (R22 lives in its own file) so
 * reverting the telemetry rule cannot fail the floor tests.
 */
import { assertFails, assertSucceeds, RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { deleteDoc, doc, getDoc, setDoc, updateDoc } from "firebase/firestore";
import {
  ALICE,
  FLOOR_NAMES,
  FloorName,
  actId,
  activityPath,
  floorViolations,
  makeEnv,
  openActivitiesDelete,
  openServerBlockWrite,
  readRules,
  removeExclusion,
  summary,
  ts,
  wildcardClause,
} from "./s02_rules_support";

let realEnv: RulesTestEnvironment;
const mutatedEnvs: RulesTestEnvironment[] = [];

beforeAll(async () => {
  realEnv = await makeEnv("demo-s02-floor-real");
});
afterAll(async () => {
  await realEnv?.cleanup();
  for (const e of mutatedEnvs) await e.cleanup();
});

/** Probe writes that the floor must refuse for the owner, one per protected path. */
const PROBES: Record<FloorName, { path: string; body: Record<string, unknown> }> = {
  activities: {
    path: activityPath(ALICE, actId(1)),
    body: summary({ polyline: "encodedPolylineOfTheRoute" }),
  },
  activity_streams: {
    path: `users/${ALICE}/activity_streams/${actId(1)}`,
    body: { state: "stored", objectPath: `streams/other/x/u.json.gz`, expiresAt: null },
  },
  activity_settings: {
    path: `users/${ALICE}/activity_settings/main`,
    body: { cloudStreams: { version: 1, acceptedAt: ts("2026-03-01T10:00:00Z") }, streamRetentionDays: 0 },
  },
  activity_tombstones: {
    path: `users/${ALICE}/activity_tombstones/${actId(1)}`,
    body: { deletedAt: ts("2026-03-01T10:00:00Z"), expireAt: ts("2999-01-01T00:00:00Z") },
  },
};

const ownerOf = (e: RulesTestEnvironment) => e.authenticatedContext(ALICE).firestore();

let seq = 0;
async function loadMutated(rules: string): Promise<RulesTestEnvironment> {
  const e = await makeEnv(`demo-s02-floor-mut-${++seq}`, rules);
  mutatedEnvs.push(e);
  return e;
}

describe("R17 exclusion falsification: removing one write exclusion from a copy of the rules makes the probe write ALLOWED", () => {
  test.each(FLOOR_NAMES.map((n) => [n]))("%s", async (name) => {
    const probe = PROBES[name];
    // Real rules refuse the probe (this is what R04, R15, R16, R27 assert in their own files).
    await assertFails(setDoc(doc(ownerOf(realEnv), probe.path), probe.body));

    const real = readRules();
    const mutatedText = removeExclusion(real, "write", name);
    expect(mutatedText).not.toBe(real); // the mutation really changed the text
    expect(wildcardClause(mutatedText, "write")).not.toContain(`'${name}'`);

    const mutated = await loadMutated(mutatedText);
    await assertSucceeds(setDoc(doc(ownerOf(mutated), probe.path), probe.body));

    // The mutation is local to the removed name: the other three probes are still refused in the same copy.
    for (const other of FLOOR_NAMES.filter((n) => n !== name)) {
      await assertFails(setDoc(doc(ownerOf(mutated), PROBES[other].path), PROBES[other].body));
    }
    // Control: a collection with its own long-standing exclusion is untouched by this mutation.
    await assertFails(setDoc(doc(ownerOf(mutated), `users/${ALICE}/usage/2026-03-01`), { n: 1 }));
  });

  test("owner delete: opening `delete` of the activities block in a copy lets the owner delete (R14 can detect that)", async () => {
    const id = actId(2);
    const real = readRules();
    await realEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), activityPath(ALICE, id)), summary());
    });
    await assertFails(deleteDoc(doc(ownerOf(realEnv), activityPath(ALICE, id))));

    const mutated = await loadMutated(openActivitiesDelete(real));
    await mutated.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), activityPath(ALICE, id)), summary());
    });
    await assertSucceeds(deleteDoc(doc(ownerOf(mutated), activityPath(ALICE, id))));
  });

  test("owner update of a server row: giving a copy's activity_tombstones block `write` lets the owner forge expireAt", async () => {
    const mutated = await loadMutated(openServerBlockWrite(readRules(), "activity_tombstones"));
    const probe = PROBES.activity_tombstones;
    await assertFails(setDoc(doc(ownerOf(realEnv), probe.path), probe.body));
    await mutated.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), probe.path), { deletedAt: ts("2026-03-01T10:00:00Z") });
    });
    // The block grant alone is not enough while the wildcard exclusion is intact? Both layers must agree: the
    // block's own `write` is allowed, so the owner write succeeds in the copy.
    await assertSucceeds(updateDoc(doc(ownerOf(mutated), probe.path), { expireAt: ts("2999-01-01T00:00:00Z") }));
  });

  test("the read clause exclusion is not behaviourally observable for owner-readable paths (owner read is allowed by the block either way)", async () => {
    // This documents why R18 is a text check: removing the READ exclusion changes nothing an owner can observe.
    const mutated = await loadMutated(removeExclusion(readRules(), "read", "activity_streams"));
    await mutated.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), PROBES.activity_streams.path), { state: "stored" });
    });
    await assertSucceeds(getDoc(doc(ownerOf(mutated), PROBES.activity_streams.path)));
    await realEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), PROBES.activity_streams.path), { state: "stored" });
    });
    await assertSucceeds(getDoc(doc(ownerOf(realEnv), PROBES.activity_streams.path)));
  });
});

describe("R18 both wildcard clauses (read and write) name every protected collection", () => {
  const rules = readRules();

  test.each(FLOOR_NAMES.flatMap((n) => [[n, "read"], [n, "write"]] as Array<[FloorName, "read" | "write"]>))(
    "%s is excluded in the %s clause",
    (name, clause) => {
      expect(wildcardClause(rules, clause)).toMatch(new RegExp(`coll\\s*!=\\s*'${name}'`));
    },
  );

  test.each(FLOOR_NAMES.flatMap((n) => [[n, "read"], [n, "write"]] as Array<[FloorName, "read" | "write"]>))(
    "removing %s from the %s clause of a copy is found by the text lint",
    (name, clause) => {
      const mutated = removeExclusion(rules, clause, name);
      expect(wildcardClause(mutated, clause)).not.toMatch(new RegExp(`coll\\s*!=\\s*'${name}'`));
      expect(floorViolations(mutated)).toContain(`${clause} clause lacks the exclusion of ${name}`);
    },
  );
});

describe("R31 permanent floor lint", () => {
  const rules = readRules();

  test("the real rules satisfy the floor", () => {
    expect(floorViolations(rules)).toEqual([]);
  });

  test("the lint fails on each of 5 mutated copies (4 exclusions removed, activities delete opened)", () => {
    for (const name of FLOOR_NAMES) {
      const found = floorViolations(removeExclusion(rules, "write", name));
      expect(found).toEqual([`write clause lacks the exclusion of ${name}`]);
    }
    const opened = floorViolations(openActivitiesDelete(rules));
    expect(opened).toEqual(["activities grants delete with a condition other than false"]);
  });

  test("the lint also fails when read exclusions go, a server block opens write, or a match block disappears", () => {
    for (const name of FLOOR_NAMES) {
      expect(floorViolations(removeExclusion(rules, "read", name))).toEqual([`read clause lacks the exclusion of ${name}`]);
    }
    for (const name of ["activity_streams", "activity_settings", "activity_tombstones"] as const) {
      const found = floorViolations(openServerBlockWrite(rules, name));
      expect(found).toEqual([`${name} grants write with a condition other than false`]);
    }
    const renamed = rules.replace("match /users/{uid}/activity_tombstones/{id} {", "match /users/{uid}/activity_tombstones_x/{id} {");
    expect(renamed).not.toBe(rules);
    expect(floorViolations(renamed)).toContain("no match block for users/{uid}/activity_tombstones");
  });

  test("a delete that is commented out does not count as `if false` (comments are stripped before parsing)", () => {
    const commented = rules.replace(
      /allow delete: if false;(\r?\n\s*\}\r?\n\s*match \/users\/\{uid\}\/activity_streams)/,
      (_m, tail: string) => "// allow delete: if false;" + tail,
    );
    expect(commented).not.toBe(rules);
    expect(floorViolations(commented)).toContain("activities has no delete statement (delete must be an explicit `if false`)");
  });

  test("every block grants through isOrdinaryUser() (the canary gets nothing, CR-05)", () => {
    const activityBlock = rules.slice(rules.indexOf("match /users/{uid}/activities/{activityId} {"), rules.indexOf("match /nutrition_cache/{key}"));
    expect(activityBlock).not.toMatch(/request\.auth\s*!=\s*null\s*&&/);
    const grants = activityBlock.match(/allow (read|create|update): if ([^;]+);/g) ?? [];
    expect(grants.length).toBeGreaterThanOrEqual(5);
    for (const g of grants) expect(g).toContain("isOrdinaryUser()");
  });
});
