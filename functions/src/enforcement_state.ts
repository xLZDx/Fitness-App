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
 * question Cloud Scheduler's own execution history can answer instead of a
 * question about a human's memory.
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

async function checkFunctions(deps: EnforcementStateDeps, token: string): Promise<SectionResult> {
  const url =
    `https://cloudfunctions.googleapis.com/v2/projects/${deps.project}` +
    `/locations/-/functions`;
  const res = await deps.fetchJson(url, token);
  if (!res.ok) {
    return { status: "UNAVAILABLE", error: `HTTP ${res.status}: ${res.errorText ?? ""}`.trim() };
  }
  const body = res.json as { functions?: unknown[] } | null;
  const fns = Array.isArray(body?.functions) ? body!.functions : [];
  const items = fns.map((raw) => {
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
  const res = await deps.fetchJson(url, token, { "X-Goog-User-Project": deps.project });
  if (!res.ok) {
    return { status: "UNAVAILABLE", error: `HTTP ${res.status}: ${res.errorText ?? ""}`.trim() };
  }
  const body = res.json as { releases?: unknown[] } | null;
  const releases = Array.isArray(body?.releases) ? body!.releases : [];
  const items = releases.map((raw) => {
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
  const res = await deps.fetchJson(url, token);
  if (!res.ok) {
    return { status: "UNAVAILABLE", error: `HTTP ${res.status}: ${res.errorText ?? ""}`.trim() };
  }
  const body = res.json as { services?: unknown[] } | null;
  const services = Array.isArray(body?.services) ? body!.services : [];
  const items = services.map((raw) => {
    const s = raw as Record<string, any>;
    return {
      service: String(s.name ?? "?").split("/").pop(),
      enforcementMode: s.enforcementMode ?? "?",
      updateTime: s.updateTime ?? "?",
    };
  });
  return { status: "OK", data: { count: items.length, services: items } };
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
  const body = (res.json ?? {}) as Record<string, any>;
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
