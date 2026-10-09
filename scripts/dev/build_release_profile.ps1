# Build-profile decision for build_release.ps1 (CR-04).
#
# Three profiles, each an EXPLICIT dart-define set -- the old wrapper passed no
# ALLOW_TIER_OVERRIDE at all, so every "release" build inherited the Dart
# default (true) and a store artifact could ship the paid-tier override.
#
#   personal : the operator's own phones. Tier override ALLOWED (the switch
#              exists so paid screens can be exercised without Stripe test
#              cards). This is what a bare `build_release.ps1` produces, and it
#              says so out loud; it is NOT a store build.
#   test     : same override policy as personal, labelled separately so a
#              tester build is distinguishable in logs.
#   store    : tier override FORBIDDEN (ALLOW_TIER_OVERRIDE=false). Anything that
#              leaves the operator's hands for a store or external testers.
#
# Kept in its own file, like build_release_gitcheck.ps1, so a test can dot-source
# just the decision logic without Flutter, git or Firebase side effects. See
# build_release_profile.tests.ps1.

function Get-ProfileDefines {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$BuildProfile)

    switch ($BuildProfile) {
        'personal' { $allow = 'true' }
        'test'     { $allow = 'true' }
        'store'    { $allow = 'false' }
        default {
            throw "Unknown build profile '$BuildProfile'. Use personal, test or store."
        }
    }
    return @(
        "--dart-define=ALLOW_TIER_OVERRIDE=$allow",
        "--dart-define=BUILD_PROFILE=$BuildProfile"
    )
}

# Last line of defence before flutter runs: a store profile whose final define
# list does not carry ALLOW_TIER_OVERRIDE=false (or carries a later =true that
# would win) must not build.
function Assert-StoreDefinesSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BuildProfile,
        [Parameter(Mandatory)][string[]]$Defines
    )
    if ($BuildProfile -ne 'store') { return }
    $tier = @($Defines | Where-Object { $_ -like '--dart-define=ALLOW_TIER_OVERRIDE=*' })
    if ($tier.Count -ne 1 -or $tier[0] -ne '--dart-define=ALLOW_TIER_OVERRIDE=false') {
        throw ("Refusing store build: the define list must contain exactly one " +
               "--dart-define=ALLOW_TIER_OVERRIDE=false, found: " + ($tier -join ', '))
    }
}
