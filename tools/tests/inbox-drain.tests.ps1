#requires -Version 7.0
# End-to-end drain tests with isolated portfolio, ingest and dispatcher fixtures.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$drain = Join-Path $PSScriptRoot '..\harness\portfolio\drain-inbox.ps1'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('sza-inbox-drain-' + [guid]::NewGuid().ToString('N'))
$oldRoot = $env:SZA_PORTFOLIO_ROOT
$oldCalls = $env:SZA_TEST_DRAIN_CALLS
$oldInbox = $env:SZA_INBOX_ROOT
function Assert-Drain($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
try {
    $portfolio = Join-Path $scratch 'portfolio'
    $inbox = Join-Path $scratch 'inbox'
    $repo = Join-Path $scratch 'repo'
    foreach ($p in @($portfolio, $inbox, $repo)) { $null = [IO.Directory]::CreateDirectory($p) }
    $env:SZA_PORTFOLIO_ROOT = $portfolio
    $env:SZA_TEST_DRAIN_CALLS = Join-Path $scratch 'calls.txt'
    $registry = @{ schemaVersion = '1.0'; repos = @(@{ key = 'alpha'; path = $repo; enabled = $true; maxWorkers = 1; concurrent = $false; role = 'product'; permissionMode = 'bypassPermissions'; rank = 10 }) }
    [IO.File]::WriteAllText((Join-Path $portfolio 'repos.json'), (ConvertTo-Json $registry -Depth 8))
    $ingest = Join-Path $scratch 'ingest.ps1'
    $pq = Join-Path $scratch 'pq.ps1'
    @'
param([switch]$All, [string]$InboxRoot)
foreach ($dir in [IO.Directory]::GetDirectories((Join-Path $InboxRoot 'new'))) {
    [IO.Directory]::Move($dir, (Join-Path (Join-Path $InboxRoot 'done') (Split-Path $dir -Leaf)))
}
exit 0
'@ | Set-Content -LiteralPath $ingest -Encoding utf8
    @'
param([string]$Verb, [string]$Ticket)
[IO.File]::AppendAllText($env:SZA_TEST_DRAIN_CALLS, "$Verb -Ticket $Ticket`n")
switch -Wildcard ($Ticket) {
    '*:LEASE' { Write-Output "pq: ticket $Ticket not run - ticket lease is held"; exit 3 }
    '*:UNKNOWN' { Write-Output "pq: ticket $Ticket not run - offers no such ticket"; exit 3 }
    '*:HOLD' { Write-Output "pq: ticket $Ticket not run - on hold in the registry"; exit 3 }
    '*:BAD' { [Console]::Error.WriteLine('pq: ArgumentInvalid - bad target'); exit 2 }
    default { exit 0 }
}
'@ | Set-Content -LiteralPath $pq -Encoding utf8
    function Invoke-TestDrain([string[]]$Extra = @()) {
        $output = & (Get-Process -Id $PID).Path -NoProfile -File $drain -InboxRoot $inbox -IngestScript $ingest -PqScript $pq @Extra 2>&1
        if ($LASTEXITCODE -ne 0) { throw "drain exited $LASTEXITCODE`: $($output -join ' | ')" }
    }
    function Add-TestPacket([string]$Id, [string]$Ticket, [string]$Project = 'alpha', [string]$Stage = 'new') {
        $path = Join-Path (Join-Path $inbox $Stage) $Id
        $null = [IO.Directory]::CreateDirectory($path)
        [IO.File]::WriteAllText((Join-Path $path 'manifest.json'), (ConvertTo-Json @{ project = $Project }))
        [IO.File]::WriteAllText((Join-Path $path 'result.json'), (ConvertTo-Json @{ packetId = $Id; tickets = @($Ticket); at = '2026-01-01T00:00:00Z' }))
    }
    function Read-Result([string]$Id) { return Get-Content (Join-Path $inbox "done\$Id\result.json") -Raw | ConvertFrom-Json -AsHashtable }
    Invoke-TestDrain
    Assert-Drain (-not (Test-Path $env:SZA_TEST_DRAIN_CALLS)) 'empty spool invoked pq'
    Add-TestPacket 'a' 'alpha:OK' 'alpha' 'done'
    Add-TestPacket 'b' 'alpha:LEASE'
    Add-TestPacket 'c' 'alpha:UNKNOWN'
    Add-TestPacket 'd' 'alpha:HOLD'
    Add-TestPacket 'e' 'alpha:BAD'
    Add-TestPacket 'f' 'canon:S1' ''
    Invoke-TestDrain
    Assert-Drain ((Read-Result 'a').execution -ceq 'ran') 'already filed packet did not run'
    Assert-Drain ((Read-Result 'b').execution -ceq 'skipped') 'lease was not skipped'
    Assert-Drain ((Read-Result 'c').execution -match 'no such ticket') 'unknown ticket reason missing'
    $calls = @(Get-Content $env:SZA_TEST_DRAIN_CALLS)
    Assert-Drain ($calls.Count -eq 3 -and $calls[0] -ceq 'start -Ticket alpha:OK') 'wrong named starts or cap'
    Invoke-TestDrain
    Assert-Drain ((Read-Result 'd').execution -match 'hold') 'hold reason missing'
    Assert-Drain ((Read-Result 'e').execution -match 'exit 2') 'exit 2 reason missing'
    Assert-Drain ((Read-Result 'f').execution -match 'project-less') 'project-less packet ran'
    $cursor = Join-Path $inbox 'inbox-state.json'
    $before = [IO.File]::ReadAllText($cursor)
    $count = @(Get-Content $env:SZA_TEST_DRAIN_CALLS).Count
    Invoke-TestDrain
    Assert-Drain ([IO.File]::ReadAllText($cursor) -ceq $before) 'empty repeat changed cursor'
    Assert-Drain (@(Get-Content $env:SZA_TEST_DRAIN_CALLS).Count -eq $count) 'repeat invoked pq'
    Add-TestPacket 'g' 'alpha:INTERRUPTED' 'alpha' 'done'
    $state = Get-Content $cursor -Raw | ConvertFrom-Json -AsHashtable
    $state.packets['g'] = @{ tickets = @('alpha:INTERRUPTED'); filedAt = '2026-01-01T00:00:00Z'; executions = @{ 'alpha:INTERRUPTED' = @{ execution = 'launching'; reason = $null; at = '2026-01-01T00:00:00Z' } } }
    [IO.File]::WriteAllText($cursor, (ConvertTo-Json $state -Depth 10))
    Invoke-TestDrain
    Assert-Drain ((Read-Result 'g').execution -match 'interrupted') 'interrupted launch was not recorded'
    Assert-Drain (@(Get-Content $env:SZA_TEST_DRAIN_CALLS).Count -eq $count) 'interrupted launch repeated'
    Add-TestPacket 'h' 'alpha:FILEONLY'
    Invoke-TestDrain @('-FileOnly')
    Assert-Drain ((Read-Result 'h').execution -match 'file-only') 'file-only decision missing'
    Add-TestPacket 'i' 'alpha:REPAIRED' 'alpha' 'done'
    $state = Get-Content $cursor -Raw | ConvertFrom-Json -AsHashtable
    $state.packets['i'] = @{ tickets = @('alpha:REPAIRED'); filedAt = '2026-01-01T00:00:00Z'; executions = @{ 'alpha:REPAIRED' = @{ execution = 'ran'; reason = $null; at = '2026-01-01T00:00:00Z' } } }
    [IO.File]::WriteAllText($cursor, (ConvertTo-Json $state -Depth 10))
    Invoke-TestDrain
    Assert-Drain ((Read-Result 'i').execution -ceq 'ran') 'cursor decision was not repaired into result'
    Assert-Drain (@(Get-Content $env:SZA_TEST_DRAIN_CALLS).Count -eq $count) 'result repair invoked pq'
    Add-TestPacket 'j' 'canon:S2' 'missing'
    Invoke-TestDrain
    Assert-Drain ((Read-Result 'j').execution -match 'unknown') 'unknown project was not left for triage'
    $env:SZA_INBOX_ROOT = $inbox
    $status = & (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $PSScriptRoot '..\harness\portfolio\pq.ps1') status 2>&1
    Assert-Drain ($LASTEXITCODE -eq 0 -and ($status -join "`n") -match 'inbox: 0 new, 0 filed waiting, oldest none') 'pq status inbox summary missing'
    $events = @(Get-ChildItem $portfolio -Recurse -Filter '*.jsonl' | ForEach-Object { Get-Content $_.FullName } | Where-Object { $_ -match 'ingest\.drain' })
    Assert-Drain ($events.Count -gt 0 -and ($events -join "`n") -match 'alpha:LEASE') 'drain event missing'
    [IO.File]::WriteAllText($cursor, '{"schemaVersion":1,"packets":null}')
    $failure = & (Get-Process -Id $PID).Path -NoProfile -File $drain -InboxRoot $inbox -IngestScript $ingest -PqScript $pq 2>&1
    Assert-Drain ($LASTEXITCODE -eq 2 -and ($failure -join ' ') -match 'InboxDrainStateUnreadable') 'invalid cursor did not fail closed'
    $failure = & (Get-Process -Id $PID).Path -NoProfile -File $drain -MaxTickets invalid 2>&1
    Assert-Drain ($LASTEXITCODE -eq 2 -and ($failure -join ' ') -match 'MaxTickets') 'invalid cap did not exit 2'
    Write-Host 'PASS: empty, ingest, exact target, cap, refusals, triage, resume, repair, status, events and file-only'
}
finally {
    $env:SZA_PORTFOLIO_ROOT = $oldRoot
    $env:SZA_TEST_DRAIN_CALLS = $oldCalls
    $env:SZA_INBOX_ROOT = $oldInbox
    if ([IO.Directory]::Exists($scratch)) { [IO.Directory]::Delete($scratch, $true) }
}
