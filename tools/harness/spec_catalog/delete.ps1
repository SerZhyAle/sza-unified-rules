[CmdletBinding()]
param(
    [string] $Id,
    # TASK-FLOW 0.52: the one-line archive reason kept in statusNote - duplicate of <id>, not needed: <why>, done in <id>.
    [Alias('StatusNote')]
    [string] $Reason,
    [switch] $Confirm,
    [switch] $Help
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')

if ($Help) {
    Show-SzaHelp $PSCommandPath
    exit $LASTEXITCODE
}
if (-not $Id) {
    Write-Error 'delete.ps1 requires -Id <Sxxxx>. Run with -Help for the parameter list.' -ErrorAction Continue
    exit 1
}

# Convert terminating errors (Write-Error, throw, provider errors) into
# the documented `exit 1` so callers can rely on $LASTEXITCODE.
trap {
    Write-Host $_ -ForegroundColor Red
    exit 1
}

. (Join-Path $PSScriptRoot '_lib.ps1')

if (-not (Test-SzaTicketId $Id)) { throw "Invalid -Id '$Id' (must match $(Get-SzaTicketIdDisplay))." }

$records = [System.Collections.Generic.List[object]]::new()
# S1437: read -> mutate -> write is one critical section. The early-exit paths below leave the
# lock held until the process ends, which releases it - these scripts exit immediately after.
$Id = Resolve-CatalogId -Id $Id  # TASK-FLOW 0.37 former id (CANONR-0195 G5)
Enter-CatalogLock
foreach ($r in (Read-Catalog)) { $records.Add($r) }

$idx = -1
for ($i = 0; $i -lt $records.Count; $i++) {
    if ($records[$i].id -eq $Id) { $idx = $i; break }
}
if ($idx -lt 0) { throw "Record '$Id' not found." }

if (-not $Confirm) {
    Write-Output "Would soft-delete $Id ($($records[$idx].name) - current status: $($records[$idx].status)). Re-run with -Confirm and -Reason '<one line>' to apply."
    exit 1
}

$old = $records[$idx]
if ($old.status -eq 'Archived') {
    Write-Output "$Id already Archived (no-op)."
    exit 0
}

Assert-ArchiveReason -Id $Id -OldStatus ([string]$old.status) -Reason $Reason -Supplied ($PSBoundParameters.ContainsKey('Reason'))

$archived = [pscustomobject]@{
    id       = [string]$old.id
    name     = [string]$old.name
    status   = 'Archived'
    priority = [int]$old.priority
    file     = [string]$old.file
    created  = [string]$old.created
    updated  = (Get-Now)
}
if ($old.PSObject.Properties.Name -contains 'tier' -and $null -ne $old.tier -and "$($old.tier)" -ne '') {
    $archived | Add-Member -NotePropertyName 'tier' -NotePropertyValue ([int]$old.tier)
}

# Every other field of the row travels: the shipment history and the former ids stay readable.
foreach ($prop in $old.PSObject.Properties) {
    if (-not ($archived.PSObject.Properties.Name -contains $prop.Name)) {
        $archived | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
    }
}
Set-PlanProp -Record $archived -Name 'statusNote' -Value $Reason
Assert-Record -Record $archived
# Relocate into the archive journal (append) and drop from the active one, so
# the split invariant holds (no Archived row in the active journal).
Add-ArchiveRecord -Record $archived
$remaining = @($records | Where-Object { $_.id -ne $Id })
Write-Catalog -Records ([object[]]$remaining)
[void](Sync-SpecHeaderStatus -PathRef $archived.file -Status 'Archived' -StatusNote $Reason)
Exit-CatalogLock
Write-Output "$Id Archived."
exit 0
