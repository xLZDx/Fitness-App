/**
 * Pure logic of retention and purge (S02 design 5.3, 6.3; story S02-05b).
 *
 * Nothing here talks to Firestore, Storage or the clock: every function takes
 * plain objects and an explicit `nowMs`, so test agents drive each branch
 * directly (expiry arithmetic, hint rewrite rule, purge decision, recompute
 * cursor validity, batch/budget arithmetic, overdue and backlog metrics).
 *
 * The expiry is DERIVED at purge time: `activityDateUtc + current
 * streamRetentionDays`, where the activity date is the summary `startUtc`
 * clamped to [2000-01-01, now] (`activityDateMs`) and `null` retention means
 * never. The stored `expiresAt` on a row is only a HINT for the purge query: no
 * function below lets a hint extend retention.
 *
 * The arithmetic itself (`activityDateMs`, `derivedExpiryMs`, `isExpiryDue`) is
 * REUSED from `upload_common.ts`, the same code the upload and commit callables
 * use, so the three places can never disagree on what "due" means.
 */
import { MAX_PURGE_ATTEMPTS, PAGE, PURGE_RUN_BUDGET_MS } from "../body_scan/purge";
import type { StreamBucket } from "./bucket";
import { isActivityId, UID_PATTERN } from "./paths";
import {
  effectiveStreamRetentionDays,
  settingsGenerationOf,
  type StreamRetentionDays,
} from "./settings";
import {
  ACTIVITY_DATE_FLOOR_MS,
  derivedExpiryMs,
  timestampMs,
  type RowData,
} from "./upload_common";

/** Injectable collaborators of the scheduled purge and the recompute continuation. */
export interface RetentionDeps {
  firestore(): FirebaseFirestore.Firestore;
  /** The stream bucket, or `undefined` when `ACTIVITY_STREAM_BUCKET` is unset (the run is a logged no-op). */
  bucket(): StreamBucket | undefined;
  nowMs(): number;
}

/** Every size knob of a run, injectable so tests need not create hundreds of rows. */
export interface RetentionLimits {
  /** Candidate rows per page of the purge query (reuses the body-scan `PAGE`). */
  purgePage: number;
  /** Rows per page of one user's recompute walk (design 5.3: 100). */
  recomputePage: number;
  /** Users with `recomputePending == true` taken per run (design 5.3: 20). */
  recomputeUsersPerRun: number;
  /** Recompute pages one user may use per run, so a heavy user cannot starve the others. */
  recomputePagesPerUser: number;
  /** After this many failures a row is only COUNTED as capped; it is still retried every run (no give-up). */
  maxPurgeAttempts: number;
  /** Shared run budget; no new work is STARTED after it (reuses `PURGE_RUN_BUDGET_MS`). */
  runBudgetMs: number;
}

export const DEFAULT_RETENTION_LIMITS: RetentionLimits = {
  purgePage: PAGE,
  recomputePage: 100,
  recomputeUsersPerRun: 20,
  recomputePagesPerUser: 10,
  maxPurgeAttempts: MAX_PURGE_ATTEMPTS,
  runBudgetMs: PURGE_RUN_BUDGET_MS,
};

/** Share of the run budget the recompute continuation may use, so purge is never starved by it. */
export const RECOMPUTE_BUDGET_SHARE = 0.5;

/** The id pair of `users/{uid}/activity_streams/{activityId}`, or `undefined` for any other path. */
export function parseStreamRowPath(path: string): { uid: string; activityId: string } | undefined {
  const parts = path.split("/");
  if (parts.length !== 4 || parts[0] !== "users" || parts[2] !== "activity_streams") return undefined;
  if (!UID_PATTERN.test(parts[1]) || !isActivityId(parts[3])) return undefined;
  return { uid: parts[1], activityId: parts[3] };
}

/** The uid of `users/{uid}/activity_settings/main`, or `undefined` for any other path. */
export function parseSettingsPath(path: string): string | undefined {
  const parts = path.split("/");
  if (parts.length !== 4 || parts[0] !== "users" || parts[2] !== "activity_settings") return undefined;
  if (parts[3] !== "main" || !UID_PATTERN.test(parts[1])) return undefined;
  return parts[1];
}

/**
 * The start time the retention clock uses. The summary `startUtc` wins; when the
 * summary is gone the server-written `activityDateUtc` (then `receivedAt`) of the
 * row is used; with none of them the floor date is used, which makes the row due
 * under a finite retention (keeping GPS of unknown age is the worse error).
 * Never a request value.
 */
export function resolveStartMs(summaryStartMs: number | undefined, row: RowData): number {
  if (summaryStartMs !== undefined) return summaryStartMs;
  return timestampMs(row.activityDateUtc) ?? timestampMs(row.receivedAt) ?? ACTIVITY_DATE_FLOOR_MS;
}

/** The hint stored on a row in epoch millis; `null` for an absent or null hint (never). */
export function hintMsOf(row: RowData): number | null {
  return timestampMs(row.expiresAt) ?? null;
}

/**
 * True when the row's hint or generation differs from what the derivation says.
 * The test of "write nothing when nothing changed" for both the purge rewrite
 * and the recompute (a rerun after a crash must not double-write a row).
 */
export function hintNeedsRewrite(
  row: RowData,
  expiryMs: number | null,
  currentGeneration: number,
): boolean {
  return hintMsOf(row) !== expiryMs || settingsGenerationOf(row) !== currentGeneration;
}

export type PurgeDecision =
  /** The row is not `stored` (changed between the query and the transaction): do nothing. */
  | { kind: "skip" }
  /** Not due. `rewriteHint` is true when the stored hint or generation is out of date. */
  | { kind: "keep"; expiryMs: number | null; rewriteHint: boolean }
  /** Due: delete the object first, then mark the row `expired`. */
  | { kind: "purge"; expiryMs: number };

/**
 * The per-candidate decision, taken from the freshly re-read row and settings.
 * Due means `derivedExpiry <= now` (exactly now is due). The stored hint is
 * consulted only to decide whether it needs rewriting, never to decide due.
 */
export function decidePurge(
  row: RowData,
  settings: RowData | undefined,
  summaryStartMs: number | undefined,
  nowMs: number,
): PurgeDecision {
  if (row.state !== "stored") return { kind: "skip" };
  const retention: StreamRetentionDays = effectiveStreamRetentionDays(settings);
  const expiryMs = derivedExpiryMs(resolveStartMs(summaryStartMs, row), retention, nowMs);
  if (expiryMs !== null && expiryMs <= nowMs) return { kind: "purge", expiryMs };
  return {
    kind: "keep",
    expiryMs,
    rewriteHint: hintNeedsRewrite(row, expiryMs, settingsGenerationOf(settings)),
  };
}

export type RecomputeRowPlan =
  /** The row does not exist or nothing differs: write nothing. */
  | { kind: "none" }
  /** A stored row whose hint and/or generation must be rewritten. */
  | { kind: "hint"; expiryMs: number | null }
  /** A row that is not `stored` but carries an older generation: only stamp the generation. */
  | { kind: "stamp" };

/**
 * What the recompute does to one row (design 5.3). Only `stored` rows get a new
 * hint. Other rows are stamped with the current generation so the per-user final
 * pass (`settingsGeneration < current`) cannot be held open forever by an
 * `expired` row it would never rewrite. An unchanged row is `none`.
 */
export function planRecomputeRow(
  row: RowData | undefined,
  settings: RowData | undefined,
  summaryStartMs: number | undefined,
  nowMs: number,
): RecomputeRowPlan {
  if (row === undefined) return { kind: "none" };
  const generation = settingsGenerationOf(settings);
  if (row.state !== "stored") {
    return settingsGenerationOf(row) === generation ? { kind: "none" } : { kind: "stamp" };
  }
  const expiryMs = derivedExpiryMs(
    resolveStartMs(summaryStartMs, row),
    effectiveStreamRetentionDays(settings),
    nowMs,
  );
  return hintNeedsRewrite(row, expiryMs, generation) ? { kind: "hint", expiryMs } : { kind: "none" };
}

const ACTIVITY_ROW_ID = /^act_[0-9a-f]{40}$/;

/**
 * The recompute cursor that may be resumed: only a well-formed activity id AND
 * only when it was recorded for the CURRENT settings generation. A cursor from an
 * older generation (the setting changed again) is ignored, so every row is
 * revisited under the newest retention.
 */
export function effectiveRecomputeCursor(settings: RowData | undefined): string | undefined {
  const cursor = settings?.recomputeCursor;
  if (typeof cursor !== "string" || !ACTIVITY_ROW_ID.test(cursor)) return undefined;
  if (settings?.recomputeGeneration !== settingsGenerationOf(settings)) return undefined;
  return cursor;
}

/** The deadline of the recompute continuation inside the shared run budget. */
export function recomputeDeadlineMs(startMs: number, budgetMs: number): number {
  return startMs + Math.floor(budgetMs * RECOMPUTE_BUDGET_SHARE);
}

/** True when no new work may be started: the deadline has passed. */
export function budgetExhausted(nowMs: number, deadlineMs: number): boolean {
  return nowMs >= deadlineMs;
}

/** True when a page that returned `returned` rows of a `pageSize` query was the last one. */
export function isLastPage(returned: number, pageSize: number): boolean {
  return returned < pageSize;
}

/** The id the next page starts after: the last id of this page, or the old cursor when empty. */
export function nextCursor(pageIds: readonly string[], previous: string | undefined): string | undefined {
  return pageIds.length > 0 ? pageIds[pageIds.length - 1] : previous;
}

/** Age past the derived expiry in millis, `0` when not yet due (design 6.3 oldest overdue age). */
export function overdueAgeMs(expiryMs: number | null, nowMs: number): number {
  return expiryMs === null || expiryMs > nowMs ? 0 : nowMs - expiryMs;
}

/** The largest of the given ages, `0` for none. */
export function maxAgeMs(ages: readonly number[]): number {
  return ages.reduce((m, a) => (a > m ? a : m), 0);
}

/** Age of the oldest of the given start times, `0` for none (the recompute backlog age). */
export function backlogAgeMs(sinceMs: readonly number[], nowMs: number): number {
  if (sinceMs.length === 0) return 0;
  return Math.max(0, nowMs - Math.min(...sinceMs));
}

/** True for the Firestore "missing composite index" failure (design 6.3 last row). */
export function isMissingIndexError(e: unknown): boolean {
  const code = (e as { code?: unknown } | null | undefined)?.code;
  return code === 9 || code === "9" || code === "failed-precondition" || code === "FAILED_PRECONDITION";
}
