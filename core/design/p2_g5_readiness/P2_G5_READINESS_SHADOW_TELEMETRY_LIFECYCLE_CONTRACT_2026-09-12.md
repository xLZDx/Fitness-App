# P2.G5-readiness — Shadow-data telemetry lifecycle + measurement contract

Status: DRAFT, frozen at the point of GPT-PM GO. Rosetta plan
`fitness_app-2026-09-12T21-27-25-820Z-b29fad` (hash `ade2c4dd338dd5a0752f93caefaf4b4199bcfa03b27b8e098d267b840753578d`),
GPT-PM APPROVE `70b0fb8f-d387-4209-b483-59f03b5b6c50` / reply `1c394b60-358e-47a0-9365-f0d9d22b3756`.

Step 1 of that plan, written BEFORE any implementation code (steps 2-9 depend on this document's
contract, not the other way around). Any change to this contract after step 2 starts is a material
change to the plan and needs its own Rosetta revision + GO, not a silent edit here.

**Revision, 2026-09-16**: §6 (merge semantics), §4.2/§4.2a/§4.2b (reason enums, real caller
reachability), and §7 items 4-5 (genericOutcome, lifecycle-end events) amended under the step 3a
Rosetta plan that supersedes the rejected `fitness_app-2026-09-15T22-49-23-311Z-616bf0` — see that
plan's own GPT-PM review (2 BLOCKER / 4 MAJOR) for what drove each change, and the revised plan's
own GO for this revision's authorization.

**Revision 2, 2026-09-16, same day**: a second GPT-PM review, of the first revision's own plan
(`fitness_app-2026-09-15T23-01-35-427Z-fd85bd`), returned 2 BLOCKER / 5 MAJOR — undefined
same-mobile-state progressive-enrichment merge semantics, `scanEndedAt` measuring dwell time rather
than pipeline latency, an unclosed provider-to-scanner data-flow for the classified failure reason,
a lost `malformedReply` audit trail under enrichment, a kill-switch/network-guarantee conflict for
`ENRICHMENT_DISABLED`, App Check/region parity, and timestamp validation. §4.2b, §5.4, §6 rule 5,
and §3's record shape amended again in response — this round's fix also SHRINKS step 3a's own scope
(no `ENRICHMENT_DISABLED` network send; `genericOutcome` deferred to step 3b) rather than adding
more moving parts, which structurally eliminates the same-state-enrichment and data-flow findings
rather than working around them. See the second revised plan's own GO for authorization.

**Revision 3, 2026-09-16, same day**: a third GPT-PM review, of the second revision's own plan
(`fitness_app-2026-09-15T23-12-21-164Z-974219`), returned 2 BLOCKER / 5 MAJOR — narrower "tie up
loose ends" findings rather than another structural redesign: `scanStartedAt` had no real mobile
source (fixed by parsing it from `scanId`'s own embedded mint timestamp, needing no new state);
`clientObservedFailures` was asymmetric between arrival orders (fixed — §6 rule 3's mobile-to-
mobile-or-SERVER_TERMINAL transition now also populates it, not just rule 5's reverse order);
same-state-different-reason retries needed explicit semantics (clarified as already covered by rule
3, restated explicitly); a client-observed failure on an otherwise-eligible `SERVER_TERMINAL` record
was invisible to every metric (fixed — §5.3 gained a third `incomplete_evidence_count` term); no
successful scan ever got mobile timing at all, so §5.4's latency metric would only ever see failure
records (fixed — the provider's success path now also sends a timing-only enrichment fragment via
rule 5); RFC3339 validation needed an explicit UTC mandate on the Dart side (fixed, §5.4). §3, §5.3,
§5.4, and §6 rules 3/5 amended accordingly. See the third revised plan's own GO for authorization.

**Revision 4, 2026-09-16, same day**: a fourth GPT-PM review, of the third revision's own plan
(`fitness_app-2026-09-15T23-21-46-920Z-4c1f49`), returned 0 BLOCKER / 1 MAJOR — confirming rounds
1-3's fixes hold, with one narrower correction: §5.4's proposed 15-minute upper bound on
`scanEndedAt - scanStartedAt` would silently reject legitimate long-running retries (the app reuses
`scanId` across a retry with no time boundary of its own), biasing the latency metric toward its
fast cases. The upper bound is removed; only `scanEndedAt >= scanStartedAt` remains validated.

No change to §0/§1/§2/§5.1-§5.2/§5.5-§5.7 (scope, gate contract, prior art, eligibility/resolution-
rate/coverage formulas) across any of the four revisions; §5.3 changes with revision 3 specifically
(one additive term, described above).

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
  scanEndedAt: string | null,     // RFC3339 — for latency, see §5.4 (revised 2026-09-16: the
                                   // identity pipeline's own settle instant, not _scanAgain())
  payloadFingerprint: string,        // sha256 over the canonical outcome-affecting fields below
                                      // (mirrors orchestrator.ts's own requestFingerprint pattern,
                                      // orchestrator.ts:150-162) — the idempotency key for §6
  priorStates: PriorStateEntry[] | null,          // audit only, §6 rule 3 — not in any §5 formula
  conflictingWrites: ConflictingWrite[] | null,    // audit only, §6 rule 4 — not in any §5 formula
  clientObservedFailures: ClientObservedFailure[] | null,  // NEW 2026-09-16, §6 rule 5 — a mobile
                                      // LOCAL_FAILURE/REQUEST_FAILURE report that arrived after this
                                      // record was already SERVER_TERMINAL; audit only, not in any
                                      // §5 formula; shape {state, reason, recordedAt}
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

**Confirmed 2026-09-16** against `equipment_identity_providers.dart`'s real `equipmentIdentityProvider`
(recon for the step 3a plan): the placeholder four map 1:1 onto real branches, once the provider's
single try/catch is split into distinguishable stages (step 3a's own step 2):
`missingImagePath` (no `scanIdImagePathProvider` entry for this scanId), `missingStructuredRecognizer`
(`machineTextRecogniser` is not a `StructuredTextRecogniser`), `ocrException` (`recogniser
.readStructured` throws), `parserException` (`parseIdentityText` throws). All four happen strictly
BEFORE the network `ask()` call — none of them means a request ever reached the server, which is
the actual dividing line between this state and `REQUEST_FAILURE` below.

### 4.2a `RequestFailureReason` (present iff `state = REQUEST_FAILURE`)

**Confirmed 2026-09-16** against `cloud_equipment_identity_service.dart`'s real throw surface
(recon for the step 3a plan): `resolveFromText` can fail two structurally different ways after the
OCR/parse stages already succeeded: (a) the `httpsCallable(...).call(...)` itself throws — typically
`FirebaseFunctionsException` (network unreachable, timeout, App Check, auth, rate limit, backend
error — the file's own doc comment names these as "whatever `cloud_functions` throws"), meaning the
mobile client genuinely does not know whether the server ever received or processed the request; or
(b) the call SUCCEEDS (a reply was received) but `EquipmentIdentity.fromJson(result.data)` throws
`FormatException` — a decode failure of a reply that was, by definition, already sent by a server
that had already reached SOME terminal decision and, per this callable's own step-2 wiring, already
attempted to persist it as `SERVER_TERMINAL` before replying.

These two are handled identically at the STATE level (both are `REQUEST_FAILURE` — from the
client's perspective, neither produces a usable `EquipmentIdentity` to show or a confirmed
`SERVER_TERMINAL` outcome it can rely on) but are recorded as different reasons, and §6 rule 5
(above) is precisely what makes lumping the decode-failure case into `REQUEST_FAILURE` SAFE rather
than misleading: if the server's write already landed as `SERVER_TERMINAL`, a later
`REQUEST_FAILURE:malformedReply` mobile report can never downgrade or conflict it — it only
contributes metadata. Enum: `networkUnreachable | timeout | appCheckOrAuth | rateLimited |
backendError | unknownClientError | malformedReply` — the first six covering (a), the last covering
(b). `unknownClientError` is the catch-all for a `FirebaseFunctionsException`/other throw whose
code does not match a more specific bucket, so this enum never needs to enumerate every possible
`FirebaseFunctionsException.code` value to stay exhaustive.

### 4.2b `ENRICHMENT_DISABLED` — schema-reserved, deliberately NOT populated by step 3a

**Revised 2026-09-16** (GPT-PM MAJOR twice over, across two review rounds): the first finding was
that `equipmentIdentityProvider`'s own internal `if (!ref.watch(equipmentIdentityEnrichmentEnabledProvider))
return null;` branch is dead code in production — BOTH real callers (`scanner_page.dart:657`,
`workout_player_page.dart:189`) already gate the `ref.watch(equipmentIdentityProvider(...))` call
itself behind the same flag in the same ternary, so the provider is never even watched while the
flag is `false`. The second, more decisive finding: `equipmentIdentityEnrichmentEnabledProvider`'s
own doc comment documents a product/privacy guarantee — "OFF by default... a caller that watches the
family unconditionally must still get zero OCR and zero network calls while this reads false." Since
this flag is HARDCODED `false` everywhere today (no remote-config/per-user override exists yet), a
telemetry NETWORK call fired specifically because the flag is false would (a) contradict that
documented zero-network guarantee, and (b) fire on every single scan in the app for zero
per-scan signal — the value would be constant, not informative, for as long as the flag stays a
global off-switch.

**Decision: step 3a does NOT send `ENRICHMENT_DISABLED` telemetry over the network at all.** The
state stays defined in the schema (exactly like `NOT_ATTEMPTED`, which §4's own table already
accepts may simply never occur — "an unused enum value is not a defect; a missing one that later
occurs uncategorized would be"), reserved for whenever the flag becomes a real, variable, per-user
toggle worth measuring — a future gate's own decision, not this one's. This removes the need for any
scanner-level telemetry-staging/data-flow design for this one state, and removes the kill-switch
contract conflict entirely.

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
                           + count(state=SERVER_TERMINAL AND clientObservedFailures is non-empty)
```

**Revised 2026-09-16** (GPT-PM MAJOR, round 3): the third term is new. A record can be
`SERVER_TERMINAL` with an eligible `identityOutcome.decision` (e.g. `MATCH`) while `clientObservedFailures`
(§6 rule 5) shows the mobile client itself could never use that answer (a `malformedReply` decode
failure, or a late client-side timeout on a request the server ultimately completed). `state`/
`identityOutcome` stay untouched — the server's answer is still real and still counted toward
eligibility/resolution-rate/coverage (§5.1/§5.2/§5.5), because it genuinely happened — but this term
ALSO surfaces such a scan in `incomplete_evidence_count`, so a reader is never confidently silent
about the fact that the user's own device never actually saw a usable result for it. This is
additive (a record can now be counted by both the second and third terms if it independently
qualifies for each), not a replacement for the existing rule.

`incomplete_evidence_count` is reported ALONGSIDE every P2.G5 metric, never folded into or silently
subtracted from `eligible_scans`. Step 6(b)'s denominator-honesty test asserts this bucket is
non-zero and correctly populated when a deliberately broken/incomplete synthetic run is fed in.

### 5.4 Latency

`latency_ms = scanEndedAt - scanStartedAt`, computed only for records where both timestamps are
present (i.e. not `NOT_ATTEMPTED`/`ENRICHMENT_DISABLED`). `scanStartedAt` is the mobile-side scan
start (`scanner_page.dart:_classify`, §2 of the recon).

**Revised 2026-09-16** (GPT-PM BLOCKER, review of plan `fitness_app-2026-09-15T23-01-35-427Z-fd85bd`):
`scanEndedAt` was originally defined as the mobile-side `_scanAgain()` logical end-of-scan event.
That is wrong for this metric: `_scanAgain()` fires when the user, having ALREADY seen the result,
decides to start a NEW scan — that gap is dwell time (how long the user looked at the answer before
moving on), not wait time. It can be seconds or minutes after the pipeline actually finished, and it
does not fire at all for a scan the user simply abandons. `scanEndedAt` is now defined as **the
moment `equipmentIdentityProvider`'s own async attempt settles** — the same instant its `try` block
either returns a real `EquipmentIdentity` or its (now stage-classified, §4.2/§4.2a) `catch` runs —
`DateTime.now()` captured at that exact point, inside the provider itself, alongside the
state/reason it is already recording. This is the honest answer to "how long does the user wait for
an answer," is available immediately (no dependency on what the user does afterward), and is the
SAME event that already produces the LOCAL_FAILURE/REQUEST_FAILURE telemetry send (§6) — so this
fragment is now self-contained (state + reason + scanStartedAt + scanEndedAt, all known at once,
sent once, no partial/progressive send from this source). On the SUCCESS path, the same settle
instant produces a timing-only enrichment fragment instead (§6 rule 5), since the server has already
committed `SERVER_TERMINAL` by the time a successful client reply exists to act on.
`_scanAgain()`/fresh-scan supersession remain exactly what they always were — the
`scanIdImagePathProvider` cleanup events — with no telemetry role at all now.

**`scanStartedAt` source, revised 2026-09-16** (GPT-PM BLOCKER, round 3): no mint-time record of any
kind exists in mobile code today (`scanIdImagePathProvider` stores only `scanId -> path`, no
timestamp), and this gate does not add one. `scanStartedAt` is instead **parsed directly from the
`scanId` string itself** — `scanId` is minted as `'scan-${DateTime.now().microsecondsSinceEpoch}'`
(`scanner_page.dart:495`), so the mint instant is already durably encoded in the id every fragment
already carries; no new mobile state, no `scanner_page.dart` changes, needed. A retry reuses the
SAME `scanId` (`isRetry && _currentScanId != null`), so a parsed `scanStartedAt` on a retry correctly
still reads as the ORIGINAL attempt's start, which is the right answer for "how long has this scan
attempt, across retries, been going."

**Timestamp provenance and validation, revised 2026-09-16** (GPT-PM MAJOR, round 3; upper bound
REMOVED, GPT-PM MAJOR, round 4): both timestamps are produced with
`DateTime.now().toUtc().toIso8601String()` (never bare `DateTime.now()` — Dart's
`toIso8601String()` omits the `Z`/offset suffix for a non-UTC `DateTime`, which a strict RFC3339
server-side validator must reject) — client-device-clock-sourced, documented as such, never treated
as an authoritative time source elsewhere. The server contract-boundary schema validates strict
RFC3339 and rejects `scanEndedAt < scanStartedAt` — **no upper bound on the gap**. Round 3 proposed
a 15-minute ceiling; round 4 correctly rejected it: `scanId` is reused across a retry
(`isRetry && _currentScanId != null`, `scanner_page.dart`), which the app itself treats as "the same
scan attempt" with NO time boundary — a user can leave the screen open and retry an hour later, and
that is still, honestly, how long this scan attempt took. Rejecting the long tail would silently bias
§5.4's latency metric toward only its fast cases, which is exactly the kind of "no silent drop"
violation §4.3.2 already refuses to accept for outcome counts. A record legitimately reflecting a
long gap is real evidence, not a data-quality defect; there is nothing else in this design that would
benefit from an arbitrary duration ceiling, so none is added.

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

**Revised 2026-09-16** (GPT-PM BLOCKER, review of the original step 3a plan,
`fitness_app-2026-09-15T22-49-23-311Z-616bf0`, rejected before GO): the original 4 rules below
never defined what happens when a SERVER-authored fragment and a MOBILE-authored fragment arrive
independently for the same `{uid, scanId}` — step 2 only ever wrote `SERVER_TERMINAL`, so rules
3/4 were validated only for server-only writes. Step 3a introduces the first MOBILE-originated
writes, so this section now also fixes, structurally, WHO may write WHAT:

**Authority split, enforced at the contract boundary (Zod discriminated union), not just by
convention:** a mobile client may only ever submit `state IN {ENRICHMENT_DISABLED, LOCAL_FAILURE,
REQUEST_FAILURE}`. `SERVER_TERMINAL` is written exclusively by the server's own identity-resolution
path (unchanged from step 2); `CONFLICT` is written exclusively by this repository's own merge
logic below, never accepted as an incoming state from any caller. This makes rules 4/5 below
structurally exhaustive rather than convention-only: a client-submitted write can never itself be
`SERVER_TERMINAL`/`CONFLICT`, so the "two independently-arriving terminal writes disagree" case
rule 4 protects against can now only ever originate from the server's own path (e.g. a genuine
re-resolution), never from mobile.

On each write attempt for `{uid, scanId}`:

1. If no record exists yet: create it (`state`, all applicable outcome fields, `payloadFingerprint`).
2. If a record exists and the incoming write's `payloadFingerprint` matches the stored one exactly:
   **no-op** — update only `updatedAt`, change nothing else. This is what makes a retried delivery
   (outbox retry, step 3b) safe to replay any number of times.
3. If a record exists, its `state` is one of the MOBILE-authoritative non-terminal states
   (`ENRICHMENT_DISABLED`, `LOCAL_FAILURE`, `REQUEST_FAILURE`) and the incoming write's
   `payloadFingerprint` differs: this is a legitimate transition, not a conflict — overwrite.
   **Revised 2026-09-16** (GPT-PM BLOCKER + MAJOR, round 3): the REPLACED fragment's full
   `{state, reason, recordedAt}` — not just its state name — is appended to `clientObservedFailures`
   (defined under rule 5 below; introduced here first since this is the first rule that needs it).
   This makes BOTH arrival orders symmetric: a mobile fragment superseded by a later genuine
   `SERVER_TERMINAL` (this rule) preserves the same full detail that rule 5 already preserves when
   `SERVER_TERMINAL` arrives FIRST and a mobile fragment arrives late. `priorStates` (bare
   `{state, recordedAt}`, no reason) remains for the mobile-to-mobile sub-case specifically, as a
   lighter-weight trail of "this scanId's mobile-side state changed over time" independent of the
   full-detail audit `clientObservedFailures` provides. This covers every arity: a mobile retry that
   lands in a DIFFERENT mobile-authoritative state than its predecessor (`LOCAL_FAILURE` then
   `REQUEST_FAILURE`); a retry that lands in the SAME state with a DIFFERENT reason (two
   `REQUEST_FAILURE` attempts, `timeout` then `backendError` — the fingerprint still differs because
   the reason differs, so this rule applies identically; A→B→C is simply this rule applied twice in
   sequence, each replacement individually recorded); and a mobile-authoritative state superseded by
   a genuine `SERVER_TERMINAL` resolution.
4. If a record exists, IS already terminal (`SERVER_TERMINAL` or `CONFLICT`), and the incoming
   write is ALSO a state-defining write whose `payloadFingerprint` differs — structurally only
   possible from the server's own path now, per the authority split above: **do not overwrite**.
   Transition to `state = CONFLICT`, preserve the original terminal record's fields under
   `conflictingWrites: [...]` rather than losing either version. `CONFLICT` records are excluded
   from every §5 formula except `incomplete_evidence_count`.
5. If a record exists, IS already terminal (`SERVER_TERMINAL` or `CONFLICT`), and the
   incoming write is a MOBILE-authoritative fragment: this is **not** a conflict. The server's
   terminal answer is authoritative and is never overwritten or downgraded by a client report that,
   by construction, cannot know whether the server ultimately succeeded. Instead, **enrich only the
   metadata fields the server-side write could never have supplied** — `scanStartedAt`/`scanEndedAt`,
   filled in only if not already set on the existing record (first-write-wins per field).
   `state`/`identityOutcome` are never touched. Two shapes of mobile-authoritative fragment can reach
   this rule:
   - A `LOCAL_FAILURE`/`REQUEST_FAILURE` fragment (e.g. a `REQUEST_FAILURE: malformedReply`
     observation that raced a server response which actually completed and committed
     `SERVER_TERMINAL` first): its own `{state, reason, recordedAt}` is additionally appended to a
     `clientObservedFailures: [...]` audit array (shape `{state, reason, recordedAt}`,
     unbounded-by-formula like `priorStates`/`conflictingWrites` — kept for debugging/data-quality
     review, and see §5.3 for its ONE formula effect). This is how a real client-observed delivery
     failure stays on the durable record even when it is not the record's authoritative outcome. A
     repeat of the SAME `clientObservedFailures` entry (identical fingerprint) is a no-op (extends
     rule 2's idempotency to this array, same as `conflictingWrites` already does).
   - **New 2026-09-16** (GPT-PM MAJOR, round 3): a **timing-only enrichment fragment** — no `state`
     at all, just `{scanId, scanStartedAt, scanEndedAt}` — sent from `equipmentIdentityProvider`'s
     OWN success path, immediately after a `MATCH`/other terminal decision returns. Necessary because
     the server's resolve callable (step 2) already commits `SERVER_TERMINAL` synchronously, BEFORE
     replying to the client — by the time the client can send anything at all on a successful path,
     the record is already terminal, so this fragment always lands here, never at rule 1/2/3. Without
     it, §5.4's latency metric would have zero data from any `SERVER_TERMINAL`/`MATCH` record — the
     only records that ever get real mobile timestamps would be exactly the ones §5.1 excludes from
     eligibility. This fragment carries no reason/state to preserve, so it touches only
     `scanStartedAt`/`scanEndedAt`, first-write-wins, same as above.

This mirrors, server-side, the exact semantic `equipment_identity_outcome_sink.dart` already
implements client-side in memory (`core/DECISION_LOG.md:50843-50861`) — the same rule, applied at
the durable layer that step 2 is adding, now extended to a second, independent writer.

## 7. Open items step 2/3 must resolve before code, not after

1. **Resolved 2026-09-16** — see §4.2: the four `LocalFailureReason` branches confirmed 1:1 against
   `equipment_identity_providers.dart`.
2. **Resolved 2026-09-16** — `ENRICHMENT_DISABLED` genuinely exists (`equipmentIdentityEnrichmentEnabledProvider`,
   hardcoded `false` today — the whole surface is off by default) but is unreachable from the
   provider's OWN internal branch in production; see §4.2b for the real-caller-site fix step 3a
   must apply. The state stays in the schema.
3. **Resolved 2026-09-16** — see §4.2a: `RequestFailureReason`'s real value set, confirmed against
   `cloud_equipment_identity_service.dart`, including the `malformedReply` case §6 rule 5 makes safe.
4. **Resolved 2026-09-16, deferred rather than closed**: `genericOutcome` (§4.1, "always recorded,
   independent of identity state") is captured on a SEPARATE async timeline from the identity
   pipeline (`scanner_page.dart`'s `_classify()` knows it, from `result.outcome`, a `ScanOutcome`
   matching `GenericScanOutcomeSchema` exactly — but only after `classifyFilePath` resolves, on its
   own schedule relative to `equipmentIdentityProvider`'s independent settle). Wiring a second,
   independent mobile-originated fragment source for just this one field was the direct cause of
   BLOCKER 1 in GPT-PM's review of `fitness_app-2026-09-15T23-01-35-427Z-fd85bd` (undefined
   same-mobile-state progressive-enrichment merge semantics). Given `genericOutcome` is not
   load-bearing for any §5 formula on a `LOCAL_FAILURE`/`REQUEST_FAILURE` record specifically (only
   `SERVER_TERMINAL` records feed §5.1-§5.2/§5.5; `LOCAL_FAILURE`/`REQUEST_FAILURE` only ever feed
   `incomplete_evidence_count`, §5.3, which `genericOutcome` does not affect either way), step 3a
   explicitly DEFERS populating `genericOutcome` on mobile-authoritative records to step 3b, where a
   real cross-fragment merge mechanism is being built anyway for durability. `genericOutcome` stays
   `null` on every record step 3a itself writes — disclosed here rather than silently dropped.
5. **Resolved 2026-09-16**: see §5.4's revision — `scanEndedAt` is now the identity pipeline's own
   settle instant (captured inside `equipmentIdentityProvider` itself, at the same point as the
   state/reason it already records), not `_scanAgain()`/fresh-scan supersession. Both original
   concerns (GPT-PM's "dwell time, not wait time" correction, and "`_classify()`'s own supersession
   is a second real end-event `_scanAgain()` alone missed") are moot under this definition: there is
   only one send, self-contained, at one well-defined instant, per identity-pipeline attempt — no
   deferred/partial send, no second end-event to track.
6. `functions-equipment-identity` test commands, confirmed: `npm test` (jest, unit), `npm run
   test:e2e` (emulator-backed, `functions-equipment-identity/package.json:9-10`). Rules tests run
   separately: `npm --prefix functions run test:rules` (comment header,
   `functions/src/__rules__/firestore_rules.test.ts:16`).
7. Legal-text pipeline, confirmed: canonical source is `scripts/legal/legal_text.py`, generator is
   `scripts/legal/build_legal.py` (`legal_text.py:12-14`: "`build_legal.py` is the generator").
   Current claim to preserve/extend accurately: `legal_text.py:201-202` — "No advertising
   identifier is collected, and no third-party analytics or attribution SDK is built into the
   app." This telemetry is first-party Firestore, consistent with that claim; step 4's legal-text
   update must describe the new collection without contradicting it.
8. No existing Admin-SDK report/admin script was found anywhere under `scripts/` (grepped for
   `firebase-admin`/`admin.initializeApp` — zero matches) — step 5's operator-only report script is
   new work, not an extension of an existing one.
