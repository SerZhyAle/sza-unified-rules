#requires -Version 7.0
<#
.SYNOPSIS
    Cases for S0056: a release archive of many BlockNeedUserTest tickets takes ONE code lock and ONE tree scan
    for the probe removal, not one of each per ticket.

.DESCRIPTION
    A fast check (the whole file is a few seconds): the batch function is called in-process against a scratch
    project root, the lock scripts run for real in it, and one case drives archive.ps1 end to end in a child.

      1. three tickets, probes in two files: one lock taken and released, the remover ran three times and each
         time under the lock, every probe is gone, every verdict is clear.
      2. one remover exits non-zero: that ticket alone is refused and keeps its probe; the others are cleared.
      3. a remover that exits 0 and leaves a probe: the post-release check refuses that ticket alone, and the
         refusal is the per-ticket checker's own.
      4. the lock is held by another session: every ticket that had probes is refused, nothing is edited, no
         queue place of ours is left behind.
      5. the many-ticket scan returns, per id, exactly what the one-ticket scan returns.
      6. archive.ps1 with three ids end to end: one acquire line, three archived, probes gone.
      7. bulk-update.ps1 with three ids end to end: one acquire line, three statuses moved, probes gone.
      8. update.ps1 with ONE id end to end (the single-ticket path, now the same batch with one id): one acquire line,
         only that ticket's probes removed, the status moved.
      9. Invoke-ProbeRemovalOnExit, the one-id wrapper: a failing remover throws and the probe stays (its success path is case 8).

    The remover in cases 1-4 is a function of this file named by probes.removeCommand; in cases 6-7 it is an
    inline expression, because those run in a child process that has no such function. Identity variables are
    set for the run and restored afterwards.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$harness = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\harness'))
$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    $caseWatch = [Diagnostics.Stopwatch]::StartNew()
    try { & $Body; $script:passed++; Write-Host ('PASS ({0:N1} s)' -f $caseWatch.Elapsed.TotalSeconds) -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$base = Join-Path ([IO.Path]::GetTempPath()) ('probe-batch-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$rootA = Join-Path $base 'a'     # in-process cases
$rootB = Join-Path $base 'b'     # archive.ps1 child
$rootC = Join-Path $base 'c'     # bulk-update.ps1 child
$rootD = Join-Path $base 'd'     # update.ps1 child (one id)
$saved = @{}
foreach ($name in 'SZA_PROJECT_ROOT', 'SZA_PROFILE_PATH', 'CLAUDE_CODE_SESSION_ID', 'SZA_AGENT_ID', 'FMS_AGENT_ID', 'FMS_SKIP_RELEASE_QUEUE', 'SZA_SKIP_RELEASE_QUEUE') {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name)
}

function New-Fixture([string] $Root, [string] $RemoveCommand, [string[]] $Statuses) {
    New-Item -ItemType Directory -Path (Join-Path $Root 'src') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Root 'PLAN') -Force | Out-Null
    $profile = [ordered]@{
        version = '1'; projectName = 'probe-batch-test'; envPrefix = 'SZA'
        probes  = [ordered]@{ removeOnExit = $true; removeCommand = $RemoveCommand }
    }
    [IO.File]::WriteAllText((Join-Path $Root '.sza-profile.json'), ($profile | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    # Two files; S0001 and S0002 share one, S0003 has the other, and S0002 also has a second probe.
    $a = @('package a', 'fun f() {', '    Timber.d("S0001: first")', '    keep()', '    Timber.d("S0002: second")', '    Timber.d("S0002: again")', '}')
    $b = @('package b', 'fun g() {', '    Timber.d("S0003: third")', '    keep()', '}')
    [IO.File]::WriteAllLines((Join-Path $Root 'src\A.kt'), $a)
    [IO.File]::WriteAllLines((Join-Path $Root 'src\B.kt'), $b)
    $rows = @()
    $n = 0
    foreach ($id in 'S0001', 'S0002', 'S0003') {
        $status = $Statuses[$n]; $n++
        $slug = "ticket-$($id.ToLower())"
        [IO.File]::WriteAllText((Join-Path $Root "PLAN\${id}_$slug.md"), "# ${id}_$slug`n`n**Status:** $status`n", [Text.UTF8Encoding]::new($false))
        $rows += ([ordered]@{ id = $id; name = $slug; status = $status; priority = 50; file = "PLAN/${id}_$slug.md"; created = '2026-11-01 10:00'; updated = '2026-11-01 10:00' } | ConvertTo-Json -Compress)
    }
    [IO.File]::WriteAllLines((Join-Path $Root 'PLAN\spec-catalog.jsonl'), $rows)
}

function Get-ProbeLines([string] $Root) {
    # Returned as one array object (the comma), so an empty result is an empty array, not $null -
    # under strict mode `$null.Count` is an error.
    $found = @(Get-ChildItem -LiteralPath (Join-Path $Root 'src') -Filter '*.kt' | ForEach-Object { Get-Content -LiteralPath $_.FullName } | Where-Object { $_ -match 'Timber\.d\("S\d{4}:' })
    return ,$found
}
function Test-CodeLockHeld([string] $Root) {
    $f = Get-ChildItem -LiteralPath $Root -Recurse -Filter 'CODE.MAIN.LOCK' -ErrorAction SilentlyContinue | Select-Object -First 1
    return ($null -ne $f)
}
function Get-InfoText($Items) {
    @($Items | Where-Object { $_ -is [Management.Automation.InformationRecord] } | ForEach-Object { [string]$_.MessageData })
}

try {
    $env:CLAUDE_CODE_SESSION_ID = $null; $env:FMS_AGENT_ID = $null; $env:SZA_AGENT_ID = 'probe-batch-mine'
    $env:SZA_PROFILE_PATH = $null; $env:FMS_SKIP_RELEASE_QUEUE = '1'; $env:SZA_SKIP_RELEASE_QUEUE = '1'

    # ---- end-to-end children, started first so they run while the in-process cases do ----------------------------------
    # archive.ps1 and bulk-update.ps1 are the two callers of the batch; each runs in its own scratch root in its own
    # process, and the cases at the bottom only read what they left. Each child is a one-line wrapper script (not
    # -Command): Start-Process does not quote its argument list.
    $inline = 'foreach ($f in Get-ChildItem src -Filter *.kt) { $k = @(Get-Content $f.FullName | Where-Object { $_ -notmatch (''"{Id}:'') }); [IO.File]::WriteAllLines($f.FullName, $k) }'
    function Start-Child([string] $Root, [string] $Name, [string] $Line) {
        $wrapper = Join-Path $base "$Name.ps1"
        [IO.File]::WriteAllText($wrapper, ($Line + "`nexit `$LASTEXITCODE`n"), [Text.UTF8Encoding]::new($false))
        $outFile = Join-Path $base "$Name.out"
        $env:SZA_PROJECT_ROOT = $Root
        try {
            $proc = Start-Process pwsh -ArgumentList @('-NoProfile', '-File', $wrapper) -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError "$outFile.err"
        }
        finally { $env:SZA_PROJECT_ROOT = $null }
        [pscustomobject]@{ proc = $proc; out = $outFile }
    }
    function Wait-Child($Child) {
        if (-not $Child.proc.WaitForExit(30000)) { $Child.proc.Kill($true); throw 'the child run did not finish in 30 s' }
        $text = (Get-Content -LiteralPath $Child.out -Raw) + (Get-Content -LiteralPath "$($Child.out).err" -Raw)
        [pscustomobject]@{ code = $Child.proc.ExitCode; output = $text }
    }
    New-Fixture $rootB $inline @('BlockNeedUserTest', 'BlockNeedUserTest', 'BlockNeedUserTest')
    New-Fixture $rootC $inline @('BlockNeedUserTest', 'BlockNeedUserTest', 'BlockNeedUserTest')
    $childArchive = Start-Child $rootB 'child-archive' ("& '{0}' -Id S0001,S0002,S0003" -f (Join-Path $harness 'spec_catalog\archive.ps1'))
    New-Fixture $rootD $inline @('BlockNeedUserTest', 'BlockNeedUserTest', 'BlockNeedUserTest')
    $childUpdate = Start-Child $rootD 'child-update' ("& '{0}' -Id S0001 -Status Implemented" -f (Join-Path $harness 'spec_catalog\update.ps1'))
    $childBulk = Start-Child $rootC 'child-bulk' ("& '{0}' -Id S0001,S0002,S0003 -Status Implemented" -f (Join-Path $harness 'spec_catalog\bulk-update.ps1'))
    # ---- in-process fixture: the remover is a function of this file -----------------------------------------------
    $script:removerCalls = [System.Collections.Generic.List[object]]::new()
    $script:failFor = ''
    $script:leaveFor = ''
    function Remove-TestProbe([string] $Id) {
        $script:removerCalls.Add([pscustomobject]@{ id = $Id; lockHeld = (Test-CodeLockHeld $rootA) })
        if ($Id -eq $script:failFor) { $global:LASTEXITCODE = 1; Write-Output "remover refused $Id"; return }
        if ($Id -eq $script:leaveFor) { $global:LASTEXITCODE = 0; return }
        foreach ($f in Get-ChildItem -LiteralPath (Join-Path $rootA 'src') -Filter '*.kt') {
            $kept = @(Get-Content -LiteralPath $f.FullName | Where-Object { $_ -notmatch ('"' + $Id + ':') })
            [IO.File]::WriteAllLines($f.FullName, $kept)
        }
        $global:LASTEXITCODE = 0
    }
    New-Fixture $rootA 'Remove-TestProbe -Id {Id}' @('BlockNeedUserTest', 'BlockNeedUserTest', 'BlockNeedUserTest')
    $env:SZA_PROJECT_ROOT = $rootA
    . (Join-Path $harness 'spec_catalog\_lib.ps1')
    . (Get-SzaHarnessScript 'spec_catalog/lib/blockneedusertest-probes.ps1')
    $srcRoots = @(Get-ProbeSourceRoot -RepoRoot $rootA)
    . (Get-SzaHarnessScript 'locks/agent-lock.ps1')

    function Reset-Fixture {
        New-Fixture $rootA 'Remove-TestProbe -Id {Id}' @('BlockNeedUserTest', 'BlockNeedUserTest', 'BlockNeedUserTest')
        $script:removerCalls.Clear(); $script:failFor = ''; $script:leaveFor = ''
    }
    function Invoke-Batch([string[]] $Ids) {
        $all = & { Invoke-ProbeRemovalBatch -Id $Ids -NewStatus 'Archived' } 6>&1
        [pscustomobject]@{
            verdict = @($all | Where-Object { $_ -is [hashtable] })[0]
            info    = Get-InfoText $all
        }
    }

    Run-Case 'S0056: three tickets take one lock, one remover per ticket under it, and end clear' {
        Reset-Fixture
        $r = Invoke-Batch @('S0001', 'S0002', 'S0003')
        Assert-That ($null -ne $r.verdict) 'the batch returned no verdict table'
        foreach ($id in 'S0001', 'S0002', 'S0003') { Assert-That ($null -eq $r.verdict[$id]) "$id was refused: $($r.verdict[$id])" }
        $acquired = @($r.info | Where-Object { $_ -match 'Code domains acquired' })
        $released = @($r.info | Where-Object { $_ -match 'Code domains released' })
        Assert-That ($acquired.Count -eq 1) "expected 1 acquire, saw $($acquired.Count): $($acquired -join ' | ')"
        Assert-That ($released.Count -eq 1) "expected 1 release, saw $($released.Count)"
        Assert-That ($acquired[0] -match '3 tickets \(S0001,S0002,S0003\)') "the lock reason does not name the batch: $($acquired[0])"
        Assert-That ($script:removerCalls.Count -eq 3) "the remover ran $($script:removerCalls.Count) times, expected 3"
        Assert-That (@($script:removerCalls | Where-Object { -not $_.lockHeld }).Count -eq 0) 'a remover ran without the code lock held'
        Assert-That (-not (Test-CodeLockHeld $rootA)) 'the lock is still held after the batch'
        Assert-That ((Get-ProbeLines $rootA).Count -eq 0) "probes remain: $((Get-ProbeLines $rootA) -join ' / ')"
    }

    Run-Case 'S0056: one remover failing refuses that ticket alone' {
        Reset-Fixture; $script:failFor = 'S0002'
        $r = Invoke-Batch @('S0001', 'S0002', 'S0003')
        Assert-That ($null -eq $r.verdict['S0001'] -and $null -eq $r.verdict['S0003']) 'a neighbour of the failed ticket was refused'
        Assert-That ([string]$r.verdict['S0002'] -match "probe remover exited 1") "S0002 verdict: $($r.verdict['S0002'])"
        Assert-That (@($r.info | Where-Object { $_ -match 'Code domains acquired' }).Count -eq 1) 'more than one lock was taken'
        $left = (Get-ProbeLines $rootA) -join ' / '
        Assert-That ($left -match 'S0002: second' -and $left -notmatch 'S0001|S0003') "wrong probes remain: $left"
        Assert-That (-not (Test-CodeLockHeld $rootA)) 'the lock is still held'
    }

    Run-Case 'S0056: a remover that exits 0 and leaves its probe is caught by the post-release check, that ticket alone' {
        Reset-Fixture; $script:leaveFor = 'S0003'
        $r = Invoke-Batch @('S0001', 'S0002', 'S0003')
        Assert-That ($null -eq $r.verdict['S0001'] -and $null -eq $r.verdict['S0002']) 'a cleared ticket was refused'
        Assert-That ([string]$r.verdict['S0003'] -match 'check-probe-absent\.ps1 reported exit 1') "S0003 verdict: $($r.verdict['S0003'])"
    }

    Run-Case 'S0056: a lock held by another session refuses every ticket with probes and edits nothing' {
        Reset-Fixture
        $env:SZA_AGENT_ID = 'probe-batch-other'
        $held = & (Get-SzaHarnessScript 'locks/enter-code-lock.ps1') -Domain 'Code.Main' -Reason 'foreign edit' 6>&1 2>&1
        Assert-That ($LASTEXITCODE -eq 0) "the foreign acquire exited $LASTEXITCODE"
        $env:SZA_AGENT_ID = 'probe-batch-mine'
        try {
            # Control first: a queue place of ours is seen by the check below, and withdrawing it clears it. A queue
            # check that could not fail would pass just as quietly as a clean queue. The place is written directly
            # (the lock script's own queued path costs seconds of console work this file cannot afford).
            $null = New-AgentLockTicketSet -Name 'Code' -Reason 'control' -Domains @('Code.Main')
            Assert-That (@(Get-AgentLockQueue -Name 'Code.Main' | Where-Object { $_.sessionId -eq 'probe-batch-mine' }).Count -eq 1) 'the queue check cannot see a queued place'
            $null = & (Get-SzaHarnessScript 'locks/withdraw-lock-ticket.ps1') -Name 'Code' *>&1

            $r = Invoke-Batch @('S0001', 'S0002', 'S0003')
            foreach ($id in 'S0001', 'S0002', 'S0003') {
                Assert-That ([string]$r.verdict[$id] -match 'held by another session') "$id verdict: $($r.verdict[$id])"
            }
            Assert-That ($script:removerCalls.Count -eq 0) 'a remover ran without the lock'
            Assert-That ((Get-ProbeLines $rootA).Count -eq 4) 'the source was edited without the lock'
            $mine = @(Get-AgentLockQueue -Name 'Code.Main' | Where-Object { $_.sessionId -eq 'probe-batch-mine' })
            if ($mine.Count -ne 0) { throw "a queue place of ours was left behind: $($mine.Count) ticket(s)" }
        }
        finally {
            $env:SZA_AGENT_ID = 'probe-batch-other'
            & (Get-SzaHarnessScript 'locks/exit-code-lock.ps1') *> $null
            $env:SZA_AGENT_ID = 'probe-batch-mine'
        }
    }

    Run-Case 'S0056: Invoke-ProbeRemovalOnExit (one id) throws when the remover fails and leaves that probe' {
        Reset-Fixture; $script:failFor = 'S0001'
        $threw = $null
        try { Invoke-ProbeRemovalOnExit -Id 'S0001' 6>&1 | Out-Null } catch { $threw = $_.Exception.Message }
        Assert-That ($null -ne $threw -and $threw -match 'probe remover exited 1') "no refusal thrown: [$threw]"
        Assert-That ((Get-ProbeLines $rootA) -join ' / ' -match 'S0001: first') 'the probe of the refused ticket was removed'
        Assert-That (-not (Test-CodeLockHeld $rootA)) 'the lock is still held'
    }

    Run-Case 'S0056: the many-ticket scan agrees with the one-ticket scan for every id' {
        Reset-Fixture
        $many = Find-TicketProbesInSource -Id @('S0001', 'S0002', 'S0003', 'S0099') -SourceRoots $srcRoots
        foreach ($id in 'S0001', 'S0002', 'S0003', 'S0099') {
            $one = Test-TicketProbeInSource -Id $id -SourceRoots $srcRoots -All
            $a = @($many[$id] | ForEach-Object { '{0}:{1}:{2}' -f $_.File, $_.Line, $_.LineText }) -join '|'
            $b = @($one.Hits | ForEach-Object { '{0}:{1}:{2}' -f $_.File, $_.Line, $_.LineText }) -join '|'
            Assert-That ($a -eq $b) "$id differs. many: [$a] one: [$b]"
        }
        Assert-That (@($many['S0002']).Count -eq 2) 'S0002 should have two probes'
        Assert-That (@($many['S0099']).Count -eq 0) 'an id with no probe must be a key with no hits'
    }

    # ---- end to end: what the two children left ---------------------------------------------------------------------
    Run-Case 'S0056: archive.ps1 with three ids takes one lock and archives all three' {
        $r = Wait-Child $childArchive
        Assert-That ($r.code -eq 0) "archive.ps1 exited $($r.code): $($r.output)"
        Assert-That ($r.output -match 'ARCHIVED: 3 of 3') "no 3-of-3 summary: $($r.output)"
        $n = ([regex]::Matches($r.output, 'Code domains acquired')).Count
        Assert-That ($n -eq 1) "expected 1 lock acquire, saw ${n}: $($r.output)"
        Assert-That ((Get-ProbeLines $rootB).Count -eq 0) "probes remain: $((Get-ProbeLines $rootB) -join ' / ')"
        Assert-That (-not (Test-CodeLockHeld $rootB)) 'the lock is still held'
        Assert-That ((Get-Content (Join-Path $rootB 'PLAN\spec-catalog-archive.jsonl') -Raw) -match 'S0003') 'S0003 is not in the archive journal'
    }

    Run-Case 'S0056: bulk-update.ps1 with three ids takes one lock and moves all three' {
        $r = Wait-Child $childBulk
        Assert-That ($r.code -eq 0) "bulk-update.ps1 exited $($r.code): $($r.output)"
        $n = ([regex]::Matches($r.output, 'Code domains acquired')).Count
        Assert-That ($n -eq 1) "expected 1 lock acquire, saw ${n}: $($r.output)"
        Assert-That ((Get-ProbeLines $rootC).Count -eq 0) "probes remain: $((Get-ProbeLines $rootC) -join ' / ')"
        $journal = Get-Content (Join-Path $rootC 'PLAN\spec-catalog.jsonl') -Raw
        Assert-That ([regex]::Matches($journal, '"status":"Implemented"').Count -eq 3) "not all three moved: $journal"
        Assert-That (-not (Test-CodeLockHeld $rootC)) 'the lock is still held'
    }

    Run-Case 'S0056: update.ps1 with one id clears only that ticket under one lock and moves its status' {
        $r = Wait-Child $childUpdate
        Assert-That ($r.code -eq 0) "update.ps1 exited $($r.code): $($r.output)"
        $n = ([regex]::Matches($r.output, 'Code domains acquired')).Count
        Assert-That ($n -eq 1) "expected 1 lock acquire, saw ${n}: $($r.output)"
        $left = (Get-ProbeLines $rootD) -join ' / '
        Assert-That ($left -notmatch 'S0001' -and $left -match 'S0002' -and $left -match 'S0003') "wrong probes remain: $left"
        $journal = Get-Content (Join-Path $rootD 'PLAN\spec-catalog.jsonl') -Raw
        Assert-That ($journal -match '"id":"S0001"[^\n]*"status":"Implemented"') "S0001 did not move: $journal"
        Assert-That (-not (Test-CodeLockHeld $rootD)) 'the lock is still held'
    }}
finally {
    foreach ($childName in 'childArchive', 'childBulk', 'childUpdate') {
        $c = Get-Variable -Name $childName -ValueOnly -ErrorAction SilentlyContinue
        if ($c -and -not $c.proc.HasExited) { $c.proc.Kill($true) }
    }
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    if (Test-Path -LiteralPath $base) { Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue }
}

$stopwatch.Stop()
Write-Host ''
Write-Host ("{0} case(s): {1} passed, {2} failed, {3:N1} s" -f $run, $passed, $failed, $stopwatch.Elapsed.TotalSeconds)
if ($failed -gt 0) { exit 1 }
exit 0
