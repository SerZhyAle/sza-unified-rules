# The qualified blocker of the portfolio (TASK-FLOW rule 52; S0016 R28; S0042): `Blocker: <repoKey>:<id>` in a spec or
# in the ledger's statusNote names a ticket of another registered repository that holds this one back.
#
# Dot-source this file after registry.ps1 and ledger-watch.ps1; it defines functions only, sets no preference and prints
# nothing. It keeps no state: the loop holds the tickets it found blocked and asks again on every turn.
#
#   Get-PqXrepoBlockers -SpecText <text> [-StatusNote <text>]
#       the distinct `repoKey:id` pairs of every `Blocker:` / `Блокер:` token in qualified form, in file order (then
#       statusNote). A local token (`Blocker: S0012`) is not one and is left to the repository's own picker.
#   Get-PqXrepoBlock -Registry <registry> -RepoKey <key> -TicketId <id>
#       $null when the ticket names no qualified blocker or every one is released; else @{ blocker; state; status; why }
#       for the first that holds it. state is open, unreadable, unknownKey or cycle (EVENTS.md xrepo.resolve); only a
#       released blocker lets the ticket go, so a typo in a key or an unreadable ledger keeps the ticket out and says why.
#
# Released means what the repository's own picker means for a local blocker (`Test-BlockerReleased` of
# spec_catalog/_status-sets.ps1): Archived, or Implemented / Verified / BlockNeedUserTest with its tactical plan finished
# when the plan carries a `**Phases:** N / M done` counter. That file is loaded in a module of its own, because it pulls in
# _profile.ps1, which caches one project root, and the dispatcher serves many repositories.
# Both the spec file and the ledger's statusNote are read (S0042): a ticket parked in BlockByOtherTask on a qualified
# cross-repo blocker may record `Blocker: <repoKey>:<id>` in either channel (rule 52).

$script:PqStatusSets = New-Module -ArgumentList (Join-Path $PSScriptRoot '..\..\spec_catalog\_status-sets.ps1') -ScriptBlock {
    param($StatusSets)
    . $StatusSets
    Export-ModuleMember -Function Test-BlockerReleased
}

$script:PqXrepoTokenPattern = '(?i)(?:Blocker|Блокер)\s*:\s*\**\s*([a-z](?:[a-z-][a-z0-9-]*)?):([A-Za-z][A-Za-z0-9_-]*\d[A-Za-z0-9_-]*)'

function Get-PqXrepoBlockers([string]$SpecText, [string]$StatusNote = '') {
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $pairs = [Collections.Generic.List[string]]::new()
    foreach ($src in @($SpecText, $StatusNote)) {
        if (-not $src) { continue }
        foreach ($m in [regex]::Matches($src, $script:PqXrepoTokenPattern)) {
            $pair = $m.Groups[1].Value.ToLowerInvariant() + ':' + $m.Groups[2].Value
            if ($seen.Add($pair)) { $pairs.Add($pair) }
        }
    }
    return [string[]]@($pairs)
}

function Get-PqXrepoStatusNote([string]$Root, [string]$Id) {
    if (-not $Root -or -not $Id) { return '' }
    try {
        $ledger = [string](Get-PqRepoPaths -RepoPath $Root).Ledger
        if (-not $ledger -or -not [IO.File]::Exists($ledger)) { return '' }
        $needle = '"id":"' + $Id + '"'
        foreach ($line in [IO.File]::ReadLines($ledger)) {
            if ($line.IndexOf($needle, [StringComparison]::Ordinal) -lt 0) { continue }
            if ($line.IndexOf('"statusNote"', [StringComparison]::Ordinal) -lt 0) { return '' }
            $row = ConvertFrom-Json -InputObject $line -DateKind String -NoEnumerate
            return [string]$row.statusNote
        }
    } catch { }
    return ''
}

# The ledger record and the absolute spec path of one ticket, or $null.
function Get-PqXrepoTicket($Repo, [string]$Id, [hashtable]$Snapshots) {
    $key = [string]$Repo.key
    if (-not $Snapshots.ContainsKey($key)) {
        try { $Snapshots[$key] = Get-PqLedgerSnapshot -RepoPath ([string]$Repo.path) } catch { $Snapshots[$key] = $null }
    }
    $snap = $Snapshots[$key]
    if ($null -eq $snap -or -not $snap.complete -or -not $snap.tickets.Contains($Id)) { return $null }
    $t = $snap.tickets[$Id]
    $file = if ($t.file) { Resolve-PqRepoPathValue $snap.root ([string]$t.file) } else { $null }
    $note = Get-PqXrepoStatusNote $snap.root $Id
    return @{ status = [string]$t.status; file = $file; statusNote = $note }
}

function Read-PqSpecText([string]$File) {
    if (-not $File -or -not [IO.File]::Exists($File)) { return '' }
    try { return [IO.File]::ReadAllText($File) } catch { return '' }
}

function Get-PqXrepoBlock {
    param([Parameter(Mandatory)]$Registry, [Parameter(Mandatory)][string]$RepoKey, [Parameter(Mandatory)][string]$TicketId,
        # Ledger snapshots shared across calls of ONE rank walk (the head filter asks once per queue row); omitted, each
        # call reads the ledgers afresh, as before.
        [hashtable]$Snapshots = $null)
    $byKey = @{}
    foreach ($r in @($Registry.repos)) { $byKey[[string]$r.key] = $r }
    if (-not $byKey.ContainsKey($RepoKey)) { return $null }
    $snaps = if ($null -ne $Snapshots) { $Snapshots } else { @{} }
    $self = Get-PqXrepoTicket $byKey[$RepoKey] $TicketId $snaps
    if ($null -eq $self) { return $null }
    foreach ($pair in @(Get-PqXrepoBlockers (Read-PqSpecText $self.file) $self.statusNote)) {
        $bKey, $bId = $pair -split ':', 2
        if ($bKey -ceq $RepoKey) { continue }
        if (-not $byKey.ContainsKey($bKey)) { return @{ blocker = $pair; state = 'unknownKey'; status = $null; why = "no registered repository '$bKey'" } }
        $b = Get-PqXrepoTicket $byKey[$bKey] $bId $snaps
        if ($null -eq $b) { return @{ blocker = $pair; state = 'unreadable'; status = $null; why = "$pair is not in its ledger or archive, or the ledger cannot be read" } }
        $released = & $script:PqStatusSets { param($s, $i, $f) Test-BlockerReleased -Status $s -Id $i -File $f } $b.status $bId $b.file
        if ($released) { continue }
        # A cycle never releases either way; it is named so the owner sees why. Followed through qualified tokens only,
        # at most ten hops.
        $start = "$RepoKey`:$TicketId"
        $at = $pair
        $file = $b.file
        $note = $b.statusNote
        $visited = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        for ($hop = 0; $hop -lt 10 -and $at; $hop++) {
            if (-not $visited.Add($at)) { break }
            $next = $null
            foreach ($p in @(Get-PqXrepoBlockers (Read-PqSpecText $file) $note)) {
                if ($p -ceq $start) { return @{ blocker = $pair; state = 'cycle'; status = $b.status; why = "$start and $pair block each other" } }
                $nKey, $nId = $p -split ':', 2
                if ($byKey.ContainsKey($nKey)) {
                    $n = Get-PqXrepoTicket $byKey[$nKey] $nId $snaps
                    if ($null -ne $n) { $next = $p; $file = $n.file; $note = $n.statusNote; break }
                }
            }
            $at = $next
        }
        $planNote = if ($b.status -cin @('Implemented', 'Verified', 'BlockNeedUserTest')) { ', its plan is not finished' } else { '' }
        return @{ blocker = $pair; state = 'open'; status = $b.status; why = "$pair is $($b.status)$planNote" }
    }
    return $null
}

# Read-only preview of the dispatcher's blocker check. Re-rank with each blocked ticket excluded so the next
# eligible ticket can occupy its place, including tickets that appear only in the multi-slot plan.
function Get-PqXrepoFilteredRank {
    param([Parameter(Mandatory)]$Registry, [Parameter(Mandatory)][scriptblock]$Ranker)
    $blocked = [ordered]@{}
    while ($true) {
        $rank = & $Ranker ([string[]]@($blocked.Keys))
        $added = $false
        foreach ($candidate in @($rank.candidates) + @($rank.plan)) {
            $key = "$($candidate.repo):$($candidate.id)"
            if ($blocked.Contains($key)) { continue }
            $reason = Get-PqXrepoBlock -Registry $Registry -RepoKey ([string]$candidate.repo) -TicketId ([string]$candidate.id)
            if ($null -ne $reason) { $blocked[$key] = $reason; $added = $true }
        }
        if (-not $added) { break }
    }
    $rank.excluded.xrepo = $blocked.Count
    $extra = @($blocked.Keys | ForEach-Object {
        $key = $_
        $repo, $id = $key -split ':', 2
        [ordered]@{ repo = $repo; why = "xrepo $id - $($blocked[$key].why)" }
    })
    $rank.skipped = @($rank.skipped) + $extra
    return $rank
}
