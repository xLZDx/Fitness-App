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
  CANARY_PROBE_FAILED_EVENT,
  ENFORCEMENT_STATE_DEGRADED_OR_FAILED_EVENT,
} from "./log_signals";
import type {
  LogMatchFilterSpec,
  AlertPolicySpec,
  CounterLogMetricSpec,
  MetricAbsenceAlertPolicySpec,
} from "./types";
import {
  toGcpFilterString,
  toAlertPolicyJson,
  toCounterLogMetricJson,
  toMetricAbsenceAlertPolicyJson,
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
/**
 * MVP1.G3 Step 9B. `runProductionCanary` (`canary_schedule.ts`) is a
 * scheduled function, not a callable, but it produces the same Gen2
 * `resource.labels.service_name` shape as every other function here --
 * `toCloudRunServiceName` derives `runproductioncanary`. Confirmed against
 * the real deployment, 2026-08-27: `gcloud run services list` returns
 * exactly `runproductioncanary` for this function -- the same live check
 * the other three names in this file already received.
 */
const CANARY_PROBE_FUNCTION_NAME = "runProductionCanary";
/**
 * MVP1.G3 Step 10A. `runEnforcementStateCheck` (`enforcement_state_schedule.ts`)
 * is a scheduled function, same Gen2 shape as the canary above --
 * `toCloudRunServiceName` derives `runenforcementstatecheck`. Not yet
 * confirmed against a live deployment (unlike the canary's name above,
 * which was); to be verified via `gcloud run services list` once this
 * function is actually deployed, same check the other four names received.
 */
const ENFORCEMENT_STATE_CHECK_FUNCTION_NAME = "runEnforcementStateCheck";

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

/**
 * `runProductionCanary`'s own thrown failure (`canary_schedule.ts`) logs
 * this exact message before throwing, so a canary failure is caught the
 * same way any other operational failure in this file is: by matching the
 * structured log line, not by inferring failure from a missing success
 * signal. GPT-PM's Step 9B GO required this as a 4th policy, distinct from
 * the three business-failure alerts: it alerts on the MONITOR itself
 * failing, not just on a business outcome.
 *
 * SCOPE, stated precisely after GPT-PM's round-2 review corrected an
 * overclaim in this comment's own earlier wording ("going quiet or
 * erroring"): this policy fires only when `runProductionCanary` actually
 * EXECUTES and either its probe reports failure or its handler's own
 * SCHEDULE_HANDLER backstop catches an unexpected rejection
 * (`canary_schedule.ts`). It CANNOT detect the Scheduler job itself being
 * disabled/deleted, a Scheduler-to-Cloud-Run auth/delivery failure, or any
 * other case where the function never runs at all -- no structured log
 * exists to match if the function never executes. Genuine Scheduler-
 * execution-health monitoring (e.g. Cloud Scheduler's own AttemptFinished
 * failure signal) is a materially different, larger scope than this Step
 * 9B GO asked for and is not built here -- a known, stated gap, not a
 * silently assumed one.
 *
 * Deliberately does NOT include `PLATFORM_UNHANDLED_ERROR`, unlike the three
 * business-failure filters above. GPT-PM's review of the first version
 * (`b9d1e9a`) found that message is specific to the onCall platform wrapper
 * (`https.js`) -- `runProductionCanary` is an `onSchedule` function, whose
 * own wrapper (`firebase-functions/lib/v2/providers/scheduler.js:71-73`)
 * catches an unexpected rejection with `logger.error(err.message)`, never
 * the literal string `"Unhandled error"`. Confirmed by reading that source
 * directly. The equivalent backstop for THIS function is
 * `canary_schedule.ts`'s own try/catch around `runCanaryProbe()`, which
 * emits `CANARY_PROBE_FAILED_EVENT` itself on an unexpected rejection --
 * that path is already covered by this filter's one message.
 */
export const CANARY_PROBE_FAILURE_FILTER: LogMatchFilterSpec = {
  exportName: CANARY_PROBE_FUNCTION_NAME,
  messageEquals: [CANARY_PROBE_FAILED_EVENT],
};

/**
 * MVP1.G3 Step 10A. `enforcement_state_schedule.ts` logs this exact message
 * whenever its own check finds any section it could not read (DEGRADED) or
 * could read none of (FAILED) -- never on a clean read, same silence-is-OK
 * convention as every filter above. No `PLATFORM_UNHANDLED_ERROR` backstop
 * needed here for the same documented reason as the canary: `onSchedule`'s
 * wrapper never logs that literal, and this function's own top-level
 * try/catch already logs this exact event on any uncaught rejection too.
 */
export const ENFORCEMENT_STATE_FAILURE_FILTER: LogMatchFilterSpec = {
  exportName: ENFORCEMENT_STATE_CHECK_FUNCTION_NAME,
  messageEquals: [ENFORCEMENT_STATE_DEGRADED_OR_FAILED_EVENT],
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

export function canaryProbeAlertFilterString(): string {
  return toGcpFilterString(CANARY_PROBE_FAILURE_FILTER);
}

export function enforcementStateAlertFilterString(): string {
  return toGcpFilterString(ENFORCEMENT_STATE_FAILURE_FILTER);
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

/**
 * The 4th policy GPT-PM's Step 9B GO required, on top of the three
 * business-failure ones above: a permanent alert on the canary MONITOR
 * itself failing or erroring -- so a broken canary reads as an incident
 * rather than silently stops proving anything.
 */
export const CANARY_PROBE_ALERT_POLICY: AlertPolicySpec = {
  displayName: "Production canary probe failure",
  conditionDisplayName: "Any canary probe failure or unhandled error in runProductionCanary",
  filter: CANARY_PROBE_FAILURE_FILTER,
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

export function canaryProbeAlertPolicyJson(): object {
  return toAlertPolicyJson(CANARY_PROBE_ALERT_POLICY);
}

/**
 * MVP1.G3 Step 10A. Permanent alert on the enforcement-state check itself
 * being unable to read (part of, or all of) live production state -- so a
 * degraded/failed visibility mechanism reads as an incident rather than
 * silently stops proving anything, same rationale GPT-PM required for the
 * canary's own 4th policy.
 */
export const ENFORCEMENT_STATE_ALERT_POLICY: AlertPolicySpec = {
  displayName: "Enforcement-state check degraded or failed",
  conditionDisplayName:
    "Any degraded or failed section in runEnforcementStateCheck",
  filter: ENFORCEMENT_STATE_FAILURE_FILTER,
  notificationRateLimitPeriod: NOTIFICATION_RATE_LIMIT_PERIOD,
  autoClose: AUTO_CLOSE,
};

export function enforcementStateAlertPolicyJson(): object {
  return toAlertPolicyJson(ENFORCEMENT_STATE_ALERT_POLICY);
}

/**
 * MVP1.G3 Step 10A remediation (GPT-PM's 2nd finding: "an independent
 * freshness/absence mechanism able to detect missed execution without
 * relying on this function's own custom log"). The Scheduler job ID follows
 * Firebase's documented `onSchedule` naming convention,
 * `firebase-schedule-<functionName>-<region>` -- NOT YET independently
 * confirmed against a live deployment (this function has not been deployed
 * yet), unlike every Cloud Run service name in this file, which was.
 * Verify via `gcloud scheduler jobs list` once deployed, same live-check
 * discipline every other identity in this file received.
 *
 * `absentFor: "86400s"` (24h) against a 6-hour schedule tolerates up to 3
 * consecutive missed runs (transient Scheduler retry/backoff, a redeploy
 * window) before firing -- deliberately looser than a hair-trigger on one
 * missed cycle, matching this check's own "config/rules state moves slowly"
 * cadence reasoning in `enforcement_state_schedule.ts`.
 */
const ENFORCEMENT_STATE_SCHEDULER_JOB_ID =
  "firebase-schedule-runEnforcementStateCheck-europe-west1";

export const ENFORCEMENT_STATE_STALENESS_POLICY: MetricAbsenceAlertPolicySpec = {
  displayName: "Enforcement-state check: Scheduler job stopped executing",
  conditionDisplayName:
    "cloudscheduler.googleapis.com/job/execution_count absent for 24h",
  filter:
    `metric.type="cloudscheduler.googleapis.com/job/execution_count" ` +
    `AND resource.type="cloud_scheduler_job" ` +
    `AND resource.label.job_id="${ENFORCEMENT_STATE_SCHEDULER_JOB_ID}"`,
  absentFor: "86400s",
  alignmentPeriodSeconds: 3600,
  notificationRateLimitPeriod: NOTIFICATION_RATE_LIMIT_PERIOD,
  autoClose: AUTO_CLOSE,
};

export function enforcementStateStalenessPolicyJson(): object {
  return toMetricAbsenceAlertPolicyJson(ENFORCEMENT_STATE_STALENESS_POLICY);
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
