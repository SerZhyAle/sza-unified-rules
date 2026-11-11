#requires -Version 7.0
# Tests for S0033: ranking cost optimizations, picker auto-skip short-circuit, first-head ranking, and queue.row deduplication
$ErrorActionPreference = 'Stop'
$lib = Join-Path (Split-Path $PSScriptRoot -Parent) 'harness/portfolio/lib'
. (Join-Path $lib 'paths.ps1')
. (Join-Path $lib 'events.ps1')
. (Join-Path $lib 'registry.ps1')
. (Join-Path $lib 'picker.ps1')
. (Join-Path $lib 'rank.ps1')
. (Join-Path $lib 'loop.ps1')

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('pq-cost-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($scratch)
$origEnv = $env:SZA_PORTFOLIO_ROOT
$env:SZA_PORTFOLIO_ROOT = $scratch

try {
    # Case 1: Get-PqPickerHead short-circuits on auto_skipped ticket in initial payload without calling second child
    Write-Host "Case 1: Get-PqPickerHead short-circuits on auto_skipped ticket in payload..." -NoNewline
    $mockPayload = [pscustomobject]@{
        selected = [pscustomobject]@{ id = 'S0010'; name = 'head-ticket'; priority = 80; status = 'Tactical' }
        ranked = @('S0010', 'S0011', 'S0012')
        auto_skipped = @(
            [pscustomobject]@{ id = 'S0011'; reason = 'idle-hold' }
            [pscustomobject]@{ id = 'S0012'; reason = 'owner-gate' }
        )
        leased_ids = @()
        excluded_ids = @()
        malformed = @()
    }
    $cache = @{ 'nonexistent-repo|' = @{ ok = $true; ms = 2; payload = $mockPayload } }

    # S0011 is in auto_skipped -> must return why = 'idle-hold' immediately without child process
    $r1 = Get-PqPickerHead -RepoPath 'nonexistent-repo' -ForceId 'S0011' -Cache $cache
    if (-not $r1.ok -or $null -ne $r1.head -or $r1.why -ne 'idle-hold') {
        throw "Expected short-circuit head=$null why='idle-hold', got: $(ConvertTo-Json $r1)"
    }

    # S0012 is in auto_skipped -> must return why = 'owner-gate' immediately without child process
    $r2 = Get-PqPickerHead -RepoPath 'nonexistent-repo' -ForceId 'S0012' -Cache $cache
    if (-not $r2.ok -or $null -ne $r2.head -or $r2.why -ne 'owner-gate') {
        throw "Expected short-circuit head=$null why='owner-gate', got: $(ConvertTo-Json $r2)"
    }
    Write-Host " PASS" -ForegroundColor Green

    # Case 2: Get-PqRank -FirstHead stops walking a repository once its first head is found
    Write-Host "Case 2: Get-PqRank -FirstHead restricts candidates to first head per project..." -NoNewline
    $testRegistry = [pscustomobject]@{
        repos = @(
            [pscustomobject]@{ key = 'proj1'; rank = 10; enabled = $true; path = 'p1' }
            [pscustomobject]@{ key = 'proj2'; rank = 20; enabled = $true; path = 'p2' }
        )
        fill = 'depth'
        maxWorkers = 5
    }
    $testQueue = [pscustomobject]@{
        rows = @(
            @{ repo = 'proj1'; kind = 'ticket'; id = 'T101'; line = 1; text = 'proj1:T101' }
            @{ repo = 'proj1'; kind = 'ticket'; id = 'T102'; line = 2; text = 'proj1:T102' }
            @{ repo = 'proj1'; kind = 'ticket'; id = 'T103'; line = 3; text = 'proj1:T103' }
            @{ repo = 'proj2'; kind = 'ticket'; id = 'T201'; line = 4; text = 'proj2:T201' }
            @{ repo = 'proj2'; kind = 'ticket'; id = 'T202'; line = 5; text = 'proj2:T202' }
        )
        held = @()
        bad = @()
    }
    $callsFirst = [Collections.Generic.List[string]]::new()
    $providerFirst = {
        param($Repo, $Exclude, $ForceId)
        $callsFirst.Add("$($Repo.key):$ForceId")
        return @{
            ok = $true
            head = [pscustomobject]@{ id = $ForceId; name = "title-$ForceId"; priority = 50; status = 'Tactical' }
            payload = [pscustomobject]@{
                selected = [pscustomobject]@{ id = $ForceId }
                ranked = @($ForceId)
                auto_skipped = @()
                leased_ids = @()
                excluded_ids = @()
                malformed = @()
            }
        }
    }

    # Run with -FirstHead
    $rankFirst = Get-PqRank -Registry $testRegistry -Queue $testQueue -HeadProvider $providerFirst -FirstHead
    if ($rankFirst.candidates.Count -ne 2) {
        throw "Expected exactly 2 candidates with -FirstHead (1 per repo), got $($rankFirst.candidates.Count)"
    }
    if ($rankFirst.candidates[0].id -ne 'T101' -or $rankFirst.candidates[1].id -ne 'T201') {
        throw "Expected T101 and T201, got $($rankFirst.candidates[0].id) and $($rankFirst.candidates[1].id)"
    }
    # Proves T102, T103, T202 were never called:
    if ($callsFirst.Count -ne 2 -or $callsFirst[0] -ne 'proj1:T101' -or $callsFirst[1] -ne 'proj2:T201') {
        throw "Expected only 2 provider calls (proj1:T101 and proj2:T201), got: $($callsFirst -join ', ')"
    }

    # Run without -FirstHead (exhaustive walk)
    $callsAll = [Collections.Generic.List[string]]::new()
    $providerAll = {
        param($Repo, $Exclude, $ForceId)
        $callsAll.Add("$($Repo.key):$ForceId")
        return @{
            ok = $true
            head = [pscustomobject]@{ id = $ForceId; name = "title-$ForceId"; priority = 50; status = 'Tactical' }
            payload = [pscustomobject]@{
                selected = [pscustomobject]@{ id = $ForceId }
                ranked = @($ForceId)
                auto_skipped = @()
                leased_ids = @()
                excluded_ids = @()
                malformed = @()
            }
        }
    }
    $rankAll = Get-PqRank -Registry $testRegistry -Queue $testQueue -HeadProvider $providerAll
    if ($rankAll.candidates.Count -ne 5) {
        throw "Expected 5 candidates without -FirstHead, got $($rankAll.candidates.Count)"
    }
    if ($callsAll.Count -lt 5) {
        throw "Expected at least 5 provider calls without -FirstHead, got $($callsAll.Count)"
    }
    Write-Host " PASS" -ForegroundColor Green

    # Case 3: queue.row event deduplication per run
    Write-Host "Case 3: queue.row event deduplication across ranking cycles..." -NoNewline
    $fakeLog = Open-PqLog -Writer 'w1' -Run 'R-test-dedup'
    $loggedBadQueueRows = [hashtable]::new([StringComparer]::Ordinal)

    $eventsCycle1 = @(
        @{ ev = 'queue.row'; d = [ordered]@{ kind = 'unknownRepo'; line = 10; text = 'bad row 10' } }
        @{ ev = 'queue.row'; d = [ordered]@{ kind = 'malformed'; line = 25; text = 'malformed ticket' } }
        @{ ev = 'rank.result'; d = [ordered]@{ fill = 'depth'; ms = 10 } }
    )
    $emittedCycle1 = [Collections.Generic.List[object]]::new()
    foreach ($e in $eventsCycle1) {
        if ($e.ev -ceq 'queue.row') {
            $rowKey = if ($null -ne $e.d.line -and [string]$e.d.line -ne '' -and [string]$e.d.line -ne '0') { [string]$e.d.line } else { "$($e.d.kind):$($e.d.text)" }
            $rowSig = "$($e.d.kind)|$($e.d.text)"
            if ($loggedBadQueueRows.ContainsKey($rowKey) -and $loggedBadQueueRows[$rowKey] -ceq $rowSig) {
                continue
            }
            $loggedBadQueueRows[$rowKey] = $rowSig
        }
        $emittedCycle1.Add($e)
        $null = Write-PqEvent -Log $fakeLog -Ev $e.ev -Run 'R-test-dedup' -Worker 1 -D $e.d
    }
    if ($emittedCycle1.Count -ne 3) {
        throw "Expected cycle 1 to emit 3 events, got $($emittedCycle1.Count)"
    }

    # Cycle 2: identical bad rows and a new rank.result
    $eventsCycle2 = @(
        @{ ev = 'queue.row'; d = [ordered]@{ kind = 'unknownRepo'; line = 10; text = 'bad row 10' } }
        @{ ev = 'queue.row'; d = [ordered]@{ kind = 'malformed'; line = 25; text = 'malformed ticket' } }
        @{ ev = 'rank.result'; d = [ordered]@{ fill = 'depth'; ms = 12 } }
    )
    $emittedCycle2 = [Collections.Generic.List[object]]::new()
    foreach ($e in $eventsCycle2) {
        if ($e.ev -ceq 'queue.row') {
            $rowKey = if ($null -ne $e.d.line -and [string]$e.d.line -ne '' -and [string]$e.d.line -ne '0') { [string]$e.d.line } else { "$($e.d.kind):$($e.d.text)" }
            $rowSig = "$($e.d.kind)|$($e.d.text)"
            if ($loggedBadQueueRows.ContainsKey($rowKey) -and $loggedBadQueueRows[$rowKey] -ceq $rowSig) {
                continue
            }
            $loggedBadQueueRows[$rowKey] = $rowSig
        }
        $emittedCycle2.Add($e)
        $null = Write-PqEvent -Log $fakeLog -Ev $e.ev -Run 'R-test-dedup' -Worker 1 -D $e.d
    }
    if ($emittedCycle2.Count -ne 1 -or $emittedCycle2[0].ev -ne 'rank.result') {
        throw "Expected cycle 2 to suppress both duplicate queue.row events and emit only rank.result, got: $($emittedCycle2.Count)"
    }

    # Cycle 3: line 10 text changed
    $eventsCycle3 = @(
        @{ ev = 'queue.row'; d = [ordered]@{ kind = 'unknownRepo'; line = 10; text = 'bad row 10 modified' } }
        @{ ev = 'queue.row'; d = [ordered]@{ kind = 'malformed'; line = 25; text = 'malformed ticket' } }
        @{ ev = 'rank.result'; d = [ordered]@{ fill = 'depth'; ms = 11 } }
    )
    $emittedCycle3 = [Collections.Generic.List[object]]::new()
    foreach ($e in $eventsCycle3) {
        if ($e.ev -ceq 'queue.row') {
            $rowKey = if ($null -ne $e.d.line -and [string]$e.d.line -ne '' -and [string]$e.d.line -ne '0') { [string]$e.d.line } else { "$($e.d.kind):$($e.d.text)" }
            $rowSig = "$($e.d.kind)|$($e.d.text)"
            if ($loggedBadQueueRows.ContainsKey($rowKey) -and $loggedBadQueueRows[$rowKey] -ceq $rowSig) {
                continue
            }
            $loggedBadQueueRows[$rowKey] = $rowSig
        }
        $emittedCycle3.Add($e)
        $null = Write-PqEvent -Log $fakeLog -Ev $e.ev -Run 'R-test-dedup' -Worker 1 -D $e.d
    }
    if ($emittedCycle3.Count -ne 2) {
        throw "Expected cycle 3 to emit changed queue.row and rank.result (2 events), got $($emittedCycle3.Count)"
    }
    Close-PqLog -Log $fakeLog
    Write-Host " PASS" -ForegroundColor Green

    Write-Host "`nAll 3 rank cost test cases PASSED cleanly." -ForegroundColor Green
}
finally {
    $env:SZA_PORTFOLIO_ROOT = $origEnv
    if (Test-Path $scratch) { Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue }
}
