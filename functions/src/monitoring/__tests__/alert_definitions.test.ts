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
  event?: string,
): LogEntryFixture {
  return { serviceName, message, severity, ...(event !== undefined ? { event } : {}) };
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
  // MVP1.G3 Step 10C (2026-08-28): this filter used to be messageEquals,
  // which GPT-PM round-8's finding (proven for enforcement_state, same root
  // cause here) means never matches a real logger.error(EVENT, {...}) call --
  // firebase-functions' entryFromArgs rewrites `message` into
  // "Error: EVENT\n    at ..." for ERROR severity. index.ts:1913,1921 now
  // set `event: EVENT` explicitly, and the filter matches on that field.
  it("matches both real failure events via the event field, using the REAL decorated message shape", () => {
    for (const eventName of [
      signals.STRIPE_RECONCILE_CANCEL_FAILED,
      signals.STRIPE_RECONCILE_FAILED,
    ]) {
      const realDecoratedMessage = `Error: ${eventName}\n    at entryFromArgs (/workspace/node_modules/firebase-functions/lib/logger/index.js:144:19)`;
      expect(
        matchesLogMatchFilter(
          STRIPE_RECONCILIATION_FAILURE_FILTER,
          entry("stripewebhook", realDecoratedMessage, "ERROR", eventName),
        ),
      ).toBe(true);
    }
  });

  it("does NOT match on the raw undecorated event string as a message with no event field (the pre-fix bug)", () => {
    expect(
      matchesLogMatchFilter(
        STRIPE_RECONCILIATION_FAILURE_FILTER,
        entry("stripewebhook", signals.STRIPE_RECONCILE_CANCEL_FAILED),
      ),
    ).toBe(false);
  });

  it("does not match the two non-failure log lines from the same code path", () => {
    expect(
      matchesLogMatchFilter(
        STRIPE_RECONCILIATION_FAILURE_FILTER,
        entry(
          "stripewebhook",
          "irrelevant",
          "WARNING",
          signals.STRIPE_RECONCILE_DUPLICATE_FOUND,
        ),
      ),
    ).toBe(false);
    expect(
      matchesLogMatchFilter(
        STRIPE_RECONCILIATION_FAILURE_FILTER,
        entry("stripewebhook", "irrelevant", "INFO", signals.STRIPE_RECONCILE_CANCEL_OK),
      ),
    ).toBe(false);
  });

  it("does not match the identical event from a different service", () => {
    expect(
      matchesLogMatchFilter(
        STRIPE_RECONCILIATION_FAILURE_FILTER,
        entry("deleteaccount", "irrelevant", "ERROR", signals.STRIPE_RECONCILE_FAILED),
      ),
    ).toBe(false);
  });

  it("renders a Gen2-shaped filter string scoped to the stripewebhook Cloud Run service, keyed on jsonPayload.event", () => {
    const filter = stripeReconciliationAlertFilterString();
    expect(filter).toContain('resource.type="cloud_run_revision"');
    expect(filter).toContain('resource.labels.service_name="stripewebhook"');
    expect(filter).not.toContain("function_name");
    expect(filter).toContain(
      `jsonPayload.event="${signals.STRIPE_RECONCILE_CANCEL_FAILED}"`,
    );
    expect(filter).toContain(`jsonPayload.event="${signals.STRIPE_RECONCILE_FAILED}"`);
    expect(filter).not.toContain("jsonPayload.message=");
  });
});

describe("deleteAccount operational-failure alert filter", () => {
  // MVP1.G3 Step 10C: index.ts:2134,2171,2193 now set `event: EVENT`
  // explicitly for all three named failure paths -- same fix as Stripe above.
  it("matches all three explicit failure paths via the event field, using the REAL decorated message shape", () => {
    for (const eventName of [
      signals.DELETE_ACCOUNT_STRIPE_CANCEL_FAILED,
      signals.DELETE_ACCOUNT_FIRESTORE_DELETE_FAILED,
      signals.DELETE_ACCOUNT_AUTH_DELETE_FAILED,
    ]) {
      const realDecoratedMessage = `Error: ${eventName}\n    at entryFromArgs (...)`;
      expect(
        matchesLogMatchFilter(
          DELETE_ACCOUNT_FAILURE_FILTER,
          entry("deleteaccount", realDecoratedMessage, "ERROR", eventName),
        ),
      ).toBe(true);
    }
  });

  it("does NOT match on the raw undecorated event string as a message with no event field (the pre-fix bug)", () => {
    expect(
      matchesLogMatchFilter(
        DELETE_ACCOUNT_FAILURE_FILTER,
        entry("deleteaccount", signals.DELETE_ACCOUNT_FIRESTORE_DELETE_FAILED),
      ),
    ).toBe(false);
  });

  it("matches the platform backstop for a failure outside the three named catches, via messageContains", () => {
    // Covers, e.g., the pre-try Firestore read at index.ts:2086 -- no
    // explicit catch names it, but firebase-functions' own https.js wraps
    // the whole handler and logs `logger.error("Unhandled error", err)` for
    // anything that isn't already an HttpsError. This is framework code --
    // this repo cannot attach an `event` field to it -- so the filter uses
    // `messageContains` instead: `entryFromArgs` runs this through
    // `util.format("Unhandled error", err)`, which always PREFIXES the
    // literal "Unhandled error" but appends the inspected err afterward, so
    // an exact `messageEquals` never matches either (a second, independent
    // reason the original filter was broken, on top of the Error-stack
    // rewrite -- `err` here already `instanceof Error`, so that particular
    // rewrite's own guard does not even apply; the appended detail is what
    // breaks exact equality instead). See README.md's failure-path audit.
    expect(
      matchesLogMatchFilter(
        DELETE_ACCOUNT_FAILURE_FILTER,
        entry(
          "deleteaccount",
          `${signals.PLATFORM_UNHANDLED_ERROR} Error: something internal\n    at ...`,
        ),
      ),
    ).toBe(true);
  });

  it("matches the platform backstop case-insensitively, same as Cloud Logging's real `:` operator", () => {
    // GPT-PM MINOR (Step 10C, round 1): the real GCP `:` (has/contains)
    // operator matches substrings case-insensitively -- the simulator must
    // reproduce that, not silently assume the framework's literal casing is
    // the only one that will ever appear.
    expect(
      matchesLogMatchFilter(
        DELETE_ACCOUNT_FAILURE_FILTER,
        entry("deleteaccount", "UNHANDLED ERROR: something internal"),
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
    expect(DELETE_ACCOUNT_FAILURE_FILTER.eventEquals).not.toContain(
      "unauthenticated",
    );
  });

  it("does not match exportAccountData's identical-shaped platform backstop", () => {
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
    expect(filter).toContain(
      `jsonPayload.event="${signals.DELETE_ACCOUNT_STRIPE_CANCEL_FAILED}"`,
    );
    expect(filter).toContain(`jsonPayload.message:"${signals.PLATFORM_UNHANDLED_ERROR}"`);
  });
});

describe("exportAccountData operational-failure alert filter", () => {
  // MVP1.G3 Step 10C: account_export.ts:317 now sets `event: EXPORT_ACCOUNT_FAILED`.
  it("matches the explicit failure via the event field, using the REAL decorated message shape", () => {
    const realDecoratedMessage = `Error: ${signals.EXPORT_ACCOUNT_FAILED}\n    at entryFromArgs (...)`;
    expect(
      matchesLogMatchFilter(
        EXPORT_ACCOUNT_FAILURE_FILTER,
        entry(
          "exportaccountdata",
          realDecoratedMessage,
          "ERROR",
          signals.EXPORT_ACCOUNT_FAILED,
        ),
      ),
    ).toBe(true);
  });

  it("does NOT match on the raw undecorated event string as a message with no event field (the pre-fix bug)", () => {
    expect(
      matchesLogMatchFilter(
        EXPORT_ACCOUNT_FAILURE_FILTER,
        entry("exportaccountdata", signals.EXPORT_ACCOUNT_FAILED),
      ),
    ).toBe(false);
  });

  it("matches the platform backstop via messageContains", () => {
    expect(
      matchesLogMatchFilter(
        EXPORT_ACCOUNT_FAILURE_FILTER,
        entry(
          "exportaccountdata",
          `${signals.PLATFORM_UNHANDLED_ERROR} Error: something internal\n    at ...`,
        ),
      ),
    ).toBe(true);
  });

  it("does not match deleteAccount's identical-shaped platform backstop", () => {
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
    expect(filter).toContain(`jsonPayload.event="${signals.EXPORT_ACCOUNT_FAILED}"`);
    expect(filter).toContain(`jsonPayload.message:"${signals.PLATFORM_UNHANDLED_ERROR}"`);
  });
});

describe("production canary probe-failure alert filter", () => {
  // MVP1.G3 Step 10C: canary_schedule.ts:99,110 now set
  // `event: CANARY_PROBE_FAILED_EVENT` explicitly -- same fix as above.
  it("matches the canary's own thrown-failure log via the event field, using the REAL decorated message shape", () => {
    const realDecoratedMessage = `Error: ${signals.CANARY_PROBE_FAILED_EVENT}\n    at entryFromArgs (...)`;
    expect(
      matchesLogMatchFilter(
        CANARY_PROBE_FAILURE_FILTER,
        entry(
          "runproductioncanary",
          realDecoratedMessage,
          "ERROR",
          signals.CANARY_PROBE_FAILED_EVENT,
        ),
      ),
    ).toBe(true);
  });

  it("does NOT match on the raw undecorated event string as a message with no event field (the pre-fix bug)", () => {
    expect(
      matchesLogMatchFilter(
        CANARY_PROBE_FAILURE_FILTER,
        entry("runproductioncanary", signals.CANARY_PROBE_FAILED_EVENT),
      ),
    ).toBe(false);
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
    expect(CANARY_PROBE_FAILURE_FILTER.messageContains).toBeUndefined();
  });

  it("does not match an identical-shaped failure from a different service", () => {
    expect(
      matchesLogMatchFilter(
        CANARY_PROBE_FAILURE_FILTER,
        entry(
          "deleteaccount",
          "irrelevant",
          "ERROR",
          signals.CANARY_PROBE_FAILED_EVENT,
        ),
      ),
    ).toBe(false);
  });

  it("renders a Gen2-shaped filter string scoped to the runproductioncanary Cloud Run service, keyed on jsonPayload.event", () => {
    const filter = canaryProbeAlertFilterString();
    expect(filter).toContain('resource.type="cloud_run_revision"');
    expect(filter).toContain(
      'resource.labels.service_name="runproductioncanary"',
    );
    expect(filter).toContain(`jsonPayload.event="${signals.CANARY_PROBE_FAILED_EVENT}"`);
    expect(filter).not.toContain("jsonPayload.message=");
  });
});

describe("enforcement-state check failure alert filter", () => {
  it("matches the check's own degraded-or-failed log via the event field", () => {
    expect(
      matchesLogMatchFilter(
        ENFORCEMENT_STATE_FAILURE_FILTER,
        entry(
          "runenforcementstatecheck",
          "irrelevant -- this filter no longer keys on message",
          "ERROR",
          signals.ENFORCEMENT_STATE_DEGRADED_OR_FAILED_EVENT,
        ),
      ),
    ).toBe(true);
  });

  // GPT-PM round-8 finding (Step 10A live-activation, real-failure proof,
  // 2026-08-27): confirmed via `firebase-functions/logger`'s own source that
  // `logger.error(EVENT, {...})` unconditionally rewrites `jsonPayload.message`
  // into `"Error: EVENT\n    at ..."` for ERROR severity. This fixture models
  // that REAL decorated shape (not the intended input string) using the exact
  // text from the captured production log entry
  // (`core/evidence/step10a_proof_only_real_failure_log_2026-08-27.json`) --
  // proving the filter matches the actual logger output, not a hypothetical
  // undecorated one.
  it("matches the REAL firebase-functions logger output (Error-prefixed, stack-suffixed), not the raw event string", () => {
    const realDecoratedMessage =
      "Error: enforcement state check degraded or failed\n" +
      "    at entryFromArgs (/workspace/node_modules/firebase-functions/lib/logger/index.js:144:19)\n" +
      "    at Object.error (/workspace/node_modules/firebase-functions/lib/logger/index.js:131:11)";
    const realEntry = entry(
      "runenforcementstatecheck",
      realDecoratedMessage,
      "ERROR",
      signals.ENFORCEMENT_STATE_DEGRADED_OR_FAILED_EVENT,
    );
    expect(matchesLogMatchFilter(ENFORCEMENT_STATE_FAILURE_FILTER, realEntry)).toBe(true);
  });

  it("does NOT match on the raw undecorated event string as a message (the bug this round fixed)", () => {
    // Proves the old messageEquals-based filter's failure mode: an entry
    // whose `message` equals the raw event string but has no `event` field
    // (what messageEquals actually needed) must NOT match via eventEquals.
    const undecoratedOnlyEntry = entry(
      "runenforcementstatecheck",
      signals.ENFORCEMENT_STATE_DEGRADED_OR_FAILED_EVENT,
      "ERROR",
      // no event field -- simulates the pre-fix log shape
    );
    expect(matchesLogMatchFilter(ENFORCEMENT_STATE_FAILURE_FILTER, undecoratedOnlyEntry)).toBe(
      false,
    );
  });

  it("does not match PLATFORM_UNHANDLED_ERROR -- onSchedule's own wrapper never logs it", () => {
    // Same documented reason as the canary's own filter above: this is an
    // onSchedule function, not onCall, so https.js's platform backstop
    // never applies to it.
    expect(ENFORCEMENT_STATE_FAILURE_FILTER.eventEquals).not.toContain(
      signals.PLATFORM_UNHANDLED_ERROR,
    );
  });

  it("does not match an identical-shaped failure from a different service", () => {
    expect(
      matchesLogMatchFilter(
        ENFORCEMENT_STATE_FAILURE_FILTER,
        entry(
          "runproductioncanary",
          "irrelevant",
          "ERROR",
          signals.ENFORCEMENT_STATE_DEGRADED_OR_FAILED_EVENT,
        ),
      ),
    ).toBe(false);
  });

  it("renders a Gen2-shaped filter string scoped to the runenforcementstatecheck Cloud Run service, keyed on jsonPayload.event", () => {
    const filter = enforcementStateAlertFilterString();
    expect(filter).toContain('resource.type="cloud_run_revision"');
    expect(filter).toContain(
      'resource.labels.service_name="runenforcementstatecheck"',
    );
    expect(filter).toContain(
      `jsonPayload.event="${signals.ENFORCEMENT_STATE_DEGRADED_OR_FAILED_EVENT}"`,
    );
    expect(filter).not.toContain("jsonPayload.message=");
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
    // 18h, not the original 24h -- the real API rejects any conditionAbsent
    // duration over 23h30m (confirmed live at Step 10A activation).
    expect(policy.conditions[0].conditionAbsent?.duration).toBe("64800s");
  });

  it("filters on the deployed function's own Cloud Run request_count, not a custom log", () => {
    // Round-2 correction, live activation: `cloudscheduler.googleapis.com/job/execution_count`
    // does not exist -- Cloud Scheduler does not publish platform metrics into Cloud
    // Monitoring at all (confirmed live: zero metric descriptors under that prefix for this
    // project, even for the long-running canary job). `run.googleapis.com/request_count` on
    // the function's own `cloud_run_revision` is real and confirmed populated immediately.
    const policy = enforcementStateStalenessPolicyJson() as {
      conditions: Array<{ conditionAbsent?: { filter: string } }>;
    };
    const filter = policy.conditions[0].conditionAbsent?.filter ?? "";
    expect(filter).toContain('metric.type="run.googleapis.com/request_count"');
    expect(filter).toContain('resource.type="cloud_run_revision"');
    expect(filter).toContain('resource.labels.service_name="runenforcementstatecheck"');
    expect(filter).not.toContain("cloudscheduler.googleapis.com");
  });

  it("requires a 2xx response class, so a crashing checker doesn't read as fresh", () => {
    // Round-4 correction, GPT-PM live-activation review: request_count alone counts
    // failed/5xx invocations too -- Cloud Run still emits a request_count point for a
    // crashing checker, defeating the staleness check. Confirmed live: `response_code_class`
    // is a real label on this exact metric/resource combination.
    const policy = enforcementStateStalenessPolicyJson() as {
      conditions: Array<{ conditionAbsent?: { filter: string } }>;
    };
    const filter = policy.conditions[0].conditionAbsent?.filter ?? "";
    expect(filter).toContain('metric.labels.response_code_class="2xx"');
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
