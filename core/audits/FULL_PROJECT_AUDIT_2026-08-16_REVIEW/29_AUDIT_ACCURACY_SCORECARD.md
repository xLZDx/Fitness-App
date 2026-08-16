# 29 - Accuracy scorecard for the first audit

**Denominators are stated. Where one is not defensible, no percentage is given.**

## Findings precision

| Class | Count | Basis |
|---|---|---|
| REPRODUCED_VERIFIED | 9 of the 11 re-tested | every BLOCKER, every CRITICAL, and 4 HIGH re-read at source |
| PARTIALLY_SUPPORTED | 2 | F001 (severity overstated), F003 (denominator not provable) |
| FALSE_POSITIVE | **0** | none of the re-tested findings collapsed |
| DUPLICATE | 0 among those re-tested | |
| STALE | 0 | the only commit since audit HEAD touched no source file |

16 of 27 findings (the MEDIUM/LOW/INFO tail) were **NOT_REVIEWED** in this pass. That is a real
limit of this review, not a clean bill for them.

## Numeric accuracy

**23 of 23 metrics reproduce exactly** from the shipped assets, independently recomputed without
opening the first audit's CSVs: 1,887 rows, 0 duplicate ids, full EN/RU parity, `summary == steps[0]`
in both languages, 0 broken equipment references, 0 missing posters, 503 without `equipmentId`, 360
without a contraindication tag, 1,484 without `purpose`, 1,877 `beginner`, 19.1%, 69 machines, 4
empty, 540 pose targets, 1,764 male and 775 female clips, 196 providers.

Both provider counts reproduce, including the wrong one: the flawed file-count method still yields
exactly 15 and the corrected occurrence method still yields exactly 7.

## Where the first audit was wrong

1. **F001 overstated.** "Any filter or selection by level is fiction" does not survive a full
   consumer trace. `fitness_model.dart:115-131` builds a per-muscle fitness estimate from the user's
   post-session `DifficultyRating`, decayed over 90 days, consumed by `fitnessProfileProvider`. A
   real level signal exists; it is earned rather than declared. HIGH -> MEDIUM.
2. **F003's denominator is not provable.** "14 of 37" - the 37 were hand-enumerated and omit at
   least `MotivationPrefs.preferredDuration`, which is genuinely consumed. Should read "at least 14".
3. **Three findings have no remediation task** (F002, F009, F011).
4. **Seven of the mandate's 38 artefacts were not produced**, plus two more partially. Disclosed in
   the README with a reason for each, which is the right handling, but it is still a coverage gap.

## Where it was right

- Every BLOCKER and CRITICAL reproduces at source.
- Its two disclosed self-corrections both reproduce, and the root cause it named was correct.
- Its internal counts are consistent across the summary, the register and the plan.
- It recorded its own errors rather than quietly fixing them - which is what let this review find a
  **third** instance of the same error class in its own re-test.

## Methodological weakness, stated plainly

The first audit's dominant method was textual search over Dart source. That method produced two
disclosed errors and one more discovered here. Every finding derived primarily from grep was
re-tested by occurrence counting with name collisions checked by hand; all survived. The findings
derived from direct source reading - which is every BLOCKER and CRITICAL - were never at risk from
this defect.

## The limit of this scorecard

**The first audit and this review share an author.** The only genuinely independent input is the
blinded adversary, which was denied access to the audit directory and the decision log. Until its
report lands, treat every "REPRODUCED_VERIFIED" here as *the same reader reaching the same
conclusion twice*, which is weaker evidence than it looks.
