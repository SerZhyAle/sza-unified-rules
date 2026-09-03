<#
.SYNOPSIS
    Show what the unattended queue runners are doing right now.

.DESCRIPTION
    Answers the question an operator actually has after leaving the machine working: is anything
    still running, what is it on, what has it finished, and is something stuck.

    Since S2406 this script renders and never collects: every section is printed from ONE snapshot
    object returned by Get-DevMonitorSnapshot (scripts/utils/dev-monitor-snapshot.ps1), the same
    object the monitor page (`.\a.ps1 rmw`) renders, so the two surfaces cannot disagree. `-Json`
    prints that object verbatim for any other viewer. The sources, each of which knows something
    the others do not:

      - Headless claude children (`claude.exe` started with -p). Their existence is the only proof
        that a run is still alive; a journal cannot say whether the process behind its last row died.
        Each one is listed with the age of the newest file its ticket has written, because existence
        alone does not separate a working run from a wedged one: a child waiting on the API sits at
        about 2% of one core, so pid age and CPU time read the same either way (measured 2026-08-25,
        two runs looked hung at 19 and 16 minutes and were both mid-plan).
      - Ticket leases (temp/SPEC-TICKET.LEASES). A live lease names the ticket a run is working
        *now* - the journal only gets its row when the ticket is finished. Read in-process and judged
        by the same liveness helper ticket-lease.ps1 uses; a lease that helper calls stale is still
        printed, marked, because this view evicts nothing.
      - The per-instance journals under temp/spec-queue/runs-<instance>.jsonl - what finished, how it
        ended, on which model, and how long it took.
      - The coordination locks, one per domain (S2109/S2170) - who is building or editing, and who
        is queued behind them. Two parallel instances spend real time here, and a run that looks
        idle is usually just waiting for the other one's gradle. The domains come from
        scripts/utils/agent-lock-domains.ps1, never from a list repeated here: a monitor carrying
        its own copy of the domain names is exactly how this section spent a day showing two
        pre-split files that nothing writes any more.
      - The agent chat (S2372): the last line of every agent in the window, by nickname.

    Read-only. It starts nothing, stops nothing and writes nothing.

    Exit codes: 0 - the report was produced (including "nothing is running", which is an answer),
                2 - the repository layout could not be read (temp/ missing, journals unreadable).

.EXAMPLE
    pwsh -NoProfile -File scripts/utils/monitor-spec-queue.ps1
    One snapshot.

.EXAMPLE
    pwsh -NoProfile -File scripts/utils/monitor-spec-queue.ps1 -Watch
    Refresh every 30 seconds until Ctrl+C.

.EXAMPLE
    pwsh -NoProfile -File scripts/utils/monitor-spec-queue.ps1 -Json
    The snapshot object as JSON - what the monitor page renders.
#>
[CmdletBinding()]
param(
    # How many finished tickets to list per instance. One by default: the operator's question between
    # refreshes is "what changed since I last looked", and the full history is in the journal file.
    [int] $Tail = 1,

    # Refresh until interrupted instead of printing one snapshot.
    [switch] $Watch,

    # Seconds between refreshes in -Watch mode.
    [int] $IntervalSeconds = 30,

    # Print the snapshot object as JSON instead of the sections (S2406).
    [switch] $Json,

    [string] $RepoRoot = '',

    [switch] $Help
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = Get-SzaProjectRoot }

if ($Help) {
    Show-SzaHelp $PSCommandPath
    exit $LASTEXITCODE
}

$ErrorActionPreference = 'Stop'

$tempDir = (Join-Path $RepoRoot (Get-SzaPath 'tempDir' -Relative))
if (-not (Test-Path -LiteralPath $tempDir)) {
    Write-Host "monitor-spec-queue: $(Get-SzaPath 'tempDir' -Relative)/ not found under $RepoRoot." -ForegroundColor Red
    exit 2
}

. (Join-Path $PSScriptRoot 'dev-monitor-snapshot.ps1')

function Write-Section([string] $Title) {
    Write-Host ''
    Write-Host ("-- {0} " -f $Title).PadRight(78, '-') -ForegroundColor DarkGray
}

function Format-Minutes {
    param($Minutes)
    if ($null -eq $Minutes) { return '?' }
    $m = [double]$Minutes
    if ($m -lt 1) { return ("{0:N0}s" -f ($m * 60)) }
    if ($m -lt 90) { return ("{0:N0}m" -f $m) }
    return ("{0:N1}h" -f ($m / 60))
}

function Format-HeldAge {
    param($Minutes, $AcquiredAtUtc)
    if ($null -eq $Minutes) { return 'for an unknown time' }
    $since = ''
    if ($AcquiredAtUtc) { try { $since = ([DateTime]::Parse($AcquiredAtUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)).ToLocalTime().ToString('HH:mm:ss') } catch { $since = '' } }
    if ([double]$Minutes -lt 1) { return ("{0,3:N0} sec   (since {1})" -f ([double]$Minutes * 60), $since) }
    return ("{0,3:N0} min   (since {1})" -f [double]$Minutes, $since)
}

function Format-ChatAge {
    param([double]$Minutes)
    if ($Minutes -lt 1) { return 'now' }
    $whole = [int][math]::Floor($Minutes)
    if ($whole -lt 60) { return ('{0}m' -f $whole) }
    return ('{0}h{1:00}' -f [int][math]::Floor($whole / 60), ($whole % 60))
}

function Show-QueueTickets {
    param($Tickets)

    $index = 0
    foreach ($ticket in @($Tickets)) {
        $index++
        # The session guid is what distinguishes two runners whose reasons read alike; eight
        # characters separate them without spending a third of the line on one field.
        $session = ([string]$ticket.sessionId)
        if ($session.Length -gt 8) { $session = $session.Substring(0, 8) }
        # Both ages, because they answer different questions and only together separate the two
        # shapes: a long wait with a fresh heartbeat is a session doing its job behind a slow
        # holder, while a long wait with a cold one is an abandoned intent head-blocking everybody.
        # This view never evicts (it writes nothing), so it has to SAY which it is looking at.
        Write-Host ("      #{0} {1}  waiting {2}, last seen {3}  {4}" -f `
                $index, $session, (Format-Minutes $ticket.waitedMinutes), (Format-Minutes $ticket.lastSeenMinutes), [string]$ticket.reason) -ForegroundColor DarkGray
    }
}

function Show-Snapshot {
    param($Snapshot)

    Write-Host ''
    Write-Host ("spec-queue monitor   {0}   ({1} ms)" -f $Snapshot.takenAtLocal, $Snapshot.durationMs) -ForegroundColor Cyan

    # --- leases: what is being worked on right now ----------------------------------------------
    Write-Section 'ticket leases (what is claimed now)'
    $leases = @($Snapshot.leases)
    if ($leases.Count -eq 0) {
        Write-Host '  nothing leased.' -ForegroundColor DarkYellow
    } else {
        # One id per line costs a screen-height per five tickets and says nothing a comma cannot. A
        # lease the liveness helper would sweep is kept and marked - this view writes nothing.
        $parts = foreach ($l in $leases) {
            if ($l.liveness -eq 'foreign-stale') { "$($l.id) (stale)" }
            elseif ($l.liveness -eq 'unknown') { "$($l.id) (?)" }
            else { $l.id }
        }
        Write-Host ("  " + ($parts -join ', '))
    }

    # --- locks -----------------------------------------------------------------------------------
    Write-Section 'locks (who is building or editing)'
    $free = @()
    foreach ($lock in @($Snapshot.locks | Where-Object { -not $_.legacy })) {
        $queue = @($lock.queue)
        if (-not $lock.held) {
            # A queue with nobody holding the lock is not idleness - it is a turn about to be taken,
            # and collapsing it into the "free" line would hide the one domain worth watching.
            if ($queue.Count -eq 0) { $free += $lock.domain; continue }
            Write-Host ("  {0,-13} free, {1} queued" -f $lock.domain, $queue.Count) -ForegroundColor DarkYellow
        }
        else {
            $held = if ($lock.unreadable) { '(unreadable)' } else { "{0}  held {1}" -f $lock.reason, (Format-HeldAge $lock.heldMinutes $lock.acquiredAtUtc) }
            Write-Host ("  {0,-13} HELD  {1}" -f $lock.domain, $held) -ForegroundColor Yellow
        }
        Show-QueueTickets -Tickets $queue
    }

    # Every free domain on one line: five domains printed as five lines push the block the operator
    # actually reads off the screen, and "free" carries no detail worth a line of its own.
    if ($free.Count -gt 0) {
        Write-Host ("  {0,-13} {1}" -f 'free', ($free -join ', ')) -ForegroundColor DarkGray
    }

    # Pre-split files still hold every domain of their type until their owner releases them, so a
    # session working from before the split must not read as nobody at all.
    foreach ($legacy in @($Snapshot.locks | Where-Object { $_.legacy })) {
        $reason = if ($legacy.unreadable) { '(unreadable)' } else { "{0}  held {1}" -f $legacy.reason, (Format-HeldAge $legacy.heldMinutes $legacy.acquiredAtUtc) }
        Write-Host ("  {0,-13} HELD  {1}  (pre-split file - covers every {2} domain)" -f "$($legacy.domain.ToUpper()).LOCK", $reason, $legacy.domain.ToLower()) -ForegroundColor Yellow
    }

    # --- agent chat (S2372) -----------------------------------------------------------------------
    # One row per agent that wrote in the retention window (by nickname - the owner's ruling of
    # 2026-09-02: a name he can recognise, not a pid), newest first, plus the alive-finding count.
    $retention = if ($Snapshot.windows) { $Snapshot.windows.retentionMinutes } else { '?' }
    Write-Section ('agent chat (last message per agent, {0} min window)' -f $retention)
    if ($Snapshot.chatError) {
        Write-Host ("  agent chat unavailable: {0}" -f $Snapshot.chatError) -ForegroundColor DarkYellow
    }
    elseif (@($Snapshot.agents).Count -eq 0) {
        Write-Host '  nobody has written.' -ForegroundColor DarkYellow
    }
    else {
        foreach ($r in @($Snapshot.agents)) {
            $flag = if ($r.silent) { 'SILENT' } else { 'live' }
            $where = if ($r.lastTicket -and $r.phase -and $r.phaseTicket -eq $r.lastTicket) { "$($r.lastTicket)/$($r.phase)" } elseif ($r.lastTicket) { $r.lastTicket } elseif ($r.phaseTicket) { "$($r.phaseTicket)/$($r.phase)" } else { '-' }
            Write-Host ('  {0,-6} {1,5} ago  {2,-22} {3}/{4}  {5,-9} {6,-12} {7}' -f $flag, (Format-ChatAge $r.ageMinutes), $r.name, $r.runtime, $r.model, $r.lastKind, $where, $r.lastNote) -ForegroundColor $(if ($r.silent) { 'DarkYellow' } else { 'Gray' })
        }
        Write-Host ('  alive findings: {0}  (`.\a.ps1 chat -Verb Find -Topic "*"` lists them)' -f @($Snapshot.findings).Count) -ForegroundColor DarkGray
        if ($Snapshot.findingsDead -and $Snapshot.findingsDead -gt 0) {
            $parts = @()
            if ($Snapshot.findingsDeadReasons) {
                $r = $Snapshot.findingsDeadReasons
                if ($r.expired -gt 0) { $parts += "expired: $($r.expired)" }
                if ($r.scopeChanged -gt 0) { $parts += "scope changed: $($r.scopeChanged)" }
                if ($r.deviceGone -gt 0) { $parts += "device gone: $($r.deviceGone)" }
                if ($r.unreadable -gt 0) { $parts += "unreadable: $($r.unreadable)" }
            }
            $breakdown = if ($parts.Count -gt 0) { " (" + ($parts -join ', ') + ")" } else { "" }
            Write-Host ('  dead findings:  {0}{1}' -f $Snapshot.findingsDead, $breakdown) -ForegroundColor DarkGray
        }
    }

    # --- journals ---------------------------------------------------------------------------------
    Write-Section ("finished tickets (last {0} per instance)" -f $Tail)
    $instances = @($Snapshot.instances)
    if ($instances.Count -eq 0) {
        Write-Host '  no run journal yet.' -ForegroundColor DarkYellow
    } else {
        foreach ($i in $instances) {
            Write-Host ''
            Write-Host ("  instance '{0}' - {1} ticket(s) recorded" -f $i.instance, $i.recorded) -ForegroundColor Cyan
            if ($i.recorded -eq 0) { continue }
            foreach ($r in @($i.rows)) {
                $colour = if ($r.moved) { 'Green' } elseif ($r.outcome -ne 'ok') { 'Red' } else { 'Yellow' }
                Write-Host ("    {0,-6} {1,-14} -> {2,-18} {3,-26} {4,3} min  {5}" -f `
                        $r.id, $r.statusBefore, $r.statusAfter, $r.outcome, $r.minutes, $r.model) -ForegroundColor $colour
            }
            Write-Host ("    total: {0} run, {1} moved, {2} stayed put" -f $i.recorded, $i.moved, $i.stayed) -ForegroundColor DarkGray
        }
    }

    # --- stop flags ---------------------------------------------------------------------------------
    $children = @($Snapshot.children)
    $stops = @($Snapshot.stop)
    if ($stops.Count -gt 0) {
        Write-Section 'stop requested'
        foreach ($f in $stops) {
            Write-Host ("  {0}  requested {1:N0} min ago" -f $f.name, [double]$f.requestedMinutes) -ForegroundColor Yellow
        }
        # The pending age is the whole point of this section. A stop is read only between tickets, so
        # one that has been pending for half an hour is waiting on the run listed below, not failing.
        if ($children.Count -gt 0) {
            Write-Host '  waiting for the ticket(s) listed under "running" to end.' -ForegroundColor DarkGray
            Write-Host '  To stop without waiting:  .\a.ps1 rs -Kill' -ForegroundColor DarkGray
        } else {
            Write-Host '  nothing is running - the next start clears the flag and proceeds.' -ForegroundColor DarkGray
        }
    }

    # --- running children (last on purpose: it is the block the operator reads on every refresh, so
    # it belongs where the cursor already is instead of scrolled off the top by the journals) ------
    Write-Section 'running'
    if ($children.Count -eq 0) {
        Write-Host '  no headless claude child is running.' -ForegroundColor DarkYellow
    } else {
        foreach ($c in $children) {
            $age = if ($null -ne $c.ageMinutes) { '{0,4:N0} min' -f [double]$c.ageMinutes } else { '   ? min' }
            Write-Host ("  pid {0,-7} {1}  ticket {2}  model {3}" -f $c.pid, $age, $c.ticket, $c.model) -ForegroundColor Green

            $quiet = $c.quietMinutes
            $writeColour = if ($null -eq $quiet) { 'DarkGray' }
                elseif ([double]$quiet -lt 5) { 'Green' }
                elseif ([double]$quiet -lt 15) { 'Yellow' }
                else { 'Red' }

            if ($null -eq $c.lastWriteMinutes) {
                Write-Host '        last write   nothing on disk for this ticket yet' -ForegroundColor $writeColour
            } elseif ($c.writeBeforeStart) {
                Write-Host ("        last write   nothing since this run started; newest is {0}" -f $c.lastWritePath) -ForegroundColor $writeColour
            } else {
                Write-Host ("        last write {0,4:N0} min ago   {1}" -f [double]$c.lastWriteMinutes, $c.lastWritePath) -ForegroundColor $writeColour
            }

            if ($null -ne $quiet -and [double]$quiet -ge 15) {
                # Silence this long is worth explaining rather than alarming: the two quiet stretches of
                # a pipeline are a gradle build (see the locks section) and a single long model turn, and
                # neither writes anything until it ends.
                Write-Host '        quiet for a while - check the locks above; a queued or running build writes nothing.' -ForegroundColor DarkGray
            }
        }
    }

    Write-Host ''
}

if ($Json) {
    Get-DevMonitorSnapshot -RepoRoot $RepoRoot -Tail $Tail | ConvertTo-Json -Depth 8
    exit 0
}

if ($Watch) {
    Write-Host 'monitor-spec-queue: refreshing until Ctrl+C.' -ForegroundColor DarkGray
    while ($true) {
        $snapshot = Get-DevMonitorSnapshot -RepoRoot $RepoRoot -Tail $Tail
        Clear-Host
        Show-Snapshot -Snapshot $snapshot
        Start-Sleep -Seconds $IntervalSeconds
    }
}

Show-Snapshot -Snapshot (Get-DevMonitorSnapshot -RepoRoot $RepoRoot -Tail $Tail)
exit 0
