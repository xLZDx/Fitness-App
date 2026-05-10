# Seed `assets/data/exercises.json` with stock-video URLs sourced from
# Pexels' free-license fitness library (CC0-equivalent).
#
# Workaround for the $5–15k contracted-shoot path: we ship with a
# stock-clip starter set, then layer community-contributed clips on top
# via the moderation queue. Quality is "generic but acceptable" — the
# moat is still injury-aware programming, not the videos themselves.
#
# Usage:
#   pwsh ./scripts/catalog/seed_stock_videos.ps1            # dry-run
#   pwsh ./scripts/catalog/seed_stock_videos.ps1 -Apply
#
# The dry-run prints a diff-style report; -Apply rewrites the file.

[CmdletBinding()]
param(
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$Root = Resolve-Path "$PSScriptRoot\..\.."
$Path = Join-Path $Root 'mobile\assets\data\exercises.json'

if (-not (Test-Path $Path)) {
    throw "exercises.json not found at $Path"
}

# Static, hand-curated allowlist. These are direct CDN URLs to Pexels
# free-license MP4s; the stock-clip ID/license check happened during
# allowlist authoring (see core/STOCK_CLIPS.md). Hashed via exerciseId
# so adding a new exercise doesn't shuffle existing assignments.
$Stock = @{
    'squat'          = 'https://videos.pexels.com/video-files/4754030/4754030-uhd_1440_2732_30fps.mp4'
    'deadlift'       = 'https://videos.pexels.com/video-files/4754027/4754027-uhd_1440_2732_30fps.mp4'
    'bench_press'    = 'https://videos.pexels.com/video-files/4794233/4794233-uhd_1440_2732_30fps.mp4'
    'overhead_press' = 'https://videos.pexels.com/video-files/4754030/4754030-uhd_1440_2732_30fps.mp4'
    'plank'          = 'https://videos.pexels.com/video-files/3823206/3823206-hd_1280_720_50fps.mp4'
    'lunge'          = 'https://videos.pexels.com/video-files/4754029/4754029-uhd_1440_2732_30fps.mp4'
    'row_barbell'    = 'https://videos.pexels.com/video-files/4754026/4754026-uhd_1440_2732_30fps.mp4'
    'pushup'         = 'https://videos.pexels.com/video-files/3823206/3823206-hd_1280_720_50fps.mp4'
}

$json = Get-Content $Path -Raw | ConvertFrom-Json
$updates = @()

foreach ($entry in $json) {
    if (-not $entry.id) { continue }
    if ($Stock.ContainsKey($entry.id) -and (-not $entry.videoUrl)) {
        $updates += [pscustomobject]@{
            id     = $entry.id
            title  = $entry.title
            url    = $Stock[$entry.id]
            action = 'add'
        }
        if ($Apply) {
            Add-Member -InputObject $entry -NotePropertyName 'videoUrl' -NotePropertyValue $Stock[$entry.id] -Force
        }
    }
}

if ($updates.Count -eq 0) {
    Write-Host 'No updates needed.' -ForegroundColor Green
    return
}

Write-Host "Updates ($(if ($Apply) { 'applying' } else { 'dry-run' })):" -ForegroundColor Cyan
foreach ($u in $updates) {
    Write-Host ("  + {0,-18}  {1}" -f $u.id, $u.url)
}

if ($Apply) {
    $json | ConvertTo-Json -Depth 12 | Set-Content -Path $Path -Encoding utf8
    Write-Host "Wrote $Path" -ForegroundColor Green
}
