# S04 requirements: GPS core without a map (recorder, not map)

Status: DRAFT for review, prepared 2026-10-17 on branch `phase2/s04-docs`; round 1 remediation applied 2026-10-17 (see the last section). Documentation only; no code, no commands run. Author role: business-analyst. All paths are relative to the repository root.

## 1. Purpose, scope, non-goals

Purpose: fix what the S04 recorder must do so that a designer can design from it and a tester can falsify it. This file holds requirements only. It does not choose architecture (architect), rank the backlog (product-owner), or design screens (S04-D contract, a separate document, see A-8).

In scope (Roadmap line 89, the S04 row): foreground-service recorder, journaled samples with crash-safe resume, auto-pause, smoothing and accuracy gate, calculators with replay tests (P2-009), permission flow (foreground first, background only while recording), battery protocol, recording that works with no map service.

Out of scope (non-goals): any map, tile or route display (S11, S05-D, S06-D); the EXPLORE and RIDE screens themselves (S05, S06); sharing, publishing, privacy-zone editor (S09, S10-D); heart-rate and BLE sensors (S06); FIT/GPX import and export; cloud upload of streams (A-6); the full consent centre (A-3); iOS (A-1).

## 2. Labels and sources

- FACT: read in the cited file (path:line). INFERENCE: drawn from facts, stated as such. ASSUMPTION: a default this file adopts so work can proceed (section 3). UNKNOWN: not verifiable here; owner named in section 11.
- PROPOSED: every number or rule invented in this file. None is measured or researched. A PROPOSED number becomes binding only when the product-owner and the operator accept it (the numbers marked "device-lab" are also re-checked on the reference phone).
- Priority: MUST (sprint fails DoD without it), SHOULD (expected; may slip with a recorded reason), COULD (nice to have).
- Short names: Roadmap = `docs/phase2/plan/03_ROADMAP_AND_SPRINTS_2026-10-15.md`; Readiness = `docs/phase2/s04/S04_DOC_READINESS.md`; Privacy = `docs/phase2/s01/GPS_LOCATION_PRIVACY_CONTRACT.md` (ids GPS-PRIV-nnn); S02 = `docs/phase2/s02/S02_DESIGN.md`; S03D = `docs/phase2/s03/S03D_UI_DESIGN_CONTRACT.md`; Round1 = `docs/phase2/s04/S04_REVIEW_FINDINGS_ROUND1.md` (decisions X1..X10 in its section 1; they are defaults the operator may override); Design = `docs/phase2/s04/S04_DESIGN.md` and S04-D = `docs/phase2/s04/S04D_UI_DESIGN_CONTRACT.md` (both edited by other authors in parallel; this file refers to them only through Round1).

## 3. Assumed defaults (operator decisions not yet answered)

Each default below is used throughout this file. "If the operator picks differently" says what changes.

| # | Decision in words | Default used here | If the operator picks differently |
|---|---|---|---|
| A-1 | Does S04 include iPhone? (Readiness section 4 item 1; Roadmap line 257, D-12) | Android only. iOS is NOT_RUN: no iOS claim anywhere. | Include iOS: requirements S04-R-001, -021..-026, -050 gain an iOS twin (background modes, permission strings, backup exclusion per `core/DECISION_LOG.md` line 57853), the repository needs an iOS project first (Roadmap line 268), and the DoD needs a physical iPhone. S04 grows by an unestimated amount (UNKNOWN). |
| A-2 | Which phone is the reference device? (Readiness item 2; Roadmap line 171) | UNKNOWN. All device-lab numbers (battery drain, frame time, kill-survival timing) are PROPOSED targets, not commitments. | When a model is named: the targets are re-set from one measured baseline run and the PROPOSED marks are removed one by one. Without a phone the DoD "tolerance and battery recorded on the operator's phone" (Roadmap line 89) cannot close; S04 can be coded and reviewed but not accepted. |
| A-3 | Where is the consent centre built? (Readiness item 3; gap G7) | S04 builds only the two location consent rows it needs: "location while recording" and "background location". The full centre waits. | Separate sprint before S04: S04-R-026 moves to that sprint and S04 only reads the stored consent. No stored consent beyond the system permission: contradicts GPS-PRIV-009 (Privacy line 88), not recommended. |
| A-4 | Default privacy-zone radius and zone-editor owner (Readiness item 4; Privacy line 166) | A default radius of 200 m (PROPOSED, S04-R-048). The zone editor is owned by S10-D. S04 only defines the default constant and the setting key. | Different radius: one constant changes, no recorder behaviour changes (S04 shares nothing). Editor in S04-D instead: S04-D grows and builds a UI the S04 code does not use. |
| A-5 | Default cloud expiry of GPS tracks (Readiness item 5; Privacy line 232) | 2 years counted from the activity date (PROPOSED, S04-R-049). The value is recorded as a default constant only; S04 enforces nothing because upload is off (A-6). | Upload date as the clock, or another default: only the constant and the privacy text change in S04; enforcement is in the later sprint that enables upload. |
| A-6 | Does S04 upload? (Readiness item 6) | No. S04 ships recording that stays on the device; the cloud-upload flag stays OFF and no upload path is enabled (GPS-PRIV-013, Privacy line 100). | Upload in S04: needs the S02 performance gate, the server deploy order and approved privacy text first (`docs/phase2/s02/S02_RELEASE_NOTES.md` lines 104, 111); S04-R-046 is replaced by an upload requirement set. |
| A-7 | Is the location pre-prompt wording approved? (Readiness item 7; Privacy lines 89-90) | Wording is DRAFT until approved. S04 is owner-only, so release with draft text is allowed, but the text carries a "DRAFT" marker in the change record, and approval is required before S09 sharing. | Approval required before the S04 release: a text-approval step is added before release, with no code change. |
| A-8 | Is S04-D a separate contract? (Readiness item 8) | Yes. S04-D is a separate contract produced in this documentation phase and approved before S04 design starts; "S04 builds only this" (Roadmap line 88). | Folded into the S04 documentation phase: the independent approval point is lost; requirements here stay valid, only the gate order changes. |

## 4. Facts that shape the requirements

- FACT: no location package, no recorder and no foreground service exist; the Android manifest declares no location or foreground-service entry (Readiness line 47; Privacy line 30).
- FACT: `ActivitySession` has 8 `StreamKind` values including gps; validation bounds are 200 000 samples per stream, lat -90..90, lon -180..180, strictly increasing offsets (S02 lines 28, 256).
- FACT: one repository owns the journal behind an in-process mutex; "the S04 recorder submit[s] mutations through it and never touch[es] files directly" (S02 line 452). Round 1 (architect review, Round1 section 3) found that this S02 interface cannot take one append per second; the per-second path is a sibling recording journal (S04-R-014). The S02 line is therefore FACT about S02 only, not a design for the recorder.
- FACT: the strip reads one provider, `activeSessionStatusProvider`, whose core reads only the set timer and rest timer; the set timer wins; the owner slot is written only by the workout page (Readiness lines 112-113; S03D lines 327-334).
- FACT: S03D rule R-S5: process death clears both timers; no strip, no recovery claim (S03D line 346). S03D states that future sources "implement the same `ActiveSessionStatus` without changing the strip" (line 334); the S03 review found this does not hold (Readiness line 112).
- FACT: payload build, gzip, SHA-256 and journal seal/open must move off the UI isolate with a 100k-sample frame-budget test before any recorder ships (Readiness G10; `docs/phase2/s02/S02_RELEASE_NOTES.md` line 104).
- UNKNOWN: content of backlog item P2-009 (the backlog file was not found, Readiness line 108). Requirements here are derived from the Roadmap row text, not from P2-009 story text.
- UNKNOWN: Android platform constraints (foreground-service type, manifest entries, Play declarations, Android 13+ notification behaviour, OEM battery killers). Privacy line 267 says they were not checked against official sources. Platform statements in this file are labelled UNVERIFIED until the platform study (Readiness G4) exists.

## 5. Requirements: recorder core

### S04-R-001 (MUST) Foreground-service recorder
Statement: Recording runs in an Android foreground service of the location type, started only by an explicit user action ("Start") while the app is visible, and showing a persistent notification for as long as it collects. UNVERIFIED pending the platform study: exact service type and manifest entries.
Rationale: survives screen off and app backgrounding (DoD); GPS-PRIV-007 demands a persistent notification during background collection.
Source: Roadmap line 89; Privacy lines 78, 86 (GPS-PRIV-007).
AC: (a) a device-lab run with the screen off for 60 min yields a continuous track; (b) the notification is present from first sample to stop; (c) a test that starts the service without a user action does not exist (no code path starts it from boot, launch or a push).

### S04-R-002 (MUST) Stop releases everything
Statement: Stop or discard ends the foreground service, removes the notification and releases the location subscription within 2 s (PROPOSED) of the user action.
Rationale: GPS-PRIV-007 "stops within the same user action".
Source: Privacy line 86.
AC: with a fake location service, after stop the subscription count is 0 within 2 s of fake time; a device-lab check shows the system location indicator off.

### S04-R-003 (MUST) One location seam, no passive collection
Statement: All location access goes through one injectable location-service interface. No subscription exists before a recording starts, after it stops, after sign-out, or after device boot.
Rationale: GPS-PRIV-002, -035.
Source: Privacy lines 69, 142.
AC: unit/widget test with a fake service asserts zero subscriptions in those four moments; a lint or grep check fails the build if a location plugin API is imported outside that one file.

### S04-R-004 (MUST) Recorder state model
Statement: The recorder exposes exactly these states to the UI: idle, acquiring, recording, poor accuracy, offline, paused manual, paused auto, background, restoring after kill, recovery failed, battery critical, permission revoked, finished. Screens, copy and glance rules belong to S04-D; this requirement fixes only the set and the legal transitions. Definition of offline (Round 2): offline means only "the device reports no network while recording; recording continues unaffected" (S04-R-005: the recorder makes no network call, so network state is informational). The state is UNGROUNDED: no source requirement asks for a visible offline indication, and it is not shown by default (no chip, banner or announcement in S04 unless S04-D justifies it and the product-owner accepts it); it must never be worded as a problem or as data loss.
Rationale: the nine states named by S04-D (Roadmap line 88) are shared by EXPLORE and RIDE, so the model must be independent of either.
Source: Roadmap line 88.
AC: a transition-table test covers every pair of states and fails on any undefined transition; a state-name list test equals the list in the approved S04-D contract. Overlapping conditions (e.g. background and poor accuracy) are resolved by a priority order defined in S04-D (UNKNOWN until it exists).

### S04-R-005 (MUST) Works with no map service and no network
Statement: Recording, journaling, pause, stop, recovery and calculators make no network call and import no map package.
Rationale: roadmap states "recording works with no map service"; offline-first (`docs/phase2/plan/04_UI_UX_DIRECTION_2026-10-15.md` line 115).
Source: Roadmap line 89.
AC: a full record-to-save run in a test with all network adapters throwing succeeds; a dependency check shows no map package in the recorder's import graph; device-lab run in airplane mode with location on yields a saved track.

## 6. Requirements: sampling, accuracy, smoothing, auto-pause

### S04-R-006 (MUST) Sampling interval
Statement: The recorder requests one fix per second (PROPOSED, device-lab) while recording or auto-paused. Below the battery-critical threshold the interval follows S04-R-030.
Rationale: 1 Hz is enough for walk, run and cycle distance at the tolerances of S04-R-032..034; a higher rate is not allowed for diagnostics (GPS-PRIV-003). Exception: manual pause uses the reduced interval of S04-R-057.
Source: Privacy line 70 (rate decided in S04-D); Roadmap line 89.
AC: fake-clock test shows the request interval is 1 s; a replay of a 3600 s run yields 3600 requests, not more; device-lab: median interval between delivered fixes between 0.9 s and 1.5 s (PROPOSED).

### S04-R-007 (MUST) Stored fields (least data)
Statement: Each journaled sample holds: time offset in ms from recording start, latitude, longitude, horizontal accuracy in m, altitude in m if present, provider speed in m/s if present. Bearing, provider name, satellite count and device identifiers are not stored.
Rationale: minimum the calculators need; precision is not increased for diagnostics (GPS-PRIV-003). Fields must map onto the gps, altitude and speed streams of `ActivitySession` (the only kinds allowed in the cloud, S02 line 254).
Source: Privacy line 70; S02 lines 28, 254.
AC: schema test rejects any extra field in a journal record; mapping test converts a journal to an `ActivitySession` with offsets strictly increasing and passes `SampleStream.validate`.

### S04-R-008 (MUST) Accuracy gate
Statement: A fix is kept for the track only if horizontal accuracy is at most 30 m (PROPOSED) and the speed implied by the previous kept fix is at most 30 m/s (PROPOSED). Rejected fixes are not journaled; only their count is kept.
Rationale: 30 m removes urban-canyon and cold-start fixes; 30 m/s (108 km/h) is above downhill cycling and rejects teleport jumps.
Source: Roadmap line 89 ("accuracy gate"); thresholds are the gap Readiness G2.
AC: replay fixtures (S04-R-038) with injected 50 m fixes and a 2 km jump yield zero kept fixes from the injected ones; boundary test at accuracy 30.0 (kept) and 30.1 (rejected).

### S04-R-009 (MUST) Poor-accuracy state and gaps
Statement: If no fix passes the gate for 10 consecutive seconds (PROPOSED), state poor accuracy is entered and left on the next kept fix. The track gets a gap marker; distance is never interpolated across the gap.
Rationale: honest data; a tunnel must not invent distance.
Source: Roadmap line 88 (state list).
AC: replay of a 60 s tunnel fixture enters and leaves the state, adds 0 m during the gap, and marks one gap with start and end offsets.

### S04-R-010 (MUST) Raw is kept, smoothing is derived
Statement: The journal holds gate-passed fixes without smoothing. Smoothing is applied only when computing distance, pace and the derived track; changing the smoothing algorithm must not require re-recording.
Rationale: derived geometry is recomputable from raw (GPS-PRIV-017); `formulaVersion` is stored with the session (S02 line 99 area, A-5 fields).
Source: Privacy line 108; S02 line 99.
AC: re-running the calculators on a stored journal with a changed algorithm version changes the derived values and leaves the raw samples byte-identical; the session stores the formula version string.

### S04-R-011 (MUST) Smoothing quality
Statement: The smoothing step must reduce the length error of a noisy straight-line fixture to within 3 % (PROPOSED) of the true length, and must not move any kept point by more than 15 m (PROPOSED) from its raw position.
Rationale: smoothing that moves points too far distorts the route; too little leaves GPS zig-zag inflating distance.
Source: Roadmap line 89 ("smoothing").
AC: replay fixtures F-noise-line and F-turns (section 10): length within 3 % of truth; maximum displacement 15 m or less; a 90-degree corner fixture keeps its apex within 15 m.

### S04-R-012 (MUST) Auto-pause rule
Statement: With auto-pause on, the recorder enters paused auto when speed stays below 0.5 m/s for 8 s (PROPOSED) and resumes when speed is at least 1.0 m/s for 3 s (PROPOSED). While paused auto, location collection continues (it is needed to detect resume) and counts as collection for privacy purposes, but paused time and distance do not enter moving time or distance. Auto-pause default is on for exactly three sports in S04: walk, run and ride; the user can switch it off. Any other sport has auto-pause off and no S04 sport list may offer a fourth sport with auto-pause on. (S04-D must state the same three; Round1 UX18 found it naming four.)
Rationale: separate thresholds (hysteresis) prevent flapping at a traffic light; the 0.5/1.0 values sit under walking speed (about 1.4 m/s).
Source: Roadmap line 89; Privacy line 86 (paused-by-auto-pause is still active recording).
AC: replay fixture F-stop-go: exactly the expected number of pause/resume events, no event inside a 7 s stop, none flapping on 0.6-0.9 m/s jitter; moving time excludes paused time within 1 s; a settings test shows auto-pause default on for walk, run, ride and off for every other sport value, and the S04-D sport list contains no fourth sport with default on.

### S04-R-013 (MUST) Manual pause
Statement: The user can pause and resume manually; manual pause does not end the foreground service and does not release the location subscription (interval and prompt while paused: S04-R-057).
Rationale: avoids a service restart (and a permission re-check) on every pause; the state set requires paused manual (Roadmap line 88).
Source: Roadmap line 88.
AC: state-machine test: manual pause then auto rule triggers do not change state; resume returns to the prior moving state.

## 7. Requirements: journal, kill and recovery

### S04-R-014 (MUST) Sibling recording journal; hand-off through the S02 repository
Statement: Samples are not appended through the S02 writer. They are written in batches, one batch per flush (S04-R-015), to a sibling recording journal that lives in app-private storage in its own directory (`recording/`) and is distinct from the permanent S02 activity store (the S02 interface cannot take a per-second append). The recording journal keeps its own durable wiped-uid marker and does not rely on an in-memory wiped-uid flag (Round 2 Y3). The recording journal supports seal and hand-off: on finish it is sealed, and the finished `ActivitySession` is written into the owner's store only through the S02 repository (single mutex). The recorder package performs no direct file I/O outside the recording journal component. Every recording step (append, seal, hand-off `put`, recovery, delete) is pinned to the owner scope captured at the start of the recording and re-checks that this scope is still bound and not wiped; on a failed check it writes nothing and keeps the recording. The recording journal shares the wiped-uid tombstone and ordering with the S02 wipe: recorder shutdown, recording journal close and refuse-after-wipe, then the S02 wipe.
Rationale: avoids a second writer to the permanent store; GPS-PRIV-014 distinguishes the crash-safe recording journal from the permanent store; a late recorder write after sign-out or wipe must not resurrect another user's or a deleted user's data (Round1 X2).
Source: Round1 X2 and section 3 (ARCH 1, 3; SEC 1); S02 line 452 (hand-off side only); Privacy line 101. Journal format and hand-off mechanics are an architect decision (Readiness G3).
AC: (a) a test with a fake file system asserts that no recorder code outside the recording journal component calls a file I/O API; (b) two concurrent mutations (hand-off through the S02 repository and an unrelated session edit) both land and neither is lost, and a spy shows that no sample batch goes through the S02 writer; (c) fault injection: the scope is unbound or wiped between append, seal, hand-off `put`, recovery and delete in turn; in each case nothing is written to the store of the old or any other uid and the recording is kept; (d) wipe-ordering test: recorder shutdown precedes journal close, which precedes the S02 wipe, and a recorder write after the wipe is refused; (e) after a simulated relaunch (in-memory state lost) following a wipe, the durable marker still makes the journal refuse writes for the wiped uid.

### S04-R-015 (MUST) Flush interval and promise on kill
Statement: Samples are made durable at least every 5 s (PROPOSED) or every 10 samples, whichever is first. The promise to the user, and the only one, is: after the app process is killed or the phone restarts, everything recorded up to about 5 s (PROPOSED) before the kill is kept. No promise is made for storage full, a power cut that corrupts the file system, or the user force-stopping the app during the final flush.
Rationale: an honest bound is testable; "never loses data" is not.
Source: Roadmap line 89 and DoD ("survives app kill and screen off"); S03D line 346 (no recovery claim without the mechanism).
AC: kill test (fault injection at random offsets in a 600 s replay, 50 runs, PROPOSED): in every run the recovered track ends no more than 6 s before the injected kill; every recovered record is complete (a torn last record is dropped, not half-read); device-lab: `adb shell am kill` and swipe-away during recording.

### S04-R-016 (MUST) Recovery offer
Statement: On the next app start after a kill with a non-empty journal, the user is offered "Resume", "Save as finished" or "Discard", before any other recording can start; if location consent is withdrawn, Resume is refused (S04-R-054) and the other two stay. Resume continues the same activity with a gap marker; time between kill and resume is not moving time and not interpolated.
Rationale: GPS-PRIV-014 "a journal left by a crash is offered for recovery".
Source: Privacy line 101; Roadmap line 88 (restoring after kill).
AC: replay-and-restart test shows the offer, and each choice yields the expected stored result; the gap marker has offsets; discarding deletes the journal and leaves no sample on disk (file listing check).

### S04-R-017 (MUST) Recovery failed is honest
Statement: If the journal cannot be read (corrupt, unsupported schema, key loss), the recorder enters recovery failed, keeps the unreadable file untouched until the user chooses Keep (the file is quarantined untouched, and the strip and the Start block are cleared) or Delete (there is no Export in S04, Round1 X3), and never shows a track it could not verify. Copy never claims recovery succeeded.
Rationale: S03D R-S5 forbids a recovery claim without the mechanism; a partial claim is worse than none.
Source: Roadmap line 88; S03D line 346.
AC: corrupt-journal fixtures (truncated, bit-flipped, wrong schema) each yield recovery failed with no exception reaching the UI isolate and the original bytes unchanged until the user acts; after Keep the file is byte-identical, the strip is clear and Start is allowed; after Delete the file is gone; no Export control exists on this screen.

### S04-R-018 (MUST) Finish hand-off
Statement: On finish, the recorder produces one `ActivitySession` (summary, gps/altitude/speed streams, provenance "app GPS") through the S02 writer and only then deletes the recording journal. If the hand-off fails, the journal stays and recovery is offered again.
Rationale: no window in which neither copy exists.
Source: S02 line 452; Privacy line 101; S02 line 419 (consent row).
AC: fault injection between hand-off and delete leaves exactly one of: journal only, or both; never neither; the next start offers recovery or silently de-duplicates by activity id (architect chooses).

### S04-R-019 (MUST) Journal lifecycle
Statement: (a) The recording journal is deleted after a confirmed hand-off and on discard. (b) Only a confirmed different non-null uid, an explicit sign-out event or an account-deletion event stops a recording; a transient null or loading auth state stops nothing: the recorder keeps running, and appends refused while the scope is unbound go to a bounded in-memory buffer (120 s, PROPOSED) that is flushed after the same uid rebinds; past the bound the recording stops with the reason `account` and is kept. (c) On sign-out, account switch to a different uid or account deletion, a running recording is stopped, sealed and handed off into the owner's store BEFORE the owner scope unbinds, with the owner check of S04-R-014. Mechanism: the component that binds and unbinds the owner scope awaits a registered recorder pre-unbind hook, bounded to 5 s (PROPOSED), before it unbinds; the hook seals and hands off; the sign-out guard path uses the same hook; the journal is deleted after the confirmed hand-off. (d) If the hook times out or fails, or the hand-off is impossible, the unsealed recording stays in its own owner scope and is not shown to or readable by any other user, with an expiry of 30 days (PROPOSED), after which it is deleted with no sample left on disk. (e) Account deletion wipes the `recording/` directory after the recorder has been shut down. (f) The sign-out guard counts an active or unfinished recording as work that would be affected. If the guard cannot determine whether a recording exists, it says so in explicit text and "Sign out anyway" stays allowed (the user can always leave); sign-out is never blocked by an unknown state. (g) The journal is excluded from Android auto-backup and device-transfer (PROPOSED check of current manifest; current state UNKNOWN).
Rationale: GPS-PRIV-014; location history must not leave the phone through a backup, and must not be lost or leaked by a flaky auth state, a sign-out, or an account switch (Round1 X1).
Source: Round1 X1, X2 and section 3 (ARCH 2, SEC 1, SEC 2); Privacy line 101; `core/DECISION_LOG.md` line 57853 (Apple rule; the Android analogue is an INFERENCE).
AC: (a) hand-off test: journal gone after confirmed hand-off and after discard; (b) a fake auth stream emitting null, loading, then the same uid stops nothing, keeps the subscription, buffers appends (at most 120 s of fake time, PROPOSED) and flushes them after the rebind with none lost; a null longer than the bound stops the recording with the reason `account` and keeps it; a different non-null uid, an explicit sign-out and a deletion event each stop the recording; (c) sign-out during a recording: the unbind is not performed until the hook completes; the session appears in the owner's store before the scope unbinds, nothing appears in any other uid's store, then the journal is gone; (d) fault injection making the hook time out (5 s of fake time, PROPOSED) or the hand-off fail leaves an unsealed recording that no other uid can list or open and that is deleted at 30 days of fake time (PROPOSED); (e) account-deletion test: recorder shut down first, then `recording/` is empty and the key is not recreated; (f) the sign-out guard shows its warning when a recording is active or unfinished, and when it cannot determine this it shows the explicit "cannot check" text and still offers "Sign out anyway", which works; (g) a manifest/backup-rules check proves the journal path is excluded.

### S04-R-020 (SHOULD) Storage full
Statement: When free space is under 20 MB (PROPOSED) the recorder warns, and when a write fails it keeps recording in memory for up to 60 s (PROPOSED), then stops and saves what it has with a visible reason; this automatic stop posts the notification of S04-R-056.
Rationale: a silent write failure must not look like a normal run.
Source: gap analysis (Readiness G2); no existing rule (UNKNOWN).
AC: fake file system returning "disk full" produces the warning, then a stopped-with-reason session containing all samples up to the stop.

## 8. Requirements: permission flow and consent

Platform specifics (permission names, API-level behaviour) are UNVERIFIED until the platform study; the behaviours below are the contract.

### S04-R-021 (MUST) Foreground first, at the tap
Statement: Location permission is requested only at the first "Start" tap that needs it, after a one-line pre-prompt stating what is recorded, where it is stored and who can see it. No location prompt appears at launch, in onboarding, or before a location feature is chosen.
Rationale: GPS-PRIV-005, -006.
Source: Privacy lines 77, 84-85; `docs/phase2/plan/04_UI_UX_DIRECTION_2026-10-15.md` line 54.
AC: widget test: app launch, onboarding and tab switches request nothing (fake permission service call count 0); first Start shows the pre-prompt, then the system request.

### S04-R-022 (MUST) Background permission only if needed
Statement: S04 uses the foreground service and requests background location only if the platform study proves continuous recording needs it. Default assumption: it is not requested. If it is requested, only after foreground is granted and only at a Start tap. The manifest and store declarations list exactly the permissions the final design uses.
Rationale: GPS-PRIV-006, -011; the foreground service is preferred "wherever the platform allows it".
Source: Privacy lines 78, 90.
AC: a manifest check compares declared location permissions with the approved list; if background is not in the list, a test asserts no request for it exists in the code.

### S04-R-023 (MUST) Denial paths keep the app usable
Statement: If foreground permission is denied once: a neutral screen offers "Try again" and "Add manually". If permanently denied: the screen offers "Open settings" and "Add manually" and does not request again. The app never re-requests in a loop. If only approximate location is granted, recording is refused with an explanation (accuracy would fail S04-R-008).
Rationale: GPS-PRIV-008, UX direction (denial path fully working).
Source: Privacy lines 79, 87; `docs/phase2/plan/04_UI_UX_DIRECTION_2026-10-15.md` line 115.
AC: widget tests for each outcome (granted, denied once, denied permanently, approximate only); request count never exceeds 1 per tap; manual entry works in every outcome.
Note (Round1 X3): S04 has no Export anywhere. No denial, revocation or recovery-failed screen offers it; the only data actions in S04 are Keep and Delete (S04-R-017, -024).

### S04-R-024 (MUST) Revocation mid-recording
Statement: If the permission is revoked during recording (in system settings or from the notification), collection stops at once, the recording is sealed and handed off as a finished partial activity (the data up to the revocation is readable) marked "permission revoked", and the user is offered Keep or Delete. Keep leaves the finished partial activity in the owner's store and clears the strip and the Start block; Delete removes the recording. Quarantine (file untouched) applies only to recovery failed (S04-R-017), not here. There is no Export in S04 (Round1 X3). The app does not re-request. (Round 2 Y1.)
Rationale: GPS-PRIV-008.
Source: Privacy line 87; Roadmap line 88.
AC: fake permission service flips to denied mid-run: subscription count 0 within 2 s, session saved with the flag, exactly two choices (Keep, Delete) shown and no Export control, request count unchanged; after Keep the partial activity is readable in the store with its samples up to the revocation and the strip and Start block are clear; after Delete nothing of the recording remains; device-lab: revoke from system settings while recording.

### S04-R-025 (MUST) Notification permission
Statement: The recorder asks for the notification permission at the first Start (Android 13+), before starting the service. If it is denied, the app tells the user that the persistent notification will not show and recording continues only if the platform study confirms the foreground service still runs; otherwise recording is refused with a reason. UNKNOWN until the platform study.
Rationale: GPS-PRIV-007 requires a visible notification; behaviour with denial is not verified.
Source: Privacy line 86; Readiness G4; manifest already declares POST_NOTIFICATIONS (Privacy line 30).
AC: widget tests for granted and denied; the chosen outcome is recorded in the platform study; device-lab run on Android 13 or later.

### S04-R-026 (MUST) Two consent rows
Statement: S04 stores a consent record for "location while recording" and "background location" (the second only if S04-R-022 uses it), each with purpose, timestamp, text version and current state. The withdrawal surface and the effect of withdrawal on Start, Resume and a running recording are defined in S04-R-054.
Rationale: GPS-PRIV-009; scoped by assumed default A-3.
Source: Privacy line 88; S02 line 419; Round1 X4.
AC: grant writes one record with the four fields; the withdrawal behaviour is tested under S04-R-054.

### S04-R-027 (SHOULD) Pre-prompt wording marked draft
Statement: The pre-prompt and the saved-on-device notice are held in localisation files marked DRAFT with a text version; changing the text increments the version.
Rationale: approver is undecided (assumed default A-7); text version is needed by S04-R-026.
Source: Privacy lines 89, 88.
AC: a test reads the text version from the consent record and from the string file and finds them equal.

## 9. Requirements: battery

### S04-R-028 (MUST) Battery protocol
Statement: A written protocol defines the measurement: reference phone and Android version recorded; 60 min walk and 60 min ride (PROPOSED durations); screen off, device in pocket or mounted, auto-brightness; start and end battery percent read from the system (not estimated); no other app foreground; result recorded as percent per hour; one run on charger-free battery; each run states temperature if known and network state.
Rationale: DoD says "battery recorded on the operator's phone" (Roadmap line 89); G5 says it is undefined.
Source: Roadmap line 89; Readiness G5.
AC: a protocol document exists before the first device-lab run and each run record has all listed fields; a run missing a field is not accepted as evidence.

### S04-R-029 (SHOULD) Drain target
Statement: Foreground-service recording with the screen off drains at most 8 % per hour (PROPOSED, device-lab) on the reference phone. A run above the target is recorded as a FAIL against the target, not hidden; the product-owner then decides to accept, tune or defer.
Rationale: a target is needed to know when to act; the number is a placeholder until the phone is known (A-2).
Source: Readiness G5.
AC: protocol record shows measured value versus 8 %; status is PASS, FAIL or NOT_RUN.

### S04-R-030 (MUST) Battery critical behaviour
Statement: At or below 10 % battery and not charging (PROPOSED), state battery critical is entered: a non-modal banner appears, the sampling interval changes to 5 s (PROPOSED), and the flush interval changes to 1 s (PROPOSED). At or below 3 % (PROPOSED) the recorder finishes and saves the activity with a visible reason and stops. The recorder never stops silently and never shows a blocking dialog while recording; the automatic stop posts the notification of S04-R-056.
Rationale: preserves the track when the phone is about to die; UX direction forbids modals while recording.
Source: Roadmap line 88 (battery critical); `docs/phase2/plan/04_UI_UX_DIRECTION_2026-10-15.md` lines 76-82 (battery guard).
AC: fake battery source at 10, 9, 3 and 2 %: state, interval, flush and auto-finish match; charging at 8 % does not enter the state; a recorded session contains a visible "stopped: battery" reason.

### S04-R-031 (SHOULD) OEM background-kill evidence
Statement: The device-lab record states whether the phone's battery-optimisation or vendor task killer ended a screen-off recording, and what the user must set. The app does not request exemption from battery optimisation without an approved design (Play policy risk, UNVERIFIED).
Rationale: kill survival differs by vendor; the honest promise (S04-R-015) must not exceed what was measured.
Source: Roadmap line 89 DoD.
AC: the record has a yes/no entry per run and the settings used.

## 10. Requirements: calculators and replay tests

### S04-R-032 (MUST) Distance
Statement: Distance is the sum of great-circle segments between consecutive smoothed kept fixes, excluding paused auto/manual time and gap segments.
Rationale: defined, reproducible metric; `distanceM` bound 0..10^7 (S02 line 78).
Source: Roadmap line 89; S02 line 78.
AC: synthetic fixtures with known length: error at most 0.5 % or 5 m, whichever is larger (PROPOSED); real-shaped fixture with surveyed length: error at most 2 % (PROPOSED).

### S04-R-033 (MUST) Pace and speed
Statement: Current pace uses a trailing window of 10 s (PROPOSED) of moving time; average pace uses moving time, not elapsed time. Pace is undefined (not zero, not infinite) when moving distance is under 10 m (PROPOSED).
Rationale: unwindowed per-fix pace is unreadable; undefined must be explicit.
Source: Roadmap line 89.
AC: constant-speed fixtures: pace within 3 s/km (PROPOSED) after the window fills; a stopped fixture returns undefined; moving time equals elapsed minus paused within 1 s.

### S04-R-034 (MUST) Elevation gain and loss
Statement: Ascent and descent use altitude with a hysteresis of 3 m (PROPOSED): a change counts only after altitude moves 3 m from the last counted extreme. Barometer data is not used in S04 (whether to use it is an open question). Missing altitude yields ascent undefined, not 0.
Rationale: raw GPS altitude noise inflates ascent.
Source: Roadmap line 89; `ascentM` bounds S02 line 78.
AC: flat noisy fixture (plus or minus 4 m noise): ascent at most 5 m; a staircase fixture of 100 m known gain: within 10 % or 5 m (PROPOSED); no-altitude fixture gives undefined.

### S04-R-035 (MUST) Replay test suite
Statement: Calculators and the gate are tested by replaying stored fixtures through the same code path the recorder uses, with a fake clock. Fixtures cover: F-noise-line, F-turns, F-stop-go, F-tunnel (60 s no fix), F-urban-canyon (accuracy spikes), F-jump (2 km teleport), F-climb, F-ride-30kmh, F-walk, F-kill-mid-run (journal truncated at offsets). Output for a fixed input is bit-identical across runs and platforms.
Rationale: P2-009 requires replay tests; determinism makes tolerances falsifiable.
Source: Roadmap line 89; Readiness G8.
AC: each fixture has a stored expected-result file; a run twice yields equal files; breaking a gate threshold in the code makes at least one fixture test fail (by assertion design, no mutation run).

### S04-R-036 (MUST) Session summary
Statement: At finish, the recorder fills `ActivitySession.summary` with distance, moving time, elapsed time, ascent, descent, average speed, and `formulaVersion` and `metricDefinitionVersion`, all within the S02 bounds.
Rationale: summary scalars are the part allowed to leave the device later.
Source: S02 lines 78, 99.
AC: a produced summary passes the S02 validator; a value outside the bounds is clamped by rejection (session flagged), not written.

## 11. Requirements: shell integration, performance, privacy, platform, evidence

### S04-R-037 (MUST) Strip shows a GPS recording; sources are independent
Statement: While a recording is active the S03 recording strip shows it on all tabs, including when a gym set or rest timer is also running. Each source has its own owner and user id. Acceptance: (a) with a fake second source the strip shows it; (b) an account switch hides it; (c) ending one source does not clear the other's owner. Whether this is done by a prioritised list of sources or by rewriting `activeSessionStatusProvider` is an architect decision recorded in the S04 plan (Readiness line 113); this requirement fixes the behaviour only.
Rationale: the present derivation reads only gym timers, writes one owner slot, and hard-codes that the set timer wins; a recorder that survives process death does not fit it.
Source: Readiness lines 112-113; S03D lines 327-334.
AC: provider tests for (a), (b), (c) with fakes; strip widget tests unchanged apart from the new source.

### S04-R-038 (MUST) Which source wins the strip
Statement: When a gym timer and a GPS recording are both active, the strip shows the GPS recording (PROPOSED) and the gym timer remains reachable from the workout page. A GPS recording is never hidden by the other source.
Rationale: location is being collected; the user must always see that. The existing rule "set timer wins" (S03D line 334) is for gym sources only.
Source: S03D line 334; Privacy line 69.
AC: provider test with both fakes active shows the GPS source; ending the GPS recording shows the gym timer.

### S04-R-039 (MUST) Recovery claim only for GPS
Statement: The strip and the app say "recovered" only after a verified GPS journal recovery. Copy for gym timers still makes no recovery claim (S03D R-S5 stays true for them).
Rationale: keeps S03D R-S5 correct.
Source: S03D line 346.
AC: copy test: the recovery string is reachable only from the recovery-succeeded path; no gym path references it.

### S04-R-040 (MUST) Minimal start and stop surface
Statement: S04 ships the smallest surface needed to start, pause, resume, stop and recover a recording, built exactly as the approved S04-D contract says, without map. It does not implement EXPLORE or RIDE journeys.
Rationale: needed for the device-lab DoD; "S04 builds only this" (Roadmap line 88).
Source: Roadmap lines 88-89; S03D (Explore and Ride "coming later").
AC: every screen in the S04 build maps to a screen in the S04-D contract; a screen without a mapping fails review. No new top-level shell paths or sheet flags are copied (Readiness line 114).

### S04-R-041 (MUST) Heavy work off the UI isolate
Statement: Payload build, gzip, SHA-256, journal seal/open, smoothing and calculators over a full session run off the UI isolate. Live metrics during recording are updated incrementally and never reprocess the full session on the UI isolate.
Rationale: carried-over S02 gate; avoids dropped frames.
Source: `docs/phase2/s02/S02_RELEASE_NOTES.md` line 104; Readiness G10.
AC: a test that spies on isolate use asserts these functions are not called on the main isolate; see S04-R-042.

### S04-R-042 (MUST) 100k-sample frame budget
Statement: With a 100 000-sample session (about 28 h at 1 Hz, within the 200 000 bound of S02 line 256), opening, sealing, finishing and displaying summary produce no frame longer than 16 ms (PROPOSED) on the UI isolate in a profile-mode test; seal plus open completes in at most 3 s (PROPOSED, device-lab) and peak extra memory stays under 100 MB (PROPOSED).
Rationale: gate required before a recorder ships.
Source: Readiness G10; S02 line 256.
AC: a frame-timing test with a 100k fixture reports the maximum frame build time and fails above the limit; the reference-phone value is recorded or NOT_RUN.

### S04-R-043 (SHOULD) Bounded live memory
Statement: During recording the app keeps at most the last 600 samples (PROPOSED) in memory for live display; everything else is in the journal.
Rationale: a long ride must not grow memory without limit.
Source: S02 line 256.
AC: a 100k-sample replay shows the in-memory list never exceeds 600 entries.

### S04-R-044 (MUST) No coordinates in logs or telemetry
Statement: Logs, metrics, crash reports, error strings and debug telemetry never contain coordinates, geohashes, geometry, place names or heart-rate values. Allowed: counts, durations, sample counts, byte sizes, activity ids, permission state, state names, error codes.
Rationale: GPS-PRIV-048, -049, -050, -068.
Source: Privacy lines 176-178, 253.
AC: a log-capture test runs record, pause, kill-recover, finish and fail flows with sentinel coordinates (e.g. 12.3456789) and asserts no captured line, exception message or telemetry event contains them; exceptions are mapped to bare codes first.

### S04-R-045 (MUST) Owner-only on the device
Statement: Recording journal and finished sessions are readable only by the app (app-private storage), shown only to the signed-in owner, and hidden on account switch.
Rationale: GPS-PRIV-012 (raw samples owner-only).
Source: Privacy line 99.
AC: account-switch test hides the journal and any recovery offer of another user; file-location test confirms app-private storage.

### S04-R-046 (MUST) Upload stays off
Statement: No code path uploads samples, derived geometry or the stream object in S04; the cloud-stream flag is OFF and a test asserts the upload entry point is unreachable from the recorder. Heart rate is never recorded in S04.
Rationale: GPS-PRIV-013 until retention is finalised; assumed default A-6.
Source: Privacy line 100; `docs/phase2/s02/S02_RELEASE_NOTES.md` lines 104, 111.
AC: with the flag off, a full run issues zero network calls (same check as S04-R-005); the flag default constant is false.

### S04-R-047 (SHOULD) Saved-on-device notice
Statement: The finish screen states that the track stays on this phone and is not shared.
Rationale: honest copy while upload is off.
Source: Privacy lines 85, 100.
AC: the string exists, is shown on finish, and is removed only by the sprint that enables upload.

### S04-R-048 (SHOULD) Default privacy-zone radius constant
Statement: A constant default privacy-zone radius of 200 m (PROPOSED) and a setting key are defined; S04 applies it to nothing because S04 shares nothing.
Rationale (PROPOSED number): a typical home block plus neighbouring gardens is about 100-150 m across, and the accuracy gate allows 30 m error, so a 200 m radius leaves a margin over both; Privacy line 166 forbids fixing the number without a design decision, so it stays PROPOSED until the operator or S04-D accepts it.
Source: Privacy lines 165-166 (GPS-PRIV-045, -046); owner of the editor is S10-D (A-4).
AC: constant and key exist with a test; no code applies it in S04.

### S04-R-049 (SHOULD) Default expiry constant
Statement: A default GPS expiry constant of 24 months counted from the activity date (PROPOSED) is defined as a setting default; S04 enforces nothing.
Rationale: Privacy line 232 proposes 2 years and the activity-date clock.
Source: Privacy lines 207, 232.
AC: constant exists; no scheduler or deletion rule is introduced in S04.

### S04-R-050 (MUST) Android only; no iOS claim
Statement: S04 builds, tests and states results for Android only. No document, store text or test report claims iOS support; iOS rows read NOT_RUN. The declared manifest permissions equal the permissions used.
Rationale: Roadmap D-12 default; GPS-PRIV-011.
Source: Roadmap lines 257, 268; Privacy line 90.
AC: a grep of release notes and tests finds no iOS pass claim; manifest-versus-approved-list check passes.

### S04-R-051 (MUST) Device-lab evidence record
Statement: The DoD is closed only by a record on the reference phone stating: device and OS, build id/head, kill survival result (S04-R-015), screen-off continuity (S04-R-001), tolerance results (S04-R-032..034) from a walked and a ridden known route, battery run (S04-R-028..029), OEM kill result (S04-R-031), each as PASS, FAIL or NOT_RUN. Missing evidence is NOT_RUN, never PASS.
Rationale: DoD text; honest status.
Source: Roadmap lines 89, 171.
AC: the record exists with all items filled (including the engine-detach device test of S04-R-058); reviewers can see the head it proves.

### S04-R-052 (MUST) Sanitising wrapper and global error handlers
Statement: Location content (coordinates, geohashes, geometry, journal bytes, place names) never reaches the process-wide error paths, not only recorder code. (a) A sanitising wrapper converts every error raised at journal decode, at worker entry and at the isolate boundary into a content-free error type (a bare code plus allowed fields of S04-R-044) before it leaves that point. (b) The global handlers (`recordFlutterFatalError`, `recordError`, the zone handler) and the debug `debugPrint` telemetry sink receive only such content-free types; a raw exception object or message from a location code path is never passed to them. Entry condition (Round 2 Y6): the server-side enforcement of GPS-PRIV-050 and GPS-PRIV-098 is a precondition to start building the recorder lane (R3 onwards), unless the operator records a dated exception; it is also a release gate. Whether that enforcement is in place today is UNKNOWN (owner in section 14).
Rationale: S04-R-044 covers only recorder code, but the app-wide handlers and Crashlytics take raw errors, so a decode exception carrying a sentinel coordinate would leave the phone (Round1 SEC4).
Source: Round1 section 3 (SEC4); Privacy lines 176-178, 253 (GPS-PRIV-048..050, -068); GPS-PRIV-098 (cited by Round1; Privacy line not re-read here).
AC: (a) a sentinel test (coordinate such as 12.3456789 inside a corrupt journal record, a worker exception and an isolate-boundary error) passes the error through the zone handler, `recordFlutterFatalError`, `recordError` and the `debugPrint` sink, and a Crashlytics spy sees no sentinel in message, stack text or custom keys; (b) a type test shows the wrapper outputs only content-free error types; (c) a static check fails the build if a location code path rethrows a raw error outside the wrapper; (d) the entry-condition evidence (server enforcement of GPS-PRIV-050 and -098) is recorded with the head it proves before the first recorder-lane (R3 onwards) commit starts, or a dated operator exception is recorded; and the same evidence is re-checked at release; otherwise NOT_RUN and the sprint cannot be accepted.
Priority: MUST.

### S04-R-053 (MUST) Lock-screen notification privacy and actions
Statement: The recording notification has lock-screen visibility private, with a generic public version. The owner-visible version (unlocked shade) shows sport, moving time and distance and nothing else; the lock-screen public version is generic only (no sport, time, distance, coordinates or pace); neither version contains coordinates or pace. The owner-visible version offers exactly two actions: Pause/Resume, and "Finish..." which opens the stop panel in the app and does not stop the recording by itself. The public version has no actions. A plain tap on the notification opens the recording screen with focus on the headline; the "Finish..." action opens the stop panel with focus on its header (Round 2 Y11). A notification also exists for the acquiring state with its own title (S04-D defines the text). UNVERIFIED pending the platform study: how the OS honours the private/public split on each Android version and vendor.
Rationale: a shoulder-surfer or a notification-listener must not learn what or where the user is recording, and an accidental tap on a locked phone must not end a recording (Round1 X6).
Source: Round1 X6 (SEC 6, UX 2, A11Y M5, M6); Privacy line 86 (GPS-PRIV-007).
AC: (a) a notification-builder test inspects both versions and finds no digit pattern of the sentinel coordinate and no pace string in either version, and no sport name, time or distance in the public version, while the owner-visible version shows exactly sport, moving time and distance; (b) the public version has zero actions, the owner-visible version has exactly the two named actions; (c) the "Finish..." action leaves the recorder in its prior state until the user confirms in the stop panel; (d) a widget test shows that a plain tap puts focus on the recording screen headline and the "Finish..." action puts focus on the stop panel header, each without a duplicate announcement; (e) device-lab: lock-screen photo/screen record on the reference phone with lock-screen notifications set to "show all" and to "hide sensitive".
Priority: MUST.

### S04-R-054 (MUST) Consent withdrawal surface and effect
Statement: Settings, Privacy has a row for location with one withdraw switch (plus the second row for background location only if S04-R-022 uses it, per S04-R-026) and links to delete the affected recorded data (no export link, Round1 X3). Effect of withdrawal: (a) Start is blocked with a visible reason and a way to grant consent again; (b) Resume of an unfinished recording is refused, while Save as finished and Discard remain available (S04-R-016); (c) withdrawing during a running recording stops it, seals it and keeps it (hand-off as in S04-R-018), and posts the notification of S04-R-056; (d) withdrawal itself deletes no data. Granting again restores Start.
Rationale: GPS-PRIV-009 requires withdrawal to be as easy as granting; without a surface the S04-R-026 consent rows could not be withdrawn (Round1 X4, UX 11, SEC 5).
Source: Round1 X4; Privacy line 88 (GPS-PRIV-009); scoped by A-3.
AC: widget and state tests: (a) switch off then Start shows the blocked reason and requests nothing; (b) with an unfinished journal and consent withdrawn, Resume is absent or disabled with a reason, and Save as finished and Discard work; (c) withdraw during a fake recording: subscription count 0 within 2 s, session kept and handed off, the stop notification posted; (d) file listing before and after withdrawal is identical except for the stopped recording; consent record shows new state and timestamp; (e) the delete link opens the delete flow and no Export control exists on the screen.
Priority: MUST.

### S04-R-055 (MUST) Start preconditions
Statement: Start is enabled only when (a) the recording journal is open and (b) the check for an unfinished recording has completed. While either is pending the user sees a visible "preparing" panel; if either fails or does not complete within 5 s (PROPOSED) the user sees a visible "cannot start" panel with a reason and a retry; no location subscription is created in those cases. One timeout per transition (Round 2 Y5): `preparing` to `cannotStart` after 5 s (PROPOSED); after the service-start call, if the recorder has not reached acquiring, a visible "start failed" panel appears 15 s (PROPOSED) counted from that call, and the start is cancelled with the subscription released.
Rationale: starting before the unfinished check could open a second recording over the one that needs recovery (S04-R-016 "before any other recording can start") or write into a journal that is not open (Round1 X7, ARCH 8).
Source: Round1 X7; Privacy line 101 (GPS-PRIV-014).
AC: with a fake journal whose open is delayed, a Start tap starts nothing and shows "preparing"; with a fake unfinished check that never completes, "cannot start" appears at 5 s of fake time (PROPOSED) with retry; subscription count is 0 in both; with both complete, Start works; with an unfinished recording found, the recovery offer appears instead of a new recording; with a fake service that never reaches acquiring, "start failed" appears at 15 s of fake time counted from the start call (not from the tap) and the subscription count returns to 0.
Priority: MUST.

### S04-R-056 (MUST) Automatic-stop notification
Statement: Exactly these automatic stops post the notification described here (Round 2 Y10): battery auto-finish of S04-R-030, storage stop of S04-R-020, the sample-cap stop (the S02 bound of 200 000 samples per stream is reached) and the consent-withdrawal stop of S04-R-054(c). The permission-revoked stop (S04-R-024) is not in this set; it keeps its own normal notification of the same family with existing copy. Each of the four posts a separate, non-ongoing notification that states the reason, the saved time and the saved distance. It is posted even when the screen is off and the app is in the background, and it is a different notification from the persistent recording notification, which is removed at the stop (S04-R-002). No coordinates, pace or sport name appear in it (same rule as S04-R-053).
Rationale: with the screen off a stop is otherwise invisible, and the user may believe the recording is still running (Round1 X6, UX 2, A11Y M5).
Source: Round1 X6; Roadmap line 88 (battery critical).
AC: fake battery at 3 %, fake disk full, a fake session reaching the sample cap and fake consent withdrawal each produce one non-ongoing notification with reason, time and distance and without content listed above; the persistent notification is gone; the saved session contains the same reason; device-lab: screen-off run auto-finished at the battery threshold shows the notification on the lock screen. A permission-revoked stop produces its own normal notification and not this one.
Priority: MUST.

### S04-R-057 (MUST) Manual pause interval and prompt
Statement: During manual pause the location subscription stays open at a reduced interval of 10 s (PROPOSED), the pause screen and the pause hint say that location stays on, and after 30 minutes (PROPOSED) of continuous manual pause a non-modal prompt offers Resume or Finish...; the prompt never stops or discards the recording by itself. Sampling during manual pause is not journaled as track and adds nothing to distance or moving time.
Rationale: a forgotten pause must not become hours of silent location collection (Round1 X5, SEC 7), while keeping the subscription avoids a restart and permission re-check (S04-R-013).
Source: Round1 X5; Privacy line 86; Roadmap line 88 (paused manual).
AC: fake clock: a request interval of 10 s during manual pause and 1 s after resume; at 30 min of fake time exactly one prompt appears and the state is still paused manual; the hint string states that location stays on; distance and moving time are unchanged across the pause; a prompt never appears for auto-pause.
Priority: MUST. Both numbers are PROPOSED and device-lab where noted.

### S04-R-058 (MUST) Engine-detach behaviour
Statement: The persistent notification must not claim "Recording" when the recorder is no longer running. When the Flutter engine detaches (Activity destroyed, swipe-away) and the recorder cannot continue, one of two outcomes occurs: the foreground service keeps recording and still shows "Recording" truthfully, or the service stops and the notification is removed or changed to a non-Recording text (for example "Recording stopped") with the saved time. The choice depends on the device test T2 of Design (Round1 ARCH6); until T2 has run, only the second outcome is allowed, and a claim of "Recording" while the recorder is dead is a FAIL.
Rationale: S03D R-S5 and the honesty rule of S04-R-017: a false "Recording" would make the user rely on a track that is not being collected (Round1 ARCH6).
Source: Round1 section 3 (ARCH6); S03D line 346. Behaviour of `geolocator` after Activity destroy, swipe-away and force-stop is carried as NOT_RUN (Round1 last section).
AC: device-lab T2 on the reference phone: start recording, swipe the app away, wait 60 s; the record states whether new samples are still being journaled and what the notification shows; PASS only if the notification claim equals the true recorder state; a fake-engine-detach test asserts that the notification text changes from Recording to the stopped text when the recorder reports dead.
Priority: MUST.

## 12. Minors, release gate and accepted risks

Minors statement (Round1 SEC9). S04 treats recordings of users under 18 the same as all others and in addition: a recording is private only; no sharing control, no publishing and no upload exists for any user in S04 (this follows S04-R-046 and holds regardless of age); no minor-specific data is collected. Whether product rules for minors (age gate, guardian consent) apply is UNKNOWN and listed in section 14, question 14. Test: the S04 build contains no share, publish or upload entry point reachable from a recording (same check as S04-R-046).

Release-gate row (Round1 SEC9). Before the S04 release the following are done, each with a named owner and the head or artifact it proves; an item without an owner is open: (1) privacy policy text covering GPS recording on the device; (2) Google Play data-safety form entries; (3) Google Play foreground-service declaration; (4) in-app disclosure text for the location purpose. Owners: UNKNOWN, section 14 question 15. Status per item: PASS, FAIL or NOT_RUN. Platform and store requirements for these are UNVERIFIED until the platform study.

Accepted risks (Round1 SEC9). The following are known, not mitigated in S04, and accepted unless the operator decides otherwise:
1. On a rooted phone or a debuggable build, the encryption key and the process memory can be read, so recorded locations can be read.
2. A second app holding location permission receives the same fixes from the OS; S04 cannot prevent it.
3. Notification-listener apps can read notification content that the OS exposes (limited by S04-R-053, not eliminated).
4. File sizes and modification times of the journal reveal the approximate duration of a recording.
5. Journal frames have integrity protection but no binding to additional authenticated data (no AAD), so a frame cannot be proven to belong to a specific recording or position by the key alone.
6. The restart promise of S04-R-015 covers a process kill and an orderly restart only; power loss and file-system corruption are excluded (Round1 ARCH12).
7. The privacy-zone default (S04-R-048) is a constant that S04 applies to nothing; the copy must say it applies when sharing and is not applied in this version (Round1 SEC8).

## 13. Traceability

| Requirement | Roadmap / privacy / readiness source | Gap or decision |
|---|---|---|
| S04-R-001, -002 | Roadmap line 89 (foreground-service recorder); GPS-PRIV-007 | G4 |
| S04-R-003 | GPS-PRIV-002, -035 | none |
| S04-R-004 | Roadmap line 88 (state list) | G1 |
| S04-R-005 | Roadmap line 89 (no map service) | none |
| S04-R-006, -007 | GPS-PRIV-003; Roadmap line 89 | G2 |
| S04-R-008, -009 | Roadmap line 89 (accuracy gate); line 88 (poor accuracy) | G2 |
| S04-R-010, -011 | Roadmap line 89 (smoothing); GPS-PRIV-017 | G2 |
| S04-R-012, -013 | Roadmap line 89 (auto-pause); line 88 (paused manual/auto) | G2 |
| S04-R-014..019 | Roadmap line 89 (journaled, crash-safe); GPS-PRIV-014 | G3 |
| S04-R-020 | none in sources | G2 (new) |
| S04-R-021..025 | Roadmap line 89 (permission flow); GPS-PRIV-005..008, -011 | G4, G7, A-1 |
| S04-R-026, -027 | GPS-PRIV-009, -010 | G7, G11, A-3, A-7 |
| S04-R-028..031 | Roadmap line 89 (battery protocol), DoD | G5, A-2 |
| S04-R-032..036 | Roadmap line 89 (calculators, replay, P2-009) | G2, G8 |
| S04-R-037..039 | Readiness addendum; S03D lines 327-346 | G9 |
| S04-R-040 | Roadmap line 88 ("S04 builds only this") | G1, A-8 |
| S04-R-041..043 | S02 release notes line 104 | G10 |
| S04-R-044, -045 | GPS-PRIV-012, -048..050, -068 | none |
| S04-R-046, -047 | GPS-PRIV-013 | A-6 |
| S04-R-048, -049 | GPS-PRIV-045, -046; Privacy line 232 | G6, A-4, A-5 |
| S04-R-050 | Roadmap D-12 (line 257); GPS-PRIV-011 | G12, A-1 |
| S04-R-051 | Roadmap DoD (line 89), line 171 | A-2 |
| S04-R-014 (revised), -019 (revised) | Round1 X1, X2; ARCH 1, 2, 3; SEC 1, 2; GPS-PRIV-014 | G3, X1, X2 |
| S04-R-012 (sports), -013 | Round1 UX18 | question 9 |
| S04-R-017, -023 note, -024 (Export removed) | Round1 X3; UX 4, 12; SEC 3 | X3 |
| S04-R-052 | Round1 SEC4; GPS-PRIV-048..050, -068, -098 | entry condition, question 11 |
| S04-R-053 | Round1 X6; SEC 6; UX 2; A11Y M5, M6; GPS-PRIV-007 | G4, X6 |
| S04-R-054 (also -026, -016) | Round1 X4; SEC 5; UX 11; GPS-PRIV-009 | A-3, X4 |
| S04-R-055 | Round1 X7; ARCH 8 | X7 |
| S04-R-056 (also -020, -030) | Round1 X6; UX 2; A11Y M5 | X6, question 12 |
| S04-R-057 (also -006, -013) | Round1 X5; SEC 7 | X5, question 13 |
| S04-R-058 | Round1 ARCH6; S03D line 346 | T2 device test, question 13 |
| Section 12 (minors, release gate, accepted risks) | Round1 SEC9, ARCH12, SEC8 | questions 14, 15 |
| S04-R-014 (round 2), -019 (round 2) | Round1 section 3: Y2, Y3, Y5; K2, K3, K5 | pre-unbind hook, transient-null buffer, cannot-check path |
| S04-R-024 (round 2), -017 | Round1 section 3: Y1; K1 | Keep = finished partial activity; quarantine only for recovery failed |
| S04-R-052 (round 2) | Round1 section 3: Y6; K6 | entry condition, question 11 |
| S04-R-053 (round 2) | Round1 section 3: Y11; C2 | notification content and tap focus |
| S04-R-055 (round 2) | Round1 section 3: Y5; K5; C4 | 5 s and 15 s timeouts |
| S04-R-056 (round 2) | Round1 section 3: Y10; K10; C5 | auto-stop set of four, question 12 |
| S04-R-004 (round 2) | Round1 section 3 (stale wording: offline) | offline UNGROUNDED, not shown by default |
| Decisions X8, X9, X10 | Round1 section 1 | no requirement here: X8 (manifest flag-gating) is a design matter and X9 and X10 are S04-D matters; S04-R-022 and -050 already require the manifest to equal the approved list |

Duplication check: acceptance for "no network" appears in -005 and -046 deliberately (different reasons: map independence versus upload off); the same test may serve both. Untestable items: none; items depending on unverified platform facts (-001, -022, -025) carry an acceptance that records the platform study outcome.

## 14. Open questions for the operator (in words, with options and consequences)

1. Strip priority when a gym timer and a GPS recording run together (S04-R-038). Option A (assumed): the recording is shown, because location is being collected and must stay visible; the gym timer stays reachable in the workout page. Option B: the gym timer stays on top as in the current rule; a person could forget an active recording. Option C: show both (needs a taller dock; changes the S03 layout). Owner: operator with product-owner.
2. Which sensors for elevation (S04-R-034). Option A (assumed): GPS altitude only with the 3 m hysteresis; simple, less accurate on hills. Option B: use the phone barometer when present; better ascent, more code and one more fact to test per device. Owner: product-owner.
3. Behaviour when the notification permission is denied (S04-R-025). Option A: refuse recording with a reason (safe, may annoy). Option B: record without the notification if the platform allows it (convenient, weaker visibility of collection). Final choice depends on the platform study. Owner: operator after the study.
4. Is it acceptable to ask the user to exempt the app from battery optimisation (S04-R-031)? Option A (assumed): no request, only explain in the device-lab record what to set. Option B: in-app request; may improve survival on some phones but risks store policy trouble (UNVERIFIED). Owner: operator.
5. Battery-critical rule (S04-R-030). Option A (assumed): slow down at 10 %, auto-finish at 3 %. Option B: only warn, never stop; the track may be lost if the phone dies, but the user keeps control. Owner: operator.
6. How long a recording may stay unfinished in the journal before recovery is no longer offered. The sources give no value. Option A: offered always until the user chooses (journal stays, costs storage). Option B: expire after N days (PROPOSED 30), then delete with a notice. Owner: operator.
7. Recovery with a long gap (S04-R-016). Option A (assumed): resume with a gap marker whatever the gap. Option B: if the gap exceeds a limit (PROPOSED 30 min), only offer save-as-finished. Owner: product-owner.
8. The eight items A-1..A-8 in section 3 remain open decisions; each default is used until answered.
9. Auto-pause sports (S04-R-012). Option A (assumed): on by default for three sports, walk, run and ride; the S04-D list that names four must drop to three. Option B: four sports; then S04-R-012 and the replay fixtures grow by one sport and its thresholds. Owner: product-owner.
10. Unsealed recording that cannot be handed off at sign-out (S04-R-019(d)). Option A (assumed): kept in its own owner scope for 30 days (PROPOSED), then deleted; the owner can still recover it on sign-in. Option B: delete at sign-out; nothing leaks, but a flaky hand-off loses a track. Owner: operator.
11. Entry condition of S04-R-052: is the server-side enforcement of GPS-PRIV-050 and GPS-PRIV-098 already in place? UNKNOWN. Option A (assumed, Round 2 Y6): building the recorder lane (R3 onwards) waits until it is (safe, delays S04), and it is also checked at release. Option B: the operator records a dated exception and the lane is built behind the flag, which stays off until enforcement exists. Owner: operator with the server owner.
12. Which stops post the separate automatic-stop notification (S04-R-056). Option A (assumed, Round 2 Y10): battery, storage, sample cap and consent withdrawal; permission revoked keeps its own normal notification. Option B: also fold permission revoked into the same notification. Owner: product-owner.
13. Numbers and choice for pause and detach (S04-R-057, -058): manual-pause interval 10 s and prompt at 30 min are PROPOSED; the service-keeps-recording versus service-stops outcome waits for device test T2 (until then the safe outcome applies). Owner: operator after T2.
14. Minors (section 12). Option A (assumed): private only, no sharing, no upload, no extra age rule in S04. Option B: add an age rule or guardian consent now; adds a requirement set and a text approval. Owner: operator.
15. Owners of the release-gate row items (privacy policy, data-safety form, foreground-service declaration, disclosure text). UNKNOWN; without owners the release cannot be accepted. Owner: operator.
16. Round1 decisions X1..X10 are defaults the operator may override; X1..X7 are written into this file, X8..X10 are carried by the design and contract authors.

Unresolved UNKNOWN items blocking the next phase (S04 design): the platform study (Android foreground-service type, notification behaviour); the reference phone; the S04-D contract (state priority order, copy); the content of P2-009; whether server enforcement of GPS-PRIV-050 and -098 is in place (question 11, entry condition of S04-R-052); the owners of the release-gate row (question 15).

## 15. Round 1 remediation log

Date 2026-10-17. Input: Round1, section "S04_REQUIREMENTS.md and S04_STORIES.md" and decisions X1..X10. One batch, this file only; nothing run, nothing committed. Counts after the batch: 58 requirements (S04-R-001..058), 7 added.

| Item | Change | Basis |
|---|---|---|
| S04-R-014 | Rewritten: sibling recording journal with seal and hand-off through the S02 repository; owner-scope pinning and wipe ordering added; section 4 FACT about S02 line 452 narrowed | stale per ARCH review; X2 |
| S04-R-019 | Rewritten as sub-clauses (a)-(g): transient null stops nothing, hand-off before unbind, 30-day PROPOSED expiry for unsealed, deletion wipes `recording/`, guard counts unfinished recording | X1, X2 |
| S04-R-012 | Sports stated as exactly three (walk, run, ride); AC added | UX18; question 9 |
| S04-R-017, -023, -024 | Export removed; Keep and Delete only; note in R-023 | X3 |
| S04-R-026 | Surface moved to S04-R-054 | X4 |
| S04-R-006, -013, -016, -020, -030, -051 | Cross-references to R-054, -056, -057, -058 | consistency |
| S04-R-052..058 | Added | SEC4 and entry condition; X6; X4; X7; X6; X5; ARCH6 |
| Section 12 | Added: minors statement, release-gate row, accepted risks (7) | SEC9, ARCH12, SEC8 |
| Traceability, questions | Extended (questions 9-16); "nine items A-1..A-8" corrected to eight | this batch |

Numbers that are PROPOSED in this batch: 30-day expiry (R-019), 5 s start timeout (R-055), 10 s manual-pause interval and 30 min prompt (R-057). Not changed: X8, X9, X10 (design and contract matters, see traceability). Not verified: all platform statements (UNVERIFIED), GPS-PRIV-098 text (cited through Round1, not re-read), whether the entry condition holds today (UNKNOWN). Stories file is not touched here; its lane table and wait edges (Round1 section 3) belong to the stories author.

## 16. Round 2 remediation log

Date 2026-10-17. Input: Round1 section 3 (decisions Y1..Y11, findings K1..K10 and minors), the items that touch this file. This file only; nothing run, nothing committed. Requirement count unchanged (58). Y1..Y11 are defaults the operator may override.

| Item | Change | Basis |
|---|---|---|
| S04-R-024 | Keep = seal and hand off as a finished partial activity; Delete removes it; quarantine only for recovery failed; AC extended | Y1, K1 |
| S04-R-019 | (b) transient-null buffer 120 s PROPOSED, stop with reason `account` past the bound; (c) pre-unbind hook, bounded 5 s PROPOSED, also for the guard path and account deletion; (d) hook timeout or failure keeps the unsealed recording with the 30-day expiry; (f) "cannot check" text and "Sign out anyway" stays allowed; ACs follow | Y2, Y3, Y5, K2, K3, K5 |
| S04-R-014 | Retitled and reworded: sibling journal, batched per flush, not appended through the S02 writer; durable wiped-uid marker; ACs (b) and (e) added | Y3, stale wording |
| S04-R-052 | Entry condition: precondition to start building the recorder lane (R3 onwards) unless a dated operator exception is recorded, and a release gate | Y6, K6 |
| S04-R-053 | Owner-visible version shows sport, moving time, distance; public version generic only; tap focuses the recording headline, Finish action focuses the stop panel header; acquiring notification title required | Y11, C2 |
| S04-R-055 | Timeouts: `preparing` to `cannotStart` 5 s; `startFailed` 15 s counted from the service-start call; AC added | Y5, K5, C4 |
| S04-R-056 | Set is exactly battery, storage, sample cap, consent withdrawal; permission revoked keeps its own normal notification; question 12 closed to a default | Y10, K10 |
| S04-R-004 | Offline defined as informational and UNGROUNDED, not shown by default | stale wording |
| Traceability, question 11, question 12 | Updated | this batch |

PROPOSED numbers added or kept: 120 s buffer, 5 s hook bound, 5 s preparing timeout, 15 s startFailed timeout, 30-day expiry. Not touched here: the 30-day expiry runner and the injected hook interface (design and stories matters). Not verified: platform behaviour of notification visibility; the sample-cap stop is stated in S04-R-056 from Y10 and has no separate requirement elsewhere in this file (S04-R-056 is its only home).
