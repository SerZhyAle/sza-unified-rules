#requires -Version 7.0
<#
.SYNOPSIS
    Smoke test for the portfolio queue runner (S0015 Phase 04 & Phase 05).

.DESCRIPTION
    Verifies:
      1. Phase 04: pq start -Drain over a throwaway portfolio with a fake runner works two tickets
         in order, logs them to runs.jsonl and events log, and exits 0.
      2. A second run with no candidates exits 3.
      3. Phase 05: pq status reports workers, passes today, STOP presence, and next candidate.
      4. pq log filters by -Ev, -Repo, -Last, and outputs -Json.
      5. pq stop writes <root>\STOP, which is reported by status and cleared by the next start.
      6. V3/V4: Repo lock exclusion and worker slot assignment.
      7. V5: Unmoved ticket exclusion.
      8. The shortcuts: install-shortcuts writes the PQ set (one `PQ Tickets <key>` per registered repository)
         into a scratch Desktop and a scratch root, repeats as a no-op, drops its own stale files, removes only
         its own files and leaves a foreign shortcut of the same name alone. `pq tickets` lists and opens each
         repository's own ticket queue file and follows the profile's paths.releaseQueue.
      10. V7: a pass the dispatcher kills releases the lease its runner made (reason run-spec-queue <instance>)
         and no other, so the rank does not skip the stopped ticket for the 45-minute liveness window.
      9. V14: a pass child does not inherit the starting agent's session variables (CLAUDECODE, the
         CLAUDE_CODE session and messaging family, *_AGENT_ID) but keeps credentials and settings; nor does any
         read-only repository child (picker, ticket record, lease release), whose picker would otherwise keep the
         starting agent's own leases in the ranking.
      11. V7: stop -Kill kills the pass tree and leaves a headless agent of another repository alive.
      12. Rule 26: a repository whose shared queue stop file exists is skipped as stopped, and the file stays.
      13. Rule 46: a runner that lost the claim before launch (exit 3) is recorded claim-lost, not child-failed.
#>
[CmdletBinding()]
param(
    [switch]$KeepScratch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$harness = Join-Path $SourceRoot 'tools\harness'
$pqScript = Join-Path $harness 'portfolio\pq.ps1'

$run = 0
$passed = 0
$failed = 0

function Assert-That([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Run-SmokeCase([string]$Name, [scriptblock]$Body) {
    $script:run++
    Write-Host -NoNewline "SMOKE  $Name ... "
    try {
        & $Body
        $script:passed++
        Write-Host "PASS" -ForegroundColor Green
    }
    catch {
        $script:failed++
        Write-Host "FAIL" -ForegroundColor Red
        Write-Host "       $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ("pq-smoke-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null

$savedPortfolioRoot = $env:SZA_PORTFOLIO_ROOT
$savedUserProfile = $env:USERPROFILE
$savedProjectRoot = $env:SZA_PROJECT_ROOT
$savedProfilePath = $env:SZA_PROFILE_PATH

try {
    $portfolioRoot = Join-Path $scratch 'portfolio'
    $env:SZA_PORTFOLIO_ROOT = $portfolioRoot
    $env:USERPROFILE = $scratch
    $env:SZA_PROJECT_ROOT = $null
    $env:SZA_PROFILE_PATH = $null

    # Helper to invoke pq.ps1
    function Start-SmokePq([string[]]$Arguments, [hashtable]$Env = @{}) {
        $pwsh = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
        $psi = [Diagnostics.ProcessStartInfo]::new($pwsh)
        $psi.ArgumentList.Add('-NoProfile')
        $psi.ArgumentList.Add('-File')
        $psi.ArgumentList.Add($pqScript)
        foreach ($a in $Arguments) { $psi.ArgumentList.Add([string]$a) }
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.WorkingDirectory = $scratch
        $psi.Environment['SZA_PORTFOLIO_ROOT'] = $portfolioRoot
        $psi.Environment['USERPROFILE'] = $scratch
        foreach ($k in $Env.Keys) { $psi.Environment[$k] = [string]$Env[$k] }
        $proc = [Diagnostics.Process]::Start($psi)
        $out = $proc.StandardOutput.ReadToEndAsync()
        $err = $proc.StandardError.ReadToEndAsync()
        return @{ process = $proc; stdout = $out; stderr = $err }
    }

    function Complete-SmokePq($Child, [int]$TimeoutSeconds = 90) {
        $proc = $Child.process
        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            $proc.Kill($true)
            $null = $proc.WaitForExit(10000)
            throw "pq timed out after $TimeoutSeconds seconds"
        }
        return [pscustomobject]@{
            code = $proc.ExitCode
            stdout = $Child.stdout.Result
            stderr = $Child.stderr.Result
            output = ($Child.stdout.Result + $Child.stderr.Result)
        }
    }

    function Invoke-SmokePq([string[]]$Arguments, [hashtable]$Env = @{}) {
        Complete-SmokePq (Start-SmokePq $Arguments $Env)
    }

    function Wait-SmokeCondition([scriptblock]$Condition, [string]$Message, [int]$Seconds = 45) {
        $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
        while ([DateTime]::UtcNow -lt $deadline) {
            if (& $Condition) { return }
            Start-Sleep -Milliseconds 100
        }
        throw $Message
    }

    # Setup fake repositories
    $repoADir = Join-Path $scratch 'repo-a'
    $repoBDir = Join-Path $scratch 'repo-b'
    foreach ($dir in $repoADir, $repoBDir) {
        New-Item -ItemType Directory -Path $dir | Out-Null
        $null = & pwsh -NoProfile -File (Join-Path $harness 'scaffold\init-task-flow.ps1') -Root $dir -NoLaunchers
        $stamp = [ordered]@{
            schemaVersion = '1.0'
            canon = @{ version = '2026.1'; coreDigest = '0' * 64; model = 'reference' }
            overlay = 'powershell-tooling'
            ledgerShape = 'spec-catalog'
        }
        [IO.File]::WriteAllText((Join-Path $dir '.sza-canon.json'), (($stamp | ConvertTo-Json -Depth 5)), [Text.Encoding]::UTF8)
    }

    # Seed 1 ticket in repo-a and 1 ticket in repo-b
    Push-Location $repoADir
    try { $null = & pwsh -NoProfile -File (Join-Path $harness 'spec_catalog\capture-draft.ps1') -Slug 'task-one' -Text 'Owner text for ticket 1' -Priority 80 } finally { Pop-Location }
    Push-Location $repoBDir
    try { $null = & pwsh -NoProfile -File (Join-Path $harness 'spec_catalog\capture-draft.ps1') -Slug 'task-two' -Text 'Owner text for ticket 2' -Priority 70 } finally { Pop-Location }

    # Register both repositories
    $regA = Invoke-SmokePq @('register', '-Path', $repoADir, '-Key', 'repo-a', '-Enable')
    Assert-That ($regA.code -eq 0) "register repo-a failed: $($regA.output)"
    $regB = Invoke-SmokePq @('register', '-Path', $repoBDir, '-Key', 'repo-b', '-Enable')
    Assert-That ($regB.code -eq 0) "register repo-b failed: $($regB.output)"

    Run-SmokeCase 'V14: missing permissionMode refuses unattended work' {
        $res = Invoke-SmokePq @('start', '-Drain', '-RunnerScript', (Join-Path $scratch 'must-not-launch.ps1'))
        Assert-That ($res.code -eq 2 -and $res.stderr -match 'PermissionModeMissing') "missing permission was not refused: $($res.output)"
        Assert-That (-not (Test-Path (Join-Path $portfolioRoot 'runs.jsonl'))) 'an unconfigured pass was recorded'
        Assert-That (@(Get-ChildItem (Join-Path $portfolioRoot 'run') -File).Count -eq 0) 'failed start leaked its slot or repo lock'
    }
    $registryFile = Join-Path $portfolioRoot 'repos.json'
    $registry = Get-Content -Raw $registryFile | ConvertFrom-Json
    $registry | Add-Member -NotePropertyName permissionMode -NotePropertyValue acceptEdits
    $registry | Add-Member -NotePropertyName pollSeconds -NotePropertyValue 1 -Force
    $registry | ConvertTo-Json -Depth 32 | Set-Content $registryFile
    # The owner's queue puts the lower-priority repository first.
    "# 1`nrepo-b`nrepo-a`n" | Set-Content (Join-Path $portfolioRoot 'PORTFOLIO_QUEUE.md')

    # Fake runner script
    $fakeRunner = Join-Path $scratch 'fake-runner.ps1'
    $runnerCode = @'
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$Ids,
    [int]$MaxTickets = 1,
    [string]$ModelPolicy = 'shape',
    [string]$Instance = 'pq1',
    [string]$PermissionMode = 'bypassPermissions',
    [switch]$Stop,
    [switch]$Kill
)
if ($Stop) { exit 0 }
if (-not $Ids) { exit 3 }
if ($env:SZA_PROJECT_ROOT -cne $RepoRoot -or $ModelPolicy -cne 'shape' -or $MaxTickets -ne 1 -or $PermissionMode -cne 'acceptEdits') { exit 9 }

# Update ticket status in ledger to Verified
$catalog = Join-Path $RepoRoot 'PLAN\spec-catalog.jsonl'
if (Test-Path $catalog) {
    $lines = Get-Content $catalog | ForEach-Object {
        $row = ConvertFrom-Json $_
        if ($row.id -eq $Ids) {
            $row.status = 'Verified'
        }
        $row | ConvertTo-Json -Compress
    }
    Set-Content $catalog -Value $lines -Encoding UTF8
}

# Write journal row
$runsDir = Join-Path $RepoRoot 'temp\spec-queue'
if (-not (Test-Path $runsDir)) { New-Item -ItemType Directory -Path $runsDir | Out-Null }
$journalFile = Join-Path $runsDir "runs-$Instance.jsonl"
$record = [ordered]@{
    id = $Ids
    model = 'sonnet'
    policy = $ModelPolicy
    complexity = 'medium'
    statusBefore = 'Draft'
    statusAfter = 'Verified'
    moved = $true
    outcome = 'ok'
    exitCode = 0
    minutes = 1
    finishedAt = (Get-Date).ToString('s')
}
Add-Content -Path $journalFile -Value (($record | ConvertTo-Json -Compress)) -Encoding UTF8
exit 0
'@
    [IO.File]::WriteAllText($fakeRunner, $runnerCode, [Text.Encoding]::UTF8)

    # ---------------------------------------------------------------- Phase 04 Proof
    Run-SmokeCase 'Phase 04: pq start -Drain works two tickets in order and exits 0' {
        $res = Invoke-SmokePq @('start', '-Drain', '-RunnerScript', $fakeRunner)
        Assert-That ($res.code -eq 0) "start -Drain exited $($res.code): $($res.output)"

        # Check runs.jsonl
        $runsFile = Join-Path $portfolioRoot 'runs.jsonl'
        Assert-That ([IO.File]::Exists($runsFile)) "runs.jsonl does not exist"
        $rows = @([IO.File]::ReadAllLines($runsFile, [Text.Encoding]::UTF8) | Where-Object { $_.Trim() })
        Assert-That ($rows.Count -eq 2) "expected 2 rows in runs.jsonl, got $($rows.Count)"
        $row1 = ConvertFrom-Json -InputObject $rows[0]
        $row2 = ConvertFrom-Json -InputObject $rows[1]
        Assert-That ($row1.repo -ceq 'repo-b' -and $row1.id -ceq 'S0001' -and $row1.outcome -ceq 'ok' -and $row1.moved -eq $true) "row1 mismatch: $($rows[0])"
        Assert-That ($row2.repo -ceq 'repo-a' -and $row2.id -ceq 'S0001' -and $row2.outcome -ceq 'ok' -and $row2.moved -eq $true) "row2 mismatch: $($rows[1])"
        foreach ($row in $row1, $row2) {
            Assert-That ($row.registryHash -match '^[0-9a-f]{64}$' -and $row.canon -and $row.plugin -and $row.seconds -ge 0) 'run row lacks version/hash/duration fields'
        }

        # Check events log
        $logDir = Join-Path $portfolioRoot 'log'
        $eventFiles = [IO.Directory]::GetFiles($logDir, 'events-*.w1.jsonl')
        Assert-That ($eventFiles.Count -ge 1) "no events-*.w1.jsonl file created"
        $events = [IO.File]::ReadAllLines($eventFiles[0], [Text.Encoding]::UTF8)
        $names = @($events | ForEach-Object { (ConvertFrom-Json $_).ev })
        Assert-That ($names -contains 'run.start') "events missing run.start"
        Assert-That ($names -contains 'pass.launch') "events missing pass.launch"
        Assert-That ($names -contains 'pass.end') "events missing pass.end"
        Assert-That ($names -contains 'run.end') "events missing run.end"
        $parsedEvents = @($events | ForEach-Object { ConvertFrom-Json $_ })
        foreach ($launch in @($parsedEvents | Where-Object ev -eq 'pass.launch')) {
            $runStart = $parsedEvents | Where-Object { $_.ev -ceq 'run.start' -and $_.run -ceq $launch.run } | Select-Object -First 1
            Assert-That ($launch.d.pid -gt 0 -and $launch.d.pid -ne $runStart.d.pid) 'pass.launch must name the runner child PID'
        }
    }

    Run-SmokeCase 'Phase 04: a second run with nothing left exits 3' {
        $res = Invoke-SmokePq @('start', '-Drain', '-RunnerScript', $fakeRunner)
        Assert-That ($res.code -eq 3) "second start -Drain expected exit 3, got $($res.code): $($res.output)"
    }

    # ---------------------------------------------------------------- Phase 05 Proof
    Run-SmokeCase 'Phase 05: pq status reports workers, passes today, and next candidate' {
        $st = Invoke-SmokePq @('status')
        Assert-That ($st.code -eq 0) "status exited $($st.code): $($st.output)"
        Assert-That ($st.stdout -match 'STOP: none') "status missing STOP: none in $($st.stdout)"
        Assert-That ($st.stdout -match 'Passes today: ok: 2') "status missing Passes today in $($st.stdout)"
        Assert-That ($st.stdout -match 'Next: none') "status missing Next: none in $($st.stdout)"

        $stJson = Invoke-SmokePq @('status', '-Json')
        Assert-That ($stJson.code -eq 0) "status -Json exited $($stJson.code)"
        $obj = ConvertFrom-Json -InputObject $stJson.stdout
        Assert-That ($obj.stop.present -eq $false) "json stop present is not false"
        Assert-That ($obj.passesToday.ok -eq 2) "json passesToday.ok is not 2"
    }

    Run-SmokeCase 'Phase 05: pq log filters by -Last, -Ev, -Repo, -Json' {
        $all = Invoke-SmokePq @('log', '-Ev', 'pass.launch', '-Last', '10')
        Assert-That ($all.code -eq 0) "log exited $($all.code): $($all.output)"
        Assert-That ($all.stdout -match 'pass\.launch') "log output does not contain pass.launch"

        $passEnd = Invoke-SmokePq @('log', '-Ev', 'pass.end')
        Assert-That ($passEnd.code -eq 0) "log -Ev pass.end exited $($passEnd.code)"
        $lines = @($passEnd.stdout -split '\r?\n' | Where-Object { $_.Trim() })
        Assert-That ($lines.Count -ge 2) "expected at least 2 pass.end events, got $($lines.Count)"
        foreach ($l in $lines) { Assert-That ($l -match 'pass\.end') "line did not match pass.end: $l" }

        $repoALog = Invoke-SmokePq @('log', '-Repo', 'repo-a')
        Assert-That ($repoALog.code -eq 0) "log -Repo repo-a exited $($repoALog.code)"
        $aLines = @($repoALog.stdout -split '\r?\n' | Where-Object { $_.Trim() })
        foreach ($l in $aLines) { Assert-That ($l -match 'repo-a:S0001') "line did not match repo-a: $l" }

        $jsonLog = Invoke-SmokePq @('log', '-Last', '5', '-Json')
        Assert-That ($jsonLog.code -eq 0) "log -Json exited $($jsonLog.code)"
        $parsed = ConvertFrom-Json -InputObject $jsonLog.stdout
        Assert-That ($parsed.Count -le 5 -and $parsed.Count -ge 1) "json log unexpected count: $($parsed.Count)"
    }

    Run-SmokeCase 'Phase 05: pq stop writes STOP, and pq start clears it' {
        $stopRes = Invoke-SmokePq @('stop')
        Assert-That ($stopRes.code -eq 0) "stop exited $($stopRes.code): $($stopRes.output)"
        Assert-That ($stopRes.stdout -match 'stop requested \(pass\)') "unexpected stop output: $($stopRes.stdout)"

        $stopFile = Join-Path $portfolioRoot 'STOP'
        Assert-That ([IO.File]::Exists($stopFile)) "STOP file was not created"

        $st = Invoke-SmokePq @('status')
        Assert-That ($st.stdout -match 'STOP: present \(level=pass\)') "status did not report STOP present: $($st.stdout)"

        # Start with STOP present clears it and announces so
        $startClear = Invoke-SmokePq @('start', '-Drain', '-RunnerScript', $fakeRunner)
        Assert-That ($startClear.stdout -match 'cleared STOP file') "start did not announce clearing STOP file: $($startClear.stdout)"
        Assert-That (-not [IO.File]::Exists($stopFile)) "STOP file was not cleared"
    }

    # ---------------------------------------------------------------- V3 & V4: Lock and Slot checks
    Run-SmokeCase 'V3: Live repo lock causes rank to mark repository occupied and skip it' {
        # Add a new ticket to repo-a
        Push-Location $repoADir
        try { $null = & pwsh -NoProfile -File (Join-Path $harness 'spec_catalog\capture-draft.ps1') -Slug 'task-three' -Text 'Ticket 3 in repo-a' -Priority 90 } finally { Pop-Location }

        # Create a repo lock with our current process ID (alive!)
        $runDir = Join-Path $portfolioRoot 'run'
        if (-not (Test-Path $runDir)) { New-Item -ItemType Directory -Path $runDir | Out-Null }
        $lockA = Join-Path $runDir 'repo-repo-a.lock'
        $lockObj = @{ pid = $PID; since = [DateTimeOffset]::UtcNow.ToString('o') }
        [IO.File]::WriteAllText($lockA, (($lockObj | ConvertTo-Json -Compress)), [Text.Encoding]::UTF8)

        # dry-run should show repo-a as occupied
        $dr = Invoke-SmokePq @('dry-run')
        Assert-That ($dr.stdout -match 'skip repo-a - occupied') "repo-a was not skipped as occupied in: $($dr.stdout)"

        # Remove lock
        Remove-Item -LiteralPath $lockA -Force
    }

    # ---------------------------------------------------------------- V5: Unmoved ticket exclusion
    Run-SmokeCase 'V5: A ticket that did not move is excluded from subsequent rank within the run' {
        # Create a fake runner that moves nothing
        $script:idleRunner = Join-Path $scratch 'idle-runner.ps1'
        $idleCode = @'
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$Ids,
    [int]$MaxTickets = 1,
    [string]$ModelPolicy = 'shape',
    [string]$Instance = 'pq1',
    [string]$PermissionMode = 'bypassPermissions'
)
# Do not update ticket status - leave as Draft
exit 0
'@
        [IO.File]::WriteAllText($idleRunner, $idleCode, [Text.Encoding]::UTF8)

        # Run with MaxTickets 1 to execute 1 pass on the unmoved ticket
        $beforeRows = @(Get-Content (Join-Path $portfolioRoot 'runs.jsonl')).Count
        $res = Invoke-SmokePq @('start', '-Drain', '-RunnerScript', $idleRunner)
        # S0002 was not moved, so it was excluded from rank and then drain exited 0 after 1 pass
        Assert-That ($res.code -eq 0) "start with idle ticket failed: $($res.output)"
        $lastRow = (Get-Content (Join-Path $portfolioRoot 'runs.jsonl') -Tail 1 | ConvertFrom-Json)
        Assert-That ($lastRow.moved -eq $false -and $lastRow.outcome -ceq 'no-progress') "expected unmoved no-progress, got: $($lastRow | ConvertTo-Json -Compress)"
        Assert-That (@(Get-Content (Join-Path $portfolioRoot 'runs.jsonl')).Count -eq $beforeRows + 1) 'unmoved ticket ran more than once'
    }

    Run-SmokeCase 'V5/V6: failed passes are excluded and MaxTickets ends without Drain' {
        $failedRunner = Join-Path $scratch 'failed-runner.ps1'
        ([IO.File]::ReadAllText($idleRunner) -replace 'exit 0', 'exit 7') | Set-Content $failedRunner
        $beforeRows = @(Get-Content (Join-Path $portfolioRoot 'runs.jsonl')).Count
        $res = Invoke-SmokePq @('start', '-Drain', '-RunnerScript', $failedRunner)
        $rows = @(Get-Content (Join-Path $portfolioRoot 'runs.jsonl'))
        $lastRow = $rows[-1] | ConvertFrom-Json
        Assert-That ($res.code -eq 0 -and $rows.Count -eq $beforeRows + 1 -and $lastRow.outcome -ceq 'child-failed' -and $lastRow.exitCode -eq 7) "failure was not journalled/excluded: $($res.output)"
        $res = Invoke-SmokePq @('start', '-MaxTickets', '1', '-RunnerScript', $idleRunner)
        Assert-That ($res.code -eq 0 -and @(Get-Content (Join-Path $portfolioRoot 'runs.jsonl')).Count -eq $beforeRows + 2) "MaxTickets did not stop after one pass: $($res.output)"
    }

    Run-SmokeCase 'V6/V7: waiting worker reloads registry, stops promptly and preserves an active STOP' {
        $registry = Get-Content -Raw $registryFile | ConvertFrom-Json
        $registry.repos[0] | Add-Member -NotePropertyName hold -NotePropertyValue $true -Force
        $registry | ConvertTo-Json -Depth 32 | Set-Content $registryFile
        $worker = Start-SmokePq @('start', '-RunnerScript', $idleRunner)
        try {
            $workerFile = Join-Path $portfolioRoot 'run/worker-1.json'
            Wait-SmokeCondition { Test-Path $workerFile } 'worker did not reserve its slot'
            Wait-SmokeCondition {
                $events = Get-Content (Join-Path $portfolioRoot 'log/events-*.w1.jsonl') | ForEach-Object { ConvertFrom-Json $_ }
                @($events | Where-Object { $_.ev -ceq 'wait.enter' -and $_.run -eq ($events | Where-Object ev -eq 'run.start' | Select-Object -Last 1).run }).Count -gt 0
            } 'empty queue never entered wait'
            $activeStatus = Invoke-SmokePq @('status', '-Json')
            $active = ConvertFrom-Json $activeStatus.stdout
            Assert-That ($active.workers.Count -eq 1 -and $active.workers[0].alive) 'status cannot read a live worker/event writer'

            $beforeRows = @(Get-Content (Join-Path $portfolioRoot 'runs.jsonl')).Count
            $registry.repos[0].hold = $false
            $registry | ConvertTo-Json -Depth 32 | Set-Content $registryFile
            Wait-SmokeCondition { @(Get-Content (Join-Path $portfolioRoot 'runs.jsonl')).Count -gt $beforeRows } 'registry release was never picked up'
            $stop = Invoke-SmokePq @('stop')
            Assert-That ($stop.code -eq 0) "stop failed: $($stop.output)"
            $ended = Complete-SmokePq $worker 10
            Assert-That ($ended.code -eq 0) "waiting worker failed: $($ended.output)"
            Assert-That (-not (Test-Path $workerFile)) 'worker slot remained after stop'

            # A start must not erase a stop while another worker is draining.
            @{ pid = $PID; repository = $null; ticket = $null; since = 'fixture' } | ConvertTo-Json | Set-Content $workerFile
            $blocked = Invoke-SmokePq @('start', '-Drain', '-RunnerScript', $idleRunner)
            Assert-That ($blocked.code -eq 3 -and (Test-Path (Join-Path $portfolioRoot 'STOP'))) 'start erased an active STOP'
            Remove-Item -LiteralPath $workerFile
        }
        finally {
            if (-not $worker.process.HasExited) { $worker.process.Kill($true); $null = $worker.process.WaitForExit(10000) }
        }
    }

    Run-SmokeCase 'V7: stop -Kill terminates the pass process tree and no other agent on the machine' {
        $sleepRunner = Join-Path $scratch 'sleep-runner.ps1'
        @'
param($RepoRoot, $Ids, $MaxTickets, $ModelPolicy, $Instance, $PermissionMode)
$psi = [Diagnostics.ProcessStartInfo]::new((Get-Command pwsh).Source)
foreach ($a in @('-NoProfile', '-Command', 'Start-Sleep -Seconds 90')) { $psi.ArgumentList.Add($a) }
$psi.UseShellExecute = $false
$child = [Diagnostics.Process]::Start($psi)
@{ runner = $PID; child = $child.Id } | ConvertTo-Json | Set-Content (Join-Path $RepoRoot 'temp/sleep-pids.json')
# The claim the real runner makes for its child, in the shape ticket-lease.ps1 writes.
$leases = Join-Path $RepoRoot 'temp/SPEC-TICKET.LEASES'
New-Item -ItemType Directory -Path $leases -Force | Out-Null
$now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
[ordered]@{ schema = 1; id = $Ids; sessionId = [guid]::NewGuid().ToString(); host = $env:COMPUTERNAME; pid = $PID; reason = "run-spec-queue $Instance"
    claimedAt = $now; lastSeenAt = $now; transcriptPath = $null } | ConvertTo-Json -Compress | Set-Content (Join-Path $leases "$Ids.json")
$child.WaitForExit()
'@ | Set-Content $sleepRunner
        # The real runner's own -Stop -Kill terminates every process named in locks.agentProcessNames whose command line
        # matches the headless flag, on the whole machine. Here that name is a harmless copy of Windows PowerShell, and a
        # process of that name runs as a local runner's child in ANOTHER repository: a portfolio kill must not reach it.
        $profilePath = Join-Path $repoADir '.sza-profile.json'
        $profile = Get-Content -Raw $profilePath | ConvertFrom-Json
        $profile.runner | Add-Member -NotePropertyName command -NotePropertyValue pwsh -Force
        $profile | Add-Member -NotePropertyName locks -NotePropertyValue ([pscustomobject]@{ agentProcessNames = @('pqsmoke-agent.exe') }) -Force
        $profile | ConvertTo-Json -Depth 32 | Set-Content $profilePath
        $fakeAgent = Join-Path $scratch 'bin\pqsmoke-agent.exe'
        New-Item -ItemType Directory -Path (Split-Path $fakeAgent) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -Destination $fakeAgent
        $foreign = Start-Process -FilePath $fakeAgent -ArgumentList '-NoProfile', '-Command', '"Start-Sleep 120 # -p S0009 local r1 child"' -WorkingDirectory $repoBDir -WindowStyle Hidden -PassThru
        $pidMarker = Join-Path $repoADir 'temp/sleep-pids.json'
        $worker = Start-SmokePq @('start', '-MaxTickets', '1', '-RunnerScript', $sleepRunner)
        $pids = $null
        try {
            Wait-SmokeCondition { Test-Path $pidMarker } 'sleeping pass did not start'
            $pids = Get-Content -Raw $pidMarker | ConvertFrom-Json
            $res = Invoke-SmokePq @('stop', '-Kill')
            Assert-That ($res.code -eq 0 -and $res.stdout -match 'stop requested \(kill\)') "stop -Kill failed: $($res.output)"
            $ended = Complete-SmokePq $worker 15
            Assert-That ($ended.code -eq 0) "killed worker failed: $($ended.output)"
            Assert-That (-not (Get-Process -Id $pids.runner, $pids.child -ErrorAction SilentlyContinue)) 'pass or descendant survived kill'
            $foreign.Refresh()
            Assert-That (-not $foreign.HasExited) 'pq stop -Kill killed a headless agent that is not a portfolio pass (another repository''s runner child)'
            $lastRow = Get-Content (Join-Path $portfolioRoot 'runs.jsonl') -Tail 1 | ConvertFrom-Json
            Assert-That ($lastRow.outcome -ceq 'killed') 'killed pass was not journalled as killed'
            Assert-That (-not (Test-Path (Join-Path $repoADir 'temp/SPEC-TICKET.LEASES/S0001.json'))) 'the killed pass left its own lease behind, so the rank would skip the ticket for 45 minutes'
        }
        finally {
            if (-not $worker.process.HasExited) { $worker.process.Kill($true); $null = $worker.process.WaitForExit(10000) }
            if ($pids) { Stop-Process -Id $pids.runner, $pids.child -Force -ErrorAction SilentlyContinue }
            if (-not $foreign.HasExited) { Stop-Process -Id $foreign.Id -Force -ErrorAction SilentlyContinue }
            $null = $foreign.WaitForExit(5000)
        }
    }

    Run-SmokeCase 'Rule 26: a repository whose shared queue stop file exists is not offered (owner rs, release freeze)' {
        $repoStop = Join-Path $repoBDir 'temp/STOP-SPEC-QUEUE'
        Set-Content -LiteralPath $repoStop -Value 'stop requested by the owner'
        try {
            $dr = Invoke-SmokePq @('dry-run')
            Assert-That ($dr.code -eq 0 -and $dr.stdout -match 'skip repo-b - stopped') "a stopped repository was ranked: $($dr.stdout)"
            Assert-That ($dr.stdout -notmatch 'slot \d+: repo-b:') "a stopped repository got a slot: $($dr.stdout)"
            Assert-That (Test-Path -LiteralPath $repoStop) 'the rank removed the owner''s stop file'
        }
        finally { Remove-Item -LiteralPath $repoStop -Force -ErrorAction SilentlyContinue }
    }

    # Exercise the shared mechanisms directly without starting an agent or modifying real repositories.
    . (Join-Path $harness 'portfolio/lib/registry.ps1')
    . (Join-Path $harness 'portfolio/lib/ledger-watch.ps1')
    . (Join-Path $harness 'portfolio/lib/picker.ps1')
    . (Join-Path $harness 'portfolio/lib/loop.ps1')

    Run-SmokeCase 'V9/V11: active event writers are readable and Last merges writers by timestamp' {
        $older = Open-PqLog -Writer w3
        $null = Write-PqEvent -Log $older -Ev owner.action -D @{ verb = 'start'; args = @() }
        Start-Sleep -Milliseconds 20
        $newer = Open-PqLog -Writer w2
        $null = Write-PqEvent -Log $newer -Ev owner.action -D @{ verb = 'stop'; args = @() }
        try {
            $res = Invoke-SmokePq @('log', '-Last', '1', '-Json')
            Assert-That ($res.code -eq 0) "live log read failed: $($res.output)"
            $last = @(ConvertFrom-Json $res.stdout)
            Assert-That ($last.Count -eq 1 -and $last[0].wr -ceq 'w2') 'Last returned file order instead of timestamp order'
        }
        finally { $null = Close-PqLog $older; $null = Close-PqLog $newer }
    }

    Run-SmokeCase 'V5/V8: outcomes ignore old journal rows and retain limits inside a successful pass' {
        $journal = Join-Path $repoADir 'temp/spec-queue/runs-pq1.jsonl'
        $offset = [IO.FileInfo]::new($journal).Length
        $unchanged = Read-PqPassOutcome -RepoPath $repoADir -Instance pq1 -TicketId S0001 -StatusBefore Verified -ChildExitCode 0 -HarnessRoot $harness -JournalOffset $offset
        Assert-That (-not $unchanged.moved -and $unchanged.outcome -ceq 'no-progress' -and $unchanged.model -ceq '') 'old success was reused for a new pass'
        Add-Content $journal '{"id":"S0001","outcome":"limit-hit","model":"sonnet","complexity":"medium"}'
        Add-Content $journal '{"id":"S0001","outcome":"context-handoff","model":"sonnet","complexity":"medium"}'
        Add-Content $journal '{"id":"S0001","outcome":"ok","model":"sonnet","complexity":"medium"}'
        $outcome = Read-PqPassOutcome -RepoPath $repoADir -Instance pq1 -TicketId S0001 -StatusBefore Draft -ChildExitCode 0 -HarnessRoot $harness -JournalOffset $offset
        Assert-That ($outcome.moved -and $outcome.outcome -ceq 'ok' -and $outcome.limits -eq 1 -and $outcome.launches -eq 3) 'limit or handoff was lost inside the pass'
        $failedPass = Read-PqPassOutcome -RepoPath $repoADir -Instance pq1 -TicketId S0001 -StatusBefore Draft -ChildExitCode 7 -HarnessRoot $harness -JournalOffset $offset
        Assert-That ($failedPass.outcome -ceq 'child-failed') 'runner failure was hidden by a successful journal row'
    }

    Run-SmokeCase 'Rule 46: a pass whose runner lost the claim before launch (exit 3) is claimLost, not child-failed' {
        $journal = Join-Path $repoADir 'temp/spec-queue/runs-pq1.jsonl'
        $offset = [IO.FileInfo]::new($journal).Length
        Add-Content $journal '{"id":"S0001","outcome":"claim-lost-before-launch","model":"haiku","complexity":"light","moved":false,"exitCode":null}'
        $lost = Read-PqPassOutcome -RepoPath $repoADir -Instance pq1 -TicketId S0001 -StatusBefore Verified -ChildExitCode 3 -HarnessRoot $harness -JournalOffset $offset
        Assert-That ($lost.outcome -ceq 'claim-lost-before-launch' -and (ConvertTo-PqPassEndOutcome $lost.outcome) -ceq 'claimLost') "a lost claim was journalled as $($lost.outcome)"
    }

    Run-SmokeCase 'V3/V4: simultaneous processes reserve distinct slots and only one repository lock' {
        $claimScript = Join-Path $scratch 'claim.ps1'
        @'
param($Harness, $Mode, $Gate, $Result, $Release)
$ErrorActionPreference = 'Stop'
. (Join-Path $Harness 'portfolio/lib/registry.ps1')
. (Join-Path $Harness 'portfolio/lib/loop.ps1')
while (-not (Test-Path $Gate)) { Start-Sleep -Milliseconds 20 }
$value = if ($Mode -eq 'slots') { Get-PqWorkerSlot @{ maxWorkers = 2 } } else { Lock-PqRepo 'race' }
[IO.File]::WriteAllText($Result, [string]$value)
while (-not (Test-Path $Release)) { Start-Sleep -Milliseconds 20 }
if ($Mode -eq 'slots' -and $value) { Remove-PqWorkerState $value }
elseif ($value) { Unlock-PqRepo $value }
'@ | Set-Content $claimScript
        foreach ($mode in 'slots', 'repo') {
            $gate = Join-Path $scratch "$mode.gate"
            $release = Join-Path $scratch "$mode.release"
            $children = @()
            $results = @()
            try {
                for ($i = 0; $i -lt 3; $i++) {
                    $result = Join-Path $scratch "$mode-$i.result"
                    $results += $result
                    $psi = [Diagnostics.ProcessStartInfo]::new((Get-Command pwsh).Source)
                    foreach ($a in @('-NoProfile', '-File', $claimScript, $harness, $mode, $gate, $result, $release)) { $psi.ArgumentList.Add($a) }
                    $psi.UseShellExecute = $false
                    $children += [Diagnostics.Process]::Start($psi)
                }
                Set-Content $gate 'go'
                Wait-SmokeCondition { @($results | Where-Object { Test-Path $_ }).Count -eq 3 } 'claim processes did not return' 15
                $values = @($results | ForEach-Object { [IO.File]::ReadAllText($_) } | Where-Object { $_ })
                if ($mode -eq 'slots') {
                    Assert-That ($values.Count -eq 2 -and @($values | Sort-Object -Unique).Count -eq 2) "slots were duplicated: $values"
                }
                else { Assert-That ($values.Count -eq 1) "repo lock had $($values.Count) winners" }
            }
            finally {
                Set-Content $release 'go'
                foreach ($child in $children) {
                    if (-not $child.WaitForExit(5000)) { $child.Kill($true); $null = $child.WaitForExit(5000) }
                    $child.Dispose()
                }
            }
        }
        $lockFile = Join-Path $portfolioRoot 'run/repo-stale.lock'
        '{"pid":2147483647}' | Set-Content $lockFile
        $taken = Lock-PqRepo 'stale'
        Assert-That ($taken -and [IO.Path]::GetFullPath($taken) -ceq [IO.Path]::GetFullPath($lockFile)) 'dead owner lock was not reclaimed'
        Assert-That ($null -eq (Lock-PqRepo 'stale')) 'live owner lock was overwritten'
        Unlock-PqRepo $taken
    }

    Run-SmokeCase 'V3/rule 60: a pass that outlives its killed dispatcher keeps the repository occupied' {
        # The dispatcher alone was ended (Task Manager, Stop-Process): its runner is not in a job and runs on.
        $own = (Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
        $lockFile = Join-Path $portfolioRoot 'run/repo-orphan.lock'
        [ordered]@{ pid = 2147483647; startedAt = 'dead'; passPid = $PID; passStartedAt = $own } | ConvertTo-Json -Compress | Set-Content $lockFile
        Assert-That ($null -eq (Lock-PqRepo 'orphan')) 'a second robot took a repository whose pass is still running'
        $occ = Get-PqOccupiedRepos @{ repos = @(@{ key = 'orphan'; path = $scratch }) }
        Assert-That (@($occ) -ccontains 'orphan' -and (Test-Path $lockFile)) 'a repository with a live orphaned pass was reported free'
        [ordered]@{ pid = 2147483647; startedAt = 'dead'; passPid = 2147483646; passStartedAt = 'dead' } | ConvertTo-Json -Compress | Set-Content $lockFile
        $taken = Lock-PqRepo 'orphan'
        Assert-That ($null -ne $taken) 'a lock whose dispatcher and pass are both gone was not reclaimed'
        Unlock-PqRepo $taken
    }

    Run-SmokeCase 'Tickets verb: lists every repository with its ticket queue file, opens one by key, follows the profile' {
        $list = Invoke-SmokePq @('tickets')
        Assert-That ($list.code -eq 0) "tickets exited $($list.code): $($list.output)"
        Assert-That ($list.stdout -match 'repo-a\s+file\s+.*RELEASE_QUEUE\.md' -and $list.stdout -match 'repo-b\s+file\s+.*RELEASE_QUEUE\.md') "unexpected listing: $($list.stdout)"
        $one = Invoke-SmokePq @('tickets', 'repo-a', '-NoOpen')
        Assert-That ($one.code -eq 0 -and $one.stdout.Trim() -ceq [IO.Path]::GetFullPath((Join-Path $repoADir 'PLAN/RELEASE_QUEUE.md'))) "wrong path: $($one.stdout)"
        $bad = Invoke-SmokePq @('tickets', 'nope', '-NoOpen')
        Assert-That ($bad.code -eq 2 -and $bad.stderr -match 'UnknownRepoKey') "unknown key was not refused: $($bad.output)"
        $profileFile = Join-Path $repoBDir '.sza-profile.json'
        $original = [IO.File]::ReadAllText($profileFile)
        try {
            $prof = $original | ConvertFrom-Json
            $paths = if ($prof.PSObject.Properties['paths']) { $prof.paths } else { $null }
            if ($null -eq $paths) { $paths = [pscustomobject]@{}; $prof | Add-Member -NotePropertyName paths -NotePropertyValue $paths }
            $paths | Add-Member -NotePropertyName releaseQueue -NotePropertyValue 'PLAN/OTHER_QUEUE.md' -Force
            [IO.File]::WriteAllText($profileFile, ($prof | ConvertTo-Json -Depth 20))
            $missing = Invoke-SmokePq @('tickets', 'repo-b', '-NoOpen')
            Assert-That ($missing.code -eq 2 -and $missing.stderr -match 'TicketQueueMissing' -and $missing.stderr -match 'OTHER_QUEUE\.md') "profile path was ignored: $($missing.output)"
        }
        finally { [IO.File]::WriteAllText($profileFile, $original) }
    }

    Run-SmokeCase 'Shortcuts: the PQ set (one tickets shortcut per repository) goes to the Desktop and the root, repeatably, removably, foreign files left alone' {
        $installer = Join-Path $harness 'portfolio\install-shortcuts.ps1'
        $desk = Join-Path $scratch 'desktop'
        $root = Join-Path $scratch 'rootdir'
        New-Item -ItemType Directory -Path $desk, $root | Out-Null
        $shell = New-Object -ComObject WScript.Shell
        $foreignPath = Join-Path $desk 'PQ Status.lnk'
        $foreign = $shell.CreateShortcut($foreignPath)
        $foreign.TargetPath = Join-Path $env:SystemRoot 'System32\notepad.exe'
        $foreign.Save()
        # Ours but out of date: the former projects shortcut, and a tickets shortcut of a repository that is not registered.
        foreach ($stale in 'PQ Queue', 'PQ Tickets gone') {
            $l = $shell.CreateShortcut((Join-Path $root ($stale + '.lnk')))
            $l.TargetPath = Join-Path $PSHOME 'pwsh.exe'
            $l.Arguments = "-NoExit -NoProfile -File `"$harness\portfolio\pq.ps1`" queue"
            $l.Save()
        }

        $out = & pwsh -NoProfile -File $installer -Desktop $desk -RootDir $root | Out-String
        Assert-That ($LASTEXITCODE -eq 0) "installer exited $LASTEXITCODE"
        Assert-That ($out -match '(?m)^install-shortcuts: 13 created, 0 updated, 0 unchanged, 0 removed, 1 foreign in .*desktop') "unexpected desktop summary: $out"
        Assert-That ($out -match '(?m)^install-shortcuts: 14 created, 0 updated, 0 unchanged, 2 removed, 0 foreign in .*rootdir') "unexpected root summary: $out"
        Assert-That (@(Get-ChildItem -LiteralPath $desk -Filter '*.lnk').Count -eq 14) 'desktop: expected 13 PQ shortcuts plus the foreign one'
        Assert-That (@(Get-ChildItem -LiteralPath $root -Filter '*.lnk').Count -eq 14) 'root: expected 14 PQ shortcuts and neither stale one'
        Assert-That (-not (Test-Path -LiteralPath (Join-Path $root 'PQ Queue.lnk')) -and -not (Test-Path -LiteralPath (Join-Path $root 'PQ Tickets gone.lnk'))) 'a stale shortcut of ours survived the refresh'
        $one = $shell.CreateShortcut((Join-Path $desk 'PQ Start 1 ticket.lnk'))
        Assert-That ($one.Arguments -match '-NoExit' -and $one.Arguments -match 'portfolio\\pq\.ps1" start -MaxTickets 1$') "bad arguments: $($one.Arguments)"
        $drain = $shell.CreateShortcut((Join-Path $root 'PQ Start Drain.lnk'))
        Assert-That ($drain.Arguments -match 'portfolio\\pq\.ps1" start -Drain$') "bad arguments: $($drain.Arguments)"
        $kill = $shell.CreateShortcut((Join-Path $desk 'PQ Stop Kill.lnk'))
        Assert-That ($kill.Arguments -match 'portfolio\\pq\.ps1" stop -Kill$') "bad arguments: $($kill.Arguments)"
        $projects = $shell.CreateShortcut((Join-Path $desk 'PQ Projects.lnk'))
        Assert-That ($projects.Arguments -match 'portfolio\\pq\.ps1" queue$') "bad arguments: $($projects.Arguments)"
        $tickets = $shell.CreateShortcut((Join-Path $root 'PQ Tickets repo-a.lnk'))
        Assert-That ($tickets.Arguments -match 'portfolio\\pq\.ps1" tickets repo-a$') "bad arguments: $($tickets.Arguments)"
        Assert-That (Test-Path -LiteralPath (Join-Path $root 'PQ Tickets repo-b.lnk')) 'no tickets shortcut for repo-b'
        $guide = $shell.CreateShortcut((Join-Path $desk 'PQ Guide.lnk'))
        Assert-That ($guide.TargetPath -ieq (Join-Path $harness 'portfolio\README.md') -and (Test-Path -LiteralPath $guide.TargetPath)) "guide points at $($guide.TargetPath)"
        Assert-That ($shell.CreateShortcut($foreignPath).TargetPath -imatch 'notepad\.exe$') 'the foreign shortcut was overwritten'

        $again = & pwsh -NoProfile -File $installer -Desktop $desk -RootDir $root | Out-String
        Assert-That ($again -match '0 created, 0 updated, 13 unchanged, 0 removed, 1 foreign' -and $again -match '0 created, 0 updated, 14 unchanged, 0 removed, 0 foreign') "second run was not a no-op: $again"

        $only = & pwsh -NoProfile -File $installer -Where Root -RootDir $root -DryRun | Out-String
        Assert-That ($only -notmatch 'desktop' -and $only -match '14 unchanged|would update') "-Where Root touched the desktop: $only"

        $gone = & pwsh -NoProfile -File $installer -Desktop $desk -RootDir $root -Remove | Out-String
        Assert-That ($gone -match '13 removed, 1 foreign' -and $gone -match '14 removed, 0 foreign') "unexpected remove summary: $gone"
        Assert-That (@(Get-ChildItem -LiteralPath $desk -Filter '*.lnk').Count -eq 1 -and (Test-Path -LiteralPath $foreignPath)) 'remove touched more than the PQ set'
        Assert-That (@(Get-ChildItem -LiteralPath $root -Filter '*.lnk').Count -eq 0) 'remove left shortcuts in the root'
    }

    Run-SmokeCase 'V7: a killed pass releases only the lease it made, never one with another reason' {
        $leaseDir = Join-Path $repoBDir 'temp/SPEC-TICKET.LEASES'
        New-Item -ItemType Directory -Path $leaseDir -Force | Out-Null
        $leaseFile = Join-Path $leaseDir 'S0001.json'
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        foreach ($case in @(@{ reason = 'spec-picker'; gone = $false }, @{ reason = 'run-spec-queue pq2'; gone = $false }, @{ reason = 'run-spec-queue pq1'; gone = $true })) {
            [ordered]@{ schema = 1; id = 'S0001'; sessionId = [guid]::NewGuid().ToString(); host = $env:COMPUTERNAME; pid = 2147483646; reason = $case.reason
                claimedAt = $now; lastSeenAt = $now; transcriptPath = $null } | ConvertTo-Json -Compress | Set-Content $leaseFile
            $released = Remove-PqKilledPassLease -RepoPath $repoBDir -TicketId 'S0001' -Instance 'pq1'
            Assert-That ($released -eq $case.gone) "reason '$($case.reason)': released=$released, expected $($case.gone)"
            Assert-That ((Test-Path $leaseFile) -eq (-not $case.gone)) "reason '$($case.reason)': the lease file state does not match"
        }
        Assert-That (-not (Remove-PqKilledPassLease -RepoPath $repoBDir -TicketId 'S0001' -Instance 'pq1')) 'no lease at all must be a quiet no-op'
    }

    Run-SmokeCase 'V14: a pass child does not inherit the starting agent''s session, only its credentials and settings' {
        # Earlier stop/kill cases leave their stop request in this throwaway portfolio.
        Remove-Item -LiteralPath (Join-Path $portfolioRoot 'STOP') -Force -ErrorAction SilentlyContinue
        $dumper = Join-Path $scratch 'env-dumper.ps1'
        @'
param($RepoRoot, $Ids, $MaxTickets, $ModelPolicy, $Instance, $PermissionMode)
$names = 'CLAUDECODE', 'CLAUDE_CODE_SESSION_ID', 'CLAUDE_CODE_ENTRYPOINT', 'CLAUDE_CODE_MESSAGING_TOKEN', 'CLAUDE_AGENT_SDK_VERSION',
         'PQSMOKE_AGENT_ID', 'CLAUDE_CODE_OAUTH_TOKEN', 'CLAUDE_CODE_GIT_BASH_PATH', 'CLAUDE_CODE_USE_VERTEX'
$seen = [ordered]@{}
foreach ($n in $names) { $seen[$n] = [Environment]::GetEnvironmentVariable($n) }
$seen | ConvertTo-Json | Set-Content (Join-Path $RepoRoot 'temp/env-dump.json')
'@ | Set-Content $dumper
        $set = [ordered]@{
            CLAUDECODE = '1'; CLAUDE_CODE_SESSION_ID = 'parent-session'; CLAUDE_CODE_ENTRYPOINT = 'cli'
            CLAUDE_CODE_MESSAGING_TOKEN = 'secret'; CLAUDE_AGENT_SDK_VERSION = '1'; PQSMOKE_AGENT_ID = 'parent'
            CLAUDE_CODE_OAUTH_TOKEN = 'keep-token'; CLAUDE_CODE_GIT_BASH_PATH = 'keep-path'; CLAUDE_CODE_USE_VERTEX = 'keep-flag'
        }
        $before = @{}
        foreach ($k in $set.Keys) { $before[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $set[$k]) }
        $dump = Join-Path $repoADir 'temp/env-dump.json'
        Remove-Item -LiteralPath $dump -ErrorAction SilentlyContinue
        try {
            $r = Invoke-PqPassChild -Script $dumper -RepoPath $repoADir -TicketId 'S0001' -PermissionMode 'acceptEdits'
        }
        finally {
            foreach ($k in $set.Keys) { [Environment]::SetEnvironmentVariable($k, $before[$k]) }
        }
        Assert-That ($r.code -eq 0 -and (Test-Path -LiteralPath $dump)) 'the dumping child did not run'
        $seen = Get-Content -Raw $dump | ConvertFrom-Json
        foreach ($n in 'CLAUDECODE', 'CLAUDE_CODE_SESSION_ID', 'CLAUDE_CODE_ENTRYPOINT', 'CLAUDE_CODE_MESSAGING_TOKEN', 'CLAUDE_AGENT_SDK_VERSION', 'PQSMOKE_AGENT_ID') {
            Assert-That ($null -eq $seen.$n) "$n reached the pass child"
        }
        foreach ($n in 'CLAUDE_CODE_OAUTH_TOKEN', 'CLAUDE_CODE_GIT_BASH_PATH', 'CLAUDE_CODE_USE_VERTEX') {
            Assert-That ($seen.$n -ceq $set[$n]) "$n was stripped but is a credential or setting"
        }
    }

    Run-SmokeCase 'Rule 29: the read-only children (picker, ticket record, lease release) do not speak as the starting agent' {
        # spec-next-preflight.ps1 keeps a lease whose holder is "mine" in the ranking, so a picker that inherits the
        # launching session's CLAUDE_CODE_SESSION_ID offers the very ticket that session holds.
        $dumper = Join-Path $scratch 'env-dumper-child.ps1'
        @'
$seen = [ordered]@{}
foreach ($n in 'CLAUDECODE', 'CLAUDE_CODE_SESSION_ID', 'PQSMOKE_AGENT_ID', 'CLAUDE_CODE_OAUTH_TOKEN') { $seen[$n] = [Environment]::GetEnvironmentVariable($n) }
$seen | ConvertTo-Json -Compress
'@ | Set-Content $dumper
        $set = [ordered]@{ CLAUDECODE = '1'; CLAUDE_CODE_SESSION_ID = 'parent-session'; PQSMOKE_AGENT_ID = 'parent'; CLAUDE_CODE_OAUTH_TOKEN = 'keep-token' }
        $before = @{}
        foreach ($k in $set.Keys) { $before[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $set[$k]) }
        try { $r = Invoke-PqRepoChild -RepoPath $repoADir -Script $dumper -Arguments @() -TimeoutSeconds 60 }
        finally { foreach ($k in $set.Keys) { [Environment]::SetEnvironmentVariable($k, $before[$k]) } }
        Assert-That ($r.code -eq 0) "the dumping child failed: $($r.stderr)"
        $seen = ConvertFrom-Json ([string]$r.stdout).Trim()
        foreach ($n in 'CLAUDECODE', 'CLAUDE_CODE_SESSION_ID', 'PQSMOKE_AGENT_ID') { Assert-That ($null -eq $seen.$n) "$n reached a read-only repository child" }
        Assert-That ($seen.CLAUDE_CODE_OAUTH_TOKEN -ceq 'keep-token') 'a credential was stripped from a repository child'
    }
}
finally {
    $env:SZA_PORTFOLIO_ROOT = $savedPortfolioRoot
    $env:USERPROFILE = $savedUserProfile
    $env:SZA_PROJECT_ROOT = $savedProjectRoot
    $env:SZA_PROFILE_PATH = $savedProfilePath
    if ($scratch -and -not $KeepScratch -and (Test-Path -LiteralPath $scratch)) {
        $resolved = [IO.Path]::GetFullPath($scratch)
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe scratch cleanup: $resolved" }
        Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
if ($failed -gt 0) {
    Write-Host "smoke-portfolio-runner: FAIL ($passed passed, $failed failed)" -ForegroundColor Red
    exit 1
}
Write-Host "smoke-portfolio-runner: PASS ($passed passed, 0 failed)" -ForegroundColor Green
exit 0
