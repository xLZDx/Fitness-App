/**
 * Slice V0: compact replay fence encoding (OFFLINE_COMMAND_PROTOCOL.md 5.2). Literal oracles were
 * computed with Python hashlib over the documented formulas.
 */
import { createHash } from "crypto";
import {
  fenceDocPath,
  fenceKeyOf,
  fenceShardOf,
  fenceValueOf,
  hashPrefix,
  operationDigest,
  parseFenceValue,
  sessionDigest,
} from "../../workout_commands/fence";
import { UID_A, opIdOf, sha256Hex } from "./support";

const OP = "abcDEF12ghijklmnopqrstuvwxyz01";

describe("fence encoding", () => {
  test("literal shard, key and session digest", () => {
    expect(fenceShardOf(OP)).toBe("eb");
    expect(fenceKeyOf(OP)).toBe("66rMivRSGnPOGz4TlybIWQ");
    expect(sessionDigest("day_20261023")).toBe("F55_QrG6WU4");
    expect(hashPrefix("00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff")).toBe("ABEiM0RVZnc");
  });

  test("shard is two lowercase hex characters, key is 22 base64url characters, for many ids", () => {
    for (let i = 0; i < 300; i++) {
      const id = opIdOf(UID_A, "n" + i);
      expect(fenceShardOf(id)).toMatch(/^[0-9a-f]{2}$/);
      expect(fenceKeyOf(id)).toMatch(/^[A-Za-z0-9_-]{22}$/);
    }
  });

  test("shard and key are deterministic and differ between operation ids", () => {
    const a = opIdOf(UID_A, "a");
    const b = opIdOf(UID_A, "b");
    expect(fenceKeyOf(a)).toBe(fenceKeyOf(a));
    expect(fenceShardOf(a)).toBe(fenceShardOf(a));
    expect(fenceKeyOf(a)).not.toBe(fenceKeyOf(b));
  });

  test("shard is the first byte of the digest and the key its first 16 bytes", () => {
    const d = createHash("sha256").update("op1|" + OP).digest();
    expect(operationDigest(OP).equals(d)).toBe(true);
    expect(fenceShardOf(OP)).toBe(d.subarray(0, 1).toString("hex"));
    expect(fenceKeyOf(OP)).toBe(d.subarray(0, 16).toString("base64url"));
  });

  test("shard distribution covers many of the 256 shards (not a constant)", () => {
    const shards = new Set<string>();
    for (let i = 0; i < 2000; i++) shards.add(fenceShardOf(opIdOf(UID_A, "d" + i)));
    expect(shards.size).toBeGreaterThan(200);
  });

  test("value is 23 characters: code + 11 session digest + 11 hash prefix", () => {
    const h = sha256Hex("payload");
    for (const code of ["C", "R", "S"] as const) {
      const v = fenceValueOf(code, "day_20261023", h);
      expect(v).toHaveLength(23);
      expect(v[0]).toBe(code);
      expect(v.slice(1, 12)).toBe("F55_QrG6WU4");
      expect(v.slice(12)).toBe(Buffer.from(h, "hex").subarray(0, 8).toString("base64url"));
    }
  });

  test("parseFenceValue round-trips and refuses malformed values", () => {
    const h = sha256Hex("payload");
    const v = fenceValueOf("R", "day_20261023", h);
    expect(parseFenceValue(v)).toEqual({ code: "R", sessionDigest: sessionDigest("day_20261023"), hashPrefix: hashPrefix(h) });
    for (const bad of [undefined, null, 5, "", v.slice(1), v + "x", "X" + v.slice(1), "c" + v.slice(1)]) {
      expect(parseFenceValue(bad)).toBeUndefined();
    }
  });

  test("hash prefix and session digest separate different payloads/sessions", () => {
    expect(hashPrefix(sha256Hex("a"))).not.toBe(hashPrefix(sha256Hex("b")));
    expect(sessionDigest("s1")).not.toBe(sessionDigest("s2"));
  });

  test("document path", () => {
    expect(fenceDocPath("u", "ab")).toBe("users/u/workout_command_fence/ab");
  });
});
