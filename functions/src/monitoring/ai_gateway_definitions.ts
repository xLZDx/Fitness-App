/**
 * AI Gateway monitoring: log-based metric and investigation-query
 * DEFINITIONS reading `ai_gateway.ts:312`'s structured `ai_gateway: call`
 * event, plus the quota-refusal signals `abuse_guard.ts` emits before a
 * call ever reaches the gateway. Same posture as `alert_definitions.ts`:
 * nothing here is deployed by this codebase, and no threshold-based
 * AlertPolicy is defined -- GPT-PM's binding ruling (2026-08-27) was that
 * an error-rate/latency/token threshold would be invented without a
 * production baseline to justify it, and stays a separate, later decision.
 *
 * Per GPT-PM's DoD: covers request rate, failures, timeout/latency, quota
 * exhaustion pressure, and token/usage pressure -- the five dimensions the
 * G3 AI Gateway scope committed to, all sourced from the one shared event
 * plus the two quota-enforcement log lines (`abuse_guard.ts:103,124`).
 */

import {
  AI_GATEWAY_CALL_EVENT,
  QUOTA_EXCEEDED_EVENT,
  QUOTA_CHECK_FAILED_EVENT,
} from "./log_signals";
import {
  AI_GATEWAY_OPERATIONS,
  AI_GATEWAY_OUTCOMES,
  type AiGatewayOperation,
} from "../ai_gateway";
import type {
  CounterLogMetricSpec,
  DistributionLogMetricSpec,
} from "./types";
import { toCounterLogMetricJson, toDistributionLogMetricJson } from "./types";

/**
 * Re-exported, not re-declared: `AI_GATEWAY_OPERATIONS`/`AI_GATEWAY_OUTCOMES`
 * are `ai_gateway.ts`'s own runtime tuples, the single source of truth
 * `AiGatewayOperation`/`AiGatewayOutcome` are themselves derived from
 * (`typeof AI_GATEWAY_OPERATIONS[number]`). GPT-PM's review of the first
 * version of this module (commit `c7a498e`) found a second, independently
 * declared array here, bounded only by a `satisfies` check that proves
 * every array element is a valid operation but NOT that every operation is
 * IN the array -- a real gap, since a 5th operation added to the union
 * would still compile with this array unchanged, silently excluding it
 * from every metric filter. Importing the producer's own tuple instead of
 * mirroring it closes that structurally: there is now exactly one array,
 * and every consumer (the type, `generate()`'s runtime check, and this
 * module's filters) reads from it.
 */
export { AI_GATEWAY_OPERATIONS, AI_GATEWAY_OUTCOMES };

const OPERATION_LABEL = {
  key: "operation",
  valueType: "STRING" as const,
  description: "Which of the four AI Gateway surfaces made the call.",
  sourceField: "jsonPayload.operation",
};

const OUTCOME_LABEL = {
  key: "outcome",
  valueType: "STRING" as const,
  description: '"success", "timeout", or "error".',
  sourceField: "jsonPayload.outcome",
};

/**
 * 1. Call counter -- request rate / success rate / error rate / timeout
 * rate, all derivable from one `operation` x `outcome` counter without
 * choosing any threshold. Bounded at 4 x 3 = 12 max time series, enforced
 * by the filter itself (see `BoundedLabel` in `types.ts`), not only by
 * this list being the intended set.
 */
export const AI_GATEWAY_CALLS_METRIC: CounterLogMetricSpec = {
  name: "ai_gateway_calls",
  description:
    "Count of AI Gateway calls by operation and outcome. Source for " +
    "request rate, success rate, error rate, and timeout rate -- no " +
    "threshold chosen here.",
  message: AI_GATEWAY_CALL_EVENT,
  boundedLabels: [
    { label: OPERATION_LABEL, allowedValues: [...AI_GATEWAY_OPERATIONS] },
    { label: OUTCOME_LABEL, allowedValues: [...AI_GATEWAY_OUTCOMES] },
  ],
};

/**
 * 2. Latency distribution -- explicit buckets, not generated, so every
 * boundary is a deliberate, documented choice rather than a curve nobody
 * chose on purpose. Concentrated resolution around this codebase's own
 * measured/configured timeouts (20_000ms for equipment recognition and
 * machine description, 25_000ms for exercise generation, 45_000ms for
 * coach advice -- confirmed via grep against each `ai_*.ts` callable's
 * `timeoutMs`), with headroom past the largest (45s) to see genuine
 * network-jitter overshoot before the AbortSignal actually lands.
 */
export const AI_GATEWAY_LATENCY_METRIC: DistributionLogMetricSpec = {
  name: "ai_gateway_latency_ms",
  description:
    "Distribution of AI Gateway call latency (ms) by operation and " +
    "outcome. Bucket boundaries are centered on this codebase's own " +
    "configured per-operation timeouts (20s/25s/45s).",
  message: AI_GATEWAY_CALL_EVENT,
  boundedLabels: [
    { label: OPERATION_LABEL, allowedValues: [...AI_GATEWAY_OPERATIONS] },
    { label: OUTCOME_LABEL, allowedValues: [...AI_GATEWAY_OUTCOMES] },
  ],
  valueField: "jsonPayload.latencyMs",
  bucketOptions: {
    bounds: [
      100, 250, 500, 1000, 2000, 3000, 5000, 8000, 12000, 16000, 20000,
      22000, 25000, 28000, 32000, 36000, 40000, 45000, 50000, 60000, 90000,
    ],
  },
};

/**
 * 3. Token/usage-pressure distribution. Deliberately NOT filtered to
 * `outcome="success"`: `ai_gateway.ts:281` captures `usageMetadata` before
 * the empty-answer check that can still flip the final event to
 * `outcome:"error"` -- a provider call that spent real, billed tokens but
 * returned an unusable response is exactly the usage this metric exists to
 * show, not to hide by filtering it out (verified by reading the actual
 * capture-then-check ordering, not assumed). The `totalTokenCount:*`
 * existence clause means an event with no usage data (a timeout before any
 * response, or a provider that omitted `usageMetadata`) is correctly
 * excluded from this metric rather than counted as zero tokens.
 */
export const AI_GATEWAY_TOKENS_METRIC: DistributionLogMetricSpec = {
  name: "ai_gateway_total_tokens_per_call",
  description:
    "Distribution of total token usage per AI Gateway call (prompt + " +
    "candidates + thoughts), by operation and outcome. Includes " +
    "usage-bearing error/timeout events -- tokens can be spent on a call " +
    "that ultimately fails. Absence of usage data (no field present) " +
    "means unavailable, not zero, and is excluded via the existence check.",
  message: AI_GATEWAY_CALL_EVENT,
  boundedLabels: [
    { label: OPERATION_LABEL, allowedValues: [...AI_GATEWAY_OPERATIONS] },
    { label: OUTCOME_LABEL, allowedValues: [...AI_GATEWAY_OUTCOMES] },
  ],
  valueField: "jsonPayload.totalTokenCount",
  extraFilterClauses: ["jsonPayload.totalTokenCount:*"],
  bucketOptions: {
    // maxOutputTokens across the four callables ranges 256-1024 (grep-
    // confirmed); prompt tokens (including any image input) add headroom
    // on top, so the curve extends well past the largest configured
    // output ceiling rather than stopping at it.
    bounds: [50, 100, 200, 300, 500, 750, 1000, 1500, 2000, 3000, 4000, 6000, 8000, 12000, 20000],
  },
};

/**
 * 4. Quota-exhaustion counter. The gateway event itself cannot see this --
 * `enforceDailyQuota` (`abuse_guard.ts`) refuses BEFORE `generate()` is
 * ever called (verified: every `ai_*.ts` callable's `enforceDailyQuota(...)`
 * call precedes its `generate({...})` call). `action` is renamed to
 * `operation` at the label level so this metric joins cleanly with the
 * call/latency/token metrics above despite reading a different event.
 * Bounded to exactly the four AI actions -- `enforceDailyQuota` is also
 * called for non-AI actions (`accountExport`, `clipUrl`, `clipUrls`,
 * `startFreeTrial`, etc.), which are out of scope for an AI Gateway
 * pressure metric and are excluded by the filter itself, not just by
 * this list's intent.
 */
export const AI_GATEWAY_QUOTA_EXHAUSTIONS_METRIC: CounterLogMetricSpec = {
  name: "ai_gateway_quota_exhaustions",
  description:
    "Count of AI Gateway calls refused for exceeding the daily quota, " +
    "before generate() was ever reached. Bounded to the four AI actions.",
  message: QUOTA_EXCEEDED_EVENT,
  boundedLabels: [
    {
      label: { ...OPERATION_LABEL, sourceField: "jsonPayload.action" },
      allowedValues: [...AI_GATEWAY_OPERATIONS],
    },
  ],
};

export function aiGatewayCallsMetricJson(): object {
  return toCounterLogMetricJson(AI_GATEWAY_CALLS_METRIC);
}

export function aiGatewayLatencyMetricJson(): object {
  return toDistributionLogMetricJson(AI_GATEWAY_LATENCY_METRIC);
}

export function aiGatewayTokensMetricJson(): object {
  return toDistributionLogMetricJson(AI_GATEWAY_TOKENS_METRIC);
}

export function aiGatewayQuotaExhaustionsMetricJson(): object {
  return toCounterLogMetricJson(AI_GATEWAY_QUOTA_EXHAUSTIONS_METRIC);
}

// ---------------------------------------------------------------------
// Source-controlled investigation queries -- plain Cloud Logging filter
// strings for manual use (Log Explorer / `gcloud logging read`), not
// metrics and not alert policies. `resource.type="cloud_run_revision"` is
// included as an external scope guard per GPT-PM's recommendation, even
// though `operation` is already the correct discriminator for this shared
// gateway (all four callables funnel through the same `generate()`).
// ---------------------------------------------------------------------

const RESOURCE_SCOPE = 'resource.type="cloud_run_revision"';

export function queryAllCalls(): string {
  return `${RESOURCE_SCOPE} AND jsonPayload.message="${AI_GATEWAY_CALL_EVENT}"`;
}

export function queryFailures(): string {
  return (
    `${RESOURCE_SCOPE} AND jsonPayload.message="${AI_GATEWAY_CALL_EVENT}" ` +
    `AND (jsonPayload.outcome="error" OR jsonPayload.outcome="timeout")`
  );
}

export function queryTimeoutsFor(operation: AiGatewayOperation): string {
  return (
    `${RESOURCE_SCOPE} AND jsonPayload.message="${AI_GATEWAY_CALL_EVENT}" ` +
    `AND jsonPayload.operation="${operation}" AND jsonPayload.outcome="timeout"`
  );
}

export function queryErrorsFor(operation: AiGatewayOperation): string {
  return (
    `${RESOURCE_SCOPE} AND jsonPayload.message="${AI_GATEWAY_CALL_EVENT}" ` +
    `AND jsonPayload.operation="${operation}" AND jsonPayload.outcome="error"`
  );
}

export function queryUsagePresent(): string {
  return (
    `${RESOURCE_SCOPE} AND jsonPayload.message="${AI_GATEWAY_CALL_EVENT}" ` +
    `AND jsonPayload.totalTokenCount:*`
  );
}

export function queryQuotaExhausted(): string {
  const actionClause = AI_GATEWAY_OPERATIONS.map(
    (op) => `jsonPayload.action="${op}"`,
  ).join(" OR ");
  return (
    `${RESOURCE_SCOPE} AND jsonPayload.message="${QUOTA_EXCEEDED_EVENT}" ` +
    `AND (${actionClause})`
  );
}

export function queryQuotaCheckFailed(): string {
  const actionClause = AI_GATEWAY_OPERATIONS.map(
    (op) => `jsonPayload.action="${op}"`,
  ).join(" OR ");
  return (
    `${RESOURCE_SCOPE} AND jsonPayload.message="${QUOTA_CHECK_FAILED_EVENT}" ` +
    `AND (${actionClause})`
  );
}
