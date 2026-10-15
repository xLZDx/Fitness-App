/**
 * Shared test doubles for the Body Scan server tests (C12).
 *
 * This is NOT a new mechanism: it is the stateful in-memory Firestore that
 * `account_deletion_reconcile.test.ts` already uses (one map keyed by document
 * path, queries that really filter/order/limit, optimistic transactions with an
 * interleaving hook), extracted into one module because eight body-scan test
 * files need the same thing, and extended with exactly what the body-scan code
 * touches that the original did not model:
 *
 *  - `collectionGroup`, `orderBy` (asc/desc, `FieldPath.documentId()`),
 *    `startAfter` (a value or a snapshot);
 *  - `FieldValue.delete()` / `FieldValue.increment()` sentinels, applied the way
 *    Firestore applies them (a delete sentinel is REJECTED by `create` and by a
 *    non-merge `set`, as in the real SDK);
 *  - `tx.create` (fails `ALREADY_EXISTS`, code 6), `tx.set`, `tx.update`
 *    (fails `not-found` for a missing document);
 *  - a real `Timestamp` class (the code under test uses `instanceof`);
 *  - a Storage double (`firebase-admin/storage`): objects in a map, `file()`,
 *    `deleteFiles()`, paged `getFiles()`, V4 signed-URL recording, and failure
 *    injection per operation.
 *
 * Wiring in a test file (the factories are lazy, so the order is safe):
 *
 *   jest.mock("firebase-admin", () => require("./fakes").adminMock());
 *   jest.mock("firebase-admin/storage", () => require("./fakes").storageMock());
 *   jest.mock("firebase-functions/logger", () => require("./fakes").loggerMock());
 *   jest.mock("@google-cloud/secret-manager", () => require("./fakes").secretManagerMock());
 *
 * This file contains no `.test.ts` suffix, so jest never collects it as a suite.
 */
/* eslint-disable @typescript-eslint/no-explicit-any */
import type {
  BodyCompositionEstimator,
  EstimatorInput,
  EstimatorOutput,
} from "../../body_scan/types";

export type Doc = Record<string, any>;

/* ------------------------------------------------------------------ */
/* Timestamp, sentinels                                                */
/* ------------------------------------------------------------------ */

export class FakeTimestamp {
  constructor(private readonly ms: number) {}
  static fromMillis(ms: number): FakeTimestamp {
    return new FakeTimestamp(ms);
  }
  static now(): FakeTimestamp {
    return new FakeTimestamp(Date.now());
  }
  toMillis(): number {
    return this.ms;
  }
  toDate(): Date {
    return new Date(this.ms);
  }
  valueOf(): number {
    return this.ms;
  }
}

class DeleteSentinel {}
class IncrementSentinel {
  constructor(readonly by: number) {}
}
class DocIdSentinel {}
const DOC_ID = new DocIdSentinel();

const norm = (v: any): any => (v instanceof FakeTimestamp ? v.toMillis() : v);

function clone<T>(value: T): T {
  if (value instanceof FakeTimestamp) return value;
  if (Array.isArray(value)) return value.map((x) => clone(x)) as any;
  if (value && typeof value === "object" && !(value instanceof Date) && !Buffer.isBuffer(value)) {
    const out: Doc = {};
    for (const [k, v] of Object.entries(value as Doc)) out[k] = clone(v);
    return out as T;
  }
  return value;
}

export const firestoreError = (message: string, code: string | number): Error =>
  Object.assign(new Error(message), { code });

/* ------------------------------------------------------------------ */
/* Firestore state                                                     */
/* ------------------------------------------------------------------ */

export const store = new Map<string, Doc>();

/** Everything that has been applied, in order: `fs:<op>:<path>` and `gcs:...`. */
export const timeline: string[] = [];
/** Committed Firestore writes (transactional and direct), in order. */
export const writes: Array<{ op: "set" | "update" | "create" | "delete"; path: string; data?: Doc }> = [];
/** Every query that was executed. */
export const queries: Array<{
  kind: "collection" | "group";
  name: string;
  filters: Array<{ f: string; op: string; v: any }>;
  orders: Array<{ f: string; dir: "asc" | "desc" }>;
  limit: number;
  startAfter?: any;
}> = [];

export const fx: {
  /** Return an error to make that operation fail; `undefined` lets it pass. */
  failOn: ((op: string, path: string) => Error | undefined) | null;
  /**
   * Awaited inside a transaction right after each `tx.get`, BEFORE the commit:
   * the interleaving point for concurrent-call tests.
   */
  afterTxRead: ((path: string, attempt: number) => Promise<void>) | null;
  /** Runs once after every committed write batch (clock advance, racing writes). */
  afterCommit: ((paths: string[]) => void) | null;
  txRetries: number;
} = { failOn: null, afterTxRead: null, afterCommit: null, txRetries: 0 };

function check(op: string, path: string): void {
  const err = fx.failOn?.(op, path);
  if (err) throw err;
}

function applyFields(base: Doc, data: Doc, op: string): Doc {
  const out: Doc = { ...base };
  for (const [key, value] of Object.entries(data)) {
    if (key.includes(".")) {
      throw new Error(`fake firestore: dotted field path "${key}" is not modelled`);
    }
    if (value instanceof DeleteSentinel) {
      if (op === "create" || op === "set-replace") {
        throw new Error(
          "fake firestore: FieldValue.delete() is not allowed in create() or a non-merge set()",
        );
      }
      delete out[key];
    } else if (value instanceof IncrementSentinel) {
      out[key] = (typeof out[key] === "number" ? out[key] : 0) + value.by;
    } else {
      out[key] = clone(value);
    }
  }
  return out;
}

type Pending = { op: "set" | "update" | "create" | "delete"; path: string; data?: Doc; merge?: boolean };

/** Applies one buffered write; throws Firestore-shaped errors. */
function applyOne(p: Pending): void {
  const exists = store.has(p.path);
  switch (p.op) {
    case "create":
      if (exists) throw firestoreError("already exists", 6);
      store.set(p.path, applyFields({}, p.data ?? {}, "create"));
      break;
    case "set":
      store.set(
        p.path,
        p.merge
          ? applyFields(store.get(p.path) ?? {}, p.data ?? {}, "set-merge")
          : applyFields({}, p.data ?? {}, "set-replace"),
      );
      break;
    case "update":
      if (!exists) throw firestoreError("no document to update", 5);
      store.set(p.path, applyFields(store.get(p.path)!, p.data ?? {}, "update"));
      break;
    case "delete":
      store.delete(p.path);
      break;
  }
}

function commitAll(pending: Pending[]): void {
  // Validate first so a batch is all-or-nothing, like a real commit.
  for (const p of pending) {
    if (p.op === "update" && !store.has(p.path)) throw firestoreError("no document to update", 5);
    if (p.op === "create" && store.has(p.path)) throw firestoreError("already exists", 6);
  }
  for (const p of pending) {
    applyOne(p);
    writes.push({ op: p.op, path: p.path, data: p.data ? clone(p.data) : undefined });
    timeline.push(`fs:${p.op}:${p.path}`);
  }
  fx.afterCommit?.(pending.map((p) => p.path));
}

/* ------------------------------------------------------------------ */
/* References, snapshots, queries                                      */
/* ------------------------------------------------------------------ */

const idOf = (path: string): string => path.split("/").pop() as string;

function snapshotOf(path: string): any {
  const current = store.get(path);
  const ref = docRef(path);
  return {
    exists: current !== undefined,
    id: idOf(path),
    ref,
    data: () => (current === undefined ? undefined : clone(current)),
  };
}

function docRef(path: string): any {
  return {
    path,
    id: idOf(path),
    get parent() {
      return collectionRef(path.split("/").slice(0, -1).join("/"));
    },
    get: async () => {
      check("get", path);
      return snapshotOf(path);
    },
    set: async (data: Doc, options?: { merge?: boolean }) => {
      check("set", path);
      commitAll([{ op: "set", path, data, merge: !!options?.merge }]);
    },
    update: async (data: Doc) => {
      check("update", path);
      commitAll([{ op: "update", path, data }]);
    },
    create: async (data: Doc) => {
      check("create", path);
      commitAll([{ op: "create", path, data }]);
    },
    delete: async () => {
      check("delete", path);
      commitAll([{ op: "delete", path }]);
    },
    collection: (name: string) => collectionRef(`${path}/${name}`),
  };
}

interface QState {
  kind: "collection" | "group";
  name: string;
  filters: Array<{ f: string; op: string; v: any }>;
  orders: Array<{ f: string | DocIdSentinel; dir: "asc" | "desc" }>;
  limit: number;
  startAfter?: any;
}

function makeQuery(s: QState): any {
  return {
    where: (f: string, op: string, v: any) => makeQuery({ ...s, filters: [...s.filters, { f, op, v }] }),
    orderBy: (f: string | DocIdSentinel, dir: "asc" | "desc" = "asc") =>
      makeQuery({ ...s, orders: [...s.orders, { f, dir }] }),
    limit: (n: number) => makeQuery({ ...s, limit: n }),
    startAfter: (v: any) => makeQuery({ ...s, startAfter: v }),
    get: async () => {
      check("query", s.name);
      queries.push({
        kind: s.kind,
        name: s.name,
        filters: s.filters,
        orders: s.orders.map((o) => ({ f: o.f instanceof DocIdSentinel ? "__name__" : o.f, dir: o.dir })),
        limit: s.limit,
        startAfter: s.startAfter,
      });
      let rows = [...store.entries()].filter(([p]) => {
        const segs = p.split("/");
        if (s.kind === "group") return segs.length % 2 === 0 && segs[segs.length - 2] === s.name;
        return p.startsWith(`${s.name}/`) && segs.length === s.name.split("/").length + 1;
      });
      rows = rows.filter(([, d]) =>
        s.filters.every(({ f, op, v }) => {
          // Firestore excludes documents that lack the filtered field.
          if (!(f in d)) return false;
          const a = norm(d[f]);
          const b = norm(v);
          switch (op) {
            case "==": return a === b;
            case "<=": return a <= b;
            case "<": return a < b;
            case ">=": return a >= b;
            case ">": return a > b;
            default: throw new Error(`fake firestore: unsupported operator ${op}`);
          }
        }),
      );
      // orderBy on a field also excludes documents that lack it (real behaviour).
      for (const o of s.orders) {
        const field = o.f;
        if (typeof field === "string") rows = rows.filter(([, d]) => field in d);
      }
      const keyOf = ([p, d]: [string, Doc]): any[] => [
        ...s.orders.map((o) => (o.f instanceof DocIdSentinel ? (s.kind === "group" ? p : idOf(p)) : norm(d[o.f]))),
        p,
      ];
      const dirs = [...s.orders.map((o) => o.dir), "asc" as const];
      const cmp = (x: any[], y: any[]): number => {
        for (let i = 0; i < x.length; i++) {
          if (x[i] === y[i]) continue;
          const r = x[i] < y[i] ? -1 : 1;
          return dirs[i] === "desc" ? -r : r;
        }
        return 0;
      };
      rows.sort((x, y) => cmp(keyOf(x), keyOf(y)));
      if (s.startAfter !== undefined) {
        if (s.orders.length !== 1) throw new Error("fake firestore: startAfter needs exactly one orderBy");
        const cursor = s.startAfter;
        let ck: any[];
        if (cursor && typeof cursor === "object" && cursor.ref && typeof cursor.ref.path === "string") {
          // A snapshot cursor carries the data it had WHEN it was read (the
          // document may have been updated or deleted since).
          ck = keyOf([cursor.ref.path, cursor.data() ?? {}]);
        } else {
          ck = [s.orders[0].f instanceof DocIdSentinel ? cursor : norm(cursor)];
        }
        rows = rows.filter((r) => cmp(keyOf(r).slice(0, ck.length), ck) > 0);
      }
      const docs = rows.slice(0, s.limit).map(([p]) => snapshotOf(p));
      return { docs, empty: docs.length === 0, size: docs.length };
    },
  };
}

function collectionRef(name: string): any {
  const segs = name.split("/");
  return {
    path: name,
    id: idOf(name),
    get parent() {
      return segs.length > 1 ? docRef(segs.slice(0, -1).join("/")) : null;
    },
    doc: (id: string) => docRef(`${name}/${id}`),
    ...makeQuery({ kind: "collection", name, filters: [], orders: [], limit: Infinity }),
  };
}

/** A faithful optimistic transaction (reads see committed state; commit validates). */
async function runTransaction<T>(fn: (tx: any) => Promise<T>): Promise<T> {
  for (let attempt = 1; attempt <= 5; attempt++) {
    const reads = new Map<string, string>();
    const pending: Pending[] = [];
    const tx = {
      get: async (ref: any) => {
        check("txget", ref.path);
        const current = store.get(ref.path);
        reads.set(ref.path, JSON.stringify(current ?? null));
        const snap = snapshotOf(ref.path);
        if (fx.afterTxRead) await fx.afterTxRead(ref.path, attempt);
        return { ...snap, data: () => (current === undefined ? undefined : clone(current)) };
      },
      create: (ref: any, data: Doc) => { pending.push({ op: "create", path: ref.path, data }); },
      set: (ref: any, data: Doc, options?: { merge?: boolean }) => {
        pending.push({ op: "set", path: ref.path, data, merge: !!options?.merge });
      },
      update: (ref: any, data: Doc) => { pending.push({ op: "update", path: ref.path, data }); },
      delete: (ref: any) => { pending.push({ op: "delete", path: ref.path }); },
    };
    const result = await fn(tx);
    check("commit", pending.map((p) => p.path).join(","));
    const stale = [...reads].some(([p, seen]) => JSON.stringify(store.get(p) ?? null) !== seen);
    if (stale) {
      fx.txRetries++;
      continue;
    }
    commitAll(pending);
    return result;
  }
  throw firestoreError("too much contention", "aborted");
}

export const firestoreInstance = {
  doc: (path: string) => docRef(path),
  collection: (name: string) => collectionRef(name),
  collectionGroup: (name: string) => makeQuery({ kind: "group", name, filters: [], orders: [], limit: Infinity }),
  runTransaction,
  recursiveDelete: async (ref: { path: string }) => {
    for (const key of [...store.keys()]) {
      if (key === ref.path || key.startsWith(`${ref.path}/`)) store.delete(key);
    }
  },
};

/** The `firebase-admin` module double. */
export function adminMock(): any {
  const firestoreFn: any = jest.fn(() => firestoreInstance);
  firestoreFn.Timestamp = FakeTimestamp;
  firestoreFn.FieldValue = {
    delete: () => new DeleteSentinel(),
    increment: (n: number) => new IncrementSentinel(n),
  };
  firestoreFn.FieldPath = { documentId: () => DOC_ID };
  return {
    initializeApp: jest.fn(),
    firestore: firestoreFn,
    auth: jest.fn(() => ({})),
  };
}

/* ------------------------------------------------------------------ */
/* Storage                                                             */
/* ------------------------------------------------------------------ */

export interface StoredObject {
  content: Buffer;
  contentType: string;
  timeCreated: string;
}

export const gcs: {
  objects: Map<string, StoredObject>;
  /** Bucket names `getStorage().bucket(name)` was asked for. */
  buckets: string[];
  signed: Array<{ path: string; opts: any }>;
  deleteFilesCalls: Array<{ prefix: string; force: unknown; options: any }>;
  getFilesCalls: any[];
  fileDeleteCalls: Array<{ name: string; opts: any }>;
  downloadCalls: string[];
  /** Return an error to make the operation fail (`sign|getMetadata|download|deleteFiles|delete|getFiles`). */
  failOn: ((op: string, name: string) => unknown) | null;
  onDeleteFiles: ((prefix: string) => void) | null;
  signCounter: number;
} = {
  objects: new Map(),
  buckets: [],
  signed: [],
  deleteFilesCalls: [],
  getFilesCalls: [],
  fileDeleteCalls: [],
  downloadCalls: [],
  failOn: null,
  onDeleteFiles: null,
  signCounter: 0,
};

function gcsCheck(op: string, name: string): void {
  const err = gcs.failOn?.(op, name);
  if (err !== undefined && err !== null) throw err;
}

const notFound = (): Error => firestoreError("No such object", 404);

function fileOf(name: string): any {
  const obj = (): StoredObject | undefined => gcs.objects.get(name);
  return {
    name,
    get metadata() {
      const o = obj();
      return o ? { timeCreated: o.timeCreated, size: String(o.content.length), contentType: o.contentType } : {};
    },
    getSignedUrl: async (opts: any) => {
      gcsCheck("sign", name);
      gcs.signed.push({ path: name, opts });
      timeline.push(`gcs:sign:${name}`);
      gcs.signCounter += 1;
      return [`https://signed.invalid/${gcs.signCounter}?action=${opts.action}`];
    },
    getMetadata: async () => {
      gcsCheck("getMetadata", name);
      const o = obj();
      if (!o) throw notFound();
      return [{ name, size: String(o.content.length), contentType: o.contentType, timeCreated: o.timeCreated }];
    },
    download: async () => {
      gcsCheck("download", name);
      gcs.downloadCalls.push(name);
      const o = obj();
      if (!o) throw notFound();
      return [o.content];
    },
    delete: async (opts?: any) => {
      gcs.fileDeleteCalls.push({ name, opts });
      gcsCheck("delete", name);
      if (!obj()) {
        if (opts?.ignoreNotFound) return [{}];
        throw notFound();
      }
      gcs.objects.delete(name);
      timeline.push(`gcs:delete:${name}`);
      return [{}];
    },
  };
}

const bucketObject: any = {
  file: (name: string) => fileOf(name),
  deleteFiles: async (options: { prefix: string; force?: unknown }) => {
    gcs.deleteFilesCalls.push({ prefix: options.prefix, force: options.force, options });
    gcsCheck("deleteFiles", options.prefix);
    timeline.push(`gcs:deleteFiles:${options.prefix}`);
    for (const key of [...gcs.objects.keys()]) {
      if (key.startsWith(options.prefix)) gcs.objects.delete(key);
    }
    gcs.onDeleteFiles?.(options.prefix);
  },
  getFiles: async (options: { prefix?: string; autoPaginate?: boolean; maxResults?: number; pageToken?: string }) => {
    gcs.getFilesCalls.push(options);
    gcsCheck("getFiles", options.prefix ?? "");
    const names = [...gcs.objects.keys()].filter((n) => n.startsWith(options.prefix ?? "")).sort();
    const start = options.pageToken ? Number(options.pageToken) : 0;
    const size = options.maxResults ?? 1000;
    const slice = names.slice(start, start + size);
    const more = start + size < names.length;
    return [slice.map((n) => fileOf(n)), more ? { pageToken: String(start + size) } : null];
  },
};

/** The `firebase-admin/storage` module double. */
export function storageMock(): any {
  return {
    getStorage: jest.fn(() => ({
      bucket: (name: string) => {
        gcs.buckets.push(name);
        return bucketObject;
      },
    })),
  };
}

/** The `firebase-functions/logger` module double. */
export function loggerMock(): any {
  return { debug: jest.fn(), info: jest.fn(), warn: jest.fn(), error: jest.fn() };
}

/* ------------------------------------------------------------------ */
/* AI Gateway kill switch (Secret Manager)                             */
/* ------------------------------------------------------------------ */

export const gateway: { enabled: boolean; readFails: boolean; reads: number } = {
  enabled: true,
  readFails: false,
  reads: 0,
};

/** The `@google-cloud/secret-manager` module double behind `enforceAiGatewayEnabled`. */
export function secretManagerMock(): any {
  return {
    SecretManagerServiceClient: jest.fn().mockImplementation(() => ({
      accessSecretVersion: async () => {
        gateway.reads += 1;
        if (gateway.readFails) throw new Error("secret unavailable");
        return [{ payload: { data: Buffer.from(JSON.stringify({ enabled: gateway.enabled, reason: null })) } }];
      },
    })),
  };
}

/* ------------------------------------------------------------------ */
/* Estimator double                                                    */
/* ------------------------------------------------------------------ */

export const VALID_OUTPUT: EstimatorOutput = {
  bodyFatPct: 20,
  rangeLowPct: 17,
  rangeHighPct: 23,
  confidence: "medium",
  checkCodes: ["looseClothing"],
};

export class FakePhotoEstimator implements BodyCompositionEstimator {
  id = "test-fake";
  version = "1.2.3";
  provisional = false;
  requiresPhotos = true;
  calls: EstimatorInput[] = [];
  /** Replace to change what the provider does (resolve, reject, hang). */
  behaviour: (input: EstimatorInput) => Promise<EstimatorOutput> = async () => ({
    ...VALID_OUTPUT,
    checkCodes: [...VALID_OUTPUT.checkCodes],
  });
  estimate(input: EstimatorInput): Promise<EstimatorOutput> {
    this.calls.push(input);
    return this.behaviour(input);
  }
}

/* ------------------------------------------------------------------ */
/* Helpers                                                             */
/* ------------------------------------------------------------------ */

/** Clears every piece of fake state; call from `beforeEach`. */
export function resetFakes(): void {
  store.clear();
  timeline.length = 0;
  writes.length = 0;
  queries.length = 0;
  fx.failOn = null;
  fx.afterTxRead = null;
  fx.afterCommit = null;
  fx.txRetries = 0;
  gcs.objects.clear();
  gcs.buckets.length = 0;
  gcs.signed.length = 0;
  gcs.deleteFilesCalls.length = 0;
  gcs.getFilesCalls.length = 0;
  gcs.fileDeleteCalls.length = 0;
  gcs.downloadCalls.length = 0;
  gcs.failOn = null;
  gcs.onDeleteFiles = null;
  gcs.signCounter = 0;
  gateway.enabled = true;
  gateway.readFails = false;
  gateway.reads = 0;
}

export const ts = (ms: number): FakeTimestamp => FakeTimestamp.fromMillis(ms);

export const MIN = 60 * 1000;
export const HOUR = 60 * MIN;
export const DAY = 24 * HOUR;
/** 2026-10-15T12:00:00Z -- the controlled "now" of the body-scan tests. */
export const T0 = Date.UTC(2026, 9, 15, 12, 0, 0);

export const UID = "uid_alice_1";
export const SCAN = "scan_0123456789";
export const BUCKET = "body-scan-test-bucket";

/** A callable request as `onCall` hands it to the handler. */
export function callReq(
  data: unknown,
  uid: string | null = UID,
  signInProvider: string | undefined = "password",
): any {
  return {
    data,
    auth: uid ? { uid, token: { firebase: { sign_in_provider: signInProvider } } } : undefined,
    rawRequest: {},
  };
}

/** Asserts a rejection with the exact HttpsError code and message slug. */
export async function expectHttpsError(
  p: Promise<unknown>,
  code: string,
  message?: string | RegExp,
): Promise<any> {
  const err: any = await p.then(
    () => {
      throw new Error(`expected HttpsError("${code}") but the call resolved`);
    },
    (e: unknown) => e,
  );
  expect(err?.httpErrorCode ?? err?.code).toBeDefined();
  expect(err.code).toBe(code);
  if (typeof message === "string") expect(err.message).toBe(message);
  else if (message) expect(err.message).toMatch(message);
  return err;
}

/** All `usage` counters of one user for one action, summed over days. */
export function usageOf(uid: string, action: string): number {
  let total = 0;
  for (const [path, d] of store) {
    if (path.startsWith(`users/${uid}/usage/`)) total += Number(d[action] ?? 0);
  }
  return total;
}

/** A JPEG-looking object (magic bytes + padding) of exactly `size` bytes. */
export function jpegBytes(size = 4096): Buffer {
  const b = Buffer.alloc(size, 0x11);
  b[0] = 0xff;
  b[1] = 0xd8;
  b[2] = 0xff;
  return b;
}

export const POSE_LIST = ["front", "side", "back"] as const;

/** Puts the three pose objects of a scan into the bucket. */
export function putPhotos(
  uid: string,
  scanId: string,
  o: { timeCreated?: number; size?: number; contentType?: string; poses?: readonly string[] } = {},
): void {
  for (const pose of o.poses ?? POSE_LIST) {
    gcs.objects.set(`users/${uid}/scans/${scanId}/${pose}.jpg`, {
      content: jpegBytes(o.size ?? 4096),
      contentType: o.contentType ?? "image/jpeg",
      timeCreated: new Date(o.timeCreated ?? T0 - DAY).toISOString(),
    });
  }
}

export const objectKeys = (prefix = ""): string[] =>
  [...gcs.objects.keys()].filter((k) => k.startsWith(prefix)).sort();

export const keysUnder = (prefix: string): string[] =>
  [...store.keys()].filter((k) => k === prefix || k.startsWith(`${prefix}/`)).sort();

/** Seeds an adult, paid-tier, consented user with a profile (the happy path for create). */
export function seedEligibleUser(uid: string = UID, o: { birthYear?: number; tier?: string } = {}): void {
  store.set(`users/${uid}/profile/main`, { personal: { birthYear: o.birthYear ?? 1990 } });
  store.set(`users/${uid}/subscription/main`, { tier: o.tier ?? "standard", status: "active" });
  store.set(`users/${uid}/body_scan_settings/main`, { cloudConsent: { version: 1 }, retentionDays: 30 });
}

/** Seeds a scan document directly. */
export function seedScan(uid: string, scanId: string, data: Doc): void {
  store.set(`users/${uid}/body_scans/${scanId}`, data);
}

export const scanDoc = (uid: string, scanId: string): Doc | undefined => store.get(`users/${uid}/body_scans/${scanId}`);

/** Everything the logger received, as one string (to prove what is NOT in it). */
export function loggedText(logger: any): string {
  const parts: string[] = [];
  for (const level of ["debug", "info", "warn", "error"]) {
    for (const call of (logger[level] as jest.Mock).mock.calls) {
      parts.push(JSON.stringify(call, (_k, v) => (v instanceof Error ? { message: v.message, code: (v as any).code } : v)));
    }
  }
  return parts.join("\n");
}

/** The structured `body_scan_event` payloads of one level. */
export function bodyScanEvents(logger: any, level: "info" | "warn" | "error" = "info"): any[] {
  return (logger[level] as jest.Mock).mock.calls.filter((c) => c[0] === "body_scan_event").map((c) => c[1]);
}

/** A "barrier": resolves once `n` callers have arrived, then releases them all. */
export function barrier(n: number): () => Promise<void> {
  let arrived = 0;
  let release!: () => void;
  const gate = new Promise<void>((r) => { release = r; });
  return async () => {
    arrived += 1;
    if (arrived >= n) release();
    await gate;
  };
}
