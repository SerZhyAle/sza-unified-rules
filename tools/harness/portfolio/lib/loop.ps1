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
#   Start-PqLoop                the main execution loop of pq start (V1-V9).

function Get-PqNextRank {
    param(
        [Parameter(Mandatory)]$Registry,
        [string]$HarnessRoot,
        [string[]]$Exclude = @(),
        [string[]]$Occupied = @(),
        [int]$Slots = -1,
        [int]$StopAfter = 0
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
    $queue = Read-PqQueueFile -Path $qp -KnownRepos (Get-PqKnownKeys $Registry) -TicketLookup $lookup
    $provider = {
        param($Repo, $Ex, $ForceId)
        $a = @{ RepoPath = [string]$Repo.path; HarnessRoot = $HarnessRoot }
        if (@($Ex).Count -gt 0) { $a.Exclude = [string[]]@($Ex) }
        if ($ForceId) { $a.ForceId = $ForceId }
        Get-PqPickerHead @a
    }

    $n = if ($Slots -ge 0) { $Slots } else { [int](Get-PqValue $Registry 'maxWorkers' 1) }
    return (Get-PqRank -Registry $Registry -Queue $queue -HeadProvider $provider -Slots $n -Exclude $Exclude -Occupied $Occupied -Stopped (Get-PqStoppedRepos $Registry) -StopAfter $StopAfter)
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

function Set-PqWorkerState([int]$Slot, [string]$Repo = $null, [string]$Ticket = $null) {
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
            since = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        }
        $tmp = "$wf.$PID.tmp"
        [IO.File]::WriteAllText($tmp, (($obj | ConvertTo-Json -Compress)), [Text.Encoding]::UTF8)
        [IO.File]::Move($tmp, $wf, $true)
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
        [string]$Instance = 'pq1',
        [Parameter(Mandatory)][string]$PermissionMode,
        [scriptblock]$OnStarted
    )
    # A registry record may spell the drive letter in lower case; the agent CLI would then see an untrusted workspace.
    $RepoPath = ConvertTo-PqFullPath $RepoPath
    $pwsh = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
    $psi = [Diagnostics.ProcessStartInfo]::new($pwsh)
    $passArgs = @('-NoProfile', '-File', $Script, '-RepoRoot', $RepoPath, '-Ids', $TicketId, '-MaxTickets', '1', '-ModelPolicy', 'shape', '-Instance', $Instance)
    if ($PermissionMode) { $passArgs += @('-PermissionMode', $PermissionMode) }
    foreach ($a in $passArgs) { $psi.ArgumentList.Add([string]$a) }
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = $RepoPath
    $psi.Environment['SZA_PROJECT_ROOT'] = $RepoPath
    [void]$psi.Environment.Remove('SZA_PROFILE_PATH')
    Remove-PqAgentSessionEnv $psi.Environment
    $proc = $null
    $killed = $false
    try {
        $proc = [Diagnostics.Process]::Start($psi)
        if ($OnStarted) { $null = & $OnStarted $proc.Id }
        # Short waits let PowerShell process Ctrl+C. A cancelled dispatcher must not orphan its runner.
        # The agent CLI prints its answer only when it finishes, so a minute-by-minute line is the only sign of life.
        $passSw = [Diagnostics.Stopwatch]::StartNew()
        $beatAt = 60
        while (-not $proc.WaitForExit(250)) {
            if ($passSw.Elapsed.TotalSeconds -ge $beatAt) {
                Write-Host ('pass {0} {1} - still running, {2:hh\:mm\:ss} elapsed' -f $Instance, $TicketId, $passSw.Elapsed) -ForegroundColor DarkGray
                $beatAt += 60
            }
            $stop = Read-PqState (Get-PqPath -Kind stop)
            if ((Get-PqValue $stop 'level') -ceq 'kill') {
                # Also covers a stop during runner startup, before its own stop-file reader is ready.
                $proc.Kill($true)
                $proc.WaitForExit()
                $killed = $true
            }
        }
        return @{ code = $proc.ExitCode; pid = $proc.Id; killed = $killed; failed = $false }
    }
    catch [Management.Automation.PipelineStoppedException] { throw }
    catch {
        return @{ code = 2; pid = $null; killed = $false; failed = $true }
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
    # A runner whose claim was lost to a sibling launched nothing and exits 3 (rule 27); its row says so (rule 46).
    if ($ChildExitCode -ne 0 -and $outcome -cnotin @('limit-hit', 'killed', 'halted', 'timeout', 'launch-failed', 'claim-lost', 'claim-lost-before-launch')) {
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
        limits = @($rows | Where-Object { $_.outcome -ceq 'limit-hit' }).Count
    }
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
        [string]$RunnerScript = ''
    )
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

    $runId = 'R' + [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 4)
    $log = Open-PqLog -Writer "w$slot" -Run $runId

    $enabledRepos = @(@($Registry.repos) | Where-Object { $_.enabled -eq $true })
    $null = Write-PqEvent -Log $log -Ev 'run.start' -Run $runId -Worker $slot -D ([ordered]@{
        mode = 'pool'
        slots = [int]$Registry.maxWorkers
        drain = [bool]$Drain
        repos = $enabledRepos.Count
        pid = $PID
    })
    Write-PqOwnerAction 'start'

    $harness = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))

    $passCount = 0
    $movedCount = 0
    $exclude = [Collections.Generic.List[string]]::new()
    $currentRepoLock = $null
    $exitCode = 0
    $runSw = [Diagnostics.Stopwatch]::StartNew()
    $waiting = $false

    try {
        while ($true) {
            # 1. Stop check
            if ([IO.File]::Exists($stopPath)) {
                $null = Write-PqEvent -Log $log -Ev 'run.stop' -Run $runId -Worker $slot -D ([ordered]@{
                    level = 'pass'
                    reason = 'owner'
                    passesInFlight = 0
                })
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

            # 3. Check occupied repositories
            $current = Read-PqRegistry
            if (-not $current.ok) { throw 'RegistryInvalid: cannot reload the registry' }
            $Registry = $current.registry
            $byKey = @{}
            foreach ($r in @($Registry.repos)) { $byKey[[string]$r.key] = $r }
            $occupied = Get-PqOccupiedRepos $Registry

            # New tickets of every repository join the bottom of PORTFOLIO_QUEUE.md before the rank reads it. A failed
            # sync (the owner saving the file at that moment) is retried on the next turn and never stops the loop.
            try {
                $qpSync = Get-PqQueuePath $Registry
                if ([IO.File]::Exists($qpSync)) { $null = Sync-PqRegisteredQueues -Path $qpSync -Registry $Registry -Log }
            }
            catch { }

            # 4. Rank. The loop reads only the first candidate, so the walk ends at the first head found: one picker run
            # per queue row costs minutes on a queue of a hundred rows.
            if (-not $waiting) { Write-Host 'ranking the queue' }
            $rank = Get-PqNextRank -Registry $Registry -HarnessRoot $harness -Exclude $exclude -Occupied $occupied -Slots 1 -StopAfter 1
            foreach ($e in @($rank.events)) {
                $null = Write-PqEvent -Log $log -Ev $e.ev -Run $runId -Worker $slot -D $e.d
            }

            # 5. Handle empty candidates
            if (@($rank.candidates).Count -eq 0) {
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

                # Wait
                $null = Write-PqEvent -Log $log -Ev 'wait.enter' -Run $runId -Worker $slot -D ([ordered]@{ open = 0 })
                $waitSw = [Diagnostics.Stopwatch]::StartNew()
                $trigger = 'heartbeat'
                $sliceMs = 1000
                $poll = if ($PollSeconds -gt 0) { $PollSeconds } else { [int]$Registry.pollSeconds }
                if (-not $waiting) { Write-Host "waiting for tickets (poll ${poll}s)"; $waiting = $true }
                $totalWaitMs = [long]$poll * 1000
                while ($waitSw.ElapsedMilliseconds -lt $totalWaitMs) {
                    $rem = $totalWaitMs - $waitSw.ElapsedMilliseconds
                    Start-Sleep -Milliseconds ([Math]::Min($sliceMs, [Math]::Max(50, [int]$rem)))
                    if ([IO.File]::Exists($stopPath)) {
                        $trigger = 'owner'
                        break
                    }
                }
                $waitSw.Stop()
                $null = Write-PqEvent -Log $log -Ev 'wait.exit' -Run $runId -Worker $slot -D ([ordered]@{
                    waited = [Math]::Round($waitSw.ElapsedMilliseconds / 1000, 1)
                    trigger = $trigger
                })

                if ($trigger -ceq 'owner') {
                    $null = Write-PqEvent -Log $log -Ev 'run.stop' -Run $runId -Worker $slot -D ([ordered]@{
                        level = 'pass'
                        reason = 'owner'
                        passesInFlight = 0
                    })
                    break
                }
                continue
            }

            # 6. We have a candidate
            $cand = $rank.candidates[0]
            if ($waiting) { Write-Host 'queue resumed'; $waiting = $false }
            $repoKey = [string]$cand.repo
            $ticketId = [string]$cand.id
            $repoRec = $byKey[$repoKey]
            $repoPath = [string]$repoRec.path
            $isConcurrent = (Get-PqValue $repoRec 'concurrent' $false) -eq $true

            if (-not $isConcurrent) {
                $currentRepoLock = Lock-PqRepo -RepoKey $repoKey
                if (-not $currentRepoLock) { continue }
            }

            # A stop may arrive while a repository's picker is running.
            if ([IO.File]::Exists($stopPath)) { continue }

            Set-PqWorkerState -Slot $slot -Repo $repoKey -Ticket $ticketId
            $passNum = $passCount + 1
            $passId = "$runId.$passNum"
            $statusBefore = [string]$cand.status

            $permMode = Get-PqValue $repoRec 'permissionMode'
            if (-not $permMode) { $permMode = Get-PqValue $Registry 'permissionMode' }
            if (-not $permMode) { throw "PermissionModeMissing: set permissionMode for $repoKey before starting unattended work" }

            $onStarted = {
                param($childPid)
                $null = Write-PqEvent -Log $log -Ev 'pass.launch' -Run $runId -Repo $repoKey -Id $ticketId -Pass $passId -Worker $slot -D ([ordered]@{
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
            Write-Host "pass $passNum $repoKey`:$ticketId $statusBefore - started"
            $childRes = Invoke-PqPassChild -Script $actualRunner -RepoPath $repoPath -TicketId $ticketId -Instance "pq$slot" -PermissionMode $permMode -OnStarted $onStarted
            $passSw.Stop()
            $elapsedSec = [Math]::Round($passSw.ElapsedMilliseconds / 1000, 1)

            # Outcome and runs.jsonl row
            $outcomeRes = Read-PqPassOutcome -RepoPath $repoPath -Instance "pq$slot" -TicketId $ticketId -StatusBefore $statusBefore -ChildExitCode $childRes.code -HarnessRoot $harness -JournalOffset $journalOffset
            if ($childRes.killed) { $outcomeRes.outcome = 'killed' }
            elseif ($childRes.failed) { $outcomeRes.outcome = 'launch-failed' }
            $runRow = [ordered]@{
                run = $runId
                pass = $passId
                repo = $repoKey
                id = $ticketId
                agent = 'claude'
                model = $outcomeRes.model
                complexity = $outcomeRes.complexity
                statusBefore = $statusBefore
                statusAfter = $outcomeRes.statusAfter
                moved = [bool]$outcomeRes.moved
                outcome = $outcomeRes.outcome
                exitCode = $childRes.code
                minutes = [Math]::Round($elapsedSec / 60, 2)
                seconds = $elapsedSec
                finishedAt = (Get-Date).ToString('s')
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
            $null = Write-PqEvent -Log $log -Ev 'pass.end' -Run $runId -Repo $repoKey -Id $ticketId -Pass $passId -Worker $slot -D ([ordered]@{
                exit = $childRes.code
                outcome = $mappedOutcome
                launches = $outcomeRes.launches
                statusBefore = $statusBefore
                statusAfter = $outcomeRes.statusAfter
                moved = [bool]$outcomeRes.moved
                elapsed = $elapsedSec
            })

            for ($limit = 0; $limit -lt $outcomeRes.limits; $limit++) {
                $null = Write-PqEvent -Log $log -Ev 'pass.limit' -Run $runId -Repo $repoKey -Id $ticketId -Pass $passId -Worker $slot -D ([ordered]@{
                    agent = 'claude'
                    source = 'log'
                    detector = 'proven'
                })
            }

            # V5: A ticket that did not move (or failed, except on limit-hit)
            if ($outcomeRes.outcome -cne 'limit-hit' -and (-not $outcomeRes.moved -or $outcomeRes.outcome -cnotin @('ok', 'context-handoff'))) {
                $exclude.Add("$repoKey`:$ticketId")
            }

            if ($currentRepoLock) {
                Unlock-PqRepo -LockFile $currentRepoLock
                $currentRepoLock = $null
            }
            Set-PqWorkerState -Slot $slot -Repo $null -Ticket $null

            $passCount++
            if ($outcomeRes.moved) { $movedCount++ }
            Write-Host "pass $passNum $repoKey`:$ticketId $statusBefore -> $($outcomeRes.statusAfter) ($($outcomeRes.outcome), ${elapsedSec}s)"
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
        Remove-PqWorkerState -Slot $slot
        try { $null = Close-PqLog -Log $log } catch { }
        Write-Host "pq stopped: passes=$passCount exit=$exitCode"
    }
    return $exitCode
}
