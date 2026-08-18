# Metric provenance: the claims a locator must not "fix"

`scripts/ml/evaluation_report.py` checks that every number `core/ml/MODEL_REGISTRY.json`
quotes actually appears in the report it cites. Twenty claims; fourteen match, none
have drifted, and six cannot be located.

This file is why those six are still unlocatable on purpose, and what each one
actually needs. The tempting fix — teach the locator a synonym table, or let it
compute — would make the module assert a mapping its sources never made. That is
the failure this module exists to catch, so it is not permitted to commit it.

**Status: `UNRESOLVED_BY_DESIGN`. Six claims, three distinct causes, none of them
a locator defect.**

## Cause 1 — the source names the metric in Russian (3 claims)

| Registry claim | Source |
|---|---|
| `confidence_min = 0.215` | `core/plans/B1_RECOGNITION_MEASUREMENT_2026-08-07.md:21` |
| `confidence_median = 0.437` | same line |
| `confidence_max = 0.897` | same line |

The line reads:

```
уверенность top-1: min 0.215 · медиана 0.437 · max 0.897
```

Every value is present and correct. The metric NAME is not: `уверенность` is
`confidence`, and `медиана` is `median`. Locating these requires a
Russian-to-English metric table, which is a semantic mapping — precisely the class
of substitution the module forbids. `top_1` ↔ `top-1` is a spelling; `уверенность`
↔ `confidence` is a translation, and a translation is a claim about meaning that
only the document's author can make.

**What would close it:** the SOURCE declaring its own metric names, in a
machine-readable block beside the prose. Not done here: B1 is a dated measurement
record of a specific session, and editing it after the fact to make a downstream
checker happy is how a document stops being evidence.

**Independently confirmed as TRUE, and still NOT_LOCATABLE.** On 2026-08-18 the
shipped v1 artefact was run through the pipeline's own `eval_on_gym_photos.py`
against its own truth file, and reported top-1 confidence `min 0.215 · median 0.437
· max 0.897` — the same three numbers, re-measured. These two facts do not conflict
and must not be collapsed: the claims are true, and this module still cannot read
them, because reading them would require a Russian-to-English metric table it is not
entitled to invent. A verdict of NOT_LOCATABLE has never meant "probably wrong"; it
means "this checker cannot confirm it", and the remedy remains a source that names
its own metrics.

## Cause 2 — the registry states the complement of what the source states (2 claims)

| Registry claim | Source |
|---|---|
| `rejected_by_photo_threshold_0_10 = 0` | `B1_RECOGNITION_MEASUREMENT_2026-08-07.md:18` |
| `rejected_by_live_threshold_0_05 = 0` | same file, line 19 |

The source writes:

```
пропущено фото-порогом    (0.10)     30/30  (100%)
пропущено живым порогом   (0.05)     30/30  (100%)
```

Thirty of thirty photos passed the threshold, so zero were rejected. The registry's
`0` is arithmetically right and textually absent: the source states `30/30`, and `0`
is `30 − 30`. A locator that derived it would be computing evidence rather than
finding it, and a locator that can compute one complement can be argued into
computing others.

**What would close it:** the registry citing what the source says (`passed = 30`,
`of = 30`) instead of the complement, or the source stating the rejection count
directly. Both are edits to a claim or a record, not to the checker.

## Cause 3 — the claim is less specific than the source (1 claim)

| Registry claim | Source |
|---|---|
| `coverage = 0.443` | `core/ml/datasets/content_qa_catalogue_v1/evaluation.json` |

The source has no scalar named `coverage`. It has a `coverage` OBJECT:

```json
"coverage": {
  "heuristic_flags": 264,
  "observations": 1400,
  "rows": 1887,
  "rows_with_any_finding": 836,
  "share": 0.443
}
```

`0.443` is `share`, and `836 / 1887 = 0.4430…` confirms it. But the registry does not
say `coverage.share`; it says `coverage`. Accepting any scalar under a block of that
name would let `264`, `1400`, `1887` and `836` all satisfy the same claim — four
wrong numbers passing a check that exists to catch wrong numbers.

**The checker was doing exactly that, and it was found by writing the test that says
it must not.** When no flattened key matched, `check_claim` fell through to the text
search on the serialized JSON — and proximity in a serialized file is sibling
adjacency, not a statement. `coverage = 264` returned MATCHES: 264 is
`heuristic_flags`, two keys above `share`. The only thing keeping that out of the
real audit was the file's indentation pushing `share` past the 120-character window,
which is to say: nothing. The fallback is gone. A JSON report names its
measurements, and if the name is not there the honest answer is that the claim
cannot be read — a false NOT_LOCATABLE gets reported to a human, a false MATCH is
never looked at again.

Removing it changed no verdict in the current audit (14 MATCHES before and after),
which is the evidence that it was only ever a path to wrong answers.

**What would close it:** the registry citing `coverage.share`. This is the cheapest
of the six and the only one whose fix is purely a matter of precision, but it is
still an edit to what the registry asserts, and the registry is not this module's to
rewrite.

## The one that WAS a locator defect

`abstained_of_30 = 10` was in this list. `mobile/assets/models/README.md:141` states:

```
abstained ('none'):                   10/30 (33%)
```

The stem `abstained` is in the source, in English, and the value is in it as `10/30`
— the source writes the denominator the registry key carries. Nothing had to be
translated or computed, so `_locate_out_of` matches it, and only when the source
contains that exact fraction: `9/30` does not satisfy a claim of ten, and `10/29`
does not satisfy a claim about thirty.

That is the boundary. A spelling the source already contains may be normalized. A
meaning the source never stated may not be supplied.
