/**
 * Account-deletion sweep of the private activity stream bucket (S02 design 6,
 * 6.1; story S02-06b).
 *
 * `sweepActivityStreamObjects(uid)` is called by `sweepAccountData` in
 * `index.ts`, which `deleteAccount` runs TWICE (Step 2 and Step 4) and
 * `reconcileAccountDeletions` runs on every retry, so every call must be
 * idempotent and must not need any Firestore row or settings document (at
 * Step 4 those are already deleted). The error contract mirrors
 * `sweepBodyScanObjects`:
 *
 *  - bucket not configured: a logged no-op (nothing could ever have been stored);
 *  - every failure of a prefix is a 404 ("nothing to delete", also a missing
 *    bucket): success;
 *  - anything else (403 IAM, network): THROWS ONE bare error, after BOTH prefixes
 *    (`streams/<uid>/` and `quarantine/<uid>/`) were attempted. A failure on the
 *    first prefix therefore never leaves the second untouched while the retry
 *    count is capped at `RETRY_MAX_ATTEMPTS` (design 6.1 / test F57).
 *
 * `runIndependentCleanups` is the aggregation half of the positive cleanup
 * invariant (design 6.1, test F78): every cleanup is attempted, a failure of one
 * never prevents the attempt of the others, and the errors become ONE bare code
 * so the durable retry completes the unfinished work.
 *
 * The prefix always ends with `/`, so uid `abc` never matches the objects of
 * uid `abcd`. Logging carries closed slugs and bare codes only (GPS-PRIV-094).
 */
import * as logger from "firebase-functions/logger";
import { activityStreamBucket, type StreamBucket } from "./bucket";
import { UID_PATTERN, userQuarantinePrefix, userStreamsPrefix } from "./paths";
import { errorCodeOf, isNotFound } from "./upload_common";

/** Logged (as message and `event`) when the sweep is a no-op because the bucket is unset. */
export const ACTIVITY_SWEEP_SKIPPED = "activity_stream_storage_sweep_skipped_unconfigured";

/** Injectable bucket seam of the sweep (`undefined` = feature off). */
export interface ActivitySweepDeps {
  bucket(): StreamBucket | undefined;
}

export const defaultActivitySweepDeps: ActivitySweepDeps = {
  bucket: () => activityStreamBucket(),
};

/**
 * Deletes one prefix. `force: true` keeps deleting after a single object fails
 * and reports every failure as an array, so the 404 test looks at all of them.
 * Resolves to `undefined` on success (or when everything was 404) and to the
 * first non-404 error otherwise; never throws.
 */
async function deletePrefix(bucket: StreamBucket, prefix: string): Promise<unknown | undefined> {
  try {
    await bucket.deleteFiles({ prefix, force: true });
    return undefined;
  } catch (err) {
    const errors: unknown[] = Array.isArray(err) ? err : [err];
    if (errors.length > 0 && errors.every(isNotFound)) return undefined;
    return errors.find((e) => !isNotFound(e)) ?? errors[0] ?? err;
  }
}

/**
 * Removes every object of [uid] under `streams/` and `quarantine/`. Both
 * prefixes are attempted independently; any failure throws ONE bare error whose
 * `code` is the first failure's code (the SDK message can name the bucket and
 * the object path, so it is never carried).
 */
export async function sweepActivityStreamObjects(
  uid: string,
  deps: ActivitySweepDeps = defaultActivitySweepDeps,
): Promise<void> {
  const bucket = deps.bucket();
  if (bucket === undefined) {
    logger.info(ACTIVITY_SWEEP_SKIPPED, { event: ACTIVITY_SWEEP_SKIPPED });
    return;
  }
  // No callable can have stored anything under a uid the path builders refuse.
  if (!UID_PATTERN.test(uid)) return;

  const failures: unknown[] = [];
  for (const prefix of [userStreamsPrefix(uid), userQuarantinePrefix(uid)]) {
    const failure = await deletePrefix(bucket, prefix);
    if (failure !== undefined) failures.push(failure);
  }
  if (failures.length > 0) {
    throw Object.assign(new Error("activity stream storage sweep failed"), {
      code: errorCodeOf(failures[0]),
    });
  }
}

/**
 * Runs every cleanup in order, never skipping one because an earlier one failed.
 * No failure: resolves. Exactly one failure: that error is rethrown unchanged (so
 * a single-cleanup failure behaves exactly as before). Several failures: ONE
 * new error with the first failure's `code` (a bare code, no message).
 */
export async function runIndependentCleanups(
  steps: ReadonlyArray<() => Promise<void>>,
): Promise<void> {
  const failures: unknown[] = [];
  for (const step of steps) {
    try {
      await step();
    } catch (err) {
      failures.push(err);
    }
  }
  if (failures.length === 0) return;
  if (failures.length === 1) throw failures[0];
  throw Object.assign(new Error("account storage sweep failed"), {
    code: (failures[0] as { code?: unknown } | null)?.code,
  });
}
