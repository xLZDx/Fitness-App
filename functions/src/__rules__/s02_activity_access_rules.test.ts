/**
 * S02 test epic 5 -- who may do what on the four activity paths, and the
 * default deny of `activity_account_state`. Plan ids: R02, R03, R15, R16, R27,
 * R30 (behavioural half).
 *
 * Every refusal is paired with a control that succeeds: the owner read of the
 * same document, and the Admin-equivalent write (`withSecurityRulesDisabled`)
 * that creates the fixture, so an emulator that denies everything cannot fake a
 * pass.
 *
 * Reading the plan: its "Fails if" column describes what would make the test
 * fail. R15 "owner read denied" therefore means the owner read must be ALLOWED,
 * and R27 "another user read succeeds" means that read must be DENIED.
 */
import { assertFails, assertSucceeds, RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { collection, deleteDoc, doc, getDoc, getDocs, setDoc, updateDoc } from "firebase/firestore";
import { readFileSync } from "fs";
import { ALICE, BOB, POLICY_PATH, actId, activityPath, makeEnv, readRules, summary, ts, stripComments } from "./s02_rules_support";

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await makeEnv("demo-s02-access");
});
afterAll(async () => env?.cleanup());
beforeEach(async () => env.clearFirestore());

const asAlice = () => env.authenticatedContext(ALICE).firestore();
const asBob = () => env.authenticatedContext(BOB).firestore();
const signedOut = () => env.unauthenticatedContext().firestore();
/** The canary identity minted for the SAME uid as the owner (isCanaryToken must still lock it out). */
const asCanaryOfAlice = () => env.authenticatedContext(ALICE, { canary: true }).firestore();

const seed = (path: string, data: Record<string, unknown>) =>
  env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), path), data);
  });

const exists = async (path: string): Promise<boolean> => {
  let out = false;
  await env.withSecurityRulesDisabled(async (ctx) => {
    out = (await getDoc(doc(ctx.firestore(), path))).exists();
  });
  return out;
};

const ID = actId(1);
const FRESH = actId(2);

/** The four paths with a valid-looking fixture body and a body for a fresh create. */
const PATHS: Array<{ name: string; path: string; fresh: string; body: Record<string, unknown> }> = [
  {
    name: "activities",
    path: activityPath(ALICE, ID),
    fresh: activityPath(ALICE, FRESH),
    body: summary(),
  },
  {
    name: "activity_streams",
    path: `users/${ALICE}/activity_streams/${ID}`,
    fresh: `users/${ALICE}/activity_streams/${FRESH}`,
    body: { state: "stored", objectPath: `streams/${ALICE}/${ID}/u1.json.gz`, bytes: 10, expiresAt: null },
  },
  {
    name: "activity_settings",
    path: `users/${ALICE}/activity_settings/main`,
    fresh: `users/${ALICE}/activity_settings/other`,
    body: { streamRetentionDays: 30, cloudStreams: { version: 1, acceptedAt: ts("2026-03-01T10:00:00Z") } },
  },
  {
    name: "activity_tombstones",
    path: `users/${ALICE}/activity_tombstones/${ID}`,
    fresh: `users/${ALICE}/activity_tombstones/${FRESH}`,
    body: { deletedAt: ts("2026-03-02T10:00:00Z"), expireAt: ts("2027-03-02T10:00:00Z") },
  },
];

const parent = (path: string) => path.slice(0, path.lastIndexOf("/"));

describe("R02 cross-user and signed-out callers", () => {
  describe.each(PATHS)("$name", ({ path, fresh, body }) => {
    beforeEach(async () => {
      await seed(path, body);
    });

    test("control: the owner reads the document and lists the collection", async () => {
      await assertSucceeds(getDoc(doc(asAlice(), path)));
      await assertSucceeds(getDocs(collection(asAlice(), parent(path))));
    });

    test.each([
      ["another signed-in user", asBob],
      ["a signed-out caller", signedOut],
    ])("%s cannot read, list, create, update or delete the owner's document", async (_who, db) => {
      await assertFails(getDoc(doc(db(), path)));
      await assertFails(getDocs(collection(db(), parent(path))));
      await assertFails(setDoc(doc(db(), fresh), body));
      await assertFails(updateDoc(doc(db(), path), { rev: 2 }));
      await assertFails(deleteDoc(doc(db(), path)));
      // Nothing changed behind the refusals.
      expect(await exists(path)).toBe(true);
      expect(await exists(fresh)).toBe(false);
    });
  });

  test("control for the create refusal: the owner CAN create a valid summary at the same fresh id", async () => {
    await assertSucceeds(setDoc(doc(asAlice(), activityPath(ALICE, FRESH)), summary()));
  });
});

describe("R03 the canary identity (even minted for the owner's uid) and a non-ordinary token", () => {
  describe.each(PATHS)("$name", ({ path, fresh, body }) => {
    beforeEach(async () => {
      await seed(path, body);
    });

    test("control: the ordinary owner reads the same document", async () => {
      await assertSucceeds(getDoc(doc(asAlice(), path)));
    });

    test("the canary token cannot read, list, create, update or delete", async () => {
      await assertFails(getDoc(doc(asCanaryOfAlice(), path)));
      await assertFails(getDocs(collection(asCanaryOfAlice(), parent(path))));
      await assertFails(setDoc(doc(asCanaryOfAlice(), fresh), body));
      await assertFails(updateDoc(doc(asCanaryOfAlice(), path), { rev: 2 }));
      await assertFails(deleteDoc(doc(asCanaryOfAlice(), path)));
      expect(await exists(fresh)).toBe(false);
    });
  });

  test("control for the create refusal: an ordinary owner token writes a valid summary", async () => {
    await assertSucceeds(setDoc(doc(asAlice(), activityPath(ALICE, FRESH)), summary()));
  });
});

describe("R15 activity_streams is server-authored", () => {
  const path = `users/${ALICE}/activity_streams/${ID}`;
  const body = PATHS[1].body;

  test("the owner can read the index row, another user cannot", async () => {
    await seed(path, body);
    await assertSucceeds(getDoc(doc(asAlice(), path)));
    await assertFails(getDoc(doc(asBob(), path)));
  });

  test("the owner cannot create, update or delete an index row (a forged expiresAt or objectPath)", async () => {
    await assertFails(setDoc(doc(asAlice(), path), body));
    expect(await exists(path)).toBe(false);
    await seed(path, body); // the Admin-equivalent write succeeds
    await assertFails(updateDoc(doc(asAlice(), path), { expiresAt: ts("2999-01-01T00:00:00Z") }));
    await assertFails(updateDoc(doc(asAlice(), path), { objectPath: `streams/${BOB}/x/u.json.gz` }));
    await assertFails(deleteDoc(doc(asAlice(), path)));
    expect(await exists(path)).toBe(true);
  });
});

describe("R16 activity_settings/main is server-authored", () => {
  const path = `users/${ALICE}/activity_settings/main`;

  test("the owner cannot forge a cloudStreams consent, by create or by update", async () => {
    const forged = { cloudStreams: { version: 1, acceptedAt: ts("2026-03-01T10:00:00Z") }, streamRetentionDays: 0 };
    await assertFails(setDoc(doc(asAlice(), path), forged));
    expect(await exists(path)).toBe(false);
    await seed(path, { streamRetentionDays: 30 });
    await assertFails(updateDoc(doc(asAlice(), path), { cloudStreams: forged.cloudStreams }));
    await assertFails(updateDoc(doc(asAlice(), path), { recomputePending: true }));
    await assertFails(deleteDoc(doc(asAlice(), path)));
    expect(await exists(path)).toBe(true);
  });

  test("the owner reads their settings, another user does not", async () => {
    await seed(path, { streamRetentionDays: 30 });
    await assertSucceeds(getDoc(doc(asAlice(), path)));
    await assertFails(getDoc(doc(asBob(), path)));
  });
});

describe("R27 tombstone path permissions", () => {
  const path = `users/${ALICE}/activity_tombstones/${ID}`;
  const body = PATHS[3].body;

  test("the owner can READ a tombstone (devices learn deleted ids) and list the collection", async () => {
    await seed(path, body);
    await assertSucceeds(getDoc(doc(asAlice(), path)));
    await assertSucceeds(getDocs(collection(asAlice(), parent(path))));
  });

  test("the owner cannot create, update or delete a tombstone", async () => {
    await assertFails(setDoc(doc(asAlice(), path), body));
    expect(await exists(path)).toBe(false);
    await seed(path, body);
    await assertFails(updateDoc(doc(asAlice(), path), { expireAt: ts("2999-01-01T00:00:00Z") }));
    await assertFails(deleteDoc(doc(asAlice(), path)));
    expect(await exists(path)).toBe(true);
  });

  test.each([
    ["another user", asBob],
    ["a signed-out caller", signedOut],
    ["the canary token", asCanaryOfAlice],
  ])("%s cannot read the tombstone", async (_who, db) => {
    await seed(path, body);
    await assertSucceeds(getDoc(doc(asAlice(), path))); // control
    await assertFails(getDoc(doc(db(), path)));
  });
});

describe("R30 activity_account_state has no client access (top-level default deny)", () => {
  const path = `activity_account_state/${ALICE}`;
  const fence = { fenceAt: ts("2026-03-01T10:00:00Z"), lateSweepAt: ts("2026-03-01T10:20:00Z") };

  test("positive control: the Admin-equivalent writes and reads the fence document", async () => {
    await seed(path, fence);
    expect(await exists(path)).toBe(true);
  });

  test.each([
    ["the owner of the same uid", () => env.authenticatedContext(ALICE).firestore()],
    ["another signed-in user", asBob],
    ["a signed-out caller", signedOut],
    ["the canary token of the same uid", asCanaryOfAlice],
  ])("%s cannot get, list, create, update or delete it", async (_who, db) => {
    await seed(path, fence);
    await assertFails(getDoc(doc(db(), path)));
    await assertFails(getDocs(collection(db(), "activity_account_state")));
    await assertFails(setDoc(doc(db(), `activity_account_state/${BOB}`), fence));
    await assertFails(setDoc(doc(db(), `activity_account_state/${ALICE}`), { fenceAt: ts("2020-01-01T00:00:00Z") }));
    await assertFails(updateDoc(doc(db(), path), { lateSweepDone: true }));
    await assertFails(deleteDoc(doc(db(), path)));
    expect(await exists(path)).toBe(true);
    expect(await exists(`activity_account_state/${BOB}`)).toBe(false);
  });

  test("the owner cannot clear their own fence to resume writing (the attack the default deny blocks)", async () => {
    await seed(path, fence);
    await assertFails(deleteDoc(doc(asAlice(), path)));
    await assertFails(setDoc(doc(asAlice(), activityPath(ALICE, ID)), summary())); // still fenced
  });
});

describe("R30 rules-text and policy assertions for activity_account_state", () => {
  const rules = stripComments(readRules());

  test("no match block names activity_account_state and no top-level wildcard grants access", () => {
    expect(rules).not.toMatch(/match\s+\/activity_account_state/);
    expect(rules).not.toMatch(/match\s+\/\{document=\*\*\}/);
    expect(rules).not.toMatch(/match\s+\/\{[A-Za-z]+\}\s*\{/); // no top-level single-segment wildcard either
  });

  test("the rules only read the fence through exists()", () => {
    const uses = rules.match(/activity_account_state/g) ?? [];
    expect(uses).toHaveLength(1);
    expect(rules).toMatch(/!exists\(\/databases\/\$\(database\)\/documents\/activity_account_state\/\$\(uid\)\)/);
  });

  test("the withdrawn activity_late_sweeps collection is absent from the rules and the lifecycle policy", () => {
    expect(readRules()).not.toContain("activity_late_sweeps");
    expect(readFileSync(POLICY_PATH, "utf8")).not.toContain("activity_late_sweeps");
  });

  test("the lifecycle policy declares activity_account_state as NONE for every client verb", () => {
    const policy = JSON.parse(readFileSync(POLICY_PATH, "utf8")) as {
      collections: Record<string, { clientAccess?: Array<{ path: string; access: Record<string, string> }> }>;
    };
    const rows = policy.collections["activity_account_state"]?.clientAccess ?? [];
    expect(rows).toHaveLength(1);
    expect(rows[0].path).toBe("/activity_account_state/{uid}");
    expect(rows[0].access).toEqual({ read: "NONE", create: "NONE", update: "NONE", delete: "NONE" });
  });
});
