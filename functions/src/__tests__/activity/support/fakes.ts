/**
 * Shared doubles for the S02 activity stream tests (plan step 0, F94).
 *
 * Firestore (with optimistic transactions that retry on conflicting writes,
 * `fx.afterTxRead` as the interleaving point) and the `firebase-admin` /
 * logger mocks are REUSED from `../../body_scan/fakes.ts`. New here: a fake
 * bucket (generation pinning, promotion by `save`, 404, signed URL, failure
 * injection, hooks), a fake Auth, a Date-only fake clock, a deadlock-guarded
 * gate for race tests, id/payload builders and seed helpers.
 *
 * Wiring in a test file:
 *   jest.mock("firebase-admin", () => require("./support/fakes").adminMock());
 *   jest.mock("firebase-functions/logger", () => require("./support/fakes").loggerMock());
 * This file has no `.test.ts` suffix, so jest never collects it.
 */
/* eslint-disable @typescript-eslint/no-explicit-any */
import { gzipSync } from "zlib";
import { createHash } from "crypto";
import {
  FakeTimestamp,
  adminMock,
  expectHttpsError,
  firestoreError,
  firestoreInstance,
  fx,
  loggedText,
  loggerMock,
  resetFakes as resetBodyScanFakes,
  store,
  timeline,
  ts,
  usageOf,
  writes,
} from "../../body_scan/fakes";
import type { StreamListingBucket } from "../../../activity_streams/bucket";
import type { UploadDeps } from "../../../activity_streams/upload_common";

export {
  FakeTimestamp, adminMock, expectHttpsError, firestoreError, firestoreInstance, fx,
  loggedText, loggerMock, store, timeline, ts, usageOf, writes,
};

export const MIN = 60 * 1000;
export const HOUR = 60 * MIN;
export const DAY = 24 * HOUR;
/** 2026-10-15T12:00:00Z. */
export const T0 = Date.UTC(2026, 9, 15, 12, 0, 0);

export const UID = "uid_alice_1";
export const UID_B = "uid_bob_2";
export const ACT = `act_${"a".repeat(40)}`;
export const ACT_2 = `act_${"b".repeat(40)}`;
export const BUCKET_NAME = "demo-activity-streams-test";

/* ------------------------------ clock ------------------------------ */

/** Fakes ONLY `Date` (zlib streams and promises keep working). */
export function useClock(ms: number = T0): void {
  jest.useFakeTimers({
    now: ms,
    doNotFake: [
      "nextTick", "setImmediate", "clearImmediate", "setTimeout", "clearTimeout",
      "setInterval", "clearInterval", "queueMicrotask", "hrtime", "performance",
    ],
  });
}
export const setNow = (ms: number): void => jest.setSystemTime(ms);
export const advance = (ms: number): void => jest.setSystemTime(Date.now() + ms);
export function releaseClock(): void {
  jest.useRealTimers();
}

/* ------------------------------ gate ------------------------------- */

/** A pause point for race tests. A gate nobody releases fails instead of hanging. */
export class Gate {
  private reachedResolve!: () => void;
  private releaseResolve!: () => void;
  readonly reached = new Promise<void>((r) => { this.reachedResolve = r; });
  private readonly released = new Promise<void>((r) => { this.releaseResolve = r; });
  hits = 0;
  constructor(readonly name: string, private readonly timeoutMs = 5000) {}
  /** Called by the actor under test. */
  async hit(): Promise<void> {
    this.hits += 1;
    this.reachedResolve();
    let timer: NodeJS.Timeout | undefined;
    const timeout = new Promise<never>((_, rej) => {
      timer = setTimeout(() => rej(new Error(`gate_timeout:${this.name}`)), this.timeoutMs);
    });
    try {
      await Promise.race([this.released, timeout]);
    } finally {
      if (timer) clearTimeout(timer);
    }
  }
  release(): void {
    this.releaseResolve();
  }
}

/* ------------------------------ auth ------------------------------- */

export class FakeAuth {
  users = new Set<string>();
  /** When set, every lookup throws it (a transient failure, not "not found"). */
  lookupError: unknown = null;
  lookups = 0;
  async exists(uid: string): Promise<boolean> {
    this.lookups += 1;
    if (this.lookupError !== null) throw this.lookupError;
    return this.users.has(uid);
  }
}

/* ------------------------------ bucket ----------------------------- */

export interface FakeObject {
  content: Buffer;
  contentType: string;
  generation: number;
}

export type BucketHook = (phase: "before" | "after", op: string, path: string) => Promise<void> | void;

export class FakeBucket implements StreamListingBucket {
  objects = new Map<string, FakeObject>();
  private nextGeneration = 100;
  /** Every `download()` : path + the generation the handle was pinned to. */
  downloads: Array<{ path: string; generation: string | number | undefined }> = [];
  metadataCalls: string[] = [];
  saves: Array<{ path: string; size: number; contentType: string }> = [];
  deletes: Array<{ path: string; ignoreNotFound: boolean }> = [];
  deleteFilesCalls: string[] = [];
  signed: Array<{ path: string; config: any }> = [];
  failOn: ((op: string, path: string) => unknown) | null = null;
  hook: BucketHook | null = null;

  put(path: string, content: Buffer, contentType = "application/gzip"): number {
    const generation = this.nextGeneration++;
    this.objects.set(path, { content: Buffer.from(content), contentType, generation });
    return generation;
  }
  keys(prefix = ""): string[] {
    return [...this.objects.keys()].filter((k) => k.startsWith(prefix)).sort();
  }
  get totalCalls(): number {
    return this.downloads.length + this.metadataCalls.length + this.saves.length +
      this.deletes.length + this.deleteFilesCalls.length + this.signed.length;
  }

  private async step(phase: "before" | "after", op: string, path: string): Promise<void> {
    if (phase === "before") {
      const err = this.failOn?.(op, path);
      if (err !== undefined && err !== null) throw err;
    }
    await this.hook?.(phase, op, path);
  }

  file(path: string, options?: { generation?: string | number }): any {
    const self = this;
    const notFound = () => firestoreError("No such object", 404);
    return {
      name: path,
      async getMetadata() {
        self.metadataCalls.push(path);
        await self.step("before", "getMetadata", path);
        const o = self.objects.get(path);
        if (!o) throw notFound();
        const meta = { generation: String(o.generation), size: String(o.content.length), contentType: o.contentType };
        await self.step("after", "getMetadata", path);
        return [meta];
      },
      async download() {
        self.downloads.push({ path, generation: options?.generation });
        await self.step("before", "download", path);
        const o = self.objects.get(path);
        if (!o) throw notFound();
        if (options?.generation !== undefined && Number(options.generation) !== o.generation) throw notFound();
        const data = Buffer.from(o.content);
        await self.step("after", "download", path);
        return [data];
      },
      async save(data: Buffer, opts: { contentType: string }) {
        await self.step("before", "save", path);
        self.saves.push({ path, size: data.length, contentType: opts.contentType });
        self.put(path, data, opts.contentType);
        await self.step("after", "save", path);
        return [{}];
      },
      async delete(opts?: { ignoreNotFound?: boolean }) {
        self.deletes.push({ path, ignoreNotFound: opts?.ignoreNotFound === true });
        await self.step("before", "delete", path);
        if (!self.objects.has(path)) {
          if (opts?.ignoreNotFound) return [{}];
          throw notFound();
        }
        self.objects.delete(path);
        await self.step("after", "delete", path);
        return [{}];
      },
      async getSignedUrl(config: any) {
        await self.step("before", "sign", path);
        self.signed.push({ path, config });
        return [`https://storage.invalid/signed/${self.signed.length}?sig=SIGNED_URL_SENTINEL`];
      },
    };
  }

  async deleteFiles(options: { prefix: string }): Promise<unknown> {
    this.deleteFilesCalls.push(options.prefix);
    await this.step("before", "deleteFiles", options.prefix);
    for (const k of this.keys(options.prefix)) this.objects.delete(k);
    await this.step("after", "deleteFiles", options.prefix);
    return [];
  }

  async getFiles(): Promise<any> {
    throw new Error("fake bucket: getFiles is not modelled in epic 6a");
  }
}

/* ------------------------------ world ------------------------------ */

export interface World {
  bucket: FakeBucket;
  auth: FakeAuth;
  deps: UploadDeps & { newJobId(): string; newSessionId(): string };
  /** Set to `null` to model the feature off. */
  bucketOn: boolean;
  uploadIdCounter: number;
}

export function uploadIdN(n: number): string {
  return `up_${n.toString(16).padStart(32, "0")}`;
}

export function createWorld(): World {
  const w: World = {
    bucket: new FakeBucket(),
    auth: new FakeAuth(),
    bucketOn: true,
    uploadIdCounter: 0,
    deps: undefined as unknown as World["deps"],
  };
  w.auth.users.add(UID).add(UID_B);
  w.deps = {
    firestore: () => firestoreInstance as unknown as FirebaseFirestore.Firestore,
    authUserExists: (uid: string) => w.auth.exists(uid),
    nowMs: () => Date.now(),
    bucket: () => (w.bucketOn ? w.bucket : undefined),
    newUploadId: () => uploadIdN(++w.uploadIdCounter),
    newJobId: () => `job_${(++w.uploadIdCounter).toString(16).padStart(32, "0")}`,
    newSessionId: () => `dbg_${(++w.uploadIdCounter).toString(16).padStart(32, "0")}`,
  };
  return w;
}

export function resetAll(): void {
  resetBodyScanFakes();
}

/* ------------------------------ seeds ------------------------------ */

export function seedSummary(uid: string, id: string, startUtcMs: number = T0 - 2 * DAY): void {
  store.set(`users/${uid}/activities/${id}`, { startUtc: ts(startUtcMs), rev: 1 });
}

export function seedConsent(uid: string, extra: Record<string, unknown> = {}): void {
  store.set(`users/${uid}/activity_settings/main`, {
    cloudStreams: { version: 1, acceptedAt: ts(T0 - DAY) },
    settingsGeneration: 1,
    streamRetentionDays: 730,
    ...extra,
  });
}

export function seedReady(uid: string = UID, id: string = ACT, startUtcMs: number = T0 - 2 * DAY): void {
  seedSummary(uid, id, startUtcMs);
  seedConsent(uid);
}

export const rowOf = (uid: string, id: string): any => store.get(`users/${uid}/activity_streams/${id}`);
export const settingsOf = (uid: string): any => store.get(`users/${uid}/activity_settings/main`);

/* ----------------------------- payloads ---------------------------- */

export function validPayload(): any {
  return {
    schema: 1,
    kinds: {
      gps: {
        kind: "gps", unit: "deg", sourceId: "src1", offsetsMs: [0, 1000, 2000],
        lats: [51.5, 51.6, 51.7], lons: [-0.1, -0.2, -0.3], accuracies: [5, 6, 7],
      },
      altitude: { kind: "altitude", unit: "m", sourceId: "src1", offsetsMs: [0, 1000], values: [10, 12] },
      speed: { kind: "speed", unit: "m/s", sourceId: "src1", offsetsMs: [0, 1000], values: [1.5, 2.5] },
    },
    meta: {
      laps: [{ index: 0, kind: "auto", startOffsetS: 0, durationS: 60, distanceM: 100, strokeCount: 10, strokeType: "free" }],
      provenance: [{
        sourceId: "src1", sourceKind: "platformHealth", importedAt: "2026-10-15T10:00:00Z",
        deviceModel: "Watch 4", appPackage: "com.example.app", externalId: "ext-1", fieldsContributed: ["distance"],
      }],
    },
  };
}

export const gz = (obj: unknown): Buffer => gzipSync(Buffer.from(JSON.stringify(obj), "utf8"));
export const sha = (b: Uint8Array): string => createHash("sha256").update(b).digest("hex");

export interface Upload { bytes: Buffer; sha: string }
export function uploadOf(obj: unknown = validPayload()): Upload {
  const bytes = gz(obj);
  return { bytes, sha: sha(bytes) };
}

export const quarantinePath = (uid: string, id: string, up: string): string => `quarantine/${uid}/${id}/${up}`;
export const streamPath = (uid: string, id: string, up: string): string => `streams/${uid}/${id}/${up}.json.gz`;

/** Puts the client's bytes at the quarantine path (the PUT through the signed URL). */
export function putQuarantine(w: World, up: Upload, uploadId: string, uid = UID, id = ACT): number {
  return w.bucket.put(quarantinePath(uid, id, uploadId), up.bytes);
}

/** A callable request as `onCall` hands it to the handler. */
export function callReq(data: unknown, uid: string | null = UID, provider = "password"): any {
  return { data, auth: uid ? { uid, token: { firebase: { sign_in_provider: provider } } } : undefined, rawRequest: {} };
}
