# Deterministic proof for the CR-04 build-profile decision (build_release_profile.ps1).
# Run: pwsh ./scripts/dev/build_release_profile.tests.ps1
# Exits 0 with "ALL PASSED" iff every case matched. No Pester, same as
# build_release_gitcheck.tests.ps1.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'build_release_profile.ps1')
$failures = @()

function Check($name, [scriptblock]$body) {
    try { & $body } catch { $script:failures += "${name}: $($_.Exception.Message)" }
}
function Expect($cond, $msg) { if (-not $cond) { throw $msg } }

Check 'store disables override' {
    $d = Get-ProfileDefines -BuildProfile store
    Expect ($d -contains '--dart-define=ALLOW_TIER_OVERRIDE=false') "store must pass ALLOW_TIER_OVERRIDE=false: $d"
    Expect (-not ($d -contains '--dart-define=ALLOW_TIER_OVERRIDE=true')) 'store must never pass =true'
}
Check 'personal and test allow override explicitly' {
    foreach ($p in 'personal', 'test') {
        $d = Get-ProfileDefines -BuildProfile $p
        Expect ($d -contains '--dart-define=ALLOW_TIER_OVERRIDE=true') "$p must pass ALLOW_TIER_OVERRIDE=true explicitly: $d"
        Expect ($d -contains "--dart-define=BUILD_PROFILE=$p") "$p must label itself: $d"
    }
}
Check 'unknown profile throws' {
    $threw = $false
    try { Get-ProfileDefines -BuildProfile 'prod' | Out-Null } catch { $threw = $true }
    Expect $threw 'an unknown profile must be refused, not defaulted'
}
Check 'store guard refuses a later =true' {
    $threw = $false
    try {
        Assert-StoreDefinesSafe -BuildProfile store -Defines @(
            '--dart-define=ALLOW_TIER_OVERRIDE=false', '--dart-define=ALLOW_TIER_OVERRIDE=true')
    } catch { $threw = $true }
    Expect $threw 'duplicate/contradicting override define must be refused for store'
}
Check 'store guard refuses a missing define' {
    $threw = $false
    try { Assert-StoreDefinesSafe -BuildProfile store -Defines @('--dart-define=GIT_SHA=x') } catch { $threw = $true }
    Expect $threw 'a store define list without ALLOW_TIER_OVERRIDE=false must be refused'
}
Check 'store guard accepts the profile output' {
    Assert-StoreDefinesSafe -BuildProfile store -Defines (Get-ProfileDefines -BuildProfile store)
}
Check 'guard ignores non-store profiles' {
    Assert-StoreDefinesSafe -BuildProfile personal -Defines @('--dart-define=ALLOW_TIER_OVERRIDE=true')
}

if ($failures.Count -gt 0) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host 'ALL PASSED' -ForegroundColor Green
exit 0
