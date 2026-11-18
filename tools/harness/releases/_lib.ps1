#requires -Version 7.0
<#
.SYNOPSIS
    The release ledger's reader, writer, fold and renderer (RELEASE-LEDGER 0.1, canon S0092).

.DESCRIPTION
    Dot-sourced by release-ledger.ps1 and by the portfolio's lib/releases.ps1. Every function takes the ledger
    folder (or a repository root) as an argument and never resolves "the" project, so one process can read the
    ledgers of every registered repository. Nothing here touches the network; the probes are _probes.ps1.

    The four files of a ledger folder (RELEASE-LEDGER rule 1):
        channels.json   the packages and the channels each ships to - written at adoption, by hand
        builds.json     the last build per package and flavor - written by the `build` verb
        history.jsonl   every publication event, append-only - written by `publish`, `probe`, `import`
        RELEASES.md     the human view, rendered from the three after every write

    Exit codes: none - a dot-sourced library; errors are thrown with a 'release-ledger:' prefix.
#>

# ---- vocabulary (RELEASE-LEDGER rules 3-6) ----

$script:RlSchemaMajor = 1
$script:RlKnownKinds = @('github', 'winget', 'msstore', 'play', 'chrome', 'edge', 'vscode', 'url', 'manual')
$script:RlStates = @('pending', 'submitted', 'live', 'blocked', 'rejected', 'withdrawn', 'n/a')
$script:RlInFlightStates = @('pending', 'submitted', 'blocked', 'rejected')
$script:RlBuildKinds = @('release', 'test', 'debug')
$script:RlSources = @('release', 'manual', 'probe', 'import')
$script:RlIdPattern = '^[a-z0-9][a-z0-9-]*$'
$script:RlUtf8 = [Text.UTF8Encoding]::new($false)

# The shipped defaults, read in an isolated module: _profile.ps1 caches one project root per process, and a
# reader of several repositories must not inherit one (the same reason as portfolio/lib/ledger-watch.ps1).
$script:RlProfileDefaults = New-Module -ArgumentList (Join-Path $PSScriptRoot '..\_profile.ps1') -ReturnResult -ScriptBlock {
    param($ProfileScript)
    . $ProfileScript
    $script:SzaProfileDefaults
}

# ---- small helpers ----

function Get-RlProp {
    # Null-safe, StrictMode-safe read of one field of a parsed JSON object or a dictionary.
    param($Object, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function ConvertFrom-RlJson {
    # Dates stay the strings they were written as (RELEASE-LEDGER rule 11 keeps what a writer does not own);
    # ConvertFrom-Json would otherwise turn every ISO timestamp into a DateTime and a rewrite would reformat it.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {
        return ($Text | ConvertFrom-Json -DateKind String -Depth 20)
    }
    return ($Text | ConvertFrom-Json -Depth 20)
}

function Get-RlNow {
    # SZA_RELEASES_NOW pins the clock for the fast suite; a real run never sets it.
    if (-not [string]::IsNullOrWhiteSpace($env:SZA_RELEASES_NOW)) { return [string]$env:SZA_RELEASES_NOW }
    return [DateTimeOffset]::Now.ToString("yyyy-MM-dd'T'HH:mm:sszzz", [Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-RlInstant {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $d = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse($Text, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeLocal, [ref]$d)) { return $d }
    return $null
}

function Format-RlDay {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    $d = ConvertTo-RlInstant $Text
    if ($null -eq $d) { return [string]$Text }
    return $d.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
}

function Write-RlText {
    # UTF-8 without BOM, LF line ends, written through a temporary file so a reader never sees half a file.
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $tmp = "$Path.tmp"
    [IO.File]::WriteAllText($tmp, $Text.Replace("`r`n", "`n"), $script:RlUtf8)
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Test-RlSchema {
    # RELEASE-LEDGER section 3: absent reads as "1", a higher minor reads as its major, a higher major is refused.
    param($Object, [Parameter(Mandatory)][string]$File)
    $s = [string](Get-RlProp $Object 'schema')
    if ([string]::IsNullOrWhiteSpace($s)) { return }
    if ($s -notmatch '^(\d+)(\.\d+)?$') { throw "release-ledger: $File carries schema '$s', which is not a version" }
    if ([int]$Matches[1] -gt $script:RlSchemaMajor) {
        throw "release-ledger: $File carries schema '$s'; this reader knows schema $($script:RlSchemaMajor).x - update the sza plugin"
    }
}

# ---- where a ledger is ----

function Get-RlFiles {
    param([Parameter(Mandatory)][string]$Dir)
    return [pscustomobject]@{
        Dir      = $Dir
        Channels = Join-Path $Dir 'channels.json'
        Builds   = Join-Path $Dir 'builds.json'
        History  = Join-Path $Dir 'history.jsonl'
        Render   = Join-Path $Dir 'RELEASES.md'
        Lock     = Join-Path $Dir '.release-ledger.lock'
    }
}

function Get-RlDefaultDir { return [string]$script:RlProfileDefaults.paths.releasesDir }

function Resolve-RlDirForRepo {
    # HARNESS-PROFILE rule 14: the repository's own paths.releasesDir, else the shipped default. The profile is
    # read as written, never through _profile.ps1 (one project per process there).
    param([Parameter(Mandatory)][string]$RepoRoot)
    $rel = Get-RlDefaultDir
    $profilePath = Join-Path $RepoRoot '.sza-profile.json'
    if (Test-Path -LiteralPath $profilePath -PathType Leaf) {
        try {
            $p = ConvertFrom-RlJson (Get-Content -LiteralPath $profilePath -Raw -Encoding utf8)
            $v = [string](Get-RlProp (Get-RlProp $p 'paths') 'releasesDir')
            if (-not [string]::IsNullOrWhiteSpace($v)) { $rel = $v }
        } catch {
            Write-Verbose "release-ledger: '$profilePath' does not parse; the default folder is used"
        }
    }
    if ([IO.Path]::IsPathRooted($rel)) { return [IO.Path]::GetFullPath($rel) }
    return [IO.Path]::GetFullPath((Join-Path $RepoRoot $rel))
}

function ConvertTo-RlRepoPath {
    # A path recorded in the ledger is repository-relative with forward slashes (rule 4); a file outside the
    # repository is recorded by its name alone, never by an absolute local path (rule 9).
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$Path)
    $full = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $RepoRoot $Path)) }
    $root = [IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if ($full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($root.Length).Replace('\', '/')
    }
    return [IO.Path]::GetFileName($full)
}

# ---- reading ----

function Read-RlChannels {
    # channels.json (rule 2). Returns exists, packages (ids), channels (normalized), errors. A kind this reader
    # does not know is kept as declared and handled as manual (rule 3).
    param([Parameter(Mandatory)][string]$Dir)
    $f = Get-RlFiles $Dir
    $errors = [System.Collections.Generic.List[string]]::new()
    $out = [ordered]@{ exists = $false; packages = @(); packageTitles = @{}; channels = @(); errors = $errors; raw = $null }
    if (-not (Test-Path -LiteralPath $f.Channels -PathType Leaf)) { return [pscustomobject]$out }
    $out.exists = $true
    try { $o = ConvertFrom-RlJson (Get-Content -LiteralPath $f.Channels -Raw -Encoding utf8) }
    catch { $errors.Add("channels.json does not parse: $($_.Exception.Message)"); return [pscustomobject]$out }
    Test-RlSchema $o 'channels.json'
    $out.raw = $o
    $ids = [System.Collections.Generic.List[string]]::new()
    foreach ($p in @(Get-RlProp $o 'packages')) {
        if ($null -eq $p) { continue }
        $id = [string](Get-RlProp $p 'id')
        if ($id -cnotmatch $script:RlIdPattern) { $errors.Add("package id '$id' does not match $($script:RlIdPattern)"); continue }
        if ($ids.Contains($id)) { $errors.Add("package id '$id' is declared twice"); continue }
        $ids.Add($id)
        $out.packageTitles[$id] = [string](Get-RlProp $p 'title')
    }
    $out.packages = $ids.ToArray()
    $keys = [System.Collections.Generic.List[string]]::new()
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($c in @(Get-RlProp $o 'channels')) {
        if ($null -eq $c) { continue }
        $key = [string](Get-RlProp $c 'key')
        $kind = [string](Get-RlProp $c 'channel')
        $pkg = [string](Get-RlProp $c 'package')
        if ($key -cnotmatch $script:RlIdPattern) { $errors.Add("channel key '$key' does not match $($script:RlIdPattern)"); continue }
        if ($keys.Contains($key)) { $errors.Add("channel key '$key' is declared twice"); continue }
        if ([string]::IsNullOrWhiteSpace($kind)) { $errors.Add("channel '$key' names no channel kind"); continue }
        if ([string]::IsNullOrWhiteSpace($pkg)) {
            if ($ids.Count -ne 1) { $errors.Add("channel '$key' names no package and the file declares $($ids.Count)"); continue }
            $pkg = $ids[0]
        } elseif (-not $ids.Contains($pkg)) {
            $errors.Add("channel '$key' names package '$pkg', which the file does not declare"); continue
        }
        $keys.Add($key)
        $effective = if ($script:RlKnownKinds -ccontains $kind) { $kind } else { 'manual' }
        $list.Add([pscustomobject]@{
                key = $key; channel = $kind; kind = $effective; package = $pkg
                title = [string](Get-RlProp $c 'title'); declared = $true; spec = $c
            })
    }
    $out.channels = $list.ToArray()
    return [pscustomobject]$out
}

function Read-RlBuilds {
    param([Parameter(Mandatory)][string]$Dir)
    $f = Get-RlFiles $Dir
    if (-not (Test-Path -LiteralPath $f.Builds -PathType Leaf)) { return [pscustomobject]@{ raw = $null; builds = @() } }
    $o = ConvertFrom-RlJson (Get-Content -LiteralPath $f.Builds -Raw -Encoding utf8)
    Test-RlSchema $o 'builds.json'
    $rows = [object[]]@(@(Get-RlProp $o 'builds') | Where-Object { $null -ne $_ })
    return [pscustomobject]@{ raw = $o; builds = $rows }
}

function Read-RlHistory {
    # history.jsonl (rule 5): blank lines ignored, a line that does not parse or lacks a required field is
    # reported by number and skipped, never repaired.
    param([Parameter(Mandatory)][string]$Dir)
    $f = Get-RlFiles $Dir
    $events = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $f.History -PathType Leaf) {
        $n = 0
        foreach ($line in @(Get-Content -LiteralPath $f.History -Encoding utf8)) {
            $n++
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $e = ConvertFrom-RlJson $line } catch { $warnings.Add("history.jsonl line ${n}: does not parse"); continue }
            $missing = @('at', 'key', 'package', 'version', 'state', 'source' | Where-Object { [string]::IsNullOrWhiteSpace([string](Get-RlProp $e $_)) })
            if ($missing.Count -gt 0) { $warnings.Add("history.jsonl line ${n}: lacks $($missing -join ', ')"); continue }
            $at = ConvertTo-RlInstant ([string]$e.at)
            if ($null -eq $at) { $warnings.Add("history.jsonl line ${n}: 'at' is not a date: $($e.at)"); continue }
            $events.Add([pscustomobject]@{ line = $n; at = $at; event = $e })
        }
    }
    return [pscustomobject]@{ events = $events.ToArray(); warnings = $warnings.ToArray() }
}

# ---- writing (one lock per ledger folder) ----

function Invoke-RlLocked {
    # The lock file is opened exclusively and deleted on close, so a crashed writer leaves nothing behind for git.
    param([Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][scriptblock]$Body, [int]$TimeoutSeconds = 15)
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
    $lockPath = (Get-RlFiles $Dir).Lock
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $fs = $null
    while ($null -eq $fs) {
        try {
            $fs = [IO.FileStream]::new($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None, 1, [IO.FileOptions]::DeleteOnClose)
        } catch {
            if ([DateTime]::UtcNow -gt $deadline) { throw "release-ledger: the ledger at '$Dir' stayed locked for $TimeoutSeconds s" }
            Start-Sleep -Milliseconds 100
        }
    }
    try { & $Body } finally { $fs.Dispose() }
}

function Set-RlBuild {
    # Rule 4: one row per package, flavor and kind; the new build replaces the old row of its triple (so a debug
    # build never hides the last release build of the same flavor), the rest keep every field they carry (rule 11),
    # and the array stays sorted by package, flavor, kind.
    param([Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][System.Collections.IDictionary]$Build)
    Invoke-RlLocked -Dir $Dir -Body {
        $read = Read-RlBuilds $Dir
        $root = $read.raw
        if ($null -eq $root) { $root = [pscustomobject][ordered]@{ schema = '1'; builds = @() } }
        $rows = [System.Collections.Generic.List[object]]::new()
        foreach ($b in $read.builds) {
            if ([string](Get-RlProp $b 'package') -ceq [string]$Build['package'] -and [string](Get-RlProp $b 'flavor') -ceq [string]$Build['flavor'] -and
                [string](Get-RlProp $b 'kind') -ceq [string]$Build['kind']) { continue }
            $rows.Add($b)
        }
        $rows.Add([pscustomobject]$Build)
        $sorted = [object[]]@($rows | Sort-Object -Property @{ Expression = { [string](Get-RlProp $_ 'package') } }, @{ Expression = { [string](Get-RlProp $_ 'flavor') } },
            @{ Expression = { [string](Get-RlProp $_ 'kind') } })
        $root | Add-Member -NotePropertyName builds -NotePropertyValue $sorted -Force
        Write-RlText -Path (Get-RlFiles $Dir).Builds -Text (($root | ConvertTo-Json -Depth 20) + "`n")
    }
}

function Add-RlEvents {
    # Rule 5: append-only. The file is never rewritten; a missing final newline is supplied before the append.
    param([Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Events)
    if ($Events.Count -eq 0) { return }
    Invoke-RlLocked -Dir $Dir -Body {
        $path = (Get-RlFiles $Dir).History
        $prefix = ''
        if ((Test-Path -LiteralPath $path -PathType Leaf) -and (Get-Item -LiteralPath $path).Length -gt 0) {
            $fs = [IO.File]::OpenRead($path)
            try { $null = $fs.Seek(-1, [IO.SeekOrigin]::End); if ($fs.ReadByte() -ne 10) { $prefix = "`n" } } finally { $fs.Dispose() }
        }
        $text = $prefix + (($Events | ForEach-Object { ([pscustomobject]$_ | ConvertTo-Json -Compress -Depth 10) }) -join "`n") + "`n"
        [IO.File]::AppendAllText($path, $text, $script:RlUtf8)
    }
}

function New-RlEvent {
    # One history row with the six required fields first and the optional ones only when they carry a value.
    param(
        [Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][string]$Package, [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$State, [Parameter(Mandatory)][string]$Source, [string]$At,
        [string]$Ref, [string]$Url, [string]$Note, [string]$Track, [object]$Rollout
    )
    $e = [ordered]@{ at = $(if ($At) { $At } else { Get-RlNow }); key = $Key; package = $Package; version = $Version; state = $State; source = $Source }
    if ($Ref) { $e.ref = $Ref }
    if ($Url) { $e.url = $Url }
    if ($Note) { $e.note = $Note }
    if ($Track) { $e.track = $Track }
    if ($null -ne $Rollout -and "$Rollout" -ne '') { $e.rollout = [double]$Rollout }
    return $e
}

# ---- the fold (rule 7) ----

function Test-RlNewer {
    # $A newer than $B: by instant, file order breaking a tie.
    param($A, $B)
    if ($null -eq $B) { return $true }
    if ($null -eq $A) { return $false }
    if ($A.at.UtcTicks -ne $B.at.UtcTicks) { return ($A.at.UtcTicks -gt $B.at.UtcTicks) }
    return ($A.line -gt $B.line)
}

function ConvertTo-RlView {
    param($Entry)
    if ($null -eq $Entry) { return $null }
    $e = $Entry.event
    $v = [ordered]@{ version = [string]$e.version; state = [string]$e.state; at = [string]$e.at; source = [string]$e.source }
    foreach ($k in 'ref', 'url', 'note', 'track', 'rollout') {
        $x = Get-RlProp $e $k
        if ($null -ne $x -and "$x" -ne '') { $v[$k] = $x }
    }
    return [pscustomobject]$v
}

function Get-RlChannelState {
    param([Parameter(Mandatory)]$Channel, [AllowEmptyCollection()][object[]]$Events = @())
    $mine = @($Events | Where-Object { [string]$_.event.key -ceq $Channel.key -and [string]$_.event.package -ceq $Channel.package })
    $ordered = @($mine | Sort-Object -Property @{ Expression = { $_.at.UtcTicks } }, @{ Expression = { $_.line } })
    $byVersion = [ordered]@{}
    foreach ($m in $ordered) { $byVersion[[string]$m.event.version] = $m }
    $live = $null
    foreach ($m in $byVersion.Values) { if ([string]$m.event.state -ceq 'live' -and (Test-RlNewer $m $live)) { $live = $m } }
    $flight = @($byVersion.Values | Where-Object { $script:RlInFlightStates -ccontains [string]$_.event.state -and (Test-RlNewer $_ $live) } |
            Sort-Object -Property @{ Expression = { $_.at.UtcTicks } }, @{ Expression = { $_.line } } -Descending)
    $last = if ($ordered.Count -gt 0) { $ordered[-1] } else { $null }
    $status = 'none'
    if ($flight.Count -gt 0) {
        $states = @($flight | ForEach-Object { [string]$_.event.state })
        foreach ($s in 'rejected', 'blocked', 'submitted', 'pending') { if ($states -ccontains $s) { $status = $s; break } }
    } elseif ($null -ne $live) { $status = 'live' }
    elseif ($null -ne $last) { $status = [string]$last.event.state }
    $versions = [ordered]@{}
    foreach ($k in $byVersion.Keys) { $versions[$k] = ConvertTo-RlView $byVersion[$k] }
    return [pscustomobject]@{
        key      = $Channel.key
        channel  = $Channel.channel
        kind     = $Channel.kind
        package  = $Channel.package
        title    = $Channel.title
        declared = [bool]$Channel.declared
        status   = $status
        live     = ConvertTo-RlView $live
        inFlight = [object[]]@($flight | ForEach-Object { ConvertTo-RlView $_ })
        last     = ConvertTo-RlView $last
        events   = $ordered.Count
        versions = $versions
    }
}

function ConvertTo-RlVersionCore {
    # The comparable core of a version string: no leading 'v', the first token only (a Play release name carries
    # the code after it), and for a dotted numeric version each part int-cast with trailing zero parts dropped -
    # so the MSIX remap 26.723.959.0 and the tag 26.0723.0959 compare equal.
    param([AllowNull()][AllowEmptyString()][string]$Version)
    $t = ([string]$Version).Trim()
    if ($t -match '^[vV](?=\d)') { $t = $t.Substring(1) }
    $t = ($t -split '[\s(]', 2)[0]
    if ($t -match '^\d+(\.\d+)*$') {
        $parts = [System.Collections.Generic.List[string]]::new()
        foreach ($p in $t.Split('.')) { $parts.Add(([System.Numerics.BigInteger]::Parse($p)).ToString()) }
        while ($parts.Count -gt 1 -and $parts[$parts.Count - 1] -eq '0') { $parts.RemoveAt($parts.Count - 1) }
        return ($parts -join '.')
    }
    return $t
}

function Test-RlVersionMatch {
    param([AllowNull()][AllowEmptyString()][string]$A, [AllowNull()][AllowEmptyString()][string]$B)
    if ([string]::IsNullOrWhiteSpace($A) -or [string]::IsNullOrWhiteSpace($B)) { return $false }
    return ((ConvertTo-RlVersionCore $A) -ceq (ConvertTo-RlVersionCore $B))
}

function Get-RlUnpublished {
    # A release build whose version no channel of its package carries, live or in flight. A package with no
    # channel at all ships nowhere by declaration and is not reported.
    param([AllowEmptyCollection()][object[]]$Builds = @(), [AllowEmptyCollection()][object[]]$States = @())
    $nowText = Get-RlNow
    $now = ConvertTo-RlInstant $nowText
    foreach ($b in $Builds) {
        if ([string](Get-RlProp $b 'kind') -cne 'release') { continue }
        $pkg = [string](Get-RlProp $b 'package')
        $ver = [string](Get-RlProp $b 'version')
        $mine = @($States | Where-Object { $_.package -ceq $pkg -and $_.status -cne 'n/a' })
        if ($mine.Count -eq 0) { continue }
        $carried = $false
        foreach ($s in $mine) {
            if ($null -ne $s.live -and (Test-RlVersionMatch $s.live.version $ver)) { $carried = $true; break }
            foreach ($f in $s.inFlight) { if (Test-RlVersionMatch $f.version $ver) { $carried = $true; break } }
            if ($carried) { break }
        }
        if ($carried) { continue }
        $built = ConvertTo-RlInstant ([string](Get-RlProp $b 'builtAt'))
        $days = if ($null -ne $built -and $null -ne $now) { [int][Math]::Floor(($now - $built).TotalDays) } else { $null }
        [pscustomobject]@{ package = $pkg; flavor = [string](Get-RlProp $b 'flavor'); version = $ver; builtAt = [string](Get-RlProp $b 'builtAt'); days = $days }
    }
}

function Get-RlClosedSinceBuild {
    # The tickets at -Status whose ledger row was written in or after the minute of the newest build of builds.json
    # (any package, flavor or kind). `updated` is a row's last write and carries minutes only, so the build instant is
    # cut to its minute, a row written again after the build is counted, and so is a row whose `updated` cannot be
    # read: the figure errs high, never low. No readable builtAt = no figure (sinceBuild $null).
    param(
        [AllowEmptyCollection()][object[]]$Builds = @(),
        [AllowEmptyCollection()][object[]]$Tickets = @(),
        [string]$Status = 'Implemented'
    )
    $last = $null
    $lastText = ''
    foreach ($b in $Builds) {
        $text = [string](Get-RlProp $b 'builtAt')
        $t = ConvertTo-RlInstant $text
        if ($null -ne $t -and ($null -eq $last -or $t -gt $last)) { $last = $t; $lastText = $text }
    }
    $floor = if ($null -ne $last) { $last.AddTicks(-($last.Ticks % [TimeSpan]::TicksPerMinute)) } else { $null }
    $atStatus = 0
    $since = 0
    foreach ($row in $Tickets) {
        if ([string](Get-RlProp $row 'status') -cne $Status) { continue }
        $atStatus++
        if ($null -eq $floor) { continue }
        $u = ConvertTo-RlInstant ([string](Get-RlProp $row 'updated'))
        if ($null -eq $u -or $u -ge $floor) { $since++ }
    }
    return [pscustomobject]@{ lastBuiltAt = $lastText; atStatus = $atStatus; sinceBuild = $(if ($null -ne $floor) { $since } else { $null }) }
}

function Get-RlSnapshot {
    # Everything a reader shows, from the three source files. History rows that name a key channels.json does
    # not declare are kept under that key as a manual channel: the history is never dropped for a config change.
    param([Parameter(Mandatory)][string]$Dir)
    $exists = Test-Path -LiteralPath $Dir -PathType Container
    $ch = Read-RlChannels $Dir
    $bu = Read-RlBuilds $Dir
    $hi = Read-RlHistory $Dir
    $channels = [System.Collections.Generic.List[object]]::new()
    foreach ($c in $ch.channels) { $channels.Add($c) }
    foreach ($e in $hi.events) {
        $k = [string]$e.event.key
        $p = [string]$e.event.package
        if (@($channels | Where-Object { $_.key -ceq $k -and $_.package -ceq $p }).Count -gt 0) { continue }
        $channels.Add([pscustomobject]@{ key = $k; channel = 'manual'; kind = 'manual'; package = $p; title = 'not declared in channels.json'; declared = $false; spec = $null })
    }
    $states = [object[]]@($channels | ForEach-Object { Get-RlChannelState -Channel $_ -Events $hi.events })
    $builds = [object[]]@($bu.builds)
    $warnings = [System.Collections.Generic.List[string]]::new()
    foreach ($w in $ch.errors) { $warnings.Add($w) }
    foreach ($w in $hi.warnings) { $warnings.Add($w) }
    return [pscustomobject]@{
        dir              = $Dir
        exists           = $exists
        channelsDeclared = $ch.exists
        packages         = [object[]]$ch.packages
        packageTitles    = $ch.packageTitles
        builds           = $builds
        channels         = $states
        unpublished      = [object[]]@(Get-RlUnpublished -Builds $builds -States $states)
        events           = $hi.events.Count
        warnings         = $warnings.ToArray()
    }
}

# ---- the render (rule 10) ----

function Format-RlCell {
    param([AllowNull()]$Value)
    if ($null -eq $Value -or "$Value" -eq '') { return '-' }
    return ("$Value" -replace '\r?\n', ' ' -replace '\|', '\|')
}

function Format-RlRef {
    param($View)
    if ($null -eq $View) { return '-' }
    $ref = [string](Get-RlProp $View 'ref')
    $url = [string](Get-RlProp $View 'url')
    if ($url -and $ref) { return "[$(Format-RlCell $ref)]($url)" }
    if ($url) { return "[link]($url)" }
    return (Format-RlCell $ref)
}

function Format-RlMarkdown {
    param([Parameter(Mandatory)]$Snapshot, [AllowEmptyCollection()][object[]]$Events = @())
    $sb = [System.Collections.Generic.List[string]]::new()
    $sb.Add('# Releases')
    $sb.Add('')
    $sb.Add('<!-- Rendered by the sza release-ledger from channels.json, builds.json and history.jsonl (RELEASE-LEDGER rule 10). Do not edit: the next write replaces this file. -->')
    $sb.Add('')
    $sb.Add('What each package was built as last, what each channel carries, and every publication before it.')
    $sb.Add('')
    $sb.Add('## Channels')
    $sb.Add('')
    if ($Snapshot.channels.Count -eq 0) {
        $sb.Add('No channel is declared yet (`channels.json`).')
    } else {
        $sb.Add('| Package | Channel | Kind | Live | Since | In flight | Ref |')
        $sb.Add('| --- | --- | --- | --- | --- | --- | --- |')
        foreach ($s in $Snapshot.channels) {
            $flight = if ($s.inFlight.Count -gt 0) { ($s.inFlight | ForEach-Object { "$($_.version) $($_.state) ($(Format-RlDay $_.at))" }) -join '; ' } else { '-' }
            $name = if ($s.title) { "$($s.key) ($($s.title))" } else { $s.key }
            $liveVer = if ($null -ne $s.live) { $s.live.version } else { $null }
            $liveAt = if ($null -ne $s.live) { Format-RlDay $s.live.at } else { $null }
            $refView = if ($s.inFlight.Count -gt 0) { $s.inFlight[0] } else { $s.live }
            $sb.Add("| $(Format-RlCell $s.package) | $(Format-RlCell $name) | $(Format-RlCell $s.channel) | $(Format-RlCell $liveVer) | $(Format-RlCell $liveAt) | $(Format-RlCell $flight) | $(Format-RlRef $refView) |")
        }
    }
    $sb.Add('')
    $sb.Add('## Last builds')
    $sb.Add('')
    if ($Snapshot.builds.Count -eq 0) {
        $sb.Add('No build is recorded yet.')
    } else {
        $sb.Add('| Package | Flavor | Kind | Version | Built | Artifact |')
        $sb.Add('| --- | --- | --- | --- | --- | --- |')
        foreach ($b in $Snapshot.builds) {
            $sb.Add("| $(Format-RlCell (Get-RlProp $b 'package')) | $(Format-RlCell (Get-RlProp $b 'flavor')) | $(Format-RlCell (Get-RlProp $b 'kind')) | $(Format-RlCell (Get-RlProp $b 'version')) | $(Format-RlCell ([string](Get-RlProp $b 'builtAt')).Replace('T', ' ')) | $(Format-RlCell (Get-RlProp $b 'artifact')) |")
        }
    }
    if ($Snapshot.unpublished.Count -gt 0) {
        $sb.Add('')
        $sb.Add('## Built, not published')
        $sb.Add('')
        $sb.Add('| Package | Flavor | Version | Built | Days |')
        $sb.Add('| --- | --- | --- | --- | --- |')
        foreach ($u in $Snapshot.unpublished) {
            $sb.Add("| $(Format-RlCell $u.package) | $(Format-RlCell $u.flavor) | $(Format-RlCell $u.version) | $(Format-RlCell (Format-RlDay $u.builtAt)) | $(Format-RlCell $u.days) |")
        }
    }
    $sb.Add('')
    $sb.Add('## History')
    $sb.Add('')
    if ($Events.Count -eq 0) {
        $sb.Add('No publication is recorded yet.')
    } else {
        $sb.Add('| When | Package | Channel | Version | State | Source | Ref | Note |')
        $sb.Add('| --- | --- | --- | --- | --- | --- | --- | --- |')
        $newest = @($Events | Sort-Object -Property @{ Expression = { $_.at.UtcTicks } }, @{ Expression = { $_.line } } -Descending)
        foreach ($e in $newest) {
            $x = $e.event
            $note = [string](Get-RlProp $x 'note')
            $track = [string](Get-RlProp $x 'track')
            $rollout = Get-RlProp $x 'rollout'
            if ($track) { $note = "track $track" + $(if ($null -ne $rollout) { ", rollout $rollout" } else { '' }) + $(if ($note) { "; $note" } else { '' }) }
            $when = ([string]$x.at).Replace('T', ' ')
            $sb.Add("| $(Format-RlCell $when) | $(Format-RlCell $x.package) | $(Format-RlCell $x.key) | $(Format-RlCell $x.version) | $(Format-RlCell $x.state) | $(Format-RlCell $x.source) | $(Format-RlRef $x) | $(Format-RlCell $note) |")
        }
    }
    if ($Snapshot.warnings.Count -gt 0) {
        $sb.Add('')
        $sb.Add('## Ledger warnings')
        $sb.Add('')
        foreach ($w in $Snapshot.warnings) { $sb.Add("- $(Format-RlCell $w)") }
    }
    $sb.Add('')
    return ($sb -join "`n")
}

function Write-RlRender {
    # Deterministic: no "rendered at" stamp, so a write that changes nothing leaves RELEASES.md byte-identical.
    param([Parameter(Mandatory)][string]$Dir)
    $snap = Get-RlSnapshot $Dir
    $hist = Read-RlHistory $Dir
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
    $text = Format-RlMarkdown -Snapshot $snap -Events $hist.events
    $path = (Get-RlFiles $Dir).Render
    if ((Test-Path -LiteralPath $path -PathType Leaf) -and ([IO.File]::ReadAllText($path, $script:RlUtf8) -ceq $text)) { return $false }
    Write-RlText -Path $path -Text $text
    return $true
}
