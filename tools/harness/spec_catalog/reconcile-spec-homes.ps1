#requires -Version 7.0
<#
.SYNOPSIS
    Move existing finished and owner-test tickets to their configured archive without changing status.
.DESCRIPTION
    A dry run by default. -Apply uses the same move and citation repair as the status writers, holds the
    catalog lock, and writes the changed paths through the catalog writers. Archived rows stay in their
    archive journal; ready rows stay active. A ticket with a lease, a missing file or a destination
    collision is reported and left alone. The operation can be repeated after the obstruction is fixed.

    Exit 0 when every considered file is at home, 1 if any file could not be moved, 2 on a store error.
#>
[CmdletBinding()]
param([switch] $Apply, [switch] $Help)

. (Join-Path $PSScriptRoot '..\_profile.ps1')
if ($Help) { Show-SzaHelp $PSCommandPath; exit $LASTEXITCODE }
. (Join-Path $PSScriptRoot '_lib.ps1')

$problems = 0
$moved = 0
$already = 0
$missing = 0
$leased = 0
$pending = 0
$mode = if ($Apply) { 'APPLY' } else { 'DRY-RUN' }

try {
    if (Get-SzaEnv 'SPEC_CATALOG_DIR') { throw 'An alternate catalog cannot move the real specification files.' }
    $specs = [IO.Path]::GetFullPath((Get-SzaPath 'specsDir')).TrimEnd('\', '/')
    $archive = [IO.Path]::GetFullPath((Get-SzaPath 'specArchiveDir')).TrimEnd('\', '/')
    $archiveRel = ([string](Get-SzaPath 'specArchiveDir' -Relative) -replace '\\', '/').TrimEnd('/')
    $leaseDir = Get-SzaPath 'leasesDir'
    if ($specs -ieq $archive) { throw 'The specification and archive directories are the same.' }

    Enter-CatalogLock
    $activeRows = Read-Catalog
    $archiveRows = Read-JsonlFile -Path (Get-ArchivePath)
    foreach ($store in @(
        [pscustomobject]@{ Name = 'active'; Rows = $activeRows },
        [pscustomobject]@{ Name = 'archive'; Rows = $archiveRows }
    )) {
        $plans = [Collections.Generic.List[object]]::new()
        foreach ($row in $store.Rows) {
            if (-not (Test-ReleaseReadyStatus -Status ([string]$row.status)) -and $row.status -ne 'Archived') { continue }
            $path = [IO.Path]::GetFullPath((Resolve-SpecPath -PathRef ([string]$row.file)))
            $parent = [IO.Path]::GetDirectoryName($path).TrimEnd('\', '/')
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                Write-Host "MISSING $($row.id): $($row.file)"
                $missing++
                continue
            }
            if ($parent -ieq $archive) { $already++; continue }
            if ($parent -ine $specs) {
                Write-Host "SKIP $($row.id): $($row.file) is outside the configured specification directory"
                $problems++
                continue
            }
            if (Test-Path -LiteralPath (Join-Path $leaseDir "$($row.id).json") -PathType Leaf) {
                Write-Host "SKIP $($row.id): ticket has a lease"
                $leased++
                continue
            }
            $name = [IO.Path]::GetFileName($path)
            $destination = Join-Path $archive $name
            $folder = $path -replace '\.md$', ''
            $targetFolder = Join-Path $archive ([IO.Path]::GetFileName($folder))
            if (("$archiveRel/$name" -notmatch $script:FilePattern) -or
                (Test-Path -LiteralPath $destination) -or
                (($folder -ne $path) -and (Test-Path -LiteralPath $folder -PathType Container) -and
                    (Test-Path -LiteralPath $targetFolder))) {
                Write-Host "SKIP $($row.id): destination conflicts or the configured file pattern rejects it"
                $problems++
                continue
            }
            $plans.Add([pscustomobject]@{ Row = $row; OldFile = [string]$row.file })
        }
        if ($plans.Count -eq 0) { continue }
        # The writer validates every row. Check before any file moves, including the old archived rows.
        foreach ($row in $store.Rows) { Assert-Record -Record $row }
        $pending += $plans.Count
        if (-not $Apply) { continue }
        $done = [Collections.Generic.List[object]]::new()
        foreach ($plan in $plans) {
            # Archived is not a status transition here: ask the shared ready-home mover to do the same
            # housekeeping while the record itself keeps its Archived status and journal.
            $result = Move-SpecToStatusHome -Record $plan.Row -OldStatus 'In Progress' -NewStatus 'Implemented'
            if (-not $result.moved) {
                Write-Host "SKIP $($plan.Row.id): $($result.note)"
                $problems++
                continue
            }
            $plan.Row.file = $result.file
            $done.Add($plan)
            if ($result.note -match 'not rewritten') { Write-Host "WARN $($plan.Row.id): $($result.note)"; $problems++ }
        }
        if ($done.Count -eq 0) { continue }
        try {
            if ($store.Name -eq 'active') { Write-Catalog -Records ([object[]]$store.Rows) }
            else { Write-ArchiveCatalog -Records ([object[]]$store.Rows) }
            $moved += $done.Count
        }
        catch {
            # Do not leave a journal pointing to a file we just moved if its write failed.
            foreach ($plan in $done) {
                $rollback = Move-SpecToStatusHome -Record $plan.Row -OldStatus 'Implemented' -NewStatus 'In Progress'
                if (-not $rollback.moved) { Write-Host "ROLLBACK FAILED $($plan.Row.id): $($rollback.note)" }
                else { $plan.Row.file = $plan.OldFile }
            }
            throw
        }
    }
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    exit 2
}
finally { Exit-CatalogLock }

Write-Host "reconcile-spec-homes [$mode]: candidates=$pending moved=$moved already=$already missing=$missing leased=$leased other-problems=$problems"
if ($missing -gt 0 -or $leased -gt 0 -or $problems -gt 0) { exit 1 }
exit 0
