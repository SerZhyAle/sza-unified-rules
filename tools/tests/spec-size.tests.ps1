#requires -Version 7.0
<#
.SYNOPSIS
  CANONR-0210: a ticket holds one copy of the request text, and spec_catalog/list-fat-specs.ps1 reports the spec files
  above a size limit with their biggest sections. Builds a throwaway repository under the system temp directory and
  reads the two ticket templates of this checkout. Writes nothing outside that directory.
.DESCRIPTION
  Cases:
    templates - the scaffold form (and this checkout's PLAN form, when present) keeps every heading a tool reads, holds
                one {{TEXT}} token and has no Progress, Steps or Plan heading
    text      - the owner text is written at the first token only, a later token becomes a pointer, and a token inside
                the text is neither expanded nor removed
    capture   - capture-draft.ps1 over a template with two tokens writes the text once
    sections  - the biggest sections come first, a heading inside a fenced block is text, the bytes add up
    report    - only files above the limit are listed, one of exactly 40 KiB is not, an archived row is, a row without
                a file is counted, and neither ledger nor spec changes
    refused   - -Root that is no folder exits 2
  Exit 0 when every case passed, 1 on any failure.
#>
[CmdletBinding()]
param([switch] $KeepScratch)

$ErrorActionPreference = 'Stop'

$Repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$Catalog = Join-Path $Repository 'tools\harness\spec_catalog'
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
function Get-Count([string] $Text, [string] $Part) { return [regex]::Matches($Text, [regex]::Escape($Part)).Count }
# A spec of exactly the asked size: ASCII only, so a character is a byte.
function New-SizedSpec([string] $Path, [int] $Bytes) {
    $head = "# t`n`n**Status:** Draft`n`n## 1. Problem`n`n"
    Write-Utf8 $Path ($head + ('x' * ($Bytes - $head.Length - 1)) + "`n")
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('tf-specsize-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$saved = @{ SZA_PORTFOLIO_ROOT = $env:SZA_PORTFOLIO_ROOT; SZA_PROJECT_ROOT = $env:SZA_PROJECT_ROOT; SZA_PQ_NO_PROJECTION = $env:SZA_PQ_NO_PROJECTION }
try {
    . (Join-Path $Catalog 'attachment-capture.ps1')
    . (Join-Path $Catalog '_spec-size.ps1')
    $env:SZA_PORTFOLIO_ROOT = Join-Path $scratch 'portfolio'
    $env:SZA_PQ_NO_PROJECTION = '1'

    Run-Case 'templates: the read headings stay, one text token, no Progress, Steps or Plan' {
        $forms = @(Join-Path $Repository 'tools\harness\scaffold\templates\ticket-template.md')
        $own = Join-Path $Repository 'PLAN\TICKET_TEMPLATE.md'
        if (Test-Path -LiteralPath $own) { $forms += $own }
        foreach ($form in $forms) {
            $text = [IO.File]::ReadAllText($form)
            foreach ($part in '**Status:** Draft', '**Complexity:** {{COMPLEXITY}}', '## 0. Owner request (verbatim)',
                '### 3.3 Owner inputs (Approval gate)', '**Related tickets:**') {
                Assert-Equal (Get-Count $text $part) 1 "$form holds $part"
            }
            Assert-Equal (Get-Count $text '{{TEXT}}') 1 "$form text tokens"
            Assert-Equal ($text -match '(?m)^#{2,3}\s+(?:[\d.]+\s+)?(Progress|Steps|Plan)\b') $false "$form dead heading"
        }
    }
    Run-Case 'text: written once at the first token, a token inside the text survives' {
        $text = 'keep {{TEXT}} as typed, $env:PATH too'
        $body = Add-DraftOwnerText -Body "## 0`n`n{{TEXT}}`n`n## Inbox`n`n{{TEXT}}`n" -Value $text 6>$null
        Assert-Equal $body "## 0`n`n$text`n`n## Inbox`n`n(The request text stands once, above.)`n" 'two tokens'
        Assert-Equal (Add-DraftOwnerText -Body "a {{TEXT}} b" -Value $text) "a $text b" 'one token'
    }
    Run-Case 'capture: a two-token template yields one copy' {
        $repo = Join-Path $scratch 'capture'
        Write-Utf8 (Join-Path $repo '.sza-profile.json') '{}'
        Write-Utf8 (Join-Path $repo 'PLAN\TICKET_TEMPLATE.md') "# {{ID}}_{{SLUG}}`n`n**Status:** Draft`n`n## 0. Owner request (verbatim)`n`n{{TEXT}}`n`n## Captured material (inbox)`n`n{{TEXT}}`n"
        $words = 'the owner words of this fixture'
        $said = & (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $Catalog 'capture-draft.ps1') -ProjectRoot $repo -Slug one-copy -Text $words 2>&1 | Out-String
        Assert-Equal $LASTEXITCODE 0 "capture: $said"
        $spec = [IO.File]::ReadAllText((Join-Path $repo 'PLAN\S0001_one-copy.md'))
        Assert-Equal (Get-Count $spec $words) 1 'copies of the owner text'
    }
    Run-Case 'sections: biggest first, a fenced heading is text, the bytes add up' {
        $path = Join-Path $scratch 'sections.md'
        $text = "# t`n`n## small`n`na`n`n## big`n`n``````text`n## not a heading`n$('b' * 500)`n```````n`n## middle`n`n$('ё' * 100)`n"
        Write-Utf8 $path $text
        $report = Get-SpecSizeReport -Path $path
        Assert-Equal (($report.Sections | Select-Object -First 3 -ExpandProperty Heading) -join '|') '## big|## middle|## small' 'order'
        Assert-Equal ($report.Sections | Measure-Object -Property Bytes -Sum).Sum $report.Bytes 'sum'
    }

    $repo = Join-Path $scratch 'report'
    Write-Utf8 (Join-Path $repo '.sza-profile.json') '{}'
    New-SizedSpec (Join-Path $repo 'PLAN\S0001_t.md') 2000
    New-SizedSpec (Join-Path $repo 'PLAN\S0002_t.md') 40960
    New-SizedSpec (Join-Path $repo 'PLAN\S0003_t.md') 40961
    New-SizedSpec (Join-Path $repo 'PLAN\DONE\S0004_t.md') 90000
    function New-Row([string] $Id, [string] $Status, [string] $File) {
        [ordered]@{ id = $Id; name = 't'; status = $Status; priority = 50; file = $File; created = '2026-11-26'; updated = '2026-11-26 00:00' } | ConvertTo-Json -Compress
    }
    $ledger = Join-Path $repo 'PLAN\spec-catalog.jsonl'
    Write-Utf8 $ledger ((@(
        (New-Row 'S0001' 'Draft' 'PLAN/S0001_t.md'), (New-Row 'S0002' 'Draft' 'PLAN/S0002_t.md'),
        (New-Row 'S0003' 'Draft' 'PLAN/S0003_t.md'), (New-Row 'S0005' 'Draft' 'PLAN/S0005_t.md')) -join "`n") + "`n")
    Write-Utf8 (Join-Path $repo 'PLAN\spec-catalog-archive.jsonl') ((New-Row 'S0004' 'Archived' 'PLAN/DONE/S0004_t.md') + "`n")
    function Get-Snapshot { (Get-ChildItem -LiteralPath $repo -Recurse -File | Sort-Object FullName | ForEach-Object { "$($_.FullName) $((Get-FileHash -LiteralPath $_.FullName).Hash)" }) -join "`n" }

    Run-Case 'report: only the oversized files, archive included, nothing written' {
        $before = Get-Snapshot
        $report = (& (Join-Path $Catalog 'list-fat-specs.ps1') -Root $repo -Json | Out-String) | ConvertFrom-Json
        Assert-Equal (($report.tickets.id) -join ',') 'S0004,S0003' 'listed, biggest first'
        Assert-Equal "$($report.specs) $($report.missing) $($report.fat)" '4 1 2' 'counts'
        $lines = @(& (Join-Path $Catalog 'list-fat-specs.ps1') -Root $repo -OverKB 1)
        Assert-Equal @($lines | Where-Object { $_ -match '^S\d{4}  ' }).Count 4 'a lower limit lists all four'
        Assert-Equal ($lines[1] -match ' KB  ## 1\. Problem$') $true "section line: $($lines[1])"
        Assert-Equal (Get-Snapshot) $before 'files untouched'
    }
    Run-Case 'refused: a missing -Root exits 2' {
        & (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $Catalog 'list-fat-specs.ps1') -Root (Join-Path $scratch 'nowhere') *> $null
        Assert-Equal $LASTEXITCODE 2 'exit code'
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
