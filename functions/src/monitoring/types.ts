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

/**
 * A log-based metric: a counter over log entries matching `filter`,
 * grouped by `labelKeys` (each key must be a field present in every
 * matched entry's `jsonPayload`, e.g. "fn" or "attested" for the App Check
 * signal). Rendered separately from an alert filter because a metric
 * descriptor and an alert policy are different GCP resource kinds even
 * though both start from a Cloud Logging filter.
 */
export interface LogBasedMetricSpec {
  name: string;
  description: string;
  filter: string;
  labelKeys: string[];
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
