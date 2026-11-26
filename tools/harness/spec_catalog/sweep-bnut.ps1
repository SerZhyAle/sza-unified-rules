#requires -Version 7.0
<#
.SYNOPSIS
    Preview owner-test tickets whose specs lack a Device check.
.PARAMETER Root
    Repository whose catalog to inspect.
.PARAMETER Apply
    Move a candidate to Implemented through update.ps1 once its spec names a Release gate.
    Review the preview first and add the Release gate only for a deferred project command.
.NOTES
    Exit 0 on success, 1 when a spec or transition needs attention, 2 for a missing catalog.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Root,
    [switch] $Apply
)

$previousRoot = $env:SZA_PROJECT_ROOT
try {
    $env:SZA_PROJECT_ROOT = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).ProviderPath
    . (Join-Path $PSScriptRoot '_lib.ps1')
    . (Join-Path $PSScriptRoot 'lib/device-check.ps1')
    if (-not (Test-Path -LiteralPath (Get-CatalogPath) -PathType Leaf)) {
        Write-Error "Catalog not found: $(Get-CatalogPath)" -ErrorAction Continue
        exit 2
    }

    $candidates = 0
    $moved = 0
    $failed = 0
    $rows = (Read-Catalog) | Where-Object status -eq 'BlockNeedUserTest' | Sort-Object id
    foreach ($row in $rows) {
        try {
            $specPath = Resolve-SpecPath -PathRef $row.file
            $deviceChecks = @(Get-SpecDeviceCheck -Path $specPath)
        } catch {
            Write-Warning ("Cannot read the spec for {0}: {1}" -f $row.id, $_.Exception.Message)
            $failed++
            continue
        }
        if ($deviceChecks.Count -gt 0) { continue }

        Write-Output ("{0}: {1}" -f $row.id, $row.file)
        $candidates++
        if (-not $Apply) { continue }

        if (-not (Select-String -LiteralPath $specPath -Pattern '^\*\*Release gate:\*\*\s*\S' -CaseSensitive -Quiet)) {
            Write-Warning "$($row.id) needs a '**Release gate:** <suite or command>' line before reclassification."
            $failed++
            continue
        }
        $updateArgs = @(
            '-Id', $row.id, '-Status', 'Implemented', '-ExpectedStatus', 'BlockNeedUserTest',
            '-StatusNote', 'release gate: owner test was not a device check (audit 2026-11-26)'
        )
        & (Join-Path $PSHOME 'pwsh') -NoProfile -File (Join-Path $PSScriptRoot 'update.ps1') @updateArgs
        if ($LASTEXITCODE -eq 0) { $moved++ } else { $failed++ }
    }

    $mode = if ($Apply) { 'apply' } else { 'dry run' }
    Write-Output "sweep-bnut ($mode): $candidates candidate(s), $moved moved, $failed needing attention"
    exit $(if ($failed) { 1 } else { 0 })
} finally {
    $env:SZA_PROJECT_ROOT = $previousRoot
}
