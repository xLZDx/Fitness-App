/**
 * P0.G5 -- cloud feasibility / IAM / region / SDK spike.
 *
 * This module defines the typed shape of a P0.G5 probe result and the
 * invariants that make it impossible to silently turn "we could not test
 * this" into "this passed." There is deliberately no boolean `cloudWorks`
 * field -- three-way probe status (NOT_ATTEMPTED | PASS | FAIL) is the only
 * shape that can express "we have no evidence" without lying about it.
 *
 * No live SDK call lives here. P0.G5 closed OCR_TEXT_ONLY_DEFER_VISUAL (see
 * core/equipment_identity/p0/P0_G5_CLOUD_FEASIBILITY.md): no safe
 * non-production Firebase/GCP project exists to prove a visual pipeline
 * against, so every visual probe below is NOT_ATTEMPTED by design, not by
 * omission.
 */

export type ProbeStatus = "NOT_ATTEMPTED" | "PASS" | "FAIL";

export type IamAssessment = "KNOWN" | "PARTIAL" | "UNKNOWN";

export type P0CloudFeasibilityOutcome =
  | "COLOCATED_VECTOR_FEASIBLE"
  | "OCR_TEXT_ONLY_DEFER_VISUAL"
  | "SPLIT_REGION_REQUIRES_OPERATOR";

/** Whether a visual-embedding provider/model has actually been selected and
 * probed, deliberately deferred pending a safe staging environment, or is
 * a real architectural fork that needs an operator decision (region split).
 * Never defaults to "selected" just because a provider name is plausible. */
export type ProviderSelectionStatus =
  | "SELECTED_AND_PROBED"
  | "DEFERRED_NO_SAFE_STAGING"
  | "REQUIRES_OPERATOR_DECISION";

export interface P0CloudFeasibilityResult {
  sourceCommit: string;
  existingFunctionsRegion: string;
  firestoreLocation: string;
  vertexLocationTested: string | null;
  providerSelectionStatus: ProviderSelectionStatus;
  /** null unless providerSelectionStatus === "SELECTED_AND_PROBED" -- see
   * assertValidP0CloudFeasibilityResult. */
  embeddingProvider: string | null;
  embeddingModel: string | null;
  embeddingDimension: number | null;
  firestoreSdkVersion: string | null;
  vertexSdkVersion: string | null;
  firestoreVectorProbe: ProbeStatus;
  vertexEmbeddingProbe: ProbeStatus;
  appCheckCallableProbe: ProbeStatus;
  iamAssessment: IamAssessment;
  latencyMs: number | null;
  costEvidence: string | null;
  dataResidencyAssessment: string;
  outcome: P0CloudFeasibilityOutcome;
  blockers: string[];
  evidence: string[];
}

export class P0CloudFeasibilityValidationError extends Error {}

const PROBE_STATUSES: readonly ProbeStatus[] = ["NOT_ATTEMPTED", "PASS", "FAIL"];
const OUTCOMES: readonly P0CloudFeasibilityOutcome[] = [
  "COLOCATED_VECTOR_FEASIBLE",
  "OCR_TEXT_ONLY_DEFER_VISUAL",
  "SPLIT_REGION_REQUIRES_OPERATOR",
];
const PROVIDER_SELECTION_STATUSES: readonly ProviderSelectionStatus[] = [
  "SELECTED_AND_PROBED",
  "DEFERRED_NO_SAFE_STAGING",
  "REQUIRES_OPERATOR_DECISION",
];
const IAM_ASSESSMENTS: readonly IamAssessment[] = ["KNOWN", "PARTIAL", "UNKNOWN"];

// A cheap, real second check -- this module only ever records hand-written
// evidence strings, so nothing here should ever look like a live
// credential. Not a substitute for never putting a secret in the object in
// the first place; a backstop, not the primary control.
const SECRET_LOOKING_RE =
  /(AIza[0-9A-Za-z_-]{20,}|ya29\.[0-9A-Za-z_-]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)/;

function assertNoSecretLikeStrings(result: P0CloudFeasibilityResult): void {
  const haystacks = [
    ...result.evidence,
    ...result.blockers,
    result.costEvidence ?? "",
    result.dataResidencyAssessment,
  ];
  for (const s of haystacks) {
    if (SECRET_LOOKING_RE.test(s)) {
      throw new P0CloudFeasibilityValidationError(
        "result contains a string that looks like a live credential/token -- refusing to record it"
      );
    }
  }
}

/**
 * Raises on any internally inconsistent or credential-absence-laundered
 * result. A valid object passing this check is not a claim that the
 * OUTCOME is the right one -- only that the record is internally honest
 * about what was and was not actually proven.
 */
export function assertValidP0CloudFeasibilityResult(result: P0CloudFeasibilityResult): void {
  if (!OUTCOMES.includes(result.outcome)) {
    throw new P0CloudFeasibilityValidationError(`unknown outcome ${String(result.outcome)}`);
  }
  for (const [field, value] of [
    ["firestoreVectorProbe", result.firestoreVectorProbe],
    ["vertexEmbeddingProbe", result.vertexEmbeddingProbe],
    ["appCheckCallableProbe", result.appCheckCallableProbe],
  ] as const) {
    if (!PROBE_STATUSES.includes(value)) {
      throw new P0CloudFeasibilityValidationError(`${field} has an unknown probe status ${String(value)}`);
    }
  }
  if (!PROVIDER_SELECTION_STATUSES.includes(result.providerSelectionStatus)) {
    throw new P0CloudFeasibilityValidationError(
      `unknown providerSelectionStatus ${String(result.providerSelectionStatus)}`
    );
  }
  if (!IAM_ASSESSMENTS.includes(result.iamAssessment)) {
    throw new P0CloudFeasibilityValidationError(`unknown iamAssessment ${String(result.iamAssessment)}`);
  }

  // A region cannot have been "tested" without the probe that would have
  // tested it actually running -- vertexLocationTested implies a real
  // vertexEmbeddingProbe attempt, not the other way around.
  if (result.vertexLocationTested !== null && result.vertexEmbeddingProbe === "NOT_ATTEMPTED") {
    throw new P0CloudFeasibilityValidationError(
      "vertexLocationTested is set but vertexEmbeddingProbe is NOT_ATTEMPTED -- a location cannot be " +
        "recorded as tested without a probe that actually tested it"
    );
  }

  // COLOCATED_VECTOR_FEASIBLE requires every required probe to have
  // genuinely PASSed -- never NOT_ATTEMPTED, never FAIL. Credential/
  // environment absence (NOT_ATTEMPTED) can never silently become a PASS.
  // It also requires knowing WHY it passed (a KNOWN/PARTIAL IAM picture,
  // not UNKNOWN) and which SDK versions were actually exercised, so the
  // result can be reproduced or re-verified later.
  if (result.outcome === "COLOCATED_VECTOR_FEASIBLE") {
    for (const [field, value] of [
      ["firestoreVectorProbe", result.firestoreVectorProbe],
      ["vertexEmbeddingProbe", result.vertexEmbeddingProbe],
      ["appCheckCallableProbe", result.appCheckCallableProbe],
    ] as const) {
      if (value !== "PASS") {
        throw new P0CloudFeasibilityValidationError(
          `outcome=COLOCATED_VECTOR_FEASIBLE requires ${field}=PASS, got ${value}`
        );
      }
    }
    if (result.providerSelectionStatus !== "SELECTED_AND_PROBED") {
      throw new P0CloudFeasibilityValidationError(
        "outcome=COLOCATED_VECTOR_FEASIBLE requires providerSelectionStatus=SELECTED_AND_PROBED"
      );
    }
    if (result.iamAssessment === "UNKNOWN") {
      throw new P0CloudFeasibilityValidationError(
        "outcome=COLOCATED_VECTOR_FEASIBLE requires a KNOWN or PARTIAL iamAssessment, not UNKNOWN -- " +
          "a passing probe with no idea which permissions let it pass is not reproducible evidence"
      );
    }
    if (result.firestoreSdkVersion === null || result.vertexSdkVersion === null) {
      throw new P0CloudFeasibilityValidationError(
        "outcome=COLOCATED_VECTOR_FEASIBLE requires firestoreSdkVersion and vertexSdkVersion to be " +
          "recorded -- otherwise the result cannot say which SDK version was actually exercised"
      );
    }
  }

  // SPLIT_REGION is always an operator decision -- never something this
  // gate can accept or use to autonomously mutate infrastructure.
  if (result.outcome === "SPLIT_REGION_REQUIRES_OPERATOR") {
    if (result.providerSelectionStatus !== "REQUIRES_OPERATOR_DECISION") {
      throw new P0CloudFeasibilityValidationError(
        "outcome=SPLIT_REGION_REQUIRES_OPERATOR requires providerSelectionStatus=REQUIRES_OPERATOR_DECISION"
      );
    }
    if (result.blockers.length === 0) {
      throw new P0CloudFeasibilityValidationError(
        "outcome=SPLIT_REGION_REQUIRES_OPERATOR requires at least one recorded blocker"
      );
    }
  }

  // OCR_TEXT_ONLY_DEFER_VISUAL is the fail-closed default and must be
  // reachable with every visual probe untouched -- it must never carry a
  // selected embedding provider (which would contradict "visual is
  // deferred"), never claim providerSelectionStatus=SELECTED_AND_PROBED
  // (the same contradiction from the other field), and must always name at
  // least one real blocker -- "deferred" with zero recorded reason is not
  // an honest record of why.
  if (result.outcome === "OCR_TEXT_ONLY_DEFER_VISUAL") {
    if (
      result.embeddingProvider !== null ||
      result.embeddingModel !== null ||
      result.embeddingDimension !== null
    ) {
      throw new P0CloudFeasibilityValidationError(
        "outcome=OCR_TEXT_ONLY_DEFER_VISUAL must not record a selected embedding provider/model/dimension"
      );
    }
    if (result.providerSelectionStatus === "SELECTED_AND_PROBED") {
      throw new P0CloudFeasibilityValidationError(
        "outcome=OCR_TEXT_ONLY_DEFER_VISUAL contradicts providerSelectionStatus=SELECTED_AND_PROBED -- " +
          "visual cannot be simultaneously deferred and already selected/probed"
      );
    }
    if (result.blockers.length === 0) {
      throw new P0CloudFeasibilityValidationError(
        "outcome=OCR_TEXT_ONLY_DEFER_VISUAL requires at least one recorded blocker -- deferring visual " +
          "feasibility with no recorded reason is not an honest record"
      );
    }
  }

  assertNoSecretLikeStrings(result);
}
