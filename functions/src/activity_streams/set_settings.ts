/**
 * `setActivityCloudSettings` -- server-side consent and retention setting for
 * cloud activity streams (S02 design 5.3, 5.4, 6.1, 9, 9.1).
 *
 * Order (part of the contract, mirrors `createBodyScan`): auth -> App Check note
 * -> non-anonymous -> validate -> feature flag (only when granting) -> quota
 * (not charged for a pure withdrawal) -> ONE transaction that reads the delete
 * fence, the retries marker and the settings, checks that the Auth user still
 * exists, then writes retention, generation, recompute flag and consent
 * together.
 *
 * Seams: `applyActivityCloudSettings` takes injectable Firestore, Auth
 * existence and clock, so tests drive it without the Functions runtime.
 *
 * Consent withdrawal (design 9.1, as far as this story owns it): records
 * `cloudStreams.withdrawnAt` and increments `settingsGeneration`. The refusal
 * of later uploads (`consent_withdrawn`) is done by the upload and commit
 * callables of S02-04b through `cloudStreamsConsentState`. The optional bulk
 * "delete my cloud streams" job runs in the seventh callable of S02-06b; this
 * callable STARTS it when the request carries `cloudStreams.deleteExisting: true`
 * with a withdrawal (job fields `streamDeleteJobId`, `streamDeletePending`,
 * `streamDeleteCursor`, written in the same transaction; a running job is kept).
 * The reconciler abort of `pending` rows belongs to S02-06a/b.
 *
 * Logging (GPS-PRIV-094): closed outcome slugs and counts only, never a uid.
 */
import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { RARE } from "../scaling";
import { QUOTAS, enforceDailyQuota, noteAppCheck, refundQuota } from "../abuse_guard";
import { assertFeatureEnabled } from "../feature_flags";
import { activityStreamCloudEnabled } from "./flags";
import { checkAccountFence, defaultFenceDeps, type FenceDeps } from "./fence";
import { defaultDeleteAllDeps, hasActiveDeleteJob } from "./delete_all_streams";
import {
  CLOUD_STREAMS_CONSENT_VERSION,
  SettingsRequestError,
  activitySettingsPath,
  isWithdrawalOnly,
  parseSettingsRequest,
  planSettingsChange,
  type CloudStreamsConsentState,
  type SettingsRequest,
  type StreamRetentionDays,
} from "./settings";

/** The quota action of this callable (design 5.4); also listed in `REDACTED_QUOTA_ACTIONS`. */
export const SETTINGS_QUOTA_ACTION = "activitySettingsSet";

/** The one structured-log message of this callable. */
export const ACTIVITY_SETTINGS_EVENT = "activity_settings_event";

/** Closed refusal codes returned to the client as the HttpsError message. */
export type SettingsRefusalCode =
  | "invalid_request"
  | "invalid_retention"
  | "invalid_consent"
  | "account_deleting"
  | "account_deleted"
  | "quota_exceeded"
  | "settings_failed";

type HttpsCode = ConstructorParameters<typeof HttpsError>[0];

const HTTPS_CODE: Record<SettingsRefusalCode, HttpsCode> = {
  invalid_request: "invalid-argument",
  invalid_retention: "invalid-argument",
  invalid_consent: "invalid-argument",
  account_deleting: "failed-precondition",
  account_deleted: "unauthenticated",
  quota_exceeded: "resource-exhausted",
  settings_failed: "internal",
};

/** A refusal with a bare code; the code is the only thing the client ever sees. */
export class SettingsRefusal extends Error {
  constructor(readonly code: SettingsRefusalCode) {
    super(code);
    this.name = "SettingsRefusal";
  }
}

/** What the callable returns. `changed: false` means the request equalled the stored state. */
export interface SettingsResult {
  changed: boolean;
  settingsGeneration: number;
  streamRetentionDays: StreamRetentionDays;
  consent: CloudStreamsConsentState;
  recomputePending: boolean;
  /** `true` when this call started the bulk stream-delete job (design 9.1); the client then calls `deleteAllActivityStreams` until `done`. */
  streamDeleteStarted: boolean;
  serverNowMs: number;
}

/** Injectable collaborators of the transaction (the shared fence seam, `fence.ts`, plus an optional job-id source). */
export type SettingsDeps = FenceDeps & { newJobId?(): string };

export const defaultSettingsDeps: SettingsDeps = defaultFenceDeps;

/**
 * The transaction. Reads (settings, both fence documents), then the Auth
 * existence check, then at most one write. Throws `SettingsRefusal` for a
 * fence or deleted-account refusal; any other failure propagates to the caller.
 */
export async function applyActivityCloudSettings(
  deps: SettingsDeps,
  uid: string,
  req: SettingsRequest,
): Promise<SettingsResult> {
  const fs = deps.firestore();
  const settingsRef = fs.doc(activitySettingsPath(uid));

  return fs.runTransaction(async (tx): Promise<SettingsResult> => {
    const settingsSnap = await tx.get(settingsRef);
    // Fence first (design 6.1): an account being deleted may not gain a consent document.
    // Tokens stay valid for about an hour after `deleteUser`; Auth existence is the second guard.
    const fence = await checkAccountFence(tx, deps, uid);
    if (fence !== "clear") throw new SettingsRefusal(fence);

    const nowMs = deps.nowMs();
    const current = settingsSnap.exists ? (settingsSnap.data() as Record<string, unknown>) : undefined;
    const plan = planSettingsChange(current, req, nowMs);

    // Design 9.1: the withdrawal starts the bulk stream-delete job when the user took the
    // offer. A running job is never replaced; the job fields are the ones
    // `deleteAllActivityStreams` reads (job id, pending flag, cursor).
    const startJob = plan.startStreamDelete && !hasActiveDeleteJob(current);
    if (startJob) {
      tx.set(
        settingsRef,
        {
          streamDeleteJobId: (deps.newJobId ?? defaultDeleteAllDeps.newJobId)(),
          streamDeletePending: true,
          streamDeleteCursor: admin.firestore.FieldValue.delete(),
        },
        { merge: true },
      );
    }

    if (plan.changed) {
      const ts = (ms: number) => admin.firestore.Timestamp.fromMillis(ms);
      const patch: Record<string, unknown> = {
        settingsGeneration: plan.settingsGeneration,
        updatedAt: ts(nowMs),
      };
      if (plan.retentionChanged) {
        patch.streamRetentionDays = plan.streamRetentionDays;
        // The purge continuation recomputes the expiry hints (design 5.3).
        patch.recomputePending = true;
        patch.recomputeCursor = null;
      }
      if (plan.grantedAtMs !== undefined) {
        patch.cloudStreams = {
          version: CLOUD_STREAMS_CONSENT_VERSION,
          acceptedAt: ts(plan.grantedAtMs),
          withdrawnAt: admin.firestore.FieldValue.delete(),
        };
      } else if (plan.withdrawnAtMs !== undefined) {
        patch.cloudStreams = { withdrawnAt: ts(plan.withdrawnAtMs) };
      }
      tx.set(settingsRef, patch, { merge: true });
    }

    return {
      changed: plan.changed,
      settingsGeneration: plan.settingsGeneration,
      streamRetentionDays: plan.streamRetentionDays,
      consent: plan.consent,
      recomputePending: plan.recomputePending,
      streamDeleteStarted: startJob,
      serverNowMs: nowMs,
    };
  });
}

function toHttpsError(code: SettingsRefusalCode): HttpsError {
  return new HttpsError(HTTPS_CODE[code], code);
}

function log(level: "info" | "warn" | "error", fields: Record<string, string | number | boolean>): void {
  logger[level](ACTIVITY_SETTINGS_EVENT, { operation: "setActivityCloudSettings", ...fields });
}

/** A bare error code from a thrown value; never the message (it can embed a document path and so the uid). */
function errorCodeOf(e: unknown): string {
  const code = (e as { code?: unknown } | null | undefined)?.code;
  const text = typeof code === "string" || typeof code === "number" ? String(code) : "";
  return /^[A-Za-z0-9_./-]{1,64}$/.test(text) ? text : "unknown";
}

/**
 * Whole request pipeline with injectable collaborators (testable without the
 * Functions runtime). `signInProvider` is `request.auth.token.firebase.sign_in_provider`.
 */
export async function handleSetActivityCloudSettings(
  deps: SettingsDeps,
  uid: string,
  signInProvider: string | undefined,
  data: unknown,
): Promise<SettingsResult> {
  const started = deps.nowMs();
  // Ordinary users only: an anonymous uid costs nothing to mint, so it may not record GPS consent.
  if (signInProvider === "anonymous") {
    throw new HttpsError("permission-denied", "anonymous_not_allowed");
  }
  let req: SettingsRequest;
  try {
    req = parseSettingsRequest(data);
  } catch (e) {
    if (e instanceof SettingsRequestError) throw toHttpsError(e.code);
    throw toHttpsError("invalid_request");
  }
  // Only granting needs the feature: withdrawal and retention must always work.
  if (req.cloudStreamsGranted === true) assertFeatureEnabled(activityStreamCloudEnabled());

  const charged = !isWithdrawalOnly(req);
  if (charged) {
    try {
      await enforceDailyQuota(uid, SETTINGS_QUOTA_ACTION, QUOTAS.activitySettingsSet);
    } catch (e) {
      if ((e as { code?: unknown } | null)?.code === "resource-exhausted") {
        log("warn", { outcome: "quota_exceeded" });
        throw toHttpsError("quota_exceeded");
      }
      log("error", { outcome: "quota_check_failed", errorCode: errorCodeOf(e) });
      throw toHttpsError("settings_failed");
    }
  }

  try {
    const result = await applyActivityCloudSettings(deps, uid, req);
    log("info", {
      outcome: result.changed ? "changed" : "unchanged",
      withdrew: req.cloudStreamsGranted === false && result.changed,
      latencyMs: deps.nowMs() - started,
    });
    return result;
  } catch (e) {
    // Nothing was written: give the charge back.
    if (charged) await refundQuota(uid, SETTINGS_QUOTA_ACTION, 1);
    if (e instanceof SettingsRefusal) {
      log("warn", { outcome: e.code });
      throw toHttpsError(e.code);
    }
    log("error", { outcome: "settings_failed", errorCode: errorCodeOf(e) });
    throw toHttpsError("settings_failed");
  }
}

export const setActivityCloudSettings = onCall(RARE, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "sign_in_required");
  noteAppCheck(request, "setActivityCloudSettings");
  return handleSetActivityCloudSettings(
    defaultSettingsDeps,
    request.auth.uid,
    request.auth.token?.firebase?.sign_in_provider,
    request.data,
  );
});
