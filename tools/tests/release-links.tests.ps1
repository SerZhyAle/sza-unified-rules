#requires -Version 7.0
<#
.SYNOPSIS
    Fixture tests for check-compliance.ps1 SZA-VER04 (versioned release links on a site page).

.DESCRIPTION
    Creates one scratch git repository under the temp directory and runs check-compliance.ps1 with
    -Only SZA-VER04 -Json, rewriting the page between runs. Covers:
      1. No release manifest -> a versioned link warns.
      2. Manifest version matches (link tag with a leading v) and /releases/latest is on the page -> clean.
      3. A link of another version beside a good one -> warn naming the stale tag.
      4. Matching version without a durable fallback, or with another repository's only -> warn.

    Exit codes: 0 all passed; 1 assertion failed.
#>
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$gate = Join-Path $repoRoot 'tools/check-compliance.ps1'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('sza-release-links-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $scratch -Force
$script:failed = 0

$releases = 'https://github.com/o/r/releases'
$current = "<a href=`"$releases/download/v1.2.3/app.zip`">get</a>"
$stale = "<a href=`"$releases/download/v1.2.2/app.zip`">old</a>"
$durable = "<a href=`"$releases/latest`">latest</a>"
$foreign = '<a href="https://github.com/o/other/releases/latest">other</a>'

function Write-Fixture([string]$Name, [string]$Text) { [IO.File]::WriteAllText((Join-Path $scratch $Name), $Text) }

function Get-Findings([string]$Page) {
    Write-Fixture 'index.html' $Page
    $raw = (& pwsh -NoProfile -File $gate -RepoRoot $scratch -Only SZA-VER04 -Json 2>&1) -join "`n"
    return @(($raw | ConvertFrom-Json).findings)
}

function Test-Case([string]$Name, [scriptblock]$Body) {
    try { & $Body; Write-Host "PASS  $Name" }
    catch { $script:failed++; Write-Host "FAIL  $Name - $_" -ForegroundColor Red }
}

function Assert-Warn($Found, [string]$Pattern) {
    if ($Found.Count -ne 1 -or $Found[0].message -notmatch $Pattern) {
        throw "expected one warning matching '$Pattern', got: $($Found | ConvertTo-Json -Compress)"
    }
}

try {
    Write-Fixture '.sza-canon.json' '{"schemaVersion":"1.0","canon":{"version":"2026.11.25.5","coreDigest":"0","model":"reference"},"overlay":["none"],"ledgerShape":"none","channels":[],"site":{"kind":"product","root":".","pages":["index.html"]}}'
    Write-Fixture 'index.html' ''
    $null = & git -C $scratch init -q 2>&1
    $null = & git -C $scratch add -A 2>&1

    Test-Case '1. no release manifest: a versioned link warns' {
        Assert-Warn (Get-Findings "$current $durable") 'no tracked release-manifest\.json'
    }

    $null = New-Item -ItemType Directory -Path (Join-Path $scratch 'tools') -Force
    Write-Fixture 'tools/release-manifest.json' '{"version":"1.2.3"}'
    $null = & git -C $scratch add -A 2>&1

    Test-Case '2. manifest version with a durable fallback is clean' {
        $found = Get-Findings "$current $durable"
        if ($found.Count) { throw "expected no finding, got: $($found | ConvertTo-Json -Compress)" }
    }
    Test-Case '3. a stale link beside a current one warns' {
        Assert-Warn (Get-Findings "$current $stale $durable") 'v1\.2\.2 is not the release manifest'
    }
    Test-Case '4. no fallback, or only another repository''s, warns' {
        Assert-Warn (Get-Findings $current) 'no durable fallback'
        Assert-Warn (Get-Findings "$current $foreign") 'no durable fallback'
    }
}
finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:failed) { Write-Host "release-links.tests: FAILED ($($script:failed))" -ForegroundColor Red; exit 1 }
Write-Host 'release-links.tests: OK' -ForegroundColor Green
exit 0
