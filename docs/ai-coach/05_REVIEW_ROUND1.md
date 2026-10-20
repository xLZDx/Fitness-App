# AI Coach documentation: review round 1 findings

Date: 2026-10-17. Reviewers (Sonnet 5.5, read-only): product-ux-reviewer, architect, security-reviewer, reliability-reviewer, silent-failure-hunter. Findings are claims by the reviewers until the remediation batch verifies each against the cited source. Severity: BLOCKER unsafe to proceed; MAJOR material correctness, safety or rework risk; MINOR bounded improvement.

## 1. product-ux-reviewer (17 findings, 0 BLOCKER, 12 MAJOR, 5 MINOR)

Not verified by the reviewer: Flutter code claims taken from S03D, 02_BACKLOG.md, 04a, contrast figures, Russian string budgets.

| ID | Sev | Finding | Required change |
|---|---|---|---|
| UX-1 | MAJOR | A misheard set (for example "eighty" for "eight") is journaled before the user hears the read-back, and the draft has no void or edit command; correction window T-5 is 10 s (03b:122,436,445,678) | Make correct/void a P0 requirement, visible Undo on the Saved card, defined behaviour after T-5, an acceptance criterion, confirm-first for implausible values |
| UX-2 | MAJOR | Design cites read-back confirmation "10.4" that does not exist (03_DESIGN.md:108); UI confirmation tiers have no runtime contract | Add a design section for confirmation, correction and duplicate-suspect, or drop the reference |
| UX-3 | MAJOR | Safety-stop resume: UI says voice alone never clears it (03b:336,596), design allows a distinct confirmed phrase (03_DESIGN.md:195) | One rule; the UI rule is safer, so the design drops the phrase option |
| UX-4 | MAJOR | Behaviour of the rest timer during a safety stop is unspecified and documents disagree (03_DESIGN.md:195,320 vs 03b J9/J10) | Suppress rest cue and freeze or hide the countdown; add to the acceptance criterion |
| UX-5 | MAJOR | Safety-stop routes incomplete: joint-pain mapping to PAUSED/ABANDONED, emergency number by locale, no action on the locked-screen notification | Define per-locale number, whether a Call action is allowed on the notification, joint-pain state mapping |
| UX-6 | MAJOR | Default always-on hands-free in a noisy gym; no NO_MATCH / "did not catch that" state; echo cancellation on the target device UNKNOWN | Add NO_MATCH and low-confidence states and an ack cue; tap-to-talk (or headset-only hands-free) as MVP default until the gym trial |
| UX-7 | MAJOR | Copy "phone stays in your pocket" contradicts defaults (screen on, proximity guard off); the 64 dp primary control may log directly; the locked-screen mode may fail spike S-A1 | Conditional copy; primary dock action opens the set-entry sheet; specify pocket-touch default |
| UX-8 | MAJOR | TalkBack announcements can be picked up by the mic and duplicate the coach read-back; focus jump to Stop talking conflicts with reading order | Define a screen-reader policy: suppress duplicates while the coach speaks, headset or tap-to-talk when a screen reader is active, no focus jump |
| UX-9 | MAJOR | Back keeps the microphone open with only a one-time snackbar (03b:478, UQ-15) | Persistent cue; confirm sheet on Back or Back closes voice |
| UX-10 | MINOR | Confirm timeout T-7 (15 s) is short for screen-reader and motor-impaired users | Extend with a screen reader or make the timeout visible/optional |
| UX-11 | MAJOR | NEXT_EXERCISE is transient in the design but has a HUD row and dock control in the UI (03_DESIGN.md:66; 03b:279-290) | Render it as a view derived from ACTIVE_EXERCISE |
| UX-12 | MINOR | "Not confirmed" at 4 s can later resolve to Saved; Try again idempotence not stated in the UI | State that the card updates and retry is idempotent |
| UX-13 | MAJOR | Consent gaps: "Not now" reads as deferral, no re-prompt cadence, offline consent validity, age gating before the mic screen | Define cadence, firm-decline label and age gating; server-side consent record stays an operator/legal question |
| UX-14 | MINOR | Reduced motion follows only the OS setting | Add an in-app row or document why not; respect it for the highlight and auto-advance |
| UX-15 | MINOR | Status row read as one group vs tappable chips | Expose chip actions as custom accessibility actions |
| UX-16 | MINOR | HUD rest controls have no size rule; the existing button is 44 dp | 56 dp minimum for rest controls; tie the acceptance criterion |
| UX-17 | MINOR | Pain control is a chip in a scrolling bar that can scroll away or be disabled | Pin it outside the scrolling bar, never disabled by state |

## 2. architect (18 findings, 1 BLOCKER, 12 MAJOR, 5 MINOR)

Not verified by the reviewer: second halves of 03b (lines 475-714) and 04a (lines 228-512) except rules rows; ai_coach_advice.ts and abuse_guard.ts citations; Android/Play/speech_to_text claims.

| ID | Sev | Finding | Required change |
|---|---|---|---|
| AR-1 | BLOCKER | Multi-device conflict can lose confirmed sets: read-only second device waits for takeover (OQ-23 open), journals are never merged (G18, FT-1080), set ids `session:seq` collide on create-only docs and the whole batch is rejected; contradicts "lost confirmed sets = 0" | Single-writer ownership of a live session (lease or owner token) or a deterministic merge or fork rule; define what happens to the loser's journal |
| AR-2 | MAJOR | The replica revision fence does not enforce a single writer: check is client-side, skipped revisions pass, deviceId is mutable, sets and commands have no getAfter link | Put deviceId or an owner token in the fence, or state that the server does not arbitrate |
| AR-3 | MAJOR | Rest timer ownership inconsistent: RestTimerController has start(Duration) only (rest_timer_providers.dart:152-153), no absolute restEndsAt restore; design says runtime is pure Dart, no existing file changes, no timer in runtime/ | Name the owner of rest state; additive restore API on the controller or Runtime owns restEndsAt and the controller only renders |
| AR-4 | MAJOR | Time-driven transitions (rest elapsed, PREPARING) have no journal or revision semantics; if expiry bumps the revision, model-mediated commands go stale systematically | Decide whether timer events are journaled internal commands; define staleness for model and voice commands |
| AR-5 | MAJOR | Single-writer assumption of the Runtime breaks if a service-owned cached engine hosts it (two isolates, two mutexes, one journal file) | Declare one sole owner isolate for Runtime, journal and timer; the other is a thin client |
| AR-6 | MAJOR | Account deletion and offline replay can resurrect live data: tombstone and account fence omitted (firestore.rules:978-988); local journal purge on deletion UNKNOWN (G13) | Add the fence to live-session rules; define local purge |
| AR-7 | MAJOR | Failing closed on the feature flag conflicts with offline-first and with finishing a running session (1 h cache) | Flags gate new starts only; define offline start rule |
| AR-8 | MAJOR | The server-confirmed level has no mechanism for the workout_sessions projection; save() has the 4 s swallow (firestore_workout_session_repository.dart:67-70) and LogSessionAction awaits it (workout_session_providers.dart:93-105) | Specify an observer with snapshot metadata for the projected doc; do not route the projector through LogSessionAction |
| AR-9 | MAJOR | Refusals and the idempotency ledger contradict: journaling a transient refusal replays it forever for a derived id | Refusals are not recorded in the ledger, or carry a retryable marker; fix step 2 |
| AR-10 | MAJOR | Session-minute cost model does not fit Mode B (per-turn), the default; leak if end-session is never called (G10, G11) | Per-turn budget for Mode B; reservation expiry; state whether the kill switch blocks end-session |
| AR-11 | MAJOR | Requirements not amended (AICR-021, 022, 028, 032) while the design and 04a say "design wins" | Amend the requirements or record a deviation per AICR before design review closes |
| AR-12 | MAJOR | D1..D17 not all resolved: D11, D13, D14, D15 OPEN, D3 depends on OQ-23, D8 on OQ-07; "DECIDED (proposed)" is not a status | Three-value status per row; list which D items gate AI-COACH-01 |
| AR-13 | MAJOR | State-machine gaps: safety_stop target "ABANDONED or PAUSED", commands allowed from NOT_STARTED, no add_rest_time, no edit or void-set command, NEXT_EXERCISE HUD vs transient state | Add the commands and void semantics to the enum; fix the row; reconcile NEXT_EXERCISE |
| AR-14 | MAJOR | Safety-stop trigger and scope differ between design 9.3 and UI J7 (closed phrase list vs free text; whole workout vs exercise only) | One scope; closed classifier for free text, or default to pause |
| AR-15 | MINOR | Projection recovery duty unstated; a finished session invisible in History until next launch | State the recovery step and ordering (journal, projection, replica) with an idempotency key |
| AR-16 | MINOR | Separate collection plus rules fence, flag mechanism and L1..L3 semantics lack their own ADRs | Give each an ADR |
| AR-17 | MINOR | Voice-state vocabulary differs (user mute PAUSED in UI, not in design 10.1) | Add the transition to the design table |
| AR-18 | MINOR | Journal-stalling conditions have no escape | Conflict-resolution terminal and size or age bound |

## 3. security-reviewer (18 findings, 0 BLOCKER, 7 MAJOR, 11 MINOR)

Not verified by the reviewer: what `sub()` in account_export.ts does for nested sets and commands; Vertex retention terms; Android foreground-service rules; which recogniser speech_to_text uses; reconcileAccountDeletions in full; 04b by grep only; 01b and 03b lines 475-714 unread.

| ID | Sev | Finding | Required change |
|---|---|---|---|
| SE-1 | MAJOR | The live privacy policy says health answers are never sent to any AI model and that the app does not use the microphone (public/privacy.html:66,82,90); the package has no deliverable to change it before the first build that calls liveCoach* | Policy update (voice, STT and model provider, retention) plus the Play data-safety form are a hard prerequisite for any build calling liveCoach*, as an AI-COACH-02 acceptance item |
| SE-2 | MAJOR | "No health-derived value reaches the model" (03_DESIGN.md:190) is false for the real channels: free speech utterance, report_symptom, safety_status reason codes, refused_safety codes, free-text "Something else"; the provider-terms check covers Mode A only | Declare the utterance a health-bearing channel in the consent text; provider retention and no-training criteria also for Mode B; classify free-text symptoms on device only; drop InjuryFilterReason and ScreeningCeilingReason codes from model-bound context; FT row that a spoken health statement is never logged server-side |
| SE-3 | MAJOR | Requirements and backlog still mandate sending restrictions to the model (AICR-010, ACS-040 AC-1) and say a UID is "ignored" where the design says rejected (ACS-028 AC-2); design section 23 omits them | Amend AICR-010, ACS-040 AC-1, ACS-028 AC-2 and add them to design section 23 |
| SE-4 | MAJOR | Journal and plan files under the app support directory are plaintext and not excluded from Android Auto Backup (backup_rules.xml:45-57, data_extraction_rules.xml:27-47); the activity journal precedent is AES-GCM encrypted (journal_cipher.dart); adding the exclusion edits the exact-set backup_rules_test, which conflicts with AICR-069 / FT-1071 | Exclude live_coach in both XML files and the shared constant; encrypt with the existing cipher pattern; declare the backup_rules_test edit as intentional; test that stored bytes are not plaintext |
| SE-5 | MAJOR | Copy of the activities pattern omits the account-deletion fence (firestore.rules:985-996, fence.ts, index.ts:2643-2651); a second device replays queued batches after deletion; liveCoach* callables could write after deletion | Fence guard in the new rules blocks; checkAccountFence in every liveCoach* callable; rules emulator test that a write is denied once the fence exists |
| SE-6 | MAJOR | The cost cap is minute-based and does not bound Mode B per-turn spend or concurrency (abuse_guard.ts:389-431, scaling.ts:361-368: 150 in-flight AI calls fleet-wide) | QUOTAS.liveCoachTurn, per-session turn cap, per-user in-flight and rate limit, required maxOutputTokens, add to AI_GATEWAY_OPERATIONS (ai_gateway.ts:172-185), function tests |
| SE-7 | MAJOR | The server replica carries health signals: commands store action and resultCode, including SAFETY_BLOCKED, SCREENING_INCOMPLETE and safety_stop (03_DESIGN.md:93,130); existing rules strip health fields (firestore.rules:209-250); FT-1092 forbids only three keys | Replicate only an allowlisted set of non-health action and result codes; exclude safety_stop and SAFETY_* from the replica; enforce in the rules enum; emulator test |
| SE-8 | MINOR | Injection posture assumes capabilities the gateway lacks: generate() takes one prompt string, no systemInstruction or tools (ai_gateway.ts:222-234,284-305); client-supplied titles in the snapshot; an injected model-emitted record_set runs before confirmation | State how tool calls are produced (JSON responseSchema or an extended gateway); ids over titles; reword FT-2026/2033 to what is achievable; specify the missing "read-back 10.4" |
| SE-9 | MINOR | Voice-session ownership, reservation, flag and allow-list records have no stated location; the data-lifecycle policy file (scripts/ci/data_lifecycle_policy.json) needs a classification for each new collection; export list (account_export.ts:511-557) | Keep records under users/{uid}/ or add a sweep; add collections to the policy file and the export list |
| SE-10 | MINOR | Local cleanup on account deletion marked blocked (FT-1100, G13) although main.dart:611 already wraps the wipe via ActivityAwareLocalDataWipe | Wrap the same way and unblock FT-1100 |
| SE-11 | MINOR | live_coach_memory may hold health text; free text versus closed vocabulary open (G16) | Closed value vocabulary in the rules; FT-3027 tests it |
| SE-12 | MINOR | Mode A credential gate C9 lacks: credential locked to server-set prompt, tools and model, single use, revocation, budget re-check on renewal | Add to C9 and spike S-A8 |
| SE-13 | MINOR | Consent only partly specified: storage location, withdrawal, versioning; consent text must name the STT recogniser, the model provider and that spoken health statements are included | Record consent version and timestamp per uid (allowlisted, in export and delete); test that capture is refused without current-version consent |
| SE-14 | MINOR | The "no raw audio" test cannot see the platform recogniser (FT-2044) | Decide on-device-only recognition or disclosure; test that the recogniser prefers offline |
| SE-15 | MINOR | App Check posture under-specified for new callables and getFeatureFlags; non-AI options default to unenforced (scaling.ts:195) | Specify options per callable and pin them in the scaling test |
| SE-16 | MINOR | Per-feature emergency kill lives in a Firestore document that the runtime identity can rewrite (abuse_guard.ts:156-166) | Document the limit or use the Secret Manager switch for per-feature kills |
| SE-17 | MINOR | Replica documents unbounded in number; the design cites activities rules at 966-1007 but they are at 989-1011 | Bound seq range in the id regex or route writes through a quota'd callable; fix the citation |
| SE-18 | MINOR | Ambient speech issues commands; confirmations arrive through the same lane | Document residual risk; screen or headset-button confirmation for finish_workout and abandon when available |

## 4. reliability-reviewer (23 findings, 0 BLOCKER, 11 MAJOR, 12 MINOR)

Not verified by the reviewer: only the first 227 of 512 lines of 04a were read; 01b, 03b and most of 02/03a unread; Android behaviour unverified.

| ID | Sev | Finding | Required change |
|---|---|---|---|
| RL-1 | MAJOR | Model-mediated commands have no stable command_id; only the command lane derives one from (voiceSessionId, utteranceId) (03_DESIGN.md:108 vs 299-309) | Derive tool-call ids from (voiceSessionId, utteranceId, toolCallIndex); make liveCoachTurn idempotent per utterance; test a retried turn |
| RL-2 | MAJOR | liveCoachTurn has no client deadline, retry bound or error policy; PROCESSING has no timeout exit | Per-turn deadline, PROCESSING to LISTENING timeout with a local message, never auto-retry state-changing tool calls, no-charge rule for failed turns |
| RL-3 | MAJOR | The rules fence omits the activities tombstone and account-deletion fence (firestore.rules:978-1007); an unsynced journal can recreate live data after account deletion | Same account-state fence on live collections; define purge on refusal; rules emulator test |
| RL-4 | MAJOR | Foreground-service engine and Activity engine could both write the same journal (03_DESIGN.md:230,101) | One owner isolate for the Runtime with the UI as a thin client, or an OS file lock plus single-writer lease; two-engine test |
| RL-5 | MAJOR | Journal durability relies on an outbox precedent that uses temp file plus rename, not append (equipment_identity_telemetry_outbox.dart:229-248) | Real-device kill and low-disk run in the AI-COACH-01 exit criteria, or decide SQLite now; define the disk-full behaviour |
| RL-6 | MAJOR | Journal retention rules conflict (03_DESIGN.md:139 vs 145, FT-1077); a rejected replica write never reaches the server-confirmed level | Define terminal states (sync-failed), bound journal count and size, never auto-delete an unfinished session |
| RL-7 | MAJOR | Projection after COMPLETED goes through the old save() with its swallowed timeout; no durable "projected" marker; the streak update is not shown idempotent | Durable projected marker, streak update idempotent by sessionId, project-twice test |
| RL-8 | MAJOR | Foreground-service start rules are UNVERIFIED-EXTERNAL but the requirements rely on them; no design for service death | Service-death section, notification independent of the microphone, behaviour on ForegroundServiceStartNotAllowedException, spike as a gate for AI-COACH-02 |
| RL-9 | MAJOR | Rest end cue is a Dart timer; a killed process during a locked-screen rest fires nothing | OS-scheduled alarm or notification at restEndsAt as backstop with permission analysis; e2e coverage |
| RL-10 | MAJOR | The three-level sync driver has no backoff, attempt cap, poison-record handling or backlog age | Exponential backoff with jitter, max attempts, quarantine of poison records with a visible sync-failed state, FT rows |
| RL-11 | MAJOR | Observability sink is UNKNOWN; events have no aggregation, alert or owner | Name the sink; alerts for recovery failure rate, persist-failed rate, sessions stuck below the server-confirmed level over 24 h, reservation leaks; forced-failure test |
| RL-12 | MAJOR | Minute reservation leaks if liveCoachEndSession is never called (G10) | Server-side lease with expiry and refund, renewal heartbeats, idempotent end and refund, allowed under the kill switch |
| RL-13 | MINOR | Idempotency lookup is O(file); start-up replay of all journals on the main isolate | In-memory id set per session, bounded replay, max journal size |
| RL-14 | MINOR | Same command_id with a different payload returns the original silently | Emit command_id_payload_mismatch event and test it |
| RL-15 | MINOR | Reconnect has no backoff, cap or credential renewal; give-up target state undefined | Bounded reconnect, renew-credential step, give-up state |
| RL-16 | MINOR | Local resource exhaustion not designed (disk full, store quota, concurrent callables, long-session TTS/recogniser) | Disk preflight, low-space warning, documented manual-only mode |
| RL-17 | MINOR | Two unfinished journals for one uid (G18) undecided; a new start may conflict with the old replica lease | Refuse or park a new start while one is unfinished; discard is the only destructive path with confirmation |
| RL-18 | MINOR | Replica commands and sets collections have no retention | Retention or TTL policy; drop commands after completion |
| RL-19 | MINOR | Batch size 8 with getAfter lookups may exceed the rules call budget | Measure in the emulator and derive the batch size |
| RL-20 | MINOR | Feature-flag cache TTL (1 h, expired is OFF) is shorter than a workout | An active session keeps running on an expired cache; OFF applies to new sessions; the server kill switch stops new turns |
| RL-21 | MINOR | Device clock changes during a wall-clock rest | Bound remaining to the original duration; backward clock jump test |
| RL-22 | MINOR | 04a rows missing for isolate concurrency, poison record, rest backstop alarm, disk full; FT-1026 uses a fault double, not a real kill | Add rows and a device-level kill test; limit the claim to the test device |
| RL-23 | MINOR | liveCoachStartSession not idempotent; a retry reserves a second budget slice | Client request id; reconcile minutes by voiceSessionId; cap open reservations per user |

## 5. silent-failure-hunter (21 findings, 1 BLOCKER, 15 MAJOR, 5 MINOR)

Basis tags used by the reviewer: FACT (cited file opened), DOC (conflict between package documents), EXT (external behaviour not verified). Not verified: 04b was absent at review time; 01, 02, 03a and the input draft not read in full; Firestore rejected-queued-write behaviour and Android recogniser lifetime not checked.

| ID | Sev | Finding | Required change |
|---|---|---|---|
| SF-1 | BLOCKER | A failed journal write rolls back in-memory state (03_DESIGN.md:103) and safety_stop is an ordinary command (03_DESIGN.md:195): after a reported symptom with storage full the stop is undone and timers continue | The in-memory stop and the local message take effect before and regardless of persistence; persistence failure only adds a notice; add safety_stop to the fail-before-append, fail-on-flush and out-of-space cases |
| SF-2 | MAJOR | Finished-workout "synced" cannot be observed: the repository has only save and watch, save returns normally after 4 s offline, watch has no metadata changes (workout_session_repository.dart:32,18; firestore_workout_session_repository.dart:67-70,45-49) | Add a confirmation-observing path for the projected document and gate journal deletion on it; FT-1076 needs a silent-save double |
| SF-3 | MAJOR | Journal may be deleted after 30 days although never confirmed or projected (03_DESIGN.md:139 vs FT-1077); abandoned sessions rely on that timer | Remove the time-based delete; only user-visible delete or export first |
| SF-4 | MAJOR | UI says "your results are not lost; open History" for a corrupt journal while live sets are kept out of History (03b:353) | Neutral wording, a visible recovery-failure state, keep the file |
| SF-5 | MAJOR | The microphone on/off chip has no ground-truth source: no capture-started, capture-stopped or capture-lost events in the port (03_DESIGN.md:226) | Native capture events plus a liveness watchdog; render only from them; a "mic state unknown" display |
| SF-6 | MAJOR | The model's replyText can claim success while a tool call is dropped or refused; nothing governs it | For state-changing intents speak only device-generated text after the result; tell the device when a tool call was dropped; test with a stub |
| SF-7 | MAJOR | Safety-unavailable behaviour is described three incompatible ways (03_DESIGN.md:187 vs 03b:301,529 vs FT-1049); a performed set could be lost | Recording a performed fact is never gated; align design, banner and rows via one shared allowed-action table |
| SF-8 | MAJOR | Replica sync failures have no terminal state; UI says "will sync when you are online" even for rejection | A sync-blocked state with attempt and age bounds, chip, event; journal-driven reconciliation |
| SF-9 | MAJOR | The feature flag fails closed and hides the live screen for an offline user mid-workout after the 1 h cache expires | Flag OFF only blocks new sessions; an unfinished session is always honoured; explicit reason shown |
| SF-10 | MAJOR | The finish projection inherits a streak write that is lost offline (workout_session_providers.dart:138-147) | Tracked, retried streak step in the projection state; delete the journal only after it is confirmed, or recompute at the next confirmed sync |
| SF-11 | MAJOR | A double tap on Log set can create two sets: manual commands reuse the current revision and the command_id mint point is unspecified | Mint command_id when the entry sheet opens or disable the control until ack; extend the duplicate-suspect check to taps |
| SF-12 | MAJOR | Late ack after "Not confirmed" undefined; T-3 tied to the old 4 s swallowed timeout; Try again re-sends an old expected_revision | The dispatch result is authoritative; reconcile against the journal head before showing "Not confirmed"; upgrade the card on a late ok |
| SF-13 | MAJOR | Nothing proves journal durability: FT-1026 uses a fault-injecting store and a permissive oracle | Device kill-loop scenario (E2E-07) with the oracle "acknowledged set present exactly once"; remove the "or" |
| SF-14 | MAJOR | Withdrawing consent has no failure path | Apply locally first with a persistent flag; block capture until persisted; visible failure state |
| SF-15 | MAJOR | Minute reservations leak and the user sees a false "daily limit" banner | Expire reservations server-side with refund; distinct copy |
| SF-16 | MAJOR | No test covers the UI never-claim table N-1..N-15 and AC-LC-5..26 | Map each N item to a row with a stated "fails if" (04b now exists and must be checked for this) |
| SF-17 | MINOR | ABANDONED summary says "{n} sets are saved" while nothing goes to History (03b:350) | "Saved on this phone, not in History" or project partial sessions |
| SF-18 | MINOR | LC-12 error says "Your sets are saved" although the read failed | Say saved sets could not be read; offer retry |
| SF-19 | MINOR | Voice idempotency assumes the recogniser gives stable utterance ids | Fallback id (hash of text plus audio window) in the port contract; test |
| SF-20 | MINOR | Observability sink unknown, events may go nowhere | Name the sink before sprint 01; test delivery |
| SF-21 | MINOR | Several rows test against doubles that encode the SDK behaviour (FT-1063/1064/1073/1074) | Run FT-1063, 1064, 1074 once against the Firestore emulator |
