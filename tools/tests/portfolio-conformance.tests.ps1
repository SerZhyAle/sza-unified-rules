#requires -Version 7.0
# Fast cases of S0082 (TASK-FLOW 0.27 rules 41-64 against tools/harness/portfolio): one case per item the ticket
# implemented in code. Function calls on dot-sourced libraries; no pq process and no live registry. The worker-cap and
# resource cases write into a throwaway portfolio root under the system temp directory (SZA_PORTFOLIO_ROOT for the
# duration of the script), removed at the end; nothing else is written.
#
# Cases:
#   rule 52 - the dispatcher's qualified-blocker reader ignores a token quoted after a backtick or an angle bracket,
#             as the closing gate does, and still reads a plain, a bold and a statusNote token
#   rule 46 - the run row's finishedAt is local yyyy-MM-ddTHH:mm:ss with no zone; agentExit is an integer or absent
#   rule 46 - no zone-offset finishedAt is left in the loop
#   rule 41 - an agent record is refused for a halt, limitPollMinutes or limitDetector.pattern the contract does not allow
#   rule 42 - agent.fallback is written only with a why of its vocabulary (an owner stop is not a fallback), and
#             since TASK-FLOW 0.50 never per ranking for a limit
#   rule 48 - agent.resume carries heldFor and says reset or probe
#   rule 51 - the dispatcher's and the runner's level regexes are the same three
#   rule 61 - repo.free carries the by, holderKind and start of the occupancy it ends
#   rule 62 - a worker-cap refusal names maxWorkers or leased; a resource event reports its own token's held and cap
#   rule 51 - a pass carries cx and cxSource (header, default, fixedAgent); a rewritten level gives ticket.complexity
#   rule 53 - the envelope carries model and cx; the handle counts the lines it wrote (run.end eventsWritten)
#   rule 58 - dispatch.pick explains the pick (top three alternatives, agentWhy); a rank is a picker call of poll.summary
#   rules 53-58 - run.start, run.end and pass.launch carry the cheap keys the loop now fills
#   rule 41 - analysis.thresholds, named by finding id, move a finding's threshold; a non-number is ignored
#   rule 49 - a worktree of a registered repository is collected as repo.skipped, not joined
#   rule 47 - a drain of any target carries the ticket in flight; a stricter stop over it ends the carry; a worker
#             between two passes of a carried ticket keeps that stop's target busy
#   rule 47 - halt and kill cleanup clears dead locks through the locks tool, validates the ledger and names the files
#             changed since the pass began (a throwaway git repository)
#   rule 48 - past a poll hold's limitPollMinutes exactly one worker takes the probe (agent cap 1 under the assignment
#             lock), the others see the agent held while it runs, and agent.probe says ok, limit or error
#   rule 59 - the ledger watch is wired: a shared look per repository, a baseline first, then ticket.transition (actor
#             from a pq<k> runner row), ticket.created with a repository-relative file and ingest.ledgerDiff, once
#
# Exit 0 when every case passed, 1 on the first failure.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$lib = Join-Path $PSScriptRoot '..\harness\portfolio\lib'
. (Join-Path $lib 'xrepo.ps1')
. (Join-Path $lib 'paths.ps1')
. (Join-Path $lib 'registry.ps1')
. (Join-Path $lib 'loop.ps1')
. (Join-Path $lib 'agents.ps1')
. (Join-Path $lib 'resources.ps1')
. (Join-Path $lib 'events.ps1')
. (Join-Path $lib 'analysis.ps1')
. (Join-Path $lib 'discovery.ps1')
. (Join-Path $lib 'stop.ps1')
. (Join-Path $lib 'ledger-watch.ps1')

$script:count = 0
function Assert-Equal($Actual, $Expected, [string]$Case) {
    $script:count++
    if ("$Actual" -cne "$Expected") { Write-Host "FAIL $Case - expected '$Expected', got '$Actual'"; exit 1 }
    Write-Host "PASS $Case"
}

# ---- rule 52 ----
Assert-Equal ((Get-PqXrepoBlockers "Blocker: fms-a:S4466") -join ',') 'fms-a:S4466' 'rule 52: a plain token is read'
Assert-Equal ((Get-PqXrepoBlockers "- **Blocker:** fms-a:S4466") -join ',') 'fms-a:S4466' 'rule 52: a bold token is read'
Assert-Equal ((Get-PqXrepoBlockers '' 'waits. Blocker: hub:L0012') -join ',') 'hub:L0012' 'rule 52: a statusNote token is read'
Assert-Equal ((Get-PqXrepoBlockers 'write `Blocker: fms-a:S4466` on its own line') -join ',') '' 'rule 52: a backtick-quoted example is not read'
Assert-Equal ((Get-PqXrepoBlockers 'the form <Blocker: fms-a:S4466> is an example') -join ',') '' 'rule 52: an angle-bracket example is not read'
$gate = Join-Path $PSScriptRoot '..\harness\spec_catalog\_blocker-links.ps1'
$gateHasLookbehind = ([IO.File]::ReadAllText($gate)).Contains('(?<![`<])(?:Blocker|')
Assert-Equal $gateHasLookbehind $true 'rule 52: the gate carries the same lookbehind'

# ---- rule 46 ----
$fixed = [datetime]::new(2026, 11, 15, 7, 8, 9, [DateTimeKind]::Local)
Assert-Equal (Get-PqRunRowTime $fixed) '2026-11-15T07:08:09' 'rule 46: finishedAt is yyyy-MM-ddTHH:mm:ss, local, no zone'
Assert-Equal ((Get-PqRunRowTime) -match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$') $true 'rule 46: finishedAt of now has the shape'
Assert-Equal ($null -eq (Get-PqRunRowAgentExit $null)) $true 'rule 46: no journal exit code - agentExit absent'
Assert-Equal (Get-PqRunRowAgentExit 0) '0' 'rule 46: exit 0 is written'
Assert-Equal (Get-PqRunRowAgentExit '7') '7' 'rule 46: a string integer is written as an integer'
Assert-Equal ($null -eq (Get-PqRunRowAgentExit 'n/a')) $true 'rule 46: a non-integer is absent'
$loopText = [IO.File]::ReadAllText((Join-Path $lib 'loop.ps1'))
Assert-Equal ($loopText.Contains('sszzz')) $false 'rule 46: no zone-offset finishedAt left in the loop'
Assert-Equal ([regex]::Matches($loopText, 'agentExit = -1').Count) 0 'rule 46: no placeholder agentExit in a run row'

# ---- rule 41: agent record fields ----
function Get-AgentProblems([hashtable]$Extra) {
    $a = [ordered]@{ name = 'codex'; command = 'node'; model = 'm'; effort = 'high' }
    foreach ($k in $Extra.Keys) { $a[$k] = $Extra[$k] }
    $doc = ConvertTo-Json -Depth 8 -InputObject ([ordered]@{ schemaVersion = '1.0'; repos = @(); agents = @($a); agentOrder = @('codex') }) | ConvertFrom-Json -DateKind String
    $r = Test-PqRegistry -Registry $doc -ProfileReader { param($p) 0 }
    return (@($r.errors | Where-Object { $_.where -like 'agents*' } | ForEach-Object { "$($_.name)@$(($_.where -split '\.', 2)[1])" }) -join ',')
}
Assert-Equal (Get-AgentProblems @{ halt = 'none'; limitPollMinutes = 30; limitDetector = @{ kind = 'exitText'; pattern = '(?i)usage limit'; status = 'unproven' } }) '' 'rule 41: a record of the live shape is accepted'
Assert-Equal (Get-AgentProblems @{ limitDetector = @{ kind = 'transcript'; status = 'proven' } }) '' 'rule 41: a transcript detector needs no pattern'
Assert-Equal (Get-AgentProblems @{ halt = 'sigterm' }) 'AgentHaltInvalid@halt' 'rule 41: halt outside ctrlBreak, closeMain, none is refused'
Assert-Equal (Get-AgentProblems @{ limitPollMinutes = 0 }) 'AgentLimitPollRange@limitPollMinutes' 'rule 41: limitPollMinutes below 1 is refused'
Assert-Equal (Get-AgentProblems @{ limitPollMinutes = '30' }) 'AgentLimitPollRange@limitPollMinutes' 'rule 41: limitPollMinutes as a string is refused'
Assert-Equal (Get-AgentProblems @{ limitDetector = @{ kind = 'log' } }) 'LimitDetectorInvalid@limitDetector.pattern' 'rule 41: a log detector without a pattern is refused'
Assert-Equal (Get-AgentProblems @{ limitDetector = @{ kind = 'exitText'; pattern = '(unclosed' } }) 'LimitDetectorInvalid@limitDetector.pattern' 'rule 41: a pattern that is not a regular expression is refused'

# ---- rule 42: agent.fallback why ----
Assert-Equal (Test-PqFallbackWhy 'stopped') $false 'rule 42: an owner stop is not a fallback why'
Assert-Equal (@(@('limit', 'maxParallel', 'levelNotAllowed', 'aboveCeiling', 'noPipelineForm', 'launchFailed') | Where-Object { -not (Test-PqFallbackWhy $_) }).Count) 0 'rule 42: every why of the vocabulary is written'
$loopText = [IO.File]::ReadAllText((Join-Path $lib 'loop.ps1'))
Assert-Equal ($loopText -match "foreach \(\`$fb in @\(Get-PqRankingFallbacks \`$pick\)\) \{\s+\`$null = Write-PqEvent -Log \`$log -Ev 'agent\.fallback'") $true 'rule 42: the loop writes agent.fallback per ranking through Get-PqRankingFallbacks'
Assert-Equal ((Get-PqRankingFallbacks @{ fallbacks = @(@{ from = 'a'; why = 'stopped' }, @{ from = 'b'; why = 'limit' }, @{ from = 'c'; why = 'aboveCeiling' }) } | ForEach-Object { $_.from }) -join ',') 'c' 'rule 42: an owner stop and a limit are no per-ranking fallback, every other reason is'

# ---- rule 48: agent.resume ----
$now = [DateTimeOffset]::new(2026, 11, 15, 12, 0, 0, [TimeSpan]::Zero)
$r = Get-PqHoldResume @{ writtenAt = '2026-11-15T11:30:00.000Z'; until = $null } $now
Assert-Equal "$($r.heldFor)/$($r.by)" '1800/probe' 'rule 48: a poll hold resumes by probe with heldFor in seconds'
$r = Get-PqHoldResume @{ writtenAt = '2026-11-15T10:00:00.000Z'; until = '2026-11-15T11:59:00Z' } $now
Assert-Equal "$($r.heldFor)/$($r.by)" '7200/reset' 'rule 48: a timed hold resumes by reset'
$r = Get-PqHoldResume @{ writtenAt = 'garbage' } $now
Assert-Equal "$($r.heldFor)/$($r.by)" '0/probe' 'rule 48: an unreadable hold time gives heldFor 0'
$agentsText = [IO.File]::ReadAllText((Join-Path $lib 'agents.ps1'))
Assert-Equal ($agentsText.Contains("heldFor = (Get-PqValue `$resume 'heldFor' 0); by = `$by")) $true 'rule 48: the cleared hold writes heldFor into agent.resume'
Assert-Equal ($loopText.Contains('Remove-PqAgentHoldAfterPass -Log $log -Name $agentName')) $true 'rule 48: the loop clears a hold through Remove-PqAgentHoldAfterPass'

# ---- rule 51: one parser of the line for both readers (TASK-FLOW 0.32, S0139) ----
$levelRx = { param([string]$Text) @([regex]::Matches($Text, "'(\^\((?:light|medium|hard)\|[^']+)'") | ForEach-Object { $_.Groups[1].Value }) -join ' ' }
$parserRx = & $levelRx ([IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\harness\spec_catalog\lib\complexity-grade.ps1')))
Assert-Equal (@($parserRx -split ' ').Count) 3 'rule 51: the parser has three level patterns'
Assert-Equal (([IO.File]::ReadAllText((Join-Path $lib 'agents.ps1'))).Contains('ConvertFrom-SzaComplexityValue $raw')) $true 'rule 51: the dispatcher reads the line through the parser'
Assert-Equal (([IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\harness\batch\run-spec-queue.ps1'))).Contains('ConvertFrom-SzaComplexityValue $raw')) $true 'rule 51: the runner reads the line through the same parser'

# ---- rule 61: repo.free ----
$mark = New-PqOccupancyMark @{ by = 'lease'; holderKind = 'unknown' } $now
$free = Get-PqRepoFreeData $mark $now.AddSeconds(95)
Assert-Equal "$($free.by)/$($free.holderKind)/$($free.age)/$($free.since)" 'lease/unknown/95/2026-11-15T12:00:00Z' 'rule 61: repo.free carries the occupancy it ends'
Assert-Equal ($loopText.Contains("by = 'transcript'; holderKind = 'manual' })")) $false 'rule 61: no hard-coded repo.free left in the loop'

# ---- rule 51: cx, cxSource and ticket.complexity ----
$c = Get-PqPassCx '' 'claude'; Assert-Equal "$($c.cx)/$($c.cxSource)" 'medium/default' 'rule 51: no declared level runs at medium, cxSource default'
$c = Get-PqPassCx 'hard' 'claude'; Assert-Equal "$($c.cx)/$($c.cxSource)" 'hard/header' 'rule 51: a declared level is cxSource header'
$c = Get-PqPassCx 'light' 'codex'; Assert-Equal "$($c.cx)/$($c.cxSource)" 'light/fixedAgent' 'rule 51: a non-Claude agent is cxSource fixedAgent'
Assert-Equal ($null -eq (Get-PqComplexityChange 'hard' 'hard' 'Draft')) $true 'rule 51: an unchanged level writes no ticket.complexity'
$x = Get-PqComplexityChange '' 'hard' 'Draft'
Assert-Equal "$($x.Contains('from'))/$($x.to)/$($x.by)/$($x.direction)" 'False/hard/specPass/set' 'rule 51: a first level is set by the spec pass'
$x = Get-PqComplexityChange 'medium' 'hard' 'Tactical'
Assert-Equal "$($x.from)/$($x.to)/$($x.by)/$($x.direction)" 'medium/hard/planPass/raise' 'rule 51: a raise at Tactical is the plan pass'
$x = Get-PqComplexityChange 'hard' 'light' 'Approved'
Assert-Equal "$($x.by)/$($x.direction)" 'specPass/lower' 'rule 51: a lower before Tactical is the spec pass'
Assert-Equal ($loopText.Contains("-Ev 'ticket.complexity'")) $true 'rule 51: the loop writes ticket.complexity after a pass'

# ---- rule 58: dispatch.pick ----
$claudePick = @{ agent = 'claude'; record = @{ name = 'claude' }; fallbacks = @() }
$codexPick = @{ agent = 'codex'; record = @{ name = 'codex'; model = 'gpt-x' }; fallbacks = @(@{ from = 'claude'; why = 'limit' }) }
Assert-Equal "$($null -eq (Get-PqPickModel $claudePick))/$(Get-PqPickModel $codexPick)" 'True/gpt-x' 'rule 53: the pick model is the fixed record model, none for claude'
$cand = [ordered]@{ repo = 'demo'; id = 'S0001'; rule = 'queueFile'; status = 'Approved'; title = ('t' * 90)
    alt = @(1..4 | ForEach-Object { [ordered]@{ repo = 'demo'; id = "S000$($_ + 1)"; why = 'laterRow' } }) }
$pd = Get-PqDispatchPickData $cand $claudePick @{ agentOrder = @('claude', 'codex') } 'medium' $null
Assert-Equal "$($pd.repo):$($pd.id)/$($pd.rule)/$(@($pd.alt).Count)/$($pd.agentWhy)/$($pd.statusBefore)/$($pd.title.Length)" 'demo:S0001/queueFile/3/spendOrder/Approved/80' 'rule 58: dispatch.pick carries the top three alternatives and the cut title'
Assert-Equal (Get-PqDispatchPickData $cand $codexPick @{ agentOrder = @('claude', 'codex') } 'light' 'gpt-x').agentWhy 'fallback' 'rule 58: an earlier agent passed over is agentWhy fallback'
Assert-Equal (Get-PqDispatchPickData $cand $claudePick @{ agentOrder = @('claude') } 'medium' $null).agentWhy 'only' 'rule 58: a single agent in the order is agentWhy only'
Assert-Equal ($loopText.Contains("-Ev 'dispatch.pick'")) $true 'rule 58: the loop writes dispatch.pick'
Assert-Equal ($loopText.Contains('Add-PqPickerStat -Stats $pollStats')) $true 'rule 58: the loop counts each rank into poll.summary'

# ---- rules 53-58: the cheap keys ----
$hi = Get-PqHostInfo
Assert-Equal "$($hi.cpu -gt 0)/$([bool]$hi.os)/$($hi.Contains('ramGb'))" 'True/True/True' 'rule 53: run.start host has cpu, ramGb and os'
Assert-Equal "$((Get-PqArgvHash @('a', 'b')) -ceq (Get-PqArgvHash @('a', 'b')))/$((Get-PqArgvHash @('a', 'b')) -ceq (Get-PqArgvHash @('a', 'c')))" 'True/False' 'rule 53: argvHash is stable for a launch line and differs for another'
foreach ($k in @('$startD.watch', '$startD.detached', '$startD.canon', '$startD.plugin', '$startD.registryHash', '$startD.queueHash', '$startD.host', 'eventsWritten = ', 'logErrors = ', 'argvHash = ', 'promptForm = ', 'cxSource = ', 'profileHash = $profileHash', 'heads = ')) {
    Assert-Equal ($loopText.Contains($k)) $true "rules 53-58: the loop fills $k"
}

# ---- rule 41: analysis.thresholds ----
$thrashRuns = @(1..2 | ForEach-Object { [pscustomobject]@{ repo = 'demo'; id = 'S0001'; statusBefore = 'Approved'; statusAfter = 'Approved'; outcome = 'no-progress' } })
$fid = { param($t) @(Get-PqFindings -Runs $thrashRuns -Events @() -Gaps @() -Thresholds $t | ForEach-Object { $_.fid }) -join ',' }
Assert-Equal (& $fid $null) '' 'rule 41: two passes are under the default thrash threshold of 3'
Assert-Equal (& $fid ([pscustomobject]@{ 'PQ-THRASH01' = 2 })) 'PQ-THRASH01' 'rule 41: analysis.thresholds PQ-THRASH01 2 makes them a finding'
Assert-Equal (& $fid ([pscustomobject]@{ 'PQ-THRASH01' = 'two'; unknownName = 1 })) '' 'rule 41: a non-number and an unknown name are ignored'

# ---- rule 49: repo.skipped ----
$discScratch = Join-Path ([IO.Path]::GetTempPath()) ('pq-conformance-disc-' + [guid]::NewGuid().ToString('N'))
try {
    $mainDir = Join-Path $discScratch 'main'
    $wtDir = Join-Path $discScratch 'wt'
    $wtGit = Join-Path $mainDir '.git\worktrees\wt'
    $null = [IO.Directory]::CreateDirectory($wtGit)
    $null = [IO.Directory]::CreateDirectory($wtDir)
    [IO.File]::WriteAllText((Join-Path $mainDir '.sza-canon.json'), '{}')
    [IO.File]::WriteAllText((Join-Path $wtDir '.sza-canon.json'), '{}')
    [IO.File]::WriteAllText((Join-Path $wtDir '.git'), "gitdir: $wtGit")
    [IO.File]::WriteAllText((Join-Path $wtGit 'commondir'), '../..')
    $skippedList = [Collections.Generic.List[object]]::new()
    $daughters = @(Find-PqDaughters @{ repos = @(@{ key = 'main'; path = $mainDir }) } $skippedList)
    Assert-Equal "$($daughters.Count)/$($skippedList.Count)/$($skippedList[0].why)/$($skippedList[0].of)" '0/1/worktree/main' 'rule 49: a worktree of a registered repository is skipped and named'
}
finally { if ([IO.Directory]::Exists($discScratch)) { Remove-Item -LiteralPath $discScratch -Recurse -Force -ErrorAction SilentlyContinue } }

# ---- rule 62: worker cap and resources, in a throwaway portfolio root ----
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('pq-conformance-' + [guid]::NewGuid().ToString('N'))
$savedRoot = $env:SZA_PORTFOLIO_ROOT
try {
    $null = [IO.Directory]::CreateDirectory($scratch)
    $env:SZA_PORTFOLIO_ROOT = $scratch
    $repo = @{ key = 'demo'; concurrent = $false; maxWorkers = 1 }
    Set-PqWorkerState -Slot 1
    Set-PqWorkerState -Slot 2
    Assert-Equal (Request-PqWorkerAssignment -Slot 1 -Repo $repo -Ticket 'S0001' -Title '' -Agent 'claude' -AgentMax 2) $true 'rule 62: the first worker is assigned'
    Assert-Equal "$(Request-PqWorkerAssignment -Slot 2 -Repo $repo -Ticket 'S0001' -Title '' -Agent 'claude' -AgentMax 2)/$script:PqAssignmentWhy" 'False/leased' 'rule 62: the same ticket is refused as leased'
    Assert-Equal "$(Request-PqWorkerAssignment -Slot 2 -Repo $repo -Ticket 'S0002' -Title '' -Agent 'claude' -AgentMax 2)/$script:PqAssignmentWhy" 'False/maxWorkers' 'rule 62: a full repository is refused as maxWorkers'
    $t0 = [DateTime]::UtcNow
    Assert-Equal "$(Test-PqSkipDue 'k' $t0)/$(Test-PqSkipDue 'k' $t0.AddSeconds(5))/$(Test-PqSkipDue 'k' $t0.AddSeconds(61))" 'True/False/True' 'rule 62: a cap skip is written at most once a minute'

    $reg = @{ resources = @{ build = 3; emulator = 1 } }
    $stalePath = Get-PqPath -Kind resourceToken -Token 'build' -Repo 'gone' -Id 'S9'
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $stalePath))
    [IO.File]::WriteAllText($stalePath, '{"token":"build","repo":"gone","id":"S9","pid":999999,"procStart":"2000-01-01T00:00:00Z"}')
    $req = Request-PqResources -Registry $reg -RepoKey 'demo' -TicketId 'S0001' -Verify 'emulator' -PassId 'r.1'
    Assert-Equal $req.ok $true 'rule 62: an emulator ticket takes its tokens'
    $b = Get-PqResourceEventData $req 'build' 'emulator'
    $e = Get-PqResourceEventData $req 'emulator' 'emulator'
    Assert-Equal "$($b.held)/$($b.cap)|$($e.held)/$($e.cap)" '1/3|1/1' 'rule 62: each acquire reports its own token''s held and cap'
    Assert-Equal (@($req.stale) -join ',') 'build/gone__S9' 'rule 62: the dead owner''s token is cleared'
    $s = Get-PqResourceEventData $req 'build' 'emulator' 'build/gone__S9'
    Assert-Equal "$($s.resource)/$($s.verify)/$($s.held)/$($s.cap)/$($s.stale)" 'build/emulator/1/3/build/gone__S9' 'rule 62: the stale release carries verify, held and cap'
    Assert-Equal ($loopText.Contains('held = $resReq.heldCount; cap = $resReq.cap })')) $true 'rule 62: resource.wait keeps the failing token''s count'
    $null = Remove-PqResources -RepoKey 'demo' -TicketId 'S0001'

    # ---- rule 53: envelope model and cx, the written count; rule 58: picker calls in poll.summary ----
    $h = Open-PqLog -Writer 'w7' -Run 'R-conformance'
    $null = Write-PqEvent -Log $h -Ev 'pass.launch' -Repo 'demo' -Id 'S0001' -Worker 7 -Agent 'codex' -Model 'gpt-x' -Cx 'light' -D ([ordered]@{ instance = 'pq7' })
    $stats = New-PqPollStats
    Add-PqPickerStat -Stats $stats -Log $h -Ms 10
    Add-PqPickerStat -Stats $stats -Log $h -Ms 30
    Assert-Equal (Write-PqPollSummary -Stats $stats -Log $h) $true 'rule 58: a busy hour with ranks and no polls still writes poll.summary'
    Assert-Equal $h.Written 2 'rule 53: the handle counts the lines it wrote'
    $logFile = $h.Path
    Close-PqLog -Log $h
    $lines = @([IO.File]::ReadAllLines($logFile) | ForEach-Object { ConvertFrom-Json $_ })
    Assert-Equal "$($lines[0].model)/$($lines[0].cx)" 'gpt-x/light' 'rule 53: the envelope carries model and cx'
    Assert-Equal "$($lines[1].ev)/$($lines[1].d.pickerCalls)/$($lines[1].d.pickerMsAvg)/$($lines[1].d.pickerMsMax)" 'poll.summary/2/20/30' 'rule 58: poll.summary counts the ranks as picker calls'

    # ---- rule 47: drain of every target ----
    $mk = { param($kind, $target, $level) [pscustomobject]@{ kind = $kind; target = $target; level = $level; file = "STOP-$kind-$target" } }
    $repoDrain = & $mk 'repo' 'demo' 'drain'
    Assert-Equal "$(Test-PqDrainCarry $repoDrain $true $false)/$(Test-PqDrainCarry $repoDrain $false $false)/$(Test-PqDrainCarry $repoDrain $true $true)/$(Test-PqDrainCarry (& $mk 'repo' 'demo' 'pass') $true $false)/$(Test-PqDrainCarry $null $true $false)" 'True/False/False/False/False' 'rule 47: a moved, unkilled pass under a drain of any target is carried'
    Assert-Equal (Test-PqDrainCarry (& $mk 'ticket' 'demo:S0001' 'drain') $true $false) $true 'rule 47: a ticket drain carries its ticket'
    Assert-Equal ((Get-PqCarryStop -Stops @($repoDrain) -Carry 'demo:S0001' -Agent 'codex').file) 'STOP-repo-demo' 'rule 47: a repository drain lets the carried ticket go on'
    Assert-Equal ((Get-PqCarryStop -Stops @((& $mk 'agent' 'codex' 'drain')) -Carry 'demo:S0001' -Agent 'codex').file) 'STOP-agent-codex' 'rule 47: an agent drain lets the carried ticket of that agent go on'
    Assert-Equal ($null -eq (Get-PqCarryStop -Stops @($repoDrain, (& $mk 'ticket' 'demo:S0001' 'pass')) -Carry 'demo:S0001')) $true 'rule 47: a pass stop over the carried ticket wins over the drain'
    Assert-Equal ($null -eq (Get-PqCarryStop -Stops @((& $mk 'repo' 'other' 'drain'), (& $mk 'all' $null 'drain')) -Carry 'demo:S0001')) $true 'rule 47: a drain of another repository or the STOP is no target carry'
    $carrier = [pscustomobject]@{ slot = 5; key = ''; repository = ''; agent = ''; carry = 'demo:S0001'; carryAgent = 'codex' }
    Assert-Equal "$(Test-PqStopTargetBusy $repoDrain @($carrier))/$(Test-PqStopTargetBusy (& $mk 'agent' 'codex' 'drain') @($carrier))/$(Test-PqStopTargetBusy (& $mk 'ticket' 'demo:S0001' 'drain') @($carrier))/$(Test-PqStopTargetBusy (& $mk 'repo' 'other' 'drain') @($carrier))" 'True/True/True/False' 'rule 47: a carrying worker keeps its target busy'
    Set-PqWorkerState -Slot 5 -Carry 'demo:S0001' -CarryAgent 'codex'
    $w5 = @(Get-PqWorkerFiles | Where-Object { $_.slot -eq 5 })
    Assert-Equal "$($w5.Count)/$($w5[0].key)/$($w5[0].carry)/$($w5[0].carryAgent)" '1//demo:S0001/codex' 'rule 47: the worker state names the carry and Get-PqWorkerFiles reads it'
    Set-PqWorkerState -Slot 5
    Assert-Equal (@(Get-PqWorkerFiles | Where-Object { $_.slot -eq 5 })[0].carry) '' 'rule 47: a plain worker state carries nothing'
    Assert-Equal ($loopText.Contains("-cin @('all', 'worker')) { `$drainCarry")) $false 'rule 47: the loop no longer limits the carry to STOP and STOP-worker'

    # ---- rule 47: halt and kill cleanup ----
    $gitRepo = Join-Path $scratch 'repo'
    $null = [IO.Directory]::CreateDirectory($gitRepo)
    $null = & git -C $gitRepo init -q 2>&1
    foreach ($f in 'kept.txt', 'gone.txt', 'old.txt') { [IO.File]::WriteAllText((Join-Path $gitRepo $f), 'x') }
    $null = & git -C $gitRepo add -A 2>&1
    $null = & git -C $gitRepo -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m init 2>&1
    $since = [DateTime]::Now
    [IO.File]::WriteAllText((Join-Path $gitRepo 'old.txt'), 'y')
    [IO.File]::SetLastWriteTime((Join-Path $gitRepo 'old.txt'), $since.AddHours(-1))
    [IO.File]::Delete((Join-Path $gitRepo 'gone.txt'))
    $null = [IO.Directory]::CreateDirectory((Join-Path $gitRepo 'sub'))
    [IO.File]::WriteAllText((Join-Path $gitRepo 'sub\new.txt'), 'n')
    Assert-Equal ((Get-PqChangedSince -RepoPath $gitRepo -Since $since) -join ',') 'gone.txt,sub/new.txt' 'rule 47: the files changed since the pass began are named, an older edit is not'
    Assert-Equal (@(Get-PqChangedSince -RepoPath $scratch -Since $since).Count) 0 'rule 47: outside a git repository nothing is named'
    $calls = [Collections.Generic.List[string]]::new()
    $stub = { param($rp, $sc, $ar) $calls.Add("$([IO.Path]::GetFileName($sc)) $($ar -join ' ')"); @{ code = $(if ($ar -contains 'Code') { 1 } else { 0 }); timedOut = $false } }
    $clean = Invoke-PqStopCleanup -RepoPath $gitRepo -HarnessRoot 'H:\harness' -Since $since -Invoker $stub
    Assert-Equal ($calls -join '|') 'clear-agent-lock.ps1 -Name Build|clear-agent-lock.ps1 -Name Code|validate.ps1 ' 'rule 47: cleanup runs the locks tool for both types without -Force, then the ledger validate'
    Assert-Equal "$($clean.locks['Build'])/$($clean.locks['Code'])/$($clean.validate)/$(@($clean.changed).Count)" '0/1/0/2' 'rule 47: cleanup returns the lock codes, the validate code and the changed files'
    $thrower = { param($rp, $sc, $ar) throw 'boom' }
    $bad = Invoke-PqStopCleanup -RepoPath $gitRepo -HarnessRoot 'H:\harness' -Since $since -Invoker $thrower
    Assert-Equal "$($bad.locks['Build'])/$($bad.locks['Code'])/$($bad.validate)" 'error/error/error' 'rule 47: a failing cleanup step is recorded, never thrown'
    Assert-Equal ($loopText.Contains('Invoke-PqStopCleanup -RepoPath $repoPath')) $true 'rule 47: the loop runs the cleanup on halt and kill'

    # ---- rule 48: one probe pass of a poll hold ----
    $codex = [pscustomobject]@{ name = 'codex'; maxParallel = 2; limitPollMinutes = 30 }
    $holdFile = Get-PqPath -Kind hold -Agent 'codex'
    $writeHold = { param($minutesAgo, $until) $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $holdFile)); [IO.File]::WriteAllText($holdFile, (ConvertTo-Json -Compress -InputObject ([ordered]@{ agent = 'codex'; until = $until; source = 'log'; detector = 'unproven'; writtenAt = [DateTimeOffset]::UtcNow.AddMinutes(-$minutesAgo).ToString('yyyy-MM-ddTHH:mm:ss.fffZ'); pass = 'r.1' }))) }
    $pickCodex = @{ agent = 'codex'; record = $codex }
    & $writeHold 5 $null
    Assert-Equal "$(Test-PqAgentHeld (Get-PqAgentHold 'codex') $codex)/$(Test-PqAgentProbeDue (Get-PqAgentHold 'codex') $codex)/$(Get-PqPassAgentMax $pickCodex)" 'True/False/2' 'rule 48: a poll hold inside limitPollMinutes holds; no probe yet'
    & $writeHold 40 $null
    Assert-Equal "$(Test-PqAgentHeld (Get-PqAgentHold 'codex') $codex)/$(Test-PqAgentProbeDue (Get-PqAgentHold 'codex') $codex)/$(Get-PqPassAgentMax $pickCodex)" 'False/True/1' 'rule 48: past the poll the next pass is the probe, with an agent cap of 1'
    $otherPid = (Get-Process -Id $PID).Parent.Id
    $w9 = Join-Path (Join-Path $scratch 'run') 'worker-9.json'
    [IO.File]::WriteAllText($w9, (ConvertTo-Json -Compress -InputObject ([ordered]@{ slot = 9; pid = $otherPid; repository = 'other'; ticket = 'S0009'; agent = 'codex' })))
    Assert-Equal (Test-PqAgentHeld (Get-PqAgentHold 'codex') $codex) $true 'rule 48: while another worker''s probe runs, the agent stays held'
    Remove-Item -LiteralPath $w9 -Force
    & $writeHold 40 ([DateTimeOffset]::UtcNow.AddHours(2).ToString('o'))
    Assert-Equal "$(Test-PqAgentProbeDue (Get-PqAgentHold 'codex') $codex)/$(Get-PqPassAgentMax $pickCodex)" 'False/2' 'rule 48: a hold with a reset time has no probe'
    Remove-Item -LiteralPath $holdFile -Force
    Assert-Equal "$(Test-PqAgentProbeDue $null $codex)/$(Get-PqPassAgentMax $pickCodex)" 'False/2' 'rule 48: no hold, no probe'
    Set-PqWorkerState -Slot 1
    Set-PqWorkerState -Slot 2
    Assert-Equal (Request-PqWorkerAssignment -Slot 1 -Repo @{ key = 'p1' } -Ticket 'S0001' -Title '' -Agent 'codex' -AgentMax 1) $true 'rule 48: the first worker takes the probe'
    Assert-Equal "$(Request-PqWorkerAssignment -Slot 2 -Repo @{ key = 'p2' } -Ticket 'S0002' -Title '' -Agent 'codex' -AgentMax 1)/$script:PqAssignmentWhy" 'False/maxWorkers' 'rule 48: a second probe of the agent is refused under the lock'
    Set-PqWorkerState -Slot 1
    Assert-Equal "$(Get-PqProbeResult 1 $false $false 'limit-hit')/$(Get-PqProbeResult 0 $true $false 'ok')/$(Get-PqProbeResult 0 $false $false 'child-failed')/$(Get-PqProbeResult 0 $false $false 'ok')" 'limit/error/error/ok' 'rule 48: agent.probe result is limit, error or ok'
    Assert-Equal ($loopText.Contains("-Ev 'agent.probe'") -and $loopText.Contains('-AgentMax (Get-PqPassAgentMax $pick)')) $true 'rule 48: the loop writes agent.probe and caps the probe assignment'

    # ---- rule 59: the ledger watch wiring ----
    $lwRepo = Join-Path $scratch 'lwrepo'
    $null = [IO.Directory]::CreateDirectory((Join-Path $lwRepo 'PLAN'))
    $null = [IO.Directory]::CreateDirectory((Join-Path $lwRepo 'temp\spec-queue'))
    $ledgerFile = Join-Path $lwRepo 'PLAN\spec-catalog.jsonl'
    $row = { param($id, $status, $updated) ConvertTo-Json -Compress -InputObject ([ordered]@{ id = $id; status = $status; updated = $updated; created = '2026-11-15'; priority = 'P2'; file = "PLAN/${id}_x.md" }) }
    [IO.File]::WriteAllText($ledgerFile, ((& $row 'S0001' 'Draft' '2026-11-15 08:00') + "`n"))
    $lwReg = [pscustomobject]@{ repos = @([pscustomobject]@{ key = 'lw'; path = $lwRepo; enabled = $true }) }
    $lwLog = Open-PqLog -Writer 'w8' -Run 'R-lw'
    Assert-Equal (Invoke-PqLedgerWatch -Registry $lwReg -Log $lwLog -Run 'R-lw' -Worker 8) 0 'rule 59: the first look is a baseline and writes no event'
    Assert-Equal ([IO.File]::Exists((Get-PqLedgerWatchPath 'lw'))) $true 'rule 59: the look is saved in run\ledger-<key>.json, shared by the workers'
    $t1 = (Get-Date).AddMinutes(1).ToString('yyyy-MM-dd HH:mm')
    [IO.File]::WriteAllText($ledgerFile, ((& $row 'S0001' 'Approved' $t1) + "`n" + (& $row 'S0002' 'Draft' $t1) + "`n"))
    [IO.File]::WriteAllText((Join-Path $lwRepo 'temp\spec-queue\runs-pq8.jsonl'), ((ConvertTo-Json -Compress -InputObject ([ordered]@{ id = 'S0001'; statusBefore = 'Draft'; statusAfter = 'Approved'; finishedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss') })) + "`n"))
    Assert-Equal (Invoke-PqLedgerWatch -Registry $lwReg -Log $lwLog -Run 'R-lw' -Worker 8 -Repos @('lw')) 3 'rule 59: a look after a move writes ticket.transition, ticket.created and ingest.ledgerDiff'
    Assert-Equal (Invoke-PqLedgerWatch -Registry $lwReg -Log $lwLog -Run 'R-lw' -Worker 9 -Repos @('lw')) 0 'rule 59: a second worker''s look at the same ledger writes nothing again'
    Assert-Equal (Invoke-PqLedgerWatch -Registry $lwReg -Log $lwLog -Run 'R-lw' -Worker 8 -Repos @('other')) 0 'rule 59: a repository not named is not looked at'
    $lwFile = $lwLog.Path
    Close-PqLog -Log $lwLog
    $lwEv = @([IO.File]::ReadAllLines($lwFile) | ForEach-Object { ConvertFrom-Json $_ })
    Assert-Equal (($lwEv | ForEach-Object { $_.ev }) -join ',') 'ticket.transition,ticket.created,ingest.ledgerDiff' 'rule 59: the events in order'
    Assert-Equal "$($lwEv[0].id)/$($lwEv[0].d.from)/$($lwEv[0].d.to)/$($lwEv[0].d.actor)" 'S0001/Draft/Approved/robot' 'rule 59: a move covered by a pq<k> runner row is the robot''s'
    Assert-Equal "$($lwEv[1].id)/$($lwEv[1].d.source)/$($lwEv[1].d.file)" 'S0002/owner/PLAN/S0002_x.md' 'rule 59: ticket.created carries the spec file repository-relative (rule 56)'
    Assert-Equal "$($lwEv[2].d.transitions)/$($lwEv[2].d.created)/$($lwEv[2].d.unattributed)" '1/1/0' 'rule 59: ingest.ledgerDiff counts the interval'
    $saved = Read-PqLedgerWatch (Get-PqLedgerWatchPath 'lw')
    Assert-Equal "$(@($saved.snapshot.tickets.Keys) -join ',')/$($saved.enteredAt['S0001'])" "S0001,S0002/$t1" 'rule 59: the saved look carries the rows and the entry map'
    $lock = Invoke-PqLedgerWatchLock 'lw' { Invoke-PqLedgerWatchLock 'lw' { } }
    Assert-Equal $lock $true 'rule 59: the watch lock runs its body when free'
    Assert-Equal ($null -eq (Get-PqRepoRunnerRows (Join-Path $lwRepo 'temp\spec-queue'))) $false 'rule 59: the runner rows are read'
    Assert-Equal (@(Get-PqRepoRunnerRows (Join-Path $lwRepo 'temp\spec-queue'))[0].instance) 'pq8' 'rule 59: a runner row carries its instance from the file name'
    Assert-Equal ($loopText.Contains('-LivePasses @($endedPass)') -and $loopText.Contains("-contains 'ledger'")) $true 'rule 59: the loop looks after each pass and after a ledger change while waiting'
}
finally {
    $env:SZA_PORTFOLIO_ROOT = $savedRoot
    if ([IO.Directory]::Exists($scratch)) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "$script:count cases passed"
exit 0
