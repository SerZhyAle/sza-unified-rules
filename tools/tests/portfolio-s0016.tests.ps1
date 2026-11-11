#requires -Version 7.0
<#
.SYNOPSIS
    Fast direct-call proof for the S0016 pieces built on 2026-11-10/11 (the "direct-s0016.ps1" checks, committed).

.DESCRIPTION
    One scratch portfolio root (SZA_PORTFOLIO_ROOT), no real registry, no agent process, no loop run:

      1.  Resources (R65, D17: build 3, emulator 1, device never): the verify-level map, the level read from a spec,
          the token caps, all-or-nothing, a foreign pass's claim rejected, stale tokens cleared, release by owner only,
          device never offered.
      2.  Waiting (R29-R34): the fingerprint parts, change detection per file kind, a lease heartbeat rewrite is not a
          change, the drop fingerprint on the spec file, the wait `why` counts, drop-lift thrash.
      3.  Stop and console (R54-R56): level ranks, stop file parsing, the most severe applicable stop, busy targets,
          target completion (repo stop leaves a hold), pause, transcript record formatting, Read-PqTail offset/carry.
      4.  Analysis (R44-R48): run rows, stats, the n >= 5 split rule, findings with stable ids severity-first, seq gaps
          and unparsable/unsupported lines, trace, compare verdict, CSV.
      5.  The loop wiring of the 2026-11-10 pieces (source-level, as portfolio-occupancy case 4 does).

    Everything runs in-process; the only child process is one sleeper used as a foreign token owner. Target: seconds.
#>
$ErrorActionPreference = 'Stop'
$lib = Join-Path (Split-Path $PSScriptRoot -Parent) 'harness/portfolio/lib'
. (Join-Path $lib 'paths.ps1')
. (Join-Path $lib 'events.ps1')
. (Join-Path $lib 'registry.ps1')
. (Join-Path $lib 'ledger-watch.ps1')
. (Join-Path $lib 'loop.ps1')
. (Join-Path $lib 'picker.ps1')
. (Join-Path $lib 'occupancy.ps1')
. (Join-Path $lib 'resources.ps1')
. (Join-Path $lib 'waiting.ps1')
. (Join-Path $lib 'stop.ps1')
. (Join-Path $lib 'console.ps1')
. (Join-Path $lib 'analysis.ps1')
. (Join-Path $lib 'xrepo.ps1')

# waiting.ps1/loop.ps1 call Get-PqQueuePath, which lives in pq.ps1; the suite does not dot-source the CLI script.
if (-not (Get-Command Get-PqQueuePath -ErrorAction SilentlyContinue)) {
    function Get-PqQueuePath($Registry) {
        $q = Get-PqValue (Get-PqValue $Registry 'paths') 'portfolioQueue'
        if ($q) { if ([IO.Path]::IsPathRooted([string]$q)) { return [string]$q }; return (Join-Path (Get-PqRoot) $q) }
        return (Join-Path (Get-PqRoot) 'PORTFOLIO_QUEUE.md')
    }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('pq-s0016-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($scratch)
$origEnv = $env:SZA_PORTFOLIO_ROOT
$env:SZA_PORTFOLIO_ROOT = $scratch
$root = Initialize-PqRoot
$case = 0
function Check([bool]$Cond, [string]$What) { if (-not $Cond) { throw "case $($script:case): $What" } }
function Case([string]$Name) { $script:case++; Write-Host "Case $($script:case): $Name..." -NoNewline }

$sleeper = $null
try {
    # ---- a fixture repository: ledger with one Draft, its spec with a Verify line, the queue files ----
    $repo = Join-Path $scratch 'demo-repo'
    foreach ($d in @('PLAN', 'temp/SPEC-TICKET.LEASES')) { $null = [IO.Directory]::CreateDirectory((Join-Path $repo $d)) }
    $specEmulator = Join-Path $repo 'PLAN\S0001_task-one.md'
    [IO.File]::WriteAllText($specEmulator, "# S0001`n`n**Verify:** emulator - needs a device run`n`nbody`n", [Text.Encoding]::UTF8)
    $specPlain = Join-Path $repo 'PLAN\S0002_task-two.md'
    [IO.File]::WriteAllText($specPlain, "# S0002`n`nno verify line here`n", [Text.Encoding]::UTF8)
    $ledger = Join-Path $repo 'PLAN\spec-catalog.jsonl'
    [IO.File]::WriteAllText($ledger, (@(
        '{"id":"S0001","name":"task one","status":"Draft","priority":80,"file":"PLAN/S0001_task-one.md","created":"2026-11-11","updated":"2026-11-11 10:00"}'
        '{"id":"S0002","name":"task two","status":"Draft","priority":50,"file":"PLAN/S0002_task-two.md","created":"2026-11-11","updated":"2026-11-11 10:00"}'
    ) -join "`n") + "`n", [Text.Encoding]::UTF8)
    foreach ($f in @('PLAN\spec-catalog-archive.jsonl', 'PLAN\RELEASE_QUEUE.md', 'PLAN\RELEASE_READY.md', 'PLAN\RELEASE_QUEUE_DONE.md')) {
        [IO.File]::WriteAllText((Join-Path $repo $f), '', [Text.Encoding]::UTF8)
    }
    $reg = [ordered]@{ schemaVersion = '1.0'; repos = @(@{ key = 'demo'; path = $repo; enabled = $true }) }

    # ================= 1. resources =================
    Case 'resource token map by verify level' {
        Check ((@((Get-PqVerifyTokens 'edit'))).Count -eq 0) 'edit takes no token'
        Check ((Get-PqVerifyTokens 'build') -join ',') -ceq 'build' 'build takes build'
        Check ((Get-PqVerifyTokens 'emulator') -join ',') -ceq 'build,emulator' 'emulator takes build and emulator'
        Check ((@((Get-PqVerifyTokens 'device'))).Count -eq 0) 'device takes no token (it is never offered)'
    }
    Case 'verify level read from the spec (first 40 lines, in doubt build)' {
        Check ((Get-PqTicketVerify -RepoPath $repo -TicketId 'S0001') -ceq 'emulator') 'S0001 has the Verify line -> emulator'
        Check ((Get-PqTicketVerify -RepoPath $repo -TicketId 'S0002') -ceq 'build') 'no line -> build'
        Check ((Get-PqTicketVerify -RepoPath $repo -TicketId 'S9999') -ceq 'build') 'unknown ticket -> build'
    }
    Case 'build cap 3 (the default of D17), all-or-nothing, re-ask by the same ticket is allowed' {
        $r1 = Request-PqResources -Registry $reg -RepoKey 'demo' -TicketId 'S0001' -Verify 'build' -PassId 'p1'
        Check ($r1.ok -and ($r1.held -join ',') -ceq 'build') "first build token taken: $($r1 | ConvertTo-Json -Compress)"
        $again = Request-PqResources -Registry $reg -RepoKey 'demo' -TicketId 'S0001' -Verify 'build' -PassId 'p1'
        Check ($again.ok) 'the same ticket asking again gets its own token'
        $r2 = Request-PqResources -Registry $reg -RepoKey 'demo' -TicketId 'S0002' -Verify 'build' -PassId 'p2'
        $r3 = Request-PqResources -Registry $reg -RepoKey 'demo' -TicketId 'S0003' -Verify 'build' -PassId 'p3'
        Check ($r2.ok -and $r3.ok) 'tokens 2 and 3 taken'
        $r4 = Request-PqResources -Registry $reg -RepoKey 'demo' -TicketId 'S0004' -Verify 'build' -PassId 'p4'
        Check (-not $r4.ok -and $r4.why -ceq 'resource' -and $r4.heldCount -eq 3 -and $r4.cap -eq 3) "the 4th build token is refused (cap 3): $($r4 | ConvertTo-Json -Compress)"
        Check (-not [IO.File]::Exists((Get-PqPath -Kind resourceToken -Token 'build' -Repo 'demo' -Id 'S0004'))) 'the refused ticket holds no token file'
    }
    Case 'emulator cap 1, and an emulator ticket that cannot get its tokens takes nothing' {
        $big = [ordered]@{ resources = @{ build = 10; emulator = 1 } }
        $e1 = Request-PqResources -Registry $big -RepoKey 'demo' -TicketId 'S0010' -Verify 'emulator' -PassId 'p10'
        Check ($e1.ok -and ($e1.held -join ',') -ceq 'build,emulator') 'emulator ticket takes build and emulator'
        $e2 = Request-PqResources -Registry $big -RepoKey 'demo' -TicketId 'S0011' -Verify 'emulator' -PassId 'p11'
        Check (-not $e2.ok -and $e2.resource -ceq 'emulator' -and $e2.cap -eq 1) "the second emulator token is refused (cap 1): $($e2 | ConvertTo-Json -Compress)"
        $holdsNeither = (-not [IO.File]::Exists((Get-PqPath -Kind resourceToken -Token 'build' -Repo 'demo' -Id 'S0011'))) -and (-not [IO.File]::Exists((Get-PqPath -Kind resourceToken -Token 'emulator' -Repo 'demo' -Id 'S0011')))
        Check $holdsNeither 'all-or-nothing: the refused emulator ticket holds neither token'
    }
    Case 'device level is never offered to a robot' {
        $d = Request-PqResources -Registry $reg -RepoKey 'demo' -TicketId 'S0012' -Verify 'device' -PassId 'p12'
        Check (-not $d.ok -and $d.why -ceq 'deviceLevel') "device -> why=deviceLevel: $($d | ConvertTo-Json -Compress)"
    }
    Case "another pass's claim on the same ticket is rejected, a stale owner's token is cleared, only the owner releases" {
        $sleeper = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep 60') -PassThru
        $foreign = Get-PqPath -Kind resourceToken -Token 'build' -Repo 'demo' -Id 'S0020'
        $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $foreign))
        [IO.File]::WriteAllText($foreign, (@{ token = 'build'; repo = 'demo'; id = 'S0020'; pid = $sleeper.Id; pass = 'pForeign'; at = '2026-11-11T10:00:00.000Z' } | ConvertTo-Json -Compress), [Text.Encoding]::UTF8)
        $fx = Request-PqResources -Registry $reg -RepoKey 'demo' -TicketId 'S0020' -Verify 'build' -PassId 'pMine'
        Check (-not $fx.ok -and $fx.why -ceq 'resource') "the foreign pass's token blocks the same ticket: $($fx | ConvertTo-Json -Compress)"
        $dead = Get-PqPath -Kind resourceToken -Token 'build' -Repo 'demo' -Id 'S0021'
        [IO.File]::WriteAllText($dead, (@{ token = 'build'; repo = 'demo'; id = 'S0021'; pid = 999999; procStart = '2026-11-11T09:00:00.0000000Z'; pass = 'pDead'; at = '2026-11-11T09:00:00.000Z' } | ConvertTo-Json -Compress), [Text.Encoding]::UTF8)
        $h = Get-PqResourceHeld -Token 'build' -ClearStale
        Check (($h.stale -join ',') -ccontains 'demo__S0021') "the dead owner's token was cleared: $($h.stale -join ',')"
        Check (-not [IO.File]::Exists($dead)) 'the stale token file is gone'
        $rel = Remove-PqResources -RepoKey 'demo' -TicketId 'S0020'
        Check (@($rel).Count -eq 0 -and [IO.File]::Exists($foreign)) 'Remove-PqResources does not remove another process token'
        $rel1 = Remove-PqResources -RepoKey 'demo' -TicketId 'S0001'
        Check ($rel1 -ccontains 'build' -and -not [IO.File]::Exists((Get-PqPath -Kind resourceToken -Token 'build' -Repo 'demo' -Id 'S0001'))) 'the owner releases its own token'
        Stop-Process -Id $sleeper.Id -Force -ErrorAction SilentlyContinue
    }

    # ================= 2. waiting =================
    Case 'fingerprint covers the registry, the queue, holds, resources and every enabled repository' {
        $fp = Get-PqFingerprint -Registry $reg -PathsCache @{}
        foreach ($p in @('registry', 'portfolioQueue', 'holds', 'resources', 'demo/ledger', 'demo/archive', 'demo/queue', 'demo/ready', 'demo/done', 'demo/leases', 'demo/stop')) {
            Check ($fp.Contains($p)) "fingerprint part '$p' missing"
        }
        $cmp = Compare-PqFingerprint -Old $fp -New $fp
        Check (-not $cmp.changed -and @($cmp.files).Count -eq 0) 'an identical fingerprint is no change'
    }
    Case 'a ledger write is a change naming the repository and kind; a lease heartbeat rewrite is not' {
        $fp1 = Get-PqFingerprint -Registry $reg -PathsCache @{}
        [IO.File]::AppendAllText($ledger, '{"id":"S0003","name":"task three","status":"Draft","priority":10,"file":"PLAN/S0003_task-three.md","created":"2026-11-11","updated":"2026-11-11 11:00"}' + "`n", [Text.Encoding]::UTF8)
        $fp2 = Get-PqFingerprint -Registry $reg -PathsCache @{}
        $cmp = Compare-PqFingerprint -Old $fp1 -New $fp2
        Check ($cmp.changed -and ($cmp.files -ccontains 'ledger') -and ($cmp.repos -ccontains 'demo')) "ledger change detected: $($cmp.files -join ',') / $($cmp.repos -join ',')"
        $lease = Join-Path $repo 'temp\SPEC-TICKET.LEASES\S0001.json'
        [IO.File]::WriteAllText($lease, '{"holder":"x"}', [Text.Encoding]::UTF8)
        $fp3 = Get-PqFingerprint -Registry $reg -PathsCache @{}
        $cmp2 = Compare-PqFingerprint -Old $fp2 -New $fp3
        Check ($cmp2.changed -and ($cmp2.files -ccontains 'leases')) 'a new lease name is a change'
        [IO.File]::WriteAllText($lease, '{"holder":"heartbeat rewrite"}', [Text.Encoding]::UTF8)  # same name, new content
        $fp4 = Get-PqFingerprint -Registry $reg -PathsCache @{}
        $cmp3 = Compare-PqFingerprint -Old $fp3 -New $fp4
        Check (-not $cmp3.changed) 'a lease heartbeat rewrite (same name) is not a change'
    }
    Case 'the drop fingerprint follows the dropped ticket spec file only' {
        $drops = @{ 'demo:S0001' = @{ repo = 'demo'; id = 'S0001'; mark = @{ specFile = $specEmulator; status = 'Draft'; updated = '2026-11-11 10:00' } } }
        $dfp = Get-PqDropFingerprint $drops
        Check ($dfp.Contains('demo/spec') -and $dfp['demo/spec'] -match 'S0001=') "drop fingerprint: $($dfp['demo/spec'])"
        $before = $dfp['demo/spec']
        [IO.File]::SetLastWriteTimeUtc($specEmulator, [DateTime]::UtcNow.AddSeconds(5))
        $dfp2 = Get-PqDropFingerprint $drops
        Check ($dfp2['demo/spec'] -cne $before) 'touching the spec file lifts the drop in the fingerprint'
    }
    Case 'wait.enter why counts: skipped reasons, auto-skips, dropped, xrepo, transient; empty means none' {
        $rank = @{ skipped = @(@{ why = 'hold' }, @{ why = 'occupied' }, @{ why = 'disabled' }, @{ why = 'leased' }); autoSkipReasons = @{ blocked = 2 } }
        $why = Get-PqWaitReasons -Rank $rank -Dropped 1 -Xrepo 1 -Transient @{ t = @{ why = 'resource' } }
        Check ($why['held'] -eq 1 -and $why['occupied'] -eq 1 -and $why['leased'] -eq 1 -and $why['blocked'] -eq 2 -and $why['dropped'] -eq 1 -and $why['xrepo'] -eq 1 -and $why['resource'] -eq 1) "why counts: $($why | ConvertTo-Json -Compress)"
        Check (-not $why.Contains('disabled')) 'a disabled repository is not a wait reason'
        $none = Get-PqWaitReasons -Rank @{ skipped = @(); autoSkipReasons = @{} }
        Check ($none['none'] -eq 1) 'nothing held back -> none=1'
    }
    Case 'drop-lift thrash: the 3rd lift inside the window holds the ticket' {
        $lifts = @{}
        $now = [datetime]::UtcNow
        $a = Register-PqLift -Lifts $lifts -Key 'demo:S0001' -Now $now
        $b = Register-PqLift -Lifts $lifts -Key 'demo:S0001' -Now $now.AddMinutes(10)
        $c = Register-PqLift -Lifts $lifts -Key 'demo:S0001' -Now $now.AddMinutes(20)
        Check (-not $a.thrash -and -not $b.thrash -and $c.thrash -and $c.count -eq 3) "thrash at the 3rd lift: $($c | ConvertTo-Json -Compress)"
        $old = Register-PqLift -Lifts $lifts -Key 'demo:S0002' -Now $now.AddHours(-2)
        $fresh = Register-PqLift -Lifts $lifts -Key 'demo:S0002' -Now $now
        Check ($fresh.count -eq 1 -and -not $fresh.thrash) 'lifts outside the 60-minute window are forgotten'
    }

    # ================= 3. stop and console =================
    Case 'stop level ranks: drain < pass (default) < halt < kill' {
        Check ((Get-PqStopLevelRank 'drain') -eq 1 -and (Get-PqStopLevelRank 'pass') -eq 2 -and (Get-PqStopLevelRank 'halt') -eq 3 -and (Get-PqStopLevelRank 'kill') -eq 4 -and (Get-PqStopLevelRank 'junk') -eq 2) 'ranks'
    }
    Case 'stop files parse into kind/target/level; the most severe applicable stop wins; busy targets' {
        $w = { param($file, $level) [IO.File]::WriteAllText($file, (@{ level = $level; by = 'owner'; at = '2026-11-11T12:00:00.000Z'; reason = 'owner' } | ConvertTo-Json -Compress), [Text.Encoding]::UTF8) }
        & $w (Join-Path $root 'STOP') 'kill'
        & $w (Get-PqPath -Kind stopTarget -StopKind worker -Target '2') 'pass'
        & $w (Get-PqPath -Kind stopTarget -StopKind repo -Target 'demo') 'halt'
        & $w (Get-PqPath -Kind stopTarget -StopKind ticket -Target 'demo__S0001') 'drain'
        [IO.File]::WriteAllText((Join-Path $root 'STOP-junk'), '{}', [Text.Encoding]::UTF8)
        $stops = Get-PqStopFiles
        Check (@($stops).Count -eq 4) "4 stop files parsed, the junk one skipped: $(@($stops).Count)"
        $byKind = @{}; foreach ($s in $stops) { $byKind[$s.kind] = $s }
        Check ($byKind['all'].level -ceq 'kill' -and $byKind['worker'].target -ceq '2' -and $byKind['repo'].target -ceq 'demo' -and $byKind['ticket'].target -ceq 'demo:S0001') 'kinds and targets'
        $app = Get-PqApplicableStop -Stops $stops -Slot 3 -Repo 'demo' -Agent 'claude' -Ticket 'demo:S0001'
        Check ($app.kind -ceq 'all' -and $app.level -ceq 'kill') 'the whole-portfolio kill wins over every target'
        Remove-Item -LiteralPath (Join-Path $root 'STOP') -Force
        $app2 = Get-PqApplicableStop -Stops (Get-PqStopFiles) -Slot 2 -Repo 'demo' -Agent 'claude' -Ticket 'demo:S0001'
        Check ($app2.kind -ceq 'repo' -and $app2.level -ceq 'halt') "halt (repo) outranks pass (worker 2): $($app2.kind)/$($app2.level)"
        $app3 = Get-PqApplicableStop -Stops (Get-PqStopFiles) -Slot 3 -Repo '' -Agent '' -Ticket ''
        Check ($null -eq $app3) 'no target stop names worker 3 with no repo/ticket'
        $workers = @(
            [pscustomobject]@{ slot = 2; repository = 'demo'; ticket = 'S0001'; agent = 'claude'; key = 'demo:S0001' }
            [pscustomobject]@{ slot = 3; repository = 'other'; ticket = 'S0009'; agent = 'codex'; key = 'other:S0009' }
        )
        Check ((Test-PqStopTargetBusy -Stop $byKind['worker'] -Workers $workers)) 'worker 2 is busy'
        Check (-not (Test-PqStopTargetBusy -Stop (@{ kind = 'agent'; target = 'gemini' }) -Workers $workers)) 'agent gemini is not busy'
        Check ((Test-PqStopTargetBusy -Stop $byKind['ticket'] -Workers $workers)) 'ticket demo:S0001 is busy'
    }
    Case 'a target stop completes: the file goes and a repo stop leaves a registry hold; STOP all never completes' {
        [IO.File]::WriteAllText((Get-PqPath -Kind registry), ([ordered]@{ schemaVersion = '1.0'; repos = @(@{ key = 'demo'; path = $repo; enabled = $true; hold = $false }) } | ConvertTo-Json -Depth 8), [Text.Encoding]::UTF8)
        $stops = Get-PqStopFiles
        $all = @($stops | Where-Object { $_.kind -ceq 'all' })[0]
        Complete-PqStop -Stop $all -Log $null
        Check ([IO.File]::Exists($all.file)) 'the whole-portfolio STOP is never completed by this'
        $repoStop = @($stops | Where-Object { $_.kind -ceq 'repo' })[0]
        Complete-PqStop -Stop $repoStop -Log $null
        Check (-not [IO.File]::Exists($repoStop.file)) 'the repo stop file is gone'
        $regDoc = ConvertFrom-Json ([IO.File]::ReadAllText((Get-PqPath -Kind registry))) -DateKind String
        Check ($regDoc.repos[0].hold -eq $true) 'the repository is left on hold in the registry'
    }
    Case 'pause: set once, test, clear once' {
        Check ((Set-PqPause)) 'first Set-PqPause returns true'
        Check (-not (Set-PqPause)) 'second Set-PqPause returns false'
        Check (Test-PqPaused) 'Test-PqPaused true'
        Check (Clear-PqPause) 'first Clear-PqPause returns true'
        Check (-not (Clear-PqPause) -and -not (Test-PqPaused)) 'cleared'
    }
    Case 'transcript records format to display lines; Read-PqTail follows by offset with a carried partial line' {
        Check ((Format-PqTranscriptRecord '{"type":"assistant","message":{"content":"hello world"}}') -join '|') -ceq '> hello world' 'assistant text'
        $tool = Format-PqTranscriptRecord '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"P:/x/y.md"}}]}}'
        Check ($tool[0] -cmatch '^\. Read P:/x/y\.md$') "tool_use: $($tool[0])"
        $err = Format-PqTranscriptRecord '{"type":"user","message":{"content":[{"type":"tool_result","is_error":true,"content":"boom"}]}}'
        Check ($err[0] -ceq '! boom') "tool error: $($err[0])"
        Check (@((Format-PqTranscriptRecord 'not json')).Count -eq 0) 'garbage gives nothing'
        $live = Join-Path $scratch 'live.log'
        [IO.File]::WriteAllText($live, "line1`npartial", [Text.Encoding]::UTF8)
        $t1 = Read-PqTail -Path $live -Offset 0 -Carry ''
        Check (($t1.lines -join '|') -ceq 'line1' -and $t1.carry -ceq 'partial') "first read: $($t1.lines -join '|') / carry='$($t1.carry)'"
        [IO.File]::AppendAllText($live, " rest`nline2`n", [Text.Encoding]::UTF8)
        $t2 = Read-PqTail -Path $live -Offset $t1.offset -Carry $t1.carry
        Check (($t2.lines -join '|') -ceq 'partial rest|line2') "second read joins the carried partial: $($t2.lines -join '|')"
    }

    # ================= 4. analysis =================
    Case 'run rows: read by window, stats, the report, the n>=5 split rule, compare verdict, CSV' {
        $runsPath = Join-Path $root 'runs.jsonl'
        $rows = [Collections.Generic.List[string]]::new()
        $nowIso = [DateTimeOffset]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'")
        for ($i = 1; $i -le 5; $i++) {
            $rows.Add((@{ finishedAt = $nowIso; run = 'r1'; pass = "p$i"; repo = 'demo'; id = "S00$i"; agent = 'claude'; model = 'sonnet'; complexity = 'medium'; statusBefore = 'Draft'; statusAfter = 'Approved'; moved = $true; outcome = 'ok'; exitCode = 0; minutes = 10 + $i; canon = '1'; plugin = '1'; registryHash = 'a'; profileHash = 'b' } | ConvertTo-Json -Compress))
        }
        $rows.Add((@{ finishedAt = $nowIso; run = 'r1'; pass = 'p6'; repo = 'demo'; id = 'S0006'; agent = 'codex'; model = 'gpt-6.1-terra'; complexity = 'hard'; statusBefore = 'Draft'; statusAfter = 'Draft'; moved = $false; outcome = 'failed'; exitCode = 1; minutes = 3; canon = '1'; plugin = '1'; registryHash = 'a'; profileHash = 'b' } | ConvertTo-Json -Compress))
        [IO.File]::WriteAllText($runsPath, (($rows.ToArray() -join "`n") + "`n"), [Text.Encoding]::UTF8)
        $runs = @(Read-PqRuns -Root $root -Since ([datetime]::UtcNow.AddHours(-1)))
        Check ($runs.Count -eq 6) "6 run rows read, got $($runs.Count)"
        $st = Get-PqRunStats $runs
        Check ($st.n -eq 6 -and $st.ok -eq 5 -and $st.okShare -eq 83.3 -and $st.minutesP50 -eq 12) "stats: $($st | ConvertTo-Json -Compress)"
        $rep = Get-PqReport -Root $root -Days 1
        Check ($rep.headline.n -eq 6 -and $rep.by_agent['claude'].n -eq 5 -and $rep.by_agent['claude'].okShare -eq 100) 'report headline and the claude split'
        Check ($rep.by_agent['codex'].note -ceq 'n too small') 'a split with n under 5 carries only a note'
        $cmp = Compare-PqRuns -Runs $runs -By 'agent'
        Check ($cmp.verdict -cmatch '^no evidence') "compare with n=1 under the min sample: $($cmp.verdict)"
        $csv = ConvertTo-PqRunCsv $runs
        $csvLines = $csv -split "`n"
        Check ($csvLines[0] -ceq 'finishedAt,run,pass,repo,id,agent,model,complexity,statusBefore,statusAfter,moved,outcome,exitCode,minutes,canon,plugin,registryHash,profileHash' -and $csvLines.Count -eq 7) 'CSV header and rows'
    }
    Case 'events: the window merge counts seq gaps, unparsable and unsupported lines; findings are severity-first with stable ids; trace filters one ticket' {
        $day = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-dd')
        $evFile = Join-Path $root "log\events-$day.w1.jsonl"
        $mk = {
            param([long]$Seq, [string]$Ev, [string]$Repo = '', [string]$Id = '', $D = @{})
            [ordered]@{ v = 1; ts = [DateTimeOffset]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'"); seq = $Seq; wr = 'w1'; run = 'r1'; ev = $Ev; repo = $Repo; id = $Id; pass = 'p1'; worker = 1; agent = 'claude'; model = 'sonnet'; cx = ''; d = $D } | ConvertTo-Json -Compress -Depth 8
        }
        $lines = @(
            (& $mk 1 'claim.lost' 'demo' 'S0001')
            (& $mk 2 'tripwire.trip' 'demo' 'S0009')
            (& $mk 3 'agent.hold' '' '' @{ agent = 'zai' })
            (& $mk 4 'intake.robotDraft' 'demo' 'S0007' @{ count = 21; cap = 20; capped = $true })
            (& $mk 5 'ticket.thrash' 'demo' 'S0001' @{ passes = 3; window = 60 })
            (& $mk 6 'xrepo.cycle' '' '' @{ cycle = @('a:S1', 'b:S2') })
            (& $mk 8 'dispatch.skip' 'demo' 'S0002' @{ why = 'resource' })   # seq 7 missing -> a gap
            'this is not json'
            '{"v":2,"ts":"2026-11-11T10:00:00.000Z","seq":9,"wr":"w1","ev":"old.event","d":{}}'
        )
        [IO.File]::WriteAllText($evFile, (($lines -join "`n") + "`n"), [Text.Encoding]::UTF8)
        $wev = Read-PqWindowEvents -Root $root -Since ([datetime]::new(2020, 1, 1))
        Check ($wev.events.Count -eq 7) "7 valid events, got $($wev.events.Count)"
        Check ($wev.bad -eq 1 -and $wev.unsupported -eq 1) "bad=$($wev.bad) unsupported=$($wev.unsupported)"
        Check (@($wev.gaps).Count -eq 1 -and $wev.gaps[0].count -eq 1 -and $wev.gaps[0].after -eq 6) "one seq gap after 6: $($wev.gaps | ConvertTo-Json -Compress)"
        $f = @(Get-PqFindings -Runs @() -Events $wev.events -Gaps $wev.gaps -Bad $wev.bad)
        $fids = @($f | ForEach-Object { $_.fid })
        Check (($fids -join ',') -ceq 'PQ-DATA01,PQ-RACE01,PQ-SAFE01,PQ-LIMIT01,PQ-THRASH01,PQ-XREPO01,PQ-SAFE02') "findings severity-first: $($fids -join ',')"
        Check (@($f | Where-Object { $_.fid -ceq 'PQ-DATA01' })[0].severity -ceq 'high') 'log health is high'
        Check (@($f | Where-Object { $_.fid -ceq 'PQ-RACE01' })[0].evidence.Count -ge 1) 'findings carry event refs'
        $tr = @(Get-PqTrace -Root $root -Repo 'demo' -Id 'S0001')
        Check ($tr.Count -eq 2 -and @($tr | ForEach-Object { $_.ev }) -join ',' -ceq 'claim.lost,ticket.thrash') "trace of demo:S0001: $($tr.Count) events"
    }

    # ================= 5. loop wiring (source-level) =================
    Case 'the loop carries the 2026-11-10 wiring: draft cap, waiting events, occupancy, resources, halt' {
        $loop = [IO.File]::ReadAllText((Join-Path $lib 'loop.ps1'))
        foreach ($s in @('robotDraftCap', 'intakeCap', 'wait.enter', 'poll.change', 'ticket.thrash', 'repo.occupied', 'resource.acquire', 'pass.halt', 'Invoke-PqStateLock', 'Request-PqResources', 'Get-PqFingerprint', 'Get-PqRepoOccupancy')) {
            Check ($loop.Contains($s)) "loop.ps1 lacks '$s'"
        }
    }

    Case 'read-only rank skips a cross-repository blocker even in a later slot, and restores it after release' {
        $other = Join-Path $scratch 'other-repo'
        $null = [IO.Directory]::CreateDirectory((Join-Path $other 'PLAN'))
        $otherLedger = Join-Path $other 'PLAN/spec-catalog.jsonl'
        [IO.File]::WriteAllText($specEmulator, "# S0001`nBlocker: other:S0009`n", [Text.Encoding]::UTF8)
        [IO.File]::WriteAllText($otherLedger, '{"id":"S0009","status":"Draft","file":"PLAN/S0009_other.md"}' + "`n", [Text.Encoding]::UTF8)
        $reg.repos += @{ key = 'other'; path = $other; enabled = $true }
        $ranker = {
            param($excluded)
            $head = @{ repo = 'demo'; id = 'S0002' }
            $plan = @($head)
            if ($excluded -cnotcontains 'demo:S0001') { $plan += @{ repo = 'demo'; id = 'S0001' } }
            return @{ candidates = @($head); plan = $plan; skipped = @(); excluded = [ordered]@{ xrepo = 0 } }
        }
        $blockedRank = Get-PqXrepoFilteredRank -Registry $reg -Ranker $ranker
        Check ($blockedRank.plan.Count -eq 1 -and $blockedRank.excluded.xrepo -eq 1) 'the blocked later slot is removed'
        Check ($blockedRank.skipped.Count -eq 1 -and $blockedRank.skipped[0].why -match 'other:S0009') 'the preview explains the blocker'
        $headRanker = {
            param($excluded)
            $id = if ($excluded -ccontains 'demo:S0001') { 'S0002' } else { 'S0001' }
            $head = @{ repo = 'demo'; id = $id }
            return @{ candidates = @($head); plan = @($head); skipped = @(); excluded = [ordered]@{ xrepo = 0 } }
        }
        $next = Get-PqXrepoFilteredRank -Registry $reg -Ranker $headRanker
        Check ($next.candidates[0].id -ceq 'S0002' -and $next.excluded.xrepo -eq 1) 'the next eligible ticket replaces a blocked head'

        # Exercise the actual rank wrapper with a deterministic picker, without starting a repository runner.
        . (Join-Path $lib 'rank.ps1')
        function Get-PqKnownKeys($Registry) { return [string[]]@($Registry.repos | ForEach-Object { $_.key }) }
        function Read-PqQueueFile { param($Path, $KnownRepos, $TicketLookup); return @{ rows = @(); held = @(); bad = @() } }
        function Get-PqOccupiedRepos { param($Registry, [switch]$ReadOnly); return [string[]]@() }
        function Get-PqStoppedRepos($Registry) { return [string[]]@() }
        function Get-PqPickerHead {
            param($RepoPath, $HarnessRoot, $Cache, $Exclude, $ForceId)
            $id = if (@($Exclude) -ccontains 'S0001') { 'S0002' } else { 'S0001' }
            return @{ ok = $true; head = @{ id = $id; status = 'Draft'; name = $id; priority = 50 }; payload = $null }
        }
        $reg.repos[1].enabled = $false
        $reg.fill = 'depth'
        $reg.maxWorkers = 1
        $wrapped = Get-PqNextRank -Registry $reg -Slots 1 -StopAfter 1 -CheckXrepo
        Check ($wrapped.candidates[0].id -ceq 'S0002' -and $wrapped.excluded.xrepo -eq 1) 'the rank wrapper passes exclusions back to the picker'
        [IO.File]::WriteAllText($otherLedger, '{"id":"S0009","status":"Archived","file":"PLAN/S0009_other.md"}' + "`n", [Text.Encoding]::UTF8)
        $releasedRank = Get-PqXrepoFilteredRank -Registry $reg -Ranker $ranker
        Check ($releasedRank.plan.Count -eq 2 -and $releasedRank.excluded.xrepo -eq 0) 'the released ticket returns to the plan'
        Check ($releasedRank.skipped.Count -eq 0) 'no blocker is reported after release'

        # S0042: a BlockByOtherTask ticket whose qualified blocker lives in statusNote is also held until release.
        [IO.File]::WriteAllText($specEmulator, "# S0001`nbody without blocker token`n", [Text.Encoding]::UTF8)
        [IO.File]::WriteAllText($ledger, (@(
            '{"id":"S0001","name":"task one","status":"BlockByOtherTask","statusNote":"waiting on sibling. Blocker: other:S0009","priority":80,"file":"PLAN/S0001_task-one.md","created":"2026-11-11","updated":"2026-11-11 10:00"}'
            '{"id":"S0002","name":"task two","status":"Draft","priority":50,"file":"PLAN/S0002_task-two.md","created":"2026-11-11","updated":"2026-11-11 10:00"}'
        ) -join "`n") + "`n", [Text.Encoding]::UTF8)
        [IO.File]::WriteAllText($otherLedger, '{"id":"S0009","status":"Draft","file":"PLAN/S0009_other.md"}' + "`n", [Text.Encoding]::UTF8)
        $noteBlocked = Get-PqXrepoBlock -Registry $reg -RepoKey 'demo' -TicketId 'S0001'
        Check ($null -ne $noteBlocked -and $noteBlocked.blocker -ceq 'other:S0009' -and $noteBlocked.state -ceq 'open') 'statusNote qualified blocker holds BlockByOtherTask ticket'
        [IO.File]::WriteAllText($otherLedger, '{"id":"S0009","status":"Verified","file":"PLAN/S0009_other.md"}' + "`n", [Text.Encoding]::UTF8)
        $noteReleased = Get-PqXrepoBlock -Registry $reg -RepoKey 'demo' -TicketId 'S0001'
        Check ($null -eq $noteReleased) 'statusNote qualified blocker releases when sibling ticket is Verified'
    }

    Write-Host "`nportfolio-s0016-tests: PASS ($case cases)" -ForegroundColor Green
    exit 0
}
finally {
    if ($null -ne $sleeper) { Stop-Process -Id $sleeper.Id -Force -ErrorAction SilentlyContinue }
    $env:SZA_PORTFOLIO_ROOT = $origEnv
    if ([IO.Directory]::Exists($scratch)) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
