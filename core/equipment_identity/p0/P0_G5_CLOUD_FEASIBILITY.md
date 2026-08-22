# P0.G5 — Cloud feasibility, IAM, region & SDK spike

Status: CLOSED, outcome **OCR_TEXT_ONLY_DEFER_VISUAL** (pending push/remote-sync
verification — see §7 below).

Purpose (per `SPTR_EQUIPMENT_RECOGNITION_V4_4_GATE_CONTRACTS_AND_AC_DOD_2026-08-22.md`
P0.G5): prove the preferred Firebase/Vertex/Firestore vector path fits the
actual project — region is a fixed input, not an open architecture choice.
This is a feasibility spike, not P4 implementation. Story AC, verbatim:
"exactly one of three outcomes is recorded with evidence — colocated,
deliberately split-region with a measured latency budget, or stay
OCR/text-only — and no outcome moves or duplicates the existing region for
already-deployed payment/account functions."

Every claim below is labeled `FACT` (directly observed), `MEASURED` (a
command run against real state), `NOT_ATTEMPTED` (deliberately not run, with
the reason), `BLOCKED_EXTERNAL` (cannot be resolved from inside this
session), or `DECISION` (a choice made on the evidence above it). No prose
in this document turns a `NOT_ATTEMPTED` into a `PASS`.

## 1. Fixed facts re-measured (per §10.1 of the implementation plan)

| Fact | Value | Label |
|---|---|---|
| Existing Cloud Functions region | `europe-west1` | `FACT` — `functions/src/scaling.ts:70`, unchanged by this gate |
| Firestore location | `eur3`, `FIRESTORE_NATIVE` | `MEASURED` — `gcloud firestore databases describe --project=fitness-app-korostelev` |
| Functions runtime | Node 20 | `FACT` — `functions/package.json` `engines.node` |
| `firebase-functions` version | `^6.0.0` | `FACT` — `functions/package.json` |
| `firebase-admin` version | `^12.6.0` | `FACT` — `functions/package.json` |
| Functions codebase declaration | single `"default"` entry | `FACT` — `firebase.json` |

`stripeWebhook`'s region/URL was not touched — no file under `functions/`
was modified by this gate.

## 2. Safe non-production project check (the actual gating question)

**`BLOCKED_EXTERNAL` / `DECISION`-driving fact**: no safe non-production
Firebase/GCP project exists for this app.

- `MEASURED` — `.firebaserc` declares exactly two aliases: `default` →
  `fitness-app-korostelev` (the same project `stripeWebhook` runs in — the
  live production project) and `legacy-shared` → `traidingbot-b4061`, a
  completely different, unrelated application (a trading-bot repo, not a
  staging copy of this app). Neither is a usable non-production
  environment for this app.
- `MEASURED` — `gcloud auth list`: the active account is the project's
  default Firebase Admin SDK service account (production, with write
  access to the live project), plus the operator's own Google account. No
  non-production service account or project is configured. (This repo is
  public; the exact service-account email and personal account address are
  deliberately not printed here — per `security-reviewer`'s P0.G5 review
  round, naming the production admin identity verbatim in a public,
  committed file hands a would-be attacker an exact target for phishing or
  IAM-impersonation probing with no corresponding benefit to this
  document's purpose.)
- `MEASURED` — `gcloud projects list` (under the currently active
  credentials) returns exactly one project: `fitness-app-korostelev`.

Per the gate's own real-probe policy (§10.4 of the implementation plan):
"Cloud network probing is allowed only when it is safely observable/
reversible… Determine whether an already-configured NON-PRODUCTION
Firebase/GCP project exists. If yes… perform applicable real probe." The
answer here is a clean, verified no. Running any Firestore KNN write, a
temporary vector index creation, or a Vertex embedding call under these
credentials would touch the production project by construction — not a
"staging" probe in any sense the gate's own safety policy permits.

## 3. Secondary finding: platform-lifecycle risk (not a hard blocker on its own)

`FACT` (WebSearch/WebFetch, 2026-08-22) — Google's Vertex AI generative-AI
documentation set now banners "Vertex AI documentation is no longer being
updated," redirecting to a newer "Gemini Enterprise Agent Platform" surface.
A search result stated the older, high-level Python Vertex AI SDK's
`vertexai.vision_models` module (not the underlying Prediction API, and not
the Node `@google-cloud/aiplatform` client this project would actually use)
was deprecated 2026-06-24. `multimodalembedding@001` itself remains
documented with a stated 2027-04-01 retirement date, and the underlying
`aiplatform.googleapis.com` API remains current per what was fetchable.

This was independently reviewed with GPT-PM before being recorded (PM
Bridge exchange, 2026-08-22) to avoid overclaiming — the first-pass reading
of this evidence ("the model/SDK is already unavailable") was corrected:
the model is not dead, but the design's specific SDK-version assumptions
are stale enough to need re-verification whenever this gate is reopened.
**This finding does not independently force `OCR_TEXT_ONLY_DEFER_VISUAL`**
— §2's blocker already does that on its own — but it is recorded as a
second, independent reason not to pin a provider SDK choice right now.

## 4. Probes — all `NOT_ATTEMPTED`, by design

| Probe | Status | Reason |
|---|---|---|
| Firestore KNN real staging proof (T1) | `NOT_ATTEMPTED` | No safe non-production project (§2). Per the gate's own conditional-task correction (AC-M01), T1 only runs "if (a)/(b) remain viable after T0" — they do not. |
| Vertex embedding probe (T1) | `NOT_ATTEMPTED` | Same reason. |
| App Check callable probe (T2) | `NOT_ATTEMPTED` | Same reason; P0.G0 (external platform migration) also remains independently blocked/external and is out of this gate's scope. |

No probe touched production. No new IAM role was granted. No billing was
activated. No production App Check enforcement state was changed.

## 5. Cost / IAM evidence (§10.6)

- Cost: `UNKNOWN` by design — no cost estimate is recorded, because no
  provider/model/region combination was selected (§6). Per the
  implementation plan: "If chosen outcome requires a known cost to close
  and cost cannot be established: do not use that outcome; choose the
  fail-closed text-only path." That is exactly what happened here.
- IAM: `PARTIAL` assessment. `FACT` — the one accessible project's active
  credentials are a production admin-SDK service account, which is
  over-privileged for what a real staging KNN/Vertex spike would need
  (least-privilege staging roles were never defined, since no staging
  project exists to define them against). No new production role was
  requested or granted by this gate.
- Data residency: `DECISION` — no new residency decision was made or
  needed. Firestore stays `eur3`; `europe-west1` stays the Functions
  region. Nothing in this gate moved or duplicated the existing region for
  `stripeWebhook` or any other already-deployed function.

## 6. Outcome decision

**`DECISION`: OCR_TEXT_ONLY_DEFER_VISUAL.**

Per §10.5(C) of the implementation plan, this is "the fail-closed,
reversible P0.G5 closure when visual cloud feasibility cannot be proven
under currently authorized constraints." Explicitly, per that same
section: this is **not** "visual feature cancelled." It means:
- OCR/text P1/P2 work may continue unaffected.
- P4 (visual retrieval) is not activated from this evidence — no provider,
  model, or region was selected or pinned (`providerSelectionStatus:
  DEFERRED_NO_SAFE_STAGING` in `p0_g5_probe_result.json`).
- P0.G5 may later be deliberately reopened once a safe non-production
  project exists, with current platform evidence re-verified at that time
  rather than trusted from this gate's snapshot.

`COLOCATED_VECTOR_FEASIBLE` was not reachable: it requires a genuinely
`PASS`ing Firestore KNN probe and Vertex embedding probe (§10.5(A)), and
neither could be safely attempted (§2). `SPLIT_REGION_REQUIRES_OPERATOR`
was not chosen either: nothing in the evidence gathered shows Vertex
*requires* a materially different region from `europe-west1`/`eur3` — the
blocker is the absence of a safe place to test, not a proven region
mismatch. Recording `SPLIT_REGION` would have overclaimed a fact not in
evidence.

This decision was reached jointly with GPT-PM via PM Bridge (2026-08-22,
full exchange referenced in `core/DECISION_LOG.md`), which independently
confirmed: "PRIMARY BLOCKER TO VISUAL FEASIBILITY PROOF: No authorized/safe
non-production Firebase/GCP project exists" is independently sufficient to
force this outcome, and recommended the package below install no
provider SDK at all while this outcome stands.

## 7. What was built

| File | Role |
|---|---|
| `functions-equipment-identity/` (new package: `package.json`, `package-lock.json`, `tsconfig.json`, `jest.config.js`, `.gitignore`, `src/index.ts`, `src/p0/cloud_feasibility.ts`, `src/__tests__/cloud_feasibility.test.ts`) | Isolated feasibility package per P0.G6's already-chosen strategy (separate codebase) — not yet wired into `firebase.json`; that wiring is P0.G6's own scope. |
| `core/equipment_identity/p0/p0_g5_probe_result.json` | The recorded `P0CloudFeasibilityResult` for this closure. |
| `core/equipment_identity/p0/P0_G5_CLOUD_FEASIBILITY.md` | This document. |

`src/index.ts` exports nothing (`export {}`) — no production identity
Cloud Function exists yet. Dependencies are deliberately minimal:
`firebase-admin`/`firebase-functions` only (matching the default `functions/`
package's versions). **`@google-cloud/aiplatform` and `@google-cloud/firestore`
were deliberately NOT installed** — per the GPT-PM exchange above, pinning a
provider SDK now would lock in an unverified architecture without
producing any real gate evidence, and would leave a stale lockfile choice
for whichever future session reopens P0.G5 for real visual work.
`package-lock.json` was generated by a real `npm install` (498 resolved
packages) — no hand-authored lock entries.

`cloud_feasibility.ts`'s `P0CloudFeasibilityResult` type has no boolean
`cloudWorks` field — only three-way probe status
(`NOT_ATTEMPTED`/`PASS`/`FAIL`) can express "we have no evidence" without
lying about it. `assertValidP0CloudFeasibilityResult` enforces (among other
invariants): `COLOCATED_VECTOR_FEASIBLE` requires every required probe to
be a genuine `PASS` (never `NOT_ATTEMPTED`, so credential/environment
absence can never silently become a pass); `SPLIT_REGION_REQUIRES_OPERATOR`
always requires `providerSelectionStatus: REQUIRES_OPERATOR_DECISION` and
at least one recorded blocker; `OCR_TEXT_ONLY_DEFER_VISUAL` must never
carry a selected embedding provider/model/dimension; and a cheap
secret-pattern scan refuses to validate a result whose evidence/blockers/
cost fields look like a live API key, OAuth token, or private key block.

## 8. Tests run

```
npm --prefix functions-equipment-identity run build
npm --prefix functions-equipment-identity test
28 passed
```

Covers every case §10.8 of the implementation plan named: result schema
accepted when well-formed; an impossible mixed state (unknown
outcome/probe-status/providerSelectionStatus/iamAssessment value) rejected;
`COLOCATED_VECTOR_FEASIBLE` cannot be returned with a required probe
`FAIL`; `SPLIT_REGION` always flagged as an operator decision (and
rejected without a recorded blocker); `OCR_TEXT_ONLY_DEFER_VISUAL` can
close with every visual probe still `NOT_ATTEMPTED`; credential/
environment absence cannot become `PASS` by omission; no secret-looking
string may be recorded. Two additional cases beyond the minimum list: the
actual committed `p0_g5_probe_result.json` is loaded and asserted valid
under the module's own invariants, so the evidence file and the code that
defines what a valid file looks like cannot silently drift apart; and a
dedicated structural suite (`no_production_calls.test.ts`) greps every
non-test source file for a Google Cloud SDK import or a raw network call
and asserts `index.ts` still exports nothing — turning "no probe was
attempted" from a prose claim into something a future regression would
fail loudly on, added during the review round (§9).

## 9. Review record (P0.G5)

Reviewers per the gate's own implementation plan: `security-reviewer`,
`database-reviewer`, `silent-failure-hunter` — all three confirmed
available in this session (no substitution needed, unlike prior P0
gates' project-scoped reviewers). Questions: are we confusing lack of
evidence with feasibility? Did any probe touch production? Did we
introduce unnecessary permissions? Did we silently change data residency?
Can outcome C genuinely close under the final AC/DoD? Is visual P4
correctly gated from false-positive feasibility?

**BLOCKER (`silent-failure-hunter`) — `iamAssessment` was never validated
against its own enum or cross-checked against outcome.** A result with a
made-up `iamAssessment` string passed silently, and — the exact scenario
named — `COLOCATED_VECTOR_FEASIBLE` with both probes `PASS` but
`iamAssessment: "UNKNOWN"` also passed: "this cloud path works but we have
no idea what permissions let it pass" was a valid record. **Verified** by
reading `assertValidP0CloudFeasibilityResult` directly — confirmed
`iamAssessment` was never referenced anywhere in the function body.
**Fixed**: added an `IAM_ASSESSMENTS` membership check, plus a requirement
that `COLOCATED_VECTOR_FEASIBLE` cannot record `iamAssessment: UNKNOWN`.

**MAJOR x4 (`silent-failure-hunter`), all independently verified against
the code before being fixed:**
- `OCR_TEXT_ONLY_DEFER_VISUAL` never checked `providerSelectionStatus`,
  so a result claiming visual is simultaneously "deferred" and
  `SELECTED_AND_PROBED` passed. Fixed: that outcome now requires
  `providerSelectionStatus !== "SELECTED_AND_PROBED"`.
- `blockers: []` was legal under `OCR_TEXT_ONLY_DEFER_VISUAL` — "deferred"
  with zero recorded reason passed, even though a real named blocker is
  the entire premise of this gate's own outcome (§2/§6). Fixed: that
  outcome now requires at least one recorded blocker, mirroring the
  existing `SPLIT_REGION` check.
- `vertexLocationTested` was never cross-checked against
  `vertexEmbeddingProbe` — a result could claim a region was "tested"
  while the probe that would have tested it was `NOT_ATTEMPTED`. Fixed:
  `vertexLocationTested` must be `null` unless `vertexEmbeddingProbe` is
  not `NOT_ATTEMPTED`.
- No structural guarantee existed against a future real SDK-call
  regression — the "no production touched" claim was prose-only, and a
  future PR adding a real Vertex/Firestore call would compile and pass
  every existing test while silently contradicting the doc. Fixed: a new
  `no_production_calls.test.ts` greps every non-test source file for a
  Google Cloud SDK import or a raw `fetch`/`https.request` call, and
  asserts `index.ts` still exports nothing.

**MINOR (`silent-failure-hunter`) — `COLOCATED_VECTOR_FEASIBLE` didn't
require `appCheckCallableProbe: PASS`**, only the two vector-path probes,
even though the gate's own task table (T2) expects the App Check probe to
run and pass under outcomes (a)/(b). Fixed: added to the `COLOCATED`
required-probe list.

**MINOR (`database-reviewer`) — `COLOCATED_VECTOR_FEASIBLE` never required
`firestoreSdkVersion`/`vertexSdkVersion` to be recorded**, so a future real
`PASS` could lose exactly the "which SDK version was actually tested" fact
needed to reproduce or re-verify the result later. Fixed: both fields are
now required non-null under that outcome.

**MINOR x2 (`database-reviewer`, forward-looking, not fixed now — both
explicitly flagged as "not a fix-now item" by the reviewer):** the
three-way `ProbeStatus` enum can't express a probe that started but timed
out or passed with a caveat (e.g. a Firestore vector index still
building); and the doc could note `firestore.indexes.json` currently has
zero indexes and a future vector index is a distinct, dimension-locked
type. Both are genuine considerations for whoever reopens P0.G5 for a real
staging probe, not gaps in this gate's own honest-record contract — left
as documented forward guidance rather than speculative code changes now.

**MINOR (`security-reviewer`) — the production Admin SDK service-account
email and the operator's personal Google account were both being recorded
verbatim in this gate's committed, PUBLIC-repo evidence files.** Project
IDs alone are routinely public (embedded in the shipped client app), but
naming the exact production service-account identity hands a would-be
attacker a specific phishing/IAM-impersonation target with no benefit to
this document's actual purpose. **Fixed**: both `P0_G5_CLOUD_FEASIBILITY.md`
and `p0_g5_probe_result.json` now describe the account generically ("the
project's default Firebase Admin SDK service account," "the operator's own
Google account") instead of printing the literal addresses.

**NIT (`security-reviewer`) — `SECRET_LOOKING_RE`'s pattern set (API key /
OAuth token / PEM private-key header) is adequate for this module's own
narrow use (only ever records hand-authored evidence strings) but would
miss GitHub/Slack/AWS token shapes and generic high-entropy blobs if ever
reused as a general secret scanner elsewhere.** Not fixed — reviewer
explicitly stated this is not required for the current, narrow use;
recorded here so a future reuse of this pattern doesn't assume more
coverage than it has.

Everything else each reviewer checked came back clean: no live network
call, Firestore write, or index creation anywhere in the new code (now
also mechanically enforced, not just observed); `.gitignore` correctly
excludes `.env`/`.env.*`/`node_modules`/`lib`; no credential-shaped string
in any new file; `functions-equipment-identity` confirmed absent from
`firebase.json`'s `functions` array; test/build paths are fully
synchronous with no swallowed exceptions. No unresolved BLOCKER/MAJOR
after fixes.

All fixes verified: `npm --prefix functions-equipment-identity test` → 28
passed (18 original + 10 regression/new).

## 10. Close conditions (P0.G5 §10.10)

- [x] One allowed outcome is explicit: `OCR_TEXT_ONLY_DEFER_VISUAL` (§6).
- [x] All AC/DoD conditions for that outcome satisfied: T0 (decision
      evidence, §2-§6) and T3 (outcome recorded with evidence) are the only
      required tasks under outcome C; T1/T2 are conditional and correctly
      skipped with a recorded reason (§4), not incorrectly required.
- [x] Rollback/failure handling recorded (§11).
- [x] Reviewers: no unresolved BLOCKER/MAJOR — three independent reviewers
      ran (one BLOCKER + four MAJOR + three MINOR found and fixed, two
      MINOR accepted as forward-looking, one NIT accepted as-is; §9).
- [ ] Commit pushed/synced — pending, see the close-out step below.

## 11. Rollback / failure handling

Per the gate contract's own rollback mode: "Stay OCR/text-only and
postpone visual retrieval (unaffected by P6-T)." That is the outcome this
gate actually chose, not a fallback from a failed attempt — nothing needs
to be rolled back. If P0.G5 is reopened later with a real staging project:
`providerSelectionStatus` moves from `DEFERRED_NO_SAFE_STAGING` toward
`SELECTED_AND_PROBED` (or `REQUIRES_OPERATOR_DECISION` if a real region
split is found) only once genuine `PASS`/`FAIL` probe evidence exists —
`assertValidP0CloudFeasibilityResult` mechanically refuses any record that
tries to claim `COLOCATED_VECTOR_FEASIBLE` without it.
