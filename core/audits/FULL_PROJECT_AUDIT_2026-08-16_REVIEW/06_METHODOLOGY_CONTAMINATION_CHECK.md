# 06 - Methodology contamination check

**This is the most important artefact in the second-order review.**

## Conflict of interest, stated first

The first audit was produced by the same agent performing this review. Self-review is not
independence. The mitigation is a blinded adversary (§40 stage A) that was given the repository and
the invariants but explicitly forbidden from reading
`core/audits/FULL_PROJECT_AUDIT_2026-08-16/` or `core/DECISION_LOG.md`. Everything below that rests
on my own re-reading should be weighted accordingly.

## The first audit disclosed two self-corrections. Both reproduce.

| Correction | Reproduced | Method |
|---|---|---|
| Dead providers 15 -> 7 | **REPRODUCED_VERIFIED** | The flawed file-count method yields exactly 15 today; occurrence counting yields exactly 7 |
| `heightCm` / `weightCurrentKg` wrongly called unused | **REPRODUCED_VERIFIED** | Both are read by `body_comp/data/body_comp_estimate.dart` and `form_check/data/pose_silhouette.dart` |

## The root cause, and a third occurrence found in this review

Both errors share one defect: **a textual match treated as a semantic fact.**

- The 15 -> 7 error counted *files containing an identifier* rather than *occurrences of it*, so a
  provider consumed in its own file read as dead. `aiCoachServiceProvider` is watched four lines
  below its declaration.
- The body-metric error used an incomplete list of "engine" directories, so consumers in
  `body_comp/` and `form_check/` were invisible to the classifier.

**A third instance appeared while writing this review, in my own re-test.** Re-checking the fourteen
questionnaire fields the first audit called unused, the automated pass flagged `motivation` as
CONTRADICTED, citing `suggestion_builder.dart:135`:

```dart
final targetMinutes = _targetMinutes(profile?.motivation.preferredDuration);
```

That is a **name collision**, not a use. `UserProfile.motivation` is a `MotivationPrefs` object
(`profile_models.dart:874`); the field the first audit called unused is the `String? motivation`
*inside* it (`:825`). The line reads a sibling field, `preferredDuration` (`:831`). Every read of the
string itself is in onboarding, the questionnaire notifier, or Firestore serialisation.

So the correction was itself a false positive from the same class of error, and the original finding
stands.

## Contamination sweep - which findings were grep-derived, and do they survive?

| Finding | Method | Re-tested by | Verdict |
|---|---|---|---|
| F003 (14 fields reach no engine) | grep + directory classification | occurrence counting outside onboarding/profile/l10n, with the collision checked by hand | **REPRODUCED_VERIFIED** - 14 stands, all fourteen |
| F004 (recovery ignores sleep/stress) | same | same | **REPRODUCED_VERIFIED** |
| F010 (7 unreferenced providers) | corrected occurrence count | re-run | **REPRODUCED_VERIFIED** |
| F001 (difficulty inert) | data + grep on consumers | full consumer trace | **PARTIALLY_SUPPORTED - see below** |
| F013, F014, F015, F016, F017, F018 | direct source reading, not grep | re-read | **REPRODUCED_VERIFIED** |

## A denominator that is not provably complete

F003 reports "14 of 37 questionnaire fields". The 37 were enumerated by hand from
`profile_models.dart`. This review found `MotivationPrefs.preferredDuration` - a real field, really
consumed by `suggestion_builder.dart:135` - **which is not among the 37**. The numerator is sound;
the denominator is a hand-built list with at least one known omission and is not provably complete.
The finding should read "at least 14 fields", not "14 of 37".

## F001 was overstated

The first audit concluded that because 1,877 of 1,887 rows are `beginner`, *"any filter or selection
by level is fiction"*. Tracing every consumer of difficulty contradicts the generalisation:

- `sortByTierFit` (`exercise_filter.dart:196-205`) reads the catalogue column. With every row at the
  same grade the comparator returns 0 for all pairs. **Genuinely inert - the specific claim holds.**
- `CatalogLabels.difficulty` (`catalog_labels.dart:62-66`) is display only and works correctly.
- `fitness_model.dart:115-131` reads a **different signal**: `WorkoutLogEntry.difficulty`, the user's
  post-session `DifficultyRating` (tooEasy / justRight / tooHard), weighted by a 90-day linear decay
  into a per-muscle fitness estimate, consumed by `fitnessProfileProvider`
  (`personalisation_providers.dart:12`).

So the app **does** have a working level signal; it is earned from logged sessions rather than
declared in onboarding, and it is untouched by the degenerate catalogue column. The narrow claim is
right and the sweeping one is wrong. Severity accordingly drops from HIGH to MEDIUM.
