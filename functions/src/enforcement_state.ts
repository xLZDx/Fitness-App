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
 * + JSON fetcher); the real implementation (`realDeps`, used by the
 * production default) calls `google-auth-library` and the real REST APIs,
 * but every unit test injects a fake `deps` instead — same principle as
 * `canary_probe.ts`'s emulator-env-var detection: production code has no
 * test-only branch, tests substitute the actual seam.
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
) => Promise<JsonFetchResult>;

export type TokenGetter = () => Promise<string>;

export interface EnforcementStateDeps {
  project: string;
  getAccessToken: TokenGetter;
  fetchJson: JsonFetcher;
}

const DEFAULT_PROJECT = "fitness-app-korostelev";
const REQUEST_TIMEOUT_MS = 20_000;
const MAX_PAGES = 20;

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
): Promise<JsonFetchResult> {
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${token}`, ...extraHeaders },
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    return { ok: false, status: res.status, json: null, errorText: text.slice(0, 300) };
  }
  const json = await res.json();
  return { ok: true, status: res.status, json };
}

function realDeps(project: string): EnforcementStateDeps {
  return { project, getAccessToken: realGetAccessToken, fetchJson: realFetchJson };
}

/**
 * Fetches every page of a `{ [listKey]: T[], nextPageToken?: string }`-shaped
 * list endpoint, accumulating items across pages. Fails closed (returns
 * `ok: false`) on a non-2xx response, a non-object body, or a body whose
 * `listKey` is present but not an array -- see this file's module header
 * ("WHY A SECTION FAILS CLOSED...") for why a malformed 200 is not treated
 * as an empty success.
 */
async function fetchAllPages(
  deps: EnforcementStateDeps,
  token: string,
  baseUrl: string,
  listKey: string,
  extraHeaders?: Record<string, string>,
): Promise<{ ok: true; items: unknown[] } | { ok: false; error: string }> {
  const items: unknown[] = [];
  let pageToken: string | undefined;
  for (let page = 0; page < MAX_PAGES; page++) {
    const url = pageToken
      ? `${baseUrl}${baseUrl.includes("?") ? "&" : "?"}pageToken=${encodeURIComponent(pageToken)}`
      : baseUrl;
    const res = await deps.fetchJson(url, token, extraHeaders);
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
    const next = body.nextPageToken;
    if (typeof next === "string" && next.length > 0) {
      pageToken = next;
      continue;
    }
    return { ok: true, items };
  }
  return { ok: false, error: `pagination did not terminate within ${MAX_PAGES} pages` };
}

async function checkFunctions(deps: EnforcementStateDeps, token: string): Promise<SectionResult> {
  const url =
    `https://cloudfunctions.googleapis.com/v2/projects/${deps.project}` +
    `/locations/-/functions`;
  const pages = await fetchAllPages(deps, token, url, "functions");
  if (!pages.ok) return { status: "UNAVAILABLE", error: pages.error };
  if (pages.items.length === 0) {
    // This project always has deployed functions; a genuinely empty result
    // is far more likely to be a permission/API regression than reality.
    return { status: "UNAVAILABLE", error: "empty result: 0 functions returned" };
  }
  const items = pages.items.map((raw) => {
    const f = raw as Record<string, any>;
    return {
      name: String(f.name ?? "?").split("/").pop(),
      state: f.state ?? "?",
      environment: f.environment ?? "?",
      updateTime: f.updateTime ?? "?",
      revision: f.serviceConfig?.revision ?? "?",
    };
  });
  items.sort((a, b) => String(a.name).localeCompare(String(b.name)));
  return { status: "OK", data: { count: items.length, functions: items } };
}

async function checkFirestoreRules(
  deps: EnforcementStateDeps,
  token: string,
): Promise<SectionResult> {
  const url = `https://firebaserules.googleapis.com/v1/projects/${deps.project}/releases`;
  const pages = await fetchAllPages(deps, token, url, "releases", {
    "X-Goog-User-Project": deps.project,
  });
  if (!pages.ok) return { status: "UNAVAILABLE", error: pages.error };
  if (pages.items.length === 0) {
    // Same reasoning as Functions -- this project always has a published
    // ruleset (`production_manifest.py`'s own comment: "no releases
    // returned -- no ruleset is published" is itself a red flag there too).
    return { status: "UNAVAILABLE", error: "empty result: 0 rule releases returned" };
  }
  const items = pages.items.map((raw) => {
    const r = raw as Record<string, any>;
    return {
      release: String(r.name ?? "?").split("/").pop(),
      ruleset: String(r.rulesetName ?? "?").split("/").pop(),
      updateTime: r.updateTime ?? "?",
    };
  });
  return { status: "OK", data: { count: items.length, releases: items } };
}

async function checkAppCheck(deps: EnforcementStateDeps, token: string): Promise<SectionResult> {
  const url = `https://firebaseappcheck.googleapis.com/v1/projects/${deps.project}/services`;
  // Needs the same quota-project header as Firestore Rules and Identity
  // Toolkit -- confirmed live during this remediation round (a local
  // `gcloud auth print-access-token` call without it returns the identical
  // SERVICE_DISABLED/quota-project 403 App Check returns without it).
  const pages = await fetchAllPages(deps, token, url, "services", {
    "X-Goog-User-Project": deps.project,
  });
  if (!pages.ok) return { status: "UNAVAILABLE", error: pages.error };
  // Deliberately NOT failing closed on zero services -- see this file's
  // module header. An empty list is a real, meaningful App Check state for
  // this project, not evidence the read itself failed.
  const items = pages.items.map((raw) => {
    const s = raw as Record<string, any>;
    return {
      service: String(s.name ?? "?").split("/").pop(),
      enforcementMode: s.enforcementMode ?? "?",
      updateTime: s.updateTime ?? "?",
    };
  });
  const anyEnforcementOff = items.some((i) => i.enforcementMode === "OFF");
  return {
    status: "OK",
    data: { count: items.length, services: items, anyEnforcementOff },
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
): Promise<SectionResult> {
  const url = `https://identitytoolkit.googleapis.com/v2/projects/${deps.project}/config`;
  const res = await deps.fetchJson(url, token, { "X-Goog-User-Project": deps.project });
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

  let token: string;
  try {
    token = await deps.getAccessToken();
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
      checkFunctions(deps, token).catch(
        (e): SectionResult => ({ status: "UNAVAILABLE", error: String(e) }),
      ),
      checkFirestoreRules(deps, token).catch(
        (e): SectionResult => ({ status: "UNAVAILABLE", error: String(e) }),
      ),
      checkAppCheck(deps, token).catch(
        (e): SectionResult => ({ status: "UNAVAILABLE", error: String(e) }),
      ),
      checkIdentityToolkit(deps, token).catch(
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
