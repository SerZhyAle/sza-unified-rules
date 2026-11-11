#requires -Version 7.0
# The inbox drain (S0047): every ticket a phone packet filed is run once through the normal dispatcher
# (`pq start -Ticket <key>:<id>`, TASK-FLOW rule 66), never through a runner of its own.
#
# Dot-source this file; it defines functions only, sets no preference and prints nothing. It loads the spool
# library (and through it the packet reader). The drain is a CALLER of the dispatcher, like PQShell's Run now:
# it never launches a runner, never edits a hold line or a status, and adds no selection logic - occupancy, the
# repository lock, the lease, the stops and the provider holds are the dispatcher's, and a refusal is recorded.
#
# The cursor. <inbox root>\inbox-state.json (beside the spool, done criterion 1):
#   { schemaVersion: 1, updatedAt, baselineAt, packets: { <packetId>: { tickets: [..], filedAt,
#     executions: { "<key>:<id>": { execution, reason, at, pid* } } } } }
#   execution: ran | skipped | not-run | launching (written BEFORE the named start, so a drain killed mid-pass
#   leaves evidence: the next drain records it `not-run: interrupted` and never starts that ticket a second time -
#   the double-run guard; the main loop still works the ticket). Written atomically, temp + rename, like
#   Write-PqRegistry. A missing cursor leaves all filed packets eligible for their first decision.
#
#   Read-InboxDrainState -Root               the cursor, a fresh one when the file is absent; throws
#                                            'InboxDrainStateUnreadable: <path>' on a file that does not parse.
#   Write-InboxDrainState -Root -State       temp + rename; returns the path.
#   Get-InboxDonePackets -Root               done/ packets carrying a result.json: @{ packetId; path; tickets;
#                                            at; named (the keys the manifest asked for); result }, oldest first.
#   Get-InboxDrainPending -Root -State       per done packet the tickets with no decided execution:
#                                            @{ packetId; tickets; at; named; projectless; path }.
#   Get-InboxDrainTarget -Ticket -Named      run | triage: a ticket whose key the packet did not name (no project
#                                            at all, or an unknown key routed to canon by S0046) is the owner's -
#                                            never auto-run (owner choice 3(b)).
#   ConvertFrom-InboxPqResult -Code -Lines -Ticket
#                                            the named start's outcome: @{ execution; reason }. 0 ran; 3 the
#                                            printed `pq: ticket <k:i> not run - <reason>` line, a lease reason
#                                            being `skipped` (the main loop is working it), any other `not-run`;
#                                            2 or anything else `not-run` with the stderr line.
#   Set-InboxResultExecution -PacketPath -Executions
#                                            the packet's result.json gains `execution` (ran | skipped | <reason>
#                                            for one ticket; ran | mixed for several) and `executions` [..];
#                                            additive members, temp + rename.
#   Get-InboxDrainSummary -Root              what pq status prints: @{ present; new; filedWaiting; oldestAge }.

. (Join-Path $PSScriptRoot 'inbox-spool.ps1')

$script:InboxDrainStateName = 'inbox-state.json'

function Get-InboxDrainStatePath([string]$Root) { return (Join-Path $Root $script:InboxDrainStateName) }

function New-InboxDrainState {
    return [ordered]@{ schemaVersion = 1; updatedAt = $null; baselineAt = $null; packets = [ordered]@{} }
}

function Read-InboxDrainState {
    param([Parameter(Mandatory)][string]$Root)
    $path = Get-InboxDrainStatePath $Root
    if (-not [IO.File]::Exists($path)) { return (New-InboxDrainState) }
    try { $doc = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($path)) -AsHashtable -DateKind String }
    catch { throw "InboxDrainStateUnreadable: $path" }
    if ($doc -isnot [Collections.IDictionary] -or $doc['schemaVersion'] -ne 1 -or $doc['packets'] -isnot [Collections.IDictionary]) { throw "InboxDrainStateUnreadable: $path" }
    $state = New-InboxDrainState
    foreach ($k in @('updatedAt', 'baselineAt')) { if ($doc.Contains($k)) { $state[$k] = $doc[$k] } }
    if ($doc.Contains('packets') -and $doc['packets'] -is [Collections.IDictionary]) {
        foreach ($id in @($doc['packets'].Keys)) {
            $p = $doc['packets'][$id]
            if ($p -isnot [Collections.IDictionary] -or $p['tickets'] -isnot [array] -or $p['executions'] -isnot [Collections.IDictionary]) { throw "InboxDrainStateUnreadable: $path" }
            $ex = [ordered]@{}
            if ($p.Contains('executions') -and $p['executions'] -is [Collections.IDictionary]) {
                foreach ($t in @($p['executions'].Keys)) {
                    $decision = $p['executions'][$t]
                    if ($decision -isnot [Collections.IDictionary] -or $decision['execution'] -cnotin @('launching', 'ran', 'skipped', 'not-run')) { throw "InboxDrainStateUnreadable: $path" }
                    $ex[$t] = $decision
                }
            }
            $state.packets[$id] = [ordered]@{ tickets = @($p['tickets']); filedAt = $p['filedAt']; executions = $ex }
        }
    }
    return $state
}

function Write-InboxDrainState {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)]$State)
    $path = Get-InboxDrainStatePath $Root
    $State.updatedAt = [DateTimeOffset]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    $json = (ConvertTo-Json -InputObject $State -Depth 10).Replace("`r`n", "`n") + "`n"
    $tmp = "$path.$PID.tmp"
    [IO.File]::WriteAllText($tmp, $json, [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($tmp, $path, $true)
    return $path
}

# The keys the packet's manifest asked for (project + projects[]); none = a project-less packet.
function Get-InboxManifestKeys([string]$PacketPath) {
    $read = Read-InboxPacketManifest -Path (Join-Path $PacketPath 'manifest.json')
    if (-not $read.ok) { return @() }
    $keys = [Collections.Generic.List[string]]::new()
    $p = Get-InboxMember $read.document 'project'
    if ($p.value -is [string] -and $p.value) { $keys.Add([string]$p.value) }
    foreach ($k in @(Get-InboxArrayValue $read.document 'projects')) { if ($k -is [string] -and $k -and -not $keys.Contains($k)) { $keys.Add($k) } }
    return @($keys)
}

function Get-InboxDonePackets {
    param([Parameter(Mandatory)][string]$Root)
    $doneDir = Join-Path $Root 'done'
    if (-not [IO.Directory]::Exists($doneDir)) { return @() }
    $list = [Collections.Generic.List[object]]::new()
    foreach ($dir in [IO.Directory]::GetDirectories($doneDir)) {
        $resultPath = Join-Path $dir 'result.json'
        if (-not [IO.File]::Exists($resultPath)) { continue }
        try { $result = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($resultPath)) -AsHashtable -DateKind String } catch { throw "InboxResultUnreadable: $resultPath" }
        if ($result -isnot [Collections.IDictionary] -or $result['tickets'] -isnot [array]) { throw "InboxResultUnreadable: $resultPath" }
        $list.Add([pscustomobject]@{
            packetId = Split-Path -Leaf $dir
            path     = $dir
            tickets  = @(@($result['tickets']) | Where-Object { $_ -is [string] -and $_ -match '^[^:\s]+:[^:\s]+$' })
            at       = [string]$result['at']
            named    = @(Get-InboxManifestKeys $dir)
            result   = $result
        })
    }
    return @($list | Sort-Object -Property at, packetId)
}

function Get-InboxDrainTarget {
    param([Parameter(Mandatory)][string]$Ticket, [string[]]$Named = @(), [string[]]$Known = @())
    $key = ($Ticket -split ':', 2)[0]
    # A canon ticket may combine an explicit canon target and an unknown project's triage.
    if ($key -ieq 'canon' -and @($Named | Where-Object { $Known -notcontains $_ }).Count -gt 0) { return 'triage' }
    if (@($Named) -contains $key) { return 'run' }
    return 'triage'
}

function Test-InboxExecutionDecided($Entry) {
    if ($null -eq $Entry) { return $false }
    return ([string]$Entry['execution'] -cne 'launching')
}

function Get-InboxDrainPending {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)]$State)
    $pending = [Collections.Generic.List[object]]::new()
    foreach ($p in @(Get-InboxDonePackets -Root $Root)) {
        $known = if ($State.packets.Contains($p.packetId)) { $State.packets[$p.packetId] } else { $null }
        $open = @(foreach ($t in @($p.tickets)) {
                $e = if ($null -ne $known -and $known.executions.Contains($t)) { $known.executions[$t] } else { $null }
                if (-not (Test-InboxExecutionDecided $e)) { $t }
            })
        if ($open.Count -eq 0) { continue }
        $pending.Add([pscustomobject]@{ packetId = $p.packetId; path = $p.path; tickets = $open; at = $p.at; named = $p.named
                projectless = (@($p.named).Count -eq 0) })
    }
    return @($pending)
}

function ConvertFrom-InboxPqResult {
    param([int]$Code, $Lines, [string]$Ticket)
    $lines = @(@($Lines) | Where-Object { $_ } | ForEach-Object { ([string]$_).TrimEnd() })
    if ($Code -eq 0) { return @{ execution = 'ran'; reason = $null } }
    if ($Code -eq 3) {
        $reason = $null
        $pattern = '^pq: ticket ' + [regex]::Escape($Ticket) + ' not run - (?<r>.+)$'
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            $m = [regex]::Match($lines[$i], $pattern)
            if ($m.Success) { $reason = $m.Groups['r'].Value.Trim(); break }
        }
        if (-not $reason) {
            $last = @($lines | Where-Object { $_ -match '^pq: ' } | Select-Object -Last 1)
            $reason = if ($last.Count) { $last[0] } else { 'exit 3 with no reason line' }
        }
        if ($reason -match '(?i)\blease\b') { return @{ execution = 'skipped'; reason = "leased: $reason" } }
        return @{ execution = 'not-run'; reason = $reason }
    }
    $err = @($lines | Where-Object { $_ -match '^pq: ' } | Select-Object -Last 1)
    $why = if ($err.Count) { $err[0] } else { "pq exited $Code" }
    return @{ execution = 'not-run'; reason = "exit ${Code}: $why" }
}

function Set-InboxResultExecution {
    param([Parameter(Mandatory)][string]$PacketPath, [Parameter(Mandatory)]$Executions)
    $path = Join-Path $PacketPath 'result.json'
    if (-not [IO.File]::Exists($path)) { return $false }
    try {
        $doc = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($path)) -AsHashtable -DateKind String
        $rows = @(foreach ($t in @($Executions.Keys)) {
                $e = $Executions[$t]
                [ordered]@{ ticket = $t; execution = [string]$e['execution']; reason = $e['reason']; at = $e['at'] }
            })
        $label = { param($r) if ($r.execution -ceq 'ran') { 'ran' } elseif ($r.execution -ceq 'skipped') { 'skipped' } else { [string]$r.reason } }
        $doc['execution'] = if ($rows.Count -eq 1) { & $label $rows[0] }
                            elseif (@($rows | Where-Object { $_.execution -cne 'ran' }).Count -eq 0) { 'ran' } else { 'mixed' }
        $doc['executions'] = $rows
        $json = (ConvertTo-Json -InputObject $doc -Depth 8).Replace("`r`n", "`n") + "`n"
        $tmp = "$path.$PID.tmp"
        [IO.File]::WriteAllText($tmp, $json, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($tmp, $path, $true)
        return $true
    }
    catch { return $false }
}

function Get-InboxDrainSummary {
    param([Parameter(Mandatory)][string]$Root)
    $age = Get-InboxSpoolAge -Root $Root
    $out = @{ present = $age.present; new = 0; filedWaiting = 0; oldestAge = 'none'; stale = 0 }
    if (-not $age.present) { return $out }
    $out.new = [int]$age.waiting + [int]$age.processing
    $out.stale = [int]$age.stale
    $oldest = $age.oldestAgeSeconds
    try {
        $pending = @(Get-InboxDrainPending -Root $Root -State (Read-InboxDrainState -Root $Root))
        foreach ($p in $pending) { $out.filedWaiting += @($p.tickets).Count }
        foreach ($p in $pending) {
            $at = [DateTimeOffset]::MinValue
            if ([DateTimeOffset]::TryParse([string]$p.at, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$at)) {
                $s = [long][Math]::Max(0, ([DateTimeOffset]::UtcNow - $at).TotalSeconds)
                if ($null -eq $oldest -or $s -gt $oldest) { $oldest = $s }
            }
        }
    }
    catch { }
    if (($out.new + $out.filedWaiting) -gt 0) { $out.oldestAge = ConvertTo-InboxAgeText $oldest }
    return $out
}

# S0048: the build half of a ran ticket. The packet's result.json gains `builds` [..] - additive members, like
# `execution`/`executions` beside them: one row per build decision, written AFTER the build finishes (a drain
# killed mid-build leaves no row, so the next drain tries again exactly once - a rebuild, never a run skipped
# as done). A row: @{ ticket; outcome (delivered | refused | not-built | deferred); version*; dir*; reason*;
# at }. Guard: a row with a decided outcome for that ticket means the decision stands - never built twice.
function Add-InboxResultBuild {
    param([Parameter(Mandatory)][string]$PacketPath, [Parameter(Mandatory)]$Build)
    $path = Join-Path $PacketPath 'result.json'
    if (-not [IO.File]::Exists($path)) { return $false }
    try {
        $doc = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($path)) -AsHashtable -DateKind String
        $rows = @()
        if ($doc.Contains('builds') -and $doc['builds'] -is [array]) { $rows = @($doc['builds'] | Where-Object { $null -ne $_ }) }
        if (@($rows | Where-Object { $_['ticket'] -ceq $Build['ticket'] -and $_['outcome'] -cne 'deferred' }).Count -gt 0) { return $true }
        $rows = @($rows + @([ordered]@{ ticket = [string]$Build['ticket']; outcome = [string]$Build['outcome']; version = $Build['version']; dir = $Build['dir']; reason = $Build['reason']; at = $Build['at'] }))
        $doc['builds'] = $rows
        $json = (ConvertTo-Json -InputObject $doc -Depth 8).Replace("`r`n", "`n") + "`n"
        $tmp = "$path.$PID.tmp"
        [IO.File]::WriteAllText($tmp, $json, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($tmp, $path, $true)
        return $true
    }
    catch { return $false }
}

# The build decision already standing for one ticket of one packet (a decided row, a deferred one included -
# deferred is also a decision, only a killed build erases nothing and so retries).
function Test-InboxResultBuildDecided {
    param([Parameter(Mandatory)]$Result, [Parameter(Mandatory)][string]$Ticket)
    if ($null -eq $Result) { return $false }
    if (-not ($Result -is [Collections.IDictionary]) -or -not $Result.Contains('builds') -or $Result['builds'] -isnot [array]) { return $false }
    return (@($Result['builds'] | Where-Object { $null -ne $_ -and $_['ticket'] -ceq $Ticket }).Count -gt 0)
}
