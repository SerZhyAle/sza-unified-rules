#requires -Version 7.0
param([string]$ChildRoot = '', [int]$ChildSlot = 0, [string]$Ticket = '', [int]$Cap = 1, [int]$AgentMax = 2)

$ErrorActionPreference = 'Stop'
$lib = Join-Path (Split-Path $PSScriptRoot -Parent) 'harness/portfolio/lib'
. (Join-Path $lib 'paths.ps1')
. (Join-Path $lib 'registry.ps1')
. (Join-Path $lib 'loop.ps1')
. (Join-Path $lib 'resources.ps1')

if ($ChildRoot) {
    $env:SZA_PORTFOLIO_ROOT = $ChildRoot
    Set-PqWorkerState -Slot $ChildSlot
    [IO.File]::WriteAllText((Join-Path $ChildRoot "ready-$ChildSlot"), '')
    while (-not [IO.File]::Exists((Join-Path $ChildRoot 'go'))) { Start-Sleep -Milliseconds 10 }
    $ok = Request-PqWorkerAssignment -Slot $ChildSlot -Repo @{ key = 'demo'; concurrent = $true; maxWorkers = $Cap } -Ticket $Ticket -Title '' -Agent 'test' -AgentMax $AgentMax
    [IO.File]::WriteAllText((Join-Path $ChildRoot "result-$ChildSlot"), [string]$ok)
    while (-not [IO.File]::Exists((Join-Path $ChildRoot 'finish'))) { Start-Sleep -Milliseconds 10 }
    Remove-PqWorkerState -Slot $ChildSlot
    exit 0
}

$originalRoot = $env:SZA_PORTFOLIO_ROOT
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('pq-assignment-' + [guid]::NewGuid().ToString('N'))
$processes = @()
try {
    foreach ($case in @(
        @{ name = 'repository cap'; cap = 1; agentMax = 2; tickets = @('S0001', 'S0002'); expected = 1 },
        @{ name = 'duplicate ticket'; cap = 2; agentMax = 2; tickets = @('S0001', 'S0001'); expected = 1 },
        @{ name = 'provider cap'; cap = 2; agentMax = 1; tickets = @('S0001', 'S0002'); expected = 1 },
        @{ name = 'independent tickets'; cap = 2; agentMax = 2; tickets = @('S0001', 'S0002'); expected = 2 }
    )) {
        $root = Join-Path $scratch $case.name
        $null = [IO.Directory]::CreateDirectory($root)
        $processes = @(1..2 | ForEach-Object {
            $info = [Diagnostics.ProcessStartInfo]::new('pwsh')
            $info.UseShellExecute = $false
            $info.CreateNoWindow = $true
            foreach ($arg in @('-NoProfile', '-File', $PSCommandPath, '-ChildRoot', $root, '-ChildSlot', "$_", '-Ticket', $case.tickets[$_ - 1], '-Cap', "$($case.cap)", '-AgentMax', "$($case.agentMax)")) { $info.ArgumentList.Add($arg) }
            [Diagnostics.Process]::Start($info)
        })
        $deadline = [DateTime]::UtcNow.AddSeconds(4)
        while (-not ([IO.File]::Exists((Join-Path $root 'ready-1')) -and [IO.File]::Exists((Join-Path $root 'ready-2')))) {
            if ([DateTime]::UtcNow -gt $deadline -or @($processes | Where-Object HasExited).Count) { throw "$($case.name): children did not start" }
            Start-Sleep -Milliseconds 10
        }
        [IO.File]::WriteAllText((Join-Path $root 'go'), '')
        while (-not ([IO.File]::Exists((Join-Path $root 'result-1')) -and [IO.File]::Exists((Join-Path $root 'result-2')))) {
            if ([DateTime]::UtcNow -gt $deadline -or @($processes | Where-Object HasExited).Count) { throw "$($case.name): children did not finish assignment" }
            Start-Sleep -Milliseconds 10
        }
        $wins = @(1..2 | Where-Object { [IO.File]::ReadAllText((Join-Path $root "result-$_")) -ceq 'True' }).Count
        if ($wins -ne $case.expected) { throw "$($case.name): expected $($case.expected) assignments, got $wins" }
        if ($case.name -ceq 'repository cap') {
            $env:SZA_PORTFOLIO_ROOT = $root
            $token = Get-PqPath -Kind resourceToken -Token 'build' -Repo 'demo' -Id 'S0001'
            $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $token))
            $foreign = @{ repo = 'demo'; id = 'S0001'; pid = $processes[0].Id; procStart = $processes[0].StartTime.ToUniversalTime().ToString('o'); pass = 'foreign' }
            [IO.File]::WriteAllText($token, ($foreign | ConvertTo-Json -Compress))
            $req = Request-PqResources -Registry @{ resources = @{ build = 3 } } -RepoKey 'demo' -TicketId 'S0001' -Verify 'build' -PassId 'ours'
            $null = Remove-PqResources -RepoKey 'demo' -TicketId 'S0001'
            if ($req.ok -or -not [IO.File]::Exists($token)) { throw 'another process resource was overwritten or removed' }
            Write-Host 'OK foreign resource preserved'
        }
        [IO.File]::WriteAllText((Join-Path $root 'finish'), '')
        foreach ($p in $processes) { $p.WaitForExit(); if ($p.ExitCode -ne 0) { throw 'child failed' } }
        $processes = @()
        Write-Host "OK $($case.name)"
    }
    $env:SZA_PORTFOLIO_ROOT = Join-Path $scratch 'resources'
    $registry = @{ resources = @{ build = 3; emulator = 1 } }
    $first = Request-PqResources -Registry $registry -RepoKey 'demo' -TicketId 'S0001' -Verify 'build' -PassId 'first'
    $repeat = Request-PqResources -Registry $registry -RepoKey 'demo' -TicketId 'S0001' -Verify 'build' -PassId 'first'
    $other = Request-PqResources -Registry $registry -RepoKey 'demo' -TicketId 'S0001' -Verify 'build' -PassId 'other'
    if (-not $first.ok -or -not $repeat.ok -or $repeat.heldCount -ne 1 -or $other.ok) { throw 'resource ownership failed' }
    $null = Remove-PqResources -RepoKey 'demo' -TicketId 'S0001'
    if (@((Get-PqResourceHeld -Token 'build').live).Count -ne 0) { throw 'resource release failed' }
    Write-Host 'OK resource ownership'
}
finally {
    foreach ($p in $processes) { if (-not $p.HasExited) { $p.Kill(); $p.WaitForExit() } }
    $env:SZA_PORTFOLIO_ROOT = $originalRoot
    if ([IO.Directory]::Exists($scratch)) { [IO.Directory]::Delete($scratch, $true) }
}
