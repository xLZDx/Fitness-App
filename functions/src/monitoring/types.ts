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
 */
export interface LogEntryFixture {
  functionName: string;
  message: string;
  severity: "DEFAULT" | "INFO" | "WARNING" | "ERROR";
}

export interface LogMatchFilterSpec {
  /** `resource.labels.function_name` -- the deployed Cloud Function/Run service. */
  functionName: string;
  /** Matches if the log entry's message equals ANY of these, exactly. */
  messageEquals: string[];
}

export function toGcpFilterString(spec: LogMatchFilterSpec): string {
  const messageClause = spec.messageEquals
    .map((m) => `jsonPayload.message="${m}"`)
    .join(" OR ");
  return (
    `resource.labels.function_name="${spec.functionName}" ` +
    `AND (${messageClause})`
  );
}

export function matchesLogMatchFilter(
  spec: LogMatchFilterSpec,
  entry: LogEntryFixture,
): boolean {
  return (
    entry.functionName === spec.functionName &&
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
