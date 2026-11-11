#requires -Version 7.0
# Tests for S0034: occupancy robot vs owner classification, flat pass-sessions, robot transcript detection, and concurrent repo occupancy
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

    Write-Host "`nAll 4 test cases passed successfully." -ForegroundColor Green
}
finally {
    $env:SZA_PORTFOLIO_ROOT = $origEnv
    $env:USERPROFILE = $origProfile
    if ([IO.Directory]::Exists($scratch)) {
        Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}
