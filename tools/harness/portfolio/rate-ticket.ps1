#requires -Version 7.0
<#
.SYNOPSIS
    Grade one ticket 0-9 with a rater model, or a list of tickets against expected grades (TASK-FLOW 0.32, rule 71;
    canon ticket S0139).

.DESCRIPTION
    The same prompt and answer check the dispatcher uses before a pass (portfolio/lib/rater.ps1,
    portfolio/rater/RATER_PROMPT.md), run by hand. Without -Write nothing is changed: the grade is printed. With
    -Write the spec's `**Complexity:**` line is rewritten as the dispatcher would (never a pinned line).

    -Anchors runs the rater over a JSON array of { "project": "<key>", "id": "<id>", "expected": <0-9> } and prints,
    per ticket, the expected grade, the rater's grade and whether they agree within +-1, then the agreement count.
    That is the report the rater of record is chosen from (Haiku against Sonnet). Every row is a model call: it is a
    release-tier run, made when the owner names it.

    The rater is the registry's `raters` record named by -Rater, else its first record, else the built-in
    `claude-haiku` record (command claude, model claude-haiku-5-5, no tools, the prompt on the standard input). -Model
    overrides the record's model for this run.

.PARAMETER Project
    A registered project key, or a project folder.
.PARAMETER Id
    The ticket id - the current one, an old id a prefix migration replaced, or the bare number (139, -0139) when
    one ticket of the project ends in it.
.PARAMETER Rater
    The name of a `raters` record of the registry.
.PARAMETER Model
    A model id that replaces the rater record's model for this run.
.PARAMETER Write
    Rewrite the spec's Complexity line with the grade.
.PARAMETER PromptOnly
    Print the prompt the rater would get and exit 0; no model is called.
.PARAMETER Anchors
    A JSON file of tickets with expected grades; prints the agreement report.

.EXAMPLE
    pwsh -NoProfile -File rate-ticket.ps1 -Project canon -Id S0139 -PromptOnly

.NOTES
    Exit codes: 0 graded (or the prompt printed, or the report printed); 1 the rater gave no valid answer, or the
    spec could not be written; 2 bad invocation - unknown project or ticket, no spec file, unknown rater, unreadable
    anchors file.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string] $Project = '',
    [string] $Id = '',
    [string] $Rater = '',
    [string] $Model = '',
    [switch] $Write,
    [switch] $PromptOnly,
    [string] $Anchors = ''
)
$ErrorActionPreference = 'Stop'
$lib = Join-Path $PSScriptRoot 'lib'
foreach ($f in 'paths', 'events', 'registry', 'loop', 'ledger-watch', 'agents') { . (Join-Path $lib "$f.ps1") }

function Stop-Rate([int]$Code, [string]$Message) {
    Write-Host "rate-ticket: $Message" -ForegroundColor $(if ($Code -eq 0) { 'Gray' } else { 'Red' })
    exit $Code
}

$regRes = Read-PqRegistry
$registry = $regRes.document

function Resolve-RateProject([string]$Value) {
    if ([IO.Directory]::Exists($Value)) { return (ConvertTo-PqFullPath $Value) }
    if ($null -ne $registry) {
        foreach ($r in @($registry.repos)) { if ([string](Get-PqValue $r 'key') -ceq $Value) { return [string]$r.path } }
    }
    return $null
}

function Get-RateRecord {
    $list = @(Get-PqRaters $registry)
    $rec = $null
    if ($Rater) {
        $rec = $list | Where-Object { [string](Get-PqValue $_ 'name') -ceq $Rater } | Select-Object -First 1
        if ($null -eq $rec) { Stop-Rate 2 "no rater record named '$Rater' in the registry" }
    }
    elseif ($list.Count -gt 0) { $rec = $list[0] }
    else { $rec = [pscustomobject]@{ name = 'claude-haiku'; command = 'claude'; model = 'claude-haiku-5-5' } }
    if ($Model) {
        $rec = $rec | Select-Object *
        $rec.model = $Model
    }
    return $rec
}

function Invoke-RateOne([string]$ProjectValue, [string]$TicketId, $Record) {
    $root = Resolve-RateProject $ProjectValue
    if (-not $root) { return @{ ok = $false; code = 2; why = "unknown project '$ProjectValue'" } }
    $info = Get-PqTicketLevelInfo -RepoPath $root -TicketId $TicketId
    if (-not $info.spec) { return @{ ok = $false; code = 2; why = "no spec file for $ProjectValue`:$TicketId" } }
    $prompt = Get-PqRaterPrompt -SpecPath $info.spec -Registry $registry
    if ($PromptOnly) { return @{ ok = $true; code = 0; prompt = $prompt; info = $info } }
    $run = Invoke-PqRaterRecord -Rater $Record -Prompt $prompt -WorkingDirectory ([IO.Path]::GetTempPath())
    if (-not $run.ok) { return @{ ok = $false; code = 1; why = "rater run failed: $($run.why)"; info = $info } }
    $ans = ConvertFrom-PqRaterAnswer $run.text
    if (-not $ans.ok) { return @{ ok = $false; code = 1; why = "rater answer $($ans.why)"; info = $info } }
    return @{ ok = $true; code = 0; answer = $ans; info = $info }
}

$record = Get-RateRecord
$raterName = "$([string](Get-PqValue $record 'name'))/$([string](Get-PqValue $record 'model'))"

if ($Anchors) {
    if (-not [IO.File]::Exists($Anchors)) { Stop-Rate 2 "no anchors file at $Anchors" }
    $rows = $null
    try { $rows = @(ConvertFrom-Json ([IO.File]::ReadAllText($Anchors))) } catch { Stop-Rate 2 "the anchors file is not JSON: $($_.Exception.Message)" }
    $agree = 0; $n = 0
    foreach ($row in $rows) {
        $n++
        $exp = [int]$row.expected
        $r = Invoke-RateOne ([string]$row.project) ([string]$row.id) $record
        if (-not $r.ok) { Write-Host ('{0}:{1}  expected {2}  -> {3}' -f $row.project, $row.id, $exp, $r.why); continue }
        $got = [int]$r.answer.score
        $ok = [Math]::Abs($got - $exp) -le 1
        if ($ok) { $agree++ }
        Write-Host ('{0}:{1}  expected {2}  rated {3} ({4})  {5}  {6}' -f $row.project, $row.id, $exp, $got, $r.answer.confidence, $(if ($ok) { 'agree' } else { 'DIFFER' }), $r.answer.reason)
    }
    Write-Host ("rater {0}: {1} of {2} within +-1" -f $raterName, $agree, $n)
    exit 0
}

if (-not $Project -or -not $Id) { Stop-Rate 2 'give -Project and -Id, or -Anchors <file>' }
$res = Invoke-RateOne $Project $Id $record
if ($PromptOnly -and $res.ok) { Write-Output $res.prompt; exit 0 }
if (-not $res.ok) { Stop-Rate $res.code $res.why }
$a = $res.answer
Write-Host ("{0}:{1} grade {2} ({3}, band {4}) by {5}: {6}" -f $Project, $res.info.id,$a.score, $a.confidence, (Get-SzaComplexityBand $a.score), $raterName, $a.reason)
if ($Write) {
    $line = Format-SzaComplexityLine -Score $a.score -Reason ("rated by {0} ({1}): {2}" -f ([string](Get-PqValue $record 'model')), $a.confidence, $(if ($a.reason) { $a.reason } else { 'no reason given' }))
    $wrote = Set-PqSpecComplexity -SpecPath $res.info.spec -Line $line
    if (-not $wrote) { Stop-Rate 1 'the line was not written (pinned, already the same, or the file is not UTF-8)' }
    Write-Host "written: $line"
}
exit 0
