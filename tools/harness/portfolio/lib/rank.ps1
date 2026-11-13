# The cross-repository rank (TASK-FLOW 0.12 rules 43, 44, 45 and 63; S0015 R59, R62, R66).
#
# Dot-source this file; it defines functions only, sets no preference and prints nothing. State: none.
# Get-PqRank is pure: it reads nothing and writes nothing but what its head provider does, and returns the payloads
# of queue.row and rank.result for its caller to emit. Only heads are compared, never a merged list (rule 21).
#
#   Get-PqRank -Registry <obj> [-Queue <Read-PqQueueFile result>] -HeadProvider <sb param($Repo,$Exclude,$ForceId)>
#              [-Exclude <repo:id[]>] [-SkipRepos <key[]>] [-Slots <int>] [-Busy <hashtable key->int>]
#              [-Occupied <key[]>] [-Stopped <key[]>] [-TicketBlocked <hashtable 'repo:id'->'resource'|'deviceLevel'>]
#              [-Fill depth|breadth] [-StopAfter <int>] [-NamedTicket <key:id>] [-OnlyRepo <key>] [-FirstHead]
#
#   -NamedTicket key:id (S0027, `pq start -Ticket`): only that repository is active and its single entry is exactly that
#   ticket, whatever its rank; the queue file's rows are ignored and so are its hold lines for that repository (the whole-
#   project hold row, and the hold row of that exact ticket) - the lines themselves stay in the file and keep holding every
#   other ticket. Everything else still applies: the registry's enabled and hold flags, a stop, occupancy, the exclusion
#   lists, and the picker's own gates. The result then also carries named = @{ repo; id; offered; why; heldBypassed }, and
#   rank.result carries 'named' and 'heldBypassed'; without the parameter neither key exists.
#   -OnlyRepo key (`pq start -Repo`): only that repository is ranked, in its own ticket order, every hold kept.
#
#   -StopAfter n > 0: the walk of step 3 ends once n distinct heads are found, so a caller that reads only the first
#   candidate (the dispatcher loop, status) does not pay one picker run per queue row it never looks at. The first n
#   candidates are exactly those of the full walk; the alternatives of the last one, and the counts the walk would
#   have added, cover only what was walked. 0 (the default) walks every entry.
#   -FirstHead: the walk of step 3 stops walking a repository once its first head is found (one candidate per project).
#
#   The provider returns what Get-PqPickerHead returns: @{ ok; head; payload; why } ($Repo is the registry record).
#
#   Order (rule 63): the active repositories by registry rank ascending, array position on a tie - the owner's order
#   of projects, which no package of the queue file outranks. Inside a repository, its rows of the queue file in
#   the reader's order (a head row asks for the repository's own head, a ticket row for exactly that ticket); a
#   repository the file does not mention offers its own head at its place. A row whose ticket is not offered is
#   recorded as an alternative 'notOffered:<why>' and the walk goes on.
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

# '<key>:<id>' split on the first colon: @{ repo; id }, or $null when it is not that shape (no key, no id, a blank).
function ConvertTo-PqNamedTicket([string]$Text) {
    if ([string]::IsNullOrEmpty($Text)) { return $null }
    $i = $Text.IndexOf(':')
    if ($i -le 0 -or $i -ge $Text.Length - 1) { return $null }
    $key = $Text.Substring(0, $i)
    $id = $Text.Substring($i + 1)
    if ($key -match '\s' -or $id -match '\s') { return $null }
    return @{ repo = $key; id = $id }
}

# The checks of `pq start -Ticket / -Repo` that need no worker slot (S0027): @{ ok; name; message; named }. Pure.
function Test-PqStartTarget {
    param([Parameter(Mandatory)]$Registry, [string]$Ticket = '', [string]$Repo = '', [int]$MaxTickets = 0)
    $keys = @(@($Registry.repos) | ForEach-Object { [string](Get-PqRankValue $_ 'key') })
    $bad = { param($n, $m) @{ ok = $false; name = $n; message = $m; named = $null } }
    if ($Ticket -and $Repo) { return (& $bad 'ArgumentConflict' '-Ticket and -Repo cannot be used together') }
    if ($Ticket) {
        $named = ConvertTo-PqNamedTicket $Ticket
        if ($null -eq $named) { return (& $bad 'ArgumentInvalid' "-Ticket '$Ticket' is not <key>:<id>") }
        if ($keys -cnotcontains $named.repo) { return (& $bad 'UnknownRepoKey' "no repository '$($named.repo)' in the registry") }
        if ($MaxTickets -gt 1) { return (& $bad 'ArgumentInvalid' "-MaxTickets $MaxTickets with -Ticket: a named start is one pass (use 0 or 1)") }
        return @{ ok = $true; name = $null; message = $null; named = $named }
    }
    if ($Repo -and $keys -cnotcontains $Repo) { return (& $bad 'UnknownRepoKey' "no repository '$Repo' in the registry") }
    return @{ ok = $true; name = $null; message = $null; named = $null }
}

# One line for `pq: ticket <key>:<id> not run - <reason>`: what the loop itself held back (-Marks: xblocked, transient,
# occupied - the loop's hashtables - and exclude, its list) first, then the named result of the rank.
function Get-PqNamedNotRunReason {
    param($Rank, [Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][string]$Id, [hashtable]$Marks = @{})
    $tk = "$Key`:$Id"
    $xb = Get-PqRankValue $Marks 'xblocked'
    if ($null -ne $xb -and $xb.ContainsKey($tk)) { return "it waits on a blocker in another project ($($xb[$tk].blocker))" }
    $tr = Get-PqRankValue $Marks 'transient'
    if ($null -ne $tr -and $tr.ContainsKey($tk)) {
        if ([string]$tr[$tk].why -ceq 'deviceLevel') { return 'it needs real hardware (Verify: device) and robots never take it' }
        return 'it waits for a machine resource (build, emulator) that another pass holds'
    }
    $oc = Get-PqRankValue $Marks 'occupied'
    if ($null -ne $oc -and $oc.ContainsKey($Key)) {
        if ([string]$oc[$Key].why -ceq 'workerCap') { return "the project's worker cap is reached" }
        return 'the project is occupied by a live owner session (the robot yields)'
    }
    if (@(Get-PqRankValue $Marks 'exclude' @()) -ccontains $tk) { return 'the ticket was excluded earlier in this run' }
    $n = Get-PqRankValue $Rank 'named'
    $why = [string](Get-PqRankValue $n 'why' '')
    switch ($why) {
        'unknownRepo' { return 'no such project in the registry' }
        'disabled' { return 'the project is disabled in the registry (enabled is false)' }
        'hold' { return "the project is on hold in the registry (pq release $Key)" }
        'heldByQueue' { return 'the project is under a hold line of the queue file' }
        'stopped' { return 'the project is stopped (its shared stop file exists)' }
        'occupied' { return 'the project is occupied (another worker holds it, or a live owner session)' }
        'skipped' { return 'the project was skipped by the caller' }
        'excluded' { return 'the ticket is excluded in this run (dropped, stopped or waiting on a resource)' }
        'leased' { return 'the ticket holds a live lease (another session or pass is working it)' }
        'notRanked' { return 'the project offers no such ticket (absent, closed, or a status no robot works)' }
        'malformed' { return "the ticket's ledger row is malformed" }
        'notOffered' { return 'the picker does not offer the ticket now' }
        'pickerFailed' { return 'the picker failed' }
        'idle-hold' { return 'the picker holds it (idle-run hold)' }
        'awaits-release' { return 'the picker holds it (only release-tier work is left and the code tree is unchanged since its last audit)' }
        'owner-gate' { return 'the picker holds it (owner gate)' }
        '' { return 'it is not offered' }
        default { return "the picker holds it ($why)" }
    }
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
        [ValidateRange(0, [int]::MaxValue)][int]$StopAfter = 0,
        [string]$NamedTicket = '',
        [string]$OnlyRepo = '',
        [switch]$FirstHead,
        # Asked of every head the walk of step 3 finds: param($RepoKey, $Id) -> $null when the head may be offered, else
        # an object saying why not (the loop passes Get-PqXrepoBlock, rule 52). A refused head is excluded and the SAME
        # entry is asked again, so one walk goes past every blocked head instead of the caller ranking once per head.
        [scriptblock]$HeadFilter = $null
    )
    $headRefused = [Collections.Generic.List[object]]::new()
    $namedMode = $false
    $namedRepo = ''
    $namedId = ''
    if ($NamedTicket) {
        if ($OnlyRepo) { throw 'ArgumentConflict: -NamedTicket and -OnlyRepo are exclusive' }
        $nt = ConvertTo-PqNamedTicket $NamedTicket
        if ($null -eq $nt) { throw "ArgumentInvalid: -NamedTicket '$NamedTicket' is not <key>:<id>" }
        $namedMode = $true
        $namedRepo = $nt.repo
        $namedId = $nt.id
    }
    $onlyKey = if ($namedMode) { $namedRepo } else { $OnlyRepo }
    $heldBypassed = $false
    $namedOffered = $false
    $namedWhy = $null
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
        # A named ticket passes through the hold lines that name its project or itself; the lines stay in the file.
        if ($namedMode -and $h.repo -ceq $namedRepo -and ($null -eq $h.id -or $h.id -ceq $namedId)) { $heldBypassed = $true; continue }
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
        if ($onlyKey -and $k -cne $onlyKey) { continue }
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

    if ($namedMode -and -not $active.Contains($namedRepo)) {
        $namedWhy = 'skipped'
        if (-not $repos.Contains($namedRepo)) { $namedWhy = 'unknownRepo' }
        else { foreach ($sk in $skipped) { if ($sk.repo -ceq $namedRepo) { $namedWhy = [string]$sk.why; break } } }
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
                    # TASK-FLOW 0.24 rule 67: counted with the idle hold - both mean "another pass would
                    # repeat the last one" - so the rank.result payload keeps its keys.
                    'awaits-release' { $excluded.idleHold++ }
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

    # 2. Entries: the repositories in registry rank order (rule 63); inside one, its rows of the queue file in the reader's
    # order, or its own head when the file does not name it.
    $entries = [Collections.Generic.List[object]]::new()
    $mentioned = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $rowsOf = @{}
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
        if (-not $rowsOf.ContainsKey($row.repo)) { $rowsOf[$row.repo] = [Collections.Generic.List[object]]::new() }
        $rowsOf[$row.repo].Add(@{ repo = $row.repo; kind = $row.kind; id = $row.id; source = 'queueFile'; rule = 'queueFile'; score = $ordinal
                package = $row.package; row = $row.line })
    }
    foreach ($k in @($active.Keys | Sort-Object -Stable -Property @{ Expression = { $repos[$_].rank } }, @{ Expression = { $repos[$_].index } })) {
        if ($namedMode) {
            # One entry: the named ticket itself; the queue file's rows of the repository are not consulted. source and
            # rule carry the existing enum value 'queueFile' (EVENTS.md lists no other for heads[].source and
            # dispatch.pick rule); the 'named' key of rank.result says it was the owner's explicit start.
            $entries.Add(@{ repo = $k; kind = 'ticket'; id = $namedId; source = 'queueFile'; rule = 'queueFile'; score = 0
                    package = $null; row = $null })
        }
        elseif ($rowsOf.ContainsKey($k)) { foreach ($x in $rowsOf[$k]) { $entries.Add($x) } }
        elseif (-not $mentioned.Contains($k)) {
            $entries.Add(@{ repo = $k; kind = 'head'; id = $null; source = 'repoOrder'; rule = 'repoRank'; score = $repos[$k].rank
                    package = $null; row = $null; unlisted = $true })
        }
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
    $reposWithHead = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $found = 0
    foreach ($e in $entries) {
        if ($StopAfter -gt 0 -and $found -ge $StopAfter) { break }
        if ($FirstHead -and $reposWithHead.Contains($e.repo)) { continue }
        $p = & $pickOne $e $false
        # Measured 2026-11-13: three hub tickets waiting on other projects cost a full walk each (about a minute per walk,
        # the higher-ranked repositories asked again every time) before the robot reached work. Refuse them here, inside
        # the walk; the next ask of the entry carries the grown exclusion, so only this repository's picker runs again.
        if ($null -ne $HeadFilter -and -not $namedMode) {
            $guard = 0
            while ($null -ne $p.head -and $guard -lt 50) {
                $guard++
                $hid = [string](Get-PqRankValue $p.head 'id')
                $refusal = & $HeadFilter $e.repo $hid
                if ($null -eq $refusal) { break }
                $repoExclude[$e.repo].Add($hid)
                $excluded.xrepo++
                $headRefused.Add([ordered]@{ repo = $e.repo; id = $hid; status = [string](Get-PqRankValue $p.head 'status'); refusal = $refusal })
                $p = & $pickOne $e $false
            }
        }
        if ($namedMode) { $namedOffered = ($null -ne $p.head); $namedWhy = if ($namedOffered) { $null } else { [string]$p.why } }
        if ($null -eq $p.head) {
            if ($e.kind -eq 'ticket') { $walk.Add(@{ entry = $e; head = $null; why = "notOffered:$($p.why)"; id = $e.id }) }
            continue
        }
        $id = [string](Get-PqRankValue $p.head 'id')
        if (-not $seen.Add("$($e.repo):$id")) { continue }
        $null = $reposWithHead.Add($e.repo)
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
                score = $Entry.score
                priority = Get-PqRankValue $Head 'priority'; status = Get-PqRankValue $Head 'status'; title = Get-PqRankValue $Head 'name' })
    }
    if ($Fill -ceq 'depth') {
        foreach ($e in $entries) {
            $st = $active[$e.repo]
            while ($plan.Count -lt $Slots -and $st.used -lt $st.cap) {
                if ($FirstHead -and $st.used -ge 1) { break }
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
                if ($FirstHead -and $st.used -ge 1) { continue }
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
                elseif ($e.repo -cne $oe.repo) { $why = 'laterRepoRank' }
                else { $why = if ($oe.package -ne $e.package) { 'lowerPackage' } else { 'laterRow' } }
            }
            $alt.Add([ordered]@{ repo = $o.entry.repo; id = $o.id; why = $why })
        }
        $candidates.Add([ordered]@{ repo = $e.repo; id = $w.id; rule = $e.rule; source = $e.source; score = $e.score; package = $e.package
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
    $resultD = [ordered]@{ heads = $heads; excluded = $excluded; autoSkipReasons = $autoSkip; fill = $Fill
        ms = [int]$sw.ElapsedMilliseconds; queueRows = $queueRows.Count; queueBad = $queueBad }
    if ($namedMode) { $resultD.named = "$namedRepo`:$namedId"; $resultD.heldBypassed = $heldBypassed }
    $events.Add(@{ ev = 'rank.result'; d = $resultD })
    $result = @{
        candidates = $candidates.ToArray(); plan = $plan.ToArray(); skipped = $skipped.ToArray(); excluded = $excluded
        autoSkipReasons = $autoSkip; fill = $Fill; heads = $heads; ms = [int]$sw.ElapsedMilliseconds
        queueRows = $queueRows.Count; queueBad = $queueBad; events = $events.ToArray()
        headRefused = $headRefused.ToArray()
    }
    if ($namedMode) {
        $result.named = @{ repo = $namedRepo; id = $namedId; offered = $namedOffered; why = $namedWhy; heldBypassed = $heldBypassed }
    }
    return $result
}
