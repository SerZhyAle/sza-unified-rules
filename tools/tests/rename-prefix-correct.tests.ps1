<#  Cases of the owner's correction of a migrated prefix (TASK-FLOW 0.39 section 17, HARNESS-PROFILE 0.21 rule 16):
    spec_catalog/rename-prefix.ps1 -Correct run as a child in a throwaway repository under the system temp directory -
    refused on a repository that has not migrated, then one migration and one correction: the current shape is renamed
    again, grammar.legacyTicketIdPatterns grows (it is never replaced), formerIds lists every id the row carried, the next
    id continues the numbers, and a return to a prefix the repository carried before is refused. Nothing else is touched.
    Exit 0 when every case passed, 1 on any failure.
    Run:  pwsh -NoProfile -File tools/tests/rename-prefix-correct.tests.ps1 [-KeepScratch] #>
[CmdletBinding()]
param([switch] $KeepScratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Harness = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))) 'tools\harness'
$pwshExe = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source

$run = 0; $passed = 0; $failed = 0
function Assert-Equal($Actual, $Expected, [string] $What) { if ("$Actual" -cne "$Expected") { throw "$What - expected '$Expected', got '$Actual'" } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}
$utf8 = [Text.UTF8Encoding]::new($false)
function Write-Text([string] $Path, [string] $Text) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path, $Text, $utf8)
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('rename-correct-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$repo = Join-Path $scratch 'repo'
$other = Join-Path $scratch 'other'
$portfolio = Join-Path $scratch 'portfolio'
$profileText = '{"projectName":"t","paths":{"specsDir":"PLAN","specArchiveDir":"PLAN/DONE"},"grammar":{"specFilePattern":"^PLAN/(DONE/)?S\\d{4}_(?!spec_)"}}'
Write-Text (Join-Path $repo '.sza-profile.json') $profileText
$rows = @(
    '{"id":"S0001","name":"done","status":"Verified","priority":50,"file":"PLAN/DONE/S0001_done.md","created":"2026-11-01","updated":"2026-11-01 10:00"}'
    '{"id":"S0002","name":"open","status":"Draft","priority":50,"file":"PLAN/S0002_open.md","created":"2026-11-01","updated":"2026-11-01 10:00"}'
    '{"id":"S0003","name":"held","status":"BlockByOtherTask","priority":50,"file":"PLAN/S0003_held.md","created":"2026-11-01","updated":"2026-11-01 10:00","statusNote":"Blocker: S0002"}'
)
Write-Text (Join-Path $repo 'PLAN\spec-catalog.jsonl') (($rows -join "`n") + "`n")
Write-Text (Join-Path $repo 'PLAN\DONE\S0001_done.md') "# S0001_done`n`n**Status:** Verified`n"
Write-Text (Join-Path $repo 'PLAN\S0002_open.md') "# S0002_open`n`n**Status:** Draft`n"
Write-Text (Join-Path $repo 'PLAN\S0003_held.md') "# S0003_held`n`n**Status:** BlockByOtherTask`n`nBlocker: S0002`n"
Write-Text (Join-Path $other 'PLAN\S0009_waits.md') "# S0009_waits`n`nBlocker: t:S0002`n"
$reg = @{ repos = @(@{ key = 't'; path = $repo }, @{ key = 'o'; path = $other }) } | ConvertTo-Json -Depth 5
Write-Text (Join-Path $portfolio 'repos.json') $reg
Write-Text (Join-Path $portfolio 'PORTFOLIO_QUEUE.md') "ticket  changed  status`n1`nt:S0002_open  26-11-01 10:00  Draft`n"

$fakeHome = Join-Path $scratch 'home'
Write-Text (Join-Path $fakeHome '.claude\plugins\cache\sza-unified-rules\sza\2026.1119.2\tools\harness\_profile.ps1') '# grammar.legacyTicketIdPatterns'

function Invoke-Tool([string] $Script, [string[]] $Arguments) {
    $psi = [Diagnostics.ProcessStartInfo]::new($pwshExe)
    foreach ($a in (@('-NoProfile', '-File', (Join-Path $Harness $Script)) + $Arguments)) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $repo
    $psi.Environment['SZA_PROJECT_ROOT'] = $repo
    $psi.Environment['SZA_PORTFOLIO_ROOT'] = $portfolio
    $psi.Environment['USERPROFILE'] = $fakeHome
    $psi.Environment['SZA_SKIP_RELEASE_QUEUE'] = '1'
    foreach ($n in 'SZA_PROFILE_PATH', 'SZA_SPEC_CATALOG_DIR', 'SZA_PQ_IN_SYNC', 'SZA_HARNESS_ROOT') { [void]$psi.Environment.Remove($n) }
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(30000)) { try { $p.Kill($true) } catch { }; throw "$Script timed out" }
    $p.WaitForExit()
    return @{ code = $p.ExitCode; out = ([string]$o.Result + [string]$e.Result) }
}
function Read-Rows { return @(Get-Content -LiteralPath (Join-Path $repo 'PLAN\spec-catalog.jsonl') -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json }) }
function Read-Text([string] $Rel) { return [IO.File]::ReadAllText((Join-Path $scratch $Rel)) }

try {
    Run-Case '-Correct on a repository that has not migrated is refused with exit 2' {
        $r = Invoke-Tool 'spec_catalog\rename-prefix.ps1' @('-Prefix', 'TESTCD', '-Correct')
        Assert-Equal $r.code 2 "the exit code ($($r.out))"
        Assert-Equal (Read-Text 'repo\.sza-profile.json') $profileText 'the profile'
    }
    Run-Case 'the one migration, then the correction renames the current shape again and keeps every former id' {
        $m = Invoke-Tool 'spec_catalog\rename-prefix.ps1' @('-Prefix', 'TESTAB', '-AllRepos')
        Assert-Equal $m.code 0 "the migration ($($m.out))"
        $r = Invoke-Tool 'spec_catalog\rename-prefix.ps1' @('-Prefix', 'TESTCD', '-Correct', '-AllRepos')
        Assert-Equal $r.code 0 "the correction ($($r.out))"
        $byId = @{}; foreach ($x in (Read-Rows)) { $byId[$x.id] = $x }
        Assert-Equal (($byId.Keys | Sort-Object) -join ',') 'S0001,TESTCD-0002,TESTCD-0003' 'the ledger ids'
        Assert-Equal (@($byId['TESTCD-0002'].formerIds) -join ',') 'S0002,TESTAB-0002' 'formerIds list every id'
        Assert-Equal $byId['TESTCD-0002'].file 'PLAN/TESTCD-0002_open.md' 'the file of the row'
        Assert-Equal $byId['TESTCD-0003'].statusNote 'Blocker: TESTCD-0002' 'the statusNote token'
        Assert-Equal (Test-Path (Join-Path $repo 'PLAN\DONE\S0001_done.md')) 'True' 'the closed ticket kept its file'
        Assert-Equal ((Read-Text 'repo\PLAN\TESTCD-0003_held.md').Contains("Blocker: TESTCD-0002`n")) 'True' 'the token line'
        Assert-Equal ((Read-Text 'other\PLAN\S0009_waits.md').Contains('Blocker: t:TESTCD-0002')) 'True' "the other repository's token"
        $p = Read-Text 'repo\.sza-profile.json' | ConvertFrom-Json
        Assert-Equal $p.grammar.ticketIdPattern '^TESTCD-\d{4}$' 'the new pattern'
        Assert-Equal (@($p.grammar.legacyTicketIdPatterns) -join ',') '^S\d{4}$,^TESTAB-\d{4}$' 'the legacy list grew'
        Assert-Equal ($p.grammar.specFilePattern.Contains('TESTCD-\d{4}') -and $p.grammar.specFilePattern.Contains('TESTAB-\d{4}') -and $p.grammar.specFilePattern.Contains('S\d{4}')) 'True' 'the spec file pattern covers every shape'
    }
    Run-Case 'the next id continues the numbers; a return to a prefix carried before is refused' {
        $n = Invoke-Tool 'spec_catalog\next-id.ps1' @()
        Assert-Equal $n.out.Trim() 'TESTCD-0004' 'next-id.ps1'
        $back = Invoke-Tool 'spec_catalog\rename-prefix.ps1' @('-Prefix', 'TESTAB', '-Correct')
        Assert-Equal $back.code 2 "the return to TESTAB ($($back.out))"
    }
}
finally {
    if ($KeepScratch) { Write-Host "scratch kept: $scratch" }
    else { try { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction Stop } catch { Write-Host "scratch not removed: $scratch" } }
}
Write-Host "`nRESULT  run=$run  passed=$passed  failed=$failed"
if ($failed -gt 0) { exit 1 }
exit 0
