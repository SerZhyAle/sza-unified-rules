#requires -Version 7.0
<#
.SYNOPSIS
  CANONR-0211, TASK-FLOW 0.52 rules 14-16: package assignment and shipment history on the ticket ledger, the two views
  rendered from it, the one-way read of the old ready and shipped files, and the release sweep. Harness scripts run
  in this process (child processes only where the scripts start their own), against a throwaway repository under the
  system temp directory.
.DESCRIPTION
  The fixture is a ledger of seven active rows and one archived row, with a hand-kept ready file whose packages stand
  out of numeric order under an owner `#` line, and a shipped file holding package 1 twice, an archived ticket, a
  ticket shipped twice and one row that names no ledger ticket.

  Cases:
    conversion - -Show Ready and -Show Done keep package, row order, shipment membership, version, date, stamp and
                 status, answer the same on a second read, and write nothing
    persisted  - the first status write puts the facts on the rows (the archived one included); both views are
                 unchanged and neither old file changes a byte
    round trip - a reopened ticket returns to the queue at its package and comes back to its place
    ship       - -Ship records one shipment on the rows, newest block first, advances the marker; old files unchanged
    sweep      - ship-package.ps1 archives only a Verified ticket whose shipment names a version, with that reason;
                 an unplanned one and one shipped without a version stay
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

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('plan-ledger-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
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
function Add-Ticket([System.Collections.Generic.List[string]] $To, [string] $Id, [string] $Slug, [string] $Status, [string] $Dir = 'PLAN') {
    Write-Utf8 (Join-Path $repo "$Dir\${Id}_$Slug.md") "# ${Id}_$Slug`n`n**Status:** $Status`n"
    $To.Add(([ordered]@{ id = $Id; name = $Slug; status = $Status; priority = 50; file = "$Dir/${Id}_$Slug.md"; created = '2026-10-01'; updated = '2026-11-01 10:00' } | ConvertTo-Json -Compress))
}
function Invoke-Script([string] $Name, [hashtable] $Parameters) {
    $global:LASTEXITCODE = 0
    $out = & (Join-Path $Catalog $Name) @Parameters *>&1 | Out-String -Width 400
    return @{ code = $global:LASTEXITCODE; out = $out }
}
function Get-View([string] $Side) {
    $r = Invoke-Script 'release-queue.ps1' @{ Show = $Side }
    Assert-Equal $r.code 0 "-Show $Side : $($r.out)"
    return $r.out
}
function Get-Skeleton([string] $Text) {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($Text -split "`r?`n")) {
        $t = $line.Trim()
        if ($t -match '^(\d+|--)$' -or $t.StartsWith('#')) { $out.Add($t) }
        elseif ($t -match '^(S\d{4}_\S+)\s+(\S+ \S+)\s+(\S+)') { $out.Add("$($Matches[1]) $($Matches[2]) $($Matches[3])") }
    }
    return ($out -join '|')
}
function Get-Row([string] $Id) {
    foreach ($file in 'spec-catalog.jsonl', 'spec-catalog-archive.jsonl') {
        foreach ($line in [IO.File]::ReadAllLines((Join-Path $repo "PLAN\$file"))) {
            if ($line) { $row = $line | ConvertFrom-Json; if ($row.id -ceq $Id) { return $row } }
        }
    }
    throw "no row $Id"
}
function Get-Prop($Row, [string] $Name) { $p = $Row.PSObject.Properties[$Name]; if ($p) { return $p.Value } return $null }

try {
    foreach ($k in $pinned.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $pinned[$k]) }
    Write-Utf8 (Join-Path $repo '.sza-profile.json') '{}'
    $active = [System.Collections.Generic.List[string]]::new()
    $archive = [System.Collections.Generic.List[string]]::new()
    Add-Ticket $active 'S0001' 'one' 'Draft'
    Add-Ticket $active 'S0002' 'two' 'Implemented'
    Add-Ticket $active 'S0003' 'three' 'Verified'
    Add-Ticket $active 'S0004' 'four' 'BlockNeedUserTest'
    Add-Ticket $active 'S0005' 'five' 'Verified'
    Add-Ticket $active 'S0007' 'seven' 'Verified'
    Add-Ticket $active 'S0008' 'eight' 'Verified'
    Add-Ticket $archive 'S0006' 'six' 'Archived' 'PLAN/archive'
    Write-Utf8 (Join-Path $repo 'PLAN\spec-catalog.jsonl') (($active -join "`n") + "`n")
    Write-Utf8 (Join-Path $repo 'PLAN\spec-catalog-archive.jsonl') (($archive -join "`n") + "`n")
    $queuePath = Join-Path $repo 'PLAN\RELEASE_QUEUE.md'
    $readyPath = Join-Path $repo 'PLAN\RELEASE_READY.md'
    $donePath = Join-Path $repo 'PLAN\RELEASE_QUEUE_DONE.md'
    Write-Utf8 $queuePath "# Release Queue`r`ncurrent-next-release: 2`r`n`r`n2`r`nS0001_one   26-11-01 10:00  Draft`r`n"
    Write-Utf8 $readyPath "# Release Content (ready)`r`n`r`n3`r`nS0003_three   26-11-02 10:00  Verified`r`n2`r`n# wear group`r`nS0004_four   26-11-02 11:00  BlockNeedUserTest`r`nS0002_two   26-11-02 12:00  Implemented`r`n"
    Write-Utf8 $donePath (@(
        '# Shipped Release Packages', '', '## release 1 - v1.0.2 - 2026-11-01', '',
        'S0005_five   26-11-01 09:00  Verified', 'S0099_gone   26-11-01 09:30  Verified', '',
        '## release 1 - v1.0.1 - 2026-10-30', '',
        'S0006_six   26-10-30 09:00  Implemented', 'S0005_five   26-10-30 08:00  Implemented', '') -join "`r`n")
    $readyBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($readyPath))
    $doneBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($donePath))
    function Assert-OldFiles([string] $When) {
        Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes($readyPath))) $readyBytes "the old ready file $When"
        Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes($donePath))) $doneBytes "the old shipped file $When"
    }

    $readyExpected = '# Release Content (ready)|3|S0003_three 26-11-02 10:00 Verified|2|# wear group|S0004_four 26-11-02 11:00 BlockNeedUserTest|S0002_two 26-11-02 12:00 Implemented'
    $doneExpected = '# Shipped Release Packages|## release 1 - v1.0.2 - 2026-11-01|S0005_five 26-11-01 09:00 Verified|## release 1 - v1.0.1 - 2026-10-30|S0006_six 26-10-30 09:00 Implemented|S0005_five 26-10-30 08:00 Implemented|# rows that name no ledger ticket, kept in PLAN/RELEASE_QUEUE_DONE.md:|# release 1 - v1.0.2 - 2026-11-01 | S0099_gone'

    Run-Case 'conversion: both views keep package, order, membership, version and date, twice, and write nothing' {
        $ledgerBefore = [IO.File]::ReadAllText((Join-Path $repo 'PLAN\spec-catalog.jsonl'))
        foreach ($pass in 1, 2) {
            Assert-Equal (Get-Skeleton (Get-View 'Ready')) $readyExpected "the ready view, read $pass"
            Assert-Equal (Get-Skeleton (Get-View 'Done')) $doneExpected "the shipped view, read $pass"
        }
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $repo 'PLAN\spec-catalog.jsonl'))) $ledgerBefore 'a view wrote the ledger'
        Assert-OldFiles 'after the views'
    }

    Run-Case 'persisted: the first status write puts the facts on the rows; views and old files unchanged' {
        $r = Invoke-Script 'update.ps1' @{ Id = 'S0001'; Status = 'In Progress' }
        Assert-Equal $r.code 0 "update S0001: $($r.out)"
        Assert-Equal @(Get-Prop (Get-Row 'S0005') 'shipments').Count 2 'the shipments of a ticket shipped twice'
        Assert-Equal @(Get-Prop (Get-Row 'S0006') 'shipments').Count 1 'the shipments of the archived ticket'
        Assert-Equal (Get-Prop (Get-Row 'S0003') 'package') '3' 'the package of S0003'
        Assert-Equal (Get-Skeleton (Get-View 'Ready')) $readyExpected 'the ready view after the import'
        Assert-Equal (Get-Skeleton (Get-View 'Done')) $doneExpected 'the shipped view after the import'
        Assert-OldFiles 'after a status write'
    }

    Run-Case 'round trip: a reopened ticket returns to the queue at its package and comes back to its place' {
        $r = Invoke-Script 'update.ps1' @{ Id = 'S0002'; Status = 'In Progress' }
        Assert-Equal $r.code 0 "reopen S0002: $($r.out)"
        Assert-That ($null -eq (Get-Prop (Get-Row 'S0002') 'package')) 'the reopened row kept its plan fields'
        Assert-That (([IO.File]::ReadAllText($queuePath)) -match '(?ms)^2\r?$.*S0002_two\s+\S+ \S+\s+In Progress') 'S0002 is not in package 2 of the queue'
        $r = Invoke-Script 'update.ps1' @{ Id = 'S0002'; Status = 'Implemented' }
        Assert-Equal $r.code 0 "finish S0002: $($r.out)"
        Assert-That ((Get-Skeleton (Get-View 'Ready')) -match 'S0004_four [^|]+\|S0002_two [^|]+Implemented$') 'S0002 did not return after S0004'
        Assert-OldFiles 'after the round trip'
    }

    Run-Case 'ship: one shipment on the rows, newest block first, the marker advances, the old files stay' {
        $r = Invoke-Script 'release-queue.ps1' @{ Ship = $true; Release = '2'; Version = '2.0.0' }
        Assert-Equal $r.code 0 "-Ship: $($r.out)"
        $done = Get-Skeleton (Get-View 'Done')
        Assert-That ($done -match "^# Shipped Release Packages\|## release 2 - v2\.0\.0 - $(Get-Date -Format 'yyyy-MM-dd')\|S0004_four [^|]+\|S0002_two [^|]+\|## release 1 - v1\.0\.2") "the new block: $done"
        Assert-Equal (Get-Skeleton (Get-View 'Ready')) '# Release Content (ready)|3|S0003_three 26-11-02 10:00 Verified' 'the ready view after the ship'
        Assert-That (([IO.File]::ReadAllText($queuePath)) -match '(?m)^current-next-release: 3\r?$') 'the marker did not advance'
        Assert-OldFiles 'after the ship step'
    }

    Run-Case 'sweep: only a ticket whose shipment names a version is archived, with that reason' {
        # S0008 shipped by a step that named no version; S0007 was never planned.
        $path = Join-Path $repo 'PLAN\spec-catalog.jsonl'
        $lines = @([IO.File]::ReadAllLines($path) | ForEach-Object {
                if ($_ -match '"id":"S0008"') { $_.TrimEnd('}') + ',"shipments":[{"release":"1","block":1,"order":9,"title":"## release 1 - 2026-10-01","date":"2026-10-01","changed":"26-10-01 09:00","status":"Verified"}]}' } else { $_ } })
        Write-Utf8 $path (($lines -join "`n") + "`n")
        $r = Invoke-Script 'ship-package.ps1' @{ Release = '2'; Version = '2.0.1' }
        Assert-Equal $r.code 0 "ship-package: $($r.out)"
        Assert-That ($r.out -match '2 Verified ticket\(s\) stay[^\r\n]*S0007, S0008') "the unproven rows are not named: $($r.out)"
        $five = Get-Row 'S0005'
        Assert-Equal $five.status 'Archived' 'the proven ticket'
        Assert-Equal $five.statusNote 'shipped in v1.0.2 (release 1)' 'its reason'
        Assert-Equal @($five.shipments).Count 2 'its history after the archive'
        Assert-That (([IO.File]::ReadAllText((Join-Path $repo 'PLAN\archive\S0005_five.md'))) -match '(?m)^\*\*Status:\*\* Archived\r?\n\*\*Status note:\*\* shipped in v1\.0\.2') 'the header does not mirror the archived row'
        foreach ($id in 'S0003', 'S0007', 'S0008') { Assert-Equal (Get-Row $id).status 'Verified' "$id" }
        Assert-OldFiles 'after the sweep'
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
