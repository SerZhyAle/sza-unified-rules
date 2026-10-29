#requires -Version 7.0
<#
.SYNOPSIS
    Cases for tools/harness/portfolio/quiz-list.ps1 - the lookup half of the spec-quiz skill.

.DESCRIPTION
    Runs the script over throwaway repositories and a throwaway portfolio root with hand-written ledgers; the real
    registry and the real ledgers are never read or written. Starts no agent and no pq child, so the whole file
    takes a few seconds.

      1. The project of the current folder: its BlockQuestions tickets only, highest priority first, the reason
         note flattened to one line with Cyrillic kept, the count line exact.
      2. -Id for an id that is not waiting here but waits in two other projects: the result line says what the id is
         here and lists both others; a bare number matches the id's trailing digits.
      3. -All counts every project; -Json is a valid array with the full note; nothing waiting prints [].
      4. Refusals exit 2 (unknown project, no project at or above the folder without -All); a missing registry still
         answers for the current project.
      5. It writes nothing: every ledger hashes the same after all the runs.
#>
[CmdletBinding()]
param([switch] $KeepScratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$script_ = Join-Path $SourceRoot 'tools\harness\portfolio\quiz-list.ps1'
$pwshExe = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('quiz-list-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null
$savedRoot = $env:SZA_PORTFOLIO_ROOT
$portfolio = Join-Path $scratch 'portfolio'
New-Item -ItemType Directory -Path $portfolio | Out-Null

function New-Project([string] $Key, [string[]] $Rows) {
    $root = Join-Path $scratch $Key
    New-Item -ItemType Directory -Path (Join-Path $root 'PLAN') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $root '.sza-profile.json'), '{}')
    [IO.File]::WriteAllText((Join-Path $root 'PLAN\spec-catalog.jsonl'), (($Rows -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    return $root
}
function Row([string] $Id, [string] $Status, [int] $Priority, [string] $Note = '') {
    $o = [ordered]@{ id = $Id; name = "name-$Id"; status = $Status; priority = $Priority; file = "PLAN/${Id}_x.md"; created = '2026-10-29'; updated = '2026-10-29 10:00' }
    if ($Note) { $o.statusNote = $Note }
    return (ConvertTo-Json -InputObject $o -Compress)
}

$alpha = New-Project 'alpha' @((Row 'S0021' 'Draft' 50), (Row 'S0030' 'BlockQuestions' 40 "Missing owner call: name`nsecond line"), (Row 'S0031' 'BlockQuestions' 80 'Решение владельца: имя и remote'), (Row 'S0032' 'BlockNeedUserTest' 90 'a device run'))
$beta = New-Project 'beta' @((Row 'S0021' 'BlockQuestions' 60 'beta question'), (Row 'S0022' 'Verified' 10))
$gamma = New-Project 'gamma' @((Row 'S0021' 'BlockQuestions' 58 'gamma question'))
$delta = New-Project 'delta' @((Row 'S0001' 'Approved' 50))

$repos = foreach ($p in @(@('alpha', $alpha, 10), @('beta', $beta, 20), @('gamma', $gamma, 30), @('delta', $delta, 40))) {
    [ordered]@{ key = $p[0]; path = $p[1]; enabled = $true; maxWorkers = 1; concurrent = $false; role = 'product'; permissionMode = 'bypassPermissions'; rank = $p[2] }
}
[IO.File]::WriteAllText((Join-Path $portfolio 'repos.json'), (ConvertTo-Json -InputObject ([ordered]@{ schemaVersion = '1.0'; repos = @($repos) }) -Depth 5))

$hashesBefore = @($alpha, $beta, $gamma, $delta) | ForEach-Object { (Get-FileHash -LiteralPath (Join-Path $_ 'PLAN\spec-catalog.jsonl')).Hash }

# The child prints UTF-8 whatever the console code page is, so the Cyrillic assertions do not depend on the machine.
$wrapper = Join-Path $scratch 'run-quiz.ps1'
[IO.File]::WriteAllText($wrapper, '[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); & $env:QUIZ_SCRIPT @args; exit $LASTEXITCODE')
$emptyRoot = Join-Path $scratch 'no-registry'
New-Item -ItemType Directory -Path $emptyRoot | Out-Null

# Every invocation the cases need, started at once: ten sequential pwsh starts alone would pass the 5 s line.
$calls = [ordered]@{
    current = @{ a = @();                                  w = $alpha }
    idHere  = @{ a = @('-Id', 'S0021');                    w = $alpha }
    idBare  = @{ a = @('-Id', '21', '-Project', 'beta');   w = $alpha }
    idAbsent = @{ a = @('-Id', 'S0077');                   w = $alpha }
    all     = @{ a = @('-All');                            w = $delta }
    json    = @{ a = @('-All', '-Json');                   w = $delta }
    empty   = @{ a = @('-Json');                           w = $delta }
    unknown = @{ a = @('-Project', 'nope');                w = $alpha }
    nowhere = @{ a = @();                                  w = $scratch }
    alone   = @{ a = @();                                  w = $alpha; root = $emptyRoot }
}
$results = @{}
$calls.GetEnumerator() | ForEach-Object -ThrottleLimit 10 -Parallel {
    $c = $_.Value
    $psi = [Diagnostics.ProcessStartInfo]::new($using:pwshExe)
    foreach ($x in (@('-NoProfile', '-File', $using:wrapper) + $c.a)) { $psi.ArgumentList.Add([string] $x) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $psi.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $psi.WorkingDirectory = $c.w
    $psi.Environment['SZA_PORTFOLIO_ROOT'] = $(if ($c.ContainsKey('root')) { $c.root } else { $using:portfolio })
    $psi.Environment['QUIZ_SCRIPT'] = $using:script_
    $proc = [Diagnostics.Process]::Start($psi)
    $out = $proc.StandardOutput.ReadToEndAsync()
    $err = $proc.StandardError.ReadToEndAsync()
    if (-not $proc.WaitForExit(60000)) { $proc.Kill($true) }
    $proc.WaitForExit()
    $lines = @($out.Result -split '\r?\n' | Where-Object { $_.Trim() })
    [pscustomobject]@{ name = $_.Key; code = $proc.ExitCode; lines = $lines; text = ($lines -join "`n"); stderr = $err.Result; last = $(if ($lines.Count) { $lines[-1] } else { '' }) }
} | ForEach-Object { $results[$_.name] = $_ }
function Invoke-Quiz([string] $Name) { return $results[$Name] }

try {
    Run-Case '1 current project' {
        $r = Invoke-Quiz 'current'
        Assert-That ($r.code -eq 0) "exit $($r.code): $($r.text)"
        $bq = @($r.lines | Where-Object { $_ -like 'BQ *' })
        Assert-That ($bq.Count -eq 2) "expected 2 BQ lines, got $($bq.Count): $($r.text)"
        Assert-That ($bq[0] -like 'BQ  alpha:S0031  p80*') "highest priority first: $($bq[0])"
        Assert-That ($r.text.Contains('note: Решение владельца: имя и remote')) 'Cyrillic note lost'
        Assert-That ($r.text.Contains('note: Missing owner call: name second line')) 'multi-line note not flattened'
        Assert-That ($r.last -eq 'quiz-list: 2 in BlockQuestions across 1 project(s)') "result line: $($r.last)"
        Assert-That (-not $r.text.Contains('S0032')) 'a BlockNeedUserTest ticket was listed'
    }
    Run-Case '2 id waiting elsewhere' {
        $r = Invoke-Quiz 'idHere'
        Assert-That ($r.code -eq 0) "exit $($r.code): $($r.text)"
        Assert-That ($r.last -eq 'quiz-list: id S0021 here=alpha:S0021=Draft blockquestions=beta:S0021,gamma:S0021') "result line: $($r.last)"
        $r2 = Invoke-Quiz 'idBare'
        Assert-That ($r2.last -eq 'quiz-list: id 21 here=beta:S0021=BlockQuestions blockquestions=beta:S0021,gamma:S0021') "bare number: $($r2.last)"
        $r3 = Invoke-Quiz 'idAbsent'
        Assert-That ($r3.last -eq 'quiz-list: id S0077 here=alpha:S0077=absent blockquestions=none') "absent id: $($r3.last)"
    }
    Run-Case '3 all and json' {
        $r = Invoke-Quiz 'all'
        Assert-That ($r.last -eq 'quiz-list: 4 in BlockQuestions across 3 project(s)') "all: $($r.last)"
        $parsed = ConvertFrom-Json -InputObject (Invoke-Quiz 'json').text
        Assert-That (@($parsed).Count -eq 4) "json count $(@($parsed).Count)"
        Assert-That ((@($parsed | Where-Object { $_.id -eq 'S0031' })[0].note) -eq 'Решение владельца: имя и remote') 'json note'
        $none = Invoke-Quiz 'empty'
        Assert-That ($none.text.Trim() -eq '[]') "empty json: $($none.text)"
    }
    Run-Case '4 refusals and no registry' {
        $bad = Invoke-Quiz 'unknown'
        Assert-That ($bad.code -eq 2) "unknown project exit $($bad.code)"
        $nowhere = Invoke-Quiz 'nowhere'
        Assert-That ($nowhere.code -eq 2) "no project exit $($nowhere.code)"
        $alone = Invoke-Quiz 'alone'
        Assert-That ($alone.code -eq 0 -and $alone.last -eq 'quiz-list: 2 in BlockQuestions across 1 project(s)') "no registry: $($alone.code) $($alone.last)"
    }
    Run-Case '5 writes nothing' {
        $after = @($alpha, $beta, $gamma, $delta) | ForEach-Object { (Get-FileHash -LiteralPath (Join-Path $_ 'PLAN\spec-catalog.jsonl')).Hash }
        Assert-That (($after -join ',') -eq ($hashesBefore -join ',')) 'a ledger changed'
        Assert-That (-not (Test-Path -LiteralPath (Join-Path $portfolio 'run'))) 'the portfolio root gained a run folder'
    }
}
finally {
    $env:SZA_PORTFOLIO_ROOT = $savedRoot
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ("quiz-list tests: {0} run, {1} passed, {2} failed" -f $run, $passed, $failed)
exit $(if ($failed -eq 0) { 0 } else { 1 })
