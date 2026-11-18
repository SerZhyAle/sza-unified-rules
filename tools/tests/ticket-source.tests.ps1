<#  Fast cases of the ledger field `source` (TASK-FLOW rule 3): Resolve-TicketSource of
    spec_catalog/_ticket-source.ps1 called directly (default, variable, argument, queue sync, refusal) and three child
    runs of insert.ps1 in a throwaway repository under the system temp directory. Nothing else is touched.
    Exit 0 when every case passed, 1 on any failure. Expected wall time: under 5 s.
    Run:  pwsh -NoProfile -File tools/tests/ticket-source.tests.ps1 [-KeepScratch] #>
[CmdletBinding()]
param([switch] $KeepScratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Harness = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))) 'tools\harness'
. (Join-Path $Harness 'spec_catalog\_ticket-source.ps1')
$pwshExe = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source

$run = 0; $passed = 0; $failed = 0
function Assert-Equal($Actual, $Expected, [string] $What) { if ("$Actual" -cne "$Expected") { throw "$What - expected '$Expected', got '$Actual'" } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}
function Resolve-With([string] $Explicit, $Variable, $InSync) {   <# $null removes the variable #>
    $env:SZA_TICKET_SOURCE = $Variable; $env:SZA_PQ_IN_SYNC = $InSync
    return (Resolve-TicketSource -Explicit $Explicit)
}
$savedSource = $env:SZA_TICKET_SOURCE; $savedSync = $env:SZA_PQ_IN_SYNC   <# this suite may itself run inside a pass #>
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('ticket-source-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$repo = Join-Path $scratch 'repo'
New-Item -ItemType Directory -Path (Join-Path $repo 'PLAN') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $repo '.sza-profile.json'), '{}', [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $repo 'PLAN\spec-catalog.jsonl'), '', [Text.UTF8Encoding]::new($false))
function Invoke-Insert([string[]] $Arguments, $Variable) {
    $psi = [Diagnostics.ProcessStartInfo]::new($pwshExe)
    foreach ($a in (@('-NoProfile', '-File', (Join-Path $Harness 'spec_catalog\insert.ps1')) + $Arguments)) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $repo
    $psi.Environment['SZA_PROJECT_ROOT'] = $repo
    $psi.Environment['SZA_PORTFOLIO_ROOT'] = (Join-Path $scratch 'portfolio')
    $psi.Environment['SZA_SKIP_RELEASE_QUEUE'] = '1'   <# no plan files, no portfolio refresh: the row is the subject #>
    foreach ($n in 'SZA_PROFILE_PATH', 'SZA_SPEC_CATALOG_DIR', 'SZA_PQ_IN_SYNC', 'SZA_TICKET_SOURCE') { [void]$psi.Environment.Remove($n) }
    if ($null -ne $Variable) { $psi.Environment['SZA_TICKET_SOURCE'] = [string]$Variable }
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(30000)) { try { $p.Kill($true) } catch { }; throw 'insert.ps1 timed out' }
    $p.WaitForExit()
    return @{ code = $p.ExitCode; out = ([string]$o.Result + [string]$e.Result) }
}
try {
    Run-Case 'resolve: no argument and no variable is owner' { Assert-Equal (Resolve-With '' $null $null) 'owner' 'the default' }
    Run-Case 'resolve: the variable names the source' {
        Assert-Equal (Resolve-With '' 'robot' $null) 'robot' 'the child of a pass'; Assert-Equal (Resolve-With '' 'inbox' $null) 'inbox' 'the child of the inbox ingest'
    }
    Run-Case 'resolve: the argument beats the variable and the queue sync' {
        Assert-Equal (Resolve-With 'campaign' 'robot' $null) 'campaign' 'over the variable'; Assert-Equal (Resolve-With 'owner' 'robot' '1') 'owner' 'over the queue sync'
    }
    Run-Case 'resolve: the queue sync child is import whatever variable it inherited' {
        Assert-Equal (Resolve-With '' $null '1') 'import' 'no variable'; Assert-Equal (Resolve-With '' 'robot' '1') 'import' 'a sync started from inside a pass'
    }
    Run-Case 'resolve: a value outside the list throws and names the list (case-sensitive)' {
        foreach ($bad in @(@('capture', $null), @('', 'Robot'))) {
            $msg = ''
            try { $null = Resolve-With $bad[0] $bad[1] $null } catch { $msg = $_.Exception.Message }
            Assert-Equal ($msg -match 'Allowed: owner, robot, import, inbox, campaign') 'True' "the refusal of '$($bad[0])$($bad[1])'"
        }
    }
    Run-Case 'insert.ps1 writes the field and refuses an unknown value before a row exists' {
        $a = Invoke-Insert @('-Name', 'by-robot', '-Slug', 'by-robot') 'robot'
        Assert-Equal $a.code 0 "the insert of a pass child ($($a.out))"
        $b = Invoke-Insert @('-Name', 'by-hand', '-Slug', 'by-hand') $null
        Assert-Equal $b.code 0 "the plain insert ($($b.out))"
        $c = Invoke-Insert @('-Name', 'bad', '-Slug', 'bad', '-Source', 'nonsense') $null
        Assert-Equal $c.code 1 'an unknown -Source exits 1'
        $rows = @(Get-Content -LiteralPath (Join-Path $repo 'PLAN\spec-catalog.jsonl') -Encoding UTF8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
        Assert-Equal $rows.Count 2 'the refused call wrote no row'
        Assert-Equal (($rows | ForEach-Object { "$($_.name)=$($_.source)" }) -join ',') 'by-robot=robot,by-hand=owner' 'the two rows'
    }
}
finally {
    $env:SZA_TICKET_SOURCE = $savedSource; $env:SZA_PQ_IN_SYNC = $savedSync
    if ($KeepScratch) { Write-Host "scratch kept: $scratch" }
    else { try { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction Stop } catch { Write-Host "scratch not removed: $scratch" } }
}
Write-Host "`nRESULT  run=$run  passed=$passed  failed=$failed"
if ($failed -gt 0) { exit 1 }
exit 0
