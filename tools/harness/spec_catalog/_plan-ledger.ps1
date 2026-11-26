# _plan-ledger.ps1 - the release plan facts the ticket ledger holds (TASK-FLOW rules 14-16, amended 0.52).
#
# Dot-sourced by _lib.ps1 and by nothing else: it uses the plan-file readers, the journal readers and the
# placement helpers defined there.
#
# One home per fact. The queue file stays the file of unfinished work. The finished side lives on the ledger row:
#
#   package         the package of a finished ticket that has not shipped
#   packageOrder    its place in the finished side, 1-based across all packages
#   packageChanged  the plan's `changed` column: the last status move, `yy-MM-dd HH:mm`
#   packageNotes    the owner's `#` group lines that travelled with the row (seed and import only)
#   shipments       one entry per shipment: release, block, order, title, version, date, changed, status
#
# `block` numbers a shipment of the whole project, newest highest, so two shipments of one package number stay two.
# The ready and the shipped view are rendered from these fields. The two files that held them before are read once
# (and again whenever an older tool rewrites one) and never written.

$script:PackageFields = @('package', 'packageOrder', 'packageChanged', 'packageNotes')

function Get-PlanProp {
    param($Record, [Parameter(Mandatory)][string] $Name)
    if ($null -eq $Record) { return $null }
    $p = $Record.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Set-PlanProp {
    param([Parameter(Mandatory)] $Record, [Parameter(Mandatory)][string] $Name, $Value)
    if ($null -ne $Record.PSObject.Properties[$Name]) { $Record.$Name = $Value }
    else { $Record | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Remove-PlanProp {
    param([Parameter(Mandatory)] $Record, [Parameter(Mandatory)][string] $Name)
    if ($null -ne $Record.PSObject.Properties[$Name]) { $Record.PSObject.Properties.Remove($Name) }
}

function Remove-PackageFields {
    param([Parameter(Mandatory)] $Record)
    foreach ($f in $script:PackageFields) { Remove-PlanProp -Record $Record -Name $f }
}

function Test-HasPackage {
    param($Record)
    return -not [string]::IsNullOrEmpty([string](Get-PlanProp -Record $Record -Name 'package'))
}

function Get-RecordShipments {
    # Every shipment of one record, oldest block first. Wrap the call in @(..).
    param($Record)
    $value = Get-PlanProp -Record $Record -Name 'shipments'
    if ($null -eq $value) { return }
    @($value) | Where-Object { $null -ne $_ } | Sort-Object -Property @{ Expression = { [int](Get-PlanProp $_ 'block') } }
}

function Add-RecordShipment {
    param([Parameter(Mandatory)] $Record, [Parameter(Mandatory)] $Shipment)
    $all = @(Get-RecordShipments -Record $Record) + @($Shipment)
    Set-PlanProp -Record $Record -Name 'shipments' -Value ([object[]]$all)
}

function New-ShipmentEntry {
    param(
        [Parameter(Mandatory)][string] $Release,
        [Parameter(Mandatory)][int] $Block,
        [Parameter(Mandatory)][int] $Order,
        [Parameter(Mandatory)][string] $Title,
        [Parameter(Mandatory)][string] $Changed,
        [Parameter(Mandatory)][string] $Status
    )
    $facts = ConvertFrom-ShipTitle -Title $Title
    $entry = [ordered]@{ release = $Release; block = $Block; order = $Order; title = $Title }
    if ($facts.Version) { $entry['version'] = $facts.Version }
    if ($facts.Date) { $entry['date'] = $facts.Date }
    $entry['changed'] = $Changed
    $entry['status'] = $Status
    return [pscustomobject]$entry
}

function Format-ShipTitle {
    param([Parameter(Mandatory)][string] $Release, [AllowEmptyString()][string] $Version, [Parameter(Mandatory)][string] $Date)
    if ($Version) { return "## release $Release - v$Version - $Date" }
    return "## release $Release - $Date"
}

function ConvertFrom-ShipTitle {
    # The version and the date a shipped-block title names; either may be absent.
    param([Parameter(Mandatory)][string] $Title)
    $version = ''
    $date = ''
    foreach ($part in @($Title.Trim() -split '\s+-\s+') | Select-Object -Skip 1) {
        $piece = $part.Trim()
        if (-not $date -and $piece -match '^(\d{4}-\d{2}-\d{2})\b') { $date = $Matches[1]; continue }
        if (-not $version -and $piece -match '^v(\d\S*)') { $version = $Matches[1] }
    }
    return [pscustomobject]@{ Version = $version; Date = $date }
}

# -- The finished side as plan lines --------------------------------------------------------------

function Get-ReadyLinesFromRecords {
    # The finished side in the line shape the placement helpers work on: one heading line per run of a package, then
    # its rows in packageOrder. -PreviousStatus gives each row the status the ledger held before the write in hand,
    # which is how a status move is told from any other edit.
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Records,
        [hashtable] $PreviousStatus = @{}
    )
    $lines = New-Object System.Collections.Generic.List[object]
    $rows = @($Records | Where-Object { Test-HasPackage $_ } |
            Sort-Object -Property @{ Expression = { [int](Get-PlanProp $_ 'packageOrder') } }, @{ Expression = { [string]$_.id } })
    $section = $null
    foreach ($r in $rows) {
        $package = Format-ReleaseQueueSection -Release ([string] $r.package)
        if ($package -cne $section) {
            $lines.Add([pscustomobject]@{ Kind = 'verbatim'; Text = $package })
            $section = $package
        }
        $changed = [string](Get-PlanProp $r 'packageChanged')
        if (-not $changed) { $changed = [string]$r.updated }
        $status = if ($PreviousStatus.ContainsKey([string]$r.id)) { [string]$PreviousStatus[[string]$r.id] } else { [string]$r.status }
        $notes = Get-PlanProp $r 'packageNotes'
        $lines.Add([pscustomobject]@{
            Kind    = 'ticket'
            Release = $package
            Ticket  = (Get-TicketBaseName -File $r.file)
            Changed = (ConvertTo-ReleaseChangedStamp -Value $changed)
            Status  = $status
            Id      = [string]$r.id
            Notes   = @($notes | Where-Object { $null -ne $_ })
        })
    }
    return ,$lines
}

function Add-ReadyRows {
    # Add-ReleaseLines over the in-memory finished side: a package with no heading yet gets one first, so a row never
    # settles inside another package's run.
    param([Parameter(Mandatory)][AllowEmptyCollection()] $Target, [Parameter(Mandatory)][AllowEmptyCollection()] $Additions)
    foreach ($add in $Additions) {
        $package = Format-ReleaseQueueSection -Release ([string] $add.Release)
        $found = $false
        foreach ($line in $Target) {
            if ($line.Kind -eq 'verbatim' -and (Get-ReleaseSectionHeading -Text ([string]$line.Text)) -eq $package) { $found = $true; break }
        }
        if (-not $found) { $Target.Add([pscustomobject]@{ Kind = 'verbatim'; Text = $package }) }
        Add-ReleaseLines -Target $Target -Additions @($add)
    }
}

function Set-PackageFields {
    # Write the finished side back onto the records, in line order. Returns the ids that are on it.
    param([Parameter(Mandatory)][hashtable] $ById, [Parameter(Mandatory)] $Lines)
    $order = 0
    $kept = @{}
    foreach ($line in $Lines) {
        if ($line.Kind -ne 'ticket' -or -not $ById.ContainsKey([string]$line.Id)) { continue }
        $record = $ById[[string]$line.Id]
        $order++
        Set-PlanProp $record 'package' (Format-ReleaseQueueSection -Release ([string]$line.Release))
        Set-PlanProp $record 'packageOrder' $order
        Set-PlanProp $record 'packageChanged' ([string]$line.Changed)
        $notes = @()
        if ($null -ne $line.PSObject.Properties['Notes']) { $notes = @($line.Notes | Where-Object { $null -ne $_ }) }
        if ($notes.Count -gt 0) { Set-PlanProp $record 'packageNotes' ([string[]]$notes) }
        else { Remove-PlanProp $record 'packageNotes' }
        $kept[[string]$line.Id] = $true
    }
    return $kept
}

# -- Shipment history -----------------------------------------------------------------------------

function Get-NextShipBlock {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Records)
    $max = 0
    foreach ($r in $Records) {
        foreach ($s in @(Get-RecordShipments -Record $r)) { if ([int]$s.block -gt $max) { $max = [int]$s.block } }
    }
    return ($max + 1)
}

function Get-ShipBlocks {
    # The shipment history of the given records: newest block first, rows in shipped order. Wrap the call in @(..).
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Records)
    $blocks = @{}
    foreach ($r in $Records) {
        foreach ($s in @(Get-RecordShipments -Record $r)) {
            $key = [int]$s.block
            if (-not $blocks.ContainsKey($key)) {
                $blocks[$key] = [pscustomobject]@{ Block = $key; Title = [string]$s.title; Release = [string]$s.release; Rows = (New-Object System.Collections.Generic.List[object]) }
            }
            $blocks[$key].Rows.Add([pscustomobject]@{
                Id = [string]$r.id; Ticket = (Get-TicketBaseName -File $r.file); Order = [int]$s.order
                Changed = [string]$s.changed; Status = [string]$s.status
            })
        }
    }
    foreach ($key in @($blocks.Keys | Sort-Object -Descending)) {
        $block = $blocks[$key]
        $block.Rows = @($block.Rows | Sort-Object -Property Order, Id)
        $block
    }
}

function Get-ShippedArchiveReason {
    # The archive reason a recorded shipment proves, from the newest one; $null when there is none with a version.
    param($Record)
    $last = @(Get-RecordShipments -Record $Record) | Select-Object -Last 1
    if ($null -eq $last) { return $null }
    $version = [string](Get-PlanProp $last 'version')
    if (-not $version) { return $null }
    return ('shipped in v{0} (release {1})' -f $version, $last.release)
}

# -- The one-way import of the two files the ledger replaced ----------------------------------------

function Get-RecordIdMap {
    # id and former id -> record. A current id wins over a former one.
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Records)
    $map = @{}
    foreach ($r in $Records) { $map[[string]$r.id] = $r }
    foreach ($r in $Records) {
        foreach ($former in @(Get-PlanProp $r 'formerIds')) {
            if ($former -and -not $map.ContainsKey([string]$former)) { $map[[string]$former] = $r }
        }
    }
    return $map
}

function Get-LegacyDoneBlocks {
    # The blocks of the old shipped file, top (newest) first. Wrap the call in @(..).
    $lines = Read-ReleaseFile -Path $script:ReleaseQueueDonePath
    $block = $null
    foreach ($line in $lines) {
        if ($line.Kind -eq 'verbatim' -and $line.Text -match '^##\s+release\s') {
            if ($null -ne $block) { $block }
            $block = [pscustomobject]@{ Title = ([string]$line.Text).TrimEnd(); Rows = (New-Object System.Collections.Generic.List[object]) }
            continue
        }
        if ($line.Kind -eq 'ticket' -and $null -ne $block) { $block.Rows.Add($line) }
    }
    if ($null -ne $block) { $block }
}

function Import-LegacyReleaseFiles {
    # Read the old ready and shipped files into records held in memory. The caller decides whether to persist.
    #
    # Idempotent. A ready row is taken when its ledger row is active and finished, has no package, is not in the queue
    # file and no shipment carries the row's own stamp (that row already shipped). A shipped row is taken when its
    # record has no shipment of the same block title and stamp. Neither file is written.
    #
    # Returns @{ ReadyRows; ActiveChanged; ArchiveChanged; Unattributed }.
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Records,
        [AllowEmptyCollection()][object[]] $ArchiveRecords = @(),
        [hashtable] $QueueIds = @{}
    )
    $result = [pscustomobject]@{
        ReadyRows = (New-Object System.Collections.Generic.List[object])
        ActiveChanged = $false
        ArchiveChanged = $false
        Unattributed = (New-Object System.Collections.Generic.List[string])
    }
    $map = Get-RecordIdMap -Records (@($Records) + @($ArchiveRecords))
    $activeIds = @{}
    foreach ($r in $Records) { $activeIds[[string]$r.id] = $true }

    $readyLines = Read-ReleaseFile -Path $script:ReleaseReadyPath
    $groups = Get-ReleaseRowGroups -Lines $readyLines
    $previous = $null
    $taken = @{}
    foreach ($row in $readyLines) {
        if ($row.Kind -ne 'ticket') { continue }
        if (-not $map.ContainsKey([string]$row.Id)) { continue }
        $record = $map[[string]$row.Id]
        $id = [string]$record.id
        $shippedRow = @(Get-RecordShipments -Record $record | Where-Object { [string]$_.changed -ceq [string]$row.Changed }).Count -gt 0
        if ($activeIds.ContainsKey($id) -and (Test-ReleaseReadyStatus -Status $record.status) -and
            -not (Test-HasPackage $record) -and -not $QueueIds.ContainsKey($id) -and -not $shippedRow -and -not $taken.ContainsKey($id)) {
            $notes = @()
            if ($groups.ContainsKey([string]$row.Id)) { $notes = @($groups[[string]$row.Id].Lines) }
            $result.ReadyRows.Add([pscustomobject]@{
                Kind = 'ticket'; Release = [string]$row.Release; Ticket = (Get-TicketBaseName -File $record.file)
                Changed = [string]$row.Changed; Status = [string]$record.status; Id = $id; After = $previous; Notes = $notes
            })
            $taken[$id] = $true
        }
        $previous = $id
    }

    $legacy = @(Get-LegacyDoneBlocks)
    $next = Get-NextShipBlock -Records (@($Records) + @($ArchiveRecords))
    # Oldest first, so the block numbers rise toward the top of the old file.
    for ($i = $legacy.Count - 1; $i -ge 0; $i--) {
        $block = $legacy[$i]
        $missing = New-Object System.Collections.Generic.List[object]
        $target = $null
        $order = 0
        foreach ($row in $block.Rows) {
            $order++
            if (-not $map.ContainsKey([string]$row.Id)) { $result.Unattributed.Add("$($block.Title) | $($row.Ticket)"); continue }
            $record = $map[[string]$row.Id]
            $known = @(Get-RecordShipments -Record $record | Where-Object {
                    [string]$_.title -ceq $block.Title -and [string]$_.changed -ceq [string]$row.Changed }) | Select-Object -First 1
            if ($null -ne $known) { $target = [int]$known.block; continue }
            $missing.Add([pscustomobject]@{ Record = $record; Row = $row; Order = $order })
        }
        if ($missing.Count -eq 0) { continue }
        if ($null -eq $target) { $target = $next; $next++ }
        foreach ($m in $missing) {
            $entry = New-ShipmentEntry -Release ([string]$m.Row.Release) -Block $target -Order $m.Order -Title $block.Title `
                -Changed ([string]$m.Row.Changed) -Status ([string]$m.Row.Status)
            Add-RecordShipment -Record $m.Record -Shipment $entry
            if ($activeIds.ContainsKey([string]$m.Record.id)) { $result.ActiveChanged = $true }
            else { $result.ArchiveChanged = $true }
        }
    }
    return $result
}

function Get-LegacyPlanStampPath { return (Join-Path (Get-SzaPath 'tempDir') 'release-plan-imported.json') }

function Get-LegacyPlanFingerprint {
    # What the two old files and the journal in use look like now. A change means an import is due.
    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add((Get-CatalogPath))
    foreach ($path in @($script:ReleaseReadyPath, $script:ReleaseQueueDonePath)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $item = Get-Item -LiteralPath $path
            $parts.Add(('{0}:{1}' -f $item.Length, $item.LastWriteTimeUtc.Ticks))
        } else { $parts.Add('-') }
    }
    return ($parts -join '|')
}

function Test-LegacyPlanImported {
    # $true when nothing is left to import: no old file exists, or both are as the last persisted import saw them.
    # The stamp lives in the scratch directory; losing it costs one more idempotent read.
    if (-not (Test-Path -LiteralPath $script:ReleaseReadyPath) -and -not (Test-Path -LiteralPath $script:ReleaseQueueDonePath)) { return $true }
    $stamp = Get-LegacyPlanStampPath
    if (-not (Test-Path -LiteralPath $stamp -PathType Leaf)) { return $false }
    return ([IO.File]::ReadAllText($stamp).Trim() -ceq (Get-LegacyPlanFingerprint))
}

function Set-LegacyPlanImported {
    $stamp = Get-LegacyPlanStampPath
    $dir = Split-Path -Parent $stamp
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($stamp, (Get-LegacyPlanFingerprint), [Text.UTF8Encoding]::new($false))
}

function Get-QueueIdSet {
    $set = @{}
    foreach ($line in (Read-ReleaseQueue)) { if ($line.Kind -eq 'ticket') { $set[[string]$line.Id] = $true } }
    return $set
}

function Read-PlanRecords {
    # Both journals with the old files imported in memory. Writes nothing; the next ledger write persists it.
    $active = Read-Catalog
    $archived = Read-JsonlFile -Path (Get-ArchivePath)
    $import = $null
    if (-not (Test-LegacyPlanImported)) {
        $import = Import-LegacyReleaseFiles -Records $active -ArchiveRecords $archived -QueueIds (Get-QueueIdSet)
    }
    return [pscustomobject]@{ Active = $active; Archived = $archived; Import = $import }
}

function Read-ReleaseReady {
    # The finished side of the plan, rendered from the ledger, as the line objects Read-ReleaseFile returns.
    $plan = Read-PlanRecords
    $lines = Get-ReadyLinesFromRecords -Records $plan.Active
    if ($null -ne $plan.Import) { Add-ReadyRows -Target $lines -Additions $plan.Import.ReadyRows }
    return ,$lines
}

# -- The reconciliation every ledger write runs (Write-Catalog) -------------------------------------

function Update-ReleasePlan {
    # Compute the plan for the records about to be written and put the plan fields onto them. Runs before the
    # journal write and writes nothing itself; Complete-ReleasePlan writes the queue file afterwards.
    #
    # Invariants:
    #   - never reorders rows and never changes a row's package,
    #   - moves the `changed` stamp ONLY when the status actually moved,
    #   - a status change across the ready boundary moves the row to the other side, keeping its place when it can,
    #   - drops a row whose ticket left the active journal (archived or deleted),
    #   - never puts a ready ticket that is on neither side onto one: it shipped earlier, or was never planned
    #     (release-queue.ps1 -Seed is the owner's one-off for a ledger where that is false, S0151),
    #   - keeps ONE row per ticket id across both sides: the queue file wins (S1698).
    #
    # A ticket reopened from the finished side keeps its plan fields in this journal write and loses them after the
    # queue file holds its row, so a queue write that fails never loses its package.
    param([AllowEmptyCollection()][object[]] $Records = @())

    if ((Get-SzaEnv 'SKIP_RELEASE_QUEUE')) { return $null }
    if (-not (Test-Path $script:ReleaseQueuePath)) {
        # S0102: still not an error - the journal write stands and no file is created - but it is said once
        # per process, because a profile naming a file nobody created read exactly like a reconciled queue.
        if (-not $script:ReleaseQueueMissingNoted) {
            $script:ReleaseQueueMissingNoted = $true
            Write-Host ("  release queue: no file at {0} (paths.releaseQueue) - nothing reconciled; work order is the ledger's. Not an error of this write." -f $script:ReleaseQueuePath) -ForegroundColor DarkYellow
        }
        return $null
    }

    $script:ReleaseQueueDuplicatesDropped = 0
    $byId = @{}
    foreach ($r in $Records) { $byId[[string]$r.id] = $r }
    $previous = @{}
    foreach ($r in (Read-JsonlFile -Path (Get-CatalogPath))) { $previous[[string]$r.id] = [string]$r.status }

    $archived = @()
    $import = $null
    if (-not (Test-LegacyPlanImported)) {
        $archived = Read-JsonlFile -Path (Get-ArchivePath)
        $import = Import-LegacyReleaseFiles -Records $Records -ArchiveRecords $archived -QueueIds (Get-QueueIdSet)
    }
    $readyLines = Get-ReadyLinesFromRecords -Records $Records -PreviousStatus $previous
    if ($null -ne $import) { Add-ReadyRows -Target $readyLines -Additions $import.ReadyRows }

    $stamp = Get-ReleaseChangedStamp
    $seen = @{}
    $toReady = New-Object System.Collections.Generic.List[object]
    $toQueue = New-Object System.Collections.Generic.List[object]

    # One pass per side: keep what still belongs, collect what crossed the boundary.
    $queueLines = Read-ReleaseQueue
    $keptQueue = Select-ReleaseLines -Lines $queueLines -ById $byId -Seen $seen `
        -Stamp $stamp -WantReady $false -Moved $toReady
    $keptReady = Select-ReleaseLines -Lines $readyLines -ById $byId -Seen $seen `
        -Stamp $stamp -WantReady $true -Moved $toQueue
    $reopened = @($toQueue | ForEach-Object { [string]$_.Id })

    # A brand-new ticket is unfinished by definition, so it lands in the queue only.
    $current = Get-CurrentRelease
    foreach ($r in ($Records | Sort-Object -Property id)) {
        if ($seen.ContainsKey($r.id)) { continue }
        if (Test-ReleaseReadyStatus -Status $r.status) { continue }
        $toQueue.Add([pscustomobject]@{
            Kind    = 'ticket'
            Release = $current
            Ticket  = (Get-TicketBaseName -File $r.file)
            Changed = (ConvertTo-ReleaseChangedStamp -Value "$($r.updated)")
            Status  = $r.status
            Id      = $r.id
        })
    }

    Add-ReleaseLines -Target $keptQueue -Additions $toQueue
    Add-ReadyRows -Target $keptReady -Additions $toReady

    $kept = Set-PackageFields -ById $byId -Lines $keptReady
    foreach ($r in $Records) {
        if (-not $kept.ContainsKey([string]$r.id) -and $reopened -notcontains [string]$r.id) { Remove-PackageFields -Record $r }
    }
    return [pscustomobject]@{
        Queue    = $keptQueue
        Reopened = $reopened
        Archived = $archived
        Import   = $import
    }
}

function Complete-ReleasePlan {
    # The writes that follow the journal write.
    param([Parameter(Mandatory)] $Plan, [AllowEmptyCollection()][object[]] $Records = @())
    Write-ReleaseFile -Path $script:ReleaseQueuePath -Lines $Plan.Queue
    $left = @($Records | Where-Object { $Plan.Reopened -contains [string]$_.id -and (Test-HasPackage $_) })
    if ($left.Count -gt 0) {
        foreach ($r in $left) { Remove-PackageFields -Record $r }
        Write-JsonlFile -Path (Get-CatalogPath) -Lines @(Format-CatalogLines -Records $Records)
    }
    if ($null -ne $Plan.Import) {
        if ($Plan.Import.ArchiveChanged) { Write-ArchiveCatalog -Records $Plan.Archived }
        Set-LegacyPlanImported
    }
}

function Save-LegacyPlanImport {
    # Persist a due import now, through the one write path. A caller that already holds the catalog lock keeps it.
    if ((Get-SzaEnv 'SKIP_RELEASE_QUEUE') -or -not (Test-Path $script:ReleaseQueuePath) -or (Test-LegacyPlanImported)) { return }
    $held = $null -ne $script:CatalogMutex
    if (-not $held) { Enter-CatalogLock }
    try {
        $records = Read-Catalog
        Write-Catalog -Records $records
    }
    finally { if (-not $held) { Exit-CatalogLock } }
}

# -- The two views --------------------------------------------------------------------------------

function Get-ReleaseReadyViewLines {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($h in @(Get-ReleaseReadyHeaderLines)) { $out.Add($h) }
    $section = $null
    $lastNotes = ''
    $ready = Read-ReleaseReady
    foreach ($line in $ready) {
        if ($line.Kind -ne 'ticket') { continue }
        $package = Format-ReleaseQueueSection -Release ([string]$line.Release)
        if ($package -cne $section) { $out.Add($package); $section = $package; $lastNotes = '' }
        $notes = @($line.Notes)
        $joined = $notes -join "`n"
        if ($joined -and $joined -cne $lastNotes) { foreach ($n in $notes) { $out.Add([string]$n) } }
        $lastNotes = $joined
        $out.Add((Format-ReleaseQueueLine -Ticket $line.Ticket -Changed $line.Changed -Status $line.Status))
    }
    return $out.ToArray()
}

function Get-ReleaseDoneViewLines {
    $plan = Read-PlanRecords
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($h in @(Get-ReleaseDoneHeaderLines)) { $out.Add($h) }
    $all = @($plan.Active) + @($plan.Archived)
    foreach ($block in @(Get-ShipBlocks -Records $all)) {
        $out.Add($block.Title)
        $out.Add('')
        foreach ($row in $block.Rows) { $out.Add((Format-ReleaseQueueLine -Ticket $row.Ticket -Changed $row.Changed -Status $row.Status)) }
        $out.Add('')
    }
    # A row of the old file that names no ledger ticket cannot be carried on a record: it is shown, from that file.
    $map = Get-RecordIdMap -Records $all
    $orphans = New-Object System.Collections.Generic.List[string]
    foreach ($block in @(Get-LegacyDoneBlocks)) {
        foreach ($row in $block.Rows) { if (-not $map.ContainsKey([string]$row.Id)) { $orphans.Add("# $($block.Title.TrimStart('#', ' ')) | $($row.Ticket)") } }
    }
    if ($orphans.Count -gt 0) {
        $out.Add(('# rows that name no ledger ticket, kept in {0}:' -f (Get-SzaPath 'releaseQueueDone' -Relative)))
        foreach ($o in $orphans) { $out.Add($o) }
    }
    return $out.ToArray()
}
