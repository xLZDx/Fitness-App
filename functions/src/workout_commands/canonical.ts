/**
 * Canonical JSON, payload hash (hashVersion 2) and payload validation for the
 * offline workout command protocol (OFFLINE_COMMAND_PROTOCOL.md 2.1 and 2.2).
 *
 * Everything here is pure (no I/O, no clock) so tests can call it directly and
 * the Dart client can be checked against the same golden vectors.
 *
 * Canonical form: UTF-8 JSON, no whitespace, object keys in recursive
 * lexicographic order (UTF-16 code unit order; all protocol keys and ids are
 * ASCII, so this equals byte order), integers only (no fractions, no exponents,
 * no NaN/Infinity, safe-integer range), explicit `null` for nullable fixed fields,
 * unpaired UTF-16 surrogates rejected in strings and keys (the Dart side rejects
 * them too), unknown keys rejected by `parseCommandPayload`.
 */
import { createHash } from "crypto";
import { sha256Hex } from "../activity_streams/hash";
import { LIMITS_V1, type CommandPayload, type CompleteSetBody, type SessionInit } from "./types";

export class CanonicalError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CanonicalError";
  }
}

/** Thrown by `parseCommandPayload`; the apply maps it to `INVALID_PAYLOAD`. */
export class InvalidPayloadError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InvalidPayloadError";
  }
}

// ---------------------------------------------------------------- canonical JSON

const LONE_SURROGATE = /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/;

/** JSON string literal; an unpaired UTF-16 surrogate is outside the canon. */
function quoteString(value: string): string {
  if (LONE_SURROGATE.test(value)) throw new CanonicalError("unpaired surrogate");
  return JSON.stringify(value);
}

/** Canonical JSON text of a plain JSON value. Throws `CanonicalError` for anything outside the canon. */
export function canonicalJson(value: unknown): string {
  if (value === null) return "null";
  switch (typeof value) {
    case "boolean":
      return value ? "true" : "false";
    case "string":
      return quoteString(value);
    case "number":
      if (!Number.isSafeInteger(value)) throw new CanonicalError("non-integer number");
      return String(Object.is(value, -0) ? 0 : value);
    case "object": {
      if (Array.isArray(value)) return "[" + value.map(canonicalJson).join(",") + "]";
      const proto = Object.getPrototypeOf(value);
      if (proto !== Object.prototype && proto !== null) throw new CanonicalError("non-plain object");
      const obj = value as Record<string, unknown>;
      const keys = Object.keys(obj).sort();
      const parts: string[] = [];
      for (const k of keys) {
        if (obj[k] === undefined) throw new CanonicalError("undefined member");
        parts.push(quoteString(k) + ":" + canonicalJson(obj[k]));
      }
      return "{" + parts.join(",") + "}";
    }
    default:
      throw new CanonicalError("unsupported type");
  }
}

/** UTF-8 bytes of the canonical JSON text. */
export function canonicalBytes(value: unknown): Uint8Array {
  return Buffer.from(canonicalJson(value), "utf8");
}

/** Lowercase hex SHA-256 of the canonical bytes of `value`. */
export function hashCanonical(value: unknown): string {
  return sha256Hex(canonicalBytes(value));
}

/** hashVersion 2 payload hash: lowercase hex SHA-256 of the received/canonical bytes (spec 2.2). */
export function payloadHashOfBytes(bytes: Uint8Array): string {
  return sha256Hex(bytes);
}

/** Canonical bytes of a hashVersion 2 payload (all fields of spec 2.2 are hashed). */
export function canonicalPayloadBytes(payload: CommandPayload): Uint8Array {
  return canonicalBytes(payload);
}

/** hashVersion 2 payload hash of a payload object. */
export function payloadHashOf(payload: CommandPayload): string {
  return payloadHashOfBytes(canonicalPayloadBytes(payload));
}

// ---------------------------------------------------------------- identity

// Firestore reserves ids of the form __name__; they must never become document ids or map keys.
const RESERVED_ID = /^__.*__$/;
const B64URL_22 = /^[A-Za-z0-9_-]{22}$/;
const ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;
const HEX64 = /^[0-9a-f]{64}$/;

/** `uidTag`: base64url of the first 6 bytes of SHA-256("u1|" + uid), 8 characters (spec 2.1). */
export function uidTagOf(uid: string): string {
  return createHash("sha256").update("u1|" + uid, "utf8").digest().subarray(0, 6).toString("base64url");
}

/** True for a 30-character operation id: 8 characters of uidTag plus 22 of random base64url. */
export function isOperationId(value: unknown): value is string {
  return (
    typeof value === "string" &&
    value.length === 30 &&
    /^[A-Za-z0-9_-]{30}$/.test(value) &&
    !RESERVED_ID.test(value) &&
    B64URL_22.test(value.slice(8))
  );
}

/** True when the operation id carries the tag of `uid`. */
export function operationIdMatchesUid(operationId: string, uid: string): boolean {
  return operationId.startsWith(uidTagOf(uid));
}

/** `logicalSetId = {sessionId}:{exerciseId}:{setIndex}` (spec 2.1). */
export function logicalSetIdOf(sessionId: string, exerciseId: string, setIndex: number): string {
  return `${sessionId}:${exerciseId}:${setIndex}`;
}

/** `set_` plus `setIndex` zero-padded to 4 digits (spec 2.1, derived display value). */
export function setIdOf(setIndex: number): string {
  return "set_" + String(setIndex).padStart(4, "0");
}

// ---------------------------------------------------------------- validation

function fail(message: string): never {
  throw new InvalidPayloadError(message);
}

function isPlainObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function exactKeys(obj: Record<string, unknown>, keys: readonly string[], where: string): void {
  const have = Object.keys(obj).sort();
  const want = [...keys].sort();
  if (have.length !== want.length || have.some((k, i) => k !== want[i])) fail(`${where}: keys`);
}

function intIn(v: unknown, min: number, max: number, where: string): number {
  if (typeof v !== "number" || !Number.isSafeInteger(v) || v < min || v > max) fail(`${where}: range`);
  return v;
}

function nullableIntIn(v: unknown, min: number, max: number, where: string): number | null {
  return v === null ? null : intIn(v, min, max, where);
}

function bool(v: unknown, where: string): boolean {
  if (typeof v !== "boolean") fail(`${where}: boolean`);
  return v;
}

function idString(v: unknown, where: string): string {
  if (typeof v !== "string" || !ID_PATTERN.test(v) || RESERVED_ID.test(v)) fail(`${where}: id`);
  return v;
}

const TITLE_KEY = /^(default|day:[A-Za-z0-9_-]{1,64}|plan:[A-Za-z0-9_-]{1,64})$/;
const SOURCE = /^[A-Za-z0-9_-]{1,32}$/;
const TOP_KEYS = [
  "protocolVersion", "hashVersion", "limitsVersion", "operationId", "uid", "sessionId",
  "originDeviceInstallId", "sessionGeneration", "acceptedEpoch", "seq", "dependsOn",
  "exerciseId", "operation", "logicalSetId", "sessionInit", "body",
] as const;
const BODY_KEYS = [
  "mode", "setId", "performedConfirmed", "actualReps", "actualRepsConfirmed",
  "targetReps", "loadGrams", "source", "performedAtClientMs",
] as const;

/**
 * Strict schema validation of a parsed hashVersion 2 CompleteSet APPEND payload.
 * Unknown or missing keys, out-of-range integers and malformed ids throw `InvalidPayloadError`.
 * Slice V0 accepts only `operation = CompleteSet` with `body.mode = APPEND`.
 */
export function parseCommandPayload(raw: unknown): CommandPayload {
  if (!isPlainObject(raw)) fail("payload: object");
  exactKeys(raw, TOP_KEYS, "payload");
  if (raw.protocolVersion !== 2 || raw.hashVersion !== 2 || raw.limitsVersion !== 1) fail("version triple");
  if (!isOperationId(raw.operationId)) fail("operationId");
  const operationId = raw.operationId;
  if (typeof raw.uid !== "string" || raw.uid.length < 1 || raw.uid.length > 128) fail("uid");
  const sessionId = idString(raw.sessionId, "sessionId");
  const originDeviceInstallId = idString(raw.originDeviceInstallId, "originDeviceInstallId");
  const sessionGeneration = intIn(raw.sessionGeneration, 1, 1_000_000, "sessionGeneration");
  const acceptedEpoch = intIn(raw.acceptedEpoch, 0, 1_000_000, "acceptedEpoch");
  const seq = intIn(raw.seq, 1, 2_147_483_647, "seq");

  if (!Array.isArray(raw.dependsOn) || raw.dependsOn.length > LIMITS_V1.maxDependsOn) fail("dependsOn");
  const dependsOn: string[] = [];
  for (const d of raw.dependsOn) {
    if (!isOperationId(d)) fail("dependsOn id");
    dependsOn.push(d);
  }
  // Canonical: sorted ascending, no duplicates, never the operation itself.
  for (let i = 0; i < dependsOn.length; i++) {
    if (dependsOn[i] === operationId) fail("dependsOn self");
    if (i > 0 && !(dependsOn[i - 1] < dependsOn[i])) fail("dependsOn order");
  }

  const exerciseId = idString(raw.exerciseId, "exerciseId");
  if (raw.operation !== "CompleteSet") fail("operation");

  if (!isPlainObject(raw.body)) fail("body");
  const b = raw.body;
  exactKeys(b, BODY_KEYS, "body");
  if (b.mode !== "APPEND") fail("body.mode");
  if (typeof b.source !== "string" || !SOURCE.test(b.source)) fail("body.source");
  const body: CompleteSetBody = {
    mode: "APPEND",
    setId: typeof b.setId === "string" ? b.setId : fail("body.setId"),
    performedConfirmed: bool(b.performedConfirmed, "body.performedConfirmed"),
    actualReps: nullableIntIn(b.actualReps, 0, LIMITS_V1.maxReps, "body.actualReps"),
    actualRepsConfirmed: bool(b.actualRepsConfirmed, "body.actualRepsConfirmed"),
    targetReps: nullableIntIn(b.targetReps, 0, LIMITS_V1.maxReps, "body.targetReps"),
    loadGrams: nullableIntIn(b.loadGrams, 0, LIMITS_V1.maxLoadGrams, "body.loadGrams"),
    source: b.source,
    performedAtClientMs: intIn(b.performedAtClientMs, 0, Number.MAX_SAFE_INTEGER, "body.performedAtClientMs"),
  };

  // logicalSetId must be exactly {sessionId}:{exerciseId}:{setIndex}, canonical decimal 1..1000.
  if (typeof raw.logicalSetId !== "string") fail("logicalSetId");
  const prefix = `${sessionId}:${exerciseId}:`;
  if (!raw.logicalSetId.startsWith(prefix)) fail("logicalSetId prefix");
  const idxText = raw.logicalSetId.slice(prefix.length);
  if (!/^[1-9][0-9]{0,3}$/.test(idxText)) fail("logicalSetId index");
  const setIndex = Number(idxText);
  if (setIndex < 1 || setIndex > LIMITS_V1.maxSetIndex) fail("logicalSetId index range");
  if (body.setId !== setIdOf(setIndex)) fail("body.setId derivation");

  let sessionInit: SessionInit | null = null;
  if (raw.sessionInit !== null) {
    if (!isPlainObject(raw.sessionInit)) fail("sessionInit");
    const si = raw.sessionInit;
    exactKeys(si, ["titleKey", "dayId", "startedAtClientMs"], "sessionInit");
    if (typeof si.titleKey !== "string" || !TITLE_KEY.test(si.titleKey)) fail("sessionInit.titleKey");
    sessionInit = {
      titleKey: si.titleKey,
      dayId: si.dayId === null ? null : idString(si.dayId, "sessionInit.dayId"),
      startedAtClientMs: intIn(si.startedAtClientMs, 0, Number.MAX_SAFE_INTEGER, "sessionInit.startedAtClientMs"),
    };
  }

  return {
    protocolVersion: 2,
    hashVersion: 2,
    limitsVersion: 1,
    operationId,
    uid: raw.uid,
    sessionId,
    originDeviceInstallId,
    sessionGeneration,
    acceptedEpoch,
    seq,
    dependsOn,
    exerciseId,
    operation: "CompleteSet",
    logicalSetId: raw.logicalSetId,
    sessionInit,
    body,
  };
}

/** Set index of a validated payload (the last segment of `logicalSetId`). */
export function setIndexOf(payload: CommandPayload): number {
  return Number(payload.logicalSetId.slice(payload.logicalSetId.lastIndexOf(":") + 1));
}

export type ParsedEnvelopePayload = { payload: CommandPayload; payloadHash: string };

/**
 * Parse received payload text: JSON parse, strict validation, and a byte-exactness check that the
 * text IS the canonical form of what it parses to (so the hash binds the canonical bytes, never a
 * re-serialisation). Returns the payload and the recomputed hash. Throws `InvalidPayloadError`.
 */
export function parseAndHashPayloadText(text: string): ParsedEnvelopePayload {
  if (typeof text !== "string" || text.length === 0 || text.length > LIMITS_V1.maxPayloadChars) fail("payload size");
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    return fail("payload json");
  }
  const payload = parseCommandPayload(raw);
  let canon: string;
  try {
    canon = canonicalJson(payload);
  } catch {
    return fail("payload canonical");
  }
  if (canon !== text) fail("payload not canonical");
  return { payload, payloadHash: payloadHashOfBytes(Buffer.from(text, "utf8")) };
}

/** True for exactly 64 lowercase hex characters. */
export function isLowerHex64(v: unknown): v is string {
  return typeof v === "string" && HEX64.test(v);
}
