#requires -Version 7.0
# Tests for S0034: occupancy robot vs owner classification, flat pass-sessions, robot transcript detection, and concurrent repo occupancy
# Case 6 (TASK-FLOW 0.40): a `pq start -Repo` worker skips the transcript evidence in the repository it names.
# Case 7 (TASK-FLOW rule 61, CANONR-0196 C-G13): a live lock whose holder is not a dispatcher pass occupies the repository.
$ErrorActionPreference = 'Stop'
$lib = Join-Path (Split-Path $PSScriptRoot -Parent) 'harness/portfolio/lib'
. (Join-Path $lib 'paths.ps1')
. (Join-Path $lib 'events.ps1')
. (Join-Path $lib 'registry.ps1')
. (Join-Path $lib 'loop.ps1')
. (Join-Path $lib 'occupancy.ps1')

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('pq-occ-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($scratch)
$origEnv = $env:SZA_PORTFOLIO_ROOT
$origProfile = $env:USERPROFILE
$env:SZA_PORTFOLIO_ROOT = $scratch

try {
    # Case 1: Pass-sessions flat storage, retrieval, and legacy whitespace-collapsed string migration
    Write-Host "Case 1: pass-sessions flat storage, reading, and legacy recovery..." -NoNewline
    $runDir = Join-Path $scratch 'run'
    $null = [IO.Directory]::CreateDirectory($runDir)
    $passSessionsFile = Join-Path $runDir 'pass-sessions.json'

    # Write legacy corrupted format (single element string with space-joined IDs)
    $legacyJson = '["sess-1 sess-2 sess-3","sess-4"]'
    [IO.File]::WriteAllText($passSessionsFile, $legacyJson, [Text.Encoding]::UTF8)

    # Get-PqPassSessions recovers each ID individually
    $recovered = Get-PqPassSessions
    if (-not $recovered.Contains('sess-1') -or -not $recovered.Contains('sess-2') -or -not $recovered.Contains('sess-3') -or -not $recovered.Contains('sess-4')) {
        throw "Failed to recover all individual IDs from legacy collapsed pass-sessions.json"
    }

    # Add-PqPassSessions flattens the file cleanly when appending
    Add-PqPassSessions @('sess-5')
    $parsed = ConvertFrom-Json ([IO.File]::ReadAllText($passSessionsFile))
    $items = @($parsed)
    if ($items.Count -ne 5) {
        throw "Expected 5 distinct elements in pass-sessions.json after Add-PqPassSessions, got $($items.Count): $($parsed | ConvertTo-Json -Compress)"
    }
    if ($items -notcontains 'sess-1' -or $items -notcontains 'sess-5') {
        throw "pass-sessions.json missing expected elements: $($parsed | ConvertTo-Json -Compress)"
    }
    Write-Host " PASS" -ForegroundColor Green

    # Case 2: Test-PqTranscriptIsRobot detects "an unattended queue pass" in first 1 KB only
    Write-Host "Case 2: Test-PqTranscriptIsRobot header inspection..." -NoNewline
    $testFilesDir = Join-Path $scratch 'transcripts-test'
    $null = [IO.Directory]::CreateDirectory($testFilesDir)

    $robotTranscript = Join-Path $testFilesDir 'robot.jsonl'
    $robotLine = '{"type":"queue-operation","content":"/sza:spec-to-audit S0001 - an unattended queue pass, nobody answers questions"}'
    [IO.File]::WriteAllText($robotTranscript, $robotLine, [Text.Encoding]::UTF8)

    if (-not (Test-PqTranscriptIsRobot $robotTranscript)) {
        throw "Expected Test-PqTranscriptIsRobot to return true for robot transcript"
    }

    $manualTranscript = Join-Path $testFilesDir 'manual.jsonl'
    $manualLine = '{"type":"user","message":{"content":"please check why this test is failing"}}'
    [IO.File]::WriteAllText($manualTranscript, $manualLine, [Text.Encoding]::UTF8)

    if (Test-PqTranscriptIsRobot $manualTranscript) {
        throw "Expected Test-PqTranscriptIsRobot to return false for manual transcript"
    }

    # String beyond 1 KB should not trigger robot detection
    $paddedTranscript = Join-Path $testFilesDir 'padded.jsonl'
    $paddedContent = ('A' * 1500) + 'an unattended queue pass'
    [IO.File]::WriteAllText($paddedTranscript, $paddedContent, [Text.Encoding]::UTF8)

    if (Test-PqTranscriptIsRobot $paddedTranscript) {
        throw "Expected Test-PqTranscriptIsRobot to return false when signature is beyond 1 KB"
    }
    Write-Host " PASS" -ForegroundColor Green

    # Case 3: Get-PqRepoOccupancy filters by occupiedMinutes window and skips robot passes
    Write-Host "Case 3: Get-PqRepoOccupancy time window and robot pass skipping..." -NoNewline
    $fakeProfile = Join-Path $scratch 'userprofile'
    $fakeRepoPath = 'P:\TEST\demo-repo'
    $sanitized = [regex]::Replace($fakeRepoPath, '[^A-Za-z0-9]', '-')
    $transcriptDir = Join-Path (Join-Path (Join-Path $fakeProfile '.claude') 'projects') $sanitized
    $null = [IO.Directory]::CreateDirectory($transcriptDir)
    $env:USERPROFILE = $fakeProfile

    $registry = @{ occupiedMinutes = 5 }
    $repoRec = @{ key = 'demo'; path = $fakeRepoPath; concurrent = $false }

    # 1. Old manual transcript (>10 minutes ago) -> not occupied
    $oldManual = Join-Path $transcriptDir 'old-manual.jsonl'
    [IO.File]::WriteAllText($oldManual, '{"user":"hello"}', [Text.Encoding]::UTF8)
    [IO.File]::SetLastWriteTimeUtc($oldManual, [DateTime]::UtcNow.AddMinutes(-15))

    $occ = Get-PqRepoOccupancy -Repo $repoRec -Registry $registry -NoLease
    if ($occ.occupied) {
        throw "Expected occupied=false for transcript older than occupiedMinutes window"
    }

    # 2. Recent transcript (<1 minute ago) but belongs to robot pass -> not occupied
    $recentRobot = Join-Path $transcriptDir 'recent-robot.jsonl'
    [IO.File]::WriteAllText($recentRobot, $robotLine, [Text.Encoding]::UTF8)
    [IO.File]::SetLastWriteTimeUtc($recentRobot, [DateTime]::UtcNow.AddSeconds(-30))

    $occ = Get-PqRepoOccupancy -Repo $repoRec -Registry $registry -NoLease
    if ($occ.occupied) {
        throw "Expected occupied=false when recent transcript is a robot pass"
    }

    # 3. Recent transcript from pass-sessions.json -> not occupied
    $passSessFile = Join-Path $transcriptDir 'sess-5.jsonl'
    [IO.File]::WriteAllText($passSessFile, '{"type":"user","content":"work"}', [Text.Encoding]::UTF8)
    [IO.File]::SetLastWriteTimeUtc($passSessFile, [DateTime]::UtcNow.AddSeconds(-20))

    $occ = Get-PqRepoOccupancy -Repo $repoRec -Registry $registry -NoLease
    if ($occ.occupied) {
        throw "Expected occupied=false when recent transcript is in pass-sessions.json"
    }

    # 4. Recent manual session (<1 minute ago) -> occupied!
    $recentManual = Join-Path $transcriptDir 'recent-manual.jsonl'
    [IO.File]::WriteAllText($recentManual, '{"user":"developer manual work"}', [Text.Encoding]::UTF8)
    [IO.File]::SetLastWriteTimeUtc($recentManual, [DateTime]::UtcNow.AddSeconds(-10))

    $occ = Get-PqRepoOccupancy -Repo $repoRec -Registry $registry -NoLease
    if (-not $occ.occupied -or $occ.by -ne 'transcript' -or $occ.holderKind -ne 'manual') {
        throw "Expected occupied=true (by=transcript, holderKind=manual) for recent manual transcript, got: $($occ | ConvertTo-Json -Compress)"
    }
    Write-Host " PASS" -ForegroundColor Green

    # Case 4: Occupancy check applies to concurrent repositories too
    Write-Host "Case 4: Occupancy check applies to concurrent repositories..." -NoNewline
    $concurrentRepoRec = @{ key = 'demo-conc'; path = $fakeRepoPath; concurrent = $true }
    $occConc = Get-PqRepoOccupancy -Repo $concurrentRepoRec -Registry $registry -NoLease
    if (-not $occConc.occupied -or $occConc.by -ne 'transcript') {
        throw "Expected Get-PqRepoOccupancy to report occupied=true for concurrent repository when manual session active"
    }

    # In loop.ps1, verify Get-PqRepoOccupancy is called directly without being guarded by (-not $isConcurrent)
    $loopScript = Join-Path $lib 'loop.ps1'
    $loopContent = [IO.File]::ReadAllText($loopScript)
    if ($loopContent -match '(?s)if\s*\(-not\s*\$isConcurrent\)\s*\{\s*\$occ\s*=\s*Get-PqRepoOccupancy') {
        throw "loop.ps1 still guards Get-PqRepoOccupancy with 'if (-not `$isConcurrent)'"
    }
    Write-Host " PASS" -ForegroundColor Green

    # Case 5: the whole registry is read in one go, so one walk of the rank can go past every occupied repository
    Write-Host "Case 5: Get-PqTranscriptOccupiedRepos reads every repository and says when each can be free..." -NoNewline
    $projectsDir = Join-Path (Join-Path $fakeProfile '.claude') 'projects'
    $quietPath = 'P:\TEST\quiet-repo'
    $null = [IO.Directory]::CreateDirectory((Join-Path $projectsDir ([regex]::Replace($quietPath, '[^A-Za-z0-9]', '-'))))
    $offPath = 'P:\TEST\off-repo'
    $offDir = Join-Path $projectsDir ([regex]::Replace($offPath, '[^A-Za-z0-9]', '-'))
    $null = [IO.Directory]::CreateDirectory($offDir)
    $offTranscript = Join-Path $offDir 'recent-manual.jsonl'
    [IO.File]::WriteAllText($offTranscript, '{"user":"work in a disabled repository"}', [Text.Encoding]::UTF8)
    [IO.File]::SetLastWriteTimeUtc($offTranscript, [DateTime]::UtcNow.AddSeconds(-5))
    $registry5 = @{ occupiedMinutes = 5; repos = @(
            @{ key = 'demo'; path = $fakeRepoPath; enabled = $true },
            @{ key = 'quiet'; path = $quietPath; enabled = $true },
            @{ key = 'off'; path = $offPath; enabled = $false },
            @{ key = 'nofolder'; path = 'P:\TEST\no-folder-at-all'; enabled = $true }) }
    $found = Get-PqTranscriptOccupiedRepos -Registry $registry5
    $keys = @($found.Keys)
    if ($keys.Count -ne 1 -or $keys[0] -cne 'demo') {
        throw "Expected only 'demo' (enabled, recent manual transcript), got: $($keys -join ', ')"
    }
    # The newest manual transcript of 'demo' is 10 s old in a 5 minute window: free in about 290 s, never sooner.
    $freeIn = [int]$found['demo'].freeInSeconds
    if ($freeIn -lt 270 -or $freeIn -gt 300) {
        throw "Expected freeInSeconds of about 290 for a 10 s old transcript in a 5 minute window, got $freeIn"
    }
    if ($loopContent -notmatch 'Get-PqTranscriptOccupiedRepos') {
        throw "loop.ps1 does not read the owner's sessions of every repository before it ranks"
    }
    Write-Host " PASS" -ForegroundColor Green

    # Case 6: a `pq start -Repo` worker does not wait for the owner's transcript in the repository it names (TASK-FLOW 0.40)
    Write-Host "Case 6: -SkipTranscript drops the transcript evidence only, and the loop passes it for -Repo..." -NoNewline
    $occSkip = Get-PqRepoOccupancy -Repo $repoRec -Registry $registry -NoLease -SkipTranscript
    if ($occSkip.occupied) {
        throw "Expected occupied=false with -SkipTranscript for a recent manual transcript, got: $($occSkip | ConvertTo-Json -Compress)"
    }
    $occKept = Get-PqRepoOccupancy -Repo $repoRec -Registry $registry -NoLease
    if (-not $occKept.occupied -or $occKept.by -ne 'transcript') {
        throw "Expected the call without -SkipTranscript to stay occupied by the same transcript, got: $($occKept | ConvertTo-Json -Compress)"
    }
    if ($loopContent -notmatch '-SkipTranscript:\$namedRepo') {
        throw "loop.ps1 does not pass -SkipTranscript for the repository a -Repo worker names"
    }
    if ($loopContent -notmatch 'if \(\$null -eq \$named -and -not \$OnlyRepo\)\s*\{\s*\$ownerIn') {
        throw "loop.ps1 still reads every repository's transcripts in a -Repo worker"
    }
    Write-Host " PASS" -ForegroundColor Green

    # Case 7: a live lock whose holder is not a dispatcher pass occupies the repository (TASK-FLOW rule 61; CANONR-0196 C-G13)
    Write-Host "Case 7: lock evidence - live, stale, a pass's own, a concurrent repository..." -NoNewline
    $lockRepo = Join-Path $scratch 'lock-repo'
    $lockDir = Join-Path $lockRepo 'temp'
    $null = [IO.Directory]::CreateDirectory($lockDir)
    $lockFile = Join-Path $lockDir 'CODE.LOCK'
    $writeLock = {
        param([long]$AgeSeconds, [string]$Reason)
        $acq = [DateTimeOffset]::UtcNow.AddSeconds(-$AgeSeconds).ToUnixTimeMilliseconds()
        $obj = [ordered]@{ lockType = 'Code'; pid = 999999; procStart = 1; acquiredAt = $acq; reason = $Reason; host = 'x' }
        [IO.File]::WriteAllText($lockFile, ($obj | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
    }
    $lockReg = @{ occupiedMinutes = 3; repos = @() }
    $lockRec = @{ key = 'lockdemo'; path = $lockRepo; enabled = $true }
    & $writeLock 20 'edit by the owner'
    $o = Get-PqRepoOccupancy -Repo $lockRec -Registry $lockReg -NoLease -SkipTranscript
    if (-not $o.occupied -or $o.by -cne 'lock' -or $o.freeInSeconds -lt 150) { throw "a 20 s old lock of a dead process should occupy for about 160 s: $($o | ConvertTo-Json -Compress)" }
    $o = Get-PqRepoOccupancy -Repo $lockRec -Registry $lockReg -NoLease -SkipTranscript -NoLock
    if ($o.occupied) { throw "-NoLock should drop the lock kind: $($o | ConvertTo-Json -Compress)" }
    & $writeLock 400 'edit by the owner'
    $o = Get-PqRepoOccupancy -Repo $lockRec -Registry $lockReg -NoLease -SkipTranscript
    if ($o.occupied) { throw "a lock older than occupiedMinutes whose process is gone is not live: $($o | ConvertTo-Json -Compress)" }
    # A live process (this one) holds it however old the lock is.
    $me = Get-Process -Id $PID
    $acqOld = [DateTimeOffset]::UtcNow.AddSeconds(-4000).ToUnixTimeMilliseconds()
    [IO.File]::WriteAllText($lockFile, ([ordered]@{ lockType = 'Build'; pid = $PID; procStart = $me.StartTime.Ticks; acquiredAt = $acqOld; reason = 'build' } | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
    $o = Get-PqRepoOccupancy -Repo $lockRec -Registry $lockReg -NoLease -SkipTranscript
    if (-not $o.occupied -or $o.freeInSeconds -ne 0) { throw "a lock of a live process should occupy: $($o | ConvertTo-Json -Compress)" }
    # A lock taken inside a finished pass of the repository (runs.jsonl, widened by 60 s) is the pass's own.
    & $writeLock 30 'edit by a pass'
    $fin = [DateTime]::Now.AddSeconds(-10).ToString('yyyy-MM-ddTHH:mm:ss')
    [IO.File]::WriteAllText((Join-Path $scratch 'runs.jsonl'), ('{"repo":"lockdemo","id":"S1","seconds":60,"finishedAt":"' + $fin + '"}' + "`n"), [Text.UTF8Encoding]::new($false))
    $o = Get-PqRepoOccupancy -Repo $lockRec -Registry $lockReg -NoLease -SkipTranscript
    if ($o.occupied) { throw "a lock acquired inside a pass interval is the pass's own: $($o | ConvertTo-Json -Compress)" }
    Remove-Item -LiteralPath (Join-Path $scratch 'runs.jsonl') -Force
    # A concurrent repository counts only a lock of the ticket itself.
    $concRec = @{ key = 'lockdemo'; path = $lockRepo; enabled = $true; concurrent = $true }
    & $writeLock 20 'S0002 edit'
    $o = Get-PqRepoOccupancy -Repo $concRec -Registry $lockReg -NoLease -SkipTranscript -TicketId 'S0001'
    if ($o.occupied) { throw "a concurrent repository's lock of another ticket does not occupy: $($o | ConvertTo-Json -Compress)" }
    & $writeLock 20 'S0001 edit'
    $o = Get-PqRepoOccupancy -Repo $concRec -Registry $lockReg -NoLease -SkipTranscript -TicketId 'S0001'
    if (-not $o.occupied -or $o.by -cne 'lock') { throw "a concurrent repository's lock of the ticket itself occupies: $($o | ConvertTo-Json -Compress)" }
    Write-Host " PASS" -ForegroundColor Green

    Write-Host "`nAll 7 test cases passed successfully." -ForegroundColor Green
}
finally {
    $env:SZA_PORTFOLIO_ROOT = $origEnv
    $env:USERPROFILE = $origProfile
    if ([IO.Directory]::Exists($scratch)) {
        Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}
