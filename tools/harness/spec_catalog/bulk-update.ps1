[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]] $Id,
    [ValidateSet('Draft','Approved','Tactical','In Progress',
        'Implemented','Verified','Partial','Broken',
        'BlockByOtherTask','BlockNeedUserTest','BlockQuestions','BlockExternal',
        'Archived')]
    [string] $Status,
    [ValidateRange(0,100)]
    [int]    $Priority = -1,
    # S2581: one reason for the whole batch, which is the semantics a bulk block already has -
    # a batch entering Block* is entering it for one shared cause. Added with the gate rather
    # than after it: without a note channel here the gate would not refuse a bad write, it
    # would silently remove this script's ability to set any Block* status at all.
    [string] $StatusNote = $null
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')

# Convert terminating errors (Write-Error, throw, provider errors) into
# the documented `exit 1` so callers can rely on $LASTEXITCODE.
trap {
    Write-Host $_ -ForegroundColor Red
    exit 1
}

. (Join-Path $PSScriptRoot '_lib.ps1')

if (-not $PSBoundParameters.ContainsKey('Status') -and $Priority -lt 0) {
    Write-Error "At least one of -Status or -Priority must be provided."
    exit 1
}

# Read once, outside the loop: '' (clear the note) and omitted (leave it alone) are different
# intents, and only the binder can tell them apart (S2581).
$noteSupplied = $PSBoundParameters.ContainsKey('StatusNote')

# Phase 1: validate all ids before touching the journal
$errors = New-Object System.Collections.Generic.List[string]
$allRecords = [System.Collections.Generic.List[object]]::new()
# S1437: read -> mutate -> write is one critical section. Two processes holding the same
# snapshot lose one change entirely - the later write replaces the whole journal.
Enter-CatalogLock
foreach ($r in (Read-Catalog)) { $allRecords.Add($r) }

$indexMap = @{}
for ($i = 0; $i -lt $allRecords.Count; $i++) {
    $indexMap[$allRecords[$i].id] = $i
}

foreach ($ticketId in $Id) {
    if ($ticketId -notmatch '^S\d{4}$') {
        $errors.Add("Invalid id '$ticketId' (must match S####).")
        continue
    }
    if (-not $indexMap.ContainsKey($ticketId)) {
        $errors.Add("Record '$ticketId' not found.")
    }
}

if ($errors.Count -gt 0) {
    foreach ($e in $errors) { Write-Error $e }
    exit 1
}

# Phase 2: apply changes in memory and assert
$now = Get-Now
$results = New-Object System.Collections.Generic.List[string]

foreach ($ticketId in $Id) {
    $idx = $indexMap[$ticketId]
    $old = $allRecords[$idx]
    $oldStatus = $old.status

    $updated = [pscustomobject]@{
        id       = [string]$old.id
        name     = [string]$old.name
        status   = if ($PSBoundParameters.ContainsKey('Status')) { $Status } else { [string]$old.status }
        priority = if ($Priority -ge 0) { $Priority } else { [int]$old.priority }
        file     = [string]$old.file
        created  = [string]$old.created
        updated  = $now
    }
    if ($old.PSObject.Properties.Name -contains 'tier' -and $null -ne $old.tier -and "$($old.tier)" -ne '') {
        $updated | Add-Member -NotePropertyName 'tier' -NotePropertyValue ([int]$old.tier)
    }
    $fixedKeys = @('id','name','status','priority','tier','file','created','updated')
    foreach ($prop in $old.PSObject.Properties) {
        if ($fixedKeys -notcontains $prop.Name -and -not ($updated.PSObject.Properties.Name -contains $prop.Name)) {
            $updated | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
        }
    }

    # S2581: apply the batch note the way update.ps1 applies its own - set when non-empty,
    # remove when explicitly blank, and auto-clear on the way OUT of a Block* status so a
    # stale reason cannot outlive the block it described.
    if ($noteSupplied) {
        if ($StatusNote -ne '') {
            if ($updated.PSObject.Properties.Name -contains 'statusNote') { $updated.statusNote = $StatusNote }
            else { $updated | Add-Member -NotePropertyName 'statusNote' -NotePropertyValue $StatusNote }
        }
        elseif ($updated.PSObject.Properties.Name -contains 'statusNote') {
            $updated.PSObject.Properties.Remove('statusNote')
        }
    }
    elseif ($PSBoundParameters.ContainsKey('Status') -and $oldStatus -like 'Block*' -and $updated.status -notlike 'Block*') {
        if ($updated.PSObject.Properties.Name -contains 'statusNote') {
            $updated.PSObject.Properties.Remove('statusNote')
        }
    }

    try { Assert-Record -Record $updated }
    catch { $errors.Add("$ticketId : $($_.Exception.Message)") }

    # This script writes the journal itself rather than delegating to update.ps1, so the
    # closing gates have to be invoked here too - otherwise a batch is a way to close a
    # ticket around them. Collected as an error rather than thrown, matching the batch
    # contract: every ticket is judged, then the whole batch aborts if any failed.
    if ($PSBoundParameters.ContainsKey('Status')) {
        try {
            Assert-ClosingGates -Id $ticketId -OldStatus $oldStatus -NewStatus $updated.status `
                -StatusNote ([string]$StatusNote) -NoteSupplied $noteSupplied
        }
        catch { $errors.Add("$ticketId : $($_.Exception.Message)") }
    }

    $allRecords[$idx] = $updated
    $results.Add(("{0} {1} -> {2} (priority: {3})" -f $ticketId, $oldStatus, $updated.status, $updated.priority))
}

if ($errors.Count -gt 0) {
    foreach ($e in $errors) { Write-Error $e }
    exit 1
}

# Phase 3: atomic writes, routing newly-Archived records into the archive journal.
# (Reviving an archived id is out of scope for bulk - use update.ps1 for that.)
$archivedNow = @($allRecords | Where-Object { $_.status -eq 'Archived' })
$activeNow   = @($allRecords | Where-Object { $_.status -ne 'Archived' })
if ($archivedNow.Count -gt 0) {
    $movingIds = @($archivedNow | ForEach-Object { $_.id })
    $existingArchive = Read-JsonlFile -Path (Get-ArchivePath)
    $mergedArchive = @($existingArchive | Where-Object { $movingIds -notcontains $_.id }) + $archivedNow
    Write-ArchiveCatalog -Records ([object[]]$mergedArchive)
}
Write-Catalog -Records ([object[]]$activeNow)

# Phase 4: mirror each new status into its spec file's **Status:** header so the
# in-file header never drifts from the journal (shared fail-soft helper; only on
# status changes - a priority-only batch leaves headers untouched).
if ($PSBoundParameters.ContainsKey('Status')) {
    foreach ($ticketId in $Id) {
        $rec = $allRecords[$indexMap[$ticketId]]
        # S2581: the note reaches the header too, so `**Status note:**` cannot say one thing in
        # the spec while the journal says another. $null when omitted, which the helper reads as
        # "leave the header's note alone".
        $headerNote = if ($noteSupplied) { $StatusNote } else { $null }
        [void](Sync-SpecHeaderStatus -PathRef $rec.file -Status $rec.status -StatusNote $headerNote)
    }
}

Exit-CatalogLock

foreach ($line in $results) { Write-Output $line }
exit 0
