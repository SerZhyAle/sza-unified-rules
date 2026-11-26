#requires -Version 7.0
<#
.SYNOPSIS
  CANONR-0210, TASK-FLOW 0.53 section 29: a spec file above 40960 bytes is handed on only with a link to its evidence
  log. The link test and check-spec-size.ps1 over literal fixtures, then real transitions of update.ps1 over a
  throwaway repository under the system temp directory. Writes nothing outside that directory.
.DESCRIPTION
  Cases:
    link    - an evidence link is read in its accepted spellings; a line without a leading `Evidence:`, a bare path, a
              missing file, a file outside the ticket's evidence/ folder, a rooted path, a URL, a '..' path and a
              quoted line are none
    gate    - check-spec-size.ps1 passes 40960 bytes, refuses 40961 without a link and passes it with one
    refused - Implemented, Verified and BlockNeedUserTest refuse a new entry of an oversized spec without a link
    admit   - with a link the entry passes and the link holds after the file and the folder moved (rule 70)
    kept    - a reaffirmation and Archived are not gated
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

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('tf-specgate-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$saved = @{ SZA_PORTFOLIO_ROOT = $env:SZA_PORTFOLIO_ROOT; SZA_PROJECT_ROOT = $env:SZA_PROJECT_ROOT; SZA_PQ_IN_SYNC = $env:SZA_PQ_IN_SYNC }
try {
    . (Join-Path $Catalog '_spec-size.ps1')

    Run-Case 'link: accepted spellings are read, look-alikes are none' {
        $spec = Join-Path $scratch 'link\S0009_t.md'
        Write-Utf8 (Join-Path $scratch 'link\S0009_t\evidence\log.md') "log`n"
        Write-Utf8 (Join-Path $scratch 'link\S0009_t\research\note.md') "note`n"
        Write-Utf8 (Join-Path $scratch 'link\other\evidence\log.md') "log`n"
        $good = 'S0009_t/evidence/log.md'
        foreach ($line in "Evidence: [log]($good)", "- **Evidence:** [log](./$good)", "1. Evidence: see [x](https://a.example/b) and [log]($good#today)") {
            Write-Utf8 $spec "# t`n`n$line`n"
            Assert-Equal ((Find-SpecEvidenceLink -Path $spec) -ne '') $true "link: $line"
        }
        $rooted = (Join-Path $scratch "link\$good") -replace '\\', '/'
        foreach ($line in "See [log]($good)", "The Evidence: [log]($good)", "Evidence: $good", 'Evidence: [log](S0009_t/evidence/gone.md)',
            'Evidence: [log](S0009_t/research/note.md)', 'Evidence: [log](other/evidence/log.md)', 'Evidence: [log](S0009_t/evidence/../evidence/log.md)',
            "Evidence: [log](/$good)", "Evidence: [log]($rooted)", "Evidence: [log](https://a.example/$good)", "``````text`nEvidence: [log]($good)`n``````") {
            Write-Utf8 $spec "# t`n`n$line`n"
            Assert-Equal (Find-SpecEvidenceLink -Path $spec) '' "none: $line"
        }
    }

    $audit = "**Device check:** Look at the window.`n`n## Last Audit`n`n**Counts:** PASS 1 | FAIL 0 | RELEASE 0`n`n- ``pwsh -File gate.ps1`` - exit 0"
    # A spec of exactly the asked size: ASCII only, so a character is a byte.
    function New-SizedSpec([string] $Id, [string] $Status, [int] $Bytes, [string] $Line) {
        $head = "# ${Id}_t`n`n**Status:** $Status`n`n$Line`n`n$audit`n`n## 3. Approach`n`n"
        Write-Utf8 (Join-Path $repo "PLAN\${Id}_t.md") ($head + ('x' * ($Bytes - $head.Length - 1)) + "`n")
    }
    $repo = Join-Path $scratch 'repo'
    Write-Utf8 (Join-Path $repo '.sza-profile.json') '{"probes":{"enabled":false}}'
    $link = 'Evidence: [log](S0004_t/evidence/log.md)'
    New-SizedSpec 'S0001' 'In Progress' 40960 ''
    New-SizedSpec 'S0002' 'In Progress' 40961 ''
    New-SizedSpec 'S0003' 'Implemented' 40961 ''
    New-SizedSpec 'S0004' 'In Progress' 40961 $link
    Write-Utf8 (Join-Path $repo 'PLAN\S0004_t\evidence\log.md') "log`n"
    $rows = foreach ($f in @(@('S0001', 'In Progress'), @('S0002', 'In Progress'), @('S0003', 'Implemented'), @('S0004', 'In Progress'))) {
        [ordered]@{ id = $f[0]; name = 't'; status = $f[1]; priority = 50; file = "PLAN/$($f[0])_t.md"; created = '2026-11-26'; updated = '2026-11-26 00:00' } | ConvertTo-Json -Compress
    }
    $ledger = Join-Path $repo 'PLAN\spec-catalog.jsonl'
    Write-Utf8 $ledger (($rows -join "`n") + "`n")
    $env:SZA_PORTFOLIO_ROOT = Join-Path $scratch 'portfolio'
    $env:SZA_PROJECT_ROOT = $repo
    $env:SZA_PQ_IN_SYNC = '1'

    function Get-Row([string] $Id) {
        return Get-Content -LiteralPath $ledger -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.id -eq $Id }
    }
    function Move-Status([string] $Id, [string] $Status, [string] $Note) {
        $said = [System.Collections.Generic.List[string]]::new()
        $extra = @{}; if ($Note) { $extra.StatusNote = $Note }
        try { & (Join-Path $Catalog 'update.ps1') -Id $Id -Status $Status @extra *>&1 | ForEach-Object { $said.Add([string]$_) } }
        catch { $said.Add($_.Exception.Message) }
        return ($said -join "`n")
    }

    Run-Case 'gate: 40960 bytes pass, 40961 need a link' {
        $gate = Join-Path $Catalog 'check-spec-size.ps1'
        foreach ($t in @(@('S0001', 0), @('S0002', 1), @('S0004', 0))) {
            $said = & $gate -Id $t[0] *>&1 | Out-String
            Assert-Equal $LASTEXITCODE $t[1] "$($t[0]): $said"
        }
    }
    Run-Case 'refused: a new entry of an oversized spec without a link' {
        foreach ($t in @(@('Implemented', ''), @('Verified', ''), @('BlockNeedUserTest', 'look at the window'))) {
            $said = Move-Status 'S0002' $t[0] $t[1]
            Assert-Equal (Get-Row 'S0002').status 'In Progress' "$($t[0]) keeps the status: $said"
            Assert-Equal ($said -match 'above the limit of 40960') $true "$($t[0]) refusal: $said"
        }
    }
    Run-Case 'admit: a link passes and holds after the move' {
        $said = Move-Status 'S0004' 'Implemented'
        $row = Get-Row 'S0004'
        Assert-Equal $row.status 'Implemented' "with a link: $said"
        Assert-Equal $row.file 'PLAN/archive/S0004_t.md' "moved: $said"
        Assert-Equal ((Find-SpecEvidenceLink -Path (Join-Path $repo $row.file)) -ne '') $true 'the link after the move'
    }
    Run-Case 'kept: a reaffirmation and Archived are not gated' {
        # Judged by the shared gate alone, in this process: neither transition has to be written to be judged.
        . (Join-Path $Catalog '_lib.ps1')
        foreach ($status in 'Implemented', 'Archived') {
            $said = ''
            try { Assert-ClosingGates -Id 'S0003' -OldStatus 'Implemented' -NewStatus $status -StatusNote 'not needed: fixture' -NoteSupplied $true *> $null }
            catch { $said = $_.Exception.Message }
            Assert-Equal $said '' "$status"
        }
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
