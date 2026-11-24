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

    # The dated form of a limit that lifts on another day - the real Codex line of 2026-11-17 (typographic apostrophe
    # kept): the clock-only pattern cannot match it, so the hold had no time and the provider was probed by real passes.
    $datedText = "ERROR: You$([char]0x2019)ve hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro), visit https://chatgpt.com/settings/usage to purchase more credits or try again at Nov 19th, 2026 11:35 PM."
    $datedIso = ConvertFrom-PqLimitText -Text $datedText -Offset "+01:00" -Now ([DateTimeOffset]::Parse("2026-11-17T12:00:00.000Z"))
    if ($datedIso -ne '2026-11-19T22:36:00.000Z') { throw "Expected 2026-11-19T22:36:00.000Z for the dated Codex form, got '$datedIso'" }
    $datedPast = ConvertFrom-PqLimitText -Text $datedText -Offset "+01:00" -Now ([DateTimeOffset]::Parse("2026-11-20T12:00:00.000Z"))
    if ($null -ne $datedPast) { throw "Expected null for a dated reset already past, got '$datedPast'" }
    $datedNow = [DateTimeOffset]::Parse("2026-11-17T12:00:00.000Z")
    $datedLong = ConvertFrom-PqLimitText -Text "Limit reached. Resets on November 19, 2026 at 9:05 am" -Offset "+00:00" -Now $datedNow
    if ($datedLong -ne '2026-11-19T09:06:00.000Z') { throw "Expected 2026-11-19T09:06:00.000Z for the long-month form, got '$datedLong'" }
    # A pass log quotes limit texts (this file among them): a dated text counts only as the last limit-shaped text of
    # the log and only within eight days, so a quoted fixture never outranks the real message that ends the log.
    $quotedThenReal = "tests.ps1:98: or try again at Nov 19th, 2026 11:35 PM.`nERROR: You've hit your usage limit. Try again at 2:38 PM."
    $realIso = ConvertFrom-PqLimitText -Text $quotedThenReal -Offset "+00:00" -Now $datedNow
    if ($realIso -ne '2026-11-17T14:39:00.000Z') { throw "Expected the clock form that ends the log (2026-11-17T14:39:00.000Z), got '$realIso'" }
    $farAway = ConvertFrom-PqLimitText -Text "try again at Nov 19th, 2027 11:35 PM." -Offset "+00:00" -Now $datedNow
    if ($null -ne $farAway) { throw "Expected null for a dated reset more than eight days ahead, got '$farAway'" }
    $sept = ConvertFrom-PqLimitText -Text "try again at Sept 19th, 2026 11:35 PM." -Offset "+00:00" -Now ([DateTimeOffset]::Parse("2026-09-17T12:00:00.000Z"))
    if ($sept -ne '2026-09-19T23:36:00.000Z') { throw "Expected 2026-09-19T23:36:00.000Z for a four-letter month, got '$sept'" }
    # The same holds inside the ISO and the clock forms: a quoted older line comes first and the real message ends the
    # log, so the LAST match counts. Taking the first read a quoted past time (null) and a quoted 2:38 AM (the next day).
    $isoTwice = "fixture.ps1:86: Your limit will reset at 2026-11-11 00:34:51`nUsage limit reached for 5 hour. Your limit will reset at 2026-11-17 18:00:00"
    $isoLast = ConvertFrom-PqLimitText -Text $isoTwice -Offset "+00:00" -Now $datedNow
    if ($isoLast -ne '2026-11-17T18:01:00.000Z') { throw "Expected the ISO time that ends the log (2026-11-17T18:01:00.000Z), got '$isoLast'" }
    $clockTwice = "tests.ps1:68: Try again at 2:38 AM.`nERROR: You've hit your usage limit. Try again at 11:35 PM."
    $clockLast = ConvertFrom-PqLimitText -Text $clockTwice -Offset "+00:00" -Now $datedNow
    if ($clockLast -ne '2026-11-17T23:36:00.000Z') { throw "Expected the clock time that ends the log (2026-11-17T23:36:00.000Z), got '$clockLast'" }
    # The one reading of a provider's UTC offset the three forms share.
    $zonePlus = ConvertTo-PqLimitZone '+08:00'
    $zoneMinus = ConvertTo-PqLimitZone ' -05:30 '
    if ($zonePlus -ne [timespan]::new(8, 0, 0) -or $zoneMinus -ne [timespan]::new(-5, -30, 0)) { throw "Expected +08:00 and -05:30 as timespans, got '$zonePlus' and '$zoneMinus'" }
    if ($null -ne (ConvertTo-PqLimitZone '') -or $null -ne (ConvertTo-PqLimitZone 'Europe/Kyiv')) { throw "Expected `$null for an empty or unreadable offset" }
    # The span form, exact values: agy's quota error, and the Antigravity usage line with days and hours set apart by a comma.
    $spanCases = @(
        @{ Text = 'Individual quota reached. Resets in 57h10m24s.'; Want = '2026-11-19T21:11:24.000Z' }
        @{ Text = 'Individual quota reached. Resets in 2h30m.'; Want = '2026-11-17T14:31:00.000Z' }
        @{ Text = 'You have used some of your weekly limit, it will fully refresh in 4 days, 6 hours.'; Want = '2026-11-21T18:01:00.000Z' }
        @{ Text = 'It will refresh in 1 day and 2 hours'; Want = '2026-11-18T14:01:00.000Z' }
        @{ Text = 'Your limit refreshes in 45 minutes.'; Want = '2026-11-17T12:46:00.000Z' }
        # A quoted older text comes first and the real message ends the log; a text with no number is no span.
        @{ Text = "tests.ps1:99: it will fully refresh in 4 days, 6 hours.`nIndividual quota reached. Resets in 2h30m."; Want = '2026-11-17T14:31:00.000Z' }
        @{ Text = "the cache resets in the morning`nIndividual quota reached. Resets in 2h30m."; Want = '2026-11-17T14:31:00.000Z' }
        @{ Text = "or try again at Nov 19th, 2026 11:35 PM.`nit will fully refresh in 4 days, 6 hours."; Want = '2026-11-21T18:01:00.000Z' }
        @{ Text = 'it will refresh in the morning'; Want = $null }
    )
    foreach ($c in $spanCases) {
        $got = ConvertFrom-PqLimitText -Text $c.Text -Offset '+00:00' -Now $datedNow
        if ($got -ne $c.Want) { throw "Span form: expected '$($c.Want)' for '$($c.Text)', got '$got'" }
    }
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

    # Case 6: Get-PqCarriedDrops - the drops a worker restarted for a code change inherits (S0105)
    Write-Host "Case 6: Get-PqCarriedDrops walks the chain of code-change restarts..." -NoNewline
    $carryLog = Join-Path $scratch 'carry-log'
    $null = [IO.Directory]::CreateDirectory($carryLog)
    $carryLine = {
        param([string]$Run, [string]$Ev, [string]$Id, $D)
        ConvertTo-Json -Compress -InputObject ([ordered]@{ v = 1; ts = '2026-11-18T10:00:00.000Z'; seq = 1; wr = 'w7'; run = $Run; ev = $Ev; repo = $(if ($Id) { 'demo' } else { $null }); id = $(if ($Id) { $Id } else { $null }); pass = $null; worker = 7; agent = $null; model = $null; cx = $null; d = $D })
    }
    $markA = [ordered]@{ statusAt = 'In Progress'; updatedAt = '2026-11-17 10:00'; specMtime = '2026-11-17T09:00:00.0000000Z'; after = 1 }
    $markB = [ordered]@{ statusAt = 'Draft'; updatedAt = '2026-11-18 08:00'; specMtime = ''; after = 1 }
    $noMark = [ordered]@{ statusAt = $null; updatedAt = $null; specMtime = $null; after = 1 }
    $day1 = @(
        (& $carryLine 'R0' 'run.start' '' ([ordered]@{ pid = 1 })), (& $carryLine 'R0' 'ticket.dropped' 'S0009' $markB), (& $carryLine 'R0' 'run.end' '' ([ordered]@{ exit = 0 })),
        (& $carryLine 'RA' 'run.start' '' ([ordered]@{ pid = 2 })), (& $carryLine 'RA' 'ticket.dropped' 'S0001' $markA), (& $carryLine 'RA' 'ticket.dropped' 'S0002' $markB),
        (& $carryLine 'RA' 'ticket.dropped' 'S0004' $noMark), (& $carryLine 'RA' 'run.codeChanged' '' ([ordered]@{ action = 'restart' })),
        (& $carryLine 'RA' 'run.end' '' ([ordered]@{ exit = 75 })), (& $carryLine 'RA' 'poll.summary' '' ([ordered]@{ polls = 1 })))
    $day2 = @(
        (& $carryLine 'RB' 'run.start' '' ([ordered]@{ pid = 3 })), (& $carryLine 'RB' 'ticket.dropLifted' 'S0002' ([ordered]@{ changed = 'status' })),
        (& $carryLine 'RB' 'ticket.dropped' 'S0003' $markB), (& $carryLine 'RB' 'run.end' '' ([ordered]@{ exit = 75 })),
        (& $carryLine 'RB' 'poll.summary' '' ([ordered]@{ polls = 1 })), (& $carryLine 'RC' 'run.start' '' ([ordered]@{ pid = 4 })))
    [IO.File]::WriteAllText((Join-Path $carryLog 'events-2026-11-17.w7.jsonl'), (($day1 -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $carryLog 'events-2026-11-18.w7.jsonl'), (($day2 -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    $carried = Get-PqCarriedDrops -LogDir $carryLog -Writer 'w7' -SkipRun 'RC'
    $carriedKeys = @($carried.Keys | Sort-Object) -join ','
    if ($carriedKeys -ne 'demo:S0001,demo:S0003') { throw "Expected demo:S0001,demo:S0003 carried (S0002 lifted, S0004 no mark, S0009 before the chain), got '$carriedKeys'" }
    $m1 = $carried['demo:S0001'].mark
    if ($m1.specMtime -isnot [string] -or $m1.specMtime -cne '2026-11-17T09:00:00.0000000Z') { throw "Expected specMtime kept as the event's string, got '$($m1.specMtime)'" }
    if ($null -ne (Get-PqDropChange $m1 ([ordered]@{ status = 'In Progress'; updated = '2026-11-17 10:00'; specMtime = '2026-11-17T09:00:00.0000000Z'; specFile = '' }))) { throw 'Expected an unchanged ticket to stay dropped' }
    if ((Get-PqDropChange $m1 ([ordered]@{ status = 'Broken'; updated = '2026-11-17 10:00'; specMtime = '2026-11-17T09:00:00.0000000Z'; specFile = '' })) -cne 'status') { throw 'Expected a status change to lift the carried drop' }
    if ((Get-PqCarriedDrops -LogDir $carryLog -Writer 'w7').Count -ne 0) { throw 'Expected nothing carried when the newest run has not ended with the restart code' }
    if ((Get-PqCarriedDrops -LogDir $carryLog -Writer 'w8').Count -ne 0) { throw 'Expected nothing carried from another writer' }
    Write-Host " PASS" -ForegroundColor Green

    # Case 7: the robot-filed cap is counted from the ledger rows of one local day (TASK-FLOW rule 41, robotDraftCap)
    Write-Host "Case 7: robot-filed cap counted from the ledger rows of one day..." -NoNewline
    $capRepo = Join-Path $scratch 'capRepo'
    $null = [IO.Directory]::CreateDirectory((Join-Path $capRepo 'PLAN'))
    [IO.File]::WriteAllText((Join-Path $capRepo '.sza-profile.json'), '{}', [Text.UTF8Encoding]::new($false))
    $capRow = {
        param([string]$Id, [string]$Source, [string]$Created = '2026-11-18', [string]$Status = 'Draft')
        $o = [ordered]@{ id = $Id; name = "t-$Id".ToLowerInvariant(); status = $Status; priority = 50; file = "PLAN/${Id}_t.md"; created = $Created; updated = "$Created 10:00" }
        if ($Source) { $o.source = $Source }
        ($o | ConvertTo-Json -Compress)
    }
    $capRows = @(
        (& $capRow 'S0001' 'owner'), (& $capRow 'S0002' 'robot'), (& $capRow 'S0003' ''),
        (& $capRow 'S0004' 'robot' '2026-11-17'), (& $capRow 'S0005' 'robot'),
        (& $capRow 'S0006' 'robot' '2026-11-18' 'Approved'), (& $capRow 'S0007' 'robot'), (& $capRow 'S0008' 'inbox')
    )
    [IO.File]::WriteAllText((Join-Path $capRepo 'PLAN/spec-catalog.jsonl'), (($capRows -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $capRepo 'PLAN/spec-catalog-archive.jsonl'), ((& $capRow 'S0000' 'robot' '2026-11-18' 'Verified') + "`n"), [Text.UTF8Encoding]::new($false))
    # 6a: only source robot rows of the day count, ids in ordinal order, the archive included; past the cap only a Draft is held.
    $cap2 = Get-PqRobotFiled -RepoPath $capRepo -Day '2026-11-18' -Cap 2
    if (($cap2.counted -join ',') -cne 'S0000,S0002,S0005,S0006,S0007') { throw "Expected counted S0000,S0002,S0005,S0006,S0007, got '$($cap2.counted -join ',')'" }
    if (($cap2.capped -join ',') -cne 'S0005,S0007') { throw "Expected capped S0005,S0007 at cap 2, got '$($cap2.capped -join ',')'" }
    # 6b: under the cap nothing is held, a cap of 0 holds every robot-filed Draft of the day, another day counts nothing.
    if (@((Get-PqRobotFiled -RepoPath $capRepo -Day '2026-11-18' -Cap 20).capped).Count -ne 0) { throw "Expected nothing held at cap 20" }
    $cap0 = Get-PqRobotFiled -RepoPath $capRepo -Day '2026-11-18' -Cap 0
    if (($cap0.capped -join ',') -cne 'S0002,S0005,S0007') { throw "Expected capped S0002,S0005,S0007 at cap 0, got '$($cap0.capped -join ',')'" }
    if (@((Get-PqRobotFiled -RepoPath $capRepo -Day '2026-11-19' -Cap 0).counted).Count -ne 0) { throw "Expected the next day to count nothing" }
    # 6c: the rank's exclude list - 'key:id' over the enabled repositories, nothing remembered between calls.
    $capRegistry = [ordered]@{ robotDraftCap = 2; repos = @([pscustomobject]@{ key = 'demo'; path = $capRepo; enabled = $true }, [pscustomobject]@{ key = 'off'; path = $capRepo; enabled = $false }, [pscustomobject]@{ key = 'gone'; path = (Join-Path $scratch 'no-such-repo'); enabled = $true }) }
    $heldKeys = @(Get-PqIntakeCapped $capRegistry '2026-11-18')
    if (($heldKeys -join ',') -cne 'demo:S0005,demo:S0007') { throw "Expected demo:S0005,demo:S0007, got '$($heldKeys -join ',')'" }
    if (@(Get-PqIntakeCapped $capRegistry '2026-11-19').Count -ne 0) { throw "Expected no held ticket on the next day" }
    $capRegistry.Remove('robotDraftCap')
    if (@(Get-PqIntakeCapped $capRegistry '2026-11-18').Count -ne 0) { throw "Expected the default cap of 20 to hold nothing here" }
    if ((Get-PqLocalDay ([datetime]'2026-11-18T23:59:00')) -cne '2026-11-18') { throw "Expected Get-PqLocalDay to give the local date" }
    # 6d: the loop keeps no count of its own, and every rank excludes the held tickets.
    $loopSrc = [IO.File]::ReadAllText((Join-Path $pqLib 'loop.ps1'))
    if ($loopSrc.Contains('$robotDrafts')) { throw 'loop.ps1 still keeps the robot-filed count in process memory' }
    if (-not $loopSrc.Contains('if (-not $NamedTicket) { $Exclude = [string[]]@(@($Exclude) + @(Get-PqIntakeCapped $Registry)) }')) { throw 'Get-PqNextRank does not exclude the robot-filed tickets past the cap' }
    Write-Host " PASS" -ForegroundColor Green

    # -----------------------------------------------------------------------------------------
    # Case 8: a workspace's spend limit (HTTP 400, error `unknown`) is a limit through the provider's pattern, and is timed
    # -----------------------------------------------------------------------------------------
    Write-Host "Case 8: workspace spend limit read from the transcript record and timed from its text..." -NoNewline
    $spendPattern = '(?i)credit balance (is )?too low|insufficient (credit|balance)|reached your specified workspace API usage limits?'
    $regainDay = [DateTimeOffset]::UtcNow.AddDays(3).ToString('yyyy-MM-dd')
    $spendText = "API Error: 400 You have reached your specified workspace API usage limits. You will regain access on $regainDay at 00:00 UTC."
    $makeRecord = {
        param([string]$Text, [bool]$IsApiError)
        (ConvertTo-Json -Compress -Depth 6 ([ordered]@{
            parentUuid = 'p1'; isSidechain = $false; type = 'assistant'; uuid = 'u1'
            message = [ordered]@{ role = 'assistant'; model = '<synthetic>'; content = @([ordered]@{ type = 'text'; text = $Text }) }
            error = 'unknown'; isApiErrorMessage = $IsApiError; apiErrorStatus = 400 }))
    }
    $writeTranscript = {
        param([string]$Name, [string]$Record)
        $p = Join-Path $scratch $Name
        [IO.File]::WriteAllText($p, ((@('{"type":"user","message":{"role":"user","content":"hi"}}', $Record, '{"type":"last-prompt","lastPrompt":"hi"}')) -join "`n") + "`n")
        $p
    }
    $spendFile = & $writeTranscript 'spend.jsonl' (& $makeRecord $spendText $true)
    $sigSpend = Get-LimitSignal -TranscriptPath $spendFile -ExitCode 1 -Pattern $spendPattern
    if ($null -eq $sigSpend) { throw 'Expected the spend-limit record to be a limit with the provider pattern, got null' }
    if ($sigSpend.Source -ne 'transcript') { throw "Expected Source 'transcript', got '$($sigSpend.Source)'" }
    $expectUnix = [DateTimeOffset]::Parse("${regainDay}T00:00:00Z").ToUnixTimeSeconds()
    if ($sigSpend.ResetsAt -ne $expectUnix) { throw "Expected ResetsAt $expectUnix from the text, got '$($sigSpend.ResetsAt)'" }
    # Without the pattern the same record is no limit (claude's own prose decides there), and a record that is not an API error
    # message - the model writing ABOUT the limit - is none either.
    if ($null -ne (Get-LimitSignal -TranscriptPath $spendFile -ExitCode 1)) { throw 'Expected no limit for the record without a provider pattern' }
    $aboutFile = & $writeTranscript 'about.jsonl' (& $makeRecord $spendText $false)
    if ($null -ne (Get-LimitSignal -TranscriptPath $aboutFile -ExitCode 0 -Pattern $spendPattern)) { throw 'Expected no limit for a record that is not an API error message' }
    # The time forms: the clock time in UTC, a time already past, and the pq side's reader of a pass log.
    if ($null -ne (ConvertFrom-LimitAbsoluteText 'You will regain access on 2020-01-01 at 00:00 UTC.')) { throw 'Expected a past clock time to give no reset' }
    $pqIso = ConvertFrom-PqLimitText -Text $spendText -Now ([DateTimeOffset]::UtcNow)
    if ($null -eq $pqIso) { throw 'Expected ConvertFrom-PqLimitText to read the regain-access time' }
    $pqAt = [DateTimeOffset]::Parse($pqIso)
    $expectAt = [DateTimeOffset]::Parse("${regainDay}T00:01:00Z")
    if ($pqAt -ne $expectAt) { throw "Expected $($expectAt.ToString('o')) (the time + the minute's margin), got $($pqAt.ToString('o'))" }
    Write-Host " PASS" -ForegroundColor Green

    Write-Host ""
    Write-Host "All 8 test cases passed successfully." -ForegroundColor Green
}
finally {
    $env:SZA_PORTFOLIO_ROOT = $origEnv
    if (Test-Path -LiteralPath $scratch) {
        Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}
