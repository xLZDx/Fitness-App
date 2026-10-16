/**
 * Pure model of `users/{uid}/activity_settings/main` (S02 design 3.2, 5.3, 9, 9.1).
 *
 * Everything here is free of Firebase imports so test agents can drive it with
 * plain objects: request parsing, the retention rule, the consent state and the
 * pure change planner `planSettingsChange`. The callable in
 * `set_settings.ts` only adds the shared hardening, the transaction and the
 * Firestore value types (server timestamps, field deletes).
 *
 * The document is server-authored (the Firestore rules deny every client
 * write), because the upload callables trust it: a client-forgeable consent
 * record would defeat the whole consent gate.
 */

/** Where the settings live, relative to the project root. */
export function activitySettingsPath(uid: string): string {
  return `users/${uid}/activity_settings/main`;
}

/** Version of the cloud-stream consent text. The SERVER records this, never the client value. */
export const CLOUD_STREAMS_CONSENT_VERSION = 1;

/**
 * ANSWERED by the operator on 2026-10-16 (question 12.3 item 1 / DQ-7):
 * default stream retention in days is 730 (two years). It is defined here once.
 */
export const DEFAULT_STREAM_RETENTION_DAYS = 730;

/**
 * ANSWERED by the operator on 2026-10-16 (question 12.3 item 1 / DQ-7): the
 * retention values the user may choose are 90 days, 1 year and 2 years (design
 * 5.3). Any other number (0, negative, fractional, huge) is refused.
 */
export const ALLOWED_STREAM_RETENTION_DAYS: readonly number[] = [90, 365, 730];

/**
 * ANSWERED by the operator on 2026-10-16 (question 12.3 item 1 / DQ-7): "never
 * expire" (`null`) is NOT offered, so `null` is refused everywhere (settings
 * validation and, in S02-05b, purge read this same constant so they cannot
 * disagree, test F13/F15). "Never" would mean GPS history is kept indefinitely.
 */
export const STREAM_RETENTION_NEVER_OFFERED = false;

/** A retention value as stored: whole days, or `null` meaning never expire. */
export type StreamRetentionDays = number | null;

/** True when `v` is a retention value this deployment accepts. */
export function isValidStreamRetentionDays(v: unknown): v is StreamRetentionDays {
  if (v === null) return STREAM_RETENTION_NEVER_OFFERED;
  return typeof v === "number" && Number.isInteger(v) && ALLOWED_STREAM_RETENTION_DAYS.includes(v);
}

/**
 * The retention in force for a settings document: the stored value when it is
 * valid (an explicit `null` is "never"), otherwise the default. Malformed or
 * absent data falls back to the default, never to "never".
 */
export function effectiveStreamRetentionDays(
  settings: Record<string, unknown> | undefined,
): StreamRetentionDays {
  const raw = settings?.streamRetentionDays;
  if (raw !== undefined && isValidStreamRetentionDays(raw)) return raw;
  return DEFAULT_STREAM_RETENTION_DAYS;
}

/** The settings generation, `0` when absent or malformed. */
export function settingsGenerationOf(settings: Record<string, unknown> | undefined): number {
  const g = settings?.settingsGeneration;
  return typeof g === "number" && Number.isInteger(g) && g >= 0 ? g : 0;
}

/** Epoch millis of a Firestore Timestamp-like value (`toMillis`) or a Date, else `undefined`. */
function millisOfLoose(v: unknown): number | undefined {
  if (v instanceof Date) return v.getTime();
  const m = (v as { toMillis?: unknown } | null | undefined)?.toMillis;
  if (typeof m === "function") {
    const n = (m as () => unknown).call(v);
    return typeof n === "number" && Number.isFinite(n) ? n : undefined;
  }
  return undefined;
}

export type CloudStreamsConsentState = "none" | "granted" | "withdrawn";

/**
 * Consent state of a settings document (used by the upload and commit callables
 * of S02-04b, which refuse everything but `granted` with `consent_withdrawn` or
 * a consent-required code). `granted` needs a recorded acceptance of the
 * CURRENT consent version and no withdrawal; anything malformed is `none`.
 */
export function cloudStreamsConsentState(
  settings: Record<string, unknown> | undefined,
): CloudStreamsConsentState {
  const c = settings?.cloudStreams as Record<string, unknown> | undefined;
  if (!c || typeof c !== "object") return "none";
  if (millisOfLoose(c.withdrawnAt) !== undefined) return "withdrawn";
  const accepted = millisOfLoose(c.acceptedAt) !== undefined;
  const version = c.version;
  if (accepted && typeof version === "number" && Number.isInteger(version) && version >= CLOUD_STREAMS_CONSENT_VERSION) {
    return "granted";
  }
  return "none";
}

/** A refusal with a bare, stable code (never a message that echoes client input). */
export class SettingsRequestError extends Error {
  constructor(readonly code: "invalid_request" | "invalid_retention" | "invalid_consent") {
    super(code);
    this.name = "SettingsRequestError";
  }
}

/** A parsed, validated request. At least one of the two fields is present. */
export interface SettingsRequest {
  /** Present when the caller sets retention; whole days, `null` ("never") is refused by the validator. */
  streamRetentionDays?: StreamRetentionDays;
  /** Present when the caller grants (`true`) or withdraws (`false`) cloud-stream consent. */
  cloudStreamsGranted?: boolean;
  /**
   * Present (true) only together with a withdrawal (`granted: false`): the user took the
   * offer to also delete the existing cloud streams, so the call starts the bulk
   * stream-delete job (design 9.1). Summaries are kept.
   */
  deleteExistingStreams?: boolean;
}

function isPlainObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

/**
 * Strict closed parse (design 5.4: validation first, bare codes). Unknown keys
 * are refused, never ignored. Request shape:
 *
 *   { streamRetentionDays?: 90 | 365 | 730,
 *     cloudStreams?: { granted: boolean, version: number, deleteExisting?: boolean } }
 *
 * `deleteExisting: true` is accepted only with `granted: false` (design 9.1: the
 * withdrawal itself starts the bulk delete job when the user chose the offer).
 * `deleteExisting: false` is the same as omitting it.
 *
 * `cloudStreams.version` must equal `CLOUD_STREAMS_CONSENT_VERSION`: a client
 * that showed an older consent text cannot grant consent to the current one.
 */
export function parseSettingsRequest(data: unknown): SettingsRequest {
  if (!isPlainObject(data)) throw new SettingsRequestError("invalid_request");
  for (const key of Object.keys(data)) {
    if (key !== "streamRetentionDays" && key !== "cloudStreams") {
      throw new SettingsRequestError("invalid_request");
    }
  }
  const out: SettingsRequest = {};
  if ("streamRetentionDays" in data) {
    if (!isValidStreamRetentionDays(data.streamRetentionDays)) {
      throw new SettingsRequestError("invalid_retention");
    }
    out.streamRetentionDays = data.streamRetentionDays;
  }
  if ("cloudStreams" in data) {
    const c = data.cloudStreams;
    if (!isPlainObject(c)) throw new SettingsRequestError("invalid_consent");
    for (const key of Object.keys(c)) {
      if (key !== "granted" && key !== "version" && key !== "deleteExisting") {
        throw new SettingsRequestError("invalid_consent");
      }
    }
    if (typeof c.granted !== "boolean" || c.version !== CLOUD_STREAMS_CONSENT_VERSION) {
      throw new SettingsRequestError("invalid_consent");
    }
    if ("deleteExisting" in c) {
      if (typeof c.deleteExisting !== "boolean") throw new SettingsRequestError("invalid_consent");
      // Deleting streams while granting consent makes no sense: refuse, never ignore.
      if (c.deleteExisting && c.granted) throw new SettingsRequestError("invalid_consent");
      if (c.deleteExisting) out.deleteExistingStreams = true;
    }
    out.cloudStreamsGranted = c.granted;
  }
  if (out.streamRetentionDays === undefined && out.cloudStreamsGranted === undefined) {
    throw new SettingsRequestError("invalid_request");
  }
  return out;
}

/**
 * True when the request is a pure withdrawal of consent. Withdrawal is an
 * erasure-side action: the callable does not charge the daily quota for it, so
 * a user can always withdraw (design 9.1).
 */
export function isWithdrawalOnly(req: SettingsRequest): boolean {
  return req.cloudStreamsGranted === false && req.streamRetentionDays === undefined;
}

/** What a request changes, computed from the current document and the injected clock. */
export interface SettingsPlan {
  /** False when the request equals the current state: nothing is written, the generation stays. */
  changed: boolean;
  /** The generation after the call (current + 1 when changed). */
  settingsGeneration: number;
  /** The retention after the call. */
  streamRetentionDays: StreamRetentionDays;
  /** The consent state after the call. */
  consent: CloudStreamsConsentState;
  /** Set when the retention value changed: the purge continuation must recompute hints (5.3). */
  recomputePending: boolean;
  /** Present when consent is granted by this call (server time, millis). */
  grantedAtMs?: number;
  /** Present when consent is withdrawn by this call (server time, millis). */
  withdrawnAtMs?: number;
  /** True when the retention changed (the cursor is reset, 5.3). */
  retentionChanged: boolean;
  /** True when a withdrawal was recorded by this call (design 9.1). */
  withdrew: boolean;
  /**
   * True when the request asked to delete the existing streams and consent is not
   * granted after the call. The callable starts the bulk job unless one is already
   * active (it never replaces a running job). Independent of `changed`: a user who
   * withdrew earlier may take the offer later.
   */
  startStreamDelete: boolean;
}

/**
 * Pure transition. One call is one atomic change: retention, consent and the
 * generation move together (F75). An identical request is a no-op, so a
 * replayed or double-tapped call neither bumps the generation nor queues a
 * recompute. The generation increments exactly once per effective change, even
 * when retention and consent change in the same call.
 *
 * Consent rules: granting records a server timestamp and the current consent
 * version and clears an earlier withdrawal; withdrawing records `withdrawnAt`
 * (it keeps the earlier acceptance as history) and is the signal that makes the
 * upload and commit callables refuse with `consent_withdrawn` (design 9.1).
 * Withdrawing when no consent was ever granted records nothing (`none` stays
 * `none`); granting again after a grant is a no-op.
 */
export function planSettingsChange(
  current: Record<string, unknown> | undefined,
  req: SettingsRequest,
  nowMs: number,
): SettingsPlan {
  const generation = settingsGenerationOf(current);
  const retentionBefore = effectiveStreamRetentionDays(current);
  const consentBefore = cloudStreamsConsentState(current);

  let retentionAfter = retentionBefore;
  let retentionChanged = false;
  if (req.streamRetentionDays !== undefined && req.streamRetentionDays !== retentionBefore) {
    retentionAfter = req.streamRetentionDays;
    retentionChanged = true;
  }

  let consentAfter = consentBefore;
  let grantedAtMs: number | undefined;
  let withdrawnAtMs: number | undefined;
  if (req.cloudStreamsGranted === true && consentBefore !== "granted") {
    consentAfter = "granted";
    grantedAtMs = nowMs;
  } else if (req.cloudStreamsGranted === false && consentBefore === "granted") {
    consentAfter = "withdrawn";
    withdrawnAtMs = nowMs;
  }

  const consentChanged = consentAfter !== consentBefore;
  const changed = retentionChanged || consentChanged;
  const previouslyPending = current?.recomputePending === true;
  return {
    changed,
    settingsGeneration: changed ? generation + 1 : generation,
    streamRetentionDays: retentionAfter,
    consent: consentAfter,
    // A pending recompute from an earlier change stays pending until the purge clears it.
    recomputePending: retentionChanged || previouslyPending,
    grantedAtMs,
    withdrawnAtMs,
    retentionChanged,
    withdrew: withdrawnAtMs !== undefined,
    startStreamDelete: req.deleteExistingStreams === true && consentAfter !== "granted",
  };
}
