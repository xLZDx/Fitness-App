/**
 * The CLOSED debug-telemetry schema and its pure sanitiser (S02 design 8, 8.1;
 * story S02-09; GPS-PRIV-050 / 098).
 *
 * Guarantee: a batch that passes `sanitizeTelemetryBatch` cannot carry a
 * coordinate, a geohash, a heart-rate value or a place name, because
 *   - every string value comes from an ENUMERATION below (no free text, no
 *     identifier-shaped strings, so a geohash such as `u4pruyd` is not in any set);
 *   - every number is a named integer COUNTER capped at `TELEMETRY_COUNTER_MAX`
 *     (255; a 6-digit value or a scaled latitude cannot fit);
 *   - events are FLAT maps (no nested map, no list inside an event), keys are a
 *     closed set, and unknown keys reject the whole batch;
 *   - `identity`, `uid` and `receivedAt` are never accepted from the client: the
 *     callable derives them (identity from `request.auth`, time from the server clock).
 *
 * The first violation rejects the WHOLE batch with a bare code; no code echoes a
 * client value. Residual honest limit (design 5.1a, DQ-6): a small counter can
 * still carry a number a modified client chose; that is not detectable here.
 *
 * Pure: no I/O, no clock. The Dart client keeps a mirror table
 * (`mobile/lib/core/diagnostics/debug_telemetry_schema.dart`); the shared fixture
 * `functions/src/__tests__/activity/fixtures/telemetry_schema.json` is the data
 * form of `TELEMETRY_SCHEMA` below.
 */

/** Maximum of every counter (design 8.1 closing check). */
export const TELEMETRY_COUNTER_MAX = 255;

/** Events per call (design 8.1, starting value). */
export const TELEMETRY_MAX_EVENTS = 100;

/** Serialised batch size cap in bytes (design 8.1, starting value: 16 KiB). */
export const TELEMETRY_MAX_BATCH_BYTES = 16 * 1024;

/** Closed bare refusal codes of the sanitiser. */
export type TelemetryRefusal = "batch_too_large" | "too_many_events" | "invalid_batch";

export interface EnumField {
  kind: "enum";
  values: readonly string[];
  required: boolean;
}

export interface CounterField {
  kind: "counter";
  max: number;
  required: boolean;
}

export type TelemetryField = EnumField | CounterField;

/**
 * The reviewed field table. Event fields only; top-level keys are
 * `events` and `droppedCount` (a counter), see `top`.
 */
export const TELEMETRY_SCHEMA = {
  /** Event fields. */
  event: {
    type: {
      kind: "enum",
      values: ["log", "lifecycle", "error", "metric", "permission", "network"],
      required: true,
    },
    level: { kind: "enum", values: ["debug", "info", "warn", "error"], required: true },
    component: {
      kind: "enum",
      values: [
        "app",
        "auth",
        "scanner",
        "camera",
        "catalog",
        "recognition",
        "workout",
        "nutrition",
        "activity",
        "sync",
        "export",
        "settings",
        "print",
        "other",
      ],
      required: true,
    },
    code: {
      kind: "enum",
      values: [
        "none",
        "ok",
        "failed",
        "denied",
        "timeout",
        "unavailable",
        "cancelled",
        "fallback",
        "retry",
        "started",
        "stopped",
        "other",
      ],
      required: false,
    },
    /** Occurrence count of the event (for example how many times it repeated). */
    count: { kind: "counter", max: TELEMETRY_COUNTER_MAX, required: false },
    /** Position of the event inside the batch, 0..255. */
    seq: { kind: "counter", max: TELEMETRY_COUNTER_MAX, required: false },
  },
  /** Top-level counters. `droppedCount` is reported by the callable as a metric, not stored. */
  top: {
    droppedCount: { kind: "counter", max: TELEMETRY_COUNTER_MAX, required: false },
  },
  /** Server-derived identity values (sign-in provider, never a client string). */
  providers: ["password", "google", "apple", "phone", "custom", "other"],
} as const;

export interface TelemetryEvent {
  type: string;
  level: string;
  component: string;
  code?: string;
  count?: number;
  seq?: number;
}

export interface TelemetryBatch {
  events: TelemetryEvent[];
  /** 0 when the client sent none; the callable emits a metric only when it was sent. */
  droppedCount: number;
  droppedReported: boolean;
}

export type SanitizeResult =
  | { ok: true; batch: TelemetryBatch }
  | { ok: false; code: TelemetryRefusal };

const EVENT_FIELDS = TELEMETRY_SCHEMA.event;
const EVENT_KEYS = Object.keys(EVENT_FIELDS) as (keyof typeof EVENT_FIELDS)[];
const TOP_KEYS = new Set(["events", "droppedCount"]);

function isPlainObject(v: unknown): v is Record<string, unknown> {
  if (typeof v !== "object" || v === null || Array.isArray(v)) return false;
  const proto = Object.getPrototypeOf(v);
  return proto === Object.prototype || proto === null;
}

function validCounter(v: unknown, max: number): v is number {
  return typeof v === "number" && Number.isInteger(v) && v >= 0 && v <= max;
}

/** Serialised size in bytes, or -1 when the value cannot be serialised (cycle, BigInt). */
function serialisedBytes(data: unknown): number {
  try {
    const text = JSON.stringify(data);
    return text === undefined ? -1 : Buffer.byteLength(text, "utf8");
  } catch {
    return -1;
  }
}

function sanitizeEvent(raw: unknown): TelemetryEvent | undefined {
  if (!isPlainObject(raw)) return undefined;
  for (const key of Object.keys(raw)) {
    if (!Object.prototype.hasOwnProperty.call(EVENT_FIELDS, key)) return undefined;
  }
  const out: Record<string, string | number> = {};
  for (const key of EVENT_KEYS) {
    const spec: TelemetryField = EVENT_FIELDS[key];
    const present = Object.prototype.hasOwnProperty.call(raw, key);
    if (!present) {
      if (spec.required) return undefined;
      continue;
    }
    const value = raw[key];
    if (spec.kind === "enum") {
      if (typeof value !== "string" || !spec.values.includes(value)) return undefined;
      out[key] = value;
    } else {
      if (!validCounter(value, spec.max)) return undefined;
      out[key] = value;
    }
  }
  return out as unknown as TelemetryEvent;
}

/**
 * Validates a whole request payload. Order: size, shape, event count, then each
 * event; the first violation returns a bare code and nothing is kept.
 */
export function sanitizeTelemetryBatch(data: unknown): SanitizeResult {
  const bytes = serialisedBytes(data);
  if (bytes < 0) return { ok: false, code: "invalid_batch" };
  if (bytes > TELEMETRY_MAX_BATCH_BYTES) return { ok: false, code: "batch_too_large" };
  if (!isPlainObject(data)) return { ok: false, code: "invalid_batch" };
  for (const key of Object.keys(data)) {
    if (!TOP_KEYS.has(key)) return { ok: false, code: "invalid_batch" };
  }
  const events = data.events;
  if (!Array.isArray(events)) return { ok: false, code: "invalid_batch" };
  if (events.length > TELEMETRY_MAX_EVENTS) return { ok: false, code: "too_many_events" };

  const droppedReported = Object.prototype.hasOwnProperty.call(data, "droppedCount");
  let droppedCount = 0;
  if (droppedReported) {
    if (!validCounter(data.droppedCount, EVENT_FIELDS.count.max)) {
      return { ok: false, code: "invalid_batch" };
    }
    droppedCount = data.droppedCount;
  }

  const clean: TelemetryEvent[] = [];
  for (const raw of events) {
    const event = sanitizeEvent(raw);
    if (event === undefined) return { ok: false, code: "invalid_batch" };
    clean.push(event);
  }
  return { ok: true, batch: { events: clean, droppedCount, droppedReported } };
}

/**
 * Maps the Firebase sign-in provider to the closed `providers` enumeration; any
 * other (or missing) value becomes `other`. The identity of a session is derived
 * from this, never from the payload.
 */
export function identityFromProvider(signInProvider: string | undefined): string {
  switch (signInProvider) {
    case "password":
      return "password";
    case "google.com":
      return "google";
    case "apple.com":
      return "apple";
    case "phone":
      return "phone";
    case "custom":
      return "custom";
    default:
      return "other";
  }
}
