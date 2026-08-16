# SPTR Full Catalog (1887) — Independently Verified Audit, Final Summary

**Date:** 2026-08-15
**Source catalog:** `D:/Repo/Fitness_App/mobile/assets/data/exercises_vendor.json` (1887 exercises, verified 1:1 by id against every audit file below)

## What this supersedes

The original ChatGPT-produced audit package (`SPTR_FULL_CATALOG_1887_PATTERN_AUDIT_2026-08-15.html` +
`SPTR_FULL_CATALOG_1887_MISMATCH_MATRIX_2026-08-15.csv` + `SPTR_FULL_CATALOG_1887_ISSUE_MATRIX_2026-08-15.csv`)
claimed **519 flagged** (P0 1 / P1 149 / P2 369). Every one of its 609 individual findings was checked
against the real exercise text in `exercises_vendor.json`, plus (Gate A) against the referenced prior
REV2 round (`SPTR_H3_REV2_ACTION_REGISTER_2026-08-15.md`, 135 cards, id-set verified identical, 0 diff).

## Final numbers

| Status | Originally claimed | Independently confirmed |
|---|---|---|
| P0 | 1 | 1 |
| P1 | 149 | **49** |
| P2 | 369 | **149** |
| PASS | 1368 | **1688** |
| Total flagged | 519 | **199** |

**305 of the original 609 findings (50%) were false positives** — the claimed phrase/pattern was
absent from the real text, usually because the real text already contained the *correct* wording the
audit was recommending (e.g. flagging "flat back" when the text already said "neutral spine";
flagging "knee behind toes" when the text already said "knee tracking over the toes"; flagging vague
timing when the text already said "hold for a second").

**135 PRIOR_REAUDIT findings (Gate A)** referenced an earlier REV2 round. That source file was located,
its 135-card id set matched exactly, and each of its 191 individual requirements was checked against
current text: 80 were already resolved in the live data (the requested wording is already present
verbatim), 55 are genuinely still open.

## Files

- `SPTR_FULL_CATALOG_1887_FINAL_VERIFIED_2026-08-15.csv` — one row per exercise (1887), `final_priority`
  + `confirmed_real_issue_codes` columns. This is the authoritative per-exercise result.
- `SPTR_FULL_CATALOG_1887_FINAL_ISSUES_2026-08-15.csv` — one row per individual finding (609), with
  `verified` (REAL/FALSE_POSITIVE) and `verification_note` citing the concrete evidence for every row.

## Known gaps (not covered by this verification pass)

1. Quality of the `proposed_steps`/`proposed_purpose` replacement text for the 199 confirmed-real rows
   has not been checked — only whether the underlying finding claim itself is true.
2. The 1484 no-purpose cards' poster images have not been visually inspected (1752 image files) —
   file-existence only (2539/2539 confirmed present).
3. The interactive HTML page has not been regenerated against these final numbers.
4. `exercises_vendor.json` itself has not yet been edited — this is a verification pass only, no
   remediation has been applied to the production data.
