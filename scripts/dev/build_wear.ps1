# Build + install the Wear OS companion APK.
#
# Pre-reqs:
#   - Wear OS emulator running (or paired physical watch with adb-debug)
#   - Android SDK + Gradle on PATH
#
# Usage:
#   pwsh ./scripts/dev/build_wear.ps1                # debug build
#   pwsh ./scripts/dev/build_wear.ps1 -Release       # release build
#   pwsh ./scripts/dev/build_wear.ps1 -EmulatorSerial emulator-5554

[CmdletBinding()]
param(
    [switch]$Release,
    [string]$EmulatorSerial = ''
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Resolve-Path "$PSScriptRoot\..\.."
$WearDir = Join-Path $ProjectRoot 'wear'
$Adb = 'D:/android-sdk/platform-tools/adb.exe'

if (-not (Test-Path (Join-Path $WearDir 'build.gradle.kts'))) {
    throw "wear/ module not found at $WearDir"
}

Push-Location $WearDir
try {
    Write-Host 'Building Wear OS APK...' -ForegroundColor Cyan
    if ($Release) {
        & ./gradlew.bat :wear-app:assembleRelease
    } else {
        & ./gradlew.bat :wear-app:assembleDebug
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Wear gradle build failed (exit $LASTEXITCODE)"
    }

    # Find the produced APK.
    $apk = Get-ChildItem -Path 'build/outputs/apk' -Recurse -Filter '*.apk' |
        Where-Object { $_.FullName -match ($Release ? 'release' : 'debug') } |
        Select-Object -First 1
    if (-not $apk) {
        throw "No APK produced under wear/build/outputs/apk"
    }
    Write-Host "Built $($apk.FullName)" -ForegroundColor Green

    if ($EmulatorSerial) {
        Write-Host "Installing onto $EmulatorSerial..." -ForegroundColor Cyan
        & $Adb -s $EmulatorSerial install -r $apk.FullName
        if ($LASTEXITCODE -ne 0) {
            throw "adb install failed (exit $LASTEXITCODE)"
        }
        Write-Host 'Installed. Wake the watch face to see it.' -ForegroundColor Green
    } else {
        Write-Host 'Skipping install (no -EmulatorSerial provided).' -ForegroundColor Yellow
        Write-Host "  Install manually: $Adb -s <serial> install -r $($apk.FullName)"
    }
} finally {
    Pop-Location
}
