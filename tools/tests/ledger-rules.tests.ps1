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
        if ($r.output -match 'file authoritative') {
            Write-Gap 'rule 4: the picker reports the mismatch and calls the FILE authoritative; the rule says the reader trusts the ledger'
        }
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

    Test-Case 'rules 6 and 7: leaving a Block* status clears its note, and the one-level exit is only a convention' {
        $p = New-Project 'a-block' @('b')
        Move-Ticket $p 'S0001' 'BlockExternal' 'waiting for a vendor'
        Assert-That ((Get-Row $p 'S0001').statusNote -eq 'waiting for a vendor') 'the note was not kept'
        Assert-That ((Get-SpecText $p 'S0001') -match '(?m)^\*\*Status note:\*\*\s*waiting for a vendor') 'the note is not mirrored under the status line'
        $r = Invoke-Tool $p 'spec_catalog/update.ps1' @('-Id', 'S0001', '-Status', 'Implemented')
        if ($r.code -eq 0) {
            Assert-That (-not (Get-Row $p 'S0001').PSObject.Properties.Name.Contains('statusNote') -or -not (Get-Row $p 'S0001').statusNote) 'the note outlived the Block* status'
            Write-Gap 'rule 6: a Block* ticket leaves to any status (Draft -> BlockExternal -> Implemented was accepted); the rule says it advances exactly one level, and the ledger keeps no record of the level it left'
        }
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
        # A CLI that does not list --session-id gets no identity from the runner, so a leaked id reaches the child.
        $q = New-RunnerProject 'd-identity-plain' @('one')
        $r = Invoke-Runner $q @{ SZA_AGENT_ID = 'launcher-leaked-id' }
        $plain = @(Get-Children $q)
        Assert-That ($plain.Count -ge 1) "no child ran under a CLI without --session-id: $($r.output)"
        if ($plain[0].agent -eq 'launcher-leaked-id') {
            Write-Gap 'rule 29: for a CLI whose --help does not list --session-id the runner gives the child no identity, so an id leaked into the launcher''s environment is the child''s; the identity half of the rule holds for the CLI that lists the flag'
        }
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
