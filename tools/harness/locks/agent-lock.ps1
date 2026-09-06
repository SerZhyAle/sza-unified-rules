<#
.SYNOPSIS
    Cross-agent coordination locks: temp/BUILD.LOCK and temp/CODE.LOCK.

.DESCRIPTION
    Dot-source this file to get Enter-AgentLock / Exit-AgentLock / Get-AgentLockStatus /
    Enter-BuildLockOrExit. No top-level side effects other than resolving the repo root once.

    Two independent locks, deliberately different enforcement strength:
      - Build: a real OS process owns it for its whole lifetime, so staleness is judged by
        PID liveness (never by a guessed timeout while the process is actually alive - real
        builds legitimately run 10-25+ minutes). Enforced HARD - a leaf gradle-invoking script
        that can't acquire it must exit non-zero (see Enter-BuildLockOrExit).
      - Code: there is no persistent process to check (a Claude Code editing turn is not one
        continuous OS process - nothing runs between tool calls), so staleness is wall-clock
        only. Enforced SOFT by convention (CLAUDE.md rule + skills) - a build script that finds
        it fresh only warns, it never refuses, since nothing guarantees timely release.

    Lock file schema (single-line JSON, mirrors the existing .claude/scheduled_tasks.lock
    precedent):
      {"lockType":"Build","pid":12345,"procStart":<ticks>,"acquiredAt":<unix-ms>,
       "reason":"build-debug.PS1","host":"<COMPUTERNAME>"}

    S1432 adds a third state between free and held: QUEUED. Each lock has a queue directory
    temp/<NAME>.QUEUE holding one ticket file per waiter, named <seq:0000>__<sessionId>.json:
      {"schema":1,"seq":7,"lockType":"Build","sessionId":"<uuid>","host":"<COMPUTERNAME>",
       "pid":12345,"procStart":<ticks>,"reason":"a.ps1 d","enqueuedAt":<unix-ms>,
       "transcriptPath":"<path|null>"}
    A ticket's owner is an agent SESSION, not a process: the waiter that holds a place exits
    the moment the turn arrives (its exit IS the "your turn" signal), so process liveness can
    never on its own identify a live queue member. Liveness comes from the owning session's
    transcript write time - a live session appends to it every turn - with transcriptPath
    resolved once at enqueue time so a poll never rescans ~/.claude/projects. Timings per
    resource live in $Script:AgentLockTimings.

    S2577 qualifies that in one direction only, and only for a BUILD domain: there the waiting
    is done IN the enqueueing process (Enter-BuildLockOrExit waits in-process and removes its
    own tickets if the wait fails), so a dead pid proves nobody is left to spend that turn even
    while the session stays live. A dead process therefore evicts a build ticket; it never
    evicts a code one, where the enqueueing process is expected to be gone, and it never keeps
    alive a ticket the session-liveness rule already judged stale. See
    Test-AgentTicketProcessAlive and reason 1b in Remove-StaleAgentLockTickets.

.EXAMPLE
    . (Get-SzaHarnessScript 'locks/agent-lock.ps1')
    Enter-BuildLockOrExit -Reason "build-debug.PS1"
    try {
        # ... existing gradle-invoking body ...
    } finally {
        Exit-AgentLock -Name Build
    }

.NOTES
    Exit codes: 0 dot-sourced successfully; 2 invoked as a script instead of being dot-sourced
    (see the direct-invocation guard below - this file exposes no command-line interface).
#>

# S1505: this file is a library, not a CLI - it has no param() block and no verb dispatch, so
# `pwsh -File agent-lock.ps1 -Name Code -Action Release` used to bind nothing, define the
# functions, print nothing and exit 0. That reads as a successful release while the lock stays
# held; observed holding CODE.LOCK for 479s across a whole implementation phase. A wrong call
# must fail loudly rather than look like a working one, so refuse anything that is not a
# dot-source. Dot-sourcing reports InvocationName '.' even when the dot-sourcing script was
# itself started with `pwsh -File`, which is how every real consumer loads this file.
. (Join-Path $PSScriptRoot '..\_profile.ps1')
if ($MyInvocation.InvocationName -ne '.') {
    $guardMessage = @(
        "agent-lock.ps1 is a dot-source library and has no command-line interface.",
        "Running it as a script does nothing at all - it cannot acquire or release any lock.",
        "",
        "Release the code lock:   $(Get-SzaInvocation 'locks/exit-code-lock.ps1')",
        "Acquire the code lock:   $(Get-SzaInvocation 'locks/enter-code-lock.ps1') -Reason '<why>'",
        "Inspect a lock:          $(Get-SzaInvocation 'locks/lock-status.ps1') -Name <Build|Code> -Queue",
        "Clear a stuck lock:      $(Get-SzaInvocation 'locks/clear-agent-lock.ps1') -Name <Build|Code> -Force",
        "",
        "From a script, load the functions instead:",
        "    . `"$PSCommandPath`"",
        "    Exit-AgentLock -Name Code"
    ) -join [Environment]::NewLine
    Write-Error $guardMessage -ErrorAction Continue
    exit 2
}

# S2109: the domain table. A resource name is now a pair - type plus domain - and every accepted
# name, its canonical rank and the "bare name means every domain of that type" rule live there.
. "$PSScriptRoot\agent-lock-domains.ps1"
# S2372: the descriptive layer. Identity (agent-identity.ps1, through the store) and the chat
# store load here so every caller of the lock library can post and read without a second import;
# the store reads its windows from $Script:AgentLockTimings below, which is why it comes after
# the domains and never stands alone.
. (Get-SzaHarnessScript 'chat/agent-chat-store.ps1')

function Resolve-AgentLockRepoRoot {
    # Prefer git's common-dir parent so every linked worktree shares ONE temp/BUILD.LOCK and
    # temp/CODE.LOCK. Fallback to the current checkout root when git is unavailable.
    $repoCandidate = (Get-SzaProjectRoot)
    try {
        $gitCommonDir = (& git -C $repoCandidate rev-parse --path-format=absolute --git-common-dir 2>$null)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($gitCommonDir)) {
            $commonDir = "$gitCommonDir".Trim()
            if (Test-Path -LiteralPath $commonDir) {
                return Split-Path -Parent $commonDir
            }
        }
    }
    catch {
    }
    return $repoCandidate
}

# Captured once, at dot-source time, from THIS file's own location - not re-derived inside
# functions, where $PSScriptRoot would otherwise be ambiguous across a dot-sourcing boundary.
$Script:AgentLockRepoRoot = (Get-SzaProjectRoot)

# S2109: pre-split lock files already honoured in this process, so the notice is printed once per
# file rather than on every status read - a poll loop would otherwise bury its own output.
$Script:AgentLockLegacyNoticed = [System.Collections.Generic.HashSet[string]]::new()

# Codex exposes the same stable turn identity under a different environment name. Normalise it
# once for existing lock and spec scripts, whose child processes inherit this environment.
if ([string]::IsNullOrWhiteSpace($env:CLAUDE_CODE_SESSION_ID) -and
    -not [string]::IsNullOrWhiteSpace($env:CODEX_SESSION_ID)) {
    $env:CLAUDE_CODE_SESSION_ID = $env:CODEX_SESSION_ID
}

function Get-AgentLockPath {
    <#
    .SYNOPSIS
        Lock file for a coordination resource: temp/<NAME>.LOCK, upper-cased.
    .DESCRIPTION
        S2109: the name is a concrete domain (Code.Wear -> temp/CODE.WEAR.LOCK) or a bare type,
        which keeps pointing at today's temp/BUILD.LOCK and temp/CODE.LOCK. Research artifact 05
        established this function and Get-AgentLockQueueDir as the single point of truth for
        every coordination path on disk, which is why the domain dimension reaches the whole
        file set from here and nowhere else.
    #>
    param([Parameter(Mandatory)][string]$Name)
    Assert-AgentLockDomainName -Name $Name | Out-Null
    $tempDir = (Get-SzaPath 'locksDir')
    if (-not (Test-Path -LiteralPath $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }
    return Join-Path $tempDir "$($Name.ToUpper()).LOCK"
}

# Per-resource timings (S1432). Build keeps the pre-existing ceilings: a real build legitimately
# runs 10-25+ minutes, and a session waiting on one writes nothing to its transcript meanwhile.
# Code is deliberately shorter - an edit is a short burst of writes, not a long-running process,
# so a code ticket that has sat for 20 minutes is far more likely abandoned than working.
#
# S2098: TicketCeilingMinutes is declared for Build and Code below but read by NO queue consumer -
# only ticket-lease.ps1 and device-lease.ps1 apply the field. Queue eviction
# (Remove-StaleAgentLockTickets) judges the OWNER, never the ticket's age. That is deliberate, not
# an oversight: a legitimate wait behind one long build, or behind several queued builds, outlasts
# both numbers, so applying them would evict a session waiting exactly as the contract demands.
# The remedy for a ticket whose owner is alive but whose intent was dropped is therefore explicit,
# not a timer - scripts/utils/withdraw-lock-ticket.ps1. Do not wire these two values into the
# queue sweep without redoing that reasoning; an unannounced non-application reads as a working
# safety net, which is how the 2026-08-27 stall went unlooked-for.
#
# S2109: each concrete domain carries its own record, inheriting the values of its bare type
# unchanged - strategic section 5.1 pillar A makes ownership, eviction and head-of-queue
# reservation properties of the mechanism, not of the domain, and every one of those rules is
# read out of this table alone. A domain with different numbers would be a second policy.
#
# S2582: StallMinutes is the age at which a HELD lock with a queue behind it becomes worth a
# warning, and it is a separate number from LockStaleMinutes because the two answer different
# questions. For a code domain they coincide at 10 - one below its SessionStaleMinutes of 15, so
# the warning arrives before the lock is even reclaimable, which is S2413's whole point and stays
# bit-identical here. For a build domain LockStaleMinutes is an hour of wall clock, the outer
# bound on a legitimately long build, and warning at that age arrives after the damage: measured
# 2026-09-05, thirteen sessions had queued behind one hung holder by minute 51. The 25 is the
# threshold the external reaper already runs on, raised there from 12 because engine startup plus
# a cold configuration phase routinely exceeds 12 and the signal must not fire on those.
# Lease-shaped records keep 0 alongside their LockStaleMinutes: no lock file, no queue, nothing
# to stall.
$Script:AgentLockTimings = @{
    Build = [pscustomobject]@{
        LockStaleMinutes    = 60
        TicketCeilingMinutes = 60
        ReservationMinutes   = 5
        SessionStaleMinutes  = 45
        StallMinutes         = 25
    }
    'Build.Phone' = [pscustomobject]@{
        LockStaleMinutes    = 60
        TicketCeilingMinutes = 60
        ReservationMinutes   = 5
        SessionStaleMinutes  = 45
        StallMinutes         = 25
    }
    'Build.Wear' = [pscustomobject]@{
        LockStaleMinutes    = 60
        TicketCeilingMinutes = 60
        ReservationMinutes   = 5
        SessionStaleMinutes  = 45
        StallMinutes         = 25
    }
    Code  = [pscustomobject]@{
        LockStaleMinutes    = 10
        TicketCeilingMinutes = 20
        ReservationMinutes   = 1
        SessionStaleMinutes  = 15
        StallMinutes         = 10
    }
    'Code.Phone' = [pscustomobject]@{
        LockStaleMinutes    = 10
        TicketCeilingMinutes = 20
        ReservationMinutes   = 1
        SessionStaleMinutes  = 15
        StallMinutes         = 10
    }
    'Code.Wear' = [pscustomobject]@{
        LockStaleMinutes    = 10
        TicketCeilingMinutes = 20
        ReservationMinutes   = 1
        SessionStaleMinutes  = 15
        StallMinutes         = 10
    }
    'Code.Scripts' = [pscustomobject]@{
        LockStaleMinutes    = 10
        TicketCeilingMinutes = 20
        ReservationMinutes   = 1
        SessionStaleMinutes  = 15
        StallMinutes         = 10
    }
    # S1437: a spec-ticket lease has no lock file and no queue, so LockStaleMinutes and
    # ReservationMinutes do not apply and stay 0. SessionStaleMinutes matches the round-state
    # window rather than Code's, because a lease spans a whole ticket - research, spec, edits,
    # a release-scale build - and a session waiting on one writes nothing for tens of minutes.
    # Expiring it on Code's 15 would hand a working session's ticket to a sibling mid-edit.
    SpecTicket = [pscustomobject]@{
        LockStaleMinutes    = 0
        TicketCeilingMinutes = 480
        ReservationMinutes   = 0
        SessionStaleMinutes  = 45
        StallMinutes         = 0
    }
    # S1926: a device lease has the same shape as a spec-ticket lease - no lock file, no queue -
    # so LockStaleMinutes and ReservationMinutes stay 0 for the same reason.
    #
    # SessionStaleMinutes matches SpecTicket rather than Code: a session driving a device scenario
    # spends long stretches building and installing an APK without writing anything, and Code's
    # 15-minute window would evict it mid-install and hand its device to a sibling.
    #
    # TicketCeilingMinutes is far shorter than SpecTicket's 480 because the resource is held for a
    # scenario, not for a ticket's whole life - research, spec writing and gates need no device, so
    # a lease still standing after two hours is an abandoned one, not a slow one.
    Device = [pscustomobject]@{
        LockStaleMinutes    = 0
        TicketCeilingMinutes = 120
        ReservationMinutes   = 0
        SessionStaleMinutes  = 45
        StallMinutes         = 0
    }
}

function Get-AgentLockTimings {
    <#
    .SYNOPSIS
        Timings for one lock. Single source for every minute value in this file.
    .DESCRIPTION
        S2109: accepts a concrete domain alongside the bare types; the two lease names, which
        have no lock file and no queue, keep their own records.
    #>
    param([Parameter(Mandatory)][string]$Name)
    if (-not $Script:AgentLockTimings.ContainsKey($Name)) {
        $accepted = ($Script:AgentLockTimings.Keys | Sort-Object) -join ', '
        throw "Unknown coordination resource name '$Name'. Accepted values: $accepted."
    }
    return $Script:AgentLockTimings[$Name]
}

function Get-AgentLockQueueDir {
    <#
    .SYNOPSIS
        Queue directory for a lock, created on demand. Shares the repo root with the lock file
        itself, so every linked worktree orders itself through ONE queue.

        S2109: keyed off the concrete domain, so Code.Wear queues in temp/CODE.WEAR.QUEUE while
        a bare Code still names today's temp/CODE.QUEUE.
    #>
    param([Parameter(Mandatory)][string]$Name)
    Assert-AgentLockDomainName -Name $Name | Out-Null
    $queueDir = Join-Path (Get-SzaPath 'locksDir') "$($Name.ToUpper()).QUEUE"
    if (-not (Test-Path -LiteralPath $queueDir)) {
        New-Item -ItemType Directory -Path $queueDir -Force | Out-Null
    }
    return $queueDir
}

function Get-AgentSessionId {
    <#
    .SYNOPSIS
        Identity of the calling agent session, never empty.
    .DESCRIPTION
        No session id in the environment - a plain shell, a cron run, a nested tool - falls back
        to a process-scoped identity so the caller is still distinguishable. Liveness for such an
        identity degrades to its wall-clock ceiling, which is why this returns the fallback rather
        than $null: a caller that must name someone is better served by "pid-1234" than by blank.

        Added by S1596 as the shared accessor for an idiom that had been inlined four times.
        Existing call sites are left as they are - converting them is a separate change.
    #>
    # S2372: the chain itself lives in agent-identity.ps1 (FMS_AGENT_ID, then the session id, then
    # pid-<PID>), so the lock, the lease, the queue and the chat name one agent the same way.
    return Get-AgentIdentityId
}

function Get-AgentSessionTranscriptPath {
    <#
    .SYNOPSIS
        Full path of an agent session's transcript file, or $null when it cannot be located.
    .DESCRIPTION
        Resolved ONCE, at enqueue time, and stored in the ticket. A queue poll runs every few
        seconds and must read small files only (S1432 strategic 3.2) - rescanning the whole
        ~/.claude/projects tree on each poll would break that.
    #>
    param([string]$SessionId)

    if ([string]::IsNullOrWhiteSpace($SessionId)) { return $null }
    $projectsRoot = Join-Path $env:USERPROFILE '.claude\projects'
    if (-not (Test-Path -LiteralPath $projectsRoot)) { return $null }
    $match = Get-ChildItem -Path $projectsRoot -Recurse -Filter "$SessionId.jsonl" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($match) { return $match.FullName }
    return $null
}

function Get-AgentSessionTranscriptLastWrite {
    <#
    .SYNOPSIS
        Newest write time of a session's transcript, counting its subagents' transcripts too.
        $null when neither exists.
    .DESCRIPTION
        S2408 decision 7. A session that hands its work to a subagent writes nothing to
        <session>.jsonl for the whole run, while <session>/subagents/*.jsonl is written
        continuously - measured 2026-09-03, a six-minute gap between the two on a session that was
        editing the whole time, and on 2026-09-02 an eleven-minute one that lost its Code.Scripts
        lock to the ten-minute staleness window while its owner was mid-edit.

        Both the lock library's liveness and the lease's quiet-time reading call THIS function, so
        the two cannot judge different sets of files and disagree about one agent (S1621).

        Only the one session's own directory is enumerated, never the whole projects tree: this is
        called from the queue poll, which must read small (S1432 strategic 3.2). Measured warm at
        1.7 ms against a live session directory.
    #>
    param([string]$TranscriptPath)

    if ([string]::IsNullOrWhiteSpace($TranscriptPath)) { return $null }
    $marks = @()
    if (Test-Path -LiteralPath $TranscriptPath) {
        try { $marks += (Get-Item -LiteralPath $TranscriptPath).LastWriteTime } catch { }
    }
    $dir = Split-Path -Parent $TranscriptPath
    $base = [System.IO.Path]::GetFileNameWithoutExtension($TranscriptPath)
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not [string]::IsNullOrWhiteSpace($base)) {
        $subagentDir = Join-Path (Join-Path $dir $base) 'subagents'
        if (Test-Path -LiteralPath $subagentDir) {
            try {
                $newest = Get-ChildItem -LiteralPath $subagentDir -Filter '*.jsonl' -Recurse -File -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($newest) { $marks += $newest.LastWriteTime }
            }
            catch { }
        }
    }
    if ($marks.Count -eq 0) { return $null }
    return ($marks | Sort-Object -Descending | Select-Object -First 1)
}

function New-AgentLockTicket {
    <#
    .SYNOPSIS
        Take a place in the queue for a lock. Returns the ticket (with its file path attached).
    .DESCRIPTION
        The sequence number is claimed with FileMode.CreateNew - the same atomic test-and-set
        Enter-AgentLock uses - so two sessions enqueueing at the same instant cannot end up
        holding the same number. Losing the race is not an error: recompute and retry.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Reason,
        # Take a second place in the same queue anyway. Only a test harness simulating several
        # independent agents from one session needs this.
        [switch]$ForceNew
    )

    $queueDir = Get-AgentLockQueueDir -Name $Name
    # S2408: through the shared accessor, never the raw variable with a private fallback. A ticket
    # stamped pid-<PID> beside a lock file of the same acquisition stamped host-<..> is one holder
    # recorded as two owners - the S2371 divergence, reintroduced one level down.
    $sessionId = Get-AgentSessionId
    $transcriptPath = Get-AgentSessionTranscriptPath -SessionId $env:CLAUDE_CODE_SESSION_ID

    # One session, one place. A skill that asks twice (checked, went off to do lock-free work,
    # came back and asked again) must keep the place it already earned, not take a second one -
    # observed live: a sibling session held two consecutive tickets in the Code queue, which
    # both inflates the queue and lets one agent occupy two turns.
    if (-not $ForceNew) {
        $existing = @(Get-AgentLockQueue -Name $Name | Where-Object { [string]$_.sessionId -eq $sessionId })
        if ($existing.Count -gt 0) {
            # S2577: the place is kept, the PROCESS carrying it is stamped afresh. A session whose
            # first build was killed inherits the killed process's pid here, and reason 1b below
            # judges a build ticket by exactly that field - so without this the re-run's own live
            # wait would be swept by the next sibling that read the queue. seq and enqueuedAt are
            # untouched: the ticket keeps the position and the age it earned.
            return (Set-AgentTicketHeartbeat -Ticket $existing[0])
        }
    }

    # Read once, outside the retry loop: a lost CreateNew race re-runs the loop, and the start
    # time of this process cannot change between attempts. 0 means "unreadable", which
    # Test-AgentTicketProcessAlive treats as a ticket with no start stamp at all.
    $procStartTicks = 0
    try { $procStartTicks = (Get-Process -Id $PID).StartTime.Ticks } catch { $procStartTicks = 0 }

    for ($attempt = 1; $attempt -le 50; $attempt++) {
        $highest = 0
        foreach ($file in @(Get-ChildItem -LiteralPath $queueDir -Filter '*.json' -ErrorAction SilentlyContinue)) {
            if ($file.Name -match '^(\d+)__') {
                $parsed = [int]$Matches[1]
                if ($parsed -gt $highest) { $highest = $parsed }
            }
        }
        $seq = $highest + 1
        $path = Join-Path $queueDir ('{0:0000}__{1}.json' -f $seq, $sessionId)

        try {
            $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
        }
        catch [System.IO.IOException] {
            continue
        }

        $ticket = [ordered]@{
            schema         = 1
            seq            = $seq
            lockType       = $Name
            sessionId      = $sessionId
            host           = $env:COMPUTERNAME
            pid            = $PID
            # S2577: stamped exactly as the lock file stamps its holder. A bare pid cannot
            # survive pid reuse, and reason 1b judges a build ticket by this pair.
            procStart      = $procStartTicks
            reason         = $Reason
            enqueuedAt     = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            transcriptPath = $transcriptPath
        }
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes(($ticket | ConvertTo-Json -Compress))
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush()
        }
        finally {
            $stream.Close()
        }

        $issued = [pscustomobject]$ticket
        $issued | Add-Member -NotePropertyName 'path' -NotePropertyValue $path -Force
        return $issued
    }

    throw "agent-lock: could not claim a $Name queue sequence number after 50 attempts"
}

function Get-AgentTicketLiveness {
    <#
    .SYNOPSIS
        Verdict on a ticket's owner: self | foreign-live | foreign-stale | undetermined.
    .DESCRIPTION
        Same vocabulary as scripts/spec_catalog/spec-next-session.ps1, and for the same reason:
        the owner is a session, not a process, so the closest thing to a heartbeat is the write
        time of that session's transcript. Falls back to the ticket's own enqueue time when the
        transcript is unreachable (different machine, pruned history).

        'undetermined' means WE have no session id, so "mine" and "theirs" are indistinguishable -
        it must never be treated as grounds for eviction.

        S1448 - liveness signal precedence, strongest first, with S2408 adding the first entry:
          0. the owner's own process, when the id names one (host- or pid-). One-directional:
             it may only answer 'foreign-live', never 'foreign-stale';
          1. the ticket's own lastSeenAt heartbeat, written by the polling waiter that owns it;
          2. the owning session's transcript write time, counting the subagent subtree;
          3. the ticket's enqueuedAt, when none of the above is readable.
        The heartbeat leads the clock-based signals because a session that waits by the contract -
        background waiter plus lock-free work - produces no transcript writes, and was therefore
        being evicted for obeying the rules. The process check leads all of them because it is the
        only signal that observes the owner rather than a trace it left.
    #>
    param(
        [Parameter(Mandatory)]$Ticket,
        # Mandatory on purpose: the threshold belongs to the resource, and every caller reads it
        # from $Script:AgentLockTimings - a default here would be a second source of truth.
        [Parameter(Mandatory)][int]$StaleMinutes
    )

    $owner = if ($Ticket) { [string]$Ticket.sessionId } else { $null }
    if ([string]::IsNullOrWhiteSpace($owner)) { return 'foreign-stale' }

    # S2371: the caller identity goes through the same accessor the writers use, so a
    # pid-fallback caller recognises its own lock and tickets as 'self'. The raw env read
    # collapsed every unnamed caller to 'undetermined' before the self comparison, which both
    # hid a caller's own hold from it (judged stale by wall clock while alive) and let dead
    # pid-owned tickets survive every liveness sweep.
    $sessionId = Get-AgentSessionId
    if ([string]::IsNullOrWhiteSpace($sessionId)) { return 'undetermined' }
    if ($owner -eq $sessionId) { return 'self' }

    # S2408 ADR-3: the owner's own process, when the id names one, is the strongest signal and the
    # only one-directional one - it can turn this verdict LIVE but never stale, so it adds no
    # eviction that did not exist before. A host- id carries the start ticks; a pid- id carries
    # nothing, so the record's own write time bounds it against a recycled pid.
    $writtenAt = [datetime]::MinValue
    if ($Ticket.PSObject.Properties.Name -contains 'enqueuedAt' -and $Ticket.enqueuedAt) {
        $writtenAt = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$Ticket.enqueuedAt).LocalDateTime
    }
    if (Test-AgentIdentityProcessAlive -Id $owner -NotStartedAfter $writtenAt) { return 'foreign-live' }

    $lastSeen = $null
    if ($Ticket.PSObject.Properties.Name -contains 'lastSeenAt' -and $Ticket.lastSeenAt) {
        $lastSeen = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$Ticket.lastSeenAt).LocalDateTime
    }
    $transcript = [string]$Ticket.transcriptPath
    # S2408: the subagent subtree counts as the session writing. See
    # Get-AgentSessionTranscriptLastWrite.
    if ($null -eq $lastSeen -and -not [string]::IsNullOrWhiteSpace($transcript)) {
        $lastSeen = Get-AgentSessionTranscriptLastWrite -TranscriptPath $transcript
    }
    # S2372 ADR-7: the owner's newest chat message is the fourth signal - after the heartbeat and
    # the transcript, before the enqueue time - so a runtime with no transcript is judged by what
    # it said rather than by the clock alone. It can only extend a life, never shorten one.
    if ($null -eq $lastSeen) {
        $chatSeen = $null
        try { $chatSeen = Get-AgentChatLastSeen -AgentId $owner } catch { $chatSeen = $null }
        if ($null -ne $chatSeen) { $lastSeen = $chatSeen.ToLocalTime() }
    }
    if ($null -eq $lastSeen -and $Ticket.enqueuedAt) {
        $lastSeen = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$Ticket.enqueuedAt).LocalDateTime
    }
    if ($null -eq $lastSeen) { return 'foreign-stale' }

    $ageMinutes = ((Get-Date) - $lastSeen).TotalMinutes
    if ($ageMinutes -le $StaleMinutes) { return 'foreign-live' }
    return 'foreign-stale'
}

function Test-AgentTicketProcessAlive {
    <#
    .SYNOPSIS
        Is the process that took this ticket still running? True on every doubt.
    .DESCRIPTION
        S2577. Get-AgentTicketLiveness judges the owning SESSION, which is right for a code
        domain - there enter-code-lock.ps1 enqueues and exits 4 at once, and the waiting is done
        by a different process entirely, so a dead pid is the normal state of a perfectly live
        ticket. It is wrong for a build domain: Enter-BuildLockOrExit enqueues and then waits IN
        THAT PROCESS, removing its own tickets when the wait fails, so a live build ticket always
        has a live process behind it. A dead one means nobody is left to spend that turn - and
        until this existed nothing removed it, because the session stayed live: the ticket rode to
        the head of the queue and held a reservation it could never take. Measured 2026-09-05,
        three such tickets sat on Build.Phone behind one hung holder and were deleted by hand,
        no other path existing.

        Deliberately NOT Test-AgentIdentityProcessAlive. That one judges an identity STRING and
        answers false whenever StartTime cannot be read (another user, elevation) - harmless
        there, because its answer may only keep a record alive, never evict one. Here the same
        false is a deletion, so every doubt has to read as ALIVE instead: no pid field, an
        unreadable StartTime, a pre-S2577 ticket carrying no procStart whose process started
        before it was written.

        Two guards against a recycled pid, mirroring Get-AgentLockStatus's build branch. procStart
        must match the running process exactly. A ticket written before S2577 carries none, so its
        enqueue time bounds it instead - a process that started after the ticket was written
        cannot be the process that wrote it. The one-minute grace covers clock granularity
        between the two writes, not a real gap.
    #>
    param([Parameter(Mandatory)]$Ticket)

    if (-not $Ticket) { return $true }
    if ($Ticket.PSObject.Properties.Name -notcontains 'pid') { return $true }
    $ticketPid = 0
    try { $ticketPid = [int]$Ticket.pid } catch { $ticketPid = 0 }
    if ($ticketPid -le 0) { return $true }

    $process = Get-Process -Id $ticketPid -ErrorAction SilentlyContinue
    if (-not $process) { return $false }

    $started = $null
    try { $started = $process.StartTime } catch { $started = $null }
    if ($null -eq $started) { return $true }

    $expectedTicks = 0
    if ($Ticket.PSObject.Properties.Name -contains 'procStart' -and $Ticket.procStart) {
        $expectedTicks = [int64]$Ticket.procStart
    }
    if ($expectedTicks -gt 0) { return ([int64]$started.Ticks -eq $expectedTicks) }

    if ($Ticket.PSObject.Properties.Name -contains 'enqueuedAt' -and $Ticket.enqueuedAt) {
        $writtenAt = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$Ticket.enqueuedAt).LocalDateTime
        if ($started -gt $writtenAt.AddMinutes(1)) { return $false }
    }
    return $true
}

function Get-AgentOwnerQuietMinutes {
    <#
    .SYNOPSIS
        Minutes since the freshest sign of life from a session, or $null when no mark is readable.
    .DESCRIPTION
        S2413. The marks are exactly the ones Get-AgentTicketLiveness already judges by - the
        transcript write counting the subagent subtree, the record's own heartbeat, the newest chat
        line - so a signal built on this number and the eviction built on that verdict can never
        disagree about the same owner (S1621). No fourth source is added here.

        It reports a number and judges nothing: no threshold is read, because a threshold belongs to
        the resource and every caller already takes its own from $Script:AgentLockTimings.

        The transcript path is resolved only when the caller has none - resolving it walks the whole
        projects tree, while every record that matters stored the path at enqueue time.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$SessionId,
        [string]$TranscriptPath,
        # Epoch milliseconds, as a ticket or a lease stores its heartbeat.
        [object]$LastSeenAt
    )

    if ([string]::IsNullOrWhiteSpace($SessionId)) { return $null }

    if ([string]::IsNullOrWhiteSpace($TranscriptPath)) {
        try { $TranscriptPath = Get-AgentSessionTranscriptPath -SessionId $SessionId } catch { $TranscriptPath = $null }
    }

    $marks = @()
    if (-not [string]::IsNullOrWhiteSpace($TranscriptPath)) {
        try {
            $write = Get-AgentSessionTranscriptLastWrite -TranscriptPath $TranscriptPath
            if ($null -ne $write) { $marks += $write }
        }
        catch { }
    }
    if ($null -ne $LastSeenAt -and "$LastSeenAt" -ne '') {
        try { $marks += [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$LastSeenAt).LocalDateTime } catch { }
    }
    try {
        $chatSeen = Get-AgentChatLastSeen -AgentId $SessionId
        if ($null -ne $chatSeen) { $marks += $chatSeen.ToLocalTime() }
    }
    catch { }

    if ($marks.Count -eq 0) { return $null }
    $freshest = @($marks | Sort-Object -Descending)[0]
    return [math]::Round(((Get-Date) - $freshest).TotalMinutes, 1)
}

# S2582. Rates, not per-window constants: the same numbers are run by the external reaper over a
# 6-second window, and expressing them per second is what keeps the signal and the reaper from
# reaching opposite verdicts about one holder just because they sampled for different lengths.
# 0.067 CPU-seconds per second is the reaper's 0.4-per-6s idle floor; 0.5 is its busy floor, half
# a core. The window is 3 seconds rather than the reaper's 6 because this runs inside an operator's
# status query and a monitor refresh, and it is only ever paid in the already-broken state.
$Script:AgentStallSampleSeconds = 3
$Script:AgentStallIdleCpuRate   = 0.067
$Script:AgentStallBusyCpuRate   = 0.5

function Get-AgentBuildEngineMatch {
    <#
    .SYNOPSIS
        The project's build-engine vocabulary from locks.buildEngine, or $null when it declares none.
    .DESCRIPTION
        S2582. The mechanism ships with the canon and the vocabulary belongs to the project, so the
        process names and command-line pattern that identify a working build engine are read from
        the profile and never written here. A project that declares none gets no build stall verdict
        at all - deliberately fail-closed, because half the predicate is unmeasurable without it and
        the half that remains is the one measured to be wrong on its own.
    #>
    $node = $null
    try { $node = Get-SzaProfileValue 'locks.buildEngine' } catch { return $null }
    if ($null -eq $node) { return $null }
    $names = @()
    if (Test-SzaHasProperty -Object $node -Name 'processNames') { $names = @($node.processNames) }
    $busy = if (Test-SzaHasProperty -Object $node -Name 'busyMatch') { [string]$node.busyMatch } else { '' }
    $exclude = if (Test-SzaHasProperty -Object $node -Name 'busyExclude') { [string]$node.busyExclude } else { '' }
    if ($names.Count -eq 0 -or [string]::IsNullOrWhiteSpace($busy)) { return $null }
    return [pscustomobject]@{ ProcessNames = $names; BusyMatch = $busy; BusyExclude = $exclude }
}

function Measure-AgentBuildActivity {
    <#
    .SYNOPSIS
        CPU burned by a build lock holder's process tree and by the build engine, over ONE window.
        $null when the project declares no build engine.
    .DESCRIPTION
        S2582. Two sets, one Start-Sleep. Both halves are needed and neither is sufficient:

          - The holder's tree, breadth first, because a build is a wrapper plus a launcher client
            plus workers, and judging the wrapper alone reports idle for a tree that is compiling.
          - Every build-engine process on the machine, because the engine DETACHES: its parent is
            gone by design, so it is never a descendant of the wrapper holding the lock, and the
            wrapper legitimately sits at zero while the engine compiles at full speed elsewhere in
            the process table. Measured 2026-09-05: a reaper that judged the tree alone killed 24
            live builds in 105 minutes, always exactly at its threshold, while one build in that
            window reached success.

        One window rather than two, so a domain costs one sleep and both halves describe the same
        stretch of time. Read only - it starts nothing, stops nothing and writes nothing.
    #>
    param(
        [Parameter(Mandatory)][int]$HolderPid,
        [int]$SampleSeconds = 0
    )

    $engine = Get-AgentBuildEngineMatch
    if ($null -eq $engine) { return $null }
    if ($SampleSeconds -le 0) { $SampleSeconds = $Script:AgentStallSampleSeconds }

    $all = @()
    try { $all = @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, Name, CommandLine -ErrorAction Stop) }
    catch { return $null }

    $byParent = @{}
    foreach ($p in $all) {
        $key = [int]$p.ParentProcessId
        if (-not $byParent.ContainsKey($key)) { $byParent[$key] = @() }
        $byParent[$key] += [int]$p.ProcessId
    }
    $tree = [System.Collections.Generic.HashSet[int]]::new()
    $pending = [System.Collections.Generic.Queue[int]]::new()
    $pending.Enqueue($HolderPid)
    while ($pending.Count -gt 0) {
        $current = $pending.Dequeue()
        if (-not $tree.Add($current)) { continue }
        if ($byParent.ContainsKey($current)) {
            foreach ($child in $byParent[$current]) { $pending.Enqueue($child) }
        }
    }
    # The holder pid itself is in the set even when the process is already gone; a dead pid simply
    # contributes no CPU below, which is the right answer rather than a special case.
    $engineIds = @()
    foreach ($p in $all) {
        if ([string]$p.Name -notin $engine.ProcessNames) { continue }
        $cmd = [string]$p.CommandLine
        if ([string]::IsNullOrWhiteSpace($cmd)) { continue }
        if ($cmd -notmatch $engine.BusyMatch) { continue }
        if ($engine.BusyExclude -and $cmd -match $engine.BusyExclude) { continue }
        $engineIds += [int]$p.ProcessId
    }

    $sample = {
        param([int[]]$Ids)
        $out = @{}
        foreach ($id in $Ids) {
            $proc = Get-Process -Id $id -ErrorAction SilentlyContinue
            if ($proc -and $null -ne $proc.CPU) { $out[$id] = [double]$proc.CPU }
        }
        return $out
    }
    $treeIds = @($tree)
    $treeBefore = & $sample $treeIds
    $engineBefore = & $sample $engineIds
    Start-Sleep -Seconds $SampleSeconds
    $treeAfter = & $sample $treeIds
    $engineAfter = & $sample $engineIds

    $delta = {
        param([hashtable]$Before, [hashtable]$After)
        $sum = 0.0
        foreach ($id in $Before.Keys) {
            if ($After.ContainsKey($id)) { $sum += ($After[$id] - $Before[$id]) }
        }
        return [math]::Round($sum, 2)
    }

    return [pscustomobject][ordered]@{
        sampleSeconds    = $SampleSeconds
        treeCount        = $treeIds.Count
        treeCpuSeconds   = (& $delta $treeBefore $treeAfter)
        engineCount      = $engineIds.Count
        engineCpuSeconds = (& $delta $engineBefore $engineAfter)
    }
}

function Get-AgentLockStall {
    <#
    .SYNOPSIS
        The stalled-holder verdict for one domain, or $null when the domain is not stalled.
    .DESCRIPTION
        S2413. Held, a queue behind it, and a holder that is not making progress. All the halves
        already existed and were read by four different readers; none of them joined them, so a
        session that stopped moving at 00:19 while holding three code domains was noticed at 00:29
        by the owner's eyes and by nothing else.

        Read-only and decision-free: nothing here evicts, sweeps or writes, and no lock, queue or
        lease branches on the result. It names what a human was left to spot.

        TWO RULES, because the two resource types fail differently and neither test transfers.

          - `quiet-owner`, code domains (S2413). The owner is quiet for longer than the domain's
            StallMinutes, measured exactly as eviction measures it. On a code domain an agent
            between edits writes, so silence really is the absence of work.
          - `no-cpu`, build domains (S2582). The holder is past StallMinutes, its process is alive,
            its whole tree burns no CPU across a sampling window AND no build-engine process on the
            machine burns any either. Owner silence is deliberately NOT the test here: a session
            waiting on its own foreground build legitimately writes nothing for the build's whole
            length, so that rule would fire on every healthy build. The engine half is equally
            mandatory - the engine detaches and is never a descendant of the wrapper, so a healthy
            build's tree also reads idle; a reaper judging the tree alone killed 24 live builds in
            105 minutes (measured 2026-09-05).

        Exclusions common to both rules, each of which would otherwise make the signal noise:
          - an empty queue, where a stuck holder blocks nobody;
          - the holder's own leftover ticket, which is the S1448 starvation shape rather than a
            second session waiting;
          - a dead build holder, which already makes the lock stale so the next claimant reclaims
            it unaided - there is nothing for a human to do about it.

        A live holder process does NOT clear the verdict - it is reported beside it, because
        "hung" and "gone" cost the queue exactly the same and only differ in what to do next. On a
        build domain that is the entire point: `processAlive: True` was the line that made a
        51-minute hang look healthy.

        The threshold is the domain's own StallMinutes: 10 for code, below its SessionStaleMinutes
        of 15, so the warning arrives before the lock is even reclaimable; 25 for build, far below
        its hour of wall clock, because by minute 51 thirteen sessions had queued.

        The sample is paid LAST, after four free conditions, so a healthy build never pays for it.

        A caller that has already read the lock file passes the holder facts in; with none supplied
        the lock is read here.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$HolderSessionId,
        [string]$HolderTranscriptPath,
        [object]$HeldMinutes,
        # The build rule judges the holder process, so a caller that read the lock passes its pid.
        [int]$HolderPid = 0,
        # Queue tickets already read, carrying either waitedMinutes or enqueuedAt.
        [object[]]$Queue,
        [int]$SampleSeconds = 0
    )

    $resolved = @()
    try { $resolved = @(Resolve-AgentLockDomains -Name $Name) } catch { return $null }
    if ($resolved.Count -ne 1) { return $null }
    $domain = [string]$resolved[0]
    $isBuild = $domain -like 'Build*'

    $sessionId = $HolderSessionId
    $transcriptPath = $HolderTranscriptPath
    $heldMinutes = $HeldMinutes
    $holderPid = $HolderPid
    $needStatus = if ($isBuild) { $holderPid -le 0 -or $null -eq $heldMinutes }
                  else { [string]::IsNullOrWhiteSpace($sessionId) }
    if ($needStatus) {
        $status = $null
        try { $status = Get-AgentLockStatus -Name $domain } catch { return $null }
        if (-not $status.Exists -or $status.Stale) { return $null }
        $sessionId = [string]$status.SessionId
        $transcriptPath = [string]$status.TranscriptPath
        $heldMinutes = [math]::Round(([double]$status.AgeSeconds) / 60.0, 1)
        if ($null -ne $status.Pid) { $holderPid = [int]$status.Pid }
    }
    if ($isBuild) {
        if ($holderPid -le 0) { return $null }
        if ([string]::IsNullOrWhiteSpace($sessionId)) {
            # Get-AgentLockStatus reports pid and not session for a build lock: it judges that type
            # by process liveness, and filling SessionId there would change how the head-of-queue
            # reservation and the self-ownership check read every build lock. The holder stamps the
            # id in the file all the same, and the verdict wants it only to name the holder and to
            # drop the holder's own leftover ticket below.
            try {
                $rawLock = Get-Content -LiteralPath (Get-AgentLockPath -Name $domain) -Raw -ErrorAction Stop |
                    ConvertFrom-Json -ErrorAction Stop
                $lockFields = $rawLock.PSObject.Properties.Name
                if ($lockFields -contains 'sessionId') { $sessionId = [string]$rawLock.sessionId }
                if ($lockFields -contains 'transcriptPath') { $transcriptPath = [string]$rawLock.transcriptPath }
            }
            catch { }
        }
    }
    elseif ([string]::IsNullOrWhiteSpace($sessionId)) { return $null }

    # ContainsKey, not a null test: a caller that read the queue and found it empty is stating a
    # fact, and $null -ne @() would silently re-read the directory and answer a different question.
    $tickets = if ($PSBoundParameters.ContainsKey('Queue')) { @($Queue) } else { @(Get-AgentLockQueue -Name $domain) }
    $waits = @()
    foreach ($ticket in $tickets) {
        if (-not [string]::IsNullOrWhiteSpace($sessionId) -and [string]$ticket.sessionId -eq $sessionId) { continue }
        $waited = $null
        $fields = $ticket.PSObject.Properties.Name
        if ($fields -contains 'waitedMinutes' -and $null -ne $ticket.waitedMinutes) {
            $waited = [double]$ticket.waitedMinutes
        }
        elseif ($fields -contains 'enqueuedAt' -and $ticket.enqueuedAt) {
            $waited = ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [int64]$ticket.enqueuedAt) / 60000.0
        }
        $waits += [double]$(if ($null -eq $waited) { 0 } else { $waited })
    }
    if ($waits.Count -eq 0) { return $null }

    $threshold = (Get-AgentLockTimings -Name $domain).StallMinutes
    $quietMinutes = $null
    $rule = 'quiet-owner'
    $activity = $null
    $processAlive = $false

    if ($isBuild) {
        $rule = 'no-cpu'
        if ($null -eq $heldMinutes -or [double]$heldMinutes -lt [double]$threshold) { return $null }
        $processAlive = [bool](Get-Process -Id $holderPid -ErrorAction SilentlyContinue)
        if (-not $processAlive) { return $null }
        $activity = Measure-AgentBuildActivity -HolderPid $holderPid -SampleSeconds $SampleSeconds
        if ($null -eq $activity) { return $null }
        if ([double]$activity.treeCpuSeconds -gt ($Script:AgentStallIdleCpuRate * $activity.sampleSeconds)) { return $null }
        if ([double]$activity.engineCpuSeconds -ge ($Script:AgentStallBusyCpuRate * $activity.sampleSeconds)) { return $null }
        # Reported beside the verdict, never part of it, and measured only once the verdict is
        # certain: on a build domain the owner is legitimately silent for the build's whole length,
        # so this number is a second clue for the reader and would be a false positive as a test.
        if (-not [string]::IsNullOrWhiteSpace($sessionId)) {
            $quietMinutes = Get-AgentOwnerQuietMinutes -SessionId $sessionId -TranscriptPath $transcriptPath
        }
    }
    else {
        $quietMinutes = Get-AgentOwnerQuietMinutes -SessionId $sessionId -TranscriptPath $transcriptPath
        if ($null -eq $quietMinutes) { return $null }
        if ($quietMinutes -le $threshold) { return $null }
        try { $processAlive = [bool](Test-AgentIdentityProcessAlive -Id $sessionId) } catch { $processAlive = $false }
    }

    return [pscustomobject][ordered]@{
        domain             = $domain
        rule               = $rule
        sessionId          = $sessionId
        heldMinutes        = $heldMinutes
        quietMinutes       = $quietMinutes
        thresholdMinutes   = [int]$threshold
        queueDepth         = $waits.Count
        longestWaitMinutes = [math]::Round((@($waits | Sort-Object -Descending)[0]), 1)
        holderProcessAlive = $processAlive
        holderPid          = $holderPid
        sampleSeconds      = $(if ($activity) { $activity.sampleSeconds } else { $null })
        treeCpuSeconds     = $(if ($activity) { $activity.treeCpuSeconds } else { $null })
        engineCpuSeconds   = $(if ($activity) { $activity.engineCpuSeconds } else { $null })
    }
}

function Get-AgentLockStalls {
    <#
    .SYNOPSIS
        Every stalled domain of the table, in canonical rank order. Empty when nothing is stalled.
    #>
    $out = @()
    foreach ($row in @(Get-AgentLockDomainTable)) {
        $stall = Get-AgentLockStall -Name $row.Domain
        if ($null -ne $stall) { $out += $stall }
    }
    return @($out)
}

function Remove-StaleAgentLockTickets {
    <#
    .SYNOPSIS
        Drop tickets whose owner is no longer live, plus a head that forfeited its turn. Returns
        the total count.
    .DESCRIPTION
        Without this, one closed session parks itself at the head of the queue and every other
        agent waits forever - a worse failure than the contention the queue exists to fix.
        A malformed ticket file is deleted, mirroring how a torn lock file is already treated.

        Three independent reasons, in this order:
          1. the owner is stale by Get-AgentTicketLiveness against SessionStaleMinutes;
          1b. S2577 - a BUILD ticket whose own process is gone while its session stays live. The
             narrowest of the three: build domain only, five conditions, see that branch;
          2. S2194 - the ticket is its queue's head, its turn was granted more than
             ReservationMinutes ago, and it never took the lock. See the comment at that branch
             for why this is not the ticket-age timer the timings table forbids.

        S2421 qualifies reason 2, which was written assuming a free lock and never said so.
        turnGrantedAt records that a free lock was OBSERVED, not that it stayed free:
        Set-AgentTicketTurnGranted is one-shot, so the stamp keeps ageing while somebody else holds
        the lock, and Test-AgentLockTurn now clears it on every observation of a held lock so the
        window restarts from the release. Reason 2 is additionally not even considered while a live
        foreign lock exists - "granted and never taken" is false when entering was impossible.
    #>
    param([Parameter(Mandatory)][string]$Name)

    $timings = Get-AgentLockTimings -Name $Name
    $queueDirs = @(Get-AgentLockQueueDir -Name $Name)

    # S2170: sweep the pre-split queue too, exactly the set Get-AgentLockQueue reads. Without this
    # the two halves disagreed: a ticket written before the split was READ as a place in every
    # domain of its type but never judged for liveness, so a dead session's pre-split ticket sat on
    # the head of all three code domains permanently - visible to every inspector, evictable by
    # nothing, which is the starvation shape the eviction pass exists to prevent.
    $legacyName = Get-AgentLockLegacyName -Name $Name
    if ($legacyName) {
        $legacyDir = Join-Path (Get-SzaPath 'locksDir') "$($legacyName.ToUpper()).QUEUE"
        if (Test-Path -LiteralPath $legacyDir) { $queueDirs += $legacyDir }
    }
    $removed = 0

    foreach ($file in @($queueDirs | ForEach-Object { Get-ChildItem -LiteralPath $_ -Filter '*.json' -ErrorAction SilentlyContinue })) {
        $ticket = $null
        try { $ticket = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
        catch { $ticket = $null }

        if ($null -eq $ticket) {
            # Unreadable, but a ticket being rewritten right now looks identical to a corrupt
            # one. Only a file that has stayed unreadable past a grace window is really corrupt;
            # deleting a fresh one would drop a live agent's place in the queue.
            $unreadableForSeconds = ((Get-Date) - $file.LastWriteTime).TotalSeconds
            if ($unreadableForSeconds -gt 60) {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
                $removed++
            }
            continue
        }

        $liveness = Get-AgentTicketLiveness -Ticket $ticket -StaleMinutes $timings.SessionStaleMinutes
        if ($liveness -eq 'foreign-stale') {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
            $removed++
            continue
        }

        # S2577 - reason 1b. A build ticket whose enqueueing process is gone while the session it
        # belongs to keeps writing: session liveness alone can never see this, and it is what
        # parks a dead waiter at the head of a live queue. Five conditions, each closing one way
        # this could evict somebody still working - the mirror image of S2421, which was this
        # sweep evicting a live waiter and cost a session 292 s of correct polling.
        #   - build domain only: a code ticket's enqueueing process is EXPECTED to be gone;
        #   - foreign-live only: 'self' is our own place and 'undetermined' means we have no
        #     session id, so ours and theirs are indistinguishable - never grounds for eviction;
        #   - the process is provably gone, every doubt reading as alive
        #     (Test-AgentTicketProcessAlive);
        #   - no heartbeat inside ReservationMinutes: a live wait-for-lock-turn.ps1 under an
        #     inherited ticket (session dedup, or -Handoff where the runtime has no session id)
        #     stamps its own pid and lastSeenAt on every poll;
        #   - no live turn reservation: between "your turn" and the build actually starting, the
        #     ticket deliberately outlives the waiter process that earned it.
        # No new constant: the two windows read ReservationMinutes from $Script:AgentLockTimings,
        # which is the single home of every minute in this file.
        if ($Name -like 'Build*' -and $liveness -eq 'foreign-live' -and
            -not (Test-AgentTicketProcessAlive -Ticket $ticket)) {
            $graceMs = [double]$timings.ReservationMinutes * 60000.0
            $sweepNowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $heartbeatFresh = $false
            if ($ticket.PSObject.Properties.Name -contains 'lastSeenAt' -and $ticket.lastSeenAt) {
                $heartbeatFresh = (($sweepNowMs - [int64]$ticket.lastSeenAt) -le $graceMs)
            }
            $reservationLive = $false
            if ($ticket.PSObject.Properties.Name -contains 'turnGrantedAt' -and $ticket.turnGrantedAt) {
                $reservationLive = (($sweepNowMs - [int64]$ticket.turnGrantedAt) -le $graceMs)
            }
            if (-not $heartbeatFresh -and -not $reservationLive) {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
                $removed++
            }
        }
    }

    # S2194: a second, deliberately narrow reason to drop a ticket - a HEAD whose turn was granted
    # and never taken. This is NOT the ticket-age timer the timings table above forbids: it reads
    # ReservationMinutes rather than TicketCeilingMinutes or SessionStaleMinutes, and it judges an
    # already-granted turn instead of a wait, so a session waiting behind a long build is untouched
    # however long it waits. Safe because it fires only AFTER the reservation expired, at which
    # point the head holds no privilege anyway - Test-AgentLockTurn already hands the turn to
    # whoever asks. Leaving it in place is what costs: every remaining waiter is then told "your
    # turn" at once and they race for the lock file, so a later arrival can overtake an earlier
    # one, and every inspector reports a waiter that does not exist.
    $selfSessionId = Get-AgentSessionId
    $lockStatus = Get-AgentLockStatus -Name $Name
    $reservationMs = [double]$timings.ReservationMinutes * 60000.0
    $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

    foreach ($queueDir in $queueDirs) {
        $entries = @()
        foreach ($file in @(Get-ChildItem -LiteralPath $queueDir -Filter '*.json' -ErrorAction SilentlyContinue)) {
            $ticket = $null
            try { $ticket = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
            catch { $ticket = $null }
            if ($null -eq $ticket -or $null -eq $ticket.seq) { continue }
            $entries += [pscustomobject]@{ File = $file; Ticket = $ticket }
        }
        if ($entries.Count -eq 0) { continue }

        $head = @($entries | Sort-Object { [int]$_.Ticket.seq })[0]
        $headTicket = $head.Ticket
        if (-not ($headTicket.PSObject.Properties['turnGrantedAt'] -and $headTicket.turnGrantedAt)) { continue }
        # Never the caller's own head: this sweep runs on the acquire path, so without this the
        # session would drop the very turn it came to take.
        if ([string]$headTicket.sessionId -eq $selfSessionId) { continue }
        # The head may have taken the lock and simply not cleared its ticket yet.
        if ($lockStatus.Exists -and [string]$lockStatus.SessionId -eq [string]$headTicket.sessionId) { continue }
        # S2421: a THIRD session holds the lock, so the head could not enter however hard it tried.
        # The forfeit below asserts "the turn was granted and never taken"; against a foreign holder
        # that assertion is simply false, and acting on it evicts a live waiter for obeying the
        # waiting contract - measured 2026-09-03, a waiter that had polled every 5 s for 292 s lost
        # its Code.Scripts place to a session that was never in the queue. The two exemptions above
        # are both about identity, so neither covers this state. S2194's own scenario survives
        # intact: an abandoned head only blocks its neighbours while the lock is FREE, and under a
        # held lock every waiter is waiting on the lock rather than on the head. A torn or expired
        # lock reports Stale, so the forfeit still runs there - a stale lock has no live holder.
        if ($lockStatus.Exists -and -not $lockStatus.Stale) { continue }
        if (($nowMs - [int64]$headTicket.turnGrantedAt) -le $reservationMs) { continue }

        Remove-Item -LiteralPath $head.File.FullName -Force -ErrorAction SilentlyContinue
        $removed++
    }

    [void](Remove-StaleTurnMarkers -Name $Name)

    return $removed
}

function Remove-StaleTurnMarkers {
    <#
    .SYNOPSIS
        Sweep turn markers in temp/ older than ReservationMinutes (or StaleMinutes). Returns count removed.
    .DESCRIPTION
        S2405: wait-for-lock-turn.ps1 writes temp/*.TURN-<sessionId>.json markers when a wait completes.
        These markers are read by the waiting session or inspectors. A marker whose age exceeds
        the domain's ReservationMinutes (plus buffer) or whose timestamp is old is no longer needed
        and must be removed to avoid accumulating endless files.
    #>
    param(
        [string]$Name
    )
    $tempDir = (Get-SzaPath 'locksDir')
    if (-not (Test-Path -LiteralPath $tempDir)) { return 0 }

    $maxAgeMinutes = 15
    if ($Name) {
        $timings = Get-AgentLockTimings -Name $Name
        if ($timings -and $timings.ReservationMinutes) {
            $maxAgeMinutes = [Math]::Max(15, [int]($timings.ReservationMinutes * 3))
        }
    }

    $cutoff = (Get-Date).AddMinutes(-$maxAgeMinutes)
    $pattern = if ($Name) { "$($Name.ToUpper())*.TURN-*.json" } else { "*.TURN-*.json" }
    $removed = 0

    foreach ($file in @(Get-ChildItem -LiteralPath $tempDir -Filter $pattern -ErrorAction SilentlyContinue)) {
        if ($file.LastWriteTime -lt $cutoff) {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
            $removed++
        }
    }
    return $removed
}

function Remove-AgentSessionTickets {
    <#
    .SYNOPSIS
        Drop every queue ticket owned by one session. Returns the count removed.
    .DESCRIPTION
        S1448. Called the instant a session takes the lock. Without it a session that works step
        by step - take lock, close step, immediately queue for the next one - leaves the previous
        step's ticket sitting on the queue head while it holds the lock, and every sibling behind
        that ticket waits for a head that belongs to the current holder. Reads the directory
        directly rather than going through Get-AgentLockQueue: this runs on the acquire path,
        where the eviction sweep's extra work buys nothing.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$SessionId
    )

    if ([string]::IsNullOrWhiteSpace($SessionId)) { return 0 }
    $queueDir = Get-AgentLockQueueDir -Name $Name
    $removed = 0

    foreach ($file in @(Get-ChildItem -LiteralPath $queueDir -Filter '*.json' -ErrorAction SilentlyContinue)) {
        $ticket = $null
        try { $ticket = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
        catch { continue }
        if ([string]$ticket.sessionId -ne $SessionId) { continue }
        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
        $removed++
    }

    return $removed
}

function Get-AgentLockQueue {
    <#
    .SYNOPSIS
        Surviving tickets for a lock, ordered by sequence number. Evicts first, so every reader
        sees a self-cleaning queue.
    #>
    param([Parameter(Mandatory)][string]$Name)

    [void](Remove-StaleAgentLockTickets -Name $Name)
    $queueDirs = @(Get-AgentLockQueueDir -Name $Name)

    # S2109 transition: a ticket written before the split names no domain, so it is a place in the
    # queue of every domain of its type. Ordering stays by sequence number, which is what makes a
    # legacy waiter keep the position it earned instead of being overtaken by the split.
    $legacyName = Get-AgentLockLegacyName -Name $Name
    if ($legacyName) {
        $legacyDir = Join-Path (Get-SzaPath 'locksDir') "$($legacyName.ToUpper()).QUEUE"
        if (Test-Path -LiteralPath $legacyDir) { $queueDirs += $legacyDir }
    }

    $tickets = @()
    foreach ($queueDir in $queueDirs) {
        foreach ($file in @(Get-ChildItem -LiteralPath $queueDir -Filter '*.json' -ErrorAction SilentlyContinue)) {
            try { $ticket = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
            catch { continue }
            $ticket | Add-Member -NotePropertyName 'path' -NotePropertyValue $file.FullName -Force
            $tickets += $ticket
        }
    }

    return @($tickets | Sort-Object { [int]$_.seq })
}

function Set-AgentTicketTurnGranted {
    <#
    .SYNOPSIS
        Stamp the moment a ticket became eligible to take the lock. Best-effort, idempotent.
    .DESCRIPTION
        The reservation window must start when the turn ARRIVES, not when the ticket was issued -
        a waiter that legitimately queued behind a 20-minute build would otherwise have its
        reservation expire before it was ever offered the resource. Any process that observes
        "lock free, this ticket is head" stamps it, so no central arbiter is needed. Two
        processes racing here write the same fact, so a lost write costs nothing.
    #>
    param([Parameter(Mandatory)]$Ticket)

    # Property-bag probe, not a direct read: a ticket written before this field existed has no
    # such property, and a caller running under Set-StrictMode turns that read into a terminating
    # error - which took the whole lock queue down with it instead of stamping the ticket.
    if ($Ticket.PSObject.Properties['turnGrantedAt'] -and $Ticket.turnGrantedAt) { return $Ticket }
    $Ticket | Add-Member -NotePropertyName 'turnGrantedAt' -NotePropertyValue ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Force
    try {
        $body = $Ticket | Select-Object -ExcludeProperty path | ConvertTo-Json -Compress
        # Write-then-rename, never write in place: a reader that caught a half-written ticket
        # would see malformed JSON, and the sweeper deletes malformed tickets - so an in-place
        # write could evict the very queue head it was stamping. Move-Item -Force is an atomic
        # replace on NTFS, so a reader sees either the old ticket or the new one.
        $staging = "$($Ticket.path).tmp-$PID"
        Set-Content -LiteralPath $staging -Value $body -Encoding utf8NoBOM -ErrorAction Stop
        Move-Item -LiteralPath $staging -Destination $Ticket.path -Force -ErrorAction Stop
    }
    catch {
        # The queue survives a failed stamp: the next observer retries, and the ticket ceiling
        # still bounds how long a head can sit there.
    }
    return $Ticket
}

function Clear-AgentTicketTurnGranted {
    <#
    .SYNOPSIS
        Drop a ticket's turnGrantedAt stamp. Best-effort, idempotent.
    .DESCRIPTION
        S2421. Set-AgentTicketTurnGranted is one-shot by design, so the stamp records "a free lock
        was observed once", never "the lock has been free since". Left alone it keeps ageing while a
        foreign session holds the lock, and the reservation window it feeds is therefore already
        spent at the moment the lock is finally released - the head would be evictable before its
        owner's next 5-second poll. Clearing it whenever the lock is observed held restarts the
        window from the release, which is what the field was always meant to measure.

        Costs at most one write per period of occupancy: the field is removed once and there is
        nothing left to remove afterwards.
    #>
    param([Parameter(Mandatory)]$Ticket)

    # Property-bag probe for the same reason Set-AgentTicketTurnGranted uses one: a ticket written
    # before the field existed has no such property, and a direct read under Set-StrictMode is a
    # terminating error that would take the whole sweep down with it.
    if (-not ($Ticket.PSObject.Properties['turnGrantedAt'] -and $Ticket.turnGrantedAt)) { return $Ticket }
    if (-not ($Ticket.PSObject.Properties['path'] -and $Ticket.path)) { return $Ticket }
    $Ticket.PSObject.Properties.Remove('turnGrantedAt')
    try {
        $body = $Ticket | Select-Object -ExcludeProperty path | ConvertTo-Json -Compress
        # Write-then-rename, never in place: the sweeper deletes a ticket it cannot parse, so a
        # reader catching a half-written file could evict the very head being cleared.
        $staging = "$($Ticket.path).tmp-$PID"
        Set-Content -LiteralPath $staging -Value $body -Encoding utf8NoBOM -ErrorAction Stop
        Move-Item -LiteralPath $staging -Destination $Ticket.path -Force -ErrorAction Stop
    }
    catch {
        # A failed clear costs nothing beyond one more occupied poll: the next observer of the held
        # lock retries, and the forfeit branch is exempt while that lock is held anyway.
    }
    return $Ticket
}
function Set-AgentTicketHeartbeat {
    <#
    .SYNOPSIS
        Stamp lastSeenAt on a ticket. Best-effort; overwrites any previous value.
    .DESCRIPTION
        S1448. A ticket's owner is a session, and the only heartbeat available for a session used
        to be its transcript write time - which punishes exactly the behaviour the waiting
        contract demands: take a ticket, run the background waiter, do lock-free work. A session
        that waits quietly writes nothing, looks dead at SessionStaleMinutes, and gets evicted
        from a place it earned. The poll loop is proof the waiter is alive, so it records that
        proof here. Unlike Set-AgentTicketTurnGranted this rewrites on every call - it is a
        heartbeat, not a one-shot fact. This stamp deliberately does not extend TicketCeilingMinutes
        (S1448 ADR-3) - but that is moot for a queue, because S2098 found no queue consumer reads
        that field at all: an abandoned head does NOT age out, and the remedy is the owning session
        calling withdraw-lock-ticket.ps1. See the timings table for why applying it would be worse.
    #>
    param([Parameter(Mandatory)]$Ticket)

    if (-not $Ticket -or -not $Ticket.path) { return $Ticket }
    $Ticket | Add-Member -NotePropertyName 'lastSeenAt' -NotePropertyValue ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Force
    # S2577: the heartbeat also names WHO is watching now. A waiter routinely inherits a ticket
    # another process wrote - session dedup in New-AgentLockTicket, or -Handoff in a runtime with
    # no session id - and reason 1b of the sweep judges a build ticket by its pid, so a live
    # waiter under an inherited ticket has to re-stamp its own process or be swept as abandoned.
    $Ticket | Add-Member -NotePropertyName 'pid' -NotePropertyValue $PID -Force
    try { $Ticket | Add-Member -NotePropertyName 'procStart' -NotePropertyValue ((Get-Process -Id $PID).StartTime.Ticks) -Force }
    catch { $Ticket | Add-Member -NotePropertyName 'procStart' -NotePropertyValue 0 -Force }
    try {
        $body = $Ticket | Select-Object -ExcludeProperty path | ConvertTo-Json -Compress
        # Write-then-rename for the same reason Set-AgentTicketTurnGranted does it: the sweeper
        # deletes a ticket it cannot parse, so an in-place write could evict the ticket it is
        # stamping. Move-Item -Force is an atomic replace on NTFS.
        $staging = "$($Ticket.path).tmp-$PID"
        Set-Content -LiteralPath $staging -Value $body -Encoding utf8NoBOM -ErrorAction Stop
        Move-Item -LiteralPath $staging -Destination $Ticket.path -Force -ErrorAction Stop
    }
    catch {
        # A missed heartbeat costs nothing: the next poll writes another one, and the ticket
        # ceiling still bounds how long any ticket can sit in the queue.
    }
    return $Ticket
}

function Test-AgentLockTurn {
    <#
    .SYNOPSIS
        Whose turn is it. Returns IsMyTurn / Position / HeadSessionId / Reason.
    .DESCRIPTION
        Ownership of a queued resource belongs to the head of the queue, not to whoever polls
        fastest. A free lock is therefore NOT enough to acquire: a live head that has not yet
        used its reservation window still owns the turn. That window is what survives the gap
        between the "your turn" signal and the moment gradle actually starts.

        S1448: the turn is decided by TICKET identity alone. A caller with no ticket is answered
        from the lock and the head's reservation, never from a session-id match against the head.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        $Ticket
    )

    $timings = Get-AgentLockTimings -Name $Name
    $queue = @(Get-AgentLockQueue -Name $Name)

    $position = 0
    if ($Ticket) {
        for ($i = 0; $i -lt $queue.Count; $i++) {
            if ([int]$queue[$i].seq -eq [int]$Ticket.seq) { $position = $i + 1; break }
        }
    }

    if ($queue.Count -eq 0) {
        return [pscustomobject]@{ IsMyTurn = $true; Position = 0; HeadSessionId = $null; Reason = 'queue is empty' }
    }

    $head = $queue[0]
    if ($Ticket) {
        # A ticket is the precise question: is THIS ticket the head. Comparing session ids
        # instead would tell two processes of the SAME session that both of them are next.
        if ([int]$head.seq -eq [int]$Ticket.seq) {
            return [pscustomobject]@{ IsMyTurn = $true; Position = 1; HeadSessionId = $head.sessionId; Reason = 'head of queue' }
        }
    }
    # S1448: a caller WITHOUT a ticket used to inherit the turn whenever the head happened to
    # belong to its own session. That is precisely the starvation shape - the head was the
    # caller's own abandoned ticket from a previous step, so the session handed itself every
    # turn and nobody behind it ever advanced. The turn belongs to a ticket, never to a session.

    $lockStatus = Get-AgentLockStatus -Name $Name
    if ($lockStatus.Exists -and -not $lockStatus.Stale) {
        # S2421: turnGrantedAt below means "a free lock was observed", not "the lock is free", and
        # Set-AgentTicketTurnGranted never rewrites it. So a stamp taken in a brief free window goes
        # on ageing under a foreign holder, and Remove-StaleAgentLockTickets would read that age as
        # a forfeited turn. Reset it here, so the head's reservation is counted from the moment the
        # lock actually became free. Skipped when the head IS the holder: its stamp is the record of
        # the turn it took, and the sweep exempts it on identity anyway.
        if ([string]$lockStatus.SessionId -ne [string]$head.sessionId) {
            [void](Clear-AgentTicketTurnGranted -Ticket $head)
        }
        return [pscustomobject]@{ IsMyTurn = $false; Position = $position; HeadSessionId = $head.sessionId; Reason = 'lock held' }
    }

    [void](Set-AgentTicketTurnGranted -Ticket $head)
    $grantedAt = if ($head.PSObject.Properties['turnGrantedAt'] -and $head.turnGrantedAt) {
        [int64]$head.turnGrantedAt
    } else {
        [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    }
    $reservedForMinutes = ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - $grantedAt) / 60000.0
    if ($reservedForMinutes -gt $timings.ReservationMinutes) {
        return [pscustomobject]@{ IsMyTurn = $true; Position = $position; HeadSessionId = $head.sessionId; Reason = 'head reservation expired' }
    }

    return [pscustomobject]@{ IsMyTurn = $false; Position = $position; HeadSessionId = $head.sessionId; Reason = 'reserved for queue head' }
}

function Test-WaiterAcquireEligible {
    <#
    .SYNOPSIS
        May wait-for-lock-turn.ps1 -Acquire take the lock in the waiter process? Returns
        Eligible / Reason.
    .DESCRIPTION
        Chaining the acquire onto the poll that observed the turn is what keeps a freed domain
        from sitting idle for the head's whole reservation window while its owner comes back
        through a model round trip. It is safe only where the lock outlives the process that took
        it, and there are exactly two shapes where it does not:

          - a BUILD domain, whose staleness is judged by the acquiring PID (Get-AgentLockStatus).
            The waiter exits the instant it acquires, so the lock would read as dead on arrival
            and the next caller would reclaim it out from under the session it was taken for;
          - a pid-<PID> session identity, the last resort of the identity chain. A code lock is
            judged by its owner session, so a lock stamped with one process's pid is foreign to
            every later process of the same session - including the one that asked for the wait.

        Everything else - a code domain under a stable identity - keeps the lock exactly as if
        the caller had acquired it itself, which is what makes the caller's re-run re-entrant.
    #>
    param(
        [Parameter(Mandatory)][string[]]$Domains,
        [Parameter(Mandatory)][string]$SessionId
    )

    # Count first, index second: under Set-StrictMode -Version Latest, indexing an empty result
    # throws instead of yielding $null, and every caller of this helper runs strict.
    $buildDomains = @($Domains | Where-Object { $_ -like 'Build*' })
    if ($buildDomains.Count -gt 0) {
        return [pscustomobject]@{
            Eligible = $false
            Reason   = "$($buildDomains[0]) is judged stale by the acquiring PID, and this process exits at once."
        }
    }
    if ($SessionId -match '^pid-\d+$') {
        return [pscustomobject]@{
            Eligible = $false
            Reason   = "this session has no stable identity ($SessionId), so a lock taken here would be foreign to its own later processes."
        }
    }
    return [pscustomobject]@{ Eligible = $true; Reason = 'code domain under a stable session identity' }
}

function New-AgentLockTicketSet {
    <#
    .SYNOPSIS
        Take one place per domain of a set. Returns a hashtable keyed by domain name.
    .DESCRIPTION
        S2109. A multi-domain waiter needs a place in every queue it will eventually take, or the
        domains it is not queued for can be handed to somebody who arrived later. Tickets are
        taken in canonical order for the same reason acquisition is: it is the order that makes
        two overlapping sets resolve rather than block.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Reason,
        [string[]]$Domains,
        [switch]$ForceNew
    )

    $resolved = @(if ($Domains) { Sort-AgentLockDomains -Domain $Domains }

                else { Resolve-AgentLockDomains -Name $Name })
    $tickets = @{}
    foreach ($domain in $resolved) {
        $tickets[$domain] = New-AgentLockTicket -Name $domain -Reason $Reason -ForceNew:$ForceNew
    }
    return $tickets
}

function Test-AgentLockTurnSet {
    <#
    .SYNOPSIS
        Is it this caller's turn in EVERY domain of a set. Returns IsMyTurn / Position /
        BlockingDomain / Reason.
    .DESCRIPTION
        S2109. Granted only when the caller's ticket is the head everywhere. Being head in one
        domain and second in another is not a partial success - it is the state that livelocks
        two overlapping sets, because each waiter holds the head the other one needs. Reporting
        it as "not yet, blocked on <domain>" is what keeps the wait honest, and Position is the
        worst position across the set rather than the best.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [hashtable]$Tickets,
        [string[]]$Domains
    )

    $resolved = @(if ($Domains) { Sort-AgentLockDomains -Domain $Domains }

                else { Resolve-AgentLockDomains -Name $Name })
    $worstPosition = 0
    foreach ($domain in $resolved) {
        $ticket = if ($Tickets -and $Tickets.ContainsKey($domain)) { $Tickets[$domain] } else { $null }
        $turn = Test-AgentLockTurn -Name $domain -Ticket $ticket
        if ($turn.Position -gt $worstPosition) { $worstPosition = $turn.Position }
        if (-not $turn.IsMyTurn) {
            return [pscustomobject]@{
                IsMyTurn = $false; Position = $turn.Position; BlockingDomain = $domain
                HeadSessionId = $turn.HeadSessionId; Reason = "$domain - $($turn.Reason)"
            }
        }
    }

    return [pscustomobject]@{
        IsMyTurn = $true; Position = $worstPosition; BlockingDomain = $null
        HeadSessionId = $null; Reason = 'head of queue in every domain'
    }
}

function Get-AgentLockBlockingDomain {
    <#
    .SYNOPSIS
        Which domain of a set is actually holding this caller back. Returns a domain name, or
        $null when nothing observable holds it.
    .DESCRIPTION
        S2410. A refused set has two different reasons and they live in two different places: a
        live LOCK on one of its domains, or a foreign ticket ahead of ours in one of its QUEUES.
        Test-AgentLockTurnSet answers the second question only, and answers it correctly - being
        head in every queue while a foreign lock is held is an ordinary state, and it reports
        BlockingDomain = $null for it.

        A caller that reads that $null as "no information" and substitutes the first domain of
        the set states something false rather than merely vague: the refusal then names a domain
        it can be seen to be free, so the message reads as a broken queue instead of a busy
        neighbour, and the wait it suggests returns instantly and refuses again.

        The lock is asked first because it is the stronger fact: a domain another session is
        editing right now blocks the set wherever our ticket sits in its queue.

        $null is a real answer, not a failure - the set was refused, yet no domain of it carries
        a live lock and this caller is head in every queue, which is a transient collision
        against a concurrent acquire. The caller MUST NOT name a domain in that case: there is
        no true one to name, and inventing one is the defect this function exists to remove.
    #>
    param(
        [Parameter(Mandatory)][string[]]$Domains,
        # What Test-AgentLockTurnSet returned, when the caller has it. Optional: the lock walk
        # above needs nothing, and a caller with no turn object still gets the stronger half.
        $Turn
    )

    foreach ($domain in @(Sort-AgentLockDomains -Domain $Domains)) {
        $status = Get-AgentLockStatus -Name $domain
        if ($status.Exists -and -not $status.Stale) { return $domain }
    }

    # S1462: the turn object is whatever a caller passed, so the property is probed rather than
    # read - an absent one is an error only under Set-StrictMode, which is exactly the caller
    # this would break and no other.
    if ($Turn -and $Turn.PSObject.Properties['BlockingDomain'] -and $Turn.BlockingDomain) {
        return [string]$Turn.BlockingDomain
    }

    return $null
}

function Remove-AgentSessionTicketSet {
    <#
    .SYNOPSIS
        Drop this session's tickets across every domain of a set. Returns the count removed.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$SessionId,
        [string[]]$Domains
    )

    $resolved = @(if ($Domains) { Sort-AgentLockDomains -Domain $Domains }

                else { Resolve-AgentLockDomains -Name $Name })
    $removed = 0
    foreach ($domain in $resolved) {
        $removed += Remove-AgentSessionTickets -Name $domain -SessionId $SessionId
    }
    return $removed
}

function Save-AgentLockTicketHandoff {
    <#
    .SYNOPSIS
        Persist a ticket set to a per-intent handoff file. Returns the file path.
    .DESCRIPTION
        S2403. enter-code-lock and the waiter it instructs are separate pwsh processes, and in a
        runtime with no session id their pid-fallback identities never match, so the "one
        session, one place" dedup in New-AgentLockTicket cannot bridge them: the waiter took a
        SECOND ticket and then waited out the reservation window behind its own dead first one.
        The agent that reads the exit-4 message and copies the suggested command is the only
        session-scoped channel between the two processes, so the ticket travels in a uniquely
        named file that the suggested command carries by path.

        The file is disposable by design: nothing sweeps it, and a stale copy is inert because
        the reader rejects it by age and by "seq still queued" - the worst failure is a fresh
        ticket, which is exactly the pre-S2403 behaviour.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Tickets,
        [Parameter(Mandatory)][string]$Reason
    )

    $dir = (Get-SzaPath 'lockHandoffDir')
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $firstDomain = @($Tickets.Keys | Sort-Object)[0]
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $path = Join-Path $dir ("HANDOFF-{0}-{1}-{2}-{3}.json" -f $firstDomain.ToUpper(), [int]$Tickets[$firstDomain].seq, $stamp, $PID)
    $seqMap = [ordered]@{}
    foreach ($domain in @($Tickets.Keys | Sort-Object)) { $seqMap[$domain] = [int]$Tickets[$domain].seq }
    $body = [ordered]@{
        schema    = 1
        reason    = $Reason
        sessionId = (Get-AgentSessionId)
        createdAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        tickets   = $seqMap
    } | ConvertTo-Json -Compress
    # Write-then-rename so a reader never catches a half-written handoff - same discipline as the
    # ticket and marker writers, for the same reason.
    $staging = "$path.tmp-$PID"
    Set-Content -LiteralPath $staging -Value $body -Encoding utf8NoBOM
    Move-Item -LiteralPath $staging -Destination $path -Force
    return $path
}

function Read-AgentLockTicketHandoff {
    <#
    .SYNOPSIS
        Adopt tickets from a handoff file for the given domains. Returns a domain-to-ticket
        hashtable covering only domains whose seq is still queued, or $null when unusable.
    .DESCRIPTION
        S2403. Adoption never rewrites the adopted ticket: its sessionId stays the writer's
        identity, fairness stays by seq, and the acquire retires it through the explicit
        by-path removal Enter-AgentLockDomain already applies to a handed-in ticket "whose
        session id differs from ours". Age is bounded by SessionStaleMinutes of the first
        domain because a handoff older than that names tickets whose reservation window and
        liveness have both lapsed - adopting one would claim a place the queue has reclaimed.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Domains
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { return $null }
    if ($null -eq $raw -or $null -eq $raw.tickets -or -not $raw.createdAt) { return $null }

    $ageMinutes = ((Get-Date) - [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$raw.createdAt).LocalDateTime).TotalMinutes
    if ($ageMinutes -gt (Get-AgentLockTimings -Name $Domains[0]).SessionStaleMinutes) { return $null }

    $adopted = @{}
    foreach ($domain in $Domains) {
        $seqProp = $raw.tickets.PSObject.Properties[$domain]
        if (-not $seqProp) { continue }
        $match = @(Get-AgentLockQueue -Name $domain) |
            Where-Object { [int]$_.seq -eq [int]$seqProp.Value } |
            Select-Object -First 1
        if ($match) { $adopted[$domain] = $match }
    }
    if ($adopted.Count -eq 0) { return $null }
    return $adopted
}

function Get-AgentLockStatus {
    <#
    .SYNOPSIS
        Read-only status query. Never deletes anything - staleness is only ever reclaimed by
        Enter-AgentLock, at the moment a caller actually wants the lock.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        # 0 = use the per-resource default from $Script:AgentLockTimings.
        [int]$StaleMinutes = 0
    )
    if ($StaleMinutes -le 0) {
        $StaleMinutes = (Get-AgentLockTimings -Name $Name).LockStaleMinutes
    }

    $path = Get-AgentLockPath -Name $Name
    $tempDirForLock = Split-Path -Parent $path
    $result = [ordered]@{
        Name          = $Name
        Path          = $path
        Legacy        = $false
        Exists        = $false
        AgeSeconds    = $null
        Pid           = $null
        ProcessAlive  = $null
        Reason        = $null
        Host          = $null
        AcquiredAtIso = $null
        SessionId     = $null
        # S2413: the holder stamped it at acquire time, and resolving it again would walk the whole
        # projects tree - the one thing the queue poll may not do.
        TranscriptPath = $null
        # S2623: the verdict that actually decides a code lock's fate, published rather than folded
        # into Stale and discarded. Null on a Build domain, where Pid/ProcessAlive answer instead,
        # and on a schema-1 code lock, which stamped no session to ask about.
        OwnerLiveness = $null
        Stale         = $false
    }

    if (-not (Test-Path -LiteralPath $path)) {
        # S2109 transition: no file for this domain, but a pre-split lock of the same type still
        # holds every domain it covers. Honour it until its owner releases it or today's rules
        # judge it stale - a live sibling that took the old file must not become invisible here.
        $legacyName = Get-AgentLockLegacyName -Name $Name
        $legacyPath = if ($legacyName) { Join-Path $tempDirForLock "$($legacyName.ToUpper()).LOCK" } else { $null }
        if (-not $legacyPath -or -not (Test-Path -LiteralPath $legacyPath)) {
            return [pscustomobject]$result
        }
        if (-not $Script:AgentLockLegacyNoticed.Contains($legacyPath)) {
            [void]$Script:AgentLockLegacyNoticed.Add($legacyPath)
            Write-Host "Honouring pre-split $legacyPath as holding every $legacyName domain." -ForegroundColor DarkGray
        }
        $path = $legacyPath
        $result.Path = $legacyPath
        $result.Legacy = $true
    }
    $result.Exists = $true

    try {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        # Corrupt or mid-write content (torn write from a crash) - treat as stale so a
        # legitimate acquirer is never blocked forever by unreadable leftovers.
        $result.Stale = $true
        return [pscustomobject]$result
    }

    $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $ageSeconds = [math]::Max(0, ($nowMs - [int64]$raw.acquiredAt) / 1000.0)
    $result.AgeSeconds = $ageSeconds
    $result.Pid = [int]$raw.pid
    $result.Reason = [string]$raw.reason
    $result.Host = [string]$raw.host
    $result.AcquiredAtIso = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$raw.acquiredAt).ToLocalTime().ToString('yyyy-MM-ddTHH:mm:ss')

    # S2109: staleness model follows the resource TYPE - every build domain is judged by PID
    # liveness, every code domain by its owning session, exactly as the two bare names were.
    if ($Name -like 'Build*') {
        $proc = Get-Process -Id ([int]$raw.pid) -ErrorAction SilentlyContinue
        $alive = $false
        if ($proc) {
            try {
                # StartTime match defends against PID reuse (a dead build's PID recycled by an
                # unrelated later process would otherwise look "alive").
                $alive = ($proc.StartTime.Ticks -eq [int64]$raw.procStart)
            }
            catch {
                # Some processes deny StartTime (cross-session/elevated) - treat as alive rather
                # than force-clearing a lock we can't actually disprove.
                $alive = $true
            }
        }
        $result.ProcessAlive = $alive
        $result.Stale = (-not $alive) -or ($ageSeconds -gt ($StaleMinutes * 60))
    }
    else {
        # Code lock: no process to check. S1432 - when the holder stamped a session id, judge it
        # by that session's liveness and let the wall clock be the backstop. A queue behind this
        # lock makes the difference matter: a blindly-expiring lock stalls everyone waiting.
        $result.ProcessAlive = $null
        $result.SessionId = [string]$raw.sessionId
        $result.TranscriptPath = [string]$raw.transcriptPath
        if ([string]::IsNullOrWhiteSpace($result.SessionId)) {
            # schema 1 - nothing to ask about the owner, so the wall clock is all there is.
            $result.Stale = $ageSeconds -gt ($StaleMinutes * 60)
        }
        else {
            # schema 2 - the owner answers for itself. A LIVE owner keeps its lock however long
            # the edit takes: expiring a working session by the clock would hand its turn to the
            # next agent mid-edit, which is precisely the collision this ticket exists to stop.
            # A dead owner needs no clock either - its transcript stops moving and it goes stale
            # on its own, which is what bounds the wait.
            $liveness = Get-AgentTicketLiveness -Ticket ([pscustomobject]@{
                    sessionId      = $raw.sessionId
                    transcriptPath = $raw.transcriptPath
                    enqueuedAt     = $raw.acquiredAt
                }) -StaleMinutes (Get-AgentLockTimings -Name $Name).SessionStaleMinutes
            $result.OwnerLiveness = $liveness
            $result.Stale = switch ($liveness) {
                'foreign-stale' { $true }
                'undetermined' { $ageSeconds -gt ($StaleMinutes * 60) }
                default { $false }
            }
        }
    }

    return [pscustomobject]$result
}

function Resolve-AgentLockTopUp {
    <#
    .SYNOPSIS
        Split a requested domain set into what this session already holds and what is still
        missing, and judge whether a top-up (acquire the missing domains, keep the held ones) is
        safe. Returns @{ Domains; Held; Missing; AscendingSafe }.
    .DESCRIPTION
        S2200. `Enter-AgentLockDomain` has no self-ownership check - a domain this session already
        holds is judged "busy" exactly like a foreign holder's, so a superset request queues the
        caller behind its own lock. That queue entry can never be granted from the outside (the
        only release is this session's own future Exit-AgentLock, which runs only after the
        request already unblocked), so treating it as an ordinary wait is a livelock, not a delay.

        Safety of a top-up is not a single yes/no - it depends on canonical rank (research
        artifact PLAN/S2200_.../research/01). Granting the missing domains while keeping the held
        ones is equivalent to continuing an already-in-progress canonical-order acquisition, and
        inherits that acquisition's deadlock-freedom, only when every held domain outranks every
        missing one - i.e. the caller is extending strictly upward through the table. Extending
        downward (holding a higher-ranked domain, needing to add a lower-ranked one) would let a
        symmetric session holding the lower one and needing the higher deadlock against it - the
        exact AB-BA shape canonical order exists to rule out. That direction is reported unsafe
        here and must fall back to release-then-retake, never a direct grant.
    #>
    param(
        [Parameter(Mandatory)][string[]]$Domains
    )

    $ordered = Sort-AgentLockDomains -Domain $Domains
    $sessionId = Get-AgentSessionId

    $held = @()
    $missing = @()
    foreach ($domain in $ordered) {
        $status = Get-AgentLockStatus -Name $domain
        $isMine = $status.Exists -and -not $status.Stale -and
            [string]$status.SessionId -eq $sessionId
        if ($isMine) { $held += $domain } else { $missing += $domain }
    }

    $rankOf = @{}
    foreach ($entry in (Get-AgentLockDomainTable)) { $rankOf[$entry.Domain] = $entry.Rank }

    # Nothing held, or nothing missing: no direction to judge, so there is nothing unsafe about it
    # - the caller falls straight through to the ordinary full-set or already-held path.
    $ascendingSafe = $true
    if ($held.Count -gt 0 -and $missing.Count -gt 0) {
        $maxHeldRank = ($held | ForEach-Object { $rankOf[$_] } | Measure-Object -Maximum).Maximum
        $minMissingRank = ($missing | ForEach-Object { $rankOf[$_] } | Measure-Object -Minimum).Minimum
        $ascendingSafe = $maxHeldRank -lt $minMissingRank
    }

    return [pscustomobject]@{
        Domains       = $ordered
        Held          = $held
        Missing       = $missing
        AscendingSafe = $ascendingSafe
    }
}

function Enter-AgentLockDomain {
    <#
    .SYNOPSIS
        Acquire ONE concrete domain: reclaim-if-stale, then atomically create. Returns
        @{ Acquired; Status }.
    .DESCRIPTION
        S2109 split this out of Enter-AgentLock unchanged. Enter-AgentLock is now the set-level
        operation and calls this once per domain; every rule here - reservation, staleness,
        ticket retirement, the FMS_BUILD_LOCK_HELD_BY stamp - is per domain, which is what
        strategic section 5.1 pillar A means by "inherited unchanged".

        Single-shot on purpose: the set-level caller owns the waiting, because a domain held
        across a sleep is half a set, and half a set is the deadlock this ticket exists to
        avoid.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Reason,
        # S1432: the caller's queue ticket, when it took one. Supplying it makes this acquire
        # obey the queue order; omitting it keeps the historical behaviour for an empty queue.
        $Ticket
    )

    $status = Get-AgentLockStatus -Name $Name
    $lockBusy = ($status.Exists -and -not $status.Stale)
    # A free lock is not enough: a live queue head that has not yet spent its reservation
    # window still owns the turn (S1432). With an empty queue this is always true, so a
    # caller that never enqueues behaves exactly as it did before.
    $turn = Test-AgentLockTurn -Name $Name -Ticket $Ticket
    if ($lockBusy -or -not $turn.IsMyTurn) {
        $blockedBy = if ($lockBusy) { 'lock' } else { 'queue-head' }
        return [pscustomobject]@{
            Acquired = $false; Status = $status; BlockedBy = $blockedBy; Turn = $turn; Domain = $Name
        }
    }
    if ($status.Exists -and $status.Stale) {
        # Best-effort reclaim of a dead/expired lock before attempting to acquire.
        Remove-Item -LiteralPath $status.Path -Force -ErrorAction SilentlyContinue
    }

    $path = Get-AgentLockPath -Name $Name
    try {
        # FileMode.CreateNew is the atomic test-and-set: it throws IOException if the file
        # already exists, so "does it exist" and "create it" happen as one filesystem call -
        # no Test-Path-then-Write race window.
        $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
    }
    catch [System.IO.IOException] {
        # Lost the race to another process between the staleness check above and this create.
        return [pscustomobject]@{
            Acquired = $false; Status = (Get-AgentLockStatus -Name $Name); BlockedBy = 'lock'; Domain = $Name
        }
    }

    try {
        $proc = Get-Process -Id $PID
        # S2371: the owner is stamped through the same accessor the queue ticket uses, so a
        # lock acquired without CLAUDE_CODE_SESSION_ID names the pid- identity its own session
        # can recognise. The raw env read wrote sessionId null while the ticket of the same
        # acquisition said pid-NNNN - one holder recorded as two different identities.
        $ownerSessionId = Get-AgentSessionId
        $body = [ordered]@{
            # schema 2 (S1432) adds the session fields. A schema-1 file (no sessionId) still
            # reads correctly and still expires - it just falls back to wall-clock staleness.
            schema         = 2
            lockType       = $Name
            pid            = $PID
            procStart      = $proc.StartTime.Ticks
            acquiredAt     = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            reason         = $Reason
            host           = $env:COMPUTERNAME
            sessionId      = $ownerSessionId
            # Raw env on purpose: a pid- identity has no transcript, and searching the whole
            # ~/.claude/projects tree for pid-NNNN.jsonl would cost a scan that cannot match.
            transcriptPath = (Get-AgentSessionTranscriptPath -SessionId $env:CLAUDE_CODE_SESSION_ID)
        } | ConvertTo-Json -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
    }
    finally {
        $stream.Close()
    }

    # The ticket has done its job the moment the lock is held - leaving it in the queue would
    # keep this session at the head and stall everyone behind it (S1432). S1448: sweep EVERY
    # ticket of this session, not only the one handed in - the observed starvation was a ticket
    # from the session's previous step still holding the head while it held the lock. The
    # explicit removal below stays for a ticket whose session id differs from ours.
    # S2408: the sweep must name the identity the tickets were STAMPED with, which is whatever
    # Get-AgentSessionId returned when New-AgentLockTicket ran - a second chain here would sweep
    # nothing and leave this session parked at its own head.
    $acquiringSessionId = Get-AgentSessionId
    [void](Remove-AgentSessionTickets -Name $Name -SessionId $acquiringSessionId)
    if ($Ticket -and $Ticket.path -and (Test-Path -LiteralPath $Ticket.path)) {
        Remove-Item -LiteralPath $Ticket.path -Force -ErrorAction SilentlyContinue
    }

    # Child processes inherit this, which is how a nested gradle-invoking script recognises that
    # its own ancestor already holds the lock (see the re-entrancy guard in Enter-BuildLockOrExit).
    # S2058: carries the acquirer's process-start ticks alongside its PID, not the PID alone - a
    # bare PID match let a process that merely INHERITED this variable from a long-dead ancestor
    # mistake an unrelated, later, coincidentally-same-PID holder for itself and `return` as if it
    # already held BUILD.LOCK, without queueing or building anything - the same PID-reuse hazard
    # Get-AgentLockStatus already guards against for the lock file's own liveness check below.
    # S2109: any build domain, not the bare name alone - a nested gradle script under a
    # Build.Phone holder must recognise its ancestor exactly as it did under a bare Build one.
    if ($Name -like 'Build*') { Set-SzaEnv 'BUILD_LOCK_HELD_BY' -Value "$PID`:$($proc.StartTime.Ticks)" }

    return [pscustomobject]@{
        Acquired = $true; Status = (Get-AgentLockStatus -Name $Name); Domain = $Name
    }
}

function Enter-AgentLock {
    <#
    .SYNOPSIS
        Acquire every domain a name resolves to, all or nothing. Returns @{ Acquired; Status }.
    .DESCRIPTION
        S2109. The name resolves through Resolve-AgentLockDomains into a set, and the set is
        taken in that table's canonical order. Two properties make this safe, and neither is
        optional (strategic section 5.1 pillar D):

          - Canonical order. Two sessions whose sets overlap take the shared domains in the same
            sequence, so one of them always gets the first contested domain and the other always
            queues. Letting callers choose the order is what produces a mutual block with no
            timeout to break it.
          - All or nothing. A domain that cannot be taken releases every domain already taken in
            THIS call before returning, so a refusal never leaves half a set held. A caller that
            waits therefore sleeps holding nothing.

        The returned Status is the blocking domain's on a refusal and the last acquired domain's
        on success; Domains carries the whole set either way.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Reason,
        # S2109: an explicit subset, for a caller whose set was DERIVED and so has no single name
        # ("phone and wear but not scripts"). Ordered canonically here, never by the caller.
        [string[]]$Domains,
        # S1338: block until the holder releases instead of refusing. 793 lock-status polls and
        # 48 hand-rolled `until` loops existed only because this function had no way to wait.
        # Default stays single-shot: a caller that cannot afford to block must still fail fast.
        [switch]$Wait,
        [int]$WaitTimeoutSeconds = 900,
        [int]$PollSeconds = 2,
        $Ticket,
        # Set-level waiters hand back one ticket per domain, keyed by domain name.
        [hashtable]$Tickets
    )

    $domains = @(if ($Domains) { Sort-AgentLockDomains -Domain $Domains }

                else { Resolve-AgentLockDomains -Name $Name })
    $deadline = (Get-Date).AddSeconds($WaitTimeoutSeconds)
    # S2582: a waiting session is the first to be hurt by a stuck holder and the last to hear about
    # it - this loop polls every couple of seconds and says nothing until its timeout an hour later.
    # Measured 2026-09-05, thirteen sessions waited between 5 and 51 minutes behind one hung build
    # holder in exactly this silence. Five minutes, not every poll: the verdict can cost a sampling
    # window, and a line repeated every two seconds is noise nobody reads.
    $nextStallNotice = (Get-Date).AddMinutes(5)

    while ($true) {
        $taken = @()
        $failure = $null

        foreach ($domain in $domains) {
            $domainTicket = if ($Tickets -and $Tickets.ContainsKey($domain)) { $Tickets[$domain] }
                            elseif ($domains.Count -eq 1) { $Ticket }
                            else { $null }
            $attempt = Enter-AgentLockDomain -Name $domain -Reason $Reason -Ticket $domainTicket
            if ($attempt.Acquired) { $taken += $domain; continue }
            $failure = $attempt
            break
        }

        if ($null -eq $failure) {
            # S2372: the acquisition is the moment a sibling refused later wants to read about.
            [void](Send-AgentChatMessage -Kind lock -Domains $domains -Note "acquired $($domains -join ', '): $Reason")
            return [pscustomobject]@{
                Acquired = $true
                Status   = (Get-AgentLockStatus -Name $domains[-1])
                Domains  = $domains
            }
        }

        # Rollback. Releasing what this call took is the whole of "all or nothing": a caller left
        # holding the domains it managed to get would block every session whose set overlaps
        # them, for as long as it waits for the one it could not.
        foreach ($domain in $taken) { Exit-AgentLockDomain -Name $domain }

        if (-not $Wait) {
            return [pscustomobject]@{
                Acquired = $false; Status = $failure.Status; BlockedBy = $failure.BlockedBy
                Turn = $failure.Turn; Domain = $failure.Domain; Domains = $domains
            }
        }
        if ((Get-Date) -ge $deadline) {
            return [pscustomobject]@{
                Acquired = $false; Status = $failure.Status; WaitTimedOut = $true
                BlockedBy = $failure.BlockedBy; Turn = $failure.Turn; Domain = $failure.Domain
                Domains = $domains
            }
        }
        if ((Get-Date) -ge $nextStallNotice) {
            $nextStallNotice = (Get-Date).AddMinutes(5)
            $blockedDomain = if ($failure.Domain) { [string]$failure.Domain } else { [string]$domains[0] }
            $waitStall = $null
            try { $waitStall = Get-AgentLockStall -Name $blockedDomain } catch { $waitStall = $null }
            if ($waitStall) {
                $evidence = if ($waitStall.rule -eq 'no-cpu') {
                    "no CPU - holder tree $($waitStall.treeCpuSeconds)s, build engine $($waitStall.engineCpuSeconds)s over $($waitStall.sampleSeconds)s"
                }
                else {
                    "owner quiet $($waitStall.quietMinutes)m (threshold $($waitStall.thresholdMinutes)m)"
                }
                Write-Host "$blockedDomain STALLED ($($waitStall.rule)): you are waiting behind a holder that is not progressing - held $($waitStall.heldMinutes)m, $evidence, $($waitStall.queueDepth) session(s) in the queue." -ForegroundColor Red
                Write-Host "  This wait continues; nothing is evicted on this verdict. Inspect: $(Get-SzaInvocation 'locks/lock-status.ps1') -Name $blockedDomain -Queue" -ForegroundColor Gray
            }
        }
        Start-Sleep -Seconds $PollSeconds
    }
}

function Exit-AgentLock {
    <#
    .SYNOPSIS
        Release every domain the name resolves to. Safe to call unconditionally from a `finally`.
    .DESCRIPTION
        S2109. Releases exactly the domains its own -Name resolves to, each owner-checked on its
        own. Research artifact 04 makes this the closure facade's contract too: a facade that
        took two domains must give back those two, never the whole code lock, or it hands away a
        third domain some other session is holding.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [string[]]$Domains
    )

    $resolved = @(if ($Domains) { Sort-AgentLockDomains -Domain $Domains }

                else { Resolve-AgentLockDomains -Name $Name })
    $heldBefore = @($resolved | Where-Object { (Get-AgentLockStatus -Name $_).Exists })
    foreach ($domain in $resolved) {
        Exit-AgentLockDomain -Name $domain
    }
    # S2372: say what actually went away - an owner-checked release may leave a file in place.
    $gone = @($heldBefore | Where-Object { -not (Get-AgentLockStatus -Name $_).Exists })
    if ($gone.Count -gt 0) { [void](Send-AgentChatMessage -Kind lock -Domains $gone -Note "released $($gone -join ', ')") }

    # S2109 transition, second half. Adoption alone makes a pre-split lock BLOCK without making it
    # RELEASABLE: a session that took temp/CODE.LOCK before the split releases through this
    # function afterwards, the three domain files it names are absent, and the file it actually
    # holds is never touched - so its own lock outlives it and everyone queued behind it waits for
    # the staleness window instead of for the work. Only a BARE name does this, because the legacy
    # file covers every domain of its type and a caller releasing one domain must not hand away
    # the other two. Ownership is checked by Exit-AgentLockDomain exactly as for any other file.
    # -Domains is a PARTIAL set by construction, so it must never drop the pre-split file either:
    # that file covers every domain of its type, including the ones this caller did not take.
    if (-not $Domains -and $null -eq (Get-AgentLockLegacyName -Name $Name)) {
        $legacyPath = Join-Path (Get-SzaPath 'locksDir') "$($Name.ToUpper()).LOCK"
        if (Test-Path -LiteralPath $legacyPath) { Exit-AgentLockDomain -Name $Name }
    }
}

function Exit-AgentLockDomain {
    <#
    .SYNOPSIS
        Best-effort release of ONE concrete domain. Safe to call unconditionally from a `finally`
        block, even if the lock was never acquired in this process (no-op).

    .DESCRIPTION
        Build and Code have different ownership models, so release differs:
          - Build: acquire and release always happen in the SAME long-running OS process (one
            leaf script's lifetime), so only remove when the recorded pid matches the current
            process - this is what makes it safe to call unconditionally from a `finally`
            without risking deleting a DIFFERENT live build's lock.
          - Code: acquire (scripts/utils/enter-code-lock.ps1) and release
            (scripts/post-change.ps1's finally, or scripts/utils/exit-code-lock.ps1) are
            deliberately DIFFERENT OS processes - each is its own short-lived pwsh invocation,
            with no single process spanning a whole editing turn. A pid-match check here would
            never fire and the lock would never actually be released before its wall-clock
            staleness window. So Code is released unconditionally (best-effort remove) - it is
            already Tier-2/advisory (see agent-lock.ps1 header), so the small risk of racing an
            unrelated concurrent release is an acceptable soft failure mode.
    #>
    param([Parameter(Mandatory)][string]$Name)

    $path = Get-AgentLockPath -Name $Name
    if (-not (Test-Path -LiteralPath $path)) { return }

    # S2109: the ownership model belongs to the resource TYPE, so every code domain releases the
    # way the bare Code lock does and every build domain the way Build does.
    if ($Name -like 'Code*') {
        # S1432: release only what this session owns. With a queue behind the lock, an
        # unconditional delete would hand the turn to the wrong session - not merely drop an
        # advisory hint, as it did before. A schema-1 file (no session id) and a lock whose
        # owner is already stale are still removed, so nothing can get permanently stuck.
        $status = Get-AgentLockStatus -Name $Name
        if (-not $status.Exists) { return }
        # S2371: caller identity through the same accessor the lock was written with, plus a
        # disjunct for the unnamed world. Acquire and release are deliberately DIFFERENT pwsh
        # processes, so a pid- owner can never be pid-matched by its own closure across that
        # boundary - without the disjunct every unnamed closure would leave its live lock held
        # until staleness, blocking the domain for the whole staleness window. An unnamed
        # caller releasing an unnamed owner keeps the pre-S2371 advisory semantics (a null
        # owner was releasable by anyone); a NAMED caller still cannot touch an unnamed
        # holder's live lock.
        $mySessionId = Get-AgentSessionId
        $ownerSessionId = [string]$status.SessionId
        $isMine = [string]::IsNullOrWhiteSpace($ownerSessionId) -or
                  ($ownerSessionId -eq $mySessionId) -or
                  ($ownerSessionId -match '^pid-\d+$' -and [string]::IsNullOrWhiteSpace($env:CLAUDE_CODE_SESSION_ID)) -or
                  $status.Stale
        if (-not $isMine) {
            Write-Host "$($Name.ToUpper()).LOCK belongs to session $ownerSessionId (reason: '$($status.Reason)') - leaving it in place." -ForegroundColor Yellow
            return
        }
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        return
    }

    try {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ([int]$raw.pid -eq $PID) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            # S2058: match the "pid:startTicks" shape Enter-AgentLock now writes - a bare "$PID"
            # comparison here would never match it, leaving the variable set after release and
            # available for a later, unrelated process to inherit and misread as still-live.
            if ((Get-SzaEnv 'BUILD_LOCK_HELD_BY') -match '^(\d+):') {
                if ([int]$Matches[1] -eq $PID) { Set-SzaEnv 'BUILD_LOCK_HELD_BY' -Value $null }
            }
        }
    }
    catch {
        # Corrupt/unreadable content - nothing legible depends on it, safe to drop.
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-GradleJvmHome {
    <#
    .SYNOPSIS
        Resolve the JVM Gradle will run on, in Gradle's own precedence order.
    .DESCRIPTION
        org.gradle.java.home from the user-level gradle.properties, then the repository one,
        then JAVA_HOME. Returns $null when nothing names a JVM - that is not an error, it
        leaves the choice to Gradle. Reads text only; never launches a JVM.
    #>
    $gradleUserHome = if (-not [string]::IsNullOrWhiteSpace($env:GRADLE_USER_HOME)) {
        $env:GRADLE_USER_HOME
    }
    else {
        Join-Path $env:USERPROFILE '.gradle'
    }

    $propertyFiles = @(
        (Join-Path $gradleUserHome 'gradle.properties'),
        (Join-Path $Script:AgentLockRepoRoot 'gradle.properties')
    )

    foreach ($file in $propertyFiles) {
        if (-not (Test-Path -LiteralPath $file)) { continue }
        foreach ($line in (Get-Content -LiteralPath $file -ErrorAction SilentlyContinue)) {
            $trimmed = $line.Trim()
            if ($trimmed.StartsWith('#') -or $trimmed.StartsWith('!')) { continue }
            if ($trimmed -match '^org\.gradle\.java\.home\s*=\s*(.+)$') {
                return [pscustomobject]@{ Path = $Matches[1].Trim(); Source = $file }
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
        return [pscustomobject]@{ Path = $env:JAVA_HOME; Source = 'JAVA_HOME environment variable' }
    }
    return $null
}

function Test-JvmHomeMissingParts {
    <#
    .SYNOPSIS
        Return the names of the JVM parts missing from a candidate JVM home. Empty means usable.
    .DESCRIPTION
        S1425 checks files rather than launching a JVM, because proving it by spawning a process
        would cost that spawn on every build. S1896 gave the same two probes a second caller - the
        launcher JVM - so they live here instead of being written twice and drifting apart.
    #>
    param([Parameter(Mandatory)][string]$JvmHome)

    $missing = @()
    if (-not (@('bin\java.exe', 'bin/java') | Where-Object { Test-Path -LiteralPath (Join-Path $JvmHome $_) })) {
        $missing += 'bin/java(.exe)'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $JvmHome 'lib/jvm.cfg'))) {
        $missing += 'lib/jvm.cfg'
    }
    return , $missing
}

function Resolve-PersistedJavaHomeRepair {
    <#
    .SYNOPSIS
        The persisted JAVA_HOME, for when this process's snapshot of it has gone stale (S1928).
    .DESCRIPTION
        An environment variable inside a running process is a snapshot taken when that process
        started. A long-lived agent session carries the snapshot for hours, so a JDK point-update
        on the machine leaves it naming a directory that no longer exists while the machine's own
        persisted value is already correct. Observed 2026-08-21: every gradle target of a session
        failed identically for the rest of that session, and the fix was to restart the process.

        This is deliberately NOT a fallback-JDK search. It never looks at the disk, never considers
        the Android Studio jbr, and can only ever return a value the operator persisted themselves -
        the very value the stale snapshot is a snapshot OF. Picking a JVM nobody configured is what
        the guard below is right to refuse; refreshing a snapshot is a different act.

        All three conditions are required. A persisted value equal to the snapshot has nothing to
        refresh - the JDK really is gone. An unusable one is not worth taking. An absent one leaves
        the refusal exactly as it was.

        Returns the usable persisted value with the scope it came from, or $null.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$CurrentValue)

    foreach ($scope in @('User', 'Machine')) {
        $candidate = $null
        # Reading a scope is unsupported off Windows and simply yields nothing there.
        try { $candidate = [Environment]::GetEnvironmentVariable('JAVA_HOME', $scope) } catch { continue }
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if ($candidate -eq $CurrentValue) { continue }
        if ((Test-JvmHomeMissingParts -JvmHome $candidate).Count -gt 0) { continue }
        return [pscustomobject]@{ Path = $candidate; Scope = $scope }
    }
    return $null
}

function Assert-GradleToolchainOrExit {
    <#
    .SYNOPSIS
        Refuse to start gradle when the configured JVM cannot launch. Exits 3.
    .DESCRIPTION
        S1425: a partial Android Studio uninstall left bin/java.exe in place but deleted
        lib/jvm.cfg, so every forked JVM died with "could not open jvm.cfg" while the daemon
        already running kept compiling from memory. Compilation stayed green and the whole
        unit-test tier was down for hours before anything said so. Two Test-Path calls at the
        first gradle call buy that signal back; launching the JVM to prove it would cost a
        process spawn on every build, which is why this checks files only.
    #>
    # S1896: the LAUNCHER JVM first, and separately from the daemon one below. gradlew.bat starts
    # on JAVA_HOME; only after that does Gradle read org.gradle.java.home. Resolve-GradleJvmHome
    # returns the first of (user gradle.properties, repo gradle.properties, JAVA_HOME), so a valid
    # org.gradle.java.home made this function pass while gradlew.bat died on a stale JAVA_HOME -
    # the wrapper printed its own error and nothing here ever looked at that variable.
    if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
        $launcherMissing = Test-JvmHomeMissingParts -JvmHome $env:JAVA_HOME
        # S1928: before refusing, ask whether the machine is actually misconfigured or whether only
        # this process's snapshot of JAVA_HOME went stale. The repair is loud on purpose - a silent
        # JVM swap is worse than stopping, and the line below is what makes this a refresh rather
        # than a swap.
        $javaHomeRepair = if ($launcherMissing.Count -gt 0) {
            Resolve-PersistedJavaHomeRepair -CurrentValue $env:JAVA_HOME
        }
        else { $null }
        if ($null -ne $javaHomeRepair) {
            Write-Host "JAVA_HOME snapshot was stale - refreshed from the persisted $($javaHomeRepair.Scope) value." -ForegroundColor Yellow
            Write-Host "  was: $env:JAVA_HOME (missing $($launcherMissing -join ', '))" -ForegroundColor Yellow
            Write-Host "  now: $($javaHomeRepair.Path)" -ForegroundColor Yellow
            Write-Host "  Only this process was changed. Fix the environment your session inherits, or the next one starts stale too." -ForegroundColor Gray
            $env:JAVA_HOME = $javaHomeRepair.Path
            $launcherMissing = @()
        }
        if ($launcherMissing.Count -gt 0) {
            Write-Host "Launcher JVM unusable - refusing to start gradle. Nothing was built." -ForegroundColor Red
            Write-Host "  JAVA_HOME: $env:JAVA_HOME" -ForegroundColor Red
            Write-Host "  Missing: $($launcherMissing -join ', ')" -ForegroundColor Red
            Write-Host "  gradlew.bat launches on JAVA_HOME, before Gradle ever reads org.gradle.java.home," -ForegroundColor Gray
            Write-Host "  so a valid org.gradle.java.home does not rescue this." -ForegroundColor Gray
            Write-Host "  Point JAVA_HOME at a JDK 17, 21, or 25 install, or clear it to let the wrapper search." -ForegroundColor Gray
            exit 3
        }
    }

    $resolved = Resolve-GradleJvmHome
    # Nothing configured anywhere - Gradle picks its own JVM, and there is nothing to verify.
    if ($null -eq $resolved) { return }

    $jvmHome = $resolved.Path
    $missing = Test-JvmHomeMissingParts -JvmHome $jvmHome
    if ($missing.Count -eq 0) { return }

    Write-Host "Toolchain JVM unusable - refusing to start gradle. Nothing was built." -ForegroundColor Red
    Write-Host "  Resolved JVM home: $jvmHome" -ForegroundColor Red
    Write-Host "  Missing: $($missing -join ', ')" -ForegroundColor Red
    Write-Host "  Configured by: $($resolved.Source)" -ForegroundColor Red
    Write-Host "  Point it at a JDK 17, 21, or 25 install (JDK 26 is incompatible with Gradle 9.4.1 / AGP 9.2.1)." -ForegroundColor Gray
    Write-Host "  See the header of gradle.properties for where the JVM home is configured." -ForegroundColor Gray
    exit 3
}

function Enter-BuildLockOrExit {
    <#
    .SYNOPSIS
        Convenience for leaf gradle-invoking scripts: verify the toolchain JVM, warn (never
        block) on a fresh CODE.LOCK, then queue for BUILD.LOCK and acquire it in turn.
    .DESCRIPTION
        S1432: waiting is the DEFAULT. A busy lock puts this caller in the queue and it starts
        when its turn comes, because a refusal here surfaces to an agent as a completed
        background task - "the build passed" has repeatedly meant "the build never ran". Pass
        -NoWait (or set FMS_LOCK_NO_WAIT=1) where an immediate answer matters more.

        Exit codes this function can impose on its caller:
          1 - BUILD.LOCK held and fail-fast was requested (-NoWait / FMS_LOCK_NO_WAIT=1).
          2 - the wait ran out of time; nothing was inspected and nothing was built.
          3 - the launcher JVM (JAVA_HOME) or the configured toolchain JVM cannot launch
              (see Assert-GradleToolchainOrExit - it checks both, and they can differ).
        The toolchain check runs FIRST, so a broken environment never takes the lock or a place
        in the queue.
    #>
    param(
        [Parameter(Mandatory)][string]$Reason,
        # S1338 introduced this switch. S1432 made waiting the DEFAULT, so it is accepted and
        # ignored - every existing call site keeps working and now queues instead of refusing.
        [switch]$Wait,
        # S1432: opt out of the queue for a caller that must answer immediately. The environment
        # variable FMS_LOCK_NO_WAIT=1 does the same globally, for unattended runs.
        [switch]$NoWait,
        [int]$WaitTimeoutSeconds = 3600,
        # S2109: which build domain this run needs. Defaults to the bare name, which is BOTH build
        # domains - so a caller that has not been taught its module keeps serialising against every
        # build exactly as it did before the split (ADR-2: the untouched caller must stay safe, not
        # silently become unprotected).
        [string]$Name = 'Build',
        # An explicit list, for a caller that spans some but not all build domains.
        [string[]]$Domain
    )

    Assert-GradleToolchainOrExit

    # Re-entrancy guard (S1432). Several gates run a nested script while already holding
    # BUILD.LOCK, and `& other.ps1` runs in the SAME process - so the nested acquire would now
    # wait for a lock this very run owns and deadlock. Before waiting became the default this
    # was a fast, visible refusal; it must not silently become a hang.
    #
    # S2058: the inherited half of this check is PID plus process-start ticks, not PID alone. A
    # spawned child process inherits FMS_BUILD_LOCK_HELD_BY from whatever ancestor last acquired
    # the lock in-process; a bare PID match against the CURRENT lock file's holder is therefore
    # only safe as long as PIDs are never reused. Windows reuses them quickly, and a long-lived
    # ancestor spawning many short-lived children makes the collision realistic - when it lands,
    # the child mistook an unrelated, later holder for itself and returned as though it already
    # held BUILD.LOCK, without queueing or actually holding it (observed exit 0 on a refusal that
    # should have queued or failed fast). Start ticks are what Get-AgentLockStatus already uses
    # to defend the SAME lock file against PID reuse a few lines below - this mirrors it rather
    # than inventing a second defense.
    # S2109: the guard has to look at the domains this call will actually take. Asking the bare
    # name would read a file nothing writes any more, so the guard would never fire and a nested
    # gradle script would queue behind its own ancestor - a hang, not a refusal.
    $buildDomains = @(if ($Domain) { Sort-AgentLockDomains -Domain $Domain }
                      else { Resolve-AgentLockDomains -Name $Name })
    $selfCheck = $null
    foreach ($buildDomainItem in $buildDomains) {
        $candidate = Get-AgentLockStatus -Name $buildDomainItem
        if ($candidate.Exists -and -not $candidate.Stale) { $selfCheck = $candidate; break }
    }
    if ($null -eq $selfCheck) { $selfCheck = Get-AgentLockStatus -Name $buildDomains[0] }
    if ($selfCheck.Exists -and -not $selfCheck.Stale) {
        $holderPid = [int]$selfCheck.Pid
        $holderStartTicks = 0
        try {
            $rawLock = Get-Content -LiteralPath $selfCheck.Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($rawLock.PSObject.Properties['procStart']) { $holderStartTicks = [int64]$rawLock.procStart }
        }
        catch {
            # Torn/mid-write lock file - $holderStartTicks stays 0, which never matches a real
            # inherited value below, so the guard falls through to the normal queue/refuse path.
        }
        $inheritedPid = 0
        $inheritedStartTicks = 0
        if ((Get-SzaEnv 'BUILD_LOCK_HELD_BY') -match '^(\d+):(\d+)$') {
            $inheritedPid = [int]$Matches[1]
            $inheritedStartTicks = [int64]$Matches[2]
        }
        $inheritedMatchesHolder = ($inheritedPid -ne 0) -and ($inheritedPid -eq $holderPid) -and
            ($holderStartTicks -ne 0) -and ($inheritedStartTicks -eq $holderStartTicks)
        if ($holderPid -eq $PID -or $inheritedMatchesHolder) {
            Write-Host "$($selfCheck.Name.ToUpper()).LOCK already held by this run (pid $holderPid) - reusing it instead of queueing behind ourselves." -ForegroundColor DarkGray
            return
        }
    }

    # A code edit in ANY domain can leave a half-written tree under this build, so the warning
    # asks about the whole code side rather than one domain of it.
    foreach ($codeDomain in @(Resolve-AgentLockDomains -Name 'Code')) {
        $codeStatus = Get-AgentLockStatus -Name $codeDomain
        if ($codeStatus.Exists -and -not $codeStatus.Stale) {
            Write-Host "Warning: $($codeDomain.ToUpper()).LOCK present (age $([int]$codeStatus.AgeSeconds)s, reason: '$($codeStatus.Reason)') - a code edit may be in progress elsewhere. This build may reflect a half-written state." -ForegroundColor Yellow
        }
    }

    $failFast = $NoWait -or ((Get-SzaEnv 'LOCK_NO_WAIT') -eq '1')
    $enterArgs = @{ Name = $Name; Reason = $Reason; Domains = $buildDomains }
    $ticket = $null
    $ticketSet = $null

    if (-not $failFast) {
        # Take a place in the queue BEFORE looking at the lock: ordering is what turns "whoever
        # polls first" into "whoever asked first" (S1432). S2109: one place per domain this call
        # will take - a ticket in a queue the acquire never consults orders nothing.
        $ticketSet = New-AgentLockTicketSet -Name $Name -Reason $Reason -Domains $buildDomains
        $ticket = $ticketSet[$buildDomains[0]]
        $enterArgs.Wait = $true
        $enterArgs.WaitTimeoutSeconds = $WaitTimeoutSeconds
        $enterArgs.Tickets = $ticketSet

        $turn = Test-AgentLockTurnSet -Name $Name -Tickets $ticketSet -Domains $buildDomains
        $lockNow = $selfCheck
        if (-not $turn.IsMyTurn -or ($lockNow.Exists -and -not $lockNow.Stale)) {
            $holder = if ($lockNow.Exists) { "holder pid $($lockNow.Pid), age $([int]$lockNow.AgeSeconds)s, reason '$($lockNow.Reason)'" } else { $turn.Reason }
            Write-Host "BUILD.LOCK busy - queued at position $($turn.Position) (ticket #$($ticket.seq)) in the Build domain. Waiting up to ${WaitTimeoutSeconds}s. $holder" -ForegroundColor DarkGray
            # S2372: what the holder is doing, and a trace of this wait for whoever queues next.
            $holderChatId = if ($lockNow.Exists) { [string]$lockNow.SessionId } else { [string]$turn.HeadSessionId }
            Write-AgentChatContext -AgentId $holderChatId -Domain $buildDomains[0]
            [void](Send-AgentChatMessage -Kind wait -Domains $buildDomains -Note "queued at position $($turn.Position) for $($buildDomains -join ', '): $Reason")
        }
    }

    $waitStartedAt = Get-Date
    $result = Enter-AgentLock @enterArgs
    if (-not $result.Acquired) {
        $s = $result.Status
        $waitTimedOut = ($result.PSObject.Properties.Name -contains 'WaitTimedOut' -and $result.WaitTimedOut)
        # S2109: name the domain that actually blocked. Without it a refusal about Build.Wear reads
        # as a refusal about the phone build, which is the misreading strategic 5.1 pillar F exists
        # to stop - already made twice on the two modules' fast checks.
        $blockedDomain = if ($result.PSObject.Properties['Domain'] -and $result.Domain) { $result.Domain } else { $buildDomains[0] }
        if ($ticketSet) {
            foreach ($buildDomainItem in $buildDomains) {
                if ($ticketSet[$buildDomainItem] -and $ticketSet[$buildDomainItem].path) {
                    Remove-Item -LiteralPath $ticketSet[$buildDomainItem].path -Force -ErrorAction SilentlyContinue
                }
            }
        }
        if ($waitTimedOut) {
            Write-Host "$($blockedDomain.ToUpper()).LOCK still not ours after ${WaitTimeoutSeconds}s - giving up without building." -ForegroundColor Red
        }
        else {
            Write-Host "$($blockedDomain.ToUpper()).LOCK held - refusing to start a second gradle build (fail-fast requested)." -ForegroundColor Red
        }
        # S1448: a Holder line for an absent lock file names a pid nobody holds. When the lock is
        # free and a foreign ticket owns the head, the head is the thing that is actually blocking,
        # so report that instead - it is what the waiter needs in order to judge its own wait.
        if ($s.Exists) {
            Write-Host "  Holder PID: $($s.Pid)  age: $([int]$s.AgeSeconds)s  reason: '$($s.Reason)'  host: $($s.Host)" -ForegroundColor Red
        }
        elseif ($result.PSObject.Properties['Turn'] -and $result.Turn) {
            $t = $result.Turn
            Write-Host "  $blockedDomain lock is free; the turn belongs to session $($t.HeadSessionId) ($($t.Reason))." -ForegroundColor Red
            Write-Host "  Head reservation window: $((Get-AgentLockTimings -Name $blockedDomain).ReservationMinutes) min." -ForegroundColor Gray
        }
        Write-Host "  Never run two gradle builds concurrently in one domain (daemon OOM / cache corruption - see CLAUDE.md)." -ForegroundColor Gray
        Write-Host "  Check status: $(Get-SzaInvocation 'locks/lock-status.ps1') -Name $blockedDomain" -ForegroundColor Gray
        # A wait that ran out of time inspected nothing - exit 2 "cannot verify", not 1 "failed".
        if ($waitTimedOut) { exit 2 }
        exit 1
    }

    $waitedSeconds = [int]((Get-Date) - $waitStartedAt).TotalSeconds
    # Name the domains every time, not only after a wait: the acquisition line is where an operator
    # reads which half of the tree this run serialises against (strategic 5.1 pillar F).
    $queueSuffix = if ($waitedSeconds -ge 3) { " after ${waitedSeconds}s in the queue" } else { '' }
    Write-Host "Build domains acquired: $($buildDomains -join ', ')$queueSuffix - starting." -ForegroundColor DarkGray
}
