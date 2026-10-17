# S04 stories: GPS core without a map (prioritised backlog)

Status: DRAFT for review, 2026-10-17, branch `phase2/s04-docs`; Round 1 remediation applied in one batch (see the last section; decisions X1 to X10 are in `S04_REVIEW_FINDINGS_ROUND1.md`). Documentation only; no code written, no command run. Author role: product-owner. Paths are relative to the repository root.

Inputs read: `docs/phase2/s04/S04_REQUIREMENTS.md` (Req), `S04_DOC_READINESS.md`, `S04_ANDROID_PLATFORM_STUDY.md` (Study), the S04 row of `docs/phase2/plan/03_ROADMAP_AND_SPRINTS_2026-10-15.md` line 89, `docs/phase2/s03/S03_DESIGN.md` section 9.2 (lane format), `docs/phase2/s03/S03_SPRINT_REPORT.md` section 9 (retro actions).

Labels: FACT (read in a cited file), INFERENCE (drawn from facts), PROPOSED (a number or rule invented in Req and not yet accepted), UNKNOWN. Every threshold in an AC below is PROPOSED in Req and stays PROPOSED here; this file adds no new numbers except where marked.

## 1. Sprint goal and scope

Sprint goal (one sentence): an owner-only Android recorder that keeps a continuous, honest GPS track with the screen off, loses at most about 5 s on an app kill, offers recovery on the next start, calculates distance, pace and ascent with replay-tested tolerances, and does all of it with no map service, no network and no upload.

Roadmap source (FACT, line 89): foreground-service recorder, journaled samples (crash-safe resume), auto-pause, smoothing and accuracy gate, calculators with replay tests (P2-009), permission flow, battery protocol; DoD "survives app kill and screen off; tolerance and battery recorded on the operator's phone". Roadmap estimate 5 (unit "pw" is undefined in the rows read; INFERENCE person-weeks). This file makes no estimate of its own: sizes in section 4 are relative (S/M/L), INFERENCE, to be replaced by the architect's S04 design.

One sprint, ONE PR (global rule). Backlog file: this file. Sprint-scope file: section 5 of this file (the READY stories) once the Definition of Ready is met; `docs/phase2/s04/S04_ACCEPTANCE.md` is written at sprint end (not now).

Honest limit of the goal (Study section 5, Req S04-R-015): "survives app kill" means journal recovery on the next launch, not continued recording. The roadmap wording is ambiguous (Study Q2); this backlog uses the recovery meaning until the operator says otherwise.

## 2. Prioritisation rule

1. Risk first: stories whose failure loses user data or whose platform behaviour is unverified (service, journal, recovery) come before comfort features.
2. Dependency second: the location seam, replay harness and state machine unblock almost everything and go first.
3. Value third: calculators and permission flow deliver the user-visible result.
4. Evidence-dependent and operator-dependent work (device lab, conditional stories) goes last and is never counted as done without evidence.
5. A story with an unanswered operator question is CONDITIONAL: it is in the backlog, outside the committed sprint scope until the question is answered, and its default branch is stated.

Priority labels: P0 = sprint fails without it; P1 = expected, may slip with a recorded reason; P2 = nice to have. They follow the Req MUST/SHOULD/COULD marks.

## 3. Epics

| Epic | Name | Stories |
|---|---|---|
| EP-A | Foundations: seam, replay harness, state machine, service | S04-01 to S04-04 |
| EP-B | Sample quality: gate, smoothing, auto-pause | S04-05 to S04-07 |
| EP-C | Calculators | S04-08 to S04-10 |
| EP-D | Journal, kill and recovery | S04-11 to S04-16 |
| EP-E | Permission flow and consent | S04-17 to S04-21 |
| EP-F | Battery | S04-22, S04-23 |
| EP-G | Shell integration and minimal surface | S04-24, S04-25 |
| EP-H | Performance and privacy guarantees | S04-26 to S04-28 |
| EP-I | Device-lab evidence | S04-29 |
| EP-J | Round 1 additions: account events, privacy hardening, notifications, consent surface, preconditions, release gate | S04-30 to S04-38 |

Epic ids are local to S04 (the roadmap epic is E3, FACT line 194). Test agents write and run the complete test set per epic (global rule, section 8).

## 4. Stories

Format: story, priority, size (INFERENCE), requirements, depends on, then numbered acceptance criteria AC-n. Each AC is Given/When/Then and falsifiable. Numbers inside ACs are the Req PROPOSED values.

### EP-A Foundations

**S04-01 Location seam and import guard** (P0, S). Req: S04-R-003, S04-R-005. Depends: none.
- AC-1: Given a fake location service, when the app launches, the user signs out, the device boots (simulated start) or a recording ends, then the fake's subscription count is 0 in all four moments.
- AC-2: Given the recorder package, when the source tree is scanned, then no location-plugin or map-package import exists outside the single seam file; the scan fails the build otherwise.
- AC-3: Given all network adapters throwing, when a fake record-to-save run executes, then it succeeds.

**S04-02 Replay harness and fixtures** (P0, M). Req: S04-R-035. Depends: none (content of P2-009 is UNKNOWN; fixtures follow Req section 10).
- AC-1: Given the ten fixtures (F-noise-line, F-turns, F-stop-go, F-tunnel, F-urban-canyon, F-jump, F-climb, F-ride-30kmh, F-walk, F-kill-mid-run), when each is replayed with a fake clock, then each has a stored expected-result file.
- AC-2: Given one fixture, when replayed twice, then the two outputs are byte-equal.
- AC-3: Given a gate threshold changed in code, when the fixture tests run, then at least one fails (design guarantee by assertion; no mutation run, operator rule).

**S04-03 Recorder state machine** (P0, M). Req: S04-R-004, S04-R-013. Depends: none for the set of 13 states; the priority order of overlapping conditions comes from S04-D (UNKNOWN until approved).
- AC-1: Given the 13 states of Req S04-R-004, when a transition-table test enumerates every pair, then each pair is either a defined transition or rejected; an undefined pair fails the test.
- AC-2: Given the approved S04-D state list, when compared with the code list, then the name lists are equal.
- AC-3: Given state paused manual, when the auto-pause rule fires, then the state does not change; resume returns to the prior moving state.
- AC-4: Given manual pause, when it starts, then the service stays up and the subscription count stays 1.

**S04-04 Android foreground service, manifest, notification** (P0, L). Req: S04-R-001, S04-R-002, S04-R-050 (manifest half). Depends: S04-01; platform study outcome (Study Q1, Q4).
- AC-1: Given the manifest, when checked against the approved list, then it declares exactly the foreground-service, foreground-service-location and location permissions the design uses and one non-exported `location` service; nothing else is added. Per X8 these entries are flag-gated (S04 design D-17 option B) and the plugin's merged manifest is resolved first: the comparison runs against the merged manifest of each flag state, and with the flag off no location or foreground-service entry is merged in.
- AC-2: Given a user taps Start while the app is visible, when the service starts, then the persistent notification is present from the first sample to stop (device lab).
- AC-3: Given the code, when searched, then no path starts the service from boot, launch or a push.
- AC-4: Given a fake location service, when the user stops or discards, then the subscription count is 0 within 2 s of fake time; device lab: the system location indicator goes off.
- AC-5: Given the screen off for 60 min on the reference phone, when recording, then the track is continuous (device lab; evidence in S04-29).

### EP-B Sample quality

**S04-05 Sampling, stored fields, accuracy gate, gaps** (P0, M). Req: S04-R-006, -007, -008, -009. Depends: S04-01, S04-02, S04-03.
- AC-1: Given a 3600 s fake-clock replay, when recording, then exactly 3600 location requests are made (1 s interval).
- AC-2: Given a journal record, when the schema test runs, then any field beyond offset, lat, lon, accuracy, optional altitude, optional speed is rejected; bearing, provider and satellite count are absent.
- AC-3: Given fixes at accuracy 30.0 and 30.1 m, when gated, then the first is kept and the second rejected and only counted.
- AC-4: Given F-jump and F-urban-canyon, when replayed, then no injected fix is kept.
- AC-5: Given F-tunnel (60 s without a kept fix), when replayed, then poor accuracy is entered after 10 s and left on the next kept fix, 0 m is added in the gap, and one gap marker with start and end offsets is written.
- AC-6: Given a stored journal, when mapped to `ActivitySession`, then offsets are strictly increasing and `SampleStream.validate` passes.

**S04-06 Smoothing, raw kept** (P0, M). Req: S04-R-010, -011. Depends: S04-02, S04-05.
- AC-1: Given a changed smoothing algorithm version, when the calculators rerun on a stored journal, then derived values change and the raw sample bytes are identical.
- AC-2: Given F-noise-line and F-turns, when smoothed, then the length is within 3 % of truth, no point moves more than 15 m, and a 90-degree apex stays within 15 m.
- AC-3: Given a finished session, when read, then the formula version string is stored with it.

**S04-07 Auto-pause** (P0, M). Req: S04-R-012. Depends: S04-02, S04-03, S04-05.
- AC-1: Given F-stop-go, when replayed, then the number of pause and resume events equals the expected count; none fires inside a 7 s stop and none flaps on 0.6 to 0.9 m/s jitter.
- AC-2: Given auto-pause on and speed under 0.5 m/s for 8 s, when evaluated, then state paused auto is entered; at 1.0 m/s for 3 s it resumes.
- AC-3: Given paused auto, when sampling continues, then moving time and distance exclude the paused span (moving time within 1 s).
- AC-4: Given walk, run or ride, when a recording starts, then auto-pause defaults to on and can be switched off.

### EP-C Calculators

**S04-08 Distance and session summary** (P0, M). Req: S04-R-032, -036. Depends: S04-06, S04-07.
- AC-1: Given synthetic fixtures of known length, when computed, then error is at most 0.5 % or 5 m, whichever is larger.
- AC-2: Given a real-shaped fixture with surveyed length, when computed, then error is at most 2 %.
- AC-3: Given paused spans and gap segments, when computed, then they add 0 m.
- AC-4: Given a finished recording, when the summary is built, then distance, moving time, elapsed time, ascent, descent, average speed, `formulaVersion` and `metricDefinitionVersion` pass the S02 validator; an out-of-bound value flags the session and is not written.

**S04-09 Pace and speed** (P1, S). Req: S04-R-033. Depends: S04-08.
- AC-1: Given a constant-speed fixture, when the 10 s window is full, then pace is within 3 s/km.
- AC-2: Given moving distance under 10 m or a stopped fixture, when pace is read, then it is undefined (not zero, not infinite).
- AC-3: Given any fixture, when computed, then moving time equals elapsed minus paused within 1 s.

**S04-10 Elevation gain and loss** (P1, S). Req: S04-R-034. Depends: S04-06.
- AC-1: Given a flat fixture with plus or minus 4 m altitude noise, when computed, then ascent is at most 5 m.
- AC-2: Given a staircase fixture of 100 m known gain, when computed, then ascent is within 10 % or 5 m.
- AC-3: Given a fixture with no altitude, when computed, then ascent is undefined, not 0.
- Note: barometer use is an open product question (Req section 13 item 2); default is GPS altitude only.

### EP-D Journal, kill and recovery

**S04-11 Journal append and flush through the S02 writer** (P0, L). Req: S04-R-014, -015, -043. Depends: S04-05; architect decision on journal format and hand-off (Readiness G3, Study Q3).
- AC-1: Given a fake file system, when the recorder package is inspected, then it makes no direct file I/O call; per-second appends go to the sibling recording journal (the S02 interface cannot append per second), and seal and hand-off go through the S02 repository writer.
- AC-2: Given a recorder append and an unrelated session edit running concurrently, when both complete, then both land.
- AC-3: Given a 600 s replay with a fault injected at a random offset, 50 runs, when recovered, then in every run the track ends no more than 6 s before the kill and a torn last record is dropped, not half-read.
- AC-4: Given a 100 000-sample replay, when recording, then the in-memory live list never exceeds 600 entries.
- AC-5: Given `adb shell am kill` and swipe-away during recording on the reference phone, when the app restarts, then the kill promise of AC-3 holds (device lab, S04-29).

**S04-12 Recovery offer and resume** (P0, M). Req: S04-R-016. Depends: S04-11.
- AC-1: Given a non-empty journal after a kill, when the app next starts, then Resume, Save as finished and Discard are offered before any other recording can start.
- AC-2: Given each choice, when chosen, then the stored result matches: Resume continues the same activity with a gap marker (gap not moving time, not interpolated) and enters `acquiring` for every origin (recording, manual pause, auto pause; Z1), with the pause origin preserved in the journal and the interrupted interval adding neither moving time nor distance (a `restart` gap pair); Save stores the session; Discard deletes the journal and a file listing shows no sample left.
- AC-3: Given the recovery text, when reached, then the "recovered" string is reachable only after a verified recovery (links to S04-24 AC-4).
- AC-4 (Round 1, UX1): Given a recovery Resume that is still in `acquiring`, when the user taps Stop, then the kept time is shown and the only exits are Finish or Discard; the recovered data is never discarded as "nothing recorded".
- AC-6 (Z1): Given recordings killed in the paused manual state and in the paused auto state, when each is recovered with Resume, then the state is `acquiring` (never `paused`), the preserved pause-origin and counter values are unchanged, and one `restart` gap pair exists; a test that expects a return into the paused state fails.
- AC-5 (Round 1, X1, X7): Given consent withdrawn, when Resume is chosen, then Resume is refused with the reason and Save as finished and Discard stay available.

**S04-13 Recovery failed is honest** (P0, S). Req: S04-R-017. Depends: S04-11.
- AC-1: Given truncated, bit-flipped and wrong-schema journal fixtures, when opened, then each yields state recovery failed and no exception reaches the UI isolate.
- AC-2: Given recovery failed, when the user has not acted, then the original bytes are unchanged; Keep (quarantine: clears the strip and the Start block, file untouched) and Delete are the only actions. There is no Export in S04 (X3).
- AC-3: Given recovery failed, when copy is shown, then it never claims success.

**S04-14 Finish hand-off** (P0, M). Req: S04-R-018. Depends: S04-08, S04-11.
- AC-1: Given a finish, when the recorder hands off, then one `ActivitySession` (provenance "app GPS") is written through the S02 writer and only then the journal is deleted (ordered writes).
- AC-2: Given a fault injected between hand-off and delete, when the app restarts, then exactly one of journal-only or both exists, never neither; the next start offers recovery or de-duplicates by activity id (architect chooses).
- AC-3: Given a hand-off failure, when it occurs, then the journal stays and recovery is offered again.

**S04-15 Journal lifecycle and owner-only storage** (P0, S). Req: S04-R-019, -045. Depends: S04-11.
- AC-1: Given an explicit sign-out or account deletion, when it completes, then the journal is removed per X1 (sign-out: hand-off first and then delete; the 30-day fallback of S04-30 AC-3 applies only when the hand-off failed and the user was told; deletion: the `recording/` directory is wiped after the recorder is shut down). The sequencing is proved in S04-30.
- AC-2: Given the Android backup and device-transfer rules, when checked against the real directory the factory creates (not a hand-copied name list), then the journal path is excluded.
- AC-3: Given an account switch, when the other user signs in, then the first user's journal and any recovery offer are hidden; the file lives in app-private storage.

**S04-16 Storage full** (P1, S). Req: S04-R-020. Depends: S04-11.
- AC-1: Given free space under 20 MB, when recording, then a warning is shown.
- AC-2: Given a write failure from a fake file system, when it persists 60 s, then the recorder stops, saves all samples up to the stop and shows the reason.

### EP-E Permission flow and consent

**S04-17 Foreground permission flow and denial paths** (P0, M). Req: S04-R-021, -023. Depends: S04-01, S04-03; S04-D copy.
- AC-1: Given app launch, onboarding and tab switches, when they occur, then the fake permission service call count is 0.
- AC-2: Given the first Start tap, when pressed, then the pre-prompt shows, then the system request (fine and coarse together).
- AC-3: Given outcomes granted, denied once, denied permanently and approximate only, when each occurs, then the screens match: Try again plus Add manually; Open settings plus Add manually with no re-request; approximate refuses recording with an explanation. Request count never exceeds 1 per tap; manual entry works in every outcome.

**S04-18 Permission set and background-location decision** (P0, S) - CONDITIONAL. Req: S04-R-022. Depends: S04-04.
- Question in words: does continuous recording need background location, or is a foreground service started while the app is visible enough? Study 3.7 infers it is enough but needs a device test; Play handling is UNKNOWN (Study 4.11). Default branch: not requested.
- AC-1 (default branch): Given the approved permission list without background location, when the manifest and code are scanned, then no declaration and no request for it exist.
- AC-2 (branch B only, if the operator or the device test requires it): Given foreground granted, when the first recording starts, then background is requested separately, only at a Start tap, with educational UI; declared set equals used set.

**S04-19 Revocation mid-recording** (P0, S). Req: S04-R-024. Depends: S04-04, S04-17.
- AC-1: Given the fake permission service flips to denied mid-run, when detected, then the subscription count is 0 within 2 s and collection stops (Z2).
- AC-1b (Z2): Given a revocation, when it is detected, then the partial recording is durably SEALED in the recording journal in the display state `permissionRevoked` (pending decision, listed by `listUnfinished`, survives a kill); no S02 hand-off has happened yet and the stale internal reason `stoppedRevoked` is not used.
- AC-2: Given the revoked session, when shown, then Keep (the ordered, idempotent, owner-checked S02 hand-off as a finished partial activity whose data up to the revocation is readable, Y1, Z2) and Delete (the ordered delete with the `DISCARDING` marker; the recording is never resurrected) are offered, with no Export (X3); quarantine (file untouched, clears the strip and the Start block) applies only to `recoveryFailed` (S04-13), and the request count is unchanged (no re-request). A pending revoked decision has a durable home (strip row and Home card) and the screen states whether Start is blocked (UX3).
- AC-3: Given the reference phone, when permission is revoked in system settings, then the result is recorded as PASS, FAIL or NOT_RUN (Study section 7 item 4).
- AC-4 (Z2, fault injection): Given a fault injected at each of: revocation, seal, process death, Keep, hand-off, Delete, when the app restarts, then exactly one consistent durable state exists, either the pending-decision sealed recording or the finished activity (never both, never twice, no duplicated activity), and a Delete that was interrupted completes and never resurrects the recording.
- AC-5 (Z5, first durable decision wins): Given a pending-decision recording, when Keep or Delete is chosen, then the single authoritative file `DECISION` in the recording directory is created with an exclusive-create operation (fails if the file exists; never a rename that may replace a target, Z7), the winner writes `KEEP` or `DELETE` into it and fsyncs the file and then the parent directory, and only then may any irreversible action start (S02 `put` or ordered delete); Keep and Delete are mutually exclusive and the first successful exclusive create wins. `DISCARDING` is not a decision: it is a progress marker valid only with `DECISION` = `DELETE` (Z7).
- AC-6 (Z5, replay and refusal): Given a durable marker, when the other choice or a replay of the same choice arrives, then it is a no-op reporting "already decided"; once `KEEP` is durable Delete is not offered for that recording and never removes the S02 activity the hand-off created (deleting that finished activity later is a separate action through the normal S02 delete flow); once `DELETE` is durable Keep is refused and the delete completes on recovery.
- AC-7 (Z5, recovery by marker): Given a restart, when recovery reads the marker, then `KEEP` completes the hand-off idempotently (upsert on the deterministic activity id) and then cleans up, `DELETE` completes the ordered delete, and no marker means the recording is still a pending decision.
- AC-9 (Z7, arbiter and loser): Given two callers (Keep and Delete, or two Keeps) that both saw no marker, when both run, then exactly one exclusive create succeeds and the loser's create fails, the loser reads the committed winner, does nothing irreversible (no `put`, no delete step, no overwrite of `DECISION`) and reports "already decided"; a per-recording mutex serialises same-process callers as defence in depth but the test must also pass with the mutex bypassed.
- AC-10 (Z7, forced interleaving): Given a test hook that pauses both writers after each has checked for a marker and before either creates `DECISION`, when they are released in both orders, then in each order exactly one decision exists, equal to the winner's choice, and the final durable state is the single consistent result of AC-8; a rename-based implementation fails this test.
- AC-11 (Z7, torn or empty file): Given a `DECISION` file that is empty or torn (creator crashed between create and the durable write), when recovery runs at the next start, then no irreversible action has happened, the empty or torn file is removed and the recording is again a pending decision; a live loser finding an empty file waits at most 2 s, then reports "decision in progress, try again" without acting.
- AC-12 (Z7, malformed combinations): Given `DISCARDING` without `DECISION` = `DELETE`, `DECISION` = `KEEP` together with `DISCARDING`, or unknown `DECISION` content, when recovery runs, then the recording moves to QUARANTINED with a visible notice and performs no delete and no hand-off, and the file bytes are unchanged.
- AC-8 (Z5, crash and concurrent injection): Given Keep and Delete injected concurrently and as a crash at each of three points (before the S02 `put`, immediately after a successful `put`, before journal cleanup), when the app restarts, then each point yields exactly one deterministic result by the precedence rule above (before `put` with both requests: the first marker written wins; after `put` or before cleanup: Keep wins and the single activity remains), with no duplicate activity and no resurrected data.

**S04-20 Notification permission** (P1, S) - CONDITIONAL. Req: S04-R-025. Depends: S04-04.
- Question in words: when the user denies notifications, may the recorder run without a visible notification, or must it refuse to record? Default branch: refuse with a reason (safe); the final choice depends on the device test (Study 3.12) and the operator (Req item 3).
- AC-1: Given Android 13 or later, when the first Start is tapped, then the notification permission is asked before the service starts.
- AC-2: Given granted, when recording, then the notification shows.
- AC-3: Given denied, when Start is tapped, then the chosen branch applies (default: recording refused with a reason) and the outcome is recorded in the platform study.

**S04-21 Two consent rows and draft wording** (P1, M). Req: S04-R-026, -027. Depends: S04-17.
- AC-1: Given a grant, when stored, then one record holds purpose, timestamp, text version and state; a background row exists only if S04-18 uses it.
- AC-2: Given withdrawal, when the next Start is tapped, then collection is off and no data is deleted; links to the in-app delete path open (no export link, X3). The withdraw surface itself is S04-33.
- AC-3: Given the consent record and the string file, when compared, then the text versions are equal; the strings are marked DRAFT.

### EP-F Battery

**S04-22 Battery-critical behaviour** (P0, S). Req: S04-R-030. Depends: S04-03, S04-11.
- AC-1: Given a fake battery at 10, 9, 3 and 2 %, when not charging, then at 10 and 9 state battery critical, a non-modal banner, a 5 s sampling interval and a 1 s flush apply; at 3 and 2 the recorder finishes and saves with the visible reason "stopped: battery".
- AC-2: Given charging at 8 %, when evaluated, then the state is not entered.
- AC-3: Given any battery event, when it occurs, then no blocking dialog appears and the recorder never stops silently.
- Note: warn-only instead of auto-finish is an open product question (Req item 5); default is auto-finish at 3 %.

**S04-23 Battery protocol document** (P1, S). Req: S04-R-028. Depends: none.
- AC-1: Given the document, when reviewed, then it fixes: phone and Android version, 60 min walk and 60 min ride, screen off, battery percent read from the system, one run on battery, network state and temperature, result as percent per hour.
- AC-2: Given a run record missing any listed field, when reviewed, then it is not accepted as evidence.

### EP-G Shell integration and minimal surface

**S04-24 Strip shows the GPS recording; independent sources** (P0, M). Req: S04-R-037, -038, -039. Depends: S04-03; architect decision (prioritised source list or rewrite of `activeSessionStatusProvider`, Readiness line 113).
- AC-1: Given a fake second source, when active, then the strip shows it on all tabs.
- AC-2: Given an account switch, when it occurs, then the strip hides the other account's source.
- AC-3: Given two sources, when one ends, then the other's owner is not cleared.
- AC-4: Given a gym timer and a GPS recording both active, when the strip is derived, then the GPS recording is shown (PROPOSED; open question Req item 1) and ending it shows the gym timer.
- AC-5: Given copy, when scanned, then the recovery string is reachable only from the recovery-succeeded path and no gym path references it.
- AC-6: Given every entry point of the capability "recording visible" (dock strip, rail slot, Record pill, Record shortcut, Record sheet opener), when a foreign-account session is present, then each has its own test row.

**S04-25 Minimal start, pause, stop and recover surface** (P0, L). Req: S04-R-040. Depends: S04-03, S04-17, S04-24; S04-D approved (Roadmap: "S04 builds only this").
- AC-1: Given the built screens, when mapped, then each maps to a screen in the approved S04-D contract; an unmapped screen fails review.
- AC-2: Given the surface, when used, then Start, pause, resume, stop and the recovery choices work with no map and no EXPLORE or RIDE journey.
- AC-3: Given the code, when searched, then no new top-level shell path list, back rule or sheet flag copy is added (Readiness line 114).
- AC-4: Given the finish screen, when shown, then it states the track stays on this phone and is not shared (S04-R-047 shares the string with S04-28).
- AC-5 (X9): Given text scale 2.0 on a 320x640 screen, when the recording screen is shown, then the time numerals are capped at scale 1.3 with fit-to-width and nothing overflows; hint, signal word and banner are counted and capped per element class, not by a single "five text elements" rule.
- AC-6 (X10): Given the user's own Pause, Resume, Stop, Finish or Discard, when pressed, then the response is always announced; only machine-originated announcement kinds are suppressed when repeated.
- AC-7 (X3): Given the revoked and recovery-failed screens built, when mapped to S04-D, then neither offers Export; the Stop, Discard and Finish panels scroll with the body at scale 2.0 and in landscape with the focused button visible (A11Y M2).

### EP-H Performance and privacy

**S04-26 Off the UI isolate and 100k frame budget** (P0, M). Req: S04-R-041, -042. Depends: S04-11, S04-14.
- AC-1: Given a spy on isolate use, when payload build, gzip, SHA-256, journal seal and open, smoothing and full-session calculators run, then none runs on the main isolate; live metrics update incrementally.
- AC-2: Given a 100 000-sample session in a profile-mode test, when opened, sealed, finished and summarised, then the maximum frame build time is at most 16 ms, seal plus open at most 3 s and peak extra memory under 100 MB; the reference-phone value is PASS, FAIL or NOT_RUN.

**S04-27 No coordinates in logs or telemetry** (P0, S). Req: S04-R-044. Depends: S04-11.
- AC-1: Given sentinel coordinates such as 12.3456789, when the record, pause, kill-recover, finish and fail flows run, then no captured log line, exception message or telemetry event contains them.
- AC-2: Given any exception on these flows, when logged, then it is mapped to a bare code first.

**S04-28 Upload off, constants, Android-only claim** (P1, S). Req: S04-R-046, -047, -048, -049, -050 (claim half). Depends: S04-05.
- AC-1: Given the cloud-stream flag, when read, then the default constant is false and a test asserts the upload entry point is unreachable from the recorder; heart rate is never recorded.
- AC-2: Given the saved-on-device string, when the finish screen shows, then it is present; it is removed only by the sprint that enables upload.
- AC-3: Given the constants, when read, then default privacy-zone radius (200 m) with its setting key and default expiry (24 months from activity date) exist with a test; no code applies them.
- AC-4: Given release notes and tests, when searched, then no iOS pass claim exists; iOS rows read NOT_RUN.

### EP-I Device-lab evidence

**S04-29 Device-lab record on the reference phone** (P0, M) - CONDITIONAL. Req: S04-R-029, -031, -051 (runs under S04-R-028 protocol). Depends: S04-04, S04-11, S04-08 to S04-10, S04-23; a named reference phone.
- Question in words: which phone is the reference device and when is it available? Default: UNKNOWN. Without it the DoD "tolerance and battery recorded on the operator's phone" cannot close; S04 can be coded and reviewed but not accepted, and this story stays NOT_RUN.
- AC-1: Given the reference phone, when the record is written, then it states device and OS, build id and head, kill survival (S04-11 AC-5), screen-off continuity (S04-04 AC-5), tolerance results from a walked and a ridden known route, the battery run against the 8 % per hour target, and the OEM background-kill result, each as PASS, FAIL or NOT_RUN.
- AC-2: Given missing evidence, when recorded, then it is NOT_RUN, never PASS; a FAIL against the drain target is recorded and the product-owner decides accept, tune or defer.
- AC-3: Given the record, when reviewed, then it identifies the head it proves.
- AC-4: Given the OEM check, when run, then the app does not request a battery-optimisation exemption (default; open question Req item 4).

### EP-J Round 1 additions

Story ids S04-30 to S04-38 are appended so existing ids stay stable. Requirement ids S04-R-052 to -058 are in `S04_REQUIREMENTS.md`; the AC wording follows those requirements and `S04_REVIEW_FINDINGS_ROUND1.md` (decisions X1 to X10, Y1 to Y11). Numbers marked PROPOSED come from the decisions X1 to X10.

**S04-30 Sign-out, account switch and account deletion with a recording** (P0, L). Req: S04-R-019 (reworded per X1), S04-R-043; source X1, X2, ARCH1 to ARCH3, SEC1, SEC2. Depends: S04-11, S04-14, S04-15; architect decision on tombstone and ordering.
- AC-1: Given a recording running, when the auth stream emits a transient null or a loading state, then nothing stops, nothing is written to another scope and the subscription count stays 1.
- AC-2: Given a recording running, when a confirmed different non-null uid appears or an explicit sign-out or deletion event arrives, then the bind controller in `activity_wiring.dart` awaits the registered recorder pre-unbind hook (bounded, PROPOSED 5 s) before it unbinds, and the hook stops, seals and hands off into the owner's store with an owner check against the scope captured at `begin()`; on the strict path the hand-off completes first and only then is the recording journal deleted (Z3); only if the hook times out or the hand-off fails does the unsealed recording stay encrypted in its scope under the 30-day fallback of AC-3 (Y2). While the scope is unbound after a transient null, appends go to a bounded in-memory buffer (PROPOSED 120 s) and flush after the same uid rebinds; past the bound the recording stops with the reason `account` (Y3).
- AC-3 (Z3): Given the hand-off cannot complete, when sign-out proceeds, then the user is told at sign-out with explicit text, and the unsealed recording stays encrypted in its own account scope for at most a PROPOSED 30 days; it is deleted on expiry, on account deletion or after recovery, and is never readable by another account (links to S04-15 AC-3). This is the only case where a recording journal outlives a sign-out. It amends S01 GPS-PRIV-014 (journal deleted on sign-out or deletion) as a PROPOSED clarification; the alternative is strict deletion with silent loss on hand-off failure, an operator question carried in the requirements.
- AC-8 (Z3, lifecycle rows, one test row each): (a) successful hand-off: the activity exists once and the recording journal is deleted; (b) failed hand-off: the recording stays in its scope, the notice was shown, nothing is readable by another account; (c) explicit sign-out: the strict path of AC-2 runs; (d) account deletion: the `recording/` directory is empty and nothing is resurrected (AC-4); (e) expiry: at 30 days the fallback recording is deleted and a clock test at 29 days 23 h keeps it; (f) subsequent sign-in: the same owner sees the unfinished recording offered for recovery before the expiry, a different account sees nothing, and after expiry nobody sees it.
- AC-4: Given account deletion, when it runs, then the order is: recorder shutdown, recording journal close and refuse-after-wipe (shared wiped-uid tombstone), then the S02 wipe, and then the `recording/` directory is empty; a fault injected between any two steps never leaves a resurrected key or a readable journal.
- AC-5: Given every recording step (append, seal, hand-off `put`, recovery, delete), when the scope is no longer bound or has been wiped, then the step writes nothing and keeps the recording (X2).
- AC-6: Given an active or unfinished recording, when the user opens sign-out, then the sign-out guard counts it and the warning sheet names it; the guard path uses the same pre-unbind hook as AC-2; when the guard cannot check, then it shows the reason with explicit text and "Sign out anyway" stays allowed, because the user can always leave (Y5); the outcome is never silent.
- AC-7: Given the entry points of the capability "sign-out with a recording" (settings sign-out, guard sheet, account-deletion flow, auth-stream event, notification action while signed out), when each is exercised, then each has its own test row (DoD item 4).

**S04-31 Sanitising wrapper and global error handlers** (P0, M). Req: S04-R-052 (new), extends S04-R-044. Source SEC4. Depends: S04-27; entry condition in section 5 (GPS-PRIV-050 and 098 server enforcement).
- AC-1: Given journal decode, worker entry and the isolate boundary, when an error occurs, then a sanitising wrapper converts it to a content-free error type before it leaves that layer.
- AC-2: Given sentinel coordinates such as 12.3456789, when errors are raised on record, kill-recover, finish and fail flows, then neither the zone handler, `recordFlutterFatalError`, `recordError`, the debug `debugPrint` telemetry sink nor a Crashlytics spy sees them.
- AC-3: Given the code, when scanned, then no raw exception object from recorder code reaches a global handler without the wrapper.

**S04-32 Lock-screen notification** (P0, M). Req: S04-R-053 (new). Source X6, SEC6. Depends: S04-04; S04-D copy.
- AC-1: Given the device lock screen, when recording, then the notification visibility is private and the public version is generic, with no sport, time, distance, coordinates or pace; the owner-visible (unlocked shade) version shows sport, moving time and distance (Y11).
- AC-2: Given the public version, when inspected, then it has no actions; the private version has Pause/Resume and "Finish..." only, and "Finish..." opens the stop panel and does not stop the recording.
- AC-3: Given a plain notification tap, when handled, then the recording screen opens with focus on the headline; given the Finish action, then the stop panel header takes focus; in both cases the header is read once with no duplicate announcement (Y11, C6).
- AC-4: Given the device lab, when the lock screen is photographed, then the result is PASS, FAIL or NOT_RUN in S04-29.

**S04-33 Consent withdrawal surface** (P1, M). Req: S04-R-054 (new), completes S04-R-026. Source X4, SEC5, UX11. Depends: S04-21.
- AC-1: Given Settings, Privacy, when opened, then one withdraw switch and the links are shown; the strings are DRAFT.
- AC-2: Given consent withdrawn, when Start is tapped, then Start is blocked with the reason, and Resume is refused (S04-12 AC-5).
- AC-3: Given consent withdrawn during a recording, when the switch is flipped, then the recording stops and is kept, never deleted.
- AC-4: Given withdrawal, when it is stored, then purpose, timestamp, text version and state are recorded and no data is deleted.

**S04-34 Start preconditions** (P0, S). Req: S04-R-055 (new). Source X7, ARCH8. Depends: S04-11, S04-12, S04-17.
- AC-1: Given the journal is not yet open or the unfinished-recording check is incomplete, when Start is tapped, then a visible "preparing" panel shows and no recording starts.
- AC-2: Given the journal cannot be opened, when Start is tapped, then a "cannot start" panel shows with Try again and Add manually, one timeout per transition (Y5): `preparing` changes to `cannotStart` after a PROPOSED 5 s; `startFailed` follows after a PROPOSED 15 s counted from the service-start call (UX7, A11Y M9).
- AC-3: Given the preconditions pass, when Start is tapped, then recording starts and a busy label shows until the first state change; a start that hangs ends in a `startFailed` panel.

**S04-35 Automatic-stop notification** (P0, S). Req: S04-R-056 (new). Source X6, UX2, A11Y M5. Depends: S04-22, S04-16, S04-32.
- AC-1: Given an automatic stop of one of the set battery (3 %), storage failure (60 s), sample cap or consent withdrawal (Y10), when the stop completes, then a separate non-ongoing notification is posted with the reason, the saved time and the distance. Permission revoked is not in the set; it keeps its own normal notification of the same family with the existing copy (S04-19).
- AC-2: Given the screen off, when the stop happens, then the notification is the only signal and it contains no coordinates.
- AC-3: Given the notification, when tapped, then the behaviour of S04-32 AC-3 applies (recording screen, focus on the headline, one reading).

**S04-36 Manual-pause interval and prompt** (P1, S). Req: S04-R-057 (new). Source X5, SEC7. Depends: S04-03, S04-04.
- AC-1: Given manual pause, when it is entered, then the subscription count stays 1 at a PROPOSED reduced interval of 10 s and no sample reaches the track.
- AC-2: Given manual pause lasting a PROPOSED 30 minutes, when the time passes, then a prompt asks to resume or finish.
- AC-3: Given the pause hint, when shown, then it says that location stays on.
- AC-4: Given S04-03 AC-4 (the subscription stays 1), when this story lands, then both ACs are consistent in the transition-table test.

**S04-37 Engine-detach behaviour** (P0, M) - CONDITIONAL on device test T2. Req: S04-R-058 (new). Source ARCH6. Depends: S04-04, S04-29.
- Question in words: when Android destroys the Flutter engine while the service lives on, does the notification keep saying Recording although no Dart code runs? Default branch: the service stops, or the notification stops claiming Recording, when the engine detaches; option A (keep recording through detach) is allowed only if device test T2 passes.
- AC-1: Given a simulated engine detach, when it occurs, then the notification never claims Recording while no Dart code consumes fixes.
- AC-2: Given the detach, when the app restarts, then the S04-12 recovery path is offered and the gap is a marked gap.
- AC-3: Given device test T2, when run on the reference phone, then it is PASS, FAIL or NOT_RUN; NOT_RUN keeps the default branch.

**S04-38 Release gate: privacy policy, data-safety form, foreground-service declaration, disclosure text** (P0 for release, outside code, S). Req: `S04_REQUIREMENTS.md` section 12 (minors statement, release-gate row, accepted risks; this section has no S04-R id, owners are open question 15). Depends: S04-21, S04-04.
- Owner (PROPOSED): the operator owns the Play Console submission; the product-owner drafts the four texts and records status; the security-reviewer checks them against the shipped manifest.
- AC-1: Given the release checklist, when reviewed, then it has one row each for the privacy policy, the data-safety form, the foreground-service declaration (with the location use justification) and the in-app disclosure text, each with an owner and the status DRAFT, READY or NOT_RUN.
- AC-2: Given the minors statement, when reviewed, then it says recordings are private only, with no sharing and no upload.
- AC-3: Given the data-safety answers, when compared with the manifest and S04-28, then they match (no upload, no sharing, no heart rate).
- AC-4: Given any row not READY, when the sprint is accepted, then the sprint can be accepted for code but the release is recorded as blocked, never as ready.
- AC-5: Given the accepted risks (rooted or debuggable build can read key and memory; a second app with location permission sees the same fixes; notification-listener apps; file sizes and mtimes reveal duration; no AAD binding of frames, integrity only), when reviewed, then each is written down in the design or the checklist.

## 5. Sprint scope and Definition of Ready

Committed scope once ready (all non-conditional stories): S04-01 to S04-17, S04-19, S04-21 to S04-28, S04-30 to S04-36, S04-38. Export is out of scope (X3). Conditional, pulled only when the named question is answered: S04-18 (background-location use), S04-20 (notification denial), S04-29 (reference phone), S04-37 (engine-detach, needs device test T2; default branch applies meanwhile). Nothing outside the goal is added.

Suggested build order (INFERENCE, dependency-derived): wave 1 S04-01, S04-02, S04-03, S04-23; wave 2 S04-04, S04-05, S04-11; wave 3 S04-06, S04-07, S04-12 to S04-16, S04-17; wave 4 S04-08 to S04-10, S04-19, S04-21, S04-22, S04-24; wave 5 S04-25 to S04-28 and S04-30 to S04-36 (S04-30 right after S04-14 and S04-15, S04-31 with S04-27); S04-38 runs in parallel as a document task from wave 1; last S04-18, S04-20, S04-29, S04-37. Per retro action 1, the first compile smoke runs after wave 1.

**Definition of Ready (a story enters the sprint only if all hold):**
1. Each requirement id is traced (section 7) and the Req text is not DRAFT-contradicted by a later decision.
2. Every AC is Given/When/Then and testable with a fake or fixture; a device-only AC names the device-lab story that carries it.
3. Design and UI inputs exist: S04-D approved for any story that shows a screen or copy (S04-03 AC-2, S04-17, S04-19, S04-22, S04-25); the platform study outcome is recorded for S04-04.
4. Dependencies are known and no dependency is unscheduled; the architect's S04 design names the journal format, hand-off and strip approach (S04-11, S04-14, S04-24).
5. Operator questions: each unanswered question has a stated default branch or the story is CONDITIONAL.
6. The file lane (section 9) is assigned and owns every path the story touches, including the Round 1 files (sign-out guard, wipe, generation writer, record sheet, shortcuts, pubspec and Gradle, ARB, main shell).
7. Entry condition (Y6): server enforcement of GPS-PRIV-050 and GPS-PRIV-098 is a precondition to start building the recorder lanes (R3 onwards) unless the operator records a dated exception; it is also a release gate (S04-38). Without it, or the exception, the recorder-lane stories stay NOT READY.
8. Round 1 decisions X1 to X10 are reflected in the S04 design, the S04-D contract and the requirements text the story cites; a story citing text that still contradicts a decision is NOT READY.

Current readiness (status at 2026-10-17, Round 2): the S04-D contract, the S04 design and the requirements text exist as drafts and have passed two internal review rounds, but none is approved; the test plan is not written (Readiness G8). Stories needing an approved S04-D or design are NOT READY until approval; the GPS-PRIV-050 and 098 enforcement entry condition (DoR item 7) is not confirmed (UNKNOWN); the Round 1 text fixes by other authors are not yet merged (DoR item 8); S04-38 needs the operator as owner of the Play Console steps. Stories S04-01, S04-02, S04-23 are READY now (INFERENCE: no listed dependency open).

## 6. Definition of Done

Sprint level (all required for acceptance; CI is not a requirement, operator rule):
1. Code committed; every commit has its own change-record file linked from the message, and an entry in `core/LESSONS_LOG.md` in the same commit.
2. Compile smoke (retro action 1): after any batch edited by agents that cannot build, one test agent runs a compile-only smoke before the commit; the first test run starts after wave 1, not after the last lane. Risky diffs are read by the coordinator.
3. Per-epic functional tests: the test agents write detailed scripts for every epic and run the complete set they wrote after each epic; after the last epic they run everything once more, on the exact head to be approved. A run one fix cycle behind the approved head does not count as final (S03 retro open question).
4. Entry points enumerated (retro action 2): for each capability a rule applies to (recording visible, foreign-account hiding, start allowed, stop), the story lists every entry point (dock, rail, pill, shortcut, sheet opener, notification action, recovery offer) and each has a test row.
5. Ordered writes (retro action 2): every notifier or store that persists state has an ordered write path, a sequence test, and for each new state field every function that reads or resets it has a test row (retro action 7). The finish hand-off and journal delete order is proved by fault injection (S04-14).
6. State machines list all events of their source streams including repeated and equal values (retro action 6): permission, battery, location and auth streams.
7. Review: relevant specialist agents (architect, functional-test-reviewer, silent-failure-hunter, security-reviewer, reliability-reviewer, database-reviewer, flutter-reviewer, code-reviewer as routed) reach consensus on the head; all valid BLOCKER and MAJOR findings fixed; an independent read-only review of the journal and recovery state machine before the code gate.
8. GPT-PM APPROVE for the exact head; a new commit invalidates it; then push and ONE PR.
9. Data protection before data on (retro action 9): backup exclusion of the journal lands and its test walks the real directory before recording is enabled.
10. Documentation: S04 release notes, platform study updated with device results, document registry regenerated, `S04_ACCEPTANCE.md` written with each story accepted, rejected or carried and an evidence link.
11. Honest status: every unmeasured item reads NOT_RUN; no PASS without an artifact; no iOS claim.
12. Product acceptance of agent-drafted strings is recorded as open (S03 left it open); strings stay marked DRAFT.
13. Round 1 gates: the sanitising-wrapper sentinel test runs through the zone handler and a Crashlytics spy (S04-31); account-event fault-injection rows for sign-out, deletion and wipe ordering are green (S04-30); manifest entries are checked against the merged manifest of both flag states (S04-04 AC-1).
14. Release gate (S04-38): privacy policy, data-safety form, foreground-service declaration and disclosure text each have an owner and a recorded status. Code acceptance does not require them READY, but release readiness is not claimed while any row is not READY.
15. A TalkBack device walk and the lock-screen check are recorded in S04-29 as PASS, FAIL or NOT_RUN (A11Y m4, SEC6).
16. Export is not built or tested in S04; a scan finds no export entry point in the recording feature (X3).

Story level: all ACs have a passing test or a recorded device-lab result; the test would fail if the guarded behaviour broke (assertion check, no mutation run); no open BLOCKER or MAJOR on the story.

## 7. Out of scope (explicit)

- Any map, tile or route display; map package imports (S11, S05-D, S06-D).
- EXPLORE and RIDE screens and journeys (S05, S06); walking and running engines, bike types, GPX/FIT import and export.
- Export of any recording, including export-raw of a failed journal and export of a revoked session (X3; S04-D DN-8 option B). Revoked and recovery-failed screens offer Keep and Delete only.
- Sharing, publishing, privacy-zone editor and applying the zone to anything (S09, S10-D); S04 defines only the constants.
- Cloud upload of streams, upload scheduler, expiry enforcement or deletion jobs (A-6, A-5).
- Heart-rate and BLE sensors (S06); heart rate is never recorded in S04.
- The full consent centre (A-3); iOS (A-1; no iOS claim, rows NOT_RUN).
- Barometer elevation (default GPS altitude only); battery-optimisation exemption request (default none).
- Unattended restart or continued recording after an app kill (not promised by the platform pages read, Study section 5).
- Layout fixes to base code found by the S03 conformance matrix; the S03 stories S03-19 and S03-20 (carried, lane L11).
- Writing S04-D, the S04 design and the test plan (separate documentation steps, Readiness section 5).

## 8. Story-to-requirement trace

| Story | Requirements |
|---|---|
| S04-01 | S04-R-003, -005 |
| S04-02 | S04-R-035 |
| S04-03 | S04-R-004, -013 |
| S04-04 | S04-R-001, -002, -050 |
| S04-05 | S04-R-006, -007, -008, -009 |
| S04-06 | S04-R-010, -011 |
| S04-07 | S04-R-012 |
| S04-08 | S04-R-032, -036 |
| S04-09 | S04-R-033 |
| S04-10 | S04-R-034 |
| S04-11 | S04-R-014, -015, -043 |
| S04-12 | S04-R-016 |
| S04-13 | S04-R-017 |
| S04-14 | S04-R-018 |
| S04-15 | S04-R-019, -045 |
| S04-16 | S04-R-020 |
| S04-17 | S04-R-021, -023 |
| S04-18 (CONDITIONAL) | S04-R-022 |
| S04-19 | S04-R-024 |
| S04-20 (CONDITIONAL) | S04-R-025 |
| S04-21 | S04-R-026, -027 |
| S04-22 | S04-R-030 |
| S04-23 | S04-R-028 |
| S04-24 | S04-R-037, -038, -039 |
| S04-25 | S04-R-040 |
| S04-26 | S04-R-041, -042 |
| S04-27 | S04-R-044 |
| S04-28 | S04-R-046, -047, -048, -049, -050 |
| S04-29 (CONDITIONAL) | S04-R-029, -031, -051 |
| S04-30 | S04-R-019 (X1 wording), -043; X1, X2 |
| S04-31 | S04-R-052, -044 |
| S04-32 | S04-R-053 |
| S04-33 | S04-R-054, -026 |
| S04-34 | S04-R-055 |
| S04-35 | S04-R-056 |
| S04-36 | S04-R-057 |
| S04-37 (CONDITIONAL) | S04-R-058 |
| S04-38 | Requirements section 12 (no S04-R id): minors statement, release-gate row, accepted risks |

Coverage check (by reading the table): requirements 001 to 058 each appear at least once (052 to 058 are in `S04_REQUIREMENTS.md`, read in Round 2); the shared ones are -005 (S04-01, reused by S04-28 AC-1), -047 (S04-25 AC-4 and S04-28 AC-2) and -050 (manifest half S04-04, claim half S04-28). No story lacks a requirement; no requirement is without a story. Number of stories 38, of which 4 CONDITIONAL (S04-18, S04-20, S04-29, S04-37).

## 9. Proposed build lanes and file ownership

Rule (from S03 RV-5): a path appears in at most one lane; a lane owns a file for the whole sprint; a second lane never edits it, not even serially. A dependent lane uses the public API of a file owned by another lane, created in that lane's interface commit (final signatures, possibly stub bodies) before the dependent lane mounts it. Shared resource files (ARB localisation, router, `main.dart`, providers wiring) are lane rows, not free-for-all (retro action 8). Implementation agents use the allowed model policy, never approve their own change, and the coordinator runs no tests. Test files have one owner each, the test agents, and are not lane paths.

Paths below are PROPOSED: the architect's S04 design fixes them. `mobile/lib/features/recording/` is a new directory (no recorder exists, FACT Readiness line 47). Existing paths are read from the S03 table or the Study: `features/workouts/state/active_session_status.dart`, `shared/widgets/dock_widgets.dart`, `core/wiring/activity_wiring.dart`, `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/res/xml/backup_rules.xml`, `data_extraction_rules.xml`. S03 lanes are closed (merged), so ownership of its files transfers to S04 lanes for this sprint only.

| Lane | Paths owned (under `mobile/` unless stated) |
|---|---|
| R1 | `lib/features/recording/location/**` (the single location seam, fake interface, permission service), `lib/features/recording/permissions/**`, import-guard scan test support |
| R2 | `android/app/src/main/AndroidManifest.xml`, native service files under `android/app/src/main/kotlin/**` (only if the architect picks an own channel; path UNKNOWN), `android/app/src/main/res/xml/backup_rules.xml`, `data_extraction_rules.xml`, notification string resources under `android/app/src/main/res/values/` (native notification text only, keys supplied by R8); Round 1: `pubspec.yaml` and `pubspec.lock` (the single owner of dependency changes, plugin resolution first per X8) and the Gradle files (`android/build.gradle*`, `android/settings.gradle*`, `android/gradle.properties`, `android/app/build.gradle*`) |
| R3 | `lib/features/recording/pipeline/**` (gate, gap detection, smoothing, auto-pause, distance, pace, elevation, summary builder; pure Dart, no I/O) |
| R4 | `lib/features/recording/state/**` (recorder state machine, battery monitor, orchestration providers, live metrics) |
| R5 | `lib/features/recording/journal/**` (journal records, flush policy, recovery, hand-off, lifecycle), read-only use of the S02 repository writer; `lib/core/wiring/activity_wiring.dart` only for the recorder hook (single splice: registers the pre-unbind hook that the bind controller awaits, bounded PROPOSED 5 s, Y2); S02 files whose ownership transfers to R5 for this sprint: `journal_generation_writer.dart`, `uid_scoped_activity_journal.dart`, `file_activity_journal.dart`, `journal_layout.dart` (gated isolate move, owner-scope pinning of every step, durable wiped-uid marker, `segmentBreak` frames; ARCH7, X2, Y3, Y4, Y7). Exact paths are read in the first step |
| R6 | `lib/features/workouts/state/active_session_status.dart` (prioritised sources or rewrite), `lib/shared/widgets/dock_widgets.dart`, `lib/shared/widgets/shell_dock.dart` if the strip needs it; Round 1: `record_sheet.dart` (GPS row replaced by Open recording during a recording, UX8) and `app_shortcuts.dart` (Record shortcut entry point) |
| R7 | `lib/features/recording/pages/**`, `lib/features/recording/widgets/**` (start, pause, stop, recovery, permission and denial screens; only screens in the approved S04-D) |
| R8 | localisation ARB files (path read in the first step) and `lib/features/recording/l10n/**`; consent store `lib/features/recording/consent/**`; privacy constants `lib/core/config/recording_defaults.dart`; the sanitiser `lib/features/recording/safety/**` (wrapper, content-free error types, Y4) |
| R9 | `lib/main.dart`, `lib/core/router/**`, `lib/shared/widgets/main_shell.dart` (one splice each: provider overrides, recovery gate at start, route registration), and the Settings page splice for the Privacy row (Y4) |
| R10 (conditional) | background-location request and educational UI under `lib/features/recording/permissions/background/**` (S04-18 branch B), notification-denied branch (S04-20); waits for R1 |
| R11 (docs, test inputs) | `docs/phase2/s04/S04_BATTERY_PROTOCOL.md`, `S04_DEVICE_LAB_RECORD.md` (S04-23, S04-29) |
| R13 (Round 1) | `activity_aware_local_data_wipe.dart` (wipe ordering and the injected hook interface between the repository-layer wipe and the recorder; the relaunch `finishInterruptedWipe` path runs without a recorder), `sign_out_guard.dart` (counts an active or unfinished recording; uses the same pre-unbind hook, Y2), `sign_out_warning_sheet.dart` (names the recording). S02 and S03 files; ownership transfers to R13 for this sprint. Exact paths are read in the first step |

Single source of ownership (Y4): this table is the only list of file owners for S04. The design cites it and does not keep its own list; a path missing here has no owner and the story that touches it is NOT READY (DoR item 6). Any path not named above and not under a lane glob is added here before work starts.
| R12 fixes | fixes forced by tests and reviews; started only after the other lanes close; each fix listed by file first, a file never claimed by two fixes (as S03 L12) |

| Lane | Stories, in order | Waits for |
|---|---|---|
| R1 | S04-01, S04-17 (service part), S04-19 (detection) | nothing; S04-D copy for screens |
| R2 | S04-04 (manifest, service, flag-gated entries), S04-15 (backup rules), S04-32 and S04-35 (native notification text), S04-36 (reduced interval request parameters), S04-37 (detach behaviour, native half) | R1 seam interface commit; platform study decision; the merged manifest resolved first; R8 notification keys |
| R3 | S04-05, S04-06, S04-07, S04-08, S04-09, S04-10 | S04-02 fixtures (test agents) |
| R4 | S04-03, S04-22, S04-34 (precondition state), S04-36 (pause interval and prompt state), S04-35 (stop reason event), S04-37 (detach state) | R3 interface commit (events); R5 journal-open API for S04-34 |
| R5 | S04-11, S04-12, S04-13, S04-14, S04-15, S04-16, S04-26 (isolate move), S04-30 (owner-pinned steps, sealed hand-off, 30-day fallback), S04-31 (decode sanitising) | R3, R4 interface commits; architect journal decision; tombstone ordering agreed with R13 |
| R6 | S04-24, record sheet and shortcut entry points of S04-24 AC-6 | architect source-list decision; R4 state API; R5 recovery-pending API |
| R7 | S04-25, S04-17 (screens), S04-19 and S04-22 (copy surfaces), S04-33 (withdraw switch screen), S04-34 (panels) | S04-D approved; R1, R4, R6, R8 interface commits |
| R8 | S04-21, S04-27 (log mapper), S04-28, S04-31 (wrapper and handler hooks), S04-33 (consent state), ARB keys for S04-32, S04-34, S04-35, S04-36 and S04-38 texts | R1, R5; key lists from R7 and R2 |
| R9 | wiring and routes for S04-25, S04-12, S04-33; `main_shell.dart` splice for the recovery gate and the Privacy row route | R5, R6, R7 page files exist; R13 guard API for sign-out wiring |
| R10 | S04-18 branch B, S04-20 | operator answer; R1 |
| R11 | S04-23, S04-29, S04-38 (release checklist document, owners and statuses) | reference phone (S04-29 only); operator for the Play Console rows |
| R13 | S04-30 (sign-out guard, warning sheet, wipe ordering) | R5 stop, seal and hand-off interface commit; R4 stop event; R9 for the auth wiring splice |

Parallelism (INFERENCE): R1, R3, R4 start together after the interface commits; R2 and R5 follow once the architect decisions land; R6, R7, R8 run in parallel when their waits are met; R9 last among build lanes; R12 after all. Critical path (INFERENCE): R3 pipeline, then R5 journal and recovery, then R9 wiring, then the epic test runs and S04-29 device-lab record. Collision points removed: `main.dart` and the router by R9 only; the strip provider by R6 only; the manifest by R2 only (R10 supplies request code, not manifest edits); ARB files by R8 only (R7 supplies key lists to R8, not edits); `pubspec.yaml` and Gradle files by R2 only (no other lane adds a dependency); `main_shell.dart` by R9 only (R6 supplies the record-sheet API, not edits); the wipe and the sign-out guard by R13 only (R5 supplies the shutdown and seal API); the S02 generation writer and uid-scoped journal by R5 only. Round 1 wait edges: R13 after R5 interface; R9 after R13 guard API; R6 after R5 recovery-pending API; R2 after R8 notification keys.

Test agents: after each epic the test-writing agents (`functional-test-reviewer`, `e2e-runner`, `tdd-guide`, `performance-optimizer` for S04-26) write and run the complete set: EP-A after R1, R2 (manifest), R4; EP-B and EP-C after R3; EP-D after R5; EP-E after R1, R8, R10; EP-F after R4; EP-G after R6, R7, R9; EP-H after R5, R8; EP-J after R2, R4, R5, R7, R8, R13 (S04-38 is reviewed, not tested); a final complete run after the last epic on the head to be approved. Findings go to `docs/phase2/s04/S04_TEST_FINDINGS_EPICn.md`. Each test agent uses a private output file name and runs are sequenced or in two waves (retro action 10).

## 10. Risks and open items for the product owner

1. Unverified platform behaviour (swipe-away, force-stop, notification denial, revocation callback, OEM killers): Study section 7 lists 10 NOT_RUN items; S04-04, S04-19, S04-20 and S04-29 carry them. Mitigation: platform study stays the first design input; stories report PASS, FAIL or NOT_RUN honestly.
2. Reference phone unknown: the DoD cannot close (A-2). Repo comments mention a Samsung S23 Ultra and an S8; whether either is the reference phone is UNKNOWN.
3. Package choice (maintained plugin, own channel, paid plugin) changes R2 and R5 size materially (Study Q4); size labels are INFERENCE until the architect decides.
4. Single journal writer versus a native writer (Study Q3) may force a change to S02 mutex semantics across isolates; UNKNOWN whether it already spans isolates.
5. Documentation not yet approved: S04-D, S04 design (drafts exist) and the test plan (not written); stories depending on them stay NOT READY. The content of P2-009 is UNKNOWN; if it contradicts S04-02 or S04-08 to S04-10, those stories are revised, not silently kept.
6. Open operator questions carried from Req section 13 (strip priority, barometer, notification denial, battery-optimisation request, battery-critical rule, journal expiry, long-gap recovery) each have a default in the stories above; answering differently changes the named story only.
7. Round 1 risks: GPS-PRIV-050 and 098 server enforcement is an entry condition and is UNKNOWN; engine-detach behaviour (S04-37) and `geolocator` after Activity destroy stay NOT_RUN until a reference phone is named; the release-gate rows need the operator for Play Console; S02 and S03 files transferred to S04 lanes (R5, R13) raise merge-risk, mitigated by single-owner rules.

## 11. Round 1 remediation log

Source: `docs/phase2/s04/S04_REVIEW_FINDINGS_ROUND1.md`, applied in one batch to this file only. Sizes remain INFERENCE.

| Item | Change in this file |
|---|---|
| X1 | New S04-30; S04-15 AC-1 reworded; S04-12 AC-5 |
| X2 | S04-30 AC-4 and AC-5; lanes R5 and R13 |
| X3 | Export marked out of scope (section 7, DoD 16); S04-13 AC-2, S04-19 AC-2, S04-21 AC-2, S04-25 AC-7 |
| X4 | New S04-33 |
| X5 | New S04-36 |
| X6 | New S04-32 and S04-35 |
| X7 | New S04-34; S04-12 AC-5 |
| X8 | S04-04 AC-1; lane R2 owns pubspec, Gradle and manifest; DoD 13 |
| X9 and X10 | S04-25 AC-5 to AC-7 |
| ARCH6 | New S04-37 (CONDITIONAL, default branch stated) |
| ARCH7 | Lane R5 owns the S02 generation writer and uid-scoped journal; no separate story (design owns the gate) |
| ARCH10 | Lane table: all listed files now have one owner and wait edges (R2, R5, R6, R8, R9, R13) |
| SEC4 | New S04-31; DoR item 7 entry condition (GPS-PRIV-050 and 098 enforcement); DoD 13 |
| SEC9 | New S04-38 with proposed owner; accepted risks AC-5 |
| UX1, UX3, UX7 | S04-12 AC-4, S04-19 AC-2, S04-34 AC-2 and AC-3 |
| Counts | Stories 29 to 38; conditional 3 to 4; DoR 6 to 8 items; DoD 12 to 16 items |

Not done here (belongs to other authors or later steps): UX and A11Y copy and layout fixes outside the listed ACs, the requirements text for S04-R-052 to -058, design changes for ARCH3 to ARCH5 and ARCH11, and ARCH12 to ARCH14 and the remaining MINOR items; they are carried to the owners of the design, contract and requirements. Open: whether the operator accepts the proposed S04-38 owners and the 30-day and 10 s and 30 min values (PROPOSED).

## 12. Round 2 remediation log (see also section 13)

Source: section 3 of `S04_REVIEW_FINDINGS_ROUND1.md` (decisions Y1 to Y11, findings K1 to K10 and minors); only items touching this file are applied. This is the last internal batch; the documents then go to the external gate.

| Item | Change in this file |
|---|---|
| Y1, K1 | S04-19 AC-2: Keep on a revoked recording = seal and hand off as a finished partial activity; Delete removes it; quarantine only for `recoveryFailed` |
| Y2, K2 | S04-30 AC-2: pre-unbind hook awaited by the bind controller (PROPOSED 5 s) with the 30-day fallback; AC-6 guard uses the same hook; R5 and R13 rows name the hook |
| Y3, K3 | S04-30 AC-2: bounded in-memory buffer (PROPOSED 120 s) and reason `account`; durable wiped-uid marker in the R5 row |
| Y4, K4 | Lane table declared the single source of ownership; added `file_activity_journal.dart` and `journal_layout.dart` (R5), `recording/safety/**` (R8), Settings page splice (R9); wipe hook interface and `finishInterruptedWipe` note (R13) |
| Y5, K5 | S04-34 AC-2: `preparing` to `cannotStart` 5 s, `startFailed` 15 s from the service-start call; S04-30 AC-6: "Sign out anyway" stays allowed |
| Y6, K6 | DoR item 7: precondition to start building R3 onwards unless the operator records a dated exception; also a release gate |
| Y7, Y8, Y9 | Design-only; no story change (the segment, delete-order and re-anchor rules are tested under S04-11, S04-14 and S04-05 by the test agents once the design is final) |
| Y10, K10 | S04-35 AC-1: set is battery, storage, sample cap, consent withdrawal; permission revoked keeps its own notification |
| Y11 | S04-32 AC-1 and AC-3, S04-35 AC-3: owner-visible versus generic version; tap opens recording screen, Finish opens stop panel, one reading |
| Stale lines | S04-11 AC-1 wording fixed; "S04-D not written" and "R-052..058 not read" lines replaced; S04-38 now cites requirements section 12 (it has no S04-R id) |
| Not done here | Contract items C1 to C8 and design items K7 to K9 belong to their authors; the 10 s manual-pause and 30 min values remain PROPOSED |

## 13. GPT-PM gate round 1 remediation log

Source: section 4 of `S04_REVIEW_FINDINGS_ROUND1.md` (head 535ae9e4, verdict MODIFY, 3 MAJOR, 1 MINOR); only items touching this file are applied.

| Item | Change in this file |
|---|---|
| Z1 (M1) | S04-12 AC-2 reworded and new AC-6: Resume enters `acquiring` for every origin, pause origin preserved, `restart` gap pair, recovery from both paused states asserted |
| Z2 (M2) | S04-19 AC-1 (collection stops), new AC-1b (durable SEALED pending-decision state `permissionRevoked`), AC-2 (hand-off on Keep, ordered delete on Delete), new AC-4 (fault injection at revocation, seal, process death, Keep, hand-off, Delete; one consistent state, no duplicate); stale name `stoppedRevoked` not used |
| Z3 (M3) | S04-30 AC-2 (strict path: hand-off then delete), AC-3 (30-day fallback only on failed hand-off, user told, amends S01 GPS-PRIV-014 as a PROPOSED clarification, strict deletion is the alternative), new AC-8 (six lifecycle rows: successful hand-off, failed hand-off, explicit sign-out, account deletion, expiry, subsequent sign-in); S04-15 AC-1 wording aligned |
| Z4 (m1) | Test-plan item, not this file |
| Z7 (verification round 2, MAJOR) | S04-19 AC-5 reworded (one exclusive-create `DECISION` arbiter, fsync file then directory, `DISCARDING` is only a DELETE progress marker); new AC-9 (loser does nothing irreversible), AC-10 (forced two-writer interleaving), AC-11 (empty or torn file), AC-12 (malformed combinations quarantined). AC-9 to AC-12 sit before AC-8 in the file; ids are kept. The test-plan map (Z6) must add them |
| Z5 (verification round, MAJOR) | S04-19 new AC-5 to AC-8: durable `DECISION` marker, first decision wins, replay is a no-op, Delete not offered after Keep is durable and never removes the hand-off's S02 activity, recovery by marker, crash and concurrent injection before `put`, after `put` and before cleanup. S04-13 does not apply (its Keep is quarantine with no hand-off). Z6 (story-to-rows map) is a test-plan item; the new ids are S04-12 AC-6 and S04-19 AC-1b, AC-4 to AC-8 |
| Open | The Z3 amendment and the 30-day value are the operator's to confirm (default applied) |
