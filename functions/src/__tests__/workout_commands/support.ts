/**
 * Shared builders for the slice V0 workout command tests (unit, emulator e2e and rules).
 * Not a test file (name does not end in `.test.ts`). Uses only Node crypto so that the oracles do
 * not run through the code under test.
 */
import { createHash } from "crypto";
import { readFileSync } from "fs";
import { resolve } from "path";
import type { CommandPayload } from "../../workout_commands/types";

export const UID_A = "user_A_9f3kQ2LmZx81";
export const UID_B = "user_B_77hTz0pQwErT";
export const SESSION = "day_20261023";
export const EXERCISE = "ex_bench_press";
export const DEVICE = "dev_AAAA1111";
export const PROOF = "writer-proof-secret-aaaaaaaaaaaaaaaaaaaaaaaa";

export const FIXTURE_PATH = resolve(__dirname, "../../../../docs/v1/fixtures/workout_command_golden_vectors.json");

/** Independent uidTag (spec 2.1): base64url of the first 6 bytes of SHA-256("u1|" + uid). */
export function tagOf(uid: string): string {
  return createHash("sha256").update(Buffer.from("u1|" + uid, "utf8")).digest().subarray(0, 6).toString("base64url");
}

/** Deterministic valid operation id for `uid` and a seed. */
export function opIdOf(uid: string, seed: string): string {
  return tagOf(uid) + createHash("sha256").update("t|" + seed).digest().subarray(0, 16).toString("base64url");
}

export function sha256Hex(text: string): string {
  return createHash("sha256").update(Buffer.from(text, "utf8")).digest("hex");
}

export type Over = Partial<Omit<CommandPayload, "body">> & { body?: Partial<CommandPayload["body"]> };

/** A valid CompleteSet APPEND payload (first set of a new session unless overridden). */
export function payloadOf(uid: string, seed: string, over: Over = {}): CommandPayload {
  const { body, ...rest } = over;
  const setIndex = Number((rest.logicalSetId ?? `${SESSION}:${EXERCISE}:1`).split(":").pop());
  return {
    protocolVersion: 2,
    hashVersion: 2,
    limitsVersion: 1,
    operationId: opIdOf(uid, seed),
    uid,
    sessionId: SESSION,
    originDeviceInstallId: DEVICE,
    sessionGeneration: 1,
    acceptedEpoch: 0,
    seq: 1,
    dependsOn: [],
    exerciseId: EXERCISE,
    operation: "CompleteSet",
    logicalSetId: `${SESSION}:${EXERCISE}:1`,
    sessionInit: { titleKey: "day:monday", dayId: "monday", startedAtClientMs: 1792000000000 },
    ...rest,
    body: {
      mode: "APPEND",
      setId: "set_" + String(setIndex).padStart(4, "0"),
      performedConfirmed: true,
      actualReps: 8,
      actualRepsConfirmed: true,
      targetReps: 8,
      loadGrams: 60000,
      source: "manual",
      performedAtClientMs: 1792000012345,
      ...body,
    },
  };
}

/** Independent canonical JSON (own implementation, sorted keys, no whitespace, integers only). */
export function canon(v: unknown): string {
  if (v === null) return "null";
  if (typeof v === "boolean") return v ? "true" : "false";
  if (typeof v === "number") {
    if (!Number.isInteger(v)) throw new Error("non-integer");
    return String(v);
  }
  if (typeof v === "string") return JSON.stringify(v);
  if (Array.isArray(v)) return "[" + v.map(canon).join(",") + "]";
  const o = v as Record<string, unknown>;
  return "{" + Object.keys(o).sort().map((k) => JSON.stringify(k) + ":" + canon(o[k])).join(",") + "}";
}

export type Envelope = { payloadBytes: string; payloadHash: string; writerProof: string; deviceInstallId?: string };

export function envelopeOf(p: CommandPayload, proof: string = PROOF, device: string | undefined = DEVICE): Envelope {
  const payloadBytes = canon(p);
  return { payloadBytes, payloadHash: sha256Hex(payloadBytes), writerProof: proof, ...(device ? { deviceInstallId: device } : {}) };
}

export interface GoldenVector {
  name: string;
  description: string;
  authUid: string;
  requestSessionId: string;
  uidTag: string;
  payloadObject: Record<string, unknown> | null;
  canonicalText: string | null;
  payloadText: string;
  payloadHash: string;
  sentPayloadHash?: string;
  expectedPrepare: string;
  pairedWith?: string;
}

export function loadVectors(): GoldenVector[] {
  return (JSON.parse(readFileSync(FIXTURE_PATH, "utf8")) as { vectors: GoldenVector[] }).vectors;
}
