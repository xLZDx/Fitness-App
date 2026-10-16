/**
 * S02-07 and S02-09 functions part: F29-F33, F69, F70 (export, download URLs, log hygiene),
 * F34-F37, F73, F74, F90, F93 (telemetry callable and closed schema).
 */
jest.mock("firebase-admin", () => require("./support/fakes").adminMock());
jest.mock("firebase-functions/logger", () => require("./support/fakes").loggerMock());

import * as fs from "fs";
import * as path from "path";
import * as logger from "firebase-functions/logger";
import { exportAccountData } from "../../account_export";
import { handleGetActivityStreamDownloadUrls } from "../../activity_streams/download_urls";
import {
  DEBUG_TELEMETRY_DROP_EVENT, TELEMETRY_OPTIONS, handleSendDebugTelemetry,
} from "../../activity_streams/telemetry";
import {
  TELEMETRY_COUNTER_MAX, TELEMETRY_MAX_BATCH_BYTES, TELEMETRY_SCHEMA, identityFromProvider, sanitizeTelemetryBatch,
} from "../../activity_streams/telemetry_schema";
import {
  ACT, ACT_2, DAY, MIN, T0, UID, UID_B, callReq, createWorld, expectHttpsError, fx, loggedText, releaseClock, resetAll,
  seedReady, store, streamPath, ts, uploadIdN, usageOf, useClock, validPayload, type World,
} from "./support/fakes";
import { commit, create, fullUpload, outcome, stage } from "./support/flow";
import { SEVEN } from "./support/seven";

let w: World;
const actId = (n: number): string => `act_${n.toString(16).padStart(40, "0")}`;
const exp = (data: unknown = {}, uid = UID): Promise<any> => (exportAccountData as any).run(callReq(data, uid));
const dl = (ids: unknown, uid = UID, provider = "password") => handleGetActivityStreamDownloadUrls(w.deps, uid, provider, { activityIds: ids, expectedUid: uid });

beforeEach(() => {
  resetAll();
  useClock(T0);
  w = createWorld();
});
afterEach(() => releaseClock());

function seedActivity(uid: string, id: string, startMs: number, extra: Record<string, unknown> = {}): void {
  store.set(`users/${uid}/activities/${id}`, { startUtc: ts(startMs), rev: 1, sport: "run", ...extra });
}

describe("F29/F31 export parity and isolation", () => {
  test("summary, stream index row (allow-listed) and settings are exported; no samples, no object path, no tombstone section; another user's rows absent", async () => {
    seedActivity(UID, ACT, T0 - DAY);
    seedActivity(UID_B, ACT_2, T0 - DAY);
    store.set(`users/${UID}/activity_streams/${ACT}`, {
      state: "stored", bytes: 123, kinds: ["gps"], expiresAt: ts(T0 + DAY), objectPath: streamPath(UID, ACT, "up_1"),
      contentSha256: "ab".repeat(32), lats: [51.5007], uploadId: "up_1",
    });
    store.set(`users/${UID_B}/activity_streams/${ACT_2}`, { state: "stored", bytes: 9, kinds: ["gps"] });
    store.set(`users/${UID}/activity_settings/main`, { streamRetentionDays: 365, settingsGeneration: 3 });
    store.set(`users/${UID}/activity_tombstones/${ACT_2}`, { deletedAt: ts(T0) });
    const res = await exp();
    expect(res.activities.map((r: any) => r.id)).toEqual([ACT]);
    expect(res.activityStreams).toEqual([{ id: ACT, state: "stored", bytes: 123, kinds: ["gps"], expiresAt: expect.anything() }]);
    expect(res.activitySettings).toMatchObject({ id: "main", streamRetentionDays: 365 });
    const text = JSON.stringify(res);
    for (const banned of ["lats", "51.5007", "objectPath", "streams/", "contentSha256", "activity_tombstones", ACT_2, "uploadId"]) expect(text).not.toContain(banned);
    expect(res.notes.join(" ")).toContain("heart-rate streams are on your device only");
  });
});

describe("F30 truncation", () => {
  test("2001 activity docs return 2000 rows, name activities in truncated and offer a continuation", async () => {
    for (let i = 1; i <= 2001; i++) seedActivity(UID, actId(i), T0 - i * 1000);
    const res = await exp();
    expect(res.activities).toHaveLength(2000);
    expect(res.truncated).toContain("activities");
    expect(res.paging.activities.hasMore).toBe(true);
    expect(res.notes.join(" ")).toContain("activities");
  });
});

describe("F70 worst-case sizing and paging", () => {
  test("2500 maximum-size rows: every response stays within 8 MiB, truncated names the trimmed section, the continuation returns every row exactly once", async () => {
    const pad = "p".repeat(6000);
    for (let i = 1; i <= 2500; i++) seedActivity(UID, actId(i), T0 - i * 1000, { notes: pad });
    const oneRow = JSON.stringify({ id: actId(1), startUtc: ts(0), rev: 1, sport: "run", notes: pad }).length;
    expect(oneRow * 2000).toBeGreaterThan(8 * 1024 * 1024); // arithmetic: the seed IS the worst case
    const first = await exp();
    expect(Buffer.byteLength(JSON.stringify(first))).toBeLessThanOrEqual(8 * 1024 * 1024);
    expect(first.truncated).toContain("activities");
    expect(first.paging.activities.hasMore).toBe(true);
    const ids: string[] = first.activities.map((r: any) => r.id);
    let cursor = first.paging.activities.nextCursor;
    let guard = 0;
    while (cursor && guard++ < 50) {
      const page = await exp({ cursors: { activities: cursor } });
      expect(Buffer.byteLength(JSON.stringify(page))).toBeLessThanOrEqual(8 * 1024 * 1024);
      ids.push(...page.activities.map((r: any) => r.id));
      cursor = page.paging.activities.hasMore ? page.paging.activities.nextCursor : null;
    }
    expect(ids).toHaveLength(2500);
    expect(new Set(ids).size).toBe(2500);
    expect(ids[0]).toBe(actId(1)); // newest first
    expect(ids[2499]).toBe(actId(2500));
  });
});

describe("F32/F69 download URLs", () => {
  function seedRow(id: string, state: string, uid = UID): void {
    store.set(`users/${uid}/activity_streams/${id}`, { state, objectPath: streamPath(uid, id, "up_1") });
  }
  test("a stored row gets a V4 GET URL with a 15 minute TTL; the other states give their code; the four 'absent' cases are IDENTICAL", async () => {
    seedRow(actId(1), "stored");
    seedRow(actId(2), "expired");
    seedRow(actId(3), "pending");
    seedRow(actId(4), "deleted");
    seedRow(actId(5), "stored");
    store.set(`users/${UID}/activity_tombstones/${actId(5)}`, { deletedAt: ts(T0) });
    seedRow(actId(7), "stored", UID_B);
    const res = await dl([actId(1), actId(2), actId(3), actId(4), actId(5), actId(6), actId(7)]);
    expect(res.results[0]).toMatchObject({ activityId: actId(1), status: "ok", expiresAtMs: T0 + 15 * MIN });
    expect((res.results[0] as any).url).toContain("https://");
    expect(res.results[1]).toEqual({ activityId: actId(2), status: "unavailable", code: "expired" });
    expect(res.results[2]).toEqual({ activityId: actId(3), status: "unavailable", code: "not_ready" });
    const absent = [3, 4, 5, 6].map((i) => ({ ...res.results[i], activityId: "x" }));
    for (const a of absent) expect(a).toEqual({ activityId: "x", status: "unavailable", code: "not_found" });
    expect(w.bucket.signed).toHaveLength(1);
    expect(w.bucket.signed[0].path).toBe(streamPath(UID, actId(1), "up_1"));
    expect(w.bucket.signed[0].config).toMatchObject({ version: "v4", action: "read", expires: T0 + 15 * MIN });
  });
  test("20 ids ok, 21 refused, duplicates are de-duplicated, an empty or non-array request is refused, anonymous is refused", async () => {
    const ids = Array.from({ length: 21 }, (_, i) => actId(i + 1));
    for (const id of ids) seedRow(id, "stored");
    expect((await dl(ids.slice(0, 20))).results).toHaveLength(20);
    await expectHttpsError(dl(ids), "invalid-argument", "invalid_request");
    expect((await dl([ids[0], ids[0], ids[1]])).results).toHaveLength(2);
    await expectHttpsError(dl([]), "invalid-argument", "invalid_request");
    await expectHttpsError(dl(["not an id"]), "invalid-argument", "invalid_request");
    await expectHttpsError(dl(ids.slice(0, 1), UID, "anonymous"), "permission-denied");
  });
  test("a fence or a deleted Auth user refuses, issues nothing and refunds the quota", async () => {
    seedRow(actId(1), "stored");
    store.set(`activity_account_state/${UID}`, { fenceAt: ts(T0) });
    await expectHttpsError(dl([actId(1)]), "failed-precondition", "account_deleting");
    expect(w.bucket.signed).toHaveLength(0);
    expect(usageOf(UID, "activityDownloadUrls")).toBe(0);
    store.delete(`activity_account_state/${UID}`);
    w.auth.users.delete(UID);
    await expectHttpsError(dl([actId(1)]), "unauthenticated", "account_deleted");
  });
  test("a signing failure returns a bare code and nothing partial", async () => {
    seedRow(actId(1), "stored");
    w.bucket.failOn = (op) => (op === "sign" ? Object.assign(new Error(`gs://b/streams/${UID}`), { code: 500 }) : null);
    const e = await expectHttpsError(dl([actId(1)]), "internal", "download_failed");
    expect(e.message).not.toContain(UID);
  });
  test("a row whose objectPath leaves the activity prefix is treated as not_found", async () => {
    store.set(`users/${UID}/activity_streams/${actId(1)}`, { state: "stored", objectPath: `streams/${UID_B}/${actId(1)}/up.json.gz` });
    expect((await dl([actId(1)])).results[0]).toMatchObject({ status: "unavailable", code: "not_found" });
  });
});

describe("F33 log hygiene across upload, commit, delete, export and download URLs", () => {
  test("no captured log line or thrown message holds a coordinate, an HR value or a signed URL", async () => {
    seedReady();
    const thrown: string[] = [];
    const f = await fullUpload(w);
    const bad = validPayload();
    bad.kinds.hr = { kind: "hr", unit: "bpm", sourceId: "src1", offsetsMs: [0], values: [173.25] };
    seedReady(UID, ACT_2);
    const s = await stage(w, bad, UID, ACT_2);
    thrown.push(await outcome(commit(w, { activityId: ACT_2, uploadId: s.uploadId })));
    expect(thrown[0]).not.toBe("OK");
    thrown.push(await outcome(dl([ACT])));
    await dl([ACT]);
    await exp();
    thrown.push(await outcome(SEVEN.find((e) => e.name === "deleteActivity")!.call(w, { activityId: ACT })));
    thrown.push(await outcome(create(w, { activityId: "bad", bytes: 1, contentSha256: "x" })));
    const text = loggedText(logger) + thrown.join("\n");
    for (const banned of ["51.5", "51.6", "173.25", "SIGNED_URL_SENTINEL", "X-Goog-Signature", "storage.invalid"]) expect(text).not.toContain(banned);
    expect(f.result).toBeDefined();
  });
});

/* ------------------------------ telemetry ------------------------------ */

const ev = (o: Record<string, unknown> = {}) => ({ type: "log", level: "info", component: "app", ...o });
const send = (data: unknown, uid = UID, provider = "password") => handleSendDebugTelemetry(w.deps, uid, provider, data);
const sessions = (): Array<[string, any]> => [...store.entries()].filter(([k]) => k.startsWith("debug_sessions/"));

describe("F34 valid batch", () => {
  test("is stored in the Phase 1 shape with server-set uid, identity and receivedAt", async () => {
    const res = await send({ events: [ev({ code: "ok", count: 3, seq: 0 }), ev({ type: "metric" })] });
    expect(res.stored).toBe(2);
    const [[key, doc]] = sessions();
    expect(key).toMatch(/^debug_sessions\/dbg_/);
    expect(Object.keys(doc).sort()).toEqual(["events", "identity", "receivedAt", "uid"]);
    expect(doc.uid).toBe(UID);
    expect(doc.identity).toBe("password");
    expect(doc.receivedAt.toMillis()).toBe(T0);
    expect(doc.events).toEqual([ev({ code: "ok", count: 3, seq: 0 }), ev({ type: "metric" })]);
  });
});

describe("F35 modified client", () => {
  const poisons: Array<[string, unknown]> = [
    ["coordinate pair", { lat: 51.5007, lon: -0.1278 }],
    ["geohash", "u4pruyd"],
    ["heart rate value", 173.25],
    ["place name", "Hyde Park"],
  ];
  const places: Array<[string, (v: unknown) => Record<string, unknown>]> = [
    ["top-level value", (v) => ev({ code: v })],
    ["nested map", (v) => ev({ code: { inner: v } })],
    ["list element", (v) => ev({ code: [v] })],
  ];
  const cases = poisons.flatMap(([pn, pv]) => places.map(([ln, make]) => [`${pn} as ${ln}`, make(pv)] as [string, Record<string, unknown>]));
  test.each(cases)("%s is rejected and nothing is written", async (_n, event) => {
    await expectHttpsError(send({ events: [ev(), event] }), "invalid-argument", "invalid_batch");
    expect(sessions()).toEqual([]);
  });
  test("99 valid events plus one poisoned event store none of the valid ones", async () => {
    const events = Array.from({ length: 99 }, () => ev());
    events.push(ev({ count: 51.5007 }) as never);
    await expectHttpsError(send({ events }), "invalid-argument", "invalid_batch");
    expect(sessions()).toEqual([]);
  });
});

describe("F36 closed schema limits", () => {
  test.each([
    ["unknown event type", ev({ type: "gps_fix" })],
    ["free-text string", ev({ code: "the user was at home" })],
    ["identifier-shaped string not in the enumeration", ev({ code: "a1b2c3" })],
    ["non-integer counter", ev({ count: 51.5007 })],
    ["negative counter", ev({ count: -1 })],
    ["unknown key", { ...ev(), lat: 1 }],
    ["missing required field", { type: "log", level: "info" }],
  ])("%s", async (_n, event) => {
    await expectHttpsError(send({ events: [event] }), "invalid-argument", "invalid_batch");
    expect(sessions()).toEqual([]);
  });
  test("101 events are refused with too_many_events, 100 are accepted", async () => {
    await expectHttpsError(send({ events: Array.from({ length: 101 }, () => ev()) }), "invalid-argument", "too_many_events");
    expect((await send({ events: Array.from({ length: 100 }, () => ev()) })).stored).toBe(100);
  });
});

describe("F37 identity", () => {
  test("an unauthenticated/anonymous caller is refused; a uid in the payload is rejected and the stored uid is the caller's", async () => {
    await expectHttpsError(send({ events: [ev()] }, UID, "anonymous"), "permission-denied", "anonymous_not_allowed");
    await expectHttpsError(send({ events: [ev()], uid: UID_B }), "invalid-argument", "invalid_batch");
    await send({ events: [ev()] });
    expect(sessions()[0][1].uid).toBe(UID);
  });
  test("the callable itself rejects a request without auth", async () => {
    const { sendDebugTelemetry } = await import("../../activity_streams/telemetry");
    await expect((sendDebugTelemetry as any).run({ data: { events: [] }, auth: undefined, rawRequest: {} })).rejects.toMatchObject({ code: "unauthenticated" });
  });
});

describe("F73 caps, quota, server-set fields", () => {
  test("the batch size gate: exactly 16 KiB passes the gate, 16 KiB + 1 byte is batch_too_large", () => {
    const sized = (bytes: number) => {
      const base = JSON.stringify({ events: [], pad: "" }).length;
      return { events: [], pad: "x".repeat(bytes - base) };
    };
    expect(Buffer.byteLength(JSON.stringify(sized(TELEMETRY_MAX_BATCH_BYTES)))).toBe(16384);
    expect(sanitizeTelemetryBatch(sized(16384))).toEqual({ ok: false, code: "invalid_batch" }); // passes the size gate, fails the key check
    expect(sanitizeTelemetryBatch(sized(16385))).toEqual({ ok: false, code: "batch_too_large" });
  });
  test("100 events per call are stored; the daily EVENT ceiling of 5000 is enforced across calls with a bare code", async () => {
    const batch = { events: Array.from({ length: 100 }, () => ev()) };
    for (let i = 0; i < 50; i++) await send(batch);
    await expectHttpsError(send(batch), "resource-exhausted", "quota_exceeded");
    expect(sessions()).toHaveLength(50);
    expect(usageOf(UID, "debugTelemetryEvents")).toBe(5000);
    expect(usageOf(UID, "debugTelemetrySend")).toBe(50); // the refused call gave its call charge back
  });
  test("the call quota of 200 per day is enforced", async () => {
    for (let i = 0; i < 200; i++) await send({ events: [] });
    await expectHttpsError(send({ events: [] }), "resource-exhausted", "quota_exceeded");
  });
  test("droppedCount is a counter capped at 255", async () => {
    await send({ events: [], droppedCount: 255 });
    await expectHttpsError(send({ events: [], droppedCount: 256 }), "invalid-argument", "invalid_batch");
  });
  test("the callable timeout is the bounded design value", () => {
    expect(TELEMETRY_OPTIONS.timeoutSeconds).toBe(30);
  });
  test("the fence and Auth existence are read inside the write transaction", async () => {
    store.set(`activity_account_state/${UID}`, { fenceAt: ts(T0) });
    await expectHttpsError(send({ events: [ev()] }), "failed-precondition", "account_deleting");
    store.delete(`activity_account_state/${UID}`);
    w.auth.users.delete(UID);
    await expectHttpsError(send({ events: [ev()] }), "unauthenticated", "account_deleted");
    expect(sessions()).toEqual([]);
    expect(usageOf(UID, "debugTelemetrySend")).toBe(0);
  });
  test("a fence created between the read and the commit stops the write (transaction retry)", async () => {
    let fired = false;
    fx.afterTxRead = async (p) => {
      if (!fired && p.startsWith(`activity_account_state/`)) { fired = true; store.set(`activity_account_state/${UID}`, { fenceAt: ts(T0) }); }
    };
    await expectHttpsError(send({ events: [ev()] }), "failed-precondition", "account_deleting");
    expect(sessions()).toEqual([]);
  });
});

describe("F74 closed schema table", () => {
  const fixture = JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures", "telemetry_schema.json"), "utf8"));
  test("the fixture is the data form of TELEMETRY_SCHEMA (no drift between the two copies)", () => {
    expect(fixture.event).toEqual(JSON.parse(JSON.stringify(TELEMETRY_SCHEMA.event)));
    expect(fixture.top).toEqual(JSON.parse(JSON.stringify(TELEMETRY_SCHEMA.top)));
    expect(fixture.providers).toEqual([...TELEMETRY_SCHEMA.providers]);
    expect(fixture.counterMax).toBe(TELEMETRY_COUNTER_MAX);
  });
  test("every field is an enumeration or a counter with max <= 255 (or justified); no free-text field", () => {
    for (const [name, spec] of Object.entries<any>(fixture.event)) {
      expect(["enum", "counter"]).toContain(spec.kind);
      if (spec.kind === "enum") expect(spec.values.length).toBeGreaterThan(0);
      else if (spec.max > 255) expect(fixture.justified).toContain(name);
    }
  });
  test.each(Object.entries<any>(fixture.event).filter(([, s]) => s.kind === "counter"))("counter %s: max accepted, 256, -1, 1.5, a 6-digit value, a string and a nested map rejected", (name, spec) => {
    const ok = (v: unknown) => sanitizeTelemetryBatch({ events: [ev({ [name]: v })] }).ok;
    expect(ok(spec.max)).toBe(true);
    expect(ok(0)).toBe(true);
    for (const bad of [spec.max + 1, 256, -1, 1.5, 123456, "7", { a: 1 }, [1], null]) expect(ok(bad)).toBe(false);
  });
  test.each(Object.entries<any>(fixture.event).filter(([, s]) => s.kind === "enum"))("enumeration %s: every listed value accepted, anything else rejected", (name, spec) => {
    const ok = (v: unknown) => sanitizeTelemetryBatch({ events: [ev({ [name]: v })] }).ok;
    for (const v of spec.values) expect(ok(v)).toBe(true);
    for (const bad of ["u4pruyd", "a1b2c3", "", "free text", 5, { a: 1 }, ["log"]]) expect(ok(bad)).toBe(false);
  });
  test("identity or any similar free-form field is refused in the payload (top level and per event)", async () => {
    for (const k of ["identity", "user", "deviceLabel"]) {
      expect(sanitizeTelemetryBatch({ events: [{ ...ev(), [k]: "abc123" }] }).ok).toBe(false);
      expect(sanitizeTelemetryBatch({ events: [ev()], [k]: "abc123" }).ok).toBe(false);
    }
  });
});

describe("F90 identity is not client chosen", () => {
  test("the stored identity follows request.auth, never the payload", async () => {
    await send({ events: [ev()] }, UID, "google.com");
    expect(sessions()[0][1].identity).toBe("google");
    await expectHttpsError(send({ events: [ev()], identity: "apple" }, UID, "google.com"), "invalid-argument", "invalid_batch");
    await expectHttpsError(send({ events: [{ ...ev(), identity: "password" }] }), "invalid-argument", "invalid_batch");
    expect(sessions()).toHaveLength(1);
    expect(identityFromProvider("something.else")).toBe("other");
    expect(identityFromProvider(undefined)).toBe("other");
    for (const p of ["password", "phone", "custom"]) expect(identityFromProvider(p)).toBe(p);
  });
});

describe("F93 drop counter", () => {
  test("droppedCount = 7 raises the drop metric by 7 in a production call, carries no uid and is not stored", async () => {
    (logger.info as jest.Mock).mockClear();
    await send({ events: [ev()], droppedCount: 7 });
    const calls = (logger.info as jest.Mock).mock.calls.filter((c) => c[0] === DEBUG_TELEMETRY_DROP_EVENT);
    expect(calls).toHaveLength(1);
    expect(calls[0][1]).toEqual({ operation: "sendDebugTelemetry", dropped: 7 });
    expect(JSON.stringify(calls)).not.toContain(UID);
    expect(JSON.stringify(sessions()[0][1])).not.toContain("dropped");
  });
  test("a batch without the counter emits no drop metric (not a zero)", async () => {
    (logger.info as jest.Mock).mockClear();
    await send({ events: [ev()] });
    expect((logger.info as jest.Mock).mock.calls.filter((c) => c[0] === DEBUG_TELEMETRY_DROP_EVENT)).toHaveLength(0);
  });
  test("an explicit zero IS reported as 0 only when the client states it", async () => {
    (logger.info as jest.Mock).mockClear();
    await send({ events: [], droppedCount: 0 });
    const calls = (logger.info as jest.Mock).mock.calls.filter((c) => c[0] === DEBUG_TELEMETRY_DROP_EVENT);
    expect(calls).toHaveLength(1);
    expect(calls[0][1].dropped).toBe(0);
    expect(uploadIdN(1)).toBeDefined();
  });
});
