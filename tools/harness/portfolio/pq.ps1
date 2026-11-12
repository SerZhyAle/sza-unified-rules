#requires -Version 7.0
<#
.SYNOPSIS
    pq - work the portfolio queue, inspect its logs and manage its repositories.

.DESCRIPTION
    pq register -Path <dir> [-Key <k>] [-Enable] [-PermissionMode <mode>]
                                                   add a repository to the registry (repos.json in the portfolio
                                                   root); it joins disabled unless -Enable, with maxWorkers 1 and
                                                   concurrent false; -PermissionMode (acceptEdits, auto,
                                                   bypassPermissions, manual, dontAsk, plan) is written on its record
    pq list [-Json]                                 the registered repositories
    pq dry-run [-Slots <n>] [-Json] [-All]          the global order and the slot plan; launches and writes nothing
    pq queue [-Init] [-NoOpen]                      open PORTFOLIO_QUEUE.md, synced first: every registered
                                                   repository's queued tickets, new ones added to their project's
                                                   rows, changed and status refreshed, closed ones removed; then
                                                   arranged as pq arrange; -Init writes a first one when none exists
    pq tickets [<repo>] [-NoOpen]                   open a repository's own ticket queue file (PLAN/RELEASE_QUEUE.md
                                                   unless its profile says otherwise); without a key, list every
                                                   registered repository with that file's path
    pq rank [<repo> -Rank <n>] [-Order <k1,k2,..>]  the project order (registry rank ascending, equal ranks in
                                                   array order); with <repo> -Rank set one repository's rank; with
                                                   -Order put the listed projects first in that order, the rest
                                                   after them, and write ranks 10, 20, 30, ..; bare, list it
    pq arrange                                      line PORTFOLIO_QUEUE.md up in the order of work: one package 1,
                                                   the projects by rank, each project's rows in their own order;
                                                   hold is not touched, and the order of work does not change
    pq pin <repo:id>                                put a ticket at the top of the first numbered package
    pq sync [-Path <repository>]                    refresh the portfolio projection, optionally for one repository
    pq hold <repo[:id]>                             move a row under the hold heading
    pq release <repo[:id]>                          remove a row from under hold; a bare key also clears the
                                                    registry hold of that repository (TASK-FLOW rule 41)
    pq agents [-Order <p1,p2,..>] [-Release <p>] [-Json]
                                                   the model providers (openai, anthropic, gemini, zai) and the
                                                   order in which they spend tokens; bare, list them with their
                                                   position, CLI and usage-limit hold; with -Order choose the
                                                   providers and their order (the first works until its limit is
                                                   spent, the next takes over only then) - a provider without a
                                                   record gets the shipped one; with -Release clear a provider's
                                                   limit hold, so it is tried again at once
    pq doctor [-All]                                check the enabled repositories (all with -All); writes nothing
    pq start [-Drain] [-MaxTickets <n>] [-Until <time>] [-Ticket <key:id> | -Repo <key>]
                                                   run one worker; wait when empty, or exit with -Drain; -Until
                                                   ends the run at a clock time (HH:mm, today or tomorrow, or a
                                                   full date and time): no new pass after it, a waiting worker ends
                                                   at once; -Ticket <key:id> runs exactly that ticket whatever its
                                                   rank - one pass through the normal path (occupancy, repository
                                                   lock, lease, resources, provider order), then exit; it never waits
                                                   and never takes another ticket; it passes through the hold lines
                                                   of PORTFOLIO_QUEUE.md that name its project or itself (they stay
                                                   in the file) and nothing else - the registry's hold and enabled
                                                   flags, stops, occupancy, leases and the picker's gates still
                                                   apply; -MaxTickets with it must be 0 or 1; -Repo <key> is a normal
                                                   worker that ranks only that project, every hold kept; neither
                                                   changes the project order or reorders the queue file (each syncs
                                                   its own project's rows only, and runs no discovery); -Ticket and
                                                   -Repo together are refused
    pq stop [-Level drain|pass|halt|kill] [-Kill] [-Worker <n>] [-Repo <key>] [-Agent <name>] [-Ticket <key:id>]
                                                   stop; the level is pass by default (the passes in flight end, then
                                                   the worker stops), drain lets a pass-in-flight ticket go on while it
                                                   moves, halt and kill end the pass at once (every agent record says
                                                   halt none, so halt is a kill that is recorded as a halt); -Kill is
                                                   -Level kill. Without a target every worker stops; with one, only that
                                                   worker, repository (it also stays on hold), agent or ticket. Exit 0
                                                   when the request was recorded, 2 when nothing matched the target,
                                                   3 when no worker is running (no file is written)
    pq pause                                        no worker launches a new pass; passes in flight are not touched
    pq resume                                       undo pause
    pq status [-Json] [-Next]                      workers, today's (the local day) pass outcomes, STOP and pause;
                                                   the rank runs only with -Next, which also prints the next ticket;
                                                   the last line is what waits for the owner -> pq inbox
    pq inbox [-Json]                               what waits for the owner across all projects, read-only: one line
                                                   per kind (count, oldest age, the command that clears it), then the
                                                   tickets with id, age and note; BlockByOtherTask as chain roots
    pq tail [<repo:id>] [-Worker <n>] [-Last <n>]   follow what the agent of a running pass is doing, read from the
                                                   transcript it writes (Claude passes; another agent writes none
                                                   until the pass ends); Ctrl+C leaves, it ends by itself with the pass
    pq log [-Last <n>] [-Repo <key>] [-Ev <name>] [-Json]  recent events across all writers (default 40)
    pq report [-Days <n>] [-Json]                   the last n days (7): passes, outcomes, splits by agent, model,
                                                   complexity and repository (only where n is at least 5), waiting,
                                                   occupancy, resources, stops, robot-filed tickets, limits, log health
                                                   and the open findings
    pq problems [-Days <n>] [-Json]                 the open findings only, severity first, with their evidence
    pq trace <repo:id> [-Json]                      one ticket's events in time order
    pq export [-What runs|events] [-Format jsonl|csv] [-Days <n>]
                                                   the run rows (default) or the events of the window, to stdout
    pq compare [-By canon|plugin|registryHash|profileHash|agent|model|complexity|repo] [-Days <n>] [-Json]
                                                   the run rows of the window split by one field, with n, ok share and a
                                                   verdict between the last two values (better, worse, no evidence)

    start uses registry pollSeconds (60 by default); -PollSeconds overrides it. Each repository needs an
    explicit permissionMode, in its own record or inherited from the registry, before unattended work starts.

    The portfolio root is SZA_PORTFOLIO_ROOT, else %USERPROFILE%\.sza\portfolio.

    Exit codes: 0 done; 1 doctor found a failure; 2 invalid invocation or a named error ('pq: <Name> - <message>'
    on stderr; a malformed -Ticket, an unknown project key and -Ticket with -Repo are refused this way before a worker
    slot is taken); 3 start -Drain ran no pass, or a previous STOP is still draining live workers, or start -Ticket did
    not run its ticket ('pq: ticket <key:id> not run - <reason>' on the console; exit 0 only when its pass ran).
#>
param(
    [string]$Verb,
    [string]$Target,
    [string]$Path,
    [string]$Key,
    [string]$PermissionMode,
    [int]$Slots = -1,
    [switch]$Enable,
    [switch]$All,
    [switch]$Init,
    [switch]$Json,
    [switch]$NoOpen,
    [switch]$Drain,
    [ValidateRange(0, [int]::MaxValue)][int]$MaxTickets = 0,
    [ValidateRange(0, [int]::MaxValue)][int]$PollSeconds = 0,
    [string]$RunnerScript,
    [switch]$Kill,
    [int]$Last = 40,
    [string]$Repo,
    [string]$Ev,
    [string]$Rank,
    [string[]]$Order,
    [string]$Release,
    [ValidateSet('', 'drain', 'pass', 'halt', 'kill')][string]$Level = '',
    [ValidateRange(0, [int]::MaxValue)][int]$Worker = 0,
    [string]$Agent,
    [string]$Ticket,
    [string]$Until,
    [ValidateRange(1, 3650)][int]$Days = 0,
    [string]$By,
    [ValidateSet('', 'jsonl', 'csv')][string]$Format = '',
    [ValidateSet('', 'runs', 'events')][string]$What = '',
    [switch]$Next,
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$lib = Join-Path $PSScriptRoot 'lib'
. (Join-Path $lib 'paths.ps1')
. (Join-Path $lib 'events.ps1')
. (Join-Path $lib 'delivery.ps1')
. (Join-Path $lib 'registry.ps1')
. (Join-Path $lib 'queue-file.ps1')
. (Join-Path $lib 'picker.ps1')
. (Join-Path $lib 'rank.ps1')
. (Join-Path $lib 'ledger-watch.ps1')
. (Join-Path $lib 'xrepo.ps1')
. (Join-Path $lib 'inbox.ps1')
. (Join-Path $lib 'inbox-spool.ps1')
. (Join-Path $lib 'inbox-drain.ps1')
. (Join-Path $lib 'discovery.ps1')
. (Join-Path $lib 'loop.ps1')
. (Join-Path $lib 'agents.ps1')
. (Join-Path $lib 'stop.ps1')
. (Join-Path $lib 'occupancy.ps1')
. (Join-Path $lib 'resources.ps1')
. (Join-Path $lib 'waiting.ps1')
. (Join-Path $lib 'console.ps1')
. (Join-Path $lib 'analysis.ps1')

function Write-PqError([string]$Name, [string]$Message) {
    [Console]::Error.WriteLine("pq: $Name - $Message")
}

# owner.action after a successful write: the verb and the NAMES of the parameters used, never their values.
# Fail-open: a failed event write never changes the exit code.
function Write-PqOwnerAction([string]$VerbName) {
    try {
        $opened = $false
        $cliLog = $null
        if ($null -eq $script:PqDefaultLog) {
            $cliLog = Open-PqLog -Writer cli
            $opened = $true
        }
        $names = @($script:PqBound | Where-Object { $_ -cne 'Verb' })
        $null = Write-PqEvent -Ev 'owner.action' -D ([ordered]@{ verb = $VerbName; args = $names })
        if ($opened -and $null -ne $cliLog) { $null = Close-PqLog -Log $cliLog }
    }
    catch { }
}

function Get-PqRegistryOrFail {
    $read = Read-PqRegistry
    if (-not $read.ok) {
        foreach ($e in @($read.errors)) {
            if ($e.name -ceq 'RegistryMissing') { Write-PqError 'RegistryMissing' "no registry at $($read.path); run 'pq register'" }
            else { Write-PqError $e.name "$($e.where) - $($e.message)" }
        }
        return $null
    }
    return $read
}

function Get-PqQueuePath($Registry) {
    $override = $null
    if ($null -ne $Registry) {
        $paths = Get-PqValue $Registry 'paths'
        if ($null -ne $paths) { $override = Get-PqValue $paths 'portfolioQueue' }
    }
    if ($override) { return (Get-PqPath -Kind queue -Override $override) }
    return (Get-PqPath -Kind queue)
}

function Get-PqKnownKeys($Registry) { return [string[]]@(@($Registry.repos) | ForEach-Object { [string]$_.key }) }

# The registry when one exists (for -KnownRepos and paths.portfolioQueue), else $null.
function Read-PqRegistryIfAny {
    $p = Get-PqPath -Kind registry
    if (-not [IO.File]::Exists($p)) { return $null }
    $read = Read-PqRegistry -Path $p
    if (-not $read.ok) { return $null }
    return $read.registry
}

# ---- verbs ----

function Invoke-PqSync {
    $read = Get-PqRegistryOrFail
    if ($null -eq $read) { return 2 }
    $registry = $read.registry
    $syncKey = ''
    if ($Path) {
        $full = [IO.Path]::GetFullPath($Path)
        $repo = @($registry.repos | Where-Object { (ConvertTo-PqPathKey ([IO.Path]::GetFullPath([string]$_.path))) -ceq (ConvertTo-PqPathKey $full) }) | Select-Object -First 1
        if ($null -eq $repo) { Write-PqError 'UnknownRepoPath' "repository '$full' is not registered"; return 2 }
        $syncKey = [string]$repo.key
    }
    $qp = Get-PqQueuePath $registry
    $result = Sync-PqRegisteredQueues -Path $qp -Registry $registry -Key $syncKey
    if ($result.ok) {
        "pq sync: $($result.added) added, $($result.updated) updated, $($result.removed) removed"
        if (@($result.unreadable).Count -gt 0) {
            Write-PqError 'TicketQueueUnreadable' "no complete ticket queue for: $($result.unreadable -join ', ')"
            return 2
        }
        return 0
    }
    Write-PqError $result.error $result.message
    return 2
}

function Invoke-PqRegister {
    if (-not $Path) { Write-PqError 'ArgumentMissing' 'register needs -Path <dir>'; return 2 }
    $full = if ([IO.Path]::IsPathFullyQualified($Path)) { $Path } else { [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Path)) }
    $a = @{ Path = $full; Enable = $Enable; Log = $true }
    if ($Key) { $a.Key = $Key }
    if ($PermissionMode) { $a.PermissionMode = $PermissionMode }
    $null = Initialize-PqRoot
    $r = Add-PqRepo @a
    if (-not $r.ok) { Write-PqError $r.error $r.message; return 2 }
    if ($r.status -ceq 'already') { "already registered $($r.key)" }
    else { "registered $($r.key)"; Write-PqOwnerAction 'register' }
    return 0
}

function Invoke-PqList {
    $read = Get-PqRegistryOrFail
    if ($null -eq $read) { return 2 }
    if ($Json) { ConvertTo-Json -InputObject $read.document -Depth 64; return 0 }
    foreach ($r in @($read.registry.repos)) {
        '{0}  enabled={1}  hold={2}  rank={3}  maxWorkers={4}  {5}' -f $r.key, $r.enabled.ToString().ToLowerInvariant(),
        $r.hold.ToString().ToLowerInvariant(), $r.rank, $r.maxWorkers, $r.path
    }
    if (@($read.registry.repos).Count -eq 0) { 'no repositories registered' }
    return 0
}

function Invoke-PqQueueWriter([string]$Which) {
    if (-not $Target) { Write-PqError 'ArgumentMissing' "$Which needs a target"; return 2 }
    $read = Get-PqRegistryOrFail
    if ($null -eq $read) { return 2 }
    $known = Get-PqKnownKeys $read.registry
    $qp = Get-PqQueuePath $read.registry
    $null = Open-PqLog -Writer cli
    $r = switch ($Which) {
        'pin' { Add-PqQueuePin -Path $qp -Ticket $Target -KnownRepos $known -Log }
        'hold' { Set-PqQueueHold -Path $qp -Target $Target -KnownRepos $known -Log }
        'release' {
            $t = ConvertTo-PqQueueTarget $Target
            if ($null -ne $t -and -not ($known -ccontains $t.repo)) { @{ ok = $false; changed = $false; error = 'UnknownRepoKey'; message = "no repository '$($t.repo)' in the registry" } }
            else {
                $q = Remove-PqQueueHold -Path $qp -Target $Target -Log
                # A bare key also clears the registry hold (rule 41).
                if ($null -ne $t -and $null -eq $t.id) {
                    $h = Set-PqRepoHold -Key $t.repo -Hold $false -Log
                    if ($h.ok -and $h.changed) { $q = @{ ok = $true; changed = $true; error = $null; message = 'registry hold cleared' } }
                }
                $q
            }
        }
    }
    if (-not $r.ok) {
        $message = if ($r.message) { $r.message } else { $r.error }
        Write-PqError $r.error $message
        return 2
    }
    if ($r.error -ceq 'NotHeld') { "$Target is not held" }
    elseif ($r.changed) { "$Which $Target" }
    else { "$Which $Target - no change" }
    Write-PqOwnerAction $Which
    return 0
}

function Invoke-PqRank {
    $read = Get-PqRegistryOrFail
    if ($null -eq $read) { return 2 }
    $keys = @(@($Order) | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($keys.Count -gt 0 -and ($Target -or $Rank)) { Write-PqError 'ArgumentConflict' 'rank takes either <repo> -Rank <n> or -Order, not both'; return 2 }
    $r = $null
    if ($keys.Count -gt 0) {
        $r = Set-PqRepoOrder -Keys $keys -Log
    }
    elseif ($Target -or $Rank) {
        $value = [long]0
        if (-not $Target -or -not [long]::TryParse($Rank, [ref]$value)) { Write-PqError 'ArgumentMissing' 'rank needs <repo> -Rank <integer>'; return 2 }
        $r = Set-PqRepoRank -Key $Target -Rank $value -Log
    }
    if ($null -ne $r) {
        if (-not $r.ok) { Write-PqError $r.error $r.message; return 2 }
        if ($r.changed) { Write-PqOwnerAction 'rank' }
        $read = Get-PqRegistryOrFail
        if ($null -eq $read) { return 2 }
    }
    $i = 0
    foreach ($o in (Get-PqRepoOrder $read.registry)) {
        $i++
        '{0,2}. {1}  rank={2}' -f $i, $o.key, $o.rank
    }
    if ($i -eq 0) { 'no repositories registered' }
    if ($null -ne $r -and -not $r.changed) { 'rank - no change' }
    return 0
}

function Invoke-PqAgents {
    $read = Get-PqRegistryOrFail
    if ($null -eq $read) { return 2 }
    $names = @(@($Order) | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($names.Count -gt 0 -and $Release) { Write-PqError 'ArgumentConflict' 'agents takes either -Order or -Release, not both'; return 2 }
    if ($Release) {
        $p = Resolve-PqProvider $Release
        if ($null -eq $p) { Write-PqError 'UnknownProvider' "no provider '$Release'"; return 2 }
        $released = Remove-PqAgentHold -Name $p.agent
        Write-PqOwnerAction 'agents'
        if (-not $Json) { if ($released) { "released $($p.id) - its limit hold is cleared" } else { "$($p.id) was not held" } }
    }
    elseif ($names.Count -gt 0) {
        $r = Set-PqAgentOrder -Names $names -Log
        if (-not $r.ok) { Write-PqError $r.error $r.message; return 2 }
        if ($r.changed) { Write-PqOwnerAction 'agents' }
        $read = Get-PqRegistryOrFail
        if ($null -eq $read) { return 2 }
        if (-not $Json -and -not $r.changed) { 'agents - no change' }
    }
    $rows = @(Get-PqProviderStatus -Registry $read.registry)
    if ($Json) { ConvertTo-Json -InputObject $rows -Depth 6; return 0 }
    foreach ($row in ($rows | Sort-Object { if ($_.position -gt 0) { $_.position } else { 99 } })) {
        $pos = if ($row.position -gt 0) { '{0,2}.' -f $row.position } else { ' -' }
        $state = @()
        if ($row.position -eq 0) { $state += 'not in the order' }
        if (-not $row.cliFound) { $state += $row.cliNote }
        if ($row.held) {
            $at = ([DateTimeOffset]::Parse([string]$row.holdUntil)).LocalDateTime.ToString('yyyy-MM-dd HH:mm')
            $state += $(if ($row.holdKind -ceq 'resets') { "usage limit spent, back at $at" } else { "usage limit spent, probed again at $at" })
        }
        '{0} {1,-9} {2,-20} {3}' -f $pos, $row.id, $row.label, ($state -join '; ')
    }
    return 0
}

function Invoke-PqArrange {
    $read = Get-PqRegistryOrFail
    if ($null -eq $read) { return 2 }
    $qp = Get-PqQueuePath $read.registry
    $null = Open-PqLog -Writer cli
    $keys = [string[]]@(Get-PqRepoOrder $read.registry | ForEach-Object { $_.key })
    $r = Sort-PqQueueByRank -Path $qp -ProjectOrder $keys -Log
    if (-not $r.ok) {
        $message = if ($r.message) { $r.message } else { $r.error }
        Write-PqError $r.error $message
        return 2
    }
    if ($r.changed) { "arrange - $($r.moved) rows moved"; Write-PqOwnerAction 'arrange' }
    else { 'arrange - no change' }
    return 0
}

function Invoke-PqQueue {
    $registry = Read-PqRegistryIfAny
    $qp = Get-PqQueuePath $registry
    if ($Init) {
        if ($null -eq $registry) {
            $read = Get-PqRegistryOrFail
            if ($null -eq $read) { return 2 }
            $registry = $read.registry
        }
        $null = Open-PqLog -Writer cli
        $r = Initialize-PqQueueFile -Path $qp -Registry $registry -Log
        if (-not $r.ok) { Write-PqError $r.error $r.message; return 2 }
        if ($r.status -ceq 'exists') { "exists $qp - not changed" } else { "written $qp"; Write-PqOwnerAction 'queue' }
        if (-not $NoOpen -and $r.status -ceq 'written') { Open-PqEditor $qp }
        return 0
    }
    if (-not [IO.File]::Exists($qp)) { Write-PqError 'QueueFileMissing' "run 'pq queue -Init'"; return 2 }
    # Bring the file up to date before the owner sees it: new tickets added, changed and status current, then the rows
    # in the order of work, so the file reads like the project list of PQ Control Panel (rule 44).
    if ($null -ne $registry) {
        $null = Open-PqLog -Writer cli
        $s = Sync-PqRegisteredQueues -Path $qp -Registry $registry -Log
        if (-not $s.ok) { Write-PqError $s.error "sync skipped: $($s.message)" }
        elseif ($s.changed) { "synced $qp - $($s.added) added, $($s.updated) updated, $($s.removed) removed" }
        $keys = [string[]]@(Get-PqRepoOrder $registry | ForEach-Object { $_.key })
        $a = Sort-PqQueueByRank -Path $qp -ProjectOrder $keys -Log
        if (-not $a.ok) { Write-PqError $a.error "arrange skipped: $($a.message)" }
        elseif ($a.changed) { "arranged $qp - $($a.moved) rows moved" }
    }
    if ($NoOpen) { $qp; return 0 }
    Open-PqEditor $qp
    return 0
}

function Open-PqEditor([string]$File) {
    $editor = if ($env:EDITOR) { $env:EDITOR } else { 'notepad' }
    Start-Process -FilePath $editor -ArgumentList @("`"$File`"") | Out-Null
}

# A repository's own ticket queue (TASK-FLOW rule 14), where its plan tool adds new tickets; the sync carries them into
# PORTFOLIO_QUEUE.md. Get-PqTicketQueuePath is in lib/queue-file.ps1.
function Invoke-PqTickets {
    $read = Get-PqRegistryOrFail
    if ($null -eq $read) { return 2 }
    $repos = @($read.registry.repos)
    if (-not $Target) {
        foreach ($r in $repos) {
            $qp = Get-PqTicketQueuePath $r
            '{0}  {1}  {2}' -f $r.key, $(if ([IO.File]::Exists($qp)) { 'file   ' } else { 'MISSING' }), $qp
        }
        if ($repos.Count -eq 0) { 'no repositories registered' }
        return 0
    }
    $repo = @($repos | Where-Object { [string]$_.key -ceq $Target }) | Select-Object -First 1
    if ($null -eq $repo) { Write-PqError 'UnknownRepoKey' "no repository '$Target' in the registry"; return 2 }
    $qp = Get-PqTicketQueuePath $repo
    if (-not [IO.File]::Exists($qp)) { Write-PqError 'TicketQueueMissing' "no ticket queue file at $qp"; return 2 }
    if ($NoOpen) { $qp; return 0 }
    Open-PqEditor $qp
    return 0
}

function Invoke-PqDryRun {
    # Read-only: no log, no root, no registry write, no temp file; the picker runs -NoDrift without its claim switch.
    $read = Get-PqRegistryOrFail
    if ($null -eq $read) { return 2 }
    $registry = $read.registry
    $enabled = @(@($registry.repos) | Where-Object { $_.enabled -eq $true })
    $n = if ($Slots -ge 0) { $Slots } else { [int]$registry.maxWorkers }
    if ($enabled.Count -eq 0) {
        if ($Json) { ConvertTo-Json -InputObject ([ordered]@{ candidates = @(); plan = @(); skipped = @(); excluded = [ordered]@{}; fill = $registry.fill }) -Depth 16 }
        else { "pq dry-run: fill=$($registry.fill) slots=$n enabled=0 candidates=0"; 'no enabled repositories' }
        return 0
    }
    $harness = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $rank = Get-PqNextRank -Registry $registry -HarnessRoot $harness -Slots $n -FirstHead:(-not $All) -CheckXrepo
    if ($Json) {
        ConvertTo-Json -InputObject ([ordered]@{ candidates = $rank.candidates; plan = $rank.plan; skipped = $rank.skipped; excluded = $rank.excluded
                autoSkipReasons = $rank.autoSkipReasons; fill = $rank.fill; heads = $rank.heads; ms = $rank.ms; queueRows = $rank.queueRows; queueBad = $rank.queueBad }) -Depth 16
        return 0
    }
    "pq dry-run: fill=$($rank.fill) slots=$n enabled=$($enabled.Count) candidates=$(@($rank.candidates).Count)"
    $i = 0
    foreach ($c in @($rank.candidates)) {
        $i++
        '{0,2}. {1}:{2}  rule={3}  pri={4}  {5}  {6}' -f $i, $c.repo, $c.id, $c.rule, $c.priority, $c.status, (ConvertTo-PqCut ([string]$c.title) 80)
        if ($i -le 3) { foreach ($a in @($c.alt)) { "      alt $($a.repo):$($a.id) - $($a.why)" } }
    }
    foreach ($p in @($rank.plan)) { "slot $($p.slot): $($p.repo):$($p.id)" }
    foreach ($s in @($rank.skipped)) { "skip $($s.repo) - $($s.why)" }
    foreach ($e in @($rank.events | Where-Object { $_.ev -ceq 'queue.row' })) { "queue row $($e.d.line) - $($e.d.kind): $($e.d.text)" }
    return 0
}

function Test-PqDoctorRepo($Repo, $Out) {
    $k = [string]$Repo.key
    $p = [string]$Repo.path
    $add = { param($v, $check, $detail) $Out.Add("$v $k $check - $detail") }
    if (-not [IO.Directory]::Exists($p)) { & $add 'FAIL' 'path' "$p does not exist"; return }
    & $add 'PASS' 'path' $p
    # stamp: the checks of check-compliance.ps1 that need no canon digest.
    $stampFile = Join-Path $p '.sza-canon.json'
    if (-not [IO.File]::Exists($stampFile)) { & $add 'FAIL' 'stamp' 'no .sza-canon.json' }
    else {
        $stamp = $null
        try { $stamp = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($stampFile)) -DateKind String } catch { }
        if (-not (Test-PqObjectValue $stamp)) { & $add 'FAIL' 'stamp' '.sza-canon.json does not parse as an object' }
        else {
            $missing = @(foreach ($n in @('canon', 'overlay', 'ledgerShape')) { if (-not (Test-PqHasKey $stamp $n)) { $n } })
            $canon = Get-PqValue $stamp 'canon'
            if (Test-PqObjectValue $canon) {
                $missing += @(foreach ($n in @('version', 'coreDigest', 'model')) { if (-not (Test-PqHasKey $canon $n) -or [string]::IsNullOrWhiteSpace([string]$canon.$n)) { "canon.$n" } })
            }
            $carrier = $null
            try { Assert-SzaSchemaCarrier $stamp 'schemaVersion' 'REPO-STAMP' } catch { $carrier = $_.Exception.Message }
            if ($missing.Count -gt 0) { & $add 'FAIL' 'stamp' "missing $($missing -join ', ')" }
            elseif ($carrier) { & $add 'FAIL' 'stamp' $carrier }
            else { & $add 'PASS' 'stamp' "canon $($canon.version)" }
        }
    }
    # profile: R37, ready needs a profile. Read with ConvertFrom-Json, never through _profile.ps1 (one project per process).
    $profileFile = Join-Path $p '.sza-profile.json'
    if (-not [IO.File]::Exists($profileFile)) { & $add 'FAIL' 'profile' 'no .sza-profile.json' }
    else {
        $prof = $null
        try { $prof = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($profileFile)) -DateKind String } catch { }
        if (-not (Test-PqObjectValue $prof)) { & $add 'FAIL' 'profile' '.sza-profile.json does not parse as an object' }
        else {
            $carrier = $null
            try { Assert-SzaSchemaCarrier $prof 'version' 'HARNESS-PROFILE' } catch { $carrier = $_.Exception.Message }
            if ($carrier) { & $add 'FAIL' 'profile' $carrier } else { & $add 'PASS' 'profile' "version $(Get-PqValue $prof 'version' '1.0')" }
        }
    }
    $harness = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $v = Invoke-PqRepoChild -RepoPath $p -Script (Join-Path $harness 'spec_catalog\validate.ps1') -Arguments @() -TimeoutSeconds 300
    if ($v.timedOut) { & $add 'FAIL' 'ledger' 'validate.ps1 timed out' }
    elseif ($v.code -ne 0) {
        $last = @(([string]$v.stdout + [string]$v.stderr) -split '\r?\n' | Where-Object { $_ -match 'FAIL' } | Select-Object -First 1)
        & $add 'FAIL' 'ledger' "validate.ps1 exit $($v.code)$(if ($last.Count) { ': ' + $last[0].Trim() })"
    }
    else { & $add 'PASS' 'ledger' 'validate.ps1 exit 0' }
    # S0041: which workable tickets declare no level the runner recognises - the population that
    # launches the default model (sonnet) until a pass writes their `**Complexity:**` line. Workable =
    # open and not blocked: a Verified, Archived or Block* status never reaches a routing decision, and
    # a ticket whose line the reader accepts is already routed by it. Read-only - the snapshot reads the
    # ledger, the archive and each spec header, and writes nothing. A ledger that does not read whole is
    # skipped here: validate.ps1 above already failed it, and two reports of one defect is how a check
    # gets ignored. The capture default is a recognised level (rule 51), so it is counted beside the
    # list, never folded into it.
    try {
        $snap = Get-PqLedgerSnapshot -RepoPath $p
        if ($snap.complete) {
            $workable = 0
            $capture = 0
            $missing = [Collections.Generic.List[string]]::new()
            foreach ($id in @($snap.tickets.Keys)) {
                $st = [string]$snap.tickets[$id].status
                if (@('Verified', 'Archived') -contains $st -or $st.StartsWith('Block')) { continue }
                $workable++
                $li = Get-PqTicketLevelInfo -RepoPath $p -TicketId ([string]$id)
                if ($li.captureDefault) { $capture++; continue }
                if ($li.level) { continue }
                $missing.Add(('{0} ({1})' -f $id, $li.why))
            }
            $capPart = ''
            if ($capture -gt 0) { $capPart = "; $capture at the capture default" }
            if ($missing.Count -gt 0) {
                $shown = @($missing | Sort-Object) -join ', '
                & $add 'WARN' 'complexity' "no recognised level: $shown$capPart - $($missing.Count) of $workable workable"
            }
            else { & $add 'PASS' 'complexity' "$workable workable, all declared$capPart" }
        }
    }
    catch { & $add 'WARN' 'complexity' "ledger unreadable - $($_.Exception.Message)" }
    # The same three shapes check-compliance.ps1 accepts as a launcher (SZA-FLOW03): the rendered r0.ps1, an
    # r0.cmd, or a root a.ps1 that declares an r0 target - the text is matched, never run. A repository whose
    # launcher is the third shape was reported as having none.
    $launcher = ''
    if ([IO.File]::Exists((Join-Path $p 'r0.ps1'))) { $launcher = 'r0.ps1' }
    elseif ([IO.File]::Exists((Join-Path $p 'r0.cmd'))) { $launcher = 'r0.cmd' }
    elseif ([IO.File]::Exists((Join-Path $p 'a.ps1'))) {
        try { if ([IO.File]::ReadAllText((Join-Path $p 'a.ps1')) -match "'r0'\s*=\s*@\{") { $launcher = 'a.ps1 (r0 target)' } }
        catch { $launcher = '' }
    }
    if ($launcher) { & $add 'PASS' 'launcher' $launcher }
    else { & $add 'WARN' 'launcher' 'no launcher: no r0.ps1 or r0.cmd, and no a.ps1 with an r0 target (init-task-flow.ps1 renders them; the migration of existing repositories is S0016 Phase 09)' }
}

function Invoke-PqDoctor {
    $out = [Collections.Generic.List[string]]::new()
    $read = Read-PqRegistry
    $repos = @()
    if (-not $read.ok) {
        foreach ($e in @($read.errors)) { $out.Add("FAIL registry - $($e.name): $($e.where) $($e.message)") }
    }
    else {
        $out.Add("PASS registry - $(@($read.registry.repos).Count) repositories")
        $repos = @(@($read.registry.repos) | Where-Object { $All -or $_.enabled -eq $true })
    }
    foreach ($r in $repos) { Test-PqDoctorRepo $r $out }
    $registry = if ($read.ok) { $read.registry } else { $null }
    $qp = Get-PqQueuePath $registry
    if (-not [IO.File]::Exists($qp)) { $out.Add("WARN queue - no $qp; run 'pq queue -Init'") }
    else {
        $a = @{ Path = $qp }
        if ($null -ne $registry) { $a.KnownRepos = Get-PqKnownKeys $registry }
        $q = Read-PqQueueFile @a
        if (@($q.bad).Count -gt 0) { $out.Add("WARN queue - $(@($q.bad).Count) bad rows") }
        else { $out.Add("PASS queue - $(@($q.rows).Count) rows, $(@($q.held).Count) held") }
    }
    $out
    $fails = @($out | Where-Object { $_.StartsWith('FAIL ') }).Count
    $warns = @($out | Where-Object { $_.StartsWith('WARN ') }).Count
    "pq doctor: $($repos.Count) repositories, $fails FAIL, $warns WARN"
    if ($fails -gt 0) { return 1 }
    return 0
}

function Invoke-PqStart {
    $read = Get-PqRegistryOrFail
    if ($null -eq $read) { return 2 }
    # S0027: -Ticket <key>:<id> and -Repo <key> are checked before a worker slot is taken; a bad one launches nothing.
    $target = Test-PqStartTarget -Registry $read.registry -Ticket $Ticket -Repo $Repo -MaxTickets $MaxTickets
    if (-not $target.ok) { Write-PqError $target.name $target.message; return 2 }
    # Unattended work needs an explicit permissionMode, in the repository's own record or inherited from the registry,
    # before anything starts (the loop re-checks at every launch); refuse here, before a worker slot is taken.
    $regPerm = [string](Get-PqValue $read.registry 'permissionMode')
    $scope = if ($Repo) { @($read.registry.repos | Where-Object { [string]$_.key -ceq $Repo }) }
             elseif ($Ticket) { @($read.registry.repos | Where-Object { [string]$_.key -ceq (($Ticket -split ':', 2)[0]) }) }
             else { @($read.registry.repos | Where-Object { $_.enabled -eq $true }) }
    foreach ($r in @($scope)) {
        if (-not (Get-PqValue $r 'permissionMode') -and -not $regPerm) {
            Write-PqError 'PermissionModeMissing' "set permissionMode for $($r.key), or at the registry top level, before starting unattended work"
            return 2
        }
    }
    # An open-ended worker runs under a supervisor that starts it again when pq's own code changed (exit 75); a run with a
    # ceiling (-Ticket, -MaxTickets) never ends for that reason. The child of the supervisor is marked and runs the loop.
    if (-not $Ticket -and $MaxTickets -le 0 -and $env:SZA_PQ_SUPERVISED -cne '1') {
        $childArgs = [Collections.Generic.List[string]]::new()
        foreach ($k in $script:PqBound) {
            if ($k -ceq 'Verb') { continue }
            $v = Get-Variable -Name $k -ValueOnly
            if ($v -is [switch]) { if ($v.IsPresent) { $childArgs.Add("-$k") } }
            elseif ($v -is [array]) { $childArgs.Add("-$k"); foreach ($x in $v) { $childArgs.Add([string]$x) } }
            else { $childArgs.Add("-$k"); $childArgs.Add([string]$v) }
        }
        return (Invoke-PqSupervised -Script (Join-Path $PSScriptRoot 'pq.ps1') -Verb $Verb -Arguments @($childArgs))
    }
    $a = @{
        Registry = $read.registry
        Drain = $Drain
        MaxTickets = $MaxTickets
        PollSeconds = $PollSeconds
    }
    if ($Ticket) { $a.OnlyTicket = $Ticket }
    if ($Repo) { $a.OnlyRepo = $Repo }
    if ($RunnerScript) { $a.RunnerScript = $RunnerScript }
    if ($Until) {
        $at = ConvertTo-PqUntil $Until
        if ($null -eq $at) { Write-PqError 'ArgumentInvalid' "-Until '$Until' is not a time (HH:mm, or a date and time)"; return 2 }
        $a.Until = $at
    }
    return (Start-PqLoop @a)
}

# An end time for `pq start -Until`: HH:mm is the next such time (today, or tomorrow when it has passed), anything else is
# read as a date and time. $null when it reads as neither.
function ConvertTo-PqUntil([string]$Text) {
    $t = $Text.Trim()
    if ($t -match '^\d{1,2}:\d{2}$') {
        $span = [timespan]::Zero
        if (-not [timespan]::TryParse($t, [ref]$span) -or $span.TotalHours -ge 24) { return $null }
        $at = [datetime]::Today.Add($span)
        if ($at -le [DateTime]::Now) { $at = $at.AddDays(1) }
        return $at
    }
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse($t, [ref]$parsed)) { return $parsed }
    return $null
}

# TASK-FLOW rule 47. The stop is a file in the portfolio root: STOP for everything, STOP-worker__<n>, STOP-repo__<key>,
# STOP-agent__<name> or STOP-ticket__<key>__<id> for one target; the workers read them. The kill is the dispatcher's own:
# every live worker kills the process tree of the pass it started (Invoke-PqPassChild), then releases that pass's lease.
# The runner's own -Stop -Kill is never called from here: it terminates every headless agent process on the machine,
# whichever repository or instance started it, so it would also kill the local runners' children and every other
# portfolio pass.
function Invoke-PqStop {
    if ($Level -and $Kill -and $Level -cne 'kill') { Write-PqError 'ArgumentConflict' "-Kill is -Level kill, not -Level $Level"; return 2 }
    $level = if ($Level) { $Level } elseif ($Kill) { 'kill' } else { 'pass' }
    $targets = @(@(if ($Worker -gt 0) { 'worker' }) + @(if ($Repo) { 'repo' }) + @(if ($Agent) { 'agent' }) + @(if ($Ticket) { 'ticket' }))
    if ($targets.Count -gt 1) { Write-PqError 'ArgumentConflict' 'stop takes one target: -Worker, -Repo, -Agent or -Ticket'; return 2 }
    $kind = if ($targets.Count -eq 1) { $targets[0] } else { 'all' }

    $registry = Read-PqRegistryIfAny
    $keys = if ($null -ne $registry) { @(Get-PqKnownKeys $registry) } else { @() }
    $target = $null
    $label = 'every worker'
    $workers = @(Get-PqWorkerFiles)
    switch ($kind) {
        'worker' {
            if (-not ($workers | Where-Object { $_.slot -eq $Worker })) { Write-PqError 'NoSuchTarget' "no running worker has slot $Worker"; return 2 }
            $target = [string]$Worker; $label = "worker $Worker"
        }
        'repo' {
            if ($keys -cnotcontains $Repo) { Write-PqError 'UnknownRepoKey' "no repository '$Repo' in the registry"; return 2 }
            $target = $Repo; $label = "repository $Repo"
        }
        'agent' {
            $names = if ($null -ne $registry) { @(@($registry.agents) | ForEach-Object { [string]$_.name }) } else { @() }
            if ($names -cnotcontains $Agent) { Write-PqError 'UnknownAgent' "no agent '$Agent' in the registry"; return 2 }
            $target = $Agent; $label = "agent $Agent"
        }
        'ticket' {
            $parts = $Ticket -split ':', 2
            if ($parts.Count -ne 2 -or -not $parts[1]) { Write-PqError 'ArgumentInvalid' "-Ticket '$Ticket' is not <repo>:<id>"; return 2 }
            if ($keys -cnotcontains $parts[0]) { Write-PqError 'UnknownRepoKey' "no repository '$($parts[0])' in the registry"; return 2 }
            $target = "$($parts[0])__$($parts[1])"; $label = "ticket $Ticket"
        }
    }
    # No run at all: nothing to stop, and no file is written (a file left behind would only be cleared by the next start).
    # A repository stop still sets the registry's hold, which is what a repository stop leaves behind.
    if ($workers.Count -eq 0) {
        if ($kind -ceq 'repo') {
            $h = Set-PqRepoHold -Key $Repo -Hold $true -Log
            Write-PqOwnerAction 'stop'
            "no worker is running; repository $Repo is on hold$(if ($h.ok -and -not $h.changed) { ' already' })"
        }
        else { 'no worker is running - nothing to stop' }
        return 3
    }

    $root = Initialize-PqRoot
    $file = if ($kind -ceq 'all') { Join-Path $root 'STOP' } else { Get-PqPath -Kind stopTarget -StopKind $kind -Target $target }
    $stopObj = [ordered]@{
        level = $level
        by = 'cli'
        at = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        reason = 'owner'
    }
    $stopped = [Collections.Generic.List[string]]::new()
    Invoke-PqStateLock {
        [IO.File]::WriteAllText($file, (($stopObj | ConvertTo-Json)), [Text.Encoding]::UTF8)
    }
    foreach ($w in $workers) {
        if (-not $w.key) { continue }
        $hit = switch ($kind) { 'all' { $true } 'worker' { $w.slot -eq $Worker } 'repo' { $w.repository -ceq $Repo } 'agent' { $w.agent -ceq $Agent } 'ticket' { $w.key -ceq $Ticket } }
        if ($hit) { $stopped.Add($w.key) }
    }
    Write-PqOwnerAction 'stop'
    "stop requested ($level) for $label"
    foreach ($p in $stopped) {
        switch ($level) {
            'kill' { "  killing the pass on $p" }
            'halt' { "  halting the pass on $p (no polite interrupt exists for the agent, so it is ended at once)" }
            'drain' { "  the pass on $p ends, and its ticket goes on while it moves" }
            default { "  finishing the pass on $p" }
        }
    }
    return 0
}

function Invoke-PqPause {
    $new = Set-PqPause
    Write-PqOwnerAction 'pause'
    if ($new) { 'paused - no worker launches a new pass; passes in flight finish (pq resume to continue)' } else { 'already paused' }
    if (@(Get-PqWorkerFiles).Count -eq 0) { '  (no worker is running; the pause waits in the portfolio root until one starts)' }
    return 0
}

function Invoke-PqResume {
    if (Clear-PqPause) { Write-PqOwnerAction 'resume'; 'resumed' } else { 'was not paused' }
    return 0
}

# Follows what the agent of a running pass is doing: the records the Claude Code session of the pass appends to its transcript.
function Invoke-PqTail {
    $read = Get-PqRegistryOrFail
    if ($null -eq $read) { return 2 }
    $workers = @(Get-PqWorkerFiles)
    $w = Get-PqLiveTarget -Workers $workers -Target $Target -Slot $Worker
    if ($null -eq $w) {
        if ($Target -or $Worker -gt 0) { 'no running pass matches that target' } else { 'no pass is running' }
        return 3
    }
    $repoRec = @($read.registry.repos | Where-Object { [string]$_.key -ceq $w.repository }) | Select-Object -First 1
    if ($null -eq $repoRec) { Write-PqError 'UnknownRepoKey' "no repository '$($w.repository)' in the registry"; return 2 }
    if ($w.agent -and $w.agent -cne 'claude') {
        "$($w.key) runs on agent $($w.agent), which writes no transcript while it works; its output is written to the repository's runs folder when the pass ends"
        return 0
    }
    "following $($w.key) (worker $($w.slot)) - Ctrl+C leaves, the pass is not touched"
    $tx = $null
    for ($i = 0; $i -lt 30; $i++) {
        $tx = Get-PqLiveTranscript -Repo $repoRec -TicketId $w.ticket
        if ($tx.ok) { break }
        Start-Sleep -Seconds 1
    }
    if (-not $tx.ok) { "cannot follow yet: $($tx.why)"; return 3 }
    $n = if ($Last -gt 0) { $Last } else { 10 }
    # The first screen: the last n records worth showing, read from the tail of the file.
    $len = [IO.FileInfo]::new($tx.path).Length
    $start = [Math]::Max(0, $len - 131072)
    $first = Read-PqTail -Path $tx.path -Offset $start
    $shown = [Collections.Generic.List[string]]::new()
    $lines = @($first.lines)
    if ($start -gt 0 -and $lines.Count -gt 0) { $lines = $lines[1..($lines.Count - 1)] }
    foreach ($l in $lines) { foreach ($d in @(Format-PqTranscriptRecord $l)) { $shown.Add($d) } }
    $from = [Math]::Max(0, $shown.Count - $n)
    for ($i = $from; $i -lt $shown.Count; $i++) { $shown[$i] }
    $offset = $first.offset
    $carry = $first.carry
    while ($true) {
        Start-Sleep -Seconds 1
        $r = Read-PqTail -Path $tx.path -Offset $offset -Carry $carry
        $offset = $r.offset
        $carry = $r.carry
        foreach ($l in @($r.lines)) { foreach ($d in @(Format-PqTranscriptRecord $l)) { $d } }
        $still = Get-PqLiveTarget -Workers @(Get-PqWorkerFiles) -Target $w.key
        if ($null -eq $still) { 'the pass has ended'; break }
    }
    return 0
}

function Invoke-PqStatus {
    $root = Get-PqRoot
    $stopFile = Join-Path $root 'STOP'
    $stopPresent = [IO.File]::Exists($stopFile)
    $stopLevel = $null
    if ($stopPresent) {
        try {
            $stopObj = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($stopFile, [Text.Encoding]::UTF8)) -DateKind String
            $stopLevel = [string]$stopObj.level
        }
        catch { $stopLevel = 'pass' }
    }

    $workers = [Collections.Generic.List[object]]::new()
    $runDir = Join-Path $root 'run'
    if ([IO.Directory]::Exists($runDir)) {
        $wFiles = [IO.Directory]::GetFiles($runDir, 'worker-*.json')
        [Array]::Sort($wFiles, [StringComparer]::Ordinal)
        foreach ($wf in $wFiles) {
            $fn = [IO.Path]::GetFileNameWithoutExtension($wf)
            $k = [int]($fn.Substring('worker-'.Length))
            try {
                $wObj = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($wf, [Text.Encoding]::UTF8)) -DateKind String
                $p = [int]$wObj.pid
                $alive = Test-PqStateOwner $wObj
                $target = if ($wObj.repository -and $wObj.ticket) { "$($wObj.repository):$($wObj.ticket)" } else { '-' }
                $title = if ($wObj.PSObject.Properties['title']) { [string]$wObj.title } else { '' }
                $seenRaw = if ($wObj.PSObject.Properties['seen']) { [string]$wObj.seen } else { [string]$wObj.since }
                $seenMin = $null
                if ($seenRaw) {
                    $seenDt = [DateTimeOffset]::MinValue
                    if ([DateTimeOffset]::TryParse($seenRaw, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$seenDt)) {
                        $seenMin = [int][Math]::Max(0, [Math]::Floor(([DateTimeOffset]::UtcNow - $seenDt).TotalMinutes))
                    }
                }
                $workers.Add([ordered]@{
                    slot = $k
                    pid = $p
                    alive = $alive
                    target = $target
                    title = $title
                    since = [string]$wObj.since
                    seen = [string]$wObj.seen
                    seenMinutes = $seenMin
                })
            }
            catch { }
        }
    }

    $passesToday = [ordered]@{}
    foreach ($e in @(Read-PqCliEvents -Today | Where-Object { $_.ev -ceq 'pass.end' })) {
        $oc = [string]$e.d.outcome
        if ($passesToday.Contains($oc)) { $passesToday[$oc]++ } else { $passesToday[$oc] = 1 }
    }

    # The rank is the expensive part (it walks every ledger and spec), so it runs only with -Next (S0025).
    $nextCandidate = $null
    $reg = Read-PqRegistryIfAny
    if ($Next -and $null -ne $reg) {
        try {
            $harness = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
            $rank = Get-PqNextRank -Registry $reg -HarnessRoot $harness -Slots 1 -StopAfter 1 -CheckXrepo
            if (@($rank.candidates).Count -gt 0) {
                $nextCandidate = [ordered]@{
                    repo = [string]$rank.candidates[0].repo
                    id = [string]$rank.candidates[0].id
                    status = [string]$rank.candidates[0].status
                    title = [string]$rank.candidates[0].title
                }
            }
        }
        catch { }
    }

    # What waits for the owner, across every registered ledger (S0025): the counts pq inbox reports in full.
    $waiting = [ordered]@{ questions = 0; tests = 0; outside = 0; chain = 0; unbuilt = 0 }
    if ($null -ne $reg) {
        try { $waiting = Get-PqInboxCounts -Rows (Get-PqInboxRows $reg).rows } catch { }
    }

    # The phone inbox spool (S0046): packets sitting in new/ or processing/ - printed only when the inbox root
    # exists, so a machine without the Drive channel sees no line at all.
    $spool = $null
    try { $spool = Get-InboxSpoolAge -Root (Resolve-InboxSpoolRoot '') } catch { }
    # S0047: the drain's half - tickets a packet filed that no drain has decided yet (run or recorded not-run).
    $drain = $null
    try { $drain = Get-InboxDrainSummary -Root (Resolve-InboxSpoolRoot '') } catch { }
    # S0048: the newest build.delivered per project (project, version, age), read-only over the event log.
    $lastBuilds = @()
    try { $lastBuilds = @(Get-PqLastDeliveries) } catch { }
    $targetStops = @(Get-PqStopFiles | Where-Object { $_.kind -cne 'all' })
    $paused = Test-PqPaused

    if ($Json) {
        $res = [ordered]@{
            stop = if ($stopPresent) { @{ present = $true; level = $stopLevel } } else { @{ present = $false } }
            targetStops = @($targetStops | ForEach-Object { [ordered]@{ kind = $_.kind; target = $_.target; level = $_.level } })
            paused = $paused
            workers = $workers
            passesToday = $passesToday
            next = $nextCandidate
            nextRanked = [bool]$Next
            waiting = $waiting
            inboxSpool = $(if ($null -ne $spool) { $spool } else { @{ present = $false; waiting = 0; processing = 0; stale = 0 } })
            inboxDrain = $(if ($null -ne $drain) { $drain } else { @{ present = $false; new = 0; filedWaiting = 0; oldestAge = 'none' } })
            lastBuilds = @($lastBuilds)
        }
        ConvertTo-Json -InputObject $res -Depth 16
        return 0
    }

    "STOP: $(if ($stopPresent) { "present (level=$stopLevel)" } else { 'none' })"
    foreach ($ts in $targetStops) { "STOP of $($ts.kind) $($ts.target): level=$($ts.level)" }
    if ($paused) { 'Paused: yes (pq resume continues)' }
    if ($workers.Count -eq 0) {
        "Workers: none active"
    }
    else {
        "Workers:"
        foreach ($w in $workers) {
            $targetStr = if ($w.title) { "$($w.target) ($($w.title))" } else { $w.target }
            $seenPart = if ($null -ne $w.seenMinutes) { "  last seen $($w.seenMinutes) min ago" } else { '' }
            "  slot {0}  pid={1}  alive={2}  target={3}  since={4}{5}" -f $w.slot, $w.pid, $w.alive.ToString().ToLowerInvariant(), $targetStr, $w.since, $seenPart
        }
    }
    if ($passesToday.Count -eq 0) {
        "Passes today: none"
    }
    else {
        $parts = foreach ($k in $passesToday.Keys) { "$k`: $($passesToday[$k])" }
        "Passes today: $($parts -join ', ')"
    }
    if ($Next) {
        if ($null -ne $nextCandidate) {
            "Next: $($nextCandidate.repo):$($nextCandidate.id) ($($nextCandidate.status)) $($nextCandidate.title)"
        }
        else {
            "Next: none"
        }
    }
    else {
        "Next: (not ranked - pq status -Next runs the rank)"
    }
    if ($spool -and $spool.present -and (($spool.waiting + $spool.processing) -gt 0)) {
        $spoolNote = ''
        if ($spool.stale -gt 0) { $spoolNote = " - $($spool.stale) past the $($script:InboxSpoolAgeThresholdSeconds / 60)m mark, is the watcher running?"; }
        "phone inbox: $($spool.waiting + $spool.processing) unprocessed packet(s) (new $($spool.waiting), processing $($spool.processing), oldest $($spool.oldestAge) in $($spool.oldestStage)/)$spoolNote"
    }
    foreach ($b in @($lastBuilds)) {
        $age = ''
        $ts = [DateTimeOffset]::MinValue
        if ([DateTimeOffset]::TryParse([string]$b.at, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$ts)) {
            $minutes = [int][Math]::Floor(([DateTimeOffset]::UtcNow - $ts).TotalMinutes)
            $age = if ($minutes -lt 60) { "$minutes min ago" } elseif ($minutes -lt 1440) { "$([int][Math]::Floor($minutes / 60)) h ago" } else { "$([int][Math]::Floor($minutes / 1440)) d ago" }
        }
        "delivered: $($b.project) $($b.version)$(if ($age) { " ($age)" }) -> $(Get-PqDeliveryRoot)"
    }
    $inboxFragment = if ($drain -and $drain.present) { "; inbox: $($drain.new) new, $($drain.filedWaiting) filed waiting, oldest $($drain.oldestAge)" } else { '' }
    "waiting for you: questions $($waiting.questions), tests $($waiting.tests), outside $($waiting.outside), chain $($waiting.chain), unbuilt $($waiting.unbuilt)$inboxFragment -> pq inbox"
    return 0
}

# S0025: the owner's inbox, read-only over every registered ledger (the quiz-list reader, lib/inbox.ps1).
function Invoke-PqInbox {
    $read = Get-PqRegistryOrFail
    if ($null -eq $read) { return 2 }
    $registry = $read.registry
    # The rows held under a hold heading of PORTFOLIO_QUEUE.md, so a chain root can print as held.
    $held = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    try {
        $qp = Get-PqQueuePath $registry
        if ([IO.File]::Exists($qp)) {
            $q = Read-PqQueueFile -Path $qp -KnownRepos (Get-PqKnownKeys $registry)
            foreach ($h in @($q.held)) { if ($h.id) { $null = $held.Add("$($h.repo):$($h.id)") } }
        }
    }
    catch { }
    $inbox = Get-PqInbox -Registry $registry -Held $held
    if ($Json) {
        ConvertTo-Json -InputObject $inbox -Depth 12
        return 0
    }
    foreach ($label in $inbox.kinds.Keys) {
        $k = $inbox.kinds[$label]
        '{0,-8} {1,4}  oldest {2,-6}  clear: {3}' -f $label, $k['count'], $k.oldestAge, $k.clear
        if ($label -ceq 'chain') {
            foreach ($r in @($k.roots)) {
                $parts = @()
                if ($r.held) { $parts += 'held' }
                if ($r.note) { $parts += (ConvertTo-PqCut $r.note 40) }
                if ($parts.Count -eq 0) { $parts += $(if ($r.status) { $r.status } else { $r.state }) }
                '  {0} ({1}) frees {2}' -f $r.pair, ($parts -join ', '), $r.freesCount
            }
        }
        foreach ($t in @($k.tickets)) {
            $note = if ($t.note) { '  ' + (ConvertTo-PqCut $t.note 100) } else { '' }
            '  {0}:{1}  p{2}  age {3}{4}' -f $t.repo, $t.id, $t.priority, $t.age, $note
        }
    }
    foreach ($s in @($inbox.skipped)) { [Console]::Error.WriteLine("pq inbox: skipped $s") }
    "pq inbox: {0} waiting across {1} project(s)" -f $inbox.total, $inbox.projects
    return 0
}

function Read-PqCliEvents([switch]$Today) {
    $root = Get-PqRoot
    $logDir = Join-Path $root 'log'
    $events = [Collections.Generic.List[object]]::new()
    if ([IO.Directory]::Exists($logDir)) {
        if ($Today) {
            # "Today" is the local day (S0025); the files stay named by their UTC date (rule 54), and a local day can
            # span two of them, so the neighbouring dates are read too and the events are kept by their own ts.
            $now = [DateTimeOffset]::Now
            $localToday = $now.LocalDateTime.Date
            $dates = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($d in -1, 0, 1) { $null = $dates.Add($now.AddDays($d).UtcDateTime.ToString('yyyy-MM-dd')) }
            foreach ($date in $dates) {
                foreach ($f in [IO.Directory]::GetFiles($logDir, 'events-' + $date + '.*.jsonl')) {
                    foreach ($e in (Read-PqDay -Path $f).events) {
                        $ts = [DateTimeOffset]::MinValue
                        if ([DateTimeOffset]::TryParse([string]$e.ts, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$ts) -and $ts.LocalDateTime.Date -eq $localToday) {
                            $events.Add($e)
                        }
                    }
                }
            }
        }
        else {
            foreach ($f in [IO.Directory]::GetFiles($logDir, 'events-*.jsonl')) {
                foreach ($e in (Read-PqDay -Path $f).events) { $events.Add($e) }
            }
        }
    }
    # Files are grouped by writer. Last N means chronological order across every writer.
    return @($events | Sort-Object ts, wr, seq)
}

function Invoke-PqLog {
    $events = @(Read-PqCliEvents | Where-Object {
        (-not $Repo -or $_.repo -ceq $Repo) -and (-not $Ev -or $_.ev -ceq $Ev)
    })

    $n = if ($Last -gt 0) { $Last } else { 40 }
    $selected = if ($events.Count -gt $n) { $events[($events.Count - $n)..($events.Count - 1)] } else { $events }

    if ($Json) {
        ConvertTo-Json -InputObject @($selected) -Depth 16
        return 0
    }

    foreach ($e in $selected) {
        $target = if ($e.repo) { "$($e.repo):$($e.id) " } else { '' }
        $dStr = if ($null -ne $e.d) { ConvertTo-Json -InputObject $e.d -Compress } else { '{}' }
        '{0}  {1,-15}  wr={2}  {3}{4}' -f $e.ts, $e.ev, $e.wr, $target, $dStr
    }
    return 0
}

# ---- analysis (S0016 R44-R48, METRICS.md): read-only views over runs.jsonl and the event files ----

function Format-PqShare($Stats) {
    if ($Stats.Contains('note')) { return "n=$($Stats.n) - $($Stats.note)" }
    return ('n={0} moved {1}% ok {2}% minutes p50 {3} p90 {4}' -f $Stats.n, $Stats.movedShare, $Stats.okShare, $Stats.minutesP50, $Stats.minutesP90)
}

function Format-PqFinding($F) {
    $ev = if (@($F.evidence).Count -gt 0) { '  evidence: ' + (@($F.evidence) -join ' ') } else { '' }
    return ('{0} [{1}] -> {2}: {3} (value {4}, threshold {5}){6}' -f $F.fid, $F.severity, $F.target, $F.text, $F.value, $F.threshold, $ev)
}

function Invoke-PqReport {
    $d = if ($Days -gt 0) { $Days } else { 7 }
    # S0037: each registered repository's own R0 journal (runs-mono.jsonl), reported apart as outside pq.
    $sources = [Collections.Generic.List[object]]::new()
    $reg = Read-PqRegistryIfAny
    if ($null -ne $reg) {
        foreach ($repo in @($reg.repos)) {
            try { $sources.Add(@{ repo = [string]$repo.key; path = (Join-Path (Get-PqRepoPaths -RepoPath ([string]$repo.path)).RunsDir 'runs-mono.jsonl') }) }
            catch { $sources.Add(@{ repo = [string]$repo.key; why = $_.Exception.Message }) }
        }
    }
    $r = Get-PqReport -Root (Get-PqRoot) -Days $d -Standalone @($sources)
    if ($Json) { ConvertTo-Json -InputObject $r -Depth 12; return 0 }
    "pq report - last $($r.window.days) day(s), since $($r.window.since)"
    $h = $r.headline
    if ($h.n -eq 0) { 'no passes in the window' }
    else { "passes $($h.n)  moved $($h.moved) ($($h.movedShare)%)  ok $($h.ok) ($($h.okShare)%)  wall $($h.hours) h  minutes p50 $($h.minutesP50) p90 $($h.minutesP90)" }
    if ($r.outcomes.Count -gt 0) { 'outcomes: ' + (@($r.outcomes.Keys | ForEach-Object { "$_ $($r.outcomes[$_])" }) -join ', ') }
    if ($r.statuses.ended.Count -gt 0) {
        'ended in: ' + (@($r.statuses.ended.Keys | ForEach-Object { "$_ $($r.statuses.ended[$_])" }) -join ', ')
        foreach ($agent in $r.statuses.byAgent.Keys) {
            $counts = $r.statuses.byAgent[$agent]
            "  ${agent}: " + (@($counts.Keys | ForEach-Object { "$_ $($counts[$_])" }) -join ', ')
        }
    }
    'entered / left:'
    foreach ($status in $r.statuses.gates.Keys) {
        $counts = $r.statuses.gates[$status]
        "  ${status}: $($counts.entered) / $($counts.left)"
    }
    if ($r.built.Count -gt 0) {
        'closed unbuilt (self-reported "not built, not tested until the release"; unknown = no disclosure, not a build):'
        foreach ($k in $r.built.Keys) { $b = $r.built[$k]; "  {0,-18} closing {1}  unbuilt {2}  unknown {3}" -f $k, $b.closing, $b.unbuilt, $b.unknown }
    }
    $ut = $r.usage.total
    if ($ut.passes -gt 0) {
        # Nothing recorded and nothing priced print as unknown, never as a zero.
        $fmtUsage = { param($t)
            if ($t.withUsage -eq 0) { return "usage unknown (no usage recorded)" }
            $cost = if ($t.priced -gt 0) { "list-price estimate `${0} over {1} priced pass(es)" -f $t.costUsd, $t.priced } else { 'list-price estimate unknown' }
            "tokens in {0} out {1} cache read {2} write {3}  {4}; no usage {5}, incomplete {6}, unpriced {7}" -f $t.input, $t.output, $t.cacheRead, $t.cacheWrite, $cost, ($t.passes - $t.withUsage), $t.incomplete, $t.unpriced }
        'usage (an estimate at list price, not an invoice): ' + (& $fmtUsage $ut)
        foreach ($split in @(@('repository', $r.usage.byRepo), @('model', $r.usage.byModel), @('outcome', $r.usage.byOutcome))) {
            "  by $($split[0]):"
            foreach ($k in $split[1].Keys) { "    {0,-18} passes {1}  {2}" -f $k, $split[1][$k].passes, (& $fmtUsage $split[1][$k]) }
        }
    }
    $o = $r.outsidePq
    if ($o.headline.n -gt 0 -or @($o.unreadable).Count -gt 0) {
        "outside pq ($($o.source)): passes $($o.headline.n)  moved $($o.headline.moved)  ok $($o.headline.ok)"
        foreach ($k in $o.byRepo.Keys) { "  {0,-18} {1}" -f $k, (Format-PqShare $o.byRepo[$k]) }
        if ($o.statuses.ended.Count -gt 0) { '  ended in: ' + (@($o.statuses.ended.Keys | ForEach-Object { "$_ $($o.statuses.ended[$_])" }) -join ', ') }
        foreach ($u in @($o.unreadable)) { "  unreadable $($u.repo): $($u.why)" }
    }
    foreach ($field in @('agent', 'model', 'complexity', 'repo')) {
        $split = $r["by_$field"]
        if ($split.Count -eq 0) { continue }
        "by ${field}:"
        foreach ($k in $split.Keys) { "  {0,-18} {1}" -f $k, (Format-PqShare $split[$k]) }
    }
    $w = $r.waiting
    "waiting: $($w.waits) wait(s), $($w.pollChanges) change(s) seen, polls $($w.polls) (reranks $($w.reranks), skipped unchanged $($w.skippedUnchanged))"
    if ($r.occupied.Count -gt 0) { 'occupied by the owner: ' + (@($r.occupied.Keys | ForEach-Object { "$_ x$($r.occupied[$_])" }) -join ', ') }
    "resources: acquired $($r.resources.acquired), waited $($r.resources.waited), device-level tickets skipped $($r.resources.deviceSkipped)"
    if ($r.stops.Count -gt 0) { 'stops: ' + (@($r.stops.Keys | ForEach-Object { "$_ x$($r.stops[$_])" }) -join ', ') }
    "robot-filed tickets: $($r.intake.robotFiled) (capped $($r.intake.capped))"
    "limits: pass limits $($r.limits.passLimits), holds $($r.limits.holds), resumes $($r.limits.resumes), fallbacks $($r.limits.fallbacks)"
    "log: $($r.telemetry.events) events, $($r.telemetry.logErrors) log.error, $($r.telemetry.runErrors) run.error, $($r.telemetry.seqGaps) seq gap(s), $($r.telemetry.unparsable) unparsable"
    if (@($r.findings).Count -eq 0) { 'findings: none' }
    else { 'findings:'; foreach ($f in $r.findings) { '  ' + (Format-PqFinding $f) } }
    return 0
}

function Invoke-PqProblems {
    $d = if ($Days -gt 0) { $Days } else { 7 }
    $w = Get-PqWindow $d
    $root = Get-PqRoot
    $runs = @(Read-PqRuns -Root $root -Since $w.since)
    $ev = Read-PqWindowEvents -Root $root -Since $w.since
    $f = @(Get-PqFindings -Runs $runs -Events @($ev.events) -Gaps $ev.gaps -Bad $ev.bad)
    # The phone inbox spool (S0046): an unprocessed packet past the threshold is a finding the engine cannot see
    # (the spool is not the ledger), printed the way S0025 surfaced the waiting statuses - only when the inbox
    # root exists, so a machine without the Drive channel reports nothing.
    $spoolLines = @()
    $spool = $null
    try { $spool = Get-InboxSpoolAge -Root (Resolve-InboxSpoolRoot '') } catch { }
    if ($spool -and $spool.present -and $spool.stale -gt 0) {
        $spoolLines = @("phone inbox: $($spool.waiting + $spool.processing) packet(s) unprocessed past the $($script:InboxSpoolAgeThresholdSeconds / 60)m mark (oldest $($spool.oldestPacketId) $($spool.oldestAge) in $($spool.oldestStage)/) - run install-inbox-watcher.ps1 or start watch-inbox.ps1 by hand")
    }
    if ($spool -and $spool.present) {
        try {
            $registryRead = Read-PqRegistry -Path (Get-PqPath -Kind registry)
            if ($registryRead.ok) {
                $knownKeys = @($registryRead.registry.repos | ForEach-Object { [string]$_.key })
                foreach ($packet in @(Get-InboxDonePackets -Root (Resolve-InboxSpoolRoot ''))) {
                    $unknown = @($packet.named | Where-Object { $knownKeys -notcontains $_ })
                    if ($unknown.Count -gt 0) {
                        $spoolLines += "phone inbox: packet $($packet.packetId) named unknown project(s) $($unknown -join ', '); filed $($packet.tickets -join ', ') for triage"
                    }
                }
            }
        }
        catch { $spoolLines += "phone inbox: could not inspect filed packets for unknown projects: $($_.Exception.Message)" }
    }
    if ($Json) {
        foreach ($l in $spoolLines) { [Console]::Error.WriteLine($l) }
        ConvertTo-Json -InputObject $f -Depth 8; return 0
    }
    if ($f.Count -eq 0) { foreach ($l in $spoolLines) { $l }; if ($spoolLines.Count -eq 0) { "no open findings in the last $d day(s) ($($runs.Count) passes, $(@($ev.events).Count) events)" }; return 0 }
    foreach ($x in $f) { Format-PqFinding $x }
    foreach ($l in $spoolLines) { $l }
    return 0
}

function Invoke-PqTrace {
    $t = ConvertTo-PqQueueTarget $Target
    if ($null -eq $t -or -not $t.id) { Write-PqError 'ArgumentMissing' 'trace needs <repo:id>'; return 2 }
    $events = @(Get-PqTrace -Root (Get-PqRoot) -Repo $t.repo -Id $t.id)
    if ($Json) { ConvertTo-Json -InputObject $events -Depth 12; return 0 }
    if ($events.Count -eq 0) { "no events for $($t.repo):$($t.id)"; return 0 }
    $lastPass = $null
    foreach ($e in $events) {
        if ($e.pass -and $e.pass -cne $lastPass) { "-- pass $($e.pass)$(if ($e.agent) { " ($($e.agent))" })"; $lastPass = $e.pass }
        $dStr = if ($null -ne $e.d) { ConvertTo-Json -InputObject $e.d -Compress } else { '{}' }
        '{0}  {1,-18} {2}' -f $e.ts, $e.ev, $dStr
    }
    return 0
}

function Invoke-PqExport {
    $d = if ($Days -gt 0) { $Days } else { 7 }
    $what = if ($What) { $What } else { 'runs' }
    $w = Get-PqWindow $d
    $root = Get-PqRoot
    if ($what -ceq 'events') {
        if ($Format -ceq 'csv') { Write-PqError 'ArgumentConflict' 'events are exported as jsonl only'; return 2 }
        foreach ($e in @((Read-PqWindowEvents -Root $root -Since $w.since).events)) { ConvertTo-Json -InputObject $e -Depth 12 -Compress }
        return 0
    }
    $runs = @(Read-PqRuns -Root $root -Since $w.since)
    if ($Format -ceq 'csv') { ConvertTo-PqRunCsv $runs }
    else { foreach ($r in $runs) { ConvertTo-Json -InputObject $r -Depth 6 -Compress } }
    return 0
}

function Invoke-PqCompare {
    $d = if ($Days -gt 0) { $Days } else { 30 }
    $by = if ($By) { $By } else { 'canon' }
    if ($by -cnotin @('canon', 'plugin', 'registryHash', 'profileHash', 'agent', 'model', 'complexity', 'repo')) { Write-PqError 'ArgumentInvalid' "-By '$by' is not a run-row field to split on"; return 2 }
    $w = Get-PqWindow $d
    $runs = @(Read-PqRuns -Root (Get-PqRoot) -Since $w.since)
    $c = Compare-PqRuns -Runs $runs -By $by
    if ($Json) { ConvertTo-Json -InputObject $c -Depth 8; return 0 }
    "pq compare - $($runs.Count) passes in the last $d day(s), split by $by"
    foreach ($g in $c.groups) { '  {0,-24} n={1}  ok {2}%  moved {3}%  minutes p50 {4}' -f $g.value, $g.n, $g.okShare, $g.movedShare, $g.minutesP50 }
    if ($null -ne $c.from) { "verdict $($c.from) -> $($c.to): $($c.verdict)" } else { "verdict: $($c.verdict) (fewer than two values)" }
    return 0
}

# ---- router ----

# Every verb of the INDEX code map; $null marks a verb whose handler a later phase adds.
$verbs = [ordered]@{
    start = { Invoke-PqStart }; stop = { Invoke-PqStop }; status = { Invoke-PqStatus }; inbox = { Invoke-PqInbox }; log = { Invoke-PqLog }
    watch = $null; tail = { Invoke-PqTail }; page = $null; pause = { Invoke-PqPause }; resume = { Invoke-PqResume }
    hold = { Invoke-PqQueueWriter 'hold' }; release = { Invoke-PqQueueWriter 'release' }; pin = { Invoke-PqQueueWriter 'pin' }
    rank = { Invoke-PqRank }; arrange = { Invoke-PqArrange }; agents = { Invoke-PqAgents }
    queue = { Invoke-PqQueue }; sync = { Invoke-PqSync }; tickets = { Invoke-PqTickets }; register = { Invoke-PqRegister }; list = { Invoke-PqList }; 'dry-run' = { Invoke-PqDryRun }
    report = { Invoke-PqReport }; trace = { Invoke-PqTrace }; problems = { Invoke-PqProblems }; export = { Invoke-PqExport }; compare = { Invoke-PqCompare }; analyze = $null; improve = $null
    doctor = { Invoke-PqDoctor }
}

if ($Help -or -not $Verb) {
    Get-Help $PSCommandPath -Detailed | Out-String
    if (-not $Help) { exit 2 }
    exit 0
}
if (-not $verbs.Contains($Verb)) {
    [Console]::Error.WriteLine("pq: unknown verb '$Verb'. Verbs: $(@($verbs.Keys) -join ' ')")
    exit 2
}
$handler = $verbs[$Verb]
if ($null -eq $handler) {
    [Console]::Error.WriteLine("pq: verb '$Verb' is not available in this build")
    exit 2
}
$script:PqBound = @($PSBoundParameters.Keys)
$code = 2
try {
    $output = @(& $handler)
    $code = $output[-1]
    if ($output.Count -gt 1) { $output[0..($output.Count - 2)] }
}
catch {
    $m = $_.Exception.Message
    $name = if ($m -match '^([A-Za-z]+): ') { $Matches[1] } else { 'Failed' }
    Write-PqError $name $m
    $code = 2
}
finally {
    try { foreach ($h in @($script:PqLogs.Values)) { $null = Close-PqLog -Log $h } } catch { }
}
exit ([int]$code)
