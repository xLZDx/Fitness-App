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
import type {
  LogMatchFilterSpec,
  AlertPolicySpec,
  CounterLogMetricSpec,
} from "./types";
import {
  toGcpFilterString,
  toAlertPolicyJson,
  toCounterLogMetricJson,
} from "./types";

/**
 * TypeScript export names of the enclosing deployed Cloud Functions.
 * `toCloudRunServiceName` (types.ts) derives the actual Gen2 Cloud Run
 * service name from these at render/match time -- kept as the source
 * export name here, not the derived name, so a function rename in index.ts
 * changes both the filter and its tests together.
 *
 * `reconcileDuplicateSubscriptions` (index.ts:1862) is a plain function
 * called from inside `stripeWebhook` (index.ts:1019, an `onRequest`
 * export) -- it has no function identity of its own in Cloud Logging, so
 * the filter scopes on the enclosing exported function.
 */
const STRIPE_WEBHOOK_FUNCTION_NAME = "stripeWebhook";
const DELETE_ACCOUNT_FUNCTION_NAME = "deleteAccount";
const EXPORT_ACCOUNT_FUNCTION_NAME = "exportAccountData";

/** Standard rate limit/auto-close for every log-match policy defined here. */
const NOTIFICATION_RATE_LIMIT_PERIOD = "300s"; // 5 min: avoid renotifying on every raw log line
const AUTO_CLOSE = "604800s"; // 7 days: Google Cloud Monitoring's own default

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
  exportName: STRIPE_WEBHOOK_FUNCTION_NAME,
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
  exportName: DELETE_ACCOUNT_FUNCTION_NAME,
  messageEquals: [
    DELETE_ACCOUNT_STRIPE_CANCEL_FAILED,
    DELETE_ACCOUNT_FIRESTORE_DELETE_FAILED,
    DELETE_ACCOUNT_AUTH_DELETE_FAILED,
    PLATFORM_UNHANDLED_ERROR,
  ],
};

/** Same shape as delete, for the export path's one explicit failure log. */
export const EXPORT_ACCOUNT_FAILURE_FILTER: LogMatchFilterSpec = {
  exportName: EXPORT_ACCOUNT_FUNCTION_NAME,
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
 * The full, deployable-shaped `AlertPolicy` JSON for each log-match monitor
 * -- not just a filter string (see `types.ts`'s `AlertPolicySpec` doc for
 * why a filter alone was insufficient per GPT-PM's review). Each has
 * `notificationChannels: []`: safe by construction even if applied today,
 * since a policy with no channels notifies nobody. Attaching a channel is
 * the deliberate, separate step gated on `DECISION FA-D1`.
 */
export const STRIPE_RECONCILIATION_ALERT_POLICY: AlertPolicySpec = {
  displayName: "Stripe duplicate-subscription reconciliation failure",
  conditionDisplayName: "Any reconciliation failure log in stripeWebhook",
  filter: STRIPE_RECONCILIATION_FAILURE_FILTER,
  notificationRateLimitPeriod: NOTIFICATION_RATE_LIMIT_PERIOD,
  autoClose: AUTO_CLOSE,
};

export const DELETE_ACCOUNT_ALERT_POLICY: AlertPolicySpec = {
  displayName: "deleteAccount operational failure",
  conditionDisplayName:
    "Any named failure or unhandled error in deleteAccount",
  filter: DELETE_ACCOUNT_FAILURE_FILTER,
  notificationRateLimitPeriod: NOTIFICATION_RATE_LIMIT_PERIOD,
  autoClose: AUTO_CLOSE,
};

export const EXPORT_ACCOUNT_ALERT_POLICY: AlertPolicySpec = {
  displayName: "exportAccountData operational failure",
  conditionDisplayName:
    "Any named failure or unhandled error in exportAccountData",
  filter: EXPORT_ACCOUNT_FAILURE_FILTER,
  notificationRateLimitPeriod: NOTIFICATION_RATE_LIMIT_PERIOD,
  autoClose: AUTO_CLOSE,
};

export function stripeReconciliationAlertPolicyJson(): object {
  return toAlertPolicyJson(STRIPE_RECONCILIATION_ALERT_POLICY);
}

export function deleteAccountAlertPolicyJson(): object {
  return toAlertPolicyJson(DELETE_ACCOUNT_ALERT_POLICY);
}

export function exportAccountAlertPolicyJson(): object {
  return toAlertPolicyJson(EXPORT_ACCOUNT_ALERT_POLICY);
}

/**
 * Log-based metric for App Check attestation ratio. Grep-verified 17 call
 * sites of `noteAppCheck` (`index.ts` x10, `video_urls.ts` x2,
 * `account_export.ts` x1, the 4 `ai_*.ts` callables x1 each), each passing
 * a compile-time string literal -- never user-supplied -- so `fn`'s real
 * cardinality only grows via a deliberate code change, not per-request or
 * per-user traffic. `attested` is a genuine boolean (`request.app !==
 * undefined`), rendered unquoted by `boundedLabelFilterClause`'s BOOL case
 * -- Cloud Logging converts the filter's right-hand value to the field's
 * own type before comparing, so an unquoted `true`/`false` is simply the
 * type-correct form for a boolean field, not a fix for a proven mismatch.
 * No uid or other per-user field is a label, matching `noteAppCheck`'s own
 * privacy design (abuse_guard.ts:49-51).
 *
 * UNLIKE `AI_GATEWAY_OPERATIONS` (a closed TypeScript union derived from
 * one runtime tuple, so the type system itself keeps the bounding list
 * exhaustive): `noteAppCheck`'s `fn` parameter is a plain `string`, not a
 * union -- there is no compile-time source of truth to derive this list
 * from. `APP_CHECK_KNOWN_CALLABLES` below is a maintained list, the same
 * class of risk GPT-PM's review flagged for the AI Gateway operation list
 * before that fix. Closed the same way that fix was preferred: not by a
 * comment, but by `__tests__/app_check_metric_parity.test.ts`, which
 * mechanically compares this list against `discoverOnCallExports()` (the
 * SAME real-source-scanning inventory `__tests__/scaling.test.ts`'s
 * "every callable reports its attestation" test already uses) as exact
 * sets in both directions -- a callable missing from this list, or a
 * stale entry with no matching callable, both fail that test. A new
 * callable is therefore caught at test time, not left to page nobody in
 * production because its logs were silently excluded from the metric.
 */
export const APP_CHECK_KNOWN_CALLABLES = [
  "aiCoachAdvice",
  "aiEquipmentRecognition",
  "aiExerciseGeneration",
  "aiMachineDescription",
  "bookCoachSession",
  "clipUrl",
  "clipUrls",
  "createCheckoutSession",
  "createPortalSession",
  "deleteAccount",
  "exportAccountData",
  "generateAnnualReceipt",
  "optInDonorWall",
  "optOutDonorWall",
  "reportEquipment",
  "startCoachOnboarding",
  "startFreeTrial",
] as const;

export const APP_CHECK_ATTESTED_RATIO_METRIC: CounterLogMetricSpec = {
  name: "appcheck_attestation",
  description:
    "Count of callable invocations by function and whether the call " +
    "carried a verified App Check token. attested-ratio = " +
    "sum(attested=true) / sum(all), grouped by fn.",
  message: APP_CHECK_EVENT,
  boundedLabels: [
    {
      label: {
        key: "fn",
        valueType: "STRING",
        description: "Which callable this attestation measurement is for.",
        sourceField: "jsonPayload.fn",
      },
      allowedValues: [...APP_CHECK_KNOWN_CALLABLES],
    },
    {
      label: {
        key: "attested",
        valueType: "BOOL",
        description: "Whether the call carried a verified App Check token.",
        sourceField: "jsonPayload.attested",
      },
      allowedValues: ["true", "false"],
    },
  ],
};

export function appCheckAttestedRatioMetricJson(): object {
  return toCounterLogMetricJson(APP_CHECK_ATTESTED_RATIO_METRIC);
}
