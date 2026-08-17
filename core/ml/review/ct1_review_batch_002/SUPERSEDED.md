# SUPERSEDED — do not review from this directory

`CT1_REVIEW_BATCH_002` was replaced by **`CT1_REVIEW_BATCH_003`** before any reviewer returned a
submission against it. The live batch, and the pages to open, are in
[core/ml/review/ct1_review_batch_003/](../ct1_review_batch_003/).

## Why

The baseline's duplicate checks reported the second and later occurrence **in catalogue file order**,
so which member of a duplicate group got flagged was a fact about the file's layout rather than about
its content. Reordering the catalogue without changing a character would have moved rows in and out
of the flagged stratum. Fixed to a deterministic representative (the lowest id in the group), which
changed the flagged holdout population from 56 to 55 and moved two rows in and out of the batch.

Found by a test written during this gate's own review, asserting that selection is a function of the
row id.

## What that means for anything in here

The row assignments in `assignments.json` are **not** the live ones. A submission produced from
`app/review_R*.html` in this directory will be refused on import: the batch id does not match, and
two of the rows are not in the live batch.

This directory is kept rather than deleted so the supersession is checkable — `test_review_batch.py`
rebuilds against `items.json` here and asserts the move was the small explained one and not a
reshuffle.

Deleting it is an operator call, not one this session took: a shared checkout means a shell hook
guards recursive deletes, and the honest alternative to slipping past that guard is to leave the
files and label them.
