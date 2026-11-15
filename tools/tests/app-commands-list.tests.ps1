#requires -Version 7.0
<#
.SYNOPSIS
    Cases for tools/harness/portfolio/app-commands-list.ps1 - the discovery half of APP-COMMANDS (rule 20), walked
    over the portfolio registry.

.DESCRIPTION
    Runs the script over throwaway repositories and a throwaway portfolio root; the real registry and the real
    repositories are never read or written. Starts no agent and no pq child, so the whole file takes a few seconds
    (every invocation is started at once - sequential pwsh starts alone would pass the 5 s line).

      1. A manifest that parses: the OK line (product, cliVersion, command count), one indented line per verb with
         risk, cold start and summary; a summary on two lines is flattened, Cyrillic is kept, a risk or cold start
         the manifest omits prints as `unknown` (never `safe`), members the lister does not know are ignored.
      2. The four states apart, one line each, and the result line counting them: a repository with no manifest
         (NONE), manifests that do not parse (INVALID: not JSON, a top-level array, schemaVersion missing,
         schemaVersion 2, no commands array, an entry without a name) and a registered folder that is gone
         (MISSING). An invalid manifest lists none of its commands.
      3. Registry rank order, whatever the array order; -Project takes a registered key or an unregistered
         folder and exits 2 for anything else.
      4. -Json is one flat array of records, the commands inside an OK record and none in an invalid one; an
         empty set prints [].
      5. An empty set is a report: no registry file, and a registry with no repositories, both exit 0 with
         `0 command(s) in 0 product(s)`.
      6. It reads the manifest and nothing else, writes nothing: a repository whose profile, ledger and stamp are
         garbage still lists, and every file hashes the same after all the runs.
      7. One manifest per program (APP-COMMANDS 0.2 item R.1): docs/cli-commands.<program>.json is listed beside
         docs/cli-commands.json as <key>/<program>, the main one first and the others by name; a broken second
         manifest is INVALID alone and the main one still lists; a repository with only a second manifest lists it
         and has no NONE line; a file whose middle part is not a short lower-case name is not a manifest; -Json
         carries `program` ('' for the main one) and the result line counts every manifest that parses.
#>
[CmdletBinding()]
param([switch] $KeepScratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$script_ = Join-Path $SourceRoot 'tools\harness\portfolio\app-commands-list.ps1'
$pwshExe = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('app-commands-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null
$portfolio = Join-Path $scratch 'portfolio'
New-Item -ItemType Directory -Path $portfolio | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)

function New-Repo([string] $Key, $Manifest = $null) {   # untyped: a [string] parameter would turn $null into an empty file
    $root = Join-Path $scratch $Key
    New-Item -ItemType Directory -Path (Join-Path $root 'docs') -Force | Out-Null
    if ($null -ne $Manifest) { [IO.File]::WriteAllText((Join-Path $root 'docs\cli-commands.json'), $Manifest, $utf8) }
    return $root
}
function ConvertTo-ManifestText($Object) { return (ConvertTo-Json -InputObject $Object -Depth 8) }

# ---- the repositories ----
$good = [ordered]@{
    schemaVersion = 1; product = 'Alpha Tool'; exe = 'AlphaTool.exe'; cliVersion = '1.2'; futureMember = @{ x = 1 }
    commands = @(
        [ordered]@{ name = 'commands'; summary = 'Prints the manifest.'; risk = 'safe'; coldStart = 'oneshot'; aliases = @('--commands'); examples = @() }
        [ordered]@{ name = 'note add'; summary = "Adds a note`n  to the day's list."; risk = 'writes-user-data'; coldStart = 'start' }
        [ordered]@{ name = 'экран снимок'; summary = 'Снимок области экрана.'; risk = 'reads-user-data'; coldStart = 'refuse' }
        [ordered]@{ name = 'bare'; summary = 'A verb that states neither risk nor cold start.' }
    )
}
$alpha = New-Repo 'alpha' (ConvertTo-ManifestText $good)
# Garbage in every file the lister must not read: the ledger, the profile, the stamp.
New-Item -ItemType Directory -Path (Join-Path $alpha 'PLAN') | Out-Null
[IO.File]::WriteAllText((Join-Path $alpha 'PLAN\spec-catalog.jsonl'), "not json at all`n", $utf8)
[IO.File]::WriteAllText((Join-Path $alpha '.sza-profile.json'), '{ broken', $utf8)
[IO.File]::WriteAllText((Join-Path $alpha '.sza-canon.json'), '[[[', $utf8)

$beta = New-Repo 'beta' (ConvertTo-ManifestText ([ordered]@{ schemaVersion = 1; product = 'Beta'; cliVersion = '1.0'; commands = @() }))
$none = New-Repo 'none'
$notJson = New-Repo 'notjson' '{ "schemaVersion": 1, '
$array = New-Repo 'array' '[1, 2, 3]'
$noSchema = New-Repo 'noschema' (ConvertTo-ManifestText ([ordered]@{ product = 'X'; commands = @() }))
$schema2 = New-Repo 'schema2' (ConvertTo-ManifestText ([ordered]@{ schemaVersion = 2; product = 'X'; commands = @() }))
$noCommands = New-Repo 'nocommands' (ConvertTo-ManifestText ([ordered]@{ schemaVersion = 1; product = 'X' }))
$noName = New-Repo 'noname' (ConvertTo-ManifestText ([ordered]@{ schemaVersion = 1; product = 'X'; commands = @([ordered]@{ name = 'ok'; risk = 'safe' }, [ordered]@{ summary = 'no name here'; risk = 'safe' }) }))
$gone = Join-Path $scratch 'gone'   # registered, never created
$loose = New-Repo 'loose' (ConvertTo-ManifestText ([ordered]@{ schemaVersion = 1; product = 'Loose'; cliVersion = '0.1'; commands = @([ordered]@{ name = 'show'; summary = 'Brings the window forward.'; risk = 'safe'; coldStart = 'start' }) }))

# Registry order is by rank; the array order is shuffled on purpose.
$entries = @(
    @('noname', $noName, 90), @('alpha', $alpha, 10), @('gone', $gone, 100), @('none', $none, 40), @('beta', $beta, 20),
    @('notjson', $notJson, 50), @('array', $array, 60), @('noschema', $noSchema, 70), @('schema2', $schema2, 80), @('nocommands', $noCommands, 85)
)
$repos = foreach ($p in $entries) {
    [ordered]@{ key = $p[0]; path = $p[1]; enabled = $true; maxWorkers = 1; concurrent = $false; role = 'product'; permissionMode = 'bypassPermissions'; rank = $p[2] }
}
[IO.File]::WriteAllText((Join-Path $portfolio 'repos.json'), (ConvertTo-Json -InputObject ([ordered]@{ schemaVersion = '1.0'; repos = @($repos) }) -Depth 5), $utf8)

# A second registry for case 7: a product with several programs, and one that has only a second manifest.
$multi = New-Repo 'multi' (ConvertTo-ManifestText ([ordered]@{ schemaVersion = 1; product = 'Main Prog'; exe = 'Main.exe'; cliVersion = '1.0'; commands = @(
            [ordered]@{ name = 'commands'; summary = 'Prints the manifest.'; risk = 'safe'; coldStart = 'oneshot' }
            [ordered]@{ name = 'show'; summary = 'Brings the window forward.'; risk = 'safe'; coldStart = 'start' }) }))
[IO.File]::WriteAllText((Join-Path $multi 'docs\cli-commands.share-manager.json'), (ConvertTo-ManifestText ([ordered]@{ schemaVersion = 1; product = 'Share Manager'; exe = 'Companion.exe'; cliVersion = '1.1'; commands = @(
            [ordered]@{ name = 'clipboard send'; summary = 'Sends the clipboard.'; risk = 'leaves-machine'; coldStart = 'oneshot' }) })), $utf8)
[IO.File]::WriteAllText((Join-Path $multi 'docs\cli-commands.broken-one.json'), '{ "schemaVersion": 1, ', $utf8)
# Not manifests by the name rule: an upper-case or underscored program name, a numeric first character, a third dot.
foreach ($ignored in @('cli-commands.Bad_Name.json', 'cli-commands.2fast.json', 'cli-commands.a.b.json', 'cli-commands.json.bak')) {
    [IO.File]::WriteAllText((Join-Path $multi "docs\$ignored"), (ConvertTo-ManifestText ([ordered]@{ schemaVersion = 1; product = 'Ignored'; commands = @([ordered]@{ name = 'x' }) })), $utf8)
}
$onlySecond = New-Repo 'onlysecond'
[IO.File]::WriteAllText((Join-Path $onlySecond 'docs\cli-commands.extra.json'), (ConvertTo-ManifestText ([ordered]@{ schemaVersion = 1; product = 'Extra'; cliVersion = '0.3'; commands = @([ordered]@{ name = 'status'; summary = 'Asks the first instance.'; risk = 'safe'; coldStart = 'refuse' }) })), $utf8)
$multiRoot = Join-Path $scratch 'multi-registry'
New-Item -ItemType Directory -Path $multiRoot | Out-Null
$multiRepos = foreach ($p in @(@('onlysecond', $onlySecond, 20), @('multi', $multi, 10))) {
    [ordered]@{ key = $p[0]; path = $p[1]; enabled = $true; maxWorkers = 1; concurrent = $false; role = 'product'; permissionMode = 'bypassPermissions'; rank = $p[2] }
}
[IO.File]::WriteAllText((Join-Path $multiRoot 'repos.json'), (ConvertTo-Json -InputObject ([ordered]@{ schemaVersion = '1.0'; repos = @($multiRepos) }) -Depth 5), $utf8)

$noRegistryRoot = Join-Path $scratch 'no-registry'
New-Item -ItemType Directory -Path $noRegistryRoot | Out-Null
$emptyRoot = Join-Path $scratch 'empty-registry'
New-Item -ItemType Directory -Path $emptyRoot | Out-Null
[IO.File]::WriteAllText((Join-Path $emptyRoot 'repos.json'), (ConvertTo-Json -InputObject ([ordered]@{ schemaVersion = '1.0'; repos = @() })), $utf8)

$watched = @(Get-ChildItem -LiteralPath $scratch -Recurse -File | Where-Object { $_.FullName -notlike "$noRegistryRoot*" -and $_.FullName -notlike "$emptyRoot*" } | Sort-Object FullName)
$hashesBefore = @($watched | ForEach-Object { '{0}={1}' -f $_.FullName, (Get-FileHash -LiteralPath $_.FullName).Hash })

# The child prints UTF-8 whatever the console code page is, so the Cyrillic assertions do not depend on the machine.
$wrapper = Join-Path $scratch 'run-lister.ps1'
[IO.File]::WriteAllText($wrapper, '[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); & $env:LISTER_SCRIPT @args; exit $LASTEXITCODE')

$calls = [ordered]@{
    all      = @{ a = @() }
    json     = @{ a = @('-Json') }
    byKey    = @{ a = @('-Project', 'ALPHA') }
    byFolder = @{ a = @('-Project', $loose) }
    unknown  = @{ a = @('-Project', 'nope') }
    noReg    = @{ a = @();         root = $noRegistryRoot }
    noRegJson = @{ a = @('-Json'); root = $noRegistryRoot }
    emptyReg = @{ a = @();         root = $emptyRoot }
    multi    = @{ a = @();         root = $multiRoot }
    multiJson = @{ a = @('-Json'); root = $multiRoot }
    multiOne = @{ a = @('-Project', 'multi'); root = $multiRoot }
}
$results = @{}
$calls.GetEnumerator() | ForEach-Object -ThrottleLimit 8 -Parallel {
    $c = $_.Value
    $psi = [Diagnostics.ProcessStartInfo]::new($using:pwshExe)
    foreach ($x in (@('-NoProfile', '-File', $using:wrapper) + $c.a)) { $psi.ArgumentList.Add([string] $x) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $psi.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $psi.WorkingDirectory = $using:scratch
    $psi.Environment['SZA_PORTFOLIO_ROOT'] = $(if ($c.ContainsKey('root')) { $c.root } else { $using:portfolio })
    $psi.Environment['LISTER_SCRIPT'] = $using:script_
    $proc = [Diagnostics.Process]::Start($psi)
    $out = $proc.StandardOutput.ReadToEndAsync()
    $err = $proc.StandardError.ReadToEndAsync()
    if (-not $proc.WaitForExit(60000)) { $proc.Kill($true) }
    $proc.WaitForExit()
    $lines = @($out.Result -split '\r?\n' | Where-Object { $_.Trim() })
    [pscustomobject]@{ name = $_.Key; code = $proc.ExitCode; lines = $lines; text = ($lines -join "`n"); stderr = $err.Result; last = $(if ($lines.Count) { $lines[-1] } else { '' }) }
} | ForEach-Object { $results[$_.name] = $_ }

try {
    Run-Case '1 a manifest that parses' {
        $r = $results['all']
        Assert-That ($r.code -eq 0) "exit $($r.code): $($r.text)"
        Assert-That ($r.lines -contains 'OK       alpha  Alpha Tool  cliVersion=1.2  4 command(s)') "OK line: $($r.text)"
        Assert-That ($r.lines -contains '    commands  risk=safe  coldStart=oneshot  Prints the manifest.') 'the safe verb line'
        Assert-That ($r.lines -contains "    note add  risk=writes-user-data  coldStart=start  Adds a note to the day's list.") "two-line summary not flattened: $($r.text)"
        Assert-That ($r.lines -contains '    экран снимок  risk=reads-user-data  coldStart=refuse  Снимок области экрана.') 'Cyrillic verb and summary lost'
        Assert-That ($r.lines -contains '    bare  risk=unknown  coldStart=unknown  A verb that states neither risk nor cold start.') 'an omitted risk must print as unknown, never safe'
        Assert-That ($r.lines -contains 'OK       beta  Beta  cliVersion=1.0  0 command(s)') 'a manifest with no commands is still OK'
    }
    Run-Case '2 the four states apart' {
        $r = $results['all']
        Assert-That ($r.lines -contains 'NONE     none') 'a repository with no manifest'
        Assert-That ($r.lines -contains 'INVALID  notjson  not JSON') 'not JSON'
        Assert-That ($r.lines -contains 'INVALID  array  not a JSON object') 'top-level array'
        Assert-That ($r.lines -contains 'INVALID  noschema  schemaVersion is missing or not an integer') 'schemaVersion missing'
        Assert-That ($r.lines -contains 'INVALID  schema2  schemaVersion 2 is not 1, the one this lister reads') 'schemaVersion 2'
        Assert-That ($r.lines -contains 'INVALID  nocommands  no commands array') 'no commands array'
        Assert-That ($r.lines -contains 'INVALID  noname  commands[1] has no name') "entry without a name: $($r.text)"
        Assert-That ($r.lines -contains "MISSING  gone  $gone") 'a registered folder that is gone'
        Assert-That (-not ($r.text -match '(?m)^    ok ')) 'an invalid manifest listed one of its commands'
        Assert-That ($r.last -eq 'app-commands: 4 command(s) in 2 product(s); none 1, invalid 6, missing 1') "result line: $($r.last)"
    }
    Run-Case '3 rank order and -Project' {
        $r = $results['all']
        $heads = @($r.lines | Where-Object { $_ -match '^(OK|NONE|INVALID|MISSING) ' } | ForEach-Object { ($_ -split '\s+')[1] })
        Assert-That (($heads -join ',') -eq 'alpha,beta,none,notjson,array,noschema,schema2,nocommands,noname,gone') "rank order: $($heads -join ',')"
        $k = $results['byKey']
        Assert-That ($k.code -eq 0 -and $k.last -eq 'app-commands: 4 command(s) in 1 product(s); none 0, invalid 0, missing 0') "by key (case-insensitive): $($k.code) $($k.last)"
        $f = $results['byFolder']
        Assert-That ($f.code -eq 0 -and $f.lines -contains 'OK       loose  Loose  cliVersion=0.1  1 command(s)') "by folder: $($f.text)"
        Assert-That ($results['unknown'].code -eq 2) "unknown project exit $($results['unknown'].code)"
        Assert-That ($results['unknown'].stderr -like '*unknown project*') "unknown project message: $($results['unknown'].stderr)"
    }
    Run-Case '4 -Json' {
        $text = $results['json'].text
        Assert-That ($text -match '^\s*\[\s*\{') "json is one flat array of records: $($text.Substring(0, [Math]::Min(20, $text.Length)))"
        $doc = ConvertFrom-Json -InputObject $text -NoEnumerate
        Assert-That ($doc.Count -eq 10) "json holds $($doc.Count) record(s)"
        $a = @($doc | Where-Object { $_.repo -eq 'alpha' })[0]
        Assert-That ($a.state -eq 'ok' -and $a.product -eq 'Alpha Tool' -and $a.exe -eq 'AlphaTool.exe' -and $a.cliVersion -eq '1.2' -and $a.schemaVersion -eq 1) 'alpha record members'
        Assert-That (@($a.commands).Count -eq 4 -and $a.commands[1].name -eq 'note add' -and $a.commands[1].risk -eq 'writes-user-data' -and $a.commands[3].risk -eq 'unknown') 'alpha commands'
        $n = @($doc | Where-Object { $_.repo -eq 'noname' })[0]
        Assert-That ($n.state -eq 'invalid' -and @($n.commands).Count -eq 0 -and $n.reason -eq 'commands[1] has no name') 'an invalid record carries its reason and no commands'
        Assert-That (@($doc | Where-Object { $_.repo -eq 'gone' })[0].state -eq 'missing') 'missing state in json'
        Assert-That (@($doc | Where-Object { $_.repo -eq 'none' })[0].state -eq 'none') 'none state in json'
    }
    Run-Case '5 an empty set is a report' {
        $a = $results['noReg']
        Assert-That ($a.code -eq 0 -and $a.last -eq 'app-commands: 0 command(s) in 0 product(s); none 0, invalid 0, missing 0') "no registry file: $($a.code) $($a.text)"
        Assert-That ($a.stderr -eq '') "a missing registry is not a complaint: $($a.stderr)"
        Assert-That ($results['noRegJson'].code -eq 0 -and $results['noRegJson'].text.Trim() -eq '[]') "no registry, json: $($results['noRegJson'].text)"
        $b = $results['emptyReg']
        Assert-That ($b.code -eq 0 -and $b.last -eq 'app-commands: 0 command(s) in 0 product(s); none 0, invalid 0, missing 0') "no repositories: $($b.code) $($b.text)"
    }
    Run-Case '6 reads the manifest only, writes nothing' {
        Assert-That ($results['all'].lines -contains 'OK       alpha  Alpha Tool  cliVersion=1.2  4 command(s)') 'a repository with a garbage profile, ledger and stamp must still list'
        $watchedAfter = @(Get-ChildItem -LiteralPath $scratch -Recurse -File | Where-Object { $_.FullName -notlike "$noRegistryRoot*" -and $_.FullName -notlike "$emptyRoot*" -and $_.Name -ne 'run-lister.ps1' } | Sort-Object FullName)
        $hashesAfter = @($watchedAfter | ForEach-Object { '{0}={1}' -f $_.FullName, (Get-FileHash -LiteralPath $_.FullName).Hash })
        Assert-That (($hashesBefore -join "`n") -ceq ($hashesAfter -join "`n")) 'a file under the scratch tree changed, appeared or vanished'
    }
    Run-Case '7 one manifest per program' {
        $r = $results['multi']
        Assert-That ($r.code -eq 0) "exit $($r.code): $($r.text)"
        $heads = @($r.lines | Where-Object { $_ -match '^(OK|NONE|INVALID|MISSING) ' } | ForEach-Object { ($_ -split '\s+')[0, 1] -join ' ' })
        Assert-That (($heads -join ',') -eq 'OK multi,INVALID multi/broken-one,OK multi/share-manager,OK onlysecond/extra') "labels and order (main first, then by name, rank across repositories): $($heads -join ',')"
        Assert-That ($r.lines -contains 'OK       multi  Main Prog  cliVersion=1.0  2 command(s)') "main manifest line: $($r.text)"
        Assert-That ($r.lines -contains 'OK       multi/share-manager  Share Manager  cliVersion=1.1  1 command(s)') 'second program line'
        Assert-That ($r.lines -contains '    clipboard send  risk=leaves-machine  coldStart=oneshot  Sends the clipboard.') 'a verb of the second program'
        Assert-That ($r.lines -contains 'INVALID  multi/broken-one  not JSON') 'a broken second manifest is INVALID alone'
        Assert-That ($r.lines -contains '    show  risk=safe  coldStart=start  Brings the window forward.') 'the main manifest still lists beside a broken one'
        Assert-That (-not ($r.text -match 'Ignored|Bad_Name|2fast|a\.b')) "a file that is not a manifest by the name rule was read: $($r.text)"
        Assert-That ($r.lines -contains 'OK       onlysecond/extra  Extra  cliVersion=0.3  1 command(s)') 'a repository with only a second manifest lists it'
        Assert-That (-not ($r.text -match '(?m)^NONE ')) 'a repository with a second manifest is not NONE'
        Assert-That ($r.last -eq 'app-commands: 4 command(s) in 3 product(s); none 0, invalid 1, missing 0') "result line counts every manifest that parses: $($r.last)"
        $o = $results['multiOne']
        Assert-That ($o.code -eq 0 -and $o.last -eq 'app-commands: 3 command(s) in 2 product(s); none 0, invalid 1, missing 0') "-Project narrows to one repository, every program of it: $($o.last)"
        $doc = ConvertFrom-Json -InputObject $results['multiJson'].text -NoEnumerate
        Assert-That ($doc.Count -eq 4) "json holds $($doc.Count) record(s)"
        $programs = @($doc | ForEach-Object { '{0}|{1}|{2}' -f $_.repo, $_.program, $_.state })
        Assert-That (($programs -join ',') -eq 'multi||ok,multi|broken-one|invalid,multi|share-manager|ok,onlysecond|extra|ok') "json repo, program, state: $($programs -join ',')"
        $plain = ConvertFrom-Json -InputObject $results['json'].text -NoEnumerate
        $alphaJson = @($plain | Where-Object { $_.repo -eq 'alpha' })[0]
        Assert-That ($null -ne $alphaJson.PSObject.Properties['program'] -and $alphaJson.program -ceq '') 'the main record carries program as an empty string'
    }
}
finally {
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
    else { Write-Host "scratch kept at $scratch" }
}

Write-Host ''
Write-Host ("app-commands-list tests: {0} case(s), {1} passed, {2} failed" -f $run, $passed, $failed)
if ($failed -gt 0) { exit 1 }
exit 0
