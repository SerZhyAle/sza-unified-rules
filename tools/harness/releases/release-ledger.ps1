#requires -Version 7.0
<#
.SYNOPSIS
    The release ledger of one repository: last builds, publications per channel, their history (RELEASE-LEDGER 0.1).

.DESCRIPTION
    The only writer of the ledger folder (HARNESS-PROFILE paths.releasesDir, default docs/releases): channels.json is
    written once by `init` and then by hand, builds.json by `build`, history.jsonl by `publish`, `confirm`, `probe`
    and `import`, and RELEASES.md is re-rendered after every write. It never publishes anything: `probe` and `import`
    only read the channels (a public page, a public API, `gh`, `msstore submission get`), and nothing here uploads,
    submits, merges or tags.

    release-ledger init
        write a starter channels.json from the stamp's channel list (never overwrites one); fill its ids by hand
    release-ledger build -Package <id> -Kind release|test|debug -Version <v> [-Flavor <f>] [-Artifact <path>] [-Note <t>]
        record the last build of a package and flavor (replaces the previous one of that pair); a build script calls
        it after a successful build and ignores a non-zero exit (the ledger never fails a build)
    release-ledger publish -Key <channel key> -Version <v> -State <state> [-Ref <r>] [-Url <u>] [-Note <t>]
                           [-Track <t>] [-Rollout <0..1>] [-Source release|manual] [-At <iso time>]
        append a publication event - the release and store-publish flows call it at each channel step
    release-ledger confirm ...  the same as publish with -Source manual: a hand confirmation of a channel that has no
                                probe (a forum post, a VR store) or that the probe cannot see
    release-ledger show [-Key <k>] [-Json]
        the current state: last builds, the live version and the in-flight versions per channel, release builds no
        channel carries yet, and the ledger's warnings
    release-ledger history [-Key <k>] [-Package <p>] [-Last <n>] [-Json]
        every publication event, newest first
    release-ledger render
        rewrite RELEASES.md from the three source files
    release-ledger probe [-Key <k>] [-DryRun]
        read each channel and append an event only where what it shows differs from the ledger; a channel the probe
        cannot see is reported as unverified with the reason and writes nothing
    release-ledger import [-Key <k>] [-DryRun]
        backfill: every version the automatic sources list (GitHub Releases, winget-pkgs, the stores' current live
        version, the Marketplace's versions), at the channel's own time where it gives one; a version already
        recorded in the same state is skipped

    -RepoRoot <dir> works on another repository's ledger (its own profile decides the folder); without it the project
    root is resolved as every harness script does (_profile.ps1).

    States: pending, submitted, live, blocked, rejected, withdrawn, n/a. Build kinds: release, test, debug.
    Probe kinds (channels.json `channel`): github, winget, msstore, play, chrome, edge, vscode, url, manual; any
    other kind is kept and handled as manual. Credentials: the Play probe reads the service account key file named by
    SZA_PLAY_SERVICE_ACCOUNT_JSON (outside every repository); the others use the tools' own sign-in (gh, msstore) or
    public endpoints.

    Exit codes: 0 done (a probe that could not see a channel still exits 0 and says so); 1 the ledger could not be
    read (a schema this reader does not know, a channels.json error) or written; 2 invalid invocation.
#>
param(
    [Parameter(Position = 0)][string]$Verb,
    [string]$RepoRoot,
    [string]$Package,
    [string]$Flavor,
    [string]$Kind,
    [string]$Version,
    [string]$Artifact,
    [string]$Key,
    [string]$State,
    [string]$Ref,
    [string]$Url,
    [string]$Note,
    [string]$Track,
    [string]$Rollout,
    [string]$Source,
    [string]$At,
    [int]$Last = 0,
    [switch]$Json,
    [switch]$DryRun,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_lib.ps1')
. (Join-Path $PSScriptRoot '_probes.ps1')

function Stop-Rl([int]$Code, [string]$Message) {
    [Console]::Error.WriteLine("release-ledger: $Message")
    exit $Code
}

if ($Help -or [string]::IsNullOrWhiteSpace($Verb)) {
    Get-Help $PSCommandPath -Detailed | Out-String | Write-Output
    exit $(if ($Help) { 0 } else { 2 })
}
$verbs = @('init', 'build', 'publish', 'confirm', 'show', 'history', 'render', 'probe', 'import')
if ($verbs -cnotcontains $Verb) { Stop-Rl 2 "unknown verb '$Verb' (one of: $($verbs -join ', '))" }

# ---- where ----

if ($RepoRoot) {
    if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) { Stop-Rl 2 "-RepoRoot '$RepoRoot' is not a directory" }
    $root = (Resolve-Path -LiteralPath $RepoRoot).Path
    $dir = Resolve-RlDirForRepo $root
} else {
    . (Join-Path $PSScriptRoot '..\_profile.ps1')
    try { $root = Get-SzaProjectRoot; $dir = Get-SzaPath 'releasesDir' } catch { Stop-Rl 2 $_.Exception.Message }
}
$relDir = ConvertTo-RlRepoPath -RepoRoot $root -Path $dir

function Get-RlChannelsOrStop {
    try { $ch = Read-RlChannels $dir } catch { Stop-Rl 1 $_.Exception.Message }
    if ($ch.errors.Count -gt 0) { Stop-Rl 1 ("$relDir/channels.json: " + ($ch.errors -join '; ')) }
    return $ch
}

function Write-RlRenderOrStop {
    try { $null = Write-RlRender $dir } catch { Stop-Rl 1 "RELEASES.md was not rendered: $($_.Exception.Message)" }
}

function Format-RlStateLine($S) {
    $parts = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $S.live) { $parts.Add("live $($S.live.version) ($(Format-RlDay $S.live.at))") }
    foreach ($f in $S.inFlight) {
        $parts.Add("$($f.state) $($f.version) ($(Format-RlDay $f.at))$(if (Get-RlProp $f 'ref') { ' ' + $f.ref })")
    }
    if ($parts.Count -eq 0) { $parts.Add($(if ($S.status -ne 'none') { $S.status } else { 'nothing recorded' })) }
    return ($parts -join '; ')
}

function ConvertTo-RlPublicState($S) {
    # The JSON shape pq and PQShell read: the derived state without the per-version map.
    return [pscustomobject]@{
        key = $S.key; channel = $S.channel; kind = $S.kind; package = $S.package; title = $S.title; declared = $S.declared
        status = $S.status; live = $S.live; inFlight = [object[]]$S.inFlight; last = $S.last; events = $S.events
    }
}

# ---- init ----

function Get-RlStampChannels {
    $stampPath = Join-Path $root '.sza-canon.json'
    if (-not (Test-Path -LiteralPath $stampPath -PathType Leaf)) { return @() }
    try { $s = ConvertFrom-RlJson (Get-Content -LiteralPath $stampPath -Raw -Encoding utf8) } catch { return @() }
    return [string[]]@(@(Get-RlProp $s 'channels') | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant() })
}

function Find-RlWingetId {
    foreach ($folder in 'winget', 'publishing/winget', 'packaging/winget') {
        $p = Join-Path $root $folder
        if (-not (Test-Path -LiteralPath $p -PathType Container)) { continue }
        foreach ($f in Get-ChildItem -LiteralPath $p -Recurse -File -Filter '*.yaml' -ErrorAction SilentlyContinue | Select-Object -First 40) {
            $m = Select-String -LiteralPath $f.FullName -Pattern '^\s*PackageIdentifier:\s*([\w.\-]+)' | Select-Object -First 1
            if ($m) { return $m.Matches[0].Groups[1].Value }
        }
    }
    return ''
}

if ($Verb -ceq 'init') {
    $files = Get-RlFiles $dir
    if (Test-Path -LiteralPath $files.Channels -PathType Leaf) {
        Write-Output "release-ledger: $relDir/channels.json exists and is left as it is"
        exit 0
    }
    $kindOf = @{ github = 'github'; winget = 'winget'; msstore = 'msstore'; store = 'msstore'; play = 'play'; chrome = 'chrome'; edge = 'edge'; vscode = 'vscode' }
    $channels = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.List[string]]::new()
    foreach ($c in (Get-RlStampChannels)) {
        $keyName = ($c -replace '[^a-z0-9-]', '-').Trim('-')
        if (-not $keyName -or $seen.Contains($keyName)) { continue }
        $seen.Add($keyName)
        $k = if ($kindOf.ContainsKey($c)) { $kindOf[$c] } else { 'manual' }
        $entry = [ordered]@{ key = $keyName; channel = $k; package = 'app' }
        switch ($k) {
            'github' { $r = Get-RlGithubRepoFromRemote $root; $entry.repo = $(if ($r) { $r } else { '' }) }
            'winget' { $entry.id = Find-RlWingetId }
            'msstore' { $entry.storeId = '' }
            'play' { $entry.id = ''; $entry.track = 'production' }
            'chrome' { $entry.id = '' }
            'edge' { $entry.id = '' }
            'vscode' { $entry.id = '' }
            default { $entry.title = $c }
        }
        $channels.Add([pscustomobject]$entry)
    }
    if ($channels.Count -eq 0) {
        $r = Get-RlGithubRepoFromRemote $root
        if ($r) { $channels.Add([pscustomobject][ordered]@{ key = 'github'; channel = 'github'; package = 'app'; repo = $r }) }
    }
    $doc = [pscustomobject][ordered]@{
        schema   = '1'
        packages = @([pscustomobject][ordered]@{ id = 'app'; title = (Split-Path -Leaf $root) })
        channels = [object[]]$channels.ToArray()
    }
    if ($DryRun) { $doc | ConvertTo-Json -Depth 10; exit 0 }
    try {
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Write-RlText -Path $files.Channels -Text (($doc | ConvertTo-Json -Depth 10) + "`n")
    } catch { Stop-Rl 1 "channels.json was not written: $($_.Exception.Message)" }
    Write-RlRenderOrStop
    Write-Output "release-ledger: wrote $relDir/channels.json with $($channels.Count) channel(s) from the stamp; fill the empty ids, rename package 'app' if the repository ships more than one package"
    foreach ($c in $channels) { Write-Output ("  {0,-10} {1}" -f $c.key, $c.channel) }
    exit 0
}

# ---- build ----

if ($Verb -ceq 'build') {
    if ($Package -cnotmatch $script:RlIdPattern) { Stop-Rl 2 "-Package '$Package' does not match $($script:RlIdPattern)" }
    if ($script:RlBuildKinds -cnotcontains $Kind) { Stop-Rl 2 "-Kind must be one of: $($script:RlBuildKinds -join ', ')" }
    if ([string]::IsNullOrWhiteSpace($Version)) { Stop-Rl 2 '-Version is required' }
    if ([string]::IsNullOrWhiteSpace($Flavor)) { $Flavor = 'default' }
    try { $ch = Read-RlChannels $dir } catch { Stop-Rl 1 $_.Exception.Message }
    if ($ch.exists -and $ch.packages.Count -gt 0 -and $ch.packages -cnotcontains $Package) {
        Stop-Rl 2 "package '$Package' is not declared in $relDir/channels.json (declared: $($ch.packages -join ', '))"
    }
    $build = [ordered]@{ package = $Package; flavor = $Flavor; kind = $Kind; version = $Version.Trim(); builtAt = (Get-RlNow) }
    if ($Artifact) {
        $full = if ([IO.Path]::IsPathRooted($Artifact)) { $Artifact } else { Join-Path $root $Artifact }
        $build.artifact = ConvertTo-RlRepoPath -RepoRoot $root -Path $Artifact
        if (Test-Path -LiteralPath $full -PathType Leaf) { $build.sha256 = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    if ($Note) { $build.note = $Note }
    try { Set-RlBuild -Dir $dir -Build $build } catch { Stop-Rl 1 "builds.json was not written: $($_.Exception.Message)" }
    Write-RlRenderOrStop
    Write-Output "release-ledger: build $Package/$Flavor $Kind $($build.version) recorded in $relDir"
    exit 0
}

# ---- publish / confirm ----

if ($Verb -ceq 'publish' -or $Verb -ceq 'confirm') {
    if ([string]::IsNullOrWhiteSpace($Key)) { Stop-Rl 2 '-Key is required (a channel key of channels.json)' }
    if ([string]::IsNullOrWhiteSpace($Version)) { Stop-Rl 2 '-Version is required' }
    if ($script:RlStates -cnotcontains $State) { Stop-Rl 2 "-State must be one of: $($script:RlStates -join ', ')" }
    if (-not $Source) { $Source = $(if ($Verb -ceq 'confirm') { 'manual' } else { 'release' }) }
    if (@('release', 'manual') -cnotcontains $Source) { Stop-Rl 2 '-Source must be release or manual (probe and import are written by their own verbs)' }
    if ($At -and $null -eq (ConvertTo-RlInstant $At)) { Stop-Rl 2 "-At '$At' is not an ISO 8601 time" }
    $roll = $null
    if ($Rollout) {
        $d = 0.0
        if (-not [double]::TryParse($Rollout, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d) -or $d -lt 0 -or $d -gt 1) { Stop-Rl 2 '-Rollout must be a fraction from 0 to 1' }
        $roll = $d
    }
    $ch = Get-RlChannelsOrStop
    if (-not $ch.exists) { Stop-Rl 2 "$relDir/channels.json does not exist - run 'release-ledger init' first" }
    $c = @($ch.channels | Where-Object { $_.key -ceq $Key }) | Select-Object -First 1
    if ($null -eq $c) { Stop-Rl 2 "channel key '$Key' is not declared in $relDir/channels.json (declared: $(($ch.channels | ForEach-Object key) -join ', '))" }
    if ($Package -and $Package -cne $c.package) { Stop-Rl 2 "channel '$Key' ships package '$($c.package)', not '$Package'" }
    $e = New-RlEvent -Key $Key -Package $c.package -Version $Version.Trim() -State $State -Source $Source -At $At -Ref $Ref -Url $Url -Note $Note -Track $Track -Rollout $roll
    try { Add-RlEvents -Dir $dir -Events @($e) } catch { Stop-Rl 1 "history.jsonl was not written: $($_.Exception.Message)" }
    Write-RlRenderOrStop
    Write-Output "release-ledger: $Key $($c.package) $($e.version) $State ($Source) recorded in $relDir"
    exit 0
}

# ---- reading verbs ----

try { $snap = Get-RlSnapshot $dir } catch { Stop-Rl 1 $_.Exception.Message }

if ($Verb -ceq 'render') {
    try { $changed = Write-RlRender $dir } catch { Stop-Rl 1 "RELEASES.md was not rendered: $($_.Exception.Message)" }
    Write-Output "release-ledger: $relDir/RELEASES.md $(if ($changed) { 'rendered' } else { 'unchanged' })"
    exit 0
}

if ($Verb -ceq 'show') {
    $states = @($snap.channels | Where-Object { -not $Key -or $_.key -ceq $Key })
    if ($Json) {
        [pscustomobject]@{
            dir = $relDir; exists = $snap.exists; channelsDeclared = $snap.channelsDeclared; packages = $snap.packages
            builds = $snap.builds; channels = [object[]]@($states | ForEach-Object { ConvertTo-RlPublicState $_ })
            unpublished = $snap.unpublished; events = $snap.events; warnings = $snap.warnings
        } | ConvertTo-Json -Depth 12
        exit $(if ($snap.warnings.Count -gt 0 -and -not $snap.channelsDeclared) { 1 } else { 0 })
    }
    if (-not $snap.exists) { Write-Output "release-ledger: no ledger at $relDir (run 'release-ledger init')"; exit 0 }
    Write-Output "release ledger: $relDir ($($snap.channels.Count) channel(s), $($snap.events) event(s))"
    Write-Output 'builds:'
    if ($snap.builds.Count -eq 0) { Write-Output '  none recorded' }
    foreach ($b in $snap.builds) {
        Write-Output ("  {0,-24} {1,-8} {2,-20} {3}" -f "$(Get-RlProp $b 'package')/$(Get-RlProp $b 'flavor')", (Get-RlProp $b 'kind'), (Get-RlProp $b 'version'), ([string](Get-RlProp $b 'builtAt')).Replace('T', ' '))
    }
    Write-Output 'channels:'
    if ($states.Count -eq 0) { Write-Output '  none declared' }
    foreach ($s in $states) { Write-Output ("  {0,-14} {1,-8} {2,-10} {3}" -f $s.key, $s.channel, $s.package, (Format-RlStateLine $s)) }
    if ($snap.unpublished.Count -gt 0) {
        Write-Output 'built, not published:'
        foreach ($u in $snap.unpublished) { Write-Output ("  {0}/{1} {2} built {3}$(if ($null -ne $u.days) { ', ' + $u.days + ' day(s) ago' })" -f $u.package, $u.flavor, $u.version, (Format-RlDay $u.builtAt)) }
    }
    foreach ($w in $snap.warnings) { Write-Output "warning: $w" }
    exit 0
}

if ($Verb -ceq 'history') {
    $hist = (Read-RlHistory $dir).events
    $rows = @($hist | Where-Object { (-not $Key -or [string]$_.event.key -ceq $Key) -and (-not $Package -or [string]$_.event.package -ceq $Package) } |
            Sort-Object -Property @{ Expression = { $_.at.UtcTicks } }, @{ Expression = { $_.line } } -Descending)
    if ($Last -gt 0) { $rows = @($rows | Select-Object -First $Last) }
    if ($Json) { ConvertTo-Json -InputObject ([object[]]@($rows | ForEach-Object { $_.event })) -Depth 8; exit 0 }
    if ($rows.Count -eq 0) { Write-Output 'release-ledger: no publication recorded'; exit 0 }
    foreach ($r in $rows) {
        $x = $r.event
        $tail = @((Get-RlProp $x 'ref'), (Get-RlProp $x 'track'), (Get-RlProp $x 'note')) | Where-Object { $_ }
        Write-Output ("{0}  {1,-14} {2,-10} {3,-22} {4,-10} {5,-7} {6}" -f ([string]$x.at).Replace('T', ' '), $x.key, $x.package, $x.version, $x.state, $x.source, ($tail -join ' | '))
    }
    exit 0
}

# ---- probe / import ----

$ch = Get-RlChannelsOrStop
if (-not $ch.exists) { Stop-Rl 2 "$relDir/channels.json does not exist - run 'release-ledger init' first" }
$targets = @($ch.channels | Where-Object { -not $Key -or $_.key -ceq $Key })
if ($Key -and $targets.Count -eq 0) { Stop-Rl 2 "channel key '$Key' is not declared in $relDir/channels.json" }
$isImport = ($Verb -ceq 'import')
$sourceName = if ($isImport) { 'import' } else { 'probe' }
$pending = [System.Collections.Generic.List[object]]::new()
$now = Get-RlNow

foreach ($c in $targets) {
    $chState = @($snap.channels | Where-Object { $_.key -ceq $c.key -and $_.package -ceq $c.package }) | Select-Object -First 1
    $known = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $chState) { foreach ($v in $chState.versions.Keys) { $known.Add([string]$v) } }
    foreach ($b in $snap.builds) { if ([string](Get-RlProp $b 'package') -ceq $c.package -and -not $known.Contains([string](Get-RlProp $b 'version'))) { $known.Add([string](Get-RlProp $b 'version')) } }
    $res = Invoke-RlProbe -Channel $c -RepoRoot $root -Candidates ([string[]]@($known | Select-Object -Last 20)) -All:$isImport
    if (-not $res.ok) { Write-Output ("unverified  {0,-14} {1}" -f $c.key, $res.reason); continue }
    if ($res.observed.Count -eq 0) { Write-Output ("seen        {0,-14} nothing published$(if ($res.reason) { ' - ' + $res.reason })" -f $c.key); continue }
    foreach ($o in $res.observed) {
        # The ledger's own spelling of a version wins over the channel's (26.1117.1450 recorded, 26.1117.1450.0 in
        # the Store): the observation is matched loosely and written under the recorded string.
        $recordedKey = $null
        if ($null -ne $chState) {
            if ($chState.versions.Contains([string]$o.version)) { $recordedKey = [string]$o.version }
            else { foreach ($k in $chState.versions.Keys) { if (Test-RlVersionMatch $k $o.version) { $recordedKey = [string]$k; break } } }
        }
        $ver = if ($recordedKey) { $recordedKey } else { [string]$o.version }
        $cur = if ($recordedKey) { $chState.versions[$recordedKey] } else { $null }
        $same = $false
        if ($null -ne $cur -and [string]$cur.state -ceq [string]$o.state) {
            $curTrack = [string](Get-RlProp $cur 'track'); $curRoll = [string](Get-RlProp $cur 'rollout')
            $same = ($curTrack -ceq [string]$o.track -or -not $o.track) -and ($curRoll -ceq [string]$o.rollout -or "$($o.rollout)" -eq '')
        }
        if ($isImport -and $null -ne $chState) {
            # import never repeats a (version, state) the history already holds, whatever came after it
            $hist = @((Read-RlHistory $dir).events | Where-Object { [string]$_.event.key -ceq $c.key -and (Test-RlVersionMatch ([string]$_.event.version) $ver) -and [string]$_.event.state -ceq [string]$o.state })
            if ($hist.Count -gt 0) { $same = $true }
        }
        if ($same) { Write-Output ("same        {0,-14} {1} {2}" -f $c.key, $ver, $o.state); continue }
        $note = [string]$o.note
        if ($ver -cne [string]$o.version) { $note = (@("channel shows $($o.version)", $note) | Where-Object { $_ }) -join '; ' }
        $atText = if ($isImport -and $o.at -and $null -ne (ConvertTo-RlInstant $o.at)) { [string]$o.at } else { $now }
        $pending.Add((New-RlEvent -Key $c.key -Package $c.package -Version $ver -State ([string]$o.state) -Source $sourceName -At $atText `
                    -Ref ([string]$o.ref) -Url ([string]$o.url) -Note $note -Track ([string]$o.track) -Rollout $o.rollout))
        Write-Output ("{0} {1,-14} {2} {3}" -f $(if ($DryRun) { 'would record' } else { 'recorded   ' }), $c.key, $ver, $o.state)
    }
}

if ($DryRun -or $pending.Count -eq 0) {
    Write-Output "release-ledger: $sourceName $(if ($DryRun) { 'dry run, ' })$($pending.Count) new event(s)$(if ($DryRun) { ', nothing written' })"
    exit 0
}
try { Add-RlEvents -Dir $dir -Events $pending.ToArray() } catch { Stop-Rl 1 "history.jsonl was not written: $($_.Exception.Message)" }
Write-RlRenderOrStop
Write-Output "release-ledger: $sourceName recorded $($pending.Count) event(s) in $relDir"
exit 0
