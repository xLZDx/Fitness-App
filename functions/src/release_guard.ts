/**
 * MVP1.G4 Step 9 -- the AI Gateway release guard.
 *
 * GPT-PM's binding DoD (obtained during Step 8's own DoD question, since
 * neither Step 8 nor Step 9 had a stated DoD anywhere in this repo): a
 * FAIL-CLOSED release gate -- not a runtime control like Step 8's kill
 * switch -- that runs in the canonical release path, verifies the 6 expected
 * AI callables (4 at Step 9; `analyzeMealPhoto` and `parseNutritionLabel` joined
 * in the Body Scan + Nutrition Coach sprint, D-63) are the intended deployed set
 * on `fn-ai-runtime`, verifies
 * App Check enforcement is on/fail-closed for all of them, verifies anonymous
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

/** Names of every check `runReleaseGuard` reports (one place, so the not-run list cannot drift). */
export const CHECK_NAME = {
  target: "Deploy target is this project's real Firebase project",
  inventory: "AI callables match the intended fn-ai-runtime deployed set",
  appCheck: "App Check enforcement is on (fail-closed) for all 6 AI callables",
  anonymous: "Anonymous callers are refused on all 6 AI callables",
  killSwitch: "Step 8 kill switch secret exists with genuinely read-only runtime IAM",
  drill: "Step 8 kill-switch drill evidence recorded as closed",
  observability: "AI Gateway observability metrics exist, match source, and are producing",
  s23: "S23 production Play Integrity proof gates an AI-enabled release",
  candidate: "Candidate source still carries its App Check / anonymous-refusal / gateway-guard wiring (AST-verified)",
  provenance: "Release comes from a clean, committed working tree",
  bodyScanBucket: "Body scan private bucket exists, is private, has the required IAM, and the canary is acknowledged",
} as const;

export type CheckStatus = "OK" | "FAILED" | "UNAVAILABLE";

export interface CheckResult {
  name: string;
  status: CheckStatus;
  detail: string;
}

export type Verdict = "PASS" | "BLOCK";

/** Which product line the checked-out branch belongs to -- see `classifyDeployLine`. */
export type DeployLine = "phase1" | "phase2" | "other";

export interface ReleaseGuardResult {
  verdict: Verdict;
  generatedAt: string;
  checks: CheckResult[];
  /** Deploy line derived from the current git branch. */
  line: DeployLine;
  /** Current git branch, or `null` when it could not be read / HEAD is detached. */
  branch: string | null;
  /** The project id the guard validated (`deps.project`). */
  project: string;
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
  /** Current git branch name (`git rev-parse --abbrev-ref HEAD`). Returns
   * `null` when it cannot be read; a detached HEAD is reported as the literal
   * `"HEAD"` by git and is treated as an unknown line. Never throws. */
  currentBranch: () => Promise<string | null>;
  /** Commit provenance for the Phase 1 line: resolves `true` only when HEAD is
   * verified to be an ancestor of (or equal to) a protected Phase 1 remote-
   * tracking ref (`PROTECTED_PHASE1_REFS`, via `git merge-base --is-ancestor`).
   * Must resolve `false` when a ref is missing, git fails, or HEAD is not
   * contained -- the guard also treats a rejection as `false`. Never trusted
   * from the branch name alone. */
  isCommitOnProtectedLine: () => Promise<boolean>;
  /** Process environment; only consulted to see whether `BODY_SCAN_BUCKET` is
   * configured (C12 flag-gated check). Optional so older callers/tests that
   * do not pass it behave exactly as before (bucket check skipped). */
  env?: Record<string, string | undefined>;
}

/**
 * The exact 6 AI Gateway callables this gate covers -- see `abuse_guard.ts`'s own QUOTAS map.
 * Body Scan + Nutrition Coach (D-63, C20) grew the set from 4 to 6: `analyzeMealPhoto` and
 * `parseNutritionLabel` run on `AI_METERED` as `fn-ai-runtime`, so they must be inside the
 * guarded set or `checkFunctionsInventory` would report them as `extra`.
 */
export const AI_CALLABLES = [
  "aiCoachAdvice",
  "aiEquipmentRecognition",
  "aiMachineDescription",
  "aiExerciseGeneration",
  "analyzeMealPhoto",
  "parseNutritionLabel",
] as const;

export const AI_RUNTIME_SERVICE_ACCOUNT_LOCAL = "fn-ai-runtime";
export const KILL_SWITCH_SECRET_NAME = "ai-gateway-kill-switch";
export const RELEASE_EVIDENCE_PATH = "core/state/g4_release_evidence.json";

/** The single real Firebase project this guard is meaningful for -- see
 * `.firebaserc`, which also defines an unrelated `legacy-shared` alias. */
export const EXPECTED_PROJECT_ID = "fitness-app-korostelev";

/** The unrelated legacy project alias in `.firebaserc` -- never a deploy target. */
export const LEGACY_PROJECT_ID = "traidingbot-b4061";

/** The `.firebaserc` alias the operator creates for the separate Phase 2 Firebase project. */
export const PHASE2_ALIAS = "phase2";

export const FIREBASERC_PATH = ".firebaserc";

/** Closed set of deploy-line block reasons; each appears as the leading slug
 * of the failing `checkDeployTarget` detail. */
export const DEPLOY_LINE_REASONS = [
  "deploy-line-unknown",
  "phase1-wrong-project",
  "firebaserc-unreadable",
  "phase2-alias-missing",
  "phase2-targets-production",
  "phase2-project-mismatch",
  "phase1-provenance-unverified",
] as const;
export type DeployLineReason = (typeof DEPLOY_LINE_REASONS)[number];

/** A Firebase/GCP project id (6-30 chars, lowercase letters, digits, hyphens, starts with a letter, does not end
 * with a hyphen). The id is interpolated into gcloud arguments, so anything else is refused before any command runs. */
export const PROJECT_ID_PATTERN = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/;

/** Closed set of reasons `resolveEffectiveProject` (and the project-id validation in `runReleaseGuard`) can fail with. */
export const PROJECT_RESOLUTION_REASONS = ["project-undeterminable", "project-conflict", "project-invalid"] as const;
export type ProjectResolutionReason = (typeof PROJECT_RESOLUTION_REASONS)[number];

/** Remote-tracking refs of the protected Phase 1 line. A Phase 1 production
 * deploy requires HEAD to be an ancestor of (or equal to) at least one of
 * them. `origin/master` stays valid only while `master` is still a Phase 1
 * branch name (see `classifyDeployLine`). */
export const PROTECTED_PHASE1_REFS = [
  "refs/remotes/origin/phase1/main",
  "refs/remotes/origin/master",
] as const;

/** Maps a git branch name to a deploy line. `phase2/*` -> phase2;
 * `phase1/main`, `master`, `phase1/*` -> phase1; anything else (feature
 * branches, detached HEAD = "HEAD", empty, unreadable = null) -> other. */
export function classifyDeployLine(branch: string | null): DeployLine {
  if (branch === null) return "other";
  const b = branch.trim();
  if (b.startsWith("phase2/")) return "phase2";
  if (b === "phase1/main" || b === "master" || b.startsWith("phase1/")) return "phase1";
  return "other";
}

export type DeployTargetResolution =
  | { ok: true; line: DeployLine; branch: string | null; allowedProject: string }
  | { ok: false; line: DeployLine; branch: string | null; reason: DeployLineReason; detail: string };

interface FirebaseRc {
  projects?: Record<string, unknown>;
}

/** Resolves the deploy line from the current branch and the single project id
 * that line may deploy to. Fails closed with a closed-slug reason; there is
 * deliberately no environment override. */
export async function resolveDeployTarget(deps: ReleaseGuardDeps): Promise<DeployTargetResolution> {
  let branch: string | null;
  try {
    branch = await deps.currentBranch();
  } catch {
    branch = null;
  }
  const line = classifyDeployLine(branch);
  if (line === "other") {
    return {
      ok: false,
      line,
      branch,
      reason: "deploy-line-unknown",
      detail: `deploy-line-unknown: branch ${branch === null ? "could not be read" : JSON.stringify(branch)} is not on a deploy line (phase1/*, master, phase2/*) -- no deploy from here`,
    };
  }
  if (line === "phase1") {
    // The branch NAME is not proof of what is checked out: a local branch
    // called phase1/x can hold Phase 2 commits. Require verified commit
    // provenance against the protected remote-tracking refs; fail closed.
    let onProtectedLine = false;
    try {
      onProtectedLine = (await deps.isCommitOnProtectedLine()) === true;
    } catch {
      onProtectedLine = false;
    }
    if (!onProtectedLine) {
      return {
        ok: false,
        line,
        branch,
        reason: "phase1-provenance-unverified",
        detail: `phase1-provenance-unverified: HEAD is not verified to be contained in ${PROTECTED_PHASE1_REFS.join(" or ")} (ref missing, git failed, or HEAD has commits outside the protected Phase 1 line) -- the branch name ${JSON.stringify(branch)} alone is not trusted; fetch and deploy only commits that are on the protected line`,
      };
    }
    return { ok: true, line, branch, allowedProject: EXPECTED_PROJECT_ID };
  }

  // phase2 line: the only allowed project is the id under alias `phase2`.
  const raw = await deps.readFile(FIREBASERC_PATH);
  let rc: FirebaseRc | undefined;
  if (raw !== null) {
    try {
      rc = JSON.parse(raw) as FirebaseRc;
    } catch {
      rc = undefined;
    }
  }
  if (rc === undefined || rc === null || typeof rc !== "object" || typeof rc.projects !== "object" || rc.projects === null) {
    return {
      ok: false,
      line,
      branch,
      reason: "firebaserc-unreadable",
      detail: `firebaserc-unreadable: ${FIREBASERC_PATH} is missing, unparseable or has no "projects" map -- cannot resolve alias "${PHASE2_ALIAS}"`,
    };
  }
  const projects = rc.projects;
  const alias = projects[PHASE2_ALIAS];
  if (typeof alias !== "string" || alias.trim().length === 0) {
    return {
      ok: false,
      line,
      branch,
      reason: "phase2-alias-missing",
      detail: `phase2-alias-missing: ${FIREBASERC_PATH} has no non-empty alias "${PHASE2_ALIAS}" -- the operator must create the Phase 2 Firebase project and add it`,
    };
  }
  const forbidden = new Set<string>([EXPECTED_PROJECT_ID, LEGACY_PROJECT_ID]);
  for (const [key, value] of Object.entries(projects)) {
    if (key !== PHASE2_ALIAS && typeof value === "string") forbidden.add(value);
  }
  if (forbidden.has(alias)) {
    return {
      ok: false,
      line,
      branch,
      reason: "phase2-targets-production",
      detail: `phase2-targets-production: alias "${PHASE2_ALIAS}" = "${alias}" is the production/legacy/other-alias project -- Phase 2 must have its own Firebase project`,
    };
  }
  return { ok: true, line, branch, allowedProject: alias };
}

/** `firebase deploy` arguments the guard cares about. */
export interface DeployArgs {
  /** Value of every `--project` / `--project=` / `-P` flag, in order (`""` when a value is missing). */
  projects: string[];
  /** True when `--config`/`-c` is present: a different firebase config carries different (possibly no) guard hooks. */
  hasConfigFlag: boolean;
  /** True when a short-flag cluster such as `-ic x.json` or `-iPprod` could hide `-c` or `-P`: any token matching
   * `/^-[A-Za-z]{2,}/` that contains `c` or `P` (and is not itself `-P<value>`/`-c...`). Treated as fail closed. */
  hasShortFlagCluster: boolean;
  /** The arguments with every project flag (and its value) removed. */
  rest: string[];
}

/** Parses `firebase deploy` arguments the way the CLI's own option parser
 * reads the project selector: `--project X`, `--project=X`, `-P X`, `-PX`. */
export function parseDeployArgs(argv: string[]): DeployArgs {
  const projects: string[] = [];
  const rest: string[] = [];
  let hasConfigFlag = false;
  let hasShortFlagCluster = false;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--project" || a === "-P") {
      projects.push(argv[i + 1] ?? "");
      i++;
      continue;
    }
    if (a.startsWith("--project=")) {
      projects.push(a.slice("--project=".length));
      continue;
    }
    if (a.startsWith("-P") && a.length > 2) {
      projects.push(a.slice(2));
      continue;
    }
    if (a === "-c" || a === "--config" || a.startsWith("--config=") || (a.startsWith("-c") && !a.startsWith("--"))) {
      hasConfigFlag = true;
    } else if (/^-[A-Za-z]{2,}/.test(a) && /[cP]/.test(a)) {
      hasShortFlagCluster = true;
    }
    rest.push(a);
  }
  return { projects, hasConfigFlag, hasShortFlagCluster, rest };
}

export type EffectiveProjectResolution =
  | { ok: true; project: string; source: "GCLOUD_PROJECT" | "--project" }
  | { ok: false; reason: ProjectResolutionReason; detail: string };

function readRcAliases(firebaserc: string | null): Record<string, unknown> {
  if (firebaserc === null) return {};
  try {
    const rc = JSON.parse(firebaserc) as FirebaseRc;
    return rc !== null && typeof rc === "object" && typeof rc.projects === "object" && rc.projects !== null
      ? rc.projects
      : {};
  } catch {
    return {};
  }
}

/**
 * Determines the project a deploy will actually hit, from the real CLI inputs,
 * and fails CLOSED when it cannot.
 *
 * Verified against firebase-tools 15.x source (`lib/deploy/lifecycleHooks.js`,
 * `lib/command.js`): inside a `predeploy` hook the CLI exports the RESOLVED
 * project id as `GCLOUD_PROJECT` (alias already mapped through `.firebaserc`),
 * so that variable is authoritative there. The CLI itself picks the project
 * from `--project`/`-P` (alias or id), else the per-user `firebase use` active
 * project (configstore, outside the repo and not readable here), else the
 * `.firebaserc` single/`default` alias -- `FIREBASE_PROJECT` is only read by
 * `firebase init`, never by `deploy`. The guard therefore never guesses from
 * `.firebaserc` defaults or the environment: it accepts only `GCLOUD_PROJECT`
 * and/or an explicit project flag (alias resolved via `.firebaserc`), blocks
 * when the two disagree, and blocks when neither is present.
 */
export function resolveEffectiveProject(input: {
  env: Record<string, string | undefined>;
  argv: string[];
  firebaserc: string | null;
}): EffectiveProjectResolution {
  const aliases = readRcAliases(input.firebaserc);
  const toId = (value: string): string => {
    const mapped = aliases[value];
    return typeof mapped === "string" && mapped.trim().length > 0 ? mapped.trim() : value;
  };

  const parsedArgs = parseDeployArgs(input.argv);
  if (parsedArgs.hasShortFlagCluster) {
    return {
      ok: false,
      reason: "project-undeterminable",
      detail: "project-undeterminable: a combined short-flag token (for example -ic or -iPprod) could hide --config or --project -- pass flags separately",
    };
  }
  const flagValues = parsedArgs.projects.map((v) => v.trim());
  if (flagValues.some((v) => v.length === 0)) {
    return {
      ok: false,
      reason: "project-undeterminable",
      detail: "project-undeterminable: a --project/-P flag has no value -- cannot determine the deploy project",
    };
  }
  const flagProjects = [...new Set(flagValues.map(toId))];
  if (flagProjects.length > 1) {
    return {
      ok: false,
      reason: "project-conflict",
      detail: `project-conflict: several different --project values (${flagProjects.join(", ")}) -- refusing to guess which one the CLI uses`,
    };
  }
  const envProject = (input.env["GCLOUD_PROJECT"] ?? "").trim();

  if (envProject.length > 0 && flagProjects.length === 1 && envProject !== flagProjects[0]) {
    return {
      ok: false,
      reason: "project-conflict",
      detail: `project-conflict: GCLOUD_PROJECT = "${envProject}" but --project resolves to "${flagProjects[0]}" -- refusing to guess which one the deploy hits`,
    };
  }
  const invalid = (value: string): EffectiveProjectResolution => ({
    ok: false,
    reason: "project-invalid",
    detail: `project-invalid: ${JSON.stringify(value)} is not a valid project id (expected ${PROJECT_ID_PATTERN.source})`,
  });
  if (envProject.length > 0) {
    return PROJECT_ID_PATTERN.test(envProject) ? { ok: true, project: envProject, source: "GCLOUD_PROJECT" } : invalid(envProject);
  }
  if (flagProjects.length === 1) {
    return PROJECT_ID_PATTERN.test(flagProjects[0]) ? { ok: true, project: flagProjects[0], source: "--project" } : invalid(flagProjects[0]);
  }
  return {
    ok: false,
    reason: "project-undeterminable",
    detail:
      "project-undeterminable: neither GCLOUD_PROJECT (set by the firebase CLI for predeploy hooks) nor an explicit --project/-P is present -- the guard does not guess from .firebaserc defaults or the active-project store; deploy through scripts/deploy/guarded_deploy.mjs or pass --project",
  };
}

/** Marker proving a `predeploy` entry runs this guard. */
export const GUARD_COMMAND_MARKER = "run_release_guard.mjs";

/** The exact `predeploy` command that runs the guard; `findUnguardedDeployTargets` requires this whole string
 * (after trimming), not a substring, so `echo run_release_guard.mjs` or a neutered variant does not count. */
export const GUARD_COMMAND = "node functions/scripts/run_release_guard.mjs";

/** `firebase.json` sections whose schema accepts `predeploy` (verified in
 * firebase-tools' `schema/firebase-config.json`): each must run the guard. */
const GUARDABLE_DEPLOY_SECTIONS = [
  "functions",
  "firestore",
  "hosting",
  "storage",
  "database",
  "dataconnect",
  "remoteconfig",
] as const;

/** Deploy sections whose schema has no `predeploy` at all: if one is present
 * in `firebase.json` it cannot carry the guard and must be reported. */
const UNGUARDABLE_DEPLOY_SECTIONS = ["apphosting", "auth", "extensions"] as const;

/** Returns a label for every deploy target in a parsed `firebase.json` that
 * does NOT run the release guard in its `predeploy` hook (empty = every
 * present deploy target is guarded). Sections absent from the file (for
 * example `storage` while no `storage.rules` exists) are not reported;
 * sections that cannot carry a hook at all are reported when present. */
export function findUnguardedDeployTargets(config: unknown): string[] {
  if (config === null || typeof config !== "object") return ["firebase.json:unreadable"];
  const c = config as Record<string, unknown>;
  const out: string[] = [];
  for (const section of GUARDABLE_DEPLOY_SECTIONS) {
    const value = c[section];
    if (value === undefined) continue;
    const entries = Array.isArray(value) ? value : [value];
    entries.forEach((entry, index) => {
      const label = Array.isArray(value) ? `${section}[${index}]` : section;
      const predeploy = entry !== null && typeof entry === "object" ? (entry as { predeploy?: unknown }).predeploy : undefined;
      const commands = typeof predeploy === "string" ? [predeploy] : Array.isArray(predeploy) ? predeploy : [];
      if (!commands.some((cmd) => typeof cmd === "string" && cmd.trim() === GUARD_COMMAND)) out.push(label);
    });
  }
  for (const section of UNGUARDABLE_DEPLOY_SECTIONS) {
    if (c[section] !== undefined) out.push(`${section}:no-predeploy-hook`);
  }
  return out;
}

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
  analyzeMealPhoto: "functions/src/analyze_meal_photo.ts",
  parseNutritionLabel: "functions/src/parse_nutrition_label.ts",
};
const SCALING_SOURCE_FILE = "functions/src/scaling.ts";

interface ReleaseEvidence {
  step8KillSwitch?: { status?: unknown };
  s23PlayIntegrityProof?: { status?: unknown };
  /** Operator acknowledgement that the runbook canary (write + deleteFiles as
   * fn-bodyscan and as fn-account-delete) passed; see
   * `runbooks/body_scan_bucket.md` section 4. Only read when BODY_SCAN_BUCKET
   * is configured. */
  bodyScanBucketCanary?: { status?: unknown };
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
export async function checkDeployTarget(
  deps: ReleaseGuardDeps,
  resolution?: DeployTargetResolution,
): Promise<CheckResult> {
  const name = CHECK_NAME.target;
  const resolved = resolution ?? (await resolveDeployTarget(deps));
  if (!resolved.ok) {
    return { name, status: "FAILED", detail: resolved.detail };
  }
  if (deps.project !== resolved.allowedProject) {
    const reason: DeployLineReason = resolved.line === "phase2" ? "phase2-project-mismatch" : "phase1-wrong-project";
    return {
      name,
      status: "FAILED",
      detail: `${reason}: resolved project is "${deps.project}", the ${resolved.line} line may deploy only to "${resolved.allowedProject}" -- every other check below would validate the wrong project`,
    };
  }
  return { name, status: "OK", detail: `line = ${resolved.line}, project = ${resolved.allowedProject}` };
}

async function checkFunctionsInventory(deps: ReleaseGuardDeps): Promise<CheckResult> {
  const name = CHECK_NAME.inventory;
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
  return { name, status: "OK", detail: `all 6 callables, exactly, run as ${runtimeSa}` };
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
  const name = CHECK_NAME.appCheck;
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
  const name = CHECK_NAME.anonymous;
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
  const name = CHECK_NAME.killSwitch;
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
  const name = CHECK_NAME.drill;
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
  const name = CHECK_NAME.observability;
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
  const name = CHECK_NAME.s23;
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
  const name = CHECK_NAME.candidate;
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
    detail: "AST-verified: AI_METERED wiring, all 6 callables' onCall(AI_METERED, ...) declarations, and real enforceNonAnonymousForAi/enforceAiGatewayEnabled CallExpression nodes are all present in the candidate source (not merely mentioned in a comment)",
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
  // Everything else `firebase deploy` reads (review fix A): rules, indexes and the hosting public dir.
  "firestore.rules",
  "firestore.indexes.json",
  "storage.rules",
  "public",
] as const;

/** Only plain repo-relative paths may enter the `git status` pathspec (no absolute paths, no `..`, no pathspec magic). */
function isSafeRepoRelativePath(p: string): boolean {
  return (
    p.length > 0 &&
    !p.startsWith("/") &&
    !p.startsWith(":") &&
    !p.startsWith("-") &&
    !/^[A-Za-z]:/.test(p) &&
    !p.includes("\\") &&
    !p.split("/").includes("..")
  );
}

/** A directory `firebase deploy` uploads, with the target's own ignore patterns from `firebase.json`. */
interface DeployDir {
  /** Repo-relative directory (hosting `public`, functions `source`). */
  dir: string;
  ignore: string[];
  kind: "hosting" | "functions";
}

interface ProvenanceScope {
  paths: string[];
  dirs: DeployDir[];
}

/** The fixed list plus every rules/indexes file, hosting public dir and functions source named in `firebase.json`
 * (when readable and well-formed); the fixed list is always included, so an unreadable file only loses the extras.
 * Also returns each uploaded directory with its own `ignore` list (used to classify git-ignored files). */
async function provenanceScope(deps: ReleaseGuardDeps): Promise<ProvenanceScope> {
  const out = new Set<string>(PROVENANCE_RELEVANT_PATHS);
  const dirs: DeployDir[] = [];
  let config: unknown;
  try {
    const raw = await deps.readFile("firebase.json");
    config = raw === null ? undefined : JSON.parse(raw);
  } catch {
    config = undefined;
  }
  if (config === null || typeof config !== "object") {
    // Unreadable firebase.json: the fixed directories with no ignore list (strictest classification).
    return {
      paths: [...out],
      dirs: [
        { dir: "functions", ignore: [], kind: "functions" },
        { dir: "functions-equipment-identity", ignore: [], kind: "functions" },
        { dir: "public", ignore: [], kind: "hosting" },
      ],
    };
  }
  const c = config as Record<string, unknown>;
  const asList = (v: unknown): Record<string, unknown>[] =>
    (Array.isArray(v) ? v : v === undefined ? [] : [v]).filter(
      (e): e is Record<string, unknown> => e !== null && typeof e === "object",
    );
  const norm = (v: unknown): string | undefined => {
    if (typeof v !== "string") return undefined;
    const n = v.trim().replace(/^\.\//, "").replace(/\/+$/, "");
    return isSafeRepoRelativePath(n) ? n : undefined;
  };
  const add = (v: unknown): void => {
    const n = norm(v);
    if (n !== undefined) out.add(n);
  };
  const ignoreList = (e: Record<string, unknown>): string[] =>
    Array.isArray(e["ignore"]) ? (e["ignore"] as unknown[]).filter((x): x is string => typeof x === "string") : [];
  // firebase-tools `prepareFunctionsUpload.js`: `config.ignore || ["node_modules", ".git"]`, then always adds
  // `firebase-debug.log` and `firebase-debug.*.log`. An explicit `ignore: []` therefore uploads node_modules.
  const functionsIgnoreList = (e: Record<string, unknown>): string[] => [
    ...(Array.isArray(e["ignore"]) ? ignoreList(e) : ["node_modules", ".git"]),
    "firebase-debug.log",
    "firebase-debug.*.log",
  ];
  for (const e of asList(c["firestore"])) {
    add(e["rules"]);
    add(e["indexes"]);
  }
  for (const e of asList(c["storage"])) add(e["rules"]);
  for (const e of asList(c["hosting"])) {
    add(e["public"]);
    const dir = norm(e["public"]);
    if (dir !== undefined) dirs.push({ dir, ignore: ignoreList(e), kind: "hosting" });
  }
  for (const e of asList(c["functions"])) {
    add(e["source"]);
    const dir = norm(e["source"]);
    if (dir !== undefined) dirs.push({ dir, ignore: functionsIgnoreList(e), kind: "functions" });
  }
  return { paths: [...out], dirs };
}

/** Compiled output built by `predeploy` from tracked source (the guard itself loads `functions/lib`). */
const ALLOWED_IGNORED_BUILD_DIRS = ["functions/lib", "functions-equipment-identity/lib"] as const;

/** Converts the simple glob forms used in `firebase.json` ignore lists to a RegExp over a `/`-separated relative
 * path: `*` (no `/`, never a leading dot at a segment start), `?`, `**` and the `**` + `/` / `/` + `**` forms.
 * Anything else (character classes, braces, negation, escapes) is unsupported and returns `null` = never matches,
 * so an unrecognised pattern can only make the check stricter. */
function globToRegExp(pattern: string): RegExp | null {
  const pat = pattern.trim().replace(/^\.\//, "");
  if (pat.length === 0) return null;
  let re = "";
  let i = 0;
  while (i < pat.length) {
    const ch = pat[i];
    if (pat.startsWith("**/", i)) {
      re += "(?:.*/)?";
      i += 3;
    } else if (pat.startsWith("/**", i) && i + 3 === pat.length) {
      re += "(?:/.*)?";
      i += 3;
    } else if (pat.startsWith("**", i)) {
      re += ".*";
      i += 2;
    } else if (ch === "*") {
      re += i === 0 || pat[i - 1] === "/" ? "(?!\\.)[^/]*" : "[^/]*";
      i += 1;
    } else if (ch === "?") {
      re += "[^/]";
      i += 1;
    } else if ("[]{}()!+@|\\".includes(ch)) {
      return null;
    } else {
      re += ch.replace(/[.^$*+?()[\]{}|\\]/g, "\\$&");
      i += 1;
    }
  }
  return new RegExp(`^${re}$`);
}

/** True when `rel` (path relative to the uploaded dir) or any of its ancestor directories matches an ignore
 * pattern -- an ignored directory excludes everything inside it. */
function excludedByTargetIgnore(rel: string, patterns: string[], matchBase: boolean): boolean {
  const segments = rel.split("/");
  const regexps = patterns.map((pt) => ({ re: globToRegExp(pt), slashFree: !pt.includes("/") }));
  for (let n = 1; n <= segments.length; n++) {
    const prefix = segments.slice(0, n).join("/");
    const base = segments[n - 1];
    // Functions upload uses minimatch with `matchBase: true`: a slash-free pattern matches the basename at any depth.
    if (regexps.some(({ re, slashFree }) => re !== null && (re.test(prefix) || (matchBase && slashFree && re.test(base))))) {
      return true;
    }
  }
  return false;
}

/** Classifies one git-ignored entry (`!!` line, repo-relative, trailing `/` for a directory). Returns true when it
 * is legitimately not a deploy input or is a known harmless/build artefact. Everything else is an ignored file
 * that Firebase would still upload from a path the verified commit does not contain. */
function isAllowedIgnoredEntry(entry: string, scope: ProvenanceScope): boolean {
  if (entry.startsWith('"')) return false; // quoted (special characters): cannot be classified, fail closed
  const p = entry.replace(/\/+$/, "");
  if (p.length === 0 || !isSafeRepoRelativePath(p)) return false;
  // node_modules is NOT allowed unconditionally: it is only allowed when the deploy target's own ignore list
  // excludes it (rule (c) below). `hosting.ignore: []` uploads public/node_modules, `functions[].ignore: []`
  // uploads functions/node_modules.
  // (b) compiled output built by predeploy (packaged by design: `main` is lib/index.js)
  if (ALLOWED_IGNORED_BUILD_DIRS.some((d) => p === d || p.startsWith(`${d}/`))) return true;
  for (const t of scope.dirs) {
    if (p !== t.dir && !p.startsWith(`${t.dir}/`)) continue;
    const rel = p === t.dir ? "" : p.slice(t.dir.length + 1);
    if (rel.length === 0) continue;
    // (d) Firebase env files are deploy inputs by design (their candidate content is not verified here)
    if (t.kind === "functions" && !rel.includes("/") && (rel === ".env" || rel.startsWith(".env."))) return true;
    // (c) excluded by the target's own ignore list
    if (excludedByTargetIgnore(rel, t.ignore, t.kind === "functions")) return true;
  }
  return false;
}

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
  const name = CHECK_NAME.provenance;
  const scope = await provenanceScope(deps);
  const paths = scope.paths;
  // `--ignored=matching` adds `!!` entries for git-IGNORED files: Firebase uploads them anyway (it only honours
  // the target's own `ignore` list), so an ignored file is not part of the verified commit but would be deployed.
  const status = await deps.runCommand("git", ["status", "--porcelain", "--ignored=matching", "--", ...paths], 15_000);
  if (!status.ok) return { name, status: "UNAVAILABLE", detail: status.stderr || "git status failed" };
  const lines = status.stdout.split(/\r?\n/).filter((l) => l.trim().length > 0);
  if (lines.some((l) => !l.startsWith("!! "))) {
    return { name, status: "FAILED", detail: `uncommitted changes under ${paths.join(", ")}` };
  }
  const offending = [...new Set(lines.map((l) => l.slice(3)).filter((entry) => !isAllowedIgnoredEntry(entry, scope)))].sort();
  if (offending.length > 0) {
    const shown = offending.slice(0, 20).join(", ");
    const more = offending.length > 20 ? ` (+${offending.length - 20} more)` : "";
    return {
      name,
      status: "FAILED",
      detail: `ignored-deployable-files: git-ignored but deployable entries under ${paths.join(", ")} that are not in the verified commit: ${shown}${more}`,
    };
  }
  const head = await deps.runCommand("git", ["rev-parse", "HEAD"], 15_000);
  if (!head.ok) return { name, status: "UNAVAILABLE", detail: head.stderr || "git rev-parse HEAD failed" };
  return { name, status: "OK", detail: `clean tree (scoped to ${paths.join(", ")}) at ${head.stdout.trim()}` };
}

const BODY_SCAN_BUCKET_NAME = /^[a-z0-9][a-z0-9._-]{1,220}[a-z0-9]$/;
const BODY_SCAN_RUNTIME_SA_LOCAL = "fn-bodyscan";
const ACCOUNT_DELETE_SA_LOCAL = "fn-account-delete";

/** The configured private body-scan bucket (same validity rule as
 * `body_scan/flags.ts`), from the process env first, then from the
 * codebase-wide `functions/.env.<project>` the deploy actually reads. */
async function configuredBodyScanBucket(deps: ReleaseGuardDeps): Promise<string | undefined> {
  const fromEnv = deps.env?.["BODY_SCAN_BUCKET"]?.trim();
  if (fromEnv) return BODY_SCAN_BUCKET_NAME.test(fromEnv) ? fromEnv : undefined;
  const dotenv = await deps.readFile(`functions/.env.${deps.project}`);
  if (dotenv === null) return undefined;
  for (const line of dotenv.split(/\r?\n/)) {
    const m = /^\s*BODY_SCAN_BUCKET\s*=\s*(.*?)\s*$/.exec(line);
    if (!m) continue;
    const value = m[1].replace(/^(["'])(.*)\1$/, "$2").trim();
    if (BODY_SCAN_BUCKET_NAME.test(value)) return value;
  }
  return undefined;
}

/**
 * C12 / D-60 / SD-6 / SD-11: flag-gated. Runs only when `BODY_SCAN_BUCKET` is
 * configured -- the body-scan callables run as `fn-bodyscan`, outside the AI
 * guard set (D-63), so with no bucket there is nothing to prove and the guard
 * emits no extra check. With a bucket, the release needs: the bucket exists,
 * public access prevention enforced, uniform access on, `fn-bodyscan` and
 * `fn-account-delete` both hold objectAdmin on it, and the committed evidence
 * records the runbook canary as closed ("configured but IAM-denied" would make
 * account deletion fail for every user).
 */
async function checkBodyScanBucket(
  deps: ReleaseGuardDeps,
  bucket: string,
  evidence: ReleaseEvidence | undefined,
): Promise<CheckResult> {
  const name = CHECK_NAME.bodyScanBucket;
  const described = await runGcloudJson<Record<string, unknown>>(deps, [
    "storage",
    "buckets",
    "describe",
    `gs://${bucket}`,
    `--project=${deps.project}`,
  ]);
  if ("error" in described) return { name, status: "UNAVAILABLE", detail: `bucket describe: ${described.error}` };
  const info = described.value;
  const iamConfig = (info["iamConfiguration"] ?? {}) as {
    publicAccessPrevention?: unknown;
    uniformBucketLevelAccess?: { enabled?: unknown };
  };
  const pap = info["public_access_prevention"] ?? iamConfig.publicAccessPrevention;
  const ubla = info["uniform_bucket_level_access"] ?? iamConfig.uniformBucketLevelAccess?.enabled;
  const problems: string[] = [];
  if (pap !== "enforced") problems.push(`public access prevention is ${JSON.stringify(pap)}, expected "enforced"`);
  if (ubla !== true) problems.push("uniform bucket-level access is not enabled");

  const policy = await runGcloudJson<IamPolicy>(deps, [
    "storage",
    "buckets",
    "get-iam-policy",
    `gs://${bucket}`,
    `--project=${deps.project}`,
  ]);
  if ("error" in policy) return { name, status: "UNAVAILABLE", detail: `bucket IAM policy: ${policy.error}` };
  const bindings = policy.value.bindings ?? [];
  for (const m of bindings.flatMap((b) => b.members)) {
    if (m === "allUsers" || m === "allAuthenticatedUsers") problems.push(`public principal ${m} is bound on the bucket`);
  }
  for (const local of [BODY_SCAN_RUNTIME_SA_LOCAL, ACCOUNT_DELETE_SA_LOCAL]) {
    const member = `serviceAccount:${local}@${deps.project}.iam.gserviceaccount.com`;
    const hasAdmin = bindings.some((b) => b.role === "roles/storage.objectAdmin" && b.members.includes(member));
    if (!hasAdmin) problems.push(`${local} lacks roles/storage.objectAdmin on the bucket`);
  }

  if (evidence === undefined) {
    problems.push(`${RELEASE_EVIDENCE_PATH} missing or unparseable (canary acknowledgement unreadable)`);
  } else if (evidence.bodyScanBucketCanary?.status !== "closed") {
    problems.push(`bodyScanBucketCanary.status = ${JSON.stringify(evidence.bodyScanBucketCanary?.status)}, expected "closed" (runbooks/body_scan_bucket.md section 4)`);
  }
  if (problems.length > 0) return { name, status: "FAILED", detail: problems.join("; ") };
  return { name, status: "OK", detail: `bucket ${bucket}: private, uniform access, fn-bodyscan and fn-account-delete objectAdmin, canary closed` };
}

/** Turns an unexpected throw inside one check into an UNAVAILABLE check (the report must stay complete). */
async function guardedCheck(name: string, fn: () => Promise<CheckResult>): Promise<CheckResult> {
  try {
    return await fn();
  } catch (e) {
    return { name, status: "UNAVAILABLE", detail: `check threw an unexpected error: ${e instanceof Error ? e.message : String(e)}` };
  }
}

/** Every check except the deploy-target one, in report order -- used for the deterministic "not run" report. */
const DOWNSTREAM_CHECK_NAMES = [
  CHECK_NAME.candidate,
  CHECK_NAME.inventory,
  CHECK_NAME.appCheck,
  CHECK_NAME.anonymous,
  CHECK_NAME.killSwitch,
  CHECK_NAME.drill,
  CHECK_NAME.observability,
  CHECK_NAME.s23,
  CHECK_NAME.provenance,
] as const;

export async function runReleaseGuard(deps: ReleaseGuardDeps): Promise<ReleaseGuardResult> {
  // 1. Deploy target FIRST: no gcloud/git-state command may run against a project that is not validated.
  let target: DeployTargetResolution;
  try {
    target = await resolveDeployTarget(deps);
  } catch (e) {
    target = {
      ok: false,
      line: "other",
      branch: null,
      reason: "deploy-line-unknown",
      detail: `deploy-line-unknown: deploy-line resolution threw an unexpected error: ${e instanceof Error ? e.message : String(e)}`,
    };
  }
  const projectValid = typeof deps.project === "string" && PROJECT_ID_PATTERN.test(deps.project);
  const targetCheck: CheckResult = !projectValid
    ? {
        name: CHECK_NAME.target,
        status: "FAILED",
        detail: `project-invalid: ${JSON.stringify(deps.project)} is not a valid project id (expected ${PROJECT_ID_PATTERN.source})`,
      }
    : await guardedCheck(CHECK_NAME.target, () => checkDeployTarget(deps, target));
  const checks: CheckResult[] = [targetCheck];

  if (targetCheck.status !== "OK") {
    for (const name of DOWNSTREAM_CHECK_NAMES) {
      checks.push({ name, status: "UNAVAILABLE", detail: "not run: the deploy-target check did not pass, so no command was run against this project" });
    }
    return {
      verdict: "BLOCK",
      generatedAt: new Date(deps.now()).toISOString(),
      checks,
      line: target.line,
      branch: target.branch,
      project: deps.project,
    };
  }

  // 2. Everything else; one check throwing never aborts the report.
  let evidence: ReleaseEvidence | undefined;
  try {
    evidence = await loadEvidence(deps);
  } catch {
    evidence = undefined;
  }
  let describedFunctions: Awaited<ReturnType<typeof describeAiFunctions>>;
  try {
    describedFunctions = await describeAiFunctions(deps);
  } catch (e) {
    describedFunctions = { error: `describing AI functions threw: ${e instanceof Error ? e.message : String(e)}` };
  }

  checks.push(await guardedCheck(CHECK_NAME.candidate, () => checkCandidateSourceInvariants(deps)));
  checks.push(await guardedCheck(CHECK_NAME.inventory, () => checkFunctionsInventory(deps)));
  checks.push(
    "error" in describedFunctions
      ? { name: CHECK_NAME.appCheck, status: "UNAVAILABLE", detail: describedFunctions.error }
      : await guardedCheck(CHECK_NAME.appCheck, () => checkAppCheckEnforcement(describedFunctions)),
  );
  checks.push(
    "error" in describedFunctions
      ? { name: CHECK_NAME.anonymous, status: "UNAVAILABLE", detail: describedFunctions.error }
      : await guardedCheck(CHECK_NAME.anonymous, () => checkAnonymousRefused(describedFunctions)),
  );
  checks.push(await guardedCheck(CHECK_NAME.killSwitch, () => checkKillSwitchExists(deps)));
  checks.push(await guardedCheck(CHECK_NAME.drill, () => checkStep8DrillEvidence(evidence)));
  checks.push(await guardedCheck(CHECK_NAME.observability, () => checkAiObservability(deps)));
  checks.push(await guardedCheck(CHECK_NAME.s23, () => checkS23Gate(deps, evidence)));
  checks.push(await guardedCheck(CHECK_NAME.provenance, () => checkSourceProvenance(deps)));
  try {
    const bodyScanBucket = await configuredBodyScanBucket(deps);
    if (bodyScanBucket !== undefined) {
      checks.push(await guardedCheck(CHECK_NAME.bodyScanBucket, () => checkBodyScanBucket(deps, bodyScanBucket, evidence)));
    }
  } catch (e) {
    checks.push({
      name: CHECK_NAME.bodyScanBucket,
      status: "UNAVAILABLE",
      detail: `could not determine whether BODY_SCAN_BUCKET is configured: ${e instanceof Error ? e.message : String(e)}`,
    });
  }

  const verdict: Verdict = checks.every((c) => c.status === "OK") ? "PASS" : "BLOCK";
  return {
    verdict,
    generatedAt: new Date(deps.now()).toISOString(),
    checks,
    line: target.line,
    branch: target.branch,
    project: deps.project,
  };
}
