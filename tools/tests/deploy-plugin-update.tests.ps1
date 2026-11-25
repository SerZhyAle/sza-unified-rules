#requires -Version 7.0
<#
.SYNOPSIS
    Cases for the plugin-update step of deploy.ps1 (Update-PluginCache).

.DESCRIPTION
    The function is lifted out of deploy.ps1 by its syntax tree and run against a scratch plugin cache and a stub
    `claude`; nothing is pushed, no real plugin is touched, no child process starts, so the file takes well under a
    second.

      1. deploy.ps1 parses, and has the -NoPluginUpdate switch.
      2. A cache already at the pushed version: nothing runs.
      3. Behind, on main: the marketplace refresh, then the plugin update, in that order; the cache reaches the version.
      4. Behind, not on main: nothing runs and the message says why.
      5. -Skip: nothing runs and the manual commands are printed.
      6. No `claude` on PATH, or no cache folder: nothing runs, no throw.
      7. The update does not move the cache, or throws: reported as stale, the function still returns.
      8. The ZCode arguments: paths under the app and the home folder, the runtime switch, the manual command,
         and the call site after the Claude one.
      9. A ZCode run: the script goes before the verbs, the environment variable holds during both calls and is
         restored, also after a throw; the messages name ZCode.
#>
[CmdletBinding()]
param([switch] $KeepScratch)

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

$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($deploy, [ref]$null, [ref]$parseErrors)
$fn = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Update-PluginCache' }, $true))
if ($fn.Count -eq 1) { . ([scriptblock]::Create($fn[0].Extent.Text)) }
$fnZcode = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-ZCodeUpdateArgs' }, $true))
if ($fnZcode.Count -eq 1) { . ([scriptblock]::Create($fnZcode[0].Extent.Text)) }

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('deploy-update-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null
$pushed = '2026.1029.9'
$old = '2026.1029.5'

# The stub records its arguments; it moves the cache only when the case says it should.
$script:calls = @()
$script:mode = 'creates'
$script:cache = ''
function fake-claude {
    $script:calls += ($args -join ' ')
    if ($script:mode -eq 'throws') { throw 'boom' }
    if ($script:mode -eq 'creates' -and $args[1] -eq 'update') { New-Item -ItemType Directory -Path (Join-Path $script:cache $pushed) | Out-Null }
    'stub output'
}

function Invoke-Update([string] $Cached, [string] $Branch = 'main', [string] $Mode = 'creates', [switch] $Skip, [string] $Cli = 'fake-claude', [switch] $NoCache) {
    $root = Join-Path $scratch ([guid]::NewGuid().ToString('N').Substring(0, 6))
    New-Item -ItemType Directory -Path (Join-Path $root '.claude-plugin') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $root '.claude-plugin\plugin.json'), "{ `"name`": `"sza`", `"version`": `"$pushed`" }")
    $cache = Join-Path $root 'cache'
    if (-not $NoCache) {
        New-Item -ItemType Directory -Path (Join-Path $cache $Cached) -Force | Out-Null
    }
    $script:cache = $cache; $script:calls = @(); $script:mode = $Mode
    $all = @(Update-PluginCache -Root $root -Branch $Branch -CacheRoot $cache -Cli $Cli -Skip:$Skip 6>&1)
    $result = @($all | Where-Object { $_ -is [string] -and $_ -ne 'stub output' }) | Select-Object -Last 1
    $text = (@($all | Where-Object { $_ -is [Management.Automation.InformationRecord] } | ForEach-Object { [string]$_.MessageData }) -join "`n")
    return [pscustomobject]@{ result = $result; text = $text; calls = @($script:calls) }
}

try {
    Run-Case '1 parses, has the switch' {
        Assert-That (@($parseErrors).Count -eq 0) "parse errors: $(@($parseErrors) -join '; ')"
        Assert-That ($fn.Count -eq 1) 'Update-PluginCache is not defined exactly once'
        Assert-That (@($ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'NoPluginUpdate' }).Count -eq 1) 'no -NoPluginUpdate switch'
        Assert-That ($ast.Extent.Text.Contains('Update-PluginCache -Root $root -Branch $branch -Skip:$NoPluginUpdate')) 'the function is never called'
    }
    Run-Case '2 already current' {
        $r = Invoke-Update -Cached $pushed
        Assert-That ($r.result -eq 'current') "result: $($r.result)"
        Assert-That ($r.calls.Count -eq 0) "ran: $($r.calls -join ' | ')"
    }
    Run-Case '3 behind on main: refresh, then update' {
        $r = Invoke-Update -Cached $old
        Assert-That ($r.result -eq 'updated') "result: $($r.result) / $($r.text)"
        Assert-That (($r.calls -join ' | ') -eq 'plugin marketplace update sza-unified-rules | plugin update sza@sza-unified-rules') "calls: $($r.calls -join ' | ')"
        Assert-That ($r.text.Contains("now has plugin $pushed")) "text: $($r.text)"
        Assert-That ($r.text.Contains('restart open Claude sessions')) 'no restart hint'
    }
    Run-Case '4 not on main' {
        $r = Invoke-Update -Cached $old -Branch 'feature/x'
        Assert-That ($r.result -eq 'not-main' -and $r.calls.Count -eq 0) "result: $($r.result), calls: $($r.calls -join ' | ')"
        Assert-That ($r.text.Contains("'feature/x'") -and $r.text.Contains('follows main')) "text: $($r.text)"
    }
    Run-Case '5 -Skip' {
        $r = Invoke-Update -Cached $old -Skip
        Assert-That ($r.result -eq 'skipped' -and $r.calls.Count -eq 0) "result: $($r.result), calls: $($r.calls -join ' | ')"
        Assert-That ($r.text.Contains('claude plugin marketplace update sza-unified-rules; claude plugin update sza@sza-unified-rules')) "text: $($r.text)"
    }
    Run-Case '6 no claude, no cache' {
        $r = Invoke-Update -Cached $old -Cli 'no-such-cli-here'
        Assert-That ($r.result -eq 'no-cli' -and $r.text.Contains('is not on PATH')) "no cli: $($r.result) / $($r.text)"
        $n = Invoke-Update -Cached $old -NoCache
        Assert-That ($n.result -eq 'no-cache' -and $n.calls.Count -eq 0) "no cache: $($n.result)"
    }
    Run-Case '7 update that does not land, and one that throws' {
        $s = Invoke-Update -Cached $old -Mode 'nothing'
        Assert-That ($s.result -eq 'stale' -and $s.calls.Count -eq 2) "stale: $($s.result), calls: $($s.calls -join ' | ')"
        Assert-That ($s.text.Contains("still at $old")) "text: $($s.text)"
        $t = Invoke-Update -Cached $old -Mode 'throws'
        Assert-That ($t.result -eq 'stale' -and $t.text.Contains('the Claude plugin update failed')) "throws: $($t.result) / $($t.text)"
    }
    Run-Case '8 ZCode arguments and call site' {
        Assert-That ($fnZcode.Count -eq 1) 'Get-ZCodeUpdateArgs is not defined exactly once'
        $z = Get-ZCodeUpdateArgs -AppRoot (Join-Path $scratch 'app') -HomeRoot (Join-Path $scratch 'home')
        Assert-That ($z.Cli -eq (Join-Path $scratch 'app\ZCode.exe')) "cli: $($z.Cli)"
        Assert-That ((@($z.CliPrefix) -join '|') -eq (Join-Path $scratch 'app\resources\glm\zcode.cjs')) "prefix: $($z.CliPrefix)"
        Assert-That ($z.CacheRoot -eq (Join-Path $scratch 'home\.zcode\cli\plugins\cache\sza-unified-rules\sza')) "cache: $($z.CacheRoot)"
        Assert-That ($z.CliEnv['ELECTRON_RUN_AS_NODE'] -eq '1' -and $z.Product -eq 'ZCode') 'runtime switch or product name'
        Assert-That ($z.Manual.Contains('marketplace update sza-unified-rules') -and $z.Manual.Contains('update sza@sza-unified-rules') -and $z.Manual.Contains('$env:ELECTRON_RUN_AS_NODE=')) "manual: $($z.Manual)"
        $parse = $null
        $null = [Management.Automation.Language.Parser]::ParseInput($z.Manual, [ref]$null, [ref]$parse)
        Assert-That (@($parse).Count -eq 0) "the manual command does not parse: $($z.Manual)"
        $text = $ast.Extent.Text
        $claudeAt = $text.IndexOf('$cacheState = Update-PluginCache')
        $zcodeAt = $text.IndexOf('$null = Update-PluginCache -Root $root -Branch $branch -Skip:$NoPluginUpdate @zcode')
        Assert-That ($claudeAt -ge 0 -and $zcodeAt -gt $claudeAt) 'the ZCode update is not called after the Claude one'
    }
    Run-Case '9 ZCode run: prefix, environment, messages' {
        $root = Join-Path $scratch 'zroot'
        New-Item -ItemType Directory -Path (Join-Path $root '.claude-plugin') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $root '.claude-plugin\plugin.json'), "{ `"name`": `"sza`", `"version`": `"$pushed`" }")
        $cache = Join-Path $root 'cache'
        New-Item -ItemType Directory -Path (Join-Path $cache $old) -Force | Out-Null
        $script:seen = @()
        $script:boom = $false
        function fake-zcode {
            $script:seen += "$($env:SZA_TEST_RUNTIME):$($args -join ' ')"
            if ($script:boom) { throw 'boom' }
        }
        $env:SZA_TEST_RUNTIME = $null
        $run1 = @(Update-PluginCache -Root $root -Branch 'main' -CacheRoot $cache -Cli 'fake-zcode' -CliPrefix @('z.cjs') -CliEnv @{ SZA_TEST_RUNTIME = '1' } -Product 'ZCode' -Manual 'run-by-hand' 6>&1)
        Assert-That (($script:seen -join ' | ') -eq '1:z.cjs plugin marketplace update sza-unified-rules | 1:z.cjs plugin update sza@sza-unified-rules') "calls: $($script:seen -join ' | ')"
        Assert-That (-not $env:SZA_TEST_RUNTIME) 'the environment variable stayed set'
        $text = (@($run1 | Where-Object { $_ -is [Management.Automation.InformationRecord] } | ForEach-Object { [string]$_.MessageData }) -join "`n")
        Assert-That ($text.Contains('ZCode cache is still at') -and $text.Contains('run-by-hand') -and -not $text.Contains('Claude')) "text: $text"

        $env:SZA_TEST_RUNTIME = 'before'
        $script:boom = $true
        try {
            $null = Update-PluginCache -Root $root -Branch 'main' -CacheRoot $cache -Cli 'fake-zcode' -CliEnv @{ SZA_TEST_RUNTIME = '1' } -Product 'ZCode' 6>&1
            Assert-That ($env:SZA_TEST_RUNTIME -eq 'before') "not restored after a throw: $($env:SZA_TEST_RUNTIME)"
        }
        finally { $env:SZA_TEST_RUNTIME = $null }
    }
}
finally {
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ("deploy-plugin-update tests: {0} run, {1} passed, {2} failed" -f $run, $passed, $failed)
exit $(if ($failed -eq 0) { 0 } else { 1 })
