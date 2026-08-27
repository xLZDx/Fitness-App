import {
  AI_GATEWAY_OPERATIONS,
  AI_GATEWAY_OUTCOMES,
  AI_GATEWAY_CALLS_METRIC,
  AI_GATEWAY_LATENCY_METRIC,
  AI_GATEWAY_TOKENS_METRIC,
  AI_GATEWAY_QUOTA_EXHAUSTIONS_METRIC,
  aiGatewayCallsMetricJson,
  aiGatewayLatencyMetricJson,
  aiGatewayTokensMetricJson,
  aiGatewayQuotaExhaustionsMetricJson,
  queryAllCalls,
  queryFailures,
  queryTimeoutsFor,
  queryErrorsFor,
  queryUsagePresent,
  queryQuotaExhausted,
  queryQuotaCheckFailed,
} from "../ai_gateway_definitions";
import {
  counterLogMetricFilterString,
  distributionLogMetricFilterString,
} from "../types";
import * as signals from "../log_signals";
import * as aiGateway from "../../ai_gateway";

type CounterMetricJson = {
  name: string;
  filter: string;
  metricDescriptor: {
    metricKind: string;
    valueType: string;
    labels: Array<{ key: string; valueType: string }>;
  };
  labelExtractors: Record<string, string>;
};

type DistributionMetricJson = CounterMetricJson & {
  valueExtractor: string;
  bucketOptions: { explicitBuckets: { bounds: number[] } };
};

describe("AI_GATEWAY_OPERATIONS / AI_GATEWAY_OUTCOMES source of truth", () => {
  it("is a re-export of ai_gateway.ts's own tuple, not an independently maintained copy", () => {
    // Referential identity, not just value equality: this is the actual
    // structural fix for GPT-PM's finding on commit c7a498e (a second,
    // independently-declared array here was bounded only by a `satisfies`
    // check, which proves every array element is valid but not that every
    // union member is present -- a real gap when a 5th operation is added
    // later). There is now exactly one array; this test fails if a future
    // edit reintroduces a second declaration instead of importing this one.
    expect(AI_GATEWAY_OPERATIONS).toBe(aiGateway.AI_GATEWAY_OPERATIONS);
    expect(AI_GATEWAY_OUTCOMES).toBe(aiGateway.AI_GATEWAY_OUTCOMES);
  });

  it("has exactly the four known AI Gateway operations", () => {
    expect(AI_GATEWAY_OPERATIONS).toEqual([
      "aiCoachAdvice",
      "aiEquipmentRecognition",
      "aiMachineDescription",
      "aiExerciseGeneration",
    ]);
  });
});

describe("ai_gateway_calls counter metric", () => {
  it("filters on the exact event message and bounds both labels", () => {
    const filter = counterLogMetricFilterString(AI_GATEWAY_CALLS_METRIC);
    expect(filter).toContain(`jsonPayload.message="${signals.AI_GATEWAY_CALL_EVENT}"`);
    for (const op of AI_GATEWAY_OPERATIONS) {
      expect(filter).toContain(`jsonPayload.operation="${op}"`);
    }
    for (const outcome of ["success", "timeout", "error"]) {
      expect(filter).toContain(`jsonPayload.outcome="${outcome}"`);
    }
  });

  it("does not bound an unknown operation or outcome (cardinality cap)", () => {
    const filter = counterLogMetricFilterString(AI_GATEWAY_CALLS_METRIC);
    expect(filter).not.toContain('jsonPayload.operation="someFutureOperation"');
    expect(filter).not.toContain('jsonPayload.outcome="cancelled"');
  });

  it("renders the real LogMetric shape: metricDescriptor.labels + labelExtractors", () => {
    const json = aiGatewayCallsMetricJson() as CounterMetricJson;
    expect(json.metricDescriptor.metricKind).toBe("DELTA");
    expect(json.metricDescriptor.valueType).toBe("INT64");
    expect(json.metricDescriptor.labels.map((l) => l.key).sort()).toEqual([
      "operation",
      "outcome",
    ]);
    expect(json.labelExtractors.operation).toBe("EXTRACT(jsonPayload.operation)");
    expect(json.labelExtractors.outcome).toBe("EXTRACT(jsonPayload.outcome)");
  });

  it("caps at 4 operations x 3 outcomes = 12 max time series", () => {
    const opCount = AI_GATEWAY_CALLS_METRIC.boundedLabels.find(
      (bl) => bl.label.key === "operation",
    )?.allowedValues.length;
    const outcomeCount = AI_GATEWAY_CALLS_METRIC.boundedLabels.find(
      (bl) => bl.label.key === "outcome",
    )?.allowedValues.length;
    expect((opCount ?? 0) * (outcomeCount ?? 0)).toBe(12);
  });
});

describe("ai_gateway_latency_ms distribution metric", () => {
  it("extracts latencyMs and uses explicit buckets covering the known timeouts", () => {
    const json = aiGatewayLatencyMetricJson() as DistributionMetricJson;
    expect(json.metricDescriptor.metricKind).toBe("DELTA");
    expect(json.metricDescriptor.valueType).toBe("DISTRIBUTION");
    expect(json.valueExtractor).toBe("EXTRACT(jsonPayload.latencyMs)");
    const bounds = json.bucketOptions.explicitBuckets.bounds;
    // This codebase's own configured per-operation timeouts (grep-verified
    // against each ai_*.ts callable's timeoutMs) must fall within range.
    expect(Math.max(...bounds)).toBeGreaterThan(45_000);
    expect(Math.min(...bounds)).toBeLessThan(1_000);
    expect(bounds).toContain(20000);
    expect(bounds).toContain(25000);
    expect(bounds).toContain(45000);
  });

  it("filters on the same message and label bounds as the call counter", () => {
    const filter = distributionLogMetricFilterString(AI_GATEWAY_LATENCY_METRIC);
    expect(filter).toContain(`jsonPayload.message="${signals.AI_GATEWAY_CALL_EVENT}"`);
  });
});

describe("ai_gateway_total_tokens_per_call distribution metric", () => {
  it("extracts totalTokenCount and requires its presence, but not outcome=success", () => {
    const json = aiGatewayTokensMetricJson() as DistributionMetricJson;
    expect(json.valueExtractor).toBe("EXTRACT(jsonPayload.totalTokenCount)");
    expect(json.filter).toContain("jsonPayload.totalTokenCount:*");
    // Deliberately does NOT restrict to outcome="success" -- usage can be
    // spent on a call that still ends in "error" (empty-answer case,
    // ai_gateway.ts:281 captures usage before the empty check). Confirm
    // "error" and "timeout" remain in the bounded outcome set, not just
    // "success".
    expect(json.filter).toContain('jsonPayload.outcome="error"');
    expect(json.filter).toContain('jsonPayload.outcome="timeout"');
    expect(json.filter).toContain('jsonPayload.outcome="success"');
  });

  it("uses bucket bounds covering the configured maxOutputTokens range with headroom", () => {
    const bounds = AI_GATEWAY_TOKENS_METRIC.bucketOptions.bounds;
    // maxOutputTokens across the four callables ranges 256-1024
    // (grep-verified); prompt/image tokens add further headroom.
    expect(Math.max(...bounds)).toBeGreaterThan(1024);
    expect(Math.min(...bounds)).toBeLessThan(256);
  });
});

describe("ai_gateway_quota_exhaustions counter metric", () => {
  it("filters on the quota-exceeded event, bounded to exactly the 4 AI actions", () => {
    const json = aiGatewayQuotaExhaustionsMetricJson() as CounterMetricJson;
    expect(json.filter).toContain(`jsonPayload.message="${signals.QUOTA_EXCEEDED_EVENT}"`);
    for (const op of AI_GATEWAY_OPERATIONS) {
      expect(json.filter).toContain(`jsonPayload.action="${op}"`);
    }
  });

  it("does not include a non-AI quota action (accountExport, clipUrl, etc.)", () => {
    const json = aiGatewayQuotaExhaustionsMetricJson() as CounterMetricJson;
    expect(json.filter).not.toContain('jsonPayload.action="accountExport"');
    expect(json.filter).not.toContain('jsonPayload.action="clipUrl"');
  });

  it("labels the extracted field as 'operation', reading from jsonPayload.action", () => {
    const json = aiGatewayQuotaExhaustionsMetricJson() as CounterMetricJson;
    expect(json.labelExtractors.operation).toBe("EXTRACT(jsonPayload.action)");
  });

  it("has bounded cardinality of at most 4 (one per AI action)", () => {
    const allowed = AI_GATEWAY_QUOTA_EXHAUSTIONS_METRIC.boundedLabels[0].allowedValues;
    expect(allowed).toHaveLength(4);
  });
});

describe("investigation queries", () => {
  it("queryAllCalls matches the exact event message, scoped to Cloud Run", () => {
    const q = queryAllCalls();
    expect(q).toContain('resource.type="cloud_run_revision"');
    expect(q).toContain(`jsonPayload.message="${signals.AI_GATEWAY_CALL_EVENT}"`);
  });

  it("queryFailures matches error or timeout, not success", () => {
    const q = queryFailures();
    expect(q).toContain('jsonPayload.outcome="error"');
    expect(q).toContain('jsonPayload.outcome="timeout"');
    expect(q).not.toContain('jsonPayload.outcome="success"');
  });

  it("queryTimeoutsFor/queryErrorsFor scope to one operation and one outcome", () => {
    const timeouts = queryTimeoutsFor("aiCoachAdvice");
    expect(timeouts).toContain('jsonPayload.operation="aiCoachAdvice"');
    expect(timeouts).toContain('jsonPayload.outcome="timeout"');
    const errors = queryErrorsFor("aiMachineDescription");
    expect(errors).toContain('jsonPayload.operation="aiMachineDescription"');
    expect(errors).toContain('jsonPayload.outcome="error"');
  });

  it("queryUsagePresent requires totalTokenCount to exist", () => {
    expect(queryUsagePresent()).toContain("jsonPayload.totalTokenCount:*");
  });

  it("queryQuotaExhausted and queryQuotaCheckFailed key on different messages, both bounded to AI actions", () => {
    const exhausted = queryQuotaExhausted();
    expect(exhausted).toContain(`jsonPayload.message="${signals.QUOTA_EXCEEDED_EVENT}"`);
    const checkFailed = queryQuotaCheckFailed();
    expect(checkFailed).toContain(`jsonPayload.message="${signals.QUOTA_CHECK_FAILED_EVENT}"`);
    for (const q of [exhausted, checkFailed]) {
      for (const op of AI_GATEWAY_OPERATIONS) {
        expect(q).toContain(`jsonPayload.action="${op}"`);
      }
    }
  });
});
