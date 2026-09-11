/**
 * P2.G3 -- the full v4.1 CONSENSUS §6.2 "cheap exact-model path" policy
 * (SPTR_EQUIPMENT_RECOGNITION_MASTER_TECHNICAL_PLAN_v4.1_CONSENSUS_2026-08-21.md,
 * lines 347-363, still binding per the P2.G3 gate contract's own
 * cross-reference). A unique model-code match may emit exact identity only
 * when ALL of the following pass:
 *
 *   1. model code is unique in the current (pinned) catalog version;
 *   2. no conflicting model code is present (a different candidate resolves
 *      to a different real model);
 *   3. OCR region is compatible with the central-machine/placard ownership
 *      policy -- carried here as P2.G2's own `conflicts[]` field, which is
 *      exactly where identity_text_parser.dart records a cross-cluster
 *      ownership ambiguity (see ambiguous-ownership branch of
 *      `parseIdentityText`);
 *   4. O<->0 / I<->1 OCR-confusion substitutions may create candidates but
 *      never exact certainty without corroboration;
 *   5. type evidence is reconciled by authority: VERIFIED/high-assurance
 *      generic type conflict -> NEED_MORE_VIEW; low-confidence, ambiguous
 *      or offline-fallback type is soft evidence and cannot veto a unique
 *      verified model-code match;
 *   6. textSupportStatus for the model is VERIFIED for a PRODUCTION claim;
 *      EXPERIMENTAL may only ever produce a SHADOW-only candidate (P2.G3
 *      Story DoD, gate contract §"P2.G3").
 *
 * This gate is text-only -- no image is uploaded (privacy/cost
 * optimization, v4.1 §6.2's own closing note). `typeEvidence` IS threaded
 * from the real request in production (orchestrator.ts's
 * `deriveTypeEvidence`, GPT-PM MAJOR fix, P2.G3 pre-commit review,
 * 2026-09-11) -- but only ever as LOW_CONFIDENCE/AMBIGUOUS, never
 * HIGH_ASSURANCE/VERIFIED, since an OCR-derived type-hint phrase has no
 * typeId-vocabulary alignment with a catalog model's canonical
 * `primaryTypeId`/`supportedTypeIds` to assert that level of confidence
 * about. The HIGH_ASSURANCE/VERIFIED veto branch this condition also
 * implements is therefore real and tested here, but reachable in
 * production only by a FUTURE caller with genuine visual/classifier
 * evidence (P4 fusion), not by this gate's own text-only wiring.
 */
import type { ModelCodeLookupResult } from "./text_key_index";

export type TextSupportStatus = "NONE" | "EXPERIMENTAL" | "VERIFIED";

export type GenericTypeEvidenceStatus =
  | "VERIFIED"
  | "HIGH_ASSURANCE"
  | "LOW_CONFIDENCE"
  | "AMBIGUOUS"
  | "OFFLINE_FALLBACK";

export interface GenericTypeEvidence {
  status: GenericTypeEvidenceStatus;
  typeId: string;
}

export interface CatalogModelFields {
  modelId: string;
  catalogVersion: string;
  textSupportStatus: TextSupportStatus;
  primaryTypeId: string;
  supportedTypeIds: string[];
}

export interface ResolvedCandidate {
  rawCandidate: string;
  lookup: ModelCodeLookupResult;
}

export interface ExactPolicyInput {
  /** One entry per DISTINCT raw modelCodeCandidate string from the P2.G2
   * evidence, each already resolved against the pinned catalog via
   * text_key_index.ts's `resolveModelCodeLookup` (this function is pure --
   * it performs no Firestore I/O itself). */
  candidates: ResolvedCandidate[];
  /** P2.G2's own `ParsedIdentityText.conflicts` field. */
  parserConflicts: string[];
  /** Pre-fetched catalog fields for every UNIQUE-resolved modelId that
   * appears in `candidates`. Only the winning model's entry is actually
   * consulted, but the caller does not need to know in advance which one
   * that will be. */
  modelFieldsByModelId: Map<string, CatalogModelFields>;
  typeEvidence?: GenericTypeEvidence;
}

export type ExactPolicyResult =
  | { outcome: "EXACT_PRODUCTION"; modelId: string; catalogVersion: string }
  | {
      outcome: "EXACT_SHADOW_ONLY";
      modelId: string;
      catalogVersion: string;
      reason: "EXPERIMENTAL_TEXT_SUPPORT";
    }
  | { outcome: "NEED_MORE_VIEW"; reason: string }
  | { outcome: "ABSTAIN"; abstainReason: "EVIDENCE_CONFLICT" | "LOW_CONFIDENCE"; reason: string }
  | { outcome: "NOT_ELIGIBLE"; reason: string };

function containsOcrAmbiguousChar(raw: string): boolean {
  return /[O0I1]/.test(raw.toUpperCase());
}

/**
 * Maps every OCR-ambiguous character to one canonical form (O->0, I->1).
 * Two raw strings that canonicalize IDENTICALLY are not two independent
 * readings -- they are the SAME underlying token, decoded two different
 * ways by the client's own ambiguity-expansion logic (mirrors
 * identity_text_parser.dart's own `isOcrConfusionVariant`, which the
 * client already uses for exactly this "same token, different reading"
 * question when building `conflicts[]`). Used below so "8TR0" and "8TRO"
 * -- literally GPT-PM's own counter-example (P2.G3 pre-commit review,
 * 2026-09-11) -- collapse to one canonical form and stop counting as
 * corroboration of each other.
 */
function canonicalizeAmbiguousChars(raw: string): string {
  return raw.toUpperCase().replace(/O/g, "0").replace(/I/g, "1");
}

export function evaluateExactResolutionPolicy(input: ExactPolicyInput): ExactPolicyResult {
  // Condition 3: ownership/placard-compatibility conflicts already flagged
  // by the client parser fail the whole attempt outright -- there is no
  // partial credit for "the code matched but the placard was ambiguous".
  if (input.parserConflicts.length > 0) {
    return {
      outcome: "ABSTAIN",
      abstainReason: "EVIDENCE_CONFLICT",
      reason: `parser-reported conflict(s) present: ${input.parserConflicts.join("; ")}`,
    };
  }

  const uniqueResolutions = input.candidates.filter(
    (c): c is ResolvedCandidate & { lookup: { outcome: "UNIQUE"; modelId: string; keyKinds: string[] } } =>
      c.lookup.outcome === "UNIQUE",
  );
  const nonuniqueResolutions = input.candidates.filter((c) => c.lookup.outcome === "NONUNIQUE");

  // Condition 1/2: any candidate that is itself ambiguous against the
  // catalog (NONUNIQUE) fails the whole attempt -- an ambiguous candidate
  // can never contribute to a clean exact-model claim.
  if (nonuniqueResolutions.length > 0) {
    return {
      outcome: "ABSTAIN",
      abstainReason: "EVIDENCE_CONFLICT",
      reason: `candidate "${nonuniqueResolutions[0].rawCandidate}" matches more than one catalog model`,
    };
  }

  const distinctModelIds = [...new Set(uniqueResolutions.map((c) => c.lookup.modelId))];

  if (distinctModelIds.length === 0) {
    return { outcome: "NOT_ELIGIBLE", reason: "no candidate resolved to a unique catalog model" };
  }

  // Condition 2: two DIFFERENT candidates resolving to two DIFFERENT real
  // models is a genuine conflicting-model-code case.
  if (distinctModelIds.length > 1) {
    return {
      outcome: "ABSTAIN",
      abstainReason: "EVIDENCE_CONFLICT",
      reason: `candidates resolve to ${distinctModelIds.length} distinct catalog models: ${distinctModelIds.sort().join(", ")}`,
    };
  }

  const winningModelId = distinctModelIds[0];
  const winningModel = input.modelFieldsByModelId.get(winningModelId);
  if (!winningModel) {
    return {
      outcome: "NOT_ELIGIBLE",
      reason: `resolved modelId ${winningModelId} has no supplied catalog fields`,
    };
  }

  // Condition 4: O<->0 / I<->1 substitutions may create a candidate but
  // never exact certainty alone. Corroboration = at least one of the raw
  // strings that resolved to the winning model contains NO ambiguous
  // character, or at least two GENUINELY DISTINCT canonical readings agree
  // (GPT-PM MAJOR, P2.G3 pre-commit review, 2026-09-11: the previous
  // version counted "8TR0" and "8TRO" alone as two independent
  // corroborating readings, when they are the same underlying token read
  // two different ways -- raw distinct-string count was never a genuine
  // independence proxy; distinct CANONICAL-form count is, since the two
  // strings only look different at exactly the ambiguous positions).
  const winningRawStrings = uniqueResolutions
    .filter((c) => c.lookup.modelId === winningModelId)
    .map((c) => c.rawCandidate);
  const hasUnambiguousReading = winningRawStrings.some((raw) => !containsOcrAmbiguousChar(raw));
  const distinctCanonicalReadings = new Set(winningRawStrings.map(canonicalizeAmbiguousChars));
  const hasCorroboration = hasUnambiguousReading || distinctCanonicalReadings.size >= 2;
  if (!hasCorroboration) {
    return {
      outcome: "ABSTAIN",
      abstainReason: "LOW_CONFIDENCE",
      reason: `resolving candidate(s) "${winningRawStrings.join(", ")}" are all OCR-ambiguity variants of the same reading, with no unambiguous or genuinely independent second reading`,
    };
  }

  // Condition 5: type evidence reconciliation.
  if (input.typeEvidence) {
    const isHighAssurance =
      input.typeEvidence.status === "VERIFIED" || input.typeEvidence.status === "HIGH_ASSURANCE";
    const typeCompatible = winningModel.supportedTypeIds.includes(input.typeEvidence.typeId);
    if (isHighAssurance && !typeCompatible) {
      return {
        outcome: "NEED_MORE_VIEW",
        reason: `high-assurance generic type "${input.typeEvidence.typeId}" is not among the resolved model's supportedTypeIds`,
      };
    }
    // LOW_CONFIDENCE/AMBIGUOUS/OFFLINE_FALLBACK is soft evidence and never
    // vetoes, regardless of compatibility -- intentionally not checked.
  }

  // Condition 6: production requires VERIFIED; EXPERIMENTAL is shadow-only,
  // never a production-authorized exact claim (P2.G3 Story DoD).
  if (winningModel.textSupportStatus === "VERIFIED") {
    return {
      outcome: "EXACT_PRODUCTION",
      modelId: winningModel.modelId,
      catalogVersion: winningModel.catalogVersion,
    };
  }
  if (winningModel.textSupportStatus === "EXPERIMENTAL") {
    return {
      outcome: "EXACT_SHADOW_ONLY",
      modelId: winningModel.modelId,
      catalogVersion: winningModel.catalogVersion,
      reason: "EXPERIMENTAL_TEXT_SUPPORT",
    };
  }
  return {
    outcome: "NOT_ELIGIBLE",
    reason: `model ${winningModel.modelId} has textSupportStatus=NONE -- not eligible for any exact-text claim`,
  };
}
