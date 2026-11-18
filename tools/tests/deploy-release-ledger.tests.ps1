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
}
finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "deploy-release-ledger tests: $run run, $passed passed, $failed failed"
if ($failed -gt 0) { exit 1 }
exit 0
