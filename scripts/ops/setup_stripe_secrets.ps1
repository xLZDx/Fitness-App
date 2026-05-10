# Wire 5 Stripe price IDs into Firebase Functions secrets.
#
# Pre-requisites in your Stripe dashboard:
#   1. Standard product (already exists). Add 4 prices to it:
#      - $59.99/yr (recurring)
#      - $14.99/mo (recurring)  -> Family · 2 seats
#      - $19.99/mo (recurring)  -> Family · 4 seats
#      (the existing $9.99/mo monthly price stays)
#   2. Celebrity product (already exists). Add 2 prices to it:
#      - $119.99/yr (recurring)
#      - $499 (one-time)        -> Lifetime
#      (the existing $19.99/mo monthly price stays)
#
# Then run this with the 5 new price IDs as parameters. The script
# pipes each value into a tempfile (avoids the CRLF gotcha that
# poisoned the Stripe Authorization header in Phase 4B) and calls
# `firebase functions:secrets:set` for each.
#
# Usage:
#   pwsh ./scripts/ops/setup_stripe_secrets.ps1 `
#     -StandardAnnual price_1Ab... `
#     -CelebrityAnnual price_1Cd... `
#     -StandardFamily2 price_1Ef... `
#     -StandardFamily4 price_1Gh... `
#     -CelebrityLifetime price_1Ij...

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$StandardAnnual,
    [Parameter(Mandatory)] [string]$CelebrityAnnual,
    [Parameter(Mandatory)] [string]$StandardFamily2,
    [Parameter(Mandatory)] [string]$StandardFamily4,
    [Parameter(Mandatory)] [string]$CelebrityLifetime,
    [string]$Project = 'fitnessapp-1d3b3'
)

$ErrorActionPreference = 'Stop'

function Set-Secret {
    param([string]$Name, [string]$Value)
    if (-not $Value.StartsWith('price_')) {
        throw "$Name does not look like a Stripe price id (got: $Value)"
    }
    $tmp = New-TemporaryFile
    try {
        # Write without BOM/CRLF — Stripe SDK rejects the secret if
        # the request header has a stray CR. UTF8 (no BOM) is safe.
        [System.IO.File]::WriteAllText(
            $tmp.FullName,
            $Value,
            [System.Text.UTF8Encoding]::new($false)
        )
        Write-Host "→ Setting $Name..." -ForegroundColor Cyan
        firebase --project $Project functions:secrets:set $Name --data-file $tmp.FullName
    } finally {
        Remove-Item $tmp.FullName -ErrorAction SilentlyContinue
    }
}

Set-Secret 'STRIPE_PRICE_STANDARD_ANNUAL'    $StandardAnnual
Set-Secret 'STRIPE_PRICE_CELEBRITY_ANNUAL'   $CelebrityAnnual
Set-Secret 'STRIPE_PRICE_STANDARD_FAMILY2'   $StandardFamily2
Set-Secret 'STRIPE_PRICE_STANDARD_FAMILY4'   $StandardFamily4
Set-Secret 'STRIPE_PRICE_CELEBRITY_LIFETIME' $CelebrityLifetime

Write-Host ''
Write-Host 'All five secrets written. Redeploy the function:' -ForegroundColor Green
Write-Host '  firebase --project ' -NoNewline; Write-Host $Project -NoNewline -ForegroundColor Yellow
Write-Host ' deploy --only functions:createCheckoutSession,functions:stripeWebhook'
