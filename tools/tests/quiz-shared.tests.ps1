#requires -Version 7.0
<#
.SYNOPSIS
    Cases for the shared items of tools/harness/portfolio/quiz-list.ps1 - one question or owner action that several
    waiting tickets carry.

.DESCRIPTION
    Runs the script over two throwaway repositories and a throwaway portfolio root with hand-written ledgers and spec
    files; the real registry and the real ledgers are never read or written. Starts no agent and no pq child.

      1. Two owner actions that differ only in the ticket ids they name, in two projects, print as one `shared:` line
         naming both; a question of two current blocks does the same.
      2. An action one ticket carries alone, two actions that differ in a name, and an action already marked done are
         not shared.
      3. -Json carries the shared items on the records they name, and an empty list on the others.
      4. It writes nothing: every ledger and spec file hashes the same after the runs.
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

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('quiz-shared-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null
$savedRoot = $env:SZA_PORTFOLIO_ROOT
$portfolio = Join-Path $scratch 'portfolio'
New-Item -ItemType Directory -Path $portfolio | Out-Null

function New-Project([string] $Key, [object[]] $Tickets) {
    $root = Join-Path $scratch $Key
    New-Item -ItemType Directory -Path (Join-Path $root 'PLAN') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $root '.sza-profile.json'), '{}')
    $rows = foreach ($t in $Tickets) {
        [IO.File]::WriteAllText((Join-Path $root "PLAN\$($t.id)_x.md"), $t.spec, [Text.UTF8Encoding]::new($false))
        ConvertTo-Json -Compress -InputObject ([ordered]@{ id = $t.id; name = "name-$($t.id)"; status = 'BlockQuestions'; priority = 50
                file = "PLAN/$($t.id)_x.md"; created = '2026-11-20'; updated = '2026-11-20 10:00'; statusNote = $t.note })
    }
    [IO.File]::WriteAllText((Join-Path $root 'PLAN\spec-catalog.jsonl'), (($rows -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    return $root
}
function New-Spec([string] $Do, [string] $Question = '') {
    $text = "# ticket`n`n### 3.3 Owner inputs (Approval gate)`n`n- **DO:** $Do`n"
    if ($Question) { $text += "`n### Questions (v1, 2026-11-20)`n- Q: $Question`n  - yes - one line (recommended)`n  - no - one line`n" }
    return $text
}

$alpha = New-Project 'alpha' @(
    @{ id = 'ALPHAX-0001'; note = 'DO: walk the gate'; spec = (New-Spec 'Sign in to the console and finish ALPHAX-0001.' 'ship the two panels together?') },
    @{ id = 'ALPHAX-0002'; note = 'DO: only here'; spec = (New-Spec 'Create the project **first** in the console.') },
    @{ id = 'ALPHAX-0003'; note = 'DO: marked'; spec = (New-Spec 'Plug the phone in. - done 2026-11-21: seen') })
$beta = New-Project 'beta' @(
    @{ id = 'BETAXX-0007'; note = 'DO: walk the other gate'; spec = (New-Spec 'Sign in to the console  and finish `beta:BETAXX-0007`' 'Ship the two panels together?') },
    @{ id = 'BETAXX-0008'; note = 'DO: only there'; spec = (New-Spec 'Create the account **first** in the console.') },
    @{ id = 'BETAXX-0009'; note = 'DO: marked too'; spec = (New-Spec 'Plug the phone in. - done 2026-11-21: seen') })

$repos = foreach ($p in @(@('alpha', $alpha, 10), @('beta', $beta, 20))) {
    [ordered]@{ key = $p[0]; path = $p[1]; enabled = $true; maxWorkers = 1; concurrent = $false; role = 'product'; permissionMode = 'bypassPermissions'; rank = $p[2] }
}
[IO.File]::WriteAllText((Join-Path $portfolio 'repos.json'), (ConvertTo-Json -InputObject ([ordered]@{ schemaVersion = '1.0'; repos = @($repos) }) -Depth 5))

function Get-Hashes { @(Get-ChildItem -Path (Join-Path $alpha 'PLAN'), (Join-Path $beta 'PLAN') -File | Sort-Object FullName | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName).Hash }) -join ',' }
$before = Get-Hashes

try {
    $env:SZA_PORTFOLIO_ROOT = $portfolio
    $text = @(& $pwshExe -NoProfile -File $script_ -All)
    $textExit = $LASTEXITCODE
    $jsonText = (@(& $pwshExe -NoProfile -File $script_ -All -Json)) -join "`n"
    $jsonExit = $LASTEXITCODE
    $sharedLines = @($text | Where-Object { $_ -like 'shared:*' })

    Run-Case '1 the same action and question in two projects are one line' {
        Assert-That ($textExit -eq 0) "exit ${textExit}: $($text -join '; ')"
        Assert-That (@($sharedLines | Where-Object { $_ -like 'shared: DO  Sign in to the console*`[alpha:ALPHAX-0001, beta:BETAXX-0007`]' }).Count -eq 1) "DO line: $($sharedLines -join ' / ')"
        Assert-That (@($sharedLines | Where-Object { $_ -like 'shared: Q  *panels together?  `[alpha:ALPHAX-0001, beta:BETAXX-0007`]' }).Count -eq 1) "Q line: $($sharedLines -join ' / ')"
        Assert-That ($text[-1] -eq 'quiz-list: 6 in BlockQuestions across 2 project(s)') "result line: $($text[-1])"
    }
    Run-Case '2 different or settled actions are not shared' {
        Assert-That ($sharedLines.Count -eq 2) "expected 2 shared lines, got $($sharedLines.Count): $($sharedLines -join ' / ')"
    }
    Run-Case '3 json carries the items on the records they name' {
        Assert-That ($jsonExit -eq 0) "exit $jsonExit"
        $records = @(ConvertFrom-Json -InputObject $jsonText)
        $one = @($records | Where-Object { $_.id -eq 'BETAXX-0007' })[0]
        Assert-That (@($one.shared).Count -eq 2) "shared on BETAXX-0007: $(@($one.shared).Count)"
        Assert-That ((@($one.shared | Where-Object { $_.kind -eq 'DO' })[0].tickets -join ',') -eq 'alpha:ALPHAX-0001,beta:BETAXX-0007') 'tickets of the DO item'
        $alone = @($records | Where-Object { $_.id -eq 'ALPHAX-0002' })[0]
        Assert-That (@($alone.shared).Count -eq 0 -and $jsonText -match '"shared": \[\]') 'an unshared record carries an empty list'
    }
    Run-Case '4 writes nothing' { Assert-That ((Get-Hashes) -eq $before) 'a ledger or a spec file changed' }
}
finally {
    $env:SZA_PORTFOLIO_ROOT = $savedRoot
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ("quiz-shared tests: {0} run, {1} passed, {2} failed" -f $run, $passed, $failed)
exit $(if ($failed -eq 0) { 0 } else { 1 })
