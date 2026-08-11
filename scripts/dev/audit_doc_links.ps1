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
#
# Every entry here is a class of identifier that happens to contain a slash. Adding
# one is only legitimate when the thing genuinely is not a repo path -- never to
# quieten a reference that IS a path and simply does not resolve. The gate exists to
# be believed, and an ignore list used as a mute button destroys that.
$ignoreRegex = @(
    '^r/',                                  # reddit subs
    '^(cloud_firestore|firebase_\w+)/',     # SDK error codes
    'NNNN|XXXX|\.\.\.',                     # placeholder names
    '^ABS_MT_',                             # evdev constants
    '^(users|stats)/',                      # firestore collection/document paths
    '^\w+\.example\.com',                   # example hostnames
    '^(android|ios)/',                       # platform prose
    '^v?\d+\.\d+',                          # version strings
    '^meta\.json$',                         # generated per-run into logs/sessions/<latest>/
    '^logs/',                               # runtime output (gitignored): sessions/, test_runs/
    '^origin/',                             # git refs -- origin/master is not a directory
    '^roles/',                              # GCP IAM role ids, e.g. roles/storage.objectViewer
    '^projects/\d+',                        # GCP resource names
    '^xLZDx/',                              # this repo's own GitHub owner/name slug
    '^(xiaoshis-workspace|thestalkers-project)/',  # Roboflow workspace/project ids
    '^out_v2/',                             # training outputs under D:\tools\equipment-model
    '^men/$',                               # subdir of the external vendor clip library
    '^lib/(arm64-v8a|armeabi-v7a|x86_64)/', # paths INSIDE a packaged .aar/.apk, not the tree
    '^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.(com|org|net|io|app|dev|me)/',  # hostnames without a scheme
    '^[A-Z][A-Za-z]+/[A-Z][A-Za-z]+$',      # two type names, e.g. Flexible/Expanded
    '^\d+/\d+$',                            # a fraction -- "10/30 datasets", not a directory
    '^(bangkit-academy-ognnb|fitfuel)/'     # Roboflow dataset ids, same class as the two above
)

# Docs that record a PAST state: a log entry, a dated snapshot, a removal record. They name
# what was there at the time, on purpose, and rewriting them to match today would destroy the
# record. Reported separately so the list stays visible, but they do not fail the gate.
#
# This is the second-largest class in the pre-fix FAIL list, and the clearest example is
# `LEGACY_CATALOG_REMOVED_2026-08-04.md` -- a document whose entire subject is that those
# files no longer exist, failing a gate for saying so.
#
# A DATE IN THE FILENAME is the strongest signal of all: `BACKLOG_2026-07-31.md`,
# `B1_RECOGNITION_MEASUREMENT_2026-08-07.md` and the rest are snapshots of a day, and a
# snapshot that has been edited to stay green is no longer a snapshot. Note this silences
# the gate on those files, not the obligation -- a false CLAIM inside a dated doc is still
# worth correcting when found, it just is not this gate's job to find it.
$historicalDocRe = '(?i)(DECISION_LOG|_REMOVED_|SESSION_STATE_|SESSION_HANDOFF_|STATE_H_GATES_|^PLAN_|_AUDIT_|CHANGELOG|_20\d\d-\d\d-\d\d)'

# Imported design material describing an EXTERNAL artefact (the Figma Make prototype and
# its sibling zip). These docs are not claims about this tree, and their `App.tsx` lives
# in an archive that was never checked in -- which the docs themselves say plainly.
$referenceDirRe = '(?i)\\docs\\Redisign\\'

$extRe = '^[A-Za-z0-9_.\-/\\ ]+\.(?:md|dart|ts|tsx|ps1|json|yaml|yml|kt|gradle|xml|csv|png|tflite)$'
$dirRe = '^(?:[A-Za-z0-9_.\-]+[/\\])+[A-Za-z0-9_.\-]*$'

# Pre-index every file basename in the repo (excluding build output) for the fallback lookup,
# and every SEGMENT SUFFIX of every path for the partial-path lookup below.
$basenameIndex = @{}
$suffixIndex   = @{}
$skipDirs = '\\(build|\.dart_tool|node_modules|\.git|logs|\.gradle|Pods)\\'

# Docs legitimately write a path relative to the thing they are describing. CODEMAP's
# `workouts` row says `data/cue_player.dart`, meaning
# `mobile/lib/features/workouts/data/cue_player.dart` -- which is clearer for a reader
# than repeating the feature directory in every cell. Resolving only against a fixed set
# of bases called all of those broken, and that one convention accounted for a large part
# of a 98-entry FAIL list: the docs were right and the checker was not.
#
# Indexing every suffix instead. Segment boundaries only, so `art.dart` never matches
# `smart.dart`, and the reference still has to name a real tail of a real path.
function Add-Suffixes {
    param([string]$RelPath)
    $norm = $RelPath -replace '\\', '/'
    $segs = $norm -split '/'
    for ($i = $segs.Count - 1; $i -ge 0; $i--) {
        $suffixIndex[(($segs[$i..($segs.Count - 1)]) -join '/').ToLower()] = $true
    }
}

Get-ChildItem -Path $RepoRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch $skipDirs } |
    ForEach-Object {
        $basenameIndex[$_.Name.ToLower()] = $true
        Add-Suffixes -RelPath $_.FullName.Substring($RepoRoot.Length + 1)
    }

# Directories too, so `widgets/` and `onboarding/steps/` resolve the same way.
Get-ChildItem -Path $RepoRoot -Recurse -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch $skipDirs } |
    ForEach-Object { Add-Suffixes -RelPath $_.FullName.Substring($RepoRoot.Length + 1) }

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
    # Bare filename -- or a bare directory name like `widgets/`, which the trim above has
    # already reduced to a single segment. Both are looked up by name anywhere in the repo.
    if ($norm -notmatch '/') {
        if ($basenameIndex.ContainsKey($norm.ToLower())) { return $true }
        if ($suffixIndex.ContainsKey($norm.ToLower())) { return $true }
        return $false
    }
    # A tail of a real path: the feature-relative convention described at the index above.
    if ($suffixIndex.ContainsKey($norm.ToLower())) { return $true }
    return $false
}

$broken     = New-Object System.Collections.Generic.List[object]
$planned    = New-Object System.Collections.Generic.List[object]
$historical = New-Object System.Collections.Generic.List[object]
$checked = 0

foreach ($doc in $targets) {
    $text   = Get-Content -LiteralPath $doc.FullName -Raw
    $rel    = $doc.FullName.Substring($RepoRoot.Length + 1)
    $docDir = Split-Path $doc.FullName -Parent
    $isPlanning   = $planningDocs -contains $doc.Name
    $isHistorical = ($doc.Name -match $historicalDocRe) -or
                    ($doc.FullName -match $referenceDirRe)

    # Scan line by line so we can (a) report line numbers and (b) read the surrounding
    # sentence. A doc that says "there is no `foo/`" is documenting an absence on purpose --
    # that must not be reported as a broken link, or the gate becomes noise people ignore.
    $negationRe = '(?i)\b(no|not|never|absent|missing|removed|deleted|instead of|do not|don''t|doesn''t|does not|will fail|unbuilt|nonexistent)\b'

    $cands = New-Object System.Collections.Generic.List[object]
    $lineNo = 0
    $prevLine = ''
    foreach ($line in ($text -split "`r?`n")) {
        $lineNo++
        # Look back one line too: markdown prose wraps, so "...files that do not exist yet"
        # frequently sits on the line above the paths it is talking about.
        $isNegated = ($line -match $negationRe) -or
                     (($prevLine.Trim() -ne '') -and ($prevLine -match $negationRe))
        $prevLine = $line
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
            if ($isPlanning) { $planned.Add($row) }
            elseif ($isHistorical) { $historical.Add($row) }
            else { $broken.Add($row) }
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

if ($historical.Count -gt 0 -and -not $Quiet) {
    Write-Host ('HISTORICAL -- {0} reference(s) in logs, dated snapshots and removal records (not a failure):' -f $historical.Count) -ForegroundColor DarkGray
    $historical | Sort-Object Doc, Line | Format-Table -AutoSize
}

if ($broken.Count -eq 0) {
    Write-Host ('PASS -- 0 broken references across {0} checked.' -f $checked) -ForegroundColor Green
    exit 0
} else {
    Write-Host ('FAIL -- {0} BROKEN reference(s) in non-planning docs:' -f $broken.Count) -ForegroundColor Red
    $broken | Sort-Object Doc, Line | Format-Table -AutoSize
    exit 1
}
