#requires -Version 7.0
<#
.SYNOPSIS
    Read-only list of the tickets that wait for the owner's answers (status BlockQuestions) - the mechanical half of
    the spec-quiz skill.

.DESCRIPTION
    A quiz clears a ticket that left the queue because it needs the owner's call (spec-to-audit, Quiz mode). Ticket
    ids are only unique inside one project (S0021 exists in several registered projects at once), so the owner's
    "quiz S0021" is resolved here, from the ledgers, never from a filename or from memory.

    Scopes:
      (none)         the project holding the current folder
      -Project k     a registered key, or a folder
      -All           every project in the portfolio registry (repos.json), held or not: a held project still has
                     questions the owner may answer. Listed in registry rank order (rank, then array order - the
                     dispatcher's Get-PqRepoOrder), then priority; the current folder's project is not put first
      -Id X          one ticket: its state in the project of the current folder (or -Project), and every OTHER
                     registered project whose ticket with that id is in a listed status. A bare number matches the
                     trailing digits of an id (21 -> S0021, SP-0021).
      -Status <name[,name]>
                     the ledger statuses to list (default BlockQuestions), comma-separated; any status name works

    Reads the ledger journals directly and the registry; reads each listed ticket's spec file to report its
    question block (TASK-FLOW rule 7, S0026); writes nothing, locks nothing, launches nothing.

    Text output, one block per ticket (the prefix is BQ for BlockQuestions, else the ticket's status):
        BQ  <key>:<id>  p<priority>  <updated>  <name>
            file: <spec path, absolute>
            note: <the ledger's statusNote, one line>
            block: see below
    The `block:` line is the state of the ticket's newest question block - the `### Questions (v1, <date>)`
    section a pass entering BlockQuestions writes into the spec file (TASK-FLOW rule 7):
        block: current v1 <date>, <n> question(s)   the quiz asks from it, no re-research
        block: stale - <why>                          the quiz researches again, the block stays as it is
        block: answered <date>                        an answered block is never current (researches again)
        block: none - <why>                           no block, another version, or one that does not parse
    It is printed for every BlockQuestions ticket; for another listed status only when a block exists.
    then the result line:
        quiz-list: <n> in <statuses> across <m> project(s)
    With -Id the result line is instead:
        quiz-list: id <X> here=<key>:<id>=<status|absent> blockquestions=<key:id,..|none>
        (waiting=... instead of blockquestions= when -Status lists more than BlockQuestions)
    -Json prints the same records as one JSON array (full notes, the block's state) and no result line.

    Exit codes: 0 listed (an empty list is still 0 - a report, not a gate); 2 bad invocation, an unknown project, or
    no project at or above the current folder without -All.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string] $Project = '',
    [switch] $All,
    [string] $Id = '',
    [string[]] $Status = @('BlockQuestions'),
    [switch] $Json,
    [switch] $Help
)

if ($Help) {
    Get-Help -Name $PSCommandPath -Detailed | Out-String -Width 120 | Write-Host
    exit 0
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The ledger reader is shared with pq inbox (lib/inbox.ps1), which also loads registry.ps1 and ledger-watch.ps1.
. (Join-Path $PSScriptRoot 'lib/inbox.ps1')

function Stop-Quiz([int] $Code, [string] $Message) {
    [Console]::Error.WriteLine("quiz-list: $Message")
    exit $Code
}

# The statuses to list, parsed from -Status <name[,name]>; the default is BlockQuestions alone.
$statusList = @($Status -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($statusList.Count -eq 0) { Stop-Quiz 2 "-Status '$Status' names no status" }
$defaultOnly = ($statusList.Count -eq 1 -and $statusList[0] -ceq 'BlockQuestions')

function Test-IdMatch([string] $RowId, [string] $Wanted) {
    if ($RowId -ieq $Wanted) { return $true }
    if ($Wanted -match '^\d+$') {
        $m = [regex]::Match($RowId, '(\d+)$')
        return $m.Success -and [int64]$m.Groups[1].Value -eq [int64]$Wanted
    }
    return $false
}

# ---- the question block (TASK-FLOW 0.23 rule 7, canon ticket S0026) ----
# A pass entering BlockQuestions writes '### Questions (v1, <date>)' into the ticket's spec file; the quiz asks
# from a current block instead of researching the ticket again. This reader decides current-ness exactly as
# rule 7 states it: the newest block that does not carry ' - answered <date>' on its heading is current while
# (a) its date is not earlier than the ticket's latest entry into BlockQuestions - compared against the ledger
# row's `updated` day, the day the row last moved - and (b) every 'Q:' text of the statusNote appears in it as a
# question line, compared after trimming and collapsing runs of white space. Everything else (no block, no spec
# file, another version, a block that does not parse, only answered blocks) reads as "ask the pre-0.23 way":
# research, then ask. The comparison never rewrites a line; the block is the writer's record to keep.
function ConvertTo-QuizFlatText([string] $Text) {
    return [regex]::Replace([string]$Text, '\s+', ' ').Trim()
}

function Get-QuizQuestionBlock([string] $SpecPath, [string] $Note, [string] $Updated) {
    $res = [ordered]@{ state = 'none'; version = ''; date = ''; answered = $false; questions = @(); reason = 'no question block' }
    if ([string]::IsNullOrWhiteSpace($SpecPath) -or -not (Test-Path -LiteralPath $SpecPath -PathType Leaf)) {
        $res.reason = 'no spec file'; return [pscustomobject]$res
    }
    $lines = @()
    try { $lines = [IO.File]::ReadAllLines($SpecPath) } catch { $res.reason = 'the spec file cannot be read'; return [pscustomobject]$res }
    $heading = [regex]'^### Questions \((v\d+), (\d{4}-\d{2}-\d{2})\)(.*)$'   # '### Questions (v1, 2026-11-12)'
    $edge = [regex]'^(#{1,3}(\s|$))'                                        # a heading of level 3 or above ends it
    $qText = [regex]'^-\s+Q:\s*(.+?)\s*$'                                   # '- Q: <question>?'
    $blocks = [Collections.Generic.List[object]]::new()
    $open = $null
    foreach ($line in $lines) {
        $m = $heading.Match($line)
        if ($m.Success) {
            $open = [pscustomobject]@{ version = $m.Groups[1].Value; date = $m.Groups[2].Value; answered = [bool]($m.Groups[3].Value -match '-\s+answered\s+\d{4}-\d{2}-\d{2}'); questions = [Collections.Generic.List[string]]::new() }
            $blocks.Add($open)
            continue
        }
        if ($null -ne $open -and $edge.IsMatch($line)) { $open = $null; continue }
        if ($null -eq $open) { continue }
        $q = $qText.Match($line)
        if ($q.Success) { $open.questions.Add($q.Groups[1].Value) }
    }
    if ($blocks.Count -eq 0) { return [pscustomobject]$res }
    $freshest = @($blocks | Where-Object { -not $_.answered } | Sort-Object -Property date) | Select-Object -Last 1
    if (-not $freshest) {
        $last = @($blocks | Sort-Object -Property date) | Select-Object -Last 1
        $res.state = 'answered'; $res.version = $last.version; $res.date = $last.date; $res.answered = $true
        return [pscustomobject]$res
    }
    if ($freshest.version -cne 'v1') {
        $res.reason = ("version {0} is not v1" -f $freshest.version); return [pscustomobject]$res
    }
    $day = [regex]::Match($Updated, '(\d{4}-\d{2}-\d{2})')
    if ($day.Success -and [string]$freshest.date -lt $day.Groups[1].Value) {
        $res.state = 'stale'; $res.version = $freshest.version; $res.date = $freshest.date
        $res.reason = ("dated {0}, older than the block entry {1}" -f $freshest.date, $day.Groups[1].Value)
        return [pscustomobject]$res
    }
    $flatQs = @($freshest.questions | ForEach-Object { ConvertTo-QuizFlatText $_ })
    foreach ($m in [regex]::Matches($Note, '(?<![A-Za-z0-9])Q:\s*([^?]*\?)')) {
        $wanted = ConvertTo-QuizFlatText $m.Groups[1].Value
        if ($flatQs -cnotcontains $wanted) {
            $res.state = 'stale'; $res.version = $freshest.version; $res.date = $freshest.date
            $res.reason = ("missing the note's Q: '{0}'" -f $wanted)
            return [pscustomobject]$res
        }
    }
    $res.state = 'current'; $res.version = $freshest.version; $res.date = $freshest.date
    $res.questions = @($freshest.questions)
    return [pscustomobject]$res
}

# ---- the registry (it may be missing: the current project is still answerable) ----
$repos = @()
$rankOf = @{}   # registry key -> position in Get-PqRepoOrder (rank, then array order)
try {
    $read = Read-PqRegistry
    if ($read.ok) {
        $repos = @($read.registry.repos)
        $pos = 0
        foreach ($o in @(Get-PqRepoOrder $read.registry)) { $rankOf[[string]$o.key] = $pos; $pos++ }
    }
}
catch { $repos = @() }
$keys = if ($repos.Count) { (@($repos | ForEach-Object { [string]$_.key }) -join ', ') } else { 'none registered' }

function Get-KeyForRoot([string] $Root) {
    $k = ConvertTo-PqPathKey $Root
    $hit = @($repos | Where-Object { (ConvertTo-PqPathKey ([string]$_.path)) -ceq $k }) | Select-Object -First 1
    if ($hit) { return [string]$hit.key }
    return (Split-Path -Leaf $Root)
}

# ---- the current / named project ----
$hereRoot = $null
if ($Project) {
    $rec = @($repos | Where-Object { [string]$_.key -ieq $Project }) | Select-Object -First 1
    if ($rec) { $hereRoot = [string]$rec.path }
    elseif (Test-Path -LiteralPath $Project -PathType Container) { $hereRoot = (Resolve-Path -LiteralPath $Project).Path }
    else { Stop-Quiz 2 "unknown project '$Project' - neither a registered key nor a folder (registered: $keys)" }
}
elseif (-not $All -or $Id) {
    $dir = (Get-Location).Path
    while ($dir) {
        if ((Test-Path -LiteralPath (Join-Path $dir '.sza-profile.json') -PathType Leaf) -or (Test-Path -LiteralPath (Join-Path $dir '.sza-canon.json') -PathType Leaf)) { $hereRoot = $dir; break }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    if (-not $hereRoot -and -not $All) { Stop-Quiz 2 "no project here - no .sza-profile.json or .sza-canon.json at or above $((Get-Location).Path). Pass -Project <key|path> or -All (registered: $keys)" }
}
$hereKey = if ($hereRoot) { Get-KeyForRoot $hereRoot } else { $null }

# ---- gather ----
$scope = [Collections.Generic.List[object]]::new()   # @{ key; root }
if ($All -or $Id) {
    foreach ($r in $repos) { $scope.Add(@{ key = [string]$r.key; root = [string]$r.path }) }
}
if ($hereRoot -and -not @($scope | Where-Object { (ConvertTo-PqPathKey $_.root) -ceq (ConvertTo-PqPathKey $hereRoot) }).Count) {
    $scope.Insert(0, @{ key = $hereKey; root = $hereRoot })
}
if (-not ($All -or $Id)) {
    $scope.Clear()
    $scope.Add(@{ key = $hereKey; root = $hereRoot })
}

$found = [Collections.Generic.List[object]]::new()
$hereState = 'absent'
$hereTicket = $null
$projectsWith = [Collections.Generic.HashSet[string]]::new()
foreach ($s in $scope) {
    if (-not (Test-Path -LiteralPath $s.root -PathType Container)) { continue }
    try { $rows = Read-PqLedgerRows $s.root } catch { [Console]::Error.WriteLine("quiz-list: $($s.key) skipped - $($_.Exception.Message)"); continue }
    $isHere = $hereRoot -and ((ConvertTo-PqPathKey $s.root) -ceq (ConvertTo-PqPathKey $hereRoot))
    if ($Id -and $isHere) {
        $mine = @($rows | Where-Object { Test-IdMatch $_.Id $Id }) | Select-Object -First 1
        if ($mine) { $hereState = $mine.Status; $hereTicket = $mine }
    }
    foreach ($row in $rows) {
        if ($statusList -notcontains $row.Status) { continue }
        if ($Id -and -not (Test-IdMatch $row.Id $Id)) { continue }
        $specFile = Join-Path $row.Root $row.File
        $found.Add([pscustomobject][ordered]@{
            repo = $s.key; rank = $(if ($rankOf.ContainsKey($s.key)) { $rankOf[$s.key] } else { $rankOf.Count }); id = $row.Id; status = $row.Status; priority = $row.Priority; updated = $row.Updated
            name = $row.Name; file = $specFile; note = $row.Note; here = [bool]$isHere
            block = (Get-QuizQuestionBlock $specFile $row.Note $row.Updated)
        })
        $null = $projectsWith.Add($s.key)
    }
}

# -All is one portfolio sitting: projects in registry rank (an unregistered current project last), then priority.
# Every other scope keeps the current project first.
$sortKeys = if ($All -and -not $Id) { @('rank', 'repo', @{ Expression = 'priority'; Descending = $true }, 'id') }
else { @(@{ Expression = { -not $_.here } }, @{ Expression = 'priority'; Descending = $true }, 'repo', 'id') }
$sorted = @($found | Sort-Object -Property $sortKeys)

if ($Json) {
    # Depth 6: the records hold the block object with its questions array inside.
    if ($sorted.Count -eq 0) { Write-Output '[]' } else { ConvertTo-Json -InputObject $sorted -Depth 6 }
    exit 0
}

foreach ($t in $sorted) {
    $prefix = if ($defaultOnly) { 'BQ' } else { $t.status }
    Write-Host ("{0}  {1}:{2}  p{3}  {4}  {5}" -f $prefix, $t.repo, $t.id, $t.priority, $t.updated, $t.name)
    Write-Host ("    file: {0}" -f $t.file)
    if ($t.note) { Write-Host ("    note: {0}" -f $t.note) }
    $blk = $t.block
    if ($t.status -ceq 'BlockQuestions' -or $blk.state -cne 'none') {
        $line = switch ($blk.state) {
            'current' { "current {0} {1}, {2} question(s)" -f $blk.version, $blk.date, $blk.questions.Count }
            'stale'   { "stale - {0}" -f $blk.reason }
            'answered' { "answered {0}" -f $blk.date }
            default  { "none - {0}" -f $blk.reason }
        }
        Write-Host ("    block: {0}" -f $line)
    }
}
if ($Id) {
    $hereText = if ($hereKey) { '{0}:{1}={2}' -f $hereKey, $(if ($hereTicket) { $hereTicket.Id } else { $Id }), $hereState } else { 'no-current-project' }
    $waiting = if ($sorted.Count) { (@($sorted | ForEach-Object { '{0}:{1}' -f $_.repo, $_.id }) -join ',') } else { 'none' }
    $waitingLabel = if ($defaultOnly) { 'blockquestions' } else { 'waiting' }
    Write-Host ("quiz-list: id {0} here={1} {2}={3}" -f $Id, $hereText, $waitingLabel, $waiting)
}
else {
    Write-Host ("quiz-list: {0} in {1} across {2} project(s)" -f $sorted.Count, ($statusList -join ','), $projectsWith.Count)
}
exit 0
