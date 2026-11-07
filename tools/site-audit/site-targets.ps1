#requires -Version 7.5
<#
.SYNOPSIS
    Resolve the sites a site audit runs against and print the site-audit workflow's args as JSON.

.DESCRIPTION
    A target is a repository whose .sza-canon.json stamp carries a `site` block ({kind, root, pages}); kind 'none'
    serves no pages, and an absent root is the repository root (REPO-STAMP rule 4). A stamp that does not parse or is
    not an object, a schemaVersion this reader does not support (the amendment of 2026-10-23), a site that is not an
    object or names no kind (rule 4 gives an absent kind no meaning), and a root outside the repository are refused,
    never read as a stamp without a site (rule 2). The base URL is the CNAME in the served root (https://<cname>/; a
    CNAME that is not a bare host name is refused), otherwise the GitHub Pages address derived from the origin remote
    (https://<owner>.github.io/<repo>/, the owner lowercased).

    Each target gets a fresh run folder, <repo>/<tempDir>/site-audit/<date>[_<n>]/. <tempDir> is paths.tempDir of the
    repository's own .sza-profile.json, 'temp' by default (HARNESS-PROFILE rule 1; a profile that cannot be read is a
    refusal), and <n> is one more than the highest run of that date, so the name of a deleted run is never reused. git
    must ignore the whole folder: on a site served from the repository root every tracked file is published, so a
    report in a tracked folder is one `git add -A` away from the public site. A target whose run folder git would
    track is refused and listed under "refused", never written. This script writes nothing but the -OutFile; the
    workflow's agents create the folders.

    The previous run is the newest earlier run folder that holds a report.md or an imported baseline.md: prevDir
    names the folder and prevFile the file the report stage compares with, report.md first. A run that also holds the
    report of every lens this run asks for, or a baseline, wins over a newer one that does not, so a run of one lens
    is never the yardstick of a full one.

.PARAMETER Repo
    One repository, or any folder inside one. Default: the current location. Its key is the registry's, matched by
    the path or by the folder git reports for a registry path (a junction, a short name), else the folder name.

.PARAMETER All
    Every repository the portfolio registry lists whose stamp has a site block, in project order (rank ascending,
    equal ranks in file order; TASK-FLOW rule 45), enabled or not: enabled and hold govern the queue, not the site.
    The registry is read the way pq.ps1 reads it, SZA_PORTFOLIO_ROOT included; an unreadable one is exit 2 with pq's
    own error. A registered folder git cannot open is refused when it declares a site, and skipped when it is gone.

.PARAMETER Url
    Hosts with no repository on this machine, as several values or as one comma-separated list (pwsh -File passes
    `-Url <a>,<b>` as one string). Each is an absolute http(s) base URL with no query, fragment or user name; a last
    path segment with a dot in it names a page and is cut. The host, lowercased, with _<port> for a port that is not
    the default, names the run folder <portfolio repo>/<tempDir>/site-audit/<run>/external/<host>/, so a second URL
    on the same host is refused. A malformed URL is exit 2 before any repository is weighed.

.PARAMETER PortfolioKey
    The target whose run folder receives portfolio.md and the external hosts. Default: the first target of kind
    'portfolio' served from a custom domain, else the first target.

.PARAMETER Lens
    A lens subset for an audit run, as several values or as one comma-separated list; default all six: robot, ux,
    release-facts, structured-data, i18n, docs. An unknown name is exit 2.

.PARAMETER Mode
    audit (default) or prepublish.

.PARAMETER Baseline
    A baseline findings file the report stage compares with when a site has no previous run. A relative path is
    taken from the current location.

.PARAMETER Date
    yyyy-MM-dd, a real date of the Gregorian calendar. Default: today.

.PARAMETER OutFile
    Write the JSON there instead of to stdout; a relative path is taken from the current location. The file names
    absolute local paths, so inside a git working tree it must be a path git ignores (exit 2 otherwise): the
    scratchpad is the place for it.

.EXAMPLE
    pwsh -NoProfile -File tools/site-audit/site-targets.ps1 -All -Url https://example.org/ -OutFile <scratchpad>/site-audit-args.json

Exit codes:
  0  at least one target resolved (refused ones, if any, are listed)
  2  bad invocation, an unreadable registry under -All, or nothing to audit; the refusals collected before it are listed
  3  every target was refused
#>
[CmdletBinding()]
param(
    [string]$Repo = (Get-Location).Path,
    [switch]$All,
    [string[]]$Url = @(),
    [string]$PortfolioKey = '',
    [string[]]$Lens = @(),
    [ValidateSet('audit', 'prepublish')]
    [string]$Mode = 'audit',
    [string]$Baseline = '',
    # The invariant culture: the local calendar need not be the Gregorian one (th-TH counts the year 2569).
    [string]$Date = (Get-Date).ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture),
    [string]$OutFile = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pluginRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
# The profile defaults (paths.tempDir) and Assert-SzaSchemaCarrier; dot-sourcing defines them and reads no project.
. (Join-Path $pluginRoot 'tools/harness/_profile.ps1')
# The portfolio registry as pq.ps1 reads it - SZA_PORTFOLIO_ROOT, its validation, the project order - in this process.
. (Join-Path $pluginRoot 'tools/harness/portfolio/lib/registry.ps1')

$targets = [System.Collections.Generic.List[object]]::new()
$refused = [System.Collections.Generic.List[object]]::new()

function Write-Refusal([string]$Message) { [Console]::Error.WriteLine("site-targets: $Message") }
function Write-Refused { foreach ($r in $refused) { Write-Refusal "refused $($r.key): $($r.reason)" } }
# Every exit after the targets are weighed lists the refusals so far: the reason a target fell is never lost.
function Exit-Run([int]$Code) { Write-Refused; exit $Code }
function Add-Refusal([string]$Key, $RepoPath, [string]$Reason) { $refused.Add([pscustomobject]@{ key = $Key; repo = $RepoPath; reason = $Reason }) }

# A relative path is taken from the current location, as Test-Path takes it, never from the process folder: a call
# with & after Set-Location has the two apart.
function Resolve-LocalPath([string]$Path) {
    $provider = $null
    $drive = $null
    $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path, [ref]$provider, [ref]$drive)
    if ($provider.Name -ne 'FileSystem') { throw "'$Path' is not a file-system path" }
    return $full
}

function Get-GitTop([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $top = git -C $Path rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $top) { return $null }
    return [IO.Path]::GetFullPath($top)
}

# git check-ignore, run in $Where. A folder is asked about with its trailing slash: git never looks inside an ignored
# folder, so the answer covers every file written into it, and it holds before the folder exists.
function Test-Ignored([string]$Where, [string]$RelPath) {
    git -C $Where check-ignore -q -- $RelPath 2>$null
    return ($LASTEXITCODE -eq 0)
}

# StrictMode-safe: an object with no properties has no .PSObject.Properties.Name to read (Test-SzaHasProperty).
function Get-Prop($Object, [string]$Name, $Default) {
    $p = if ($null -ne $Object) { $Object.PSObject.Properties[$Name] }
    if ($null -ne $p -and $null -ne $p.Value) { return $p.Value }
    return $Default
}

function Test-Inside([string]$Root, [string]$Path) {
    $r = [IO.Path]::TrimEndingDirectorySeparator($Root)
    return ($Path -ieq $r -or $Path.StartsWith($r + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase))
}

function Get-SiteBlock([string]$RepoRoot) {
    $stamp = Join-Path $RepoRoot '.sza-canon.json'
    if (-not (Test-Path -LiteralPath $stamp -PathType Leaf)) { return $null }
    # REPO-STAMP rule 2: a stamp that does not parse is reported, never read as one that declares nothing.
    $j = $null
    try { $j = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $stamp -Raw) -DateKind String -NoEnumerate } catch { }
    if ($null -eq $j) { throw 'the stamp .sza-canon.json is not valid JSON (REPO-STAMP rule 2)' }
    if ($j -isnot [System.Management.Automation.PSCustomObject]) { throw 'the stamp .sza-canon.json is not a JSON object (REPO-STAMP rule 2)' }
    # The amendment of 2026-10-23: an unsupported or malformed schemaVersion is refused before any declaration is read.
    Assert-SzaSchemaCarrier $j 'schemaVersion' 'REPO-STAMP'
    $prop = $j.PSObject.Properties['site']
    if ($null -eq $prop -or $null -eq $prop.Value) { return $null }
    $site = $prop.Value
    if ($site -isnot [System.Management.Automation.PSCustomObject]) { throw 'the site of the stamp is not an object (REPO-STAMP rule 4)' }
    # Rule 4 gives kind 'none' a meaning and an absent kind none, so an absent kind is not read as 'none'.
    $kind = Get-Prop $site 'kind' $null
    if ($kind -isnot [string] -or -not $kind.Trim()) { throw 'the site block of the stamp has no kind - write none, product or portfolio' }
    if ($kind -eq 'none') { return $null }
    return $site
}

# HARNESS-PROFILE rule 1: the scratch root is paths.tempDir of the repository's own profile over the canon default,
# read per repository, because Get-SzaPath serves one project per process.
function Get-TempDir([string]$RepoRoot) {
    $dir = [string]$Script:SzaProfileDefaults.paths.tempDir
    $file = Join-Path $RepoRoot '.sza-profile.json'
    if (Test-Path -LiteralPath $file -PathType Leaf) {
        $prof = $null
        try { $prof = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $file -Raw) -DateKind String -NoEnumerate } catch { }
        if ($prof -isnot [System.Management.Automation.PSCustomObject]) { throw 'the profile .sza-profile.json is not a JSON object' }
        Assert-SzaSchemaCarrier $prof 'version' 'HARNESS-PROFILE'
        $v = Get-Prop (Get-Prop $prof 'paths' $null) 'tempDir' $null
        if ($null -ne $v) {
            if ($v -isnot [string]) { throw 'paths.tempDir in .sza-profile.json is not a string' }
            $dir = $v
        }
    }
    $dir = $dir.Trim().Replace('\', '/')
    if (-not $dir.Trim('/') -or [IO.Path]::IsPathRooted($dir) -or $dir -match '(^|/)\.\.(/|$)') {
        throw "paths.tempDir '$dir' in .sza-profile.json is not a folder inside the repository"
    }
    return $dir.TrimEnd('/')
}

# CNAME in the served root first; the Pages address from the origin remote otherwise.
function Get-BaseUrl([string]$RepoRoot, [string]$ServedRoot) {
    $cnameFile = Join-Path $ServedRoot 'CNAME'
    if (Test-Path -LiteralPath $cnameFile -PathType Leaf) {
        $domain = ((Get-Content -LiteralPath $cnameFile -TotalCount 1) ?? '').Trim().TrimEnd('/')
        if ($domain) {
            if ($domain -notmatch '^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$') { throw "the CNAME in the served root holds '$domain', not a bare host name" }
            return [pscustomobject]@{ url = "https://$domain/"; cname = $domain }
        }
    }
    $origin = git -C $RepoRoot remote get-url origin 2>$null
    if ($LASTEXITCODE -eq 0 -and "$origin" -match 'github\.com[:/]([^/]+)/([^/]+?)(?:\.git)?/?$') {
        $owner = $Matches[1].ToLowerInvariant()
        $name = $Matches[2]
        if ($name.ToLowerInvariant() -eq "$owner.github.io") { return [pscustomobject]@{ url = "https://$owner.github.io/"; cname = $null } }
        return [pscustomobject]@{ url = "https://$owner.github.io/$name/"; cname = $null }
    }
    return $null
}

# A run folder is <yyyy-MM-dd> or <yyyy-MM-dd>_<n>, a real date and n of up to six digits; any other name is no run.
function Get-RunSortKey([string]$Name) {
    if ($Name -notmatch '^(\d{4}-\d{2}-\d{2})(?:_(\d{1,6}))?$') { return $null }
    $day = $Matches[1]
    $n = if ($Matches[2]) { [int]$Matches[2] } else { 1 }
    $parsed = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($day, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed)) { return $null }
    return '{0}_{1:D6}' -f $day, $n
}

# One more than the highest run of the date, never the first free name: a deleted run's name, reused, would sort
# before the runs that followed it and break the previous-run chain.
function Get-RunName([string]$RepoRoot, [string]$RunRel) {
    $base = Join-Path $RepoRoot $RunRel
    $max = 0
    if (Test-Path -LiteralPath $base -PathType Container) {
        $rx = '^' + [regex]::Escape($Date) + '(?:_(\d{1,6}))?$'
        foreach ($d in Get-ChildItem -LiteralPath $base -Force) {
            if ($d.Name -match $rx) {
                $n = if ($Matches[1]) { [int]$Matches[1] } else { 1 }
                if ($n -gt $max) { $max = $n }
            }
        }
    }
    $n = $max + 1
    $name = if ($n -eq 1) { $Date } else { "${Date}_$n" }
    # Past six digits a name is no run, so it is not counted above: never hand out one that exists all the same.
    while (Test-Path -LiteralPath (Join-Path $base $name)) { $n++; $name = "${Date}_$n" }
    return $name
}

# The newest earlier run that left a report.md (or an imported baseline.md) behind: its folder and that file. One that
# also holds the report of every lens this run asks for, or a baseline, wins over a newer one that does not.
function Get-PreviousRun([string]$RepoRoot, [string]$RunRel, [string]$CurrentName, [string]$Sub = '') {
    $base = Join-Path $RepoRoot $RunRel
    $current = Get-RunSortKey $CurrentName
    if (-not $current -or -not (Test-Path -LiteralPath $base -PathType Container)) { return $null }
    $runs = @(foreach ($d in Get-ChildItem -LiteralPath $base -Directory -Force) {
            $k = Get-RunSortKey $d.Name
            if ($k -and $k -lt $current) { [pscustomobject]@{ key = $k; dir = $(if ($Sub) { Join-Path $d.FullName $Sub } else { $d.FullName }) } }
        })
    $fallback = $null
    foreach ($r in @($runs | Sort-Object key -Descending)) {
        $report = Join-Path $r.dir 'report.md'
        $imported = Join-Path $r.dir 'baseline.md'
        if (Test-Path -LiteralPath $report -PathType Leaf) {
            $found = [pscustomobject]@{ dir = $r.dir; file = $report }
            $missing = @($needLenses | Where-Object { -not (Test-Path -LiteralPath (Join-Path $r.dir "$_.md") -PathType Leaf) })
            if (-not $missing.Count) { return $found }
            if (-not $fallback) { $fallback = $found }
        }
        elseif (Test-Path -LiteralPath $imported -PathType Leaf) { return [pscustomobject]@{ dir = $r.dir; file = $imported } }
    }
    return $fallback
}

$parsedDate = [datetime]::MinValue
if (-not [datetime]::TryParseExact($Date, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsedDate)) {
    Write-Refusal "-Date must be a real yyyy-MM-dd date, got '$Date'"; exit 2
}
if ($Baseline) {
    try { $Baseline = Resolve-LocalPath $Baseline } catch { Write-Refusal "-Baseline: $($_.Exception.Message)"; exit 2 }
    if (-not (Test-Path -LiteralPath $Baseline -PathType Leaf)) { Write-Refusal "baseline file not found: $Baseline"; exit 2 }
}
if ($OutFile) {
    try { $OutFile = Resolve-LocalPath $OutFile } catch { Write-Refusal "-OutFile: $($_.Exception.Message)"; exit 2 }
    $outFolder = Split-Path -Parent $OutFile
    if (-not (Test-Path -LiteralPath $outFolder -PathType Container)) { Write-Refusal "-OutFile: no folder $outFolder"; exit 2 }
    # The file names absolute local paths: in a tracked folder of a served site it is one `git add -A` from the public.
    $outTop = Get-GitTop $outFolder
    if ($outTop -and -not (Test-Ignored $outFolder (Split-Path -Leaf $OutFile))) {
        Write-Refusal "-OutFile $OutFile is in the git working tree $outTop and git would track it: write it to the scratchpad or to an ignored folder"; exit 2
    }
}

# pwsh -File hands '-Lens robot,ux' and '-Url <a>,<b>', the form the skill passes, over as one string each, so the
# lists are split here; a ValidateSet on -Lens would refuse 'robot,ux' before this line runs. The workflow compares
# the mode and the lens names case-sensitively, so they leave in its spelling, each lens once.
$lensNames = @('robot', 'ux', 'release-facts', 'structured-data', 'i18n', 'docs')
$picked = [System.Collections.Generic.List[string]]::new()
foreach ($l in @($Lens | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
    $known = @($lensNames | Where-Object { $_ -eq $l })
    if (-not $known.Count) { Write-Refusal "unknown lens '$l'; the lenses are $($lensNames -join ', ')"; exit 2 }
    if (-not $picked.Contains($known[0])) { $picked.Add($known[0]) }
}
$Lens = $picked.ToArray()
$Mode = $Mode.ToLowerInvariant()
# What a previous run must hold to be this run's yardstick: the report of every lens this run asks for. Prepublish
# compares only the rows its own checks re-measure, so any report serves it.
$needLenses = @(if ($Mode -ne 'prepublish') { if ($Lens.Count) { $Lens } else { $lensNames } })

# -Url values are judged before any repository is weighed, so a malformed one is exit 2 whatever the targets.
$urlSpecs = [System.Collections.Generic.List[object]]::new()
foreach ($u in @($Url | ForEach-Object { $_ -split ',(?=\s*https?://)' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
    $uri = $null
    if (-not [Uri]::TryCreate($u, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @('http', 'https')) { Write-Refusal "not an absolute http(s) URL: $u"; exit 2 }
    if ($uri.Query -or $uri.Fragment -or $uri.UserInfo) { Write-Refusal "-Url $u - give the base URL, not a page: no query, fragment or user name"; exit 2 }
    # The host names a folder, external/<host>: lowercased, in punycode, a port that is not the default as _<port>.
    $hostName = $uri.IdnHost.ToLowerInvariant().TrimEnd('.') -replace '[^a-z0-9.-]', '_'
    if ($hostName -notmatch '[a-z0-9]') { Write-Refusal "-Url $u names no host"; exit 2 }
    if (-not $uri.IsDefaultPort) { $hostName += "_$($uri.Port)" }
    # A last path segment with a dot in it names a page, and its folder is the base.
    $path = $uri.AbsolutePath
    $slash = $path.LastIndexOf('/')
    if ($path.Substring($slash + 1).Contains('.')) { $path = $path.Substring(0, $slash + 1) }
    if (-not $path.EndsWith('/')) { $path += '/' }
    $authority = if ($uri.HostNameType -eq [UriHostNameType]::IPv6) { $uri.Host } else { $uri.IdnHost }
    if (-not $uri.IsDefaultPort) { $authority += ":$($uri.Port)" }
    $urlSpecs.Add([pscustomobject]@{ given = $u; url = "$($uri.Scheme)://$authority$path"; host = $hostName })
}

# The registry, in project order: rank ascending, equal ranks in file order (TASK-FLOW rule 45, Get-PqRepoOrder).
$registryError = ''
$registry = @()
try {
    $read = Read-PqRegistry
    if ($read.ok) {
        $listed = @($read.registry.repos)
        $registry = @(foreach ($o in @(Get-PqRepoOrder -Registry $read.registry)) {
                [pscustomobject]@{ key = [string]$o.key; path = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([string]$listed[$o.index].path)) }
            })
    }
    else { $registryError = (@($read.errors) | ForEach-Object { "$($_.name)$(if ($_.where -ne '$') { " $($_.where)" }) - $($_.message)" }) -join '; ' }
}
catch { $registryError = $_.Exception.Message }

$candidates = [System.Collections.Generic.List[object]]::new()
if ($All) {
    if ($registryError) { Write-Refusal "the portfolio registry cannot be read: $registryError; pass -Repo instead"; exit 2 }
    if (-not $registry.Count) { Write-Refusal 'the portfolio registry lists no repository; pass -Repo instead'; exit 2 }
    foreach ($r in $registry) { $candidates.Add($r) }
}
else {
    try { $Repo = Resolve-LocalPath $Repo } catch { Write-Refusal "-Repo: $($_.Exception.Message)"; exit 2 }
    $top = Get-GitTop $Repo
    if (-not $top) { Write-Refusal "not inside a git repository: $Repo"; exit 2 }
    # The key pq gives it: by the path, else by the folder git reports for a registry path (a junction, a short name).
    $hit = $registry | Where-Object { $_.path -ieq $top } | Select-Object -First 1
    if (-not $hit) { $hit = $registry | Where-Object { (Get-GitTop $_.path) -ieq $top } | Select-Object -First 1 }
    $key = if ($hit) { $hit.key } else { (Split-Path $top -Leaf).ToLowerInvariant() }
    if (-not $hit -and $registryError) { Write-Refusal "note: no registry key ($registryError); the target is named after its folder: $key" }
    $candidates.Add([pscustomobject]@{ key = $key; path = $top })
}

$seenUrl = @{}
$tempDirOf = @{}
foreach ($c in $candidates) {
    $top = Get-GitTop $c.path
    if (-not $top) {
        # A registered folder git cannot open is reported when it declares a site; one that is gone is skipped.
        if (Test-Path -LiteralPath $c.path -PathType Container) {
            $declares = $true
            try { $declares = $null -ne (Get-SiteBlock $c.path) } catch { }
            if ($declares) { Add-Refusal $c.key $c.path 'git cannot open the folder (no .git, or safe.directory refuses it)' }
        }
        continue
    }
    $site = $null
    try {
        $site = Get-SiteBlock $top
        if ($site) {
            $tempDir = Get-TempDir $top
            $siteRoot = [string](Get-Prop $site 'root' '')
            if (-not $siteRoot.Trim()) { $siteRoot = '.' }
            $served = if ([IO.Path]::IsPathRooted($siteRoot)) { $null } else { [IO.Path]::GetFullPath((Join-Path $top $siteRoot)) }
            if (-not $served -or -not (Test-Inside $top $served)) { throw "site.root '$siteRoot' is not a folder inside the repository (REPO-STAMP rule 4)" }
            $base = Get-BaseUrl $top $served
        }
    }
    catch { Add-Refusal $c.key $top $_.Exception.Message; continue }
    if (-not $site) {
        if (-not $All) { Write-Refusal "the stamp of $top has no site block, or its site.kind is none: nothing to audit"; Exit-Run 2 }
        continue
    }
    if (-not $base) { Add-Refusal $c.key $top 'no CNAME in the served root and no GitHub origin remote: the base URL cannot be derived'; continue }
    if ($seenUrl.ContainsKey($base.url)) { Add-Refusal $c.key $top "same URL as $($seenUrl[$base.url]): $($base.url)"; continue }
    $runRel = "$tempDir/site-audit"
    $run = Get-RunName $top $runRel
    if (-not (Test-Ignored $top "$runRel/$run/")) {
        Add-Refusal $c.key $top "git would track $runRel/$run/ - add $tempDir/ to .gitignore first; a report in a tracked folder of a served site gets published"
        continue
    }
    $seenUrl[$base.url] = $c.key
    $tempDirOf[$c.key] = $tempDir
    $prev = Get-PreviousRun $top $runRel $run
    $targets.Add([pscustomobject][ordered]@{
            key      = $c.key
            url      = $base.url
            cname    = $base.cname
            repo     = $top
            siteRoot = $siteRoot
            kind     = [string](Get-Prop $site 'kind' '')
            pages    = @(Get-Prop $site 'pages' @() | ForEach-Object { [string]$_ })
            outDir   = [IO.Path]::GetFullPath((Join-Path $top "$runRel/$run"))
            prevDir  = if ($prev) { $prev.dir } else { $null }
            prevFile = if ($prev) { $prev.file } else { $null }
            run      = $run
        })
}

$portfolio = $null
if ($targets.Count) {
    if ($PortfolioKey) {
        $portfolio = $targets | Where-Object key -EQ $PortfolioKey | Select-Object -First 1
        if (-not $portfolio) { Write-Refusal "-PortfolioKey '$PortfolioKey' is not among the targets"; Exit-Run 2 }
    }
    else { $portfolio = $targets | Where-Object { $_.kind -eq 'portfolio' -and $_.cname } | Select-Object -First 1 }
    if (-not $portfolio) { $portfolio = $targets[0] }
}

$seenHost = @{}
foreach ($u in $urlSpecs) {
    if (-not $portfolio) { Write-Refusal "-Url $($u.given) needs a repository target to hold its report"; Exit-Run $(if ($refused.Count) { 3 } else { 2 }) }
    if ($seenUrl.ContainsKey($u.url)) { continue }
    if ($seenHost.ContainsKey($u.host)) { Add-Refusal $u.host $portfolio.repo "same host as $($seenHost[$u.host]): one external/$($u.host) folder per run"; continue }
    if ($targets | Where-Object key -EQ $u.host) { Add-Refusal $u.host $portfolio.repo "a target is already named $($u.host)"; continue }
    $sub = "external/$($u.host)"
    $runRel = "$($tempDirOf[$portfolio.key])/site-audit"
    $rel = "$runRel/$($portfolio.run)/$sub"
    if (-not (Test-Ignored $portfolio.repo "$rel/")) { Add-Refusal $u.host $portfolio.repo "git would track $rel/"; continue }
    $seenUrl[$u.url] = $u.host
    $seenHost[$u.host] = $u.url
    $prev = Get-PreviousRun $portfolio.repo $runRel $portfolio.run $sub
    $targets.Add([pscustomobject][ordered]@{
            key      = $u.host
            url      = $u.url
            cname    = $null
            repo     = $null
            siteRoot = $null
            kind     = 'external'
            pages    = @()
            outDir   = [IO.Path]::GetFullPath((Join-Path $portfolio.repo $rel))
            prevDir  = if ($prev) { $prev.dir } else { $null }
            prevFile = if ($prev) { $prev.file } else { $null }
            run      = $portfolio.run
        })
}

if (-not $targets.Count) {
    if ($refused.Count) { Exit-Run 3 }
    Write-Refusal 'nothing to audit: no repository with a site block'
    exit 2
}
Write-Refused

$doc = [ordered]@{
    pluginRoot   = $pluginRoot
    date         = $Date
    mode         = $Mode
    lenses       = @($Lens)
    baseline     = $Baseline
    portfolioOut = Join-Path $portfolio.outDir 'portfolio.md'
    targets      = @($targets)
    refused      = @($refused)
}
$json = ConvertTo-Json -InputObject $doc -Depth 6
if ($OutFile) {
    [IO.File]::WriteAllText($OutFile, $json, [Text.UTF8Encoding]::new($false))
    "site-targets: $($targets.Count) target(s), $($refused.Count) refused -> $OutFile"
}
else { $json }
exit 0
