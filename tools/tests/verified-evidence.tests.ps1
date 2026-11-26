#requires -Version 7.0
<#
.SYNOPSIS
  CANONR-0202, TASK-FLOW 0.48 section 24: what a `## Last Audit` block must hold before a ticket enters Verified.
  The patterns of spec_catalog/_audit-evidence.ps1 on literal lines, then real transitions of update.ps1 and the
  report of list-thin-verified.ps1 over a throwaway repository under the system temp directory, all in this one
  process. Writes nothing outside that directory.
.DESCRIPTION
  Cases:
    lines   - an executed-check line in each accepted spelling counts; a command without backticks, exit 1, exit 05,
              a bare `exit 0` and an unticked item do not
    lines   - a RELEASE item or a RELEASE count above 0 is open; RELEASE 0, `RELEASE: none`, RELEASE_QUEUE.md and a
              `Release gate:` line are not
    refused - Draft and Implemented into Verified with an audit that records no executed check
    refused - a recorded check beside an open RELEASE item; the row keeps its status and the refusal says why
    admitted - Draft and Implemented into Verified with a recorded check and no RELEASE item
    kept    - a bare audit still passes the BlockNeedUserTest gate, and a row already Verified reaffirms its status
    report  - list-thin-verified lists the one thin Verified row and leaves the ledger byte for byte
  Exit 0 when every case passed, 1 on any failure.
#>
[CmdletBinding()]
param([switch] $KeepScratch)

$ErrorActionPreference = 'Stop'

$Catalog = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\harness\spec_catalog'))
$run = 0; $passed = 0; $failed = 0
function Assert-Equal($Actual, $Expected, [string] $What) {
    if ("$Actual" -cne "$Expected") { throw "$What - expected '$Expected', got '$Actual'" }
}
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}
function Write-Utf8([string] $Path, [string] $Text) {
    $dir = [IO.Path]::GetDirectoryName($Path)
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('tf-verified-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$saved = @{ SZA_PORTFOLIO_ROOT = $env:SZA_PORTFOLIO_ROOT; SZA_PROJECT_ROOT = $env:SZA_PROJECT_ROOT; SZA_PQ_IN_SYNC = $env:SZA_PQ_IN_SYNC }
try {
    . (Join-Path $Catalog '_audit-evidence.ps1')

    Run-Case 'lines: executed-check spellings count, look-alikes do not' {
        foreach ($line in '- `tool -x` - exit 0', '1. PASS - `a b`, exit code 0. expected 0', '- `a` -> Exit: 0', '`a`: exit=0', '- [x] `a` exit 0') {
            Assert-Equal (Get-AuditEvidence -Lines @($line)).Executed 1 "counted: $line"
        }
        foreach ($line in '- tool -x - exit 0', '- `a` - exit 1', '- `a` - exit 05', '- the gate returns `exit 0`', '- [ ] `a` exit 0') {
            Assert-Equal (Get-AuditEvidence -Lines @($line)).Executed 0 "not counted: $line"
        }
    }
    Run-Case 'lines: open release items are seen, their absence is not mistaken for one' {
        foreach ($line in '- RELEASE - `a`', '1. RELEASE: rerun the suite', 'RELEASE `a`', '- [ ] **RELEASE** `a`', '- RELEASE: none of them ran') {
            Assert-Equal (Get-AuditEvidence -Lines @($line)).Unrun 1 "open: $line"
        }
        Assert-Equal (Get-AuditEvidence -Lines @('**Counts:** PASS 4 | FAIL 0 | RELEASE 3', '- RELEASE `a`')).Unrun 3 'the count wins over fewer lines'
        $none = @('**Counts:** PASS 4 | FAIL 0 | RELEASE 0', '- RELEASE: none', 'RELEASE_QUEUE.md was read', '- RELEASE-LEDGER row read', '**Release gate:** suite')
        Assert-Equal (Get-AuditEvidence -Lines $none).Unrun 0 'nothing open'
    }

    $thin = "- Read the code; nothing was run."
    $proven = "**Counts:** PASS 1 | WARN 0 | FAIL 0 | MANUAL 0 | UNCHECKABLE 0 | EXEMPT 0 | RELEASE 0`n`n- ``pwsh -File gate.ps1`` - exit 0"
    $unrun = "**Counts:** PASS 1 | WARN 0 | FAIL 0 | MANUAL 0 | UNCHECKABLE 0 | EXEMPT 0 | RELEASE 1`n`n- ``pwsh -File gate.ps1`` - exit 0`n- RELEASE ``pwsh -File slow.ps1``"
    $fixtures = @(
        @{ id = 'S0001'; status = 'Draft'; audit = $thin },
        @{ id = 'S0002'; status = 'Implemented'; audit = $thin },
        @{ id = 'S0003'; status = 'Implemented'; audit = $unrun },
        @{ id = 'S0005'; status = 'Draft'; audit = $proven },
        @{ id = 'S0006'; status = 'Implemented'; audit = $proven },
        @{ id = 'S0007'; status = 'Draft'; audit = $thin },
        @{ id = 'S0008'; status = 'Verified'; audit = $thin },
        @{ id = 'S0009'; status = 'Draft'; audit = '' }
    )
    $repo = Join-Path $scratch 'repo'
    Write-Utf8 (Join-Path $repo '.sza-profile.json') '{"probes":{"enabled":false}}'
    $rows = foreach ($f in $fixtures) {
        $file = "PLAN/$($f.id)_t.md"
        Write-Utf8 (Join-Path $repo $file) "# $($f.id)_t`n`n**Status:** $($f.status)`n`n**Device check:** Look at the window; no command observes it.`n`n## Last Audit`n`n$($f.audit)`n"
        [ordered]@{ id = $f.id; name = 't'; status = $f.status; priority = 50; file = $file; created = '2026-11-26'; updated = '2026-11-26 00:00' } | ConvertTo-Json -Compress
    }
    $ledger = Join-Path $repo 'PLAN\spec-catalog.jsonl'
    Write-Utf8 $ledger (($rows -join "`n") + "`n")
    $env:SZA_PORTFOLIO_ROOT = Join-Path $scratch 'portfolio'
    $env:SZA_PROJECT_ROOT = $repo
    $env:SZA_PQ_IN_SYNC = '1'

    function Get-RowStatus([string] $Id) {
        return [string](Get-Content -LiteralPath $ledger -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.id -eq $Id }).status
    }
    function Move-Status([string] $Id, [string] $Status, [string] $Note) {
        $said = [System.Collections.Generic.List[string]]::new()
        $extra = @{}; if ($Note) { $extra.StatusNote = $Note }
        try { & (Join-Path $Catalog 'update.ps1') -Id $Id -Status $Status @extra *>&1 | ForEach-Object { $said.Add([string]$_) } }
        catch { $said.Add($_.Exception.Message) }
        return ($said -join "`n")
    }

    Run-Case 'refused: Draft and Implemented into Verified with no executed check' {
        foreach ($t in @(@('S0001', 'Draft'), @('S0002', 'Implemented'))) {
            $said = Move-Status $t[0] 'Verified'
            Assert-Equal (Get-RowStatus $t[0]) $t[1] "$($t[0]) keeps its status: $said"
            Assert-Equal ($said -match 'no executed-check line') $true "$($t[0]) refusal: $said"
        }
    }
    Run-Case 'refused: a recorded check beside an open RELEASE item does not admit Verified' {
        $said = Move-Status 'S0003' 'Verified'
        Assert-Equal (Get-RowStatus 'S0003') 'Implemented' "S0003 keeps its status: $said"
        Assert-Equal ($said -match 'Implemented \(unrun checks: 1\)') $true "S0003 refusal: $said"
    }
    Run-Case 'admitted: Draft and Implemented into Verified with a recorded check' {
        foreach ($id in 'S0005', 'S0006') {
            $said = Move-Status $id 'Verified'
            Assert-Equal (Get-RowStatus $id) 'Verified' "$id : $said"
        }
    }
    Run-Case 'kept: a bare audit passes the BlockNeedUserTest gate, a Verified row reaffirms its status' {
        # The checker itself, in this process: an accepted transition costs a child process for its chat post.
        $gate = Join-Path $Catalog 'check-audit-recorded.ps1'
        $said = & $gate -Id 'S0007' -NewStatus 'BlockNeedUserTest' *>&1 | Out-String
        Assert-Equal $LASTEXITCODE 0 "owner test: $said"
        $said = & $gate -Id 'S0009' -NewStatus 'BlockNeedUserTest' *>&1 | Out-String
        Assert-Equal $LASTEXITCODE 1 "an empty audit is still refused: $said"
        $said = Move-Status 'S0008' 'Verified'
        Assert-Equal ($said -match 'Status gate blocked') $false "reaffirmation: $said"
        Assert-Equal (Get-RowStatus 'S0008') 'Verified' 'the row stays'
    }
    Run-Case 'report: the one thin Verified row is listed and nothing is written' {
        $before = [IO.File]::ReadAllBytes($ledger)
        $report = (& (Join-Path $Catalog 'list-thin-verified.ps1') -Root $repo -Json | Out-String) | ConvertFrom-Json
        Assert-Equal $report.verified 3 'Verified rows'
        Assert-Equal (($report.tickets.id) -join ',') 'S0008' 'the thin one'
        Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes($ledger))) ([Convert]::ToBase64String($before)) 'the ledger is untouched'
    }
}
finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    if (-not $KeepScratch -and (Test-Path -LiteralPath $scratch)) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host "run=$run passed=$passed failed=$failed"
if ($failed -gt 0) { exit 1 }
exit 0
