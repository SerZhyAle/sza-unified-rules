#requires -Version 7.0
<#
.SYNOPSIS
    Ingest the phone-ticket inbox: a claimed packet into a real Draft ticket, through the shared capture path.

.DESCRIPTION
    The packet half of S0046: watch-inbox.ps1 claims a packet folder that arrived in the inbox root (S0045's
    transport), and this script - or the library it wraps - turns it into tickets: one in the named project, or
    one in each of projects[] (cross-linked), or in canon when no project is named, and in canon (with the asked
    key quoted) when the phone's key is stale. Every capture goes through spec-draft.ps1, so the ledger row, the
    spec file and the queue row are written by the project's own capture tool, never by hand.

    A processed packet moves to done\<packetId>\ with result.json beside the manifest: { packetId, tickets,
    verdict, at }; the phone sees the move on its next Drive sync. A refused or failed packet moves to
    failed\<packetId>\ with reason.json { error, detail }, and is retried automatically at most the ceiling of
    times (transient failures: a locked repo, a bad invocation, exit 1 or 2 - the backoff is 1, 5, 15 minutes).
    A re-dropped packet already in done/ or failed/ is skipped: no packet is ingested twice.

    The crashed-before-finished case is covered twice: a processing/ packet whose result.json exists is moved to
    done/ here (the crash fell between the result write and the move), and a stale claim - one whose claim.json
    heartbeated longer ago than the lease window (45 minutes) and whose process is gone - is re-queued to new/.
    A live claim is never touched: another working watcher owns it.

    Every decision writes one event line into the portfolio event log (log\events-*.jsonl), the additive
    'ingest.packet' of EVENTS.md 3.9: d = { packetId, outcome (accepted|refused|processed|failed), project,
    tickets*, reason* }. Old readers ignore the name.

.PARAMETER Packet
    One packet folder, in new\ (claimed here) or in processing\ (resumed).

.PARAMETER All
    Drain: every claimable packet in new\, one after another, until none is left. What S0047's periodic drain
    calls.

.PARAMETER InboxRoot
    The inbox root (INBOX-PACKET section 1): -InboxRoot, else SZA_INBOX_ROOT, else C:\GD\SZA\ticket-inbox.

.PARAMETER NoRecover
    Skip the startup re-scan of processing\ (the caller did one already).

.PARAMETER StaleMinutes
    The claim liveness window, the lease rule already used for tickets (45 minutes).

.PARAMETER SpecDraft
    The capture entry point; default spec-draft.ps1 beside this script (SZA_SPEC_DRAFT overrides).

.EXAMPLE
    pwsh -NoProfile -File ingest-inbox.ps1 -All
    Drain the inbox (what the watcher does per packet, in one call).

.Exit codes
    0 every packet decided (done/ or failed/; a re-queued retry wait included)
    1 a packet left undecided in processing\
    2 bad invocation (no packet to ingest, an unclaimable one, a bad inbox root)
    3 -All and nothing was pending
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Packet = '',
    [switch]$All,
    [string]$InboxRoot = '',
    [switch]$NoRecover,
    [int]$StaleMinutes = 0,
    [int]$RetryCeiling = 0,
    [int[]]$BackoffSeconds = @(),
    [long]$MaxPacketBytes = 0,
    [int]$MaxFiles = 0,
    [string]$SpecDraft = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cli = @{ Packet = $Packet; All = $All; InboxRoot = $InboxRoot; NoRecover = $NoRecover }
if ($StaleMinutes -gt 0) { $cli.StaleMinutes = $StaleMinutes }
if ($RetryCeiling -gt 0) { $cli.RetryCeiling = $RetryCeiling }
if (@($BackoffSeconds).Count -gt 0) { $cli.BackoffSeconds = $BackoffSeconds }
if ($MaxPacketBytes -gt 0) { $cli.MaxPacketBytes = $MaxPacketBytes }
if ($MaxFiles -gt 0) { $cli.MaxFiles = $MaxFiles }
if ($SpecDraft) { $cli.SpecDraft = $SpecDraft }

. (Join-Path $PSScriptRoot 'lib\inbox-ingest.ps1')
exit (Invoke-InboxIngestCli @cli)
