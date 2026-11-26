#requires -Version 7.0
<#
.SYNOPSIS
    One writer of the contracts catalog at a time (CANONR-0225).

.DESCRIPTION
    Every canon session - attended or an unattended queue pass - shares this checkout, and only a canon session
    writes the catalog (rules/CONTRACTS.md). Two of them amending one contract at once bumped it to the same
    version number in the same minute. This lock serialises them: take it before the "Before <task>" catalog
    snapshot, read the contract's current version only after it is granted, and release it after the closing
    snapshot.

    The lock file is temp/contracts-writer.lock in this checkout - never inside the catalog, whose snapshot
    commit would record it. Its owner is the agent identity of tools/harness/locks/agent-identity.ps1. A holder
    is stale when its host-/pid- process is gone. An identity that names no process (a session guid) is paired
    with the host process of the session that took the lock, recorded as hostId: the holder is stale when that
    process is gone (a headless pass that ended on a usage limit, CANONR-0240), and in any case when the lock is
    older than -StaleHours. A record without hostId (written before CANONR-0240, or with the host walk off)
    falls back to the clock alone.

.PARAMETER Acquire
    Take the lock for -Ticket. Re-entrant for the same owner.

.PARAMETER Release
    Give the lock back. Only the owner releases; -Force releases whoever holds it (owner use only).

.PARAMETER Status
    Print "free" or the holder line.

.NOTES
    Exit codes:
    0 - acquired, released, or status printed.
    2 - bad arguments, or -Release by a session that does not hold the lock.
    4 - another live session holds the lock; the holder is printed. Wait and run -Acquire again.
#>
[CmdletBinding(DefaultParameterSetName = 'Status')]
param(
    [Parameter(ParameterSetName = 'Acquire', Mandatory)][switch]$Acquire,
    [Parameter(ParameterSetName = 'Acquire', Mandatory)][string]$Ticket,
    [Parameter(ParameterSetName = 'Release', Mandatory)][switch]$Release,
    [Parameter(ParameterSetName = 'Release')][switch]$Force,
    [Parameter(ParameterSetName = 'Status')][switch]$Status,
    [double]$StaleHours = 2,
    [string]$LockPath = (Join-Path $PSScriptRoot '..\temp\contracts-writer.lock')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'harness\locks\agent-identity.ps1')

$LockPath = [IO.Path]::GetFullPath($LockPath)
$me = Get-AgentIdentity

function Read-Holder {
    if (-not (Test-Path -LiteralPath $LockPath)) { return $null }
    try { return Get-Content -LiteralPath $LockPath -Raw | ConvertFrom-Json } catch { return $null }
}

function Test-HolderStale([object]$Holder) {
    if ($null -eq $Holder -or [string]::IsNullOrWhiteSpace([string]$Holder.owner)) { return $true }
    $since = [datetime]::MinValue
    if (-not [datetime]::TryParse([string]$Holder.since, [ref]$since)) { return $true }
    $owner = [string]$Holder.owner
    if ($owner -match '^(host|pid)-') {
        return -not (Test-AgentIdentityProcessAlive -Id $owner -NotStartedAfter $since)
    }
    if (((Get-Date) - $since).TotalHours -gt $StaleHours) { return $true }
    $hostProp = $Holder.PSObject.Properties['hostId']
    $hostId = if ($null -ne $hostProp) { [string]$hostProp.Value } else { '' }
    if ($hostId -match '^(host|pid)-') {
        return -not (Test-AgentIdentityProcessAlive -Id $hostId -NotStartedAfter $since)
    }
    return $false
}

function Format-Holder([object]$Holder) {
    return "held by $($Holder.name) ($($Holder.owner)) for $($Holder.ticket) since $($Holder.since)"
}

$holder = Read-Holder

if ($PSCmdlet.ParameterSetName -eq 'Status') {
    if ($null -eq $holder) { 'free' }
    elseif (Test-HolderStale $holder) { "free (stale: $(Format-Holder $holder))" }
    else { Format-Holder $holder }
    exit 0
}

if ($Release) {
    if ($null -eq $holder) { 'already free'; exit 0 }
    if (-not $Force -and [string]$holder.owner -cne $me.id) {
        Write-Error "not yours to release: $(Format-Holder $holder)" -ErrorAction Continue
        exit 2
    }
    Remove-Item -LiteralPath $LockPath -Force
    "released ($($holder.ticket))"
    exit 0
}

# Acquire
if ($null -ne $holder) {
    if ([string]$holder.owner -ceq $me.id) { "already yours: $(Format-Holder $holder)"; exit 0 }
    if (-not (Test-HolderStale $holder)) { "busy: $(Format-Holder $holder)"; exit 4 }
    Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue
}

$record = [ordered]@{
    owner  = $me.id
    name   = $me.name
    ticket = $Ticket
    since  = (Get-Date).ToString('o')
}
# A session guid names no process, so the session's host process is recorded beside it (CANONR-0240).
if ([string]$me.id -notmatch '^(host|pid)-') {
    $hostId = Get-AgentHostIdentityId
    if (-not [string]::IsNullOrWhiteSpace($hostId)) { $record.hostId = $hostId }
}
$record = $record | ConvertTo-Json -Compress

$dir = Split-Path -Parent $LockPath
if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
try {
    # CreateNew is the atomic step: of two sessions racing past the check above, exactly one creates the file.
    $stream = [IO.File]::Open($LockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($record)
        $stream.Write($bytes, 0, $bytes.Length)
    }
    finally { $stream.Dispose() }
}
catch [System.IO.IOException] {
    $other = Read-Holder
    if ($null -ne $other) { "busy: $(Format-Holder $other)" } else { 'busy: another session is taking the lock' }
    exit 4
}
"acquired for $Ticket"
exit 0
