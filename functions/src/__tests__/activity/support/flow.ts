/**
 * Flow helpers that call the production handlers (kept apart from `fakes.ts`
 * because `fakes.ts` is loaded by the jest.mock factory of firebase-admin and
 * must not import production code).
 */
/* eslint-disable @typescript-eslint/no-explicit-any */
import { handleCreateActivityStreamUpload } from "../../../activity_streams/create_upload";
import { handleCommitActivityStream } from "../../../activity_streams/commit_stream";
import { ACT, UID, putQuarantine, uploadOf, validPayload, type Upload, type World } from "./fakes";

/**
 * Adds the invocation-bound identity (`expectedUid`, S02 design 17 item 25) to a plain-object request
 * that does not already carry the key. Non-object data and an explicit key (right or wrong) pass
 * through untouched, so the negative tests keep full control of the request.
 */
export function withUid(data: unknown, uid: string): unknown {
  if (typeof data !== "object" || data === null || Array.isArray(data)) return data;
  if (Object.prototype.hasOwnProperty.call(data, "expectedUid")) return data;
  return { ...(data as Record<string, unknown>), expectedUid: uid };
}

export const create = (w: World, data: unknown, uid = UID, provider = "password"): Promise<any> =>
  handleCreateActivityStreamUpload(w.deps, uid, provider, withUid(data, uid));

export const commit = (w: World, data: unknown, uid = UID, provider = "password"): Promise<any> =>
  handleCommitActivityStream(w.deps, uid, provider, withUid(data, uid));

/** Settles a promise to its HttpsError message/code, or "OK". */
export async function outcome(p: Promise<unknown>): Promise<string> {
  try {
    await p;
    return "OK";
  } catch (e: any) {
    return `${e.code}:${e.message}`;
  }
}

/** Create + PUT: returns the upload id and the client bytes. */
export async function stage(
  w: World,
  obj: unknown = validPayload(),
  uid = UID,
  id = ACT,
): Promise<{ uploadId: string; up: Upload }> {
  const up = uploadOf(obj);
  const res = await create(w, { activityId: id, bytes: up.bytes.length, contentSha256: up.sha }, uid);
  if (res.status !== "upload") throw new Error(`stage: expected an upload, got ${res.status}`);
  putQuarantine(w, up, res.uploadId, uid, id);
  return { uploadId: res.uploadId, up };
}

/** stage + commit. */
export async function fullUpload(
  w: World,
  obj: unknown = validPayload(),
  uid = UID,
  id = ACT,
): Promise<{ uploadId: string; up: Upload; result: any }> {
  const s = await stage(w, obj, uid, id);
  const result = await commit(w, { activityId: id, uploadId: s.uploadId }, uid);
  return { ...s, result };
}
