# The waiting dispatcher, in full (TASK-FLOW rules 41, 43, 58; S0016 R29-R34): what a poll looks at, when a change
# counts, why nothing is offerable, and when a ticket is offered too often.
#
# Dot-source this file after ledger-watch.ps1 and loop.ps1; it defines functions only, sets no preference and prints
# nothing.
#
#   Get-PqFingerprint -Registry <registry> [-PathsCache <hashtable>]
#       an ordered map part -> stamp of everything a change in which can make a ticket offerable: per enabled
#       repository its ledger, archive, ticket queue, ready and done files (size and write time), the names of the files
#       in its lease folder (a heartbeat rewrites a lease every few minutes and must not look like a change, a claim or a
#       release is a name), the shared stop file; and the registry, PORTFOLIO_QUEUE.md, the folder of agent holds and the
#       names of the resource tokens. A part is named '<repoKey>/<kind>' or '<kind>'.
#   Compare-PqFingerprint -Old <map> -New <map>
#       @{ changed; files = kinds; repos = keys } - the kinds are ledger, archive, queue, ready, done, leases, stop,
#       registry, portfolioQueue, holds, resources (the names of `poll.change`, rule 58).
#   Get-PqWaitReasons -Rank <rank result> -Dropped <n> -Xrepo <n> -Transient <hashtable>
#       the counts for `wait.enter` `why`: why each repository offered nothing, plus the tickets the loop itself holds
#       back (dropped, waiting on a blocker in another repository, a token, or the owner's session).
#   Register-PqLift -Lifts <hashtable> -Key <repo:id> -Now <datetime> [-Max 3] [-WindowMinutes 60]
#       count one lift of a drop; @{ thrash; count } with thrash true from the Max-th lift inside the window (a ticket
#       whose pass moves nothing, is lifted by its own writes and offered again, round and round).

function Get-PqFileStamp([string]$Path) {
    try {
        $fi = [IO.FileInfo]::new($Path)
        if (-not $fi.Exists) { return '-' }
        return "$($fi.Length)/$($fi.LastWriteTimeUtc.Ticks)"
    }
    catch { return '?' }
}

function Get-PqDirNamesStamp([string]$Dir, [string]$Filter = '*') {
    try {
        if (-not $Dir -or -not [IO.Directory]::Exists($Dir)) { return '-' }
        $names = @([IO.Directory]::GetFiles($Dir, $Filter) | ForEach-Object { [IO.Path]::GetFileName($_) })
        [Array]::Sort($names, [StringComparer]::Ordinal)
        return ($names -join ',')
    }
    catch { return '?' }
}

# The spec files of the tickets the loop has dropped (rule 43): the owner's edit of one lifts the drop (its write time), and
# nothing else in a fingerprint would show it. One part per repository, '<repoKey>/spec'.
function Get-PqDropFingerprint($Drops) {
    $byRepo = @{}
    foreach ($dk in @($Drops.Keys)) {
        $d = $Drops[$dk]
        $f = [string](Get-PqValue (Get-PqValue $d 'mark') 'specFile' '')
        if (-not $f) { continue }
        if (-not $byRepo.ContainsKey($d.repo)) { $byRepo[$d.repo] = [Collections.Generic.List[string]]::new() }
        $byRepo[$d.repo].Add("$($d.id)=$(Get-PqFileStamp $f)")
    }
    $out = [ordered]@{}
    foreach ($k in @($byRepo.Keys | Sort-Object)) { $out["$k/spec"] = (@($byRepo[$k] | Sort-Object) -join ';') }
    return $out
}

function Get-PqFingerprint {
    param([Parameter(Mandatory)]$Registry, [hashtable]$PathsCache, $Extra)
    if ($null -eq $PathsCache) { $PathsCache = @{} }
    $parts = [ordered]@{}
    if ($null -ne $Extra) { foreach ($k in @($Extra.Keys)) { $parts[[string]$k] = [string]$Extra[$k] } }
    $parts['registry'] = Get-PqFileStamp (Get-PqPath -Kind registry)
    $parts['portfolioQueue'] = Get-PqFileStamp (Get-PqQueuePath $Registry)
    $parts['holds'] = Get-PqDirNamesStamp (Get-PqPath -Kind holds) '*.json'
    $parts['resources'] = (Get-PqDirNamesStamp (Get-PqResourceTokenDir 'build') '*.json') + '|' + (Get-PqDirNamesStamp (Get-PqResourceTokenDir 'emulator') '*.json')
    foreach ($r in @($Registry.repos)) {
        if ((Get-PqValue $r 'enabled' $false) -ne $true) { continue }
        $k = [string]$r.key
        $rp = $null
        if ($PathsCache.ContainsKey($k)) { $rp = $PathsCache[$k] }
        else {
            try { $rp = Get-PqRepoPaths -RepoPath ([string]$r.path) } catch { $rp = $null }
            $PathsCache[$k] = $rp
        }
        if ($null -eq $rp) { $parts["$k/ledger"] = '?'; continue }
        $parts["$k/ledger"] = Get-PqFileStamp $rp.Ledger
        $parts["$k/archive"] = Get-PqFileStamp $rp.Archive
        $parts["$k/queue"] = Get-PqFileStamp $rp.Queue
        $parts["$k/ready"] = Get-PqFileStamp $rp.Ready
        $parts["$k/done"] = Get-PqFileStamp $rp.Done
        $parts["$k/leases"] = Get-PqDirNamesStamp $rp.LeasesDir '*.json'
        $parts["$k/stop"] = Get-PqFileStamp $rp.StopFile
    }
    return $parts
}

function Compare-PqFingerprint {
    param($Old, $New)
    $files = [Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    $repos = [Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    if ($null -eq $Old) { return @{ changed = $false; files = @(); repos = @() } }
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($n in @($Old.Keys)) { [void]$names.Add([string]$n) }
    foreach ($n in @($New.Keys)) { [void]$names.Add([string]$n) }
    foreach ($n in $names) {
        $a = if ($Old.Contains($n)) { [string]$Old[$n] } else { $null }
        $b = if ($New.Contains($n)) { [string]$New[$n] } else { $null }
        if ($a -ceq $b) { continue }
        $slash = $n.IndexOf('/')
        if ($slash -gt 0) { [void]$repos.Add($n.Substring(0, $slash)); [void]$files.Add($n.Substring($slash + 1)) }
        else { [void]$files.Add($n) }
    }
    return @{ changed = ($files.Count -gt 0); files = [string[]]@($files); repos = [string[]]@($repos) }
}

function Get-PqWaitReasons {
    param($Rank, [int]$Dropped = 0, [int]$Xrepo = 0, $Transient = $null)
    $why = [ordered]@{}
    $add = { param($name, $n) if ($n -gt 0) { if ($why.Contains($name)) { $why[$name] += $n } else { $why[$name] = $n } } }
    if ($null -ne $Rank) {
        foreach ($s in @($Rank.skipped)) {
            $name = switch ([string]$s.why) { 'hold' { 'held' } 'heldByQueue' { 'held' } 'stopped' { 'held' } 'occupied' { 'occupied' } 'disabled' { $null } default { [string]$s.why } }
            if ($name) { & $add $name 1 }
        }
        $auto = $Rank.autoSkipReasons
        if ($null -ne $auto) {
            if ($auto -is [Collections.IDictionary]) { foreach ($k in $auto.Keys) { & $add ([string]$k) ([int]$auto[$k]) } }
            else { foreach ($p in $auto.PSObject.Properties) { & $add ([string]$p.Name) ([int]$p.Value) } }
        }
    }
    & $add 'dropped' $Dropped
    & $add 'xrepo' $Xrepo
    if ($null -ne $Transient) {
        foreach ($t in @($Transient.Values)) { & $add ([string]$t.why) 1 }
    }
    if ($why.Count -eq 0) { $why['none'] = 1 }
    return $why
}

function Register-PqLift {
    param([Parameter(Mandatory)][hashtable]$Lifts, [Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][datetime]$Now, [int]$Max = 3, [int]$WindowMinutes = 60)
    $cut = $Now.AddMinutes(-$WindowMinutes)
    $list = [Collections.Generic.List[datetime]]::new()
    if ($Lifts.ContainsKey($Key)) { foreach ($t in @($Lifts[$Key])) { if ($t -ge $cut) { $list.Add($t) } } }
    $list.Add($Now)
    $Lifts[$Key] = $list
    return @{ thrash = ($list.Count -ge $Max); count = $list.Count }
}
