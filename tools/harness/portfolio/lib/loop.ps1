# The run loop of the portfolio dispatcher (TASK-FLOW rules 41-47; S0015 V1-V9).
#
# Dot-source this file; it defines functions only, sets no preference and prints nothing.
#
#   Get-PqNextRank              ranks repositories and tickets across the portfolio, returning the same rank
#                               result as pq dry-run.
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
#   Start-PqLoop                the main execution loop of pq start (V1-V9).

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
        [string]$OnlyRepo = ''
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
    $pickerCache = @{}
    $provider = {
        param($Repo, $Ex, $ForceId)
        $a = @{ RepoPath = [string]$Repo.path; HarnessRoot = $HarnessRoot; Cache = $pickerCache }
        if (@($Ex).Count -gt 0) { $a.Exclude = [string[]]@($Ex) }
        if ($ForceId) { $a.ForceId = $ForceId }
        Get-PqPickerHead @a
    }

    $n = if ($Slots -ge 0) { $Slots } else { [int](Get-PqValue $Registry 'maxWorkers' 1) }
    $rankArgs = @{ Registry = $Registry; Queue = $queue; HeadProvider = $provider; Slots = $n; Exclude = $Exclude; Occupied = $Occupied; Stopped = (Get-PqStoppedRepos $Registry); StopAfter = $StopAfter }
    if ($NamedTicket) { $rankArgs.NamedTicket = $NamedTicket }
    if ($OnlyRepo) { $rankArgs.OnlyRepo = $OnlyRepo }
    return (Get-PqRank @rankArgs)
}

# Keys of enabled repositories whose shared queue stop file (rule 26, paths.queueStopFile) exists: the owner's `rs`, or
# a release freeze that stopped the queue. It is read before a ticket is offered, because the runner a pass starts
# treats a shared stop with no live child as left over from a finished run and deletes it - a portfolio pass would
# cancel the owner's stop within one poll. Only the shared file counts: an instance's own stop file is that instance's.
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

function Get-PqWorkerSlot($Registry) {
    Invoke-PqStateLock {
        $root = Get-PqRoot
        $runDir = Join-Path $root 'run'
        if (-not [IO.Directory]::Exists($runDir)) { $null = [IO.Directory]::CreateDirectory($runDir) }
        $max = [Math]::Max(1, [int](Get-PqValue $Registry 'maxWorkers' 1))
        for ($k = 1; $k -le $max; $k++) {
            $wf = Join-Path $runDir "worker-$k.json"
            if (-not (Test-PqStateOwner (Read-PqState $wf))) {
                Set-PqWorkerState -Slot $k
                return $k
            }
        }
        return $null
    }
}

function Set-PqWorkerState([int]$Slot, [string]$Repo = $null, [string]$Ticket = $null, [string]$Title = $null, [string]$Agent = $null) {
    Invoke-PqStateLock {
        $root = Get-PqRoot
        $runDir = Join-Path $root 'run'
        if (-not [IO.Directory]::Exists($runDir)) { $null = [IO.Directory]::CreateDirectory($runDir) }
        $wf = Join-Path $runDir "worker-$Slot.json"
        $obj = [ordered]@{
            pid = $PID
            startedAt = (Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
            repository = $Repo
            ticket = $Ticket
            title = $Title
            agent = $Agent
            since = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        }
        $tmp = "$wf.$PID.tmp"
        [IO.File]::WriteAllText($tmp, (($obj | ConvertTo-Json -Compress)), [Text.Encoding]::UTF8)
        [IO.File]::Move($tmp, $wf, $true)
    }
}

# Reserve the repository and ticket together with the worker state. Ranking is only a snapshot: another
# worker can choose the same candidate before either has published its assignment.
function Request-PqWorkerAssignment {
    param([int]$Slot, $Repo, [string]$Ticket, [string]$Title, [string]$Agent, [int]$AgentMax = 1)
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
            if ((Get-PqValue $state 'ticket') -ceq $Ticket) { return $false }
            $count++
        }
        if ($count -ge $limit -or $agentCount -ge $AgentMax) { return $false }
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
        [scriptblock]$OnStarted,
        # The agent of the pass, when it is not claude (Get-PqAgentPassArgs): it carries its own -ModelPolicy.
        [string[]]$AgentArgs = @(),
        # Called about every three seconds while the pass runs (the loop reads the session the pass runs under from it).
        [scriptblock]$OnTick,
        # Called about every second; returns the stop that applies to this pass (Get-PqApplicableStop) or $null. Without
        # it only the whole-portfolio STOP is read, as before levels existed.
        [scriptblock]$StopWatcher
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
    [void]$psi.Environment.Remove('SZA_PROFILE_PATH')
    Remove-PqAgentSessionEnv $psi.Environment
    $proc = $null
    $killed = $false
    $halted = $false
    try {
        $proc = [Diagnostics.Process]::Start($psi)
        if ($OnStarted) { $null = & $OnStarted $proc.Id }
        # Short waits let PowerShell process Ctrl+C. A cancelled dispatcher must not orphan its runner.
        # The agent CLI prints its answer only when it finishes, so a minute-by-minute line is the only sign of life.
        $passSw = [Diagnostics.Stopwatch]::StartNew()
        $beatAt = 60
        $stopAt = 0.0
        $tickAt = 0.0
        $titlePart = if ($TicketTitle) { " - $TicketTitle" } else { '' }
        try { $host.UI.RawUI.WindowTitle = "pass $Instance $TicketId$titlePart" } catch { }
        while (-not $proc.WaitForExit(250)) {
            $elapsedNow = $passSw.Elapsed.TotalSeconds
            if ($elapsedNow -ge $beatAt) {
                Write-Host ('pass {0} {1}{2} - still running, {3:hh\:mm\:ss} elapsed' -f $Instance, $TicketId, $titlePart, $passSw.Elapsed) -ForegroundColor DarkGray
                $beatAt += 60
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
    $limits = @($rows | Where-Object { $_.outcome -ceq 'limit-hit' }).Count
    # Exit 5: the runner found the provider's usage limit already in force and launched nothing (-ExitOnLimit).
    if ($ChildExitCode -eq 5) { $outcome = 'limit-hit'; $limits = [Math]::Max(1, $limits) }
    # A runner whose claim was lost to a sibling launched nothing and exits 3 (rule 27); its row says so (rule 46).
    elseif ($ChildExitCode -ne 0 -and $outcome -cnotin @('limit-hit', 'killed', 'halted', 'timeout', 'launch-failed', 'claim-lost', 'claim-lost-before-launch')) {
        $outcome = 'child-failed'
    }
    elseif (-not $outcome -or $outcome -ceq 'ok') { $outcome = if ($moved) { 'ok' } else { 'no-progress' } }
    return [ordered]@{
        model = [string](Get-PqValue $journalRow 'model' '')
        complexity = [string](Get-PqValue $journalRow 'complexity' '')
        statusAfter = $statusAfter
        moved = $moved
        outcome = $outcome
        launches = $rows.Count
        limits = $limits
    }
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

# Every ticket id of a repository's ledger and archive, read from the files; $null when they cannot be read in full. A
# pass is bracketed by two such reads, and an id that is in the second and not in the first is a ticket the pass filed:
# the robot-filed Draft of D5 (S0016 R24).
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
        'context-handoff' { 'ok' }
        default { if ($Outcome) { $Outcome } else { 'unknown' } }
    }
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
        Write-PqError 'NoWorkerSlot' "all $([int]$Registry.maxWorkers) worker slots are busy"
        return 2
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
        pid = $PID
    }
    if ($null -ne $named) { $startD.target = "ticket:$($named.repo):$($named.id)" }
    elseif ($OnlyRepo) { $startD.target = "repo:$OnlyRepo" }
    $null = Write-PqEvent -Log $log -Ev 'run.start' -Run $runId -Worker $slot -D $startD
    $repoOnly = @{}
    if ($OnlyRepo) { $repoOnly.OnlyRepo = $OnlyRepo }
    Write-PqOwnerAction 'start'

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
    $settling = $false
    $quietPolls = 0
    $pollStats = New-PqPollStats
    $waitSaid = ''
    $lifts = @{}
    $thrashUntil = @{}
    # Held back for a moment by the loop itself: a repository the owner works in, a ticket that could not get its resource.
    $occupiedMarks = @{}
    $occupancyState = @{}
    $transient = @{}
    $transientSaid = @{}
    $heldResources = $null
    $heldResourcesRepo = ''
    $heldResourcesId = ''
    # Stops and the pause (rule 47, R56) and the robot-filed Drafts (D5).
    $paused = $false
    $drainCarry = $null
    $robotDrafts = @{}

    try {
        while ($true) {
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
                if ($stops.Count -gt 0) {
                    $liveWorkers = @(Get-PqWorkerFiles)
                    foreach ($ts in $stops) {
                        if ($ts.kind -cin @('all', 'worker')) { continue }
                        if (Test-PqStopTargetBusy $ts $liveWorkers) {
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
                if ([DateTime]::UtcNow -ge $nextDiscoveryAt) {
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

                # New tickets of every repository join their project's rows of PORTFOLIO_QUEUE.md before the rank reads it. A failed
                # sync (the owner saving the file at that moment) is retried on the next turn and never stops the loop.
                try {
                    $qpSync = Get-PqQueuePath $Registry
                    if ([IO.File]::Exists($qpSync)) { $null = Sync-PqRegisteredQueues -Path $qpSync -Registry $Registry -Log }
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

                # What the loop itself holds back for a moment lapses on its own: a repository the owner works in, and a
                # ticket that could not get its resource.
                $nowUtc = [DateTime]::UtcNow
                foreach ($mk in @($occupiedMarks.Keys)) { if ($occupiedMarks[$mk].until -le $nowUtc) { $occupiedMarks.Remove($mk) } }
                foreach ($mk in @($transient.Keys)) { if ($transient[$mk].until -le $nowUtc) { $transient.Remove($mk); $transientSaid.Remove($mk) } }

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

                # 4. Rank. The loop reads only the first candidate, so the walk ends at the first head found: one picker run
                # per queue row costs minutes on a queue of a hundred rows.
                if (-not $waiting) { Write-Host 'ranking the queue' }
                $rankExclude = @($exclude) + @($transient.Keys) + @($stopTickets)
                $rankOccupied = @($occupied) + @($occupiedMarks.Keys) + @($stopRepos) + @($capRepos)
                $rank = $null
                if ($null -ne $named) {
                    # A named start asks the rank for that one ticket only: no drain carry, no breadth fill.
                    $rank = Get-PqNextRank -Registry $Registry -HarnessRoot $harness -Exclude $rankExclude -Occupied $rankOccupied -Slots 1 -StopAfter 1 -NamedTicket $OnlyTicket
                }
                elseif ($drainNow -and $drainCarry) {
                    # A drain (rule 47) goes on with the ticket whose pass was in flight when it was read, as long as the
                    # repository still offers it; the rank is not asked.
                    $dc = $drainCarry -split ':', 2
                    $drec = $byKey[$dc[0]]
                    $dh = if ($null -ne $drec) { Get-PqPickerHead -RepoPath ([string]$drec.path) -HarnessRoot $harness -ForceId $dc[1] } else { $null }
                    $drainCarry = $null
                    if ($null -ne $dh -and $dh.ok -and $null -ne $dh.head) {
                        $rank = @{ events = @(); skipped = @(); autoSkipReasons = $null; candidates = @([ordered]@{ repo = $dc[0]; id = $dc[1]; status = [string]$dh.head.status; title = [string](Get-PqValue $dh.head 'name' ''); priority = (Get-PqValue $dh.head 'priority') }) }
                    }
                    else {
                        $null = Write-PqEvent -Log $log -Ev 'run.stop' -Run $runId -Worker $slot -D ([ordered]@{ level = 'drain'; target = 'all'; reason = 'owner'; passesInFlight = 0 })
                        Write-Host "drain: $($dc[0]):$($dc[1]) is not offered any more - stopping"
                        break
                    }
                }
                else {
                    if ((Get-PqValue $Registry 'fill' 'depth') -ceq 'breadth' -and $busyRepos.Count -gt 0) {
                        $rank = Get-PqNextRank -Registry $Registry -HarnessRoot $harness -Exclude $rankExclude -Occupied (@($rankOccupied) + @($busyRepos)) -Slots 1 -StopAfter 1 @repoOnly
                        if (@($rank.candidates).Count -eq 0) { $rank = $null }
                    }
                    if ($null -eq $rank) { $rank = Get-PqNextRank -Registry $Registry -HarnessRoot $harness -Exclude $rankExclude -Occupied $rankOccupied -Slots 1 -StopAfter 1 @repoOnly }
                }
                foreach ($e in @($rank.events)) {
                    $null = Write-PqEvent -Log $log -Ev $e.ev -Run $runId -Worker $slot -D $e.d
                }

                # 5. Handle empty candidates
                if (@($rank.candidates).Count -eq 0) {
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
                    $waitSummary = (@($whyCounts.Keys | ForEach-Object { "$_ $($whyCounts[$_])" }) -join ', ')
                    $null = Write-PqEvent -Log $log -Ev 'wait.enter' -Run $runId -Worker $slot -D ([ordered]@{ open = 0; why = $whyCounts })
                    if (-not $waiting -or $waitSummary -cne $waitSaid) {
                        Write-Host "waiting for tickets (poll ${poll}s) - nothing offerable: $waitSummary"
                        $waiting = $true
                        $waitSaid = $waitSummary
                    }
                    $waitSw = [Diagnostics.Stopwatch]::StartNew()
                    $trigger = 'heartbeat'
                    $heartbeatEvery = if (($transient.Count + $occupiedMarks.Count) -gt 0) { 1 } else { 10 }
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
                            continue
                        }
                        if ($settling) {
                            $settling = $false
                            $trigger = 'change'
                            Add-PqPollStat -Stats $pollStats -Log $log -Rerank
                            break
                        }
                        $quietPolls++
                        if ($quietPolls -ge $heartbeatEvery) {
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
                    continue
                }

                # Rule 61: the robot yields to the owner. In a repository that is not `concurrent` a live manual session (a
                # transcript written within occupiedMinutes, a live lease no pass holds) means no pass is launched; the
                # repository is looked at again in half a minute, and the next repository of the rank is tried meanwhile.
                if (-not $isConcurrent) {
                    $occ = Get-PqRepoOccupancy -Repo $repoRec -Registry $Registry -HarnessRoot $harness
                    if ($occ.occupied) {
                        $occupiedMarks[$repoKey] = @{ until = [DateTime]::UtcNow.AddSeconds(30); why = 'occupied' }
                        if (-not $occupancyState.ContainsKey($repoKey)) {
                            $occupancyState[$repoKey] = $true
                            $null = Write-PqEvent -Log $log -Ev 'repo.occupied' -Run $runId -Repo $repoKey -Worker $slot -D ([ordered]@{ by = $occ.by; holderKind = $occ.holderKind; age = $occ.ageSeconds })
                            Write-Host "repository $repoKey is occupied ($($occ.by), $($occ.ageSeconds) s ago) - the robot waits for the owner"
                        }
                        $null = Write-PqEvent -Log $log -Ev 'dispatch.skip' -Run $runId -Repo $repoKey -Id $ticketId -Worker $slot -D ([ordered]@{ why = 'occupied' })
                        continue
                    }
                    if ($occupancyState.ContainsKey($repoKey)) {
                        $occupancyState.Remove($repoKey)
                        $null = Write-PqEvent -Log $log -Ev 'repo.free' -Run $runId -Repo $repoKey -Worker $slot -D ([ordered]@{ by = 'transcript'; holderKind = 'manual' })
                        Write-Host "repository $repoKey is free again"
                    }
                }

                if (-not $ticketTitle) {
                    $rec = Get-PqTicketRecord -RepoPath $repoPath -Id $ticketId -HarnessRoot $harness
                    if ($rec -and $rec.name) { $ticketTitle = [string]$rec.name }
                    elseif ($rec -and $rec.title) { $ticketTitle = [string]$rec.title }
                }
                if (-not $ticketTitle) {
                    try {
                        $repoPaths = Get-PqRepoPaths -RepoPath $repoPath
                        $planDir = $repoPaths.SpecsDir
                        if ([IO.Directory]::Exists($planDir)) {
                            $files = [IO.Directory]::GetFiles($planDir, "$ticketId*.md")
                            if ($files.Length -gt 0) {
                                foreach ($line in [IO.File]::ReadLines($files[0])) {
                                    if ($line -match '^#\s+(?:' + [regex]::Escape($ticketId) + '\s*[-:]\s*)?(?<title>.+)$') {
                                        $ticketTitle = $Matches['title'].Trim()
                                        break
                                    }
                                }
                            }
                        }
                    } catch { }
                }

                # The agent of this pass (rule 42): the first of agentOrder that is not held, under its maxParallel, admits
                # the ticket's level and can reach the repository's pipeline. No declared level runs at medium (rule 51).
                $ticketLevel = Get-PqTicketLevel -RepoPath $repoPath -TicketId $ticketId
                $pick = Select-PqAgent -Registry $Registry -RepoPath $repoPath -Level $(if ($ticketLevel) { $ticketLevel } else { 'medium' }) -Skip $stopAgents
                foreach ($fb in @($pick.fallbacks)) {
                    $null = Write-PqEvent -Log $log -Ev 'agent.fallback' -Run $runId -Repo $repoKey -Id $ticketId -Worker $slot -D ([ordered]@{ from = $fb.from; to = $pick.agent; repo = $repoKey; id = $ticketId; why = $fb.why })
                }
                if (-not $pick.agent) {
                    $null = Write-PqEvent -Log $log -Ev 'dispatch.skip' -Run $runId -Repo $repoKey -Id $ticketId -Worker $slot -D ([ordered]@{ why = 'noAgent' })
                    # Said once per change, not every half minute: a weekly limit is a wait of days.
                    $noAgentWhy = Get-PqNoAgentSummary -Pick $pick -Registry $Registry
                    if ($null -ne $named) { $namedFail = "no provider of the order may take it now ($noAgentWhy)"; break }
                    if ($noAgentWhy -cne $noAgentSaid) {
                        Write-Host "ticket $repoKey`:$ticketId - no provider of the order may take it now ($noAgentWhy); checking again every 30 s"
                        $noAgentSaid = $noAgentWhy
                    }
                    for ($w = 0; $w -lt 30 -and -not [IO.File]::Exists($stopPath); $w++) { Start-Sleep -Seconds 1 }
                    continue
                }
                $noAgentSaid = ''
                $agentName = [string]$pick.agent
                $agentArgs = if ($agentName -ceq 'claude') { @() } else { Get-PqAgentPassArgs $pick }

                if (-not (Request-PqWorkerAssignment -Slot $slot -Repo $repoRec -Ticket $ticketId -Title $ticketTitle -Agent $agentName -AgentMax ([int](Get-PqValue $pick.record 'maxParallel' 1)))) {
                    $occupiedMarks[$repoKey] = @{ until = [DateTime]::UtcNow.AddSeconds(5); why = 'workerCap' }
                    continue
                }

                # Rule 62: the machine-wide tokens the ticket's own **Verify:** level takes (build, emulator); a ticket that
                # cannot get them is passed over for a minute and the next candidate is taken; hardware is never offered.
                $verify = Get-PqTicketVerify -RepoPath $repoPath -TicketId $ticketId
                $passIdNext = "$runId.$($passCount + 1)"
                $resReq = Request-PqResources -Registry $Registry -RepoKey $repoKey -TicketId $ticketId -Verify $verify -PassId $passIdNext
                foreach ($sk in @($resReq.stale)) { $null = Write-PqEvent -Log $log -Ev 'resource.release' -Run $runId -Worker $slot -D ([ordered]@{ resource = ($sk -split '/')[0]; stale = $sk }) }
                if (-not $resReq.ok) {
                    Set-PqWorkerState -Slot $slot
                    $tk = "$repoKey`:$ticketId"
                    $recheck = if ($resReq.why -ceq 'deviceLevel') { 600 } else { 60 }
                    $transient[$tk] = @{ until = [DateTime]::UtcNow.AddSeconds($recheck); why = $(if ($resReq.why -ceq 'deviceLevel') { 'deviceLevel' } else { 'resource' }) }
                    $null = Write-PqEvent -Log $log -Ev 'dispatch.skip' -Run $runId -Repo $repoKey -Id $ticketId -Worker $slot -D ([ordered]@{ why = $resReq.why })
                    if ($resReq.why -ceq 'resource') {
                        $null = Write-PqEvent -Log $log -Ev 'resource.wait' -Run $runId -Repo $repoKey -Id $ticketId -Worker $slot -D ([ordered]@{ resource = $resReq.resource; verify = $verify; held = $resReq.heldCount; cap = $resReq.cap })
                    }
                    if (-not $transientSaid.ContainsKey($tk)) {
                        $transientSaid[$tk] = $true
                        if ($resReq.why -ceq 'deviceLevel') { Write-Host "ticket $tk needs real hardware (Verify: device) - robots never take it" }
                        else { Write-Host "ticket $tk waits for the $($resReq.resource) resource ($($resReq.heldCount) of $($resReq.cap) held) - the next ticket is taken" }
                    }
                    continue
                }
                if (@($resReq.held).Count -gt 0) {
                    $heldResources = @($resReq.held)
                    $heldResourcesRepo = $repoKey
                    $heldResourcesId = $ticketId
                    foreach ($ht in $heldResources) {
                        $null = Write-PqEvent -Log $log -Ev 'resource.acquire' -Run $runId -Repo $repoKey -Id $ticketId -Pass $passIdNext -Worker $slot -D ([ordered]@{ resource = $ht; verify = $verify; held = $resReq.heldCount; cap = $resReq.cap })
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
                    param($childPid)
                    $null = Write-PqEvent -Log $log -Ev 'pass.launch' -Run $runId -Repo $repoKey -Id $ticketId -Pass $passId -Worker $slot -Agent $agentName -D ([ordered]@{
                        instance = "pq$slot"
                        permission = $permMode
                        statusBefore = $statusBefore
                        pid = $childPid
                    })
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
                $titlePart = if ($ticketTitle) { " - $ticketTitle" } else { '' }
                $agentPart = if ($agentName -cne 'claude') { " [$agentName]" } else { '' }

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

                Write-Host "pass $passNum $repoKey`:$ticketId $statusBefore$titlePart$agentPart - started"
                $childRes = Invoke-PqPassChild -Script $actualRunner -RepoPath $repoPath -TicketId $ticketId -TicketTitle $ticketTitle -Instance "pq$slot" -PermissionMode $permMode -OnStarted $onStarted -AgentArgs $agentArgs -OnTick $onTick -StopWatcher $stopWatcher
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
                    finishedAt = [DateTimeOffset]::Now.ToString("yyyy-MM-dd'T'HH:mm:sszzz")
                    canon = $canonVersion
                    plugin = $pluginVersion
                    registryHash = $current.hash
                    profileHash = $profileHash
                }
                $runsJsonl = Join-Path $root 'runs.jsonl'
                Invoke-PqStateLock {
                    [IO.File]::AppendAllText($runsJsonl, (($runRow | ConvertTo-Json -Compress) + "`n"), [Text.Encoding]::UTF8)
                }

                $mappedOutcome = ConvertTo-PqPassEndOutcome $outcomeRes.outcome
                $null = Write-PqEvent -Log $log -Ev 'pass.end' -Run $runId -Repo $repoKey -Id $ticketId -Pass $passId -Worker $slot -Agent $agentName -D ([ordered]@{
                    exit = $childRes.code
                    outcome = $mappedOutcome
                    launches = $outcomeRes.launches
                    statusBefore = $statusBefore
                    statusAfter = $outcomeRes.statusAfter
                    moved = [bool]$outcomeRes.moved
                    elapsed = $elapsedSec
                })

                # Rule 47: halt and kill clean up and never decide a status. The lease the pass held is released (done in
                # Invoke-PqPassChild), the resources above, and the ledger is checked, so a half-written row shows at once
                # instead of at the next ticket; pass.halt / pass.kill and a console line tell you.
                if ($childRes.killed) {
                    $validate = $null
                    try {
                        $vr = Invoke-PqRepoChild -RepoPath $repoPath -Script (Join-Path $harness 'spec_catalog\validate.ps1') -Arguments @() -TimeoutSeconds 120
                        $validate = if ($vr.timedOut) { 'timeout' } else { [int]$vr.code }
                    }
                    catch { $validate = 'error' }
                    if ($childRes.halted) {
                        $null = Write-PqEvent -Log $log -Ev 'pass.halt' -Run $runId -Repo $repoKey -Id $ticketId -Pass $passId -Worker $slot -Agent $agentName -D ([ordered]@{ signal = 'none'; grace = 0; degradedToKill = $true; validate = $validate })
                    }
                    else {
                        $null = Write-PqEvent -Log $log -Ev 'pass.kill' -Run $runId -Repo $repoKey -Id $ticketId -Pass $passId -Worker $slot -Agent $agentName -D ([ordered]@{ level = 'kill'; validate = $validate })
                    }
                    Write-Host "pass $passNum ended by the owner's $(if ($childRes.halted) { 'halt' } else { 'kill' }); lease and resources released, ledger validate: $validate"
                }

                # D5: a ticket that is new in the repository after the pass is a ticket the pass filed (park, do not fix,
                # rule 13). The first `robotDraftCap` of them in a repository per run are worked like any other; beyond the
                # cap each one is kept out of the rank and the owner is told, so robots cannot feed themselves for ever.
                $newIds = @(Get-PqNewTicketIds $idsBefore (Get-PqTicketIds $repoPath))
                if ($newIds.Count -gt 0) {
                    $draftCap = [int](Get-PqValue $Registry 'robotDraftCap' 20)
                    if (-not $robotDrafts.ContainsKey($repoKey)) { $robotDrafts[$repoKey] = [Collections.Generic.List[string]]::new() }
                    $beyond = 0
                    foreach ($nid in $newIds) {
                        $robotDrafts[$repoKey].Add($nid)
                        $count = $robotDrafts[$repoKey].Count
                        $capped = ($count -gt $draftCap)
                        $null = Write-PqEvent -Log $log -Ev 'intake.robotDraft' -Run $runId -Repo $repoKey -Id $nid -Pass $passId -Worker $slot -D ([ordered]@{ count = $count; cap = $draftCap; capped = $capped })
                        if ($capped) {
                            $beyond++
                            $exclude.Add("$repoKey`:$nid")
                            $null = Write-PqEvent -Log $log -Ev 'dispatch.skip' -Run $runId -Repo $repoKey -Id $nid -Worker $slot -D ([ordered]@{ why = 'intakeCap' })
                        }
                    }
                    Write-Host "pass $passNum filed $($newIds.Count) new ticket(s) in ${repoKey}: $($newIds -join ', ') (robot-filed this run: $($robotDrafts[$repoKey].Count) of $draftCap)"
                    if ($beyond -gt 0) { Write-Host "the cap of $draftCap robot-filed tickets in $repoKey is reached - the $beyond beyond it stay with the owner" }
                }

                for ($limit = 0; $limit -lt $outcomeRes.limits; $limit++) {
                    $null = Write-PqEvent -Log $log -Ev 'pass.limit' -Run $runId -Repo $repoKey -Id $ticketId -Pass $passId -Worker $slot -D ([ordered]@{
                        agent = $agentName
                        source = 'log'
                        detector = 'proven'
                    })
                }

                # Rule 48: the only thing that moves a ticket to the next provider of agentOrder is the provider's usage
                # limit, read from its own output (claude: its transcript; the others: the record's limitDetector
                # pattern in the pass's log). The provider is held machine-wide - until the reset time the runner read,
                # else for limitPollMinutes and then one probe pass - and the ticket is neither dropped nor counted
                # against: a limit is nothing the ticket did. A failure with no limit text in it is an ordinary failed
                # pass and is never taken for a limit. A pass that ends without a limit clears a poll hold: it was the probe.
                $agentHeldNow = $false
                if (-not $childRes.killed -and -not $childRes.failed) {
                    if ($outcomeRes.limits -gt 0) {
                        $heldUntil = Get-PqRunnerLimitUntil -RepoPath $repoPath -Agent $agentName
                        # The runner times only a limit it reads from a Claude transcript; another provider's message may still
                        # say when it lifts, in the pass's own log.
                        if (-not $heldUntil -and $agentName -cne 'claude') { $heldUntil = Get-PqLogLimitUntil -RepoPath $repoPath -TicketId $ticketId -Record $pick.record }
                        Set-PqAgentHold -Name $agentName -Pass $passId -Source 'log' -Detector 'proven' -Until $heldUntil
                        $agentHeldNow = $true
                        $null = Write-PqEvent -Log $log -Ev 'agent.hold' -Run $runId -Repo $repoKey -Id $ticketId -Pass $passId -Worker $slot -Agent $agentName -D ([ordered]@{ agent = $agentName; until = $heldUntil; source = 'log'; detector = 'proven' })
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
                            $null = Write-PqEvent -Log $log -Ev 'agent.resume' -Run $runId -Worker $slot -Agent $agentName -D ([ordered]@{ agent = $agentName; by = 'probe' })
                        }
                        if ($agentName -cne 'claude' -and -not $outcomeRes.moved -and $elapsedSec -lt $script:PqFastFailureSeconds -and $outcomeRes.outcome -cin @('child-failed', 'launch-failed')) {
                            Write-Host "provider $agentName failed fast (${elapsedSec}s, $($outcomeRes.outcome)) and no usage-limit text was found in its output - not taken for a limit, so the order does not move on; if it was one, extend limitDetector.pattern of the '$agentName' record (the pass's output is in the repository's runs folder, $ticketId.log)"
                        }
                    }
                }

                # V5: A ticket that did not move (or failed, except on limit-hit)
                if (-not $agentHeldNow -and $outcomeRes.outcome -cne 'limit-hit' -and (-not $outcomeRes.moved -or $outcomeRes.outcome -cnotin @('ok', 'context-handoff'))) {
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

                if ($currentRepoLock) {
                    Unlock-PqRepo -LockFile $currentRepoLock
                    $currentRepoLock = $null
                }
                Set-PqWorkerState -Slot $slot -Repo $null -Ticket $null

                # A drain (rule 47) goes on with the ticket of the pass that was in flight when it was read, while the pass moves it.
                $drainCarry = $null
                if ($outcomeRes.moved -and -not $childRes.killed) {
                    $sNow = Get-PqApplicableStop -Stops @(Get-PqStopFiles) -Slot $slot -Repo $repoKey -Agent $agentName -Ticket "$repoKey`:$ticketId"
                    if ($null -ne $sNow -and $sNow.level -ceq 'drain' -and $sNow.kind -cin @('all', 'worker')) { $drainCarry = "$repoKey`:$ticketId" }
                }

                $passCount++
                if ($outcomeRes.moved) { $movedCount++ }
                Write-Host "pass $passNum $repoKey`:$ticketId $statusBefore -> $($outcomeRes.statusAfter)$titlePart ($($outcomeRes.outcome), ${elapsedSec}s)"
                $errStreak = 0
            }
            catch {
                # A turn that fails is recorded and skipped, never the end of the run (TASK-FLOW EVENTS 3.1, run.error): an
                # unattended night must not stop on one bad payload. The ticket the turn held is dropped like a pass that
                # did not move, and the loop pauses first, longer each time in a row, so a failure that repeats cannot spin.
                $err = $_
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
                $d = [ordered]@{ err = (ConvertTo-PqCut "$($err.Exception.Message)$where" 300); stage = 'turn' }
                if ($turnKey) { $d.repo = $turnRepo; $d.id = $turnId }
                $d.retryIn = $retryIn
                $null = Write-PqEvent -Log $log -Ev 'run.error' -Run $runId -Worker $slot -D $d
                $dropPart = if ($turnKey) { " ($turnKey dropped)" } else { '' }
                if ($null -ne $named) {
                    $namedFail = "the turn failed ($($err.Exception.Message)$where)"
                    Write-Host "turn failed: $($err.Exception.Message)$where$dropPart"
                    break
                }
                Write-Host "turn failed: $($err.Exception.Message)$where$dropPart - the loop goes on in $retryIn s"
                $waiting = $false
                for ($w = 0; $w -lt $retryIn -and -not [IO.File]::Exists($stopPath); $w++) { Start-Sleep -Seconds 1 }
            }
        }
        # A named start exits 0 only when its pass ran; any other ending (a reason above, STOP, the end time) is 3.
        if ($null -ne $named -and $passCount -eq 0 -and $exitCode -eq 0) {
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
