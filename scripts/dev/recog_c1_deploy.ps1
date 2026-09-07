# RECOG-C1 — put one measurement window on the device, and take the raw rows back.
#
# Plan fitness_app-2026-09-05T11-25-16-919Z-377ee0, steps 6-7. This script is
# the only thing that touches the device; the harness itself decides nothing
# about WHICH observations to make -- that comes from the committed run plan
# this pushes.
#
#   .\scripts\dev\recog_c1_deploy.ps1 -Push   -Window 1 -RunId w1
#   .\scripts\dev\recog_c1_deploy.ps1 -Pull   -RunId w1
#
# Why the app's own external files directory: `adb push` can write
# /sdcard/Android/data/<pkg>/files without any runtime permission, and the app
# can read it without one either. Nothing else on the device is touched.
#
# The two arms share filenames -- 20260810_131311.jpg exists as an original AND
# as a crop -- so they go to SEPARATE directories, `images/A` and `images/B`.
# One flat directory would silently serve whichever arm was copied last, and
# the whole measurement is a comparison between those two arms.

[CmdletBinding()]
param(
    [switch]$Push,
    [switch]$Pull,
    # Runs the artifact-provenance checks and exits. No device, no adb, nothing
    # copied -- so the guards below can be mutation-tested on their own, which
    # is the only way anyone can know they still work.
    [switch]$VerifyOnly,
    # Installs the measurement APK and PROVES it landed. See Install-Measured.
    [string]$Install,
    # Checks that the device holds exactly what this window's rows require --
    # every image, right bytes, and the frozen run plan -- without pushing
    # anything. Separate from -Push so the check can be exercised, and usable
    # on its own before a run to answer "did the earlier push actually land".
    [switch]$VerifyDevice,
    [int]$Window = 1,
    [Parameter(Mandatory = $true)][string]$RunId,
    [string]$Serial,
    [string]$WorkDir = "D:\Temp\claude\d--Repo\5c302c91-31c2-4e5a-8695-d3eb4d063e24\scratchpad\recog_c1",
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'

# Debug builds carry `applicationIdSuffix ".debug"` (mobile/android/app/build.gradle.kts),
# and the harness is `kDebugMode`-gated, so this is the only package it can run in.
$Package = 'com.fitnessapp.fitness_app.sptr.debug'
$Remote = "/sdcard/Android/data/$Package/files/recog_c1"

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$planRel = 'core/plans/RECOG_C1_RUN_PLAN_2026-09-05.csv'
$planSrc = Join-Path $repo ($planRel -replace '/', '\')
$manifestRel = 'core/plans/RECOG_C1_FREEZE_MANIFEST.json'

# sha256 of a file's newline-normalised bytes. Normalised because git checks
# these CSVs out as CRLF on this machine while the generators write LF, so a raw
# hash is not stable across checkouts and would fail for the wrong reason.
function Get-LfSha256([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes) -replace "`r`n", "`n"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text))
    } finally { $sha.Dispose() }
    return -join ($hash | ForEach-Object { $_.ToString('x2') })
}

# The plan's identity, read from the COMMITTED manifest rather than from the
# working copy -- and never from the plan itself.
#
# This is the whole point. Hashing the file you are about to push and compiling
# that value into the APK proves only that the two agree with each other: a
# stale or hand-edited plan supplies both sides of the equality and passes on
# both ends perfectly. Taking the reference from `git show HEAD:` makes editing
# it locally do nothing, and editing it for real mean committing it -- which
# puts it in the history, where it is reviewable.
function Assert-Provenance {
    $manifestJson = & git -C $repo show "HEAD:$manifestRel" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $manifestJson) {
        throw "$manifestRel is not in HEAD. The authoritative hashes must be committed before a measurement build; without them nothing distinguishes the frozen plan from a local edit."
    }
    $manifest = $manifestJson | ConvertFrom-Json
    $expected = $manifest.artifacts.$planRel.sha256_lf
    if (-not $expected) { throw "no sha256_lf for $planRel in the committed manifest" }

    $actual = Get-LfSha256 $planSrc
    if ($actual -ne $expected) {
        throw "run plan does not match the committed freeze manifest.`n  committed: $expected`n  local:     $actual`nThe measurement must run the frozen plan or it is measuring something nobody agreed to."
    }

    # A dirty tree cannot be identified by HEAD: the compiled bytes are not the
    # bytes that commit names, so RECOG_C1_SOURCE_SHA would record a provenance
    # the build does not have. A hard stop, not a warning -- a warning is
    # something a run discovers it ignored after the day's calls are spent.
    $dirty = @(& git -C $repo status --porcelain | Where-Object { $_ })
    if ($dirty.Count -gt 0) {
        $shown = ($dirty | Select-Object -First 10) -join "`n  "
        throw "the working tree is dirty, so RECOG_C1_SOURCE_SHA would name a commit whose contents are not what gets compiled. Commit first.`n  $shown"
    }

    Write-Host "provenance OK: plan matches the committed manifest ($expected), tree is clean"
    return $expected
}

if ($VerifyOnly) {
    $null = Assert-Provenance
    exit 0
}

function Get-Adb {
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
        "$env:ANDROID_HOME\platform-tools\adb.exe",
        "D:\android-sdk\platform-tools\adb.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    throw "adb not found. Put it on PATH or edit the candidate list in this script."
}

$adb = Get-Adb

# A wrong device is a wrong measurement, so an ambiguous device list is a stop
# rather than a guess.
# @() is load-bearing, not style. PowerShell unwraps a single-element pipeline
# result into a bare string, and a string answers .Count with 1 and [0] with its
# FIRST CHARACTER -- so with exactly one device attached (the normal case) this
# resolved $Serial to "c" and every adb call failed with "device 'c' not found".
# Caught on the first real -Pull, after the same code had already run -Push and
# -Install by being handed an explicit -Serial each time.
$devices = @(& $adb devices | Select-Object -Skip 1 |
    Where-Object { $_ -match '\sdevice$' } |
    ForEach-Object { ($_ -split '\s+')[0] })
if ($Serial) {
    if ($devices -notcontains $Serial) { throw "device $Serial is not attached" }
} elseif ($devices.Count -eq 1) {
    $Serial = $devices[0]
} else {
    throw "expected exactly one attached device, found $($devices.Count): $($devices -join ', '). Pass -Serial."
}
$adbArgs = @('-s', $Serial)

# Every adb call goes through here, and that is the point.
#
# `$ErrorActionPreference = 'Stop'` does NOT make a native executable's non-zero
# exit throw. That is precisely how an `adb install` reported success on
# 2026-09-05 having installed nothing, and `Install-Measured` below was written
# to close it -- for install only. Every `push`, `pull` and `shell` in this file
# still discarded its exit code afterwards, which left the same hole one step
# earlier in the pipeline: a run plan that never reaches the device makes the
# harness print one line and return, and "one line and nothing else" is the same
# silence the install incident produced.
#
# A wrapper rather than a check at each call site, because the sites that matter
# are exactly the ones nobody remembers to check.
function Invoke-Adb {
    param(
        [Parameter(Mandatory = $true)][string]$What,
        [switch]$AllowFailure,
        [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )
    $out = & $adb @adbArgs @Arguments 2>&1
    $code = $LASTEXITCODE
    if (-not $AllowFailure -and $code -ne 0) {
        throw "$What failed (adb exit $code): $($out -join ' ')"
    }
    return $out
}

# sha256 of a file ON THE DEVICE. The only way to know that what was pushed is
# what arrived: `adb push` reporting a byte count describes what it sent, not
# what landed.
function Get-RemoteSha256([string]$RemotePath) {
    $line = (Invoke-Adb -What "sha256sum $RemotePath" -- shell "sha256sum '$RemotePath'") -join ' '
    if ($line -notmatch '^([0-9a-f]{64})\s') {
        throw "could not read a sha256 for $RemotePath from the device (got: '$line')"
    }
    return $Matches[1]
}

# Proof that what the push SENT is what the device HOLDS.
#
# Everything here exists because a push that half-happened produced the same
# output as one that succeeded: `adb push` printed a byte count, the script
# printed "pushed to ...", and the first thing that would have noticed a missing
# image is the harness reaching that row -- after a build, an install, and some
# of the day's sixty calls already spent on the rows before it.
#
# A separate function, reachable through -VerifyDevice, so the check can be
# exercised on its own. A verification that can only run as a side effect of the
# thing it verifies cannot be shown to work.
function Assert-DeviceMatchesPlan($Rows, [string]$AuthoritativePlanSha) {
    # 1. the plan on the device is the frozen plan, byte for byte.
    $remotePlanSha = Get-RemoteSha256 "$Remote/run_plan.csv"
    if ($remotePlanSha -ne $AuthoritativePlanSha) {
        throw "the run plan on the device does not match the committed manifest: device has $remotePlanSha, manifest says $AuthoritativePlanSha. A run started now would measure a plan nobody agreed to."
    }

    # 2. every image this window needs is present, with the right bytes.
    #    Hashed ON THE DEVICE: a push's byte count describes what was sent.
    $remoteHashes = @{}
    foreach ($arm in @('A', 'B')) {
        foreach ($line in (Invoke-Adb -What "hashing arm $arm images" -- shell "sha256sum $Remote/images/$arm/* 2>/dev/null")) {
            if ($line -match '^([0-9a-f]{64})\s+(\S+)$') {
                $remoteHashes["$arm/$([System.IO.Path]::GetFileName($Matches[2]))"] = $Matches[1]
            }
        }
    }
    $missing = 0
    $wrong = 0
    foreach ($r in $Rows) {
        $key = "$($r.arm)/$($r.source_file)"
        if (-not $remoteHashes.ContainsKey($key)) {
            Write-Host "  MISSING on device: $key" -ForegroundColor Red
            $missing++
        }
        elseif ($remoteHashes[$key] -ne $r.transformed_sha256) {
            Write-Host "  WRONG BYTES on device: $key" -ForegroundColor Red
            $wrong++
        }
    }
    if ($missing -gt 0 -or $wrong -gt 0) {
        throw "$missing image(s) missing and $wrong with the wrong bytes on the device, out of $($Rows.Count) this window needs. adb reported success for all of them."
    }

    Write-Host "device verified: $($Rows.Count) images match the plan's hashes, run plan matches the committed manifest ($remotePlanSha)"
}

# Installs the APK and then proves the device actually took it.
#
# `adb install` reporting success is not evidence that it installed. On
# 2026-09-06 this exact step returned exit code 0 with no output while leaving
# the previous day's build in place; the run then launched that old build,
# which has the harness compiled out, so it printed nothing and did nothing --
# and "no RECOG-C1 output" is indistinguishable from "the harness declined to
# start". The failure was found by hand, after the fact. Nothing should have to
# be found by hand twice.
#
# The check is `lastUpdateTime` moving forward. Coarse, and deliberately so: it
# needs no cooperation from the app, no version bump, and no parsing of
# anything the build itself controls -- it is the package manager's own record
# of whether it did the thing.
function Install-Measured([string]$ApkPath) {
    if (-not (Test-Path $ApkPath)) { throw "no APK at $ApkPath" }

    $before = (& $adb @adbArgs shell "dumpsys package $Package | grep lastUpdateTime") -join ' '
    $mb = [math]::Round((Get-Item $ApkPath).Length / 1MB)
    Write-Host "installing $([System.IO.Path]::GetFileName($ApkPath)) ($mb MB)"

    $output = & $adb @adbArgs install -r $ApkPath 2>&1
    $code = $LASTEXITCODE
    $output | ForEach-Object { Write-Host "  $_" }
    if ($code -ne 0) {
        throw "adb install failed with exit $code. INSTALL_FAILED_INSUFFICIENT_STORAGE means the device is full: rebuild with --split-per-abi rather than uninstalling anything, which is the operator's call and not this script's. NOT --target-platform android-arm64: that was tried on 2026-09-06 and did not shrink the APK at all, because it governs only the Flutter engine's own libraries while the plugin native libraries come from Gradle -- unpacking showed all four ABIs still present."
    }

    $after = (& $adb @adbArgs shell "dumpsys package $Package | grep lastUpdateTime") -join ' '
    if (-not $after -or $after.Trim() -eq $before.Trim()) {
        throw "adb install reported success but the package manager's lastUpdateTime did not move ('$($before.Trim())' -> '$($after.Trim())'). The device is still running the previous build, and a measurement started now would silently be no measurement at all."
    }
    Write-Host "install verified: lastUpdateTime moved to $($after.Trim())"
}

if ($VerifyDevice) {
    # The authoritative hash comes from the COMMITTED manifest, same as -Push.
    # The dirty-tree stop is deliberately NOT applied here: nothing is being
    # compiled, so there is no build whose provenance a dirty tree could
    # misdescribe -- and requiring a clean tree would make this check
    # unrunnable while anyone is editing the script that contains it.
    $manifestJson = & git -C $repo show "HEAD:$manifestRel" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $manifestJson) {
        throw "$manifestRel is not in HEAD; there is no authoritative hash to check the device against"
    }
    $expectedPlanSha = ($manifestJson | ConvertFrom-Json).artifacts.$planRel.sha256_lf
    if (-not $expectedPlanSha) { throw "no sha256_lf for $planRel in the committed manifest" }

    $rows = Import-Csv $planSrc | Where-Object { [int]$_.window -eq $Window }
    if (-not $rows) { throw "run plan has no rows for window $Window" }
    Write-Host "window ${Window}: checking $($rows.Count) observations against the device"
    Assert-DeviceMatchesPlan $rows $expectedPlanSha
    exit 0
}

if ($Install) {
    Install-Measured $Install
    exit 0
}
Write-Host "device: $Serial"
Write-Host "package: $Package"

if ($Push) {
    # Before a single byte moves. A push that has already staged images is a
    # push that has already made the device state ambiguous.
    $authoritativePlanSha = Assert-Provenance

    if (-not (Test-Path $planSrc)) { throw "missing run plan: $planSrc" }
    foreach ($arm in @('arm_a', 'arm_b')) {
        $d = Join-Path $WorkDir $arm
        if (-not (Test-Path $d)) { throw "missing image directory: $d" }
    }

    # Only the rows of THIS window are pushed, and only the arm each row names.
    # Pushing everything would work, but it would also mean a build misreading
    # the window define could silently measure targets belonging to the other
    # UTC day and still find its files.
    $rows = Import-Csv $planSrc | Where-Object { [int]$_.window -eq $Window }
    if (-not $rows) { throw "run plan has no rows for window $Window" }
    Write-Host "window ${Window}: $($rows.Count) observations"

    Invoke-Adb -What 'creating the remote image directories' -- shell "mkdir -p $Remote/images/A $Remote/images/B" | Out-Null

    $staged = Join-Path ([System.IO.Path]::GetTempPath()) "recog_c1_$RunId"
    if (Test-Path $staged) { Remove-Item $staged -Recurse -Force }
    foreach ($arm in @('A', 'B')) { New-Item -ItemType Directory -Force (Join-Path $staged $arm) | Out-Null }

    foreach ($r in $rows) {
        $srcDir = if ($r.arm -eq 'A') { 'arm_a' } else { 'arm_b' }
        $src = Join-Path (Join-Path $WorkDir $srcDir) $r.source_file
        if (-not (Test-Path $src)) { throw "missing image: $src" }
        # The plan records the sha256 of the bytes each arm is supposed to
        # send. Checking it HERE means a stale or mixed-up corpus directory
        # fails before anything is measured, rather than producing 52 rows
        # about the wrong photographs.
        $sha = (Get-FileHash $src -Algorithm SHA256).Hash.ToLower()
        if ($sha -ne $r.transformed_sha256) {
            throw "sha256 mismatch for arm $($r.arm) $($r.source_file): plan says $($r.transformed_sha256), file is $sha"
        }
        Copy-Item $src (Join-Path (Join-Path $staged $r.arm) $r.source_file)
    }

    foreach ($arm in @('A', 'B')) {
        $local = Join-Path $staged $arm
        if ((Get-ChildItem $local -File).Count -eq 0) { continue }
        Invoke-Adb -What "pushing arm $arm images" -- push "$local\." "$Remote/images/$arm/" | Out-Null
    }
    Invoke-Adb -What 'pushing the run plan' -- push $planSrc "$Remote/run_plan.csv" | Out-Null
    Remove-Item $staged -Recurse -Force

    Assert-DeviceMatchesPlan $rows $authoritativePlanSha

    # Not recomputed from the pushed bytes: taken from the committed manifest,
    # which is the only value independent of the artifact being checked.
    $planSha = $authoritativePlanSha

    Write-Host ""
    Write-Host "Now build and install the measurement APK:"
    Write-Host "  flutter build apk --debug --split-per-abi ``"
    Write-Host "    --dart-define=RECOG_C1_HARNESS=true ``"
    Write-Host "    --dart-define=RECOG_C1_DIR=$Remote ``"
    Write-Host "    --dart-define=RECOG_C1_RUN_ID=$RunId ``"
    Write-Host "    --dart-define=RECOG_C1_WINDOW=$Window ``"
    Write-Host "    --dart-define=RECOG_C1_PLAN_SHA=$planSha ``"
    Write-Host "    --dart-define=RECOG_C1_SOURCE_SHA=`$(git rev-parse HEAD) ``"
    Write-Host "    --dart-define=APP_CHECK_DEBUG_TOKEN=`$env:APP_CHECK_DEBUG_TOKEN"
    Write-Host ""
    Write-Host "Every one of those defines is REQUIRED. The first five the harness"
    Write-Host "checks itself: it refuses to run without them rather than defaulting"
    Write-Host "to all 104 observations in one UTC day against a 60-call quota."
    Write-Host ""
    Write-Host "The SIXTH one the harness cannot check -- App Check is the app's"
    Write-Host "dependency, established long before the harness starts -- and on"
    Write-Host "2026-09-07 it cost two runs. Not because it was absent: because the"
    Write-Host "value being passed was a debug token's RESOURCE ID rather than its"
    Write-Host "secret. The App Check API names a token .../debugTokens/<base64 id>"
    Write-Host "and that id is a different UUID from the value, so an id looks just"
    Write-Host "as much like a credential as the credential does. Firebase answers"
    Write-Host "403 App attestation failed; the device reports only 'unauthenticated',"
    Write-Host "which names neither App Check nor the build while the log above it"
    Write-Host "says the user IS signed in."
    Write-Host ""
    Write-Host "So do not trust a token because a document calls it one. Exchange it"
    Write-Host "first -- recog_c1_window2.ps1 does this in its preconditions, costs no"
    Write-Host "AI quota, and refuses on anything but 200."
    Write-Host ""
    Write-Host "No token VALUE is printed here, logged, or committed by this script."
}

if ($Pull) {
    if (-not $OutDir) { $OutDir = Join-Path $WorkDir 'raw' }
    New-Item -ItemType Directory -Force $OutDir | Out-Null
    $remoteFile = "$Remote/recog_c1_raw_$RunId.jsonl"
    $exists = ((Invoke-Adb -What 'checking for the raw file' -- shell "test -f $remoteFile && echo yes || echo no") -join '').Trim()
    if ($exists -ne 'yes') { throw "no raw file on the device at $remoteFile" }
    $dest = Join-Path $OutDir "recog_c1_raw_$RunId.jsonl"

    # Remove any earlier copy FIRST. `$dest` is deterministic per run id, so a
    # pull that fails leaves the previous attempt's file sitting there, and the
    # consistency check below -- which only compares the file against itself --
    # would pass on it happily. A stale 48-observation file and a genuine
    # 48-observation run that hit the abort valve print the same line.
    if (Test-Path $dest) { Remove-Item $dest -Force }

    $remoteSha = Get-RemoteSha256 $remoteFile
    Invoke-Adb -What 'pulling the raw file' -- pull $remoteFile $dest | Out-Null
    if (-not (Test-Path $dest)) { throw "adb pull reported success but $dest does not exist" }

    # Compared against the DEVICE, not against itself. Internal consistency
    # (52 observations, 52 markers) is a property a truncated file can also
    # have.
    $localSha = (Get-FileHash $dest -Algorithm SHA256).Hash.ToLower()
    if ($localSha -ne $remoteSha) {
        throw "the pulled file does not match the device: device $remoteSha, local $localSha. The transfer was incomplete or something else wrote to $dest."
    }
    # Counted by record type, not by line. The file interleaves a write-ahead
    # `attempt_started` marker with each observation, so a line count reads
    # exactly double and would have reported window 1's 52 observations as 104
    # -- the full two-window run, which is the one number this gate must never
    # claim by accident.
    $content = @(Get-Content $dest | Where-Object { $_.Trim() })
    $observations = @($content | Where-Object { $_ -match '"record_type":"observation"' }).Count
    $started = @($content | Where-Object { $_ -match '"record_type":"attempt_started"' }).Count
    Write-Host "pulled $observations observations ($started attempts started, $($content.Count) records) -> $dest"
    if ($observations -ne $started) {
        Write-Host "  NOTE: $($started - $observations) attempt(s) started without a matching observation -- outcome unknown, not a failure." -ForegroundColor Yellow
    }
    Write-Host "sha256: $((Get-FileHash $dest -Algorithm SHA256).Hash.ToLower())"
}

if (-not $Push -and -not $Pull) { throw "pass -Push, -Pull, -VerifyDevice, -VerifyOnly or -Install" }
