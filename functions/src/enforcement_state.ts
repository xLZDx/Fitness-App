/**
 * MVP1.G3 Step 10A — live production enforcement-state visibility.
 *
 * WHY THIS EXISTS
 *
 * `scripts/dev/production_manifest.py` already reads live Functions/
 * Firestore-rules/App-Check/Hosting state and refuses to invent a value —
 * but it is a human-run script (`python scripts/dev/production_manifest.py`),
 * so its own honesty guarantee ("every field is a live read or an explicit
 * `unavailable:`") only holds at the moment someone remembers to run it.
 * GPT-PM's Step 10A ruling (`core/DECISION_LOG.md`, 2026-08-27): this needs
 * to be a repeatable AUTOMATED check with mechanically detectable staleness,
 * not a human-only audit — the exact gap OBS-1 item #3 was left PARTIAL on
 * at the original G3 re-baseline.
 *
 * This file is the automated counterpart: the same four live sections
 * (Functions, Firestore rules, App Check, Identity Toolkit — Hosting is
 * intentionally NOT repeated here, see below), read with the DEPLOYED
 * function's own ambient service-account credentials rather than a human's
 * `gcloud`/`firebase` CLI session, wired to a Cloud Scheduler trigger by
 * `enforcement_state_schedule.ts` so "did anyone check recently" becomes a
 * question Cloud Scheduler's own execution history (and, since GPT-PM's
 * remediation round, an independent metric-absence alert -- see
 * `alert_definitions.ts`'s `ENFORCEMENT_STATE_STALENESS_POLICY`) can answer
 * instead of a question about a human's memory.
 *
 * WHY HOSTING IS NOT INCLUDED
 *
 * `production_manifest.py`'s Hosting section exists because that script
 * audits the whole deployable surface. GPT-PM's Step 10A DoD names exactly
 * four things: "deployed Functions inventory; active Firestore ruleset +
 * update time; App Check enforcement/state...; Identity Toolkit/Auth state."
 * Hosting is not on that list, and this project's Hosting surface is not
 * itself an enforcement/security-relevant control the way rules/App-Check/
 * Auth are — adding it would be scope creep on a step GPT-PM was explicit
 * should not expand.
 *
 * WHY THE IDENTITY TOOLKIT SECTION ONLY EXTRACTS AN ALLOWLIST OF FIELDS
 *
 * `GET .../v2/projects/{project}/config` returns `signIn.hashConfig.signerKey`
 * (the password-hashing signer key — a real secret) and `client.apiKey` (the
 * project's Web API key — the exact same value this project's canary probe
 * treats as a secret, held in Secret Manager as `CANARY_WEB_API_KEY`).
 * Confirmed live by probing this endpoint directly before writing this file
 * (`D:/Temp/.../scratchpad/idtoolkit_probe.json`, not committed — see
 * `core/DECISION_LOG.md`'s Step 10A entry for the full field inventory).
 * `extractIdentityToolkitState()` below is a strict ALLOWLIST, not a
 * denylist: it reads only the specific fields this check needs and never
 * passes the raw response through, so a future field Google adds to that
 * API cannot silently leak into committed evidence the way a denylist would.
 *
 * WHY A SECTION FAILS CLOSED ON A MALFORMED OR EMPTY RESULT
 *
 * GPT-PM's remediation-round finding: an HTTP 200 with a missing/malformed
 * body, or a genuinely empty list where this specific project always has a
 * nonzero real count (Functions, Firestore rules releases), used to still
 * be reported `OK` -- proving only that the API call succeeded, not that
 * the returned state was real. `readListSection()` below now treats a
 * non-object body, a present-but-non-array list key, AND (for the two
 * sections where this project can never legitimately be empty) a
 * zero-length list as `UNAVAILABLE`, not silent success. App Check is
 * deliberately exempt from the zero-length rule: `production_manifest.py`'s
 * own comment already documents that an empty App Check services list is a
 * MEANINGFUL state (no service has a non-default enforcement mode), not an
 * error -- flagging it as `UNAVAILABLE` would be a false alarm on the
 * common case, not a real robustness improvement.
 *
 * WHY LIST CALLS FOLLOW PAGINATION
 *
 * None of the three list endpoints this file calls needs more than one page
 * at this project's current scale (confirmed live: no `nextPageToken` in
 * any of the three real responses probed before writing this remediation).
 * But all three APIs support it, and silently reading only page one while a
 * genuine future page two exists is exactly the kind of "reachable but
 * incomplete" gap GPT-PM's review flagged -- `fetchAllPages()` follows
 * `nextPageToken` for every list section, bounded to `MAX_PAGES` so a
 * malfunctioning API returning an ever-repeating token cannot loop this
 * function forever.
 *
 * WHY EVERY REQUEST HAS ITS OWN TIMEOUT, SHORTER THAN THE FUNCTION'S
 *
 * The deployed function itself has `timeoutSeconds: 60`
 * (`enforcement_state_schedule.ts`) -- without a per-request bound, one
 * hung network call could silently consume the whole budget with nothing
 * logged before Cloud Functions kills the instance, which is itself a
 * silent-failure gap (GPT-PM's review named this directly: "an outbound
 * request hangs until platform timeout"). `REQUEST_TIMEOUT_MS` bounds each
 * individual call well under that ceiling, so a hang on one section still
 * lets the others complete and still lets this function's own
 * try/catch/log run before the platform would ever intervene.
 *
 * WHY THIS IS TESTABLE WITHOUT LIVE GCP CREDENTIALS
 *
 * `runEnforcementStateProbe()` takes an optional `deps` object (token getter
 * + JSON fetcher + clock); the real implementation (`realDeps`, used by the
 * production default) calls `google-auth-library`, the real REST APIs and
 * `Date.now`, but every unit test injects a fake `deps` instead — same
 * principle as `canary_probe.ts`'s emulator-env-var detection: production
 * code has no test-only branch, tests substitute the actual seam.
 *
 * ROUND 2 (2026-08-27, same day): GPT-PM re-reviewed the round-1 remediation
 * commit and found the same four original findings still open in a deeper
 * form, plus this file's own App Check enforcement-mode comparison was
 * checking a string (`"OFF"`) the real API never returns. Each is documented
 * where it's fixed; the summary:
 *
 * WHY APP CHECK NOW COMPARES AGAINST "ENFORCED", NOT "OFF"
 *
 * A live probe during this remediation round
 * (`https://firebaseappcheck.googleapis.com/v1/projects/{p}/services`)
 * returned real `enforcementMode` values of `"UNENFORCED"` and `"ENFORCED"`
 * -- never `"OFF"`/`"ON"`. Round 1's `anyEnforcementOff` check compared
 * against the literal `"OFF"`, which no real response can ever equal, so the
 * signal was silently dead on arrival regardless of actual state. Every
 * comparison in this file now treats anything other than the literal
 * `"ENFORCED"` as not-enforced, which is also safer against a future enum
 * value this file has never seen (fail toward flagging, not toward silence).
 *
 * WHY APP CHECK ALSO CHECKS A NAMED LIST OF INTENDED SERVICES, NOT JUST
 * WHATEVER services.list HAPPENS TO RETURN
 *
 * `services.list` only returns a row for a backing service that has ever had
 * its enforcement mode explicitly set; a service Firebase has never heard an
 * opinion about is simply absent from the list, which round 1's code (and
 * `production_manifest.py`'s own comment) treated as an unremarkable empty
 * state. That reasoning is right for a service this project doesn't rely on
 * App Check for at all, and wrong for one it does: `firestore.rules`
 * (`D:\Repo\Fitness_App\firestore.rules`) grants an authenticated client
 * direct read/write access to its own `/users/{uid}/...` subtree with no
 * App-Check gate written into the rules themselves -- backing-service-level
 * enforcement on `firestore.googleapis.com` is the ONLY control that can
 * require App Check attestation on that direct path at all (the callables'
 * own `enforceAppCheck: true` option, `scaling.ts`, is a completely separate
 * mechanism enforced by the Functions runtime and never appears in this API
 * response either way). A live probe during this remediation round confirmed
 * `firestore.googleapis.com` is currently present and `UNENFORCED` -- a real,
 * current state this check now actually surfaces via
 * `unenforcedIntendedServices`, where round 1 could not have caught it even
 * if the row had been entirely absent. No `storage.rules` file exists in
 * this repo (confirmed by its absence), so Cloud Storage direct client
 * access is not part of this project's architecture today and is
 * deliberately not in `APP_CHECK_INTENDED_ENFORCED_SERVICES`. This section's
 * `status` still means "the read succeeded and the data is structurally
 * valid," same as every other section in this file -- it does not mean "the
 * observed state is the desired one." Whether an unenforced intended service
 * should itself page someone is a monitoring-policy decision for whoever
 * consumes `unenforcedIntendedServices`, deliberately left out of this
 * step's scope.
 *
 * WHY EVERY ROW IS VALIDATED, NOT JUST THE ENVELOPE
 *
 * Round 1 fixed a non-object body, a non-array list and a zero-length list
 * where this project can never legitimately be empty -- but a row inside a
 * genuinely non-empty, well-formed list could still be missing the specific
 * field this file depends on (`f.state`, `r.rulesetName`, `s.enforcementMode`),
 * and round 1's `?? "?"` fallback would quietly report `state: "?"` as `OK`
 * rather than surface that the read didn't actually return what this file
 * needs. Every section now rejects (not filters -- the whole section, so a
 * shrunk-but-silent count can't happen either) on any row missing its
 * required identifying fields. Firestore Rules additionally requires that
 * one of the valid rows be specifically the `cloud.firestore` release (its
 * real name, confirmed live: `projects/{project}/releases/cloud.firestore`)
 * -- a non-empty releases list that happens to contain some other release
 * but not this project's actual Firestore ruleset used to read as `OK`.
 *
 * WHY A NON-EMPTY unreachable[] MAKES THE FUNCTIONS SECTION UNAVAILABLE
 *
 * The Cloud Functions v2 `locations/-/functions` list contract can return an
 * `unreachable` array naming locations the API could not query for this
 * call -- functions deployed there are simply missing from `functions[]`,
 * with no other signal. `fetchAllPages()` now accumulates `unreachable`
 * across every page; if it's ever non-empty, the Functions section reports
 * `UNAVAILABLE` (keeping the partial `data` it already read, per this file's
 * existing "retain what was read" convention) instead of a silently
 * incomplete `OK`.
 *
 * WHY THERE IS A WHOLE-PROBE DEADLINE, NOT JUST A PER-REQUEST TIMEOUT
 *
 * A per-request `AbortSignal.timeout` bounds one call, but `fetchAllPages`
 * can make up to `MAX_PAGES` of them for one section -- several near-timeout
 * pages in a row could still exhaust the function's own 60-second platform
 * budget before `runEnforcementStateProbe()` ever returns, which silently
 * recreates the exact "platform kills the instance before our own
 * try/catch/log runs" gap the per-request timeout was meant to close.
 * `PROBE_BUDGET_MS` is a single deadline computed once, before token
 * acquisition, and threaded into every section and every page: each fetch
 * checks the remaining budget first and fails closed
 * (`"probe deadline exceeded..."`) instead of firing a request that has no
 * real chance to matter, and each request's own timeout is capped to
 * whatever budget actually remains. The deadline is read through the same
 * injectable `deps.now` seam as everything else, so a test can simulate the
 * clock crossing it without real elapsed time or fake system timers.
 *
 * ROUND 3 (2026-08-27, same day): GPT-PM's re-review of round 2 found the
 * deadline was computed before token acquisition but never actually applied
 * to it, and that a structurally valid `cloud.firestore` row could still be
 * accepted `OK` with no genuine `updateTime`.
 *
 * WHY TOKEN ACQUISITION IS RACED AGAINST THE SAME DEADLINE, NOT A NEW TIMER
 *
 * `deadlineAt` used to be computed before `deps.getAccessToken()` so its
 * elapsed time would count against the budget -- but nothing actually BOUNDS
 * `getAccessToken()` itself. A hang there (ADC/metadata/token-exchange) would
 * consume the function's entire 60-second platform timeout before any
 * section, or this file's own try/catch/log, ever ran -- the identical
 * silent-platform-kill failure mode the per-request and per-page deadline
 * checks exist to close, just one step earlier. `deps.raceDeadline()` races
 * `getAccessToken()`'s promise against the SAME `deadlineAt` (never a second,
 * independent timer that could outlive it, per GPT-PM's explicit
 * requirement) and is itself an injectable seam, so a test can force the
 * deadline branch to win deterministically against a token promise that
 * never resolves, without a real elapsed wall-clock wait. The real
 * implementation `.unref()`s its underlying timer so a lost race never keeps
 * the process alive past the point the rest of this file has already failed
 * closed, and always clears it so a normal (non-timeout) run never leaks a
 * live ~45s timer into the background -- this suite already showed a "worker
 * process failed to exit gracefully... active timers" warning once before,
 * from an unrelated cause, and this file has no interest in adding a real
 * one of its own.
 *
 * WHY THE cloud.firestore ROW ALSO REQUIRES A VALID updateTime
 *
 * Step 10A's own DoD is "active Firestore ruleset + update time," not merely
 * "a `cloud.firestore` release exists" -- round 2 required the release and
 * its `rulesetName` but still let `updateTime` default to `"?"` on an
 * otherwise-OK section. The `cloud.firestore` row specifically (other rows
 * are unaffected) now also requires a non-empty `updateTime` that
 * `Date.parse` accepts, or the section reports `UNAVAILABLE` instead of a
 * snapshot that silently doesn't have the one field Step 10A was built to
 * prove. Functions' own `updateTime` is held to the same bar (always present
 * per the v2 API contract, independent of GEN_1/GEN_2). `revision`
 * (`serviceConfig.revision`) is deliberately NOT made required alongside it:
 * that field's presence is generation-dependent in ways this file has no
 * live GEN_1 deployment to verify against (this project's own functions are
 * all confirmed `GEN_2`), so requiring it now would be encoding an unverified
 * assumption rather than a proven contract -- kept as best-effort (`?? "?"`)
 * and left as a scoping call GPT-PM can contest next round if it disagrees.
 */
import { GoogleAuth } from "google-auth-library";

export type SectionStatus = "OK" | "UNAVAILABLE";

export interface SectionResult {
  status: SectionStatus;
  /** Only set when `status === "UNAVAILABLE"` — never invented, never blank-means-fine. */
  error?: string;
  data?: Record<string, unknown>;
}

export type OverallStatus = "OK" | "DEGRADED" | "FAILED";

export interface EnforcementStateResult {
  status: OverallStatus;
  generatedAt: string;
  sections: {
    functions: SectionResult;
    firestoreRules: SectionResult;
    appCheck: SectionResult;
    identityToolkit: SectionResult;
  };
}

export interface JsonFetchResult {
  ok: boolean;
  status: number;
  json: unknown;
  errorText?: string;
}

export type JsonFetcher = (
  url: string,
  token: string,
  extraHeaders?: Record<string, string>,
  timeoutMs?: number,
) => Promise<JsonFetchResult>;

export type TokenGetter = () => Promise<string>;

/**
 * Races `promise` against `remainingMs`, resolving/rejecting with whichever
 * finishes first. Never a second, independent timer -- callers always pass
 * however much of the SAME whole-probe deadline is left. See module header,
 * "WHY TOKEN ACQUISITION IS RACED AGAINST THE SAME DEADLINE".
 */
export type DeadlineRacer = <T>(promise: Promise<T>, remainingMs: number, label: string) => Promise<T>;

export interface EnforcementStateDeps {
  project: string;
  getAccessToken: TokenGetter;
  fetchJson: JsonFetcher;
  /** Wall-clock source for the whole-probe deadline -- defaults to `Date.now`.
   *  Injectable so a test can simulate the clock advancing between calls
   *  without real elapsed time or fake system timers. */
  now: () => number;
  /** Defaults to a real setTimeout-based race. Injectable so a test can
   *  force the deadline branch to win deterministically, with no real
   *  elapsed wall-clock wait. */
  raceDeadline: DeadlineRacer;
}

const DEFAULT_PROJECT = "fitness-app-korostelev";
const REQUEST_TIMEOUT_MS = 20_000;
const MAX_PAGES = 20;
// Headroom under the deployed function's own 60s platform timeout
// (`enforcement_state_schedule.ts`) -- see this file's module header, "WHY
// THERE IS A WHOLE-PROBE DEADLINE".
const PROBE_BUDGET_MS = 45_000;

function realRaceDeadline<T>(promise: Promise<T>, remainingMs: number, label: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error(`probe deadline exceeded during ${label}`));
    }, remainingMs);
    // Never keep the process alive on this timer alone -- if it's ever left
    // to fire (it shouldn't be, `.then` below always clears it), the rest of
    // this file has already failed the probe closed by the time it matters.
    if (typeof timer.unref === "function") timer.unref();
    promise.then(
      (v) => {
        clearTimeout(timer);
        resolve(v);
      },
      (e) => {
        clearTimeout(timer);
        reject(e);
      },
    );
  });
}

async function realGetAccessToken(): Promise<string> {
  const auth = new GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/cloud-platform"],
  });
  const client = await auth.getClient();
  const tokenResponse = await client.getAccessToken();
  if (!tokenResponse.token) {
    throw new Error("GoogleAuth returned no access token");
  }
  return tokenResponse.token;
}

async function realFetchJson(
  url: string,
  token: string,
  extraHeaders: Record<string, string> = {},
  timeoutMs: number = REQUEST_TIMEOUT_MS,
): Promise<JsonFetchResult> {
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${token}`, ...extraHeaders },
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    return { ok: false, status: res.status, json: null, errorText: text.slice(0, 300) };
  }
  const json = await res.json();
  return { ok: true, status: res.status, json };
}

function realDeps(project: string): EnforcementStateDeps {
  return {
    project,
    getAccessToken: realGetAccessToken,
    fetchJson: realFetchJson,
    now: Date.now,
    raceDeadline: realRaceDeadline,
  };
}

/**
 * Fetches every page of a `{ [listKey]: T[], nextPageToken?: string,
 * unreachable?: string[] }`-shaped list endpoint, accumulating items AND any
 * `unreachable` entries across pages. Fails closed (returns `ok: false`) on
 * a non-2xx response, a non-object body, a body whose `listKey` is present
 * but not an array, or the whole-probe `deadlineAt` having passed -- see
 * this file's module header ("WHY A SECTION FAILS CLOSED...",
 * "WHY THERE IS A WHOLE-PROBE DEADLINE...") for why.
 */
async function fetchAllPages(
  deps: EnforcementStateDeps,
  token: string,
  baseUrl: string,
  listKey: string,
  deadlineAt: number,
  extraHeaders?: Record<string, string>,
): Promise<
  { ok: true; items: unknown[]; unreachable: string[] } | { ok: false; error: string }
> {
  const items: unknown[] = [];
  const unreachable: string[] = [];
  let pageToken: string | undefined;
  for (let page = 0; page < MAX_PAGES; page++) {
    const remaining = deadlineAt - deps.now();
    if (remaining <= 0) {
      return { ok: false, error: "probe deadline exceeded before all pages could be read" };
    }
    const url = pageToken
      ? `${baseUrl}${baseUrl.includes("?") ? "&" : "?"}pageToken=${encodeURIComponent(pageToken)}`
      : baseUrl;
    const timeoutMs = Math.max(1_000, Math.min(REQUEST_TIMEOUT_MS, remaining));
    const res = await deps.fetchJson(url, token, extraHeaders, timeoutMs);
    if (!res.ok) {
      return { ok: false, error: `HTTP ${res.status}: ${res.errorText ?? ""}`.trim() };
    }
    if (res.json === null || typeof res.json !== "object") {
      return { ok: false, error: "malformed response: body is not a JSON object" };
    }
    const body = res.json as Record<string, unknown>;
    const list = body[listKey];
    if (list !== undefined && !Array.isArray(list)) {
      return {
        ok: false,
        error: `malformed response: "${listKey}" is present but not an array`,
      };
    }
    if (Array.isArray(list)) items.push(...list);
    const bodyUnreachable = body.unreachable;
    if (Array.isArray(bodyUnreachable)) {
      for (const u of bodyUnreachable) if (typeof u === "string") unreachable.push(u);
    }
    const next = body.nextPageToken;
    if (typeof next === "string" && next.length > 0) {
      pageToken = next;
      continue;
    }
    return { ok: true, items, unreachable };
  }
  return { ok: false, error: `pagination did not terminate within ${MAX_PAGES} pages` };
}

/** True only when every required field is a non-empty string on every row. */
function everyRowHas(rows: Record<string, any>[], fields: string[]): boolean {
  return rows.every((row) => fields.every((f) => typeof row[f] === "string" && row[f].length > 0));
}

async function checkFunctions(
  deps: EnforcementStateDeps,
  token: string,
  deadlineAt: number,
): Promise<SectionResult> {
  const url =
    `https://cloudfunctions.googleapis.com/v2/projects/${deps.project}` +
    `/locations/-/functions`;
  const pages = await fetchAllPages(deps, token, url, "functions", deadlineAt);
  if (!pages.ok) return { status: "UNAVAILABLE", error: pages.error };
  if (pages.items.length === 0) {
    // This project always has deployed functions; a genuinely empty result
    // is far more likely to be a permission/API regression than reality.
    return { status: "UNAVAILABLE", error: "empty result: 0 functions returned" };
  }
  const rawItems = pages.items as Record<string, any>[];
  if (!everyRowHas(rawItems, ["name", "state", "updateTime"])) {
    return {
      status: "UNAVAILABLE",
      error: "malformed response: one or more function rows are missing name/state/updateTime",
    };
  }
  const items = rawItems
    .map((f) => ({
      name: String(f.name).split("/").pop(),
      state: f.state,
      environment: f.environment ?? "?",
      updateTime: f.updateTime,
      // NOT required alongside name/state/updateTime -- generation-dependent
      // in ways this file has no live GEN_1 deployment to verify against.
      // See module header, "WHY THE cloud.firestore ROW ALSO REQUIRES...".
      revision: f.serviceConfig?.revision ?? "?",
    }))
    .sort((a, b) => String(a.name).localeCompare(String(b.name)));
  if (pages.unreachable.length > 0) {
    // Functions in an unreachable location are simply missing from `items`
    // above with no other signal -- see this file's module header, "WHY A
    // NON-EMPTY unreachable[]...". Retain what was read as partial evidence.
    return {
      status: "UNAVAILABLE",
      error: `partial result: unreachable location(s): ${pages.unreachable.join(", ")}`,
      data: { count: items.length, functions: items },
    };
  }
  return { status: "OK", data: { count: items.length, functions: items } };
}

async function checkFirestoreRules(
  deps: EnforcementStateDeps,
  token: string,
  deadlineAt: number,
): Promise<SectionResult> {
  const url = `https://firebaserules.googleapis.com/v1/projects/${deps.project}/releases`;
  const pages = await fetchAllPages(deps, token, url, "releases", deadlineAt, {
    "X-Goog-User-Project": deps.project,
  });
  if (!pages.ok) return { status: "UNAVAILABLE", error: pages.error };
  if (pages.items.length === 0) {
    // Same reasoning as Functions -- this project always has a published
    // ruleset (`production_manifest.py`'s own comment: "no releases
    // returned -- no ruleset is published" is itself a red flag there too).
    return { status: "UNAVAILABLE", error: "empty result: 0 rule releases returned" };
  }
  const rawItems = pages.items as Record<string, any>[];
  if (!everyRowHas(rawItems, ["name", "rulesetName", "updateTime"])) {
    return {
      status: "UNAVAILABLE",
      error:
        "malformed response: one or more rule release rows are missing name/rulesetName/updateTime",
    };
  }
  const items = rawItems.map((r) => ({
    release: String(r.name).split("/").pop(),
    ruleset: String(r.rulesetName).split("/").pop(),
    updateTime: r.updateTime,
  }));
  const firestoreRelease = items.find((i) => i.release === "cloud.firestore");
  if (!firestoreRelease) {
    // A non-empty, well-formed releases list that simply doesn't contain
    // THIS project's actual Firestore ruleset used to read as OK -- see
    // module header, "WHY EVERY ROW IS VALIDATED...".
    return {
      status: "UNAVAILABLE",
      error: "no cloud.firestore release present among returned releases",
      data: { count: items.length, releases: items },
    };
  }
  if (Number.isNaN(Date.parse(firestoreRelease.updateTime))) {
    // Step 10A's own DoD is "active ruleset + update time" -- see module
    // header, "WHY THE cloud.firestore ROW ALSO REQUIRES A VALID updateTime".
    return {
      status: "UNAVAILABLE",
      error: "cloud.firestore release has an invalid updateTime",
      data: { count: items.length, releases: items },
    };
  }
  return { status: "OK", data: { count: items.length, releases: items } };
}

/**
 * Backing services this project's OWN architecture proves it depends on App
 * Check to protect, beyond whatever `services.list` happens to return -- see
 * module header, "WHY APP CHECK ALSO CHECKS A NAMED LIST...".
 */
const APP_CHECK_INTENDED_ENFORCED_SERVICES = ["firestore.googleapis.com"];

async function checkAppCheck(
  deps: EnforcementStateDeps,
  token: string,
  deadlineAt: number,
): Promise<SectionResult> {
  const url = `https://firebaseappcheck.googleapis.com/v1/projects/${deps.project}/services`;
  // Needs the same quota-project header as Firestore Rules and Identity
  // Toolkit -- confirmed live during round 1 (a local `gcloud auth
  // print-access-token` call without it returns the identical
  // SERVICE_DISABLED/quota-project 403 App Check returns without it).
  const pages = await fetchAllPages(deps, token, url, "services", deadlineAt, {
    "X-Goog-User-Project": deps.project,
  });
  if (!pages.ok) return { status: "UNAVAILABLE", error: pages.error };
  // Deliberately NOT failing closed on zero services -- see this file's
  // module header. An empty list is a real, meaningful App Check state for
  // this project, not evidence the read itself failed.
  const rawItems = pages.items as Record<string, any>[];
  if (!everyRowHas(rawItems, ["name", "enforcementMode"])) {
    return {
      status: "UNAVAILABLE",
      error: "malformed response: one or more App Check service rows are missing "
        + "name/enforcementMode",
    };
  }
  const items = rawItems.map((s) => ({
    service: String(s.name).split("/").pop() as string,
    enforcementMode: s.enforcementMode as string,
    updateTime: s.updateTime ?? "?",
  }));
  // The real API's values are "ENFORCED" / "UNENFORCED" (confirmed live this
  // round) -- never "ON"/"OFF". See module header, "WHY APP CHECK NOW
  // COMPARES AGAINST 'ENFORCED'".
  const byService = new Map(items.map((i) => [i.service, i.enforcementMode]));
  const unenforcedIntendedServices = APP_CHECK_INTENDED_ENFORCED_SERVICES.filter(
    (svc) => byService.get(svc) !== "ENFORCED",
  );
  const anyEnforcementOff =
    items.some((i) => i.enforcementMode !== "ENFORCED") || unenforcedIntendedServices.length > 0;
  return {
    status: "OK",
    data: { count: items.length, services: items, anyEnforcementOff, unenforcedIntendedServices },
  };
}

/**
 * STRICT ALLOWLIST — see this file's module header. Never spread/pass the
 * raw response through; every field here was individually chosen as safe.
 */
function extractIdentityToolkitState(raw: Record<string, any>): Record<string, unknown> {
  const signInMethods = Object.keys(raw?.signIn ?? {}).filter((k) => k !== "hashConfig");
  return {
    signInMethodsConfigured: signInMethods,
    anonymousEnabled: raw?.signIn?.anonymous?.enabled ?? null,
    mfaState: raw?.mfa?.state ?? null,
    multiTenant: raw?.multiTenant ?? null,
    authorizedDomainsCount: Array.isArray(raw?.authorizedDomains)
      ? raw.authorizedDomains.length
      : null,
    smsRegionAllowlistOnly: raw?.smsRegionConfig?.allowlistOnly ?? null,
    emailPrivacyImproved: raw?.emailPrivacyConfig?.enableImprovedEmailPrivacy ?? null,
    monitoringRequestLogging: raw?.monitoring?.requestLogging ?? null,
    blockingFunctionsConfigured: !!raw?.blockingFunctions
      && Object.keys(raw.blockingFunctions).length > 0,
  };
}

async function checkIdentityToolkit(
  deps: EnforcementStateDeps,
  token: string,
  deadlineAt: number,
): Promise<SectionResult> {
  const remaining = deadlineAt - deps.now();
  if (remaining <= 0) {
    return {
      status: "UNAVAILABLE",
      error: "probe deadline exceeded before Identity Toolkit could be read",
    };
  }
  const timeoutMs = Math.max(1_000, Math.min(REQUEST_TIMEOUT_MS, remaining));
  const url = `https://identitytoolkit.googleapis.com/v2/projects/${deps.project}/config`;
  const res = await deps.fetchJson(
    url,
    token,
    { "X-Goog-User-Project": deps.project },
    timeoutMs,
  );
  if (!res.ok) {
    return { status: "UNAVAILABLE", error: `HTTP ${res.status}: ${res.errorText ?? ""}`.trim() };
  }
  if (res.json === null || typeof res.json !== "object") {
    return { status: "UNAVAILABLE", error: "malformed response: body is not a JSON object" };
  }
  const body = res.json as Record<string, any>;
  // A real config response always names its own resource; its absence is
  // the cheapest possible signal that something other than a real config
  // object came back (an empty `{}`, a differently-shaped error body that
  // still happened to carry a 2xx status, etc.).
  if (typeof body.name !== "string" || body.name.length === 0) {
    return { status: "UNAVAILABLE", error: "malformed response: missing config resource name" };
  }
  return { status: "OK", data: extractIdentityToolkitState(body) };
}

function overallStatus(sections: EnforcementStateResult["sections"]): OverallStatus {
  const values = Object.values(sections);
  const unavailable = values.filter((s) => s.status === "UNAVAILABLE").length;
  if (unavailable === 0) return "OK";
  if (unavailable === values.length) return "FAILED";
  return "DEGRADED";
}

export async function runEnforcementStateProbe(
  overrides: Partial<EnforcementStateDeps> = {},
): Promise<EnforcementStateResult> {
  const deps: EnforcementStateDeps = { ...realDeps(DEFAULT_PROJECT), ...overrides };
  const generatedAt = new Date().toISOString();
  // Started before token acquisition so that time counts against the budget
  // too -- see module header, "WHY THERE IS A WHOLE-PROBE DEADLINE".
  const deadlineAt = deps.now() + PROBE_BUDGET_MS;

  let token: string;
  try {
    const remaining = deadlineAt - deps.now();
    if (remaining <= 0) {
      throw new Error("probe deadline exceeded before token acquisition could complete");
    }
    // Raced against the SAME deadline, not a second timer -- see module
    // header, "WHY TOKEN ACQUISITION IS RACED AGAINST THE SAME DEADLINE".
    token = await deps.raceDeadline(deps.getAccessToken(), remaining, "token acquisition");
  } catch (e) {
    // No token at all -- every section is unreachable. Reported as FAILED,
    // not four separate identical error strings.
    const error = e instanceof Error ? e.message : String(e);
    const failed: SectionResult = { status: "UNAVAILABLE", error: `no access token: ${error}` };
    return {
      status: "FAILED",
      generatedAt,
      sections: {
        functions: failed,
        firestoreRules: failed,
        appCheck: failed,
        identityToolkit: failed,
      },
    };
  }

  const [functionsResult, firestoreRulesResult, appCheckResult, identityToolkitResult] =
    await Promise.all([
      checkFunctions(deps, token, deadlineAt).catch(
        (e): SectionResult => ({ status: "UNAVAILABLE", error: String(e) }),
      ),
      checkFirestoreRules(deps, token, deadlineAt).catch(
        (e): SectionResult => ({ status: "UNAVAILABLE", error: String(e) }),
      ),
      checkAppCheck(deps, token, deadlineAt).catch(
        (e): SectionResult => ({ status: "UNAVAILABLE", error: String(e) }),
      ),
      checkIdentityToolkit(deps, token, deadlineAt).catch(
        (e): SectionResult => ({ status: "UNAVAILABLE", error: String(e) }),
      ),
    ]);

  const sections = {
    functions: functionsResult,
    firestoreRules: firestoreRulesResult,
    appCheck: appCheckResult,
    identityToolkit: identityToolkitResult,
  };

  return { status: overallStatus(sections), generatedAt, sections };
}

// Exported for tests only -- not part of the module's real runtime seam.
export const _internal = { extractIdentityToolkitState, overallStatus };
