# SPTR — Full Catalog (1887) Audit Status and Gap Report

**Date:** 2026-08-15  
**Inputs available in this review:**
- `CARD_403_CONTENT_REMEDIATION_2026-08-15.md`
- `CARD_FULL_CATALOG_AUDIT_2026-08-15.md`
- `H3_PURPOSE_REVIEW_2026-08-15_REV2.html` containing the 403 B3 rows

## What I independently verified

- The REV2 artifact contains exactly **403** exercise cards.
- The 403-card remediation delta is real: **79 unique cards**, **23 Purpose**, **60 Steps**, no title or poster changes.
- The 60 neutral-spine rewrites exactly replace 60 of the 64 original `flat back/back flat` Step hits; the 4 retained hits are surface-contact/posterior-pelvic-tilt contexts.
- Current post-remediation classification for the 403 set is **P0 1 / P1 52 / P2 82 / PASS 268**.

## What `CARD_FULL_CATALOG_AUDIT_2026-08-15.md` states

- Catalog total: **1887**.
- 403 rows have Purpose and are represented in REV2.
- **1484** rows have no Purpose yet.
- On those 1484, the card reports **13** `flat back/back flat` Step hits, **1** summary hit and **0** hits for the selected absolute-claim summary patterns.

## Critical limitation: 1484 rows are not present in the attached review artifact

The actual `mobile/assets/data/exercises_vendor.json` was **not attached and is not available as a Library file in this session**. The companion card gives aggregate counts but does not list the 1484 rows or their complete `title/summary/steps` content. Therefore I can verify the card's methodology and internal arithmetic, but I **cannot truthfully produce an exercise-by-exercise professional verdict for those 1484 from these inputs alone**.

Creating 1484 named PASS/WARN/FAIL rows from only the aggregate card would be fabricated evidence, so this report intentionally does not do that.

## What is needed for the remaining 1484 exercise-by-exercise audit

Provide either:

1. `mobile/assets/data/exercises_vendor.json` (preferred), or
2. a generated full-catalog HTML containing all 1887 rows with `title`, `summary`, `steps`, poster and safety tags.

Then every remaining row can be evaluated with the same schema used in the 403 report:

- Header/title ↔ poster
- equipment / movement identity
- Summary/Purpose ↔ title/poster
- every Step ↔ image/title/description
- neutral-spine / ROM / knee-tracking / landing / joint-position cues
- pain/injury/rehab/posture claims
- absolute/superlative claims
- safety tags / difficulty / prerequisites / regression
- ACE/NASM consistency
- P0/P1/P2/PASS and exact recommended rewrite

## Decision on the three scope options proposed in the card

- **Option 1 (13 flat-back fixes only): insufficient as final QA.** It is safe as a mechanical cleanup, but it does not answer whether the other 1471 rows contain different technique/safety problems.
- **Option 2 (full text-pattern scan across 1887): useful mandatory pre-gate.** Add knee-behind-toes, heel-only drive, forced/max ROM, pain/rehab claims, posture-correction claims, safety superlatives and symptom prescriptions.
- **Option 3 (full professional re-audit): recommended before generating/publishing all H3 Purpose content.** Run by muscle group and save per-exercise evidence/status.

## Current GO/HOLD recommendation

**HOLD H3 bulk propagation.** Close the single P0 in the existing 403 and disposition the P1 set first. Then obtain the full 1887 source and run at least Option 2 plus per-exercise audit for the 1484 before using the 403 style as a generation template.

## Professional baseline

- ACE Exercise Library — proper-form descriptions/photos
- NASM Exercise Library — step-by-step exercise guidance
- NASM progression/regression — controlled pain-free ROM without compensation
- ACE flexibility — stretching should not be painful
- NASM corrective/posture scope — do not turn fitness cues into pain treatment
