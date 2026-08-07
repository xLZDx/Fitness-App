# `flutter run` wrapped with the debug daemon.
#
# Starts the daemon in a separate child process so both run side-by-side:
# the daemon captures device logs / errors / touches / screencaps, while
# `flutter run` keeps hot-reload working in the foreground. When the user
# hits 'q' to quit flutter, the daemon gets a clean shutdown.
#
# Usage:
#   pwsh ./scripts/dev/run_with_debug.ps1
#   pwsh ./scripts/dev/run_with_debug.ps1 -Session feature-x
#   pwsh ./scripts/dev/run_with_debug.ps1 -Profile

[CmdletBinding()]
param(
    [string]$Session = 'default',
    [string]$EmulatorSerial = 'emulator-5556',
    [string]$Package = 'com.fitnessapp.fitness_app.sptr',
    [switch]$Profile,
    [switch]$Release
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Resolve-Path "$PSScriptRoot\..\.."
$Mobile = Join-Path $ProjectRoot 'mobile'
$Flutter = 'D:/flutter/bin/flutter.bat'

# Launch the daemon as a background pwsh process so it tails logs
# while we hand the foreground to `flutter run`.
$daemonScript = Join-Path $PSScriptRoot 'debug_daemon.ps1'
$daemonArgs = @(
    '-NoLogo', '-NonInteractive',
    '-File', $daemonScript,
    '-Session', $Session,
    '-EmulatorSerial', $EmulatorSerial,
    '-Package', $Package
)
Write-Host "Starting debug daemon (session=$Session)..." -ForegroundColor Cyan
$daemon = Start-Process -FilePath 'pwsh' -ArgumentList $daemonArgs -PassThru -WindowStyle Hidden

# Run flutter in the foreground. Hot reload + restart still work as
# usual; the daemon listens to logcat in parallel.
$mode = '--debug'
if ($Profile) { $mode = '--profile' }
if ($Release) { $mode = '--release' }

Push-Location $Mobile
try {
    Write-Host "flutter run $mode (-d $EmulatorSerial)" -ForegroundColor Cyan
    & $Flutter run $mode -d $EmulatorSerial
} finally {
    Pop-Location
    if ($daemon -and -not $daemon.HasExited) {
        Write-Host "Stopping debug daemon..." -ForegroundColor Cyan
        Stop-Process -Id $daemon.Id -Force -ErrorAction SilentlyContinue
    }
}
