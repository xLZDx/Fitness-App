# P2.G5-readiness — Shadow-data telemetry lifecycle + measurement contract

Status: DRAFT, frozen at the point of GPT-PM GO. Rosetta plan
`fitness_app-2026-09-12T21-27-25-820Z-b29fad` (hash `ade2c4dd338dd5a0752f93caefaf4b4199bcfa03b27b8e098d267b840753578d`),
GPT-PM APPROVE `70b0fb8f-d387-4209-b483-59f03b5b6c50` / reply `1c394b60-358e-47a0-9365-f0d9d22b3756`.

Step 1 of that plan, written BEFORE any implementation code (steps 2-9 depend on this document's
contract, not the other way around). Any change to this contract after step 2 starts is a material
change to the plan and needs its own Rosetta revision + GO, not a silent edit here.

## 0. Scope

IN SCOPE: define the durable per-scan telemetry record, its lifecycle states, its idempotency
rule, and the frozen P2.G5 metric formulas. NOT in scope: the actual GO_VISUAL/DEFER_VISUAL
decision, recruiting or running the pilot, or any P3/P4 work — unchanged from the plan's own scope
statement.

## 1. The binding gate contract this serves

Quoted from `core/design/sptr_equipment_recognition_v4_1/SPTR_EQUIPMENT_RECOGNITION_V4_4_GATE_CONTRACTS_AND_AC_DOD_2026-08-22.md:758-792`
(P2.G5, "OCR-only shadow & value checkpoint"):

- Inputs required: "Shadow text identity on real scans, latency, exact text-resolution rate,
  need-more-view rate, catalog coverage, and product value evidence."
- Story AC: "the value checkpoint is computed over all eligible scans, including NEED_MORE_VIEW —
  v4.2's original exclusion is binding-reversed by v4.3 and must not resurface as an 'interim'
  carve-out."
- Story DoD: "total eligible scans = resolved + NEED_MORE_VIEW (OCR unresolved) + other terminal
  outcomes, with no silent drop."

This is also restated as AC-B01 in `core/DECISION_LOG.md:23607-23610` and in P2.G4's own Story
AC/DoD (`core/DECISION_LOG.md:710-714,737,753,790`).

No numeric GO_VISUAL/DEFER_VISUAL threshold is specified anywhere in the gate contract (checked:
the file's only 6 "P2.G5" hits are reproduced above) — the gate requires the decision be
"explicit, evidence-backed," not that a named number be cleared. The literal string
"P2.G5-readiness" (as a named GPT-PM-authored DoD artifact) does not exist anywhere in the repo —
searched case-sensitively and case-insensitively across the whole tree; zero matches. This
document is what stands in its place: **it, not a separately-quoted DoD, is the frozen contract**
for this gate's own implementation.

## 2. What already exists — do not re-invent

- **Firestore path**: `users/{uid}/equipment_identity_telemetry/{docId}` is already reserved.
  Path helper: `functions-equipment-identity/src/p1/firestore_paths.ts:112-116`
  (`userEquipmentIdentityTelemetryDocPath(uid, docId)`).
- **Firestore rules**: already deny-read/deny-write for the client on this exact collection —
  `firestore.rules:364-366` ("Written by the server pipeline only; a client that could edit or
  delete its own telemetry would make it worthless as an evaluation signal.") — no rules change
  needed for step 2's ingestion path, only a real Admin SDK writer.
- **No live writer yet**: confirmed by grep — `userEquipmentIdentityTelemetryDocPath` is imported
  nowhere under `functions-equipment-identity/src` except its own definition and its unit test
  (`src/__tests__/p1_firestore_paths.test.ts`). `scripts/ci/data_lifecycle_policy.json:56-59`
  independently confirms this ("not yet wired to a live writer"), classified `DELETE` (covered by
  the existing `deleteAccount` recursive-delete cascade, no export yet — step 4 of the plan must
  reclassify to `BOTH` once export lands, per that same file's own stated policy).
- **Sibling collection with a live writer, for comparison**: `equipment_identity_sessions` /
  `equipment_identity_latest_session` DO have one (`functions-equipment-identity/src/p2/session_repository.ts`,
  imports `userEquipmentIdentitySessionDocPath` at line 28, writes via `tx.set` at lines 273, 282,
  342, 355). Step 2's writer should follow that file's transactional-merge shape rather than invent
  a new one.
- **Mobile-side idempotency precedent**: `equipment_identity_outcome_sink.dart` (mobile) already
  implements "identical-payload replay is a no-op, differing replay is a surfaced conflict" for
  in-memory outcome recording, per `core/DECISION_LOG.md:50843-50861`. Step 2/3 reuse this exact
  semantic server-side rather than inventing a second idempotency rule.

## 3. The per-scan telemetry record

One logical record per `{uid, scanId}`, written to
`users/{uid}/equipment_identity_telemetry/{scanId}` (reusing `scanId` as `docId` — the mobile scanId
minted at `mobile/lib/features/scanner/scanner_page.dart:495`, `'scan-${DateTime.now().microsecondsSinceEpoch}'`,
already the natural per-scan key; no new id scheme needed).

```
EquipmentIdentityTelemetryRecordV1 {
  schemaVersion: 1,               // literal; a future field addition bumps this
  uid: string,                    // SERVER-AUTHORITATIVE ONLY — never accepted from the client
  scanId: string,
  createdAt: string,              // RFC3339, set once on first write for this scanId
  updatedAt: string,               // RFC3339, set on every write
  state: TelemetryState,          // see §4 — the ONE field that drives all P2.G5 arithmetic
  genericOutcome: GenericScanOutcome | null,   // see §4.1
  identityOutcome: IdentityTerminalOutcome | null,  // see §4.3, present only when state=SERVER_TERMINAL
  localFailureReason: LocalFailureReason | null,    // present only when state=LOCAL_FAILURE
  requestFailureReason: RequestFailureReason | null,// present only when state=REQUEST_FAILURE
  scanStartedAt: string | null,   // RFC3339 — for latency, see §5.4
  scanEndedAt: string | null,     // RFC3339 — for latency, see §5.4
  payloadFingerprint: string,        // sha256 over the canonical outcome-affecting fields below
                                      // (mirrors orchestrator.ts's own requestFingerprint pattern,
                                      // orchestrator.ts:150-162) — the idempotency key for §6
}
```

**Revised 2026-09-15** (GPT-PM MAJOR, retrospective review of commit afca346): the fields above were
originally written as Firestore `Timestamp`. Step 2's actual implementation stores RFC3339 strings
(`new Date().toISOString()`), matching `session_repository.ts`'s own already-shipped `createdAt:
string` convention for the sibling `equipment_identity_sessions` collection this schema was designed
to sit next to. Reconciling the CONTRACT to the CHOSEN, already-consistent representation rather than
changing the implementation to `Timestamp` — introducing a second timestamp convention into this
one package, inconsistent with its one existing precedent, would be the worse fix. No downstream
reader exists yet (step 5's report script is unstarted) so there is no compatibility surface this
revision breaks.

`uid` is set only from `request.auth.uid` inside the writing Cloud Function, exactly as
`functions-equipment-identity/src/index.ts:70` already does for the identity callable itself —
never accepted as a client-supplied field, closing the same trust-boundary requirement GPT-PM's
round-1 review raised for the identity callable, applied identically here.

## 4. Lifecycle states — every real path, exhaustively

`TelemetryState` is one of exactly six values. Every value maps to a real, evidenced code path;
none is speculative.

| State | Meaning | Evidence for why this path is real |
|---|---|---|
| `NOT_ATTEMPTED` | The generic scan pipeline ran; the identity pipeline was never invoked for this scan (feature disabled, or the generic outcome made identity irrelevant). | `equipmentIdentityProvider` is a separate, optional pipeline layered on the generic scan (`core/DECISION_LOG.md:50857-50859` — outcome sink wired only into the identity provider's own success path). |
| `ENRICHMENT_DISABLED` | Identity pipeline explicitly gated off (feature flag / remote config), distinguished from `NOT_ATTEMPTED` so a future report can tell "we chose not to look" from "we tried and something broke before we could." | Named explicitly in the plan's step 1 requirement; no separate mobile flag located this session — **UNKNOWN**, to confirm during step 2/3 implementation whether a real flag exists or this collapses into `NOT_ATTEMPTED`. If no such flag exists, this value is defined but will simply never occur — that is acceptable (an unused enum value is not a defect; a missing one that later occurs uncategorized would be). |
| `LOCAL_FAILURE` | The mobile identity pipeline attempted but failed before any network request went out. | `core/DECISION_LOG.md:50859-50861` names four such branches feeding the outcome sink's fail-open-to-null path: OCR failure, ask failure, disabled, no image path. Exact `equipment_identity_providers.dart` file:line for each was not opened this session (recon hit its turn budget) — step 2 implementation must open that file and enumerate the real branches before finalizing `LocalFailureReason`'s value set below. |
| `REQUEST_FAILURE` | The mobile pipeline attempted, reached the network layer, and failed there (not a local/OCR failure). | `mobile/lib/features/visual_equipment/data/cloud_equipment_identity_service.dart` is the network client (located, not opened this session — same reason). Server-observable analogue: `orchestrator.ts`'s six `UNAVAILABLE_*` decisions (§4.3) are what the mobile side would see as HttpsError responses if the request DID reach the server; a `REQUEST_FAILURE` telemetry record is for the case it did not (timeout before response, no connectivity, DNS, etc.) — distinguished from `SERVER_TERMINAL` with an `unavailable*` identityOutcome precisely because the latter means the server DID respond, just with "not right now." |
| `SERVER_TERMINAL` | The server callable returned a response (any of the 12 `EquipmentIdentityDecision` values in `functions-equipment-identity/src/p2/contract.ts:102-115`). | Direct evidence: `contract.ts` response schema, `orchestrator.ts`'s exhaustive decision-path switch (lines 577-612 for the 4 core outcomes, plus the `UNAVAILABLE_*`/`CANCELLED_STALE`/`UNSUPPORTED_CLIENT_CONTRACT` paths documented in §4.3.2 below). |
| `CONFLICT` | A later write for the same `scanId` disagreed with an already-committed record (see §6). Terminal, not overwritten. | New state, needed because §6 requires conflicts to be surfaced, never silently resolved by last-write-wins. |

### 4.1 `GenericScanOutcome` (always recorded, independent of identity state)

Direct mirror of `mobile/lib/features/visual_equipment/data/scan_outcome.dart:13-48`:
`confident | alternatives | unknown | noEquipment | timeout | failed`. Recorded on every telemetry
record regardless of `state`, because the generic outcome is available even when identity was
never attempted (`NOT_ATTEMPTED`) — this is what lets a future report separate "identity pipeline
never ran because the generic scanner itself failed" from "generic scanner succeeded but identity
was skipped."

### 4.2 `LocalFailureReason` (present iff `state = LOCAL_FAILURE`)

Placeholder set, to be confirmed against `equipment_identity_providers.dart` in step 2 before
being frozen further:
`missingImagePath | missingStructuredRecognizer | ocrException | parserException`.
This is the plan's own step-1 wording ("localFailure (with a reason: missing path/missing
structured recognizer/OCR exception/parser exception)"), not yet independently verified against
the four branches `core/DECISION_LOG.md:50859-50861` names. **Action for step 2**: open
`equipment_identity_providers.dart`, confirm these four (or however many actually exist) map
1:1 onto real `catch`/branch sites, and correct this enum before the schema ships.

### 4.3 `IdentityTerminalOutcome` (present iff `state = SERVER_TERMINAL`)

Carries the full server response shape, not a summary — every field `contract.ts:183-274`'s
response schema defines: `decision`, `identityLevel?`, `abstainReason?`, `failureCode?`, `model?`,
`shadowCandidate?`, `authority`, `evidenceLane`, `verifierInvoked`. Storing the full record (not a
derived boolean) is what lets a later, differently-shaped report be computed from the same
telemetry without a second data-collection pass — the same reasoning `EquipmentIdentity.fromJson`
already applies on the mobile side (`equipment_identity.dart:347-421`, which re-validates every
server invariant rather than trusting a summary).

#### 4.3.1 The 4 genuine identity-pipeline outcomes (feed the P2.G5 metric numerator/denominator)

`MATCH` (resolved, exact text resolution succeeded), `NEED_MORE_VIEW` (binding: OCR-unresolved,
stays IN the denominator per AC-B01), `ABSTAIN` (evidence existed but was insufficient/conflicting
— a genuine terminal conclusion, not an infrastructure failure), `NOT_SUPPORTED` (catalog has no
matching entry — also a genuine terminal conclusion, distinct from ABSTAIN: the OCR text was
usable, the catalog just doesn't cover it).

#### 4.3.2 The 8 infrastructure/lifecycle outcomes (recorded, EXCLUDED from P2.G5 eligibility, never silently dropped)

`CANCELLED_STALE` (this scan's own identity attempt was superseded by a newer one —
`orchestrator.ts` lines 280-282, 399-405, 437-439, 678-685 — it says nothing about THIS scan's OCR
quality), `UNSUPPORTED_CLIENT_CONTRACT` (client/server version skew, `orchestrator.ts:360-364`),
`UNAVAILABLE_TIMEOUT | UNAVAILABLE_NETWORK | UNAVAILABLE_APPCHECK | UNAVAILABLE_RATE_LIMIT |
UNAVAILABLE_BACKEND | UNAVAILABLE_CATALOG_VERSION` (server-side infra/availability failures,
`orchestrator.ts` throughout §4.3 evidence above). These 8 are stored on the record like any other
outcome (never dropped) but are excluded from the P2.G5 eligibility denominator in §5 for the same
reason `NOT_SUPPORTED`/`ABSTAIN` are included: eligibility measures "did the OCR-to-catalog pipeline
reach a real conclusion," and these 8 mean it did not get the chance to, for reasons unrelated to
OCR/catalog quality. Excluding them from eligibility is a scoping decision this document makes
explicitly (per the plan's own instruction not to imply something the data doesn't support) — it is
NOT the same claim as "no silent drop": every one of these 8 is still counted, just in the
`INCOMPLETE_EVIDENCE` bucket defined in §5.3, so the report is never confidently silent about them.

## 5. The frozen P2.G5 metric contract

### 5.1 Eligibility (binding, matches the plan's own GPT-PM-reviewed verification text verbatim)

```
eligible_scans = count(state=SERVER_TERMINAL AND identityOutcome.decision IN
                        {MATCH, NEED_MORE_VIEW, ABSTAIN, NOT_SUPPORTED})
```

This is exactly "resolved + NEED_MORE_VIEW + other terminal outcomes" from the plan's verification
field and from the P2.G5 gate contract's own Story DoD (§1). `ABSTAIN` and `NOT_SUPPORTED` are the
"other terminal outcomes."

### 5.2 Exact text-resolution rate

```
text_resolution_rate = count(state=SERVER_TERMINAL AND identityOutcome.decision = MATCH)
                        / eligible_scans
```

Numerator is `MATCH` only. `NEED_MORE_VIEW` is explicitly excluded from the numerator (it is
"OCR-unresolved" by AC-B01's own wording) but stays in the denominator — this is the concrete
arithmetic form of the binding rule in §1, not a new interpretation of it.

### 5.3 Need-more-view rate and INCOMPLETE_EVIDENCE

```
need_more_view_rate = count(identityOutcome.decision = NEED_MORE_VIEW) / eligible_scans

incomplete_evidence_count = count(state IN {LOCAL_FAILURE, REQUEST_FAILURE, CONFLICT})
                           + count(state=SERVER_TERMINAL AND identityOutcome.decision IN
                                   {CANCELLED_STALE, UNSUPPORTED_CLIENT_CONTRACT,
                                    UNAVAILABLE_TIMEOUT, UNAVAILABLE_NETWORK, UNAVAILABLE_APPCHECK,
                                    UNAVAILABLE_RATE_LIMIT, UNAVAILABLE_BACKEND,
                                    UNAVAILABLE_CATALOG_VERSION})
```

`incomplete_evidence_count` is reported ALONGSIDE every P2.G5 metric, never folded into or silently
subtracted from `eligible_scans`. Step 6(b)'s denominator-honesty test asserts this bucket is
non-zero and correctly populated when a deliberately broken/incomplete synthetic run is fed in.

### 5.4 Latency

`latency_ms = scanEndedAt - scanStartedAt`, computed only for records where both timestamps are
present (i.e. not `NOT_ATTEMPTED`/`ENRICHMENT_DISABLED`). `scanStartedAt` is the mobile-side scan
start (`scanner_page.dart:_classify`, §2 of the recon), `scanEndedAt` is the mobile-side
`_scanAgain()` logical end-of-scan event (`scanner_page.dart:537-558`) — chosen deliberately over
the identity callable's own server-side duration, because P2.G5's latency question is "how long
does the USER wait," not "how long does one network call take."

### 5.5 Catalog coverage

```
catalog_coverage_rate = count(identityOutcome.decision = MATCH)
                       / count(identityOutcome.decision IN {MATCH, NOT_SUPPORTED})
```

Deliberately excludes `NEED_MORE_VIEW`/`ABSTAIN` from this specific formula's denominator: those
reflect OCR/evidence quality on scans the catalog might still cover, whereas `NOT_SUPPORTED` means
the OCR text WAS usable and the catalog specifically lacks that model — that is what "catalog
coverage" is meant to measure. Secondary, non-headline breakdown: identityLevel distribution
(`exactModel | productLine | brandAndType | typeOnly`) among `MATCH` records, showing depth of
match, not just presence/absence.

### 5.6 Product value evidence — explicit source statement (plan step 1 requires this to not be implied where absent)

**Telemetry alone does NOT provide product-value evidence.** Searched the repository
(case-insensitive) for `beta_feedback`, `user_feedback`, `survey_responses`, `nps_survey` — zero
matches anywhere in `D:\Repo\Fitness_App`. No beta-feedback or survey mechanism exists today. This
telemetry contract measures pipeline QUALITY (resolution rate, coverage, latency) — it cannot by
itself measure whether users found the feature valuable. If "product value evidence" is required
for the GO_VISUAL/DEFER_VISUAL decision (P2.G5's own stated input list, §1), it must come from a
SEPARATE mechanism not yet built and not in this plan's scope — this document does not invent one,
and no later step in this plan should present telemetry-derived quality metrics as if they were
product-value evidence.

### 5.7 Pre-registered minimum evidence window / stopping rule

Fixed here, before any counted pilot scan, per the plan's own requirement:
- Minimum sample: **50 eligible scans** (§5.1 definition) before ANY GO_VISUAL/DEFER_VISUAL
  decision may be drawn from this data. Below 50, every metric in §5.2-§5.5 must be reported as
  "insufficient sample" rather than as a decision-grade number.
- Minimum window: **14 calendar days** of collection, whichever of (sample, window) is reached
  later — a 50-scan sample gathered in one afternoon from one tester is not representative.
- No early stopping on a favorable interim number: the window/sample above is a floor, not a
  target: the decision is drawn once BOTH are met, not the moment either one first clears, closing
  the "after-the-fact convenient sample" risk the plan's step 1 names explicitly.
- These two numbers (50 / 14 days) are this document's own proposal, not independently sourced from
  an existing repo artifact — flagged as **DECISION**, not FACT, and open to GPT-PM's step-8
  pre-commit review to adjust before this contract is frozen for real.

## 6. Idempotent merge semantics

On each write attempt for `{uid, scanId}`:
1. If no record exists yet: create it (`state`, all applicable outcome fields, `payloadFingerprint`).
2. If a record exists and the incoming write's `payloadFingerprint` matches the stored one exactly:
   **no-op** — update only `updatedAt`, change nothing else. This is what makes a retried delivery
   (outbox retry, step 3) safe to replay any number of times.
3. If a record exists, its `state` is NOT terminal (i.e. still `LOCAL_FAILURE`/`REQUEST_FAILURE` —
   a genuine progression from "we couldn't tell yet" to "now we can") and the incoming write is a
   `SERVER_TERMINAL`/different state: this is a legitimate transition, not a conflict — overwrite,
   recording the prior state in an internal `priorStates` audit array (not exposed to the metric
   formulas, kept for debugging only).
4. If a record exists, IS already terminal (`SERVER_TERMINAL` or `CONFLICT`), and the incoming
   write's `payloadFingerprint` differs: **do not overwrite**. Transition to `state = CONFLICT`,
   preserve the original terminal record's fields under `conflictingWrites: [...]` rather than
   losing either version. `CONFLICT` records are excluded from every §5 formula except
   `incomplete_evidence_count`.

This mirrors, server-side, the exact semantic `equipment_identity_outcome_sink.dart` already
implements client-side in memory (`core/DECISION_LOG.md:50843-50861`) — the same rule, applied at
the durable layer that step 2 is adding.

## 7. Open items step 2/3 must resolve before code, not after

1. Confirm the real branch set behind `LOCAL_FAILURE`/`LocalFailureReason` by reading
   `equipment_identity_providers.dart` directly (not yet opened this session).
2. Confirm whether an `ENRICHMENT_DISABLED` path genuinely exists on the mobile side, or remove
   that state before schema freeze if it does not.
3. Confirm mobile-side network/quota failure surface by reading
   `cloud_equipment_identity_service.dart` directly (not yet opened this session) — needed to
   finalize `RequestFailureReason`'s value set (this document has not yet defined that enum's
   values because the evidence for it was not gathered this session; step 2 must write it from the
   real file, not guess).
4. `functions-equipment-identity` test commands, confirmed: `npm test` (jest, unit), `npm run
   test:e2e` (emulator-backed, `functions-equipment-identity/package.json:9-10`). Rules tests run
   separately: `npm --prefix functions run test:rules` (comment header,
   `functions/src/__rules__/firestore_rules.test.ts:16`).
5. Legal-text pipeline, confirmed: canonical source is `scripts/legal/legal_text.py`, generator is
   `scripts/legal/build_legal.py` (`legal_text.py:12-14`: "`build_legal.py` is the generator").
   Current claim to preserve/extend accurately: `legal_text.py:201-202` — "No advertising
   identifier is collected, and no third-party analytics or attribution SDK is built into the
   app." This telemetry is first-party Firestore, consistent with that claim; step 4's legal-text
   update must describe the new collection without contradicting it.
6. No existing Admin-SDK report/admin script was found anywhere under `scripts/` (grepped for
   `firebase-admin`/`admin.initializeApp` — zero matches) — step 5's operator-only report script is
   new work, not an extension of an existing one.
