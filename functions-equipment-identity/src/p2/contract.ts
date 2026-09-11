/**
 * P2.G3 -- the FULL v4.4 request/response contract
 * (MASTER_TECHNICAL_PLAN_v4.4_MECHANICAL_PATCH_2026-08-22.md, "6.5
 * Recognition response contract", lines ~200-270), not a bare exact-lookup
 * shape (GPT-PM round-1 MAJOR, P2.G3 plan review, 2026-09-10 -- the plan
 * originally omitted `identityContractVersion`/`clientCapabilities`/
 * `recognitionSessionId`/`evidenceLane`/the full `decision` enum entirely).
 *
 * This gate is TEXT-ONLY (`evidenceLane` is always `"TEXT_ONLY"` here --
 * there is no visual signal in this request shape at all, so it is not
 * even a request field, just a response constant), so `verifierModel`,
 * `calibratedConfidence` and `nextView` -- fields the full v4.4 contract
 * defines only for the VISUAL/fusion path -- are intentionally absent from
 * this gate's response; they belong to P4/P6, not P2.G3.
 *
 * `verifierInvoked` is NOT in that list (GPT-PM MAJOR, P2.G3 pre-commit
 * review, 2026-09-11, correcting this file's own earlier framing): v4.4
 * defines TEXT_ONLY partly BY `verifierInvoked == false`, so a response
 * that simply omits the field is not the same claim as one that states it
 * false -- an omitted field is silent about verification, a `false` field
 * asserts none happened. Required (not optional) below, so a response
 * missing it fails schema validation outright rather than parsing as if
 * the question were simply never asked.
 */
import { z } from "zod";
import { RecognitionAuthorityTupleSchema } from "../p1/contracts";

// --- request ---------------------------------------------------------

/**
 * Versions this server currently accepts. A real "N-1" mobile client does
 * not exist yet (this is the FIRST implementation of this contract), but
 * the mechanism is a SET, not a single hardcoded string, precisely so it
 * generalizes the moment a second version ships -- the N/N-1 compatibility
 * TEST proves the mechanism (any version in the set succeeds, any version
 * outside it is rejected), not that two real client versions exist today.
 */
export const CURRENT_IDENTITY_CONTRACT_VERSION = "v1";
export const SUPPORTED_IDENTITY_CONTRACT_VERSIONS: ReadonlySet<string> = new Set([
  CURRENT_IDENTITY_CONTRACT_VERSION,
]);

export function isSupportedIdentityContractVersion(version: string): boolean {
  return SUPPORTED_IDENTITY_CONTRACT_VERSIONS.has(version);
}

/**
 * Server-side DTO mirror of P2.G2's `ParsedIdentityText`
 * (mobile/lib/features/visual_equipment/data/parsed_identity_text.dart) --
 * the client sends its already-parsed text evidence, never the raw image
 * or the raw full OCR text (privacy/cost optimization, v4.1 §6.2's own
 * closing note; also T4's "no image/full raw OCR text enters request,
 * storage or logs").
 */
/**
 * Bounds on every request-evidence array/string (GPT-PM MAJOR, P2.G3
 * pre-commit review, 2026-09-11): none existed before this, so an
 * authenticated caller could send an arbitrarily large
 * `modelCodeCandidates` array and drive one `resolveModelCodeLookup` +
 * one `fetchModelFields` Firestore call PER DISTINCT ENTRY
 * (orchestrator.ts's steps 4/5) from a single quota-charged request --
 * cost amplification, not merely an oversized payload. Real client output
 * (identity_text_parser.dart) never produces more than a handful of
 * candidates per field or a token longer than a placard's own text, so
 * these bounds are generous relative to any real request, not tuned to a
 * measured maximum.
 */
const MAX_EVIDENCE_ARRAY_LENGTH = 20;
const MAX_EVIDENCE_STRING_LENGTH = 128;
const evidenceStringArray = () =>
  z.array(z.string().max(MAX_EVIDENCE_STRING_LENGTH)).max(MAX_EVIDENCE_ARRAY_LENGTH);

export const IdentityTextEvidenceSchema = z
  .object({
    brandCandidates: evidenceStringArray(),
    productLineCandidates: evidenceStringArray(),
    modelCodeCandidates: evidenceStringArray(),
    typeHints: evidenceStringArray(),
    conflicts: evidenceStringArray(),
  })
  .strict();
export type IdentityTextEvidence = z.infer<typeof IdentityTextEvidenceSchema>;

export const EquipmentIdentityRequestSchema = z
  .object({
    scanId: z.string().min(1).max(MAX_EVIDENCE_STRING_LENGTH),
    identityContractVersion: z.string().min(1).max(MAX_EVIDENCE_STRING_LENGTH),
    clientCapabilities: evidenceStringArray(),
    evidence: IdentityTextEvidenceSchema,
    /** Which on-device OCR build produced `evidence` -- a CLIENT property,
     * the server cannot derive this itself, unlike the policy-version
     * fields below which are the server's own. */
    ocrVersion: z.string().min(1).max(MAX_EVIDENCE_STRING_LENGTH),
    /** Optional per RecognitionAuthorityTupleSchema's own optionality. */
    identityParserVersion: z.string().min(1).max(MAX_EVIDENCE_STRING_LENGTH).optional(),
  })
  .strict();
export type EquipmentIdentityRequest = z.infer<typeof EquipmentIdentityRequestSchema>;

// --- response ----------------------------------------------------------

export const DecisionSchema = z.enum([
  "MATCH",
  "ABSTAIN",
  "NEED_MORE_VIEW",
  "NOT_SUPPORTED",
  "CANCELLED_STALE",
  "UNSUPPORTED_CLIENT_CONTRACT",
  "UNAVAILABLE_TIMEOUT",
  "UNAVAILABLE_NETWORK",
  "UNAVAILABLE_APPCHECK",
  "UNAVAILABLE_RATE_LIMIT",
  "UNAVAILABLE_BACKEND",
  "UNAVAILABLE_CATALOG_VERSION",
]);
export type Decision = z.infer<typeof DecisionSchema>;

export const AbstainReasonSchema = z.enum([
  "LOW_CONFIDENCE",
  "OUT_OF_DISTRIBUTION",
  "EVIDENCE_CONFLICT",
  "INSUFFICIENT_EVIDENCE",
]);
export type AbstainReason = z.infer<typeof AbstainReasonSchema>;

export const FailureCodeSchema = z.enum([
  "TIMEOUT",
  "NETWORK",
  "APPCHECK",
  "RATE_LIMITED",
  "BACKEND_ERROR",
  "EMBEDDING_FAILURE",
  "INDEX_UNAVAILABLE",
  "VERIFIER_SCHEMA_VIOLATION",
  "CATALOG_VERSION_UNAVAILABLE",
]);
export type FailureCode = z.infer<typeof FailureCodeSchema>;

export const IdentityLevelSchema = z.enum([
  "TYPE_ONLY",
  "BRAND_AND_TYPE",
  "PRODUCT_LINE",
  "EXACT_MODEL",
]);
export type IdentityLevel = z.infer<typeof IdentityLevelSchema>;

/** This gate is always `TEXT_ONLY` -- not a request field, purely
 * server-derived (v4.4 §6.4.1's `evidenceLane` rule). */
export const EvidenceLaneSchema = z.enum(["TEXT_ONLY", "VISUAL"]);
export const TEXT_ONLY_EVIDENCE_LANE = "TEXT_ONLY" as const;

const UNAVAILABLE_DECISIONS = new Set<Decision>([
  "UNAVAILABLE_TIMEOUT",
  "UNAVAILABLE_NETWORK",
  "UNAVAILABLE_APPCHECK",
  "UNAVAILABLE_RATE_LIMIT",
  "UNAVAILABLE_BACKEND",
  "UNAVAILABLE_CATALOG_VERSION",
]);

/**
 * A non-authoritative EXPERIMENTAL-text-support candidate, gathered for
 * shadow evidence while App Check enforcement (and this gate's own
 * production posture) is not yet on. Deliberately NOT part of a MATCH
 * claim (GPT-PM MAJOR, P2.G3 pre-commit review round 2, 2026-09-11,
 * correcting round 1's own remediation attempt: v4.4 binds a TEXT_ONLY
 * `decision: MATCH, identityLevel: EXACT_MODEL` claim to
 * `textSupportStatus == VERIFIED`; adding a side-channel `matchAuthority`
 * marker to an otherwise-unchanged MATCH response does not change that the
 * response still asserts an exact claim it has no basis for -- a consumer
 * reading only `decision`/`identityLevel`/`evidenceLane`, the fields the
 * binding contract actually defines the claim through, still sees MATCH).
 * `textSupportStatus` is a literal `"EXPERIMENTAL"` -- a VERIFIED result
 * always goes through `model` as a real MATCH instead, never through here.
 */
export const ShadowCandidateSchema = z.object({
  modelId: z.string().min(1),
  catalogVersion: z.string().min(1),
  textSupportStatus: z.literal("EXPERIMENTAL"),
});
export type ShadowCandidate = z.infer<typeof ShadowCandidateSchema>;

export const EquipmentIdentityResponseSchema = z
  .object({
    scanId: z.string().min(1),
    recognitionSessionId: z.string().min(1),
    identityContractVersion: z.string().min(1),
    authority: RecognitionAuthorityTupleSchema,
    evidenceLane: EvidenceLaneSchema,
    decision: DecisionSchema,
    identityLevel: IdentityLevelSchema.optional(),
    abstainReason: AbstainReasonSchema.optional(),
    failureCode: FailureCodeSchema.optional(),
    /** Only ever VERIFIED -- see `ShadowCandidateSchema`'s own doc comment
     * for where an EXPERIMENTAL result goes instead. */
    model: z
      .object({
        modelId: z.string().min(1),
        catalogVersion: z.string().min(1),
        textSupportStatus: z.literal("VERIFIED"),
      })
      .optional(),
    shadowCandidate: ShadowCandidateSchema.optional(),
    /** TEXT_ONLY (this gate, always) implies no verifier ever ran -- see
     * this file's own header comment. Required, not optional: a response
     * missing it fails validation outright. */
    verifierInvoked: z.boolean(),
  })
  .strict()
  .superRefine((resp, ctx) => {
    if (resp.evidenceLane === "TEXT_ONLY" && resp.verifierInvoked !== false) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "TEXT_ONLY evidenceLane requires verifierInvoked === false",
        path: ["verifierInvoked"],
      });
    }
    if (resp.decision === "MATCH") {
      if (resp.model === undefined) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: "decision MATCH requires model",
          path: ["model"],
        });
      }
    } else if (resp.model !== undefined) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "model is present but decision is not MATCH",
        path: ["model"],
      });
    }
    // A real exact claim (model) and a non-authoritative shadow candidate
    // are mutually exclusive by construction -- never both on one response.
    if (resp.model !== undefined && resp.shadowCandidate !== undefined) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "model and shadowCandidate are mutually exclusive",
        path: ["shadowCandidate"],
      });
    }
    // Binding rule (v4.4 §6.5): abstainReason and failureCode are
    // mutually exclusive by construction.
    if (resp.abstainReason !== undefined && resp.failureCode !== undefined) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "abstainReason and failureCode are mutually exclusive",
        path: ["abstainReason"],
      });
    }
    if (resp.abstainReason !== undefined && resp.decision !== "ABSTAIN") {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "abstainReason is present but decision is not ABSTAIN",
        path: ["abstainReason"],
      });
    }
    const isUnavailable = UNAVAILABLE_DECISIONS.has(resp.decision);
    if (isUnavailable && resp.failureCode === undefined) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: `decision ${resp.decision} requires a failureCode`,
        path: ["failureCode"],
      });
    }
    if (!isUnavailable && resp.failureCode !== undefined) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "failureCode is present but decision is not an UNAVAILABLE_* value",
        path: ["failureCode"],
      });
    }
  });
export type EquipmentIdentityResponse = z.infer<typeof EquipmentIdentityResponseSchema>;
