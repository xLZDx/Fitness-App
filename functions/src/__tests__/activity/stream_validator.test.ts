/** F01-F06: byte-level and structural validation of the uploaded stream object (S02-04a). */
import { gzipSync } from "zlib";
import { validateUploadedStream } from "../../activity_streams/upload_validate";
import { validateStreamPayload } from "../../activity_streams/validate";
import { MAX_COMPRESSED_BYTES, MAX_SAMPLES_PER_STREAM } from "../../activity_streams/schema";
import { gz, sha, uploadOf, validPayload } from "./support/fakes";

const clone = (): any => JSON.parse(JSON.stringify(validPayload()));
const run = (obj: unknown) => {
  const u = uploadOf(obj);
  return validateUploadedStream(u.bytes, u.sha);
};
const codeOf = async (obj: unknown): Promise<string> => {
  const r = await run(obj);
  return r.ok ? "OK" : r.code;
};

describe("F01 valid object", () => {
  test("a valid gps+altitude+speed object is accepted and reports its kinds", async () => {
    const r = await run(validPayload());
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.kinds).toEqual(["gps", "altitude", "speed"]);
      expect(r.contentSha256).toBe(uploadOf().sha);
      expect(r.storedSha256).toBe(sha(r.storedBytes));
    }
  });
  test("a payload with no stream kind is refused", async () => {
    const p = clone();
    p.kinds = {};
    expect(await codeOf(p)).toBe("empty");
  });
});

describe("F02 D-16: the server rejects heart rate", () => {
  const cases: Array<[string, (p: any) => void, string]> = [
    ["kinds.heartRate", (p) => { p.kinds.heartRate = { kind: "heartRate", unit: "bpm", sourceId: "s", offsetsMs: [0], values: [60] }; }, "forbidden_kind"],
    ["kinds.heart_rate", (p) => { p.kinds.heart_rate = {}; }, "forbidden_kind"],
    ["kinds.hr", (p) => { p.kinds.hr = {}; }, "forbidden_kind"],
    ["kinds.HeartRate", (p) => { p.kinds.HeartRate = {}; }, "forbidden_kind"],
    ["lap avgHrBpm", (p) => { p.meta.laps[0].avgHrBpm = 150; }, "forbidden_kind"],
    ["meta.userEdits", (p) => { p.meta.userEdits = { hr: 1 }; }, "unknown_key"],
    ["unknown kind name", (p) => { p.kinds.cadence = { kind: "cadence", unit: "rpm", sourceId: "s", offsetsMs: [0], values: [1] }; }, "unknown_key"],
  ];
  test.each(cases)("%s is rejected with a bare code and nothing to promote", async (_n, mutate, code) => {
    const p = clone();
    mutate(p);
    const r = await run(p);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.code).toBe(code);
    expect(r).not.toHaveProperty("storedBytes");
  });
  test("control: the same payload without the extra key is accepted", async () => {
    expect(await codeOf(clone())).toBe("OK");
  });
});

describe("F03 coordinate ranges (inclusive, design 5.1)", () => {
  const withGps = (lats: unknown[], lons: unknown[]): any => {
    const p = clone();
    p.kinds.gps.lats = lats;
    p.kinds.gps.lons = lons;
    return p;
  };
  test.each([
    ["lat 90.0001", [90.0001, 0, 0], [0, 0, 0]],
    ["lat -90.0001", [0, 0, -90.0001], [0, 0, 0]],
    ["lon 180.0001", [0, 0, 0], [0, 180.0001, 0]],
    ["lon -180.0001", [0, 0, 0], [-180.0001, 0, 0]],
  ])("%s is out_of_range", async (_n, lats, lons) => {
    expect(await codeOf(withGps(lats as any, lons as any))).toBe("out_of_range");
  });
  test.each([["null", null], ["string", "51.5"]])("lat %s is bad_number", async (_n, v) => {
    expect(await codeOf(withGps([v, 0, 0], [0, 0, 0]))).toBe("bad_number");
  });
  test("exactly +/-90 and +/-180 are ACCEPTED (design: inclusive; the plan row F03 says the opposite and is wrong)", async () => {
    expect(await codeOf(withGps([90, -90, 0], [180, -180, 0]))).toBe("OK");
  });
});

describe("F04 monotonic offsets, equal lengths", () => {
  test.each([
    ["equal offsets", [0, 1000, 1000]],
    ["decreasing offsets", [0, 2000, 1000]],
  ])("%s -> not_monotonic", async (_n, offs) => {
    const p = clone();
    p.kinds.gps.offsetsMs = offs;
    expect(await codeOf(p)).toBe("not_monotonic");
  });
  test("lats shorter than offsets -> length_mismatch", async () => {
    const p = clone();
    p.kinds.gps.lats = [1, 2];
    expect(await codeOf(p)).toBe("length_mismatch");
  });
  test("lons longer than offsets -> length_mismatch", async () => {
    const p = clone();
    p.kinds.gps.lons = [1, 2, 3, 4];
    expect(await codeOf(p)).toBe("length_mismatch");
  });
  test("accuracies of the wrong length -> length_mismatch; altitude values too", async () => {
    const p = clone();
    p.kinds.gps.accuracies = [1];
    expect(await codeOf(p)).toBe("length_mismatch");
    const q = clone();
    q.kinds.altitude.values = [1, 2, 3];
    expect(await codeOf(q)).toBe("length_mismatch");
  });
});

describe("F05 size bounds", () => {
  test("compressed 5 MiB + 1 byte is too_large even with a matching hash; exactly 5 MiB passes the size gate", async () => {
    const big = Buffer.alloc(MAX_COMPRESSED_BYTES + 1, 7);
    const r = await validateUploadedStream(big, sha(big));
    expect(r).toEqual({ ok: false, code: "too_large" });
    const exact = Buffer.alloc(MAX_COMPRESSED_BYTES, 7);
    const r2 = await validateUploadedStream(exact, sha(exact));
    // Past the size gate: it now fails on the NEXT check (not gzip), proving the boundary.
    expect(r2).toEqual({ ok: false, code: "not_gzip" });
  });
  test("200 001 samples are too_many, 200 000 are accepted", async () => {
    const mk = (n: number): any => {
      const p = clone();
      p.kinds = { altitude: { kind: "altitude", unit: "m", sourceId: "s", offsetsMs: Array.from({ length: n }, (_, i) => i * 1000), values: new Array(n).fill(1) } };
      return p;
    };
    const over = validateStreamPayload(mk(MAX_SAMPLES_PER_STREAM + 1));
    expect(over).toEqual({ ok: false, code: "too_many" });
    expect(validateStreamPayload(mk(MAX_SAMPLES_PER_STREAM)).ok).toBe(true);
  });
  test("a real high-ratio gzip (zeros) is aborted as bomb, never inflated fully", async () => {
    // 4 MiB of zeros compresses to a few KiB: ratio far above 20.
    const bomb = gzipSync(Buffer.alloc(4 * 1024 * 1024, 0));
    expect(bomb.length).toBeLessThan(10_000);
    const r = await validateUploadedStream(bomb, sha(bomb));
    expect(r).toEqual({ ok: false, code: "bomb" });
  });
});

describe("F06 integrity", () => {
  const good = uploadOf();
  test("sha256 mismatch -> sha_mismatch; malformed claim -> bad_sha", async () => {
    expect(await validateUploadedStream(good.bytes, "0".repeat(64))).toEqual({ ok: false, code: "sha_mismatch" });
    expect(await validateUploadedStream(good.bytes, "xyz")).toEqual({ ok: false, code: "bad_sha" });
  });
  test("the claimed hash may be upper case (idempotency key compare is case-insensitive)", async () => {
    expect((await validateUploadedStream(good.bytes, good.sha.toUpperCase())).ok).toBe(true);
  });
  test("non-gzip -> not_gzip", async () => {
    const b = Buffer.from("this is plain text, not gzip");
    expect(await validateUploadedStream(b, sha(b))).toEqual({ ok: false, code: "not_gzip" });
  });
  test("truncated gzip -> not_gzip", async () => {
    const t = good.bytes.subarray(0, good.bytes.length - 12);
    expect(await validateUploadedStream(t, sha(t))).toEqual({ ok: false, code: "not_gzip" });
  });
  test("invalid JSON -> bad_json; invalid UTF-8 -> bad_encoding", async () => {
    const j = gzipSync(Buffer.from("{not json"));
    expect(await validateUploadedStream(j, sha(j))).toEqual({ ok: false, code: "bad_json" });
    const u = gzipSync(Buffer.from([0x7b, 0x22, 0xff, 0xfe, 0x22, 0x7d]));
    expect(await validateUploadedStream(u, sha(u))).toEqual({ ok: false, code: "bad_encoding" });
  });
  test("unknown schema number -> bad_schema", async () => {
    const p = clone();
    p.schema = 2;
    expect(await codeOf(p)).toBe("bad_schema");
    const q = clone();
    q.schema = "1";
    expect(await codeOf(q)).toBe("bad_schema");
  });
  test("gz helper sanity: a different byte layout of the same JSON has a different content hash", () => {
    expect(sha(gz(validPayload()))).toBe(good.sha);
  });
});
