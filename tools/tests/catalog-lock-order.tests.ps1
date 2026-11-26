#requires -Version 7.0
<#
.SYNOPSIS
  S0144: the order of the catalog lock and the portfolio projection. A catalog write that asks for the projection
  while it holds the lock must not start it under the lock; the release-queue writers that rewrite the plan files
  join the lock. Child processes of the harness's own scripts only, against a throwaway repository under the system
  temp directory.
.DESCRIPTION
  The projection is a `pq sync` child that may start insert.ps1 or update.ps1 (TASK-FLOW rules 65 and 68), and both
  take the catalog mutex. A process cannot win a lock its own parent holds, so under the lock every such grandchild
  waited the 30 s of Enter-CatalogLock and failed. The first case does not wait: it loads the real library in a
  child process and replaces the one function that starts the projection child with a recorder of the lock state.

  Cases:
    lock order - Sync-PortfolioProjection under the lock starts nothing; Exit-CatalogLock then runs it once with the
                 lock free; a second Exit-CatalogLock starts nothing; with no lock it runs at once; Write-Catalog
                 under the lock starts nothing and the release runs it; a child of the queue sync
                 (SZA_PQ_IN_SYNC=1) refreshes none
    ship       - release-queue.ps1 -Ship records an imported ready row as a shipment on its ledger row, advances the
                 marker and leaves the old ready and shipped files as they were
    plan files - release-queue.ps1 -SetCurrent and -Ship take the catalog lock (a text match on the two branches);
                 -SetCurrent still rewrites the marker (one real run)
    finished   - update.ps1 moving a Draft row to Implemented puts its package on the ledger row and writes no
                 ready file (S0150: the row was once dropped silently)
  Exit 0 when every case passed, 1 on any failure.
#>
[CmdletBinding()]
param([switch] $KeepScratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$Harness = Join-Path $SourceRoot 'tools\harness'
$pwshExe = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source

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

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('lock-order-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null

function Write-Utf8([string] $Path, [string] $Text) {
    $dir = [IO.Path]::GetDirectoryName($Path)
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
function New-Row([string] $Id, [string] $Name, [string] $File, [string] $Status = 'Draft') {
    return ([ordered]@{ id = $Id; name = $Name; status = $Status; priority = 50; file = $File; created = '2026-11-18'; updated = '2026-11-18 00:00' } | ConvertTo-Json -Compress)
}
function Invoke-Tool([string] $Root, [string] $Script, [string[]] $Arguments) {
    $psi = [Diagnostics.ProcessStartInfo]::new($pwshExe)
    foreach ($a in (@('-NoProfile', '-File', $Script) + $Arguments)) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $Root
    $psi.Environment['SZA_PROJECT_ROOT'] = $Root
    foreach ($n in 'SZA_PROFILE_PATH', 'SZA_SPEC_CATALOG_DIR', 'SZA_PQ_IN_SYNC', 'SZA_PQ_NO_PROJECTION', 'SZA_SKIP_RELEASE_QUEUE') { [void]$psi.Environment.Remove($n) }
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(60000)) { try { $p.Kill($true) } catch { } ; throw "$Script timed out" }
    $p.WaitForExit()
    return @{ code = $p.ExitCode; out = ([string]$o.Result + [string]$e.Result) }
}

try {
    $repo = Join-Path $scratch 'repo'
    Write-Utf8 (Join-Path $repo '.sza-profile.json') '{}'
    Write-Utf8 (Join-Path $repo 'PLAN\spec-catalog.jsonl') ((New-Row 'S0001' 'lock-order' 'PLAN/S0001_lock-order.md') + "`n")
    Write-Utf8 (Join-Path $repo 'PLAN\S0001_lock-order.md') "# S0001_lock-order`n`n**Status:** Draft`n"
    Write-Utf8 (Join-Path $repo 'PLAN\RELEASE_QUEUE.md') "# Release queue`r`n`r`ncurrent-next-release: 1`r`n"

    Run-Case 'lock order: a projection asked for under the catalog lock runs after the release, and not inside the queue sync child' {
        $probe = Join-Path $scratch 'lock-order-probe.ps1'
        Write-Utf8 $probe @'
param([Parameter(Mandatory)][string] $Lib)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. $Lib
$script:calls = New-Object System.Collections.Generic.List[string]
function Invoke-PortfolioProjectionChild {
    param([string] $ToolPath)
    $script:calls.Add($(if ($script:CatalogMutex) { 'held' } else { 'free' }))
    return @{ code = 0; out = '' }
}
$steps = [ordered]@{}
Enter-CatalogLock
Sync-PortfolioProjection
$steps['under-lock'] = $script:calls.Count
Exit-CatalogLock
$steps['after-exit'] = ($script:calls -join '+')
Exit-CatalogLock
$steps['second-exit'] = $script:calls.Count
Sync-PortfolioProjection
$steps['no-lock'] = $script:calls.Count
Enter-CatalogLock
$records = Read-Catalog
Write-Catalog -Records $records
$steps['write-under-lock'] = $script:calls.Count
Exit-CatalogLock
$steps['write-after-exit'] = $script:calls.Count
$env:SZA_PQ_IN_SYNC = '1'
Enter-CatalogLock
$records = Read-Catalog
Write-Catalog -Records $records
Exit-CatalogLock
$steps['in-sync-child'] = $script:calls.Count
$env:SZA_PQ_IN_SYNC = $null
$env:SZA_PQ_NO_PROJECTION = '1'
Enter-CatalogLock
$records = Read-Catalog
Write-Catalog -Records $records
Exit-CatalogLock
$steps['no-projection-child'] = $script:calls.Count
foreach ($k in $steps.Keys) { Write-Output ('{0}={1}' -f $k, $steps[$k]) }
'@
        $r = Invoke-Tool $repo $probe @((Join-Path $Harness 'spec_catalog\_lib.ps1'))
        Assert-Equal $r.code 0 "the probe: $($r.out)"
        $got = @{}
        foreach ($l in ($r.out -split "`r?`n")) { if ($l -match '^(?<k>[a-z-]+)=(?<v>.*)$') { $got[$Matches['k']] = $Matches['v'] } }
        Assert-Equal $got['under-lock'] '0' 'the projection must not start while the lock is held'
        Assert-Equal $got['after-exit'] 'free' 'the deferred projection runs once, with the lock free'
        Assert-Equal $got['second-exit'] '1' 'a second Exit-CatalogLock starts nothing'
        Assert-Equal $got['no-lock'] '2' 'with no lock held the projection runs at once'
        Assert-Equal $got['write-under-lock'] '2' 'Write-Catalog under the lock starts no projection'
        Assert-Equal $got['write-after-exit'] '3' 'the write''s projection runs when the lock is released'
        Assert-Equal $got['in-sync-child'] '3' 'a child of the queue sync (SZA_PQ_IN_SYNC=1) refreshes no projection'
        Assert-Equal $got['no-projection-child'] '3' 'a child of a campaign (SZA_PQ_NO_PROJECTION=1) refreshes no projection'
    }

    Run-Case 'ship: a row of an old ready file is imported, shipped onto its ledger row, and neither old file changes a byte' {
        $tool = Join-Path $Harness 'spec_catalog\release-queue.ps1'
        $readyPath = Join-Path $repo 'PLAN\RELEASE_READY.md'
        $queuePath = Join-Path $repo 'PLAN\RELEASE_QUEUE.md'
        $donePath = Join-Path $repo 'PLAN\RELEASE_QUEUE_DONE.md'

        # No shipped file at all - the first release of a project.
        Write-Utf8 (Join-Path $repo 'PLAN\spec-catalog.jsonl') ((New-Row 'S0002' 'ship-one' 'PLAN/S0002_ship-one.md' 'Implemented') + "`n")
        Write-Utf8 $readyPath "# Release ready`r`n`r`n1`r`nS0002_ship-one   26-11-18 12:00  Implemented`r`n"
        Write-Utf8 $queuePath "# Release queue`r`n`r`ncurrent-next-release: 1`r`n"
        $readyBefore = [IO.File]::ReadAllText($readyPath)
        $r = Invoke-Tool $repo $tool @('-Ship', '-Release', '1', '-Version', '1.0.0')
        Assert-Equal $r.code 0 "-Ship: $($r.out)"
        $row = [IO.File]::ReadAllText((Join-Path $repo 'PLAN\spec-catalog.jsonl')) | ConvertFrom-Json
        Assert-Equal @($row.shipments).Count 1 'the shipments of the row'
        Assert-Equal $row.shipments[0].version '1.0.0' 'the shipped version'
        Assert-Equal $row.shipments[0].changed '26-11-18 12:00' 'the row stamp travels with the shipment'
        Assert-That ($null -eq $row.PSObject.Properties['package']) 'the shipped row still carries a package'
        Assert-Equal ([IO.File]::ReadAllText($readyPath)) $readyBefore 'the old ready file'
        Assert-That (-not (Test-Path -LiteralPath $donePath)) 'a shipped file was created'
        Assert-That (([IO.File]::ReadAllText($queuePath)) -match '(?m)^current-next-release: 2\s*$') "the marker did not advance"
    }

    Run-Case 'plan files: release-queue.ps1 -SetCurrent and -Ship take the catalog lock, and -SetCurrent still rewrites the marker' {
        $tool = Join-Path $Harness 'spec_catalog\release-queue.ps1'
        $text = [IO.File]::ReadAllText($tool)
        foreach ($branch in 'SetCurrent', 'Ship') {
            $m = [regex]::Match($text, "(?s)'$branch' \{(?<body>.*?)\r?\n    \}\r?\n")
            Assert-That $m.Success "the $branch branch was not found"
            Assert-That ($m.Groups['body'].Value -match 'Enter-CatalogLock') "the $branch branch does not take the catalog lock"
        }
        $r = Invoke-Tool $repo $tool @('-SetCurrent', '4')
        Assert-Equal $r.code 0 "-SetCurrent: $($r.out)"
        $queue = [IO.File]::ReadAllText((Join-Path $repo 'PLAN\RELEASE_QUEUE.md'))
        Assert-That ($queue -match '(?m)^current-next-release: 4\s*$') "the marker was not rewritten: $queue"
    }

    Run-Case 'finished side: a row that finishes keeps its package on the ledger row and writes no ready file' {
        $tool = Join-Path $Harness 'spec_catalog\update.ps1'
        $readyPath = Join-Path $repo 'PLAN\RELEASE_READY.md'
        $queuePath = Join-Path $repo 'PLAN\RELEASE_QUEUE.md'
        Write-Utf8 (Join-Path $repo 'PLAN\spec-catalog.jsonl') `
            ((New-Row 'S0004' 'ready-file' 'PLAN/S0004_ready-file.md') + "`n")
        Write-Utf8 (Join-Path $repo 'PLAN\S0004_ready-file.md') "# S0004_ready-file`n`n**Status:** Draft`n"
        Write-Utf8 $queuePath "# Release queue`r`n`r`ncurrent-next-release: 1`r`n`r`n1`r`nS0004_ready-file   26-11-18 12:00  Draft`r`n"
        if (Test-Path -LiteralPath $readyPath) { Remove-Item -LiteralPath $readyPath -Force }

        $r = Invoke-Tool $repo $tool @('-Id', 'S0004', '-Status', 'Implemented')
        Assert-Equal $r.code 0 "update.ps1 to Implemented: $($r.out)"
        $row = [IO.File]::ReadAllText((Join-Path $repo 'PLAN\spec-catalog.jsonl')) | ConvertFrom-Json
        Assert-Equal $row.package '1' 'the package of the finished row'
        Assert-Equal $row.packageOrder 1 'its place on the finished side'
        Assert-That (-not (Test-Path -LiteralPath $readyPath)) 'a ready file was written'
        $queue = [IO.File]::ReadAllText($queuePath)
        Assert-That ($queue -notmatch 'S0004_ready-file') "the row is still in the queue file too: $queue"
    }
}
finally {
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
    else { Write-Host "scratch kept: $scratch" }
}

Write-Host ''
Write-Host ("run={0} passed={1} failed={2}" -f $run, $passed, $failed)
if ($failed -gt 0) { exit 1 }
exit 0
