# The cross-repository rank (TASK-FLOW rules 43, 44, 45 and 63; S0015 R59, R62, R66).
#
# Dot-source this file; it defines functions only, sets no preference and prints nothing. State: none.
# Get-PqRank is pure: it reads nothing and writes nothing but what its head provider does, and returns the payloads
# of queue.row and rank.result for its caller to emit. Only heads are compared, never a merged list (rule 21).
#
#   Get-PqRank -Registry <obj> [-Queue <Read-PqQueueFile result>] -HeadProvider <sb param($Repo,$Exclude,$ForceId)>
#              [-Exclude <repo:id[]>] [-SkipRepos <key[]>] [-Slots <int>] [-Busy <hashtable key->int>]
#              [-Occupied <key[]>] [-Stopped <key[]>] [-TicketBlocked <hashtable 'repo:id'->'resource'|'deviceLevel'>]
#              [-Fill depth|breadth] [-StopAfter <int>]
#
#   -StopAfter n > 0: the walk of step 3 ends once n distinct heads are found, so a caller that reads only the first
#   candidate (the dispatcher loop, status) does not pay one picker run per queue row it never looks at. The first n
#   candidates are exactly those of the full walk; the alternatives of the last one, and the counts the walk would
#   have added, cover only what was walked. 0 (the default) walks every entry.
#
#   The provider returns what Get-PqPickerHead returns: @{ ok; head; payload; why } ($Repo is the registry record).
#
#   Order: the queue file's active rows in the reader's order (a head row asks for the repository's own head, a
#   ticket row for exactly that ticket); then every active repository the file does not mention, by head priority
#   descending, registry rank ascending, array position. A row whose ticket is not offered is recorded as an
#   alternative 'notOffered:<why>' and the walk goes on.
#
#   Returns @{ candidates; plan; skipped; excluded; autoSkipReasons; fill; heads; ms; queueRows; queueBad; events }:
#     candidates  distinct first picks in global order, @{ repo; id; rule; source; score; package; row; priority;
#                 status; title; alt }, alt the top three rejected picks @{ repo; id; why }
#     plan        @{ slot; repo; id; rule; source; score; priority; status; title } for -Slots under the fill policy
#     skipped     @{ repo; why } (disabled, hold, heldByQueue, stopped, occupied, exhausted, allLeased, noCandidate,
#                 pickerFailed); stopped counts under excluded.held
#     events      @{ ev; d } for every queue.row and the one rank.result

function Get-PqRankValue($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    if ($Object -is [Collections.IDictionary]) { if ($Object.Contains($Name)) { return $Object[$Name] } else { return $Default } }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

function Get-PqRankIds($Items) {
    return @(foreach ($x in @($Items)) {
            if ($null -eq $x) { continue }
            if ($x -is [string]) { $x } else { [string](Get-PqRankValue $x 'id') }
        })
}

function Get-PqRank {
    param(
        [Parameter(Mandatory)]$Registry,
        $Queue,
        [Parameter(Mandatory)][scriptblock]$HeadProvider,
        [string[]]$Exclude = @(),
        [string[]]$SkipRepos = @(),
        [int]$Slots = -1,
        [hashtable]$Busy = @{},
        [string[]]$Occupied = @(),
        [string[]]$Stopped = @(),
        [hashtable]$TicketBlocked = @{},
        [ValidateSet('', 'depth', 'breadth')][string]$Fill = '',
        [ValidateRange(0, [int]::MaxValue)][int]$StopAfter = 0
    )
    $sw = [Diagnostics.Stopwatch]::StartNew()
    if (-not $Fill) { $Fill = [string](Get-PqRankValue $Registry 'fill' 'depth') }
    if ($Slots -lt 0) { $Slots = [int](Get-PqRankValue $Registry 'maxWorkers' 5) }
    $excluded = [ordered]@{ blocked = 0; leased = 0; dropped = 0; held = 0; gated = 0; malformed = 0; idleHold = 0; xrepo = 0
        settling = 0; levelNotAllowed = 0; occupied = 0; resource = 0; deviceLevel = 0 }
    $autoSkip = [ordered]@{}
    $skipped = [Collections.Generic.List[object]]::new()
    $events = [Collections.Generic.List[object]]::new()
    $queueBad = 0

    # 1. Active repositories.
    $repos = [ordered]@{}
    $index = 0
    foreach ($r in @($Registry.repos)) {
        $key = [string](Get-PqRankValue $r 'key')
        $repos[$key] = @{ key = $key; record = $r; index = $index; rank = [long](Get-PqRankValue $r 'rank' 100) }
        $index++
    }
    $queueRows = @()
    $heldRows = @()
    if ($null -ne $Queue) {
        $queueRows = @($Queue.rows)
        $heldRows = @($Queue.held)
        foreach ($b in @($Queue.bad)) {
            $events.Add(@{ ev = 'queue.row'; d = [ordered]@{ kind = $b.kind; line = $b.line; text = $b.text } })
            $queueBad++
        }
    }
    $heldRepos = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $repoExclude = @{}
    foreach ($k in $repos.Keys) { $repoExclude[$k] = [Collections.Generic.List[string]]::new() }
    foreach ($h in $heldRows) {
        if ($null -eq $h.id) { $null = $heldRepos.Add($h.repo) }
        elseif ($repoExclude.ContainsKey($h.repo)) { $repoExclude[$h.repo].Add($h.id); $excluded.held++ }
    }
    foreach ($x in @($Exclude)) {
        $i = $x.IndexOf(':')
        if ($i -le 0) { continue }
        $k = $x.Substring(0, $i)
        if ($repoExclude.ContainsKey($k)) { $repoExclude[$k].Add($x.Substring($i + 1)) }
    }
    foreach ($tk in @($TicketBlocked.Keys)) {
        $i = ([string]$tk).IndexOf(':')
        if ($i -le 0) { continue }
        $k = ([string]$tk).Substring(0, $i)
        if (-not $repoExclude.ContainsKey($k)) { continue }
        $repoExclude[$k].Add(([string]$tk).Substring($i + 1))
        $why = [string]$TicketBlocked[$tk]
        if ($why -ceq 'deviceLevel') { $excluded.deviceLevel++ } else { $excluded.resource++ }
    }
    $active = [ordered]@{}
    foreach ($k in $repos.Keys) {
        if (@($SkipRepos) -ccontains $k) { continue }
        $rec = $repos[$k].record
        if ((Get-PqRankValue $rec 'enabled' $false) -ne $true) { $skipped.Add([ordered]@{ repo = $k; why = 'disabled' }); $excluded.held++; continue }
        if ((Get-PqRankValue $rec 'hold' $false) -eq $true) { $skipped.Add([ordered]@{ repo = $k; why = 'hold' }); $excluded.held++; continue }
        if ($heldRepos.Contains($k)) { $skipped.Add([ordered]@{ repo = $k; why = 'heldByQueue' }); $excluded.held++; continue }
        # The repository's own shared stop file (rule 26): the owner's stop or a release freeze holds it like a hold.
        if (@($Stopped) -ccontains $k) { $skipped.Add([ordered]@{ repo = $k; why = 'stopped' }); $excluded.held++; continue }
        if (@($Occupied) -ccontains $k) { $skipped.Add([ordered]@{ repo = $k; why = 'occupied' }); $excluded.occupied++; continue }
        $cap = if ((Get-PqRankValue $rec 'concurrent' $false) -eq $true) { [int](Get-PqRankValue $rec 'maxWorkers' 1) } else { 1 }
        $busyNow = if ($Busy.ContainsKey($k)) { [int]$Busy[$k] } else { 0 }
        $active[$k] = @{ cap = [Math]::Max(0, $cap - $busyNow); used = 0; planned = [Collections.Generic.List[string]]::new()
            counted = $false; failed = $false; none = $null; picks = 0 }
    }

    # The provider, memoised per (repo, exclusion, forced id), with the exclusion counts taken once per repository.
    $memo = @{}
    $ask = {
        param([string]$Key, [string[]]$Extra, [string]$ForceId)
        $st = $active[$Key]
        $ids = @(@($repoExclude[$Key]) + @($Extra) | Where-Object { $_ } | Sort-Object -Unique)
        $mk = "$Key|$($ids -join ',')|$ForceId"
        if ($memo.ContainsKey($mk)) { return $memo[$mk] }
        $r = & $HeadProvider $repos[$Key].record $ids $ForceId
        if ($null -eq $r) { $r = @{ ok = $false; head = $null; payload = $null; why = 'pickerFailed' } }
        $memo[$mk] = $r
        if (-not $r.ok) { $st.failed = $true; return $r }
        if (-not $st.counted -and $null -ne $r.payload) {
            $st.counted = $true
            $p = $r.payload
            $excluded.leased += @(Get-PqRankIds (Get-PqRankValue $p 'leased_ids' @())).Count
            $excluded.malformed += @(Get-PqRankValue $p 'malformed' @()).Count
            foreach ($s in @(Get-PqRankValue $p 'auto_skipped' @())) {
                if ($null -eq $s) { continue }
                $reason = [string](Get-PqRankValue $s 'reason' 'unknown')
                if ($autoSkip.Contains($reason)) { $autoSkip[$reason]++ } else { $autoSkip[$reason] = 1 }
                switch ($reason) {
                    'idle-hold' { $excluded.idleHold++ }
                    'owner-gate' { $excluded.gated++ }
                    default { $excluded.blocked++ }
                }
            }
        }
        if ($null -eq $ForceId -or $ForceId -eq '') {
            $head = $r.head
            if ($null -eq $head -and $null -eq $st.none) {
                $reason = [string](Get-PqRankValue $r.payload 'selected_none_reason' '')
                $st.none = switch ($reason) { 'queue-exhausted' { 'exhausted' } 'all-leased' { 'allLeased' } default { 'noCandidate' } }
            }
        }
        return $r
    }

    # 2. Entries.
    $entries = [Collections.Generic.List[object]]::new()
    $mentioned = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $ordinal = 0
    foreach ($row in $queueRows) {
        $ordinal++
        if (-not $repos.Contains($row.repo)) {
            $events.Add(@{ ev = 'queue.row'; d = [ordered]@{ kind = 'unknownRepo'; line = $row.line; text = $row.text } })
            $queueBad++
            continue
        }
        $null = $mentioned.Add($row.repo)
        if (-not $active.Contains($row.repo)) { continue }
        $entries.Add(@{ repo = $row.repo; kind = $row.kind; id = $row.id; source = 'queueFile'; rule = 'queueFile'; score = $ordinal
                package = $row.package; row = $row.line })
    }
    $unlisted = [Collections.Generic.List[object]]::new()
    foreach ($k in $active.Keys) {
        if ($mentioned.Contains($k)) { continue }
        $r = & $ask $k @() $null
        $prio = if ($r.ok -and $null -ne $r.head) { [long](Get-PqRankValue $r.head 'priority' 0) } else { [long]::MinValue }
        $unlisted.Add(@{ key = $k; priority = $prio; rank = $repos[$k].rank; index = $repos[$k].index; has = ($r.ok -and $null -ne $r.head) })
    }
    $sorted = @($unlisted | Sort-Object -Stable -Property @{ Expression = { $_.priority }; Descending = $true }, @{ Expression = { $_.rank } }, @{ Expression = { $_.index } })
    foreach ($u in $sorted) {
        $tie = @($sorted | Where-Object { $_.has -and $_.priority -eq $u.priority }).Count -gt 1
        $entries.Add(@{ repo = $u.key; kind = 'head'; id = $null; source = $(if ($tie) { 'repoOrder' } else { 'priority' })
                rule = $(if ($tie) { 'repoRank' } else { 'priority' }); score = $(if ($tie) { $u.rank } else { $u.priority })
                package = $null; row = $null; unlisted = $true })
    }

    # One pick of an entry, with the ids already planned for its repository excluded. @{ head; why }.
    $pickOne = {
        param($Entry, [bool]$WithPlanned)
        $st = $active[$Entry.repo]
        $extra = if ($WithPlanned) { @($st.planned) } else { @() }
        if ($Entry.kind -eq 'ticket') {
            if (@($repoExclude[$Entry.repo]) -ccontains $Entry.id) { return @{ head = $null; why = 'excluded' } }
            if ($WithPlanned -and @($st.planned) -ccontains $Entry.id) { return @{ head = $null; why = 'planned' } }
            $r = & $ask $Entry.repo $extra $Entry.id
            if (-not $r.ok) { return @{ head = $null; why = 'pickerFailed' } }
            return @{ head = $r.head; why = $(if ($null -eq $r.head) { [string]$r.why } else { $null }) }
        }
        $r = & $ask $Entry.repo $extra $null
        if (-not $r.ok) { return @{ head = $null; why = 'pickerFailed' } }
        return @{ head = $r.head; why = $(if ($null -eq $r.head) { 'none' } else { $null }) }
    }

    # 3. Candidates: the first pick of every entry; an entry that offers nothing becomes an alternative of the
    # candidate above it.
    $walk = [Collections.Generic.List[object]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $found = 0
    foreach ($e in $entries) {
        if ($StopAfter -gt 0 -and $found -ge $StopAfter) { break }
        $p = & $pickOne $e $false
        if ($null -eq $p.head) {
            if ($e.kind -eq 'ticket') { $walk.Add(@{ entry = $e; head = $null; why = "notOffered:$($p.why)"; id = $e.id }) }
            continue
        }
        $id = [string](Get-PqRankValue $p.head 'id')
        if (-not $seen.Add("$($e.repo):$id")) { continue }
        $walk.Add(@{ entry = $e; head = $p.head; why = $null; id = $id })
        $found++
    }

    # 4. Fill (R66).
    $plan = [Collections.Generic.List[object]]::new()
    $addPlan = {
        param($Entry, $Head)
        $id = [string](Get-PqRankValue $Head 'id')
        $active[$Entry.repo].planned.Add($id)
        $active[$Entry.repo].used++
        $active[$Entry.repo].picks++
        $plan.Add([ordered]@{ slot = $plan.Count + 1; repo = $Entry.repo; id = $id; rule = $Entry.rule; source = $Entry.source
                score = $(if ($Entry.source -ceq 'priority') { [long](Get-PqRankValue $Head 'priority' 0) } else { $Entry.score })
                priority = Get-PqRankValue $Head 'priority'; status = Get-PqRankValue $Head 'status'; title = Get-PqRankValue $Head 'name' })
    }
    if ($Fill -ceq 'depth') {
        foreach ($e in $entries) {
            $st = $active[$e.repo]
            while ($plan.Count -lt $Slots -and $st.used -lt $st.cap) {
                $p = & $pickOne $e $true
                if ($null -eq $p.head) { break }
                & $addPlan $e $p.head
                if ($e.kind -eq 'ticket') { break }
            }
        }
    }
    else {
        $round = 1
        $doneTicket = [Collections.Generic.HashSet[int]]::new()
        do {
            $made = $false
            for ($i = 0; $i -lt $entries.Count; $i++) {
                if ($plan.Count -ge $Slots) { break }
                $e = $entries[$i]
                if ($round -gt 1 -and $e.kind -eq 'ticket') { continue }
                if ($doneTicket.Contains($i)) { continue }
                $st = $active[$e.repo]
                if ($st.used -ge $st.cap) { continue }
                $p = & $pickOne $e $true
                if ($null -eq $p.head) { continue }
                & $addPlan $e $p.head
                if ($e.kind -eq 'ticket') { $null = $doneTicket.Add($i) }
                $made = $true
            }
            $round++
        } while ($made -and $plan.Count -lt $Slots)
    }

    # 5. Candidates with their alternatives, and the payloads.
    $planned = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($p in $plan) { $null = $planned.Add("$($p.repo):$($p.id)") }
    $candidates = [Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $walk.Count; $i++) {
        $w = $walk[$i]
        if ($null -eq $w.head) { continue }
        $e = $w.entry
        $alt = [Collections.Generic.List[object]]::new()
        for ($j = $i + 1; $j -lt $walk.Count -and $alt.Count -lt 3; $j++) {
            $o = $walk[$j]
            $why = $o.why
            if ($null -eq $why) {
                $oe = $o.entry
                $notPlanned = -not $planned.Contains("$($oe.repo):$($o.id)")
                if ($notPlanned -and $active[$oe.repo].used -ge $active[$oe.repo].cap) { $why = 'fillCap' }
                elseif ($notPlanned -and $plan.Count -ge $Slots) { $why = 'slotsFull' }
                elseif ($e.source -ceq 'queueFile' -and $oe.source -ceq 'queueFile') { $why = if ($oe.package -ne $e.package) { 'lowerPackage' } else { 'laterRow' } }
                elseif ($e.source -ceq 'queueFile') { $why = 'lowerPackage' }
                else {
                    $myP = [long](Get-PqRankValue $w.head 'priority' 0)
                    $oP = [long](Get-PqRankValue $o.head 'priority' 0)
                    $why = if ($oP -lt $myP) { 'lowerPriority' } else { 'laterRepoRank' }
                }
            }
            $alt.Add([ordered]@{ repo = $o.entry.repo; id = $o.id; why = $why })
        }
        $score = if ($e.source -ceq 'priority') { [long](Get-PqRankValue $w.head 'priority' 0) } else { $e.score }
        $candidates.Add([ordered]@{ repo = $e.repo; id = $w.id; rule = $e.rule; source = $e.source; score = $score; package = $e.package
                row = $e.row; priority = Get-PqRankValue $w.head 'priority'; status = Get-PqRankValue $w.head 'status'
                title = Get-PqRankValue $w.head 'name'; alt = $alt.ToArray() })
    }
    foreach ($k in $active.Keys) {
        $st = $active[$k]
        $hasCandidate = @($candidates | Where-Object { $_.repo -ceq $k }).Count -gt 0
        if ($hasCandidate -or $st.picks -gt 0) { continue }
        if ($st.failed) { $skipped.Add([ordered]@{ repo = $k; why = 'pickerFailed' }) }
        elseif ($null -ne $st.none) { $skipped.Add([ordered]@{ repo = $k; why = $st.none }) }
        elseif (-not $mentioned.Contains($k) -or $st.cap -le 0) { $skipped.Add([ordered]@{ repo = $k; why = 'noCandidate' }) }
    }
    $sw.Stop()
    $heads = @($candidates | ForEach-Object { [ordered]@{ repo = $_.repo; id = $_.id; source = $_.source; score = $_.score } })
    $events.Add(@{ ev = 'rank.result'; d = [ordered]@{ heads = $heads; excluded = $excluded; autoSkipReasons = $autoSkip; fill = $Fill
                ms = [int]$sw.ElapsedMilliseconds; queueRows = $queueRows.Count; queueBad = $queueBad } })
    return @{
        candidates = $candidates.ToArray(); plan = $plan.ToArray(); skipped = $skipped.ToArray(); excluded = $excluded
        autoSkipReasons = $autoSkip; fill = $Fill; heads = $heads; ms = [int]$sw.ElapsedMilliseconds
        queueRows = $queueRows.Count; queueBad = $queueBad; events = $events.ToArray()
    }
}
