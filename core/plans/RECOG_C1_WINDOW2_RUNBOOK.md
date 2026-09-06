# RECOG-C1 — window 2 runbook

Window 2 is the second half of the baseline: 52 observations, 26 pairs, UTC day **2026-09-07**.
It cannot run on 09-06 — window 1 already spent 52 of that day's 60 calls
(`QUOTAS.aiEquipmentRecognition`, enforced before the model call in
`functions/src/ai_equipment_recognition.ts:124-128`).

This file exists so tomorrow's run does not re-derive what today's run already paid for. Every step
below has a stated way to know it worked, because on 2026-09-05 a step that reported success had in
fact done nothing, and nothing downstream noticed for a day.

## Before anything

| | |
| --- | --- |
| device | `ce02171299f0711005` (Galaxy S8, arm64-v8a) |
| package | `com.fitnessapp.fitness_app.sptr.debug` |
| adb | `D:\android-sdk\platform-tools\adb.exe` |
| remote dir | `/sdcard/Android/data/com.fitnessapp.fitness_app.sptr.debug/files/recog_c1` |
| window 1's raw file | `core/plans/recog_c1_raw/recog_c1_raw_w1.jsonl`, sha256 `556480993b8de6d1308031f4a5b4b4d028bad8c98a223b4c35c8f2fd87e0f989` |

**Wait for the UTC boundary.** Not "roughly tomorrow" — a run started before `00:00Z` splits its
observations across two quota days and leaves window 2 short. Check with
`date -u`, not local time.

    date -u '+%Y-%m-%dT%H:%M:%SZ'

## 1. Provenance, with no device attached

    pwsh -NoProfile -Command "& scripts/dev/recog_c1_deploy.ps1 -VerifyOnly -RunId w2"

Passes only when the working tree is clean AND the local run plan matches the hash in
`core/plans/RECOG_C1_FREEZE_MANIFEST.json` **as committed** (read via `git show HEAD:`, never from
the working copy — a plan that hashes itself proves nothing).

## 2. Push the images and the plan for window 2

    pwsh -NoProfile -Command "& scripts/dev/recog_c1_deploy.ps1 -Push -Window 2 -RunId w2"

Window 1's images are already on the device; the push is idempotent.

## 3. Build

    flutter build apk --debug --split-per-abi \
      --dart-define=RECOG_C1_HARNESS=true \
      --dart-define=RECOG_C1_DIR=<remote dir> \
      --dart-define=RECOG_C1_RUN_ID=w2 \
      --dart-define=RECOG_C1_WINDOW=2 \
      --dart-define=RECOG_C1_PLAN_SHA=4f4ef743734ce710e6e82e968db41a4c682af1f230f2c8ff2aad0d6b9828325d \
      --dart-define=RECOG_C1_SOURCE_SHA=$(git rev-parse HEAD)

`--split-per-abi` is not optional. Without it the APK is 423 MB, `/data` is 98 % full, and the
install fails with `INSTALL_FAILED_INSUFFICIENT_STORAGE` — which on 2026-09-05 surfaced as exit code
0 and no output. `--target-platform android-arm64` does **not** substitute: it governs only the
Flutter engine's libraries, and unpacking showed all four ABIs still present.

Every `--dart-define` is required. The harness refuses to start without them rather than defaulting
to all 104 observations in one 60-call day. **No token value appears in this command or anywhere in
the log.**

## 4. Install, and prove it landed

    pwsh -NoProfile -Command "& scripts/dev/recog_c1_deploy.ps1 -Install <path to apk> -RunId w2"

The script requires the package manager's own `lastUpdateTime` to move and throws otherwise. `adb
install` printing `Success` is not evidence — that exact output accompanied a build that never
installed.

## 5. Run

Launch the app. The harness runs from `main()`. Watch for `RECOG-C1` lines in logcat.

**Silence is ambiguous and must be treated as failure.** `kEnabled` is compile-time false in a build
without the defines, so the branch is removed and there is nothing left to print: "no RECOG-C1 lines"
means "the harness refused" and "the harness is not in this build" equally. If nothing appears within
a minute, go back to step 4 rather than waiting.

Expect roughly six observations a minute, so about nine minutes.

**Relaunching is safe.** Rows already written for a run id are skipped, so a restart resumes rather
than repeating. That is also why the run id must be `w2`: reusing `w1` would find 52 rows already
done and do nothing at all.

## 6. Pull

    pwsh -NoProfile -Command "& scripts/dev/recog_c1_deploy.ps1 -Pull -RunId w2"

It reports observations counted by record type, plus any `attempt_started` marker with no matching
observation. A marker without an observation is an attempt that may have spent quota and whose
outcome nobody knows — it is never absorbed into a total. Copy the file to
`core/plans/recog_c1_raw/recog_c1_raw_w2.jsonl` and commit it.

Expected: 52 observations, 52 markers, 0 orphaned.

## 7. Compute the baseline — both windows together

    cd mobile
    RECOG_C1_RAW=<w1 path>,<w2 path> \
    RECOG_C1_GT=core/plans/RECOG_C1_GROUND_TRUTH_2026-09-05.csv \
    RECOG_C1_PLAN=core/plans/RECOG_C1_RUN_PLAN_2026-09-05.csv \
    RECOG_C1_OUT=core/plans/RECOG_C1_MEASUREMENT_2026-09-05.md \
    flutter test test/tools/recog_c1_compute_metrics.dart

Both raw files, comma-separated. With only one the script correctly reports the run as short of its
plan — useful as a check, useless as a baseline.

It stops rather than continues on: a reconstruction mismatch (the device and the analysis disagreeing
about what the model said), a duplicate observation id, an unparseable line, ground truth missing for
an observation, an unknown `gt_kind`, or pair accounting that does not add up. Each of those would
otherwise produce a number that looks fine and is false.

## 8. Step 10

Revert the harness, prove the tree is byte-identical to its pre-harness state, and write the
measurement document and the final report. The harness is debug-only and compile-gated, but "it
cannot run in release" is a weaker claim than "it is not in the tree".

## What window 1 already showed, so it is not rediscovered

- 52/52 observations, one session, all 26 pairs intact, zero operational failures, zero transport
  errors, the frozen plan's hash on every row.
- Frames holding one catalogue machine: 16 resolved rows, 16 correct and confident.
- Frames holding several machines with no single subject: 34 rows, 32 answered confidently with a
  single machine anyway.
- The two arms matched on every count, so the viewfinder crop moved nothing in window 1.

None of that is the baseline. It is half the corpus, and window 2 is the other half.

## Open, and not for this run to settle

The identity of the Star Trac plate-loaded unit in photographs #15, #29 and #47 is frozen
`unresolved` and excluded from every accuracy metric in both directions. It is a question for the
operator, not a blocker.
