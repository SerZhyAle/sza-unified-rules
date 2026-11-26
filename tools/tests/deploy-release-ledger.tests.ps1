#requires -Version 7.0
<#
.SYNOPSIS
    Cases for the release-ledger hooks in deploy.ps1 (Invoke-ReleaseLedgerStep, Test-ShipsToConsumers,
    Get-DeployChangeNote).

.DESCRIPTION
    The functions are lifted out of deploy.ps1 by its syntax tree and run against a scratch root and a stub `pwsh`
    command; nothing is pushed, no real ledger is written, and no child process starts, so the suite runs well under
    one second.

      1. deploy.ps1 parses, defines Invoke-ReleaseLedgerStep once, and guards the build and publish call sites.
      2. Test-ShipsToConsumers exempts docs/releases/ while still detecting consumer-facing files.
      3. Invoke-ReleaseLedgerStep passes build and publish arguments cleanly and returns 'ok'.
      4. A missing release-ledger.ps1 returns 'missing' without throwing.
      5. A non-zero exit (including stderr output) returns 'failed' with its warning and never fails the deploy.
      6. A throwing invocation returns 'failed' with its warning and never fails the deploy.
      7. Get-DeployChangeNote builds one line from the unpushed subjects, the changed rule documents and the
         per-folder counts; an explicit message replaces it; the deploy's own bookkeeping yields an empty line.
      8. Test-ShipsToConsumers ships a facts record under rules/contrib/ and exempts rules/contrib/history/.
      9. The ship-package call follows publish, carries its own label and pins the project root for the child.
     10. Get-DeployTickets over a fixture ledger finds the finished rows since the last deploy and the ids of the
         unpushed subjects, falls back to the added diff lines, and Get-DeployChangeNote turns the result into the
         subject, with the folder counts only when no id is found.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$deploy = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\deploy.ps1'))

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

$deployText = Get-Content -LiteralPath $deploy -Raw
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($deploy, [ref]$null, [ref]$parseErrors)
$fnStep = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-ReleaseLedgerStep' }, $true))
$fnShips = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-ShipsToConsumers' }, $true))
if ($fnStep.Count -eq 1) { . ([scriptblock]::Create($fnStep[0].Extent.Text)) }
if ($fnShips.Count -eq 1) { . ([scriptblock]::Create($fnShips[0].Extent.Text)) }
$fnNote = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-DeployChangeNote' }, $true))
if ($fnNote.Count -eq 1) { . ([scriptblock]::Create($fnNote[0].Extent.Text)) }
$fnTickets = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-DeployTickets' }, $true))
if ($fnTickets.Count -eq 1) { . ([scriptblock]::Create($fnTickets[0].Extent.Text)) }

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('deploy-ledger-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$root = Join-Path $scratch 'repo'
$ledgerScript = Join-Path $root 'tools\harness\releases\release-ledger.ps1'
New-Item -ItemType Directory -Path (Split-Path $ledgerScript) -Force | Out-Null
[IO.File]::WriteAllText($ledgerScript, '')
$emptyRoot = Join-Path $scratch 'empty'
New-Item -ItemType Directory -Path $emptyRoot -Force | Out-Null

$script:calls = @()
$script:stubCode = 0
$script:stubMode = 'ok'
function fake-ledger-pwsh {
    $script:calls += , @($args)
    if ($script:stubMode -eq 'throw') { throw 'cannot launch pwsh' }
    if ($script:stubMode -eq 'fail') {
        Write-Error 'release-ledger: simulated write failure'
        $global:LASTEXITCODE = $script:stubCode
        return
    }
    $global:LASTEXITCODE = 0
    'release-ledger: simulated ok'
}

function Invoke-Step([string] $TargetRoot, [string[]] $StepArgs, [string] $Mode = 'ok', [int] $Code = 0) {
    $script:calls = @()
    $script:stubMode = $Mode
    $script:stubCode = $Code
    $all = @(Invoke-ReleaseLedgerStep -Root $TargetRoot -Arguments $StepArgs -Pwsh 'fake-ledger-pwsh' 6>&1)
    $result = @($all | Where-Object { $_ -is [string] }) | Select-Object -Last 1
    $text = (@($all | Where-Object { $_ -is [Management.Automation.InformationRecord] } | ForEach-Object { [string]$_.MessageData }) -join "`n")
    return [pscustomobject]@{ result = $result; text = $text; calls = @($script:calls) }
}

try {
    Run-Case '1 parses, defines helper once, guards build and publish call sites' {
        Assert-That (@($parseErrors).Count -eq 0) "parse errors: $(@($parseErrors) -join '; ')"
        Assert-That ($fnStep.Count -eq 1) 'Invoke-ReleaseLedgerStep is not defined exactly once'
        Assert-That ($fnShips.Count -eq 1) 'Test-ShipsToConsumers is not defined exactly once'
        $buildSiteStart = $deployText.IndexOf('if (-not $DryRun)')
        $buildSiteEnd = $deployText.IndexOf('# The two version files', $buildSiteStart)
        Assert-That ($buildSiteStart -ge 0 -and $buildSiteEnd -gt $buildSiteStart) 'build call site not found'
        $buildSite = $deployText.Substring($buildSiteStart, $buildSiteEnd - $buildSiteStart)
        Assert-That ($buildSite.Contains('Invoke-ReleaseLedgerStep') -and $buildSite.Contains("'build'") -and $buildSite.Contains("'sza'") -and $buildSite.Contains("'release'")) "unexpected build call site: $buildSite"
        Assert-That ($buildSite -notmatch '\bFail\b|\bexit\b') "build call site must not fail deploy: $buildSite"
        Assert-That ($buildSite.Contains("@('-Note', `$changeNote)")) "build call site does not pass the change note: $buildSite"
        Assert-That (-not $deployText.Contains('CANON_VERSION $canonNote')) 'the note that restates the version is still there'

        $pubSiteStart = $deployText.IndexOf('$cacheState = Update-PluginCache')
        Assert-That ($pubSiteStart -ge 0) 'publish call site not found'
        $pubSite = $deployText.Substring($pubSiteStart)
        Assert-That ($pubSite.Contains("if (`$bumpedVersion -and `$cacheState -in @('updated', 'current'))")) 'publish guard missing'
        Assert-That ($pubSite.Contains('Invoke-ReleaseLedgerStep') -and $pubSite.Contains("'publish'") -and $pubSite.Contains("'marketplace'") -and $pubSite.Contains("'live'")) "unexpected publish call site: $pubSite"
        Assert-That ($pubSite -notmatch '\bFail\b') "publish call site must not Fail deploy: $pubSite"
    }

    Run-Case '2 Test-ShipsToConsumers exempts docs/releases/ only' {
        Assert-That (-not (Test-ShipsToConsumers @('docs/releases/history.jsonl', 'docs/releases/RELEASES.md'))) 'ledger-only changes should not bump version'
        Assert-That (Test-ShipsToConsumers @('docs/releases/history.jsonl', 'rules/INVARIANTS.md')) 'consumer change beside ledger must bump version'
    }

    Run-Case '3 build and publish pass arguments and return ok' {
        $b = Invoke-Step -TargetRoot $root -StepArgs @('build', '-Package', 'sza', '-Kind', 'release', '-Version', '2026.1117.3', '-Note', 'rules: AUTHOR; tools 2')
        Assert-That ($b.result -eq 'ok') "build result: $($b.result)"
        Assert-That ($b.calls.Count -eq 1) "calls: $($b.calls.Count)"
        $bArgs = $b.calls[0] -join ' '
        Assert-That ($bArgs.Contains("-File $ledgerScript build -Package sza -Kind release -Version 2026.1117.3 -Note rules: AUTHOR; tools 2")) "build args: $bArgs"

        $p = Invoke-Step -TargetRoot $root -StepArgs @('publish', '-Key', 'marketplace', '-Version', '2026.1117.3', '-State', 'live', '-Ref', 'abc1234')
        Assert-That ($p.result -eq 'ok') "publish result: $($p.result)"
        $pArgs = $p.calls[0] -join ' '
        Assert-That ($pArgs.Contains('publish -Key marketplace -Version 2026.1117.3 -State live -Ref abc1234')) "publish args: $pArgs"
    }

    Run-Case '4 missing script returns missing without throwing' {
        $m = Invoke-Step -TargetRoot $emptyRoot -StepArgs @('build', '-Package', 'sza', '-Kind', 'release', '-Version', '2026.1117.3')
        Assert-That ($m.result -eq 'missing' -and $m.calls.Count -eq 0) "result: $($m.result), calls: $($m.calls.Count)"
        Assert-That ($m.text.Contains('release-ledger skipped')) "text: $($m.text)"
    }

    Run-Case '5 non-zero exit returns failed with warning without throwing' {
        $f = Invoke-Step -TargetRoot $root -StepArgs @('publish', '-Key', 'marketplace', '-Version', '2026.1117.3', '-State', 'live') -Mode 'fail' -Code 2
        Assert-That ($f.result -eq 'failed') "result: $($f.result)"
        Assert-That ($f.text.Contains('exited 2') -and $f.text.Contains('simulated write failure')) "text: $($f.text)"
    }

    Run-Case '6 throwing invocation returns failed with warning without throwing' {
        $t = Invoke-Step -TargetRoot $root -StepArgs @('build', '-Package', 'sza', '-Kind', 'release', '-Version', '2026.1117.3') -Mode 'throw'
        Assert-That ($t.result -eq 'failed') "result: $($t.result)"
        Assert-That ($t.text.Contains('release-ledger failed') -and $t.text.Contains('cannot launch pwsh')) "text: $($t.text)"
    }

    Run-Case '7 Get-DeployChangeNote builds one line from subjects, rule docs and folder counts' {
        Assert-That ($fnNote.Count -eq 1) 'Get-DeployChangeNote is not defined exactly once'
        $full = Get-DeployChangeNote -Paths @(
            'rules/TESTING_AND_QA.md', 'rules/AUTHOR.md', 'rules/contrib/filedo.md', 'tools/a.ps1', 'tools\harness\b.ps1',
            'skills/x/SKILL.md', 'deploy.ps1', 'docs/releases/history.jsonl', 'CANON_VERSION', '.claude-plugin/plugin.json'
        ) -Subjects @('Add the inbox listener (S0046)', 'Canon update 2026-11-17', 'Add the inbox listener (S0046)')
        Assert-That ($full -ceq 'Add the inbox listener (S0046); rules: AUTHOR, TESTING_AND_QA; tools 2, contrib 1, root 1, skills 1') "full: $full"

        $explicit = Get-DeployChangeNote -Message "Fix the `"digest`"`nsecond line" -Paths @('tools/a.ps1') -Subjects @('ignored')
        Assert-That ($explicit -ceq "Fix the 'digest'") "explicit: $explicit"

        $own = Get-DeployChangeNote -Paths @('docs/releases/history.jsonl', 'docs/releases/RELEASES.md', 'CANON_VERSION')
        Assert-That ($own -ceq '') "bookkeeping only: $own"

        $many = Get-DeployChangeNote -Paths @('tools/a.ps1') -Subjects @('s1', 's2', 's3', 's4', 's5', 's6')
        Assert-That ($many -ceq 's1; s2; s3; s4; +2 more; tools 1') "many: $many"

        $dash = Get-DeployChangeNote -Subjects @('- leading dash subject')
        Assert-That ($dash -ceq 'leading dash subject') "dash: $dash"

        Assert-That ($deployText.Contains('$changeNote = Get-DeployChangeNote -Message $Message')) 'the note is never built'
        Assert-That ($deployText.Contains('git -C $root commit @commitArgs')) 'the commit does not take the built arguments'
    }

    Run-Case '8 Test-ShipsToConsumers ships a facts record, exempts its history' {
        Assert-That (Test-ShipsToConsumers @('rules/contrib/sample.md')) 'a facts record is read from the plugin cache and must bump the version'
        Assert-That (Test-ShipsToConsumers @('rules\contrib\TEMPLATE.md')) 'a backslash path must be normalized before the exemption test'
        Assert-That (-not (Test-ShipsToConsumers @('rules/contrib/history/sample.md'))) 'a history-only change should not bump the version'
        Assert-That (-not (Test-ShipsToConsumers @('rules\contrib\history\sample.md', 'docs/releases/history.jsonl'))) 'history beside the ledger should not bump the version'
    }

    Run-Case '9 ship-package runs after publish with its own label and a pinned project root' {
        $pubSite = $deployText.Substring($deployText.IndexOf('$cacheState = Update-PluginCache'))
        $shipAt = $pubSite.IndexOf("-Label 'ship-package'")
        Assert-That ($shipAt -gt $pubSite.IndexOf("'publish'")) 'ship-package is not called after publish'
        Assert-That ($pubSite.Contains('tools\harness\spec_catalog\ship-package.ps1') -and $pubSite.Contains("-Arguments @('-Version', `$bumpedVersion)")) 'the ship-package script or its version argument is missing'
        Assert-That ($pubSite.Contains('$env:SZA_PROJECT_ROOT = $root') -and $pubSite.Contains('$env:SZA_PROJECT_ROOT = $prevProjectRoot')) 'the project root is not pinned and restored'
        $script:calls = @()
        $all = @(Invoke-ReleaseLedgerStep -Root $emptyRoot -Arguments @('-Version', '2026.1118.2') -Pwsh 'fake-ledger-pwsh' -Label 'ship-package' -ScriptRel 'tools\harness\spec_catalog\ship-package.ps1' 6>&1)
        $text = (@($all | Where-Object { $_ -is [Management.Automation.InformationRecord] } | ForEach-Object { [string]$_.MessageData }) -join "`n")
        Assert-That ((@($all | Where-Object { $_ -is [string] }) | Select-Object -Last 1) -eq 'missing') 'a missing ship-package.ps1 must return missing'
        Assert-That ($text.Contains('deploy: ship-package skipped') -and -not $text.Contains('release-ledger')) "the label is not used: $text"
    }

    Run-Case '10 the subject names the tickets, folder counts only without an id' {
        Assert-That ($fnTickets.Count -eq 1) 'Get-DeployTickets is not defined exactly once'
        # Local times on both sides, so the case does not depend on the machine's zone.
        $since = [datetimeoffset]::new([datetime]::new(2026, 11, 26, 3, 2, 13, [DateTimeKind]::Local)).ToString('o')
        $rows = @(
            [pscustomobject]@{ id = 'CANONR-0203'; status = 'Verified'; updated = '2026-11-26 04:42'; title = 'Second change' }
            [pscustomobject]@{ id = 'CANONR-0201'; status = 'Implemented'; updated = '2026-11-26 03:02'; title = 'First change' }
            [pscustomobject]@{ id = 'CANONR-0200'; status = 'Implemented'; updated = '2026-11-26 03:01'; title = 'Shipped before' }
            [pscustomobject]@{ id = 'CANONR-0204'; status = 'Draft'; updated = '2026-11-26 05:00'; title = 'Only captured' }
            [pscustomobject]@{ id = 'CANONR-0205'; status = 'Partial'; updated = '2026-11-26 05:00' }
        )
        $moved = @(Get-DeployTickets -Rows $rows -Since $since -AddedLines @('+ cites CANONR-0200'))
        Assert-That (($moved.id -join ' ') -ceq 'CANONR-0201 CANONR-0203 CANONR-0205') "moved: $($moved.id -join ' ')"
        Assert-That ($moved[2].title -ceq '') "a row without a title: $($moved[2].title)"

        $subjects = @(Get-DeployTickets -Rows $rows -Subjects @('Fix the gate (CANONR-0199)') -AddedLines @('+ CANONR-0200'))
        Assert-That (($subjects.id -join ' ') -ceq 'CANONR-0199') "subject ids: $($subjects.id -join ' ')"

        $diff = @(Get-DeployTickets -Rows $rows -AddedLines @('+ CANONR-0200 and CANONR-9999'))
        Assert-That (($diff.id -join ' ') -ceq 'CANONR-0200') "diff ids: $($diff.id -join ' ')"

        $note = Get-DeployChangeNote -Paths @('tools/a.ps1', 'rules/AUTHOR.md') -Subjects @('ignored') -Tickets $moved
        Assert-That ($note -ceq 'CANONR-0201, CANONR-0203, CANONR-0205: First change') "note: $note"

        $none = @(Get-DeployTickets -Rows @() -Since $since)
        Assert-That ($none.Count -eq 0) "no id expected: $($none.Count)"
        $counts = Get-DeployChangeNote -Paths @('tools/a.ps1') -Tickets $none
        Assert-That ($counts -ceq 'tools 1') "fallback: $counts"

        $pubSite = $deployText.Substring($deployText.IndexOf('$cacheState = Update-PluginCache'))
        Assert-That ($pubSite.Contains("`$publishArgs += @('-Note'")) 'the publish row does not get the ids'
    }
}
finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "deploy-release-ledger tests: $run run, $passed passed, $failed failed"
if ($failed -gt 0) { exit 1 }
exit 0
