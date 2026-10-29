#requires -Version 7.0
<#
.SYNOPSIS
    Cases for the ticket id grammar of the spec catalog: the id shape is the profile's grammar.ticketIdPattern
    (TASK-FLOW rule 2), not a hard-coded S####.

.DESCRIPTION
    Runs the shipped harness over throwaway projects; no registry, no portfolio, no agent. About twenty seconds.

      1. A project that numbers SP-0001 (the profile's pattern, its own archive folder and queue file): hand-kept
         tickets whose ids sit in the burned list are not orphans, capture takes the next number, the catalog and
         the picker accept it, an S#### id is refused, and an unburned stray file is still an orphan.
      2. The default grammar behaves as it always did: S0001, S0002, an SP- id refused, the same picker answer.
      3. A pattern with no fixed width still validates ids but cannot allocate one, and says so.
#>
[CmdletBinding()]
param([switch] $KeepScratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$harness = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\harness'))
$pwshExe = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('id-grammar-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null

# One child process per call, its own project root; returns the exit code and everything printed.
function Invoke-Harness([string] $Project, [string] $Script, [string[]] $Arguments = @()) {
    $psi = [Diagnostics.ProcessStartInfo]::new($pwshExe)
    foreach ($a in (@('-NoProfile', '-File', (Join-Path $harness $Script)) + $Arguments)) { $psi.ArgumentList.Add([string] $a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $Project
    $psi.Environment['SZA_PROJECT_ROOT'] = $Project
    [void] $psi.Environment.Remove('SZA_PROFILE_PATH')
    $proc = [Diagnostics.Process]::Start($psi)
    $out = $proc.StandardOutput.ReadToEndAsync()
    $err = $proc.StandardError.ReadToEndAsync()
    if (-not $proc.WaitForExit(120000)) { $proc.Kill($true); throw "$Script timed out" }
    $proc.WaitForExit()
    return [pscustomobject]@{ code = $proc.ExitCode; text = ($out.Result + $err.Result) }
}

function New-Project([string] $Name, $Profile) {
    $dir = Join-Path $scratch $Name
    New-Item -ItemType Directory -Path (Join-Path $dir 'PLAN') -Force | Out-Null
    if ($Profile) { [IO.File]::WriteAllText((Join-Path $dir '.sza-profile.json'), ($Profile | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false)) }
    return $dir
}
function Add-Stores([string] $Dir) {
    $r = Invoke-Harness $Dir 'scaffold\init-task-flow.ps1' @('-Root', $Dir, '-NoLaunchers', '-NoForwarder', '-RunnerPath', 'r0.ps1')
    Assert-That ($r.code -eq 0) "scaffold exit $($r.code): $($r.text)"
}
function Get-PickerSelected([string] $Dir) {
    $r = Invoke-Harness $Dir 'spec_catalog\spec-next-preflight.ps1' @('-NoDrift', '-Format', 'json')
    Assert-That ($r.code -eq 0) "picker exit $($r.code): $($r.text)"
    $line = @($r.text -split '\r?\n' | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1)[0]
    return ($line | ConvertFrom-Json)
}
$words = Join-Path $scratch 'owner.txt'
[IO.File]::WriteAllText($words, 'Urgent: stop the full build.', [Text.UTF8Encoding]::new($false))

try {
    Run-Case '1 SP-#### grammar: burned legacy ids, capture, update, picker, refusals' {
        $spProfile = [ordered]@{
            version = '1'; projectName = 'sp-proj'
            paths = [ordered]@{ specArchiveDir = 'PLAN/DONE'; releaseQueue = 'PLAN/PQ_QUEUE.md' }
            grammar = [ordered]@{ ticketIdPattern = '^SP-\d{4}$'; specFilePattern = '^PLAN/(DONE/)?SP-\d{4}_(?!spec_)' }
            probes = [ordered]@{ enabled = $false }
        }
        $dir = New-Project 'sp-proj' $spProfile
        New-Item -ItemType Directory -Path (Join-Path $dir 'PLAN\DONE') | Out-Null
        [IO.File]::WriteAllText((Join-Path $dir 'PLAN\SP-0001_old-open.md'), "# SP-0001`n`n**Status:** In Progress`n")
        [IO.File]::WriteAllText((Join-Path $dir 'PLAN\DONE\SP-0003_old-done.md'), "# SP-0003`n`n**Status:** Verified`n")
        Add-Stores $dir
        $burned = 1..3 | ForEach-Object { [ordered]@{ id = ('SP-{0:D4}' -f $_); reason = 'predates the ledger'; burned = '2026-10-29' } | ConvertTo-Json -Compress }
        [IO.File]::WriteAllText((Join-Path $dir 'PLAN\spec-catalog-burned-ids.jsonl'), (($burned -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))

        $v = Invoke-Harness $dir 'spec_catalog\validate.ps1'
        Assert-That ($v.code -eq 0 -and $v.text -match 'have a record or a burned id') "legacy tickets are orphans: $($v.text)"

        $c1 = Invoke-Harness $dir 'spec_catalog\capture-draft.ps1' @('-ProjectRoot', $dir, '-Slug', 'hotfix-x', '-TextFile', $words, '-Priority', '95')
        Assert-That ($c1.code -eq 0 -and $c1.text -match '(?m)^SP-0004\s*$') "first capture: $($c1.text)"
        $c2 = Invoke-Harness $dir 'spec_catalog\capture-draft.ps1' @('-ProjectRoot', $dir, '-Slug', 'second', '-TextFile', $words)
        Assert-That ($c2.code -eq 0 -and $c2.text -match '(?m)^SP-0005\s*$') "second capture: $($c2.text)"
        Assert-That (Test-Path (Join-Path $dir 'PLAN\SP-0004_hotfix-x.md')) 'the spec file is not at the profile''s path'

        $v = Invoke-Harness $dir 'spec_catalog\validate.ps1'
        Assert-That ($v.code -eq 0 -and $v.text -match 'dense SP-0001\.\.SP-0005') "validate after capture: $($v.text)"

        $u = Invoke-Harness $dir 'spec_catalog\update.ps1' @('-Id', 'SP-0004', '-Status', 'Approved')
        Assert-That ($u.code -eq 0 -and $u.text -match 'SP-0004 Draft -> Approved') "update: $($u.text)"
        $queue = Get-Content (Join-Path $dir 'PLAN\PQ_QUEUE.md') -Raw
        Assert-That ($queue -match '(?m)^SP-0004_hotfix-x\s+\S+\s+\S+\s+Approved' -and $queue -match '(?m)^SP-0005_second\s') "queue rows: $queue"

        $sel = Get-PickerSelected $dir
        Assert-That ([string]$sel.selected.id -ceq 'SP-0004') "the picker offered '$($sel.selected.id)', not SP-0004"

        $bad = Invoke-Harness $dir 'spec_catalog\update.ps1' @('-Id', 'S0004', '-Status', 'Approved')
        Assert-That ($bad.code -ne 0 -and $bad.text -match 'must match SP-####') "an S id was not refused: $($bad.text)"

        [IO.File]::WriteAllText((Join-Path $dir 'PLAN\SP-0009_stray.md'), "# SP-0009`n")
        $v = Invoke-Harness $dir 'spec_catalog\validate.ps1'
        Assert-That ($v.code -ne 0 -and $v.text -match 'orphan filesystem entries.*SP-0009_stray') "an unburned stray file passed: $($v.text)"
    }

    Run-Case '2 the default grammar is unchanged: S0001, an SP- id refused, the picker answers' {
        $dir = New-Project 'default-proj' $null
        Add-Stores $dir
        $c1 = Invoke-Harness $dir 'spec_catalog\capture-draft.ps1' @('-ProjectRoot', $dir, '-Slug', 'first', '-TextFile', $words)
        $c2 = Invoke-Harness $dir 'spec_catalog\capture-draft.ps1' @('-ProjectRoot', $dir, '-Slug', 'second', '-TextFile', $words)
        Assert-That ($c1.code -eq 0 -and $c1.text -match '(?m)^S0001\s*$' -and $c2.code -eq 0 -and $c2.text -match '(?m)^S0002\s*$') "captures: $($c1.text) | $($c2.text)"
        $v = Invoke-Harness $dir 'spec_catalog\validate.ps1'
        Assert-That ($v.code -eq 0 -and $v.text -match 'dense S0001\.\.S0002') "validate: $($v.text)"
        $sel = Get-PickerSelected $dir
        Assert-That ([string]$sel.selected.id -match '^S000[12]$') "the picker offered '$($sel.selected.id)'"
        $bad = Invoke-Harness $dir 'spec_catalog\update.ps1' @('-Id', 'SP-0001', '-Status', 'Approved')
        Assert-That ($bad.code -ne 0 -and $bad.text -match 'must match S####') "an SP id was not refused: $($bad.text)"
    }

    Run-Case '3 a pattern with no fixed width validates ids but cannot allocate one' {
        $dir = New-Project 'loose-proj' ([ordered]@{ version = '1'; projectName = 'loose'; grammar = [ordered]@{ ticketIdPattern = '^S\d{1,4}$' } })
        Add-Stores $dir
        $c = Invoke-Harness $dir 'spec_catalog\capture-draft.ps1' @('-ProjectRoot', $dir, '-Slug', 'first', '-TextFile', $words)
        Assert-That ($c.code -ne 0 -and $c.text -match 'cannot allocate ids') "no clear refusal: exit $($c.code): $($c.text)"
        Assert-That (-not (Test-Path (Join-Path $dir 'PLAN\S1_first.md'))) 'a ticket file was written anyway'
    }
}
finally {
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
    else { Write-Host "scratch kept: $scratch" }
}

Write-Host ''
Write-Host "ticket-id-grammar: $passed/$run passed, $failed failed"
exit $(if ($failed -gt 0 -or $run -eq 0) { 1 } else { 0 })
