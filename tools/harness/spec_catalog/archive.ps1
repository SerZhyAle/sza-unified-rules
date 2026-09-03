<#
.SYNOPSIS
    Archive one or more specs: move their files to PLAN/archive/ and flip the records to Archived.
.DESCRIPTION
    S2400: a list of ids is archived in ONE process under ONE catalog lock, with one archive-journal
    write and one active-journal write (hence one release-queue reconcile). The release step 12c used
    to call this once per id - 187 interpreter starts, 187 rewrites of the 2279-row archive journal
    and 187 reconciles for one identical end state, all of it waited for in the foreground.

    Every id is resolved BEFORE the first write (bulk-update.ps1's shape): an invalid or unknown id is
    reported and skipped, never allowed to abort the ids after it. Per-id failures inside the critical
    section are collected the same way. The summary line `ARCHIVED: n of N [| FAILED: ..]` is printed
    only for a multi-id call; a single-id call keeps its historical one-line output.

    `-Id` accepts an array or one comma-joined string: `pwsh -File` binds `-Id a,b` as ONE element
    and refuses separate elements as positional, so every caller crossing a process boundary sends
    the CSV form (S1184).

    Exit codes:
      0  every id archived.
      1  at least one id failed (invalid, not found, already archived with nothing left to move, or a
         move/journal error) - the failed ids are named in the output.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]] $Id
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')

# Under _lib.ps1's $ErrorActionPreference = 'Stop', Write-Error/throw raise
# terminating errors that abort the script before reaching `exit 1`. The trap
# below converts any such terminating error into a proper exit-1 contract,
# so callers can rely on $LASTEXITCODE.
trap {
    Write-Host $_ -ForegroundColor Red
    exit 1
}

. (Join-Path $PSScriptRoot '_lib.ps1')

$ids = @($Id | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
if ($ids.Count -eq 0) { throw "No id given (-Id must carry at least one S#### id)." }

$repoRoot = (Get-SzaProjectRoot)
# S1620: the archive is the only durable record of WHY a closed decision was made, so it
# lives under version control. It used to go to temp/done/, which is git-ignored and
# disposable - archiving therefore deleted the reasoning from every machine but this one.
# PLAN/ itself stays untracked; .gitignore re-includes PLAN/archive/ specifically.
# The folder sits beside the archive JOURNAL, so an alternate-catalog run (FMS_SPEC_CATALOG_DIR,
# S1534) moves fixture files into its own sandbox instead of the production PLAN/archive/.
$doneDir = Join-Path (Split-Path -Parent (Get-ArchivePath)) 'archive'
if (-not (Test-Path $doneDir)) {
    New-Item -ItemType Directory -Path $doneDir -Force | Out-Null
}
$doneLabel = ($doneDir.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/') + '/'

$planDir = Join-Path $repoRoot 'PLAN'
$lines   = [System.Collections.Generic.List[string]]::new()
$failed  = [System.Collections.Generic.List[string]]::new()
$plans   = [System.Collections.Generic.List[object]]::new()

# Phase 1: resolve every id and locate its artefacts before anything is touched.
foreach ($oneId in $ids) {
    if ($oneId -notmatch '^S\d{4}$') {
        $failed.Add($oneId); $lines.Add("${oneId}: invalid id (must match S####)."); continue
    }
    $record = Find-Record -Id $oneId
    if (-not $record) {
        $failed.Add($oneId); $lines.Add("${oneId}: record not found."); continue
    }

    $slug = $record.name
    # Prefer the catalog path because some specs were renamed after ticket creation.
    $recordFileRelative = if ($record.PSObject.Properties.Name -contains 'file' -and "$($record.file)" -ne '') {
        [string]$record.file
    } else {
        [string](Get-SzaProfileValue 'grammar.specFileTemplate') -f $oneId, $slug
    }
    $recordFilePath   = Join-Path $repoRoot ($recordFileRelative -replace '/', '\')
    $fallbackSpecFile = Join-Path $planDir "${oneId}_${slug}.md"

    $specFile = $null
    foreach ($candidate in @($recordFilePath, $fallbackSpecFile) | Select-Object -Unique) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $specFile = $candidate; break }
    }

    # Strip the extension to get the tactical folder path; ChangeExtension($p, $null)
    # yields "path." in PowerShell 7+ which then fails to resolve, so build it manually.
    $recordTacticalDir = Join-Path `
        ([System.IO.Path]::GetDirectoryName($recordFilePath)) `
        ([System.IO.Path]::GetFileNameWithoutExtension($recordFilePath))
    $fallbackTacticalDir = Join-Path $planDir "${oneId}_${slug}"
    $tacticalDirs = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in @($recordTacticalDir, $fallbackTacticalDir) | Select-Object -Unique) {
        if (Test-Path -LiteralPath $candidate -PathType Container) { $tacticalDirs.Add($candidate) }
    }

    if ($record.status -eq 'Archived' -and $null -eq $specFile -and $tacticalDirs.Count -eq 0) {
        $failed.Add($oneId); $lines.Add("${oneId}: already Archived."); continue
    }
    if ($record.status -eq 'Archived') {
        Write-Warning "$oneId is already Archived in the catalog; continuing to move remaining artefacts from $(Get-SzaPath 'specsDir' -Relative)/."
    }

    $plans.Add([pscustomobject]@{
        Id           = $oneId
        Record       = $record
        SpecFile     = $specFile
        SpecFileRel  = $recordFileRelative
        TacticalDirs = $tacticalDirs
    })
}

# Phase 2: one critical section for the whole list. S1437: read -> mutate -> write is one critical
# section; two processes holding the same snapshot lose one change entirely. Both journals are read
# once and written once - the per-id Add-ArchiveRecord path re-read and rewrote the whole archive
# journal for every id, which is what made the release sweep scale with the archive's size.
$archivedIds = [System.Collections.Generic.HashSet[string]]::new()
if ($plans.Count -gt 0) {
    Enter-CatalogLock
    try {
        $allRecords = [System.Collections.Generic.List[object]]::new()
        foreach ($r in (Read-Catalog)) { $allRecords.Add($r) }
        $activeById = @{}
        foreach ($r in $allRecords) { $activeById[[string]$r.id] = $r }

        # Keyed by id so re-archiving replaces the row instead of duplicating it (idempotent, as before).
        $archiveById = [ordered]@{}
        foreach ($r in (Read-JsonlFile -Path (Get-ArchivePath))) { $archiveById[[string]$r.id] = $r }

        foreach ($plan in $plans) {
            $oneId = $plan.Id
            try {
                $moved = [System.Collections.Generic.List[string]]::new()
                if ($null -ne $plan.SpecFile) {
                    # Set the in-file header to Archived before moving, so the artefact in
                    # PLAN/archive/ matches the journal (shared fail-soft helper, first line only).
                    [void](Sync-SpecHeaderStatus -PathRef $plan.SpecFile -Status 'Archived')
                    $specFileName = Split-Path -Path $plan.SpecFile -Leaf
                    Move-Item -LiteralPath $plan.SpecFile -Destination (Join-Path $doneDir $specFileName) -Force
                    $moved.Add($specFileName)
                } else {
                    Write-Warning "Strategic file not found in PLAN for '$($plan.SpecFileRel)' - skipping file move."
                }
                foreach ($tacticalDir in $plan.TacticalDirs) {
                    $tacticalDirName = Split-Path -Path $tacticalDir -Leaf
                    Move-Item -LiteralPath $tacticalDir -Destination (Join-Path $doneDir $tacticalDirName) -Force
                    $moved.Add("${tacticalDirName}/")
                }

                # When the id is no longer in the active journal (already moved to archive),
                # fall back to the record resolved earlier via Find-Record's archive fallback.
                $old = if ($activeById.ContainsKey($oneId)) { $activeById[$oneId] } else { $plan.Record }

                # S1620: record where the file actually IS, not where it used to be. Only rewrite when a
                # file was really moved: a record whose artefact was never found keeps its original path
                # rather than gaining a fabricated one.
                $archivedFileRef = [string]$old.file
                if ($null -ne $plan.SpecFile) {
                    $archivedFileRef = (Get-SzaPath 'specArchiveDir' -Relative) + '/' + (Split-Path -Path $plan.SpecFile -Leaf)
                }

                $archived = [pscustomobject]@{
                    id       = [string]$old.id
                    name     = [string]$old.name
                    status   = 'Archived'
                    priority = 0
                    file     = $archivedFileRef
                    created  = [string]$old.created
                    updated  = (Get-Now)
                }
                if ($old.PSObject.Properties.Name -contains 'tier' -and $null -ne $old.tier -and "$($old.tier)" -ne '') {
                    $archived | Add-Member -NotePropertyName 'tier' -NotePropertyValue ([int]$old.tier)
                }
                # 'statusNote' is dropped, not carried over: it describes what a Block* status is waiting
                # for, and Archived waits for nothing. Archiving straight from BlockQuestions used to freeze
                # a stale "owner decision needed" note into the archive journal forever (S1186).
                $fixedKeys = @('id','name','status','priority','tier','file','created','updated','statusNote')
                foreach ($prop in $old.PSObject.Properties) {
                    if ($fixedKeys -notcontains $prop.Name -and -not ($archived.PSObject.Properties.Name -contains $prop.Name)) {
                        $archived | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
                    }
                }
                Assert-Record -Record $archived

                $archiveById[$oneId] = $archived
                [void]$archivedIds.Add($oneId)
                $movedStr = if ($moved.Count -gt 0) { $moved -join ', ' } else { '(no files found)' }
                $lines.Add("$oneId archived [priority -> 0]. Moved: $movedStr -> $doneLabel")
            }
            catch {
                $failed.Add($oneId)
                $lines.Add("${oneId}: $($_.Exception.Message)")
            }
        }

        if ($archivedIds.Count -gt 0) {
            Write-ArchiveCatalog -Records ([object[]]@($archiveById.Values))
            $remaining = @($allRecords | Where-Object { -not $archivedIds.Contains([string]$_.id) })
            Write-Catalog -Records ([object[]]$remaining)
        }
    }
    finally {
        Exit-CatalogLock
    }
}

foreach ($line in $lines) { Write-Output $line }
if ($ids.Count -gt 1) {
    $tail = if ($failed.Count -gt 0) { ' | FAILED: ' + ($failed -join ', ') } else { '' }
    Write-Output ("ARCHIVED: $($archivedIds.Count) of $($ids.Count)$tail")
}
if ($failed.Count -gt 0) { exit 1 }
exit 0
