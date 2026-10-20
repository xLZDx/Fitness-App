/** F50: decompression limits (ratio 20, 32 MiB cap, 10 s budget), streaming abort, bare codes. */
import { inflateBounded, validateUploadedStream, type GunzipChunks } from "../../activity_streams/upload_validate";
import { MAX_DECOMPRESSED_BYTES } from "../../activity_streams/schema";
import { sha } from "./support/fakes";

const CHUNK = 1024 * 1024;

/** A fake decompressor that yields `total` bytes in `chunk`-sized pieces, counting what was pulled. */
function source(total: number, chunk = CHUNK, onChunk?: () => void) {
  const state = { yielded: 0 };
  const gen: GunzipChunks = () => (async function* () {
    let left = total;
    while (left > 0) {
      const n = Math.min(chunk, left);
      left -= n;
      state.yielded += n;
      onChunk?.();
      yield Buffer.alloc(n, 0x20);
    }
  })();
  return { gen, state };
}

const codeOf = async (p: Promise<unknown>): Promise<string> => {
  try { await p; return "RESOLVED"; } catch (e: any) { return e.code; }
};

describe("F50 ratio limit", () => {
  const compressed = Buffer.alloc(1000, 1);
  test("exactly 20x is accepted, 20x + 1 byte is bomb", async () => {
    const ok = source(20_000);
    await expect(inflateBounded(compressed, { gunzipChunks: ok.gen })).resolves.toHaveLength(20_000);
    const bad = source(20_001);
    expect(await codeOf(inflateBounded(compressed, { gunzipChunks: bad.gen }))).toBe("bomb");
  });
  test("the abort is streaming: pulled bytes stay below the limit plus one chunk", async () => {
    const infinite = source(10 * 1024 * 1024 * 1024, CHUNK); // 10 GiB if it were read
    expect(await codeOf(inflateBounded(Buffer.alloc(1000, 1), { gunzipChunks: infinite.gen }))).toBe("bomb");
    expect(infinite.state.yielded).toBeLessThanOrEqual(20_000 + CHUNK);
  });
});

describe("F50 absolute cap", () => {
  const noRatio = { maxRatio: 1e9 };
  test("32 MiB exactly is accepted, 32 MiB + 1 byte is bomb", async () => {
    const ok = source(MAX_DECOMPRESSED_BYTES);
    await expect(inflateBounded(Buffer.alloc(10, 1), { ...noRatio, gunzipChunks: ok.gen })).resolves.toHaveLength(MAX_DECOMPRESSED_BYTES);
    const bad = source(MAX_DECOMPRESSED_BYTES + 1);
    expect(await codeOf(inflateBounded(Buffer.alloc(10, 1), { ...noRatio, gunzipChunks: bad.gen }))).toBe("bomb");
  });
  test("a stream that stays under the ratio but over the cap is aborted at the cap (memory proxy)", async () => {
    // 5 MiB compressed * ratio 20 = 100 MiB allowed by the ratio; the cap must still bind.
    const big = source(100 * 1024 * 1024);
    expect(await codeOf(inflateBounded(Buffer.alloc(5 * 1024 * 1024, 1), { gunzipChunks: big.gen }))).toBe("bomb");
    expect(big.state.yielded).toBeLessThanOrEqual(MAX_DECOMPRESSED_BYTES + CHUNK);
  });
});

describe("F50 wall-clock budget (injected clock)", () => {
  test("elapsed beyond 10 s aborts with timeout; exactly 10 s does not", async () => {
    let now = 0;
    const slow = source(10 * CHUNK, CHUNK, () => { now += 4000; });
    expect(await codeOf(inflateBounded(Buffer.alloc(10 * CHUNK, 1), { now: () => now, gunzipChunks: slow.gen }))).toBe("timeout");
    expect(slow.state.yielded).toBe(3 * CHUNK); // 4 s, 8 s, 12 s -> stopped at the third chunk

    let t2 = 0;
    const exact = source(2 * CHUNK, CHUNK, () => { t2 += 5000; });
    await expect(inflateBounded(Buffer.alloc(2 * CHUNK, 1), { now: () => t2, gunzipChunks: exact.gen })).resolves.toHaveLength(2 * CHUNK);
  });
});

describe("F50 bare codes through the whole validator", () => {
  test("bomb and timeout surface as exactly {ok:false, code}", async () => {
    const c = Buffer.concat([Buffer.from([0x1f, 0x8b]), Buffer.alloc(100, 1)]);
    const bomb = await validateUploadedStream(c, sha(c), { gunzipChunks: source(1_000_000).gen });
    expect(bomb).toEqual({ ok: false, code: "bomb" });
    let now = 0;
    const timeout = await validateUploadedStream(c, sha(c), { now: () => now, gunzipChunks: source(1500, 500, () => { now += 6000; }).gen });
    expect(timeout).toEqual({ ok: false, code: "timeout" });
  });
  test("a decompressor that throws is not_gzip with no message", async () => {
    const c = Buffer.concat([Buffer.from([0x1f, 0x8b]), Buffer.alloc(100, 1)]);
    const boom: GunzipChunks = () => (async function* () { yield Buffer.alloc(1); throw new Error("secret path /x/uid"); })();
    const r = await validateUploadedStream(c, sha(c), { gunzipChunks: boom });
    expect(r).toEqual({ ok: false, code: "not_gzip" });
  });
});
