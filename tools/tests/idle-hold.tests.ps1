#requires -Version 7.0
<#
.SYNOPSIS
    Cases for the idle hold of a ticket and its lift (TASK-FLOW rule 24): batch/_idle-runs.ps1.
.DESCRIPTION
    The library is loaded against a scratch project under the system temp directory. No runner, no child
    process, no git; nothing outside the scratch directory is written. Cases: 1 two counted unmoved runs hold and a
    moved run ends the series; 2 limit-hit, claim-lost-before-launch and launch-failed neither count nor end a series;
    3 a spec file written more than 60 s after the newest counted run lifts the hold; 4 every doubt keeps the hold;
    5 one edit earns one pass; 6 the picker, the plan-file marker and the back-link writer are wired (read as text);
    7 the panel's walk applies the same lift (read as text); 8 this repository's R0 and the scaffold leave Implemented
    out (read as text); 9 repeat parks count and a forward move resets; 10 the three-row window
    accepts a prior statusBefore and ignores the fourth preceding row.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\harness'))
$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}
$clock = [Diagnostics.Stopwatch]::StartNew()
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('idle-hold-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$proj = Join-Path $scratch 'proj'
$journal = Join-Path $proj 'temp\spec-queue\runs-a.jsonl'
New-Item -ItemType Directory -Path (Join-Path $proj 'PLAN'), (Split-Path -Parent $journal) | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Row([string] $Id, [string] $At, [string] $Outcome, [bool] $Moved = $false, [string] $Before = 'Draft', [string] $After = 'Draft') {
    return ('{{"id":"{0}","statusBefore":"{4}","statusAfter":"{5}","moved":{1},"outcome":"{2}","finishedAt":"{3}"}}' -f $Id, $Moved.ToString().ToLowerInvariant(), $Outcome, $At, $Before, $After)
}
function New-Spec([string] $Name, [string] $WrittenAt) {
    $path = Join-Path $proj "PLAN\$Name.md"
    [IO.File]::WriteAllText($path, "# $Name`n", $utf8)
    (Get-Item -LiteralPath $path).LastWriteTime = [datetime] $WrittenAt
    return $path
}
try {
    # The library resolves the project root when it loads, so it is set first.
    $env:SZA_PROJECT_ROOT = $proj
    . (Join-Path $root 'batch\_idle-runs.ps1')
    [IO.File]::WriteAllLines($journal, [string[]]@(
        (Row 'T1' '2026-11-12T10:00:00' 'ok'), (Row 'T1' '2026-11-12T11:00:00' 'timeout'),
        (Row 'T2' '2026-11-12T10:00:00' 'ok'), (Row 'T2' '2026-11-12T11:00:00' 'ok'), (Row 'T2' '2026-11-12T12:00:00' 'ok' $true),
        (Row 'T3' '2026-11-12T10:00:00' 'ok'), (Row 'T3' '2026-11-12T11:00:00' 'claim-lost-before-launch'),
        (Row 'T3' '2026-11-12T12:00:00' 'launch-failed'), (Row 'T3' '2026-11-12T13:00:00' 'limit-hit'),
        (Row 'T4' '2026-11-12T10:00:00' 'claim-lost-before-launch'), (Row 'T4' '2026-11-12T11:00:00' 'claim-lost-before-launch'),
        (Row 'T5' '2026-11-12T10:00:00' 'ok'), (Row 'T5' '2026-11-12T11:00:00' 'launch-failed'), (Row 'T5' '2026-11-12T12:00:00' 'ok'),
        (Row 'T6' 'not a time' 'ok'), (Row 'T6' 'not a time' 'ok')
    ), $utf8)
    $null = Get-IdleRunMap -Refresh
    Run-Case '1. two counted unmoved runs hold; a moved run ends the series' {
        Assert-That ((Get-IdleRunSeries -Id 'T1').Count -eq 2 -and (Test-IdleRunHeld -Id 'T1')) 'ok then timeout must hold'
        Assert-That ((Get-IdleRunSeries -Id 'T2').Count -eq 0 -and -not (Test-IdleRunHeld -Id 'T2')) 'a moved newest run must end the series'
        Assert-That (-not (Test-IdleRunHeld -Id 'NEVER')) 'a ticket the journals never mention is not held'
    }
    Run-Case '2. limit-hit, claim-lost-before-launch and launch-failed neither count nor end a series' {
        Assert-That ((Get-IdleRunSeries -Id 'T3').Count -eq 1 -and -not (Test-IdleRunHeld -Id 'T3')) 'three neutral runs after one ok must leave the count at 1'
        Assert-That ((Get-IdleRunSeries -Id 'T4').Count -eq 0 -and -not (Test-IdleRunHeld -Id 'T4')) 'two claims lost before launch must not hold'
        Assert-That ((Get-IdleRunSeries -Id 'T5').Count -eq 2 -and (Test-IdleRunHeld -Id 'T5')) 'a neutral run between two counted ones must be stepped over'
    }
    Run-Case '3. a spec file written more than 60 s after the newest counted run lifts the hold' {
        Assert-That (-not (Test-IdleRunHeld -Id 'T1' -SpecPath (New-Spec 't1-late' '2026-11-12T11:02:00'))) 'an edit two minutes after the run must lift the hold'
        Assert-That (Test-IdleRunHeld -Id 'T1' -SpecPath (New-Spec 't1-grace' '2026-11-12T11:00:30')) 'a write inside the 60 s grace must not lift'
        Assert-That (Test-IdleRunHeld -Id 'T1' -SpecPath (New-Spec 't1-old' '2026-11-12T10:59:00')) 'a write before the run ended must not lift'
        Assert-That ((Get-IdleRunSeries -Id 'T1').Count -eq 2) 'the lift must not change the count'
    }
    Run-Case '4. every doubt keeps the hold: no path, a missing file, an unreadable finishedAt' {
        Assert-That (Test-IdleRunHeld -Id 'T1' -SpecPath '') 'no path must keep the hold'
        Assert-That (Test-IdleRunHeld -Id 'T1' -SpecPath (Join-Path $proj 'PLAN\absent.md')) 'a missing file must keep the hold'
        Assert-That ((Get-IdleRunSeries -Id 'T6').Count -eq 2 -and (Test-IdleRunHeld -Id 'T6' -SpecPath (New-Spec 't6' '2026-11-12T11:02:00'))) 'an unreadable finishedAt must keep the hold'
    }
    Run-Case '5. one edit earns one pass: an unmoved run after the edit holds the ticket again' {
        $spec = New-Spec 't1-again' '2026-11-12T11:02:00'
        [IO.File]::AppendAllText($journal, (Row 'T1' '2026-11-12T12:00:00' 'ok') + "`n", $utf8)
        Assert-That (Test-IdleRunHeld -Id 'T1' -SpecPath $spec -Refresh) 'a run newer than the edit must hold again'
        Assert-That ((Get-IdleRunSeries -Id 'T1').Count -eq 3) 'the series must count the third run'
    }
    Run-Case '6. the picker, the plan-file marker and the back-link writer are wired to it' {
        $pre = Get-Content -LiteralPath (Join-Path $root 'spec_catalog\spec-next-preflight.ps1') -Raw
        $lib = Get-Content -LiteralPath (Join-Path $root 'spec_catalog\_lib.ps1') -Raw
        $links = Get-Content -LiteralPath (Join-Path $root 'spec_catalog\block-links.ps1') -Raw
        $runner = Get-Content -LiteralPath (Join-Path $root 'batch\run-spec-queue.ps1') -Raw
        Assert-That ($pre -match 'Test-IdleRunHeld -Id \(\[string\]\$cand\.id\) -SpecPath \$idleSpecPath') 'the picker does not ask Test-IdleRunHeld'
        Assert-That ($lib -match 'Test-IdleRunHeld -Id \(\[string\] \$series\.Id\) -SpecPath \$specPath') 'the marker does not ask Test-IdleRunHeld'
        Assert-That ($links -match 'SetLastWriteTimeUtc\(\$Path, \$stamp\)') 'the back-link writer does not keep the file time'
        Assert-That ($pre -notmatch 'held until the status moves;' -and $runner -notmatch 'pass it over until the status moves\.') 'a message still says only a status move ends the hold'
    }
    Run-Case '7. the panel''s copy of the walk lifts the hold with the same grace (read as text; the panel is built at a release)' {
        $vb = Get-Content -LiteralPath (Join-Path $root 'portfolio\gui\src\PortfolioState.vb') -Raw
        $lib = Get-Content -LiteralPath (Join-Path $root 'batch\_idle-runs.ps1') -Raw
        Assert-That ($lib -match '\$script:IdleRunLiftGraceSeconds = 60' -and $vb -match 'Const IdleLiftGraceSeconds As Double = 60') 'the two copies name different grace periods'
        Assert-That ($vb.Contains('If count = 0 Then newest = run.At')) 'the panel does not keep the newest counted run'
        Assert-That ($vb.Contains('If Not IsIdleLifted(repoPath, specFile, kv.Value) Then result.Add(kv.Key)')) 'the panel does not apply the lift'
        Assert-That ($vb.Contains('File.GetLastWriteTime(full) > finished.AddSeconds(IdleLiftGraceSeconds)')) 'the panel does not compare the spec file time'
    }
    Run-Case '8. R0, which has no idle hold, ranks no Implemented ticket: this repository''s launcher and the scaffold' {
        $r0 = Get-Content -LiteralPath (Join-Path $root '..\..\r0.ps1') -Raw
        $default = [regex]::Match($r0, '(?m)^\s*\[string\[\]\]\s+\$WorkStatuses\s*=\s*@\((?<v>[^)]*)\)')
        Assert-That ($default.Success -and $default.Groups['v'].Value -match "'Draft'" -and $default.Groups['v'].Value -notmatch 'Implemented') 'r0.ps1 still ranks Implemented'
        $scaffold = Get-Content -LiteralPath (Join-Path $root 'scaffold\init-task-flow.ps1') -Raw
        $filter = [regex]::Match($scaffold, '(?m)^\$workStatuses = .*$')
        Assert-That ($filter.Success -and $filter.Value.Contains("-notin @('Implemented', 'Verified', 'Archived')")) 'the scaffold still renders Implemented into R0'
    }
    Run-Case '9. alternating work and parks hold on the second repeat; forward moves reset' {
        foreach ($status in @('BlockQuestions', 'BlockExternal', 'BlockByOtherTask')) {
            [IO.File]::AppendAllLines($journal, [string[]]@(
                '{"id":"Old","moved":true,"outcome":"ok","finishedAt":"2026-11-12T09:00:00"}',
                (Row $status '2026-11-12T10:00:00' 'ok' $false 'In Progress' 'In Progress'),
                (Row $status '2026-11-12T11:00:00' 'ok' $true 'In Progress' $status),
                (Row $status '2026-11-12T12:00:00' 'limit-hit' $false $status $status),
                (Row $status '2026-11-12T13:00:00' 'launch-failed' $true 'In Progress' $status),
                (Row $status '2026-11-12T14:00:00' 'limit-hit' $false $status $status),
                (Row $status '2026-11-12T15:00:00' 'limit-hit' $true 'In Progress' $status)
            ), $utf8)
            Assert-That (Test-IdleRunHeld -Id $status -Refresh) "second repeat park at $status must hold"
            Assert-That ((Get-IdleRunSeries -Id $status).Count -eq 2) 'only the repeat parks count'
            [IO.File]::AppendAllLines($journal, [string[]]@(Row $status '2026-11-12T16:00:00' 'ok' $true 'In Progress' 'Implemented'), $utf8)
            Assert-That ((Get-IdleRunSeries -Id $status -Refresh).Count -eq 0) 'a forward move must reset'
        }
        Assert-That ((Get-IdleRunSeries -Id 'Old').Count -eq 0) 'an old moved row without status fields still resets'
    }
    Run-Case '10. the repeat-park window reads statusBefore on the third preceding row and excludes the fourth' {
        foreach ($id in 'Within', 'Outside') {
            $rows = @(
                (Row $id '2026-11-12T09:00:00' 'limit-hit' $false 'BlockQuestions' 'In Progress'),
                (Row $id '2026-11-12T10:00:00' 'limit-hit'),
                (Row $id '2026-11-12T11:00:00' 'limit-hit')
            )
            if ($id -eq 'Outside') { $rows += Row $id '2026-11-12T12:00:00' 'limit-hit' }
            $rows += Row $id '2026-11-12T13:00:00' 'ok' $true 'In Progress' 'BlockQuestions'
            [IO.File]::AppendAllLines($journal, [string[]]$rows, $utf8)
        }
        Assert-That ((Get-IdleRunSeries -Id 'Within' -Refresh).Count -eq 1) 'the third preceding row counts'
        Assert-That ((Get-IdleRunSeries -Id 'Outside').Count -eq 0) 'the fourth preceding row is outside the window'
    }
}
finally {
    Remove-Item Env:\SZA_PROJECT_ROOT -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ''
Write-Host ("idle-hold: {0} case(s), {1} passed, {2} failed, {3} s" -f $run, $passed, $failed, [math]::Round($clock.Elapsed.TotalSeconds, 1))
if ($failed -gt 0) { exit 1 }
exit 0
