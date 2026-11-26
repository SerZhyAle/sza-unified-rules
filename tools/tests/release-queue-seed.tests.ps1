#requires -Version 7.0
<#
.SYNOPSIS
  S0151: release-queue.ps1 -Seed, the one-off that moves an existing ledger onto the release plan, and the unlisted-row
  count of -Validate. Child processes of the harness's own scripts only, against a throwaway repository under the
  system temp directory.
.DESCRIPTION
  The sync never adds a ready ticket that stands on neither side of the plan (it shipped earlier, is the premise).
  The seed is the owner's action for a ledger that already holds built, unshipped work: it puts those tickets into one
  package of the finished side (ledger fields, TASK-FLOW 0.52), splits a hand-kept queue file by status keeping the
  owner's `#` group comment lines with the rows that move, and is a dry run unless -Apply is given.

  The fixture is a ledger of nine rows and a hand-kept queue file of four: S0001 unfinished under package 1; S0002
  and S0003 ready, under one group comment; S0004 ready, in package 2 under a two-line group comment. S0005, S0006
  and S0009 are ready and listed nowhere and newer than the last release; S0007 is ready, listed nowhere and older;
  S0008 is unfinished and listed nowhere. S0009 was updated at the very minute of -Since.

  Cases:
    validate before - -Validate names the four ready ledger rows listed in neither file and still reports the one
                      unfinished row missing from the queue as drift (exit 1)
    dry run         - -Seed -Release 3 -Since .. writes nothing (the queue file and the ledger byte for byte, no ready
                      file, no done file) and prints each add, move, new and left-out row, with a moved row's group
    apply           - -Apply writes the ledger and no ready or done file; the ready view holds package 1 and package 2
                      with their group comments and package 3 with S0005, S0006, S0009 in id order; S0007 is left out;
                      the queue file keeps its comments and gains S0008 at package 3
    validate after  - -Validate exits 0 and counts the one row left out
    second apply    - without -Since, with a tenth ready row and an eleventh the ledger reopened while its row still
                      carries a package: S0007 and S0010 land at the end of the existing package 3 run (one heading),
                      S0011 goes back to the queue, nothing else moves, and the output says no -Since was given
    arguments       - a non-numeric -Release and an unreadable -Since each stop before any write
  Exit 0 when every case passed, 1 on any failure.
#>
[CmdletBinding()]
param([switch] $KeepScratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$Harness = Join-Path $SourceRoot 'tools\harness'
$Tool = Join-Path $Harness 'spec_catalog\release-queue.ps1'
$pwshExe = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Assert-Equal($Actual, $Expected, [string] $What) {
    if ("$Actual" -cne "$Expected") { throw "$What - expected '$Expected', got '$Actual'" }
}
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('queue-seed-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null

function Write-Utf8([string] $Path, [string] $Text) {
    $dir = [IO.Path]::GetDirectoryName($Path)
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
function New-Row([string] $Id, [string] $Slug, [string] $Status, [string] $Updated) {
    return ([ordered]@{ id = $Id; name = $Slug; status = $Status; priority = 50; file = "PLAN/${Id}_$Slug.md"; created = '2026-11-01'; updated = $Updated } | ConvertTo-Json -Compress)
}
function Start-Tool([string] $Root, [string[]] $Arguments) {
    $psi = [Diagnostics.ProcessStartInfo]::new($pwshExe)
    foreach ($a in (@('-NoProfile', '-File', $Tool) + $Arguments)) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $Root
    $psi.Environment['SZA_PROJECT_ROOT'] = $Root
    # The projection is a `pq sync` child; this repository is not registered, so it would do nothing but cost time.
    $psi.Environment['SZA_PQ_IN_SYNC'] = '1'
    foreach ($n in 'SZA_PROFILE_PATH', 'SZA_SPEC_CATALOG_DIR', 'SZA_SKIP_RELEASE_QUEUE') { [void]$psi.Environment.Remove($n) }
    $p = [Diagnostics.Process]::Start($psi)
    return @{ proc = $p; o = $p.StandardOutput.ReadToEndAsync(); e = $p.StandardError.ReadToEndAsync() }
}
function Wait-Tool($Handle) {
    $p = $Handle.proc
    if (-not $p.WaitForExit(60000)) { try { $p.Kill($true) } catch { } ; throw 'release-queue.ps1 timed out' }
    $p.WaitForExit()
    return @{ code = $p.ExitCode; out = ([string]$Handle.o.Result + [string]$Handle.e.Result) }
}
function Invoke-Tool([string] $Root, [string[]] $Arguments) { return (Wait-Tool (Start-Tool $Root $Arguments)) }
function Get-Skeleton([string] $Path) {
    # The lines that carry the plan: package headings, `#` lines and the ticket token of each row.
    $out = New-Object System.Collections.Generic.List[string]
    $text = if ($Path.Contains("`n")) { $Path } else { [IO.File]::ReadAllText($Path) }
    foreach ($line in ($text -split "`r?`n")) {
        $t = $line.Trim()
        if ($t -match '^(\d+|--)$' -or $t.StartsWith('#')) { $out.Add($t) }
        elseif ($t -match '^(S\d{4}_\S+)\s') { $out.Add($Matches[1]) }
    }
    return ($out -join '|')
}

try {
    $repo = Join-Path $scratch 'repo'
    $queuePath = Join-Path $repo 'PLAN\RELEASE_QUEUE.md'
    $readyPath = Join-Path $repo 'PLAN\RELEASE_READY.md'
    $donePath = Join-Path $repo 'PLAN\RELEASE_QUEUE_DONE.md'
    $ledgerPath = Join-Path $repo 'PLAN\spec-catalog.jsonl'
    Write-Utf8 (Join-Path $repo '.sza-profile.json') '{}'
    $rows = @(
        (New-Row 'S0001' 'one' 'Draft' '2026-11-12 10:00'),
        (New-Row 'S0002' 'two' 'Implemented' '2026-11-14 10:00'),
        (New-Row 'S0003' 'three' 'Verified' '2026-11-14 11:00'),
        (New-Row 'S0004' 'four' 'BlockNeedUserTest' '2026-11-15 09:00'),
        (New-Row 'S0005' 'five' 'Verified' '2026-11-16 08:00'),
        (New-Row 'S0006' 'six' 'Implemented' '2026-11-14 12:00'),
        (New-Row 'S0007' 'seven' 'Verified' '2026-11-10 08:00'),
        (New-Row 'S0008' 'eight' 'Draft' '2026-11-13 09:00'),
        (New-Row 'S0009' 'nine' 'Implemented' '2026-11-13 01:30')
    )
    Write-Utf8 $ledgerPath (($rows -join "`n") + "`n")
    $queueText = @(
        '# Release queue'
        'current-next-release: 3'
        ''
        'A bare number opens a package.'
        ''
        'ticket                                                         changed         status'
        '1'
        'S0001_one                                                      26-11-12 10:00  Draft'
        '# Group A - sorting'
        'S0002_two                                                      26-11-14 10:00  Implemented'
        'S0003_three                                                    26-11-14 11:00  Verified'
        '2'
        '# Group B - wear'
        '# second line of group B'
        'S0004_four                                                     26-11-15 09:00  BlockNeedUserTest'
    ) -join "`r`n"
    Write-Utf8 $queuePath ($queueText + "`r`n")

    # Phase one: the four calls that must write nothing - -Validate, the dry run and the two refused ones - run side by
    # side, because each costs about half a second and the suite is held to the 5 s line. They share one fixture state.
    $queueBefore = [IO.File]::ReadAllText($queuePath)
    $ledgerBefore = [IO.File]::ReadAllText($ledgerPath)
    $handles = [ordered]@{
        validate   = (Start-Tool $repo @('-Validate'))
        dry        = (Start-Tool $repo @('-Seed', '-Release', '3', '-Since', '2026-11-13 01:30'))
        badRelease = (Start-Tool $repo @('-Seed', '-Release', 'next', '-Apply'))
        badSince   = (Start-Tool $repo @('-Seed', '-Release', '3', '-Since', 'last friday', '-Apply'))
    }
    $phaseOne = @{}
    foreach ($k in $handles.Keys) { $phaseOne[$k] = Wait-Tool $handles[$k] }
    $untouched = @{
        queue  = ([IO.File]::ReadAllText($queuePath) -ceq $queueBefore)
        ledger = ([IO.File]::ReadAllText($ledgerPath) -ceq $ledgerBefore)
        ready  = (Test-Path -LiteralPath $readyPath)
        done   = (Test-Path -LiteralPath $donePath)
    }

    Run-Case 'validate before: the ready rows listed nowhere are counted, the unfinished one missing is still drift' {
        $r = $phaseOne['validate']
        Assert-Equal $r.code 1 "-Validate exit code: $($r.out)"
        Assert-That ($r.out -match 'missing from the queue: S0008_eight') "S0008 is not named as missing: $($r.out)"
        Assert-That ($r.out -match 'note - 4 ready ledger row\(s\) are on neither side of the plan') "the count of unlisted ready rows is missing or wrong: $($r.out)"
        Assert-That ($r.out -match '-Seed -Release') "the note does not name the seed: $($r.out)"
    }

    Run-Case 'dry run: -Seed without -Apply writes nothing and names every row' {
        $r = $phaseOne['dry']
        Assert-Equal $r.code 0 "-Seed dry run: $($r.out)"
        Assert-That ($r.out -match 'DRY RUN, nothing written') "the dry run does not say so: $($r.out)"
        Assert-That ($r.out -match 'add\s+S0005_five\s+Verified') "S0005 is not listed as added: $($r.out)"
        Assert-That ($r.out -match 'add\s+S0009_nine\s+Implemented') "S0009 (updated at the minute of -Since) is not listed as added: $($r.out)"
        Assert-That ($r.out -match 'left out\s+S0007_seven.*before -Since') "S0007 is not listed as left out: $($r.out)"
        Assert-That ($r.out -match 'move\s+S0002_two.*under "# Group A - sorting"') "the move of S0002 does not name its group: $($r.out)"
        Assert-That ($r.out -match 'move\s+S0004_four.*under "# second line of group B"') "the move of S0004 does not name its group: $($r.out)"
        Assert-That ($r.out -match 'new\s+S0008_eight\s+Draft') "S0008 is not listed as new in the queue: $($r.out)"
        Assert-That ($r.out -match 'would add 3 ready ticket\(s\) to package 3, moved 3 from the queue file, put 0 back in the queue, queued 1 new, left out 1') "the summary line is wrong: $($r.out)"
        Assert-That $untouched['queue'] 'the queue file changed under a dry run'
        Assert-That $untouched['ledger'] 'the ledger changed under a dry run'
        Assert-That (-not $untouched['ready']) 'the ready file was created by a dry run'
        Assert-That (-not $untouched['done']) 'the done file was created by a dry run'
    }

    Run-Case 'apply: the files, the groups, the id order and the left-out row' {
        $r = Invoke-Tool $repo @('-Seed', '-Release', '3', '-Since', '2026-11-13 01:30', '-Apply')
        Assert-Equal $r.code 0 "-Seed -Apply: $($r.out)"
        Assert-That ($r.out -notmatch 'DRY RUN') "an applied seed calls itself a dry run: $($r.out)"
        Assert-That ($r.out -match 'seed - added 3 ready ticket\(s\) to package 3, moved 3 from the queue file') "the summary does not say added 3 and moved 3: $($r.out)"
        Assert-That (-not (Test-Path -LiteralPath $readyPath) -and -not (Test-Path -LiteralPath $donePath)) 'a ready or a shipped file was written'
        $view = (Invoke-Tool $repo @('-Show', 'Ready')).out
        Assert-Equal (Get-Skeleton $view) ('# Release Content (ready)|1|# Group A - sorting|S0002_two|S0003_three|2|# Group B - wear|# second line of group B|S0004_four|3|S0005_five|S0006_six|S0009_nine') 'the ready view'
        Assert-Equal (Get-Skeleton $queuePath) ('# Release queue|1|S0001_one|# Group A - sorting|2|# Group B - wear|# second line of group B|3|S0008_eight') 'the queue file'
        Assert-That ($view -match 'S0002_two\s+26-11-14 10:00\s+Implemented') 'a moved row lost its changed stamp'
        Assert-That ($view -match 'S0005_five\s+26-11-16 08:00\s+Verified') 'an added row does not carry the ledger stamp'
        $seven = @([IO.File]::ReadAllLines($ledgerPath) | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.id -eq 'S0007' })[0]
        Assert-That ($null -eq $seven.PSObject.Properties['package']) 'the row before -Since got a package'
    }

    Run-Case 'validate after: clean, and the one row left out is counted' {
        $r = Invoke-Tool $repo @('-Validate')
        Assert-Equal $r.code 0 "-Validate after the seed: $($r.out)"
        Assert-That ($r.out -match 'OK - 8 ticket\(s\), no drift') "the OK line is missing: $($r.out)"
        Assert-That ($r.out -match 'note - 1 ready ledger row\(s\) are on neither side of the plan') "the left-out row is not counted: $($r.out)"
    }

    Run-Case 'second apply: no -Since, one more ready row, one reopened; the package block grows, the reopened row goes back, nothing else moves' {
        # S0011 stands on the finished side while the ledger has reopened it as Draft - the state a ledger write
        # leaves behind when the sync did not run. The seed does what the sync would: the row goes back.
        $eleven = (New-Row 'S0011' 'eleven' 'Draft' '2026-11-17 10:00').TrimEnd('}') + ',"package":"3","packageOrder":99,"packageChanged":"26-11-17 10:00"}'
        Write-Utf8 $ledgerPath (([IO.File]::ReadAllText($ledgerPath)) + (New-Row 'S0010' 'ten' 'Verified' '2026-11-17 09:00') + "`n" + $eleven + "`n")
        $r = Invoke-Tool $repo @('-Seed', '-Release', '3', '-Apply')
        Assert-Equal $r.code 0 "second -Seed -Apply: $($r.out)"
        Assert-That ($r.out -match 'no -Since') "the missing -Since is not said: $($r.out)"
        Assert-That ($r.out -match 'back\s+S0011_eleven\s+Draft\s+ready -> PLAN/RELEASE_QUEUE\.md, package 3') "the return of S0011 is not listed: $($r.out)"
        Assert-That ($r.out -match 'added 2 ready ticket\(s\) to package 3, moved 0 from the queue file, put 1 back in the queue') "the second summary is wrong: $($r.out)"
        Assert-Equal (Get-Skeleton (Invoke-Tool $repo @('-Show', 'Ready')).out) ('# Release Content (ready)|1|# Group A - sorting|S0002_two|S0003_three|2|# Group B - wear|# second line of group B|S0004_four|3|S0005_five|S0006_six|S0009_nine|S0007_seven|S0010_ten') 'the ready view after the second seed'
        Assert-Equal (Get-Skeleton $queuePath) ('# Release queue|1|S0001_one|# Group A - sorting|2|# Group B - wear|# second line of group B|3|S0008_eight|S0011_eleven') 'the queue file after the second seed'
    }

    Run-Case 'arguments: a non-numeric -Release and an unreadable -Since stop before any write' {
        $r = $phaseOne['badRelease']
        Assert-Equal $r.code 1 "-Seed -Release next: $($r.out)"
        Assert-That ($r.out -match 'package number') "the bad -Release is not explained: $($r.out)"
        $r = $phaseOne['badSince']
        Assert-Equal $r.code 1 "-Seed -Since 'last friday': $($r.out)"
        Assert-That ($r.out -match 'yyyy-MM-dd') "the bad -Since is not explained: $($r.out)"
        # -Apply was on both calls, and they ran with the files in the state of the first case.
        Assert-That ($untouched['queue'] -and $untouched['ledger'] -and -not $untouched['ready'] -and -not $untouched['done']) 'a refused call wrote a file'
    }
}
finally {
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
    else { Write-Host "scratch kept: $scratch" }
}

Write-Host ''
Write-Host ("run={0} passed={1} failed={2}" -f $run, $passed, $failed)
if ($failed -gt 0) { exit 1 }
exit 0
