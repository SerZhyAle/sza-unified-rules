<#
.SYNOPSIS
    Ticket leases for parallel /spec-next and /spec-do sessions (S1437).

.DESCRIPTION
    A lease marks one spec ticket as being worked by one agent session, so a sibling session
    ranking the same queue is offered a different ticket instead of duplicating the work.

    One file per lease under temp/SPEC-TICKET.LEASES/<Sxxxx>.json. A claim is an atomic file
    creation, not a check followed by a write: the gap between those two disk calls is exactly
    how two sessions take one ticket. Losing a claim is therefore a normal outcome (exit 3), not
    an error - the caller re-ranks with that id excluded and takes the next one.

    Ownership is a session, not a process, so liveness is the write time of that session's
    transcript. The rule itself is NOT restated here: Get-AgentTicketLiveness in
    scripts/utils/agent-lock.ps1 owns it, and a third copy of it would drift from the two that
    already exist. Timings likewise come from $Script:AgentLockTimings.SpecTicket.

    A stale lease is swept by whoever reads next - List, Status and Claim all sweep first. There
    is no watchdog process, matching the queue design in S1432.

S2404 - the claim hands its identity forward. In a no-session-id runtime (ZCode, a plain
shell, cron) the identity chain degrades to pid-<PID>, which dies with the claiming process
while the logical session keeps working the ticket; liveness is judged from wall-clock
evidence (lastSeenAt, chat, claimedAt) and never from the process, so the lease read live for
SessionStaleMinutes behind a pid nothing can act as. The claim therefore writes a per-claim
handoff file under temp/LEASE-HANDOFF/ and prints its path; the agent carries that path into
later invocations through -Handoff, the one session-scoped channel two processes of one
logical session share (S2403's conclusion, same pattern as temp/LOCK-HANDOFF). The test seam
FMS_TICKET_LEASE_ROOT overrides the root both directories live under.

.PARAMETER Verb
    Claim   - take the ticket. Atomic; idempotent for a lease this session already owns.
    Release - give it back. Owner-checked: a live foreign lease is refused.
    List    - ids only, one per line (or a JSON array under -Json). Feeds an exclusion list.
    Status  - human-readable holder map: ticket, session, host, last seen, reason.
    Sweep   - drop stale leases and report how many went.
    Clean   - drop every lease nothing alive still supports, and say why each one went or stayed.
              Clean adds keep-signals Sweep does not have - a headless child naming the ticket,
              a lock naming it - but it judges liveness by the SAME verdict and the SAME window
              as Claim (S2407). It carried a two-minute window of its own until then, which let
              one script answer "held by a live session" (Claim, exit 3) and "litter" (Clean)
              about one lease at one moment; a live interactive session lost a ticket to that.
              Right after the operator killed the runners, the flow is gone and its leases are
              simply litter - that case is -Force, whose contract is exactly a supervisor that
              watched the processes exit.

.PARAMETER Id
    Ticket id, Sxxxx. Required for Claim and Release.

.PARAMETER Reason
    Free text recorded in the lease, shown by Status. Defaults to the calling skill's name.

.PARAMETER Handoff
    Path printed by a successful Claim (S2404). In a runtime with no session id every pwsh
    invocation is its own "session", so the claiming process's identity is unreachable from
    the next invocation of the same logical session. A handoff file names the lease's owning
    sessionId: Claim uses it for the already-mine check and the heartbeat refresh, Release
    treats a handoff matching the lease owner as proof of succession and does not refuse on
    liveness. Invalid, expired or foreign handoffs are ignored and today's semantics apply.

.PARAMETER Json
    Emit machine-readable output instead of console text.

.PARAMETER StaleMinutes
    Liveness window. Defaults to $Script:AgentLockTimings.SpecTicket.SessionStaleMinutes.

.PARAMETER QuietMinutes
    Clean only. The window Clean judges liveness against. Unset (0) means the shared window,
    SpecTicket.SessionStaleMinutes - the one Claim uses, which is the whole point of S2407.

    A value BELOW that window is refused (exit 2) unless -Force is also passed. Narrowing the
    window redefines "dead" for somebody else's lease, and that is not a knob: measured
    2026-09-02, a sibling read a live session's chat, saw it had spoken two minutes earlier,
    passed -QuietMinutes 1 anyway and took its ticket. -Force already declares that leases go
    regardless of liveness, so pairing the two states out loud what narrowing does silently.
    A value at or above the window is accepted bare, because it only makes Clean keep longer.

.EXAMPLE
    pwsh -NoProfile -File scripts/spec_catalog/ticket-lease.ps1 -Verb Claim -Id S1234 -Reason "/spec-next"
    Takes S1234. Exit 0 on success, exit 3 when a live sibling got there first.

.EXAMPLE
    pwsh -NoProfile -File scripts/spec_catalog/ticket-lease.ps1 -Verb Status
    Prints which session holds which ticket and how long ago each was last seen.

.EXAMPLE
    pwsh -NoProfile -File scripts/spec_catalog/ticket-lease.ps1 -Verb Clean
    After killing the queue runners: drops the leases their dead children left behind, keeps the
    ones a live run or a held lock still vouches for. -Force drops the lot unconditionally.

.EXIT CODES
    0 - done: claimed, released, or reported.
    1 - error: unreadable store, bad argument shape, write failure.
    2 - refused to look: Clean was asked to judge liveness by a window narrower than the shared
        one without -Force, so it dropped nothing rather than apply a threshold of its own.
    3 - claim lost: a live foreign session already holds this ticket.
    4 - release refused: a live foreign session owns this lease (never returned under -Force).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Claim', 'Release', 'List', 'Status', 'Sweep', 'Clean')]
    [string]$Verb,

    [string]$Id,

    [string]$Reason = 'spec-picker',

    [string]$Handoff,

    [switch]$Json,

    # Release only: drop the lease even though its owner still looks live. Liveness here is the write
    # time of the owner's transcript, which cannot separate "still working" from "exited a minute ago" -
    # the file stops growing either way. A supervisor that spawned the owning process and watched it
    # exit knows what that heuristic cannot reach, and only such a caller may pass this. Never pass it
    # to clear a lease you merely believe is idle: that is what Sweep and the staleness window are for.
    [switch]$Force,

    [int]$StaleMinutes = 0,

    # Clean only - see .PARAMETER QuietMinutes. 0 means the shared liveness window.
    [int]$QuietMinutes = 0
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')

$ErrorActionPreference = 'Stop'

. (Get-SzaHarnessScript 'locks/agent-lock.ps1')

$timings = Get-AgentLockTimings -Name SpecTicket
if ($StaleMinutes -le 0) { $StaleMinutes = $timings.SessionStaleMinutes }

# S2407. Refused rather than obeyed: a narrower window is a private redefinition of "dead" applied
# to a lease this session does not own, and the refusal has to name why, because exit 2 means "did
# not look" and the caller must be able to tell that from "looked, found nothing to drop".
if ($Verb -eq 'Clean' -and $QuietMinutes -gt 0 -and $QuietMinutes -lt $timings.SessionStaleMinutes -and -not $Force) {
    # Built above the call so -ErrorAction Continue shares the Write-Error's physical line:
    # assert-exit-contract.ps1 reads that line, and a wrapped call reads as a terminating error
    # with an unreachable exit below it.
    $floorRefusal = "ticket-lease: -QuietMinutes $QuietMinutes is below the shared liveness window of $($timings.SessionStaleMinutes) min, " +
        'and a lease whose owner produced any evidence that recently is alive, not litter. ' +
        'Re-run without -QuietMinutes, or add -Force to state that leases go regardless of liveness.'
    Write-Error $floorRefusal -ErrorAction Continue
    exit 2
}

# Test seam (S2404): the hermetic suite points this at a throwaway root so a run never reads
# or writes the repository's real leases. Precedent: FMS_AGENT_CHAT_ROOT (S2372).
$root = (Get-SzaEnv 'TICKET_LEASE_ROOT')
if ([string]::IsNullOrWhiteSpace($root)) {
    $root = (Get-SzaProjectRoot)
}
$leaseDir = (Get-SzaPath 'leasesDir')
if (-not (Test-Path -LiteralPath $leaseDir)) {
    New-Item -ItemType Directory -Path $leaseDir -Force | Out-Null
}

function Get-SessionId {
    return Get-AgentSessionId
}

function Get-LeasePath {
    param([Parameter(Mandatory)][string]$TicketId)
    return (Join-Path $leaseDir "$TicketId.json")
}

function Read-Lease {
    param([Parameter(Mandatory)][string]$Path)
    try { return (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json) }
    catch { return $null }
}

function Save-TicketLeaseHandoff {
    <#
        S2404. Persist a lease's owning identity to a per-claim handoff file and return the path.
        The name is unique per claim (ticket + stamp + pid) on purpose: the path is the proof, and
        the only channel that carries it is the agent copying the printed output into its next
        command - a stable per-ticket name would make release a guessable path and the owner-check
        decorative. Nothing sweeps the directory; a stale file is inert because Read rejects it by
        age, exactly the LOCK-HANDOFF discipline (S2403).
    #>
    param(
        [Parameter(Mandatory)][string]$TicketId,
        [Parameter(Mandatory)][string]$SessionId
    )
    $dir = (Get-SzaPath 'leaseHandoffDir')
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $path = Join-Path $dir ("LEASE-HANDOFF-{0}-{1}-{2}.json" -f $TicketId, $stamp, $PID)
    $body = [ordered]@{
        schema    = 1
        id        = $TicketId
        sessionId = $SessionId
        createdAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        reason    = $Reason
    } | ConvertTo-Json -Compress
    $staging = "$path.tmp-$PID"
    Set-Content -LiteralPath $staging -Value $body -Encoding utf8NoBOM
    Move-Item -LiteralPath $staging -Destination $path -Force
    return $path
}

function Read-TicketLeaseHandoff {
    <#
        S2404. The sessionId a valid handoff names, or $null. Valid means: the file exists, parses,
        names THIS ticket (a handoff for another ticket proves nothing here), carries a sessionId,
        and is younger than the liveness window - an old handoff names a lease the sweep has long
        reclaimed, and honouring it would let a dead intent release a live successor's lease.
    #>
    param(
        [string]$Path,
        [string]$TicketId
    )
    # Not Mandatory on purpose: the verbs pass their possibly-empty -Id / -Handoff straight
    # through, and an empty value must degrade to "$null, nothing adopted", not fail binding.
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($TicketId)) { return $null }
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { return $null }
    if ($null -eq $raw) { return $null }
    if ([string]$raw.id -ne $TicketId) { return $null }
    if ([string]::IsNullOrWhiteSpace([string]$raw.sessionId) -or -not $raw.createdAt) { return $null }
    $ageMinutes = ((Get-Date) - [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$raw.createdAt).LocalDateTime).TotalMinutes
    if ($ageMinutes -gt $StaleMinutes) { return $null }
    return [string]$raw.sessionId
}

function Get-LeaseAgeMinutes {
    param([Parameter(Mandatory)]$Lease)
    if (-not $Lease.claimedAt) { return [double]::MaxValue }
    $claimed = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$Lease.claimedAt).LocalDateTime
    return ((Get-Date) - $claimed).TotalMinutes
}

function Test-LeaseOwnerHoldsLock {
    <#
        S1448. A session that holds CODE.LOCK or BUILD.LOCK with a reason naming this ticket id is
        working this ticket right now - that is direct proof, stronger than any inference from a
        transcript timestamp. Observed live: preflight offered S1436 as unleased while the owning
        session held CODE.LOCK with reason '/spec-dev S1436 step 06.2', and a sibling trusting that
        would have written the same ticket concurrently - exactly what the lease exists to stop.
    #>
    param([Parameter(Mandatory)]$Lease)

    $ownerSessionId = [string]$Lease.sessionId
    $ticketId = [string]$Lease.id
    if ([string]::IsNullOrWhiteSpace($ownerSessionId) -or [string]::IsNullOrWhiteSpace($ticketId)) { return $false }

    # S2109: scan every domain, not the two bare names. Research artifact 05 flagged this as one of
    # only two functional consumers of the lock name outside the library: after the split a session
    # holding Code.Wear writes no file under the bare name, so a check that looked only there would
    # find nothing, read a working session's lease as abandoned, and sweep it out from under it.
    $lockNames = @(Resolve-AgentLockDomains -Name 'Code') + @(Resolve-AgentLockDomains -Name 'Build') +
        @('Code', 'Build')
    foreach ($lockName in $lockNames) {
        $lock = Get-AgentLockStatus -Name $lockName
        if (-not $lock.Exists -or $lock.Stale) { continue }
        if ([string]$lock.SessionId -ne $ownerSessionId) { continue }
        if ([string]$lock.Reason -match [regex]::Escape($ticketId)) { return $true }
    }
    return $false
}

function Get-LeaseLiveness {
    # Get-AgentTicketLiveness falls back to $Ticket.enqueuedAt when the transcript is unreachable.
    # The lease's own field is claimedAt, so shim it across rather than storing the value twice.
    # S1448 adds lastSeenAt as the strongest signal, matching the queue-ticket precedence order.
    # S2407 adds -Window so Clean can be asked to judge against a WIDER window than $StaleMinutes
    # without growing a second copy of the verdict - the duplication that let Claim and Clean
    # disagree about one lease. Narrower is unreachable here: the parameter check at the top of
    # the script refuses it unless -Force was passed, and -Force drops every lease unjudged.
    param(
        [Parameter(Mandatory)]$Lease,
        [int]$Window = 0
    )
    $effectiveWindow = if ($Window -gt 0) { $Window } else { $StaleMinutes }
    $shim = [pscustomobject]@{
        sessionId      = $Lease.sessionId
        transcriptPath = $Lease.transcriptPath
        lastSeenAt     = $Lease.lastSeenAt
        enqueuedAt     = $Lease.claimedAt
    }
    $verdict = Get-AgentTicketLiveness -Ticket $shim -StaleMinutes $effectiveWindow
    if ($verdict -eq 'foreign-stale' -and (Test-LeaseOwnerHoldsLock -Lease $Lease)) { return 'foreign-live' }
    return $verdict
}

function New-LeaseDropRecord {
    <#
        S2407. One record per dropped lease, and the chat line that tells its owner. A lease is the
        only marker saying "someone is on this ticket", so taking one silently left its owner to
        discover the loss by collision: the chat context added by S2372 printed for the session
        that LOST a race, never for the session whose lease was taken. The post is best-effort and
        never alters the drop - Send-AgentChatMessage swallows its own failures by contract.
    #>
    param(
        [Parameter(Mandatory)][string]$TicketId,
        [string]$HolderSessionId = ''
    )
    $known = -not [string]::IsNullOrWhiteSpace($HolderSessionId)
    $mine = $known -and ($HolderSessionId -eq $effectiveSessionId)
    if ($known -and -not $mine) {
        # Fallback first, so a chat store that cannot answer still yields a usable name.
        $who = $HolderSessionId
        try { $who = Get-AgentChatDisplayName -Agent $null -Id $HolderSessionId } catch { }
        [void](Send-AgentChatMessage -Kind ticket -Ticket $TicketId -Note "dropped $TicketId held by $who")
    }
    return [pscustomobject]@{ id = $TicketId; heldBy = $HolderSessionId; mine = $mine }
}

function Write-LeaseDropNotice {
    <#
        S2407. Name the owner of every foreign lease this run dropped and print what it last said,
        through the same helper the refusal uses. Text mode only, and that is not a preference:
        List and Status sweep too, and a Write-Host between the lines of their -Json payload would
        be read as part of it.
    #>
    param([object[]]$Records = @())
    foreach ($record in $Records) {
        if ($record.mine -or [string]::IsNullOrWhiteSpace([string]$record.heldBy)) { continue }
        Write-Host ("ticket-lease: dropped {0}, held by session {1}." -f $record.id, $record.heldBy) -ForegroundColor Yellow
        Write-AgentChatContext -AgentId ([string]$record.heldBy)
    }
}

function Invoke-LeaseSweep {
    <#
        Drops a lease whose owning session has gone quiet, or which passed the absolute ceiling
        regardless of liveness - the case where a transcript keeps being written but the ticket
        itself was abandoned. Never drops on 'undetermined': that means WE have no session id,
        so "mine" and "theirs" are indistinguishable and eviction would be a guess.

        S2407: returns a record per drop (id, heldBy, mine) instead of a bare id, and announces
        each foreign drop in the chat through New-LeaseDropRecord.
    #>
    $removed = @()
    foreach ($file in (Get-ChildItem -LiteralPath $leaseDir -Filter '*.json' -ErrorAction SilentlyContinue)) {
        $lease = Read-Lease -Path $file.FullName
        if ($null -eq $lease) {
            # Grace window against catching a file mid-write: the writer renames into place, but a
            # reader that arrives between create and rename would otherwise delete a valid lease.
            $ageSeconds = ((Get-Date) - $file.LastWriteTime).TotalSeconds
            if ($ageSeconds -gt 60) {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
                $removed += (New-LeaseDropRecord -TicketId $file.BaseName)
            }
            continue
        }
        $liveness = Get-LeaseLiveness -Lease $lease
        if ($liveness -eq 'undetermined') { continue }
        $ageMinutes = Get-LeaseAgeMinutes -Lease $lease
        if ($liveness -eq 'foreign-stale' -or $ageMinutes -gt $timings.TicketCeilingMinutes) {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
            $removed += (New-LeaseDropRecord -TicketId ([string]$lease.id) -HolderSessionId ([string]$lease.sessionId))
        }
    }
    return $removed
}

function Get-LiveLeases {
    $out = @()
    foreach ($file in (Get-ChildItem -LiteralPath $leaseDir -Filter '*.json' -ErrorAction SilentlyContinue)) {
        $lease = Read-Lease -Path $file.FullName
        if ($null -eq $lease) { continue }
        $liveness = Get-LeaseLiveness -Lease $lease
        # S2372: every evidence of life counts - transcript, heartbeat, chat - through the one helper
        # Clean already judges by, so Status and Clean cannot disagree about the same lease.
        $quiet = Get-LeaseQuietMinutes -Lease $lease
        $lastSeenMinutes = if ($null -ne $quiet) { [math]::Round($quiet, 1) } else { $null }
        $out += [pscustomobject]@{
            id              = [string]$lease.id
            sessionId       = [string]$lease.sessionId
            host            = [string]$lease.host
            pid             = $lease.pid
            reason          = [string]$lease.reason
            claimedAt       = $lease.claimedAt
            ageMinutes      = [math]::Round((Get-LeaseAgeMinutes -Lease $lease), 1)
            lastSeenMinutes = $lastSeenMinutes
            liveness        = $liveness
            mine            = ($liveness -eq 'self')
        }
    }
    return ($out | Sort-Object id)
}

function Get-LiveRunTicketIds {
    <#
        Ticket ids named by the headless children running right now. This is the same evidence the
        queue monitor shows under "running", and it is the one signal that survives a long model
        turn: a child mid-turn writes no transcript line and touches no lock, so without it Clean
        would drop a lease out from under a run that is working perfectly.
    #>
    $ids = @()
    foreach ($proc in @((Get-SzaAgentProcesses))) {
        if (-not $proc.CommandLine) { continue }
        if ($proc.CommandLine -notmatch '\s-p\s') { continue }
        foreach ($m in [regex]::Matches([string]$proc.CommandLine, 'S\d{4}')) { $ids += $m.Value }
    }
    return @($ids | Sort-Object -Unique)
}

function Get-LeaseQuietMinutes {
    <#
        Minutes since the owning session last produced evidence of itself: its transcript's write
        time (the subagent subtree included, S2408), the lease's own heartbeat, its newest chat
        line, or the fact that its process is still running. $null means none of them exists,
        which is not the same as "quiet forever" - the caller decides what that is worth.
    #>
    param([Parameter(Mandatory)]$Lease)

    $marks = @()
    $transcript = [string]$Lease.transcriptPath
    # S2408: through the shared helper, which counts the owner's subagent transcripts as the owner
    # writing - the lock library reads the same one, so the two cannot disagree about one session.
    if (-not [string]::IsNullOrWhiteSpace($transcript)) {
        $transcriptMark = Get-AgentSessionTranscriptLastWrite -TranscriptPath $transcript
        if ($null -ne $transcriptMark) { $marks += $transcriptMark }
    }
    # S2408 decision 5: a running owner process is being observed right now, so the honest reading
    # is zero quiet minutes. Clean sweeps on quiet minutes rather than on the liveness verdict, so
    # without this the keep-signal would hold in Claim and not in Clean.
    try {
        $writtenAt = [datetime]::MinValue
        if ($Lease.claimedAt) {
            $writtenAt = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$Lease.claimedAt).LocalDateTime
        }
        if (Test-AgentIdentityProcessAlive -Id ([string]$Lease.sessionId) -NotStartedAfter $writtenAt) {
            $marks += (Get-Date)
        }
    }
    catch { }
    if ($Lease.lastSeenAt) {
        $marks += [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$Lease.lastSeenAt).LocalDateTime
    }
    # S2372 ADR-7: the owner's newest chat message is evidence of life too, read through the same
    # helper the lock library's liveness uses, so the lease and the lock agree on one agent.
    try {
        $chatSeen = Get-AgentChatLastSeen -AgentId ([string]$Lease.sessionId)
        if ($null -ne $chatSeen) { $marks += $chatSeen.ToLocalTime() }
    } catch { }
    if ($marks.Count -eq 0) { return $null }
    $newest = ($marks | Sort-Object -Descending | Select-Object -First 1)
    return ((Get-Date) - $newest).TotalMinutes
}

function Write-LeaseFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$TicketId,
        [Parameter(Mandatory)][string]$SessionId
    )
    $payload = [ordered]@{
        schema         = 1
        id             = $TicketId
        sessionId      = $SessionId
        host           = $env:COMPUTERNAME
        pid            = $PID
        reason         = $Reason
        claimedAt      = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        # S1448: refreshed by Update-LeaseHeartbeat on every verb this session runs against its
        # own lease. claimedAt stays frozen so the 480-minute ceiling cannot be extended.
        lastSeenAt     = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        transcriptPath = (Get-AgentSessionTranscriptPath -SessionId $SessionId)
    }
    $text = ($payload | ConvertTo-Json -Depth 4 -Compress)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    # CreateNew makes "does it exist" and "create it" one filesystem call, so two sessions racing
    # for one ticket cannot both win. The IOException below is the loser, not a fault.
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $bytes = $utf8NoBom.GetBytes($text)
        $stream.Write($bytes, 0, $bytes.Length)
    }
    finally { $stream.Dispose() }
}

function Update-LeaseHeartbeat {
    <#
        S1448. Refresh lastSeenAt on every lease this session owns, so a session that is plainly
        active - it just ran a lease verb - is never judged gone. Best-effort and write-then-rename:
        a reader that caught a half-written lease would treat it as unreadable.
    #>
    param([Parameter(Mandatory)][string]$SessionId)

    foreach ($file in (Get-ChildItem -LiteralPath $leaseDir -Filter '*.json' -ErrorAction SilentlyContinue)) {
        $lease = Read-Lease -Path $file.FullName
        if ($null -eq $lease -or [string]$lease.sessionId -ne $SessionId) { continue }
        try {
            $lease | Add-Member -NotePropertyName 'lastSeenAt' -NotePropertyValue ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Force
            $staging = "$($file.FullName).tmp-$PID"
            Set-Content -LiteralPath $staging -Value ($lease | ConvertTo-Json -Depth 4 -Compress) -Encoding utf8NoBOM -ErrorAction Stop
            Move-Item -LiteralPath $staging -Destination $file.FullName -Force -ErrorAction Stop
        }
        catch {
            # A missed refresh costs a delay, never a stuck ticket - the next verb retries.
        }
    }
}

$sessionId = Get-SessionId
# S2404: a valid handoff speaks as the identity that claimed the lease, so the heartbeat this
# invocation refreshes and the "already-mine" comparison below target that identity - this is
# the refresh path a no-session-id runtime was missing. An unusable handoff adopts nothing and
# every verb falls back to the caller's own identity, i.e. today's semantics.
$adoptedSessionId = Read-TicketLeaseHandoff -Path $Handoff -TicketId $Id
$effectiveSessionId = if ($adoptedSessionId) { $adoptedSessionId } else { $sessionId }
Update-LeaseHeartbeat -SessionId $effectiveSessionId

switch ($Verb) {

    'Claim' {
        if ([string]::IsNullOrWhiteSpace($Id)) {
            Write-Error 'ticket-lease: -Id is required for Claim.' -ErrorAction Continue
            exit 1
        }
        # S2407: the sweep that clears the way for this claim may have taken a sibling's lease.
        # Say so here rather than at the outcome - the drop is a fact whether or not the claim
        # below then succeeds, and the operator reading this run is the one who can act on it.
        $sweptForClaim = @(Invoke-LeaseSweep)
        if (-not $Json) { Write-LeaseDropNotice -Records $sweptForClaim }
        $path = Get-LeasePath -TicketId $Id

        if (Test-Path -LiteralPath $path) {
            $existing = Read-Lease -Path $path
            if ($null -ne $existing -and [string]$existing.sessionId -eq $effectiveSessionId) {
                # Re-claiming our own lease is a no-op, so a resumed round does not fight itself.
                # The handoff is rewritten on every no-op too: its age bound is the liveness
                # window, so a long ticket must not age out mid-session between phase boundaries.
                $handoffPath = Save-TicketLeaseHandoff -TicketId $Id -SessionId ([string]$existing.sessionId)
                if ($Json) { [pscustomobject]@{ outcome = 'already-mine'; id = $Id; sessionId = $effectiveSessionId; handoffPath = $handoffPath } | ConvertTo-Json -Compress }
                else {
                    Write-Host "ticket-lease: $Id already held by this session." -ForegroundColor DarkGray
                    Write-Host "ticket-lease: lease handoff: $handoffPath"
                }
                exit 0
            }
        }

        try {
            Write-LeaseFile -Path $path -TicketId $Id -SessionId $sessionId
        }
        catch [System.IO.IOException] {
            $holder = Read-Lease -Path $path
            $holderId = if ($holder) { [string]$holder.sessionId } else { 'unknown' }
            $holderHost = if ($holder) { [string]$holder.host } else { 'unknown' }
            # S2372: the refusal carries what the holder is doing, so the loser can decide between
            # waiting and other work without asking anyone. Best effort - the verdict stays exit 3.
            $holderChat = @()
            try { $holderChat = @(Get-AgentChatMessages -Stream all -AgentId $holderId -Last 3 | ForEach-Object { Format-AgentChatLine $_ }) } catch { $holderChat = @() }
            if ($Json) {
                [pscustomobject]@{ outcome = 'claim-lost'; id = $Id; heldBy = $holderId; host = $holderHost; holderChat = $holderChat } | ConvertTo-Json -Compress
            }
            else {
                Write-Host "ticket-lease: $Id already claimed by session $holderId on $holderHost." -ForegroundColor Yellow
                Write-AgentChatContext -AgentId $holderId
                # S2407: the rule belongs where it is already being read. The sibling that took
                # S2406 had exactly this block on screen, saw a chat row two minutes old, and
                # lowered Clean's window anyway - so a command file was the wrong place for it.
                Write-Host "ticket-lease: a chat row younger than $StaleMinutes min means the holder is alive - do not run Clean with a lowered -QuietMinutes to take this ticket." -ForegroundColor DarkGray
            }
            exit 3
        }

        [void](Send-AgentChatMessage -Kind ticket -Ticket $Id -Note "claimed ${Id}: $Reason")
        $handoffPath = Save-TicketLeaseHandoff -TicketId $Id -SessionId $sessionId
        if ($Json) { [pscustomobject]@{ outcome = 'claimed'; id = $Id; sessionId = $sessionId; handoffPath = $handoffPath } | ConvertTo-Json -Compress }
        else {
            Write-Host "ticket-lease: claimed $Id (session $sessionId)." -ForegroundColor Green
            Write-Host "ticket-lease: lease handoff: $handoffPath"
        }
        exit 0
    }

    'Release' {
        if ([string]::IsNullOrWhiteSpace($Id)) {
            Write-Error 'ticket-lease: -Id is required for Release.' -ErrorAction Continue
            exit 1
        }
        $path = Get-LeasePath -TicketId $Id
        if (-not (Test-Path -LiteralPath $path)) {
            if ($Json) { [pscustomobject]@{ outcome = 'absent'; id = $Id } | ConvertTo-Json -Compress }
            else { Write-Host "ticket-lease: $Id holds no lease." -ForegroundColor DarkGray }
            exit 0
        }

        $lease = Read-Lease -Path $path
        $liveness = if ($null -ne $lease) { Get-LeaseLiveness -Lease $lease } else { 'foreign-stale' }
        # S2404: a handoff naming this lease's owner is proof the caller succeeded the claiming
        # invocation - stronger than the liveness guess and weaker than -Force, which asserts a
        # supervised exit. A handoff naming anyone else proves nothing and the refusal stands.
        $handoffProof = ($null -ne $lease -and $null -ne $adoptedSessionId -and [string]$lease.sessionId -eq $adoptedSessionId)
        if ($liveness -eq 'foreign-live' -and -not $Force -and -not $handoffProof) {
            $holderId = [string]$lease.sessionId
            if ($Json) { [pscustomobject]@{ outcome = 'release-refused'; id = $Id; heldBy = $holderId } | ConvertTo-Json -Compress }
            else { Write-Host "ticket-lease: refusing to release $Id - live session $holderId owns it." -ForegroundColor Yellow }
            exit 4
        }

        $forced = ($liveness -eq 'foreign-live') -and -not $handoffProof
        $viaHandoff = $handoffProof -and ($liveness -eq 'foreign-live')
        Remove-Item -LiteralPath $path -Force
        [void](Send-AgentChatMessage -Kind ticket -Ticket $Id -Note "released $Id$(if ($forced) { ' (forced)' })$(if ($viaHandoff) { ' (via handoff)' })")
        if ($Json) { [pscustomobject]@{ outcome = 'released'; id = $Id; forced = $forced; viaHandoff = $viaHandoff } | ConvertTo-Json -Compress }
        elseif ($forced) { Write-Host "ticket-lease: force-released $Id (owner looked live; caller says its process exited)." -ForegroundColor Yellow }
        elseif ($viaHandoff) { Write-Host "ticket-lease: released $Id (via handoff from session $adoptedSessionId)." -ForegroundColor Green }
        else { Write-Host "ticket-lease: released $Id." -ForegroundColor Green }
        exit 0
    }

    'List' {
        [void](Invoke-LeaseSweep)
        $ids = @(@(Get-LiveLeases) | ForEach-Object { $_.id })
        if ($Json) { ConvertTo-Json -InputObject $ids -Compress }
        elseif ($ids.Count -eq 0) { Write-Host 'no leases held' }
        else { $ids | ForEach-Object { Write-Output $_ } }
        exit 0
    }

    'Status' {
        [void](Invoke-LeaseSweep)
        $leases = @(Get-LiveLeases)
        if ($Json) {
            ConvertTo-Json -InputObject @($leases) -Depth 5 -Compress
            exit 0
        }
        if ($leases.Count -eq 0) {
            Write-Host 'no leases held'
            exit 0
        }
        Write-Host "Ticket leases ($($leases.Count)):" -ForegroundColor Cyan
        foreach ($l in $leases) {
            $marker = if ($l.mine) { '>' } else { ' ' }
            $seen = if ($null -ne $l.lastSeenMinutes) { "last seen $($l.lastSeenMinutes) min ago" } else { 'last seen unknown' }
            $color = if ($l.mine) { 'Green' } else { 'Gray' }
            Write-Host ("  {0} {1}  {2} on {3}  ({4}, held {5} min)  {6}" -f `
                    $marker, $l.id, $l.sessionId, $l.host, $seen, $l.ageMinutes, $l.reason) -ForegroundColor $color
        }
        exit 0
    }

    'Clean' {
        # S2407: one window for both verbs. $QuietMinutes can only widen this - a narrower value
        # was refused at the top of the script unless -Force was passed, and -Force drops the lot
        # without consulting any window at all.
        $cleanWindow = if ($QuietMinutes -gt 0) { $QuietMinutes } else { $StaleMinutes }
        $liveTickets = @(Get-LiveRunTicketIds)
        $dropped = @()
        $kept = @()
        foreach ($file in (Get-ChildItem -LiteralPath $leaseDir -Filter '*.json' -ErrorAction SilentlyContinue)) {
            $lease = Read-Lease -Path $file.FullName
            $id = if ($null -ne $lease) { [string]$lease.id } else { $file.BaseName }

            $keepReason = $null
            if (-not $Force) {
                if ($null -eq $lease) {
                    # Unreadable can mean mid-write. The 60-second grace matches Invoke-LeaseSweep's,
                    # for the same reason: a reader arriving between create and rename must not delete
                    # a lease that is about to be valid.
                    if (((Get-Date) - $file.LastWriteTime).TotalSeconds -le 60) { $keepReason = 'unreadable but written seconds ago' }
                }
                elseif ($liveTickets -contains $id) { $keepReason = 'a running headless child names this ticket' }
                elseif (Test-LeaseOwnerHoldsLock -Lease $lease) { $keepReason = 'its owner holds a lock naming this ticket' }
                else {
                    $keepReason = switch (Get-LeaseLiveness -Lease $lease -Window $cleanWindow) {
                        'self' { 'this session owns it' }
                        'foreign-live' { 'its owner is live by the shared {0} min window' -f $cleanWindow }
                        # Invoke-LeaseSweep's invariant, which Clean did not carry: 'undetermined'
                        # means WE have no session id, so "mine" and "theirs" cannot be told apart
                        # and dropping would be a guess about which one this is.
                        'undetermined' { 'this session has no identity, so ownership cannot be judged' }
                        default { $null }
                    }
                    if ($null -eq $keepReason) {
                        # S2372 ADR-7: a chat message may only extend a life, never shorten one.
                        # Get-AgentTicketLiveness reads chat solely when the heartbeat and the
                        # transcript are both unreachable, while Get-LeaseQuietMinutes takes the
                        # newest of all three - so a lease the shared verdict calls stale is kept
                        # anyway while any single signal still falls inside the window.
                        $quiet = Get-LeaseQuietMinutes -Lease $lease
                        if ($null -ne $quiet -and $quiet -lt $cleanWindow) {
                            $keepReason = 'its owner produced evidence {0:N1} min ago' -f $quiet
                        }
                    }
                }
            }

            if ($keepReason) {
                $kept += [pscustomobject]@{ id = $id; reason = $keepReason }
                continue
            }
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
            $why = if ($Force) { 'forced' }
                elseif ($null -eq $lease) { 'unreadable' }
                else {
                    $quiet = Get-LeaseQuietMinutes -Lease $lease
                    if ($null -eq $quiet) { 'no live run, no transcript' }
                    else { 'no live run, owner quiet {0:N0} min against a {1} min window' -f $quiet, $cleanWindow }
                }
            $holderSessionId = if ($null -ne $lease) { [string]$lease.sessionId } else { '' }
            $record = New-LeaseDropRecord -TicketId $id -HolderSessionId $holderSessionId
            $dropped += [pscustomobject]@{ id = $id; reason = $why; heldBy = $record.heldBy; mine = $record.mine }
        }

        if ($Json) {
            [pscustomobject]@{ outcome = 'cleaned'; dropped = @($dropped); kept = @($kept) } | ConvertTo-Json -Depth 4 -Compress
            exit 0
        }
        foreach ($k in $kept) { Write-Host ("  kept    {0}  ({1})" -f $k.id, $k.reason) -ForegroundColor DarkGray }
        foreach ($d in $dropped) {
            Write-Host ("  dropped {0}  ({1})" -f $d.id, $d.reason) -ForegroundColor Yellow
            # S2407: the dropped line used to name neither the owner nor what it was doing, so the
            # operator taking a lease could not see whose work was being taken.
            if (-not $d.mine -and -not [string]::IsNullOrWhiteSpace([string]$d.heldBy)) {
                Write-Host ("          held by session {0}" -f $d.heldBy) -ForegroundColor Yellow
                Write-AgentChatContext -AgentId ([string]$d.heldBy) -Prefix '          chat:'
            }
        }
        if ($dropped.Count -eq 0 -and $kept.Count -eq 0) { Write-Host 'ticket-lease: no leases held.' }
        else { Write-Host ("ticket-lease: {0} dropped, {1} kept." -f $dropped.Count, $kept.Count) -ForegroundColor Cyan }
        exit 0
    }

    'Sweep' {
        $removed = @(Invoke-LeaseSweep)
        # S2407: `removed` keeps its shape - a flat id list existing readers already parse - and
        # `dropped` carries the owner beside each id for anyone who needs to name the victim.
        $removedIds = @($removed | ForEach-Object { [string]$_.id })
        if ($Json) { [pscustomobject]@{ outcome = 'swept'; removed = $removedIds; dropped = @($removed) } | ConvertTo-Json -Depth 4 -Compress }
        elseif ($removed.Count -eq 0) { Write-Host 'ticket-lease: nothing stale.' }
        else {
            Write-Host "ticket-lease: swept $($removed.Count) stale lease(s): $($removedIds -join ', ')" -ForegroundColor Yellow
            Write-LeaseDropNotice -Records $removed
        }
        exit 0
    }
}
