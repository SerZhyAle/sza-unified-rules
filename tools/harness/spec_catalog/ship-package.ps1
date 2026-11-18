<#
.SYNOPSIS
    Ship the finished rows of the release plan, then archive what is fully done (TASK-FLOW rule 16, steps 2 and 3).
.DESCRIPTION
    Run once per release, after the release is proven live: by the release skill (Phase 8) and by the canon's own
    deploy. It edits no file itself: it calls release-queue.ps1 -Ship for every numbered package up to the marker
    that has ready rows, puts the marker on the next package, then calls archive.ps1 for every Verified ledger row
    that is in neither plan file any more. Rows under the unscheduled heading or a later package stay and are counted.
    -Version is stamped on each shipped block; -Release names the package the release closes (default: the marker
    of the queue file); -DryRun changes nothing. The marker never ends below where it stood.
    Exit codes: 0 shipped, or nothing was ready; 1 a ship or an archive call failed (named in the output);
    2 cannot verify - no queue file, no ready file, or no numeric current-next-release marker.
#>
[CmdletBinding()]
param([string] $Version = '', [string] $Release = '', [switch] $DryRun)

. (Join-Path $PSScriptRoot '..\_profile.ps1')
trap { Write-Host $_ -ForegroundColor Red; exit 1 }
. (Join-Path $PSScriptRoot '_lib.ps1')

$pwsh = if ([Environment]::ProcessPath) { [Environment]::ProcessPath } else { 'pwsh' }
$queueTool = Join-Path $PSScriptRoot 'release-queue.ps1'
$archiveTool = Join-Path $PSScriptRoot 'archive.ps1'
if (-not (Test-Path -LiteralPath (Get-ReleaseQueuePath))) {
    Write-Output "ship-package: no queue file at $(Get-SzaPath 'releaseQueue' -Relative) - nothing shipped"; exit 2
}
if (-not (Test-Path -LiteralPath (Get-ReleaseReadyPath))) {
    Write-Output "ship-package: no ready file at $(Get-SzaPath 'releaseReady' -Relative) - nothing shipped"; exit 2
}
$fileMarker = [string](Get-CurrentRelease)
$marker = if ($Release) { $Release } else { $fileMarker }
if ($marker -notmatch '^\d+$') {
    Write-Output "ship-package: no numeric current-next-release marker (got '$marker') - nothing shipped"; exit 2
}
$markerNo = [int]$marker
$fileNo = if ($fileMarker -match '^\d+$') { [int]$fileMarker } else { -1 }
$nextNo = [Math]::Max($markerNo + 1, $fileNo)
function Set-PackageMarker([int] $To) {
    & $pwsh -NoProfile -File $queueTool -SetCurrent $To | ForEach-Object { Write-Output "$_" }
    if ($LASTEXITCODE -ne 0) { Write-Output "ship-package: the marker was not set to $To - set it by hand" }
}

    # A row keeps its package when it crosses into the ready file, so a row that finished after its package
    # shipped sits under an earlier number: every numbered package up to the marker is shipped.
$toShip = @{}
$stay = 0
$readyLines = Read-ReleaseReady
foreach ($line in $readyLines) {
    if ($line.Kind -ne 'ticket') { continue }
    $package = [string]$line.Release
    if ($package -match '^\d+$' -and [int]$package -le $markerNo) { $toShip[$package] = $true } else { $stay++ }
}
$packages = @($toShip.Keys | Sort-Object { [int]$_ })
$lastShipped = -1
foreach ($package in $packages) {
    $argv = @('-NoProfile', '-File', $queueTool, '-Ship', '-Release', $package)
    if ($Version) { $argv += @('-Version', $Version) }
    if ($DryRun) { $argv += '-DryRun' }
    & $pwsh @argv | ForEach-Object { Write-Output "$_" }
    if ($LASTEXITCODE -ne 0) {
        Write-Output "ship-package: release-queue -Ship -Release $package exited $LASTEXITCODE - stopped before the archive sweep"
        # -Ship of an earlier package left the marker below where it stood: put it back before leaving.
        if (-not $DryRun -and $fileNo -ge 0 -and $lastShipped -ge 0 -and ($lastShipped + 1) -ne $fileNo) { Set-PackageMarker $fileNo }
        exit 1
    }
    $lastShipped = [int]$package
}
if ($packages.Count -eq 0) { Write-Output "ship-package: nothing ready in package $marker or earlier" }
if ($stay -gt 0) { Write-Output "ship-package: $stay ready row(s) stay (unscheduled, or a package after $marker)" }
    # -Ship leaves the marker one above the package it moved; the release closes the marker's package, so the
    # marker goes to the next one - or stays where the file had it when that is further on.
if ($lastShipped -ge 0 -and $fileNo -ge 0) {
    if ($DryRun) { Write-Output "ship-package: DRY RUN - the marker would go to $nextNo" }
    elseif (($lastShipped + 1) -ne $nextNo) { Set-PackageMarker $nextNo }
}

    # The sweep takes only what the plan files no longer hold, so it can never drop a row that has not shipped.
$planned = @{}
$queueLines = Read-ReleaseQueue
foreach ($line in $queueLines) { if ($line.Kind -eq 'ticket') { $planned[[string]$line.Id] = $true } }
$readyNow = Read-ReleaseReady
foreach ($line in $readyNow) {
    if ($line.Kind -ne 'ticket') { continue }
    if ($DryRun -and $toShip.ContainsKey([string]$line.Release)) { continue }
    $planned[[string]$line.Id] = $true
}
$ids = New-Object System.Collections.Generic.List[string]
$records = Read-Catalog
foreach ($record in $records) {
    if ([string]$record.status -eq 'Verified' -and -not $planned.ContainsKey([string]$record.id)) { $ids.Add([string]$record.id) }
}
if ($ids.Count -eq 0) { Write-Output 'ship-package: no shipped Verified ticket to archive'; exit 0 }
if ($DryRun) {
    Write-Output ("ship-package: DRY RUN - would archive {0} Verified ticket(s): {1}" -f $ids.Count, ($ids -join ', ')); exit 0
}
& $pwsh -NoProfile -File $archiveTool -Id ($ids -join ',') | ForEach-Object { Write-Output "$_" }
if ($LASTEXITCODE -ne 0) {
    Write-Output "ship-package: archive exited $LASTEXITCODE - the ids it names as failed stay in the ledger"; exit 1
}
Write-Output ("ship-package: archived {0} Verified ticket(s)" -f $ids.Count)
exit 0
