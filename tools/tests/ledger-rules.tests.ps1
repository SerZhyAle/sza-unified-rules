#requires -Version 7.0
<#
    Exercise the TASK-FLOW rules that the runner suite (batch-runner.tests.ps1) and the day-0 rehearsal do
    not reach, against throwaway projects and the shipped harness tools: the ledger and its files (rules 1,
    2, 3, 4, 6, 9, 10, 11), the plan files and how finished work leaves (14-17), evidence and step markers
    (19, 20), and the parts of the runner that coordinate (28, 29, 32, 34, 38).

    What this proves: each rule's mechanical part, by a command that passes and, wherever the rule forbids
    something, a command that is refused. Rules whose subject is an agent's behaviour are not here because no
    command can exercise them: rule 13 (park, do not fix), the habit half of rule 20 (state is read from the
    ticket), the measurement half of rule 34 and rule 40 (grow a runner against a measurement). TASK-FLOW
    section 4 says so.

    What it does not prove: anything a real agent does. No `claude` process is started; the children are
    fakes, as in the runner suite.

    A `GAP` line is a place where a shipped tool differs from the contract's text. It never fails the run and
    the case flips to PASS the day the tool changes, so the claim cannot go stale in either direction.

    Takes about five minutes: every ledger operation is a process of its own, and the runner cases wait for real
    children. Windows only: the runner cases use taskkill and CIM. Exit codes: 0 all cases passed; 1 an assertion
    failed; 2 prerequisites unavailable.
#>
[CmdletBinding()]
param(
    [string]$SourceRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    # Run only the cases whose name matches this regular expression (a negative control needs one case, not twenty-four).
    [string]$Case,
    [switch]$KeepScratch
)

$ErrorActionPreference = 'Stop'
$run = 0
$failed = 0
$gaps = 0
$savedRoot = $env:SZA_PROJECT_ROOT
$savedProfile = $env:SZA_PROFILE_PATH
$savedAgent = $env:SZA_AGENT_ID
$scratch = $null

function Assert-That([bool]$Condition, [string]$Reason) { if (-not $Condition) { throw $Reason } }
function Test-Case([string]$Name, [scriptblock]$Body) {
    if ($Case -and $Name -notmatch $Case) { return }
    $script:run++
    try {
        $lines = @(& $Body)
        $gap = @($lines | Where-Object { "$_".StartsWith('GAP ') })
        if ($gap.Count -gt 0) { $script:gaps++; $gap }
        else { "OK $Name" }
    }
    catch { $script:failed++; "FAIL $Name - $($_.Exception.Message)" }
}
function Write-Gap([string]$Text) { "GAP $Text" }

function Invoke-Tool([string]$Project, [string]$Script, [string[]]$ToolArgs = @()) {
    $env:SZA_PROJECT_ROOT = $Project
    $output = & pwsh -NoProfile -File (Join-Path $harness $Script) @ToolArgs 2>&1 | Out-String
    [pscustomobject]@{ code = $LASTEXITCODE; output = $output.Trim() }
}
function Assert-Tool([string]$Project, [string]$Script, [string[]]$ToolArgs = @()) {
    $r = Invoke-Tool $Project $Script $ToolArgs
    Assert-That ($r.code -eq 0) "$Script $($ToolArgs -join ' ') exited $($r.code): $($r.output)"
    return $r
}
# Start a tool without waiting; the environment is set on the child only.
function Start-Tool([string]$Project, [string]$Script, [string[]]$ToolArgs = @()) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new((Get-Command pwsh -CommandType Application | Select-Object -First 1).Source)
    foreach ($a in (@('-NoProfile', '-File', (Join-Path $harness $Script)) + $ToolArgs)) { $psi.ArgumentList.Add($a) }
    $psi.WorkingDirectory = $Project
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.Environment['SZA_PROJECT_ROOT'] = $Project
    $proc = [System.Diagnostics.Process]::Start($psi)
    [pscustomobject]@{ process = $proc; out = $proc.StandardOutput.ReadToEndAsync(); err = $proc.StandardError.ReadToEndAsync() }
}

function Read-Jsonl([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    @(Get-Content -LiteralPath $Path | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json -DateKind String })
}
function Get-Ledger([string]$Project) { Read-Jsonl (Join-Path $Project 'PLAN/spec-catalog.jsonl') }
function Get-Row([string]$Project, [string]$Id) { Get-Ledger $Project | Where-Object id -eq $Id }
function Get-SpecText([string]$Project, [string]$Id) {
    $row = @(Get-Ledger $Project) + @(Read-Jsonl (Join-Path $Project 'PLAN/spec-catalog-archive.jsonl')) | Where-Object id -eq $Id | Select-Object -First 1
    Get-Content -LiteralPath (Join-Path $Project $row.file) -Raw
}
function Get-HeaderStatus([string]$Text) { [regex]::Match($Text, '(?m)^\*\*Status:\*\*\s*(.+?)\s*$').Groups[1].Value }

function New-Project([string]$Name, [string[]]$Slugs = @('one', 'two', 'three')) {
    $root = Join-Path $scratch $Name
    New-Item -ItemType Directory -Path $root | Out-Null
    Assert-Tool $root 'scaffold/init-task-flow.ps1' @('-Root', $root) | Out-Null
    foreach ($slug in $Slugs) {
        Assert-Tool $root 'spec_catalog/capture-draft.ps1' @('-Slug', "task-$slug", '-Text', "the owner's words for $slug") | Out-Null
    }
    return $root
}
function Move-Ticket([string]$Project, [string]$Id, [string]$Status, [string]$Note = $null) {
    $a = @('-Id', $Id, '-Status', $Status)
    if ($Note) { $a += @('-StatusNote', $Note) }
    Assert-Tool $Project 'spec_catalog/update.ps1' $a | Out-Null
}

try {
    if (-not $IsWindows) { throw 'Windows only: the runner cases use taskkill and CIM process listing' }
    foreach ($required in @('tools/harness/spec_catalog/update.ps1', 'tools/harness/scaffold/init-task-flow.ps1', 'tools/harness/batch/run-spec-queue.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot $required))) { throw "Missing prerequisite: $required" }
    }
    $harness = (Resolve-Path (Join-Path $SourceRoot 'tools/harness')).Path
    $env:SZA_PROFILE_PATH = $null
    $scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('s0013-ledger-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $scratch | Out-Null

    # === A. Numbering and state ===================================================================================

    Test-Case 'rule 1: the three files sit at their default paths, UTF-8 without a BOM, one object per line, and an absent archive reads as empty' {
        $p = New-Project 'a-files'
        foreach ($rel in 'PLAN/spec-catalog.jsonl', 'PLAN/spec-catalog-archive.jsonl', 'PLAN/spec-catalog-burned-ids.jsonl') {
            Assert-That (Test-Path -LiteralPath (Join-Path $p $rel)) "$rel is missing"
            $bytes = [System.IO.File]::ReadAllBytes((Join-Path $p $rel))
            Assert-That (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) "$rel starts with a BOM"
        }
        foreach ($line in (Get-Content (Join-Path $p 'PLAN/spec-catalog.jsonl') | Where-Object { $_.Trim() })) {
            $null = $line | ConvertFrom-Json
        }
        Remove-Item -LiteralPath (Join-Path $p 'PLAN/spec-catalog-archive.jsonl')
        Assert-Tool $p 'spec_catalog/validate.ps1' | Out-Null
        $r = Assert-Tool $p 'spec_catalog/select.ps1' @('-Id', 'S0001', '-IncludeArchived', '-Format', 'json')
        Assert-That ((@($r.output | ConvertFrom-Json)).Count -eq 1) 'the lookup without an archive file did not find the live ticket'
    }

    Test-Case 'rule 1: the paths a profile declares move the ledger, the archive and the burned list' {
        $p = New-Project 'a-paths' @()
        $profilePath = Join-Path $p '.sza-profile.json'
        $doc = Get-Content $profilePath -Raw | ConvertFrom-Json -AsHashtable
        $doc.paths = @{ journal = 'LEDGER/rows.jsonl'; journalArchive = 'LEDGER/old.jsonl'; burnedIds = 'LEDGER/burned.jsonl' }
        $doc | ConvertTo-Json -Depth 6 | Set-Content $profilePath -Encoding utf8
        Assert-Tool $p 'spec_catalog/capture-draft.ps1' @('-Slug', 'moved', '-Text', 'words') | Out-Null
        Assert-That (@(Read-Jsonl (Join-Path $p 'LEDGER/rows.jsonl')).Count -eq 1) 'the row is not in the declared ledger'
        Assert-That (@(Read-Jsonl (Join-Path $p 'PLAN/spec-catalog.jsonl')).Count -eq 0) 'the row still reached the default ledger'
    }

    Test-Case 'rules 2 and 38: five creators started at once get five distinct, dense ids and the ledger validates' {
        $p = New-Project 'a-parallel' @()
        $jobs = 1..5 | ForEach-Object { Start-Tool $p 'spec_catalog/capture-draft.ps1' @('-Slug', "par-$_", '-Text', "words $_") }
        foreach ($j in $jobs) {
            Assert-That ($j.process.WaitForExit(120000)) 'a creator did not finish in 120 s'
            Assert-That ($j.process.ExitCode -eq 0) "a creator exited $($j.process.ExitCode): $($j.out.Result)$($j.err.Result)"
        }
        $ids = @(Get-Ledger $p | ForEach-Object { $_.id } | Sort-Object)
        Assert-That ($ids -join ',' -eq 'S0001,S0002,S0003,S0004,S0005') "ids were $($ids -join ',')"
        Assert-Tool $p 'spec_catalog/validate.ps1' | Out-Null
    }

    Test-Case 'rules 2 and 11: an id an archived or a burned ticket spent is never allocated again, and validate accounts for the hole' {
        $p = New-Project 'a-burned' @('keep', 'archived')
        Assert-Tool $p 'spec_catalog/archive.ps1' @('-Id', 'S0002') | Out-Null
        Assert-That ((Assert-Tool $p 'spec_catalog/next-id.ps1').output -eq 'S0003') 'the archive did not count toward the next id'
        # The one removal the contract allows is a test fixture: a probe the harness itself wrote.
        Assert-Tool $p 'spec_catalog/capture-draft.ps1' @('-Slug', 'preview-tests-probe-x', '-Text', 'probe') | Out-Null
        Assert-That ((Get-Row $p 'S0003').name -eq 'preview-tests-probe-x') 'the probe did not get S0003'
        Assert-Tool $p 'spec_catalog/delete.ps1' @('-Id', 'S0003', '-Confirm') | Out-Null
        Assert-Tool $p 'spec_catalog/purge-probe-records.ps1' | Out-Null
        # delete.ps1 is a soft delete and purge removes only the record; the probe's own file is the fixture's to remove.
        Remove-Item -LiteralPath (Join-Path $p 'PLAN/S0003_preview-tests-probe-x.md')
        $burned = @(Read-Jsonl (Join-Path $p 'PLAN/spec-catalog-burned-ids.jsonl'))
        Assert-That (@($burned | Where-Object id -eq 'S0003').Count -eq 1) 'the purged id is not on the burned list'
        $row = $burned | Where-Object id -eq 'S0003'
        foreach ($field in 'reason', 'burned') { Assert-That ($row.PSObject.Properties.Name -contains $field) "the burned row lacks '$field'" }
        Assert-That (@(Read-Jsonl (Join-Path $p 'PLAN/spec-catalog-archive.jsonl') | Where-Object id -eq 'S0003').Count -eq 0) 'the purged row is still in the archive'
        Assert-That ((Assert-Tool $p 'spec_catalog/next-id.ps1').output -eq 'S0004') 'a burned id was handed out again'
        Assert-Tool $p 'spec_catalog/capture-draft.ps1' @('-Slug', 'after-burn', '-Text', 'words') | Out-Null
        Assert-That ((Get-Row $p 'S0004').name -eq 'after-burn') 'the next ticket did not get S0004'
        Assert-Tool $p 'spec_catalog/validate.ps1' | Out-Null
        # Archived tickets stay addressable by id.
        $found = @((Assert-Tool $p 'spec_catalog/select.ps1' @('-Id', 'S0002', '-IncludeArchived', '-Format', 'json')).output | ConvertFrom-Json)
        Assert-That ($found.Count -eq 1 -and $found[0].status -eq 'Archived') 'an archived ticket is not found by id'
    }

    Test-Case 'rule 3: a captured row carries every required field in its shape' {
        $p = New-Project 'a-record' @('shape')
        $row = Get-Row $p 'S0001'
        foreach ($field in 'id', 'name', 'status', 'priority', 'file', 'created', 'updated') {
            Assert-That ($row.PSObject.Properties.Name -contains $field) "the row lacks '$field'"
        }
        Assert-That ($row.name -cmatch '^[a-z0-9][a-z0-9-]*$' -and $row.name -notlike 'spec_*') "name '$($row.name)' is not a slug"
        Assert-That ($row.priority -is [int] -or $row.priority -is [long]) 'priority is not an integer'
        Assert-That ($row.priority -ge 0 -and $row.priority -le 100) 'priority is outside 0-100'
        Assert-That ($row.file -notmatch '^[A-Za-z]:|^/|\.\.') "file '$($row.file)' is not a relative path under the repository"
        Assert-That ($row.created -match '^\d{4}-\d\d-\d\d$') "created '$($row.created)' is not YYYY-MM-DD"
        Assert-That ($row.updated -match '^\d{4}-\d\d-\d\d \d\d:\d\d$') "updated '$($row.updated)' is not YYYY-MM-DD HH:mm"
    }

    Test-Case 'rule 3: a writer preserves a field it does not know and a reader ignores it' {
        $p = New-Project 'a-unknown' @('keep')
        $ledger = Join-Path $p 'PLAN/spec-catalog.jsonl'
        $rows = @(Get-Content $ledger)
        $rows[0] = $rows[0].TrimEnd().TrimEnd('}') + ',"zz_custom":{"k":1}}'
        Set-Content $ledger $rows -Encoding utf8
        Assert-Tool $p 'spec_catalog/validate.ps1' | Out-Null
        Move-Ticket $p 'S0001' 'Approved'
        Assert-That ((Get-Content $ledger -Raw) -match '"zz_custom":\{"k":1\}') 'update dropped the unknown field'
        Assert-Tool $p 'spec_catalog/archive.ps1' @('-Id', 'S0001') | Out-Null
        Assert-That ((Get-Content (Join-Path $p 'PLAN/spec-catalog-archive.jsonl') -Raw) -match '"zz_custom":\{"k":1\}') 'archive dropped the unknown field'
    }

    Test-Case 'rule 4: every status change writes the ledger and the spec header together' {
        $p = New-Project 'a-header' @('twin')
        foreach ($status in 'Approved', 'Tactical', 'In Progress', 'Implemented') {
            Move-Ticket $p 'S0001' $status
            Assert-That ((Get-Row $p 'S0001').status -eq $status) "the ledger says $((Get-Row $p 'S0001').status), not $status"
            Assert-That ((Get-HeaderStatus (Get-SpecText $p 'S0001')) -eq $status) "the header says $(Get-HeaderStatus (Get-SpecText $p 'S0001')), not $status"
        }
    }

    Test-Case 'rule 4: a header changed by hand is reported by the picker, and the ledger is the side it names' {
        $p = New-Project 'a-mismatch' @('drift')
        Move-Ticket $p 'S0001' 'Approved'
        $spec = Join-Path $p (Get-Row $p 'S0001').file
        (Get-Content $spec -Raw) -replace '(?m)^\*\*Status:\*\*.*$', '**Status:** Tactical' | Set-Content $spec -NoNewline -Encoding utf8
        $r = Invoke-Tool $p 'spec_catalog/spec-next-preflight.ps1' @('-Format', 'table', '-NoDrift')
        Assert-That ($r.output -match 'status mismatch: catalog=Approved file=Tactical') "the mismatch was not reported: $($r.output)"
        Assert-That ((Get-Row $p 'S0001').status -eq 'Approved') 'the picker rewrote the ledger'
        Assert-That ($r.output -match 'catalog authoritative') "the picker did not call catalog authoritative: $($r.output)"
        Assert-That ($r.output -notmatch 'file authoritative') "the picker called file authoritative: $($r.output)"
    }

    Test-Case 'rule 6: the vocabulary is closed - update refuses an undeclared status and validate refuses a ledger that holds one' {
        $p = New-Project 'a-vocab' @('v')
        $r = Invoke-Tool $p 'spec_catalog/update.ps1' @('-Id', 'S0001', '-Status', 'Done')
        Assert-That ($r.code -ne 0) 'update accepted the status Done'
        $ledger = Join-Path $p 'PLAN/spec-catalog.jsonl'
        $good = Get-Content $ledger
        Set-Content $ledger ($good -replace '"status":"Draft"', '"status":"Done"') -Encoding utf8
        Assert-That ((Invoke-Tool $p 'spec_catalog/validate.ps1').code -ne 0) 'validate accepted a ledger holding the status Done'
        Set-Content $ledger $good -Encoding utf8
        Assert-Tool $p 'spec_catalog/validate.ps1' | Out-Null
    }

    Test-Case 'rule 6: Archived is reachable from every status and revivable' {
        $p = New-Project 'a-archived' @('draft', 'approved', 'tactical', 'progress', 'implemented', 'partial', 'broken', 'bq', 'bx', 'verified')
        $walk = [ordered]@{
            S0002 = @('Approved'); S0003 = @('Tactical'); S0004 = @('In Progress'); S0005 = @('Implemented')
            S0006 = @('Partial'); S0007 = @('Broken')
        }
        foreach ($id in $walk.Keys) { Move-Ticket $p $id $walk[$id][0] }
        Move-Ticket $p 'S0008' 'BlockQuestions' 'waiting for the owner'
        Move-Ticket $p 'S0009' 'BlockExternal' 'waiting for a vendor'
        $spec = Join-Path $p (Get-Row $p 'S0010').file
        Add-Content $spec "`n## Last Audit`n`nChecked by hand for the fixture: the result covers the task.`n"
        Move-Ticket $p 'S0010' 'Verified'
        $reached = @()
        foreach ($row in (Get-Ledger $p)) {
            Assert-Tool $p 'spec_catalog/archive.ps1' @('-Id', $row.id) | Out-Null
            $reached += $row.status
        }
        Assert-That (@(Get-Ledger $p).Count -eq 0) 'a ticket stayed in the ledger'
        Assert-That ((@(Read-Jsonl (Join-Path $p 'PLAN/spec-catalog-archive.jsonl') | Where-Object { $_.status -eq 'Archived' })).Count -eq 10) 'not every ticket reached the archive as Archived'
        Move-Ticket $p 'S0010' 'Draft'
        Assert-That ((Get-Row $p 'S0010').status -eq 'Draft') 'an archived ticket was not revived'
        Assert-Tool $p 'spec_catalog/validate.ps1' | Out-Null
    }

    Test-Case 'rules 6 and 7: leaving a Block* status clears its note, and a Block* ticket may leave to any active status' {
        $p = New-Project 'a-block' @('b')
        Move-Ticket $p 'S0001' 'BlockExternal' 'waiting for a vendor'
        Assert-That ((Get-Row $p 'S0001').statusNote -eq 'waiting for a vendor') 'the note was not kept'
        Assert-That ((Get-SpecText $p 'S0001') -match '(?m)^\*\*Status note:\*\*\s*waiting for a vendor') 'the note is not mirrored under the status line'
        $r = Invoke-Tool $p 'spec_catalog/update.ps1' @('-Id', 'S0001', '-Status', 'Implemented')
        Assert-That ($r.code -eq 0) "update refused leaving Block* to Implemented: $($r.output)"
        Assert-That (-not (Get-Row $p 'S0001').PSObject.Properties.Name.Contains('statusNote') -or -not (Get-Row $p 'S0001').statusNote) 'the note outlived the Block* status'
        Assert-That ((Get-Row $p 'S0001').status -eq 'Implemented') 'the status was not updated to Implemented'
    }

    Test-Case 'rule 9: direction is read from literal tokens, never from prose' {
        $loader = Join-Path $scratch 'blockers.ps1'
        @"
. '$(Join-Path $harness 'spec_catalog/_blocker-links.ps1')'
`$cases = [ordered]@{
    depends   = Get-BlockerLinks -SpecText "**Depends on:** S0002, S0003`n" -SelfId S0001
    token     = Get-BlockerLinks -SpecText "## 10. Links`n`nBlocker: S0004`n" -SelfId S0001
    russian   = Get-BlockerLinks -SpecText "## 10. Links`n`nБлокер: S0005`n" -SelfId S0001
    note      = Get-BlockerLinks -SpecText '' -StatusNote 'waiting. Blocker: S0006' -SelfId S0001
    prose     = Get-BlockerLinks -SpecText "## 10. Links`n`nThe consumers are S0007 and S0008; related to S0009.`n" -SelfId S0001
    carrier   = Get-BlockerLinks -SpecText "## 10. Links`n`nCarrier: S0010`n" -SelfId S0001
    self      = Get-BlockerLinks -SpecText "**Depends on:** S0001`n" -SelfId S0001
}
`$cases | ConvertTo-Json -Compress
"@ | Set-Content $loader -Encoding utf8
        $out = (& pwsh -NoProfile -File $loader 2>&1 | Out-String).Trim() | ConvertFrom-Json
        Assert-That ((@($out.depends) -join ',') -eq 'S0002,S0003') "Depends on gave $(@($out.depends) -join ',')"
        Assert-That ((@($out.token) -join ',') -eq 'S0004') "a Blocker token gave $(@($out.token) -join ',')"
        Assert-That ((@($out.russian) -join ',') -eq 'S0005') "a Блокер token gave $(@($out.russian) -join ',')"
        Assert-That ((@($out.note) -join ',') -eq 'S0006') "a token in the note gave $(@($out.note) -join ',')"
        Assert-That (@($out.prose | Where-Object { $_ }).Count -eq 0) "ids in prose were read as blockers: $(@($out.prose) -join ',')"
        Assert-That (@($out.carrier | Where-Object { $_ }).Count -eq 0) "a Carrier token was read as a blocker: $(@($out.carrier) -join ',')"
        Assert-That (@($out.self | Where-Object { $_ }).Count -eq 0) 'a ticket was blocked by itself'
    }

    Test-Case 'rule 9 and 52: a qualified Blocker token is ignored by every local reader and is never read as a local id' {
        # Rule 52 writes a blocker held in another repository as `Blocker: <repoKey>:<id>` and promises that a local
        # reader ignores it. This case characterises the shipped readers, so it passes on the unmodified harness; its
        # guard value is the negative control of S0015 phase 00 step 00.3, a reader that tolerates a `repo:` prefix.
        $loader = Join-Path $scratch 'qblockers.ps1'
        @"
. '$(Join-Path $harness 'spec_catalog/_blocker-links.ps1')'
`$cases = [ordered]@{
    qualified = Get-BlockerLinks -SpecText "## 10. Links`n`nBlocker: fms-web:S0028`n" -SelfId S0001
    russian   = Get-BlockerLinks -SpecText "## 10. Links`n`nБлокер: fms-web:S0028`n" -SelfId S0001
    mixed     = Get-BlockerLinks -SpecText "## 10. Links`n`nBlocker: S0004`nBlocker: fms-web:S0028`n" -SelfId S0001
    note      = Get-BlockerLinks -SpecText '' -StatusNote 'waiting. Blocker: fms-web:S0028' -SelfId S0001
    digitkey  = Get-BlockerLinks -SpecText "## 10. Links`n`nBlocker: s0001:S0002`n" -SelfId S0009
    depends   = Get-BlockerLinks -SpecText "**Depends on:** fms-web:S0028`n" -SelfId S0001
}
`$cases | ConvertTo-Json -Compress
"@ | Set-Content $loader -Encoding utf8
        $out = (& pwsh -NoProfile -File $loader 2>&1 | Out-String).Trim() | ConvertFrom-Json
        Assert-That (@($out.qualified | Where-Object { $_ }).Count -eq 0) "(a) 'Blocker: fms-web:S0028' under '## 10. Links' was read as a local id: $(@($out.qualified) -join ',')"
        Assert-That (@($out.russian | Where-Object { $_ }).Count -eq 0) "(b) 'Блокер: fms-web:S0028' under '## 10. Links' was read as a local id: $(@($out.russian) -join ',')"
        Assert-That ((@($out.mixed) -join ',') -eq 'S0004') "(c) a section holding 'Blocker: S0004' and 'Blocker: fms-web:S0028' gave '$(@($out.mixed) -join ',')', not exactly S0004"
        Assert-That (@($out.note | Where-Object { $_ }).Count -eq 0) "(d) the status note 'waiting. Blocker: fms-web:S0028' was read as a local id: $(@($out.note) -join ',')"
        # Hazard pins: they record where the local reader is NOT safe, so the contract forbids the input instead.
        # The SelfId is S0009 here, because the reader drops its own id case-insensitively and S0001 would hide the hazard.
        Assert-That ((@($out.digitkey) -join ',') -ceq 's0001') "(e) 'Blocker: s0001:S0002' gave '$(@($out.digitkey) -join ',')', not the single id s0001 (the reader is case-insensitive on S\d{4}); rule 41 forbids a key whose second character is a digit"
        Assert-That ((@($out.depends) -join ',') -eq 'S0028') "(f) '**Depends on:** fms-web:S0028' gave '$(@($out.depends) -join ',')', not the local S0028; rule 52 allows the qualified form only in a Blocker token"
        # (g) The process level: the closing gate and the picker, in a throwaway project.
        $p = New-Project 'a-qblock' @('one', 'two')
        Add-Content (Join-Path $p (Get-Row $p 'S0001').file) "`n## 10. Links`n`nBlocker: other-repo:S0099`n"
        # A ticket whose only blocker is in another repository is not parked in BlockByOtherTask; the dispatcher holds it (rule 52).
        $gate = Invoke-Tool $p 'spec_catalog/check-block-note.ps1' @('-Id', 'S0001', '-NewStatus', 'BlockByOtherTask', '-StatusNote', 'waiting on other-repo:S0099', '-NoteSupplied')
        Assert-That ($gate.code -eq 1) "(g) check-block-note with only 'Blocker: other-repo:S0099' in section 10 exited $($gate.code), not 1: $($gate.output)"
        Assert-That ($gate.output -match 'records no blocker in a directional channel') "(g) check-block-note with only 'Blocker: other-repo:S0099' did not say it records no directional blocker: $($gate.output)"
        # The local picker does not enforce the token: the ticket stays selectable.
        $pick = Invoke-Tool $p 'spec_catalog/spec-next-preflight.ps1' @('-NoDrift', '-Format', 'json')
        $json = @($pick.output -split "`r?`n" | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1)
        Assert-That ($pick.code -eq 0 -and $json.Count -eq 1) "(g) spec-next-preflight exited $($pick.code) without a JSON payload: $($pick.output)"
        $picked = $json[0] | ConvertFrom-Json
        Assert-That ($picked.selected.id -eq 'S0001') "(g) with 'Blocker: other-repo:S0099' in its section 10 the picker selected '$($picked.selected.id)', not S0001"
        Assert-That (@($picked.auto_skipped | Where-Object { $_.id -eq 'S0001' }).Count -eq 0) "(g) the picker auto-skipped S0001 for 'Blocker: other-repo:S0099': $(@($picked.auto_skipped | Where-Object { $_.id -eq 'S0001' } | ForEach-Object { $_.reason }) -join ',')"
    }

    Test-Case 'rule 10: every way a ledger can be wrong fails validation, and each failure names what is wrong' {
        $p = New-Project 'a-validate' @('one', 'two', 'three')
        $ledger = Join-Path $p 'PLAN/spec-catalog.jsonl'
        $good = Get-Content $ledger
        $mutations = [ordered]@{
            'an incomplete JSON line'  = { param($r) $r + '{"id":"S0004",' }
            'a missing required field' = { param($r) @($r[0] -replace '"created":"[^"]*",', '') + $r[1..2] }
            'an id outside the pattern' = { param($r) @($r[0] -replace '"id":"S0001"', '"id":"X1"') + $r[1..2] }
            'a duplicate id'           = { param($r) @($r[0], ($r[1] -replace '"id":"S0002"', '"id":"S0001"'), $r[2]) }
            'a status outside the vocabulary' = { param($r) @($r[0] -replace '"status":"Draft"', '"status":"Nope"') + $r[1..2] }
            'a priority above 100'     = { param($r) @($r[0] -replace '"priority":\d+', '"priority":101') + $r[1..2] }
            'a file path with ..'      = { param($r) @($r[0] -replace 'PLAN/S0001', 'PLAN/../S0001') + $r[1..2] }
            'a record whose file is gone' = { param($r) Remove-Item -LiteralPath (Join-Path $p 'PLAN/S0003_task-three.md'); $r }
            'a spec file with no record' = { param($r) @($r[0], $r[1]) }
            'an Archived record in the ledger' = { param($r) @($r[0] -replace '"status":"Draft"', '"status":"Archived"') + $r[1..2] }
        }
        foreach ($name in $mutations.Keys) {
            $backup = Join-Path $scratch 'spec3.bak'
            Copy-Item (Join-Path $p 'PLAN/S0003_task-three.md') $backup -Force
            Set-Content $ledger (& $mutations[$name] $good) -Encoding utf8
            $r = Invoke-Tool $p 'spec_catalog/validate.ps1'
            Assert-That ($r.code -ne 0) "validate accepted $name"
            Assert-That ($r.output -match '\[FAIL\]') "validate failed $name without naming a check"
            Set-Content $ledger $good -Encoding utf8
            Copy-Item $backup (Join-Path $p 'PLAN/S0003_task-three.md') -Force
        }
        Assert-Tool $p 'spec_catalog/validate.ps1' | Out-Null
    }

    Test-Case 'rule 10: an id gap is reported, and not once the burned list accounts for it' {
        $p = New-Project 'a-gap' @('one', 'two', 'three')
        $ledger = Join-Path $p 'PLAN/spec-catalog.jsonl'
        $rows = Get-Content $ledger
        $without2 = @($rows[0], $rows[2])
        Set-Content $ledger $without2 -Encoding utf8
        Remove-Item -LiteralPath (Join-Path $p (($rows[1] | ConvertFrom-Json).file))
        $r = Invoke-Tool $p 'spec_catalog/validate.ps1'
        Assert-That ($r.output -match '\[WARN\]\s+Monotonicity\s+id gaps: S0002') "a hole at S0002 was not reported: $($r.output)"
        Set-Content (Join-Path $p 'PLAN/spec-catalog-burned-ids.jsonl') '{"id":"S0002","reason":"fixture","burned":"2026-10-26"}' -Encoding utf8
        $r = Assert-Tool $p 'spec_catalog/validate.ps1'
        Assert-That ($r.output -match '\[OK\]\s+Monotonicity.*1 burned id\(s\) accounted for') "the burned list did not account for the hole: $($r.output)"
        Assert-That ($r.output -notmatch 'id gaps') 'the hole is still reported after it was burned'
    }

    # === B. The plan files ========================================================================================

    Test-Case 'rules 14 and 15: a row is ticket, changed, status; a new ticket lands at the end; the tool never reorders; a missing plan file is a no-op' {
        $p = New-Project 'b-plan' @('one', 'two', 'three')
        $queue = Join-Path $p 'PLAN/RELEASE_QUEUE.md'
        $text = Get-Content $queue -Raw
        Assert-That ($text -match '(?m)^current-next-release:\s*1\s*$') 'the open package is not named by current-next-release'
        Assert-That ($text -match '(?m)^1\s*$') 'a package is not a heading line holding only its number'
        foreach ($row in (Get-Ledger $p)) {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($row.file)
            Assert-That ($text -match "(?m)^$([regex]::Escape($name))\s+\d\d-\d\d-\d\d \d\d:\d\d\s+Draft\s*$") "no row 'ticket  YY-MM-DD HH:mm  status' for $name"
        }
        # The owner reorders by moving lines; the tool must leave the order alone through later writes.
        $lines = @(Get-Content $queue)
        $first = [array]::FindIndex($lines, [Predicate[string]] { param($l) $l -like 'S0001_*' })
        $last = [array]::FindIndex($lines, [Predicate[string]] { param($l) $l -like 'S0003_*' })
        $lines[$first], $lines[$last] = $lines[$last], $lines[$first]
        Set-Content $queue $lines -Encoding utf8
        $order = { @(Get-Content $queue | Where-Object { $_ -match '^S\d{4}_' } | ForEach-Object { $_.Substring(0, 5) }) -join ',' }
        $before = & $order
        Move-Ticket $p 'S0002' 'Approved'
        Assert-Tool $p 'spec_catalog/capture-draft.ps1' @('-Slug', 'task-four', '-Text', 'the owner''s words for four') | Out-Null
        Assert-That ((& $order) -eq "$before,S0004") "the order was '$before' and became '$(& $order)'"
        Assert-That ((Get-Content $queue -Raw) -match '(?m)^S0002_\S+\s+\d\d-\d\d-\d\d \d\d:\d\d\s+Approved\s*$') 'the row of S0002 does not show the new status'
        # `changed` is the time of the last STATUS move, not of a text edit.
        $stamp = [regex]::Match((Get-Content $queue -Raw), '(?m)^S0002_\S+\s+(\d\d-\d\d-\d\d \d\d:\d\d)').Groups[1].Value
        Add-Content (Join-Path $p (Get-Row $p 'S0002').file) "`nAn edit of the text only.`n"
        Assert-Tool $p 'spec_catalog/release-queue.ps1' @('-Reconcile') | Out-Null
        Assert-That ([regex]::Match((Get-Content $queue -Raw), '(?m)^S0002_\S+\s+(\d\d-\d\d-\d\d \d\d:\d\d)').Groups[1].Value -eq $stamp) 'a text edit moved the changed time'
        # A missing plan file is a no-op, not an error.
        Remove-Item -LiteralPath (Join-Path $p 'PLAN/RELEASE_QUEUE.md'), (Join-Path $p 'PLAN/RELEASE_READY.md')
        Move-Ticket $p 'S0001' 'Approved'
        Assert-That (-not (Test-Path (Join-Path $p 'PLAN/RELEASE_QUEUE.md'))) 'a ledger write re-created a plan file the project had removed'
    }

    Test-Case 'rule 16: crossing into Implemented moves the row to the ready file and reopening moves it back' {
        $p = New-Project 'b-ready' @('one', 'two')
        $queue = Join-Path $p 'PLAN/RELEASE_QUEUE.md'
        $ready = Join-Path $p 'PLAN/RELEASE_READY.md'
        Move-Ticket $p 'S0001' 'Implemented'
        Assert-That ((Get-Content $ready -Raw) -match '(?m)^S0001_\S+\s+.*Implemented') 'the row did not reach the ready file'
        Assert-That ((Get-Content $queue -Raw) -notmatch 'S0001_') 'the row stayed in the queue file'
        Move-Ticket $p 'S0001' 'In Progress'
        Assert-That ((Get-Content $queue -Raw) -match '(?m)^S0001_\S+\s+.*In Progress') 'a reopened ticket did not return to the queue'
        Assert-That ((Get-Content $ready -Raw) -notmatch 'S0001_') 'a reopened ticket stayed in the ready file'
        Move-Ticket $p 'S0001' 'BlockExternal' 'vendor'
        Assert-That ((Get-Content $queue -Raw) -match '(?m)^S0001_\S+\s+.*BlockExternal') 'a Block* ticket is not planned around in the queue file'
    }

    Test-Case 'rule 16: the ship step moves the ready block to the done file, advances the marker and reports unfinished rows without moving them; the archive sweep comes last' {
        $p = New-Project 'b-ship' @('one', 'two')
        Move-Ticket $p 'S0001' 'Implemented'
        $queue = Join-Path $p 'PLAN/RELEASE_QUEUE.md'
        $r = Assert-Tool $p 'spec_catalog/release-queue.ps1' @('-Ship', '-Release', '1', '-Version', '1.0.0')
        Assert-That ($r.output -match 'WARNING.*1 unfinished ticket') "the unfinished S0002 was not reported: $($r.output)"
        Assert-That ((Get-Content (Join-Path $p 'PLAN/RELEASE_QUEUE_DONE.md') -Raw) -match 'S0001_') 'the shipped block is not in the done file'
        Assert-That ((Get-Content (Join-Path $p 'PLAN/RELEASE_READY.md') -Raw) -notmatch 'S0001_') 'the shipped row is still in the ready file'
        Assert-That ((Get-Content $queue -Raw) -match '(?m)^current-next-release:\s*2\s*$') 'the marker did not advance to 2'
        Assert-That ((Get-Content $queue -Raw) -match '(?m)^S0002_') 'the unfinished row was moved out of the queue'
        # Only now does archiving run, and it drops the rows but not what shipped.
        Assert-Tool $p 'spec_catalog/archive.ps1' @('-Id', 'S0001') | Out-Null
        Assert-That ((Get-Content (Join-Path $p 'PLAN/RELEASE_QUEUE_DONE.md') -Raw) -match 'S0001_') 'archiving lost the record of what shipped'
    }

    Test-Case 'rule 17: archiving is soft - the record moves, the spec file moves to PLAN/archive, nothing is deleted and the id stays spent' {
        $p = New-Project 'b-soft' @('one', 'two')
        $spec = Join-Path $p (Get-Row $p 'S0002').file
        $name = Split-Path $spec -Leaf
        Assert-Tool $p 'spec_catalog/archive.ps1' @('-Id', 'S0002') | Out-Null
        Assert-That (-not (Get-Row $p 'S0002')) 'the record is still in the ledger'
        $moved = @(Read-Jsonl (Join-Path $p 'PLAN/spec-catalog-archive.jsonl') | Where-Object id -eq 'S0002')
        Assert-That ($moved.Count -eq 1 -and $moved[0].status -eq 'Archived') 'the record is not in the archive file as Archived'
        Assert-That (Test-Path -LiteralPath (Join-Path $p "PLAN/archive/$name")) 'the spec file did not move to PLAN/archive'
        Assert-That (-not (Test-Path -LiteralPath $spec)) 'a copy of the spec file stayed behind'
        Assert-That ((Assert-Tool $p 'spec_catalog/next-id.ps1').output -eq 'S0003') 'the id was not spent'
    }

    # === C. Evidence and step markers ===============================================================================

    Test-Case 'rule 19: evidence cited from temp/ moves into the ticket''s own folder at closing, and what cannot move refuses the closing' {
        $p = New-Project 'c-evidence' @('small', 'large')
        foreach ($id in 'S0001', 'S0002') {
            New-Item -ItemType Directory -Path (Join-Path $p "temp/$id") -Force | Out-Null
        }
        Set-Content (Join-Path $p 'temp/S0001/result.txt') 'verdict: pass'
        [System.IO.File]::WriteAllBytes((Join-Path $p 'temp/S0002/big.log'), (New-Object byte[] (70 * 1024)))
        Add-Content (Join-Path $p (Get-Row $p 'S0001').file) "`n## Evidence`n`nThe verdict is in temp/S0001/result.txt.`n"
        Add-Content (Join-Path $p (Get-Row $p 'S0002').file) "`n## Evidence`n`nThe log is temp/S0002/big.log.`n"
        Move-Ticket $p 'S0001' 'Implemented'
        $text = Get-SpecText $p 'S0001'
        Assert-That ($text -notmatch 'temp/S0001/result\.txt') 'the closed ticket still cites temp/'
        $folder = Join-Path $p 'PLAN/S0001_task-small'
        Assert-That (@(Get-ChildItem -LiteralPath $folder -Recurse -File -Filter 'result.txt' -ErrorAction SilentlyContinue).Count -eq 1) 'the evidence is not under the ticket''s own folder'
        $r = Invoke-Tool $p 'spec_catalog/update.ps1' @('-Id', 'S0002', '-Status', 'Implemented')
        Assert-That ($r.code -ne 0) 'a closing that cites a 70 KB file under temp/ was accepted'
        Assert-That ((Get-Row $p 'S0002').status -eq 'Draft') 'the refused closing still moved the ticket'
        Assert-That ($r.output -match 'temp/') 'the refusal does not name the citation'
        # Archiving is never gated.
        Assert-Tool $p 'spec_catalog/archive.ps1' @('-Id', 'S0002', '-AllowMissingArtefact') | Out-Null
    }

    Test-Case 'rule 20: a step marker is ticked through the tool, and the tool refuses to guess' {
        $p = New-Project 'c-ticks' @('steps')
        $spec = Join-Path $p (Get-Row $p 'S0001').file
        Add-Content $spec "`n# Phase 01`n`n- [ ] first gate holds`n- [ ] second gate holds`n- [ ] gate with a twin`n- [ ] gate with a twin as well`n"
        Assert-Tool $p 'spec_catalog/plan-tick.ps1' @('-Id', 'S0001', '-Phase', '01', '-Checkbox', 'first gate', '-State', 'Done') | Out-Null
        $text = Get-Content $spec -Raw
        Assert-That ($text -match '- \[x\] first gate holds') 'the named gate was not ticked'
        Assert-That ($text -match '- \[ \] second gate holds') 'a gate that was not named changed'
        $none = Invoke-Tool $p 'spec_catalog/plan-tick.ps1' @('-Id', 'S0001', '-Phase', '01', '-Checkbox', 'no such gate', '-State', 'Done')
        Assert-That ($none.code -eq 4) "a fragment that matches nothing exited $($none.code), not 4"
        $twin = Invoke-Tool $p 'spec_catalog/plan-tick.ps1' @('-Id', 'S0001', '-Phase', '01', '-Checkbox', 'gate with a twin', '-State', 'Done')
        Assert-That ($twin.code -eq 4) "a fragment that matches two gates exited $($twin.code), not 4"
        Assert-That ((Get-Content $spec -Raw) -notmatch '- \[x\] gate with a twin') 'an ambiguous fragment ticked a gate'
    }

    # === D. Runners that share the tree (R1..Rn) and what R0 leaves out =========================================

    # One fake child. It records the id, the agent id it was given and the vector it received, then moves the
    # ticket one step so the runner sees progress.
    $fakeChild = @'
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSCommandPath
$env:SZA_PROJECT_ROOT = $root
$text = $args -join ' '
$id = [regex]::Match($text, 'S\d{4}').Value
Add-Content (Join-Path $root 'children.log') ("$id|agent=$($env:SZA_AGENT_ID)|args=$text")
& pwsh -NoProfile -File '__HARNESS__/spec_catalog/update.ps1' -Id $id -Status 'In Progress' | Out-Null
exit 0
'@
    # A command that answers --help the way the real CLI does (it lists --session-id) and otherwise runs the fake child.
    $fakeCli = @'
@echo off
if "%~1"=="--help" (
  echo   --session-id ^<uuid^>   Use a specific session ID
  exit /b 0
)
pwsh -NoProfile -File "%~dp0fake-child.ps1" %*
exit /b %ERRORLEVEL%
'@
    function New-RunnerProject([string]$Name, [string[]]$Slugs, [string]$Command = 'pwsh', [string[]]$ArgsTemplate = $null, [string]$PromptTemplate = '{Id}') {
        $root = New-Project $Name $Slugs
        $fakeChild.Replace('__HARNESS__', ($harness -replace '\\', '/')) | Set-Content (Join-Path $root 'fake-child.ps1') -Encoding utf8
        $fakeCli | Set-Content (Join-Path $root 'fake-claude.cmd') -Encoding ascii
        $profilePath = Join-Path $root '.sza-profile.json'
        $doc = Get-Content $profilePath -Raw | ConvertFrom-Json -AsHashtable
        if (-not $ArgsTemplate) { $ArgsTemplate = @('-NoProfile', '-File', (Join-Path $root 'fake-child.ps1'), '{prompt}') }
        $doc.runner = @{ command = $Command; argsTemplate = $ArgsTemplate; promptTemplate = $PromptTemplate; headlessMatch = [regex]::Escape((Split-Path $root -Leaf)) }
        $doc.locks = @{ agentProcessNames = @('pwsh.exe', 'pwsh', 'cmd.exe') }
        $doc | ConvertTo-Json -Depth 8 | Set-Content $profilePath -Encoding utf8
        return $root
    }
    function Invoke-Runner([string]$Project, [hashtable]$Environment = @{}, [string[]]$RunnerArgs = @('-TimeoutMinutes', '2', '-ClaimGraceSeconds', '3')) {
        $psi = [System.Diagnostics.ProcessStartInfo]::new((Get-Command pwsh -CommandType Application | Select-Object -First 1).Source)
        foreach ($a in (@('-NoProfile', '-File', (Join-Path $harness 'batch/run-spec-queue.ps1')) + $RunnerArgs)) { $psi.ArgumentList.Add($a) }
        $psi.WorkingDirectory = $Project
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.Environment['SZA_PROJECT_ROOT'] = $Project
        foreach ($k in $Environment.Keys) { $psi.Environment[$k] = $Environment[$k] }
        $proc = [System.Diagnostics.Process]::Start($psi)
        $out = $proc.StandardOutput.ReadToEndAsync()
        $err = $proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit(240000)) { & taskkill.exe /PID $proc.Id /T /F 2>&1 | Out-Null; throw 'the runner did not finish in 240 s' }
        [void]$out.Wait(15000); [void]$err.Wait(15000)
        [pscustomobject]@{ code = $proc.ExitCode; output = ($out.Result + $err.Result) }
    }
    function Get-Children([string]$Project) {
        $log = Join-Path $Project 'children.log'
        if (-not (Test-Path -LiteralPath $log)) { return @() }
        @(Get-Content -LiteralPath $log | ForEach-Object {
            $f = $_.Split('|', 3)
            [pscustomobject]@{ id = $f[0]; agent = $f[1].Substring('agent='.Length); args = $f[2].Substring('args='.Length) }
        })
    }

    Test-Case 'rule 28: a ticket a sibling holds is not launched, the free one is, and the lease the sibling holds is untouched' {
        $p = New-RunnerProject 'd-sibling' @('held', 'free')
        $env:SZA_AGENT_ID = 'sibling-session-0001'
        $claim = Invoke-Tool $p 'locks/ticket-lease.ps1' @('-Verb', 'Claim', '-Id', 'S0001', '-Reason', 'fixture', '-Json')
        $env:SZA_AGENT_ID = $savedAgent
        Assert-That ($claim.code -eq 0) "the sibling could not claim S0001: $($claim.output)"
        $r = Invoke-Runner $p
        Assert-That ($r.code -eq 0) "the runner exited $($r.code): $($r.output)"
        $launched = @(Get-Children $p | ForEach-Object { $_.id })
        Assert-That ($launched -notcontains 'S0001') 'a child was started for the ticket a sibling holds'
        Assert-That ($launched -contains 'S0002') "no child was started for the free ticket: $($r.output)"
        Assert-That ((Get-Row $p 'S0001').status -eq 'Draft') 'the held ticket moved'
        $held = Invoke-Tool $p 'locks/ticket-lease.ps1' @('-Verb', 'Status', '-Json')
        Assert-That ($held.output -match 'sibling-session-0001') 'the sibling''s lease is gone'
    }

    Test-Case 'rule 29: every child gets its own agent id, and an id leaked into the runner''s environment does not reach it' {
        $p = New-RunnerProject 'd-identity' @('one', 'two') 'pwsh' @('-p', '{prompt}')
        # The command is the project's own fake CLI, whose --help lists --session-id as the real one does.
        $profilePath = Join-Path $p '.sza-profile.json'
        $doc = Get-Content $profilePath -Raw | ConvertFrom-Json -AsHashtable
        $doc.runner.command = (Join-Path $p 'fake-claude.cmd')
        $doc | ConvertTo-Json -Depth 8 | Set-Content $profilePath -Encoding utf8
        $r = Invoke-Runner $p @{ SZA_AGENT_ID = 'launcher-leaked-id' }
        Assert-That ($r.code -eq 0) "the runner exited $($r.code): $($r.output)"
        $children = @(Get-Children $p)
        Assert-That ($children.Count -ge 2) "fewer than two children ran: $($r.output)"
        foreach ($c in $children) {
            Assert-That ($c.agent -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') "the child of $($c.id) ran as '$($c.agent)', not as an id of its own"
            Assert-That ($c.args -match "--session-id $($c.agent)") "the child of $($c.id) was not started under the id it was given"
        }
        Assert-That ((@($children | ForEach-Object { $_.agent } | Sort-Object -Unique)).Count -eq $children.Count) 'two children shared one agent id'
        # A CLI that does not list --session-id still gets its own agent id in its environment,
        # so an id leaked into the launcher's environment never reaches the child.
        $q = New-RunnerProject 'd-identity-plain' @('one')
        $r = Invoke-Runner $q @{ SZA_AGENT_ID = 'launcher-leaked-id' }
        $plain = @(Get-Children $q)
        Assert-That ($plain.Count -ge 1) "no child ran under a CLI without --session-id: $($r.output)"
        Assert-That ($plain[0].agent -ne 'launcher-leaked-id') "the leaked agent id reached the child: $($plain[0].agent)"
        Assert-That ($plain[0].agent -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') "child did not get its own uuid agent id: $($plain[0].agent)"
    }

    Test-Case 'rule 32: the prompt names the project''s pipeline with its mono flag and the id reaches the agent in the case the template writes it' {
        $p = New-RunnerProject 'd-prompt' @('one') 'pwsh' $null '/spec-all -m {Id}'
        $r = Invoke-Runner $p
        Assert-That ($r.code -eq 0) "the runner exited $($r.code): $($r.output)"
        $first = @(Get-Children $p)[0]
        Assert-That ($first.args -eq '/spec-all -m S0001') "the child received '$($first.args)'"
        $p2 = New-RunnerProject 'd-prompt-lower' @('one') 'pwsh' $null 'run the pipeline on {id} now'
        Invoke-Runner $p2 | Out-Null
        Assert-That (@(Get-Children $p2)[0].args -eq 'run the pipeline on S0001 now') '{id} in lower case was not substituted'
        # A project with no pipeline yet: the launcher's default prompt still carries the id.
        $r0 = Get-Content (Join-Path $p 'r0.ps1') -Raw
        Assert-That ($r0 -match '(?m)^\s*\[string\]\s+\$Prompt\s*=\s*''[^'']*\{id\}') 'the rendered launcher''s default prompt does not carry {id}'
    }

    Test-Case 'rule 34: R0 holds no claim or identity code, which is what R1..Rn add' {
        $p = New-Project 'd-r0-bare' @('one')
        $r0 = Get-Content (Join-Path $p 'r0.ps1') -Raw
        $coordination = 'ticket-lease|AGENT_ID|ClaimAs|-Verb\s+Claim|--session-id|spec-next-preflight'
        Assert-That ($r0 -notmatch $coordination) "the rendered R0 mentions coordination: $([regex]::Match($r0, $coordination).Value)"
        $full = Get-Content (Join-Path $harness 'batch/run-spec-queue.ps1') -Raw
        foreach ($needle in 'ticket-lease', 'AGENT_ID', 'claim-lost-before-launch', 'claim-lost') {
            Assert-That ($full.Contains($needle)) "the full runner no longer carries '$needle'"
        }
    }

    # === F. Complexity (S0015 R7) ===================================================================================

    # The runner's own reader of the line, copied from Get-TicketComplexity in batch/run-spec-queue.ps1 (not re-derived):
    # what capture-draft writes must be what the runner reads.
    $complexityReader = '^\*\*Complexity:\*\*\s*(.+?)\s*$'
    $notAssessed = 'medium - not assessed at capture'
    # The header block every reader of the line looks at: the first forty lines, as the runner reads them.
    function Get-HeaderLines([string]$Text) { @(($Text -split "`r?`n") | Select-Object -First 40) }
    function Get-LineIndex([string[]]$Lines, [string]$Pattern) {
        for ($i = 0; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -match $Pattern) { return $i } }
        return -1
    }

    Test-Case 'S0015 R7: capture-draft writes the Complexity line, medium - not assessed at capture by default' {
        $p = New-Project 'f-cx-default' @()
        $r = Assert-Tool $p 'spec_catalog/capture-draft.ps1' @('-Slug', 'task-one', '-Text', "the owner's words for one")
        $head = Get-HeaderLines (Get-SpecText $p 'S0001')
        $lines = @($head | Where-Object { $_ -match '^\*\*Complexity:\*\*\s+medium - not assessed at capture\s*$' })
        Assert-That ($lines.Count -eq 1) "the header holds $($lines.Count) default Complexity lines, not 1: $($head -join ' | ')"
        Assert-That (@($head | Where-Object { $_ -match '^\*\*Complexity:\*\*' }).Count -eq 1) 'the header holds more than one Complexity line'
        $status = Get-LineIndex $head '^\*\*Status:\*\*'
        $line = Get-LineIndex $head '^\*\*Complexity:\*\*'
        $owner = Get-LineIndex $head '^## 0\.'
        Assert-That ($status -ge 0 -and $owner -gt 0) "the header has no Status line or no '## 0.' heading: $($head -join ' | ')"
        Assert-That ($line -gt $status -and $line -lt $owner) "the Complexity line is at $line, not between Status ($status) and '## 0.' ($owner)"
        $m = [regex]::Match($lines[0], $complexityReader)
        Assert-That ($m.Success -and $m.Groups[1].Value -eq $notAssessed) "the runner's reader reads '$($m.Groups[1].Value)', not '$notAssessed'"
        $out = @($r.output -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        Assert-That ($out -contains "Complexity: $notAssessed") "capture-draft did not print 'Complexity: $notAssessed': $($r.output)"
        Assert-That ($out[-1] -eq 'S0001') "the last line printed is '$($out[-1])', not the id (insert.ps1 callers read the id from the last line)"
    }

    Test-Case 'S0015 R7: capture-draft -Complexity writes the given level and reason, and refuses a level outside light, medium, hard' {
        $p = New-Project 'f-cx-given' @()
        Assert-Tool $p 'spec_catalog/capture-draft.ps1' @('-Slug', 'task-hard', '-Text', 'words', '-Complexity', 'hard - a new subsystem') | Out-Null
        $head = Get-HeaderLines (Get-SpecText $p 'S0001')
        Assert-That (@($head | Where-Object { $_ -ceq '**Complexity:** hard - a new subsystem' }).Count -eq 1) "the given level is not written as given: $(@($head | Where-Object { $_ -match 'Complexity' }) -join ' | ')"
        Assert-That (@($head | Where-Object { $_ -match '^\*\*Complexity:\*\*' }).Count -eq 1) 'the header holds more than one Complexity line'
        Assert-Tool $p 'spec_catalog/capture-draft.ps1' @('-Slug', 'task-light', '-Text', 'words', '-Complexity', 'LIGHT - one string') | Out-Null
        $head = Get-HeaderLines (Get-SpecText $p 'S0002')
        Assert-That (@($head | Where-Object { $_ -ceq '**Complexity:** light - one string' }).Count -eq 1) "an upper-case level is not written lower-case: $(@($head | Where-Object { $_ -match 'Complexity' }) -join ' | ')"
        $rows = @(Get-Ledger $p).Count
        foreach ($bad in 'huge - x', 'hard', 'hard -') {
            $r = Invoke-Tool $p 'spec_catalog/capture-draft.ps1' @('-Slug', 'task-bad', '-Text', 'words', '-Complexity', $bad)
            Assert-That ($r.code -eq 2) "-Complexity '$bad' exited $($r.code), not 2: $($r.output)"
            Assert-That (@(Get-Ledger $p).Count -eq $rows) "-Complexity '$bad' still wrote a ledger row"
            Assert-That (-not (Test-Path -LiteralPath (Join-Path $p 'PLAN/S0003_task-bad.md'))) "-Complexity '$bad' still wrote a spec file"
            foreach ($level in 'light', 'medium', 'hard') {
                Assert-That ($r.output -match $level) "the refusal of '$bad' does not name the level '$level': $($r.output)"
            }
        }
    }

    Test-Case 'S0015 R7: a template without the token still gets the line and the owner''s words keep a literal token' {
        $p = New-Project 'f-cx-old-template' @()
        # The pre-S0015 template is the shipped one less its Complexity line: a project-owned copy written before the
        # change has no token. Taken from the tree, not from `git show HEAD:`, so the case survives the commit and a
        # -SourceRoot copy without .git. Written with CRLF, to show the inserted line follows the template's line ending.
        $shipped = [IO.File]::ReadAllText((Join-Path $SourceRoot 'tools/harness/scaffold/templates/ticket-template.md'))
        $old = ($shipped -replace '(?m)^\*\*Complexity:\*\*[^\r\n]*\r?\n', '') -replace '\r?\n', "`r`n"
        Assert-That (-not $old.Contains('{{COMPLEXITY}}')) 'the pre-S0015 template still carries the token'
        [IO.File]::WriteAllText((Join-Path $p 'PLAN/TICKET_TEMPLATE.md'), $old, [Text.UTF8Encoding]::new($false))
        $words = 'literal {{COMPLEXITY}} and $1 kept'
        Assert-Tool $p 'spec_catalog/capture-draft.ps1' @('-Slug', 'task-old', '-Text', $words) | Out-Null
        $text = Get-SpecText $p 'S0001'
        $head = Get-HeaderLines $text
        $line = Get-LineIndex $head '^\*\*Complexity:\*\*\s+medium - not assessed at capture\s*$'
        $created = Get-LineIndex $head '^\*\*Created:\*\*'
        $owner = Get-LineIndex $head '^## 0\.'
        Assert-That ($line -ge 0) "a token-less template got no Complexity line: $($head -join ' | ')"
        Assert-That ($line -eq $created + 1 -and $line -lt $owner) "the line is at $line, not directly after Created ($created) and above '## 0.' ($owner)"
        Assert-That ($text -notmatch '(?<!\r)\n') 'the CRLF template produced a spec with a bare LF line ending'
        $section = $text.Substring($text.IndexOf('## 0.'))
        Assert-That ($section.Contains($words)) "the owner's words were not kept byte for byte: $section"
        Assert-That (([regex]::Matches($text, [regex]::Escape('{{COMPLEXITY}}'))).Count -eq 1) 'the literal token in the owner''s words was expanded or duplicated'
        # The header sync of a status move must keep the line.
        Move-Ticket $p 'S0001' 'Approved'
        $after = Get-HeaderLines (Get-SpecText $p 'S0001')
        Assert-That ((Get-HeaderStatus (Get-SpecText $p 'S0001')) -eq 'Approved') 'the header was not synced to Approved'
        Assert-That (@($after | Where-Object { $_ -match '^\*\*Complexity:\*\*\s+medium - not assessed at capture\s*$' }).Count -eq 1) "the status rewrite dropped the Complexity line: $($after -join ' | ')"
    }

    Test-Case 'S0015 R7: validate warns on an Approved ticket still not assessed at capture, never fails' {
        $p = New-Project 'f-cx-validate' @('one')
        $v = Invoke-Tool $p 'spec_catalog/validate.ps1'
        Assert-That ($v.code -eq 0 -and $v.output -match '\[OK\]\s+Complexity') "(1) a Draft ticket: exit $($v.code), no '[OK] Complexity' line: $($v.output)"
        Move-Ticket $p 'S0001' 'Approved'
        $v = Invoke-Tool $p 'spec_catalog/validate.ps1'
        Assert-That ($v.code -eq 0) "(2) the warning changed the exit code to $($v.code): $($v.output)"
        Assert-That ($v.output -match '\[WARN\] Complexity\s+.*S0001') "(2) an Approved ticket still not assessed at capture was not reported: $($v.output)"
        Assert-That ($v.output -match 'Summary: \d+ OK, 1 WARN, 0 FAIL') "(2) the summary does not say 1 WARN: $($v.output)"
        # The check itself never fails; -Strict turning a warning into exit 1 is validate's existing contract.
        $s = Invoke-Tool $p 'spec_catalog/validate.ps1' @('-Strict')
        Assert-That ($s.code -eq 1) "(3) -Strict on the warning exited $($s.code), not 1: $($s.output)"
        $spec = Join-Path $p (Get-Row $p 'S0001').file
        $assessed = (Get-Content -LiteralPath $spec -Raw) -replace '(?m)^\*\*Complexity:\*\*[^\r\n]*', '**Complexity:** medium - assessed at the spec pass: one file, approach visible'
        [IO.File]::WriteAllText($spec, $assessed, [Text.UTF8Encoding]::new($false))
        $v = Invoke-Tool $p 'spec_catalog/validate.ps1'
        Assert-That ($v.code -eq 0 -and $v.output -match '\[OK\]\s+Complexity') "(4) a rewritten line is still reported: exit $($v.code): $($v.output)"
        # A pre-S0015 ticket has no line at all: absence is not a finding, the runner keeps its old routing for it.
        [IO.File]::WriteAllText($spec, ($assessed -replace '(?m)^\*\*Complexity:\*\*[^\r\n]*\r?\n', ''), [Text.UTF8Encoding]::new($false))
        Assert-That ((Get-Content -LiteralPath $spec -Raw) -notmatch 'Complexity') '(5) the fixture still carries a Complexity line'
        $v = Invoke-Tool $p 'spec_catalog/validate.ps1'
        Assert-That ($v.code -eq 0 -and $v.output -match '\[OK\]\s+Complexity') "(5) an Approved ticket with no line was reported: exit $($v.code): $($v.output)"
        # Only Approved is judged: the checkpoint immediately follows that transition.
        foreach ($status in 'Tactical', 'In Progress', 'Implemented') {
            $id = (Assert-Tool $p 'spec_catalog/capture-draft.ps1' @('-Slug', ('later-' + ($status -replace ' ', '-').ToLowerInvariant()), '-Text', 'words')).output -split "`r?`n" | Select-Object -Last 1
            Move-Ticket $p $id.Trim() $status
            Assert-That ((Get-SpecText $p $id.Trim()) -match "(?m)^\*\*Complexity:\*\*\s+$notAssessed\s*$") "(6) the $status fixture $id does not carry the default line"
        }
        $v = Invoke-Tool $p 'spec_catalog/validate.ps1'
        Assert-That ($v.code -eq 0 -and $v.output -match '\[OK\]\s+Complexity') "(6) a Tactical, In Progress or Implemented ticket with the default text was reported: exit $($v.code): $($v.output)"
    }

    # === G. Uniform launchers and adoption (S0015 R15, R36) =========================================================

    # The six launchers the scaffold renders beside r0.ps1. What they do when run is the runner suite's case C9
    # (batch-runner.tests.ps1); here only what is written, and when.
    $launcherNames = @('r1', 'r2', 'r3', 'rs', 'rm', 'rw')
    function Get-OutputLines([string]$Text) { @($Text -split "`r?`n" | ForEach-Object { $_.TrimEnd() }) }
    function Get-LauncherHashes([string]$Project, [string[]]$Names) {
        $h = [ordered]@{}
        foreach ($n in $Names) { $h[$n] = (Get-FileHash -LiteralPath (Join-Path $Project "$n.ps1") -Algorithm SHA256).Hash }
        return $h
    }

    Test-Case 'S0015 R36: the scaffold renders r0 and r1-r3, rs, rm, rw, never overwrites, is safe twice, and -NoLaunchers writes none of the six' {
        $p = New-Project 'g-launchers' @('one')
        $all = @('r0') + $launcherNames
        foreach ($n in $all) { Assert-That (Test-Path -LiteralPath (Join-Path $p "$n.ps1") -PathType Leaf) "the scaffold did not write $n.ps1" }
        $text = @{}
        foreach ($n in $launcherNames) {
            $t = [IO.File]::ReadAllText((Join-Path $p "$n.ps1"))
            $text[$n] = $t
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseInput($t, [ref]$null, [ref]$errors)
            Assert-That ($errors.Count -eq 0) "$n.ps1 does not parse: $($errors[0].Message)"
            Assert-That ($t -notmatch '\{\{\w+\}\}') "$n.ps1 holds an unfilled placeholder: $([regex]::Match($t, '\{\{\w+\}\}').Value)"
            Assert-That ($t.Contains('tools/harness.ps1')) "$n.ps1 does not forward through tools/harness.ps1"
            Assert-That ($t -notmatch 'ticket-lease|AGENT_ID|ConvertFrom-Json|\.sza-profile') "$n.ps1 reads the profile or makes a coordination call of its own"
        }
        # The fixed values are rendered as a table the launcher turns into -Name value at run time (C9 runs them).
        foreach ($pair in @(@('r1', 'a'), @('r2', 'b'), @('r3', 'c'))) {
            $t = $text[$pair[0]]
            Assert-That ($t.Contains('batch/run-spec-queue')) "$($pair[0]).ps1 does not target batch/run-spec-queue"
            Assert-That ($t -match "\bInstance\s*=\s*'$($pair[1])'") "$($pair[0]).ps1 does not fix the instance '$($pair[1])'"
            Assert-That ($t -match '\bQuiet\s*=\s*\$true') "$($pair[0]).ps1 does not fix -Quiet"
            Assert-That ($t -match "\bPermissionMode\s*=\s*'bypassPermissions'") "$($pair[0]).ps1 does not carry the scaffold's permission mode"
        }
        Assert-That ($text.r1 -notmatch 'StartDelaySeconds') 'r1.ps1 is delayed; only r2 and r3 are'
        Assert-That ($text.r2 -match '\bStartDelaySeconds\s*=\s*20\b') 'r2.ps1 does not fix StartDelaySeconds 20'
        Assert-That ($text.r3 -match '\bStartDelaySeconds\s*=\s*40\b') 'r3.ps1 does not fix StartDelaySeconds 40'
        Assert-That ($text.rs.Contains('batch/run-spec-queue') -and $text.rs -match '\bStop\s*=\s*\$true') 'rs.ps1 is not run-spec-queue -Stop'
        Assert-That ($text.rm.Contains('batch/monitor-spec-queue')) 'rm.ps1 does not target batch/monitor-spec-queue'
        Assert-That ($text.rw.Contains('portfolio/pq') -and $text.rw -match "'start'") 'rw.ps1 is not pq start'
        Assert-That ($text.rw -match '\bRepos\s*=\s*\$PSScriptRoot') 'rw.ps1 does not scope pq start to its own repository'

        # Safe twice: nothing created or replaced, every byte the same.
        $before = Get-LauncherHashes $p $all
        $again = Assert-Tool $p 'scaffold/init-task-flow.ps1' @('-Root', $p)
        $wrote = @(Get-OutputLines $again.output | Where-Object { $_ -match '^(created|replaced)\s' })
        Assert-That ($wrote.Count -eq 0) "a second run wrote: $($wrote -join ' | ')"
        $after = Get-LauncherHashes $p $all
        foreach ($n in $all) { Assert-That ($before[$n] -eq $after[$n]) "a second run changed $n.ps1" }

        # Never overwrites what the project made its own.
        [IO.File]::WriteAllText((Join-Path $p 'r1.ps1'), '# mine', [Text.UTF8Encoding]::new($false))
        $again = Assert-Tool $p 'scaffold/init-task-flow.ps1' @('-Root', $p)
        Assert-That ([IO.File]::ReadAllText((Join-Path $p 'r1.ps1')) -ceq '# mine') 'a run without -Force overwrote the project''s r1.ps1'
        Assert-That (@(Get-OutputLines $again.output | Where-Object { $_ -match '^exists\s+r1\.ps1$' }).Count -eq 1) "no 'exists r1.ps1' line: $($again.output)"

        # -Force replaces the generated launchers and never the profile or the ledger.
        $profileHash = (Get-FileHash -LiteralPath (Join-Path $p '.sza-profile.json')).Hash
        $ledgerHash = (Get-FileHash -LiteralPath (Join-Path $p 'PLAN/spec-catalog.jsonl')).Hash
        $forced = Assert-Tool $p 'scaffold/init-task-flow.ps1' @('-Root', $p, '-Force')
        foreach ($n in $launcherNames) {
            Assert-That (@(Get-OutputLines $forced.output | Where-Object { $_ -match "^replaced\s+$n\.ps1$" }).Count -eq 1) "-Force did not replace $n.ps1: $($forced.output)"
        }
        Assert-That ([IO.File]::ReadAllText((Join-Path $p 'r1.ps1')) -ceq $text.r1) '-Force did not restore the generated r1.ps1'
        Assert-That ((Get-FileHash -LiteralPath (Join-Path $p '.sza-profile.json')).Hash -eq $profileHash) '-Force replaced the profile'
        Assert-That ((Get-FileHash -LiteralPath (Join-Path $p 'PLAN/spec-catalog.jsonl')).Hash -eq $ledgerHash) '-Force replaced the ledger'

        # -NoLaunchers and -NoForwarder write none of the six, and say why.
        foreach ($switch in '-NoLaunchers', '-NoForwarder') {
            $q = Join-Path $scratch ('g-launchers' + $switch.ToLowerInvariant())
            New-Item -ItemType Directory -Path $q | Out-Null
            $r = Assert-Tool $q 'scaffold/init-task-flow.ps1' @('-Root', $q, $switch)
            Assert-That (Test-Path -LiteralPath (Join-Path $q 'r0.ps1') -PathType Leaf) "$switch also dropped r0.ps1"
            $present = @($launcherNames | Where-Object { Test-Path -LiteralPath (Join-Path $q "$_.ps1") })
            Assert-That ($present.Count -eq 0) "$switch still wrote: $($present -join ', ')"
            $note = @(Get-OutputLines $r.output | Where-Object { $_ -match "^skipped\s+.*r1\.ps1.*$([regex]::Escape($switch))" })
            Assert-That ($note.Count -eq 1) "$switch printed no single 'skipped' line naming the launchers and the reason: $($r.output)"
            if ($switch -eq '-NoForwarder') {
                Assert-That ($note[0] -match 'tools/harness\.ps1') "the -NoForwarder note does not say the launchers forward through tools/harness.ps1: $($note[0])"
            }
        }
    }

    Test-Case 'S0015 R36: a new profile carries runner.promptTemplate and an existing profile is left alone' {
        $p = Join-Path $scratch 'g-profile-new'
        New-Item -ItemType Directory -Path $p | Out-Null
        $r = Assert-Tool $p 'scaffold/init-task-flow.ps1' @('-Root', $p, '-Prompt', 'work {id} now')
        $doc = Get-Content -LiteralPath (Join-Path $p '.sza-profile.json') -Raw | ConvertFrom-Json
        Assert-That ((@($doc.PSObject.Properties.Name) -join ',') -eq 'version,projectName,runner') "the new profile's keys are '$(@($doc.PSObject.Properties.Name) -join ',')'"
        Assert-That ($doc.version -eq '1' -and $doc.projectName -eq 'g-profile-new') "version '$($doc.version)', projectName '$($doc.projectName)'"
        Assert-That ((@($doc.runner.PSObject.Properties.Name) -join ',') -eq 'promptTemplate') "the runner block holds '$(@($doc.runner.PSObject.Properties.Name) -join ',')', not only promptTemplate"
        Assert-That ($doc.runner.promptTemplate -ceq 'work {Id} now') "runner.promptTemplate is '$($doc.runner.promptTemplate)', not 'work {Id} now'"
        Assert-That ($r.output -notmatch '(?m)^note: .*runner\.promptTemplate') "a new profile got the existing-profile note: $($r.output)"

        # An existing profile with no runner block: its bytes stay, and the output says what r1-r3 will send.
        $q = Join-Path $scratch 'g-profile-old'
        New-Item -ItemType Directory -Path $q | Out-Null
        $own = Join-Path $q '.sza-profile.json'
        [IO.File]::WriteAllText($own, "{`r`n    ""version"": ""1"",`r`n    ""projectName"": ""mine""`r`n}`r`n", [Text.UTF8Encoding]::new($false))
        $hash = (Get-FileHash -LiteralPath $own).Hash
        $r = Assert-Tool $q 'scaffold/init-task-flow.ps1' @('-Root', $q, '-Prompt', 'work {id} now')
        Assert-That ((Get-FileHash -LiteralPath $own).Hash -eq $hash) 'the existing profile was rewritten'
        Assert-That ($r.output -match '(?m)^note: .*runner\.promptTemplate') "no note about runner.promptTemplate for an existing profile without one: $($r.output)"

        # An existing profile that already declares its prompt gets no note.
        $s = Join-Path $scratch 'g-profile-own-prompt'
        New-Item -ItemType Directory -Path $s | Out-Null
        [IO.File]::WriteAllText((Join-Path $s '.sza-profile.json'), '{ "version": "1", "projectName": "own", "runner": { "promptTemplate": "/go {Id}" } }', [Text.UTF8Encoding]::new($false))
        $r = Assert-Tool $s 'scaffold/init-task-flow.ps1' @('-Root', $s)
        Assert-That ($r.output -notmatch '(?m)^note: .*runner\.promptTemplate') "a profile that declares runner.promptTemplate still got the note: $($r.output)"
    }

    # Adoption ends in 'pq register'. The block is read from the skill text, never re-typed here, so the case
    # proves what an adopting session pastes. Every pq call gets SZA_PORTFOLIO_ROOT on the child only, pointing
    # under this suite's scratch directory: the owner's registry is never read or written.
    function New-StampedRepo([string]$Name) {
        $dir = Join-Path $scratch $Name
        New-Item -ItemType Directory -Path $dir | Out-Null
        & git -C $dir init -q 2>&1 | Out-Null
        [IO.File]::WriteAllText((Join-Path $dir '.sza-canon.json'), '{ "schemaVersion": "1.0", "role": "product" }', [Text.UTF8Encoding]::new($false))
        return $dir
    }
    function New-PortfolioRoot([string]$Name) {
        $root = Join-Path $scratch "pq-$Name"
        New-Item -ItemType Directory -Path $root | Out-Null
        return $root
    }
    # The first fenced powershell block of a skill that calls portfolio/pq.ps1, line endings normalised to LF.
    function Get-JoinBlock([string]$Skill) {
        $file = Join-Path $SourceRoot "skills/$Skill/SKILL.md"
        $text = ''
        if (Test-Path -LiteralPath $file -PathType Leaf) { $text = [IO.File]::ReadAllText($file) -replace "`r`n", "`n" }
        foreach ($m in [regex]::Matches($text, '(?ms)^[ \t]*```powershell[ \t]*\n(.*?)^[ \t]*```[ \t]*$')) {
            if ($m.Groups[1].Value.Contains('portfolio/pq.ps1')) { return $m.Groups[1].Value }
        }
        throw "no fenced powershell block that calls portfolio/pq.ps1 in $Skill"
    }
    # Run a block the way a session pastes it: '$sza = <plugin root>' first, the repository as working directory.
    function Invoke-JoinBlock([string]$Block, [string]$Sza, [string]$WorkDir, [string]$PortfolioRoot) {
        Assert-That ($PortfolioRoot -and $PortfolioRoot.StartsWith($scratch, [StringComparison]::OrdinalIgnoreCase)) "refusing to run pq without a scratch SZA_PORTFOLIO_ROOT (got '$PortfolioRoot')"
        $code = "`$sza = '$($Sza -replace "'", "''")'`n" + $Block
        $psi = [System.Diagnostics.ProcessStartInfo]::new((Get-Command pwsh -CommandType Application | Select-Object -First 1).Source)
        foreach ($a in @('-NoProfile', '-NonInteractive', '-Command', $code)) { $psi.ArgumentList.Add($a) }
        $psi.WorkingDirectory = $WorkDir
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.Environment['SZA_PORTFOLIO_ROOT'] = $PortfolioRoot
        $null = $psi.Environment.Remove('SZA_PROJECT_ROOT')
        $proc = [System.Diagnostics.Process]::Start($psi)
        $out = $proc.StandardOutput.ReadToEndAsync()
        $err = $proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit(120000)) { $proc.Kill($true); throw "the join block did not finish in 120 s in $WorkDir" }
        $proc.WaitForExit()
        [pscustomobject]@{ code = $proc.ExitCode; output = ($out.Result + $err.Result).Trim() }
    }
    function Get-RegisteredRows([string]$PortfolioRoot, [string]$Dir) {
        $file = Join-Path $PortfolioRoot 'repos.json'
        Assert-That (Test-Path -LiteralPath $file -PathType Leaf) "no registry at $file"
        $doc = [IO.File]::ReadAllText($file) | ConvertFrom-Json -DateKind String
        $want = [IO.Path]::GetFullPath($Dir).TrimEnd('\', '/')
        @(@($doc.repos) | Where-Object { [string]::Equals([IO.Path]::GetFullPath([string]$_.path).TrimEnd('\', '/'), $want, [StringComparison]::OrdinalIgnoreCase) })
    }
    # Every event the cli writer logged under a portfolio root (events-<UTC date>.cli-<pid>.jsonl, one file per process).
    function Get-CliEvents([string]$PortfolioRoot) {
        $log = Join-Path $PortfolioRoot 'log'
        if (-not (Test-Path -LiteralPath $log)) { return @() }
        $files = @(Get-ChildItem -LiteralPath $log -File | Where-Object { $_.Name -match '^events-\d{4}-\d{2}-\d{2}\.cli(-\d+)?\.jsonl$' })
        @($files | ForEach-Object { Read-Jsonl $_.FullName })
    }
    # Run the block twice against the plugin under test: one record, one registry.changed, one owner.action.
    function Assert-JoinRegisters([string]$Block, [string]$Dir, [string]$PortfolioRoot, [string]$Label) {
        $days = @([DateTime]::UtcNow.ToString('yyyy-MM-dd'))
        $first = Invoke-JoinBlock $Block $SourceRoot $Dir $PortfolioRoot
        Assert-That ($first.code -eq 0) "${Label}: the first run exited $($first.code): $($first.output)"
        $key = [regex]::Match($first.output, '(?m)^registered (\S+)\s*$').Groups[1].Value
        Assert-That ($key -ne '') "${Label}: the first run printed no 'registered <key>' line: $($first.output)"
        $rows = @(Get-RegisteredRows $PortfolioRoot $Dir)
        Assert-That ($rows.Count -eq 1) "${Label}: the registry holds $($rows.Count) records for $Dir after the first run, not 1"
        Assert-That ($rows[0].key -ceq $key -and $rows[0].enabled -eq $false) "${Label}: the record is key '$($rows[0].key)' enabled '$($rows[0].enabled)', not '$key' disabled"
        $second = Invoke-JoinBlock $Block $SourceRoot $Dir $PortfolioRoot
        Assert-That ($second.code -eq 0) "${Label}: the second run exited $($second.code): $($second.output)"
        Assert-That ($second.output -match "(?m)^already registered $([regex]::Escape($key))\s*$") "${Label}: the second run did not say 'already registered $key': $($second.output)"
        $rows = @(Get-RegisteredRows $PortfolioRoot $Dir)
        Assert-That ($rows.Count -eq 1) "${Label}: the registry holds $($rows.Count) records for $Dir after the second run, not 1"
        $days += [DateTime]::UtcNow.ToString('yyyy-MM-dd')
        $names = @(Get-ChildItem -LiteralPath (Join-Path $PortfolioRoot 'log') -File -Filter 'events-*.jsonl' | ForEach-Object Name)
        foreach ($n in $names) {
            Assert-That ($n -match '^events-(\d{4}-\d{2}-\d{2})\.cli(-\d+)?\.jsonl$' -and $days -contains $Matches[1]) "${Label}: an event file that is not the cli writer's for the UTC day: $n"
        }
        $events = @(Get-CliEvents $PortfolioRoot)
        $actions = @($events | Where-Object { $_.ev -ceq 'owner.action' -and $_.d.verb -ceq 'register' })
        Assert-That ($actions.Count -eq 1) "${Label}: $($actions.Count) owner.action register events, not 1 (the second run registers nothing)"
        Assert-That (@($actions[0].d.args) -contains 'Path' -and @($actions[0].d.args) -notcontains $Dir) "${Label}: owner.action args are '$(@($actions[0].d.args) -join ',')', not parameter names with Path"
        $changed = @($events | Where-Object { $_.ev -ceq 'registry.changed' })
        Assert-That ($changed.Count -eq 1) "${Label}: $($changed.Count) registry.changed events, not 1 (the second run changes nothing)"
        Assert-That ($changed[0].d.by -ceq 'cli' -and (@($changed[0].d.added) -join ',') -ceq $key) "${Label}: registry.changed by '$($changed[0].d.by)' added '$(@($changed[0].d.added) -join ',')', not by cli added $key"
    }

    Test-Case 'S0015 R36: a throwaway repository taken through the adoption steps ends registered, twice without a second row' {
        $real = Join-Path $env:USERPROFILE '.sza/portfolio/repos.json'
        $realBefore = if (Test-Path -LiteralPath $real) { (Get-FileHash -LiteralPath $real).Hash } else { 'absent' }
        $dir = New-StampedRepo 'g-adopt'
        Assert-Tool $dir 'scaffold/init-task-flow.ps1' @('-Root', $dir) | Out-Null
        $block = Get-JoinBlock 'adopt-canon'
        Assert-JoinRegisters $block $dir (New-PortfolioRoot 'adopt') 'adopt-canon'
        $realAfter = if (Test-Path -LiteralPath $real) { (Get-FileHash -LiteralPath $real).Hash } else { 'absent' }
        Assert-That ($realAfter -eq $realBefore) "the owner's registry $real changed during the case"
    }

    Test-Case 'S0015 R36: the adoption snippet fails soft when pq is absent' {
        $blocks = [ordered]@{}
        foreach ($skill in 'adopt-canon', 'task-flow-init') { $blocks[$skill] = Get-JoinBlock $skill }
        Assert-That ($blocks['task-flow-init'] -ceq $blocks['adopt-canon']) 'the join block of task-flow-init is not byte for byte the one of adopt-canon'
        foreach ($skill in $blocks.Keys) {
            $noPq = Join-Path $scratch "g-plugin-without-pq-$skill"
            New-Item -ItemType Directory -Path $noPq | Out-Null
            $dir = New-StampedRepo "g-join-$skill"
            $root = New-PortfolioRoot "nopq-$skill"
            $r = Invoke-JoinBlock $blocks[$skill] $noPq $dir $root
            Assert-That ($r.code -eq 0) "${skill}: with no pq in the plugin the block exited $($r.code): $($r.output)"
            Assert-That ($r.output -match 'Update the plugin') "${skill}: the output does not tell the owner to update the plugin: $($r.output)"
            Assert-That ($r.output.Contains('portfolio/pq.ps1 register') -and $r.output.Contains($dir)) "${skill}: the output does not give the command to run afterwards: $($r.output)"
            $written = @(Get-ChildItem -LiteralPath $root -Recurse -Force)
            Assert-That ($written.Count -eq 0) "${skill}: with no pq the block wrote under the portfolio root: $($written.Name -join ', ')"
            Assert-JoinRegisters $blocks[$skill] $dir (New-PortfolioRoot "with-pq-$skill") $skill
        }
    }
}
catch {
    "FAIL setup - $($_.Exception.Message)"
    $failed++
    $run++
    $setupFailed = $true
}
finally {
    $env:SZA_PROJECT_ROOT = $savedRoot
    $env:SZA_PROFILE_PATH = $savedProfile
    $env:SZA_AGENT_ID = $savedAgent
    if ($scratch -and -not $KeepScratch -and (Test-Path -LiteralPath $scratch)) {
        Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($setupFailed) { "ledger-rules-tests: COULD NOT VERIFY (run=$run skipped=0 gaps=$gaps)"; exit 2 }
if ($failed -gt 0) { "ledger-rules-tests: FAIL (run=$run skipped=0 gaps=$gaps)"; exit 1 }
"ledger-rules-tests: PASS (run=$run skipped=0 gaps=$gaps)"
exit 0
