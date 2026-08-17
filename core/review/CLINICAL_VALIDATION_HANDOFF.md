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
is no tag to screen it against. It is **withheld**, not shown-and-hoped. The app states that it
could not screen it rather than silently passing it.

This was audit finding F013, originally raised as a fail-open. A blinded second reader disagreed and
the code was re-read: it withholds. The finding is recorded as **contested and not upheld**.

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
They are currently **withheld** from any user with a declared injury. Should they be:
(a) assigned tags — and by what process; (b) left permanently `UNKNOWN` and withheld;
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
such. The result must be a document containing:

| Field | Meaning |
|---|---|
| `reviewer` | Name |
| `credentials` | Registration/licence and issuing body |
| `authority` | What you are entitled to sign off on |
| `date` | Review date |
| `scope` | What you reviewed, and explicitly what you did not |
| `catalogue_version` | The catalogue this applies to — see section 8 |
| `reviewed_rows` | Which rows, by id or by defined subset |
| `approved_mappings` | Assignments confirmed correct |
| `rejected_mappings` | Assignments that are wrong, with the correct value |
| `unknown_mappings` | Assignments you cannot resolve, and why |
| `limitations` | What this review does **not** establish |
| `required_corrections` | Changes that must be made before the disclosure changes |
| `approval_boundary` | The explicit statement of what is and is not approved |

Answers to Q1–Q7 in prose alongside.

**Anything not covered by `scope` remains unvalidated.** A partial review is welcome and useful; a
partial review recorded as a whole one is not.

---

## 8. Version binding

A review is only valid for the catalogue it was performed against. Record with your result:

- **Catalogue file:** `mobile/assets/data/exercises_vendor.json`
- **Row count at review time:** 1,887
- **Tagged / untagged:** 1,527 / 360
- **Branch:** `formcoach/gates-a-c`
- **Tag source:** `core/contraindications/*.csv`

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

---

## 10. Honest summary of the current position

The engineering work is done to the boundary of what engineering can decide. The screening layer is
deterministic, auditable, fails closed for prescriptions, fails open for browsing, states its own
gaps to users, and refuses outright in four whole-person states.

What it cannot do is tell you whether the tags are *right*. 1,527 rows carry assignments that no
clinician has seen, 360 carry none, and four declared restrictions cannot be screened at all. The
product says so on screen today.

**That is why D1 and H3 exist, and they stay in force until this document comes back answered.**
