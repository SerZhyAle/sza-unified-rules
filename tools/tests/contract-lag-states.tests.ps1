<#
.SYNOPSIS
    Fast tests for the lag states of tools/contract-lag.ps1 (S0137): a row below its contract's version is
    `behind` only when the change in between can bind the product, `unread` when only clarifications lie between.
      1. -Json: state, lag and counts, including a legacy exclusive entry in a shared log.
      2. -EmitSpec: `behind (breaking)` in the owed table; the unread row is listed and has no section of its own.
      3. -FailOnLag: exit 0 when the only lagging row is unread, exit 1 when a row is behind.
    Touches a throwaway catalog under the system temp folder only; the real catalog is never read. Four child
    processes. Takes -KeepScratch to leave the folder for inspection.
    #>
[CmdletBinding()]
param([switch]$KeepScratch)

$ErrorActionPreference = 'Stop'
$SourceRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
$lagScript = Join-Path $SourceRoot 'tools/contract-lag.ps1'
$run = 0; $passed = 0; $failed = 0
function Assert-That([bool]$Condition, [string]$Reason) { if (-not $Condition) { throw $Reason } }
function Test-Case([string]$Name, [scriptblock]$Body) {
    $script:run++
    try { & $Body; $script:passed++; Write-Host "CASE  $Name ... PASS" }
    catch { $script:failed++; Write-Host "CASE  $Name ... FAIL"; Write-Host "      $($_.Exception.Message)" }
}
function Invoke-Lag([string[]]$Arguments) {
    $output = & pwsh -NoProfile -File $lagScript -CatalogRoot $catalog @Arguments 2>&1 | Out-String
    [pscustomobject]@{ code = $LASTEXITCODE; output = $output.Trim() }
}

$catalog = Join-Path ([System.IO.Path]::GetTempPath()) ('contract-lag-states-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    foreach ($d in '_meta', 'fixa', 'fixb', 'fixc') { New-Item -ItemType Directory -Force -Path (Join-Path $catalog $d) | Out-Null }
    @(
        '## 1. Contracts'
        '| Id | Folder | Version | Status |'
        '| --- | --- | --- | --- |'
        '| `FIXA` | [`fixa/`](../fixa/README.md) | 0.4 | draft |'
        '| `FIXB` | [`fixb/`](../fixb/README.md) | 2.0 | active |'
        '| `FIXC` | [`fixc/`](../fixc/README.md) | 0.2 | draft |'
        '| `FIXD` | [`fixa/`](../fixa/README.md) | 0.4 | draft |'
        '## 2. Adoption'
        '| Contract | Product | Role | Implements | Reads | Verified |'
        '| --- | --- | --- | --- | --- | --- |'
        '| `FIXA` | lag breaking | C | - | 0.1 | 2026-10-01 |'
        '| `FIXA` | lag additive | C | - | 0.2 | 2026-10-01 |'
        '| `FIXA` | lag unread | C | - | 0.3 | 2026-10-01 |'
        '| `FIXA` | lag current | C | - | 0.4 | 2026-10-01 |'
        '| `FIXA` | lag partial | P | partial 0.3 | - | 2026-10-01 |'
        '| `FIXA` | lag partial read | C | - | partial 0.3 | 2026-10-01 |'
        '| `FIXB` | lag major | C | - | 1.4 | 2026-10-01 |'
        '| `FIXC` | lag unlogged | C | - | 0.1 | 2026-10-01 |'
        '| `FIXD` | lag exclusive | C | - | 0.3 | 2026-10-01 |'
    ) | Set-Content (Join-Path $catalog '_meta/REGISTRY.md')
    @(
        '| Date | Version | Kind | What changed |'
        '| --- | --- | --- | --- |'
        '| 2026-10-01 | 0.2 | breaking | Reader changed. |'
        '| 2026-10-02 | 0.3 | additive | Optional field. |'
        '| 2026-10-03, owner order | FIXA 0.4 | minor (clarification) | Wording. |'
        '| 2026-10-03, owner order | 0.4 | additive | `FIXD` only. Extra optional field. |'
    ) | Set-Content (Join-Path $catalog 'fixa/README.md')
    @(
        '| Date | Version | Kind | What changed |'
        '| --- | --- | --- | --- |'
        '| 2026-10-04 | 2.0 | correction | Table fixed. |'
    ) | Set-Content (Join-Path $catalog 'fixb/README.md')
    'No document log yet.' | Set-Content (Join-Path $catalog 'fixc/README.md')

    Test-Case 'json: state and lag follow the log kinds' {
        $r = Invoke-Lag @('-Json')
        Assert-That ($r.code -eq 0) "exit $($r.code): $($r.output)"
        $report = $r.output | ConvertFrom-Json
        $got = @{}
        foreach ($row in $report.rows) { $got[$row.product] = '{0}/{1}' -f $row.state, $row.lag }
        $want = [ordered]@{
            'lag breaking' = 'behind/breaking'; 'lag additive' = 'behind/additive'; 'lag unread' = 'unread/clarification'
            'lag current' = 'current/'; 'lag partial' = 'partial/clarification'; 'lag major' = 'behind/breaking'
            'lag partial read' = 'partial/clarification'
            'lag unlogged' = 'behind/additive'; 'lag exclusive' = 'behind/additive'
        }
        foreach ($name in $want.Keys) { Assert-That ($got[$name] -eq $want[$name]) "$name is '$($got[$name])', expected '$($want[$name])'" }
        Assert-That ($report.counts.behind -eq 5 -and $report.counts.unread -eq 1) "counts: $($report.counts | ConvertTo-Json -Compress)"
    }
    Test-Case 'spec: the unread row is listed and gets no section' {
        $r = Invoke-Lag @('-Product', 'lag', '-EmitSpec')
        Assert-That ($r.code -eq 0) "exit $($r.code): $($r.output)"
        Assert-That ($r.output.Contains('| behind (breaking) |')) 'the owed table does not say behind (breaking)'
        Assert-That ($r.output.Contains('Unread clarifications (informational)')) 'no unread list'
        Assert-That ($r.output.Contains('- `FIXA` (lag unread), 0.3 to 0.4')) 'the unread row is not listed'
        Assert-That (-not $r.output.Contains('to 0.4  (lag unread)')) 'the unread row got a section of its own'
        Assert-That ($r.output.Contains('to 0.4  (lag additive)')) 'the additive row lost its section'
        Assert-That ($r.output.Contains('to 0.4  (lag exclusive)') -and $r.output.Contains('`FIXD` only. Extra optional field.')) 'the exclusive entry was lost from its own contract'
    }
    Test-Case 'FailOnLag: unread alone exits 0, behind exits 1' {
        Assert-That ((Invoke-Lag @('-Product', 'lag unread', '-FailOnLag')).code -eq 0) 'an unread row failed -FailOnLag'
        Assert-That ((Invoke-Lag @('-Product', 'lag additive', '-FailOnLag')).code -eq 1) 'a behind row passed -FailOnLag'
    }
} finally {
    if (-not $KeepScratch -and (Test-Path $catalog)) { Remove-Item -Path $catalog -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Host "Cases: $run | Passed: $passed | Failed: $failed"
if ($failed -gt 0) { exit 1 } else { exit 0 }
