#requires -Version 7.0
<#
.SYNOPSIS
    Cases for the fast-gate report of deploy.ps1 (Invoke-FastGateReport).

.DESCRIPTION
    The function is lifted out of deploy.ps1 by its syntax tree and run against a scratch root of empty gate scripts
    and stub `pwsh` / `py` functions that return a chosen exit code; nothing is pushed and no child process starts,
    so the file takes well under a second.

      1. deploy.ps1 parses, defines the function once, and calls it with the canon gate's own code.
      2. All four green: four entries named in order, all ok.
      3. A red gate: its exit code and the last lines of its output are reported, the others stay ok.
      4. A gate script that is missing, a catalog that is not there, no Python on PATH, a tool that throws:
         each is 'unavailable' with a reason, and no other gate is skipped because of it.
      5. A non-zero canon code is reported red.
      6. The call site is advisory: it contains no Fail and no exit.
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
$fn = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-FastGateReport' }, $true))
if ($fn.Count -eq 1) { . ([scriptblock]::Create($fn[0].Extent.Text)) }

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('deploy-gates-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null
$catalog = Join-Path $scratch 'catalog'
New-Item -ItemType Directory -Path $catalog | Out-Null

# The stubs answer by the name of the script they are given; the arguments are recorded.
$script:codes = @{}
$script:calls = @()
$script:throwOn = ''
function fake-gate-tool {
    $script = if ($args[0] -eq '-NoProfile') { $args[2] } else { $args[0] }
    $name = Split-Path $script -Leaf
    $script:calls += $name
    if ($script:throwOn -eq $name) { throw 'cannot start' }
    $code = if ($script:codes.ContainsKey($name)) { $script:codes[$name] } else { 0 }
    if ($code -ne 0) { 'first line'; 'second line'; 'third line'; "verdict: $name red" }
    $global:LASTEXITCODE = $code
}

function New-Root([string[]] $Omit = @()) {
    $root = Join-Path $scratch ([guid]::NewGuid().ToString('N').Substring(0, 6))
    foreach ($rel in 'tools\check-contracts.ps1', 'tools\docs\check-documents.py', 'tools\harness\assert-portable.ps1') {
        if ($Omit -contains $rel) { continue }
        $path = Join-Path $root $rel
        New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
        Set-Content -LiteralPath $path -Value ''
    }
    return $root
}

function Invoke-Report([string] $Root, [int] $Canon = 0, [string] $Contracts = $catalog, [string[]] $Python = @('fake-gate-tool')) {
    $script:calls = @()
    $all = @(Invoke-FastGateReport -Root $Root -CanonCode $Canon -ContractsRoot $Contracts -Pwsh 'fake-gate-tool' -PythonCandidates $Python 6>&1)
    $report = @($all | Where-Object { $_ -isnot [Management.Automation.InformationRecord] })
    $text = (@($all | Where-Object { $_ -is [Management.Automation.InformationRecord] } | ForEach-Object { [string]$_.MessageData }) -join "`n")
    return [pscustomobject]@{ report = $report; text = $text; calls = @($script:calls) }
}
function Get-Item-By([object] $Result, [string] $Name) { @($Result.report | Where-Object { $_.name -eq $Name })[0] }

try {
    Run-Case '1 parses, defined once, called with the canon code' {
        Assert-That (@($parseErrors).Count -eq 0) "parse errors: $(@($parseErrors) -join '; ')"
        Assert-That ($fn.Count -eq 1) 'Invoke-FastGateReport is not defined exactly once'
        Assert-That ($deployText.Contains('Invoke-FastGateReport -Root $root -CanonCode $gateCode -ContractsRoot $ctrRoot')) 'the function is never called with the canon gate code'
    }
    Run-Case '2 all green' {
        $r = Invoke-Report (New-Root)
        Assert-That (($r.report | ForEach-Object { $_.name }) -join ',' -eq 'check-rules,check-contracts,check-documents,assert-portable') "names: $(($r.report | ForEach-Object { $_.name }) -join ',')"
        Assert-That (@($r.report | Where-Object { $_.state -ne 'ok' -or $_.code -ne 0 }).Count -eq 0) 'a gate is not ok'
        Assert-That ($r.calls.Count -eq 3) "ran: $($r.calls -join ' | ')"
        Assert-That ($r.text.Contains('check-contracts') -and $r.text.Contains('exit 0')) "text: $($r.text)"
    }
    Run-Case '3 a red gate is named with its code and its last lines' {
        $script:codes = @{ 'assert-portable.ps1' = 1 }
        $r = Invoke-Report (New-Root)
        $script:codes = @{}
        $red = Get-Item-By $r 'assert-portable'
        Assert-That ($red.state -eq 'red' -and $red.code -eq 1) "state: $($red.state) code: $($red.code)"
        Assert-That ($red.why.Contains('verdict: assert-portable.ps1 red') -and -not $red.why.Contains('first line')) "why: $($red.why)"
        Assert-That ($r.text.Contains('assert-portable') -and $r.text.Contains('exit 1')) "text: $($r.text)"
        Assert-That ((Get-Item-By $r 'check-documents').state -eq 'ok' -and (Get-Item-By $r 'check-contracts').state -eq 'ok') 'a green gate was disturbed'
    }
    Run-Case '4a a missing gate script is unavailable, the rest still run' {
        $r = Invoke-Report (New-Root -Omit 'tools\docs\check-documents.py')
        $gone = Get-Item-By $r 'check-documents'
        Assert-That ($gone.state -eq 'unavailable' -and $null -eq $gone.code -and $gone.why.Contains('is missing')) "state: $($gone.state) why: $($gone.why)"
        Assert-That ($r.calls.Count -eq 2) "ran: $($r.calls -join ' | ')"
        Assert-That ($r.text.Contains('unavailable')) "text: $($r.text)"
    }
    Run-Case '4b no catalog: contracts unavailable, nothing run for it' {
        $r = Invoke-Report (New-Root) -Contracts (Join-Path $scratch 'no-such-catalog')
        $item = Get-Item-By $r 'check-contracts'
        Assert-That ($item.state -eq 'unavailable' -and $item.why.Contains('is not there')) "state: $($item.state) why: $($item.why)"
        Assert-That (-not ($r.calls -contains 'check-contracts.ps1')) 'the contracts gate ran without a catalog'
    }
    Run-Case '4c no Python on PATH: check-documents unavailable' {
        $r = Invoke-Report (New-Root) -Python @('no-such-python-launcher')
        $item = Get-Item-By $r 'check-documents'
        Assert-That ($item.state -eq 'unavailable' -and $item.why.Contains('no-such-python-launcher')) "state: $($item.state) why: $($item.why)"
        Assert-That ((Get-Item-By $r 'assert-portable').state -eq 'ok') 'the portability gate was skipped'
    }
    Run-Case '4d a tool that throws is unavailable, not a crash' {
        $script:throwOn = 'check-contracts.ps1'
        $r = Invoke-Report (New-Root)
        $script:throwOn = ''
        $item = Get-Item-By $r 'check-contracts'
        Assert-That ($item.state -eq 'unavailable' -and $item.why -eq 'cannot start') "state: $($item.state) why: $($item.why)"
        Assert-That ((Get-Item-By $r 'assert-portable').state -eq 'ok') 'the portability gate was skipped'
    }
    Run-Case '5 a non-zero canon code is red' {
        $r = Invoke-Report (New-Root) -Canon 1
        $item = Get-Item-By $r 'check-rules'
        Assert-That ($item.state -eq 'red' -and $item.code -eq 1) "state: $($item.state) code: $($item.code)"
    }
    Run-Case '6 the call site is advisory' {
        $start = $deployText.IndexOf('$fastGates = @(Invoke-FastGateReport')
        $end = $deployText.IndexOf('# --- 2.', $start)
        Assert-That ($start -ge 0 -and $end -gt $start) 'call site not found'
        $site = $deployText.Substring($start, $end - $start)
        Assert-That ($site -notmatch '\bFail\b|\bexit\b') "the call site blocks: $site"
    }
}
finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "deploy-fast-gates: run=$run passed=$passed failed=$failed"
if ($failed -gt 0) { exit 1 }
exit 0
