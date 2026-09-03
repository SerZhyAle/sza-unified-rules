<#
.SYNOPSIS
    Acquire the code domains a changed file set belongs to, before a source/XML/build-file edit.

.DESCRIPTION
    S1432: the lock is ordered. When another session is mid-edit this no longer shrugs and lets
    you edit anyway - it takes a place in the queue and tells you where you stand. Editing the
    same tree from two sessions is what produces the divergence a single shared checkout exists
    to avoid, and serialised editing is the accepted price of not having separate trees.

    Queued is not idle: while you wait, do the work that needs no lock - reading, research,
    specs, catalog, log analysis. Take the lock immediately before an edit and release it right
    after, never for a whole ticket.

    S2338: "documentation" used to appear in that list and was wrong - a docs/ or dev/ edit does
    take Code.Scripts, because those are hand-edited with no finer mechanism over them. Specs are
    genuinely free, and for a stronger reason than "they are not code": PLAN/ is already exclusive
    per ticket (ticket-lease.ps1) and per journal (the catalog mutex), so the domain map exempts it
    outright and a PLAN-only set acquires nothing. Keep this list and that table in agreement -
    this message is read at the exact moment a queued session is looking for something to do, so a
    wrong item here is acted on rather than merely read.

    S2419: release is YOURS to make, with scripts/utils/exit-code-lock.ps1, the moment your edits
    are applied - not when the checks that follow them finish. post-change.ps1 also releases, now
    before its gate batch rather than in its trailing finally, but treat that as a backstop for a
    run that ended early: a caller who waits for it holds the domain through the verification
    predicates and roughly seven hundred lines of gates that only read the tree. Either release is
    owner-checked, so neither can ever take a lock belonging to another session.

.PARAMETER Reason
    What the lock is being taken for - shown to whoever inspects the lock or the queue.

.PARAMETER Wait
    Block here until the turn arrives instead of returning immediately. Prefer the background
    waiter (scripts/utils/wait-for-lock-turn.ps1) - blocking here spends the agent's turn.

.PARAMETER Handoff
    Path this script printed in its own exit-4 message (it writes the file). Adopt those
    tickets instead of enqueuing fresh ones - the post-grant re-run must retire the SAME ticket
    the waiter was granted on, not take a second place beside it (S2403). Domains the handoff
    no longer covers are enqueued as usual; an unusable handoff behaves like no handoff.

.NOTES
    Exit codes:
    0 - start editing. Three different states share this code, and only the first leaves you
        holding something to release.
        (a) The domains are acquired.
        (b) S2338: the changed set needs NO domain - every path in it is exempt (PLAN/, already
            exclusive per ticket lease and per catalog mutex). Nothing was enqueued, nothing was
            acquired, and there is nothing to release afterwards. The banner says "none".
        (c) The re-entrant cases below.
        Also returned when this session ALREADY holds
        every domain of the requested set (re-entrant call): nothing is enqueued and the existing
        locks stay yours (S1448). Holding only PART of the set tops up the missing domains
        directly when that is safe (S2200: every missing domain outranks every held one in
        canonical order) - the held domains are never released or re-queued for.
    2 - the resource name is not an accepted domain or bare type (S2109); nothing was enqueued.
    4 - queued: another session holds one of your domains, or you are not its queue head. Your
        ticket is in the queue; wait for your turn with scripts/utils/wait-for-lock-turn.ps1 (or
        re-run with -Wait). Do not edit sources yet. The domain this message names is the one
        observed to hold the set - resolved by Get-AgentLockBlockingDomain, never a placeholder
        such as the set's first domain (S2410); when no domain of the set is observably blocking,
        the message names the whole set and no single domain at all.

        Also returned, WITHOUT enqueueing anything, when this session holds a domain that
        outranks a domain still missing from the request (S2200) - granting that directly would
        require acquiring out of canonical order, which a symmetric session could deadlock
        against. Release the held domains and retake the full set (message names the two calls).

.EXAMPLE
    pwsh -NoProfile -File scripts/utils/enter-code-lock.ps1 -Reason "S0900: refactor BrowseViewModel"

.EXAMPLE
    pwsh -NoProfile -File scripts/utils/enter-code-lock.ps1 -Reason "S0900" -Wait -WaitTimeoutSeconds 600
#>
param(
    [Parameter(Mandatory)][string]$Reason,
    # S2109: the changed file set. The domains are DERIVED from it, so a wear edit, a phone edit
    # and a scripts edit no longer wait for each other. Naming no files keeps the pre-split
    # behaviour - the full code set - which is the safe default, not an oversight.
    [string[]]$Files,
    # Escape hatch for a caller that knows its domain but not its paths yet. A declared domain is
    # deliberately second-class (ADR-1): getting it wrong removes protection quietly.
    [string]$Domain,
    [switch]$Wait,
    [int]$WaitTimeoutSeconds = 1200,
    [string]$Handoff = ''
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\agent-lock.ps1"

if ($Domain) {
    $domains = @(Resolve-AgentLockDomains -Name $Domain)
    $derivedFrom = "declared -Domain $Domain"
}
elseif ($Files) {
    $domains = @(Resolve-CodeDomainsForPaths -Path $Files)
    # Count the paths the RESOLVER sees, not the parameter's element count: `pwsh -File` binds a
    # comma list as one string, so a five-file set reported itself as "1 changed path" - a line
    # that reads like the caller lost four of its files (S2170).
    $pathCount = @($Files | ForEach-Object { ([string]$_) -split ',' } |
        ForEach-Object { $_.Trim() } | Where-Object { $_ }).Count
    $derivedFrom = "derived from $pathCount changed path(s)"
}
else {
    $domains = @(Resolve-AgentLockDomains -Name 'Code')
    $derivedFrom = 'no file set given - taking the full code set'
}
# S2338: an empty set is a real answer, not a resolution failure - every path in it is exempt
# (PLAN/, which ticket-lease.ps1 and the catalog mutex already serialise). Handle it before the
# acquisition path below, which indexes $acquireDomains[0] and assumes at least one domain.
# Nothing is enqueued and nothing is acquired, so there is also nothing for the caller to release.
if ($domains.Count -eq 0) {
    Write-Host "Code domains: none  ($derivedFrom)" -ForegroundColor Green
    Write-Host "  This change set needs no code lock - every path in it is already exclusive by ticket lease or catalog mutex (S2338)." -ForegroundColor Green
    Write-Host "  Edit now; there is no lock to release afterwards." -ForegroundColor Gray
    exit 0
}

Write-Host "Code domains: $($domains -join ', ')  ($derivedFrom)" -ForegroundColor Cyan

foreach ($buildDomain in @(Resolve-AgentLockDomains -Name 'Build')) {
    $buildStatus = Get-AgentLockStatus -Name $buildDomain
    if ($buildStatus.Exists -and -not $buildStatus.Stale) {
        Write-Host "Notice: $($buildDomain.ToUpper()).LOCK is live (PID $($buildStatus.Pid), age $([int]$buildStatus.AgeSeconds)s, reason: '$($buildStatus.Reason)')." -ForegroundColor Yellow
        Write-Host "  A gradle build is running elsewhere - it may compile a half-written state if you edit now." -ForegroundColor Yellow
    }
}

# S1448/S2200 re-entrancy guard, mirroring the one Enter-BuildLockOrExit applies to BUILD.LOCK. A
# session that already holds part or all of the requested set must not enqueue behind itself for
# the part it already holds: it would exit 4, never be granted from the outside, and leave that
# ticket parked on the queue head forever (research/01, item 1) - the very state this ticket
# exists to remove, reached through a second door.
$topUp = Resolve-AgentLockTopUp -Domains $domains

if ($topUp.Missing.Count -eq 0) {
    Write-Host "Code domains $($domains -join ', ') already held by this session - reusing them, nothing queued." -ForegroundColor Green
    exit 0
}

if ($topUp.Held.Count -gt 0 -and -not $topUp.AscendingSafe) {
    # S2200: this session holds a domain that outranks one still missing. Granting the missing
    # one directly would require acquiring out of canonical order - the shape a symmetric session
    # (holding the low-ranked domain, needing the high-ranked one) could deadlock against. Refuse
    # before any ticket is written for the colliding domain, so nothing here can ever queue behind
    # this session's own lock (research/01, item 3).
    Write-Error "enter-code-lock: this session already holds $($topUp.Held -join ', '), which outranks missing domain(s) $($topUp.Missing -join ', ') in canonical order - acquiring them together without releasing risks a cross-session deadlock (S2200)." -ErrorAction Continue
    Write-Host "  Release the held domains and retake the full set in one call:" -ForegroundColor Yellow
    Write-Host "    $(Get-SzaInvocation 'locks/exit-code-lock.ps1')" -ForegroundColor Gray
    Write-Host "    $(Get-SzaInvocation 'locks/enter-code-lock.ps1') -Files <full changed set> -Reason '$Reason'" -ForegroundColor Gray
    exit 4
}

# Ascending top-up (or no overlap at all): only the missing domains need a ticket or an acquire -
# the held ones stay exactly as they are, never released, never re-queued for (research/01, item 2).
$acquireDomains = $topUp.Missing

# S1448: take the place in the queue BEFORE asking for the lock, exactly as
# Enter-BuildLockOrExit does. Two things depend on it. The ticket the acquire retires is then
# this session's own, so nothing of ours is left sitting on the queue head; and a session that
# released the lock and immediately wants it back queues BEHIND whoever was already waiting
# instead of stepping over them. The issuer below reuses this session's existing ticket, so
# asking twice keeps the place already earned rather than taking a second one.
#
# S2403: a handoff from this script's own earlier exit-4 takes priority over a fresh enqueue -
# in a runtime with no session id the re-run is a stranger to its own first ticket, and without
# the handoff it would enqueue beside it exactly like the waiter once did.
$tickets = @{}
if ($Handoff) {
    $tickets = Read-AgentLockTicketHandoff -Path $Handoff -Domains $acquireDomains
    if (-not $tickets) { $tickets = @{} }
}
$missingDomains = @($acquireDomains | Where-Object { -not $tickets.ContainsKey($_) })
if ($missingDomains.Count -gt 0) {
    $fresh = New-AgentLockTicketSet -Name 'Code' -Reason $Reason -Domains $missingDomains
    foreach ($d in $missingDomains) { $tickets[$d] = $fresh[$d] }
}
$ticket = $tickets[$acquireDomains[0]]

$result = Enter-AgentLock -Name 'Code' -Reason $Reason -Domains $acquireDomains -Tickets $tickets
if ($result.Acquired) {
    Write-Host "Code domains acquired: $($domains -join ', ') (reason: '$Reason')." -ForegroundColor Green
    exit 0
}

if ($Wait) {
    Write-Host "Code domains unavailable - queued at position $((Test-AgentLockTurnSet -Name 'Code' -Tickets $tickets -Domains $acquireDomains).Position), waiting up to ${WaitTimeoutSeconds}s.." -ForegroundColor DarkGray
    $waited = Enter-AgentLock -Name 'Code' -Reason $Reason -Domains $acquireDomains -Wait -WaitTimeoutSeconds $WaitTimeoutSeconds -Tickets $tickets
    if ($waited.Acquired) {
        Write-Host "Code domains acquired: $($domains -join ', ') (reason: '$Reason')." -ForegroundColor Green
        exit 0
    }
    foreach ($d in $acquireDomains) { Remove-Item -LiteralPath $tickets[$d].path -Force -ErrorAction SilentlyContinue }
}

$turn = Test-AgentLockTurnSet -Name 'Code' -Tickets $tickets -Domains $acquireDomains
# S2410: ask the SET what holds it, never substitute $acquireDomains[0]. Test-AgentLockTurnSet
# reports no blocking domain whenever this session is head in every queue - which is exactly the
# state a foreign LOCK produces - so the old fallback fired precisely when it was least entitled
# to guess. It was not a loss of precision but a false statement: the refusal named Code.Phone and
# then called it free in its own next line, while Code.Scripts, the domain actually held, appeared
# nowhere in the message. The wait it suggested therefore returned instantly with "your turn" and
# hit the same refusal again - four times in the measured session.
$blocked = Get-AgentLockBlockingDomain -Domains $acquireDomains -Turn $turn
# S2403: the ticket must survive the process boundary - the waiter this message instructs and the
# re-runs below it are all different pwsh processes, strangers to this one whenever no session id
# is inherited. The handoff file is the carrier; every suggested command names it. Written before
# the branches because all three of them hand it to the caller.
$handoffPath = Save-AgentLockTicketHandoff -Tickets $tickets -Reason $Reason

if ($null -eq $blocked) {
    # S2410, the third outcome: the acquire failed, yet no domain of the set carries a live lock
    # and this session is head in every queue - a concurrent acquire took and released one in the
    # gap. There is nothing here to wait FOR, so no domain is named and no waiter is suggested.
    # Naming one would name a free domain, and the queue-head line would be built from $null,
    # printing `session  (ticket #, waited 0m, reason: '')` - the empty holder S1448 removed from
    # the branch below, which reappeared here through the substituted domain.
    Write-Error "enter-code-lock: could not acquire $($acquireDomains -join ', ') - queued at position $($turn.Position). No domain of that set is held right now and this session is head in every queue, so the collision is transient." -ErrorAction Continue
    Write-Host "  Nothing to wait for - do not start a waiter. Re-run the same acquire with your ticket:" -ForegroundColor Yellow
    Write-Host "    $(Get-SzaInvocation 'locks/enter-code-lock.ps1') -Reason '$Reason'$(if ($Files) { " -Files '$($Files -join ',')'" }) -Handoff `"$handoffPath`"" -ForegroundColor Gray
    Write-Host "  Your ticket: #$($ticket.seq). The handoff keeps that place across the re-run - do not enqueue a second one." -ForegroundColor Yellow
    # S2372: no holder to name, so the chat is read per domain of the set rather than per session.
    foreach ($setDomain in $acquireDomains) { Write-AgentChatContext -AgentId '' -Domain $setDomain }
    [void](Send-AgentChatMessage -Kind wait -Domains $acquireDomains -Note "refused with no observable holder in $($acquireDomains -join ', '): $Reason")
    exit 4
}

$holder = Get-AgentLockStatus -Name $blocked

# S1448: name the blocker that actually exists. The message used to claim "held by another
# session" unconditionally and print a Holder line built from an absent lock file - which read
# as `Holder: session  (age 0s, reason: '')` and sent whoever read it looking for a holder that
# was not there. A free lock with a foreign queue head is a different fact and says so.
if ($holder.Exists -and -not $holder.Stale) {
    Write-Error "enter-code-lock: $blocked is held by another session - queued at position $($turn.Position), not yet your turn." -ErrorAction Continue
    Write-Host "  Holder: session $($holder.SessionId) (age $([int]$holder.AgeSeconds)s, reason: '$($holder.Reason)')." -ForegroundColor Yellow
    $holderChatId = [string]$holder.SessionId
}
else {
    $head = @(Get-AgentLockQueue -Name $blocked)[0]
    $reservationMinutes = (Get-AgentLockTimings -Name $blocked).ReservationMinutes
    $headWaitedMinutes = if ($head -and $head.enqueuedAt) {
        [int](([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [int64]$head.enqueuedAt) / 60000)
    }
    else { 0 }
    Write-Error "enter-code-lock: $blocked is free, but this session is not the queue head - queued at position $($turn.Position), not yet your turn." -ErrorAction Continue
    Write-Host "  Queue head: session $($head.sessionId) (ticket #$($head.seq), waited ${headWaitedMinutes}m, reason: '$($head.reason)')." -ForegroundColor Yellow
    Write-Host "  The head keeps the turn for up to ${reservationMinutes} min after the lock frees; after that the next live ticket may take it." -ForegroundColor Yellow
    $holderChatId = if ($head) { [string]$head.sessionId } else { '' }
}
# S2372: the refusal is the one moment the chat is worth reading - what the holder is on, and since
# when - and this wait is itself a trace for whoever queues next. Neither changes the verdict.
Write-AgentChatContext -AgentId $holderChatId -Domain $blocked
# S2413: the waiting session learns of a stalled holder before the operator does, and the chat lines
# above are exactly what made one look alive - its last message was fresh while its transcript had
# stopped ten minutes earlier. This says so outright. It changes no verdict: the refusal and its
# exit code are the same either way, and the queue is still the way through.
$stallVerdict = $null
try { $stallVerdict = Get-AgentLockStall -Name $blocked } catch { $stallVerdict = $null }
if ($stallVerdict) {
    $stallProcessNote = if ($stallVerdict.holderProcessAlive) {
        'its process is still running, so it is hung rather than gone'
    }
    else {
        'no process of its own is observable'
    }
    Write-Host ("  STALLED: that holder has been quiet {0}m (limit {1}m) while holding {2}m - {3}." -f
        $stallVerdict.quietMinutes, $stallVerdict.thresholdMinutes, $stallVerdict.heldMinutes, $stallProcessNote) -ForegroundColor Red
    Write-Host "  Waiting is still correct - the lock goes stale on its own and the waiter takes it. Say so in chat if it does not." -ForegroundColor Red
}
[void](Send-AgentChatMessage -Kind wait -Domains $acquireDomains -Note "queued at position $($turn.Position) for ${blocked}: $Reason")
$reservationMinutesHint = (Get-AgentLockTimings -Name $blocked).ReservationMinutes
Write-Host "  Your ticket: #$($ticket.seq). Wait in the background - the waiter TAKES the lock for you:" -ForegroundColor Yellow
Write-Host "    $(Get-SzaInvocation 'locks/wait-for-lock-turn.ps1') -Name $blocked -Reason '$Reason' -Acquire -Handoff `"$handoffPath`"" -ForegroundColor Gray
Write-Host "  Its exit means the lock is already yours - start editing, and release as usual." -ForegroundColor Gray
Write-Host "  Without -Acquire the turn waits for your next call instead, and the head reservation" -ForegroundColor Gray
Write-Host "  (${reservationMinutesHint} min) is spent on that round trip while the lock sits free:" -ForegroundColor Gray
Write-Host "    $(Get-SzaInvocation 'locks/enter-code-lock.ps1') -Reason '$Reason'$(if ($Files) { " -Files '$($Files -join ',')'" }) -Handoff `"$handoffPath`"" -ForegroundColor Gray
Write-Host "  Meanwhile do lock-free work: reading, research, specs, catalog, log analysis." -ForegroundColor Gray
Write-Host "  A docs/ or dev/ edit is NOT lock-free - it needs Code.Scripts (S2338)." -ForegroundColor Gray
exit 4
