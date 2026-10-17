# Live AI Coach - UI specification (SDLC phase 3, UI design)

Status: DRAFT for operator/product review and for the later independent UX and accessibility review. Not approved. ALL TEXT IN THIS DOCUMENT, INCLUDING EVERY COPY STRING, IS DRAFT pending operator/product review. Consent and privacy screens are specified as UI requirements only; no legal wording is written here (placeholders are marked `[LEGAL TEXT]`).
Date: 2026-10-17. Branch: `docs/ai-coach-tdd-001`. Authoring role: ui-designer. No product code is changed by this document.
Revision: round-1 remediation applied (see section 19 for the review ids). Where this file and `06_REMEDIATION_DECISIONS.md` differ, the decisions file wins. The single allowed-action table in section 4.6 is the one source for banner copy, dock enablement and tests.
Inputs: `docs/ai-coach/TDD-001_LIVE_AI_COACH_v0.1_INPUT.md` (called "the draft"; sections 1, 5, 10, 11 read in full, the rest read), `docs/ai-coach/01_REQUIREMENTS.md` (AICR-nnn ids), `docs/ai-coach/01b_CODE_MAP.md`, `docs/phase2/s03/S03D_UI_DESIGN_CONTRACT.md` (structure and shell/dock/size-class/accessibility conventions; itself a DRAFT revision 3, not approved), `core/CONVENTIONS.md`, `mobile/lib/features/equipment/workout_player_page.dart` (class list and snackbar pattern only), `mobile/lib/features/form_check/widgets/coach_hud.dart` (lines 180-330), `mobile/lib/features/workouts/widgets/rest_timer.dart` (class and semantics grep only).

Tags: FACT = read in a repository file (path given). INFERENCE = concluded from facts. PROPOSED = design choice made here, reversible. OPEN = needs an owner's answer (section 16). UNGROUNDED = could not be verified in the repository (section 17). AICR-nnn = requirement id from `01_REQUIREMENTS.md`.

## 1. Scope and non-scope

In scope: the user-visible surface of the Live AI Coach for Android phone first (MVP, draft section 2): entry, consent and permission screens, the live session screen with all states, conversation view, workout HUD, voice indicator, avatar slot, hands-free controls, foreground-service notification, safety stop, manual fallback, resume after crash, finish, coach settings and privacy controls, copy rules, accessibility, responsive behaviour, and the list of things the UI must never claim.

Not in scope: legal text; backend, provider or transport choices (ADR-001..010 stay open); Runtime command semantics beyond what the UI must display; an avatar art style or 3D asset; iOS, Wear OS and tablet device verification (design is kept portable, section 12); pricing/paywall.

Priority mapping: P0 screens and states are the MVP. The avatar is P1 (AC-015): the P0 screen is complete and correct with the avatar slot absent (AICR-054..057). Long-term memory screens (AC-016) are specified only as a settings entry and delete/export controls (AICR-060). Post-workout coach analysis is P1 (AICR-061); the P0 finish screen shows stored totals only.

## 2. Repository facts that constrain the UI

| # | Fact | Evidence |
|---|---|---|
| U-F1 | The existing workout player is a pushed page at `/workout/:id`, outside the five-tab `ShellRoute`; nothing mounted in `MainShell` is visible on it. Live Coach follows the same pattern (immersive, no tab bar). | FACT S03D F5, I2; `core/CONVENTIONS.md` "State and routing" |
| U-F2 | UI primitives to reuse: `HudScreenBody`, `HudPanel` (`dense`, `secondary`, `onTap`, `semanticLabel`), `HudSheet`, `HudButton`, `HudChip`, `HudToggle`, `HudSettingRow`, `HudRing`, `HudMetricRow`; `minTapTarget` 44; `screenGutter` 16; `reduceMotion` and `context.hudMotionDuration(...)`. Colours come from tokens, not hard-coded values. | FACT S03D F8, F9; `core/CONVENTIONS.md` "Design system" |
| U-F3 | `HudButton`, `HudChip` and `HudPanel` today hard-code 44 px height, one text line, thin semantics (subtree excluded) and no focus ring. S03D proposes optional extensions (`minHeight`, `maxLines`, `semanticHint`, `selected`, `showFocusRing`); Live Coach needs the same extensions and a 56-64 dp variant. | FACT S03D F25, F30, section 9.1 |
| U-F4 | Light-theme contrast: `warning` 1.50:1 and `danger` 2.69:1 against base; accent `#4B7A00` 4.51:1 (no margin). They must never be text or the sole signal. Dark theme is comfortable. | FACT S03D F10, section 12 |
| U-F5 | `SemanticsService.announce` is already used (`check_these_chips.dart`, `analysis_progress_view.dart`, `kcal_range_slider.dart`). No in-app motion toggle exists; reduced motion follows the OS. | FACT S03D F9, F22 |
| U-F6 | A consent sheet with explicit agree/decline exists as precedent (`cloud_consent_sheet.dart`). Error panels use plain sentences and never raw exception text (`errorServiceUnavailable`, `foodDiaryError`). | FACT S03D F22, section 11 rule 8 |
| U-F7 | Russian is the first supported locale and the fallback (`kSupportedLocaleCodes = ['ru','en']`). Every string needs a Russian value and tests run in `ru` first. | FACT S03D F20, section 13 |
| U-F8 | The Form Coach strip uses a dot that is filled while the coach is watching and hollow when paused. The same meaning (filled = live) is kept for the Live Coach mic dot. | FACT `coach_hud.dart` 182-255 |
| U-F9 | One notification channel exists (`workout_reminders`); a notification tap registers no callback today. Live Coach needs its own channel and a working tap target. | FACT S03D F19 |
| U-F10 | `RECORD_AUDIO`, foreground-service permissions, `BLUETOOTH_CONNECT` are absent from the manifest; no speech adapter, no foreground service exist. Every permission and notification surface below is new native work. | FACT `01b_CODE_MAP.md` (Verified facts, D6, D12) |
| U-F11 | `WorkoutSession` persists only weight and reps per set and `save()` swallows a late 4 s timeout; a returning `save()` is not confirmation. The UI "Saved" state must therefore come from a Runtime/journal acknowledgement, not from a repository call returning. | FACT `01b_CODE_MAP.md` (Persistence); AICR-027 |
| U-F12 | Safety refusals are typed values (`BlockReason`, `PlanRefused`), not sentences; the draft's mid-session symptom stop does not exist in code. | FACT `01b_CODE_MAP.md` (Safety, D13); AICR-066 |
| U-F13 | No client feature-flag mechanism is confirmed; the flag `live_ai_coach_enabled` defaults to off. | FACT `01_REQUIREMENTS.md` F-11, OQ-13 |

Not verified: the structure of `workout_player_page.dart` beyond its class list (the set-entry widgets, units and weight step are therefore reused by reference, not copied); `home_page.dart` insertion points; whether S03D's dock/strip and `windowSizeClass` provider will exist when Live Coach is built (dependency, section 12.1).

## 3. Design principles

1. Honesty over polish. The UI shows only what the Workout Runtime acknowledged. Anything heard, sent, proposed or guessed is visibly "not yet" until acknowledged (section 13).
2. Three independent truths, always visible: microphone (is the app listening), connection (can the coach reach the cloud), save (what is stored). They never collapse into one "OK" light (section 4).
3. The workout never depends on the coach. Every voice action has a tap equivalent that works with the network and the AI off (AICR-074, 075).
4. Voice-first, glance-second, touch-third. Spoken output always has a caption; every tap target is sized for a sweaty one-handed thumb; nothing important lives only in sound, colour or animation.
5. Microphone state is never ambiguous. On screen, in the shell strip and in the notification, the user can always see whether the mic is open.
6. Irreversible or high-risk actions are never one accidental touch, never on the lock screen or notification, and never decided by a misheard word.
7. Reuse, do not invent. New surfaces are compositions of the HUD primitives (U-F2). No new blur radius, colour or type family. Reduced motion and light-theme contrast rules of S03D apply unchanged.
8. Safety copy does not diagnose and does not reassure. It says stop, rest, and get help; the legal wording belongs to the operator.

## 4. State model the UI renders

The UI renders three independent state channels plus one derived banner. It never infers one channel from another (draft section 5: "audio state is separate from workout state").

### 4.1 Voice channel (draft section 5, AICR-005)

| Voice state | Indicator word (DRAFT) | Mic | What the user may do | Notes |
|---|---|---|---|---|
| STOPPED | Voice off | closed | Start voice; use manual controls | Default when no session or after End voice |
| INITIALIZING | Connecting | closed until LISTENING | Cancel | Static text, no looping spinner (S03D rule); timeout in T-1 |
| LISTENING | Listening | open | Speak; mute; stop voice | The only state in which commands are accepted. Sub-states: NO_MATCH (notice "I did not catch that. Say it again, or tap.", short cue, back to Listening) and LOW_CONFIDENCE (a ConfirmPrompt before anything is sent) |
| PROCESSING | Thinking | open or closed (OPEN UQ-12) | Wait; mute | After T-2 the word becomes "Still working" |
| SPEAKING | Coach is speaking | open if barge-in on (OPEN UQ-12) | Speak to interrupt; tap Stop talking | Caption streams in step with speech |
| INTERRUPTED | shown as Listening | open | Speak | Transient (the draft state exists for the machine; the UI does not show a separate screen for it) |
| RECONNECTING | Reconnecting | closed | Use manual controls; stop voice | Local timer unaffected (AICR-031) |
| PAUSED | Paused, with a reason line | closed | Resume listening; stop voice | Reasons: muted by you (user-mute is a valid PAUSED transition, added to the voice table; unmute returns to LISTENING), phone call, headset disconnected, audio taken by another app, permission removed, safety stop, system (battery or OS limit) |

Mic indicator truth (SF-5, A5.1): the Mic chip, the shell strip and the notification render only from the port events `captureStarted`, `captureStopped` and `captureLost` plus a liveness watchdog; never from the requested voice state or from a returned `stop()` call. Display values: "Microphone on" (captureStarted and watchdog fresh), "Microphone off" (captureStopped received), and "Mic state unknown" (watchdog expired, captureLost, or `stop()` failed without a captureStopped). Unknown is shown with a distinct icon and the action "Stop voice" (retries the stop); the UI never shows "off" because a stop call failed to throw. Default listening mode in the MVP is tap-to-talk (or hands-free only with a headset) until the gym trial; always-on is OPEN (UQ-12). After each accepted utterance an acknowledgement cue (earcon plus vibration, section 8.2) tells the user the phrase was taken.

### 4.2 Workout channel (draft section 6, AICR-024)

The HUD renders Runtime snapshots. States: NOT_STARTED, PREPARING, ACTIVE_EXERCISE, SET_IN_PROGRESS, SET_RECORDED, RESTING, NEXT_EXERCISE, PAUSED, COMPLETED, ABANDONED. The UI holds no workout state of its own; a tap or a voice command sends a command envelope and the HUD changes only on the acknowledgement (section 13). Note (FACT code map D1, D4): this state machine does not exist in code yet; the HUD contract is written against the draft's definition.

### 4.3 Connection / AI / safety channel

| Condition | Trigger | UI consequence |
|---|---|---|
| Online | Network and AI endpoint reachable | Normal |
| Reconnecting | Short loss while a session is live | Banner "Reconnecting"; voice RECONNECTING; manual controls fully enabled |
| Offline (long) | Reconnecting beyond T-4, or airplane mode | AI-unavailable manual mode, reason `offline` (LC-9) |
| AI unavailable, other typed reason | `serverError`, `killSwitch`, `dailyLimit` (AICR-078) | AI-unavailable manual mode with the matching reason copy; no retry is offered when it cannot succeed |
| Safety check unavailable | Mandatory check cannot run (AICR-050, fail-closed) | Banner; load and exercise suggestions, replacement and plan changes are disabled with reason. Recording a performed fact (`record_set`, `correct_set`, `void_set`) and `pause_workout`, `skip_rest`, `finish_workout` are never disabled (section 4.6; SF-7) |
| Safety stop | Dangerous symptom reported (AICR-051) | LC-8 takes over the screen at once, from the in-memory state. A journal failure never undoes it; it only adds the notice "Could not save this on the phone" (SF-1) |
| Sync blocked | A replica record was permanently rejected, or exceeded its attempt or age limit | Save chip "Sync blocked" (LC-5 6.3); copy never blames the connection for a rejection (SF-8) |
| Not the owner | This device is not the session owner (`ownerDeviceId` differs) | Read-only second-device state, section 6 LC-15 (AR-1..5, UX-11) |

### 4.4 One banner at a time

The screen shows at most one banner. Priority, highest first: (1) safety stop (full panel, not a banner), (2) not the owner device (read-only state, LC-15), (3) permission removed or microphone taken, (4) safety check unavailable, (5) sync blocked, (6) AI unavailable (any reason), (7) reconnecting, (8) voice paused with reason, (9) nothing. A lower-priority condition is still listed in the status row (section 7, C-2) so the user can read all three channels; it simply does not stack a second banner. Banner changes are announced once (section 11).

### 4.5 Command result lifecycle (what each user request looks like)

Every state-changing request, spoken or tapped, passes through the same visible lifecycle. This is the main anti-fake-success mechanism.

| Step | Visible as | Counts toward totals | Spoken |
|---|---|---|---|
| Heard | Live transcript line, grey, "Listening..." style until final | No | No |
| Understood (final utterance) | User bubble, final text | No | Possibly a read-back question |
| Pending (envelope sent, no ack) | Result card with hollow dot and the word "Saving" | No | Nothing yet |
| Confirmed (Runtime ack, journaled) | Result card with filled dot and the word "Saved" or the verb done (e.g. "Rest started"); a recorded set also shows the actions Undo and Correct (section 4.7) | Yes | Spoken after this point only; the spoken text is generated on the device from the acknowledged values (section 10 rule 12) |
| Rejected (typed reason) | Result card with "Not done" and a reason line from the copy table | No | Reason spoken briefly |
| Not confirmed (no ack from the dispatch result AND the journal head does not contain the command) | Result card with the word "Not confirmed" and actions Check / Try again | No | "I could not confirm that" |
| Late acknowledgement after Not confirmed | The same card upgrades to Saved (filled dot, announced politely once); it never becomes a second card | Yes, from this moment | Spoken success text only now |
| Duplicate ignored (same `command_id`) | Existing card unchanged; no second card | No change | Nothing |
| Heard but not matched (NO_MATCH) or low confidence | Notice line "I did not catch that. Say it again, or tap." (no result card; low-confidence numbers show a ConfirmPrompt before any command is sent) | No | The short "did not catch" cue, no success words |

Rules: Try again re-sends the same envelope (same `command_id`), so it cannot create a second set (AICR-046); the retry is idempotent and the card shows "Checking" while it runs (UX-12). The dispatch result from the Runtime is authoritative for the UI; before showing "Not confirmed" the UI reconciles against the journal head, and the T-3 timer is a UI display parameter, not the persistence timeout (SF-12). An edited value is a new command with a new id. The coach never says the word "saved" (or any success verb) before the Confirmed step (AICR-027). A manual tap mints its `command_id` when the entry sheet opens, and the Save control is disabled from the tap until the acknowledgement or a Not confirmed result (SF-11); a second tap on a disabled control does nothing. The duplicate-suspect question (T-6) applies to taps and to voice alike.

### 4.6 Shared allowed-action table (single source for banner copy, dock enablement and tests)

Y = allowed and enabled; N = disabled with the reason in the semantics value; U = user-only (a tap on screen or the headset button; a voice command or model tool call is refused). Banner text and tests for each condition are derived from this table; a copy change that contradicts a cell is a defect (SF-7, A1).

| Action (Runtime command) | Normal | Safety check unavailable | Safety stop lock | AI unavailable / offline | Not the owner device | Journal write failing (manual-only mode) |
|---|---|---|---|---|---|---|
| `record_set` | Y | Y | Y (a performed set is a fact; recorded, not coached) | Y (tap only) | N (read-only) | Y in memory, notice "Not saved on this phone" |
| `correct_set`, `void_set` | Y | Y | Y | Y (tap only) | N | Y in memory, same notice |
| `pause_workout` | Y | Y | Y (already paused) | Y | N | Y |
| `skip_rest` | Y | Y | N (rest is frozen while the lock is on) | Y | N | Y |
| `add_rest_time` | Y | Y | N (rest is frozen) | Y | N | Y |
| `finish_workout` | Y after confirm | Y after confirm | U | Y after confirm | N | Y after confirm |
| `abandon_workout` | Y after confirm (More) | Y after confirm | U | Y after confirm | N | Y after confirm |
| `resume_workout` | Y | Y | U, two-step (LC-8) | Y | N | Y |
| `start_set`, derived "next exercise" | Y | Y | N | Y | N | Y |
| Replace exercise, plan change, load suggestion | Y after confirm | N (reason shown) | N | N (needs the coach) | N | Y |
| Pain or unwell report | Y | Y | Y | Y | Y shown as a local stop on this device only (PROPOSED, OPEN UQ-22: how a report from a non-owner reaches the owner) | Y |
| Start / mute / stop voice | Y | Y | Mute and Stop only | Stop only | Stop only | Y |

The banner for "Safety check unavailable" therefore never says "Logging and timers work" in a way that hides a disabled row: it names exactly the disabled group ("suggestions, replacement and plan changes are paused"). The copy for every other condition names only what the table disables.

### 4.7 Undo and correction of a recorded set

1. Saved card (set): shows the values, the word "Saved", and two actions of at least 48 dp: "Undo" and "Correct". Undo sends `void_set(set_id)`; Correct opens the SetEntrySheet in Correct mode and sends `correct_set(set_id, reps, weight_kg, effort)`. Both append a correction record; the earlier record stays in the journal (never rewritten).
2. Within T-5 (10 s) the Undo action is the visible primary action on the card, labelled "Undo" with a visible remaining-time ring (static, no sweep with reduced motion); the coach says "Undone" only after the acknowledgement.
3. After T-5 the card does not lose the path: Undo is replaced by "Edit set" (opens Correct mode) and "Remove set" (a `void_set`, with a ConfirmPrompt because it changes totals). The same two actions exist on every row of the set list for the whole session, and in LC-12 before Done is tapped. Voice: "change the last set to ten" or "remove the last set" use the same commands and are read back.
4. A void or correction is a card of its own ("Set 2 removed", "Set 2 changed to ten reps, sixty kilograms") with the lifecycle of 4.5. Totals, set counters and the summary use the latest valid record only; the set list shows a quiet "edited" tag on a corrected row.
5. Implausible values (outside the closed plausibility bounds table owned by the Runtime, e.g. reps above 100, weight above the bound, a value that is 5 times the last recorded value) are never sent from voice without a confirm-first prompt: "Did you mean {n} reps at {w} kilograms?" Yes / No; the same prompt appears for tapped values behind the sheet's Save button. No answer within T-7 means No and nothing is recorded. The bounds are an OPEN item (UQ-21).
6. A correction that is Rejected leaves the original row unchanged and shows the typed reason.

## 5. Journeys

Each journey lists the happy path, the failure paths, and where the UI proves honesty. Screen ids (LC-n) refer to section 6. All text is DRAFT.

### J1. First use: discover, consent, permissions, first session
Preconditions: flag `live_ai_coach_enabled` on; signed in; onboarding done.
1. Entry card on Home "Train with your coach" (LC-1). Hidden entirely when the flag is off (AICR-067).
2. If mandatory screening is incomplete: LC-1 shows the typed block reason and a link to the existing screening; no session can start (AICR-012). Manual workouts are untouched.
3. Age gate (existing age policy, no relaxation) comes before any microphone or consent screen: a user the policy excludes never sees LC-2 or LC-3 and sees the LC-1 blocked copy instead (UX-13). Then the voice-data consent screen (LC-2). Accept continues; "Not now" returns with the manual path intact and a re-prompt cadence; "No thanks, do not ask again" is a separate firm decline (AICR-009).
4. Microphone permission rationale (LC-3), then the OS dialog; then, if needed, notification permission rationale.
5. Pre-start sheet (LC-4): today's plan, headset hint, connection status, Start.
6. LC-5 opens in INITIALIZING then LISTENING; the coach greets and asks what to do (first-use "What you can say" hints visible).
Failure paths: consent declined; permission denied once; permanently denied; no network (offers manual workout); safety unavailable. Each lands on a named state in section 6, never on a blank screen.

### J2. Start a voice session (returning user)
Home card or the workout entry -> LC-4 (skipped when nothing needs the user's attention: consent current, permissions granted, plan known) -> LC-5. Capture starts only after this explicit tap (AICR-040). The Start button is a foreground user action; there is no auto-start from the lock screen, location or boot.

### J3. Hands-free set (the core loop)
1. HUD shows exercise "Goblet squat, set 2 of 3, target 8-10 reps". Coach speaks the cue (caption identical).
2. User performs the set and says "eight at sixty" (or taps Log set).
3. Transcript shows the final text; result card shows `8 reps · 60 kg`, Pending.
4. Runtime acknowledges: card turns Saved, set list gains a row, HUD advances to RESTING, coach speaks "Set two saved: eight reps, sixty kilograms. Rest ninety seconds." (spoken after ack only).
5. A repeat of the same recognised utterance does not add a card (AICR-004, E2E-04). A new utterance with identical values within T-6 triggers the duplicate-suspect question "Another set, or the same one?" (PROPOSED, OPEN UQ-06).
6. Correction: "no, ten reps" within the correction window T-5, or tap Undo / Correct on the Saved card or any set row at any time (section 4.7). Correction is a new journaled `correct_set` or `void_set` command; the earlier value stays in the journal. These commands are a P0 requirement of the Runtime (closed command set additions in `06_REMEDIATION_DECISIONS.md` A2.6). After T-5 the path remains (Edit set, Remove set); only the one-tap Undo prominence expires.
Failure paths: low-confidence numbers -> the coach asks to confirm before sending; implausible numbers -> confirm-first prompt (4.7 rule 5); rejected number (negative, above the safety limit) -> Rejected card with reason; no ack -> Not confirmed card, which upgrades to Saved if a late acknowledgement arrives.

### J4. Rest
1. After Saved, RESTING starts with the planned seconds. The HUD shows a large countdown (ring plus digits) driven by the local timer, not by the coach.
2. Voice or taps: "add thirty seconds", "pause rest", "skip rest" (tap equivalents on the dock). Each is a command with a result card.
3. End of rest: a local cue (tone, vibration, and local text-to-speech "Rest over") fires even if the cloud coach is down (AICR-031). Honest labelling: when the coach cannot speak, the cue is attributed to the timer, not to the coach (section 9.2). The countdown is rendered from the Runtime's absolute `restEndsAt`, not from a screen timer. If the process is killed, an OS-scheduled notification at `restEndsAt` is the backstop (exact-alarm permission analysis is OPEN, UQ-23; default: a non-exact notification, so the cue may be late). While a safety lock is on, the countdown is frozen and shows "Rest paused" and no rest cue (tone, vibration, speech or notification) is produced.
4. The next set starts when the user says "ready" or taps Start set; the app never starts a set on its own.

### J5. Interrupt (barge-in)
User speaks while the coach is speaking: playback stops, the indicator shows Listening, the caption of the interrupted reply is cut with a visible "(interrupted)" marker (never hidden), and the new utterance is processed (AICR-002). The same effect is available by tapping Stop talking (large button visible only in SPEAKING). If a half-heard word arrives, partial hypotheses never trigger a command (AICR-003).

### J6. Replace a machine that is busy
1. "Someone is using the leg press." / tap Replace.
2. Replace sheet (LC-10) lists up to 3 alternatives that already passed equipment, restriction and Safety checks, each with a one-line reason chip from the closed reason list (AICR-033, 019).
3. User picks by tap or says "number two". Because replacement changes the plan, it requires a confirm step (section 8.3): read-back "Replace leg press with hack squat?" Yes/No.
4. Confirmed card: "Exercise replaced". The history still shows the original exercise as replaced (AICR-034).
Failure paths: no safe alternative -> "No safe replacement found. You can skip this exercise." with Skip and Finish; safety check unavailable -> replacement disabled with reason; busy machine not recognised -> coach asks which exercise.

### J7. Report pain or feeling unwell
1. Entry points: a persistent "Pain or unwell" control on LC-5, pinned in the header area outside the scrolling quick-action bar, always visible, never hidden by scroll or avatar and never disabled by any state in section 4.6 (UX-17); the phrase "I have chest pain" (any phrasing the Safety Engine classifies); a notification action is NOT provided (section 9.5).
2. Tap opens the symptom sheet (LC-11): Chest pain or pressure / Dizzy, faint or short of breath / Sharp joint or muscle pain / Something else.
3. Scope of the stop (A1.4): chest, dizziness, fainting or breathing options go straight to LC-8 and stop the whole workout (state PAUSED with the safety lock). A joint or muscle pain option stops the current exercise only and shows a short sheet: Replace exercise / Skip exercise / Finish workout (the workout stays ACTIVE for the other exercises unless the user picks Finish; the current exercise's rest and cues are frozen until the user chooses). "Something else" opens a free-text or voice field; the text is classified on the device only, against a closed symptom list, and never leaves the phone; when it cannot be classified the result is pause (PAUSED with the safety lock), not a guess. The list of symptoms and who signs it are OPEN (OQ-07, OQ-20): the symptom stop cannot ship until it is signed.
4. The workout becomes PAUSED with the safety lock. No continue action is issued by the coach (AICR-051). Resuming requires an explicit on-screen user action on LC-8; voice alone can never clear the lock (the "distinct confirmed phrase" option is withdrawn; UX-3).
5. The stop is applied in memory and on screen first. If the journal write fails, LC-8 stays and a small notice "Could not save this on the phone" is added; the stop is never undone by a storage failure (SF-1).
6. While the lock is on, the rest countdown is frozen and rest cues are suppressed (section J4), and `finish_workout` and `abandon_workout` are user-only (4.6).
Voice reports follow the same result: LC-8 appears no matter how the report arrived, even with the screen locked (then a high-importance notification, section 9.5).

### J8. Lost network
1. Voice moves to RECONNECTING; banner "Reconnecting. Your timer and manual logging still work."
2. Rest timer continues (rendered from `restEndsAt`); set logging by tap continues and is saved locally and marked "Waiting to sync". "Waiting to sync" is used only while the cause is connectivity; a rejected record becomes "Sync blocked" (LC-5 6.3) and never uses connection wording.
3. If the network returns within T-4: the session returns to LISTENING with no user action (AICR-008); banner clears; the status row briefly shows "Back online".
4. Beyond T-4: LC-9 (AI unavailable, reason `offline`). No fake coach replies; typed or voice input is disabled (or limited to local commands, OPEN UQ-10). After reconnect the Runtime reconciles; the UI shows "Checking your workout..." then the final save status. Voice resumes only if the audio state allows (AICR-044); otherwise the Resume listening button appears.

### J9. Incoming phone call
Audio focus is lost: voice goes to PAUSED, reason "Phone call". The mic closes. The rest timer keeps running (unless a safety lock is on, in which case it is frozen and silent); its end cue is vibration and a visual alert, because speaking over a call is not allowed. When the call ends, the screen shows Resume listening and so does the notification action. Auto-resume without a tap is OPEN (UQ-11); the default PROPOSED is tap to resume (privacy: the mic does not reopen by itself). The workout state is unchanged (AICR-041, E2E-05).

### J10. Bluetooth headset drops
Headset disconnect: the coach stops speaking immediately (never continues on the loudspeaker in a gym) and voice goes to PAUSED, reason "Headset disconnected". The screen offers Reconnect (re-checks the route), Use phone (speaker and phone mic, with a clear sound-out warning), and Stop voice. The timer continues; cues vibrate. When the headset returns, the same Resume listening control appears (AICR-007, 041, E2E-06).

### J11. Locked screen
1. The user locks the phone or it times out with the session live. Capture continues under the foreground service; the notification shows state and mic status (section 9.5).
2. All coach interactions remain voice. No workout content that is private is shown on the lock screen (section 9.5).
3. Lock screen shows no avatar; the 3D avatar on a locked screen is a non-goal (NG-4).
4. Unlocking returns to LC-5 in its current state. If the OS killed the service, see J13.
Pocket touch: with the screen on and the phone in a pocket, accidental touches are a real risk; protections are in section 9.4 and UQ-07.

### J12. Finish
1. "Finish workout" by voice or the More menu.
2. Confirm prompt (section 8.3): "Finish workout? 14 sets saved." Yes / Keep going. Spoken and tapped confirm are both valid; silence cancels after T-7 (extended when a screen reader is active, section 11).
3. Voice session ends and the mic closes; the notification disappears; LC-12 (summary) shows totals derived from stored data only (AICR-061, E2E-12). If some items are still waiting to sync: "Saved on this phone. 3 items will sync when you are online." Never "synced" before it is.
Failure paths: finish while offline (allowed); finish with a Pending card (the prompt says "1 set is still saving" and Finish waits for it or lists it as Not confirmed). Finish and abandon are confirmed on the screen (or with the headset button when one is connected) rather than by an ambient spoken "yes" alone, where a screen or headset is available (SE-18, A6.5); with the phone in a pocket and no headset the spoken Yes remains valid and the prompt says so.

### J13. Resume after a crash or restart
1. On the next app start, if the journal holds a non-closed live session, LC-13 (resume prompt) opens before Home content that would hide it.
2. It shows the last saved set with its time, the count of saved sets, and three actions: Continue workout, Finish workout (keeps everything saved), Not now.
3. Continue opens LC-5 in the manual-ready state with the coach off; the user starts voice with an explicit tap. The microphone never starts by itself after a restart (AICR-040).
4. There is no Discard action on this prompt (confirmed results are never thrown away from here; deletion is a history action).
Honest wording: "A set you were doing when the app closed may not be saved. Check your list." The UI never says that nothing was lost.
5. The prompt appears even when the feature flag is off, expired or unreachable: the flag gates only the start of new sessions, never an unfinished one (SF-9, A4.3). Reason line when the flag is off: "The coach is switched off for new workouts. You can finish this one." Continue then opens LC-5 in manual mode.
6. Where the data is: the prompt and the abandoned/finish summaries say where the sets are kept. A live session's sets are on this phone in the live-session record, not in History, until the workout is finished and projected. Unfinished journals are never auto-deleted; there is no timer that removes them (A3.1).
7. Second device: if the unfinished session belongs to another device the prompt is replaced by LC-15 (read-only).

### J14. AI unavailable: manual workout continues (E2E-10)
A mid-session AI failure or a start with no AI turns LC-5 into manual mode (LC-9): same HUD, same dock, same set entry; the conversation view shows a single honest notice; no typed or voice input; quick actions remain. "Try coach again" appears only for reasons that can succeed, with a visible cooldown (AICR-036, 075).

### J15. Permission removed or microphone taken during a session
The user revokes the microphone in system settings, or another app takes the mic. Voice goes to PAUSED with the matching reason, the workout continues, and the banner offers "Open settings" (revoked) or "Resume listening" (taken). The foreground notification updates.

### J16. Review and accept a proposed plan
At home or in the gym the coach proposes a 1-4 week plan (AICR-015). LC-6 shows it as a reviewable card. Accept, Reject and Change are all available; Accept needs an explicit confirm; Reject leaves nothing scheduled (AICR-018). The explanation chips are drawn from the data's reason codes, never from model text (AICR-019, 020).

### J17. Stop voice, withdraw consent, delete data
Stop voice is always one tap (mic control or End voice) and ends capture while the workout continues manually (AICR-006). Withdrawing consent (LC-14) ends any live session at once and returns to manual mode. Withdrawal is applied locally first: a persistent local flag is set, capture is blocked from that moment, and the server record is updated afterwards. If the flag cannot be persisted the screen shows the withdrawal failure state (LC-14) and capture stays blocked for the rest of the app run (SF-14, SE-13). Deleting coach memory and exporting it are in LC-14 (AICR-060, P1).

## 6. Screens and states

State vocabulary: EMPTY, LOADING, LISTENING, PROCESSING, SPEAKING, RECONNECTING, PAUSED, ERROR, AI-UNAVAILABLE (manual), CONSENT, PERMISSION-DENIED, SAFETY-STOP, SUCCESS, OFFLINE. "n/a" states state the reason. Screen keys use `Key('liveCoach....')`; key names are PROPOSED and part of the test contract.

### LC-1. Entry point (card on Home / Workouts, strip on the shell)
Purpose: start or return to a Live Coach session.
Layout: `HudPanel` card, title, one sentence, primary `HudButton` (min 56 dp), and a status chip. Registered also as a source of the S03D shell strip, so a live session is visible on all five tabs.

| State | Behaviour and copy (DRAFT) |
|---|---|
| Flag off (no unfinished session) | Card absent. Route unreachable for starting a new session (AICR-067). The flag, whether expired, unreachable or off, never hides an unfinished session (next row). |
| EMPTY (no plan for today) | Title "No workout planned today". Actions: "Ask the coach to plan one" (needs network; disabled offline with the reason) and "Pick exercises yourself" (classic path). |
| Ready | Title "Train with your coach". Body (conditional, UX-7): "Talk to your coach while you train." by default; "Hands-free. Phone can stay in your pocket." only when the device passed the locked-screen capability check (foreground service microphone type works on this device and notification permission is granted); otherwise the body adds "Keep the screen on while you use voice." Button "Start". |
| Unfinished session while flag is off | The card is absent for new sessions, but LC-13 and the shell strip still appear for an unfinished session, with the reason line "The coach is switched off for new workouts. You can finish this one." (SF-9, A4.3) |
| Session live (strip) | Strip text "Coach listening, mic on" / "Coach paused" / "Resting 0:45"; tap returns to LC-5. Never just "Active". |
| Blocked: screening incomplete | Body "Finish your health check first. The coach cannot plan or start a workout without it." Button "Open health check". Typed reason, no retry. |
| Blocked: age or restriction policy | Reason line from the existing eligibility reason text (reuse, no new rule). Button hidden or disabled with the reason. |
| Consent missing | Button label "Set up voice". |
| LOADING | Static placeholder "Checking" for at most T-1, no spinner. |
| ERROR | "Coach is not available right now. You can still train yourself." + "Start without coach". |
| OFFLINE | "No connection. You can still train yourself." Start without coach only. |
| Resume available | Replaced by LC-13. |

Keys: `liveCoach.entry.card`, `liveCoach.entry.start`, `liveCoach.entry.manual`.

### LC-2. Voice consent and privacy screen (UI requirements only)
Purpose: obtain explicit voice-data consent before any capture (AICR-009, NFR-09). Full-screen page or large sheet, scrollable, not dismissed by a stray tap outside.

Required content blocks (text is `[LEGAL TEXT]` supplied by the operator; the UI requirements are binding):
1. What happens, in plain words, as a short list that fits one screen without scrolling at text scale 1.0: the microphone is used only while a voice session is on; what you say is processed by a server and an AI service; raw audio is not stored by default (AICR-076); you can stop at any time; the workout works without the coach.
2. A "More details" row that expands to the full privacy text; reading it is optional and does not gate the buttons.
3. Three choices, the first two of equal size and weight: "Agree and continue" and "Not now", plus a text button "No thanks, do not ask again" (firm decline). "Not now" means ask later: the next offer is shown at most once per 7 days and after at most 3 "Not now" answers the screen is no longer offered unprompted (it stays reachable from "Set up voice"); the cadence numbers are PROPOSED and OPEN (UQ-24). The firm decline stores the choice, stops all prompts, and only "Set up voice" in Coach settings can reopen the screen. No pre-ticked boxes; no consequence text that shames the user for declining; no countdown. Neither button is labelled in a way that hides the difference: "Not now" never sounds like a permanent refusal and the firm decline never sounds like postponement (UX-13).
3a. The utterance is a health-bearing channel: the first block states that what you say, including anything about pain or health, is sent for processing (the wording is `[LEGAL TEXT]`; SE-1, A6.1). The consent screen names the speech recogniser and the model provider through placeholders `[PROVIDER NAMES]` (SE-13).
3b. Age gating comes before this screen (J1 step 3). Consent records version and timestamp per user; capture is refused without a current-version consent.
4. Separate optional items shown only when the feature exists, each off by default and with its own switch: long-term coach memory (P1, AICR-058), audio storage (not offered in MVP; the control is absent, not disabled, because the draft says raw audio is not stored by default).
5. Consent is versioned. A new version re-opens this screen the next time a session starts, showing what changed.
6. The date and version of the agreement are visible later in LC-14.
7. Minors: the screen follows the existing age policy; the flow for under-age users is not designed here (OPEN UQ-14).

States: LOADING (static), ERROR (consent could not be saved: "We could not save your choice. Nothing was recorded. Try again." with Retry and Not now; capture never starts without a stored consent), OFFLINE (consent can be given offline if it is stored locally; whether it must be recorded on a server first is OPEN UQ-14), DECLINED (Not now: returns to the entry with the manual path; the entry shows "Set up voice" for later; firm decline: the entry shows "Set up voice" only inside Coach settings). Keys: `liveCoach.consent.agree`, `liveCoach.consent.decline`, `liveCoach.consent.details`.

### LC-3. Permission rationale and denied states
Purpose: prepare and then recover from OS permission outcomes. A short in-app screen always comes BEFORE the OS dialog, explains why in one sentence, and offers "Continue" and "Not now". Nothing is requested at app launch or in the chooser (same rule as S03D principle 5).

| Permission | Why (DRAFT) | If denied once | If permanently denied | Effect on the workout |
|---|---|---|---|---|
| Microphone (`RECORD_AUDIO`) | "So the coach can hear you during your workout." | Panel "Without the microphone the coach cannot hear you." with "Ask again" and "Train without voice" | Same text; button "Open settings" replaces "Ask again" (deep link to app settings); "Train without voice" stays | Manual workout fully available |
| Notifications (Android 13+ `POST_NOTIFICATIONS`) | "So you can see when the microphone is on, and stop it from the lock screen." | Panel: voice works only while the screen is on and the app is open; background and locked-screen use are unavailable (AICR-039 requires the visible notification). "Ask again" / "Continue with screen on" | "Open settings" / "Continue with screen on" | Manual workout fully available |
| Bluetooth nearby devices (`BLUETOOTH_CONNECT`, Android 12+) | "So the coach can use your wireless headphones." | Voice works with the system's own audio routing; the app cannot show headset status; the row "Headset" shows "Not available" | "Open settings" optional | None |
| Battery optimisation exemption | Not requested at start. Offered only as a help article after repeated background interruptions (OPEN UQ-13). | n/a | n/a | n/a |

Rules: a denial never loops back to the same prompt; permission loss during a session follows J15; every denial state has a path to the manual workout. Keys: `liveCoach.permission.mic.continue`, `liveCoach.permission.mic.openSettings`.

### LC-4. Pre-start sheet
Purpose: one calm confirmation before the mic opens. `HudSheet`, not a full page, skipped when nothing needs attention (J2).
Content: today's workout name and exercise count, a three-line status list (Headset: connected / not connected / not available; Connection: online / offline; Coach safety checks: ready / unavailable), and the primary button "Start voice" (56 dp). Secondary: "Start without voice" (goes to LC-5 in manual mode).
States: safety checks unavailable -> line shows "Unavailable", Start voice stays enabled for helper actions but the plan summary notes that suggestions are paused; offline -> Start voice replaced by "Start without voice" with the reason; loading -> static "Checking".

### LC-5. Live Coach screen (main)
Purpose: the one screen the user returns to during the workout. Pushed route outside the shell (U-F1). Layout in compact portrait, top to bottom:
1. Header row: back arrow, workout title, the pinned "Pain or unwell" control (56 dp, outside every scrolling area, never disabled, UX-17), settings icon. The back arrow does not end the session; with the microphone open it shows the leave-with-mic-open sheet (section 9.6).
2. Status row C-2: Mic chip, Connection chip, Save chip (always visible, word plus icon).
3. Banner slot (one banner, section 4.4).
4. Workout HUD C-5: exercise name, set position, target, rest ring/countdown, "Next up".
5. Voice zone: voice indicator C-3 and, when enabled, the avatar C-4 beside it. The avatar can be hidden with one tap (the voice indicator remains).
6. Conversation view C-6 (flexible height; shows the last 3 items collapsed, expands to full height on tap).
7. Quick action bar C-8 (horizontal chips).
8. Hands-free control dock C-9, anchored at the bottom inside the safe area (primary actions in the lower 40% of the screen for one-handed reach).

Tab and focus order follows reading order: header, status row, banner, HUD, voice zone, conversation, quick actions, dock.

#### 6.1 Voice-state table for LC-5

| Voice state | Indicator | Avatar (P1) | Dock changes | Caption behaviour |
|---|---|---|---|---|
| STOPPED | Voice off, crossed mic | idle | "Start voice" is the primary dock button | Conversation shows a hint "Say or tap what you need" |
| LISTENING, tap-to-talk (MVP default) | "Tap to talk" until pressed, then "Listening" | listening | "Talk" button replaces Mute as the dock mic control; mic is open only while talking and for a short tail | Same as LISTENING |
| LISTENING, NO_MATCH | "Listening" | listening | Unchanged | Notice "I did not catch that. Say it again, or tap." with an ack cue of "not taken" (two short low tones) |
| Mic state unknown (watchdog) | "Mic state unknown" with a distinct icon | idle | "Stop voice" (retries the stop) | Notice once: "We cannot confirm the microphone is off. Tap Stop voice." |
| INITIALIZING | "Connecting", static dots | idle | Cancel | Notice "Connecting to your coach" |
| LISTENING | "Listening", filled mic dot | listening | Mute mic, Stop voice | Partial line appears while the user speaks |
| PROCESSING | "Thinking" (after T-2: "Still working") | thinking | Mute mic | Final user line committed |
| SPEAKING | "Coach is speaking" | speaking | Stop talking replaces Mute | Coach bubble grows with the speech |
| RECONNECTING | "Reconnecting" | idle, dimmed | Mute disabled; Stop voice | Notice once, no repeat |
| PAUSED (user mute) | "Muted, mic off" | idle | Primary "Unmute" | Notice once |
| PAUSED (phone call / headset / audio taken / system) | "Paused: {reason}" | idle | Primary "Resume listening" | Notice once with reason |
| PAUSED (permission removed) | "Paused: microphone off in settings" | idle | Primary "Open settings" | Notice once |
| PAUSED (safety stop) | LC-8 | warning | LC-8 | LC-8 |
| ERROR (voice session failed) | "Voice stopped" | idle | Primary "Try again" (if retry can succeed), "Train without voice" | Notice with plain sentence; no technical text |

#### 6.2 Workout-state table for the HUD

| Runtime state | HUD content (DRAFT where text) | Primary dock control |
|---|---|---|
| NOT_STARTED | Today's plan summary and "Start workout" | Start workout |
| PREPARING | "Getting ready", first exercise preview | Cancel |
| ACTIVE_EXERCISE | Exercise, set n of m, target reps, suggested load labelled "Plan", last time from history labelled "Last time" (only if stored; otherwise the line is absent, never zero) | Start set; "Log set" is also available and opens the SetEntrySheet |
| SET_IN_PROGRESS | Exercise, set n of m, elapsed set time (optional) | Log set: opens the SetEntrySheet pre-filled with the plan values; nothing is recorded until Save is tapped in the sheet (UX-7). The 64 dp primary control never records directly |
| SET_RECORDED | Saved set row highlighted for 3 s (no highlight and no auto-advance with reduced motion or the in-app reduce-animation row on), then rest; the Saved card keeps Undo and Correct (4.7) | Start rest (auto) |
| RESTING | Large ring plus digits rendered from `restEndsAt`; "Next: {exercise} set n"; buttons Add 30 s, Pause rest, Skip rest, each at least 56 dp tall and wide, 12 dp apart (UX-16) | Skip rest |
| NEXT_EXERCISE (derived view, not a state) | A view of ACTIVE_EXERCISE when the previous exercise has no sets left: "Next exercise: {name}", equipment hint, Replace link. The Runtime exposes no NEXT_EXERCISE state; tests assert the HUD from ACTIVE_EXERCISE plus an "is first set of a new exercise" flag (UX-11) | Start set |
| PAUSED | "Workout paused" with reason (you, call, safety). With a safety lock: "Workout paused after a symptom report", rest shown frozen as "Rest paused" | Resume workout (with a safety lock: the two-step of LC-8; user-only) |
| COMPLETED | goes to LC-12 | n/a |
| ABANDONED | goes to LC-12 with copy "Workout ended early" | n/a |

#### 6.3 Condition overlays for LC-5

| Condition | Banner text (DRAFT) | Controls |
|---|---|---|
| Reconnecting | "Reconnecting. Your timer and manual logging still work." | Manual controls enabled |
| AI unavailable: offline | "No connection. Train manually. Your sets are saved on this phone." | Voice, typed input, plan changes disabled |
| AI unavailable: service error | "The coach is not available right now. Train manually." + "Try again" (cooldown) | Same |
| AI unavailable: kill switch | "The coach is switched off for now. You can still train yourself." No retry | Same |
| AI unavailable: daily limit | "You have used today's coach time. You can still train yourself." No retry | Same |
| Safety check unavailable | "The coach cannot check suggestions safely right now, so it will not suggest new exercises, loads, replacements or plan changes. You can still log sets, pause, skip rest and finish." | Per the allowed-action table (4.6): Replace, plan change and load suggestion disabled with reason; `record_set`, `correct_set`, `void_set`, `pause_workout`, `skip_rest`, `finish_workout` stay enabled (AICR-050, SF-7) |
| Waiting to sync | Save chip: "3 waiting to sync" (cause is connectivity only) | None blocked |
| Sync blocked | Save chip: "Sync blocked" (word plus icon); tap opens an explanation sheet: "Some sets are saved on this phone but the server did not accept them. They are kept. This is not a connection problem." with "Keep on this phone" and "Export" (no Delete here). Never the words offline, connection or "will sync when you are online" (SF-8, A3.3) | None blocked; totals and Saved state of the sets are unchanged |
| Journal write failing | Save chip: "Not saved on this phone" and notice "Your sets are kept in the app for now. Do not close the app." Manual-only mode (A3.5) | Per 4.6 last column |
| Not the owner | LC-15 read-only state | See LC-15 |
| Mic state unknown | Banner not used; status-row chip "Mic state unknown" plus Stop voice action | Manual |
| Permission removed | "Microphone is off in settings." + Open settings | Manual |
| Another app has the microphone | "Another app is using the microphone." + Resume listening | Manual |

#### 6.4 Empty, loading and error states of LC-5

| State | Behaviour |
|---|---|
| EMPTY conversation | Shows "What you can say" with 4 examples as tappable chips (Start workout, Next exercise, I did eight at sixty, Skip rest). Chips are also the accessible alternative to voice. |
| EMPTY plan | LC-1 EMPTY copy inside the HUD slot, with the same two actions. |
| LOADING | Only the INITIALIZING state, static text; a timeout after T-1 becomes ERROR "Could not connect to the coach" with Try again and Train without voice. |
| ERROR (screen-level: runtime cannot load) | Plain sentence "We could not load your workout." + Retry + "Open classic workout" (the existing player) - OPEN UQ-02 whether the classic player may take over a session. |

Keys: `liveCoach.page`, `liveCoach.statusRow`, `liveCoach.banner`, `liveCoach.hud`, `liveCoach.voiceIndicator`, `liveCoach.avatar`, `liveCoach.conversation`, `liveCoach.quickActions`, `liveCoach.dock`.

### LC-6. Plan review (proposal and explanation)
Purpose: show a coach-proposed plan for 1-4 weeks and why (AICR-015..020). Full page; reachable from the conversation ("Open plan") and from Home.
Layout: header with plan horizon and goal; week tabs; day cards; each exercise row shows sets x reps range, rest, and reason chips from the closed reason list (user goal, experience, available equipment, recent training, safety status). A "Coach explanation" block is clearly labelled as spoken/written by the coach and cites only chips present on the row.
Actions: Accept (confirm step), Change (opens the conversation with the plan focused), Reject (the plan is not activated, nothing scheduled, undo not needed).
States: LOADING (static "Building your plan" for at most T-1, then keeps working in the background if the user leaves), EMPTY (no plan), ERROR ("The plan could not be built. Try again."), REFUSED (typed refusal: screening incomplete, restriction, equipment) shown with the reason and one next step, OFFLINE (plans already stored are readable; building a new one is disabled with the reason). Restriction changes the coach proposes appear as a confirm card (section 8.3); a restriction is never changed by a spoken guess (AICR-011).

### LC-7. Conversation-only states (inside LC-5, specified separately for the transcript)
See component C-6. States: EMPTY (hints), STREAMING (coach bubble grows), PARTIAL USER LINE, INTERRUPTED (marker), NOTICE (system sentence), RESULT CARD (section 4.5), ERROR LINE (a failed turn shows "I could not answer that" with "Say it again"), and HISTORY (scrolled up; "Jump to latest" chip appears when new items arrive).

### LC-8. Safety stop panel
Purpose: stop the workout calmly and unmistakably after a reported dangerous symptom (AICR-051).
Appearance: replaces the dock and HUD contents as a full-screen panel inside LC-5 (the status row stays). High-contrast filled panel with ink text; the warning icon plus words carry the meaning, never colour alone (U-F4).
Content (DRAFT, operator/clinical review required, not legal text):
- Title "Stop now."
- Body "Sit down and rest. If you have chest pain, feel faint, or it does not pass, get medical help."
- Primary: "Call emergency services" (opens the dialer with the emergency number chosen from a per-locale table that the operator signs; no number is hard-coded in the app; OPEN UQ-09, new item "emergency number table"). When the locale has no signed entry the button is hidden and the body text adds "Call your local emergency number."
- Secondary: "Finish workout" (user-only action, confirm required).
- Tertiary (text button, spaced away from the others): "I am OK, show my workout".
The coach says the same short text once and then goes silent. The mic stays under the user's control: Mute is available; the coach does not ask follow-up questions that could be misread as coaching.
Lock: the lock is set the moment the stop is applied (in memory, before any save). Rest countdown is frozen with the label "Rest paused", all rest cues are suppressed, and `skip_rest`, `add_rest_time` and `start_set` are disabled (4.6). `record_set`, `correct_set`, `void_set` and `pause_workout` stay available behind "Show my workout" so a set already performed is never lost.
Resume: "Show my workout" returns to LC-5 in PAUSED with the banner "Workout paused after a symptom report." Resume workout then requires a deliberate two-step on screen: tap Resume workout, then confirm "Are you feeling well enough to continue?" Yes / No. Voice alone, a headset button, the notification and a model tool call can never clear the lock; a spoken "continue" produces only the line "Use the screen to resume." (UX-3; OPEN UQ-09 only for the wording). The coach never says "continue" or "you can keep going" (AICR-051).
Persistence failure: if the journal write failed, a one-line notice "Could not save this on the phone" appears under the title; the panel and the lock are unchanged.
Locked screen: the same event posts a high-importance notification "Workout paused. Open the app." with no actions. Whether a Call action may be added to it is OPEN (UQ-09; default: no call action).
States: this panel has no loading, empty or offline variants: it works fully offline because the stop is local. If the dialer is unavailable (tablet) or no signed number exists: the call button is hidden, the text remains. The joint or muscle pain variant (J7 step 3) is a smaller sheet, not this panel, and does not set the whole-workout lock.

### LC-9. AI-unavailable manual mode (state of LC-5)
Same HUD, same dock, same set entry and rest controls; conversation view shows one notice with the reason (copy in 6.3); mic chip shows "Off"; voice indicator shows "Voice off"; the avatar is hidden or idle-dimmed; typed input disabled. Quick actions stay. Retry control per reason (6.3). Switching back to live coach mid-session never replays missed commands; the Runtime reconciles (AICR-044).

### LC-10. Replace exercise sheet
`HudSheet`, up to 3 candidate rows (name, equipment, reason chip, "Safe for you" is NOT a phrase used; the row only shows reason chips). A row is a 56 dp target. After a pick, the confirm prompt (section 8.3). Empty: "No safe replacement found." Safety unavailable: sheet shows the reason and no candidates. Keys: `liveCoach.replace.sheet`, `liveCoach.replace.row.<n>`.

### LC-11. Symptom report sheet
As J7. Rows are 64 dp, full width, labelled with plain words. The sheet is reachable in at most 2 taps from LC-5 with the screen on; nothing on it is pre-selected. Cancel closes without effect.

### LC-12. Finish summary
Purpose: close the loop and reconcile (AICR-061, E2E-12). Content: "Workout finished", duration, exercises, sets saved, total reps and volume derived from the stored session (latest valid record per set after corrections); a status line "Saved on this phone" or "Saved and synced" or "3 items will sync when you are online" (connectivity cause only) or "Sync blocked. Your sets are kept on this phone." (rejection cause); each set row offers Edit set and Remove set until Done is tapped (4.7); actions Done and "View in history". The P1 coach summary is a collapsible block labelled "Coach summary" that cites only numbers that equal the stored totals (otherwise the block is absent). States: LOADING (static), ERROR ("We could not read your saved sets just now. Try again. Nothing was deleted." - it never claims the sets are saved when the read failed; SF-18), OFFLINE (as above), ABANDONED ("Workout ended early. {n} sets are kept on this phone. They are not in History." with actions "Keep on this phone", "Export" and "Delete" (Delete asks a confirm; an abandoned journal is removed only after the user chooses delete or export; SF-17, A3.1)).

### LC-13. Resume prompt after a crash or restart
Modal page shown before Home on start when an open live session exists in the journal (J13). Content: "You have an unfinished workout", workout title, start time, last saved set and its time, saved set count. Actions: Continue workout (primary), Finish workout (secondary), Not now (text). Staleness: a session older than T-8 offers Finish workout only. States: LOADING (static "Checking your workout"), ERROR (journal unreadable or corrupt: neutral wording "We could not read your last workout on this phone. The file has been kept. Try again." with Try again and Export file; it does not say results are safe or lost and does not send the user to History, because live sets are not in History; SF-4), RECOVERY FAILED (after Try again fails twice: "We could not recover this workout. The file is kept on this phone and we have not changed it." with Export file, Start a new workout, and Contact support placeholder; the file is never auto-deleted), NOT THE OWNER (LC-15), no-open-session -> screen never appears. Abandoned or stale sessions show: "These sets are on this phone, not in History." with Finish workout, Export, Delete (SF-17).

### LC-14. Coach settings and privacy
`HudSettingRow` list (accessible labels merged with subtitle and value, S03D 9.1). Rows:
1. Voice: speaking on/off (respects the existing voice setting, AICR-037), voice speed (3 steps), volume follows system media volume.
2. Listening mode: Tap to talk (MVP default) / Hands-free with headset / Hands-free always on (offered only after the gym trial decides it; OPEN UQ-12). Choosing a mode never opens the microphone by itself.
2a. Reduce animation: an in-app switch "Reduce animation" (default follows the OS; the switch can only turn more reduction on) that also controls the Saved-row highlight and auto-advance (UX-14).
3. Captions: always on (not a toggle for speech output: captions cannot be turned off while speech is on; font size follows system scale plus an extra "Larger captions" switch).
4. Avatar: Show / Hide (persisted; default OPEN UQ-04).
5. Haptics and sounds: Cue sounds on/off, Vibration on/off, each with a test button.
6. Keep screen on while the coach is active (default OPEN UQ-07).
7. Privacy: consent status with date and version, "Withdraw voice consent", "Delete coach memory" (P1), "Export my coach data" (P1), "What is stored" (static explanation). Withdrawing is one tap plus a confirm; it ends any live session at once. Order: the local flag is set first and capture is blocked at once; then the server record is updated. WITHDRAWAL FAILURE state: if the local flag cannot be persisted: "We could not save your choice. The microphone stays off for now. Try again." with Try again; capture stays blocked until the flag is persisted. If only the server update fails: "Voice is off on this phone. We will keep trying to update your account." with a visible retry state; never shown as fully withdrawn on the server until confirmed (SF-14, SE-13). The consent row shows the version and the date of the current agreement and of any withdrawal.
8. Help: "What you can say", "Keep the coach running in the background" (battery help, OPEN UQ-13).
States: LOADING (static), ERROR on a failed save ("We could not save this setting. It will apply for this session."), OFFLINE (local settings work; delete and export state "Needs a connection" if they do), PERMISSION-DENIED rows show the denied state with Open settings.

### LC-15. Second-device read-only state and takeover
Purpose: a live session has one owner device (`ownerDeviceId`, `ownerEpoch`; A2.1). A second device that opens the session must not write.
Appearance: LC-5 layout in read-only mode: the HUD shows the last known state with the label "Last updated {time} from your other phone"; the dock, quick actions, set entry and voice are disabled with the reason in semantics (allowed-action table 4.6, column "Not the owner"); the mic chip reads "Microphone off". The persistent banner (priority 2): "This workout is running on another device." with the primary button "Take over here" and the text button "Keep watching".
Takeover: tapping "Take over here" opens a ConfirmPrompt (screen only, not voice): "Move this workout to this phone? The other phone will stop controlling it. Anything not yet synced from the other phone stays on that phone and is not merged." Yes / No. Yes increments the epoch; the previous owner's unsynced journal is parked, never merged and never deleted, and is shown there as "Kept on this phone". The previous owner shows the same read-only state on its next update. Voice never starts after a takeover without a tap (N-15).
States: LOADING (static "Checking"), OFFLINE ("You are offline. Taking over needs a connection." the button is disabled), ERROR ("We could not move the workout. Nothing changed." Try again), SUCCESS (LC-5 in manual-ready state with the coach off).
Keys: `liveCoach.readonly.banner`, `liveCoach.readonly.takeover`. The default behaviour (read-only with explicit takeover) is OQ-21..24 default; the owner-device display name source is OPEN (UQ-25).

## 7. Component contracts

Components are compositions of the HUD primitives (U-F2). Inputs and events are described, not coded. All interactive components expose a `Key`, an accessible name, and fire exactly the events listed. "min target" is the hit region.

| Id | Component | Built from | Inputs | Variants / states | Events | Rules |
|---|---|---|---|---|---|---|
| C-1 | LiveCoachPage | `HudScreenBody` | `LiveCoachViewState` (voice, workout, connection, safety, permissions, avatar visibility) | compact portrait, compact landscape, medium, expanded (section 12) | back, settings, hide avatar | Renders a snapshot; owns no workout state |
| C-2 | StatusRow | 3 x `HudChip` | mic (on, muted, off, taken, unknown), connection (online, reconnecting, offline), save (all saved, n waiting, n not confirmed, sync blocked, not saved on this phone) | each chip: word plus icon | tap opens a small explanation sheet for that chip; the same action is exposed as a custom accessibility action on the group (UX-15) | Words never truncated (wrap, max 2 lines). Mic chip renders only from capture events (4.1) and uses the filled/hollow dot meaning of U-F8 |
| C-3 | VoiceIndicator | `HudPanel(dense)` + icon + word | `VoiceState`, `reason`, `level` (0-1, optional), `reducedMotion` | one per row of 4.1 | tap on indicator = mute/unmute (when allowed) | The word is always shown. Level animation only when not reduced-motion; static otherwise. Min target 64 dp |
| C-4 | Avatar | custom painter in a hideable container (P1) | `AvatarState` (idle, listening, speaking, thinking, warning), `visible`, `size`, `reducedMotion`, `speechLevel` | see 7.1 | hide tapped | Never mutates Runtime (AICR-055); decorative, excluded from semantics |
| C-5 | WorkoutHud | `HudPanel`, `HudRing`, `HudMetricRow` | Runtime snapshot (exercise, set n/m, targets, load labelled plan/last time, rest remaining from a wall-clock `endsAt`, next exercise, save status) | one per row of 6.2 | none (information only) | Digits at least 48 sp bold, monospace for numbers (Roboto Mono per S03D F29). Missing data is absent, never zero. Rest digits not announced each second |
| C-6 | ConversationView | scrolling list of items | list of `TranscriptItem` | item kinds below | tap item = copy text (long-press is never required); "Jump to latest" | See 7.2 |
| C-7 | CommandResultCard | `HudPanel(dense)` | command kind, values, lifecycle step, typed reason | Pending, Confirmed, Rejected, Not confirmed (upgrades to Confirmed on a late ack) | Undo (`void_set`), Correct (`correct_set`), Edit set, Remove set, Try again (same `command_id`, idempotent), Check | The only place success is rendered. Rendered from the Runtime result, never from model text. Undo and Correct are also custom accessibility actions |
| C-8 | QuickActionBar | row of `HudChip` (48 dp) | available actions for the current Runtime state | e.g. Start set, Log set, Skip rest, Next exercise, Replace, Pause, Pain or unwell | each calls the same Runtime command as the matching voice phrase | Chips are at least 56 dp; enabled or disabled per table 4.6; disabled chips show their reason in semantic value. The "Pain or unwell" control is NOT in this bar (it is pinned, C-24). Works with the network and AI off |
| C-9 | HandsFreeControls (dock) | `HudButton` x up to 4 | primary action, mic control, pause, more | per row of 6.1/6.2 | press | Primary control 64 dp tall, full width on compact; secondary controls 56 dp; 12 dp gaps; Finish and End are not primary and live behind More |
| C-10 | SetEntrySheet | `HudSheet` + steppers | exercise, last or planned reps and weight, step sizes | Log, Correct | save | Reps and weight steppers with +/- buttons (56 dp) and optional keypad; no swipe or long-press needed. Reuses the existing player's set entry by reference (UNGROUNDED) |
| C-11 | ConfirmPrompt | `HudSheet` (visual) + spoken question | action label, summary values, risk tier | visual and spoken together | Yes, No, timeout | Section 8.3. Silence or timeout means No |
| C-12 | Banner | `HudPanel` | typed reason, text, optional action | per 6.3 | action tap | One at a time (4.4). Not a live region by itself; announced once on appearance |
| C-13 | SymptomSheet | `HudSheet` | none | options of LC-11 | choose, cancel | Section 6 LC-11 |
| C-14 | SafetyStopPanel | `HudPanel` filled | typed stop reason | stop, paused-after-stop | emergency call, finish, show workout, resume (two step) | Section 6 LC-8 |
| C-15 | ConsentPage | page | consent version, items | per LC-2 | agree, decline, details | Equal-weight buttons; versioned |
| C-16 | PermissionRationale | `HudSheet` | permission kind, state (first, denied, permanently denied) | per LC-3 | continue, not now, open settings | Always precedes the OS dialog |
| C-17 | ResumePrompt | page | last session summary | per LC-13 | continue, finish, not now | No discard action |
| C-18 | SessionSummary | page | stored session totals, sync status | per LC-12 | done, history | Numbers only from storage |
| C-19 | SessionNotificationModel | plain data object rendered by a platform adapter | voice state, reason, rest remaining, mic state | per 9.5 | action ids (`toggleMic`, `stopVoice`, `open`) | No Flutter or Android types in the model (portability) |
| C-20 | ShellStripSource | S03D `ActiveSessionStatus` implementation | session state | listening, paused, resting | tap to return | Depends on S03D S-4 (U-F-dependency, section 12.1) |
| C-21 | PlanReviewCard | `HudPanel` | plan, reason chips | per LC-6 | accept, change, reject | Explanation cites only reason chips present |
| C-22 | CoachSettingsList | `HudSettingRow` | settings | per LC-14 | change | Merged semantics |
| C-23 | ReadOnlyBanner (LC-15) | `HudPanel` | owner display name, last update time | read-only, takeover confirm | takeover, keep watching | Disables dock and set entry through the allowed-action table |
| C-24 | PainControl | `HudButton` 56 dp | none | one | opens C-13 | Pinned in the header outside scrolling areas; never disabled; present in every LC-5 state including read-only |

### 7.1 Avatar contract (P1, AICR-054..057)
- States (MVP, one character): idle, listening, speaking, thinking, warning. The draft's "positive feedback" and "exercise explanation" are reserved (map to idle and speaking until designed).
- Mapping from voice and safety state (a pure function of the controller event, no Runtime access): STOPPED, INITIALIZING, RECONNECTING, PAUSED -> idle; LISTENING and INTERRUPTED -> listening; PROCESSING -> thinking; SPEAKING -> speaking; safety banner, safety unavailable or safety stop -> warning; AI-unavailable manual mode -> idle, dimmed.
- Mouth sync: driven by `speechLevel` from playback; if no level is available, a fixed two-frame pattern; with reduced motion or battery saver, a static open mouth while speaking.
- Reduced motion: no loops; each state is a still pose; transitions are instant or opacity-only.
- Hide: a clearly labelled toggle on the avatar container and in settings; persisted; hiding returns the space to the HUD; all flows stay identical (AICR-056). On the first session the toggle is explained once.
- Performance guard: if the frame budget is exceeded, battery saver is on, or the device is hot, the avatar drops to a static pose and, if still struggling, hides itself with a notice; it never delays voice or timers (AICR-057).
- Never: the avatar never celebrates an unconfirmed command, never shows approval or disapproval of technique (the app does not see technique, AICR-052), and never appears on the lock screen or in the notification.
- Accessibility: decorative, excluded from semantics; everything it expresses is also in the voice indicator word and the captions.

### 7.2 Conversation view contract
Item kinds: UserPartial (live, grey, ends when finalised), UserFinal, CoachStreaming, CoachFinal, CoachInterrupted (ends with "(interrupted)"), ResultCard (C-7), Notice (system sentence, no speaker), ErrorLine.
Rules:
1. Every word the coach speaks appears as text in the same bubble, from the same string that is sent to speech (display and spoken forms may differ only in number and unit formatting, e.g. "60 kg" shown and "sixty kilograms" spoken; a test compares the normalised forms).
2. Captions appear as speech starts and cannot be turned off while speech output is on. If speech output is off, captions stay.
3. Partial transcripts never become commands and are visually different (grey, no bubble edge).
4. The conversation lives only for the session unless the operator decides otherwise (OPEN UQ-05: draft default stores no transcripts, OQ-06). A line at the top of an empty history says "This conversation is not kept after the workout" only if that decision stands.
5. Scroll anchors to latest; scrolling up shows "Jump to latest".
6. Typed input (a text field behind a Keyboard button in the dock More menu) is PROPOSED as the accessible alternative to voice; OPEN UQ-08 whether the first release supports typed messages to the coach.

## 8. Voice interaction rules visible in the UI

### 8.1 Barge-in, turn taking, partials
Covered by J5 and 4.1. The UI never shows a command as understood until the utterance is final (AICR-003).

### 8.2 Earcons and haptics (every sound has a visual twin)
| Event | Sound (DRAFT) | Vibration | Visual twin |
|---|---|---|---|
| Listening started | one rising tone | one short | indicator "Listening" |
| Phrase accepted (acknowledgement cue, played when a final utterance is taken, before any result) | one very short tick | one very short | notice line "Heard", not a result card; it never means Saved |
| Phrase not understood (NO_MATCH) | two short low tones | two short | notice "I did not catch that. Say it again, or tap." |
| Command saved | short soft tick | one short | result card Saved |
| Command not done | two low tones | two short | result card Not done |
| Rest over | three-note cue, then local speech | long | rest ring complete, HUD "Rest over" |
| Warning / safety | continuous distinct pattern | three long | LC-8 or banner |
| Mic closed | one falling tone | one short | indicator "Voice off" |
Rules: sounds follow the system media volume and ducking; with the voice setting off, tones stay but speech is silent; vibration is a setting; haptic use today is minimal (two files), so Live Coach introduces a small shared helper (UNGROUNDED).

### 8.3 Confirmation tiers (PROPOSED, OPEN UQ-03)
| Tier | Examples | Behaviour |
|---|---|---|
| Immediate (reversible, low risk) | Next exercise, Start rest, Pause rest, Skip rest | Executes, then confirms in the card |
| Read-back (data) | Log a set, change a number | Coach reads the values in the same sentence as the result after ack; if the recognition confidence is low it asks first |
| Explicit confirm (visual plus spoken, silence = no) | Replace exercise, Finish workout, Abandon workout, Remove set, Accept plan, change a restriction, implausible value (confirm-first), takeover on another device (screen only), Withdraw consent | ConfirmPrompt C-11; timeout T-7 cancels and the coach says "Cancelled". Finish and abandon prefer a screen tap or headset button when available (SE-18). Resume after a safety stop is screen-only and never voice-confirmed (LC-8) |

The confirmation tiers need a runtime contract (UX-2): the design must define confirmation, correction and duplicate-suspect semantics (L1 to L3 confirmation ADR, A8.3); until it does, this table is the UI request, not a Runtime guarantee. The earlier reference to a "read-back 10.4" in the design is not relied on here.

## 9. Surface details

### 9.1 Hands-free controls (dock) layout
Compact portrait, bottom up: safe-area inset; primary button (64 dp) full width; row of up to 3 secondary buttons (56 dp: Mic, Pause, More); quick-action chips above. Order and meaning by state in 6.1/6.2. The destructive items (Finish workout, End voice session, Withdraw) are inside More, spaced at least 24 dp from the primary button.

### 9.2 Honest attribution of cues
When the coach cannot speak (offline or paused) and a local cue fires, the caption and the voice line say "Timer: rest over", not "Coach: rest over". The avatar stays idle.

### 9.3 Number display
Weights and reps show with units ("60 kg", "8 reps") using locale formatting. Weight is metric only (S03D has no units setting; draft field `weight_kg`). Spoken forms use full words.

### 9.4 One-handed and pocket use
- All primary controls sit in the lower 40% of the screen; the header holds only back and settings.
- No control requires swipe, long-press, drag, pinch or two fingers (WCAG 2.5.1, 2.5.7).
- A 12 dp gap separates any destructive control from a frequent one; the Pain or unwell control is always visible but is a quick-action chip, not the primary button.
- Pocket protection (OPEN UQ-07): while the voice session is live and the screen is on, the app may use the proximity sensor to dim and ignore touches when covered; the default is: guard off (the screen stays on and unlocked, so pocket touches are possible). Because of that default, the "phone stays in your pocket" claim is not made unless the capability check of LC-1 passed and the user has chosen a screen-off mode; in every other case the copy says to keep the screen on (UX-7). The primary dock action opens the set-entry sheet and never records by itself, so one accidental touch cannot create a set; Save in the sheet is the recording tap.
- The screen-lock behaviour (keep screen on) follows the setting in LC-14; with the screen off, all interaction is by voice (J11).

### 9.5 Foreground-service notification
Android only (MVP). The notification model is the plain object C-19; an Android adapter renders it. Requirements (AICR-039, 040):
- Channel `live_coach_session` (PROPOSED id), separate from `workout_reminders`; importance low (no sound), ongoing, not dismissible while capture is active, removed when the voice session stops.
- Title always names the microphone state in words. Content is generic on the lock screen (visibility private with a public version "Workout in progress") so no exercise or health detail shows to bystanders (OPEN UQ-13).
- Text by state (DRAFT):

| Voice state | Notification text |
|---|---|
| LISTENING | "Coach is listening. Microphone on." |
| PROCESSING / SPEAKING | "Coach is working. Microphone on." |
| PAUSED (muted) | "Microphone muted." |
| PAUSED (call / headset / other) | "Paused: {reason}. Microphone off." |
| RECONNECTING | "Reconnecting. Timer still running. Microphone off." |
| RESTING (any live voice state) | "Rest 0:45" using a chronometer driven by the absolute `restEndsAt`, plus the mic word. With a safety lock: "Workout paused. Rest paused." and no chronometer. When the process is killed, a scheduled notification at `restEndsAt` is the rest-over backstop (UQ-23) |
| Mic state unknown | "Cannot confirm the microphone is off. Open the app." |
| AI unavailable | "Coach unavailable. Timer still running." |
- Actions (max 2): "Mute" / "Unmute", and "Stop voice". Neither finishes or abandons the workout. Finish, resume after a safety stop, replace and any plan change are NOT available from the notification, because pocket taps and the lock screen are untrusted input.
- Tapping the notification opens LC-5 (a tap callback must be registered; U-F9).
- Safety stop posts a separate high-importance notification "Workout paused. Open the app." with no actions.
- If notification permission is denied the locked-screen mode is unavailable (LC-3 table); the voice session then runs only with the screen on and the app visible.

### 9.6 Leaving the screen
System Back from LC-5 with the microphone open shows a small confirm sheet (UX-9): "The microphone is on. Leave it on, or stop voice?" with three actions: "Stop voice and leave", "Leave, keep listening" and "Stay". If the user leaves with the mic open, a persistent cue remains: the shell strip (C-20) shows "Coach listening, mic on" on every tab and the notification shows the mic word; the cue is not a one-time snackbar. With the mic closed, Back leaves directly. Ending voice or the workout is only ever an explicit control. The pre-remediation default (leave with a one-time snackbar) is withdrawn; OPEN UQ-15 now only asks whether Back should always stop voice.

## 10. Copy rules

1. Short. A spoken sentence is at most 12 words; a caption line at most 2 lines at text scale 1.0. One idea per sentence; one question at a time.
2. Spoken-friendly. No abbreviations in speech ("kilograms", not "kg"; "repetitions" or "reps" consistently, "reps" chosen). Numbers are said as numbers a person would say ("sixty", "eight"). No symbols, no emoji, no markdown in captions. The spoken and displayed texts are generated from one source (section 7.2 rule 1).
3. Honest about state. Words allowed per lifecycle step: "Heard" (transcript only), "Saving", "Saved", "Not done", "Not confirmed". "Done", "Saved", "Updated", "Synced" and "Replaced" appear only after the matching acknowledgement.
4. Honest about offline. Say what works: "Your timer and manual logging still work. Your sets are saved on this phone." Never imply the coach heard something when it did not.
5. Honest about limits. The coach does not see technique unless a Form Coach result is in context (AICR-052): no "good form", "nice depth", "I can see". It does not promise safety ("this is safe for you") or give medical conclusions.
6. Praise only effort and facts after Saved ("Set two saved. Nice work.") and never for unconfirmed actions. No streak pressure, no guilt, no body-shaming.
7. Errors are plain sentences with the next step, never exception text, never codes. A refusal shows one reason in words from the typed reason (copy keyed by enum, AICR-066).
8. No retry offered for an error that cannot succeed (kill switch, daily limit, permanent permission denial). Cooldowns are visible.
9. Safety copy: imperative, calm, non-diagnostic; wording reviewed by the operator and clinical/legal advisers before release.
10. Localization: English authored here; Russian is the default locale and must ship with every key (U-F7). Sentences with embedded names or counts use full-sentence keys or ICU plural/select (Russian declension). Budgets in Russian characters: button labels 18, chips 16, status chips 22, banners 90 (two lines at 1.0, three at 2.0), notification title 30 and text 60, result card line 40, spoken sentence 12 words.
11. Reasons the coach cites in explanations come from the closed reason list; free text may phrase them but must not add reasons (AICR-020).
12. Spoken success text is device-generated (SF-6, A5.2). For turns with a state-changing intent, only text generated on the device from the acknowledged Runtime result is spoken after the result ("Set two saved: eight reps, sixty kilograms."). Model reply text that claims completion ("done", "saved", "logged") is suppressed for such turns; if a tool call was dropped or refused the device says that it was not done. The caption and the speech come from the same device string.
13. Sync wording follows the cause: "waiting to sync" only for connectivity, "Sync blocked" for a rejection; no copy blames the connection for a rejection (SF-8).
14. Data location is stated where it matters: abandoned and unread-journal copy says the sets are on this phone and not in History (SF-4, SF-17); no copy says results are "not lost" or "safe" when the state is unknown.

### 10.1 Draft copy table (DRAFT; keys PROPOSED; Russian to be authored in the build)

| Key | Text (DRAFT) |
|---|---|
| `lcEntryTitle` | Train with your coach |
| `lcEntryBody` | Talk to your coach while you train. |
| `lcEntryBodyPocket` | Hands-free. Phone can stay in your pocket. (only when the capability check passed) |
| `lcUndo` | Undo |
| `lcCorrect` | Correct |
| `lcEditSet` | Edit set |
| `lcRemoveSet` | Remove set |
| `lcNoMatch` | I did not catch that. Say it again, or tap. |
| `lcMicUnknown` | Mic state unknown |
| `lcSyncBlocked` | Sync blocked |
| `lcNotSavedPhone` | Could not save this on the phone |
| `lcReadOnlyBanner` | This workout is running on another device. |
| `lcTakeOver` | Take over here |
| `lcConsentFirmDecline` | No thanks, do not ask again |
| `lcRestPaused` | Rest paused |
| `lcResumeCorrupt` | We could not read your last workout on this phone. The file has been kept. Try again. |
| `lcStart` | Start |
| `lcStartVoice` | Start voice |
| `lcStartManual` | Start without voice |
| `lcVoiceOff` | Voice off |
| `lcConnecting` | Connecting |
| `lcListening` | Listening |
| `lcThinking` | Thinking |
| `lcStillWorking` | Still working |
| `lcSpeaking` | Coach is speaking |
| `lcReconnecting` | Reconnecting |
| `lcMuted` | Muted, mic off |
| `lcResume` | Resume listening |
| `lcPausedCall` | Paused: phone call |
| `lcPausedHeadset` | Paused: headset disconnected |
| `lcPausedAudioTaken` | Paused: another app is using audio |
| `lcMicOnLabel` | Microphone on |
| `lcMicOffLabel` | Microphone off |
| `lcSaving` | Saving |
| `lcSaved` | Saved |
| `lcNotDone` | Not done |
| `lcNotConfirmed` | Not confirmed. Check your sets. |
| `lcTryAgain` | Try again |
| `lcWaitingSync` | {n} waiting to sync |
| `lcAllSaved` | All saved on this phone |
| `lcOfflineBanner` | No connection. Train manually. Your sets are saved on this phone. |
| `lcReconnectBanner` | Reconnecting. Your timer and manual logging still work. |
| `lcAiDownBanner` | The coach is not available right now. Train manually. |
| `lcKillSwitchBanner` | The coach is switched off for now. You can still train yourself. |
| `lcLimitBanner` | You have used today's coach time. You can still train yourself. |
| `lcSafetyUnavailable` | The coach cannot check suggestions safely right now, so it will not suggest new exercises or loads. Logging and timers work. |
| `lcRestOver` | Rest over |
| `lcTimerRestOver` | Timer: rest over |
| `lcStopTalking` | Stop talking |
| `lcPainButton` | Pain or unwell |
| `lcSafetyTitle` | Stop now. |
| `lcSafetyBody` | Sit down and rest. If you have chest pain, feel faint, or it does not pass, get medical help. |
| `lcFinishConfirm` | Finish workout? {n} sets saved. |
| `lcKeepGoing` | Keep going |
| `lcResumeTitle` | You have an unfinished workout |
| `lcResumeNote` | A set you were doing when the app closed may not be saved. Check your list. |
| `lcStillListening` | The microphone is on. Leave it on, or stop voice? (leave sheet, 9.6) |
| `lcConsentAgree` | Agree and continue |
| `lcConsentDecline` | Not now |
| `lcPermMicWhy` | So the coach can hear you during your workout. |
| `lcPermNotifWhy` | So you can see when the microphone is on, and stop it from the lock screen. |
| `lcOpenSettings` | Open settings |

## 11. Accessibility

Target: WCAG 2.2 AA on the new surfaces, validated by the independent a11y review (this spec does not replace it).

| Topic | Requirement |
|---|---|
| Touch targets | Primary dock control 64 dp tall, secondary dock controls, quick-action chips, the pinned Pain or unwell control and all rest controls (Add 30 s, Pause rest, Skip rest) at least 56 dp (UX-16), all other controls at least 48 dp including the hit region (U-F3: the constraint wraps the tap area). 12 dp between a destructive and a frequent control, 8 dp elsewhere. |
| One-handed gym use | Primary actions in the lower 40%; no gesture-only action; no hold; text entry never required (steppers and chips). Works with gloves: no tiny targets, no precision swipes. |
| Large text | Layouts hold at system text scale 2.0: chips wrap to two lines, the HUD digits stay on one line and shrink last, the banner grows, the dock keeps its order, the conversation view shrinks first. At 2.0 the conversation collapses to the last item. Russian first (U-F7). |
| Contrast | 4.5:1 for text, 3:1 for icons and non-text, against the effective surface, in dark and light themes. Light-theme `warning` and `danger` are never text or the sole signal; warnings use ink text on a filled panel plus an icon plus a word. The safety panel is filled with the text-primary-on-surface pair that passes in both themes. Gym lighting favours the dark theme; the screen follows the app theme. |
| Colour independence | Mic state = filled/hollow dot + word + icon; save state = word + icon; voice state = word + icon; avatar never carries meaning alone. |
| Screen reader: structure | Reading order equals visual order (section 6 LC-5 list). Headers are marked. The status row is one group read as "Microphone on, Online, All saved". The HUD is one group per card with a merged label. The avatar is excluded. |
| Screen reader: announcements | Use `SemanticsService.announce`. Polite: banner appeared or changed, result card Saved / Not done / Not confirmed, voice state changes that the user did not cause (paused with reason, reconnecting, back online), rest started, rest over. Assertive: safety stop. NOT announced: rest seconds, the ticking elapsed time, partial transcripts, loading placeholders. Coach captions are NOT a live region while speech output plays (the user hears the same words; announcing them would double-speak and talk over the coach). When speech output is off or the voice is paused, new coach captions are announced politely. Verify with TalkBack users (OPEN UQ-16). |
| Screen reader: policy while voice is on (UX-8) | (1) No duplicate announcements: while the coach is speaking, no `announce` is made for the same content (result cards, captions); a result is announced once, after the coach finishes, or only by the spoken text. (2) No focus jump: focus never moves by itself, including to Stop talking; Stop talking is reachable first by order but focus is not stolen, and the Stop talking control is also a custom accessibility action on the voice indicator. (3) Announcements can be picked up by the microphone and read as speech: when a screen reader is active the default listening mode is headset hands-free or tap-to-talk, never open-speaker always-on, and the mode row says why. (4) Chip actions (status chips, result card Undo and Correct, set rows Edit and Remove) are custom accessibility actions on the group node, not extra tab stops. |
| Screen reader: controls | Every control has an accessible name; disabled controls expose their reason in the value; result cards are one node ("Set two, eight reps, sixty kilograms, saved") with custom actions Undo, Correct, Edit and Try again; the Stop talking button appears in reading order next to the voice indicator and focus is never moved to it automatically (see the screen-reader policy). Mic mute is a toggle with state. |
| Deaf / hard of hearing, noisy gym | Everything spoken is captioned; every sound has a visual and a haptic twin (8.2); every voice command has a tap equivalent (quick actions, dock, set entry); typed input is the proposed alternative (UQ-08). |
| Speech difficulty or accent | Tap equivalents for all commands; recognition problems end in a clear "I did not catch that. Say it again, or tap." not a silent failure. |
| Cognitive load | One question at a time; confirm prompts have large Yes / No; no timed consent; silence on a confirm means No and says so; no auto-advance that moves a screen the user is reading. |
| Reduced motion | The OS setting (`MediaQuery.disableAnimations`, `context.hudMotionDuration`) OR the in-app "Reduce animation" row in LC-14 (UX-14) turns off the Saved-row highlight, the auto-advance after a set, and: avatar animation, voice-level meter, rest-ring sweep (the ring updates in steps, digits unchanged), list transitions. Sheets and the full-screen routes use no-transition pages when set (S03D rule). No looping animation exists in the loading states. |
| Focus | Order as in LC-5. Sheets trap focus; first focus is the sheet title; closing returns focus to the opener. Visible 2 px focus ring on new controls (S03D 9.1 extension). Keyboard (tablet, external): Tab, Enter and Space work; Esc closes the top sheet. |
| Foreground notification | Title and text carry the mic word; actions have names ("Mute microphone", "Stop voice"); no information only in an icon. |
| Time limits | No time limit on consent, permission rationale or reading the safety panel. Confirm prompts time out to the safe answer (No) and say so. With a screen reader active the confirm timeout T-7 is extended to 45 s, and in all cases the timeout is shown as a visible text countdown with an "Add time" action; the remaining time is not announced each second (UX-10). |
| Language | Spoken language follows the app language (OQ-15); mixed-language names do not break captions. |

## 12. Responsive behaviour

### 12.1 Window-size classes
The Live Coach screen uses the window-size model proposed in S03D section 10.1 (Compact under 600 dp, Medium 600-839 dp, Expanded 840 dp and up, plus the "short" flag under 480 dp height) via the single `windowSizeClass` provider, if S03D is built first. If it is not, Live Coach reads the same two breakpoints locally behind one provider so it can be swapped (dependency noted, UNGROUNDED: the provider does not exist yet, FACT S03D F28). No layout reads raw widths.

| Class | Layout |
|---|---|
| Compact portrait (Android phone, first target; Samsung Galaxy S23 class) | One column as in LC-5. Dock at the bottom. Conversation shows the last 3 items collapsed. |
| Compact landscape / short | Two columns: left HUD + voice zone, right conversation + quick actions; the dock stays at the bottom spanning the width; avatar hidden by default when height is under 480 dp. |
| Medium | Centred column at most 640 dp, or the two-column layout above when width allows; dock inside the column. |
| Expanded (tablet / large window) | Two panes: HUD and voice on the left (about 45%), conversation on the right; the dock spans the left pane; sheets become anchored popovers or centred dialogs (S03D 10.6). Shell navigation is irrelevant (the route is outside the shell). |
Resizing while a session is live (split screen, folding) is a rebuild, never a restart; no state is lost; focus stays on the same control.

### 12.2 iPhone and tablet portability
Not designed or verified (NG-7, no iOS platform folder, S03D F26). To keep portability: the UI reads only the plain state objects in section 4 and component inputs in section 7; platform-specific parts (foreground service, notification, audio focus, Bluetooth routing, permission dialogs) sit behind interfaces; no Android API appears in shared widgets; Material widgets are used and Cupertino variants (switches, sheets) can be swapped later per `core/CONVENTIONS.md`. The iOS equivalent of the notification and lock-screen behaviour is not specified and is OPEN (UQ-17).

## 13. What the UI must never claim

| # | The UI must never | Why | How the UI enforces it |
|---|---|---|---|
| N-1 | Show "Saved", "Done", "Updated" or any success verb, or speak it, before the Runtime acknowledged the command | AICR-027, draft 6 | Result cards render only from Runtime results; the TTS text for a result is generated after the ack; Pending and Not confirmed states exist |
| N-2 | Count a Pending or Not confirmed set in totals, set counters or summaries | NFR-05/06 | HUD and summary read only confirmed journal entries |
| N-3 | Say "synced" or show the cloud as current while events are waiting | Draft 11 | Save chip shows "{n} waiting to sync"; "synced" word only when the count is 0 and the server confirmed |
| N-4 | Imitate a coach reply, command handling or listening when the AI or mic is unavailable | AICR-036 | AI-unavailable mode disables the input surfaces; the mic chip shows the true state; local cues are labelled "Timer" |
| N-5 | Claim it saw the user's technique or comment on form quality without a Form Coach result | AICR-052 | No technique wording in copy or avatar reactions unless a Form Coach finding is in the context and cited |
| N-6 | Claim a replacement, load or plan is "safe" | NG-1, draft 9 | Rows show reason chips only; the word "safe" is not used in copy; blocked items show a reason |
| N-7 | Offer to continue after a safety stop, or let a casual tap or voice word clear it | AICR-051 | LC-8 on-screen two-step resume (user-only; voice, headset, notification and tool calls cannot clear the lock); no coach prompt to continue |
| N-8 | Show history, "last time" or progress numbers that are not in stored data | AICR-014, 061 | Missing data is absent; no zero for unknown; the coach summary block is removed if a number does not match |
| N-9 | Show the microphone as off when it is on, or hide that it is on after the screen is left | AICR-006, 039 | Mic chip, strip and notification use the same single source; the chip updates before any sentence |
| N-10 | Say a restriction or plan was changed when the user did not confirm it | AICR-011, 018 | Confirm cards; status stays "Proposed" until confirmed |
| N-11 | Present a retry for an error that cannot succeed, or a retry that would duplicate a set | AICR-046 | No retry for kill switch, limit, permanent permission denial; Try again re-sends the same `command_id` |
| N-12 | Say the workout was fully recovered after a crash | Draft 11, AICR-043 | Resume prompt shows the last saved set and warns about the one in progress |
| N-13 | Say the coach "remembers" or "stores" anything the operator has not approved | Draft 8, OQ-06 | Memory UI absent until P1; transcript notice only if decided |
| N-14 | Show the avatar as emotionally approving, or any celebration, for an unconfirmed action | Principle 1 | Avatar state is a function of voice and safety state only |
| N-15 | Start microphone capture without a visible user action, or after a restart without one | AICR-040 | Start voice is a button; resume after a crash starts manual |

## 14. Acceptance criteria (observable; UI-level)

Widget and integration tests use fakes: a voice-state stream, a Runtime that acks or fails on demand, a fake clock, a fake permission channel, a window size, `disableAnimations`, text scale. Criteria are written so they fail if the guarded behaviour breaks.

- AC-LC-1. Flag off: `liveCoach.entry.card` is absent and the route is unreachable; the existing workout routes still open.
- AC-LC-2. Consent withheld or declined: pumping the start path produces zero microphone-permission calls and zero capture start calls (spy); manual workout opens.
- AC-LC-3. Mic permission permanently denied: `liveCoach.permission.mic.openSettings` is present and `Ask again` is absent; the manual workout is reachable.
- AC-LC-4. For each voice state in 4.1, the indicator shows the matching word (not only an icon) and the semantics label contains it; in `ru` at scale 2.0 no word is truncated.
- AC-LC-5. A command whose Runtime result is delayed shows a Pending card with the word "Saving"; the word "Saved" and the spoken confirmation do not appear until the ack; totals do not change until the ack (spy on TTS and the HUD counters).
- AC-LC-6. A command whose Runtime result never arrives (or persistence fails) shows "Not confirmed" after T-3 only when the journal head also lacks the command, and the coach does not speak a success phrase. If a late acknowledgement then arrives, the same card (no second card) becomes Saved, totals change at that moment, and Try again before or after that does not create a second set.
- AC-LC-7. The same final utterance delivered twice yields one result card and one set (E2E-04). Try again re-sends the same `command_id`.
- AC-LC-8. A partial transcript ending in a command word creates no result card and no Runtime command.
- AC-LC-9. Speaking while SPEAKING stops playback, shows Listening, and marks the cut coach bubble "(interrupted)".
- AC-LC-10. Network off during RESTING: the rest ring continues and the end cue fires on time; the banner shows `lcReconnectBanner` then, after T-4, `lcOfflineBanner`; manual Log set still works and shows "waiting to sync" (E2E-03).
- AC-LC-11. AI-unavailable mode for each reason (offline, service error, kill switch, daily limit): the matching banner shows; typed and voice input are disabled; quick actions work; Try again is present only for reasons that can succeed (E2E-10).
- AC-LC-12. Safety unavailable: Replace, plan change and load suggestion controls are disabled with the reason in semantics; Log set, Correct, Undo, Pause, Skip rest, Finish and history stay enabled, and a test iterates every cell of table 4.6 and fails if the dock, the banner or the Runtime stub disagrees with it (AICR-050, SF-7).
- AC-LC-13. Reporting chest pain or dizziness (tap or simulated voice report) shows LC-8; the workout state is PAUSED with the safety lock; no "continue" prompt is spoken or shown; resume needs the on-screen two-step; a single tap, a spoken "continue", a headset button, a notification tap and a model tool call do not clear it (E2E-08). The rest countdown is frozen ("Rest paused") and no rest cue (tone, vibration, speech, scheduled notification) fires while the lock is on. With the journal fake failing on append, on flush and on out-of-space, LC-8 is still shown and the notice "Could not save this on the phone" appears (SF-1). `record_set`, `correct_set`, `void_set`, `pause_workout` remain enabled behind "Show my workout"; `finish_workout` and `abandon_workout` fail when sent by voice or tool call.
- AC-LC-13b. A joint or muscle pain report stops only the current exercise and offers Replace / Skip / Finish; the whole-workout lock is not set. Free text that the on-device classifier cannot classify results in pause with the lock; no free-text symptom string is present in any outbound model context or replica field (spy).
- AC-LC-14. Incoming call (audio focus loss): voice goes to PAUSED with the reason, the mic chip reads "off", the workout state is unchanged, the timer continues; no automatic mic reopen unless UQ-11 is decided otherwise (E2E-05).
- AC-LC-15. Headset disconnect: speech stops at once, voice PAUSED with the reason, no output on the speaker until the user chooses Use phone (E2E-06).
- AC-LC-16. Foreground notification: present while capture is active, text contains the mic word for each state in 9.5, has only the actions Mute/Unmute and Stop voice, removed after Stop voice (E2E-11). No Finish action exists.
- AC-LC-17. System Back from LC-5 with the mic open shows the leave sheet with three actions; after "Leave, keep listening" the strip shows "mic on" persistently on all tabs and the notification shows the mic word; "Stop voice and leave" closes capture (capture-stopped event seen) before the route pops; with the mic closed Back pops directly.
- AC-LC-18. Resume prompt: with an open journal session and a fresh app start, `liveCoach.resume.prompt` appears before Home content; it shows the last saved set; there is no Discard action; Continue opens manual-ready with the mic closed (E2E-07).
- AC-LC-19. Finish: confirm prompt shows the saved set count; silence for T-7 cancels; the summary numbers equal the stored session totals; with pending sync the summary says so (E2E-12).
- AC-LC-20. Every spoken coach sentence in a recorded dialogue has the same normalised text in a caption bubble (compare TTS input and caption model).
- AC-LC-21. Reduced motion: with `disableAnimations` or the in-app "Reduce animation" row on (each tested alone), the Saved-row highlight and auto-advance are off and no animation controller of the avatar or voice level is active; the state words and ring digits still update.
- AC-LC-22. Avatar hidden: the HUD reclaims the space; E2E-01 steps pass identically; no Runtime call is made by the avatar module (dependency check).
- AC-LC-23. Touch targets: every interactive element on LC-5 has a hit region of at least 48 dp, the primary dock control at least 64 dp, the rest controls (Add 30 s, Pause rest, Skip rest), quick-action chips and the pinned Pain or unwell control at least 56 dp, and no two of a destructive and a frequent control are closer than 12 dp (measure render objects). The Pain or unwell control is present, enabled and outside every scrollable in each state of tables 6.1, 6.2, 6.3 and 4.6.
- AC-LC-24. Screen reader: a traversal of LC-5 matches the order in section 6; rest seconds are not in any live region; the banner is announced once; coach captions and result cards are not announced while speech plays (no duplicate announcement); focus never moves without a user action (record the focused node across a SPEAKING transition); Undo, Correct and chip actions are custom accessibility actions; with a screen reader active the default listening mode is tap-to-talk or headset; the confirm timeout is 45 s with an "Add time" action.
- AC-LC-25. Window sizes: at 599, 600, 839 and 840 dp widths and at 320 dp with text scale 2.0, LC-5 has no overflow and keeps the order of controls; at 2.0 the conversation collapses to the last item.
- AC-LC-26. The copy audit finds none of the forbidden claims of section 13 (search of the ARB additions for "safe for you", "good form", "synced" outside the synced state, "never keep", etc.).

- AC-LC-27. Correction: a Saved set card shows Undo and Correct; Undo within T-5 sends `void_set` and the totals drop only after the ack; after T-5 the card shows Edit set and Remove set, and the set list rows offer the same for the whole session; a correction appends a record (the earlier record remains in the journal fake) and the row shows "edited"; a Rejected correction leaves the row unchanged.
- AC-LC-28. Implausible value (reps 400, or 5 times the last value) from a voice utterance or a tap produces a confirm-first prompt and no Runtime command until Yes; silence for T-7 produces no command.
- AC-LC-29. Double tap on Save in the SetEntrySheet yields one command (one `command_id` minted at sheet open) and one set; the control is disabled until the ack; a same-value tap within T-6 asks the duplicate-suspect question (SF-11).
- AC-LC-30. Spoken success text: with a stub model that replies "Done, saved" while the tool call is dropped or refused, no success phrase is spoken or shown; the device says the action was not done; when the call succeeds, the spoken string equals the device-generated string (SF-6).
- AC-LC-31. Mic indicator: with a fake port that emits no `captureStarted`, the chip never shows "Microphone on"; after `captureLost` or a failing `stop()` without `captureStopped` it shows "Mic state unknown", never "off"; the watchdog expiry shows unknown (SF-5).
- AC-LC-32. NO_MATCH and low confidence: an unmatched utterance shows the "I did not catch that" notice and plays the not-taken cue, creates no card and no command; an accepted phrase plays the acknowledgement cue before any result; a low-confidence number shows a ConfirmPrompt before any command; the MVP default listening mode is tap-to-talk (UX-6).
- AC-LC-33. Sync blocked: a permanently rejected replica record shows "Sync blocked" on the Save chip, its sets stay Saved, and no string contains offline, connection or "when you are online" for that state; a connectivity delay shows "waiting to sync" (SF-8).
- AC-LC-34. Read-only second device: with `ownerDeviceId` different, LC-15 shows the banner, the dock, quick actions and voice are disabled, the Pain or unwell control stays enabled, takeover requires the on-screen confirm and never starts the microphone, and the previous owner shows the read-only state and "Kept on this phone" for its unsynced journal.
- AC-LC-35. Consent: "Not now" shows the screen again no earlier than the cadence; the firm decline stops all prompts and leaves "Set up voice" only in settings; a user excluded by the age policy never sees LC-2 or LC-3 (spy on the route stack); capture is refused without a current-version consent record.
- AC-LC-36. Withdrawal failure: when the local flag cannot be persisted the failure state is shown and capture stays blocked; when only the server update fails the screen says voice is off on this phone and shows a retry; no screen shows "withdrawn" on the server before confirmation.
- AC-LC-37. Flag off, expired or unreachable with an unfinished session: LC-13 and the strip are still shown, Continue opens manual mode, no new session can start; with no unfinished session the entry card is absent.
- AC-LC-38. Corrupt or unreadable journal: LC-13 shows the neutral error with Try again and Export file, never the words "not lost", "safe" or "History"; after repeated failure the recovery-failed state is shown and the file is not deleted (journal fake still holds the bytes). An abandoned session summary says the sets are on this phone and not in History, and the journal is removed only after Delete or Export is chosen (SF-4, SF-17, SF-18).
- AC-LC-39. A "Not confirmed" label never appears while the journal head contains the command; LC-12 read error does not say the sets are saved.

Timing parameters used above are PROPOSED and need the technical measurements (OQ-12):

| Id | Meaning | Proposed |
|---|---|---|
| T-1 | Connect / load timeout before an error is shown | 10 s |
| T-2 | PROCESSING shows "Still working" | 4 s |
| T-3 | A Pending command shows Not confirmed only if no dispatch result has arrived and the journal head does not contain the command; a UI display parameter, not a persistence timeout (SF-12) | 4 s display value (PROPOSED) |
| T-4 | Reconnecting becomes AI-unavailable (offline) | 15 s |
| T-5 | Spoken correction window after a recorded set | 10 s |
| T-6 | Duplicate-suspect window for identical values | 20 s |
| T-7 | Confirm prompt timeout, silence = No | 15 s; 45 s with a screen reader active; "Add time" always offered |
| T-8 | A recovered session is "stale" and offers Finish only | 12 h |

## 15. Traceability

| UI section | Requirements covered |
|---|---|
| J3, 4.5, C-7, AC-LC-5..7 | AICR-004, 025..029, 042..047 |
| J4, 6.2 | AICR-030, 031 |
| J5, 4.1, AC-LC-8, 9 | AICR-002, 003, 005 |
| J6, LC-10 | AICR-033, 034 |
| J7, LC-8, LC-11 | AICR-051, 050 |
| J8, J14, LC-9, 6.3 | AICR-008, 036, 044, 074, 075, 078 |
| J9, J10, J15 | AICR-007, 041 |
| J11, 9.5 | AICR-038..040 |
| J12, LC-12 | AICR-061, 022 |
| J13, LC-13 | AICR-043 |
| J16, LC-6 | AICR-015..020 |
| LC-2, LC-3, LC-14 | AICR-006, 009, 060, 076 |
| C-4, 7.1 | AICR-054..057 |
| Section 13 | AICR-014, 027, 046, 052, 066 |
| Section 11 | NFR-13 (accessibility target still OPEN, OQ-11) |

## 16. Open design questions

Owner key: OP = operator/product; TR = technical review (architect, Android, backend, security); UX = independent UX/a11y review; LEGAL = legal/clinical adviser. The next phase uses the PROPOSED default unless told otherwise.

| Id | Question | Owner | Default used here |
|---|---|---|---|
| UQ-01 | Is Live Coach a new screen with its own full manual controls, or a lens on the existing player? | TR + OP | New screen with full manual controls (needed for AICR-074/075) |
| UQ-02 | May a session be handed to the classic player (`/workout/:id`) mid-session? The classic player writes `WorkoutSession` directly and could race the Runtime (code map risk). | TR | No hand-off mid-session; classic player stays separate |
| UQ-03 | Confirmation tiers (8.3), duplicate-suspect prompt (T-6) and the missing edit/void-set command in the draft's command list | OP + TR | Tiers as in 8.3; Runtime to add a correction command |
| UQ-04 | Avatar default (shown or hidden) and whether it ships before the P0 voice slice | OP | Hidden in P0 (not built); shown by default in P1 on phones with the one-time explanation |
| UQ-05 | Are transcripts shown only in-session and then discarded (draft OQ-06 default), or kept? | OP | In-session only, not kept |
| UQ-06 | Wording and use of the duplicate-suspect question | OP | On, as drafted |
| UQ-07 | Keep-screen-on default and pocket-touch protection (proximity sensor) | OP + TR | Keep screen on while the app is in front; proximity guard off until trialled in a real gym |
| UQ-08 | Typed messages to the coach in the first release (accessibility and noisy gyms) | OP | Quick-action chips only in MVP; typed input after P0 |
| UQ-09 | Safety stop content: per-locale emergency number table (who signs it), whether the locked-screen notification may carry a Call action, the symptom list and who signs it (OQ-07, OQ-20), and all wording. The rules themselves (voice cannot clear the lock, rest frozen, joint pain stops the exercise) are decided in 06 A1 | LEGAL + OP | No call action; call button hidden for a locale with no signed number; the symptom stop cannot ship until signed; wording is a placeholder |
| UQ-10 | Which commands (if any) work offline by voice (draft ADR-009); the existing `parseCommand` grammar has substring risks (A-02) | TR | No voice commands offline in MVP; tap controls only |
| UQ-11 | After a call or headset reconnect, auto-resume listening or require a tap (privacy and Android background-start limits, C-08) | TR + OP | Require a tap or notification action |
| UQ-12 | Listening mode: hands-free always-on vs tap to talk; barge-in on or off; whether the mic is open during PROCESSING and SPEAKING; wake word (not in the draft, not designed) | TR + OP | Tap-to-talk (or headset-only hands-free) is the MVP default until the gym trial; always-on is decided after the trial; barge-in on only in hands-free |
| UQ-13 | Lock-screen notification visibility; battery-optimisation help (OEM-specific); Android 13-16 differences | TR | Private visibility with a generic public text; help article only |
| UQ-14 | Consent mechanics: where consent is stored (device only or server), minors, re-consent cadence | OP + LEGAL | Versioned, stored locally and server-side where available; minors not designed |
| UQ-15 | System Back from LC-5 with the mic open: confirm sheet (decided as the default) vs Back always stopping voice | OP | Confirm sheet with a persistent mic cue after leaving |
| UQ-16 | TalkBack behaviour of captions during speech (live region policy) needs a trial with screen-reader users | UX | Not announced while speech plays |
| UQ-17 | iOS lock-screen and background behaviour (design only, NG-7) | OP | Not designed |
| UQ-18 | Dependency on S03D: dock/strip, `windowSizeClass`, HudChip/HudButton extensions. Build order? | OP + TR | Live Coach waits for or ships its own minimal copies behind the same interfaces |
| UQ-19 | Accessibility targets beyond this spec (formal WCAG level, hearing-impaired policy) | OP | WCAG 2.2 AA on new surfaces |
| UQ-20 | Number and spoken-language formats for the languages in scope (OQ-15) and the English/Russian word list for earcons and cues | OP | Russian default; English second |
| UQ-21 | Plausibility bounds for reps and weight that trigger confirm-first (4.7), and who owns the table | OP + TR | Runtime-owned closed table; the UI only shows the prompt |
| UQ-22 | How a pain or unwell report made on a non-owner device reaches the owner device | TR + LEGAL | Local stop on the reporting device only |
| UQ-23 | Exact-alarm permission for the rest-over backstop notification | TR | Non-exact notification; the cue may be late |
| UQ-24 | Consent re-prompt cadence after "Not now" (days and maximum count) | OP + LEGAL | At most once per 7 days, at most 3 times, then settings only |
| UQ-25 | Source of the owner device display name shown in LC-15 | TR | Generic "your other phone" |

## 17. What could not be grounded

- The internals of `workout_player_page.dart` set entry (weight step, units, widget names) and `rest_timer.dart` visuals: only class lists and semantic notes were read.
- Whether S03D's strip/dock, `windowSizeClass` and HUD primitive extensions will exist before Live Coach is built (S03D is a DRAFT revision 3).
- The behaviour of Android 13-16 for foreground-service microphone types, notification-permission denial, audio-focus loss and background restart; the UI follows the draft's rule not to assume arbitrary restart (C-08).
- The voice, transport and provider choice (Mode A / Mode B), which changes the PROCESSING and SPEAKING mic behaviour (UQ-12).
- Real-gym noise and glove behaviour: only a real-device trial can confirm the target sizes and the listening mode.
- Whether a Form Coach finding will ever reach the context (P2): technique wording stays out of the UI until it does.
- A real-device TalkBack walk is NOT_RUN; this spec is design intent.

## 18. Inventories

Journeys: J1 first use, J2 start voice session, J3 hands-free set, J4 rest, J5 interrupt, J6 replace machine, J7 report pain, J8 lost network, J9 incoming call, J10 Bluetooth drop, J11 locked screen, J12 finish, J13 resume after crash, J14 AI unavailable manual, J15 permission removed or mic taken, J16 review plan, J17 stop voice / withdraw consent / delete data (17).

Screens: LC-1 entry, LC-2 consent and privacy, LC-3 permission rationale and denied, LC-4 pre-start sheet, LC-5 live screen (voice, workout and condition state tables), LC-6 plan review, LC-7 conversation states, LC-8 safety stop, LC-9 AI-unavailable manual mode, LC-10 replace sheet, LC-11 symptom sheet, LC-12 finish summary, LC-13 resume prompt, LC-14 coach settings and privacy, LC-15 second-device read-only state; plus the foreground notification (9.5) (15 screens + notification). Tables: 4.6 allowed-action table, 4.7 undo and correction.

Components: C-1 to C-24 (section 7).

## 19. Change list for round-1 remediation (review ids applied)

All text remains DRAFT. Applied in this file only; `03_DESIGN.md` is edited by another agent and `06_REMEDIATION_DECISIONS.md` wins on any difference.

| Review id | Where applied |
|---|---|
| UX-1 | 4.5 Saved row, 4.7, J3 step 6, C-7, AC-LC-27, AC-LC-28 |
| UX-2 | 8.3 note: confirmation needs a Runtime contract; "10.4" not relied on |
| UX-3 | J7 step 4, LC-8 Resume, 4.6, AC-LC-13 |
| UX-4 | J4 step 3, J9, LC-8 Lock, 6.2 RESTING and PAUSED, 9.5 table, AC-LC-13 |
| UX-5 | J7 step 3, LC-8 (per-locale number, notification, joint-pain mapping), UQ-09 |
| UX-6 | 4.1 (NO_MATCH, LOW_CONFIDENCE, tap-to-talk default), 6.1, 8.2 ack cue, LC-14 row 2, AC-LC-32, UQ-12 |
| UX-7 | LC-1 Ready, 6.2 SET_IN_PROGRESS, 9.4, copy keys, AC-LC-29 |
| UX-8 | Section 11 screen-reader policy and controls row, AC-LC-24 |
| UX-9 | 9.6, LC-5 header, AC-LC-17, UQ-15 |
| UX-10 | Section 11 time limits, T-7 |
| UX-11 | 6.2 NEXT_EXERCISE as derived view; LC-15 and 4.3 (second device) |
| UX-12 | 4.5 rules (late ack, idempotent retry), AC-LC-6, AC-LC-39 |
| UX-13 | J1 step 3, LC-2 items 3, 3b, AC-LC-35 |
| UX-14 | LC-14 row 2a, section 11 reduced motion, 6.2 SET_RECORDED, AC-LC-21 |
| UX-15 | C-2 events, section 11 policy item 4 |
| UX-16 | 6.2 RESTING, section 11 touch targets, AC-LC-23 |
| UX-17 | J7 step 1, LC-5 header, C-24, AC-LC-23 |
| SF-1 | 4.3, J7 step 5, LC-8 Persistence failure, AC-LC-13 |
| SF-4 | LC-13 ERROR and RECOVERY FAILED, copy rule 14, AC-LC-38 |
| SF-5 | 4.1 mic indicator truth, C-2, 6.1, AC-LC-31 |
| SF-6 | Copy rule 12, 4.5 Confirmed row, AC-LC-30 |
| SF-7 | 4.3, 4.6, 6.3 safety-unavailable banner, AC-LC-12 |
| SF-8 | 4.3, 6.3 Sync blocked, J8, copy rule 13, AC-LC-33 |
| SF-11 | 4.5 rules, AC-LC-29 |
| SF-12 | 4.5 table and rules, T-3, AC-LC-6 |
| SF-14 | J17, LC-14 withdrawal failure, AC-LC-36 |
| SF-17 | LC-12 ABANDONED, LC-13, copy rule 14 |
| SF-18 | LC-12 ERROR, AC-LC-39 |
| SE-13 | LC-2 items 3a, 3b, LC-14 consent row, AC-LC-35 |
| SE-18 | J12, 8.3 |
| SF-9 (flag-off) | LC-1 rows, J13 step 5, AC-LC-37 |
| SE-1 (partly) | LC-2 item 3a (utterance declared health-bearing); the privacy policy and Play data-safety form prerequisite is not specified here |
| 06 A2 (ownership) | LC-15, C-23, 4.3, AC-LC-34 |

New open items added: UQ-21 to UQ-25. Not applied in this file: the rest of 06 sections A3 to A8 that concern code, rules, cost and documents (not UI); numeric consent cadence, plausibility bounds and the symptom list stay OPEN.
