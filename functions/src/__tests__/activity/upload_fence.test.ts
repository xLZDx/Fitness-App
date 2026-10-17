/** F44 create preconditions, fence and tombstone in the transaction; F87 already-due expiry; F45 state. */
jest.mock("firebase-admin", () => require("./support/fakes").adminMock());
jest.mock("firebase-functions/logger", () => require("./support/fakes").loggerMock());

import * as logger from "firebase-functions/logger";
import {
  ACT, DAY, T0, UID, createWorld, expectHttpsError, fx, loggedText, releaseClock, resetAll, rowOf, seedConsent,
  seedReady, seedSummary, setNow, store, ts, uploadOf, usageOf, useClock, validPayload, writes, type World,
} from "./support/fakes";
import { create, fullUpload, stage } from "./support/flow";

let w: World;
beforeEach(() => {
  resetAll();
  useClock(T0);
  w = createWorld();
  seedReady();
});
afterEach(() => releaseClock());

const up = uploadOf();
const req = (o: Record<string, unknown> = {}) => ({ activityId: ACT, bytes: up.bytes.length, contentSha256: up.sha, ...o });
const nothingIssued = (): void => {
  expect(w.bucket.signed).toEqual([]);
  expect(rowOf(UID, ACT)).toBeUndefined();
  expect(w.bucket.keys()).toEqual([]);
};

describe("F44 refusals are bare codes with no URL, no row, no quarantine path", () => {
  const cases: Array<[string, () => void, string, string]> = [
    ["accountDeletionRetries exists", () => store.set(`accountDeletionRetries/${UID}`, { n: 1 }), "failed-precondition", "account_deleting"],
    ["activity_account_state exists", () => store.set(`activity_account_state/${UID}`, { fenceAt: ts(T0) }), "failed-precondition", "account_deleting"],
    ["Auth user gone while the fence document is absent", () => w.auth.users.delete(UID), "unauthenticated", "account_deleted"],
    ["tombstone present", () => store.set(`users/${UID}/activity_tombstones/${ACT}`, { deletedAt: ts(T0) }), "failed-precondition", "deleted"],
    ["no summary", () => store.delete(`users/${UID}/activities/${ACT}`), "failed-precondition", "no_summary"],
    ["consent withdrawn", () => seedConsent(UID, { cloudStreams: { version: 1, acceptedAt: ts(T0 - DAY), withdrawnAt: ts(T0 - 1000) } }), "failed-precondition", "consent_withdrawn"],
    ["consent absent", () => store.delete(`users/${UID}/activity_settings/main`), "failed-precondition", "consent_required"],
    ["expiry already due", () => seedSummary(UID, ACT, T0 - 731 * DAY), "failed-precondition", "already_expired"],
  ];
  test.each(cases)("%s", async (_n, arrange, code, message) => {
    arrange();
    const err = await expectHttpsError(create(w, req()), code, message);
    expect(err.message).toBe(message);
    expect(err.message).not.toContain(UID);
    expect(err.message).not.toContain(ACT);
    nothingIssued();
  });
  test("control: all clear yields a URL", async () => {
    const r = await create(w, req());
    expect(r.status).toBe("upload");
    expect(w.bucket.signed).toHaveLength(1);
  });
  test("a fence refusal returns the quota charge (nothing was written)", async () => {
    store.set(`activity_account_state/${UID}`, { fenceAt: ts(T0) });
    await expectHttpsError(create(w, req()), "failed-precondition", "account_deleting");
    expect(usageOf(UID, "activityStreamUpload")).toBe(0);
  });
  test("a write to the fence by a second actor between the transaction's reads and its commit refuses (no URL)", async () => {
    let fired = false;
    fx.afterTxRead = async (path) => {
      if (!fired && path === `activity_account_state/${UID}`) {
        fired = true;
        store.set(`activity_account_state/${UID}`, { fenceAt: ts(T0) });
      }
    };
    await expectHttpsError(create(w, req()), "failed-precondition", "account_deleting");
    expect(fired).toBe(true);
    expect(fx.txRetries).toBeGreaterThanOrEqual(1);
    nothingIssued();
  });
  test("a tombstone created between the transaction's reads and its commit refuses (no URL)", async () => {
    let fired = false;
    fx.afterTxRead = async (path) => {
      if (!fired && path === `users/${UID}/activity_tombstones/${ACT}`) {
        fired = true;
        store.set(path, { deletedAt: ts(T0) });
      }
    };
    await expectHttpsError(create(w, req()), "failed-precondition", "deleted");
    nothingIssued();
  });
  test("a transient Auth lookup failure fails closed with a bare code, not a URL", async () => {
    w.auth.lookupError = Object.assign(new Error("net down for uid_alice_1"), { code: "auth/internal-error" });
    const err = await expectHttpsError(create(w, req()), "internal", "upload_failed");
    expect(err.message).not.toContain(UID);
    nothingIssued();
  });
});

describe("F87 already-due expiry is refused at create", () => {
  test("expiry == now is refused with the bare code, no row, no URL, no attempt counted", async () => {
    seedSummary(UID, ACT, T0 - 730 * DAY);
    await expectHttpsError(create(w, req()), "failed-precondition", "already_expired");
    nothingIssued();
  });
  test("expiry == now + 1 ms succeeds (boundary on the other side)", async () => {
    seedSummary(UID, ACT, T0 - 730 * DAY + 1);
    expect((await create(w, req())).status).toBe("upload");
    expect(rowOf(UID, ACT).attempts).toBe(1);
  });
  test("the 90 day setting makes an older activity due", async () => {
    seedConsent(UID, { streamRetentionDays: 90 });
    seedSummary(UID, ACT, T0 - 91 * DAY);
    await expectHttpsError(create(w, req()), "failed-precondition", "already_expired");
    seedSummary(UID, ACT, T0 - 89 * DAY);
    expect((await create(w, req())).status).toBe("upload");
  });
  test("a stored null (never is not offered) counts as the 730 day default: a 1990 activity is already due, one 729 days old is not", async () => {
    seedConsent(UID, { streamRetentionDays: null });
    seedSummary(UID, ACT, Date.UTC(1990, 0, 1));
    await expectHttpsError(create(w, req()), "failed-precondition", "already_expired");
    nothingIssued();
    seedSummary(UID, ACT, T0 - 729 * DAY);
    expect((await create(w, req())).status).toBe("upload");
  });
  test("a future startUtc is clamped to now (not due, expiry = now + retention)", async () => {
    seedSummary(UID, ACT, T0 + 400 * DAY);
    expect((await create(w, req())).status).toBe("upload");
  });
});

describe("F45 idempotency, attempt cap, supersede", () => {
  test("stored row with the same hash: already_stored, no URL, no new row write", async () => {
    const f = await fullUpload(w);
    const n = writes.filter((x) => x.path.includes("/activity_streams/")).length;
    const signed = w.bucket.signed.length;
    const r = await create(w, req({ bytes: f.up.bytes.length, contentSha256: f.up.sha.toUpperCase() }));
    expect(r.status).toBe("already_stored");
    expect(w.bucket.signed.length).toBe(signed);
    expect(writes.filter((x) => x.path.includes("/activity_streams/")).length).toBe(n);
  });
  test("stored row with a different hash gets a pending upload marker and STAYS stored (design 5.2; the plan text 'creates a pending row' is superseded)", async () => {
    await fullUpload(w);
    const p2 = validPayload();
    p2.kinds.altitude.values = [99, 100];
    const u2 = uploadOf(p2);
    const r = await create(w, req({ bytes: u2.bytes.length, contentSha256: u2.sha }));
    expect(r.status).toBe("upload");
    const row = rowOf(UID, ACT);
    expect(row.state).toBe("stored");
    expect(row.pendingUploadId).toBe(r.uploadId);
    expect(row.pendingContentSha256).toBe(u2.sha);
    expect(row.pendingSince.toMillis()).toBe(T0);
  });
  test("pending row fields: state, uploadId, contentSha256, pendingSince, attempts, attemptsDay", async () => {
    const r = await create(w, req());
    expect(rowOf(UID, ACT)).toMatchObject({
      state: "pending", uploadId: r.uploadId, contentSha256: up.sha, attempts: 1, attemptsDay: "2026-10-15",
    });
    expect(rowOf(UID, ACT).pendingSince.toMillis()).toBe(T0);
  });
  test("5 creates of the day succeed, the 6th is too_many_attempts, the next UTC day restarts at 1", async () => {
    for (let i = 1; i <= 5; i++) expect((await create(w, req())).status).toBe("upload");
    expect(rowOf(UID, ACT).attempts).toBe(5);
    const signed = w.bucket.signed.length;
    await expectHttpsError(create(w, req()), "resource-exhausted", "too_many_attempts");
    expect(w.bucket.signed.length).toBe(signed);
    expect(rowOf(UID, ACT).attempts).toBe(5);

    setNow(T0 + DAY); // 2026-10-16T12:00Z
    expect((await create(w, req())).status).toBe("upload");
    expect(rowOf(UID, ACT)).toMatchObject({ attempts: 1, attemptsDay: "2026-10-16" });
    for (let i = 2; i <= 5; i++) await create(w, req());
    await expectHttpsError(create(w, req()), "resource-exhausted", "too_many_attempts");
  });
  test("a row whose attemptsDay is yesterday is not refused", async () => {
    store.set(`users/${UID}/activity_streams/${ACT}`, { state: "pending", uploadId: "up_" + "0".repeat(32), attempts: 5, attemptsDay: "2026-10-14" });
    expect((await create(w, req())).status).toBe("upload");
    expect(rowOf(UID, ACT).attempts).toBe(1);
  });
  test("a new create supersedes the older pending upload and deletes its quarantine object", async () => {
    const a = await stage(w);
    const aPath = `quarantine/${UID}/${ACT}/${a.uploadId}`;
    expect(w.bucket.objects.has(aPath)).toBe(true);
    const b = await create(w, req());
    expect(w.bucket.objects.has(aPath)).toBe(false);
    expect(rowOf(UID, ACT).uploadId).toBe(b.uploadId);
    expect(b.uploadId).not.toBe(a.uploadId);
  });
  test("a failing supersede cleanup does not fail the create (the reconciler is the backstop)", async () => {
    const a = await stage(w);
    w.bucket.failOn = (op, path) => (op === "delete" && path.includes(a.uploadId) ? Object.assign(new Error("x"), { code: 500 }) : undefined);
    expect((await create(w, req())).status).toBe("upload");
    expect((logger.warn as jest.Mock).mock.calls.length).toBeGreaterThan(0);
    expect(loggedText(logger)).not.toContain(UID);
  });
});
