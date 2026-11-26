#requires -Version 7.0
<#
.SYNOPSIS
  CANONR-0211, TASK-FLOW 0.52 rule 17: every catalog path into Archived asks for a one-line reason and keeps it, and
  a row archived before the rule stays valid. Harness scripts run in this process (child processes only where the
  scripts start their own), against a throwaway repository under the system temp directory.
.DESCRIPTION
  Cases:
    log path   - close-and-log.ps1 -Status Archived without a note stops before any write; with one the row keeps it
    refusals   - archive.ps1, update.ps1, close.ps1, complete.ps1, bulk-update.ps1 and delete.ps1 refuse an entry
                 with no reason or a bad one (free text, the ticket itself, an unproven shipment, two lines), and the
                 row stays as it was
    accepted   - each of those paths archives with a reason, keeps it in statusNote and in the spec header; delete.ps1
                 keeps the other fields of the row
    historical - an archived row with no reason is re-written without one, and a bad note on it is refused
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

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('archive-reason-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
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
function Release-LeakedLock {
    # A refused write ends its script while it holds the catalog mutex; a real run releases it with its process.
    $hash = [BitConverter]::ToString([Security.Cryptography.MD5]::HashData([Text.Encoding]::UTF8.GetBytes($repo.ToLowerInvariant()))).Replace('-', '')
    $mutex = $null
    if (-not [Threading.Mutex]::TryOpenExisting("Global\FMS-SpecCatalog-$hash", [ref] $mutex)) { return }
    while ($true) { try { $mutex.ReleaseMutex() } catch { break } }
    $mutex.Dispose()
}
function Invoke-Script([string] $Name, [hashtable] $Parameters) {
    $global:LASTEXITCODE = 0
    try { $out = & (Join-Path $Catalog $Name) @Parameters *>&1 | Out-String -Width 400; $code = $global:LASTEXITCODE }
    catch { $out = $_.Exception.Message; $code = 1 }
    Release-LeakedLock
    return @{ code = $code; out = $out }
}
function Get-Row([string] $Id) {
    foreach ($file in 'spec-catalog.jsonl', 'spec-catalog-archive.jsonl') {
        foreach ($line in [IO.File]::ReadAllLines((Join-Path $repo "PLAN\$file"))) {
            if ($line) { $row = $line | ConvertFrom-Json; if ($row.id -ceq $Id) { return $row } }
        }
    }
    throw "no row $Id"
}
function Get-Note([string] $Id) { $p = (Get-Row $Id).PSObject.Properties['statusNote']; if ($p) { return [string]$p.Value } return '' }
function Assert-Mirrored([string] $Id) {
    $row = Get-Row $Id
    $text = [IO.File]::ReadAllText((Join-Path $repo $row.file))
    Assert-That ($text -match "(?m)^\*\*Status:\*\* $([regex]::Escape($row.status))\r?$") "$Id header does not say $($row.status): $text"
    $note = Get-Note $Id
    if ($note) { Assert-That ($text.Contains("**Status note:** $note")) "$Id header does not carry the note '$note': $text" }
}

try {
    foreach ($k in $pinned.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $pinned[$k]) }
    Write-Utf8 (Join-Path $repo '.sza-profile.json') '{}'
    $rows = foreach ($n in 1..9) {
        $id = 'S{0:d4}' -f $n
        Write-Utf8 (Join-Path $repo "PLAN\${id}_t.md") "# ${id}_t`n`n**Status:** Draft`n"
        $row = [ordered]@{ id = $id; name = "t$n"; status = 'Draft'; priority = 50; file = "PLAN/${id}_t.md"; created = '2026-11-01'; updated = '2026-11-01 10:00' }
        if ($n -eq 7) { $row['formerIds'] = @('S0700') }
        $row | ConvertTo-Json -Compress
    }
    Write-Utf8 (Join-Path $repo 'PLAN\spec-catalog.jsonl') (($rows -join "`n") + "`n")
    Write-Utf8 (Join-Path $repo 'PLAN\archive\S0010_old.md') "# S0010_old`n`n**Status:** Archived`n"
    Write-Utf8 (Join-Path $repo 'PLAN\spec-catalog-archive.jsonl') ('{"id":"S0010","name":"old","status":"Archived","priority":0,"file":"PLAN/archive/S0010_old.md","created":"2026-01-01","updated":"2026-01-02 10:00"}' + "`n")

    Run-Case 'log path: close-and-log without a note stops before any write; with one the row keeps it' {
        $r = Invoke-Script 'close-and-log.ps1' @{ Id = 'S0006'; Status = 'Archived'; SkipCatalogSync = $true; SkipFuncLog = $true }
        Assert-Equal $r.code 2 "no note: $($r.out)"
        Assert-Equal (Get-Row 'S0006').status 'Draft' 'the row after the refusal'
        $r = Invoke-Script 'close-and-log.ps1' @{ Id = 'S0006'; Status = 'Archived'; StatusNote = 'done in S0001'; SkipCatalogSync = $true; SkipFuncLog = $true }
        Assert-Equal $r.code 0 "with a note: $($r.out)"
        Assert-Equal (Get-Note 'S0006') 'done in S0001' 'the kept reason'
        Assert-Mirrored 'S0006'
    }

    Run-Case 'refusals: every path refuses no reason and a bad one, and the row stays' {
        $calls = @(
            @('archive.ps1', @{ Id = 'S0001' }, 'no reason'),
            @('archive.ps1', @{ Id = 'S0001'; Reason = 'cleanup' }, 'not an archive reason'),
            @('archive.ps1', @{ Id = 'S0001'; FromShipment = $true }, 'no shipment'),
            @('update.ps1', @{ Id = 'S0002'; Status = 'Archived' }, 'no reason'),
            @('update.ps1', @{ Id = 'S0002'; Status = 'Archived'; StatusNote = 'duplicate of S0002' }, 'names the ticket itself'),
            @('close.ps1', @{ Id = 'S0003'; Status = 'Archived' }, 'no reason'),
            @('close.ps1', @{ Id = 'S0003'; Status = 'Archived'; Reason = 'shipped in v9.9 (release 1)' }, 'no shipment'),
            @('complete.ps1', @{ Id = 'S0004'; Status = 'Archived'; SkipValidate = $true }, 'no reason'),
            @('bulk-update.ps1', @{ Id = @('S0005'); Status = 'Archived' }, 'no reason'),
            @('bulk-update.ps1', @{ Id = @('S0005'); Status = 'Archived'; StatusNote = "not needed: a`nb" }, 'one line'),
            @('delete.ps1', @{ Id = 'S0007'; Confirm = $true }, 'no reason')
        )
        foreach ($call in $calls) {
            $r = Invoke-Script $call[0] $call[1]
            Assert-That ($r.code -ne 0) "$($call[0]) accepted '$($call[2])': $($r.out)"
            Assert-That ($r.out -match [regex]::Escape($call[2])) "$($call[0]) does not say '$($call[2])': $($r.out)"
            Assert-Equal (Get-Row ([string]@($call[1].Id)[0])).status 'Draft' "the row after $($call[0])"
        }
    }

    Run-Case 'accepted: every path archives with a reason, keeps it and mirrors it' {
        $calls = @(
            @('archive.ps1', @{ Id = 'S0001'; Reason = 'not needed: superseded' }, 'not needed: superseded'),
            @('update.ps1', @{ Id = 'S0002'; Status = 'Archived'; StatusNote = 'duplicate of S0003' }, 'duplicate of S0003'),
            @('close.ps1', @{ Id = 'S0003'; Status = 'Archived'; Reason = 'done in canon:CANONR-0001' }, 'done in canon:CANONR-0001'),
            @('complete.ps1', @{ Id = 'S0004'; Status = 'Archived'; Reason = 'done in S0001'; SkipValidate = $true }, 'done in S0001'),
            @('bulk-update.ps1', @{ Id = @('S0005'); Status = 'Archived'; StatusNote = 'not needed: batch' }, 'not needed: batch'),
            @('delete.ps1', @{ Id = 'S0007'; Confirm = $true; Reason = 'not needed: probe' }, 'not needed: probe')
        )
        foreach ($call in $calls) {
            $id = [string]@($call[1].Id)[0]
            $r = Invoke-Script $call[0] $call[1]
            Assert-Equal $r.code 0 "$($call[0]): $($r.out)"
            Assert-Equal (Get-Row $id).status 'Archived' "the row after $($call[0])"
            Assert-Equal (Get-Note $id) $call[2] "the reason after $($call[0])"
            Assert-Mirrored $id
        }
        Assert-Equal @((Get-Row 'S0007').formerIds)[0] 'S0700' 'delete.ps1 dropped a field of the row'
    }

    Run-Case 'historical: an archived row without a reason is re-written without one; a bad note is refused' {
        $r = Invoke-Script 'update.ps1' @{ Id = 'S0010'; Status = 'Archived' }
        Assert-Equal $r.code 0 "re-writing the old row: $($r.out)"
        Assert-Equal (Get-Note 'S0010') '' 'a reason appeared from nowhere'
        $r = Invoke-Script 'update.ps1' @{ Id = 'S0010'; StatusNote = 'old stuff' }
        Assert-That ($r.code -ne 0) "a bad note was accepted: $($r.out)"
        Assert-Equal (Get-Note 'S0010') '' 'the bad note was written'
    }
}
finally {
    Release-LeakedLock
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
    else { Write-Host "scratch kept: $scratch" }
}

Write-Host ''
Write-Host ("run={0} passed={1} failed={2}" -f $run, $passed, $failed)
if ($failed -gt 0) { exit 1 }
exit 0
