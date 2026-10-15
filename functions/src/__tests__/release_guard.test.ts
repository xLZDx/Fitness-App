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
} from "../release_guard";
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
    const check = byName(result, "App Check enforcement is on (fail-closed) for all 4 AI callables");
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
    expect(byName(result, "App Check enforcement is on (fail-closed) for all 4 AI callables").status).toBe("OK");
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
    expect(byName(result, "App Check enforcement is on (fail-closed) for all 4 AI callables").status).toBe("OK");
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
    const check = byName(result, "Anonymous callers are refused on all 4 AI callables");
    expect(check.status).toBe("FAILED");
    expect(check.detail).toContain("aiMachineDescription");
  });

  test("App Check and anonymous checks both UNAVAILABLE when describe fails for any callable", async () => {
    const result = await runReleaseGuard(
      makeDeps({ gcloud: { "describe:aiExerciseGeneration": () => ({ ok: false, stdout: "", stderr: "not found" }) } }),
    );
    expect(byName(result, "App Check enforcement is on (fail-closed) for all 4 AI callables").status).toBe("UNAVAILABLE");
    expect(byName(result, "Anonymous callers are refused on all 4 AI callables").status).toBe("UNAVAILABLE");
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

  test("DEPLOY_LINE_REASONS is exactly the closed set of six slugs", () => {
    expect([...DEPLOY_LINE_REASONS]).toEqual([
      "deploy-line-unknown",
      "phase1-wrong-project",
      "firebaserc-unreadable",
      "phase2-alias-missing",
      "phase2-targets-production",
      "phase2-project-mismatch",
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
    // run_release_guard.mjs falls back to EXPECTED_PROJECT_ID when neither
    // GCLOUD_PROJECT nor --project= is given; on a phase2 branch that must block.
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
