/**
 * S02 test epic 5 -- seam test R25 (serializer output versus rules) and R22
 * (debug_sessions, kept apart from the permanent floor).
 *
 * R25: `fixtures/s02_summaries_100.json` is produced by Dart (epic 1, U30) from
 * 100 synthetic sessions. Every entry must be accepted by the emulator after the
 * same string-to-timestamp conversion the Dart writer performs; one mutated copy
 * per key class must be refused, each followed by the unmutated control at the
 * same id (so the refusal comes from the mutation).
 */
import { assertFails, assertSucceeds, RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { deleteDoc, doc, getDoc, setDoc, updateDoc } from "firebase/firestore";
import { readFileSync } from "fs";
import { resolve } from "path";
import { ALICE, ALLOWLIST, BOB, GoldenEntry, activityPath, loadGolden, makeEnv, toWireSummary } from "./s02_rules_support";

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await makeEnv("demo-s02-golden");
});
afterAll(async () => env?.cleanup());
beforeEach(async () => env.clearFirestore());

const asAlice = () => env.authenticatedContext(ALICE).firestore();
const adminExists = async (path: string): Promise<boolean> => {
  let out = false;
  await env.withSecurityRulesDisabled(async (ctx) => {
    out = (await getDoc(doc(ctx.firestore(), path))).exists();
  });
  return out;
};

const golden = loadGolden();

describe("R25 fixture sanity (the oracle is what the plan says it is)", () => {
  test("100 distinct valid ids, rev 1, only allowlisted keys, ISO strings for timestamps", () => {
    expect(golden).toHaveLength(100);
    expect(new Set(golden.map((g) => g.id)).size).toBe(100);
    for (const g of golden) {
      expect(g.id).toMatch(/^act_[0-9a-f]{40}$/);
      expect(g.summary.rev).toBe(1);
      for (const k of Object.keys(g.summary)) expect(ALLOWLIST).toContain(k);
      expect(typeof g.summary.startUtc).toBe("string");
      expect(typeof g.summary.endUtc).toBe("string");
    }
  });
});

describe("R25 every golden summary is accepted by the emulator", () => {
  test("all 100 creates succeed and read back with the converted timestamps", async () => {
    for (const g of golden) {
      await assertSucceeds(setDoc(doc(asAlice(), activityPath(ALICE, g.id)), toWireSummary(g.summary)));
    }
    let count = 0;
    await env.withSecurityRulesDisabled(async (ctx) => {
      for (const g of golden) {
        const snap = await getDoc(doc(ctx.firestore(), activityPath(ALICE, g.id)));
        expect(snap.exists()).toBe(true);
        expect(snap.data()?.startUtc.toDate().toISOString()).toBe(new Date(g.summary.startUtc as string).toISOString());
        count++;
      }
    });
    expect(count).toBe(100);
  }, 120000);

  test("the unconverted fixture (ISO strings, as raw JSON) is REFUSED: the conversion is part of the contract", async () => {
    const g = golden[0];
    await assertFails(setDoc(doc(asAlice(), activityPath(ALICE, g.id)), g.summary));
    await assertSucceeds(setDoc(doc(asAlice(), activityPath(ALICE, g.id)), toWireSummary(g.summary)));
  });
});

describe("R25 one mutated copy per key class is refused", () => {
  const byKeyCount = [...golden].sort((a, b) => Object.keys(a.summary).length - Object.keys(b.summary).length);
  const samples: GoldenEntry[] = [byKeyCount[0], byKeyCount[Math.floor(byKeyCount.length / 2)], byKeyCount[byKeyCount.length - 1]];

  const MUTATIONS: Array<[string, (s: Record<string, unknown>) => Record<string, unknown>]> = [
    ["geometry key", (s) => ({ ...s, polyline: "abc" })],
    ["place key", (s) => ({ ...s, placeName: "Home" })],
    ["heart-rate key", (s) => ({ ...s, avgHrBpm: 150 })],
    ["list value", (s) => ({ ...s, distanceM: [1, 2] })],
    ["map value (extras)", (s) => ({ ...s, extras: { a: 1 } })],
    ["wrong type", (s) => ({ ...s, distanceM: "100" })],
    ["out of range", (s) => ({ ...s, distanceM: 10000001 })],
    ["unknown key", (s) => ({ ...s, brandNewKey: 1 })],
    ["missing required key", (s) => { const { endUtc: _e, ...rest } = s; return rest; }],
    ["rev other than 1 on create", (s) => ({ ...s, rev: 2 })],
    ["bad sport", (s) => ({ ...s, sport: "Run Fast" })],
  ];

  test("the samples cover a minimal, a median and the largest golden summary", () => {
    expect(Object.keys(samples[0].summary).length).toBeLessThan(Object.keys(samples[2].summary).length);
  });

  test.each(MUTATIONS.map((m) => [m[0]] as const))("%s", async (cls) => {
    const mutate = MUTATIONS.find((m) => m[0] === cls)![1];
    for (const g of samples) {
      const ref = doc(asAlice(), activityPath(ALICE, g.id));
      const wire = toWireSummary(g.summary);
      await assertFails(setDoc(ref, mutate(wire)));
      expect(await adminExists(activityPath(ALICE, g.id))).toBe(false);
      await assertSucceeds(setDoc(ref, wire)); // control at the same id
    }
  });

  test("a bad id (uppercase hex) is refused while the same body under the real id is accepted", async () => {
    const g = samples[1];
    const badId = "act_" + g.id.slice(4).toUpperCase();
    await assertFails(setDoc(doc(asAlice(), activityPath(ALICE, badId)), toWireSummary(g.summary)));
    await assertSucceeds(setDoc(doc(asAlice(), activityPath(ALICE, g.id)), toWireSummary(g.summary)));
  });
});

// ---------------------------------------------------------------------------
// R22: debug_sessions. Separate from the permanent floor (design 8.1, 12.1):
// reverting `create: false` can fail only this block.
// ---------------------------------------------------------------------------
describe("R22 debug_sessions: client create is denied (S02-09)", () => {
  const oldValid = (uid: string) => ({ identity: { sha: "abc123" }, droppedCount: 0, events: [{ m: "hi" }], uid });
  const asBob = () => env.authenticatedContext(BOB).firestore();

  test("the old valid-shape, self-stamped document can no longer be created", async () => {
    await assertFails(setDoc(doc(asAlice(), "debug_sessions/s1"), oldValid(ALICE)));
    expect(await adminExists("debug_sessions/s1")).toBe(false);
    // Control: the Admin path (the sanitising callable) still writes it, and the document is stored.
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "debug_sessions/s1"), oldValid(ALICE));
    });
    expect(await adminExists("debug_sessions/s1")).toBe(true);
  });

  test("a wrong-uid, an empty-events and a signed-out create are denied as well", async () => {
    await assertFails(setDoc(doc(asBob(), "debug_sessions/s2"), oldValid(ALICE)));
    await assertFails(setDoc(doc(asAlice(), "debug_sessions/s3"), { ...oldValid(ALICE), events: [] }));
    await assertFails(setDoc(doc(env.unauthenticatedContext().firestore(), "debug_sessions/s4"), oldValid(ALICE)));
  });

  test("read, update and delete stay denied for the author", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "debug_sessions/s5"), oldValid(ALICE));
    });
    await assertFails(getDoc(doc(asAlice(), "debug_sessions/s5")));
    await assertFails(updateDoc(doc(asAlice(), "debug_sessions/s5"), { droppedCount: 9 }));
    await assertFails(deleteDoc(doc(asAlice(), "debug_sessions/s5")));
    expect(await adminExists("debug_sessions/s5")).toBe(true);
  });

  test("the rule text says create: false (the single separately revertible line)", () => {
    const rules = readFileSync(resolve(__dirname, "../../../firestore.rules"), "utf8");
    const start = rules.indexOf("match /debug_sessions/{sessionId}");
    const block = rules.slice(start, rules.indexOf("match /coach_bookings", start));
    expect(start).toBeGreaterThan(0);
    expect(block).toMatch(/allow create: if false;/);
  });
});
