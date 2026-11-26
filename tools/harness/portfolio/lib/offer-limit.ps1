# The bound on automatic retries (TASK-FLOW 0.51 item D): a ticket whose newest offers of the last 24 hours, three or
# more of them, brought it back to where they found it is not offered until the offers age out or its spec file is
# edited. Derived from the run rows at every rank, stored nowhere. The analysis finding PQ-THRASH01 asks the same walk.
#
# Dot-source this file; it defines functions only, sets no preference and prints nothing.
#
#   Get-PqStuckOffers -Rows <one ticket's run rows> [-Min 3]
#       @{ passes; statuses; newest } when some run of the newest -Min or more counted rows made no net advance, else
#       $null. passes = the counted rows, statuses = the status each ended in, newest = the finishedAt of the last one.
#   Get-PqThrashHeld -Registry <registry> [-Now <local datetime>] [-Root <portfolio root>]
#       the held tickets of the enabled repositories, each @{ key = '<repo>:<id>'; repo; id; passes; statuses; newest }.
#       Calls Get-PqRoot (paths.ps1) and Get-PqValue, Get-PqDropMark (the loop's libraries) at run time.

$script:PqOfferLimit = 3
$script:PqOfferHours = 24
# The grace of rule 24's lift: finishedAt is cut to whole seconds.
$script:PqOfferLiftGraceSeconds = 60
# A row of one of these says nothing about the ticket: no child worked it to an end, or the owner ended the pass.
$script:PqNotAnOffer = @('limit-hit', 'claim-lost-before-launch', 'launch-failed', 'provider-error', 'halted', 'killed')
# runs.jsonl is never rotated; a day of rows is far inside its tail.
$script:PqOfferTailBytes = 1MB

function ConvertTo-PqRowTime([string]$Text) {
    $at = [datetime]::MinValue
    if ($Text -and [datetime]::TryParse($Text, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$at)) { return $at }
    return [datetime]::MinValue
}

function Get-PqStuckOffers {
    param($Rows, [int]$Min = $script:PqOfferLimit)
    if ($Min -lt 1) { $Min = $script:PqOfferLimit }
    $offers = @(@($Rows) | Where-Object {
            $null -ne $_ -and $script:PqNotAnOffer -cnotcontains [string](Get-PqValue $_ 'outcome' '') -and
            ([string](Get-PqValue $_ 'statusBefore' '') -or [string](Get-PqValue $_ 'statusAfter' ''))
        } | Sort-Object -Stable -Property @{ Expression = { ConvertTo-PqRowTime ([string](Get-PqValue $_ 'finishedAt' '')) } })
    if ($offers.Count -lt $Min) { return $null }
    $ends = @($offers | ForEach-Object {
            $after = [string](Get-PqValue $_ 'statusAfter' '')
            if ($after) { $after } else { [string](Get-PqValue $_ 'statusBefore' '') }
        })
    $last = [string]$ends[$offers.Count - 1]
    for ($i = $offers.Count - $Min; $i -ge 0; $i--) {
        if ([string](Get-PqValue $offers[$i] 'statusBefore' '') -ceq $last) {
            return @{ passes = $offers.Count; statuses = [string[]]$ends; newest = [string](Get-PqValue $offers[$offers.Count - 1] 'finishedAt' '') }
        }
    }
    return $null
}

# The run rows finished at or after -Since, read from the tail of runs.jsonl. Only lines that name one of the window's
# days are parsed.
function Read-PqRecentRuns {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][datetime]$Since, [Parameter(Mandatory)][datetime]$Until)
    $rows = [Collections.Generic.List[object]]::new()
    if (-not [IO.File]::Exists($Path)) { return @() }
    $stream = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try {
        $cut = $stream.Length -gt $script:PqOfferTailBytes
        if ($cut) { $null = $stream.Seek(-$script:PqOfferTailBytes, 'End') }
        $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8)
        try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
    }
    finally { $stream.Dispose() }
    $lines = $text.Split("`n")
    $days = @(for ($d = $Since.Date; $d -le $Until.Date; $d = $d.AddDays(1)) { $d.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) })
    for ($i = $(if ($cut) { 1 } else { 0 }); $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        $named = $false
        foreach ($day in $days) { if ($line.Contains($day)) { $named = $true; break } }
        if (-not $named) { continue }
        try { $row = ConvertFrom-Json -InputObject $line.Trim().TrimStart([char]0xFEFF) -DateKind String } catch { continue }
        if ((ConvertTo-PqRowTime ([string](Get-PqValue $row 'finishedAt' ''))) -ge $Since) { $rows.Add($row) }
    }
    return @($rows)
}

function Get-PqThrashHeld {
    param([Parameter(Mandatory)]$Registry, [datetime]$Now = [datetime]::Now, [string]$Root)
    $held = [Collections.Generic.List[object]]::new()
    try {
        if (-not $Root) { $Root = Get-PqRoot }
        $since = $Now.AddHours(-$script:PqOfferHours)
        $rows = @(Read-PqRecentRuns -Path (Join-Path $Root 'runs.jsonl') -Since $since -Until $Now)
        if ($rows.Count -lt $script:PqOfferLimit) { return @() }
        $byKey = @{}
        foreach ($r in @($Registry.repos)) { if ((Get-PqValue $r 'enabled' $false) -eq $true) { $byKey[[string]$r.key] = $r } }
        $tickets = [ordered]@{}
        foreach ($row in $rows) {
            $repo = [string](Get-PqValue $row 'repo' '')
            $id = [string](Get-PqValue $row 'id' '')
            if (-not $id -or -not $byKey.ContainsKey($repo)) { continue }
            $k = "$repo`:$id"
            if (-not $tickets.Contains($k)) { $tickets[$k] = @{ repo = $repo; id = $id; rows = [Collections.Generic.List[object]]::new() } }
            $tickets[$k].rows.Add($row)
        }
        foreach ($k in @($tickets.Keys)) {
            $t = $tickets[$k]
            if ($t.rows.Count -lt $script:PqOfferLimit) { continue }
            $stuck = Get-PqStuckOffers -Rows $t.rows
            if ($null -eq $stuck) { continue }
            # The lift: the spec file was written after the newest counted run ended, so somebody edited the ticket.
            $mark = Get-PqDropMark -RepoPath ([string]$byKey[$t.repo].path) -TicketId $t.id
            $written = ConvertTo-PqRowTime ''
            if ($null -ne $mark -and $mark.specFile -and [IO.File]::Exists($mark.specFile)) { $written = [IO.File]::GetLastWriteTime($mark.specFile) }
            if ($written -gt (ConvertTo-PqRowTime $stuck.newest).AddSeconds($script:PqOfferLiftGraceSeconds)) { continue }
            $held.Add(@{ key = $k; repo = $t.repo; id = $t.id; passes = $stuck.passes; statuses = $stuck.statuses; newest = $stuck.newest })
        }
    }
    catch { }
    return @($held)
}
