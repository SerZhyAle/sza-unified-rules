#requires -Version 7.5
<#
.SYNOPSIS
    Save what a site-audit workflow run returned as text - each site's report.md, a lens report its agent could not
    write, and the portfolio summary - into the git-ignored run folders they belong to.

.DESCRIPTION
    The harness refuses report files from subagents ("Subagents should return findings as text, not write report
    files"), so the workflow's report and portfolio agents return their Markdown instead of writing it, and the main
    session writes it with this script. -Output is the workflow's output file, which the completion notice names, or
    the workflow's result saved as JSON.

    It saves sites[].markdown to sites[].report, every sites[].saves[] entry (a lens report returned as text) to its
    path, and portfolio.markdown to portfolio.report. A path is written only when its file name is one the workflow
    uses, its folder is a run folder (site-audit/<date>[_n], or <date>[_n]/external/<host> below one) and git reports
    the file ignored; anything else is refused and not written. An existing file is kept unless -Force is given, so a
    second call on the same output never replaces a report edited by hand.

.OUTPUTS
    One line per file: written, kept or refused, with the reason. Exit 0 when nothing was refused, 2 for unusable
    input, 3 when at least one file was refused.

.EXAMPLE
    pwsh -NoProfile -File tools/site-audit/save-reports.ps1 -Output <the notice's output file>
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Output,
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$names = 'report.md', 'portfolio.md', 'robot.md', 'ux.md', 'release-facts.md', 'structured-data.md', 'i18n.md',
    'docs.md', 'prepublish.md'
$runKey = '^\d{4}-\d{2}-\d{2}(_\d{1,6})?$'

function Get-Prop($Object, [string] $Name) {
    if ($null -eq $Object -or $Object -isnot [pscustomobject]) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { $p.Value } else { $null }
}

function Test-RunFolder([string] $Dir) {
    $leaf = Split-Path $Dir -Leaf
    $parent = Split-Path $Dir -Parent
    if ($leaf -match $runKey) { return (Split-Path $parent -Leaf) -eq 'site-audit' }
    if ((Split-Path $parent -Leaf) -ne 'external') { return $false }
    $run = Split-Path $parent -Parent
    ((Split-Path $run -Leaf) -match $runKey) -and ((Split-Path (Split-Path $run -Parent) -Leaf) -eq 'site-audit')
}

function Test-Ignored([string] $Path) {
    $dir = Split-Path $Path -Parent
    while ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { $dir = Split-Path $dir -Parent }
    if (-not $dir) { return $false }
    & git -C $dir check-ignore -q -- $Path 2>$null
    $LASTEXITCODE -eq 0
}

$outPath = [IO.Path]::GetFullPath($Output, (Get-Location).Path)
if (-not (Test-Path -LiteralPath $outPath -PathType Leaf)) { Write-Error "save-reports: no such file: $outPath" -ErrorAction Continue; exit 2 }
try { $json = Get-Content -LiteralPath $outPath -Raw | ConvertFrom-Json -Depth 100 }
catch { Write-Error "save-reports: $outPath is not JSON: $($_.Exception.Message)" -ErrorAction Continue; exit 2 }
$result = if (Get-Prop (Get-Prop $json 'result') 'sites') { $json.result } else { $json }
if ($null -eq (Get-Prop $result 'sites')) { Write-Error "save-reports: $outPath holds no site-audit result (no sites)" -ErrorAction Continue; exit 2 }

$items = [System.Collections.Generic.List[object]]::new()
foreach ($s in @($result.sites)) {
    $key = Get-Prop $s 'key'
    $items.Add([pscustomobject]@{ what = "report $key"; path = (Get-Prop $s 'report'); text = (Get-Prop $s 'markdown') })
    foreach ($x in @(Get-Prop $s 'saves')) {
        if ($null -eq $x) { continue }
        $items.Add([pscustomobject]@{ what = "lens $key"; path = (Get-Prop $x 'path'); text = (Get-Prop $x 'markdown') })
    }
}
$pf = Get-Prop $result 'portfolio'
if ($pf) { $items.Add([pscustomobject]@{ what = 'portfolio'; path = (Get-Prop $pf 'report'); text = (Get-Prop $pf 'markdown') }) }

$refused = 0; $written = 0
$enc = [Text.UTF8Encoding]::new($false)
foreach ($i in $items) {
    if (-not $i.text) { "save-reports: kept   $($i.what): the result carries no text for it"; continue }
    if (-not $i.path -or -not [IO.Path]::IsPathRooted([string] $i.path)) { $refused++; "save-reports: REFUSED $($i.what): no absolute path ($($i.path))"; continue }
    $full = [IO.Path]::GetFullPath([string] $i.path)
    $why = if ((Split-Path $full -Leaf) -notin $names) { 'not a file name the workflow writes' }
        elseif (-not (Test-RunFolder (Split-Path $full -Parent))) { 'not inside a site-audit run folder' }
        elseif (-not (Test-Ignored $full)) { 'git would track it' }
    if ($why) { $refused++; "save-reports: REFUSED $($i.what): $why - $full"; continue }
    if ((Test-Path -LiteralPath $full) -and -not $Force) { "save-reports: kept   $($i.what): exists, -Force replaces it - $full"; continue }
    [IO.Directory]::CreateDirectory((Split-Path $full -Parent)) | Out-Null
    [IO.File]::WriteAllText($full, [string] $i.text, $enc)
    $written++
    'save-reports: wrote  {0}: {1} bytes - {2}' -f $i.what, (Get-Item -LiteralPath $full).Length, $full
}
"save-reports: $written written, $refused refused, $($items.Count) in the result"
if ($refused) { exit 3 }
exit 0
