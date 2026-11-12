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
      6. -Status <name[,name]> lists other statuses (default BlockQuestions unchanged): the prefix becomes the
         ticket's status, the result line names the statuses, an empty -Status exits 2.
      7. -All lists projects in registry rank order, then priority, whatever folder it runs from (S0026); -Json
         carries the rank position.
      8. The question block reader (TASK-FLOW 0.23 rule 7, S0026 item 3), over one project with a hand-written
         spec file per ticket: a current block (dated with the ledger day, every note Q: in it, text compared after
         collapsing white space), a stale block (older than the ledger day, and missing a note Q:), no block, an
         answered block (never current), an unknown version. -Json carries the block's state, version, date,
         answered and questions. The spec files hash the same after the runs.
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
function Row([string] $Id, [string] $Status, [int] $Priority, [string] $Note = '', [string] $Updated = '2026-10-29 10:00') {
    $o = [ordered]@{ id = $Id; name = "name-$Id"; status = $Status; priority = $Priority; file = "PLAN/${Id}_x.md"; created = '2026-10-29'; updated = $Updated }
    if ($Note) { $o.statusNote = $Note }
    return (ConvertTo-Json -InputObject $o -Compress)
}

# The question-block vectors (case 8): one project past the registry, addressed by folder, so the -All cases
# keep their expected counts. TASK-FLOW 0.23 rule 7 owes exactly three conformance vectors - a ticket with a
# current block, one with a stale block, one with none - answered and unknown-version guards ride along.
$omega = New-Project 'omega' @(
    (Row 'S0101' 'BlockQuestions' 90 'Missing owner call: Q: which storage backend? Q: rename the settings page?' '2026-11-05 09:00'),
    (Row 'S0102' 'BlockQuestions' 80 'Q: which storage backend?' '2026-11-05 10:00'),
    (Row 'S0103' 'BlockQuestions' 70 'Q: which storage backend?' '2026-11-05 11:00'),
    (Row 'S0104' 'BlockQuestions' 60 'Q: which storage backend?' '2026-11-05 12:00'),
    (Row 'S0105' 'BlockQuestions' 50 'Q: which storage backend?' '2026-11-05 13:00'),
    (Row 'S0106' 'BlockQuestions' 40 'Q: which storage backend? Q: rename the settings page?' '2026-11-05 14:00'))
function New-Spec([string] $Root, [string] $Id, [string] $Text) {
    [IO.File]::WriteAllText((Join-Path $Root "PLAN\${Id}_x.md"), $Text, [Text.UTF8Encoding]::new($false))
}
New-Spec $omega 'S0101' "# S0101 current block`n`n## 0. Request`n`nowner words`n`n### Questions (v1, 2026-11-05)`n- Q: which  storage backend?`n  - sqlite - one file, no server - ships today (recommended)`n  - postgres - needs a server and ops`n- Q: rename the settings page?`n  - yes - matches the site menu (recommended)`n  - no - keep the documented name`n`n## 5. Progress`n`nnone`n"
New-Spec $omega 'S0102' "# S0102 stale by date`n`n### Questions (v1, 2026-11-04)`n- Q: which storage backend?`n  - sqlite - one file, no server - ships today (recommended)`n`n## 5. Progress`n`nnone`n"
New-Spec $omega 'S0103' "# S0103 legacy, no block`n`nThe pre-0.23 shape: research, then ask.`n"
New-Spec $omega 'S0104' "# S0104 answered`n`n### Questions (v1, 2026-11-05) - answered 2026-11-06`n- Q: which storage backend?`n  - sqlite - one file, no server - ships today (recommended)`n"
New-Spec $omega 'S0105' "# S0105 unknown version`n`n### Questions (v2, 2026-11-05)`n- Q: which storage backend?`n"
New-Spec $omega 'S0106' "# S0106 stale by missing question`n`n### Questions (v1, 2026-11-05)`n- Q: which storage backend?`n  - sqlite - one file, no server - ships today (recommended)`n"

$alpha = New-Project 'alpha' @((Row 'S0021' 'Draft' 50), (Row 'S0030' 'BlockQuestions' 40 "Missing owner call: name`nsecond line"), (Row 'S0031' 'BlockQuestions' 80 'Решение владельца: имя и remote'), (Row 'S0032' 'BlockNeedUserTest' 90 'a device run'))
$beta = New-Project 'beta' @((Row 'S0021' 'BlockQuestions' 60 'beta question'), (Row 'S0022' 'Verified' 10))
$gamma = New-Project 'gamma' @((Row 'S0021' 'BlockQuestions' 58 'gamma question'))
$delta = New-Project 'delta' @((Row 'S0001' 'Approved' 50))

$repos = foreach ($p in @(@('alpha', $alpha, 10), @('beta', $beta, 20), @('gamma', $gamma, 30), @('delta', $delta, 40))) {
    [ordered]@{ key = $p[0]; path = $p[1]; enabled = $true; maxWorkers = 1; concurrent = $false; role = 'product'; permissionMode = 'bypassPermissions'; rank = $p[2] }
}
[IO.File]::WriteAllText((Join-Path $portfolio 'repos.json'), (ConvertTo-Json -InputObject ([ordered]@{ schemaVersion = '1.0'; repos = @($repos) }) -Depth 5))

$hashesBefore = @($alpha, $beta, $gamma, $delta) | ForEach-Object { (Get-FileHash -LiteralPath (Join-Path $_ 'PLAN\spec-catalog.jsonl')).Hash }
$omegaFilesBefore = @(Get-ChildItem -LiteralPath (Join-Path $omega 'PLAN') -Filter '*.md' | Sort-Object Name | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName).Hash })

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
    allGamma = @{ a = @('-All');                           w = $gamma }
    json    = @{ a = @('-All', '-Json');                   w = $delta }
    empty   = @{ a = @('-Json');                           w = $delta }
    unknown = @{ a = @('-Project', 'nope');                w = $alpha }
    nowhere = @{ a = @();                                  w = $scratch }
    alone   = @{ a = @();                                  w = $alpha; root = $emptyRoot }
    status2 = @{ a = @('-All', '-Status', 'BlockQuestions,BlockNeedUserTest'); w = $delta }
    status1 = @{ a = @('-All', '-Status', 'BlockNeedUserTest');             w = $delta }
    status0 = @{ a = @('-All', '-Status', 'BlockByOtherTask');               w = $delta }
    statusB = @{ a = @('-All', '-Status', ' , ');                            w = $delta }
    blocks  = @{ a = @('-Project', $omega);                                  w = $delta }
    blocksJson = @{ a = @('-Project', $omega, '-Json');                      w = $delta }
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
        $jsonText = (Invoke-Quiz 'json').text
        Assert-That ($jsonText -match '^\s*\[\s*\{') "json is one flat array of records, not an array in an array: $($jsonText.Substring(0, [Math]::Min(20, $jsonText.Length)))"
        $flat = ConvertFrom-Json -InputObject $jsonText -NoEnumerate
        Assert-That ($flat.Count -eq 4 -and $flat[0].id -eq 'S0031') "json top level holds $($flat.Count) element(s), first id '$($flat[0].id)'"
        $parsed = ConvertFrom-Json -InputObject $jsonText
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
    Run-Case '6 -Status lists other statuses' {
        $r = Invoke-Quiz 'status2'
        Assert-That ($r.code -eq 0) "exit $($r.code): $($r.text)"
        $heads = @($r.lines | Where-Object { $_ -match '^(BlockQuestions|BlockNeedUserTest)  ' })
        Assert-That ($heads.Count -eq 5) "expected 5 ticket lines, got $($heads.Count): $($r.text)"
        Assert-That (@($r.lines | Where-Object { $_ -like 'BlockNeedUserTest  alpha:S0032  p90*' }).Count -eq 1) 'the BlockNeedUserTest ticket carries its status as prefix'
        Assert-That ($r.last -eq 'quiz-list: 5 in BlockQuestions,BlockNeedUserTest across 3 project(s)') "result line: $($r.last)"
        $r1 = Invoke-Quiz 'status1'
        Assert-That ($r1.last -eq 'quiz-list: 1 in BlockNeedUserTest across 1 project(s)') "one status: $($r1.last)"
        Assert-That (@($r1.lines | Where-Object { $_ -like 'BQ *' }).Count -eq 0) 'no BQ prefix for a non-default status'
        $r0 = Invoke-Quiz 'status0'
        Assert-That ($r0.code -eq 0 -and $r0.last -eq 'quiz-list: 0 in BlockByOtherTask across 0 project(s)') "empty: $($r0.code) $($r0.last)"
        $rb = Invoke-Quiz 'statusB'
        Assert-That ($rb.code -eq 2) "empty -Status exit $($rb.code)"
    }
    Run-Case '7 -All in registry rank order' {
        foreach ($name in @('all', 'allGamma')) {
            $r = Invoke-Quiz $name
            $order = @($r.lines | Where-Object { $_ -like 'BQ *' } | ForEach-Object { ($_ -split '\s+')[1] }) -join ','
            Assert-That ($order -eq 'alpha:S0031,alpha:S0030,beta:S0021,gamma:S0021') "${name}: $order"
        }
        $ranks = @(ConvertFrom-Json -InputObject (Invoke-Quiz 'json').text | ForEach-Object { $_ } | ForEach-Object { $_.rank }) -join ','
        Assert-That ($ranks -eq '0,0,1,2') "json rank: $ranks"
    }
    Run-Case '8 the question-block reader (TASK-FLOW 0.23 rule 7)' {
        $r = Invoke-Quiz 'blocks'
        Assert-That ($r.code -eq 0) "exit $($r.code): $($r.text)"
        Assert-That ($r.last -eq 'quiz-list: 6 in BlockQuestions across 1 project(s)') "result line: $($r.last)"
        $blockLines = @(Invoke-Quiz 'blocks').lines | Where-Object { $_ -like '    block:*' }
        Assert-That ($blockLines.Count -eq 6) "expected 6 block lines, got $($blockLines.Count): $($r.text)"
        Assert-That ($blockLines[0] -eq '    block: current v1 2026-11-05, 2 question(s)') "current vector: $($blockLines[0])"
        Assert-That ($blockLines[1] -eq '    block: stale - dated 2026-11-04, older than the block entry 2026-11-05') "stale-by-date vector: $($blockLines[1])"
        Assert-That ($blockLines[2] -eq '    block: none - no question block') "none vector: $($blockLines[2])"
        Assert-That ($blockLines[3] -eq '    block: answered 2026-11-05') "answered vector: $($blockLines[3])"
        Assert-That ($blockLines[4] -eq '    block: none - version v2 is not v1') "unknown version: $($blockLines[4])"
        Assert-That ($blockLines[5] -eq "    block: stale - missing the note's Q: 'rename the settings page?'") "stale-by-question vector: $($blockLines[5])"
        $json = ConvertFrom-Json -InputObject (Invoke-Quiz 'blocksJson').text
        $b101 = @($json | Where-Object { $_.id -eq 'S0101' })[0].block
        Assert-That ($b101.state -eq 'current') "json state '$($b101.state)'"
        Assert-That ($b101.version -eq 'v1' -and $b101.date -eq '2026-11-05') 'json version and date'
        Assert-That (@($b101.questions).Count -eq 2) "json questions $(@($b101.questions).Count)"
        Assert-That ($b101.answered -eq $false) 'json answered flag'
        $b104 = @($json | Where-Object { $_.id -eq 'S0104' })[0].block
        Assert-That ($b104.state -eq 'answered' -and $b104.answered -eq $true) "json answered vector: $($b104.state)"
        $b105 = @($json | Where-Object { $_.id -eq 'S0105' })[0].block
        Assert-That ($b105.state -eq 'none' -and $b105.reason -eq 'version v2 is not v1') "json unknown version: '$($b105.state)' '$($b105.reason)'"
    }
    Run-Case '5 writes nothing' {
        $after = @($alpha, $beta, $gamma, $delta) | ForEach-Object { (Get-FileHash -LiteralPath (Join-Path $_ 'PLAN\spec-catalog.jsonl')).Hash }
        Assert-That (($after -join ',') -eq ($hashesBefore -join ',')) 'a ledger changed'
        $omegaAfter = @(Get-ChildItem -LiteralPath (Join-Path $omega 'PLAN') -Filter '*.md' | Sort-Object Name | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName).Hash })
        Assert-That (($omegaAfter -join ',') -eq ($omegaFilesBefore -join ',')) 'a spec file changed'
        Assert-That (-not (Test-Path -LiteralPath (Join-Path $portfolio 'run'))) 'the portfolio root gained a run folder'
    }
}
finally {
    $env:SZA_PORTFOLIO_ROOT = $savedRoot
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ("quiz-list tests: {0} run, {1} passed, {2} failed" -f $run, $passed, $failed)
exit $(if ($failed -eq 0) { 0 } else { 1 })
