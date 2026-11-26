#requires -Version 7.0
<#
.SYNOPSIS
    Cases for the size budgets: check 7 of tools/check-rules.ps1 and CTR-SIZE of tools/check-contracts.ps1.

.DESCRIPTION
    Copies of the two gates run over scratch trees, one refused and one accepted tree each. Nothing outside the
    scratch folder is written.

      1. The rule gate refuses a doc above its line, a doc with no line, a line with no doc, a line with no date
         and a line with no reason.
      2. The rule gate keeps a doc at exactly its budget, carriage returns not counted.
      3. The catalog gate refuses a README above its line, a line with no date and a malformed row.
      4. The catalog gate refuses a budget file with no task-flow line.
      5. The catalog gate keeps a README within its budget.

    -KeepScratch leaves the trees on disk and prints their folder.
#>
[CmdletBinding()]
param([switch] $KeepScratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$tools = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repo = Split-Path $tools

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('size-budget-' + [guid]::NewGuid().ToString('N').Substring(0, 8))

function Write-Scratch([string] $Path, [string] $Text) {
    New-Item -ItemType Directory -Path (Split-Path $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path, $Text)
}

function Copy-Gate([string] $Root, [string[]] $Files) {
    foreach ($rel in $Files) {
        $target = Join-Path $Root $rel
        New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $repo $rel) -Destination $target
    }
}

function Invoke-Rules([string] $Tree, [Collections.IDictionary] $Docs, [object[]] $Budgets) {
    $root = Join-Path $scratch $Tree
    Copy-Gate $root 'tools/check-rules.ps1', 'tools/lib/size-budget.ps1', 'hooks/session-start.ps1', 'templates/.sza-canon.json'
    foreach ($name in $Docs.Keys) { Write-Scratch (Join-Path $root 'rules' $name) $Docs[$name] }
    Write-Scratch (Join-Path $root 'tools' 'rules-size-budget.json') (@{ budgets = $Budgets } | ConvertTo-Json -Depth 4)
    $out = @(& pwsh -NoProfile -File (Join-Path $root 'tools' 'check-rules.ps1') 2>&1 | ForEach-Object { "$_" })
    return [pscustomobject]@{ code = $LASTEXITCODE; text = ($out -join "`n") }
}

function New-Line([string] $File, [int] $Bytes, [string] $Date = '2026-11-26', [string] $Reason = 'baseline') {
    return @{ file = $File; bytes = $Bytes; date = $Date; reason = $Reason }
}

function Invoke-Catalog([string] $Tree, [string] $Readme, [string[]] $Rows) {
    $root = Join-Path $scratch $Tree
    Copy-Gate $root 'tools/check-contracts.ps1', 'tools/lib/size-budget.ps1'
    $catalog = Join-Path $root 'catalog'
    Write-Scratch (Join-Path $catalog 'task-flow' 'README.md') $Readme
    $table = @('| File | Budget (bytes) | Date | Reason |', '| --- | --- | --- | --- |') + $Rows
    Write-Scratch (Join-Path $catalog '_meta' 'SIZE_BUDGET.md') (($table -join "`n") + "`n")
    $out = @(& pwsh -NoProfile -File (Join-Path $root 'tools' 'check-contracts.ps1') -CatalogRoot $catalog -Json)
    $found = @(($out -join "`n") | ConvertFrom-Json | ForEach-Object { $_ } | Where-Object id -eq 'CTR-SIZE')
    return [pscustomobject]@{ code = $LASTEXITCODE; text = (@($found | ForEach-Object { "$($_.path): $($_.message)" }) -join "`n") }
}

try {
    $docs = [ordered]@{ 'INVARIANTS.md' = "# Invariants`n"; 'OVER.md' = "# Over`nlonger`n"; 'BARE.md' = "# Bare`n" }
    $bad = Invoke-Rules 'rules-refused' $docs @(
        (New-Line 'INVARIANTS.md' 100 -Date 'today' -Reason ' '), (New-Line 'OVER.md' 7), (New-Line 'GONE.md' 10))
    Run-Case '1 the rule gate names every broken line' {
        Assert-That ($bad.code -eq 1) "exit $($bad.code): $($bad.text)"
        foreach ($expected in 'OVER.md: 14 bytes, budget 7 (+7)', 'BARE.md: no budget line',
            'GONE.md: the budget line names a file that does not exist', 'INVARIANTS.md: the budget line has no date',
            'INVARIANTS.md: the budget line has no reason') {
            Assert-That ($bad.text.Contains("FAIL $expected")) "missing '$expected': $($bad.text)"
        }
    }
    Run-Case '2 a doc at its budget passes, carriage returns not counted' {
        $ok = Invoke-Rules 'rules-accepted' ([ordered]@{ 'INVARIANTS.md' = "# Invariants`r`n" }) @((New-Line 'INVARIANTS.md' 13))
        Assert-That ($ok.code -eq 0) "exit $($ok.code): $($ok.text)"
        Assert-That ($ok.text.Contains('1 size budgets kept')) $ok.text
    }
    Run-Case '3 the catalog gate refuses growth, a dateless line and a malformed row' {
        $r = Invoke-Catalog 'catalog-refused' "0123456789`n" @(
            '| `task-flow/README.md` | 5 | soon | baseline |', '| `task-flow/README.md` | 5 |')
        Assert-That ($r.code -eq 1) "exit $($r.code): $($r.text)"
        foreach ($expected in '11 bytes, budget 5 (+6)', 'has no date', 'a budget row is not') {
            Assert-That ($r.text.Contains($expected)) "missing '$expected': $($r.text)"
        }
    }
    Run-Case '4 the catalog gate requires the task-flow line' {
        $r = Invoke-Catalog 'catalog-missing' "x`n" @()
        Assert-That ($r.text.Contains('task-flow/README.md has no budget line')) $r.text
    }
    Run-Case '5 a README within its budget raises nothing' {
        $r = Invoke-Catalog 'catalog-accepted' "0123456789`r`n" @('| `task-flow/README.md` | 11 | 2026-11-26 | baseline |')
        Assert-That ($r.text -eq '') $r.text
    }
}
finally {
    if ($KeepScratch) { Write-Host "scratch kept: $scratch" }
    else { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host "size-budget: run=$run passed=$passed failed=$failed"
if ($failed -gt 0) { exit 1 }
exit 0
