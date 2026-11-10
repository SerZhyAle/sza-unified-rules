# Stop files, stop levels and the pause of the portfolio dispatcher (TASK-FLOW rule 47; S0016 R54-R56).
#
# Dot-source this file after loop.ps1 (it uses Read-PqState and Test-PqStateOwner); it defines functions only, sets
# no preference and prints nothing.
#
#   Get-PqStopLevelRank        drain 1 < pass 2 < halt 3 < kill 4; anything else reads as pass (the default of pq stop).
#   Get-PqStopFiles            every stop file in the portfolio root: STOP, STOP-worker__<n>, STOP-repo__<key>,
#                              STOP-agent__<name>, STOP-ticket__<key>__<id>, each as kind, target, level, by, at, reason.
#   Get-PqApplicableStop       the most severe stop that names this worker, repository, agent or ticket (or all of them).
#   Get-PqWorkerFiles          the live workers' state files as slot, repository, ticket, agent.
#   Test-PqStopTargetBusy      does any live worker have work in flight under that stop's target.
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
            })
    }
    return @($out)
}

function Test-PqStopTargetBusy($Stop, $Workers) {
    foreach ($w in @($Workers)) {
        if (-not $w.key) { continue }
        $busy = switch ($Stop.kind) {
            'all' { $true }
            'worker' { ([string]$w.slot) -ceq $Stop.target }
            'repo' { $w.repository -ceq $Stop.target }
            'agent' { $w.agent -ceq $Stop.target }
            'ticket' { $w.key -ceq $Stop.target }
            default { $false }
        }
        if ($busy) { return $true }
    }
    return $false
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
