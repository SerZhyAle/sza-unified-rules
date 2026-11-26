#requires -Version 7.0
<#
.SYNOPSIS
    CANONR-0222: run-tier.ps1 -Stale and the lastPass date, over a throwaway git repository.

.DESCRIPTION
    A scratch repository with commits at fixed dates, trivial fixture suites and a scratch registry; the real
    run-tier.ps1 of this tree. Cases:

      1. Committed changes: a covered path or the test file committed after lastPass is stale; a pass on or after the
         last change is not; no recorded pass, a missing listed path and a suite with no row are stale; a fast row is
         never listed; the registry is left byte for byte and the exit code is 0.
      2. Uncommitted changes: an edit and a new file under a covered path count by their file time.
      3. -Measure writes lastPass on exit 0 and leaves the registry alone on a failure.
      4. -Root without -Registry, and -Stale with -Suite, are refused with exit 2.
      5. deploy.ps1 calls -Stale only under -DryRun.

    -KeepScratch leaves the repository for inspection.
#>
[CmdletBinding()]
param([switch] $KeepScratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$runTier = Join-Path $PSScriptRoot 'run-tier.ps1'
$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('tier-stale-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$repo = Join-Path $scratch 'repo'
$registry = Join-Path $scratch 'tiers.json'
$savedDates = $env:GIT_AUTHOR_DATE, $env:GIT_COMMITTER_DATE

function Set-File([string] $Rel, [string] $Text) {
    $full = Join-Path $repo $Rel
    $null = New-Item -ItemType Directory -Path (Split-Path $full) -Force
    [IO.File]::WriteAllText($full, "$Text`n")
}
function Save-Commit([string] $Day) {
    $env:GIT_AUTHOR_DATE = $env:GIT_COMMITTER_DATE = "${Day}T12:00:00Z"
    git -C $repo -c core.autocrlf=false add -A
    git -C $repo -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false -c "core.hooksPath=$scratch/no-hooks" commit -q -m $Day
    Assert-That ($LASTEXITCODE -eq 0) "fixture commit $Day failed"
}
function New-Row([string] $Name, $LastPass, [string[]] $Paths, [string] $Tier = 'release') {
    [ordered]@{ path = "tools/tests/$Name.tests.ps1"; tier = $Tier; seconds = $(if ($Tier -eq 'fast') { 1 } else { 20 }); measured = '2026-03-01'; lastPass = $LastPass; covers = ''; paths = @($Paths) }
}
function Invoke-Tier([string[]] $Arguments) {
    $out = @(& pwsh -NoProfile -File $runTier @Arguments 2>&1 | ForEach-Object { "$_" })
    [pscustomobject]@{ code = $LASTEXITCODE; text = $out -join "`n" }
}
function Get-StaleLine($Result, [string] $Name) { @($Result.text -split "`n" | Where-Object { $_.StartsWith("STALE  tools/tests/$Name.tests.ps1 ") }) -join '' }

try {
    $null = New-Item -ItemType Directory -Path $repo -Force
    git -C $repo init -q
    foreach ($name in 'covered', 'self', 'clean', 'never', 'gone', 'dirty', 'added', 'unlisted', 'quick') { Set-File "tools/tests/$name.tests.ps1" 'exit 0' }
    Set-File 'tools/tests/broken.tests.ps1' 'exit 1'
    foreach ($name in 'covered', 'clean', 'dirty') { Set-File "src/$name.ps1" 'one' }
    Set-File 'src/added/first.ps1' 'one'
    Save-Commit '2026-03-01'
    Set-File 'src/covered.ps1' 'two'
    Set-File 'tools/tests/self.tests.ps1' 'exit 0 # two'
    Save-Commit '2026-03-10'

    $rows = @(
        New-Row 'covered' '2026-03-05' 'src/covered.ps1'
        New-Row 'self' '2026-03-05' 'src/clean.ps1'
        New-Row 'clean' '2026-03-10' @('src/clean.ps1', 'src/covered.ps1')
        New-Row 'never' $null 'src/clean.ps1'
        New-Row 'gone' '2026-03-10' 'src/no-such.ps1'
        New-Row 'dirty' '2026-03-10' 'src/dirty.ps1'
        New-Row 'added' '2026-03-10' 'src/added'
        New-Row 'quick' $null 'src/clean.ps1' 'fast'
        New-Row 'broken' $null 'src/clean.ps1'
    )
    [ordered]@{ schema = 1; lineSeconds = 5; note = 'fixture'; suites = $rows } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $registry
    $common = @('-Registry', $registry, '-Root', $repo)

    Run-Case '1 committed changes, missing records, read only' {
        $before = (Get-FileHash -LiteralPath $registry).Hash
        $r = Invoke-Tier (@('-Stale') + $common)
        Assert-That ($r.code -eq 0) "exit $($r.code): $($r.text)"
        Assert-That ((Get-StaleLine $r 'covered').Contains('last pass 2026-03-05, changed 2026-03-10')) "covered: $($r.text)"
        Assert-That ((Get-StaleLine $r 'self').Contains('changed 2026-03-10')) "self: $($r.text)"
        Assert-That ((Get-StaleLine $r 'never').Contains('no recorded pass')) "never: $($r.text)"
        Assert-That ((Get-StaleLine $r 'gone').Contains('listed path missing: src/no-such.ps1')) "gone: $($r.text)"
        Assert-That ((Get-StaleLine $r 'unlisted').Contains('no registry row')) "unlisted: $($r.text)"
        foreach ($name in 'clean', 'dirty', 'added', 'quick') { Assert-That (-not (Get-StaleLine $r $name)) "$name is listed: $($r.text)" }
        # nine rows, one of them fast, plus the suite with no row
        Assert-That ($r.text.Contains('6 of 9 release suites stale')) "count: $($r.text)"
        Assert-That ((Get-FileHash -LiteralPath $registry).Hash -eq $before) 'the registry changed'
    }
    Run-Case '2 uncommitted edits count by file time' {
        foreach ($rel in 'src/dirty.ps1', 'src/added/second.ps1') {
            Set-File $rel 'two'
            (Get-Item -LiteralPath (Join-Path $repo $rel)).LastWriteTime = [datetime]::new(2026, 3, 20, 12, 0, 0)
        }
        $r = Invoke-Tier (@('-Stale') + $common)
        foreach ($name in 'dirty', 'added') { Assert-That ((Get-StaleLine $r $name).Contains('changed 2026-03-20')) "${name}: $($r.text)" }
        Assert-That (-not (Get-StaleLine $r 'clean')) "clean is listed: $($r.text)"
    }
    Run-Case '3 -Measure records lastPass only on a pass' {
        $before = (Get-FileHash -LiteralPath $registry).Hash
        $bad = Invoke-Tier (@('-Suite', 'broken', '-Measure') + $common)
        Assert-That ($bad.code -eq 1 -and (Get-FileHash -LiteralPath $registry).Hash -eq $before) "failed run: exit $($bad.code) $($bad.text)"
        $day = (Get-Date).ToString('yyyy-MM-dd')
        $good = Invoke-Tier (@('-Suite', 'never', '-Measure') + $common)
        $row = (Get-Content -LiteralPath $registry -Raw | ConvertFrom-Json).suites | Where-Object { $_.path -eq 'tools/tests/never.tests.ps1' }
        Assert-That ($good.code -eq 0 -and $row.lastPass -in $day, (Get-Date).ToString('yyyy-MM-dd')) "passed run: exit $($good.code) lastPass $($row.lastPass)"
        Assert-That ((@($row.paths) -join ',') -eq 'src/clean.ps1') 'paths were lost on save'
    }
    Run-Case '4 refused argument sets' {
        $a = Invoke-Tier @('-Stale', '-Root', $repo)
        $b = Invoke-Tier (@('-Stale', '-Suite', 'clean') + $common)
        Assert-That ($a.code -eq 2 -and $b.code -eq 2) "exits $($a.code), $($b.code)"
    }
    Run-Case '5 deploy.ps1 lists stale suites on a dry run only' {
        $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\..\deploy.ps1'), [ref]$null, [ref]$null)
        $sites = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq '$DryRun' -and $n.Extent.Text.Contains('$tierScript -Stale') }, $true))
        Assert-That ($sites.Count -eq 1) "dry-run call sites: $($sites.Count)"
        Assert-That ($sites[0].Extent.Text -notmatch '\bFail\b|\bexit\b') 'the call site blocks'
    }
}
finally {
    $env:GIT_AUTHOR_DATE, $env:GIT_COMMITTER_DATE = $savedDates
    if ($KeepScratch) { Write-Host "scratch: $scratch" } else { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host "run-tier-stale: run=$run passed=$passed failed=$failed"
if ($failed -gt 0) { exit 1 }
exit 0
