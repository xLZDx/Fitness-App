# measure_context.ps1 -- quantify the per-session AI context tax for this repo.
#
# Measures the three cost layers an AI agent pays when working in this checkout:
#   1. ALWAYS-ON  -- the CLAUDE.md chain, loaded into every single turn's system prompt.
#   2. DOC SURFACE -- markdown an agent may Read while orienting itself.
#   3. CODE SURFACE -- Dart source it may Read while working.
#
# Token estimate uses ~4 chars/token (standard rough ratio for English + code).
# It is an ESTIMATE, not a measurement -- treat it as a relative before/after signal,
# never as an absolute billing figure.
#
# Usage:
#   .\scripts\dev\measure_context.ps1                 # human-readable table
#   .\scripts\dev\measure_context.ps1 -Csv out.csv    # also append a CSV row (for trend tracking)

[CmdletBinding()]
param(
    [string]$Csv = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

function Measure-FileSet {
    param(
        [string]$Label,
        [string[]]$Paths
    )
    $lines = 0
    $chars = 0
    $found = 0
    foreach ($p in $Paths) {
        if (Test-Path -LiteralPath $p) {
            $content = Get-Content -LiteralPath $p -Raw -ErrorAction SilentlyContinue
            if ($null -ne $content) {
                $lines += ([regex]::Matches($content, "`n")).Count + 1
                $chars += $content.Length
                $found++
            }
        }
    }
    [PSCustomObject]@{
        Layer      = $Label
        Files      = $found
        Lines      = $lines
        Chars      = $chars
        EstTokens  = [math]::Round($chars / 4)
    }
}

# --- Layer 1: ALWAYS-ON (the CLAUDE.md inheritance chain) -------------------
$alwaysOn = @(
    (Join-Path $env:USERPROFILE '.claude\CLAUDE.md'),
    'D:\test 2\CLAUDE.md',
    (Join-Path $RepoRoot 'CLAUDE.md'),
    (Join-Path $RepoRoot 'AGENTS.md')
)

# --- Layer 2: DOC SURFACE (markdown an agent might Read) --------------------
$docs = @()
if (Test-Path (Join-Path $RepoRoot 'core')) {
    $docs += (Get-ChildItem -Path (Join-Path $RepoRoot 'core') -Filter '*.md' -Recurse -File |
              Select-Object -ExpandProperty FullName)
}
$rootDocs = Get-ChildItem -Path $RepoRoot -Filter '*.md' -File |
            Select-Object -ExpandProperty FullName
$docs += $rootDocs

# --- Layer 3: CODE SURFACE (Dart source) ------------------------------------
$code = @()
$libPath = Join-Path $RepoRoot 'mobile\lib'
if (Test-Path $libPath) {
    $code = Get-ChildItem -Path $libPath -Filter '*.dart' -Recurse -File |
            Select-Object -ExpandProperty FullName
}

$results = @(
    (Measure-FileSet -Label '1. ALWAYS-ON  (CLAUDE.md chain)' -Paths $alwaysOn),
    (Measure-FileSet -Label '2. DOC SURFACE (core/ + root md)' -Paths $docs),
    (Measure-FileSet -Label '3. CODE SURFACE (mobile/lib)'     -Paths $code)
)

Write-Host ''
Write-Host 'AI CONTEXT COST -- Fitness App' -ForegroundColor Cyan
Write-Host ('Measured: {0} local / {1} UTC' -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm'))
Write-Host ''
$results | Format-Table -AutoSize

$alwaysOnRow = $results[0]
Write-Host ('ALWAYS-ON is the number that matters most: ~{0} tokens are re-sent on EVERY turn.' -f $alwaysOnRow.EstTokens) -ForegroundColor Yellow

# Per-file breakdown of the always-on layer -- this is where the tax concentrates.
Write-Host ''
Write-Host 'ALWAYS-ON breakdown:' -ForegroundColor Cyan
foreach ($p in $alwaysOn) {
    if (Test-Path -LiteralPath $p) {
        $c = Get-Content -LiteralPath $p -Raw
        $l = ([regex]::Matches($c, "`n")).Count + 1
        $leaf = Split-Path $p -Leaf
        $parent = Split-Path (Split-Path $p -Parent) -Leaf
        $label = '{0} ({1})' -f $leaf, $parent
        $tok = [math]::Round($c.Length / 4)
        Write-Host ('  {0,-46} {1,6} lines {2,8} chars ~{3,6} tok' -f $label, $l, $c.Length, $tok)
    } else {
        Write-Host ('  {0,-46} MISSING' -f (Split-Path $p -Leaf))
    }
}
Write-Host ''

if ($Csv -ne '') {
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $needHeader = -not (Test-Path -LiteralPath $Csv)
    if ($needHeader) {
        'measured_at_utc,layer,files,lines,chars,est_tokens' | Out-File -LiteralPath $Csv -Encoding utf8
    }
    foreach ($r in $results) {
        ('{0},"{1}",{2},{3},{4},{5}' -f $stamp, $r.Layer, $r.Files, $r.Lines, $r.Chars, $r.EstTokens) |
            Out-File -LiteralPath $Csv -Encoding utf8 -Append
    }
    Write-Host ('CSV row appended: {0}' -f $Csv) -ForegroundColor Green
}
