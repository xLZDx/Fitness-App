/**
 * The SEVEN new callables of design 5.4 as one table (the F41 list). The
 * hardening tests (F60 validation, F61 quota, F62 hygiene, F76 fence, F79 Auth
 * existence) iterate this table so a callable cannot dodge them.
 */
/* eslint-disable @typescript-eslint/no-explicit-any */
import { handleCommitActivityStream } from "../../../activity_streams/commit_stream";
import { handleCreateActivityStreamUpload } from "../../../activity_streams/create_upload";
import { handleDeleteActivity } from "../../../activity_streams/delete_activity";
import { handleDeleteAllActivityStreams } from "../../../activity_streams/delete_all_streams";
import { handleGetActivityStreamDownloadUrls } from "../../../activity_streams/download_urls";
import { handleSetActivityCloudSettings } from "../../../activity_streams/set_settings";
import { handleSendDebugTelemetry } from "../../../activity_streams/telemetry";
import { ACT, ACT_2, UID, store, type World } from "./fakes";
import { fullUpload } from "./flow";

export interface SevenEntry {
  name: string;
  quotaAction: string;
  limit: number;
  /** Calls the handler with the standard (UID, password) caller unless overridden. */
  call(w: World, data: unknown, uid?: string, provider?: string): Promise<any>;
  /** A request that succeeds on the primed world, repeatedly. */
  ok(ctx: Primed): unknown;
}

export interface Primed {
  uploadId: string;
  sha: string;
  bytes: number;
}

/** Seeds a stored stream for ACT and clears the usage counters. */
export async function prime(w: World): Promise<Primed> {
  const f = await fullUpload(w);
  clearUsage();
  return { uploadId: f.uploadId, sha: f.up.sha, bytes: f.up.bytes.length };
}

export function clearUsage(): void {
  for (const k of [...store.keys()]) if (k.includes("/usage/")) store.delete(k);
}

export const TELEMETRY_OK = { events: [{ type: "log", level: "info", component: "app" }] };

export const SEVEN: SevenEntry[] = [
  {
    name: "createActivityStreamUpload", quotaAction: "activityStreamUpload", limit: 30,
    call: (w, d, uid = UID, p = "password") => handleCreateActivityStreamUpload(w.deps, uid, p, d),
    ok: (c) => ({ activityId: ACT, bytes: c.bytes, contentSha256: c.sha }),
  },
  {
    name: "commitActivityStream", quotaAction: "activityStreamCommit", limit: 60,
    call: (w, d, uid = UID, p = "password") => handleCommitActivityStream(w.deps, uid, p, d),
    ok: (c) => ({ activityId: ACT, uploadId: c.uploadId }),
  },
  {
    name: "deleteActivity", quotaAction: "activityDelete", limit: 1000,
    call: (w, d, uid = UID, p = "password") => handleDeleteActivity(w.deps, uid, p, d),
    ok: () => ({ activityId: ACT_2 }),
  },
  {
    name: "setActivityCloudSettings", quotaAction: "activitySettingsSet", limit: 20,
    call: (w, d, uid = UID, p = "password") => handleSetActivityCloudSettings(w.deps, uid, p, d),
    ok: () => ({ streamRetentionDays: 730 }),
  },
  {
    name: "getActivityStreamDownloadUrls", quotaAction: "activityDownloadUrls", limit: 60,
    call: (w, d, uid = UID, p = "password") => handleGetActivityStreamDownloadUrls(w.deps, uid, p, d),
    ok: () => ({ activityIds: [ACT] }),
  },
  {
    name: "deleteAllActivityStreams", quotaAction: "activityDeleteAll", limit: 10,
    call: (w, _d, uid = UID, p = "password") => handleDeleteAllActivityStreams(w.deps, uid, p),
    ok: () => ({}),
  },
  {
    name: "sendDebugTelemetry", quotaAction: "debugTelemetrySend", limit: 200,
    call: (w, d, uid = UID, p = "password") => handleSendDebugTelemetry(w.deps, uid, p, d),
    ok: () => TELEMETRY_OK,
  },
];
