#requires -Version 7.0
<# Fast cases of the limit detector, the reset provenance of a hold and the fallback written on change (CANONR-0206,
TASK-FLOW 0.50). Exit 0 on success, 1 on a failed assertion.

Cases:
  1. Get-LimitSignal, fixture logs: limit text inside ticket content with exit 0, a match outside the last 40 lines, a
     real limit in the last 40 lines with exit 1, and the two edges of the tail and of the exit code
  2. Resolve-RunOutcome: a pass that moved the ticket is never a limit hit
  3. ConvertFrom-PqLimitTextSource and Get-PqLogLimitReset: a parsed reset is log, a clock time without a day is guessed,
     and a time outside the last 40 lines is not read
  4. Set-PqAgentHold: a guessed hold is cut to six hours, a parsed one is not, and a hold written before 0.50 reads by its until
  5. Set-PqAgentHoldFromPass and Remove-PqAgentHoldAfterPass: one agent.fallback when a hold starts and one when it ends
  6. Get-PqRankingFallbacks: a ranking records no pass-over for a limit, and the loop holds through the two functions
  7. Get-PqFindings: PQ-LIMIT01 flags a guessed hold longer than six hours only
Touches: batch/_limit-hold.ps1 (with _limit-tail.ps1), Resolve-RunOutcome of batch/run-spec-queue.ps1 (read through the parser; the runner is not
run), portfolio/lib/agents.ps1 and analysis.ps1, and a throwaway portfolio root under the system temp directory
(SZA_PORTFOLIO_ROOT for the duration of the script), removed at the end. Writes nothing else. #>
$ErrorActionPreference = 'Stop'
$harness = Join-Path (Split-Path $PSScriptRoot -Parent) 'harness'
$pqLib = Join-Path $harness 'portfolio/lib'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('limit-detector-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($scratch)
$priorRoot = $env:SZA_PORTFOLIO_ROOT
$env:SZA_PORTFOLIO_ROOT = $scratch

. (Join-Path $harness 'batch/_limit-hold.ps1')
. (Join-Path $pqLib 'paths.ps1')
. (Join-Path $pqLib 'events.ps1')
. (Join-Path $pqLib 'registry.ps1')
. (Join-Path $pqLib 'loop.ps1')
. (Join-Path $pqLib 'ledger-watch.ps1')
. (Join-Path $pqLib 'agents.ps1')
. (Join-Path $pqLib 'analysis.ps1')

$script:failed = 0
$script:passed = 0
$log = $null
function Assert-Equal($Actual, $Expected, [string] $Case) {
    if ("$Actual" -cne "$Expected") { $script:failed++; Write-Host "FAIL $Case - expected [$Expected], got [$Actual]" -ForegroundColor Red }
    else { $script:passed++; Write-Host "PASS $Case" }
}
$iso = 'yyyy-MM-ddTHH:mm:ss.fffZ'

try {
    # -----------------------------------------------------------------------------------------
    # Case 1: the detector - fixture logs
    # -----------------------------------------------------------------------------------------
    $pattern = '(?i)usage limit|rate limit'
    $ticketText = "## Finding`n- Root cause: the limit text is searched in the whole pass log, and 'rate limit' appears in tickets.`n- Repeated rankings then obscure when the hold began.`n"
    $work = (1..60 | ForEach-Object { "tool output line $_" }) -join "`n"
    $limitLine = "ERROR: You've hit your usage limit. Upgrade to Pro, or try again at 6:06 AM."

    # Limit text inside ticket content, the provider exits 0.
    $exit0 = Get-LimitSignal -LogBody ($ticketText + "final answer: the detector is narrowed.`n") -ExitCode 0 -Pattern $pattern
    Assert-Equal ($null -eq $exit0) $true 'detector: limit text inside ticket content and exit 0 is no limit'
    # The same text, the provider exits 1, and the text lies outside the last 40 lines.
    $outOfTail = Get-LimitSignal -LogBody ($ticketText + $work + "`nfinal answer: the pass ends in an error.`n") -ExitCode 1 -Pattern $pattern
    Assert-Equal ($null -eq $outOfTail) $true 'detector: a match outside the last 40 lines is no limit'
    # A real limit in the last lines, exit 1.
    $real = Get-LimitSignal -LogBody ($ticketText + $work + "`n$limitLine`ntokens used`n23,284`n") -ExitCode 1 -Pattern $pattern
    Assert-Equal ($null -eq $real) $false 'detector: a real limit in the last 40 lines with exit 1 is a limit'
    Assert-Equal $real.Source 'log' 'detector: the signal names the log as its source'
    Assert-Equal $real.Pattern $pattern 'detector: the signal carries the pattern, not the text'
    # The same real limit, exit 0, and the exit code not read.
    $realExit0 = Get-LimitSignal -LogBody "$limitLine`n" -ExitCode 0 -Pattern $pattern
    Assert-Equal ($null -eq $realExit0) $true 'detector: the real line with exit 0 is no limit'
    $noExit = Get-LimitSignal -LogBody "$limitLine`n" -Pattern $pattern
    Assert-Equal ($null -eq $noExit) $true 'detector: the real line with no exit code read is no limit'
    # The edge of the tail: the 40th line from the end counts, the 41st does not.
    $after39 = (1..39 | ForEach-Object { "line $_" }) -join "`n"
    $after40 = (1..40 | ForEach-Object { "line $_" }) -join "`n"
    $edgeIn = Get-LimitSignal -LogBody "$limitLine`n$after39" -ExitCode 1 -Pattern $pattern
    Assert-Equal ($null -eq $edgeIn) $false 'detector: the 40th line from the end is inside the tail'
    $edgeOut = Get-LimitSignal -LogBody "$limitLine`n$after40" -ExitCode 1 -Pattern $pattern
    Assert-Equal ($null -eq $edgeOut) $true 'detector: the 41st line from the end is outside the tail'
    $trailing = Get-LimitSignal -LogBody "$limitLine`n$after39`n" -ExitCode 1 -Pattern $pattern
    Assert-Equal ($null -eq $trailing) $false 'detector: a newline that ends the log is not a line of the tail'

    # -----------------------------------------------------------------------------------------
    # Case 2: Resolve-RunOutcome - a pass that moved the ticket is never a limit hit
    # -----------------------------------------------------------------------------------------
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $harness 'batch/run-spec-queue.ps1'), [ref]$tokens, [ref]$errors)
    Assert-Equal $errors.Count 0 'runner parses'
    $resolve = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Resolve-RunOutcome' }, $false)
    . ([scriptblock]::Create($resolve.Extent.Text))
    $quiet = @{ Outcome = 'ok'; ExitCode = 1; StatusBefore = 'Draft'; StatusAfter = 'Draft'; ElapsedSeconds = 30 }
    $v = Resolve-RunOutcome @quiet -LimitHit
    Assert-Equal "$($v.Outcome)/$($v.Moved)" 'limit-hit/False' 'outcome: a limit on a pass that moved nothing is limit-hit'
    $v = Resolve-RunOutcome @quiet -StatusAfter 'In Progress' -LimitHit
    Assert-Equal "$($v.Outcome)/$($v.Moved)" 'child-failed/True' 'outcome: a limit on a pass that moved the ticket and exited 1 is child-failed'
    $v = Resolve-RunOutcome @quiet -StatusAfter 'In Progress' -ExitCode 0 -LimitHit
    Assert-Equal "$($v.Outcome)/$($v.Moved)" 'ok/True' 'outcome: a limit on a pass that moved the ticket and exited 0 is ok'
    $v = Resolve-RunOutcome @quiet -StatusAfter 'In Progress' -Outcome 'context-handoff' -LimitHit
    Assert-Equal $v.Outcome 'context-handoff' 'outcome: a handoff that moved the ticket stays a handoff'
    $v = Resolve-RunOutcome @quiet -StatusAfter '' -LimitHit
    Assert-Equal "$($v.Outcome)/$($v.Moved)" 'limit-hit/False' 'outcome: an unreadable status after the pass is no move'
    $v = Resolve-RunOutcome @quiet -LimitHit -ProviderErrorHit
    Assert-Equal $v.Outcome 'limit-hit' 'outcome: the limit still comes before a provider outage'
    $v = Resolve-RunOutcome @quiet
    Assert-Equal $v.Outcome 'child-failed' 'outcome: without a limit the exit code decides, as before'

    # -----------------------------------------------------------------------------------------
    # Case 3: where the reset time came from
    # -----------------------------------------------------------------------------------------
    $now = [DateTimeOffset]::Parse('2026-11-25T12:00:00.000Z')
    $span = ConvertFrom-PqLimitTextSource -Text 'Individual quota reached. Resets in 57h10m24s.' -Now $now
    Assert-Equal $span.source 'log' 'reset: a span the message names is read from the log'
    Assert-Equal ([DateTimeOffset]::Parse($span.at) - $now.AddSeconds(60)).TotalSeconds 205824 'reset: the span is counted from now'
    $utc = ConvertFrom-PqLimitTextSource -Text 'API Error: 400 You have reached your specified workspace API usage limits. You will regain access on 2026-12-01 at 00:00 UTC.' -Now $now
    Assert-Equal $utc.source 'log' 'reset: a clock time in UTC with its day is read from the log'
    $isoRead = ConvertFrom-PqLimitTextSource -Text 'Usage limit reached for 5 hour. Your limit will reset at 2026-11-25 22:08:40' -Offset '+08:00' -Now $now
    Assert-Equal $isoRead.source 'log' 'reset: a day with a clock time is read from the log'
    $dated = ConvertFrom-PqLimitTextSource -Text 'try again at Nov 27th, 2026 11:35 PM.' -Offset '+00:00' -Now $now
    Assert-Equal $dated.source 'log' 'reset: a dated clock time is read from the log'
    $clock = ConvertFrom-PqLimitTextSource -Text "You've hit your usage limit. Try again at 2:38 AM." -Now $now
    Assert-Equal $clock.source 'guessed' 'reset: a clock time without a day is guessed'
    Assert-Equal ([DateTimeOffset]::Parse($clock.at).ToString('yyyy-MM-dd')) '2026-11-26' 'reset: the guessed day is the next one the clock time names'
    Assert-Equal (ConvertFrom-PqLimitText -Text 'Try again at 2:38 AM.' -Now $now) $clock.at 'reset: the time alone is the same reading'
    Assert-Equal ($null -eq (ConvertFrom-PqLimitTextSource -Text 'RESOURCE_EXHAUSTED (code 429)' -Now $now)) $true 'reset: a message that names no time reads as none'

    # The same reading of a pass's own log.
    $fakeRepo = Join-Path $scratch 'fakeRepo'
    $runsDir = Join-Path $fakeRepo 'temp/spec-queue'
    $null = [IO.Directory]::CreateDirectory($runsDir)
    [IO.File]::WriteAllText((Join-Path $fakeRepo '.sza-profile.json'), '{"schema":1}', [Text.UTF8Encoding]::new($false))
    $codex = [ordered]@{ name = 'codex'; limitDetector = [ordered]@{ pattern = $pattern; status = 'unproven' } }
    [IO.File]::WriteAllText((Join-Path $runsDir 'T0001.codex.log'), "work`nERROR: You've hit your usage limit. Try again at 6:06 AM.`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $runsDir 'T0002.codex.log'), "work`nAGY_ERROR: Individual quota reached. Resets in 57h10m24s.`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $runsDir 'T0003.codex.log'), "work`nAGY_ERROR: RESOURCE_EXHAUSTED (code 429).`n", [Text.UTF8Encoding]::new($false))
    $r = Get-PqLogLimitReset -RepoPath $fakeRepo -TicketId 'T0001' -Record $codex
    Assert-Equal "$([string](Get-PqValue $r 'resetSource'))/$($null -ne (Get-PqValue $r 'until'))" 'guessed/True' 'log reset: a clock time without a day is guessed'
    $r = Get-PqLogLimitReset -RepoPath $fakeRepo -TicketId 'T0002' -Record $codex
    Assert-Equal (Get-PqValue $r 'resetSource') 'log' 'log reset: a span is read from the log'
    Assert-Equal ($null -ne (Get-PqLogLimitUntil -RepoPath $fakeRepo -TicketId 'T0002' -Record $codex)) $true 'log reset: the time alone is still read'
    Assert-Equal ($null -eq (Get-PqLogLimitReset -RepoPath $fakeRepo -TicketId 'T0003' -Record $codex)) $true 'log reset: a message without a time reads as none'
    # A time quoted before the last 40 lines belongs to what the child read, not to the provider's message.
    [IO.File]::WriteAllText((Join-Path $runsDir 'T0004.codex.log'), "quoted: Resets in 57h10m24s.`n$work`nAGY_ERROR: RESOURCE_EXHAUSTED (code 429).`n", [Text.UTF8Encoding]::new($false))
    Assert-Equal ($null -eq (Get-PqLogLimitReset -RepoPath $fakeRepo -TicketId 'T0004' -Record $codex)) $true 'log reset: a time outside the last 40 lines is not read'

    # -----------------------------------------------------------------------------------------
    # Case 4: Set-PqAgentHold - the cap of a guessed hold, and holds written before 0.50
    # -----------------------------------------------------------------------------------------
    $utcNow = [DateTimeOffset]::UtcNow
    $week = $utcNow.AddDays(5).ToString($iso)
    $written = Set-PqAgentHold -Name 'codex' -Pass 'run1.1' -Source 'log' -Detector 'unproven' -Until $week -ResetSource 'guessed' -PassThru
    Assert-Equal "$($written.started)/$($written.resetSource)" 'True/guessed' 'hold: the first hold of an agent starts here and says guessed'
    $hold = Get-PqAgentHold 'codex'
    $run = ([DateTimeOffset]::Parse([string](Get-PqValue $hold 'until')) - [DateTimeOffset]::Parse([string](Get-PqValue $hold 'writtenAt'))).TotalSeconds
    Assert-Equal ([Math]::Abs($run - 6 * 3600) -lt 5) $true "hold: a guessed time five days out is cut to six hours (ran $run s)"
    Assert-Equal (Test-PqAgentHeld $hold $null) $true 'hold: the cut hold still holds'
    $short = $utcNow.AddHours(2).ToString($iso)
    $null = Remove-PqAgentHold 'codex'
    $null = Set-PqAgentHold -Name 'codex' -Pass 'run1.2' -Source 'log' -Detector 'unproven' -Until $short -ResetSource 'guessed'
    $hold = Get-PqAgentHold 'codex'
    Assert-Equal "$(Get-PqValue $hold 'until')/$(Get-PqValue $hold 'resetSource')" "$short/guessed" 'hold: a guessed time inside six hours is written as it is'
    $null = Remove-PqAgentHold 'codex'
    $null = Set-PqAgentHold -Name 'codex' -Pass 'run1.3' -Source 'log' -Detector 'unproven' -Until $week -ResetSource 'log'
    $hold = Get-PqAgentHold 'codex'
    Assert-Equal "$(Get-PqValue $hold 'until')/$(Get-PqValue $hold 'resetSource')" "$week/log" 'hold: a time read from the log is not cut'
    $null = Remove-PqAgentHold 'codex'
    # A caller from before 0.50 names no source: its timestamp is a time read from the log and is not cut.
    $null = Set-PqAgentHold -Name 'codex' -Pass 'run1.3' -Source 'log' -Detector 'unproven' -Until $week
    $hold = Get-PqAgentHold 'codex'
    Assert-Equal "$(Get-PqValue $hold 'until')/$(Get-PqValue $hold 'resetSource')" "$week/log" 'hold: a write without -ResetSource keeps a timestamp as it is, read as log'
    # A guessed write under a logged hold that lies further ahead keeps that time and its source.
    $again = Set-PqAgentHold -Name 'codex' -Pass 'run1.4' -Source 'log' -Detector 'unproven' -Until $short -ResetSource 'guessed' -PassThru
    Assert-Equal "$($again.until)/$($again.resetSource)/$($again.started)" "$week/log/False" 'hold: until only moves forward, with the source of the time in force'
    # A poll hold names no time: guessed, and it holds for its poll minutes.
    $null = Remove-PqAgentHold 'codex'
    $poll = Set-PqAgentHold -Name 'codex' -Pass 'run1.5' -Source 'log' -Detector 'unproven' -ResetSource 'guessed' -PassThru
    Assert-Equal "$($null -eq $poll.until)/$($poll.resetSource)" 'True/guessed' 'hold: a hold without a time is guessed'
    # A hold written before 0.50 carries no resetSource: it reads by its until.
    $holdsDir = Join-Path $scratch 'holds'
    $null = [IO.Directory]::CreateDirectory($holdsDir)
    [IO.File]::WriteAllText((Join-Path $holdsDir 'zai.json'), (@{ agent = 'zai'; until = $week; source = 'log'; detector = 'proven'; writtenAt = $utcNow.ToString($iso); pass = 'old.1' } | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
    Assert-Equal (Get-PqHoldResetSource (Get-PqAgentHold 'zai')) 'log' 'old hold: a timestamp without the key reads as log'
    [IO.File]::WriteAllText((Join-Path $holdsDir 'zai.json'), (@{ agent = 'zai'; until = $null; source = 'log'; detector = 'unproven'; writtenAt = $utcNow.ToString($iso); pass = 'old.2' } | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
    Assert-Equal (Get-PqHoldResetSource (Get-PqAgentHold 'zai')) 'guessed' 'old hold: no timestamp without the key reads as guessed'

    # -----------------------------------------------------------------------------------------
    # Case 5: one agent.fallback when a hold starts, one when it ends
    # -----------------------------------------------------------------------------------------
    $null = Remove-PqAgentHold 'codex'
    $null = Remove-PqAgentHold 'zai'
    $log = Open-PqLog -Writer 'w1' -Run 'run1'
    $first = Set-PqAgentHoldFromPass -Log $log -Name 'codex' -Pass 'run1.10' -Detector 'unproven' -Until $short -ResetSource 'log' -Run 'run1' -Repo 'fake' -Id 'T0010' -Worker 1
    Assert-Equal $first.started $true 'events: the first hold of an agent starts here'
    $null = Set-PqAgentHoldFromPass -Log $log -Name 'codex' -Pass 'run1.11' -Detector 'unproven' -Until $short -ResetSource 'log' -Run 'run1' -Repo 'fake' -Id 'T0011' -Worker 1
    Assert-Equal (Remove-PqAgentHoldAfterPass -Log $log -Name 'codex' -Run 'run1' -Repo 'fake' -Id 'T0012' -Pass 'run1.12' -Worker 1) $true 'events: a finished pass clears the hold'
    Assert-Equal (Remove-PqAgentHoldAfterPass -Log $log -Name 'codex' -Run 'run1' -Repo 'fake' -Id 'T0013' -Pass 'run1.13' -Worker 1) $false 'events: with no hold on disk nothing is cleared and nothing written'
    # The owner's release ends a hold too: by owner, and with no ticket.
    $null = Set-PqAgentHold -Name 'zai' -Pass 'run1.20' -Source 'log' -Detector 'proven'
    Assert-Equal (Remove-PqAgentHoldAfterPass -Log $log -Name 'zai' -By 'owner') $true 'events: the owner releases a hold'
    $null = Close-PqLog -Log $log

    $events = @([IO.File]::ReadAllLines($log.Path) | ForEach-Object { ConvertFrom-Json -InputObject $_ })
    Assert-Equal (($events | ForEach-Object { "$($_.ev):$($_.d.change)" }) -join ',') 'agent.hold:,agent.fallback:start,agent.hold:,agent.resume:,agent.fallback:end,agent.resume:,agent.fallback:end' 'events: the sequence of a hold - start, a second write, the end, the owner release'
    $start = $events[1]
    Assert-Equal "$($start.d.from)/$($start.d.why)/$(([datetime]$start.d.until).ToUniversalTime().ToString($iso))/$($start.d.resetSource)/$($null -eq (Get-PqValue $start.d 'to'))/$($start.repo):$($start.id)/$($start.pass)" "codex/limit/$short/log/True/fake:T0010/run1.10" 'events: the start carries the agent, the time and its source, and no to'
    $end = $events[4]
    Assert-Equal "$($end.d.from)/$($end.d.to)/$($end.d.why)/$($end.d.change)/$($end.repo):$($end.id)" 'codex/codex/limit/end/fake:T0012' 'events: the end carries the agent as from and to, and the pass that cleared it'
    Assert-Equal "$($events[3].d.by)/$($events[3].d.agent)" 'reset/codex' 'events: a timed hold that a pass cleared resumes by reset'
    Assert-Equal "$($events[5].d.by)/$($null -eq (Get-PqValue $events[6].d 'repo'))/$($events[6].d.change)" 'owner/True/end' 'events: the owner release is by owner and its fallback end names no ticket'
    Assert-Equal (@($events | Where-Object { $_.ev -ceq 'agent.hold' } | ForEach-Object { $_.d.resetSource }) -join ',') 'log,log' 'events: agent.hold carries resetSource'

    # -----------------------------------------------------------------------------------------
    # Case 6: a ranking records no pass-over for a limit
    # -----------------------------------------------------------------------------------------
    $pick = @{ agent = 'gemini'; fallbacks = @(
            @{ from = 'codex'; why = 'limit' }, @{ from = 'zai'; why = 'maxParallel' }, @{ from = 'claude'; why = 'stopped' }, @{ from = 'mistral'; why = 'levelNotAllowed' }) }
    Assert-Equal ((Get-PqRankingFallbacks $pick | ForEach-Object { "$($_.from):$($_.why)" }) -join ',') 'zai:maxParallel,mistral:levelNotAllowed' 'ranking: a limit and an owner stop are not recorded per ranking, every other reason is'
    Assert-Equal @(Get-PqRankingFallbacks @{ agent = 'codex'; fallbacks = @() }).Count 0 'ranking: a pick with no pass-over records nothing'
    Assert-Equal @(Get-PqRankingFallbacks @{ agent = 'codex' }).Count 0 'ranking: a pick without the list records nothing'
    $loopText = [IO.File]::ReadAllText((Join-Path $pqLib 'loop.ps1'))
    Assert-Equal ($loopText -match 'foreach \(\$fb in @\(Get-PqRankingFallbacks \$pick\)\) \{\s+\$null = Write-PqEvent -Log \$log -Ev ''agent\.fallback''') $true 'loop: the per-ranking agent.fallback is written through Get-PqRankingFallbacks'
    Assert-Equal ($loopText.Contains('foreach ($fb in @($pick.fallbacks))')) $false 'loop: the whole list is no longer written per ranking'
    Assert-Equal ($loopText.Contains('Set-PqAgentHoldFromPass -Log $log -Name $agentName')) $true 'loop: a hold is written with its events'
    Assert-Equal ($loopText.Contains('Remove-PqAgentHoldAfterPass -Log $log -Name $agentName')) $true 'loop: a cleared hold is written with its events'
    Assert-Equal ([regex]::Matches($loopText, "Set-PqAgentHold -Name|Ev 'agent\.hold'|Ev 'agent\.resume'").Count) 0 'loop: the loop writes no hold, agent.hold or agent.resume of its own'
    $agentsText = [IO.File]::ReadAllText((Join-Path $pqLib 'agents.ps1'))
    Assert-Equal ($agentsText.Contains('if ($hold.started) {')) $true 'hold events: the start of a fallback is written only when the hold started'

    # -----------------------------------------------------------------------------------------
    # Case 7: PQ-LIMIT01 - a guessed hold longer than six hours only
    # -----------------------------------------------------------------------------------------
    $ts = [DateTimeOffset]::UtcNow.ToString($iso)
    $mk = { param($Source, $Hours) [pscustomobject]@{ ev = 'agent.hold'; ts = $ts; seq = 1; wr = 'w1'; d = @{ agent = 'codex'; detector = 'unproven'; until = $(if ($null -ne $Hours) { [DateTimeOffset]::Parse($ts).AddHours($Hours).ToString($iso) } else { $null }); resetSource = $Source } } }
    $fids = { param($Events, $Thresholds = $null) @(Get-PqFindings -Runs @() -Events @($Events) -Gaps @() -Thresholds $Thresholds | Where-Object { $_.fid -ceq 'PQ-LIMIT01' }) }
    $long = @(& $fids @(& $mk 'guessed' 7))
    Assert-Equal "$($long.Count)/$($long[0].value)/$($long[0].threshold)/$($long[0].evidence[0])" '1/1/1/agent.hold#1@w1' 'finding: a guessed hold of seven hours is flagged, with its event ref'
    Assert-Equal @(& $fids @(& $mk 'guessed' 6)).Count 0 'finding: a guessed hold of six hours is at the cap, not over it'
    Assert-Equal @(& $fids @(& $mk 'guessed' 3)).Count 0 'finding: a guessed hold of three hours is not flagged'
    Assert-Equal @(& $fids @(& $mk 'log' 120)).Count 0 'finding: a hold read from the log of five days is not flagged'
    Assert-Equal @(& $fids @(& $mk $null 168)).Count 0 'finding: a hold written before 0.50 is not flagged'
    Assert-Equal @(& $fids @(& $mk 'guessed' $null)).Count 0 'finding: a guessed hold without a time is not flagged'
    Assert-Equal @(& $fids @(& $mk 'guessed' 7) @{ 'PQ-LIMIT01' = 8 }).Count 0 'finding: a threshold of the registry raises the cap'
    Assert-Equal @(& $fids @(& $mk 'guessed' 3) @{ 'PQ-LIMIT01' = 2 }).Count 1 'finding: a threshold of the registry lowers the cap'
}
catch {
    $script:failed++
    Write-Host "FAIL the suite stopped: $($_.Exception.Message) at $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
}
finally {
    if ($null -ne $log) { try { $null = Close-PqLog -Log $log } catch { } }
    $env:SZA_PORTFOLIO_ROOT = $priorRoot
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "limit-detector: PASS $script:passed, FAIL $script:failed"
if ($script:failed -gt 0) { exit 1 }
exit 0
