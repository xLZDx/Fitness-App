# audit_doc_links.ps1 -- verify every path a markdown doc points at actually exists.
#
# WHY: an AI agent trusts the docs. A doc naming a file that is not there sends the agent
# hunting through the tree (burning tokens) or, worse, acting on a false assumption. This
# makes that class of bug a checkable gate instead of something discovered by accident.
#
# Two verdicts, because two different things look identical to a naive checker:
#   BROKEN  -- an engineering doc names something that should exist but does not. A bug.
#   PLANNED -- a planning/roadmap doc names a future artefact. Legitimate; reported, not failed.
#
# Resolution is tried against several bases (doc's own dir, repo root, mobile/, mobile/lib/)
# and finally by basename anywhere in the repo, because docs legitimately write `main.dart`
# or a sibling `ROADMAP.md` without a full path.
#
# Usage:
#   .\scripts\dev\audit_doc_links.ps1              # full report
#   .\scripts\dev\audit_doc_links.ps1 -Quiet       # findings only
# Exit code: 0 = no BROKEN references (PLANNED ones do not fail the gate), 1 = at least one BROKEN.

[CmdletBinding()]
param(
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# Docs whose unresolved references are FORWARD-LOOKING, not broken.
$planningDocs = @(
    'ROADMAP_2026_V2.md', 'NEXT_TICKETS.md', 'USER_GROWTH_PLAN.md', 'NONPROFIT_PLAN.md',
    'PITCH_2026.md', 'IMPLEMENTATION_PLAN.md', 'COMPETITIVE_ASSESSMENT.md',
    'FITNESS_APP_TASK_LIST.md', 'PLAN_AI_RESTRUCTURE_2026-07-28.md'
)

# Things that pattern-match like a path but are not one.
$ignoreRegex = @(
    '^r/',                                  # reddit subs
    '^(cloud_firestore|firebase_\w+)/',     # SDK error codes
    'NNNN|XXXX|\.\.\.',                     # placeholder names
    '^ABS_MT_',                             # evdev constants
    '^users/',                              # firestore document paths
    '^\w+\.example\.com',                   # example hostnames
    '^(android|ios)/',                       # platform prose
    '^v?\d+\.\d+',                          # version strings
    '^meta\.json$'                          # generated per-run into logs/sessions/<latest>/
)

$extRe = '^[A-Za-z0-9_.\-/\\ ]+\.(?:md|dart|ts|tsx|ps1|json|yaml|yml|kt|gradle|xml|csv|png|tflite)$'
$dirRe = '^(?:[A-Za-z0-9_.\-]+[/\\])+[A-Za-z0-9_.\-]*$'

# Pre-index every file basename in the repo (excluding build output) for the fallback lookup.
$basenameIndex = @{}
$skipDirs = '\\(build|\.dart_tool|node_modules|\.git|logs|\.gradle|Pods)\\'
Get-ChildItem -Path $RepoRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch $skipDirs } |
    ForEach-Object { $basenameIndex[$_.Name.ToLower()] = $true }

$targets = @()
$targets += Get-ChildItem -Path $RepoRoot -Filter '*.md' -File
foreach ($sub in @('core', '.claude', 'docs')) {
    $d = Join-Path $RepoRoot $sub
    if (Test-Path $d) { $targets += Get-ChildItem -Path $d -Filter '*.md' -Recurse -File }
}

function Test-Reference {
    param([string]$Ref, [string]$DocDir)
    $norm = ($Ref -replace '\\', '/') -replace '^\./', ''
    $norm = $norm.TrimEnd('/')
    if ($norm -eq '') { return $true }

    $bases = @($DocDir, $RepoRoot, (Join-Path $RepoRoot 'mobile'), (Join-Path $RepoRoot 'mobile\lib'))
    foreach ($b in $bases) {
        if (Test-Path -LiteralPath (Join-Path $b $norm)) { return $true }
    }
    # Bare filename anywhere in the repo.
    if ($norm -notmatch '/') {
        if ($basenameIndex.ContainsKey($norm.ToLower())) { return $true }
    } else {
        $leaf = Split-Path $norm -Leaf
        if ($leaf -match '\.' -and $basenameIndex.ContainsKey($leaf.ToLower())) {
            # Basename exists but at a different path -- still a doc inaccuracy, but a soft one.
            return $false
        }
    }
    return $false
}

$broken  = New-Object System.Collections.Generic.List[object]
$planned = New-Object System.Collections.Generic.List[object]
$checked = 0

foreach ($doc in $targets) {
    $text   = Get-Content -LiteralPath $doc.FullName -Raw
    $rel    = $doc.FullName.Substring($RepoRoot.Length + 1)
    $docDir = Split-Path $doc.FullName -Parent
    $isPlanning = $planningDocs -contains $doc.Name

    # Scan line by line so we can (a) report line numbers and (b) read the surrounding
    # sentence. A doc that says "there is no `foo/`" is documenting an absence on purpose --
    # that must not be reported as a broken link, or the gate becomes noise people ignore.
    $negationRe = '(?i)\b(no|not|never|absent|missing|removed|deleted|instead of|do not|don''t|doesn''t|does not|will fail|unbuilt|nonexistent)\b'

    $cands = New-Object System.Collections.Generic.List[object]
    $lineNo = 0
    foreach ($line in ($text -split "`r?`n")) {
        $lineNo++
        $isNegated = $line -match $negationRe
        foreach ($m in [regex]::Matches($line, '`([^`]+)`')) {
            $cands.Add([PSCustomObject]@{ V = $m.Groups[1].Value; L = $lineNo; N = $isNegated })
        }
        foreach ($m in [regex]::Matches($line, '\]\(([^)]+)\)')) {
            $cands.Add([PSCustomObject]@{ V = $m.Groups[1].Value; L = $lineNo; N = $isNegated })
        }
    }

    $seen = @{}
    foreach ($c in $cands) {
        if ($c.N) { continue }   # deliberate reference to something that is absent
        $cand = ($c.V.Trim() -split '#')[0].Trim()
        if ($cand -eq '' -or $cand -match '[*?]' -or $cand -match '^https?:') { continue }
        if ($cand -match '\s') { continue }
        if (-not (($cand -match $extRe) -or ($cand -match $dirRe))) { continue }

        $skip = $false
        foreach ($ig in $ignoreRegex) { if ($cand -match $ig) { $skip = $true; break } }
        if ($skip) { continue }
        if ($cand -match '^(D:|C:|~|github\.com)') { continue }

        $key = "$rel|$cand"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true

        $checked++
        if (-not (Test-Reference -Ref $cand -DocDir $docDir)) {
            $row = [PSCustomObject]@{ Doc = $rel; Line = $c.L; Reference = $cand }
            if ($isPlanning) { $planned.Add($row) } else { $broken.Add($row) }
        }
    }
}

if (-not $Quiet) {
    Write-Host ''
    Write-Host 'DOC LINK AUDIT -- Fitness App' -ForegroundColor Cyan
    Write-Host ('Docs scanned: {0}   Unique path references checked: {1}' -f $targets.Count, $checked)
    Write-Host ''
}

if ($planned.Count -gt 0) {
    Write-Host ('PLANNED -- {0} forward-looking reference(s) in planning docs (not a failure):' -f $planned.Count) -ForegroundColor DarkYellow
    $planned | Sort-Object Doc, Line | Format-Table -AutoSize
}

if ($broken.Count -eq 0) {
    Write-Host ('PASS -- 0 broken references across {0} checked.' -f $checked) -ForegroundColor Green
    exit 0
} else {
    Write-Host ('FAIL -- {0} BROKEN reference(s) in non-planning docs:' -f $broken.Count) -ForegroundColor Red
    $broken | Sort-Object Doc, Line | Format-Table -AutoSize
    exit 1
}
