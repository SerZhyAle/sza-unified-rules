#requires -Version 7.0
<#
.SYNOPSIS
    Watch the phone-ticket inbox and file what arrives (S0046): the always-on listener.

.DESCRIPTION
    The resident half of S0046. Started at logon by install-inbox-watcher.ps1's scheduled task (plus a
    5-minute repeating one-shot backstop), or by hand: pwsh -NoProfile -File watch-inbox.ps1. One instance per
    machine: a named mutex is taken at start, and a second start says so and exits 3 - claimed packets and the
    event log need one writer.

    On start it re-scans processing/ (crash recovery): a packet whose result.json is already there is finished
    into done/, a claim whose process is gone and whose heartbeat (claim.json: pid, host, startedAt, updatedAt)
    is older than the lease window (45 minutes, the ticket-lease liveness rule) is re-queued to new/, and a live
    claim is left alone. Then it watches new/ with a FileSystemWatcher and a 60-second polling fallback (Drive
    for desktop sync raises no event the watcher can trust; the interval mirrors the queue poll) - a folder with
    a complete manifest.json is claimed atomically (renamed into processing/) and ingested: a valid TICKET
    packet becomes a Draft ticket through spec-draft.ps1 in the named project, in each of projects[] cross-linked,
    or in canon; a refusal lands the packet in failed/ with reason.json, a transient failure is retried with the
    backoff (1, 5, 15 min) and at most three tries. Everything the ingest times and decides is printed, one
    line per packet, and written to the portfolio event log as 'ingest.packet' (EVENTS.md 3.9).

    -Once is the scheduler's form: drain what is claimable, then exit (the 5-minute repeating trigger of the
    scheduled task covers a resident listener that died). The slug of every capture is derived by spec-draft
    from the owner's text; the ticket is a Draft - whether and when pq RUNS it is S0047, not this watcher.

.PARAMETER Once
    One drain pass, then exit 0 (the scheduled-task form).

.PARAMETER InboxRoot
    The inbox root (INBOX-PACKET section 1): -InboxRoot, else SZA_INBOX_ROOT, else C:\GD\SZA\ticket-inbox.

.PARAMETER PollSeconds
    The watcher/poll interval (60 seconds; Drive for desktop has no push - item CQ of DEVICE-EXCHANGE).

.PARAMETER RefreshProjects
    With -Once too: refresh the phone's projects.json from the registry on start, not only in the resident mode.

.EXAMPLE
    pwsh -NoProfile -File watch-inbox.ps1            # resident (at logon, via the scheduled task)
    pwsh -NoProfile -File watch-inbox.ps1 -Once       # the 5-minute repeating backstop

.Exit codes
    0 -Once finished (resident mode never returns on its own; Ctrl+C ends it)
    1 an unexpected failure of the watcher itself
    2 a bad invocation (a bad inbox root)
    3 another watcher holds this inbox
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Once,
    [string]$InboxRoot = '',
    [int]$PollSeconds = 60,
    [int]$StaleMinutes = 0,
    [int]$RetryCeiling = 0,
    [long]$MaxPacketBytes = 0,
    [int]$MaxFiles = 0,
    [string]$SpecDraft = '',
    [switch]$RefreshProjects,
    [switch]$NoRecover
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\inbox-ingest.ps1')

try { $root = Resolve-InboxSpoolRoot $InboxRoot }
catch {
    [Console]::Error.WriteLine("watch-inbox: $($_.Exception.Message)")
    exit 2
}
if ($PollSeconds -lt 5) { $PollSeconds = 5 }

$sw = [Diagnostics.Stopwatch]::StartNew()
Write-Host "watch-inbox: watching $root$(if ($Once) { ' (one pass)' } else { ' (resident)' }), started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# ---- the single-instance lock: one watcher per machine and inbox root, whatever started it. A mutex abandoned
# by a watcher that died is acquired by this start (the catch below) - the recovery re-scan then repairs what it
# left. The name is derived from the root, so a watcher of a scratch root under test is a different instance.
$watcherLock = [Threading.Mutex]::new($false, (Get-InboxWatcherLockName -Root $root))
$held = $false
try {
    try { $held = $watcherLock.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $held = $true }
}
catch {
    [Console]::Error.WriteLine("watch-inbox: the single-instance lock could not be taken: $($_.Exception.Message)")
    exit 1
}
if (-not $held) {
    [Console]::Error.WriteLine('watch-inbox: another watcher holds this inbox; nothing started (exit 3)')
    exit 3
}

# ---- startup: the spool, the log, the crash recovery ----
$null = Initialize-InboxSpool $root
$log = Open-PqLog -Writer imp
try {
    if (-not $NoRecover) {
        $recovery = Invoke-InboxRecovery -Root $root -StaleMinutes $(if ($StaleMinutes -gt 0) { $StaleMinutes } else { 45 })
        foreach ($id in @($recovery.completed)) { Write-Host "watch-inbox: finished $id - result.json was already there (crash between result and move); done/" }
        foreach ($id in @($recovery.requeued)) { Write-Host "watch-inbox: re-queued $id - the claim was stale; new/" }
        foreach ($id in @($recovery.left)) { Write-Host "watch-inbox: left $id in processing/ - its claim is live" }
    }
    if (-not $Once -or $RefreshProjects) {
        # projects.json stays current (INBOX-PACKET section 3): a phone with a stale list falls back to free
        # text, which loses the project - a silent funnel to canon. Best effort, never fatal.
        try {
            $publish = Join-Path $PSScriptRoot 'publish-projects.ps1'
            if ([IO.File]::Exists($publish)) {
                $null = & (Get-Process -Id $PID).Path -NoProfile -File $publish -InboxRoot $root 2>&1
            }
        }
        catch { Write-Host "watch-inbox: projects.json refresh failed (the phone falls back to free text): $($_.Exception.Message)" }
    }

    # ---- the ingest pass: claim everything claimable, decide each packet, print and log it ----
    function Invoke-WatchInboxPass {
        $decided = 0
        if (-not $NoRecover) {
            $recovery = Invoke-InboxRecovery -Root $root -StaleMinutes $(if ($StaleMinutes -gt 0) { $StaleMinutes } else { 45 })
            foreach ($id in @($recovery.completed)) { Write-Host "watch-inbox: recovered decision for $id" }
            foreach ($id in @($recovery.requeued)) { Write-Host "watch-inbox: re-queued stale claim $id" }
        }
        while ($true) {
            $pending = @(Get-InboxNewPackets -Root $root | Where-Object { $_.manifestReady -and $_.retryReady })
            $claimed = 0
            foreach ($p in $pending) {
                $claim = Claim-InboxPacket -Root $root -PacketId $p.packetId -Attempts $p.attempts
                if (-not $claim.ok) { Write-Host "watch-inbox: the claim of $($p.packetId) was refused - $($claim.error)"; continue }
                Write-Host "watch-inbox: claimed $($p.packetId)$(if ($p.attempts -gt 0) { " (retry $($p.attempts))" } else { '' })"
                Write-InboxIngestEvent -Log $log -Outcome 'accepted' -PacketId $p.packetId
                $claimed++
                $decided++
                Update-InboxClaim -Root $root -PacketId $p.packetId
                $r = Invoke-InboxIngestPacket -Root $root -PacketPath $claim.path -SpecDraft $SpecDraft -Log $log `
                    -MaxPacketBytes $(if ($MaxPacketBytes -gt 0) { $MaxPacketBytes } else { 209715200 }) `
                    -MaxFiles $(if ($MaxFiles -gt 0) { $MaxFiles } else { 50 }) `
                    -RetryCeiling $(if ($RetryCeiling -gt 0) { $RetryCeiling } else { 3 }) `
                    -CaptureTimeoutSeconds 300
                Update-InboxClaim -Root $root -PacketId $p.packetId
                switch ($r.outcome) {
                    'processed' { Write-Host "watch-inbox: ingested $($p.packetId) -> $(@($r.tickets) -join ', ') (verdict $($r.verdict))" }
                    'requeued' { Write-Host "watch-inbox: re-queued $($p.packetId) (attempt $($r.attempts)) - $($r.detail)" }
                    'already' {
                        # Our own claim of a packet already decided (done/ or failed/ holds the same id): the
                        # decided copy is the audit trail, the duplicate claim goes.
                        $null = Remove-InboxDuplicateClaim -Root $root -PacketId $p.packetId
                        Write-Host "watch-inbox: $($p.packetId) is already processed; the duplicate claim was removed"
                    }
                    default { Write-Host "watch-inbox: failed $($p.packetId) - $($r.reason): $($r.detail)" }
                }
            }
            if ($claimed -eq 0) { break }
        }
        return $decided
    }

    $null = Invoke-WatchInboxPass
    if ($Once) {
        Write-Host ("watch-inbox: one pass done in {0:N0} ms -> {1}" -f $sw.ElapsedMilliseconds, $root)
        exit 0
    }

    # ---- the resident loop: a FileSystemWatcher wakes the poll early; the 60 s timeout IS the fallback poll ----
    $fsWatcher = [IO.FileSystemWatcher]::new((Join-Path $root 'new'))
    $fsWatcher.IncludeSubdirectories = $true
    $fsWatcher.NotifyFilter = [IO.NotifyFilters]::DirectoryName -bor [IO.NotifyFilters]::FileName -bor [IO.NotifyFilters]::LastWrite
    try {
        while ($true) {
            $null = Invoke-WatchInboxPass
            $change = $fsWatcher.WaitForChanged([IO.WatcherChangeTypes]::Created -bor [IO.WatcherChangeTypes]::Renamed -bor [IO.WatcherChangeTypes]::Changed, $PollSeconds * 1000)
            # One quiet poll: DistinctLastWriteWithinSizeSpan of Drive means a long upload is still landing; the
            # next pass sees the completed manifest and claims it. The poll, not the event, is the guarantee.
        }
    }
    finally { $fsWatcher.Dispose() }
}
catch {
    $after = $sw.Elapsed.TotalSeconds.ToString('0.0')
    [Console]::Error.WriteLine("watch-inbox: failed after ${after}s: $($_.Exception.Message)")
    exit 1
}
finally {
    try { if ($null -ne $log) { $null = Close-PqLog -Log $log } } catch { }
    try { if ($held -and -not $watcherLock.SafeWaitHandle.IsClosed) { $watcherLock.ReleaseMutex() } } catch { }
    $watcherLock.Dispose()
}
