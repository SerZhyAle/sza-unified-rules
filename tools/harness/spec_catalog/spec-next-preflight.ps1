# spec-next-preflight.ps1 - One-shot selection preflight for /spec-next
#
# Collapses the per-round boilerplate that /spec-next used to run as 4+ separate
# calls (search.ps1 rank + skip-cache list + preview.ps1 per candidate + drift-check.ps1)
# into a single read-only invocation that returns:
#   - the full ranked eligible list, ordered by the owner's release plan
#     (PLAN/RELEASE_QUEUE.md: package asc, then line order inside the package),
#     with catalog priority desc / updated desc / id asc only as the fallback for a
#     ticket the queue does not list,
#   - the active persistent skip-cache and which ranked ids it removed,
#   - candidates auto-skipped while walking down the list (the skill persists
#     these to skip-cache itself - this script never mutates),
#   - the selected ticket with its full preview.ps1 payload + drift-check verdict.
#
# READ-ONLY by default: no writes to the catalog, the skip-cache, or any spec.
# That keeps `/spec-next --dry` pure and leaves every mutation (skip-cache add,
# status sync, status transitions) owned by the skill / by /spec-all.
#
# -Claim makes the pick and the reservation one step: the ticket lease is the only thing it writes.
# A ranking that only READS the lease store cannot stop two pickers taking one ticket - both read
# "free", both select it, and the claim made later by whoever acts on the pick decides the race
# after the loser already spent its run. Measured 2026-10-18 over the runner journals: six pairs of
# instances started the same ticket within a minute in fourteen days, every loser journalled as
# no-progress-or-claim-lost or claim-lost-before-launch, which also counts toward its idle hold.
# Under -Claim the walk claims each surviving candidate with ticket-lease.ps1 (an atomic create)
# and a lost claim walks on to the next candidate, so the caller receives a ticket it already owns
# and the loser of a race never sees the contested id at all. A caller that then decides not to work
# the ticket releases it (ticket-lease.ps1 -Verb Release -Id <id>, with -Handoff
# <selected.lease.handoff_path> in a runtime without a session id).
#
# -ClaimAs <id> claims for another identity - the queue runner reserving a ticket for the child it is
# about to launch under that session id. It sets <envPrefix>_AGENT_ID for this process, so the lease
# store's "mine" verdict and the claim both speak as that identity.
#
# Usage:
#   pwsh -NoProfile -File scripts/spec_catalog/spec-next-preflight.ps1
#   pwsh -NoProfile -File scripts/spec_catalog/spec-next-preflight.ps1 -Exclude S0506,S0508
#   pwsh -NoProfile -File scripts/spec_catalog/spec-next-preflight.ps1 -Exclude S0506 S0508
#   pwsh -NoProfile -File scripts/spec_catalog/spec-next-preflight.ps1 -Format table
#   pwsh -NoProfile -File scripts/spec_catalog/spec-next-preflight.ps1 -Claim -Reason "spec-next"
#
# -Exclude carries the in-memory "processed this run" set so a follow-up call
# returns the next candidate in one shot (no manual re-rank needed). CSV,
# repeated values, and space-separated ids are normalized into one set.
#
# The payload's current_release field echoes the release-queue marker for display only: the ranking
# above reads package headings and line order, never that marker (S3273).
#
# The auto-skip verdict of every candidate is computed in-process by Get-SpecAutoSkip (`_auto-skip.ps1`), the
# function preview.ps1 prints its own verdict from, and the selected ticket's payload is built in-process by
# Get-SpecPreview (`_spec-preview.ps1`), the function preview.ps1 prints. Until 2026-11-13 both came from a preview.ps1
# child process per candidate, and the portfolio rank - which asks every repository this question, often many times
# - spent 100-170 s starting them.
#
# -ScanAll (implied by SZA_PQ_PICKER=1, the portfolio dispatcher's picker) does not stop at the selected ticket: every
# ranked candidate gets its verdict, so auto_skipped and malformed name every candidate that would not be offered, and
# the payload says scan_complete = true. A ranked id in neither list is then offerable once the ids above it are
# excluded - the question the dispatcher used to answer with a second picker run. Nothing past the selected ticket is
# claimed or previewed in full; only its verdict is computed.
#
# -MaxScan bounds how many ranked candidates the selection walks before it gives up (0, the default, is no bound). The
# bound of 25 existed because each step cost a child process; a step now costs milliseconds, and a cap only turned "the
# 26th ticket is the first offerable one" into "no candidate". A complete scan still gives every candidate its verdict.
#
# Exit codes: 0 always (no candidate is a valid state, reported as selected=null; under -Claim a
#   claim that neither won nor lost is reported as selected.lease.outcome = 'claim-error').
#   2 - usage error only: a dash-led token that is not a declared option (S4397), or -ClaimAs
#   without -Claim.

[CmdletBinding(PositionalBinding = $false)]
param(
    [string[]]$Exclude = @(),
    [switch]$NoDrift,
    [ValidateSet('json', 'table')]
    [string]$Format = 'json',
    [int]$MaxScan = 0,
    [switch]$ScanAll,
    [switch]$Claim,
    [string]$ClaimAs = '',
    [string]$Reason = 'spec-next-preflight',
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AdditionalExclude = @()
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')

# S4397: ValueFromRemainingArguments keeps the space-separated ids (-Exclude S0506 S0508) working, but
# it also catches every option this script does not declare. A mistyped or too-new one (-Bogus, or
# -Claim/-Reason on a harness that predates them) used to land in the exclude set as if it were an id
# and the pick carried on without the behaviour the caller asked for - the swallowed -Claim of
# 2026-10-19 left the selection/claim race open and reported success. A ticket id never starts with a
# dash, so a dash-led token is an option nobody declared: refuse it before anything is read or claimed.
$unknownOptions = @($AdditionalExclude | Where-Object { "$_" -match '^-' })
if ($unknownOptions.Count -gt 0) {
    Write-Error ("spec-next-preflight: unknown option(s): $($unknownOptions -join ', '). Declared: " +
        '-Exclude, -NoDrift, -Format, -MaxScan, -ScanAll, -Claim, -ClaimAs, -Reason. Nothing was ranked or claimed.') -ErrorAction Continue
    exit 2
}

if (-not [string]::IsNullOrWhiteSpace($ClaimAs)) {
    if (-not $Claim) {
        Write-Error 'spec-next-preflight: -ClaimAs names who the claim is made for and means nothing without -Claim.' -ErrorAction Continue
        exit 2
    }
    # Process-scoped: the lease children inherit it, and it dies with this process.
    Set-SzaEnv 'AGENT_ID' $ClaimAs.Trim()
}

. (Join-Path $PSScriptRoot '_lib.ps1')

# The auto-skip verdict and the preview payload, shared with preview.ps1 (see the header). Both are written to run
# under the strict mode `_lib.ps1` just switched on.
. (Join-Path $PSScriptRoot '_spec-preview.ps1')

# S2695: the idle-run series, so a ticket that has come back unmoved twice in a row is passed over
# instead of being offered again for ever. It belongs here rather than in the skip cache because
# the runner wipes that cache at every start by design, while this walk is re-derived live on
# every ranking.
. (Get-SzaHarnessScript 'batch/_idle-runs.ps1')

# TASK-FLOW 0.24 rule 67: a ticket whose audit left only release-tier work is not offered again on the
# same code tree. The audit is static, so a second one over the same files says nothing new.
. (Get-SzaHarnessScript 'batch/_release-wait.ps1')

$pwshExe = if (Test-Path "$env:ProgramFiles\PowerShell\7\pwsh.exe") {
    "$env:ProgramFiles\PowerShell\7\pwsh.exe"
} else {
    'pwsh'
}
$driftPath = Join-Path $PSScriptRoot 'drift-check.ps1'
$skipCachePath = Join-Path $PSScriptRoot 'skip-cache.ps1'

$eligibleStatuses = @(
    'Draft', 'Approved', 'Tactical', 'In Progress',
    'Implemented', 'Partial', 'Broken', 'BlockByOtherTask'
)
$excludeSet = @{}
$normalizedExcludeIds = New-Object System.Collections.Generic.List[string]
# Split comma-joined elements: native pwsh parses `-Exclude S0506,S0508` into an array, but
# invoking via `pwsh -File ... -Exclude "S0506,S0508"` binds the whole CSV as a single element.
foreach ($e in (@($Exclude) + @($AdditionalExclude))) {
    foreach ($id in ($e -split ',')) { if ($id.Trim()) { $excludeSet[$id.Trim()] = $true } }
}
foreach ($id in $excludeSet.Keys | Sort-Object) {
    $normalizedExcludeIds.Add($id)
}

# 1. Read active catalog + filter to eligible statuses.
# NB: Read-Catalog returns the array via the ,$arr anti-unroll idiom, so it must
# be captured by direct assignment - @(Read-Catalog) would collapse to 1 element.
$all = Read-Catalog
$eligible = @($all | Where-Object { $eligibleStatuses -contains $_.status })

# The catalog the blocker lookups of step 5 read: this same active journal, and the archive only when a blocker is
# not in it - the order select.ps1 -Id resolves in, without a child process per blocker.
$autoSkipCatalog = New-AutoSkipCatalog -Active $all -ArchiveLoader { $archived = Read-JsonlFile -Path (Get-ArchivePath); $archived }
$projectRoot = Get-SzaProjectRoot

# 2. Rank by the owner's release plan first. The catalog knows priority but not intent:
# PLAN/RELEASE_QUEUE.md says which package a ticket ships in and in what order inside it,
# and that decision outranks priority. Priority survives only as the fallback ordering for
# a ticket the queue does not list (and for a queue-less checkout, where the map is empty).
$queueRank = @{}
$queueRel = @{}
$queueSide = @{}
$queueSeq = 0
foreach ($line in (Read-ReleaseQueue)) {
    if ($line.Kind -ne 'ticket') { continue }
    if ($queueRank.ContainsKey($line.Id)) { continue }
    $queueRank[$line.Id] = $queueSeq++
    $queueRel[$line.Id] = [string]$line.Release
    $queueSide[$line.Id] = 'queue'
}
# The ready side (RELEASE_READY.md) holds finished content - an `Implemented` row there still
# needs its audit, but it is not planned work, so it sorts after every numbered package.
foreach ($line in (Read-ReleaseReady)) {
    if ($line.Kind -ne 'ticket') { continue }
    if ($queueSide.ContainsKey($line.Id)) { continue }
    $queueRank[$line.Id] = $queueSeq++
    $queueRel[$line.Id] = [string]$line.Release
    $queueSide[$line.Id] = 'ready'
}
# Buckets past the last real package, so numbered work always precedes them.
$relReadySide = 9000     # finished content awaiting its audit - valuable, but not planned work
$relParked = 9100        # `--` in the queue: drive it only when nothing in a package is eligible
$relOffQueue = 9500      # in neither file: nothing was sorted, fall back to priority
function Get-QueueRelBucket {
    param([Parameter(Mandatory)][string] $Id)
    if (-not $queueRel.ContainsKey($Id)) { return $relOffQueue }
    if ($queueSide[$Id] -eq 'ready') { return $relReadySide }
    $rel = $queueRel[$Id]
    if ($rel -match '^\d+$') { return [int]$rel }
    return $relParked
}
function Get-QueueLineOrder {
    param([Parameter(Mandatory)][string] $Id)
    if ($queueRank.ContainsKey($Id)) { return $queueRank[$Id] }
    return [int]::MaxValue
}
$ranked = @($eligible | Sort-Object `
    @{ Expression = { Get-QueueRelBucket -Id $_.id }; Descending = $false }, `
    @{ Expression = { Get-QueueLineOrder -Id $_.id }; Descending = $false }, `
    @{ Expression = { [int]$_.priority }; Descending = $true }, `
    @{ Expression = { [string]$_.updated }; Descending = $true }, `
    @{ Expression = { [string]$_.id }; Descending = $false })

# 3. Load active persistent skip-cache (read-only consume)
#
# A cache file that is absent, empty or `{}` lists nothing, and skip-cache.ps1 -Action list writes nothing for it
# either, so that answer is taken here without its child process (0.4-0.5 s, paid once per repository per portfolio
# rank; measured 2026-11-13, 18 of 19 registered repositories hold `{}` or no file). Any other content, or a file that
# cannot be read, goes to the script as before - it alone prunes expired entries.
$skipCache = [ordered]@{}
$skipRaw = $null
$skipCacheText = $null
try {
    $skipCacheFile = Get-SzaPath 'skipCache'
    $skipCacheText = if (Test-Path -LiteralPath $skipCacheFile -PathType Leaf) { [string](Get-Content -LiteralPath $skipCacheFile -Raw) } else { '' }
} catch {
    $skipCacheText = $null
}
if ($null -eq $skipCacheText -or $skipCacheText.Trim() -notin @('', '{}')) {
    $skipRaw = & $pwshExe -NoProfile -File $skipCachePath -Action list 2>$null
}
if ($skipRaw -and $skipRaw.Trim() -ne '{}') {
    try {
        $parsed = $skipRaw | ConvertFrom-Json
        foreach ($prop in $parsed.PSObject.Properties) {
            $skipCache[$prop.Name] = $prop.Value
        }
    } catch {
        # Malformed cache is non-fatal for selection; surface as empty.
        $skipCache = [ordered]@{}
    }
}

# 3.5. Load ticket leases held by OTHER live sessions (S1437, read-only consume).
# Our own leases must not exclude us, or a resuming session cannot get back to its own ticket.
# A missing or failing lease store yields an empty set: the picker still works without it.
$leaseSet = @{}
$leasedDetail = @()
$leasePath = (Get-SzaHarnessScript 'locks/ticket-lease.ps1')
# No lease file means `ticket-lease.ps1 -Verb Status -Json` has nothing to sweep and prints `[]`, so that answer is taken
# here without its child process (0.4-0.6 s, once per repository per portfolio rank; measured 2026-11-13, 17 of 19
# registered repositories hold none). The directory is resolved as that script resolves it, its test seam included.
# Lease files present, or a directory that cannot be resolved: the script reads and sweeps them as before.
$leaseFilesPresent = $true
try {
    $leaseRoot = Get-SzaEnv 'TICKET_LEASE_ROOT'
    if ([string]::IsNullOrWhiteSpace($leaseRoot)) { $leaseRoot = Get-SzaProjectRoot }
    $leaseDirOnDisk = Join-Path $leaseRoot (Get-SzaPath 'leasesDir' -Relative)
    $leaseFilesPresent = @(Get-ChildItem -LiteralPath $leaseDirOnDisk -Filter '*.json' -ErrorAction SilentlyContinue).Count -gt 0
} catch {
    $leaseFilesPresent = $true
}
if ($leaseFilesPresent -and (Test-Path -LiteralPath $leasePath)) {
    $leaseRaw = & $pwshExe -NoProfile -File $leasePath -Verb Status -Json 2>$null
    if ($leaseRaw) {
        try {
            foreach ($l in @($leaseRaw | ConvertFrom-Json)) {
                if ($l.mine) { continue }
                $leaseSet[[string]$l.id] = $l
            }
        } catch {
            # Malformed lease output is non-fatal for selection; surface as no leases.
            $leaseSet = @{}
        }
    }
}

# 3.6. S2372: the holder's newest chat line, one per leased session. Read inside a scriptblock with
# its own strict-mode scope: agent-lock.ps1 switches strict mode on for the scope it is loaded into,
# and this ranker's own property reads are not written for it (the preview.ps1 lesson, S1621).
$chatLines = @{}
try {
    $leaseHolders = @($leaseSet.Values | ForEach-Object { [string]$_.sessionId } | Where-Object { $_ } | Select-Object -Unique)
    if ($leaseHolders.Count -gt 0) {
        $chatLines = & {
            param($Holders, $LockLib)
            Set-StrictMode -Off
            . $LockLib
            $out = @{}
            foreach ($sid in $Holders) {
                $m = @(Get-AgentChatMessages -Stream all -AgentId $sid -Last 1)
                if ($m.Count -gt 0) { $out[$sid] = Format-AgentChatLine $m[0] }
            }
            $out
        } $leaseHolders (Get-SzaHarnessScript 'locks/agent-lock.ps1')
    }
} catch {
    # The chat is decoration on the ranking, never an input to it.
    $chatLines = @{}
}

# 4. Drop skip-cached + excluded + leased ids from the ranked list (record what was dropped)
#
# S1864: one cached reason is deliberately NOT honoured here. `blocker-not-verified` is the
# only skip verdict about ANOTHER ticket's status, so it goes stale from work that never
# touches the cached ticket - the blocker ships and its dependent stays hidden for the rest
# of the 7-day TTL. Measured: S1714 sat cached as "Depends on S1704(BlockNeedUserTest)" while
# S1704's code was already in the tree. Caching it bought nothing either way, since step 5
# re-derives the same verdict (Get-SpecAutoSkip) on every run. Every other reason is a judgement
# about the ticket itself (tier-5 epic, owner gate, drift needing review) and still holds.
$skipCachedIds = @()
$skipCacheOverriddenIds = @()
$rankedLive = New-Object System.Collections.Generic.List[object]
foreach ($r in $ranked) {
    if ($skipCache.Contains($r.id)) {
        $cachedReason = [string]$skipCache[$r.id].reason
        if ($cachedReason -like 'blocker-not-verified*' -or $cachedReason -like 'blocker-cross-repo*') {
            $skipCacheOverriddenIds += $r.id
        }
        else {
            $skipCachedIds += $r.id
            continue
        }
    }
    if ($excludeSet.ContainsKey($r.id)) { continue }
    if ($leaseSet.ContainsKey($r.id)) {
        $held = $leaseSet[$r.id]
        $leasedDetail += [PSCustomObject]@{
            id                = [string]$r.id
            sessionId         = [string]$held.sessionId
            host              = [string]$held.host
            reason            = [string]$held.reason
            last_seen_minutes = $held.lastSeenMinutes
            last_chat         = $(if ($chatLines.ContainsKey([string]$held.sessionId)) { $chatLines[[string]$held.sessionId] } else { $null })
        }
        continue
    }
    $rankedLive.Add($r)
}

function Invoke-CandidateClaim {
    <#
        One claim through ticket-lease.ps1, reduced to the three answers the walk branches on:
        won (claimed / already-mine), lost (exit 3, a sibling holds it) and claim-error (anything
        else - the store could not be written, or the lease script is missing).
    #>
    param([Parameter(Mandatory)][string]$Id)
    if (-not (Test-Path -LiteralPath $leasePath)) {
        return [PSCustomObject]@{ outcome = 'claim-error'; exit_code = $null; session_id = $null; handoff_path = $null; held_by = $null; detail = "lease script missing: $leasePath" }
    }
    $raw = @(& $pwshExe -NoProfile -File $leasePath -Verb Claim -Id $Id -Reason $Reason -Json 2>$null)
    $code = $LASTEXITCODE
    $payload = $null
    $jsonLine = @($raw | ForEach-Object { [string]$_ } | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1)
    if ($jsonLine.Count -gt 0) {
        try { $payload = $jsonLine[0] | ConvertFrom-Json } catch { $payload = $null }
    }
    $outcome = if ($code -eq 0) {
        if ($payload -and $payload.outcome) { [string]$payload.outcome } else { 'claimed' }
    } elseif ($code -eq 3) { 'claim-lost' } else { 'claim-error' }
    return [PSCustomObject]@{
        outcome      = $outcome
        exit_code    = $code
        session_id   = $(if ($payload -and $payload.PSObject.Properties.Name -contains 'sessionId') { [string]$payload.sessionId } else { $null })
        handoff_path = $(if ($payload -and $payload.PSObject.Properties.Name -contains 'handoffPath') { [string]$payload.handoffPath } else { $null })
        held_by      = $(if ($payload -and $payload.PSObject.Properties.Name -contains 'heldBy') { [string]$payload.heldBy } else { $null })
        detail       = $(if ($outcome -eq 'claim-error') { "ticket-lease.ps1 -Verb Claim exited $code" } else { $null })
    }
}

function Get-CandidateVerdict {
    <#
        preview.ps1's verdict for one ranked candidate, in-process: @{ malformed; reason; detail; specPath }.
        malformed stands for every way preview.ps1 could not produce a payload - an id outside the grammar, no spec
        file on disk, an empty one, or a throw while judging it - which the walk has always listed as malformed.
    #>
    param([Parameter(Mandatory)] $Candidate)
    try {
        $id = [string]$Candidate.id
        if (-not (Test-SzaTicketId $id)) { return @{ malformed = $true; reason = $null; detail = $null; specPath = $null } }
        $specPath = Join-Path $projectRoot $Candidate.file
        if (-not (Test-Path -LiteralPath $specPath)) { return @{ malformed = $true; reason = $null; detail = $null; specPath = $null } }
        $specText = Read-AutoSkipSpecText -Path $specPath
        if ($null -eq $specText) { return @{ malformed = $true; reason = $null; detail = $null; specPath = $null } }
        $v = Get-SpecAutoSkip -Record $Candidate -SpecText $specText -SelfId $id -Catalog $autoSkipCatalog
        return @{ malformed = $false; reason = $v.AutoSkip; detail = $v.AutoSkipReason; specPath = $specPath }
    }
    catch {
        return @{ malformed = $true; reason = $null; detail = $null; specPath = $null }
    }
}

# 5. Walk down the live ranked list; the first candidate with no auto-skip verdict is selected. Under a complete
# scan (see the header) the walk goes on past it, giving every remaining candidate its verdict and nothing more.
$completeScan = $ScanAll.IsPresent -or ($env:SZA_PQ_PICKER -ceq '1')
$autoSkipped = @()
$malformed = @()
$claimLost = @()
$selected = $null
$scan = 0
foreach ($cand in $rankedLive) {
    $selecting = ($null -eq $selected) -and ($MaxScan -le 0 -or $scan -lt $MaxScan)
    if (-not $selecting -and -not $completeScan) { break }
    $scan++

    # Tested BEFORE the verdict: a held ticket is already decided. The series is read from the run
    # journals, so it costs one cached file walk for the whole loop.
    $idleSeries = Get-IdleRunSeries -Id $cand.id
    if ($idleSeries.Count -ge (Get-IdleRunPolicy).Threshold) {
        $autoSkipped += [PSCustomObject]@{
            id     = $cand.id
            reason = 'idle-hold'
            detail = ("{0} run(s) in a row did not move the status, last outcome '{1}' at {2} - held until the status moves; an explicit id is never held" -f `
                    $idleSeries.Count, $idleSeries.LastOutcome, $idleSeries.LastFinishedAt)
        }
        continue
    }

    # Rule 67. Tested after the idle hold (a ticket in both states keeps the older, plainer reason) and
    # before the verdict, as it always was. Only a ticket whose newest journal row stamped a tree
    # pays for a stamp of the tree now; every other candidate costs one string test. A throw here must not
    # stall the ranking: no answer reads as "not withheld".
    $awaitsRelease = $false
    if (-not [string]::IsNullOrWhiteSpace([string]$idleSeries.LastAwaitsRelease)) {
        try {
            $awaitsRelease = Test-AwaitsRelease -SpecPath ([string]$cand.file) -Status ([string]$cand.status) -RecordedStamp ([string]$idleSeries.LastAwaitsRelease)
        } catch {
            $awaitsRelease = $false
        }
    }
    if ($awaitsRelease) {
        $autoSkipped += [PSCustomObject]@{
            id     = $cand.id
            reason = 'awaits-release'
            detail = 'its last audit left only release-tier work (FAIL 0, WARN 0, RELEASE >= 1) and the code tree is the one stamped when that pass ended - held until the tree changes or the status moves; an explicit id is never held'
        }
        continue
    }

    $verdict = Get-CandidateVerdict -Candidate $cand
    if ($verdict.malformed) { $malformed += $cand.id; continue }
    if ($verdict.reason) {
        $autoSkipped += [PSCustomObject]@{
            id     = $cand.id
            reason = $verdict.reason
            detail = $verdict.detail
        }
        continue
    }
    # Past the selected ticket (or past -MaxScan) on a complete scan: the verdict is all that is asked.
    if (-not $selecting) { continue }

    # The selected ticket's payload, through the JSON round trip it always made out of the preview.ps1 child, so
    # its shape (frontmatter as an object, depends_on as an array) is the one every consumer parses.
    try {
        $pv = Get-SpecPreview -Record $cand -Id ([string]$cand.id) -Root $projectRoot -SpecPath $verdict.specPath -Catalog $autoSkipCatalog |
            ConvertTo-Json -Depth 6 -Compress | ConvertFrom-Json
    } catch {
        $malformed += $cand.id; continue
    }
    if ($pv.auto_skip) {
        # The spec changed between the two reads; the payload's own verdict is the newer one.
        $autoSkipped += [PSCustomObject]@{
            id     = $cand.id
            reason = $pv.auto_skip
            detail = $pv.auto_skip_reason
        }
        continue
    }
    if ($Claim) {
        $lease = Invoke-CandidateClaim -Id ([string]$cand.id)
        if ($lease.outcome -eq 'claim-lost') {
            # The lease read above was a moment old; a sibling claimed in between. Normal, not a fault.
            $claimLost += [PSCustomObject]@{ id = [string]$cand.id; held_by = $lease.held_by }
            continue
        }
        # A claim-error still selects: "the store could not be written" is not evidence the ticket is
        # taken, and stalling every picker behind a transient is worse than the caller's own claim,
        # which still runs. The caller reads selected.lease.outcome to know it holds nothing yet.
        Add-Member -InputObject $pv -NotePropertyName 'lease' -NotePropertyValue $lease -Force
    }
    $selected = $pv
    if (-not $completeScan) { break }
}

# 6. For the selected candidate: drift-check verdict + file/catalog status mismatch
if ($selected) {
    # status mismatch (file frontmatter vs catalog) - skill resolves via update.ps1
    $fileStatus = $null
    if ($selected.frontmatter -and ($selected.frontmatter.PSObject.Properties.Name -contains 'Status')) {
        $fileStatus = $selected.frontmatter.Status
    }
    $mismatch = $null
    if ($fileStatus -and $fileStatus -ne $selected.status) {
        $mismatch = [PSCustomObject]@{ catalog = $selected.status; file = $fileStatus }
    }
    Add-Member -InputObject $selected -NotePropertyName 'status_mismatch' -NotePropertyValue $mismatch -Force

    $drift = $null
    if (-not $NoDrift) {
        $dfRaw = & $pwshExe -NoProfile -File $driftPath -Id $selected.id -Format json 2>$null
        if ($dfRaw) {
            try { $drift = $dfRaw | ConvertFrom-Json } catch { $drift = $null }
        }
    }
    Add-Member -InputObject $selected -NotePropertyName 'drift' -NotePropertyValue $drift -Force

    # S1429: the third proof that landed work is accounted for. A Tier-3 ticket records progress in
    # its tactical INDEX, not in the strategic spec, so a gate that reads only `## Last Audit` and
    # `Implementation State` calls every in-flight tactical ticket unaccounted.
    #
    # S1634: "fresh" is now measured against the working tree instead of against a commit date. The
    # question has not changed - can this plan vouch for the marked code, or was it abandoned before
    # that code was written - but the old answer came from `git log`, and in a repository with one
    # developer committing the whole tree under a timestamp subject, a single routine snapshot dated
    # later than every plan made every in-flight ticket stale at once. The tree answers the same
    # question directly: compare when the plan was last written to when the marked sources were last
    # written. A plan touched no earlier than its marked code is accounting for it; a plan that has
    # not been touched since that code appeared is exactly the abandoned case the rule guards.
    $tacticalIndex = $null
    if ($selected.file) {
        $specRoot = (Get-SzaProjectRoot)
        $indexRel = ($selected.file -replace '\.md$', '') + '/INDEX.md'
        $indexPath = Join-Path $specRoot $indexRel
        if (Test-Path -LiteralPath $indexPath) {
            $indexText = Get-Content -LiteralPath $indexPath -Raw
            $updatedMatch = [regex]::Match($indexText, '(?m)^\*\*Last updated:\*\*\s*(\d{4}-\d{2}-\d{2})')
            $phasesMatch = [regex]::Match($indexText, '(?m)^\*\*Phases:\*\*\s*(\d+)\s*/\s*(\d+)\s*done')
            $lastUpdated = if ($updatedMatch.Success) { $updatedMatch.Groups[1].Value } else { $null }

            # The plan's own last-write time, not the `Last updated:` text: plan-tick.ps1 rewrites
            # this file on every step it ticks, so the file time tracks real plan activity and cannot
            # be left behind by a hand edit that forgot the header.
            $planWrittenAt = (Get-Item -LiteralPath $indexPath).LastWriteTimeUtc

            # The newest write among the sources actually carrying this ticket's inline markers. Only
            # those files matter: an unrelated source edited today says nothing about this plan.
            $markedWrittenAt = $null
            if ($drift -and $drift.code_markers) {
                foreach ($markerFile in @($drift.code_markers | ForEach-Object { $_.file } | Sort-Object -Unique)) {
                    $markerPath = Join-Path $specRoot $markerFile
                    if (Test-Path -LiteralPath $markerPath) {
                        $written = (Get-Item -LiteralPath $markerPath).LastWriteTimeUtc
                        if (-not $markedWrittenAt -or $written -gt $markedWrittenAt) { $markedWrittenAt = $written }
                    }
                }
            }

            # No markers means nothing to vouch for, so a plan that exists is proof enough; the
            # DRIFT verdict that consults this proof cannot even be reached in that case.
            $fresh = -not $markedWrittenAt -or $planWrittenAt -ge $markedWrittenAt

            $tacticalIndex = [PSCustomObject]@{
                path              = $indexRel
                last_updated      = $lastUpdated
                phases_done       = if ($phasesMatch.Success) { [int]$phasesMatch.Groups[1].Value } else { $null }
                phases_total      = if ($phasesMatch.Success) { [int]$phasesMatch.Groups[2].Value } else { $null }
                plan_written_at   = $planWrittenAt.ToString('yyyy-MM-dd HH:mm:ss')
                marked_written_at = if ($markedWrittenAt) { $markedWrittenAt.ToString('yyyy-MM-dd HH:mm:ss') } else { $null }
                fresh             = $fresh
            }
        }
    }
    Add-Member -InputObject $selected -NotePropertyName 'tactical_index' -NotePropertyValue $tacticalIndex -Force
}

# 7. Compose result
$rankedOut = @($rankedLive | ForEach-Object {
    [PSCustomObject]@{
        id       = $_.id
        name     = $_.name
        status   = $_.status
        priority = [int]$_.priority
        updated  = [string]$_.updated
        # release = the package this ticket belongs to ('--' parked, null = in neither file).
        # side    = 'queue' (work left), 'ready' (finished content awaiting audit), null.
        release  = $(if ($queueRel.ContainsKey($_.id)) { $queueRel[$_.id] } else { $null })
        side     = $(if ($queueSide.ContainsKey($_.id)) { $queueSide[$_.id] } else { $null })
        queue_order = $(if ($queueRank.ContainsKey($_.id)) { $queueRank[$_.id] } else { $null })
    }
})

$skipCacheOut = [PSCustomObject]@{}
foreach ($k in $skipCache.Keys) {
    Add-Member -InputObject $skipCacheOut -MemberType NoteProperty -Name $k -Value $skipCache[$k]
}

$result = [PSCustomObject]@{
    total          = $all.Count
    eligible_count = $eligible.Count
    order_source   = ('{0} (release package, then line order); catalog priority is the fallback' -f (Get-SzaPath 'releaseQueue' -Relative))
    current_release = (Get-CurrentRelease)
    ranked         = $rankedOut
    skip_cache     = $skipCacheOut
    skip_cached_ids = @($skipCachedIds)
    # S1864: cached under a stale `blocker-not-verified` and re-derived live instead of dropped.
    # Named in the payload so an operator sees the cache was overridden, not silently bypassed.
    skip_cache_overridden_ids = @($skipCacheOverriddenIds)
    excluded_ids   = @($normalizedExcludeIds)
    leased_ids     = @($leasedDetail)
    auto_skipped   = @($autoSkipped)
    malformed      = @($malformed)
    # -ScanAll / SZA_PQ_PICKER=1: every ranked candidate was judged, not only those above the selected one, so a ranked
    # id absent from auto_skipped, malformed and claim_lost would be offered once the ids above it are excluded.
    # Absent (an older harness) or false: the lists cover only the walk down to the selected ticket.
    scan_complete  = $completeScan
    # -Claim only: candidates a sibling claimed between this run's lease read and its own claim.
    claim_lost     = @($claimLost)
    claimed        = [bool]$Claim
    selected       = $selected
    # S1437: why nothing was selected, when nothing was. 'all-leased' means the queue is BUSY,
    # not finished - siblings hold every candidate and re-running later gets one. Reporting that
    # as plain exhaustion would tell the owner the work is done while three sessions are on it.
    # A candidate lost to a sibling's claim during the walk is held just as surely as one the
    # lease read already saw, so it counts toward the same verdict.
    selected_none_reason = $(
        if ($selected) { $null }
        elseif ($eligible.Count -eq 0) { 'queue-exhausted' }
        elseif ($rankedLive.Count -eq $claimLost.Count -and ($leasedDetail.Count + $claimLost.Count) -gt 0) { 'all-leased' }
        else { 'no-candidate' }
    )
}

if ($Format -eq 'json') {
    $result | ConvertTo-Json -Depth 8 -Compress
} else {
    Write-Host "spec-next preflight" -ForegroundColor Cyan
    Write-Host "  eligible: $($eligible.Count) / total: $($all.Count) | live ranked: $($rankedOut.Count)" -ForegroundColor DarkGray
    Write-Host "  order: $(Get-SzaPath 'releaseQueue' -Relative) (package, then line order) | current release: $(Get-CurrentRelease)" -ForegroundColor DarkGray
    if ($completeScan) {
        Write-Host "  scan: complete - every ranked candidate judged, not only those above the selected one" -ForegroundColor DarkGray
    }
    if ($skipCachedIds.Count -gt 0) {
        Write-Host "  skip-cached out: $($skipCachedIds -join ', ')" -ForegroundColor DarkGray
    }
    if ($skipCacheOverriddenIds.Count -gt 0) {
        Write-Host "  skip-cache overridden (blocker verdict re-derived live): $($skipCacheOverriddenIds -join ', ')" -ForegroundColor DarkGray
    }
    foreach ($l in $leasedDetail) {
        $seen = if ($null -ne $l.last_seen_minutes) { "last seen $($l.last_seen_minutes) min ago" } else { 'last seen unknown' }
        $chatSuffix = if ($l.last_chat) { " - chat: $($l.last_chat.Trim())" } else { '' }
        Write-Host "  [leased] $($l.id) - held by session $($l.sessionId) on $($l.host) ($seen)$chatSuffix" -ForegroundColor DarkCyan
    }
    foreach ($a in $autoSkipped) {
        Write-Host "  [auto-skip] $($a.id) - $($a.reason): $($a.detail)" -ForegroundColor Yellow
    }
    foreach ($c in $claimLost) {
        Write-Host "  [claim-lost] $($c.id) - claimed by session $($c.held_by) while this walk ran" -ForegroundColor DarkCyan
    }
    if ($malformed.Count -gt 0) {
        Write-Host "  malformed (preview failed): $($malformed -join ', ')" -ForegroundColor Red
    }
    if ($selected) {
        $selRel = if ($queueRel.ContainsKey($selected.id)) { $queueRel[$selected.id] } else { 'not in queue' }
        Write-Host "  SELECTED: $($selected.id) (rel $selRel, $($selected.status), pri $($selected.priority), tier $($selected.tier)) - $($selected.name)" -ForegroundColor Green
        if ($selected.status_mismatch) {
            Write-Host "    status mismatch: catalog=$($selected.status_mismatch.catalog) file=$($selected.status_mismatch.file) (catalog authoritative)" -ForegroundColor Yellow
        }
        if ($selected.drift) {
            Write-Host "    drift: $($selected.drift.verdict) (markers=$($selected.drift.markers_count))" -ForegroundColor DarkGray
        }
        if ($Claim -and $selected.lease) {
            $leaseColour = if ($selected.lease.outcome -eq 'claim-error') { 'Red' } else { 'Green' }
            Write-Host "    lease: $($selected.lease.outcome)$(if ($selected.lease.handoff_path) { " - handoff $($selected.lease.handoff_path)" })$(if ($selected.lease.detail) { " - $($selected.lease.detail)" })" -ForegroundColor $leaseColour
        }
    } else {
        switch ($result.selected_none_reason) {
            'all-leased' {
                Write-Host "  SELECTED: none - every eligible ticket is held by a live sibling session." -ForegroundColor Yellow
                Write-Host "            The queue is busy, not finished. Re-run later to pick one up." -ForegroundColor Yellow
            }
            'queue-exhausted' { Write-Host "  SELECTED: none (eligible set exhausted)" -ForegroundColor DarkGray }
            default           { Write-Host "  SELECTED: none (no candidate survived the walk)" -ForegroundColor DarkGray }
        }
    }
}

exit 0
