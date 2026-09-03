<#
.SYNOPSIS
    One-process preamble for a ticket-bound skill: resolve the record, claim the lease, check drift,
    query the document registry and print ONE block the skill reads once.
.DESCRIPTION
    S2400: /spec-all, /spec-dev and /spec-check opened a ticket with four to six separate calls -
    select.ps1, ticket-lease.ps1 Claim, drift-check.ps1, one document_registry/query.ps1 per facet -
    each 0.0-1.8 s on its own and each followed by a full model turn before the next one could start.
    Measured 2026-09-02 over the S2400 run: 76 Bash calls, 213 s of tool wait, the scripts themselves
    a small fraction of it. The wait was never the scripts; it was the round trips. Backgrounding a
    sub-second call buys nothing (the completion notice costs a turn of its own), so the fix is one
    interpreter running all of the preamble and one block to read.

    Steps, in order, all in this process:
      1. Resolve the id across both journals (select.ps1's rule) - the spec file, tactical folder and
         `## Last Audit` presence are read off disk so the resume map can be keyed without a re-read.
      2. Claim the ticket lease (skipped under -NoLease). ticket-lease.ps1 owns the rule; its exit 3
         is forwarded unchanged so the caller stops before any work.
      3. Drift check - by default only for the statuses whose resume path delegates to planning
         (Draft, Approved, Tactical, Broken), which is the set /spec-all 0a-drift names; -Drift forces
         it for any status, -NoDrift suppresses it. The verdict is printed, never turned into an exit
         code: the caller branches on the word, and the lease must not be lost to a stale marker.
      4. Document-registry query, one call per facet given (-ProductArea, -Trigger); query.ps1's own
         resolution ladder and vocabulary fallback are printed verbatim, indented.

    Exit codes:
      0  record resolved and (unless -NoLease) the lease is owned by this session. Drift and the
         registry are informational and never change the code.
      2  usage error, or the id is in neither journal - "this ticket does not exist", which calls for
         the opposite reaction to a refused lease.
      3  a live sibling session owns the lease (ticket-lease.ps1's own code) - stop before any work.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^S\d{4}$')][string] $Id,
    [string] $Reason = 'spec-preamble',
    [string] $ProductArea,
    [string] $Trigger,
    [switch] $NoLease,
    # S2404: the handoff path a previous claim printed. Forwarded verbatim to the lease child,
    # so a runtime with no session id can re-claim through the preamble instead of exiting 3 -
    # the preamble is the only call /spec-dev claims through, so printing the path without
    # accepting one left the ticket's own symptom alive on the path most drivers use.
    [string] $Handoff,
    [switch] $Drift,
    [switch] $NoDrift,
    [switch] $Json
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')

trap {
    Write-Host "spec-preamble: $_" -ForegroundColor Red
    exit 2
}

. (Join-Path $PSScriptRoot '_lib.ps1')

$repoRoot   = (Get-SzaProjectRoot)
$leasePs1   = (Get-SzaHarnessScript 'locks/ticket-lease.ps1')
$driftPs1   = Join-Path $PSScriptRoot 'drift-check.ps1'
$registryPs1 = (Get-SzaHarnessScript 'document_registry/query.ps1')
$driftStatuses = @('Draft', 'Approved', 'Tactical', 'Broken')

# 1. Record + what is on disk for it.
$record = Find-Record -Id $Id
if ($null -eq $record) {
    Write-Host "spec-preamble: $Id is in neither journal." -ForegroundColor Red
    exit 2
}
$specPath = Resolve-SpecPath -PathRef ([string]$record.file)
$specExists = Test-Path -LiteralPath $specPath -PathType Leaf
$lastAudit = $false
if ($specExists) {
    # Answered by the same code as the closing gate and preview.ps1, never by a second pattern of
    # our own: the operator's flag and the gate's verdict may not disagree (S1621), and a local
    # copy had already drifted - it missed `## 5.1 Last Audit`, on which /spec-all's 0a-drift then
    # sent a ticket with a written verdict back through a full re-audit. The call is free:
    # _lib.ps1 dot-sources _research-items.ps1, so both functions are already in scope.
    $lastAudit = @(Get-SpecSectionLines -Path $specPath -HeadingPattern (Get-AuditSectionHeadingPattern)).Count -gt 0
}
$tacticalDir = [System.IO.Path]::ChangeExtension($specPath, $null).TrimEnd('.')
$phaseCount = 0
$tacticalExists = Test-Path -LiteralPath $tacticalDir -PathType Container
if ($tacticalExists) {
    $phaseCount = @(Get-ChildItem -LiteralPath $tacticalDir -Filter 'PHASE_*.md' -File).Count
}
$status = [string]$record.status
$tier = if ($record.PSObject.Properties.Match('tier').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$record.tier)) {
    [string]$record.tier
} else {
    'not assigned'
}

# 2. Lease.
$leaseExit = $null
$leaseLines = @()
if (-not $NoLease) {
    # Child scripts run with strict mode OFF: _lib.ps1 turns it on for this scope, child scopes inherit
    # it, and query.ps1 reads .Count off a scalar - correct under its own defaults, fatal under ours.
    # Hashtable, not an array: splatting an ARRAY at a script binds positionally, so the child
    # received the literal string '-Verb' as its -Verb value and failed its own ValidateSet.
    $leaseArgs = @{ Verb = 'Claim'; Id = $Id; Reason = $Reason }
    if (-not [string]::IsNullOrWhiteSpace($Handoff)) { $leaseArgs['Handoff'] = $Handoff }
    $leaseLines = @(& { Set-StrictMode -Off; & $leasePs1 @leaseArgs *>&1 } | ForEach-Object { "$_" })
    $leaseExit = $LASTEXITCODE
}

# S2404: the claim prints the handoff path a no-session-id runtime must carry into later lease
# verbs; surface it as its own field so it cannot get lost inside the joined child output.
$leaseHandoff = $null
$handoffLine = @($leaseLines | Where-Object { $_ -like '*lease handoff:*' } | Select-Object -First 1)
if ($handoffLine.Count -gt 0 -and $handoffLine[0] -match 'lease handoff:\s*(\S+)') { $leaseHandoff = $Matches[1] }

# 3. Drift.
$driftVerdict = 'skipped'
$driftMarkers = 0
$driftFiles = 0
$runDrift = ($Drift -or ($driftStatuses -contains $status)) -and -not $NoDrift
if ($runDrift) {
    $driftRaw = @(& { Set-StrictMode -Off; & $driftPs1 -Id $Id -Format json 2>&1 } | ForEach-Object { "$_" }) -join "`n"
    $driftExit = $LASTEXITCODE
    try {
        $driftObj = $driftRaw | ConvertFrom-Json
        $driftVerdict = [string]$driftObj.verdict
        $markers = @($driftObj.code_markers)
        $driftMarkers = $markers.Count
        $driftFiles = @($markers | ForEach-Object { $_.file } | Select-Object -Unique).Count
    } catch {
        # A drift-check that could not resolve (exit 2) prints prose, not JSON - keep its words.
        $driftVerdict = "unreadable (exit $driftExit): $($driftRaw -replace '\s+', ' ')"
    }
}

# 4. Registry, one call per facet - the skill asks for the area and the trigger separately.
$registryBlocks = @()
foreach ($facet in @(@{ Name = 'ProductArea'; Value = $ProductArea }, @{ Name = 'Trigger'; Value = $Trigger })) {
    if (-not $facet.Value) { continue }
    # Not `$args`: that is PowerShell's automatic unbound-arguments variable, and splatting it passed
    # nothing through - the query answered unfiltered and the block listed the whole registry.
    $facetArgs = @{ $facet.Name = $facet.Value }
    $lines = @(& { Set-StrictMode -Off; & $registryPs1 @facetArgs *>&1 } | ForEach-Object { "$_" } | Where-Object { $_.Trim() })
    $registryBlocks += [pscustomobject]@{ facet = $facet.Name; value = $facet.Value; lines = $lines }
}

if ($Json) {
    [pscustomobject]@{
        id             = $Id
        status         = $status
        file           = [string]$record.file
        spec_exists    = $specExists
        last_audit     = $lastAudit
        tactical       = $tacticalExists
        phase_files    = $phaseCount
        tier           = $tier
        priority       = $record.priority
        lease_exit     = $leaseExit
        lease          = ($leaseLines -join ' ')
        lease_handoff  = $leaseHandoff
        drift          = $driftVerdict
        drift_markers  = $driftMarkers
        drift_files    = $driftFiles
        registry       = $registryBlocks
    } | ConvertTo-Json -Depth 5 -Compress
} else {
    Write-Host "spec-preamble $Id"
    Write-Host ("  status:   {0}   tier: {1}   priority: {2}" -f $status, $tier, $record.priority)
    $fileNote = if ($specExists) { '' } else { '   (MISSING on disk)' }
    Write-Host ("  file:     {0}{1}" -f $record.file, $fileNote)
    $tacticalNote = if ($tacticalExists) { "present, $phaseCount phase file(s)" } else { 'none' }
    Write-Host ("  tactical: {0}   last audit: {1}" -f $tacticalNote, $(if ($lastAudit) { 'present' } else { 'absent' }))
    if ($NoLease) {
        Write-Host '  lease:    not requested (-NoLease)'
    } else {
        Write-Host ("  lease:    exit {0} - {1}" -f $leaseExit, (($leaseLines -join ' ') -replace '^ticket-lease:\s*', ''))
        if ($leaseHandoff) { Write-Host ("  lease handoff: {0}" -f $leaseHandoff) }
    }
    if ($runDrift) {
        $driftNote = if ($driftVerdict -eq 'DRIFT') { " - $driftMarkers marker(s) in $driftFiles file(s)" } else { '' }
        Write-Host ("  drift:    {0}{1}" -f $driftVerdict, $driftNote)
    } else {
        Write-Host ("  drift:    skipped (status {0} resumes past planning; -Drift forces it)" -f $status)
    }
    foreach ($block in $registryBlocks) {
        Write-Host ("  registry -{0} '{1}':" -f $block.facet, $block.value)
        foreach ($line in $block.lines) { Write-Host "    $line" }
    }
}

if ($leaseExit -eq 3) { exit 3 }
exit 0
