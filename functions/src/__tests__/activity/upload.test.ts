/** F07-F12: create/commit preconditions, signed URL, happy path, retry, cross-user, bucket isolation. */
jest.mock("firebase-admin", () => require("./support/fakes").adminMock());
jest.mock("firebase-functions/logger", () => require("./support/fakes").loggerMock());

import { activityStreamBucketName } from "../../activity_streams/flags";
import { createActivityStreamUpload } from "../../activity_streams/create_upload";
import { MAX_COMPRESSED_BYTES } from "../../activity_streams/schema";
import { activityDateMs, derivedExpiryMs } from "../../activity_streams/upload_common";
import {
  ACT, DAY, T0, UID, UID_B, callReq, createWorld, expectHttpsError, quarantinePath, releaseClock,
  resetAll, rowOf, seedConsent, seedReady, seedSummary, sha, store, streamPath, ts, uploadIdN, uploadOf,
  useClock, validPayload, writes, type World,
} from "./support/fakes";
import { commit, create, fullUpload, stage } from "./support/flow";

let w: World;
beforeEach(() => {
  resetAll();
  useClock(T0);
  w = createWorld();
  seedReady();
});
afterEach(() => releaseClock());

const req = (o: Record<string, unknown> = {}) => {
  const up = uploadOf();
  return { activityId: ACT, bytes: up.bytes.length, contentSha256: up.sha, ...o };
};
const nothingCreated = (): void => {
  expect(w.bucket.signed).toEqual([]);
  expect(rowOf(UID, ACT)).toBeUndefined();
  expect(w.bucket.keys()).toEqual([]);
};

describe("F07 preconditions: each refusal yields no URL, no row, no quarantine path", () => {
  test("unauthenticated is refused by the callable itself", async () => {
    await expectHttpsError((createActivityStreamUpload as any).run(callReq(req(), null)), "unauthenticated");
    nothingCreated();
  });
  test("anonymous users are refused", async () => {
    await expectHttpsError(create(w, req(), UID, "anonymous"), "permission-denied");
    nothingCreated();
  });
  test("bucket unset (feature off) is refused", async () => {
    w.bucketOn = false;
    await expectHttpsError(create(w, req()), "failed-precondition");
    nothingCreated();
  });
  test("no cloudStreams consent: settings document absent -> consent_required", async () => {
    store.delete(`users/${UID}/activity_settings/main`);
    await expectHttpsError(create(w, req()), "failed-precondition", "consent_required");
    nothingCreated();
  });
  test("settings document without cloudStreams -> consent_required", async () => {
    store.set(`users/${UID}/activity_settings/main`, { settingsGeneration: 1 });
    await expectHttpsError(create(w, req()), "failed-precondition", "consent_required");
    nothingCreated();
  });
  test("no summary document -> no_summary", async () => {
    store.delete(`users/${UID}/activities/${ACT}`);
    await expectHttpsError(create(w, req()), "failed-precondition", "no_summary");
    nothingCreated();
  });
  test.each([
    ["not a string", 5], ["empty", ""], ["path traversal", "act_x/../y"], ["uppercase", `act_${"A".repeat(40)}`],
  ])("bad activityId (%s) -> invalid_request", async (_n, id) => {
    await expectHttpsError(create(w, req({ activityId: id })), "invalid-argument", "invalid_request");
    nothingCreated();
  });
  test.each([
    ["over the limit", MAX_COMPRESSED_BYTES + 1], ["zero", 0], ["fraction", 1.5], ["string", "100"],
  ])("declared bytes %s -> invalid_request", async (_n, bytes) => {
    await expectHttpsError(create(w, req({ bytes })), "invalid-argument", "invalid_request");
    nothingCreated();
  });
  test("control: a fully valid request yields a URL and a pending row", async () => {
    const r = await create(w, req());
    expect(r.status).toBe("upload");
    expect(w.bucket.signed).toHaveLength(1);
    expect(rowOf(UID, ACT).state).toBe("pending");
  });
});

describe("F08 signed URL parameters", () => {
  test("PUT, application/gzip, length-range header, 10 minute TTL, caller-scoped quarantine path", async () => {
    const up = uploadOf();
    const r = await create(w, { activityId: ACT, bytes: up.bytes.length, contentSha256: up.sha });
    expect(r.uploadId).toBe(uploadIdN(1));
    expect(w.bucket.signed).toHaveLength(1);
    const s = w.bucket.signed[0];
    expect(s.path).toBe(quarantinePath(UID, ACT, r.uploadId));
    expect(s.config.version).toBe("v4");
    expect(s.config.action).toBe("write");
    expect(s.config.contentType).toBe("application/gzip");
    expect(s.config.expires).toBe(T0 + 10 * 60 * 1000);
    expect(s.config.extensionHeaders).toEqual({ "x-goog-content-length-range": `${up.bytes.length},${up.bytes.length}` });
    expect(r.expiresAtMs).toBe(T0 + 600_000);
    expect(r.headers).toEqual({ "Content-Type": "application/gzip", "x-goog-content-length-range": `${up.bytes.length},${up.bytes.length}` });
    expect(r.url).toContain("signed");
  });
  test("the path is never built from a client value (other uid, path, objectPath ignored)", async () => {
    await create(w, req({ uid: UID_B, path: "evil/x", objectPath: "evil/y", bucket: "other", prefix: "z/" }));
    expect(w.bucket.signed[0].path).toBe(quarantinePath(UID, ACT, uploadIdN(1)));
  });
});

describe("F09 commit happy path", () => {
  test("object at the uploadId path, row stored with the right fields, no quarantine left", async () => {
    const { uploadId, up, result } = await fullUpload(w);
    expect(result.status).toBe("stored");
    expect(w.bucket.keys()).toEqual([streamPath(UID, ACT, uploadId)]);
    const obj = w.bucket.objects.get(streamPath(UID, ACT, uploadId))!;
    const row = rowOf(UID, ACT);
    expect(row.state).toBe("stored");
    expect(row.objectPath).toBe(streamPath(UID, ACT, uploadId));
    expect(row.uploadId).toBe(uploadId);
    expect(row.contentSha256).toBe(up.sha);
    expect(row.storedSha256).toBe(sha(obj.content));
    expect(row.bytes).toBe(obj.content.length);
    expect(row.kinds).toEqual(["gps", "altitude", "speed"]);
    expect(row.settingsGeneration).toBe(1);
    expect(row.expiresAt.toMillis()).toBe(T0 - 2 * DAY + 730 * DAY);
    expect(row.activityDateUtc.toMillis()).toBe(T0 - 2 * DAY);
    for (const k of ["pendingUploadId", "pendingSince", "pendingContentSha256", "intendedStoredSha256"]) {
      expect(row).not.toHaveProperty(k);
    }
    expect(obj.contentType).toBe("application/gzip");
  });
  test("the expiry hint uses the summary startUtc clamped to [2000-01-01, now], never a client value", async () => {
    // Lower clamp (a 1990 activity is already due at create, so it is checked on the arithmetic).
    expect(derivedExpiryMs(Date.UTC(1990, 0, 1), 730, T0)).toBe(Date.UTC(2000, 0, 1) + 730 * DAY);
    expect(activityDateMs(Date.UTC(1990, 0, 1), T0)).toBe(Date.UTC(2000, 0, 1));
    seedSummary(UID, ACT, T0 + 5 * DAY);
    await fullUpload(w);
    expect(rowOf(UID, ACT).expiresAt.toMillis()).toBe(T0 + 730 * DAY);
  });
  test("a retention of 90 days and a null (never) setting are applied to the hint", async () => {
    seedConsent(UID, { streamRetentionDays: 90, settingsGeneration: 4 });
    await fullUpload(w);
    expect(rowOf(UID, ACT).expiresAt.toMillis()).toBe(T0 - 2 * DAY + 90 * DAY);
    expect(rowOf(UID, ACT).settingsGeneration).toBe(4);
    resetAll();
    w = createWorld();
    seedReady();
    seedConsent(UID, { streamRetentionDays: null });
    await fullUpload(w);
    expect(rowOf(UID, ACT).expiresAt).toBeNull();
  });
});

describe("F10 retry and duplicate upload", () => {
  test("a second commit of the same upload id returns success and changes nothing", async () => {
    const { uploadId } = await fullUpload(w);
    const rowWrites = () => writes.filter((x) => x.path.includes("/activity_streams/")).length;
    const before = rowWrites();
    const calls = w.bucket.totalCalls;
    const again = await commit(w, { activityId: ACT, uploadId });
    expect(again.status).toBe("already_stored");
    expect(rowWrites()).toBe(before);
    expect(w.bucket.totalCalls).toBe(calls);
    expect(w.bucket.keys()).toEqual([streamPath(UID, ACT, uploadId)]);
  });
  test("a second create with the same hash is already_stored with no URL", async () => {
    const { up } = await fullUpload(w);
    const signed = w.bucket.signed.length;
    const r = await create(w, { activityId: ACT, bytes: up.bytes.length, contentSha256: up.sha });
    expect(r.status).toBe("already_stored");
    expect(r).not.toHaveProperty("url");
    expect(w.bucket.signed.length).toBe(signed);
  });
  test("a second upload with different content ends with ONE object and ONE row", async () => {
    await fullUpload(w);
    const p2 = validPayload();
    p2.kinds.speed.values = [3, 4];
    const second = await fullUpload(w, p2);
    expect(w.bucket.keys()).toEqual([streamPath(UID, ACT, second.uploadId)]);
    expect([...store.keys()].filter((k) => k.includes("/activity_streams/"))).toHaveLength(1);
    expect(rowOf(UID, ACT).uploadId).toBe(second.uploadId);
  });
});

describe("F11 cross-user", () => {
  test("user B cannot commit user A's upload id and A's data is untouched", async () => {
    seedReady(UID_B, ACT);
    const a = await stage(w);
    const rowA = JSON.stringify(rowOf(UID, ACT));
    await expectHttpsError(commit(w, { activityId: ACT, uploadId: a.uploadId }, UID_B), "aborted", "superseded");
    expect(JSON.stringify(rowOf(UID, ACT))).toBe(rowA);
    expect(w.bucket.keys()).toEqual([quarantinePath(UID, ACT, a.uploadId)]);
    expect(rowOf(UID_B, ACT)).toBeUndefined();
  });
  test("even with B's own pending row, A's id is superseded and B's path is not A's", async () => {
    seedReady(UID_B, ACT);
    const a = await stage(w);
    const b = await stage(w, validPayload(), UID_B);
    expect(b.uploadId).not.toBe(a.uploadId);
    await expectHttpsError(commit(w, { activityId: ACT, uploadId: a.uploadId }, UID_B), "aborted", "superseded");
    expect(w.bucket.keys(`quarantine/${UID}/`)).toHaveLength(1);
    expect(w.bucket.keys(`streams/`)).toEqual([]);
  });
});

describe("F12 bucket isolation (064)", () => {
  const saved = { a: process.env.ACTIVITY_STREAM_BUCKET, b: process.env.BODY_SCAN_BUCKET };
  afterEach(() => {
    for (const [k, v] of [["ACTIVITY_STREAM_BUCKET", saved.a], ["BODY_SCAN_BUCKET", saved.b]] as const) {
      if (v === undefined) delete process.env[k]; else process.env[k] = v;
    }
  });
  test("equal to BODY_SCAN_BUCKET is treated as not configured", () => {
    process.env.BODY_SCAN_BUCKET = "shared-bucket-name";
    process.env.ACTIVITY_STREAM_BUCKET = "shared-bucket-name";
    expect(activityStreamBucketName()).toBeUndefined();
  });
  test("unset or malformed is not configured; a distinct valid name is returned", () => {
    process.env.BODY_SCAN_BUCKET = "body-bucket";
    delete process.env.ACTIVITY_STREAM_BUCKET;
    expect(activityStreamBucketName()).toBeUndefined();
    process.env.ACTIVITY_STREAM_BUCKET = "Bad Name!";
    expect(activityStreamBucketName()).toBeUndefined();
    process.env.ACTIVITY_STREAM_BUCKET = "activity-bucket";
    expect(activityStreamBucketName()).toBe("activity-bucket");
  });
});

describe("F10/F11 attribution sanity", () => {
  test("created rows carry no uid or path of the caller beyond their own document", async () => {
    await create(w, req());
    expect(JSON.stringify(rowOf(UID, ACT))).not.toContain(UID);
    expect(ts(0).toMillis()).toBe(0);
  });
});
