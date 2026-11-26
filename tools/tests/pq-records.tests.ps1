#requires -Version 7.0
<# Fast cases of the queue records that decide (CANONR-0208, TASK-FLOW 0.51 section 27). Exit 0 on success, 1 on a
failed assertion.

Cases:
  1. outcome spelling: an unmoved run is journalled no-progress, an observed claim loss keeps its own outcome, a new
     portfolio row says no-progress for an old journal row, and the idle hold counts both spellings
  2. recovery of a dead worker: the row ends at the last pass.beat of its pass, records detectedAfterMinutes and carries
     run, pass, model and statusBefore; with no beat it ends at the repository lock's write time; a state written by an
     older worker still gives a row
  3. the pass facts of a worker state survive a refresh of its seen stamp; pass.beat is due once per five minutes
  4. the retry walk: three offers without net advance hold, progress and neutral outcomes do not
  5. the rank: the fourth offer is held, an edit of the spec lifts it, rows older than 24 h expire, a named start passes
  6. an unchanged blocker result is said once, across readers, and its release once
  7. old day files are zipped, readers see them, a file a writer holds and the newest 14 days stay plain
  8. findings: PQ-RACE01 points at the rows; the findings over reserved events and the live-log paths are gone
Touches: portfolio/lib (events, loop, offer-limit, rank, analysis, paths, ledger-watch), batch/_idle-runs.ps1,
Resolve-RunOutcome of batch/run-spec-queue.ps1 (read through the parser; the runner is not run), and a throwaway
directory under the system temp directory (SZA_PORTFOLIO_ROOT and SZA_PROJECT_ROOT for the duration of the script),
removed at the end. Starts no child process. Writes nothing else. #>
# As pq.ps1 runs these libraries.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$harness = Join-Path (Split-Path $PSScriptRoot -Parent) 'harness'
$pqLib = Join-Path $harness 'portfolio/lib'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('pq-records-' + [guid]::NewGuid().ToString('N'))
$portfolio = Join-Path $scratch 'portfolio'
$repo = Join-Path $scratch 'demo-repo'
foreach ($d in @($portfolio, (Join-Path $repo 'PLAN'), (Join-Path $repo 'temp/spec-queue'))) { $null = [IO.Directory]::CreateDirectory($d) }
$utf8 = [Text.UTF8Encoding]::new($false)
$priorRoot = $env:SZA_PORTFOLIO_ROOT
$priorProject = $env:SZA_PROJECT_ROOT
$env:SZA_PORTFOLIO_ROOT = $portfolio
$env:SZA_PROJECT_ROOT = $repo
# The profile names the old spelling alone: the idle hold must still count a row of the new one.
[IO.File]::WriteAllText((Join-Path $repo '.sza-profile.json'), '{"runner":{"idleOutcomes":["ok","no-progress-or-claim-lost"]}}', $utf8)

. (Join-Path $pqLib 'paths.ps1')
. (Join-Path $pqLib 'events.ps1')
. (Join-Path $pqLib 'registry.ps1')
. (Join-Path $pqLib 'ledger-watch.ps1')
. (Join-Path $pqLib 'loop.ps1')
. (Join-Path $pqLib 'picker.ps1')
. (Join-Path $pqLib 'rank.ps1')
. (Join-Path $pqLib 'xrepo.ps1')
. (Join-Path $pqLib 'waiting.ps1')
. (Join-Path $pqLib 'analysis.ps1')
. (Join-Path $harness 'batch/_idle-runs.ps1')

$script:failed = 0
$script:passed = 0
function Assert-Equal($Actual, $Expected, [string] $Case) {
    if ("$Actual" -cne "$Expected") { $script:failed++; Write-Host "FAIL $Case - expected [$Expected], got [$Actual]" -ForegroundColor Red }
    else { $script:passed++; Write-Host "PASS $Case" }
}
function Read-Rows([string] $Path) { return @([IO.File]::ReadAllLines($Path) | Where-Object { $_.Trim() } | ForEach-Object { ConvertFrom-Json $_ -DateKind String }) }
$clockFormat = "yyyy-MM-dd'T'HH:mm:ss"

try {
    # ---- 1. outcome spelling ----
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $harness 'batch/run-spec-queue.ps1'), [ref]$tokens, [ref]$errors)
    $fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Resolve-RunOutcome' }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))
    $quick = Resolve-RunOutcome -Outcome 'ok' -ExitCode 0 -StatusBefore 'Draft' -StatusAfter 'Draft' -ElapsedSeconds 30
    Assert-Equal $quick.Outcome 'no-progress' 'outcome: a quick unmoved run is no-progress'
    $lost = Resolve-RunOutcome -Outcome 'claim-lost' -ExitCode 0 -StatusBefore 'Draft' -StatusAfter 'Approved' -ElapsedSeconds 30
    Assert-Equal "$($lost.Outcome)/$($lost.Moved)" 'claim-lost/False' 'outcome: an observed claim loss keeps its own outcome'
    function Get-PqTicketRecord { param($RepoPath, $Id, $HarnessRoot) return [pscustomobject]@{ id = $Id; status = 'Draft' } }
    [IO.File]::WriteAllText((Join-Path $repo 'temp/spec-queue/runs-pq9.jsonl'), '{"id":"S0009","outcome":"no-progress-or-claim-lost","finishedAt":"2026-11-12T09:00:00","exitCode":0,"costUsd":0.1,"priceAsOf":"2026-11-12","usage":{"model":"m","input":1,"output":1,"cacheRead":0,"cacheWrite":0,"requests":1,"complete":true}}' + "`n", $utf8)
    $po = Read-PqPassOutcome -RepoPath $repo -Instance 'pq9' -TicketId 'S0009' -StatusBefore 'Draft' -ChildExitCode 0
    Assert-Equal "$($po.outcome)/$($po.costUsd)/$($po.Contains('priceAsOf'))" 'no-progress/0.1/False' 'outcome: a new row says no-progress and carries no price date'
    Assert-Equal "$(ConvertTo-PqPassEndOutcome 'no-progress')/$(ConvertTo-PqPassEndOutcome 'no-progress-or-claim-lost')" 'noProgress/noProgress' 'outcome: both spellings are noProgress in the event'
    Assert-Equal (($script:IdleRunDefaultOutcomes -contains 'no-progress') -and ($script:IdleRunDefaultOutcomes -contains 'no-progress-or-claim-lost')) $true 'idle: the default set names both spellings'
    [IO.File]::WriteAllText((Join-Path $repo 'temp/spec-queue/runs-a.jsonl'), (@(
        '{"id":"T1","statusBefore":"Draft","statusAfter":"Draft","moved":false,"outcome":"no-progress-or-claim-lost","finishedAt":"2026-11-12T10:00:00"}'
        '{"id":"T1","statusBefore":"Draft","statusAfter":"Draft","moved":false,"outcome":"no-progress","finishedAt":"2026-11-12T11:00:00"}'
    ) -join "`n") + "`n", $utf8)
    Assert-Equal "$((Get-IdleRunSeries -Id 'T1' -Refresh).Count)/$(Test-IdleRunHeld -Id 'T1')" '2/True' 'idle: a profile naming the old spelling counts old and new rows'

    # ---- 2. recovery of a dead worker ----
    $null = Initialize-PqRoot
    $runDir = Join-Path $portfolio 'run'
    $null = [IO.Directory]::CreateDirectory($runDir)
    $runsFile = Join-Path $portfolio 'runs.jsonl'
    $now = [DateTimeOffset]::UtcNow
    $start = $now.AddMinutes(-120)
    $beatTime = $now.AddMinutes(-100)
    Set-PqClock -Now { $beatTime }
    $beatLog = Open-PqLog -Writer 'w2' -Run 'R-dead'
    $null = Write-PqEvent -Log $beatLog -Ev 'pass.beat' -Run 'R-dead' -Repo 'demo' -Id 'S0001' -Pass 'R-dead.1' -Worker 2 -D @{ elapsed = 60 }
    $null = Write-PqEvent -Log $beatLog -Ev 'pass.beat' -Run 'R-dead' -Repo 'demo' -Id 'S0002' -Pass 'R-dead.0' -Worker 2 -D @{ elapsed = 60 }
    Close-PqLog -Log $beatLog
    Reset-PqClock
    $iso = "yyyy-MM-dd'T'HH:mm:ss.fff'Z'"
    $dead = [pscustomobject]@{ pid = 99999999; repository = 'demo'; ticket = 'S0001'; agent = 'claude'; since = $start.AddMinutes(-1).UtcDateTime.ToString($iso)
        run = 'R-dead'; pass = 'R-dead.1'; passSince = $start.UtcDateTime.ToString($iso); statusBefore = 'Approved'; model = 'sonnet' }
    Reclaim-PqDeadWorker -WorkerState $dead -Slot 2 -Root $portfolio 6>$null
    $row = (Read-Rows $runsFile)[-1]
    Assert-Equal $row.finishedAt $beatTime.LocalDateTime.ToString($clockFormat) 'reclaim: the row ends at the last beat of the pass'
    Assert-Equal "$($row.minutes)/$($row.outcome)" '20/orphaned' 'reclaim: the minutes count from the start to that beat'
    Assert-Equal ([Math]::Abs([double]$row.detectedAfterMinutes - 100) -lt 1) $true 'reclaim: the detection lag is recorded apart'
    Assert-Equal "$($row.run)/$($row.pass)/$($row.model)/$($row.statusBefore)" 'R-dead/R-dead.1/sonnet/Approved' 'reclaim: run, pass, model and statusBefore come from the worker state'
    $end = @((Read-PqWindowEvents -Root $portfolio).events | Where-Object { $_.ev -ceq 'pass.end' })[-1]
    Assert-Equal "$($end.pass)/$($end.d.elapsed)/$($end.d.outcome)" 'R-dead.1/1200/orphaned' 'reclaim: pass.end carries the same elapsed time'

    $lockFile = Join-Path $runDir 'repo-demo.lock'
    [IO.File]::WriteAllText($lockFile, '{"pid":99999999}', $utf8)
    $lockTime = $now.AddMinutes(-90).UtcDateTime
    [IO.File]::SetLastWriteTimeUtc($lockFile, $lockTime)
    $noBeat = [pscustomobject]@{ pid = 99999999; repository = 'demo'; ticket = 'S0003'; agent = 'codex'; since = $start.UtcDateTime.ToString($iso)
        run = 'R-lock'; pass = 'R-lock.1'; passSince = $start.UtcDateTime.ToString($iso); statusBefore = 'Draft'; model = '' }
    Reclaim-PqDeadWorker -WorkerState $noBeat -Slot 3 -Root $portfolio 6>$null
    $row = (Read-Rows $runsFile)[-1]
    Assert-Equal "$($row.finishedAt)/$($row.minutes)" "$($lockTime.ToLocalTime().ToString($clockFormat))/30" 'reclaim: with no beat the row ends at the repository lock time'

    [IO.File]::Delete($lockFile)
    $old = [pscustomobject]@{ pid = 99999999; repository = 'demo'; ticket = 'S0004'; agent = 'claude'; since = $start.UtcDateTime.ToString($iso) }
    Reclaim-PqDeadWorker -WorkerState $old -Slot 4 -Root $portfolio 6>$null
    $row = (Read-Rows $runsFile)[-1]
    Assert-Equal "$($row.run)/$($row.pass)/$($row.minutes)/$($row.finishedAt)" "R-orphaned/P-orphaned-w4/0/$($start.LocalDateTime.ToString($clockFormat))" 'reclaim: a state of an older worker ends where it started'

    # ---- 3. the worker state and the beat ----
    Set-PqWorkerState -Slot 5 -Repo 'demo' -Ticket 'S0001' -Agent 'claude'
    Set-PqWorkerPass -Slot 5 -Run 'R-live' -Pass 'R-live.1' -StatusBefore 'Draft' -Model 'opus'
    Update-PqWorkerSeen -Slot 5
    $state = Read-PqState (Join-Path $runDir 'worker-5.json')
    Assert-Equal "$($state.pass)/$($state.statusBefore)/$($state.model)/$($state.ticket)/$([bool]$state.passSince)" 'R-live.1/Draft/opus/S0001/True' 'worker: the pass facts survive a seen refresh'
    $beats = @{}
    $due = @(1..11 | ForEach-Object { 60 * $_ } | Where-Object { Test-PqBeatDue $beats $_ })
    Assert-Equal ($due -join ',') '60,360,660' 'beat: one pass.beat per five minutes'

    # ---- 4. the retry walk ----
    $t0 = [datetime]::Now.AddHours(-5)
    $script:n = 0
    function New-Offer([string] $Before, [string] $After, [string] $Outcome = 'ok') {
        $script:n++
        return [pscustomobject]@{ repo = 'demo'; id = 'S0001'; statusBefore = $Before; statusAfter = $After; outcome = $Outcome; finishedAt = $t0.AddMinutes($script:n).ToString($clockFormat) }
    }
    function Test-Stuck($Rows) { return ($null -ne (Get-PqStuckOffers -Rows $Rows)) }
    Assert-Equal (Test-Stuck @((New-Offer 'Draft' 'Draft'), (New-Offer 'Draft' 'Draft'))) $false 'walk: two offers never hold'
    Assert-Equal (Test-Stuck @((New-Offer 'Draft' 'Draft'), (New-Offer 'Draft' 'Draft'), (New-Offer 'Draft' 'Draft'))) $true 'walk: three unmoved offers hold'
    Assert-Equal (Test-Stuck @((New-Offer 'Draft' 'Approved'), (New-Offer 'Approved' 'Tactical'), (New-Offer 'Tactical' 'Implemented'))) $false 'walk: a ticket that advances is not held'
    Assert-Equal (Test-Stuck @((New-Offer 'In Progress' 'Partial'), (New-Offer 'Partial' 'In Progress'), (New-Offer 'In Progress' 'Partial'), (New-Offer 'Partial' 'In Progress'))) $true 'walk: moving there and back is no advance'
    Assert-Equal (Test-Stuck @((New-Offer 'Draft' 'Tactical'), (New-Offer 'Tactical' 'Tactical'), (New-Offer 'Tactical' 'Tactical'), (New-Offer 'Tactical' 'Tactical'))) $true 'walk: an advance followed by three standstills holds'
    Assert-Equal (Test-Stuck @((New-Offer 'Draft' 'Draft'), (New-Offer 'Draft' 'Draft'), (New-Offer 'Draft' 'Approved'))) $false 'walk: an advance of the newest offer frees the ticket'
    Assert-Equal (Test-Stuck @((New-Offer 'Draft' 'Draft' 'limit-hit'), (New-Offer 'Draft' 'Draft' 'launch-failed'), (New-Offer 'Draft' 'Draft' 'halted'), (New-Offer 'Draft' 'Draft'), (New-Offer 'Draft' 'Draft'))) $false 'walk: a limit, a failed launch and a halt are no offers'
    Assert-Equal (Test-Stuck @((New-Offer 'Draft' '' 'orphaned'), (New-Offer '' '' 'orphaned'), (New-Offer 'Draft' 'Draft'), (New-Offer 'Draft' 'Draft'))) $true 'walk: a recovered row counts by its starting status'

    # ---- 5. the rank ----
    $spec = Join-Path $repo 'PLAN/S0001_task.md'
    [IO.File]::WriteAllText($spec, "# S0001`n", $utf8)
    [IO.File]::SetLastWriteTime($spec, [datetime]::Now.AddHours(-10))
    [IO.File]::WriteAllText((Join-Path $repo 'PLAN/spec-catalog.jsonl'), '{"id":"S0001","status":"Draft","file":"PLAN/S0001_task.md","updated":"2026-11-11 10:00"}' + "`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $repo 'PLAN/spec-catalog-archive.jsonl'), '', $utf8)
    $reg = [ordered]@{ maxWorkers = 1; fill = 'depth'; repos = @(@{ key = 'demo'; path = $repo; enabled = $true }) }
    function Write-Offers([datetime] $From, [int] $Count) {
        $lines = @(1..$Count | ForEach-Object { @{ repo = 'demo'; id = 'S0001'; statusBefore = 'Draft'; statusAfter = 'Draft'; outcome = 'ok'; finishedAt = $From.AddMinutes($_).ToString($clockFormat) } | ConvertTo-Json -Compress })
        [IO.File]::WriteAllText($runsFile, (($lines -join "`n") + "`n"), $utf8)
    }
    function Get-PqKnownKeys($Registry) { return [string[]]@('demo') }
    function Read-PqQueueFile { param($Path, $KnownRepos, $TicketLookup) return @{ rows = @(); held = @(); bad = @() } }
    function Get-PqQueuePath($Registry) { return (Join-Path $portfolio 'PORTFOLIO_QUEUE.md') }
    function Get-PqOccupiedRepos { param($Registry, [switch]$ReadOnly) return [string[]]@() }
    function Get-PqStoppedRepos($Registry) { return [string[]]@() }
    function Get-PqIntakeCapped($Registry) { return [string[]]@() }
    function Get-PqPickerHead {
        param($RepoPath, $HarnessRoot, $Cache, $Exclude, $ForceId)
        $id = if ($ForceId) { $ForceId } elseif (@($Exclude) -ccontains 'S0001') { 'S0002' } else { 'S0001' }
        return @{ ok = $true; head = @{ id = $id; status = 'Draft'; name = $id; priority = 50 }; payload = $null }
    }
    Write-Offers ([datetime]::Now.AddHours(-3)) 2
    Assert-Equal (Get-PqNextRank -Registry $reg -Slots 1 -StopAfter 1).candidates[0].id 'S0001' 'rank: the third offer is made'
    Write-Offers ([datetime]::Now.AddHours(-3)) 3
    $rank = Get-PqNextRank -Registry $reg -Slots 1 -StopAfter 1
    Assert-Equal "$($rank.candidates[0].id)/$(@($rank.thrashHeld)[0].key)/$(@($rank.thrashHeld)[0].passes)" 'S0002/demo:S0001/3' 'rank: the fourth offer is held and named'
    Assert-Equal (Get-PqNextRank -Registry $reg -Slots 1 -StopAfter 1 -NamedTicket 'demo:S0001').candidates[0].id 'S0001' 'rank: a named start passes the bound'
    [IO.File]::SetLastWriteTime($spec, [datetime]::Now.AddHours(-1))
    Assert-Equal (Get-PqNextRank -Registry $reg -Slots 1 -StopAfter 1).candidates[0].id 'S0001' 'rank: an edit of the spec lifts the hold'
    [IO.File]::SetLastWriteTime($spec, [datetime]::Now.AddHours(-40))
    Write-Offers ([datetime]::Now.AddHours(-26)) 3
    Assert-Equal @(Get-PqThrashHeld $reg).Count 0 'rank: offers older than 24 hours expire'
    Assert-Equal (Get-PqWaitReasons -Rank @{ skipped = @(); autoSkipReasons = $null } -Thrash 2)['thrash'] 2 'rank: a waiting worker counts the held tickets'

    # ---- 6. an unchanged blocker result ----
    $xd = [ordered]@{ blocked = 'demo:S0005'; blocker = 'other:S0001'; state = 'open'; blockerStatus = 'Draft'; root = 'other:S0002'; rootStatus = 'Draft'; lift = 'offered' }
    $sig = Get-PqXrepoSignature $xd
    Assert-Equal "$(Request-PqSay 'xrepo-said' 'demo:S0005' $sig)/$(Request-PqSay 'xrepo-said' 'demo:S0005' $sig)" 'True/False' 'xrepo: the same result is said once'
    Assert-Equal (Request-PqSay 'xrepo-said' 'demo:S0005' (Get-PqXrepoSignature $xd -Head) -Prefix) $false 'xrepo: a look without the chain adds nothing'
    $xd.blockerStatus = 'Approved'
    Assert-Equal (Request-PqSay 'xrepo-said' 'demo:S0005' (Get-PqXrepoSignature $xd)) $true 'xrepo: a changed blocker is news'
    $sayLog = Open-PqLog -Writer 'w6' -Run 'R-say'
    $first = Write-PqUnblocked -Log $sayLog -Run 'R-say' -Repo 'demo' -Id 'S0005' -Worker 6
    $second = Write-PqUnblocked -Log $sayLog -Run 'R-say' -Repo 'demo' -Id 'S0005' -Worker 6
    Close-PqLog -Log $sayLog
    $said = @((Read-PqWindowEvents -Root $portfolio).events | Where-Object { $_.wr -ceq 'w6' })
    Assert-Equal "$first/$second/$(($said | ForEach-Object { $_.ev }) -join ',')/$($said[-1].d.blocker)" 'True/False/xrepo.resolve,ticket.unblocked/other:S0001' 'xrepo: the release is written once'

    # ---- 7. the archive ----
    $logDir = Join-Path $portfolio 'log'
    $oldDay = [DateTime]::UtcNow.AddDays(-20)
    $edgeDay = [DateTime]::UtcNow.AddDays(-14).ToString('yyyy-MM-dd')
    $mk = { param($Seq, $Writer, $Id) @{ v = 1; ts = $oldDay.ToString('yyyy-MM-dd') + 'T10:00:00.000Z'; seq = $Seq; wr = $Writer; run = 'r'; ev = 'ticket.created'; repo = 'demo'; id = $Id; pass = $null; worker = $null; agent = $null; model = $null; cx = $null; d = @{} } | ConvertTo-Json -Compress }
    $oldA = Join-Path $logDir "events-$($oldDay.ToString('yyyy-MM-dd')).w1.jsonl"
    $oldB = Join-Path $logDir "events-$($oldDay.ToString('yyyy-MM-dd')).w3.jsonl"
    $edge = Join-Path $logDir "events-$edgeDay.w1.jsonl"
    [IO.File]::WriteAllText($oldA, (& $mk 1 'w1' 'S0007') + "`n", $utf8)
    [IO.File]::WriteAllText($oldB, (& $mk 1 'w3' 'S0007') + "`n", $utf8)
    [IO.File]::WriteAllText($edge, '', $utf8)
    $writer = [IO.FileStream]::new($oldB, 'Open', 'Write', 'Read')
    try { $moved = Invoke-PqLogArchive -Root $portfolio }
    finally { $writer.Dispose() }
    Assert-Equal "$($moved.days)/$($moved.files)/$([IO.File]::Exists($oldA))/$([IO.File]::Exists($oldB))/$([IO.File]::Exists($edge))" '1/1/False/True/True' 'archive: an old closed file is zipped; a held one and day 14 stay'
    Assert-Equal @(Get-PqTrace -Root $portfolio -Repo 'demo' -Id 'S0007').Count 2 'archive: a trace reads the zipped and the plain file'
    $moved = Invoke-PqLogArchive -Root $portfolio
    $day = Merge-PqDay -Root $portfolio -Date $oldDay.ToString('yyyy-MM-dd')
    Assert-Equal "$($moved.files)/$([IO.File]::Exists($oldB))/$($day.events.Count)/$($day.bad)/$($day.files.Count)" '1/False/2/0/2' 'archive: the next run adds to the day archive'
    Assert-Equal (Invoke-PqLogArchive -Root $portfolio).files 0 'archive: nothing left to move'

    # ---- 8. findings and paths ----
    $runs = @([pscustomobject]@{ repo = 'demo'; id = 'S0001'; pass = 'R.1'; outcome = 'claim-lost' })
    $events = @([pscustomobject]@{ ev = 'tripwire.trip'; seq = 1; wr = 'w1'; d = @{} }, [pscustomobject]@{ ev = 'pass.stall'; seq = 2; wr = 'w1'; d = @{} })
    $found = @(Get-PqFindings -Runs $runs -Events $events -Gaps @())
    Assert-Equal "$(($found | ForEach-Object { $_.fid }) -join ',')|$($found[0].evidence -join ',')" 'PQ-RACE01|run demo:S0001 R.1' 'findings: the race points at its rows; no finding over reserved events'
    $gone = @('live', 'livePass' | Where-Object { $kind = $_; try { $null = Get-PqPath -Kind $kind; $false } catch { $true } })
    Assert-Equal ($gone -join ',') 'live,livePass' 'paths: the live pass log has no path'
}
catch {
    $script:failed++
    Write-Host "FAIL unexpected: $($_.Exception.Message) at $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
}
finally {
    Reset-PqClock
    $env:SZA_PORTFOLIO_ROOT = $priorRoot
    $env:SZA_PROJECT_ROOT = $priorProject
    if ([IO.Directory]::Exists($scratch)) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Host "pq-records: $($script:passed) passed, $($script:failed) failed"
if ($script:failed -gt 0) { exit 1 }
exit 0
