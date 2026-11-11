#requires -Version 7.0
# The phone-ticket inbox spool (S0046): the new/processing/done/failed layout under the inbox root, the atomic
# claim, the crash-recovery re-queue and the processed marking of INBOX-PACKET.md sections 1 and 5.
#
# Dot-source this file; it defines functions only, sets no preference and prints nothing. State: none. The packet
# itself is validated by lib/inbox-packet.ps1, which this file loads; the claim needs only a complete manifest.json
# (the phone writes it last, so it is the commit marker), the full validation is the ingest's first step and a
# refusal lands the packet in failed/ without ingesting a byte.
#
# Named folders and files the moment a packet spends in the spool:
#
#   new\<packetId>\                  waiting (the phone writes only folders here)
#   new\<packetId>.attempts.json     a PC-side retry record (a re-queued packet: attempts, nextRetryAtEpochMs, lastError)
#   processing\<packetId>\           claimed by the rename below
#   processing\<packetId>.claim.json  the heartbeat of the claim: pid, host, startedAt, updatedAt, attempts
#   processing\<packetId>.attempts.json   the attempts record travels with the folder
#   done\<packetId>\                 processed; result.json beside the manifest (INBOX-PACKET section 5)
#   failed\<packetId>\               refused; reason.json beside the manifest
#
# claim.json and the attempts record live NEXT TO the packet folder, never inside it: a packet folder that holds a
# file files[] does not list is refused as UnexpectedFile (INBOX-PACKET section 4), so the spool's own bookkeeping
# must stay out of the phone's packet. result.json and reason.json ARE inside the folder, but only ever beside the
# manifest in done/ or failed/, where the reader tolerates them (section 4).
#
#   Resolve-InboxSpoolRoot [-Root <path>]  the inbox root: -Root, else SZA_INBOX_ROOT, else C:\GD\SZA\ticket-inbox
#                                         (INBOX-PACKET section 1). Absolute; a relative value throws
#                                         'InboxRootInvalid: <value>'; it creates nothing.
#   Initialize-InboxSpool -Root <path>     the four stage folders, idempotent; returns the root.
#   Get-InboxStagePath -Root -Stage <name> one stage folder; an unknown stage throws 'InboxStageUnknown: <stage>'.
#   Get-InboxClaimPath / Get-InboxAttemptsPath -StageDir -PacketId
#                                         the sidecar names of the claim and the attempts record.
#   Get-InboxNewPackets -Root             the packet folders in new/: @{ packetId; stage; path; manifestReady;
#                                         attempts; lastError; retryReady; ageSeconds; age }, oldest first.
#                                         A missing manifest waits; an invalid manifest is claimed for refusal
#                                         after one minute, allowing an incomplete sync to finish.
#   Read-InboxAttempts / Write-InboxAttempts -Path [-Attempts]
#                                         the sidecar record: @{ attempts; nextRetryAtEpochMs; lastError }.
#                                         Unreadable is $null; a failed write throws so a retry cannot lose its count.
#   Claim-InboxPacket -Root -PacketId [-Attempts] -> @{ ok; path; claim; error; message }
#                                         the atomic claim: rename new\<id> to processing\<id>, then the claim
#                                         sidecar beside it. The rename is the claim: two claimants cannot both
#                                         win it (a rename that finds the target taken is a lost claim, not an
#                                         error). Never claimed: ManifestIncomplete, ClaimLost, ClaimMoveFailed.
#   Read-InboxClaim -Root -PacketId ->    the claim record, $null when none reads.
#   Update-InboxClaim -Root -PacketId    the heartbeat: claim.json's updatedAt refreshed; best-effort, never thrown.
#   Test-InboxClaimLiveness -Claim [-StaleMinutes] -> live|stale
#                                         the lease rule already used for tickets (locks/agent-lock.ps1
#                                         SpecTicket): a claim of a process that still runs on this host is live,
#                                         and any other claim is live while its updatedAt falls inside the stale
#                                         window (45 minutes, the shared SessionStaleMinutes); older is stale.
#                                         $null (no claim.json read) is stale.
#   Invoke-InboxRecovery -Root [-StaleMinutes] -> @{ completed; requeued; left }
#                                         the start-of-listener re-scan of processing/: a claim whose result.json
#                                         exists is finished (moved to done/ - the crash fell between the result
#                                         write and the move); a live claim is left alone (its process may still
#                                         be working); a stale claim is re-queued to new/ (claim sidecar removed,
#                                         attempts kept).
#   Test-InboxProcessedPacket -Root -PacketId -> $true when done\<id> or failed\<id> exists: the idempotency line
#                                         no packet ever crosses twice.
#   Complete-InboxPacket -Root -PacketId -Result  writes result.json beside the manifest (2-space JSON, LF, a final
#                                         newline, UTF-8 no BOM) and moves processing\<id> to done\<id>.
#                                         -> @{ ok; path; error; message }
#   Fail-InboxPacket -Root -PacketId -Error -Detail writes reason.json ({ error, detail }) and moves to failed\<id>.
#                                         -> @{ ok; path; error; message }
#   Requeue-InboxPacket -Root -PacketId -LastError [-RetryCeiling] [-BackoffSeconds <int[]>]
#                                         a retryable capture failure: attempts+1 with the backoff (1, 5, 15 min),
#                                         -> @{ outcome = requeued|ceiling|error; attempts; nextRetryAtEpochMs };
#                                         requeued is back in new/ with the wait, ceiling leaves the packet in
#                                         processing/ for the caller to Fail-InboxPacket.
#   Get-InboxSpoolAge -Root [-ThresholdSeconds] -> @{ present; waiting; processing; stale; oldestPacketId;
#                                         oldestAgeSeconds; oldestAge; oldestStage; packets } - what
#                                         pq status/problems surface (S0025's precedent): packets sitting in new/
#                                         or processing/ past the threshold. present is $false when the root does
#                                         not exist (the channel is not set up; nothing prints).

. (Join-Path $PSScriptRoot 'inbox-packet.ps1')

# The name of the single-instance lock of a watcher: one machine, one watcher PER INBOX ROOT (a scratch root
# under test is not the same inbox as the real one). The name is opaque on purpose - a mutex of a path with
# drive letters and separators is fragile, a hash is not.
function Get-InboxWatcherLockName {
    param([Parameter(Mandatory)][string]$Root)
    $hash = [BitConverter]::ToString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Root.ToUpperInvariant()))).Replace('-', '').Substring(0, 16)
    return "Global\SZA-inbox-watcher-$hash"
}

# The stale window of a claim: the shared ticket-lease liveness (locks/agent-lock.ps1 SpecTicket
# SessionStaleMinutes, 45) - the plan names it "the liveness rule already used for leases".
$script:InboxClaimStaleMinutes = 45
# The default retry ceiling and backoff of an ingest (plan 3.2 open question 5): three tries, 1, 5, 15 minutes.
$script:InboxRetryCeiling = 3
$script:InboxRetryBackoffSeconds = [int[]]@(60, 300, 900)
# How long an unprocessed packet may sit in new/ or processing/ before pq status/problems names it.
$script:InboxSpoolAgeThresholdSeconds = 900
$script:InboxStages = [string[]]@('new', 'processing', 'done', 'failed')

function Resolve-InboxSpoolRoot {
    param([string]$Root)
    $value = $Root
    if ([string]::IsNullOrWhiteSpace($value)) { $value = $env:SZA_INBOX_ROOT }
    if ([string]::IsNullOrWhiteSpace($value)) { $value = 'C:\GD\SZA\ticket-inbox' }
    if (-not [IO.Path]::IsPathFullyQualified($value)) { throw "InboxRootInvalid: $value" }
    return [IO.Path]::GetFullPath($value).TrimEnd('\', '/')
}

function Initialize-InboxSpool {
    param([Parameter(Mandatory)][string]$Root)
    foreach ($stage in $script:InboxStages) {
        $dir = Join-Path $Root $stage
        if (-not [IO.Directory]::Exists($dir)) { $null = [IO.Directory]::CreateDirectory($dir) }
    }
    return $Root
}

function Get-InboxStagePath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Stage
    )
    if ($Stage -cnotin $script:InboxStages) { throw "InboxStageUnknown: $Stage" }
    return (Join-Path $Root $Stage)
}

function Get-InboxClaimPath {
    param([Parameter(Mandatory)][string]$StageDir, [Parameter(Mandatory)][string]$PacketId)
    return (Join-Path $StageDir "$PacketId.claim.json")
}

function Get-InboxAttemptsPath {
    param([Parameter(Mandatory)][string]$StageDir, [Parameter(Mandatory)][string]$PacketId)
    return (Join-Path $StageDir "$PacketId.attempts.json")
}

function Read-InboxAttempts {
    param([Parameter(Mandatory)][string]$Path)
    if (-not [IO.File]::Exists($Path)) { return $null }
    try { return (ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path)) -DateKind String -NoEnumerate) }
    catch { return $null }
}

function Write-InboxAttempts {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Attempts
    )
    $doc = [ordered]@{
        attempts           = [int]$Attempts.attempts
        nextRetryAtEpochMs = [long]$Attempts.nextRetryAtEpochMs
        lastError          = [string]$Attempts.lastError
    }
    $json = (ConvertTo-Json -InputObject $doc -Depth 4).Replace("`r`n", "`n") + "`n"
    try {
        [IO.File]::WriteAllText("$Path.tmp", $json, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move("$Path.tmp", $Path, $true)
    }
    catch {
        if ([IO.File]::Exists("$Path.tmp")) { try { [IO.File]::Delete("$Path.tmp") } catch { } }
        throw
    }
}

# How old a packet folder is: the folder's own write time (Drive sync sets it as the packet arrives).
function Get-InboxFolderAgeSeconds([string]$Path) {
    if (-not [IO.Directory]::Exists($Path)) { return $null }
    return [long][Math]::Max(0, [Math]::Floor(([DateTimeOffset]::Now - [IO.DirectoryInfo]::new($Path).LastWriteTime).TotalSeconds))
}

function ConvertTo-InboxAgeText($Seconds) {
    if ($null -eq $Seconds) { return 'unknown' }
    if ($Seconds -ge 86400) { return '{0}d' -f [Math]::Floor($Seconds / 86400) }
    if ($Seconds -ge 3600) { return '{0}h' -f [Math]::Floor($Seconds / 3600) }
    return '{0}m' -f [Math]::Floor($Seconds / 60)
}

# The packets waiting in new/, complete or not, oldest first. manifestReady: a manifest.json that parses as one
# JSON object - the claim's only gate (S0045 writes it last; the ingest validates the rest).
function Get-InboxNewPackets {
    param([Parameter(Mandatory)][string]$Root)
    $newDir = Join-Path $Root 'new'
    $packets = [Collections.Generic.List[object]]::new()
    if (-not [IO.Directory]::Exists($newDir)) { return @() }
    foreach ($dir in [IO.Directory]::GetDirectories($newDir)) {
        $packetId = Split-Path -Leaf $dir
        $attempts = Read-InboxAttempts -Path (Get-InboxAttemptsPath -StageDir $newDir -PacketId $packetId)
        $nextRetry = $null
        if ($null -ne $attempts -and $null -ne $attempts.nextRetryAtEpochMs) { $nextRetry = [long]$attempts.nextRetryAtEpochMs }
        $retryReady = ($null -eq $nextRetry) -or ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() -ge $nextRetry)
        $ageSeconds = Get-InboxFolderAgeSeconds $dir
        $packets.Add([pscustomobject]@{
            packetId      = $packetId
            stage         = 'new'
            path          = $dir
            manifestReady = (Test-InboxPacketManifestReady $dir)
            attempts      = $(if ($null -ne $attempts) { [int]$attempts.attempts } else { 0 })
            lastError     = $(if ($null -ne $attempts) { [string]$attempts.lastError } else { '' })
            retryReady    = $retryReady
            ageSeconds    = $ageSeconds
            age           = (ConvertTo-InboxAgeText $ageSeconds)
        })
    }
    return @($packets | Sort-Object -Property @{ Expression = { $_.ageSeconds ?? [long]::MaxValue } }, packetId)
}

function Read-InboxClaim {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$PacketId
    )
    $path = Get-InboxClaimPath -StageDir (Join-Path $Root 'processing') -PacketId $PacketId
    if (-not [IO.File]::Exists($path)) { return $null }
    try { return (ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($path)) -DateKind String -NoEnumerate) }
    catch { return $null }
}

function Write-InboxClaimFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Claim
    )
    $doc = [ordered]@{
        packetId         = [string]$Claim.packetId
        pid              = [int]$Claim.pid
        host             = [string]$Claim.host
        startedAtEpochMs = [long]$Claim.startedAtEpochMs
        updatedAtEpochMs = [long]$Claim.updatedAtEpochMs
        attempts         = [int]$Claim.attempts
    }
    $json = (ConvertTo-Json -InputObject $doc -Depth 4).Replace("`r`n", "`n") + "`n"
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}

function Update-InboxClaim {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$PacketId
    )
    $claim = Read-InboxClaim -Root $Root -PacketId $PacketId
    if ($null -eq $claim) { return }
    try {
        $claim.updatedAtEpochMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        Write-InboxClaimFile -Path (Get-InboxClaimPath -StageDir (Join-Path $Root 'processing') -PacketId $PacketId) -Claim $claim
    }
    catch { }
}

# The claim's liveness: live when its process runs on this host, else live while updatedAt falls inside the stale
# window - the ticket-lease rule (a claim's pid IS the claiming process, unlike a lease's writer pid, so a live
# pid is direct evidence and the window only covers the gap after a crash).
function Test-InboxClaimLiveness {
    param(
        $Claim,
        [int]$StaleMinutes = $script:InboxClaimStaleMinutes
    )
    if ($null -eq $Claim) { return 'stale' }
    $hostName = if ([string]$Claim.host) { [string]$Claim.host } else { $env:COMPUTERNAME }
    if (($hostName -ceq $env:COMPUTERNAME) -and $Claim.pid -is [int] -and $Claim.pid -gt 0) {
        $alive = $false
        try { Get-Process -Id $Claim.pid -ErrorAction Stop | Out-Null; $alive = $true } catch { }
        if ($alive) { return 'live' }
    }
    $updatedAt = [long]($Claim.updatedAtEpochMs ?? $Claim.startedAtEpochMs ?? 0)
    $ageMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - $updatedAt
    if ($ageMs -le ([long]$StaleMinutes * 60 * 1000)) { return 'live' }
    return 'stale'
}

# The atomic claim: the rename is the claiming act, the sidecar after it only records who. An attempt count is
# carried onto the claim (the ceiling is judged against it).
function Claim-InboxPacket {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$PacketId,
        [int]$Attempts = 0
    )
    $newDir = Join-Path $Root 'new'
    $processingDir = Join-Path $Root 'processing'
    $source = Join-Path $newDir $PacketId
    if (-not [IO.Directory]::Exists($source)) { return @{ ok = $false; path = $null; claim = $null; error = 'ClaimLost'; message = "no packet '$PacketId' in new/" } }
    if (-not (Test-InboxPacketManifestReady $source)) {
        return @{ ok = $false; path = $null; claim = $null; error = 'ManifestIncomplete'; message = "packet '$PacketId' has no parsable manifest.json" }
    }
    $dest = Join-Path $processingDir $PacketId
    try { [IO.Directory]::Move($source, $dest) }
    catch { return @{ ok = $false; path = $null; claim = $null; error = 'ClaimMoveFailed'; message = $_.Exception.Message } }
    $epoch = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $claim = [pscustomobject]@{
        packetId         = $PacketId
        pid              = $PID
        host             = $env:COMPUTERNAME
        startedAtEpochMs = $epoch
        updatedAtEpochMs = $epoch
        attempts         = $Attempts
    }
    $claimPath = Get-InboxClaimPath -StageDir $processingDir -PacketId $PacketId
    try {
        Write-InboxClaimFile -Path $claimPath -Claim $claim
    }
    catch {
        try { [IO.Directory]::Move($dest, $source) } catch { }
        return @{ ok = $false; path = $null; claim = $null; error = 'ClaimWriteFailed'; message = $_.Exception.Message }
    }
    $attemptsPath = Get-InboxAttemptsPath -StageDir $newDir -PacketId $PacketId
    if ([IO.File]::Exists($attemptsPath)) {
        try { [IO.File]::Move($attemptsPath, (Get-InboxAttemptsPath -StageDir $processingDir -PacketId $PacketId), $true) }
        catch { }
    }
    return @{ ok = $true; path = $dest; claim = $claim; error = $null; message = $null }
}

# A parsable manifest is ready immediately; an invalid one is given a minute to finish syncing.
function Test-InboxPacketManifestReady([string]$PacketPath) {
    $path = Join-Path $PacketPath 'manifest.json'
    if (-not [IO.File]::Exists($path)) { return $false }
    $read = Read-InboxPacketManifest -Path $path
    if ($read.ok) { return $true }
    # Allow a sync in progress one polling interval before refusing a malformed commit marker.
    return ([DateTime]::UtcNow - [IO.File]::GetLastWriteTimeUtc($path)).TotalSeconds -ge 60
}

# The startup re-scan of processing/. One action per packet folder, the order of the done criteria: a packet
# holding result.json is finished (the move to done/ resumes and loses nothing); a live claim is left alone (the
# single-instance lock is per listener - a claim of a running process is never second-guessed); a stale claim goes
# back to new/ (claim sidecar removed, attempts kept, the crash gap itself served any backoff). A packet without
# a claim sidecar counts as stale: the crash fell between the rename and the claim write.
function Invoke-InboxRecovery {
    param(
        [Parameter(Mandatory)][string]$Root,
        [int]$StaleMinutes = $script:InboxClaimStaleMinutes
    )
    $result = @{ completed = @(); requeued = @(); left = @() }
    $processingDir = Join-Path $Root 'processing'
    $newDir = Join-Path $Root 'new'
    if (-not [IO.Directory]::Exists($processingDir)) { return $result }
    foreach ($dir in [IO.Directory]::GetDirectories($processingDir)) {
        $packetId = Split-Path -Leaf $dir
        $finalStage = if ([IO.File]::Exists((Join-Path $dir 'result.json'))) { 'done' } elseif ([IO.File]::Exists((Join-Path $dir 'reason.json'))) { 'failed' } else { '' }
        if ($finalStage) {
            $donePath = Join-Path (Join-Path $Root $finalStage) $packetId
            try {
                if ([IO.Directory]::Exists($donePath)) {
                    $result.left += "$packetId ($finalStage/ already exists; inspect both copies)"
                }
                else {
                    [IO.Directory]::Move($dir, $donePath)
                    $result.completed += $packetId
                }
            }
            catch { $result.left += "$packetId (decision exists but the move failed: $($_.Exception.Message))" }
            continue
        }
        $claim = Read-InboxClaim -Root $Root -PacketId $packetId
        if ((Test-InboxClaimLiveness -Claim $claim -StaleMinutes $StaleMinutes) -ceq 'live') {
            $result.left += "$packetId (claim live)"
            continue
        }
        $claimPath = Get-InboxClaimPath -StageDir $processingDir -PacketId $packetId
        $newPath = Join-Path $newDir $packetId
        if ([IO.Directory]::Exists($newPath)) {
            $result.left += "$packetId (already back in new/)"
            continue
        }
        try {
            [IO.Directory]::Move($dir, $newPath)
            if ([IO.File]::Exists($claimPath)) { try { [IO.File]::Delete($claimPath) } catch { } }
            $attemptsPath = Get-InboxAttemptsPath -StageDir $processingDir -PacketId $packetId
            if ([IO.File]::Exists($attemptsPath)) {
                try {
                    $newAttemptsPath = Get-InboxAttemptsPath -StageDir $newDir -PacketId $packetId
                    $oldAttempts = Read-InboxAttempts $attemptsPath
                    $newAttempts = Read-InboxAttempts $newAttemptsPath
                    if ($null -ne $newAttempts -and ($null -eq $oldAttempts -or [int]$newAttempts.attempts -ge [int]$oldAttempts.attempts)) {
                        [IO.File]::Delete($attemptsPath)
                    }
                    else { [IO.File]::Move($attemptsPath, $newAttemptsPath, $true) }
                } catch { }
            }
            $result.requeued += $packetId
        }
        catch { $result.left += "$packetId (re-queue failed: $($_.Exception.Message))" }
    }
    return $result
}

function Test-InboxProcessedPacket {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$PacketId
    )
    return ([IO.Directory]::Exists((Join-Path (Join-Path $Root 'done') $PacketId)) -or
        [IO.Directory]::Exists((Join-Path (Join-Path $Root 'failed') $PacketId)))
}

function Write-InboxSpoolJson {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Document
    )
    $json = (ConvertTo-Json -InputObject $Document -Depth 12).Replace("`r`n", "`n") + "`n"
    $packetDir = Split-Path -Parent $Path
    $tmp = Join-Path (Split-Path -Parent $packetDir) ((Split-Path -Leaf $packetDir) + '.' + (Split-Path -Leaf $Path) + ".$PID.tmp")
    try {
        [IO.File]::WriteAllText($tmp, $json, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($tmp, $Path, $true)
    }
    finally { if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) } }
}

# Move processing\<id> to a final stage (done/ or failed/), both sidecars removed with it (result.json/reason.json
# hold what the decision was; the done copy is the audit).
function Move-InboxPacketToStage {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$PacketId,
        [Parameter(Mandatory)][string]$Stage
    )
    $processingDir = Join-Path $Root 'processing'
    $source = Join-Path $processingDir $PacketId
    $dest = Join-Path (Join-Path $Root $Stage) $PacketId
    if (-not [IO.Directory]::Exists($source)) { return @{ ok = $false; error = 'NotClaimed'; message = "no packet '$PacketId' in processing/" } }
    if ([IO.Directory]::Exists($dest)) { return @{ ok = $false; error = 'MoveFailed'; message = "$Stage\$PacketId already exists" } }
    try { [IO.Directory]::Move($source, $dest) }
    catch { return @{ ok = $false; error = 'MoveFailed'; message = $_.Exception.Message } }
    foreach ($side in @((Get-InboxClaimPath -StageDir $processingDir -PacketId $PacketId), (Get-InboxAttemptsPath -StageDir $processingDir -PacketId $PacketId))) {
        if ([IO.File]::Exists($side)) { try { [IO.File]::Delete($side) } catch { } }
    }
    return @{ ok = $true; path = $dest; error = $null; message = $null }
}

# INBOX-PACKET section 5: result.json beside the manifest, then the move to done/.
function Complete-InboxPacket {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$PacketId,
        [Parameter(Mandatory)]$Result
    )
    $source = Join-Path (Join-Path $Root 'processing') $PacketId
    if (-not [IO.Directory]::Exists($source)) { return @{ ok = $false; error = 'NotClaimed'; message = "no packet '$PacketId' in processing/" } }
    try {
        Write-InboxSpoolJson -Path (Join-Path $source 'result.json') -Document $Result
    }
    catch { return @{ ok = $false; error = 'ResultWriteFailed'; message = $_.Exception.Message } }
    return (Move-InboxPacketToStage -Root $Root -PacketId $PacketId -Stage 'done')
}

# INBOX-PACKET section 5: reason.json with the refusal's reason name, then the move to failed/.
function Fail-InboxPacket {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$PacketId,
        [Parameter(Mandatory)][string]$Error,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Detail
    )
    $source = Join-Path (Join-Path $Root 'processing') $PacketId
    if (-not [IO.Directory]::Exists($source)) { return @{ ok = $false; error = 'NotClaimed'; message = "no packet '$PacketId' in processing/" } }
    try {
        Write-InboxSpoolJson -Path (Join-Path $source 'reason.json') -Document ([ordered]@{ error = $Error; detail = $Detail })
    }
    catch { return @{ ok = $false; error = 'ReasonWriteFailed'; message = $_.Exception.Message } }
    return (Move-InboxPacketToStage -Root $Root -PacketId $PacketId -Stage 'failed')
}

# A claim this process made of a packet whose result already sits in done/ or failed/ is a duplicate claim - the
# crash fell between another process's decision and this claim's in-between state, and both folders hold the
# same packetId, byte for byte. The decided copy is the audit trail; the claimed copy is removed, its sidecars
# with it. Only ever called on a packet THIS process claimed (the claim is proof of the duplicate), never on a
# foreign claim.
function Remove-InboxDuplicateClaim {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$PacketId
    )
    if (-not (Test-InboxProcessedPacket -Root $Root -PacketId $PacketId)) { return $false }
    $processingDir = Join-Path $Root 'processing'
    $dir = Join-Path $processingDir $PacketId
    if (-not [IO.Directory]::Exists($dir)) { return $false }
    try { [IO.Directory]::Delete($dir, $true) }
    catch { return $false }
    foreach ($side in @((Get-InboxClaimPath -StageDir $processingDir -PacketId $PacketId), (Get-InboxAttemptsPath -StageDir $processingDir -PacketId $PacketId))) {
        if ([IO.File]::Exists($side)) { try { [IO.File]::Delete($side) } catch { } }
    }
    return $true
}

# A retryable failure: back to new/ with an attempts record and a not-before time (1, 5, 15 min), or - at the
# ceiling - left in processing/ for the caller to Fail-InboxPacket (the ceiling never re-queues: "never retried
# automatically more than the configured ceiling", plan 3.2 open question 5). The claim sidecar is removed: a
# folder in new/ with a claim still beside it would be invisible to nobody and confusing to everyone.
function Requeue-InboxPacket {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$PacketId,
        [Parameter(Mandatory)][AllowEmptyString()][string]$LastError,
        [int]$RetryCeiling = $script:InboxRetryCeiling,
        [int[]]$BackoffSeconds = $script:InboxRetryBackoffSeconds
    )
    $processingDir = Join-Path $Root 'processing'
    $newDir = Join-Path $Root 'new'
    $packetPath = Join-Path $processingDir $PacketId
    if (-not [IO.Directory]::Exists($packetPath)) { return @{ outcome = 'error'; error = 'NotClaimed'; attempts = 0; nextRetryAtEpochMs = $null } }
    $attempts = Read-InboxAttempts -Path (Get-InboxAttemptsPath -StageDir $processingDir -PacketId $PacketId)
    $count = if ($null -ne $attempts) { [int]$attempts.attempts } else { 0 }
    $count++
    if ($count -gt $RetryCeiling -or $count -gt $BackoffSeconds.Count + 1) {
        return @{ outcome = 'ceiling'; attempts = $count; nextRetryAtEpochMs = $null }
    }
    $backoff = [int]$BackoffSeconds[[Math]::Min($count - 1, $BackoffSeconds.Count - 1)]
    $record = [pscustomobject]@{
        attempts           = $count
        nextRetryAtEpochMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + [long]$backoff * 1000
        lastError          = $LastError
    }
    $claimPath = Get-InboxClaimPath -StageDir $processingDir -PacketId $PacketId
    $newPath = Join-Path $newDir $PacketId
    if ([IO.Directory]::Exists($newPath)) {
        return @{ outcome = 'error'; error = 'MoveFailed'; attempts = $count; nextRetryAtEpochMs = $null }
    }
    try {
        Write-InboxAttempts -Path (Get-InboxAttemptsPath -StageDir $newDir -PacketId $PacketId) -Attempts $record
        [IO.Directory]::Move($packetPath, $newPath)
        if ([IO.File]::Exists($claimPath)) { try { [IO.File]::Delete($claimPath) } catch { } }
        $staleAttempts = Get-InboxAttemptsPath -StageDir $processingDir -PacketId $PacketId
        if ([IO.File]::Exists($staleAttempts)) { try { [IO.File]::Delete($staleAttempts) } catch { } }
    }
    catch { return @{ outcome = 'error'; error = 'MoveFailed'; attempts = $count; nextRetryAtEpochMs = $null } }
    return @{ outcome = 'requeued'; attempts = $count; nextRetryAtEpochMs = $record.nextRetryAtEpochMs }
}

# What pq status and pq problems surface: unprocessed packets and their age. present is $false when the inbox
# root does not exist - the owner has not set the channel up, and neither verb prints anything about it.
function Get-InboxSpoolAge {
    param(
        [Parameter(Mandatory)][string]$Root,
        [int]$ThresholdSeconds = $script:InboxSpoolAgeThresholdSeconds
    )
    $result = @{
        present           = [IO.Directory]::Exists($Root)
        waiting           = 0
        processing        = 0
        stale             = 0
        oldestPacketId    = $null
        oldestAgeSeconds  = $null
        oldestAge         = 'none'
        oldestStage       = $null
        packets           = @()
    }
    if (-not $result.present) { return $result }
    $packets = [Collections.Generic.List[object]]::new()
    foreach ($stage in @('new', 'processing')) {
        $dir = Join-Path $Root $stage
        if (-not [IO.Directory]::Exists($dir)) { continue }
        foreach ($p in [IO.Directory]::GetDirectories($dir)) {
            $packetId = Split-Path -Leaf $p
            if ($stage -ceq 'new') { $result.waiting++ } else { $result.processing++ }
            $ageSeconds = Get-InboxFolderAgeSeconds $p
            $stale = ($null -ne $ageSeconds -and $ageSeconds -gt $ThresholdSeconds)
            if ($stale) { $result.stale++ }
            if ($null -eq $result.oldestAgeSeconds -or ($null -ne $ageSeconds -and $ageSeconds -gt $result.oldestAgeSeconds)) {
                $result.oldestAgeSeconds = $ageSeconds
                $result.oldestAge = ConvertTo-InboxAgeText $ageSeconds
                $result.oldestPacketId = $packetId
                $result.oldestStage = $stage
            }
            $packets.Add([pscustomobject]@{
                packetId = $packetId; stage = $stage; ageSeconds = $ageSeconds
                age      = (ConvertTo-InboxAgeText $ageSeconds); stale = $stale
            })
        }
    }
    $result.packets = @($packets | Sort-Object -Property @{ Expression = { -($_.ageSeconds ?? [long]::MaxValue) } }, packetId)
    return $result
}
