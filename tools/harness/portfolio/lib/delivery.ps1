#requires -Version 7.0
# The build-and-deliver half of the phone-filed workflow (S0048): resolve a project's build command the way
# store-publish resolves its paths (probe the repo, never a per-project list in the canon), run the build under
# the resources/build token of rule 62 so it never races a PQ pass, stamp the version the PACKAGE-VERSIONING
# contract of the project names, and copy the artifacts into the phone-reachable delivery folder with .sha256
# sidecars, a LATEST pointer and one build.delivered event.
#
# Dot-source this file; it defines functions only, sets no preference and prints nothing. It needs paths.ps1
# (Get-PqRoot, Get-PqPath, Assert-PqSegment), loop.ps1 (Invoke-PqStateLock, Read-PqState, Get-PqValue lives in
# registry.ps1), registry.ps1 (Read-PqRegistry), events.ps1 (Read-PqDay) and resources.ps1
# (Request-PqResources/Remove-PqResources/Get-PqResourceHeld) already dot-sourced.
#
# The delivery layout (one page: portfolio README section "Remote delivery"):
#
#     <root>\<key>\<version>\<artifact>.<ext>      the artifact
#     <root>\<key>\<version>\<artifact>.sha256     "<hash>  <name>", ascii, the GitHub sidecar shape
#     <root>\<key>\LATEST                          names the newest delivered version; the phone/WEB side reads it
#
# <root> is -DeliveryRoot, else SZA_DELIVERY_ROOT, else C:\GD\tc\SZA\_APP (the synced Drive folder that already
# holds the owner's installables). The sync, not this code, is the transport; nothing else is installed here.
#
#   Get-PqDeliveryRoot [-Override]            the root above (never created by this function).
#   Read-PqProjectStamp / Read-PqProjectProfile -RepoPath
#                                             .sza-canon.json / .sza-profile.json as a hashtable, $null when
#                                             absent or unparsable (a probe, never a requirement).
#   Resolve-PqDeliveryRepo -Project            the registry record of a project key (exact, case-sensitive),
#                                             [pscustomobject] { key, path, record }; $null when unknown or
#                                             the registry does not read.
#   Resolve-PqBuildCommand -RepoPath [-BuildCommand] [-Profile]
#                                             -> @{ file; args (string[]); source } or $null. In order:
#                                             -BuildCommand, the profile's optional delivery.buildCommand
#                                             (a command line relative to the repo, the repo's own record),
#                                             the root build.ps1. release.ps1 and a STORE_PUBLISHING.md /
#                                             DEV/RELEASE.md runbook are probed and REPORTED by the store
#                                             staging plan, never auto-invoked: a build tool must not trip a
#                                             repo's release path on its own.
#   Get-PqRepoTagVersion -RepoPath -TagRegex   the newest tag matching versionShape.tagRegex, with a leading
#                                             v stripped (the PACKAGE-VERSIONING stamp), $null without.
#   Get-PqArtifactStampVersion -Path           a version stamped into a PE artifact (FileVersion/ProductVersion),
#                                             $null when it carries no real stamp (the SDK default 1.0.0.0 is
#                                             not a stamp - a version is read, never guessed).
#   Resolve-PqDeliveryVersion -RepoPath -Artifacts [-Override] [-Stamp] [-Profile]
#                                             -> @{ version; source } or $null. In order: -Override, the
#                                             profile's optional delivery.versionCommand (its last stdout
#                                             line), the artifact's own stamp, the tag. Refused, never guessed.
#   Find-PqNewArtifacts -RepoPath -SinceUtc [-Profile]
#                                             the files the build just wrote: extensions exe apk msix aab msi
#                                             zip appx appxbundle (or the profile's delivery.artifactPatterns
#                                             globs, relative to the repo), written at/after -SinceUtc,
#                                             .git/obj/node_modules/packages/.vs/TestResults walked around.
#   Request-PqBuildToken -Registry -RepoKey [-TicketId] [-WaitSeconds]
#                                             one build token through Request-PqResources, waited for: a
#                                             live token of the SAME repo held by another process, or a full
#                                             cap, is waited out (poll 0.3 s) until -WaitSeconds (900) runs.
#                                             -> @{ ok; waited; why }. The ticket id is the -Ticket id when
#                                             given, else 'build-deliver' (so two concurrent invocations for
#                                             one project serialize on the same token file).
#   Copy-PqDeliveryArtifacts -Artifacts -Root -Key -Version
#                                             copies + sidecars -> @{ dir; files; hashes }; then
#   Set-PqDeliveryLatest -Root -Key -Version / Get-PqDeliveryLatest -Root -Key
#                                             the LATEST pointer, one line, the version (utf8 no BOM).
#   New-PqDeliveryEvent -Log -Record          one build.delivered event (EVENTS.md 3.9, S0048, additive):
#                                             d = { project, version, artifacts [names], sha256 [hex], at,
#                                             ticket* }.
#   Get-PqLastDeliveries                      what pq status prints: the newest build.delivered per project,
#                                             as @{ project; version; at } in event order.
#   Set-PqTicketDeliveryNote -RepoPath -TicketId -Note
#                                             the delivery as a note on the ticket's ledger row through the
#                                             project's own tooling (scripts/spec_catalog/update.ps1 in the
#                                             repo, else the canon's) - the harness never writes a ledger
#                                             directly. -> @{ ok; tool; error* }. -StatusNote only: the row's
#                                             status is preserved (update.ps1 contract).
#
# ---- the Microsoft Store staging leg (S0048 done criterion 4; skills/store-publish is the agent-side law) ----
#
#   Get-PqStoreFrozenPublisher                  the two account-wide constants the skill freezes (Publisher,
#   Get-PqStoreFrozenPublisherDisplayName       PublisherDisplayName); IdentityName is per product and read
#                                             from the repo every time.
#   Get-PqStoreIdentity -RepoPath              the reserved identity out of STORE_PUBLISHING.md (the
#                                             `Package/Identity/Name` / `.. /Publisher` /
#                                             `Package/Properties/PublisherDisplayName` rows), with the frozen
#                                             anchors asserted. -> @{ identityName*; publisher*;
#                                             publisherDisplayName*; publisherAssert*; file* }.
#   Find-PqMsixBuildScript -RepoPath           msix/build-msix.ps1 or publishing/msix/build-msix.ps1, $null.
#   Find-PqListingSources -RepoPath            the listing copies the skill names, the ones that exist.
#   Get-PqStoreStagePlan -RepoPath [-Profile]  the discover-never-assume plan: what the repo itself can
#                                             build, the identity the anchors demand, the WACK and listing
#                                             steps, and the terminal manual Partner Center step - THE
#                                             [PUBLIC] one-way step. No code path here ever performs it.
#   Invoke-PqStoreStage -RepoPath -OutDir [-Version] [-WhatIf] [-IdentityName] [-IdentityOverride]
#                                             stages: MSIX build (the repo's own script, the identity values
#                                             passed only where that script's own parameters accept them, a
#                                             switch never guessed), the packed <Identity> read back from the
#                                             package and asserted against the frozen anchors, a WACK verdict
#                                             parsed from a staged report when one is there (the kit run
#                                             itself is elevated and manual), the listing export-merge step
#                                             (a fresh Partner Center export is interactive by nature) and
#                                             the report. -> the record; the report is also written to
#                                             <OutDir>\STAGE-REPORT.md.

$script:PqDeliveryDefaultRoot = 'C:\GD\tc\SZA\_APP'
$script:PqArtifactExtensions = [string[]]@('.exe', '.apk', '.msix', '.aab', '.msi', '.zip', '.appx', '.appxbundle')
$script:PqArtifactSkipDirs = [string[]]@('.git', '.vs', 'node_modules', 'packages', 'obj', 'TestResults')
$script:PqStoreStageProducer = 'nem'

# The two values that are account-wide constants everywhere (skills/store-publish/SKILL.md); the rest are per product.
$script:PqStoreFrozenPublisher = 'CN=F98ACEDB-1E22-4C39-AF63-F9FCFE807DCD'
$script:PqStoreFrozenPublisherDisplayName = 'SZA'

function Read-PqDeliveryJson([string]$Path) {
    if (-not [IO.File]::Exists($Path)) { return $null }
    try { return (ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)) -AsHashtable -DateKind String) }
    catch { return $null }
}

function Read-PqProjectStamp {
    param([Parameter(Mandatory)][string]$RepoPath)
    return (Read-PqDeliveryJson (Join-Path $RepoPath '.sza-canon.json'))
}

function Read-PqProjectProfile {
    param([Parameter(Mandatory)][string]$RepoPath)
    return (Read-PqDeliveryJson (Join-Path $RepoPath '.sza-profile.json'))
}

function Get-PqDeliveryRoot {
    param([string]$Override = '')
    $v = $Override
    if ([string]::IsNullOrWhiteSpace($v)) { $v = [Environment]::GetEnvironmentVariable('SZA_DELIVERY_ROOT') }
    if ([string]::IsNullOrWhiteSpace($v)) { $v = $script:PqDeliveryDefaultRoot }
    return (ConvertTo-PqFullPath $v)
}

function Resolve-PqDeliveryRepo {
    param([Parameter(Mandatory)][string]$Project)
    $registry = $null
    try {
        $read = Read-PqRegistry -Path (Get-PqPath -Kind registry)
        if ($read.ok) { $registry = $read.registry }
    }
    catch { return $null }
    if ($null -eq $registry) { return $null }
    foreach ($rec in @($registry.repos)) {
        if ([string]$rec.key -ceq $Project) {
            $path = [string]$rec.path
            if (-not [IO.Directory]::Exists($path)) { return $null }
            return [pscustomobject]@{ key = [string]$rec.key; path = (ConvertTo-PqFullPath $path); record = $rec }
        }
    }
    return $null
}

# A command line -> the executable file, its args, resolved against the repo. A quoted first token is honoured;
# a leading token that is not an existing file after resolution is kept as the command (a `dotnet build`
# spelling stays one command line, never a probe result of this resolver).
function Split-PqCommandLine([string]$CommandLine) {
    $tokens = [regex]::Matches($CommandLine, '"([^"]*)"|(\S+)') | ForEach-Object {
        if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value }
    }
    return [string[]]@($tokens)
}

function Resolve-PqBuildCommand {
    param(
        [string]$RepoPath = '',
        [string]$BuildCommand = '',
        $Profile = $null
    )
    $fromLine = {
        param([string]$Line, [string]$Source)
        $tokens = @(Split-PqCommandLine $Line)
        if (@($tokens).Count -eq 0) { return $null }
        $file = [string]$tokens[0]
        if ($RepoPath -and -not [IO.Path]::IsPathFullyQualified($file)) {
            $joined = Join-Path $RepoPath $file
            if ([IO.File]::Exists($joined)) { $file = (ConvertTo-PqFullPath $joined) }
        }
        return @{ file = $file; args = [string[]]@($tokens | Select-Object -Skip 1); source = $Source }
    }
    if (-not [string]::IsNullOrWhiteSpace($BuildCommand)) { return (& $fromLine $BuildCommand 'override') }
    if ($null -ne $Profile) {
        $delivery = Get-PqValue $Profile 'delivery'
        $line = [string](Get-PqValue $delivery 'buildCommand' '')
        if (-not [string]::IsNullOrWhiteSpace($line)) { return (& $fromLine $line 'profile') }
    }
    if ($RepoPath) {
        $root = [IO.Path]::GetFullPath($RepoPath)
        foreach ($name in @('build.ps1')) {
            $candidate = Join-Path $root $name
            if ([IO.File]::Exists($candidate)) {
                return @{ file = (ConvertTo-PqFullPath $candidate); args = [string[]]@(); source = "root $name" }
            }
        }
    }
    return $null
}

function Get-PqRepoTagVersion {
    param([Parameter(Mandatory)][string]$RepoPath, [AllowEmptyString()][string]$TagRegex)
    if ([string]::IsNullOrWhiteSpace($TagRegex) -or -not [IO.Directory]::Exists($RepoPath)) { return $null }
    $tags = [string[]]@()
    try {
        # The version sort keeps numeric system parts ordered; a shaped stamp is numeric by construction.
        $out = & git -C $RepoPath tag -l --sort=-version:refname
        if ($LASTEXITCODE -eq 0) { $tags = @($out | Where-Object { $_ }) }
    }
    catch { return $null }
    foreach ($tag in @($tags)) {
        $m = [regex]::Match([string]$tag, $TagRegex)
        if (-not $m.Success) { continue }
        $text = [string]$tag
        if ($text -cmatch '^v(.+)$') { $text = $Matches[1] }
        return $text
    }
    return $null
}

# The stamp a build put into the artifact itself. The SDK defaults are not stamps: a version is read, never guessed.
function Get-PqArtifactStampVersion {
    param([Parameter(Mandatory)][string]$Path)
    if (-not [IO.File]::Exists($Path)) { return $null }
    $shape = '^\d+(?:\.\d+){1,3}$'
    $degenerate = @('0.0', '0.0.0', '0.0.0.0', '1.0', '1.0.0', '1.0.0.0')
    try { $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($Path) } catch { return $null }
    if ($null -eq $info) { return $null }
    foreach ($raw in @($info.ProductVersion, $info.FileVersion)) {
        $v = ([string]$raw).Trim()
        $sp = $v.IndexOfAny([char[]]@(' ', '+', '-'))
        if ($sp -gt 0) { $v = $v.Substring(0, $sp) }
        if ($v -cmatch $shape -and $degenerate -ccontains $v) { return $null }
        if ($v -cmatch $shape) { return $v }
    }
    return $null
}

function Resolve-PqDeliveryVersion {
    param(
        [string]$RepoPath = '',
        [Parameter(Mandatory)]$Artifacts,
        [string]$Override = '',
        $Stamp = $null,
        $Profile = $null
    )
    if (-not [string]::IsNullOrWhiteSpace($Override)) { return @{ version = $Override; source = 'override' } }
    if ($null -ne $Profile) {
        $delivery = Get-PqValue $Profile 'delivery'
        $command = [string](Get-PqValue $delivery 'versionCommand' '')
        if (-not [string]::IsNullOrWhiteSpace($command) -and $RepoPath) {
            $tokens = @(Split-PqCommandLine $command)
            $file = [string]$tokens[0]
            if (-not [IO.Path]::IsPathFullyQualified($file)) { $file = Join-Path $RepoPath $file }
            if ([IO.File]::Exists($file)) {
                $psi = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
                $psi.ArgumentList.Add('-NoProfile')
                $psi.ArgumentList.Add('-File')
                $psi.ArgumentList.Add((ConvertTo-PqFullPath $file))
                foreach ($a in @($tokens | Select-Object -Skip 1)) { $psi.ArgumentList.Add([string]$a) }
                $psi.UseShellExecute = $false
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                $p = [Diagnostics.Process]::Start($psi)
                $text = $p.StandardOutput.ReadToEnd()
                $null = $p.StandardError.ReadToEnd()
                $p.WaitForExit()
                $last = @($text -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Last 1)
                if (@($last).Count -gt 0 -and [string]$last[0] -cmatch '^\d+(?:\.\d+){1,3}$') {
                    return @{ version = [string]$last[0]; source = 'profile versionCommand' }
                }
            }
        }
    }
    foreach ($a in @($Artifacts)) {
        $v = Get-PqArtifactStampVersion ([string]$a)
        if ($v) { return @{ version = $v; source = 'artifact' } }
    }
    if ($null -ne $Stamp -and $RepoPath) {
        $shape = Get-PqValue (Get-PqValue $Stamp 'versionShape') 'tagRegex'
        $v = Get-PqRepoTagVersion -RepoPath $RepoPath -TagRegex ([string]$shape)
        if ($v) { return @{ version = $v; source = 'tag' } }
    }
    return $null
}

# What the build wrote: the recency of the write is the evidence (a build tool can invent a layout, a timestamp is
# the truth it cannot fake). Patterns from the profile win when declared, because the repo naming them is the
# repo's own record - the same discover-never-assume rule as the build command.
function Find-PqNewArtifacts {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][datetime]$SinceUtc,
        $Profile = $null
    )
    $root = [IO.Path]::GetFullPath($RepoPath)
    $result = [Collections.Generic.List[string]]::new()
    $added = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $add = {
        param([string]$File)
        if (-not [IO.File]::Exists($File)) { return }
        if (-not $added.Add([IO.Path]::GetFullPath($File))) { return }
        $info = [IO.FileInfo]::new($File)
        if ($info.LastWriteTimeUtc -lt $SinceUtc.AddSeconds(-2)) { return }
        $result.Add($info.FullName)
    }
    if ($null -ne $Profile) {
        $patterns = @(Get-PqValue (Get-PqValue $Profile 'delivery') 'artifactPatterns')
        $found = [Collections.Generic.List[string]]::new()
        foreach ($p in @($patterns)) {
            if ($p -isnot [string] -or [string]::IsNullOrWhiteSpace($p)) { continue }
            $full = if ([IO.Path]::IsPathFullyQualified($p)) { $p } else { Join-Path $root ($p.Replace('/', [IO.Path]::DirectorySeparatorChar)) }
            foreach ($f in [IO.Directory]::GetFiles((Split-Path -Parent $full), (Split-Path -Leaf $full))) { $found.Add($f) }
        }
        foreach ($f in @($found)) { & $add $f }
    }
    if ($added.Count -eq 0) {
        # The shipped discovery: a bounded walk (depth 6) around build noise, known artifact extensions only.
        $queue = [Collections.Generic.Queue[string]]::new()
        $queue.Enqueue($root)
        $depth = @{ $root = 0 }
        $seen = 50000
        while ($queue.Count -gt 0 -and $seen -gt 0) {
            $dir = $queue.Dequeue()
            foreach ($entry in [IO.Directory]::EnumerateFileSystemEntries($dir)) {
                $seen--
                if ($seen -le 0) { break }
                if ([IO.Directory]::Exists($entry)) {
                    $name = Split-Path -Leaf $entry
                    if ($script:PqArtifactSkipDirs -ccontains $name) { continue }
                    if (-not $depth.Contains($entry)) {
                        $d = [int]$depth[$dir] + 1
                        if ($d -le 6) { $depth[$entry] = $d; $queue.Enqueue($entry) } else { $depth[$entry] = $d }
                    }
                    continue
                }
                if ($script:PqArtifactExtensions -ccontains [IO.Path]::GetExtension($entry).ToLowerInvariant()) { & $add $entry }
            }
        }
    }
    # Two artifacts with the same base name are one artifact: a build that runs publish leaves the apphost of
    # the intermediate build beside the publish output. The newest write is the build's own final answer.
    $newest = [ordered]@{}
    foreach ($f in @($result)) {
        $name = Split-Path -Leaf $f
        if (-not $newest.Contains($name)) { $newest[$name] = $f; continue }
        if ([IO.File]::GetLastWriteTimeUtc($f) -gt [IO.File]::GetLastWriteTimeUtc([string]$newest[$name])) { $newest[$name] = $f }
    }
    return [string[]](@($newest.Values) | Sort-Object -Property { [IO.Path]::GetFileName($_) }, [StringComparer]::Ordinal)
}

function Request-PqBuildToken {
    param(
        [Parameter(Mandatory)]$Registry,
        [Parameter(Mandatory)][string]$RepoKey,
        [string]$TicketId = 'build-deliver',
        [int]$WaitSeconds = 900
    )
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds([Math]::Max(0, $WaitSeconds))
    $waited = [double]0
    while ($true) {
        # A live build token of the SAME repo, held by another process, means exactly the race the token exists
        # for: a PQ pass (or another build-deliver) is building this repository right now. Wait it out.
        $others = @((Get-PqResourceHeld -Token build -ClearStale).live |
            Where-Object { (Get-PqValue $_ 'repo') -ceq $RepoKey -and [int](Get-PqValue $_ 'pid' 0) -ne $PID })
        if (@($others).Count -eq 0) {
            $req = Request-PqResources -Registry $Registry -RepoKey $RepoKey -TicketId $TicketId -Verify 'build' -PassId 'build-deliver'
            if ($req.ok) { return @{ ok = $true; waited = [int][Math]::Round($waited); ticketId = $TicketId } }
        }
        if ([DateTimeOffset]::UtcNow -ge $deadline) {
            return @{ ok = $false; waited = [int][Math]::Round($waited); why = 'resources'; ticketId = $TicketId }
        }
        [Threading.Thread]::Sleep(300)
        $waited += 0.3
    }
}

function Get-PqFileSha256([string]$Path) {
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($Path))).ToLowerInvariant()
}

function Copy-PqDeliveryArtifacts {
    param(
        [Parameter(Mandatory)]$Artifacts,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Version
    )
    Assert-PqSegment 'Key' $Key
    Assert-PqSegment 'Version' $Version
    $dir = Join-Path (Join-Path (ConvertTo-PqFullPath $Root) $Key) $Version
    if (-not [IO.Directory]::Exists($dir)) { $null = [IO.Directory]::CreateDirectory($dir) }
    $files = [Collections.Generic.List[string]]::new()
    $hashes = [Collections.Generic.List[string]]::new()
    foreach ($a in @($Artifacts)) {
        $src = [string]$a
        if (-not [IO.File]::Exists($src)) { throw "ArtifactMissing: $src" }
        $name = Split-Path -Leaf $src
        $dest = Join-Path $dir $name
        [IO.File]::Copy($src, $dest, $true)
        $hash = Get-PqFileSha256 $dest
        # The GitHub sidecar shape the repos already use: "<hash>  <name>", ascii.
        [IO.File]::WriteAllText("$dest.sha256", "$hash  $name", [Text.ASCIIEncoding]::new())
        $files.Add($dest)
        $hashes.Add($hash)
    }
    return @{ dir = $dir; files = [string[]]$files.ToArray(); sha256 = [string[]]$hashes.ToArray() }
}

function Set-PqDeliveryLatest {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][string]$Version)
    Assert-PqSegment 'Key' $Key
    $keyDir = Join-Path (ConvertTo-PqFullPath $Root) $Key
    if (-not [IO.Directory]::Exists($keyDir)) { $null = [IO.Directory]::CreateDirectory($keyDir) }
    $tmp = Join-Path $keyDir "LATEST.$PID.tmp"
    [IO.File]::WriteAllText($tmp, "$Version`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($tmp, (Join-Path $keyDir 'LATEST'), $true)
}

function Get-PqDeliveryLatest {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Key)
    $path = Join-Path (Join-Path (ConvertTo-PqFullPath $Root) $Key) 'LATEST'
    if (-not [IO.File]::Exists($path)) { return $null }
    $v = ([IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)).Trim()
    if ([string]::IsNullOrWhiteSpace($v)) { return $null }
    return $v
}

function New-PqDeliveryEvent {
    param($Log, [Parameter(Mandatory)]$Record)
    if ($null -eq $Log) { return $false }
    $d = [ordered]@{
        project   = [string]$Record.project
        version   = [string]$Record.version
        artifacts = [string[]]@($Record.artifacts | ForEach-Object { Split-Path -Leaf $_ })
        sha256    = [string[]]@($Record.sha256)
        at        = [string]$Record.at
    }
    if ($Record.Contains('ticket') -and $Record.ticket) { $d['ticket'] = [string]$Record.ticket }
    return (Write-PqEvent -Log $Log -Ev 'build.delivered' -Repo ([string]$Record.project) -Id ([string]$Record.ticket) -D $d)
}

# The newest build.delivered per project, in event order - what pq status prints.
function Get-PqLastDeliveries {
    $logDir = Join-Path (Get-PqRoot) 'log'
    if (-not [IO.Directory]::Exists($logDir)) { return @() }
    $latest = [ordered]@{}
    foreach ($f in [IO.Directory]::GetFiles($logDir, 'events-*.jsonl')) {
        foreach ($e in (Read-PqDay -Path $f).events) {
            if ($e.ev -cne 'build.delivered') { continue }
            $project = [string]$e.d.project
            if (-not $project) { continue }
            $prev = $latest[$project]
            if ($null -eq $prev -or ([string]$e.ts -cgt [string]$prev.at)) {
                $latest[$project] = [pscustomobject]@{ project = $project; version = [string]$e.d.version; at = [string]$e.ts }
            }
        }
    }
    return @($latest.Values | Sort-Object -Property project)
}

# The note (and, with -Status, the status) on a ticket's ledger row, through the project's own status tooling -
# the harness never writes a ledger (TASK-FLOW rule 43). -StatusNote only: the row's status is preserved.
function Set-PqTicketDeliveryNote {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][string]$TicketId,
        [Parameter(Mandatory)][string]$Note,
        [string]$Status = '',
        [string]$UpdateScript = ''
    )
    $own = Join-Path $RepoPath (Join-Path 'scripts' (Join-Path 'spec_catalog' 'update.ps1'))
    $tool = $UpdateScript
    if (-not $tool) {
        if ([IO.File]::Exists($own)) { $tool = (ConvertTo-PqFullPath $own) }
        else {
            # $PSScriptRoot here is the portfolio lib: four parents up is the canon working tree.
            $canonTool = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))) `
                (Join-Path 'tools' (Join-Path 'harness' (Join-Path 'spec_catalog' 'update.ps1')))
            if ([IO.File]::Exists($canonTool)) { $tool = (ConvertTo-PqFullPath $canonTool) }
        }
    }
    if (-not $tool -or -not [IO.File]::Exists($tool)) { return @{ ok = $false; error = 'no update.ps1 found for the project' } }
    try {
        $psi = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
        $psi.ArgumentList.Add('-NoProfile')
        $psi.ArgumentList.Add('-File')
        $psi.ArgumentList.Add($tool)
        $psi.ArgumentList.Add('-Id')
        $psi.ArgumentList.Add($TicketId)
        if ($Status) { $psi.ArgumentList.Add('-Status'); $psi.ArgumentList.Add($Status) }
        $psi.ArgumentList.Add('-StatusNote')
        $psi.ArgumentList.Add($Note)
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $p = [Diagnostics.Process]::Start($psi)
        $out = $p.StandardOutput.ReadToEnd()
        $err = $p.StandardError.ReadToEnd()
        $p.WaitForExit()
        if ($p.ExitCode -ne 0) { return @{ ok = $false; tool = $tool; error = ((@($out, $err) | Where-Object { $_ }) -join ' ').Trim() } }
        return @{ ok = $true; tool = $tool }
    }
    catch { return @{ ok = $false; tool = $tool; error = $_.Exception.Message } }
}

# ---- the store staging leg ----

function Get-PqStoreFrozenPublisher { return $script:PqStoreFrozenPublisher }
function Get-PqStoreFrozenPublisherDisplayName { return $script:PqStoreFrozenPublisherDisplayName }

# The reserved identity a repo already recorded (STORE_PUBLISHING.md is the first source the skill names).
function Get-PqStoreIdentity {
    param([Parameter(Mandatory)][string]$RepoPath)
    $file = Join-Path $RepoPath 'STORE_PUBLISHING.md'
    if (-not [IO.File]::Exists($file)) { return @{ file = $null; identityName = $null; publisher = $null; publisherDisplayName = $null; publisherAssert = $null } }
    $rows = [ordered]@{}
    try {
        foreach ($line in [IO.File]::ReadAllLines($file, [Text.Encoding]::UTF8)) {
            $m = [regex]::Match($line, '^\|\s*`?(?:Package/)?(?<field>(?:Identity/Name|Identity/Publisher|Properties/PublisherDisplayName))`?\s*\|\s*`(?<v>[^`|]+)`')
            if ($m.Success) { $rows[[string]$m.Groups['field'].Value] = $m.Groups['v'].Value.Trim() }
        }
    }
    catch { }
    $publisher = $rows['Identity/Publisher']
    $assert = $null
    if ($publisher) { $assert = ($publisher -ceq $script:PqStoreFrozenPublisher) }
    return @{
        file                  = $file
        identityName          = $rows['Identity/Name']
        publisher             = $publisher
        publisherDisplayName  = $rows['Properties/PublisherDisplayName']
        publisherDisplayNameAssert = ($rows['Properties/PublisherDisplayName'] -ceq $script:PqStoreFrozenPublisherDisplayName)
        publisherAssert       = $assert
    }
}

function Find-PqMsixBuildScript {
    param([Parameter(Mandatory)][string]$RepoPath)
    foreach ($rel in @('msix\build-msix.ps1', 'publishing\msix\build-msix.ps1')) {
        $candidate = Join-Path $RepoPath ($rel.Replace('\', [IO.Path]::DirectorySeparatorChar))
        if ([IO.File]::Exists($candidate)) { return (ConvertTo-PqFullPath $candidate) }
    }
    return $null
}

function Find-PqListingSources {
    param([Parameter(Mandatory)][string]$RepoPath)
    $rels = [string[]]@(
        'msix\listing', 'msix\store-listings.md', 'msix\store-listing.md', 'msix\build-store-listing-csv.ps1', 'msix\merge-listing-export.ps1',
        'publishing\store\listingData.csv', 'tools\store\listingData.csv', 'tools\store\build-store-listing-csv.ps1'
    )
    $found = [Collections.Generic.List[string]]::new()
    foreach ($rel in $rels) {
        $candidate = Join-Path $RepoPath ($rel.Replace('\', [IO.Path]::DirectorySeparatorChar))
        if ([IO.File]::Exists($candidate) -or [IO.Directory]::Exists($candidate)) { $found.Add($rel.Replace('\', '/')) }
    }
    return [string[]]$found.ToArray()
}

# The discover-never-assume plan: what this repo can build, with what identity, and the steps that stay manual
# because they are interactive or one-way [PUBLIC]. No step of this plan uploads anything.
function Get-PqStoreStagePlan {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        $Profile = $null
    )
    $root = ConvertTo-PqFullPath $RepoPath
    $msix = Find-PqMsixBuildScript $root
    $identity = Get-PqStoreIdentity $root
    $listing = Find-PqListingSources $root
    # Only the parameters the repo's own script declares are ever passed (the bare-build trap: defaults differ).
    $params = [string[]]@()
    if ($msix) {
        try { $params = [string[]]@((Get-Command -Name $msix -CommandType ExternalScript).Parameters.Keys | ForEach-Object { "-$_" }) } catch { $params = [string[]]@() }
    }
    return [pscustomobject]@{
        repo              = $root
        msixScript        = $msix
        msixParameters    = $params
        identityFile      = $identity.file
        identityName      = $identity.identityName
        publisher         = $identity.publisher
        publisherDisplayName = $identity.publisherDisplayName
        publisherAssert   = $identity.publisherAssert
        publisherDisplayNameAssert = $identity.publisherDisplayNameAssert
        listingSources    = $listing
        storePublishing   = [bool]$identity.file
        thirdPartyNotices = [IO.File]::Exists((Join-Path $root 'THIRD-PARTY-NOTICES.txt'))
        manualUpload      = $true
    }
}

# Read the packed <Identity> element back out of a package (an MSIX is a zip; AppxManifest.xml is at its root).
function Read-PqMsixIdentity {
    param([Parameter(Mandatory)][string]$MsixPath)
    if (-not [IO.File]::Exists($MsixPath)) { return $null }
    try {
        $zip = [IO.Compression.ZipFile]::OpenRead($MsixPath)
        try {
            $entry = @($zip.Entries | Where-Object { $_.Name -ceq 'AppxManifest.xml' } | Select-Object -First 1)
            if (@($entry).Count -eq 0) { return $null }
            $reader = [IO.StreamReader]::new($entry[0].Open(), [Text.Encoding]::UTF8)
            try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
            $tag = [regex]::Match($text, '<Identity\s+[^>]*/>')
            if (-not $tag.Success) { return $null }
            $name = [regex]::Match($tag.Value, 'Name\s*=\s*"([^"]+)"')
            $pub = [regex]::Match($tag.Value, 'Publisher\s*=\s*"([^"]+)"')
            $ver = [regex]::Match($tag.Value, 'Version\s*=\s*"([^"]+)"')
            return @{ name = $name.Groups[1].Value; publisher = $pub.Groups[1].Value; version = $ver.Groups[1].Value }
        }
        finally { $zip.Dispose() }
    }
    catch { return $null }
}

# The WACK verdict comes from the report, never from an exit code; an empty or advisory-only report is no pass.
function Read-PqWackVerdict {
    param([Parameter(Mandatory)][string]$ReportPath)
    if (-not [IO.File]::Exists($ReportPath)) { return $null }
    try { $text = [IO.File]::ReadAllText($ReportPath, [Text.Encoding]::UTF8) } catch { return $null }
    $m = [regex]::Match($text, 'OVERALL_RESULT\s*=\s*"(?<r>[A-Z]+)"')
    if (-not $m.Success) { return $null }
    return $m.Groups['r'].Value
}
