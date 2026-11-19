#requires -Version 7.0
<#
.SYNOPSIS
    Fast direct-call proof of the model providers' shipped records (S0154): the Google provider is one Antigravity
    sign-in with four records (Hydrogen, Argon, Neon, Claude Sonnet via the Claude and GPT pool).

.DESCRIPTION
    No agent process, no real registry, no network: the CLI probe is a stub and the registry is a scratch file under
    SZA_PORTFOLIO_ROOT. Cases:

      1. The Google provider lists gemini, gemini-argon, gemini-neon, gemini-claude in that order, and `antigravity` /
         `agy` name it like `gemini` does.
      2. New-PqProviderRecord builds each record with its own model slug (Hydrogen, Argon, Neon, Claude Sonnet 5.5) over
         the same agy argument shape, and the four differ in nothing else that matters (command, detector, parallel).
      3. Set-PqAgentOrder on a registry that already holds gemini and gemini-argon adds only the missing
         gemini-neon and gemini-claude records, keeps the existing records untouched (their routes included), keeps
         the provider's records together in the order, and leaves a registry that validates.
      4. A registry that never had the later records still validates and the provider status row reads the two it has.
#>
$ErrorActionPreference = 'Stop'
$harness = Join-Path (Split-Path $PSScriptRoot -Parent) 'harness'
$pqLib = Join-Path $harness 'portfolio/lib'

. (Join-Path $harness 'batch/_limit-hold.ps1')
. (Join-Path $pqLib 'paths.ps1')
. (Join-Path $pqLib 'events.ps1')
. (Join-Path $pqLib 'registry.ps1')
. (Join-Path $pqLib 'loop.ps1')
. (Join-Path $pqLib 'ledger-watch.ps1')
. (Join-Path $pqLib 'agents.ps1')

# The probe of the CLI on this machine is replaced: the shipped record is what is judged, not where agy is installed.
function Find-PqProviderCli([string]$Id) { return @{ found = $true; command = 'agy-stub.exe'; prefix = @(); note = '' } }

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('pq-providers-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($scratch)
$origEnv = $env:SZA_PORTFOLIO_ROOT
$env:SZA_PORTFOLIO_ROOT = $scratch
$script:case = 0
function Check([bool]$Cond, [string]$What) { if (-not $Cond) { throw "case $($script:case): $What" } }
function Case([string]$Name) { $script:case++; Write-Host "Case $($script:case): $Name..." -NoNewline }

try {
    Case 'the Google provider names four records in order, and its aliases resolve'
    $google = Resolve-PqProvider 'gemini'
    Check ($null -ne $google) 'gemini does not resolve'
    $names = (Get-PqProviderAgents $google) -join ','
    Check ($names -ceq 'gemini,gemini-argon,gemini-neon,gemini-claude') "expected gemini,gemini-argon,gemini-neon,gemini-claude, got '$names'"
    foreach ($alias in 'google', 'antigravity', 'agy', 'Antigravity') {
        $r = Resolve-PqProvider $alias
        Check ($null -ne $r -and $r.id -ceq 'gemini') "alias '$alias' does not resolve to the gemini provider"
    }
    Write-Host ' PASS' -ForegroundColor Green

    Case 'each record carries its own model over the same agy arguments'
    $built = @{}
    foreach ($agent in '', 'gemini-argon', 'gemini-neon', 'gemini-claude') {
        $b = New-PqProviderRecord 'gemini' $agent
        Check $b.ok "no record for '$agent': $($b.why)"
        $built[[string]$b.record.name] = $b.record
    }
    Check ((@($built.Keys | Sort-Object) -join ',') -ceq 'gemini,gemini-argon,gemini-claude,gemini-neon') "record names: $(@($built.Keys) -join ',')"
    Check ($built['gemini'].model -ceq 'gemini-4-hydrogen-high') "gemini model is '$($built['gemini'].model)'"
    Check ($built['gemini-argon'].model -ceq 'gemini-4-argon-high') "gemini-argon model is '$($built['gemini-argon'].model)'"
    Check ($built['gemini-neon'].model -ceq 'gemini-4-neon-high') "gemini-neon model is '$($built['gemini-neon'].model)'"
    Check ($built['gemini-claude'].model -ceq 'claude-sonnet-5-5-high') "gemini-claude model is '$($built['gemini-claude'].model)'"
    $shape = (@($built['gemini'].argsTemplate) -join ' ')
    Check ($shape -ceq '--model {model} --dangerously-skip-permissions --print {prompt}') "argsTemplate is '$shape'"
    foreach ($n in $built.Keys) {
        Check ((@($built[$n].argsTemplate) -join ' ') -ceq $shape) "$n runs another argument shape"
        Check ($built[$n].command -ceq 'agy-stub.exe') "$n runs '$($built[$n].command)'"
        Check ($built[$n].limitDetector.pattern -ceq $built['gemini'].limitDetector.pattern) "$n has its own limit pattern"
        Check ($built[$n].limitDetector.status -ceq 'unproven') "$n detector is not unproven"
        Check ($built[$n].maxParallel -eq 2) "$n maxParallel is $($built[$n].maxParallel)"
        Check ($null -eq $built[$n].PSObject.Properties['routes']) "$n ships a grade route"
    }
    Write-Host ' PASS' -ForegroundColor Green

    Case 'applying the order adds only the missing records and touches nothing else'
    $regPath = Join-Path $scratch 'repos.json'
    $routes = @([pscustomobject]@{ max = 6 })
    $hydrogen = $built['gemini'] | Select-Object *; $hydrogen | Add-Member -NotePropertyName routes -NotePropertyValue $routes
    $argon = $built['gemini-argon'] | Select-Object *
    $claude = (New-PqProviderRecord 'anthropic').record
    $doc = [ordered]@{ schemaVersion = '1.0'; repos = @(); agents = @($claude, $hydrogen, $argon); agentOrder = @('claude', 'gemini', 'gemini-argon') }
    [IO.File]::WriteAllText($regPath, ($doc | ConvertTo-Json -Depth 20))
    $res = Set-PqAgentOrder -Names @('anthropic', 'gemini') -RegistryPath $regPath
    Check $res.ok "Set-PqAgentOrder failed: $($res.error) $($res.message)"
    Check $res.changed 'the order was reported unchanged though a record was added'
    $after = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($regPath))
    Check ((@($after.agentOrder) -join ',') -ceq 'claude,gemini,gemini-argon,gemini-neon,gemini-claude') "agentOrder is '$(@($after.agentOrder) -join ',')'"
    Check ((@($after.agents | ForEach-Object { $_.name }) -join ',') -ceq 'claude,gemini,gemini-argon,gemini-neon,gemini-claude') "records are '$(@($after.agents | ForEach-Object { $_.name }) -join ',')'"
    $kept = @($after.agents | Where-Object { $_.name -ceq 'gemini' })[0]
    Check ($kept.model -ceq 'gemini-4-hydrogen-high' -and @($kept.routes).Count -eq 1 -and $kept.routes[0].max -eq 6) 'the existing gemini record was rewritten (its route is gone)'
    $added = @($after.agents | Where-Object { $_.name -ceq 'gemini-claude' })[0]
    Check ($added.model -ceq 'claude-sonnet-5-5-high') "the added record runs '$($added.model)'"
    Check ($null -eq $added.PSObject.Properties['routes']) 'the added record carries a grade route'
    $neon = @($after.agents | Where-Object { $_.name -ceq 'gemini-neon' })[0]
    Check ($neon.model -ceq 'gemini-4-neon-high') "the added Neon record runs '$($neon.model)'"
    Check ($null -eq $neon.PSObject.Properties['routes']) 'the added Neon record carries a grade route'
    $second = Set-PqAgentOrder -Names @('anthropic', 'gemini') -RegistryPath $regPath
    Check ($second.ok -and -not $second.changed) 'a second apply changed the registry again'
    Write-Host ' PASS' -ForegroundColor Green

    Case 'a registry without the later records validates and reads as the two it has'
    $old = [ordered]@{ schemaVersion = '1.0'; repos = @(); agents = @($claude, $hydrogen, $argon); agentOrder = @('claude', 'gemini', 'gemini-argon') }
    $oldObj = ConvertFrom-Json -InputObject ($old | ConvertTo-Json -Depth 20)
    $check = Test-PqRegistry -Registry $oldObj
    Check $check.ok "the old registry no longer validates: $(@($check.errors | ForEach-Object { $_.message }) -join '; ')"
    $row = @(Get-PqProviderStatus -Registry $oldObj | Where-Object { $_.id -ceq 'gemini' })[0]
    Check ($row.position -eq 2 -and $row.record -and -not $row.held) "the status row is position=$($row.position) record=$($row.record) held=$($row.held)"
    Write-Host ' PASS' -ForegroundColor Green

    Write-Host ''
    Write-Host "All $($script:case) test cases passed successfully." -ForegroundColor Green
}
finally {
    $env:SZA_PORTFOLIO_ROOT = $origEnv
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
