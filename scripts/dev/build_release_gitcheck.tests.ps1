# Deterministic proof for Get-GitDirtyStamp's three branches (build_release_gitcheck.ps1).
#
# No git process and no repository involved on purpose -- the previous "fix
# verified" claim for this exact logic was two ordinary `build_release.ps1`
# runs, which only ever drove the clean and dirty (0/1) paths and never
# actually exercised the >1-throws branch it was written to add. This
# exists to close that gap with a real, repeatable result instead of another
# "it built successfully" anecdote.
#
# Run: pwsh ./scripts/dev/build_release_gitcheck.tests.ps1
# Exits 0 with "ALL PASSED" iff every case below matched; exits 1 and prints
# every mismatch otherwise. No third-party test framework (no Pester in this
# repo, unlike the Python/pytest scripts under scripts/*) -- deliberately
# small enough not to need one.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'build_release_gitcheck.ps1')

$failures = @()

function Assert-Stamp {
    param([int]$ExitCode, [string]$Base, [string]$Expected)
    try {
        $actual = Get-GitDirtyStamp -DiffExitCode $ExitCode -BaseSha $Base
        if ($actual -ne $Expected) {
            $script:failures += "exit ${ExitCode}: expected '$Expected', got '$actual'"
        }
    } catch {
        $script:failures += "exit ${ExitCode}: expected '$Expected', threw instead: $($_.Exception.Message)"
    }
}

function Assert-Throws {
    param([int]$ExitCode, [string]$Base)
    try {
        $actual = Get-GitDirtyStamp -DiffExitCode $ExitCode -BaseSha $Base
        $script:failures += "exit ${ExitCode}: expected a throw, got '$actual' instead"
    } catch {
        # Expected path -- the exit-code value itself must be traceable in the
        # message, or a future edit could silently swap in a generic error.
        if ($_.Exception.Message -notmatch [regex]::Escape("$ExitCode")) {
            $script:failures += "exit ${ExitCode}: threw, but message did not mention the exit code: $($_.Exception.Message)"
        }
    }
}

# 0 = clean: the stamp is untouched.
Assert-Stamp -ExitCode 0 -Base 'abc1234' -Expected 'abc1234'

# 1 = dirty: the documented, intentional control-flow path.
Assert-Stamp -ExitCode 1 -Base 'abc1234' -Expected 'abc1234-dirty'

# Anything else: the comparison itself failed, so this must throw rather than
# silently stamp -dirty and ship a build whose source state was never
# actually verified. 128 is a real git exit code (fatal repository error);
# 2 stands in for any other non-0/1 value.
Assert-Throws -ExitCode 128 -Base 'abc1234'
Assert-Throws -ExitCode 2 -Base 'abc1234'

if ($failures.Count -gt 0) {
    Write-Host "FAILED:" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}

Write-Host "ALL PASSED: Get-GitDirtyStamp -- 0 (clean), 1 (dirty), 128 and 2 (throws)" -ForegroundColor Green
exit 0
