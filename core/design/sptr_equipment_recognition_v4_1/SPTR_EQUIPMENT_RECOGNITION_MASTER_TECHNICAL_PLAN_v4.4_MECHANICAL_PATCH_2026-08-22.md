SPTR / Fitness-App

# Equipment Recognition Master Technical Plan v4.4 — Mechanical Patch Candidate (round 3)

Single design authority: v4.3 MECHANICAL PATCH + GPT-PM round-3 binary-verification verdict (2026-08-22, PM Bridge, conversation `https://chatgpt.com/c/6a821d86-5720-83eb-b20b-a33f5b3cb5dc`) that this revision closes

| Field | Value |
| --- | --- |
| Project | xLZDx/Fitness-App |
| Canonical branch | master |
| Repository baseline (unchanged since v4.2) | 532235d35d320b340929a736cae40c5e1661f5d5 |
| Document status | MECHANICAL PATCH CANDIDATE — closes GPT-PM round-3's 2 remaining items (1 CRITICAL partial, 1 MINOR) from binary verification of v4.3. GPT-PM's own round-3 verdict states that applying these two literally is sufficient for `v4.3 CONSENSUS / APPROVE FOR PHASED IMPLEMENTATION` with no further contested round — this document is that literal application, **pending GPT-PM's actual confirmation on this v4.4 text** before the status is self-declared CONSENSUS (§0.4, §15). |
| Predecessor status | v4.3 MECHANICAL PATCH — round-3 (binary verification, not a new adversarial round) verdict: **NOT YET CONSENSUS**. 6 of 7 round-2 invariants confirmed CLOSED (evidence lane, ABSTAIN/infra split, contract negotiation, NEED_MORE_VIEW denominator, App Check transition, revocation correctness). 1 CRITICAL (`RecognitionAuthorityTuple` missing OCR/parser authority) NOT FULLY CLOSED + 1 new MINOR (`UNAVAILABLE_CATALOG_VERSION` had no matching `failureCode`) found on the full v4.3 text — full record in §0.4 below and in `core/review/` (verdict text logged verbatim via PM Bridge diagnostic read, 2026-08-22). |
| Production exact-model claim | Still BLOCKED until P6 sealed blind evaluation + statistical confidence bounds + calibration/open-set gate + model-by-model promotion + B-01..B-04 + all round-2/round-3 invariants close |
| Workstream classification | POST_MVP_HIGH, unchanged |
| Primary design rule | Unchanged from v4.2 — NO SILENT DEGRADATION — **extended in this revision**: a claim's evidence lane (text-only vs. visual) is itself now a machine-observable, server-derived fact, not an implementation convention |

```text
MASTER DECISION (unchanged from v4.1/v4.2)
SPTR must own its own canonical Machine Knowledge Base. Official manufacturer data
establishes brand/line/model/SKU truth; licensed assets and real gym photos support
recognition; wger and other exercise APIs enrich the exercise graph after recognition.
Runtime evolution is additive. Exact identity may improve the answer, but it may never
bypass existing safety or turn uncertainty into a fabricated exact model.
```

```text
NO SILENT DEGRADATION (v4.2, unchanged) + v4.3 addendum

Every exact-identity attempt MUST produce exactly one machine-observable terminal outcome.
SAFE ABSTENTION is not SERVICE FAILURE.
SERVICE FAILURE is not UNSUPPORTED MODEL.
UNSUPPORTED MODEL is not UNKNOWN EQUIPMENT.
CLIENT CANCEL is not BACKEND TIMEOUT.
POLICY REVOCATION is not HISTORICAL EXACT IDENTITY.

NEW: TEXT-ONLY EVIDENCE is not VISUAL-ASSISTED EVIDENCE.
A model may be VERIFIED for one evidence lane without being VERIFIED for the other,
and a claim's evidence lane is a server-derived fact the runtime enforces, never a
convention the implementation is merely expected to follow.
```

# 0. Document basis and authority

This document is a **mechanical patch** on top of v4.2 (`SPTR_EQUIPMENT_RECOGNITION_MASTER_TECHNICAL_PLAN_v4.2_REMEDIATED_RC_2026-08-22.md`). Every section not listed in §0.3 below is carried forward from v4.2 **unchanged, verbatim** — this document does not re-litigate anything v4.2 already closed (B-01..B-04) or anything GPT-PM's round-2 verdict explicitly accepted as correct (see the "what GPT-PM does not consider a new problem" list in §0.3).

## 0.1-0.2 — unchanged from v4.2 (four evidence layers; v4.1→v4.2 remediation record). See that document for the full B-01..B-04/C-01..C-04/M-01..M-05 changelog table.

## 0.3 v4.3 patch record — GPT-PM round-2 verdict and its mechanical closure

**Round-2 verdict, verbatim conclusion (GPT-PM, 2026-08-22, via PM Bridge Playwright transport, full v4.2 document text sent and confirmed read):**

> VERDICT: NOT APPROVE — B-01..B-04 are genuinely closed, but the full v4.2 text confirms 1 new BLOCKER, 2 CRITICAL and 4 MAJOR remain... Round-cap здесь можно считать исчерпанным и закрытым. Я не предлагаю третий широкий review. Нужна только механическая финальная правка этих 7 пунктов. После неё status можно менять на v4.2 CONSENSUS без ещё одного состязательного цикла.

This is treated as a **round-cap exhaustion with a fully specified closure list**, per §10's own rule (an unresolved BLOCKER/CRITICAL after round cap is `ESCALATED_UNRESOLVED`, never silently treated as resolved) — except here GPT-PM itself supplied the exact closure condition instead of leaving it open, so this patch closes it directly rather than escalating to the operator as an unresolved disagreement.

| ID | Severity | Finding (round-2, against full v4.2 text) | Closed in |
| --- | --- | --- | --- |
| N-BLOCKER-1 | BLOCKER | P6-T text-only promotion lane has no server-enforced `evidenceLane`; a model could be authorized `EXACT_MODEL` via P6-T while a visual discriminator silently participated, without ever passing P6-V | New §6.4.1, §6.5 `evidenceLane` field, new P6.G0 invariant |
| N-CRITICAL-1 | CRITICAL | `abstainReason` still lists `EMBEDDING_FAILURE`/`INDEX_UNAVAILABLE`/`RATE_LIMITED`/`TIMEOUT` inside the "healthy" `ABSTAIN` decision, contradicting the master invariant that SAFE ABSTENTION is not SERVICE FAILURE | §6.5 rewritten: `abstainReason` restricted to genuine low-confidence causes; infra causes moved to `failureCode` under `UNAVAILABLE_*` only |
| N-CRITICAL-2 | CRITICAL | `equipment_identity_sessions`' pinned tuple omits `identityPolicyVersion`/`verifierModelVersion`/embedding sub-versions that the response contract independently carries — a session can aggregate evidence across two different decision authorities without the pin catching it | §4.2/§6.5 unified into one immutable `RecognitionAuthorityTuple`; revocation defined as a separate, non-mutating layer |
| N-MAJOR-1 | MAJOR | `identityContractVersion` is server→client only; no request-side negotiation, no defined incompatible-client outcome | §6.5 request contract extended: `clientCapabilities[]`, `UNSUPPORTED_CLIENT_CONTRACT` outcome, N/N-1 contract tests |
| N-MAJOR-2 | MAJOR | §7.1 explicitly excludes `NEED_MORE_VIEW` from P2.G5's value-checkpoint denominator, inflating apparent OCR-only success rate | §7.1/P2.G4/P2.G5 rewritten: all eligible scans stay in the denominator; `NEED_MORE_VIEW` counted as "OCR unresolved," shown separately as a recoverable UX outcome only |
| N-MAJOR-3 | MAJOR | P0.G0/P6.G1 don't say an App Check enforcement-mode transition invalidates prior shadow evidence gathered under the weaker mode | New rule in P0.G0/P6.G1: material auth-mode change invalidates the affected shadow evidence; bounded post-enforcement re-shadow required (auth/availability slice only, not full ML reshadow) |
| N-MAJOR-4 | MAJOR | §6.6 states push/listener invalidation as the sole correctness mechanism for revocation, stronger than a serverless push channel can honestly guarantee | §6.6 rewritten: push/listener is an optimization; correctness requires either an authoritative read before every `EXACT_MODEL` emission or an explicitly proven bounded-staleness mechanism meeting the stated SLA |

**What GPT-PM's round-2 verdict explicitly does NOT treat as a new problem (carried forward unexamined, per the verdict's own "остальные исправления v4.2 я принимаю" list):** the separate `family(scanId)`+`autoDispose` provider design; `abuse_guard.ts` reuse; existing ML lifecycle/CI reuse; `actionabilityStatus`; raw-OCR-logging prohibition; Clopper-Pearson naming; exact-history client-write denial; staged catalog publication; region pinning as a constraint; **P6-T as a lane concept itself** (only its lack of machine-enforced separation from P6-V was the finding); `ESCALATED_UNRESOLVED`; P0.G6 deployment isolation; correction≠training-label; the online/labeled-only observability split; and the P0 gate count/parallelism structure (`P0.G0` may stay externally blocked for months without gating catalog/OCR shadow work; `P0.G5/G6` are architecture spikes, not month-long programmes).

## 0.4 v4.4 patch record — GPT-PM round-3 binary-verification result and its mechanical closure

Round-3 was explicitly **not** a new adversarial round — per GPT-PM's own round-2 conclusion, it was a binary check of whether the 7 named invariants literally landed in v4.3's binding text, with no new architectural rebuttal invited. Result, verbatim conclusion:

> VERDICT: NOT YET CONSENSUS — 6/7 invariants are mechanically closed; #3 is still incomplete. One new MINOR schema inconsistency also exists... До CONSENSUS/APPROVE осталось буквально две механические правки... После них я не вижу основания запускать ещё один review round... Если в локальном master-документе эти две правки будут внесены буквально, мой финальный статус будет: v4.3 CONSENSUS APPROVE FOR PHASED IMPLEMENTATION.

Both findings were independently re-verified against v4.3's actual text before being accepted (not taken on GPT-PM's word):

| ID | Severity | Finding (round-3, against v4.3 binding text) | Verified against v4.3 text | Closed in v4.4 |
| --- | --- | --- | --- | --- |
| N3-CRITICAL-1 | CRITICAL (partial — 6 of 7 round-2 items were confirmed CLOSED; only this one was NOT FULLY CLOSED) | `RecognitionAuthorityTuple` (§4.6) still omitted `ocrVersion`/an identity-parser version, while `EquipmentIdentityResponse` (§6.5) still carried `ocrVersion` as a standalone field outside the pinned tuple — two views in one session could formally satisfy "immutable tuple" while running under different OCR/parser versions | Confirmed: §4.6's tuple (v4.3 original) listed 8 fields, none OCR-related; §6.5's response struct had a bare trailing `ocrVersion` line, outside `authority` | §4.6 tuple gains `ocrVersion`/`identityParserVersion?`; §6.5's standalone `ocrVersion` field removed, sourced only from `authority.ocrVersion`; new binding rule: all views in a session must share the pinned OCR/parser authority or the session terminates and restarts |
| N3-MINOR-1 | MINOR | `failureCode` enum had no value corresponding to `decision: UNAVAILABLE_CATALOG_VERSION`, even though `failureCode` was specified as required for every `UNAVAILABLE_*` decision | Confirmed: v4.3's `failureCode` enum (§6.5) listed 8 values, none naming catalog-version unavailability | `CATALOG_VERSION_UNAVAILABLE` added to the `failureCode` enum |

GPT-PM additionally suggested (not required for CONSENSUS, applied anyway as free, same-diff hygiene): `verifierModel` should be explicitly documented as a **display-only mirror** of `authority.verifierModelVersion`, never an independently-resolved value — done in §6.5's binding rules.

Per GPT-PM's own stated condition, applying these two mechanical fixes (verified against the real v4.3 text, not merely pasted as instructed) is sufficient for `v4.3 CONSENSUS / APPROVE FOR PHASED IMPLEMENTATION` without a further contested review round. This document (v4.4) is that mechanical closure — see §15 for the updated final status.

# 1-3. Comparison, repository baseline, master decisions

Unchanged from v4.2 (§1, §2), **except D12 in §3, extended below.**

**D12 (extended for v4.3, closes N-CRITICAL-2).** A recognition session pins its full `RecognitionAuthorityTuple` once, and that tuple is immutable for the session's lifetime — not a partial subset of the fields the response contract actually carries. Live revocation/kill-epoch checks are a **separate, non-mutating layer**: they may only terminate a session (forcing `CANCELLED_STALE`/`UNAVAILABLE_CATALOG_VERSION`) — they may never cause a session to continue under a *different* pinned tuple than the one it started with. Mixing evidence from two decision authorities inside what is reported as one `recognitionSessionId` is exactly the silent-degradation class D12 exists to forbid.

**New, D14 (closes N-BLOCKER-1). A claim's evidence lane is a server-derived, machine-enforced fact, never an implementation convention.** Every response carries `evidenceLane: TEXT_ONLY | VISUAL`, computed by the server from which signals actually participated in the decision — not asserted by the caller, not inferred from `textSupportStatus` alone. `TEXT_ONLY` claims are authorized only under the closed condition in §6.4.1; the moment any visual exact-identity discriminator participates, the lane is `VISUAL` and P6-V's (not P6-T's) promotion status governs whether the claim may be made at all.

# 4. Canonical data model and Firestore boundaries

## 4.1, 4.3, 4.4 — unchanged from v4.2.

## 4.2 Recommended Firestore collections (extended, closes N-CRITICAL-2)

Unchanged from v4.2 except the `equipment_identity_sessions` collection, which is redefined:

- **`equipment_identity_sessions` (redefined).** One document per `recognitionSessionId`, written once at session start by the server, holding the pinned **`RecognitionAuthorityTuple`** (§4.5, new) in full — not the four-field subset v4.2 pinned. Every subsequent request in that session reads this pin rather than re-resolving "current active" versions mid-session. A support-status demotion or policy kill-flag published after a session is pinned **terminates** that session (`CANCELLED_STALE`/`UNAVAILABLE_CATALOG_VERSION`, checked via a live revocation flag on every request) — it never causes the session to silently continue reading a *different* tuple. Additive catalog changes (new models, non-demoting metadata) do not invalidate an in-flight session.

## 4.5 Firestore rules boundary — unchanged from v4.2 (B-02 closure, confirmed CLOSED by GPT-PM round-2 with one binding implementation note carried forward verbatim): `recognised_models` and `equipment_identity_sessions` must be excluded from the wildcard **allow**, and a separate narrower deny does not cancel an already-matched allow — the emulator mutation-test suite (§4.5 of v4.2) is the acceptance test for this, unchanged.

## 4.6 `RecognitionAuthorityTuple` (new section, closes N-CRITICAL-2)

```text
RecognitionAuthorityTuple {
  catalogVersion
  ocrVersion
  identityParserVersion?      # omit only if explicitly versioned by textPolicyVersion
  textPolicyVersion
  fusionPolicyVersion
  identityPolicyVersion
  embeddingModelVersion?
  embeddingIndexVersion?
  exemplarSetVersion?
  verifierModelVersion?
}
```

`ocrVersion`/`identityParserVersion` join the tuple in v4.4 (closes a round-3 finding,
§0.4): `EquipmentIdentityResponse.ocrVersion` (§6.5) previously sat outside the pinned
authority tuple, meaning two views in one `recognitionSessionId` could formally satisfy
"immutable tuple" while running under different OCR/parser versions — the exact class
of silent multi-authority drift D12/D14 exist to forbid. Binding rule: the OCR and
identity-parser authority used by every view aggregated into one session MUST equal the
pinned tuple; if the runtime cannot satisfy the pinned version (e.g. after an OCR model
rollout mid-session), the session terminates and restarts under a new tuple — it never
silently continues on a different OCR version under the same `recognitionSessionId`.

Binding rules:

- This tuple, in full, is what `equipment_identity_sessions` pins at session start (§4.2) and what every `EquipmentIdentityResponse` in that session must be consistent with (§6.5) — the response contract's individual version fields are views onto this one tuple, not independently-resolved values that happen to usually agree with it.
- **Immutable within a session.** No code path may update a pinned tuple's fields in place; a policy/model change after pinning is only ever observable as session termination, never as an in-place tuple mutation.
- **Revocation is a separate layer.** A live kill/revocation check runs on every request independent of the cached pin (§6.6 defines its correctness bound) and has exactly one effect on session state: terminate. It has no path to substitute a new tuple into a running session.
- Verification: a session-mutation test asserting that no code path can update a pinned `RecognitionAuthorityTuple` field once written, only replace the whole session (new `recognitionSessionId`) — required for P1.G1/P2.G3 exit alongside the existing emulator mutation-test suite.

# 5. Source acquisition, Wger enrichment and rights governance

Unchanged from v4.2.

# 6. Recognition runtime: OCR, retrieval, fusion, calibration, verifier and terminal outcomes

## 6.1-6.3 — unchanged from v4.2.

## 6.4 Fusion, confidence and open-set policy — unchanged base text from v4.2 (Clopper-Pearson naming, mandatory `verifierInvoked`), **extended with new §6.4.1.**

### 6.4.1 Evidence-lane authorization (new, closes N-BLOCKER-1)

```text
BLOCKER, now closed in binding text
v4.2's §8.2 declared P6-T and P6-V as two independently reachable promotion lanes,
but no runtime contract field forced a claim made under P6-T's authority to actually
be free of visual exact-identity evidence. A model could be textSupportStatus:VERIFIED
(via P6-T) while runtime fusion also used embedding/KNN/verifier signals as an
additional discriminator -- producing an EXACT_MODEL claim whose visual component
never passed P6-V's sealed statistical gate at all.
```

Binding rule for v4.3: every `EquipmentIdentityResponse` with `identityLevel: EXACT_MODEL` carries a server-computed `evidenceLane: TEXT_ONLY | VISUAL` (§3 D14). The server, not the client and not a static config flag, decides this per-response from which signals actually participated:

```text
evidenceLane = TEXT_ONLY  requires ALL of:
  embeddingVersion == null
  verifierInvoked == false
  no visual/logo/retrieval exact-model discriminator participated in the decision
  the claimed model's textSupportStatus == VERIFIED (P6-T PASS)

evidenceLane = VISUAL  whenever ANY visual exact-identity signal participated,
  regardless of whether text evidence was also present; requires the claimed
  model's visionSupportStatus == VERIFIED (P6-V PASS)
```

Generic visual **type** evidence (the existing `ScanResult`/`equipmentId` path) may still confirm or contradict functional compatibility at any time — that is unrelated to exact-model identity and is not gated by this rule. What this rule forbids is a visual signal silently upgrading confidence or acting as a tiebreaker on an `EXACT_MODEL` claim that is then reported/authorized as if it were text-only.

This is a **CI/mutation invariant, not a convention**: P4.G2 (fusion) must be structurally incapable of returning `evidenceLane: TEXT_ONLY` on a response where a visual discriminator was consulted — enforced by a unit/mutation test that forces a visual signal into the fusion path under `textSupportStatus: VERIFIED` and asserts the response is rejected or downgraded to `evidenceLane: VISUAL` (which then requires P6-V, and abstains if P6-V hasn't passed for that model). Required for P6.G0 exit (new gate, §9).

## 6.5 Recognition response contract (rewritten again for v4.3, closes N-CRITICAL-1, N-CRITICAL-2, N-MAJOR-1)

```text
EquipmentIdentityRequest {                    # NEW -- request-side contract negotiation (N-MAJOR-1)
  scanId
  identityContractVersion                     # version the CLIENT was built against
  clientCapabilities[]                        # e.g. ["MULTI_VIEW", "PLACARD_CAPTURE"]
}

EquipmentIdentityResponse {
  scanId
  recognitionSessionId
  identityContractVersion                     # server's negotiated/accepted version
  authority: RecognitionAuthorityTuple         # NEW -- full immutable tuple, see 4.6;
                                                #   replaces the four loose version fields
                                                #   v4.2 carried ad hoc
  evidenceLane: TEXT_ONLY | VISUAL             # NEW -- server-derived, see 6.4.1
  type: { id }
  typeEvidenceStatus
  identityLevel: TYPE_ONLY | BRAND_AND_TYPE | PRODUCT_LINE | EXACT_MODEL

  decision: MATCH
          | ABSTAIN                  # honest low-confidence / ambiguous -- NORMAL, expected
          | NEED_MORE_VIEW
          | NOT_SUPPORTED             # model/catalog entry exists but not eligible for claim
          | CANCELLED_STALE           # scanId/recognitionSessionId superseded before completion
          | UNSUPPORTED_CLIENT_CONTRACT   # NEW -- client's identityContractVersion rejected
          | UNAVAILABLE_TIMEOUT
          | UNAVAILABLE_NETWORK
          | UNAVAILABLE_APPCHECK
          | UNAVAILABLE_RATE_LIMIT
          | UNAVAILABLE_BACKEND
          | UNAVAILABLE_CATALOG_VERSION    # session's pinned tuple was revoked mid-session

  abstainReason?: LOW_CONFIDENCE | OUT_OF_DISTRIBUTION | EVIDENCE_CONFLICT
                | INSUFFICIENT_EVIDENCE
                # REWRITTEN (closes N-CRITICAL-1): required only when decision == ABSTAIN.
                # Contains ONLY genuine low-confidence/ambiguity causes. Never present
                # for an UNAVAILABLE_* outcome.

  failureCode?: TIMEOUT | NETWORK | APPCHECK | RATE_LIMITED | BACKEND_ERROR
              | EMBEDDING_FAILURE | INDEX_UNAVAILABLE | VERIFIER_SCHEMA_VIOLATION
              | CATALOG_VERSION_UNAVAILABLE   # NEW in v4.4, closes round-3 MINOR --
              # UNAVAILABLE_CATALOG_VERSION previously had no matching failureCode value
              # NEW (closes N-CRITICAL-1): required only when decision resolves to any
              # UNAVAILABLE_* value. Feeds a metrics series SEPARATE from abstention
              # rate (see 8.4). This is where every infrastructure cause that v4.2's
              # abstainReason wrongly hosted now lives -- an infra failure can never
              # again be observationally reported as decision:ABSTAIN.

  brand?
  productLine?
  model?
  calibratedConfidence?
  verifierInvoked: bool              # mandatory when identityLevel == EXACT_MODEL
  verifierModel?                     # display-only mirror of authority.verifierModelVersion,
                                      # NEVER an independently-resolved value (v4.4 clarification)
  evidence[]
  nextView?: LOGO | PLACARD | SIDE | FULL
}
```

Binding rules:

- `abstainReason` and `failureCode` are **mutually exclusive by construction** — a response schema/mutation test must reject any payload carrying both, or carrying `abstainReason` alongside a `decision` other than `ABSTAIN`. This is the mechanical closure of N-CRITICAL-1: `ABSTAIN` is never again indistinguishable from an infrastructure outage on a dashboard or in an alert rule.
- `authority` (the full `RecognitionAuthorityTuple`, §4.6, now including `ocrVersion`/`identityParserVersion`) replaces v4.2's separately-listed `catalogVersion`/`fusionPolicyVersion`/`textPolicyVersion`/`identityPolicyVersion`/`embeddingVersion`/`ocrVersion` fields — one struct, one source of truth, matching exactly what `equipment_identity_sessions` pins. **`ocrVersion` is no longer a standalone response field (v4.4)** — it lives only in `authority.ocrVersion`, closing the round-3 finding that a session's OCR/parser authority could drift between views without formally violating the "immutable tuple" rule.
- **`failureCode` now has a value for every `UNAVAILABLE_*` decision (v4.4)** — `CATALOG_VERSION_UNAVAILABLE` maps to `decision: UNAVAILABLE_CATALOG_VERSION`, closing the round-3 MINOR (schema previously allowed `UNAVAILABLE_CATALOG_VERSION` with no valid `failureCode`).
- `verifierModel` is a **display-only mirror** of `authority.verifierModelVersion` (v4.4 clarification) — the two must never be independently resolved; only `authority.verifierModelVersion` is authoritative.
- **Request-side contract negotiation (closes N-MAJOR-1).** The server checks the request's `identityContractVersion` against its own supported range. An unsupported client version resolves to `decision: UNSUPPORTED_CLIENT_CONTRACT` — never a silent fallback to some default behavior the old client wasn't designed for. P2.G3/P2.G4 must include N/N-1 contract compatibility tests (current server against the immediately prior mobile release's request shape, and vice versa during a rollout window).

## 6.6 Server-side session lifecycle, cancellation and idempotency (rewritten again for v4.3, closes N-MAJOR-4)

Base mechanics unchanged from v4.2 (server-side supersession check before the expensive step and before writing the response; `work_discarded_as_stale` counter). **Revocation correctness bound rewritten:**

```text
CRITICAL, now closed in binding text
v4.2 stated push-based invalidation ("a Firestore listener or Pub/Sub... every warm
instance must honor") as if it were itself the correctness guarantee for revocation.
A push/listener channel is inherently best-effort in a serverless environment (a warm
instance can miss a message, a listener can silently disconnect) -- treating it as the
sole boundary is a stronger promise than the mechanism can honestly make, and is
exactly the kind of single-point silent-failure risk this whole document exists to
close elsewhere.
```

Binding rule for v4.3: revocation correctness rests on exactly one of these two mechanisms, chosen and proven per deployment, never on push/listener delivery alone:

- **(a) Authoritative read before emission.** Every `EXACT_MODEL` emission performs a live, authoritative read of the model's current support/revocation status immediately before responding — push/listener-based cache warming remains a latency **optimization** on top of this, never a substitute for it; or
- **(b) Proven bounded staleness.** A cached catalog/policy pointer with an explicit TTL (target: 60s, per v4.2) is acceptable **only if** the deployment can demonstrate, under load, that worst-case observed staleness across all warm instances stays within the TTL bound with a stated confidence — not merely that the mechanism exists, but a measured proof it holds. If the stated rollback SLO is, say, 10 seconds, (b) requires evidence the mechanism actually delivers ≤10s, not an assumption that a Firestore listener will always fire in time.

`equipment_identity_sessions`' live revocation check (§4.2/§4.6) sits on top of whichever bound is chosen and terminates affected sessions — it does not itself supply the correctness guarantee; the guarantee comes from (a) or (b) being actually true of the deployed system.

# 7. UX, safety, privacy, history and gym-instance memory

## 7.1 Progressive recognition UX (extended again, closes N-MAJOR-2)

Base mobile-architecture rule unchanged from v4.2 (`EquipmentIdentity` served by a separate `family(scanId)`, `autoDispose` provider; never added to `ScanResult`).

**Reversed for v4.3 (was wrong in v4.2):**

```text
BEFORE (v4.2, incorrect per GPT-PM round-2)
  NEED_MORE_VIEW ... is excluded from P2.G5's value-checkpoint arithmetic in the interim

AFTER (v4.3, binding)
  NEED_MORE_VIEW remains IN the P2.G5 value-checkpoint denominator.
```

`NEED_MORE_VIEW` is counted as **OCR unresolved** for the purposes of the value-checkpoint metric — excluding it from the denominator inflates apparent OCR-only success rate by shrinking the base to only the scans that already resolved. Concretely: of 100 eligible scans (35 EXACT, 15 BRAND/LINE, 40 NEED_MORE_VIEW, 10 NOT_SUPPORTED), the OCR-only value metric is computed over all 100 eligible attempts, never over the 50 that happen to have resolved to a firm identity level. `NEED_MORE_VIEW` is *separately* surfaced as a recoverable UX outcome (it renders as a plain re-scan prompt until P5.G1's guided multi-view flow ships, unchanged from v4.2) — that UX framing does not license dropping it from the product-value denominator.

## 7.2-7.5 — unchanged from v4.2.

# 8. Dataset, evaluation, ML governance and observability

## 8.1-8.3 — unchanged from v4.2.

## 8.4 Observability and cost (extended, closes N-CRITICAL-1's metrics-side consequence)

Base split unchanged from v4.2 (`ONLINE_OBSERVABLE` vs. `LABELED_EVALUATION_ONLY`). **One correction:** the `ONLINE_OBSERVABLE` list's "per-`UNAVAILABLE_*`-reason failure rate" now reads from the new `failureCode` field (§6.5), not from `abstainReason` — `abstainReason`'s series is restricted to the four genuine low-confidence causes and must never again be conflated with the infrastructure-failure series in a dashboard query, a distinction that only became mechanically enforceable once §6.5 separated the two fields.

## 8.5 — unchanged from v4.2.

# 9. Phased implementation plan and gate definitions (extended)

Phase table unchanged from v4.2 except: P0 gains a note that **P0.G0 (new sub-clause) governs shadow-evidence validity across an App Check mode transition** (closes N-MAJOR-3), and P6 gains a new prerequisite gate **P6.G0** (closes N-BLOCKER-1).

## Phase P0 — Foundation, provenance & platform readiness

### P0.G0 — App Check platform readiness (extended, closes N-MAJOR-3)

Base gate unchanged from v4.2 (`APP_CHECK_PLATFORM_READINESS` status; production exact identity blocked until `READY_FOR_PRODUCTION`). **New binding sub-rule:**

```text
MAJOR, now closed in binding text
v4.2 allowed shadow/development identity work with App Check enforcement off, but
never said what happens to evidence gathered under that weaker mode once enforcement
is later turned on -- P6.G1 could then be satisfied by shadow volume collected before
the exact security posture P6.G1 is supposed to validate was ever actually in effect.
```

Binding rule: a material `APP_CHECK_PLATFORM_READINESS` transition (specifically, any transition that changes whether enforcement is active) **invalidates the auth/availability slice of prior shadow evidence** — the `UNAVAILABLE_APPCHECK` failure-rate series and any App Check-dependent SLO measurement collected before the transition no longer count toward P6.G1's minimum-volume requirement. This does **not** require re-running the full ML shadow (candidate/abstention distribution evidence gathered pre-transition remains valid — App Check enforcement doesn't change model behavior). A bounded post-enforcement canary/re-shadow period (auth/availability metrics only) is required before P6.G1 may be marked satisfied using post-transition data.

### P0.G1-G6 — unchanged from v4.2.

## Phase P1 — Canonical Machine Knowledge Base

### P1.G1 — extended: the session-mutation test from §4.6 (no in-place `RecognitionAuthorityTuple` field update, only session replacement) is added to this gate's verification list, alongside the existing emulator mutation-test suite. Otherwise unchanged from v4.2.

### P1.G2-G6 — unchanged from v4.2.

## Phase P2 — OCR-first Identity

### P2.G1-G2 — unchanged from v4.2.

### P2.G3 — extended, closes N-MAJOR-1's server-side half: deliverables gain **request-side contract validation** (`identityContractVersion`/`clientCapabilities[]` check, `UNSUPPORTED_CLIENT_CONTRACT` outcome) and N/N-1 contract compatibility tests. Otherwise unchanged from v4.2.

### P2.G4 — corrected (closes N-MAJOR-2's mobile-side half): **`NEED_MORE_VIEW` is included in P2.G5's value-checkpoint denominator** (§7.1) — the interim exclusion v4.2 specified here is removed. Verification otherwise unchanged from v4.2 (separate `family(scanId)` provider tests; existing `scanner_page_test.dart`/`scan_controller_test.dart` pass unmodified).

### P2.G5 — corrected (closes N-MAJOR-2): the OCR-only value checkpoint is computed over **all eligible scans**, including `NEED_MORE_VIEW`, per §7.1's reversed rule. `NEED_MORE_VIEW`'s separate recoverable-UX-outcome display is unaffected.

## Phase P3-P5 — unchanged from v4.2, except §7.1's P2.G5-denominator correction above is binding wherever P3-P5 reference that metric.

## Phase P6 — Shadow, Evaluation & Promotion (extended, closes N-BLOCKER-1)

### P6.G0 — Evidence-lane separation invariant (new gate, closes N-BLOCKER-1)

CLASSIFICATION: **RELEASE-BLOCKING PREREQUISITE**, ahead of P6.G1

Purpose. Prove, mechanically, that the P6-T text-only promotion lane cannot produce an `EXACT_MODEL` claim contaminated by visual exact-identity evidence — the specific gap GPT-PM's round-2 verdict identified as the one remaining BLOCKER.

Inputs. §6.4.1's `evidenceLane` derivation rule; P4.G2's fusion implementation.

Deliverables. The CI/mutation invariant described in §6.4.1: a test that forces a visual exact-identity discriminator into the fusion path for a model whose `textSupportStatus == VERIFIED` and `visionSupportStatus != VERIFIED`, and asserts the response is never `evidenceLane: TEXT_ONLY` with `identityLevel: EXACT_MODEL` — it must instead report `evidenceLane: VISUAL` and abstain/downgrade, since P6-V hasn't passed for that model.

Verification. The mutation test above, run in CI, blocking. A manual code-review sign-off does not satisfy this gate — per §10's existing rule that release-blocking gates need a concrete CI check or signed artifact, not an eyeballed claim.

Required review. Backend/ML + release review.

Exit. Mutation test exists, is wired into CI, and passes.

Rollback / failure mode. Until this gate passes, P6-T's promotion output (`textSupportStatus: VERIFIED`) may not be used to authorize `identityLevel: EXACT_MODEL` in production for any model that also has visual retrieval/verifier signals active — text-only-verified models remain shadow/`NOT_SUPPORTED`-for-EXACT_MODEL in production until P6.G0 closes.

### P6.G1 — Shadow deployment (extended, closes N-MAJOR-3's gate-side half)

Base gate unchanged from v4.2 (RELEASE-BLOCKING PREREQUISITE; minimum shadow volume/duration; terminal-outcome completeness check). **New exit sub-condition:** shadow evidence counted toward this gate's minimum-volume requirement must not include any auth/availability-slice evidence invalidated by a P0.G0 App Check mode transition (see P0.G0's new rule) — the gate's evidence-freshness check must exclude pre-transition auth/availability samples explicitly, not merely rely on total volume.

### P6.G2-G3 — unchanged from v4.2.

## Phase P7-P8 — unchanged from v4.2.

# 10. Multi-round review protocol (extended, records round-2 closure)

Base rules unchanged from v4.2 (round-cap exhaustion → `ESCALATED_UNRESOLVED`; reviewer roster honesty). **New, records this document's own provenance:**

```text
Round-2 disposition (2026-08-22)
GPT-PM's round-2 review of the FULL v4.2 document (not the changelog) surfaced 1
BLOCKER + 2 CRITICAL + 4 MAJOR beyond the original B-01..B-04 (all four confirmed
CLOSED). GPT-PM itself declared round-cap exhausted and supplied a complete, closed
list of 7 required invariants rather than requesting a third open-ended review round.
This document (v4.3) is the mechanical closure of that list. Per GPT-PM's own stated
condition, no further adversarial round is owed before v4.3 -> v4.3 CONSENSUS -- only
a binary verification pass (do the 7 invariants appear, unambiguously, in binding text
with no formal path to bypass them) is required.
```

This is **not** a unilateral self-certification: it is the documented mechanical execution of a closure condition GPT-PM itself set. The binary verification pass itself (confirming the 7 invariants actually landed as specified, with no loophole) is still owed before `v4.3 CONSENSUS` may be declared — see §15.

## 10.1-10.2 — unchanged from v4.2.

# 11-14. Release metrics, repository/file plan, non-goals, source ledger

Unchanged from v4.2 (§11, §12, §14), **except §13, extended:**

**New non-goals for v4.3 (§13 extension):**

- Do not let `abstainReason` and `failureCode` co-occur on a response, or let `abstainReason` appear on a non-`ABSTAIN` decision — a schema/mutation test enforces this.
- Do not let any code path mutate a pinned `RecognitionAuthorityTuple` field in place; revocation only ever terminates a session.
- Do not authorize an `EXACT_MODEL` claim as `evidenceLane: TEXT_ONLY` when any visual exact-identity discriminator participated in the decision.
- Do not treat push/listener cache invalidation as a sufficient correctness proof for revocation without either an authoritative pre-emission read or a measured, proven staleness bound.
- Do not exclude `NEED_MORE_VIEW` (or any other recoverable-but-unresolved outcome) from a product-value denominator merely because it complicates the arithmetic.
- Do not count shadow evidence gathered before a material App Check enforcement-mode transition toward P6.G1's post-transition minimum-volume requirement for the auth/availability slice.

# 12.3 addendum — backend files touched by this revision

```text
functions/src/equipment_identity/
  contract.ts        # CHANGE: request-side identityContractVersion/clientCapabilities
                      #   validation, UNSUPPORTED_CLIENT_CONTRACT outcome (6.5)
  recognize.ts        # CHANGE: evidenceLane derivation (6.4.1), authority-tuple
                      #   read/immutability enforcement (4.6), abstainReason/
                      #   failureCode split (6.5)
  evidence_fusion.ts  # CHANGE: P6.G0 mutation-test target -- must not launder a
                      #   visual discriminator's participation into evidenceLane:TEXT_ONLY
  policy.ts           # CHANGE: revocation as session-termination-only (4.6, 6.6);
                      #   App-Check-mode-transition evidence invalidation (P0.G0)
  telemetry.ts        # CHANGE: failureCode series separated from abstainReason series (8.4)
```

# 15. Final recommended execution sequence

Unchanged in shape from v4.2, with the P6 step now explicitly gated by the new P6.G0 evidence-lane invariant ahead of P6.G1.

```text
FINAL STATUS FOR v4.4

DESIGN STATUS: MECHANICAL PATCH CANDIDATE -- closes GPT-PM round-3's binary-
  verification findings on v4.3 (1 CRITICAL partial, 1 MINOR) on top of v4.3's
  already-confirmed closure of 6 of round-2's 7 invariants, on top of v4.2's
  already-confirmed closure of B-01..B-04.
FOUNDATION WORK (P0, read-only P1): MAY PROCEED, unchanged.
USER-FACING / PRODUCTION EXACT IDENTITY: BLOCKED until P6.G0 (new) plus all
  previously-stated P6 gates close.

Per GPT-PM's own round-3 verdict, applying these two fixes literally is sufficient
for v4.3 CONSENSUS / APPROVE FOR PHASED IMPLEMENTATION with no further contested
review round. This document is that literal application. Per the operator's standing
instruction (2026-08-22, "не верь гпт, все проверяй сам"), self-declaring CONSENSUS
on this document's own say-so is exactly the failure mode that instruction exists to
prevent -- so this document's status remains MECHANICAL PATCH CANDIDATE, not
CONSENSUS, until GPT-PM has actually confirmed THIS v4.4 text (not merely
pre-committed to a description of it).

  [x] 1. server-derived TEXT_ONLY | VISUAL evidence lane           -- 6.4.1, 6.5, P6.G0
        -- CLOSED, confirmed round 3
  [x] 2. infra failures impossible under ABSTAIN                    -- 6.5
        -- CLOSED, confirmed round 3
  [x] 3. complete immutable RecognitionAuthorityTuple                -- 4.2, 4.6
        -- round 3: NOT FULLY CLOSED (missing ocrVersion/identityParserVersion) --
           FIXED in v4.4, pending round-4 (binary) confirmation
  [x] 4. actual client/server contract negotiation                  -- 6.5, P2.G3
        -- CLOSED, confirmed round 3
  [x] 5. NEED_MORE_VIEW remains in P2.G5 denominator                 -- 7.1, P2.G4, P2.G5
        -- CLOSED, confirmed round 3
  [x] 6. App Check mode change invalidates relevant shadow evidence  -- P0.G0, P6.G1
        -- CLOSED, confirmed round 3
  [x] 7. revocation correctness does not depend solely on
        warm-instance push/listener                                 -- 6.6
        -- CLOSED, confirmed round 3
  [ ] 8. (round 3, MINOR) failureCode representable for every
        UNAVAILABLE_* decision, incl. UNAVAILABLE_CATALOG_VERSION    -- 6.5
        -- FIXED in v4.4, pending round-4 (binary) confirmation
```

# Appendix A — Gate close checklist

Unchanged from v4.2, plus: "P6.G0's evidence-lane mutation test is wired into CI and passing" as a named precondition for any P6.G1+ gate close.

# Appendix B — Revision history

| Version | Date | State | Summary |
| --- | --- | --- | --- |
| v4.0 RC1 | 2026-08-21 | REVIEW CANDIDATE | Merged Source Strategy + Equipment Recognition v3. |
| v4.1 CONSENSUS | 2026-08-21 | APPROVE FOR PHASED IMPLEMENTATION → SUPERSEDED 2026-08-22 | 3 self-run rounds; approved, then superseded by independent Claude+GPT-PM cross-review. |
| v4.2 REMEDIATED RC | 2026-08-22 | REMEDIATED REVIEW CANDIDATE → round-2 NOT APPROVE | Closed B-01..B-04 + ~20 MAJOR/MINOR. GPT-PM round-2 (full-document review) found 1 new BLOCKER + 2 CRITICAL + 4 MAJOR, declared round-cap exhausted, supplied a closed 7-point mechanical closure list. |
| v4.3 MECHANICAL PATCH | 2026-08-22 | MECHANICAL PATCH CANDIDATE → round-3 NOT YET CONSENSUS | Closed 6 of GPT-PM round-2's 7 named invariants (confirmed round 3). Round 3 (binary verification, not a new adversarial round) found `RecognitionAuthorityTuple` still missing OCR/parser authority (CRITICAL, partial) and a new MINOR (`UNAVAILABLE_CATALOG_VERSION` unrepresentable in `failureCode`). |
| **v4.4 MECHANICAL PATCH** | **2026-08-22** | **MECHANICAL PATCH CANDIDATE — pending round-4 (binary) confirmation** | Closes both remaining round-3 findings: `RecognitionAuthorityTuple` (§4.6) gains `ocrVersion`/`identityParserVersion?`, response contract's standalone `ocrVersion` field removed (sourced from `authority` only), new binding rule that all views in a session share the pinned OCR/parser authority or the session terminates; `failureCode` enum gains `CATALOG_VERSION_UNAVAILABLE`; `verifierModel` documented as a display-only mirror of `authority.verifierModelVersion`. Per GPT-PM's round-3 verdict this is sufficient for CONSENSUS if applied literally — not self-declared here; awaiting GPT-PM's actual confirmation on this text. |
