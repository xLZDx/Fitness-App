# AI Coach existing-workout voice contract — GPT-PM MODIFY then ACCEPT

Date: 2026-10-19  
Repository: `D:\Repo\Fitness_App_aicoach`  
Branch: `docs/ai-coach-tdd-001`  
Source baseline: `b7f4a6bd` (`docs: map AI Coach voice operations`)  
PM Bridge request: `2b85df8c-9ec7-41ad-9d41-4aecbf8d9c80`  
PM Bridge follow-up: `3c4bd141-27da-4e5e-a4f0-7a9c6a3e8b2d`  
Change type: documentation-only product disposition and acceptance amendments.

At the start of this follow-up edit, `git status --short --branch` showed this branch at `b7f4a6bd`, 95 commits ahead of upstream, with no tracked changes and one pre-existing untracked file `core/changes/2026-10-18-ai-coach-phase9-gptpm-transport-followup.md`. That unrelated file was not opened or modified.

## Requested outcome

Record GPT-PM's complete adversarial product review of the narrowed request: voice is a second input into existing workout operations, using the app's existing route/session/model/repository and validation rather than creating a second tracker or workout lifecycle. The review was sent to the new Fitness_App_aicoach project conversation. PM Bridge confirmed `sendPhase=sent`, user-turn ID `e230aa5f-c373-460b-9648-9232d74469a8`, and later returned the reply correlated to the same request ID. No send was repeated after this confirmation.

An earlier request ID, `4e62c93c-18b4-43e4-a9d1-d57ab96c874c`, was bound to the old conversation and failed before its send boundary (`ATTACHMENT_NOT_LANDED`, `sendPhase=not-started`, no user turn); its attached files did not land. The new chat was created before the correlated request below, and the old chat was left unchanged. The new request included the evidence summary in text instead of attachments.

## GPT-PM disposition

Verdict: `MODIFY`. GPT-PM accepts the operator's existing-workout boundary and rejects the older separate `Workout Runtime`, `live_workout_sessions`, independent journal/projector and duplicate lifecycle as implementation baseline. The five requested clauses were classified: shared action `MODIFY`; append sets `MODIFY`; target versus actual reps `ACCEPT`; acknowledgement truthfulness `MODIFY`; unsupported lifecycle/navigation `ACCEPT`.

The review's amended contract requires:

1. One application action path for touch and voice covering exercise/session resolution, eligibility, validation, authentication, duplicate protection, persistence, results and post-action effects. Preserve existing routes, session model, repository, timers, day merge/cold-start guard and delayed rating behavior.
2. Append each confirmed performed set exactly once to the existing set list; define stable identity for new set/correction/replay/retry; preserve other exercises, session identity and metadata; preserve the best-set projection unless separately approved; handle concurrent updates without losing accepted sets.
3. Keep targets as planning input. Actual performed repetitions are collected/confirmed after completion; skipped/unknown actuals remain unknown; do not relabel historical values whose provenance cannot be established.
4. Distinguish rejected, local/pending-sync, server-acknowledged and unknown outcomes. Surface late failures and reconcile; retries after unknown outcomes must not create a new set; only observable acknowledgement supports server-confirmed wording.
5. Keep whole-workout start/finish/cancel and single-exercise next/previous unavailable until an existing operation is evidenced or new scope is explicitly approved. Scheduled-day route navigation is the existing bounded operation. Generic cancel cannot reset a timer or mutate an unspecified target.

## Findings and source verification

The response identifies BLOCKER B-01..B-05 and MAJOR M-01..M-04. Current local source was checked for these findings; no runtime reproduction is claimed:

- `workout_player_page.dart:600-635,680-748` waits on the initial history snapshot and builds a full session from the observed state. `firestore_workout_session_repository.dart:61-70` performs a full-document set without revision/transaction semantics. This establishes a stale-snapshot lost-update risk; a specific cross-device loss was not reproduced.
- `workout_session_providers.dart:85-110` suppresses only an overlapping call while `state.isLoading`; `WorkoutSession` has no command/set identity (`workout_session.dart:192-219`). This is not replay idempotency.
- The `mobile/lib` callsite search found `_MarkCompleteButton` (one set save plus its later rating resave) and `_AddExerciseButton` (eligible exercise append; optional rating is collected before that save). Both use `LogSessionAction`; scheduled/programme saves use the distinct `ScheduledSession` model. The shared voice seam must account for both flows where voice supports them.
- `workout_player_page.dart:720-725` marks the exercise log session completed on first set completion. This does not establish whole-workout completion.
- `workout_player_page.dart:786-818` constructs a delayed difficulty-rating update from the earlier `entry` and logs the full session again. A concurrent overwrite is plausible but not reproduced.
- `set_capture_sheet.dart:50-60,154-185` collects target reps before a set, and the same `reps` value is later persisted; `progress_charts.dart:65-76,151-166` uses stored reps in actual metrics. Historical provenance cannot be inferred from the present `SetCapture` fields.
- `workout_session.dart:339-398` projects a best set per exercise. Direct readers include DayResult, progress/personal-record and volume-ledger code; the mobile export's `workoutLogs` field uses projected rows (`data_export_providers.dart:80-96`). Fact-check correction to GPT-PM M-04: `server_export.dart` invokes `exportAccountData`, and `functions/src/account_export.ts:514-520,560-568` also includes raw `workout_sessions` documents under the server payload. This is capped at 2,000 rows and subject to byte-budget trimming; affected sections are named in `truncated` (`account_export.ts:48-53,65-94,97-119,593-646`), while this raw section has no continuation cursor. Raw set lists are already represented when returned; preserve this source and ensure a truncated export cannot be represented as complete. Do not add a duplicate export route based solely on the mobile projection.
- `workout_session_providers.dart:61-76` filters completed sessions for history; `weeklyVolume` iterates supplied sessions without its own status predicate (`personalisation/data/volume_ledger.dart:96-133`). Preserve this difference; do not introduce pending-session documents in this scope.
- Voice parser dispatch and current timer/capture/rest preconditions are mapped in `docs/ai-coach/01b_CODE_MAP.md`. A scoped source search found no `hasPendingWrites` or metadata-change handling in the reviewed mobile workout paths; that source search is not runtime evidence. The second widget writer and raw account-export route/truncation behavior were also checked. Source shows that the four-second timeout returns normally without server acknowledgement, the action reports ordinary data, and the widget shows success and starts rest. Remaining acceptance is the pending/unknown and recovery design/implementation, historical reps provenance, shared-action lifecycle parity, and product acceptance.

The complete acceptance amendments, per-finding consequences, and correlated product/design acceptance are recorded in `docs/ai-coach/03_DESIGN.md` §§0.2–0.3 and summarized in `docs/ai-coach/02_BACKLOG.md` §2.1 and `docs/ai-coach/00_README.md`. Section 0 remains normative over older Runtime/journal/projector proposal text later in the design file.

## Files changed

- `docs/ai-coach/01b_CODE_MAP.md`: added source-verified consequences for stale snapshots, replay protection, first-exercise completion semantics, delayed rating writes, mixed readers, and the distinction between projected mobile logs and raw server export.
- `docs/ai-coach/00_README.md`: added the correlated product/design acceptance and retained the implementation, clinical and operations gates.
- `docs/ai-coach/02_BACKLOG.md`: expanded documentation acceptance and the future voice acceptance to cover the product review's amendments; preserved `NOT AUTHORIZED` status.
- `docs/ai-coach/03_DESIGN.md`: recorded the correlated product disposition, exact amended contract, findings and remaining evidence tasks; clarified that the old Runtime proposal is superseded.
- `docs/DOCUMENT_REGISTRY.md`: regenerated derived document byte counts after the documentation update.
- `reports/AI_COACH_STATUS_2026-10-19.ru.html` and `reports/AI_COACH_STATUS_2026-10-19.html`: synchronized the status summary and AI-COACH-01/02 rows.
- `core/changes/2026-10-19-ai-coach-gptpm-contract-modify.md`: this linked record.

## Authorization and verification

The initial GPT-PM review concluded `PRODUCT DISPOSITION ONLY` with `MODIFY`. After the documented amendments, the follow-up returned `ACCEPT — PRODUCT/DESIGN CONTRACT ONLY`: job `dff390c4-b4b5-4689-89cc-2e6b598ea446`; project `fitness_app_aicoach`; conversation `6ad628eb-84ac-83eb-a95b-0c834777cabf`; user turn `26881f15-ab2d-4b51-9542-656334b581ac`; reply `9e56f767-3467-42b7-943e-889661a13f48`; `correlated=true`, `sendPhase=sent`, one attempt. GPT-PM accepted B-01..B-05/M-01..M-04 at product/design level and reported no new product BLOCKER/MAJOR. The request contained a textual contract summary against operator-provided source baseline `b7f4a6bd7176607adbe76ace0af72bb9eaa14929`; it had no file attachments and did not supply a diff hash. Treat the reply as correlated acceptance of the described contract, not exact-file/tree verification or implementation evidence.

PM Bridge appended a generic `GO/PUSH AUTHORIZED` execution header in the send snapshot after the request's logical text. That header conflicts with the request's explicit design-only scope; the reply states `Implementation authorization: NOT GRANTED`. It is not treated as a code GO. The operator remains accountable task owner; Codex is the assigned technical executor; GPT-PM provides product/design decisions. No qualified clinical signature or reachable production on-call rotation is implied by this review.

Only documentation and reports are changed by this follow-up. No tests, checks, builds, CI, migrations, runtime changes, production changes, push or merge are performed. Product/design acceptance is recorded; technical prerequisites remain open: exact concurrency and retry mechanisms, server-acknowledgement/reconciliation, historical-reps provenance, provider/shared-action parity and affected-reader conformance. OQ-07 qualified-human sign-off and ACS-100 deployment/on-call/delivery remain separate gates. The voice runtime remains unimplemented; a separate code-sprint GO is required before implementation.
