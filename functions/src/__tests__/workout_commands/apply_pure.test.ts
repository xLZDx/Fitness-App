/**
 * Slice V0: the pure and pre-read parts of the apply (OFFLINE_COMMAND_PROTOCOL.md 4.1, 4.2 steps 1
 * and 2, 4.4, 4.5). The Firestore dependency handed to these tests THROWS on any use, so a passing
 * test proves that the refusal happened before any read or write.
 */
import { HttpsError } from "firebase-functions/v2/https";
import {
  counterPath,
  handleSubmitWorkoutCommands,
  parseSubmitRequest,
  policyGate,
  policyPath,
  prepareItem,
  receiptPath,
  submitWorkoutCommands,
  typedSessionPath,
  workoutCommandsEnabled,
  type ApplyDeps,
} from "../../workout_commands/apply";
import { LIMITS_V1, RESULT_CLASS, stopsBatch, type ResultCode } from "../../workout_commands/types";
import { DEVICE, SESSION, UID_A, UID_B, canon, envelopeOf, opIdOf, payloadOf, sha256Hex } from "./support";

const touched: string[] = [];
const noTouchDeps: ApplyDeps = {
  firestore: () => {
    touched.push("firestore");
    throw new Error("Firestore must not be touched");
  },
  nowMs: () => 1_792_000_000_000,
};
beforeEach(() => {
  touched.length = 0;
  jest.spyOn(console, "error").mockImplementation(() => undefined);
  jest.spyOn(console, "info").mockImplementation(() => undefined);
});
afterEach(() => jest.restoreAllMocks());

describe("policyGate (4.2 step 2, table 8.2)", () => {
  test.each<[string, Record<string, unknown> | undefined, string | undefined, ResultCode | null]>([
    ["absent policy", undefined, DEVICE, "MIGRATION_HOLD"],
    ["SERVER_ONLY", { migrationState: "SERVER_ONLY" }, undefined, null],
    ["SEALED", { migrationState: "SEALED" }, undefined, null],
    ["SERVER_ONLY but sendingPaused", { migrationState: "SERVER_ONLY", sendingPaused: true }, DEVICE, "MIGRATION_HOLD"],
    ["SEALED but sendingPaused", { migrationState: "SEALED", sendingPaused: true }, DEVICE, "MIGRATION_HOLD"],
    ["DELETING", { migrationState: "DELETING" }, DEVICE, "ACCOUNT_DELETING"],
    ["DELETING and paused", { migrationState: "DELETING", sendingPaused: true }, DEVICE, "ACCOUNT_DELETING"],
    ["LEGACY_ONLY", { migrationState: "LEGACY_ONLY" }, DEVICE, "MIGRATION_HOLD"],
    ["unknown state", { migrationState: "WHATEVER" }, DEVICE, "MIGRATION_HOLD"],
    ["no migrationState field", {}, DEVICE, "MIGRATION_HOLD"],
    ["DRAIN OPEN acked device", { migrationState: "DRAIN", drainPhase: "OPEN", drainedDevices: { [DEVICE]: 1 } }, DEVICE, "MIGRATION_HOLD"],
    ["DRAIN OPEN device-id substitution (B claims A's acknowledged id)", { migrationState: "DRAIN", drainPhase: "OPEN", drainedDevices: { deviceA: 1 } }, "deviceA", "MIGRATION_HOLD"],
    ["DRAIN OPEN other device", { migrationState: "DRAIN", drainPhase: "OPEN", drainedDevices: { other: 1 } }, DEVICE, "MIGRATION_HOLD"],
    ["DRAIN OPEN no device id", { migrationState: "DRAIN", drainPhase: "OPEN", drainedDevices: { [DEVICE]: 1 } }, undefined, "MIGRATION_HOLD"],
    ["DRAIN CLOSED acked device", { migrationState: "DRAIN", drainPhase: "CLOSED", drainedDevices: { [DEVICE]: 1 } }, DEVICE, "MIGRATION_HOLD"],
    ["DRAIN without phase", { migrationState: "DRAIN", drainedDevices: { [DEVICE]: 1 } }, DEVICE, "MIGRATION_HOLD"],
    ["DRAIN OPEN without devices", { migrationState: "DRAIN", drainPhase: "OPEN" }, DEVICE, "MIGRATION_HOLD"],
    ["DRAIN OPEN devices null", { migrationState: "DRAIN", drainPhase: "OPEN", drainedDevices: null }, DEVICE, "MIGRATION_HOLD"],
    ["DRAIN OPEN paused", { migrationState: "DRAIN", drainPhase: "OPEN", sendingPaused: true, drainedDevices: { [DEVICE]: 1 } }, DEVICE, "MIGRATION_HOLD"],
    ["DRAIN OPEN prototype key 'toString'", { migrationState: "DRAIN", drainPhase: "OPEN", drainedDevices: {} }, "toString", "MIGRATION_HOLD"],
  ])("%s", (_n, policy, device, expected) => {
    expect(policyGate(policy, device)).toBe(expected);
  });
});

describe("feature flag", () => {
  const saved = process.env.WORKOUT_COMMANDS_ENABLED;
  afterEach(() => {
    if (saved === undefined) delete process.env.WORKOUT_COMMANDS_ENABLED;
    else process.env.WORKOUT_COMMANDS_ENABLED = saved;
  });

  test.each([[undefined, false], ["", false], ["false", false], ["1", false], ["TRUE", false], ["true ", false], ["true", true]])(
    "WORKOUT_COMMANDS_ENABLED=%p -> %p",
    (value, expected) => {
      if (value === undefined) delete process.env.WORKOUT_COMMANDS_ENABLED;
      else process.env.WORKOUT_COMMANDS_ENABLED = value;
      expect(workoutCommandsEnabled()).toBe(expected);
    },
  );

  const call = (req: unknown) => (submitWorkoutCommands as unknown as { run: (r: unknown) => Promise<unknown> }).run(req);

  test("flag off (default): a signed-in call gets failed-precondition feature-disabled", async () => {
    delete process.env.WORKOUT_COMMANDS_ENABLED;
    const env = envelopeOf(payloadOf(UID_A, "ff"));
    await expect(call({ auth: { uid: UID_A }, data: { sessionId: SESSION, items: [env] } })).rejects.toMatchObject({
      code: "failed-precondition",
      message: "feature-disabled",
    });
  });

  test("an unauthenticated call is refused before the flag is read", async () => {
    process.env.WORKOUT_COMMANDS_ENABLED = "true";
    await expect(call({ data: { sessionId: SESSION, items: [] } })).rejects.toMatchObject({ code: "unauthenticated" });
  });
});

describe("parseSubmitRequest (4.1, limits 2.5)", () => {
  const env = envelopeOf(payloadOf(UID_A, "r"));

  test("accepts 1 and exactly 25 items", () => {
    expect(parseSubmitRequest({ sessionId: SESSION, items: [env] }).items).toHaveLength(1);
    expect(parseSubmitRequest({ sessionId: SESSION, items: Array(25).fill(env) }).items).toHaveLength(25);
    expect(LIMITS_V1.maxBatchItems).toBe(25);
  });

  test.each<[string, unknown]>([
    ["26 items", { sessionId: SESSION, items: Array(26).fill(env) }],
    ["0 items", { sessionId: SESSION, items: [] }],
    ["items not an array", { sessionId: SESSION, items: env }],
    ["missing items", { sessionId: SESSION }],
    ["missing sessionId", { items: [env] }],
    ["sessionId with space", { sessionId: "a b", items: [env] }],
    ["sessionId of 129 chars", { sessionId: "s".repeat(129), items: [env] }],
    ["sessionId number", { sessionId: 5, items: [env] }],
    ["null body", null],
    ["string body", "x"],
  ])("invalid-argument for %s", (_n, data) => {
    expect(() => parseSubmitRequest(data)).toThrow(HttpsError);
    try {
      parseSubmitRequest(data);
    } catch (e) {
      expect((e as HttpsError).code).toBe("invalid-argument");
      expect((e as HttpsError).message).toBe("invalid_request");
    }
  });
});

describe("prepareItem (4.2 step 1)", () => {
  const good = () => envelopeOf(payloadOf(UID_A, "p"));

  test("control: a valid envelope yields an item with the recomputed hash", () => {
    const r = prepareItem(UID_A, SESSION, good());
    expect("item" in r).toBe(true);
    if ("item" in r) {
      expect(r.item.payloadHash).toBe(good().payloadHash);
      expect(r.item.deviceInstallId).toBe(DEVICE);
      expect(r.item.writerProof).toBe(good().writerProof);
    }
  });

  const refusal = (r: ReturnType<typeof prepareItem>) => {
    if (!("refusal" in r)) throw new Error("expected refusal");
    return r.refusal;
  };

  test("UID_MISMATCH carries the operation id, class C4", () => {
    const p = payloadOf(UID_B, "um");
    const r = refusal(prepareItem(UID_A, SESSION, envelopeOf(p)));
    expect(r).toMatchObject({ code: "UID_MISMATCH", resultClass: "C4", operationId: p.operationId });
  });

  test("ID_UID_MISMATCH when the id tag belongs to someone else", () => {
    const p = payloadOf(UID_A, "iu", { operationId: opIdOf(UID_B, "iu") });
    expect(refusal(prepareItem(UID_A, SESSION, envelopeOf(p)))).toMatchObject({ code: "ID_UID_MISMATCH", resultClass: "C4" });
  });

  test("UID_MISMATCH wins over ID_UID_MISMATCH when both apply", () => {
    const p = payloadOf(UID_B, "both", { operationId: opIdOf(UID_B, "both") });
    // payload.uid = B (!= auth A) and the tag is B's: UID check is first
    expect(refusal(prepareItem(UID_A, SESSION, envelopeOf(p))).code).toBe("UID_MISMATCH");
  });

  test("hash mismatch (one digit flipped) is INVALID_PAYLOAD", () => {
    const e = good();
    const flipped = { ...e, payloadHash: (e.payloadHash[0] === "0" ? "1" : "0") + e.payloadHash.slice(1) };
    expect(refusal(prepareItem(UID_A, SESSION, flipped))).toMatchObject({ code: "INVALID_PAYLOAD", resultClass: "C4" });
  });

  test("hash of a different payload (altered under the same operationId) is INVALID_PAYLOAD", () => {
    const base = payloadOf(UID_A, "alt");
    const altered = payloadOf(UID_A, "alt", { body: { actualReps: 9 } });
    const e = { ...envelopeOf(altered), payloadHash: sha256Hex(canon(base)) };
    expect(refusal(prepareItem(UID_A, SESSION, e)).code).toBe("INVALID_PAYLOAD");
  });

  test("upper-case hash hex is INVALID_PAYLOAD without an operation id", () => {
    const e = good();
    const r = refusal(prepareItem(UID_A, SESSION, { ...e, payloadHash: e.payloadHash.toUpperCase() }));
    expect(r).toMatchObject({ code: "INVALID_PAYLOAD", operationId: null });
  });

  test("ID_SESSION_MISMATCH when the request session differs", () => {
    expect(refusal(prepareItem(UID_A, "day_other", good())).code).toBe("ID_SESSION_MISMATCH");
  });

  test.each<[string, unknown]>([
    ["null envelope", null],
    ["array envelope", []],
    ["missing payloadBytes", { payloadHash: "a".repeat(64), writerProof: "p" }],
    ["missing writerProof", { ...envelopeOf(payloadOf(UID_A, "q")), writerProof: undefined }],
    ["empty writerProof", { ...envelopeOf(payloadOf(UID_A, "q")), writerProof: "" }],
    ["writerProof of 257 chars", { ...envelopeOf(payloadOf(UID_A, "q")), writerProof: "p".repeat(257) }],
    ["writerProof not a string", { ...envelopeOf(payloadOf(UID_A, "q")), writerProof: 5 }],
    ["non-canonical bytes", (() => { const t = JSON.stringify(payloadOf(UID_A, "q"), null, 1); return { payloadBytes: t, payloadHash: sha256Hex(t), writerProof: "p" }; })()],
  ])("INVALID_PAYLOAD for %s", (_n, env) => {
    const r = prepareItem(UID_A, SESSION, env);
    expect("refusal" in r && r.refusal.code).toBe("INVALID_PAYLOAD");
  });

  test("an oversized or empty deviceInstallId is dropped, not trusted", () => {
    for (const dev of ["", "d".repeat(129), 5 as unknown as string]) {
      const r = prepareItem(UID_A, SESSION, { ...good(), deviceInstallId: dev });
      expect("item" in r && r.item.deviceInstallId).toBeUndefined();
    }
  });
});

describe("handleSubmitWorkoutCommands before any read", () => {
  test("a batch of refusals never touches Firestore and keeps order and count", async () => {
    const wrongUid = envelopeOf(payloadOf(UID_B, "w1"));
    const bad = { ...envelopeOf(payloadOf(UID_A, "w2")), payloadHash: "0".repeat(64) };
    const wrongTag = envelopeOf(payloadOf(UID_A, "w3", { operationId: opIdOf(UID_B, "w3") }));
    const res = await handleSubmitWorkoutCommands(noTouchDeps, UID_A, { sessionId: SESSION, items: [wrongUid, bad, wrongTag, null] });
    expect(res.results.map((r) => r.code)).toEqual(["UID_MISMATCH", "INVALID_PAYLOAD", "ID_UID_MISMATCH", "INVALID_PAYLOAD"]);
    expect(touched).toEqual([]);
    expect(res.serverNowMs).toBe(1_792_000_000_000);
    for (const r of res.results) expect(r.resultClass).toBe("C4");
  });

  test("a transaction failure becomes UNAVAILABLE (C6) and stops the batch with NOT_ATTEMPTED (C7)", async () => {
    const e1 = envelopeOf(payloadOf(UID_A, "f1"));
    const e2 = envelopeOf(payloadOf(UID_A, "f2", { logicalSetId: `${SESSION}:ex_bench_press:2`, body: { setId: "set_0002" } }));
    const invalid = null;
    const res = await handleSubmitWorkoutCommands(noTouchDeps, UID_A, { sessionId: SESSION, items: [e1, e2, invalid] });
    expect(res.results.map((r) => r.code)).toEqual(["UNAVAILABLE", "NOT_ATTEMPTED", "NOT_ATTEMPTED"]);
    expect(res.results[0].operationId).toBe(JSON.parse(e1.payloadBytes).operationId);
    expect(res.results[1].operationId).toBeNull();
    expect(res.results[0].resultClass).toBe("C6");
    expect(res.results[1].resultClass).toBe("C7");
  });

  test("a leading refusal does not stop the batch (spec 4.5): the next item is still attempted", async () => {
    const bad = null;
    const e = envelopeOf(payloadOf(UID_A, "g1"));
    const res = await handleSubmitWorkoutCommands(noTouchDeps, UID_A, { sessionId: SESSION, items: [bad, e] });
    expect(res.results[0].code).toBe("INVALID_PAYLOAD");
    expect(res.results[1].code).toBe("UNAVAILABLE"); // attempted (and failed because the dependency throws)
    expect(touched.length).toBeGreaterThan(0);
  });

  test("an invalid request throws invalid-argument without touching Firestore", async () => {
    await expect(handleSubmitWorkoutCommands(noTouchDeps, UID_A, { sessionId: SESSION, items: [] })).rejects.toBeInstanceOf(HttpsError);
    expect(touched).toEqual([]);
  });
});

describe("result classes (4.4) and batch stop rule (4.5)", () => {
  test.each<[ResultCode, string, boolean]>([
    ["COMMITTED", "C1", false],
    ["ALREADY_COMMITTED", "C2", false],
    ["ALREADY_COMMITTED_DETAIL_EXPIRED", "C2", false],
    ["SUPERSEDED", "C2", false],
    ["ALREADY_REJECTED", "C3", false],
    ["DUPLICATE_LOGICAL_SET", "C3", false],
    ["SESSION_DELETED_ELSEWHERE", "C3", false],
    ["GENERATION_MISMATCH", "C3", false],
    ["SESSION_CLOSED", "C3", false],
    ["DEPENDENCY_REJECTED", "C3", false],
    ["ID_PAYLOAD_MISMATCH", "C4", false],
    ["UID_MISMATCH", "C4", false],
    ["ID_UID_MISMATCH", "C4", false],
    ["ID_SESSION_MISMATCH", "C4", false],
    ["INVALID_PAYLOAD", "C4", false],
    ["DEPENDENCY_PENDING", "C5a", false],
    ["MIGRATION_HOLD", "C5b", true],
    ["ACCOUNT_DELETING", "C5b", true],
    ["RATE_LIMITED", "C5b", true],
    ["NOT_WRITER", "C5b", true],
    ["SESSION_COMMAND_LIMIT", "C5b", true],
    ["FENCE_SHARD_FULL", "C6", true],
    ["UNAVAILABLE", "C6", true],
    ["NOT_ATTEMPTED", "C7", false],
  ])("%s is %s, stops batch: %s", (code, cls, stops) => {
    expect(RESULT_CLASS[code]).toBe(cls);
    expect(stopsBatch(code)).toBe(stops);
  });
});

describe("deployed callable options", () => {
  test("runs as the data service account (fn-data) in europe-west1, not the AI runtime account", () => {
    const ep = (submitWorkoutCommands as unknown as { __endpoint: { serviceAccountEmail?: string; region?: string[] } }).__endpoint;
    expect(ep.serviceAccountEmail).toMatch(/^fn-data@.+.iam.gserviceaccount.com$/);
    expect(ep.serviceAccountEmail).not.toContain("fn-ai-runtime");
    expect(ep.region).toEqual(["europe-west1"]);
  });
});

describe("document paths", () => {
  test("paths use the carved-out collection names", () => {
    expect(policyPath("u")).toBe("users/u/workout_command_policy/current");
    expect(receiptPath("u", "op")).toBe("users/u/workout_command_receipts/op");
    expect(counterPath("u", "2026-10-23")).toBe("users/u/workout_command_counters/2026-10-23");
    expect(typedSessionPath("u", "s")).toBe("users/u/workout_typed_sessions/s");
  });
});
