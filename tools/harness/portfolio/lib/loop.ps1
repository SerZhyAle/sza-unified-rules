# The run loop of the portfolio dispatcher (TASK-FLOW rules 41-47; S0015 V1-V9).
#
# Dot-source this file; it defines functions only, sets no preference and prints nothing.
#
#   Get-PqNextRank              ranks repositories and tickets across the portfolio; -CheckXrepo applies the
#                               dispatcher's cross-repository blocker check to a read-only preview.
#   Get-PqStoppedRepos          keys of enabled repositories whose shared queue stop file exists (rule 26).
#   Get-PqOccupiedRepos         checks run\repo-*.lock; returns keys of non-concurrent repositories held by live PIDs.
#   Get-PqWorkerSlot            reserves the first available worker slot k in 1..maxWorkers.
#   Set-PqWorkerState           updates run\worker-<k>.json with the worker's current repository and ticket.
#   Remove-PqWorkerState        removes run\worker-<k>.json.
#   Lock-PqRepo                 takes run\repo-<key>.lock for a non-concurrent repository pass.
#   Set-PqRepoLockPass          records the pass's runner process on that lock, so an orphaned pass keeps it held.
#   Unlock-PqRepo               releases run\repo-<key>.lock.
#   Get-PqDropMark              a dropped ticket's status, updated and spec-file time, read from the ledger files.
#   Get-PqDropChange            which of the three differs from the mark taken when the drop was made, or $null.
#   Invoke-PqLedgerWatch        one look at the named repositories' ledgers against the shared run\ledger-<key>.json:
#                               ticket.transition, ticket.created and ingest.ledgerDiff of rule 59 (S0082).
#   Start-PqLoop                the main execution loop of pq start (V1-V9).

# Consecutive provider-error passes per agent name. Declared here, never lazily in the loop: the runner is under strict
# mode, where even `$null -ne $script:PqProviderStreaks` throws "cannot be retrieved because it has not been set" until
# the variable exists, and that turn error dropped a ticket that had just closed Verified (S0035).
$script:PqProviderStreaks = @{}

# The rater and the escalation of rule 71 (TASK-FLOW 0.32, S0139), read by Start-PqLoop; loaded here so every loader of
# this file has them. They call agents.ps1 and events.ps1 at run time only.
. (Join-Path $PSScriptRoot 'rater.ps1')
. (Join-Path $PSScriptRoot '..\..\spec_catalog\lib\complexity-grade.ps1')

function Get-PqNextRank {
    param(
        [Parameter(Mandatory)]$Registry,
        [string]$HarnessRoot,
        [string[]]$Exclude = @(),
        [string[]]$Occupied = @(),
        [int]$Slots = -1,
        [int]$StopAfter = 0,
        # S0027: a named ticket 'key:id' (queue-file hold lines for it are bypassed, its repository is the only one ranked)
        # and a repository-only restriction 'key' (every hold kept); see Get-PqRank.
        [string]$NamedTicket = '',
        [string]$OnlyRepo = '',
        [switch]$FirstHead,
        [switch]$CheckXrepo,
        # Passed to Get-PqRank: refuse a head inside the walk (the loop's rule 52 check), see there.
        [scriptblock]$HeadFilter = $null,
        # Passed to Get-PqRank: offer the root of a refused ticket's blocker chain in its place (TASK-FLOW 0.38 section 16).
        [scriptblock]$HeadLift = $null,
        # Complete-scan picker payloads kept across immediate dispatch.skip retries of the same turn.
        [hashtable]$PickerCache = $null
    )
    if (-not $HarnessRoot) { $HarnessRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')) }
    if (@($Occupied).Count -eq 0) {
        $Occupied = Get-PqOccupiedRepos -Registry $Registry -ReadOnly
    }
    $byKey = @{}
    foreach ($r in @($Registry.repos)) { $byKey[[string]$r.key] = $r }

    # One ledger read per repository for the whole queue; a ledger that cannot be read in bulk is asked ticket by ticket.
    $ledgers = @{}
    $lookup = {
        param($repo, $id)
        if (-not $byKey.ContainsKey($repo)) { return @{ exists = $false; closed = $false } }
        if (-not $ledgers.ContainsKey($repo)) { $ledgers[$repo] = Get-PqLedgerStatuses -RepoPath $byKey[$repo].path -HarnessRoot $HarnessRoot }
        $ledger = $ledgers[$repo]
        if ($null -ne $ledger) {
            if (-not $ledger.ContainsKey($id)) { return @{ exists = $false; closed = $false } }
            return @{ exists = $true; closed = ([string]$ledger[$id] -cin @('Verified', 'Archived')) }
        }
        $rec = Get-PqTicketRecord -RepoPath $byKey[$repo].path -Id $id -HarnessRoot $HarnessRoot
        if ($null -eq $rec) { return @{ exists = $false; closed = $false } }
        return @{ exists = $true; closed = ([string]$rec.status -cin @('Verified', 'Archived')) }
    }

    $qp = Get-PqQueuePath $Registry
    # A named start reads the queue file for its hold lines only and never walks its rows, so the per-row ledger
    # lookup (one child process per repository) is not paid.
    $queueArgs = @{ Path = $qp; KnownRepos = (Get-PqKnownKeys $Registry) }
    if (-not $NamedTicket) { $queueArgs.TicketLookup = $lookup }
    $queue = Read-PqQueueFile @queueArgs
    $pickerCache = if ($null -ne $PickerCache) { $PickerCache } else { @{} }
    $provider = {
        param($Repo, $Ex, $ForceId)
        $a = @{ RepoPath = [string]$Repo.path; HarnessRoot = $HarnessRoot; Cache = $pickerCache }
        if (@($Ex).Count -gt 0) { $a.Exclude = [string[]]@($Ex) }
        if ($ForceId) { $a.ForceId = $ForceId }
        Get-PqPickerHead @a
    }

    # Rule 41 (robotDraftCap): the robot-filed Drafts past today's cap are read from the ledgers at every rank, so no
    # worker has to remember them and `pq next` shows what the loop will do. A named ticket is the owner's word and
    # is not held back.
    if (-not $NamedTicket) { $Exclude = [string[]]@(@($Exclude) + @(Get-PqIntakeCapped $Registry)) }

    $n = if ($Slots -ge 0) { $Slots } else { [int](Get-PqValue $Registry 'maxWorkers' 1) }
    $rankArgs = @{ Registry = $Registry; Queue = $queue; HeadProvider = $provider; Slots = $n; Exclude = $Exclude; Occupied = $Occupied; Stopped = (Get-PqStoppedRepos $Registry); StopAfter = $StopAfter }
    if ($NamedTicket) { $rankArgs.NamedTicket = $NamedTicket }
    if ($OnlyRepo) { $rankArgs.OnlyRepo = $OnlyRepo }
    if ($FirstHead) { $rankArgs.FirstHead = $true }
    if ($null -ne $HeadFilter) { $rankArgs.HeadFilter = $HeadFilter }
    if ($null -ne $HeadLift) { $rankArgs.HeadLift = $HeadLift }
    if ($CheckXrepo -and $null -eq $HeadFilter) {
        # The preview applies rule 52 inside the one walk, as the loop does, so that the lift of the blocker chain's root
        # shows in `pq dry-run` exactly as it will happen; Get-PqXrepoFilteredRank still re-ranks for what the walk's
        # filter cannot see (a second head of a concurrent repository in the fill).
        $previewSnaps = @{}
        $previewMemo = @{}
        $rankArgs.HeadFilter = { param($k, $i) Get-PqXrepoBlock -Registry $Registry -RepoKey $k -TicketId $i -Snapshots $previewSnaps }.GetNewClosure()
        if ($null -eq $HeadLift -and $null -ne (Get-Command Get-PqLiftTarget -ErrorAction Ignore)) {
            $rankArgs.HeadLift = { param($k, $i, $refusal) Get-PqLiftTarget -Registry $Registry -Refusal $refusal -Memo $previewMemo -Snapshots $previewSnaps }.GetNewClosure()
        }
    }
    if ($CheckXrepo) {
        $ranker = {
            param($blockedIds)
            $rankArgs.Exclude = [string[]]@($Exclude + $blockedIds)
            Get-PqRank @rankArgs
        }
        return (Get-PqXrepoFilteredRank -Registry $Registry -Ranker $ranker)
    }
    return (Get-PqRank @rankArgs)
}

# Keys of enabled repositories whose shared queue stop file (rule 26, paths.queueStopFile) exists: the owner's `rs`, or
# a release freeze that stopped the queue. It is read before a ticket is offered, because a start has to be refused
# on the owner's stop and not merely survive it: the runner a pass starts clears a shared stop only when a recorded run
# ended after it was written (S4464), and refuses to start - exit 3, nothing launched - when the stop is newer than
# the last run, so offering work there would only burn a launch. Only the shared file counts: an instance's own stop
# file is that instance's.
# A repository whose paths cannot be read is left to the picker, which reports it.
function Get-PqStoppedRepos($Registry) {
    $stopped = [Collections.Generic.List[string]]::new()
    foreach ($r in @($Registry.repos)) {
        if ((Get-PqValue $r 'enabled' $false) -ne $true) { continue }
        try { if ([IO.File]::Exists((Get-PqRepoPaths -RepoPath ([string]$r.path)).StopFile)) { $stopped.Add([string]$r.key) } }
        catch { }
    }
    return [string[]]@($stopped)
}

function Get-PqLocalDay([datetime]$Now = [datetime]::Now) {
    # The local calendar day, yyyy-MM-dd: the day a ledger row's `created` names, which the robot-filed cap counts by.
    return $Now.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
}

function Get-PqIntakeCapped($Registry, [string]$Day = '') {
    # The 'key:id' of every robot-filed Draft past its repository's cap for one local day (TASK-FLOW rule 41,
    # robotDraftCap; Get-PqRobotFiled of ledger-watch.ps1), over the enabled repositories. Read from the ledgers at
    # every rank and never remembered, so a restarted worker, a second worker and `pq next` exclude the same tickets,
    # and the list empties by itself when the day ends. A repository whose ledger cannot be read is left to the picker.
    if (-not $Day) { $Day = Get-PqLocalDay }
    $cap = [int](Get-PqValue $Registry 'robotDraftCap' 20)
    $keys = [Collections.Generic.List[string]]::new()
    foreach ($r in @($Registry.repos)) {
        if ((Get-PqValue $r 'enabled' $false) -ne $true) { continue }
        try {
            foreach ($id in @((Get-PqRobotFiled -RepoPath ([string]$r.path) -Day $Day -Cap $cap).capped)) { $keys.Add("$([string]$r.key):$id") }
        }
        catch { }
    }
    return [string[]]@($keys)
}

# Serialize short state-file transactions across terminals; a dead process releases the mutex.
function Invoke-PqStateLock([scriptblock]$Body) {
    $bytes = [Text.Encoding]::UTF8.GetBytes((Get-PqRoot).ToLowerInvariant())
    $name = 'sza-pq-' + [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    $mutex = [Threading.Mutex]::new($false, $name)
    $held = $false
    try {
        try { $held = $mutex.WaitOne(10000) }
        catch [Threading.AbandonedMutexException] { $held = $true }
        if (-not $held) { throw 'PortfolioStateBusy: state transaction timed out' }
        & $Body
    }
    finally {
        if ($held) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Test-PqProcessAlive([int]$ProcessId, $StartedAt) {
    if ($ProcessId -le 0) { return $false }
    $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $p) { return $false }
    return (-not $StartedAt -or $p.StartTime.ToUniversalTime().ToString('o') -ceq $StartedAt)
}

# The owners of these files are processes, not agent sessions: the dispatcher lives for the whole run, and the pass it
# started lives for the whole pass, so a process test is the right one here (unlike a lease or a code lock). A repository
# lock also names its pass: a dispatcher ended on its own leaves its runner running, and the repository stays occupied
# until that pass ends too (rule 60).
function Test-PqStateOwner($State) {
    if (Test-PqProcessAlive ([int](Get-PqValue $State 'pid' 0)) (Get-PqValue $State 'startedAt')) { return $true }
    return (Test-PqProcessAlive ([int](Get-PqValue $State 'passPid' 0)) (Get-PqValue $State 'passStartedAt'))
}

function Read-PqState([string]$Path) {
    try { return (ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path)) -DateKind String) }
    catch { return $null }
}

function Get-PqOccupiedRepos($Registry, [switch]$ReadOnly) {
    Invoke-PqStateLock {
        $root = Get-PqRoot
        $runDir = Join-Path $root 'run'
        if (-not [IO.Directory]::Exists($runDir)) { return [string[]]@() }
        $byKey = @{}
        foreach ($r in @($Registry.repos)) { $byKey[[string]$r.key] = $r }
        $occupied = [Collections.Generic.List[string]]::new()
        $locks = [IO.Directory]::GetFiles($runDir, 'repo-*.lock')
        foreach ($lf in $locks) {
            $fn = [IO.Path]::GetFileName($lf)
            if ($fn -match '^repo-(.+)\.lock$') {
                $k = $Matches[1]
                $rec = if ($byKey.ContainsKey($k)) { $byKey[$k] } else { $null }
                if ($null -ne $rec -and (Get-PqValue $rec 'concurrent' $false) -eq $true) {
                    continue
                }
                $locked = Test-PqStateOwner (Read-PqState $lf)

                if ($locked) {
                    $occupied.Add($k)
                }
                elseif (-not $ReadOnly) {
                    # Clean up stale lock of dead process
                    Remove-Item -LiteralPath $lf -Force -ErrorAction SilentlyContinue
                }
            }
        }
        return [string[]]@($occupied)
    }
}

function Reclaim-PqDeadWorker($WorkerState, [int]$Slot, [string]$Root) {
    try {
        $repo = [string]$WorkerState.repository
        $ticket = [string]$WorkerState.ticket
        $agent = [string]$WorkerState.agent
        $since = [string]$WorkerState.since
        $elapsedSec = 0.0
        if ($since) {
            try {
                $dt = [DateTimeOffset]::Parse($since)
                $elapsedSec = [Math]::Round(([DateTimeOffset]::UtcNow - $dt).TotalSeconds, 1)
            } catch { }
        }
        $orphanRow = [ordered]@{
            run = 'R-orphaned'
            pass = "P-orphaned-w$Slot"
            repo = $repo
            id = $ticket
            agent = $agent
            model = ''
            complexity = ''
            statusBefore = ''
            statusAfter = ''
            moved = $false
            outcome = 'orphaned'
            exitCode = -1
            minutes = [Math]::Round($elapsedSec / 60, 2)
            seconds = $elapsedSec
            finishedAt = Get-PqRunRowTime
            canon = ''
            plugin = ''
            registryHash = ''
            profileHash = ''
        }
        $runsJsonl = Join-Path $Root 'runs.jsonl'
        [IO.File]::AppendAllText($runsJsonl, (($orphanRow | ConvertTo-Json -Compress) + "`n"), [Text.Encoding]::UTF8)

        $orphanLog = Open-PqLog -Writer "w$Slot" -Run 'R-orphaned'
        try {
            $null = Write-PqEvent -Log $orphanLog -Ev 'pass.end' -Repo $repo -Id $ticket -Worker $Slot -Agent $agent -D ([ordered]@{
                exit = -1
                outcome = 'orphaned'
                moved = $false
                elapsed = $elapsedSec
            })
        }
        finally {
            Close-PqLog -Log $orphanLog
        }
        Write-Host "reclaimed dead worker $Slot file holding $repo`:$ticket - appended runs.jsonl row and pass.end (orphaned)" -ForegroundColor Yellow
    }
    catch {
        Write-Host "failed to record orphaned pass on dead worker $Slot reclamation: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Get-PqWorkerSlot($Registry) {
    Invoke-PqStateLock {
        $root = Get-PqRoot
        $runDir = Join-Path $root 'run'
        if (-not [IO.Directory]::Exists($runDir)) { $null = [IO.Directory]::CreateDirectory($runDir) }
        $max = [Math]::Max(1, [int](Get-PqValue $Registry 'maxWorkers' 1))
        for ($k = 1; $k -le $max; $k++) {
            $wf = Join-Path $runDir "worker-$k.json"
            $st = Read-PqState $wf
            if (-not (Test-PqStateOwner $st)) {
                if ($null -ne $st -and $st.ticket) {
                    Reclaim-PqDeadWorker -WorkerState $st -Slot $k -Root $root
                }
                Set-PqWorkerState -Slot $k
                return $k
            }
        }
        return $null
    }
}

function Update-PqWorkerSeen([int]$Slot) {
    Invoke-PqStateLock {
        $root = Get-PqRoot
        $runDir = Join-Path $root 'run'
        $wf = Join-Path $runDir "worker-$Slot.json"
        if ([IO.File]::Exists($wf)) {
            $state = Read-PqState $wf
            if ($null -ne $state -and (Test-PqStateOwner $state)) {
                $now = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                if ($state.PSObject.Properties['seen']) {
                    $state.seen = $now
                } else {
                    $state | Add-Member -NotePropertyName 'seen' -NotePropertyValue $now
                }
                $tmp = "$wf.$PID.tmp"
                [IO.File]::WriteAllText($tmp, ($state | ConvertTo-Json -Compress), [Text.Encoding]::UTF8)
                [IO.File]::Move($tmp, $wf, $true)
            }
        }
    }
}

function Set-PqWorkerState([int]$Slot, [string]$Repo = $null, [string]$Ticket = $null, [string]$Title = $null, [string]$Agent = $null, [string]$Carry = $null, [string]$CarryAgent = $null) {
    Invoke-PqStateLock {
        $root = Get-PqRoot
        $runDir = Join-Path $root 'run'
        if (-not [IO.Directory]::Exists($runDir)) { $null = [IO.Directory]::CreateDirectory($runDir) }
        $wf = Join-Path $runDir "worker-$Slot.json"
        $now = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        $obj = [ordered]@{
            pid = $PID
            startedAt = (Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
            repository = $Repo
            ticket = $Ticket
            title = $Title
            agent = $Agent
            since = $now
            seen = $now
        }
        # Rule 47 drain (S0082): a worker between two passes of a drained ticket says which, so another worker does
        # not honour the stop over it while the carry goes on.
        if ($Carry) { $obj.drainCarry = $Carry; $obj.carryAgent = $CarryAgent }
        $tmp = "$wf.$PID.tmp"
        [IO.File]::WriteAllText($tmp, (($obj | ConvertTo-Json -Compress)), [Text.Encoding]::UTF8)
        [IO.File]::Move($tmp, $wf, $true)
    }
}

# Reserve the repository and ticket together with the worker state. Ranking is only a snapshot: another
# worker can choose the same candidate before either has published its assignment.
# Rule 61: what the loop remembers of an occupancy it reported, so the `repo.free` that ends it carries the same
# `by` and `holderKind`, the seconds it lasted as `age`, and its start as `since`.
function New-PqOccupancyMark($Occ, [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow) {
    return @{ by = [string](Get-PqValue $Occ 'by' 'transcript'); holderKind = [string](Get-PqValue $Occ 'holderKind' 'unknown'); since = $Now }
}
function Get-PqRepoFreeData($Mark, [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow) {
    $since = [DateTimeOffset](Get-PqValue $Mark 'since' $Now)
    return [ordered]@{
        by = [string](Get-PqValue $Mark 'by' 'transcript'); holderKind = [string](Get-PqValue $Mark 'holderKind' 'unknown')
        age = [int][Math]::Max(0, [Math]::Floor(($Now - $since).TotalSeconds)); since = $since.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
}

# Why the last Request-PqWorkerAssignment of this process refused (rule 62's `dispatch.skip` reasons): `leased` when
# another worker holds the ticket, `maxWorkers` when the repository's or the provider's cap is full, '' when the
# worker's own slot was lost (nothing to report: the worker is ending).
$script:PqAssignmentWhy = ''
# A cap refusal is retried every 5 s; its `dispatch.skip` is written at most once a minute per repository, ticket and why.
$script:PqSkipSaid = @{}
function Test-PqSkipDue([string]$Key, [DateTime]$Now = [DateTime]::UtcNow, [int]$Seconds = 60) {
    if ($script:PqSkipSaid.ContainsKey($Key) -and ($Now - $script:PqSkipSaid[$Key]).TotalSeconds -lt $Seconds) { return $false }
    $script:PqSkipSaid[$Key] = $Now
    return $true
}
function Request-PqWorkerAssignment {
    param([int]$Slot, $Repo, [string]$Ticket, [string]$Title, [string]$Agent, [int]$AgentMax = 1)
    $script:PqAssignmentWhy = ''
    Invoke-PqStateLock {
        $runDir = Join-Path (Get-PqRoot) 'run'
        $own = Read-PqState (Join-Path $runDir "worker-$Slot.json")
        if ($null -eq $own -or [int](Get-PqValue $own 'pid' 0) -ne $PID -or -not (Test-PqStateOwner $own)) { return $false }
        $key = [string]$Repo.key
        $limit = if ((Get-PqValue $Repo 'concurrent' $false) -eq $true) { [int](Get-PqValue $Repo 'maxWorkers' 1) } else { 1 }
        $count = 0
        $agentCount = 0
        foreach ($file in [IO.Directory]::GetFiles($runDir, 'worker-*.json')) {
            $state = Read-PqState $file
            if (-not (Test-PqStateOwner $state)) { continue }
            if ((Get-PqValue $state 'agent') -ceq $Agent) { $agentCount++ }
            if ((Get-PqValue $state 'repository') -cne $key) { continue }
            if ((Get-PqValue $state 'ticket') -ceq $Ticket) { $script:PqAssignmentWhy = 'leased'; return $false }
            $count++
        }
        if ($count -ge $limit -or $agentCount -ge $AgentMax) { $script:PqAssignmentWhy = 'maxWorkers'; return $false }
        Set-PqWorkerState -Slot $Slot -Repo $key -Ticket $Ticket -Title $Title -Agent $Agent
        return $true
    }
}

function Remove-PqWorkerState([int]$Slot) {
    Invoke-PqStateLock {
        $root = Get-PqRoot
        $wf = Join-Path (Join-Path $root 'run') "worker-$Slot.json"
        if ((Get-PqValue (Read-PqState $wf) 'pid' 0) -eq $PID) {
            Remove-Item -LiteralPath $wf -Force -ErrorAction SilentlyContinue
        }
    }
}

function Lock-PqRepo([string]$RepoKey) {
    Invoke-PqStateLock {
        $root = Get-PqRoot
        $runDir = Join-Path $root 'run'
        if (-not [IO.Directory]::Exists($runDir)) { $null = [IO.Directory]::CreateDirectory($runDir) }
        $lf = Join-Path $runDir "repo-$RepoKey.lock"
        if (Test-PqStateOwner (Read-PqState $lf)) { return $null }
        $obj = [ordered]@{
            pid = $PID
            startedAt = (Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
            since = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        }
        $tmp = "$lf.$PID.tmp"
        [IO.File]::WriteAllText($tmp, (($obj | ConvertTo-Json -Compress)), [Text.Encoding]::UTF8)
        [IO.File]::Move($tmp, $lf, $true)
        return $lf
    }
}

# Records the runner process of the pass on the repository lock this dispatcher holds.
function Set-PqRepoLockPass([string]$LockFile, [int]$PassPid) {
    Invoke-PqStateLock {
        $state = Read-PqState $LockFile
        if ($null -eq $state -or (Get-PqValue $state 'pid' 0) -ne $PID) { return }
        $p = Get-Process -Id $PassPid -ErrorAction SilentlyContinue
        if ($null -eq $p) { return }
        $obj = [ordered]@{
            pid = $state.pid
            startedAt = $state.startedAt
            since = $state.since
            passPid = $PassPid
            passStartedAt = $p.StartTime.ToUniversalTime().ToString('o')
        }
        $tmp = "$LockFile.$PID.tmp"
        [IO.File]::WriteAllText($tmp, (($obj | ConvertTo-Json -Compress)), [Text.Encoding]::UTF8)
        [IO.File]::Move($tmp, $LockFile, $true)
    }
}

function Unlock-PqRepo([string]$LockFile) {
    Invoke-PqStateLock {
        if ($LockFile -and (Get-PqValue (Read-PqState $LockFile) 'pid' 0) -eq $PID) {
            Remove-Item -LiteralPath $LockFile -Force -ErrorAction SilentlyContinue
        }
    }
}

# A pass child is stripped of the starting agent's session by Remove-PqAgentSessionEnv (picker.ps1), as every other
# repository child is.

# A pass the dispatcher killed never reaches the runner's own finally block, which releases the lease the runner took
# for its child (run-spec-queue.ps1, "Release the lease the child claimed"). The dispatcher started that runner and
# watched it die, so the release is its to make - and only for a lease this pass itself made, whose reason is
# 'run-spec-queue <instance>'. Left alone, the ticket stays leased for the shared liveness window (45 minutes) and the
# rank skips the very ticket the owner just stopped. Returns $true when a lease was released. Never throws.
function Remove-PqKilledPassLease {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string]$TicketId,
        [Parameter(Mandatory)][string]$Instance,
        [string]$HarnessRoot
    )
    try {
        $paths = Get-PqRepoPaths -RepoPath $RepoPath
        $file = Join-Path $paths.LeasesDir "$TicketId.json"
        if (-not [IO.File]::Exists($file)) { return $false }
        $lease = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($file))
        if ([string]$lease.reason -cne "run-spec-queue $Instance") { return $false }
        $script = Join-Path (Get-PqHarnessRoot $HarnessRoot) 'locks\ticket-lease.ps1'
        $r = Invoke-PqRepoChild -RepoPath $RepoPath -Script $script -Arguments @('-Verb', 'Release', '-Id', $TicketId, '-Force') -TimeoutSeconds 60
        return (-not $r.timedOut -and $r.code -eq 0)
    }
    catch { return $false }
}

function Invoke-PqPassChild {
    param(
        [Parameter(Mandatory)][string]$Script,
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string]$TicketId,
        [string]$TicketTitle = '',
        [string]$Instance = 'pq1',
        [Parameter(Mandatory)][string]$PermissionMode,
        # Called once the child runs, with its pid and its launch line (the runner script and its arguments).
        [scriptblock]$OnStarted,
        # The agent of the pass, when it is not claude (Get-PqAgentPassArgs): it carries its own -ModelPolicy.
        [string[]]$AgentArgs = @(),
        # Called about every three seconds while the pass runs (the loop reads the session the pass runs under from it).
        [scriptblock]$OnTick,
        # Called about every second; returns the stop that applies to this pass (Get-PqApplicableStop) or $null. Without
        # it only the whole-portfolio STOP is read, as before levels existed.
        [scriptblock]$StopWatcher,
        # Called about once a minute on the beat loop; emits pass.beat event and refreshes worker seen timestamp.
        [scriptblock]$OnBeat,
        # Print what the agent does while the pass runs (console.ps1, the built-in `pq tail`): 'claude' reads the session
        # transcript (the z.ai agent is the same CLI), 'codex' the rollout file Codex writes. Empty = no view; an agent with
        # no live file (Gemini, Mistral) keeps the minute line as its only sign.
        [ValidateSet('', 'claude', 'codex')][string]$Follow = '',
        # The agent record that took the pass (claude, claude-api, zai, codex, ..). The runner prints it in its banner:
        # a plain claude pass carries no -AgentJson, so without this the runner cannot tell which provider it works for.
        [string]$Agent = ''
    )
    # A registry record may spell the drive letter in lower case; the agent CLI would then see an untrusted workspace.
    $RepoPath = ConvertTo-PqFullPath $RepoPath
    $pwsh = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
    $psi = [Diagnostics.ProcessStartInfo]::new($pwsh)
    $passArgs = @('-NoProfile', '-File', $Script, '-RepoRoot', $RepoPath, '-Ids', $TicketId, '-MaxTickets', '1', '-Instance', $Instance)
    $AgentArgs = @(@($AgentArgs) | Where-Object { $null -ne $_ })
    if ($AgentArgs.Count -gt 0) { $passArgs += $AgentArgs } else { $passArgs += @('-ModelPolicy', 'shape') }
    if ($PermissionMode) { $passArgs += @('-PermissionMode', $PermissionMode) }
    foreach ($a in $passArgs) { $psi.ArgumentList.Add([string]$a) }
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = $RepoPath
    $psi.Environment['SZA_PROJECT_ROOT'] = $RepoPath
    # A usage limit ends the pass instead of being waited out inside the runner: the worker holds that provider and
    # gives the ticket to the next one of agentOrder (rule 48).
    $psi.Environment['SZA_PQ_EXIT_ON_LIMIT'] = '1'
    # Which provider this pass works for, for the runner's banner only. An environment variable, not a runner parameter, so
    # a runner script that does not know it still starts; one left over from the worker's own environment is dropped.
    if ($Agent) { $psi.Environment['SZA_PQ_AGENT'] = $Agent } else { [void]$psi.Environment.Remove('SZA_PQ_AGENT') }
    # One harness copy per pass (S0134): a repository's forwarder reads SZA_HARNESS_ROOT before the plugin cache, so
    # the agent's own ledger and lease calls run the copy this worker and its runner run. Set for the pass child only,
    # never in the user environment: a folder without a profile would then resolve this tree as its project root.
    $psi.Environment['SZA_HARNESS_ROOT'] = (Get-PqHarnessRoot '')
    [void]$psi.Environment.Remove('SZA_PROFILE_PATH')
    Remove-PqAgentSessionEnv $psi.Environment
    $proc = $null
    $killed = $false
    $halted = $false
    try {
        $proc = [Diagnostics.Process]::Start($psi)
        if ($OnStarted) { $null = & $OnStarted $proc.Id (@($Script) + $passArgs) }
        # Short waits let PowerShell process Ctrl+C. A cancelled dispatcher must not orphan its runner.
        # The agent CLI prints its answer only when it finishes, so the session transcript is the live source (-Follow);
        # a minute-by-minute line is what stays when nothing was printed from it for a minute.
        $passSw = [Diagnostics.Stopwatch]::StartNew()
        $beatAt = 60
        $stopAt = 0.0
        $tickAt = 0.0
        $followAt = 0.0
        $lastLineAt = 0.0
        $follower = $null
        if ($Follow -and (Get-Command Step-PqPassFollower -ErrorAction SilentlyContinue)) {
            try { $follower = New-PqPassFollower -RepoPath $RepoPath -TicketId $TicketId -Since ([DateTime]::Now) -Kind $Follow } catch { $follower = $null }
        }
        $titlePart = if ($TicketTitle) { " - $TicketTitle" } else { '' }
        try { $host.UI.RawUI.WindowTitle = "pass $Instance $TicketId$titlePart" } catch { }
        while (-not $proc.WaitForExit(250)) {
            $elapsedNow = $passSw.Elapsed.TotalSeconds
            if ($null -ne $follower -and $elapsedNow -ge $followAt) {
                $followAt = $elapsedNow + 2
                # A view must never fail a pass: whatever goes wrong in it only ends the view.
                try {
                    foreach ($fl in @(Step-PqPassFollower -State $follower)) {
                        $flColor = switch ($fl.Substring(0, 1)) { '>' { 'White' } '!' { 'Red' } '(' { 'DarkGray' } default { 'DarkCyan' } }
                        Write-Host ('{0:HH:mm:ss} {1}' -f [DateTime]::Now, $fl) -ForegroundColor $flColor
                        $lastLineAt = $elapsedNow
                    }
                }
                catch [Management.Automation.PipelineStoppedException] { throw }
                catch { $follower = $null }
            }
            if ($elapsedNow -ge $beatAt) {
                if ($null -eq $follower -or ($elapsedNow - $lastLineAt) -ge 60) {
                    Write-Host ('pass {0} {1}{2} - still running, {3:hh\:mm\:ss} elapsed' -f $Instance, $TicketId, $titlePart, $passSw.Elapsed) -ForegroundColor DarkGray
                }
                $beatAt += 60
                if ($OnBeat) { try { & $OnBeat ([Math]::Round($elapsedNow, 1)) } catch { } }
            }
            if ($OnTick -and $elapsedNow -ge $tickAt) {
                $tickAt = $elapsedNow + 3
                try { $null = & $OnTick } catch { }
            }
            # The stop files are read on a one-second tick (rule 47). Only `halt` and `kill` act on a pass in flight: a
            # `halt` has no polite interrupt to send (every agent record says halt none), so it degrades to the kill at once.
            if ($elapsedNow -ge $stopAt) {
                $stopAt = $elapsedNow + 1
                $stopLevel = ''
                if ($StopWatcher) { $applicable = & $StopWatcher; if ($null -ne $applicable) { $stopLevel = [string]$applicable.level } }
                else { $stopLevel = [string](Get-PqValue (Read-PqState (Get-PqPath -Kind stop)) 'level' '') }
                if ($stopLevel -cin @('kill', 'halt')) {
                    # Also covers a stop during runner startup, before its own stop-file reader is ready.
                    $proc.Kill($true)
                    $proc.WaitForExit()
                    $killed = $true
                    $halted = ($stopLevel -ceq 'halt')
                }
            }
        }
        return @{ code = $proc.ExitCode; pid = $proc.Id; killed = $killed; halted = $halted; failed = $false }
    }
    catch [Management.Automation.PipelineStoppedException] { throw }
    catch {
        return @{ code = 2; pid = $null; killed = $false; halted = $false; failed = $true }
    }
    finally {
        if ($null -ne $proc) {
            if (-not $proc.HasExited) { $proc.Kill($true); $null = $proc.WaitForExit(10000); $killed = $true }
            $proc.Dispose()
        }
        # Covers both ways a pass is cut short: a kill-level stop and an interrupted dispatcher (Ctrl+C).
        if ($killed) { $null = Remove-PqKilledPassLease -RepoPath $RepoPath -TicketId $TicketId -Instance $Instance }
    }
}

function Read-PqPassOutcome {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string]$Instance,
        [Parameter(Mandatory)][string]$TicketId,
        [Parameter(Mandatory)][string]$StatusBefore,
        [Parameter(Mandatory)][int]$ChildExitCode,
        [string]$HarnessRoot,
        [long]$JournalOffset = 0
    )
    $rows = [Collections.Generic.List[object]]::new()
    try {
        $paths = Get-PqRepoPaths -RepoPath $RepoPath
        $jf = Join-Path $paths.RunsDir "runs-$Instance.jsonl"
        if ([IO.File]::Exists($jf)) {
            $stream = [IO.File]::Open($jf, 'Open', 'Read', 'ReadWrite')
            try {
                $null = $stream.Seek($JournalOffset, 'Begin')
                $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8)
                try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
            }
            finally { $stream.Dispose() }
            foreach ($line in $text -split "`n") {
                if (-not $line.Trim()) { continue }
                try {
                    $parsed = ConvertFrom-Json -InputObject $line.Trim() -DateKind String
                    if ($parsed.id -ceq $TicketId) { $rows.Add($parsed) }
                }
                catch { continue }
            }
        }
    }
    catch { }

    $journalRow = if ($rows.Count) { $rows[$rows.Count - 1] } else { $null }
    $statusAfter = $StatusBefore
    $rec = Get-PqTicketRecord -RepoPath $RepoPath -Id $TicketId -HarnessRoot $HarnessRoot
    if ($null -ne $rec) { $statusAfter = [string]$rec.status }
    $moved = ($statusAfter -cne $StatusBefore)
    $outcome = [string](Get-PqValue $journalRow 'outcome' '')
    $agentExit = if ($null -ne $journalRow -and $null -ne $journalRow.PSObject.Properties['exitCode']) { $journalRow.exitCode } else { $null }
    $limits = @($rows | Where-Object { $_.outcome -ceq 'limit-hit' }).Count
    # Exit 5: the runner found the provider's usage limit already in force and launched nothing (-ExitOnLimit).
    if ($ChildExitCode -eq 5) { $outcome = 'limit-hit'; $limits = [Math]::Max(1, $limits) }
    # A runner whose claim was lost to a sibling launched nothing and exits 3 (rule 27); its row says so (rule 46).
    elseif ($ChildExitCode -ne 0 -and $outcome -cnotin @('limit-hit', 'provider-error', 'killed', 'halted', 'timeout', 'launch-failed', 'claim-lost', 'claim-lost-before-launch')) {
        $outcome = 'child-failed'
    }
    elseif (-not $outcome -or $outcome -ceq 'ok') { $outcome = if ($moved) { 'ok' } else { 'no-progress' } }
    $fold = Merge-PqPassUsage -Rows $rows
    return [ordered]@{
        model = [string](Get-PqValue $journalRow 'model' '')
        complexity = [string](Get-PqValue $journalRow 'complexity' '')
        statusAfter = $statusAfter
        moved = $moved
        outcome = $outcome
        exitCode = $agentExit
        launches = $rows.Count
        limits = $limits
        usage = $fold.usage
        costUsd = $fold.costUsd
        priceAsOf = $fold.priceAsOf
    }
}

# TASK-FLOW 0.20 rule 46 (S0037): rule 23's optional usage / costUsd / priceAsOf folded over every launch of a pass
# (an old row's built field, withdrawn in 0.36, is ignored). Usage summed, a launch whose usage.session repeats counted once,
# complete=false when any launch has none; costUsd only when every launch has one, priceAsOf the oldest. $null = absent.
function Merge-PqPassUsage($Rows) {
    $sum = [ordered]@{ model = ''; input = [int64]0; output = [int64]0; cacheRead = [int64]0; cacheWrite = [int64]0; requests = 0; complete = $true }
    $models = [Collections.Generic.List[string]]::new()
    $sessions = [Collections.Generic.HashSet[string]]::new()
    $any = $false
    $cost = 0.0
    $costKnown = $true
    $priceAsOf = $null
    foreach ($row in @($Rows)) {
        if ($null -eq $row) { continue }
        $u = Get-PqValue $row 'usage' $null
        if ($null -eq $u) { $sum.complete = $false; $costKnown = $false; continue }
        $session = [string](Get-PqValue $u 'session' '')
        if ($session -and -not $sessions.Add($session)) { continue }
        $any = $true
        foreach ($k in @('input', 'output', 'cacheRead', 'cacheWrite')) { $sum[$k] += [int64](Get-PqValue $u $k 0) }
        $sum.requests += [int](Get-PqValue $u 'requests' 0)
        if (-not [bool](Get-PqValue $u 'complete' $false)) { $sum.complete = $false }
        foreach ($m in @(([string](Get-PqValue $u 'model' '')) -split '\+')) { if ($m -and -not $models.Contains($m)) { $models.Add($m) } }
        $c = Get-PqValue $row 'costUsd' $null
        $asOf = [string](Get-PqValue $row 'priceAsOf' '')
        if ($null -eq $c) { $costKnown = $false }
        else {
            $cost += [double]$c
            if ($asOf -and (-not $priceAsOf -or [string]::CompareOrdinal($asOf, $priceAsOf) -lt 0)) { $priceAsOf = $asOf }
        }
    }
    if (-not $any) { return [ordered]@{ usage = $null; costUsd = $null; priceAsOf = $null } }
    $sum.model = $models -join '+'
    if (-not $costKnown) { $priceAsOf = $null }
    return [ordered]@{ usage = $sum; costUsd = $(if ($costKnown) { [Math]::Round($cost, 4) } else { $null }); priceAsOf = $priceAsOf }
}

# The drop of rule 43 (S0016 R31): a ticket that came back unmoved stays out of the rank until its status, its `updated`
# or its spec file's modification time differs from what they were when the pass ended. The mark is taken after the
# pass, so the pass's own writes never lift its own drop. Read from the ledger files directly (no child process), so a
# waiting worker can look once a poll at no cost. $null when the ticket or its ledger cannot be read; a drop whose mark
# is $null stays for the run, as it did before marks existed.
function Get-PqDropMark {
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][string]$TicketId, $Snapshot)
    try {
        $snap = if ($null -ne $Snapshot) { $Snapshot } else { Get-PqLedgerSnapshot -RepoPath $RepoPath }
        if (-not $snap.complete -or -not $snap.tickets.Contains($TicketId)) { return $null }
        $t = $snap.tickets[$TicketId]
        $specMtime = $null
        $specFile = ''
        if ($t.file) {
            $f = Resolve-PqRepoPathValue $snap.root ([string]$t.file)
            if ([IO.File]::Exists($f)) { $specMtime = [IO.File]::GetLastWriteTimeUtc($f).ToString('o'); $specFile = $f }
        }
        # specFile is not part of the comparison (Get-PqDropChange); a waiting poll watches that file (Get-PqDropFingerprint).
        return [ordered]@{ status = [string]$t.status; updated = [string]$t.updated; specMtime = [string]$specMtime; specFile = $specFile }
    }
    catch { return $null }
}

function Get-PqDropChange($Mark, $Current) {
    if ($null -eq $Mark -or $null -eq $Current) { return $null }
    if ($Current.status -cne $Mark.status) { return 'status' }
    if ($Current.updated -cne $Mark.updated) { return 'updated' }
    if ($Current.specMtime -cne $Mark.specMtime) { return 'specMtime' }
    return $null
}

function Get-PqCarriedDrops {
    # The drops a worker inherits when it continues a run that ended for a code change (S0105). Derived, never stored:
    # the writer's own event files are read newest line first. A run whose run.end carries the restart exit code is one
    # link of the chain; the first run that ended any other way, or never ended, closes it. Per ticket the newest
    # ticket.dropped or ticket.dropLifted of the chain decides; a drop written with no mark is not carried (nothing could
    # ever lift it). -> 'repo:id' -> @{ repo; id; mark }, the shape of the loop's $drops, with mark.specFile '' (the
    # caller fills it); empty on a failed read.
    param([Parameter(Mandatory)][string]$LogDir, [Parameter(Mandatory)][string]$Writer, [string]$SkipRun = '')
    $carried = @{}
    try {
        if (-not [IO.Directory]::Exists($LogDir)) { return $carried }
        $files = [string[]]@([IO.Directory]::GetFiles($LogDir, "events-*.$Writer.jsonl"))
        [Array]::Sort($files, [StringComparer]::Ordinal)
        $decided = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $restart = [string](Get-PqRestartExitCode)
        $chainRun = ''
        $chainOk = $false
        for ($fi = $files.Length - 1; $fi -ge 0; $fi--) {
            $fs = [IO.FileStream]::new($files[$fi], [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
            try { $text = [IO.StreamReader]::new($fs, [Text.UTF8Encoding]::new($false)).ReadToEnd() } finally { $fs.Dispose() }
            $lines = $text.Split("`n")
            for ($i = $lines.Length - 1; $i -ge 0; $i--) {
                $line = $lines[$i]
                if ($line.IndexOf('"ev":"run.', [StringComparison]::Ordinal) -lt 0 -and $line.IndexOf('"ev":"ticket.drop', [StringComparison]::Ordinal) -lt 0) { continue }
                try { $e = ConvertFrom-Json -InputObject $line -DateKind String -NoEnumerate -ErrorAction Stop } catch { continue }
                $run = [string](Get-PqMember $e 'run')
                if (-not $run -or ($SkipRun -and $run -ceq $SkipRun)) { continue }
                if ($run -cne $chainRun) { $chainRun = $run; $chainOk = $false }
                $ev = [string](Get-PqMember $e 'ev')
                $d = Get-PqMember $e 'd'
                if ($ev -ceq 'run.end') {
                    if ([string](Get-PqMember $d 'exit') -cne $restart) { return $carried }
                    $chainOk = $true
                    continue
                }
                if ($ev -cnotin @('run.start', 'ticket.dropped', 'ticket.dropLifted')) { continue }
                if (-not $chainOk) { return $carried }
                if ($ev -ceq 'run.start') { continue }
                $repo = [string](Get-PqMember $e 'repo')
                $id = [string](Get-PqMember $e 'id')
                if (-not $repo -or -not $id -or -not $decided.Add("$repo`:$id")) { continue }
                if ($ev -ceq 'ticket.dropLifted') { continue }
                $status = Get-PqMember $d 'statusAt'
                if ($null -eq $status) { continue }
                $carried["$repo`:$id"] = @{ repo = $repo; id = $id; mark = [ordered]@{ status = [string]$status; updated = [string](Get-PqMember $d 'updatedAt'); specMtime = [string](Get-PqMember $d 'specMtime'); specFile = '' } }
            }
        }
    }
    catch { }
    return $carried
}

# Every ticket id of a repository's ledger and archive, read from the files; $null when they cannot be read in full. A
# pass is bracketed by two such reads, and an id that is in the second and not in the first is a ticket the pass filed:
# the candidate for the robot-filed count of D5 (S0016 R24), which counts it only when its row says source robot.
function Get-PqTicketIds([string]$RepoPath) {
    try {
        $snap = Get-PqLedgerSnapshot -RepoPath $RepoPath
        if (-not $snap.complete) { return $null }
        $set = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($k in @($snap.tickets.Keys)) { [void]$set.Add([string]$k) }
        return , $set
    }
    catch { return $null }
}

function Get-PqNewTicketIds($Before, $After) {
    if ($null -eq $Before -or $null -eq $After) { return [string[]]@() }
    $new = @(foreach ($id in $After) { if (-not $Before.Contains($id)) { $id } })
    [Array]::Sort($new, [StringComparer]::Ordinal)
    return [string[]]$new
}

# The run row's finishedAt (TASK-FLOW rule 46): local time, yyyy-MM-ddTHH:mm:ss with no zone - the shape of the runner's
# rule-23 row, so the two journals parse alike (S0082).
function Get-PqRunRowTime([datetime]$Now = [datetime]::Now) {
    return $Now.ToString("yyyy-MM-dd'T'HH:mm:ss", [Globalization.CultureInfo]::InvariantCulture)
}

# The run row's optional agentExit (rule 46): the journal row's integer exit code, or $null when there is none to write.
function Get-PqRunRowAgentExit($Value) {
    if ($null -eq $Value) { return $null }
    $n = 0
    if ([int]::TryParse([string]$Value, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$n)) { return $n }
    return $null
}

# The complexity a pass is launched at and where it came from (rule 51, EVENTS pass.launch cxSource): a non-Claude agent
# runs its record's fixed model whatever the level (fixedAgent), a declared `**Complexity:**` level is header, and no
# declaration runs at medium (default). @{ cx; cxSource }.
#
# -Rated (TASK-FLOW 0.32, EVENTS section 8): the rater graded the ticket just before this launch, so cxSource is rated.
function Get-PqPassCx([string]$Level, [string]$Agent, [switch]$Rated) {
    $cx = if ($Level) { $Level } else { 'medium' }
    $source = if ($Rated -and $Level) { 'rated' } elseif ($Agent -and $Agent -cne 'claude') { 'fixedAgent' } elseif ($Level) { 'header' } else { 'default' }
    return @{ cx = $cx; cxSource = $source }
}

# The model the dispatcher knows at the pick (EVENTS envelope model): a non-Claude agent's fixed record model; for
# claude the runner chooses by the level at launch, so the pick carries none and pass.end carries the run row's. A route
# that names a model (TASK-FLOW 0.32 item B) is that model, claude included - except on an audit status, which -Status
# names and Get-PqPickLaunch answers.
function Get-PqPickModel($Pick, [string]$Status = '') {
    if ($null -eq $Pick -or -not $Pick.agent) { return $null }
    $m = [string](Get-PqPickLaunch $Pick $Status).model
    if ($m) { return $m }
    return $null
}

# The d of dispatch.pick (rule 58): the rank's first candidate with the top three alternatives the walk rejected, and
# why the agent was the one taken - only (a single agent in the order), fallback (an earlier one passed over) or
# spendOrder (the first of the order took it).
function Get-PqDispatchPickData($Cand, $Pick, $Registry, $Cx, $Model) {
    $order = @(@(Get-PqValue $Registry 'agentOrder' @()) | Where-Object { $_ })
    $agentWhy = if ($order.Count -le 1) { 'only' } elseif (@($Pick.fallbacks).Count -gt 0) { 'fallback' } else { 'spendOrder' }
    $rule = [string](Get-PqValue $Cand 'rule' '')
    if (-not $rule) { $rule = 'queueFile' }
    $alt = @(@(Get-PqValue $Cand 'alt' @()) | Select-Object -First 3 | ForEach-Object { [ordered]@{ repo = [string]$_.repo; id = [string]$_.id; why = [string]$_.why } })
    $d = [ordered]@{
        repo = [string]$Cand.repo; id = [string]$Cand.id; rule = $rule; alt = $alt
        agent = [string]$Pick.agent; agentWhy = $agentWhy; model = $Model; cx = $Cx; statusBefore = [string](Get-PqValue $Cand 'status' '')
    }
    $title = [string](Get-PqValue $Cand 'title' '')
    if ($title) { $d.title = $(if ($title.Length -gt 80) { $title.Substring(0, 80) } else { $title }) }
    return $d
}

# The host of run.start (EVENTS 3.1): logical processors, physical memory in GB to one decimal, the OS version string.
function Get-PqHostInfo {
    $ramGb = $null
    try { $ramGb = [Math]::Round([GC]::GetGCMemoryInfo().TotalAvailableMemoryBytes / 1GB, 1) } catch { }
    return [ordered]@{ cpu = [Environment]::ProcessorCount; ramGb = $ramGb; os = [Environment]::OSVersion.VersionString }
}

# One hash of a pass's launch line (EVENTS pass.launch argvHash): the runner path and its arguments, joined by LF.
function Get-PqArgvHash([string[]]$Argv) {
    return (Get-PqFileHash ([Text.Encoding]::UTF8.GetBytes((@($Argv) | ForEach-Object { [string]$_ }) -join "`n")))
}

# ticket.complexity of a pass (EVENTS 3.5): the `**Complexity:**` level read before the launch and after the pass; $null
# when it did not change. A pass that started at Tactical or later is the plan pass, an earlier one the spec pass.
function Get-PqComplexityChange([string]$From, [string]$To, [string]$StatusBefore) {
    if (-not $To -or $From -ceq $To) { return $null }
    $rank = @{ light = 0; medium = 1; hard = 2 }
    $direction = if (-not $From) { 'set' } elseif ($rank[$To] -gt $rank[$From]) { 'raise' } else { 'lower' }
    $by = if ($StatusBefore -cin @('Tactical', 'In Progress', 'Implemented', 'Partial', 'Broken', 'BlockNeedUserTest')) { 'planPass' } else { 'specPass' }
    $d = [ordered]@{}
    if ($From) { $d.from = $From }
    $d.to = $To
    $d.by = $by
    $d.direction = $direction
    return $d
}

# ---- the ledger watch wiring (rule 59, S0082 phase 7) ----
# Every pool worker is its own dispatcher, so the previous look at a repository's ledger is shared, not per worker:
# <root>\run\ledger-<key>.json holds the last snapshot (at, ticket rows) and the entry map of Update-PqEnteredAt.
# Whichever worker looks first under the repository's watch mutex writes the interval's events and advances the file;
# a worker that finds the mutex taken skips, because the holder is reading the same files at the same moment. A
# first look with no file writes the baseline and no event (a restart diffs against the file the last run left).

function Get-PqLedgerWatchPath([string]$Key) {
    return (Join-Path (Join-Path (Get-PqRoot) 'run') "ledger-$Key.json")
}

# The saved look as @{ snapshot (the shape of Get-PqLedgerSnapshot, complete); enteredAt (ordinal ordered map) }, or
# $null when the file is absent or unreadable (the next look is then a baseline).
function Read-PqLedgerWatch([string]$Path) {
    try {
        if (-not [IO.File]::Exists($Path)) { return $null }
        $o = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
        $tickets = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
        foreach ($t in @($o.tickets)) {
            if ($null -eq $t -or -not $t.id -or $tickets.Contains([string]$t.id)) { continue }
            $tickets[[string]$t.id] = [pscustomobject][ordered]@{
                id = [string]$t.id; status = [string]$t.status; updated = $t.updated; created = $t.created; priority = $t.priority; file = $t.file
            }
        }
        $entered = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
        foreach ($e in @($o.enteredAt)) { if ($null -ne $e -and $e.id) { $entered[[string]$e.id] = $e.at } }
        $snap = [pscustomobject][ordered]@{
            repo = $o.repo; root = $o.root; at = [DateTimeOffset]::Parse([string]$o.at, [Globalization.CultureInfo]::InvariantCulture)
            tickets = $tickets; bad = 0; ledgerRead = $true; archiveRead = $true; complete = $true
            errors = [Collections.Generic.List[string]]::new()
        }
        return @{ snapshot = $snap; enteredAt = $entered }
    }
    catch { return $null }
}

function Save-PqLedgerWatch([string]$Path, $Snapshot, $EnteredAt) {
    $dir = Split-Path -Parent $Path
    if (-not [IO.Directory]::Exists($dir)) { $null = [IO.Directory]::CreateDirectory($dir) }
    $obj = [ordered]@{
        repo = $Snapshot.repo
        root = $Snapshot.root
        at = ([DateTimeOffset]$Snapshot.at).ToUniversalTime().ToString('o', [Globalization.CultureInfo]::InvariantCulture)
        tickets = @(foreach ($id in @($Snapshot.tickets.Keys)) { $Snapshot.tickets[$id] })
        enteredAt = @(foreach ($id in @($EnteredAt.Keys)) { [ordered]@{ id = $id; at = $EnteredAt[$id] } })
    }
    $tmp = "$Path.$PID.tmp"
    [IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json -Compress -Depth 6), [Text.Encoding]::UTF8)
    [IO.File]::Move($tmp, $Path, $true)
}

# The repository runner's journal rows (rule 23) with their instance, from runs-<instance>.jsonl in its runs folder:
# the last TailBytes of each file only (an attribution window is minutes, a journal grows for months). A row that is
# not JSON is skipped; a file that cannot be read returns $null (rule 59: the actor is then unknown, and counted).
function Get-PqRepoRunnerRows([string]$RunsDir, [int]$TailBytes = 262144) {
    $rows = [Collections.Generic.List[object]]::new()
    if (-not $RunsDir -or -not [IO.Directory]::Exists($RunsDir)) { return , $rows.ToArray() }
    try {
        foreach ($f in [IO.Directory]::GetFiles($RunsDir, 'runs-*.jsonl')) {
            $instance = [IO.Path]::GetFileNameWithoutExtension($f).Substring(5)
            $fs = [IO.FileStream]::new($f, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
            try {
                $start = [Math]::Max([long]0, $fs.Length - $TailBytes)
                $null = $fs.Seek($start, [IO.SeekOrigin]::Begin)
                $text = [IO.StreamReader]::new($fs, [Text.Encoding]::UTF8).ReadToEnd()
            }
            finally { $fs.Dispose() }
            $lines = $text.Split("`n")
            $first = if ($start -gt 0) { 1 } else { 0 }
            for ($i = $first; $i -lt $lines.Length; $i++) {
                $line = $lines[$i].Trim()
                if (-not $line) { continue }
                try { $r = $line | ConvertFrom-Json } catch { continue }
                if ($r -isnot [Management.Automation.PSCustomObject]) { continue }
                $r | Add-Member -NotePropertyName instance -NotePropertyValue $instance -Force
                $rows.Add($r)
            }
        }
    }
    catch { return $null }
    return , $rows.ToArray()
}

# The passes live now, from the worker state files: @{ repo; id; pass; startedAt; endedAt } as rule 59's reader wants.
# The pass id is not in a worker file; a pass that already ended is found by its runner row (instance pq<k>).
function Get-PqLiveWorkerPasses {
    $out = [Collections.Generic.List[object]]::new()
    foreach ($w in @(Get-PqWorkerFiles)) {
        if (-not $w.repository -or -not $w.ticket) { continue }
        $since = $null
        if ($w.since) { try { $since = [DateTimeOffset]::Parse([string]$w.since, [Globalization.CultureInfo]::InvariantCulture) } catch { $since = $null } }
        if ($null -eq $since) { continue }
        $out.Add(@{ repo = $w.repository; id = $w.ticket; pass = $null; startedAt = $since; endedAt = $null })
    }
    return , $out.ToArray()
}

# Run Body under the repository's watch mutex; $false without running it when another process holds it now.
function Invoke-PqLedgerWatchLock([string]$Key, [scriptblock]$Body) {
    $bytes = [Text.Encoding]::UTF8.GetBytes(((Get-PqRoot) + '|ledger-watch|' + $Key).ToLowerInvariant())
    $name = 'sza-pq-lw-' + [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    $mutex = [Threading.Mutex]::new($false, $name)
    $held = $false
    try {
        try { $held = $mutex.WaitOne(0) }
        catch [Threading.AbandonedMutexException] { $held = $true }
        if (-not $held) { return $false }
        $null = & $Body
        return $true
    }
    finally {
        if ($held) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

# One look at the ledgers of the named enabled repositories (all enabled ones without -Repos): the interval's
# ticket.transition, ticket.created and ingest.ledgerDiff (rule 59, EVENTS 3.5 and 3.9) written to the log, the shared
# look advanced. -LivePasses adds passes the worker files no longer name (the pass that just ended, with its id).
# ticket.created carries `file`, repository-relative (rule 56). Returns the number of events written; never throws.
function Invoke-PqLedgerWatch {
    param([Parameter(Mandatory)]$Registry, $Log, [string]$Run, [int]$Worker, [string[]]$Repos, $LivePasses, [hashtable]$PathsCache)
    if ($null -eq $PathsCache) { $PathsCache = @{} }
    $box = @{ n = 0 }
    foreach ($r in @($Registry.repos)) {
        if ((Get-PqValue $r 'enabled' $false) -ne $true) { continue }
        $key = [string]$r.key
        if ($PSBoundParameters.ContainsKey('Repos') -and $key -cnotin @($Repos)) { continue }
        try {
            $repoPath = [string]$r.path
            $rp = $null
            if ($PathsCache.ContainsKey($key)) { $rp = $PathsCache[$key] }
            if ($null -eq $rp) { $rp = Get-PqRepoPaths -RepoPath $repoPath; $PathsCache[$key] = $rp }
            $null = Invoke-PqLedgerWatchLock $key {
                $file = Get-PqLedgerWatchPath $key
                $prev = Read-PqLedgerWatch $file
                $cur = Get-PqLedgerSnapshot -RepoPath $repoPath -Key $key -Paths $rp
                if (-not $cur.complete) { return }
                $prevSnap = if ($null -ne $prev) { $prev.snapshot } else { $null }
                $entered = if ($null -ne $prev) { $prev.enteredAt } else { [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal) }
                if ($null -ne $prevSnap) {
                    $live = @(@($LivePasses) + @(Get-PqLiveWorkerPasses) | Where-Object { $null -ne $_ })
                    $rows = Get-PqRepoRunnerRows $rp.RunsDir
                    foreach ($e in @(Get-PqLedgerEvents -Previous $prevSnap -Current $cur -LivePasses $live -RepoRunnerRows $rows -EnteredAt $entered)) {
                        $d = $e.D
                        if ($e.Ev -ceq 'ticket.created' -and $cur.tickets.Contains([string]$e.Id)) {
                            $specFile = $cur.tickets[[string]$e.Id].file
                            if ($specFile) { $d.file = Convert-PqRelativePath -RepoPath $repoPath -Path ([string]$specFile) }
                        }
                        if (Write-PqEvent -Log $Log -Ev $e.Ev -Run $Run -Repo $e.Repo -Id $e.Id -Pass $e.Pass -Worker $Worker -D $d) { $box.n++ }
                    }
                }
                Update-PqEnteredAt -EnteredAt $entered -Previous $prevSnap -Current $cur
                Save-PqLedgerWatch $file $cur $entered
            }
        }
        catch { }
    }
    return $box.n
}

function ConvertTo-PqPassEndOutcome([string]$Outcome) {
    switch ($Outcome) {
        'ok' { 'ok' }
        'no-progress' { 'noProgress' }
        'no-progress-or-claim-lost' { 'noProgress' }
        'child-failed' { 'childFailed' }
        'timeout' { 'timeout' }
        'limit-hit' { 'limitHit' }
        'halted' { 'halted' }
        'killed' { 'killed' }
        'claim-lost' { 'claimLost' }
        'claim-lost-before-launch' { 'claimLost' }
        'launch-failed' { 'launchFailed' }
        'provider-error' { 'providerError' }
        'orphaned' { 'orphaned' }
        'status-drift' { 'statusDrift' }
        'context-handoff' { 'ok' }
        default { if ($Outcome) { $Outcome } else { 'unknown' } }
    }
}

# The exit code of a worker that ends because its own code changed (run.codeChanged). It is not 0 on purpose: the supervisor
# below starts the worker again on this code alone, so an owner stop, a reached ceiling or an error (all other codes) ends
# the window instead of starting the worker again. EX_TEMPFAIL of sysexits.h.
function Get-PqRestartExitCode { return 75 }

# An open-ended worker (`pq start` with no -Ticket and no -MaxTickets) runs in a child process of the one the owner launched,
# and the child is started again while it ends with the restart code, so it picks up its own new code. The restart lives in
# pq itself on purpose: it holds whatever launched the worker - a shortcut, the panel (an old build included), a terminal.
# Any other exit code of the child is this process's own, so a stop stays a stop. Emits only that code.
# -ThrottleSeconds: the wait before starting again after a child that ran less than 20 s, so a code that never settles
# cannot spin.
function Invoke-PqSupervised {
    param(
        [Parameter(Mandatory)][string]$Script,
        [Parameter(Mandatory)][string]$Verb,
        [string[]]$Arguments = @(),
        [string]$Pwsh = '',
        [int]$ThrottleSeconds = 10
    )
    if (-not $Pwsh) { $Pwsh = (Get-Process -Id $PID).Path }
    while ($true) {
        $psi = [Diagnostics.ProcessStartInfo]::new($Pwsh)
        foreach ($a in (@('-NoProfile', '-File', $Script, $Verb) + @($Arguments))) { $psi.ArgumentList.Add($a) }
        $psi.UseShellExecute = $false
        $psi.Environment['SZA_PQ_SUPERVISED'] = '1'
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $child = [Diagnostics.Process]::Start($psi)
        # Ctrl+C reaches the child too; stay until it has finished its own cleanup before this window gets its prompt back.
        try { $child.WaitForExit() }
        finally { if (-not $child.HasExited) { $null = $child.WaitForExit(60000) } }
        $code = $child.ExitCode
        $child.Dispose()
        if ($code -ne (Get-PqRestartExitCode)) { return $code }
        Write-Host 'pq code changed - the worker starts again with the new code'
        if ($ThrottleSeconds -gt 0 -and $sw.Elapsed.TotalSeconds -lt 20) { Start-Sleep -Seconds $ThrottleSeconds }
    }
}

function Get-PqCodeMaxWriteTime {
    $portfolioDir = Split-Path $PSScriptRoot -Parent
    $pqFile = Join-Path $portfolioDir 'pq.ps1'
    $libFiles = [IO.Directory]::GetFiles($PSScriptRoot, '*.ps1')
    $maxTime = [DateTime]::MinValue
    foreach ($f in (@($pqFile) + @($libFiles))) {
        if ([IO.File]::Exists($f)) {
            $wt = [IO.File]::GetLastWriteTimeUtc($f)
            if ($wt -gt $maxTime) { $maxTime = $wt }
        }
    }
    return $maxTime
}

function Start-PqLoop {
    param(
        [Parameter(Mandatory)]$Registry,
        [switch]$Drain,
        [int]$MaxTickets = 0,
        [int]$PollSeconds = 0,
        [string]$RunnerScript = '',
        # A clock time the run ends at (S0016 R56): no new pass after it, a waiting loop ends at once.
        [Nullable[datetime]]$Until = $null,
        # S0027: 'key:id' = exactly one pass on that ticket whatever its rank, then exit (never waits, never another
        # ticket; exit 3 with a reason when it is not run); 'key' = a normal worker that ranks only that project.
        [string]$OnlyTicket = '',
        [string]$OnlyRepo = ''
    )
    $named = $null
    $namedFail = ''
    $namedPassRan = $false
    if ($OnlyTicket -or $OnlyRepo) {
        $tv = Test-PqStartTarget -Registry $Registry -Ticket $OnlyTicket -Repo $OnlyRepo -MaxTickets $MaxTickets
        if (-not $tv.ok) { Write-PqError $tv.name $tv.message; return 2 }
        $named = $tv.named
    }
    if ($null -ne $named) {
        $MaxTickets = 1
        $Drain = [switch]$true
    }
    $root = Initialize-PqRoot
    $stopPath = Join-Path $root 'STOP'
    $slot = Invoke-PqStateLock {
        if ([IO.File]::Exists($stopPath)) {
            $runDir = Join-Path $root 'run'
            if ([IO.Directory]::Exists($runDir)) {
                foreach ($wf in [IO.Directory]::GetFiles($runDir, 'worker-*.json')) {
                    if (Test-PqStateOwner (Read-PqState $wf)) { return -1 }
                }
            }
            Remove-Item -LiteralPath $stopPath -Force
            Write-Host 'cleared STOP file'
        }
        Get-PqWorkerSlot $Registry
    }
    if ($slot -eq -1) { Write-PqError 'StopInProgress' 'STOP is still draining live workers'; return 3 }
    if ($null -eq $slot) {
        # A valid start that did not run is 3 (rule 66); 2 is an invalid invocation only (S0083).
        Write-PqError 'NoWorkerSlot' "all $([int]$Registry.maxWorkers) worker slots are busy"
        return 3
    }
    # A stop of this worker's slot left by an earlier run would end the new worker before its first pass.
    try { Remove-Item -LiteralPath (Get-PqPath -Kind stopTarget -StopKind worker -Target ([string]$slot)) -Force -ErrorAction SilentlyContinue } catch { }

    $runId = 'R' + [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 4)
    $log = Open-PqLog -Writer "w$slot" -Run $runId

    $enabledRepos = @(@($Registry.repos) | Where-Object { $_.enabled -eq $true })
    $startD = [ordered]@{
        mode = 'pool'
        slots = [int]$Registry.maxWorkers
        drain = [bool]$Drain
        repos = $enabledRepos.Count
        # S0037: the provider order in force at start (EVENTS.md `agents`); a later order change writes no new snapshot.
        agents = @(@($Registry.agentOrder) | ForEach-Object { [string]$_ })
        pid = $PID
    }
    # S0082 (EVENTS 3.1): what the run started on. A named start runs one pass and never waits (watch false); a worker
    # whose console output is captured (the panel) is detached. A value that cannot be read is null, never a guess.
    $startD.watch = ($null -eq $named)
    $startD.detached = $(try { [Console]::IsOutputRedirected } catch { $false })
    $startHarness = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
    $startD.canon = $(try { ([IO.File]::ReadAllText((Join-Path $startHarness '..\..\CANON_VERSION'))).Trim() } catch { $null })
    $startD.plugin = $(try { [string](ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $startHarness '..\..\.claude-plugin\plugin.json')))).version } catch { $null })
    $startD.registryHash = $(try { Get-PqFileHash ([IO.File]::ReadAllBytes((Get-PqPath -Kind registry))) } catch { $null })
    $startD.queueHash = $(try { $qpStart = Get-PqQueuePath $Registry; if ([IO.File]::Exists($qpStart)) { Get-PqFileHash ([IO.File]::ReadAllBytes($qpStart)) } else { $null } } catch { $null })
    $startD.host = Get-PqHostInfo
    if ($null -ne $named) { $startD.target = "ticket:$($named.repo):$($named.id)" }
    elseif ($OnlyRepo) { $startD.target = "repo:$OnlyRepo" }
    $null = Write-PqEvent -Log $log -Ev 'run.start' -Run $runId -Worker $slot -D $startD
    $repoOnly = @{}
    if ($OnlyRepo) { $repoOnly.OnlyRepo = $OnlyRepo }
    Write-PqOwnerAction 'start'
    if ($OnlyRepo) { Write-Host "repository $OnlyRepo is named at start - the owner's sessions there are not waited for (a lease, a lock or a hold still is)" }

    $harness = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))

    $passCount = 0
    $movedCount = 0
    $exclude = [Collections.Generic.List[string]]::new()
    $drops = @{}
    $xblocked = @{}
    $joinSeen = @{}
    $nextDiscoveryAt = [DateTime]::MinValue
    $currentRepoLock = $null
    $exitCode = 0
    $runSw = [Diagnostics.Stopwatch]::StartNew()
    $waiting = $false
    $noAgentSaid = ''
    $errStreak = 0
    # Waiting (rules 41, 58): what a poll saw last, whether a change is still settling, the hour's poll counters.
    $pathsCache = @{}
    $lastFp = $null
    $ledgerWatched = $false
    $settling = $false
    $quietPolls = 0
    $pollStats = New-PqPollStats
    $waitSaid = ''
    $lifts = @{}
    $thrashUntil = @{}
    # S0105: an open-ended worker the supervisor started again after a code change (run.end exit 75) goes on with the
    # drops of the run it continues (rule 43: a drop stays until the ticket changes), read back from this writer's own
    # ticket.dropped events; the first turn's lift check below offers again every one whose mark changed since.
    if ($null -eq $named -and $MaxTickets -le 0 -and $env:SZA_PQ_SUPERVISED -ceq '1') {
        try {
            $carriedDrops = Get-PqCarriedDrops -LogDir (Join-Path $root 'log') -Writer "w$slot" -SkipRun $runId
            foreach ($ck in @($carriedDrops.Keys | Sort-Object)) {
                $cd = $carriedDrops[$ck]
                $carryRepo = $null
                foreach ($r in @($Registry.repos)) { if ([string]$r.key -ceq [string]$cd.repo) { $carryRepo = $r; break } }
                if ($null -eq $carryRepo) { continue }
                # The spec file a waiting poll watches (Get-PqDropFingerprint); the event does not carry its path.
                $nowMark = Get-PqDropMark -RepoPath ([string]$carryRepo.path) -TicketId ([string]$cd.id)
                if ($null -ne $nowMark) { $cd.mark.specFile = [string]$nowMark.specFile }
                $drops[$ck] = $cd
                $exclude.Add($ck)
            }
            if ($drops.Count -gt 0) { Write-Host "carried $($drops.Count) dropped ticket(s) over the code-change restart: $(@($drops.Keys | Sort-Object) -join ', ')" }
        }
        catch { }
    }
    # Held back for a moment by the loop itself: a repository the owner works in, a ticket that could not get its resource.
    $occupiedMarks = @{}
    $occupancyState = @{}
    $stopNoticeState = @{}
    $transient = @{}
    $transientSaid = @{}
    # Tickets the raters were asked about in this worker run (TASK-FLOW rule 71): asked once, answered or not.
    $raterTried = @{}
    $heldResources = $null
    $heldResourcesRepo = ''
    $heldResourcesId = ''
    # Stops and the pause (rule 47, R56).
    $paused = $false
    $drainCarry = $null
    $drainCarryAgent = ''
    $codeStartTime = Get-PqCodeMaxWriteTime
    $lastRunErrText = ''
    $sameRunErrStreak = 0
    $loggedBadQueueRows = [hashtable]::new([StringComparer]::Ordinal)
    $turnPickerCache = @{}
    $rerankAfterSkip = $false

    try {
        while ($true) {
            # Check for changed queue code between passes. Only an open-ended worker ends for a restart: a run with a ceiling
            # (-MaxTickets, and -Ticket which sets it to 1) is one the owner wants to stop by itself, and a restarting
            # terminal would run it again past the ceiling; it keeps the code it loaded.
            $newestCodeTime = if ($null -eq $named -and $MaxTickets -le 0) { Get-PqCodeMaxWriteTime } else { $codeStartTime }
            if ($newestCodeTime -gt $codeStartTime) {
                $parseErrors = [Collections.Generic.List[string]]::new()
                $portfolioDir = Split-Path $PSScriptRoot -Parent
                $filesToCheck = @(Join-Path $portfolioDir 'pq.ps1') + @([IO.Directory]::GetFiles($PSScriptRoot, '*.ps1'))
                foreach ($f in $filesToCheck) {
                    $tokens = $null
                    $errors = $null
                    $null = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errors)
                    if ($null -ne $errors -and $errors.Count -gt 0) {
                        foreach ($e in $errors) {
                            $parseErrors.Add("$([IO.Path]::GetFileName($f)): $($e.Message)")
                        }
                    }
                }
                if ($parseErrors.Count -eq 0) {
                    $null = Write-PqEvent -Log $log -Ev 'run.codeChanged' -Run $runId -Worker $slot -D ([ordered]@{
                        files = $filesToCheck.Count
                        newestWriteTime = $newestCodeTime.ToString('o')
                        action = 'restart'
                    })
                    Write-Host "pq code changed and parsed cleanly - ending run for automatic restart (exit $(Get-PqRestartExitCode))"
                    $exitCode = Get-PqRestartExitCode
                    break
                } else {
                    Write-Host "pq code changed but has $($parseErrors.Count) parse error(s) - continuing on loaded code:" -ForegroundColor Yellow
                    foreach ($pe in $parseErrors) {
                        Write-Host "  $pe" -ForegroundColor Yellow
                    }
                }
            }

            $turnRepo = $null
            $turnId = $null
            $turnPath = $null
            try {
                # 1. Stops (rule 47). The whole-portfolio STOP and this worker's own end the loop between passes, honoured
                # here; a stop of a repository, an agent or a ticket with nothing running under it any more is honoured
                # here too (the file goes, a repository's registry hold stays), and while one still has a pass under it
                # the target gets no new work, below.
                $stops = @(Get-PqStopFiles)
                $stopRepos = @()
                $stopAgents = @()
                $stopTickets = @()
                # A drain of a repository, an agent or a ticket (S0082) carries the ticket this worker had in flight:
                # that stop is not honoured while the carry goes on, and its target still takes no other work.
                $carryStop = if ($drainCarry) { Get-PqCarryStop -Stops $stops -Carry $drainCarry -Agent $drainCarryAgent } else { $null }
                if ($stops.Count -gt 0) {
                    $liveWorkers = @(Get-PqWorkerFiles)
                    foreach ($ts in $stops) {
                        if ($ts.kind -cin @('all', 'worker')) { continue }
                        if (($null -ne $carryStop -and $ts.file -ceq $carryStop.file) -or (Test-PqStopTargetBusy $ts $liveWorkers)) {
                            switch ($ts.kind) { 'repo' { $stopRepos += $ts.target } 'agent' { $stopAgents += $ts.target } 'ticket' { $stopTickets += $ts.target } }
                            continue
                        }
                        $null = Write-PqEvent -Log $log -Ev 'run.stop' -Run $runId -Worker $slot -D ([ordered]@{ level = $ts.level; target = "$($ts.kind):$($ts.target)"; reason = 'owner'; passesInFlight = 0 })
                        Complete-PqStop -Stop $ts -Log $log
                        Write-Host "stop of $($ts.kind) $($ts.target) honoured$(if ($ts.kind -ceq 'repo') { ' - the repository stays on hold until pq release' })"
                    }
                }
                $mine = Get-PqApplicableStop -Stops $stops -Slot $slot
                if ($null -ne $mine -and -not ($mine.level -ceq 'drain' -and $drainCarry)) {
                    $null = Write-PqEvent -Log $log -Ev 'run.stop' -Run $runId -Worker $slot -D ([ordered]@{
                        level = $mine.level
                        target = $(if ($mine.kind -ceq 'worker') { "worker:$($mine.target)" } else { 'all' })
                        reason = 'owner'
                        passesInFlight = 0
                    })
                    Complete-PqStop -Stop $mine -Log $log
                    break
                }
                $drainNow = ($null -ne $mine -and $mine.level -ceq 'drain')
                $carryOn = ($null -eq $named -and $drainCarry -and ($drainNow -or $null -ne $carryStop))
                if (-not $carryOn -and $drainCarry) {
                    # The stop over the carry went or turned stricter: the worker state stops naming it, so the stop is honoured.
                    $drainCarry = $null; $drainCarryAgent = ''; $carryStop = $null
                    Set-PqWorkerState -Slot $slot
                }

                # The clock time of the run's end (R56).
                if ($null -ne $Until -and [DateTime]::Now -ge $Until) {
                    $null = Write-PqEvent -Log $log -Ev 'run.stop' -Run $runId -Worker $slot -D ([ordered]@{ level = 'pass'; reason = 'until'; passesInFlight = 0 })
                    Write-Host "reached the end time $($Until.ToString('yyyy-MM-dd HH:mm'))"
                    break
                }

                # 2. Max tickets ceiling
                if ($MaxTickets -gt 0 -and $passCount -ge $MaxTickets) {
                    $null = Write-PqEvent -Log $log -Ev 'run.stop' -Run $runId -Worker $slot -D ([ordered]@{
                        level = 'pass'
                        reason = 'maxTickets'
                        passesInFlight = 0
                    })
                    break
                }

                # The pause (R56): no pass is launched, those running are not touched (there is none in flight between turns);
                # `pq resume` removes the file. A stop or the end time still ends a paused worker, at the top of this turn.
                if (Test-PqPaused) {
                    if ($null -ne $named) { $namedFail = 'the queue is paused (pq resume continues it)'; break }
                    if (-not $paused) {
                        $null = Write-PqEvent -Log $log -Ev 'run.pause' -Run $runId -Worker $slot -D ([ordered]@{ by = 'cli' })
                        Write-Host 'paused - pq resume continues'
                        $paused = $true
                    }
                    Start-Sleep -Seconds 1
                    continue
                }
                if ($paused) {
                    $null = Write-PqEvent -Log $log -Ev 'run.resume' -Run $runId -Worker $slot -D ([ordered]@{ by = 'cli' })
                    Write-Host 'resumed'
                    $paused = $false
                }

                # A stamped repository under a discovery root joins by itself (rule 49): at the start, then every ten minutes.
                # A named start and a -Repo worker (S0027) leave other projects alone: no discovery, so no repository joins.
                if ([DateTime]::UtcNow -ge $nextDiscoveryAt -and $null -eq $named -and -not $OnlyRepo) {
                    $nextDiscoveryAt = [DateTime]::UtcNow.AddMinutes(10)
                    try { $null = Invoke-PqDiscovery -Registry $Registry -Seen $joinSeen -HarnessRoot $harness -Log $log -Run $runId -Worker $slot } catch { }
                }

                # 3. Check occupied repositories
                $current = Read-PqRegistry
                if (-not $current.ok) { throw 'RegistryInvalid: cannot reload the registry' }
                $Registry = $current.registry
                $byKey = @{}
                foreach ($r in @($Registry.repos)) { $byKey[[string]$r.key] = $r }
                $occupied = Get-PqOccupiedRepos $Registry

                if (-not $rerankAfterSkip) {
                    # New tickets of every repository join their project's rows of PORTFOLIO_QUEUE.md before the rank reads it. A failed
                    # sync (the owner saving the file at that moment) is retried on the next turn and never stops the loop.
                    try {
                        $qpSync = Get-PqQueuePath $Registry
                        # A named start and a -Repo worker (S0027) sync the target project only (-Key): other projects' ledgers
                        # and rows are not touched; the target's own file->ledger registration (rule 65) still runs.
                        $syncKey = if ($null -ne $named) { [string]$named.repo } else { [string]$OnlyRepo }
                        if ([IO.File]::Exists($qpSync)) {
                            if ($syncKey) { $null = Sync-PqRegisteredQueues -Path $qpSync -Registry $Registry -Key $syncKey -Log }
                            else { $null = Sync-PqRegisteredQueues -Path $qpSync -Registry $Registry -Log }
                        }
                    }
                    catch { }

                    # A dropped ticket the owner (or anyone) changed since its drop is offered again: one ledger read per
                    # repository that holds a drop.
                    if ($drops.Count -gt 0) {
                        $snaps = @{}
                        foreach ($dk in @($drops.Keys)) {
                            $drop = $drops[$dk]
                            $dropRepo = $byKey[$drop.repo]
                            if ($null -eq $dropRepo) { continue }
                            if (-not $snaps.ContainsKey($drop.repo)) {
                                try { $snaps[$drop.repo] = Get-PqLedgerSnapshot -RepoPath ([string]$dropRepo.path) } catch { $snaps[$drop.repo] = $null }
                            }
                            if ($null -eq $snaps[$drop.repo]) { continue }
                            $changed = Get-PqDropChange $drop.mark (Get-PqDropMark -RepoPath ([string]$dropRepo.path) -TicketId $drop.id -Snapshot $snaps[$drop.repo])
                            if (-not $changed) { continue }
                            # Thrash (S0016 R31): a ticket lifted three times within an hour keeps coming back unmoved, so
                            # something rewrites its row after every pass. It stays dropped for an hour, then is tried again.
                            if ($thrashUntil.ContainsKey($dk) -and $thrashUntil[$dk] -gt [DateTime]::UtcNow) { continue }
                            $lift = Register-PqLift -Lifts $lifts -Key $dk -Now ([DateTime]::UtcNow)
                            if ($lift.thrash) {
                                $thrashUntil[$dk] = [DateTime]::UtcNow.AddMinutes(60)
                                $null = Write-PqEvent -Log $log -Ev 'ticket.thrash' -Run $runId -Repo $drop.repo -Id $drop.id -Worker $slot -D ([ordered]@{ passes = $lift.count; window = 60; statuses = @([string]$drop.mark.status) })
                                Write-Host "ticket $dk came back unmoved $($lift.count) times within an hour - held back for an hour"
                                continue
                            }
                            $drops.Remove($dk)
                            [void]$exclude.Remove($dk)
                            $null = Write-PqEvent -Log $log -Ev 'ticket.dropLifted' -Run $runId -Repo $drop.repo -Id $drop.id -Worker $slot -D ([ordered]@{ changed = $changed })
                            Write-Host "ticket $dk changed ($changed) - offered again"
                        }
                    }

                    # A ticket held by a blocker in another repository (rule 52) is offered again once that blocker is released.
                    foreach ($bk in @($xblocked.Keys)) {
                        $held = $xblocked[$bk]
                        $still = Get-PqXrepoBlock -Registry $Registry -RepoKey $held.repo -TicketId $held.id
                        if ($null -ne $still) { continue }
                        $xblocked.Remove($bk)
                        [void]$exclude.Remove($bk)
                        $null = Write-PqEvent -Log $log -Ev 'xrepo.resolve' -Run $runId -Repo $held.repo -Id $held.id -Worker $slot -D ([ordered]@{ blocked = $bk; blocker = $held.blocker; state = 'released' })
                        $null = Write-PqEvent -Log $log -Ev 'ticket.unblocked' -Run $runId -Repo $held.repo -Id $held.id -Worker $slot -D ([ordered]@{ blocker = $held.blocker })
                        Write-Host "ticket $bk - blocker $($held.blocker) released, offered again"
                    }

                    # What a poll compares against: taken after this turn's own writes (the queue sync above), so the loop's
                    # own changes never look like the owner's.
                    $lastFp = Get-PqFingerprint -Registry $Registry -PathsCache $pathsCache -Extra (Get-PqDropFingerprint $drops)
                    $settling = $false
                    $quietPolls = 0
                    # Rule 59 (S0082): the first turn looks at every ledger once - a baseline where no look was saved, the
                    # moves made while no robot ran where one was.
                    if (-not $ledgerWatched) {
                        $ledgerWatched = $true
                        $null = Invoke-PqLedgerWatch -Registry $Registry -Log $log -Run $runId -Worker $slot -PathsCache $pathsCache
                    }
                }

                # What the loop itself holds back for a moment lapses on its own: a repository the owner works in, a
                # ticket that could not get its resource, and a ticket no provider could take that now has one.
                $nowUtc = [DateTime]::UtcNow
                foreach ($mk in @($occupiedMarks.Keys)) { if ($occupiedMarks[$mk].until -le $nowUtc) { $occupiedMarks.Remove($mk) } }
                foreach ($mk in @($transient.Keys)) {
                    $tr = $transient[$mk]
                    $due = ($tr.until -le $nowUtc)
                    if (-not $due -and -not $rerankAfterSkip -and [string]$tr.why -ceq 'noAgent' -and $tr.repoPath) {
                        $due = ($null -ne (Select-PqAgent -Registry $Registry -RepoPath ([string]$tr.repoPath) -Level ([string]$tr.level) -Skip $stopAgents -Score ([int]$tr.score)).agent)
                    }
                    if ($due) { $transient.Remove($mk); $transientSaid.Remove($mk) }
                }

                # A repository that is `concurrent` takes at most its maxWorkers workers (rule 60); one that is not is held
                # by the repository lock, above. With fill `breadth` a repository that already has a worker waits for the
                # projects that have none (rule 63).
                $workerFiles = @(Get-PqWorkerFiles)
                $capRepos = [Collections.Generic.List[string]]::new()
                $busyRepos = [Collections.Generic.List[string]]::new()
                foreach ($wr in @($workerFiles | Where-Object { $_.repository } | Group-Object repository)) {
                    $busyRepos.Add([string]$wr.Name)
                    $wrec = $byKey[[string]$wr.Name]
                    if ($null -ne $wrec -and (Get-PqValue $wrec 'concurrent' $false) -eq $true -and $wr.Count -ge [int](Get-PqValue $wrec 'maxWorkers' 1)) { $capRepos.Add([string]$wr.Name) }
                }

                # The owner's sessions are read for every repository before the rank, from transcripts alone, so a single walk
                # goes past all of them: the rank hands back one head per walk, a walk costs seconds to minutes, and the
                # half-minute mark of the first occupied repository had lapsed before the walk for the second was done, so
                # the robot kept coming back to the same two repositories instead of reaching a free one. A repository stays
                # marked until its window can have run out (a transcript only gets younger), and never less than 30 s.
                # A `pq start -Repo` worker (TASK-FLOW 0.40 section 18) ranks one repository and does not wait for the
                # owner's transcript in it, so it reads no transcript at all: the other repositories are never ranked, and
                # a line about them (one per enabled repository) was noise on the console of a scoped start.
                if (-not $rerankAfterSkip -and $null -eq $named -and -not $OnlyRepo) {
                    $ownerIn = Get-PqTranscriptOccupiedRepos -Registry $Registry -HarnessRoot $harness
                    foreach ($ownerKey in @($ownerIn.Keys)) {
                        $ownerOcc = $ownerIn[$ownerKey]
                        $occupiedMarks[$ownerKey] = @{ until = [DateTime]::UtcNow.AddSeconds([Math]::Max(30, [int]$ownerOcc.freeInSeconds)); why = 'occupied' }
                        if (-not $occupancyState.ContainsKey($ownerKey)) {
                            $occupancyState[$ownerKey] = New-PqOccupancyMark $ownerOcc
                            $null = Write-PqEvent -Log $log -Ev 'repo.occupied' -Run $runId -Repo $ownerKey -Worker $slot -D ([ordered]@{ by = $ownerOcc.by; holderKind = $ownerOcc.holderKind; age = $ownerOcc.ageSeconds })
                            Write-Host "repository $ownerKey is occupied ($($ownerOcc.by), $($ownerOcc.ageSeconds) s ago) - the robot waits for the owner"
                        }
                    }
                    # Rule 61: a repository held by the owner's transcript alone is free the walk its transcript goes quiet,
                    # not the next time the rank happens to reach it.
                    foreach ($freeKey in @($occupancyState.Keys)) {
                        if ($ownerIn.Contains($freeKey) -or [string]$occupancyState[$freeKey].by -cne 'transcript') { continue }
                        $null = Write-PqEvent -Log $log -Ev 'repo.free' -Run $runId -Repo $freeKey -Worker $slot -D (Get-PqRepoFreeData $occupancyState[$freeKey])
                        $occupancyState.Remove($freeKey)
                        Write-Host "repository $freeKey is free again"
                    }
                }

                # 4. Rank. The loop reads only the first candidate, so the walk ends at the first head found: one picker run
                # per queue row costs minutes on a queue of a hundred rows.
                $wasSkipRerank = $rerankAfterSkip
                $rerankAfterSkip = $false
                if (-not $waiting -and -not $noAgentSaid -and -not $wasSkipRerank) { Write-Host 'ranking the queue' }
                $rankExclude = @($exclude) + @($transient.Keys) + @($stopTickets)
                $rankOccupied = @($occupied) + @($occupiedMarks.Keys) + @($stopRepos) + @($capRepos)
                $rank = $null
                if ($null -ne $named) {
                    # A named start asks the rank for that one ticket only: no drain carry, no breadth fill.
                    $rank = Get-PqNextRank -Registry $Registry -HarnessRoot $harness -Exclude $rankExclude -Occupied $rankOccupied -Slots 1 -StopAfter 1 -NamedTicket $OnlyTicket
                }
                elseif ($carryOn) {
                    # A drain (rule 47) goes on with the ticket whose pass was in flight when it was read, as long as the
                    # repository still offers it; the rank is not asked. Of a STOP or this worker's stop the worker then
                    # ends; of a repository, agent or ticket stop the stop is honoured and the worker takes other work.
                    $dc = $drainCarry -split ':', 2
                    $drec = $byKey[$dc[0]]
                    $dh = if ($null -ne $drec) { Get-PqPickerHead -RepoPath ([string]$drec.path) -HarnessRoot $harness -ForceId $dc[1] } else { $null }
                    $drainCarry = $null
                    $drainCarryAgent = ''
                    Set-PqWorkerState -Slot $slot
                    if ($null -ne $dh -and $dh.ok -and $null -ne $dh.head) {
                        $rank = @{ events = @(); skipped = @(); autoSkipReasons = $null; candidates = @([ordered]@{ repo = $dc[0]; id = $dc[1]; status = [string]$dh.head.status; title = (Get-PqRankTitle $dh.head); priority = (Get-PqValue $dh.head 'priority') }) }
                        if ($null -ne $carryStop -and $carryStop.kind -ceq 'agent') { $stopAgents = @($stopAgents | Where-Object { $_ -cne $carryStop.target }) }
                    }
                    elseif ($drainNow) {
                        $null = Write-PqEvent -Log $log -Ev 'run.stop' -Run $runId -Worker $slot -D ([ordered]@{ level = 'drain'; target = 'all'; reason = 'owner'; passesInFlight = 0 })
                        Write-Host "drain: $($dc[0]):$($dc[1]) is not offered any more - stopping"
                        break
                    }
                    else {
                        $null = Write-PqEvent -Log $log -Ev 'run.stop' -Run $runId -Worker $slot -D ([ordered]@{ level = 'drain'; target = "$($carryStop.kind):$($carryStop.target)"; reason = 'owner'; passesInFlight = 0 })
                        Complete-PqStop -Stop $carryStop -Log $log
                        Write-Host "drain of $($carryStop.kind) $($carryStop.target) honoured - $($dc[0]):$($dc[1]) is not offered any more$(if ($carryStop.kind -ceq 'repo') { '; the repository stays on hold until pq release' })"
                        $carryStop = $null
                        continue
                    }
                }
                else {
                    # Rule 52 inside the walk: a head held by a blocker in another project is refused there and the walk
                    # goes on, instead of one whole rank per such head (step 6 below keeps its check as the backstop).
                    $regForFilter = $Registry
                    $xrepoSnaps = @{}
                    $xrepoFilter = { param($k, $i) Get-PqXrepoBlock -Registry $regForFilter -RepoKey $k -TicketId $i -Snapshots $xrepoSnaps }.GetNewClosure()
                    # TASK-FLOW 0.38 section 16: the root of a refused ticket's blocker chain is offered in its place. One
                    # memo per rank, so many tickets behind one blocker cost one chain walk. Without the inbox library (a
                    # test that loads the loop alone) there is no lift and the walk is the one of 0.37.
                    $xrepoLift = $null
                    if ($null -ne (Get-Command Get-PqLiftTarget -ErrorAction Ignore)) {
                        $liftMemo = @{}
                        $xrepoLift = { param($k, $i, $refusal) Get-PqLiftTarget -Registry $regForFilter -Refusal $refusal -Memo $liftMemo -Snapshots $xrepoSnaps }.GetNewClosure()
                    }
                    if ((Get-PqValue $Registry 'fill' 'depth') -ceq 'breadth' -and $busyRepos.Count -gt 0) {
                        $rank = Get-PqNextRank -Registry $Registry -HarnessRoot $harness -Exclude $rankExclude -Occupied (@($rankOccupied) + @($busyRepos)) -Slots 1 -StopAfter 1 -HeadFilter $xrepoFilter -HeadLift $xrepoLift -PickerCache $turnPickerCache @repoOnly
                        if (@($rank.candidates).Count -eq 0) { $rank = $null }
                    }
                    if ($null -eq $rank) { $rank = Get-PqNextRank -Registry $Registry -HarnessRoot $harness -Exclude $rankExclude -Occupied $rankOccupied -Slots 1 -StopAfter 1 -HeadFilter $xrepoFilter -HeadLift $xrepoLift -PickerCache $turnPickerCache @repoOnly }
                    $liftRows = @{}
                    foreach ($lf in @(Get-PqValue $rank 'lifts' @())) { $liftRows[[string]$lf.blocked] = $lf }
                    foreach ($hr in @(Get-PqValue $rank 'headRefused' @())) {
                        $xb = $hr.refusal
                        $xbKey = "$($hr.repo):$($hr.id)"
                        $lf = if ($liftRows.ContainsKey($xbKey)) { $liftRows[$xbKey] } else { $null }
                        $rootKey = if ($null -ne $lf) { [string]$lf.root } else { '' }
                        # Not added to $exclude: keeping the refused ticket in the walk lets -HeadFilter and -HeadLift offer
                        # its chain root on every turn while the blocker holds; $xblocked keeps the notice and event once per
                        # (blocker, root).
                        if ($xblocked.ContainsKey($xbKey) -and $xblocked[$xbKey].blocker -ceq $xb.blocker -and [string]$xblocked[$xbKey].root -ceq $rootKey) { continue }
                        $xblocked[$xbKey] = @{ repo = [string]$hr.repo; id = [string]$hr.id; blocker = $xb.blocker; root = $rootKey }
                        # The root of the chain and what became of it (TASK-FLOW 0.38 section 16): optional keys of the event
                        # and a tail of the printed line, so the owner sees what the waiting ticket is really waiting for.
                        $xd = [ordered]@{ blocked = $xbKey; blocker = $xb.blocker; state = $xb.state; blockerStatus = $xb.status }
                        $liftTail = ''
                        if ($null -ne $lf) {
                            $xd.root = [string]$lf.root
                            $xd.rootStatus = [string]$lf.status
                            $xd.lift = $(if ($lf.offered) { 'offered' } else { 'notOffered' })
                            if (-not $lf.offered) { $xd.liftWhy = [string]$lf.why }
                            $liftTail = "; root $($lf.root) ($($lf.status)): " + $(if ($lf.offered) { 'offered first' } else { "not worked ($($lf.why))" })
                        }
                        $null = Write-PqEvent -Log $log -Ev 'xrepo.resolve' -Run $runId -Repo $hr.repo -Id $hr.id -Worker $slot -D $xd
                        if ($xb.state -ceq 'cycle') { $null = Write-PqEvent -Log $log -Ev 'xrepo.cycle' -Run $runId -Worker $slot -D ([ordered]@{ members = @($xbKey, $xb.blocker) }) }
                        $null = Write-PqEvent -Log $log -Ev 'ticket.blocked' -Run $runId -Repo $hr.repo -Id $hr.id -Worker $slot -D ([ordered]@{ status = [string]$hr.status; why = (ConvertTo-PqCut $xb.why 80); blocker = $xb.blocker })
                        Write-Host "ticket $xbKey waits on $($xb.blocker) ($($xb.state): $($xb.why))$liftTail"
                    }
                }
                # Rule 58 (S0082): every rank is one picker call of the hour's poll.summary; a drain carry ranks nothing.
                $rankMs = Get-PqValue $rank 'ms'
                if ($null -ne $rankMs) { Add-PqPickerStat -Stats $pollStats -Log $log -Ms ([double]$rankMs) }
                foreach ($e in @($rank.events)) {
                    if ($e.ev -ceq 'queue.row') {
                        $rowKey = if ($null -ne $e.d.line -and [string]$e.d.line -ne '' -and [string]$e.d.line -ne '0') { [string]$e.d.line } else { "$($e.d.kind):$($e.d.text)" }
                        $rowSig = "$($e.d.kind)|$($e.d.text)"
                        if ($loggedBadQueueRows.ContainsKey($rowKey) -and $loggedBadQueueRows[$rowKey] -ceq $rowSig) {
                            continue
                        }
                        $loggedBadQueueRows[$rowKey] = $rowSig
                    }
                    $null = Write-PqEvent -Log $log -Ev $e.ev -Run $runId -Worker $slot -D $e.d
                }

                # A repository's own shared stop file (rule 26) takes it out of the rank without a word: no event names it, and
                # a freeze that expired while nobody opened the repository leaves its stop in place for good - the freeze is
                # cleared only when something reads it, and a repository the robot skips is never read. Said once per change,
                # on the console like an occupied repository (the event catalog has no value for it), with the file's age.
                $stoppedNow = @{}
                foreach ($sk in @($rank.skipped)) { if ([string](Get-PqValue $sk 'why' '') -ceq 'stopped') { $stoppedNow[[string]$sk.repo] = $true } }
                foreach ($sk in @($stoppedNow.Keys)) {
                    if ($stopNoticeState.ContainsKey($sk)) { continue }
                    $stopNoticeState[$sk] = $true
                    # Its own local name: $stopPath is the portfolio's STOP for the whole run, and this block must not rebind it.
                    $repoStop = ''
                    $stopAge = ''
                    try {
                        $repoStop = [string](Get-PqRepoPaths -RepoPath ([string]$byKey[$sk].path)).StopFile
                        $stopAge = ' (written {0:N1} h ago)' -f (([DateTime]::UtcNow - [IO.File]::GetLastWriteTimeUtc($repoStop)).TotalHours)
                    }
                    catch { }
                    Write-Host "repository $sk is stopped - its own stop file $repoStop$stopAge; the robot takes no ticket there until it is gone (a release freeze clears it when read after its expiry: run the repository's release-freeze Status; or delete the file)"
                }
                foreach ($sk in @($stopNoticeState.Keys)) { if (-not $stoppedNow.ContainsKey($sk)) { $stopNoticeState.Remove($sk) } }

                # 5. Handle empty candidates
                if (@($rank.candidates).Count -eq 0) {
                    $turnPickerCache.Clear()
                    $noAgentSaid = ''
                    if ($null -ne $named) {
                        # Never waits and never takes another ticket: the loop's own mark (a blocker, a resource, the
                        # owner's occupancy, the worker cap) first, then what the rank said about the named ticket.
                        $namedFail = Get-PqNamedNotRunReason -Rank $rank -Key $named.repo -Id $named.id -Marks @{ xblocked = $xblocked; transient = $transient; occupied = $occupiedMarks; exclude = @($exclude) }
                        $null = Write-PqEvent -Log $log -Ev 'run.stop' -Run $runId -Worker $slot -D ([ordered]@{ level = 'drain'; reason = 'owner'; passesInFlight = 0 })
                        break
                    }
                    if ($Drain) {
                        if ($passCount -eq 0) { Write-Host 'nothing to do' }
                        $null = Write-PqEvent -Log $log -Ev 'run.stop' -Run $runId -Worker $slot -D ([ordered]@{
                            level = 'drain'
                            reason = 'owner'
                            passesInFlight = 0
                        })
                        $exitCode = if ($passCount -gt 0) { 0 } else { 3 }
                        break
                    }

                    # Wait (rules 41, 58; R29-R34). The wait costs no agent and no picker: once per poll the files a change in
                    # which could make a ticket offerable are compared with what they were at the last rank (their sizes and
                    # write times, nothing is parsed). A change is not acted on at once but after one more quiet poll
                    # (R32: the owner who just captured a Draft may still be editing it); a rank also runs every tenth
                    # poll with no change, because some eligibility is time-based (an idle hold, an agent's limit, the
                    # owner's occupancy window), and every poll while the loop itself holds something back for a moment.
                    $poll = if ($PollSeconds -gt 0) { $PollSeconds } else { [int]$Registry.pollSeconds }
                    $nowUtc = [DateTime]::UtcNow
                    $whyCounts = Get-PqWaitReasons -Rank $rank -Dropped $drops.Count -Xrepo $xblocked.Count -Transient $transient
                    if ($occupiedMarks.Count -gt 0 -and -not $whyCounts.Contains('occupied')) { $whyCounts['occupied'] = $occupiedMarks.Count; [void]$whyCounts.Remove('none') }
                    # The console line speaks the owner's words (held, frozen, disabled); the event below keeps $whyCounts.
                    $waitWords = Get-PqWaitWords -Rank $rank -Why $whyCounts
                    $waitSummary = (@($waitWords.Keys | ForEach-Object { "$_ $($waitWords[$_])" }) -join ', ')
                    $null = Write-PqEvent -Log $log -Ev 'wait.enter' -Run $runId -Worker $slot -D ([ordered]@{ open = 0; why = $whyCounts })
                    if (-not $waiting -or $waitSummary -cne $waitSaid) {
                        Write-Host "waiting for tickets (poll ${poll}s) - nothing offerable: $waitSummary"
                        $waiting = $true
                        $waitSaid = $waitSummary
                    }
                    $waitSw = [Diagnostics.Stopwatch]::StartNew()
                    $trigger = 'heartbeat'
                    while ($true) {
                        $sliceEnd = $waitSw.ElapsedMilliseconds + ([long]$poll * 1000)
                        $interrupted = $false
                        while ($waitSw.ElapsedMilliseconds -lt $sliceEnd) {
                            Start-Sleep -Milliseconds ([Math]::Min(1000, [Math]::Max(50, [int]($sliceEnd - $waitSw.ElapsedMilliseconds))))
                            if ([IO.File]::Exists($stopPath) -or $null -ne (Get-PqApplicableStop -Stops @(Get-PqStopFiles) -Slot $slot)) { $trigger = 'owner'; $interrupted = $true; break }
                            if ($null -ne $Until -and [DateTime]::Now -ge $Until) { $trigger = 'until'; $interrupted = $true; break }
                        }
                        if ($interrupted) { break }
                        $fpNow = Get-PqFingerprint -Registry $Registry -PathsCache $pathsCache -Extra (Get-PqDropFingerprint $drops)
                        $cmp = Compare-PqFingerprint $lastFp $fpNow
                        if ($cmp.changed) {
                            $lastFp = $fpNow
                            $settling = $true
                            Add-PqPollStat -Stats $pollStats -Log $log -Change
                            $null = Write-PqEvent -Log $log -Ev 'poll.change' -Run $runId -Worker $slot -D ([ordered]@{ files = @($cmp.files); repos = @($cmp.repos) })
                            if (@($cmp.files) -contains 'ledger' -or @($cmp.files) -contains 'archive') {
                                $null = Invoke-PqLedgerWatch -Registry $Registry -Log $log -Run $runId -Worker $slot -Repos @($cmp.repos) -PathsCache $pathsCache
                            }
                            continue
                        }
                        if ($settling) {
                            $settling = $false
                            $trigger = 'change'
                            Add-PqPollStat -Stats $pollStats -Log $log -Rerank
                            break
                        }
                        $quietPolls++
                        $pollUtc = [DateTime]::UtcNow
                        $markDue = $false
                        foreach ($mk in @($occupiedMarks.Keys)) { if ($occupiedMarks[$mk].until -le $pollUtc) { $markDue = $true; break } }
                        if (-not $markDue) {
                            foreach ($mk in @($transient.Keys)) {
                                $tr = $transient[$mk]
                                if ($tr.until -le $pollUtc) { $markDue = $true; break }
                                if ([string]$tr.why -ceq 'noAgent' -and $tr.repoPath -and $null -ne (Select-PqAgent -Registry $Registry -RepoPath ([string]$tr.repoPath) -Level ([string]$tr.level) -Skip $stopAgents -Score ([int]$tr.score)).agent) {
                                    $markDue = $true; break
                                }
                            }
                        }
                        if ($markDue -or $quietPolls -ge 10) {
                            $quietPolls = 0
                            $trigger = 'heartbeat'
                            Add-PqPollStat -Stats $pollStats -Log $log -Rerank -HeartbeatRerank
                            break
                        }
                        Add-PqPollStat -Stats $pollStats -Log $log -SkippedUnchanged
                    }
                    $waitSw.Stop()
                    $null = Write-PqEvent -Log $log -Ev 'wait.exit' -Run $runId -Worker $slot -D ([ordered]@{
                        waited = [Math]::Round($waitSw.ElapsedMilliseconds / 1000, 1)
                        trigger = $trigger
                    })
                    # A stop or the end time is acted on at the top of the next turn, with its own event.
                    continue
                }

                # 6. We have a candidate
                $cand = $rank.candidates[0]
                # A named start runs the named ticket or nothing: the rank offers that one entry, and this is the guard.
                if ($null -ne $named -and ([string]$cand.repo -cne $named.repo -or [string]$cand.id -cne $named.id)) {
                    $namedFail = "the rank offered $($cand.repo):$($cand.id) instead - not taken"
                    break
                }
                if ($waiting) { Write-Host 'queue resumed'; $waiting = $false }
                $repoKey = [string]$cand.repo
                $ticketId = [string]$cand.id
                $ticketTitle = [string]$cand.title
                $repoRec = $byKey[$repoKey]
                $turnRepo = $repoKey
                $turnId = $ticketId
                $repoPath = [string]$repoRec.path
                $turnPath = $repoPath
                $isConcurrent = (Get-PqValue $repoRec 'concurrent' $false) -eq $true

                # Rule 52: a blocker in another repository that is not released keeps the ticket out; rank again at once.
                $xb = Get-PqXrepoBlock -Registry $Registry -RepoKey $repoKey -TicketId $ticketId
                if ($null -ne $xb) {
                    $xbKey = "$repoKey`:$ticketId"
                    $exclude.Add($xbKey)
                    $xblocked[$xbKey] = @{ repo = $repoKey; id = $ticketId; blocker = $xb.blocker }
                    $null = Write-PqEvent -Log $log -Ev 'xrepo.resolve' -Run $runId -Repo $repoKey -Id $ticketId -Worker $slot -D ([ordered]@{ blocked = $xbKey; blocker = $xb.blocker; state = $xb.state; blockerStatus = $xb.status })
                    if ($xb.state -ceq 'cycle') { $null = Write-PqEvent -Log $log -Ev 'xrepo.cycle' -Run $runId -Worker $slot -D ([ordered]@{ members = @($xbKey, $xb.blocker) }) }
                    $null = Write-PqEvent -Log $log -Ev 'ticket.blocked' -Run $runId -Repo $repoKey -Id $ticketId -Worker $slot -D ([ordered]@{ status = [string]$cand.status; why = (ConvertTo-PqCut $xb.why 80); blocker = $xb.blocker })
                    Write-Host "ticket $xbKey waits on $($xb.blocker) ($($xb.state): $($xb.why))"
                    $rerankAfterSkip = $true
                    continue
                }

                # Rule 61: the robot yields to the owner. A live manual session (a transcript written within
                # occupiedMinutes, a live lease no pass holds) means no pass is launched; the repository is looked
                # at again in half a minute, and the next repository of the rank is tried meanwhile.
                $namedRepo = [bool]$OnlyRepo -and $repoKey -ieq $OnlyRepo
                $occ = Get-PqRepoOccupancy -Repo $repoRec -Registry $Registry -HarnessRoot $harness -SkipTranscript:$namedRepo
                if ($occ.occupied) {
                    $occupiedMarks[$repoKey] = @{ until = [DateTime]::UtcNow.AddSeconds([Math]::Max(30, [int](Get-PqValue $occ 'freeInSeconds' 0))); why = 'occupied' }
                    if (-not $occupancyState.ContainsKey($repoKey)) {
                        $occupancyState[$repoKey] = New-PqOccupancyMark $occ
                        $null = Write-PqEvent -Log $log -Ev 'repo.occupied' -Run $runId -Repo $repoKey -Worker $slot -D ([ordered]@{ by = $occ.by; holderKind = $occ.holderKind; age = $occ.ageSeconds })
                        Write-Host "repository $repoKey is occupied ($($occ.by), $($occ.ageSeconds) s ago) - the robot waits for the owner"
                    }
                    $null = Write-PqEvent -Log $log -Ev 'dispatch.skip' -Run $runId -Repo $repoKey -Id $ticketId -Worker $slot -D ([ordered]@{ why = 'occupied' })
                    $rerankAfterSkip = $true
                    continue
                }
                if ($occupancyState.ContainsKey($repoKey)) {
                    $null = Write-PqEvent -Log $log -Ev 'repo.free' -Run $runId -Repo $repoKey -Worker $slot -D (Get-PqRepoFreeData $occupancyState[$repoKey])
                    $occupancyState.Remove($repoKey)
                    Write-Host "repository $repoKey is free again"
                }

                $rec = Get-PqTicketRecord -RepoPath $repoPath -Id $ticketId -HarnessRoot $harness
                if (-not $ticketTitle) {
                    if ($rec -and $rec.name) { $ticketTitle = [string]$rec.name }
                    elseif ($rec -and $rec.title) { $ticketTitle = [string]$rec.title }
                }
                $ticketStatus = if ($rec -and $rec.status) { [string]$rec.status } else { '' }
                if (-not $ticketTitle -or -not $ticketStatus) {
                    try {
                        $repoPaths = Get-PqRepoPaths -RepoPath $repoPath
                        $planDir = $repoPaths.SpecsDir
                        if ([IO.Directory]::Exists($planDir)) {
                            $files = [IO.Directory]::GetFiles($planDir, "$ticketId*.md")
                            if ($files.Length -gt 0) {
                                # ReadAllLines: a foreach over ReadLines left by break keeps the spec open in this
                                # process, and the robot's own write of this ticket's spec is then refused.
                                foreach ($line in [IO.File]::ReadAllLines($files[0])) {
                                    if (-not $ticketTitle -and $line -match '^#\s+(?:' + [regex]::Escape($ticketId) + '\s*[-:]\s*)?(?<title>.+)$') {
                                        $ticketTitle = $Matches['title'].Trim()
                                    }
                                    if (-not $ticketStatus -and $line -match '^\*\*Status:\*\*\s*(.+)$') {
                                        $ticketStatus = $Matches[1].Trim()
                                    }
                                    if ($ticketTitle -and $ticketStatus) { break }
                                }
                            }
                        }
                    } catch { }
                }

                # The agent of this pass (rule 42): the first of agentOrder that is not held, under its maxParallel, admits
                # the ticket's level and can reach the repository's pipeline. No declared level runs at medium (rule 51).
                # TASK-FLOW 0.32 (S0139): the grade decides too - an agent with no route for it is passed over
                # (aboveCeiling), and an ungraded ticket is graded once by the registry's raters first (rule 71).
                $levelInfo = Get-PqTicketLevelInfo -RepoPath $repoPath -TicketId $ticketId
                $ticketRated = $false
                if (Test-PqRaterDue -Registry $Registry -Info $levelInfo -Key "$repoKey`:$ticketId" -Tried $raterTried) {
                    $rateRes = Invoke-PqTicketRating -Registry $Registry -Info $levelInfo -RepoKey $repoKey -TicketId $ticketId -Log $log -Run $runId -Worker $slot
                    $raterTried["$repoKey`:$ticketId"] = $true
                    if ($rateRes.ok) { $ticketRated = $true }
                    # Read again whatever the answer: another worker may have graded the ticket meanwhile.
                    $levelInfo = Get-PqTicketLevelInfo -RepoPath $repoPath -TicketId $ticketId
                }
                $ticketLevel = [string]$levelInfo.level
                $ticketScore = [int]$levelInfo.score
                $pick = Select-PqAgent -Registry $Registry -RepoPath $repoPath -Level $(if ($ticketLevel) { $ticketLevel } else { 'medium' }) -Skip $stopAgents -Score $ticketScore
                foreach ($fb in @($pick.fallbacks)) {
                    if (-not (Test-PqFallbackWhy ([string]$fb.why))) { continue }
                    $null = Write-PqEvent -Log $log -Ev 'agent.fallback' -Run $runId -Repo $repoKey -Id $ticketId -Worker $slot -D ([ordered]@{ from = $fb.from; to = $pick.agent; repo = $repoKey; id = $ticketId; why = $fb.why })
                }
                if (-not $pick.agent) {
                    $null = Write-PqEvent -Log $log -Ev 'dispatch.skip' -Run $runId -Repo $repoKey -Id $ticketId -Worker $slot -D ([ordered]@{ why = 'noAgent' })
                    # Said once per change, not every half minute: a weekly limit is a wait of days.
                    $noAgentWhy = Get-PqNoAgentSummary -Pick $pick -Registry $Registry
                    if ($null -ne $named) { $namedFail = "no provider of the order may take it now ($noAgentWhy)"; break }
                    $noAgentHold = Get-PqNoAgentHold -Pick $pick -Registry $Registry
                    if ($noAgentHold.passOver) {
                        $tk = "$repoKey`:$ticketId"
                        $transient[$tk] = @{ until = $noAgentHold.until; why = 'noAgent'; repoPath = $repoPath; level = $(if ($ticketLevel) { $ticketLevel } else { 'medium' }); score = $ticketScore }
                        if (-not $transientSaid.ContainsKey($tk)) {
                            $transientSaid[$tk] = $true
                            Write-Host "ticket $tk - no provider of the order may take it now ($noAgentWhy) - the next ticket is taken"
                        }
                        $rerankAfterSkip = $true
                        continue
                    }
                    $turnPickerCache.Clear()
                    $noAgentKey = "$repoKey`:$ticketId|$noAgentWhy"
                    if ($noAgentKey -cne $noAgentSaid) {
                        Write-Host "ticket $repoKey`:$ticketId - no provider of the order may take it now ($noAgentWhy); checking again every 30 s"
                        $noAgentSaid = $noAgentKey
                    }
                    for ($w = 0; $w -lt 30 -and -not [IO.File]::Exists($stopPath); $w++) { Start-Sleep -Seconds 1 }
                    continue
                }

                # S0035: When the first provider's reset is less than 15 minutes away, wait for it instead of handing
                # a half-done (In Progress) ticket to the next provider.
                $primaryWait = Get-PqPrimaryResetWait -Registry $Registry -TicketStatus $ticketStatus -PickedAgent $pick.agent
                if ($null -ne $primaryWait) {
                    $tk = "$repoKey`:$ticketId"
                    $transient[$tk] = @{ until = $primaryWait.Until; why = 'limitResetNear' }
                    $null = Write-PqEvent -Log $log -Ev 'dispatch.skip' -Run $runId -Repo $repoKey -Id $ticketId -Worker $slot -D ([ordered]@{
                        why = 'limitResetNear'
                        agent = $primaryWait.Agent
                        until = $primaryWait.UntilIso
                    })
                    if (-not $transientSaid.ContainsKey($tk)) {
                        $transientSaid[$tk] = $true
                        Write-Host "ticket $tk is In Progress and primary provider '$($primaryWait.Agent)' resets in $([Math]::Round($primaryWait.DiffMinutes, 1)) min - waiting instead of fallback to '$($pick.agent)'"
                    }
                    $rerankAfterSkip = $true
                    continue
                }
                $noAgentSaid = ''
                $agentName = [string]$pick.agent
                $ticketParallelFlag = [bool](Get-PqValue $levelInfo 'parallel' $false)
                $agentArgs = if ($agentName -ceq 'claude') { @(Get-PqClaudePassArgs $pick ([string]$cand.status) $ticketParallelFlag) } else { Get-PqAgentPassArgs $pick }
                # S0140: the parallel axis this pass launches with ('' for none), for pass.launch.
                $pickParallel = if ($agentName -ceq 'claude') { Get-PqClaudeParallel $pick ([string]$cand.status) $ticketParallelFlag } else { '' }
                $passCx = Get-PqPassCx $ticketLevel $agentName -Rated:$ticketRated
                # With the status: an audit pass of claude takes no route model or effort, so the log names none.
                $pickModel = Get-PqPickModel $pick ([string]$cand.status)
                $pickEffort = [string](Get-PqPickLaunch $pick ([string]$cand.status)).effort
                $pickScore = [int]$pick.score

                # Rule 48 (S0082): past a poll hold's limitPollMinutes the pass is its probe, and the assignment's agent cap of
                # 1 lets exactly one worker take it; the others see the agent held while it runs.
                $isProbe = Test-PqAgentProbeDue (Get-PqAgentHold $agentName) $pick.record
                if (-not (Request-PqWorkerAssignment -Slot $slot -Repo $repoRec -Ticket $ticketId -Title $ticketTitle -Agent $agentName -AgentMax (Get-PqPassAgentMax $pick))) {
                    $occupiedMarks[$repoKey] = @{ until = [DateTime]::UtcNow.AddSeconds(5); why = 'workerCap' }
                    if ($script:PqAssignmentWhy -and (Test-PqSkipDue "$repoKey`:$ticketId`:$($script:PqAssignmentWhy)")) { $null = Write-PqEvent -Log $log -Ev 'dispatch.skip' -Run $runId -Repo $repoKey -Id $ticketId -Worker $slot -D ([ordered]@{ why = $script:PqAssignmentWhy }) }
                    $rerankAfterSkip = $true
                    continue
                }
                # Rule 58 (S0082): the pick explained - the candidate, the alternatives the walk passed over, the agent.
                $null = Write-PqEvent -Log $log -Ev 'dispatch.pick' -Run $runId -Repo $repoKey -Id $ticketId -Worker $slot -Agent $agentName -Model $pickModel -Cx $passCx.cx -D (Get-PqDispatchPickData $cand $pick $Registry $passCx.cx $pickModel)

                # Rule 62: the machine-wide tokens the ticket's own **Verify:** level takes (build, emulator); a ticket that
                # cannot get them is passed over for a minute and the next candidate is taken; a device ticket takes none (0.21).
                $verify = Get-PqTicketVerify -RepoPath $repoPath -TicketId $ticketId
                $passIdNext = "$runId.$($passCount + 1)"
                $resReq = Request-PqResources -Registry $Registry -RepoKey $repoKey -TicketId $ticketId -Verify $verify -PassId $passIdNext
                foreach ($sk in @($resReq.stale)) { $null = Write-PqEvent -Log $log -Ev 'resource.release' -Run $runId -Worker $slot -D (Get-PqResourceEventData $resReq ($sk -split '/')[0] $verify $sk) }
                if (-not $resReq.ok) {
                    Set-PqWorkerState -Slot $slot
                    $tk = "$repoKey`:$ticketId"
                    $recheck = 60
                    $transient[$tk] = @{ until = [DateTime]::UtcNow.AddSeconds($recheck); why = 'resource' }
                    $null = Write-PqEvent -Log $log -Ev 'dispatch.skip' -Run $runId -Repo $repoKey -Id $ticketId -Worker $slot -D ([ordered]@{ why = $resReq.why })
                    if ($resReq.why -ceq 'resource') {
                        $null = Write-PqEvent -Log $log -Ev 'resource.wait' -Run $runId -Repo $repoKey -Id $ticketId -Worker $slot -D ([ordered]@{ resource = $resReq.resource; verify = $verify; held = $resReq.heldCount; cap = $resReq.cap })
                    }
                    if (-not $transientSaid.ContainsKey($tk)) {
                        $transientSaid[$tk] = $true
                        Write-Host "ticket $tk waits for the $($resReq.resource) resource ($($resReq.heldCount) of $($resReq.cap) held) - the next ticket is taken"
                    }
                    $rerankAfterSkip = $true
                    continue
                }
                $turnPickerCache.Clear()
                if (@($resReq.held).Count -gt 0) {
                    $heldResources = @($resReq.held)
                    $heldResourcesRepo = $repoKey
                    $heldResourcesId = $ticketId
                    foreach ($ht in $heldResources) {
                        $null = Write-PqEvent -Log $log -Ev 'resource.acquire' -Run $runId -Repo $repoKey -Id $ticketId -Pass $passIdNext -Worker $slot -D (Get-PqResourceEventData $resReq $ht $verify)
                    }
                }

                if (-not $isConcurrent) {
                    $currentRepoLock = Lock-PqRepo -RepoKey $repoKey
                    if (-not $currentRepoLock) {
                        if ($null -ne $heldResources) { $null = Remove-PqResources -RepoKey $heldResourcesRepo -TicketId $heldResourcesId; $heldResources = $null }
                        Set-PqWorkerState -Slot $slot
                        continue
                    }
                }

                # A stop may arrive while a repository's picker is running.
                if ([IO.File]::Exists($stopPath)) {
                    if ($null -ne $heldResources) { $null = Remove-PqResources -RepoKey $heldResourcesRepo -TicketId $heldResourcesId; $heldResources = $null }
                    if ($currentRepoLock) { Unlock-PqRepo -LockFile $currentRepoLock; $currentRepoLock = $null }
                    Set-PqWorkerState -Slot $slot
                    continue
                }

                $passNum = $passCount + 1
                $passId = "$runId.$passNum"
                $statusBefore = [string]$cand.status

                $permMode = Get-PqValue $repoRec 'permissionMode'
                if (-not $permMode) { $permMode = Get-PqValue $Registry 'permissionMode' }
                if (-not $permMode) { throw "PermissionModeMissing: set permissionMode for $repoKey before starting unattended work" }

                $onStarted = {
                    param($childPid, [string[]]$childArgv)
                    # S0082 (EVENTS 3.4): argvHash, promptForm, cxSource, profileHash and heads; model and cx in the envelope.
                    # S0139 (EVENTS section 8): the grade the pass was chosen at, and the effort when the route or record names one.
                    $launchD = [ordered]@{
                        instance = "pq$slot"
                        argvHash = Get-PqArgvHash $childArgv
                        promptForm = [string](Get-PqValue $pick.record 'promptForm' 'slash')
                        permission = $permMode
                        statusBefore = $statusBefore
                        cxSource = $passCx.cxSource
                        score = $pickScore
                        profileHash = $profileHash
                        pid = $childPid
                        heads = @(Get-PqValue $rank 'heads' @()).Count
                    }
                    if ($pickEffort) { $launchD.effort = $pickEffort }
                    if ($pickParallel) { $launchD.parallel = $pickParallel }
                    $null = Write-PqEvent -Log $log -Ev 'pass.launch' -Run $runId -Repo $repoKey -Id $ticketId -Pass $passId -Worker $slot -Agent $agentName -Model $pickModel -Cx $passCx.cx -D $launchD
                    if ($currentRepoLock) { Set-PqRepoLockPass -LockFile $currentRepoLock -PassPid $childPid }
                }

                $actualRunner = if ($RunnerScript) { $RunnerScript } elseif ($env:SZA_PQ_RUNNER_SCRIPT) { $env:SZA_PQ_RUNNER_SCRIPT } else { Join-Path $harness 'batch\run-spec-queue.ps1' }
                $paths = Get-PqRepoPaths -RepoPath $repoPath
                $journal = Join-Path $paths.RunsDir "runs-pq$slot.jsonl"
                $journalOffset = if ([IO.File]::Exists($journal)) { [IO.FileInfo]::new($journal).Length } else { 0 }
                $canonVersion = ([IO.File]::ReadAllText((Join-Path $harness '..\..\CANON_VERSION'))).Trim()
                $pluginVersion = (ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $harness '..\..\.claude-plugin\plugin.json')))).version
                $profilePath = Join-Path $repoPath '.sza-profile.json'
                $profileHash = if ([IO.File]::Exists($profilePath)) { Get-PqFileHash ([IO.File]::ReadAllBytes($profilePath)) } else { '' }
                $passSw = [Diagnostics.Stopwatch]::StartNew()
                $passBegan = [DateTime]::Now
                $titlePart = if ($ticketTitle) { " - $ticketTitle" } else { '' }
                # Every pass names its provider, claude included - an untagged line left the owner guessing which of the
                # subscription, the API credits or z.ai took the ticket. The route's model and effort follow when it names them
                # (a plain claude pass names none here: the runner picks its model from the ticket, and its banner prints it).
                $agentDetail = if ($pickModel -and $pickEffort) { "$pickModel/$pickEffort" } elseif ($pickModel) { [string]$pickModel } elseif ($pickEffort) { "effort $pickEffort" } else { '' }
                $agentPart = " [$agentName$(if ($agentDetail) { ' ' + $agentDetail })]"

                # The tickets of the repository before the pass: whatever is new after it, the pass filed (D5). The session the
                # pass runs under is read from the lease the runner took for it, so its own transcript is never taken for the
                # owner's (rule 61); the stop files that name this pass are read every second (rule 47).
                $idsBefore = Get-PqTicketIds $repoPath
                $pqPassSessions = [Collections.Generic.HashSet[string]]::new()
                $pqLeaseFile = Join-Path $paths.LeasesDir "$ticketId.json"
                $pqSlot = $slot
                $pqRepo = $repoKey
                $pqAgent = $agentName
                $pqTicket = "$repoKey`:$ticketId"
                $onTick = {
                    $l = Read-PqState $pqLeaseFile
                    $sid = [string](Get-PqValue $l 'sessionId' '')
                    if ($sid -and (Test-PqLeaseIsPass $l $null)) { [void]$pqPassSessions.Add($sid) }
                }
                $stopWatcher = { Get-PqApplicableStop -Stops @(Get-PqStopFiles) -Slot $pqSlot -Repo $pqRepo -Agent $pqAgent -Ticket $pqTicket }
                $onBeat = {
                    param($sec)
                    $null = Write-PqEvent -Log $log -Ev 'pass.beat' -Run $runId -Repo $repoKey -Id $ticketId -Pass $passId -Worker $slot -Agent $agentName -D ([ordered]@{
                        elapsed = $sec
                        liveness = 'working'
                    })
                    Update-PqWorkerSeen -Slot $slot
                }

                Write-Host "pass $passNum $repoKey`:$ticketId $statusBefore$titlePart$agentPart - started"
                # The live view follows a Claude-CLI pass (claude, and z.ai which runs the same CLI) and a Codex pass; the others
                # keep no file while they work. SZA_PQ_FOLLOW=0 turns it off.
                $followKind = if ($env:SZA_PQ_FOLLOW -ceq '0') { '' }
                    elseif ($agentName -cmatch '^codex') { 'codex' }
                    elseif ([IO.Path]::GetFileNameWithoutExtension([string](Get-PqValue $pick.record 'command' '')) -ieq 'claude') { 'claude' }
                    else { '' }
                $childRes = Invoke-PqPassChild -Script $actualRunner -RepoPath $repoPath -TicketId $ticketId -TicketTitle $ticketTitle -Instance "pq$slot" -PermissionMode $permMode -OnStarted $onStarted -AgentArgs $agentArgs -OnTick $onTick -StopWatcher $stopWatcher -OnBeat $onBeat -Follow $followKind -Agent $agentName
                $passSw.Stop()
                $elapsedSec = [Math]::Round($passSw.ElapsedMilliseconds / 1000, 1)
                Add-PqPassSessions -Ids @($pqPassSessions)
                if ($null -ne $heldResources) {
                    foreach ($ht in @(Remove-PqResources -RepoKey $heldResourcesRepo -TicketId $heldResourcesId)) {
                        $null = Write-PqEvent -Log $log -Ev 'resource.release' -Run $runId -Repo $repoKey -Id $ticketId -Pass $passId -Worker $slot -D ([ordered]@{ resource = $ht; verify = $verify })
                    }
                    $heldResources = $null
                }

                # Outcome and runs.jsonl row
                $namedPassRan = $true
                $outcomeRes = Read-PqPassOutcome -RepoPath $repoPath -Instance "pq$slot" -TicketId $ticketId -StatusBefore $statusBefore -ChildExitCode $childRes.code -HarnessRoot $harness -JournalOffset $journalOffset
                if ($childRes.killed) { $outcomeRes.outcome = $(if ($childRes.halted) { 'halted' } else { 'killed' }) }
                elseif ($childRes.failed) { $outcomeRes.outcome = 'launch-failed' }
                $runRow = [ordered]@{
                    run = $runId
                    pass = $passId
                    repo = $repoKey
                    id = $ticketId
                    agent = $agentName
                    model = $outcomeRes.model
                    complexity = $outcomeRes.complexity
                    statusBefore = $statusBefore
                    statusAfter = $outcomeRes.statusAfter
                    moved = [bool]$outcomeRes.moved
                    outcome = $outcomeRes.outcome
                    exitCode = $childRes.code
                    minutes = [Math]::Round($elapsedSec / 60, 2)
                    seconds = $elapsedSec
                    finishedAt = Get-PqRunRowTime
                    canon = $canonVersion
                    plugin = $pluginVersion
                    registryHash = $current.hash
                    profileHash = $profileHash
                }
                # agentExit is optional (rule 46): written when the repository journal row carries one, absent otherwise.
                $agentExitValue = Get-PqRunRowAgentExit $outcomeRes.exitCode
                if ($null -ne $agentExitValue) { $runRow.agentExit = $agentExitValue }
                if ($null -ne $outcomeRes.usage) { $runRow.usage = $outcomeRes.usage }
                if ($null -ne $outcomeRes.costUsd) { $runRow.costUsd = $outcomeRes.costUsd; $runRow.priceAsOf = $outcomeRes.priceAsOf }
                $runsJsonl = Join-Path $root 'runs.jsonl'
                Invoke-PqStateLock {
                    [IO.File]::AppendAllText($runsJsonl, (($runRow | ConvertTo-Json -Compress) + "`n"), [Text.Encoding]::UTF8)
                }
                $passCount++

                $mappedOutcome = ConvertTo-PqPassEndOutcome $outcomeRes.outcome
                # S0082: the envelope of pass.end carries the model the runner actually launched and the level it read.
                $endModel = if ($outcomeRes.model) { $outcomeRes.model } else { $pickModel }
                $endCx = if ($outcomeRes.complexity) { $outcomeRes.complexity } else { $passCx.cx }
                $null = Write-PqEvent -Log $log -Ev 'pass.end' -Run $runId -Repo $repoKey -Id $ticketId -Pass $passId -Worker $slot -Agent $agentName -Model $endModel -Cx $endCx -D ([ordered]@{
                    exit = $childRes.code
                    agentExit = $outcomeRes.exitCode
                    outcome = $mappedOutcome
                    launches = $outcomeRes.launches
                    statusBefore = $statusBefore
                    statusAfter = $outcomeRes.statusAfter
                    moved = [bool]$outcomeRes.moved
                    elapsed = $elapsedSec
                })
                # Rule 51 (S0082): a pass that rewrote the ticket's `**Complexity:**` line leaves ticket.complexity.
                $afterInfo = Get-PqTicketLevelInfo -RepoPath $repoPath -TicketId $ticketId
                $cxChange = Get-PqComplexityChange $ticketLevel ([string]$afterInfo.level) $statusBefore
                if ($null -ne $cxChange) {
                    $null = Write-PqEvent -Log $log -Ev 'ticket.complexity' -Run $runId -Repo $repoKey -Id $ticketId -Pass $passId -Worker $slot -Agent $agentName -Cx $cxChange.to -D $cxChange
                }
                # Rule 71 (TASK-FLOW 0.32, S0139): a failed pass raises a numeric, unpinned grade by escalateBy, so the
                # next launch takes an agent whose route admits it. A pass that changed the grade itself, inside the
                # same band included, is obeyed instead.
                if (-not (Test-PqGradeRewritten $levelInfo $afterInfo)) {
                    try {
                        $null = Invoke-PqTicketEscalation -Registry $Registry -Info $afterInfo -Outcome ([string]$outcomeRes.outcome) -StatusAfter ([string]$outcomeRes.statusAfter) -RepoKey $repoKey -TicketId $ticketId -Log $log -Run $runId -Pass $passId -Worker $slot -Agent $agentName
                    } catch { }
                }
                # Rule 59 (S0082): the pass's own moves are written now, with its id as viaPass, not at the next idle poll.
                $endedPass = @{ repo = $repoKey; id = $ticketId; pass = $passId; startedAt = [DateTimeOffset]$passBegan; endedAt = [DateTimeOffset]::UtcNow }
                $null = Invoke-PqLedgerWatch -Registry $Registry -Log $log -Run $runId -Worker $slot -Repos @($repoKey) -LivePasses @($endedPass) -PathsCache $pathsCache

                # Rule 47: halt and kill clean up and never decide a status. The lease the pass held is released (done in
                # Invoke-PqPassChild), the resources above; the locks dead processes left are cleared, the ledger is
                # checked, so a half-written row shows at once instead of at the next ticket, and the files the pass
                # changed are named (S0082); pass.halt / pass.kill and console lines tell you.
                if ($childRes.killed) {
                    $cleanup = Invoke-PqStopCleanup -RepoPath $repoPath -HarnessRoot $harness -Since $passBegan
                    $validate = $cleanup.validate
                    $cleanD = [ordered]@{ validate = $validate; locks = $cleanup.locks; changedFiles = @($cleanup.changed).Count }
                    if ($childRes.halted) {
                        $haltD = [ordered]@{ signal = 'none'; grace = 0; degradedToKill = $true }
                        foreach ($ck in $cleanD.Keys) { $haltD[$ck] = $cleanD[$ck] }
                        $null = Write-PqEvent -Log $log -Ev 'pass.halt' -Run $runId -Repo $repoKey -Id $ticketId -Pass $passId -Worker $slot -Agent $agentName -D $haltD
                    }
                    else {
                        $killD = [ordered]@{ level = 'kill' }
                        foreach ($ck in $cleanD.Keys) { $killD[$ck] = $cleanD[$ck] }
                        $null = Write-PqEvent -Log $log -Ev 'pass.kill' -Run $runId -Repo $repoKey -Id $ticketId -Pass $passId -Worker $slot -Agent $agentName -D $killD
                    }
                    $lockText = (@($cleanup.locks.Keys | ForEach-Object { "$_ $($cleanup.locks[$_])" }) -join ', ')
                    Write-Host "pass $passNum ended by the owner's $(if ($childRes.halted) { 'halt' } else { 'kill' }); lease and resources released, dead locks cleared ($lockText; 1 = a live holder kept), ledger validate: $validate"
                    $changedList = @($cleanup.changed)
                    if ($changedList.Count -eq 0) { Write-Host "  no file of $repoKey changed since the pass began" }
                    else {
                        Write-Host "  $($changedList.Count) file(s) of $repoKey changed since the pass began - check them before the next pass:"
                        foreach ($cf in @($changedList | Select-Object -First 20)) { Write-Host "    $cf" }
                        if ($changedList.Count -gt 20) { Write-Host "    .. and $($changedList.Count - 20) more (git status in $repoPath)" }
                    }
                }

                # D5 (TASK-FLOW rule 41, robotDraftCap): a ticket the pass filed carries `source` robot on its ledger row,
                # and the count is the ledger's own - the robot-filed rows of the repository created on this local day
                # (Get-PqRobotFiled). No worker remembers it, so it is the same after a restart and for every worker, and
                # a ticket the owner or a desk session filed while the pass ran is never counted. The ones past the cap
                # are kept out of every rank until the day ends (Get-PqIntakeCapped in Get-PqNextRank); the owner is told.
                $newIds = @(Get-PqNewTicketIds $idsBefore (Get-PqTicketIds $repoPath))
                if ($newIds.Count -gt 0) {
                    $draftCap = [int](Get-PqValue $Registry 'robotDraftCap' 20)
                    $robotToday = [string[]]@()
                    $cappedToday = [string[]]@()
                    try {
                        $filed = Get-PqRobotFiled -RepoPath $repoPath -Day (Get-PqLocalDay) -Cap $draftCap
                        $robotToday = [string[]]@($filed.counted)
                        $cappedToday = [string[]]@($filed.capped)
                    }
                    catch { }
                    $beyond = 0
                    foreach ($nid in $newIds) {
                        $at = [Array]::IndexOf($robotToday, [string]$nid)
                        if ($at -lt 0) { continue }
                        $capped = ($cappedToday -ccontains $nid)
                        $null = Write-PqEvent -Log $log -Ev 'intake.robotDraft' -Run $runId -Repo $repoKey -Id $nid -Pass $passId -Worker $slot -D ([ordered]@{ count = ($at + 1); cap = $draftCap; capped = $capped })
                        if ($capped) {
                            $beyond++
                            $null = Write-PqEvent -Log $log -Ev 'dispatch.skip' -Run $runId -Repo $repoKey -Id $nid -Worker $slot -D ([ordered]@{ why = 'intakeCap' })
                        }
                    }
                    Write-Host "pass $passNum left $($newIds.Count) new ticket(s) in ${repoKey}: $($newIds -join ', ') (robot-filed today: $($robotToday.Length) of $draftCap)"
                    if ($beyond -gt 0) { Write-Host "the cap of $draftCap robot-filed tickets a day in $repoKey is reached - the $beyond beyond it wait for tomorrow or for the owner" }
                }

                $detectorStatus = [string](Get-PqValue (Get-PqValue $pick.record 'limitDetector') 'status' 'unproven')
                if (-not $detectorStatus) { $detectorStatus = 'unproven' }
                $patternId = [string](Get-PqValue (Get-PqValue $pick.record 'limitDetector') 'pattern' '')
                for ($limit = 0; $limit -lt $outcomeRes.limits; $limit++) {
                    $evD = [ordered]@{
                        agent = $agentName
                        source = 'log'
                        detector = $detectorStatus
                    }
                    if ($patternId) { $evD.matched = $patternId }
                    $null = Write-PqEvent -Log $log -Ev 'pass.limit' -Run $runId -Repo $repoKey -Id $ticketId -Pass $passId -Worker $slot -D $evD
                }

                # Rule 48: the only thing that moves a ticket to the next provider of agentOrder is the provider's usage
                # limit, read from its own output (claude: its transcript; the others: the record's limitDetector
                # pattern in the pass's log). The provider is held machine-wide - until the reset time the runner read,
                # else for limitPollMinutes and then one probe pass - and the ticket is neither dropped nor counted
                # against: a limit is nothing the ticket did. A failure with no limit text in it is an ordinary failed
                # pass and is never taken for a limit. A pass that ends without a limit clears a poll hold: it was the probe.
                $agentHeldNow = $false
                if ($isProbe) {
                    $probeResult = Get-PqProbeResult $outcomeRes.limits ([bool]$childRes.killed) ([bool]$childRes.failed) ([string]$outcomeRes.outcome)
                    $null = Write-PqEvent -Log $log -Ev 'agent.probe' -Run $runId -Repo $repoKey -Id $ticketId -Pass $passId -Worker $slot -Agent $agentName -D ([ordered]@{ agent = $agentName; result = $probeResult })
                }
                if (-not $childRes.killed -and -not $childRes.failed) {
                    if ($outcomeRes.limits -gt 0) {
                        $heldUntil = Get-PqRunnerLimitUntil -RepoPath $repoPath -Agent $agentName
                        # The runner times only a limit it reads from a Claude transcript; another provider's message may still
                        # say when it lifts, in the pass's own log.
                        if (-not $heldUntil -and $agentName -cne 'claude') { $heldUntil = Get-PqLogLimitUntil -RepoPath $repoPath -TicketId $ticketId -Record $pick.record }
                        Set-PqAgentHold -Name $agentName -Pass $passId -Source 'log' -Detector $detectorStatus -Until $heldUntil
                        $agentHeldNow = $true
                        $holdData = [ordered]@{ agent = $agentName; until = $heldUntil; source = 'log'; detector = $detectorStatus }
                        $null = Write-PqEvent -Log $log -Ev 'agent.hold' -Run $runId -Repo $repoKey -Id $ticketId -Pass $passId -Worker $slot -Agent $agentName -D $holdData
                        $poll = [int](Get-PqValue $pick.record 'limitPollMinutes' 30)
                        $when = if ($heldUntil) { "until $(([DateTimeOffset]::Parse($heldUntil)).LocalDateTime.ToString('yyyy-MM-dd HH:mm'))" } else { "no reset time given, probed again in $poll min" }
                        Write-Host "provider $agentName has spent its usage limit - held $when; the ticket goes to the next provider of the order"
                    }
                    else {
                        $oldHold = Get-PqAgentHold $agentName
                        $oldUntil = Get-PqValue $oldHold 'until'
                        $stillFuture = $false
                        if ($oldUntil) { try { $stillFuture = [DateTimeOffset]::Parse([string]$oldUntil) -gt [DateTimeOffset]::UtcNow } catch { } }
                        if (-not $stillFuture -and (Remove-PqAgentHold -Name $agentName)) {
                            $resume = Get-PqHoldResume $oldHold
                            $null = Write-PqEvent -Log $log -Ev 'agent.resume' -Run $runId -Worker $slot -Agent $agentName -D ([ordered]@{ agent = $agentName; heldFor = $resume.heldFor; by = $resume.by })
                        }
                        if ($agentName -cne 'claude' -and -not $outcomeRes.moved -and $elapsedSec -lt $script:PqFastFailureSeconds -and $outcomeRes.outcome -cin @('child-failed', 'launch-failed')) {
                            Write-Host "provider $agentName failed fast (${elapsedSec}s, $($outcomeRes.outcome)) and no usage-limit text was found in its output - not taken for a limit, so the order does not move on; if it was one, extend limitDetector.pattern of the '$agentName' record (the pass's output is in the repository's runs folder, $(if ($agentName) { "$ticketId.$agentName.log" } else { "$ticketId.log" }))"
                        }
                    }
                }

                # V5: A ticket that did not move (or failed, except on limit-hit and provider-error)
                if (-not $agentHeldNow -and $outcomeRes.outcome -cnotin @('limit-hit', 'provider-error') -and (-not $outcomeRes.moved -or $outcomeRes.outcome -cnotin @('ok', 'context-handoff'))) {
                    $exclude.Add("$repoKey`:$ticketId")
                    $mark = Get-PqDropMark -RepoPath $repoPath -TicketId $ticketId
                    if ($null -ne $mark) { $drops["$repoKey`:$ticketId"] = @{ repo = $repoKey; id = $ticketId; mark = $mark } }
                    $null = Write-PqEvent -Log $log -Ev 'ticket.dropped' -Run $runId -Repo $repoKey -Id $ticketId -Pass $passId -Worker $slot -D ([ordered]@{
                        statusAt = Get-PqValue $mark 'status'
                        updatedAt = Get-PqValue $mark 'updated'
                        specMtime = Get-PqValue $mark 'specMtime'
                        after = $passCount + 1
                    })
                }

                if ($outcomeRes.outcome -eq 'provider-error') {
                    $pStreak = 1 + [int]$script:PqProviderStreaks[$agentName]
                    $script:PqProviderStreaks[$agentName] = $pStreak
                    $pSleep = [Math]::Min(600, 120 * $pStreak)
                    $null = Write-PqEvent -Log $log -Ev 'pass.providerError' -Run $runId -Repo $repoKey -Id $ticketId -Pass $passId -Worker $slot -Agent $agentName -D ([ordered]@{
                        agent = $agentName
                        streak = $pStreak
                        sleepSeconds = $pSleep
                        outcome = 'provider-error'
                    })
                    Write-Host "provider error on $agentName (streak $pStreak) - sleeping ${pSleep}s before retrying ticket" -ForegroundColor DarkYellow
                    Start-Sleep -Seconds $pSleep
                } else {
                    if ($script:PqProviderStreaks.ContainsKey($agentName)) { $script:PqProviderStreaks[$agentName] = 0 }
                }

                if ($currentRepoLock) {
                    Unlock-PqRepo -LockFile $currentRepoLock
                    $currentRepoLock = $null
                }
                # A drain (rule 47) goes on with the ticket of the pass that was in flight when it was read, while the pass
                # moves it - under a drain of any target (S0082); the worker state names the carry so another worker
                # leaves the stop over it alone.
                $drainCarry = $null
                $drainCarryAgent = ''
                $sNow = Get-PqApplicableStop -Stops @(Get-PqStopFiles) -Slot $slot -Repo $repoKey -Agent $agentName -Ticket "$repoKey`:$ticketId"
                if (Test-PqDrainCarry $sNow ([bool]$outcomeRes.moved) ([bool]$childRes.killed)) { $drainCarry = "$repoKey`:$ticketId"; $drainCarryAgent = [string]$agentName }
                Set-PqWorkerState -Slot $slot -Repo $null -Ticket $null -Carry $drainCarry -CarryAgent $drainCarryAgent

                if ($outcomeRes.moved) { $movedCount++ }
                Write-Host "pass $passNum $repoKey`:$ticketId $statusBefore -> $($outcomeRes.statusAfter)$titlePart ($($outcomeRes.outcome), ${elapsedSec}s)"
                $errStreak = 0
                $lastRunErrText = ''
                $sameRunErrStreak = 0
            }
            catch {
                # A turn that fails is recorded and skipped, never the end of the run (TASK-FLOW EVENTS 3.1, run.error): an
                # unattended night must not stop on one bad payload. The ticket the turn held is dropped like a pass that
                # did not move, and the loop pauses first, longer each time in a row, so a failure that repeats cannot spin.
                $err = $_
                $turnPickerCache.Clear()
                $rerankAfterSkip = $false
                if ($currentRepoLock) {
                    try { Unlock-PqRepo -LockFile $currentRepoLock } catch { }
                    $currentRepoLock = $null
                }
                if ($null -ne $heldResources) {
                    try { $null = Remove-PqResources -RepoKey $heldResourcesRepo -TicketId $heldResourcesId } catch { }
                    $heldResources = $null
                }
                try { Set-PqWorkerState -Slot $slot -Repo $null -Ticket $null } catch { }
                $errStreak++
                $retryIn = [Math]::Min(600, 60 * $errStreak)
                $turnKey = if ($turnRepo -and $turnId) { "$turnRepo`:$turnId" } else { $null }
                if ($turnKey -and -not $exclude.Contains($turnKey)) {
                    $exclude.Add($turnKey)
                    try {
                        $mark = Get-PqDropMark -RepoPath $turnPath -TicketId $turnId
                        if ($null -ne $mark) { $drops[$turnKey] = @{ repo = $turnRepo; id = $turnId; mark = $mark } }
                    }
                    catch { }
                }
                $where = if ($err.InvocationInfo -and $err.InvocationInfo.ScriptName) { " at $([IO.Path]::GetFileName($err.InvocationInfo.ScriptName)):$($err.InvocationInfo.ScriptLineNumber)" } else { '' }
                $errText = "$($err.Exception.Message)$where"
                if ($errText -and $errText -ceq $lastRunErrText) {
                    $sameRunErrStreak++
                } else {
                    $lastRunErrText = $errText
                    $sameRunErrStreak = 1
                }
                $d = [ordered]@{ err = (ConvertTo-PqCut $errText 300); stage = 'turn' }
                if ($turnKey) { $d.repo = $turnRepo; $d.id = $turnId }
                $d.retryIn = $retryIn
                $null = Write-PqEvent -Log $log -Ev 'run.error' -Run $runId -Worker $slot -D $d
                $dropPart = if ($turnKey) { " ($turnKey dropped)" } else { '' }
                if ($sameRunErrStreak -ge 3) {
                    Write-Host "run ended: 3 consecutive errors with the same text: $errText"
                    $exitCode = 1
                    break
                }
                if ($null -ne $named) {
                    $namedFail = "the turn failed ($errText)"
                    Write-Host "turn failed: $errText$dropPart"
                    break
                }
                Write-Host "turn failed: $errText$dropPart - the loop goes on in $retryIn s"
                $waiting = $false
                for ($w = 0; $w -lt $retryIn -and -not [IO.File]::Exists($stopPath); $w++) { Start-Sleep -Seconds 1 }
            }
        }
        # A named start exits 0 only when its pass ran; any other ending (a reason above, STOP, the end time) is 3.
        # A pass whose child ran but whose bookkeeping failed afterwards still ran: exit 0, the failure was printed above.
        if ($null -ne $named -and $passCount -eq 0 -and $exitCode -eq 0 -and -not $namedPassRan) {
            if (-not $namedFail) { $namedFail = 'the run was stopped before the pass (STOP, a stop request or the end time)' }
            Write-Host "pq: ticket $($named.repo):$($named.id) not run - $namedFail"
            $exitCode = 3
        }
    }
    catch {
        $exitCode = 2
        throw
    }
    finally {
        $runSw.Stop()
        $totalElapsed = [Math]::Round($runSw.ElapsedMilliseconds / 1000, 1)
        try {
            $null = Write-PqEvent -Log $log -Ev 'run.end' -Run $runId -Worker $slot -D ([ordered]@{
                exit = $exitCode
                passes = $passCount
                moved = $movedCount
                elapsed = $totalElapsed
                # S0082 (EVENTS 3.1): this line counts itself; logErrors are the write failures the handle met.
                eventsWritten = [long]$log.Written + 1
                logErrors = [int]$log.Errors
            })
        }
        catch { }
        if ($currentRepoLock) {
            Unlock-PqRepo -LockFile $currentRepoLock
            $currentRepoLock = $null
        }
        if ($null -ne $heldResources) {
            try { $null = Remove-PqResources -RepoKey $heldResourcesRepo -TicketId $heldResourcesId } catch { }
            $heldResources = $null
        }
        try { $null = Write-PqPollSummary -Stats $pollStats -Log $log } catch { }
        Remove-PqWorkerState -Slot $slot
        try { $null = Close-PqLog -Log $log } catch { }
        try { $host.UI.RawUI.WindowTitle = "pq - stopped" } catch { }
        Write-Host "pq stopped: passes=$passCount exit=$exitCode"
    }
    return $exitCode
}
