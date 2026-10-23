/**
 * Slice V0 functional tests of the one-transaction apply, against the REAL Firestore emulator
 * (Admin SDK, no mocks of firebase-admin). Spec: OFFLINE_COMMAND_PROTOCOL.md 4.2 to 4.5, 5.2, 5.3.
 *
 *     npm --prefix functions run test:e2e -- src/__e2e__/workout_commands.e2e.test.ts
 */
import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {
  handleSubmitWorkoutCommands,
  submitWorkoutCommands,
  typedSessionPath,
  type ApplyDeps,
} from "../workout_commands/apply";
import { fenceDocPath, fenceKeyOf, fenceShardOf, fenceValueOf } from "../workout_commands/fence";
import {
  DEVICE,
  EXERCISE,
  PROOF,
  SESSION,
  UID_A,
  UID_B,
  canon,
  envelopeOf,
  loadVectors,
  opIdOf,
  payloadOf,
  sha256Hex,
  type Envelope,
  type Over,
} from "../__tests__/workout_commands/support";

if (admin.apps.length === 0) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const T0 = 1_792_000_000_000;
let now = T0;
const day = (ms: number) => new Date(ms).toISOString().slice(0, 10);
const DAY_MS = 86_400_000;

type Op = { kind: "get" | "set"; path: string };
let ops: Op[] = [];
let failOnSet: ((path: string) => boolean) | null = null;

/** Real Firestore, with the transaction wrapped to record the call order and to inject a fault on a write. */
function wrapFirestore(real: FirebaseFirestore.Firestore): FirebaseFirestore.Firestore {
  return new Proxy(real, {
    get(target, prop) {
      if (prop === "runTransaction") {
        return (cb: (tx: FirebaseFirestore.Transaction) => Promise<unknown>, o?: unknown) =>
          (target.runTransaction as any)((tx: FirebaseFirestore.Transaction) => {
            ops = []; // a new attempt restarts the recording
            return cb(
              new Proxy(tx, {
                get(t, p) {
                  if (p === "get") return (...a: any[]) => { ops.push({ kind: "get", path: a[0].path }); return (t.get as any)(...a); };
                  if (p === "set") {
                    return (...a: any[]) => {
                      if (failOnSet?.(a[0].path)) throw new Error("injected fault");
                      ops.push({ kind: "set", path: a[0].path });
                      return (t.set as any)(...a);
                    };
                  }
                  const v = Reflect.get(t, p);
                  return typeof v === "function" ? v.bind(t) : v;
                },
              }),
            );
          }, o);
      }
      const v = Reflect.get(target, prop);
      return typeof v === "function" ? v.bind(target) : v;
    },
  });
}

const deps: ApplyDeps = { firestore: () => wrapFirestore(db), nowMs: () => now };

const submit = (items: unknown[], uid = UID_A, sessionId = SESSION) =>
  handleSubmitWorkoutCommands(deps, uid, { sessionId, items });
const one = async (e: Envelope | unknown, uid = UID_A) => (await submit([e], uid)).results[0];

async function seedPolicy(uid: string, policy: Record<string, unknown> | null = { migrationState: "SERVER_ONLY" }) {
  if (policy) await db.doc(`users/${uid}/workout_command_policy/current`).set(policy);
}

async function wipe() {
  for (const uid of [UID_A, UID_B]) await db.recursiveDelete(db.doc(`users/${uid}`));
}

/** Every document under users/{uid} with data and update time. */
async function dump(uid: string): Promise<Record<string, { data: unknown; t: string }>> {
  const out: Record<string, { data: unknown; t: string }> = {};
  for (const col of await db.doc(`users/${uid}`).listCollections()) {
    for (const s of (await col.get()).docs) out[s.ref.path] = { data: s.data(), t: s.updateTime.toDate().toISOString() + s.updateTime.nanoseconds };
  }
  return out;
}
/** Same as dump but without the policy document (the tests seed it). */
async function dumpEffects(uid: string) {
  const d = await dump(uid);
  delete d[`users/${uid}/workout_command_policy/current`];
  return d;
}

const get = async (path: string) => {
  const s = await db.doc(path).get();
  return s.exists ? (s.data() as any) : null;
};
const typed = (uid = UID_A, s = SESSION) => get(typedSessionPath(uid, s));
const counter = (ms = now, uid = UID_A) => get(`users/${uid}/workout_command_counters/${day(ms)}`);
const shardOf = (uid: string, opId: string) => get(fenceDocPath(uid, fenceShardOf(opId)));
const receipt = (opId: string, uid = UID_A) => get(`users/${uid}/workout_command_receipts/${opId}`);

const setOver = (n: number, extra: Over = {}): Over => ({
  logicalSetId: `${SESSION}:${EXERCISE}:${n}`,
  seq: n,
  sessionInit: n === 1 ? undefined : null,
  ...extra,
  body: { setId: "set_" + String(n).padStart(4, "0"), ...(extra.body ?? {}) },
});
/** Envelope for set n of the standard session; set 1 carries sessionInit. */
function cmd(seed: string, n = 1, extra: Over = {}, uid = UID_A): { e: Envelope; opId: string } {
  const o = setOver(n, extra);
  if (o.sessionInit === undefined) delete o.sessionInit;
  const p = payloadOf(uid, seed, o);
  return { e: envelopeOf(p), opId: p.operationId };
}

beforeEach(async () => {
  now = T0;
  ops = [];
  failOnSet = null;
  await wipe();
  await seedPolicy(UID_A);
  await seedPolicy(UID_B);
  jest.spyOn(console, "error").mockImplementation(() => undefined);
  jest.spyOn(console, "info").mockImplementation(() => undefined);
});
afterEach(() => jest.restoreAllMocks());
afterAll(async () => { await wipe(); });

describe("I1 commit: all effects land together", () => {
  test("COMMITTED writes typed session, fence entry, receipt and counter", async () => {
    const { e, opId } = cmd("c1");
    const r = await one(e);
    expect(r).toMatchObject({ code: "COMMITTED", resultClass: "C1", operationId: opId });
    expect(r.receipt).toMatchObject({ status: "COMMITTED", effect: "APPENDED", revisionBefore: 0, revisionAfter: 1, serverTimeMs: T0 });

    const t = await typed();
    expect(t.exercises[EXERCISE].sets["1"]).toMatchObject({ operationId: opId, actualReps: 8, loadGrams: 60000, setId: "set_0001" });
    expect(t).toMatchObject({ sessionGeneration: 1, revision: 1, resolvedOps: 1, titleKey: "day:monday", status: "pending", writerEpoch: 1 });
    // The writer secret is stored only as its SHA-256.
    expect(t.writerTokenHash).toBe(sha256Hex(PROOF));
    expect(JSON.stringify(t)).not.toContain(PROOF);

    const shard = await shardOf(UID_A, opId);
    expect(shard.e[fenceKeyOf(opId)]).toBe(fenceValueOf("C", SESSION, JSON.parse(e.payloadBytes) && e.payloadHash));
    const rc = await receipt(opId);
    expect(rc).toMatchObject({ payloadHash: e.payloadHash, status: "COMMITTED", effect: "APPENDED", sessionId: SESSION, logicalSetId: `${SESSION}:${EXERCISE}:1` });
    expect(rc.expireAt.toMillis()).toBe(T0 + 90 * DAY_MS);
    expect(await counter()).toMatchObject({ utcDay: day(T0), applied: 1, sessionsCreated: 1 });
  });

  test("the callable wrapper path: same results through submitWorkoutCommands.run with the flag on", async () => {
    process.env.WORKOUT_COMMANDS_ENABLED = "true";
    try {
      await admin.auth().createUser({ uid: UID_A });
      const { e } = cmd("callable");
      const res: any = await (submitWorkoutCommands as any).run({ auth: { uid: UID_A }, data: { sessionId: SESSION, items: [e] } });
      expect(res.results[0].code).toBe("COMMITTED");
      expect((await typed()).revision).toBe(1);
    } finally {
      delete process.env.WORKOUT_COMMANDS_ENABLED;
      await admin.auth().deleteUser(UID_A).catch(() => undefined);
    }
  });
});

describe("feature flag off writes nothing", () => {
  test("flag unset: failed-precondition feature-disabled and the user tree is untouched", async () => {
    delete process.env.WORKOUT_COMMANDS_ENABLED;
    const before = await dump(UID_A);
    const { e } = cmd("off");
    await expect((submitWorkoutCommands as any).run({ auth: { uid: UID_A }, data: { sessionId: SESSION, items: [e] } })).rejects.toMatchObject({
      code: "failed-precondition",
      message: "feature-disabled",
    });
    expect(await dump(UID_A)).toEqual(before);
  });
});

describe("identical replay (I2) has zero new effects", () => {
  test("second identical submission returns the stored outcome and changes no document", async () => {
    const { e, opId } = cmd("rp");
    const first = await one(e);
    const before = await dump(UID_A);
    const second = await one(e);
    expect(second).toMatchObject({ code: "ALREADY_COMMITTED", resultClass: "C2", operationId: opId });
    expect(second.receipt).toEqual(first.receipt);
    expect(await dump(UID_A)).toEqual(before); // data AND update times identical
  });

  test("replay with a different writer proof or device is still answered from the fence", async () => {
    const { e } = cmd("rp2");
    await one(e);
    const before = await dump(UID_A);
    const r = await one({ ...e, writerProof: "another-proof", deviceInstallId: "other" });
    expect(r.code).toBe("ALREADY_COMMITTED");
    expect(await dump(UID_A)).toEqual(before);
  });

  test("replay after the detail receipt expired is ALREADY_COMMITTED_DETAIL_EXPIRED, still no effect", async () => {
    const { e, opId } = cmd("rp3");
    await one(e);
    await db.doc(`users/${UID_A}/workout_command_receipts/${opId}`).delete();
    const before = await dump(UID_A);
    expect((await one(e)).code).toBe("ALREADY_COMMITTED_DETAIL_EXPIRED");
    expect(await dump(UID_A)).toEqual(before);
  });

  test("replay with the daily counter at the limit still returns the stored outcome", async () => {
    const { e } = cmd("rp4");
    await one(e);
    await db.doc(`users/${UID_A}/workout_command_counters/${day(T0)}`).set({ utcDay: day(T0), applied: 2000, sessionsCreated: 1 });
    expect((await one(e)).code).toBe("ALREADY_COMMITTED");
  });

  test("replay is not charged to the counter", async () => {
    const { e } = cmd("rp5");
    await one(e);
    await one(e);
    await one(e);
    expect((await counter()).applied).toBe(1);
  });
});

describe("I5 same operationId, different payload", () => {
  test("altered payload gives ID_PAYLOAD_MISMATCH and exposes no receipt contents, nothing changes", async () => {
    const base = payloadOf(UID_A, "alt");
    const altered = payloadOf(UID_A, "alt", { body: { actualReps: 9 } });
    await one(envelopeOf(base));
    const before = await dump(UID_A);
    const r = await one(envelopeOf(altered));
    expect(r.code).toBe("ID_PAYLOAD_MISMATCH");
    expect(r.resultClass).toBe("C4");
    expect(r.receipt).toBeUndefined();
    expect(await dump(UID_A)).toEqual(before);
    expect((await typed()).exercises[EXERCISE].sets["1"].actualReps).toBe(8);
  });

  test("the shared golden vector pair behaves the same way", async () => {
    const v = loadVectors();
    const a = v.find((x) => x.name === "same_operation_id_original")!;
    const b = v.find((x) => x.name === "same_operation_id_altered_reps")!;
    const env = (x: typeof a): Envelope => ({ payloadBytes: x.payloadText, payloadHash: x.payloadHash, writerProof: PROOF, deviceInstallId: DEVICE });
    expect((await one(env(a))).code).toBe("COMMITTED");
    expect((await one(env(b))).code).toBe("ID_PAYLOAD_MISMATCH");
    expect((await one(env(a))).code).toBe("ALREADY_COMMITTED");
  });

  test("every valid golden vector commits when applied to a fresh account, with its recorded hash in the receipt", async () => {
    for (const v of loadVectors().filter((x) => x.expectedPrepare === "OK" && x.authUid === UID_A && x.name !== "same_operation_id_altered_reps")) {
      await wipe();
      await seedPolicy(UID_A);
      const sid = (v.payloadObject as any).sessionId;
      const r = (await submit([{ payloadBytes: v.payloadText, payloadHash: v.payloadHash, writerProof: PROOF }], UID_A, sid)).results[0];
      // vectors that depend on other operations (dependsOn / no sessionInit) are non-terminal or refused, never silently applied
      if ((v.payloadObject as any).sessionInit !== null && (v.payloadObject as any).dependsOn.length === 0) {
        // a NEW session can only be created at generation 1 (T = 0); higher generations are GENERATION_MISMATCH (4.2 step 6a)
        const want = (v.payloadObject as any).sessionGeneration === 1 ? "COMMITTED" : "GENERATION_MISMATCH";
        expect({ name: v.name, code: r.code }).toEqual({ name: v.name, code: want });
        if (want === "COMMITTED") expect((await receipt((v.payloadObject as any).operationId))?.payloadHash).toBe(v.payloadHash);
      } else {
        expect(r.code).not.toBe("COMMITTED");
      }
    }
  });
});

describe("I6 identity binding, before any read", () => {
  test("payload uid of another user: UID_MISMATCH and no document is created for either user", async () => {
    const before = [await dump(UID_A), await dump(UID_B)];
    const p = payloadOf(UID_B, "um");
    const r = await one(envelopeOf(p), UID_A);
    expect(r.code).toBe("UID_MISMATCH");
    expect(ops).toEqual([]); // no transaction was even started
    expect([await dump(UID_A), await dump(UID_B)]).toEqual(before);
  });

  test("B's payload submitted by B with A's operationId: ID_UID_MISMATCH, A's data unreachable", async () => {
    const a = cmd("shared");
    await one(a.e);
    const before = await dump(UID_A);
    const p = payloadOf(UID_B, "x", { operationId: a.opId });
    const r = await one(envelopeOf(p), UID_B);
    expect(r.code).toBe("ID_UID_MISMATCH");
    expect(r.receipt).toBeUndefined();
    expect(await dump(UID_A)).toEqual(before);
    expect(await dumpEffects(UID_B)).toEqual({});
  });

  test("the same content committed by two users keeps their trees separate", async () => {
    const a = cmd("same", 1, {}, UID_A);
    const b = cmd("same", 1, {}, UID_B);
    expect((await one(a.e, UID_A)).code).toBe("COMMITTED");
    expect((await one(b.e, UID_B)).code).toBe("COMMITTED");
    expect((await typed(UID_A)).revision).toBe(1);
    expect((await typed(UID_B)).revision).toBe(1);
    expect((await counter(now, UID_B)).applied).toBe(1);
  });
});

describe("I8 second APPEND to the same logical set", () => {
  test("different operationId, same set identity: DUPLICATE_LOGICAL_SET, original set untouched, refusal recorded", async () => {
    const first = cmd("d1");
    await one(first.e);
    const second = cmd("d2", 1, { sessionInit: null, seq: 2, body: { actualReps: 12, loadGrams: 1 } });
    const r = await one(second.e);
    expect(r).toMatchObject({ code: "DUPLICATE_LOGICAL_SET", resultClass: "C3" });
    const t = await typed();
    expect(t.exercises[EXERCISE].sets["1"]).toMatchObject({ operationId: first.opId, actualReps: 8, loadGrams: 60000 });
    expect(t.revision).toBe(1); // no mutation
    expect(t.resolvedOps).toBe(2); // refusals count as resolved operations
    expect((await shardOf(UID_A, second.opId)).e[fenceKeyOf(second.opId)][0]).toBe("R");
    expect(await receipt(second.opId)).toMatchObject({ status: "REJECTED", reasonCode: "DUPLICATE_LOGICAL_SET", effect: null });
    // replay of the refusal returns the stored refusal
    const again = await one(second.e);
    expect(again).toMatchObject({ code: "ALREADY_REJECTED", reason: "DUPLICATE_LOGICAL_SET" });
  });

  test("the refusal holds even after the first set's device changed: any origin", async () => {
    await one(cmd("d3").e);
    const other = cmd("d4", 1, { sessionInit: null, originDeviceInstallId: "dev_OTHER" });
    expect((await one(other.e)).code).toBe("DUPLICATE_LOGICAL_SET");
  });

  test("full set identity: same index on another exercise and another index on the same exercise both commit", async () => {
    await one(cmd("d5").e);
    const otherEx = payloadOf(UID_A, "d6", { exerciseId: "ex_squat", logicalSetId: `${SESSION}:ex_squat:1`, sessionInit: null, seq: 2 });
    const next = cmd("d7", 2);
    expect((await one(envelopeOf(otherEx))).code).toBe("COMMITTED");
    expect((await one(next.e)).code).toBe("COMMITTED");
    const t = await typed();
    expect(Object.keys(t.exercises).sort()).toEqual(["ex_bench_press", "ex_squat"]);
    expect(Object.keys(t.exercises[EXERCISE].sets).sort()).toEqual(["1", "2"]);
    expect(t.revision).toBe(3);
  });
});

describe("one transaction: both-or-neither", () => {
  const targets: Array<[string, (opId: string) => string]> = [
    ["typed session", () => typedSessionPath(UID_A, SESSION)],
    ["fence shard", (id) => fenceDocPath(UID_A, fenceShardOf(id))],
    ["receipt", (id) => `users/${UID_A}/workout_command_receipts/${id}`],
    ["daily counter", () => `users/${UID_A}/workout_command_counters/${day(T0)}`],
  ];

  test.each(targets)("a fault while writing the %s leaves NONE of the four documents, and a retry then commits", async (_n, pathOf) => {
    const { e, opId } = cmd("tx-" + _n);
    failOnSet = (p) => p === pathOf(opId);
    const r = await one(e);
    expect(r.code).toBe("UNAVAILABLE");
    expect(r.resultClass).toBe("C6");
    expect(await dumpEffects(UID_A)).toEqual({}); // nothing at all, including documents queued before the fault
    failOnSet = null;
    const retry = await one(e);
    expect(retry.code).toBe("COMMITTED"); // not ALREADY_*: no fence entry survived the failed attempt
    expect(Object.keys(await dumpEffects(UID_A)).length).toBe(4);
    expect((await counter()).applied).toBe(1);
  });

  test("the fault is injected AFTER the effect write (typed session is queued first)", async () => {
    const { e, opId } = cmd("tx-order");
    const seen: string[] = [];
    failOnSet = (p) => { seen.push(p); return p.includes("workout_command_counters"); };
    await one(e);
    expect(seen[0]).toBe(typedSessionPath(UID_A, SESSION));
    expect(seen[seen.length - 1]).toContain("workout_command_counters");
    expect(await typed()).toBeNull();
    expect(await receipt(opId)).toBeNull();
  });

  test("a refusal (DUPLICATE_LOGICAL_SET) is also atomic: fault leaves no fence/receipt and the retry records the refusal", async () => {
    await one(cmd("tx-d1").e);
    const dup = cmd("tx-d2", 1, { sessionInit: null, seq: 2 });
    const before = await dump(UID_A);
    failOnSet = (p) => p.includes("workout_command_receipts");
    expect((await one(dup.e)).code).toBe("UNAVAILABLE");
    expect(await dump(UID_A)).toEqual(before);
    failOnSet = null;
    expect((await one(dup.e)).code).toBe("DUPLICATE_LOGICAL_SET");
  });
});

describe("no read after a write inside the transaction", () => {
  const assertReadsFirst = () => {
    const firstSet = ops.findIndex((o) => o.kind === "set");
    expect(ops.some((o) => o.kind === "get")).toBe(true);
    if (firstSet >= 0) expect(ops.slice(firstSet).every((o) => o.kind === "set")).toBe(true);
  };

  test("commit, replay, duplicate refusal, rate limit and policy hold all read first", async () => {
    const c1 = cmd("ro1");
    await one(c1.e);
    assertReadsFirst();
    expect(ops.filter((o) => o.kind === "set").length).toBe(4);
    await one(c1.e); // replay
    assertReadsFirst();
    expect(ops.some((o) => o.kind === "set")).toBe(false);
    await one(cmd("ro2", 1, { sessionInit: null, seq: 2 }).e); // duplicate
    assertReadsFirst();
    await db.doc(`users/${UID_A}/workout_command_counters/${day(T0)}`).set({ utcDay: day(T0), applied: 2000, sessionsCreated: 1 });
    await one(cmd("ro3", 2).e); // rate limited
    assertReadsFirst();
    expect(ops.some((o) => o.kind === "set")).toBe(false);
    await db.doc(`users/${UID_A}/workout_command_policy/current`).set({ migrationState: "LEGACY_ONLY" });
    await one(cmd("ro4", 3).e);
    assertReadsFirst();
    expect(ops.some((o) => o.kind === "set")).toBe(false);
  });

  test("dependsOn on another shard is read before any write", async () => {
    const dep = cmd("ro-dep");
    await one(dep.e);
    const child = cmd("ro-child", 2, { dependsOn: [dep.opId] });
    expect((await one(child.e)).code).toBe("COMMITTED");
    assertReadsFirst();
  });
});

describe("daily quota (4.2 step 2 / 3b)", () => {
  const seedCounter = (applied: number, sessionsCreated = 0, ms = T0) =>
    db.doc(`users/${UID_A}/workout_command_counters/${day(ms)}`).set({ utcDay: day(ms), applied, sessionsCreated });

  test("command 2,000 commits with a lost ack; its replay is ALREADY_COMMITTED; new command 2,001 is RATE_LIMITED and writes nothing", async () => {
    await seedCounter(1999);
    const c2000 = cmd("q2000");
    const r = await one(c2000.e);
    expect(r.code).toBe("COMMITTED");
    expect((await counter()).applied).toBe(2000);
    // the response was lost: the client resends the same bytes
    const replay = await one(c2000.e);
    expect(replay.code).toBe("ALREADY_COMMITTED");
    expect((await counter()).applied).toBe(2000);

    const c2001 = cmd("q2001", 2);
    const before = await dump(UID_A);
    const limited = await one(c2001.e);
    expect(limited).toMatchObject({ code: "RATE_LIMITED", resultClass: "C5b" });
    expect(limited.retryAfterMs).toBeGreaterThanOrEqual(1000);
    expect(limited.retryAfterMs).toBeLessThanOrEqual(DAY_MS);
    expect(await dump(UID_A)).toEqual(before); // non-terminal: no fence entry, no receipt
    expect(await receipt(c2001.opId)).toBeNull();

    // next UTC day the same bytes commit
    now = T0 - (T0 % DAY_MS) + DAY_MS + 5;
    expect((await one(c2001.e)).code).toBe("COMMITTED");
    expect((await counter(now)).applied).toBe(1);
  });

  test("a batch [replay, new, new] at the limit: stored outcome, RATE_LIMITED, NOT_ATTEMPTED", async () => {
    await seedCounter(1999);
    const a = cmd("qb1");
    await one(a.e);
    const res = await submit([a.e, cmd("qb2", 2).e, cmd("qb3", 3).e]);
    expect(res.results.map((r) => r.code)).toEqual(["ALREADY_COMMITTED", "RATE_LIMITED", "NOT_ATTEMPTED"]);
  });

  test("counter is per UTC day: yesterday's full counter does not limit today", async () => {
    await seedCounter(2000, 50, T0 - DAY_MS);
    expect((await one(cmd("qd").e)).code).toBe("COMMITTED");
  });

  test("50 session creations per day: the 51st new session is RATE_LIMITED, existing sessions keep working", async () => {
    await seedCounter(10, 49);
    const s1 = cmd("qs1");
    expect((await one(s1.e)).code).toBe("COMMITTED");
    expect((await counter()).sessionsCreated).toBe(50);
    const other = payloadOf(UID_A, "qs2", { sessionId: "day_other", logicalSetId: "day_other:ex_bench_press:1" });
    const r = (await submit([envelopeOf(other)], UID_A, "day_other")).results[0];
    expect(r.code).toBe("RATE_LIMITED");
    expect((await one(cmd("qs3", 2).e)).code).toBe("COMMITTED");
  });

  test("concurrent batches serialize on the counter: exactly the remaining quota commits", async () => {
    await seedCounter(1996);
    expect((await one(cmd("qc0").e)).code).toBe("COMMITTED"); // applied 1997, session exists
    const results = await Promise.all([2, 3, 4, 5, 6].map((n) => submit([cmd("qc" + n, n).e])));
    const codes = results.map((r) => r.results[0].code);
    expect(codes.filter((c) => c === "COMMITTED").length).toBe(3);
    expect(codes.filter((c) => c === "RATE_LIMITED").length).toBe(2);
    expect(codes.filter((c) => c !== "COMMITTED" && c !== "RATE_LIMITED")).toEqual([]);
    expect((await counter()).applied).toBe(2000);
    const t = await typed();
    expect(Object.keys(t.exercises[EXERCISE].sets).length).toBe(4);
    expect(t.revision).toBe(4);
  });

  test("two concurrent submissions of the SAME command apply once", async () => {
    const { e } = cmd("qsame");
    const [a, b] = await Promise.all([one(e), one(e)]);
    expect([a.code, b.code].sort()).toEqual(["ALREADY_COMMITTED", "COMMITTED"]);
    expect((await counter()).applied).toBe(1);
    expect((await typed()).revision).toBe(1);
  });
});

describe("policy gate outcomes (4.2 step 2)", () => {
  const POLICY = `users/${UID_A}/workout_command_policy/current`;
  const setPolicy = async (p: Record<string, unknown> | null) => {
    if (p === null) await db.doc(POLICY).delete();
    else await db.doc(POLICY).set(p);
  };

  test.each<[string, Record<string, unknown> | null, string, string | undefined]>([
    ["absent policy", null, "MIGRATION_HOLD", undefined],
    ["LEGACY_ONLY", { migrationState: "LEGACY_ONLY" }, "MIGRATION_HOLD", undefined],
    ["SERVER_ONLY paused", { migrationState: "SERVER_ONLY", sendingPaused: true }, "MIGRATION_HOLD", undefined],
    ["DELETING", { migrationState: "DELETING" }, "ACCOUNT_DELETING", undefined],
    ["DRAIN OPEN unacked device", { migrationState: "DRAIN", drainPhase: "OPEN", drainedDevices: { other: 1 } }, "MIGRATION_HOLD", undefined],
    ["DRAIN CLOSED acked device", { migrationState: "DRAIN", drainPhase: "CLOSED", drainedDevices: { [DEVICE]: 1 } }, "MIGRATION_HOLD", undefined],
    ["DRAIN OPEN acked device (V0 excludes DRAIN)", { migrationState: "DRAIN", drainPhase: "OPEN", drainedDevices: { [DEVICE]: 1 } }, "MIGRATION_HOLD", undefined],
    ["DRAIN OPEN device-id substitution (B claims A's acknowledged id)", { migrationState: "DRAIN", drainPhase: "OPEN", drainedDevices: { [DEVICE]: 1 } }, "MIGRATION_HOLD", undefined],
  ])("%s answers %s and records nothing", async (_n, policy, code) => {
    await setPolicy(policy);
    const before = await dumpEffects(UID_A);
    const res = await submit([cmd("pg-" + _n).e, cmd("pg2-" + _n, 2).e]);
    expect(res.results.map((r) => r.code)).toEqual([code, "NOT_ATTEMPTED"]);
    expect(res.results[0].resultClass).toBe("C5b");
    expect(await dumpEffects(UID_A)).toEqual(before);
  });

  test.each<[string, Record<string, unknown>]>([
    ["SERVER_ONLY", { migrationState: "SERVER_ONLY" }],
    ["SEALED", { migrationState: "SEALED" }],
  ])("%s accepts the command", async (_n, policy) => {
    await setPolicy(policy);
    expect((await one(cmd("pa-" + _n).e)).code).toBe("COMMITTED");
  });

  test("a held command commits unchanged once the policy opens (non-terminal)", async () => {
    await setPolicy(null);
    const { e } = cmd("pg-late");
    expect((await one(e)).code).toBe("MIGRATION_HOLD");
    await setPolicy({ migrationState: "SERVER_ONLY" });
    expect((await one(e)).code).toBe("COMMITTED");
  });
});

describe("batch limit 25 (limitsVersion 1)", () => {
  test("26 items: invalid-argument and no document written", async () => {
    const before = await dump(UID_A);
    const items = Array.from({ length: 26 }, (_v, i) => cmd("b26-" + i, i + 1).e);
    await expect(submit(items)).rejects.toBeInstanceOf(HttpsError);
    await expect(submit(items)).rejects.toMatchObject({ code: "invalid-argument" });
    expect(await dump(UID_A)).toEqual(before);
  });

  test("exactly 25 items commit in order, one transaction each", async () => {
    const items = Array.from({ length: 25 }, (_v, i) => cmd("b25-" + i, i + 1).e);
    const res = await submit(items);
    expect(res.results.map((r) => r.code)).toEqual(Array(25).fill("COMMITTED"));
    expect(res.results.map((r) => r.receipt!.revisionAfter)).toEqual(Array.from({ length: 25 }, (_v, i) => i + 1));
    const t = await typed();
    expect(t.revision).toBe(25);
    expect(t.resolvedOps).toBe(25);
    expect((await counter()).applied).toBe(25);
  });

  test("[invalid, good, good] returns INVALID_PAYLOAD, COMMITTED, COMMITTED (4.5)", async () => {
    const res = await submit([{ junk: 1 }, cmd("bb1").e, cmd("bb2", 2).e]);
    expect(res.results.map((r) => r.code)).toEqual(["INVALID_PAYLOAD", "COMMITTED", "COMMITTED"]);
  });
});

describe("terminal and non-terminal decisions of 4.2 step 6", () => {
  test("acceptedEpoch above the writer epoch: INVALID_PAYLOAD, nothing recorded", async () => {
    const before = await dumpEffects(UID_A);
    const r = await one(cmd("ep", 1, { acceptedEpoch: 2 }).e);
    expect(r.code).toBe("INVALID_PAYLOAD");
    expect(await dumpEffects(UID_A)).toEqual(before);
    expect((await one(cmd("ep2", 1, { acceptedEpoch: 1 }).e)).code).toBe("COMMITTED"); // control: epoch 1 exists
  });

  test("new session with generation 2 is GENERATION_MISMATCH (terminal, fence R, no session)", async () => {
    const c = cmd("gen", 1, { sessionGeneration: 2 });
    expect((await one(c.e)).code).toBe("GENERATION_MISMATCH");
    expect(await typed()).toBeNull();
    expect((await shardOf(UID_A, c.opId)).e[fenceKeyOf(c.opId)][0]).toBe("R");
    expect((await one(c.e)).code).toBe("ALREADY_REJECTED");
  });

  test("existing session: lower generation SESSION_DELETED_ELSEWHERE, higher GENERATION_MISMATCH", async () => {
    await db.doc(typedSessionPath(UID_A, SESSION)).set(seedTyped({ sessionGeneration: 2 }));
    expect((await one(cmd("g1", 1, { sessionInit: null, sessionGeneration: 1 }).e)).code).toBe("SESSION_DELETED_ELSEWHERE");
    expect((await one(cmd("g3", 2, { sessionInit: null, sessionGeneration: 3 }).e)).code).toBe("GENERATION_MISMATCH");
    expect((await one(cmd("g2", 3, { sessionInit: null, sessionGeneration: 2 }).e)).code).toBe("COMMITTED");
  });

  test("no sessionInit on an absent session and no dependency: SESSION_DELETED_ELSEWHERE", async () => {
    expect((await one(cmd("nosess", 2).e)).code).toBe("SESSION_DELETED_ELSEWHERE");
  });

  test("dependency not yet in the fence: DEPENDENCY_PENDING writes nothing, then commits after the dependency", async () => {
    const init = cmd("dp-init");
    const child = cmd("dp-child", 2, { dependsOn: [init.opId] });
    const before = await dumpEffects(UID_A);
    expect((await one(child.e)).code).toBe("DEPENDENCY_PENDING");
    expect(await dumpEffects(UID_A)).toEqual(before);
    expect((await one(init.e)).code).toBe("COMMITTED");
    expect((await one(child.e)).code).toBe("COMMITTED");
  });

  test("dependency that was refused: DEPENDENCY_REJECTED (terminal)", async () => {
    await one(cmd("dr-first").e);
    const dup = cmd("dr-dup", 1, { sessionInit: null, seq: 2 });
    expect((await one(dup.e)).code).toBe("DUPLICATE_LOGICAL_SET");
    const child = cmd("dr-child", 2, { dependsOn: [dup.opId] });
    expect((await one(child.e)).code).toBe("DEPENDENCY_REJECTED");
  });

  test("wrong writer proof: NOT_WRITER, nothing written, stops the batch", async () => {
    await one(cmd("w1").e);
    const before = await dumpEffects(UID_A);
    const bad = { ...cmd("w2", 2).e, writerProof: "stolen-or-wrong" };
    const res = await submit([bad, cmd("w3", 3).e]);
    expect(res.results.map((r) => r.code)).toEqual(["NOT_WRITER", "NOT_ATTEMPTED"]);
    expect(await dumpEffects(UID_A)).toEqual(before);
    expect(res.results[0].sessionState).toMatchObject({ exists: true, writerEpoch: 1 });
    expect(JSON.stringify(res)).not.toContain(sha256Hex(PROOF)); // token hash is never returned
  });

  test("writerless session: the first proof claims it", async () => {
    await db.doc(typedSessionPath(UID_A, SESSION)).set(seedTyped({ writerTokenHash: null }));
    expect((await one(cmd("wl", 1, { sessionInit: null }).e)).code).toBe("COMMITTED");
    expect((await typed()).writerTokenHash).toBe(sha256Hex(PROOF));
    expect((await one({ ...cmd("wl2", 2, { sessionInit: null }).e, writerProof: "nope" })).code).toBe("NOT_WRITER");
  });

  test("abandoned session: SESSION_CLOSED; session at 2000 resolved operations: SESSION_COMMAND_LIMIT (non-terminal)", async () => {
    await db.doc(typedSessionPath(UID_A, SESSION)).set(seedTyped({ status: "abandoned" }));
    expect((await one(cmd("cl", 1, { sessionInit: null }).e)).code).toBe("SESSION_CLOSED");
    await db.doc(typedSessionPath(UID_A, SESSION)).set(seedTyped({ resolvedOps: 2000 }));
    const lim = cmd("lim", 2, { sessionInit: null });
    expect((await one(lim.e)).code).toBe("SESSION_COMMAND_LIMIT");
    expect(await receipt(lim.opId)).toBeNull();
  });

  test("two operations whose fence keys share a shard are both kept (merge, not overwrite)", async () => {
    const byShard = new Map<string, string>();
    let a = "", b = "";
    for (let i = 0; i < 5000 && !b; i++) {
      const id = opIdOf(UID_A, "sh" + i);
      const s = fenceShardOf(id);
      if (byShard.has(s)) { a = byShard.get(s)!; b = id; } else byShard.set(s, id);
    }
    const e1 = envelopeOf(payloadOf(UID_A, "x", { operationId: a }));
    const p2 = payloadOf(UID_A, "x", { operationId: b, logicalSetId: `${SESSION}:${EXERCISE}:2`, seq: 2, sessionInit: null, body: { setId: "set_0002" } });
    expect((await one(e1)).code).toBe("COMMITTED");
    expect((await one(envelopeOf(p2))).code).toBe("COMMITTED");
    const shard = await shardOf(UID_A, a);
    expect(Object.keys(shard.e).sort()).toEqual([fenceKeyOf(a), fenceKeyOf(b)].sort());
    expect((await one(e1)).code).toBe("ALREADY_COMMITTED");
    expect((await one(envelopeOf(p2))).code).toBe("ALREADY_COMMITTED");
  });

  test("full fence shard: FENCE_SHARD_FULL (retryable) writes nothing; an existing entry is still answered", async () => {
    const first = cmd("fs-first");
    await one(first.e);
    const target = cmd("fs-new", 2);
    const shardRef = db.doc(fenceDocPath(UID_A, fenceShardOf(target.opId)));
    const filler: Record<string, string> = {};
    for (let i = 0; filler && Object.keys(filler).length < 12000; i++) filler["F" + String(i).padStart(21, "0")] = "C" + "A".repeat(22);
    await shardRef.set({ e: filler, spill: 0 }, { merge: true });
    const before = await dump(UID_A);
    const r = await one(target.e);
    expect(r).toMatchObject({ code: "FENCE_SHARD_FULL", resultClass: "C6" });
    expect(await dump(UID_A)).toEqual(before);
    expect((await one(first.e)).code).toBe("ALREADY_COMMITTED");
  });
});

function seedTyped(over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    sessionId: SESSION, sessionGeneration: 1, writerEpoch: 1, writerDeviceInstallId: DEVICE, writerTokenHash: sha256Hex(PROOF),
    lastSeqByTarget: {}, maxSeqSeen: 0, resolvedOps: 0, revision: 0, quarantineCount: 0, status: "pending",
    titleKey: "default", dayId: null, startedAtClientMs: 0, createdAtMs: 0, updatedAtMs: 0, exercises: {},
    ...over,
  };
}

// keep `canon` referenced for payload-text assertions
test("support canonicalizer agrees with the envelope bytes", () => {
  const p = payloadOf(UID_A, "z");
  expect(envelopeOf(p).payloadBytes).toBe(canon(p));
});

describe("S1: a caller without the writer proof can never change anything (NOT_WRITER before generation checks)", () => {
  async function committedSession() {
    await db.doc(typedSessionPath(UID_A, SESSION)).set(seedTyped({ sessionGeneration: 2 }));
    expect((await one(cmd("s1-ok", 1, { sessionInit: null, sessionGeneration: 2 }).e)).code).toBe("COMMITTED");
  }

  test.each([1, 2, 3])("wrong proof with generation %i (G-1, G, G+1) gets NOT_WRITER and every collection is byte-identical", async (g) => {
    await committedSession();
    const before = await dump(UID_A); // typed session, fence, receipt, counter incl. update times
    expect(Object.keys(before).filter((k) => !k.includes("policy")).length).toBe(4);
    const c = cmd("s1-" + g, 2 + g, { sessionInit: null, sessionGeneration: g });
    const r = await one({ ...c.e, writerProof: "not-the-writer-proof" });
    expect(r).toMatchObject({ code: "NOT_WRITER", resultClass: "C5b" });
    expect(await dump(UID_A)).toEqual(before);
    expect(await receipt(c.opId)).toBeNull();
    expect(JSON.stringify(r)).not.toContain(sha256Hex(PROOF));
  });

  test("the same wrong-proof calls inside one batch: NOT_WRITER stops it, nothing changes", async () => {
    await committedSession();
    const before = await dump(UID_A);
    const items = [1, 2, 3].map((g) => ({ ...cmd("s1b-" + g, 5 + g, { sessionInit: null, sessionGeneration: g }).e, writerProof: "wrong" }));
    const res = await submit(items);
    expect(res.results.map((x) => x.code)).toEqual(["NOT_WRITER", "NOT_ATTEMPTED", "NOT_ATTEMPTED"]);
    expect(await dump(UID_A)).toEqual(before);
  });

  test("a proof-less envelope is INVALID_PAYLOAD before any read and changes nothing", async () => {
    await committedSession();
    const before = await dump(UID_A);
    const c = cmd("s1-np", 2, { sessionInit: null, sessionGeneration: 3 });
    const { writerProof: _drop, ...noProof } = c.e;
    expect((await one(noProof)).code).toBe("INVALID_PAYLOAD");
    expect((await one({ ...c.e, writerProof: "" })).code).toBe("INVALID_PAYLOAD");
    expect(await dump(UID_A)).toEqual(before);
  });

  test("control: the real writer with G+1 / G-1 still gets the recorded generation refusals", async () => {
    await committedSession();
    expect((await one(cmd("s1c-hi", 2, { sessionInit: null, sessionGeneration: 3 }).e)).code).toBe("GENERATION_MISMATCH");
    expect((await one(cmd("s1c-lo", 3, { sessionInit: null, sessionGeneration: 1 }).e)).code).toBe("SESSION_DELETED_ELSEWHERE");
  });
});

describe("S2: reserved ids (^__.*__$)", () => {
  test.each([
    ["sessionId __proto__", { sessionId: "__proto__", logicalSetId: "__proto__:ex_bench_press:1" }],
    ["sessionId __a__", { sessionId: "__a__", logicalSetId: "__a__:ex_bench_press:1" }],
    ["exerciseId __proto__", { exerciseId: "__proto__", logicalSetId: `${SESSION}:__proto__:1` }],
    ["exerciseId __a__", { exerciseId: "__a__", logicalSetId: `${SESSION}:__a__:1` }],
  ])("item with %s is INVALID_PAYLOAD and nothing is written", async (_n, over) => {
    const before = await dump(UID_A);
    const p = payloadOf(UID_A, "res-" + _n, over as Over);
    const r = (await submit([envelopeOf(p)], UID_A, SESSION)).results[0];
    expect(r.code).toBe("INVALID_PAYLOAD");
    expect(await dump(UID_A)).toEqual(before);
  });

  test("a request-level reserved sessionId is a batch-level invalid-argument", async () => {
    for (const sid of ["__proto__", "__a__"]) {
      await expect(submit([cmd("res-req").e], UID_A, sid)).rejects.toMatchObject({ code: "invalid-argument" });
    }
    expect(await dumpEffects(UID_A)).toEqual({});
  });

  test("control: ids that only start or end with underscores are fine", async () => {
    const p = payloadOf(UID_A, "res-ok", { exerciseId: "__a", logicalSetId: `${SESSION}:__a:1` });
    expect((await one(envelopeOf(p))).code).toBe("COMMITTED");
  });
});

describe("S3: UNAVAILABLE causes are logged as closed slugs without identifiers", () => {
  const lines = (spy: jest.SpyInstance) => spy.mock.calls.map((c) => JSON.stringify(c));
  const noIds = (all: string[], ...ids: string[]) => {
    for (const id of ids) for (const l of all) expect(l).not.toContain(id);
  };

  test("malformed stored fence entry: UNAVAILABLE, nothing re-applied, slug fence_entry_malformed", async () => {
    const warn = jest.spyOn(logger, "warn").mockImplementation(() => undefined);
    const info = jest.spyOn(logger, "info").mockImplementation(() => undefined);
    const c = cmd("s3-fence");
    await db.doc(fenceDocPath(UID_A, fenceShardOf(c.opId))).set({ e: { [fenceKeyOf(c.opId)]: "garbage" }, spill: 0 });
    const before = await dump(UID_A);
    const r = await one(c.e);
    expect(r.code).toBe("UNAVAILABLE");
    expect(await dump(UID_A)).toEqual(before);
    expect(warn).toHaveBeenCalledWith("workout_command_event", { slug: "fence_entry_malformed" });
    expect(info).toHaveBeenCalledWith("workout_command_result", { code: "UNAVAILABLE" });
    noIds([...lines(warn), ...lines(info)], UID_A, c.opId, SESSION);
  });

  test("unexpected error: slug item_unexpected_error with the Firestore code, one result line per item", async () => {
    const err = jest.spyOn(logger, "error").mockImplementation(() => undefined);
    const info = jest.spyOn(logger, "info").mockImplementation(() => undefined);
    const c = cmd("s3-err");
    failOnSet = (p) => p.includes("workout_command_counters");
    expect((await one(c.e)).code).toBe("UNAVAILABLE");
    expect(err).toHaveBeenCalledTimes(1);
    expect(err.mock.calls[0][0]).toBe("workout_command_event");
    expect(err.mock.calls[0][1]).toMatchObject({ slug: "item_unexpected_error" });
    expect(info).toHaveBeenCalledWith("workout_command_result", { code: "UNAVAILABLE" });
    noIds([...lines(err), ...lines(info)], UID_A, c.opId, SESSION);
  });

  test("a result line is written for each item of a batch and carries only the code", async () => {
    const info = jest.spyOn(logger, "info").mockImplementation(() => undefined);
    const res = await submit([cmd("s3-b1").e, cmd("s3-b2", 2).e, cmd("s3-b3", 2).e]);
    expect(res.results.map((r) => r.code)).toEqual(["COMMITTED", "COMMITTED", "DUPLICATE_LOGICAL_SET"]);
    const resultLines = info.mock.calls.filter((c) => c[0] === "workout_command_result");
    expect(resultLines.map((c) => (c[1] as any).code)).toEqual(["COMMITTED", "COMMITTED", "DUPLICATE_LOGICAL_SET"]);
    for (const c of resultLines) expect(Object.keys(c[1] as object)).toEqual(["code"]);
  });
});

describe("DRAIN is never admitted in V0, even with a substituted device id", () => {
  test("policy acknowledges deviceA; a caller sending deviceInstallId deviceA (not the payload origin) is held and nothing is written", async () => {
    await db.doc(`users/${UID_A}/workout_command_policy/current`).set({ migrationState: "DRAIN", drainPhase: "OPEN", drainedDevices: { deviceA: 1 } });
    const before = await dumpEffects(UID_A);
    const c = cmd("drain-sub");
    const r = await one({ ...c.e, deviceInstallId: "deviceA" });
    expect(r).toMatchObject({ code: "MIGRATION_HOLD", resultClass: "C5b" });
    expect(await dumpEffects(UID_A)).toEqual(before);
    expect(await typed()).toBeNull();
    expect(await receipt(c.opId)).toBeNull();
  });
});

describe("concurrent operations that hit the same fence shard", () => {
  const sameShardIds = (n: number, uid = UID_A) => {
    const byShard = new Map<string, string[]>();
    for (let i = 0; i < 20000; i++) {
      const id = opIdOf(uid, "cs" + i);
      const l = byShard.get(fenceShardOf(id)) ?? [];
      l.push(id);
      byShard.set(fenceShardOf(id), l);
      if (l.length === n) return l;
    }
    throw new Error("no shard collision found");
  };

  test("two different sessions created at the same time: both commit, shard keeps both keys, counters add up", async () => {
    const [a, b] = sameShardIds(2);
    const pa = payloadOf(UID_A, "x", { operationId: a, sessionId: "s_one", logicalSetId: `s_one:${EXERCISE}:1` });
    const pb = payloadOf(UID_A, "x", { operationId: b, sessionId: "s_two", logicalSetId: `s_two:${EXERCISE}:1` });
    const [ra, rb] = await Promise.all([submit([envelopeOf(pa)], UID_A, "s_one"), submit([envelopeOf(pb)], UID_A, "s_two")]);
    expect(ra.results[0].code).toBe("COMMITTED");
    expect(rb.results[0].code).toBe("COMMITTED");
    const shard = await shardOf(UID_A, a);
    expect(Object.keys(shard.e).sort()).toEqual([fenceKeyOf(a), fenceKeyOf(b)].sort());
    expect(await counter()).toMatchObject({ applied: 2, sessionsCreated: 2 });
    expect((await typed(UID_A, "s_one")).revision).toBe(1);
    expect((await typed(UID_A, "s_two")).revision).toBe(1);
  });

  test("three operations of one session on one shard fired together: all commit, revision, resolvedOps and counter agree", async () => {
    const [a, b, c] = sameShardIds(3);
    const first = cmd("cs-first");
    expect((await one(first.e)).code).toBe("COMMITTED");
    const mk = (id: string, n: number) => envelopeOf(payloadOf(UID_A, "x", { operationId: id, logicalSetId: `${SESSION}:${EXERCISE}:${n}`, seq: n, sessionInit: null, body: { setId: "set_000" + n } }));
    const res = await Promise.all([a, b, c].map((id, i) => submit([mk(id, i + 2)])));
    expect(res.map((r) => r.results[0].code)).toEqual(["COMMITTED", "COMMITTED", "COMMITTED"]);
    const t = await typed();
    expect(t.revision).toBe(4);
    expect(t.resolvedOps).toBe(4);
    expect(Object.keys(t.exercises[EXERCISE].sets).sort()).toEqual(["1", "2", "3", "4"]);
    expect((await counter()).applied).toBe(4);
    const shard = await shardOf(UID_A, a);
    for (const id of [a, b, c]) expect(shard.e[fenceKeyOf(id)][0]).toBe("C");
    for (const id of [a, b, c]) expect((await receipt(id)).status).toBe("COMMITTED");
  });
});
