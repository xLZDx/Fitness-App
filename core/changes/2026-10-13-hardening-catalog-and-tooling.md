# Change record: exercise catalog repair, Python tooling hardening, CT-1 inputs

## What changed
### Catalog data (WS5)
- `mobile/assets/data/exercises_vendor.json` and `exercises_vendor.ru.json`: per-row corrections applied from `scripts/catalog/catalog_corrections.json` (absolute, idempotent patches for en and ru). `build_vendor_catalog.py` re-applies them after its merge, so a rebuild keeps them. The diff is per row.
- Gaps before -> after: missing purpose 1484 -> 1; missing muscles 182 -> 2; equipment disagreeing with the title 291 -> 0 (40 `equipmentId` changes: bands, medicine ball, cable/band titles); steps contradicting the equipment 15 -> 0 (`isStretch` fixed on 8 stretch titles); duplicate-steps ids 83 -> 58 (16 camera-view variants got a view cue); truncated names 3 -> 0. The Russian overlay covers every purpose. One half-monkey pose became `beginner`.
- New modules: `catalog_corrections.py`, `catalog_rules.py` (consistency rules shared with the ratchet), `author_catalog_*.py` and `author_purpose_data.py` (provenance of the authored text).
- `scripts/catalog/tag_contraindications.py`: the muscle gate would have dropped 28 committed contraindication tags once muscles were derived; those rows are pinned by id so no tag is lost. 25 tags were added. Tagged rows 1527 -> 1535; the floor in `safety_coverage_test.dart`, `test_tag_contraindications.py` and `test_clinical_import.py` follows.
- `core/review/worklist/*` and `core/review/CLINICAL_VALIDATION_HANDOFF.md` regenerated from the repaired catalogue.
- Ratchets: `scripts/catalog/test_catalog_text_ratchet.py` and `mobile/test/features/equipment/catalog_description_coverage_test.dart` baselines lowered to the new counts; the ratchet now understands the deliberate bench/rack link.

### Python tooling (WS4, F10, F13)
- `scripts/l10n/fix_const.py` honours the `flutter analyze` exit code; `scripts/catalog/verify_clip_signing.py` no longer retries without certificate verification while carrying a token, has timeouts, and checks cleanup statuses; `scripts/ops/firebase_api.py` exits non-zero after an HTTP error; `scripts/ops/upload_video_library.py` targets the current buckets and streams clips; `tools/catalog/json_io.py` writes atomically; `git` calls in the ML, CT-1, review and equipment-identity scripts have timeouts and narrow exception handling; the CT-1 manifest is written LF atomically.
- Tests: `test_fix_const.py`, `test_upload_and_api_hardening.py`, `test_json_io.py`, `test_json_io_atomic.py`, `test_split_group_leakage.py`, `test_catalog_corrections.py`, `tools/evidence/test_validate_csv_evidence.py`.

## Why
The catalogue had missing or contradictory purpose, muscles, equipment and steps text that the app showed to users and the recommendation logic relied on (operator task: fix every discrepancy and gap). The tooling findings let a failed command or an unverified TLS retry look like success.

## Affected contracts and paths
Catalogue row ids are unchanged; `equipmentId` changed on 40 rows. Recommendation results move with the catalogue (the 100-profile suite is the guard). Not fixed by design, listed in the plan's exception register: the quarantined group-label row (no purpose or muscles, pinned by the quarantine test), a relaxation pose with no working muscle, and 58 ids whose steps are identical because the vendor lists one movement twice.

## Verification state
`scripts` and `tools` Python suites: see the commit message of the regeneration step for the final counts; the CT-1 registry is regenerated from an LF checkout of this commit.
