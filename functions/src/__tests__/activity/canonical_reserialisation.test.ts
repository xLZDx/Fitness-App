/** F52: the promoted bytes are the canonical re-serialisation, never the uploaded bytes. */
import { gunzipSync, gzipSync } from "zlib";
import { validateUploadedStream } from "../../activity_streams/upload_validate";
import { canonicalJson, canonicalStoredBytes } from "../../activity_streams/canonical";
import { validateStreamPayload } from "../../activity_streams/validate";
import { isSha256Hex, sha256Equal, sha256Hex } from "../../activity_streams/hash";
import { sha, validPayload } from "./support/fakes";

/** Same data as validPayload but with reversed key order, whitespace and odd number text. */
function scrambledText(): string {
  return `{
  "meta": { "provenance": [ { "fieldsContributed": ["distance"], "externalId": "ext-1", "appPackage": "com.example.app",
      "deviceModel": "Watch 4", "importedAt": "2026-10-15T10:00:00Z", "sourceKind": "platformHealth", "sourceId": "src1" } ],
    "laps": [ { "strokeType": "free", "strokeCount": 10, "distanceM": 100.0, "durationS": 6e1, "startOffsetS": 0, "kind": "auto", "index": 0 } ] },
  "kinds": {
    "speed": { "values": [1.50, 2.5], "offsetsMs": [0, 1000], "sourceId": "src1", "unit": "m/s", "kind": "speed" },
    "altitude": { "values": [10, 12], "offsetsMs": [0, 1000], "sourceId": "src1", "unit": "m", "kind": "altitude" },
    "gps": { "accuracies": [5, 6, 7], "lons": [-0.1, -0.2, -0.3], "lats": [51.5, 51.6, 51.7], "offsetsMs": [0, 1000, 2000],
      "sourceId": "src1", "unit": "deg", "kind": "gps" } },
  "schema": 1 }`;
}
const gzText = (t: string): Buffer => gzipSync(Buffer.from(t, "utf8"));

describe("F52 canonical re-serialisation", () => {
  test("a scrambled upload is stored in canonical form, not byte-equal to the upload", async () => {
    const up = gzText(scrambledText());
    const r = await validateUploadedStream(up, sha(up));
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.storedBytes.equals(up)).toBe(false);
    const stored = gunzipSync(r.storedBytes).toString("utf8");
    expect(stored).toBe(canonicalJson(validPayload() as any));
    expect(stored).not.toMatch(/[\n\r\t]|": |, "/);
    expect(stored.startsWith('{"schema":1,"kinds":{"gps"')).toBe(true);
    expect(stored).toContain('"values":[1.5,2.5]');
    expect(stored).toContain('"durationS":60');
  });

  test("storedSha256 is the hash of the promoted bytes and differs from contentSha256", async () => {
    const up = gzText(scrambledText());
    const r = await validateUploadedStream(up, sha(up));
    if (!r.ok) throw new Error("expected ok");
    expect(r.storedSha256).toBe(sha(r.storedBytes));
    expect(r.contentSha256).toBe(sha(up));
    expect(r.storedSha256).not.toBe(r.contentSha256);
  });

  test("re-serialising the promoted object again is a fixed point (same bytes, same hash)", async () => {
    const up = gzText(scrambledText());
    const first = await validateUploadedStream(up, sha(up));
    if (!first.ok) throw new Error("expected ok");
    const second = await validateUploadedStream(first.storedBytes, first.storedSha256);
    if (!second.ok) throw new Error("expected ok");
    expect(second.storedBytes.equals(first.storedBytes)).toBe(true);
    expect(second.storedSha256).toBe(first.storedSha256);
  });

  test("a clean canonical payload is stored byte-equal", async () => {
    const parsed = validateStreamPayload(validPayload());
    if (!parsed.ok) throw new Error("expected ok");
    const canon = canonicalStoredBytes(parsed.value);
    const r = await validateUploadedStream(canon, sha(canon));
    if (!r.ok) throw new Error("expected ok");
    expect(r.storedBytes.equals(canon)).toBe(true);
    expect(r.storedSha256).toBe(r.contentSha256);
  });

  test("gzip is deterministic: OS byte pinned to 255, mtime 0, equal input equal bytes", () => {
    const parsed = validateStreamPayload(validPayload());
    if (!parsed.ok) throw new Error("expected ok");
    const a = canonicalStoredBytes(parsed.value);
    const b = canonicalStoredBytes(parsed.value);
    expect(a.equals(b)).toBe(true);
    expect(a[9]).toBe(255);
    expect(a.readUInt32LE(4)).toBe(0);
  });

  test("optional keys that were absent stay absent, optional keys keep canonical position", () => {
    const p: any = JSON.parse(JSON.stringify(validPayload()));
    delete p.kinds.gps.accuracies;
    delete p.meta.laps[0].strokeType;
    delete p.meta.provenance[0].deviceModel;
    const parsed = validateStreamPayload(p);
    if (!parsed.ok) throw new Error("expected ok");
    const text = canonicalJson(parsed.value);
    expect(text).not.toContain("accuracies");
    expect(text).not.toContain("strokeType");
    expect(text).not.toContain("deviceModel");
  });

  test("a hostile extra key never reaches the stored bytes (rejected, not stripped)", async () => {
    const p: any = JSON.parse(JSON.stringify(validPayload()));
    p.meta.laps[0].avgHrBpm = 150;
    const up = gzText(JSON.stringify(p));
    expect(await validateUploadedStream(up, sha(up))).toEqual({ ok: false, code: "forbidden_kind" });
  });
});

describe("S02-04a hash helpers", () => {
  const h = sha256Hex(Buffer.from("abc"));
  test("sha256Hex is the known digest of abc", () => {
    expect(h).toBe("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  });
  test("isSha256Hex accepts exactly 64 hex characters of either case", () => {
    expect(isSha256Hex(h)).toBe(true);
    expect(isSha256Hex(h.toUpperCase())).toBe(true);
    expect(isSha256Hex(h.slice(1))).toBe(false);
    expect(isSha256Hex(h + "0")).toBe(false);
    expect(isSha256Hex("g".repeat(64))).toBe(false);
    expect(isSha256Hex(5)).toBe(false);
  });
  test("sha256Equal is case-insensitive and false for malformed input", () => {
    expect(sha256Equal(h, h.toUpperCase())).toBe(true);
    expect(sha256Equal(h, "0".repeat(64))).toBe(false);
    expect(sha256Equal(h, "zz")).toBe(false);
  });
});
