#requires -Version 7.0

<#
.SYNOPSIS
    Read-only list of the commands every registered product offers to a program that is not the user's hands -
    the discovery half of APP-COMMANDS (rule 20), walked over the portfolio registry.

.DESCRIPTION
    A product that adopted APP-COMMANDS keeps one manifest per program that stays running (item R.1 of 0.2):
    docs/cli-commands.json in its repository for the main program, docs/cli-commands.<program>.json for each other
    (<program> a short lower-case name, `share-manager`), and prints the same object with `commands --json`. This
    script reads only those files, in each registered repository, and prints the commands each holds: product, verb,
    summary, risk class and cold start. It reads nothing else of a repository (no ledger, no profile, no stamp, no
    source) and writes nothing. A file whose middle part is not such a name is not a manifest and is skipped.

    It tells four states apart, one line each per manifest, in registry rank order (rank, then array order; within
    a repository the main manifest first, then the others by name). The label <key> is the repository key, and
    <key>/<program> for a manifest of another program:
        OK       <key>  <product>  cliVersion=<v>  <n> command(s)    the manifest parses; its commands follow
        NONE     <key>                                              the repository has no manifest at all
        INVALID  <key>  <reason>                                    the file exists and does not parse: not JSON,
                                                                    not an object, schemaVersion missing or not 1,
                                                                    no commands array, an entry without a name, or
                                                                    larger than 1 MiB. Nothing of it is trusted, so
                                                                    none of its commands are listed.
        MISSING  <key>  <path>                                      the registered folder is not there
    An OK product's command lines are indented under it:
            <verb>  risk=<class>  coldStart=<mode>  <summary>
    A risk or coldStart the manifest does not state prints as `unknown` - which is never `safe`, so a caller that
    needs the person's setting for every class but `safe` (APP-COMMANDS rule 13) errs the cautious way.
    A verb is listed by its canonical name; aliases and the other members are in the manifest itself.
    The result line is last:
        app-commands: <n> command(s) in <m> product(s); none <a>, invalid <b>, missing <c>

    Scope: every repository of the portfolio registry, held or not (the registry is repos.json under
    SZA_PORTFOLIO_ROOT or %USERPROFILE%\.sza\portfolio). -Project names one registered key, or a folder that is not
    registered. An empty registry, or none, is an empty set: the result line says 0 and the exit code is 0.

    The <m> of the result line counts the manifests that parse, a second program of one repository included.

    -Json prints the same records as one JSON array - repo, program ('' for the main manifest), state, path,
    product, exe, cliVersion, schemaVersion, reason, commands[] (name, summary, risk, coldStart) - and no result
    line; an empty set prints [].

    Exit codes: 0 listed (an empty list, an invalid manifest and a missing folder are reports, not gates); 2 bad
    invocation or an unknown project.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string] $Project = '',
    [switch] $Json,
    [switch] $Help
)

if ($Help) {
    Get-Help -Name $PSCommandPath -Detailed | Out-String -Width 120 | Write-Host
    exit 0
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/registry.ps1')

function Stop-Lister([int] $Code, [string] $Message) {
    [Console]::Error.WriteLine("app-commands: $Message")
    exit $Code
}

function ConvertTo-FlatText($Value) {
    if ($null -eq $Value -or $Value -isnot [string]) { return '' }
    return [regex]::Replace($Value, '\s+', ' ').Trim()
}

function Get-FlatOrUnknown($Value) {
    $t = ConvertTo-FlatText $Value
    if ($t) { return $t }
    return 'unknown'
}

# The manifests of one repository (APP-COMMANDS rule 18 and item R.1 of 0.2): docs/cli-commands.json is the main
# program's, and every other program that stays running keeps docs/cli-commands.<program>.json, <program> a short
# lower-case name. Returns @{ program; file } in reading order - the main one first, then the others by name; a
# file whose middle part is not such a name is not a manifest and is skipped. Never throws.
function Get-AppManifestFiles([string] $Root) {
    $docs = Join-Path $Root 'docs'
    $found = [Collections.Generic.List[object]]::new()
    $main = Join-Path $docs 'cli-commands.json'
    if ([IO.File]::Exists($main)) { $found.Add(@{ program = ''; file = $main }) }
    $others = [Collections.Generic.SortedDictionary[string, string]]::new([StringComparer]::Ordinal)   # by name, ordinal: the order never depends on the culture
    try {
        foreach ($f in [IO.Directory]::GetFiles($docs, 'cli-commands.*.json')) {
            $m = [regex]::Match([IO.Path]::GetFileName($f), '^cli-commands\.(?<p>[a-z][a-z0-9-]*)\.json\z')
            if ($m.Success) { $others[$m.Groups['p'].Value] = $f }
        }
    }
    catch { }
    foreach ($p in $others.Keys) { $found.Add(@{ program = $p; file = $others[$p] }) }
    return $found.ToArray()   # the caller wraps the call in @(): an empty list emits nothing, a hashtable is never unrolled
}

# One manifest file: @{ state; reason; product; exe; cliVersion; schemaVersion; commands } with state
# none | invalid | ok. Never throws.
$script:ManifestLimit = 1MB
function Read-AppManifest([string] $file) {
    $res = [ordered]@{ state = 'none'; reason = ''; product = ''; exe = ''; cliVersion = ''; schemaVersion = $null; commands = @() }
    if (-not [IO.File]::Exists($file)) { return $res }
    $bad = { param($why) $res.state = 'invalid'; $res.reason = $why; return $res }
    try {
        $info = [IO.FileInfo]::new($file)
        if ($info.Length -gt $script:ManifestLimit) { return (& $bad 'larger than 1 MiB') }
        $text = [Text.UTF8Encoding]::new($false).GetString([IO.File]::ReadAllBytes($file))
    }
    catch { return (& $bad ('cannot be read - ' + (ConvertTo-FlatText $_.Exception.Message))) }
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    try { $doc = ConvertFrom-Json -InputObject $text -DateKind String -NoEnumerate }
    catch { return (& $bad 'not JSON') }
    if (-not (Test-PqObjectValue $doc)) { return (& $bad 'not a JSON object') }
    $sv = Get-PqValue $doc 'schemaVersion'
    if (-not (Test-PqIntValue $sv)) { return (& $bad 'schemaVersion is missing or not an integer') }
    if ($sv -ne 1) { return (& $bad "schemaVersion $sv is not 1, the one this lister reads") }
    # Read the property itself: a function's output pipeline would unroll the array (empty to $null, one to its element).
    $prop = $doc.PSObject.Properties['commands']
    $list = $null
    if ($null -ne $prop) { $list = $prop.Value }
    if ($null -eq $list -or $list -isnot [array]) { return (& $bad 'no commands array') }
    $out = [Collections.Generic.List[object]]::new()
    $i = 0
    foreach ($c in $list) {
        $i++
        $name = if (Test-PqObjectValue $c) { ConvertTo-FlatText (Get-PqValue $c 'name') } else { '' }
        if (-not $name) { return (& $bad "commands[$($i - 1)] has no name") }
        $out.Add([pscustomobject][ordered]@{
                name = $name
                summary = (ConvertTo-FlatText (Get-PqValue $c 'summary'))
                risk = (Get-FlatOrUnknown (Get-PqValue $c 'risk'))
                coldStart = (Get-FlatOrUnknown (Get-PqValue $c 'coldStart'))
            })
    }
    $res.state = 'ok'
    $res.schemaVersion = [int]$sv
    $res.product = ConvertTo-FlatText (Get-PqValue $doc 'product')
    $res.exe = ConvertTo-FlatText (Get-PqValue $doc 'exe')
    $res.cliVersion = ConvertTo-FlatText (Get-PqValue $doc 'cliVersion')
    $res.commands = $out.ToArray()
    return $res
}

# ---- the registry (it may be missing: that is an empty set) ----
$repos = @()
$rankOf = @{}
$read = $null
try { $read = Read-PqRegistry }
catch { [Console]::Error.WriteLine("app-commands: the registry cannot be read - $($_.Exception.Message)") }
if ($null -ne $read) {
    if ($null -ne $read.registry) {
        $repos = @($read.registry.repos)
        $pos = 0
        foreach ($o in @(Get-PqRepoOrder $read.registry)) { $rankOf[[string]$o.key] = $pos; $pos++ }
        if (-not $read.ok) { [Console]::Error.WriteLine("app-commands: the registry has a problem - $(@($read.errors)[0].where) $(@($read.errors)[0].message)") }
    }
    elseif (@($read.errors).Count -and @($read.errors)[0].name -cne 'RegistryMissing') {
        [Console]::Error.WriteLine("app-commands: the registry cannot be read - $(@($read.errors)[0].message)")
    }
}
$keys = if ($repos.Count) { (@($repos | ForEach-Object { [string]$_.key }) -join ', ') } else { 'none registered' }

# ---- the scope ----
$scope = [Collections.Generic.List[object]]::new()   # @{ key; root; rank }
if ($Project) {
    $rec = @($repos | Where-Object { [string]$_.key -ieq $Project }) | Select-Object -First 1
    if ($rec) { $scope.Add(@{ key = [string]$rec.key; root = [string]$rec.path; rank = $rankOf[[string]$rec.key] }) }
    elseif (Test-Path -LiteralPath $Project -PathType Container) {
        $full = (Resolve-Path -LiteralPath $Project).Path
        $scope.Add(@{ key = (Split-Path -Leaf $full); root = $full; rank = 0 })
    }
    else { Stop-Lister 2 "unknown project '$Project' - neither a registered key nor a folder (registered: $keys)" }
}
else {
    foreach ($r in $repos) { $scope.Add(@{ key = [string]$r.key; root = [string]$r.path; rank = $rankOf[[string]$r.key] }) }
}

# ---- gather ----
$records = [Collections.Generic.List[object]]::new()
foreach ($s in @($scope | Sort-Object -Property { $_.rank })) {
    $new = { param([string] $program) [ordered]@{ repo = $s.key; program = $program; state = 'none'; path = $s.root; product = ''; exe = ''; cliVersion = ''; schemaVersion = $null; reason = ''; commands = @() } }
    if ([string]::IsNullOrWhiteSpace($s.root) -or -not [IO.Directory]::Exists($s.root)) {
        $rec = & $new ''
        $rec.state = 'missing'
        $rec.reason = 'the registered folder is not there'
        $records.Add([pscustomobject]$rec)
        continue
    }
    $files = @(Get-AppManifestFiles $s.root)
    if ($files.Count -eq 0) { $records.Add([pscustomobject](& $new '')); continue }
    foreach ($f in $files) {
        $rec = & $new ([string]$f.program)
        $m = Read-AppManifest ([string]$f.file)
        foreach ($k in @('state', 'reason', 'product', 'exe', 'cliVersion', 'schemaVersion', 'commands')) { $rec[$k] = $m[$k] }
        $records.Add([pscustomobject]$rec)
    }
}

if ($Json) {
    if ($records.Count -eq 0) { Write-Output '[]' } else { ConvertTo-Json -InputObject @($records) -Depth 6 }
    exit 0
}

$counts = @{ ok = 0; none = 0; invalid = 0; missing = 0 }
$commandTotal = 0
foreach ($r in $records) {
    $counts[$r.state]++
    $label = if ($r.program) { "$($r.repo)/$($r.program)" } else { $r.repo }
    switch ($r.state) {
        'ok' {
            $commandTotal += @($r.commands).Count
            $name = if ($r.product) { $r.product } else { $r.repo }
            $cli = if ($r.cliVersion) { "cliVersion=$($r.cliVersion)" } else { 'cliVersion=unknown' }
            Write-Host ("OK       {0}  {1}  {2}  {3} command(s)" -f $label, $name, $cli, @($r.commands).Count)
            foreach ($c in @($r.commands)) {
                Write-Host ("    {0}  risk={1}  coldStart={2}  {3}" -f $c.name, $c.risk, $c.coldStart, $c.summary)
            }
        }
        'none' { Write-Host ("NONE     {0}" -f $label) }
        'invalid' { Write-Host ("INVALID  {0}  {1}" -f $label, $r.reason) }
        'missing' { Write-Host ("MISSING  {0}  {1}" -f $label, $r.path) }
    }
}
Write-Host ("app-commands: {0} command(s) in {1} product(s); none {2}, invalid {3}, missing {4}" -f $commandTotal, $counts.ok, $counts.none, $counts.invalid, $counts.missing)
exit 0
