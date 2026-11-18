#requires -Version 7.0
<# check-contracts.ps1 -Render and the block-first version map of contract-lag.ps1, on a throwaway catalog.
   Cases: contract-lag reads the block before the registry row; render raises a version and a status in place;
   render adds the missing root row and keeps the hand row; a second render changes nothing; render never lowers
   a version. Touches temp/contract-render/<guid> only, removed at the end unless -KeepScratch.
   Codes: 0 pass, 1 fail, 2 could not run. #>
[CmdletBinding()]
param([string]$SourceRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent), [switch]$KeepScratch)
$ErrorActionPreference = 'Stop'
$run = 0
$failed = 0
function Assert-That([bool]$Condition, [string]$Reason) { if (-not $Condition) { throw $Reason } }
function Test-Case([string]$Name, [scriptblock]$Body) {
    $script:run++
    try { & $Body; "PASS $Name" } catch { $script:failed++; "FAIL $Name - $($_.Exception.Message)" }
}
function Invoke-Child([string]$Path, [string[]]$Arguments) {
    $output = & pwsh -NoProfile -File $Path @Arguments 2>&1 | Out-String
    [pscustomobject]@{ code = $LASTEXITCODE; output = $output.Trim() }
}
function Set-Text([string]$Path, [string[]]$Lines) {
    [System.IO.File]::WriteAllText($Path, (($Lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
}
function New-Block([string]$Id, [string]$Version, [string]$Status, [string]$Consumers) {
    @('```contract', "id: $Id", "version: $Version", "status: $Status", 'owner: fixture', 'since: 2026-11-18',
      'wire: none', "consumers: $Consumers", 'artifacts: none', '```')
}
function New-Catalog([string]$Root, [string]$RegistryAlpha) {
    # ALPHA has a README block (1.2 active) and a registry row at $RegistryAlpha; LEGACY has a registry row only;
    # BETA has a block, a registry row and no row in the root README table.
    New-Item -ItemType Directory -Force (Join-Path $Root '_meta'), (Join-Path $Root 'alpha'), (Join-Path $Root 'beta') | Out-Null
    foreach ($name in 'RULES.md', 'VERSIONING.md', 'CONTRACT_TEMPLATE.md', 'PROJECT_PROMPT.md') {
        Set-Text (Join-Path $Root "_meta/$name") @('Fixture')
    }
    Set-Text (Join-Path $Root 'alpha/README.md') (@('# Alpha - what alpha decides', '') +
        (New-Block 'ALPHA' '1.2' 'active' 'prod-a') + @('', 'LEGACY is the long document beside this page.'))
    Set-Text (Join-Path $Root 'beta/README.md') (@('# Beta thing - what beta decides', '') + (New-Block 'BETA' '0.3' 'draft' 'prod-b'))
    Set-Text (Join-Path $Root 'README.md') @('# Fixture', '', '## The catalog', '',
        '| Function | Folder | Id | What it decides | Who is bound |', '| --- | --- | --- | --- | --- |',
        '| **Alpha** | [`alpha/`](alpha/README.md) | `ALPHA`, `LEGACY` | hand prose | hand prose |', '', '## Governance', '', 'Prose.')
    Set-Text (Join-Path $Root '_meta/REGISTRY.md') @('# Registry', '', '## 1. Contracts', '',
        '| Id | Folder | Version | Status | Owner |', '| --- | --- | --- | --- | --- |',
        ('| `ALPHA` | [`alpha/`](../alpha/README.md) | ' + $RegistryAlpha + ' | draft | 1.1 was the first cell |'),
        '', 'Prose between two parts of the table, naming 1.1 and draft.', '',
        '| `LEGACY` | [`alpha/`](../alpha/README.md) | 0.5 | record | fixture |',
        '| `BETA` | [`beta/`](../beta/README.md) | 0.3 | draft | fixture |', '',
        '## 2. Adoption', '', '| Contract | Product | Role | Implements | Reads | Verified |', '| --- | --- | --- | --- | --- | --- |',
        '| `ALPHA` | prod-a | C | - | 1.1 | 2026-11-01 |', '| `LEGACY` | prod-a | C | - | 0.5 | 2026-11-01 |')
}
$scratch = Join-Path $PSScriptRoot ('../../temp/contract-render/' + [guid]::NewGuid().ToString('N'))
try {
    $gate = Join-Path $SourceRoot 'tools/check-contracts.ps1'
    $lag = Join-Path $SourceRoot 'tools/contract-lag.ps1'
    $cat = Join-Path $scratch 'raise'
    New-Catalog $cat '1.1'
    $reg = Join-Path $cat '_meta/REGISTRY.md'
    $rootFile = Join-Path $cat 'README.md'
    $before = [System.IO.File]::ReadAllText($reg) -split "`n"

    Test-Case 'contract-lag reads the block before the registry row' {
        $r = Invoke-Child $lag @('-CatalogRoot', $cat, '-Json')
        Assert-That ($r.code -eq 0) $r.output
        $rows = @(($r.output | ConvertFrom-Json).rows)
        $a = @($rows | Where-Object contract -eq 'ALPHA')[0]
        $l = @($rows | Where-Object contract -eq 'LEGACY')[0]
        Assert-That ($a.current -eq '1.2' -and $a.state -eq 'behind') "ALPHA: $($a.current) $($a.state)"
        Assert-That ($l.current -eq '0.5' -and $l.state -eq 'current') "LEGACY: $($l.current) $($l.state)"
    }

    $first = Invoke-Child $gate @('-CatalogRoot', $cat, '-Render')
    $after = [System.IO.File]::ReadAllText($reg) -split "`n"
    Test-Case 'render raises a version and a status in place' {
        Assert-That ($first.code -eq 0 -and $first.output -match 'section 1 - 2 cell\(s\) rewritten, 0 row\(s\) refused') $first.output
        Assert-That ($after.Count -eq $before.Count) "line count $($before.Count) -> $($after.Count)"
        $moved = @(0..($before.Count - 1) | Where-Object { $before[$_] -cne $after[$_] })
        Assert-That ($moved.Count -eq 1) "lines changed: $($moved -join ', ')"
        Assert-That ($after[$moved[0]] -ceq '| `ALPHA` | [`alpha/`](../alpha/README.md) | 1.2 | active | 1.1 was the first cell |') $after[$moved[0]]
    }
    Test-Case 'render adds the missing root row and keeps the hand row' {
        $root = [System.IO.File]::ReadAllText($rootFile) -split "`n"
        Assert-That ($first.output -match 'catalog table - 0 id cell\(s\) rewritten, 1 row\(s\) added') $first.output
        Assert-That ($root[6] -ceq '| **Alpha** | [`alpha/`](alpha/README.md) | `ALPHA`, `LEGACY` | hand prose | hand prose |') $root[6]
        Assert-That ($root[7] -ceq '| **Beta thing** | [`beta/`](beta/README.md) | `BETA` | what beta decides | prod-b |') $root[7]
    }
    Test-Case 'a second render changes nothing' {
        $h = (Get-FileHash $reg).Hash + (Get-FileHash $rootFile).Hash
        $second = Invoke-Child $gate @('-CatalogRoot', $cat, '-Render')
        Assert-That ($second.code -eq 0 -and $second.output -match ' 0 cell\(s\) rewritten' -and $second.output -match ' 0 row\(s\) added') $second.output
        Assert-That ($h -eq ((Get-FileHash $reg).Hash + (Get-FileHash $rootFile).Hash)) 'a file changed on the second render'
    }
    Test-Case 'render never lowers a version' {
        $low = Join-Path $scratch 'lower'
        New-Catalog $low '1.3'
        $regLow = Join-Path $low '_meta/REGISTRY.md'
        $h = (Get-FileHash $regLow).Hash
        $r = Invoke-Child $gate @('-CatalogRoot', $low, '-Render')
        Assert-That ($r.code -eq 1 -and $r.output -match 'refused ALPHA: the registry says 1\.3') $r.output
        Assert-That ($h -eq (Get-FileHash $regLow).Hash) 'the registry was rewritten'
    }

    $verdict = if ($failed) { 'FAIL' } else { 'PASS' }
    "contract-render-tests: $verdict (run=$run skipped=0)"
    exit $(if ($failed) { 1 } else { 0 })
}
catch {
    $_.Exception.Message
    "contract-render-tests: COULD NOT VERIFY (run=$run skipped=0)"
    exit 2
}
finally {
    if (-not $KeepScratch -and (Test-Path -LiteralPath $scratch)) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
