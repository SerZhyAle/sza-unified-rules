# Telemetry analysis of the portfolio (TASK-FLOW rules 53-59; S0016 R44-R48, METRICS.md), the lean form: read-only views
# computed on demand from the run rows (<root>\runs.jsonl) and the event files, no state of their own.
#
# Dot-source this file after events.ps1 and registry.ps1; it defines functions only, sets no preference and prints nothing.
#
#   Get-PqWindow -Days <n>              @{ since; until; days } - the last n local days (n >= 1), ending now.
#   Read-PqRuns -Root -Since            the run rows (runs.jsonl) finished at or after Since, as objects.
#   Read-PqWindowEvents -Root -Since    @{ events; bad; unsupported; gaps } merged over the UTC days the window touches, the
#                                       events from Since on.
#   Get-PqPercentile -Values -P         the p-th percentile (nearest rank) of numbers, or $null.
#   Get-PqRunStats -Runs                n, moved, ok, minutes p50 and p90 for a group of run rows.
#   Get-PqReport -Root -Days            the report object: headline, outcome mix, splits by agent / model / complexity /
#                                       repository (a split prints only where n >= minSample, METRICS.md), waiting, occupancy,
#                                       resources, stops, intake, telemetry health, findings.
#   Get-PqFindings -Runs -Events -Gaps -Bad
#                                       the open findings of the window, METRICS.md ids, severity first. Each: fid, severity,
#                                       target, text, value, threshold, evidence (event refs, up to 10).
#   Get-PqTrace -Root -Repo -Id         one ticket's events in time order.
#   Compare-PqRuns -Runs -By            the same figures per value of a run-row field, in the order the values first appear, with
#                                       a plain verdict between the last two (better, worse, no evidence).
#   ConvertTo-PqRunCsv -Runs            the run rows as CSV text.
#
# The finding lifecycle events (finding.open, finding.close, finding.escalate) and the tickets of R46 (improve) are not built:
# a finding here is computed from the window each time it is asked for, nothing is filed, nothing is written.

$script:PqMinSample = 5

function Get-PqWindow([int]$Days = 7) {
    if ($Days -lt 1) { $Days = 1 }
    $until = [DateTime]::Now
    return @{ since = $until.AddDays(-$Days); until = $until; days = $Days }
}

function Read-PqRuns {
    param([Parameter(Mandatory)][string]$Root, [datetime]$Since = [datetime]::MinValue)
    $path = Join-Path $Root 'runs.jsonl'
    $rows = [Collections.Generic.List[object]]::new()
    if (-not [IO.File]::Exists($path)) { return @() }
    $stream = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
    try {
        $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8)
        try {
            while ($null -ne ($line = $reader.ReadLine())) {
                if (-not $line.Trim()) { continue }
                try { $row = ConvertFrom-Json -InputObject $line -DateKind String } catch { continue }
                $at = [datetime]::MinValue
                if ([datetime]::TryParse([string](Get-PqValue $row 'finishedAt' ''), [ref]$at) -and $at -lt $Since) { continue }
                $rows.Add($row)
            }
        }
        finally { $reader.Dispose() }
    }
    finally { $stream.Dispose() }
    return @($rows)
}

function Read-PqWindowEvents {
    param([Parameter(Mandatory)][string]$Root, [datetime]$Since = [datetime]::MinValue)
    $result = @{ events = [Collections.Generic.List[object]]::new(); bad = 0; unsupported = 0; gaps = [Collections.Generic.List[object]]::new() }
    $logDir = Join-Path $Root 'log'
    if (-not [IO.Directory]::Exists($logDir)) { return $result }
    $sinceUtc = $Since.ToUniversalTime()
    $dates = [Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    foreach ($f in [IO.Directory]::GetFiles($logDir, 'events-*.jsonl')) {
        if ([IO.Path]::GetFileName($f) -match '^events-(\d{4}-\d{2}-\d{2})\.') { [void]$dates.Add($Matches[1]) }
    }
    foreach ($d in $dates) {
        $day = [datetime]::ParseExact($d, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).AddDays(1)
        if ($day -le $sinceUtc.Date) { continue }
        $m = Merge-PqDay -Root $Root -Date $d
        $result.bad += $m.bad
        $result.unsupported += $m.unsupported
        foreach ($g in $m.gaps) { $result.gaps.Add($g) }
        foreach ($e in $m.events) {
            $at = [datetime]::MinValue
            if ($Since -gt [datetime]::MinValue -and [datetime]::TryParse([string]$e.ts, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$at) -and $at -lt $sinceUtc) { continue }
            $result.events.Add($e)
        }
    }
    return $result
}

function Get-PqPercentile {
    param([double[]]$Values, [double]$P)
    $v = @($Values | Sort-Object)
    if ($v.Count -eq 0) { return $null }
    $rank = [int][Math]::Ceiling($P / 100.0 * $v.Count)
    return $v[[Math]::Min($v.Count, [Math]::Max(1, $rank)) - 1]
}

function Get-PqRunStats($Runs) {
    $rows = @($Runs)
    $moved = @($rows | Where-Object { (Get-PqValue $_ 'moved' $false) -eq $true }).Count
    $ok = @($rows | Where-Object { (Get-PqValue $_ 'outcome' '') -ceq 'ok' }).Count
    $mins = @($rows | ForEach-Object { [double](Get-PqValue $_ 'minutes' 0) })
    return [ordered]@{
        n = $rows.Count; moved = $moved; ok = $ok
        movedShare = $(if ($rows.Count) { [Math]::Round(100.0 * $moved / $rows.Count, 1) } else { $null })
        okShare = $(if ($rows.Count) { [Math]::Round(100.0 * $ok / $rows.Count, 1) } else { $null })
        minutesP50 = (Get-PqPercentile $mins 50); minutesP90 = (Get-PqPercentile $mins 90)
    }
}

function Group-PqRunsBy($Runs, [string]$Field) {
    $groups = [ordered]@{}
    foreach ($r in @($Runs)) {
        $k = [string](Get-PqValue $r $Field '')
        if (-not $k) { $k = '(none)' }
        if (-not $groups.Contains($k)) { $groups[$k] = [Collections.Generic.List[object]]::new() }
        $groups[$k].Add($r)
    }
    return $groups
}

function Get-PqEventRef($E) { return ('{0}#{1}' -f $E.ev, $E.seq) + $(if ($E.wr) { "@$($E.wr)" } else { '' }) }

function Get-PqFindings {
    param($Runs, $Events, $Gaps, [int]$Bad = 0)
    $runs = @($Runs)
    $events = @($Events)
    $out = [Collections.Generic.List[object]]::new()
    $add = {
        param($fid, $sev, $target, $text, $value, $threshold, $evidence)
        $out.Add([ordered]@{ fid = $fid; severity = $sev; target = $target; text = $text; value = $value; threshold = $threshold; evidence = @($evidence | Select-Object -First 10) })
    }
    $of = { param($name) @($events | Where-Object { $_.ev -ceq $name }) }

    # PQ-RACE01: a claim lost, or a pass the runner could not claim.
    $lost = @(& $of 'claim.lost') + @($runs | Where-Object { (Get-PqValue $_ 'outcome' '') -cin @('claim-lost', 'claim-lost-before-launch') })
    if ($lost.Count -gt 0) { & $add 'PQ-RACE01' 'high' 'runner' "$($lost.Count) claim(s) lost: two workers reached one ticket" $lost.Count 1 @(@(& $of 'claim.lost') | ForEach-Object { Get-PqEventRef $_ }) }

    # PQ-SAFE02: the cap of robot-filed tickets was reached.
    $capped = @(& $of 'intake.robotDraft' | Where-Object { (Get-PqValue $_.d 'capped' $false) -eq $true })
    if ($capped.Count -gt 0) { & $add 'PQ-SAFE02' 'low' 'owner' "the cap of robot-filed tickets was reached $($capped.Count) time(s)" $capped.Count 1 @($capped | ForEach-Object { Get-PqEventRef $_ }) }

    # PQ-SAFE01: a tripwire trip.
    $trips = @(& $of 'tripwire.trip')
    if ($trips.Count -gt 0) { & $add 'PQ-SAFE01' 'high' 'runner' "$($trips.Count) tripwire trip(s)" $trips.Count 1 @($trips | ForEach-Object { Get-PqEventRef $_ }) }

    # PQ-LIMIT01: a usage limit with no reset time, or a detector that fired while unproven.
    $holds = @(& $of 'agent.hold' | Where-Object { -not (Get-PqValue $_.d 'until') -or (Get-PqValue $_.d 'detector' '') -ceq 'unproven' })
    if ($holds.Count -gt 0) { & $add 'PQ-LIMIT01' 'medium' 'profile' "$($holds.Count) limit hold(s) with no reset time or from an unproven detector" $holds.Count 1 @($holds | ForEach-Object { Get-PqEventRef $_ }) }

    # PQ-THRASH01: a ticket offered four or more times in the window with no net advance, and the loop's own ticket.thrash.
    $thr = @(& $of 'ticket.thrash')
    $byTicket = @{}
    foreach ($r in $runs) { $k = "$(Get-PqValue $r 'repo' ''):$(Get-PqValue $r 'id' '')"; if (-not $byTicket.ContainsKey($k)) { $byTicket[$k] = [Collections.Generic.List[object]]::new() }; $byTicket[$k].Add($r) }
    $stuck = @($byTicket.Keys | Where-Object { $byTicket[$_].Count -ge 4 -and (Get-PqValue $byTicket[$_][0] 'statusBefore' '') -ceq (Get-PqValue $byTicket[$_][$byTicket[$_].Count - 1] 'statusAfter' '') })
    if ($thr.Count -gt 0 -or $stuck.Count -gt 0) {
        & $add 'PQ-THRASH01' 'medium' 'skill' "$($stuck.Count) ticket(s) offered 4+ times with no net advance ($($stuck -join ', ')); $($thr.Count) held back by the loop" ($stuck.Count + $thr.Count) 4 @($thr | ForEach-Object { Get-PqEventRef $_ })
    }

    # PQ-RES03: a ticket that waited for a resource token for half an hour or more.
    $waits = @(& $of 'resource.wait')
    $longWait = @($waits | Group-Object { "$($_.repo):$($_.id)" } | Where-Object {
            $ts = @($_.Group | ForEach-Object { [datetime]::Parse([string]$_.ts, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal) })
            ($ts | Measure-Object -Maximum).Maximum - ($ts | Measure-Object -Minimum).Minimum -ge [timespan]::FromMinutes(30)
        })
    if ($longWait.Count -gt 0) { & $add 'PQ-RES03' 'medium' 'runner' "$($longWait.Count) ticket(s) waited 30+ minutes for a build or emulator token ($(@($longWait | ForEach-Object Name) -join ', '))" $longWait.Count 30 @($waits | ForEach-Object { Get-PqEventRef $_ }) }

    # PQ-STALL01: a pass with no signal for too long.
    $stall = @(& $of 'pass.stall')
    if ($stall.Count -gt 0) { & $add 'PQ-STALL01' 'medium' 'runner' "$($stall.Count) pass(es) went quiet" $stall.Count 1 @($stall | ForEach-Object { Get-PqEventRef $_ }) }

    # PQ-XREPO01: a cycle among cross-repository blockers.
    $cyc = @(& $of 'xrepo.cycle')
    if ($cyc.Count -gt 0) { & $add 'PQ-XREPO01' 'medium' 'owner' "$($cyc.Count) cross-repository blocker cycle(s)" $cyc.Count 1 @($cyc | ForEach-Object { Get-PqEventRef $_ }) }

    # PQ-DATA01: the log itself - a gap in seq, an error, an unparsable line.
    $logErr = @(& $of 'log.error')
    $unexplained = @(@($Gaps) | Where-Object { (Get-PqValue $_ 'explained' $true) -eq $false })
    if ($logErr.Count -gt 0 -or $unexplained.Count -gt 0 -or $Bad -gt 0) {
        & $add 'PQ-DATA01' 'high' 'runner' "log health: $($logErr.Count) log.error, $($unexplained.Count) unexplained seq gap(s), $Bad unparsable line(s)" ($logErr.Count + $unexplained.Count + $Bad) 1 @($logErr | ForEach-Object { Get-PqEventRef $_ })
    }

    # PQ-COST02: `light` that needed 3+ passes in over 30 % of its tickets (at least five tickets).
    $light = @($runs | Where-Object { (Get-PqValue $_ 'complexity' '') -ceq 'light' } | Group-Object { "$(Get-PqValue $_ 'repo' ''):$(Get-PqValue $_ 'id' '')" })
    if ($light.Count -ge $script:PqMinSample) {
        $many = @($light | Where-Object { $_.Count -ge 3 }).Count
        $share = [Math]::Round(100.0 * $many / $light.Count, 1)
        if ($share -gt 30) { & $add 'PQ-COST02' 'medium' 'canon' "$share % of light tickets needed 3+ passes ($many of $($light.Count)): the level is set too low" $share 30 @() }
    }

    # PQ-ADOPT01: a repository whose ok share is 25 points under the portfolio median (n >= 20 in it).
    $byRepo = Group-PqRunsBy $runs 'repo'
    $shares = @($byRepo.Keys | Where-Object { $byRepo[$_].Count -ge 20 } | ForEach-Object { @{ repo = $_; share = (Get-PqRunStats $byRepo[$_]).okShare } })
    if ($shares.Count -ge 2) {
        $median = Get-PqPercentile @($shares | ForEach-Object { [double]$_.share }) 50
        foreach ($s in $shares) {
            if ($median - [double]$s.share -ge 25) { & $add 'PQ-ADOPT01' 'medium' 'canon' "$($s.repo): ok share $($s.share) % against a portfolio median of $median %" $s.share 25 @() }
        }
    }

    $order = @{ high = 0; medium = 1; low = 2 }
    return @($out | Sort-Object { $order[[string]$_.severity] }, { [string]$_.fid })
}

function Get-PqReport {
    param([Parameter(Mandatory)][string]$Root, [int]$Days = 7)
    $w = Get-PqWindow $Days
    $runs = @(Read-PqRuns -Root $Root -Since $w.since)
    $ev = Read-PqWindowEvents -Root $Root -Since $w.since
    $events = @($ev.events)
    $count = { param($name) @($events | Where-Object { $_.ev -ceq $name }).Count }
    $report = [ordered]@{
        window = [ordered]@{ since = $w.since.ToString('s'); until = $w.until.ToString('s'); days = $w.days; minSample = $script:PqMinSample }
        headline = Get-PqRunStats $runs
    }
    $report.headline.hours = [Math]::Round((@($runs | ForEach-Object { [double](Get-PqValue $_ 'minutes' 0) }) | Measure-Object -Sum).Sum / 60.0, 2)
    $outcomes = [ordered]@{}
    foreach ($g in @($runs | Group-Object { [string](Get-PqValue $_ 'outcome' 'unknown') } | Sort-Object Count -Descending)) { $outcomes[$g.Name] = $g.Count }
    $report.outcomes = $outcomes
    foreach ($field in @('agent', 'model', 'complexity', 'repo')) {
        $split = [ordered]@{}
        foreach ($k in @((Group-PqRunsBy $runs $field).Keys)) {
            $rows = @((Group-PqRunsBy $runs $field)[$k])
            $split[$k] = if ($rows.Count -ge $script:PqMinSample) { Get-PqRunStats $rows } else { [ordered]@{ n = $rows.Count; note = 'n too small' } }
        }
        $report["by_$field"] = $split
    }
    $pollSum = @($events | Where-Object { $_.ev -ceq 'poll.summary' })
    $report.waiting = [ordered]@{
        waits = (& $count 'wait.enter'); pollChanges = (& $count 'poll.change')
        polls = [int](($pollSum | ForEach-Object { [int](Get-PqValue $_.d 'polls' 0) } | Measure-Object -Sum).Sum)
        reranks = [int](($pollSum | ForEach-Object { [int](Get-PqValue $_.d 'reranks' 0) } | Measure-Object -Sum).Sum)
        skippedUnchanged = [int](($pollSum | ForEach-Object { [int](Get-PqValue $_.d 'skippedUnchanged' 0) } | Measure-Object -Sum).Sum)
    }
    $occ = [ordered]@{}
    foreach ($g in @($events | Where-Object { $_.ev -ceq 'repo.occupied' } | Group-Object repo)) { $occ[$g.Name] = $g.Count }
    $report.occupied = $occ
    $report.resources = [ordered]@{ acquired = (& $count 'resource.acquire'); waited = (& $count 'resource.wait'); deviceSkipped = @($events | Where-Object { $_.ev -ceq 'dispatch.skip' -and (Get-PqValue $_.d 'why' '') -ceq 'deviceLevel' }).Count }
    $stops = [ordered]@{}
    foreach ($g in @($events | Where-Object { $_.ev -ceq 'run.stop' } | Group-Object { "$(Get-PqValue $_.d 'level' '?') ($(Get-PqValue $_.d 'reason' '?'))" })) { $stops[$g.Name] = $g.Count }
    $report.stops = $stops
    $report.intake = [ordered]@{ robotFiled = (& $count 'intake.robotDraft'); capped = @($events | Where-Object { $_.ev -ceq 'intake.robotDraft' -and (Get-PqValue $_.d 'capped' $false) -eq $true }).Count }
    $report.limits = [ordered]@{ passLimits = (& $count 'pass.limit'); holds = (& $count 'agent.hold'); resumes = (& $count 'agent.resume'); fallbacks = (& $count 'agent.fallback') }
    $report.telemetry = [ordered]@{ events = $events.Count; logErrors = (& $count 'log.error'); seqGaps = @($ev.gaps).Count; unparsable = $ev.bad; unsupported = $ev.unsupported }
    $report.findings = @(Get-PqFindings -Runs $runs -Events $events -Gaps $ev.gaps -Bad $ev.bad)
    return $report
}

function Get-PqTrace {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Id)
    $ev = Read-PqWindowEvents -Root $Root
    return @($ev.events | Where-Object { $_.repo -ceq $Repo -and $_.id -ceq $Id })
}

function Compare-PqRuns {
    param($Runs, [Parameter(Mandatory)][string]$By)
    $groups = Group-PqRunsBy $Runs $By
    $rows = [Collections.Generic.List[object]]::new()
    foreach ($k in @($groups.Keys)) {
        $s = Get-PqRunStats $groups[$k]
        $rows.Add([ordered]@{ value = $k; n = $s.n; okShare = $s.okShare; movedShare = $s.movedShare; minutesP50 = $s.minutesP50 })
    }
    $verdict = 'no evidence'
    if ($rows.Count -ge 2) {
        $a = $rows[$rows.Count - 2]
        $b = $rows[$rows.Count - 1]
        if ($a.n -ge $script:PqMinSample -and $b.n -ge $script:PqMinSample) {
            $diff = [double]$b.okShare - [double]$a.okShare
            $verdict = if ($diff -ge 15) { 'better' } elseif ($diff -le -15) { 'worse' } else { 'no evidence' }
        }
        else { $verdict = "no evidence (n under $($script:PqMinSample))" }
    }
    return [ordered]@{ by = $By; groups = @($rows); verdict = $verdict; from = $(if ($rows.Count -ge 2) { $rows[$rows.Count - 2].value } else { $null }); to = $(if ($rows.Count) { $rows[$rows.Count - 1].value } else { $null }) }
}

function ConvertTo-PqRunCsv($Runs) {
    $cols = @('finishedAt', 'run', 'pass', 'repo', 'id', 'agent', 'model', 'complexity', 'statusBefore', 'statusAfter', 'moved', 'outcome', 'exitCode', 'minutes', 'canon', 'plugin', 'registryHash', 'profileHash')
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add(($cols -join ','))
    foreach ($r in @($Runs)) {
        $lines.Add((@($cols | ForEach-Object {
                        $v = [string](Get-PqValue $r $_ '')
                        if ($v -match '[",\r\n]') { '"' + $v.Replace('"', '""') + '"' } else { $v }
                    }) -join ','))
    }
    return ($lines -join "`n")
}
