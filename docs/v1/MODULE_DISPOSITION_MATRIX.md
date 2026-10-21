# FitnessUp v1: module disposition matrix (2026-10-21)

Status: proposal from a read-only scan of `mobile/lib/features` on master `dc124bbc` (46 directories). Dispositions are decided by the operator. "KEEP" means the module stays in the v1 build, "HIDE" means its entry points are closed in release builds by the demo-feature gate or a default-off provider, "DEFER" means unwired code that stays in the repository untouched. Nothing is deleted. Method limits: the scan used directory names, doc comments, file counts and imports of `features/<module>/` from outside the module; it did not run the app, so reachability from menus and flags is only confirmed where noted.

v1 focus areas used as the yardstick: gym/home/outdoor fitness, nutrition, body, AI voice coach, equipment recognition, verified 2D gym maps, optional GPS gym attendance, plus the platform plumbing every app needs.

## KEEP (v1 areas)

| Module | Files | v1 area | Note |
|---|---|---|---|
| workouts | 40 | fitness | core logging; set logging follows `LOCAL_QUEUE_DECISION.md` |
| equipment | 31 | fitness, equipment | machine pages, exercise reference |
| programmes | 12 | fitness | wired in `main.dart` only |
| training_context | 3 | fitness | where the session happens (gym/home/outdoor) |
| recovery | 4 | fitness | deload signal text |
| safety | 7 | fitness | age policy, cautious selection |
| form_check | 40 | fitness, body | camera-based form check |
| posture | 4 | body | static posture check |
| modes | 17 | platform | mode chooser/switcher; outdoor cycling and hiking stay closed by the capability policy |
| home | 8 | platform | Day-3 modal is off by default |
| activity | 57 | fitness | unified activity journal |
| recording | 53 | fitness | GPS recorder; the start screen still lists hiking and cycling (`kGpsStartSports`), which v1 defers (package rows FU-AC-084/085) |
| progress | 5 | body | |
| progress_photos | 35 | body | |
| body_scan | 48 | body | |
| body_comp | 1 | body | Navy-formula estimate |
| cycle_aware | 1 | body, nutrition | |
| goal_photo | 1 | body | vision plan from a goal photo; confirm it is reachable before claiming v1 |
| food_diary | 32 | nutrition | |
| nutrition_plan | 37 | nutrition | |
| ai_coach | 5 | AI coach | |
| ai_planner | 5 | AI coach | |
| voice | 1 | AI coach | parser only; a streaming voice runtime does not exist yet |
| personalisation | 5 | AI coach | adaptive fitness model |
| scanner | 17 | equipment | QR/camera scan |
| visual_equipment | 35 | equipment | recognition |
| auth | 7 | platform | |
| onboarding | 23 | platform | |
| profile | 11 | platform | Coaching section is hidden in release (see HIDE) |
| settings | 1 | platform | |
| subscription | 11 | platform | Supporter subscription stays (operator decision 2026-10-21) |
| account_deletion | 5 | platform | |
| data_export | 8 | platform | |
| legal | 3 | platform | |
| licences | 1 | platform | public page |
| about | 1 | platform | public page; its donor-wall button now requires sign-in |
| splash | 1 | platform | |

## HIDE (closed in release builds)

| Module | Files | How it is closed | Where |
|---|---|---|---|
| marketplace | 4 | `/coaches` joined `isDemoGatedPath`; Profile Coaching section hidden | PR 15 |
| community | 4 | `/community` demo-gated; Profile Community section hidden | existing gate |
| celebrity_plans | 4 | `/celebrity-plans` demo-gated | existing gate |
| social_feed | 4 | reached only through `/community` | existing gate |
| catalog | 5 | `/contribute` and `/moderate` demo-gated (video contribution and moderation) | existing gate |
| moments | 5 | Day-3 modal off by default (`day3WelcomeModalEnabledProvider`); the injury-filter moment has no consumer | PR 16 |

## KEEP, login required

| Module | Files | Note |
|---|---|---|
| donor_wall | 5 | `/donors` is no longer public (PR 15). Firestore `donor_wall` stays publicly readable by the donors' own opt-in, so the login requirement is a UI choice, not a privacy boundary |

## DEFER (unwired, left in the repository)

| Module | Files | Evidence |
|---|---|---|
| buddy | 1 | no importer anywhere in `mobile/lib` (BLE presence sharing) |
| sdk_export | 1 | no importer anywhere in `mobile/lib` (white-label SDK foundations) |

## Not in the tree yet (v1 areas with no module)

Verified 2D gym maps, the gym digital twin and GPS gym attendance have no module in `mobile/lib/features` today (grep on the integration candidate was empty; see `ATTENDANCE_SPEC_AMENDMENT.md`).

## Open checks before any "reachable in v1" claim

- Confirm menu and route reachability of goal_photo, cycle_aware, body_comp, personalisation, training_context, recovery and safety: they have no importer in the `features/<name>/` path form, so relative imports may exist.
- The provider overrides in `main.dart` for marketplace, donor_wall and moments remain; they are wiring only.
