# The portfolio root and every name under it (TASK-FLOW rule 41; S0015 D8).
#
# Dot-source this file; it defines functions only, sets no preference and prints nothing. Nothing here creates a
# file except Initialize-PqRoot, which creates the root and its log directory.
#
#   Get-PqRoot          the root: SZA_PORTFOLIO_ROOT when set, else <USERPROFILE>\.sza\portfolio. Absolute,
#                       separators normalised, no trailing separator. A relative value throws
#                       'PortfolioRootNotAbsolute: <value>'; a root with a .git entry (directory, or the file a
#                       worktree has) in it or any ancestor throws 'PortfolioRootInsideRepository: <path>', because
#                       the state never enters version control.
#   Initialize-PqRoot   creates the root and log\ (idempotent) and returns the root.
#   Get-PqPath -Kind    builds one path under the root (the table below); creates nothing; an unknown kind throws
#                       'PqPathUnknownKind: <kind>', a bad argument 'PqPathArgumentInvalid: <reason>'.
#
#   Kind           Path under the root
#   registry       repos.json
#   queue          PORTFOLIO_QUEUE.md, or -Override (registry paths.portfolioQueue; a relative override is taken
#                  from the root)
#   runs           runs.jsonl
#   stop           STOP
#   stopTarget     STOP-<StopKind>__<Target> (StopKind worker|repo|agent|ticket; for ticket, Target is <key>__<id>)
#   holds / hold   holds / holds\<Agent>.json
#   run            run
#   runState       run\current.json
#   beat           run\beat
#   log / live     log / log\live
#   livePass       log\live\<Pass>.log
#   events         log\events-<Date>.<Token>.jsonl (Date yyyy-MM-dd, UTC; Token is the writer's file token)
#   resources      resources (the token directory of rule 62)
#   resourceToken  resources\<Token>\<Repo>__<Id>.json (Token build|emulator)
#   monitor        monitor\index.html
#   reports        reports

function ConvertTo-PqFullPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $rootPart = [IO.Path]::GetPathRoot($full)
    if ($full.Length -gt $rootPart.Length) {
        $full = $full.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    }
    # The agent CLI keys its per-folder workspace trust on the working directory as spelled, drive letter included:
    # `p:/X` and `P:/X` are two entries, and a pass started from the unaccepted spelling runs untrusted.
    if ($full.Length -ge 2 -and $full[1] -ceq ':' -and [char]::IsLower($full[0])) { $full = $full.Substring(0, 1).ToUpperInvariant() + $full.Substring(1) }
    return $full
}

function Find-PqGitAncestor([string]$Path) {
    $dir = [IO.DirectoryInfo]::new($Path)
    while ($null -ne $dir) {
        $candidate = Join-Path $dir.FullName '.git'
        if ([IO.Directory]::Exists($candidate) -or [IO.File]::Exists($candidate)) { return $dir.FullName }
        $dir = $dir.Parent
    }
    return $null
}

function Get-PqRoot {
    $value = $env:SZA_PORTFOLIO_ROOT
    if ([string]::IsNullOrWhiteSpace($value)) {
        $profileDir = $env:USERPROFILE
        if ([string]::IsNullOrWhiteSpace($profileDir)) { $profileDir = [Environment]::GetFolderPath('UserProfile') }
        $value = Join-Path (Join-Path $profileDir '.sza') 'portfolio'
    }
    if (-not [IO.Path]::IsPathFullyQualified($value)) { throw "PortfolioRootNotAbsolute: $value" }
    $root = ConvertTo-PqFullPath $value
    $repo = Find-PqGitAncestor $root
    if ($null -ne $repo) { throw "PortfolioRootInsideRepository: $root (working tree at $repo)" }
    return $root
}

function Initialize-PqRoot {
    $root = Get-PqRoot
    foreach ($dir in @($root, (Join-Path $root 'log'))) {
        if (-not [IO.Directory]::Exists($dir)) { $null = [IO.Directory]::CreateDirectory($dir) }
    }
    return $root
}

# A name that becomes one path segment: not empty, no separator, no '..', no character a file name cannot hold.
function Assert-PqSegment([string]$Name, [string]$Value) {
    if ([string]::IsNullOrEmpty($Value)) { throw "PqPathArgumentInvalid: -$Name is required" }
    if ($Value.Contains('..') -or $Value.IndexOfAny([char[]]@('\', '/')) -ge 0 -or
        $Value.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        throw "PqPathArgumentInvalid: -$Name '$Value' is not a plain name"
    }
}

function Get-PqPath {
    param(
        [Parameter(Mandatory)][string]$Kind,
        [string]$Agent,
        [string]$StopKind,
        [string]$Target,
        [string]$Pass,
        [string]$Date,
        [string]$Token,
        [string]$Repo,
        [string]$Id,
        [string]$Override
    )
    $root = Get-PqRoot
    $rel = switch ($Kind) {
        'registry' { 'repos.json' }
        'queue' {
            if ($Override) {
                if ([IO.Path]::IsPathFullyQualified($Override)) { return (ConvertTo-PqFullPath $Override) }
                return (ConvertTo-PqFullPath (Join-Path $root $Override))
            }
            'PORTFOLIO_QUEUE.md'
        }
        'runs' { 'runs.jsonl' }
        'stop' { 'STOP' }
        'stopTarget' {
            if ($StopKind -cnotin @('worker', 'repo', 'agent', 'ticket')) {
                throw "PqPathArgumentInvalid: -StopKind '$StopKind' is not worker, repo, agent or ticket"
            }
            Assert-PqSegment 'Target' $Target
            "STOP-${StopKind}__$Target"
        }
        'holds' { 'holds' }
        'hold' { Assert-PqSegment 'Agent' $Agent; Join-Path 'holds' "$Agent.json" }
        'run' { 'run' }
        'runState' { Join-Path 'run' 'current.json' }
        'beat' { Join-Path 'run' 'beat' }
        'log' { 'log' }
        'live' { Join-Path 'log' 'live' }
        'livePass' { Assert-PqSegment 'Pass' $Pass; Join-Path (Join-Path 'log' 'live') "$Pass.log" }
        'events' {
            $parsed = [datetime]::MinValue
            if (-not $Date -or -not [datetime]::TryParseExact($Date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture,
                    [Globalization.DateTimeStyles]::None, [ref]$parsed)) {
                throw "PqPathArgumentInvalid: -Date '$Date' is not yyyy-MM-dd"
            }
            Assert-PqSegment 'Token' $Token
            Join-Path 'log' "events-$Date.$Token.jsonl"
        }
        'resources' { 'resources' }
        'resourceToken' {
            if ($Token -cnotin @('build', 'emulator')) { throw "PqPathArgumentInvalid: -Token '$Token' is not build or emulator" }
            Assert-PqSegment 'Repo' $Repo
            Assert-PqSegment 'Id' $Id
            Join-Path (Join-Path 'resources' $Token) "${Repo}__$Id.json"
        }
        'monitor' { Join-Path 'monitor' 'index.html' }
        'reports' { 'reports' }
        default { throw "PqPathUnknownKind: $Kind" }
    }
    return (Join-Path $root $rel)
}
