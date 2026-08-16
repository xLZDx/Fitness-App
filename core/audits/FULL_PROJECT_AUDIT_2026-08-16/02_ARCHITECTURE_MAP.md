# 02 — Architecture map

Measured by walking the tree on 2026-08-16, not read from a document.

## Scale

| Layer | Count |
|---|---|
| Flutter production `.dart` under `mobile/lib` | 316 |
| Dart tests under `mobile/test` | 264 files |
| Cloud Functions TypeScript under `functions/src` | 6 production + 10 test |
| Python tooling (`scripts/`, `tools/`) | 77 |
| Shipped JSON datasets | 6 |
| ML model artefacts | 1 (`equipment_v1.tflite`, 4.29 MB) |
| Poster images on disk | 2,989 |
| Video files in the repository | **0** — clips are served remotely |
| Markdown docs under `core/`, `docs/`, `runbooks/` | 129 |
| Total files inventoried | 1,058 (784 production, 274 test) |

## Feature surface — 37 directories under `mobile/lib/features`

about · account_deletion · ai_coach · ai_planner · auth · body_comp · buddy · catalog ·
celebrity_plans · community · cycle_aware · data_export · donor_wall · equipment · form_check ·
goal_photo · home · legal · licences · marketplace · moments · onboarding · personalisation ·
posture · profile · programmes · progress · progress_photos · recovery · safety · scanner ·
sdk_export · settings · social_feed · splash · subscription · visual_equipment · voice · workouts

## Core — 11 directories under `mobile/lib/core`

assets · camera · diagnostics · firebase · health · licences · notifications · router · settings ·
theme · wear

## State and navigation

- **196 Riverpod providers** declared across `lib/`. Only **5** are `autoDispose`.
- **32 GoRouter paths**, zero duplicate path declarations.
- **15 providers have no consumer anywhere in `lib/` or `test/`** — listed in `28_DEAD_CODE_AUDIT.md`.

## Backend

`functions/src/index.ts` plus `account_export.ts`, `abuse_guard.ts`, `scaling.ts`, `tiers.ts`,
`video_urls.ts`. Firestore security lives in `firestore.rules` (130 lines). Video delivery is a
signed-URL flow (`clipUrl` / `clipUrls`) with a per-uid daily quota in `abuse_guard.ts` — which is
why 0 video files ship in the app.
