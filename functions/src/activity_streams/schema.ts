/**
 * Closed schema of the private activity stream object (S02 design 5.1, 5.1a,
 * story S02-04a). This module holds ONLY constants: key sets, bounds, enums
 * and per-string-field patterns. The validator (`validate.ts`) and the canonical
 * serialiser (`canonical.ts`) are the only readers.
 *
 * The key sets mirror the Dart builder `activity_stream_payload.dart`
 * (S02-01) and `SampleStream.toJson`; the shared fixture
 * `functions/src/__tests__/activity/fixtures/stream_schema_keys.json` pins both
 * sides (tests F53 and U37). `heartRate` is NOT an allowed kind and no
 * heart-rate key exists in any set below.
 *
 * Everything marked PROPOSED (bounds, plausibility ranges, string patterns)
 * is a starting value awaiting the security review the design demands before
 * the validator ships (design 5.1a). None of it is measured.
 */

/** Payload schema number (matches `kStreamPayloadSchema` in Dart). */
export const STREAM_PAYLOAD_SCHEMA = 1;

/** Kinds that may reach the cloud (design 5.1). Heart rate is not here. */
export const CLOUD_STREAM_KINDS = ["gps", "altitude", "speed"] as const;
export type CloudStreamKind = (typeof CLOUD_STREAM_KINDS)[number];

/** Canonical unit of each allowed kind (`StreamKind.unit` in Dart). */
export const STREAM_UNITS: Readonly<Record<CloudStreamKind, string>> = {
  gps: "deg",
  altitude: "m",
  speed: "m/s",
};

/** Closed key sets (order is the canonical serialisation order). */
export const TOP_LEVEL_KEYS = ["schema", "kinds", "meta"] as const;
export const META_KEYS = ["laps", "provenance"] as const;
export const STREAM_KEYS = [
  "kind",
  "unit",
  "sourceId",
  "offsetsMs",
  "values",
  "lats",
  "lons",
  "accuracies",
] as const;
export const LAP_KEYS = [
  "index",
  "kind",
  "startOffsetS",
  "durationS",
  "distanceM",
  "strokeCount",
  "strokeType",
] as const;
export const PROVENANCE_KEYS = [
  "sourceId",
  "sourceKind",
  "importedAt",
  "deviceModel",
  "appPackage",
  "externalId",
  "fieldsContributed",
] as const;

/** Bounds (design 5.1, PROPOSED, unmeasured). */
export const MAX_COMPRESSED_BYTES = 5 * 1024 * 1024;
export const MAX_DECOMPRESSED_BYTES = 32 * 1024 * 1024;
/** decompressed / compressed; the running total may equal but not exceed it. */
export const MAX_COMPRESSION_RATIO = 20;
export const MAX_DECOMPRESS_MS = 10_000;
export const MAX_SAMPLES_PER_STREAM = 200_000;
/** Largest sample offset: 7 days in milliseconds (PROPOSED). */
export const MAX_OFFSET_MS = 7 * 24 * 60 * 60 * 1000;
export const MAX_LAPS = 10_000;
export const MAX_PROVENANCE_RECORDS = 64;
export const MAX_FIELDS_CONTRIBUTED = 32;

/** Latitude and longitude limits are inclusive (design 5.1, F03). */
export const LAT_RANGE = { min: -90, max: 90 } as const;
export const LON_RANGE = { min: -180, max: 180 } as const;

/**
 * Plausibility ranges per kind (PROPOSED). A cheap partial defence against
 * non-stream numbers; NOT a guarantee against heart rate relabelled as an
 * allowed kind (design 5.1a accepted residual risk, DQ-6).
 */
export const VALUE_RANGES: Readonly<
  Record<"altitude" | "speed", { min: number; max: number }>
> = {
  altitude: { min: -1_000, max: 20_000 },
  speed: { min: 0, max: 150 },
};
export const ACCURACY_RANGE = { min: 0, max: 100_000 } as const;

/** Lap numeric ranges (PROPOSED). */
export const LAP_INDEX_MAX = 100_000;
export const LAP_SECONDS_MAX = MAX_OFFSET_MS / 1000;
export const LAP_DISTANCE_MAX_M = 10_000_000;
export const LAP_STROKE_COUNT_MAX = 1_000_000;

/** Enum names of `LapKind` and `StrokeType` in Dart. */
export const LAP_KINDS = ["auto", "manual", "poolLength", "interval"] as const;
export const STROKE_TYPES = ["free", "back", "breast", "fly", "mixed"] as const;
/** Enum names of `SourceKind` in Dart. */
export const SOURCE_KINDS = [
  "platformHealth",
  "bleSensor",
  "vendorCloud",
  "companionApp",
  "fileImport",
] as const;

/**
 * Per-string-field schema of laps and provenance records (design 5.1a closing
 * check: BOTH a length bound AND a regex per field).
 *
 * PROPOSED -- SECURITY REVIEW REQUIRED. The Dart regexes in
 * `activity_stream_payload.dart` are the starting point and are mirrored here
 * byte for byte (length bounds included). The server adds one stricter,
 * shared rule on top, `COORDINATE_LIKE`, which no field may match.
 */
export interface StringFieldRule {
  /** Maximum length in UTF-16 code units (also enforced inside the regex). */
  readonly maxLength: number;
  readonly pattern: RegExp;
}

export const PROVENANCE_STRING_RULES: Readonly<Record<string, StringFieldRule>> = {
  sourceId: { maxLength: 64, pattern: /^[A-Za-z0-9._:-]{1,64}$/ },
  sourceKind: {
    maxLength: 32,
    pattern: new RegExp(`^(?:${SOURCE_KINDS.join("|")})$`),
  },
  // ISO-8601 UTC as produced by Dart `toUtc().toIso8601String()`.
  importedAt: {
    maxLength: 32,
    pattern: /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/,
  },
  deviceModel: { maxLength: 64, pattern: /^[A-Za-z0-9 ._()-]{1,64}$/ },
  appPackage: { maxLength: 128, pattern: /^[a-z][a-z0-9_.]{0,127}$/ },
  externalId: { maxLength: 128, pattern: /^[A-Za-z0-9._:-]{1,128}$/ },
};

/** Each element of `fieldsContributed` (names of fields, never values). */
export const FIELD_CONTRIBUTED_RULE: StringFieldRule = {
  maxLength: 32,
  pattern: /^[A-Za-z][A-Za-z0-9]{0,31}$/,
};

/** Lap string fields (both are enum names). */
export const LAP_STRING_RULES: Readonly<Record<string, StringFieldRule>> = {
  kind: { maxLength: 16, pattern: new RegExp(`^(?:${LAP_KINDS.join("|")})$`) },
  strokeType: {
    maxLength: 16,
    pattern: new RegExp(`^(?:${STROKE_TYPES.join("|")})$`),
  },
};

/** `sourceId` of a stream record uses the provenance `sourceId` rule. */
export const STREAM_SOURCE_ID_RULE: StringFieldRule =
  PROVENANCE_STRING_RULES.sourceId;

/**
 * A string that looks like a coordinate: a number with at least two decimals
 * (`51.5007`, `-0.1276`, `173.25`), or two numbers separated by a comma. Rejected in EVERY free-form string field regardless of the field
 * regex (PROPOSED, design 5.1a closing check). Honest limit: a geohash or an
 * opaque id that merely encodes a position cannot be told from an ordinary id.
 */
export const COORDINATE_LIKE = /\d\.\d{2,}|\d\s*,\s*-?\d/;
