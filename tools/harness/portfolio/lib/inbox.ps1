# The owner's inbox of the portfolio (S0025): the tickets that wait for the owner alone, read from the ledgers of
# every registered repository. The row reader is the quiz-list reader - one place reads a ledger for a read-only
# owner-facing list, so quiz-list.ps1 and pq inbox cannot drift apart.
#
# Dot-source this file; it defines functions only, sets no preference and prints nothing. It loads registry.ps1 and
# ledger-watch.ps1 itself. The chain-root walk needs xrepo.ps1 (Get-PqXrepoBlock, the picker's release test); load
# it before calling Get-PqInbox - pq.ps1 does, quiz-list.ps1 never calls that far.
#
#   Read-PqLedgerRows -RepoPath <dir>
#       every row of one project's ledger as it stands: @{ Root; Id; Name; Status; Priority; Updated; File; Note }
#       (note flattened to one line). A line that is not a JSON object is skipped, never thrown.
#   Get-PqInboxRows -Registry
#       @{ rows; skipped } over every registered repository; each row gains `repo` (the registry key). A repository
#       whose folder or ledger cannot be read lands in skipped with its key, never as an error.
#   Get-PqInboxCounts -Rows
#       the five kinds of the inbox as an ordered map label -> count.
#   Get-PqInbox -Registry [-Held <set of "key:id">]
#       the full inbox: @{ total; projects; skipped; kinds } where kinds is an ordered map label ->
#       @{ status; label; clear; count; oldestAge; oldestSeconds; tickets; roots (chain only) }. A ticket is
#       @{ repo; id; status; priority; updated; ageSeconds; age; name; file; note }. A chain root is
#       @{ repo; id; pair; status; note; held; state; why; frees (the "key:id" it holds back); freesCount; age }.
#       BlockByOtherTask tickets are grouped by their chain root: the walk follows the spec's Blocker: tokens
#       (qualified and local) while the blocker holds, judged by the same release test the picker uses
#       (Test-BlockerReleased through xrepo.ps1), at most ten hops.

. (Join-Path $PSScriptRoot 'registry.ps1')
. (Join-Path $PSScriptRoot 'ledger-watch.ps1')

# The five kinds of what waits for the owner, in the order they print. `clear` is the command that clears the kind.
$script:PqInboxKinds = [ordered]@{
    questions = @{ status = 'BlockQuestions';    clear = '/spec-quiz <key>:<id>' }
    tests     = @{ status = 'BlockNeedUserTest'; clear = '/spec-to-audit <key>:<id> (Sweep mode - run the recorded manual check)' }
    outside   = @{ status = 'BlockExternal';     clear = 'the outside party named in the note - no pq command' }
    chain     = @{ status = 'BlockByOtherTask';  clear = 'pq release <root>, or the root''s own status moves' }
    unbuilt   = @{ status = 'Implemented';       clear = '/spec-to-audit <key>:<id> (audit to Verified)' }
}

# Null-safe property read: ledger rows leave most keys out, and StrictMode throws on a missing one.
function Get-PqRowProp($Object, [string] $Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

# Every row of one project's ledger, as it stands. A line that is not a JSON object is skipped, never thrown: a
# half-written last line must not hide the rest.
function Read-PqLedgerRows([string] $RepoPath) {
    $paths = Get-PqRepoPaths -RepoPath $RepoPath
    if (-not [IO.File]::Exists($paths.Ledger)) { return @() }
    $fs = [IO.FileStream]::new($paths.Ledger, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try { $text = [IO.StreamReader]::new($fs, [Text.UTF8Encoding]::new($false)).ReadToEnd() } finally { $fs.Dispose() }
    $rows = [Collections.Generic.List[object]]::new()
    foreach ($raw in $text.TrimStart([char]0xFEFF).Split("`n")) {
        $line = $raw.Trim()
        if ($line.Length -eq 0) { continue }
        try { $row = ConvertFrom-Json -InputObject $line -DateKind String -NoEnumerate } catch { continue }
        if ($row -isnot [Management.Automation.PSCustomObject]) { continue }
        if ($row.PSObject.Properties['id'] -isnot [Management.Automation.PSPropertyInfo]) { continue }
        $note = [regex]::Replace([string](Get-PqRowProp $row 'statusNote' ''), '\s*[\r\n]+\s*', ' ')
        $rows.Add([pscustomobject]@{
            Root     = $paths.Root
            Id       = [string](Get-PqRowProp $row 'id' '')
            Name     = [string](Get-PqRowProp $row 'name' '')
            Status   = [string](Get-PqRowProp $row 'status' '')
            Priority = [int](Get-PqRowProp $row 'priority' 0)
            Updated  = [string](Get-PqRowProp $row 'updated' '')
            File     = [string](Get-PqRowProp $row 'file' '')
            Note     = $note
        })
    }
    return $rows.ToArray()
}

# Every registered repository's rows, read-only. $Registry is the registry with defaults applied.
function Get-PqInboxRows($Registry) {
    $rows = [Collections.Generic.List[object]]::new()
    $skipped = [Collections.Generic.List[string]]::new()
    foreach ($r in @($Registry.repos)) {
        $key = [string]$r.key
        if (-not (Test-Path -LiteralPath ([string]$r.path) -PathType Container)) { $skipped.Add("$key - folder missing"); continue }
        try {
            foreach ($row in @(Read-PqLedgerRows ([string]$r.path))) {
                $rows.Add([pscustomobject]@{
                    repo = $key; id = $row.Id; name = $row.Name; status = $row.Status; priority = $row.Priority
                    updated = $row.Updated; file = $row.File; note = $row.Note; root = $row.Root
                })
            }
        }
        catch { $skipped.Add("$key - $($_.Exception.Message)") }
    }
    return @{ rows = $rows.ToArray(); skipped = $skipped.ToArray() }
}

# Age in whole seconds as Nd / Nh / Nm; $null reads as 'unknown'.
function ConvertTo-PqInboxAgeText($Seconds) {
    if ($null -eq $Seconds) { return 'unknown' }
    if ($Seconds -ge 86400) { return '{0}d' -f [Math]::Floor($Seconds / 86400) }
    if ($Seconds -ge 3600) { return '{0}h' -f [Math]::Floor($Seconds / 3600) }
    return '{0}m' -f [Math]::Floor($Seconds / 60)
}

# Age of a ledger row from its `updated` (a local wall-clock time) to now: @{ seconds; text }.
function Get-PqInboxAge([string] $Updated) {
    $from = ConvertFrom-PqLocalTime $Updated
    $seconds = $null
    if ($null -ne $from) { $seconds = [long][Math]::Max(0, [Math]::Floor(([DateTimeOffset]::Now - $from).TotalSeconds)) }
    return @{ seconds = $seconds; text = (ConvertTo-PqInboxAgeText $seconds) }
}

function ConvertTo-PqInboxTicket($Row) {
    $age = Get-PqInboxAge $Row.updated
    return [pscustomobject][ordered]@{
        repo = $Row.repo; id = $Row.id; status = $Row.status; priority = $Row.priority; updated = $Row.updated
        ageSeconds = $age.seconds; age = $age.text; name = $Row.name; file = $Row.file; note = $Row.note
    }
}

# The five counts, as the status line of pq status prints them.
function Get-PqInboxCounts($Rows) {
    $counts = [ordered]@{}
    foreach ($label in $script:PqInboxKinds.Keys) { $counts[$label] = 0 }
    foreach ($row in @($Rows)) {
        foreach ($label in $script:PqInboxKinds.Keys) {
            if ($row.status -ceq $script:PqInboxKinds[$label].status) { $counts[$label]++; break }
        }
    }
    return $counts
}

# The first local (same-repository) `Blocker: <id>` token of the ticket's spec whose blocker is not released - the
# picker's release test, the one xrepo.ps1 runs for qualified blockers - as "key:id", else $null. A blocker that
# cannot be read holds, like xrepo.ps1's 'unreadable'.
function Get-PqInboxLocalHold($ByKey, $Snaps, [string] $RepoKey, [string] $Id) {
    if ($null -eq (Get-Variable -Name PqStatusSets -Scope Script -ErrorAction Ignore)) { return $null }
    if (-not $ByKey.ContainsKey($RepoKey)) { return $null }
    $t = Get-PqXrepoTicket $ByKey[$RepoKey] $Id $Snaps
    if ($null -eq $t) { return $null }
    $spec = Read-PqSpecText $t.file
    if (-not $spec) { return $null }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($m in [regex]::Matches($spec, '(?i)(?:Blocker|Блокер)\s*:\s*\**\s*([A-Za-z][A-Za-z0-9_-]*(?:\s*:\s*[A-Za-z][A-Za-z0-9_-]*)?)')) {
        $val = $m.Groups[1].Value -replace '\s*:\s*', ':'
        if ($val.Contains(':')) { continue }   # a qualified token: xrepo.ps1's own walk owns it
        if ($val -ceq $Id) { continue }
        if (-not $seen.Add($val)) { continue }
        $b = Get-PqXrepoTicket $ByKey[$RepoKey] $val $Snaps
        if ($null -eq $b) { return "$RepoKey`:$val" }
        $released = & $script:PqStatusSets { param($s, $i, $f) Test-BlockerReleased -Status $s -Id $i -File $f } $b.status $val $b.file
        if (-not $released) { return "$RepoKey`:$val" }
    }
    return $null
}

# The chain root of one BlockByOtherTask ticket: follow the spec's Blocker: tokens while the blocker holds (the
# picker's release test via xrepo.ps1), at most ten hops. -> @{ pair; state; why }.
function Get-PqInboxChainRoot($Registry, $ByKey, $Snaps, [string] $RepoKey, [string] $Id) {
    $at = "$RepoKey`:$Id"
    $visited = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $state = 'root'
    $why = $null
    for ($hop = 0; $hop -lt 10; $hop++) {
        if (-not $visited.Add($at)) { return @{ pair = $at; state = 'cycle'; why = 'the blockers form a cycle' } }
        $k, $i = $at -split ':', 2
        if (-not $ByKey.ContainsKey($k)) { return @{ pair = $at; state = 'unknownKey'; why = "no registered repository '$k'" } }
        $block = $null
        try { $block = Get-PqXrepoBlock -Registry $Registry -RepoKey $k -TicketId $i } catch { $block = $null }
        $next = $null
        if ($null -ne $block) { $next = [string]$block.blocker; $state = [string]$block.state; $why = [string]$block.why }
        else {
            $local = Get-PqInboxLocalHold $ByKey $Snaps $k $i
            if ($null -ne $local) { $next = $local; $state = 'open'; $why = 'a local Blocker: token holds' }
        }
        if ($null -eq $next) { return @{ pair = $at; state = $state; why = $why } }
        $at = $next
    }
    return @{ pair = $at; state = 'cycle'; why = 'the blocker chain is longer than ten hops' }
}

# The full inbox. -Held: the set of "key:id" rows held in PORTFOLIO_QUEUE.md (may be $null).
function Get-PqInbox {
    param([Parameter(Mandatory)]$Registry, $Held)
    $gathered = Get-PqInboxRows $Registry
    $rows = @($gathered.rows)
    $byPair = @{}
    foreach ($row in $rows) { $byPair["$($row.repo):$($row.id)"] = $row }
    $byKey = @{}
    foreach ($r in @($Registry.repos)) { $byKey[[string]$r.key] = $r }

    $kinds = [ordered]@{}
    $chainRows = @($rows | Where-Object { $_.status -ceq 'BlockByOtherTask' })
    foreach ($label in $script:PqInboxKinds.Keys) {
        $status = $script:PqInboxKinds[$label].status
        $mine = if ($label -ceq 'chain') { $chainRows } else { @($rows | Where-Object { $_.status -ceq $status }) }
        $tickets = @($mine | ForEach-Object { ConvertTo-PqInboxTicket $_ } | Sort-Object -Property @{ Expression = { -($_.ageSeconds ?? [long]::MaxValue) } }, 'repo', 'id')
        $oldest = $null
        foreach ($t in $tickets) { if ($null -ne $t.ageSeconds -and ($null -eq $oldest -or $t.ageSeconds -gt $oldest)) { $oldest = $t.ageSeconds } }
        $kinds[$label] = [ordered]@{
            label = $label; status = $status; clear = $script:PqInboxKinds[$label].clear
            count = $tickets.Count; oldestSeconds = $oldest
            oldestAge = $(if ($null -eq $oldest) { 'none' } else { (ConvertTo-PqInboxAgeText $oldest) })
            tickets = $tickets; roots = @()
        }
    }

    # Chain roots: every BlockByOtherTask ticket walks to its root; the root line says how many it frees.
    if ($chainRows.Count -gt 0) {
        $snaps = @{}
        $groups = [ordered]@{}
        $selfRoot = @{}
        foreach ($row in $chainRows) {
            $root = Get-PqInboxChainRoot $Registry $byKey $snaps $row.repo $row.id
            $pair = $root.pair
            if (-not $groups.Contains($pair)) {
                $groups[$pair] = [Collections.Generic.List[object]]::new()
                $selfRoot[$pair] = $root
            }
            $groups[$pair].Add($row)
        }
        $roots = [Collections.Generic.List[object]]::new()
        $loose = [Collections.Generic.List[object]]::new()
        foreach ($pair in $groups.Keys) {
            $members = @($groups[$pair])
            $root = $selfRoot[$pair]
            $rPair = $pair -split ':', 2
            $rRow = if ($byPair.ContainsKey($pair)) { $byPair[$pair] } else { $null }
            $rAge = if ($null -ne $rRow) { Get-PqInboxAge $rRow.updated } else { @{ seconds = $null; text = 'unknown' } }
            $isSelf = ($members.Count -eq 1 -and $root.state -ceq 'root' -and "$($members[0].repo):$($members[0].id)" -ceq $pair)
            if ($isSelf) { $loose.Add($members[0]); continue }
            $note = if ($null -ne $rRow) { $rRow.note } else { '' }
            $roots.Add([pscustomobject][ordered]@{
                pair = $pair; repo = $rPair[0]; id = $rPair[1]
                status = $(if ($null -ne $rRow) { $rRow.status } else { $null })
                note = $note; held = ($null -ne $Held -and $Held.Contains($pair))
                state = $root.state; why = $root.why
                frees = @($members | ForEach-Object { "$($_.repo):$($_.id)" })
                freesCount = $members.Count
                ageSeconds = $rAge.seconds; age = $rAge.text
            })
        }
        $kinds['chain']['roots'] = @($roots | Sort-Object -Property @{ Expression = { -$_.freesCount } }, 'pair')
        # The BlockByOtherTask tickets whose every blocker is released (or unreadable) wait on nothing foreign: they
        # print as ordinary ticket lines, the note says why they are still blocked.
        $kinds['chain']['tickets'] = @($loose | ForEach-Object { ConvertTo-PqInboxTicket $_ } | Sort-Object -Property @{ Expression = { -($_.ageSeconds ?? [long]::MaxValue) } }, 'repo', 'id')
    }

    $counts = Get-PqInboxCounts $rows
    $projects = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($row in $rows) { $null = $projects.Add($row.repo) }
    return [ordered]@{
        total = $counts.Values | Measure-Object -Sum | ForEach-Object { $_.Sum }
        projects = $projects.Count
        skipped = $gathered.skipped
        counts = $counts
        kinds = $kinds
    }
}
