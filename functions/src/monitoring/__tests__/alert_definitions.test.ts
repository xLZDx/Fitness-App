import {
  STRIPE_RECONCILIATION_FAILURE_FILTER,
  DELETE_ACCOUNT_FAILURE_FILTER,
  EXPORT_ACCOUNT_FAILURE_FILTER,
  CANARY_PROBE_FAILURE_FILTER,
  ENFORCEMENT_STATE_FAILURE_FILTER,
  APP_CHECK_ATTESTED_RATIO_METRIC,
  stripeReconciliationAlertFilterString,
  deleteAccountAlertFilterString,
  exportAccountAlertFilterString,
  canaryProbeAlertFilterString,
  enforcementStateAlertFilterString,
  stripeReconciliationAlertPolicyJson,
  deleteAccountAlertPolicyJson,
  exportAccountAlertPolicyJson,
  canaryProbeAlertPolicyJson,
  enforcementStateAlertPolicyJson,
  enforcementStateStalenessPolicyJson,
  appCheckAttestedRatioMetricJson,
} from "../alert_definitions";
import {
  matchesLogMatchFilter,
  toCloudRunServiceName,
  counterLogMetricFilterString,
  type LogEntryFixture,
} from "../types";
import * as signals from "../log_signals";

function entry(
  serviceName: string,
  message: string,
  severity: LogEntryFixture["severity"] = "ERROR",
): LogEntryFixture {
  return { serviceName, message, severity };
}

describe("toCloudRunServiceName", () => {
  it("lowercases and hyphenates a camelCase export name", () => {
    expect(toCloudRunServiceName("deleteAccount")).toBe("deleteaccount");
    expect(toCloudRunServiceName("exportAccountData")).toBe(
      "exportaccountdata",
    );
    expect(toCloudRunServiceName("stripeWebhook")).toBe("stripewebhook");
  });

  it("replaces underscores with hyphens", () => {
    expect(toCloudRunServiceName("some_fn_name")).toBe("some-fn-name");
  });
});

describe("Stripe reconciliation-failure alert filter", () => {
  it("matches both real failure log lines from the webhook's deployed service", () => {
    expect(
      matchesLogMatchFilter(
        STRIPE_RECONCILIATION_FAILURE_FILTER,
        entry("stripewebhook", signals.STRIPE_RECONCILE_CANCEL_FAILED),
      ),
    ).toBe(true);
    expect(
      matchesLogMatchFilter(
        STRIPE_RECONCILIATION_FAILURE_FILTER,
        entry("stripewebhook", signals.STRIPE_RECONCILE_FAILED),
      ),
    ).toBe(true);
  });

  it("does not match the two non-failure log lines from the same code path", () => {
    expect(
      matchesLogMatchFilter(
        STRIPE_RECONCILIATION_FAILURE_FILTER,
        entry("stripewebhook", signals.STRIPE_RECONCILE_DUPLICATE_FOUND, "WARNING"),
      ),
    ).toBe(false);
    expect(
      matchesLogMatchFilter(
        STRIPE_RECONCILIATION_FAILURE_FILTER,
        entry("stripewebhook", signals.STRIPE_RECONCILE_CANCEL_OK, "INFO"),
      ),
    ).toBe(false);
  });

  it("does not match the identical message from a different service", () => {
    expect(
      matchesLogMatchFilter(
        STRIPE_RECONCILIATION_FAILURE_FILTER,
        entry("deleteaccount", signals.STRIPE_RECONCILE_FAILED),
      ),
    ).toBe(false);
  });

  it("renders a Gen2-shaped filter string scoped to the stripewebhook Cloud Run service", () => {
    const filter = stripeReconciliationAlertFilterString();
    expect(filter).toContain('resource.type="cloud_run_revision"');
    expect(filter).toContain('resource.labels.service_name="stripewebhook"');
    expect(filter).not.toContain("function_name");
    expect(filter).toContain(signals.STRIPE_RECONCILE_CANCEL_FAILED);
    expect(filter).toContain(signals.STRIPE_RECONCILE_FAILED);
  });
});

describe("deleteAccount operational-failure alert filter", () => {
  it("matches all three explicit failure paths", () => {
    for (const message of [
      signals.DELETE_ACCOUNT_STRIPE_CANCEL_FAILED,
      signals.DELETE_ACCOUNT_FIRESTORE_DELETE_FAILED,
      signals.DELETE_ACCOUNT_AUTH_DELETE_FAILED,
    ]) {
      expect(
        matchesLogMatchFilter(
          DELETE_ACCOUNT_FAILURE_FILTER,
          entry("deleteaccount", message),
        ),
      ).toBe(true);
    }
  });

  it("matches the platform backstop for a failure outside the three named catches", () => {
    // Covers, e.g., the pre-try Firestore read at index.ts:2086 -- no
    // explicit catch names it, but firebase-functions' own https.js wraps
    // the whole handler and logs this exact message for anything that
    // isn't already an HttpsError. See README.md's failure-path audit.
    expect(
      matchesLogMatchFilter(
        DELETE_ACCOUNT_FAILURE_FILTER,
        entry("deleteaccount", signals.PLATFORM_UNHANDLED_ERROR),
      ),
    ).toBe(true);
  });

  it("does not match an expected refusal (thrown as HttpsError, never reaches the backstop)", () => {
    // "unauthenticated" and the quota/App-Check refusals inside deleteAccount
    // are thrown as HttpsError, so the platform wrapper's own
    // `!(err instanceof HttpsError)` check means they never produce a
    // PLATFORM_UNHANDLED_ERROR line in the first place. There is no
    // separate log message for them to accidentally match here -- this
    // test documents that absence rather than asserting a fixture.
    expect(DELETE_ACCOUNT_FAILURE_FILTER.messageEquals).not.toContain(
      "unauthenticated",
    );
  });

  it("does not match exportAccountData's identical-shaped failure", () => {
    expect(
      matchesLogMatchFilter(
        DELETE_ACCOUNT_FAILURE_FILTER,
        entry("exportaccountdata", signals.PLATFORM_UNHANDLED_ERROR),
      ),
    ).toBe(false);
  });

  it("renders a Gen2-shaped filter string scoped to the deleteaccount Cloud Run service", () => {
    const filter = deleteAccountAlertFilterString();
    expect(filter).toContain('resource.type="cloud_run_revision"');
    expect(filter).toContain('resource.labels.service_name="deleteaccount"');
    expect(filter).toContain(signals.PLATFORM_UNHANDLED_ERROR);
  });
});

describe("exportAccountData operational-failure alert filter", () => {
  it("matches the explicit failure and the platform backstop", () => {
    expect(
      matchesLogMatchFilter(
        EXPORT_ACCOUNT_FAILURE_FILTER,
        entry("exportaccountdata", signals.EXPORT_ACCOUNT_FAILED),
      ),
    ).toBe(true);
    expect(
      matchesLogMatchFilter(
        EXPORT_ACCOUNT_FAILURE_FILTER,
        entry("exportaccountdata", signals.PLATFORM_UNHANDLED_ERROR),
      ),
    ).toBe(true);
  });

  it("does not match deleteAccount's identical-shaped failure", () => {
    expect(
      matchesLogMatchFilter(
        EXPORT_ACCOUNT_FAILURE_FILTER,
        entry("deleteaccount", signals.PLATFORM_UNHANDLED_ERROR),
      ),
    ).toBe(false);
  });

  it("renders a Gen2-shaped filter string scoped to the exportaccountdata Cloud Run service", () => {
    const filter = exportAccountAlertFilterString();
    expect(filter).toContain('resource.type="cloud_run_revision"');
    expect(filter).toContain(
      'resource.labels.service_name="exportaccountdata"',
    );
  });
});

describe("production canary probe-failure alert filter", () => {
  it("matches the canary's own thrown-failure log", () => {
    expect(
      matchesLogMatchFilter(
        CANARY_PROBE_FAILURE_FILTER,
        entry("runproductioncanary", signals.CANARY_PROBE_FAILED_EVENT),
      ),
    ).toBe(true);
  });

  it("does not match PLATFORM_UNHANDLED_ERROR -- onSchedule's own wrapper never logs it", () => {
    // Unlike deleteAccount/exportAccountData (onCall functions, where
    // https.js's platform wrapper genuinely does log this exact message),
    // runProductionCanary is onSchedule -- its wrapper
    // (scheduler.js:71-73) logs only `err.message`, never the literal
    // string "Unhandled error". Including it here would be a filter clause
    // that can never match anything real. GPT-PM's review of b9d1e9a caught
    // this; canary_schedule.ts's own try/catch is the real backstop for
    // this function, and it emits CANARY_PROBE_FAILED_EVENT itself.
    expect(CANARY_PROBE_FAILURE_FILTER.messageEquals).not.toContain(
      signals.PLATFORM_UNHANDLED_ERROR,
    );
  });

  it("does not match an identical-shaped failure from a different service", () => {
    expect(
      matchesLogMatchFilter(
        CANARY_PROBE_FAILURE_FILTER,
        entry("deleteaccount", signals.CANARY_PROBE_FAILED_EVENT),
      ),
    ).toBe(false);
  });

  it("renders a Gen2-shaped filter string scoped to the runproductioncanary Cloud Run service", () => {
    const filter = canaryProbeAlertFilterString();
    expect(filter).toContain('resource.type="cloud_run_revision"');
    expect(filter).toContain(
      'resource.labels.service_name="runproductioncanary"',
    );
    expect(filter).toContain(signals.CANARY_PROBE_FAILED_EVENT);
  });
});

describe("enforcement-state check failure alert filter", () => {
  it("matches the check's own degraded-or-failed log", () => {
    expect(
      matchesLogMatchFilter(
        ENFORCEMENT_STATE_FAILURE_FILTER,
        entry("runenforcementstatecheck", signals.ENFORCEMENT_STATE_DEGRADED_OR_FAILED_EVENT),
      ),
    ).toBe(true);
  });

  it("does not match PLATFORM_UNHANDLED_ERROR -- onSchedule's own wrapper never logs it", () => {
    // Same documented reason as the canary's own filter above: this is an
    // onSchedule function, not onCall, so https.js's platform backstop
    // never applies to it.
    expect(ENFORCEMENT_STATE_FAILURE_FILTER.messageEquals).not.toContain(
      signals.PLATFORM_UNHANDLED_ERROR,
    );
  });

  it("does not match an identical-shaped failure from a different service", () => {
    expect(
      matchesLogMatchFilter(
        ENFORCEMENT_STATE_FAILURE_FILTER,
        entry("runproductioncanary", signals.ENFORCEMENT_STATE_DEGRADED_OR_FAILED_EVENT),
      ),
    ).toBe(false);
  });

  it("renders a Gen2-shaped filter string scoped to the runenforcementstatecheck Cloud Run service", () => {
    const filter = enforcementStateAlertFilterString();
    expect(filter).toContain('resource.type="cloud_run_revision"');
    expect(filter).toContain(
      'resource.labels.service_name="runenforcementstatecheck"',
    );
    expect(filter).toContain(signals.ENFORCEMENT_STATE_DEGRADED_OR_FAILED_EVENT);
  });
});

describe("enforcement-state Scheduler staleness policy (metric-absence, GPT-PM remediation)", () => {
  it("renders a conditionAbsent condition, not conditionMatchedLog", () => {
    const policy = enforcementStateStalenessPolicyJson() as {
      conditions: Array<{
        conditionAbsent?: { filter: string; duration: string; aggregations: unknown[] };
        conditionMatchedLog?: unknown;
      }>;
    };
    expect(policy.conditions).toHaveLength(1);
    expect(policy.conditions[0].conditionMatchedLog).toBeUndefined();
    expect(policy.conditions[0].conditionAbsent).toBeDefined();
    expect(policy.conditions[0].conditionAbsent?.duration).toBe("86400s");
  });

  it("filters on the Scheduler job's own execution-count metric, not a custom log", () => {
    const policy = enforcementStateStalenessPolicyJson() as {
      conditions: Array<{ conditionAbsent?: { filter: string } }>;
    };
    const filter = policy.conditions[0].conditionAbsent?.filter ?? "";
    expect(filter).toContain(
      'metric.type="cloudscheduler.googleapis.com/job/execution_count"',
    );
    expect(filter).toContain('resource.type="cloud_scheduler_job"');
    expect(filter).toContain("runEnforcementStateCheck");
  });

  it("has an empty notificationChannels list, same posture as every other policy before FA-D1/activation", () => {
    const policy = enforcementStateStalenessPolicyJson() as { notificationChannels: unknown[] };
    expect(policy.notificationChannels).toEqual([]);
  });
});

describe("AlertPolicy JSON shape (Cloud Monitoring projects.alertPolicies REST shape)", () => {
  it.each([
    ["Stripe reconciliation", stripeReconciliationAlertPolicyJson()],
    ["deleteAccount", deleteAccountAlertPolicyJson()],
    ["exportAccountData", exportAccountAlertPolicyJson()],
    ["production canary probe", canaryProbeAlertPolicyJson()],
    ["enforcement-state check", enforcementStateAlertPolicyJson()],
  ])("%s policy has the full deployable shape, not a bare filter", (_label, policy) => {
    const p = policy as {
      displayName: string;
      combiner: string;
      conditions: Array<{ conditionMatchedLog?: { filter: string } }>;
      alertStrategy: {
        notificationRateLimit: { period: string };
        autoClose: string;
      };
      notificationChannels: unknown[];
    };
    expect(typeof p.displayName).toBe("string");
    expect(p.displayName.length).toBeGreaterThan(0);
    expect(p.combiner).toBe("OR");
    expect(p.conditions).toHaveLength(1);
    expect(p.conditions[0].conditionMatchedLog?.filter).toEqual(
      expect.stringContaining('resource.type="cloud_run_revision"'),
    );
    expect(p.alertStrategy.notificationRateLimit.period).toMatch(/^\d+s$/);
    expect(p.alertStrategy.autoClose).toMatch(/^\d+s$/);
  });

  it.each([
    ["Stripe reconciliation", stripeReconciliationAlertPolicyJson()],
    ["deleteAccount", deleteAccountAlertPolicyJson()],
    ["exportAccountData", exportAccountAlertPolicyJson()],
    ["production canary probe", canaryProbeAlertPolicyJson()],
    ["enforcement-state check", enforcementStateAlertPolicyJson()],
  ])("%s policy has an empty notificationChannels list (no live paging until FA-D1)", (_label, policy) => {
    const p = policy as { notificationChannels: unknown[] };
    expect(p.notificationChannels).toEqual([]);
  });
});

describe("App Check attested-ratio log-based metric definition", () => {
  it("filters on the exact noteAppCheck event message", () => {
    const filter = counterLogMetricFilterString(APP_CHECK_ATTESTED_RATIO_METRIC);
    expect(filter).toContain(`jsonPayload.message="${signals.APP_CHECK_EVENT}"`);
  });

  it("renders the boolean attested label unquoted, not as a string", () => {
    const filter = counterLogMetricFilterString(APP_CHECK_ATTESTED_RATIO_METRIC);
    expect(filter).toContain("jsonPayload.attested=true");
    expect(filter).toContain("jsonPayload.attested=false");
    expect(filter).not.toContain('jsonPayload.attested="true"');
  });

  it("bounds fn to the known callable list, excluding an unknown/typo'd value", () => {
    const filter = counterLogMetricFilterString(APP_CHECK_ATTESTED_RATIO_METRIC);
    expect(filter).toContain('jsonPayload.fn="deleteAccount"');
    expect(filter).toContain('jsonPayload.fn="aiCoachAdvice"');
    expect(filter).not.toContain('jsonPayload.fn="someFutureCallable"');
  });

  it("renders the real LogMetric shape: metricDescriptor.labels + labelExtractors", () => {
    const json = appCheckAttestedRatioMetricJson() as {
      metricDescriptor: {
        metricKind: string;
        valueType: string;
        labels: Array<{ key: string; valueType: string }>;
      };
      labelExtractors: Record<string, string>;
    };
    expect(json.metricDescriptor.metricKind).toBe("DELTA");
    expect(json.metricDescriptor.valueType).toBe("INT64");
    expect(json.metricDescriptor.labels.map((l) => l.key).sort()).toEqual([
      "attested",
      "fn",
    ]);
    expect(json.labelExtractors.fn).toBe("EXTRACT(jsonPayload.fn)");
    expect(json.labelExtractors.attested).toBe("EXTRACT(jsonPayload.attested)");
  });

  it("keeps labels bounded to fn and attested -- no uid or other unbounded field", () => {
    const keys = APP_CHECK_ATTESTED_RATIO_METRIC.boundedLabels.map(
      (bl) => bl.label.key,
    );
    expect(keys.sort()).toEqual(["attested", "fn"]);
    expect(keys).not.toContain("uid");
  });
});
