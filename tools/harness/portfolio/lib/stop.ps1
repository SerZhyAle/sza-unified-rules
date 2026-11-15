# Stop files, stop levels and the pause of the portfolio dispatcher (TASK-FLOW rule 47; S0016 R54-R56).
#
# Dot-source this file after loop.ps1 (it uses Read-PqState and Test-PqStateOwner); it defines functions only, sets
# no preference and prints nothing.
#
#   Get-PqStopLevelRank        drain 1 < pass 2 < halt 3 < kill 4; anything else reads as pass (the default of pq stop).
#   Get-PqStopFiles            every stop file in the portfolio root: STOP, STOP-worker__<n>, STOP-repo__<key>,
#                              STOP-agent__<name>, STOP-ticket__<key>__<id>, each as kind, target, level, by, at, reason.
#   Get-PqApplicableStop       the most severe stop that names this worker, repository, agent or ticket (or all of them).
#   Get-PqWorkerFiles          the live workers' state files as slot, repository, ticket, agent, since, and the drain carry
#                              (`drainCarry` <key>:<id>, `carryAgent`) of a worker between two passes of one ticket.
#   Test-PqStopTargetBusy      does any live worker have work in flight under that stop's target; a worker carrying a
#                              ticket under a drain counts for that ticket's repository, agent and ticket (S0082).
#   Test-PqDrainCarry          does a pass that ended under this stop give its ticket another pass (rule 47 drain).
#   Get-PqCarryStop            the target stop (repository, agent, ticket) that lets a carried ticket go on: the most
#                              severe target stop over it when that one is a drain, else nothing.
#   Get-PqChangedSince         the repository's files git reports changed whose write time is at or after a moment,
#                              or which are gone: what a halted or killed pass changed (rule 47).
#   Clear-PqDeadLocks          the repository's coordination locks left by dead processes, cleared by the locks
#                              tool in its conservative mode (a live holder is refused, never cleared).
#   Invoke-PqStopCleanup       halt and kill cleanup of rule 47 past the lease: dead locks cleared, ledger validated,
#                              changed files collected; never decides a status and never throws.
#   Complete-PqStop            honour a target stop that has nothing left in flight: delete its file; a repository stop
#                              leaves the registry hold of that repository (rule 47).
#   Get-PqPausePath            <root>\PAUSE: the pause of S0016 R56.
#   Test-PqPaused              is the file there.
#   Set-PqPause / Clear-PqPause   write / delete it.

function Get-PqStopLevelRank([string]$Level) {
    switch ($Level) { 'drain' { 1 } 'pass' { 2 } 'halt' { 3 } 'kill' { 4 } default { 2 } }
}

function Get-PqStopFiles {
    $root = Get-PqRoot
    $list = [Collections.Generic.List[object]]::new()
    if (-not [IO.Directory]::Exists($root)) { return @() }
    foreach ($file in [IO.Directory]::GetFiles($root, 'STOP*')) {
        $name = [IO.Path]::GetFileName($file)
        $kind = $null
        $target = $null
        if ($name -ceq 'STOP') { $kind = 'all' }
        elseif ($name -cmatch '^STOP-(worker|repo|agent)__(.+)$') { $kind = $Matches[1]; $target = $Matches[2] }
        elseif ($name -cmatch '^STOP-ticket__(.+?)__(.+)$') { $kind = 'ticket'; $target = "$($Matches[1]):$($Matches[2])" }
        else { continue }
        $state = Read-PqState $file
        $level = [string](Get-PqValue $state 'level' 'pass')
        if ($level -cnotin @('drain', 'pass', 'halt', 'kill')) { $level = 'pass' }
        $list.Add([pscustomobject]@{
                kind = $kind; target = $target; file = $file; level = $level
                by = [string](Get-PqValue $state 'by' ''); at = [string](Get-PqValue $state 'at' ''); reason = [string](Get-PqValue $state 'reason' 'owner')
            })
    }
    return @($list)
}

function Get-PqApplicableStop {
    param($Stops, [int]$Slot = 0, [string]$Repo = '', [string]$Agent = '', [string]$Ticket = '')
    $best = $null
    foreach ($s in @($Stops)) {
        $hit = switch ($s.kind) {
            'all' { $true }
            'worker' { ($Slot -gt 0) -and (([string]$Slot) -ceq $s.target) }
            'repo' { $Repo -and ($s.target -ceq $Repo) }
            'agent' { $Agent -and ($s.target -ceq $Agent) }
            'ticket' { $Ticket -and ($s.target -ceq $Ticket) }
            default { $false }
        }
        if ($hit -and ($null -eq $best -or (Get-PqStopLevelRank $s.level) -gt (Get-PqStopLevelRank $best.level))) { $best = $s }
    }
    return $best
}

# The live workers (a process that still owns its state file) as slot, repository, ticket, agent. A worker between
# passes has no repository and no ticket.
function Get-PqWorkerFiles {
    $runDir = Join-Path (Get-PqRoot) 'run'
    $out = [Collections.Generic.List[object]]::new()
    if (-not [IO.Directory]::Exists($runDir)) { return @() }
    foreach ($wf in [IO.Directory]::GetFiles($runDir, 'worker-*.json')) {
        $s = Read-PqState $wf
        if ($null -eq $s -or -not (Test-PqStateOwner $s)) { continue }
        $slot = 0
        if ([IO.Path]::GetFileNameWithoutExtension($wf) -match '^worker-(\d+)$') { $slot = [int]$Matches[1] }
        $repo = [string](Get-PqValue $s 'repository' '')
        $ticket = [string](Get-PqValue $s 'ticket' '')
        $out.Add([pscustomobject]@{
                slot = $slot; pid = [int](Get-PqValue $s 'pid' 0); repository = $repo; ticket = $ticket
                agent = [string](Get-PqValue $s 'agent' ''); key = $(if ($repo -and $ticket) { "${repo}:$ticket" } else { '' })
                carry = [string](Get-PqValue $s 'drainCarry' ''); carryAgent = [string](Get-PqValue $s 'carryAgent' '')
                since = [string](Get-PqValue $s 'since' '')
            })
    }
    return @($out)
}

function Test-PqStopTargetBusy($Stop, $Workers) {
    foreach ($w in @($Workers)) {
        $key = [string]$w.key
        $repo = [string]$w.repository
        $agent = [string]$w.agent
        # A worker between two passes of a drained ticket still has that ticket under the stop (S0082, rule 47).
        $carry = [string](Get-PqValue $w 'carry' '')
        if (-not $key -and $carry) { $key = $carry; $repo = ($carry -split ':', 2)[0]; $agent = [string](Get-PqValue $w 'carryAgent' '') }
        if (-not $key) { continue }
        $busy = switch ($Stop.kind) {
            'all' { $true }
            'worker' { ([string]$w.slot) -ceq $Stop.target }
            'repo' { $repo -ceq $Stop.target }
            'agent' { $agent -and ($agent -ceq $Stop.target) }
            'ticket' { $key -ceq $Stop.target }
            default { $false }
        }
        if ($busy) { return $true }
    }
    return $false
}

# Rule 47 drain: a ticket whose pass moved it and was not killed gets its next pass while the stop over it is a
# drain - whatever the stop's target (S0082: before, only STOP and STOP-worker carried it).
function Test-PqDrainCarry($Stop, [bool]$Moved, [bool]$Killed) {
    return ($null -ne $Stop -and $Moved -and -not $Killed -and [string]$Stop.level -ceq 'drain')
}

# The target stop that lets a carried ticket (<key>:<id>, last run by $Agent) go on: among the repository, agent and
# ticket stops over it the most severe one, returned only when it is a drain. A pass, halt or kill over the same
# ticket wins, and then nothing carries it.
function Get-PqCarryStop {
    param($Stops, [string]$Carry, [string]$Agent = '')
    if (-not $Carry) { return $null }
    $repo = ($Carry -split ':', 2)[0]
    $targets = @(@($Stops) | Where-Object { $null -ne $_ -and $_.kind -cin @('repo', 'agent', 'ticket') })
    $best = Get-PqApplicableStop -Stops $targets -Repo $repo -Agent $Agent -Ticket $Carry
    if ($null -ne $best -and $best.level -ceq 'drain') { return $best }
    return $null
}

# What a halted or killed pass changed (rule 47): the paths `git status` names whose file was written at or after
# $Since, or which no longer exist, repository-relative with forward slashes, sorted. Untracked files count; ignored
# ones do not. Not a git repository, or git missing: an empty list.
function Get-PqChangedSince {
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][datetime]$Since)
    $out = [Collections.Generic.List[string]]::new()
    try {
        $raw = & git -C $RepoPath status --porcelain=v1 -z --untracked-files=all 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $raw) { return @() }
        $entries = ([string]($raw -join "`n")) -split "`0"
        $sinceUtc = $Since.ToUniversalTime()
        for ($i = 0; $i -lt $entries.Count; $i++) {
            $e = $entries[$i]
            if ($e.Length -lt 4) { continue }
            $code = $e.Substring(0, 2)
            $rel = $e.Substring(3)
            # A rename or copy entry is followed by its source path, which is not a change of its own.
            if ($code -match '[RC]') { $i++ }
            $full = Join-Path $RepoPath $rel
            $hit = $true
            if ([IO.File]::Exists($full)) { $hit = ([IO.File]::GetLastWriteTimeUtc($full) -ge $sinceUtc) }
            elseif ([IO.Directory]::Exists($full)) { $hit = ([IO.Directory]::GetLastWriteTimeUtc($full) -ge $sinceUtc) }
            if ($hit) { $out.Add($rel.Replace('\', '/').TrimEnd('/')) }
        }
    }
    catch { return @() }
    return @($out | Sort-Object -Unique)
}

# The locks of dead processes in a repository (rule 47): the locks tool's clear-agent-lock.ps1 without -Force, for
# both bare types, so a stale or dead holder is removed and a live one is refused and left alone. Returns per type the
# tool's exit code (0 free, 1 a live holder kept, 2 no such domain) or 'timeout' / 'error'. $Invoker replaces the
# child runner (Invoke-PqRepoChild) for a test: it gets the repository path, the script and its arguments.
function Clear-PqDeadLocks {
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][string]$HarnessRoot, [scriptblock]$Invoker = $null)
    $result = [ordered]@{}
    $clear = [IO.Path]::Combine($HarnessRoot, 'locks', 'clear-agent-lock.ps1')
    foreach ($name in @('Build', 'Code')) {
        try {
            $r = if ($null -ne $Invoker) { & $Invoker $RepoPath $clear @('-Name', $name) } else { Invoke-PqRepoChild -RepoPath $RepoPath -Script $clear -Arguments @('-Name', $name) -TimeoutSeconds 60 }
            $result[$name] = if ($r.timedOut) { 'timeout' } else { [int]$r.code }
        }
        catch { $result[$name] = 'error' }
    }
    return $result
}

# Halt and kill cleanup past the lease and the resources (rule 47): the locks of dead processes cleared, the ledger
# validated (rule 10), the files changed since the pass began collected for the owner. Never decides a status, never
# throws. Returns validate, locks and changed.
function Invoke-PqStopCleanup {
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][string]$HarnessRoot, [Parameter(Mandatory)][datetime]$Since, [scriptblock]$Invoker = $null)
    $locks = Clear-PqDeadLocks -RepoPath $RepoPath -HarnessRoot $HarnessRoot -Invoker $Invoker
    $validate = $null
    try {
        $vs = [IO.Path]::Combine($HarnessRoot, 'spec_catalog', 'validate.ps1')
        $vr = if ($null -ne $Invoker) { & $Invoker $RepoPath $vs @() } else { Invoke-PqRepoChild -RepoPath $RepoPath -Script $vs -Arguments @() -TimeoutSeconds 120 }
        $validate = if ($vr.timedOut) { 'timeout' } else { [int]$vr.code }
    }
    catch { $validate = 'error' }
    $changed = @(Get-PqChangedSince -RepoPath $RepoPath -Since $Since)
    return [ordered]@{ validate = $validate; locks = $locks; changed = $changed }
}

# Honours a target stop (never the whole-portfolio STOP, which a later start clears): the file goes, and a repository
# stop leaves the registry's hold of that repository until the owner clears it (rule 47). Never throws.
function Complete-PqStop {
    param([Parameter(Mandatory)]$Stop, $Log)
    try {
        if ($Stop.kind -ceq 'all') { return }
        Remove-Item -LiteralPath $Stop.file -Force -ErrorAction SilentlyContinue
        if ($Stop.kind -ceq 'repo') {
            if ($null -ne $Log) { $null = Set-PqRepoHold -Key $Stop.target -Hold $true -Log } else { $null = Set-PqRepoHold -Key $Stop.target -Hold $true }
        }
    }
    catch { }
}

function Get-PqPausePath { return (Join-Path (Get-PqRoot) 'PAUSE') }

function Test-PqPaused { return [IO.File]::Exists((Get-PqPausePath)) }

function Set-PqPause {
    $root = Initialize-PqRoot
    $obj = [ordered]@{ by = 'cli'; at = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') }
    $path = Join-Path $root 'PAUSE'
    $existed = [IO.File]::Exists($path)
    [IO.File]::WriteAllText($path, ($obj | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
    return (-not $existed)
}

function Clear-PqPause {
    $path = Get-PqPausePath
    if (-not [IO.File]::Exists($path)) { return $false }
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    return $true
}
