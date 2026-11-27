#requires -Version 7.0
<#
.SYNOPSIS
    Check the public-vs-local repository contents boundary (REPO-LAYOUT 0.12 rule 8, SZA-LAY07).

.DESCRIPTION
    Runs tools/check-compliance.ps1 -Only SZA-LAY07 against the target repository root (defaults to
    SZA_PROJECT_ROOT or the current working directory). Designed for direct runs and portfolio
    tracking-campaign checks (`spec-draft.ps1 -Tracking -Check tools/check-public-repo-contents.ps1`).

    Exit codes: 0 = clean (or exempt role canon-home/internal); 1 = tracked local-only files found;
    2 = could not verify.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = ''
)

$ErrorActionPreference = 'Continue'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = if ($env:SZA_PROJECT_ROOT) { $env:SZA_PROJECT_ROOT } else { (Get-Location).Path }
}
& (Join-Path $PSScriptRoot 'check-compliance.ps1') -RepoRoot $RepoRoot -Only SZA-LAY07
exit $LASTEXITCODE
