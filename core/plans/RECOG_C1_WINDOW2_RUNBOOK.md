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

    cd D:\Repo\Fitness_App
    .\scripts\dev\recog_c1_deploy.ps1 -VerifyOnly -RunId w2

Passes only when the working tree is clean AND the local run plan matches the hash in
`core/plans/RECOG_C1_FREEZE_MANIFEST.json` **as committed** (read via `git show HEAD:`, never from
the working copy — a plan that hashes itself proves nothing).

## 2. The images — already done, and here is how to confirm it

**Window 2 needs 26 entirely different images per arm.** Checked against the frozen plan: the two
windows share zero `image_id`, and `pair_id` is globally unique (p00–p25 in window 1, p26–p51 in
window 2). So this is a real step, not the formality an earlier draft of this file implied.

**They were pushed and verified on 2026-09-06**, deliberately early, because `-Push` reads the corpus
from `-WorkDir`, which defaults to the SESSION scratchpad that produced it:

    D:\Temp\claude\d--Repo\5c302c91-31c2-4e5a-8695-d3eb4d063e24\scratchpad\recog_c1

Tomorrow's session has a different scratchpad path, so a `-Push` run then would have thrown
`missing image directory` at 00:00Z with the quota window open and nothing to measure. If a push IS
needed again, pass that absolute path as `-WorkDir`.

Confirm what the device holds, which costs nothing and takes seconds:

    cd D:\Repo\Fitness_App
    .\scripts\dev\recog_c1_deploy.ps1 -VerifyDevice -Window 2 -RunId w2

It hashes every image **on the device** and compares against the plan's `transformed_sha256`, and
checks the device's `run_plan.csv` against the committed freeze manifest. Expected output:
`device verified: 52 images match the plan's hashes`. A byte count from `adb push` describes what was
sent; this describes what arrived. Proved capable of failing: corrupting one device-side image by a
single byte makes it name that file and stop.

## 3. Build

    cd D:\Repo\Fitness_App\mobile
    flutter build apk --debug --split-per-abi `
      --dart-define=RECOG_C1_HARNESS=true `
      --dart-define=RECOG_C1_DIR=/sdcard/Android/data/com.fitnessapp.fitness_app.sptr.debug/files/recog_c1 `
      --dart-define=RECOG_C1_RUN_ID=w2 `
      --dart-define=RECOG_C1_WINDOW=2 `
      --dart-define=RECOG_C1_PLAN_SHA=4f4ef743734ce710e6e82e968db41a4c682af1f230f2c8ff2aad0d6b9828325d `
      --dart-define=RECOG_C1_SOURCE_SHA=$(git rev-parse HEAD) `
      --dart-define=APP_CHECK_DEBUG_TOKEN=$env:APP_CHECK_DEBUG_TOKEN

**The sixth define, and the thing that actually cost two runs on 2026-09-07.** App Check is enforced
on the AI callables (`APP_CHECK_ENFORCED_AI`, fail-closed), and a debug build takes its App Check
token from this define at build time. When the client cannot obtain an attestation token it sends an
error placeholder; the backend logs `Decoding App Check token failed` and refuses the call as
`unauthenticated` — a message that mentions neither App Check nor the build, while the log line right
above it says the user IS signed in.

Window 1 nonetheless ran with only five defines and verified `app=VALID` server-side, because the
device still held a persisted debug secret that the Android provider reuses when a build supplies
none. That store is gone from the device now, so the define is genuinely required — but "window 1
did not need it" is exactly why a check for mere presence is not enough.

**What failed twice was not an absent token but a value that was never a token.** The string recorded
in `core/DECISION_LOG.md` is a debug token's RESOURCE ID: the App Check API names a token
`projects/../apps/../debugTokens/<base64 id>`, and that id is an unrelated server-generated UUID, so
an id looks exactly as much like a credential as the credential does. The value is returned only when
the token is created and cannot be recovered from the id afterwards. Firebase answers
`403 App attestation failed`, correctly, and the device reports only `unauthenticated`.

`recog_c1_window2.ps1` now **exchanges the token against `firebaseappcheck.googleapis.com` before it
builds anything** and refuses on anything but `200`. It costs no AI quota — that is App Check's own
API, not a callable — and it fails on all three previously "registered" values while passing on a
freshly minted one, which is how it is known to discriminate rather than merely to run.

The value is never echoed, logged or committed. Set it in the environment before running.

This machine's shell is PowerShell: the continuation character is a backtick, not a backslash, and
an earlier draft of this file used backslashes, which would have made every `--dart-define` after the
first one vanish -- producing a build the harness refuses to start rather than one that measures the
wrong thing, but still a wasted build.

`--split-per-abi` is not optional. Without it the APK is 423 MB, `/data` is 98 % full, and the
install fails with `INSTALL_FAILED_INSUFFICIENT_STORAGE` — which on 2026-09-05 surfaced as exit code
0 and no output. `--target-platform android-arm64` does **not** substitute: it governs only the
Flutter engine's libraries, and unpacking showed all four ABIs still present.

Every `--dart-define` is required. The harness refuses to start without them rather than defaulting
to all 104 observations in one 60-call day. **No token value appears in this command or anywhere in
the log.**

## 4. Install, and prove it landed

    cd D:\Repo\Fitness_App
    .\scripts\dev\recog_c1_deploy.ps1 -Install mobile\build\app\outputs\flutter-apk\app-arm64-v8a-debug.apk -RunId w2

`--split-per-abi` names the output per ABI; the device reports `arm64-v8a`, so that is the one file
of the three that matters. Do NOT install `app-debug.apk` -- that is the 423 MB fat build the device
has no room for.

The script requires the package manager's own `lastUpdateTime` to move and throws otherwise. `adb
install` printing `Success` is not evidence — that exact output accompanied a build that never
installed.

## 5. Run

    $adb = 'D:\android-sdk\platform-tools\adb.exe'
    $dev = 'ce02171299f0711005'
    & $adb -s $dev shell am start -n com.fitnessapp.fitness_app.sptr.debug/com.fitnessapp.fitness_app.MainActivity

Progress, without tailing a log (the file is the source of truth, not the console):

    & $adb -s $dev shell "grep -c '\"record_type\":\"observation\"' /sdcard/Android/data/com.fitnessapp.fitness_app.sptr.debug/files/recog_c1/recog_c1_raw_w2.jsonl"

The pattern has no space after the colon because `jsonEncode` writes none -- a pattern with a space
returns 0 on a perfectly healthy file, which is how a working run first looked like a dead one.

The harness runs from `main()`. `RECOG-C1` lines also appear in logcat.

**Silence is ambiguous and must be treated as failure.** `kEnabled` is compile-time false in a build
without the defines, so the branch is removed and there is nothing left to print: "no RECOG-C1 lines"
means "the harness refused" and "the harness is not in this build" equally. If nothing appears within
a minute, go back to step 4 rather than waiting.

Expect roughly six observations a minute, so about nine minutes.

**Relaunching is safe.** Rows already written for a run id are skipped, so a restart resumes rather
than repeating. That is also why the run id must be `w2`: reusing `w1` would find 52 rows already
done and do nothing at all.

## 6. Pull

    cd D:\Repo\Fitness_App
    .\scripts\dev\recog_c1_deploy.ps1 -Pull -RunId w2 -OutDir D:\Repo\Fitness_App\core\plans\recog_c1_raw

`-OutDir` is given explicitly so the file lands where it is committed from. Its default is the
scratchpad of the session that wrote this script, which a later session does not have.

It reports observations counted by record type, plus any `attempt_started` marker with no matching
observation. A marker without an observation is an attempt that may have spent quota and whose
outcome nobody knows — it is never absorbed into a total. With the `-OutDir` above the file already
lands at `core/plans/recog_c1_raw/recog_c1_raw_w2.jsonl`; commit it from there.

Expected: 52 observations, 52 markers, 0 orphaned.

The pull now proves itself rather than asking you to eyeball it: any earlier copy at the destination
is deleted first (so a failed pull cannot resurrect a stale file that reads as a short run), the
transfer's exit code is checked, and the pulled bytes are compared against a digest computed **on the
device**. Internal consistency — 52 observations against 52 markers — is a property a truncated file
also has, so it was never sufficient on its own.

## 7. Compute the baseline — both windows together

    cd D:\Repo\Fitness_App\mobile
    $p = 'D:/Repo/Fitness_App/core/plans'
    $env:RECOG_C1_RAW  = "$p/recog_c1_raw/recog_c1_raw_w1.jsonl,$p/recog_c1_raw/recog_c1_raw_w2.jsonl"
    $env:RECOG_C1_GT   = "$p/RECOG_C1_GROUND_TRUTH_2026-09-05.csv"
    $env:RECOG_C1_PLAN = "$p/RECOG_C1_RUN_PLAN_2026-09-05.csv"
    $env:RECOG_C1_OUT  = "$p/RECOG_C1_MEASUREMENT_2026-09-05.md"
    flutter test test/tools/recog_c1_compute_metrics.dart

PowerShell has no inline `VAR=x cmd` form, so these are set as `$env:` first. Forward slashes
throughout: they go into Dart's `File`, which takes them on Windows, and a backslash inside a
double-quoted PowerShell string is not an escape but a comma-separated path list is easier to read
this way.

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

**The first command below is a file deletion, which `~/.claude/CLAUDE.md` §20 reserves to the
operator regardless of any review approval.** It is the only step in this whole plan that does.

    cd D:\Repo\Fitness_App
    git rm mobile/lib/features/visual_equipment/measurement/recog_c1_harness.dart
    git checkout 7eb4392 -- mobile/lib/main.dart
    .\scripts\dev\recog_c1_verify_revert.ps1

`recog_c1_contract.dart` stays. It predates the harness, is present in the baseline, and five
committed analysis files import it -- removing it would leave a tree that looks correctly cleaned
while making every number in the measurement unreproducible. The verify script asserts it is still
there for exactly that reason.

Expected: `revert verified: ... byte-identical to 7eb439202563d924983bacc3987723f9591fb28c ...`.
Run it BEFORE the revert too, once: it must exit 1. A check that has never failed is not known to
work.

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
