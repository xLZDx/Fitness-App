# RECOG-C1 step 10 — prove the measurement harness is gone, rather than assert it.
#
# The harness is debug-only and compile-gated (`kDebugMode && bool.fromEnvironment`),
# so it cannot execute in a release build. That is a weaker claim than "it is not
# in the tree", and step 10 of the plan asks for the stronger one. This script is
# the difference between the two.
#
# It compares against the PRE-HARNESS BASELINE COMMIT, not against a description
# of what the revert should have done. A revert that removes the file but leaves
# an import, a stray blank line, or a reordered import block is not a revert --
# it is a tree that merely looks reverted, and every later "unchanged since"
# claim built on it would be false.
#
# Written BEFORE the revert, deliberately: a check authored afterwards tends to
# describe whatever the revert happened to produce.
#
# Run it now, before the revert, and it MUST fail -- that is how you know it is
# capable of failing at all. Run it after, and it must pass with no output but
# the summary.

param(
    # The commit the tree must match on these paths. Defaults to the parent of
    # the commit that introduced the harness (81d2237), i.e. step 4's ground-truth
    # freeze, which is the last state of mobile/lib before any measurement code.
    [string]$Baseline = '7eb4392',
    # Runs the comparison even when the measurement document is still missing.
    # Read-only either way; this only lifts the refusal explained at step 0.
    [switch]$Force,
    # Skips the analyzer gate at step 6. Only for a machine with no Flutter
    # toolchain -- the gate is the reason this script now catches what it
    # missed on 2026-09-07, so skipping it is a weaker verification, not an
    # equivalent one.
    [switch]$SkipAnalyze
)

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$harness = 'mobile/lib/features/visual_equipment/measurement/recog_c1_harness.dart'

# Paths that get compiled into the shipped app. Test files and plans are NOT in
# this list on purpose: the measurement's own analysis script, its tests, the
# frozen plan and the raw data are the durable record of the experiment and are
# meant to survive. What must not survive is anything the app itself carries.
$productionPaths = @(
    'mobile/lib',
    'mobile/pubspec.yaml',
    'mobile/android'
)

$failures = New-Object System.Collections.Generic.List[string]

function Fail([string]$Message) { $failures.Add($Message) }

# --- 0. is it even TIME to revert? -------------------------------------------
# This runs before anything else because of what happened on 2026-09-06: the
# operator was told "run it before the revert, it must exit 1", ran it, and got
# a list of 34 items naming every line to remove. That reads as a to-do list,
# not as a warning. They then reverted -- with window 2 still unmeasured, which
# takes the harness out of the tree and makes the second half of the experiment
# unbuildable.
#
# So the script now refuses to print that list at all until the measurement it
# exists to follow actually exists. The output of a check should never be
# mistakable for instructions to do the thing the check is guarding.
$measurement = Join-Path $repo 'core\plans\RECOG_C1_MEASUREMENT_2026-09-05.md'
$harnessPath = Join-Path $repo ($harness -replace '/', '\')
if ((Test-Path $harnessPath) -and -not (Test-Path $measurement)) {
    Write-Host "STOP -- do not revert yet." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  The measurement document does not exist:"
    Write-Host "    core/plans/RECOG_C1_MEASUREMENT_2026-09-05.md"
    Write-Host ""
    Write-Host "  That file is written by step 7, from BOTH windows. Removing the"
    Write-Host "  harness before it exists takes the instrument out of the tree while"
    Write-Host "  half the corpus is still unmeasured -- window 2 could not then be"
    Write-Host "  built at all without first undoing the revert."
    Write-Host ""
    Write-Host "  Run scripts\dev\recog_c1_window2.ps1 first. Come back here after."
    Write-Host ""
    Write-Host "  (Nothing was checked. Pass -Force to run the comparison anyway --"
    Write-Host "   it only reads, it changes nothing.)"
    if (-not $Force) { exit 2 }
    Write-Host ""
}

# --- 1. the baseline must exist, or every comparison below is vacuous ---------
& git -C $repo rev-parse --verify "$Baseline^{commit}" *> $null
if ($LASTEXITCODE -ne 0) {
    throw "baseline commit $Baseline does not exist in this repository; without it this script would compare against nothing and pass"
}
$baselineSha = (& git -C $repo rev-parse $Baseline).Trim()

# --- 2. the harness file must be gone from the working tree AND from HEAD -----
if (Test-Path (Join-Path $repo ($harness -replace '/', '\'))) {
    Fail "$harness still exists in the working tree"
}
& git -C $repo cat-file -e "HEAD:$harness" *> $null
if ($LASTEXITCODE -eq 0) {
    Fail "$harness is still tracked at HEAD (deleting it locally is not the same as removing it from the commit)"
}

# --- 3. every production path must be byte-identical to the baseline ----------
# `git diff --name-status` compares blob hashes, so this is a byte comparison,
# not a "looks the same" comparison. It also catches a file ADDED since the
# baseline that nobody thought to look for.
$drift = @(& git -C $repo diff --name-status "$baselineSha..HEAD" -- $productionPaths | Where-Object { $_ })
foreach ($line in $drift) {
    Fail "differs from the baseline: $line"
}

# --- 4. no reference to the HARNESS may survive anywhere in the app ----------
# Belt and braces against what the blob comparison cannot see: a rename or a
# partial revert can leave a dangling symbol that only a name search finds.
#
# Scoped to the harness's own names, NOT to `recog_c1` generally. The first
# version of this check searched for `recog_c1` and flagged
# `recog_c1_contract.dart` -- which is not part of the harness footprint at all:
# it was committed two steps earlier (7955dac), it is present in the baseline,
# and five committed analysis files import it, including the step-8 metric
# script. Removing it would not be a cleaner revert; it would permanently break
# the tooling that produces the measurement.
#
# Scoped to `mobile`, NOT to `mobile/lib`, and that widening is the whole point
# of this comment. The first real revert, on 2026-09-07, passed this script and
# left the project unable to analyse: `mobile/test/.../recog_c1_harness_test.dart`
# still imported the deleted harness, 42 analyzer errors. The check was looking
# only where the shipped app lives, so it could not see a test that tests code
# that no longer exists -- and a test file cannot survive the thing it tests, no
# matter how much the rest of the measurement's tests are meant to.
$harnessSymbols = 'RecogC1Harness|RecogC1Runner|RecogC1Journal|recog_c1_harness'
$refs = @(& git -C $repo grep -n -E $harnessSymbols -- 'mobile' 2>$null | Where-Object { $_ })
foreach ($r in $refs) {
    Fail "surviving harness reference under mobile/: $r"
}

# --- 5. the frozen contract must STILL be there ------------------------------
# The opposite failure, and the reason this is a positive assertion rather than
# a comment: "prove the tree is byte-identical to the baseline" is also
# satisfied by deleting more than the harness, and an over-broad revert would
# take the scoring contract with it. Every number in the measurement is derived
# through that file; losing it makes the whole experiment unreproducible while
# leaving a tree that looks correctly cleaned.
$contract = 'mobile/lib/features/visual_equipment/measurement/recog_c1_contract.dart'
if (-not (Test-Path (Join-Path $repo ($contract -replace '/', '\')))) {
    Fail "$contract is MISSING. It is not part of the harness: it predates it, it is in the baseline, and the committed analysis imports it. A revert that removes it is too broad."
}

# --- 6. and the tree must actually still ANALYSE -----------------------------
# Byte-identity with a baseline is not the same as a working project, which is
# exactly how the 2026-09-07 revert passed while leaving 42 analyzer errors: the
# harness came OUT of the baseline paths, but its test was ADDED after the
# baseline, so no comparison against the baseline could ever mention it.
#
# This is the check that would have caught it without knowing what to look for.
# It asserts zero ERRORS specifically -- pre-existing infos and warnings are not
# this script's business and must not make a revert unverifiable.
if (-not $SkipAnalyze) {
    $mobile = Join-Path $repo 'mobile'
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        Write-Host "flutter is not on PATH; skipping the analyzer gate. This is a WEAKER verification -- byte-identity alone did not catch the 2026-09-07 breakage."
    }
    else {
        Write-Host "running the analyzer (this is slow, and it is the check that would have caught the 2026-09-07 miss)..."
        Push-Location $mobile
        try { $analysis = & flutter analyze 2>&1 | Out-String }
        finally { Pop-Location }
        # An analyzer that never RAN produces output matching no error pattern,
        # so "found no errors" and "never started" would look identical -- the
        # exact shape of failure this whole gate keeps being bitten by. Require
        # positive evidence that it reached a verdict before believing the
        # verdict.
        if ($analysis -notmatch 'issues found|No issues found') {
            Fail "the analyzer did not reach a verdict, so its silence proves nothing. Output was:`n$($analysis.Trim())"
        }
        else {
            $errorLines = @($analysis -split "`n" | Where-Object { $_ -match '^\s*error\s' })
            foreach ($e in $errorLines) { Fail "analyzer error after the revert: $($e.Trim())" }
            if ($errorLines.Count -eq 0) { Write-Host "  analyzer: 0 errors" }
        }
    }
}

# --- report ------------------------------------------------------------------
if ($failures.Count -gt 0) {
    Write-Host "REVERT NOT VERIFIED against $baselineSha" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
    Write-Host ""
    Write-Host "$($failures.Count) problem(s). The tree still carries measurement code."
    exit 1
}

Write-Host "revert verified: mobile/lib, mobile/pubspec.yaml and mobile/android are byte-identical to $baselineSha; no harness symbol survives anywhere under mobile/ (lib AND test); the analyzer reports zero errors; the frozen scoring contract is still present."
exit 0
