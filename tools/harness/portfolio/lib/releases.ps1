# pq releases - the release ledgers of every registered repository, read-only (RELEASE-LEDGER 0.1, canon S0092).
#
# Get-PqReleases reads each registered repository's ledger folder (its own .sza-profile.json paths.releasesDir, else the
# shipped default) through the ledger library of tools/harness/releases, in the project order (registry rank). It
# writes nothing, calls no channel and starts no probe: what it shows is what the repositories recorded. A repository
# without a ledger folder is listed with hasLedger false; a ledger that cannot be read is listed with its error, and the
# others are still read.

. (Join-Path $PSScriptRoot '..\..\releases\_lib.ps1')

function Get-PqReleases($Registry) {
    $order = @(Get-PqRepoOrder $Registry)
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($o in $order) {
        $repo = @($Registry.repos) | Where-Object { [string](Get-PqValue $_ 'key') -ceq $o.key } | Select-Object -First 1
        if ($null -eq $repo) { continue }
        $path = [string](Get-PqValue $repo 'path')
        $row = [ordered]@{
            key = $o.key; rank = $o.rank; path = $path; dir = $null; hasLedger = $false; error = $null
            builds = @(); lastBuild = $null; channels = @(); unpublished = @(); events = 0; warnings = @()
        }
        try {
            if (-not [IO.Directory]::Exists($path)) { throw "the repository path does not exist" }
            $dir = Resolve-RlDirForRepo $path
            $row.dir = ConvertTo-RlRepoPath -RepoRoot $path -Path $dir
            if ([IO.Directory]::Exists($dir)) {
                $snap = Get-RlSnapshot $dir
                $row.hasLedger = $true
                $row.builds = [object[]]$snap.builds
                $row.lastBuild = @($snap.builds | Sort-Object -Property @{ Expression = { $t = ConvertTo-RlInstant ([string](Get-RlProp $_ 'builtAt')); if ($t) { $t.UtcTicks } else { 0 } } } -Descending) | Select-Object -First 1
                $row.channels = [object[]]@($snap.channels | ForEach-Object {
                        [pscustomobject]@{ key = $_.key; channel = $_.channel; kind = $_.kind; package = $_.package; title = $_.title; status = $_.status; live = $_.live; inFlight = [object[]]$_.inFlight; events = $_.events }
                    })
                $row.unpublished = [object[]]$snap.unpublished
                $row.events = $snap.events
                $row.warnings = [object[]]$snap.warnings
            }
        } catch {
            $row.error = $_.Exception.Message
        }
        $rows.Add([pscustomobject]$row)
    }
    return [pscustomobject]@{ generatedAt = (Get-RlNow); repos = [object[]]$rows.ToArray() }
}

function Get-PqClosedUnbuilt {
    # Closed without a build, per registered repository (S0135, TASK-FLOW 0.36), counted and never asked of a pass.
    # -Releases: Get-PqReleases' result. -Tickets and -Skipped: rows and skipped of Get-PqInboxRows ("<key> - <why>").
    param($Releases, $Tickets, $Skipped)
    $out = [ordered]@{}
    foreach ($x in @($Releases.repos)) {
        $key = [string]$x.key
        $entry = [ordered]@{ available = $false; why = ''; lastBuiltAt = ''; implemented = $null; sinceBuild = $null }
        $out[$key] = $entry
        if ($x.error) { $entry.why = "release ledger not read: $($x.error)"; continue }
        if (-not $x.hasLedger) { $entry.why = 'no release ledger'; continue }
        if (@(@($Skipped) | Where-Object { ([string]$_).StartsWith("$key - ", [StringComparison]::Ordinal) }).Count -gt 0) { $entry.why = 'ticket ledger not read'; continue }
        $mine = [object[]]@(@($Tickets) | Where-Object { $null -ne $_ -and [string]$_.repo -ceq $key })
        $f = Get-RlClosedSinceBuild -Builds ([object[]]@($x.builds)) -Tickets $mine
        $entry.implemented = $f.atStatus
        if (-not $f.lastBuiltAt) { $entry.why = 'no build recorded'; continue }
        $entry.available = $true
        $entry.lastBuiltAt = $f.lastBuiltAt
        $entry.sinceBuild = $f.sinceBuild
    }
    return $out
}

function Format-PqReleaseChannel($C) {
    $parts = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $C.live) { $parts.Add("live $($C.live.version) ($(Format-RlDay $C.live.at))") }
    foreach ($f in @($C.inFlight)) { $parts.Add("$($f.state) $($f.version) ($(Format-RlDay $f.at))") }
    if ($parts.Count -eq 0) { $parts.Add($(if ($C.status -ne 'none') { $C.status } else { 'nothing recorded' })) }
    return ($parts -join '; ')
}
