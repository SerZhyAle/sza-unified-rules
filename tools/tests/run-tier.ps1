#requires -Version 7.0
<#
    The test tiers of this repository. tools/tests/tiers.json is the one home of the tier, the measured seconds and
    the date of every gate and suite (rules/TESTING_AND_QA.md section 2). A suite on disk with no row there is
    release tier, unmeasured. A suite header says what the suite covers; it never states a tier or a time.

      -List [-Tier fast]      every row and every unlisted suite (or one tier, with the sum of its seconds)
      -Tier fast              runs every fast row, one line per suite
      -Suite <name>           runs one fast suite; refuses a release-tier or unmeasured one
      -Suite <name> -Measure  the owner-named run: runs any suite, times it, writes seconds, date and tier
      -Registry <file>        another registry file (a scratch copy); suites still come from this checkout

    Exit codes: 0 pass, 1 a suite failed or a row is wrong, 2 refused or could not run.
#>
[CmdletBinding()]
param(
    [switch] $List,
    [ValidateSet('fast', 'release')][string] $Tier,
    [string] $Suite,
    [switch] $Measure,
    [string] $Registry
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$inv = [cultureinfo]::InvariantCulture
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if (-not $Registry) { $Registry = Join-Path $PSScriptRoot 'tiers.json' }
if (-not (Test-Path -LiteralPath $Registry)) { Write-Host "run-tier: COULD NOT RUN - registry not found: $Registry"; exit 2 }
$Registry = (Resolve-Path -LiteralPath $Registry).Path
$doc = Get-Content -LiteralPath $Registry -Raw | ConvertFrom-Json
$line = [double]$doc.lineSeconds
$rows = [Collections.Generic.List[object]]::new()
foreach ($r in @($doc.suites)) { $rows.Add($r) }

$onDisk = @(foreach ($glob in 'tools/tests/*.tests.ps1', 'tools/tests/*.tests.py', 'tools/tests/smoke-*.ps1', 'hooks/tests/smoke-*.ps1') {
        Get-ChildItem -Path (Join-Path $root $glob) -File -ErrorAction SilentlyContinue |
            ForEach-Object { [IO.Path]::GetRelativePath($root, $_.FullName) -replace '\\', '/' }
    })
$listed = @($rows | ForEach-Object { $_.path })
$unlisted = @($onDisk | Where-Object { $listed -notcontains $_ } | Sort-Object)

function Format-Sec($Value) { if ($null -eq $Value) { '-' } else { ([double]$Value).ToString('0.0#', $inv) } }
function Test-FastRow($Row) { $Row.tier -eq 'fast' -and $null -ne $Row.seconds -and [double]$Row.seconds -le $line }

function Invoke-One([string] $Path) {
    $full = Join-Path $root $Path
    $exe = 'pwsh'; $argList = @('-NoProfile', '-File', $full)
    if ($Path -like '*.py') {
        $exe = 'py', 'python' | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
        $argList = @($full)
    }
    if (-not $exe) { return [pscustomobject]@{ code = $null; seconds = 0.0; out = @('neither py nor python is on PATH') } }
    Push-Location -LiteralPath $root
    try {
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $out = @(& $exe @argList 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
        $watch.Stop()
    }
    finally { Pop-Location }
    [pscustomobject]@{ code = $code; seconds = [math]::Round($watch.Elapsed.TotalSeconds, 2); out = $out }
}

function Save-Registry {
    $text = @('{', "  `"schema`": $($doc.schema),", "  `"lineSeconds`": $($doc.lineSeconds),", "  `"note`": $(ConvertTo-Json ([string]$doc.note)),", '  "suites": [')
    $text += (@($rows | ForEach-Object { '    ' + ($_ | ConvertTo-Json -Compress) }) -join ",`n")
    $text += '  ]', '}'
    [IO.File]::WriteAllText($Registry, (($text -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
}

if ($Measure -and -not $Suite) { Write-Host 'run-tier: COULD NOT RUN - -Measure needs -Suite <name>'; exit 2 }

if ($Suite) {
    $name = $Suite -replace '\\', '/'
    $hit = @(@($listed + $unlisted) | Where-Object { $_ -eq $name -or ($_ -split '/')[-1] -in @($name, "$name.ps1", "$name.py", "$name.tests.ps1", "$name.tests.py") })
    if ($hit.Count -ne 1) { Write-Host "run-tier: COULD NOT RUN - '$Suite' matches $($hit.Count) suites: $($hit -join ', ')"; exit 2 }
    $path = $hit[0]
    $row = $rows | Where-Object { $_.path -eq $path } | Select-Object -First 1
    if (-not $Measure -and -not ($row -and (Test-FastRow $row))) {
        $what = if ($row) { "release tier ($(Format-Sec $row.seconds) s, $($row.measured))" } else { 'release tier, unmeasured' }
        Write-Host "run-tier: REFUSED - $path is $what; it runs only when the owner names it: add -Measure to run it and record the time"
        exit 2
    }
    $res = Invoke-One $path
    $res.out | ForEach-Object { Write-Host $_ }
    if ($null -eq $res.code) { Write-Host "run-tier: COULD NOT RUN - $path"; exit 2 }
    if ($res.code -ne 0) { Write-Host "run-tier: FAIL  $(Format-Sec $res.seconds) s  $path (exit $($res.code))$(if ($Measure) { ' - not recorded' })"; exit 1 }
    if ($Measure) {
        $newTier = if ($res.seconds -le $line) { 'fast' } else { 'release' }
        $today = (Get-Date).ToString('yyyy-MM-dd', $inv)
        if ($row) { $row.tier = $newTier; $row.seconds = $res.seconds; $row.measured = $today }
        else { $rows.Add([pscustomobject][ordered]@{ path = $path; tier = $newTier; seconds = $res.seconds; measured = $today; covers = '' }) }
        Save-Registry
        Write-Host "run-tier: recorded $path - $newTier, $(Format-Sec $res.seconds) s, $today$(if (-not $row) { ' (new row: fill its covers text by hand)' })"
    }
    Write-Host "run-tier: PASS  $(Format-Sec $res.seconds) s  $path"
    exit 0
}

if ($List -or -not $Tier) {
    $bad = 0; $sum = 0.0; $shown = 0
    foreach ($r in $rows) {
        if ($Tier -and $r.tier -ne $Tier) { continue }
        $flag = ''
        if (-not (Test-Path -LiteralPath (Join-Path $root $r.path))) { $flag = '  << MISSING FILE'; $bad++ }
        elseif ($r.tier -notin 'fast', 'release' -or ($r.tier -eq 'fast' -and -not (Test-FastRow $r))) { $flag = '  << TIER CONTRADICTS SECONDS'; $bad++ }
        if ($null -ne $r.seconds) { $sum += [double]$r.seconds }
        $shown++
        Write-Host ('{0,-8}{1,7} s  {2,-10}  {3} - {4}{5}' -f $r.tier, (Format-Sec $r.seconds), $r.measured, $r.path, $r.covers, $flag)
    }
    if ($Tier -ne 'fast') { foreach ($p in $unlisted) { $shown++; Write-Host ('{0,-8}{1,7} s  {2,-10}  {3}' -f 'release', '-', 'unmeasured', $p) } }
    Write-Host "run-tier: $shown shown$(if ($Tier) { " ($Tier)" }), recorded seconds sum $(Format-Sec $sum) s, the line is $(Format-Sec $line) s per suite, $bad wrong row(s)"
    exit $(if ($bad) { 1 } else { 0 })
}

if ($Tier -eq 'release') { Write-Host 'run-tier: REFUSED - the release tier is never run as a whole; name one suite: -Suite <name> -Measure'; exit 2 }

$failed = 0; $skipped = 0; $ran = 0; $total = 0.0
foreach ($r in @($rows | Where-Object { Test-FastRow $_ })) {
    $res = Invoke-One $r.path
    if ($null -eq $res.code) { $skipped++; Write-Host "SKIP        -    $($r.path) - $($res.out -join ' ')"; continue }
    $ran++; $total += $res.seconds
    $over = if ($res.seconds -gt $line) { '  << above the line in this run; re-measure by name' } else { '' }
    Write-Host ('{0}  {1,7} s  {2}{3}' -f $(if ($res.code -eq 0) { 'PASS' } else { 'FAIL' }), (Format-Sec $res.seconds), $r.path, $over)
    if ($res.code -ne 0) { $failed++; $res.out | Select-Object -Last 8 | ForEach-Object { Write-Host "        $_" } }
}
Write-Host "run-tier: $(if ($failed) { 'FAIL' } else { 'PASS' }) (run=$ran failed=$failed skipped=$skipped, $(Format-Sec $total) s)"
exit $(if ($failed) { 1 } else { 0 })
