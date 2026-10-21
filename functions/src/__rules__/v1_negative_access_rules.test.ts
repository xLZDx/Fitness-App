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
 * The lists are parsed out of firestore.rules at run time so the suite notices
 * names the rules add, but the parser is NOT the authority: a hard-coded
 * mandatory inventory (ten server-only-write collections, five of them
 * owner-read-denied) carries unconditional assertions, so a more permissive
 * rule fails a test instead of removing one.
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
import {
  collection,
  collectionGroup,
  doc,
  getDoc,
  getDocs,
  setDoc,
  deleteDoc,
  updateDoc,
} from "firebase/firestore";

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
// EXPECTED POLICY (hard-coded, independent of the parser).
//
// The parser above only OBSERVES the rules. The lists below are the policy the
// product relies on; a rule change that makes a mandatory collection more
// permissive must FAIL an assertion here, never silently drop one. The parser
// may add extra names on top, it is not the authority.
// Verified against firestore.rules on 2026-10-21 (see the change record).
// ---------------------------------------------------------------------------

/** Server-only-write: no client (owner included) may create/update/delete. */
const MANDATORY_SERVER_WRITE_ONLY = [
  "subscription",
  "usage",
  "receipts",
  "recognised_models",
  "equipment_identity_sessions",
  "equipment_identity_latest_session",
  "equipment_identity_telemetry",
  "activity_streams",
  "activity_settings",
  "activity_tombstones",
];

/** Of those, the ones whose OWNER READ is denied today. */
const MANDATORY_OWNER_READ_DENIED = [
  "usage",
  "receipts",
  "equipment_identity_sessions",
  "equipment_identity_latest_session",
  "equipment_identity_telemetry",
];

/** Of those, the ones the owner may still READ today (never write). */
const MANDATORY_OWNER_READ_ALLOWED = MANDATORY_SERVER_WRITE_ONLY.filter(
  (n) => !MANDATORY_OWNER_READ_DENIED.includes(n),
);

/** Mandatory names plus whatever else the parser classifies as server-only. */
const WRITE_DENIED_NAMES = [...new Set([...MANDATORY_SERVER_WRITE_ONLY, ...SERVER_ONLY_WRITE])];
const READ_DENIED_NAMES = [...new Set([...MANDATORY_OWNER_READ_DENIED, ...SERVER_ONLY_READ])];

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

/** Seed users/OWNER/<name>/seed/sub/n1 (a document two levels under the collection). */
async function seedNested(name: string): Promise<void> {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `users/${OWNER}/${name}/seed/sub/n1`), SEED);
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

  test("the mandatory inventory has exactly the ten expected names", () => {
    expect(MANDATORY_SERVER_WRITE_ONLY).toHaveLength(10);
    expect(new Set(MANDATORY_SERVER_WRITE_ONLY).size).toBe(10);
  });

  test.each(MANDATORY_SERVER_WRITE_ONLY.map((n) => [n]))(
    "%s: is on the wildcard WRITE exclusion list and classified server-only",
    (name) => {
      expect(WRITE_EXCLUDED).toContain(name);
      expect(SERVER_ONLY_WRITE).toContain(name);
    },
  );

  test.each(MANDATORY_OWNER_READ_DENIED.map((n) => [n]))(
    "%s: is on the wildcard READ exclusion list and its block denies read",
    (name) => {
      expect(READ_EXCLUDED).toContain(name);
      expect(SERVER_ONLY_READ).toContain(name);
    },
  );

  test("owner-readable mandatory names are NOT on the read exclusion list or have an owner-read grant", () => {
    // subscription is read through the wildcard; the rest through a dedicated
    // owner-read block. Either way the observed classification is "not read
    // denied"; the behavior itself is asserted in (a).
    for (const n of MANDATORY_OWNER_READ_ALLOWED) expect(SERVER_ONLY_READ).not.toContain(n);
  });
});

// ---------------------------------------------------------------------------
// (a) Owner cannot write a server-only collection.
// ---------------------------------------------------------------------------

describe("(a) owner client cannot write server-only collections", () => {
  test.each(WRITE_DENIED_NAMES.map((n) => [n]))("%s: create, update, delete denied", async (name) => {
    await seed(name);
    const db = asOwner();
    await assertFails(setDoc(doc(db, `users/${OWNER}/${name}/new-doc`), { x: 1 }));
    await assertFails(setDoc(doc(db, `users/${OWNER}/${name}/seed`), { x: 2 }));
    await assertFails(updateDoc(doc(db, `users/${OWNER}/${name}/seed`), { x: 3 }));
    await assertFails(deleteDoc(doc(db, `users/${OWNER}/${name}/seed`)));
    // Nested document path under the collection must not slip through either.
    await assertFails(setDoc(doc(db, `users/${OWNER}/${name}/seed/nested/n1`), { x: 4 }));
  });

  test.each(READ_DENIED_NAMES.map((n) => [n]))(
    "%s: owner get, list and nested read denied",
    async (name) => {
      await seed(name);
      await seedNested(name);
      const db = asOwner();
      await assertFails(getDoc(doc(db, `users/${OWNER}/${name}/seed`)));
      await assertFails(getDocs(collection(db, `users/${OWNER}/${name}`)));
      await assertFails(getDoc(doc(db, `users/${OWNER}/${name}/seed/sub/n1`)));
      await assertFails(getDocs(collection(db, `users/${OWNER}/${name}/seed/sub`)));
    },
  );

  test.each(MANDATORY_OWNER_READ_ALLOWED.map((n) => [n]))(
    "%s: owner may still READ it (get and list), never write it",
    async (name) => {
      await seed(name);
      const db = asOwner();
      await assertSucceeds(getDoc(doc(db, `users/${OWNER}/${name}/seed`)));
      await assertSucceeds(getDocs(collection(db, `users/${OWNER}/${name}`)));
      await assertFails(setDoc(doc(db, `users/${OWNER}/${name}/seed`), { tier: "pro" }));
    },
  );

  test("collection-group query over a server-only name is denied to the owner", async () => {
    for (const name of MANDATORY_SERVER_WRITE_ONLY) {
      await seed(name);
      await assertFails(getDocs(collectionGroup(asOwner(), name)));
    }
  });
});

// ---------------------------------------------------------------------------
// (b) Another user and a signed-out client are closed out of EVERY listed path.
// ---------------------------------------------------------------------------

describe("(b) other user and signed-out client are denied on every excluded path", () => {
  // Mandatory names are always included, whatever the parser discovers. The
  // conditional-write collections (profile, body_scans, weight_entries, ...)
  // come from the parser and are covered here for foreign/signed-out access.
  const ALL = [...new Set([...MANDATORY_SERVER_WRITE_ONLY, ...WRITE_EXCLUDED, ...READ_EXCLUDED])];

  test.each(ALL.map((n) => [n]))("%s: other user and signed-out client denied collection list", async (name) => {
    await seed(name);
    for (const db of [asOther(), signedOut()]) {
      await assertFails(getDocs(collection(db, `users/${OWNER}/${name}`)));
    }
  });

  test.each(ALL.map((n) => [n]))(
    "%s: other user and signed-out client denied on a nested path (get, list, create, overwrite, update, delete)",
    async (name) => {
      await seed(name);
      await seedNested(name);
      for (const db of [asOther(), signedOut()]) {
        const ref = doc(db, `users/${OWNER}/${name}/seed/sub/n1`);
        await assertFails(getDoc(ref));
        await assertFails(getDocs(collection(db, `users/${OWNER}/${name}/seed/sub`)));
        await assertFails(setDoc(doc(db, `users/${OWNER}/${name}/seed/sub/fresh`), { x: 1 }));
        await assertFails(setDoc(ref, { x: 2 }));
        await assertFails(updateDoc(ref, { x: 3 }));
        await assertFails(deleteDoc(ref));
      }
    },
  );

  test.each(ALL.map((n) => [n]))(
    "%s: OWNER client cannot write a nested path under an excluded collection",
    async (name) => {
      await seedNested(name);
      const db = asOwner();
      const ref = doc(db, `users/${OWNER}/${name}/seed/sub/n1`);
      await assertFails(setDoc(doc(db, `users/${OWNER}/${name}/seed/sub/fresh`), { x: 1 }));
      await assertFails(setDoc(ref, { x: 2 }));
      await assertFails(updateDoc(ref, { x: 3 }));
      await assertFails(deleteDoc(ref));
    },
  );

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
