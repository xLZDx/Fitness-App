# How to review

Two files. Fill both, send both back.

## 1. `worklist.csv` — 1887 rows

Open it in a spreadsheet. The first eight columns are what the app currently
holds; the last three are yours:

| Column | What to put in it |
|---|---|
| `disposition` | one of `ACCEPT`, `REJECT`, `AMEND`, `UNKNOWN` |
| `tags` | **only** when the disposition is `AMEND`: the tags this row should carry, space-separated, drawn from the list below. Leave empty for the other three. An `AMEND` with an empty `tags` cell means *this row should carry no tags* — that is a real answer and it is not the same as leaving the row blank. |
| `rationale` | free text, optional |

The vocabulary, and nothing outside it — a tag the app cannot match is
invisible to every safety filter, so it looks like a screened row and behaves
like an unscreened one:

    ankle elbow hip knee lower_back neck shoulder upper_back wrist

**`UNKNOWN` is a real answer.** A row whose content does not let anyone decide
should be marked `UNKNOWN`, not guessed at. Nothing downstream treats it as a
failure to answer.

**Leave a row blank if you did not review it.** A blank row is recorded as NOT
REVIEWED. It is never recorded as accepted, and a partial review is welcome —
a partial review recorded as a whole one is not.

## 2. `submission.json`

Seven lines. Your name, your registration and issuing body, what you are
entitled to sign off on, and the date. `catalogue_sha256` and `handoff_commit`
are filled in already: they pin this review to the exact bytes you reviewed,
so please do not edit them.

The credentials and authority fields are required and the import refuses a
submission without them. That is deliberate: an anonymous clinical review
cannot be attributed to anybody, and this repository has no way to tell a
clinician's judgement from a developer's guess except by who signed it.

## 3. Send it back

Both files. It is checked with:

    python scripts/review/clinical_import.py --check submission.json

That check is a **structural** one — required fields, a tag vocabulary, rows
that exist, no row reviewed twice, and the catalogue digest. It has no opinion
whatsoever about which tag belongs on which exercise. That judgement is the
thing we are asking you for and the thing we must not manufacture.

If the catalogue changes before your review comes back, the check refuses the
submission as STALE and we reissue the worklist. Your work is not discarded.
