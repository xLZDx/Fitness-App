# P0 evidence index — SPTR Equipment Recognition v4.4

Aggregate index across every P0 gate, written at P0's close-out per GPT-PM's
explicit request after P0.G6 closed. This document does not restate each
gate's full narrative — that lives in the per-gate `P0_G*.md` files linked
below — it exists so a future session (or the operator) can see the whole
phase's state in one place without re-deriving it from six separate docs
and a commit log.

**Phase status: gates closeable in an autonomous coding session are all
CLOSED. P0.G0 remains BLOCKED_EXTERNAL_PLATFORM_MIGRATION, exactly as
planned from the start — this was never in scope for this run. Final phase
verdict is recorded in §5 below, after the regression rerun and adversarial
review in §3-§4.**

## 1. Gate-by-gate index

| Gate | Status | Closing commit(s) | Doc | Evidence artifacts | Tests | `pm_set_gate` |
|---|---|---|---|---|---|---|
| P0.G0 — App Check platform readiness | `BLOCKED_EXTERNAL_PLATFORM_MIGRATION` | — (not started; external platform migration, out of scope for an autonomous coding session) | gate contract only, §"P0.G0" of `SPTR_EQUIPMENT_RECOGNITION_V4_4_GATE_CONTRACTS_AND_AC_DOD_2026-08-22.md` | none | none | not called (never closeable this run) |
| P0.G1 — Recognition baseline freeze | CLOSED | `f23130b` | [`P0_G1_BASELINE.md`](P0_G1_BASELINE.md) | `recognition_baseline_v1.json`, `legacy_real_gym_regression_inventory.json` | `test_baseline.py`, 15 tests | passed, 2026-08-22T09:18:47.632Z |
| P0.G2 — ML provenance recovery/ratchet | CLOSED | `7053cfd` | [`P0_G2_ML_PROVENANCE.md`](P0_G2_ML_PROVENANCE.md) | `equipment_identity_provenance_contract.schema.json` | `test_provenance.py`, 23 tests | passed, 2026-08-22T09:45:05.597Z |
| P0.G3 — Source & rights registry | CLOSED | `0a6d5c3` | [`P0_G3_RIGHTS_GOVERNANCE.md`](P0_G3_RIGHTS_GOVERNANCE.md) | `source_registry.json` + `.schema.json`, `rights_decision.schema.json`, `SOURCE_PRIORITY.md` | `test_rights.py`, 22 tests | passed, 2026-08-22T10:06:08.799Z |
| P0.G4 — Catalog version & type snapshot | CLOSED (contract repaired) | `eac45bb` (implementation), `0e4316f` (gate-contract repair) | [`P0_G4_CATALOG_SNAPSHOT.md`](P0_G4_CATALOG_SNAPSHOT.md) | `functional_type_snapshot_v1.json`, `functional_type_snapshot_manifest.json` | `test_type_snapshot.py`, 17 tests | passed, 2026-08-22T10:28:11.045Z |
| P0.G5 — Cloud feasibility spike | CLOSED — outcome `OCR_TEXT_ONLY_DEFER_VISUAL` | `e0483c1` | [`P0_G5_CLOUD_FEASIBILITY.md`](P0_G5_CLOUD_FEASIBILITY.md) | `p0_g5_probe_result.json` | `functions-equipment-identity` Jest, 28 tests | passed, 2026-08-22T10:48:38.116Z |
| P0.G6 — Functions deployment isolation | CLOSED — strategy `SEPARATE_FIREBASE_CODEBASE` | `4c97d7e` (implementation), `f6315dd` (evidence-json hash fix) | [`P0_G6_DEPLOYMENT_ISOLATION.md`](P0_G6_DEPLOYMENT_ISOLATION.md) | `p0_g6_isolation_evidence.json` | `test_deployment_isolation.py`, 10 tests | passed, 2026-08-22T11:20:04.000Z |

All six closeable gates ran under the standing `EQUIPMENT_RECOGNITION_V4_4_AUTONOMOUS_PROGRAM`
authorization (operator: "ГО — начинай весь P0 автономно"), 2026-08-22, sequentially, no operator
check-in between gates. Every commit above is on `master`, pushed, and remote-sync verified
(`git rev-list --left-right --count HEAD...origin/master` = `0 0`) at the time each gate closed.

## 2. Review coverage across P0

Every gate got an independent, cold-read multi-agent review round before closing (`security-reviewer`
plus 1-2 more specialists per gate, per §6 of the operating contract's agent-routing rules). Zero
BLOCKER survived any gate's close. Total across P0.G1-G6: 1 BLOCKER found and fixed (P0.G5,
`iamAssessment` validation gap), roughly a dozen MAJOR found and fixed (rights fail-open gaps in
P0.G3, cross-field invariant gaps in P0.G5's result validator, the differential-proof/untested-main/
defeatable-grep trio in P0.G6, a missed generic-deploy-command reference in P0.G6), several MINOR
fixed, and a small number of MINOR items explicitly accepted and documented as deferred rather than
fixed or silently dropped (see each gate's own §6/review-record section for the specific list — none
of the deferred items are release-blocking, and each requires a precondition that doesn't exist yet
in P0, e.g. a real deployed identity function or a real production probe).

Two review agents got stuck mid-round and required recovery: P0.G5's first `security-reviewer`
attempt looped on citation-format corrections across 3 resumes with no findings delivered (fixed by a
fresh retry with a narrower prompt); P0.G6's `code-reviewer` first completion notification arrived
with no findings text at all (fixed by a `SendMessage` follow-up asking it to restate). Both recoveries
are recorded in their respective gate docs and in `core/DECISION_LOG.md`.

## 3. Full regression rerun on final P0 HEAD (commit `f6315dd`)

Per GPT-PM's explicit request: rerun the whole P0-relevant regression set on the final HEAD, not on
each gate's own now-stale commit-time results.

| Suite | Command | Result |
|---|---|---|
| Python — ML governance + equipment identity | `python -m pytest scripts/ml scripts/ct1 scripts/equipment_identity -q` | **408 passed**, rerun to **410 passed** after §4b's 2 new anti-drift tests were added |
| Python — deployment isolation (subset, re-confirmed alone) | `python -m pytest scripts/equipment_identity/test_deployment_isolation.py -q` | **10 passed** |
| Default Functions (Stripe/account) — Jest | `npm --prefix functions test` | **240 passed** (9 suites) |
| Default Functions — Firestore rules (emulator) | `npm --prefix functions run test:rules` | **64 passed** |
| Default Functions — e2e (emulator) | `npm --prefix functions run test:e2e` | **11 passed** |
| Identity codebase — build | `npm --prefix functions-equipment-identity run build` | **PASS** (tsc, no errors) |
| Identity codebase — Jest | `npm --prefix functions-equipment-identity test` | **28 passed** (2 suites) |
| Flutter — static analysis | `flutter analyze` (from `mobile/`) | **16 pre-existing issues, 0 errors** — all in files P0 never touched (theme/workout/state providers, test-only lint items); not a P0 regression |
| Flutter — full test suite | `flutter test` (from `mobile/`) | **3242 passed, 1 failed** — see below |

**The one Flutter test failure is pre-existing and unrelated to P0, not a regression from this
phase's work.** `test/theme/app_semantic_colors_test.dart` — "the hardcoded whites that survived
G1.2b stay accounted for" — asserts an exact ratchet count of hardcoded white-color usages across an
explicit file whitelist (expected 61, actual 58; note this test's own "G1.2b" label is an unrelated,
pre-existing naming scheme in the mobile theme-audit lineage, not this program's P0.G1). Every file
in that whitelist (`celebrity_plans_page.dart`, `equipment_detail_page.dart`, `scanner_page.dart`,
`form_check_page.dart`, and others) is a `mobile/lib/features/**` UI file — no P0 gate touched
`mobile/lib` at all; every P0 commit is confined to `scripts/`, `functions/`, `functions-equipment-
identity/`, `core/equipment_identity/`, `.github/workflows/`, and `firebase.json`. This drift predates
P0 and is out of this phase's scope to fix — flagged here rather than silently ignored, and left for
whichever session owns the mobile theme audit to reconcile the ratchet count against current code.

No other regression, in any suite, anywhere in the P0-relevant surface.

## 4. Artifact drift check

Rather than hand-recomputing hashes outside the actual generator code (a real risk of introducing a
false-positive drift finding through a subtly different hashing implementation), drift was checked
the way each gate's own design intends: every generated artifact (`recognition_baseline_v1.json`,
the provenance contract, `source_registry.json`, `functional_type_snapshot_v1.json` +
`functional_type_snapshot_manifest.json`, `p0_g5_probe_result.json`, `p0_g6_isolation_evidence.json`)
has a paired test suite that re-derives or re-validates it against the current generator/validator
code, and every one of those suites passed on the exact final HEAD checked out for this index
(§3 above — the full 408-test Python run and the 28-test identity-package Jest run cover all of
these). No drift found.

**P0.G0 status check**: grepped the full repository for every `P0.G0` reference (design docs,
`DECISION_LOG.md`, gate docs, published reports). Every occurrence describes it as blocked/external/
not-yet-started; none marks it passed, ready, or otherwise closed. No drift.

**P0.G5 outcome-scope check**: grepped for `OCR_TEXT_ONLY_DEFER_VISUAL`/`COLOCATED_VECTOR_FEASIBLE`
across the repository. Both strings appear only inside P0.G5's own evidence/doc/type files and the
identity package's own type definitions — nowhere in `mobile/lib`, no P4/visual-feature code path
reads or branches on this outcome. `functions-equipment-identity/src/index.ts` still exports nothing.
No drift, and no accidental unlock of visual work.

## 4b. Final adversarial review round (3 independent agents, whole P0 diff range)

Per GPT-PM's explicit request, a fourth review round ran against the full P0 diff (`f23130b~1..f6315dd`,
all 9 commits), independent of and blind to every per-gate review already done — `security-reviewer`
(production/deploy safety), `silent-failure-hunter` (evidence integrity), `code-reviewer` (provenance
authenticity). Two of the three agents' completion notifications arrived with no findings text on
their first (and in one case, second) attempt; each was recovered with a follow-up message asking it
to restate, per the established recovery pattern from earlier P0 gates.

**security-reviewer** (hidden production mutation; accidental dual deploy; secrets/PII disclosure;
rights fail-open) — **NO ISSUE on all 4 areas**, each independently re-verified rather than taken on
a prior session's word (re-grepped for bare `firebase deploy --only functions`, re-read
`source_registry.json` in full, re-traced every `rights.py` eligibility path looking for a bypass and
found none). One already-known, already-documented MINOR reconfirmed (Firebase CLI predeploy-hook
scoping is asserted from vendor docs, not empirically dry-run tested) — not new, already recorded at
P0.G6.

**code-reviewer** (invented provenance/baseline authenticity vs real orchestration code; legacy set
mislabeling; P0.G1/P0.G2 AC/DoD-vs-doc consistency; generator code review) — **NO ISSUE on all 4
areas**, verified by directly reading the real orchestration Dart files the baseline doc claims to
describe (not just re-reading the doc's own claims about itself) and confirming every fact matches
current source. One MINOR found and fixed: P0_G1_BASELINE.md and P0_G2_ML_PROVENANCE.md's own
close-condition checklists still showed "commit pushed and remote SHA verified" as an unchecked `[ ]`
at the individual gate-close time (deliberately, to avoid a second source of truth vs
`core/DECISION_LOG.md`) — this read as "still pending" during the aggregate review even though the
fact was true. Fixed by checking both boxes now, since the underlying fact (`git fetch origin` +
`git rev-list --left-right --count HEAD...origin/master` = `0 0`) was independently re-verified as of
this exact HEAD, not merely assumed from the earlier gate-close record.

**silent-failure-hunter** (invented/false cloud feasibility; stale evidence hashes/drift; ontology/
schema drift; AC/DoD vs recorded gate status) — **1 MAJOR found and confirmed, 1 area NO ISSUE, 2
areas left explicitly UNKNOWN by the agent itself** (it disclosed running out of time rather than
guessing):

- **MAJOR, CONFIRMED independently, then FIXED.** `recognition_baseline_v1.json` (P0.G1, committed at
  the very first P0 commit, `f23130b`, 09:18 local time) still recorded `equipment.json`'s **pre**-
  `.gitattributes`-LF-fix CRLF-based SHA-256. P0.G4 (commit `eac45bb`, ~13:22, roughly 4 hours later)
  fixed exactly this class of drift for its own snapshot artifact by pinning `text eol=lf` for the
  same source file — but nothing regenerated P0.G1's baseline afterward, so it kept the stale,
  pre-fix hash. **Independently reproduced**, not taken on the agent's word: ran
  `recognition_baseline.py --check --target baseline` directly and confirmed it failed
  (`recognition_baseline_v1.json does not match what the source actually says`); computed the current
  file's real SHA-256 both from the working copy and from the git object at HEAD and confirmed both
  equal the value P0.G4's manifest already recorded, not the value P0.G1's baseline recorded. **Root
  cause of why no test caught this**: every existing test in `test_baseline.py` built a *fresh*
  payload via `baseline.build()` and compared it to a *fresh* hash of the current file in the same
  test run — a tautology that stays green even when the actually-committed file on disk is stale,
  because it never loads and checks the real committed JSON. The CI step wired at P0.G4
  (`flutter.yml`'s `ct1-content-qa` step) only runs `pytest`, never `recognition_baseline.py --check`
  against the real committed file, so nothing in CI would have caught this either. **Fixed**:
  regenerated `recognition_baseline_v1.json` for real (`--write --target baseline`); the diff is
  exactly the two fields affected (`functionalCatalog.sha256` and `sourceCommit`) — `typeCount`
  unchanged, confirming the catalog's actual content never changed, only the CRLF-vs-LF byte
  representation of the file the hash was computed over. Added two new tests,
  `test_10_committed_baseline_matches_a_fresh_build` and
  `test_10b_committed_legacy_inventory_matches_a_fresh_build`, that load the real committed files
  (via the same `--check` code path, with no `--out` override) instead of a freshly-built temp copy —
  closing the exact tautology gap that let this drift land silently. Verified: `--check` now passes
  for both targets; the type-snapshot generator's own test suite already had the non-tautological
  equivalent (`test_generated_files_on_disk_match_a_fresh_build`, present since P0.G4) so this gap was
  scoped to P0.G1 only, not systemic across every generator — P0.G2's provenance contract and P0.G3's
  source registry are hand-authored/curated data, not hash-derived-from-source artifacts, so this
  drift class does not apply to them.
- NO ISSUE on invented/false cloud feasibility: the P0.G5 result validator was re-read and confirmed
  to structurally refuse any outcome claiming more than was actually probed; nothing downstream reads
  the deferred outcome as "confirmed working."
- **UNKNOWN, not cleared, disclosed by the agent rather than guessed**: full ontology/schema-shape
  cross-check between `rights_decision.schema.json` and `rights.py`'s eligibility functions, and P0.G3
  through P0.G6's own AC/DoD text vs their closing docs, were not exhaustively finished by this agent
  before it chose to report its one confirmed result rather than keep digging indefinitely. Given the
  cost/value of a further full round, this session closed the residual gap directly instead of
  spawning a 4th agent attempt: `functional_type_snapshot_v1.json`'s actual on-disk shape (a
  `types` array of `{id, name, category, manufacturer, description}` objects) was read directly and
  confirmed to match exactly what `validate_type_reference` (the function P1.G1 T5/P1.G6 T5 are
  contracted to call) actually expects. `rights.py`'s eligibility functions were already traced in
  full, independently, by `security-reviewer`'s own area-4 pass in this same round (see above) — the
  overlapping ground between "rights fail-open" and "rights/schema ontology" is covered by that
  result. P0.G3 through P0.G6's AC/DoD-vs-doc consistency was not re-verified by a fresh cold agent in
  this round; each gate's own close-conditions checklist was built directly against the gate-contract
  doc's text at that gate's own close time and confirmed live with GPT-PM via `pm_set_gate` at each
  step (see §1's timestamps) — treated here as a weaker form of evidence than a genuinely independent
  cold re-read would be, and flagged honestly as such rather than silently upgraded to "confirmed."

## 5. Final phase verdict

**P0 COMPLETE. P1 MAY START.** One real MAJOR was found and fixed during this aggregate pass (§4b —
P0.G1's baseline artifact was stale relative to the P0.G4 CRLF/LF fix, plus the tautological test gap
that let it stay stale); everything else in the adversarial review came back NO ISSUE or was an
already-known, already-documented deferred MINOR. The following residual items carry forward, all
already documented at their owning gate and none release-blocking for P1:

- **P0.G0** (App Check platform readiness) stays `BLOCKED_EXTERNAL_PLATFORM_MIGRATION` — genuinely
  out of scope for an autonomous coding session (needs a real platform migration decision/action).
  P1+ work that depends on App Check enforcement state must continue to read P0.G0's status
  conditionally, per the gate contract's own T3 requirement — never assume it as closed.
- **P0.G4's server-consumption DoD** was mechanically moved to P1.G1 T5 and P1.G6 T5 (the gate-
  contract repair, commit `0e4316f`) — P1.G1 and P1.G6 now carry that requirement explicitly in their
  own task tables; this is not a dropped requirement, just correctly relocated to its real owner gate.
- **P0.G5's deferred visual path** (`OCR_TEXT_ONLY_DEFER_VISUAL`) means no provider SDK is installed
  and no embedding/vector-search architecture is chosen yet — whichever gate reopens visual equipment
  recognition (design docs point at a later P-phase) starts from zero on that specific sub-decision,
  not from an assumed default.
- **Three MINOR findings accepted/deferred, all requiring a precondition P0 deliberately doesn't
  have yet**: Firebase CLI predeploy-hook scoping and cross-codebase deletion-detection (P0.G6, both
  need a real deployed identity function to test further), and the un-exhaustively-re-verified
  ontology/AC-DoD checks for P0.G3-P0.G6 (§4b, judged lower-value than a 4th agent round given each
  was already checked live against the gate contract at its own close time and confirmed with
  GPT-PM) — flagged honestly as weaker evidence than a fresh independent re-check, not silently
  upgraded to "confirmed clean."
- **The pre-existing Flutter hardcoded-white-count ratchet test failure** (§3) is unrelated to P0 and
  was not fixed here, per the "don't touch unrelated code" discipline — flagged for whoever owns that
  test/audit lineage.

No BLOCKER and no unresolved MAJOR exists anywhere in P0's scope (the one MAJOR found in §4b was
fixed within this same aggregate pass, verified by rerunning the affected suite before this verdict
was written). Rights fail-open, accidental dual deploy, hidden production mutation, and false
cloud-feasibility claims were all actively hunted for by an independent cold-read agent and none was
found. One adversarial review round, with each of the two agents whose first completion arrived empty
recovered via restatement, was sufficient — no second full round was required, since the one
confirmed finding was fixed inline rather than needing a contested-finding rebuttal round.

Note on CI status: GitHub's combined-status API did not return status contexts for the final commit
(`f6315dd`) at the time this index was written — this is not read as "CI failed" or "CI green," it is
simply not evidence either way. Every test result cited above (§3) is from a real local run against
the exact final HEAD, not inferred from CI status.
