/**
 * Source-controlled monitor DEFINITIONS for MVP1.G3 Step 9 groundwork.
 *
 * None of these is deployed by this codebase: there is no `terraform apply`,
 * `gcloud alpha monitoring policies create`, or admin-SDK call anywhere that
 * reads from this file. It exists so a definition can be reviewed, tested
 * against fixtures, and diffed in a PR before anyone creates the matching
 * live GCP resource by hand -- which stays a separate, deliberate step,
 * gated the way `README.md` in this directory records:
 *
 *  - the two alert-policy definitions (Stripe reconciliation, delete/export
 *    operational failure) are READY_TO_ACTIVATE: creating the live
 *    `notificationChannels: []`-only policy costs nothing extra once
 *    DECISION FA-D1 names who owns it, per GPT-PM's ruling of 2026-08-27;
 *  - the App Check log-based METRIC definition is READY_TO_ACTIVATE for the
 *    definition itself, but creating the live GCP metric resource is HELD
 *    until a real (not estimated) incremental-cost figure is available --
 *    see README.md's cost model section for why this session cannot supply
 *    that figure itself.
 */

import {
  STRIPE_RECONCILE_CANCEL_FAILED,
  STRIPE_RECONCILE_FAILED,
  DELETE_ACCOUNT_STRIPE_CANCEL_FAILED,
  DELETE_ACCOUNT_FIRESTORE_DELETE_FAILED,
  DELETE_ACCOUNT_AUTH_DELETE_FAILED,
  EXPORT_ACCOUNT_FAILED,
  PLATFORM_UNHANDLED_ERROR,
  APP_CHECK_EVENT,
} from "./log_signals";
import type { LogMatchFilterSpec, LogBasedMetricSpec } from "./types";
import { toGcpFilterString } from "./types";

/**
 * Deployed Cloud Run/Functions service name for the Stripe webhook handler.
 * `reconcileDuplicateSubscriptions` (index.ts:1862) is a plain function
 * called from inside `stripeWebhook` (index.ts:1019, an `onRequest`
 * export) -- it has no function identity of its own in Cloud Logging, so
 * the filter scopes on the enclosing exported function.
 */
const STRIPE_WEBHOOK_FUNCTION_NAME = "stripeWebhook";
const DELETE_ACCOUNT_FUNCTION_NAME = "deleteAccount";
const EXPORT_ACCOUNT_FUNCTION_NAME = "exportAccountData";

/**
 * Every duplicate-subscription reconciliation failure inside the Stripe
 * webhook. Deliberately excludes the two non-failure log lines emitted by
 * the same code path (`duplicate subscriptions found` is a WARNING that a
 * duplicate exists, not that reconciliation failed; `cancelled duplicate
 * subscription` is the success case) -- reconciliation swallows its own
 * errors so the webhook can return 2xx (see index.ts:1857-1861), which is
 * exactly why this log line is the only remaining signal of the failure.
 */
export const STRIPE_RECONCILIATION_FAILURE_FILTER: LogMatchFilterSpec = {
  functionName: STRIPE_WEBHOOK_FUNCTION_NAME,
  messageEquals: [STRIPE_RECONCILE_CANCEL_FAILED, STRIPE_RECONCILE_FAILED],
};

/**
 * `deleteAccount`'s three explicitly named failure paths, plus the
 * platform-level backstop for anything outside them (proven to exist and
 * to actually cover this function in README.md's failure-path audit --
 * notably the pre-try-block Firestore read at index.ts:2086, which no
 * explicit catch names).
 */
export const DELETE_ACCOUNT_FAILURE_FILTER: LogMatchFilterSpec = {
  functionName: DELETE_ACCOUNT_FUNCTION_NAME,
  messageEquals: [
    DELETE_ACCOUNT_STRIPE_CANCEL_FAILED,
    DELETE_ACCOUNT_FIRESTORE_DELETE_FAILED,
    DELETE_ACCOUNT_AUTH_DELETE_FAILED,
    PLATFORM_UNHANDLED_ERROR,
  ],
};

/** Same shape as delete, for the export path's one explicit failure log. */
export const EXPORT_ACCOUNT_FAILURE_FILTER: LogMatchFilterSpec = {
  functionName: EXPORT_ACCOUNT_FUNCTION_NAME,
  messageEquals: [EXPORT_ACCOUNT_FAILED, PLATFORM_UNHANDLED_ERROR],
};

export function stripeReconciliationAlertFilterString(): string {
  return toGcpFilterString(STRIPE_RECONCILIATION_FAILURE_FILTER);
}

export function deleteAccountAlertFilterString(): string {
  return toGcpFilterString(DELETE_ACCOUNT_FAILURE_FILTER);
}

export function exportAccountAlertFilterString(): string {
  return toGcpFilterString(EXPORT_ACCOUNT_FAILURE_FILTER);
}

/**
 * Log-based metric for App Check attestation ratio. Labels are bounded by
 * construction: `fn` ranges over the ~13 known call sites of `noteAppCheck`
 * (a fixed, small set of function names, not a user-supplied value) and
 * `attested` is a boolean -- so cardinality is bounded at roughly
 * (call sites) x 2, never grows with traffic or user count. No uid or other
 * per-user field is a label, matching `noteAppCheck`'s own privacy design
 * (abuse_guard.ts:49-51).
 */
export const APP_CHECK_ATTESTED_RATIO_METRIC: LogBasedMetricSpec = {
  name: "appcheck_attestation",
  description:
    "Count of callable invocations by function and whether the call " +
    "carried a verified App Check token. attested-ratio = " +
    "sum(attested=true) / sum(all), grouped by fn.",
  filter: `jsonPayload.message="${APP_CHECK_EVENT}"`,
  labelKeys: ["fn", "attested"],
};
