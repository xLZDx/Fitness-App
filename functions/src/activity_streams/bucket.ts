/**
 * Injectable bucket seam for the activity stream callables (S02 design 5.2).
 *
 * The callables of S02-04b depend on the small structural interfaces below,
 * never on `@google-cloud/storage` types, so tests pass a fake bucket and can
 * count reads (the commit must read the quarantine object exactly once, pinned
 * to its generation: test F49). `activityStreamBucket()` returns `undefined`
 * when `ACTIVITY_STREAM_BUCKET` is unset or invalid; the caller turns that into
 * feature-off (callables) or a logged no-op (sweeps).
 */
import { getStorage } from "firebase-admin/storage";
import { activityStreamBucketName } from "./flags";

export interface StreamFileMetadata {
  generation?: string | number;
  size?: string | number;
  contentType?: string;
}

export interface StreamFile {
  getMetadata(): Promise<[StreamFileMetadata, ...unknown[]]>;
  /** Reads the whole object; a file opened with a `generation` is pinned to it. */
  download(): Promise<[Buffer, ...unknown[]]>;
  save(data: Buffer, options: { contentType: string; resumable?: boolean }): Promise<unknown>;
  delete(options?: { ignoreNotFound?: boolean }): Promise<unknown>;
  /** V4 signed URL (S02-04b: the upload callable signs the quarantine PUT). */
  getSignedUrl(config: {
    version: "v4";
    action: "write";
    expires: number;
    contentType: string;
    extensionHeaders?: Record<string, string>;
  }): Promise<[string, ...unknown[]]>;
}

export interface StreamBucket {
  /** `generation` pins every later read of the handle to that object version. */
  file(path: string, options?: { generation?: string | number }): StreamFile;
  /** Deletes every object under `prefix`; an empty prefix is a no-op. */
  deleteFiles(options: { prefix: string; force?: boolean }): Promise<unknown>;
}

/** An object returned by a prefix listing (reconciler, S02-06b). */
export interface ListedStreamFile {
  name: string;
  /** Raw GCS metadata; only `timeCreated` (RFC 3339) is read. */
  metadata?: { timeCreated?: string };
  delete(options?: { ignoreNotFound?: boolean }): Promise<unknown>;
}

/** A bucket that can also list a prefix (the real Admin SDK bucket can; the reconciler needs it). */
export interface StreamListingBucket extends StreamBucket {
  getFiles(options: {
    prefix: string;
    autoPaginate: false;
    maxResults: number;
    startOffset?: string;
  }): Promise<[ListedStreamFile[], ...unknown[]]>;
}

/** The configured stream bucket as a listing bucket, or `undefined` when the feature is off. */
export function activityStreamListingBucket(
  factory: StreamBucketFactory = defaultFactory,
): StreamListingBucket | undefined {
  return activityStreamBucket(factory) as StreamListingBucket | undefined;
}

/** Produces the bucket for a name; the default uses the Admin SDK. */
export type StreamBucketFactory = (name: string) => StreamBucket;

const defaultFactory: StreamBucketFactory = (name) =>
  getStorage().bucket(name) as unknown as StreamBucket;

/** The configured stream bucket, or `undefined` when the feature is off. */
export function activityStreamBucket(
  factory: StreamBucketFactory = defaultFactory,
): StreamBucket | undefined {
  const name = activityStreamBucketName();
  return name === undefined ? undefined : factory(name);
}

/**
 * Deletes every object under `prefix` in the stream bucket. Mirrors
 * `deleteScanObjects`: idempotent, and a no-op (returns `false`) when the
 * bucket is not configured because nothing could ever have been stored.
 */
export async function deleteStreamObjects(
  prefix: string,
  factory: StreamBucketFactory = defaultFactory,
): Promise<boolean> {
  const bucket = activityStreamBucket(factory);
  if (bucket === undefined) return false;
  await bucket.deleteFiles({ prefix });
  return true;
}
