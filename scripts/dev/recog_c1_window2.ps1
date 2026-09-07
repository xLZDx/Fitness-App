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
Write-Host "  window 2 not yet run (repository)"

# And on the DEVICE, which is the copy the harness actually resumes from. A
# partial file there is worse than an absent one: rows already written for this
# run id are skipped by design, so a leftover file silently shortens the window
# instead of stopping it. On 2026-09-07 an aborted attempt left three rows; a
# blind re-run would have measured 49 of 52 and reported a complete window.
$remoteRaw = "$remote/recog_c1_raw_w2.jsonl"
$remoteState = ((& $adb -s $Serial shell "test -f $remoteRaw && grep -c response_class $remoteRaw || echo absent" 2>$null) -join '').Trim()
if ($remoteState -ne 'absent') {
    throw "the device already holds $remoteRaw with $remoteState observation(s) in it. Rows already written for run id w2 are SKIPPED on resume, so running now would measure only what is missing and still report a finished window. Preserve that file and remove it from the device before re-running, or use a fresh run id."
}
Write-Host "  window 2 not yet run (device)"

# The SIXTH define. App Check is enforced on the AI callables
# (`APP_CHECK_ENFORCED_AI`, fail-closed in functions/src/scaling.ts), and a debug
# build's App Check token is supplied at BUILD time --
# `String.fromEnvironment('APP_CHECK_DEBUG_TOKEN')` in main.dart, empty unless a
# --dart-define provides it. When the client cannot obtain an App Check token it
# sends an error placeholder, the backend logs
# `Decoding App Check token failed` and refuses the call as `unauthenticated` --
# a message that names neither App Check nor the build, while the log line above
# it says the user IS signed in.
#
# Window 1 nonetheless ran with five defines and verified `app=VALID` server-side,
# because the device still held a persisted debug secret the Android provider
# reuses when a build supplies none. That store is gone, so the define is now
# genuinely required -- but "window 1 didn't need it" is exactly why a check for
# mere PRESENCE is not enough.
if (-not $env:APP_CHECK_DEBUG_TOKEN -or $env:APP_CHECK_DEBUG_TOKEN.Trim().Length -eq 0) {
    throw "APP_CHECK_DEBUG_TOKEN is not set in the environment. The device no longer holds a persisted App Check debug secret to fall back on, so without this the client obtains no attestation token and every call is refused as 'unauthenticated' -- which does not mention App Check and looks like a sign-in fault. Set it (never echo it) and re-run."
}
Write-Host "  App Check debug token present ($($env:APP_CHECK_DEBUG_TOKEN.Trim().Length) chars, value not shown)"

# --- and it must actually WORK, not merely exist ------------------------------
# Both aborted attempts on 2026-09-07 passed every check that existed, because
# every check asked "is a token present" and none asked "is this a token". The
# value carried in core/DECISION_LOG.md turned out to be the debug token's
# RESOURCE ID: the App Check API names a token
# `projects/../apps/../debugTokens/<base64 id>` where the id is an unrelated
# server-generated UUID, so an id looks exactly as much like a credential as the
# credential does. Proved by minting a token with a locally-generated value and
# watching the server return a different id for it.
#
# One HTTPS call settles it, against the same endpoint the device's SDK uses, so
# a 200 here means the device will get a token too and a 403 here is the failure
# the run would otherwise discover one build and 52 refusals later. It spends no
# AI quota: this is App Check's own API, not a callable.
#
# In THIS check the token travels in an HTTP request body and neither it nor the
# returned JWT is printed. That guarantee is scoped to this check and must not be
# read as covering the script: the build below passes the token as a literal
# --dart-define, so it is visible in that process's command line to anything
# running as the same user while the build lasts. That is the project's existing
# convention for this debug-only value (core/DECISION_LOG.md around :19741) and
# is accepted, not overlooked -- --dart-define-from-file with a gitignored file
# would close it if it is ever judged worth closing.
$gsPath = Join-Path $repo 'mobile/android/app/google-services.json'
if (-not (Test-Path $gsPath)) {
    throw "google-services.json is missing at $gsPath, so the App Check token cannot be verified against the app it must attest for."
}
$gs = Get-Content -Raw $gsPath | ConvertFrom-Json
$appIdForPackage = $null
foreach ($client in $gs.client) {
    if ($client.client_info.android_client_info.package_name -eq $package) {
        $appIdForPackage = $client.client_info.mobilesdk_app_id
    }
}
if (-not $appIdForPackage) { throw "google-services.json has no client for $package, so there is no app id to attest as." }
$apiKey = $gs.client[0].api_key[0].current_key
if (-not $apiKey) { throw "no api_key in google-services.json" }
$exchangeUri = "https://firebaseappcheck.googleapis.com/v1/projects/$($gs.project_info.project_number)/apps/${appIdForPackage}:exchangeDebugToken?key=$apiKey"
try {
    $exchanged = Invoke-RestMethod -Method Post -Uri $exchangeUri -ContentType 'application/json' `
        -Body (@{ debug_token = $env:APP_CHECK_DEBUG_TOKEN.Trim() } | ConvertTo-Json) -TimeoutSec 30
}
catch {
    $detail = $_.ErrorDetails.Message; if (-not $detail) { $detail = $_.Exception.Message }
    throw "the App Check debug token was REJECTED by Firebase, so this build would be refused on every call.`n  app      : $package ($appIdForPackage)`n  response : $detail`n`n'403 App attestation failed' means the value is not a registered debug token for this app. The cause that took two runs on 2026-09-07 is that it was a debug token's RESOURCE ID rather than its secret -- the id is a different UUID from the value, and the value is returned only when the token is created, so it cannot be recovered from the id afterwards. Mint a new token against this app, keep the value out of the repository, and set it here."
}
if (-not $exchanged.token) { throw "the App Check exchange returned no token; refusing to build against an unverified attestation path." }
Write-Host "  App Check token verified: exchanged for a real attestation token (ttl $($exchanged.ttl))"

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
        --dart-define=RECOG_C1_SOURCE_SHA=$sourceSha `
        --dart-define=APP_CHECK_DEBUG_TOKEN=$($env:APP_CHECK_DEBUG_TOKEN.Trim())
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
