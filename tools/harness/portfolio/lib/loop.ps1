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
        [string[]]$AgentArgs = @()
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
        $titlePart = if ($TicketTitle) { " - $TicketTitle" } else { '' }
        try { $host.UI.RawUI.WindowTitle = "pass $Instance $TicketId$titlePart" } catch { }
        while (-not $proc.WaitForExit(250)) {
            if ($passSw.Elapsed.TotalSeconds -ge $beatAt) {
                Write-Host ('pass {0} {1}{2} - still running, {3:hh\:mm\:ss} elapsed' -f $Instance, $TicketId, $titlePart, $passSw.Elapsed) -ForegroundColor DarkGray
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
        if ($t.file) {
            $f = Resolve-PqRepoPathValue $snap.root ([string]$t.file)
            if ([IO.File]::Exists($f)) { $specMtime = [IO.File]::GetLastWriteTimeUtc($f).ToString('o') }
        }
        return [ordered]@{ status = [string]$t.status; updated = [string]$t.updated; specMtime = [string]$specMtime }
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
    $drops = @{}
    $xblocked = @{}
    $joinSeen = @{}
    $nextDiscoveryAt = [DateTime]::MinValue
    $currentRepoLock = $null
    $exitCode = 0
    $runSw = [Diagnostics.Stopwatch]::StartNew()
    $waiting = $false
    $errStreak = 0

    try {
        while ($true) {
            $turnRepo = $null
            $turnId = $null
            $turnPath = $null
            try {
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

                # New tickets of every repository join the bottom of PORTFOLIO_QUEUE.md before the rank reads it. A failed
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
                $pick = Select-PqAgent -Registry $Registry -RepoPath $repoPath -Level $(if ($ticketLevel) { $ticketLevel } else { 'medium' })
                foreach ($fb in @($pick.fallbacks)) {
                    $null = Write-PqEvent -Log $log -Ev 'agent.fallback' -Run $runId -Repo $repoKey -Id $ticketId -Worker $slot -D ([ordered]@{ from = $fb.from; to = $pick.agent; repo = $repoKey; id = $ticketId; why = $fb.why })
                }
                if (-not $pick.agent) {
                    $null = Write-PqEvent -Log $log -Ev 'dispatch.skip' -Run $runId -Repo $repoKey -Id $ticketId -Worker $slot -D ([ordered]@{ why = 'noAgent' })
                    Write-Host "ticket $repoKey`:$ticketId - no agent may take it now ($((@($pick.fallbacks) | ForEach-Object { "$($_.from): $($_.why)" }) -join ', ')); waiting 30 s"
                    for ($w = 0; $w -lt 30 -and -not [IO.File]::Exists($stopPath); $w++) { Start-Sleep -Seconds 1 }
                    continue
                }
                $agentName = [string]$pick.agent
                $agentArgs = if ($agentName -ceq 'claude') { @() } else { Get-PqAgentPassArgs $pick }

                if (-not $isConcurrent) {
                    $currentRepoLock = Lock-PqRepo -RepoKey $repoKey
                    if (-not $currentRepoLock) { continue }
                }

                # A stop may arrive while a repository's picker is running.
                if ([IO.File]::Exists($stopPath)) { continue }

                Set-PqWorkerState -Slot $slot -Repo $repoKey -Ticket $ticketId -Title $ticketTitle -Agent $agentName
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
                Write-Host "pass $passNum $repoKey`:$ticketId $statusBefore$titlePart$agentPart - started"
                $childRes = Invoke-PqPassChild -Script $actualRunner -RepoPath $repoPath -TicketId $ticketId -TicketTitle $ticketTitle -Instance "pq$slot" -PermissionMode $permMode -OnStarted $onStarted -AgentArgs $agentArgs
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
                $null = Write-PqEvent -Log $log -Ev 'pass.end' -Run $runId -Repo $repoKey -Id $ticketId -Pass $passId -Worker $slot -Agent $agentName -D ([ordered]@{
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
                        agent = $agentName
                        source = 'log'
                        detector = 'proven'
                    })
                }

                # Rule 48 for an agent other than claude: its limit text is never read, so a fast failure that moved nothing
                # is a probable limit. The agent is held and polled, the pass is neutral to the ticket, and the next pass
                # offers the same ticket to the next agent of agentOrder. A pass that did not fail fast clears a hold: it
                # was the probe.
                $agentHeldNow = $false
                if ($agentName -cne 'claude' -and -not $childRes.killed) {
                    $fastFail = (-not $outcomeRes.moved) -and $elapsedSec -lt $script:PqFastFailureSeconds -and $outcomeRes.outcome -cin @('child-failed', 'no-progress', 'launch-failed')
                    if ($fastFail) {
                        Set-PqAgentHold -Name $agentName -Pass $passId -Source 'fastFailure' -Detector 'unproven'
                        $agentHeldNow = $true
                        $poll = [int](Get-PqValue $pick.record 'limitPollMinutes' 30)
                        $null = Write-PqEvent -Log $log -Ev 'agent.hold' -Run $runId -Repo $repoKey -Id $ticketId -Pass $passId -Worker $slot -Agent $agentName -D ([ordered]@{ agent = $agentName; until = $null; source = 'fastFailure'; detector = 'unproven' })
                        $null = Write-PqEvent -Log $log -Ev 'agent.unproven' -Run $runId -Worker $slot -Agent $agentName -D ([ordered]@{ agent = $agentName; signal = 'fastFailureNoMove'; count = 1 })
                        Write-Host "agent $agentName failed fast (${elapsedSec}s, $($outcomeRes.outcome)) - held as a probable limit, probed again in $poll min; the ticket goes to the next agent"
                    }
                    elseif (Remove-PqAgentHold -Name $agentName) {
                        $null = Write-PqEvent -Log $log -Ev 'agent.resume' -Run $runId -Worker $slot -Agent $agentName -D ([ordered]@{ agent = $agentName; by = 'probe' })
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
                Write-Host "turn failed: $($err.Exception.Message)$where$dropPart - the loop goes on in $retryIn s"
                $waiting = $false
                for ($w = 0; $w -lt $retryIn -and -not [IO.File]::Exists($stopPath); $w++) { Start-Sleep -Seconds 1 }
            }
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
        try { $host.UI.RawUI.WindowTitle = "pq - stopped" } catch { }
        Write-Host "pq stopped: passes=$passCount exit=$exitCode"
    }
    return $exitCode
}
