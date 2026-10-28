#requires -Version 7.0
<#
.SYNOPSIS
    Cases for tools/harness/portfolio/spec-draft.ps1 - the capture-and-report half of the spec-draft skill.

.DESCRIPTION
    Runs the script over throwaway repositories and a throwaway portfolio root; the real registry and the
    real PORTFOLIO_QUEUE.md are never read or written. Starts no agent.

      1. The owner's words land in the spec file byte for byte (Cyrillic, `$`, `{{ID}}`, quotes, `...`), the
         ledger row and the ticket-queue row exist, the ledger validates, the result line is exact.
      2. A second and a third ticket land behind the first: the reported position is the one the project's own
         picker gives, and a hotfix behind others is told how to jump the line.
      3. -Pin writes the ticket into PORTFOLIO_QUEUE.md; under `hold` it is refused and nothing is written.
      4. A project under `hold` is still captured into, and reported as not dispatched; the file is untouched.
      5. An unregistered project is captured into and reported as unregistered; the registry is untouched.
      6. With no -Project the project is found from the current folder.
      7. A project's own scripts/utils/capture-draft.ps1 is used instead of the canon's.
      8. Every refusal (bad slug, no text, empty text, unknown project, no task flow, -Attach without a script
         that takes it) exits 2 and creates nothing; -WhatIf creates nothing.
#>
[CmdletBinding()]
param([switch] $KeepScratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$harness = Join-Path $SourceRoot 'tools\harness'
$draftScript = Join-Path $harness 'portfolio\spec-draft.ps1'
$pqScript = Join-Path $harness 'portfolio\pq.ps1'
$pwshExe = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('spec-draft-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null
$portfolioRoot = Join-Path $scratch 'portfolio'
$saved = @{ SZA_PORTFOLIO_ROOT = $env:SZA_PORTFOLIO_ROOT; USERPROFILE = $env:USERPROFILE; SZA_PROJECT_ROOT = $env:SZA_PROJECT_ROOT; SZA_PROFILE_PATH = $env:SZA_PROFILE_PATH }

# One child process, its own environment; returns code, stdout, stderr, and the last printed line.
function Invoke-Script([string] $Script, [string[]] $Arguments, [string] $WorkDir = $scratch, [hashtable] $Env = @{}) {
    $psi = [Diagnostics.ProcessStartInfo]::new($pwshExe)
    foreach ($a in (@('-NoProfile', '-File', $Script) + $Arguments)) { $psi.ArgumentList.Add([string] $a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $WorkDir
    $psi.Environment['SZA_PORTFOLIO_ROOT'] = $portfolioRoot
    $psi.Environment['USERPROFILE'] = $scratch
    [void] $psi.Environment.Remove('SZA_PROJECT_ROOT')
    [void] $psi.Environment.Remove('SZA_PROFILE_PATH')
    foreach ($k in $Env.Keys) { $psi.Environment[$k] = [string] $Env[$k] }
    $proc = [Diagnostics.Process]::Start($psi)
    $out = $proc.StandardOutput.ReadToEndAsync()
    $err = $proc.StandardError.ReadToEndAsync()
    if (-not $proc.WaitForExit(180000)) { $proc.Kill($true); throw "$Script timed out" }
    $proc.WaitForExit()
    $lines = @($out.Result -split '\r?\n' | Where-Object { $_.Trim() })
    return [pscustomobject]@{ code = $proc.ExitCode; stdout = $out.Result; stderr = $err.Result; output = $out.Result + $err.Result; last = $(if ($lines.Count) { $lines[-1] } else { '' }) }
}
function Invoke-Draft([string[]] $Arguments, [string] $WorkDir = $scratch) { Invoke-Script $draftScript $Arguments $WorkDir }
function Invoke-PqCli([string[]] $Arguments) { Invoke-Script $pqScript $Arguments }

function New-Repo([string] $Name) {
    $dir = Join-Path $scratch $Name
    New-Item -ItemType Directory -Path $dir | Out-Null
    $null = & $pwshExe -NoProfile -File (Join-Path $harness 'scaffold\init-task-flow.ps1') -Root $dir -NoLaunchers
    $stamp = [ordered]@{ schemaVersion = '1.0'; canon = @{ version = '2026.1'; coreDigest = '0' * 64; model = 'reference' }; overlay = 'powershell-tooling'; ledgerShape = 'spec-catalog' }
    [IO.File]::WriteAllText((Join-Path $dir '.sza-canon.json'), ($stamp | ConvertTo-Json -Depth 5), [Text.Encoding]::UTF8)
    return $dir
}
function Write-Text([string] $Name, [string] $Content) {
    $p = Join-Path $scratch $Name
    [IO.File]::WriteAllText($p, $Content, [Text.UTF8Encoding]::new($false))
    return $p
}
function Get-LedgerCount([string] $Repo) { return @(Get-Content (Join-Path $Repo 'PLAN\spec-catalog.jsonl') | Where-Object { $_.Trim() }).Count }
function Get-FileHashOf([string] $Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

try {
    $env:SZA_PORTFOLIO_ROOT = $portfolioRoot
    $env:USERPROFILE = $scratch
    $env:SZA_PROJECT_ROOT = $null
    $env:SZA_PROFILE_PATH = $null

    $repoA = New-Repo 'repo-a'
    $reg = Invoke-PqCli @('register', '-Path', $repoA, '-Key', 'repo-a', '-Enable', '-PermissionMode', 'bypassPermissions')
    Assert-That ($reg.code -eq 0) "register repo-a failed: $($reg.output)"
    $q = Invoke-PqCli @('queue', '-Init', '-NoOpen')
    Assert-That ($q.code -eq 0) "queue -Init failed: $($q.output)"
    $queueFile = Join-Path $portfolioRoot 'PORTFOLIO_QUEUE.md'

    $tricky = "Приложение падает при открытии сетки.. ёж`r`nШаги: нажать `"Открыть`" и `$env:PATH, {{ID}}, {{TEXT}}, 50% ... готово.`r`n`tхвост без перевода строки"

    Run-Case 'local catalog mutations refresh the portfolio through the last completion and reopen' {
        $repoLife = New-Repo 'repo-life'
        $regLife = Invoke-PqCli @('register', '-Path', $repoLife, '-Key', 'repo-life', '-Enable')
        Assert-That ($regLife.code -eq 0) "register: $($regLife.output)"
        $capture = Invoke-Script (Join-Path $harness 'spec_catalog\capture-draft.ps1') @('-Slug', 'lifecycle', '-Text', 'Lifecycle') $repoLife @{ SZA_PROJECT_ROOT = $repoLife }
        Assert-That ($capture.code -eq 0 -and (Get-Content $queueFile -Raw) -match 'repo-life:S0001_lifecycle.*Draft') "local creation: $($capture.output)"
        $updateScript = Join-Path $harness 'spec_catalog\update.ps1'
        $update = Invoke-Script $updateScript @('-Id', 'S0001', '-Status', 'In Progress') $repoLife @{ SZA_PROJECT_ROOT = $repoLife }
        Assert-That ($update.code -eq 0 -and (Get-Content $queueFile -Raw) -match 'repo-life:S0001_lifecycle[^\r\n]*In Progress') "status update: $($update.output)"
        $update = Invoke-Script $updateScript @('-Id', 'S0001', '-Status', 'Implemented') $repoLife @{ SZA_PROJECT_ROOT = $repoLife }
        Assert-That ($update.code -eq 0 -and (Get-Content $queueFile -Raw) -notmatch 'repo-life:S0001') "last completion: $($update.output)"
        $update = Invoke-Script $updateScript @('-Id', 'S0001', '-Status', 'Broken') $repoLife @{ SZA_PROJECT_ROOT = $repoLife }
        Assert-That ($update.code -eq 0 -and (Get-Content $queueFile -Raw) -match 'repo-life:S0001_lifecycle[^\r\n]*Broken') "reopen: $($update.output)"
        $backup = "$queueFile.test-backup"
        Move-Item -LiteralPath $queueFile -Destination $backup
        try {
            $update = Invoke-Script $updateScript @('-Id', 'S0001', '-Status', 'In Progress') $repoLife @{ SZA_PROJECT_ROOT = $repoLife }
            Assert-That ($update.code -eq 0 -and $update.output -match 'portfolio queue not refreshed' -and $update.output -match 'pq sync') "projection failure was not reported: $($update.output)"
            Assert-That ((Get-Content (Join-Path $repoLife 'PLAN\RELEASE_QUEUE.md') -Raw) -match 'S0001_lifecycle[^\r\n]*In Progress') 'local status was lost when portfolio sync failed'
        } finally { Move-Item -LiteralPath $backup -Destination $queueFile -Force }
        $repair = Invoke-PqCli @('sync', '-Path', $repoLife)
        Assert-That ($repair.code -eq 0 -and (Get-Content $queueFile -Raw) -match 'repo-life:S0001_lifecycle[^\r\n]*In Progress') "repair: $($repair.output)"
        $localQueue = Join-Path $repoLife 'PLAN\RELEASE_QUEUE.md'
        Move-Item -LiteralPath $localQueue -Destination "$localQueue.test-backup"
        try {
            $update = Invoke-Script $updateScript @('-Id', 'S0001', '-Status', 'Broken') $repoLife @{ SZA_PROJECT_ROOT = $repoLife }
            Assert-That ($update.code -eq 0 -and $update.output -match 'portfolio queue not refreshed') "missing local queue was not reported: $($update.output)"
        } finally { Move-Item -LiteralPath "$localQueue.test-backup" -Destination $localQueue -Force }
        $repair = Invoke-Script (Join-Path $harness 'spec_catalog\release-queue.ps1') @('-Reconcile') $repoLife @{ SZA_PROJECT_ROOT = $repoLife }
        Assert-That ($repair.code -eq 0 -and (Get-Content $queueFile -Raw) -match 'repo-life:S0001_lifecycle[^\r\n]*Broken') "local repair: $($repair.output)"
    }

    Run-Case '1 words verbatim, ledger and queue rows, exact result line' {
        $f = Write-Text 'owner1.txt' $tricky
        $r = Invoke-Draft @('-Project', 'repo-a', '-Slug', 'bugfix-grid-crash', '-TextFile', $f, '-Complexity', 'light - one crash site')
        Assert-That ($r.code -eq 0) "exit $($r.code): $($r.output)"
        Assert-That ($r.last -ceq 'drafted repo-a:S0001 file=PLAN/S0001_bugfix-grid-crash.md priority=90 pq=dispatchable position=1/1') "result line: $($r.last)"
        $spec = [IO.File]::ReadAllText((Join-Path $repoA 'PLAN\S0001_bugfix-grid-crash.md'))
        Assert-That ($spec.Contains($tricky)) 'the owner text is not in the spec byte for byte'
        Assert-That ($spec -match '(?m)^\*\*Complexity:\*\* light - one crash site\r?$') 'the Complexity line is missing'
        Assert-That ((Get-Content (Join-Path $repoA 'PLAN\RELEASE_QUEUE.md') -Raw) -match 'S0001_bugfix-grid-crash') 'no row in the ticket queue'
        Assert-That ((Get-Content $queueFile -Raw) -match 'repo-a:S0001_bugfix-grid-crash') 'no row in the portfolio queue'
        $v = Invoke-Script (Join-Path $harness 'spec_catalog\validate.ps1') @() $repoA @{ SZA_PROJECT_ROOT = $repoA }
        Assert-That ($v.code -eq 0) "validate.ps1 exit $($v.code): $($v.output)"
    }

    Run-Case '2 later tickets land behind it; the position is the picker''s; a hotfix is told how to jump' {
        $f = Write-Text 'owner2.txt' 'Add CSV export to the list screen.'
        $r = Invoke-Draft @('-Project', 'repo-a', '-Slug', 'add-csv-export', '-TextFile', $f)
        Assert-That ($r.code -eq 0 -and $r.last -ceq 'drafted repo-a:S0002 file=PLAN/S0002_add-csv-export.md priority=50 pq=dispatchable position=2/2') "second: $($r.last) | $($r.output)"
        Assert-That ($r.stdout -match '#2 of 2 in its own queue; 1 run before it') "no position sentence: $($r.stdout)"
        $f = Write-Text 'owner3.txt' 'Boot loop on cold start.'
        $r = Invoke-Draft @('-Project', 'repo-a', '-Slug', 'hotfix-boot-loop', '-TextFile', $f)
        Assert-That ($r.code -eq 0 -and $r.last -ceq 'drafted repo-a:S0003 file=PLAN/S0003_hotfix-boot-loop.md priority=95 pq=dispatchable position=3/3') "hotfix: $($r.last) | $($r.output)"
        Assert-That ($r.stdout -match 'pq pin repo-a:S0003') "no pin hint: $($r.stdout)"
    }

    Run-Case '3 -Pin writes PORTFOLIO_QUEUE.md' {
        $before = Get-FileHashOf $queueFile
        $f = Write-Text 'owner4.txt' 'Urgent: sync crash.'
        $r = Invoke-Draft @('-Project', 'repo-a', '-Slug', 'hotfix-sync-crash', '-TextFile', $f, '-Pin')
        Assert-That ($r.code -eq 0 -and $r.stdout -match 'pq: pinned - repo-a:S0004') "not pinned: $($r.output)"
        Assert-That ((Get-FileHashOf $queueFile) -cne $before) 'the queue file did not change'
        Assert-That ((Get-Content $queueFile -Raw) -match '(?m)^repo-a:S0004(?:_|\s|$)') 'no pin row in PORTFOLIO_QUEUE.md'
    }

    Run-Case '4 a project under hold is captured into, reported not dispatched, and -Pin is refused' {
        Add-Content -LiteralPath $queueFile -Value "`nhold`nrepo-a   # test hold" -Encoding utf8
        $ledgerBefore = Get-LedgerCount $repoA
        $f = Write-Text 'owner5.txt' 'Held project ticket.'
        $r = Invoke-Draft @('-Project', 'repo-a', '-Slug', 'held-one', '-TextFile', $f)
        Assert-That ($r.code -eq 0 -and $r.last -match 'pq=held-by-queue ') "verdict: $($r.last) | $($r.output)"
        Assert-That ($r.stdout -match "NOT dispatched - repo-a sits under 'hold'") "no hold sentence: $($r.stdout)"
        Assert-That ((Get-LedgerCount $repoA) -gt $ledgerBefore) 'the ticket was not captured'
        $f = Write-Text 'owner6.txt' 'Held and pinned.'
        $r = Invoke-Draft @('-Project', 'repo-a', '-Slug', 'held-two', '-TextFile', $f, '-Pin')
        Assert-That ($r.code -eq 0 -and $r.stdout -match 'pin refused') "pin not refused: $($r.output)"
        $heldQueue = Get-Content $queueFile -Raw
        Assert-That ($heldQueue -match 'repo-a:S0005_held-one' -and $heldQueue -match 'repo-a:S0006_held-two' -and $heldQueue -match 'hold\s+repo-a\s+# test hold') 'tickets or project hold missing from portfolio queue'
    }

    $repoFree = New-Repo 'repo-free'
    Run-Case '5 an unregistered project is captured into and reported; the registry is untouched' {
        $regFile = Join-Path $portfolioRoot 'repos.json'
        $before = Get-FileHashOf $regFile
        $f = Write-Text 'owner7.txt' 'Task for an unregistered project.'
        $r = Invoke-Draft @('-Project', $repoFree, '-Slug', 'first-task', '-TextFile', $f)
        Assert-That ($r.code -eq 0 -and $r.last -ceq 'drafted repo-free:S0001 file=PLAN/S0001_first-task.md priority=50 pq=unregistered position=0/0') "result: $($r.last) | $($r.output)"
        Assert-That ($r.stdout -match 'NOT registered' -and $r.stdout -match 'register -Path') "no registration advice: $($r.stdout)"
        Assert-That ((Get-FileHashOf $regFile) -ceq $before) 'the registry was written'
    }

    Run-Case '6 no -Project: the project is found from the current folder' {
        $sub = Join-Path $repoFree 'docs\deep'
        New-Item -ItemType Directory -Path $sub -Force | Out-Null
        $f = Write-Text 'owner8.txt' 'Found from a subfolder.'
        $r = Invoke-Draft @('-Slug', 'from-subfolder', '-TextFile', $f) $sub
        Assert-That ($r.code -eq 0 -and $r.last -match '^drafted repo-free:S0002 ') "result: $($r.last) | $($r.output)"
    }

    Run-Case '7 a project''s own scripts/utils/capture-draft.ps1 is used instead of the canon''s' {
        $repoOwn = New-Repo 'repo-own'
        $utils = Join-Path $repoOwn 'scripts\utils'
        New-Item -ItemType Directory -Path $utils -Force | Out-Null
        $stub = @'
param([string]$Slug, [string]$TextFile, [int]$Priority = -1, [string]$Complexity = '', [string]$DedupQuery = '', [switch]$AllowClosedDuplicate, [string]$Attach = '')
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'stub-called.txt'), "$Slug|$Priority|$Attach|$([IO.File]::ReadAllText($TextFile))")
Write-Host "S0001 $Slug - Draft. Captured: 1 chars + 0 attachment(s)."
exit 0
'@
        [IO.File]::WriteAllText((Join-Path $utils 'capture-draft.ps1'), $stub)
        $f = Write-Text 'owner9.txt' 'Handled by the project script.'
        $r = Invoke-Draft @('-Project', $repoOwn, '-Slug', 'bugfix-own-path', '-TextFile', $f, '-Attach', 'x.png')
        Assert-That ($r.code -eq 0) "exit $($r.code): $($r.output)"
        $called = [IO.File]::ReadAllText((Join-Path $utils 'stub-called.txt'))
        Assert-That ($called -ceq 'bugfix-own-path|90|x.png|Handled by the project script.') "stub saw: $called"
        Assert-That ($r.last -match '^drafted repo-own:S0001 ') "result: $($r.last)"
    }

    Run-Case '8 refusals exit 2 and create nothing; -WhatIf creates nothing' {
        $ledger = Get-LedgerCount $repoFree
        $good = Write-Text 'owner10.txt' 'Some text.'
        $empty = Write-Text 'empty.txt' "  `r`n"
        $bare = Join-Path $scratch 'bare'; New-Item -ItemType Directory -Path $bare | Out-Null
        $cases = @(
            @{ n = 'bad slug'; a = @('-Project', $repoFree, '-Slug', 'Bad_Slug', '-TextFile', $good); m = 'invalid -Slug' },
            @{ n = 'spec_ slug'; a = @('-Project', $repoFree, '-Slug', 'spec_x', '-TextFile', $good); m = 'invalid -Slug' },
            @{ n = 'no text file'; a = @('-Project', $repoFree, '-Slug', 'ok-slug'); m = '-TextFile' },
            @{ n = 'empty text'; a = @('-Project', $repoFree, '-Slug', 'ok-slug', '-TextFile', $empty); m = 'text is empty' },
            @{ n = 'unknown project'; a = @('-Project', 'no-such-key', '-Slug', 'ok-slug', '-TextFile', $good); m = 'registered: repo-a' },
            @{ n = 'no task flow'; a = @('-Project', $bare, '-Slug', 'ok-slug', '-TextFile', $good); m = 'task-flow-init' },
            @{ n = 'attach without a script that takes it'; a = @('-Project', $repoFree, '-Slug', 'ok-slug', '-TextFile', $good, '-Attach', 'a.png'); m = 'attachments' }
        )
        foreach ($c in $cases) {
            $r = Invoke-Draft $c.a
            Assert-That ($r.code -eq 2) "$($c.n): expected exit 2, got $($r.code): $($r.output)"
            Assert-That ($r.output -match [regex]::Escape($c.m)) "$($c.n): message lacks '$($c.m)': $($r.output)"
        }
        Assert-That ((Get-LedgerCount $repoFree) -eq $ledger) 'a refusal created a ledger row'
        $r = Invoke-Draft @('-Project', $repoFree, '-Slug', 'would-be', '-TextFile', $good, '-WhatIf')
        Assert-That ($r.code -eq 0 -and $r.stdout -match 'nothing was created') "-WhatIf: $($r.output)"
        Assert-That ((Get-LedgerCount $repoFree) -eq $ledger) '-WhatIf created a ledger row'
    }
}
finally {
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
    else { Write-Host "scratch kept: $scratch" }
}

Write-Host ''
Write-Host "spec-draft: $passed/$run passed, $failed failed"
exit $(if ($failed -gt 0 -or $run -eq 0) { 1 } else { 0 })
