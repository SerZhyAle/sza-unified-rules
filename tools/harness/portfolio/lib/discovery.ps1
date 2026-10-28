# Joining (TASK-FLOW rule 49; S0016 R35-R38): a stamped directory one level under a discovery root that is not registered
# joins the portfolio by itself.
#
# Dot-source this file after registry.ps1, picker.ps1 and ledger-watch.ps1; it defines functions only and sets no
# preference. Only Invoke-PqDiscovery prints, one line per repository, once per worker process.
#
#   Get-PqDiscoveryRoots -Registry <registry>
#       discoveryRoots when the registry has it, else the distinct parent directories of the registered paths.
#   Get-PqGitCommonDir -Path <dir>
#       the full path of the git common directory (a worktree's main .git included), or $null.
#   Find-PqDaughters -Registry <registry>
#       the stamped directories under the roots that are not registered, minus the worktrees of registered ones.
#   Test-PqRepoReady -Path <dir> [-HarnessRoot <dir>]
#       @{ ready; checks = [ordered]@{ stamp; profile; ledger; launcher }; why }: the stamp reads, the profile exists,
#       spec_catalog/validate.ps1 exits 0 and the pass runner's -DryRun exits 0 against the repository.
#   Invoke-PqDiscovery -Registry <registry> -Seen <hashtable> [-HarnessRoot] [-Log] [-Run] [-Worker]
#       registers every ready daughter, enabled when autoEnable is on and the registry names a permissionMode, and
#       announces it once. A daughter that is not ready is announced once and checked again on later scans; nothing is
#       written into it - day 0 is the owner's `task-flow-init`, which ends in `pq register`.
#
# Deliberately not here (the contract's rule 49 allows more): scaffolding day 0 into a repository that is not ready.
# Writing files into a repository nobody asked about is the one step of joining that cannot be undone by editing the
# registry, so the lean version reports and waits.

function Get-PqDiscoveryRoots($Registry) {
    if (Test-PqHasKey $Registry 'discoveryRoots') { return [string[]]@(@($Registry.discoveryRoots) | ForEach-Object { [string]$_ }) }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $roots = [Collections.Generic.List[string]]::new()
    foreach ($r in @($Registry.repos)) {
        $p = [string](Get-PqValue $r 'path' '')
        if (-not $p) { continue }
        $parent = Split-Path -Parent (ConvertTo-PqFullPath $p)
        if ($parent -and $seen.Add($parent)) { $roots.Add($parent) }
    }
    return [string[]]@($roots)
}

function Get-PqGitCommonDir([string]$Path) {
    $dotGit = Join-Path $Path '.git'
    try {
        if ([IO.Directory]::Exists($dotGit)) { return [IO.Path]::GetFullPath($dotGit).TrimEnd('\') }
        if (-not [IO.File]::Exists($dotGit)) { return $null }
        $line = ([IO.File]::ReadAllText($dotGit)).Trim()
        if ($line -notmatch '^gitdir:\s*(.+)$') { return $null }
        $gitDir = $Matches[1].Trim()
        if (-not [IO.Path]::IsPathRooted($gitDir)) { $gitDir = Join-Path $Path $gitDir }
        $commonFile = Join-Path $gitDir 'commondir'
        if ([IO.File]::Exists($commonFile)) {
            $common = ([IO.File]::ReadAllText($commonFile)).Trim()
            if (-not [IO.Path]::IsPathRooted($common)) { $common = Join-Path $gitDir $common }
            return [IO.Path]::GetFullPath($common).TrimEnd('\')
        }
        return [IO.Path]::GetFullPath($gitDir).TrimEnd('\')
    }
    catch { return $null }
}

function Find-PqDaughters($Registry) {
    $known = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $commons = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($r in @($Registry.repos)) {
        $p = [string](Get-PqValue $r 'path' '')
        if (-not $p) { continue }
        $null = $known.Add((ConvertTo-PqPathKey (ConvertTo-PqFullPath $p)))
        $c = Get-PqGitCommonDir $p
        if ($c) { $null = $commons.Add($c) }
    }
    $found = [Collections.Generic.List[string]]::new()
    foreach ($root in @(Get-PqDiscoveryRoots $Registry)) {
        if (-not [IO.Directory]::Exists($root)) { continue }
        try { $dirs = [IO.Directory]::GetDirectories($root) } catch { continue }
        foreach ($d in $dirs) {
            if (-not [IO.File]::Exists((Join-Path $d '.sza-canon.json'))) { continue }
            $full = ConvertTo-PqFullPath $d
            if ($known.Contains((ConvertTo-PqPathKey $full))) { continue }
            $c = Get-PqGitCommonDir $full
            if ($c -and $commons.Contains($c)) { continue }
            $found.Add($full)
        }
    }
    return [string[]]@($found)
}

function Test-PqRepoReady {
    param([Parameter(Mandatory)][string]$Path, [string]$HarnessRoot)
    $HarnessRoot = Get-PqHarnessRoot $HarnessRoot
    $checks = [ordered]@{ stamp = $false; profile = $false; ledger = $false; launcher = $false }
    $no = { param($why) @{ ready = $false; checks = $checks; why = $why } }
    try { $stamp = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $Path '.sza-canon.json'))) } catch { $stamp = $null }
    if (-not (Test-PqObjectValue $stamp)) { return (& $no 'the canon stamp does not read') }
    $checks.stamp = $true
    if (-not [IO.File]::Exists((Join-Path $Path '.sza-profile.json'))) { return (& $no 'no .sza-profile.json (day 0 of task-flow-init not done)') }
    $checks.profile = $true
    $v = Invoke-PqRepoChild -RepoPath $Path -Script (Join-Path $HarnessRoot 'spec_catalog\validate.ps1') -Arguments @() -TimeoutSeconds 120
    if ($v.timedOut -or $v.code -ne 0) { return (& $no 'the ticket ledger does not validate (spec_catalog/validate.ps1)') }
    $checks.ledger = $true
    $d = Invoke-PqRepoChild -RepoPath $Path -Script (Join-Path $HarnessRoot 'batch\run-spec-queue.ps1') -Arguments @('-RepoRoot', $Path, '-DryRun') -TimeoutSeconds 180
    if ($d.timedOut -or $d.code -ne 0) { return (& $no "the runner's dry run fails (exit $($d.code))") }
    $checks.launcher = $true
    return @{ ready = $true; checks = $checks; why = $null }
}

function Invoke-PqDiscovery {
    param([Parameter(Mandatory)]$Registry, [Parameter(Mandatory)][hashtable]$Seen, [string]$HarnessRoot, $Log, [string]$Run, $Worker)
    $joined = 0
    foreach ($path in @(Find-PqDaughters $Registry)) {
        $pk = ConvertTo-PqPathKey $path
        $first = -not $Seen.ContainsKey($pk)
        if ($first) {
            $role = 'product'
            $stampVersion = $null
            try {
                $stamp = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText((Join-Path $path '.sza-canon.json')))
                $role = [string](Get-PqValue $stamp 'role' 'product')
                $stampVersion = Get-PqValue $stamp 'schemaVersion'
            }
            catch { }
            $null = Write-PqEvent -Log $Log -Ev 'repo.discovered' -Run $Run -Worker $Worker -D ([ordered]@{ root = (Split-Path -Parent $path); role = $role; stampVersion = $stampVersion; path = $path })
        }
        $ready = Test-PqRepoReady -Path $path -HarnessRoot $HarnessRoot
        if (-not $ready.ready) {
            if ($first -or $Seen[$pk] -cne $ready.why) {
                $null = Write-PqEvent -Log $Log -Ev 'repo.notready' -Run $Run -Worker $Worker -D ([ordered]@{ checks = $ready.checks; why = $ready.why; path = $path })
                Write-Host "found $path (canon stamp) - not joined: $($ready.why); run task-flow-init there, or pq register -Path"
            }
            $Seen[$pk] = $ready.why
            continue
        }
        $Seen[$pk] = 'ready'
        $permission = Get-PqValue $Registry 'permissionMode'
        $enable = ((Get-PqValue $Registry 'autoEnable' $true) -eq $true) -and [bool]$permission
        $add = Add-PqRepo -Path $path -Enable:$enable -By discovery -Log
        if (-not $add.ok) {
            Write-Host "found $path (canon stamp, ready) - not registered: $($add.message)"
            continue
        }
        if ($add.status -cne 'registered') { continue }
        $joined++
        $null = Write-PqEvent -Log $Log -Ev 'repo.ready' -Run $Run -Repo $add.key -Worker $Worker -D ([ordered]@{ checks = $ready.checks })
        $open = 0
        try {
            $snap = Get-PqLedgerSnapshot -RepoPath $path
            foreach ($t in $snap.tickets.Values) { if ($t.status -cnotin @('Verified', 'Archived')) { $open++ } }
        }
        catch { }
        if ($enable) {
            $null = Write-PqEvent -Log $Log -Ev 'repo.enabled' -Run $Run -Repo $add.key -Worker $Worker -D ([ordered]@{ by = 'autoEnable'; open = $open })
            Write-Host "new repository $($add.key) ($path) joined the portfolio and is enabled: $open open tickets, permission $permission"
        }
        else {
            $why = if (-not $permission) { 'the registry names no top-level permissionMode' } else { 'autoEnable is off' }
            Write-Host "new repository $($add.key) ($path) registered, not enabled ($why): $open open tickets"
        }
    }
    return $joined
}
