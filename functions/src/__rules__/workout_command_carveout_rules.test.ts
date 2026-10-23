/**
 * Slice V0 rules tests: the five carved-out workout command collections are closed to every
 * client (owner included) for read and write, through the wildcard and the dedicated matches.
 * Style follows the s02_* files (support module, falsification on a COPY of the rules text).
 */
import { assertFails, assertSucceeds, RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { collection, collectionGroup, deleteDoc, doc, getDoc, getDocs, setDoc, updateDoc, writeBatch } from "firebase/firestore";
import { ALICE, BOB, makeEnv, parseMatchBlocks, readRules, stripComments, wildcardClause } from "./s02_rules_support";

const NAMES = [
  "workout_command_fence",
  "workout_command_receipts",
  "workout_command_policy",
  "workout_command_counters",
  "workout_typed_sessions",
] as const;

let env: RulesTestEnvironment;
beforeAll(async () => { env = await makeEnv("demo-v0-carveout"); });
afterAll(async () => env?.cleanup());
beforeEach(async () => env.clearFirestore());

const asAlice = () => env.authenticatedContext(ALICE).firestore();
const asBob = () => env.authenticatedContext(BOB).firestore();
const anon = () => env.unauthenticatedContext().firestore();
const seed = (path: string) => env.withSecurityRulesDisabled(async (c) => { await setDoc(doc(c.firestore(), path), { seeded: true }); });
const adminGet = async (path: string) => {
  let exists = false;
  await env.withSecurityRulesDisabled(async (c) => { exists = (await getDoc(doc(c.firestore(), path))).exists(); });
  return exists;
};

describe.each(NAMES)("%s is closed to every client", (name) => {
  const p = (uid: string, id = "d1") => `users/${uid}/${name}/${id}`;

  test("owner cannot get, list, create, update or delete (document level)", async () => {
    await seed(p(ALICE));
    const db = asAlice();
    await assertFails(getDoc(doc(db, p(ALICE))));
    await assertFails(getDocs(collection(db, `users/${ALICE}/${name}`)));
    await assertFails(setDoc(doc(db, p(ALICE, "new")), { x: 1 }));
    await assertFails(setDoc(doc(db, p(ALICE)), { x: 2 }));
    await assertFails(updateDoc(doc(db, p(ALICE)), { x: 3 }));
    await assertFails(deleteDoc(doc(db, p(ALICE))));
    expect(await adminGet(p(ALICE))).toBe(true); // seeded document survived
    expect(await adminGet(p(ALICE, "new"))).toBe(false);
  });

  test("owner cannot touch a nested subcollection document under it (wildcard {document=**})", async () => {
    const nested = `users/${ALICE}/${name}/d1/sub/n1`;
    await seed(nested);
    const db = asAlice();
    await assertFails(getDoc(doc(db, nested)));
    await assertFails(setDoc(doc(db, `users/${ALICE}/${name}/d1/sub/n2`), { x: 1 }));
    await assertFails(updateDoc(doc(db, nested), { x: 2 }));
    await assertFails(deleteDoc(doc(db, nested)));
  });

  test("a batched write that contains one forbidden document is refused as a whole", async () => {
    const db = asAlice();
    const b = writeBatch(db);
    b.set(doc(db, `users/${ALICE}/notes_probe/ok`), { x: 1 }); // unlisted name: allowed on its own
    b.set(doc(db, p(ALICE, "b")), { x: 1 });
    await assertFails(b.commit());
    expect(await adminGet(`users/${ALICE}/notes_probe/ok`)).toBe(false);
  });

  test("collection-group read is refused for the owner", async () => {
    await seed(p(ALICE));
    await assertFails(getDocs(collectionGroup(asAlice(), name)));
  });

  test("another user and a signed-out client are refused everything", async () => {
    await seed(p(ALICE));
    for (const db of [asBob(), anon()]) {
      await assertFails(getDoc(doc(db, p(ALICE))));
      await assertFails(setDoc(doc(db, p(ALICE, "x")), { x: 1 }));
      await assertFails(updateDoc(doc(db, p(ALICE)), { x: 1 }));
      await assertFails(deleteDoc(doc(db, p(ALICE))));
    }
  });
});

describe("other collections stay unchanged", () => {
  test("an owner still reaches an unlisted sub-collection (documented allow-list behavior)", async () => {
    await assertSucceeds(setDoc(doc(asAlice(), `users/${ALICE}/notes_probe/a`), { x: 1 }));
    await assertSucceeds(getDoc(doc(asAlice(), `users/${ALICE}/notes_probe/a`)));
  });

  test("previously protected collections stay closed to owner writes", async () => {
    for (const n of ["usage", "receipts", "subscription", "activity_streams", "activity_tombstones"]) {
      await assertFails(setDoc(doc(asAlice(), `users/${ALICE}/${n}/x`), { x: 1 }));
    }
  });

  test("a name that merely resembles a carved-out name is NOT carved out (exact-match exclusion)", async () => {
    await assertSucceeds(setDoc(doc(asAlice(), `users/${ALICE}/workout_command_fence2/a`), { x: 1 }));
    await assertSucceeds(setDoc(doc(asAlice(), `users/${ALICE}/workout_typed_session/a`), { x: 1 }));
  });
});

describe("rules text: both clauses and the dedicated blocks", () => {
  const rules = readRules();

  test.each(NAMES)("%s is excluded in the read AND the write clause of the wildcard", (n) => {
    const re = new RegExp(`coll\\s*!=\\s*'${n}'`);
    expect(re.test(wildcardClause(rules, "read"))).toBe(true);
    expect(re.test(wildcardClause(rules, "write"))).toBe(true);
  });

  test.each(NAMES)("%s has a dedicated match whose every allow is `if false`", (n) => {
    const block = parseMatchBlocks(rules).find((b) => new RegExp(`^/users/\\{uid\\}/${n}/\\{[A-Za-z]+\\}$`).test(b.path));
    expect(block).toBeDefined();
    expect(block!.allows.length).toBeGreaterThan(0);
    for (const a of block!.allows) expect(a.condition).toBe("false");
  });

  test("no other match block grants access to these paths", () => {
    const code = stripComments(rules);
    for (const n of NAMES) {
      const hits = [...code.matchAll(new RegExp(`match\\s+/[^\\s]*${n}`, "g"))];
      expect(hits.length).toBe(1);
    }
  });
});

describe("falsification on a COPY of the rules text (the exclusion is what protects)", () => {
  test.each(NAMES)("without the %s exclusion in the wildcard write clause the owner could write (so the denial above is meaningful)", async (n) => {
    const src = readRules();
    // drop the term from BOTH wildcard clauses and also open the dedicated block: only then can the owner write
    let mutated = src.replace(new RegExp(`\\s*&&\\s*coll\\s*!=\\s*'${n}'`, "g"), "");
    mutated = mutated.replace(new RegExp(String.raw`match /users/\{uid\}/${n}/\{[A-Za-z]+\}\s*\{[^}]*\}`), "");
    const env2 = await makeEnv("demo-v0-carveout-mut-" + n.replace(/_/g, "-"), mutated);
    try {
      await assertSucceeds(setDoc(doc(env2.authenticatedContext(ALICE).firestore(), `users/${ALICE}/${n}/x`), { x: 1 }));
    } finally {
      await env2.cleanup();
    }
  });
});
