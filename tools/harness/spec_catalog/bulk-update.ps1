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

# TASK-FLOW 0.37: a former id of a ticket renamed by the prefix migration names that ticket.
$Id = @($Id | ForEach-Object { if (Test-SzaTicketId $_) { Resolve-CatalogId -Id $_ } else { $_ } })
$indexMap = @{}
for ($i = 0; $i -lt $allRecords.Count; $i++) {
    $indexMap[$allRecords[$i].id] = $i
}

foreach ($ticketId in $Id) {
    if (-not (Test-SzaTicketId $ticketId)) {
        $errors.Add("Invalid id '$ticketId' (must match $(Get-SzaTicketIdDisplay)).")
        continue
    }
    if (-not $indexMap.ContainsKey($ticketId)) {
        $errors.Add("Record '$ticketId' not found.")
    }
    elseif ($Status -eq 'Archived') {
        # TASK-FLOW 0.52: judged before the probe batch below touches a file.
        $problem = Test-ArchiveReason -Record $allRecords[$indexMap[$ticketId]] -Reason $(if ($noteSupplied) { $StatusNote })
        if ($null -ne $problem) { $errors.Add("Cannot archive '$ticketId': $problem.") }
    }
}

if ($errors.Count -gt 0) {
    foreach ($e in $errors) { Write-Error $e }
    exit 1
}

# Phase 2: apply changes in memory and assert
$now = Get-Now
$results = New-Object System.Collections.Generic.List[string]
$hookMoves = [System.Collections.Generic.List[hashtable]]::new()
$oldRecords = @{}

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
    # remove when explicitly blank, and auto-clear on any status change that lands on a non-Block*
    # status so a stale reason cannot outlive the state it described (S2796; it used to fire only on
    # the way out of a Block* status, which left a Partial/Broken note on a Verified ticket).
    if ($noteSupplied) {
        if ($StatusNote -ne '') {
            if ($updated.PSObject.Properties.Name -contains 'statusNote') { $updated.statusNote = $StatusNote }
            else { $updated | Add-Member -NotePropertyName 'statusNote' -NotePropertyValue $StatusNote }
        }
        elseif ($updated.PSObject.Properties.Name -contains 'statusNote') {
            $updated.PSObject.Properties.Remove('statusNote')
        }
    }
    elseif ($PSBoundParameters.ContainsKey('Status') -and $oldStatus -ne $updated.status -and $updated.status -notlike 'Block*') {
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
        # CANONR-0236: every gate is judged with the probe exit step deferred; the probes are removed
        # only after the whole batch passed, below, so a refusal leaves every probe where it was.
        try {
            Assert-ClosingGates -Id $ticketId -OldStatus $oldStatus -NewStatus $updated.status `
                -StatusNote ([string]$StatusNote) -NoteSupplied $noteSupplied -DeferProbeExit
        }
        catch { $errors.Add("$ticketId : $($_.Exception.Message)") }
    }

    $oldRecords[$ticketId] = $old
    $allRecords[$idx] = $updated
    $hookMoves.Add(@{ Id = $ticketId; Old = [string]$oldStatus; New = [string]$updated.status })
    $results.Add(("{0} {1} -> {2} (priority: {3})" -f $ticketId, $oldStatus, $updated.status, $updated.priority))
}

if ($errors.Count -gt 0) {
    foreach ($e in $errors) { Write-Error $e }
    exit 1
}

# Phase 2a - CANONR-0236: the BlockNeedUserTest exit step, after every gate of every ticket passed.
# S0056: two or more leaving tickets with probes.removeOnExit true share one batch (one scan, one lock,
# one absence check); otherwise each takes the per-ticket step. A ticket the remover refuses keeps its
# old record and is reported; the others are applied (the archive.ps1 contract), and the call exits 1.
$probeErrors = New-Object System.Collections.Generic.List[string]
if ($PSBoundParameters.ContainsKey('Status') -and $Status -ne 'BlockNeedUserTest') {
    $leavingIds = @($hookMoves | Where-Object { $_.Old -eq 'BlockNeedUserTest' } | ForEach-Object { $_.Id } | Select-Object -Unique)
    $probeVerdict = @{}
    if ($leavingIds.Count -gt 1 -and [bool](Get-SzaProfileValue 'probes.removeOnExit')) {
        try { $probeVerdict = Invoke-ProbeRemovalBatch -Id $leavingIds -NewStatus $Status }
        catch { foreach ($leavingId in $leavingIds) { $probeVerdict[$leavingId] = $_.Exception.Message } }
    }
    else {
        foreach ($leavingId in $leavingIds) {
            try { Invoke-ProbeExitStep -Id $leavingId -OldStatus 'BlockNeedUserTest' -NewStatus $Status; $probeVerdict[$leavingId] = $null }
            catch { $probeVerdict[$leavingId] = $_.Exception.Message }
        }
    }
    foreach ($leavingId in $leavingIds) {
        $refusal = $probeVerdict[$leavingId]
        if ($null -eq $refusal) { continue }
        $probeErrors.Add("$leavingId : $refusal")
        $allRecords[$indexMap[$leavingId]] = $oldRecords[$leavingId]
        foreach ($m in @($hookMoves | Where-Object { $_.Id -eq $leavingId })) { [void]$hookMoves.Remove($m) }
        foreach ($r in @($results | Where-Object { $_ -like "$leavingId *" })) { [void]$results.Remove($r) }
    }
}

# Phase 2b - TASK-FLOW rule 70 (S0076): a ticket entering Implemented, Verified or BlockNeedUserTest takes its spec
# file (and folder) into paths.specArchiveDir, one leaving them for an open status brings them back. Every gate has
# passed (they read each file where its row still names it) and the lock is held; the new `file` is written by the
# journal write below. Best effort, noted per ticket on the host stream so the result lines stay as they were.
if ($PSBoundParameters.ContainsKey('Status')) {
    foreach ($move in $hookMoves) {
        $moveRec = $allRecords[$indexMap[$move.Id]]
        $homeMove = Move-SpecToStatusHome -Record $moveRec -OldStatus $move.Old -NewStatus $move.New
        if ($homeMove.moved) { $moveRec.file = $homeMove.file }
        if ($homeMove.note) { Write-Host ("  {0}: spec file {1}" -f $move.Id, $homeMove.note) -ForegroundColor DarkGray }
    }
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
    $quizEntries = @{}
    foreach ($move in $hookMoves) {
        if ($move.Old -ne 'BlockQuestions' -and $move.New -eq 'BlockQuestions') {
            $quizEntries[$move.Id] = Get-QuizEntryDay $now
        }
    }
    foreach ($ticketId in @($hookMoves | ForEach-Object { $_.Id })) {
        $rec = $allRecords[$indexMap[$ticketId]]
        # S2581: the note reaches the header too, so `**Status note:**` cannot say one thing in
        # the spec while the journal says another. $null when omitted, which the helper reads as
        # "leave the header's note alone".
        $headerNote = if ($noteSupplied) { $StatusNote } else { $null }
        [void](Sync-SpecHeaderStatus -PathRef $rec.file -Status $rec.status -StatusNote $headerNote -QuizEntryDay $quizEntries[$ticketId])
    }
}

Exit-CatalogLock

foreach ($line in $results) { Write-Output $line }

# TASK-FLOW rule 69, per ticket, after the lock: back-links on entry into BlockByOtherTask, releases after a move.
if ($PSBoundParameters.ContainsKey('Status')) {
    . (Join-Path $PSScriptRoot '_block-links-hook.ps1')
    foreach ($move in $hookMoves) {
        Invoke-BlockLinksHook -Id $move.Id -OldStatus $move.Old -NewStatus $move.New -NoteChanged:$noteSupplied
    }
}
if ($probeErrors.Count -gt 0) {
    foreach ($e in $probeErrors) { Write-Error $e -ErrorAction Continue }
    exit 1
}
exit 0
