#requires -Version 7.0
<#
.SYNOPSIS
    Fast cases for `pq start -Ticket <key>:<id>` and `pq start -Repo <key>` (S0027) - the dispatcher part.

.DESCRIPTION
    Calls Get-PqRank (lib/rank.ps1) directly with a stub head provider over a hand-built registry and a queue file read
    from a temp file, so no process, no picker and no portfolio root is involved; then runs pq.ps1 as a child for the
    argument checks that end before any worker slot is taken, over a throwaway portfolio root. The real registry and the
    real portfolio root are never read or written. Total time is a few seconds.

      1. Without the new parameters the rank is what it was: the same candidates, and no 'named' key in the result or in
         the rank.result event.
      2. A named ticket runs although its project is under a whole-project hold row of the queue file, and although its
         own ticket row is under hold; the hold lines stay in the queue object; another ticket of the same held project
         is not offered by that rank; a hold row of a different ticket keeps excluding that ticket.
      3. The registry's hold flag and enabled=false, a stop, occupancy and an exclusion still skip the named ticket.
      4. A higher-ranked project does not pre-empt the named ticket and is never asked.
      5. An unknown id, an unknown project: not offered, with a why, and no other ticket offered.
      6. -OnlyRepo ranks only that project and keeps its holds.
      7. Get-PqNamedNotRunReason prefers the loop's own marks; Test-PqStartTarget refuses what it must.
      8. pq.ps1 refuses a malformed -Ticket, an unknown key, -Ticket with -Repo and -MaxTickets above 1 with exit 2 and a
         named error, and takes no worker slot (no run/ folder appears).
#>
[CmdletBinding()]
param([switch] $KeepScratch)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$pq = Join-Path $SourceRoot 'tools\harness\portfolio\pq.ps1'
$lib = Join-Path $SourceRoot 'tools\harness\portfolio\lib'
. (Join-Path $lib 'queue-file.ps1')
. (Join-Path $lib 'rank.ps1')
$pwshExe = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
$swAll = [Diagnostics.Stopwatch]::StartNew()

$run = 0; $passed = 0; $failed = 0
function Assert-That([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Run-Case([string] $Name, [scriptblock] $Body) {
    $script:run++
    Write-Host -NoNewline "CASE  $Name ... "
    try { & $Body; $script:passed++; Write-Host 'PASS' -ForegroundColor Green }
    catch { $script:failed++; Write-Host 'FAIL' -ForegroundColor Red; Write-Host "      $($_.Exception.Message)" -ForegroundColor DarkRed }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('pq-named-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null
$savedRoot = $env:SZA_PORTFOLIO_ROOT

try {
    # ---- the registry, the queue file and the stub provider ----
    function New-Repo([string] $Key, [int] $Rank, [bool] $Enabled = $true, [bool] $Hold = $false) {
        [pscustomobject]@{ key = $Key; path = (Join-Path $scratch $Key); enabled = $Enabled; hold = $Hold; rank = $Rank; concurrent = $false; maxWorkers = 1 }
    }
    $registry = [pscustomobject]@{
        maxWorkers = 3
        repos = @(
            (New-Repo 'alpha' 10), (New-Repo 'beta' 20), (New-Repo 'gamma' 30),
            (New-Repo 'delta' 40 $true $true), (New-Repo 'eps' 50 $false), (New-Repo 'zeta' 60)
        )
    }
    $keys = @($registry.repos | ForEach-Object { $_.key })
    $queuePath = Join-Path $scratch 'PORTFOLIO_QUEUE.md'
    [IO.File]::WriteAllText($queuePath, "# portfolio queue`n`n## 1`n`nalpha:A2  first`nzeta`n`nhold`n`nbeta`ngamma:G2`n")
    $queue = Read-PqQueueFile -Path $queuePath -KnownRepos $keys
    Assert-That (@($queue.rows).Count -eq 2 -and @($queue.held).Count -eq 2 -and @($queue.bad).Count -eq 0) 'the temp queue file did not read as 2 rows and 2 held'

    $tickets = @{ alpha = @('A1', 'A2'); beta = @('B1', 'B2'); gamma = @('G1', 'G2'); delta = @('D1'); eps = @('E1'); zeta = @('Z1') }
    $script:asked = [Collections.Generic.List[string]]::new()
    $script:askedExclude = @{}
    $provider = {
        param($Repo, $Exclude, $ForceId)
        $k = [string]$Repo.key
        $script:asked.Add($k)
        $script:askedExclude[$k] = @($Exclude)
        $mine = @($tickets[$k])
        if ($ForceId) {
            if (@($Exclude) -ccontains $ForceId) { return @{ ok = $true; head = $null; payload = $null; why = 'excluded' } }
            if ($mine -cnotcontains $ForceId) { return @{ ok = $true; head = $null; payload = $null; why = 'notRanked' } }
            return @{ ok = $true; head = @{ id = $ForceId; status = 'Approved'; name = "name-$ForceId"; priority = 50 }; payload = $null; why = $null }
        }
        $first = @($mine | Where-Object { @($Exclude) -cnotcontains $_ }) | Select-Object -First 1
        if ($null -eq $first) { return @{ ok = $true; head = $null; payload = $null; why = $null } }
        return @{ ok = $true; head = @{ id = $first; status = 'Approved'; name = "name-$first"; priority = 50 }; payload = $null; why = $null }
    }
    function Get-Rank([hashtable] $Extra = @{}) {
        $script:asked.Clear(); $script:askedExclude = @{}
        $a = @{ Registry = $registry; Queue = $queue; HeadProvider = $provider; Slots = 1 }
        foreach ($k in $Extra.Keys) { $a[$k] = $Extra[$k] }
        return (Get-PqRank @a)
    }
    function Get-ResultEvent($Rank) { return @($Rank.events | Where-Object { $_.ev -ceq 'rank.result' })[0] }

    # ---- 1. unchanged without the new parameters ----
    Run-Case 'without the new parameters the rank is unchanged and carries no named key' {
        $r = Get-Rank
        $ids = @($r.candidates | ForEach-Object { "$($_.repo):$($_.id)" })
        Assert-That (($ids -join ',') -ceq 'alpha:A2,gamma:G1,zeta:Z1') "candidates were $($ids -join ',')"
        Assert-That ((@($r.skipped | Where-Object { $_.repo -ceq 'beta' -and $_.why -ceq 'heldByQueue' })).Count -eq 1) 'beta is not skipped as heldByQueue'
        Assert-That (-not $r.ContainsKey('named')) 'result has a named key'
        $d = (Get-ResultEvent $r).d
        Assert-That (-not $d.Contains('named') -and -not $d.Contains('heldBypassed')) 'rank.result carries named or heldBypassed'
        Assert-That (($d.Keys -join ',') -ceq 'heads,excluded,autoSkipReasons,fill,ms,queueRows,queueBad') "rank.result keys were $($d.Keys -join ',')"
        $r2 = Get-Rank @{ NamedTicket = '' ; OnlyRepo = '' }
        Assert-That ((@($r2.candidates | ForEach-Object { "$($_.repo):$($_.id)" }) -join ',') -ceq ($ids -join ',')) 'empty new parameters changed the rank'
        Assert-That ((@($r2.skipped | ForEach-Object { "$($_.repo):$($_.why)" }) -join ',') -ceq (@($r.skipped | ForEach-Object { "$($_.repo):$($_.why)" }) -join ',')) 'empty new parameters changed skipped'
    }

    # ---- 2. holds ----
    Run-Case 'a named ticket passes through the whole-project hold row; the row stays; no other ticket of the project' {
        $r = Get-Rank @{ NamedTicket = 'beta:B1' }
        Assert-That (@($r.candidates).Count -eq 1 -and $r.candidates[0].repo -ceq 'beta' -and $r.candidates[0].id -ceq 'B1') 'beta:B1 was not the one candidate'
        Assert-That ($r.named.offered -eq $true -and $r.named.heldBypassed -eq $true -and $r.named.repo -ceq 'beta' -and $r.named.id -ceq 'B1') 'named result wrong'
        $d = (Get-ResultEvent $r).d
        Assert-That ($d.named -ceq 'beta:B1' -and $d.heldBypassed -eq $true) 'rank.result lacks named / heldBypassed'
        Assert-That (@($queue.held).Count -eq 2 -and @($queue.held | Where-Object { $_.repo -ceq 'beta' -and $null -eq $_.id }).Count -eq 1) 'the hold row left the queue object'
        Assert-That (@($r.skipped | Where-Object { $_.why -ceq 'heldByQueue' }).Count -eq 0) 'beta is still skipped as held'
    }
    Run-Case 'the other ticket of the held project is not offered by that rank' {
        $r = Get-Rank @{ NamedTicket = 'beta:B1' }
        Assert-That (@($r.candidates | Where-Object { $_.id -ceq 'B2' }).Count -eq 0) 'B2 was offered'
        Assert-That (@($r.candidates | Where-Object { $_.repo -cne 'beta' }).Count -eq 0) 'another project was offered'
        Assert-That (@($script:asked | Where-Object { $_ -cne 'beta' }).Count -eq 0) 'another project was asked'
    }
    Run-Case 'a named ticket under its own hold row runs; a hold row of another ticket keeps excluding that ticket' {
        $r = Get-Rank @{ NamedTicket = 'gamma:G2' }
        Assert-That (@($r.candidates).Count -eq 1 -and $r.candidates[0].id -ceq 'G2' -and $r.named.heldBypassed -eq $true) 'gamma:G2 did not run through its hold row'
        Assert-That (@($script:askedExclude['gamma']) -cnotcontains 'G2') 'G2 stayed in the exclusion list'
        $r2 = Get-Rank @{ NamedTicket = 'gamma:G1' }
        Assert-That ($r2.candidates[0].id -ceq 'G1' -and $r2.named.heldBypassed -eq $false) 'gamma:G1 reported a bypass it did not use'
        Assert-That (@($script:askedExclude['gamma']) -ccontains 'G2') 'the hold row of G2 no longer excludes G2 for another named ticket'
    }

    # ---- 3. what is not bypassed ----
    Run-Case 'the registry hold flag and enabled=false still skip the named ticket' {
        $r = Get-Rank @{ NamedTicket = 'delta:D1' }
        Assert-That (@($r.candidates).Count -eq 0 -and $r.named.offered -eq $false -and $r.named.why -ceq 'hold') "delta: $($r.named.why)"
        $r = Get-Rank @{ NamedTicket = 'eps:E1' }
        Assert-That (@($r.candidates).Count -eq 0 -and $r.named.why -ceq 'disabled') "eps: $($r.named.why)"
    }
    Run-Case 'a stop, occupancy and an exclusion still skip the named ticket, even in a held project' {
        $r = Get-Rank @{ NamedTicket = 'beta:B1'; Stopped = @('beta') }
        Assert-That (@($r.candidates).Count -eq 0 -and $r.named.why -ceq 'stopped') "stopped: $($r.named.why)"
        $r = Get-Rank @{ NamedTicket = 'beta:B1'; Occupied = @('beta') }
        Assert-That (@($r.candidates).Count -eq 0 -and $r.named.why -ceq 'occupied') "occupied: $($r.named.why)"
        $r = Get-Rank @{ NamedTicket = 'alpha:A1'; Exclude = @('alpha:A1') }
        Assert-That (@($r.candidates).Count -eq 0 -and $r.named.why -ceq 'excluded') "excluded: $($r.named.why)"
        $r = Get-Rank @{ NamedTicket = 'alpha:A1'; TicketBlocked = @{ 'alpha:A1' = 'resource' } }
        Assert-That (@($r.candidates).Count -eq 0 -and $r.named.why -ceq 'excluded') "resource: $($r.named.why)"
    }

    # ---- 4. no pre-emption ----
    Run-Case 'a higher-ranked project does not pre-empt the named ticket and is not asked' {
        $r = Get-Rank @{ NamedTicket = 'zeta:Z1' }
        Assert-That (@($r.candidates).Count -eq 1 -and $r.candidates[0].repo -ceq 'zeta' -and $r.candidates[0].id -ceq 'Z1') 'zeta:Z1 was not the one candidate'
        Assert-That (@($script:asked | Where-Object { $_ -cne 'zeta' }).Count -eq 0) 'another project was asked'
        Assert-That ($r.named.heldBypassed -eq $false) 'heldBypassed set for an unheld project'
        $r2 = Get-Rank @{ NamedTicket = 'alpha:A1' }
        Assert-That ($r2.candidates[0].id -ceq 'A1') 'alpha:A1 was replaced by the queue row alpha:A2'
    }

    # ---- 5. unknown ----
    Run-Case 'an unknown id or project is not offered, with a why, and no other ticket' {
        $r = Get-Rank @{ NamedTicket = 'beta:B9' }
        Assert-That (@($r.candidates).Count -eq 0 -and $r.named.offered -eq $false -and $r.named.why -ceq 'notRanked') "beta:B9 -> $($r.named.why)"
        $r = Get-Rank @{ NamedTicket = 'nope:X1' }
        Assert-That (@($r.candidates).Count -eq 0 -and $r.named.offered -eq $false -and $r.named.why -ceq 'unknownRepo') "nope:X1 -> $($r.named.why)"
        Assert-That ($script:asked.Count -eq 0) 'a provider was asked for an unknown project'
    }
    Run-Case 'a malformed -NamedTicket and -NamedTicket with -OnlyRepo are refused' {
        foreach ($bad in @('alpha', 'alpha:', ':A1', 'alpha: A1')) {
            $threw = $false; try { $null = Get-Rank @{ NamedTicket = $bad } } catch { $threw = $_.Exception.Message -like 'ArgumentInvalid:*' }
            Assert-That $threw "'$bad' was not refused"
        }
        $threw = $false; try { $null = Get-Rank @{ NamedTicket = 'alpha:A1'; OnlyRepo = 'alpha' } } catch { $threw = $_.Exception.Message -like 'ArgumentConflict:*' }
        Assert-That $threw 'both parameters were not refused'
    }

    # ---- 6. repository-only ----
    Run-Case '-OnlyRepo ranks only that project in its own order and keeps every hold' {
        $r = Get-Rank @{ OnlyRepo = 'gamma' }
        Assert-That (@($r.candidates).Count -eq 1 -and $r.candidates[0].repo -ceq 'gamma' -and $r.candidates[0].id -ceq 'G1') 'gamma was not ranked alone at G1'
        Assert-That (@($script:asked | Where-Object { $_ -cne 'gamma' }).Count -eq 0) 'another project was asked'
        Assert-That (@($script:askedExclude['gamma']) -ccontains 'G2') 'the hold row of G2 was dropped'
        $r = Get-Rank @{ OnlyRepo = 'beta' }
        Assert-That (@($r.candidates).Count -eq 0 -and @($r.skipped | Where-Object { $_.repo -ceq 'beta' -and $_.why -ceq 'heldByQueue' }).Count -eq 1) 'the whole-project hold of beta was bypassed'
        $r = Get-Rank @{ OnlyRepo = 'delta' }
        Assert-That (@($r.candidates).Count -eq 0 -and @($r.skipped | Where-Object { $_.repo -ceq 'delta' -and $_.why -ceq 'hold' }).Count -eq 1) 'the registry hold of delta was bypassed'
        $r = Get-Rank @{ OnlyRepo = 'alpha' }
        Assert-That ($r.candidates[0].id -ceq 'A2' -and $r.candidates[0].source -ceq 'queueFile') 'the queue row order of alpha was not kept'
        Assert-That (-not $r.ContainsKey('named') -and -not (Get-ResultEvent $r).d.Contains('named')) 'a repo-only rank carries named'
    }

    # ---- 7. the reason text and the checks ----
    Run-Case 'the not-run reason names the loop mark first, then the rank' {
        $rank = Get-Rank @{ NamedTicket = 'beta:B1'; Occupied = @('beta') }
        $m = @{ xblocked = @{ 'beta:B1' = @{ blocker = 'alpha:A9' } }; transient = @{}; occupied = @{}; exclude = @() }
        Assert-That ((Get-PqNamedNotRunReason -Rank $rank -Key beta -Id B1 -Marks $m) -like '*blocker in another project (alpha:A9)*') 'xblocked mark'
        $m = @{ xblocked = @{}; transient = @{ 'beta:B1' = @{ why = 'deviceLevel' } }; occupied = @{}; exclude = @() }
        Assert-That ((Get-PqNamedNotRunReason -Rank $rank -Key beta -Id B1 -Marks $m) -like '*real hardware*') 'deviceLevel mark'
        $m = @{ xblocked = @{}; transient = @{ 'beta:B1' = @{ why = 'resource' } }; occupied = @{}; exclude = @() }
        Assert-That ((Get-PqNamedNotRunReason -Rank $rank -Key beta -Id B1 -Marks $m) -like '*machine resource*') 'resource mark'
        $m = @{ xblocked = @{}; transient = @{}; occupied = @{ beta = @{ why = 'workerCap' } }; exclude = @() }
        Assert-That ((Get-PqNamedNotRunReason -Rank $rank -Key beta -Id B1 -Marks $m) -like '*worker cap*') 'workerCap mark'
        $m = @{ xblocked = @{}; transient = @{}; occupied = @{ beta = @{ why = 'occupied' } }; exclude = @() }
        Assert-That ((Get-PqNamedNotRunReason -Rank $rank -Key beta -Id B1 -Marks $m) -like '*live owner session*') 'occupied mark'
        $m = @{ xblocked = @{}; transient = @{}; occupied = @{}; exclude = @('beta:B1') }
        Assert-That ((Get-PqNamedNotRunReason -Rank $rank -Key beta -Id B1 -Marks $m) -like '*excluded earlier*') 'exclude mark'
        $m = @{ xblocked = @{}; transient = @{}; occupied = @{}; exclude = @() }
        Assert-That ((Get-PqNamedNotRunReason -Rank $rank -Key beta -Id B1 -Marks $m) -like '*occupied*') 'rank occupied'
        $rank = Get-Rank @{ NamedTicket = 'delta:D1' }
        Assert-That ((Get-PqNamedNotRunReason -Rank $rank -Key delta -Id D1 -Marks $m) -like '*on hold in the registry (pq release delta)*') 'hold text'
        $rank = Get-Rank @{ NamedTicket = 'beta:B9' }
        Assert-That ((Get-PqNamedNotRunReason -Rank $rank -Key beta -Id B9 -Marks $m) -like '*offers no such ticket*') 'notRanked text'
    }
    Run-Case 'Test-PqStartTarget refuses what must not start' {
        foreach ($case in @(
                @{ T = 'alpha'; R = ''; M = 0; N = 'ArgumentInvalid' }, @{ T = 'alpha:'; R = ''; M = 0; N = 'ArgumentInvalid' },
                @{ T = 'nope:S1'; R = ''; M = 0; N = 'UnknownRepoKey' }, @{ T = 'alpha:A1'; R = 'alpha'; M = 0; N = 'ArgumentConflict' },
                @{ T = ''; R = 'nope'; M = 0; N = 'UnknownRepoKey' }, @{ T = 'alpha:A1'; R = ''; M = 5; N = 'ArgumentInvalid' })) {
            $v = Test-PqStartTarget -Registry $registry -Ticket $case.T -Repo $case.R -MaxTickets $case.M
            Assert-That ($v.ok -eq $false -and $v.name -ceq $case.N) "ticket '$($case.T)' repo '$($case.R)' max $($case.M) -> $($v.name)"
        }
        $v = Test-PqStartTarget -Registry $registry -Ticket 'alpha:S0001' -MaxTickets 1
        Assert-That ($v.ok -and $v.named.repo -ceq 'alpha' -and $v.named.id -ceq 'S0001') 'a good -Ticket was refused'
        $v = Test-PqStartTarget -Registry $registry -Ticket 'alpha:a:b'
        Assert-That ($v.ok -and $v.named.id -ceq 'a:b') 'the split is not on the first colon'
        $v = Test-PqStartTarget -Registry $registry -Repo 'beta'
        Assert-That ($v.ok -and $null -eq $v.named) 'a good -Repo was refused'
    }

    # ---- 8. pq.ps1 argument checks, before a worker slot is taken ----
    $portfolio = Join-Path $scratch 'portfolio'
    New-Item -ItemType Directory -Path $portfolio | Out-Null
    $repoRecords = foreach ($k in @('alpha', 'beta')) {
        $root = Join-Path $scratch "r-$k"
        New-Item -ItemType Directory -Path (Join-Path $root 'PLAN') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $root '.sza-profile.json'), '{}')
        [IO.File]::WriteAllText((Join-Path $root 'PLAN\spec-catalog.jsonl'), '')
        [ordered]@{ key = $k; path = $root; enabled = $true; maxWorkers = 1; concurrent = $false; role = 'product'; permissionMode = 'bypassPermissions'; rank = 10 }
    }
    [IO.File]::WriteAllText((Join-Path $portfolio 'repos.json'), (ConvertTo-Json -InputObject ([ordered]@{ schemaVersion = '1.0'; repos = @($repoRecords) }) -Depth 5))
    $env:SZA_PORTFOLIO_ROOT = $portfolio
    $cases = @(
        @{ Name = 'malformed -Ticket'; Args = @('-Ticket', 'alpha'); Err = 'pq: ArgumentInvalid - ' },
        @{ Name = 'unknown key in -Ticket'; Args = @('-Ticket', 'nope:S0001'); Err = 'pq: UnknownRepoKey - ' },
        @{ Name = 'unknown key in -Repo'; Args = @('-Repo', 'nope'); Err = 'pq: UnknownRepoKey - ' },
        @{ Name = '-Ticket with -Repo'; Args = @('-Ticket', 'alpha:S0001', '-Repo', 'alpha'); Err = 'pq: ArgumentConflict - ' },
        @{ Name = '-Ticket with -MaxTickets 5'; Args = @('-Ticket', 'alpha:S0001', '-MaxTickets', '5'); Err = 'pq: ArgumentInvalid - ' }
    )
    foreach ($c in $cases) {
        $c.Out = Join-Path $scratch ("out-" + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.txt')
        $c.ErrFile = $c.Out + '.err'
        $c.Proc = Start-Process -FilePath $pwshExe -PassThru -NoNewWindow -RedirectStandardOutput $c.Out -RedirectStandardError $c.ErrFile `
            -ArgumentList (@('-NoProfile', '-File', $pq, 'start') + $c.Args)
    }
    foreach ($c in $cases) {
        $null = $c.Proc.WaitForExit(30000)
        Run-Case "pq start: $($c.Name) exits 2 with a named error and takes no slot" {
            Assert-That ($c.Proc.HasExited) 'the child did not end within 30 s'
            Assert-That ($c.Proc.ExitCode -eq 2) "exit code $($c.Proc.ExitCode)"
            $err = [IO.File]::ReadAllText($c.ErrFile)
            Assert-That ($err.StartsWith($c.Err)) "stderr was '$($err.Trim())'"
        }
    }
    Run-Case 'no worker slot, no run folder, no log was created by the refused starts' {
        Assert-That (-not (Test-Path (Join-Path $portfolio 'run'))) 'a run/ folder appeared'
        Assert-That (-not (Test-Path (Join-Path $portfolio 'log'))) 'a log/ folder appeared'
    }
}
finally {
    $env:SZA_PORTFOLIO_ROOT = $savedRoot
    if (-not $KeepScratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

$swAll.Stop()
Write-Host ("{0} case(s): {1} passed, {2} failed in {3:N1} s" -f $run, $passed, $failed, $swAll.Elapsed.TotalSeconds)
if ($failed -gt 0) { exit 1 }
exit 0
