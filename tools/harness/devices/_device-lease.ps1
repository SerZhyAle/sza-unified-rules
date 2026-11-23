#requires -Version 7.0
# Machine-wide leases on test targets (canon TESTING_AND_QA section 4, skill device-lease).
#
# A lease says "this session is driving this target right now": an attached phone or watch (its adb serial), a running
# emulator or an emulator about to start (avd:<name>). The key is an opaque plain name; nothing here talks to adb.
#
# Dot-source this file; it defines functions only, sets no preference and prints nothing. Nothing here creates a file
# except Request-DeviceLease (the lease), Update-DeviceLeaseHeartbeat (its refresh) and the directory under it.
#
# THE STORE IS OUTSIDE EVERY REPOSITORY. Two sessions in two projects share one adb server, the same phones and the same
# emulator ports, so a lease kept under one repository's temp/ is invisible to the other project - which is the case that
# produces the collision. The store is <portfolio root>\devices, with the root of Get-PqRoot: SZA_PORTFOLIO_ROOT when set,
# else <USERPROFILE>\.sza\portfolio. One file per lease, <key with ':' written as '_'>.json.
#
# The shape is the ticket lease's, not the build lock's (DEVELOPMENT section 10): the claim is one atomic file creation,
# losing it is a normal outcome ("take a different target"), and there is NO queue - a sibling's scenario has no bound, so
# waiting for it does not end. Ownership is a session; liveness is Get-AgentTicketLiveness of the harness lock library
# (the owner's process, the heartbeat, the transcript write time, subagents counted), with the `Device` timings of
# Get-AgentLockTimings: quiet for SessionStaleMinutes is stale, older than TicketCeilingMinutes is abandoned. A verdict of
# 'undetermined' is never grounds for removal.
#
#   Get-DeviceLeaseDir                   <portfolio root>\devices (never creates it)
#   Test-DeviceLeaseId <key>             a plain name: letters, digits, . _ : -, at most 96, first character alphanumeric
#   Split-DeviceLeaseIds <string[]>      each element split on , and ;, trimmed, de-duplicated, order kept
#   Invoke-DeviceLease -Verb <Claim|Release|List|Status|Sweep> [-Id <keys>] [-Any] [-All] [-Reason <text>]
#       -> @{ Exit; Outcome; Text; Data }   Exit 0 done, 1 error, 3 claim lost, 4 release refused.
#          Claim takes every key or none; with -Any it takes the first key that is free. Release is owner-checked;
#          with -All it releases every lease of this session. List is the keys of the live leases; Status is who holds
#          what; Sweep drops the stale ones (every other verb sweeps first).

. (Join-Path $PSScriptRoot '..\_profile.ps1')
. (Get-SzaHarnessScript 'locks/agent-lock.ps1')
. (Get-SzaHarnessScript 'portfolio/lib/paths.ps1')

$script:DeviceLeaseIdPattern = '^[A-Za-z0-9][A-Za-z0-9._:-]{0,95}$'

function Get-DeviceLeaseDir { return (Join-Path (Get-PqRoot) 'devices') }

function Test-DeviceLeaseId([string]$Id) { return ($Id -cmatch $script:DeviceLeaseIdPattern) }

function Get-DeviceLeasePath([string]$Id) {
    return (Join-Path (Get-DeviceLeaseDir) (($Id -replace ':', '_') + '.json'))
}

function Split-DeviceLeaseIds([string[]]$Id) {
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $out = [Collections.Generic.List[string]]::new()
    foreach ($raw in @($Id)) {
        foreach ($part in ([string]$raw -split '[,;]')) {
            $key = $part.Trim()
            if ($key -and $seen.Add($key)) { $out.Add($key) }
        }
    }
    return $out.ToArray()
}

function Get-DeviceLeaseProject {
    try { return (Split-Path -Leaf (Get-SzaProjectRoot)) }
    catch { return (Split-Path -Leaf (Get-Location).Path) }
}

function Read-DeviceLease([string]$Path) {
    try { return (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json) }
    catch { return $null }
}

# The harness liveness reads a ticket-shaped record; a lease's own field is claimedAt, so it is shimmed across.
function Get-DeviceLeaseLiveness($Lease, [int]$StaleMinutes) {
    $shim = [pscustomobject]@{
        sessionId      = $Lease.sessionId
        transcriptPath = $Lease.transcriptPath
        lastSeenAt     = $Lease.lastSeenAt
        enqueuedAt     = $Lease.claimedAt
    }
    return (Get-AgentTicketLiveness -Ticket $shim -StaleMinutes $StaleMinutes)
}

function Get-DeviceLeaseAgeMinutes($Lease) {
    if (-not $Lease.claimedAt) { return [double]::MaxValue }
    $claimed = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$Lease.claimedAt).LocalDateTime
    return ((Get-Date) - $claimed).TotalMinutes
}

# Minutes since the holder's session last wrote anything, or $null when that cannot be read.
function Get-DeviceLeaseSeenMinutes($Lease) {
    $transcript = [string]$Lease.transcriptPath
    if ([string]::IsNullOrWhiteSpace($transcript)) { return $null }
    $seen = Get-AgentSessionTranscriptLastWrite -TranscriptPath $transcript
    if ($null -eq $seen) { return $null }
    return [math]::Round(((Get-Date) - $seen).TotalMinutes, 1)
}

function Format-DeviceLeaseHolder($Lease) {
    $session = [string]$Lease.sessionId
    if ($session.Length -gt 8) { $session = $session.Substring(0, 8) }
    $project = [string]$Lease.project
    if (-not $project) { $project = 'unknown project' }
    $seen = Get-DeviceLeaseSeenMinutes $Lease
    $when = if ($null -ne $seen) { "seen $seen min ago" } else { 'last activity unknown' }
    return ("session {0} of {1} on {2}, {3}, reason '{4}'" -f $session, $project, $Lease.host, $when, $Lease.reason)
}

# Drops a lease whose session went quiet, or that passed the absolute ceiling whatever its liveness (a transcript that
# keeps growing while the target was abandoned). 'undetermined' is skipped: it means THIS caller has no identity, so mine
# and theirs cannot be told apart and a removal would be a guess.
function Invoke-DeviceLeaseSweep {
    $dir = Get-DeviceLeaseDir
    $removed = [Collections.Generic.List[string]]::new()
    if (-not [IO.Directory]::Exists($dir)) { return @() }
    $timings = Get-AgentLockTimings -Name Device
    foreach ($file in (Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        $lease = Read-DeviceLease $file.FullName
        if ($null -eq $lease) {
            # A reader between the create and the write sees an empty file; only an old one is garbage.
            if (((Get-Date) - $file.LastWriteTime).TotalSeconds -gt 60) {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
                $removed.Add($file.BaseName)
            }
            continue
        }
        $liveness = Get-DeviceLeaseLiveness $lease $timings.SessionStaleMinutes
        if ($liveness -eq 'undetermined') { continue }
        if ($liveness -eq 'foreign-stale' -or (Get-DeviceLeaseAgeMinutes $lease) -gt $timings.TicketCeilingMinutes) {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
            $removed.Add([string]$lease.id)
        }
    }
    return @($removed)
}

function Get-DeviceLeases {
    $dir = Get-DeviceLeaseDir
    $out = [Collections.Generic.List[object]]::new()
    if (-not [IO.Directory]::Exists($dir)) { return @() }
    $timings = Get-AgentLockTimings -Name Device
    foreach ($file in (Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        $lease = Read-DeviceLease $file.FullName
        if ($null -eq $lease) { continue }
        $liveness = Get-DeviceLeaseLiveness $lease $timings.SessionStaleMinutes
        $out.Add([pscustomobject]@{
                id              = [string]$lease.id
                sessionId       = [string]$lease.sessionId
                project         = [string]$lease.project
                host            = [string]$lease.host
                pid             = $lease.pid
                reason          = [string]$lease.reason
                claimedAt       = $lease.claimedAt
                ageMinutes      = [math]::Round((Get-DeviceLeaseAgeMinutes $lease), 1)
                lastSeenMinutes = (Get-DeviceLeaseSeenMinutes $lease)
                liveness        = $liveness
                mine            = ($liveness -eq 'self')
            })
    }
    return @($out | Sort-Object id)
}

function Write-DeviceLeaseFile([string]$Path, [string]$Id, [string]$SessionId, [string]$Reason, [string]$Project) {
    # The transcript path is looked up before the file is opened, so the empty file a reader could catch lives for
    # microseconds, not for the length of a directory scan.
    $payload = [ordered]@{
        schema         = 1
        id             = $Id
        sessionId      = $SessionId
        project        = $Project
        host           = $env:COMPUTERNAME
        pid            = $PID
        reason         = $Reason
        claimedAt      = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        # Refreshed by Update-DeviceLeaseHeartbeat; claimedAt stays frozen so activity cannot extend the ceiling.
        lastSeenAt     = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        transcriptPath = (Get-AgentSessionTranscriptPath -SessionId $SessionId)
    }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($payload | ConvertTo-Json -Depth 4 -Compress))
    # CreateNew makes "does it exist" and "create it" one filesystem call: two sessions racing for one target cannot both
    # win, and the IOException is the loser, not a fault.
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
}

# Every verb a session runs refreshes the leases it owns, so a session that is plainly active is never judged gone.
# Write-then-rename, best effort: a missed refresh costs a delay, never a stuck target.
function Update-DeviceLeaseHeartbeat([string]$SessionId) {
    $dir = Get-DeviceLeaseDir
    if (-not [IO.Directory]::Exists($dir)) { return }
    foreach ($file in (Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        $lease = Read-DeviceLease $file.FullName
        if ($null -eq $lease -or [string]$lease.sessionId -ne $SessionId) { continue }
        try {
            $lease | Add-Member -NotePropertyName 'lastSeenAt' -NotePropertyValue ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Force
            $staging = "$($file.FullName).tmp-$PID"
            Set-Content -LiteralPath $staging -Value ($lease | ConvertTo-Json -Depth 4 -Compress) -Encoding utf8NoBOM -ErrorAction Stop
            Move-Item -LiteralPath $staging -Destination $file.FullName -Force -ErrorAction Stop
        }
        catch { }
    }
}

# One key: claimed, already-mine, or lost (with the holder's record).
function Request-DeviceLease([string]$Id, [string]$SessionId, [string]$Reason, [string]$Project) {
    $dir = Get-DeviceLeaseDir
    if (-not [IO.Directory]::Exists($dir)) { $null = [IO.Directory]::CreateDirectory($dir) }
    $path = Get-DeviceLeasePath $Id
    if ([IO.File]::Exists($path)) {
        $existing = Read-DeviceLease $path
        if ($null -ne $existing -and [string]$existing.sessionId -eq $SessionId) { return @{ state = 'already-mine'; id = $Id; holder = $existing } }
    }
    try {
        Write-DeviceLeaseFile -Path $path -Id $Id -SessionId $SessionId -Reason $Reason -Project $Project
        return @{ state = 'claimed'; id = $Id; holder = $null }
    }
    catch [IO.IOException] {
        return @{ state = 'lost'; id = $Id; holder = (Read-DeviceLease $path) }
    }
}

function New-DeviceLeaseResult([int]$Exit, [string]$Outcome, [string]$Text, $Data) {
    return [pscustomobject]@{ Exit = $Exit; Outcome = $Outcome; Text = $Text; Data = $Data }
}

function Invoke-DeviceLease {
    param(
        [Parameter(Mandatory)][ValidateSet('Claim', 'Release', 'List', 'Status', 'Sweep')][string]$Verb,
        [string[]]$Id = @(),
        [switch]$Any,
        [switch]$All,
        [string]$Reason = 'device-lease'
    )
    $ids = @(Split-DeviceLeaseIds $Id)
    foreach ($key in $ids) {
        if (-not (Test-DeviceLeaseId $key)) {
            return (New-DeviceLeaseResult 1 'bad-id' "device-lease: '$key' is not a plain target name (letters, digits and . _ : -, at most 96)." $null)
        }
    }
    $sessionId = Get-AgentSessionId
    Update-DeviceLeaseHeartbeat -SessionId $sessionId

    switch ($Verb) {
        'Claim' {
            if ($ids.Count -eq 0) { return (New-DeviceLeaseResult 1 'no-id' 'device-lease: -Id is required for Claim.' $null) }
            [void](Invoke-DeviceLeaseSweep)
            $project = Get-DeviceLeaseProject
            $lost = [Collections.Generic.List[object]]::new()
            if ($Any) {
                foreach ($key in $ids) {
                    $r = Request-DeviceLease $key $sessionId $Reason $project
                    if ($r.state -ne 'lost') {
                        $outcome = if ($r.state -eq 'claimed') { 'claimed' } else { 'already-mine' }
                        $verbText = if ($r.state -eq 'claimed') { 'claimed' } else { 'already held by this session' }
                        return (New-DeviceLeaseResult 0 $outcome "device-lease: $key $verbText." ([pscustomobject]@{ outcome = $outcome; id = $key; ids = @($key); sessionId = $sessionId }))
                    }
                    $lost.Add($r)
                }
            }
            else {
                $took = [Collections.Generic.List[string]]::new()
                foreach ($key in $ids) {
                    $r = Request-DeviceLease $key $sessionId $Reason $project
                    if ($r.state -eq 'lost') { $lost.Add($r); break }
                    if ($r.state -eq 'claimed') { $took.Add($key) }
                }
                if ($lost.Count -eq 0) {
                    $outcome = if ($took.Count -gt 0) { 'claimed' } else { 'already-mine' }
                    $text = if ($took.Count -gt 0) { 'device-lease: claimed ' + ($ids -join ', ') + '.' } else { 'device-lease: ' + ($ids -join ', ') + ' already held by this session.' }
                    return (New-DeviceLeaseResult 0 $outcome $text ([pscustomobject]@{ outcome = $outcome; id = $ids[0]; ids = @($ids); sessionId = $sessionId }))
                }
                # All or nothing: what this call took is given back, so half a set never stays held.
                foreach ($key in $took) { Remove-Item -LiteralPath (Get-DeviceLeasePath $key) -Force -ErrorAction SilentlyContinue }
            }
            $first = $lost[0]
            $holderText = if ($null -ne $first.holder) { Format-DeviceLeaseHolder $first.holder } else { 'a session that could not be read' }
            $names = ($lost | ForEach-Object { $_.id }) -join ', '
            $text = "device-lease: $names held by $holderText. Take a different target or defer the device stage; do not wait for it and do not touch it."
            $heldBy = if ($null -ne $first.holder) { [string]$first.holder.sessionId } else { 'unknown' }
            $heldProject = if ($null -ne $first.holder) { [string]$first.holder.project } else { '' }
            return (New-DeviceLeaseResult 3 'claim-lost' $text ([pscustomobject]@{ outcome = 'claim-lost'; id = $first.id; ids = @($lost | ForEach-Object { $_.id }); heldBy = $heldBy; project = $heldProject }))
        }
        'Release' {
            if ($All) {
                $mine = @(Get-DeviceLeases | Where-Object { $_.mine } | ForEach-Object { $_.id })
                $ids = @($ids + $mine)
            }
            if ($ids.Count -eq 0) {
                if ($All) { return (New-DeviceLeaseResult 0 'absent' 'device-lease: this session holds no lease.' ([pscustomobject]@{ outcome = 'absent'; released = @(); refused = @() })) }
                return (New-DeviceLeaseResult 1 'no-id' 'device-lease: -Id or -All is required for Release.' $null)
            }
            $timings = Get-AgentLockTimings -Name Device
            $released = [Collections.Generic.List[string]]::new()
            $refused = [Collections.Generic.List[string]]::new()
            $absent = [Collections.Generic.List[string]]::new()
            foreach ($key in $ids) {
                $path = Get-DeviceLeasePath $key
                if (-not [IO.File]::Exists($path)) { $absent.Add($key); continue }
                $lease = Read-DeviceLease $path
                $liveness = if ($null -ne $lease) { Get-DeviceLeaseLiveness $lease $timings.SessionStaleMinutes } else { 'foreign-stale' }
                if ($liveness -eq 'foreign-live') { $refused.Add($key); continue }
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
                $released.Add($key)
            }
            $data = [pscustomobject]@{ outcome = ''; released = @($released); refused = @($refused); absent = @($absent) }
            if ($refused.Count -gt 0) {
                $data.outcome = 'release-refused'
                return (New-DeviceLeaseResult 4 'release-refused' ('device-lease: refusing to release ' + ($refused -join ', ') + ' - a live session owns it.') $data)
            }
            $outcome = if ($released.Count -gt 0) { 'released' } else { 'absent' }
            $data.outcome = $outcome
            $text = if ($released.Count -gt 0) { 'device-lease: released ' + ($released -join ', ') + '.' } else { 'device-lease: ' + ($absent -join ', ') + ' holds no lease.' }
            return (New-DeviceLeaseResult 0 $outcome $text $data)
        }
        'List' {
            [void](Invoke-DeviceLeaseSweep)
            $keys = @(Get-DeviceLeases | ForEach-Object { $_.id })
            return (New-DeviceLeaseResult 0 'listed' ($keys -join "`n") $keys)
        }
        'Status' {
            [void](Invoke-DeviceLeaseSweep)
            $leases = @(Get-DeviceLeases)
            if ($leases.Count -eq 0) { return (New-DeviceLeaseResult 0 'listed' 'device-lease: no target is leased.' $leases) }
            $lines = foreach ($l in $leases) {
                $who = if ($l.mine) { 'this session' } else { $l.sessionId.Substring(0, [math]::Min(8, $l.sessionId.Length)) }
                $seen = if ($null -ne $l.lastSeenMinutes) { "$($l.lastSeenMinutes) min ago" } else { 'unknown' }
                '  {0,-28} {1,-13} {2,-22} seen {3,-12} {4}' -f $l.id, $who, $l.project, $seen, $l.reason
            }
            return (New-DeviceLeaseResult 0 'listed' ($lines -join "`n") $leases)
        }
        'Sweep' {
            $removed = @(Invoke-DeviceLeaseSweep)
            $text = if ($removed.Count -eq 0) { 'device-lease: nothing to sweep.' } else { 'device-lease: swept ' + $removed.Count + ' stale lease(s): ' + ($removed -join ', ') }
            return (New-DeviceLeaseResult 0 'swept' $text ([pscustomobject]@{ outcome = 'swept'; removed = $removed }))
        }
    }
}
