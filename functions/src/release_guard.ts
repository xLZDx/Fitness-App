/**
 * MVP1.G4 Step 9 -- the AI Gateway release guard.
 *
 * GPT-PM's binding DoD (obtained during Step 8's own DoD question, since
 * neither Step 8 nor Step 9 had a stated DoD anywhere in this repo): a
 * FAIL-CLOSED release gate -- not a runtime control like Step 8's kill
 * switch -- that runs in the canonical release path, verifies the 4 expected
 * AI callables are the intended deployed set on `fn-ai-runtime`, verifies
 * App Check enforcement is on/fail-closed for all four, verifies anonymous
 * paid AI access stays refused, verifies the Step 8 kill switch exists and
 * its drill passed, verifies AI observability is present/producing, verifies
 * source/live provenance, and prevents an AI-enabled release while the S23
 * production Play Integrity proof is still open -- a deliberately
 * AI-disabled release may still ship even then.
 *
 * WHY THIS IS A STANDALONE MODULE, NOT A DEPLOYED CLOUD FUNCTION
 *
 * A release gate has to run BEFORE a release exists, on the releasing
 * operator/session's own `gcloud`/git session -- a deployed Cloud Function
 * cannot gate its own deployment. This mirrors `scripts/dev/
 * production_manifest.py`'s own established pattern (a human/CI-run script
 * reading live GCP state via `gcloud`), not `enforcement_state.ts`'s
 * scheduled-Cloud-Function pattern -- that file is post-release drift
 * detection, a genuinely different concern (see its own module header).
 *
 * WHY THE DEPS-INJECTION SEAM
 *
 * Same principle as `enforcement_state.ts`'s `EnforcementStateDeps`: the
 * default implementation shells out to real `gcloud`/`git` and reads real
 * files, but every unit test injects a fake `ReleaseGuardDeps` instead, so
 * every check's OK/FAILED/UNAVAILABLE branch is provably exercised without
 * live GCP credentials or any risk to real infrastructure.
 *
 * WHY EVERY CHECK FAILS CLOSED ON UNREADABLE EVIDENCE
 *
 * A `gcloud`/git command that errors, times out, or returns something this
 * code cannot parse is `UNAVAILABLE`, never silently treated as "the
 * invariant holds" -- the DoD's own first requirement. `UNAVAILABLE` blocks
 * the release exactly like `FAILED` does; the two exist as separate states
 * only so the guard's own output can tell an operator "this failed a real
 * check" apart from "this could not be checked at all."
 *
 * WHY THE S23 GATE READS THE KILL SWITCH'S LIVE STATE, NOT A SEPARATE FLAG
 *
 * The DoD's own carve-out -- "a deliberately AI-disabled release may still
 * ship" -- is already exactly what Step 8's kill switch encodes
 * (`ai-gateway-kill-switch`'s `enabled` field). Inventing a second,
 * independent "is this release AI-enabled" flag would be two sources of
 * truth for one fact; this guard reads the same secret Step 8 already made
 * authoritative.
 *
 * WHY THE S23 PROOF AND STEP-8-DRILL-PASSED FACTS COME FROM A COMMITTED FILE
 *
 * Neither is a live-queryable GCP fact -- "did the Step 8 drill's review
 * conclude APPROVE" and "has the S23 device attestation proof passed" are
 * process/human facts, exactly like every other decision this project
 * already records in `core/DECISION_LOG.md` and the per-step gate docs. This
 * guard needs ONE machine-readable anchor for them rather than parsing
 * prose, so `core/state/g4_release_evidence.json` is that anchor -- committed,
 * versioned, and updated by hand exactly when one of those facts actually
 * changes (see that file's own top-level comment... it's JSON, so the
 * comment lives here instead).
 *
 * ROUND 1 GPT-PM REVIEW: 4 MAJOR, all remediated below (see
 * `core/G4_STEP9_RELEASE_GUARD_2026-08-29.md` for the full round writeup):
 *
 * 1. The original 6 live-GCP checks (functions inventory, App Check,
 *    anonymous refusal, kill switch, drill evidence, observability) all read
 *    CURRENTLY DEPLOYED state -- correct for "is the environment the
 *    candidate is about to replace currently safe," but silent about the
 *    CANDIDATE itself: a commit that strips `enforceAppCheck` or deletes
 *    `enforceNonAnonymousForAi()`/`enforceAiGatewayEnabled()` would sail
 *    through unnoticed, because nothing checked the source about to be
 *    built. Fixed by `checkCandidateSourceInvariants` below -- a genuinely
 *    independent check reading the actual committed source files (not live
 *    GCP, not the compiled candidate, since predeploy's own first step
 *    already builds from this exact source) for the same invariants.
 * 2. `deps.project` was a hardcoded default with no binding to the ACTUAL
 *    Firebase deploy target -- `firebase deploy --project=<other-alias>`
 *    (this repo's `.firebaserc` genuinely has a second alias,
 *    `legacy-shared` -> an unrelated project) would have validated the
 *    WRONG project while Firebase deployed to the real one. Fixed:
 *    `run_release_guard.mjs` now reads `process.env.GCLOUD_PROJECT` first
 *    (the same env var `scaling.ts`'s own `projectId()` already reads, and
 *    the one Firebase's CLI sets for predeploy hooks), and
 *    `checkDeployTarget` below fails the whole gate outright if it resolves
 *    to anything other than this project's single real target.
 * 3. The kill-switch IAM check's write-role denylist omitted
 *    `roles/secretmanager.editor` (independently confirmed via `gcloud iam
 *    roles describe` to include `secretmanager.versions.add` -- exactly the
 *    permission that would let the runtime re-enable its own kill switch),
 *    and only inspected the SECRET's own IAM policy, missing an inherited
 *    PROJECT-level grant or a custom role carrying the same permission.
 *    Fixed: `checkKillSwitchExists` now unions secret-level and
 *    project-level role bindings for the runtime SA, and for any role not
 *    on the known-safe/known-dangerous lists, resolves its actual
 *    `includedPermissions` via `gcloud iam roles describe` rather than
 *    guessing from the name -- covers custom roles like this project's own
 *    `fitness.vertexPredictor` correctly (verified live: grants only
 *    `aiplatform.endpoints.predict`, nothing secret-related).
 * 4. The observability check's own doc comment claimed the 4 AI Gateway
 *    log-based metrics were "defined but not activated" -- stale: verified
 *    live (`gcloud logging metrics list`) that all 4
 *    (`ai_gateway_calls`/`_latency_ms`/`_quota_exhaustions`/
 *    `_total_tokens_per_call`) already exist as real GCP LogMetric
 *    resources. Fixed: the check now confirms those 4 resources exist
 *    (the actual "metrics are present" half of the DoD) in addition to the
 *    existing recent-log-event check (the "producing" half).
 *
 * ROUND 2 GPT-PM REVIEW: 3 more MAJOR, all remediated below (round 1's
 * fixes #2/deploy-target and the S23 proof both confirmed CLOSED, no
 * further change):
 *
 * 5. `checkCandidateSourceInvariants` (round 1's own fix) used substring/
 *    regex matching over raw source text -- a commented-out call
 *    (`// enforceNonAnonymousForAi(...)`) still satisfies `indexOf`, so the
 *    check could not actually distinguish "the guard runs" from "the guard
 *    is mentioned in a comment." Fixed: rewritten on the real TypeScript
 *    AST (`typescript`, already a project devDependency) -- it locates the
 *    actual exported callable's `onCall(AI_METERED, ...)` `CallExpression`,
 *    walks its handler body for genuine `CallExpression` nodes (which the
 *    parser never produces for comment text at all, closing this class of
 *    bypass structurally rather than by pattern-matching harder), and
 *    checks `AI_METERED`'s own `ObjectLiteralExpression` properties the
 *    same way.
 * 6. The kill-switch IAM check (round 1's own fix) still only treated
 *    direct `secretmanager.*` mutation permissions as dangerous -- a role
 *    granting `resourcemanager.projects.setIamPolicy` (independently
 *    confirmed via `gcloud iam roles describe
 *    roles/resourcemanager.projectIamAdmin` to include it) would let the
 *    runtime grant ITSELF a write-capable secret role and then mutate the
 *    switch, an indirect path the permission-name check never saw. Fixed:
 *    added `resourcemanager.projects.setIamPolicy` to the dangerous-
 *    permission list -- a role carrying it is now caught by the same
 *    resolve-and-check logic as a direct `secretmanager.*` write permission.
 * 7. Observability (round 1's own fix) proved the 4 metric RESOURCES exist
 *    but not that their FILTER/EXTRACTOR/LABELS still match the source
 *    definition -- a corrupted filter would leave the resource present and
 *    raw `ai_gateway: call` logs flowing while the metric itself silently
 *    stopped producing meaningful data. Fixed: reuses this project's own
 *    existing canonical-JSON builders
 *    (`aiGatewayCallsMetricJson`/`aiGatewayLatencyMetricJson`/
 *    `aiGatewayTokensMetricJson`/`aiGatewayQuotaExhaustionsMetricJson` in
 *    `./monitoring/ai_gateway_definitions`) -- the same mechanism Step 9B's
 *    own source==live SHA-256 verification already used
 *    (`core/evidence/step9b_live_readback_2026-08-27.json`) -- and compares
 *    each live metric's actual definition against it field-by-field, not
 *    just its name.
 *
 * ROUND 3 GPT-PM REVIEW: 3 more MAJOR, all remediated below (round 2's own
 * fixes #5/#6/#7 all confirmed CLOSED live, no further change):
 *
 * 8. `checkScalingAst`'s check on `APP_CHECK_ENFORCED_AI` (round 1's own
 *    fix) was still a loose regex over the initializer's raw text --
 *    `/envFlagFailClosed\(...\)/.test(initText)` only proves the call
 *    APPEARS somewhere in the text, not that it is the value the export
 *    actually evaluates to, so `envFlagFailClosed("APP_CHECK_ENFORCED_AI")
 *    && false` (fail-OPEN in truth) would have passed. Fixed: the check now
 *    verifies the exact real expression shape instead -- a `BinaryExpression`
 *    using `||`, whose left side is a `CallExpression` to the bare
 *    identifier `envFlagFailClosed` with exactly one string-literal argument
 *    equal to `"APP_CHECK_ENFORCED_AI"`, and whose right side is the bare
 *    identifier `APP_CHECK_ENFORCED` -- matching `scaling.ts`'s real source
 *    line for line.
 * 9. Every round so far verified only the CONSUMER reference
 *    (`AI_METERED.serviceAccount === RUNTIME_SA.aiRuntime`, a bare
 *    property-access shape match) and never the DEFINITION site -- a rewrite
 *    of `RUNTIME_SA.aiRuntime` itself to an empty string or a hardcoded
 *    wrong service account would have kept every earlier round's check
 *    green. Fixed: `checkRuntimeSaAiRuntime` now locates `RUNTIME_SA`'s own
 *    exported object literal (unwrapping the `as const` assertion the real
 *    source uses -- confirmed live this was necessary: the very first live
 *    run of this fix against the real `scaling.ts` failed with "RUNTIME_SA
 *    is not an exported object literal" until the unwrap was added) and
 *    verifies `aiRuntime`'s initializer is a template expression whose
 *    literal head/tail are exactly `fn-ai-runtime@` /
 *    `.iam.gserviceaccount.com`, with a genuine non-empty dynamic expression
 *    in between.
 * 10. Reachability/ordering: `checkCallableAst` (round 2's own fix) proves
 *     `enforceNonAnonymousForAi`/`enforceAiGatewayEnabled` exist as real
 *     `CallExpression` nodes somewhere in the handler subtree and checks
 *     their relative source-position order, but never proves those calls sit
 *     on the path the handler actually executes before doing paid work --
 *     e.g. both calls moved inside a dead `if (false)` branch, or after the
 *     real AI-generation call instead of before it, would satisfy a purely
 *     syntactic AST match. Rather than deepen the AST heuristic further
 *     (risking the same kind of arms race each of the last two rounds
 *     already produced -- CLAUDE.md §17's "one sweep, not one finding per
 *     round" spiral), this reuses `functions/src/__tests__/
 *     ai_coach_advice.test.ts`'s own existing, already-passing END-TO-END
 *     tests, which call the REAL exported `aiCoachAdvice.run()` handler with
 *     a real anonymous auth context and assert the real rejection ("an
 *     anonymous caller is refused before the quota is even checked") and the
 *     real kill-switch-first ordering ("refuses when the AI Gateway kill
 *     switch is off, before quota/generate" -- asserts `generate` was never
 *     called) -- proof against the ACTUAL wired-up control flow, which no
 *     syntactic AST match can provide. `firebase.json`'s `functions`
 *     "default" codebase `predeploy` array now runs `npm ... test` (the full
 *     Jest suite) between `build` and this guard script, so a regression in
 *     any of these behavioral tests blocks the release before the guard's
 *     own AST checks even run. The one gap no existing test covered --
 *     `AI_METERED.serviceAccount`'s actual resolved runtime VALUE, as
 *     opposed to its source-level shape -- got one new focused test
 *     (`scaling.test.ts`, "G4 Step 9 round 3: AI_METERED.serviceAccount
 *     resolves to the real fn-ai-runtime service account...").
 */

import * as ts from "typescript";
import {
  aiGatewayCallsMetricJson,
  aiGatewayLatencyMetricJson,
  aiGatewayTokensMetricJson,
  aiGatewayQuotaExhaustionsMetricJson,
} from "./monitoring/ai_gateway_definitions";

export type CheckStatus = "OK" | "FAILED" | "UNAVAILABLE";

export interface CheckResult {
  name: string;
  status: CheckStatus;
  detail: string;
}

export type Verdict = "PASS" | "BLOCK";

export interface ReleaseGuardResult {
  verdict: Verdict;
  generatedAt: string;
  checks: CheckResult[];
}

export interface CommandResult {
  ok: boolean;
  stdout: string;
  stderr: string;
}

export type CommandRunner = (
  cmd: string,
  args: string[],
  timeoutMs?: number,
) => Promise<CommandResult>;

/** Returns `null` when the file does not exist or cannot be read -- never throws. */
export type FileReader = (path: string) => Promise<string | null>;

export interface ReleaseGuardDeps {
  project: string;
  runCommand: CommandRunner;
  readFile: FileReader;
  now: () => number;
}

/** The exact 4 AI Gateway callables this gate covers -- see `abuse_guard.ts`'s own QUOTAS map. */
export const AI_CALLABLES = [
  "aiCoachAdvice",
  "aiEquipmentRecognition",
  "aiMachineDescription",
  "aiExerciseGeneration",
] as const;

export const AI_RUNTIME_SERVICE_ACCOUNT_LOCAL = "fn-ai-runtime";
export const KILL_SWITCH_SECRET_NAME = "ai-gateway-kill-switch";
export const RELEASE_EVIDENCE_PATH = "core/state/g4_release_evidence.json";

/** The single real Firebase project this guard is meaningful for -- see
 * `.firebaserc`, which also defines an unrelated `legacy-shared` alias. */
export const EXPECTED_PROJECT_ID = "fitness-app-korostelev";

/** Known-safe roles for the kill-switch secret -- skipped without further resolution. */
const KNOWN_SAFE_SECRET_ROLES = new Set([
  "roles/secretmanager.secretAccessor",
  "roles/secretmanager.viewer",
]);

/** Predefined roles that grant a documented ability to mutate the secret --
 * `roles/secretmanager.editor` independently confirmed (`gcloud iam roles
 * describe`) to include `secretmanager.versions.add`. */
const KNOWN_WRITE_CAPABLE_SECRET_ROLES = new Set([
  "roles/secretmanager.admin",
  "roles/secretmanager.editor",
  "roles/secretmanager.secretVersionManager",
  "roles/secretmanager.secretVersionAdder",
  "roles/owner",
  "roles/editor",
]);

/** Permissions that would let a caller re-enable, mutate, or reclaim control
 * of the kill switch -- checked against any role not already classified
 * above (a custom role, or a predefined role neither list names).
 * `resourcemanager.projects.setIamPolicy` is round 2's own fix: it does not
 * touch the secret directly, but independently confirmed
 * (`gcloud iam roles describe roles/resourcemanager.projectIamAdmin`) to
 * let its holder grant itself any other role -- including a write-capable
 * secret role -- so it is exactly as dangerous as holding one directly. */
const DANGEROUS_SECRET_PERMISSIONS = [
  "secretmanager.versions.add",
  "secretmanager.versions.enable",
  "secretmanager.versions.disable",
  "secretmanager.versions.destroy",
  "secretmanager.secrets.update",
  "secretmanager.secrets.setIamPolicy",
  "resourcemanager.projects.setIamPolicy",
];

/** Source files this guard reads directly (not compiled, not live GCP) to
 * prove the CANDIDATE about to be built still carries the invariants the
 * live checks above can only prove for the environment it is replacing. */
const AI_SOURCE_FILES: Record<(typeof AI_CALLABLES)[number], string> = {
  aiCoachAdvice: "functions/src/ai_coach_advice.ts",
  aiEquipmentRecognition: "functions/src/ai_equipment_recognition.ts",
  aiMachineDescription: "functions/src/ai_machine_description.ts",
  aiExerciseGeneration: "functions/src/ai_exercise_generation.ts",
};
const SCALING_SOURCE_FILE = "functions/src/scaling.ts";

interface ReleaseEvidence {
  step8KillSwitch?: { status?: unknown };
  s23PlayIntegrityProof?: { status?: unknown };
}

function tryParseJson<T>(text: string): T | undefined {
  try {
    return JSON.parse(text) as T;
  } catch {
    return undefined;
  }
}

async function loadEvidence(deps: ReleaseGuardDeps): Promise<ReleaseEvidence | undefined> {
  const raw = await deps.readFile(RELEASE_EVIDENCE_PATH);
  if (raw === null) return undefined;
  return tryParseJson<ReleaseEvidence>(raw);
}

async function runGcloudJson<T>(
  deps: ReleaseGuardDeps,
  args: string[],
): Promise<{ value: T } | { error: string }> {
  const res = await deps.runCommand("gcloud", [...args, "--format=json"], 30_000);
  if (!res.ok) return { error: res.stderr || "gcloud command failed" };
  const parsed = tryParseJson<T>(res.stdout);
  if (parsed === undefined) return { error: "gcloud returned unparseable JSON" };
  return { value: parsed };
}

interface GcloudFunctionSummary {
  name: string;
  serviceConfig?: { serviceAccountEmail?: string; environmentVariables?: Record<string, string> };
}

/**
 * Fetched once and shared by the App-Check and anonymous-refusal checks
 * below. `gcloud functions describe <name>` alone resolves against a
 * default region (`us-central1`) that this project does not deploy to --
 * confirmed live (`404 ... locations/us-central1/functions/aiCoachAdvice`)
 * before this region-discovery step existed. Each callable's real region is
 * read from `functions list`'s own full resource name
 * (`projects/P/locations/REGION/functions/NAME`) rather than hardcoded, so
 * this does not silently break if these functions ever move region.
 */
async function describeAiFunctions(
  deps: ReleaseGuardDeps,
): Promise<{ byName: Map<string, GcloudFunctionSummary> } | { error: string }> {
  const listResult = await runGcloudJson<GcloudFunctionSummary[]>(deps, [
    "functions",
    "list",
    "--v2",
    `--project=${deps.project}`,
  ]);
  if ("error" in listResult) return { error: `listing functions to discover region: ${listResult.error}` };
  if (!Array.isArray(listResult.value)) {
    return { error: "functions list did not return an array while discovering region" };
  }
  const regionByName = new Map<string, string>();
  for (const f of listResult.value) {
    const match = /\/locations\/([^/]+)\/functions\/([^/]+)$/.exec(f.name);
    if (match) regionByName.set(match[2], match[1]);
  }

  const byName = new Map<string, GcloudFunctionSummary>();
  for (const name of AI_CALLABLES) {
    const region = regionByName.get(name);
    if (!region) return { error: `${name} not found in functions list -- cannot determine its region` };
    const result = await runGcloudJson<GcloudFunctionSummary>(deps, [
      "functions",
      "describe",
      name,
      "--v2",
      `--region=${region}`,
      `--project=${deps.project}`,
    ]);
    if ("error" in result) return { error: `describing ${name}: ${result.error}` };
    byName.set(name, result.value);
  }
  return { byName };
}

/** Fails outright if the resolved deploy target is not this project's one
 * real Firebase project -- every other check below is meaningless (or
 * silently checks the wrong project) if this one is wrong. See
 * `run_release_guard.mjs` for how `deps.project` is derived from
 * `GCLOUD_PROJECT`. */
async function checkDeployTarget(deps: ReleaseGuardDeps): Promise<CheckResult> {
  const name = "Deploy target is this project's real Firebase project";
  if (deps.project !== EXPECTED_PROJECT_ID) {
    return {
      name,
      status: "FAILED",
      detail: `resolved project is "${deps.project}", expected "${EXPECTED_PROJECT_ID}" -- every other check below would validate the wrong project`,
    };
  }
  return { name, status: "OK", detail: `project = ${EXPECTED_PROJECT_ID}` };
}

async function checkFunctionsInventory(deps: ReleaseGuardDeps): Promise<CheckResult> {
  const name = "AI callables match the intended fn-ai-runtime deployed set";
  const result = await runGcloudJson<GcloudFunctionSummary[]>(deps, [
    "functions",
    "list",
    "--v2",
    `--project=${deps.project}`,
  ]);
  if ("error" in result) return { name, status: "UNAVAILABLE", detail: result.error };
  if (!Array.isArray(result.value)) {
    return { name, status: "UNAVAILABLE", detail: "functions list did not return an array" };
  }
  const runtimeSa = `${AI_RUNTIME_SERVICE_ACCOUNT_LOCAL}@${deps.project}.iam.gserviceaccount.com`;
  const deployed = result.value
    .filter((f) => f.serviceConfig?.serviceAccountEmail === runtimeSa)
    .map((f) => f.name.split("/functions/").pop() ?? f.name)
    .sort();
  const expected: string[] = [...AI_CALLABLES].sort();
  const missing = expected.filter((n) => !deployed.includes(n));
  const extra = deployed.filter((n) => !expected.includes(n));
  if (missing.length > 0 || extra.length > 0) {
    return {
      name,
      status: "FAILED",
      detail: `missing=[${missing.join(",")}] extra=[${extra.join(",")}] on ${runtimeSa}`,
    };
  }
  return { name, status: "OK", detail: `all 4 callables, exactly, run as ${runtimeSa}` };
}

/**
 * Mirrors `scaling.ts`'s own `envFlagFailClosed("APP_CHECK_ENFORCED_AI") ||
 * APP_CHECK_ENFORCED` formula exactly -- the deployed raw env vars are the
 * bake-time inputs to that computed boolean, so this reads the same two
 * strings the source formula reads and applies the identical logic.
 */
function appCheckEnforced(env: Record<string, string> | undefined): boolean {
  const rawAi = env?.["APP_CHECK_ENFORCED_AI"];
  const rawGeneral = env?.["APP_CHECK_ENFORCED"];
  return rawAi !== "false" || rawGeneral === "true";
}

async function checkAppCheckEnforcement(
  described: { byName: Map<string, GcloudFunctionSummary> },
): Promise<CheckResult> {
  const name = "App Check enforcement is on (fail-closed) for all 4 AI callables";
  const unenforced: string[] = [];
  for (const callable of AI_CALLABLES) {
    const env = described.byName.get(callable)?.serviceConfig?.environmentVariables;
    if (!appCheckEnforced(env)) unenforced.push(callable);
  }
  if (unenforced.length > 0) {
    return { name, status: "FAILED", detail: `unenforced: ${unenforced.join(", ")}` };
  }
  return { name, status: "OK", detail: "APP_CHECK_ENFORCED_AI is not the literal string \"false\" on any of the 4 (fail-closed default holds)" };
}

async function checkAnonymousRefused(
  described: { byName: Map<string, GcloudFunctionSummary> },
): Promise<CheckResult> {
  const name = "Anonymous callers are refused on all 4 AI callables";
  const allowed: string[] = [];
  for (const callable of AI_CALLABLES) {
    const env = described.byName.get(callable)?.serviceConfig?.environmentVariables;
    if (env?.["AI_ALLOW_ANONYMOUS"] === "true") allowed.push(callable);
  }
  if (allowed.length > 0) {
    return { name, status: "FAILED", detail: `AI_ALLOW_ANONYMOUS=true on: ${allowed.join(", ")}` };
  }
  return { name, status: "OK", detail: "AI_ALLOW_ANONYMOUS is not \"true\" on any of the 4" };
}

interface IamBinding {
  role: string;
  members: string[];
}
interface IamPolicy {
  bindings?: IamBinding[];
}

/** Resolves a role's actual `includedPermissions` -- a custom project role
 * (`projects/P/roles/R`) needs `--project=`; a predefined role (`roles/R`)
 * does not. Used for any role not already on the known-safe/known-dangerous
 * lists, so an unrecognized custom role is verified, not assumed safe. */
async function describeRolePermissions(
  deps: ReleaseGuardDeps,
  role: string,
): Promise<{ value: string[] } | { error: string }> {
  const customMatch = /^projects\/([^/]+)\/roles\/(.+)$/.exec(role);
  const args = customMatch
    ? ["iam", "roles", "describe", customMatch[2], `--project=${customMatch[1]}`]
    : ["iam", "roles", "describe", role];
  const result = await runGcloudJson<{ includedPermissions?: string[] }>(deps, args);
  if ("error" in result) return { error: result.error };
  return { value: result.value.includedPermissions ?? [] };
}

async function checkKillSwitchExists(deps: ReleaseGuardDeps): Promise<CheckResult> {
  const name = "Step 8 kill switch secret exists with genuinely read-only runtime IAM";
  const describeResult = await runGcloudJson<{ name?: string }>(deps, [
    "secrets",
    "describe",
    KILL_SWITCH_SECRET_NAME,
    `--project=${deps.project}`,
  ]);
  if ("error" in describeResult) {
    return { name, status: "UNAVAILABLE", detail: `secret describe: ${describeResult.error}` };
  }
  const secretPolicyResult = await runGcloudJson<IamPolicy>(deps, [
    "secrets",
    "get-iam-policy",
    KILL_SWITCH_SECRET_NAME,
    `--project=${deps.project}`,
  ]);
  if ("error" in secretPolicyResult) {
    return { name, status: "UNAVAILABLE", detail: `secret IAM policy: ${secretPolicyResult.error}` };
  }
  const projectPolicyResult = await runGcloudJson<IamPolicy>(deps, [
    "projects",
    "get-iam-policy",
    deps.project,
  ]);
  if ("error" in projectPolicyResult) {
    return { name, status: "UNAVAILABLE", detail: `project IAM policy: ${projectPolicyResult.error}` };
  }

  const runtimeMember = `serviceAccount:${AI_RUNTIME_SERVICE_ACCOUNT_LOCAL}@${deps.project}.iam.gserviceaccount.com`;
  const secretRoles = (secretPolicyResult.value.bindings ?? [])
    .filter((b) => b.members.includes(runtimeMember))
    .map((b) => b.role);
  const projectRoles = (projectPolicyResult.value.bindings ?? [])
    .filter((b) => b.members.includes(runtimeMember))
    .map((b) => b.role);

  if (!secretRoles.includes("roles/secretmanager.secretAccessor")) {
    return { name, status: "FAILED", detail: `fn-ai-runtime lacks roles/secretmanager.secretAccessor -- the runtime could not even read the switch` };
  }

  // Resource-level AND inherited project-level bindings both count -- a
  // role granted at the project scope is just as effective against this
  // secret as one bound directly to it.
  const allRoles = [...new Set([...secretRoles, ...projectRoles])];
  for (const role of allRoles) {
    if (KNOWN_SAFE_SECRET_ROLES.has(role)) continue;
    if (KNOWN_WRITE_CAPABLE_SECRET_ROLES.has(role)) {
      return {
        name,
        status: "FAILED",
        detail: `fn-ai-runtime holds write-capable role ${role} (secret- or project-level) -- the runtime could mutate its own kill switch`,
      };
    }
    // Not on either list -- a custom role or an unlisted predefined role.
    // Resolve its real permissions rather than guess from its name.
    const permsResult = await describeRolePermissions(deps, role);
    if ("error" in permsResult) {
      return { name, status: "UNAVAILABLE", detail: `could not resolve permissions for role ${role}: ${permsResult.error}` };
    }
    const dangerous = permsResult.value.filter((p) => DANGEROUS_SECRET_PERMISSIONS.includes(p));
    if (dangerous.length > 0) {
      return {
        name,
        status: "FAILED",
        detail: `fn-ai-runtime holds role ${role}, which grants ${dangerous.join(", ")} -- the runtime could mutate its own kill switch`,
      };
    }
  }
  return {
    name,
    status: "OK",
    detail: `secret- and project-level IAM checked (${allRoles.length} role(s) resolved): fn-ai-runtime holds only read/unrelated roles, no resolved write permission on secret versions`,
  };
}

async function checkStep8DrillEvidence(evidence: ReleaseEvidence | undefined): Promise<CheckResult> {
  const name = "Step 8 kill-switch drill evidence recorded as closed";
  if (evidence === undefined) {
    return { name, status: "UNAVAILABLE", detail: `${RELEASE_EVIDENCE_PATH} missing or unparseable` };
  }
  if (evidence.step8KillSwitch?.status !== "closed") {
    return { name, status: "FAILED", detail: `step8KillSwitch.status = ${JSON.stringify(evidence.step8KillSwitch?.status)}, expected "closed"` };
  }
  return { name, status: "OK", detail: "step8KillSwitch.status = \"closed\"" };
}

/** The 4 AI Gateway log-based metrics `functions/src/monitoring/
 * ai_gateway_definitions.ts` defines, paired with the canonical-JSON builder
 * that already exists for each -- the exact mechanism Step 9B's own
 * source==live SHA-256 verification used
 * (`core/evidence/step9b_live_readback_2026-08-27.json`), reused here rather
 * than reinvented. Round-1 GPT-PM review found these already exist as real
 * GCP LogMetric resources (contradicting this file's own earlier "defined
 * but not activated" claim); round-2 found resource EXISTENCE alone does
 * not prove the live filter/extractor/labels still match source -- a
 * corrupted definition could leave the resource present and raw log lines
 * flowing while the metric itself silently stopped producing meaningful
 * data. */
const AI_GATEWAY_METRIC_BUILDERS: Record<string, () => object> = {
  ai_gateway_calls: aiGatewayCallsMetricJson,
  ai_gateway_latency_ms: aiGatewayLatencyMetricJson,
  ai_gateway_quota_exhaustions: aiGatewayQuotaExhaustionsMetricJson,
  ai_gateway_total_tokens_per_call: aiGatewayTokensMetricJson,
};

interface LiveMetricLabel {
  key?: string;
  description?: string;
}
interface LiveMetric {
  name?: string;
  description?: string;
  filter?: string;
  labelExtractors?: Record<string, string>;
  valueExtractor?: string;
  bucketOptions?: unknown;
  metricDescriptor?: {
    metricKind?: string;
    valueType?: string;
    labels?: LiveMetricLabel[];
  };
}

/** Keeps only the fields the canonical builders produce -- live `gcloud
 * logging metrics describe` output also carries GCP-populated fields
 * (`createTime`, `updateTime`, `resourceName`, `metricDescriptor.name`,
 * `metricDescriptor.type`, `metricDescriptor.unit`) that have no source-side
 * counterpart to compare against, confirmed live before writing this.
 *
 * `labels` is sorted by `key` before comparing -- confirmed live (a direct
 * `ai_gateway_latency_ms` describe vs. its own canonical JSON) that GCP does
 * NOT preserve declaration order for a LogMetric's label array: the counter
 * metrics happened to come back in source order, but both distribution
 * metrics came back reversed (`[outcome, operation]` live vs.
 * `[operation, outcome]` source) with the filter/labelExtractors/
 * valueExtractor/bucketOptions all otherwise byte-identical. `labels` is
 * semantically a SET of {key, description} pairs, not a sequence -- treating
 * it as order-sensitive was this check's own bug, not a real drift. */
function canonicalMetricSubset(m: LiveMetric): object {
  const sortedLabels = (m.metricDescriptor?.labels ?? [])
    .map((l) => ({ key: l.key, description: l.description }))
    .sort((a, b) => (a.key ?? "").localeCompare(b.key ?? ""));
  const out: Record<string, unknown> = {
    name: m.name,
    description: m.description,
    filter: m.filter,
    metricDescriptor: {
      metricKind: m.metricDescriptor?.metricKind,
      valueType: m.metricDescriptor?.valueType,
      labels: sortedLabels,
    },
    labelExtractors: m.labelExtractors,
  };
  if (m.valueExtractor !== undefined) out.valueExtractor = m.valueExtractor;
  if (m.bucketOptions !== undefined) out.bucketOptions = m.bucketOptions;
  return out;
}

async function checkAiObservability(deps: ReleaseGuardDeps): Promise<CheckResult> {
  const name = "AI Gateway observability metrics exist, match source, and are producing";
  const problems: string[] = [];

  for (const [metricName, buildCanonical] of Object.entries(AI_GATEWAY_METRIC_BUILDERS)) {
    const result = await runGcloudJson<LiveMetric>(deps, [
      "logging",
      "metrics",
      "describe",
      metricName,
      `--project=${deps.project}`,
    ]);
    if ("error" in result) {
      return { name, status: "UNAVAILABLE", detail: `describing ${metricName}: ${result.error}` };
    }
    const liveSubset = JSON.stringify(canonicalMetricSubset(result.value));
    const canonicalSubset = JSON.stringify(canonicalMetricSubset(buildCanonical() as LiveMetric));
    if (liveSubset !== canonicalSubset) {
      problems.push(`${metricName}: live definition no longer matches the source-controlled definition (filter/extractor/labels drift)`);
    }
  }
  if (problems.length > 0) {
    return { name, status: "FAILED", detail: problems.join("; ") };
  }

  const res = await deps.runCommand(
    "gcloud",
    [
      "logging",
      "read",
      'jsonPayload.message="ai_gateway: call"',
      `--project=${deps.project}`,
      "--freshness=30d",
      "--limit=1",
      "--format=json",
    ],
    30_000,
  );
  if (!res.ok) return { name, status: "UNAVAILABLE", detail: res.stderr || "gcloud logging read failed" };
  const parsed = tryParseJson<unknown[]>(res.stdout);
  if (!Array.isArray(parsed)) {
    return { name, status: "UNAVAILABLE", detail: "gcloud logging read returned unparseable JSON" };
  }
  if (parsed.length === 0) {
    return { name, status: "FAILED", detail: `all 4 metric definitions verified against source, but no "ai_gateway: call" log entry in the last 30 days (not producing)` };
  }
  return { name, status: "OK", detail: `all 4 AI Gateway metric definitions verified byte-for-byte against source, and at least one real ai_gateway: call event in the last 30 days` };
}

interface KillSwitchPayload {
  enabled?: unknown;
}

async function checkS23Gate(
  deps: ReleaseGuardDeps,
  evidence: ReleaseEvidence | undefined,
): Promise<CheckResult> {
  const name = "S23 production Play Integrity proof gates an AI-enabled release";
  const res = await deps.runCommand(
    "gcloud",
    [
      "secrets",
      "versions",
      "access",
      "latest",
      `--secret=${KILL_SWITCH_SECRET_NAME}`,
      `--project=${deps.project}`,
    ],
    30_000,
  );
  if (!res.ok) {
    return { name, status: "UNAVAILABLE", detail: `could not read live kill-switch state: ${res.stderr}` };
  }
  const payload = tryParseJson<KillSwitchPayload>(res.stdout);
  if (payload === undefined) {
    return { name, status: "UNAVAILABLE", detail: "kill-switch secret payload is not valid JSON" };
  }
  const aiEnabled = payload.enabled === true;
  if (!aiEnabled) {
    return { name, status: "OK", detail: "kill switch is currently disabled -- a deliberately AI-disabled release may ship regardless of S23 status" };
  }
  if (evidence === undefined) {
    return { name, status: "UNAVAILABLE", detail: `${RELEASE_EVIDENCE_PATH} missing or unparseable, and the release is AI-enabled` };
  }
  if (evidence.s23PlayIntegrityProof?.status !== "closed") {
    return {
      name,
      status: "FAILED",
      detail: `kill switch is enabled (AI-enabled release), but s23PlayIntegrityProof.status = ${JSON.stringify(evidence.s23PlayIntegrityProof?.status)}, not "closed"`,
    };
  }
  return { name, status: "OK", detail: "kill switch is enabled and s23PlayIntegrityProof.status = \"closed\"" };
}

function parseTs(fileName: string, text: string): ts.SourceFile {
  return ts.createSourceFile(fileName, text, ts.ScriptTarget.Latest, true);
}

/** Finds the initializer of `export const <exportName> = ...` anywhere in
 * the file -- the only shape this codebase's exported constants use. */
function findExportedConstInit(sf: ts.SourceFile, exportName: string): ts.Expression | undefined {
  let found: ts.Expression | undefined;
  const visit = (node: ts.Node): void => {
    if (found) return;
    if (ts.isVariableStatement(node) && node.modifiers?.some((m) => m.kind === ts.SyntaxKind.ExportKeyword)) {
      for (const decl of node.declarationList.declarations) {
        if (ts.isIdentifier(decl.name) && decl.name.text === exportName && decl.initializer) {
          found = decl.initializer;
        }
      }
    }
    if (!found) ts.forEachChild(node, visit);
  };
  visit(sf);
  return found;
}

/** Collects every real `CallExpression` node whose callee is the bare
 * identifier `calleeName`, anywhere within `root` -- a genuine AST walk, so
 * a call mentioned only in a comment or a string literal is invisible to
 * it (the parser never produces a node for comment text at all). This is
 * what round-2 GPT-PM review required in place of round-1's substring/regex
 * matching, which a commented-out call could satisfy without the guard it
 * mentions actually running. */
function findCallExpressions(root: ts.Node, calleeName: string): ts.CallExpression[] {
  const found: ts.CallExpression[] = [];
  const visit = (node: ts.Node): void => {
    if (ts.isCallExpression(node) && ts.isIdentifier(node.expression) && node.expression.text === calleeName) {
      found.push(node);
    }
    ts.forEachChild(node, visit);
  };
  visit(root);
  return found;
}

/** Strips `as const` / `as <Type>` assertions and redundant parentheses so
 * an object-literal check still recognizes `{ ... } as const` -- the real
 * shape `RUNTIME_SA` uses in `scaling.ts` -- as the object literal it wraps,
 * rather than reporting it as missing. Confirmed live: without this, the
 * guard failed against the REAL source it is meant to verify. */
function unwrapExpression(node: ts.Expression): ts.Expression {
  let current = node;
  while (ts.isAsExpression(current) || ts.isParenthesizedExpression(current)) {
    current = ts.isAsExpression(current) ? current.expression : current.expression;
  }
  return current;
}

/** Finds a plain `key: value` property on an object literal by name --
 * shorthand and computed properties are deliberately not matched, since
 * every real property this file inspects (`RUNTIME_SA.aiRuntime`,
 * `AI_METERED.enforceAppCheck`/`.serviceAccount`) is written as an explicit
 * `PropertyAssignment` in this codebase. */
function findObjectLiteralProperty(obj: ts.ObjectLiteralExpression, propName: string): ts.Expression | undefined {
  for (const prop of obj.properties) {
    if (ts.isPropertyAssignment(prop) && ts.isIdentifier(prop.name) && prop.name.text === propName) {
      return prop.initializer;
    }
  }
  return undefined;
}

/** Round-3 GPT-PM MAJOR 1 (part B): round 1/2's check only verified the
 * CONSUMER reference (`AI_METERED.serviceAccount === RUNTIME_SA.aiRuntime`,
 * a bare property-access match) -- it never looked at what `RUNTIME_SA.
 * aiRuntime` itself actually resolves to. A rewrite of `RUNTIME_SA` to
 * `{ aiRuntime: "" }` or a hardcoded wrong service account would have kept
 * that earlier check green. This verifies the DEFINITION site: `RUNTIME_SA`
 * is a real exported object literal, `aiRuntime` is a template expression
 * whose literal head/tail are exactly `fn-ai-runtime@` /
 * `.iam.gserviceaccount.com` (the real source shape in `scaling.ts`), with a
 * genuine (non-empty) dynamic project-id expression in between -- so neither
 * a static wrong string nor an empty placeholder can pass. */
function checkRuntimeSaAiRuntime(sf: ts.SourceFile, path: string, problems: string[]): void {
  const runtimeSaInit = findExportedConstInit(sf, "RUNTIME_SA");
  const runtimeSa = runtimeSaInit ? unwrapExpression(runtimeSaInit) : undefined;
  if (!runtimeSa || !ts.isObjectLiteralExpression(runtimeSa)) {
    problems.push(`${path}: RUNTIME_SA is not an exported object literal (or is missing)`);
    return;
  }
  const aiRuntime = findObjectLiteralProperty(runtimeSa, "aiRuntime");
  if (
    !aiRuntime ||
    !ts.isTemplateExpression(aiRuntime) ||
    aiRuntime.head.text !== "fn-ai-runtime@" ||
    aiRuntime.templateSpans.length !== 1 ||
    aiRuntime.templateSpans[0].literal.text !== ".iam.gserviceaccount.com" ||
    aiRuntime.templateSpans[0].expression.getText(sf).trim().length === 0
  ) {
    problems.push(`${path}: RUNTIME_SA.aiRuntime does not resolve to a real fn-ai-runtime@<project>.iam.gserviceaccount.com template (definition-site check)`);
  }
}

function checkScalingAst(text: string, path: string, problems: string[]): void {
  const sf = parseTs(path, text);
  const aiMetered = findExportedConstInit(sf, "AI_METERED");
  if (!aiMetered || !ts.isObjectLiteralExpression(aiMetered)) {
    problems.push(`${path}: AI_METERED is not an exported object literal (or is missing)`);
  } else {
    let enforceAppCheckOk = false;
    let serviceAccountOk = false;
    for (const prop of aiMetered.properties) {
      if (!ts.isPropertyAssignment(prop) || !ts.isIdentifier(prop.name)) continue;
      if (
        prop.name.text === "enforceAppCheck" &&
        ts.isIdentifier(prop.initializer) &&
        prop.initializer.text === "APP_CHECK_ENFORCED_AI"
      ) {
        enforceAppCheckOk = true;
      }
      if (
        prop.name.text === "serviceAccount" &&
        ts.isPropertyAccessExpression(prop.initializer) &&
        ts.isIdentifier(prop.initializer.expression) &&
        prop.initializer.expression.text === "RUNTIME_SA" &&
        prop.initializer.name.text === "aiRuntime"
      ) {
        serviceAccountOk = true;
      }
    }
    if (!enforceAppCheckOk) problems.push(`${path}: AI_METERED.enforceAppCheck is not wired to APP_CHECK_ENFORCED_AI (real property assignment not found)`);
    if (!serviceAccountOk) problems.push(`${path}: AI_METERED.serviceAccount is not wired to RUNTIME_SA.aiRuntime (real property assignment not found)`);
  }

  checkRuntimeSaAiRuntime(sf, path, problems);

  /**
   * Round-3 GPT-PM MAJOR 1 (part A): round 1's check only did a loose
   * substring/regex match on `APP_CHECK_ENFORCED_AI`'s initializer text
   * (`/envFlagFailClosed\(...\)/.test(initText)`) -- so
   * `envFlagFailClosed("APP_CHECK_ENFORCED_AI") && false` would have PASSED
   * (the regex only checks the call is present somewhere in the text, not
   * that it is the actual value the export evaluates to). This verifies the
   * exact real shape instead: a `BinaryExpression` using `||`, whose LEFT
   * side is a `CallExpression` to the bare identifier `envFlagFailClosed`
   * with exactly one string-literal argument equal to
   * `"APP_CHECK_ENFORCED_AI"`, and whose RIGHT side is the bare identifier
   * `APP_CHECK_ENFORCED` -- the real source shape in `scaling.ts`.
   */
  const appCheckEnforcedAi = findExportedConstInit(sf, "APP_CHECK_ENFORCED_AI");
  let failClosedOk = false;
  if (
    appCheckEnforcedAi &&
    ts.isBinaryExpression(appCheckEnforcedAi) &&
    appCheckEnforcedAi.operatorToken.kind === ts.SyntaxKind.BarBarToken
  ) {
    const left = appCheckEnforcedAi.left;
    const right = appCheckEnforcedAi.right;
    const leftOk =
      ts.isCallExpression(left) &&
      ts.isIdentifier(left.expression) &&
      left.expression.text === "envFlagFailClosed" &&
      left.arguments.length === 1 &&
      ts.isStringLiteral(left.arguments[0]) &&
      left.arguments[0].text === "APP_CHECK_ENFORCED_AI";
    const rightOk = ts.isIdentifier(right) && right.text === "APP_CHECK_ENFORCED";
    failClosedOk = leftOk && rightOk;
  }
  if (!failClosedOk) {
    problems.push(`${path}: APP_CHECK_ENFORCED_AI is not exactly envFlagFailClosed("APP_CHECK_ENFORCED_AI") || APP_CHECK_ENFORCED (exact expression-shape check)`);
  }
}

function checkCallableAst(text: string, path: string, callable: string, problems: string[]): void {
  const sf = parseTs(path, text);
  const init = findExportedConstInit(sf, callable);
  if (!init || !ts.isCallExpression(init) || !ts.isIdentifier(init.expression) || init.expression.text !== "onCall") {
    problems.push(`${path}: ${callable} is not exported as a real onCall(...) CallExpression`);
    return;
  }
  const firstArg = init.arguments[0];
  if (!firstArg || !ts.isIdentifier(firstArg) || firstArg.text !== "AI_METERED") {
    problems.push(`${path}: ${callable} no longer declared as onCall(AI_METERED, ...)`);
  }
  const handler = init.arguments[1];
  if (!handler || !(ts.isArrowFunction(handler) || ts.isFunctionExpression(handler))) {
    problems.push(`${path}: ${callable}'s onCall(...) has no recognizable handler function to inspect`);
    return;
  }
  const anonCalls = findCallExpressions(handler, "enforceNonAnonymousForAi");
  const gatewayCalls = findCallExpressions(handler, "enforceAiGatewayEnabled");
  if (anonCalls.length === 0) {
    problems.push(`${path}: ${callable} -- no real enforceNonAnonymousForAi(...) call in the handler body`);
  }
  if (gatewayCalls.length === 0) {
    problems.push(`${path}: ${callable} -- no real enforceAiGatewayEnabled(...) call in the handler body`);
  }
  if (anonCalls.length > 0 && gatewayCalls.length > 0 && gatewayCalls[0].getStart() < anonCalls[0].getStart()) {
    problems.push(`${path}: ${callable} -- enforceAiGatewayEnabled(...) runs before enforceNonAnonymousForAi(...) -- ordering regression`);
  }
}

/** Proves the CANDIDATE about to be built and deployed still carries its own
 * safety invariants -- independent of every live-GCP check above, which can
 * only speak to the environment the candidate is about to REPLACE. Reads
 * the actual committed source (predeploy's own prior step already builds
 * from this exact tree) and parses it with the real TypeScript compiler
 * (round 2's fix -- round 1's own substring/regex version could be
 * satisfied by a commented-out call, since it never distinguished real code
 * from comment text). */
async function checkCandidateSourceInvariants(deps: ReleaseGuardDeps): Promise<CheckResult> {
  const name = "Candidate source still carries its App Check / anonymous-refusal / gateway-guard wiring (AST-verified)";
  const problems: string[] = [];

  const scaling = await deps.readFile(SCALING_SOURCE_FILE);
  if (scaling === null) {
    return { name, status: "UNAVAILABLE", detail: `could not read ${SCALING_SOURCE_FILE}` };
  }
  checkScalingAst(scaling, SCALING_SOURCE_FILE, problems);

  for (const callable of AI_CALLABLES) {
    const path = AI_SOURCE_FILES[callable];
    const src = await deps.readFile(path);
    if (src === null) {
      problems.push(`${path}: file missing`);
      continue;
    }
    checkCallableAst(src, path, callable, problems);
  }

  if (problems.length > 0) {
    return { name, status: "FAILED", detail: problems.join("; ") };
  }
  return {
    name,
    status: "OK",
    detail: "AST-verified: AI_METERED wiring, all 4 callables' onCall(AI_METERED, ...) declarations, and real enforceNonAnonymousForAi/enforceAiGatewayEnabled CallExpression nodes are all present in the candidate source (not merely mentioned in a comment)",
  };
}

/**
 * The paths this guard's own provenance claim actually depends on.
 * Deliberately NOT the whole repository -- this is a multi-purpose
 * monorepo-style checkout (`mobile/`, `reports/`, other `core/*.md` docs
 * unrelated to this release) where unrelated untracked debris is routine
 * and has zero bearing on what a `firebase deploy` of this project's
 * Functions actually uploads. Round-5 GPT-PM review found the first attempt
 * at this list incomplete on 3 counts, all fixed here:
 *
 * - `functions` -- the "default"/AI codebase this guard itself is wired
 *   into (source, tests, and the compiled `predeploy` scripts all live
 *   under it).
 * - `functions-equipment-identity` -- `firebase.json`'s SECOND, independent
 *   Functions codebase. `firebase deploy --only functions` (no per-function
 *   filter) deploys every configured codebase in one invocation, so a dirty
 *   change here ships alongside the AI Gateway release in exactly the
 *   scenario this check exists to catch, even though this guard's own
 *   invariants (App Check, kill switch, etc.) are specific to the other
 *   codebase.
 * - `firebase.json` -- the predeploy wiring itself, and the source of both
 *   codebases' `source`/`ignore` config.
 * - `.firebaserc` -- the project-alias file `firebase deploy` resolves its
 *   target project from. `checkDeployTarget` already fails closed if the
 *   RESOLVED project differs from `EXPECTED_PROJECT_ID`, but that only
 *   proves THIS invocation resolved correctly -- an uncommitted edit to
 *   this file (e.g. a new alias) is itself unreviewed deploy-configuration
 *   change this check should still catch.
 * - `.gitignore` (repo root) -- `git status`'s own ignore rules. Dirty
 *   `.gitignore` is a check-defeat vector: an uncommitted pattern added
 *   here could make a real untracked file under one of the paths above
 *   invisible to the very `git status` call below, silently reopening the
 *   thing this whole check exists to prevent.
 * - `RELEASE_EVIDENCE_PATH` -- the release-evidence anchor the guard reads
 *   directly.
 */
const PROVENANCE_RELEVANT_PATHS = [
  "functions",
  "functions-equipment-identity",
  "firebase.json",
  ".firebaserc",
  ".gitignore",
  RELEASE_EVIDENCE_PATH,
] as const;

/**
 * Confirmed live, round 4's own follow-up verification: a bare `git status
 * --porcelain` (repo-root scope) never reports clean in this checkout even
 * on a freshly committed HEAD, because unrelated untracked artifacts sit
 * elsewhere in the tree (old report HTML files from unrelated gates,
 * nothing to do with this release). Scoping `git status` to
 * `PROVENANCE_RELEVANT_PATHS` (via `git status --porcelain -- <paths>`,
 * which still respects `.gitignore` and still flags a genuinely dirty or
 * uncommitted change anywhere the deploy/guard actually depends on) fixes
 * this without weakening what the check protects.
 *
 * Round-5 GPT-PM MAJOR: the first version of this fix scoped to `functions`
 * alone, which does NOT exclude `functions/.gcloudignore` -- an
 * auto-generated Firebase/gcloud-CLI artifact that lives INSIDE that
 * directory and so still showed up as `?? functions/.gcloudignore` even
 * under the narrowed scope, defeating the fix's own stated purpose.
 *
 * Round-6 GPT-PM MAJOR: the first attempted fix -- adding `.gcloudignore`
 * to `functions/.gitignore` so `git status` stops seeing it -- traded that
 * permanent false positive for a genuine blind spot: a file `git status`
 * has been told to ignore can be silently modified (or, if `gcloud
 * functions deploy` were ever used as a real deploy path instead of this
 * project's actual `firebase deploy`, could genuinely change what gets
 * packaged) with zero visibility to this check ever again. Verified against
 * `firebase-tools`' own source (`prepareFunctionsUpload.ts`) that
 * `firebase deploy` -- this project's sole documented release path, see
 * this file's own module header -- reads `firebase.json`'s
 * `functions.ignore` field and a small hardcoded default list, and does NOT
 * consult `.gcloudignore` at all; but the safer fix does not need to lean
 * on that fact holding forever. Instead: `.gcloudignore` is now a normal
 * TRACKED file (its actual current content -- `.git`/`.gitignore`/
 * `node_modules` exclusions via `#!include:.gitignore`, the standard
 * Firebase-CLI template) rather than gitignored. A committed-and-clean file
 * shows nothing under scoped `git status`; a future mutation of it shows up
 * as a real, caught diff -- the same guarantee every other tracked file in
 * `PROVENANCE_RELEVANT_PATHS` already has, with no assumption required
 * about which deploy tool is used.
 *
 * Round-7 GPT-PM INFO (out-of-scope MINOR, not a provenance defect --
 * documented here rather than left implicit): this tracked `.gcloudignore`
 * is NOT independently verified safe for a direct `gcloud functions deploy`
 * -- its `#!include:.gitignore` inherits `functions/.gitignore`'s `lib/`
 * exclusion, so a raw `gcloud` deploy using it would omit the compiled
 * output. That path is unsupported by this project regardless (this file's
 * own module header: the sole documented release path is `firebase deploy
 * --only functions:*`, which -- per the verification above -- never reads
 * this file at all), so this does not weaken the provenance invariant
 * itself; it is a reason not to treat `gcloud functions deploy` as an
 * ad-hoc alternative release path without first fixing this file for it.
 */
async function checkSourceProvenance(deps: ReleaseGuardDeps): Promise<CheckResult> {
  const name = "Release comes from a clean, committed working tree";
  const status = await deps.runCommand("git", ["status", "--porcelain", "--", ...PROVENANCE_RELEVANT_PATHS], 15_000);
  if (!status.ok) return { name, status: "UNAVAILABLE", detail: status.stderr || "git status failed" };
  if (status.stdout.trim().length > 0) {
    return { name, status: "FAILED", detail: `uncommitted changes under ${PROVENANCE_RELEVANT_PATHS.join(", ")}` };
  }
  const head = await deps.runCommand("git", ["rev-parse", "HEAD"], 15_000);
  if (!head.ok) return { name, status: "UNAVAILABLE", detail: head.stderr || "git rev-parse HEAD failed" };
  return { name, status: "OK", detail: `clean tree (scoped to ${PROVENANCE_RELEVANT_PATHS.join(", ")}) at ${head.stdout.trim()}` };
}

export async function runReleaseGuard(deps: ReleaseGuardDeps): Promise<ReleaseGuardResult> {
  const evidence = await loadEvidence(deps);
  const describedFunctions = await describeAiFunctions(deps);

  const checks: CheckResult[] = [];
  checks.push(await checkDeployTarget(deps));
  checks.push(await checkCandidateSourceInvariants(deps));
  checks.push(await checkFunctionsInventory(deps));
  checks.push(
    "error" in describedFunctions
      ? { name: "App Check enforcement is on (fail-closed) for all 4 AI callables", status: "UNAVAILABLE", detail: describedFunctions.error }
      : await checkAppCheckEnforcement(describedFunctions),
  );
  checks.push(
    "error" in describedFunctions
      ? { name: "Anonymous callers are refused on all 4 AI callables", status: "UNAVAILABLE", detail: describedFunctions.error }
      : await checkAnonymousRefused(describedFunctions),
  );
  checks.push(await checkKillSwitchExists(deps));
  checks.push(await checkStep8DrillEvidence(evidence));
  checks.push(await checkAiObservability(deps));
  checks.push(await checkS23Gate(deps, evidence));
  checks.push(await checkSourceProvenance(deps));

  const verdict: Verdict = checks.every((c) => c.status === "OK") ? "PASS" : "BLOCK";
  return { verdict, generatedAt: new Date(deps.now()).toISOString(), checks };
}
