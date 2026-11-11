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
                     questions the owner may answer
      -Id X          one ticket: its state in the project of the current folder (or -Project), and every OTHER
                     registered project whose ticket with that id is in a listed status. A bare number matches the
                     trailing digits of an id (21 -> S0021, SP-0021).
      -Status <name[,name]>
                     the ledger statuses to list (default BlockQuestions), comma-separated; any status name works

    Reads the ledger journals directly and the registry; writes nothing, locks nothing, launches nothing.

    Text output, one block per ticket (the prefix is BQ for BlockQuestions, else the ticket's status):
        BQ  <key>:<id>  p<priority>  <updated>  <name>
            file: <spec path, absolute>
            note: <the ledger's statusNote, one line>
    then the result line:
        quiz-list: <n> in <statuses> across <m> project(s)
    With -Id the result line is instead:
        quiz-list: id <X> here=<key>:<id>=<status|absent> blockquestions=<key:id,..|none>
        (waiting=... instead of blockquestions= when -Status lists more than BlockQuestions)
    -Json prints the same records as one JSON array (full notes) and no result line.

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

# ---- the registry (it may be missing: the current project is still answerable) ----
$repos = @()
try {
    $read = Read-PqRegistry
    if ($read.ok) { $repos = @($read.registry.repos) }
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
        $found.Add([pscustomobject][ordered]@{
            repo = $s.key; id = $row.Id; status = $row.Status; priority = $row.Priority; updated = $row.Updated
            name = $row.Name; file = (Join-Path $row.Root $row.File); note = $row.Note; here = [bool]$isHere
        })
        $null = $projectsWith.Add($s.key)
    }
}

$sorted = @($found | Sort-Object -Property @{ Expression = { -not $_.here } }, @{ Expression = 'priority'; Descending = $true }, 'repo', 'id')

if ($Json) {
    if ($sorted.Count -eq 0) { Write-Output '[]' } else { ConvertTo-Json -InputObject $sorted -Depth 4 -AsArray }
    exit 0
}

foreach ($t in $sorted) {
    $prefix = if ($defaultOnly) { 'BQ' } else { $t.status }
    Write-Host ("{0}  {1}:{2}  p{3}  {4}  {5}" -f $prefix, $t.repo, $t.id, $t.priority, $t.updated, $t.name)
    Write-Host ("    file: {0}" -f $t.file)
    if ($t.note) { Write-Host ("    note: {0}" -f $t.note) }
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
