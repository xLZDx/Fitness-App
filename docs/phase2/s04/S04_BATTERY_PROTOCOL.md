# S04 battery protocol (story S04-23, requirement S04-R-028)

Status: DRAFT, 2026-10-17, branch `phase2/s04`. Documentation only: no command was run, no device was used, no run was made. Every result field in this document is an empty template and reads NOT_RUN. Paths are relative to the repository root.

Sources read: `docs/phase2/s04/S04_STORIES.md` (S04-23, S04-29, S04-22), `S04_TEST_PLAN.md` sections 5.1 to 5.3 (rows DT-23-1, DT-23-2, DL-3, DL-3b, DL-9), `S04_DESIGN.md` section 8 and section 2.6, `S04_ANDROID_PLATFORM_STUDY.md` sections 3.11, 5 and 7.

Tags: FACT (read in a cited file), INFERENCE (drawn from facts; the premise is named), PROPOSED (a number or rule not yet accepted), UNKNOWN (not established), NOT_RUN (needs the device and was not done; never PASS without an artifact).

## 1. Purpose and reader

This document fixes how battery drain of the S04 recorder is measured, so that a drain number is comparable between runs and cannot be produced by accident. It is written for the person who carries the phone (the operator or a delegate) and for the reviewer who decides whether a run record is evidence. The results go into `docs/phase2/s04/S04_DEVICE_LAB_RECORD.md`; this file contains no results.

Target (PROPOSED, S04-R-029): at most 8 percent battery per hour with the screen off while recording. A result above the target is recorded as FAIL, not hidden; the product-owner then decides accept, tune or defer.

## 2. Reference phone (operator decision, 2026-10-17)

The reference phone is the operator's Samsung Galaxy S8. It is permanently connected to the development machine. Consequences recorded here so the protocol does not hide them:

1. Old Android. INFERENCE (premise: the S8 shipped with Android 8.0 and is not known to receive Android 10 or later from the vendor; the actual version is UNKNOWN until read from the phone and recorded in the run header). Battery-saver, standby and vendor task-killer behaviour on this phone can differ from newer phones, so a number measured here does not transfer to a newer phone. Each run record names the phone model and the exact Android version.
2. Always connected to the dev machine. A USB cable charges the phone and invalidates any battery number (section 5, rule 4). Every measured run needs a documented way to run unplugged (section 6). A run that was plugged in at any moment is rejected.
3. Aged battery. INFERENCE (premise: the phone is several years old; battery health is UNKNOWN). Capacity loss changes percent per hour. The record states the battery state if the phone reports it, and the control run (section 5, rule 5) is mandatory so that recording drain is separated from background drain.
4. Platform features older than the S04 design assumes cannot be exercised on this phone, so the related device rows stay NOT_RUN until a second, newer phone exists. From the Study: the notification runtime permission and the Task Manager stop are Android 13 and later (Study 3.11, 5.8). INFERENCE: the approximate-location choice is also newer than the S8's Android. These rows are listed in `S04_DEVICE_LAB_RECORD.md` section 4.
5. The 8 percent target was written before any phone was named. It is not re-set by this document. Re-setting happens only from a measured baseline on this phone, in a separate recorded decision of the product-owner.

## 3. Scope

In: the recorder's drain with the screen off, on foot and on a bike, with no map and no network use by the app. Out: drain with the screen on, drain of any map or upload feature (none exists in S04), heart-rate sensors, iOS.

## 4. Run types and counts

| Run type | Duration | Minimum runs (PROPOSED) | Matching test row |
|---|---|---|---|
| walk | 60 min | 2 | DL-3, DT-29-3 |
| ride | 60 min | 2 | DL-3b, DT-29-4 |
| control, per run type | same duration and conditions, app installed, not recording | 1 per run type | rule 5 below |

Both values of the two runs are reported, not an average alone (S04-R-029). Fewer than the minimum runs leaves the status of that type at NOT_RUN.

## 5. Rules for a valid run

A run record is accepted as evidence only if every rule holds and every field of section 7 is filled. A record missing any field, or any rule broken, is rejected (S04-23 AC-2; test DT-23-2).

1. Phone and build. Phone model and Android version are read from the phone. The app build id and the git head of the build are recorded. A record without the head cannot prove anything (S04-29 AC-3).
2. Run type and duration. Walk or ride, 60 minutes (PROPOSED). The route is described in words (no coordinates are written into the record).
3. Screen off for the whole run. The phone is in a pocket or mounted. No other app is in the foreground. The same system location mode is kept for all runs of a series. Recording is started from the visible app, then the screen is switched off.
4. No charger and no USB. The phone is not plugged in at any moment, including a data cable to the dev machine, because a cable charges the phone. Start and end battery percent are read from the system, not estimated. Whole-percent resolution is coarse for one hour, so the record also stores the charge counter in microampere-hours before and after (PROPOSED), read through the platform battery property, and the system battery statistics when available. Do not use any command or setting that fakes a battery or charging state for a measured run.
5. Control run. One run of the same type and duration with the app installed and not recording, to separate recording drain from background drain (PROPOSED).
6. Start level. At least 80 percent at the start, and the time the phone was unplugged before the run is recorded.
7. Conditions. Temperature if known; network state (airplane, Wi-Fi, cellular); a weather note.
8. Recorder settings and counters. The request interval, flush interval and auto-pause setting used; the sample, reject and gap counters of the run (counts only, no coordinates; from the debug-only run log of the design, section 8.2).
9. Result. Percent per hour, the 8 percent target, and the status PASS, FAIL or NOT_RUN. PASS needs a linked artifact (a screenshot or exported statistics file kept outside git, referenced by name and date). Missing artifact means NOT_RUN.
10. Vendor background-kill entry. Whether the phone's own battery manager ended or restricted a screen-off run, yes or no, and the manager settings in force (S04-R-031). The app does not request a battery-optimisation exemption (design D-16, default; Study 5.7).

## 6. Running unplugged while the phone is the dev-machine device

The phone is permanently connected, so the unplugged state must be created on purpose for each measured run. Options, to be chosen and written into the run record by the run owner. None was tried; the exact commands are not fixed here because they have not been verified on this phone (UNKNOWN).

| Option | Idea | Caveat |
|---|---|---|
| A. Wireless debugging or adb over the network, then unplug | The adb session continues over Wi-Fi and the cable is removed for the run. Check the phone's own wireless debugging setting on its Android version before the run | Wi-Fi must stay on for the whole run, which changes network state and drain; record it as the network state |
| B. No adb during the run | Disconnect the cable, run, reconnect after; read start and end values by hand from the system battery screen and read the charge counter after reconnecting | Counters and logs from the debug run log are read after the run, not during |

A run is rejected if the record cannot state which option was used and that the cable was removed before the start reading and stayed removed until the end reading.

## 7. Required fields of a run record

These are the field names checked by tests DT-23-1 and DT-23-2. Names are exact; a missing or empty field rejects the record. Result fields stay empty until a run exists.

| Field | Meaning | Value in this document |
|---|---|---|
| `device_model` | phone model | empty (reference: Samsung Galaxy S8, per operator decision) |
| `android_version` | version read from the phone | empty |
| `build_head` | build id and git head | empty |
| `run_type` | walk, ride or control | empty |
| `duration_min` | minutes | empty |
| `screen_off` | yes or no for the whole run | empty |
| `carry` | pocket or mounted | empty |
| `no_charger` | yes or no, including USB; plus the option A or B of section 6 | empty |
| `battery_start_percent` | read from the system | empty |
| `battery_end_percent` | read from the system | empty |
| `charge_counter_start` | microampere-hours | empty |
| `charge_counter_end` | microampere-hours | empty |
| `control_run` | reference to the matching control run | empty |
| `temperature` | if known | empty |
| `network_state` | airplane, Wi-Fi or cellular | empty |
| `recorder_settings` | request interval, flush interval, auto-pause | empty |
| `counters` | sample, reject, gap counts | empty |
| `percent_per_hour` | computed result | empty |
| `target` | 8 (PROPOSED) | 8 |
| `status` | PASS, FAIL or NOT_RUN | NOT_RUN |
| `oem_kill_entry` | yes or no and the manager settings | empty |

Computation: percent per hour is (start percent minus end percent) divided by duration in hours. When the charge counter is available, also report counter delta per hour; if the two disagree by more than the coarse resolution explains, say so in the record and do not choose the better-looking one.

## 8. Decisions after a result

| Outcome | Record | Next step |
|---|---|---|
| at most 8 percent per hour with all fields | PASS with artifact | none |
| above 8 percent | FAIL, value shown | the product-owner decides accept, tune or defer; the decision is recorded in the device-lab record |
| a rule broken or a field missing | rejected, status NOT_RUN | repeat the run |
| no run made | NOT_RUN | the sprint can be coded and reviewed but the DoD "battery recorded on the operator's phone" stays open (Stories section 6) |

## 9. Link to behaviour under test

The battery-critical behaviour (slower sampling at or below 10 percent, finish at or below 3 percent while not charging) is a code behaviour tested with a fake battery (S04-22, rows in the test plan); this protocol measures drain, not that behaviour. A device check of the automatic-stop notification with the screen off is DL-13 in the test plan and is listed in the device-lab record.

## 10. Open items

1. Battery health and exact Android version of the S8 are UNKNOWN until read.
2. The unplugged method (section 6) is not chosen.
3. Whether 8 percent per hour is realistic on this phone is UNKNOWN; no baseline exists.
4. The vendor battery-manager names and settings of this phone are UNKNOWN and are recorded from the phone itself, not from community lists.
