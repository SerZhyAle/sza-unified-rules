<#
bump-canon-version.ps1 - the single writer of the canon's version pair.

Two files carry the same number in two spellings: CANON_VERSION as `yyyy.MM.dd.N`, and
.claude-plugin/plugin.json `version` as `yyyy.<month without a leading zero><day>.N`, because semver
forbids a leading zero in a numeric identifier. They must move together - a drift between them is what
delivers a canon change to nobody - so nothing else writes either file. deploy.ps1 calls this.

The plugin version is what actually delivers the canon: `claude plugin update` compares that number and
nothing else, and the consumer's cache is a directory named for it, so content pushed under an
already-installed number is never refetched while both the deploy and the update report success.

  pwsh -File tools/bump-canon-version.ps1 -Print     # report the current pair, write nothing
  pwsh -File tools/bump-canon-version.ps1 -DryRun    # report the pair it would write, write nothing
  pwsh -File tools/bump-canon-version.ps1            # write the next pair

The next value keeps the stored date and increments N when that date is today or later, otherwise it is
today's date with N = 1. "Or later" is deliberate: a clock behind the stamp must not walk the version
backwards, which would leave consumers on a cache they can never be told to leave.

Exit codes: 0 = wrote the pair, or reported it under -DryRun / -Print;
            1 = a write failed;
            2 = cannot verify (a file is missing, or a version string does not parse).
#>
[CmdletBinding()]
param(
    [string]$Root,
    [switch]$DryRun,
    [switch]$Print
)

$ErrorActionPreference = 'Stop'

function Fail([string]$text, [int]$code) {
    Write-Host "bump-canon-version: $text" -ForegroundColor Red
    exit $code
}

if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
if (-not (Test-Path -LiteralPath $Root)) { Fail "root not found: $Root" 2 }

$canonFile  = Join-Path $Root 'CANON_VERSION'
$pluginFile = Join-Path $Root '.claude-plugin/plugin.json'
if (-not (Test-Path -LiteralPath $canonFile))  { Fail 'CANON_VERSION is missing - cannot verify' 2 }
if (-not (Test-Path -LiteralPath $pluginFile)) { Fail '.claude-plugin/plugin.json is missing - cannot verify' 2 }

$canonText = ([System.IO.File]::ReadAllText($canonFile)).Trim()
if ($canonText -notmatch '^(\d{4})\.(\d{2})\.(\d{2})\.(\d+)$') {
    Fail "CANON_VERSION does not parse as yyyy.MM.dd.N: '$canonText'" 2
}
$year = $Matches[1]; $month = $Matches[2]; $day = $Matches[3]; $serial = [int]$Matches[4]

function Get-PluginVersion([string]$y, [string]$mo, [string]$d, [int]$n) {
    '{0}.{1}{2}.{3}' -f $y, [int]$mo, $d, $n
}

$pluginText = [System.IO.File]::ReadAllText($pluginFile)
if ($pluginText -notmatch '"version"\s*:\s*"([^"]+)"') {
    Fail 'plugin.json carries no "version" field - cannot verify' 2
}
$pluginCurrent = $Matches[1]

$currentPair = Get-PluginVersion $year $month $day $serial
if ($pluginCurrent -ne $currentPair) {
    # A drift is exactly the failure this script exists to prevent, so say it rather than overwrite it silently.
    Write-Host "bump-canon-version: WARNING - the pair is already out of step: CANON_VERSION $canonText derives $currentPair, plugin.json holds $pluginCurrent" -ForegroundColor Yellow
}

if ($Print) {
    Write-Host "bump-canon-version: CANON_VERSION $canonText   plugin.json $pluginCurrent"
    exit 0
}

$today = Get-Date -Format 'yyyy.MM.dd'
$stored = "$year.$month.$day"
if ([string]::Compare($stored, $today, [System.StringComparison]::Ordinal) -ge 0) {
    $nextSerial = $serial + 1
    $nextDate = $stored
} else {
    $nextSerial = 1
    $nextDate = $today
}

$nextCanon = "$nextDate.$nextSerial"
$parts = $nextDate.Split('.')
$nextPlugin = Get-PluginVersion $parts[0] $parts[1] $parts[2] $nextSerial

if ($DryRun) {
    Write-Host "bump-canon-version: DRY RUN - would write CANON_VERSION $canonText -> $nextCanon" -ForegroundColor Yellow
    Write-Host "bump-canon-version: DRY RUN - would write plugin.json  $pluginCurrent -> $nextPlugin" -ForegroundColor Yellow
    exit 0
}

# CANON_VERSION is a bare version with no trailing newline; keep that byte shape so the file's diff is
# the version and nothing else.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
try {
    [System.IO.File]::WriteAllText($canonFile, $nextCanon, $utf8NoBom)
} catch {
    Fail "could not write CANON_VERSION: $($_.Exception.Message)" 1
}

# Replace the one version line rather than re-serialising: ConvertTo-Json would reorder and reformat the
# whole manifest, burying the change nobody could then review.
$updated = [regex]::Replace($pluginText, '("version"\s*:\s*")[^"]+(")', "`${1}$nextPlugin`${2}", 1)
if ($updated -eq $pluginText) { Fail 'the plugin.json version line did not change - refusing to report a bump that did not happen' 1 }
try {
    [System.IO.File]::WriteAllText($pluginFile, $updated, $utf8NoBom)
} catch {
    Fail "could not write plugin.json: $($_.Exception.Message)" 1
}

Write-Host "bump-canon-version: CANON_VERSION $canonText -> $nextCanon" -ForegroundColor Green
Write-Host "bump-canon-version: plugin.json  $pluginCurrent -> $nextPlugin" -ForegroundColor Green
exit 0
