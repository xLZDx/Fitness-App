# AI Coach documentation: remediation decisions for review round 1

Date: 2026-10-17. Inputs: `05_REVIEW_ROUND1.md` (97 reviewer claims: AR 18, UX 17, RL 23, SF 21, SE 18; two BLOCKER: AR-1 and SF-1). This file is the coordinator's single batch of design decisions that the documents must apply. Where a decision is not the coordinator's to make it is listed in section C as an OPEN operator or technical-review question with a proposed default; nothing in section C may be written as decided. Reviewer claims were not all re-opened by the coordinator; each editing agent must verify the code citations it relies on and report any claim it finds wrong.

## A. Decisions to apply (design level, reversible, inside the documentation program)

### A1. Safety (SF-1, SF-7, UX-3, UX-4, UX-5, AR-13 row safety_stop, AR-14)
1. `safety_stop` takes effect in memory and on screen first. A journal failure never undoes it; it only adds a "could not save" notice. Add `safety_stop` to every persistence-failure test.
2. After a safety stop: state PAUSED with a safety lock; voice alone can never clear it (UI rule wins; remove the "distinct confirmed phrase" option from the design); rest countdown is frozen and rest cues are suppressed; `finish_workout` and `abandon_workout` are user-only actions.
3. Recording a performed fact is never gated by the safety check: `record_set`, `correct_set`, `pause_workout`, `skip_rest`, `finish_workout` always succeed when the state allows them. One shared allowed-action table is the single source for design, banner copy and tests.
4. Scope of a symptom stop: a chest, dizziness, fainting or breathing code stops the whole workout; a joint or muscle pain code stops the current exercise and offers replace, skip or finish; free-text "something else" is classified on the device only against a closed list and defaults to pause when unclassified. Who signs the symptom list is OPEN (section C).
5. The emergency number is chosen per locale from a table the operator signs; no hard-coded number. A call action on the locked-screen notification is OPEN.

### A2. Single writer, ownership and time (AR-1..5, RL-4, RL-17, UX-11)
1. A live session has one owner: `ownerDeviceId` plus an `ownerEpoch` counter, both in the replica session document and in the rules fence (owner fields immutable except through a takeover that increments the epoch). A second device opens the session read-only; takeover is an explicit user action; the previous owner's unsynced journal is parked, never merged, never deleted, and shown as "kept on this phone".
2. One owner isolate holds the Runtime, the journal and the rest state. When the foreground service engine is active it is the owner and the UI engine is a thin client over a channel; otherwise the UI isolate is the owner. Never two Runtimes.
3. The Runtime owns `restEndsAt` (absolute time). `RestTimerController` is not changed in sprint 01; the live screen renders from the Runtime. An OS-scheduled notification at `restEndsAt` is the end-of-rest backstop when the process is killed (permission analysis is OPEN).
4. Time-driven transitions (rest elapsed, PREPARING end) are journaled internal commands with their own `seq`. Model and voice commands are fenced on session id, `ownerEpoch` and command id, not on the exact revision, so a rest expiry does not make a spoken set stale. `expected_revision` stays for manual optimistic edits and for the replica fence.
5. Refusals are returned to the caller and emitted as events but are not stored in the idempotency ledger, so a transient refusal can be retried. Only accepted commands are ledgered. A same-id, different-payload command returns the original result and emits `command_id_payload_mismatch`.
6. Closed command set additions: `correct_set(set_id, reps, weight_kg, effort)` (appends a correction record, never rewrites), `void_set(set_id)`, `add_rest_time(seconds)`. NEXT_EXERCISE is a derived view of ACTIVE_EXERCISE, not a persisted state. `safety_stop` and `finish_workout` are rejected from NOT_STARTED.
7. Tool-call ids from the model are `(voiceSessionId, utteranceId, toolCallIndex)`; `liveCoachTurn` is idempotent per utterance; a per-turn client deadline moves PROCESSING to LISTENING with a local "unavailable" message; state-changing tool calls are never auto-retried; a failed turn is not charged.
8. A manual tap mints its `command_id` when the entry sheet opens; the control is disabled until the acknowledgement; the duplicate-suspect check covers taps and voice.

### A3. Journal, projection and sync (SF-2, SF-3, SF-10, SF-12, SF-13, RL-5..7, RL-10, RL-13, RL-16, RL-18, RL-19, AR-8, AR-15, AR-18)
1. No time-based journal deletion. A journal is removed only after (a) the local projection exists, (b) the projection is server-confirmed through a metadata-observing path, (c) the streak step is confirmed, and (d) for an abandoned session after the user chose to delete or export. Unfinished journals are never auto-deleted.
2. The projector does not go through `LogSessionAction` or the 4 s `save()`. It writes through a new observed path and records a durable `projected` marker; the streak update is a tracked retried step keyed by `sessionId`.
3. The sync driver uses exponential backoff with jitter, a maximum attempts per record and a maximum backlog age; a permanently rejected record is quarantined with a visible "sync blocked" state and an event; copy never blames connectivity for a rejection.
4. The dispatch result is authoritative for the UI. Before showing "Not confirmed" the UI reconciles against the journal head; a late acknowledgement upgrades the card to Saved. The 4 s timeout is not a UI constant.
5. Journal files are AES-GCM encrypted with the existing activity cipher pattern, excluded from Android backup in both XML files and the shared constant, bounded in size and count, preflighted for free disk at start, and in a visible manual-only mode when storage fails. Replay time is bounded; an in-memory command-id set is kept per loaded session. The exact-set backup rules test is edited on purpose and the edit is declared.
6. Real-device kill-and-restart evidence is an exit criterion of AI-COACH-01 (claim limited to the test device); SQLite is the named fallback if the file journal fails it.
7. Replica `commands` and `sets` have a retention policy and a bounded `seq` range; the batch size is derived from a rules-emulator call-budget measurement, not fixed at 8.

### A4. Rules, flags, deletion (SE-5, SE-7, SE-9, SE-10, SE-15..17, AR-2, AR-6, AR-7, RL-3, RL-20)
1. The live collections copy the full activities pattern including the account-deletion fence and tombstone check; every `liveCoach*` callable calls the account fence check. A refused replay purges that journal's replica queue (the local file is kept, parked).
2. The replica carries only an allowlisted set of non-health action and result codes; `safety_stop`, `SAFETY_*` and screening codes never leave the device.
3. Feature flags gate only the start of new sessions. An unfinished session continues on an expired or unreachable flag cache. The global server kill switch stops new turns and still allows `liveCoachEndSession`. Per-feature emergency kill uses the Secret Manager switch, not a Firestore document.
4. New collections and the voice-session, reservation and consent records live under `users/{uid}/...`, are added to the data-lifecycle policy file and the account export list, and the local journal wipe is wrapped like `ActivityAwareLocalDataWipe`.
5. App Check options for every new callable are specified and pinned in the scaling test.

### A5. Voice, model output, cost (SF-5, SF-6, SE-6, SE-8, SE-12, RL-1, RL-2, RL-12, RL-15, RL-23, AR-10, UX-6)
1. The port exposes `captureStarted`, `captureStopped`, `captureLost` and a liveness watchdog; the mic indicator renders only from them, with an explicit "mic state unknown" display. A failing `stop()` never shows "off".
2. For turns with state-changing intents only device-generated text is spoken after the result; model reply text that claims completion is suppressed; a dropped or refused tool call is reported to the device.
3. Default MVP listening mode is tap-to-talk (or headset-only hands-free) until the gym trial; always-on is OPEN. NO_MATCH and low-confidence states and an acknowledgement cue are added.
4. Reconnect is bounded (backoff with jitter, cap, credential renewal, defined give-up state).
5. Cost: per-turn budget for Mode B (`QUOTAS.liveCoachTurn`, per-session turn cap, per-user in-flight limit, required `maxOutputTokens`, added to the gateway operation list); server-side reservation lease with `expiresAt` and refund, renewal heartbeats, idempotent start and end. Numeric caps are OPEN (OQ-05).
6. Mode A credential gate: locked to server-set prompt, tools and model; single use; revocable; budget re-checked on renewal.
7. Voice utterance ids: fallback id is a hash of final text plus audio window when the recogniser gives no stable id.
8. The tool-call production mechanism (JSON response schema or an extended gateway) is stated; ids are sent instead of titles; injection tests are reworded to what the gateway can do.

### A6. Privacy and consent (SE-1..4, SE-11, SE-13, SE-14, SE-18)
1. The utterance is declared a health-bearing channel in consent and in the privacy deliverable. A privacy policy update (voice, recogniser, model provider, retention) and the Play data-safety form are a hard prerequisite for any build that calls `liveCoach*`, as an AI-COACH-02 acceptance item (the wording itself stays an operator and legal decision).
2. `InjuryFilterReason` and `ScreeningCeilingReason` codes are removed from model-bound context; free-text symptoms are classified on the device only; provider retention and no-training criteria apply to Mode B too.
3. Coach memory values use a closed vocabulary enforced by rules. Consent is recorded per uid with version and timestamp (allowlisted, in export and delete); capture is refused without current-version consent; withdrawal applies locally first with a persistent flag and blocks capture until persisted. "Not now" gets a re-prompt cadence and a separate firm-decline action; age gating comes before the microphone screen.
4. Recogniser preference for on-device recognition is decided in the provider ADR; "no raw audio persisted" is tested for app storage only and the platform recogniser is disclosed.
5. `finish_workout` and `abandon` ask for a screen or headset-button confirmation when available.

### A7. UI wording and behaviour (UX-1, 2, 7..10, 12..17, SF-4, SF-17, SF-18)
Undo on the Saved card and a defined correction path after the 10 s window; confirm-first for implausible values; primary dock action opens the set-entry sheet; pocket claim is conditional on the actual capability; screen-reader policy (no duplicate announcements while the coach speaks, no focus jump, chip actions as custom actions, headset or tap-to-talk when a screen reader is active); Back shows a persistent microphone cue or a confirm sheet; T-7 extended with a screen reader; pain control pinned outside the scrolling bar; rest controls 56 dp; in-app reduce-animation row; neutral wording for a corrupt journal; abandoned-session copy says where data is; "Not confirmed" can later resolve to Saved.

### A8. Document hygiene (AR-11, AR-12, AR-16, AR-17, SF-16, SF-20, SE-3, RL-11, RL-22)
1. Amend AICR-010, AICR-021, AICR-022, AICR-028, AICR-032, ACS-028 AC-2, ACS-040 AC-1 and the code map's `coach_marketplace` naming (folder is `features/marketplace`); add the amendments to the design's amendment list.
2. D1..D17 get a three-value status: RESOLVED, RESOLVED PENDING SIGN-OFF, OPEN WITH DEFAULT; list which gate AI-COACH-01.
3. New ADRs: separate collection with rules fence and ownership; feature flag mechanism; L1 to L3 confirmation semantics; user-mute PAUSED transition added to the voice table.
4. Observability: name the sink, alerts and owners; recovery failure rate, persist-failed rate, sessions stuck below server-confirmed over 24 h, reservation leaks, reconnect time.
5. Add the missing test rows (isolate concurrency, poison record, rest backstop, disk full, safety stop under persistence failure, ownership takeover, rejected-replay purge, N-table and AC-LC mapping, spoken false-success, double tap, late ack, consent withdrawal failure, reservation expiry, flag expiry mid-session, backup exclusion and encryption); run FT-1063, 1064 and 1074 once on the Firestore emulator.

## B. Out of scope for this documentation program
Writing or changing any Dart, TypeScript, rules or manifest file; running any test; contacting any provider; editing the live privacy policy or Play Console.

## C. OPEN items (operator or technical review; defaults proposed)
| Item | Plain-words question | Default if unanswered |
|---|---|---|
| OQ-03/04 | Which voice mode and provider first | Mode B first, Mode A measured in a spike |
| OQ-05 | Per-user daily and monthly AI cost cap and behaviour at the limit | Hard daily cap then manual mode; no number proposed |
| OQ-06 | Keep transcripts or not | No transcripts |
| OQ-07, OQ-20 | Load limits, dangerous-symptom list and who signs it | Symptom stop cannot ship until signed |
| OQ-19 | May any health-derived data reach the model | Nothing leaves the phone except what the user speaks |
| OQ-08 | Consent text and Play declaration | Prepared in AI-COACH-00, operator approves |
| OQ-09..12 | Device matrix, battery budget, accessibility target, SLO numbers | Measured in spikes |
| OQ-13 | Where the flag lives | Server per-feature flag plus build switch, default OFF |
| OQ-15, OQ-16 | Languages; minors and seniors | Current age policy, no relaxation |
| OQ-17 | Relation to Phase 2 sprints | Separate line, no change to Phase 2 |
| OQ-21..24 | Where effort is stored; abandoned sessions in History; second device behaviour; scope of the 2 s target | Effort in the journal only; abandoned kept on phone; read-only second device with explicit takeover; 2 s applies to the voice acknowledgement, 300 ms to the local lane |
| New | Emergency number table per locale; call action on locked-screen notification; exact-alarm permission for the rest backstop; always-on vs tap-to-talk default after the gym trial | Tap-to-talk; no call action; notification without exact alarm |
