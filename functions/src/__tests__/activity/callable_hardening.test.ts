/** F41 registered and authenticated, F60 input validation, F61 quota, F62 log and error hygiene. */
jest.mock("firebase-admin", () => require("./support/fakes").adminMock());
jest.mock("firebase-functions/logger", () => require("./support/fakes").loggerMock());

import { readdirSync, readFileSync } from "fs";
import { join } from "path";
import * as logger from "firebase-functions/logger";
import { QUOTAS } from "../../abuse_guard";
import {
  ACT, ACT_2, DAY, T0, UID, UID_B, callReq, ts, createWorld, expectHttpsError, loggedText, quarantinePath, releaseClock,
  resetAll, rowOf, seedReady, setNow, store, uploadOf, usageOf, useClock, validPayload, writes, type World,
} from "./support/fakes";
import { commit, create, outcome, stage } from "./support/flow";
import { SEVEN, TELEMETRY_OK, clearUsage, prime, type Primed } from "./support/seven";

import { createActivityStreamUpload } from "../../activity_streams/create_upload";
import { commitActivityStream } from "../../activity_streams/commit_stream";
import { deleteActivity } from "../../activity_streams/delete_activity";
import { setActivityCloudSettings } from "../../activity_streams/set_settings";
import { getActivityStreamDownloadUrls } from "../../activity_streams/download_urls";
import { deleteAllActivityStreams } from "../../activity_streams/delete_all_streams";
import { sendDebugTelemetry } from "../../activity_streams/telemetry";

let w: World;
let p: Primed;
beforeEach(async () => {
  resetAll();
  useClock(T0);
  w = createWorld();
  seedReady();
  p = await prime(w);
});
afterEach(() => releaseClock());

const SRC = join(__dirname, "..", "..");
const by = (n: string) => SEVEN.find((e) => e.name === n)!;

describe("F41 callables registered and authenticated", () => {
  const exported: Record<string, unknown> = {
    createActivityStreamUpload, commitActivityStream, deleteActivity, setActivityCloudSettings,
    getActivityStreamDownloadUrls, deleteAllActivityStreams, sendDebugTelemetry,
  };
  test("the table, the imports and the source scan agree on exactly SEVEN names", () => {
    const dir = join(SRC, "activity_streams");
    const found = readdirSync(dir).filter((f) => f.endsWith(".ts")).flatMap((f) =>
      [...readFileSync(join(dir, f), "utf8").matchAll(/export const (\w+) = onCall/g)].map((m) => m[1]));
    expect(found.sort()).toEqual(Object.keys(exported).sort());
    expect(SEVEN.map((e) => e.name).sort()).toEqual(Object.keys(exported).sort());
    expect(SEVEN).toHaveLength(7);
  });
  test.each(SEVEN.map((e) => e.name))("%s is exported from index, calls noteAppCheck, and refuses an unauthenticated call", async (name) => {
    const index = readFileSync(join(SRC, "index.ts"), "utf8");
    expect(index).toMatch(new RegExp(`export \\{[^}]*\\b${name}\\b[^}]*\\} from "\\./activity_streams/`));
    const file = readdirSync(join(SRC, "activity_streams")).map((f) => readFileSync(join(SRC, "activity_streams", f), "utf8")).find((t) => t.includes(`export const ${name} = onCall`))!;
    expect(file).toContain(`noteAppCheck(request, "${name}")`);
    expect(file).toContain('if (!request.auth) throw new HttpsError("unauthenticated"');
    await expectHttpsError((exported[name] as any).run(callReq({}, null)), "unauthenticated");
  });
  test.each(SEVEN.map((e) => e.name))("%s refuses an anonymous caller before any work", async (name) => {
    const e = by(name);
    const calls = w.bucket.totalCalls;
    const n = writes.length;
    await expectHttpsError(e.call(w, e.ok(p), UID, "anonymous"), "permission-denied");
    expect(w.bucket.totalCalls).toBe(calls);
    expect(writes.length).toBe(n);
  });
});

describe("F60 shared input validation", () => {
  const BAD_IDS: unknown[] = [
    "act_x/../y", `act_${"a".repeat(39)}`, `act_${"a".repeat(41)}`, `act_${"A".repeat(40)}`, `act_${"a".repeat(20)}/${"a".repeat(19)}`,
    "", 5, null, undefined, `../${ACT}`, ["x"],
  ];
  const idCallables: Array<[string, (id: unknown) => unknown]> = [
    ["createActivityStreamUpload", (id) => ({ activityId: id, bytes: p.bytes, contentSha256: p.sha })],
    ["commitActivityStream", (id) => ({ activityId: id, uploadId: p.uploadId })],
    ["deleteActivity", (id) => ({ activityId: id })],
    ["getActivityStreamDownloadUrls", (id) => ({ activityIds: [id] })],
  ];
  for (const [name, mk] of idCallables) {
    test.each(BAD_IDS.map((v) => [JSON.stringify(v) ?? "undefined", v] as const))(`${name} refuses activityId %s with no storage call and no charge`, async (_l, id) => {
      const calls = w.bucket.totalCalls;
      await expectHttpsError(by(name).call(w, mk(id)), "invalid-argument", "invalid_request");
      expect(w.bucket.totalCalls).toBe(calls);
      expect(usageOf(UID, by(name).quotaAction)).toBe(0);
    });
  }
  test("commit refuses a malformed or client-chosen uploadId", async () => {
    for (const up of ["up_x", `up_${"B".repeat(32)}`, "../../x", 7, undefined]) {
      await expectHttpsError(commit(w, { activityId: ACT, uploadId: up }), "invalid-argument", "invalid_request");
    }
  });
  test.each([[0], [5 * 1024 * 1024 + 1], [1.5], ["100"], [-1], [null]])("bytes %p is refused", async (bytes) => {
    await expectHttpsError(create(w, { activityId: ACT_2, bytes, contentSha256: p.sha }), "invalid-argument", "invalid_request");
    expect(rowOf(UID, ACT_2)).toBeUndefined();
  });
  test.each([[1], [5 * 1024 * 1024]])("bytes %p is accepted", async (bytes) => {
    seedReady(UID, ACT_2);
    expect((await create(w, { activityId: ACT_2, bytes, contentSha256: "b".repeat(64) })).status).toBe("upload");
  });
  test.each([["63 chars", "a".repeat(63)], ["65 chars", "a".repeat(65)], ["non-hex", "g".repeat(64)], ["number", 5]])("contentSha256 %s is refused", async (_n, h) => {
    await expectHttpsError(create(w, { activityId: ACT_2, bytes: 10, contentSha256: h }), "invalid-argument", "invalid_request");
  });
  test("an upper case hash is accepted and stored lower case", async () => {
    seedReady(UID, ACT_2);
    await create(w, { activityId: ACT_2, bytes: 10, contentSha256: "AB".repeat(32) });
    expect(rowOf(UID, ACT_2).contentSha256).toBe("ab".repeat(32));
  });
  test("download: 21 distinct ids refused, 20 accepted, duplicates deduplicated, empty/non-array refused", async () => {
    const id = (n: number) => `act_${n.toString(16).padStart(40, "0")}`;
    const d = by("getActivityStreamDownloadUrls");
    await expectHttpsError(d.call(w, { activityIds: Array.from({ length: 21 }, (_, i) => id(i)) }), "invalid-argument", "invalid_request");
    expect((await d.call(w, { activityIds: Array.from({ length: 20 }, (_, i) => id(i)) })).results).toHaveLength(20);
    const dup = await d.call(w, { activityIds: Array.from({ length: 25 }, () => ACT) });
    expect(dup.results).toHaveLength(1);
    const mixed = await d.call(w, { activityIds: [...Array.from({ length: 20 }, (_, i) => id(i)), id(0), id(1)] });
    expect(mixed.results).toHaveLength(20);
    await expectHttpsError(d.call(w, { activityIds: [] }), "invalid-argument", "invalid_request");
    await expectHttpsError(d.call(w, { activityIds: "x" }), "invalid-argument", "invalid_request");
    await expectHttpsError(d.call(w, { activityIds: Array.from({ length: 101 }, () => ACT) }), "invalid-argument", "invalid_request");
  });
  test("client-supplied path, prefix, uid, bucket and objectPath fields never reach a path (delete, commit, download)", async () => {
    const evil = { path: "evil/p", prefix: "evil/", uid: UID_B, bucket: "other", objectPath: "evil/o" };
    await by("deleteActivity").call(w, { activityId: ACT_2, ...evil });
    expect(store.has(`users/${UID}/activity_tombstones/${ACT_2}`)).toBe(true);
    expect([...store.keys()].some((k) => k.includes(UID_B))).toBe(false);
    expect(w.bucket.deleteFilesCalls.every((x) => x.includes(UID) && !x.includes("evil"))).toBe(true);
    await by("commitActivityStream").call(w, { activityId: ACT, uploadId: p.uploadId, ...evil });
    const dl = await by("getActivityStreamDownloadUrls").call(w, { activityIds: [ACT], ...evil });
    expect(w.bucket.signed.at(-1)!.path.startsWith(`streams/${UID}/${ACT}/`)).toBe(true);
    expect(dl.results[0].status).toBe("ok");
  });
  test("settings: unknown keys are refused, never ignored; deleteAll refuses a client body (J3a); telemetry refuses an unknown top-level key", async () => {
    await expectHttpsError(by("setActivityCloudSettings").call(w, { streamRetentionDays: 90, uid: UID_B }), "invalid-argument", "invalid_request");
    await expectHttpsError(by("sendDebugTelemetry").call(w, { events: [], uid: UID_B }), "invalid-argument", "invalid_batch");
    await expectHttpsError(by("deleteAllActivityStreams").call(w, { activityId: "../x", uid: UID_B }), "invalid-argument", "invalid_request");
    expect((await by("deleteAllActivityStreams").call(w, {})).status).toBe("done");
  });
});

describe("F61 quota per callable", () => {
  test("the starting limits are pinned", () => {
    for (const e of SEVEN) expect((QUOTAS as Record<string, number>)[e.quotaAction]).toBe(e.limit);
  });
  test.each(SEVEN.map((e) => e.name))("%s: call N succeeds, N+1 is a bare quota code without side effects; the next day resets; another user is unaffected; the log names no uid", async (name) => {
    const e = by(name);
    // Isolate from the priming: the table's own action starts at zero.
    clearUsage();
    for (let i = 1; i <= e.limit; i++) await e.call(w, e.ok(p));
    expect(usageOf(UID, e.quotaAction)).toBe(e.limit);

    const stateBefore = JSON.stringify([...store.entries()].filter(([k]) => !k.includes("/usage/")));
    const calls = w.bucket.totalCalls;
    (logger.warn as jest.Mock).mockClear();
    const err = await expectHttpsError(e.call(w, e.ok(p)), "resource-exhausted", "quota_exceeded");
    expect(err.message).toBe("quota_exceeded");
    expect(JSON.stringify([...store.entries()].filter(([k]) => !k.includes("/usage/")))).toBe(stateBefore);
    expect(w.bucket.totalCalls).toBe(calls);
    expect(usageOf(UID, e.quotaAction)).toBe(e.limit);
    expect(loggedText(logger)).not.toContain(UID);

    // Another user is not affected by this user's exhaustion.
    expect(await outcome(e.call(w, e.ok(p), UID_B))).not.toBe("resource-exhausted:quota_exceeded");

    setNow(T0 + DAY);
    expect(await outcome(e.call(w, e.ok(p)))).not.toBe("resource-exhausted:quota_exceeded");
    // The new UTC day's counter restarted at 1 (usageOf sums all days, so read the day document).
    expect(store.get(`users/${UID}/usage/2026-10-16`)?.[e.quotaAction]).toBe(1);
    expect(store.get(`users/${UID}/usage/2026-10-15`)?.[e.quotaAction]).toBe(e.limit);
  });
  test("exhausting activityDelete does not block deleteAllActivityStreams and the reverse (design 5.4)", async () => {
    clearUsage();
    for (let i = 0; i < 1000; i++) await by("deleteActivity").call(w, { activityId: ACT_2 });
    await expectHttpsError(by("deleteActivity").call(w, { activityId: ACT_2 }), "resource-exhausted", "quota_exceeded");
    expect((await by("deleteAllActivityStreams").call(w, {})).status).toBe("done");
    clearUsage();
    for (let i = 0; i < 10; i++) await by("deleteAllActivityStreams").call(w, {});
    await expectHttpsError(by("deleteAllActivityStreams").call(w, {}), "resource-exhausted", "quota_exceeded");
    expect((await by("deleteActivity").call(w, { activityId: ACT_2 })).deleted).toBe(true);
  });
  test("E2 / MAJOR-03: the activityDelete daily limit is 1000, per user, and fence refusals refund the charge", async () => {
    expect(QUOTAS.activityDelete).toBe(1000);
    clearUsage();
    const day = `users/${UID}/usage/2026-10-15`;
    store.set(day, { activityDelete: 999 });
    // 1000th call of the day is accepted, the 1001st is refused.
    expect((await by("deleteActivity").call(w, { activityId: ACT_2 })).deleted).toBe(true);
    expect(usageOf(UID, "activityDelete")).toBe(1000);
    await expectHttpsError(by("deleteActivity").call(w, { activityId: ACT_2 }), "resource-exhausted", "quota_exceeded");
    // Per user: another account is not affected by UID's exhaustion.
    expect(usageOf(UID_B, "activityDelete")).toBe(0);
    await by("deleteActivity").call(w, { activityId: ACT_2 }, UID_B).catch(() => undefined);
    expect(usageOf(UID_B, "activityDelete")).toBe(1);
    // Fence refusal refunds: at 999 used, a fenced call leaves the counter at 999.
    store.set(day, { activityDelete: 999 });
    store.set(`activity_account_state/${UID}`, { fenceAt: ts(T0) });
    await expectHttpsError(by("deleteActivity").call(w, { activityId: ACT_2 }), "failed-precondition", "account_deleting");
    expect(usageOf(UID, "activityDelete")).toBe(999);
  });
});

describe("F62 error and log hygiene", () => {
  const SENT = "SENTINEL_ID_77";
  const FORBIDDEN = () => [UID, ACT, p.uploadId, "quarantine/", "streams/", "SIGNED_URL_SENTINEL", "51.5007", "https://", SENT];

  test("every failure path throws a bare code and logs no client value, uid, path, coordinate or URL", async () => {
    const BARE = /^[a-z-]+:[a-z_]+$/;
    const outcomes: string[] = [];
    const run = async (pr: Promise<unknown>) => { outcomes.push(await outcome(pr)); };

    // Validation failures carrying sentinels.
    await run(create(w, { activityId: `act_${SENT}/../x`, bytes: 5, contentSha256: SENT }));
    await run(commit(w, { activityId: ACT, uploadId: `up_${SENT}` }));
    await run(by("deleteActivity").call(w, { activityId: SENT }));
    await run(by("getActivityStreamDownloadUrls").call(w, { activityIds: [SENT] }));
    await run(by("setActivityCloudSettings").call(w, { [SENT]: 1 }));
    await run(by("sendDebugTelemetry").call(w, { events: [{ type: SENT }] }));

    // Fence, tombstone, consent, storage failure with a hostile message.
    store.set(`users/${UID}/activity_tombstones/${ACT_2}`, { deletedAt: 1 });
    seedReady(UID, ACT_2);
    await run(create(w, { activityId: ACT_2, bytes: 10, contentSha256: "a".repeat(64) }));
    await run(commit(w, { activityId: ACT_2, uploadId: `up_${"d".repeat(32)}` }));
    w.bucket.failOn = () => Object.assign(new Error(`boom at quarantine/${UID}/${ACT} 51.5007,-0.1276`), { code: 500 });
    const s = await stage(w, validPayload(), UID, ACT_2).catch(() => undefined);
    w.bucket.failOn = null;
    store.delete(`users/${UID}/activity_tombstones/${ACT_2}`);
    const s2 = await stage(w, validPayload(), UID, ACT_2);
    w.bucket.failOn = () => Object.assign(new Error(`boom at quarantine/${UID}/${ACT} 51.5007,-0.1276`), { code: 500 });
    await run(commit(w, { activityId: ACT_2, uploadId: s2.uploadId }));
    w.bucket.failOn = null;
    w.auth.lookupError = Object.assign(new Error(`lookup ${UID}`), { code: "auth/internal-error" });
    for (const e of SEVEN) await run(e.call(w, e.ok(p)));
    w.auth.lookupError = null;

    // A validation rejection whose payload carries a coordinate-like string.
    const bad = validPayload();
    bad.meta.provenance[0].externalId = "ext:51.5007";
    const s3 = await stage(w, bad, UID, ACT_2);
    await run(commit(w, { activityId: ACT_2, uploadId: s3.uploadId }));

    void s;
    expect(outcomes.length).toBeGreaterThan(10);
    for (const o of outcomes) {
      expect(o).toMatch(BARE);
      for (const f of FORBIDDEN()) expect(o).not.toContain(f);
    }
    const text = loggedText(logger);
    for (const f of FORBIDDEN().filter((x) => x !== ACT && x !== p.uploadId)) expect(text).not.toContain(f);
    // Identifiers: neither the activity ids nor the upload ids appear in any log line.
    expect(text).not.toContain(ACT);
    expect(text).not.toContain(ACT_2);
    expect(text).not.toContain(p.uploadId);
    expect(text).not.toContain(s2.uploadId);
  });

  test("successful calls also log no uid, id, path or URL", async () => {
    (logger.info as jest.Mock).mockClear();
    const up = uploadOf({ ...validPayload(), kinds: { speed: validPayload().kinds.speed } });
    seedReady(UID, ACT_2);
    const r = await create(w, { activityId: ACT_2, bytes: up.bytes.length, contentSha256: up.sha });
    w.bucket.put(quarantinePath(UID, ACT_2, r.uploadId), up.bytes);
    await commit(w, { activityId: ACT_2, uploadId: r.uploadId });
    await by("getActivityStreamDownloadUrls").call(w, { activityIds: [ACT_2] });
    await by("deleteActivity").call(w, { activityId: ACT_2 });
    const text = loggedText(logger);
    for (const f of [UID, ACT_2, r.uploadId, "SIGNED_URL_SENTINEL", "https://", "quarantine/", "streams/"]) expect(text).not.toContain(f);
    expect(text).toContain("activity_upload_event");
  });
  void TELEMETRY_OK;
});
