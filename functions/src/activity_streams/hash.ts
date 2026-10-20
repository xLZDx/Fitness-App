/**
 * SHA-256 helpers for the activity stream upload (S02 design 5.1a, 5.2).
 *
 * Two distinct hashes exist and must never be confused:
 *  - `contentSha256`: hash of the bytes the client uploaded (compressed);
 *  - `storedSha256`: hash of the bytes the server re-serialised and stores.
 */
import { createHash, timingSafeEqual } from "crypto";

const SHA256_HEX = /^[0-9a-fA-F]{64}$/;

/** True for exactly 64 hex characters (either case). */
export function isSha256Hex(value: unknown): value is string {
  return typeof value === "string" && SHA256_HEX.test(value);
}

/** Lowercase hex SHA-256 of `bytes`. */
export function sha256Hex(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}

/** Constant-time comparison of two hex digests, case-insensitive. */
export function sha256Equal(a: string, b: string): boolean {
  if (!isSha256Hex(a) || !isSha256Hex(b)) return false;
  return timingSafeEqual(
    Buffer.from(a.toLowerCase(), "hex"),
    Buffer.from(b.toLowerCase(), "hex"),
  );
}
