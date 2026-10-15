/**
 * `createBodyScan` (design s7.1, D-53, D-58, D-59): validation, server-derived
 * age, tier gate, consent, idempotency, quota accounting and signed upload URLs.
 *
 * Firestore and Storage are the stateful doubles in `./fakes` (the same model as
 * `account_deletion_reconcile.test.ts`), so assertions look at what is stored
 * and charged, not at which mock was called. The clock is a controllable
 * `Date.now` spy. Every test asserts a state that would differ if the guarded
 * behaviour were broken.
 */
jest.mock("firebase-admin", () => require("./fakes").adminMock());
jest.mock("firebase-admin/storage", () => require("./fakes").storageMock());
jest.mock("firebase-functions/logger", () => require("./fakes").loggerMock());
jest.mock("@google-cloud/secret-manager", () => require("./fakes").secretManagerMock());

import * as logger from "firebase-functions/logger";
import { createBodyScan } from "../../body_scan/create";
import { __setTestEstimatorForTests } from "../../body_scan/estimator";
import { deleteFenceRef } from "../../body_scan/shared";
import { __resetAiGatewayControlCacheForTests } from "../../abuse_guard";
import {
  BUCKET, DAY, FakePhotoEstimator, MIN, T0, UID, SCAN,
  bodyScanEvents, callReq, expectHttpsError, firestoreError, fx, gcs, loggedText,
  resetFakes, scanDoc, seedEligibleUser, seedScan, store, timeline, ts, usageOf, writes,
} from "./fakes";

let now = T0;
let dateSpy: jest.SpyInstance;
let fake: FakePhotoEstimator;

const run = (data: unknown, uid: string | null = UID): Promise<any> =>
  (createBodyScan as any).run(callReq(data, uid));

/** A fully valid request; `o` overrides top-level keys. */
const valid = (o: Record<string, unknown> = {}): any => ({
  scanId: SCAN,
  takenAtMs: now - 1000,
  subject: { sexAtBirth: "female", heightCm: 170, weightKg: 65.5, ageYears: 25 },
  capture: { manualOverride: { front: false, side: true, back: false } },
  ...o,
});
const withSubject = (s: Record<string, unknown>): any =>
  valid({ subject: { ...valid().subject, ...s } });

const SCAN_PATH = `users/${UID}/body_scans/${SCAN}`;
const scanWrites = (): typeof writes => writes.filter((w) => w.path === SCAN_PATH);
const nothingCreated = (): void => {
  expect(scanDoc(UID, SCAN)).toBeUndefined();
  expect(scanWrites()).toEqual([]);
  expect(gcs.signed).toEqual([]);
  expect(usageOf(UID, "bodyScanCreate")).toBe(0);
};

beforeEach(() => {
  resetFakes();
  now = T0;
  dateSpy = jest.spyOn(Date, "now").mockImplementation(() => now);
  for (const level of ["debug", "info", "warn", "error"] as const) (logger[level] as jest.Mock).mockClear();
  __resetAiGatewayControlCacheForTests();
  process.env.BODY_SCAN_BUCKET = BUCKET;
  process.env.BODY_SCAN_PROVIDER = "test-fake";
  fake = new FakePhotoEstimator();
  __setTestEstimatorForTests(fake);
  seedEligibleUser();
});

afterEach(() => {
  dateSpy.mockRestore();
});

afterAll(() => {
  __setTestEstimatorForTests(undefined);
  delete process.env.BODY_SCAN_BUCKET;
  delete process.env.BODY_SCAN_PROVIDER;
});

describe("happy path", () => {
  test("creates a pending scan, charges one quota unit and signs three PUT URLs", async () => {
    const res = await run(valid());

    expect(res.scanId).toBe(SCAN);
    expect(res.status).toBe("pending");
    expect(res.serverNowMs).toBe(now);
    expect(res.provider).toEqual({ id: "test-fake", version: "1.2.3", provisional: false, requiresPhotos: true });
    expect(Object.keys(res.uploads).sort()).toEqual(["back", "front", "side"]);
    for (const pose of ["front", "side", "back"]) {
      expect(res.uploads[pose].url).toMatch(/^https:\/\/signed\.invalid\//);
      expect(res.uploads[pose].expiresAtMs).toBe(now + 10 * MIN);
      expect(res.uploads[pose].headers).toEqual({
        "Content-Type": "image/jpeg",
        "x-goog-content-length-range": "1024,3145728",
      });
    }
    // Three distinct URLs (one per object).
    expect(new Set(Object.values<any>(res.uploads).map((u) => u.url)).size).toBe(3);

    const doc = scanDoc(UID, SCAN)!;
    expect(doc).toEqual({
      schema: 1,
      createdAt: ts(now),
      takenAt: ts(now - 1000),
      weightKg: 65.5,
      status: "pending",
      pendingExpiresAt: ts(now + 48 * 60 * MIN),
      // The server-derived age (2026 - 1990 - 1), NOT the client's 25.
      subject: { sexAtBirth: "female", ageYears: 35, heightCm: 170, weightKg: 65.5 },
      capture: { manualOverride: { front: false, side: true, back: false }, poses: ["front", "side", "back"] },
      provider: { id: "test-fake", version: "1.2.3", provisional: false, requiresPhotos: true },
      photosState: "awaiting_upload",
      purgeAttempts: 0,
    });
    expect(usageOf(UID, "bodyScanCreate")).toBe(1);
    // The document is created with `create` (never overwrites an existing scan).
    expect(scanWrites().map((w) => w.op)).toEqual(["create"]);
  });

  test("signed URL options: V4, write, 10 minutes, JPEG content type, size-range header, per-pose path in the configured bucket", async () => {
    await run(valid());

    expect(gcs.buckets.every((b) => b === BUCKET)).toBe(true);
    expect(gcs.signed.map((s) => s.path).sort()).toEqual([
      `users/${UID}/scans/${SCAN}/back.jpg`,
      `users/${UID}/scans/${SCAN}/front.jpg`,
      `users/${UID}/scans/${SCAN}/side.jpg`,
    ]);
    for (const s of gcs.signed) {
      expect(s.opts).toEqual({
        version: "v4",
        action: "write",
        expires: now + 10 * MIN,
        contentType: "image/jpeg",
        extensionHeaders: { "x-goog-content-length-range": "1024,3145728" },
      });
    }
  });

  test("the structured log carries the outcome and no uid, object path, URL or body metric", async () => {
    await run(valid());

    const events = bodyScanEvents(logger);
    expect(events).toHaveLength(1);
    expect(events[0]).toMatchObject({ operation: "bodyScanCreate", outcome: "created", providerId: "test-fake", providerVersion: "1.2.3" });
    const text = loggedText(logger);
    for (const secret of [UID, SCAN, "users/", "signed.invalid", "65.5", "170", "1990"]) {
      expect(text).not.toContain(secret);
    }
  });
});

describe("request validation (nothing is created, charged or signed on a bad request)", () => {
  const cases: Array<[string, unknown, string]> = [
    ["null body", null, "invalid-request"],
    ["array body", [valid()], "invalid-request"],
    ["string body", "scan", "invalid-request"],
    ["scanId missing", valid({ scanId: undefined }), "invalid-scan-id"],
    ["scanId number", valid({ scanId: 12345678 }), "invalid-scan-id"],
    ["scanId 7 chars", valid({ scanId: "abcdefg" }), "invalid-scan-id"],
    ["scanId 65 chars", valid({ scanId: "a".repeat(65) }), "invalid-scan-id"],
    ["scanId with a slash", valid({ scanId: "abcd/efgh" }), "invalid-scan-id"],
    ["scanId with a space", valid({ scanId: "abcd efgh" }), "invalid-scan-id"],
    ["scanId with dots", valid({ scanId: "..abcdef" }), "invalid-scan-id"],
    ["takenAtMs missing", valid({ takenAtMs: undefined }), "invalid-taken-at"],
    ["takenAtMs string", valid({ takenAtMs: String(T0) }), "invalid-taken-at"],
    ["takenAtMs NaN", valid({ takenAtMs: NaN }), "invalid-taken-at"],
    ["takenAtMs Infinity", valid({ takenAtMs: Infinity }), "invalid-taken-at"],
    ["takenAtMs 7 days + 1 ms back", valid({ takenAtMs: T0 - 7 * DAY - 1 }), "invalid-taken-at"],
    ["takenAtMs 5 minutes + 1 ms ahead", valid({ takenAtMs: T0 + 5 * MIN + 1 }), "invalid-taken-at"],
    ["subject missing", valid({ subject: undefined }), "invalid-subject"],
    ["subject array", valid({ subject: [] }), "invalid-subject"],
    ["sexAtBirth unknown", withSubject({ sexAtBirth: "other" }), "invalid-subject"],
    ["sexAtBirth missing", withSubject({ sexAtBirth: undefined }), "invalid-subject"],
    ["heightCm 119", withSubject({ heightCm: 119 }), "invalid-subject"],
    ["heightCm 231", withSubject({ heightCm: 231 }), "invalid-subject"],
    ["heightCm non-integer", withSubject({ heightCm: 170.5 }), "invalid-subject"],
    ["heightCm string", withSubject({ heightCm: "170" }), "invalid-subject"],
    ["weightKg 29.99", withSubject({ weightKg: 29.99 }), "invalid-subject"],
    ["weightKg 300.01", withSubject({ weightKg: 300.01 }), "invalid-subject"],
    ["weightKg NaN", withSubject({ weightKg: NaN }), "invalid-subject"],
    ["weightKg string", withSubject({ weightKg: "65" }), "invalid-subject"],
    ["capture missing", valid({ capture: undefined }), "invalid-capture"],
    ["manualOverride missing", valid({ capture: {} }), "invalid-capture"],
    ["manualOverride lacks a pose", valid({ capture: { manualOverride: { front: true, side: true } } }), "invalid-capture"],
    ["manualOverride pose is not boolean", valid({ capture: { manualOverride: { front: "yes", side: true, back: true } } }), "invalid-capture"],
    ["manualOverride is an array", valid({ capture: { manualOverride: [true, true, true] } }), "invalid-capture"],
  ];

  test.each(cases)("%s -> invalid-argument", async (_name, body, slug) => {
    await expectHttpsError(run(body), "invalid-argument", slug);
    nothingCreated();
  });

  test.each([
    ["heightCm 120", withSubject({ heightCm: 120 })],
    ["heightCm 230", withSubject({ heightCm: 230 })],
    ["weightKg 30", withSubject({ weightKg: 30 })],
    ["weightKg 300", withSubject({ weightKg: 300 })],
    ["sexAtBirth unspecified", withSubject({ sexAtBirth: "unspecified" })],
    ["scanId 8 chars", valid({ scanId: "abcd_fgh" })],
    ["scanId 64 chars with - and _", valid({ scanId: `${"a-_".repeat(21)}a` })],
  ])("boundary %s is accepted", async (_name, body) => {
    const res = await run(body);
    expect(res.status).toBe("pending");
    expect(usageOf(UID, "bodyScanCreate")).toBe(1);
  });

  test("takenAtMs window: exactly 7 days back is accepted and stored unchanged", async () => {
    await run(valid({ takenAtMs: T0 - 7 * DAY }));
    expect(scanDoc(UID, SCAN)!.takenAt).toEqual(ts(T0 - 7 * DAY));
  });

  test("takenAtMs up to 5 minutes ahead is accepted but clamped to the server time", async () => {
    await run(valid({ takenAtMs: T0 + 5 * MIN }));
    expect(scanDoc(UID, SCAN)!.takenAt).toEqual(ts(T0));
    expect(scanDoc(UID, SCAN)!.createdAt).toEqual(ts(T0));
  });

  test("unknown request keys are ignored and never stored", async () => {
    await run(valid({ isAdmin: true, subject: { ...valid().subject, ageYears: 99, bodyFatPct: 12 } }));
    const doc = scanDoc(UID, SCAN)!;
    expect(JSON.stringify(doc)).not.toContain("isAdmin");
    expect(JSON.stringify(doc)).not.toContain("bodyFatPct");
    expect(doc.subject).toEqual({ sexAtBirth: "female", ageYears: 35, heightCm: 170, weightKg: 65.5 });
  });
});

describe("server-derived age (D-58)", () => {
  test("the client ageYears is ignored: a 25 claim does not change the stored age", async () => {
    await run(withSubject({ ageYears: 25 }));
    expect(scanDoc(UID, SCAN)!.subject.ageYears).toBe(35);
  });

  test("a client claiming an adult age cannot rescue a minor profile", async () => {
    seedEligibleUser(UID, { birthYear: 2012 });
    await expectHttpsError(run(withSubject({ ageYears: 40 })), "failed-precondition", "age-required");
    nothingCreated();
  });

  test.each([
    ["no profile document", undefined],
    ["profile without personal", {}],
    ["birthYear missing", { personal: {} }],
    ["birthYear is a string", { personal: { birthYear: "1990" } }],
    ["birthYear is a float", { personal: { birthYear: 1990.5 } }],
    ["birthYear null", { personal: { birthYear: null } }],
  ])("%s -> age-required, nothing created or charged", async (_name, profile) => {
    if (profile === undefined) store.delete(`users/${UID}/profile/main`);
    else store.set(`users/${UID}/profile/main`, profile as any);
    await expectHttpsError(run(valid()), "failed-precondition", "age-required");
    nothingCreated();
  });

  test("lowestAgeAt boundary: in 2026 birth year 2007 (lowest age 18) passes, 2008 (17) is refused", async () => {
    seedEligibleUser(UID, { birthYear: 2007 });
    const ok = await run(valid());
    expect(ok.status).toBe("pending");
    expect(scanDoc(UID, SCAN)!.subject.ageYears).toBe(18);

    store.clear();
    seedEligibleUser(UID, { birthYear: 2008 });
    await expectHttpsError(run(valid()), "failed-precondition", "age-required");
  });

  test("lowestAgeAt is calendar-year based: the same birth year flips from refused (31 Dec 2026) to accepted (1 Jan 2027)", async () => {
    seedEligibleUser(UID, { birthYear: 2008 });
    now = Date.UTC(2026, 11, 31, 23, 59, 0);
    await expectHttpsError(run(valid({ takenAtMs: now - 1000 })), "failed-precondition", "age-required");
    now = Date.UTC(2027, 0, 1, 0, 1, 0);
    const res = await run(valid({ takenAtMs: now - 1000 }));
    expect(res.status).toBe("pending");
    expect(scanDoc(UID, SCAN)!.subject.ageYears).toBe(18);
  });

  test("implausible age: 120 is accepted, 121 is refused", async () => {
    seedEligibleUser(UID, { birthYear: 1905 });
    expect((await run(valid())).status).toBe("pending");
    expect(scanDoc(UID, SCAN)!.subject.ageYears).toBe(120);
    store.clear();
    seedEligibleUser(UID, { birthYear: 1904 });
    await expectHttpsError(run(valid()), "failed-precondition", "age-required");
  });
});

describe("tier gate (port of effectiveTier)", () => {
  const setSub = (sub: Record<string, unknown> | undefined): void => {
    if (sub === undefined) store.delete(`users/${UID}/subscription/main`);
    else store.set(`users/${UID}/subscription/main`, sub as any);
  };

  test.each([
    ["no subscription document", undefined],
    ["tier free", { tier: "free", status: "active" }],
    ["unknown tier (never a silent grant)", { tier: "platinum", status: "active" }],
    ["tier missing", { status: "active" }],
    ["tier not a string", { tier: 2, status: "active" }],
    ["unknown status", { tier: "standard", status: "paused" }],
    ["expired status", { tier: "standard", status: "expired" }],
    ["trial ended 1 ms ago", { tier: "standard", status: "trial", trialEndsAt: ts(T0 - 1) }],
    ["trial ended (ISO string)", { tier: "standard", status: "trial", trialEndsAt: new Date(T0 - 1000).toISOString() }],
    ["active period ended 1 ms ago", { tier: "celebrityTrainer", status: "active", currentPeriodEndsAt: ts(T0 - 1) }],
    ["cancelled and the paid period is over", { tier: "standard", status: "cancelled", currentPeriodEndsAt: ts(T0 - 1) }],
  ])("%s -> permission-denied tier-required, nothing created or charged", async (_name, sub) => {
    setSub(sub as any);
    await expectHttpsError(run(valid()), "permission-denied", "tier-required");
    nothingCreated();
  });

  test.each([
    ["standard active, no period end", { tier: "standard", status: "active" }],
    ["celebrityTrainer active", { tier: "celebrityTrainer", status: "active", currentPeriodEndsAt: ts(T0 + DAY) }],
    ["trial ending exactly now", { tier: "standard", status: "trial", trialEndsAt: ts(T0) }],
    ["trial without an end date", { tier: "standard", status: "trial" }],
    ["trial ending later (ISO string)", { tier: "standard", status: "trial", trialEndsAt: new Date(T0 + DAY).toISOString() }],
    ["cancelled but the paid period has not ended", { tier: "standard", status: "cancelled", currentPeriodEndsAt: ts(T0 + 1) }],
  ])("%s -> allowed", async (_name, sub) => {
    setSub(sub as any);
    expect((await run(valid())).status).toBe("pending");
    expect(usageOf(UID, "bodyScanCreate")).toBe(1);
  });
});

describe("refusals that must precede any charge", () => {
  test("an account whose deletion is in flight (accountDeletionRetries exists) -> account-deleting", async () => {
    store.set(`accountDeletionRetries/${UID}`, { uid: UID, status: "pending" });
    await expectHttpsError(run(valid()), "failed-precondition", "account-deleting");
    nothingCreated();
  });

  test("a deletion record of ANOTHER user does not block this user", async () => {
    store.set("accountDeletionRetries/someone_else", { uid: "someone_else", status: "pending" });
    expect((await run(valid())).status).toBe("pending");
  });

  test.each([
    ["BODY_SCAN_PROVIDER unset", () => { delete process.env.BODY_SCAN_PROVIDER; }],
    ["provider is the reserved licensed-api", () => { process.env.BODY_SCAN_PROVIDER = "licensed-api"; }],
    ["provider id unknown", () => { process.env.BODY_SCAN_PROVIDER = "mystery"; }],
    ["test-fake selected but no double installed", () => { __setTestEstimatorForTests(undefined); }],
    ["provider does not require photos", () => { (fake as any).requiresPhotos = false; }],
  ])("%s -> provider-not-configured", async (_name, arrange) => {
    arrange();
    await expectHttpsError(run(valid()), "failed-precondition", "provider-not-configured");
    nothingCreated();
  });

  test.each([
    ["no settings document", undefined],
    ["consent version 0", { cloudConsent: { version: 0 } }],
    ["consent version is a string", { cloudConsent: { version: "1" } }],
    ["consent version negative", { cloudConsent: { version: -1 } }],
    ["no cloudConsent block", { retentionDays: 30 }],
  ])("consent < 1 (%s) -> consent-required, nothing charged or created", async (_name, settings) => {
    if (settings === undefined) store.delete(`users/${UID}/body_scan_settings/main`);
    else store.set(`users/${UID}/body_scan_settings/main`, settings as any);
    await expectHttpsError(run(valid()), "failed-precondition", "consent-required");
    nothingCreated();
  });

  test("consent version 2 (newer than required) is accepted", async () => {
    store.set(`users/${UID}/body_scan_settings/main`, { cloudConsent: { version: 2 } });
    expect((await run(valid())).status).toBe("pending");
  });

  test("a validation failure never reaches the age/tier/consent reads", async () => {
    store.clear();
    await expectHttpsError(run(valid({ scanId: "x" })), "invalid-argument", "invalid-scan-id");
    expect(writes).toEqual([]);
  });
});

describe("daily quota", () => {
  test("at the daily limit (30) a NEW scan is refused with resource-exhausted and nothing is created", async () => {
    store.set(`users/${UID}/usage/${new Date().toISOString().slice(0, 10)}`, { bodyScanCreate: 30 });
    await expectHttpsError(run(valid()), "resource-exhausted");
    expect(scanDoc(UID, SCAN)).toBeUndefined();
    expect(gcs.signed).toEqual([]);
    expect(usageOf(UID, "bodyScanCreate")).toBe(30);
  });

  test("at the limit, an idempotent replay of an existing pending scan still works and charges nothing", async () => {
    await run(valid());
    store.set(`users/${UID}/usage/${new Date().toISOString().slice(0, 10)}`, { bodyScanCreate: 30 });
    const res = await run(valid());
    expect(res.status).toBe("pending");
    expect(usageOf(UID, "bodyScanCreate")).toBe(30);
  });
});

describe("idempotency (D-53, D-59)", () => {
  test("replay of a pending scan re-issues fresh URLs, charges nothing and only extends pendingExpiresAt (DB-F8)", async () => {
    const first = await run(valid());
    const before = { ...scanDoc(UID, SCAN)! };
    const writesBefore = scanWrites().length;
    now += 5 * MIN;
    const second = await run(valid({ takenAtMs: now - 1000, subject: { ...valid().subject, weightKg: 99 } }));

    expect(second.status).toBe("pending");
    expect(second.uploads.front.url).not.toBe(first.uploads.front.url);
    expect(second.uploads.front.expiresAtMs).toBe(now + 10 * MIN);
    expect(usageOf(UID, "bodyScanCreate")).toBe(1);
    expect(scanDoc(UID, SCAN)).toEqual({
      ...before,
      pendingExpiresAt: ts(now + 48 * 60 * MIN),
      uploadReissues: 1,
    });
    expect(scanWrites().length).toBe(writesBefore + 1);
    expect(bodyScanEvents(logger).map((e) => e.outcome)).toEqual(["created", "reissue"]);
  });

  test("a reissue extends pendingExpiresAt from the reissue time, so the purge cannot tombstone a scan mid-upload (DB-F8)", async () => {
    await run(valid());
    now += 40 * 60 * MIN;
    await run(valid());
    expect(scanDoc(UID, SCAN)!.pendingExpiresAt).toEqual(ts(now + 48 * 60 * MIN));
  });

  test("signed-URL reissues are capped at 5 per scan: the 6th answers resource-exhausted upload-url-limit, no URLs, no charge (P-5)", async () => {
    await run(valid());
    for (let i = 0; i < 5; i++) await run(valid());
    expect(scanDoc(UID, SCAN)!.uploadReissues).toBe(5);
    const signedBefore = gcs.signed.length;
    await expectHttpsError(run(valid()), "resource-exhausted", "upload-url-limit");
    expect(gcs.signed.length).toBe(signedBefore);
    expect(usageOf(UID, "bodyScanCreate")).toBe(1);
  });

  test("a failed scan reset starts a fresh reissue and attempt budget", async () => {
    seedScan(UID, SCAN, {
      schema: 1, createdAt: ts(T0 - DAY), takenAt: ts(T0 - DAY), weightKg: 70, status: "failed",
      photosState: "awaiting_upload", purgeAttempts: 0, estimateAttempts: 3, uploadReissues: 5,
    });
    await run(valid());
    const doc = scanDoc(UID, SCAN)!;
    expect("estimateAttempts" in doc).toBe(false);
    expect("uploadReissues" in doc).toBe(false);
  });

  test("replay of a done scan returns the stored entry: no URLs, no quota, no writes, no provider", async () => {
    seedScan(UID, SCAN, {
      status: "done",
      photosState: "deleted",
      provider: { id: "test-fake", version: "1.2.3", provisional: false, requiresPhotos: true },
      estimate: {
        bodyFatPct: 21, rangeLowPct: 18, rangeHighPct: 24, confidence: "high", checkCodes: ["poorLighting"],
        modelId: "test-fake", modelVersion: "1.2.3", estimatedAt: ts(T0 - DAY),
      },
    });
    const before = JSON.stringify(scanDoc(UID, SCAN));
    const res = await run(valid());

    expect(res).toEqual({
      scanId: SCAN,
      status: "done",
      provider: { id: "test-fake", version: "1.2.3", provisional: false, requiresPhotos: true },
      estimate: {
        bodyFatPct: 21, rangeLowPct: 18, rangeHighPct: 24, confidence: "high", checkCodes: ["poorLighting"],
        modelId: "test-fake", modelVersion: "1.2.3", estimatedAtMs: T0 - DAY,
      },
      serverNowMs: now,
    });
    expect(res.uploads).toBeUndefined();
    expect(gcs.signed).toEqual([]);
    expect(usageOf(UID, "bodyScanCreate")).toBe(0);
    expect(scanWrites()).toEqual([]);
    expect(JSON.stringify(scanDoc(UID, SCAN))).toBe(before);
    expect(bodyScanEvents(logger).map((e) => e.outcome)).toEqual(["done-replay"]);
  });

  test("a failed scan is reset to pending and charged again (the first charge was spent on the failure)", async () => {
    seedScan(UID, SCAN, {
      schema: 1,
      createdAt: ts(T0 - 2 * DAY),
      takenAt: ts(T0 - 2 * DAY),
      weightKg: 70,
      status: "failed",
      subject: { sexAtBirth: "male", ageYears: 40, heightCm: 180, weightKg: 70 },
      capture: { manualOverride: { front: true, side: true, back: true }, poses: ["front", "side", "back"] },
      provider: { id: "old", version: "0", provisional: false, requiresPhotos: true },
      photosState: "stored",
      purgeAttempts: 4,
      estimateLeaseUntil: ts(T0 + MIN),
    });
    const res = await run(valid());

    expect(res.status).toBe("pending");
    expect(Object.keys(res.uploads)).toHaveLength(3);
    const doc = scanDoc(UID, SCAN)!;
    expect(doc.status).toBe("pending");
    expect(doc.photosState).toBe("awaiting_upload");
    expect(doc.purgeAttempts).toBe(0);
    expect(doc.pendingExpiresAt).toEqual(ts(T0 + 48 * 60 * MIN));
    expect("estimateLeaseUntil" in doc).toBe(false);
    expect(doc.provider.id).toBe("test-fake");
    expect(doc.subject).toEqual({ sexAtBirth: "female", ageYears: 35, heightCm: 170, weightKg: 65.5 });
    expect(doc.createdAt).toEqual(ts(T0 - 2 * DAY)); // history is kept
    expect(scanWrites().map((w) => w.op)).toEqual(["update"]);
    expect(usageOf(UID, "bodyScanCreate")).toBe(1);
  });

  test("a cancelled tombstone -> scan-cancelled: no URLs, no charge, document unchanged", async () => {
    seedScan(UID, SCAN, { status: "cancelled", photosState: "deleted", pendingExpiresAt: ts(T0 + DAY) });
    const before = JSON.stringify(scanDoc(UID, SCAN));
    await expectHttpsError(run(valid()), "failed-precondition", "scan-cancelled");
    expect(usageOf(UID, "bodyScanCreate")).toBe(0);
    expect(gcs.signed).toEqual([]);
    expect(JSON.stringify(scanDoc(UID, SCAN))).toBe(before);
    expect(scanWrites()).toEqual([]);
  });

  test("two concurrent creates of the same new scan: exactly one document, one net charge (the loser is refunded), both get URLs", async () => {
    const gate = require("./fakes").barrier(2) as () => Promise<void>;
    fx.afterTxRead = async (path) => {
      if (path === SCAN_PATH) await gate();
    };
    const [a, b] = await Promise.all([run(valid()), run(valid())]);

    expect(a.status).toBe("pending");
    expect(b.status).toBe("pending");
    expect(scanWrites().map((w) => w.op)).toEqual(["create", "update"]);
    expect(usageOf(UID, "bodyScanCreate")).toBe(1);
    expect(fx.txRetries).toBeGreaterThanOrEqual(1);
    expect(bodyScanEvents(logger).map((e) => e.outcome).sort()).toEqual(["created", "reissue"]);
  });

  test("a create that loses to a concurrent estimate that finished -> done entry returned and the charge refunded", async () => {
    let injected = false;
    fx.afterTxRead = async (path) => {
      if (path === SCAN_PATH && !injected) {
        injected = true;
        seedScan(UID, SCAN, {
          status: "done",
          provider: { id: "test-fake", version: "1.2.3", provisional: false, requiresPhotos: true },
          estimate: { bodyFatPct: 20, rangeLowPct: 17, rangeHighPct: 23, confidence: "medium", checkCodes: [], modelId: "test-fake", modelVersion: "1.2.3", estimatedAt: ts(T0) },
        });
      }
    };
    const res = await run(valid());
    expect(res.status).toBe("done");
    expect(res.estimate.bodyFatPct).toBe(20);
    expect(res.uploads).toBeUndefined();
    expect(usageOf(UID, "bodyScanCreate")).toBe(0);
    expect(gcs.signed).toEqual([]);
  });

  test("a create that loses to a concurrent delete (tombstone) -> scan-cancelled and the charge is refunded", async () => {
    let injected = false;
    fx.afterTxRead = async (path) => {
      if (path === SCAN_PATH && !injected) {
        injected = true;
        seedScan(UID, SCAN, { status: "cancelled", photosState: "deleted", pendingExpiresAt: ts(T0 + DAY) });
      }
    };
    await expectHttpsError(run(valid()), "failed-precondition", "scan-cancelled");
    expect(usageOf(UID, "bodyScanCreate")).toBe(0);
    expect(gcs.signed).toEqual([]);
  });

  test("ALREADY_EXISTS (code 6) from the commit -> aborted scan-create-conflict, and the charge is refunded", async () => {
    fx.failOn = (op, path) =>
      op === "commit" && path.includes("body_scans") ? firestoreError("exists", 6) : undefined;
    await expectHttpsError(run(valid()), "aborted", "scan-create-conflict");
    expect(usageOf(UID, "bodyScanCreate")).toBe(0);
    expect(gcs.signed).toEqual([]);
  });

  test("any other Firestore failure -> internal scan-create-failed, charge refunded, the log carries only the error code", async () => {
    fx.failOn = (op, path) =>
      op === "commit" && path.includes("body_scans")
        ? firestoreError(`write to users/${UID}/body_scans failed`, "unavailable")
        : undefined;
    await expectHttpsError(run(valid()), "internal", "scan-create-failed");
    expect(usageOf(UID, "bodyScanCreate")).toBe(0);
    expect(scanDoc(UID, SCAN)).toBeUndefined();
    const events = bodyScanEvents(logger, "error");
    expect(events).toEqual([{ operation: "bodyScanCreate", outcome: "firestore-failed", errorCode: "unavailable" }]);
    expect(loggedText(logger)).not.toContain(UID);
  });
});

describe("signing failure", () => {
  test("-> internal upload-url-failed; the log has the error code only (no path, uid or SDK text)", async () => {
    gcs.failOn = (op, name) =>
      op === "sign" ? firestoreError(`cannot sign ${name} for ${UID}`, 403) : undefined;
    await expectHttpsError(run(valid()), "internal", "upload-url-failed");

    const events = bodyScanEvents(logger, "error");
    expect(events).toEqual([{ operation: "bodyScanCreate", outcome: "sign-failed", errorCode: "403" }]);
    const text = loggedText(logger);
    expect(text).not.toContain(UID);
    expect(text).not.toContain("users/");
    expect(text).not.toContain("cannot sign");
  });

  test("the scan survives a signing failure, so the retry re-issues URLs without a second charge", async () => {
    let fail = true;
    gcs.failOn = (op) => (op === "sign" && fail ? firestoreError("boom", 500) : undefined);
    await expectHttpsError(run(valid()), "internal", "upload-url-failed");
    expect(scanDoc(UID, SCAN)!.status).toBe("pending");
    expect(usageOf(UID, "bodyScanCreate")).toBe(1);

    fail = false;
    const res = await run(valid());
    expect(res.status).toBe("pending");
    expect(Object.keys(res.uploads)).toHaveLength(3);
    expect(usageOf(UID, "bodyScanCreate")).toBe(1);
    // The retry is a re-issue: one pendingExpiresAt refresh, never a second document or charge.
    expect(scanWrites().map((w) => w.op)).toEqual(["create", "update"]);
  });
});

describe("ordering", () => {
  test("the document is created in Firestore before any URL is signed", async () => {
    await run(valid());
    const created = timeline.indexOf(`fs:create:${SCAN_PATH}`);
    const firstSign = timeline.findIndex((t) => t.startsWith("gcs:sign:"));
    expect(created).toBeGreaterThanOrEqual(0);
    expect(firstSign).toBeGreaterThan(created);
  });
});

describe("bulk-delete fence (delete-all in progress)", () => {
  // The real id is a uid hash and the fake store keys on the exact path, so seed through the real helper.
  const fencePath = (uid: string): string => deleteFenceRef(uid).path;
  const raise = (activeUntilMs: number): void => {
    store.set(fencePath(UID), { startedAtMs: now - MIN, activeUntilMs, action: "deleteAllScans" });
  };

  test("(b) an active fence refuses a new scan server-side: delete-in-progress, nothing created, quota refunded, no URLs", async () => {
    raise(now + 10 * MIN);
    await expectHttpsError(run(valid()), "failed-precondition", "delete-in-progress");
    nothingCreated();
  });

  test("(b) an active fence also refuses a re-issue and a failed-scan reset for an existing scan", async () => {
    seedScan(UID, SCAN, { schema: 1, status: "pending", photosState: "awaiting_upload", pendingExpiresAt: ts(now + DAY), purgeAttempts: 0 });
    raise(now + 10 * MIN);
    const before = JSON.stringify(scanDoc(UID, SCAN));
    await expectHttpsError(run(valid()), "failed-precondition", "delete-in-progress");
    expect(JSON.stringify(scanDoc(UID, SCAN))).toBe(before);
    expect(gcs.signed).toEqual([]);
    expect(usageOf(UID, "bodyScanCreate")).toBe(0);

    seedScan(UID, SCAN, { schema: 1, status: "failed", photosState: "stored", purgeAttempts: 0 });
    await expectHttpsError(run(valid()), "failed-precondition", "delete-in-progress");
    expect(scanDoc(UID, SCAN)!.status).toBe("failed");
    expect(usageOf(UID, "bodyScanCreate")).toBe(0);
  });

  test("an idempotent replay of a done scan keeps working during the fence", async () => {
    seedScan(UID, SCAN, {
      status: "done",
      provider: { id: "test-fake", version: "1.2.3", provisional: false, requiresPhotos: true },
      estimate: { bodyFatPct: 20, rangeLowPct: 17, rangeHighPct: 23, confidence: "medium", checkCodes: [], modelId: "test-fake", modelVersion: "1.2.3", estimatedAt: ts(T0) },
    });
    raise(now + 10 * MIN);
    const res = await run(valid());
    expect(res.status).toBe("done");
  });

  test("(c) once the fence is cleared the same create succeeds", async () => {
    raise(now + 10 * MIN);
    await expectHttpsError(run(valid()), "failed-precondition", "delete-in-progress");
    store.delete(fencePath(UID));
    const res = await run(valid());
    expect(res.status).toBe("pending");
    expect(usageOf(UID, "bodyScanCreate")).toBe(1);
  });

  test("(d) the fence expires: refused at activeUntilMs - 1, allowed at activeUntilMs", async () => {
    raise(now + 15 * MIN);
    now += 15 * MIN - 1;
    await expectHttpsError(run(valid({ takenAtMs: now - 1000 })), "failed-precondition", "delete-in-progress");
    now += 1;
    const res = await run(valid({ takenAtMs: now - 1000 }));
    expect(res.status).toBe("pending");
  });

  test("another user's fence does not affect this user", async () => {
    store.set(fencePath("someone_else_1"), { startedAtMs: now, activeUntilMs: now + 10 * MIN, action: "deleteAllScans" });
    const res = await run(valid());
    expect(res.status).toBe("pending");
  });
});
