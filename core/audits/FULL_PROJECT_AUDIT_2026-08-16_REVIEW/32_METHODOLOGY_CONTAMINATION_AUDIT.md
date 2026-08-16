# 32 - Systematic methodology contamination audit

Registers: `METHODOLOGY_ERROR_REGISTER.csv` (5 errors), `CONTAMINATED_CLAIMS_REVALIDATION.csv`
(12 claims). Neither the first audit nor any product file was modified.

## The headline

The first audit disclosed two methodology errors. This sweep found **three more, and all three are
mine** - two in the second-order review's own correction pass, one of which **invalidates a
correction I published**. The error class did not stop at the first audit; it propagated into the
review of the first audit.

## The taxonomy

| ID | Owner | Category | One-line failure |
|---|---|---|---|
| E01 | first audit | naive reference counting | counted files, not occurrences |
| E02 | first audit | wrong denominator | hand-built "engine directory" list omitted two real consumers |
| E03 | this review | semantic inference from lexical match | name collision: read a sibling field and called it a use |
| E04 | this review | non-existence from a narrow search | never searched `functions/src` before declaring a subsystem absent |
| E05 | this review | naive reference counting, second order | a doc-comment mention counts as an occurrence |

Categories from the mandate that produced **no** error here, and why:
`generated Riverpod code` - the project has no `riverpod_generator`, `freezed`, `json_serializable`
or any `.g.dart`/`.freezed.dart` under `lib/`, so no reference could hide in generated source;
`path/version confusion` - one worktree, one HEAD, verified;
`duplicate counting` - the finding register was checked for duplicates and had none;
`production/test/dead-code mixing` - test directories were separated in every re-count.

## E05 and what it cost

`E01` corrected "15 dead providers" to 7. That correction was itself wrong. Stripping comment lines
before counting yields **10**, and raw grep at source confirms each of the three additions:

- `fitnessProfileProvider` (`personalisation_providers.dart:12`)
- `safetyVerdictProvider` (`safety_providers.dart:17`)
- `draftSafetyVerdictProvider` (`safety_providers.dart:31`)

Each is mentioned only in prose. Nothing watches any of them.

**This reverses a published correction.** In `06` and `29` I downgraded F001 from HIGH to MEDIUM,
arguing that although the catalogue's `difficulty` column is degenerate (1,877 of 1,887 `beginner`),
a real level signal exists because `fitness_model.dart:115-131` builds a per-muscle estimate from
post-session `DifficultyRating`, *"consumed by `fitnessProfileProvider`"*.

Nothing consumes `fitnessProfileProvider`. The model computes into a void. The first audit's original
claim - *"any filter or selection by level is fiction"* - is correct as written, and **F001 returns to
HIGH**. `07_HIGH_SEVERITY_REPRODUCTION.csv` has been corrected in place; the first audit has not been
touched.

The pattern is worth naming: my correction was more confident than the claim it corrected, and less
carefully checked, precisely because finding an error feels like the end of the work rather than the
start of it.

## PASS claims, attacked

The mandate required attacking positive claims, not only findings. Four were re-tested.

- **No health data reaches any model prompt** - held. Three model-input files enumerated, zero
  health tokens in any.
- **196 providers** - held exactly.
- **32 routes, none dead** - **false negative.** `/team/:teamId` has no navigation call site anywhere
  in `lib/`; the only references are the router declaration (`app_router.dart:349`) and a reachability
  test asserting the route exists. `/splash` and `/progress`, which the same automated pass also
  flagged, are live - via `initialLocation` (`:184`) and the shell tab list (`main_shell.dart:16`)
  respectively. Two of three flags were noise; one was real. INFO severity.
- **No Firebase Storage** - **corrected.** See E04. Right conclusion, false evidence.

## A new dead-safety-code finding

`safetyVerdictProvider` and `draftSafetyVerdictProvider` are complete, correct screening providers
that nothing watches (C12). The live screening path runs through the eligibility layer instead, so no
user goes unscreened because of this - but two implementations of the same safety decision exist and
one is unreachable, which is how the *next* divergence gets introduced.

## What this changes about the second-order verdict

Not the direction, and not for the better. Every reproduced BLOCKER and CRITICAL was established by
**direct source reading**, which no error in this taxonomy touches. What changed is the tally of
first-audit mistakes: one of the two I recorded against it (F001 overstated) was **my** mistake, not
its. The scorecard in `29` is now too harsh on the first audit and was too generous to this review.

## Coverage limit, stated plainly

Twelve claims were revalidated. That is every claim I could identify as lexically derived, but the
identification itself was made by reading the first audit's stated methods - and an audit that
misdescribes its own method would not be caught by this sweep. Sixteen MEDIUM/LOW/INFO findings
remain `NOT_REVIEWED`.
