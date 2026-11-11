#requires -Version 7.0
<#
.SYNOPSIS
    Drain the phone-ticket inbox (S0047): file what arrived, then run each newly filed ticket once through the
    normal dispatcher - `pq start -Ticket <key>:<id>` - never through a runner of its own.

.DESCRIPTION
    The execution half of the phone inbox. Scheduled every 10 minutes by install-inbox-watcher.ps1 (the task
    'SZA inbox drain'), or run by hand. Two steps, in order:

      1. Ingest: ingest-inbox.ps1 -All (S0046), so a dead listener costs at most one interval.
      2. Execute: every ticket a packet filed since the last drain (the cursor inbox-state.json beside the spool
         lists packetId -> tickets -> execution) gets exactly one named start, oldest packet first, at most
         -MaxTickets (3) per drain; the rest wait for the next drain.

    No parallel dispatch: the drain only calls `pq start -Ticket`, whose exit 0 means the pass ran and 3 means it
    did not, with a printed reason. Occupancy, the repository lock, the lease, STOP files, the provider holds, the
    registry's hold and enabled flags and the picker's gates all stay the dispatcher's; a ticket the main loop is
    working is leased, so its named start exits 3 and the drain records `skipped` (leased), not a failure. Hold
    lines of PORTFOLIO_QUEUE.md are passed for that exact ticket by the named start (S0027) and never edited here.

    Never run automatically (recorded `not-run` with the reason, never replaced by another ticket):
      - a ticket whose project the packet did not name: a project-less packet, or an unknown key S0046 routed
        to canon - those are the owner's questions (owner choice 3(b));
      - every ticket under -FileOnly (the regular pq start works them);
      - a ticket a killed drain had started (`launching` in the cursor): recorded `interrupted` and never started
        a second time - the double-run guard.
    A first drain also processes tickets already filed by the listener; otherwise arrivals before the first
    scheduled execution would be lost.

    Each decision goes into the packet's result.json (`execution`: ran | skipped | <reason>, plus `executions`)
    and the drain writes one `ingest.drain` event: d = { packets, filed[], ran[], skipped[{id, reason}],
    deferred, ms } (EVENTS.md 3.9, additive). A packet whose text asked for a build (the ingest marked
    `buildIntent` in its result.json), or the one ticket `-After <key>:<id>` names, is also BUILT after its
    named start ran and its ledger row reached Implemented or BlockNeedUserTest - one build
    (`-MaxBuilds` default 1) through build-deliver.ps1, delivered into the Drive folder the phone reaches
    (S0048). The build decision lands in the packet's result.json as `builds` [..] (additive): delivered with
    the version, refused with the reason, or not-built with the ticket's status after the pass. The [PUBLIC]
    store upload is never part of this: a filed publish-to-store is staged by stage-store-publish.ps1 and the
    manual Partner Center step stays the owner's.

.PARAMETER MaxTickets
    Named starts per drain (default 3, owner choice 4(b)); 0 executes none (same as -FileOnly, but the tickets
    stay pending for a later drain).

.PARAMETER FileOnly
    File only: every new ticket is recorded `not-run: file-only` and left to the regular pq start.

.PARAMETER After
    Build this ticket's project after its pass, whatever the packet said: `<key>:<id>`, the owner's explicit
    trigger (S0048 open question 1(a)).

.PARAMETER MaxBuilds
    Builds per drain after the cap of passes (default 1); an eligible ticket beyond it is recorded `deferred`
    and built by the next drain.

.PARAMETER InboxRoot
    The inbox root: -InboxRoot, else SZA_INBOX_ROOT, else C:\GD\SZA\ticket-inbox.

.PARAMETER PqScript
    The dispatcher entry point: -PqScript, else SZA_PQ_SCRIPT, else pq.ps1 beside this script.

.PARAMETER IngestScript
    The ingest: -IngestScript, else SZA_INGEST_SCRIPT, else ingest-inbox.ps1 beside this script.

.PARAMETER BuildDeliverScript
    The build-and-deliver step: -BuildDeliverScript, else SZA_BUILD_DELIVER, else build-deliver.ps1 beside
    this script.

.EXAMPLE
    pwsh -NoProfile -File drain-inbox.ps1                # what the scheduled task runs
    pwsh -NoProfile -File drain-inbox.ps1 -FileOnly      # file, run nothing
    pwsh -NoProfile -File drain-inbox.ps1 -After cyrflip:C123   # build cyrflip once its ticket ran

.Exit codes
    0 the drain completed (also with nothing to do, another drain running, or targets refused with reasons printed)
    2 invalid invocation, an unreadable spool, cursor or registry, or the ingest refused its invocation
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$MaxTickets = '3',
    [switch]$FileOnly,
    [string]$After = '',
    [string]$MaxBuilds = '1',
    [string]$InboxRoot = '',
    [string]$PqScript = '',
    [string]$IngestScript = '',
    [string]$BuildDeliverScript = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$lib = Join-Path $PSScriptRoot 'lib'
. (Join-Path $lib 'inbox-drain.ps1')
. (Join-Path $lib 'paths.ps1')
. (Join-Path $lib 'events.ps1')
. (Join-Path $lib 'registry.ps1')
. (Join-Path $lib 'ledger-watch.ps1')

function Write-DrainError([string]$Message) { [Console]::Error.WriteLine("drain-inbox: $Message") }

$limit = 0
if (-not [int]::TryParse($MaxTickets, [ref]$limit) -or $limit -lt 0 -or $limit -gt 100) {
    Write-DrainError '-MaxTickets must be an integer from 0 to 100'
    exit 2
}
$buildLimit = 0
if (-not [int]::TryParse($MaxBuilds, [ref]$buildLimit) -or $buildLimit -lt 0 -or $buildLimit -gt 10) {
    Write-DrainError '-MaxBuilds must be an integer from 0 to 10'
    exit 2
}
if ($After -and $After -cnotmatch '^[A-Za-z0-9_.\-]+:[A-Za-z0-9_.\-]+$') {
    Write-DrainError "`-After '$After' is not <key>:<id>"
    exit 2
}

function Resolve-DrainScript([string]$Given, [string]$EnvName, [string]$Default) {
    $v = $Given
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable($EnvName) }
    if (-not $v) { $v = Join-Path $PSScriptRoot $Default }
    if (-not [IO.File]::Exists($v)) { throw "ScriptMissing: $v" }
    return [IO.Path]::GetFullPath($v)
}

# One child pwsh; stdout echoed line by line as it comes (a pass runs for minutes), stderr collected.
function Invoke-DrainChild([string]$Script, [string[]]$Arguments) {
    $psi = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
    foreach ($a in @('-NoProfile', '-File', $Script) + @($Arguments)) { $psi.ArgumentList.Add([string]$a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = [Diagnostics.Process]::Start($psi)
    try {
        $err = $proc.StandardError.ReadToEndAsync()
        $lines = [Collections.Generic.List[string]]::new()
        while ($null -ne ($line = $proc.StandardOutput.ReadLine())) { $lines.Add($line); Write-Host "  | $line" }
        $proc.WaitForExit()
        foreach ($l in @(([string]$err.Result) -split '\r?\n' | Where-Object { $_ })) { $lines.Add($l); Write-Host "  ! $l" }
        return @{ code = $proc.ExitCode; lines = @($lines) }
    }
    finally { $proc.Dispose() }
}

$sw = [Diagnostics.Stopwatch]::StartNew()
try {
    $root = Resolve-InboxSpoolRoot $InboxRoot
    $pq = Resolve-DrainScript $PqScript 'SZA_PQ_SCRIPT' 'pq.ps1'
    $ingest = Resolve-DrainScript $IngestScript 'SZA_INGEST_SCRIPT' 'ingest-inbox.ps1'
    $buildDeliver = Resolve-DrainScript $BuildDeliverScript 'SZA_BUILD_DELIVER' 'build-deliver.ps1'
}
catch { Write-DrainError $_.Exception.Message; exit 2 }

$reg = $null
try { $reg = Read-PqRegistry } catch { }
if ($null -eq $reg -or -not $reg.ok) { Write-DrainError 'the portfolio registry is missing or unreadable (pq list)'; exit 2 }
try { $null = Initialize-InboxSpool $root }
catch { Write-DrainError "the spool at $root cannot be prepared: $($_.Exception.Message)"; exit 2 }

# One drain at a time: the cursor has one writer. A second drain is not an error - the first one is doing the work.
$lock = [Threading.Mutex]::new($false, 'Global\SZA-inbox-drain-S0047')
$held = $false
try { $held = $lock.WaitOne(0) } catch [Threading.AbandonedMutexException] { $held = $true }
if (-not $held) { Write-Host 'drain-inbox: another drain is running; nothing done'; $lock.Dispose(); exit 0 }

$log = $null
try {
    try { $state = Read-InboxDrainState -Root $root }
    catch { Write-DrainError $_.Exception.Message; exit 2 }
    $log = Open-PqLog -Writer imp
    Write-Host "drain-inbox: $root$(if ($FileOnly) { ' (file only)' }), at most $MaxTickets named start(s)"

    # ---- 1. ingest ----
    $ing = Invoke-DrainChild $ingest @('-All', '-InboxRoot', $root)
    if ($ing.code -notin @(0, 1, 3)) { Write-DrainError "the ingest failed (exit $($ing.code))"; exit 2 }
    $ingestNote = switch ($ing.code) { 0 { 'every packet decided' } 1 { 'a packet left for a retry' } 3 { 'nothing pending' } default { "exit $($ing.code)" } }
    Write-Host "drain-inbox: ingest - $ingestNote"

    $now = { [DateTimeOffset]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'") }
    # Repair a result write interrupted after the cursor was saved, without dispatching again.
    foreach ($done in @(Get-InboxDonePackets -Root $root)) {
        if (-not $state.packets.Contains($done.packetId)) { continue }
        $executions = $state.packets[$done.packetId].executions
        if ($executions.Count -eq 0 -or @($executions.Values | Where-Object { $_['execution'] -ceq 'launching' }).Count -gt 0) { continue }
        $rows = if ($done.result.Contains('executions') -and $done.result['executions'] -is [array]) { $done.result['executions'] } else { @() }
        $expected = @($executions.Keys | Where-Object { $key = $_; -not @($rows | Where-Object { $null -ne $_ -and $_['ticket'] -ceq $key -and $_['execution'] -ceq $executions[$key]['execution'] -and $_['reason'] -ceq $executions[$key]['reason'] }).Count })
        if ($expected.Count -gt 0 -and -not (Set-InboxResultExecution -PacketPath $done.path -Executions $executions)) { throw "ResultWriteFailed: $($done.path)" }
    }

    # ---- 2. execute ----
    $filed = [Collections.Generic.List[string]]::new()
    $ran = [Collections.Generic.List[string]]::new()
    $ranInfo = [Collections.Generic.List[object]]::new()
    $skipped = [Collections.Generic.List[object]]::new()
    $deferred = 0
    $starts = 0
    $pending = @(Get-InboxDrainPending -Root $root -State $state)
    foreach ($p in $pending) {
        if (-not $state.packets.Contains($p.packetId)) {
            $state.packets[$p.packetId] = [ordered]@{ tickets = @($p.tickets); filedAt = $p.at; executions = [ordered]@{} }
            foreach ($t in @($p.tickets)) { $filed.Add($t) }
        }
        $entry = $state.packets[$p.packetId]
        $record = {
            param([string]$T, [string]$Execution, [string]$Reason)
            $entry.executions[$T] = [ordered]@{ execution = $Execution; reason = $Reason; at = (& $now) }
            if ($Execution -ceq 'ran') { $ran.Add($T) } else { $skipped.Add([ordered]@{ id = $T; reason = $(if ($Reason) { $Reason } else { $Execution }) }) }
            $null = Write-InboxDrainState -Root $root -State $state
            Write-Host "drain-inbox: $T ($($p.packetId)) - $(if ($Execution -ceq 'ran') { 'ran' } else { "$Execution`: $Reason" })"
        }
        foreach ($t in @($p.tickets)) {
            $prior = if ($entry.executions.Contains($t)) { $entry.executions[$t] } else { $null }
            if ($null -ne $prior -and [string]$prior['execution'] -ceq 'launching') {
                & $record $t 'not-run' 'interrupted: an earlier drain ended during its named start; not started a second time'
                continue
            }
            if ($FileOnly) { & $record $t 'not-run' 'file-only: left to the regular pq start'; continue }
            if ((Get-InboxDrainTarget -Ticket $t -Named $p.named -Known @($reg.registry.repos | ForEach-Object { [string]$_.key })) -ceq 'triage') {
                $why = if ($p.projectless) { 'project-less packet: waits for the owner (never auto-run)' } else { 'routed to canon for triage (the named project is unknown): waits for the owner' }
                & $record $t 'not-run' $why
                continue
            }
            if ($starts -ge $limit) { $deferred++; continue }
            $starts++
            $entry.executions[$t] = [ordered]@{ execution = 'launching'; reason = $null; at = (& $now); pid = $PID }
            $null = Write-InboxDrainState -Root $root -State $state
            Write-Host "drain-inbox: pq start -Ticket $t"
            $r = Invoke-DrainChild $pq @('start', '-Ticket', $t)
            $o = ConvertFrom-InboxPqResult -Code $r.code -Lines $r.lines -Ticket $t
            & $record $t $o.execution $o.reason
            if ($o.execution -ceq 'ran') { $ranInfo.Add([pscustomobject]@{ ticket = $t; path = $p.path; packetId = $p.packetId }) }
        }
        $decided = @($p.tickets | Where-Object { $entry.executions.Contains($_) -and [string]$entry.executions[$_]['execution'] -cne 'launching' })
        if ($decided.Count -gt 0) {
            $all = [ordered]@{}
            foreach ($t in @($entry.tickets)) { if ($entry.executions.Contains($t)) { $all[$t] = $entry.executions[$t] } }
            if (-not (Set-InboxResultExecution -PacketPath $p.path -Executions $all)) { throw "ResultWriteFailed: $($p.path)" }
        }
    }
    # ---- 3. build (S0048): the ran tickets the packet's text asked a build for, plus the one -After names.
    # The decision is written to the packet's result.json (additive `builds`), once; the [PUBLIC] store upload is
    # never here - build-deliver delivers to the Drive folder and stops.
    $buildsDone = 0
    foreach ($info in @($ranInfo)) {
        $t = [string]$info.ticket
        $packetResult = $null
        try { $packetResult = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $info.path 'result.json'))) -AsHashtable -DateKind String } catch { }
        if ((Test-InboxResultBuildDecided -Result $packetResult -Ticket $t)) { continue }
        $wantsBuild = $false
        if ($packetResult -is [Collections.IDictionary] -and $packetResult.Contains('buildIntent')) { $wantsBuild = [bool]$packetResult['buildIntent'] }
        $isAfter = ($After -and $t -ceq $After)
        if (-not ($wantsBuild -or $isAfter)) { continue }
        $key = ($t -split ':', 2)[0]
        $id = ($t -split ':', 2)[1]
        $row = [ordered]@{ ticket = $t; outcome = 'not-built'; version = $null; dir = $null; reason = $null; at = (& $now) }
        if ($isAfter -and -not $wantsBuild) { Write-Host "drain-inbox: -After names $t" }
        if ($buildsDone -ge $buildLimit) {
            $row['outcome'] = 'deferred'
            $row['reason'] = "the drain's build cap ($buildLimit) was reached; the next drain builds it"
            $null = Add-InboxResultBuild -PacketPath $info.path -Build $row
            Write-Host "drain-inbox: build of $t deferred to the next drain"
            continue
        }
        $repoRec = @($reg.registry.repos | Where-Object { [string]$_.key -ceq $key } | Select-Object -First 1)
        if (@($repoRec).Count -eq 0 -or -not [IO.Directory]::Exists([string]$repoRec[0].path)) {
            $row['outcome'] = 'refused'
            $row['reason'] = "project '$key' is not registered on this PC"
        }
        else {
            $status = $null
            try {
                $snap = Get-PqLedgerSnapshot -RepoPath ([string]$repoRec[0].path) -Key $key
                if ($snap.tickets.Contains($id)) { $status = [string]$snap.tickets[$id].status }
            }
            catch { $row['reason'] = "the ledger of $key did not read: $($_.Exception.Message)" }
            if (-not $row['reason'] -and $status -cnotin @('Implemented', 'BlockNeedUserTest')) {
                $row['reason'] = "ticket status after the pass is '$status', not Implemented/BlockNeedUserTest - nothing to build yet"
            }
        }
        if (-not $row['reason']) {
            Write-Host "drain-inbox: build-deliver -Project $key -Ticket $t"
            $b = Invoke-DrainChild $buildDeliver @('-Project', $key, '-Ticket', $t, '-Json')
            $parsed = $null
            try {
                $text = (@($b.lines) -join "`n")
                $start = $text.IndexOf('{')
                $end = $text.LastIndexOf('}')
                if ($start -ge 0 -and $end -gt $start) { $parsed = ConvertFrom-Json -InputObject $text.Substring($start, $end - $start + 1) -AsHashtable -DateKind String }
            }
            catch { }
            $buildsDone++
            if ($b.code -eq 0 -and $parsed) {
                $row['outcome'] = 'delivered'
                $row['version'] = [string]$parsed['version']
                $row['dir'] = [string]$parsed['dir']
                Write-Host "drain-inbox: built $t -> version $($parsed['version']) delivered to $($parsed['dir'])"
            }
            else {
                $row['outcome'] = $(if ($b.code -eq 2) { 'refused' } else { 'failed' })
                $why = if ($parsed -is [Collections.IDictionary] -and $parsed.Contains('error')) { [string]$parsed['error'] } else { "build-deliver exited $($b.code)" }
                $row['reason'] = $why
                Write-Host "drain-inbox: build of $t $($row['outcome']): $why"
            }
        }
        else {
            Write-Host "drain-inbox: build of $t not built - $($row['reason'])"
        }
        $null = Add-InboxResultBuild -PacketPath $info.path -Build $row
    }

    $sw.Stop()
    $null = Write-PqEvent -Log $log -Ev 'ingest.drain' -D ([ordered]@{
            packets = $pending.Count; filed = @($filed); ran = @($ran); skipped = @($skipped); deferred = $deferred
            ms = [int]$sw.ElapsedMilliseconds
        })
    Write-Host ("drain-inbox: {0} packet(s), {1} filed, {2} ran, {3} not run, {4} deferred to the next drain, {5:N0} ms" -f $pending.Count, $filed.Count, $ran.Count, $skipped.Count, $deferred, $sw.ElapsedMilliseconds)
    exit 0
}
catch {
    Write-DrainError "failed: $($_.Exception.Message)"
    exit 2
}
finally {
    try { if ($null -ne $log) { $null = Close-PqLog -Log $log } } catch { }
    try { if ($held) { $lock.ReleaseMutex() } } catch { }
    $lock.Dispose()
}
