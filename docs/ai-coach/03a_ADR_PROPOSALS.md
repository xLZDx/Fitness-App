# Live AI Coach - ADR proposals ADR-001..ADR-010

Status of every ADR in this file: PROPOSED. None is ACCEPTED. Listing an option in the draft (`TDD-001_LIVE_AI_COACH_v0.1_INPUT.md` section 16) does not approve it (constraint C-04). Date: 2026-10-17. Branch: `docs/ai-coach-tdd-001`. Companion: `03_DESIGN.md` (section numbers below refer to it). Nothing here was tested or measured. UNKNOWN = the repository cannot answer; UNVERIFIED-EXTERNAL = depends on provider/OS/store behaviour not checked in this phase.

Decision owner: an ADR becomes ACCEPTED only after design review consensus and, where marked, an operator decision. Operator-level items are mirrored in `03_DESIGN.md` section 22.

---

## ADR-001 Realtime voice provider and voice mode

Status: PROPOSED (open on provider; mode default proposed). Related: OQ-03, OQ-04, OQ-05, OQ-12; AICR-001..008, 035, 073, 078.

Context: The draft prefers Mode A (realtime speech-to-speech) with Mode B (STT, model, TTS) as fallback. Repo facts: all AI access today is Vertex AI via callables with Application Default Credentials and no key in the app (`functions/src/ai_gateway.ts`); no realtime, streaming or ephemeral-credential surface exists; `speech_to_text` is declared but never imported; `flutter_tts` and `TtsVoiceCoach` exist. Whether Vertex offers a usable realtime API in the project region, its price and data terms are UNKNOWN.

Options:
- A. Mode A first: streaming provider session for all dialogue and commands.
- B. Mode B first: on-device or server STT, callable per turn, on-device TTS; add Mode A later if the spike passes.
- C. Two lanes in either mode: deterministic on-device command lane (closed grammar, local acknowledgement) plus model dialogue lane.

Proposed decision: B with lane structure C; run a time-boxed Mode A spike using the measurement procedure in design section 8 (C1..C9). Choose Mode A for the dialogue lane only if latency, availability/terms, background survival and security pass and cost is within the operator budget. The command lane stays in both modes so workout control never depends on the model.

Consequences: (+) reuses the existing callable pattern, no streaming infrastructure or temporary credentials needed for MVP; (+) NFR-01 for commands is met locally. (-) dialogue less natural; per-turn latency includes a request/response; STT quality and background behaviour on Android is a risk (see ADR-008). Reading NFR-01 as applying to the command lane needs operator confirmation (OQ-24).

Evidence still needed: provider availability, price and data-use terms; measured P95 latency on Samsung Galaxy S23 over Wi-Fi and mobile data (N >= 100 per condition); recognition accuracy replayed at recorded gym noise and in a real gym; idle false-activation count; per-workout-hour cost; operator budget (OQ-05).

---

## ADR-002 Audio transport

Status: PROPOSED (conditional on ADR-001). Related: OQ-04, OQ-12; AICR-002, 008, 073.

Context: Callables are request/response (FACT) and cannot carry a live audio stream. If Mode A is chosen, a streaming transport with reconnect is required. If Mode B only, audio never leaves the device through our transport (STT result text does).

Options:
- A. No streaming transport (Mode B): text over callables.
- B. Direct client-to-provider session using a short-lived credential minted by a callable.
- C. Server relay (for example a Cloud Run WebSocket service that verifies the Firebase ID token and App Check token) between app and provider.

Proposed decision: A for MVP. If Mode A is selected later, prefer C when the provider cannot issue a credential bound to a user and a hard duration, otherwise B with TTL about 10 minutes (PROPOSED value), renewal through a callable, and a maximum session duration. Reconnect: the voice state machine enters RECONNECTING while the Runtime and rest timer continue locally (design 10.1, 6.5).

Consequences: B is cheaper to build but the server cannot observe consumed minutes (cap relies on credential TTL; client heartbeats are untrusted). C gives exact metering and central kill but adds a service to build, secure, scale and pay for. A needs neither but caps naturalness.

Evidence needed: provider credential capabilities (binding, TTL, revocation); whether App Check tokens can be verified on a relay in this project; reconnect time measured under network flap (sets the SLO, OQ-12); Cloud Run WebSocket behaviour with the project's scaling profile (`scaling.ts` AI_METERED values: maxInstances 15, concurrency 10 apply to callables, not necessarily to a relay: UNKNOWN).

---

## ADR-003 Server orchestration and short-lived credentials

Status: PROPOSED. Related: OQ-04, OQ-05, OQ-13; AICR-071, 072, 073, 078.

Context: The `aiCoachAdvice` callable shows the repo's pattern: authenticated, App Check noted, non-anonymous, global kill switch (Secret Manager JSON, fail-closed on read error), per-day request quota, fixed prompt template, bounded output (FACT `ai_coach_advice.ts:135-185`, `abuse_guard.ts:312-329`). Quota is request-count based, not minute based. Health data is stripped by Firestore rules and the server cannot read it (FACT `firestore.rules:209-250`).

Options:
- A. Extend the existing pattern with new callables (`liveCoachStartSession`, `liveCoachTurn`, `liveCoachEndSession`); workout tools execute on the device.
- B. A separate isolated backend service (draft wording) that also executes tools server-side.
- C. Client talks to the provider directly with a long-lived key. Rejected: violates AICR-073 and the repo's no-key-in-app rule.

Proposed decision: A. `uid` only from `request.auth`; tool calls are schema-validated on the server and re-validated on the device; no server-executed workout tools in MVP (the server has neither the journal nor the health data). Add a server-only per-user session-minute counter (reserve at start, reconcile at end, daily and monthly caps set by the operator). Add per-feature flag checks next to the global kill switch (design 12).

Consequences: (+) smallest new surface, tested pattern, no cross-user tool authority on the server. (-) the device is the executor, so security of tool execution rests on the device Runtime validation (acceptable: the user owns their workout; the replica is protected by rules). A later server-side tool surface would need its own ownership checks and a new ADR.

Evidence needed: callable latency for a conversational turn with thinking disabled (the existing advice callable documents a 25-31 s thinking-enabled ceiling, so settings must differ: measurement needed); cost per turn; App Check enforcement status for the new functions (`APP_CHECK_ENFORCED_AI` value not inspected); operator caps (OQ-05).

Related decision candidate (not numbered in the draft): per-feature flag mechanism. Options: build-time define only; server callable `getFeatureFlags` over a server-only document with per-uid allow-list (proposed); Firebase Remote Config (not in `pubspec.yaml`; new dependency; fit UNKNOWN); client-readable Firestore document (needs rules). Default OFF on any failure. Evidence needed: operator choice (OQ-13).

---

## ADR-004 Memory storage

Status: PROPOSED. Related: OQ-06, OQ-19; AICR-058..060, 076, 077.

Context: Draft proposes Firestore plus minimal projections. Health data is device-only (FACT); the wildcard rule permits any shape in unlisted collections (FACT), so a new collection is unconstrained unless carved out. Account deletion runs `recursiveDelete(users/{uid})` (FACT `index.ts:2386`); account export lists collections explicitly (FACT `account_export.ts:517-519`).

Options:
- A. Firestore `users/{uid}/live_coach_memory/{itemId}` with a closed schema, derived items only.
- B. Device-only storage (like `PrefsSensitiveStore`), nothing in Firestore.
- C. Store transcripts as well. Rejected as default (OQ-06 default: no transcripts).

Proposed decision: A for Profile/Training/Preference/Session items (non-health), B for Safety Context. Each item has exactly one category, a source, `confirmedAt`; conflict priority is the ordered resolver of AICR-059; the model may propose items, the user confirms; no raw audio ever (AICR-076). Collection excluded from the wildcard and given a closed-schema rule block (like the live-session carve-out, not edited here). Add the collection to export; deletion covered by account deletion, plus a user-invoked "delete coach memory".

Consequences: (+) cross-device continuity for non-health memory, minimal data. (-) health-adjacent preferences must be filtered; classification mistakes could leak sensitive text into Firestore - mitigated by closed value vocabularies rather than free text where possible (free-text allowance UNKNOWN, decision needed).

Evidence needed: retention period (OQ-06); operator view on free-text items; rules emulator tests; export and deletion tests.

---

## ADR-005 Local event journal

Status: PROPOSED. Related: OQ-01, OQ-02; AICR-026, 042..047; NFR-05..08.

Context: No journal exists (FACT). The existing `save()` is a plain upsert with a 4 s timeout that swallows a late rejection (FACT `firestore_workout_session_repository.dart:67-70`), so a returned future is not confirmation. Firestore offline cache exists but gives no per-command idempotency ledger. `pubspec.yaml` has no SQLite/Hive/Isar package (grep); `path_provider` and `dart:io` are used by an existing durable outbox (FACT `equipment_identity_telemetry_outbox.dart`).

Options:
- A. Append-only JSON-lines file per session with crc and flush per record, behind `CommandJournalStore`.
- B. SQLite via a new dependency (transactional command+result).
- C. Rely on the Firestore offline cache as the journal.

Proposed decision: A, behind an interface so B can replace it. A record contains command, result, new revision and events; acknowledgement means flushed; a torn trailing line is discarded. Three confirmation levels are kept apart: journal-committed, replica-queued, server-confirmed (snapshot without pending writes and not from cache). The old repository's `save()` future is never treated as confirmation.

Consequences: (+) no new dependency, portable to iOS (`dart:io`), simple replay. (-) durability guarantee under process kill and low storage on Android is UNKNOWN until proven; no query capability; compaction not provided.

Evidence needed: kill-at-every-step test (AICR-026) on a physical device; flush/fsync behaviour on Android filesystems; behaviour with full storage; crc torn-write handling test. If any fails, move to B.

---

## ADR-006 Avatar implementation

Status: PROPOSED (deferred detail to AI-COACH-04). Related: AICR-054..057; D16.

Context: Only a pose skeleton painter exists in `form_check` (code map). The avatar must not affect voice or Runtime and must be hideable.

Options: A. Light 2D renderer in Flutter (`CustomPainter`/sprites) driven by an event stream. B. Rive/Lottie style asset animation (new dependency, fit UNKNOWN). C. 3D/native renderer. Rejected for MVP (NG-4, battery risk).

Proposed decision: A, one character, one voice, states idle/listening/speaking/thinking/positive/explaining/warning, mouth movement from playback amplitude events, full hide switch; the module imports only event types (static dependency check). Performance guard: degrade to static image when frame budget is exceeded.

Consequences: (+) smallest risk to the critical path. (-) limited visual quality; lip sync fidelity depends on amplitude events only.

Evidence needed: frame-time and battery measurements on S23 with the avatar on versus off; operator approval of the character art; asset licensing (UNKNOWN).

---

## ADR-007 WorkoutSession migrations

Status: PROPOSED. Related: OQ-01; AICR-022, 028, 070; D2, D4.

Context: `WorkoutSession` persists weight and reps per set and a status enum; `pending`/`abandoned` are never written; `totals()` counts every document in the collection; `weeklyVolume` reads raw sessions without a status filter; `asLogEntries` collapses sets to the heaviest (FACT, all opened in this phase).

Options:
- A. Add optional fields to `SetCapture`/`WorkoutSession` and write live sessions into `workout_sessions` as `pending`.
- B. Keep `WorkoutSession` unchanged; store live state in a new collection; project one `completed` `WorkoutSession` at finish.
- C. Change `asLogEntries` and readers to understand live sessions.

Proposed decision: B. No change to `WorkoutSession`, `SetCapture`, `asLogEntries` or the existing repository in MVP. The projector uses `id = live sessionId` so a retry upserts. Old documents are untouched; old app versions read the projected document as before.

Consequences: (+) removes the count and volume miscount risks, zero migration, flag-off safe. (-) per-set `source`, `effort`, `command_id` do not reach long-term history; abandoned sessions are not in history unless the user chooses "save what I did" (OQ-22). The unaudited readers (Wear, scheduled sessions, backfill script) are unaffected by construction.

Evidence needed: regression test that History/totals/export render a projected session unchanged (AICR-022); operator decision whether per-set metadata must reach history (would force option A later with a reader audit).

---

## ADR-008 Hands-free lifecycle (Android foreground service)

Status: PROPOSED; all platform behaviour UNVERIFIED-EXTERNAL. Related: AICR-038..041; C-08; D12.

Context: Manifest has no RECORD_AUDIO, no foreground-service permission or type, no BLUETOOTH_CONNECT; its own comment says to add them only with the feature, privacy text and Play declaration (FACT). `POST_NOTIFICATIONS` and `WAKE_LOCK` exist. `active_session_status.dart` states process death clears the in-memory timers (FACT).

Options: A. Native foreground service of type microphone (plus media playback if needed) hosting the audio pipeline, started only from a user tap; Runtime in a cached FlutterEngine owned by the service. B. Foreground-only operation with screen kept on and show-over-lock. C. Third-party Flutter foreground-task plugin (new dependency, fit UNKNOWN).

Proposed decision: A as target, with spike S-A1 to prove the Dart isolate survives screen lock and Activity destruction; B is the documented fallback if S-A1 fails (AICR-038 then partially unmet - operator-visible). Persistent notification with a Stop action while capturing; capture never starts from boot or location (NG-6, AICR-040); call, focus loss and headset loss move voice to PAUSED without touching workout state; no automatic capture restart after a Bluetooth reconnect.

Consequences: (+) the only route to genuine locked-screen operation. (-) native Kotlin code, Play foreground-service declaration, privacy text, OEM battery-manager risk, Android 13-16 matrix, echo cancellation for barge-in unproven.

Evidence needed: Android 13-16 behaviour for microphone-type services started from the UI; Play Console declaration requirements; S23 background survival over 60 minutes; Bluetooth routing; acoustic echo handling; battery per hour (OQ-10).

---

## ADR-009 Offline commands

Status: PROPOSED. Related: AICR-031, 074, 075; draft section 11.

Context: Local rest timer uses wall-clock `endsAt` and an injectable clock (FACT). The journal makes local commands durable (ADR-005). Cloud dialogue may be unavailable.

Options: A. Limited safe set offline (start_set, record_set, rest commands, complete_exercise, pause/resume, finish, get_current_exercise, abandon, safety_stop; start_workout from a cached local plan). B. All commands offline including model-suggested replacement. C. Nothing offline.

Proposed decision: A. Model-dependent commands (dialogue, model-suggested replacement) are unavailable offline and the app says so honestly, never imitating success (AICR-036). Manual replacement from a locally cached eligible list stays available. Sync after reconnect follows design 6.5 with idempotent create-only documents.

Consequences: (+) matches the draft's "workout does not depend on the AI server". (-) the command lane offline requires local STT; whether Android's recogniser works offline on the target devices is UNKNOWN, otherwise offline operation is touch-only.

Evidence needed: offline recogniser availability on S23 and a low-end device; airplane-mode E2E (E2E-03, E2E-10); sync-after-offline integration test with duplicate delivery.

---

## ADR-010 AI provider fallback

Status: PROPOSED (open decision per backlog; may remain open in AI-COACH-00). Related: AICR-036, 075, 078; OQ-05.

Context: One provider path exists (Vertex via ADC). The global kill switch fails closed (FACT). No second provider is configured; its availability, terms and cost are UNKNOWN.

Options: A. Manual mode only (no second provider): on provider failure, budget exhaustion or kill switch the model lane stops and the Runtime plus command lane continue. B. Second model/provider with safe switchover. C. Degrade from Mode A to Mode B on failure.

Proposed decision: A for MVP, plus C if both modes ship. No automatic switch to a different provider without a new ADR, operator approval and a privacy review (a second provider changes who sees user speech). Manual mode is always the end state; tested by E2E-10.

Consequences: (+) smallest privacy and security surface. (-) a provider outage ends conversational features until recovery.

Evidence needed: outage and budget-exhaustion E2E; user-facing messaging text review; operator decision on whether a second provider is wanted at all.

---

## Additional decisions raised by the design (not in the draft list)

These are candidates for ADR-011 and later, listed so they are not lost; none is proposed for acceptance here.
- Two-lane voice (deterministic command lane plus dialogue lane): captured under ADR-001.
- Separate live-session collection with rev fence and Firestore rules carve-out: captured under ADR-007 and design section 7 (rules edit not performed).
- Health-data exposure to the model (options A opaque, B coarse flags, C detailed): operator privacy decision OQ-19, design 9.2.
- Mid-session symptom stop and its approver: OQ-20, design 9.3.
