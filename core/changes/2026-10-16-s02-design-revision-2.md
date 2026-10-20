# S02 design revision 2 (after architecture, reliability and security review)

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `docs/phase2/s02/S02_DESIGN.md` revised in place: all 24 findings of the three internal reviews (architect A1-A8, reliability R1-R10, security S1-S6) applied, none rejected (section 13): delete fence and late sweep, server tombstone with delete-wins, idempotent commit state machine with same-bytes promotion, purge and recompute bookkeeping with expiry derived at purge time, closed server schema that rejects unknown keys (heart rate never accepted), hardened telemetry callable, local store authority and sign-out behaviour, ownership of the three workout models, consent withdrawal, a permanent four-exclusion rules floor, operations signal table. Section 14 answers the 15 design questions raised by the test plan (proposals).
- `docs/phase2/s01/GPS_LOCATION_PRIVACY_CONTRACT.md`: GPS-PRIV-014 clarified (it concerns the S04 recording journal; the S02 local store is the permanent device copy), GPS-PRIV-064 acceptance reworded for a dedicated private bucket (Storage rules stay deny-all; existing deny-all test plus functions-level tests; per-prefix rules tests only for default-bucket prefixes).
- `docs/DOCUMENT_REGISTRY.md` regenerated.

## Why
Phase 3/5 of S02: the first review round returned NEEDS CHANGES from all three reviewers; remediation is one batch before the GPT-PM review.

## Affected contracts and paths
Documentation only: `docs/phase2/s02/`, `docs/phase2/s01/GPS_LOCATION_PRIVACY_CONTRACT.md`.

## Verification state
No tests or checks were run. The reviewers verified their evidence in code; the writer applied findings without re-reading code. Open items and the three operator-owned questions (cloud stream kinds beyond GPS, the "never" retention option, the default expiry value) are listed in section 12.3. The test plan is committed separately.
