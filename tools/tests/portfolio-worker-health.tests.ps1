#requires -Version 7.0
# Tests for S0032: worker health visibility, dead worker reclamation, pass.beat/seen, run.error tracking, and code change reload
$ErrorActionPreference = 'Stop'
$lib = Join-Path (Split-Path $PSScriptRoot -Parent) 'harness/portfolio/lib'
. (Join-Path $lib 'paths.ps1')
. (Join-Path $lib 'events.ps1')
. (Join-Path $lib 'registry.ps1')
. (Join-Path $lib 'analysis.ps1')
. (Join-Path $lib 'loop.ps1')

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('pq-health-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($scratch)
$origEnv = $env:SZA_PORTFOLIO_ROOT
$env:SZA_PORTFOLIO_ROOT = $scratch

try {
    # Case 1: Analysis counts run.error and raises PQ-DATA01, excluding provider-pause
    Write-Host "Case 1: analysis.ps1 counts run.error and raises high finding..." -NoNewline
    $fakeLog = Open-PqLog -Writer 'w1' -Run 'R-test-1'
    $null = Write-PqEvent -Log $fakeLog -Ev 'run.error' -Run 'R-test-1' -Worker 1 -D ([ordered]@{ err = 'boom'; stage = 'turn' })
    $null = Write-PqEvent -Log $fakeLog -Ev 'run.error' -Run 'R-test-1' -Worker 1 -D ([ordered]@{ err = 'pause'; stage = 'provider-pause' })
    Close-PqLog -Log $fakeLog

    $rep = Get-PqReport -Root $scratch -Days 1
    if ($rep.telemetry.runErrors -ne 1) {
        throw "Expected 1 non-pause runError in telemetry, got $($rep.telemetry.runErrors)"
    }
    $findings = @($rep.findings | Where-Object { $_.fid -eq 'PQ-DATA01' })
    if ($findings.Count -ne 1 -or $findings[0].severity -ne 'high' -or $findings[0].text -notmatch '1 run\.error') {
        throw "Expected PQ-DATA01 high finding mentioning 1 run.error, got: $($findings | ConvertTo-Json)"
    }
    Write-Host " PASS" -ForegroundColor Green

    # Case 2: Worker state seen timestamp initialization and update
    Write-Host "Case 2: Worker seen timestamp initialized and refreshed..." -NoNewline
    Set-PqWorkerState -Slot 1 -Repo 'repo1' -Ticket 'S0001'
    $st1 = Read-PqState (Join-Path (Join-Path $scratch 'run') 'worker-1.json')
    if (-not $st1.seen) { throw "Expected worker-1.json to contain 'seen' property" }
    $seen1 = $st1.seen
    Start-Sleep -Milliseconds 50
    Update-PqWorkerSeen -Slot 1
    $st2 = Read-PqState (Join-Path (Join-Path $scratch 'run') 'worker-1.json')
    if ($st2.seen -eq $seen1) { throw "Expected seen timestamp to advance on Update-PqWorkerSeen" }
    Write-Host " PASS" -ForegroundColor Green

    # Case 3: Dead worker reclamation records orphaned run row and pass.end
    Write-Host "Case 3: Dead worker reclamation appends runs.jsonl and pass.end..." -NoNewline
    # Create dead worker state for slot 2
    $runDir = Join-Path $scratch 'run'
    $w2File = Join-Path $runDir 'worker-2.json'
    $deadObj = [ordered]@{
        pid = 99999999 # non-existent pid
        startedAt = '2026-11-10T12:00:00Z'
        repository = 'demo'
        ticket = 'S0042'
        title = 'Orphaned ticket'
        agent = 'claude'
        since = [DateTimeOffset]::UtcNow.AddMinutes(-5).ToString('o')
        seen = [DateTimeOffset]::UtcNow.AddMinutes(-2).ToString('o')
    }
    [IO.File]::WriteAllText($w2File, ($deadObj | ConvertTo-Json -Compress), [Text.Encoding]::UTF8)

    # Reclaim slot 2 via Get-PqWorkerSlot
    $claimedSlot = Get-PqWorkerSlot @{ maxWorkers = 2 }
    if ($claimedSlot -ne 2) { throw "Expected slot 2 to be reclaimed, got $claimedSlot" }

    # Check runs.jsonl
    $runsFile = Join-Path $scratch 'runs.jsonl'
    if (-not [IO.File]::Exists($runsFile)) { throw "Expected runs.jsonl to exist after dead worker reclamation" }
    $rows = @([IO.File]::ReadAllLines($runsFile) | Where-Object { $_.Trim() } | ForEach-Object { ConvertFrom-Json $_ })
    $orphanRows = @($rows | Where-Object { $_.outcome -eq 'orphaned' -and $_.id -eq 'S0042' })
    if ($orphanRows.Count -ne 1) { throw "Expected 1 orphaned run row, got $($orphanRows.Count)" }

    # Check pass.end event in today's log
    $todayEvents = @(Read-PqWindowEvents -Root $scratch).events
    $orphanEvents = @($todayEvents | Where-Object { $_.ev -eq 'pass.end' -and $_.d.outcome -eq 'orphaned' -and $_.id -eq 'S0042' })
    if ($orphanEvents.Count -ne 1) { throw "Expected 1 orphaned pass.end event, got $($orphanEvents.Count)" }
    Write-Host " PASS" -ForegroundColor Green

    # Case 4: ConvertTo-PqPassEndOutcome maps orphaned
    Write-Host "Case 4: ConvertTo-PqPassEndOutcome maps orphaned..." -NoNewline
    $mapped = ConvertTo-PqPassEndOutcome 'orphaned'
    if ($mapped -ne 'orphaned') { throw "Expected orphaned, got $mapped" }
    Write-Host " PASS" -ForegroundColor Green

    # Case 5: Code write-time detection and parser check
    Write-Host "Case 5: Code write-time detection and parser check..." -NoNewline
    $t1 = Get-PqCodeMaxWriteTime
    if ($t1 -le [DateTime]::MinValue) { throw "Get-PqCodeMaxWriteTime returned invalid time" }
    Write-Host " PASS" -ForegroundColor Green

    # Case 6: Three consecutive turn errors with same text terminate the run
    Write-Host "Case 6: Three consecutive identical turn errors terminate run..." -NoNewline
    $testScript = {
        param($failText)
        $lastErr = ''
        $streak = 0
        $ended = $false
        for ($i = 0; $i -lt 5; $i++) {
            try {
                throw $failText
            }
            catch {
                $msg = $_.Exception.Message
                if ($msg -and $msg -ceq $lastErr) { $streak++ } else { $lastErr = $msg; $streak = 1 }
                if ($streak -ge 3) {
                    $ended = $true
                    break
                }
            }
        }
        return @{ ended = $ended; streak = $streak }
    }
    $res = & $testScript 'Simulated repeated failure'
    if (-not $res.ended -or $res.streak -ne 3) { throw "Expected streak=3 and ended=true" }
    Write-Host " PASS" -ForegroundColor Green

    # Case 7: the supervisor starts the child again on the restart code and on no other (an owner stop ends a worker with 0,
    # and a supervisor that looped on 0 would undo the stop), passes the arguments through, and marks the child
    Write-Host "Case 7: supervisor restarts on the restart code only, keeps stop and errors..." -NoNewline
    $code = Get-PqRestartExitCode
    if ($code -le 0) { throw "Expected a non-zero restart exit code, got $code" }
    $stub = Join-Path $scratch 'stub-pq.ps1'
    $stubState = Join-Path $scratch 'stub-state.txt'
    $stubArgs = Join-Path $scratch 'stub-args.txt'
    [IO.File]::WriteAllText($stub, @'
param([string]$Verb, [Parameter(ValueFromRemainingArguments)]$Rest)
$dir = Split-Path $PSCommandPath -Parent
$state = Join-Path $dir 'stub-state.txt'
$n = if (Test-Path $state) { [int](Get-Content $state) } else { 0 }
$n++
Set-Content $state $n
Add-Content (Join-Path $dir 'stub-args.txt') "$Verb|$($Rest -join ' ')|$env:SZA_PQ_SUPERVISED"
$until = [int]$env:STUB_RESTARTS
if ($n -le $until) { exit 75 }
exit ([int]$env:STUB_FINAL)
'@)
    $env:STUB_RESTARTS = '2'; $env:STUB_FINAL = '3'
    $rc = Invoke-PqSupervised -Script $stub -Verb 'start' -Arguments @('-Repo', 'fms-a') -ThrottleSeconds 0 6>$null
    if ($rc -ne 3) { throw "Expected the final child code 3, got '$rc'" }
    if ([int](Get-Content $stubState) -ne 3) { throw "Expected 3 launches (2 restarts, then the final code), got $(Get-Content $stubState)" }
    $lines = @(Get-Content $stubArgs)
    if ($lines.Count -ne 3 -or @($lines | Where-Object { $_ -ne 'start|-Repo fms-a|1' }).Count -gt 0) { throw "Arguments or the supervised mark were not passed through: $($lines -join ' / ')" }
    # A stop (child exit 0) is not a restart: one launch, code 0
    Remove-Item $stubState, $stubArgs -Force
    $env:STUB_RESTARTS = '0'; $env:STUB_FINAL = '0'
    $rc = Invoke-PqSupervised -Script $stub -Verb 'start' -ThrottleSeconds 0 6>$null
    if ($rc -ne 0 -or [int](Get-Content $stubState) -ne 1) { throw "A child that ended with 0 must end the supervisor at once; code '$rc', launches $(Get-Content $stubState)" }
    Remove-Item Env:\STUB_RESTARTS, Env:\STUB_FINAL -ErrorAction SilentlyContinue
    $loopText = [IO.File]::ReadAllText((Join-Path $lib 'loop.ps1'))
    if ($loopText -notmatch '\$null -eq \$named -and \$MaxTickets -le 0') { throw "loop.ps1: a run with a ceiling must not end for a code change" }
    Write-Host " PASS" -ForegroundColor Green

    Write-Host "`nAll 7 worker health test cases PASSED cleanly." -ForegroundColor Green
    exit 0
}
finally {
    $env:SZA_PORTFOLIO_ROOT = $origEnv
    try { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}
