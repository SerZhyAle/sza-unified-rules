# The qualified blocker of the portfolio (TASK-FLOW rule 52; S0016 R28): `Blocker: <repoKey>:<id>` in a spec names a
# ticket of another registered repository that holds this one back.
#
# Dot-source this file after registry.ps1 and ledger-watch.ps1; it defines functions only, sets no preference and prints
# nothing. It keeps no state: the loop holds the tickets it found blocked and asks again on every turn.
#
#   Get-PqXrepoBlockers -SpecText <text>
#       the distinct `repoKey:id` pairs of every `Blocker:` / `Блокер:` token in qualified form, in file order. A local
#       token (`Blocker: S0012`) is not one and is left to the repository's own picker.
#   Get-PqXrepoBlock -Registry <registry> -RepoKey <key> -TicketId <id>
#       $null when the ticket names no qualified blocker or every one is released; else @{ blocker; state; status; why }
#       for the first that holds it. state is open, unreadable, unknownKey or cycle (EVENTS.md xrepo.resolve); only a
#       released blocker lets the ticket go, so a typo in a key or an unreadable ledger keeps the ticket out and says why.
#
# Released means what the repository's own picker means for a local blocker (`Test-BlockerReleased` of
# spec_catalog/_status-sets.ps1): Archived, or Implemented / Verified / BlockNeedUserTest with its tactical plan finished
# when the plan carries a `**Phases:** N / M done` counter. That file is loaded in a module of its own, because it pulls in
# _profile.ps1, which caches one project root, and the dispatcher serves many repositories.
# The spec file is the only source read; a token in the ledger's statusNote is not, because a ticket whose blocker is in
# another repository keeps its working status (rule 52) and has no Block* note.

$script:PqStatusSets = New-Module -ArgumentList (Join-Path $PSScriptRoot '..\..\spec_catalog\_status-sets.ps1') -ScriptBlock {
    param($StatusSets)
    . $StatusSets
    Export-ModuleMember -Function Test-BlockerReleased
}

$script:PqXrepoTokenPattern = '(?i)(?:Blocker|Блокер)\s*:\s*\**\s*([a-z][a-z0-9-]*):([A-Za-z][A-Za-z0-9_-]*)'

function Get-PqXrepoBlockers([string]$SpecText) {
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $pairs = [Collections.Generic.List[string]]::new()
    if (-not $SpecText) { return [string[]]@() }
    foreach ($m in [regex]::Matches($SpecText, $script:PqXrepoTokenPattern)) {
        $pair = $m.Groups[1].Value.ToLowerInvariant() + ':' + $m.Groups[2].Value
        if ($seen.Add($pair)) { $pairs.Add($pair) }
    }
    return [string[]]@($pairs)
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
    return @{ status = [string]$t.status; file = $file }
}

function Read-PqSpecText([string]$File) {
    if (-not $File -or -not [IO.File]::Exists($File)) { return '' }
    try { return [IO.File]::ReadAllText($File) } catch { return '' }
}

function Get-PqXrepoBlock {
    param([Parameter(Mandatory)]$Registry, [Parameter(Mandatory)][string]$RepoKey, [Parameter(Mandatory)][string]$TicketId)
    $byKey = @{}
    foreach ($r in @($Registry.repos)) { $byKey[[string]$r.key] = $r }
    if (-not $byKey.ContainsKey($RepoKey)) { return $null }
    $snaps = @{}
    $self = Get-PqXrepoTicket $byKey[$RepoKey] $TicketId $snaps
    if ($null -eq $self) { return $null }
    foreach ($pair in @(Get-PqXrepoBlockers (Read-PqSpecText $self.file))) {
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
        $visited = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        for ($hop = 0; $hop -lt 10 -and $at; $hop++) {
            if (-not $visited.Add($at)) { break }
            $next = $null
            foreach ($p in @(Get-PqXrepoBlockers (Read-PqSpecText $file))) {
                if ($p -ceq $start) { return @{ blocker = $pair; state = 'cycle'; status = $b.status; why = "$start and $pair block each other" } }
                $nKey, $nId = $p -split ':', 2
                if ($byKey.ContainsKey($nKey)) {
                    $n = Get-PqXrepoTicket $byKey[$nKey] $nId $snaps
                    if ($null -ne $n) { $next = $p; $file = $n.file; break }
                }
            }
            $at = $next
        }
        $planNote = if ($b.status -cin @('Implemented', 'Verified', 'BlockNeedUserTest')) { ', its plan is not finished' } else { '' }
        return @{ blocker = $pair; state = 'open'; status = $b.status; why = "$pair is $($b.status)$planNote" }
    }
    return $null
}
