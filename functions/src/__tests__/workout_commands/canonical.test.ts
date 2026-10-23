/**
 * Slice V0, server half: canonical JSON, hash binding, uidTag/operationId, payload validation and
 * the shared golden vectors (docs/v1/fixtures/workout_command_golden_vectors.json).
 * Oracles are literal constants or Node crypto computed in `support.ts`, never the code under test.
 */
import {
  CanonicalError,
  InvalidPayloadError,
  canonicalJson,
  hashCanonical,
  isLowerHex64,
  isOperationId,
  logicalSetIdOf,
  operationIdMatchesUid,
  parseAndHashPayloadText,
  parseCommandPayload,
  payloadHashOf,
  setIdOf,
  setIndexOf,
  uidTagOf,
} from "../../workout_commands/canonical";
import { HttpsError } from "firebase-functions/v2/https";
import { parseSubmitRequest, prepareItem } from "../../workout_commands/apply";
import {
  SESSION,
  UID_A,
  UID_B,
  canon,
  envelopeOf,
  loadVectors,
  opIdOf,
  payloadOf,
  sha256Hex,
  tagOf,
  type Over,
} from "./support";

describe("canonicalJson", () => {
  test("sorts keys recursively and keeps array order, no whitespace", () => {
    expect(canonicalJson({ b: 1, a: { d: [3, 1, 2], c: null }, A: true })).toBe('{"A":true,"a":{"c":null,"d":[3,1,2]},"b":1}');
  });

  test("orders keys by UTF-16 code unit, not by locale", () => {
    expect(canonicalJson({ "é": 1, z: 2, B: 3, _: 4, a: 5 })).toBe('{"B":3,"_":4,"a":5,"z":2,"é":1}');
  });

  test("strings: raw UTF-8 for non-ASCII, escapes for quote, backslash and control characters", () => {
    expect(canonicalJson("é日😀")).toBe('"é日😀"');
    expect(canonicalJson('a"b\\c\n\t\u0001\u007f ')).toBe('"a\\"b\\\\c\\n\\t\\u0001\u007f "');
  });

  test("negative zero is written 0; safe-integer extremes are exact", () => {
    expect(canonicalJson(-0)).toBe("0");
    expect(canonicalJson(Number.MAX_SAFE_INTEGER)).toBe("9007199254740991");
    expect(canonicalJson(Number.MIN_SAFE_INTEGER)).toBe("-9007199254740991");
  });

  test.each([
    ["fraction", 1.5],
    ["NaN", NaN],
    ["Infinity", Infinity],
    ["above safe integer", 2 ** 53],
    ["bigint", BigInt(1)],
    ["undefined", undefined],
    ["function", () => 1],
    ["symbol", Symbol("x")],
    ["Date", new Date(0)],
    ["Map", new Map()],
    ["undefined member", { a: undefined }],
    ["nested fraction", { a: [{ b: 0.1 }] }],
  ])("refuses %s", (_name, value) => {
    expect(() => canonicalJson(value)).toThrow(CanonicalError);
  });

  test("hash is SHA-256 hex of the canonical bytes (literal oracle for {})", () => {
    expect(hashCanonical({})).toBe("44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a");
  });

  test("agrees with the independent implementation on a full payload with unicode", () => {
    const p = payloadOf("uid-é-日😀", "x");
    expect(canonicalJson(p)).toBe(canon(p));
    expect(payloadHashOf(p)).toBe(sha256Hex(canon(p)));
  });
});

describe("uidTag and operation ids", () => {
  test("literal tags (cross-checked with Python hashlib)", () => {
    expect(uidTagOf(UID_A)).toBe("-ks1E2RW");
    expect(uidTagOf(UID_B)).toBe("mw0fxScC");
    expect(uidTagOf(UID_A)).toBe(tagOf(UID_A));
  });

  test("operationId is exactly 30 base64url characters", () => {
    const ok = opIdOf(UID_A, "s");
    expect(ok).toHaveLength(30);
    expect(isOperationId(ok)).toBe(true);
    expect(isOperationId(ok.slice(1))).toBe(false);
    expect(isOperationId(ok + "A")).toBe(false);
    expect(isOperationId(ok.slice(0, 29) + "+")).toBe(false);
    expect(isOperationId(ok.slice(0, 29) + "=")).toBe(false);
    expect(isOperationId(42)).toBe(false);
  });

  test("operationIdMatchesUid binds the tag to the uid", () => {
    const id = opIdOf(UID_A, "s");
    expect(operationIdMatchesUid(id, UID_A)).toBe(true);
    expect(operationIdMatchesUid(id, UID_B)).toBe(false);
  });

  test("logicalSetId, setId and setIndex derivations", () => {
    expect(logicalSetIdOf("s", "e", 7)).toBe("s:e:7");
    expect(setIdOf(1)).toBe("set_0001");
    expect(setIdOf(1000)).toBe("set_1000");
    expect(setIndexOf(payloadOf(UID_A, "i", { logicalSetId: `${SESSION}:ex_bench_press:12`, body: { setId: "set_0012" } }))).toBe(12);
  });

  test("isLowerHex64 refuses upper case, short, long and non-strings", () => {
    const h = "a".repeat(64);
    expect(isLowerHex64(h)).toBe(true);
    expect(isLowerHex64(h.toUpperCase())).toBe(false);
    expect(isLowerHex64(h.slice(1))).toBe(false);
    expect(isLowerHex64(h + "a")).toBe(false);
    expect(isLowerHex64(5)).toBe(false);
  });
});

describe("parseCommandPayload", () => {
  const valid = () => JSON.parse(JSON.stringify(payloadOf(UID_A, "v")));

  test("control: the valid payload is accepted and returned unchanged", () => {
    expect(parseCommandPayload(valid())).toEqual(valid());
  });

  const mutate = (fn: (p: any) => void) => {
    const p = valid();
    fn(p);
    return p;
  };

  const rejected: Array<[string, (p: any) => void]> = [
    ["unknown top-level key", (p) => { p.extra = 1; }],
    ["missing top-level key", (p) => { delete p.seq; }],
    ["protocolVersion 1", (p) => { p.protocolVersion = 1; }],
    ["hashVersion 1", (p) => { p.hashVersion = 1; }],
    ["limitsVersion 2", (p) => { p.limitsVersion = 2; }],
    ["operationId 29 chars", (p) => { p.operationId = p.operationId.slice(1); }],
    ["operationId with '+'", (p) => { p.operationId = p.operationId.slice(0, 29) + "+"; }],
    ["empty uid", (p) => { p.uid = ""; }],
    ["uid of 129 chars", (p) => { p.uid = "u".repeat(129); }],
    ["uid not a string", (p) => { p.uid = 5; }],
    ["sessionId with space", (p) => { p.sessionId = "a b"; }],
    ["sessionId of 129 chars", (p) => { p.sessionId = "s".repeat(129); }],
    ["originDeviceInstallId empty", (p) => { p.originDeviceInstallId = ""; }],
    ["sessionGeneration 0", (p) => { p.sessionGeneration = 0; }],
    ["sessionGeneration 1000001", (p) => { p.sessionGeneration = 1_000_001; }],
    ["sessionGeneration fraction", (p) => { p.sessionGeneration = 1.5; }],
    ["acceptedEpoch -1", (p) => { p.acceptedEpoch = -1; }],
    ["acceptedEpoch as string", (p) => { p.acceptedEpoch = "0"; }],
    ["seq 0", (p) => { p.seq = 0; }],
    ["seq 2147483648", (p) => { p.seq = 2_147_483_648; }],
    ["dependsOn not an array", (p) => { p.dependsOn = "x"; }],
    ["dependsOn with 4 entries", (p) => { p.dependsOn = ["a", "b", "c", "d"].map((s) => opIdOf(UID_A, s)).sort(); }],
    ["dependsOn entry malformed", (p) => { p.dependsOn = ["short"]; }],
    ["dependsOn descending", (p) => { p.dependsOn = [opIdOf(UID_A, "a"), opIdOf(UID_A, "b")].sort().reverse(); }],
    ["dependsOn duplicate", (p) => { const d = opIdOf(UID_A, "a"); p.dependsOn = [d, d]; }],
    ["dependsOn contains itself", (p) => { p.dependsOn = [p.operationId]; }],
    ["exerciseId with colon", (p) => { p.exerciseId = "a:b"; }],
    ["operation SetDifficulty", (p) => { p.operation = "SetDifficulty"; }],
    ["operation AddEligibleExercise", (p) => { p.operation = "AddEligibleExercise"; }],
    ["body missing", (p) => { p.body = null; }],
    ["body array", (p) => { p.body = []; }],
    ["body unknown key", (p) => { p.body.extra = 1; }],
    ["body missing key", (p) => { delete p.body.loadGrams; }],
    ["body.mode CORRECT", (p) => { p.body.mode = "CORRECT"; }],
    ["body.source with space", (p) => { p.body.source = "a b"; }],
    ["body.source of 33 chars", (p) => { p.body.source = "s".repeat(33); }],
    ["body.source empty", (p) => { p.body.source = ""; }],
    ["body.setId does not match the index", (p) => { p.body.setId = "set_0002"; }],
    ["body.setId not a string", (p) => { p.body.setId = 1; }],
    ["performedConfirmed as string", (p) => { p.body.performedConfirmed = "true"; }],
    ["actualReps 1001", (p) => { p.body.actualReps = 1001; }],
    ["actualReps -1", (p) => { p.body.actualReps = -1; }],
    ["actualReps fraction", (p) => { p.body.actualReps = 8.5; }],
    ["targetReps 1001", (p) => { p.body.targetReps = 1001; }],
    ["loadGrams 1000001", (p) => { p.body.loadGrams = 1_000_001; }],
    ["performedAtClientMs -1", (p) => { p.body.performedAtClientMs = -1; }],
    ["performedAtClientMs above 2^53-1", (p) => { p.body.performedAtClientMs = 2 ** 53; }],
    ["logicalSetId wrong session", (p) => { p.logicalSetId = `other:${p.exerciseId}:1`; }],
    ["logicalSetId wrong exercise", (p) => { p.logicalSetId = `${p.sessionId}:ex_other:1`; }],
    ["logicalSetId index 0", (p) => { p.logicalSetId = `${p.sessionId}:${p.exerciseId}:0`; p.body.setId = "set_0000"; }],
    ["logicalSetId index 01", (p) => { p.logicalSetId = `${p.sessionId}:${p.exerciseId}:01`; }],
    ["logicalSetId index 1001", (p) => { p.logicalSetId = `${p.sessionId}:${p.exerciseId}:1001`; p.body.setId = "set_1001"; }],
    ["logicalSetId index 10000", (p) => { p.logicalSetId = `${p.sessionId}:${p.exerciseId}:10000`; p.body.setId = "set_10000"; }],
    ["logicalSetId null", (p) => { p.logicalSetId = null; }],
    ["sessionInit not an object", (p) => { p.sessionInit = "x"; }],
    ["sessionInit unknown key", (p) => { p.sessionInit.extra = 1; }],
    ["sessionInit titleKey free text", (p) => { p.sessionInit.titleKey = "My workout"; }],
    ["sessionInit titleKey 'day:' empty id", (p) => { p.sessionInit.titleKey = "day:"; }],
    ["sessionInit titleKey id of 65 chars", (p) => { p.sessionInit.titleKey = "day:" + "a".repeat(65); }],
    ["sessionInit titleKey non-ASCII", (p) => { p.sessionInit.titleKey = "day:übung"; }],
    ["sessionInit dayId invalid", (p) => { p.sessionInit.dayId = "a b"; }],
    ["sessionInit startedAtClientMs negative", (p) => { p.sessionInit.startedAtClientMs = -1; }],
  ];

  test.each(rejected)("rejects: %s", (_name, fn) => {
    expect(() => parseCommandPayload(mutate(fn))).toThrow(InvalidPayloadError);
  });

  test.each([null, 5, "x", [], undefined])("rejects a non-object payload (%p)", (raw) => {
    expect(() => parseCommandPayload(raw)).toThrow(InvalidPayloadError);
  });

  const accepted: Array<[string, Over]> = [
    ["sessionInit null", { sessionInit: null }],
    ["titleKey default", { sessionInit: { titleKey: "default", dayId: null, startedAtClientMs: 0 } }],
    ["titleKey plan:", { sessionInit: { titleKey: "plan:p_1", dayId: null, startedAtClientMs: 1 } }],
    ["titleKey id of 64 chars", { sessionInit: { titleKey: "day:" + "a".repeat(64), dayId: null, startedAtClientMs: 1 } }],
    ["three sorted dependsOn", { sessionInit: null, dependsOn: ["a", "b", "c"].map((s) => opIdOf(UID_A, s)).sort() }],
    ["set index 1000", { logicalSetId: `${SESSION}:ex_bench_press:1000`, body: { setId: "set_1000" } }],
    ["nullable body fields null", { body: { actualReps: null, targetReps: null, loadGrams: null } }],
    ["unicode uid of 128 units", { uid: "é".repeat(128) }],
    ["maximal integers", { sessionGeneration: 1_000_000, acceptedEpoch: 1_000_000, seq: 2_147_483_647, body: { actualReps: 1000, targetReps: 1000, loadGrams: 1_000_000, performedAtClientMs: Number.MAX_SAFE_INTEGER } }],
  ];
  test.each(accepted)("accepts: %s", (_name, over) => {
    const p = payloadOf(UID_A, "ok", over);
    expect(parseCommandPayload(JSON.parse(JSON.stringify(p)))).toEqual(p);
  });
});

describe("parseAndHashPayloadText (hash binding)", () => {
  const p = payloadOf(UID_A, "h");
  const text = canon(p);

  test("returns the payload and the hash of the exact received bytes", () => {
    const r = parseAndHashPayloadText(text);
    expect(r.payload).toEqual(p);
    expect(r.payloadHash).toBe(sha256Hex(text));
  });

  test("hash covers non-ASCII uid as UTF-8 bytes", () => {
    const u = payloadOf("uid-é-日😀", "h");
    const t = canon(u);
    expect(parseAndHashPayloadText(t).payloadHash).toBe(sha256Hex(t));
    expect(Buffer.byteLength(t, "utf8")).toBeGreaterThan(t.length);
  });

  test("changing any one value changes the hash (hash binds operationId, uid, sessionId, origin)", () => {
    const base = parseAndHashPayloadText(text).payloadHash;
    const variants: Over[] = [
      { operationId: opIdOf(UID_A, "other") },
      { uid: UID_B },
      { sessionId: "day_other", logicalSetId: "day_other:ex_bench_press:1" },
      { originDeviceInstallId: "dev_BBBB2222" },
      { body: { actualReps: 9 } },
    ];
    const seen = new Set([base]);
    for (const v of variants) {
      const h = payloadHashOf(payloadOf(UID_A, "h", v));
      expect(seen.has(h)).toBe(false);
      seen.add(h);
    }
  });

  test.each([
    ["empty text", ""],
    ["invalid JSON", "{"],
    ["JSON null", "null"],
    ["BOM prefix", "﻿" + text],
    ["leading space", " " + text],
    ["trailing newline", text + "\n"],
    ["pretty printed", JSON.stringify(JSON.parse(text), null, 2)],
    ["unsorted keys", JSON.stringify(Object.fromEntries(Object.entries(JSON.parse(text)).reverse()))],
    ["duplicate key", text.replace('"seq":1', '"seq":1,"seq":1')],
    ["fraction written 1.0", text.replace('"seq":1', '"seq":1.0')],
    ["exponent", text.replace('"loadGrams":60000', '"loadGrams":6e4')],
    ["escaped non-ASCII where raw is canonical", canon(payloadOf("éx", "h")).replace("é", "\\u00e9")],
    ["size above 8192 chars", text.slice(0, -1) + ' '.repeat(9000) + "}"],
  ])("INVALID_PAYLOAD for %s", (_name, t) => {
    expect(() => parseAndHashPayloadText(t)).toThrow(InvalidPayloadError);
  });

  test("non-string input is refused", () => {
    expect(() => parseAndHashPayloadText(undefined as unknown as string)).toThrow(InvalidPayloadError);
  });
});

describe("golden vectors (shared with the Dart canonicalizer)", () => {
  const vectors = loadVectors();

  test("fixture has the required spread", () => {
    expect(vectors.length).toBeGreaterThanOrEqual(6);
    const names = vectors.map((v) => v.name);
    expect(new Set(names).size).toBe(names.length);
    for (const needle of ["minimal", "unicode", "ordering", "boundaries", "same_operation_id", "uid_mismatch"]) {
      expect(names.some((n) => n.includes(needle))).toBe(true);
    }
  });

  test.each(vectors.map((v) => [v.name, v] as const))("%s", (_name, v) => {
    // 1. hash of the literal text, by Node crypto (independent of canonical.ts)
    expect(sha256Hex(v.payloadText)).toBe(v.payloadHash);
    expect(tagOf(v.authUid)).toBe(v.uidTag);
    expect(uidTagOf(v.authUid)).toBe(v.uidTag);
    // 2. canonicalizer reproduces the recorded text from the object
    if (v.payloadObject !== null) {
      expect(canonicalJson(v.payloadObject)).toBe(v.canonicalText);
      expect(canon(v.payloadObject)).toBe(v.canonicalText);
      expect(hashCanonical(v.payloadObject)).toBe(sha256Hex(v.canonicalText as string));
    }
    // 3. the server's envelope validation gives the recorded outcome
    const r = prepareItem(v.authUid, v.requestSessionId, {
      payloadBytes: v.payloadText,
      payloadHash: v.sentPayloadHash ?? v.payloadHash,
      writerProof: "p",
    });
    if (v.expectedPrepare === "OK") {
      expect("item" in r).toBe(true);
      if ("item" in r) expect(r.item.payloadHash).toBe(v.payloadHash);
    } else {
      expect("refusal" in r).toBe(true);
      if ("refusal" in r) expect(r.refusal.code).toBe(v.expectedPrepare);
    }
  });

  test("the altered-payload pair shares the operationId and differs in hash", () => {
    const a = vectors.find((v) => v.name === "same_operation_id_original")!;
    const b = vectors.find((v) => v.name === "same_operation_id_altered_reps")!;
    expect((a.payloadObject as any).operationId).toBe((b.payloadObject as any).operationId);
    expect(a.payloadHash).not.toBe(b.payloadHash);
  });

  test("the same content minted for another user has a different hash and operationId", () => {
    const a = vectors.find((v) => v.name === "minimal_complete_set_append_with_session_init")!;
    const b = vectors.find((v) => v.name === "different_uid_same_content_different_hash")!;
    expect(a.payloadHash).not.toBe(b.payloadHash);
    expect((a.payloadObject as any).operationId).not.toBe((b.payloadObject as any).operationId);
  });

  test("key-ordering vector: the recorded text is sorted although the object was given reversed", () => {
    const v = vectors.find((x) => x.name === "key_ordering_stress_reverse_input_order")!;
    expect(Object.keys(v.payloadObject!)[0]).toBe("uid");
    expect((v.canonicalText as string).startsWith('{"acceptedEpoch":0,"body":{"actualReps":8')).toBe(true);
  });
});

describe("reserved ids and string edge cases (review round)", () => {
  const depId = (c: string) => { const b = opIdOf(UID_A, "dd"); return b.slice(0, 15) + c + b.slice(16); };

  test.each([
    ["sessionId __proto__", { sessionId: "__proto__", logicalSetId: "__proto__:ex_bench_press:1" }],
    ["sessionId __a__", { sessionId: "__a__", logicalSetId: "__a__:ex_bench_press:1" }],
    ["exerciseId __proto__", { exerciseId: "__proto__", logicalSetId: `${SESSION}:__proto__:1` }],
    ["exerciseId __a__", { exerciseId: "__a__", logicalSetId: `${SESSION}:__a__:1` }],
    ["originDeviceInstallId __x__", { originDeviceInstallId: "__x__" }],
    ["sessionInit.dayId __d__", { sessionInit: { titleKey: "default", dayId: "__d__", startedAtClientMs: 1 } }],
  ])("%s is rejected by the schema", (_n, over) => {
    expect(() => parseCommandPayload(JSON.parse(JSON.stringify(payloadOf(UID_A, "rs", over as Over))))).toThrow(InvalidPayloadError);
  });

  test("control: ids that only start or only end with underscores are accepted", () => {
    const p = payloadOf(UID_A, "rs2", { exerciseId: "__a", logicalSetId: `${SESSION}:__a:1` });
    expect(parseCommandPayload(JSON.parse(JSON.stringify(p)))).toEqual(p);
    const q = payloadOf(UID_A, "rs3", { exerciseId: "a__", logicalSetId: `${SESSION}:a__:1` });
    expect(parseCommandPayload(JSON.parse(JSON.stringify(q)))).toEqual(q);
  });

  test("isOperationId refuses a reserved-looking 30-character id", () => {
    expect(isOperationId("__" + "A".repeat(26) + "__")).toBe(false);
  });

  test("parseSubmitRequest: reserved request sessionId is invalid-argument; near-misses pass", () => {
    for (const sid of ["__proto__", "__a__", "____"]) {
      expect(() => parseSubmitRequest({ sessionId: sid, items: [{ x: 1 }] })).toThrow(HttpsError);
    }
    for (const sid of ["__a", "a__", "_a_", "_"]) {
      expect(parseSubmitRequest({ sessionId: sid, items: [{ x: 1 }] }).sessionId).toBe(sid);
    }
  });

  test("prepareItem answers INVALID_PAYLOAD for a reserved sessionId even when request and payload agree", () => {
    const p = payloadOf(UID_A, "r", { sessionId: "__proto__", logicalSetId: "__proto__:ex_bench_press:1" });
    const r = prepareItem(UID_A, "__proto__", envelopeOf(p));
    expect("refusal" in r && r.refusal.code).toBe("INVALID_PAYLOAD");
  });

  test("dependsOn is ordered by code unit: - < A < _ < a is accepted, - < _ < A is not", () => {
    const ok = (ids: string[]) => payloadOf(UID_A, "do", { sessionInit: null, dependsOn: ids });
    expect(parseCommandPayload(JSON.parse(JSON.stringify(ok([depId("-"), depId("A"), depId("_")]))))).toBeDefined();
    expect(parseCommandPayload(JSON.parse(JSON.stringify(ok([depId("A"), depId("_"), depId("a")]))))).toBeDefined();
    expect(() => parseCommandPayload(JSON.parse(JSON.stringify(ok([depId("-"), depId("_"), depId("A")]))))).toThrow(InvalidPayloadError);
  });

  test("-0 in the text is not canonical (INVALID_PAYLOAD); the canonicalizer never emits -0", () => {
    const t = canon(payloadOf(UID_A, "nz")).replace('"acceptedEpoch":0', '"acceptedEpoch":-0');
    expect(t).toContain('"acceptedEpoch":-0');
    expect(() => parseAndHashPayloadText(t)).toThrow(InvalidPayloadError);
    expect(canonicalJson({ a: -0 })).toBe('{"a":0}');
  });

  test("a RAW lone surrogate in the text is not canonical (INVALID_PAYLOAD)", () => {
    const lone = "a" + String.fromCharCode(0xd800) + "b";
    const t = canonicalJson(payloadOf("aXb", "ls")).split("aXb").join(lone);
    expect(t).toContain(String.fromCharCode(0xd800));
    expect(() => parseAndHashPayloadText(t)).toThrow(InvalidPayloadError);
  });

  test("an unpaired surrogate in a string or object key is refused by the canonicalizer and the escaped text is INVALID_PAYLOAD", () => {
    const lone = "a" + String.fromCharCode(0xd800) + "b";
    expect(() => canonicalJson(lone)).toThrow(CanonicalError);
    expect(() => canonicalJson({ [lone]: 1 })).toThrow(CanonicalError);
    expect(() => canonicalJson(payloadOf(lone, "ls2"))).toThrow(CanonicalError);
    const t = canonicalJson(payloadOf("aXb", "ls2")).split("aXb").join("a" + String.fromCharCode(92) + "ud800b");
    expect(() => parseAndHashPayloadText(t)).toThrow(InvalidPayloadError);
    // a well-formed surrogate PAIR stays valid
    expect(canonicalJson("😀")).toBe('"😀"');
  });
});
