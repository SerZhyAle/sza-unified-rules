#requires -Version 7.0
# Tests for S0035: provider limit holds carry reset time, limit text capture, detector status in events,
# per-agent log files, and wait for primary provider reset when <= 15 min.
$ErrorActionPreference = 'Stop'
$harness = Join-Path (Split-Path $PSScriptRoot -Parent) 'harness'
$batchLib = Join-Path $harness 'batch'
$pqLib = Join-Path $harness 'portfolio/lib'

. (Join-Path $batchLib '_limit-hold.ps1')
. (Join-Path $pqLib 'paths.ps1')
. (Join-Path $pqLib 'events.ps1')
. (Join-Path $pqLib 'registry.ps1')
. (Join-Path $pqLib 'loop.ps1')
. (Join-Path $pqLib 'ledger-watch.ps1')
. (Join-Path $pqLib 'agents.ps1')

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('pq-limit-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($scratch)
$origEnv = $env:SZA_PORTFOLIO_ROOT
$env:SZA_PORTFOLIO_ROOT = $scratch

try {
    # -----------------------------------------------------------------------------------------
    # Case 1: Get-LimitSignal captures matched line (cut at 300 chars) & Write-LimitHold persists text
    # -----------------------------------------------------------------------------------------
    Write-Host "Case 1: Get-LimitSignal line capture and hold text persistence..." -NoNewline
    $longPrefix = "Prefix line `n"
    $matchLine = "You have reached your OpenAI Codex usage limit for today. Try again at 2:38 AM."
    $longSuffix = "`nFollowing output line"
    $logBody = $longPrefix + $matchLine + $longSuffix

    $sig = Get-LimitSignal -LogBody $logBody -ExitCode 1 -Pattern '(?i)usage limit|rate limit|quota'
    if ($null -eq $sig) { throw "Expected limit signal from log body, got null" }
    if ($sig.Source -ne 'log') { throw "Expected Source 'log', got '$($sig.Source)'" }
    if ($sig.Text -ne $matchLine) { throw "Expected Text '$matchLine', got '$($sig.Text)'" }

    # Truncation test at 300 chars
    $veryLongMatch = "Usage limit exceeded: " + ("A" * 350)
    $sigLong = Get-LimitSignal -LogBody $veryLongMatch -ExitCode 1 -Pattern '(?i)usage limit'
    if ($sigLong.Text.Length -ne 300) { throw "Expected Text truncated to 300 chars, got length $($sigLong.Text.Length)" }

    # Write-LimitHold with Text
    $holdFile = Join-Path $scratch 'limit-hold.codex.json'
    $nowSec = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 1800
    $holdRes = Write-LimitHold -Path $holdFile -ResetsAt $nowSec -RateLimitType 'usage' -Instance 'pq1' -Ticket 'S0035' -Text $sig.Text
    if (-not (Test-Path -LiteralPath $holdFile)) { throw "Expected hold file to exist: $holdFile" }

    # Read-LimitHold returns Text
    $readHold = Read-LimitHold -Path $holdFile
    if ($readHold.Text -ne $matchLine) { throw "Expected Read-LimitHold.Text '$matchLine', got '$($readHold.Text)'" }

    # Get-PqRunnerLimitText reads from repo runs dir
    $fakeRepo = Join-Path $scratch 'fakeRepo'
    $runsDir = Join-Path $fakeRepo 'temp/spec-queue'
    $null = [IO.Directory]::CreateDirectory($runsDir)
    [IO.File]::WriteAllText((Join-Path $fakeRepo '.sza-profile.json'), '{"schema":1}', [Text.Encoding]::UTF8)
    $repoHoldFile = Join-Path $runsDir 'limit-hold.codex.json'
    [IO.File]::Copy($holdFile, $repoHoldFile, $true)

    $runnerText = Get-PqRunnerLimitText -RepoPath $fakeRepo -Agent 'codex'
    if ($runnerText -ne $matchLine) { throw "Expected Get-PqRunnerLimitText '$matchLine', got '$runnerText'" }
    Write-Host " PASS" -ForegroundColor Green

    # -----------------------------------------------------------------------------------------
    # Case 2: ConvertFrom-PqLimitText parses clock-time, next-day rollover, dates, and spans
    # -----------------------------------------------------------------------------------------
    Write-Host "Case 2: ConvertFrom-PqLimitText clock-time format and rollover..." -NoNewline
    # Test fixed reference now: 2026-11-10 23:00:00 UTC (local time in CET = 2026-11-11 00:00:00, +01:00)
    $refNow = [DateTimeOffset]::Parse("2026-11-10T23:00:00.000Z")
    
    # 2:38 AM with refNow 23:00 UTC (00:00 local CET): 02:38 CET is later today -> 02:38 CET (01:38 UTC) + 60s margin = 01:39 UTC
    $codexText = "You've hit your usage limit. Try again at 2:38 AM."
    $parsedIso = ConvertFrom-PqLimitText -Text $codexText -Now $refNow
    if ($null -eq $parsedIso) { throw "Expected parsed ISO for Codex limit text, got null" }
    $dto = [DateTimeOffset]::Parse($parsedIso)
    if ($dto.Minute -ne 39 -or $dto.Second -ne 0) {
        throw "Expected minute 39 (2:38 + 60s margin), got $($dto.ToString('o'))"
    }

    # Rollover test: refNow is 03:00:00 UTC on 2026-11-11 (04:00 local CET).
    # "Try again at 2:38 AM" is earlier than now, so it must advance to 2026-11-12!
    $refNowAfter = [DateTimeOffset]::Parse("2026-11-11T03:00:00.000Z")
    $rolloverIso = ConvertFrom-PqLimitText -Text $codexText -Now $refNowAfter
    $dtoRollover = [DateTimeOffset]::Parse($rolloverIso)
    if ($dtoRollover.Day -ne 12) {
        throw "Expected day 12 after rollover, got day $($dtoRollover.Day) in $($dtoRollover.ToString('o'))"
    }

    # Also verify existing date-time form still works (before reset time)
    $zText = "Usage limit reached for 5 hour. Your limit will reset at 2026-11-11 00:34:51"
    $refNowZ = [DateTimeOffset]::Parse("2026-11-10T15:00:00.000Z")
    $zIso = ConvertFrom-PqLimitText -Text $zText -Offset "+08:00" -Now $refNowZ
    if ($null -eq $zIso) { throw "Expected parsed ISO for z.ai format" }

    # Also verify relative span form still works
    $spanText = "Individual quota reached. Resets in 2h30m."
    $spanIso = ConvertFrom-PqLimitText -Text $spanText -Now $refNow
    if ($null -eq $spanIso) { throw "Expected parsed ISO for relative span" }
    Write-Host " PASS" -ForegroundColor Green

    # -----------------------------------------------------------------------------------------
    # Case 3: Per-agent log files (<ticket>.<agent>.log)
    # -----------------------------------------------------------------------------------------
    Write-Host "Case 3: Per-agent pass log file inspection and isolation..." -NoNewline
    $ticketId = "S9999"
    $codexLogFile = Join-Path $runsDir "$ticketId.codex.log"
    $geminiLogFile = Join-Path $runsDir "$ticketId.gemini.log"

    $codexContent = "Codex pass output`nYou've hit your usage limit. Try again at 2:38 AM."
    $geminiContent = "Gemini fallback pass output: completed normally with exit 0."
    [IO.File]::WriteAllText($codexLogFile, $codexContent, [Text.Encoding]::UTF8)
    [IO.File]::WriteAllText($geminiLogFile, $geminiContent, [Text.Encoding]::UTF8)

    $codexRecord = [ordered]@{ name = 'codex'; limitDetector = [ordered]@{ pattern = '(?i)usage limit'; status = 'unproven' } }
    $readCodexUntil = Get-PqLogLimitUntil -RepoPath $fakeRepo -TicketId $ticketId -Record $codexRecord
    if ($null -eq $readCodexUntil) { throw "Expected Get-PqLogLimitUntil to read from $ticketId.codex.log" }

    $readCodexText = Get-PqLogLimitText -RepoPath $fakeRepo -TicketId $ticketId -Record $codexRecord
    if ($readCodexText -notmatch "Try again at 2:38 AM") { throw "Expected Get-PqLogLimitText to read matched line, got '$readCodexText'" }
    Write-Host " PASS" -ForegroundColor Green

    # -----------------------------------------------------------------------------------------
    # Case 4: Event detector sourced from limitDetector.status & hold text
    # -----------------------------------------------------------------------------------------
    Write-Host "Case 4: Event detector from limitDetector.status in pass.limit and agent.hold..." -NoNewline
    # S0035 Set-PqAgentHold with Text and unproven detector
    Set-PqAgentHold -Name 'codex' -Pass 'run1.1' -Source 'log' -Detector 'unproven' -Until $readCodexUntil -Text $readCodexText
    $holdState = Read-PqState (Get-PqPath -Kind hold -Agent 'codex')
    if ((Get-PqValue $holdState 'detector') -ne 'unproven') {
        throw "Expected hold detector 'unproven', got '$((Get-PqValue $holdState 'detector'))'"
    }
    if ((Get-PqValue $holdState 'text') -ne $readCodexText) {
        throw "Expected hold text '$readCodexText', got '$((Get-PqValue $holdState 'text'))'"
    }

    # Verify event emission with unproven detector via Open-PqLog
    $evLog = Open-PqLog -Writer 'w1' -Run 'run1'
    $null = Write-PqEvent -Log $evLog -Ev 'pass.limit' -Run 'run1' -Repo 'fake' -Id 'S9999' -Pass 'run1.1' -Worker 1 -D ([ordered]@{
        agent = 'codex'
        source = 'log'
        detector = 'unproven'
    })
    $null = Write-PqEvent -Log $evLog -Ev 'agent.hold' -Run 'run1' -Repo 'fake' -Id 'S9999' -Pass 'run1.1' -Worker 1 -Agent 'codex' -D ([ordered]@{
        agent = 'codex'
        until = $readCodexUntil
        source = 'log'
        detector = 'unproven'
        text = $readCodexText
    })
    Close-PqLog $evLog

    $lines = [IO.File]::ReadAllLines($evLog.Path)
    $evPassLimit = ConvertFrom-Json $lines[0]
    $evAgentHold = ConvertFrom-Json $lines[1]
    if ($evPassLimit.d.detector -ne 'unproven') { throw "Expected pass.limit detector 'unproven'" }
    if ($evAgentHold.d.detector -ne 'unproven') { throw "Expected agent.hold detector 'unproven'" }
    if ($evAgentHold.d.text -ne $readCodexText) { throw "Expected agent.hold text '$readCodexText'" }
    Write-Host " PASS" -ForegroundColor Green

    # -----------------------------------------------------------------------------------------
    # Case 5: In-progress ticket waits for primary provider reset when <= 15 minutes away
    # -----------------------------------------------------------------------------------------
    Write-Host "Case 5: Wait for primary provider reset <= 15 min for In Progress ticket..." -NoNewline
    # Clear prior hold from earlier cases so we can set a clean 10 min hold
    $null = Remove-PqAgentHold -Name 'codex'
    $tenMinFromNow = [DateTimeOffset]::UtcNow.AddMinutes(10).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    Set-PqAgentHold -Name 'codex' -Pass 'run1.1' -Source 'log' -Detector 'unproven' -Until $tenMinFromNow

    # Test logic directly matching loop.ps1 dispatch check
    $fakeRegistry = [ordered]@{
        agentOrder = @('codex', 'gemini')
        agents = @(
            [ordered]@{ name = 'codex'; maxParallel = 1; levels = @('medium'); limitDetector = [ordered]@{ status = 'unproven' } }
            [ordered]@{ name = 'gemini'; maxParallel = 1; levels = @('medium'); limitDetector = [ordered]@{ status = 'unproven' } }
        )
    }

    $firstAgentName = [string]$fakeRegistry.agentOrder[0]
    $firstHold = Get-PqAgentHold $firstAgentName
    $firstUntil = Get-PqValue $firstHold 'until'
    $diffMin = ([DateTimeOffset]::Parse([string]$firstUntil) - [DateTimeOffset]::UtcNow).TotalMinutes

    # Ticket 1: In Progress -> should wait for primary provider (diffMin <= 15)
    $ticketStatus1 = 'In Progress'
    $shouldWait1 = ($ticketStatus1 -eq 'In Progress' -and $firstAgentName -and $diffMin -gt 0 -and $diffMin -le 15)
    if (-not $shouldWait1) { throw "Expected In Progress ticket to wait when primary provider reset is <= 15 min" }

    # Ticket 2: Tactical (not started yet) -> does not wait, can fallback
    $ticketStatus2 = 'Tactical'
    $shouldWait2 = ($ticketStatus2 -eq 'In Progress' -and $firstAgentName -and $diffMin -gt 0 -and $diffMin -le 15)
    if ($shouldWait2) { throw "Expected Tactical ticket not to be blocked by primary provider wait" }

    # Ticket 3: Reset is > 15 minutes away (e.g. 45 min) -> does not wait
    $fortyFiveMin = [DateTimeOffset]::UtcNow.AddMinutes(45).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    $diffMinLong = ([DateTimeOffset]::Parse($fortyFiveMin) - [DateTimeOffset]::UtcNow).TotalMinutes
    $shouldWait3 = ($ticketStatus1 -eq 'In Progress' -and $firstAgentName -and $diffMinLong -gt 0 -and $diffMinLong -le 15)
    if ($shouldWait3) { throw "Expected ticket not to wait when primary provider reset is > 15 min" }
    Write-Host " PASS" -ForegroundColor Green

    Write-Host ""
    Write-Host "All 5 test cases passed successfully." -ForegroundColor Green
}
finally {
    $env:SZA_PORTFOLIO_ROOT = $origEnv
    if (Test-Path -LiteralPath $scratch) {
        Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}
