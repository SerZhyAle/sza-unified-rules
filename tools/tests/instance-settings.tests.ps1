#requires -Version 7.0
<#
.SYNOPSIS
    Fast targeted tests for HARNESS-PROFILE section 3 rule 9 (S0078): a runner instance may carry its own
    `promptTemplate` and `complexityModels`, falling back to `runner.promptTemplate` and
    `runner.complexityModels` by the chain of rule 8.

      1. The chain (batch/_instance-settings.ps1): the agent record, then the instance, then the shared
         `runner.<field>`, then the shipped default - for both fields, on throwaway profiles.
      2. An instance that carries neither field, an instance absent from the map and a profile with no
         `instances` all read the shared values; a profile with no `runner` at all reads the shipped default,
         which declares both paths (rule 4: reading them cannot throw).
      3. An instance map owns the whole map: a level it omits answers '' (no declaration), it is not looked
         up in the shared map - the fallback is by field, as for effortByModel.
      4. The runner itself obeys the chain: a dry run for instance `b` prints that instance's prompt and
         routes a `hard` ticket to that instance's model, and `-PromptTemplate` still outranks the profile.

    Cases 1-3 call the changed functions directly; case 4 runs run-spec-queue.ps1 -DryRun once per
    assertion against a throwaway project with a hand-written ledger row. Nothing launches a child and
    nothing touches a real project. The suite is designed to stay under the 5 s line; it takes -KeepScratch
    to leave the throwaway folders for inspection.
#>
[CmdletBinding()]
param([switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
$SourceRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
$harness = Join-Path $SourceRoot 'tools/harness'
$runner = Join-Path $harness 'batch/run-spec-queue.ps1'

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool]$Condition, [string]$Reason) { if (-not $Condition) { throw $Reason } }
function Test-Case([string]$Name, [scriptblock]$Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try {
        & $Body
        $script:passed++
        Write-Host 'PASS' -ForegroundColor Green
    } catch {
        $script:failed++
        Write-Host 'FAIL' -ForegroundColor Red
        Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('s0078-rule9-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null
$savedRoot = $env:SZA_PROJECT_ROOT
$savedProfile = $env:SZA_PROFILE_PATH
$env:SZA_PROFILE_PATH = $null

# The functions under test, loaded into this scope; the profile cache is reset between throwaway profiles.
. (Join-Path $harness 'batch/_instance-settings.ps1')

$script:projects = 0
function Use-Profile($Profile) {
    $script:projects++
    $root = Join-Path $scratch ("p{0}" -f $script:projects)
    New-Item -ItemType Directory -Path $root | Out-Null
    if ($null -ne $Profile) { $Profile | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $root '.sza-profile.json') -Encoding utf8 }
    $env:SZA_PROJECT_ROOT = $root
    $Script:SzaProfileCache = $null
    $Script:SzaProjectRootCache = $null
    return $root
}

$sharedModels = @{ light = 'shared-light'; medium = 'shared-medium'; hard = 'shared-hard' }
$twoInstances = @{
    command          = 'pwsh'
    promptTemplate   = 'shared-prompt {Id}'
    complexityModels = $sharedModels
    instances        = @{
        b     = @{ promptTemplate = 'instance-b-prompt {Id}'; complexityModels = @{ hard = 'b-hard' } }
        plain = @{ headlessMatch = '\s-p\s' }
    }
}

try {
    Test-Case 'an instance reads its own promptTemplate and complexityModels, another instance and none read the shared ones' {
        [void](Use-Profile @{ version = '1'; runner = $twoInstances })
        Assert-That ((Get-SzaInstanceSetting -Field 'promptTemplate' -Instance 'b') -ceq 'instance-b-prompt {Id}') "instance b read '$(Get-SzaInstanceSetting -Field 'promptTemplate' -Instance 'b')'"
        Assert-That ((Get-SzaComplexityModel -Level 'hard' -Instance 'b') -ceq 'b-hard') "instance b hard -> '$(Get-SzaComplexityModel -Level 'hard' -Instance 'b')'"
        Assert-That ((Get-SzaInstanceSetting -Field 'promptTemplate' -Instance 'a') -ceq 'shared-prompt {Id}') 'an instance absent from the map did not read the shared promptTemplate'
        Assert-That ((Get-SzaComplexityModel -Level 'hard' -Instance 'a') -ceq 'shared-hard') 'an instance absent from the map did not read the shared complexityModels'
        Assert-That ((Get-SzaInstanceSetting -Field 'promptTemplate') -ceq 'shared-prompt {Id}') 'no instance name did not read the shared promptTemplate'
        Assert-That ((Get-SzaComplexityModel -Level 'light') -ceq 'shared-light') 'no instance name did not read the shared complexityModels'
    }

    Test-Case 'an instance that carries neither field falls back to the shared values' {
        [void](Use-Profile @{ version = '1'; runner = $twoInstances })
        Assert-That ((Get-SzaInstanceSetting -Field 'promptTemplate' -Instance 'plain') -ceq 'shared-prompt {Id}') 'instance plain did not fall back for promptTemplate'
        Assert-That ((Get-SzaComplexityModel -Level 'medium' -Instance 'plain') -ceq 'shared-medium') 'instance plain did not fall back for complexityModels'
        # The fields rule 8 already resolved still resolve beside the new two.
        Assert-That ((Get-SzaInstanceSetting -Field 'headlessMatch' -Instance 'plain') -ceq '\s-p\s') 'rule 8 headlessMatch of the same instance regressed'
        Assert-That ((Get-SzaInstanceSetting -Field 'command' -Instance 'b') -ceq 'pwsh') 'rule 8 command fell back wrongly'
    }

    Test-Case 'the agent record outranks the instance, and carries only the fields it names' {
        [void](Use-Profile @{ version = '1'; runner = $twoInstances })
        $record = [pscustomobject]@{ name = 'claude'; promptTemplate = 'record-prompt {Id}' }
        Assert-That ((Get-SzaInstanceSetting -Field 'promptTemplate' -Instance 'b' -Record $record) -ceq 'record-prompt {Id}') 'the record did not outrank the instance promptTemplate'
        # The record names no complexityModels, so the instance's map still answers.
        Assert-That ((Get-SzaComplexityModel -Level 'hard' -Instance 'b' -Record $record) -ceq 'b-hard') 'a record without complexityModels hid the instance map'
    }

    Test-Case 'an instance map owns the whole map: an omitted level is no declaration, not the shared answer' {
        [void](Use-Profile @{ version = '1'; runner = $twoInstances })
        Assert-That ((Get-SzaComplexityModel -Level 'medium' -Instance 'b') -ceq '') "instance b medium answered '$(Get-SzaComplexityModel -Level 'medium' -Instance 'b')', not ''"
        Assert-That ((Get-SzaComplexityModel -Level 'nonsense' -Instance 'a') -ceq '') 'an unknown level answered a model'
    }

    Test-Case 'a profile with no runner reads the shipped defaults, which declare both paths (rule 4)' {
        [void](Use-Profile @{ version = '1' })
        $p = Get-SzaInstanceSetting -Field 'promptTemplate' -Instance 'b'
        Assert-That ($p -ceq [string]$Script:SzaProfileDefaults.runner.promptTemplate) 'the shipped promptTemplate was not the fallback'
        Assert-That ((Get-SzaComplexityModel -Level 'light' -Instance 'b') -ceq 'haiku') 'the shipped complexityModels did not answer light -> haiku'
        Assert-That ((Get-SzaComplexityModel -Level 'hard') -ceq 'opus') 'the shipped complexityModels did not answer hard -> opus'
        $threw = $false
        try { [void](Get-SzaProfileValue 'runner.promptTemplate'); [void](Get-SzaProfileValue 'runner.complexityModels') } catch { $threw = $true }
        Assert-That (-not $threw) 'reading a declared runner path threw'
        $undeclared = $false
        try { [void](Get-SzaInstanceSetting -Field 'noSuchField' -Instance 'b') } catch { $undeclared = $true }
        Assert-That $undeclared 'a field nothing declares did not throw (rule 4)'
    }

    Test-Case 'run-spec-queue -DryRun for instance b prints its prompt and routes by its map; -PromptTemplate outranks it' {
        $root = Use-Profile @{ version = '1'; projectName = 'fixture'; probes = @{ enabled = $false }; locks = @{ agentProcessNames = @('pwsh.exe', 'pwsh') }; runner = $twoInstances }
        New-Item -ItemType Directory (Join-Path $root 'PLAN') | Out-Null
        $spec = "# S0001_task-hard`n`n**Status:** Draft`n**Created:** 2026-11-15`n**Complexity:** hard - fixture`n`n## 0. Owner request (verbatim)`n`nfixture`n"
        [IO.File]::WriteAllText((Join-Path $root 'PLAN/S0001_task-hard.md'), $spec, [Text.UTF8Encoding]::new($false))
        $row = '{"id":"S0001","name":"task-hard","status":"Draft","priority":50,"file":"PLAN/S0001_task-hard.md","created":"2026-11-15","updated":"2026-11-15 00:00"}'
        [IO.File]::WriteAllText((Join-Path $root 'PLAN/spec-catalog.jsonl'), $row + "`n", [Text.UTF8Encoding]::new($false))

        $out = & pwsh -NoProfile -File $runner -RepoRoot $root -Ids 'S0001' -DryRun -ModelPolicy shape -Instance b 2>&1 | Out-String
        Assert-That ($LASTEXITCODE -eq 0) "the dry run exited $($LASTEXITCODE): $out"
        Assert-That ($out -match '(?m)^\s*prompt\s*:\s*instance-b-prompt \{id\}\s*$') "instance b's promptTemplate did not reach the runner: $out"
        Assert-That ($out -match 'S0001.*complexity hard\) -> model b-hard') "instance b's complexityModels did not route the hard ticket: $out"

        $out = & pwsh -NoProfile -File $runner -RepoRoot $root -Ids 'S0001' -DryRun -ModelPolicy shape -Instance b -PromptTemplate 'explicit-prompt {id}' 2>&1 | Out-String
        Assert-That ($LASTEXITCODE -eq 0) "the explicit-prompt dry run exited $($LASTEXITCODE): $out"
        Assert-That ($out -match '(?m)^\s*prompt\s*:\s*explicit-prompt \{id\}\s*$') "-PromptTemplate did not outrank the profile: $out"
    }
} finally {
    $env:SZA_PROJECT_ROOT = $savedRoot
    $env:SZA_PROFILE_PATH = $savedProfile
    if (-not $KeepScratch -and (Test-Path $scratch)) {
        Remove-Item -Path $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host "Cases: $run | Passed: $passed | Failed: $failed"
if ($failed -gt 0) { exit 1 } else { exit 0 }
