/**
 * P2.G3 -- the orchestrator tying every other module in this gate together:
 * idempotency/staleness short-circuit -> quota -> contract validation ->
 * pinned-catalog lookup -> exact-resolution policy -> conditional
 * shadow/production gating -> pre-emission authoritative re-read -> session
 * pinning -> versioned response.
 *
 * Deliberately a plain async function, not wrapped in `onCall` here -- the
 * real callable (index.ts) is a thin wrapper that extracts `uid` from the
 * authenticated context and calls this. Keeping the orchestration itself
 * framework-agnostic is what lets it run directly against a real Firestore
 * emulator in tests without any callable/App-Check machinery involved.
 */
import { createHash } from "crypto";
import * as logger from "firebase-functions/logger";
import type { RecognitionAuthorityTuple } from "../p1/contracts";
import {
  type EquipmentIdentityRequest,
  type EquipmentIdentityResponse,
  type Decision,
  type AbstainReason,
  type FailureCode,
  type IdentityLevel,
  type ShadowCandidate,
  CURRENT_IDENTITY_CONTRACT_VERSION,
  TEXT_ONLY_EVIDENCE_LANE,
  isSupportedIdentityContractVersion,
} from "./contract";
import { resolveModelCodeLookup, type ModelCodeLookupResult } from "./text_key_index";
import {
  evaluateExactResolutionPolicy,
  type CatalogModelFields,
  type GenericTypeEvidence,
} from "./exact_resolution_policy";
import {
  fetchActiveCatalogPointer,
  fetchModelFields,
  checkModelStillEligibleForExact,
  verifyActiveCatalogVersionStillCurrent,
} from "./catalog_reader";
import {
  admitSessionClaim,
  finalizeSessionOutcome,
  readSession,
  readLatestSession,
  type PinnedMatchOutcome,
  type ResolvedSession,
  type SupersededClaim,
} from "./session_repository";
import { loadAppCheckPlatformReadiness, resolveAppCheckEnforcement } from "./app_check_readiness";

export const TEXT_POLICY_VERSION = "p2g3-text-exact-v1";
export const IDENTITY_POLICY_VERSION = "p2g3-text-exact-v1";
/** This gate never runs fusion (it is text-only) -- an honest non-empty
 * placeholder, not a real fusion policy epoch. */
export const FUSION_POLICY_VERSION_NONE = "none";
/** Authority reported when a request bails out before any catalog version
 * was ever consulted (e.g. quota exhaustion, unsupported contract). */
const NO_CATALOG_CONSULTED = "unresolved";

/** `String(e)` on an Error/HttpsError is message-only -- it never includes
 * a stack trace, which is exactly what is needed to actually locate a
 * failure afterward. Shared by every catch block below (silent-failure-hunter
 * finding, P2.G3 pre-commit review, 2026-09-11). */
function errorDetail(e: unknown): string {
  return e instanceof Error ? (e.stack ?? e.message) : String(e);
}

export interface OrchestratorInput {
  uid: string;
  request: EquipmentIdentityRequest;
}

interface ResponseOverrides {
  decision: Decision;
  identityLevel?: IdentityLevel;
  abstainReason?: AbstainReason;
  failureCode?: FailureCode;
  model?: { modelId: string; catalogVersion: string; textSupportStatus: "VERIFIED" };
  shadowCandidate?: ShadowCandidate;
}

function buildResponse(
  request: EquipmentIdentityRequest,
  recognitionSessionId: string,
  authority: RecognitionAuthorityTuple,
  overrides: ResponseOverrides,
): EquipmentIdentityResponse {
  return {
    scanId: request.scanId,
    recognitionSessionId,
    identityContractVersion: CURRENT_IDENTITY_CONTRACT_VERSION,
    authority,
    evidenceLane: TEXT_ONLY_EVIDENCE_LANE,
    // TEXT_ONLY never invokes a verifier -- always stated `false`, never
    // simply omitted (GPT-PM MAJOR, P2.G3 pre-commit review, 2026-09-11;
    // see contract.ts's own doc comment for why omission and `false` are
    // different claims).
    verifierInvoked: false,
    ...overrides,
  };
}

function baseAuthority(
  request: EquipmentIdentityRequest,
  catalogVersion: string,
): RecognitionAuthorityTuple {
  return {
    catalogVersion,
    ocrVersion: request.ocrVersion,
    // `identityParserVersion` is optional on both the request and the
    // authority tuple -- assigning it as a literal `undefined` key (rather
    // than omitting the key) makes Firestore's Admin SDK throw on write
    // ("Cannot use 'undefined' as a Firestore value") the moment a client
    // omits it, which is the common case, not an edge case. Conditional
    // spread keeps the key entirely absent when the request didn't send it.
    ...(request.identityParserVersion !== undefined
      ? { identityParserVersion: request.identityParserVersion }
      : {}),
    textPolicyVersion: TEXT_POLICY_VERSION,
    fusionPolicyVersion: FUSION_POLICY_VERSION_NONE,
    identityPolicyVersion: IDENTITY_POLICY_VERSION,
  };
}

/**
 * Deterministic per-(uid, scanId) session identity, replacing an
 * unconditional `randomUUID()` mint on every call (GPT-PM MAJOR, P2.G3
 * pre-commit review, 2026-09-11: no supersession/idempotency mechanism
 * existed at all -- every retry, including a client's own network-timeout
 * retry of the identical scan, minted a brand-new orphan session and paid
 * quota a second time). A stable id lets a genuine retry land on the SAME
 * Firestore document, which is what makes both the idempotent-replay
 * short-circuit and the race-closing check at the pin step possible below.
 */
function deriveRecognitionSessionId(uid: string, scanId: string): string {
  return createHash("sha256").update(JSON.stringify([uid, scanId])).digest("hex");
}

/**
 * sha256 over every request field that can change the OUTCOME -- never
 * `uid` (already the document's own partition) and never `scanId` (that
 * is the session id itself, see above). Two calls under the same
 * (uid, scanId) with the SAME fingerprint are the SAME logical request
 * (a client retry, e.g. after a network timeout); a DIFFERENT fingerprint
 * under the same scanId is a genuinely conflicting attempt, handled as
 * CANCELLED_STALE below rather than silently overwriting what is already
 * pinned for that scanId.
 */
function computeRequestFingerprint(request: EquipmentIdentityRequest): string {
  return createHash("sha256")
    .update(
      JSON.stringify({
        identityContractVersion: request.identityContractVersion,
        clientCapabilities: request.clientCapabilities,
        evidence: request.evidence,
        ocrVersion: request.ocrVersion,
        identityParserVersion: request.identityParserVersion ?? null,
      }),
    )
    .digest("hex");
}

/**
 * Maps a resolved model to its FINAL response shape. VERIFIED is a real,
 * authoritative exact claim; EXPERIMENTAL is deliberately NOT (GPT-PM
 * MAJOR, P2.G3 pre-commit review round 2, 2026-09-11, correcting round 1's
 * own remediation attempt -- adding a side-channel `matchAuthority` marker
 * to an otherwise-unchanged `decision: MATCH, identityLevel: EXACT_MODEL`
 * response did not change that the response still asserted an exact claim
 * v4.4 only binds to `textSupportStatus == VERIFIED`; see
 * `contract.ts`'s `ShadowCandidateSchema` for the corrected shape). The
 * SAME function serves both a fresh pipeline result and an idempotent
 * replay, so the two paths can never drift apart in how they represent an
 * outcome.
 */
function outcomeResponseOverrides(outcome: PinnedMatchOutcome): ResponseOverrides {
  if (outcome.textSupportStatus === "VERIFIED") {
    return {
      decision: "MATCH",
      identityLevel: "EXACT_MODEL",
      model: { modelId: outcome.modelId, catalogVersion: outcome.catalogVersion, textSupportStatus: "VERIFIED" },
    };
  }
  return {
    decision: "NOT_SUPPORTED",
    shadowCandidate: {
      modelId: outcome.modelId,
      catalogVersion: outcome.catalogVersion,
      textSupportStatus: "EXPERIMENTAL",
    },
  };
}

/**
 * v4.4 §6.6's authoritative-pre-emission-read bound applies to EVERY
 * emission of a resolved outcome, not just the first one (GPT-PM MAJOR,
 * P2.G3 pre-commit review round 2, 2026-09-11: round 1's idempotent-replay
 * short-circuit returned a cached outcome without ever re-checking whether
 * the model had since been revoked or the active pointer had since moved
 * -- exactly the live-read guarantee this check exists to provide). Shared
 * by the main pipeline's pre-emission step and the idempotent-replay path
 * so neither can drift out of sync with the other.
 */
async function checkOutcomeStillEligible(outcome: PinnedMatchOutcome): Promise<boolean> {
  const [modelEligibility, pointerStillCurrent] = await Promise.all([
    checkModelStillEligibleForExact(outcome.catalogVersion, outcome.modelId, outcome.textSupportStatus),
    verifyActiveCatalogVersionStillCurrent(outcome.catalogVersion),
  ]);
  return modelEligibility.eligible && pointerStillCurrent;
}

/** How long a genuinely concurrent duplicate (identical fingerprint,
 * already ADMITTED elsewhere) waits for that winner to finish, before
 * giving up and reporting UNAVAILABLE_TIMEOUT rather than hanging
 * indefinitely -- bounded well under `CLAIM_LEASE_MS`
 * (session_repository.ts), so a genuinely crashed winner's lease still has
 * room to expire and be reclaimed by a LATER attempt even after this one
 * times out. */
const WAIT_POLL_INTERVAL_MS = 100;
const WAIT_POLL_TIMEOUT_MS = 3000;

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Polls `readSession` until the claim this caller is waiting on leaves
 * PENDING (resolved or superseded) or the bounded wait window elapses.
 * Never calls `admitSessionClaim` itself -- reclaiming an expired lease is
 * left to whichever request (this one's own eventual retry, or a wholly
 * different one) next actually attempts admission, keeping this a pure,
 * side-effect-free wait.
 */
async function pollUntilResolved(
  uid: string,
  sessionId: string,
): Promise<ResolvedSession | SupersededClaim | "TIMED_OUT"> {
  const deadline = Date.now() + WAIT_POLL_TIMEOUT_MS;
  while (Date.now() < deadline) {
    await sleep(WAIT_POLL_INTERVAL_MS);
    const record = await readSession(uid, sessionId);
    if (record && record.status !== "PENDING") return record;
  }
  return "TIMED_OUT";
}

/**
 * Shared by both replay paths (a direct REPLAY from `admitSessionClaim`,
 * and a WAIT that later observed a RESOLVED record via `pollUntilResolved`)
 * so the two can never drift apart in what they require before ever
 * handing back a cached outcome: (a) this must still be the LATEST scan for
 * this uid -- a newer scan already superseding it makes a replay stale even
 * though the retry's own fingerprint matched; (b) the pinned outcome must
 * still be live-eligible RIGHT NOW, not merely at the time it was first
 * resolved (GPT-PM MAJOR, P2.G3 pre-commit review round 2, 2026-09-11).
 */
async function replayResolvedSession(
  uid: string,
  request: EquipmentIdentityRequest,
  recognitionSessionId: string,
  record: ResolvedSession,
  preCatalogAuthority: RecognitionAuthorityTuple,
): Promise<EquipmentIdentityResponse> {
  let latest;
  try {
    latest = await readLatestSession(uid);
  } catch (e) {
    logger.error("equipment_identity_latest_session_read_failed", {
      uid,
      scanId: request.scanId,
      recognitionSessionId,
      err: errorDetail(e),
    });
    return buildResponse(request, recognitionSessionId, preCatalogAuthority, {
      decision: "UNAVAILABLE_BACKEND",
      failureCode: "BACKEND_ERROR",
    });
  }
  if (latest && latest.recognitionSessionId !== recognitionSessionId) {
    return buildResponse(request, recognitionSessionId, preCatalogAuthority, { decision: "CANCELLED_STALE" });
  }
  let stillEligible: boolean;
  try {
    stillEligible = await checkOutcomeStillEligible(record.matchOutcome);
  } catch (e) {
    logger.error("equipment_identity_replay_eligibility_check_failed", {
      uid,
      scanId: request.scanId,
      recognitionSessionId,
      err: errorDetail(e),
    });
    return buildResponse(request, recognitionSessionId, preCatalogAuthority, {
      decision: "UNAVAILABLE_BACKEND",
      failureCode: "BACKEND_ERROR",
    });
  }
  if (!stillEligible) {
    return buildResponse(request, recognitionSessionId, record.authority, {
      decision: "UNAVAILABLE_CATALOG_VERSION",
      failureCode: "CATALOG_VERSION_UNAVAILABLE",
    });
  }
  return buildResponse(
    request,
    recognitionSessionId,
    record.authority,
    outcomeResponseOverrides(record.matchOutcome),
  );
}

/**
 * OCR-derived type-hint phrases are non-binding suggestions only -- the
 * same principle P1.G1's own `StagedEquipmentModelCandidate.typeHints` doc
 * comment states for the adapter layer ("Adapters NEVER assign
 * authoritative primaryTypeId") applies here by direct analogy: neither
 * this parser layer nor P2.G3 has any typeId-vocabulary alignment between
 * a mobile lexicon phrase (identity_text_parser.dart's `typeHintPhrases`)
 * and a catalog model's canonical `primaryTypeId`/`supportedTypeIds`, so
 * treating an OCR phrase as HIGH_ASSURANCE/VERIFIED would fabricate a
 * confidence level text evidence alone cannot support. This function
 * therefore NEVER returns those two statuses -- a single, unambiguous hint
 * is LOW_CONFIDENCE; more than one distinct hint (the parser itself found
 * more than one candidate phrase) is AMBIGUOUS. Both are non-vetoing per
 * the policy's own condition 5 (exact_resolution_policy.ts).
 *
 * NOT RESOLVED, STATED EXPLICITLY (GPT-PM MAJOR, P2.G3 pre-commit review
 * round 2, 2026-09-11 -- correcting round 1's own claim that threading
 * this in closed the finding): the ORIGINAL finding wanted a real
 * HIGH_ASSURANCE/VERIFIED veto reachable through THIS gate's own runtime
 * path when an authoritative generic-type recognizer disagrees with the
 * resolved model. No such authoritative recognizer exists anywhere in this
 * repository today -- building one is P4 fusion's own scope, not
 * buildable here without fabricating a confidence level. This function's
 * soft-only wiring is therefore real production wiring for the ONLY input
 * this gate actually has (OCR text hints), but it does NOT satisfy the
 * original finding, which stays OPEN, tracked as P4 fusion's obligation,
 * not silently marked complete by this gate.
 */
function deriveTypeEvidence(typeHints: string[]): GenericTypeEvidence | undefined {
  const distinct = [...new Set(typeHints.map((h) => h.trim().toUpperCase()).filter((h) => h.length > 0))];
  if (distinct.length === 0) return undefined;
  return {
    status: distinct.length > 1 ? "AMBIGUOUS" : "LOW_CONFIDENCE",
    typeId: distinct[0],
  };
}

export async function resolveEquipmentIdentityFromText(
  input: OrchestratorInput,
): Promise<EquipmentIdentityResponse> {
  const { uid, request } = input;
  const recognitionSessionId = deriveRecognitionSessionId(uid, request.scanId);
  const requestFingerprint = computeRequestFingerprint(request);
  const preCatalogAuthority = baseAuthority(request, NO_CATALOG_CONSULTED);

  // 1. Request-side contract negotiation FIRST (v4.4 §6.5, closes
  // N-MAJOR-1) -- pure validation, no Firestore I/O, so a request this
  // server will refuse regardless never even attempts admission/quota.
  if (!isSupportedIdentityContractVersion(request.identityContractVersion)) {
    return buildResponse(request, recognitionSessionId, preCatalogAuthority, {
      decision: "UNSUPPORTED_CLIENT_CONTRACT",
    });
  }

  // 2. Admission -- linearizes session ownership for (uid, scanId), this
  // uid's latest-scan ordering, AND the identity-lookup quota charge in ONE
  // Firestore transaction, BEFORE the expensive pipeline runs (GPT-PM
  // MAJOR, P2.G3 pre-commit review round 3, 2026-09-11, correcting round
  // 2's own remediation -- see session_repository.ts's own header comment
  // for the exact race this closes: round 2 only advanced the
  // latest-session pointer at the FINAL pin, after the whole pipeline had
  // already run, so a slow request for an OLDER scan could still win the
  // "latest" race against a newer, faster one purely on timing). See
  // `admitSessionClaim`'s own doc comment for the full semantics of each
  // outcome below.
  let admission;
  try {
    admission = await admitSessionClaim(uid, recognitionSessionId, request.scanId, requestFingerprint);
  } catch (e) {
    logger.error("equipment_identity_admission_failed", {
      uid,
      scanId: request.scanId,
      recognitionSessionId,
      err: errorDetail(e),
    });
    return buildResponse(request, recognitionSessionId, preCatalogAuthority, {
      decision: "UNAVAILABLE_BACKEND",
      failureCode: "BACKEND_ERROR",
    });
  }

  if (admission.outcome === "RATE_LIMITED") {
    return buildResponse(request, recognitionSessionId, preCatalogAuthority, {
      decision: "UNAVAILABLE_RATE_LIMIT",
      failureCode: "RATE_LIMITED",
    });
  }
  if (admission.outcome === "STALE") {
    // Either a genuinely conflicting attempt (same scanId, different
    // evidence, an already-RESOLVED or live-PENDING doc under a different
    // fingerprint) or a retry against an already-SUPERSEDED claim -- both
    // are honestly CANCELLED_STALE, no pipeline run, no quota charged.
    return buildResponse(request, recognitionSessionId, preCatalogAuthority, { decision: "CANCELLED_STALE" });
  }
  if (admission.outcome === "REPLAY") {
    return replayResolvedSession(uid, request, recognitionSessionId, admission.record, preCatalogAuthority);
  }
  if (admission.outcome === "WAIT") {
    // A genuinely concurrent duplicate of this EXACT request (identical
    // fingerprint) is already admitted and running elsewhere -- wait for
    // that winner to finish rather than charge quota and run the pipeline
    // a second time for what is, by fingerprint, the SAME logical request
    // (GPT-PM MAJOR, P2.G3 pre-commit review round 3, 2026-09-11: "identical
    // concurrent duplicate не increment-ит quota второй раз").
    let resolution;
    try {
      resolution = await pollUntilResolved(uid, recognitionSessionId);
    } catch (e) {
      logger.error("equipment_identity_wait_poll_failed", {
        uid,
        scanId: request.scanId,
        recognitionSessionId,
        err: errorDetail(e),
      });
      return buildResponse(request, recognitionSessionId, preCatalogAuthority, {
        decision: "UNAVAILABLE_BACKEND",
        failureCode: "BACKEND_ERROR",
      });
    }
    if (resolution === "TIMED_OUT") {
      return buildResponse(request, recognitionSessionId, preCatalogAuthority, {
        decision: "UNAVAILABLE_TIMEOUT",
        failureCode: "TIMEOUT",
      });
    }
    if (resolution.status === "SUPERSEDED") {
      return buildResponse(request, recognitionSessionId, preCatalogAuthority, { decision: "CANCELLED_STALE" });
    }
    return replayResolvedSession(uid, request, recognitionSessionId, resolution, preCatalogAuthority);
  }
  // admission.outcome === "ADMITTED" -- this caller now owns the claim and
  // has already been charged quota atomically as part of admission. Proceed
  // with the full pipeline below. `claimId` is this specific admission's own
  // generation token -- threaded through to `finalizeSessionOutcome` below
  // so a stale/reclaimed caller can never finalize a claim it no longer owns
  // (GPT-PM MAJOR, P2.G3 pre-commit review round 4, 2026-09-11).
  const claimId = admission.claimId;

  // 3. catalogVersion ONLY from the server-pinned active pointer -- never
  // accepted from the client (GPT-PM round-1 MAJOR). Wrapped (GPT-PM
  // MAJOR, P2.G3 pre-commit review, 2026-09-11: every Firestore call after
  // quota was previously unwrapped, so a transient Firestore error here
  // threw out of this function entirely instead of resolving to a
  // schema-valid terminal response).
  let pointer;
  try {
    pointer = await fetchActiveCatalogPointer();
  } catch (e) {
    logger.error("equipment_identity_catalog_pointer_read_failed", {
      uid,
      scanId: request.scanId,
      err: errorDetail(e),
    });
    return buildResponse(request, recognitionSessionId, preCatalogAuthority, {
      decision: "UNAVAILABLE_BACKEND",
      failureCode: "BACKEND_ERROR",
    });
  }
  if (!pointer) {
    return buildResponse(request, recognitionSessionId, preCatalogAuthority, {
      decision: "UNAVAILABLE_CATALOG_VERSION",
      failureCode: "CATALOG_VERSION_UNAVAILABLE",
    });
  }
  const catalogVersion = pointer.activeCatalogVersion;
  const authority = baseAuthority(request, catalogVersion);

  // 4. Resolve every distinct candidate against the pinned catalog
  // version. Wrapped for the same reason as step 3.
  const distinctRawCandidates = [...new Set(request.evidence.modelCodeCandidates)];
  const candidates: { rawCandidate: string; lookup: ModelCodeLookupResult }[] = [];
  try {
    for (const rawCandidate of distinctRawCandidates) {
      candidates.push({ rawCandidate, lookup: await resolveModelCodeLookup(rawCandidate, catalogVersion) });
    }
  } catch (e) {
    logger.error("equipment_identity_candidate_lookup_failed", {
      uid,
      scanId: request.scanId,
      catalogVersion,
      err: errorDetail(e),
    });
    return buildResponse(request, recognitionSessionId, authority, {
      decision: "UNAVAILABLE_BACKEND",
      failureCode: "BACKEND_ERROR",
    });
  }

  // 5. Pre-fetch catalog fields for every UNIQUE-resolved modelId.
  // Wrapped for the same reason as step 3.
  const uniqueModelIds = [
    ...new Set(
      candidates
        .map((c) => c.lookup)
        .filter((l): l is Extract<ModelCodeLookupResult, { outcome: "UNIQUE" }> => l.outcome === "UNIQUE")
        .map((l) => l.modelId),
    ),
  ];
  const modelFieldsByModelId = new Map<string, CatalogModelFields>();
  try {
    for (const modelId of uniqueModelIds) {
      const fields = await fetchModelFields(catalogVersion, modelId);
      if (fields) {
        modelFieldsByModelId.set(modelId, fields);
      } else {
        // The text-key index just reported this modelId as a UNIQUE match
        // -- a missing/invalid catalog-fields entry for it can only mean a
        // dangling index row or catalog corruption, never a legitimate
        // business outcome (that's NOT_ELIGIBLE further down, for a
        // textSupportStatus=NONE model that DOES have fields). Without
        // this log, both cases produced the identical NOT_SUPPORTED
        // response with nothing anywhere distinguishing "real
        // data-integrity bug" from "this model just isn't text-eligible
        // yet" (silent-failure-hunter finding, P2.G3 pre-commit review,
        // 2026-09-11).
        logger.error("equipment_identity_dangling_text_key_index_entry", {
          catalogVersion,
          modelId,
          scanId: request.scanId,
        });
      }
    }
  } catch (e) {
    logger.error("equipment_identity_model_fields_fetch_failed", {
      uid,
      scanId: request.scanId,
      catalogVersion,
      err: errorDetail(e),
    });
    return buildResponse(request, recognitionSessionId, authority, {
      decision: "UNAVAILABLE_BACKEND",
      failureCode: "BACKEND_ERROR",
    });
  }

  // 6. The full v4.1 §6.2 exact-resolution policy. `typeEvidence` is
  // threaded from the request -- see `deriveTypeEvidence`'s own doc
  // comment for what this does and does not resolve.
  const policyResult = evaluateExactResolutionPolicy({
    candidates,
    parserConflicts: request.evidence.conflicts,
    modelFieldsByModelId,
    typeEvidence: deriveTypeEvidence(request.evidence.typeHints),
  });

  // 7. Shadow-vs-production lane, derived from the SAME platform-owned
  // readiness signal T3 gates App Check enforcement with -- while P0.G0 is
  // not READY_FOR_PRODUCTION, this whole deployment runs in SHADOW: both a
  // VERIFIED and an EXPERIMENTAL exact match may resolve to an outcome
  // (evidence gathering) -- see `outcomeResponseOverrides` for how the two
  // are represented differently in the response. Once READY_FOR_PRODUCTION,
  // PRODUCTION lane applies and an EXPERIMENTAL-backed match is
  // NOT_SUPPORTED outright, before even reaching the pin step (not yet
  // eligible for a production claim) -- never independently asserted true
  // (Story AC).
  let matched: PinnedMatchOutcome | null = null;

  // A `switch` with a `never`-typed default, not an if/else-if chain ending
  // in a bare `else` -- a bare `else` silently swallows any FUTURE
  // ExactPolicyResult variant into NOT_SUPPORTED with no compiler warning
  // (type-design-analyzer + code-reviewer finding, P2.G3 pre-commit review,
  // 2026-09-11). This makes adding a 6th outcome variant to
  // exact_resolution_policy.ts a compile error here until this switch is
  // updated to handle it, rather than a silent misclassification discovered
  // only by reading the code.
  switch (policyResult.outcome) {
    case "EXACT_PRODUCTION":
      matched = {
        modelId: policyResult.modelId,
        catalogVersion: policyResult.catalogVersion,
        textSupportStatus: "VERIFIED",
      };
      break;
    case "EXACT_SHADOW_ONLY": {
      const readiness = loadAppCheckPlatformReadiness().status;
      const productionReady = resolveAppCheckEnforcement(readiness, "PRODUCTION");
      if (!productionReady) {
        matched = {
          modelId: policyResult.modelId,
          catalogVersion: policyResult.catalogVersion,
          textSupportStatus: "EXPERIMENTAL",
        };
      } else {
        return buildResponse(request, recognitionSessionId, authority, { decision: "NOT_SUPPORTED" });
      }
      break;
    }
    case "NEED_MORE_VIEW":
      return buildResponse(request, recognitionSessionId, authority, { decision: "NEED_MORE_VIEW" });
    case "ABSTAIN":
      return buildResponse(request, recognitionSessionId, authority, {
        decision: "ABSTAIN",
        abstainReason: policyResult.abstainReason,
      });
    case "NOT_ELIGIBLE":
      return buildResponse(request, recognitionSessionId, authority, { decision: "NOT_SUPPORTED" });
    default: {
      const exhaustiveCheck: never = policyResult;
      throw new Error(`unhandled ExactPolicyResult outcome: ${JSON.stringify(exhaustiveCheck)}`);
    }
  }

  // 8. Authoritative pre-emission re-read (v4.4 §6.6, revocation option
  // (a)) -- re-verifies BOTH the model's own eligibility and the active
  // catalog pointer itself, not just the model doc at the already-pinned
  // catalogVersion (the pointer can move to a different catalogVersion
  // between this request's earlier pointer read (step 3) and this final
  // check). Shared with the idempotent-replay path via
  // `checkOutcomeStillEligible`. Wrapped for the same reason as step 3.
  let eligible: boolean;
  try {
    eligible = await checkOutcomeStillEligible(matched);
  } catch (e) {
    logger.error("equipment_identity_pre_emission_check_failed", {
      uid,
      scanId: request.scanId,
      catalogVersion: matched.catalogVersion,
      modelId: matched.modelId,
      err: errorDetail(e),
    });
    return buildResponse(request, recognitionSessionId, authority, {
      decision: "UNAVAILABLE_BACKEND",
      failureCode: "BACKEND_ERROR",
    });
  }
  if (!eligible) {
    return buildResponse(request, recognitionSessionId, authority, {
      decision: "UNAVAILABLE_CATALOG_VERSION",
      failureCode: "CATALOG_VERSION_UNAVAILABLE",
    });
  }

  // 9. Finalize -- see session_repository.ts's own doc comment for the full
  // semantics. Re-verifies "am I still this uid's latest scan" one more
  // time, inside the SAME transaction that would write the resolved
  // outcome: a genuinely newer scan admitted while THIS pipeline was still
  // running means this claim lost, and finalize aborts (SUPERSEDED) rather
  // than ever emitting a stale result.
  //
  // The final response is built from `finalizeSessionOutcome`'s own
  // RETURNED record, never from this function's local `matched` (GPT-PM
  // MAJOR, P2.G3 pre-commit review round 2, 2026-09-11, preserved through
  // round 3's admission/finalize redesign: `authority` alone does not
  // encode `modelId`, so whichever call's finalize actually WON is the
  // only one whose outcome is real, and every caller -- winner or
  // superseded loser -- must respond with THAT one, not its own
  // locally-computed guess).
  let finalizeResult;
  try {
    finalizeResult = await finalizeSessionOutcome(uid, recognitionSessionId, authority, {
      requestFingerprint,
      claimId,
      matchOutcome: matched,
    });
  } catch (e) {
    logger.error("equipment_identity_session_finalize_failed", {
      uid,
      scanId: request.scanId,
      recognitionSessionId,
      err: errorDetail(e),
    });
    return buildResponse(request, recognitionSessionId, authority, {
      decision: "UNAVAILABLE_BACKEND",
      failureCode: "BACKEND_ERROR",
    });
  }
  if (finalizeResult.outcome !== "RESOLVED") {
    // SUPERSEDED (a genuinely newer scan was admitted while this pipeline
    // ran) or ABANDONED (defensive-only -- see finalizeSessionOutcome's own
    // doc comment) are both honestly CANCELLED_STALE from this caller's own
    // point of view: whatever it just computed is no longer the thing to
    // report.
    return buildResponse(request, recognitionSessionId, authority, { decision: "CANCELLED_STALE" });
  }

  return buildResponse(
    request,
    recognitionSessionId,
    authority,
    outcomeResponseOverrides(finalizeResult.record.matchOutcome),
  );
}
