/**
 * Body Scan server flags (design s7, D-60, SD-2) -- the ONE module that reads
 * `BODY_SCAN_BUCKET` and `BODY_SCAN_PROVIDER`.
 *
 * Both are environment variables (`functions/.env.<project>` reaches every
 * function in the default codebase, so `sweepAccountData` in `index.ts` and
 * the body-scan callables see the same value), both are unset by default, and
 * both are read PER CALL rather than at module load so a test can set and
 * clear them without re-requiring the module.
 *
 * Unset means the whole cloud photo path is off: no callable will do work
 * (`assertFeatureEnabled` answers `failed-precondition: feature-disabled`
 * before any quota is charged), and `sweepAccountData` treats the storage purge
 * as a logged no-op because nothing could ever have been stored (SD-6).
 * Enabling it is an operator action (`runbooks/body_scan_bucket.md`) and needs
 * no code change.
 */

/**
 * A GCS bucket name: 3-222 characters of lowercase letters, digits, `-`, `_`
 * and `.`, starting and ending with a letter or digit. Anything else is
 * treated as "not configured" -- a typo disables the feature rather than
 * pointing the purge at a different bucket.
 */
const BUCKET_NAME = /^[a-z0-9][a-z0-9._-]{1,220}[a-z0-9]$/;

/** The private body-scan bucket, or `undefined` when none is configured. */
export function bodyScanBucketName(): string | undefined {
  const raw = process.env.BODY_SCAN_BUCKET?.trim();
  return raw && BUCKET_NAME.test(raw) ? raw : undefined;
}

/** Whether the cloud photo path is configured at all (the bucket is set). */
export function bodyScanCloudEnabled(): boolean {
  return bodyScanBucketName() !== undefined;
}

/**
 * Whether NEW scans may be created and estimated (`createBodyScan`,
 * `estimateBodyScan`). On by default whenever the bucket is configured; the
 * operator sets `BODY_SCAN_ACCEPT_UPLOADS=false` (or `0`/`off`/`no`) to stop
 * intake WITHOUT unsetting the bucket. Erase paths (`deleteBodyScan`,
 * `manageBodyScanData`, the purge job, the account-delete sweep) never read
 * this: they depend on the bucket name alone, so rolling back intake can never
 * strand stored objects.
 */
export function bodyScanAcceptUploads(): boolean {
  if (!bodyScanCloudEnabled()) return false;
  const raw = process.env.BODY_SCAN_ACCEPT_UPLOADS?.trim().toLowerCase();
  return !(raw === "false" || raw === "0" || raw === "off" || raw === "no");
}

/**
 * The registered estimator id the server should use (`licensed-api` or
 * `test-fake`), or `undefined` when none is configured. There is no server-side
 * provisional estimator (D-52): the provisional estimate is computed on the
 * device, so an unset provider means no server estimate can be produced.
 */
export function bodyScanProviderId(): string | undefined {
  const raw = process.env.BODY_SCAN_PROVIDER?.trim();
  return raw ? raw : undefined;
}
