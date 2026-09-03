#requires -Version 7.0
<#
.SYNOPSIS
    Read-only snapshot of the BlockNeedUserTest backlog.

.DESCRIPTION
    Lists every ticket currently in status BlockNeedUserTest from the spec catalog
    journal, sorted by priority (desc) then id, with file path and last-updated
    timestamp. Prints an `expected: 0 | actual: N` count so the backlog size is
    visible before and after a /spec-sweep pass. Never mutates the journal.

    The journal path comes from Get-CatalogPath in _lib.ps1, so a harness pointing
    the catalog at a fixture through FMS_SPEC_CATALOG_DIR gets a report about that
    fixture (S2414). A hand-built path made this the one catalog reader that read
    production regardless - silently, since the output format is identical.

    Exit codes (S1070):
      0 - listed successfully (an empty backlog is still 0 - this is a report, not
          a gate, so "no tickets" is not a failure).
      1 - cannot run: _lib.ps1 refuses to resolve a catalog path because
          FMS_SPEC_CATALOG_DIR names a directory that does not exist.
      2 - cannot run: the resolved journal file is not there.

.PARAMETER MinPriority
    Optional: only list tickets with priority >= this value.

.EXAMPLE
    pwsh -NoProfile -File scripts/spec_catalog/list-blockneedusertest.ps1
    pwsh -NoProfile -File scripts/spec_catalog/list-blockneedusertest.ps1 -MinPriority 90
#>
[CmdletBinding()]
param(
    [int]$MinPriority = 0
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_lib.ps1')

$catalog = Get-CatalogPath
if (-not (Test-Path $catalog)) { Write-Error "Not found: $catalog" -ErrorAction Continue; exit 2 }

$rows = [System.Collections.Generic.List[object]]::new()
foreach ($line in Get-Content -LiteralPath $catalog) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try { $rec = $line | ConvertFrom-Json } catch { continue }
    if ($rec.status -ne 'BlockNeedUserTest') { continue }
    if ([int]$rec.priority -lt $MinPriority) { continue }
    $rows.Add([pscustomobject]@{
        Priority = [int]$rec.priority
        Id       = $rec.id
        Updated  = $rec.updated
        File     = $rec.file
    })
}

$sorted = $rows | Sort-Object -Property @{Expression = 'Priority'; Descending = $true }, @{Expression = 'Id'; Descending = $false }
Write-Host ("{0,-4}  {1,-6}  {2,-16}  {3}" -f 'PRI', 'ID', 'UPDATED', 'FILE')
foreach ($r in $sorted) {
    Write-Host ("{0,-4}  {1,-6}  {2,-16}  {3}" -f $r.Priority, $r.Id, $r.Updated, $r.File)
}
Write-Host ("list-blockneedusertest: expected: 0 | actual: {0} (MinPriority {1})" -f $rows.Count, $MinPriority)
