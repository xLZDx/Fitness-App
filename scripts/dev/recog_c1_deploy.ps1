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
$devices = & $adb devices | Select-Object -Skip 1 |
    Where-Object { $_ -match '\sdevice$' } |
    ForEach-Object { ($_ -split '\s+')[0] }
if ($Serial) {
    if ($devices -notcontains $Serial) { throw "device $Serial is not attached" }
} elseif ($devices.Count -eq 1) {
    $Serial = $devices[0]
} else {
    throw "expected exactly one attached device, found $($devices.Count): $($devices -join ', '). Pass -Serial."
}
$adbArgs = @('-s', $Serial)
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

    & $adb @adbArgs shell "mkdir -p $Remote/images/A $Remote/images/B" | Out-Null

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
        & $adb @adbArgs push "$local\." "$Remote/images/$arm/" | Out-Null
    }
    & $adb @adbArgs push $planSrc "$Remote/run_plan.csv" | Out-Null
    Remove-Item $staged -Recurse -Force

    Write-Host "pushed to $Remote"
    & $adb @adbArgs shell "ls $Remote/images/A | wc -l; ls $Remote/images/B | wc -l"

    # Not recomputed from the pushed bytes: taken from the committed manifest,
    # which is the only value independent of the artifact being checked.
    $planSha = $authoritativePlanSha

    Write-Host ""
    Write-Host "Now build and install the measurement APK:"
    Write-Host "  flutter build apk --debug ``"
    Write-Host "    --dart-define=RECOG_C1_HARNESS=true ``"
    Write-Host "    --dart-define=RECOG_C1_DIR=$Remote ``"
    Write-Host "    --dart-define=RECOG_C1_RUN_ID=$RunId ``"
    Write-Host "    --dart-define=RECOG_C1_WINDOW=$Window ``"
    Write-Host "    --dart-define=RECOG_C1_PLAN_SHA=$planSha ``"
    Write-Host "    --dart-define=RECOG_C1_SOURCE_SHA=`$(git rev-parse HEAD)"
    Write-Host ""
    Write-Host "Every one of those defines is REQUIRED: the harness refuses to run"
    Write-Host "without them rather than defaulting to all 104 observations in one"
    Write-Host "UTC day against a 60-call quota."
    Write-Host "No token value is passed here or recorded anywhere."
}

if ($Pull) {
    if (-not $OutDir) { $OutDir = Join-Path $WorkDir 'raw' }
    New-Item -ItemType Directory -Force $OutDir | Out-Null
    $remoteFile = "$Remote/recog_c1_raw_$RunId.jsonl"
    $exists = (& $adb @adbArgs shell "test -f $remoteFile && echo yes || echo no").Trim()
    if ($exists -ne 'yes') { throw "no raw file on the device at $remoteFile" }
    $dest = Join-Path $OutDir "recog_c1_raw_$RunId.jsonl"
    & $adb @adbArgs pull $remoteFile $dest | Out-Null
    $lines = (Get-Content $dest | Where-Object { $_.Trim() }).Count
    Write-Host "pulled $lines observations -> $dest"
    Write-Host "sha256: $((Get-FileHash $dest -Algorithm SHA256).Hash.ToLower())"
}

if (-not $Push -and -not $Pull) { throw "pass -Push or -Pull" }
