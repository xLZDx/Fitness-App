# Repeatable release build + optional Firebase App Distribution upload.
#
# WHY THIS EXISTS
#
# Build 1.0.0 (2014) was produced by hand: the GIT_SHA and BUILT_AT
# dart-defines were typed into the flutter command at the keyboard. That
# works exactly once. The next person -- or the same person next week --
# forgets one, and B6's session header ships reading "unknown", which
# defeats the point of B6: a log you cannot tie to a build tells you
# nothing about which code produced it.
#
# The two values are derived here, never typed. There is no way to run this
# script and get an unstamped build.
#
# WHY --split-per-abi IS THE DEFAULT
#
# The single fat APK is ~244 MB, of which ~207 MB is native libraries for
# three ABIs -- arm64-v8a, armeabi-v7a, x86_64 -- and only ~33 MB is the
# app. A phone runs exactly one of those. Splitting gives ~98 MB for
# arm64-v8a, which is every Android phone shipped in the last several years.
# Pass -Fat when you genuinely need one file that installs anywhere.
#
# For the Play Store use -Bundle: Play does the splitting itself and an AAB
# is what the console accepts.
#
# Usage:
#   pwsh ./scripts/dev/build_release.ps1
#   pwsh ./scripts/dev/build_release.ps1 -Distribute
#   pwsh ./scripts/dev/build_release.ps1 -Bundle
#   pwsh ./scripts/dev/build_release.ps1 -Distribute -Notes "B5 model v2"

[CmdletBinding()]
param(
    [switch]$Distribute,
    [switch]$Bundle,
    [switch]$Fat,
    [string]$Notes = '',
    [string]$Testers = 'korostelevivan@gmail.com',
    [string]$FirebaseAppId = '1:988522745882:android:b9af40bb887a0388c201a3'
)

# Get-GitDirtyStamp lives in its own file so a test harness can dot-source
# just the decision logic -- no real git process, no repo, no Flutter or
# Firebase side effects. See build_release_gitcheck.ps1 and its companion
# build_release_gitcheck.tests.ps1.
. (Join-Path $PSScriptRoot 'build_release_gitcheck.ps1')

$ErrorActionPreference = 'Stop'
$ProjectRoot = Resolve-Path "$PSScriptRoot\..\.."
$MobileDir = Join-Path $ProjectRoot 'mobile'
$Flutter = 'D:/flutter/bin/flutter.bat'

if ($Bundle -and $Fat) { throw '-Bundle and -Fat are mutually exclusive.' }

# --- The two stamps -------------------------------------------------------

# Short SHA of HEAD. Fails loudly outside a git checkout rather than
# stamping "unknown" and shipping a build nobody can trace back.
Push-Location $ProjectRoot
try {
    $GitSha = (& git rev-parse --short HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($GitSha)) {
        throw 'git rev-parse failed -- run this from inside the repository.'
    }
    $GitSha = $GitSha.Trim()

    # A dirty tree means the APK does not match the commit it claims. Marked
    # in the stamp itself, because the whole value of the stamp is that it is
    # not a polite approximation. The 0/1/>1 decision itself lives in
    # Get-GitDirtyStamp above, where it can be tested without a real git call.
    #
    # Reading $LASTEXITCODE at all requires surviving the call first: under
    # $ErrorActionPreference = 'Stop', Windows PowerShell 5.1 turns any
    # stderr line from a native command into a terminating error
    # independently of `2>$null` (that redirects the displayed text, not the
    # error-record it also raises) -- and git occasionally writes an
    # unrelated autocrlf advisory ("LF will be replaced by CRLF...") to
    # stderr for whichever file it last touched, which was enough to abort
    # the whole script before $LASTEXITCODE below was ever read. Hit twice,
    # with two different files, before this was traced to the git call
    # itself rather than either file. Scoped to just this one call rather
    # than flipping the script's own $ErrorActionPreference, which stays
    # 'Stop' for everything that should actually abort the build.
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & git diff --quiet HEAD 2>$null
    $diffExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousEap
    $stamped = Get-GitDirtyStamp -DiffExitCode $diffExitCode -BaseSha $GitSha
    if ($stamped -ne $GitSha) {
        $GitSha = $stamped
        Write-Host "WARNING: working tree is dirty -- stamping $GitSha" -ForegroundColor Yellow
    }
} finally {
    Pop-Location
}

# UTC, ISO 8601, second precision. Matches what debug_telemetry.dart parses.
$BuiltAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
$LocalNow = (Get-Date).ToString('yyyy-MM-dd HH:mm')

# --- The build number ------------------------------------------------------
#
# WHY THIS IS DERIVED AND NOT TYPED
#
# Three consecutive App Distribution releases all read "1.0.0 (2014)". The
# tester could not tell which build was installed, and the "Installed" badge
# sat on whichever release the console listed first regardless of the APK on
# the phone. Nothing was broken in the upload: the release NOTES did differ.
# The version did not, because pubspec.yaml has said `1.0.0+14` since
# 2026-08-02 and nothing bumps it.
#
# The 2014 is not 14 with a typo. `--split-per-abi` makes Flutter override
# each split's versionCode with `abi * 1000 + versionCode`, and arm64-v8a is
# abi 2 -- so 2000 + 14 = 2014, and the fat/bundle build of the same commit
# would have read 14. Both numbers are correct and neither moves on its own.
#
# The commit count is the build number: monotonic on master, derived from
# the same HEAD the SHA stamp comes from, and impossible to forget.
Push-Location $ProjectRoot
try {
    $BuildNumber = (& git rev-list --count HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($BuildNumber)) {
        throw 'git rev-list --count failed -- run this from inside the repository.'
    }
    $BuildNumber = [int]$BuildNumber.Trim()
} finally {
    Pop-Location
}

# A shallow clone counts only the commits it fetched, which is how a build
# number silently goes BACKWARDS. Android refuses to install a lower
# versionCode over a higher one, so that failure arrives as "install failed"
# on a tester's phone rather than as an error here. Compare against the
# floor pubspec still declares and stop if we would regress.
$PubspecVersion = (Get-Content (Join-Path $MobileDir 'pubspec.yaml') |
    Select-String -Pattern '^version:\s*(.+)$').Matches.Groups[1].Value.Trim()
$PubspecBuild = 0
if ($PubspecVersion -match '\+(\d+)$') { $PubspecBuild = [int]$Matches[1] }
if ($BuildNumber -le $PubspecBuild) {
    throw ("Derived build number $BuildNumber is not above pubspec's $PubspecBuild " +
           '-- a shallow clone? Fetch full history (git fetch --unshallow).')
}

Write-Host ''
Write-Host "GIT_SHA  : $GitSha" -ForegroundColor Cyan
Write-Host "BUILT_AT : $BuiltAt UTC  ($LocalNow local)" -ForegroundColor Cyan
Write-Host "BUILD No : $BuildNumber  (arm64 split shows as $(2000 + $BuildNumber))" -ForegroundColor Cyan
Write-Host ''

# --- Build ----------------------------------------------------------------

$defines = @(
    "--dart-define=GIT_SHA=$GitSha",
    "--dart-define=BUILT_AT=$BuiltAt",
    "--build-number=$BuildNumber"
)

Push-Location $MobileDir
try {
    if ($Bundle) {
        Write-Host 'Building AAB (release)...' -ForegroundColor Cyan
        & $Flutter build appbundle --release @defines
        $Artifact = Join-Path $MobileDir 'build\app\outputs\bundle\release\app-release.aab'
    } elseif ($Fat) {
        Write-Host 'Building fat APK (release, all ABIs)...' -ForegroundColor Cyan
        & $Flutter build apk --release @defines
        $Artifact = Join-Path $MobileDir 'build\app\outputs\flutter-apk\app-release.apk'
    } else {
        Write-Host 'Building split APKs (release, per ABI)...' -ForegroundColor Cyan
        & $Flutter build apk --release --split-per-abi @defines
        $Artifact = Join-Path $MobileDir 'build\app\outputs\flutter-apk\app-arm64-v8a-release.apk'
    }
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed ($LASTEXITCODE)" }
} finally {
    Pop-Location
}

if (-not (Test-Path $Artifact)) {
    throw "Build reported success but $Artifact is missing."
}

$SizeMb = [math]::Round((Get-Item $Artifact).Length / 1MB, 1)
Write-Host ''
Write-Host "Artifact : $Artifact" -ForegroundColor Green
Write-Host "Size     : $SizeMb MB" -ForegroundColor Green

# --- Distribute -----------------------------------------------------------

if (-not $Distribute) {
    Write-Host ''
    Write-Host 'Not distributed. Re-run with -Distribute to send to testers.' -ForegroundColor DarkGray
    exit 0
}

if ($Bundle) {
    throw 'App Distribution takes an APK, not an AAB. Drop -Bundle to distribute.'
}

if ([string]::IsNullOrWhiteSpace($Notes)) {
    $Notes = "$GitSha built $BuiltAt"
}
# The stamps go in the release notes too. The tester sees which build they
# have without opening the app, and the note survives in the console after
# the local file is gone.
$Notes = "$Notes`n`ngit $GitSha | built $BuiltAt UTC | $SizeMb MB"

Write-Host ''
Write-Host "Distributing to $Testers ..." -ForegroundColor Cyan
& firebase appdistribution:distribute $Artifact `
    --app $FirebaseAppId `
    --release-notes $Notes `
    --testers $Testers
if ($LASTEXITCODE -ne 0) { throw "firebase appdistribution:distribute failed ($LASTEXITCODE)" }

Write-Host ''
Write-Host "Distributed $GitSha ($SizeMb MB) to $Testers" -ForegroundColor Green
