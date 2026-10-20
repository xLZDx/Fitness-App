/**
 * S02 test epic 8b, remediation A12 -- `primarySourceId` of a cloud summary must follow the
 * stream `sourceId` pattern (`^[A-Za-z0-9._:-]{1,64}$`) and must not be coordinate-like
 * (a number with two or more decimals, for example `173.25` or `51.5007`).
 *
 * Oracle: the remediation notes (A12) and the stream validator pattern of design 5.1a, written
 * out literally below, never read from `firestore.rules`. Every denial is paired with an accepted
 * control at the SAME id, so a broken emulator or a body error cannot fake a pass. The test runs
 * against the real Firestore emulator; both create and update are covered.
 */
import { assertFails, assertSucceeds, RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc } from "firebase/firestore";
import { ALICE, activityPath, actId, makeEnv, summary } from "./s02_rules_support";

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await makeEnv("demo-s02-source-id");
});
afterAll(async () => env?.cleanup());
beforeEach(async () => env.clearFirestore());

const ref = (id: string) => doc(env.authenticatedContext(ALICE).firestore(), activityPath(ALICE, id));
const create = (id: string, data: Record<string, unknown>) => setDoc(ref(id), data);
const seed = (id: string, data: Record<string, unknown>) =>
  env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), activityPath(ALICE, id)), data);
  });
const adminRead = async (id: string): Promise<Record<string, any> | null> => {
  let out: Record<string, any> | null = null;
  await env.withSecurityRulesDisabled(async (ctx) => {
    const s = await getDoc(doc(ctx.firestore(), activityPath(ALICE, id)));
    out = s.exists() ? (s.data() as Record<string, any>) : null;
  });
  return out;
};

const ACCEPTED: string[] = [
  "Watch4",
  "health-connect.v2:abc",
  "app",
  "ble-strap-1",
  "a",
  "A.b_c:d-e",
  "v1.5", // one decimal digit is not coordinate-like
  "x".repeat(64), // exactly the maximum length
  "1.5",
  "3.x",
];

const REJECTED: Array<[string, string]> = [
  ["a coordinate-like number with two decimals", "173.25"],
  ["a latitude", "51.5007"],
  ["a negative longitude embedded in a label", "home-0.1276"],
  ["a place label with a space and a coordinate pair", "home 51.5007,-0.1276"],
  ["a space", "a b"],
  ["a comma", "a,b"],
  ["a comma between digits", "51,-0"],
  ["a slash", "a/b"],
  ["a plus sign", "a+b"],
  ["a non-ASCII letter", "Wätch4"],
  ["a trailing newline", "Watch4\n"],
  ["the empty string", ""],
  ["65 characters (one over the maximum)", "x".repeat(65)],
  ["a long id (200 characters)", "y".repeat(200)],
  ["a coordinate-like fragment inside a long valid id", "ab" + "51.25" + "cd"],
  ["three decimals inside a version string", "v2.123"],
];

describe("A12 create", () => {
  test.each(ACCEPTED)("primarySourceId %j is accepted and stored unchanged", async (id) => {
    await assertSucceeds(create(actId(1), summary({ primarySourceId: id })));
    expect((await adminRead(actId(1)))?.primarySourceId).toBe(id);
  });

  test.each(REJECTED)("%s is denied; the same body with a valid id is accepted", async (_label, bad) => {
    await assertFails(create(actId(2), summary({ primarySourceId: bad })));
    expect(await adminRead(actId(2))).toBeNull();
    await assertSucceeds(create(actId(2), summary({ primarySourceId: "Watch4" })));
  });

  test("a summary without primarySourceId is still accepted (the key stays optional)", async () => {
    const { primarySourceId: _omit, ...rest } = summary() as Record<string, unknown>;
    await assertSucceeds(create(actId(3), rest));
  });

  test("the numeric 173.25 as a NUMBER is denied too (type check unchanged)", async () => {
    await assertFails(create(actId(4), summary({ primarySourceId: 173.25 })));
    expect(await adminRead(actId(4))).toBeNull();
  });
});

describe("A12 update", () => {
  test.each(REJECTED)("an update to %s is denied and leaves the stored id and rev", async (_label, bad) => {
    await seed(actId(10), summary({ primarySourceId: "Watch4" }));
    await assertFails(updateDoc(ref(actId(10)), { rev: 2, primarySourceId: bad }));
    const row = await adminRead(actId(10));
    expect(row?.primarySourceId).toBe("Watch4");
    expect(row?.rev).toBe(1);
    // control: the same update with a valid id passes
    await assertSucceeds(updateDoc(ref(actId(10)), { rev: 2, primarySourceId: "health-connect.v2:abc" }));
    expect((await adminRead(actId(10)))?.primarySourceId).toBe("health-connect.v2:abc");
  });

  test("an unrelated update of a document that already carries a valid id still succeeds", async () => {
    await seed(actId(11), summary({ primarySourceId: "Watch4" }));
    await assertSucceeds(updateDoc(ref(actId(11)), { rev: 2, distanceM: 10100 }));
  });
});
