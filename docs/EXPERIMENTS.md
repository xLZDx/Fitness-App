# Experiments register

Definition (operator rule 2026-10-15): a feature planned after 2026-10-10 that is present in the Phase 1 code line is an experiment. It stays flag OFF by default, receives no new work in Phase 1 and is developed only in Phase 2. Provenance of all feature folders: `docs/phase2/plan/01_PROJECT_REASSESSMENT_2026-10-15.md` section 4.1.

Current state: no experiment code is in the Phase 1 line (`phase1/main` = tag `phase1-baseline` at `42d1b849`). The Body Scan + Nutrition Coach sprint (PR #5, approved head `cd9d7c3a`) was merged into `phase2/main` on 2026-10-15 (merge commit `5137ccda`).

| Experiment | Folders and server parts | Flags (default OFF) | In Phase 1 line? | Phase 2 home |
|---|---|---|---|---|
| Body Scan | `mobile/lib/features/body_scan`, `functions/src/body_scan` | `BODY_SCAN_CLOUD`, server `BODY_SCAN_BUCKET`, `BODY_SCAN_ACCEPT_UPLOADS` | no | S14 (BODY integration) |
| Nutrition Coach | `mobile/lib/features/nutrition_plan` | none (on-device, adult-only clamps) | no | S14 |
| Food diary and scanning | `mobile/lib/features/food_diary`, food callables | `FOOD_AI`, `FOOD_LOOKUP` | no | S14 |
| Activity foundation | `mobile/lib/features/activity` | none (no UI) | no | S02 |

Boundary case ruled by the operator (D-1b): `training_context` stays in Phase 1.

Rule: a new row is added when an experiment appears in `phase1/*`; a row is closed when the feature is removed from the Phase 1 line or the operator reclassifies it.
