/**
 * Compact replay fence helpers (OFFLINE_COMMAND_PROTOCOL.md 5.2). Pure functions.
 *
 * Document `users/{uid}/workout_command_fence/{shard}`: `shard` = two lowercase hex characters
 * (first byte of D = SHA-256("op1|" + operationId)); one map field `e`; key = base64url of the
 * first 16 bytes of D (22 chars); value = 23 chars = code (C|R|S) + 11 chars of base64url of the
 * first 8 bytes of SHA-256("s1|" + sessionId) + 11 chars of base64url of the first 8 bytes of the
 * payload hash. Slice V0 does not implement spill documents.
 */
import { createHash } from "crypto";

export type FenceCode = "C" | "R" | "S";

export function operationDigest(operationId: string): Buffer {
  return createHash("sha256").update("op1|" + operationId, "utf8").digest();
}

export function fenceShardOf(operationId: string): string {
  return operationDigest(operationId).subarray(0, 1).toString("hex");
}

export function fenceKeyOf(operationId: string): string {
  return operationDigest(operationId).subarray(0, 16).toString("base64url");
}

export function sessionDigest(sessionId: string): string {
  return createHash("sha256").update("s1|" + sessionId, "utf8").digest().subarray(0, 8).toString("base64url");
}

/** Base64url of the first 8 bytes of a lowercase hex SHA-256 payload hash (11 chars). */
export function hashPrefix(payloadHashHex: string): string {
  return Buffer.from(payloadHashHex, "hex").subarray(0, 8).toString("base64url");
}

export function fenceValueOf(code: FenceCode, sessionId: string, payloadHashHex: string): string {
  return code + sessionDigest(sessionId) + hashPrefix(payloadHashHex);
}

export type FenceEntry = { code: FenceCode; sessionDigest: string; hashPrefix: string };

/** Parse a stored 23-character fence value; `undefined` for anything malformed. */
export function parseFenceValue(value: unknown): FenceEntry | undefined {
  if (typeof value !== "string" || value.length !== 23) return undefined;
  const code = value[0];
  if (code !== "C" && code !== "R" && code !== "S") return undefined;
  return { code, sessionDigest: value.slice(1, 12), hashPrefix: value.slice(12) };
}

export function fenceDocPath(uid: string, shard: string): string {
  return `users/${uid}/workout_command_fence/${shard}`;
}
