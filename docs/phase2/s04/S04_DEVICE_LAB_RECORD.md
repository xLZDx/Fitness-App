# S04 device-lab record (story S04-29, requirements S04-R-029, -031, -051)

Status: TEMPLATE, 2026-10-17, branch `phase2/s04`. Nothing in this file was measured. Every status below is NOT_RUN. No cell may be changed to PASS without a linked artifact (rule R-2). Paths are relative to the repository root.

Sources read: `docs/phase2/s04/S04_STORIES.md` (S04-29, S04-04 AC-5, S04-11 AC-5, S04-19 AC-3, S04-32 AC-4, S04-37), `S04_TEST_PLAN.md` sections 3.9, 5 and 6, `S04_DESIGN.md` section 2.6 (tests T1 to T6), `S04_ANDROID_PLATFORM_STUDY.md` section 7. Method of the drain runs: `docs/phase2/s04/S04_BATTERY_PROTOCOL.md`.

## 1. Rules of this record

- R-1. Allowed statuses: PASS, FAIL, NOT_RUN. Missing evidence is NOT_RUN, never PASS (S04-29 AC-2).
- R-2. A PASS needs an Artifact reference (file name and date of a screenshot, screen recording or exported statistics kept outside git, or a test output). An empty Artifact cell with PASS is invalid (test DT-29-10, `/no-pass-without-artifact`).
- R-3. A FAIL against the drain target is recorded as it is; the product-owner decides accept, tune or defer (S04-29 AC-2).
- R-4. This record names the head it proves (S04-29 AC-3). A result for another head does not count; a new commit that touches the recorder invalidates the results listed against the old head until re-run or explicitly re-confirmed.
- R-5. No coordinates, no place names and no personal data are written here.
- R-6. iOS rows read NOT_RUN; no iOS claim is made (S04-28 AC-4).
- R-7. The app does not request a battery-optimisation exemption in the runs (S04-29 AC-4); if a run used one, the run is marked and the product-owner is told.

## 2. Header

| Field | Value |
|---|---|
| Reference phone | Samsung Galaxy S8 (operator decision recorded 2026-10-17; permanently connected to the dev machine) |
| Android version read from the phone | (empty) |
| One UI or vendor build | (empty) |
| Battery state of the phone, if reported | (empty) |
| App build id | (empty) |
| Git head proved by this record | (empty) |
| Build flavour and flag state (for example recorder flag on, debug build) | (empty) |
| Date of the session | (empty) |
| Run owner | (empty) |
| Second phone (newer Android), if any | (empty; none named) |

Reference-phone consequences (INFERENCE; the premises are in the battery protocol section 2): the phone has old Android, so battery-saver and standby behaviour differs from newer phones; a cable charges it, so measured runs need a documented unplugged method; some platform features of newer Android versions cannot be exercised on it (section 4).

## 3. Summary of the seven required items (S04-29 AC-1)

| # | Item | Story or row it closes | Status | Artifact | Notes |
|---|---|---|---|---|---|
| 1 | Device and OS | header | NOT_RUN | none | filled when the header is read from the phone |
| 2 | Build id and head | header | NOT_RUN | none | |
| 3 | Kill survival | S04-11 AC-5; DL-4; test T2 | NOT_RUN | none | |
| 4 | Screen-off continuity | S04-04 AC-5; DL-3; test T1 | NOT_RUN | none | |
| 5 | Tolerance, walked known route and ridden known route | S04-08 to S04-10; DL-1, DL-2 | NOT_RUN | none | |
| 6 | Battery runs against the 8 percent per hour target (PROPOSED) | S04-29 AC-1; DL-3, DL-3b | NOT_RUN | none | method in the battery protocol |
| 7 | OEM background-kill result | S04-R-031; DL-9 | NOT_RUN | none | |

## 4. Device rows

Status column: NOT_RUN for all rows. The column "Reachable on the S8" is an INFERENCE from the platform facts in the Study (the notification permission dialog and Task Manager stop are Android 13 and later: Study 3.11, 5.8); it must be confirmed once the S8's Android version is read. "Needs newer phone" means the row cannot be answered on the S8 and stays NOT_RUN until a second phone is named.

| Id | What is measured | Method summary (full text in the test plan, section 5.1) | Pass criterion (PROPOSED) | Test rows | Reachable on the S8 | Status | Artifact | Result notes |
|---|---|---|---|---|---|---|---|---|
| DL-1 | distance, pace, ascent tolerance, walked known route | known route 2 to 5 km, length method written here; phone in pocket then in hand | distance within 2 percent; ascent per DT-10 tolerance | DT-29-1 | yes | NOT_RUN | none | route length method: (empty) |
| DL-2 | same, ridden known route | phone mounted | same | DT-29-2 | yes | NOT_RUN | none | |
| DL-3 | screen-off continuity, notification, location indicator, fix interval, drain (walk) | start from visible app, screen off, 60 min, then Stop and read the indicator | no gap over 10 s without a recorded cause; notification present; median fix interval 0.9 to 1.5 s; drain at most 8 percent per hour | DT-04-8 to DT-04-10, DT-29-3, DT-29-7 | yes | NOT_RUN | none | |
| DL-3b | drain (ride) | same on a ride | same | DT-29-4 | yes | NOT_RUN | none | |
| DL-4 | kill survival | during recording: `adb shell am kill`, swipe from recents, phone restart; `adb shell cmd activity stop-app <package>` is a newer-Android command | everything flushed before the kill is offered; loss at most about 5 s | DT-11-16 | partly (stop-app is Android 13 and later) | NOT_RUN | none | per method: am kill (empty), swipe (empty), restart (empty), stop-app (empty) |
| DL-5 | permission revoked mid-recording | revoke location in system settings while recording; record latency and whether the process restarts | latency recorded; no re-request | DT-19-8 | yes | NOT_RUN | none | |
| DL-6 | notification permission denied | deny on Android 13 or later; does the service keep running | outcome recorded in the Study | DT-20-6 | needs newer phone | NOT_RUN | none | |
| DL-7 | airplane mode | location on, network off, record 10 min, save | a saved track | DT-29-6 | yes | NOT_RUN | none | |
| DL-8 | 100 000-sample budget in profile mode | open, seal, finish, summarise the F-100k fixture | max frame build 16 ms; seal plus open 3 s; extra memory under 100 MB | DT-26-7 | yes (the old phone is a slow-end data point) | NOT_RUN | none | |
| DL-9 | vendor task killer | read the result of DL-3 and DL-4 on the phone's own battery manager | recorded per run | DT-29-5 | yes | NOT_RUN | none | see section 5 |
| DL-10 | Doze during a stationary auto-pause | `adb shell dumpsys deviceidle force-idle`, `am set-inactive` while paused auto | fix cadence recorded | DT-29-8 | yes (Doze exists from API 23, Study 5.1) | NOT_RUN | none | |
| DL-11 | merged manifest of a built APK | inspect build artifact | equals the approved list | DT-04-11 | not a phone item (needs a build) | NOT_RUN | none | |
| DL-12 | lock-screen content of the recording notification | photo or screen record, lock-screen notifications set to show all and to hide sensitive | generic text only on the public version | DT-32-6 | yes | NOT_RUN | none | |
| DL-13 | automatic-stop notification with the screen off | screen-off run auto-finished at the battery threshold | reason, time and distance shown | DT-35-5 | yes | NOT_RUN | none | |
| DL-14 | TalkBack walk and numeral contrast | journeys JP-1, JP-8, JP-9, JP-11, JP-12 with TalkBack; live numerals against 7:1 | every task completes | DT-25-52, DT-25-53 | yes | NOT_RUN | none | |
| DL-15 | approximate to precise downgrade | approximate only, then Precise in settings, return to the recording start screen | continues without a new request | DT-17-21 | needs newer phone (INFERENCE) | NOT_RUN | none | |
| DL-16 | engine detach (test T2, conditional on story S04-37) | start, swipe the app away, wait 60 s; are samples still journaled and what does the notification say | the notification claim equals the true recorder state | DT-37-3 | yes | NOT_RUN | none | default branch of S04-37 applies while NOT_RUN |

The file-level validator test (DT-29-10) checks sections 2, 3 and 4 of this record; the exemption scan (DT-29-11) is a source scan, not a device row.

## 5. OEM background-kill entry (S04-R-031)

| Field | Value |
|---|---|
| Did the phone's own battery manager end a screen-off run | (empty) |
| Which run | (empty) |
| Manager name and settings in force (read from the phone; community lists are not a source) | (empty) |
| Was a battery-optimisation exemption requested by the app | no (default; S04-29 AC-4) |
| Status | NOT_RUN |

## 6. Tolerance results (items DL-1, DL-2)

| Route | Surveyed length and method | Recorded distance | Error percent | Ascent expected and recorded | Pace window result | Status | Artifact |
|---|---|---|---|---|---|---|---|
| walked | (empty) | (empty) | (empty) | (empty) | (empty) | NOT_RUN | none |
| ridden | (empty) | (empty) | (empty) | (empty) | (empty) | NOT_RUN | none |

No coordinates are recorded here.

## 7. Battery run table (one row per run; fields as in the battery protocol, section 7)

| run_type | duration_min | battery_start_percent | battery_end_percent | charge_counter_start | charge_counter_end | percent_per_hour | target | no_charger and unplugged option | control_run | status | Artifact |
|---|---|---|---|---|---|---|---|---|---|---|---|
| walk, run 1 | (empty) | (empty) | (empty) | (empty) | (empty) | (empty) | 8 (PROPOSED) | (empty) | (empty) | NOT_RUN | none |
| walk, run 2 | (empty) | (empty) | (empty) | (empty) | (empty) | (empty) | 8 (PROPOSED) | (empty) | (empty) | NOT_RUN | none |
| walk, control | (empty) | (empty) | (empty) | (empty) | (empty) | (empty) | n/a | (empty) | n/a | NOT_RUN | none |
| ride, run 1 | (empty) | (empty) | (empty) | (empty) | (empty) | (empty) | 8 (PROPOSED) | (empty) | (empty) | NOT_RUN | none |
| ride, run 2 | (empty) | (empty) | (empty) | (empty) | (empty) | (empty) | 8 (PROPOSED) | (empty) | (empty) | NOT_RUN | none |
| ride, control | (empty) | (empty) | (empty) | (empty) | (empty) | (empty) | n/a | (empty) | n/a | NOT_RUN | none |

The remaining fields (`device_model`, `android_version`, `build_head`, `screen_off`, `carry`, `temperature`, `network_state`, `recorder_settings`, `counters`, `oem_kill_entry`) are kept per run in an attached run sheet that copies the field list of the battery protocol; a row here without its run sheet is NOT_RUN.

## 8. Decision log for FAIL results

| Item | FAIL value | Product-owner decision (accept, tune, defer) | Date |
|---|---|---|---|
| (none recorded) | | | |

## 9. Closing statement

Accepted for code: not applicable until a head is named. DoD item "tolerance and battery recorded on the operator's phone": open (NOT_RUN). Current honest summary: no device measurement exists. The sprint can be coded and reviewed; the story S04-29 stays NOT_RUN until the rows above carry artifacts.
