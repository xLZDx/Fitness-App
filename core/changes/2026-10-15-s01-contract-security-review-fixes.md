# S01: GPS privacy contract revised after the security review

Date: 2026-10-15. Branch: `phase2/s01-contracts`.

## What changed
- `docs/phase2/s01/GPS_LOCATION_PRIVACY_CONTRACT.md`: now 94 requirements (GPS-PRIV-001..094, all PROPOSED). 001..070 keep their numbers (18 have amended text); 071..094 are new (owner-wildcard shielding, C2 gating, publish validation, public document vs private registry, deletion sweep map and failure path, secondary-store erasure windows, EXIF quarantine and full re-encode, third-party egress, backup exclusion and at-rest protection, unlisted-link rules, "known adult" definition, retention of report evidence and consent records, export links). Section 13 is a review disposition table (no finding rejected; findings 6, 9 and 15 accepted with qualifications). D-16 and D-17 stay open decisions with more options and unchanged recommended defaults.
- `docs/phase2/s01/DATA_LIFECYCLE_MATRIX.md`: rows C2, C3, C10 reworked, new deletion sweep map (one row and one acceptance test per store), four new gaps.
- `core/DECISION_LOG.md`: one entry.

## Why
Security review (Sonnet 5.5, medium) of the drafts at `d58ff1d6` returned 15 findings: 1 BLOCKER (the owner wildcard in `firestore.rules:61-82` makes a per-collection block ineffective), 11 MAJOR, 3 MINOR.

## Affected contracts and paths
Documentation only. No code, rules or flags changed.

## Verification state
No tests or checks run. The writer re-checked the wildcard exclusion lists, the hardcoded `sweepAccountData` list and `backup_rules.xml` against the files. Not verifiable from the repository: Storage soft-delete and versioning, Firestore PITR and backups, Cloud Logging retention, CDN behaviour. Numeric parameters in 074, 087, 091, 093, 094 are starting proposals. The 18-boundary formula in 088 is unverified arithmetic. A second security review round, GPT-PM review and operator approval are pending.
