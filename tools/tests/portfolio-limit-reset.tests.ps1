#requires -Version 7.0
# Tests for S0035: provider limit holds carry reset time, limit text privacy, detector status in events,
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
    # Case 1: Get-LimitSignal line detection, no text capture, hold file privacy
    # -----------------------------------------------------------------------------------------
    Write-Host "Case 1: Get-LimitSignal detection and hold file text privacy..." -NoNewline
    $longPrefix = "Prefix line `n"
    $matchLine = "You have reached your OpenAI Codex usage limit for today. Try again at 2:38 AM."
    $longSuffix = "`nFollowing output line"
    $logBody = $longPrefix + $matchLine + $longSuffix

    $sig = Get-LimitSignal -LogBody $logBody -ExitCode 1 -Pattern '(?i)usage limit|rate limit|quota'
    if ($null -eq $sig) { throw "Expected limit signal from log body, got null" }
    if ($sig.Source -ne 'log') { throw "Expected Source 'log', got '$($sig.Source)'" }
    if ($sig.Pattern -ne '(?i)usage limit|rate limit|quota') { throw "Expected Pattern preserved, got '$($sig.Pattern)'" }
    # Absence of matched text property in signal
    if ($sig.PSObject.Properties.Name -contains 'Text' -and $null -ne $sig.Text) {
        throw "Expected signal not to capture raw matched text, found '$($sig.Text)'"
    }

    # Write-LimitHold without Text
    $holdFile = Join-Path $scratch 'limit-hold.codex.json'
    $nowSec = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 1800
    $holdRes = Write-LimitHold -Path $holdFile -ResetsAt $nowSec -RateLimitType 'usage' -Instance 'pq1' -Ticket 'S0035'
    if (-not (Test-Path -LiteralPath $holdFile)) { throw "Expected hold file to exist: $holdFile" }

    # Verify raw JSON in hold file does not contain text property
    $rawHoldJson = [IO.File]::ReadAllText($holdFile) | ConvertFrom-Json
    if ($rawHoldJson.PSObject.Properties.Name -contains 'text') {
        throw "Expected hold file JSON to omit 'text' property, found '$($rawHoldJson.text)'"
    }

    # Read-LimitHold returns no Text
    $readHold = Read-LimitHold -Path $holdFile
    if ($readHold.PSObject.Properties.Name -contains 'Text' -and $null -ne $readHold.Text) {
        throw "Expected Read-LimitHold to omit Text property"
    }
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
    $fakeRepo = Join-Path $scratch 'fakeRepo'
    $runsDir = Join-Path $fakeRepo 'temp/spec-queue'
    $null = [IO.Directory]::CreateDirectory($runsDir)
    [IO.File]::WriteAllText((Join-Path $fakeRepo '.sza-profile.json'), '{"schema":1}', [Text.Encoding]::UTF8)

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

    # Fallback to $ticketId.log when per-agent log does not exist
    $fallbackTicket = "S8888"
    $fallbackLog = Join-Path $runsDir "$fallbackTicket.log"
    [IO.File]::WriteAllText($fallbackLog, $codexContent, [Text.Encoding]::UTF8)
    $readFallbackUntil = Get-PqLogLimitUntil -RepoPath $fakeRepo -TicketId $fallbackTicket -Record $codexRecord
    if ($null -eq $readFallbackUntil) { throw "Expected Get-PqLogLimitUntil to fall back to $fallbackTicket.log" }
    Write-Host " PASS" -ForegroundColor Green

    # -----------------------------------------------------------------------------------------
    # Case 4: Event detector from limitDetector.status & absence of hold text
    # -----------------------------------------------------------------------------------------
    Write-Host "Case 4: Event detector from limitDetector.status & hold text privacy..." -NoNewline
    # Set-PqAgentHold with unproven detector and reset timestamp
    Set-PqAgentHold -Name 'codex' -Pass 'run1.1' -Source 'log' -Detector 'unproven' -Until $readCodexUntil
    $holdState = Read-PqState (Get-PqPath -Kind hold -Agent 'codex')
    if ((Get-PqValue $holdState 'detector') -ne 'unproven') {
        throw "Expected hold detector 'unproven', got '$((Get-PqValue $holdState 'detector'))'"
    }
    if ($holdState.PSObject.Properties.Name -contains 'text') {
        throw "Expected hold state not to contain 'text' property, found '$($holdState.text)'"
    }

    # Verify event emission with unproven detector via Open-PqLog
    $evLog = Open-PqLog -Writer 'w1' -Run 'run1'
    $patternId = [string]$codexRecord.limitDetector.pattern
    $null = Write-PqEvent -Log $evLog -Ev 'pass.limit' -Run 'run1' -Repo 'fake' -Id 'S9999' -Pass 'run1.1' -Worker 1 -D ([ordered]@{
        agent = 'codex'
        source = 'log'
        detector = 'unproven'
        matched = $patternId
    })
    $null = Write-PqEvent -Log $evLog -Ev 'agent.hold' -Run 'run1' -Repo 'fake' -Id 'S9999' -Pass 'run1.1' -Worker 1 -Agent 'codex' -D ([ordered]@{
        agent = 'codex'
        until = $readCodexUntil
        source = 'log'
        detector = 'unproven'
    })
    Close-PqLog $evLog

    $lines = [IO.File]::ReadAllLines($evLog.Path)
    $evPassLimit = ConvertFrom-Json $lines[0]
    $evAgentHold = ConvertFrom-Json $lines[1]
    if ($evPassLimit.d.detector -ne 'unproven') { throw "Expected pass.limit detector 'unproven'" }
    if ($evPassLimit.d.matched -ne $patternId) { throw "Expected pass.limit matched '$patternId'" }
    if ($evPassLimit.d.PSObject.Properties.Name -contains 'text') { throw "Expected pass.limit to contain no 'text' field" }
    if ($evAgentHold.d.detector -ne 'unproven') { throw "Expected agent.hold detector 'unproven'" }
    if ($evAgentHold.d.PSObject.Properties.Name -contains 'text') { throw "Expected agent.hold to contain no 'text' field" }
    Write-Host " PASS" -ForegroundColor Green

    # -----------------------------------------------------------------------------------------
    # Case 5: Primary provider reset wait for In Progress ticket (both sides of 15 min threshold)
    # -----------------------------------------------------------------------------------------
    Write-Host "Case 5: Wait for primary provider reset <= 15 min for In Progress ticket..." -NoNewline
    $fakeRegistry = [ordered]@{
        agentOrder = @('codex', 'gemini')
        agents = @(
            [ordered]@{ name = 'codex'; maxParallel = 1; levels = @('medium'); limitDetector = [ordered]@{ status = 'unproven' } }
            [ordered]@{ name = 'gemini'; maxParallel = 1; levels = @('medium'); limitDetector = [ordered]@{ status = 'unproven' } }
        )
    }

    # 5a: <= 15 minutes away (e.g. 10 min) for 'In Progress' ticket -> WAITS
    $null = Remove-PqAgentHold -Name 'codex'
    $tenMinIso = [DateTimeOffset]::UtcNow.AddMinutes(10).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    Set-PqAgentHold -Name 'codex' -Pass 'run1.1' -Source 'log' -Detector 'unproven' -Until $tenMinIso

    $wait1 = Get-PqPrimaryResetWait -Registry $fakeRegistry -TicketStatus 'In Progress' -PickedAgent 'gemini'
    if ($null -eq $wait1) { throw "Expected In Progress ticket to wait when primary provider reset is 10 min away" }
    if ($wait1.Agent -ne 'codex') { throw "Expected wait agent 'codex', got '$($wait1.Agent)'" }
    if ($wait1.DiffMinutes -le 0 -or $wait1.DiffMinutes -gt 15) { throw "Expected diffMinutes within 0..15, got $($wait1.DiffMinutes)" }

    # 5b: > 15 minutes away (e.g. 20 min) for 'In Progress' ticket -> DOES NOT WAIT (allowed fallback)
    $null = Remove-PqAgentHold -Name 'codex'
    $twentyMinIso = [DateTimeOffset]::UtcNow.AddMinutes(20).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    Set-PqAgentHold -Name 'codex' -Pass 'run1.1' -Source 'log' -Detector 'unproven' -Until $twentyMinIso

    $wait2 = Get-PqPrimaryResetWait -Registry $fakeRegistry -TicketStatus 'In Progress' -PickedAgent 'gemini'
    if ($null -ne $wait2) { throw "Expected In Progress ticket NOT to wait when primary provider reset is > 15 min" }

    # 5c: Reset <= 15 min (10 min) but ticket is 'Tactical' (not In Progress) -> DOES NOT WAIT (allowed fallback)
    $null = Remove-PqAgentHold -Name 'codex'
    Set-PqAgentHold -Name 'codex' -Pass 'run1.1' -Source 'log' -Detector 'unproven' -Until $tenMinIso

    $wait3 = Get-PqPrimaryResetWait -Registry $fakeRegistry -TicketStatus 'Tactical' -PickedAgent 'gemini'
    if ($null -ne $wait3) { throw "Expected Tactical ticket NOT to wait for primary provider reset" }

    # 5d: Reset <= 15 min (10 min) but ticket is 'Approved' -> DOES NOT WAIT
    $wait4 = Get-PqPrimaryResetWait -Registry $fakeRegistry -TicketStatus 'Approved' -PickedAgent 'gemini'
    if ($null -ne $wait4) { throw "Expected Approved ticket NOT to wait for primary provider reset" }

    # 5e: Reset <= 15 min but picked agent IS the primary agent -> DOES NOT WAIT
    $wait5 = Get-PqPrimaryResetWait -Registry $fakeRegistry -TicketStatus 'In Progress' -PickedAgent 'codex'
    if ($null -ne $wait5) { throw "Expected no wait when picked agent is primary agent itself" }

    # 5f: Verify dispatch.skip event emission for limitResetNear
    $evLogWait = Open-PqLog -Writer 'w1' -Run 'run2'
    $null = Write-PqEvent -Log $evLogWait -Ev 'dispatch.skip' -Run 'run2' -Repo 'fake' -Id 'S9999' -Worker 1 -D ([ordered]@{
        why = 'limitResetNear'
        agent = $wait1.Agent
        until = $wait1.UntilIso
    })
    Close-PqLog $evLogWait
    $waitLines = [IO.File]::ReadAllLines($evLogWait.Path)
    $evSkip = ConvertFrom-Json $waitLines[-1]
    if ($evSkip.ev -ne 'dispatch.skip') { throw "Expected event 'dispatch.skip', got '$($evSkip.ev)'" }
    if ($evSkip.d.why -ne 'limitResetNear') { throw "Expected why 'limitResetNear'" }
    if ($evSkip.d.agent -ne 'codex') { throw "Expected agent 'codex'" }
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
