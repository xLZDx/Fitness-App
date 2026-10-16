/**
 * Activity stream server flag (S02 design 5): the ONE module that reads
 * `ACTIVITY_STREAM_BUCKET`.
 *
 * Same shape as `body_scan/flags.ts`: an environment variable in
 * `functions/.env.<project>`, unset by default, read PER CALL. Unset means the
 * cloud stream path is off: the callables answer feature-off and the sweep is
 * a logged no-op, because nothing could ever have been stored.
 *
 * GPS-PRIV-064 isolation: the stream bucket must be its own bucket. A value
 * equal to `BODY_SCAN_BUCKET` is treated as NOT configured (the feature stays
 * off) so a copy-paste mistake can never put GPS streams next to photos.
 */
import { bodyScanBucketName } from "../body_scan/flags";

/** Same GCS naming rule as the Body Scan bucket. */
const BUCKET_NAME = /^[a-z0-9][a-z0-9._-]{1,220}[a-z0-9]$/;

/** The private activity stream bucket, or `undefined` when none is configured. */
export function activityStreamBucketName(): string | undefined {
  const raw = process.env.ACTIVITY_STREAM_BUCKET?.trim();
  if (!raw || !BUCKET_NAME.test(raw)) return undefined;
  if (raw === bodyScanBucketName()) return undefined;
  return raw;
}

/** Whether the cloud stream path is configured at all. */
export function activityStreamCloudEnabled(): boolean {
  return activityStreamBucketName() !== undefined;
}
