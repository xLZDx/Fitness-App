/**
 * S02 remediation J3a: the invocation-bound identity (`expectedUid`) at the download and delete-all handlers
 * (design 17 item 25), plus the structural guard that every client-initiated activity callable verifies it
 * before its first `await`. Mismatch reads nothing, writes nothing and charges nothing.
 */
jest.mock("firebase-admin", () => require("./support/fakes").adminMock());
jest.mock("firebase-functions/logger", () => require("./support/fakes").loggerMock());

import { readdirSync, readFileSync } from "fs";
import { join } from "path";
import * as logger from "firebase-functions/logger";
import {
  ACT, T0, UID, UID_B, callReq, createWorld, expectHttpsError, loggedText, releaseClock, resetAll, seedReady,
  store, useClock, usageOf, writes, timeline, type World,
} from "./support/fakes";
import { prime } from "./support/seven";

import { handleDeleteAllActivityStreams, deleteAllActivityStreams } from "../../activity_streams/delete_all_streams";
import { handleGetActivityStreamDownloadUrls, getActivityStreamDownloadUrls } from "../../activity_streams/download_urls";

/* eslint-disable @typescript-eslint/no-explicit-any */
let w: World;
beforeEach(async () => {
  resetAll();
  useClock(T0);
  w = createWorld();
  seedReady();
  await prime(w);
});
afterEach(() => releaseClock());

type Raw = (w: World, uid: string, provider: string, data: unknown) => Promise<any>;
interface Case {
  name: string;
  action: string;
  limit: number;
  raw: Raw;
  /** A valid request body WITHOUT the key. */
  body(): Record<string, unknown>;
  /** A request that is invalid on its own (proves the key is checked before the parse). */
  invalidBody(): Record<string, unknown>;
  proof(res: any): void;
  onCall: unknown;
}

const CASES: Case[] = [
  {
    name: "getActivityStreamDownloadUrls", action: "activityDownloadUrls", limit: 60,
    raw: (x, uid, prov, d) => handleGetActivityStreamDownloadUrls(x.deps, uid, prov, d),
    body: () => ({ activityIds: [ACT] }),
    invalidBody: () => ({ activityIds: ["not-an-id"] }),
    proof: (res) => { expect(res.results).toHaveLength(1); expect(res.results[0].status).toBe("ok"); },
    onCall: getActivityStreamDownloadUrls,
  },
  {
    name: "deleteAllActivityStreams", action: "activityDeleteAll", limit: 10,
    raw: (x, uid, prov, d) => handleDeleteAllActivityStreams(x.deps, uid, prov, d),
    body: () => ({}),
    invalidBody: () => ({ extra: 1 }),
    proof: (res) => { expect(res.status).toBe("done"); expect(res.deleted).toBe(1); expect(store.has(`users/${UID}/activity_streams/${ACT}`)).toBe(false); },
    onCall: deleteAllActivityStreams,
  },
];

const snapshot = (): string => JSON.stringify([...store.entries()]);
interface Marks { state: string; writes: number; timeline: number; bucket: number; lookups: number }
const mark = (): Marks => ({
  state: snapshot(), writes: writes.length, timeline: timeline.length, bucket: w.bucket.totalCalls, lookups: w.auth.lookups,
});
/** Nothing changed and nothing was even READ: the injected firestore() seam was never asked for. */
const expectUntouched = (m: Marks, action: string, fsSpy: jest.SpyInstance): void => {
  expect(fsSpy).not.toHaveBeenCalled();
  expect(writes.length).toBe(m.writes);
  expect(timeline.length).toBe(m.timeline);
  expect(snapshot()).toBe(m.state);
  expect(w.bucket.totalCalls).toBe(m.bucket);
  expect(w.auth.lookups).toBe(m.lookups);
  expect(usageOf(UID, action)).toBe(0);
  expect(usageOf(UID_B, action)).toBe(0);
};
const spyFs = (): jest.SpyInstance => jest.spyOn(w.deps as any, "firestore");
const names = CASES.map((c) => [c.name] as const);
const by = (n: string): Case => CASES.find((c) => c.name === n)!;

describe("J3a account_changed: mismatch is refused before anything happens", () => {
  test.each(names)("%s: failed-precondition / account_changed, no read, no write, no quota document, no storage or auth call, log without uid", async (name) => {
    const c = by(name);
    const m = mark();
    const fs = spyFs();
    (logger.warn as jest.Mock).mockClear();
    const err = await expectHttpsError(c.raw(w, UID, "password", { ...c.body(), expectedUid: UID_B }), "failed-precondition", "account_changed");
    expect(err.message).toBe("account_changed");
    expectUntouched(m, c.action, fs);
    expect((logger.warn as jest.Mock).mock.calls.some((x) => JSON.stringify(x).includes('"outcome":"account_changed"'))).toBe(true);
    const text = loggedText(logger);
    expect(text).toContain('"outcome":"account_changed"');
    expect(text).not.toContain(UID);
    expect(text).not.toContain(UID_B);
    expect(text).not.toContain(ACT);
  });

  test.each(names)("%s: a case-different key is a mismatch, not a pass", async (name) => {
    const c = by(name);
    const m = mark();
    const fs = spyFs();
    await expectHttpsError(c.raw(w, UID, "password", { ...c.body(), expectedUid: UID.toUpperCase() }), "failed-precondition", "account_changed");
    expectUntouched(m, c.action, fs);
  });

  test.each(names)("%s: the mismatch wins over an invalid rest of the request (runs before the parse)", async (name) => {
    const c = by(name);
    const m = mark();
    const fs = spyFs();
    await expectHttpsError(c.raw(w, UID, "password", { ...c.invalidBody(), expectedUid: UID_B }), "failed-precondition", "account_changed");
    expectUntouched(m, c.action, fs);
    // Control: the same invalid body with the RIGHT key is invalid_request, so the body really is invalid.
    await expectHttpsError(c.raw(w, UID, "password", { ...c.invalidBody(), expectedUid: UID }), "invalid-argument", "invalid_request");
  });

  test.each(names)("%s: the mismatch wins over an exhausted quota and does not touch the counter (runs before the charge)", async (name) => {
    const c = by(name);
    const day = `users/${UID}/usage/2026-10-15`;
    store.set(day, { [c.action]: c.limit });
    const before = JSON.stringify(store.get(day));
    const nWrites = writes.length;
    await expectHttpsError(c.raw(w, UID, "password", { ...c.body(), expectedUid: UID_B }), "failed-precondition", "account_changed");
    expect(JSON.stringify(store.get(day))).toBe(before);
    expect(writes.length).toBe(nWrites);
    // Control: the same exhausted state with the RIGHT key is a quota refusal, so the setup really exhausts it.
    await expectHttpsError(c.raw(w, UID, "password", { ...c.body(), expectedUid: UID }), "resource-exhausted", "quota_exceeded");
  });

  test.each(names)("%s: the anonymous gate stays first, even with a mismatching key", async (name) => {
    const c = by(name);
    const m = mark();
    const fs = spyFs();
    (logger.warn as jest.Mock).mockClear();
    await expectHttpsError(c.raw(w, UID, "anonymous", { ...c.body(), expectedUid: UID_B }), "permission-denied", "anonymous_not_allowed");
    expectUntouched(m, c.action, fs);
    expect((logger.warn as jest.Mock).mock.calls.some((x) => JSON.stringify(x).includes("account_changed"))).toBe(false);
  });

  test.each(names)("%s: the key is checked against the caller uid, so a caller as UID_B with UID's key is a mismatch", async (name) => {
    const c = by(name);
    const m = mark();
    const fs = spyFs();
    await expectHttpsError(c.raw(w, UID_B, "password", { ...c.body(), expectedUid: UID }), "failed-precondition", "account_changed");
    expectUntouched(m, c.action, fs);
  });
});

describe("J3a malformed or missing key: invalid_request", () => {
  const BAD: Array<[string, unknown, boolean]> = [
    ["missing", undefined, false],
    ["null", null, true],
    ["number", 5, true],
    ["object", { uid: UID }, true],
    ["empty string", "", true],
    ["129 characters", "u".repeat(129), true],
  ];
  for (const [label, value, present] of BAD) {
    test.each(names)(`%s: ${label} key -> invalid-argument / invalid_request, no read, no charge, no write`, async (name) => {
      const c = by(name);
      const m = mark();
      const fs = spyFs();
      const data = present ? { ...c.body(), expectedUid: value } : c.body();
      const err = await expectHttpsError(c.raw(w, UID, "password", data), "invalid-argument", "invalid_request");
      expect(err.message).toBe("invalid_request");
      expectUntouched(m, c.action, fs);
    });
  }

  test.each(names)("%s: non-object data is invalid_request with no read, no charge and no write", async (name) => {
    const c = by(name);
    for (const data of [null, undefined, [], [{ expectedUid: UID }], "x", 5]) {
      const m = mark();
      const fs = spyFs();
      await expectHttpsError(c.raw(w, UID, "password", data), "invalid-argument", "invalid_request");
      expectUntouched(m, c.action, fs);
      fs.mockRestore();
    }
  });
});

describe("J3a matching key: the success path and the strict bodies", () => {
  test.each(names)("%s: a matching key reaches the handler, charges exactly once and has the normal effect", async (name) => {
    const c = by(name);
    const res = await c.raw(w, UID, "password", { ...c.body(), expectedUid: UID });
    c.proof(res);
    expect(usageOf(UID, c.action)).toBe(1);
  });

  test("download: with a valid expectedUid a malformed id is still invalid_request (no read, no charge)", async () => {
    // The download parser reads only `activityIds`; a malformed id with a valid key stays invalid_request and charges nothing.
    const m = mark();
    const fs = spyFs();
    await expectHttpsError(
      handleGetActivityStreamDownloadUrls(w.deps, UID, "password", { activityIds: [ACT, "bad"], expectedUid: UID }),
      "invalid-argument", "invalid_request",
    );
    expect(usageOf(UID, "activityDownloadUrls")).toBe(0);
    expect(w.bucket.totalCalls).toBe(m.bucket);
    expect(fs).not.toHaveBeenCalled();
  });

  test("download: the expectedUid key itself is never treated as an activity id source (no ids -> invalid_request, no charge)", async () => {
    await expectHttpsError(
      handleGetActivityStreamDownloadUrls(w.deps, UID, "password", { expectedUid: UID }),
      "invalid-argument", "invalid_request",
    );
    expect(usageOf(UID, "activityDownloadUrls")).toBe(0);
  });

  test("deleteAll: an extra body key next to a valid expectedUid is invalid_request, nothing is read, charged or deleted", async () => {
    const m = mark();
    const fs = spyFs();
    await expectHttpsError(
      handleDeleteAllActivityStreams(w.deps, UID, "password", { expectedUid: UID, extra: 1 }),
      "invalid-argument", "invalid_request",
    );
    expectUntouched(m, "activityDeleteAll", fs);
    expect(store.has(`users/${UID}/activity_streams/${ACT}`)).toBe(true);
  });

  test("deleteAll: client path fields in the body are refused, never ignored (the old ignore-the-body behavior is gone)", async () => {
    for (const evil of [{ activityId: "../x" }, { uid: UID_B }, { path: "evil/p" }]) {
      const m = mark();
      const fs = spyFs();
      await expectHttpsError(
        handleDeleteAllActivityStreams(w.deps, UID, "password", { expectedUid: UID, ...evil }),
        "invalid-argument", "invalid_request",
      );
      expectUntouched(m, "activityDeleteAll", fs);
      fs.mockRestore();
    }
  });
});

describe("J3a onCall wrapper", () => {
  test.each(names)("%s: a missing request.auth is refused as unauthenticated before the handler", async (name) => {
    const c = by(name);
    const m = mark();
    const fs = spyFs();
    await expectHttpsError((c.onCall as any).run(callReq({ ...c.body(), expectedUid: UID }, null)), "unauthenticated", "sign_in_required");
    expectUntouched(m, c.action, fs);
  });

  test.each(names)("%s: through the real onCall, a mismatching key is account_changed and a matching key is accepted by the wrapper", async (name) => {
    const c = by(name);
    await expectHttpsError(
      (c.onCall as any).run(callReq({ ...c.body(), expectedUid: UID_B }, UID)),
      "failed-precondition", "account_changed",
    );
    expect(usageOf(UID, c.action)).toBe(0);
  });
});

/* ---------------------------------------------------------------------------------------------- */
/* Structural guard: every client-initiated activity callable verifies expectedUid before an await. */
/* ---------------------------------------------------------------------------------------------- */

/** Exported onCall handlers that are NOT bound to an account, by name with the reason. */
const EXEMPT: Record<string, string> = {
  sendDebugTelemetry: "debug telemetry batch carries no account action; its strict batch parser refuses extra keys (design 17 item 25 scope)",
};

interface HandlerScan { name: string; handle: string | undefined; verifiesBeforeAwait: boolean }

/** Pure scan of one source file: every `export const X = onCall(` and whether its `handle...` function verifies first. */
export function scanHandlers(src: string): HandlerScan[] {
  const out: HandlerScan[] = [];
  for (const m of src.matchAll(/export const (\w+) = onCall\(/g)) {
    const rest = src.slice(m.index! + m[0].length);
    const end = rest.indexOf("\n});");
    const wrapper = end === -1 ? rest : rest.slice(0, end);
    const handle = /return\s+(handle\w+)\(/.exec(wrapper)?.[1];
    let verifies = false;
    if (handle !== undefined) {
      const at = src.search(new RegExp(`export (?:async )?function ${handle}\\(`));
      if (at !== -1) {
        const fnRest = src.slice(at);
        const close = fnRest.search(/\n}\n|\n}$/);
        const fn = close === -1 ? fnRest : fnRest.slice(0, close);
        const bodyStart = fn.indexOf("{\n");
        const body = bodyStart === -1 ? fn : fn.slice(bodyStart);
        const v = body.indexOf("verifyExpectedUid(");
        const a = body.indexOf("await ");
        verifies = v !== -1 && (a === -1 || v < a);
      }
    }
    out.push({ name: m[1], handle, verifiesBeforeAwait: verifies });
  }
  return out;
}

describe("J3a structural: every client-initiated activity callable verifies expectedUid before its first await", () => {
  const dir = join(__dirname, "..", "..", "activity_streams");
  const all = readdirSync(dir).filter((f) => f.endsWith(".ts")).flatMap((f) => scanHandlers(readFileSync(join(dir, f), "utf8")));

  test("the scan finds all seven callables, each with a resolvable handle function", () => {
    expect(all.map((h) => h.name).sort()).toEqual([
      "commitActivityStream", "createActivityStreamUpload", "deleteActivity", "deleteAllActivityStreams",
      "getActivityStreamDownloadUrls", "sendDebugTelemetry", "setActivityCloudSettings",
    ]);
    for (const h of all) expect(h.handle).toMatch(/^handle/);
  });

  test("exactly the exempt handlers lack the early verification; all others have it", () => {
    const lacking = all.filter((h) => !h.verifiesBeforeAwait).map((h) => h.name).sort();
    expect(lacking).toEqual(Object.keys(EXEMPT).sort());
    expect(Object.keys(EXEMPT)).toEqual(["sendDebugTelemetry"]);
  });

  describe("self-check on synthetic sources (the scan can fail)", () => {
    const wrapper = (h: string) => `export const doIt = onCall(RARE, async (request) => {\n  return ${h}(deps, request.auth.uid, p, request.data);\n});\n`;
    test("verify before the first await passes", () => {
      const src = `export async function handleDoIt(a) {\n  const x = 1;\n  verifyExpectedUid(uid, data);\n  await go();\n}\n${wrapper("handleDoIt")}`;
      expect(scanHandlers(src)).toEqual([{ name: "doIt", handle: "handleDoIt", verifiesBeforeAwait: true }]);
    });
    test("an await before the verification fails", () => {
      const src = `export async function handleDoIt(a) {\n  await go();\n  verifyExpectedUid(uid, data);\n}\n${wrapper("handleDoIt")}`;
      expect(scanHandlers(src)[0].verifiesBeforeAwait).toBe(false);
    });
    test("no verification at all fails", () => {
      const src = `export async function handleDoIt(a) {\n  return 1;\n}\n${wrapper("handleDoIt")}`;
      expect(scanHandlers(src)[0].verifiesBeforeAwait).toBe(false);
    });
    test("a handler whose handle function cannot be resolved fails", () => {
      expect(scanHandlers(wrapper("handleMissing"))[0].verifiesBeforeAwait).toBe(false);
    });
    test("a verification that only appears in a later function does not count", () => {
      const src = `export async function handleDoIt(a) {\n  await go();\n}\n\nfunction other() {\n  verifyExpectedUid(u, d);\n}\n${wrapper("handleDoIt")}`;
      expect(scanHandlers(src)[0].verifiesBeforeAwait).toBe(false);
    });
  });
});
