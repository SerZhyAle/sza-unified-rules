<#
.SYNOPSIS
    Take a place in a lock's queue, block until it is this session's turn, then EXIT.

.DESCRIPTION
    S1432. Run this as a BACKGROUND task: its exit is the "your turn" signal. The agent that
    launched it is free to do work that needs no lock (reading, research, specs, catalog, docs)
    and gets called back the moment this process ends - which is the only channel through which
    an external event can return an agent to work.

    The ticket deliberately SURVIVES a granted exit: the caller inherits it and is protected by
    the head-of-queue reservation window while it starts the real work. Pass the ticket back to
    Enter-AgentLock (-Ticket) so the lock acquire obeys the queue and the ticket is retired.
    On timeout or eviction the ticket is removed - nobody is left holding a place they will
    never use.

    The verdict travels in a marker file, never in the exit code: a background task reports the
    exit of the last command in its launch line, which has already turned a refused build into
    an apparently green one. Read the marker.

    Each poll doubles as the ticket's liveness heartbeat (S1448): it stamps lastSeenAt on the
    ticket, so a session waiting exactly as the contract demands - background waiter plus
    lock-free work, therefore no transcript writes - is no longer evicted for staying quiet.

.PARAMETER Name
    Which lock to queue for: Build or Code.

.PARAMETER Reason
    Free text recorded in the ticket - shown to whoever inspects the queue.

.PARAMETER WaitTimeoutSeconds
    Give up after this long. Default 3600.

.PARAMETER PollSeconds
    Interval between turn checks. Default 5.

.PARAMETER Acquire
    Take the lock in THIS process the moment the turn arrives, instead of exiting and leaving
    the caller to run enter-code-lock.ps1 again. That second call is a model round trip, and the
    round trip is what burns the head-of-queue reservation: measured 2026-09-03 on Code.Scripts,
    two consecutive handovers left the free lock idle for 3m03s and 3m07s - the full
    ReservationMinutes - because the granted head was a chat turn away from claiming it, while
    the handovers where the winner was already polling took 9-16 s. Chaining the acquire onto the
    poll costs no tokens and closes that gap to one poll interval.

    Refused, with a warning and a fall back to a plain wait, in the two cases where the lock
    would outlive the process that owns it: a Build domain, whose staleness is judged by the
    acquiring PID (this process exits immediately, so the lock would read as dead on arrival),
    and a pid-<PID> session identity, which makes every later process of the same session a
    stranger to the lock it just took.

.PARAMETER Handoff
    Path written by enter-code-lock's exit-4 message. Adopt those tickets instead of enqueuing
    fresh ones (S2403): without a session id the two processes are strangers to each other, and
    a fresh enqueue would put one intent on two tickets - the waiter then waits out the
    reservation window behind its own dead first ticket. Domains the handoff no longer covers
    are enqueued as usual; an unusable handoff behaves exactly like no handoff.

.EXIT CODES
    0 - granted: it is this session's turn, ticket left in place for the caller. With -Acquire
        the lock is already HELD by this session and the ticket is retired - the caller's
        enter-code-lock.ps1 re-run is then a re-entrant no-op, and the release is still owed.
    2 - timed out: nothing was acquired, ticket removed.
    3 - evicted: the ticket was dropped while waiting (session judged gone), ticket removed.
    4 - could not enqueue.

.EXAMPLE
    pwsh -NoProfile -File scripts/utils/wait-for-lock-turn.ps1 -Name Build -Reason "a.ps1 d"
#>
param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Reason,
    [int]$WaitTimeoutSeconds = 3600,
    [int]$PollSeconds = 5,
    [switch]$Acquire,
    [string]$Handoff = ''
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\agent-lock.ps1"

# S2109: a bare Build or Code is the whole set of its domains, a concrete domain is itself. The
# wait is granted only when this session is head EVERYWHERE in the set - see Test-AgentLockTurnSet.
try {
    $domains = @(Resolve-AgentLockDomains -Name $Name)
}
catch {
    Write-Error "wait-for-lock-turn: $($_.Exception.Message)" -ErrorAction Continue
    exit 4
}

# S2408: the same accessor the ticket was stamped with. A waiter that names itself differently
# writes a turn marker its own follow-up call cannot find, and the marker is the only grant signal
# the Rule 23 contract gives the caller.
$sessionId = Get-AgentSessionId
$tempDir = (Get-SzaPath 'locksDir')

# Both refusals degrade to a plain wait rather than stopping: the wait itself is still correct and
# still the caller's signal. The decision lives in agent-lock.ps1 so it can be tested without
# enqueuing anything in a live queue.
if ($Acquire) {
    $eligibility = Test-WaiterAcquireEligible -Domains $domains -SessionId $sessionId
    if (-not $eligibility.Eligible) {
        Write-Warning "wait-for-lock-turn: -Acquire ignored - $($eligibility.Reason) Waiting only."
        $Acquire = $false
    }
}
# One marker per domain: a caller that waited for two domains must be able to read the verdict of
# each, and a single combined file would make a granted set indistinguishable from a granted half.
$markerPaths = @{}
foreach ($domain in $domains) {
    $markerPaths[$domain] = Join-Path $tempDir "$($domain.ToUpper()).TURN-$sessionId.json"
}
$startedAt = Get-Date

function Write-TurnMarker {
    param(
        [Parameter(Mandatory)][string]$Outcome,
        [hashtable]$Tickets,
        [string]$Detail = ''
    )
    foreach ($domain in $domains) {
        $ticket = if ($Tickets -and $Tickets.ContainsKey($domain)) { $Tickets[$domain] } else { $null }
        $body = [ordered]@{
            outcome       = $Outcome
            lockType      = $domain
            domains       = $domains
            seq           = if ($ticket) { $ticket.seq } else { $null }
            sessionId     = $sessionId
            reason        = $Reason
            detail        = $Detail
            waitedSeconds = [int]((Get-Date) - $startedAt).TotalSeconds
            decidedAt     = (Get-Date).ToString('s')
        } | ConvertTo-Json -Compress
        # Write-then-rename so a reader never catches a half-written verdict.
        $staging = "$($markerPaths[$domain]).tmp-$PID"
        Set-Content -LiteralPath $staging -Value $body -Encoding utf8NoBOM
        Move-Item -LiteralPath $staging -Destination $markerPaths[$domain] -Force
    }
}

try {
    # S2403: adopt the tickets enter-code-lock left in the handoff before enqueuing anything.
    # In a runtime with no session id the adopting process is a stranger to the writer, which is
    # exactly why the handoff exists - the dedup inside New-AgentLockTicket cannot see across
    # the process boundary and would take a second place for the same intent.
    $tickets = @{}
    if ($Handoff) {
        $tickets = Read-AgentLockTicketHandoff -Path $Handoff -Domains $domains
        if (-not $tickets) { $tickets = @{} }
    }
    $missingDomains = @($domains | Where-Object { -not $tickets.ContainsKey($_) })
    if ($missingDomains.Count -gt 0) {
        $fresh = New-AgentLockTicketSet -Name $Name -Reason $Reason -Domains $missingDomains
        foreach ($d in $missingDomains) { $tickets[$d] = $fresh[$d] }
    }
}
catch {
    Write-Error "wait-for-lock-turn: could not enqueue for $Name - $($_.Exception.Message)" -ErrorAction Continue
    Write-TurnMarker -Outcome 'enqueue-failed' -Tickets $null -Detail $_.Exception.Message
    exit 4
}

foreach ($domain in $domains) { [void](Set-AgentTicketHeartbeat -Ticket $tickets[$domain]) }
$initial = Test-AgentLockTurnSet -Name $Name -Tickets $tickets
$seqText = ($domains | ForEach-Object { "$_ #$($tickets[$_].seq)" }) -join ', '
Write-Host "$Name queue: $seqText, position $($initial.Position). Marker: $($markerPaths[$domains[0]])" -ForegroundColor Cyan
if (-not $initial.IsMyTurn) {
    Write-Host "  Waiting - $($initial.Reason). Do lock-free work meanwhile; this process exits when it is your turn." -ForegroundColor DarkGray
}

$deadline = $startedAt.AddSeconds($WaitTimeoutSeconds)
$lastPosition = $initial.Position

while ($true) {
    foreach ($domain in $domains) {
        $queue = @(Get-AgentLockQueue -Name $domain)
        $stillQueued = @($queue | Where-Object { [int]$_.seq -eq [int]$tickets[$domain].seq }).Count -gt 0
        if (-not $stillQueued) {
            Write-Error "wait-for-lock-turn: ticket #$($tickets[$domain].seq) was evicted from the $domain queue while waiting." -ErrorAction Continue
            Write-TurnMarker -Outcome 'evicted' -Tickets $tickets -Detail "ticket no longer in the $domain queue"
            exit 3
        }
        # S1448: this poll IS the proof that the waiting session is alive. Without stamping it the
        # ticket's only liveness signal is the session transcript, which a correctly-waiting agent
        # does not write - and the ticket was evicted for it.
        [void](Set-AgentTicketHeartbeat -Ticket $tickets[$domain])
    }

    $turn = Test-AgentLockTurnSet -Name $Name -Tickets $tickets
    $lockBusy = $false
    $busyDomain = $null
    foreach ($domain in $domains) {
        $lock = Get-AgentLockStatus -Name $domain
        if ($lock.Exists -and -not $lock.Stale) { $lockBusy = $true; $busyDomain = $domain; break }
    }

    if ($turn.IsMyTurn -and -not $lockBusy) {
        $waited = [int]((Get-Date) - $startedAt).TotalSeconds
        if ($Acquire) {
            # Same process, same instant: this is the whole point of the flag. A lost race is not
            # a failure - somebody else's poll got there first, so keep waiting rather than
            # reporting a turn the caller cannot use.
            $taken = Enter-AgentLock -Name $Name -Reason $Reason -Domains $domains -Tickets $tickets
            if ($taken.Acquired) {
                Write-Host "$Name acquired in the waiter ($seqText, waited ${waited}s). Edit now; release with exit-code-lock.ps1 (or let post-change.ps1 do it)." -ForegroundColor Green
                Write-TurnMarker -Outcome 'acquired' -Tickets $tickets -Detail 'taken by the waiter'
                exit 0
            }
            Write-Host "$Name queue: turn arrived but the acquire lost the race - still waiting." -ForegroundColor DarkGray
        }
        else {
            Write-Host "$Name queue: your turn ($seqText, waited ${waited}s). Ticket left in place - pass it to Enter-AgentLock." -ForegroundColor Green
            Write-TurnMarker -Outcome 'granted' -Tickets $tickets -Detail $turn.Reason
            exit 0
        }
    }

    if ($turn.Position -ne $lastPosition -and $turn.Position -gt 0) {
        Write-Host "$Name queue: position $($turn.Position)." -ForegroundColor DarkGray
        $lastPosition = $turn.Position
    }

    if ((Get-Date) -ge $deadline) {
        foreach ($domain in $domains) {
            Remove-Item -LiteralPath $tickets[$domain].path -Force -ErrorAction SilentlyContinue
        }
        Write-Error "wait-for-lock-turn: still not this session's turn for $Name after ${WaitTimeoutSeconds}s - giving up, ticket removed." -ErrorAction Continue
        $timeoutDetail = if ($lockBusy) { "$busyDomain lock held" } else { $turn.Reason }
        Write-TurnMarker -Outcome 'timeout' -Tickets $tickets -Detail $timeoutDetail
        exit 2
    }

    Start-Sleep -Seconds $PollSeconds
}
