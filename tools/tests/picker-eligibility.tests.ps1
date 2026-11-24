<#
    Fast tests for the eligible set of the ranking (tools/harness/spec_catalog/spec-next-preflight.ps1; TASK-FLOW 0.42 rule 18,
    canon ticket CANONR-0175): the ranking offers the queued statuses and no others, in every run mode.
     1. A project holding one ticket in each of twelve statuses: the ranked list is exactly the seven queued statuses
        (Draft, Approved, Tactical, In Progress, Partial, Broken, BlockByOtherTask) and the eligible count is 7 of 12,
        with SZA_PQ_PICKER unset - the run mode of /spec-next and of a repository's own runner.
     2. The same project with SZA_PQ_PICKER=1 - the dispatcher's picker - gives the same ranked list.
     3. A project whose only tickets are Implemented, Verified and BlockNeedUserTest: nothing is selected, the eligible
        count is 0 and a reason is given, so a runner finds nothing to do instead of an idle audit pass.
     4. An explicit id is not ranking: spec-preamble.ps1 -Id of an Implemented ticket resolves it and claims its lease.
     5. The script no longer adds a status to the eligible set from the environment.
    Throwaway projects built by hand and four child processes started together; no real repository, registry, queue file
    or lease is touched, and no environment variable of this process is changed. -KeepScratch leaves the folder. #>
[CmdletBinding()]
param([switch]$KeepScratch)
$ErrorActionPreference = 'Stop'
$SourceRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
$harness = Join-Path $SourceRoot 'tools/harness'
$preflight = Join-Path $harness 'spec_catalog/spec-next-preflight.ps1'
$preamble = Join-Path $harness 'spec_catalog/spec-preamble.ps1'
$pwshExe = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
$clock = [Diagnostics.Stopwatch]::StartNew()
$run = 0; $passed = 0; $failed = 0
function Assert-That([bool]$Condition, [string]$Reason) { if (-not $Condition) { throw $Reason } }
function Test-Case([string]$Name, [scriptblock]$Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}
function Write-Utf8([string]$Path, [string]$Text) {
    $dir = [IO.Path]::GetDirectoryName($Path)
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
# One project: .sza-profile.json, the ledger and one spec file per ticket. $Tickets is a list of id/status pairs.
function New-Project([string]$Name, [object[]]$Tickets) {
    $root = Join-Path $scratch $Name
    Write-Utf8 (Join-Path $root '.sza-profile.json') '{}'
    $rows = foreach ($t in $Tickets) {
        $slug = ([string]$t.status).ToLowerInvariant() -replace '[^a-z]+', '-'
        $file = "PLAN/$($t.id)_$slug.md"
        Write-Utf8 (Join-Path $root $file) "# $($t.id)_$slug`n`n**Status:** $($t.status)`n"
        ([ordered]@{ id = $t.id; name = $slug; status = $t.status; priority = 50; file = $file; created = '2026-11-24'; updated = '2026-11-24 00:00' } | ConvertTo-Json -Compress)
    }
    Write-Utf8 (Join-Path $root 'PLAN/spec-catalog.jsonl') (($rows -join "`n") + "`n")
    return $root
}
# Start a child without waiting; the picker variable is set or removed on the child only.
function Start-Tool([string]$Project, [string]$Script, [string[]]$ToolArgs, [string]$Picker = '') {
    $psi = [Diagnostics.ProcessStartInfo]::new($pwshExe)
    foreach ($a in (@('-NoProfile', '-File', $Script) + $ToolArgs)) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $Project
    $psi.Environment['SZA_PROJECT_ROOT'] = $Project
    if ($Picker) { $psi.Environment['SZA_PQ_PICKER'] = $Picker } else { [void]$psi.Environment.Remove('SZA_PQ_PICKER') }
    $proc = [Diagnostics.Process]::Start($psi)
    [pscustomobject]@{ process = $proc; out = $proc.StandardOutput.ReadToEndAsync(); err = $proc.StandardError.ReadToEndAsync() }
}
function Wait-Tool($Started) {
    if (-not $Started.process.WaitForExit(60000)) { try { $Started.process.Kill($true) } catch { }; throw 'a child did not finish in 60 s' }
    $Started.process.WaitForExit()
    [pscustomobject]@{ code = $Started.process.ExitCode; out = [string]$Started.out.Result; err = [string]$Started.err.Result }
}
function Read-Payload($Result) {
    Assert-That ($Result.code -eq 0) "spec-next-preflight exited $($Result.code): $($Result.err)$($Result.out)"
    $line = @($Result.out -split "`r?`n" | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1)
    Assert-That ($line.Count -eq 1) "no JSON payload: $($Result.out)"
    return ($line[0] | ConvertFrom-Json)
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('picker-eligibility-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
try {
    $queued = [ordered]@{ S0001 = 'Draft'; S0002 = 'Approved'; S0003 = 'Tactical'; S0004 = 'In Progress'; S0005 = 'Partial'; S0006 = 'Broken'; S0007 = 'BlockByOtherTask' }
    $other = [ordered]@{ S0008 = 'Implemented'; S0009 = 'Verified'; S0010 = 'BlockNeedUserTest'; S0011 = 'BlockQuestions'; S0012 = 'BlockExternal' }
    $all = @(); foreach ($d in @($queued, $other)) { foreach ($k in $d.Keys) { $all += [pscustomobject]@{ id = $k; status = $d[$k] } } }
    $mixed = New-Project 'mixed' $all
    $finished = New-Project 'finished' @(
        [pscustomobject]@{ id = 'S0001'; status = 'Implemented' }, [pscustomobject]@{ id = 'S0002'; status = 'Verified' },
        [pscustomobject]@{ id = 'S0003'; status = 'BlockNeedUserTest' })
    $named = New-Project 'named' @([pscustomobject]@{ id = 'S0001'; status = 'Implemented' })

    # One wave of four children keeps the suite inside the five-second line.
    $wave = [ordered]@{
        attended = Start-Tool $mixed $preflight @('-NoDrift', '-Format', 'json')
        picker   = Start-Tool $mixed $preflight @('-NoDrift', '-Format', 'json') '1'
        finished = Start-Tool $finished $preflight @('-NoDrift', '-Format', 'json')
        named    = Start-Tool $named $preamble @('-Id', 'S0001', '-Reason', 'picker-eligibility')
    }
    $got = [ordered]@{}
    foreach ($k in $wave.Keys) { $got[$k] = Wait-Tool $wave[$k] }

    $expected = ($queued.Keys | Sort-Object) -join ','
    Test-Case 'unset SZA_PQ_PICKER: the ranked list is the seven queued statuses, and no finished or blocked one' {
        $p = Read-Payload $got.attended
        Assert-That ((@($p.ranked | ForEach-Object { $_.id } | Sort-Object) -join ',') -ceq $expected) "ranked is '$(@($p.ranked | ForEach-Object { $_.id }) -join ',')', not $expected"
        Assert-That ($p.eligible_count -eq 7 -and $p.total -eq 12) "eligible_count $($p.eligible_count) of total $($p.total), not 7 of 12"
        Assert-That (@($p.ranked | Where-Object { $_.status -ceq 'Implemented' }).Count -eq 0) 'an Implemented ticket was ranked'
    }
    Test-Case 'SZA_PQ_PICKER=1: the dispatcher''s picker ranks the same seven' {
        $p = Read-Payload $got.picker
        Assert-That ((@($p.ranked | ForEach-Object { $_.id } | Sort-Object) -join ',') -ceq $expected) "ranked is '$(@($p.ranked | ForEach-Object { $_.id }) -join ',')', not $expected"
        Assert-That ($p.eligible_count -eq 7) "eligible_count is $($p.eligible_count), not 7"
    }
    Test-Case 'a project with only Implemented, Verified and BlockNeedUserTest tickets selects nothing' {
        $p = Read-Payload $got.finished
        Assert-That ($null -eq $p.selected) "selected is '$($p.selected.id)', not null"
        Assert-That ($p.eligible_count -eq 0 -and $p.total -eq 3) "eligible_count $($p.eligible_count) of total $($p.total), not 0 of 3"
        Assert-That (-not [string]::IsNullOrWhiteSpace([string]$p.selected_none_reason)) 'no reason is given for selecting nothing'
    }
    Test-Case 'an explicit id is not ranking: spec-preamble of an Implemented ticket resolves it and claims the lease' {
        $r = $got.named
        Assert-That ($r.code -eq 0) "spec-preamble exited $($r.code): $($r.err)$($r.out)"
        Assert-That ($r.out -match '(?m)^\s*status:\s+Implemented\b') "the status line is missing: $($r.out)"
        Assert-That ($r.out -match 'claimed S0001') "the lease was not claimed: $($r.out)"
    }
    Test-Case 'the script adds no status to the eligible set from the environment' {
        $src = Get-Content -LiteralPath $preflight -Raw
        Assert-That ($src -notmatch '\$eligibleStatuses\s*\+=') 'the script appends to the eligible set'
        Assert-That ($src -notmatch '(?s)if \(\$env:SZA_PQ_PICKER[^{]*\{[^}]*\$eligibleStatuses') 'the picker variable still feeds the eligible set'
    }
} finally {
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Host ("RESULT  run={0}  passed={1}  failed={2}  {3} s" -f $run, $passed, $failed, [math]::Round($clock.Elapsed.TotalSeconds, 1))
if ($failed -gt 0) { exit 1 } else { exit 0 }
