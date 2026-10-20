/** S02 remediation A8 (validator part): the cheap separator bound rejects comma filler `too_many` BEFORE JSON.parse. */
import { gzipSync } from "zlib";
import { CLOUD_STREAM_KINDS, MAX_SAMPLES_PER_STREAM } from "../../activity_streams/schema";
import { validateUploadedStream } from "../../activity_streams/upload_validate";
import { gz, sha, validPayload } from "./support/fakes";

// Oracle (notes A8): the bound is samples x 8 x kinds separators.
const BOUND = MAX_SAMPLES_PER_STREAM * 8 * CLOUD_STREAM_KINDS.length;
const RELAXED = { maxRatio: 1_000_000 }; // comma filler compresses far beyond the production ratio cap

const upload = (body: string) => {
  const bytes = gzipSync(Buffer.from(body, "utf8"));
  return { bytes, sha: sha(bytes) };
};

describe("A8 validateUploadedStream separator bound", () => {
  let parseSpy: jest.SpyInstance;
  beforeEach(() => { parseSpy = jest.spyOn(JSON, "parse"); });
  afterEach(() => parseSpy.mockRestore());

  test("the bound formula is the documented one and is large (sanity: far above a legitimate payload)", () => {
    expect(BOUND).toBeGreaterThan(1_000_000);
    expect(CLOUD_STREAM_KINDS.length).toBeGreaterThan(0);
  });
  test("comma filler beyond the bound is rejected too_many and JSON.parse is never reached", async () => {
    const u = upload("1,".repeat(BOUND + 1));
    parseSpy.mockClear();
    const r = await validateUploadedStream(u.bytes, u.sha, RELAXED);
    expect(r).toEqual({ ok: false, code: "too_many" });
    expect(parseSpy).not.toHaveBeenCalled();
  });
  test("a 32 MiB comma filler is rejected too_many (the example of the notes), parse not reached", async () => {
    const u = upload("1,".repeat(16 * 1024 * 1024));
    parseSpy.mockClear();
    const r = await validateUploadedStream(u.bytes, u.sha, RELAXED);
    expect(r).toEqual({ ok: false, code: "too_many" });
    expect(parseSpy).not.toHaveBeenCalled();
  }, 60000);
  test("exactly at the bound the cheap check passes (the parse IS reached and the filler fails later, not as too_many)", async () => {
    const u = upload(("1,".repeat(BOUND)).slice(0, -1)); // BOUND-1 commas
    parseSpy.mockClear();
    const r = await validateUploadedStream(u.bytes, u.sha, RELAXED);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.code).not.toBe("too_many");
    expect(parseSpy).toHaveBeenCalled();
    const v = upload("1,".repeat(BOUND)); // exactly BOUND commas
    parseSpy.mockClear();
    const r2 = await validateUploadedStream(v.bytes, v.sha, RELAXED);
    if (!r2.ok) expect(r2.code).not.toBe("too_many");
  }, 60000);
  test("a large valid payload (200000 gps samples) is still accepted", async () => {
    const n = MAX_SAMPLES_PER_STREAM;
    const p = validPayload();
    p.kinds = {
      gps: {
        kind: "gps", unit: "deg", sourceId: "src1",
        offsetsMs: Array.from({ length: n }, (_, i) => i * 1000),
        lats: Array.from({ length: n }, (_, i) => 51 + (i % 1000) / 10000),
        lons: Array.from({ length: n }, (_, i) => -0.1 - (i % 1000) / 10000),
        accuracies: Array.from({ length: n }, () => 5),
      },
    };
    const bytes = gz(p);
    const r = await validateUploadedStream(bytes, sha(bytes), RELAXED);
    expect(r.ok).toBe(true);
  });
  test("a normal valid payload is accepted with the production options", async () => {
    const bytes = gz(validPayload());
    expect((await validateUploadedStream(bytes, sha(bytes))).ok).toBe(true);
  });
});
