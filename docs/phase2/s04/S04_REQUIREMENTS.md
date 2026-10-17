# S04 requirements: GPS core without a map (recorder, not map)

Status: DRAFT for review, prepared 2026-10-17 on branch `phase2/s04-docs`. Documentation only; no code, no commands run. Author role: business-analyst. All paths are relative to the repository root.

## 1. Purpose, scope, non-goals

Purpose: fix what the S04 recorder must do so that a designer can design from it and a tester can falsify it. This file holds requirements only. It does not choose architecture (architect), rank the backlog (product-owner), or design screens (S04-D contract, a separate document, see A-8).

In scope (Roadmap line 89, the S04 row): foreground-service recorder, journaled samples with crash-safe resume, auto-pause, smoothing and accuracy gate, calculators with replay tests (P2-009), permission flow (foreground first, background only while recording), battery protocol, recording that works with no map service.

Out of scope (non-goals): any map, tile or route display (S11, S05-D, S06-D); the EXPLORE and RIDE screens themselves (S05, S06); sharing, publishing, privacy-zone editor (S09, S10-D); heart-rate and BLE sensors (S06); FIT/GPX import and export; cloud upload of streams (A-6); the full consent centre (A-3); iOS (A-1).

## 2. Labels and sources

- FACT: read in the cited file (path:line). INFERENCE: drawn from facts, stated as such. ASSUMPTION: a default this file adopts so work can proceed (section 3). UNKNOWN: not verifiable here; owner named in section 11.
- PROPOSED: every number or rule invented in this file. None is measured or researched. A PROPOSED number becomes binding only when the product-owner and the operator accept it (the numbers marked "device-lab" are also re-checked on the reference phone).
- Priority: MUST (sprint fails DoD without it), SHOULD (expected; may slip with a recorded reason), COULD (nice to have).
- Short names: Roadmap = `docs/phase2/plan/03_ROADMAP_AND_SPRINTS_2026-10-15.md`; Readiness = `docs/phase2/s04/S04_DOC_READINESS.md`; Privacy = `docs/phase2/s01/GPS_LOCATION_PRIVACY_CONTRACT.md` (ids GPS-PRIV-nnn); S02 = `docs/phase2/s02/S02_DESIGN.md`; S03D = `docs/phase2/s03/S03D_UI_DESIGN_CONTRACT.md`.

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
- FACT: one repository owns the journal behind an in-process mutex; "the S04 recorder submit[s] mutations through it and never touch[es] files directly" (S02 line 452).
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
Statement: The recorder exposes exactly these states to the UI: idle, acquiring, recording, poor accuracy, offline (no network, recording continues), paused manual, paused auto, background, restoring after kill, recovery failed, battery critical, permission revoked, finished. Screens, copy and glance rules belong to S04-D; this requirement fixes only the set and the legal transitions.
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
Rationale: 1 Hz is enough for walk, run and cycle distance at the tolerances of S04-R-032..034; a higher rate is not allowed for diagnostics (GPS-PRIV-003).
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
Statement: With auto-pause on, the recorder enters paused auto when speed stays below 0.5 m/s for 8 s (PROPOSED) and resumes when speed is at least 1.0 m/s for 3 s (PROPOSED). While paused auto, location collection continues (it is needed to detect resume) and counts as collection for privacy purposes, but paused time and distance do not enter moving time or distance. Auto-pause default is on for walk, run and ride; the user can switch it off.
Rationale: separate thresholds (hysteresis) prevent flapping at a traffic light; the 0.5/1.0 values sit under walking speed (about 1.4 m/s).
Source: Roadmap line 89; Privacy line 86 (paused-by-auto-pause is still active recording).
AC: replay fixture F-stop-go: exactly the expected number of pause/resume events, no event inside a 7 s stop, none flapping on 0.6-0.9 m/s jitter; moving time excludes paused time within 1 s.

### S04-R-013 (MUST) Manual pause
Statement: The user can pause and resume manually; manual pause does not end the foreground service and does not release the location subscription.
Rationale: avoids a service restart (and a permission re-check) on every pause; the state set requires paused manual (Roadmap line 88).
Source: Roadmap line 88.
AC: state-machine test: manual pause then auto rule triggers do not change state; resume returns to the prior moving state.

## 7. Requirements: journal, kill and recovery

### S04-R-014 (MUST) Journal through the S02 writer seam
Statement: Samples are appended to a recording journal written only through the S02 repository writer (single mutex); the recorder never opens journal files directly. The recording journal lives in app-private storage and is distinct from the permanent S02 activity store.
Rationale: avoids a second writer; GPS-PRIV-014 distinguishes the crash-safe recording journal from the permanent store.
Source: S02 line 452; Privacy line 101. Format and hand-off are an architect decision (Readiness G3).
AC: a test with a fake file system asserts that the recorder package has no file I/O API calls; two concurrent mutations (recorder append and an unrelated session edit) both land and neither is lost.

### S04-R-015 (MUST) Flush interval and promise on kill
Statement: Samples are made durable at least every 5 s (PROPOSED) or every 10 samples, whichever is first. The promise to the user, and the only one, is: after the app process is killed or the phone restarts, everything recorded up to about 5 s (PROPOSED) before the kill is kept. No promise is made for storage full, a power cut that corrupts the file system, or the user force-stopping the app during the final flush.
Rationale: an honest bound is testable; "never loses data" is not.
Source: Roadmap line 89 and DoD ("survives app kill and screen off"); S03D line 346 (no recovery claim without the mechanism).
AC: kill test (fault injection at random offsets in a 600 s replay, 50 runs, PROPOSED): in every run the recovered track ends no more than 6 s before the injected kill; every recovered record is complete (a torn last record is dropped, not half-read); device-lab: `adb shell am kill` and swipe-away during recording.

### S04-R-016 (MUST) Recovery offer
Statement: On the next app start after a kill with a non-empty journal, the user is offered "Resume", "Save as finished" or "Discard", before any other recording can start. Resume continues the same activity with a gap marker; time between kill and resume is not moving time and not interpolated.
Rationale: GPS-PRIV-014 "a journal left by a crash is offered for recovery".
Source: Privacy line 101; Roadmap line 88 (restoring after kill).
AC: replay-and-restart test shows the offer, and each choice yields the expected stored result; the gap marker has offsets; discarding deletes the journal and leaves no sample on disk (file listing check).

### S04-R-017 (MUST) Recovery failed is honest
Statement: If the journal cannot be read (corrupt, unsupported schema, key loss), the recorder enters recovery failed, keeps the unreadable file untouched until the user chooses delete or export-raw, and never shows a track it could not verify. Copy never claims recovery succeeded.
Rationale: S03D R-S5 forbids a recovery claim without the mechanism; a partial claim is worse than none.
Source: Roadmap line 88; S03D line 346.
AC: corrupt-journal fixtures (truncated, bit-flipped, wrong schema) each yield recovery failed with no exception reaching the UI isolate and the original bytes unchanged until the user acts.

### S04-R-018 (MUST) Finish hand-off
Statement: On finish, the recorder produces one `ActivitySession` (summary, gps/altitude/speed streams, provenance "app GPS") through the S02 writer and only then deletes the recording journal. If the hand-off fails, the journal stays and recovery is offered again.
Rationale: no window in which neither copy exists.
Source: S02 line 452; Privacy line 101; S02 line 419 (consent row).
AC: fault injection between hand-off and delete leaves exactly one of: journal only, or both; never neither; the next start offers recovery or silently de-duplicates by activity id (architect chooses).

### S04-R-019 (MUST) Journal lifecycle
Statement: The recording journal is deleted after a confirmed hand-off, on discard, and on sign-out or account deletion. It is excluded from Android auto-backup and device-transfer (PROPOSED check of current manifest; current state UNKNOWN).
Rationale: GPS-PRIV-014; location history must not leave the phone through a backup.
Source: Privacy line 101; `core/DECISION_LOG.md` line 57853 (Apple rule; the Android analogue is an INFERENCE).
AC: sign-out test removes the journal; a manifest/backup-rules check proves the journal path is excluded.

### S04-R-020 (SHOULD) Storage full
Statement: When free space is under 20 MB (PROPOSED) the recorder warns, and when a write fails it keeps recording in memory for up to 60 s (PROPOSED), then stops and saves what it has with a visible reason.
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

### S04-R-024 (MUST) Revocation mid-recording
Statement: If the permission is revoked during recording (in system settings or from the notification), collection stops at once, the recording is saved up to that moment and marked "permission revoked", and the user is offered keep, export or delete. The app does not re-request.
Rationale: GPS-PRIV-008.
Source: Privacy line 87; Roadmap line 88.
AC: fake permission service flips to denied mid-run: subscription count 0 within 2 s, session saved with the flag, three choices shown, request count unchanged; device-lab: revoke from system settings while recording.

### S04-R-025 (MUST) Notification permission
Statement: The recorder asks for the notification permission at the first Start (Android 13+), before starting the service. If it is denied, the app tells the user that the persistent notification will not show and recording continues only if the platform study confirms the foreground service still runs; otherwise recording is refused with a reason. UNKNOWN until the platform study.
Rationale: GPS-PRIV-007 requires a visible notification; behaviour with denial is not verified.
Source: Privacy line 86; Readiness G4; manifest already declares POST_NOTIFICATIONS (Privacy line 30).
AC: widget tests for granted and denied; the chosen outcome is recorded in the platform study; device-lab run on Android 13 or later.

### S04-R-026 (MUST) Two consent rows
Statement: S04 stores a consent record for "location while recording" and "background location" (the second only if S04-R-022 uses it), each with purpose, timestamp, text version and current state. Withdrawing is one switch and offers export and delete links for the affected data.
Rationale: GPS-PRIV-009; scoped by assumed default A-3.
Source: Privacy line 88; S02 line 419.
AC: grant writes one record with the four fields; withdrawal turns collection off at the next Start and does not delete data; links open export and delete.

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
Statement: At or below 10 % battery and not charging (PROPOSED), state battery critical is entered: a non-modal banner appears, the sampling interval changes to 5 s (PROPOSED), and the flush interval changes to 1 s (PROPOSED). At or below 3 % (PROPOSED) the recorder finishes and saves the activity with a visible reason and stops. The recorder never stops silently and never shows a blocking dialog while recording.
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
AC: the record exists with all items filled; reviewers can see the head it proves.

## 12. Traceability

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

Duplication check: acceptance for "no network" appears in -005 and -046 deliberately (different reasons: map independence versus upload off); the same test may serve both. Untestable items: none; items depending on unverified platform facts (-001, -022, -025) carry an acceptance that records the platform study outcome.

## 13. Open questions for the operator (in words, with options and consequences)

1. Strip priority when a gym timer and a GPS recording run together (S04-R-038). Option A (assumed): the recording is shown, because location is being collected and must stay visible; the gym timer stays reachable in the workout page. Option B: the gym timer stays on top as in the current rule; a person could forget an active recording. Option C: show both (needs a taller dock; changes the S03 layout). Owner: operator with product-owner.
2. Which sensors for elevation (S04-R-034). Option A (assumed): GPS altitude only with the 3 m hysteresis; simple, less accurate on hills. Option B: use the phone barometer when present; better ascent, more code and one more fact to test per device. Owner: product-owner.
3. Behaviour when the notification permission is denied (S04-R-025). Option A: refuse recording with a reason (safe, may annoy). Option B: record without the notification if the platform allows it (convenient, weaker visibility of collection). Final choice depends on the platform study. Owner: operator after the study.
4. Is it acceptable to ask the user to exempt the app from battery optimisation (S04-R-031)? Option A (assumed): no request, only explain in the device-lab record what to set. Option B: in-app request; may improve survival on some phones but risks store policy trouble (UNVERIFIED). Owner: operator.
5. Battery-critical rule (S04-R-030). Option A (assumed): slow down at 10 %, auto-finish at 3 %. Option B: only warn, never stop; the track may be lost if the phone dies, but the user keeps control. Owner: operator.
6. How long a recording may stay unfinished in the journal before recovery is no longer offered. The sources give no value. Option A: offered always until the user chooses (journal stays, costs storage). Option B: expire after N days (PROPOSED 30), then delete with a notice. Owner: operator.
7. Recovery with a long gap (S04-R-016). Option A (assumed): resume with a gap marker whatever the gap. Option B: if the gap exceeds a limit (PROPOSED 30 min), only offer save-as-finished. Owner: product-owner.
8. The nine items A-1..A-8 in section 3 remain open decisions; each default is used until answered.

Unresolved UNKNOWN items blocking the next phase (S04 design): the platform study (Android foreground-service type, notification behaviour); the reference phone; the S04-D contract (state priority order, copy); the content of P2-009.
