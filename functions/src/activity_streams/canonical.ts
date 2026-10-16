/**
 * Canonical re-serialisation of a VALIDATED stream payload (S02 design 5.1a):
 * the object promoted to `streams/` is re-serialised from the parsed
 * structure, never the uploaded bytes, so `storedSha256` identifies a form the
 * server fully controls.
 *
 * Canonical form:
 *  - JSON without whitespace, keys in the fixed order of `schema.ts`
 *    (insertion order of the objects built here), optional keys omitted;
 *  - numbers via `JSON.stringify` (shortest round-trip form, `-0` as `0`);
 *  - UTF-8 bytes;
 *  - gzip level 9 with the OS byte of the header pinned to 255 ("unknown") so
 *    the same JSON always yields the same bytes on every platform and zlib
 *    build. (`mtime` is already 0 in Node's gzip output; no file name is set.)
 *
 * Re-serialising the output of this module is a fixed point
 * (`canonicalJson(validate(parse(canonicalJson(x)))) === canonicalJson(x)`).
 */
import { gzipSync } from "zlib";
import { CLOUD_STREAM_KINDS, STREAM_KEYS } from "./schema";
import type {
  CanonicalLap,
  CanonicalPayload,
  CanonicalProvenance,
  CanonicalStream,
} from "./validate";

const GZIP_OS_BYTE_OFFSET = 9;
const GZIP_OS_UNKNOWN = 255;

function orderedStream(s: CanonicalStream): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  const src = s as unknown as Record<string, unknown>;
  for (const key of STREAM_KEYS) if (src[key] !== undefined) out[key] = src[key];
  return out;
}

function orderedLap(l: CanonicalLap): Record<string, unknown> {
  const out: Record<string, unknown> = {
    index: l.index,
    kind: l.kind,
    startOffsetS: l.startOffsetS,
    durationS: l.durationS,
  };
  if (l.distanceM !== undefined) out.distanceM = l.distanceM;
  if (l.strokeCount !== undefined) out.strokeCount = l.strokeCount;
  if (l.strokeType !== undefined) out.strokeType = l.strokeType;
  return out;
}

function orderedProvenance(p: CanonicalProvenance): Record<string, unknown> {
  const out: Record<string, unknown> = {
    sourceId: p.sourceId,
    sourceKind: p.sourceKind,
    importedAt: p.importedAt,
  };
  if (p.deviceModel !== undefined) out.deviceModel = p.deviceModel;
  if (p.appPackage !== undefined) out.appPackage = p.appPackage;
  if (p.externalId !== undefined) out.externalId = p.externalId;
  out.fieldsContributed = p.fieldsContributed;
  return out;
}

/** The canonical JSON text of a validated payload. */
export function canonicalJson(payload: CanonicalPayload): string {
  const kinds: Record<string, unknown> = {};
  for (const kind of CLOUD_STREAM_KINDS) {
    const s = payload.kinds[kind];
    if (s !== undefined) kinds[kind] = orderedStream(s);
  }
  return JSON.stringify({
    schema: payload.schema,
    kinds,
    meta: {
      laps: payload.meta.laps.map(orderedLap),
      provenance: payload.meta.provenance.map(orderedProvenance),
    },
  });
}

/** Canonical UTF-8 bytes (uncompressed). */
export function canonicalJsonBytes(payload: CanonicalPayload): Buffer {
  return Buffer.from(canonicalJson(payload), "utf8");
}

/** Deterministic gzip of `bytes` (see the module comment). */
export function deterministicGzip(bytes: Uint8Array): Buffer {
  const gz = gzipSync(bytes, { level: 9 });
  gz[GZIP_OS_BYTE_OFFSET] = GZIP_OS_UNKNOWN;
  return gz;
}

/** The exact bytes stored under `streams/`: deterministic gzip of the canonical JSON. */
export function canonicalStoredBytes(payload: CanonicalPayload): Buffer {
  return deterministicGzip(canonicalJsonBytes(payload));
}
