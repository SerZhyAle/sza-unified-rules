# The idle-run series of a ticket - how many runs in a row handed it back without moving its
# status, and what the last one's outcome was (S2695).
#
# Dot-sourced, never invoked. Holds one process-scope cache and nothing else mutable.
#
# WHY IT IS DERIVED AND NOT STORED. A stored counter would have to be zeroed on a status move,
# which means catching that event in every catalog mutator; the run journals already record both
# the outcome and whether the status moved, so the series is a walk from the end of the journal to
# the first record that moved. That gives the reset for free, and it spans instances because every
# runs-*.jsonl is read - which is the half a per-process $processed list can never cover. The
# skip cache is not an option: the runner wipes it at every start by design, so a mark left there
# would not survive one launch.
#
# Compatible with PowerShell 5.1 and 7+, and safe to load under Set-StrictMode Latest.

. (Join-Path $PSScriptRoot '..\_profile.ps1')

# Fallbacks, used only when the consuming project's profile does not carry the keys.
# Get-SzaProfileValue THROWS on an unknown key - deliberately, so a typo cannot read as "not
# configured" - and the other adopting repositories have no runner.idle* block at all, so every
# read here has to survive its absence or this library would break them the moment it loads.
$script:IdleRunDefaultThreshold = 2
$script:IdleRunDefaultOutcomes = @(
    'ok', 'timeout', 'claim-lost', 'claim-lost-before-launch', 'no-progress-or-claim-lost', 'launch-failed'
)

$script:IdleRunMap = $null

function Get-IdleRunProfileValue {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)] $Default)
    try { return (Get-SzaProfileValue $Path) } catch { return $Default }
}

function Get-IdleRunPolicy {
    <#
    .SYNOPSIS
        The project's idle-run policy: the threshold, and which outcomes count as idle.
    #>
    $threshold = [int] (Get-IdleRunProfileValue -Path 'runner.idleRunThreshold' -Default $script:IdleRunDefaultThreshold)
    if ($threshold -lt 1) { $threshold = $script:IdleRunDefaultThreshold }
    $outcomes = @(Get-IdleRunProfileValue -Path 'runner.idleOutcomes' -Default $script:IdleRunDefaultOutcomes)
    if ($outcomes.Count -eq 0) { $outcomes = $script:IdleRunDefaultOutcomes }
    return [pscustomobject]@{ Threshold = $threshold; Outcomes = @($outcomes | ForEach-Object { [string] $_ }) }
}

function ConvertTo-IdleRunDate {
    <#
    .SYNOPSIS
        A journal timestamp as a DateTime, whatever shape it arrived in. An unreadable one sorts
        first (MinValue) rather than throwing - a row with no usable time must not be able to
        become the newest one and end a series that is still running.
    #>
    param($Value)
    if ($Value -is [datetime]) { return $Value }
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse([string] $Value, [ref] $parsed)) { return $parsed }
    return [datetime]::MinValue
}

function Format-IdleRunDate {
    # The sortable form the journal itself writes, so a series reports the same text the row holds.
    param($Value)
    $date = ConvertTo-IdleRunDate $Value
    if ($date -eq [datetime]::MinValue) { return '' }
    return $date.ToString('s')
}

function Get-IdleRunMap {
    <#
    .SYNOPSIS
        Ticket id -> the ticket's current idle series, for every ticket the journals mention.
    .PARAMETER Refresh
        Re-read the journals. Without it the first reading in this process is reused - this map is
        built on the hot path of every release-file write, and re-reading every journal there would
        put the cost of the whole run history on each status change.
    #>
    param([switch] $Refresh)
    if ($null -ne $script:IdleRunMap -and -not $Refresh) { return $script:IdleRunMap }

    $map = @{}
    $script:IdleRunMap = $map

    $runsDir = $null
    try { $runsDir = (Get-SzaPath 'queueRunsDir') } catch { return $map }
    if (-not $runsDir -or -not (Test-Path -LiteralPath $runsDir)) { return $map }

    $policy = Get-IdleRunPolicy
    $byId = @{}
    foreach ($file in (Get-ChildItem -LiteralPath $runsDir -Filter 'runs-*.jsonl' -ErrorAction SilentlyContinue)) {
        $lines = @()
        try { $lines = @(Get-Content -LiteralPath $file.FullName -Encoding UTF8 -ErrorAction Stop) } catch { continue }
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            # A half-written last line is normal: a run appends while this may be reading. Skipping
            # it silently is right - one unreadable record can only shorten a series, never invent
            # one, and refusing the whole file would hide every other ticket's history with it.
            $record = $null
            try { $record = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            if ($null -eq $record) { continue }
            $id = ''
            try { $id = [string] $record.id } catch { continue }
            if ([string]::IsNullOrWhiteSpace($id)) { continue }
            if (-not $byId.ContainsKey($id)) { $byId[$id] = New-Object System.Collections.Generic.List[object] }
            $byId[$id].Add($record)
        }
    }

    foreach ($id in $byId.Keys) {
        # Sorted by the record's own finishedAt, not by file order: two instances write two files,
        # and their rows interleave in time.
        #
        # Sorted as a DATE, never as the string. ConvertFrom-Json turns the journal's sortable
        # 's' timestamp into a DateTime, and casting that back to a string renders it in the
        # current culture - '09/06/2026 17:18:16' here - which sorts month-first and puts every
        # January after every December. Coerce both shapes to a DateTime instead.
        $ordered = @($byId[$id] | Sort-Object -Property @{ Expression = { ConvertTo-IdleRunDate $_.finishedAt } })
        $count = 0
        $lastOutcome = ''
        $lastFinishedAt = ''
        for ($i = $ordered.Count - 1; $i -ge 0; $i--) {
            $record = $ordered[$i]
            $moved = $false
            try { $moved = [bool] $record.moved } catch { $moved = $false }
            if ($moved) { break }
            $outcome = ''
            try { $outcome = [string] $record.outcome } catch { $outcome = '' }
            # An outcome the project does not call idle ends the series rather than being skipped
            # over: the series claims CONSECUTIVE idle runs, and stepping past a record that is not
            # one would join two separate series into a count no run ever produced.
            if ($policy.Outcomes -notcontains $outcome) { break }
            if ($count -eq 0) {
                $lastOutcome = $outcome
                try { $lastFinishedAt = Format-IdleRunDate $record.finishedAt } catch { $lastFinishedAt = '' }
            }
            $count++
        }
        $map[$id] = [pscustomobject]@{
            Id             = $id
            Count          = $count
            LastOutcome    = $lastOutcome
            LastFinishedAt = $lastFinishedAt
        }
    }

    return $map
}

function Get-IdleRunSeries {
    <#
    .SYNOPSIS
        One ticket's idle series. A ticket the journals never mention reports a zero count, never
        $null, so a caller can read .Count without testing for absence first.
    #>
    param([Parameter(Mandatory)][string] $Id, [switch] $Refresh)
    $map = Get-IdleRunMap -Refresh:$Refresh
    if ($map.ContainsKey($Id)) { return $map[$Id] }
    return [pscustomobject]@{ Id = $Id; Count = 0; LastOutcome = ''; LastFinishedAt = '' }
}

function Test-IdleRunHeld {
    <#
    .SYNOPSIS
        True when this ticket has reached the project's threshold and automatic ranking must pass
        it over. The comparison lives here so the ranker, the queue renderer and the runner cannot
        disagree about where the line is.
    #>
    param([Parameter(Mandatory)][string] $Id, [switch] $Refresh)
    $series = Get-IdleRunSeries -Id $Id -Refresh:$Refresh
    return ($series.Count -ge (Get-IdleRunPolicy).Threshold)
}
