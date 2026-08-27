/**
 * A structured representation of a Cloud Logging filter, restricted to the
 * exact grammar this codebase's definitions need: an AND of resource-scope
 * clauses plus an OR of exact-message clauses. Deliberately not a free-form
 * filter string -- the same spec both renders to the real Cloud Logging
 * query syntax (`toGcpFilterString`) AND is directly evaluable against a
 * sample log entry in a test (`matches`), so a definition's tests exercise
 * the actual matching semantics instead of independently re-typing them.
 *
 * Only equality and OR-of-equality are supported because every definition
 * in `alert_definitions.ts` only needs that; extending the grammar for a
 * future definition should extend this type deliberately, not by having a
 * caller reach past it into a raw string.
 *
 * ## Resource shape: Gen2 (Cloud Run), not Gen1
 *
 * GPT-PM's review of commit 41cb872 (2026-08-27) found the first version of
 * this module used `resource.labels.function_name` -- the Gen1 Cloud
 * Functions shape. Every function in this project is deployed via
 * `firebase-functions/v2` (Gen2), which runs on Cloud Run: its log entries
 * carry `resource.type="cloud_run_revision"` and
 * `resource.labels.service_name`, not `function_name`. A Gen1-shaped filter
 * would match zero real log entries -- a monitor that is silently green
 * during an actual failure, exactly the failure mode this groundwork exists
 * to prevent. Confirmed via Google Cloud's own docs and community reports,
 * not assumed (see `README.md`'s "Resource shape" section for sources).
 */
export interface LogEntryFixture {
  /** The deployed Cloud Run service name, as it appears in a real log entry. */
  serviceName: string;
  message: string;
  severity: "DEFAULT" | "INFO" | "WARNING" | "ERROR";
}

export interface LogMatchFilterSpec {
  /**
   * The TypeScript export name of the Cloud Function (e.g. `"deleteAccount"`),
   * NOT the Cloud Run service name -- `toCloudRunServiceName` derives the
   * latter from this, so a function rename here changes both the filter and
   * its tests together instead of leaving a stale service name behind.
   */
  exportName: string;
  /** Matches if the log entry's message equals ANY of these, exactly. */
  messageEquals: string[];
}

/**
 * firebase-tools' documented Gen2 deploy-time transform: underscores become
 * hyphens, uppercase becomes lowercase (Cloud Run service names are RFC1035
 * labels and cannot contain either). E.g. `deleteAccount` -> `deleteaccount`,
 * `some_fn` -> `some-fn`. Sourced from firebase-tools' own release notes and
 * issue tracker (see README.md) -- NOT independently verified against this
 * project's live deployment, since this session has no `gcloud`/Cloud
 * Logging access to confirm the actual deployed service names. Treat a
 * definition built from this function as `READY_TO_ACTIVATE` pending that
 * live confirmation, not as already proven correct in production.
 */
export function toCloudRunServiceName(exportName: string): string {
  return exportName.replace(/_/g, "-").toLowerCase();
}

export function toGcpFilterString(spec: LogMatchFilterSpec): string {
  const serviceName = toCloudRunServiceName(spec.exportName);
  const messageClause = spec.messageEquals
    .map((m) => `jsonPayload.message="${m}"`)
    .join(" OR ");
  return (
    `resource.type="cloud_run_revision" ` +
    `AND resource.labels.service_name="${serviceName}" ` +
    `AND (${messageClause})`
  );
}

export function matchesLogMatchFilter(
  spec: LogMatchFilterSpec,
  entry: LogEntryFixture,
): boolean {
  return (
    entry.serviceName === toCloudRunServiceName(spec.exportName) &&
    spec.messageEquals.includes(entry.message)
  );
}

/** One label on a real `google.logging.v2.LogMetric`. */
export interface LogMetricLabel {
  key: string;
  valueType: "STRING" | "BOOL" | "INT64";
  description: string;
  /** The `jsonPayload` field this label is extracted from, e.g. `"jsonPayload.operation"`. */
  sourceField: string;
}

export interface BoundedLabel {
  label: LogMetricLabel;
  /**
   * The exact allowed values for this label. ANDed into the metric's
   * `filter` as an OR-of-equality clause -- so cardinality is capped by
   * the filter itself, not only by an out-of-band comment listing known
   * values. An unexpected value (a typo, a future 5th operation added
   * without updating this list) is simply excluded from the metric rather
   * than silently creating a new, unbounded time series.
   */
  allowedValues: string[];
}

/**
 * Explicit histogram buckets only. `linearBuckets`/`exponentialBuckets`
 * exist on the real API but are not needed here -- every distribution this
 * codebase defines has a small, known set of meaningful thresholds (e.g.
 * this project's own AI Gateway timeout values) that read more clearly as
 * an explicit list than as a generated curve. See each spec's `bounds` for
 * the reasoning behind its specific values.
 */
export interface BucketOptionsSpec {
  bounds: number[];
}

function boundedLabelFilterClause(bl: BoundedLabel): string {
  // BOOL fields render as unquoted literals (`field=true`), not strings
  // (`field="true"`) -- Cloud Logging's filter grammar treats these
  // differently, and a quoted boolean would never match a real log entry.
  const renderValue = (v: string) =>
    bl.label.valueType === "BOOL" ? v : `"${v}"`;
  return (
    "(" +
    bl.allowedValues
      .map((v) => `${bl.label.sourceField}=${renderValue(v)}`)
      .join(" OR ") +
    ")"
  );
}

function metricDescriptorLabels(
  labels: LogMetricLabel[],
): Array<{ key: string; valueType: string; description: string }> {
  return labels.map((l) => ({
    key: l.key,
    valueType: l.valueType,
    description: l.description,
  }));
}

function labelExtractors(labels: LogMetricLabel[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (const l of labels) out[l.key] = `EXTRACT(${l.sourceField})`;
  return out;
}

/**
 * A counter (`metricKind: DELTA`, `valueType: INT64`) log-based metric,
 * bounded on every label by `boundedLabels`.
 */
export interface CounterLogMetricSpec {
  name: string;
  description: string;
  message: string;
  boundedLabels: BoundedLabel[];
  /** Extra AND-ed filter clauses with no associated label, e.g. an existence check. */
  extraFilterClauses?: string[];
}

export function counterLogMetricFilterString(
  spec: CounterLogMetricSpec,
): string {
  return [
    `jsonPayload.message="${spec.message}"`,
    ...spec.boundedLabels.map(boundedLabelFilterClause),
    ...(spec.extraFilterClauses ?? []),
  ].join(" AND ");
}

export function toCounterLogMetricJson(spec: CounterLogMetricSpec): object {
  const labels = spec.boundedLabels.map((bl) => bl.label);
  return {
    name: spec.name,
    description: spec.description,
    filter: counterLogMetricFilterString(spec),
    metricDescriptor: {
      metricKind: "DELTA",
      valueType: "INT64",
      labels: metricDescriptorLabels(labels),
    },
    labelExtractors: labelExtractors(labels),
  };
}

/**
 * A distribution (`metricKind: DELTA`, `valueType: DISTRIBUTION`)
 * log-based metric: a histogram of `valueField`'s numeric value across
 * matching log entries, bounded on every label by `boundedLabels`.
 */
export interface DistributionLogMetricSpec {
  name: string;
  description: string;
  message: string;
  boundedLabels: BoundedLabel[];
  /** The `jsonPayload` field holding the numeric value, e.g. `"jsonPayload.latencyMs"`. */
  valueField: string;
  bucketOptions: BucketOptionsSpec;
  extraFilterClauses?: string[];
}

export function distributionLogMetricFilterString(
  spec: DistributionLogMetricSpec,
): string {
  return [
    `jsonPayload.message="${spec.message}"`,
    ...spec.boundedLabels.map(boundedLabelFilterClause),
    ...(spec.extraFilterClauses ?? []),
  ].join(" AND ");
}

export function toDistributionLogMetricJson(
  spec: DistributionLogMetricSpec,
): object {
  const labels = spec.boundedLabels.map((bl) => bl.label);
  return {
    name: spec.name,
    description: spec.description,
    filter: distributionLogMetricFilterString(spec),
    metricDescriptor: {
      metricKind: "DELTA",
      valueType: "DISTRIBUTION",
      labels: metricDescriptorLabels(labels),
    },
    labelExtractors: labelExtractors(labels),
    valueExtractor: `EXTRACT(${spec.valueField})`,
    bucketOptions: { explicitBuckets: { bounds: spec.bucketOptions.bounds } },
  };
}

/**
 * The real `google.monitoring.v3.AlertPolicy` REST shape for a log-match
 * ("any matching log entry is an incident") alert -- not just a filter
 * string. GPT-PM's review established that a filter alone cannot be
 * submitted as a policy: the API requires this full wrapper, including an
 * `alertStrategy` (log-based conditions require `notificationRateLimit`)
 * and a `notificationChannels` list. Field names/types confirmed against
 * Google's `projects.alertPolicies` REST reference (README.md has the
 * source). `notificationChannels: []` here is the actual safety property:
 * even if this JSON were submitted to the API today, it would create a
 * policy that notifies nobody -- the deliberate state while `FA-D1` is
 * pending, matching the HOLD on ever adding a channel before then.
 */
export interface AlertPolicySpec {
  displayName: string;
  conditionDisplayName: string;
  filter: LogMatchFilterSpec;
  /** Duration string, e.g. "300s" -- how often a repeat match may re-notify. */
  notificationRateLimitPeriod: string;
  /** Duration string, e.g. "604800s" -- auto-close an incident with no new matches this long. */
  autoClose: string;
}

export function toAlertPolicyJson(spec: AlertPolicySpec): object {
  return {
    displayName: spec.displayName,
    combiner: "OR",
    enabled: false,
    conditions: [
      {
        displayName: spec.conditionDisplayName,
        conditionMatchedLog: {
          filter: toGcpFilterString(spec.filter),
        },
      },
    ],
    alertStrategy: {
      notificationRateLimit: { period: spec.notificationRateLimitPeriod },
      autoClose: spec.autoClose,
      notificationPrompts: ["OPENED"],
    },
    notificationChannels: [],
  };
}

/**
 * MVP1.G3 Step 10A remediation. A log-match alert only fires while the
 * checking FUNCTION ITSELF runs and logs a failure -- it says nothing if
 * Cloud Scheduler's job is disabled/deleted, or a request hangs past the
 * function's own timeout with nothing ever logged. GPT-PM's review of the
 * first Step 10A submission: "add an independent freshness/absence
 * mechanism able to detect missed execution without relying on this
 * function's own custom log."
 *
 * `conditionAbsent` is Cloud Monitoring's own built-in mechanism for exactly
 * this ("this metric stopped reporting") -- watched here against
 * `cloudscheduler.googleapis.com/job/execution_count`, a metric the
 * PLATFORM emits automatically for every Scheduler job execution attempt,
 * independent of whether this codebase's own logging code ever runs at
 * all. This is the "already-available production mechanism, no unnecessary
 * infrastructure" GPT-PM's original Step 10A DoD asked to prefer.
 */
export interface MetricAbsenceAlertPolicySpec {
  displayName: string;
  conditionDisplayName: string;
  /** e.g. `metric.type="cloudscheduler.googleapis.com/job/execution_count" AND resource.type="cloud_scheduler_job" AND resource.label.job_id="..."` */
  filter: string;
  /** Duration string, e.g. "86400s" -- how long the metric may be absent before this fires. */
  absentFor: string;
  alignmentPeriodSeconds: number;
  notificationRateLimitPeriod: string;
  autoClose: string;
}

export function toMetricAbsenceAlertPolicyJson(
  spec: MetricAbsenceAlertPolicySpec,
): object {
  return {
    displayName: spec.displayName,
    combiner: "OR",
    enabled: false,
    conditions: [
      {
        displayName: spec.conditionDisplayName,
        conditionAbsent: {
          filter: spec.filter,
          duration: spec.absentFor,
          aggregations: [
            {
              alignmentPeriod: `${spec.alignmentPeriodSeconds}s`,
              perSeriesAligner: "ALIGN_COUNT",
              crossSeriesReducer: "REDUCE_SUM",
            },
          ],
        },
      },
    ],
    alertStrategy: {
      notificationRateLimit: { period: spec.notificationRateLimitPeriod },
      autoClose: spec.autoClose,
      notificationPrompts: ["OPENED"],
    },
    notificationChannels: [],
  };
}
