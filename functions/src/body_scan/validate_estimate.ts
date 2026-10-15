/**
 * Output validation for a provider estimate (design s7.2 `validateEstimate`).
 *
 * A provider is an external, replaceable component, so its output is treated as
 * untrusted data: every number must be finite and in range, the confidence and
 * every check code must be members of a closed list, and the traceability
 * strings must be bounded. A violation is an `internal: provider-output-invalid`
 * error and the scan stays `pending` (retryable) -- never a silent clamp of
 * nonsense into something that looks plausible.
 */
import { HttpsError } from "firebase-functions/v2/https";
import {
  CHECK_CODES,
  CONFIDENCES,
  type CheckCode,
  type Confidence,
  type StoredEstimate,
} from "./types";

export const PROVIDER_OUTPUT_INVALID = "provider-output-invalid";

/** Plausible body-fat bounds (percent) and the widest accepted range. */
const MIN_PCT = 3;
const MAX_PCT = 60;
const MAX_RANGE_WIDTH_PTS = 20;
const MAX_ID_LENGTH = 64;

const CHECK_CODE_SET: ReadonlySet<string> = new Set(CHECK_CODES);
const CONFIDENCE_SET: ReadonlySet<string> = new Set(CONFIDENCES);

function invalid(): never {
  throw new HttpsError("internal", PROVIDER_OUTPUT_INVALID);
}

function isBoundedString(value: unknown): value is string {
  return (
    typeof value === "string" && value.length > 0 && value.length <= MAX_ID_LENGTH
  );
}

/**
 * Validates one provider output and returns the exact block that is stored.
 * Unknown extra keys on `raw` are dropped (the result is rebuilt field by
 * field), so nothing a provider adds can reach the document.
 */
export function validateEstimate(
  raw: unknown,
  modelId: unknown,
  modelVersion: unknown,
): StoredEstimate {
  if (typeof raw !== "object" || raw === null) invalid();
  const o = raw as Record<string, unknown>;

  const value = o.bodyFatPct;
  const low = o.rangeLowPct;
  const high = o.rangeHighPct;
  if (
    typeof value !== "number" || !Number.isFinite(value) ||
    typeof low !== "number" || !Number.isFinite(low) ||
    typeof high !== "number" || !Number.isFinite(high)
  ) {
    invalid();
  }
  const v = value as number;
  const lo = low as number;
  const hi = high as number;
  if (!(MIN_PCT <= lo && lo <= v && v <= hi && hi <= MAX_PCT)) invalid();
  if (hi - lo > MAX_RANGE_WIDTH_PTS) invalid();

  if (typeof o.confidence !== "string" || !CONFIDENCE_SET.has(o.confidence)) {
    invalid();
  }
  if (!Array.isArray(o.checkCodes) || o.checkCodes.length > CHECK_CODES.length) {
    invalid();
  }
  const codes = o.checkCodes as unknown[];
  for (const code of codes) {
    if (typeof code !== "string" || !CHECK_CODE_SET.has(code)) invalid();
  }

  if (!isBoundedString(modelId) || !isBoundedString(modelVersion)) invalid();

  return {
    bodyFatPct: v,
    rangeLowPct: lo,
    rangeHighPct: hi,
    confidence: o.confidence as Confidence,
    checkCodes: Array.from(new Set(codes as CheckCode[])),
    modelId: modelId as string,
    modelVersion: modelVersion as string,
  };
}
