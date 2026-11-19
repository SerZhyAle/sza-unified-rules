<#  Fast cases of the one prefix migration of TASK-FLOW 0.37 rule 2 (canon ticket S0152): spec_catalog/rename-prefix.ps1
    run as a child in a throwaway repository and a throwaway portfolio root under the system temp directory - the dry
    run, the rename (ledger rows, formerIds, files, folder, token lines, prose left alone, plan file, the other
    repository's qualified token), the next id continuing the old numbers, a former id accepted by update.ps1, the
    refusal of a second migration and of a bad prefix, the R0 launcher's -IdRegex default re-rendered by the run and
    healed by a repeat of the same prefix (CANONR-0157), the probes of the renamed tickets retagged in source by the run
    and healed by the same repeat (CANONR-0158). Nothing else is touched.
    Exit 0 when every case passed, 1 on any failure.
    Run:  pwsh -NoProfile -File tools/tests/rename-prefix.tests.ps1 [-KeepScratch] #>
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

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('rename-prefix-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
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
Write-Text (Join-Path $repo 'PLAN\S0002_open.md') "# S0002_open`n`n**Status:** Draft`n`nSee [the held one](S0003_held.md).`n"
Write-Text (Join-Path $repo 'PLAN\S0002_open\attachments\a.txt') 'x'
Write-Text (Join-Path $repo 'PLAN\S0003_held.md') "# S0003_held`n`n**Status:** BlockByOtherTask`n`nBlocker: S0002`n`nThe prose names S0002 and S0001 and stays as written.`n"
Write-Text (Join-Path $repo 'PLAN\RELEASE_QUEUE.md') "# Release Queue`n`nticket  changed  status`n1`nS0003_held  26-11-01 10:00  BlockByOtherTask`nS0002_open  26-11-01 10:00  Draft`n"
$launcherText = "param(`n    [string[]] `$ChildArgs      = @(),`n    [string]   `$IdRegex        = 'S\d{4}',`n    [string[]] `$WorkStatuses   = @('Draft')`n)`n"
$launcherNew = $launcherText.Replace("'S\d{4}'", "'(?:TESTAB-\d{4}|S\d{4})'")
Write-Text (Join-Path $repo 'r0.ps1') $launcherText
<# CANONR-0158: probes of two open tickets (one spanning two lines), a probe of the closed one, and mentions that are
   not probes - a log call of another level and a comment. #>
$sourceText = "fun a() {`n    Timber.d(`"S0002: opened`")`n    Timber.d(`n        `"S0003: held`")`n    Timber.i(`"S0002: not a probe`")`n    // Timber.d(`"S0002: in a comment`")`n    Timber.d(`"S0001: closed`")`n}`n"
$sourceNew = $sourceText.Replace('"S0002: opened"', '"TESTAB-0002: opened"').Replace('"S0003: held"', '"TESTAB-0003: held"')
Write-Text (Join-Path $repo 'src\A.kt') $sourceText
Write-Text (Join-Path $other 'PLAN\S0009_waits.md') "# S0009_waits`n`nBlocker: t:S0002`n`nBlocker: t:S0001`n"
$reg = @{ repos = @(@{ key = 't'; path = $repo }, @{ key = 'o'; path = $other }) } | ConvertTo-Json -Depth 5
Write-Text (Join-Path $portfolio 'repos.json') $reg
Write-Text (Join-Path $portfolio 'PORTFOLIO_QUEUE.md') "ticket  changed  status`n1`nt:S0002_open  26-11-01 10:00  Draft`no:S0009_waits  26-11-01 10:00  Draft`n"

$fakeHome = Join-Path $scratch 'home'
$fakeReader = Join-Path $fakeHome '.claude\plugins\cache\sza-unified-rules\sza\2026.1118.1\tools\harness\_profile.ps1'
Write-Text $fakeReader '# a harness before TASK-FLOW 0.37'

function Invoke-Tool([string] $Script, [string[]] $Arguments) {
    $psi = [Diagnostics.ProcessStartInfo]::new($pwshExe)
    foreach ($a in (@('-NoProfile', '-File', (Join-Path $Harness $Script)) + $Arguments)) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $repo
    $psi.Environment['SZA_PROJECT_ROOT'] = $repo
    $psi.Environment['SZA_PORTFOLIO_ROOT'] = $portfolio
    $psi.Environment['USERPROFILE'] = $fakeHome   <# the plugin cache the guard reads is the scratch one #>
    $psi.Environment['SZA_SKIP_RELEASE_QUEUE'] = '1'   <# the plan files are rewritten by the tool itself; no re-render, no pq sync #>
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
    Run-Case 'a bad prefix is refused with exit 2' {
        $r = Invoke-Tool 'spec_catalog\rename-prefix.ps1' @('-Prefix', 'canon_')
        Assert-Equal $r.code 2 "the exit code ($($r.out))"
    }
    Run-Case 'the dry run lists the renames and writes nothing' {
        $r = Invoke-Tool 'spec_catalog\rename-prefix.ps1' @('-Prefix', 'TESTAB', '-DryRun', '-AllRepos')
        Assert-Equal $r.code 0 "the exit code ($($r.out))"
        Assert-Equal ($r.out -match 'S0002 -> TESTAB-0002' -and $r.out -match 'S0003 -> TESTAB-0003' -and $r.out -notmatch 'S0001 ->') 'True' 'the listed renames'
        Assert-Equal (Read-Text 'repo\.sza-profile.json') $profileText 'the profile'
        Assert-Equal (Test-Path (Join-Path $repo 'PLAN\S0002_open.md')) 'True' 'the old spec file'
        Assert-Equal ($r.out.Contains('would set the -IdRegex default')) 'True' 'the planned launcher line'
        Assert-Equal (Read-Text 'repo\r0.ps1') $launcherText 'the launcher'
        Assert-Equal ($r.out -match 'would retag the probe .*A\.kt:2  S0002 -> TESTAB-0002' -and $r.out -match 'A\.kt:3  S0003 -> TESTAB-0003') 'True' "the planned probe retags ($($r.out))"
        Assert-Equal (Read-Text 'repo\src\A.kt') $sourceText 'the source'
    }
    Run-Case 'an installed plugin older than TASK-FLOW 0.37 refuses the run with exit 2' {
        $r = Invoke-Tool 'spec_catalog\rename-prefix.ps1' @('-Prefix', 'TESTAB')
        Assert-Equal $r.code 2 "the exit code ($($r.out))"
        Assert-Equal (Read-Text 'repo\.sza-profile.json') $profileText 'the profile'
        Write-Text $fakeReader '# grammar.legacyTicketIdPatterns'   <# the release that ships the reader #>
    }
    Run-Case 'the run renames the open tickets and only them' {
        $r = Invoke-Tool 'spec_catalog\rename-prefix.ps1' @('-Prefix', 'TESTAB', '-AllRepos')
        Assert-Equal $r.code 0 "the exit code ($($r.out))"
        $byId = @{}; foreach ($x in (Read-Rows)) { $byId[$x.id] = $x }
        Assert-Equal (($byId.Keys | Sort-Object) -join ',') 'S0001,TESTAB-0002,TESTAB-0003' 'the ledger ids'
        Assert-Equal (@($byId['TESTAB-0002'].formerIds) -join ',') 'S0002' 'formerIds'
        Assert-Equal $byId['TESTAB-0002'].file 'PLAN/TESTAB-0002_open.md' 'the file of the row'
        Assert-Equal $byId['TESTAB-0003'].statusNote 'Blocker: TESTAB-0002' 'the statusNote token'
        Assert-Equal (Test-Path (Join-Path $repo 'PLAN\TESTAB-0002_open\attachments\a.txt')) 'True' 'the renamed folder'
        Assert-Equal (Test-Path (Join-Path $repo 'PLAN\DONE\S0001_done.md')) 'True' 'the closed ticket kept its file'
        $held = Read-Text 'repo\PLAN\TESTAB-0003_held.md'
        Assert-Equal ($held.StartsWith('# TESTAB-0003_held')) 'True' 'the heading'
        Assert-Equal ($held.Contains("Blocker: TESTAB-0002`n")) 'True' 'the token line'
        Assert-Equal ($held.Contains('The prose names S0002 and S0001 and stays as written.')) 'True' 'the prose'
        Assert-Equal ((Read-Text 'repo\PLAN\TESTAB-0002_open.md').Contains('(TESTAB-0003_held.md)')) 'True' 'the link to the renamed file'
        Assert-Equal ((Read-Text 'repo\PLAN\RELEASE_QUEUE.md').Contains("`nTESTAB-0002_open ")) 'True' 'the plan file row'
        $o = Read-Text 'other\PLAN\S0009_waits.md'
        Assert-Equal ($o.Contains('Blocker: t:TESTAB-0002') -and $o.Contains('Blocker: t:S0001')) 'True' "the other repository's tokens"
        Assert-Equal ((Read-Text 'portfolio\PORTFOLIO_QUEUE.md').Contains("`nt:TESTAB-0002_open ")) 'True' 'the portfolio queue row'
        $p = Read-Text 'repo\.sza-profile.json' | ConvertFrom-Json
        Assert-Equal $p.grammar.ticketIdPattern '^TESTAB-\d{4}$' 'the new pattern'
        Assert-Equal (@($p.grammar.legacyTicketIdPatterns) -join ',') '^S\d{4}$' 'the legacy pattern'
        Assert-Equal (Read-Text 'repo\r0.ps1') $launcherNew 'the re-rendered launcher'
        Assert-Equal (Read-Text 'repo\src\A.kt') $sourceNew 'the retagged probes, the rest of the source as written'
    }
    Run-Case 'the same prefix again re-renders a stale launcher, retags left-over probes and leaves the ledger alone' {
        Write-Text (Join-Path $repo 'r0.ps1') $launcherText
        Write-Text (Join-Path $repo 'src\A.kt') $sourceText   <# a repository that migrated before CANONR-0158 #>
        $before = Read-Text 'repo\PLAN\spec-catalog.jsonl'
        $r = Invoke-Tool 'spec_catalog\rename-prefix.ps1' @('-Prefix', 'TESTAB')
        Assert-Equal $r.code 0 "the exit code ($($r.out))"
        Assert-Equal (Read-Text 'repo\r0.ps1') $launcherNew 'the healed launcher'
        Assert-Equal (Read-Text 'repo\src\A.kt') $sourceNew 'the healed probes'
        Assert-Equal (Read-Text 'repo\PLAN\spec-catalog.jsonl') $before 'the ledger'
    }
    Run-Case 'the next id continues the old numbers, a former id names its ticket, a second migration is refused' {
        $n = Invoke-Tool 'spec_catalog\next-id.ps1' @()
        Assert-Equal $n.out.Trim() 'TESTAB-0004' 'next-id.ps1'
        $u = Invoke-Tool 'spec_catalog\update.ps1' @('-Id', 'S0002', '-Priority', '61')
        Assert-Equal $u.code 0 "update.ps1 by the former id ($($u.out))"
        Assert-Equal (@(Read-Rows | Where-Object { $_.id -eq 'TESTAB-0002' })[0].priority) 61 'the priority of the renamed row'
        $again = Invoke-Tool 'spec_catalog\rename-prefix.ps1' @('-Prefix', 'TESTCD')
        Assert-Equal $again.code 2 "the second migration ($($again.out))"
    }
}
finally {
    if ($KeepScratch) { Write-Host "scratch kept: $scratch" }
    else { try { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction Stop } catch { Write-Host "scratch not removed: $scratch" } }
}
Write-Host "`nRESULT  run=$run  passed=$passed  failed=$failed"
if ($failed -gt 0) { exit 1 }
exit 0
