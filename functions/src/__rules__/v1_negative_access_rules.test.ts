/**
 * V1 negative-access tests for the owner wildcard in firestore.rules.
 *
 *   match /users/{uid}/{coll}/{document=**}
 *
 * The wildcard excludes protected sub-collections one by one with
 * `coll != '...'` lists in its read rule and its write rule. A list of names
 * does not stop a client from touching a sub-collection that is not on it, so
 * this file (a) proves the listed server-only collections really are closed,
 * (b) proves other users and signed-out clients are closed out of EVERY listed
 * path, and (c)/(d) records the CURRENT behavior for unlisted names as a known
 * gap, so nobody mistakes the allow-list for a deny-list.
 *
 * The lists are parsed out of firestore.rules at run time, never copied here,
 * so this suite fails when the rules and the test drift apart.
 *
 * Project id is its own ("demo-fitness-negative-access") so seeded data never
 * leaks into the other rules suites sharing the emulator.
 */
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { readFileSync } from "fs";
import { resolve } from "path";
import { doc, getDoc, setDoc, deleteDoc, updateDoc } from "firebase/firestore";

const RULES_PATH = resolve(__dirname, "../../../firestore.rules");
const RULES = readFileSync(RULES_PATH, "utf8");

const OWNER = "owner-uid";
const OTHER = "other-uid";

// ---------------------------------------------------------------------------
// Parsing firestore.rules (kept deliberately small and strict).
// ---------------------------------------------------------------------------

/** Body of the `allow <verbs>: if ...;` statement of the wildcard, by verb. */
function wildcardRuleText(verb: "read" | "write"): string {
  const start = RULES.indexOf("match /users/{uid}/{coll}/{document=**} {");
  if (start < 0) throw new Error("owner wildcard match block not found in firestore.rules");
  const end = RULES.indexOf("\n    }", start);
  const block = RULES.slice(start, end);
  const m = new RegExp(`allow ${verb}:([\\s\\S]*?);`).exec(block);
  if (!m) throw new Error(`wildcard 'allow ${verb}' not found`);
  return m[1];
}

function excludedNames(verb: "read" | "write"): string[] {
  const names = [...wildcardRuleText(verb).matchAll(/coll != '([^']+)'/g)].map((m) => m[1]);
  return [...new Set(names)];
}

const READ_EXCLUDED = excludedNames("read");
const WRITE_EXCLUDED = excludedNames("write");

/** Text of the dedicated `match /users/{uid}/<name>/{...} { ... }` block, or null. */
function dedicatedBlock(name: string): string | null {
  const re = new RegExp(`match /users/\\{uid\\}/${name}/\\{[^}]+\\} \\{`);
  const m = re.exec(RULES);
  if (!m) return null;
  const end = RULES.indexOf("\n    }", m.index);
  return RULES.slice(m.index, end);
}

/**
 * True when the collection's dedicated block (or the absence of one, which
 * leaves no grant at all once the wildcard excludes it) denies every client
 * write: each `allow` statement naming a write verb has the condition `false`.
 */
function writeIsServerOnly(name: string): boolean {
  const block = dedicatedBlock(name);
  if (block === null) return true; // excluded from wildcard and no own grant
  const stmts = [...block.matchAll(/allow ([a-z, ]+):\s*if ([^;]+);/g)];
  const writeStmts = stmts.filter((s) =>
    /write|create|update|delete/.test(s[1]),
  );
  return writeStmts.every((s) => s[2].trim() === "false");
}

/** True when the collection's dedicated block denies every client read. */
function readIsServerOnly(name: string): boolean {
  if (!READ_EXCLUDED.includes(name)) return false; // wildcard grants owner read
  const block = dedicatedBlock(name);
  if (block === null) return true;
  const stmts = [...block.matchAll(/allow ([a-z, ]+):\s*if ([^;]+);/g)];
  const readStmts = stmts.filter((s) => /read|get|list/.test(s[1]));
  return readStmts.every((s) => s[2].trim() === "false");
}

const SERVER_ONLY_WRITE = WRITE_EXCLUDED.filter(writeIsServerOnly);
const SERVER_ONLY_READ = WRITE_EXCLUDED.filter(readIsServerOnly);

// ---------------------------------------------------------------------------
// Emulator plumbing
// ---------------------------------------------------------------------------

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-fitness-negative-access",
    firestore: {
      rules: RULES,
      host: "127.0.0.1",
      port: Number(process.env.FIRESTORE_EMULATOR_PORT ?? 8080),
    },
  });
});
afterAll(async () => env?.cleanup());
beforeEach(async () => env.clearFirestore());

const asOwner = () => env.authenticatedContext(OWNER).firestore();
const asOther = () => env.authenticatedContext(OTHER).firestore();
const signedOut = () => env.unauthenticatedContext().firestore();

const SEED = { seeded: true };

async function seed(name: string, id = "seed"): Promise<void> {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `users/${OWNER}/${name}/${id}`), SEED);
  });
}

// ---------------------------------------------------------------------------
// Drift guards: the parsed lists must still contain what the product relies on.
// ---------------------------------------------------------------------------

describe("parsed exclusion lists (drift guard)", () => {
  test("write list parses and is non-trivial", () => {
    expect(WRITE_EXCLUDED.length).toBeGreaterThanOrEqual(10);
  });

  test("every read-excluded name is also write-excluded", () => {
    for (const n of READ_EXCLUDED) expect(WRITE_EXCLUDED).toContain(n);
  });

  test("the known server-only collections are still classified server-only", () => {
    for (const n of [
      "subscription",
      "usage",
      "receipts",
      "recognised_models",
      "equipment_identity_sessions",
      "equipment_identity_latest_session",
      "equipment_identity_telemetry",
    ]) {
      expect(SERVER_ONLY_WRITE).toContain(n);
    }
  });
});

// ---------------------------------------------------------------------------
// (a) Owner cannot write a server-only collection.
// ---------------------------------------------------------------------------

describe("(a) owner client cannot write server-only collections", () => {
  test.each(SERVER_ONLY_WRITE.map((n) => [n]))("%s: create, update, delete denied", async (name) => {
    await seed(name);
    const db = asOwner();
    await assertFails(setDoc(doc(db, `users/${OWNER}/${name}/new-doc`), { x: 1 }));
    await assertFails(setDoc(doc(db, `users/${OWNER}/${name}/seed`), { x: 2 }));
    await assertFails(updateDoc(doc(db, `users/${OWNER}/${name}/seed`), { x: 3 }));
    await assertFails(deleteDoc(doc(db, `users/${OWNER}/${name}/seed`)));
    // Nested document path under the collection must not slip through either.
    await assertFails(setDoc(doc(db, `users/${OWNER}/${name}/seed/nested/n1`), { x: 4 }));
  });

  test.each(SERVER_ONLY_READ.map((n) => [n]))("%s: owner read denied", async (name) => {
    await seed(name);
    await assertFails(getDoc(doc(asOwner(), `users/${OWNER}/${name}/seed`)));
  });

  test("subscription: owner may still READ it (documented), never write it", async () => {
    expect(READ_EXCLUDED).not.toContain("subscription");
    await seed("subscription", "main");
    await assertSucceeds(getDoc(doc(asOwner(), `users/${OWNER}/subscription/main`)));
    await assertFails(setDoc(doc(asOwner(), `users/${OWNER}/subscription/main`), { tier: "pro" }));
  });
});

// ---------------------------------------------------------------------------
// (b) Another user and a signed-out client are closed out of EVERY listed path.
// ---------------------------------------------------------------------------

describe("(b) other user and signed-out client are denied on every excluded path", () => {
  const ALL = [...new Set([...WRITE_EXCLUDED, ...READ_EXCLUDED])];

  test.each(ALL.map((n) => [n]))("%s: other authenticated user denied read/create/update/delete", async (name) => {
    await seed(name);
    const db = asOther();
    const ref = doc(db, `users/${OWNER}/${name}/seed`);
    await assertFails(getDoc(ref));
    await assertFails(setDoc(doc(db, `users/${OWNER}/${name}/new-doc`), { x: 1 }));
    await assertFails(setDoc(ref, { x: 2 }));
    await assertFails(updateDoc(ref, { x: 3 }));
    await assertFails(deleteDoc(ref));
  });

  test.each(ALL.map((n) => [n]))("%s: unauthenticated client denied read/create/update/delete", async (name) => {
    await seed(name);
    const db = signedOut();
    const ref = doc(db, `users/${OWNER}/${name}/seed`);
    await assertFails(getDoc(ref));
    await assertFails(setDoc(doc(db, `users/${OWNER}/${name}/new-doc`), { x: 1 }));
    await assertFails(setDoc(ref, { x: 2 }));
    await assertFails(updateDoc(ref, { x: 3 }));
    await assertFails(deleteDoc(ref));
  });
});

// ---------------------------------------------------------------------------
// (c) workout_command_policy/current -- documented server-only account policy.
// ---------------------------------------------------------------------------

describe("(c) users/{uid}/workout_command_policy/current", () => {
  const NAME = "workout_command_policy";
  const mentioned = RULES.includes(NAME);
  const path = `users/${OWNER}/${NAME}/current`;

  if (mentioned) {
    // Once a rule names it, it must be closed to every client operation.
    test("owner client cannot create, update or delete it", async () => {
      await seed(NAME, "current");
      const db = asOwner();
      await assertFails(setDoc(doc(db, `users/${OWNER}/${NAME}/fresh`), { x: 1 }));
      await assertFails(setDoc(doc(db, path), { x: 2 }));
      await assertFails(updateDoc(doc(db, path), { x: 3 }));
      await assertFails(deleteDoc(doc(db, path)));
    });
  } else {
    // FINDING: firestore.rules does not mention the path at all, so it falls
    // into the owner wildcard. This test pins the CURRENT behavior and flips
    // (deliberately fails) the day someone adds a rule, at which point the
    // branch above takes over.
    test("documents: workout_command_policy/current is NOT protected (owner client can write it; rules do not mention it)", async () => {
      const db = asOwner();
      await assertSucceeds(setDoc(doc(db, path), { x: 1 }));
      await assertSucceeds(updateDoc(doc(db, path), { x: 2 }));
      await assertSucceeds(deleteDoc(doc(db, path)));
    });
  }

  test("other user and signed-out client cannot touch it regardless", async () => {
    await seed(NAME, "current");
    for (const db of [asOther(), signedOut()]) {
      const ref = doc(db, path);
      await assertFails(getDoc(ref));
      await assertFails(setDoc(ref, { x: 1 }));
      await assertFails(updateDoc(ref, { x: 2 }));
      await assertFails(deleteDoc(ref));
    }
  });
});

// ---------------------------------------------------------------------------
// (d) Allow-list gap: an unlisted sub-collection is owner-writable today.
// ---------------------------------------------------------------------------

describe("(d) allow-list gap for unlisted sub-collections", () => {
  const UNLISTED = "brand_new_unlisted_collection";

  test("precondition: the probe name is not on either exclusion list", () => {
    expect(READ_EXCLUDED).not.toContain(UNLISTED);
    expect(WRITE_EXCLUDED).not.toContain(UNLISTED);
    expect(dedicatedBlock(UNLISTED)).toBeNull();
  });

  test("documents: unlisted owner sub-collection is writable (allow-list gap)", async () => {
    const db = asOwner();
    const ref = doc(db, `users/${OWNER}/${UNLISTED}/d1`);
    await assertSucceeds(setDoc(ref, { x: 1 }));
    await assertSucceeds(getDoc(ref));
    await assertSucceeds(updateDoc(ref, { x: 2 }));
    await assertSucceeds(deleteDoc(ref));
  });

  test("the gap is owner-only: another user and a signed-out client are still denied", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `users/${OWNER}/${UNLISTED}/d1`), SEED);
    });
    for (const db of [asOther(), signedOut()]) {
      const ref = doc(db, `users/${OWNER}/${UNLISTED}/d1`);
      await assertFails(getDoc(ref));
      await assertFails(setDoc(ref, { x: 1 }));
      await assertFails(deleteDoc(ref));
    }
  });
});
