#requires -Version 7.0
<#
.SYNOPSIS
  CANONR-0211, TASK-FLOW 0.52 rule 4: the spec header is written from the ledger by the catalog tools, and a header
  that differs is reported and rewritten. Harness scripts run in this process (child processes only where the scripts
  start their own), against a throwaway repository under the system temp directory.
.DESCRIPTION
  Cases:
    status paths - update.ps1, bulk-update.ps1, close.ps1 and archive.ps1 each leave the header equal to the row,
                   the archive reason on its note line
    drift        - an edited header is reported by drift-check.ps1 and validate.ps1 and rewritten from the ledger by
                   update.ps1
  Exit 0 when every case passed, 1 on any failure.
#>
[CmdletBinding()]
param([switch] $KeepScratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$Catalog = Join-Path $SourceRoot 'tools\harness\spec_catalog'

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Assert-Equal($Actual, $Expected, [string] $What) {
    if ("$Actual" -cne "$Expected") { throw "$What - expected '$Expected', got '$Actual'" }
}
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('header-mirror-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$repo = Join-Path $scratch 'repo'
$saved = @{}
$pinned = @{
    SZA_PROJECT_ROOT = $repo; SZA_HARNESS_ROOT = (Join-Path $SourceRoot 'tools\harness'); SZA_PQ_IN_SYNC = '1'
    SZA_BLOCK_LINKS = '0'; SZA_PROFILE_PATH = $null; SZA_SPEC_CATALOG_DIR = $null; SZA_SKIP_RELEASE_QUEUE = $null
}

function Write-Utf8([string] $Path, [string] $Text) {
    $dir = [IO.Path]::GetDirectoryName($Path)
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
function Invoke-Script([string] $Name, [hashtable] $Parameters) {
    $global:LASTEXITCODE = 0
    $out = & (Join-Path $Catalog $Name) @Parameters *>&1 | Out-String -Width 400
    return @{ code = $global:LASTEXITCODE; out = $out }
}
function Get-Row([string] $Id) {
    foreach ($file in 'spec-catalog.jsonl', 'spec-catalog-archive.jsonl') {
        foreach ($line in [IO.File]::ReadAllLines((Join-Path $repo "PLAN\$file"))) {
            if ($line) { $row = $line | ConvertFrom-Json; if ($row.id -ceq $Id) { return $row } }
        }
    }
    throw "no row $Id"
}
function Assert-Mirrored([string] $Id) {
    $row = Get-Row $Id
    $text = [IO.File]::ReadAllText((Join-Path $repo $row.file))
    Assert-That ($text -match "(?m)^\*\*Status:\*\* $([regex]::Escape($row.status))\r?$") "$Id header does not say $($row.status): $text"
    $note = $row.PSObject.Properties['statusNote']
    if ($note) { Assert-That ($text.Contains("**Status note:** $($note.Value)")) "$Id header does not carry the note: $text" }
}

try {
    foreach ($k in $pinned.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $pinned[$k]) }
    Write-Utf8 (Join-Path $repo '.sza-profile.json') '{}'
    $rows = foreach ($n in 1..4) {
        $id = 'S{0:d4}' -f $n
        Write-Utf8 (Join-Path $repo "PLAN\${id}_t.md") "# ${id}_t`n`n**Status:** Draft`n"
        [ordered]@{ id = $id; name = "t$n"; status = 'Draft'; priority = 50; file = "PLAN/${id}_t.md"; created = '2026-11-01'; updated = '2026-11-01 10:00' } | ConvertTo-Json -Compress
    }
    Write-Utf8 (Join-Path $repo 'PLAN\spec-catalog.jsonl') (($rows -join "`n") + "`n")
    Write-Utf8 (Join-Path $repo 'PLAN\spec-catalog-archive.jsonl') ''

    Run-Case 'status paths: every one leaves the header equal to the row' {
        $calls = @(
            @('update.ps1', @{ Id = 'S0001'; Status = 'In Progress' }),
            @('bulk-update.ps1', @{ Id = @('S0002'); Status = 'Partial' }),
            @('close.ps1', @{ Id = 'S0003'; Status = 'Archived'; Reason = 'not needed: x' }),
            @('archive.ps1', @{ Id = 'S0004'; Reason = 'not needed: y' })
        )
        foreach ($call in $calls) {
            $r = Invoke-Script $call[0] $call[1]
            Assert-Equal $r.code 0 "$($call[0]): $($r.out)"
            Assert-Mirrored ([string]@($call[1].Id)[0])
        }
    }

    Run-Case 'drift: an edited header is reported and rewritten from the ledger by the status tool' {
        $spec = Join-Path $repo 'PLAN\S0001_t.md'
        Write-Utf8 $spec ([IO.File]::ReadAllText($spec).Replace('**Status:** In Progress', '**Status:** Verified'))
        $r = Invoke-Script 'drift-check.ps1' @{ Id = 'S0001'; Format = 'json' }
        $drift = ($r.out -split "`r?`n" | Where-Object { $_.StartsWith('{') } | Select-Object -First 1) | ConvertFrom-Json
        Assert-Equal $drift.header_mismatch 'True' "drift-check: $($r.out)"
        Assert-Equal $drift.header_status 'Verified' 'the reported header status'
        $r = Invoke-Script 'validate.ps1' @{}
        Assert-That ($r.out -match 'HeaderStatus\s+spec header differs[^\r\n]*S0001: header Verified, ledger In Progress') "validate: $($r.out)"
        $r = Invoke-Script 'update.ps1' @{ Id = 'S0001'; Status = 'In Progress' }
        Assert-Equal $r.code 0 "the repair: $($r.out)"
        Assert-Mirrored 'S0001'
    }
}
finally {
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
    else { Write-Host "scratch kept: $scratch" }
}

Write-Host ''
Write-Host ("run={0} passed={1} failed={2}" -f $run, $passed, $failed)
if ($failed -gt 0) { exit 1 }
exit 0
