# One-shot dev runner.
#
# Rebuilds the debug APK if missing, force-stops + clears the app on the
# emulator, launches it fresh, then hands the terminal to debug_daemon.ps1
# so every tap, log line, error and screencap from the session is captured
# under logs/sessions/.
#
# Usage:
#   pwsh ./scripts/dev/run_app.ps1
#   pwsh ./scripts/dev/run_app.ps1 -Session stripe-flow
#   pwsh ./scripts/dev/run_app.ps1 -Session login -Rebuild

[CmdletBinding()]
param(
    [string]$Session = 'default',
    [string]$EmulatorSerial = 'emulator-5556',
    [string]$Package = 'com.fitnessapp.fitness_app',
    [switch]$Rebuild
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Resolve-Path "$PSScriptRoot\..\.."
$Adb = 'D:/android-sdk/platform-tools/adb.exe'
$Flutter = 'D:/flutter/bin/flutter.bat'
$Apk = Join-Path $ProjectRoot 'mobile\build\app\outputs\flutter-apk\app-debug.apk'

if ($Rebuild -or -not (Test-Path $Apk)) {
    Write-Host "Building debug APK..." -ForegroundColor Cyan
    Push-Location (Join-Path $ProjectRoot 'mobile')
    try {
        & $Flutter build apk --debug
        if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed ($LASTEXITCODE)" }
    } finally {
        Pop-Location
    }
}

Write-Host "Installing $Apk..." -ForegroundColor Cyan
& $Adb -s $EmulatorSerial install -r $Apk
if ($LASTEXITCODE -ne 0) { throw "adb install failed ($LASTEXITCODE)" }

Write-Host "Clearing app state + launching $Package..." -ForegroundColor Cyan
& $Adb -s $EmulatorSerial shell am force-stop $Package
& $Adb -s $EmulatorSerial shell pm clear $Package
& $Adb -s $EmulatorSerial shell am start -n "$Package/.MainActivity"

# Hand over to the daemon. Captures stay alive until Ctrl+C.
& (Join-Path $PSScriptRoot 'debug_daemon.ps1') -Session $Session -EmulatorSerial $EmulatorSerial -Package $Package
