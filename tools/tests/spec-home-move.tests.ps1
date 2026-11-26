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
      9. (S0087) The dev-monitor's last-write reader finds the spec and folder of a moved ticket - through the archive
         directory, and through a ledger row's own directory - and still reads an active ticket and its scratch dir.

    Three pwsh children. -KeepScratch leaves the repository for inspection.
#>
[CmdletBinding()]
param([switch] $KeepScratch)

$harness = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\harness'))
$update = Join-Path $harness 'spec_catalog\update.ps1'
$archive = Join-Path $harness 'spec_catalog\archive.ps1'
$gate = Join-Path $harness 'spec_catalog\check-evidence-durable.ps1'
$planTick = Join-Path $harness 'spec_catalog\plan-tick.ps1'

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

    Run-Case 'S0084: the move rewrites the citations of the spec''s own old path in the moved files, and the way back restores them' {
        $r = New-Spec 'S1700' 'In Progress' -WithFolder
        New-Item -ItemType Directory -Path (Join-Path $repo 'PLAN/S1700_t/attachments') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $repo 'PLAN/S1700_t/attachments/a.txt'), 'evidence')
        $body = @(
            '# Spec: S1700 - t', '', '**Status:** In Progress', '',
            '## 0. Owner request (verbatim)', '', 'Verbatim: PLAN/S1700_t/attachments/a.txt and PLAN/S1700_t.md stay as written.', '',
            '## 1. Problem', '',
            'Evidence: PLAN/S1700_t/attachments/a.txt, spec PLAN/S1700_t.md.',
            'Decoys: PLAN/DONE/S1700_t/attachments/a.txt and sub/PLAN/S1700_t/x.txt and PLAN/S1700_tx/y.txt stay.', ''
        ) -join "`n"
        [IO.File]::WriteAllText((Join-Path $repo 'PLAN/S1700_t.md'), $body)
        [IO.File]::WriteAllText((Join-Path $repo 'PLAN/S1700_t/PHASE_01__x.md'), "Phase cites PLAN/S1700_t/attachments/a.txt`n")

        $m = Move-SpecToStatusHome -Record $r -OldStatus 'In Progress' -NewStatus 'Verified'
        Assert-That $m.moved "not moved: $($m.note)"
        Assert-That ($m.note -like '*3 citation(s)*') "note does not count the three rewrites: $($m.note)"
        $moved = [IO.File]::ReadAllText((Join-Path $repo 'PLAN/DONE/S1700_t.md'))
        Assert-That ($moved.Contains('Evidence: PLAN/DONE/S1700_t/attachments/a.txt, spec PLAN/DONE/S1700_t.md.')) 'section 1 citations not rewritten'
        Assert-That ($moved.Contains('Verbatim: PLAN/S1700_t/attachments/a.txt and PLAN/S1700_t.md stay as written.')) 'section 0 was rewritten'
        Assert-That ($moved.Contains('Decoys: PLAN/DONE/S1700_t/attachments/a.txt and sub/PLAN/S1700_t/x.txt and PLAN/S1700_tx/y.txt stay.')) 'a decoy was touched'
        Assert-That (([IO.File]::ReadAllText((Join-Path $repo 'PLAN/DONE/S1700_t/PHASE_01__x.md'))) -ceq "Phase cites PLAN/DONE/S1700_t/attachments/a.txt`n") 'phase file citation not rewritten'
        Assert-That (Test-At 'PLAN/DONE/S1700_t/attachments/a.txt') 'the cited attachment is not at the rewritten path'

        $r2 = [pscustomobject]@{ id = 'S1700'; status = 'Verified'; file = $m.file }
        $back = Move-SpecToStatusHome -Record $r2 -OldStatus 'Verified' -NewStatus 'In Progress'
        Assert-That $back.moved "back move failed: $($back.note)"
        $again = [IO.File]::ReadAllText((Join-Path $repo 'PLAN/S1700_t.md'))
        Assert-That ($again.Contains('Evidence: PLAN/S1700_t/attachments/a.txt, spec PLAN/S1700_t.md.')) 'the back move did not restore the citations'
        Assert-That ($again.Contains('sub/PLAN/S1700_t/x.txt and PLAN/S1700_tx/y.txt stay.')) 'the back move rewrote a decoy'
        Assert-That (Test-At 'PLAN/S1700_t/attachments/a.txt') 'the attachment did not come back with the folder'
    }

    Run-Case 'S0084: a refused move leaves the citations as they were' {
        $r = New-Spec 'S1701' 'In Progress' -WithFolder
        [IO.File]::WriteAllText((Join-Path $repo 'PLAN/S1701_t.md'), "# Spec: S1701 - t`n`n**Status:** In Progress`n`n## 1. Problem`n`nEvidence: PLAN/S1701_t/attachments/a.txt`n")
        [IO.File]::WriteAllText((Join-Path $repo 'PLAN/DONE/S1701_t.md'), 'older')
        $m = Move-SpecToStatusHome -Record $r -OldStatus 'In Progress' -NewStatus 'Verified'
        Assert-That (-not $m.moved -and $m.note -like '*already exists*') "collision did not refuse: moved=$($m.moved) note=$($m.note)"
        Assert-That (([IO.File]::ReadAllText((Join-Path $repo 'PLAN/S1701_t.md'))).Contains('Evidence: PLAN/S1701_t/attachments/a.txt')) 'a refused move rewrote the citation'
    }

    # The children below read the ledger, so it is written now with the tickets they act on.
    $rows = foreach ($t in @(@{ id = 'S1600'; status = 'Approved' }, @{ id = 'S1601'; status = 'Verified' }, @{ id = 'S1602'; status = 'Approved' })) {
        $dir = if ($t.status -eq 'Verified') { 'PLAN/DONE' } else { 'PLAN' }
        [void](New-Spec $t.id $t.status -WithFolder -Dir $dir)
        (@{ id = $t.id; name = 't'; status = $t.status; priority = 50; file = "$dir/$($t.id)_t.md"; created = '2026-11-15'; updated = '2026-11-15 10:00' } | ConvertTo-Json -Compress)
    }
    [IO.File]::WriteAllText((Join-Path $repo 'PLAN\spec-catalog.jsonl'), (($rows -join "`n") + "`n"))
    # S0084: S1600 cites a scratch file, so the closing path below runs relocation, the gate and the move end to end.
    New-Item -ItemType Directory -Path (Join-Path $repo 'temp/S1600') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $repo 'temp/S1600/note.txt'), 'scratch evidence')
    [IO.File]::AppendAllText((Join-Path $repo 'PLAN/S1600_t.md'), "`n## 4. Evidence`n`nVerdict: temp/S1600/note.txt`n")

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

    Run-Case 'S0084: relocation, the gate and the move together leave the cited attachment where the spec says' {
        $spec = [IO.File]::ReadAllText((Join-Path $repo 'PLAN/DONE/S1600_t.md'))
        Assert-That ($spec.Contains('Verdict: PLAN/DONE/S1600_t/attachments/note.txt')) "citation is not at the final home: $($spec -replace '\s+', ' ')"
        Assert-That (Test-At 'PLAN/DONE/S1600_t/attachments/note.txt') 'the attachment is not at the cited path'
        Assert-That (-not $spec.Contains('PLAN/S1600_t/attachments')) 'a citation of the old home is left behind'
        Assert-That (Test-At 'temp/S1600/note.txt') 'the scratch file was deleted'
        $env:SZA_PROJECT_ROOT = $repo
        $out = & $gate -Id S1600 2>&1 | Out-String
        Assert-That ($LASTEXITCODE -eq 0 -and $out -match 'PASS S1600') "the gate does not pass the moved spec (exit $LASTEXITCODE): $($out.Trim())"
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
        $out = & pwsh -NoProfile -File $archive -Id S1601 -Reason 'not needed: fixture' 2>&1 | Out-String
        $code = $LASTEXITCODE
        Assert-That ($code -eq 0) "archive exit $code : $($out.Trim())"
        Assert-That ($out -match 'already there') "no 'already there' in: $($out.Trim())"
        Assert-That ((Test-At 'PLAN/DONE/S1601_t.md') -and (Test-At 'PLAN/DONE/S1601_t/INDEX.md') -and -not (Test-At 'PLAN/archive')) 'file moved or a second archive folder appeared'
        $arch = [IO.File]::ReadAllLines((Join-Path $repo 'PLAN\spec-catalog-archive.jsonl')) | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.id -ceq 'S1601' }
        Assert-That ($arch.file -ceq 'PLAN/DONE/S1601_t.md' -and $arch.status -ceq 'Archived') "archive row: file=$($arch.file) status=$($arch.status)"
    }

    function Add-LedgerRow([string] $Id, [string] $Status, [string] $File, [switch] $NoName) {
        $row = [ordered]@{ id = $Id }
        if (-not $NoName) { $row['name'] = 't' }
        $row['status'] = $Status; $row['priority'] = 50; $row['file'] = $File; $row['created'] = '2026-11-15'; $row['updated'] = '2026-11-15 10:00'
        [IO.File]::AppendAllText((Join-Path $repo 'PLAN\spec-catalog.jsonl'), (($row | ConvertTo-Json -Compress) + "`n"))
    }
    function Get-ScriptFunctionText([string] $Path, [string] $Name) {
        $ast = [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        $fn = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name }, $true))
        Assert-That ($fn.Count -eq 1) "$Name is defined $($fn.Count) times in $Path"
        return $fn[0].Extent.Text
    }

    Run-Case 'S0084: the evidence gate refuses a cited own-folder file that does not exist, and only that one' {
        [void](New-Spec 'S1703' 'In Progress' -WithFolder)
        New-Item -ItemType Directory -Path (Join-Path $repo 'PLAN/S1703_t/attachments') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $repo 'PLAN/S1703_t/attachments/there.txt'), 'x')
        $body = @(
            '# Spec: S1703 - t', '', '**Status:** In Progress', '',
            '## 0. Owner request (verbatim)', '', 'Verbatim, exempt: PLAN/S1703_t/attachments/gone-in-zero.txt', '',
            '## 4. Evidence', '',
            'Present: PLAN/S1703_t/attachments/there.txt and with a line PLAN/S1703_t/attachments/there.txt:12 and a fragment PLAN/S1703_t/attachments/there.txt#top.',
            'Skipped: glob PLAN/S1703_t/attachments/*.log, directory PLAN/S1703_t/attachments/, other home PLAN/DONE/S1703_t/attachments/x.txt.',
            'Dangling: PLAN/S1703_t/attachments/gone.txt.', ''
        ) -join "`n"
        [IO.File]::WriteAllText((Join-Path $repo 'PLAN/S1703_t.md'), $body)
        Add-LedgerRow 'S1703' 'In Progress' 'PLAN/S1703_t.md'
        $env:SZA_PROJECT_ROOT = $repo
        $out = & $gate -Id S1703 2>&1 | Out-String
        Assert-That ($LASTEXITCODE -eq 1) "the gate did not refuse (exit $LASTEXITCODE): $($out.Trim())"
        $listed = @($out -split "`r?`n" | Where-Object { $_ -match '^- PLAN/' })
        Assert-That ($listed.Count -eq 1 -and $listed[0] -match 'attachments/gone\.txt$') "expected exactly gone.txt listed, got: $($listed -join ' | ')"
    }

    Run-Case 'S0084: plan-tick finds the plan of a ticket whose spec has moved to the archive directory' {
        New-Item -ItemType Directory -Path (Join-Path $repo 'PLAN/DONE') -Force | Out-Null
        $plan = @(
            '# Spec: S1705 - t', '', '**Status:** Verified', '', '## 1. Problem', '', 'Text.', '',
            '# Phase 1', '', '**Steps done:** 0 / 1', '', '### Step 1.1 - do it', '', '**Status:** `[ ]` not done', ''
        ) -join "`n"
        [IO.File]::WriteAllText((Join-Path $repo 'PLAN/DONE/S1705_t.md'), $plan)
        Add-LedgerRow 'S1705' 'Verified' 'PLAN/DONE/S1705_t.md'
        $env:SZA_PROJECT_ROOT = $repo
        $out = & $planTick -Id S1705 -Phase 01 -Steps 1 -State Done 2>&1 | Out-String
        Assert-That ($LASTEXITCODE -eq 0) "plan-tick exit $LASTEXITCODE : $($out.Trim())"
        $after = [IO.File]::ReadAllText((Join-Path $repo 'PLAN/DONE/S1705_t.md'))
        Assert-That ($after -match '\*\*Status:\*\* `\[x\]` done') "the marker was not ticked in the archive copy: $($after -replace '\s+', ' ')"
        Assert-That ($after -match '\*\*Steps done:\*\* 1 / 1') 'the counter was not updated'
        # A ticket with no ledger row at all is still found in the archive directory.
        [IO.File]::WriteAllText((Join-Path $repo 'PLAN/DONE/S1706_t.md'), "# Spec: S1706 - t`n")
        $found = Find-SzaSpecFile -Id 'S1706' -RepoRoot $repo
        Assert-That ($found -and $found.FullName -ieq (Join-Path $repo 'PLAN\DONE\S1706_t.md')) "no-row lookup: '$($found.FullName)'"
    }

    Run-Case 'S0084: the two title fallbacks read the spec from the ledger row''s file once it has moved' {
        # The runner scripts are not strict; this scope must not be either, or a row with no `name` throws inside a try.
        Set-StrictMode -Off
        [IO.File]::WriteAllText((Join-Path $repo 'PLAN/DONE/S1707_t.md'), "# S1707 - Title from the moved spec`n`n**Status:** Verified`n")
        [IO.File]::AppendAllText((Join-Path $repo 'PLAN\spec-catalog.jsonl'), '{"id":"S1707","status":"Verified","priority":50,"file":"PLAN/DONE/S1707_t.md","created":"2026-11-15","updated":"2026-11-15 10:00"}' + "`n")
        $RepoRoot = $repo
        function Get-TicketRecord { param([string] $Id) [pscustomobject]@{ id = $Id; file = 'PLAN/DONE/S1707_t.md' } }
        . ([scriptblock]::Create((Get-ScriptFunctionText (Join-Path $harness 'batch\run-spec-queue.ps1') 'Get-TicketTitle')))
        . ([scriptblock]::Create((Get-ScriptFunctionText (Join-Path $harness 'batch\dev-monitor-snapshot.ps1') 'Get-DevMonitorTicketTitle')))
        $fromRunner = Get-TicketTitle -Ticket $null -Id 'S1707'
        $fromMonitor = Get-DevMonitorTicketTitle -RepoRoot $repo -Id 'S1707'
        Assert-That ($fromRunner -ceq 'Title from the moved spec') "run-spec-queue title: '$fromRunner'"
        Assert-That ($fromMonitor -ceq 'Title from the moved spec') "dev-monitor title: '$fromMonitor'"
    }

    Run-Case 'S0087: the dev-monitor last-write reads the spec and folder of a ticket that has moved to the archive directory' {
        Set-StrictMode -Off
        . ([scriptblock]::Create((Get-ScriptFunctionText (Join-Path $harness 'batch\dev-monitor-snapshot.ps1') 'Get-DevMonitorRelativePath')))
        . ([scriptblock]::Create((Get-ScriptFunctionText (Join-Path $harness 'batch\dev-monitor-snapshot.ps1') 'Get-DevMonitorTicketLastWrite')))
        function Set-Age([string] $Rel, [int] $Minutes) { (Get-Item -LiteralPath (Join-Path $repo $Rel)).LastWriteTime = (Get-Date).AddMinutes(-$Minutes) }

        # Moved by rule 70, no ledger row: found through paths.specArchiveDir; the folder file is the newest.
        [void](New-Spec 'S1708' 'Verified' -WithFolder -Dir 'PLAN/DONE')
        Set-Age 'PLAN/DONE/S1708_t.md' 30; Set-Age 'PLAN/DONE/S1708_t/INDEX.md' 4
        $w = Get-DevMonitorTicketLastWrite -RepoRoot $repo -Id 'S1708'
        Assert-That ($null -ne $w) 'archive: no write time for a ticket that lives only in the archive directory'
        Assert-That ($w.Path -ceq 'PLAN/DONE/S1708_t/INDEX.md') "archive: newest path is '$($w.Path)'"
        Assert-That ($w.Minutes -ge 3.5 -and $w.Minutes -lt 6) "archive: minutes $($w.Minutes)"

        # The ledger row's own `file` names a directory neither profile path covers: the row is read first.
        [void](New-Spec 'S1709' 'Verified' -Dir 'PLAN/sub')
        Set-Age 'PLAN/sub/S1709_t.md' 9
        Add-LedgerRow 'S1709' 'Verified' 'PLAN/sub/S1709_t.md'
        $w2 = Get-DevMonitorTicketLastWrite -RepoRoot $repo -Id 'S1709'
        Assert-That ($null -ne $w2 -and $w2.Path -ceq 'PLAN/sub/S1709_t.md') "ledger dir: '$($w2.Path)'"

        # An active ticket is still read from the specs directory, and the scratch directory still counts.
        [void](New-Spec 'S1710' 'In Progress' -WithFolder)
        Set-Age 'PLAN/S1710_t.md' 20; Set-Age 'PLAN/S1710_t/INDEX.md' 15
        New-Item -ItemType Directory -Path (Join-Path $repo 'temp/S1710') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $repo 'temp/S1710/scratch.txt'), 'x')
        Set-Age 'temp/S1710/scratch.txt' 2
        $w3 = Get-DevMonitorTicketLastWrite -RepoRoot $repo -Id 'S1710'
        Assert-That ($null -ne $w3 -and $w3.Path -ceq 'temp/S1710/scratch.txt') "scratch: '$($w3.Path)'"
        Remove-Item -LiteralPath (Join-Path $repo 'temp/S1710') -Recurse -Force
        $w4 = Get-DevMonitorTicketLastWrite -RepoRoot $repo -Id 'S1710'
        Assert-That ($null -ne $w4 -and $w4.Path -ceq 'PLAN/S1710_t/INDEX.md') "active: '$($w4.Path)'"

        # Nothing anywhere, and a malformed id, answer $null.
        Assert-That ($null -eq (Get-DevMonitorTicketLastWrite -RepoRoot $repo -Id 'S1799')) 'unknown ticket did not answer $null'
        Assert-That ($null -eq (Get-DevMonitorTicketLastWrite -RepoRoot $repo -Id 'not-an-id')) 'malformed id did not answer $null'
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
