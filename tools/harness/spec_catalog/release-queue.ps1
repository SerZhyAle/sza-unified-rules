# release-queue.ps1 - operator CLI for PLAN/RELEASE_QUEUE.md, the owner's release plan.
#
# The queue answers "what ships in which release package, in what order" - a question the
# catalog cannot answer, because the catalog knows status but not intent. Division of labour:
#
#   catalog (PLAN/spec-catalog.jsonl)  owns  status, priority, dates - written by the skills
#   queue   (PLAN/RELEASE_QUEUE.md)    owns  release assignment + order - written by the OWNER
#
# Every catalog mutation reconciles the queue automatically (Sync-ReleaseQueue, called from
# Write-Catalog in _lib.ps1), so no skill needs to know this file exists. That sync never
# reorders lines: a script may add, update a status/date, or drop an archived ticket, but the
# sequence itself is the owner's plan and stays untouched.
#
# Actions:
#   -Reconcile            Force a sync against the catalog now (the automatic path, on demand). It holds the
#                         catalog lock for the read and the rewrite of both plan files, like every mutator;
#                         the portfolio projection is refreshed after the lock is released.
#   -Validate             Report drift: unknown tickets, duplicates, status mismatches. It compares
#                         the file with the catalog, and the catalog does not know packages, so a
#                         clean -Validate says nothing about package membership: a row moved to the
#                         wrong package validates clean. Before a queue mutator, copy the file; after
#                         it, diff membership against the copy (PLAN/ is often outside git).
#                         It ends with a `note` line when ready ledger rows are listed in neither file - not
#                         drift, and no exit code: they shipped earlier, or the ledger was never seeded (-Seed).
#   -Seed -Release N [-Since "<yyyy-MM-dd HH:mm>"] [-Apply]
#                         The one-off that moves an existing ledger onto the plan files (S0151). The sync never
#                         adds a READY ticket that stands in neither file (it shipped in an earlier package, is the
#                         premise); for a project that adopts the plan files with built, unshipped work already in its
#                         ledger that is false. The seed, over the active ledger:
#                           - adds every ready ticket in neither file whose ledger `updated` is at or after -Since
#                             (every one of them when -Since is absent) to package N of the ready file, in id order;
#                           - splits a hand-kept queue file by status the way the sync does, and brings the owner's
#                             `#` group comment lines along: a ready row goes to the ready file, in its own package,
#                             under the same comment (the queue file keeps its comments);
#                           - adds the unfinished tickets that are listed nowhere to the queue at the open package;
#                           - creates the ready and the shipped file when they are absent (with -Apply);
#                           - prints what it added, moved and left out, and why.
#                         A dry run unless -Apply is given: without it nothing is written, and the output is exactly
#                         what -Apply would do. With -Apply it holds the catalog lock for the read and the rewrite
#                         of the plan files, like -Reconcile. Nothing existing is reordered and no row changes its
#                         package. -Since reads the same stamp the ledger keeps (`yyyy-MM-dd HH:mm`, or a bare
#                         `yyyy-MM-dd` for midnight); name the time of the last release.
#   -List [-Release N] [-WithLeases]
#                         Print the queue, optionally one release block. -WithLeases marks each
#                         taken row inline and appends the holder detail block.
#   -SetCurrent N         Point the "current-release:" marker at package N. A label only: the queue
#                         ranking reads package headings and line order, never this marker. Holds the
#                         catalog lock for the read and the rewrite, like -Reconcile (S0144).
#   -Ship -Release N      Move block N into PLAN/RELEASE_QUEUE_DONE.md and advance the marker. Holds the
#                         catalog lock from the first read to the last write (S0144).
#         [-Version X]    Stamp the shipped block with the released version name.
#         [-DryRun]       Show what -Ship would move, change nothing.
#
# Usage:
#   pwsh -NoProfile -File scripts/spec_catalog/release-queue.ps1 -Reconcile
#   pwsh -NoProfile -File scripts/spec_catalog/release-queue.ps1 -Seed -Release 14 -Since "2026-11-13 01:30"
#   pwsh -NoProfile -File scripts/spec_catalog/release-queue.ps1 -Seed -Release 14 -Since "2026-11-13 01:30" -Apply
#   pwsh -NoProfile -File scripts/spec_catalog/release-queue.ps1 -List -Release 30
#   pwsh -NoProfile -File scripts/spec_catalog/release-queue.ps1 -List -Release 30 -WithLeases
#   pwsh -NoProfile -File scripts/spec_catalog/release-queue.ps1 -Ship -Release 30 -Version 2.60.7300.900
#
# Exit codes:
#   0  success (for -Validate: no drift).
#   1  error, or -Validate found drift.
#   2  cannot verify - PLAN/RELEASE_QUEUE.md is missing (seed it before using the queue). -List is
#      the exception: a missing plan file lists as empty and exits 0.
[CmdletBinding(DefaultParameterSetName = 'List')]
param(
    [Parameter(ParameterSetName = 'Reconcile')][switch] $Reconcile,
    [Parameter(ParameterSetName = 'Validate')][switch] $Validate,
    [Parameter(ParameterSetName = 'List')][switch] $List,
    # List the finished side (PLAN/RELEASE_READY.md) instead of the work-remaining queue.
    [Parameter(ParameterSetName = 'List')][switch] $Ready,
    # Mark each taken row inline, and append a read-only projection of active ticket leases.
    [Parameter(ParameterSetName = 'List')][switch] $WithLeases,
    [Parameter(ParameterSetName = 'SetCurrent', Mandatory = $true)][int] $SetCurrent,
    [Parameter(ParameterSetName = 'Ship', Mandatory = $true)][switch] $Ship,
    [Parameter(ParameterSetName = 'Ship', Mandatory = $true)]
    [Parameter(ParameterSetName = 'Seed', Mandatory = $true)]
    [Parameter(ParameterSetName = 'List')][string] $Release = '',
    [Parameter(ParameterSetName = 'Ship')][string] $Version = '',
    [Parameter(ParameterSetName = 'Ship')][switch] $DryRun,
    [Parameter(ParameterSetName = 'Seed', Mandatory = $true)][switch] $Seed,
    # The time of the last release, in the ledger's own stamp shape; ready tickets last updated before it are left out.
    [Parameter(ParameterSetName = 'Seed')][string] $Since = '',
    # Write the seed. Without it the action is a dry run.
    [Parameter(ParameterSetName = 'Seed')][switch] $Apply
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_lib.ps1')

trap {
    Write-Error $_ -ErrorAction Continue
    exit 1
}

$queuePath = Get-ReleaseQueuePath
# A listing of a plan file that does not exist yet is an empty listing (TASK-FLOW rules 15 and 35), the
# way every write path already treats it. The other actions need the file to act on or to compare with,
# so they keep saying "cannot verify".
if (-not (Test-Path $queuePath) -and $PSCmdlet.ParameterSetName -ne 'List') {
    Write-Error "Release queue not found: $queuePath" -ErrorAction Continue
    exit 2
}

function Get-QueueTickets {
    param([Parameter(Mandatory)][AllowEmptyCollection()] $Lines)
    return @($Lines | Where-Object { $_.Kind -eq 'ticket' })
}

function Get-ActiveTicketLeases {
    $leaseScript = (Get-SzaHarnessScript 'locks/ticket-lease.ps1')
    $fixturePath = (Get-SzaEnv 'TICKET_LEASE_STATUS_FIXTURE')
    if (-not [string]::IsNullOrWhiteSpace($fixturePath)) {
        if (-not (Test-Path -LiteralPath $fixturePath)) {
            throw "Ticket lease fixture not found: $fixturePath"
        }
        $raw = Get-Content -LiteralPath $fixturePath -Raw -Encoding utf8
        if (-not $raw) { return @() }
        return @($raw | ConvertFrom-Json)
    }
    $pwsh = if (Test-Path "$env:ProgramFiles\PowerShell\7\pwsh.exe") {
        "$env:ProgramFiles\PowerShell\7\pwsh.exe"
    } else {
        'pwsh'
    }
    $raw = & $pwsh -NoProfile -File $leaseScript -Verb Status -Json
    if ($LASTEXITCODE -ne 0) {
        throw "ticket-lease Status failed with exit code $LASTEXITCODE"
    }
    if (-not $raw) { return @() }
    return @($raw | ConvertFrom-Json)
}

switch ($PSCmdlet.ParameterSetName) {

    'Reconcile' {
        # Under the catalog lock every mutator holds (S1437): the catalog read and the read-modify-write of both
        # plan files are one critical section. Without it, a mutator that wrote the catalog and re-rendered the
        # plan files between this read and this write would be overwritten by this older snapshot - the lost
        # update the lock exists to stop. run-spec-queue.ps1 calls this branch after a forced lease release,
        # while sibling instances keep writing the same catalog, so the race is real there.
        #
        # The portfolio projection is not part of the critical section: it is a `pq sync` child that may start
        # insert.ps1 or update.ps1 (rules 65 and 68), and both take this mutex, which a child cannot win while
        # its parent holds it. So the sync below is told to skip it, and it runs after Exit-CatalogLock - the
        # order _block-links-hook.ps1 keeps for the same reason.
        $before = 0
        $after = 0
        $dropped = 0
        Enter-CatalogLock
        try {
            $records = Read-Catalog
            $before = @(Get-QueueTickets -Lines (Read-ReleaseQueue)).Count
            Sync-ReleaseQueue -Records $records -SkipProjection
            $after = @(Get-QueueTickets -Lines (Read-ReleaseQueue)).Count
            $dropped = Get-ReleaseQueueDuplicatesDropped
        }
        finally { Exit-CatalogLock }
        Sync-PortfolioProjection
        Write-Output ("release-queue: reconciled - {0} ticket(s) before, {1} after" -f $before, $after)
        # The counts above cover the QUEUE file only, so a duplicate collapsed in the READY file
        # moves neither number - reporting it separately is the only proof the repair happened.
        if ($dropped -gt 0) {
            Write-Output ("release-queue: removed {0} duplicate line(s)" -f $dropped)
        }
        exit 0
    }

    'Validate' {
        $records = Read-Catalog
        $byId = @{}
        foreach ($r in $records) { $byId[$r.id] = $r }

        $tickets = @()
        $tickets += Get-QueueTickets -Lines (Read-ReleaseQueue)
        $tickets += Get-QueueTickets -Lines (Read-ReleaseReady)
        $problems = New-Object System.Collections.Generic.List[string]
        $seen = @{}

        foreach ($t in $tickets) {
            if ($seen.ContainsKey($t.Id)) {
                $problems.Add("duplicate line: $($t.Ticket)")
                continue
            }
            $seen[$t.Id] = $true
            if (-not $byId.ContainsKey($t.Id)) {
                $problems.Add("not in the active catalog (archived or deleted?): $($t.Ticket)")
                continue
            }
            $rec = $byId[$t.Id]
            if ($rec.status -ne $t.Status) {
                $problems.Add("status drift: $($t.Ticket) queue='$($t.Status)' catalog='$($rec.status)'")
            }
            $expected = Get-TicketBaseName -File $rec.file
            if ($expected -ne $t.Ticket) {
                $problems.Add("renamed spec file: queue='$($t.Ticket)' catalog='$expected'")
            }
        }

        $unlisted = 0
        foreach ($r in $records) {
            # A ready ticket in neither file shipped in an earlier package - not drift. It is counted, though
            # (S0151): in a project that adopted the plan files with built, unshipped work already in its ledger
            # the same state is a release content that is incomplete, and the line above would hide it.
            if (Test-ReleaseReadyStatus -Status $r.status) {
                if (-not $seen.ContainsKey($r.id)) { $unlisted++ }
                continue
            }
            if (-not $seen.ContainsKey($r.id)) {
                $problems.Add("missing from the queue: $(Get-TicketBaseName -File $r.file) [$($r.status)]")
            }
        }

        $unlistedNote = ''
        if ($unlisted -gt 0) {
            $unlistedNote = ("release-queue: note - {0} ready ledger row(s) are listed in neither plan file: shipped in an earlier package, or never seeded. -Seed -Release <N> [-Since ""<yyyy-MM-dd HH:mm>""] lists them and writes nothing without -Apply." -f $unlisted)
        }
        if ($problems.Count -eq 0) {
            Write-Output ("release-queue: OK - {0} ticket(s), no drift" -f $tickets.Count)
            if ($unlistedNote) { Write-Output $unlistedNote }
            exit 0
        }
        Write-Output ("release-queue: DRIFT - {0} problem(s)" -f $problems.Count)
        foreach ($p in $problems) { Write-Output "  $p" }
        if ($unlistedNote) { Write-Output $unlistedNote }
        Write-Output "Fix with: release-queue.ps1 -Reconcile"
        exit 1
    }

    'Seed' {
        # S0151. -Release is the package that takes the ready tickets listed nowhere: a number, because the ready
        # file holds finished content of a package that is going to ship, and `--` is never shipped.
        if ($Release -notmatch '^\d+$') {
            Write-Error "-Release must be a package number, got '$Release'" -ErrorAction Continue
            exit 1
        }
        # Not `$since`: PowerShell names are case-insensitive, and the parameter is a [string].
        $sinceMoment = $null
        if (-not [string]::IsNullOrWhiteSpace($Since)) {
            $sinceMoment = ConvertTo-ReleaseSeedMoment -Text $Since
            if ($null -eq $sinceMoment) {
                Write-Error "-Since must read 'yyyy-MM-dd HH:mm' or 'yyyy-MM-dd', got '$Since'" -ErrorAction Continue
                exit 1
            }
        }
        $report = $null
        # The read and, with -Apply, the rewrite of the plan files are one critical section, as in -Reconcile. A dry
        # run takes the lock as well: a preview read between another writer's two files shows a state that never was.
        Enter-CatalogLock
        try {
            $records = Read-Catalog
            $report = Invoke-ReleaseSeed -Records $records -Release $Release -SinceMoment $sinceMoment -Apply:$Apply
        }
        finally { Exit-CatalogLock }
        if ($Apply) { Sync-PortfolioProjection }

        $readyRel = Get-SzaPath 'releaseReady' -Relative
        $queueRel = Get-SzaPath 'releaseQueue' -Relative
        $sinceText = if ($null -ne $sinceMoment) { $sinceMoment.ToString('yyyy-MM-dd HH:mm') } else { 'none' }
        if ($Apply) {
            Write-Output ("release-queue: seed - package {0}, since {1}" -f $Release, $sinceText)
        } else {
            Write-Output ("release-queue: seed - DRY RUN, nothing written (add -Apply to write); package {0}, since {1}" -f $Release, $sinceText)
        }
        if ($null -eq $sinceMoment) {
            Write-Output "  no -Since: every ready ticket listed nowhere is taken, shipped in an earlier package or not - name the time of the last release to leave those out"
        }
        foreach ($f in $report.Created) {
            Write-Output ("  create    {0}" -f (Get-SzaPath $f -Relative))
        }
        foreach ($t in $report.Added) {
            Write-Output ("  add       {0,-48} {1,-17} updated {2}  -> {3}, package {4}" -f $t.Ticket, $t.Status, $t.Updated, $readyRel, $Release)
        }
        foreach ($t in $report.Moved) {
            $groupText = ''
            if ($null -ne $t.Group) { $groupText = ('  under "{0}"' -f (([string] @($t.Group.Lines)[-1]).Trim())) }
            Write-Output ("  move      {0,-48} {1,-17} {2} -> {3}, package {4}{5}" -f $t.Ticket, $t.Status, $queueRel, $readyRel, $t.Release, $groupText)
        }
        foreach ($t in $report.Returned) {
            Write-Output ("  back      {0,-48} {1,-17} {2} -> {3}, package {4}" -f $t.Ticket, $t.Status, $readyRel, $queueRel, $t.Release)
        }
        foreach ($t in $report.QueueAdded) {
            Write-Output ("  new       {0,-48} {1,-17} -> {2}, package {3}" -f $t.Ticket, $t.Status, $queueRel, $t.Release)
        }
        foreach ($t in $report.LeftOut) {
            Write-Output ("  left out  {0,-48} {1,-17} updated {2}  - {3}" -f $t.Ticket, $t.Status, $t.Updated, $t.Reason)
        }
        $verb = if ($Apply) { 'added' } else { 'would add' }
        Write-Output ("release-queue: seed - {0} {1} ready ticket(s) to package {2}, moved {3} from the queue file, put {4} back in the queue, queued {5} new, left out {6}" -f `
                $verb, $report.Added.Count, $Release, $report.Moved.Count, $report.Returned.Count, $report.QueueAdded.Count, $report.LeftOut.Count)
        if ($report.DuplicatesDropped -gt 0) {
            Write-Output ("release-queue: seed - {0} duplicate line(s) collapsed" -f $report.DuplicatesDropped)
        }
        exit 0
    }

    'SetCurrent' {
        # S0144: under the catalog lock like every other writer of the plan files. A mutator's Sync-ReleaseQueue
        # re-renders this file from its own read, and an older snapshot written back here would undo that.
        Enter-CatalogLock
        $lines = Read-ReleaseQueue
        $updated = $false
        foreach ($line in $lines) {
            if ($line.Kind -eq 'verbatim' -and $line.Text -match '^\s*current-(?:next-)?release:\s*\d+\s*$') {
                $line.Text = "current-next-release: $SetCurrent"
                $updated = $true
            }
        }
        if (-not $updated) {
            Exit-CatalogLock
            Write-Error "No 'current-next-release:' marker in $queuePath" -ErrorAction Continue
            exit 1
        }
        Write-ReleaseQueue -Lines $lines
        Exit-CatalogLock
        Write-Output "release-queue: current release -> $SetCurrent"
        # S3273: the marker labels, it does not order. The bare confirmation above read as "the queue
        # now starts at N", while the runner never reads it - declaring a package current with a lower
        # package still open handed the runner the deferred work and both files looked correct.
        Write-Output 'release-queue: ranking is unaffected - the runner orders by package number ascending, then line order inside a package; the marker only labels the current release (new-ticket placement, the monitor line, the -Ship bump).'
        exit 0
    }

    'Ship' {
        # S0144: the read of both plan files and their rewrite are one critical section under the catalog lock, as in
        # -Reconcile. No child is started in between, so the lock cannot starve one.
        Enter-CatalogLock
        # The shipped content is the READY file - the queue holds what did NOT make it.
        $readyPath = Get-ReleaseReadyPath
        $lines = Read-ReleaseFile -Path $readyPath
        $shipping = @(Get-QueueTickets -Lines $lines | Where-Object { $_.Release -eq $Release })
        if ($shipping.Count -eq 0) {
            Exit-CatalogLock
            Write-Error "Nothing ready for release $Release ($(Get-SzaPath 'releaseReady' -Relative))" -ErrorAction Continue
            exit 1
        }

        # Leftovers stay the owner's call: they are re-sorted into a later package by hand.
        $leftover = @(Get-QueueTickets -Lines (Read-ReleaseQueue) | Where-Object { $_.Release -eq $Release })
        if ($leftover.Count -gt 0) {
            Write-Output ("release-queue: WARNING - {0} unfinished ticket(s) still assigned to release {1}:" -f $leftover.Count, $Release)
            foreach ($u in $leftover) { Write-Output ("  {0,-18} {1}" -f $u.Status, $u.Ticket) }
            Write-Output "  Move them to a later package (or --) in $(Get-SzaPath 'releaseQueue' -Relative); they do not ship."
        }

        if ($DryRun) {
            Exit-CatalogLock
            Write-Output ("release-queue: DRY RUN - would move {0} ready ticket(s) out of release {1}" -f $shipping.Count, $Release)
            exit 0
        }

        $stamp = Get-Today
        $title = if ($Version) { "## release $Release - v$Version - $stamp" } else { "## release $Release - $stamp" }
        $block = New-Object System.Collections.Generic.List[string]
        $block.Add($title)
        $block.Add('')
        foreach ($t in $shipping) {
            # No package column on the row: the block title above it already names the package
            # (S2852), and this file is one block per package by construction.
            $block.Add((Format-ReleaseQueueLine -Ticket $t.Ticket -Changed $t.Changed -Status $t.Status))
        }
        $block.Add('')

        $donePath = Get-ReleaseQueueDonePath
        # S0145: never `$x = if (..) { .. } else { .. }` - the if unrolls the array, so a missing
        # file leaves $null and a one-line file leaves a [string], and `.Count` below throws under
        # StrictMode. Each branch assigns its own array-wrapped value instead.
        if (Test-Path $donePath) { $existing = @(Get-Content -LiteralPath $donePath -Encoding UTF8) }
        else { $existing = @() }
        # Newest release on top: the head of the file is always the last thing shipped.
        $headerLen = 0
        while ($headerLen -lt $existing.Count -and $existing[$headerLen] -notmatch '^## release ') { $headerLen++ }
        $merged = New-Object System.Collections.Generic.List[string]
        for ($i = 0; $i -lt $headerLen; $i++) { $merged.Add($existing[$i]) }
        foreach ($b in $block) { $merged.Add($b) }
        for ($i = $headerLen; $i -lt $existing.Count; $i++) { $merged.Add($existing[$i]) }

        $payload = [string]::Join("`r`n", $merged.ToArray()) + "`r`n"
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText("$donePath.tmp", $payload, $utf8NoBom)
        Move-Item -LiteralPath "$donePath.tmp" -Destination $donePath -Force

        # Drop the shipped block from the ready file.
        $remaining = New-Object System.Collections.Generic.List[object]
        foreach ($line in $lines) {
            if ($line.Kind -eq 'ticket' -and $line.Release -eq $Release) { continue }
            $remaining.Add($line)
        }
        Write-ReleaseFile -Path $readyPath -Lines $remaining

        # Advance the marker, which lives in the queue - the file the owner plans in.
        $queueLines = Read-ReleaseQueue
        foreach ($line in $queueLines) {
            if ($line.Kind -eq 'verbatim' -and $line.Text -match '^\s*current-(?:next-)?release:\s*\d+\s*$') {
                $line.Text = "current-next-release: $([int]$Release + 1)"
            }
        }
        Write-ReleaseQueue -Lines $queueLines
        Exit-CatalogLock

        Write-Output ("release-queue: shipped release {0} - {1} ticket(s) moved to {2}" -f $Release, $shipping.Count, (Split-Path $donePath -Leaf))
        Write-Output ("release-queue: current release -> {0}" -f ([int]$Release + 1))
        exit 0
    }

    default {
        $source = if ($Ready) { Read-ReleaseReady } else { Read-ReleaseQueue }
        # An empty result unrolls to $null at the call site, and `.Count` on $null throws under
        # StrictMode - the array is rebuilt here, not left to the -Release branch below.
        $tickets = @(Get-QueueTickets -Lines $source)
        if ($Release) { $tickets = @($tickets | Where-Object { $_.Release -eq $Release }) }
        # Read the leases once and use them twice. The inline marker answers "is anyone on this
        # right now" in the same scan as the plan itself - a lease lives minutes, so it can never
        # be written into the queue FILE, and a reader who has to consult a second block below
        # the table reads the plan and the occupancy as two separate questions. The block stays
        # because the marker deliberately omits what only matters once occupancy is established:
        # the full session id and host, needed before stealing or clearing a lease.
        $leaseById = @{}
        if ($WithLeases) {
            foreach ($lease in (Get-ActiveTicketLeases)) { $leaseById[[string] $lease.id] = $lease }
        }
        # S2852: the row no longer carries its package, so the listing prints the heading the file
        # prints. Without it a multi-package -List is a flat list of tickets whose package is
        # unknowable, which is the one thing this command is read for.
        $section = $null
        foreach ($t in $tickets) {
            $release = Format-ReleaseQueueSection -Release ([string] $t.Release)
            if ($release -ne $section) {
                Write-Output $release
                $section = $release
            }
            $row = Format-ReleaseQueueLine -Ticket $t.Ticket -Changed $t.Changed -Status $t.Status
            $ticketId = [string] $t.Id
            if ($leaseById.ContainsKey($ticketId)) {
                $lease = $leaseById[$ticketId]
                $sessionId = [string] $lease.sessionId
                # Probed, not read: `mine` is emitted by ticket-lease Status but absent from the
                # test fixture, and a bare read of a missing property throws under StrictMode.
                $mine = $false
                if ($lease.PSObject.Properties['mine']) { $mine = [bool] $lease.mine }
                $holder = if ($mine) {
                    'this session'
                } elseif ($sessionId.Length -ge 8) {
                    'session ' + $sessionId.Substring(0, 8)
                } else {
                    "session $sessionId"
                }
                $reason = if ([string]::IsNullOrWhiteSpace([string] $lease.reason)) { 'no reason given' } else { [string] $lease.reason }
                # Pad to a fixed column so the markers line up: the status column is ragged
                # (4 characters for 'Dead' against 17 for 'BlockNeedUserTest') and an unpadded
                # marker zig-zags across the block, which is the one thing this row is for.
                $row = '{0}[taken {1}m, {2}, {3}]' -f $row.PadRight($script:ReleaseQueueMarkerColumn), $lease.ageMinutes, $reason, $holder
            }
            Write-Output $row
        }
        Write-Output ("--- {0} ticket(s); current release: {1}" -f $tickets.Count, (Get-CurrentRelease))
        if ($WithLeases) {
            $visibleIds = @{}
            foreach ($ticket in $tickets) { $visibleIds[$ticket.Id] = $true }
            $leases = @($leaseById.Values | Where-Object { $visibleIds.ContainsKey([string] $_.id) } | Sort-Object id)
            Write-Output '--- active ticket leases'
            if ($leases.Count -eq 0) {
                Write-Output '(none)'
            } else {
                foreach ($lease in $leases) {
                    Write-Output ("[lease] {0} session={1} age={2}m liveness={3} reason={4}" -f `
                            $lease.id, $lease.sessionId, $lease.ageMinutes, $lease.liveness, $lease.reason)
                }
            }
        }
        exit 0
    }
}
