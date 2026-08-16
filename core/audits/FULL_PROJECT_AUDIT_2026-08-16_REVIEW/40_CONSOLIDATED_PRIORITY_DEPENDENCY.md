# 40 - Consolidated findings: priority and dependency order

Reconciles all 35 findings (27 original + 8 from the second-order review) against the revised
remediation plan (`30_REVISED_REMEDIATION_PLAN.md`, 5 gates + orphans) and the four operator
decisions. Raw sortable data: `41_CONSOLIDATED_FINDINGS_PRIORITY.csv`.

**Not started.** Nothing here has been actioned. Awaiting `REMEDIATION-GO` for the gates; the Tier 0
decisions can be asked for immediately since they cost engineering nothing to wait on.

Two findings' severities in this list differ from a plain read of the individual finding registers:
`F013`'s BLOCKER is **CONTESTED** (not upheld) per the blinded adversary's disagreement, and `F001` is
**HIGH**, not the review's own MEDIUM downgrade - restored this session after independently
re-confirming `fitnessProfileProvider` has zero consumers (E05).

## Addendum: "16 NOT_REVIEWED" reconciliation, and 8 findings reproduced this session

The narrative in `00_CONSOLIDATED_REPORT.md` states 16 of 27 first-audit findings remain
`NOT_REVIEWED`. The first version of this consolidated table only marked 8 as such - it had wrongly
tagged `F002, F004, F005, F006, F009, F011, F022, F023` as `OPEN_REPRODUCED` on the strength of their
citations in `16_ROOT_CAUSE_MAP.csv` / `33_REMEDIATION_ORPHANS_CLOSED.csv`, which is evidence of a
root-cause mapping pass, not a formal reproduction pass. Checked directly: `07_HIGH_SEVERITY_REPRODUCTION.csv`
contains exactly 11 finding ids (`F001, F003, F013-F021`). 27 - 11 = 16. **The narrative "16" is
correct; the table was wrong**, in exactly the citation-treated-as-verification shape the audit exists
to catch (compare E01/E05).

All 8 have now been independently reproduced against current source this session (not merely
relabeled) - see the `notes` column in `41_CONSOLIDATED_FINDINGS_PRIORITY.csv` for the exact
file:line evidence for each. Two of them also resolved a pending decision:

- **D3 resolved.** `mobile/assets/models/README.md` read in full: the shipped model (v1) is 10 classes.
  A v2 exists in development with real-abstention support but measures **28% top-3 on the operator's
  own 30 real gym photos** - worse than the headline v1 number, not better, and explicitly not shipped.
  Decision: correct the Scan-tab copy to what v1 actually supports now (G-A/A6); do not reference v2's
  capability in any user-facing claim until it ships and clears a real-world bar. This is a copy-only
  decision, not an ML-scope one - no model work is authorized by this decision.
- **F011 resolved.** All 10 `onCall` callables in `functions/src/index.ts` enumerated. Decision:
  `RISK_ACCEPTED` for the 7 callables whose blast radius is bounded by Firestore data that deletion
  already removes; `REMEDIATE` for `startFreeTrial` and `createCheckoutSession` specifically, since a
  stale token could replay trial/checkout eligibility checks against now-absent records inside the ~1h
  window - this is a distinct exploit the deletion path introduces, not a pre-existing one. Implementation
  queued under Tier 6.

Still genuinely `NOT_REVIEWED` after this session: `F007, F008, F024, F025, F026, F027, F010, F012` -
8 findings, all Tier 6, none blocking any of the five gates.

---

## Tier 0 - Decisions the operator must make; engineering cannot proceed past them for the affected findings

These have no code dependency on anything else and should be asked **now**, in parallel with Tier 1 -
both have lead times measured in days and neither blocks any gate.

| Decision | Findings gated | What's needed | What is NOT blocked |
|---|---|---|---|
| **D1** | F013 (BLOCKER, contested) | Clinician review of a stratified sample of the 360 untagged rows: are they untagged because they're safe, or because nobody looked? | G-A/A4 (making the tagged/total figure visible) proceeds regardless of the answer |
| **D2** | F014 (BLOCKER) | Wording of the pregnancy question and whether the product refuses this user at all | The mechanism (ephemeral question -> `wholePersonBlocks`, no persisted medical category) is already fully scoped and needs no further engineering discovery |
| **D3** | F002 (HIGH) | Whether the "scan any gym machine" claim narrows, or the label set expands | The copy fix (G-A/A6) is copy-only and proceeds regardless; ML label-set expansion is a separate, larger, unauthorised project |
| **D4** | F003, F004 (MEDIUM), 12 unencrypted health fields in SharedPreferences | Consume vs. delete decision per field, under collect/store/consume/purpose/retention/sensitivity/necessity | Default per the mandate is delete/stop-collecting absent a justified use |
| **F011 sign-off** | F011 (INFO) | Security-domain-owner accepts the ~1h post-deletion token window, or requires `checkRevoked` on named callables | Stays `OPEN`, not `CLOSED`, either way until signed |

---

## Tiers 1-5 - The five remediation gates, in dependency order

Order is `G-A -> G-D -> G-C -> G-B -> G-E`, fixed by the revised remediation plan on cost/risk
grounds, not severity alone: G-A is cheapest and touches no decision path, so it goes first
precisely *because* it cannot break the eligibility layer while the higher-risk gates are still ahead
of it. G-B is deliberately placed after the cheap wins are banked because it is the largest
correctness change and the highest risk (it edits the safety layer's own call sites, six of them).
G-E is last because it is a generator rewrite that needs domain/strength review, not just a test.

### Tier 1 - G-A: make the refusals the app already produces visible to the user
No decision-path changes. Root cause RC3.
**Closes:** N01, F017, F018, F019, F020 (partial - the render-site half), F002 (copy-only, orphan
task A6).
**Risk:** low.

### Tier 2 - G-D: close the client-writable server state
Three clauses behind a CI job that already exists. Root cause RC6.
**Closes:** F005, F006, N03.
**Risk:** low, but verify against the rules emulator before shipping - the review states the change is
"three lines" but that has not been independently re-attacked (see open audit-quality work).

### Tier 3 - G-C: stop rendering invented exercises
Self-contained. Root cause RC2.
**Closes:** F016.
**Risk:** low.

### Tier 4 - G-B: route every exercise-serving surface through the eligibility layer that already exists
One pattern, six call sites. Root cause RC1. This is the largest correctness win in the whole plan
and the highest risk, because it changes call sites on the safety layer itself.
**Closes:** F015 (partly - the immediate patch), F020 (partial - the data-routing half), F023, N02,
N04.
**Risk:** medium. Each of the six call sites (B1-B6) should land and get its own mutation test
separately rather than as one combined change.

### Tier 5 - G-E: give the default programme a real spec and delete the alphabetical fallback
Needs explicit invariants first (goal, safety, equipment, movement-restriction, whole-person-block,
progression/regression, empty-result semantics - see master prompt §23) before implementation, not
just a green test. Root cause RC4.
**Closes:** F015 (fully), F021, F022.
**Risk:** medium-high - a real generator change, needs the strength reviewer.

---

## Tier 6 - Independent findings: no gate dependency, can run in parallel at any point

None of these block or are blocked by the five gates. Most are also part of the still-unreviewed
16-item MEDIUM/LOW/INFO tail (§27-28 of the master prompt) - they have not been re-tested at current
HEAD by this review, only carried forward from the first audit.

| Finding | Severity | One-line | Tail status |
|---|---|---|---|
| F009 | LOW | uid in a debug log on a corrupt-key path - one-line fix, orphan `G-F/F1` | reproduced this session's predecessor review, no decision needed |
| N08 | LOW | Two dead safety-screening providers, duplicate of the live eligibility layer | independently re-verified this session (zero watch call sites) |
| F007 | MEDIUM | Analyzer warnings/infos cannot fail CI | **NOT_REVIEWED** |
| F008 | MEDIUM | No push-triggered CI on the working branch | **NOT_REVIEWED** |
| F024 | MEDIUM | `sortByTierFit` has no tie-break, unstable sort | **NOT_REVIEWED** |
| F025 | MEDIUM | Nine celebrity-plan exercise ids are all dangling (dormant) | **NOT_REVIEWED** |
| F026 | MEDIUM | No `SafetySetting` on any Gemini call | **NOT_REVIEWED** |
| F027 | MEDIUM | Seven hardcoded English safety strings bypass l10n | **NOT_REVIEWED** |
| F010 | INFO | Moments + both Wear OS providers unreferenced - decide wire vs. delete, don't delete during an audit | **NOT_REVIEWED** |
| F012 | INFO | Scope doc contradicts the shipped TFLite model - simple doc correction | **NOT_REVIEWED** |
| N07 | INFO | `/team/:teamId` declared, unreachable - add an entry point or remove the route | reproduced this review |

## Closed / informational - no remediation task at all

- **N05** - methodology correction only (Storage evidence was wrong, conclusion survived). No product
  defect.
- **N06** - informational; no independent task, feeds how D1 should be framed.

---

## Recommended execution order

```
NOW, in parallel, zero engineering lead-time cost:
  D1, D2, D3, D4, F011 sign-off

THEN, in strict order (each gate's acceptance test + mutation test before the next):
  G-A -> G-D -> G-C -> G-B -> G-E

ANY TIME, unordered, no dependency on the above:
  Tier 6 (F007, F008, F009, F010, F012, F024, F025, F026, F027, N07, N08)
```

## What this list does not replace

This is a remediation-priority view, not a substitute for finishing the audit itself. Separately and
before any final second-order verdict is reissued: the 16-item tail above still needs revalidation at
current HEAD, Firestore/CI/the test suite still need independent (not self-) re-attack, QA-adversary
Stage B still needs to run, and scorecard `29` still needs its correction written. None of that blocks
starting Tier 0 or Tier 1 - it blocks calling the *audit* finished, not calling *remediation* startable.
