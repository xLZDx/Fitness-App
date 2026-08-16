# Consolidated report - second-order forensic audit

**Subject:** the SPTR full project audit of 2026-08-16 (`core/audits/FULL_PROJECT_AUDIT_2026-08-16/`,
commit `1453236`, 27 findings, 31 artefacts) and, through it, the product itself.

**Status: audit only.** No product file was changed. The first audit was not edited. Nothing was
committed or pushed. Remediation has not started and awaits an explicit `REMEDIATION-GO`.

**Not final.** Sixteen MEDIUM/LOW/INFO findings remain un-revalidated; see *Limits* at the end. The
verdict in `31_FINAL_SECOND_ORDER_VERDICT.md` is deliberately not updated yet.

---

## 1. The two verdicts

### On the product: NOT_RELEASE_READY - upheld, and independently

The verdict does not rest on any finding that this review weakened. It rests on three defects re-read
at source at current HEAD:

| Blocker | Reproduced | Evidence |
|---|---|---|
| Injury filter fails open on untagged rows | YES, verbatim | `exercise_filter.dart:37-45` - `if (exercise.contraindications.isEmpty) return false;`. 360 of 1,887 rows untagged (19.1%) |
| No pregnancy path exists | YES | Neither `ParQQuestion` (7 values) nor `MovementRestriction` (9 values) carries one. The only mentions in `lib/` are comments at `cycle_phase.dart:56-64` recording the deliberate decision not to hold the status |
| Spec-less programme enrolment bypasses the whole-person gate | YES | `programme_providers.dart:199-206` calls `buildProgrammeSchedule` with no `SafetyContext` - the parameter does not exist on the function |

One blocker is **contested**, not confirmed: see §4.

### On the first audit: SUBSTANTIALLY SOUND

- Every BLOCKER and CRITICAL reproduces at source.
- **23 of 23 numeric claims reproduce exactly**, recomputed from the shipped assets without opening
  the audit's own CSVs (`14_NUMERIC_REPRODUCTION.csv`).
- **Zero re-tested findings collapsed into false positives.**
- Its internal counts are consistent across summary, register and plan.
- It disclosed its own errors rather than quietly fixing them - which is the only reason this review
  could trace the error class at all.

Where it was wrong: one denominator is unprovable (F003's "of 37"), three findings had no remediation
task, and five omitted artefacts were producible. **One charge laid against it in this review's first
pass has since been withdrawn - it was my error, not its** (§3).

---

## 2. Findings: 35 total

| Severity | First audit | Added by this review | Total |
|---|---|---|---|
| BLOCKER | 3 | 0 | 3 |
| CRITICAL | 3 | 0 | 3 |
| HIGH | 7 | 2 | 9 |
| MEDIUM | 10 | 2 | 12 |
| LOW | 1 | 1 | 2 |
| INFO | 3 | 3 | 6 |
| **Total** | **27** | **8** | **35** |

### The eight new ones (`18_NEW_FINDINGS.csv`)

**N01 (HIGH) - a safety refusal reaches the user as a network error, with a Retry button.**
The single sharpest miss. `ProgrammeNotViable`, including `ProgrammeFault.blockedBySafety`, becomes an
`AsyncValue.error` and lands in a generic handler at `workouts_page.dart:1281-1291`, which renders
*"The service is temporarily unavailable. Check your connection and try again."* (`app_en.arb:2118`)
with a **Retry** action. The four templates that refuse *correctly* tell the user it is a connectivity
problem and invite them to retry forever. The app's one honest refusal is the one the user never sees.

**N02 (HIGH) - the in-workout picker logs an unscreened pick, and the tap is terminal.**
`workout_player_page.dart:798-800,845`: the picker reads the injury-only catalogue and the tap writes
straight to the session. Every other unscreened list is saved by a re-screen on tap; here the tap *is*
the terminal action.

**N03 (MEDIUM) - the device-local health split is enforced only by client code.**
Nothing in `firestore.rules:12-17` rejects a `health` map on `users/{uid}/profile/main`. The strip
lives in one wrapper wired in one place.

**N04 (MEDIUM) - the AI coach entry is gated on one screen and ungated on two.**
`exercise_page.dart:83-88` gates it; `equipment_detail_page.dart:110-118` and `scanner_page.dart:1422`
do not. A user the app has refused all training can still obtain a sets-times-reps prescription.

**N05 (INFO)** - Storage holds no user content; deletion cannot orphan objects. *This finding's
original evidence was false and has been corrected - see E04.*

**N06 (INFO)** - `safety_coverage_providers.dart:121`: `const bool kSafetyTagsClinicallyReviewed =
false`. The product already records in code that its safety tags are unreviewed. Directly relevant to
how the headline blocker should be framed, and the first audit never surfaced it.

**N07 (INFO)** - `/team/:teamId` is declared and unreachable; the reachability test asserts
declaration, not reachability.

**N08 (LOW)** - `safetyVerdictProvider` and `draftSafetyVerdictProvider` are complete, correct and
watched by nothing.

---

## 3. Methodology: five errors, three of them mine

`METHODOLOGY_ERROR_REGISTER.csv`, `CONTAMINATED_CLAIMS_REVALIDATION.csv`,
`32_METHODOLOGY_CONTAMINATION_AUDIT.md`.

The first audit disclosed two errors. The contamination sweep found three more, **all three in this
review**, and one of them **reverses a correction I published**.

| ID | Owner | Category | Failure |
|---|---|---|---|
| E01 | first audit | naive reference counting | counted files, not occurrences (15 -> 7) |
| E02 | first audit | wrong denominator | hand-built "engine directory" list omitted real consumers |
| E03 | this review | semantic inference from lexical match | name collision - read a sibling field and called it a use |
| E04 | this review | non-existence from a narrow search | declared a subsystem absent without searching `functions/src` |
| E05 | this review | naive reference counting, second order | a doc-comment mention counts as an occurrence (7 -> **10**) |

### E05 and what it cost

Stripping comments before counting yields **10 dead providers, not 7**. Three were hidden by prose:
`fitnessProfileProvider` (`personalisation_providers.dart:12`), `safetyVerdictProvider` and
`draftSafetyVerdictProvider` (`safety_providers.dart:17,31`).

`fitnessProfileProvider` is the one that matters. This review downgraded **F001** from HIGH to MEDIUM
on the argument that a real level signal exists - `fitness_model.dart:115-131` builds a per-muscle
estimate from post-session `DifficultyRating` - *"consumed by `fitnessProfileProvider`"*.

Nothing consumes it. The model computes into a void. The first audit's original claim, *"any filter or
selection by level is fiction"*, is correct as written. **F001 is restored to HIGH.**

Worth naming: the correction was more confident than the claim it corrected, and less carefully
checked - because finding an error feels like the end of the work rather than the start of it.

### What was cleared

The project has **no code generation under `lib/`** - no `riverpod_generator`, `freezed`,
`json_serializable`, no `.g.dart` or `.freezed.dart`. So the "a reference hid in generated source"
vector is closed by evidence, not assumed away. Path/version confusion, duplicate counting and
production/test mixing each produced no error on re-test.

### Positive claims, attacked

The mandate required attacking PASS claims, not only findings. Twelve claims were revalidated
(`CONTAMINATED_CLAIMS_REVALIDATION.csv`); the load-bearing results:

| Claim | Result |
|---|---|
| No health data reaches any model prompt | **REPRODUCED_VERIFIED** - three model-input files enumerated, zero health tokens |
| 196 providers declared | REPRODUCED_VERIFIED, exactly |
| F003 / F004 / F014 / F019 / F020 | REPRODUCED_VERIFIED |
| 32 routes, none dead | **FALSE_NEGATIVE** - `/team/:teamId` (N07). Two of the three automated flags were noise; one was real |
| No Firebase Storage | **CORRECTED** - right conclusion, false evidence |
| 7 dead providers | **CORRECTED** to 10 |

---

## 4. The contested blocker

Two independent readers - the second-order review and a **blinded** adversary denied access to the
audit directory and the decision log - measured the same data and agree on every number: 1,527 of
1,887 rows tagged (80.9%), 360 untagged, nine tags covering all nine `InjuryRegion` values.

They disagree on what it means. The first audit read the untagged 360 as a fail-open hole and called
it a BLOCKER. The blinded reviewer, seeing 80.9% coverage across every region, filed the filter under
*"no material issue found"* and put the risk elsewhere: *"I cannot verify that any individual tag set
is right, nor that the 360 untagged rows are genuinely safe for everyone"* - citing the constant the
first audit never surfaced (N06).

**Neither reader can settle it. The tie-break is clinical**, and it is decision **D1** below.

---

## 5. Remediation: 8 root causes, 5 gates

`16_ROOT_CAUSE_MAP.csv`, `30_REVISED_REMEDIATION_PLAN.md`. Built from root causes, not from 35
findings. Five gates close 21 findings. **Not started.**

| Gate | Root cause | Scope | Closes |
|---|---|---|---|
| **G-A** | The refusal exists but does not reach the user | copy + five render sites + the scanner-coverage statement | N01, F017, F018, F019, F020, F002 |
| **G-D** | Server state is client-writable | three clauses in `firestore.rules:12-17` | F005, F006, N03 |
| **G-C** | Model output rendered without catalogue validation | `machine_describer.dart:165-177` | F016 |
| **G-B** | Safety context not propagated to every surface | one pattern, six call sites | F015 (partly), F020, F023, N02, N04 |
| **G-E** | The default programme never adopted the spec pipeline | add a `ProgrammeSpec`, delete `_fillDay` | F015 (fully), F021, F022 |

**Order: G-A -> G-D -> G-C -> G-B -> G-E.**

G-A first because it is the only gate that improves user safety without touching a decision path -
today the app makes correct refusals the user never sees. G-D next: three lines behind a CI job that
already exists. G-C is self-contained. G-B is the largest correctness win and the highest risk, so it
follows the cheap wins. G-E last - a generator rewrite needing domain review, not just a test.

Orphans closed (`33_REMEDIATION_ORPHANS_CLOSED.csv`): **F002** -> G-A/A6 (copy only; expanding the
label set is a separate ML gate and must not be bundled). **F009** -> G-F/F1, one line at
`photo_key_store.dart:184`. **F011** -> `NO_REMEDIATION_REQUIRED` **conditionally** - INFO severity and
the reasoning is already recorded in code, but "accept the window" is a security decision requiring
domain-owner sign-off. It stays OPEN until signed.

---

## 6. Four decisions that are yours, not engineering's

**D1 - the untagged 360.** Contested 1-1 between independent readers. Ask a clinician to adjudicate a
stratified sample. **Do not flip `exercise_filter.dart:38` to fail-closed before that answer** -
withholding 19.1% of the catalogue from every injured user is a large product change made on a
contested premise. G-A/A4 makes the gap visible meanwhile, which is the honest interim either way.

**D2 - pregnancy.** The mechanism is small: one ephemeral question routed to the existing
`wholePersonBlocks`, holding no medical category - which respects the recorded decision at
`cycle_phase.dart:56-64`. What needs you is the wording, and whether the product will refuse this user
at all. **Anyone reading this blocker as "start storing pregnancy status" will implement the wrong
fix.**

**D3 - "scan any gym machine"** (`PITCH_2026.md:15`) against 10 of 69 recognisable machines. Either
the claim changes or the label set does.

**D4 - collected-and-unused data.** At least 14 questionnaire fields and 12 health fields reach no
engine, the sensitive ones unencrypted in SharedPreferences. Consuming them is feature work; deleting
them is a product decision. Deleting is cheaper and reduces liability.

---

## 7. The first audit's omissions

Ten artefacts were dispositioned (`34_OMITTED_ARTEFACT_DISPOSITION.csv`, `35_OMISSION_ASSESSMENT.md`):
2 `EQUIVALENT_COVERAGE_ELSEWHERE`, 3 `PARTIAL_COVERAGE`, 1 `UNAVAILABLE`, **5 `TRUE_AUDIT_SHORTFALL`**.

The README justified every omission with *"writing them would have meant presenting unread territory
as audited."* For four that is exactly right. For five it is not: each had a **mechanical half that
required no judgement** and was producible from files already read.

One has a demonstrated cost. `16_FIREBASE_DATA_MAP.md` would have forced the question *"which rule
governs each field this client writes?"* - which is precisely the question that produced **N03**, found
in this review rather than the first.

---

## 8. Limits of this review

Stated plainly, because a second-order audit that oversells itself is the failure mode it exists to
catch.

- **The first audit and most of this review share an author.** Self-review is not independence. The
  only genuinely independent input is the blinded adversary (`27_QA_ADVERSARY_BLIND_REPORT.md`).
  Treat every `REPRODUCED_VERIFIED` produced by me as *the same reader reaching the same conclusion
  twice*.
- **16 of 27 first-audit findings** - the MEDIUM/LOW/INFO tail - remain `NOT_REVIEWED`.
- **Firestore rules, CI and the test suite were not independently re-attacked.**
- **QA-adversary stage B** (non-blind challenge of the findings) was never run.
- The contamination sweep identified lexically-derived claims **by reading the first audit's stated
  methods**. An audit that misdescribed its own method would not be caught by it.
- Everything marked `UNAVAILABLE` in the first audit - clip-to-exercise correspondence, technique
  soundness, real-gym recognition, background timer behaviour - remains `UNAVAILABLE`. None of it
  became testable by writing a second audit.

**`29_AUDIT_ACCURACY_SCORECARD.md` is now too harsh on the first audit**, since one of the two errors
it charges against it turned out to be mine. It has not yet been rewritten.

---

## 9. Artefact index

`00` this report · `02` internal consistency · `06` contamination check · `07` high-severity
reproduction · `14` numeric reproduction (23/23) · `16` root-cause map · `18` new findings (N01-N08) ·
`27` blinded adversary · `29` accuracy scorecard · `30` revised remediation plan · `31` verdict
(**not final**) · `32` contamination audit · `33` orphans closed · `34` omitted-artefact disposition ·
`35` omission assessment · `METHODOLOGY_ERROR_REGISTER.csv` · `CONTAMINATED_CLAIMS_REVALIDATION.csv`
