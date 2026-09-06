# RECOG-C1 window 2 — the whole run, in order, with the preconditions enforced
# rather than described.
#
# This exists because a hand-ordered list of command blocks was run out of
# order on 2026-09-06: step 8's revert went first, which removed the harness
# from the tree while half the corpus was still unmeasured. Nothing was lost --
# nothing had been committed, and the relaunched window-1 build spent no quota
# because its rows were already recorded -- but a checklist that can be run in
# the wrong order eventually is.
#
# Steps 1 to 7 only. The revert is NOT here and never will be: it removes a
# tracked file, which is the operator's under ~/.claude/CLAUDE.md §20, and it
# must not happen until the measurement document exists.
#
#   .\scripts\dev\recog_c1_window2.ps1
#
# Every step states how it is known to have worked. Refusals are loud and early:
# the expensive failure in this gate is not a crash, it is a run that looks like
# it happened.

param(
    [string]$Serial = 'ce02171299f0711005',
    # Stop after the preconditions, having changed nothing. Use it to find out
    # whether tonight's run can go ahead without starting it.
    [switch]$PreflightOnly
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$deploy = Join-Path $PSScriptRoot 'recog_c1_deploy.ps1'
$adb = 'D:\android-sdk\platform-tools\adb.exe'
$package = 'com.fitnessapp.fitness_app.sptr.debug'
$remote = "/sdcard/Android/data/$package/files/recog_c1"
$activity = "$package/com.fitnessapp.fitness_app.MainActivity"

$rawDir = Join-Path $repo 'core\plans\recog_c1_raw'
$w1 = Join-Path $rawDir 'recog_c1_raw_w1.jsonl'
$w2 = Join-Path $rawDir 'recog_c1_raw_w2.jsonl'
$harness = Join-Path $repo 'mobile\lib\features\visual_equipment\measurement\recog_c1_harness.dart'
$apk = Join-Path $repo 'mobile\build\app\outputs\flutter-apk\app-arm64-v8a-debug.apk'
$planSha = '4f4ef743734ce710e6e82e968db41a4c682af1f230f2c8ff2aad0d6b9828325d'

function Step([string]$Text) {
    Write-Host ""
    Write-Host "== $Text" -ForegroundColor Cyan
}

# =============================================================================
# Preconditions. All of them, before anything is touched.
# =============================================================================
Step 'preconditions'

# The quota day, derived from the DATA rather than from a hardcoded date.
# `QUOTAS.aiEquipmentRecognition` is 60 per user per UTC day and window 1 spent
# 52 of them; a second window in the same UTC day would run into the wall after
# roughly eight observations and leave a file that is short for a reason no
# control record can express.
if (-not (Test-Path $w1)) { throw "window 1's raw file is missing at $w1 -- there is no baseline to extend" }
$w1Dates = Get-Content $w1 |
    Where-Object { $_ -match '"utc_start":"(\d{4}-\d{2}-\d{2})' } |
    ForEach-Object { $Matches[1] } |
    Sort-Object -Unique
if (-not $w1Dates) { throw "could not read any utc_start out of $w1" }
$today = [DateTime]::UtcNow.ToString('yyyy-MM-dd')
if ($w1Dates -contains $today) {
    throw "window 1 ran on $today UTC and spent 52 of that day's 60 calls. Window 2 needs 52 more, so it cannot run until the UTC day rolls over. It is $([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')) now -- $([math]::Round(([DateTime]::UtcNow.Date.AddDays(1) - [DateTime]::UtcNow).TotalHours, 1)) hours to go."
}
Write-Host "  quota day: window 1 ran on $($w1Dates -join ', ') UTC, today is $today -- clear"

# The instrument has to be in the tree to be compiled into anything.
if (-not (Test-Path $harness)) {
    throw "the measurement harness is not in the working tree ($harness). If the revert was run early, restore it with: git checkout HEAD -- mobile/lib/features/visual_equipment/measurement/recog_c1_harness.dart mobile/lib/main.dart"
}
Write-Host "  harness present"

# Already done is a refusal, not a no-op: re-running would spend a second set of
# calls on photographs already measured.
if (Test-Path $w2) {
    throw "window 2's raw file already exists at $w2. If this run genuinely needs repeating, move that file aside deliberately -- re-running spends another 52 calls on targets already measured."
}
Write-Host "  window 2 not yet run"

$dirty = @(& git -C $repo status --porcelain | Where-Object { $_ })
if ($dirty.Count -gt 0) {
    throw "the working tree is dirty, so the build's RECOG_C1_SOURCE_SHA would name a commit whose contents are not what gets compiled:`n  $(($dirty | Select-Object -First 10) -join "`n  ")"
}
Write-Host "  tree clean at $((& git -C $repo rev-parse --short HEAD).Trim())"

if ($PreflightOnly) {
    Write-Host ""
    Write-Host "preflight only: every precondition passes, nothing was changed." -ForegroundColor Green
    exit 0
}

# =============================================================================
Step '1/7 provenance'
& $deploy -VerifyOnly -RunId w2
if ($LASTEXITCODE -ne 0) { throw 'provenance check failed' }

Step '2/7 the device holds what window 2 needs'
& $deploy -VerifyDevice -Window 2 -RunId w2 -Serial $Serial
if ($LASTEXITCODE -ne 0) { throw 'device verification failed' }

Step '3/7 build'
# --split-per-abi is not optional: the fat APK is 423 MB and /data has ~1.3 GB
# free, which failed as INSTALL_FAILED_INSUFFICIENT_STORAGE presenting as exit
# code 0 with no output. --target-platform android-arm64 does not substitute --
# measured, it leaves all four ABIs in place.
$sourceSha = (& git -C $repo rev-parse HEAD).Trim()
Push-Location (Join-Path $repo 'mobile')
try {
    & flutter build apk --debug --split-per-abi `
        --dart-define=RECOG_C1_HARNESS=true `
        --dart-define=RECOG_C1_DIR=$remote `
        --dart-define=RECOG_C1_RUN_ID=w2 `
        --dart-define=RECOG_C1_WINDOW=2 `
        --dart-define=RECOG_C1_PLAN_SHA=$planSha `
        --dart-define=RECOG_C1_SOURCE_SHA=$sourceSha
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed with exit $LASTEXITCODE" }
}
finally { Pop-Location }
if (-not (Test-Path $apk)) { throw "the build reported success but $apk is not there" }
# A stale APK from an earlier build would install perfectly and measure the
# wrong window, so the file's age is checked rather than assumed.
$age = ([DateTime]::Now - (Get-Item $apk).LastWriteTime).TotalMinutes
if ($age -gt 30) { throw "$apk is $([math]::Round($age)) minutes old -- that is not the build this run just made" }
Write-Host "  built $([math]::Round((Get-Item $apk).Length / 1MB)) MB from $sourceSha"

Step '4/7 install, and prove it landed'
& $deploy -Install $apk -RunId w2 -Serial $Serial
if ($LASTEXITCODE -ne 0) { throw 'install verification failed' }

Step '5/7 run'
& $adb -s $Serial shell am start -n $activity | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'could not start the app' }

# Counted by `response_class`, which appears on observation records and on no
# control record -- so it needs no quoting, which is what broke the hand-typed
# progress command: PowerShell mangled the escaped quotes and grep saw a
# trailing backslash.
$deadline = (Get-Date).AddMinutes(25)
$seen = -1
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 20
    $n = 0
    $out = (& $adb -s $Serial shell "grep -c response_class $remote/recog_c1_raw_w2.jsonl" 2>$null) -join ''
    if ($out -match '(\d+)') { $n = [int]$Matches[1] }
    $alive = ((& $adb -s $Serial shell "pidof $package" 2>$null) -join '').Trim()
    if ($n -ne $seen) { Write-Host "  $n / 52 observations"; $seen = $n }
    if ($n -ge 52) { break }
    if (-not $alive) { throw "the app is no longer running and only $n of 52 observations exist. Relaunching resumes rather than repeats -- rows already written are skipped -- so start it again rather than rebuilding." }
}
if ($seen -lt 52) { throw "timed out at $seen of 52 observations" }
Write-Host "  52 / 52"

Step '6/7 pull'
& $deploy -Pull -RunId w2 -OutDir $rawDir -Serial $Serial
if ($LASTEXITCODE -ne 0) { throw 'pull failed' }
if (-not (Test-Path $w2)) { throw "the pull reported success but $w2 is not there" }

Step '7/7 the baseline, both windows together'
$p = ($repo -replace '\\', '/') + '/core/plans'
$env:RECOG_C1_RAW = "$p/recog_c1_raw/recog_c1_raw_w1.jsonl,$p/recog_c1_raw/recog_c1_raw_w2.jsonl"
$env:RECOG_C1_GT = "$p/RECOG_C1_GROUND_TRUTH_2026-09-05.csv"
$env:RECOG_C1_PLAN = "$p/RECOG_C1_RUN_PLAN_2026-09-05.csv"
$env:RECOG_C1_OUT = "$p/RECOG_C1_MEASUREMENT_2026-09-05.md"
Push-Location (Join-Path $repo 'mobile')
try {
    & flutter test test/tools/recog_c1_compute_metrics.dart
    if ($LASTEXITCODE -ne 0) { throw "the metric script stopped. It stops rather than continues on a reconstruction mismatch, a duplicate observation id, an unparseable line, missing ground truth, an unknown gt_kind, or pair accounting that does not add up -- each of which would otherwise produce a number that looks fine and is false. Read the message; do not re-run it hoping." }
}
finally { Pop-Location }

Write-Host ""
Write-Host "window 2 complete. The measurement is at core/plans/RECOG_C1_MEASUREMENT_2026-09-05.md" -ForegroundColor Green
Write-Host "Commit the raw file and the measurement. The harness revert (step 8) is separate, is the"
Write-Host "operator's under CLAUDE.md 20, and only makes sense now that the measurement exists."
