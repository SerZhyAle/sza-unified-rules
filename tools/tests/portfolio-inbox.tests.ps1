#requires -Version 7.0
<#
.SYNOPSIS
    Cases for `pq inbox` and the waiting line of `pq status` (S0025) - the owner's inbox over all projects.

.DESCRIPTION
    Runs pq.ps1 over throwaway repositories and a throwaway portfolio root with hand-written ledgers, spec files with
    Blocker: tokens and a PORTFOLIO_QUEUE.md with a held row; the real registry and the real ledgers are never read
    or written. Starts no agent and no pq child, so the whole file takes a few seconds.

      1. pq inbox prints one line per kind (count, oldest age, the command that clears it), then the tickets with
         id, age and note; BlockByOtherTask prints as chain roots ("beta:S0021 (held, owner decision) frees 2"),
         a ticket whose blockers are all released prints as an ordinary ticket; the last line is the total.
      2. pq inbox -Json carries the same data for the GUI: counts, roots with frees and held, tickets with full note.
      3. pq status ends with "waiting for you: questions N, tests N, outside N, chain N, unbuilt N -> pq inbox",
         does not run the rank without -Next ("Next: (not ranked ...)"), and -Json carries waiting and next=null.
      4. "Passes today" counts the local day: an event of local yesterday in a neighbour's UTC-date file is not
         counted, an event of local today in the +1 UTC-date file is.
      5. It writes nothing: every ledger and the registry hash the same, no run/ or log/ folder appears.
#>
[CmdletBinding()]
param([switch] $KeepScratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$pq = Join-Path $SourceRoot 'tools\harness\portfolio\pq.ps1'
$pwshExe = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('pq-inbox-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null
$savedRoot = $env:SZA_PORTFOLIO_ROOT
$portfolio = Join-Path $scratch 'portfolio'
New-Item -ItemType Directory -Path $portfolio | Out-Null

function New-Project([string] $Key, [string[]] $Rows, [hashtable] $Specs) {
    $root = Join-Path $scratch $Key
    New-Item -ItemType Directory -Path (Join-Path $root 'PLAN') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $root '.sza-profile.json'), '{}')
    [IO.File]::WriteAllText((Join-Path $root 'PLAN\spec-catalog.jsonl'), (($Rows -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    foreach ($k in $Specs.Keys) { [IO.File]::WriteAllText((Join-Path $root ('PLAN\' + $k)), $Specs[$k], [Text.UTF8Encoding]::new($false)) }
    return $root
}
function Row([string] $Id, [string] $Status, [int] $Priority, [string] $Note = '', [string] $Updated = '2026-11-09 10:00') {
    $o = [ordered]@{ id = $Id; name = "name-$Id"; status = $Status; priority = $Priority; file = "PLAN/${Id}_x.md"; created = '2026-10-29'; updated = $Updated }
    if ($Note) { $o.statusNote = $Note }
    return (ConvertTo-Json -InputObject $o -Compress)
}

$alpha = New-Project 'alpha' @(
    (Row 'S0031' 'BlockQuestions' 80 'owner call: name and remote'),
    (Row 'S0032' 'BlockNeedUserTest' 90 'device run needed'),
    (Row 'S0040' 'BlockByOtherTask' 50 'waiting on beta S0021')
) @{ 'S0040_x.md' = "# S0040`n`nBlocker: beta:S0021`n" }
$beta = New-Project 'beta' @(
    (Row 'S0021' 'BlockQuestions' 60 'owner decision'),
    (Row 'S0022' 'BlockExternal' 30 'vendor key'),
    (Row 'S0023' 'Implemented' 70 'built, awaiting audit'),
    (Row 'S0099' 'Archived' 10 '')
) @{}
$gamma = New-Project 'gamma' @(
    (Row 'S0050' 'BlockByOtherTask' 40 'waiting on beta S0021'),
    (Row 'S0051' 'BlockByOtherTask' 40 'stale: blocker released'),
    (Row 'S0052' 'BlockByOtherTask' 40 'local blocker holds'),
    (Row 'S0053' 'In Progress' 20 'being worked')
) @{
    'S0050_x.md' = "Blocker: beta:S0021`n"
    'S0051_x.md' = "Blocker: beta:S0099`n"
    'S0052_x.md' = "Blocker: S0053`n"
}

$repos = foreach ($p in @(@('alpha', $alpha), @('beta', $beta), @('gamma', $gamma))) {
    [ordered]@{ key = $p[0]; path = $p[1]; enabled = $true; maxWorkers = 1; concurrent = $false; role = 'product'; permissionMode = 'bypassPermissions'; rank = 10 }
}
$registryFile = Join-Path $portfolio 'repos.json'
[IO.File]::WriteAllText($registryFile, (ConvertTo-Json -InputObject ([ordered]@{ schemaVersion = '1.0'; repos = @($repos) }) -Depth 5))
[IO.File]::WriteAllText((Join-Path $portfolio 'PORTFOLIO_QUEUE.md'),
    "# portfolio queue`n`n## 1`n`nalpha:S0031  some text`nbeta  # role: product`n`nhold`n`nbeta:S0021  held by owner`n")

# Event files for the local-day count: the files stay named by UTC date (rule 54), the events carry their own ts.
$logDir = Join-Path $portfolio 'log'
New-Item -ItemType Directory -Path $logDir | Out-Null
$now = [DateTimeOffset]::Now
$dMinus = $now.AddDays(-1).UtcDateTime.ToString('yyyy-MM-dd')
$dToday = $now.UtcDateTime.ToString('yyyy-MM-dd')
$dPlus = $now.AddDays(1).UtcDateTime.ToString('yyyy-MM-dd')
function EvLine([long] $Seq, [DateTimeOffset] $Ts, [string] $Outcome) {
    # A complete envelope: every key of rule 53 present (null allowed), ts in the exact UTC format.
    return (ConvertTo-Json -InputObject ([ordered]@{
        v = 1; ts = $Ts.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'"); seq = $Seq; wr = 'cli'
        run = $null; ev = 'pass.end'; repo = $null; id = $null; pass = $null; worker = $null; agent = $null; model = $null; cx = $null
        d = [ordered]@{ outcome = $Outcome }
    }) -Compress)
}
[IO.File]::WriteAllText((Join-Path $logDir "events-$dMinus.cli.jsonl"), ((EvLine 1 ($now.AddDays(-1)) 'moved') + "`n" + (EvLine 2 $now 'ok') + "`n"), [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $logDir "events-$dToday.cli.jsonl"), ((EvLine 1 ($now.AddDays(-1)) 'moved') + "`n" + (EvLine 2 $now 'ok') + "`n"), [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $logDir "events-$dPlus.cli.jsonl"), ((EvLine 1 $now 'ok') + "`n"), [Text.UTF8Encoding]::new($false))

$hashesBefore = @($alpha, $beta, $gamma) | ForEach-Object { (Get-FileHash -LiteralPath (Join-Path $_ 'PLAN\spec-catalog.jsonl')).Hash }
$registryHashBefore = (Get-FileHash -LiteralPath $registryFile).Hash

# The child prints UTF-8 whatever the console code page is, so the assertions do not depend on the machine.
$wrapper = Join-Path $scratch 'run-pq.ps1'
[IO.File]::WriteAllText($wrapper, '[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); & $env:PQ_SCRIPT @args; exit $LASTEXITCODE')

# Every invocation the cases need, started at once: sequential pwsh starts alone would pass the 5 s line.
$calls = [ordered]@{
    inbox      = @('inbox')
    inboxJson  = @('inbox', '-Json')
    status     = @('status')
    statusJson = @('status', '-Json')
}
$results = @{}
$calls.GetEnumerator() | ForEach-Object -ThrottleLimit 4 -Parallel {
    $psi = [Diagnostics.ProcessStartInfo]::new($using:pwshExe)
    foreach ($x in (@('-NoProfile', '-File', $using:wrapper) + $_.Value)) { $psi.ArgumentList.Add([string] $x) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $psi.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $psi.WorkingDirectory = $using:scratch
    $psi.Environment['SZA_PORTFOLIO_ROOT'] = $using:portfolio
    $psi.Environment['PQ_SCRIPT'] = $using:pq
    $proc = [Diagnostics.Process]::Start($psi)
    $out = $proc.StandardOutput.ReadToEndAsync()
    $err = $proc.StandardError.ReadToEndAsync()
    if (-not $proc.WaitForExit(60000)) { $proc.Kill($true) }
    $proc.WaitForExit()
    $lines = @($out.Result -split '\r?\n' | Where-Object { $_.Trim() })
    [pscustomobject]@{ name = $_.Key; code = $proc.ExitCode; lines = $lines; text = ($lines -join "`n"); stderr = $err.Result; last = $(if ($lines.Count) { $lines[-1] } else { '' }) }
} | ForEach-Object { $results[$_.name] = $_ }
function Invoke-Pq([string] $Name) { return $results[$Name] }

try {
    Run-Case '1 pq inbox text' {
        $r = Invoke-Pq 'inbox'
        Assert-That ($r.code -eq 0) "exit $($r.code): $($r.stderr)"
        Assert-That (@($r.lines | Where-Object { $_ -match '^questions\s+2\s+oldest \d+[dhm]\s+clear: /spec-quiz <key>:<id>$' }).Count -eq 1) "questions line: $($r.text)"
        Assert-That (@($r.lines | Where-Object { $_ -match '^tests\s+1\s+oldest ' }).Count -eq 1) 'tests line'
        Assert-That (@($r.lines | Where-Object { $_ -match '^outside\s+1\s+oldest ' }).Count -eq 1) 'outside line'
        Assert-That (@($r.lines | Where-Object { $_ -match '^chain\s+4\s+oldest ' }).Count -eq 1) 'chain line'
        Assert-That (@($r.lines | Where-Object { $_ -match '^unbuilt\s+1\s+oldest ' }).Count -eq 1) 'unbuilt line'
        Assert-That (@($r.lines | Where-Object { $_ -eq '  beta:S0021 (held, owner decision) frees 2' }).Count -eq 1) "chain root line: $($r.text)"
        Assert-That (@($r.lines | Where-Object { $_ -match '^  gamma:S0053 \(being worked\) frees 1$' }).Count -eq 1) 'local-blocker root line'
        Assert-That (@($r.lines | Where-Object { $_ -match '^  gamma:S0051\s+p40\s+age \d+[dhm]\s+stale: blocker released$' }).Count -eq 1) 'released-blocker ticket prints as a ticket'
        Assert-That (@($r.lines | Where-Object { $_ -match '^  alpha:S0031\s+p80\s+age \d+[dhm]\s+owner call: name and remote$' }).Count -eq 1) 'question ticket with age and note'
        Assert-That ($r.last -eq 'pq inbox: 9 waiting across 3 project(s)') "total line: $($r.last)"
    }
    Run-Case '2 pq inbox -Json' {
        $r = Invoke-Pq 'inboxJson'
        Assert-That ($r.code -eq 0) "exit $($r.code): $($r.stderr)"
        $j = ConvertFrom-Json -InputObject $r.text
        Assert-That ($j.total -eq 9 -and $j.projects -eq 3) "total=$($j.total) projects=$($j.projects)"
        Assert-That ($j.counts.questions -eq 2 -and $j.counts.tests -eq 1 -and $j.counts.outside -eq 1 -and $j.counts.chain -eq 4 -and $j.counts.unbuilt -eq 1) 'counts'
        $roots = @($j.kinds.chain.roots)
        Assert-That ($roots.Count -eq 2) "roots $($roots.Count)"
        $root = @($roots | Where-Object { $_.pair -eq 'beta:S0021' })[0]
        Assert-That ($root.held -eq $true -and $root.freesCount -eq 2 -and $root.status -eq 'BlockQuestions') "root: $($root | ConvertTo-Json -Compress)"
        Assert-That (@($root.frees) -contains 'alpha:S0040' -and @($root.frees) -contains 'gamma:S0050') 'frees list'
        Assert-That (@($j.kinds.chain.tickets | Where-Object { $_.id -eq 'S0051' })[0].note -eq 'stale: blocker released') 'loose ticket with full note'
        Assert-That (@($j.kinds.questions.tickets | Where-Object { $_.id -eq 'S0031' })[0].note -eq 'owner call: name and remote') 'question note full in json'
    }
    Run-Case '3 pq status waiting line, no rank without -Next' {
        $r = Invoke-Pq 'status'
        Assert-That ($r.code -eq 0) "exit $($r.code): $($r.stderr)"
        Assert-That ($r.last -eq 'waiting for you: questions 2, tests 1, outside 1, chain 4, unbuilt 1 -> pq inbox') "last line: $($r.last)"
        Assert-That (@($r.lines | Where-Object { $_ -eq 'Next: (not ranked - pq status -Next runs the rank)' }).Count -eq 1) 'next not ranked'
        $rj = ConvertFrom-Json -InputObject (Invoke-Pq 'statusJson').text
        Assert-That ($rj.next -eq $null -and $rj.nextRanked -eq $false) 'json next'
        Assert-That ($rj.waiting.questions -eq 2 -and $rj.waiting.chain -eq 4 -and $rj.waiting.unbuilt -eq 1) "json waiting: $($rj.waiting | ConvertTo-Json -Compress)"
    }
    Run-Case '4 passes today is the local day' {
        $r = Invoke-Pq 'status'
        Assert-That (@($r.lines | Where-Object { $_ -eq 'Passes today: ok: 3' }).Count -eq 1) "local-day count: $($r.lines -join ' | ')"
    }
    Run-Case '5 writes nothing' {
        $after = @($alpha, $beta, $gamma) | ForEach-Object { (Get-FileHash -LiteralPath (Join-Path $_ 'PLAN\spec-catalog.jsonl')).Hash }
        Assert-That (($after -join ',') -eq ($hashesBefore -join ',')) 'a ledger changed'
        Assert-That ((Get-FileHash -LiteralPath $registryFile).Hash -eq $registryHashBefore) 'the registry changed'
        Assert-That (-not (Test-Path -LiteralPath (Join-Path $portfolio 'run'))) 'the portfolio root gained a run folder'
    }
}
finally {
    $env:SZA_PORTFOLIO_ROOT = $savedRoot
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ("pq-inbox tests: {0} run, {1} passed, {2} failed" -f $run, $passed, $failed)
exit $(if ($failed -eq 0) { 0 } else { 1 })
