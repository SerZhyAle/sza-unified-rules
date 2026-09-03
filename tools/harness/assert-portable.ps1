#requires -Version 7.0
<#
.SYNOPSIS
    Refuse a harness script whose body still names one product's paths, vocabulary or prefix.

.DESCRIPTION
    The harness is shipped by the canon and configured by one file, .sza-profile.json. A path,
    an environment prefix, a log-call shape or a build-system marker written into a script body
    is a value the profile can no longer override, so an adopting repository silently runs
    another product's convention. This gate judges CODE lines only: block comments and line
    comments are stripped first, because a comment that cites a ticket's history is allowed to
    say where a value used to live.

    Patterns judged (each names the product coupling it catches):
      PLAN[\\/]              spec directory
      dev[\\/]CHANGELOG      change journal
      docs[\\/](ALL_FEATURES|DOCUMENT_REGISTRY)   ledger and registry files
      temp[\\/]              scratch root and every lock/lease/chat directory under it
      FMS_                   environment prefix
      Timber\.               Android log call
      app_v2|[\\/]wear[\\/]  module roots
      settings\.gradle       build-system root marker
      scripts[\\/]           this repository's script tree (a harness script reaches a sibling
                             relatively, and a project script through the profile's hooks)
      dev[\\/]CATALOG        this repository's class catalogue
      \.claude[\\/]commands  command driver directory
      serzhyale|FastMediaSorter   product and owner names

.PARAMETER Root
    Harness root to judge. Defaults to this script's own directory.

.PARAMETER Allow
    Extra regex patterns whose matches are ignored (for a deliberate, documented default).

.OUTPUTS
    One line per offending code line: <relative path>:<line>: <text>.

.EXAMPLE
    pwsh -NoProfile -File tools/harness/assert-portable.ps1

Exit codes:
  0  no product literal found in any code line
  1  at least one code line names a product literal (each is printed)
  2  the root does not exist
#>
[CmdletBinding()]
param(
    [string]$Root = $PSScriptRoot,
    [string[]]$Allow = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    Write-Host "assert-portable: root '$Root' does not exist" -ForegroundColor Red
    exit 2
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$patterns = @(
    'PLAN[\\/]',
    'dev[\\/]CHANGELOG',
    'docs[\\/](ALL_FEATURES|DOCUMENT_REGISTRY)',
    '(?<![A-Za-z])temp[\\/]',
    'FMS_',
    'Timber\.',
    'app_v2',
    '[\\/''"]wear[\\/''"]',
    'settings\.gradle',
    'scripts[\\/]',
    'dev[\\/]CATALOG',
    '\.claude[\\/]commands',
    'serzhyale',
    'FastMediaSorter'
)
$judge = [regex]::new(($patterns -join '|'))
$allowRx = if ($Allow.Count -gt 0) { [regex]::new(($Allow -join '|')) } else { $null }

function Get-CodeLines([string]$Path) {
    # Strip <# .. #> blocks and trailing/whole-line # comments, keeping line numbers stable so a
    # finding points at the real line. Strings are not parsed: a literal inside a string IS the
    # coupling this gate exists to find.
    $raw = Get-Content -LiteralPath $Path -Raw
    $noBlock = [regex]::Replace($raw, '(?s)<#.*?#>', { param($m) ($m.Value -replace '[^\r\n]', ' ') })
    $lines = $noBlock -split "`r?`n"
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        # A '#' inside a quoted string is not a comment; the common shapes here are '#' after
        # code and whole-line comments, and a regex literal like '^#' sits inside quotes.
        $code = $line
        $inS = $false; $inD = $false
        for ($i = 0; $i -lt $code.Length; $i++) {
            $c = $code[$i]
            if ($c -eq "'" -and -not $inD) { $inS = -not $inS; continue }
            if ($c -eq '"' -and -not $inS) { $inD = -not $inD; continue }
            if ($c -eq '#' -and -not $inS -and -not $inD) { $code = $code.Substring(0, $i); break }
        }
        $out.Add($code)
    }
    return $out
}

$findings = 0
# _profile.ps1 is excluded by design: its defaults ARE the canon's conventions, and they are the
# one place a path literal belongs - every other script reads them from there.
$files = Get-ChildItem -LiteralPath $Root -Recurse -File -Include *.ps1 |
    Where-Object { $_.FullName -ne $PSCommandPath -and $_.Name -ne '_profile.ps1' }
foreach ($f in $files) {
    $rel = $f.FullName.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/')
    $lines = Get-CodeLines $f.FullName
    for ($n = 0; $n -lt $lines.Count; $n++) {
        $text = $lines[$n]
        if (-not $judge.IsMatch($text)) { continue }
        if ($allowRx -and $allowRx.IsMatch($text)) { continue }
        $findings++
        Write-Output ("{0}:{1}: {2}" -f $rel, ($n + 1), $text.Trim())
    }
}

if ($findings -gt 0) {
    Write-Host "assert-portable: FAIL - $findings code line(s) name a product literal under $Root" -ForegroundColor Red
    exit 1
}
Write-Host "assert-portable: PASS - $($files.Count) script(s) carry no product literal" -ForegroundColor Green
exit 0
