/**
 * S02 test epic 5 -- shape, bounds and update rules of the activity SUMMARY
 * block `users/{uid}/activities/{activityId}` against the real Firestore
 * emulator. Plan ids: R01, R04-R14, R19, R20, R21, R28, R29.
 *
 * Oracle: the literal key allowlist and numeric bounds of S02_DESIGN.md 3.2
 * (see `s02_rules_support.ts`), never values read from `firestore.rules`.
 *
 * Reading the plan: the "Fails if" column of the test plan describes what
 * would make the test FAIL. A row such as "R11 `endUtc == startUtc` denied"
 * therefore means the equal case must be ALLOWED. Every denial below is paired
 * with an accepted control write at the same id (a broken emulator or a body
 * error cannot fake a pass).
 *
 * Own emulator project id so this file can run in parallel with the others.
 */
import { assertFails, assertSucceeds, RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { deleteDoc, doc, getDoc, serverTimestamp, setDoc, updateDoc } from "firebase/firestore";
import {
  ALICE,
  ALLOWLIST,
  BOUNDS,
  END,
  REQUIRED_KEYS,
  START,
  SOURCE_KINDS,
  activityPath,
  actId,
  estimateDocBytes,
  fullSummary,
  makeEnv,
  minimalSummary,
  summary,
  ts,
  without,
} from "./s02_rules_support";

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await makeEnv("demo-s02-summary");
});
afterAll(async () => env?.cleanup());
beforeEach(async () => env.clearFirestore());

const asAlice = () => env.authenticatedContext(ALICE).firestore();
const ref = (id: string) => doc(asAlice(), activityPath(ALICE, id));

const create = (id: string, data: Record<string, unknown>) => setDoc(ref(id), data);

const seed = (id: string, data: Record<string, unknown>) =>
  env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), activityPath(ALICE, id)), data);
  });

const adminRead = async (id: string): Promise<Record<string, any> | null> => {
  let out: Record<string, any> | null = null;
  await env.withSecurityRulesDisabled(async (ctx) => {
    const snap = await getDoc(doc(ctx.firestore(), activityPath(ALICE, id)));
    out = snap.exists() ? (snap.data() as Record<string, any>) : null;
  });
  return out;
};

/** A refused write followed by an accepted control at the SAME id. */
async function deniedThenControl(id: string, bad: Record<string, unknown>, good: Record<string, unknown>) {
  await assertFails(create(id, bad));
  expect(await adminRead(id)).toBeNull(); // the refusal left nothing behind
  await assertSucceeds(create(id, good));
}

describe("R01 allowlisted-only create succeeds", () => {
  test("a minimal document (the five required keys) is accepted", async () => {
    await assertSucceeds(create(actId(1), minimalSummary()));
    expect((await adminRead(actId(1)))?.rev).toBe(1);
  });

  test("a full document with every allowlisted key is accepted", async () => {
    const full = fullSummary();
    expect(Object.keys(full).sort()).toEqual([...ALLOWLIST].sort()); // the fixture really carries all 32 keys
    await assertSucceeds(create(actId(2), full));
  });

  test("a document with one extra non-allowlisted key is refused, the same body without it is accepted", async () => {
    await deniedThenControl(actId(3), summary({ unknownKey: 1 }), summary());
  });
});

describe("R04 geometry and place keys are refused at create and at update", () => {
  const GEOMETRY: Array<[string, unknown]> = [
    ["polyline", "encodedPolyline"],
    ["points", [1, 2]],
    ["bbox", { n: 1, s: 0 }],
    ["startLat", 52.1],
    ["startLon", 4.3],
    ["lats", [52.1]],
    ["lons", [4.3]],
    ["route", "gpx"],
    ["geohash", "u173zq"],
    ["placeName", "Home"],
  ];

  test.each(GEOMETRY)("create with %s is refused, the same body without it is accepted", async (key, value) => {
    await deniedThenControl(actId(10), summary({ [key]: value }), summary());
  });

  test.each(GEOMETRY)("update adding %s is refused, a valid update succeeds", async (key, value) => {
    await seed(actId(11), summary());
    await assertFails(updateDoc(ref(actId(11)), { [key]: value, rev: 2 }));
    expect((await adminRead(actId(11)))?.rev).toBe(1);
    await assertSucceeds(updateDoc(ref(actId(11)), { rev: 2, distanceM: 10100 }));
  });
});

describe("R05 heart-rate keys are refused", () => {
  test.each(["avgHrBpm", "maxHrBpm", "heartRate", "hr"])("%s is refused at create", async (key) => {
    await deniedThenControl(actId(20), summary({ [key]: 150 }), summary());
  });
});

describe("R06 list and map values are refused", () => {
  test("a list value for a numeric key is refused", async () => {
    await deniedThenControl(actId(30), summary({ distanceM: [1, 2] }), summary({ distanceM: 1 }));
  });

  test("a map value for a string key is refused", async () => {
    await deniedThenControl(actId(31), summary({ sport: {} }), summary({ sport: "cycling" }));
  });

  test.each([
    ["laps", [{ n: 1 }]],
    ["provenance", [{ source: "x" }]],
    ["extras", { k: "v" }],
    ["laps", []],
    ["extras", {}],
  ] as Array<[string, unknown]>)("key %s with a list or map is refused", async (key, value) => {
    await deniedThenControl(actId(32), summary({ [key]: value }), summary());
  });
});

describe("R07 wrong types are refused", () => {
  test.each([
    ["sport as number", { sport: 5 }, { sport: "swimming" }],
    ["startUtc as string", { startUtc: "2026-03-01T10:00:00Z" }, { startUtc: ts("2026-03-01T10:00:00Z") }],
    ["endUtc as string", { endUtc: "2026-03-01T11:00:00Z" }, { endUtc: ts("2026-03-01T11:00:00Z") }],
    ["schema as float", { schema: 1.5 }, { schema: 2 }],
    ["distanceM as string", { distanceM: "100" }, { distanceM: 100 }],
    ["hasRoute as string", { hasRoute: "true" }, { hasRoute: true }],
    ["utcOffsetMinutes as float", { utcOffsetMinutes: 60.5 }, { utcOffsetMinutes: 60 }],
    ["sourceCount as float", { sourceCount: 1.5 }, { sourceCount: 2 }],
    ["rev as string", { rev: "1" }, { rev: 1 }],
    ["rev as float", { rev: 1.5 }, { rev: 1 }],
    ["updatedAt as number", { updatedAt: 1700000000 }, { updatedAt: ts("2026-03-01T11:00:00Z") }],
    ["primarySourceId as number", { primarySourceId: 7 }, { primarySourceId: "7" }],
  ] as Array<[string, Record<string, unknown>, Record<string, unknown>]>)("%s", async (_label, bad, good) => {
    await deniedThenControl(actId(40), summary(bad), summary(good));
  });
});

describe("R08 numeric bounds (off-by-one detection)", () => {
  test.each(BOUNDS.map((b) => [b.key, b] as const))("%s", async (_key, b) => {
    // Accepted at both inclusive ends.
    await assertSucceeds(create(actId(100), summary({ [b.key]: b.min })));
    await assertSucceeds(create(actId(101), summary({ [b.key]: b.max })));
    // Refused one unit outside.
    await assertFails(create(actId(102), summary({ [b.key]: b.min - 1 })));
    await assertFails(create(actId(103), summary({ [b.key]: b.max + 1 })));
    expect(await adminRead(actId(102))).toBeNull();
    expect(await adminRead(actId(103))).toBeNull();
    if (b.int) {
      // An int key refuses a fractional value inside the range.
      await assertFails(create(actId(104), summary({ [b.key]: b.max - 0.5 })));
    } else {
      // A number key refuses a fraction outside the range (a `<` slipped in for `<=` would show here).
      await assertFails(create(actId(105), summary({ [b.key]: b.max + 0.001 })));
      await assertFails(create(actId(106), summary({ [b.key]: b.min - 0.001 })));
      // ... and accepts a fraction inside it.
      await assertSucceeds(create(actId(107), summary({ [b.key]: b.max - 0.001 })));
    }
  });

  test("negative movingTimeS and utcOffsetMinutes 841 are refused", async () => {
    await assertFails(create(actId(110), summary({ movingTimeS: -1 })));
    await assertFails(create(actId(111), summary({ utcOffsetMinutes: 841 })));
    await assertFails(create(actId(112), summary({ utcOffsetMinutes: -841 })));
    await assertSucceeds(create(actId(113), summary({ movingTimeS: 0, utcOffsetMinutes: -840 })));
  });

  test("NaN and infinities are refused for a measure", async () => {
    for (const bad of [Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY]) {
      await assertFails(create(actId(114), summary({ distanceM: bad })));
    }
    await assertSucceeds(create(actId(114), summary({ distanceM: 5 })));
  });

  test("rev bounds on update: 1000000 accepted, 1000001 and 0 refused", async () => {
    await seed(actId(115), summary({ rev: 5 }));
    await assertFails(updateDoc(ref(actId(115)), { rev: 1000001 }));
    await assertFails(updateDoc(ref(actId(115)), { rev: 0 }));
    await assertSucceeds(updateDoc(ref(actId(115)), { rev: 1000000 }));
    expect((await adminRead(actId(115)))?.rev).toBe(1000000);
  });
});

describe("R09 id pattern act_ + 40 lowercase hex", () => {
  const hex40 = "0123456789abcdef0123456789abcdef01234567";
  test.each([
    ["foo", "foo"],
    ["39 hex digits", "act_" + hex40.slice(0, 39)],
    ["41 hex digits", "act_" + hex40 + "8"],
    ["uppercase hex", "act_" + hex40.toUpperCase()],
    ["non-hex letters", "act_" + "g".repeat(40)],
    ["missing prefix", hex40],
  ])("id %s is refused", async (_label, badId) => {
    await assertFails(create(badId, summary()));
    await assertSucceeds(create("act_" + hex40, summary())); // the exact pattern is accepted
  });
});

describe("R10 open sport pattern ^[a-z][A-Za-z0-9]{0,31}$", () => {
  test.each([
    ["Run"],
    ["5k"],
    ["run_fast"],
    ["run-fast"],
    [""],
    ["a" + "b".repeat(32)], // 33 characters
  ])("sport %j is refused", async (sport) => {
    await deniedThenControl(actId(200), summary({ sport }), summary());
  });

  test.each([["r"], ["running"], ["newSport7"], ["a" + "b".repeat(31)]])("sport %j is accepted (a future sport must never break a write)", async (sport) => {
    await assertSucceeds(create(actId(201), summary({ sport })));
  });
});

describe("R11 time order", () => {
  test("endUtc before startUtc is refused", async () => {
    await deniedThenControl(
      actId(210),
      summary({ startUtc: ts("2026-03-01T10:00:00Z"), endUtc: ts("2026-03-01T09:59:59Z") }),
      summary(),
    );
  });

  test("endUtc equal to startUtc is accepted (the order is non-strict)", async () => {
    await assertSucceeds(create(actId(211), summary({ startUtc: ts(START), endUtc: ts(START) })));
  });
});

describe("R12 required keys schema, sport, startUtc, endUtc, rev", () => {
  test.each(REQUIRED_KEYS.map((k) => [k]))("a document without %s is refused", async (key) => {
    await deniedThenControl(actId(220), without(summary(), key), summary());
  });
});

describe("R13 string bounds and enums", () => {
  test.each([
    ["primarySourceId", "p".repeat(65), "p".repeat(64)],
    ["sourceTermsSnapshot", "t".repeat(65), "t".repeat(64)],
    ["formulaVersion", "f".repeat(33), "f".repeat(32)],
    ["metricDefinitionVersion", "m".repeat(33), "m".repeat(32)],
    ["thresholdPolicyVersion", "h".repeat(33), "h".repeat(32)],
    ["formulaVersion", "has space", "formula-1"],
    ["sourceTermsSnapshot", "has space", "terms-2026-10:319".replace(":", "-")],
    ["primarySourceKind", "Bluetooth", "bleSensor"],
    ["primarySourceKind", "BLESENSOR", "bleSensor"],
  ])("%s: %j is refused, %j is accepted", async (key, bad, good) => {
    await deniedThenControl(actId(230), summary({ [key]: bad }), summary({ [key]: good }));
  });

  test.each(SOURCE_KINDS.map((k) => [k]))("primarySourceKind %s is accepted", async (kind) => {
    await assertSucceeds(create(actId(231), summary({ primarySourceKind: kind })));
  });
});

describe("R14 client delete is denied", () => {
  test("the owner cannot delete an existing summary, and it survives", async () => {
    await seed(actId(240), summary());
    await assertSucceeds(getDoc(ref(actId(240)))); // control: the owner can read it
    await assertFails(deleteDoc(ref(actId(240))));
    expect(await adminRead(actId(240))).not.toBeNull();
  });

  test("delete of a document that does not exist is also refused", async () => {
    await assertFails(deleteDoc(ref(actId(241))));
  });
});

describe("R19 update via merge", () => {
  test("adding polyline to an existing valid document is refused, a plain rev bump is accepted", async () => {
    await seed(actId(250), summary());
    await assertFails(updateDoc(ref(actId(250)), { rev: 2, polyline: "x" }));
    expect(await adminRead(actId(250))).toEqual(summary());
    await assertSucceeds(updateDoc(ref(actId(250)), { rev: 2, distanceM: 12000 }));
    expect((await adminRead(actId(250)))?.distanceM).toBe(12000);
  });

  test("a merge update that sets a field out of bounds is refused", async () => {
    await seed(actId(251), summary());
    await assertFails(updateDoc(ref(actId(251)), { rev: 2, distanceM: 10000001 }));
    await assertSucceeds(updateDoc(ref(actId(251)), { rev: 2, distanceM: 10000000 }));
  });
});

describe("R20 updatedAt is a client hint", () => {
  test.each([["a string", "2026-03-01"], ["a number", 123]])("%s is refused", async (_l, bad) => {
    await deniedThenControl(actId(260), summary({ updatedAt: bad }), summary({ updatedAt: ts("2026-03-01T11:00:00Z") }));
  });

  test("an old timestamp from an offline queue is accepted (rules must not force request.time)", async () => {
    await assertSucceeds(create(actId(261), summary({ updatedAt: ts("2020-01-01T00:00:00Z") })));
    await seed(actId(262), summary({ updatedAt: ts("2020-01-01T00:00:00Z") }));
    await assertSucceeds(updateDoc(ref(actId(262)), { rev: 2, updatedAt: ts("2020-01-02T00:00:00Z") }));
  });

  test("a far-future timestamp and a server timestamp are both accepted (no ordering use of the hint)", async () => {
    await assertSucceeds(create(actId(263), summary({ updatedAt: ts("2040-01-01T00:00:00Z") })));
    await assertSucceeds(create(actId(264), summary({ updatedAt: serverTimestamp() })));
  });
});

describe("R21 document size bound (design 4: a summary stays well under 4 KiB)", () => {
  test("a document with every key at its maximum length is still under 4096 bytes", () => {
    const longest = fullSummary({
      sport: "a" + "b".repeat(31),
      primarySourceId: "p".repeat(64),
      primarySourceKind: "platformHealth", // the longest of the five names
      formulaVersion: "f".repeat(32),
      metricDefinitionVersion: "m".repeat(32),
      thresholdPolicyVersion: "h".repeat(32),
      sourceTermsSnapshot: "t".repeat(64),
    });
    const bytes = estimateDocBytes(activityPath(ALICE, actId(1)), longest);
    // Printed so the margin is visible in the run log.
    console.log(`R21 estimated maximum summary size: ${bytes} bytes (limit 4096)`);
    expect(bytes).toBeLessThan(4096);
    // The estimate must be meaningful, not trivially small: strings alone are >= 400 bytes.
    expect(bytes).toBeGreaterThan(700);
  });

  test("the maximum-length document is accepted by the emulator (the size claim is not a different document)", async () => {
    const longest = fullSummary({
      sport: "a" + "b".repeat(31),
      primarySourceId: "p".repeat(64),
      primarySourceKind: "platformHealth",
      formulaVersion: "f".repeat(32),
      metricDefinitionVersion: "m".repeat(32),
      thresholdPolicyVersion: "h".repeat(32),
      sourceTermsSnapshot: "t".repeat(64),
    });
    await assertSucceeds(create(actId(270), longest));
  });
});

describe("R28 startUtc clamp (>= 2000-01-01 inclusive, <= request.time + 1 day)", () => {
  const body = (iso: string | Date) => summary({ startUtc: ts(iso), endUtc: ts(iso) });
  const hours = (h: number) => new Date(Date.now() + h * 3600 * 1000);

  test("1999-12-31T23:59:59Z is refused, 2000-01-01T00:00:00Z is accepted (inclusive lower bound)", async () => {
    await assertFails(create(actId(280), body("1999-12-31T23:59:59.000Z")));
    await assertSucceeds(create(actId(281), body("2000-01-01T00:00:00.000Z")));
    await assertSucceeds(create(actId(282), body("2000-01-01T00:00:01.000Z")));
  });

  test("23 hours ahead is accepted, 25 hours ahead is refused (1 h margins around the 1-day bound)", async () => {
    await assertSucceeds(create(actId(283), body(hours(23))));
    await assertFails(create(actId(284), body(hours(25))));
    expect(await adminRead(actId(284))).toBeNull();
  });

  test("endUtc has no separate clamp: a far-future endUtc with a valid startUtc is accepted", async () => {
    await assertSucceeds(create(actId(285), summary({ startUtc: ts(START), endUtc: ts("2090-01-01T00:00:00Z") })));
  });

  test("the clamp is also enforced on update (a forged far-future startUtc cannot be applied)", async () => {
    // startUtc is immutable on update, so a clamp bypass on update would need a stored out-of-range date;
    // the stored one is valid, and an update that changes it is refused by the immutability rule (R29) either way.
    await seed(actId(286), summary());
    await assertFails(setDoc(ref(actId(286)), summary({ rev: 2, startUtc: ts(hours(48)), endUtc: ts(hours(49)) })));
  });

  test("the exact bound is visible in the rules source", () => {
    const rulesSource = require("fs").readFileSync(require("path").resolve(__dirname, "../../../firestore.rules"), "utf8") as string;
    expect(rulesSource).toMatch(/d\.startUtc >= timestamp\.date\(2000, 1, 1\)/);
    expect(rulesSource).toMatch(/d\.startUtc <= request\.time \+ duration\.value\(1, 'd'\)/);
    expect(rulesSource).not.toMatch(/d\.endUtc <= request\.time/); // endUtc has no separate clamp
  });
});

describe("R29 startUtc and sport are immutable after creation", () => {
  test("changing startUtc on update is refused", async () => {
    await seed(actId(290), summary());
    const moved = ts("2026-03-01T10:00:01Z");
    await assertFails(setDoc(ref(actId(290)), summary({ rev: 2, startUtc: moved, endUtc: ts(END) })));
    await assertFails(updateDoc(ref(actId(290)), { rev: 2, startUtc: moved }));
    expect(await adminRead(actId(290))).toEqual(summary());
  });

  test("changing sport on update is refused", async () => {
    await seed(actId(291), summary());
    await assertFails(setDoc(ref(actId(291)), summary({ rev: 2, sport: "cycling" })));
    await assertFails(updateDoc(ref(actId(291)), { rev: 2, sport: "cycling" }));
    expect((await adminRead(actId(291)))?.sport).toBe("running");
  });

  test("keeping both and changing distanceM is accepted (control)", async () => {
    await seed(actId(292), summary());
    await assertSucceeds(setDoc(ref(actId(292)), summary({ rev: 2, distanceM: 10500 })));
    expect((await adminRead(actId(292)))?.distanceM).toBe(10500);
  });

  test("create with any valid sport still works", async () => {
    for (const [i, sport] of ["running", "cycling", "swimming", "other", "futureSport9"].entries()) {
      await assertSucceeds(create(actId(293 + i), summary({ sport })));
    }
  });
});
