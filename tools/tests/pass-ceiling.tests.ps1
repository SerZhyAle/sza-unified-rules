#requires -Version 7.0
<# Fast pass ceiling and profile-reader cases. Exit 0 on success, 1 on a failed assertion. #>
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../harness/batch/_context-handoff.ps1')
. (Join-Path $PSScriptRoot '../harness/_profile.ps1')

function Assert-Equal($Actual, $Expected, [string] $Case) {
    if ($Actual -cne $Expected) { throw "$Case expected [$Expected], got [$Actual]" }
    Write-Host "PASS $Case"
}

$ceiling = @{ minutes = 45; usd = 15 }
Assert-Equal (Test-PassCeiling 44 14.99 $ceiling) $null 'below both ceilings'
Assert-Equal (Test-PassCeiling 45 $null $ceiling) 'minutes' 'elapsed ceiling with unknown cost'
Assert-Equal (Test-PassCeiling 44 $null $ceiling) $null 'unknown cost cannot reach the cost ceiling'
Assert-Equal (Test-PassCeiling 44 15 $ceiling) 'usd' 'exact cost ceiling'
Assert-Equal (Test-PassCeiling 46 16 $ceiling) 'minutes' 'both ceilings reached'
Assert-Equal (Test-PassCeiling 200 200 @{ minutes = 0; usd = $null }) $null 'individual ceilings disabled'
Assert-Equal (Test-PassCeiling 200 200 0) $null 'whole ceiling disabled by zero'
Assert-Equal (Test-PassCeiling 200 200 $null) $null 'whole ceiling disabled by null'

$runner = Join-Path $PSScriptRoot '../harness/batch/run-spec-queue.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($runner, [ref]$tokens, [ref]$errors)
Assert-Equal $errors.Count 0 'runner parses'
$resolve = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Resolve-RunOutcome'
}, $false)
. ([scriptblock]::Create($resolve.Extent.Text))
$verdictArgs = @{ Outcome = 'context-handoff'; ExitCode = 1; StatusBefore = 'In Progress'; StatusAfter = 'In Progress' }
Assert-Equal (Resolve-RunOutcome @verdictArgs).Outcome 'context-handoff' 'ceiling survives a stopped child exit code'
Assert-Equal (Resolve-RunOutcome @verdictArgs -LimitHit).Outcome 'limit-hit' 'provider limit takes precedence'
Assert-Equal (Resolve-RunOutcome @verdictArgs -ProviderErrorHit).Outcome 'provider-error' 'provider outage takes precedence'

$scratch = Join-Path (Get-SzaPath 'tempDir') ('pass-ceiling-tests-' + [guid]::NewGuid())
$prior = $env:SZA_PROFILE_PATH
try {
    $env:SZA_PROFILE_PATH = $scratch
    foreach ($case in @(
        @{ json = '{}'; minutes = 45; usd = 15 },
        @{ json = '{"runner":{"passCeiling":{"minutes":2.5}}}'; minutes = 2.5; usd = 15 },
        @{ json = '{"runner":{"passCeiling":{"minutes":null,"usd":0}}}'; minutes = $null; usd = 0 },
        @{ json = '{"runner":{"passCeiling":null}}'; whole = $null },
        @{ json = '{"runner":{"passCeiling":0}}'; whole = 0 },
        @{ json = '{"runner":{"passCeiling":{"minutes":"2"}}}'; error = 'runner.passCeiling.minutes' },
        @{ json = '{"runner":{"passCeiling":{"usd":-1}}}'; error = 'runner.passCeiling.usd' },
        @{ json = '{"runner":{"passCeiling":false}}'; error = 'runner.passCeiling' },
        @{ json = '{"runner":{"passCeiling":[]}}'; error = 'runner.passCeiling' }
    )) {
        [IO.File]::WriteAllText($scratch, $case.json)
        $Script:SzaProfileCache = $null
        if ($case.ContainsKey('error')) {
            $message = ''
            try { $null = Get-SzaProfile } catch { $message = $_.Exception.Message }
            Assert-Equal ($message.Contains($case.error)) $true "reject $($case.json)"
        } else {
            $actual = Get-SzaProfileValue 'runner.passCeiling'
            if ($case.ContainsKey('whole')) {
                Assert-Equal $actual $case.whole "read $($case.json)"
            } else {
                Assert-Equal $actual.minutes $case.minutes "minutes from $($case.json)"
                Assert-Equal $actual.usd $case.usd "usd from $($case.json)"
            }
        }
    }
} finally {
    $env:SZA_PROFILE_PATH = $prior
    Remove-Item -LiteralPath $scratch -ErrorAction SilentlyContinue
}
