/**
 * Identifier patterns and object path builders of the activity stream bucket
 * (S02 design 5.1, 5.2, 5.4). Paths are built ONLY from `request.auth.uid` and
 * identifiers that passed these patterns; a client-supplied path or prefix is
 * never used. Every builder throws on a bad input, so a path containing `/`,
 * `..` or an empty segment can never be produced.
 */

/** Activity id (design 5.4): `act_` plus 40 lowercase hex characters. */
export const ACTIVITY_ID_PATTERN = /^act_[0-9a-f]{40}$/;

/** Server-generated upload id (PROPOSED): `up_` plus 32 lowercase hex characters. */
export const UPLOAD_ID_PATTERN = /^up_[0-9a-f]{32}$/;

/** Firebase Auth uid as a path segment (1-128 URL-safe characters, no `/`). */
export const UID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

export function isActivityId(v: unknown): v is string {
  return typeof v === "string" && ACTIVITY_ID_PATTERN.test(v);
}

export function isUploadId(v: unknown): v is string {
  return typeof v === "string" && UPLOAD_ID_PATTERN.test(v);
}

function uidOf(uid: string): string {
  if (!UID_PATTERN.test(uid)) throw new Error("bad_uid");
  return uid;
}

function activityIdOf(id: string): string {
  if (!ACTIVITY_ID_PATTERN.test(id)) throw new Error("bad_activity_id");
  return id;
}

function uploadIdOf(id: string): string {
  if (!UPLOAD_ID_PATTERN.test(id)) throw new Error("bad_upload_id");
  return id;
}

/** `quarantine/{uid}/{activityId}/{uploadId}`: where the client PUTs (signed URL). */
export function quarantineObjectPath(uid: string, activityId: string, uploadId: string): string {
  return `quarantine/${uidOf(uid)}/${activityIdOf(activityId)}/${uploadIdOf(uploadId)}`;
}

/** `streams/{uid}/{activityId}/{uploadId}.json.gz`: the promoted canonical object. */
export function streamObjectPath(uid: string, activityId: string, uploadId: string): string {
  return `streams/${uidOf(uid)}/${activityIdOf(activityId)}/${uploadIdOf(uploadId)}.json.gz`;
}

/** Prefix of every promoted object of one activity (reconciler, delete). */
export function activityStreamsPrefix(uid: string, activityId: string): string {
  return `streams/${uidOf(uid)}/${activityIdOf(activityId)}/`;
}

/** Prefix of every quarantine object of one activity. */
export function activityQuarantinePrefix(uid: string, activityId: string): string {
  return `quarantine/${uidOf(uid)}/${activityIdOf(activityId)}/`;
}

/** Prefix of every promoted object of one user (account delete, bulk delete). */
export function userStreamsPrefix(uid: string): string {
  return `streams/${uidOf(uid)}/`;
}

/** Prefix of every quarantine object of one user. */
export function userQuarantinePrefix(uid: string): string {
  return `quarantine/${uidOf(uid)}/`;
}

/** `users/{uid}/activities/{activityId}`: the client-written summary document. */
export function activitySummaryPath(uid: string, activityId: string): string {
  return `users/${uidOf(uid)}/activities/${activityIdOf(activityId)}`;
}

/** `users/{uid}/activity_streams/{activityId}`: the server-written stream index row. */
export function activityStreamRowPath(uid: string, activityId: string): string {
  return `users/${uidOf(uid)}/activity_streams/${activityIdOf(activityId)}`;
}

/** `users/{uid}/activity_tombstones/{activityId}`: the server-written delete marker (design 6.2). */
export function activityTombstonePath(uid: string, activityId: string): string {
  return `users/${uidOf(uid)}/activity_tombstones/${activityIdOf(activityId)}`;
}
