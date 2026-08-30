# The one piece of build_release.ps1's git-dirty-stamp decision that is worth
# testing in isolation, split into its own file so a test harness can
# dot-source *only* this -- no git process, no repo, no Flutter or Firebase
# side effects -- and build_release.ps1 dot-sources the same file so the two
# can never drift apart.
#
# `--quiet`'s contract is its exit code: 0 = clean, 1 = dirty (normal control
# flow, not a failure). Anything else (e.g. 128, a repository-level git
# error) means the comparison itself did not run, and treating that the same
# as "dirty" would stamp and ship a build whose source state was never
# actually verified -- exactly the failure this stamp exists to prevent.
function Get-GitDirtyStamp {
    param(
        [Parameter(Mandatory)][int]$DiffExitCode,
        [Parameter(Mandatory)][string]$BaseSha
    )
    if ($DiffExitCode -eq 1) {
        return "$BaseSha-dirty"
    } elseif ($DiffExitCode -ne 0) {
        throw "git diff --quiet HEAD failed with exit code $DiffExitCode -- working tree state could not be verified."
    }
    return $BaseSha
}
