/**
 * Byte-level validation of one uploaded activity stream object (S02 design
 * 5.1, 5.1a, 5.2 step 2b; story S02-04a). It takes the bytes the commit
 * callable already read ONCE into memory and returns either the exact bytes to
 * promote or a bare rejection code. No bucket, no Firestore, no logging: the
 * callable (S02-04b) owns quarantine deletion and row state.
 *
 * Order of checks (each branch has its own code):
 *   size -> sha256 of the uploaded bytes -> gzip magic -> bounded streaming
 *   decompression (absolute cap, ratio, wall clock) -> UTF-8/JSON parse ->
 *   closed schema -> canonical re-serialisation -> stored size.
 */
import { createGunzip } from "zlib";
import { Readable } from "stream";
import {
  MAX_COMPRESSED_BYTES,
  MAX_COMPRESSION_RATIO,
  MAX_DECOMPRESSED_BYTES,
  MAX_DECOMPRESS_MS,
  CLOUD_STREAM_KINDS,
  type CloudStreamKind,
} from "./schema";
import { canonicalJsonBytes, deterministicGzip } from "./canonical";
import { isSha256Hex, sha256Equal, sha256Hex } from "./hash";
import { validateStreamPayload, type StreamRejectCode } from "./validate";

/** Rejection codes of the byte layer, in addition to the schema codes. */
export type UploadRejectCode =
  | StreamRejectCode
  | "bad_sha"
  | "sha_mismatch"
  | "too_large"
  | "not_gzip"
  | "bomb"
  | "timeout"
  | "bad_encoding";

/** Streams the decompressed output of `compressed` in chunks (injectable). */
export type GunzipChunks = (compressed: Buffer) => AsyncIterable<Buffer>;

export interface UploadValidationOptions {
  /** Wall-clock source in milliseconds (injectable for the timeout test). */
  now?: () => number;
  /** Decompression stream (injectable for the zip-bomb and timeout tests). */
  gunzipChunks?: GunzipChunks;
  /** Overrides, for boundary tests only; production uses the schema values. */
  maxCompressedBytes?: number;
  maxDecompressedBytes?: number;
  maxRatio?: number;
  maxDecompressMs?: number;
}

export interface ValidatedUpload {
  ok: true;
  /** Hash of the uploaded (compressed) bytes; equals the client's value. */
  contentSha256: string;
  /** Canonical gzip bytes to promote, byte-for-byte. */
  storedBytes: Buffer;
  /** Hash of `storedBytes`. */
  storedSha256: string;
  /** Kinds present, in canonical order. */
  kinds: CloudStreamKind[];
}

export type UploadValidationResult =
  | ValidatedUpload
  | { ok: false; code: UploadRejectCode };

const GZIP_MAGIC_1 = 0x1f;
const GZIP_MAGIC_2 = 0x8b;
/** Compressed input is fed in slices so a stream fake can interleave checks. */
const FEED_SLICE = 16 * 1024;

/** Default decompressor: Node zlib fed in slices, output in zlib-sized chunks. */
export const defaultGunzipChunks: GunzipChunks = (compressed) => {
  const gunzip = createGunzip();
  const slices: Buffer[] = [];
  for (let i = 0; i < compressed.length; i += FEED_SLICE) {
    slices.push(compressed.subarray(i, i + FEED_SLICE));
  }
  Readable.from(slices, { objectMode: false }).on("error", (e) => gunzip.destroy(e)).pipe(gunzip);
  return gunzip as unknown as AsyncIterable<Buffer>;
};

class ByteReject extends Error {
  constructor(readonly code: UploadRejectCode) {
    super(code);
  }
}

/**
 * Inflates `compressed` with three independent limits, checked after every
 * chunk so memory stays below the cap plus one chunk:
 *   total > maxDecompressedBytes          -> `bomb`
 *   total > maxRatio * compressed.length  -> `bomb`
 *   elapsed > maxDecompressMs             -> `timeout`
 * A corrupt or truncated stream is `not_gzip`.
 */
export async function inflateBounded(
  compressed: Buffer,
  opts: UploadValidationOptions = {},
): Promise<Buffer> {
  const now = opts.now ?? Date.now;
  const cap = opts.maxDecompressedBytes ?? MAX_DECOMPRESSED_BYTES;
  const ratioCap = (opts.maxRatio ?? MAX_COMPRESSION_RATIO) * compressed.length;
  const budget = opts.maxDecompressMs ?? MAX_DECOMPRESS_MS;
  const start = now();
  const chunks: Buffer[] = [];
  let total = 0;
  try {
    for await (const chunk of (opts.gunzipChunks ?? defaultGunzipChunks)(compressed)) {
      total += chunk.length;
      if (total > cap || total > ratioCap) throw new ByteReject("bomb");
      if (now() - start > budget) throw new ByteReject("timeout");
      chunks.push(chunk);
    }
  } catch (err) {
    if (err instanceof ByteReject) throw err;
    throw new ByteReject("not_gzip");
  }
  return Buffer.concat(chunks, total);
}

/**
 * Validates one uploaded object. `expectedContentSha256` is the client's claim
 * (already shape-checked by the callable; re-checked here). Never throws.
 */
export async function validateUploadedStream(
  compressed: Buffer,
  expectedContentSha256: string,
  opts: UploadValidationOptions = {},
): Promise<UploadValidationResult> {
  const reject = (code: UploadRejectCode): UploadValidationResult => ({ ok: false, code });
  try {
    if (compressed.length < 1 || compressed.length > (opts.maxCompressedBytes ?? MAX_COMPRESSED_BYTES)) {
      return reject("too_large");
    }
    if (!isSha256Hex(expectedContentSha256)) return reject("bad_sha");
    const contentSha256 = sha256Hex(compressed);
    if (!sha256Equal(contentSha256, expectedContentSha256)) return reject("sha_mismatch");
    if (compressed.length < 2 || compressed[0] !== GZIP_MAGIC_1 || compressed[1] !== GZIP_MAGIC_2) {
      return reject("not_gzip");
    }

    const json = await inflateBounded(compressed, opts);
    let parsed: unknown;
    try {
      // `fatal: true` rejects invalid UTF-8 instead of replacing it.
      parsed = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(json));
    } catch (err) {
      // `name` as well as instanceof: the decoder's TypeError can come from another realm (jest sandbox).
      return reject(err instanceof TypeError || (err as { name?: unknown })?.name === "TypeError" ? "bad_encoding" : "bad_json");
    }

    const result = validateStreamPayload(parsed);
    if (!result.ok) return reject(result.code);

    const storedBytes = deterministicGzip(canonicalJsonBytes(result.value));
    // Re-compression can differ slightly from the upload; the stored object
    // obeys the same compressed bound (design 5.1).
    if (storedBytes.length > (opts.maxCompressedBytes ?? MAX_COMPRESSED_BYTES)) {
      return reject("too_large");
    }
    return {
      ok: true,
      contentSha256,
      storedBytes,
      storedSha256: sha256Hex(storedBytes),
      kinds: CLOUD_STREAM_KINDS.filter((k) => result.value.kinds[k] !== undefined),
    };
  } catch (err) {
    if (err instanceof ByteReject) return reject(err.code);
    return reject("bad_json");
  }
}
