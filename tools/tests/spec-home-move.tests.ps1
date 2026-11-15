#requires -Version 7.0
<#
.SYNOPSIS
    TASK-FLOW rule 70 (S0076): a finished ticket's spec file follows its status into the archive directory.

.DESCRIPTION
    One throwaway repository (PLAN/ and PLAN/DONE/, a profile that declares both) and the real harness of this
    tree. Move-SpecToStatusHome is called in-process; update.ps1 and archive.ps1 run once each as real children.
    Cases:

      1. Implemented, Verified and BlockNeedUserTest move the spec file and its folder into the archive directory
         and return the new `file`.
      2. A move out of the ready set to an open status moves them back; a move to Archived moves nothing.
      3. An open status, a file already at home and a file outside the top level of the folder it would leave move
         nothing and say nothing.
      4. A name collision, a missing file and a pattern the profile does not admit leave the file in place with a
         reason; an alternate-catalog run does the same.
      5. A repository whose archive directory is its specs directory is left alone.
      6. update.ps1 -Status Implemented moves the file, writes the row's `file` and the header, and the status change
         stands.
      7. A status the gates refuse (Verified with no audit block) moves nothing.
      8. archive.ps1 on a ticket already in the archive directory keeps the file and records the same path.

    Three pwsh children, 4.97 s measured on 2026-11-15 - at the 5-second line, so it is run by name and is not in the
    fast list. -KeepScratch leaves the repository for inspection.
#>
[CmdletBinding()]
param([switch] $KeepScratch)

$harness = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\harness'))
$update = Join-Path $harness 'spec_catalog\update.ps1'
$archive = Join-Path $harness 'spec_catalog\archive.ps1'

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('spec-home-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$repo = Join-Path $scratch 'r'
$saved = @{}
foreach ($n in 'SZA_PROJECT_ROOT', 'SZA_PROFILE_PATH', 'SZA_SPEC_CATALOG_DIR', 'SZA_BLOCK_LINKS') { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }

function Write-Profile([string] $ArchiveDir) {
    $p = [ordered]@{
        version = '1'; projectName = 'scratch'; envPrefix = 'SZA'
        paths   = [ordered]@{ specsDir = 'PLAN'; specArchiveDir = $ArchiveDir }
        grammar = [ordered]@{ specFilePattern = '^PLAN/(DONE/)?S\d{4}_(?!spec_)' }
        probes  = [ordered]@{ enabled = $false }
    }
    [IO.File]::WriteAllText((Join-Path $repo '.sza-profile.json'), ($p | ConvertTo-Json -Depth 5))
    $script:SzaProfileCache = $null
}
function New-Spec([string] $Id, [string] $Status, [switch] $WithFolder, [string] $Dir = 'PLAN') {
    New-Item -ItemType Directory -Path (Join-Path $repo $Dir) -Force | Out-Null
    $rel = "$Dir/${Id}_t.md"
    [IO.File]::WriteAllText((Join-Path $repo $rel), "# Spec: $Id - t`n`n**Status:** $Status`n`n## 1. Problem`n`nText.`n")
    if ($WithFolder) {
        New-Item -ItemType Directory -Path (Join-Path $repo "$Dir/${Id}_t") -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $repo "$Dir/${Id}_t/INDEX.md"), "index`n")
    }
    return [pscustomobject]@{ id = $Id; status = $Status; file = $rel }
}
function Test-At([string] $Rel) { Test-Path -LiteralPath (Join-Path $repo $Rel) }

try {
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    $env:SZA_PROJECT_ROOT = $repo; $env:SZA_PROFILE_PATH = $null; $env:SZA_SPEC_CATALOG_DIR = $null; $env:SZA_BLOCK_LINKS = '0'
    Write-Profile 'PLAN/DONE'
    . (Join-Path $harness 'spec_catalog\_lib.ps1')

    Run-Case 'the three ready statuses move the file and its folder' {
        foreach ($s in 'Implemented', 'Verified', 'BlockNeedUserTest') {
            $id = 'S1' + (100 + [array]::IndexOf(@('Implemented', 'Verified', 'BlockNeedUserTest'), $s))
            $r = New-Spec $id 'In Progress' -WithFolder
            $m = Move-SpecToStatusHome -Record $r -OldStatus 'In Progress' -NewStatus $s
            Assert-That $m.moved "$s : not moved ($($m.note))"
            Assert-That ($m.file -ceq "PLAN/DONE/${id}_t.md") "$s : file is '$($m.file)'"
            Assert-That ((Test-At "PLAN/DONE/${id}_t.md") -and (Test-At "PLAN/DONE/${id}_t/INDEX.md")) "$s : file or folder missing in DONE"
            Assert-That (-not (Test-At "PLAN/${id}_t.md") -and -not (Test-At "PLAN/${id}_t")) "$s : left behind in PLAN"
        }
    }

    Run-Case 'leaving the ready set for an open status moves them back; Archived moves nothing' {
        $r = New-Spec 'S1200' 'Verified' -WithFolder -Dir 'PLAN/DONE'
        $m = Move-SpecToStatusHome -Record $r -OldStatus 'BlockNeedUserTest' -NewStatus 'In Progress'
        Assert-That ($m.moved -and $m.file -ceq 'PLAN/S1200_t.md') "back move: moved=$($m.moved) file=$($m.file) note=$($m.note)"
        Assert-That ((Test-At 'PLAN/S1200_t.md') -and (Test-At 'PLAN/S1200_t/INDEX.md') -and -not (Test-At 'PLAN/DONE/S1200_t.md')) 'back move: wrong places'
        $r2 = New-Spec 'S1201' 'Verified' -Dir 'PLAN/DONE'
        $m2 = Move-SpecToStatusHome -Record $r2 -OldStatus 'Verified' -NewStatus 'Archived'
        Assert-That (-not $m2.moved -and -not $m2.note -and (Test-At 'PLAN/DONE/S1201_t.md')) "Archived: moved=$($m2.moved) note=$($m2.note)"
    }

    Run-Case 'open status, file already home and file elsewhere move nothing, silently' {
        $r = New-Spec 'S1300' 'Draft'
        $m = Move-SpecToStatusHome -Record $r -OldStatus 'Draft' -NewStatus 'Approved'
        Assert-That (-not $m.moved -and -not $m.note -and (Test-At 'PLAN/S1300_t.md')) "open: moved=$($m.moved) note=$($m.note)"
        $r2 = New-Spec 'S1301' 'Verified' -Dir 'PLAN/DONE'
        $m2 = Move-SpecToStatusHome -Record $r2 -OldStatus 'Implemented' -NewStatus 'Verified'
        Assert-That (-not $m2.moved -and -not $m2.note) "already home: moved=$($m2.moved) note=$($m2.note)"
        $r3 = New-Spec 'S1302' 'In Progress' -Dir 'PLAN/sub'
        $m3 = Move-SpecToStatusHome -Record $r3 -OldStatus 'In Progress' -NewStatus 'Verified'
        Assert-That (-not $m3.moved -and -not $m3.note -and (Test-At 'PLAN/sub/S1302_t.md')) "elsewhere: moved=$($m3.moved) note=$($m3.note)"
    }

    Run-Case 'collision, missing file, unadmitted pattern and an alternate catalog leave the file with a reason' {
        $r = New-Spec 'S1400' 'In Progress'
        [IO.File]::WriteAllText((Join-Path $repo 'PLAN/DONE/S1400_t.md'), 'older')
        $m = Move-SpecToStatusHome -Record $r -OldStatus 'In Progress' -NewStatus 'Verified'
        Assert-That (-not $m.moved -and $m.note -like '*already exists*' -and (Test-At 'PLAN/S1400_t.md')) "collision: moved=$($m.moved) note=$($m.note)"
        Assert-That (([IO.File]::ReadAllText((Join-Path $repo 'PLAN/DONE/S1400_t.md'))) -ceq 'older') 'collision: the file in DONE was overwritten'

        $ghost = [pscustomobject]@{ id = 'S1401'; status = 'In Progress'; file = 'PLAN/S1401_t.md' }
        $m2 = Move-SpecToStatusHome -Record $ghost -OldStatus 'In Progress' -NewStatus 'Verified'
        Assert-That (-not $m2.moved -and $m2.note -like '*does not exist*') "missing: moved=$($m2.moved) note=$($m2.note)"

        $r3 = New-Spec 'S1402' 'In Progress'
        $savedPattern = $script:FilePattern
        $script:FilePattern = '^PLAN/S\d{4}_(?!spec_)'
        try { $m3 = Move-SpecToStatusHome -Record $r3 -OldStatus 'In Progress' -NewStatus 'Verified' } finally { $script:FilePattern = $savedPattern }
        Assert-That (-not $m3.moved -and $m3.note -like '*specFilePattern*' -and (Test-At 'PLAN/S1402_t.md')) "pattern: moved=$($m3.moved) note=$($m3.note)"

        $r4 = New-Spec 'S1403' 'In Progress'
        $env:SZA_SPEC_CATALOG_DIR = $scratch
        try { $m4 = Move-SpecToStatusHome -Record $r4 -OldStatus 'In Progress' -NewStatus 'Verified' } finally { $env:SZA_SPEC_CATALOG_DIR = $null }
        Assert-That (-not $m4.moved -and $m4.note -like '*alternate catalog*' -and (Test-At 'PLAN/S1403_t.md')) "alternate: moved=$($m4.moved) note=$($m4.note)"
    }

    Run-Case 'equal specs and archive directories are left alone' {
        Write-Profile 'PLAN'
        try {
            $r = New-Spec 'S1500' 'In Progress'
            $m = Move-SpecToStatusHome -Record $r -OldStatus 'In Progress' -NewStatus 'Verified'
            Assert-That (-not $m.moved -and -not $m.note -and (Test-At 'PLAN/S1500_t.md')) "equal: moved=$($m.moved) note=$($m.note)"
        } finally { Write-Profile 'PLAN/DONE' }
    }

    # The children below read the ledger, so it is written now with the tickets they act on.
    $rows = foreach ($t in @(@{ id = 'S1600'; status = 'Approved' }, @{ id = 'S1601'; status = 'Verified' }, @{ id = 'S1602'; status = 'Approved' })) {
        $dir = if ($t.status -eq 'Verified') { 'PLAN/DONE' } else { 'PLAN' }
        [void](New-Spec $t.id $t.status -WithFolder -Dir $dir)
        (@{ id = $t.id; name = 't'; status = $t.status; priority = 50; file = "$dir/$($t.id)_t.md"; created = '2026-11-15'; updated = '2026-11-15 10:00' } | ConvertTo-Json -Compress)
    }
    [IO.File]::WriteAllText((Join-Path $repo 'PLAN\spec-catalog.jsonl'), (($rows -join "`n") + "`n"))

    Run-Case 'update.ps1 -Status Implemented moves the file, writes `file` and keeps the status' {
        # Implemented is the one ready status no audit gate guards, so the real update.ps1 reaches the move with a bare spec.
        $env:SZA_PROJECT_ROOT = $repo
        $out = & pwsh -NoProfile -File $update -Id S1600 -Status Implemented 2>&1 | Out-String
        $code = $LASTEXITCODE
        Assert-That ($code -eq 0) "update exit $code : $($out.Trim())"
        Assert-That ($out -match 'S1600 Approved -> Implemented') "no status line: $($out.Trim())"
        Assert-That ((Test-At 'PLAN/DONE/S1600_t.md') -and (Test-At 'PLAN/DONE/S1600_t/INDEX.md') -and -not (Test-At 'PLAN/S1600_t.md')) 'file or folder not in DONE'
        $row = [IO.File]::ReadAllLines((Join-Path $repo 'PLAN\spec-catalog.jsonl')) | Where-Object { $_ -match '"S1600"' } | ForEach-Object { $_ | ConvertFrom-Json }
        Assert-That ($row.file -ceq 'PLAN/DONE/S1600_t.md' -and $row.status -ceq 'Implemented') "row: file=$($row.file) status=$($row.status)"
        $header = ([IO.File]::ReadAllText((Join-Path $repo 'PLAN/DONE/S1600_t.md')) -split "`n" | Where-Object { $_ -like '**Status:**' + '*' } | Select-Object -First 1)
        Assert-That ($header -match 'Implemented') "header not synced: '$header'"
    }

    Run-Case 'a status the gates refuse moves nothing' {
        # Verified needs a `## Last Audit` block, which this bare spec does not carry: the gate refuses before the move.
        $env:SZA_PROJECT_ROOT = $repo
        $out = & pwsh -NoProfile -File $update -Id S1602 -Status Verified 2>&1 | Out-String
        $code = $LASTEXITCODE
        Assert-That ($code -ne 0) "the gate did not refuse: $($out.Trim())"
        Assert-That ((Test-At 'PLAN/S1602_t.md') -and (Test-At 'PLAN/S1602_t/INDEX.md') -and -not (Test-At 'PLAN/DONE/S1602_t.md')) 'a refused status moved the file'
        $row = [IO.File]::ReadAllLines((Join-Path $repo 'PLAN\spec-catalog.jsonl')) | Where-Object { $_ -match '"S1602"' } | ForEach-Object { $_ | ConvertFrom-Json }
        Assert-That ($row.file -ceq 'PLAN/S1602_t.md' -and $row.status -ceq 'Approved') "row changed: file=$($row.file) status=$($row.status)"
    }

    Run-Case 'archive.ps1 keeps a file that is already in the archive directory' {
        $env:SZA_PROJECT_ROOT = $repo
        $out = & pwsh -NoProfile -File $archive -Id S1601 2>&1 | Out-String
        $code = $LASTEXITCODE
        Assert-That ($code -eq 0) "archive exit $code : $($out.Trim())"
        Assert-That ($out -match 'already there') "no 'already there' in: $($out.Trim())"
        Assert-That ((Test-At 'PLAN/DONE/S1601_t.md') -and (Test-At 'PLAN/DONE/S1601_t/INDEX.md') -and -not (Test-At 'PLAN/archive')) 'file moved or a second archive folder appeared'
        $arch = [IO.File]::ReadAllLines((Join-Path $repo 'PLAN\spec-catalog-archive.jsonl')) | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.id -ceq 'S1601' }
        Assert-That ($arch.file -ceq 'PLAN/DONE/S1601_t.md' -and $arch.status -ceq 'Archived') "archive row: file=$($arch.file) status=$($arch.status)"
    }
}
finally {
    foreach ($n in $saved.Keys) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) }
    if ($KeepScratch) { Write-Host "scratch kept: $scratch" }
    else { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ("run={0} passed={1} failed={2}" -f $run, $passed, $failed)
if ($failed -gt 0) { exit 1 }
exit 0
