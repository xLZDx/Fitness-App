# Debug daemon for the Fitness App.
#
# Spawns five background captures into a timestamped session folder so
# every dev session has one place to look when things break:
#   - flutter.log         flutter+AndroidRuntime+fitness_app logcat lines
#   - errors.log          ERROR/FATAL lines from any tag (broader than flutter.log)
#   - touches.log         every touch-down event w/ timestamp + coords
#   - screencap-*.png     full-screen capture every 30s (visual context)
#   - functions.log       Cloud Functions log poll (every 30s)
#   - meta.json           session metadata: when started, device, app build
#
# Usage:
#   pwsh ./scripts/dev/debug_daemon.ps1                 # session = "default"
#   pwsh ./scripts/dev/debug_daemon.ps1 -Session login  # named session
#
# Stop with Ctrl+C - captures shut down cleanly and the session folder
# stays for review. logs/ is gitignored.

[CmdletBinding()]
param(
    [string]$Session = 'default',
    [string]$EmulatorSerial = 'emulator-5556',
    [string]$Package = 'com.fitnessapp.fitness_app',
    [string]$Project = 'traidingbot-b4061',
    [int]$ScreenshotInterval = 30,
    [int]$FunctionsPollInterval = 30
)

$ErrorActionPreference = 'Continue'
$ProjectRoot = Resolve-Path "$PSScriptRoot\..\.."
$Adb = 'D:/android-sdk/platform-tools/adb.exe'
$Firebase = 'D:/npm-global/firebase.cmd'

# Sanity checks - fail fast if the environment isn't ready.
if (-not (Test-Path $Adb)) {
    throw "adb not found at $Adb. Install Android platform-tools or update the path."
}
if (-not (Test-Path $Firebase)) {
    Write-Warning "firebase CLI not found at $Firebase - Cloud Functions log poll will be disabled."
    $Firebase = $null
}

$devices = & $Adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "^$EmulatorSerial\s+device" }
if (-not $devices) {
    throw "Emulator $EmulatorSerial not attached. Run: emulator -avd Pixel_API_34"
}

# Session folder.
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$SessionDir = Join-Path $ProjectRoot "logs\sessions\$timestamp-$Session"
New-Item -ItemType Directory -Force -Path $SessionDir | Out-Null
Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  Debug daemon  ::  $Session" -ForegroundColor Cyan
Write-Host "  -> $SessionDir" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host ""

# Make taps visible on screen so screenshots show where the user pressed.
& $Adb -s $EmulatorSerial shell settings put system show_touches 1 | Out-Null
& $Adb -s $EmulatorSerial shell settings put system pointer_location 1 | Out-Null

# Drop a meta.json so future-you (or claude) can reconstruct the session.
$appInfo = & $Adb -s $EmulatorSerial shell dumpsys package $Package |
    Select-String -Pattern 'versionName=|firstInstallTime=|lastUpdateTime=' |
    Select-Object -First 5
$meta = @{
    session            = $Session
    started_at         = (Get-Date).ToString('o')
    emulator_serial    = $EmulatorSerial
    package            = $Package
    firebase_project   = $Project
    screenshot_seconds = $ScreenshotInterval
    app_info           = $appInfo | ForEach-Object { $_.Line.Trim() }
} | ConvertTo-Json -Depth 4
Set-Content -Path (Join-Path $SessionDir 'meta.json') -Value $meta

# Background jobs --------------------------------------------------------

# Pre-create the log files so the live tail (below) doesn't race the
# background jobs creating them.
foreach ($f in 'flutter.log', 'errors.log', 'touches.log', 'functions.log') {
    New-Item -ItemType File -Force -Path (Join-Path $SessionDir $f) | Out-Null
}

# 1) Flutter + AndroidRuntime + app-specific logcat. Clear first so the
#    capture is scoped to the current session. Tee-Object on Windows
#    PowerShell 5.1 writes UTF-16-LE which is unreadable in tail/grep —
#    we route through Add-Content with explicit UTF-8 instead.
& $Adb -s $EmulatorSerial logcat -c
$flutterJob = Start-Job -ArgumentList $Adb, $EmulatorSerial, (Join-Path $SessionDir 'flutter.log') -ScriptBlock {
    param($Adb, $Serial, $LogPath)
    & $Adb -s $Serial logcat -v time `
        flutter:V `
        AndroidRuntime:E `
        FlutterActivityAndFragmentDelegate:V `
        FirebaseAuth:V `
        FirebaseFirestore:V `
        CloudFunctions:V `
        '*:S' |
        ForEach-Object {
            Add-Content -Path $LogPath -Value $_ -Encoding utf8
            Write-Output $_
        }
}

# 2) Broader error capture - anything ERROR or FATAL across all tags. Useful
#    for surfacing native crashes or system-side denials that the flutter-
#    only filter misses.
$errorJob = Start-Job -ArgumentList $Adb, $EmulatorSerial, (Join-Path $SessionDir 'errors.log') -ScriptBlock {
    param($Adb, $Serial, $LogPath)
    & $Adb -s $Serial logcat -v time '*:E' |
        ForEach-Object {
            Add-Content -Path $LogPath -Value $_ -Encoding utf8
        }
}

# 3) Touch events. Listens to /dev/input/event2 (the Pixel emulator's
#    multitouch device) and writes a timestamped line for every BTN_TOUCH
#    down event. Coordinates land in flutter.log when the app handles them
#    via gesture detectors.
$touchScript = @'
param($Adb, $Serial, $LogPath)
$touchDevice = & $Adb -s $Serial shell getevent -pl 2>$null |
    Select-String -Pattern '(/dev/input/event\d+).*ABS_MT_POSITION' |
    Select-Object -First 1 |
    ForEach-Object { ($_ -match '/dev/input/event\d+') | Out-Null; $matches[0] }
if (-not $touchDevice) { $touchDevice = '/dev/input/event2' }
& $Adb -s $Serial shell "getevent -lt $touchDevice" 2>$null |
    Where-Object { $_ -match 'BTN_TOUCH|ABS_MT_POSITION' } |
    ForEach-Object { Add-Content -Path $LogPath -Value $_ -Encoding utf8 }
'@
$touchJob = Start-Job -ScriptBlock ([ScriptBlock]::Create($touchScript)) `
    -ArgumentList $Adb, $EmulatorSerial, (Join-Path $SessionDir 'touches.log')

# 4) Screenshot loop.
$screenshotJob = Start-Job -ArgumentList $Adb, $EmulatorSerial, $SessionDir, $ScreenshotInterval -ScriptBlock {
    param($Adb, $Serial, $Dir, $Interval)
    $i = 0
    while ($true) {
        $idx = $i.ToString().PadLeft(4, '0')
        $stamp = Get-Date -Format 'HHmmss'
        $remote = "/sdcard/dbg-$idx.png"
        $local = Join-Path $Dir "screencap-$idx-$stamp.png"
        & $Adb -s $Serial shell screencap -p $remote *>$null
        & $Adb -s $Serial pull $remote $local *>$null
        & $Adb -s $Serial shell rm $remote *>$null
        $i++
        Start-Sleep -Seconds $Interval
    }
}

# 5) Cloud Functions log poll.
if ($Firebase) {
    $functionsJob = Start-Job -ArgumentList $Firebase, $Project, (Join-Path $SessionDir 'functions.log'), $FunctionsPollInterval -ScriptBlock {
        param($Firebase, $Project, $LogPath, $Interval)
        $seen = @{}
        while ($true) {
            $output = & $Firebase functions:log --project $Project 2>&1 | Out-String
            $lines = $output -split "`r?`n"
            foreach ($line in $lines) {
                if ($line -match '^\d{4}-\d{2}-\d{2}T') {
                    $key = ($line.Substring(0, [Math]::Min($line.Length, 200)))
                    if (-not $seen.ContainsKey($key)) {
                        $seen[$key] = $true
                        Add-Content -Path $LogPath -Value $line
                    }
                }
            }
            Start-Sleep -Seconds $Interval
        }
    }
}

Write-Host "Captures live (Ctrl+C to stop):" -ForegroundColor Green
Write-Host "  flutter.log    - flutter + crash + auth + firestore + functions" -ForegroundColor Gray
Write-Host "  errors.log     - every ERROR/FATAL line, all tags" -ForegroundColor Gray
Write-Host "  touches.log    - touch-down events" -ForegroundColor Gray
Write-Host "  screencap-*.png - every $ScreenshotInterval s" -ForegroundColor Gray
if ($Firebase) {
    Write-Host "  functions.log  - Cloud Functions logs (poll every $FunctionsPollInterval s)" -ForegroundColor Gray
}
Write-Host ""

# Live tail of flutter.log so the operator sees what's happening.
try {
    Start-Sleep -Seconds 1
    Get-Content -Path (Join-Path $SessionDir 'flutter.log') -Tail 0 -Wait |
        ForEach-Object {
            if ($_ -match 'E/|FATAL|EXCEPTION|Error|Failed') {
                Write-Host $_ -ForegroundColor Red
            } elseif ($_ -match 'W/|warning|Warning') {
                Write-Host $_ -ForegroundColor Yellow
            } else {
                Write-Host $_
            }
        }
} finally {
    Write-Host ""
    Write-Host "Stopping captures..." -ForegroundColor Cyan
    foreach ($job in @($flutterJob, $errorJob, $touchJob, $screenshotJob)) {
        if ($job) { Stop-Job -Job $job -ErrorAction SilentlyContinue; Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
    }
    if ($functionsJob) { Stop-Job -Job $functionsJob -ErrorAction SilentlyContinue; Remove-Job -Job $functionsJob -Force -ErrorAction SilentlyContinue }

    # Reset show_touches / pointer_location.
    & $Adb -s $EmulatorSerial shell settings put system show_touches 0 | Out-Null
    & $Adb -s $EmulatorSerial shell settings put system pointer_location 0 | Out-Null

    # Quick session summary.
    function _SizeKB($path) {
        $item = Get-Item -ErrorAction SilentlyContinue -Path $path
        if ($item) { return [math]::Round($item.Length / 1KB, 1) }
        return 0
    }
    $flutterSize = _SizeKB (Join-Path $SessionDir 'flutter.log')
    $errorSize = _SizeKB (Join-Path $SessionDir 'errors.log')
    $touchSize = _SizeKB (Join-Path $SessionDir 'touches.log')
    $screencapCount = @(Get-ChildItem -Path $SessionDir -Filter 'screencap-*.png' -ErrorAction SilentlyContinue).Count
    Write-Host ""
    Write-Host "Session summary:" -ForegroundColor Green
    Write-Host "  flutter.log   $flutterSize KB"
    Write-Host "  errors.log    $errorSize KB"
    Write-Host "  touches.log   $touchSize KB"
    Write-Host "  screencaps    $screencapCount"
    Write-Host "  -> $SessionDir"
}
