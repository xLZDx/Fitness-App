# SUPERSEDED — DO NOT REVIEW, DO NOT IMPORT

`CT1_REVIEW_BATCH_001` was replaced before any reviewer returned a submission against it. The live
batch is **`CT1_REVIEW_BATCH_003`**, in
[core/ml/review/ct1_review_batch_003/](../ct1_review_batch_003/).

## Why

001 was built at **review schema v1**: five questions, verdicts `ok` / `problem` / `cannot_judge`, no
reason codes, no per-row content digest, no review timestamp and no review status. v2 added all of
those. A v1 answer cannot carry them, so reading a v1 submission under v2 would be guessing what the
reviewer meant.

002 then replaced 001 for that schema change (same rows), and 003 replaced 002 because the rows moved
— the baseline's duplicate checks were selecting the flagged member of a duplicate group by position
in the catalogue file rather than by a property of the rows. See
[../ct1_review_batch_002/SUPERSEDED.md](../ct1_review_batch_002/SUPERSEDED.md).

## This is enforced, not merely stated

`review_batch.assert_authoritative()` refuses to generate reviewer pages from, or build an evaluation
dataset out of, any batch whose id is not the authoritative one. `review_batch.check_contract()`
separately refuses a manifest whose recorded question set, verdicts, reason codes, statuses or schema
versions are not the ones the current code implements — which 001's are not.

Both refusals are mutation-tested: break either and a test goes red.

## Why it is kept

Historical evidence, not clutter. `test_review_batch.py` rebuilds the current selection against
`002/items.json` to assert that the 002 → 003 move was the small explained one and not a reshuffle.
Deleting the record would delete the ability to check the claim.

There is nothing sensitive here: no reviewer names, no submissions, only catalogue content that ships
in the app and the baseline's own rule output.
