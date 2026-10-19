# AI Coach transaction/offline product tradeoff proposal

Date: 2026-10-19  
Repository: `D:\Repo\Fitness_App_aicoach`  
Branch: `docs/ai-coach-tdd-001`  
Baseline: `2556ff7d` (`docs(ai-coach): record GPT-PM contract acceptance`)  
PM Bridge request: `e0b7b888-d2a4-4dfd-a3b9-f73e52a38fed`  
PM Bridge job: `0be741fe-3e0b-4792-b962-7a098942453b`  
Change type: documentation-only technical design proposal; no product disposition received.

## Baseline and scope

Immediately before this follow-up, `git status --short --branch` showed the branch at `2556ff7d`, 96 commits ahead of upstream, with no tracked modifications and one pre-existing untracked change record `core/changes/2026-10-18-ai-coach-phase9-gptpm-transport-followup.md`. That file was not opened or modified. The scope is the open technical design for the accepted product boundary “voice is a second input to the existing workout flow.” No runtime, schema, policy, test, or production change is included.

## Source evidence and decision proposal

`WorkoutSessionRepository.save` replaces the full `WorkoutSession` document and returns normally after its four-second timeout (`mobile/lib/features/workouts/data/firestore_workout_session_repository.dart:61-70`). `LogSessionAction.log` accepts a widget-held snapshot and reports ordinary `AsyncValue.data` after the repository call (`mobile/lib/features/workouts/state/workout_session_providers.dart:89-110`). The two widget callers are `_MarkCompleteButton` and `_AddExerciseButton` (`mobile/lib/features/equipment/workout_player_page.dart:669-748,961-1023`). `SetCapture` contains weight/reps but no stable set identity (`mobile/lib/features/workouts/data/set_capture.dart:8`). The app constrains `cloud_firestore` to `^6.3.0` (`mobile/pubspec.yaml:46`).

Official Firebase documentation states that Firestore transactions fail offline, transaction callbacks can rerun after conflicting changes, and offline writes synchronize later with last-write-wins for multiple changes to one document: [transactions](https://firebase.google.com/docs/firestore/manage-data/transactions), [offline behavior](https://firebase.google.com/docs/firestore/manage-data/enable-offline).

The technical proposal in `docs/ai-coach/03_DESIGN.md` §0.4 recommends typed commands using a transaction over the latest existing session document, stable set IDs, identical-replay no-op, changed-payload conflict, and an explicit `NOT_SENT_OFFLINE` result. It would retain the captured set only in the current UI and would not start rest or claim persistence. `UNKNOWN` after a sent request remains unresolved until a server-backed read confirms the operation. The alternative is a keyed offline-operation representation that changes all readers/export and requires cross-version compatibility; the proposal does not treat this as approved scope.

This recommendation removes durable offline set logging for these mutations. GPT-PM must decide whether that tradeoff fits the accepted product goal. No code GO, implementation authorization, schema/migration approval, clinical sign-off, or production authorization is implied.

## PM Bridge attempt

The request was intended to ask for a product-only ACCEPT/MODIFY/REJECT on the offline tradeoff, explicitly excluding implementation authorization. Job status was read back with `pm_bridge_job_status`: `failed`, `sendPhase=not-started`, `ATTACHMENT_NOT_LANDED`, missing `03_DESIGN.md`, `attempts=1`, `sendSnapshot=null`, `userTurnId=null`, `replyId=null`. A same-ID retry returned the unchanged persisted job and payload hash; the attempt count remained one, with no send snapshot, user turn, or reply. Nothing was sent, no new request ID was created, and no GPT-PM reply or decision exists.

## Files changed

- `docs/ai-coach/03_DESIGN.md`: added §0.4 options, recommendation, result states, compatibility and verification boundaries; recorded the pre-send PM Bridge failure.
- `docs/ai-coach/02_BACKLOG.md` and `00_README.md`: marked the product tradeoff as pending and linked the design section.
- `reports/AI_COACH_STATUS_2026-10-19.ru.html` and `.html`: updated the status matrix and ordered next actions with the exact failed-send evidence and owners.
- `docs/DOCUMENT_REGISTRY.md`: regenerated derived document counts.
- This record documents the change and its verification limits.

## Verification and remaining acceptance

No tests, project checks, builds, CI, migrations, runtime actions, alert sends, production changes, push, or merge were performed. One `git diff --check` was run inadvertently despite the prior restriction; it reported no whitespace errors and only LF/CRLF line-ending warnings. It was not repeated. Read-only review covered the cited source boundaries and the diff; the HTML pair was conformed using the repository report formatter. The product decision remains pending because the PM Bridge attachment did not land. PM Bridge attachment-transport ownership is not established by this repository evidence. The operator remains accountable task owner, Codex is technical owner/executor, and GPT-PM owns the product decision. Runtime implementation still needs the explicit code-sprint GO and the technical compatibility gates described in §0.4.
