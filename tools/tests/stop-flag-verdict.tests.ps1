#requires -Version 7.0
<#
.SYNOPSIS
    Cases for the verdict the queue runner passes on the shared stop flag at start (S4464).

.DESCRIPTION
    Get-StopFileVerdict is lifted out of batch/run-spec-queue.ps1 by its syntax tree and run against a
    scratch directory whose files carry chosen write times; no runner starts and no child process runs,
    so the file takes well under a second.

      1. The runner parses, defines the function once, stamps the end of a run, and refuses with exit 3.
      2. No run on record (no stamp, no journal): the flag is not a leftover.
      3. A stamp at or after the flag: a leftover. A stamp before the flag: the flag stands.
      4. No stamp, but a journal: the journal stands in for it, same comparison.
      5. The later of stamp and journal decides - a runner killed before it could stamp.
      6. The flag's own first line is reported, cut at 120 characters.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$runner = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\harness\batch\run-spec-queue.ps1'))

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

$runnerText = Get-Content -LiteralPath $runner -Raw
$ast = [Management.Automation.Language.Parser]::ParseFile($runner, [ref]$null, [ref]$null)
$fn = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-StopFileVerdict' }, $true))
if ($fn.Count -eq 1) { . ([scriptblock]::Create($fn[0].Extent.Text)) }

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('stop-verdict-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null
$base = [datetime]::UtcNow.AddHours(-2)

# A fresh run directory per case: the flag, and optionally a stamp and a journal, each at an offset in minutes.
function New-Case([string] $Name, [double] $FlagAt, $StampAt = $null, $JournalAt = $null, [string] $FlagText = 'stop requested 2026-11-12T10:00:00') {
    $dir = Join-Path $scratch $Name
    New-Item -ItemType Directory -Path $dir | Out-Null
    $flag = Join-Path $scratch "$Name.STOP"
    Set-Content -LiteralPath $flag -Value $FlagText
    (Get-Item -LiteralPath $flag).LastWriteTimeUtc = $base.AddMinutes($FlagAt)
    if ($null -ne $StampAt) {
        $s = Join-Path $dir 'last-run-end.json'; Set-Content -LiteralPath $s -Value '{}'
        (Get-Item -LiteralPath $s).LastWriteTimeUtc = $base.AddMinutes($StampAt)
    }
    if ($null -ne $JournalAt) {
        $j = Join-Path $dir 'runs-a.jsonl'; Set-Content -LiteralPath $j -Value '{}'
        (Get-Item -LiteralPath $j).LastWriteTimeUtc = $base.AddMinutes($JournalAt)
    }
    [pscustomobject]@{ Flag = $flag; Dir = $dir }
}

try {
    Run-Case 'the runner parses, defines the verdict once, stamps the end of a run and refuses with exit 3' {
        Assert-That ($fn.Count -eq 1) "Get-StopFileVerdict is defined $($fn.Count) times in run-spec-queue.ps1"
        Assert-That ($runnerText -match "last-run-end\.json'\) -Value") 'the loop never stamps last-run-end.json'
        Assert-That ($runnerText -match 'Get-StopFileVerdict -StopFile \$stopFileAll') 'the start does not ask for a verdict on the shared flag'
        Assert-That ($runnerText -match 'a stop flag stands that no finished run left behind') 'the refusal message is gone'
    }

    Run-Case 'no run on record: the flag is not a leftover' {
        $c = New-Case 'nothing' 0
        $v = Get-StopFileVerdict -StopFile $c.Flag -RunDir $c.Dir
        Assert-That (-not $v.Leftover) 'a flag with no run on record was called a leftover'
        Assert-That ($null -eq $v.RunEndAt) 'a run end was reported where none exists'
    }

    Run-Case 'a missing runs directory is the same as an empty one' {
        $flag = Join-Path $scratch 'nodir.STOP'; Set-Content -LiteralPath $flag -Value 'stop'
        $v = Get-StopFileVerdict -StopFile $flag -RunDir (Join-Path $scratch 'does-not-exist')
        Assert-That (-not $v.Leftover) 'a flag with no runs directory was called a leftover'
    }

    Run-Case 'a stamp after the flag: a leftover, and the stamp is named as the source' {
        $c = New-Case 'stamp-after' 0 5
        $v = Get-StopFileVerdict -StopFile $c.Flag -RunDir $c.Dir
        Assert-That $v.Leftover 'a flag older than the stamp was kept'
        Assert-That ($v.RunEndSource -eq 'last-run-end.json') "source was '$($v.RunEndSource)'"
    }

    Run-Case 'a stamp equal to the flag time still counts as a leftover (the loop breaks after it reads the flag)' {
        $c = New-Case 'stamp-equal' 3 3
        Assert-That (Get-StopFileVerdict -StopFile $c.Flag -RunDir $c.Dir).Leftover 'equal times were called a standing flag'
    }

    Run-Case 'a stamp before the flag: the flag stands' {
        $c = New-Case 'stamp-before' 10 5
        $v = Get-StopFileVerdict -StopFile $c.Flag -RunDir $c.Dir
        Assert-That (-not $v.Leftover) 'a flag set after the last run ended was cleared'
        Assert-That ($v.StopAt -gt $v.RunEndAt) 'the report does not show the flag as the later of the two'
    }

    Run-Case 'no stamp: a journal after the flag stands in for it' {
        $c = New-Case 'journal-after' 0 $null 4
        $v = Get-StopFileVerdict -StopFile $c.Flag -RunDir $c.Dir
        Assert-That $v.Leftover 'a flag older than the newest journal was kept'
        Assert-That ($v.RunEndSource -eq 'runs-a.jsonl') "source was '$($v.RunEndSource)'"
    }

    Run-Case 'no stamp: a journal before the flag leaves the flag standing' {
        $c = New-Case 'journal-before' 10 $null 4
        Assert-That (-not (Get-StopFileVerdict -StopFile $c.Flag -RunDir $c.Dir).Leftover) 'a flag newer than the journal was cleared'
    }

    Run-Case 'the later of stamp and journal decides: a runner killed before it could stamp' {
        # An old stamp, then a run during which the flag was set and a ticket still finished; the runner was killed.
        $c = New-Case 'killed' 10 5 15
        $v = Get-StopFileVerdict -StopFile $c.Flag -RunDir $c.Dir
        Assert-That $v.Leftover 'the later journal did not outrank the older stamp'
        Assert-That ($v.RunEndSource -eq 'runs-a.jsonl') "source was '$($v.RunEndSource)'"
    }

    Run-Case 'the flag text is reported, cut at 120 characters' {
        $c = New-Case 'text' 0 $null $null ('x' * 300)
        $v = Get-StopFileVerdict -StopFile $c.Flag -RunDir $c.Dir
        Assert-That ($v.Text.Length -eq 120) "text length was $($v.Text.Length)"
        $c2 = New-Case 'text2' 0
        Assert-That ((Get-StopFileVerdict -StopFile $c2.Flag -RunDir $c2.Dir).Text -eq 'stop requested 2026-11-12T10:00:00') 'the flag text was not reported'
    }
}
finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} cases: {1} passed, {2} failed" -f $run, $passed, $failed)
exit $(if ($failed -eq 0) { 0 } else { 1 })
