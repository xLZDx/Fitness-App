/**
 * Pure closed-schema validator of the PARSED activity stream object (S02
 * design 5.1a, story S02-04a). No I/O, no clock, no logging.
 *
 * Contract:
 *  - the input is whatever `JSON.parse` returned (`unknown`); nothing is
 *    trusted;
 *  - an unknown key at ANY depth is REJECTED, never stripped (so a heart-rate
 *    key can never be silently dropped and then stored next to clean data);
 *  - the output is a NEW object built key by key from the validated values in
 *    the canonical key order, so a prototype-polluting or extra key can never
 *    survive into the stored bytes;
 *  - rejection is a bare code (`StreamRejectCode`); no message ever echoes a
 *    client value (GPS-PRIV-094).
 */
import {
  ACCURACY_RANGE,
  CLOUD_STREAM_KINDS,
  COORDINATE_LIKE,
  FIELD_CONTRIBUTED_RULE,
  LAP_DISTANCE_MAX_M,
  LAP_INDEX_MAX,
  LAP_KEYS,
  LAP_SECONDS_MAX,
  LAP_STRING_RULES,
  LAP_STROKE_COUNT_MAX,
  LAT_RANGE,
  LON_RANGE,
  MAX_FIELDS_CONTRIBUTED,
  MAX_LAPS,
  MAX_OFFSET_MS,
  MAX_PROVENANCE_RECORDS,
  MAX_SAMPLES_PER_STREAM,
  META_KEYS,
  PROVENANCE_KEYS,
  PROVENANCE_STRING_RULES,
  STREAM_KEYS,
  STREAM_PAYLOAD_SCHEMA,
  STREAM_SOURCE_ID_RULE,
  STREAM_UNITS,
  TOP_LEVEL_KEYS,
  VALUE_RANGES,
  type CloudStreamKind,
  type StringFieldRule,
} from "./schema";

/** Bare rejection codes. Each one is a distinct, separately testable branch. */
export type StreamRejectCode =
  | "bad_json"
  | "bad_schema"
  | "bad_shape"
  | "unknown_key"
  | "forbidden_kind"
  | "empty"
  | "too_many"
  | "bad_number"
  | "out_of_range"
  | "not_monotonic"
  | "length_mismatch"
  | "bad_string";

export interface CanonicalStream {
  kind: CloudStreamKind;
  unit: string;
  sourceId: string;
  offsetsMs: number[];
  values?: number[];
  lats?: number[];
  lons?: number[];
  accuracies?: number[];
}

export interface CanonicalLap {
  index: number;
  kind: string;
  startOffsetS: number;
  durationS: number;
  distanceM?: number;
  strokeCount?: number;
  strokeType?: string;
}

export interface CanonicalProvenance {
  sourceId: string;
  sourceKind: string;
  importedAt: string;
  deviceModel?: string;
  appPackage?: string;
  externalId?: string;
  fieldsContributed: string[];
}

export interface CanonicalPayload {
  schema: number;
  kinds: Partial<Record<CloudStreamKind, CanonicalStream>>;
  meta: { laps: CanonicalLap[]; provenance: CanonicalProvenance[] };
}

export type ValidationResult =
  | { ok: true; value: CanonicalPayload }
  | { ok: false; code: StreamRejectCode };

class Reject extends Error {
  constructor(readonly code: StreamRejectCode) {
    super(code);
  }
}

const fail = (code: StreamRejectCode): never => {
  throw new Reject(code);
};

/** Key names that name heart rate in any case or spelling (code only; the key set is closed anyway). */
const HEART_RATE_NAME = /heart|(?:^|[^a-z])hr(?:[^a-z]|$)|bpm/i;

const hasOwn = (o: object, k: string): boolean =>
  Object.prototype.hasOwnProperty.call(o, k);

/** A plain JSON object whose own keys are all in `allowed` and include `required`. */
function closedObject(
  value: unknown,
  allowed: readonly string[],
  required: readonly string[],
): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return fail("bad_shape");
  }
  const proto = Object.getPrototypeOf(value);
  if (proto !== Object.prototype && proto !== null) return fail("bad_shape");
  const obj = value as Record<string, unknown>;
  for (const key of Object.keys(obj)) {
    if (!allowed.includes(key)) {
      return fail(HEART_RATE_NAME.test(key) ? "forbidden_kind" : "unknown_key");
    }
  }
  for (const key of required) if (!hasOwn(obj, key)) return fail("bad_shape");
  return obj;
}

function finiteNumber(v: unknown): number {
  if (typeof v !== "number" || !Number.isFinite(v)) return fail("bad_number");
  return v;
}

function numberIn(v: unknown, min: number, max: number): number {
  const n = finiteNumber(v);
  if (n < min || n > max) return fail("out_of_range");
  return n;
}

function intIn(v: unknown, min: number, max: number): number {
  const n = finiteNumber(v);
  if (!Number.isSafeInteger(n)) return fail("bad_number");
  if (n < min || n > max) return fail("out_of_range");
  return n;
}

/** Length bound AND per-field regex AND the shared coordinate-like denial. */
function checkedString(v: unknown, rule: StringFieldRule): string {
  if (typeof v !== "string") return fail("bad_string");
  if (v.length < 1 || v.length > rule.maxLength) return fail("bad_string");
  if (!rule.pattern.test(v)) return fail("bad_string");
  if (COORDINATE_LIKE.test(v)) return fail("bad_string");
  return v;
}

function numberList(
  v: unknown,
  each: (n: unknown) => number,
): number[] {
  if (!Array.isArray(v)) return fail("bad_shape");
  if (v.length > MAX_SAMPLES_PER_STREAM) return fail("too_many");
  const out: number[] = new Array<number>(v.length);
  for (let i = 0; i < v.length; i++) out[i] = each(v[i]);
  return out;
}

function validateStream(key: CloudStreamKind, raw: unknown): CanonicalStream {
  const isGps = key === "gps";
  const required = isGps
    ? ["kind", "unit", "sourceId", "offsetsMs", "lats", "lons"]
    : ["kind", "unit", "sourceId", "offsetsMs", "values"];
  const o = closedObject(raw, STREAM_KEYS, required);

  if (o.kind !== key) return fail("bad_shape");
  if (o.unit !== STREAM_UNITS[key]) return fail("bad_shape");
  // GPS carries no `values`; every other kind carries no lat/lon/accuracy.
  if (isGps && hasOwn(o, "values")) return fail("bad_shape");
  if (!isGps && (hasOwn(o, "lats") || hasOwn(o, "lons") || hasOwn(o, "accuracies"))) {
    return fail("bad_shape");
  }

  const sourceId = checkedString(o.sourceId, STREAM_SOURCE_ID_RULE);
  const offsetsMs = numberList(o.offsetsMs, (n) => intIn(n, 0, MAX_OFFSET_MS));
  if (offsetsMs.length === 0) return fail("empty");
  for (let i = 1; i < offsetsMs.length; i++) {
    if (offsetsMs[i] <= offsetsMs[i - 1]) return fail("not_monotonic");
  }

  const out: CanonicalStream = {
    kind: key,
    unit: STREAM_UNITS[key],
    sourceId,
    offsetsMs,
  };
  if (isGps) {
    out.lats = numberList(o.lats, (n) => numberIn(n, LAT_RANGE.min, LAT_RANGE.max));
    out.lons = numberList(o.lons, (n) => numberIn(n, LON_RANGE.min, LON_RANGE.max));
    if (out.lats.length !== offsetsMs.length || out.lons.length !== offsetsMs.length) {
      return fail("length_mismatch");
    }
    if (hasOwn(o, "accuracies")) {
      out.accuracies = numberList(o.accuracies, (n) =>
        numberIn(n, ACCURACY_RANGE.min, ACCURACY_RANGE.max),
      );
      if (out.accuracies.length !== offsetsMs.length) return fail("length_mismatch");
    }
  } else {
    const range = VALUE_RANGES[key as "altitude" | "speed"];
    out.values = numberList(o.values, (n) => numberIn(n, range.min, range.max));
    if (out.values.length !== offsetsMs.length) return fail("length_mismatch");
  }
  return out;
}

function validateLap(raw: unknown): CanonicalLap {
  const o = closedObject(raw, LAP_KEYS, ["index", "kind", "startOffsetS", "durationS"]);
  const lap: CanonicalLap = {
    index: intIn(o.index, 0, LAP_INDEX_MAX),
    kind: checkedString(o.kind, LAP_STRING_RULES.kind),
    startOffsetS: numberIn(o.startOffsetS, 0, LAP_SECONDS_MAX),
    durationS: numberIn(o.durationS, 0, LAP_SECONDS_MAX),
  };
  if (hasOwn(o, "distanceM")) lap.distanceM = numberIn(o.distanceM, 0, LAP_DISTANCE_MAX_M);
  if (hasOwn(o, "strokeCount")) {
    lap.strokeCount = intIn(o.strokeCount, 0, LAP_STROKE_COUNT_MAX);
  }
  if (hasOwn(o, "strokeType")) {
    lap.strokeType = checkedString(o.strokeType, LAP_STRING_RULES.strokeType);
  }
  return lap;
}

function validateProvenance(raw: unknown): CanonicalProvenance {
  const o = closedObject(raw, PROVENANCE_KEYS, [
    "sourceId",
    "sourceKind",
    "importedAt",
    "fieldsContributed",
  ]);
  const rec: CanonicalProvenance = {
    sourceId: checkedString(o.sourceId, PROVENANCE_STRING_RULES.sourceId),
    sourceKind: checkedString(o.sourceKind, PROVENANCE_STRING_RULES.sourceKind),
    importedAt: checkedString(o.importedAt, PROVENANCE_STRING_RULES.importedAt),
    fieldsContributed: [],
  };
  // The regex checks the shape; this rejects impossible dates such as month 13.
  if (Number.isNaN(Date.parse(rec.importedAt))) return fail("bad_string");
  for (const k of ["deviceModel", "appPackage", "externalId"] as const) {
    if (hasOwn(o, k)) rec[k] = checkedString(o[k], PROVENANCE_STRING_RULES[k]);
  }
  const fields = o.fieldsContributed;
  if (!Array.isArray(fields)) return fail("bad_shape");
  if (fields.length > MAX_FIELDS_CONTRIBUTED) return fail("too_many");
  rec.fieldsContributed = fields.map((f) => checkedString(f, FIELD_CONTRIBUTED_RULE));
  return rec;
}

function validateList<T>(raw: unknown, max: number, each: (v: unknown) => T): T[] {
  if (!Array.isArray(raw)) return fail("bad_shape");
  if (raw.length > max) return fail("too_many");
  return raw.map(each);
}

/**
 * Validates a parsed stream object and returns its canonical form, or a bare
 * rejection code. Never throws for any input.
 */
export function validateStreamPayload(parsed: unknown): ValidationResult {
  try {
    const top = closedObject(parsed, TOP_LEVEL_KEYS, TOP_LEVEL_KEYS);
    if (top.schema !== STREAM_PAYLOAD_SCHEMA) return fail("bad_schema");

    const kindsRaw = closedObject(top.kinds, CLOUD_STREAM_KINDS, []);
    const kinds: Partial<Record<CloudStreamKind, CanonicalStream>> = {};
    for (const kind of CLOUD_STREAM_KINDS) {
      if (hasOwn(kindsRaw, kind)) kinds[kind] = validateStream(kind, kindsRaw[kind]);
    }
    if (Object.keys(kinds).length === 0) return fail("empty");

    const meta = closedObject(top.meta, META_KEYS, META_KEYS);
    const value: CanonicalPayload = {
      schema: STREAM_PAYLOAD_SCHEMA,
      kinds,
      meta: {
        laps: validateList(meta.laps, MAX_LAPS, validateLap),
        provenance: validateList(
          meta.provenance,
          MAX_PROVENANCE_RECORDS,
          validateProvenance,
        ),
      },
    };
    return { ok: true, value };
  } catch (err) {
    if (err instanceof Reject) return { ok: false, code: err.code };
    // Unexpected failure: still a bare code, never a message.
    return { ok: false, code: "bad_shape" };
  }
}
