# Clinical validation handoff — SPTR exercise safety tags

**For:** a clinician or clinical exercise physiologist asked to review D1 and H3.
**Prepared:** 2026-08-17, against branch `formcoach/gates-a-c`.
**You should not need to read the codebase.** Everything you need is in this document.

**Status this document does not change:** `D1 = EXTERNAL_CLINICAL_VALIDATION_REQUIRED`,
`H3 = HOLD`. Nothing produced by the engineering team, by any automated tool, or by any AI system
can satisfy them. That is the entire reason you are being asked.

---

## 1. What SPTR is, in one paragraph

A fitness app that builds training programmes. It holds a user's self-reported health answers on
their device, screens them with PAR-Q+, and filters the exercise catalogue against injuries and
movement restrictions they have declared. It gives no diagnoses and prescribes no medication. Its
central safety claim to users is: *"exercises that conflict with an injury you reported were removed
from your list."*

**The question for you is whether that claim is currently defensible, and under what conditions it
could be.**

---

## 2. The catalogue, measured today

| | Count |
|---|---|
| Exercise rows in the shipped catalogue | **1,887** |
| Rows carrying at least one safety tag | **1,527** (80.9%) |
| Rows carrying **no** safety tag | **360** (19.1%) |

Tags come from a nine-value body-region vocabulary. Distribution across the 1,527 tagged rows:

| Region tag | Rows |
|---|---|
| `shoulder` | 489 |
| `hip` | 404 |
| `elbow` | 371 |
| `knee` | 362 |
| `lower_back` | 313 |
| `upper_back` | 265 |
| `ankle` | 229 |
| `wrist` | 190 |
| `neck` | 117 |

Rows carry between 0 and 6 tags; 759 rows carry exactly one, 55 carry four, 4 carry six.

**Verified by measurement against `mobile/assets/data/exercises_vendor.json` on the date above, not
quoted from an earlier document.**

---

## 3. Where the tags came from, and what that means

The 1,527 tagged rows were tagged by `tag_contraindications.py` — **deterministic rules over the
vendor's own movement names and primary muscles**. Every assignment records which rule produced it,
per row, in `core/contraindications/*.csv` (one file per region).

That is a real screen. **It is not a clinical one.** No clinician has reviewed the taxonomy, the
rules, or any individual assignment.

The product already records this, in code:

```dart
const bool kSafetyTagsClinicallyReviewed = false;
```

`mobile/lib/features/equipment/state/safety_coverage_providers.dart:121`

It is not decoration. It drives a user-facing disclosure, and two tests hold it false so that
flipping it is a deliberate act. When a clinician signs off, flipping that one constant removes the
weaker disclosure automatically — the disclosure is written to disappear on its own rather than
requiring someone to remember to delete it.

**Your sign-off is what that constant is waiting for.**

---

## 4. How the app behaves today

You are reviewing a system that already fails conservatively in most places. Knowing exactly where
matters, because it changes which of your answers are urgent.

### 4.1 An untagged exercise

For a user who has declared **no** injuries: shown normally.

For a user who **has** declared an injury or restriction: an untagged row cannot be screened — there
is no tag to screen it against — and it is **shown anyway**.

> **CORRECTION, 2026-08-17.** An earlier version of this section said the opposite: that an untagged
> row is *withheld*. **That was wrong**, and it was wrong about the single behaviour Q3 asks you to
> judge. The correction is recorded here rather than silently rewritten, because a reader who saw the
> earlier text formed a view on a false premise.

The measured behaviour, at
[mobile/lib/features/equipment/data/exercise_filter.dart](../../mobile/lib/features/equipment/data/exercise_filter.dart):

```dart
bool isContraindicated(ExerciseItem exercise, Iterable<Injury> injuries) {
  if (exercise.contraindications.isEmpty) return false;   // <- untagged: not contraindicated
  ...
}
```

and the function's own doc comment says *"Exercises with no contraindication tags are always kept."*
`evaluateExercise` adds an injury block only when `isContraindicated` returns true, so an untagged
row returns `Allowed` on every surface. **No user-facing string says the app could not screen it.**
(There is a separate, unrelated mechanism — `cannotScreenGeneratedFor` — which covers AI-*generated*
rows. It does not cover these 360 catalogue rows.)

This is audit finding **F013**, and the repository's own record is more precise than the earlier text
here allowed:

| | |
|---|---|
| The **behaviour** | `REPRODUCED_VERIFIED` — *"Line 38 is `if (exercise.contraindications.isEmpty) return false;` verbatim. Untagged count is exactly 360, share 19.1%"* (`07_HIGH_SEVERITY_REPRODUCTION.csv`) |
| The **severity** | `CONTESTED` 1-1 between independent readers — *"needs a clinician"* (`16_ROOT_CAUSE_MAP.csv`) |
| The **instruction** | *"Do not flip `exercise_filter.dart:38` to fail-closed before D1 answers"* (`41_CONSOLIDATED_FINDINGS_PRIORITY.csv`) |

So the behaviour is not in doubt. **What is in doubt is whether it is acceptable, and that is Q3.**
The code has deliberately not been changed while this handoff is open: flipping it to fail-closed
would remove 360 exercises from every injured user's library, which is a clinical trade-off and not
an engineering one.

### 4.2 Injuries and movement restrictions

The user declares a body region (`shoulder`, `knee`, …) or a movement restriction (overhead work,
deep knee flexion, loaded spinal flexion, spinal extension, wrist loading, impact, prolonged
standing, balance, other). Exercises whose tags intersect the affected regions are removed.

**Four of those restrictions cannot be enforced at all** — `impact`, `prolongedStanding`, `balance`
and `other` — because the nine-region vocabulary has no tag that distinguishes, for example, jumping
from not-jumping. The app does **not** pretend otherwise: it tells the user that it carries no tag
for that restriction and filtered nothing on that basis.

**This is a taxonomy gap, and it is one of the things worth your opinion.**

### 4.3 Whole-person blocks — the app refuses to prescribe at all

Four states stop any programme, plan or prescription being produced:

1. PAR-Q+ screening did not clear the user (or was never completed);
2. the user reports a clinician advised them against exercise;
3. the user reports being under post-operative restrictions;
4. **the user reports being pregnant or recently postpartum** (added 2026-08-17, finding F014).

State 4 is deliberately a **refusal, not a policy**. SPTR holds no validated perinatal exercise
policy, so rather than improvise one it declines to build a personalised programme and refers the
user to a midwife, doctor or qualified perinatal exercise professional. It encodes no trimester, no
due date, no postpartum week and no risk score, and it does not remove a single exercise from the
library — it withholds the *prescription*.

**If you believe that refusal is the wrong call in either direction — too strict, or not strict
enough — that is a question for section 6.**

### 4.4 Unknown state

An unanswered question is never treated as a safe answer. A user who has not completed onboarding is
refused prescriptions (fail-closed) while keeping the ability to browse and read (fail-open on
display). Those two are held apart deliberately; collapsing them hid the entire app from
un-onboarded users twice during remediation.

### 4.5 What AI does and does not decide

The app uses AI for equipment recognition from photos and for a coach chat. **No AI output can
create, name or authorise an exercise**: model output cannot become a canonical exercise identity,
and the safety layer is deterministic. Provider content moderation is configured and is unrelated to
exercise safety.

---

## 5. What we are NOT asking you to do

- Not to review 1,887 exercise cards one by one. H3 is on hold precisely to avoid a rubber-stamp.
- Not to write a training programme, or approve one.
- Not to validate the app as a whole, or its marketing.
- Not to accept any AI-generated tagging as pre-reviewed. It is not.

---

## 6. The questions we are asking

Bounded, answerable, and each one changes a specific product decision.

### Q1 — Taxonomy
Is a **nine-region body-part vocabulary** (shoulder, hip, elbow, knee, lower_back, upper_back,
ankle, wrist, neck) a clinically acceptable basis for excluding exercises from a person who has
declared an injury in that region?
*If not: what is the minimum acceptable taxonomy?*

### Q2 — Rule provenance
The mapping is deterministic rules over movement names and primary muscles, recorded per row in
`core/contraindications/*.csv`. **Is rule-derived tagging acceptable as a screening basis at all**,
or does each assignment require individual clinical review?
*This single answer determines whether H3 is weeks of work or months.*

### Q3 — The 360 untagged rows
They are currently **shown** to any user with a declared injury, unscreened and unlabelled as such —
see the correction in §4.1. Should they be:
(a) assigned tags — and by what process; (b) treated as `UNKNOWN` and withheld;
(c) excluded from the catalogue entirely?

### Q4 — What must stay UNKNOWN
Which exercises or categories should **never** receive an automated tag, and must remain
clinician-assigned or withheld regardless of how good the rules become?

### Q5 — Categorical exclusions
Which declared conditions or states should trigger a **categorical** refusal to prescribe, rather
than a filtered list? We currently have four (section 4.3). Are any missing, and is any of the four
wrong?

### Q6 — The unenforceable restrictions
Four declared restrictions (impact, prolonged standing, balance, other) cannot be screened by the
current vocabulary and the app says so. **Is stating the gap sufficient**, or must the app refuse to
prescribe for a user who declares one?

### Q7 — Evidence to change the disclosure
`kSafetyTagsClinicallyReviewed = false` drives the "screened by rules, not by a clinician"
disclosure. **What evidence would have to exist for that constant to become `true`?** Please answer
concretely — a scope, a sample size, a review method — because that answer is the definition of done
for H3.

---

## 7. What must come back

A review comment such as *"looks good"* is **not validation evidence** and will not be recorded as
such. An earlier version of this section listed thirteen prose fields and shipped nothing to put
them in, which is why nobody could start. There is now a worklist.

### 7.1 The two files you receive

Generated by `scripts/review/clinical_import.py --worklist <dir>`, checked in at
[core/review/worklist/](core/review/worklist/):

| File | What it is |
|---|---|
| [core/review/worklist/worklist.csv](core/review/worklist/worklist.csv) | All **1,887** rows, one per line. Eight read-only columns (id, population, current tags, title, summary, steps, equipment, and what the app does with that row today) and three you fill: `disposition`, `tags`, `rationale`. |
| [core/review/worklist/submission.json](core/review/worklist/submission.json) | Seven lines: your name, credentials, authority and date. The catalogue digest and commit are pre-filled — they pin the review to exact bytes and should not be edited. |
| [core/review/worklist/HOW\_TO\_REVIEW.md](core/review/worklist/HOW_TO_REVIEW.md) | The instructions, restated for a reader who does not read the rest of this document. |
| [core/review/worklist/worklist.meta.json](core/review/worklist/worklist.meta.json) | Counts, digest, commit and the tag vocabulary. Metadata only: the rows live in the CSV and nowhere else, so the two copies cannot disagree. |

The worklist covers **both** populations — the 1,527 tagged rows and the 360 untagged ones. A
worklist of only the untagged rows would have answered Q2 by omission.

### 7.2 The four dispositions

| `disposition` | Meaning |
|---|---|
| `ACCEPT` | The tags this row currently carries are correct. |
| `REJECT` | They are wrong, and this row should not be relied on as tagged. |
| `AMEND` | They should be different. Put the correct set in the `tags` column, space-separated, from the nine-region vocabulary. An **empty** `tags` cell on an `AMEND` row means *this row should carry no tags* — a real answer, distinct from leaving the row alone. |
| `UNKNOWN` | The content does not let anyone decide. This is a first-class answer and nothing downstream treats it as a failure to respond. |

**A blank row is NOT REVIEWED.** It is never recorded as accepted, and the import reports the
not-reviewed count explicitly. A partial review is welcome and useful; a partial review recorded as
a whole one is not.

### 7.3 What we check, and what we deliberately do not

`python scripts/review/clinical_import.py --check submission.json` validates **structure and
provenance only**: required identity fields, an ISO-8601 timestamp with an offset, the catalogue
digest, rows that exist, no row reviewed twice, dispositions from the list above, and tags from the
nine-region vocabulary. A tag outside the nine is refused because the app cannot match it — such a
row looks screened and behaves unscreened.

It has **no opinion about which tag belongs on which exercise**, and it must not acquire one:
`scripts/review/test_clinical_import.py` fails if a heuristic mapping content to a tag ever appears
in that module. Your judgement is the thing this repository does not have, and the thing it must not
manufacture.

`reviewer_credentials` and `reviewer_authority` are required and the import refuses a submission
without them. This is the field CT-1's content-review importer deliberately does **not** have: a
content reviewer needs no licence, a clinical one does, and the distinction has to survive being
written down.

Answers to Q1–Q7 in prose alongside the two files.

---

## 8. Version binding

A review is only valid for the catalogue it was performed against. Record with your result:

```text
catalogue_file    mobile/assets/data/exercises_vendor.json
catalogue_sha256  d9de3a740f9cc3d20e5ee994170969fe90bbdb7549444f5330483b904f3197c8
catalogue_bytes   3127495
rows              1887
tagged/untagged   1527 / 360
handoff_commit    a18e0daa5727fd9f104a2dc57f083ef82f097400
tag_source        core/contraindications/*.csv
```

The load-bearing half is the **digest**. `handoff_commit` names the commit the worklist was generated
at, and it is necessarily one behind the commit that records it — a pin cannot name its own commit.
That off-by-one is bounded and harmless: the commit it names contains this document and this
worklist, and the only thing that can change underneath a review is the catalogue, which the digest
covers exactly. Check the digest; the commit is for finding the sources afterwards.

A **digest and a commit**, not a branch. The previous version of this section named the branch
`formcoach/gates-a-c`, which is a moving pointer: it advanced three commits while this document sat
unchanged, so a review "against the branch" could not be tied to anything. A review is only valid for
the exact bytes it was performed against, and those bytes now have a name.

Verify the pin before you start:

```bash
sha256sum mobile/assets/data/exercises_vendor.json
```

If it does not match, this handoff is stale — ask for a regenerated worklist rather than reviewing a
catalogue nobody has recorded. `scripts/review/clinical_import.py --check` performs the same check
and refuses a submission that names a different digest.

If the catalogue changes after your review, the delta is unvalidated until reviewed. That is the
mechanism by which "validated once" does not silently become "validated forever".

---

## 9. Where the evidence lives

| Subject | Path |
|---|---|
| Exercise catalogue | `mobile/assets/data/exercises_vendor.json` |
| Per-row tag provenance | `core/contraindications/*.csv` |
| The review flag and disclosure | `mobile/lib/features/equipment/state/safety_coverage_providers.dart` |
| Eligibility and whole-person blocks | `mobile/lib/features/safety/data/eligibility.dart` |
| Declared health answers | `mobile/lib/features/safety/data/health_flags.dart` |
| PAR-Q+ screening | `mobile/lib/features/safety/data/par_q.dart` |
| Decision history | `core/DECISION_LOG.md` |
| The worklist and its validator | [core/review/worklist/](core/review/worklist/), [scripts/review/clinical\_import.py](scripts/review/clinical_import.py) |

---

## 10. Honest summary of the current position

The engineering work is done to the boundary of what engineering can decide. The screening layer is
deterministic, auditable, fails closed for prescriptions, fails open for browsing, states its own
gaps to users, and refuses outright in four whole-person states.

What it cannot do is tell you whether the tags are *right*. 1,527 rows carry assignments that no
clinician has seen, 360 carry none, and four declared restrictions cannot be screened at all. The
product says so on screen today.

**That is why D1 and H3 exist, and they stay in force until this document comes back answered.**

A returned worklist that passes `--check` does **not** close them either. It establishes that a
named, credentialled reviewer gave structurally valid answers about specific rows of a specific
catalogue version. What the app should then do — particularly with a row marked `UNKNOWN`, and
whether `exercise_filter.dart:38` should stop returning `false` for untagged rows — is a separate
decision that no validator has authority over. The audit's own instruction stands: do not flip that
line to fail-closed before D1 answers.
