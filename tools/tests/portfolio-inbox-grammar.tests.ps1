#requires -Version 7.0
# Focused S0051 regression: real profiles, ledgers and specs, without starting a pq process.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\harness\portfolio\lib\inbox.ps1')
. (Join-Path $PSScriptRoot '..\harness\portfolio\lib\xrepo.ps1')

$scratch = Join-Path (Join-Path $PSScriptRoot '..\..\temp\S0051_bugfix-inbox-blocker-token-prose') ([guid]::NewGuid().ToString('N'))
$count = 0
function Assert-Equal($Actual, $Expected, [string]$Case) {
    $script:count++
    if ($Actual -cne $Expected) { throw "$Case - expected '$Expected', got '$Actual'" }
    Write-Host "PASS $Case"
}
function New-TestRepo([string]$Key, [string]$Profile, [string]$Id, [string]$BlockerId) {
    $root = Join-Path $scratch $Key
    $plan = Join-Path $root 'PLAN'
    $null = New-Item -ItemType Directory -Path $plan -Force
    [IO.File]::WriteAllText((Join-Path $root '.sza-profile.json'), $Profile)
    $rows = @(
        @{ id = $Id; status = 'BlockByOtherTask'; file = "PLAN/${Id}_x.md" }
        @{ id = $BlockerId; status = 'In Progress'; file = "PLAN/${BlockerId}_x.md" }
        @{ id = 'S0099'; status = 'Archived'; file = 'PLAN/S0099_x.md' }
    ) | ForEach-Object { ConvertTo-Json -InputObject $_ -Compress }
    [IO.File]::WriteAllText((Join-Path $plan 'spec-catalog.jsonl'), ($rows -join "`n"))
    return @{ key = $Key; path = $root }
}
function Set-Spec($Repo, [string]$Id, [string]$Text) {
    [IO.File]::WriteAllText((Join-Path $Repo.path "PLAN/${Id}_x.md"), $Text)
}
try {
    $a = New-TestRepo 'default' '{}' 'S0001' 'S0002'
    $b = New-TestRepo 'custom' '{"grammar":{"ticketIdPattern":"^SP-\\d{4}$"}}' 'SP-0001' 'SP-0002'
    $byKey = @{ default = $a; custom = $b }
    $registry = @{ repos = @($a, $b) }

    Set-Spec $a 'S0001' "Blocker: FastMediaSorter`nBlocker: S0002"
    Assert-Equal (Get-PqInboxLocalHold $byKey @{} 'default' 'S0001') 'default:S0002' 'prose is skipped before a valid blocker'
    Set-Spec $a 'S0001' 'Blocker: FastMediaSorter'
    Assert-Equal (Get-PqInboxLocalHold $byKey @{} 'default' 'S0001') $null 'prose alone does not hold'
    Assert-Equal (Get-PqInboxChainRoot $registry $byKey @{} 'default' 'S0001').pair 'default:S0001' 'prose does not create a chain root'
    Set-Spec $a 'S0001' 'Blocker: S0002suffix'
    Assert-Equal (Get-PqInboxLocalHold $byKey @{} 'default' 'S0001') $null 'partial id does not match'
    Set-Spec $a 'S0001' 'Blocker: S0003'
    Assert-Equal (Get-PqInboxLocalHold $byKey @{} 'default' 'S0001') 'default:S0003' 'missing but valid id still holds'
    Set-Spec $a 'S0001' 'Blocker: S0099'
    Assert-Equal (Get-PqInboxLocalHold $byKey @{} 'default' 'S0001') $null 'released local blocker does not hold'
    Set-Spec $a 'S0001' 'Blocker: custom:SP-0002'
    Assert-Equal (Get-PqInboxLocalHold $byKey @{} 'default' 'S0001') $null 'qualified blocker remains with cross-repo walk'
    Assert-Equal (Get-PqInboxChainRoot $registry $byKey @{} 'default' 'S0001').pair 'custom:SP-0002' 'qualified blocker still forms a chain'
    Set-Spec $b 'SP-0001' "Blocker: S0002`nBlocker: SP-0002"
    Assert-Equal (Get-PqInboxLocalHold $byKey @{} 'custom' 'SP-0001') 'custom:SP-0002' 'custom grammar overrides default'
    Set-Spec $b 'SP-0001' 'Blocker: S0002'
    Assert-Equal (Get-PqInboxLocalHold $byKey @{} 'custom' 'SP-0001') $null 'default id is prose in custom project'
    Set-Spec $a 'S0001' 'Blocker: SP-0002'
    Assert-Equal (Get-PqInboxLocalHold $byKey @{} 'default' 'S0001') $null 'custom id is prose in default project'
    Set-Spec $b 'SP-0001' 'Блокер: **SP-0002**'
    Assert-Equal (Get-PqInboxLocalHold $byKey @{} 'custom' 'SP-0001') 'custom:SP-0002' 'localized and formatted blocker'
    Write-Host "portfolio-inbox-grammar: $count passed"
}
finally {
    # ReadLines enumerators from the production reader may still await finalization after an early return.
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
