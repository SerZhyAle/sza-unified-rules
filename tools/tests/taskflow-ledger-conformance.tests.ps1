#requires -Version 7.0
<#
.SYNOPSIS
  Fast cases of S0083 (TASK-FLOW 0.27 rules 7, 9, 65, 66 and 68 against tools/harness): the ledger-side rules that
  had no test of their own. Function calls on dot-sourced libraries, and three short child processes of the
  harness's own tools. Writes only into a throwaway repository under the system temp directory.
.DESCRIPTION
  Cases:
    rule 9  - a `**Depends on:**` line and `Blocker:` tokens are read TOGETHER: a line that names no id no longer
              silences the tokens of the note, a line with ids and a token gives both, the spec's own id is dropped
    rule 9  - the qualified token is read in the spec file and in the note, and a quoted example is not read
    rule 7  - the Q: and DO: tokens of a BlockQuestions note are literal: "need to do: x" and a lowercase "q:" are
              prose and refused; `Q: ..?` and `DO: <action>` pass (check-block-note.ps1 as a child process)
    rule 3  - update.ps1 -Title writes the optional `title` of a row, trimmed, and changes neither name nor status
    rule 9  - the BlockByOtherTask refusal names the channels of the canon ticket form: the note for a local
              token, the note or the spec file for a qualified one, and no "section 10" (a text match on
              check-block-note.ps1)
    rule 66 - a start that finds no free worker slot is a valid start that did not run: the loop returns 3, not 2
    rule 65 - a file '<id>_<slug>.md' in the specs directory with no row is listed with its header status (else
              Draft) and a lowercase-hyphen name; a file whose id is in the journal, the archive or the burned list,
              a file in a subdirectory, a 'spec_' slug and a non-ticket name are not; one real registration goes
              through the repository's own insert.ps1 and leaves a row that names the file
    rule 68 - a row whose file is missing is repointed to the one same-named file of the other directory (both
              directions, and from a third place); two candidates or none leave the row; one real repoint goes
              through update.ps1 -File and changes `file` only
  Exit 0 when every case passed, 1 on any failure. Expected wall time: under 5 s.
#>
[CmdletBinding()]
param([switch] $KeepScratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$Harness = Join-Path $SourceRoot 'tools\harness'
$Lib = Join-Path $Harness 'portfolio\lib'
$pwshExe = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Assert-Equal($Actual, $Expected, [string] $What) {
    if ("$Actual" -cne "$Expected") { throw "$What - expected '$Expected', got '$Actual'" }
}
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('tf-ledger-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null
$savedPortfolio = $env:SZA_PORTFOLIO_ROOT
$savedProject = $env:SZA_PROJECT_ROOT
$env:SZA_PORTFOLIO_ROOT = Join-Path $scratch 'portfolio'

function Write-Utf8([string] $Path, [string] $Text) {
    $dir = [IO.Path]::GetDirectoryName($Path)
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
function New-Row([string] $Id, [string] $Name, [string] $File, [string] $Status = 'Draft') {
    return ([ordered]@{ id = $Id; name = $Name; status = $Status; priority = 50; file = $File; created = '2026-11-15'; updated = '2026-11-15 00:00' } | ConvertTo-Json -Compress)
}
function Invoke-Tool([string] $Root, [string] $Script, [string[]] $Arguments) {
    $psi = [Diagnostics.ProcessStartInfo]::new($pwshExe)
    foreach ($a in (@('-NoProfile', '-File', $Script) + $Arguments)) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $Root
    $psi.Environment['SZA_PROJECT_ROOT'] = $Root
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(60000)) { try { $p.Kill($true) } catch { } ; throw "$Script timed out" }
    $p.WaitForExit()
    return @{ code = $p.ExitCode; out = ([string]$o.Result + [string]$e.Result) }
}

try {
    # ------------------------------------------------------------------ rule 9
    . (Join-Path $Harness '_profile.ps1')
    . (Join-Path $Harness 'spec_catalog\_blocker-links.ps1')

    Run-Case 'rule 9: a Depends-on line that names no id does not silence the note token' {
        $spec = "# S0001_x`n`n**Status:** Draft`n**Depends on:** none yet`n"
        $ids = @(Get-BlockerLinks -SpecText $spec -StatusNote 'waits. Blocker: S0004' -SelfId S0001)
        Assert-Equal ($ids -join ',') 'S0004' 'the token of the note is read beside an empty line'
    }
    Run-Case 'rule 9: the line and the tokens are a union, deduplicated, without the spec itself' {
        $spec = "# S0001_x`n`n**Depends on:** S0002, S0003`n`n## 10. Links`n`nBlocker: S0003`nБлокер: S0005`nBlocker: S0001`n"
        $ids = @(Get-BlockerLinks -SpecText $spec -StatusNote 'waiting. Blocker: S0006' -SelfId S0001)
        Assert-Equal ($ids -join ',') 'S0002,S0003,S0005,S0006' 'line ids + section-10 tokens + note token'
    }
    Run-Case 'rule 9: with no line the tokens alone still read, and prose ids stay mentions' {
        $spec = "# S0001_x`n`n## 10. Links`n`nThe consumers are S0007 and S0008; related to S0009.`nBlocker: S0004`n"
        Assert-Equal ((@(Get-BlockerLinks -SpecText $spec -SelfId S0001)) -join ',') 'S0004' 'only the token is a claim'
    }
    Run-Case 'rule 9: the qualified token is read in the spec and in the note; a quoted example is not' {
        $spec = "Blocker: hub:L0012`nwrite ``Blocker: fms-a:S4466`` on its own line`nthe form <Blocker: fms-web:S0001> is an example`n"
        $pairs = @(Get-QualifiedBlockerLinks -SpecText $spec -StatusNote 'waits. Blocker: Fms-A:S4466')
        Assert-Equal ($pairs -join ',') 'hub:L0012,fms-a:S4466' 'plain spec token, note token lowercased, examples ignored'
    }

    # ------------------------------------------------------------------ rule 7
    $gateRoot = Join-Path $scratch 'gate'
    Write-Utf8 (Join-Path $gateRoot '.sza-profile.json') '{}'
    Write-Utf8 (Join-Path $gateRoot 'PLAN\spec-catalog.jsonl') ((New-Row 'S0001' 'gate' 'PLAN/S0001_gate.md') + "`n")
    Write-Utf8 (Join-Path $gateRoot 'PLAN\S0001_gate.md') "# S0001_gate`n`n**Status:** Draft`n"
    $gate = Join-Path $Harness 'spec_catalog\check-block-note.ps1'
    function Test-QuestionsNote([string] $Note) {
        $r = Invoke-Tool $gateRoot $gate @('-Id', 'S0001', '-NewStatus', 'BlockQuestions', '-StatusNote', $Note, '-NoteSupplied')
        return $r.code
    }
    Run-Case 'rule 7: Q: and DO: are literal tokens - prose that merely contains the letters is refused' {
        Assert-Equal (Test-QuestionsNote 'which package hosts the first compile? Q: which package number?') 0 'a Q: token ending in ?'
        Assert-Equal (Test-QuestionsNote 'DO: create the Play Console app and paste the applicationId') 0 'a DO: token'
        Assert-Equal (Test-QuestionsNote 'the owner still has to do: the device pairing') 1 'lowercase "do:" is prose'
        Assert-Equal (Test-QuestionsNote 'TODO: pair the device') 1 'TODO: is not a DO: token'
        Assert-Equal (Test-QuestionsNote 'q: which package number?') 1 'lowercase "q:" is prose'
    }

    Run-Case 'rule 9: the BlockByOtherTask refusal names the note and the spec file, not a section 10' {
        $text = [IO.File]::ReadAllText($gate)
        Assert-That ($text -match 'records no blocker in a directional channel') 'the refusal headline is gone'
        Assert-That ($text -match 'a local token, in the note \(-StatusNote\)') 'the local channel does not name the note'
        Assert-That ($text -match 'a cross-repo token, in the note or the spec file') 'the qualified channel does not name the spec file'
        Assert-That ($text -notmatch 'in section 10') 'the refusal still sends the reader to section 10'
    }

    # ------------------------------------------------------------------ rule 3
    Run-Case 'rule 3: update.ps1 -Title writes the optional title, trimmed, and changes neither name nor status' {
        # SZA_PQ_IN_SYNC keeps the catalog write from starting the portfolio sync child: one process, not two.
        $savedInSync = $env:SZA_PQ_IN_SYNC
        $env:SZA_PQ_IN_SYNC = '1'
        try { $r = Invoke-Tool $gateRoot (Join-Path $Harness 'spec_catalog\update.ps1') @('-Id', 'S0001', '-Title', '  Gate fixture ticket  ') }
        finally { $env:SZA_PQ_IN_SYNC = $savedInSync }
        Assert-Equal $r.code 0 "update.ps1 -Title: $($r.out)"
        $row = Get-Content -LiteralPath (Join-Path $gateRoot 'PLAN\spec-catalog.jsonl') -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json } | Select-Object -First 1
        Assert-Equal $row.title 'Gate fixture ticket' 'the title, trimmed'
        Assert-Equal $row.name 'gate' 'the name is untouched'
        Assert-Equal $row.status 'Draft' 'the status is untouched'
    }

    # ------------------------------------------------------------------ rule 66
    Run-Case 'rule 66: no free worker slot is a valid start that did not run - exit 3, not 2' {
        $loop = [IO.File]::ReadAllText((Join-Path $Lib 'loop.ps1'))
        $m = [regex]::Match($loop, "Write-PqError 'NoWorkerSlot'[^\r\n]*\r?\n\s*return (?<c>\d)")
        Assert-That $m.Success 'the NoWorkerSlot refusal is followed by a return'
        Assert-Equal $m.Groups['c'].Value '3' 'the NoWorkerSlot exit code'
    }

    # ------------------------------------------------------------------ rules 65 and 68
    . (Join-Path $Lib 'events.ps1')
    . (Join-Path $Lib 'picker.ps1')
    . (Join-Path $Lib 'queue-file.ps1')

    $repo = Join-Path $scratch 'repo'
    Write-Utf8 (Join-Path $repo '.sza-profile.json') '{"paths":{"specsDir":"PLAN","specArchiveDir":"PLAN/DONE"},"grammar":{"specFilePattern":"^PLAN/(DONE/)?S\\d{4}_(?!spec_)"}}'
    $rows = @(
        (New-Row 'S0001' 'known' 'PLAN/S0001_known.md'),
        (New-Row 'S0002' 'moved-out' 'PLAN/S0002_moved-out.md' 'Implemented'),
        (New-Row 'S0003' 'moved-back' 'PLAN/DONE/S0003_moved-back.md'),
        (New-Row 'S0004' 'lost' 'PLAN/S0004_lost.md'),
        (New-Row 'S0005' 'two' 'PLAN/other/S0005_two.md'),
        (New-Row 'S0006' 'third' 'PLAN/other/S0006_third.md')
    )
    Write-Utf8 (Join-Path $repo 'PLAN\spec-catalog.jsonl') (($rows -join "`n") + "`n")
    Write-Utf8 (Join-Path $repo 'PLAN\spec-catalog-archive.jsonl') ((New-Row 'S0012' 'archived' 'PLAN/DONE/S0012_archived.md' 'Archived') + "`n")
    Write-Utf8 (Join-Path $repo 'PLAN\spec-catalog-burned-ids.jsonl') ('{"id":"S0013","reason":"fixture","burned":"2026-11-15"}' + "`n")
    foreach ($f in 'PLAN\S0001_known.md', 'PLAN\DONE\S0002_moved-out.md', 'PLAN\S0003_moved-back.md', 'PLAN\S0005_two.md', 'PLAN\DONE\S0005_two.md', 'PLAN\DONE\S0006_third.md') {
        Write-Utf8 (Join-Path $repo $f) "# $([IO.Path]::GetFileNameWithoutExtension($f))`n`n**Status:** Draft`n"
    }
    # rule 65 inputs
    Write-Utf8 (Join-Path $repo 'PLAN\S0010_new-thing.md') "# S0010_new-thing`n`n**Status:** Approved`n"
    Write-Utf8 (Join-Path $repo 'PLAN\S0011_Other_Thing.md') "# S0011_Other_Thing`n`nno header status here`n"
    Write-Utf8 (Join-Path $repo 'PLAN\S0012_archived.md') "# S0012`n`n**Status:** Draft`n"
    Write-Utf8 (Join-Path $repo 'PLAN\S0013_burned.md') "# S0013`n`n**Status:** Draft`n"
    Write-Utf8 (Join-Path $repo 'PLAN\DONE\S0014_in-archive-dir.md') "# S0014`n`n**Status:** Draft`n"
    Write-Utf8 (Join-Path $repo 'PLAN\S0015_spec_style.md') "# S0015`n`n**Status:** Draft`n"
    Write-Utf8 (Join-Path $repo 'PLAN\notes.md') "# notes`n"
    $registryRepo = [pscustomobject]@{ key = 'scratch'; path = $repo; enabled = $true }

    Run-Case 'rule 65: the files with no row are listed with their header status and a lowercase-hyphen name' {
        $listed = @(Register-PqTicketFiles -Repo $registryRepo -HarnessRoot $Harness -List)
        $byId = @{}; foreach ($l in $listed) { $byId[[string]$l.id] = $l }
        Assert-Equal (($byId.Keys | Sort-Object) -join ',') 'S0010,S0011' 'only the two files with no row'
        Assert-Equal $byId['S0010'].status 'Approved' 'the header status of S0010'
        Assert-Equal $byId['S0011'].status 'Draft' 'a file with no header status is a Draft'
        Assert-Equal $byId['S0010'].file 'PLAN/S0010_new-thing.md' 'the repository-relative file'
    }
    Run-Case 'rule 65: one real registration goes through insert.ps1 and leaves a row that names the file' {
        $one = Join-Path $scratch 'one'
        Write-Utf8 (Join-Path $one '.sza-profile.json') '{}'
        Write-Utf8 (Join-Path $one 'PLAN\spec-catalog.jsonl') ''
        Write-Utf8 (Join-Path $one 'PLAN\S0010_New_Thing.md') "# S0010_New_Thing`n`n**Status:** Approved`n"
        $r = @(Register-PqTicketFiles -Repo ([pscustomobject]@{ key = 'one'; path = $one }) -HarnessRoot $Harness)
        Assert-Equal $r.Count 1 'one file tried'
        $why = if ($r[0].Contains('err')) { [string]$r[0].err } else { '' }
        Assert-That ([bool]$r[0].ok) "insert.ps1 refused: $why"
        $row = (Get-Content -LiteralPath (Join-Path $one 'PLAN\spec-catalog.jsonl') -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json }) | Select-Object -First 1
        Assert-Equal $row.id 'S0010' 'the id of the file'
        Assert-Equal $row.name 'new-thing' 'the slug lowercased, joined by hyphens'
        Assert-Equal $row.status 'Approved' 'the status of the header'
        Assert-Equal ($row.file -replace '\\', '/') 'PLAN/S0010_New_Thing.md' 'the file it names'
        $sourceProp = $row.PSObject.Properties['source']
        Assert-That ($null -ne $sourceProp -and [string]$sourceProp.Value -ceq 'import') 'the row does not say source import (TASK-FLOW rule 3)'
        Assert-Equal @(Register-PqTicketFiles -Repo ([pscustomobject]@{ key = 'one'; path = $one }) -HarnessRoot $Harness -List).Count 0 'a second run finds nothing'
    }
    Run-Case 'rule 65: a repository with no profile or no ledger is not given one' {
        $bare = Join-Path $scratch 'bare'
        Write-Utf8 (Join-Path $bare 'PLAN\S0010_x.md') "# x`n"
        Assert-Equal @(Register-PqTicketFiles -Repo ([pscustomobject]@{ key = 'bare'; path = $bare }) -HarnessRoot $Harness -List).Count 0 'no profile'
        Write-Utf8 (Join-Path $bare '.sza-profile.json') '{}'
        Assert-Equal @(Register-PqTicketFiles -Repo ([pscustomobject]@{ key = 'bare'; path = $bare }) -HarnessRoot $Harness -List).Count 0 'a profile and no ledger'
        Assert-That (-not (Test-Path -LiteralPath (Join-Path $bare 'PLAN\spec-catalog.jsonl'))) 'no ledger was created'
    }
    Run-Case 'rule 68: a row whose file moved is repointed to the one same-named file, in both directions and from a third place' {
        $listed = @(Repair-PqTicketFileRefs -Repo $registryRepo -HarnessRoot $Harness -List)
        $byId = @{}; foreach ($l in $listed) { $byId[[string]$l.id] = $l }
        Assert-Equal (($byId.Keys | Sort-Object) -join ',') 'S0002,S0003,S0006' 'S0001 exists, S0004 has no candidate, S0005 has two'
        Assert-Equal $byId['S0002'].to 'PLAN/DONE/S0002_moved-out.md' 'specs -> archive'
        Assert-Equal $byId['S0003'].to 'PLAN/S0003_moved-back.md' 'archive -> specs'
        Assert-Equal $byId['S0006'].to 'PLAN/DONE/S0006_third.md' 'a file named in neither directory is found in one of them'
    }
    Run-Case 'rule 68: a repository whose two directories are one has nothing to relink' {
        $same = Join-Path $scratch 'same'
        Write-Utf8 (Join-Path $same '.sza-profile.json') '{"paths":{"specsDir":"PLAN","specArchiveDir":"PLAN"}}'
        Write-Utf8 (Join-Path $same 'PLAN\spec-catalog.jsonl') ((New-Row 'S0001' 'gone' 'PLAN/S0001_gone.md') + "`n")
        Assert-Equal @(Repair-PqTicketFileRefs -Repo ([pscustomobject]@{ key = 'same'; path = $same }) -HarnessRoot $Harness -List).Count 0 'equal directories'
    }
    Run-Case 'rule 68: one real repoint goes through update.ps1 -File and changes the file column only' {
        # A repository of its own: update.ps1 validates every row it writes beside, so the rows must be grammar-valid.
        $two = Join-Path $scratch 'two'
        Write-Utf8 (Join-Path $two '.sza-profile.json') '{"paths":{"specsDir":"PLAN","specArchiveDir":"PLAN/DONE"},"grammar":{"specFilePattern":"^PLAN/(DONE/)?S\\d{4}_(?!spec_)"}}'
        $twoRows = @((New-Row 'S0002' 'moved-out' 'PLAN/S0002_moved-out.md' 'Implemented'), (New-Row 'S0004' 'lost' 'PLAN/S0004_lost.md'))
        Write-Utf8 (Join-Path $two 'PLAN\spec-catalog.jsonl') (($twoRows -join "`n") + "`n")
        Write-Utf8 (Join-Path $two 'PLAN\DONE\S0002_moved-out.md') "# S0002_moved-out`n`n**Status:** Implemented`n"
        $twoRepo = [pscustomobject]@{ key = 'two'; path = $two }
        $r = @(Repair-PqTicketFileRefs -Repo $twoRepo -HarnessRoot $Harness)
        Assert-Equal $r.Count 1 'one row tried (S0004 has no candidate)'
        $why = if ($r[0].Contains('err')) { [string]$r[0].err } else { '' }
        Assert-That ([bool]$r[0].ok) "update.ps1 refused: $why"
        Assert-Equal $r[0].from 'PLAN/S0002_moved-out.md' 'from'
        Assert-Equal $r[0].to 'PLAN/DONE/S0002_moved-out.md' 'to'
        $after = Get-Content -LiteralPath (Join-Path $two 'PLAN\spec-catalog.jsonl') -Encoding UTF8 | Where-Object { $_ -match '"id":"S0002"' } | ForEach-Object { $_ | ConvertFrom-Json }
        Assert-Equal ($after.file -replace '\\', '/') 'PLAN/DONE/S0002_moved-out.md' 'the new file'
        Assert-Equal $after.status 'Implemented' 'the status is untouched'
        Assert-Equal $after.name 'moved-out' 'the name is untouched'
        Assert-Equal @(Repair-PqTicketFileRefs -Repo $twoRepo -HarnessRoot $Harness -List).Count 0 'a second look finds nothing to do'
    }
}
finally {
    $env:SZA_PORTFOLIO_ROOT = $savedPortfolio
    $env:SZA_PROJECT_ROOT = $savedProject
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
    else { Write-Host "scratch kept: $scratch" }
}

Write-Host ''
Write-Host ("run={0} passed={1} failed={2}" -f $run, $passed, $failed)
if ($failed -gt 0) { exit 1 }
exit 0
