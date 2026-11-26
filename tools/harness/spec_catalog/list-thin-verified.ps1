<#
.SYNOPSIS
    Report: the Verified tickets of one repository that the Verified gate of TASK-FLOW 0.48 would refuse today.

.DESCRIPTION
    Reads the ledger and the spec files and writes nothing: no status, no file. A ticket already Verified keeps its
    status - the gate judges new entries only - and what to do with a listed ticket is the owner's call. The judgement
    is the one of check-audit-recorded.ps1 (_audit-evidence.ps1).

.PARAMETER Root
    The repository to read. Default: the project of the current folder.

.PARAMETER Json
    One JSON object instead of the lines: root, verified, thin, tickets[{id, executed, unrun, missing[]}].

.NOTES
    Exit codes: 0 = the report was written, whatever it found. 2 = -Root is not a folder, or the ledger is unreadable.
#>
[CmdletBinding()]
param(
    [string] $Root,
    [switch] $Json
)

if ($Root) {
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        Write-Error "-Root is not a folder: $Root" -ErrorAction Continue
        exit 2
    }
    $savedRoot = $env:SZA_PROJECT_ROOT
    $env:SZA_PROJECT_ROOT = (Resolve-Path -LiteralPath $Root).Path
}

try {
    . (Join-Path $PSScriptRoot '..\_profile.ps1')
    . (Join-Path $PSScriptRoot '_lib.ps1')
    . (Join-Path $PSScriptRoot '_audit-evidence.ps1')

    # Read-Catalog hands its array over as one object, so it is assigned before it is filtered.
    try { $all = Read-Catalog; $rows = @($all | Where-Object { [string]$_.status -eq 'Verified' }) }
    catch {
        Write-Error "The ledger could not be read: $($_.Exception.Message)" -ErrorAction Continue
        exit 2
    }

    $thin = @(foreach ($row in $rows) {
        $section = @(Get-SpecSectionLines -Path $row.file -HeadingPattern (Get-AuditSectionHeadingPattern))
        $evidence = Get-AuditEvidence -Lines @($section | ForEach-Object { $_.Text })
        if ($evidence.Missing.Count -gt 0) {
            [pscustomobject]@{
                id = [string]$row.id; executed = $evidence.Executed; unrun = $evidence.Unrun; missing = $evidence.Missing
            }
        }
    })

    $shownRoot = if ($Root) { $env:SZA_PROJECT_ROOT } else { (Get-Location).Path }
    if ($Json) {
        [pscustomobject]@{ root = $shownRoot; verified = $rows.Count; thin = $thin.Count; tickets = $thin } |
            ConvertTo-Json -Depth 4 -Compress
    } else {
        foreach ($t in $thin) { Write-Output ('{0}  {1}' -f $t.id, ($t.missing -join '; ')) }
        Write-Output ('list-thin-verified: {0} of {1} Verified ticket(s) lack the evidence ({2})' -f $thin.Count, $rows.Count, $shownRoot)
    }
}
finally {
    if ($Root) { $env:SZA_PROJECT_ROOT = $savedRoot }
}
exit 0
