/**
 * S02 remediation J1: the invocation-bound identity (`expectedUid`) at the four activity handlers
 * (design 17 item 25). Mismatch writes nothing and charges nothing; the check runs right after the
 * anonymous gate and before the parse and the quota charge.
 */
jest.mock("firebase-admin", () => require("./support/fakes").adminMock());
jest.mock("firebase-functions/logger", () => require("./support/fakes").loggerMock());

import * as logger from "firebase-functions/logger";
import {
  ACT, ACT_2, T0, UID, UID_B, callReq, createWorld, expectHttpsError, loggedText, releaseClock, resetAll, rowOf,
  seedReady, settingsOf, store, useClock, usageOf, writes, timeline, type World,
} from "./support/fakes";
import { SEVEN, prime, type Primed } from "./support/seven";

import { handleCommitActivityStream } from "../../activity_streams/commit_stream";
import { handleCreateActivityStreamUpload } from "../../activity_streams/create_upload";
import { handleDeleteActivity } from "../../activity_streams/delete_activity";
import { handleSetActivityCloudSettings } from "../../activity_streams/set_settings";
import { commitActivityStream } from "../../activity_streams/commit_stream";
import { createActivityStreamUpload } from "../../activity_streams/create_upload";
import { deleteActivity } from "../../activity_streams/delete_activity";
import { setActivityCloudSettings } from "../../activity_streams/set_settings";

/* eslint-disable @typescript-eslint/no-explicit-any */
let w: World;
let p: Primed;
beforeEach(async () => {
  resetAll();
  useClock(T0);
  w = createWorld();
  seedReady();
  p = await prime(w);
  seedReady(UID, ACT_2); // the create body targets ACT_2; seeding here keeps every body() free of side effects
});
afterEach(() => releaseClock());

type Raw = (w: World, uid: string, provider: string, data: unknown) => Promise<any>;
interface Case {
  name: string;
  action: string;
  raw: Raw;
  /** A valid request body WITHOUT the key. */
  body(): Record<string, unknown>;
  /** A request that is invalid on its own (proves the key is checked before the parse). */
  invalidBody(): Record<string, unknown>;
  /** Asserts the success effect of a matching-key call. */
  proof(res: any): void;
  onCall: unknown;
}

const CASES: Case[] = [
  {
    name: "createActivityStreamUpload", action: "activityStreamUpload",
    raw: (x, uid, prov, d) => handleCreateActivityStreamUpload(x.deps, uid, prov, d),
    body: () => ({ activityId: ACT_2, bytes: 10, contentSha256: "a".repeat(64) }),
    invalidBody: () => ({ activityId: "not-an-id", bytes: -1, contentSha256: "zz" }),
    proof: (res) => { expect(res.status).toBe("upload"); expect(rowOf(UID, ACT_2)).toBeDefined(); },
    onCall: createActivityStreamUpload,
  },
  {
    name: "commitActivityStream", action: "activityStreamCommit",
    raw: (x, uid, prov, d) => handleCommitActivityStream(x.deps, uid, prov, d),
    body: () => ({ activityId: ACT, uploadId: p.uploadId }),
    invalidBody: () => ({ activityId: "not-an-id", uploadId: 7 }),
    proof: (res) => { expect(res).toBeDefined(); expect(rowOf(UID, ACT)).toBeDefined(); },
    onCall: commitActivityStream,
  },
  {
    name: "deleteActivity", action: "activityDelete",
    raw: (x, uid, prov, d) => handleDeleteActivity(x.deps, uid, prov, d),
    body: () => ({ activityId: ACT_2 }),
    invalidBody: () => ({ activityId: "not-an-id" }),
    proof: (res) => { expect(res.deleted).toBe(true); expect(store.has(`users/${UID}/activity_tombstones/${ACT_2}`)).toBe(true); },
    onCall: deleteActivity,
  },
  {
    name: "setActivityCloudSettings", action: "activitySettingsSet",
    raw: (x, uid, prov, d) => handleSetActivityCloudSettings(x.deps, uid, prov, d),
    body: () => ({ streamRetentionDays: 90 }),
    invalidBody: () => ({ streamRetentionDays: "forever", bogus: 1 }),
    proof: () => { expect(settingsOf(UID).streamRetentionDays).toBe(90); },
    onCall: setActivityCloudSettings,
  },
];

const snapshot = (): string => JSON.stringify([...store.entries()]);
interface Marks { state: string; writes: number; timeline: number; bucket: number; lookups: number }
const mark = (): Marks => ({
  state: snapshot(), writes: writes.length, timeline: timeline.length, bucket: w.bucket.totalCalls, lookups: w.auth.lookups,
});
const expectUntouched = (m: Marks, action: string): void => {
  expect(writes.length).toBe(m.writes);
  expect(timeline.length).toBe(m.timeline);
  expect(snapshot()).toBe(m.state);
  expect(w.bucket.totalCalls).toBe(m.bucket);
  expect(w.auth.lookups).toBe(m.lookups);
  expect(usageOf(UID, action)).toBe(0);
  expect(usageOf(UID_B, action)).toBe(0);
};
const names = CASES.map((c) => [c.name] as const);
const by = (n: string): Case => CASES.find((c) => c.name === n)!;

describe("J1 account_changed: mismatch is refused before anything happens", () => {
  test.each(names)("%s: failed-precondition / account_changed, no write, no quota document, no storage or auth call, log without uid", async (name) => {
    const c = by(name);
    const body = c.body();
    const m = mark();
    (logger.warn as jest.Mock).mockClear();
    const err = await expectHttpsError(c.raw(w, UID, "password", { ...body, expectedUid: UID_B }), "failed-precondition", "account_changed");
    expect(err.message).toBe("account_changed");
    expectUntouched(m, c.action);
    const text = loggedText(logger);
    expect(text).toContain('"outcome":"account_changed"');
    expect((logger.warn as jest.Mock).mock.calls.some((x) => JSON.stringify(x).includes('"outcome":"account_changed"'))).toBe(true);
    expect(text).not.toContain(UID);
    expect(text).not.toContain(UID_B);
    expect(text).not.toContain(ACT);
    expect(text).not.toContain(ACT_2);
  });

  test.each(names)("%s: a case-different key is a mismatch, not a pass", async (name) => {
    const c = by(name);
    const m = mark();
    await expectHttpsError(c.raw(w, UID, "password", { ...c.body(), expectedUid: UID.toUpperCase() }), "failed-precondition", "account_changed");
    expectUntouched(m, c.action);
  });

  test.each(names)("%s: the mismatch wins over an invalid rest of the request (runs before the parse)", async (name) => {
    const c = by(name);
    const m = mark();
    await expectHttpsError(c.raw(w, UID, "password", { ...c.invalidBody(), expectedUid: UID_B }), "failed-precondition", "account_changed");
    expectUntouched(m, c.action);
  });

  test.each(names)("%s: the mismatch wins over an exhausted quota and does not touch the counter (runs before the charge)", async (name) => {
    const c = by(name);
    const limit = SEVEN.find((e) => e.name === name)!.limit;
    const day = `users/${UID}/usage/2026-10-15`;
    store.set(day, { [c.action]: limit });
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
    await expectHttpsError(c.raw(w, UID, "anonymous", { ...c.body(), expectedUid: UID_B }), "permission-denied", "anonymous_not_allowed");
    expectUntouched(m, c.action);
  });
});

describe("J1 malformed or missing key: the existing invalid-request error", () => {
  const BAD: Array<[string, unknown, boolean]> = [
    ["missing", undefined, false],
    ["null", null, true],
    ["number", 5, true],
    ["object", { uid: UID }, true],
    ["empty string", "", true],
    ["129 characters", "u".repeat(129), true],
  ];
  for (const [label, value, present] of BAD) {
    test.each(names)(`%s: ${label} key -> invalid-argument / invalid_request, no charge, no write, no storage call`, async (name) => {
      const c = by(name);
      const body = c.body();
      const m = mark();
      const data = present ? { ...body, expectedUid: value } : body;
      const err = await expectHttpsError(c.raw(w, UID, "password", data), "invalid-argument", "invalid_request");
      expect(err.message).toBe("invalid_request");
      expectUntouched(m, c.action);
    });
  }

  test.each(names)("%s: non-object data keeps the existing invalid_request error, with no charge and no write", async (name) => {
    const c = by(name);
    for (const data of [null, undefined, [], [{ expectedUid: UID }], "x", 5]) {
      const m = mark();
      await expectHttpsError(c.raw(w, UID, "password", data), "invalid-argument", "invalid_request");
      expectUntouched(m, c.action);
    }
  });
});

describe("J1 matching key: the success path and the strict parser", () => {
  test.each(names)("%s: a matching key reaches the handler, charges exactly once and has the normal effect", async (name) => {
    const c = by(name);
    const body = c.body();
    const res = await c.raw(w, UID, "password", { ...body, expectedUid: UID });
    c.proof(res);
    expect(usageOf(UID, c.action)).toBe(1);
  });

  test("settings: the strict parser still refuses an unknown extra key with a valid expectedUid, and nothing is charged or written", async () => {
    const c = by("setActivityCloudSettings");
    const m = mark();
    await expectHttpsError(c.raw(w, UID, "password", { ...c.body(), uid: UID_B, expectedUid: UID }), "invalid-argument", "invalid_request");
    expectUntouched(m, c.action);
  });

  // create, commit and delete use lenient parsers (existing F60 behavior: client path fields are ignored, never used).
  // The binding key must not change that: the extra key is dropped and the normal effect happens for the caller's uid only.
  test.each([["createActivityStreamUpload"], ["commitActivityStream"], ["deleteActivity"]] as const)(
    "%s: with a valid expectedUid an extra client uid key is ignored, never used as the account", async (name) => {
      const c = by(name);
      const res = await c.raw(w, UID, "password", { ...c.body(), uid: UID_B, expectedUid: UID });
      c.proof(res);
      expect([...store.keys()].some((k) => k.includes(UID_B))).toBe(false);
    });

  test("settings: { streamRetentionDays: 90, uid, expectedUid } is invalid_request and the settings stay unchanged", async () => {
    const before = JSON.stringify(settingsOf(UID));
    await expectHttpsError(
      handleSetActivityCloudSettings(w.deps, UID, "password", { streamRetentionDays: 90, uid: UID_B, expectedUid: UID }),
      "invalid-argument", "invalid_request",
    );
    expect(JSON.stringify(settingsOf(UID))).toBe(before);
  });

  test.each(names)("%s: the key is checked against the caller uid, so a caller as UID_B with UID's key is a mismatch", async (name) => {
    const c = by(name);
    const m = mark();
    await expectHttpsError(c.raw(w, UID_B, "password", { ...c.body(), expectedUid: UID }), "failed-precondition", "account_changed");
    expect(w.bucket.totalCalls).toBe(m.bucket);
    expect(usageOf(UID_B, c.action)).toBe(0);
    expect(usageOf(UID, c.action)).toBe(0);
  });
});

describe("J1 onCall wrapper", () => {
  test.each(names)("%s: a missing request.auth is refused as unauthenticated before the handler", async (name) => {
    const c = by(name);
    const m = mark();
    await expectHttpsError((c.onCall as any).run(callReq({ ...c.body(), expectedUid: UID }, null)), "unauthenticated", "sign_in_required");
    expectUntouched(m, c.action);
  });
});
