#requires -Version 7.0
<#
.SYNOPSIS
    One in-process snapshot of what the development machine is doing (S2406) - the object that both
    the terminal monitor (`.\a.ps1 rm`) and the monitor page (`.\a.ps1 rmw`) render.

.DESCRIPTION
    Dot-source this file; it defines functions only. Get-DevMonitorSnapshot reads seven sources and
    returns a single versioned object (schema 1):

      - ticket leases      temp/SPEC-TICKET.LEASES/*.json, liveness judged by Get-AgentTicketLiveness -
                           the same helper ticket-lease.ps1 judges by (S1621), read in-process instead
                           of through a child pwsh (434 ms of a 1000 ms budget, measured 2026-09-02);
      - stalled holders    the S2413 predicate per code domain, computed from the locks below
                           rather than re-read: held, a queue behind it, and an owner quiet past
                           that domain's LockStaleMinutes. Empty array when nothing is stalled.
      - locks and queues   temp/<DOMAIN>.LOCK and temp/<DOMAIN>.QUEUE/*.json for every domain in
                           agent-lock-domains.ps1 plus the two pre-split files, read without eviction;
      - agent chat         the progress stream (one row per agent, newest first, plus the newest
                           `phase` message of each agent), the tail of the stream, alive findings;
      - run journals       temp/spec-queue/runs-<instance>.jsonl, tail rows plus counts;
      - stop flags         temp/STOP-SPEC-QUEUE*;
      - live sessions      ticket-lease owners still judged live, plus fresh session-start records;
      - headless children  claude.exe started with -p, with the age of the newest file its ticket wrote;
      - the release queue  PLAN/RELEASE_QUEUE.md rows of the current package, in file order, with the
                           [taken ..] marker and the Block* statuses the ranker would skip.

    Reads only. No child process, no lock, no chat post, no sweep (every chat read passes -NoSweep),
    no file written - the contract suite proves the fixture is byte-for-byte untouched by one call.
    The whole call is timed into `durationMs`; the page prints it, the suite bounds it.

    Exit codes: none - library.
#>

. (Join-Path $PSScriptRoot '..\_profile.ps1')
. (Get-SzaHarnessScript 'locks/agent-lock-domains.ps1')

function ConvertFrom-DevMonitorEpoch {
    <# Epoch milliseconds -> local DateTime, or $null for anything unreadable. #>
    param($Epoch)
    if ($null -eq $Epoch -or "$Epoch" -eq '') { return $null }
    try { return [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$Epoch).LocalDateTime }
    catch { return $null }
}

function Get-DevMonitorMinutesSince {
    param($When)
    if ($null -eq $When) { return $null }
    return [math]::Round(((Get-Date) - [DateTime]$When).TotalMinutes, 1)
}

function ConvertTo-DevMonitorUtcText {
    param($When)
    if ($null -eq $When) { return $null }
    return ([DateTime]$When).ToUniversalTime().ToString('o')
}

function Get-DevMonitorRelativePath {
    param([string]$RepoRoot, [string]$Path)
    if ($Path.StartsWith($RepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $Path = $Path.Substring($RepoRoot.Length).TrimStart('\', '/')
    }
    return $Path.Replace('\', '/')
}

function Read-DevMonitorJson {
    param([string]$Path)
    try { return (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop) }
    catch { return $null }
}

function Read-DevMonitorTailLines {
    <# Read only the final bounded portion of an append-only text source. #>
    param([string]$Path, [int]$MaxBytes = 131072)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $stream = $null
    $reader = $null
    try {
        $stream = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        $start = [Math]::Max(0, $stream.Length - $MaxBytes)
        [void]$stream.Seek($start, [System.IO.SeekOrigin]::Begin)
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.UTF8Encoding]::new($false), $true)
        $text = $reader.ReadToEnd()
        $lines = @($text -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($start -gt 0 -and $lines.Count -gt 0) { $lines = @($lines | Select-Object -Skip 1) }
        return $lines
    }
    catch { return @() }
    finally {
        if ($reader) { $reader.Dispose() }
        elseif ($stream) { $stream.Dispose() }
    }
}

function Get-DevMonitorGates {
    param([string]$RepoRoot)
    $path = Join-Path $RepoRoot 'temp/metrics/gate-executions.jsonl'
    $runs = @{}
    foreach ($line in @(Read-DevMonitorTailLines -Path $path)) {
        try { $row = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        $runId = [string](Get-DevMonitorProp $row 'runId' 'legacy')
        if (-not $runs.ContainsKey($runId)) { $runs[$runId] = @() }
        $runs[$runId] += $row
    }
    $items = @()
    foreach ($run in $runs.Values) {
        $ordered = @($run | Sort-Object { [string](Get-DevMonitorProp $_ 'timestampUtc' '') })
        $last = $ordered[-1]
        $bad = @($ordered | Where-Object { [string](Get-DevMonitorProp $_ 'status' '') -ne 'PASS' } |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    gate = [string](Get-DevMonitorProp $_ 'gate' '')
                    scope = [string](Get-DevMonitorProp $_ 'scope' 'unknown')
                    count = Get-DevMonitorProp $_ 'findingCount'
                }
            })
        $items += [pscustomobject][ordered]@{
            runner = [string](Get-DevMonitorProp $last 'runner' '')
            runId = [string](Get-DevMonitorProp $last 'runId' '')
            atUtc = [string](Get-DevMonitorProp $last 'timestampUtc' '')
            status = if ($bad.Count -gt 0) { 'FAIL' } else { 'PASS' }
            failures = $bad
        }
    }
    return @($items | Sort-Object atUtc -Descending | Select-Object -First 12)
}

function Get-DevMonitorContextSignals {
    param([string]$RepoRoot)
    $dir = Join-Path $RepoRoot 'temp/context-signal'
    $out = @{}
    if (-not (Test-Path -LiteralPath $dir)) { return $out }
    foreach ($file in @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        $marker = Read-DevMonitorJson -Path $file.FullName
        if ($null -eq $marker) { continue }
        $id = $file.BaseName
        $out[$id] = [pscustomobject][ordered]@{
            band = if (Get-DevMonitorProp $marker 'signalled' $false) { 'over threshold' }
                elseif (Get-DevMonitorProp $marker 'commandDriven' $false) { 'pipeline' }
                else { 'available' }
            overThreshold = [bool](Get-DevMonitorProp $marker 'signalled' $false)
        }
    }
    return $out
}

function Get-DevMonitorWatchdogActions {
    param([string]$RepoRoot)
    $path = Join-Path $RepoRoot 'temp/scratch/watchdog/watchdog.log'
    $out = @()
    foreach ($line in @(Read-DevMonitorTailLines -Path $path -MaxBytes 65536 | Select-Object -Last 30)) {
        if ($line -notmatch '^(?<at>\S+\s+\S+)\s+(?<action>KILLED|DROPPED|STARTED runner|WOULD KILL|WOULD DROP|WOULD START|FAILED)\s+(?<detail>.+)$') { continue }
        $out += [pscustomobject][ordered]@{ at = $Matches.at; action = $Matches.action; detail = $Matches.detail }
    }
    return @($out | Select-Object -Last 12)
}

function Get-DevMonitorProp {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

function Get-DevMonitorTicketLastWrite {
    <#
        The newest file a ticket wrote: its spec and tactical folder under PLAN/, its scratch dir under
        temp/. The lease heartbeat is deliberately not counted - it proves the process is scheduled,
        only a file it wrote proves it is working.
    #>
    param([string]$RepoRoot, [string]$Id)
    if ($Id -notmatch '^S\d{4}$') { return $null }
    $files = @()
    $planDir = Join-Path $RepoRoot 'PLAN'
    if (Test-Path -LiteralPath $planDir) {
        # Two passes on purpose: -Filter applies at every level of -Recurse, so one recursive call
        # filtered by the id prefix would miss INDEX.md and the phase files inside the folder.
        foreach ($top in @(Get-ChildItem -LiteralPath $planDir -Filter ($Id + '_*') -ErrorAction SilentlyContinue)) {
            if ($top.PSIsContainer) { $files += @(Get-ChildItem -LiteralPath $top.FullName -Recurse -File -ErrorAction SilentlyContinue) }
            else { $files += $top }
        }
    }
    $scratch = Join-Path (Join-Path $RepoRoot (Get-SzaPath 'tempDir' -Relative)) $Id
    if (Test-Path -LiteralPath $scratch) {
        $files += @(Get-ChildItem -LiteralPath $scratch -Recurse -File -ErrorAction SilentlyContinue)
    }
    if ($files.Count -eq 0) { return $null }
    $newest = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    return [pscustomobject]@{
        Minutes = [math]::Round(((Get-Date) - $newest.LastWriteTime).TotalMinutes, 1)
        Path    = Get-DevMonitorRelativePath -RepoRoot $RepoRoot -Path $newest.FullName
    }
}

function Get-DevMonitorLeaseFiles {
    param([string]$RepoRoot)
    $dir = (Join-Path $RepoRoot (Get-SzaPath 'leasesDir' -Relative))
    $out = @()
    if (-not (Test-Path -LiteralPath $dir)) { return $out }
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $lease = Read-DevMonitorJson -Path $f.FullName
        if ($null -eq $lease) { continue }
        $claimed = ConvertFrom-DevMonitorEpoch (Get-DevMonitorProp $lease 'claimedAt')
        $out += [pscustomobject][ordered]@{
            id              = [string](Get-DevMonitorProp $lease 'id' $f.BaseName)
            sessionId       = [string](Get-DevMonitorProp $lease 'sessionId' '')
            name            = ''
            reason          = [string](Get-DevMonitorProp $lease 'reason' '')
            host            = [string](Get-DevMonitorProp $lease 'host' '')
            pid             = Get-DevMonitorProp $lease 'pid'
            claimedAtUtc    = ConvertTo-DevMonitorUtcText $claimed
            ageMinutes      = Get-DevMonitorMinutesSince $claimed
            lastSeenMinutes = $null
            liveness        = 'unknown'
            transcriptPath  = [string](Get-DevMonitorProp $lease 'transcriptPath' '')
            lastSeenAt      = Get-DevMonitorProp $lease 'lastSeenAt'
        }
    }
    return $out
}

function Get-DevMonitorQueueTickets {
    param([string]$RepoRoot, [string]$Domain)
    $tickets = @()
    $dirs = @((Join-Path (Join-Path $RepoRoot (Get-SzaPath 'locksDir' -Relative)) "$($Domain.ToUpper()).QUEUE"))
    try { $dirs += (Join-Path (Join-Path $RepoRoot (Get-SzaPath 'locksDir' -Relative)) ((Get-AgentLockLegacyName -Name $Domain).ToUpper() + '.QUEUE')) } catch { }
    foreach ($dir in $dirs) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -ErrorAction SilentlyContinue)) {
            $t = Read-DevMonitorJson -Path $file.FullName
            if ($null -eq $t) { continue }
            $enq = ConvertFrom-DevMonitorEpoch (Get-DevMonitorProp $t 'enqueuedAt')
            $seen = ConvertFrom-DevMonitorEpoch (Get-DevMonitorProp $t 'lastSeenAt')
            $tickets += [pscustomobject][ordered]@{
                seq             = [int](Get-DevMonitorProp $t 'seq' 0)
                sessionId       = [string](Get-DevMonitorProp $t 'sessionId' '')
                name            = ''
                reason          = [string](Get-DevMonitorProp $t 'reason' '')
                waitedMinutes   = Get-DevMonitorMinutesSince $enq
                lastSeenMinutes = Get-DevMonitorMinutesSince $seen
            }
        }
    }
    return @($tickets | Sort-Object seq)
}

function Get-DevMonitorLocks {
    param([string]$RepoRoot)
    $out = @()
    $rows = @()
    foreach ($d in @(Get-AgentLockDomainTable)) { $rows += [pscustomobject]@{ Domain = $d.Domain; Legacy = $false } }
    # The pre-split files still hold every domain of their type until their owner releases them.
    foreach ($legacy in @('Build', 'Code')) {
        if (Test-Path -LiteralPath (Join-Path (Join-Path $RepoRoot (Get-SzaPath 'locksDir' -Relative)) "$($legacy.ToUpper()).LOCK")) {
            $rows += [pscustomobject]@{ Domain = $legacy; Legacy = $true }
        }
    }
    foreach ($r in $rows) {
        $lockPath = Join-Path (Join-Path $RepoRoot (Get-SzaPath 'locksDir' -Relative)) "$($r.Domain.ToUpper()).LOCK"
        $held = Test-Path -LiteralPath $lockPath
        $body = if ($held) { Read-DevMonitorJson -Path $lockPath } else { $null }
        $acquired = ConvertFrom-DevMonitorEpoch (Get-DevMonitorProp $body 'acquiredAt')
        $queue = if ($r.Legacy) { @() } else { @(Get-DevMonitorQueueTickets -RepoRoot $RepoRoot -Domain $r.Domain) }
        $out += [pscustomobject][ordered]@{
            domain        = $r.Domain
            legacy        = $r.Legacy
            held          = $held
            unreadable    = ($held -and $null -eq $body)
            reason        = [string](Get-DevMonitorProp $body 'reason' '')
            sessionId     = [string](Get-DevMonitorProp $body 'sessionId' '')
            name          = ''
            host          = [string](Get-DevMonitorProp $body 'host' '')
            pid           = Get-DevMonitorProp $body 'pid'
            acquiredAtUtc = ConvertTo-DevMonitorUtcText $acquired
            heldMinutes   = Get-DevMonitorMinutesSince $acquired
            # Transport only, stripped before the snapshot is returned: the stall predicate needs
            # the path the holder stamped at acquire time, and resolving it again would walk the
            # whole projects tree once per domain (S2413).
            transcriptPath = [string](Get-DevMonitorProp $body 'transcriptPath' '')
            queue         = $queue
        }
    }
    return $out
}

function Get-DevMonitorInstances {
    param([string]$RepoRoot, [int]$Tail)
    $out = @()
    $runDir = (Join-Path $RepoRoot (Get-SzaPath 'queueRunsDir' -Relative))
    if (-not (Test-Path -LiteralPath $runDir)) { return $out }
    foreach ($j in @(Get-ChildItem -LiteralPath $runDir -Filter 'runs-*.jsonl' -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $lines = @(Read-DevMonitorTailLines -Path $j.FullName)
        # Counts by regex, rows by parse: parsing three hundred rows to show five costs more than
        # the rest of the snapshot together.
        $moved = @($lines | Where-Object { $_ -match '"moved"\s*:\s*true' }).Count
        $rows = @()
        foreach ($line in @($lines | Select-Object -Last $Tail)) {
            try { $r = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            $rows += [pscustomobject][ordered]@{
                id           = [string](Get-DevMonitorProp $r 'id' '')
                statusBefore = [string](Get-DevMonitorProp $r 'statusBefore' '')
                statusAfter  = [string](Get-DevMonitorProp $r 'statusAfter' '')
                moved        = [bool](Get-DevMonitorProp $r 'moved' $false)
                outcome      = [string](Get-DevMonitorProp $r 'outcome' '')
                exitCode     = Get-DevMonitorProp $r 'exitCode'
                minutes      = Get-DevMonitorProp $r 'minutes'
                model        = [string](Get-DevMonitorProp $r 'model' '')
                finishedAt   = [string](Get-DevMonitorProp $r 'finishedAt' '')
            }
        }
        $out += [pscustomobject][ordered]@{
            instance = ($j.BaseName -replace '^runs-', '')
            recorded = $lines.Count
            moved    = $moved
            stayed   = ($lines.Count - $moved)
            idleToday = @($rows | Where-Object { -not $_.moved }).Count
            idleMinutesToday = [math]::Round((@($rows | Where-Object { -not $_.moved } | Measure-Object -Property minutes -Sum).Sum), 1)
            timeoutsToday = @($rows | Where-Object { $_.outcome -eq 'timeout' }).Count
            cheapModelShare = if ($rows.Count -gt 0) {
                [math]::Round((@($rows | Where-Object { $_.model -and $_.model -notmatch 'opus' }).Count / $rows.Count) * 100, 1)
            } else { $null }
            rows     = $rows
        }
    }
    return $out
}

function Get-DevMonitorStopFlags {
    param([string]$RepoRoot)
    $out = @()
    $tempDir = (Join-Path $RepoRoot (Get-SzaPath 'tempDir' -Relative))
    if (-not (Test-Path -LiteralPath $tempDir)) { return $out }
    $stopFlag = Join-Path $RepoRoot (Get-SzaPath 'queueStopFile' -Relative)
    foreach ($f in @(Get-ChildItem -LiteralPath (Split-Path $stopFlag -Parent) -Filter ((Split-Path $stopFlag -Leaf) + '*') -File -ErrorAction SilentlyContinue)) {
        $out += [pscustomobject][ordered]@{
            name             = $f.Name
            requestedMinutes = [math]::Round(((Get-Date) - $f.LastWriteTime).TotalMinutes, 1)
        }
    }
    return $out
}

function Get-DevMonitorChildren {
    param([string]$RepoRoot)
    $out = @()
    $procs = @()
    try {
        $procs = @((Get-SzaAgentProcesses) |
                Where-Object { $_.CommandLine -and $_.CommandLine -match '\s-p\s' })
    } catch { $procs = @() }
    foreach ($c in $procs) {
        $started = $null
        try { $started = $c.CreationDate } catch { $started = $null }
        $ageMinutes = if ($started) { [math]::Round(((Get-Date) - $started).TotalMinutes, 1) } else { $null }
        $ticket = if ($c.CommandLine -match '(S\d{4})') { $Matches[1] } else { '?' }
        $model = if ($c.CommandLine -match '--model\s+(\S+)') { $Matches[1] } else { 'default' }
        $write = Get-DevMonitorTicketLastWrite -RepoRoot $RepoRoot -Id $ticket
        # Judge the silence against this run's own age, never against the file's absolute date: a
        # five-minute-old child cannot have been quiet for longer than five minutes.
        $quiet = if ($null -eq $write) { $ageMinutes }
            elseif ($null -eq $ageMinutes) { $write.Minutes }
            else { [math]::Min($write.Minutes, $ageMinutes) }
        $out += [pscustomobject][ordered]@{
            pid              = $c.ProcessId
            ticket           = $ticket
            model            = $model
            ageMinutes       = $ageMinutes
            lastWriteMinutes = if ($null -ne $write) { $write.Minutes } else { $null }
            lastWritePath    = if ($null -ne $write) { $write.Path } else { $null }
            writeBeforeStart = ($null -ne $write -and $null -ne $ageMinutes -and $write.Minutes -gt ($ageMinutes + 1))
            quietMinutes     = $quiet
        }
    }
    return $out
}

function Get-DevMonitorNextUp {
    <#
        The current package of PLAN/RELEASE_QUEUE.md in file order - the file IS the execution order
        (CLAUDE.md section 4); the ranker only skips leased, blocked and skip-cached rows, and the first
        two of those are visible on the row itself.
    #>
    param([string]$RepoRoot, [int]$NextUp)
    $result = [pscustomobject][ordered]@{ package = $null; rows = @(); totalInPackage = 0 }
    $path = (Join-Path $RepoRoot (Get-SzaPath 'releaseQueue' -Relative))
    if (-not (Test-Path -LiteralPath $path)) { return $result }
    $lines = @()
    try { $lines = @(Get-Content -LiteralPath $path -ErrorAction Stop) } catch { return $result }
    $package = $null
    foreach ($line in $lines) {
        if ($line -match '^current-next-release:\s*(\S+)') { $package = $Matches[1]; break }
    }
    $result.package = $package
    if ($null -eq $package) { return $result }
    $rows = @()
    $inPackage = $false
    $total = 0
    # S2852: the package lives in a section heading, not in a column on the row, so this parser
    # tracks the heading the way the file reads. The pre-S2852 shape - a leading package column, a
    # date with no time - still parses, so a stale copy of the file is read rather than reported
    # as an empty package.
    $section = $null
    $changedPattern = '(\d{4}-\d{2}-\d{2}(?: \d{2}:\d{2})?|\d{2}-\d{2}-\d{2}(?: \d{2}:\d{2})?)'
    $markerPattern = '(?:\s+\[taken ([^\]]+)\])?(?:\s+\[idle (\d+), ([^\]]+)\])?'
    foreach ($line in $lines) {
        if ($line -match '^\s*(\d+|--)\s*$') { $section = $Matches[1]; continue }
        $rel = $null
        if ($line -match ('^(S(\d{4}))_(\S+)\s+' + $changedPattern + '\s+(\S+)' + $markerPattern)) {
            $rel = $section
            $id = $Matches[1]; $slug = $Matches[3]; $changed = $Matches[4]; $status = $Matches[5]
            $takenRaw = $Matches[6]; $idleCountRaw = $Matches[7]; $idleOutcomeRaw = $Matches[8]
        } elseif ($line -match ('^(\d+|--)\s+(S\d{4})_(\S+)\s+' + $changedPattern + '\s+(\S+)' + $markerPattern)) {
            $rel = $Matches[1]
            $id = $Matches[2]; $slug = $Matches[3]; $changed = $Matches[4]; $status = $Matches[5]
            $takenRaw = $Matches[6]; $idleCountRaw = $Matches[7]; $idleOutcomeRaw = $Matches[8]
        }
        if ($null -ne $rel) {
            if ($rel -ne $package) { $inPackage = $false; continue }
            $inPackage = $true
            $total++
            if ($rows.Count -ge $NextUp -and $NextUp -gt 0) { continue }
            $taken = if ($takenRaw) { $takenRaw } else { $null }
            $rows += [pscustomobject][ordered]@{
                kind    = 'row'
                rel     = $rel
                id      = $id
                slug    = $slug
                changed = $changed
                status  = $status
                taken   = $taken
                leased  = ($null -ne $taken)
                blocked = ($status -like 'Block*')
                idleCount = if ($idleCountRaw) { [int]$idleCountRaw } else { $null }
                idleOutcome = if ($idleOutcomeRaw) { $idleOutcomeRaw } else { $null }
            }
            continue
        }
        # A package sub-heading (`# 36.0 ..`) keeps the order readable the way the file reads.
        if ($line -match "^#\s+$([regex]::Escape($package))\.\d+\s+(.*)$") {
            $inPackage = $true
            if ($rows.Count -ge $NextUp -and $NextUp -gt 0) { continue }
            $rows += [pscustomobject][ordered]@{ kind = 'group'; text = ("{0}.{1}" -f $package, ($line -replace "^#\s+$([regex]::Escape($package))\.", '')) }
        }
    }
    $result.rows = $rows
    $result.totalInPackage = $total
    return $result
}

function Get-DevMonitorSnapshot {
    <#
    .SYNOPSIS
        The whole picture as one object (schema 1). See the file header for the sources.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        # Finished tickets per instance.
        [int]$Tail = 5,
        # Rows of the current package shown under next-up (0 = all).
        [int]$NextUp = 25,
        # Newest progress messages kept in the chat tail.
        [int]$ChatTail = 40
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path.TrimEnd('\', '/')

    $timings = [ordered]@{}
    $measure = {
        param([string]$Name, [scriptblock]$Read)
        $part = [System.Diagnostics.Stopwatch]::StartNew()
        $value = & $Read
        $part.Stop()
        $timings[$Name] = [int]$part.ElapsedMilliseconds
        return $value
    }
    $leases = @(& $measure 'leases' { Get-DevMonitorLeaseFiles -RepoRoot $RepoRoot })
    $locks = @(& $measure 'locks' { Get-DevMonitorLocks -RepoRoot $RepoRoot })
    $instances = @(& $measure 'runner' { Get-DevMonitorInstances -RepoRoot $RepoRoot -Tail $Tail })
    $gates = @(& $measure 'gates' { Get-DevMonitorGates -RepoRoot $RepoRoot })
    $contexts = & $measure 'context' { Get-DevMonitorContextSignals -RepoRoot $RepoRoot }
    $watchdog = @(& $measure 'watchdog' { Get-DevMonitorWatchdogActions -RepoRoot $RepoRoot })
    $stop = @(& $measure 'stop' { Get-DevMonitorStopFlags -RepoRoot $RepoRoot })
    $children = @(& $measure 'children' { Get-DevMonitorChildren -RepoRoot $RepoRoot })
    # Not `$nextUp`: PowerShell names are case-insensitive, so that would be the [int] parameter.
    $queueRows = & $measure 'queue' { Get-DevMonitorNextUp -RepoRoot $RepoRoot -NextUp $NextUp }

    # Everything that needs the lock library runs inside one scriptblock: its strict mode and its
    # timings stay out of the caller's scope (the pattern the terminal monitor used for the chat).
    $lockLib = (Get-SzaHarnessScript 'locks/agent-lock.ps1')
    $chat = $null
    try {
        $chat = & {
            param($LockLib, $Leases, $Locks, $ChatTail)
            Set-StrictMode -Off
            $ErrorActionPreference = 'Continue'
            . $LockLib
            $timings = Get-AgentLockTimings -Name SpecTicket
            $w = Get-AgentChatWindows
            $messages = @(Get-AgentChatMessages -Stream progress -Last 0 -NoSweep)

            # Nicknames: the name a message carries first (an FMS_AGENT_NAME override never reaches the
            # registry), then the registry, then the id's first eight characters - the last one is
            # never cached, so a lease read before the agent's message cannot pin the fallback.
            $names = @{}
            foreach ($m in $messages) {
                $agent = Get-AgentChatProp $m 'agent'
                $id = [string](Get-AgentChatProp $agent 'id' '')
                $n = [string](Get-AgentChatProp $agent 'name' '')
                if ($id -and $n -and -not $names.ContainsKey($id)) { $names[$id] = $n }
            }
            $nameOf = {
                param($Id, $Agent)
                if ([string]::IsNullOrWhiteSpace($Id)) { return '' }
                if ($names.ContainsKey($Id)) { return $names[$Id] }
                $n = [string](Get-AgentChatProp $Agent 'name' '')
                if (-not $n) { try { $n = [string](Get-AgentNickname -Id $Id -NoCreate) } catch { $n = '' } }
                if ($n) { $names[$Id] = $n; return $n }
                if ($Id.Length -gt 8) { return $Id.Substring(0, 8) }
                return $Id
            }

            foreach ($l in $Leases) {
                $shim = [pscustomobject]@{ sessionId = $l.sessionId; transcriptPath = $l.transcriptPath; lastSeenAt = $l.lastSeenAt; enqueuedAt = $null }
                $verdict = 'unknown'
                try { $verdict = [string](Get-AgentTicketLiveness -Ticket $shim -StaleMinutes $timings.SessionStaleMinutes) } catch { $verdict = 'unknown' }
                $l.liveness = $verdict
                $l.name = & $nameOf $l.sessionId $null
                # S2413: the quiet time goes through the lock library's own helper, so this page and
                # the eviction that reads the same marks cannot disagree about one holder. The
                # hand-rolled copy of the loop that stood here counted a transcript write without
                # the subagent subtree, and so read a session working through a subagent as quiet.
                $quiet = Get-AgentOwnerQuietMinutes -SessionId $l.sessionId -TranscriptPath $l.transcriptPath -LastSeenAt $l.lastSeenAt
                if ($null -ne $quiet) { $l.lastSeenMinutes = $quiet }
            }
            $stalls = @()
            foreach ($k in $Locks) {
                if ($k.sessionId) { $k.name = & $nameOf $k.sessionId $null }
                foreach ($q in @($k.queue)) { if ($q.sessionId) { $q.name = & $nameOf $q.sessionId $null } }
                # Computed from the locks already read - the snapshot reads every lock file once and
                # the predicate must not read them a second time.
                if (-not $k.held -or $k.legacy -or -not $k.sessionId) { continue }
                $stall = $null
                try {
                    # S2582: the pid goes in for the same reason the session id does - the build rule
                    # judges the holder PROCESS, and without it the predicate would re-read the lock
                    # file this loop has already read.
                    $stall = Get-AgentLockStall -Name $k.domain -HolderSessionId $k.sessionId `
                        -HolderTranscriptPath $k.transcriptPath -HeldMinutes $k.heldMinutes `
                        -HolderPid ([int]$(if ($null -eq $k.pid) { 0 } else { $k.pid })) -Queue @($k.queue)
                }
                catch { $stall = $null }
                if ($null -ne $stall) {
                    $stall | Add-Member -NotePropertyName 'name' -NotePropertyValue $k.name -Force
                    $stall | Add-Member -NotePropertyName 'reason' -NotePropertyValue $k.reason -Force
                    $stalls += $stall
                }
            }

            $seenAgents = [ordered]@{}
            $phaseOf = @{}
            foreach ($m in $messages) {
                $agent = Get-AgentChatProp $m 'agent'
                $id = [string](Get-AgentChatProp $agent 'id' '?')
                if (-not $seenAgents.Contains($id)) { $seenAgents[$id] = $m }
                if (-not $phaseOf.ContainsKey($id) -and [string](Get-AgentChatProp $m 'kind' '') -eq 'phase') { $phaseOf[$id] = $m }
            }
            $agents = @()
            foreach ($id in $seenAgents.Keys) {
                $m = $seenAgents[$id]
                $agent = Get-AgentChatProp $m 'agent'
                $ph = if ($phaseOf.ContainsKey($id)) { $phaseOf[$id] } else { $null }
                $leaseId = $null
                foreach ($l in $Leases) { if ($l.sessionId -eq $id) { $leaseId = $l.id; break } }
                $age = [double](Get-AgentChatProp $m 'ageMinutes' 0)
                $agents += [pscustomobject][ordered]@{
                    id              = $id
                    name            = & $nameOf $id $agent
                    runtime         = [string](Get-AgentChatProp $agent 'runtime' 'unknown')
                    model           = [string](Get-AgentChatProp $agent 'model' 'unknown')
                    instance        = [string](Get-AgentChatProp $agent 'instance' '-')
                    host            = [string](Get-AgentChatProp $agent 'host' '')
                    ageMinutes      = $age
                    silent          = ($age -gt $w.SilentMinutes)
                    lastKind        = [string](Get-AgentChatProp $m 'kind' '')
                    lastTicket      = [string](Get-AgentChatProp $m 'ticket' '')
                    lastNote        = [string](Get-AgentChatProp $m 'note' '')
                    lease           = $leaseId
                    phaseTicket     = if ($ph) { [string](Get-AgentChatProp $ph 'ticket' '') } else { $null }
                    phase           = if ($ph) { [string](Get-AgentChatProp $ph 'phase' '') } else { $null }
                    phaseNote       = if ($ph) { [string](Get-AgentChatProp $ph 'note' '') } else { $null }
                    phaseAgeMinutes = if ($ph) { [double](Get-AgentChatProp $ph 'ageMinutes' 0) } else { $null }
                    contextBand     = if ($contexts.ContainsKey($id)) { $contexts[$id].band } else { $null }
                    contextOverThreshold = if ($contexts.ContainsKey($id)) { $contexts[$id].overThreshold } else { $false }
                }
            }
            $agents = @($agents | Sort-Object ageMinutes)

            # `children` below is deliberately process-shaped: it answers whether a `claude -p`
            # process exists. RUNNING needs the other view as well: the original agent sessions
            # that own live leases, regardless of runtime, plus a fresh session that has no ticket
            # yet. Do not infer a root session from a pid-* chat record: hookless runtimes can mint
            # one such identity per tool call, and presenting those as independent sessions would
            # recreate the exact monitor confusion this field removes.
            $sessionsById = [ordered]@{}
            foreach ($l in $Leases) {
                if ($l.liveness -ne 'foreign-live' -or [string]::IsNullOrWhiteSpace($l.sessionId)) { continue }
                # A pid-* identity belongs to one short-lived tool process. Its heartbeat can remain
                # inside the lease grace window after that process is gone, which says "not stale"
                # for arbitration but must not say "running" in the monitor. Stable session ids are
                # still judged by the lease liveness contract above.
                if ($l.sessionId -match '^pid-' -and -not (Test-AgentIdentityProcessAlive -Id $l.sessionId)) { continue }
                $agent = @($agents | Where-Object { $_.id -eq $l.sessionId } | Select-Object -First 1)[0]
                $sessionsById[$l.sessionId] = [pscustomobject][ordered]@{
                    id         = $l.sessionId
                    name       = $l.name
                    runtime    = if ($agent) { $agent.runtime } else { 'unknown' }
                    ticket     = $l.id
                    ageMinutes = $l.lastSeenMinutes
                    source     = 'live lease'
                }
            }
            foreach ($agent in $agents) {
                if ($agent.silent -or $agent.lastKind -ne 'session' -or $agent.lastNote -match '^session ended') { continue }
                if ($agent.id -match '^pid-') { continue }
                if ($sessionsById.Contains($agent.id)) { continue }
                $sessionsById[$agent.id] = [pscustomobject][ordered]@{
                    id         = $agent.id
                    name       = $agent.name
                    runtime    = $agent.runtime
                    ticket     = ''
                    ageMinutes = $agent.ageMinutes
                    source     = 'session heartbeat'
                }
            }
            $sessions = @($sessionsById.Values | Sort-Object ageMinutes)

            $tail = @()
            foreach ($m in @($messages | Select-Object -First $ChatTail)) {
                $agent = Get-AgentChatProp $m 'agent'
                $id = [string](Get-AgentChatProp $agent 'id' '?')
                $tail += [pscustomobject][ordered]@{
                    atUtc      = ([DateTime](Get-AgentChatProp $m 'atUtc' ([DateTime]::UtcNow))).ToString('o')
                    ageMinutes = [double](Get-AgentChatProp $m 'ageMinutes' 0)
                    kind       = [string](Get-AgentChatProp $m 'kind' '')
                    name       = & $nameOf $id $agent
                    ticket     = [string](Get-AgentChatProp $m 'ticket' '')
                    phase      = [string](Get-AgentChatProp $m 'phase' '')
                    note       = [string](Get-AgentChatProp $m 'note' '')
                }
            }

            $alive = @()
            $dead = 0
            $deadReasons = [pscustomobject][ordered]@{
                expired      = 0
                scopeChanged = 0
                deviceGone   = 0
                unreadable   = 0
            }
            $scopeCache = @{}
            foreach ($f in @(Get-AgentChatMessages -Stream finding -Last 0 -NoSweep)) {
                $verdict = $null
                try { $verdict = Test-AgentChatFindingAlive -Finding $f -ScopeCache $scopeCache } catch { $verdict = $null }
                if ($null -eq $verdict -or -not $verdict.Alive) {
                    $dead++
                    $reason = if ($null -eq $verdict) { 'unreadable' } else { [string]$verdict.Reason }
                    if ($reason -eq 'expired' -or $reason -like 'unreadable*') { $deadReasons.expired++ }
                    elseif ($reason -like 'scope changed*' -or $reason -like 'scope path gone*') { $deadReasons.scopeChanged++ }
                    elseif ($reason -like 'device not listed*' -or $reason -like 'adb not found*') { $deadReasons.deviceGone++ }
                    else { $deadReasons.unreadable++ }
                    continue
                }
                $agent = Get-AgentChatProp $f 'agent'
                $id = [string](Get-AgentChatProp $agent 'id' '?')
                $alive += [pscustomobject][ordered]@{
                    topic      = [string](Get-AgentChatProp $f 'topic' '')
                    kind       = [string](Get-AgentChatProp $f 'kind' '')
                    name       = & $nameOf $id $agent
                    atUtc      = ([DateTime](Get-AgentChatProp $f 'atUtc' ([DateTime]::UtcNow))).ToString('o')
                    ageMinutes = [double](Get-AgentChatProp $f 'ageMinutes' 0)
                    expiresAt  = [string](Get-AgentChatProp $f 'expiresAt' '')
                    scopeCount = @(Get-AgentChatProp $f 'scope' @()).Count
                    device     = [string](Get-AgentChatProp $f 'device' '')
                    note       = [string](Get-AgentChatProp $f 'note' '')
                }
            }

            [pscustomobject]@{
                Windows     = [pscustomobject][ordered]@{
                    silentMinutes    = [int]$w.SilentMinutes
                    retentionMinutes = [int]$w.ProgressRetentionMinutes
                    staleMinutes     = [int]$timings.SessionStaleMinutes
                    ceilingMinutes   = [int]$timings.TicketCeilingMinutes
                }
                Agents      = $agents
                Sessions    = $sessions
                Stalls      = $stalls
                Tail        = $tail
                Findings    = $alive
                Dead        = $dead
                DeadReasons = $deadReasons
                Error       = $null
            }
        } $lockLib $leases $locks $ChatTail
    } catch {
        $chat = [pscustomobject]@{ Windows = $null; Agents = @(); Sessions = @(); Stalls = @(); Tail = @(); Findings = @(); Dead = 0; DeadReasons = $null; Error = "$_" }
    }

    # The transport fields of a lease are not for display.
    foreach ($l in $leases) { $l.PSObject.Properties.Remove('transcriptPath'); $l.PSObject.Properties.Remove('lastSeenAt') }
    foreach ($k in $locks) { $k.PSObject.Properties.Remove('transcriptPath') }

    $sw.Stop()
    $now = Get-Date
    return [pscustomobject][ordered]@{
        schema              = 1
        takenAtUtc          = $now.ToUniversalTime().ToString('o')
        takenAtLocal        = $now.ToString('yyyy-MM-dd HH:mm:ss')
        host                = $env:COMPUTERNAME
        repoRoot            = $RepoRoot.Replace('\', '/')
        durationMs          = [int]$sw.ElapsedMilliseconds
        timings             = [pscustomobject]$timings
        chatError           = $chat.Error
        windows             = $chat.Windows
        leases              = $leases
        locks               = $locks
        # Additive, so the schema stays 1: a reader that does not know the field is unaffected, and
        # every reader that does draws the same verdict rather than deriving its own (S2413).
        stalls              = @($chat.Stalls)
        agents              = @($chat.Agents)
        sessions            = @($chat.Sessions)
        chat                = @($chat.Tail)
        findings            = @($chat.Findings)
        findingsDead        = [int]$chat.Dead
        findingsDeadReasons = $chat.DeadReasons
        instances           = $instances
        gates               = $gates
        watchdog            = $watchdog
        stop                = $stop
        children            = $children
        nextUp              = $queueRows
    }
}
