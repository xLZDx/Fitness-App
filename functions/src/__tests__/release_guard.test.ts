/**
 * MVP1.G4 Step 9's release guard. Every check's OK/FAILED/UNAVAILABLE branch
 * is exercised here via an injected fake `ReleaseGuardDeps` -- no live
 * `gcloud`/git/filesystem access, matching `enforcement_state.ts`'s own
 * deps-injection test philosophy. `baseCommandTable` returns the "everything
 * is healthy" response for every real command this module issues; each test
 * overrides only the one command relevant to what it is proving.
 *
 * Round-1 GPT-PM review found 4 MAJORs in the original 8-check guard;
 * `checkDeployTarget` and `checkCandidateSourceInvariants` are new checks
 * added in remediation, and `checkKillSwitchExists`/`checkAiObservability`
 * were both substantially rewritten -- see `release_guard.ts`'s own module
 * header for the full list.
 */
import {
  runReleaseGuard,
  ReleaseGuardDeps,
  CommandResult,
  AI_CALLABLES,
  RELEASE_EVIDENCE_PATH,
  EXPECTED_PROJECT_ID,
  LEGACY_PROJECT_ID,
  PHASE2_ALIAS,
  FIREBASERC_PATH,
  DEPLOY_LINE_REASONS,
  classifyDeployLine,
  resolveDeployTarget,
  checkDeployTarget,
  PROTECTED_PHASE1_REFS,
  PROJECT_RESOLUTION_REASONS,
  GUARD_COMMAND_MARKER,
  parseDeployArgs,
  resolveEffectiveProject,
  findUnguardedDeployTargets,
} from "../release_guard";
import * as fs from "fs";
import * as path from "path";
import {
  aiGatewayCallsMetricJson,
  aiGatewayLatencyMetricJson,
  aiGatewayQuotaExhaustionsMetricJson,
  aiGatewayTokensMetricJson,
} from "../monitoring/ai_gateway_definitions";

const PROJECT = EXPECTED_PROJECT_ID;
const RUNTIME_SA = `fn-ai-runtime@${PROJECT}.iam.gserviceaccount.com`;
const PHASE2_PROJECT = "fitness-app-phase2-test";

const DEFAULT_FIREBASERC = JSON.stringify({
  projects: { default: EXPECTED_PROJECT_ID, "legacy-shared": LEGACY_PROJECT_ID },
});
function firebasercWith(projects: Record<string, unknown>): string {
  return JSON.stringify({ projects });
}

const HEALTHY_EVIDENCE = JSON.stringify({
  step8KillSwitch: { status: "closed" },
  s23PlayIntegrityProof: { status: "closed" },
});

const HEALTHY_KILL_SWITCH_PAYLOAD = JSON.stringify({ enabled: false, reason: null });

function functionsListJson(): string {
  return JSON.stringify(
    AI_CALLABLES.map((name) => ({
      name: `projects/${PROJECT}/locations/europe-west1/functions/${name}`,
      serviceConfig: { serviceAccountEmail: RUNTIME_SA },
    })),
  );
}

function functionDescribeJson(overrides: Record<string, string> = {}): string {
  return JSON.stringify({
    serviceConfig: {
      serviceAccountEmail: RUNTIME_SA,
      environmentVariables: { APP_CHECK_ENFORCED_AI: "true", ...overrides },
    },
  });
}

const HEALTHY_SECRET_IAM_POLICY = JSON.stringify({
  bindings: [{ role: "roles/secretmanager.secretAccessor", members: [`serviceAccount:${RUNTIME_SA}`] }],
});

const HEALTHY_PROJECT_IAM_POLICY = JSON.stringify({
  bindings: [{ role: "roles/datastore.user", members: [`serviceAccount:${RUNTIME_SA}`] }],
});

const METRIC_BUILDERS: Record<string, () => object> = {
  ai_gateway_calls: aiGatewayCallsMetricJson,
  ai_gateway_latency_ms: aiGatewayLatencyMetricJson,
  ai_gateway_quota_exhaustions: aiGatewayQuotaExhaustionsMetricJson,
  ai_gateway_total_tokens_per_call: aiGatewayTokensMetricJson,
};

/** The real canonical JSON (imported straight from source, so this fixture
 * can never silently drift from what the guard itself compares against)
 * plus the GCP-only fields a live `gcloud logging metrics describe` response
 * carries and the guard's `canonicalMetricSubset` deliberately strips --
 * confirmed against a real live describe call before writing this. */
function healthyLiveMetricJson(metricName: string): string {
  const canonical = METRIC_BUILDERS[metricName]() as Record<string, unknown>;
  const descriptor = canonical.metricDescriptor as Record<string, unknown>;
  return JSON.stringify({
    ...canonical,
    createTime: "2026-08-27T12:52:35.602108773Z",
    updateTime: "2026-08-27T12:52:35.602108773Z",
    resourceName: `projects/${PROJECT}/metrics/${metricName}`,
    metricDescriptor: {
      ...descriptor,
      name: `projects/${PROJECT}/metricDescriptors/logging.googleapis.com/user/${metricName}`,
      type: `logging.googleapis.com/user/${metricName}`,
      unit: "1",
    },
  });
}

const HEALTHY_SCALING_SOURCE = `
export const RUNTIME_SA = {
  aiRuntime: \`fn-ai-runtime@\${projectId()}.iam.gserviceaccount.com\`,
} as const;
export const APP_CHECK_ENFORCED_AI =
  envFlagFailClosed("APP_CHECK_ENFORCED_AI") || APP_CHECK_ENFORCED;
export const AI_METERED = {
  enforceAppCheck: APP_CHECK_ENFORCED_AI,
  serviceAccount: RUNTIME_SA.aiRuntime,
};
`;

function healthyCallableSource(callable: string): string {
  return `
export const ${callable} = onCall(AI_METERED, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "x");
  enforceNonAnonymousForAi(signInProvider(request));
  await enforceAiGatewayEnabled("${callable}");
  return {};
});
`;
}

const AI_SOURCE_PATHS: Record<string, string> = {
  aiCoachAdvice: "functions/src/ai_coach_advice.ts",
  aiEquipmentRecognition: "functions/src/ai_equipment_recognition.ts",
  aiMachineDescription: "functions/src/ai_machine_description.ts",
  aiExerciseGeneration: "functions/src/ai_exercise_generation.ts",
  analyzeMealPhoto: "functions/src/analyze_meal_photo.ts",
  parseNutritionLabel: "functions/src/parse_nutrition_label.ts",
};
const SCALING_PATH = "functions/src/scaling.ts";

type CommandHandler = (args: string[]) => CommandResult;

function makeDeps(opts: {
  project?: string;
  gcloud?: Partial<Record<string, CommandHandler>>;
  git?: Partial<Record<string, CommandHandler>>;
  evidence?: string | null;
  sourceOverrides?: Partial<Record<string, string | null>>;
  /** Branch returned by `currentBranch`; default is a phase1 branch. */
  branch?: string | null;
  /** When set, `currentBranch` rejects with this error. */
  branchThrows?: Error;
  /** Override for `isCommitOnProtectedLine`; default resolves `true` (HEAD is on the protected line). */
  isCommitOnProtectedLine?: () => Promise<boolean>;
  /** Content of `.firebaserc`; `null` = file missing. Default: production + legacy aliases only. */
  firebaserc?: string | null;
}): ReleaseGuardDeps {
  return {
    project: opts.project ?? PROJECT,
    now: () => Date.parse("2026-08-29T12:00:00.000Z"),
    currentBranch: async () => {
      if (opts.branchThrows) throw opts.branchThrows;
      return opts.branch === undefined ? "phase1/main" : opts.branch;
    },
    isCommitOnProtectedLine: opts.isCommitOnProtectedLine ?? (async () => true),
    readFile: async (path: string) => {
      if (path === FIREBASERC_PATH) return opts.firebaserc === undefined ? DEFAULT_FIREBASERC : opts.firebaserc;
      if (path === RELEASE_EVIDENCE_PATH) return opts.evidence === undefined ? HEALTHY_EVIDENCE : opts.evidence;
      if (opts.sourceOverrides && path in opts.sourceOverrides) return opts.sourceOverrides[path] ?? null;
      if (path === SCALING_PATH) return HEALTHY_SCALING_SOURCE;
      for (const [callable, p] of Object.entries(AI_SOURCE_PATHS)) {
        if (path === p) return healthyCallableSource(callable);
      }
      return null;
    },
    runCommand: async (cmd: string, args: string[]) => {
      if (cmd === "gcloud") {
        if (args[0] === "functions" && args[1] === "list") {
          return (opts.gcloud?.functionsList ?? (() => ({ ok: true, stdout: functionsListJson(), stderr: "" })))(args);
        }
        if (args[0] === "functions" && args[1] === "describe") {
          const fnName = args[2];
          const handler = opts.gcloud?.[`describe:${fnName}`] ?? opts.gcloud?.describeDefault;
          return (handler ?? (() => ({ ok: true, stdout: functionDescribeJson(), stderr: "" })))(args);
        }
        if (args[0] === "secrets" && args[1] === "describe") {
          return (opts.gcloud?.secretDescribe ?? (() => ({ ok: true, stdout: JSON.stringify({ name: "x" }), stderr: "" })))(args);
        }
        if (args[0] === "secrets" && args[1] === "get-iam-policy") {
          return (opts.gcloud?.secretIamPolicy ?? (() => ({ ok: true, stdout: HEALTHY_SECRET_IAM_POLICY, stderr: "" })))(args);
        }
        if (args[0] === "secrets" && args[1] === "versions" && args[2] === "access") {
          return (opts.gcloud?.secretAccess ?? (() => ({ ok: true, stdout: HEALTHY_KILL_SWITCH_PAYLOAD, stderr: "" })))(args);
        }
        if (args[0] === "projects" && args[1] === "get-iam-policy") {
          return (opts.gcloud?.projectIamPolicy ?? (() => ({ ok: true, stdout: HEALTHY_PROJECT_IAM_POLICY, stderr: "" })))(args);
        }
        if (args[0] === "iam" && args[1] === "roles" && args[2] === "describe") {
          const handler = opts.gcloud?.[`roleDescribe:${args[3]}`] ?? opts.gcloud?.roleDescribeDefault;
          return (handler ?? (() => ({ ok: true, stdout: JSON.stringify({ includedPermissions: [] }), stderr: "" })))(args);
        }
        if (args[0] === "logging" && args[1] === "metrics" && args[2] === "describe") {
          const metricName = args[3];
          const handler = opts.gcloud?.[`metricDescribe:${metricName}`] ?? opts.gcloud?.metricDescribeDefault;
          return (handler ?? (() => ({ ok: true, stdout: healthyLiveMetricJson(metricName), stderr: "" })))(args);
        }
        if (args[0] === "logging" && args[1] === "read") {
          return (opts.gcloud?.loggingRead ?? (() => ({ ok: true, stdout: JSON.stringify([{ x: 1 }]), stderr: "" })))(args);
        }
        throw new Error(`unexpected gcloud invocation in test: ${args.join(" ")}`);
      }
      if (cmd === "git") {
        if (args[0] === "status") {
          return (opts.git?.status ?? (() => ({ ok: true, stdout: "", stderr: "" })))(args);
        }
        if (args[0] === "rev-parse") {
          return (opts.git?.revParse ?? (() => ({ ok: true, stdout: "abc1234\n", stderr: "" })))(args);
        }
        throw new Error(`unexpected git invocation in test: ${args.join(" ")}`);
      }
      throw new Error(`unexpected command in test: ${cmd}`);
    },
  };
}

const byName = (r: Awaited<ReturnType<typeof runReleaseGuard>>, name: string) =>
  r.checks.find((c) => c.name === name)!;

const DEPLOY_TARGET_CHECK = "Deploy target is this project's real Firebase project";
const CANDIDATE_INVARIANTS_CHECK = "Candidate source still carries its App Check / anonymous-refusal / gateway-guard wiring (AST-verified)";
const KILL_SWITCH_CHECK = "Step 8 kill switch secret exists with genuinely read-only runtime IAM";
const OBSERVABILITY_CHECK = "AI Gateway observability metrics exist, match source, and are producing";
const S23_CHECK = "S23 production Play Integrity proof gates an AI-enabled release";
const PROVENANCE_CHECK = "Release comes from a clean, committed working tree";

describe("runReleaseGuard", () => {
  test("PASS when every invariant genuinely holds", async () => {
    const result = await runReleaseGuard(makeDeps({}));
    expect(result.verdict).toBe("PASS");
    expect(result.checks.every((c) => c.status === "OK")).toBe(true);
    expect(result.checks).toHaveLength(10);
  });

  test("deploy target FAILED when the resolved project is not this project's real one", async () => {
    const result = await runReleaseGuard(makeDeps({ project: "legacy-shared-alias-target" }));
    const check = byName(result, DEPLOY_TARGET_CHECK);
    expect(check.status).toBe("FAILED");
    expect(check.detail).toContain("legacy-shared-alias-target");
    expect(result.verdict).toBe("BLOCK");
  });

  test("candidate invariants FAILED when AI_METERED no longer wires enforceAppCheck", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        sourceOverrides: {
          [SCALING_PATH]: HEALTHY_SCALING_SOURCE.replace(
            "enforceAppCheck: APP_CHECK_ENFORCED_AI,",
            "enforceAppCheck: false,",
          ),
        },
      }),
    );
    const check = byName(result, CANDIDATE_INVARIANTS_CHECK);
    expect(check.status).toBe("FAILED");
    expect(check.detail).toContain("is not wired to APP_CHECK_ENFORCED_AI");
  });

  test("candidate invariants FAILED when a callable drops enforceNonAnonymousForAi", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        sourceOverrides: {
          [AI_SOURCE_PATHS.aiCoachAdvice]: healthyCallableSource("aiCoachAdvice").replace(
            "enforceNonAnonymousForAi(signInProvider(request));",
            "",
          ),
        },
      }),
    );
    const check = byName(result, CANDIDATE_INVARIANTS_CHECK);
    expect(check.status).toBe("FAILED");
    expect(check.detail).toContain("no real enforceNonAnonymousForAi(...) call in the handler body");
  });

  test("candidate invariants FAILED when a callable drops enforceAiGatewayEnabled", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        sourceOverrides: {
          [AI_SOURCE_PATHS.aiExerciseGeneration]: healthyCallableSource("aiExerciseGeneration").replace(
            'await enforceAiGatewayEnabled("aiExerciseGeneration");',
            "",
          ),
        },
      }),
    );
    const check = byName(result, CANDIDATE_INVARIANTS_CHECK);
    expect(check.status).toBe("FAILED");
    expect(check.detail).toContain("no real enforceAiGatewayEnabled(...) call in the handler body");
  });

  test("candidate invariants FAILED when a callable is no longer declared onCall(AI_METERED, ...)", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        sourceOverrides: {
          [AI_SOURCE_PATHS.aiMachineDescription]: healthyCallableSource("aiMachineDescription").replace(
            "onCall(AI_METERED,",
            "onCall(INTERACTIVE,",
          ),
        },
      }),
    );
    const check = byName(result, CANDIDATE_INVARIANTS_CHECK);
    expect(check.status).toBe("FAILED");
    expect(check.detail).toContain("no longer declared as onCall(AI_METERED, ...)");
  });

  test("candidate invariants UNAVAILABLE when scaling.ts cannot be read", async () => {
    const result = await runReleaseGuard(makeDeps({ sourceOverrides: { [SCALING_PATH]: null } }));
    expect(byName(result, CANDIDATE_INVARIANTS_CHECK).status).toBe("UNAVAILABLE");
  });

  test("candidate invariants FAILED when APP_CHECK_ENFORCED_AI is fail-closed in text only, but its real value is always false -- the exact round-3 GPT-PM bypass: round-1's loose regex only checked envFlagFailClosed(...) appears somewhere in the initializer text, so `&& false` would have passed it", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        sourceOverrides: {
          [SCALING_PATH]: HEALTHY_SCALING_SOURCE.replace(
            'envFlagFailClosed("APP_CHECK_ENFORCED_AI") || APP_CHECK_ENFORCED;',
            'envFlagFailClosed("APP_CHECK_ENFORCED_AI") && false;',
          ),
        },
      }),
    );
    const check = byName(result, CANDIDATE_INVARIANTS_CHECK);
    expect(check.status).toBe("FAILED");
    expect(check.detail).toContain("is not exactly envFlagFailClosed(\"APP_CHECK_ENFORCED_AI\") || APP_CHECK_ENFORCED");
  });

  test("candidate invariants FAILED when RUNTIME_SA.aiRuntime's own definition no longer resolves to a real fn-ai-runtime service account -- round-3 GPT-PM MAJOR: round-1/2 only checked the CONSUMER reference (AI_METERED.serviceAccount === RUNTIME_SA.aiRuntime), never the definition site", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        sourceOverrides: {
          [SCALING_PATH]: HEALTHY_SCALING_SOURCE.replace(
            "aiRuntime: `fn-ai-runtime@${projectId()}.iam.gserviceaccount.com`,",
            'aiRuntime: "fn-some-other-account@wrong-project.iam.gserviceaccount.com",',
          ),
        },
      }),
    );
    const check = byName(result, CANDIDATE_INVARIANTS_CHECK);
    expect(check.status).toBe("FAILED");
    expect(check.detail).toContain("RUNTIME_SA.aiRuntime does not resolve to a real fn-ai-runtime@<project>.iam.gserviceaccount.com template");
  });

  test("candidate invariants FAILED when enforceNonAnonymousForAi survives only as a comment -- the exact round-2 GPT-PM bypass: round-1's substring check would have passed this", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        sourceOverrides: {
          [AI_SOURCE_PATHS.aiCoachAdvice]: healthyCallableSource("aiCoachAdvice").replace(
            "enforceNonAnonymousForAi(signInProvider(request));",
            "// enforceNonAnonymousForAi(signInProvider(request));",
          ),
        },
      }),
    );
    const check = byName(result, CANDIDATE_INVARIANTS_CHECK);
    expect(check.status).toBe("FAILED");
    expect(check.detail).toContain("no real enforceNonAnonymousForAi(...) call in the handler body");
  });

  test("candidate invariants FAILED when enforceAiGatewayEnabled survives only inside a dead-code string literal", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        sourceOverrides: {
          [AI_SOURCE_PATHS.aiExerciseGeneration]: healthyCallableSource("aiExerciseGeneration").replace(
            'await enforceAiGatewayEnabled("aiExerciseGeneration");',
            'const _dead = "await enforceAiGatewayEnabled(\\"aiExerciseGeneration\\")";',
          ),
        },
      }),
    );
    const check = byName(result, CANDIDATE_INVARIANTS_CHECK);
    expect(check.status).toBe("FAILED");
    expect(check.detail).toContain("no real enforceAiGatewayEnabled(...) call in the handler body");
  });

  test("candidate invariants OK when the two guard calls are merely reordered relative to unrelated statements, as long as their own relative order holds", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        sourceOverrides: {
          [AI_SOURCE_PATHS.aiMachineDescription]: `
export const aiMachineDescription = onCall(AI_METERED, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "x");
  const extra = 1;
  enforceNonAnonymousForAi(signInProvider(request));
  const another = 2;
  await enforceAiGatewayEnabled("aiMachineDescription");
  return { extra, another };
});
`,
        },
      }),
    );
    expect(byName(result, CANDIDATE_INVARIANTS_CHECK).status).toBe("OK");
  });

  test("functions inventory FAILED when a callable is missing from fn-ai-runtime", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        gcloud: {
          functionsList: () => ({
            ok: true,
            stdout: JSON.stringify([
              { name: `.../functions/aiCoachAdvice`, serviceConfig: { serviceAccountEmail: RUNTIME_SA } },
            ]),
            stderr: "",
          }),
        },
      }),
    );
    const check = byName(result, "AI callables match the intended fn-ai-runtime deployed set");
    expect(check.status).toBe("FAILED");
    expect(check.detail).toMatch(/missing=/);
    expect(result.verdict).toBe("BLOCK");
  });

  test("functions inventory FAILED when an unexpected function runs as fn-ai-runtime", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        gcloud: {
          functionsList: () => ({
            ok: true,
            stdout: JSON.stringify([
              ...AI_CALLABLES.map((name) => ({ name: `.../functions/${name}`, serviceConfig: { serviceAccountEmail: RUNTIME_SA } })),
              { name: `.../functions/someOtherFn`, serviceConfig: { serviceAccountEmail: RUNTIME_SA } },
            ]),
            stderr: "",
          }),
        },
      }),
    );
    const check = byName(result, "AI callables match the intended fn-ai-runtime deployed set");
    expect(check.status).toBe("FAILED");
    expect(check.detail).toMatch(/extra=\[someOtherFn\]/);
  });

  test("functions inventory UNAVAILABLE when gcloud functions list fails", async () => {
    const result = await runReleaseGuard(
      makeDeps({ gcloud: { functionsList: () => ({ ok: false, stdout: "", stderr: "auth error" }) } }),
    );
    expect(byName(result, "AI callables match the intended fn-ai-runtime deployed set").status).toBe("UNAVAILABLE");
  });

  test("App Check FAILED when APP_CHECK_ENFORCED_AI is the literal string false", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        gcloud: {
          "describe:aiEquipmentRecognition": () => ({
            ok: true,
            stdout: functionDescribeJson({ APP_CHECK_ENFORCED_AI: "false" }),
            stderr: "",
          }),
        },
      }),
    );
    const check = byName(result, "App Check enforcement is on (fail-closed) for all 6 AI callables");
    expect(check.status).toBe("FAILED");
    expect(check.detail).toContain("aiEquipmentRecognition");
  });

  test("App Check OK when APP_CHECK_ENFORCED_AI is simply absent (fail-closed default)", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        gcloud: {
          describeDefault: () => ({
            ok: true,
            stdout: JSON.stringify({
              serviceConfig: { serviceAccountEmail: RUNTIME_SA, environmentVariables: {} },
            }),
            stderr: "",
          }),
        },
      }),
    );
    expect(byName(result, "App Check enforcement is on (fail-closed) for all 6 AI callables").status).toBe("OK");
  });

  test("App Check OK when APP_CHECK_ENFORCED_AI is off but APP_CHECK_ENFORCED covers it", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        gcloud: {
          describeDefault: () => ({
            ok: true,
            stdout: JSON.stringify({
              serviceConfig: {
                serviceAccountEmail: RUNTIME_SA,
                environmentVariables: { APP_CHECK_ENFORCED_AI: "false", APP_CHECK_ENFORCED: "true" },
              },
            }),
            stderr: "",
          }),
        },
      }),
    );
    expect(byName(result, "App Check enforcement is on (fail-closed) for all 6 AI callables").status).toBe("OK");
  });

  test("anonymous-refusal FAILED when AI_ALLOW_ANONYMOUS=true on any callable", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        gcloud: {
          "describe:aiMachineDescription": () => ({
            ok: true,
            stdout: functionDescribeJson({ AI_ALLOW_ANONYMOUS: "true" }),
            stderr: "",
          }),
        },
      }),
    );
    const check = byName(result, "Anonymous callers are refused on all 6 AI callables");
    expect(check.status).toBe("FAILED");
    expect(check.detail).toContain("aiMachineDescription");
  });

  test("App Check and anonymous checks both UNAVAILABLE when describe fails for any callable", async () => {
    const result = await runReleaseGuard(
      makeDeps({ gcloud: { "describe:aiExerciseGeneration": () => ({ ok: false, stdout: "", stderr: "not found" }) } }),
    );
    expect(byName(result, "App Check enforcement is on (fail-closed) for all 6 AI callables").status).toBe("UNAVAILABLE");
    expect(byName(result, "Anonymous callers are refused on all 6 AI callables").status).toBe("UNAVAILABLE");
  });

  test("kill switch FAILED when fn-ai-runtime lacks secretAccessor entirely", async () => {
    const result = await runReleaseGuard(
      makeDeps({ gcloud: { secretIamPolicy: () => ({ ok: true, stdout: JSON.stringify({ bindings: [] }), stderr: "" }) } }),
    );
    const check = byName(result, KILL_SWITCH_CHECK);
    expect(check.status).toBe("FAILED");
    expect(check.detail).toMatch(/lacks roles\/secretmanager\.secretAccessor/);
  });

  test("kill switch FAILED when fn-ai-runtime holds a write-capable role at the secret level (the exact round-1 Step-8 defect)", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        gcloud: {
          secretIamPolicy: () => ({
            ok: true,
            stdout: JSON.stringify({
              bindings: [
                { role: "roles/secretmanager.secretAccessor", members: [`serviceAccount:${RUNTIME_SA}`] },
                { role: "roles/secretmanager.admin", members: [`serviceAccount:${RUNTIME_SA}`] },
              ],
            }),
            stderr: "",
          }),
        },
      }),
    );
    const check = byName(result, KILL_SWITCH_CHECK);
    expect(check.status).toBe("FAILED");
    expect(check.detail).toContain("roles/secretmanager.admin");
  });

  test("kill switch FAILED when fn-ai-runtime holds secretmanager.editor -- the round-1 MAJOR: this role was missing from the old denylist", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        gcloud: {
          secretIamPolicy: () => ({
            ok: true,
            stdout: JSON.stringify({
              bindings: [
                { role: "roles/secretmanager.secretAccessor", members: [`serviceAccount:${RUNTIME_SA}`] },
                { role: "roles/secretmanager.editor", members: [`serviceAccount:${RUNTIME_SA}`] },
              ],
            }),
            stderr: "",
          }),
        },
      }),
    );
    const check = byName(result, KILL_SWITCH_CHECK);
    expect(check.status).toBe("FAILED");
    expect(check.detail).toContain("roles/secretmanager.editor");
  });

  test("kill switch FAILED when a write-capable role is granted at the PROJECT level instead of the secret level", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        gcloud: {
          projectIamPolicy: () => ({
            ok: true,
            stdout: JSON.stringify({
              bindings: [{ role: "roles/editor", members: [`serviceAccount:${RUNTIME_SA}`] }],
            }),
            stderr: "",
          }),
        },
      }),
    );
    const check = byName(result, KILL_SWITCH_CHECK);
    expect(check.status).toBe("FAILED");
    expect(check.detail).toContain("roles/editor");
    expect(check.detail).toContain("secret- or project-level");
  });

  test("kill switch FAILED when an unrecognized CUSTOM role resolves to a dangerous secret permission", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        gcloud: {
          projectIamPolicy: () => ({
            ok: true,
            stdout: JSON.stringify({
              bindings: [
                {
                  role: `projects/${PROJECT}/roles/sneakyCustomRole`,
                  members: [`serviceAccount:${RUNTIME_SA}`],
                },
              ],
            }),
            stderr: "",
          }),
          [`roleDescribe:sneakyCustomRole`]: () => ({
            ok: true,
            stdout: JSON.stringify({ includedPermissions: ["secretmanager.versions.add"] }),
            stderr: "",
          }),
        },
      }),
    );
    const check = byName(result, KILL_SWITCH_CHECK);
    expect(check.status).toBe("FAILED");
    expect(check.detail).toContain("sneakyCustomRole");
    expect(check.detail).toContain("secretmanager.versions.add");
  });

  test("kill switch OK when an unrecognized CUSTOM role resolves to only harmless permissions (this project's own fitness.vertexPredictor)", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        gcloud: {
          projectIamPolicy: () => ({
            ok: true,
            stdout: JSON.stringify({
              bindings: [
                {
                  role: `projects/${PROJECT}/roles/fitness.vertexPredictor`,
                  members: [`serviceAccount:${RUNTIME_SA}`],
                },
              ],
            }),
            stderr: "",
          }),
          [`roleDescribe:fitness.vertexPredictor`]: () => ({
            ok: true,
            stdout: JSON.stringify({ includedPermissions: ["aiplatform.endpoints.predict"] }),
            stderr: "",
          }),
        },
      }),
    );
    expect(byName(result, KILL_SWITCH_CHECK).status).toBe("OK");
  });

  test("kill switch FAILED when an unrecognized role grants resourcemanager.projects.setIamPolicy -- round-2 GPT-PM MAJOR: the runtime could grant itself a write-capable secret role", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        gcloud: {
          projectIamPolicy: () => ({
            ok: true,
            stdout: JSON.stringify({
              bindings: [{ role: "roles/resourcemanager.projectIamAdmin", members: [`serviceAccount:${RUNTIME_SA}`] }],
            }),
            stderr: "",
          }),
          "roleDescribe:roles/resourcemanager.projectIamAdmin": () => ({
            ok: true,
            stdout: JSON.stringify({
              includedPermissions: ["resourcemanager.projects.getIamPolicy", "resourcemanager.projects.setIamPolicy"],
            }),
            stderr: "",
          }),
        },
      }),
    );
    const check = byName(result, KILL_SWITCH_CHECK);
    expect(check.status).toBe("FAILED");
    expect(check.detail).toContain("resourcemanager.projects.setIamPolicy");
  });

  test("kill switch UNAVAILABLE when an unrecognized role's permissions cannot be resolved", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        gcloud: {
          projectIamPolicy: () => ({
            ok: true,
            stdout: JSON.stringify({
              bindings: [{ role: "roles/someUnlistedRole", members: [`serviceAccount:${RUNTIME_SA}`] }],
            }),
            stderr: "",
          }),
          roleDescribeDefault: () => ({ ok: false, stdout: "", stderr: "NOT_FOUND" }),
        },
      }),
    );
    expect(byName(result, KILL_SWITCH_CHECK).status).toBe("UNAVAILABLE");
  });

  test("kill switch UNAVAILABLE when the secret does not exist", async () => {
    const result = await runReleaseGuard(
      makeDeps({ gcloud: { secretDescribe: () => ({ ok: false, stdout: "", stderr: "NOT_FOUND" }) } }),
    );
    expect(byName(result, KILL_SWITCH_CHECK).status).toBe("UNAVAILABLE");
  });

  test("kill switch UNAVAILABLE when the project-level IAM policy cannot be read", async () => {
    const result = await runReleaseGuard(
      makeDeps({ gcloud: { projectIamPolicy: () => ({ ok: false, stdout: "", stderr: "PERMISSION_DENIED" }) } }),
    );
    expect(byName(result, KILL_SWITCH_CHECK).status).toBe("UNAVAILABLE");
  });

  test("Step 8 drill evidence UNAVAILABLE when the evidence file is missing", async () => {
    const result = await runReleaseGuard(makeDeps({ evidence: null }));
    expect(byName(result, "Step 8 kill-switch drill evidence recorded as closed").status).toBe("UNAVAILABLE");
  });

  test("S23 gate is ALSO UNAVAILABLE on missing evidence, but only when the kill switch is enabled", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        evidence: null,
        gcloud: { secretAccess: () => ({ ok: true, stdout: JSON.stringify({ enabled: true }), stderr: "" }) },
      }),
    );
    expect(byName(result, S23_CHECK).status).toBe("UNAVAILABLE");
  });

  test("Step 8 drill evidence FAILED when status is not exactly \"closed\"", async () => {
    const result = await runReleaseGuard(
      makeDeps({ evidence: JSON.stringify({ step8KillSwitch: { status: "pending" }, s23PlayIntegrityProof: { status: "closed" } }) }),
    );
    const check = byName(result, "Step 8 kill-switch drill evidence recorded as closed");
    expect(check.status).toBe("FAILED");
    expect(check.detail).toContain("pending");
  });

  test("observability UNAVAILABLE when a metric resource does not exist (describe fails)", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        gcloud: {
          "metricDescribe:ai_gateway_latency_ms": () => ({ ok: false, stdout: "", stderr: "NOT_FOUND" }),
        },
      }),
    );
    expect(byName(result, OBSERVABILITY_CHECK).status).toBe("UNAVAILABLE");
  });

  test("observability FAILED when a metric resource exists but its live definition no longer matches source -- round-2 GPT-PM MAJOR: existence alone does not prove the filter/extractor still match", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        gcloud: {
          "metricDescribe:ai_gateway_calls": () => {
            const drifted = JSON.parse(healthyLiveMetricJson("ai_gateway_calls"));
            drifted.filter = 'jsonPayload.message="something else entirely"';
            return { ok: true, stdout: JSON.stringify(drifted), stderr: "" };
          },
        },
      }),
    );
    const check = byName(result, OBSERVABILITY_CHECK);
    expect(check.status).toBe("FAILED");
    expect(check.detail).toContain("ai_gateway_calls");
    expect(check.detail).toContain("no longer matches the source-controlled definition");
  });

  test("observability OK when a metric's labels come back in a different order live -- GCP does not guarantee label array order (confirmed live on ai_gateway_latency_ms), so this must not be treated as drift", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        gcloud: {
          "metricDescribe:ai_gateway_calls": () => {
            const reordered = JSON.parse(healthyLiveMetricJson("ai_gateway_calls"));
            reordered.metricDescriptor.labels = [...reordered.metricDescriptor.labels].reverse();
            return { ok: true, stdout: JSON.stringify(reordered), stderr: "" };
          },
        },
      }),
    );
    expect(byName(result, OBSERVABILITY_CHECK).status).toBe("OK");
  });

  test("observability OK when a metric's live definition matches source even with GCP-only fields (createTime/type/unit) differing", async () => {
    // healthyLiveMetricJson already includes those GCP-only fields with
    // fixture values -- this test just documents that the comparison
    // deliberately ignores them (they have no source-side counterpart).
    const result = await runReleaseGuard(makeDeps({}));
    expect(byName(result, OBSERVABILITY_CHECK).status).toBe("OK");
  });

  test("observability FAILED when all 4 metric resources exist but no call event exists in the last 30 days", async () => {
    const result = await runReleaseGuard(
      makeDeps({ gcloud: { loggingRead: () => ({ ok: true, stdout: "[]", stderr: "" }) } }),
    );
    const check = byName(result, OBSERVABILITY_CHECK);
    expect(check.status).toBe("FAILED");
    expect(check.detail).toContain("not producing");
  });

  test("observability UNAVAILABLE when gcloud logging read fails", async () => {
    const result = await runReleaseGuard(
      makeDeps({ gcloud: { loggingRead: () => ({ ok: false, stdout: "", stderr: "permission denied" }) } }),
    );
    expect(byName(result, OBSERVABILITY_CHECK).status).toBe("UNAVAILABLE");
  });

  test("S23 gate OK when the kill switch is disabled, even though S23 is open -- the DoD's own carve-out", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        gcloud: { secretAccess: () => ({ ok: true, stdout: JSON.stringify({ enabled: false }), stderr: "" }) },
        evidence: JSON.stringify({ step8KillSwitch: { status: "closed" }, s23PlayIntegrityProof: { status: "open" } }),
      }),
    );
    expect(byName(result, S23_CHECK).status).toBe("OK");
  });

  test("S23 gate FAILED when the kill switch is enabled and S23 is still open -- the actual current live state", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        gcloud: { secretAccess: () => ({ ok: true, stdout: JSON.stringify({ enabled: true }), stderr: "" }) },
        evidence: JSON.stringify({ step8KillSwitch: { status: "closed" }, s23PlayIntegrityProof: { status: "open" } }),
      }),
    );
    const check = byName(result, S23_CHECK);
    expect(check.status).toBe("FAILED");
    expect(result.verdict).toBe("BLOCK");
  });

  test("S23 gate OK when the kill switch is enabled and S23 is closed", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        gcloud: { secretAccess: () => ({ ok: true, stdout: JSON.stringify({ enabled: true }), stderr: "" }) },
        evidence: JSON.stringify({ step8KillSwitch: { status: "closed" }, s23PlayIntegrityProof: { status: "closed" } }),
      }),
    );
    expect(byName(result, S23_CHECK).status).toBe("OK");
  });

  test("S23 gate UNAVAILABLE when the live kill-switch payload cannot be read", async () => {
    const result = await runReleaseGuard(
      makeDeps({ gcloud: { secretAccess: () => ({ ok: false, stdout: "", stderr: "PERMISSION_DENIED" }) } }),
    );
    expect(byName(result, S23_CHECK).status).toBe("UNAVAILABLE");
  });

  test("source provenance FAILED when the working tree is dirty", async () => {
    const result = await runReleaseGuard(
      makeDeps({ git: { status: () => ({ ok: true, stdout: " M functions/src/x.ts\n", stderr: "" }) } }),
    );
    expect(byName(result, PROVENANCE_CHECK).status).toBe("FAILED");
  });

  test("source provenance UNAVAILABLE when git status fails", async () => {
    const result = await runReleaseGuard(
      makeDeps({ git: { status: () => ({ ok: false, stdout: "", stderr: "not a git repository" }) } }),
    );
    expect(byName(result, PROVENANCE_CHECK).status).toBe("UNAVAILABLE");
  });

  test("source provenance scopes `git status` to functions/, functions-equipment-identity/, firebase.json, .firebaserc, .gitignore, and the release-evidence file -- not the whole repo -- so unrelated untracked debris elsewhere (old report artifacts) can never permanently block a genuinely clean release", async () => {
    let capturedArgs: string[] = [];
    const result = await runReleaseGuard(
      makeDeps({
        git: {
          status: (args) => {
            capturedArgs = args;
            return { ok: true, stdout: "", stderr: "" };
          },
        },
      }),
    );
    expect(capturedArgs).toEqual([
      "status",
      "--porcelain",
      "--",
      "functions",
      "functions-equipment-identity",
      "firebase.json",
      ".firebaserc",
      ".gitignore",
      RELEASE_EVIDENCE_PATH,
    ]);
    expect(byName(result, PROVENANCE_CHECK).status).toBe("OK");
  });

  test("source provenance still FAILS on a dirty change confined to a scoped path (e.g. functions/) -- the scoping narrows WHERE it looks, not what counts as dirty", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        git: { status: () => ({ ok: true, stdout: " M functions/src/scaling.ts\n", stderr: "" }) },
      }),
    );
    expect(byName(result, PROVENANCE_CHECK).status).toBe("FAILED");
  });

  test("source provenance FAILS on a dirty functions-equipment-identity/ -- round-5 GPT-PM MAJOR: firebase.json's second Functions codebase, deployed alongside the default one by `firebase deploy --only functions`, was originally outside the scoped provenance check entirely", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        git: { status: () => ({ ok: true, stdout: " M functions-equipment-identity/src/index.ts\n", stderr: "" }) },
      }),
    );
    expect(byName(result, PROVENANCE_CHECK).status).toBe("FAILED");
  });

  test("source provenance FAILS on a dirty .firebaserc -- round-5 GPT-PM MAJOR: an uncommitted project-alias change is itself unreviewed deploy configuration, not just something checkDeployTarget's resolved-project check alone should catch", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        git: { status: () => ({ ok: true, stdout: " M .firebaserc\n", stderr: "" }) },
      }),
    );
    expect(byName(result, PROVENANCE_CHECK).status).toBe("FAILED");
  });

  test("source provenance FAILS on a dirty root .gitignore -- round-5 GPT-PM MAJOR: an uncommitted ignore-rule change could otherwise make a real dirty file under a scoped path invisible to this very check", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        git: { status: () => ({ ok: true, stdout: " M .gitignore\n", stderr: "" }) },
      }),
    );
    expect(byName(result, PROVENANCE_CHECK).status).toBe("FAILED");
  });

  test("source provenance FAILS on a modified functions/.gcloudignore -- round-6 GPT-PM MAJOR: gitignoring it (the first attempted fix) made it permanently invisible to this check instead of merely quiet when clean; tracking it as a real committed file means a mutation is caught like any other file under functions/", async () => {
    const result = await runReleaseGuard(
      makeDeps({
        git: { status: () => ({ ok: true, stdout: " M functions/.gcloudignore\n", stderr: "" }) },
      }),
    );
    expect(byName(result, PROVENANCE_CHECK).status).toBe("FAILED");
  });

  test("verdict is BLOCK if even one check is not OK, regardless of how many others pass", async () => {
    const result = await runReleaseGuard(
      makeDeps({ git: { revParse: () => ({ ok: false, stdout: "", stderr: "fatal" }) } }),
    );
    expect(result.checks.filter((c) => c.status === "OK")).toHaveLength(9);
    expect(result.verdict).toBe("BLOCK");
  });
});

describe("deploy line classification (S00 backend separation gate)", () => {
  test.each([
    ["phase2/s00-split-docs", "phase2"],
    ["phase2/x", "phase2"],
    ["  phase2/padded  ", "phase2"],
    ["phase1/main", "phase1"],
    ["master", "phase1"],
    ["phase1/x", "phase1"],
    ["phase1/hotfix/deep", "phase1"],
    ["feature/x", "other"],
    ["main", "other"],
    ["HEAD", "other"],
    ["", "other"],
    ["   ", "other"],
    ["phase2", "other"],
    ["phase1", "other"],
    ["Phase2/x", "other"],
    ["release/phase2/x", "other"],
    [null, "other"],
  ] as const)("classifyDeployLine(%j) = %s", (branch, expected) => {
    expect(classifyDeployLine(branch)).toBe(expected);
  });

  test("DEPLOY_LINE_REASONS is exactly the closed set of seven slugs", () => {
    expect([...DEPLOY_LINE_REASONS]).toEqual([
      "deploy-line-unknown",
      "phase1-wrong-project",
      "firebaserc-unreadable",
      "phase2-alias-missing",
      "phase2-targets-production",
      "phase2-project-mismatch",
      "phase1-provenance-unverified",
    ]);
  });

  test("PROJECT_RESOLUTION_REASONS is exactly the closed set of two slugs", () => {
    expect([...PROJECT_RESOLUTION_REASONS]).toEqual(["project-undeterminable", "project-conflict"]);
  });

  test("PROTECTED_PHASE1_REFS names exactly the two protected remote-tracking refs", () => {
    expect([...PROTECTED_PHASE1_REFS]).toEqual([
      "refs/remotes/origin/phase1/main",
      "refs/remotes/origin/master",
    ]);
  });
});

describe("checkDeployTarget / resolveDeployTarget by deploy line", () => {
  const phase2Rc = firebasercWith({
    default: EXPECTED_PROJECT_ID,
    "legacy-shared": LEGACY_PROJECT_ID,
    [PHASE2_ALIAS]: PHASE2_PROJECT,
  });

  function slugOf(detail: string): string {
    return detail.split(":")[0];
  }

  // ---- PASS paths
  test("PASS: phase1 line + production project", async () => {
    const check = await checkDeployTarget(makeDeps({ branch: "phase1/main", project: EXPECTED_PROJECT_ID }));
    expect(check.status).toBe("OK");
    expect(check.detail).toBe(`line = phase1, project = ${EXPECTED_PROJECT_ID}`);
  });

  test("PASS: master is phase1 and may deploy to production", async () => {
    const check = await checkDeployTarget(makeDeps({ branch: "master" }));
    expect(check.status).toBe("OK");
  });

  test("PASS: phase2 line + the project behind alias phase2", async () => {
    const check = await checkDeployTarget(
      makeDeps({ branch: "phase2/s00-split-docs", project: PHASE2_PROJECT, firebaserc: phase2Rc }),
    );
    expect(check.status).toBe("OK");
    expect(check.detail).toBe(`line = phase2, project = ${PHASE2_PROJECT}`);
  });

  test("resolveDeployTarget returns the allowed project per line", async () => {
    const p1 = await resolveDeployTarget(makeDeps({ branch: "phase1/x" }));
    expect(p1).toEqual({ ok: true, line: "phase1", branch: "phase1/x", allowedProject: EXPECTED_PROJECT_ID });
    const p2 = await resolveDeployTarget(makeDeps({ branch: "phase2/x", firebaserc: phase2Rc }));
    expect(p2).toEqual({ ok: true, line: "phase2", branch: "phase2/x", allowedProject: PHASE2_PROJECT });
  });

  // ---- deploy-line-unknown
  test.each(["feature/x", "HEAD", "", "main"])("deploy-line-unknown for branch %j", async (branch) => {
    const check = await checkDeployTarget(makeDeps({ branch }));
    expect(check.status).toBe("FAILED");
    expect(slugOf(check.detail)).toBe("deploy-line-unknown");
    expect(check.detail).toContain(JSON.stringify(branch));
  });

  test("deploy-line-unknown when the branch cannot be read (null)", async () => {
    const check = await checkDeployTarget(makeDeps({ branch: null }));
    expect(check.status).toBe("FAILED");
    expect(slugOf(check.detail)).toBe("deploy-line-unknown");
    expect(check.detail).toContain("could not be read");
  });

  test("deploy-line-unknown when currentBranch throws (fails closed, does not propagate)", async () => {
    const deps = makeDeps({ branchThrows: new Error("git exploded") });
    const resolved = await resolveDeployTarget(deps);
    expect(resolved).toMatchObject({ ok: false, line: "other", branch: null, reason: "deploy-line-unknown" });
    const check = await checkDeployTarget(deps);
    expect(check.status).toBe("FAILED");
    expect(slugOf(check.detail)).toBe("deploy-line-unknown");
  });

  // ---- phase1-wrong-project
  test.each([LEGACY_PROJECT_ID, PHASE2_PROJECT, "anything-else"])(
    "phase1-wrong-project when the phase1 line targets %s",
    async (project) => {
      const check = await checkDeployTarget(makeDeps({ branch: "phase1/main", project }));
      expect(check.status).toBe("FAILED");
      expect(slugOf(check.detail)).toBe("phase1-wrong-project");
      expect(check.detail).toContain(`"${project}"`);
      expect(check.detail).toContain(`"${EXPECTED_PROJECT_ID}"`);
    },
  );

  test("phase1 line cannot deploy to the phase2 project even when .firebaserc defines it", async () => {
    const check = await checkDeployTarget(
      makeDeps({ branch: "phase1/main", project: PHASE2_PROJECT, firebaserc: phase2Rc }),
    );
    expect(slugOf(check.detail)).toBe("phase1-wrong-project");
  });

  // ---- firebaserc-unreadable
  test.each([
    ["missing file", null],
    ["bad JSON", "{not json"],
    ["empty file", ""],
    ["JSON null", "null"],
    ["JSON array root", "[]"],
    ["no projects object", JSON.stringify({ other: 1 })],
    ["projects is a string", JSON.stringify({ projects: "x" })],
    ["projects is null", JSON.stringify({ projects: null })],
  ] as const)("firebaserc-unreadable on phase2 line: %s", async (_label, firebaserc) => {
    const check = await checkDeployTarget(makeDeps({ branch: "phase2/x", project: PHASE2_PROJECT, firebaserc }));
    expect(check.status).toBe("FAILED");
    expect(slugOf(check.detail)).toBe("firebaserc-unreadable");
  });

  test("a missing .firebaserc does NOT matter on the phase1 line (it is not consulted)", async () => {
    const check = await checkDeployTarget(makeDeps({ branch: "phase1/main", firebaserc: null }));
    expect(check.status).toBe("OK");
  });

  // ---- phase2-alias-missing
  test.each([
    ["absent", firebasercWith({ default: EXPECTED_PROJECT_ID })],
    ["non-string (number)", firebasercWith({ [PHASE2_ALIAS]: 42 })],
    ["non-string (object)", firebasercWith({ [PHASE2_ALIAS]: { id: PHASE2_PROJECT } })],
    ["null", firebasercWith({ [PHASE2_ALIAS]: null })],
    ["empty string", firebasercWith({ [PHASE2_ALIAS]: "" })],
    ["blank string", firebasercWith({ [PHASE2_ALIAS]: "   " })],
    ["empty projects map", firebasercWith({})],
  ] as const)("phase2-alias-missing when alias phase2 is %s", async (_label, firebaserc) => {
    const check = await checkDeployTarget(makeDeps({ branch: "phase2/x", project: PHASE2_PROJECT, firebaserc }));
    expect(check.status).toBe("FAILED");
    expect(slugOf(check.detail)).toBe("phase2-alias-missing");
  });

  // ---- phase2-targets-production
  test.each([
    ["the production id", firebasercWith({ default: EXPECTED_PROJECT_ID, [PHASE2_ALIAS]: EXPECTED_PROJECT_ID })],
    ["the production id with no other aliases", firebasercWith({ [PHASE2_ALIAS]: EXPECTED_PROJECT_ID })],
    ["the legacy id", firebasercWith({ "legacy-shared": LEGACY_PROJECT_ID, [PHASE2_ALIAS]: LEGACY_PROJECT_ID })],
    ["the legacy id with no legacy alias", firebasercWith({ [PHASE2_ALIAS]: LEGACY_PROJECT_ID })],
    ["another alias's id", firebasercWith({ staging: "shared-staging", [PHASE2_ALIAS]: "shared-staging" })],
  ] as const)("phase2-targets-production when alias phase2 equals %s", async (_label, firebaserc) => {
    const resolved = await resolveDeployTarget(makeDeps({ branch: "phase2/x", firebaserc }));
    expect(resolved).toMatchObject({ ok: false, line: "phase2", reason: "phase2-targets-production" });
    const check = await checkDeployTarget(makeDeps({ branch: "phase2/x", project: PHASE2_PROJECT, firebaserc }));
    expect(check.status).toBe("FAILED");
    expect(slugOf(check.detail)).toBe("phase2-targets-production");
  });

  test("phase2-targets-production even when deps.project equals the production id (cannot be satisfied by matching)", async () => {
    const check = await checkDeployTarget(
      makeDeps({
        branch: "phase2/x",
        project: EXPECTED_PROJECT_ID,
        firebaserc: firebasercWith({ [PHASE2_ALIAS]: EXPECTED_PROJECT_ID }),
      }),
    );
    expect(check.status).toBe("FAILED");
    expect(slugOf(check.detail)).toBe("phase2-targets-production");
  });

  // ---- phase2-project-mismatch
  test.each([EXPECTED_PROJECT_ID, LEGACY_PROJECT_ID, "some-other-project"])(
    "phase2-project-mismatch when phase2 line targets %s instead of the alias project",
    async (project) => {
      const check = await checkDeployTarget(makeDeps({ branch: "phase2/x", project, firebaserc: phase2Rc }));
      expect(check.status).toBe("FAILED");
      expect(slugOf(check.detail)).toBe("phase2-project-mismatch");
      expect(check.detail).toContain(`"${project}"`);
      expect(check.detail).toContain(`"${PHASE2_PROJECT}"`);
    },
  );

  test("phase2 run with the default project fallback (production id) blocks", async () => {
    // The production project id (what a production-resolving deploy would carry)
    // on a phase2 branch must block. run_release_guard.mjs no longer falls back
    // to a default project (see resolveEffectiveProject), but a CLI that really
    // resolves to production still reaches this check.
    const result = await runReleaseGuard(makeDeps({ branch: "phase2/x", firebaserc: phase2Rc }));
    expect(result.project).toBe(EXPECTED_PROJECT_ID);
    expect(result.verdict).toBe("BLOCK");
    const check = byName(result, DEPLOY_TARGET_CHECK);
    expect(check.status).toBe("FAILED");
    expect(slugOf(check.detail)).toBe("phase2-project-mismatch");
  });

  // ---- runReleaseGuard result fields
  test("runReleaseGuard reports line, branch and project on a phase1 PASS", async () => {
    const result = await runReleaseGuard(makeDeps({ branch: "phase1/main" }));
    expect(result.verdict).toBe("PASS");
    expect(result.line).toBe("phase1");
    expect(result.branch).toBe("phase1/main");
    expect(result.project).toBe(EXPECTED_PROJECT_ID);
  });

  test("runReleaseGuard reports line other / branch null when the branch is unreadable, and BLOCKs", async () => {
    const result = await runReleaseGuard(makeDeps({ branch: null }));
    expect(result.verdict).toBe("BLOCK");
    expect(result.line).toBe("other");
    expect(result.branch).toBeNull();
    expect(slugOf(byName(result, DEPLOY_TARGET_CHECK).detail)).toBe("deploy-line-unknown");
  });

  test("runReleaseGuard reports line phase2 on a phase2 branch", async () => {
    const result = await runReleaseGuard(
      makeDeps({ branch: "phase2/s00", project: PHASE2_PROJECT, firebaserc: phase2Rc }),
    );
    expect(result.line).toBe("phase2");
    expect(result.branch).toBe("phase2/s00");
    expect(result.project).toBe(PHASE2_PROJECT);
    expect(byName(result, DEPLOY_TARGET_CHECK).status).toBe("OK");
  });

  test("every failing deploy-target detail leads with a slug from the closed DEPLOY_LINE_REASONS set", async () => {
    const cases = [
      makeDeps({ branch: "feature/x" }),
      makeDeps({ branch: "phase1/main", project: LEGACY_PROJECT_ID }),
      makeDeps({ branch: "phase2/x", firebaserc: null }),
      makeDeps({ branch: "phase2/x", firebaserc: firebasercWith({}) }),
      makeDeps({ branch: "phase2/x", firebaserc: firebasercWith({ [PHASE2_ALIAS]: EXPECTED_PROJECT_ID }) }),
      makeDeps({ branch: "phase2/x", firebaserc: phase2Rc }),
    ];
    const slugs: string[] = [];
    for (const deps of cases) {
      const check = await checkDeployTarget(deps);
      expect(check.status).toBe("FAILED");
      const slug = slugOf(check.detail);
      expect(DEPLOY_LINE_REASONS as readonly string[]).toContain(slug);
      slugs.push(slug);
    }
    expect(new Set(slugs).size).toBe(6);
  });

  test("the seventh slug (phase1-provenance-unverified) is also a member of the closed set when it fails", async () => {
    const check = await checkDeployTarget(makeDeps({ branch: "phase1/x", isCommitOnProtectedLine: async () => false }));
    expect(check.status).toBe("FAILED");
    expect(DEPLOY_LINE_REASONS as readonly string[]).toContain(slugOf(check.detail));
    expect(slugOf(check.detail)).toBe("phase1-provenance-unverified");
  });

  // ---- no override
  test("no override path: env vars and extra deps fields cannot turn a block into a pass", async () => {
    const names = [
      "GCLOUD_PROJECT",
      "FORCE_DEPLOY",
      "RELEASE_GUARD_OVERRIDE",
      "RELEASE_GUARD_SKIP",
      "DEPLOY_LINE",
      "ALLOW_CROSS_LINE_DEPLOY",
      "FIREBASE_PROJECT",
    ];
    const saved: Record<string, string | undefined> = {};
    for (const n of names) saved[n] = process.env[n];
    try {
      for (const n of names) process.env[n] = "1";
      process.env.GCLOUD_PROJECT = PHASE2_PROJECT;
      process.env.DEPLOY_LINE = "phase2";

      const blocked = makeDeps({ branch: "feature/x" }) as ReleaseGuardDeps & Record<string, unknown>;
      blocked.override = true;
      blocked.force = true;
      blocked.allowCrossLine = true;
      expect((await checkDeployTarget(blocked)).status).toBe("FAILED");
      expect((await runReleaseGuard(blocked)).verdict).toBe("BLOCK");

      const crossLine = makeDeps({ branch: "phase1/main", project: PHASE2_PROJECT });
      expect(slugOf((await checkDeployTarget(crossLine)).detail)).toBe("phase1-wrong-project");

      const prodFromPhase2 = makeDeps({ branch: "phase2/x", firebaserc: phase2Rc });
      expect(slugOf((await checkDeployTarget(prodFromPhase2)).detail)).toBe("phase2-project-mismatch");
    } finally {
      for (const n of names) {
        if (saved[n] === undefined) delete process.env[n];
        else process.env[n] = saved[n];
      }
    }
  });
});

describe("Phase 1 commit provenance (isCommitOnProtectedLine)", () => {
  const slugOf = (detail: string): string => detail.split(":")[0];

  test("PASS: phase1 branch + provenance true -> allowed project is production", async () => {
    const calls = jest.fn(async () => true);
    const resolved = await resolveDeployTarget(makeDeps({ branch: "phase1/x", isCommitOnProtectedLine: calls }));
    expect(resolved).toEqual({ ok: true, line: "phase1", branch: "phase1/x", allowedProject: EXPECTED_PROJECT_ID });
    expect(calls).toHaveBeenCalledTimes(1);
    const check = await checkDeployTarget(makeDeps({ branch: "phase1/x", isCommitOnProtectedLine: calls }));
    expect(check.status).toBe("OK");
    expect(check.detail).toBe(`line = phase1, project = ${EXPECTED_PROJECT_ID}`);
  });

  test.each(["phase1/main", "master", "phase1/x", "phase1/hotfix/deep"])(
    "BLOCK: provenance false on branch %s -> phase1-provenance-unverified",
    async (branch) => {
      const deps = makeDeps({ branch, isCommitOnProtectedLine: async () => false });
      const resolved = await resolveDeployTarget(deps);
      expect(resolved).toMatchObject({ ok: false, line: "phase1", branch, reason: "phase1-provenance-unverified" });
      const check = await checkDeployTarget(deps);
      expect(check.status).toBe("FAILED");
      expect(slugOf(check.detail)).toBe("phase1-provenance-unverified");
      // The operator must be told which refs HEAD has to be contained in.
      for (const ref of PROTECTED_PHASE1_REFS) expect(check.detail).toContain(ref);
      expect(check.detail).toContain(JSON.stringify(branch));
    },
  );

  test("BLOCK: a rejecting provenance reader fails closed (does not propagate)", async () => {
    const deps = makeDeps({
      branch: "phase1/main",
      isCommitOnProtectedLine: async () => {
        throw new Error("git exploded");
      },
    });
    const resolved = await resolveDeployTarget(deps);
    expect(resolved).toMatchObject({ ok: false, line: "phase1", reason: "phase1-provenance-unverified" });
    expect(slugOf((await checkDeployTarget(deps)).detail)).toBe("phase1-provenance-unverified");
    expect((await runReleaseGuard(deps)).verdict).toBe("BLOCK");
  });

  test("BLOCK: a provenance reader that throws synchronously also fails closed", async () => {
    const deps = makeDeps({
      branch: "phase1/main",
      isCommitOnProtectedLine: (() => {
        throw new Error("sync boom");
      }) as unknown as () => Promise<boolean>,
    });
    const resolved = await resolveDeployTarget(deps);
    expect(resolved).toMatchObject({ ok: false, reason: "phase1-provenance-unverified" });
  });

  test.each([["yes"], [1], [{}], [undefined], [null]])(
    "BLOCK: only the boolean true counts as verified (resolved value %j)",
    async (value) => {
      const deps = makeDeps({
        branch: "phase1/main",
        isCommitOnProtectedLine: (async () => value) as unknown as () => Promise<boolean>,
      });
      expect(await resolveDeployTarget(deps)).toMatchObject({ ok: false, reason: "phase1-provenance-unverified" });
    },
  );

  test("Phase 2 content presented under a branch named phase1/x (provenance false) is blocked end to end", async () => {
    // Local branch name says phase1, commit graph says Phase 2: the injected
    // provenance reader reports HEAD is not contained in the protected refs.
    const result = await runReleaseGuard(makeDeps({ branch: "phase1/x", isCommitOnProtectedLine: async () => false }));
    expect(result.verdict).toBe("BLOCK");
    expect(result.line).toBe("phase1");
    expect(result.branch).toBe("phase1/x");
    const notOk = result.checks.filter((c) => c.status !== "OK");
    // Everything else is healthy in this fixture, so the provenance block is the ONLY reason.
    expect(notOk.map((c) => c.name)).toEqual([DEPLOY_TARGET_CHECK]);
    expect(slugOf(notOk[0].detail)).toBe("phase1-provenance-unverified");
  });

  test("same healthy fixture with provenance true PASSes (control for the test above)", async () => {
    const result = await runReleaseGuard(makeDeps({ branch: "phase1/x", isCommitOnProtectedLine: async () => true }));
    expect(result.verdict).toBe("PASS");
  });

  test("provenance true does not bypass the project check (phase1-wrong-project still wins)", async () => {
    const check = await checkDeployTarget(
      makeDeps({ branch: "phase1/main", project: LEGACY_PROJECT_ID, isCommitOnProtectedLine: async () => true }),
    );
    expect(slugOf(check.detail)).toBe("phase1-wrong-project");
  });

  test("provenance is NOT consulted on the phase2 line and cannot affect it", async () => {
    const phase2Rc = firebasercWith({ default: EXPECTED_PROJECT_ID, [PHASE2_ALIAS]: PHASE2_PROJECT });
    const calls = jest.fn(async () => false);
    const check = await checkDeployTarget(
      makeDeps({ branch: "phase2/s00", project: PHASE2_PROJECT, firebaserc: phase2Rc, isCommitOnProtectedLine: calls }),
    );
    expect(check.status).toBe("OK");
    expect(calls).not.toHaveBeenCalled();
  });

  test.each(["feature/x", "HEAD", "main", null])(
    "provenance is NOT consulted when the branch is not on a deploy line (%j) -- deploy-line-unknown",
    async (branch) => {
      const calls = jest.fn(async () => true);
      const resolved = await resolveDeployTarget(makeDeps({ branch, isCommitOnProtectedLine: calls }));
      expect(resolved).toMatchObject({ ok: false, reason: "deploy-line-unknown" });
      expect(calls).not.toHaveBeenCalled();
    },
  );
});

describe("explicit production project from a phase2/* branch is blocked (effective project -> deploy target)", () => {
  const rc = firebasercWith({
    default: EXPECTED_PROJECT_ID,
    "legacy-shared": LEGACY_PROJECT_ID,
    [PHASE2_ALIAS]: PHASE2_PROJECT,
  });

  async function checkFor(argv: string[], env: Record<string, string | undefined>, branch: string) {
    const eff = resolveEffectiveProject({ env, argv, firebaserc: rc });
    if (!eff.ok) throw new Error(`unexpected resolution failure: ${eff.detail}`);
    return checkDeployTarget(makeDeps({ branch, project: eff.project, firebaserc: rc }));
  }

  test.each([
    ["--project with the production id", ["--project", EXPECTED_PROJECT_ID], {}],
    ["--project=<production id>", [`--project=${EXPECTED_PROJECT_ID}`], {}],
    ["-P <production id>", ["-P", EXPECTED_PROJECT_ID], {}],
    ["-P<production id>", [`-P${EXPECTED_PROJECT_ID}`], {}],
    ["the 'default' alias (maps to production)", ["--project", "default"], {}],
    ["GCLOUD_PROJECT = production id", [], { GCLOUD_PROJECT: EXPECTED_PROJECT_ID }],
    ["the legacy alias", ["--project", "legacy-shared"], {}],
  ] as const)("phase2 branch + %s -> phase2-project-mismatch", async (_label, argv, env) => {
    const check = await checkFor([...argv], { ...env }, "phase2/s00-split-docs");
    expect(check.status).toBe("FAILED");
    expect(check.detail.split(":")[0]).toBe("phase2-project-mismatch");
    expect(check.detail).toContain(`"${PHASE2_PROJECT}"`);
  });

  test("control: phase2 branch + the phase2 alias / id is allowed", async () => {
    for (const [argv, env] of [
      [["--project", PHASE2_ALIAS], {}],
      [["--project", PHASE2_PROJECT], {}],
      [[], { GCLOUD_PROJECT: PHASE2_PROJECT }],
    ] as const) {
      const check = await checkFor([...argv], { ...env }, "phase2/s00-split-docs");
      expect(check.status).toBe("OK");
    }
  });

  test("control: the same production project from a verified phase1 branch is allowed", async () => {
    const check = await checkFor(["--project", "default"], {}, "phase1/main");
    expect(check.status).toBe("OK");
  });
});

describe("parseDeployArgs", () => {
  test("no arguments", () => {
    expect(parseDeployArgs([])).toEqual({ projects: [], hasConfigFlag: false, rest: [] });
  });

  test("unrelated arguments are passed through untouched, in order", () => {
    expect(parseDeployArgs(["--only", "functions:default", "--force"])).toEqual({
      projects: [],
      hasConfigFlag: false,
      rest: ["--only", "functions:default", "--force"],
    });
  });

  test.each([
    ["--project X", ["--project", "X"], ["X"]],
    ["--project=X", ["--project=X"], ["X"]],
    ["-P X", ["-P", "X"], ["X"]],
    ["-PX", ["-PX"], ["X"]],
  ] as const)("project flag form %s is parsed and removed from rest", (_label, argv, projects) => {
    expect(parseDeployArgs([...argv, "--only", "hosting"])).toEqual({
      projects: [...projects],
      hasConfigFlag: false,
      rest: ["--only", "hosting"],
    });
  });

  test.each([
    ["--project with no value", ["--project"]],
    ["-P with no value", ["-P"]],
    ["--project= with empty value", ["--project="]],
  ] as const)("%s yields an empty-string value (so the resolver can fail closed)", (_label, argv) => {
    expect(parseDeployArgs([...argv]).projects).toEqual([""]);
  });

  test("project flag consumes its value even when the flag is in the middle", () => {
    expect(parseDeployArgs(["--only", "firestore", "--project", "a", "--force"])).toEqual({
      projects: ["a"],
      hasConfigFlag: false,
      rest: ["--only", "firestore", "--force"],
    });
  });

  test("several project flags are all collected in order", () => {
    expect(parseDeployArgs(["--project", "a", "-Pb", "--project=c"]).projects).toEqual(["a", "b", "c"]);
  });

  test.each([
    ["--config", ["--config", "other.json"]],
    ["--config=other.json", ["--config=other.json"]],
    ["-c", ["-c", "other.json"]],
    ["-cother.json", ["-cother.json"]],
  ] as const)("%s sets hasConfigFlag", (_label, argv) => {
    const parsed = parseDeployArgs([...argv]);
    expect(parsed.hasConfigFlag).toBe(true);
    // config flags are NOT stripped: the wrapper refuses them rather than rewriting them.
    expect(parsed.rest).toEqual([...argv]);
  });

  test.each([["--only"], ["--force"], ["--cors"], ["--projects"], ["--projectx"]])(
    "%s is not mistaken for a project or config flag",
    (flag) => {
      const parsed = parseDeployArgs([flag]);
      expect(parsed).toEqual({ projects: [], hasConfigFlag: false, rest: [flag] });
    },
  );

  test("does not mutate its input", () => {
    const argv = ["--project", "a", "--only", "x"];
    const copy = [...argv];
    parseDeployArgs(argv);
    expect(argv).toEqual(copy);
  });
});

describe("resolveEffectiveProject", () => {
  const RC = firebasercWith({
    default: EXPECTED_PROJECT_ID,
    "legacy-shared": LEGACY_PROJECT_ID,
    [PHASE2_ALIAS]: PHASE2_PROJECT,
  });
  const resolve = (env: Record<string, string | undefined>, argv: string[], firebaserc: string | null = RC) =>
    resolveEffectiveProject({ env, argv, firebaserc });

  // ---- accepted inputs
  test("GCLOUD_PROJECT only", () => {
    expect(resolve({ GCLOUD_PROJECT: "proj-a" }, [])).toEqual({ ok: true, project: "proj-a", source: "GCLOUD_PROJECT" });
  });

  test("GCLOUD_PROJECT is trimmed", () => {
    expect(resolve({ GCLOUD_PROJECT: "  proj-a \n" }, [])).toEqual({ ok: true, project: "proj-a", source: "GCLOUD_PROJECT" });
  });

  test.each([
    ["--project X", ["--project", "proj-x"]],
    ["--project=X", ["--project=proj-x"]],
    ["-P X", ["-P", "proj-x"]],
    ["-PX", ["-Pproj-x"]],
  ] as const)("explicit flag form %s", (_label, argv) => {
    expect(resolve({}, [...argv])).toEqual({ ok: true, project: "proj-x", source: "--project" });
  });

  test("an explicit alias is mapped through .firebaserc", () => {
    expect(resolve({}, ["--project", "default"])).toEqual({ ok: true, project: EXPECTED_PROJECT_ID, source: "--project" });
    expect(resolve({}, ["-P", PHASE2_ALIAS])).toEqual({ ok: true, project: PHASE2_PROJECT, source: "--project" });
  });

  test("a value that is not an alias is used as the project id", () => {
    expect(resolve({}, ["--project", "not-an-alias"])).toMatchObject({ ok: true, project: "not-an-alias" });
  });

  test("an unreadable/missing .firebaserc means no alias mapping (flag value used verbatim)", () => {
    for (const rc of [null, "{not json", "[]", JSON.stringify({ projects: "x" }), JSON.stringify({ projects: null })]) {
      expect(resolve({}, ["--project", "default"], rc)).toEqual({ ok: true, project: "default", source: "--project" });
    }
  });

  test("a blank alias mapping is ignored (value used verbatim)", () => {
    const rc = firebasercWith({ weird: "   " });
    expect(resolve({}, ["--project", "weird"], rc)).toMatchObject({ ok: true, project: "weird" });
  });

  test("unrelated arguments around the flag are ignored", () => {
    expect(resolve({}, ["--only", "functions", "--project", "proj-x", "--force"])).toMatchObject({
      ok: true,
      project: "proj-x",
    });
  });

  test("GCLOUD_PROJECT and a flag that agree (alias resolved) -> GCLOUD_PROJECT wins as source", () => {
    expect(resolve({ GCLOUD_PROJECT: PHASE2_PROJECT }, ["--project", PHASE2_ALIAS])).toEqual({
      ok: true,
      project: PHASE2_PROJECT,
      source: "GCLOUD_PROJECT",
    });
  });

  test("repeating the same project through alias and id is not a conflict", () => {
    expect(resolve({}, ["--project", PHASE2_ALIAS, "--project", PHASE2_PROJECT])).toEqual({
      ok: true,
      project: PHASE2_PROJECT,
      source: "--project",
    });
  });

  test("GCLOUD_PROJECT is taken as an already-resolved id, never alias-mapped", () => {
    expect(resolve({ GCLOUD_PROJECT: "default" }, [])).toMatchObject({ ok: true, project: "default" });
  });

  // ---- project-undeterminable
  test.each([
    ["--project with no value", ["--project"]],
    ["-P with no value", ["-P"]],
    ["--project= with an empty value", ["--project="]],
    ["--project with a blank value", ["--project", "   "]],
    ["an empty flag followed by a valid one", ["--project=", "--project", "x"]],
  ] as const)("flag without a value fails closed: %s", (_label, argv) => {
    const r = resolve({}, [...argv]);
    expect(r).toMatchObject({ ok: false, reason: "project-undeterminable" });
  });

  test("a valueless flag blocks even when GCLOUD_PROJECT is set (never silently falls back to the env)", () => {
    expect(resolve({ GCLOUD_PROJECT: "proj-a" }, ["--project"])).toMatchObject({
      ok: false,
      reason: "project-undeterminable",
    });
  });

  test.each([
    ["empty env, no flag", {}],
    ["GCLOUD_PROJECT empty string", { GCLOUD_PROJECT: "" }],
    ["GCLOUD_PROJECT whitespace", { GCLOUD_PROJECT: "   " }],
    ["GCLOUD_PROJECT undefined", { GCLOUD_PROJECT: undefined }],
    ["FIREBASE_PROJECT only (ignored by firebase deploy, ignored here)", { FIREBASE_PROJECT: PHASE2_PROJECT }],
    ["GOOGLE_CLOUD_PROJECT only", { GOOGLE_CLOUD_PROJECT: PHASE2_PROJECT }],
  ] as const)("neither source present fails closed: %s", (_label, env) => {
    const r = resolve({ ...env }, ["--only", "functions"]);
    expect(r).toMatchObject({ ok: false, reason: "project-undeterminable" });
    // It must NOT guess from the .firebaserc default alias (which maps to production).
    expect(JSON.stringify(r)).not.toContain(`"project":"${EXPECTED_PROJECT_ID}"`);
  });

  test("neither source present, no .firebaserc at all", () => {
    expect(resolve({}, [], null)).toMatchObject({ ok: false, reason: "project-undeterminable" });
  });

  // ---- project-conflict
  test("two different flag values conflict", () => {
    const r = resolve({}, ["--project", "a", "--project", "b"]);
    expect(r).toMatchObject({ ok: false, reason: "project-conflict" });
    expect(r.ok === false && r.detail).toContain("a, b");
  });

  test("two flags that resolve to different ids via aliases conflict", () => {
    expect(resolve({}, ["--project", "default", "-P", PHASE2_ALIAS])).toMatchObject({
      ok: false,
      reason: "project-conflict",
    });
  });

  test("GCLOUD_PROJECT disagreeing with a flag conflicts (flag = production, env = phase2)", () => {
    const r = resolve({ GCLOUD_PROJECT: PHASE2_PROJECT }, ["--project", "default"]);
    expect(r).toMatchObject({ ok: false, reason: "project-conflict" });
    expect(r.ok === false && r.detail).toContain(PHASE2_PROJECT);
    expect(r.ok === false && r.detail).toContain(EXPECTED_PROJECT_ID);
  });

  test("GCLOUD_PROJECT disagreeing with a flag conflicts (flag = phase2, env = production)", () => {
    expect(resolve({ GCLOUD_PROJECT: EXPECTED_PROJECT_ID }, ["--project", PHASE2_ALIAS])).toMatchObject({
      ok: false,
      reason: "project-conflict",
    });
  });

  test("every failure reason is a member of PROJECT_RESOLUTION_REASONS and leads its detail", () => {
    const failures = [
      resolve({}, []),
      resolve({}, ["--project"]),
      resolve({}, ["--project", "a", "--project", "b"]),
      resolve({ GCLOUD_PROJECT: "a" }, ["--project", "b"]),
    ];
    for (const f of failures) {
      expect(f.ok).toBe(false);
      if (!f.ok) {
        expect(PROJECT_RESOLUTION_REASONS as readonly string[]).toContain(f.reason);
        expect(f.detail.startsWith(`${f.reason}:`)).toBe(true);
      }
    }
  });
});

describe("findUnguardedDeployTargets", () => {
  const REPO_ROOT = path.resolve(__dirname, "..", "..", "..");
  const GUARD_CMD = "node functions/scripts/run_release_guard.mjs";
  const guarded = (): { predeploy: string[] } => ({ predeploy: ["npm --prefix functions run build", GUARD_CMD] });
  const unguarded = (): { predeploy: string[] } => ({ predeploy: ["npm --prefix functions run build"] });
  const base = (): Record<string, unknown> => ({
    firestore: guarded(),
    hosting: guarded(),
    functions: [guarded(), guarded()],
    emulators: { firestore: { port: 8080 } },
  });
  const realConfig = (): Record<string, unknown> =>
    JSON.parse(fs.readFileSync(path.join(REPO_ROOT, "firebase.json"), "utf8")) as Record<string, unknown>;

  test("GUARD_COMMAND_MARKER is the guard script's file name", () => {
    expect(GUARD_COMMAND_MARKER).toBe("run_release_guard.mjs");
  });

  // ---- the real repository file
  test("REAL firebase.json: no deploy target is left unguarded", () => {
    expect(findUnguardedDeployTargets(realConfig())).toEqual([]);
  });

  test("REAL firebase.json: the four known deploy targets exist (the empty list above is not vacuous) and each runs the guard", () => {
    const c = realConfig() as {
      firestore?: { predeploy?: string[] };
      hosting?: { predeploy?: string[] };
      functions?: Array<{ codebase?: string; predeploy?: string[] }>;
    };
    expect(c.functions).toHaveLength(2);
    expect(c.functions!.map((f) => f.codebase)).toEqual(["default", "equipment-identity"]);
    for (const [label, entry] of [
      ["firestore", c.firestore],
      ["hosting", c.hosting],
      ["functions[0]", c.functions![0]],
      ["functions[1]", c.functions![1]],
    ] as const) {
      expect(entry).toBeDefined();
      const hit = (entry!.predeploy ?? []).filter((cmd) => cmd.includes(GUARD_COMMAND_MARKER));
      expect({ label, guardCommands: hit.length }).toEqual({ label, guardCommands: 1 });
    }
  });

  test("REAL firebase.json: every deploy-capable section present carries the guard, and no unknown top-level section appears", () => {
    const deploySections = [
      "functions", "firestore", "hosting", "storage", "database", "dataconnect", "remoteconfig",
      "apphosting", "auth", "extensions",
    ];
    const ignored = new Set(["emulators", "$schema"]);
    const c = realConfig();
    for (const key of Object.keys(c)) {
      if (ignored.has(key)) continue;
      // A new top-level key must be consciously classified here, not silently left unguarded.
      expect(deploySections).toContain(key);
      const entries = Array.isArray(c[key]) ? (c[key] as unknown[]) : [c[key]];
      for (const [i, entry] of entries.entries()) {
        const predeploy = (entry as { predeploy?: unknown } | null)?.predeploy;
        const cmds = typeof predeploy === "string" ? [predeploy] : Array.isArray(predeploy) ? predeploy : [];
        const carriesGuard = cmds.some((cmd) => typeof cmd === "string" && cmd.includes(GUARD_COMMAND_MARKER));
        expect({ section: key, index: i, carriesGuard }).toEqual({ section: key, index: i, carriesGuard: true });
      }
    }
  });

  test("REAL firebase.json: the guard command points at a script that exists", () => {
    const c = realConfig() as { firestore: { predeploy: string[] } };
    const cmd = c.firestore.predeploy.find((x) => x.includes(GUARD_COMMAND_MARKER))!;
    const rel = cmd.replace(/^node\s+/, "").trim();
    expect(fs.existsSync(path.join(REPO_ROOT, rel))).toBe(true);
  });

  // ---- synthetic configs
  test("fully guarded synthetic config -> empty", () => {
    expect(findUnguardedDeployTargets(base())).toEqual([]);
  });

  test("firestore only unguarded", () => {
    const c = base();
    c.firestore = unguarded();
    expect(findUnguardedDeployTargets(c)).toEqual(["firestore"]);
  });

  test("hosting only unguarded", () => {
    const c = base();
    c.hosting = unguarded();
    expect(findUnguardedDeployTargets(c)).toEqual(["hosting"]);
  });

  test("functions[1] only unguarded", () => {
    const c = base();
    c.functions = [guarded(), unguarded()];
    expect(findUnguardedDeployTargets(c)).toEqual(["functions[1]"]);
  });

  test("functions[0] only unguarded", () => {
    const c = base();
    c.functions = [unguarded(), guarded()];
    expect(findUnguardedDeployTargets(c)).toEqual(["functions[0]"]);
  });

  test("a future storage block without the guard is reported; with the guard it is not", () => {
    const c = base();
    c.storage = { rules: "storage.rules" };
    expect(findUnguardedDeployTargets(c)).toEqual(["storage"]);
    c.storage = { rules: "storage.rules", ...guarded() };
    expect(findUnguardedDeployTargets(c)).toEqual([]);
  });

  test.each(["database", "dataconnect", "remoteconfig"])("a future %s block without the guard is reported", (section) => {
    const c = base();
    c[section] = {};
    expect(findUnguardedDeployTargets(c)).toEqual([section]);
  });

  test.each(["apphosting", "auth", "extensions"])(
    "%s cannot carry a predeploy hook at all, so its mere presence is reported",
    (section) => {
      const c = base();
      c[section] = {};
      expect(findUnguardedDeployTargets(c)).toEqual([`${section}:no-predeploy-hook`]);
    },
  );

  test("everything unguarded -> every target listed", () => {
    const c: Record<string, unknown> = {
      firestore: unguarded(),
      hosting: unguarded(),
      functions: [unguarded(), unguarded()],
    };
    expect([...findUnguardedDeployTargets(c)].sort()).toEqual(["firestore", "functions[0]", "functions[1]", "hosting"]);
  });

  test("a non-array functions block is labelled without an index", () => {
    expect(findUnguardedDeployTargets({ functions: unguarded() })).toEqual(["functions"]);
    expect(findUnguardedDeployTargets({ functions: guarded() })).toEqual([]);
  });

  test("predeploy as a plain string is accepted only when it runs the guard", () => {
    expect(findUnguardedDeployTargets({ hosting: { predeploy: GUARD_CMD } })).toEqual([]);
    expect(findUnguardedDeployTargets({ hosting: { predeploy: "npm run build" } })).toEqual(["hosting"]);
  });

  test.each([
    ["missing predeploy", { public: "public" }],
    ["empty predeploy array", { predeploy: [] }],
    ["predeploy runs a different script", { predeploy: ["node scripts/other_guard.mjs"] }],
    ["predeploy has only non-string entries", { predeploy: [1, null, {}] }],
    ["predeploy is a number", { predeploy: 7 }],
    ["entry is null", null],
    ["entry is a string", "hosting"],
  ] as const)("a hosting block with %s is reported", (_label, hosting) => {
    expect(findUnguardedDeployTargets({ hosting })).toEqual(["hosting"]);
  });

  test("the emulators block is not a deploy target", () => {
    expect(findUnguardedDeployTargets({ emulators: { firestore: {} } })).toEqual([]);
  });

  test.each([[null], [undefined], ["x"], [42]])("an unreadable config (%j) fails closed", (config) => {
    expect(findUnguardedDeployTargets(config)).toEqual(["firebase.json:unreadable"]);
  });
});

/* ------------------------------------------------------------------ */
/* E0 / C02 + C12 leftovers: guard set parity and the flag-gated       */
/* body-scan bucket check (T06, RULES-16, RULES-21)                    */
/* ------------------------------------------------------------------ */

import { AI_GATEWAY_OPERATIONS } from "../ai_gateway";

describe("release guard set vs. the Body Scan + Nutrition Coach surface", () => {
  test("every guarded AI callable is a registered AI Gateway operation (guard set cannot drift from the gateway)", () => {
    for (const name of AI_CALLABLES) {
      expect(AI_GATEWAY_OPERATIONS as readonly string[]).toContain(name);
    }
  });

  test("the body-scan callables run as fn-bodyscan outside the AI guard set (D-63): none is in AI_CALLABLES", () => {
    for (const name of ["createBodyScan", "estimateBodyScan", "deleteBodyScan", "manageBodyScanData"]) {
      expect(AI_CALLABLES as readonly string[]).not.toContain(name);
    }
  });

  // RULES-21: the guard set is six callables (the four originals plus the two
  // food AI callables, D-63) and the healthy guard passes with them.
  test("AI_CALLABLES is exactly the six guarded surfaces, the four originals first", () => {
    expect([...AI_CALLABLES]).toEqual([
      "aiCoachAdvice",
      "aiEquipmentRecognition",
      "aiMachineDescription",
      "aiExerciseGeneration",
      "analyzeMealPhoto",
      "parseNutritionLabel",
    ]);
    expect(AI_CALLABLES).toHaveLength(6);
  });

  test("the lookup callables (lookupBarcode, searchFoods) are NOT in the AI guard set: they make no Vertex call", () => {
    expect(AI_CALLABLES as readonly string[]).not.toContain("lookupBarcode");
    expect(AI_CALLABLES as readonly string[]).not.toContain("searchFoods");
  });

  test.each(["analyzeMealPhoto", "parseNutritionLabel"])(
    "the guard FAILS the candidate-source check when the %s source file is missing (it is really read)",
    async (callable) => {
      const result = await runReleaseGuard(makeDeps({ sourceOverrides: { [AI_SOURCE_PATHS[callable]]: null } }));
      const check = byName(result, CANDIDATE_INVARIANTS_CHECK);
      expect(check.status).toBe("FAILED");
      expect(check.detail).toContain(AI_SOURCE_PATHS[callable]);
      expect(check.detail).toContain("file missing");
    },
  );

  test.each(["analyzeMealPhoto", "parseNutritionLabel"])(
    "the guard FAILS when %s drops enforceAiGatewayEnabled, exactly like the original four",
    async (callable) => {
      const result = await runReleaseGuard(
        makeDeps({
          sourceOverrides: {
            [AI_SOURCE_PATHS[callable]]: healthyCallableSource(callable).replace(`await enforceAiGatewayEnabled("${callable}");`, ""),
          },
        }),
      );
      const check = byName(result, CANDIDATE_INVARIANTS_CHECK);
      expect(check.status).toBe("FAILED");
      expect(check.detail).toContain("no real enforceAiGatewayEnabled(...) call in the handler body");
    },
  );

  test("the healthy guard with all six callables passes (10 checks, PASS)", async () => {
    const result = await runReleaseGuard(makeDeps({}));
    expect(result.verdict).toBe("PASS");
    expect(result.checks).toHaveLength(10);
  });
});

describe("runReleaseGuard: flag-gated body-scan bucket check (C12 leftovers, D-60)", () => {
  const BUCKET = "fitness-app-korostelev-body-scans";
  const BUCKET_CHECK = "Body scan private bucket exists, is private, has the required IAM, and the canary is acknowledged";
  const SCAN_SA = `serviceAccount:fn-bodyscan@${PROJECT}.iam.gserviceaccount.com`;
  const DELETE_SA = `serviceAccount:fn-account-delete@${PROJECT}.iam.gserviceaccount.com`;

  const healthyBucketInfo = { iamConfiguration: { publicAccessPrevention: "enforced", uniformBucketLevelAccess: { enabled: true } } };
  const healthyBucketPolicy = {
    bindings: [{ role: "roles/storage.objectAdmin", members: [SCAN_SA, DELETE_SA] }],
  };
  const CANARY_CLOSED = JSON.stringify({
    step8KillSwitch: { status: "closed" },
    s23PlayIntegrityProof: { status: "closed" },
    bodyScanBucketCanary: { status: "closed" },
  });

  type Storage = { describe?: () => CommandResult; policy?: () => CommandResult };
  const ok = (v: unknown): CommandResult => ({ ok: true, stdout: JSON.stringify(v), stderr: "" });

  function depsWithBucket(opts: {
    env?: Record<string, string | undefined>;
    dotenv?: string | null;
    evidence?: string | null;
    storage?: Storage;
    calls?: string[][];
  }): ReleaseGuardDeps {
    const base = makeDeps({ evidence: opts.evidence === undefined ? CANARY_CLOSED : opts.evidence });
    const baseRead = base.readFile;
    const baseRun = base.runCommand;
    return {
      ...base,
      ...(opts.env ? { env: opts.env } : {}),
      readFile: async (path: string) => {
        if (path === `functions/.env.${PROJECT}`) return opts.dotenv === undefined ? null : opts.dotenv;
        return baseRead(path);
      },
      runCommand: async (cmd, args, timeoutMs) => {
        if (cmd === "gcloud" && args[0] === "storage" && args[1] === "buckets") {
          opts.calls?.push(args);
          if (args[2] === "describe") return (opts.storage?.describe ?? (() => ok(healthyBucketInfo)))();
          if (args[2] === "get-iam-policy") return (opts.storage?.policy ?? (() => ok(healthyBucketPolicy)))();
        }
        return baseRun(cmd, args, timeoutMs);
      },
    };
  }

  const bucketCheck = (r: Awaited<ReturnType<typeof runReleaseGuard>>) => r.checks.find((c) => c.name === BUCKET_CHECK);

  test("unset bucket: the check is absent, the guard keeps its 10 checks and PASSes (flag-gated skip)", async () => {
    const calls: string[][] = [];
    const result = await runReleaseGuard(depsWithBucket({ env: {}, calls }));
    expect(bucketCheck(result)).toBeUndefined();
    expect(result.checks).toHaveLength(10);
    expect(result.verdict).toBe("PASS");
    expect(calls).toHaveLength(0);
  });

  test("no env at all (older callers) behaves exactly like unset", async () => {
    const result = await runReleaseGuard(depsWithBucket({}));
    expect(bucketCheck(result)).toBeUndefined();
    expect(result.checks).toHaveLength(10);
  });

  test("an invalid bucket name is treated as not configured, never probed", async () => {
    for (const bad of ["Bad_Bucket", "x", "-lead", "trail-", "has space", ""]) {
      const calls: string[][] = [];
      const result = await runReleaseGuard(depsWithBucket({ env: { BODY_SCAN_BUCKET: bad }, calls }));
      expect(bucketCheck(result)).toBeUndefined();
      expect(calls).toHaveLength(0);
    }
  });

  test("set via env and fully healthy: 11 checks, the bucket check is OK, PASS, and gcloud was asked about gs://<bucket>", async () => {
    const calls: string[][] = [];
    const result = await runReleaseGuard(depsWithBucket({ env: { BODY_SCAN_BUCKET: `  ${BUCKET}  ` }, calls }));
    expect(result.checks).toHaveLength(11);
    const check = bucketCheck(result)!;
    expect(check.status).toBe("OK");
    expect(check.detail).toContain(BUCKET);
    expect(result.verdict).toBe("PASS");
    expect(calls.map((c) => c.slice(0, 4))).toEqual([
      ["storage", "buckets", "describe", `gs://${BUCKET}`],
      ["storage", "buckets", "get-iam-policy", `gs://${BUCKET}`],
    ]);
  });

  test("set only in functions/.env.<project> (quoted value): the check runs", async () => {
    const result = await runReleaseGuard(
      depsWithBucket({ env: {}, dotenv: `OTHER=1\nBODY_SCAN_BUCKET="${BUCKET}"\n` }),
    );
    expect(bucketCheck(result)?.status).toBe("OK");
  });

  test("a commented-out BODY_SCAN_BUCKET line in the .env file does not count", async () => {
    const result = await runReleaseGuard(depsWithBucket({ env: {}, dotenv: `# BODY_SCAN_BUCKET=${BUCKET}\n` }));
    expect(bucketCheck(result)).toBeUndefined();
  });

  test("process env wins over the .env file", async () => {
    const calls: string[][] = [];
    await runReleaseGuard(
      depsWithBucket({ env: { BODY_SCAN_BUCKET: BUCKET }, dotenv: "BODY_SCAN_BUCKET=some-other-bucket-name\n", calls }),
    );
    expect(calls[0][3]).toBe(`gs://${BUCKET}`);
  });

  test("snake_case gcloud storage output (public_access_prevention / uniform_bucket_level_access) is accepted too", async () => {
    const result = await runReleaseGuard(
      depsWithBucket({
        env: { BODY_SCAN_BUCKET: BUCKET },
        storage: { describe: () => ok({ public_access_prevention: "enforced", uniform_bucket_level_access: true }) },
      }),
    );
    expect(bucketCheck(result)?.status).toBe("OK");
  });

  test("FAILED when public access prevention is not enforced (and BLOCK verdict)", async () => {
    const result = await runReleaseGuard(
      depsWithBucket({
        env: { BODY_SCAN_BUCKET: BUCKET },
        storage: { describe: () => ok({ iamConfiguration: { publicAccessPrevention: "inherited", uniformBucketLevelAccess: { enabled: true } } }) },
      }),
    );
    const check = bucketCheck(result)!;
    expect(check.status).toBe("FAILED");
    expect(check.detail).toContain("public access prevention");
    expect(result.verdict).toBe("BLOCK");
  });

  test("FAILED when uniform bucket-level access is off", async () => {
    const result = await runReleaseGuard(
      depsWithBucket({
        env: { BODY_SCAN_BUCKET: BUCKET },
        storage: { describe: () => ok({ iamConfiguration: { publicAccessPrevention: "enforced", uniformBucketLevelAccess: { enabled: false } } }) },
      }),
    );
    expect(bucketCheck(result)!.detail).toContain("uniform bucket-level access is not enabled");
    expect(bucketCheck(result)!.status).toBe("FAILED");
  });

  test.each(["allUsers", "allAuthenticatedUsers"])("FAILED when the public principal %s is bound", async (principal) => {
    const result = await runReleaseGuard(
      depsWithBucket({
        env: { BODY_SCAN_BUCKET: BUCKET },
        storage: {
          policy: () =>
            ok({
              bindings: [
                { role: "roles/storage.objectAdmin", members: [SCAN_SA, DELETE_SA] },
                { role: "roles/storage.objectViewer", members: [principal] },
              ],
            }),
        },
      }),
    );
    expect(bucketCheck(result)!.status).toBe("FAILED");
    expect(bucketCheck(result)!.detail).toContain(principal);
  });

  test("FAILED when fn-bodyscan lacks objectAdmin (named in the detail), and only that account is named", async () => {
    const result = await runReleaseGuard(
      depsWithBucket({
        env: { BODY_SCAN_BUCKET: BUCKET },
        storage: { policy: () => ok({ bindings: [{ role: "roles/storage.objectAdmin", members: [DELETE_SA] }] }) },
      }),
    );
    const check = bucketCheck(result)!;
    expect(check.status).toBe("FAILED");
    expect(check.detail).toContain("fn-bodyscan lacks roles/storage.objectAdmin");
    expect(check.detail).not.toContain("fn-account-delete lacks");
  });

  test("FAILED when fn-account-delete lacks objectAdmin (a configured-but-IAM-denied bucket would break account deletion)", async () => {
    const result = await runReleaseGuard(
      depsWithBucket({
        env: { BODY_SCAN_BUCKET: BUCKET },
        storage: { policy: () => ok({ bindings: [{ role: "roles/storage.objectAdmin", members: [SCAN_SA] }] }) },
      }),
    );
    expect(bucketCheck(result)!.status).toBe("FAILED");
    expect(bucketCheck(result)!.detail).toContain("fn-account-delete lacks roles/storage.objectAdmin");
  });

  test("FAILED when the role is a weaker one than objectAdmin", async () => {
    const result = await runReleaseGuard(
      depsWithBucket({
        env: { BODY_SCAN_BUCKET: BUCKET },
        storage: { policy: () => ok({ bindings: [{ role: "roles/storage.objectViewer", members: [SCAN_SA, DELETE_SA] }] }) },
      }),
    );
    expect(bucketCheck(result)!.status).toBe("FAILED");
  });

  test("FAILED when the canary evidence is open, absent from the evidence file, or the evidence is unreadable", async () => {
    const open = JSON.stringify({ step8KillSwitch: { status: "closed" }, s23PlayIntegrityProof: { status: "closed" }, bodyScanBucketCanary: { status: "open" } });
    const absent = JSON.stringify({ step8KillSwitch: { status: "closed" }, s23PlayIntegrityProof: { status: "closed" } });
    for (const evidence of [open, absent, "not json {"]) {
      const result = await runReleaseGuard(depsWithBucket({ env: { BODY_SCAN_BUCKET: BUCKET }, evidence }));
      const check = bucketCheck(result)!;
      expect(check.status).toBe("FAILED");
      expect(check.detail).toMatch(/bodyScanBucketCanary|canary acknowledgement unreadable/);
    }
  });

  test("UNAVAILABLE (not OK, not silently skipped) when the bucket cannot be described", async () => {
    const result = await runReleaseGuard(
      depsWithBucket({
        env: { BODY_SCAN_BUCKET: BUCKET },
        storage: { describe: () => ({ ok: false, stdout: "", stderr: "404 bucket not found" }) },
      }),
    );
    const check = bucketCheck(result)!;
    expect(check.status).toBe("UNAVAILABLE");
    expect(check.detail).toContain("404 bucket not found");
    expect(result.verdict).toBe("BLOCK");
  });

  test("UNAVAILABLE when the bucket IAM policy cannot be read", async () => {
    const result = await runReleaseGuard(
      depsWithBucket({
        env: { BODY_SCAN_BUCKET: BUCKET },
        storage: { policy: () => ({ ok: true, stdout: "garbage {", stderr: "" }) },
      }),
    );
    expect(bucketCheck(result)!.status).toBe("UNAVAILABLE");
    expect(result.verdict).toBe("BLOCK");
  });

  test("several problems are all reported in one detail, not just the first", async () => {
    const result = await runReleaseGuard(
      depsWithBucket({
        env: { BODY_SCAN_BUCKET: BUCKET },
        evidence: JSON.stringify({ step8KillSwitch: { status: "closed" }, s23PlayIntegrityProof: { status: "closed" } }),
        storage: {
          describe: () => ok({ iamConfiguration: { publicAccessPrevention: "inherited", uniformBucketLevelAccess: { enabled: false } } }),
          policy: () => ok({ bindings: [] }),
        },
      }),
    );
    const detail = bucketCheck(result)!.detail;
    for (const part of ["public access prevention", "uniform bucket-level access", "fn-bodyscan lacks", "fn-account-delete lacks", "bodyScanBucketCanary"]) {
      expect(detail).toContain(part);
    }
  });
});

describe("merge interactions: deploy-line gate x PR #5 six callables x body-scan bucket check", () => {
  const BUCKET = "fitness-app-korostelev-body-scans";
  const BUCKET_CHECK = "Body scan private bucket exists, is private, has the required IAM, and the canary is acknowledged";
  const INVENTORY_CHECK = "AI callables match the intended fn-ai-runtime deployed set";
  const SCAN_SA = `serviceAccount:fn-bodyscan@${PROJECT}.iam.gserviceaccount.com`;
  const DELETE_SA = `serviceAccount:fn-account-delete@${PROJECT}.iam.gserviceaccount.com`;
  const CANARY_CLOSED = JSON.stringify({
    step8KillSwitch: { status: "closed" },
    s23PlayIntegrityProof: { status: "closed" },
    bodyScanBucketCanary: { status: "closed" },
  });
  const phase2Rc = firebasercWith({
    default: EXPECTED_PROJECT_ID,
    "legacy-shared": LEGACY_PROJECT_ID,
    [PHASE2_ALIAS]: PHASE2_PROJECT,
  });
  const ok = (v: unknown): CommandResult => ({ ok: true, stdout: JSON.stringify(v), stderr: "" });

  /** Healthy everywhere (six callables, bucket configured and healthy, canary closed) except what the test overrides. */
  function healthyWithBucket(opts: Parameters<typeof makeDeps>[0]): ReleaseGuardDeps {
    const base = makeDeps({ evidence: CANARY_CLOSED, ...opts });
    const baseRun = base.runCommand;
    return {
      ...base,
      env: { BODY_SCAN_BUCKET: BUCKET },
      runCommand: async (cmd, args, timeoutMs) => {
        if (cmd === "gcloud" && args[0] === "storage" && args[1] === "buckets") {
          if (args[2] === "describe") {
            return ok({ iamConfiguration: { publicAccessPrevention: "enforced", uniformBucketLevelAccess: { enabled: true } } });
          }
          return ok({ bindings: [{ role: "roles/storage.objectAdmin", members: [SCAN_SA, DELETE_SA] }] });
        }
        return baseRun(cmd, args, timeoutMs);
      },
    };
  }

  test("control: healthy phase1 line with provenance, six callables and a healthy bucket -> PASS with 11 checks", async () => {
    const result = await runReleaseGuard(healthyWithBucket({ branch: "phase1/main" }));
    expect(result.verdict).toBe("PASS");
    expect(result.checks).toHaveLength(11);
    expect(result.checks.every((c) => c.status === "OK")).toBe(true);
  });

  test("phase1 provenance failure still BLOCKs through the Deploy target check even though the bucket check is OK and all six callables are present", async () => {
    const result = await runReleaseGuard(
      healthyWithBucket({ branch: "phase1/main", isCommitOnProtectedLine: async () => false }),
    );
    expect(result.verdict).toBe("BLOCK");
    expect(result.checks).toHaveLength(11);
    expect(byName(result, BUCKET_CHECK).status).toBe("OK");
    expect(byName(result, INVENTORY_CHECK).status).toBe("OK");
    expect(byName(result, INVENTORY_CHECK).detail).toContain("all 6 callables");
    const notOk = result.checks.filter((c) => c.status !== "OK");
    expect(notOk.map((c) => c.name)).toEqual([DEPLOY_TARGET_CHECK]);
    expect(notOk[0].detail.split(":")[0]).toBe("phase1-provenance-unverified");
  });

  test("phase1 provenance reader rejecting is the same BLOCK with the bucket and callable checks OK", async () => {
    const result = await runReleaseGuard(
      healthyWithBucket({
        branch: "phase1/x",
        isCommitOnProtectedLine: async () => {
          throw new Error("git exploded");
        },
      }),
    );
    expect(result.verdict).toBe("BLOCK");
    expect(result.checks.filter((c) => c.status !== "OK").map((c) => c.name)).toEqual([DEPLOY_TARGET_CHECK]);
  });

  test("phase2 branch + production project is BLOCKed (phase2-project-mismatch) while the bucket and callable checks pass", async () => {
    const result = await runReleaseGuard(
      healthyWithBucket({ branch: "phase2/s00-split-docs", project: EXPECTED_PROJECT_ID, firebaserc: phase2Rc }),
    );
    expect(result.verdict).toBe("BLOCK");
    expect(result.line).toBe("phase2");
    expect(byName(result, BUCKET_CHECK).status).toBe("OK");
    expect(byName(result, INVENTORY_CHECK).status).toBe("OK");
    const notOk = result.checks.filter((c) => c.status !== "OK");
    expect(notOk.map((c) => c.name)).toEqual([DEPLOY_TARGET_CHECK]);
    expect(notOk[0].detail.split(":")[0]).toBe("phase2-project-mismatch");
  });

  test("a missing body-scan canary evidence blocks on the bucket check only, and the deploy-line gate stays OK (the two gates are independent)", async () => {
    const result = await runReleaseGuard(
      healthyWithBucket({ branch: "phase1/main", evidence: JSON.stringify({
        step8KillSwitch: { status: "closed" },
        s23PlayIntegrityProof: { status: "closed" },
      }) }),
    );
    expect(result.verdict).toBe("BLOCK");
    expect(byName(result, DEPLOY_TARGET_CHECK).status).toBe("OK");
    expect(result.checks.filter((c) => c.status !== "OK").map((c) => c.name)).toEqual([BUCKET_CHECK]);
  });

  test("the six AI source paths used by the fixtures all exist in the repository", () => {
    const repoRoot = path.resolve(__dirname, "..", "..", "..");
    expect(Object.keys(AI_SOURCE_PATHS).sort()).toEqual([...AI_CALLABLES].sort());
    for (const rel of Object.values(AI_SOURCE_PATHS)) {
      expect({ rel, exists: fs.existsSync(path.join(repoRoot, rel)) }).toEqual({ rel, exists: true });
    }
    expect(fs.existsSync(path.join(repoRoot, SCALING_PATH))).toBe(true);
  });

  test("REAL firebase.json: the storage block PR #5 added exists, has its rules file, runs the guard, and the whole file reports no unguarded target", () => {
    const repoRoot = path.resolve(__dirname, "..", "..", "..");
    const config = JSON.parse(fs.readFileSync(path.join(repoRoot, "firebase.json"), "utf8")) as {
      storage?: { rules?: string; predeploy?: string[] };
    };
    expect(config.storage).toBeDefined();
    expect(fs.existsSync(path.join(repoRoot, config.storage!.rules!))).toBe(true);
    expect((config.storage!.predeploy ?? []).filter((c) => c.includes(GUARD_COMMAND_MARKER))).toHaveLength(1);
    expect(findUnguardedDeployTargets(config)).toEqual([]);
  });

  test("the same real config with its storage guard removed reports exactly storage", () => {
    const repoRoot = path.resolve(__dirname, "..", "..", "..");
    const config = JSON.parse(fs.readFileSync(path.join(repoRoot, "firebase.json"), "utf8")) as {
      storage: { predeploy?: string[] };
    };
    config.storage.predeploy = config.storage.predeploy!.filter((c) => !c.includes(GUARD_COMMAND_MARKER));
    expect(findUnguardedDeployTargets(config)).toEqual(["storage"]);
  });
});
