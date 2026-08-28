# Comprehensive test runner.
#
# Runs the whole Flutter pipeline in order:
#   1. flutter analyze        -- static type / lint / unused-import check
#   2. flutter test            -- unit + widget + golden tests
#   3. (optional) integration  -- device-backed flows in mobile/integration_test/,
#                                 run when -Integration is set. Skips cleanly
#                                 (rather than erroring) when that directory is
#                                 absent or the target emulator/device is not
#                                 connected -- see core/CODEMAP.md.
#
# Outputs a per-run report under logs/test_runs/<timestamp>/ so a failure
# can be triaged without re-running. Exits non-zero on any failure so CI
# (or scripts/dev/run_app.ps1) can fail fast.
#
# Usage:
#   pwsh ./scripts/dev/run_tests.ps1
#   pwsh ./scripts/dev/run_tests.ps1 -Integration
#   pwsh ./scripts/dev/run_tests.ps1 -SkipAnalyze

[CmdletBinding()]
param(
    [switch]$Integration,
    [switch]$SkipAnalyze,
    [string]$EmulatorSerial = 'emulator-5556'
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Resolve-Path "$PSScriptRoot\..\.."
$Mobile = Join-Path $ProjectRoot 'mobile'
$Flutter = 'D:/flutter/bin/flutter.bat'
$Stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$RunDir = Join-Path $ProjectRoot "logs/test_runs/$Stamp"
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

function Run-Step {
    param([string]$Name, [scriptblock]$Body, [string]$LogFile)
    Write-Host ""
    Write-Host "== $Name ==" -ForegroundColor Cyan
    $log = Join-Path $RunDir $LogFile
    & $Body 2>&1 | ForEach-Object {
        Add-Content -Path $log -Value $_ -Encoding utf8
        Write-Host $_
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[$Name] FAILED (exit $LASTEXITCODE) -- see $log" -ForegroundColor Red
        return $false
    }
    Write-Host "[$Name] OK" -ForegroundColor Green
    return $true
}

Push-Location $Mobile
try {
    $results = @{}

    if (-not $SkipAnalyze) {
        $results['analyze'] = Run-Step 'flutter analyze' {
            & $Flutter analyze --no-pub
        } 'analyze.log'
    }

    $results['test'] = Run-Step 'flutter test' {
        & $Flutter test --reporter expanded --coverage
    } 'test.log'

    if ($Integration) {
        # Directory existence is environment-independent -- check it BEFORE device connectivity.
        # Checking device first would mask this behind an unrelated "emulator not running" SKIP
        # whenever no emulator happens to be up, and crash with a raw Flutter error the one time
        # someone runs this against the recommended Pixel_API_34 dev setup. This repo currently
        # has no mobile/integration_test/ -- see core/CODEMAP.md and core/CONVENTIONS.md.
        $IntegrationDir = Join-Path $Mobile 'integration_test'
        if (-not (Test-Path -LiteralPath $IntegrationDir -PathType Container)) {
            Write-Host "[integration] SKIPPED -- mobile/integration_test/ does not exist in this repo" -ForegroundColor Yellow
            $results['integration'] = $null
        } else {
            $devices = & $Flutter devices --machine 2>$null | Out-String
            if ($devices -notmatch [regex]::Escape($EmulatorSerial)) {
                Write-Host "[integration] SKIPPED -- emulator $EmulatorSerial not running" -ForegroundColor Yellow
                $results['integration'] = $null
            } else {
                # One file per `flutter test` invocation, NOT the bare
                # directory -- verified live (2026-08-28) that
                # `flutter test integration_test/ -d <device>` starts
                # building/installing the NEXT file's APK onto the device
                # while a PRIOR file's suite is still mid-run, replacing its
                # app process out from under it; every test after that point
                # reports "did not complete" rather than a real per-test
                # result. Looping gives each file its own process and a full
                # install/run/teardown before the next begins.
                #
                # Aggregate, don't fail-fast: an earlier `return` on the
                # first non-zero exit skipped every later file, so a
                # known-red file (e.g. app_test.dart) silently prevented a
                # later one (e.g. workout_completion_persistence_test.dart)
                # from ever running. GPT-PM round 3 (2026-08-28) caught this.
                # Run every file regardless of prior failures, then report
                # failure only after all of them have run.
                #
                # The aggregate result MUST be surfaced via a real native
                # exit code (`cmd /c exit N`), not a plain `$LASTEXITCODE = N`
                # assignment -- Run-Step invokes this scriptblock via `&`,
                # which creates a child scope, and a direct assignment to
                # $LASTEXITCODE there only shadows the local copy; it does
                # not propagate back to Run-Step's scope, so Run-Step would
                # keep reading whichever real exit code the LAST native
                # `flutter test` call happened to leave behind -- silently
                # masking an earlier real failure whenever the last file in
                # the loop passed. GPT-PM round 4 (2026-08-28) caught this;
                # reproduced and confirmed with a standalone PowerShell
                # scoping test before applying the fix.
                $results['integration'] = Run-Step 'integration tests' {
                    $files = Get-ChildItem -Path $IntegrationDir -Filter '*_test.dart'
                    $hadFailure = $false
                    foreach ($f in $files) {
                        Write-Host "  -- $($f.Name)" -ForegroundColor DarkCyan
                        & $Flutter test $f.FullName -d $EmulatorSerial
                        if ($LASTEXITCODE -ne 0) { $hadFailure = $true }
                    }
                    if ($hadFailure) { cmd /c exit 1 } else { cmd /c exit 0 }
                } 'integration.log'
            }
        }
    }

    $summary = Join-Path $RunDir 'summary.txt'
    $lines = @("Test run $Stamp")
    foreach ($k in $results.Keys) {
        $v = $results[$k]
        $label = if ($v -eq $true) { 'PASS' } elseif ($v -eq $false) { 'FAIL' } else { 'SKIP' }
        $lines += ("  {0,-12} {1}" -f $k, $label)
    }
    $lines | Set-Content -Path $summary -Encoding utf8
    Write-Host ""
    Write-Host "Run summary at $summary" -ForegroundColor Cyan
    Get-Content $summary | Write-Host

    $failed = $results.Values | Where-Object { $_ -eq $false }
    if ($failed) {
        exit 1
    }
} finally {
    Pop-Location
}
