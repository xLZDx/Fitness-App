/**
 * `sendDebugTelemetry` -- the sanitising callable that is the only writer of
 * `debug_sessions` (S02 design 8, 8.1; story S02-09; GPS-PRIV-050 / 098).
 *
 * Option A of the design: the client no longer writes `debug_sessions` (rules
 * `create: false`); it sends a batch here and the closed schema in
 * `telemetry_schema.ts` decides, per element, whether anything is stored. The
 * stored document keeps the Phase 1 collection and the keys `identity`,
 * `events`, `uid`, `receivedAt` (Admin SDK write), so the export and the
 * deletion sweep (`owned("debug_sessions", "uid")`) are unchanged.
 *
 * Hardening (design 5.4, 8.1): auth required, anonymous users refused, App Check
 * noted (and enforced by the shared profile flag), closed schema and enumerated
 * strings, counters <= 255, whole batch rejected at the first violation, `uid` and
 * `receivedAt` set server-side, `identity` derived from `request.auth`, the
 * account fence and Auth existence read INSIDE the write transaction, two redacted
 * daily quotas, bare codes only, logs carry codes and counts only.
 *
 * Drop signal (design 6.3): when the batch states `droppedCount`, the callable
 * emits it as a structured-log metric (no uid, no id). It is NOT stored in the
 * session document and a batch without the counter emits nothing.
 */
import { randomBytes } from "crypto";
import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { RARE } from "../scaling";
import { QUOTAS, enforceDailyQuota, noteAppCheck, refundQuota } from "../abuse_guard";
import { checkAccountFence, defaultFenceDeps, type FenceDeps } from "./fence";
import { sanitizeTelemetryBatch, identityFromProvider } from "./telemetry_schema";
import { errorCodeOf } from "./upload_common";

/** Quota actions (design 5.4, 8.1); both also listed in `REDACTED_QUOTA_ACTIONS`. */
export const TELEMETRY_CALL_QUOTA_ACTION = "debugTelemetrySend";
export const TELEMETRY_EVENT_QUOTA_ACTION = "debugTelemetryEvents";

/** Structured-log message names. */
export const DEBUG_TELEMETRY_EVENT = "debug_telemetry_event";
export const DEBUG_TELEMETRY_DROP_EVENT = "debug_telemetry_dropped";

/** Callable timeout in seconds (design 8.1: a small, bounded value). */
export const TELEMETRY_TIMEOUT_SECONDS = 30;

export interface TelemetryDeps extends FenceDeps {
  /** A fresh server-generated session document id. */
  newSessionId(): string;
}

export const defaultTelemetryDeps: TelemetryDeps = {
  ...defaultFenceDeps,
  newSessionId: () => `dbg_${randomBytes(16).toString("hex")}`,
};

type RefusalCode =
  | "anonymous_not_allowed"
  | "batch_too_large"
  | "too_many_events"
  | "invalid_batch"
  | "quota_exceeded"
  | "account_deleting"
  | "account_deleted"
  | "send_failed";
type HttpsCode = ConstructorParameters<typeof HttpsError>[0];

const HTTPS_CODE: Record<RefusalCode, HttpsCode> = {
  anonymous_not_allowed: "permission-denied",
  batch_too_large: "invalid-argument",
  too_many_events: "invalid-argument",
  invalid_batch: "invalid-argument",
  quota_exceeded: "resource-exhausted",
  account_deleting: "failed-precondition",
  account_deleted: "unauthenticated",
  send_failed: "internal",
};

function refusal(code: RefusalCode): HttpsError {
  return new HttpsError(HTTPS_CODE[code], code);
}

function log(level: "info" | "warn" | "error", fields: Record<string, string | number | boolean>): void {
  logger[level](DEBUG_TELEMETRY_EVENT, { operation: "sendDebugTelemetry", ...fields });
}

export interface TelemetryResult {
  stored: number;
  serverNowMs: number;
}

function isQuotaRefusal(e: unknown): boolean {
  return (e as { code?: unknown } | null)?.code === "resource-exhausted";
}

/** Whole request pipeline with injectable collaborators (Firestore, Auth, clock, ids). */
export async function handleSendDebugTelemetry(
  deps: TelemetryDeps,
  uid: string,
  signInProvider: string | undefined,
  data: unknown,
): Promise<TelemetryResult> {
  if (signInProvider === "anonymous") throw refusal("anonymous_not_allowed");

  // Input validation first: nothing is charged or stored for an invalid batch.
  const checked = sanitizeTelemetryBatch(data);
  if (!checked.ok) {
    log("warn", { outcome: checked.code });
    throw refusal(checked.code);
  }
  const { events, droppedCount, droppedReported } = checked.batch;

  // Quotas: calls per day, then events per day (cost = events in this batch).
  let callCharged = false;
  let eventsCharged = 0;
  try {
    await enforceDailyQuota(uid, TELEMETRY_CALL_QUOTA_ACTION, QUOTAS.debugTelemetrySend);
    callCharged = true;
    if (events.length > 0) {
      await enforceDailyQuota(uid, TELEMETRY_EVENT_QUOTA_ACTION, QUOTAS.debugTelemetryEvents, events.length);
      eventsCharged = events.length;
    }
  } catch (e) {
    if (callCharged) await refundQuota(uid, TELEMETRY_CALL_QUOTA_ACTION, 1);
    if (isQuotaRefusal(e)) {
      log("warn", { outcome: "quota_exceeded" });
      throw refusal("quota_exceeded");
    }
    log("error", { outcome: "quota_check_failed", errorCode: errorCodeOf(e) });
    throw refusal("send_failed");
  }

  const refund = async (): Promise<void> => {
    await refundQuota(uid, TELEMETRY_CALL_QUOTA_ACTION, 1);
    if (eventsCharged > 0) await refundQuota(uid, TELEMETRY_EVENT_QUOTA_ACTION, eventsCharged);
  };

  try {
    const fs = deps.firestore();
    const ref = fs.doc(`debug_sessions/${deps.newSessionId()}`);
    const fence = await fs.runTransaction(async (tx) => {
      const state = await checkAccountFence(tx, deps, uid);
      if (state !== "clear") return state;
      if (events.length > 0) {
        tx.create(ref, {
          identity: identityFromProvider(signInProvider),
          events,
          uid,
          receivedAt: admin.firestore.Timestamp.fromMillis(deps.nowMs()),
        });
      }
      return state;
    });
    if (fence !== "clear") {
      await refund();
      log("warn", { outcome: fence });
      throw refusal(fence);
    }
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    await refund();
    log("error", { outcome: "send_failed", errorCode: errorCodeOf(e) });
    throw refusal("send_failed");
  }

  if (droppedReported) {
    logger.info(DEBUG_TELEMETRY_DROP_EVENT, { operation: "sendDebugTelemetry", dropped: droppedCount });
  }
  log("info", { outcome: "stored", events: events.length });
  return { stored: events.length, serverNowMs: deps.nowMs() };
}

/** Function options: the shared RARE profile plus the design's bounded timeout. */
export const TELEMETRY_OPTIONS = { ...RARE, timeoutSeconds: TELEMETRY_TIMEOUT_SECONDS };

export const sendDebugTelemetry = onCall(TELEMETRY_OPTIONS, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "sign_in_required");
  noteAppCheck(request, "sendDebugTelemetry");
  return handleSendDebugTelemetry(
    defaultTelemetryDeps,
    request.auth.uid,
    request.auth.token?.firebase?.sign_in_provider,
    request.data,
  );
});
