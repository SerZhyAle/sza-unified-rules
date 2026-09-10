<#
.SYNOPSIS
    Drive the release queue one ticket at a time, each in its own fresh Claude Code process.

.DESCRIPTION
    The cheap alternative to /spec-do and /spec-next. Those keep one conversation alive across every
    ticket, so the context only grows and each later ticket is billed against everything the session
    already carries. This script spends one OS process per ticket instead: the child starts with an
    empty context, runs /spec-all for exactly one id, and exits. The process boundary IS the /clear,
    and unlike a /clear nobody can forget to run it.

    Order comes from the same authority the pipeline uses - scripts/spec_catalog/spec-next-preflight.ps1,
    which ranks by PLAN/RELEASE_QUEUE.md (release package ascending, then the owner's line order) and
    applies eligibility, the skip cache and sibling leases. This script never re-derives an order of
    its own; it asks for the next ticket, runs it, and asks again.

    How a run ends does not matter. Verified, still blocked, a hard stop, a timeout, a crashed child -
    each is recorded and the loop moves to the next ticket. A ticket that comes back with the status it
    started with has no autonomous next step left, so it is dropped for the rest of the run rather than
    re-picked forever.

    Two or three instances may run side by side against one working tree, and that is the intended
    way to use it. Each one ranks, takes a ticket and works it alone:

      - The ranking already skips a ticket a live sibling holds, because spec-next-preflight.ps1
        reads the lease store.
      - The window between "I ranked it" and "my child claimed it" is closed from both sides. Before
        the launch, the lease store is re-read: a ticket a sibling now holds is journalled
        claim-lost-before-launch and the loop moves on, so a lost race costs one pwsh call and no
        child at all. After the launch, the child is watched for -ClaimGraceSeconds: a lease whose
        claimedAt predates the child's own start time was written by a sibling, so the child is
        killed with its process tree and the run is journalled claim-lost.
      - Until 2026-09-05 this paragraph put the window at seconds and its cost at one CLI startup,
        and nothing enforced either number. Measured that day: instances a and b took S2578 thirty
        seconds apart, the loser ran 16 minutes of Opus, and its journal row claimed the winner's
        Draft -> Approved transition as its own. The two checks above are what the sentence now
        describes.
      - -StartDelaySeconds staggers instances launched from the same keystroke so they do not rank
        on the same instant.
      - Everything heavier is already serialised by the repository's own locks: gradle waits on
        temp/BUILD.LOCK, a multi-file source edit waits on temp/CODE.LOCK.

    Give each instance its own -Instance name so the journal and the per-ticket logs do not collide.

    What each instance LAUNCHES is the profile's, per instance (S2698). runner.instances maps an
    -Instance name onto a record whose `command`, `argsTemplate` and `headlessMatch` each fall back
    to the shared runner.<field> beside it, so a project declaring no map launches exactly what it
    launched before. The template's substitutions are {prompt}, {permissionMode} and {model}, and
    an element carrying {model} is dropped with the flag before it when no model was chosen. That
    is what lets one instance of three run a different agent or a different model while the other
    two are untouched - the comparison then needs no new journal field, since the run journal is
    already per instance and already records the model.

    Model: chosen per ticket, from the ticket's own shape, by -ModelPolicy tiered (the default). The
    saving in this script comes from the process boundary, not from a weak model, so the strong tier
    is the default and the cheap tiers have to be earned:

      - Opus   - anything that still needs a decision: Draft, Approved, Tactical, In Progress,
                 Partial, Broken, BlockQuestions, or a spec at tier 4 and above. Designing,
                 planning and writing Kotlin against this architecture is where a weak model
                 produces work that has to be redone, which costs more than it saved, and a
                 BlockQuestions run's whole product is the questions it puts to the owner.
      - Sonnet - the code-complete states, Implemented and BlockNeedUserTest, where the run audits
                 a spec against code the tree already carries and the only thing outstanding is a
                 human on a device; and tier 1-3 tickets, the band below the strong tier's own
                 floor. Status is read before tier: a status names what work is left, a tier only
                 names how big it is.
      - Haiku  - never for a whole ticket. It is a lookup tier: a full /spec-all run has to hold a
                 spec, a tactical plan, gate verdicts and a build log at once. Where haiku belongs is
                 inside a session, on the search and doc subagents (CLAUDE.md Rule 31), and that is a
                 property of those agent definitions, not of this script.

    -ModelPolicy shape is the same split re-cut by the SHAPE of the work rather than by the status,
    because for a ticket the queue actually offers, the status does not vary. PLAN/RELEASE_QUEUE.md
    holds everything below Implemented and runner.decisionStatuses lists exactly those, so the first
    test above answers "strong" for every queue ticket and the tier test is never reached; the cheap
    statuses describe RELEASE_READY.md, the file the runner does not take work from. Measured on the
    full run journal, 2026-09-07: 625 runs strong against 65 cheap, and all 65 cheap ones came from
    the two ready-file statuses. Under shape the order is

      1. a status in runner.alwaysStrongStatuses  -> strong (BlockQuestions, whose whole product is
         a set of questions put to the owner),
      2. tier at or above runner.strongTierMin    -> strong,
      3. tier from 1 to runner.shapeCheapTierMax  -> cheap, whatever the status,
      4. anything else                            -> falls through to the tiered order, unchanged.

    Step 4 falls through rather than defaulting to strong on purpose: a ticket with no tier, or with
    a status neither list names, must get exactly what it gets today, or the policy would change
    behaviour where it promised nothing. Step 3 starts at 1 for the same reason - a blank or zero
    tier is not a small ticket, it is an unstated one.

    Pass -ModelPolicy fixed with -Model <name> to override the whole run.

    Stopping: `.\a.ps1 rs`, or this script with -Stop, writes temp/STOP-SPEC-QUEUE and every instance
    finishes the ticket it is on, then stops cleanly; -Stop -Instance b stops one instance only, and
    -Stop -Kill also terminates the headless children instead of letting them finish. Ctrl+C stops
    it immediately and leaves the child's own work durable - every /spec-all writes its status and
    dev-log rows as it goes.

    Exit codes: 0 = the loop ran to a normal end (queue exhausted, -MaxTickets reached, or the stop file
                    appeared),
                2 = invalid invocation - the Claude CLI or the preflight script could not be found or
                    could not be parsed,
                3 = nothing ran - either nothing was eligible at the very first ranking, or a stop
                    is still draining (children from a previous run are alive and the shared stop
                    flag is set), which is a "not now", not a failure.

.EXAMPLE
    pwsh -NoProfile -File scripts/utils/run-spec-queue.ps1
    Work the queue from the top until it is exhausted.

.EXAMPLE
    pwsh -NoProfile -File scripts/utils/run-spec-queue.ps1 -MaxTickets 5 -TimeoutMinutes 45
    Five tickets, forty-five minutes each at most.

.EXAMPLE
    pwsh -NoProfile -File scripts/utils/run-spec-queue.ps1 -Ids "S2014,S2018" -DryRun
    Show what would run for two named tickets, without launching anything.
#>
[CmdletBinding()]
param(
    # Explicit ticket list, comma-separated, run in the order given. Omit to take them from the queue.
    [string] $Ids = '',

    # Stop after this many tickets. 0 means "until the queue is exhausted".
    [int] $MaxTickets = 0,

    # Hard ceiling per ticket. The child is killed with its whole process tree when it overruns.
    [int] $TimeoutMinutes = 90,

    # How the child's model is chosen. 'tiered' reads it off the ticket (see the description);
    # 'fixed' uses -Model for every ticket; 'default' passes nothing and lets the CLI decide.
    [ValidateSet('tiered', 'shape', 'fixed', 'default')]
    [string] $ModelPolicy = 'tiered',

    # The model used when -ModelPolicy is 'fixed'.
    [string] $Model = 'opus',

    # Overrides for the tiered policy, so the split can be retuned without editing the script.
    [string] $StrongModel = 'opus',
    [string] $CheapModel = 'sonnet',

    # Name for this instance when several run in parallel. Keeps journals and per-ticket logs apart.
    [string] $Instance = 'a',

    # Random stagger before the first ranking, so instances launched together do not rank in lockstep.
    [int] $StartDelaySeconds = 0,

    # How long to watch a freshly started child for its lease claim before letting it run unwatched.
    # A lease that appears in this window carrying a claimedAt EARLIER than the child's start time was
    # written by a sibling, so the child lost the race and is killed. Long enough to cover a cold CLI
    # start plus /spec-all stage 0a; 0 disables the watch entirely.
    [int] $ClaimGraceSeconds = 180,

    # The command each child runs. {id} is replaced with the ticket id. Empty = the profile's
    # runner.promptTemplate.
    [string] $PromptTemplate = '',

    # Permission mode for the child session.
    [ValidateSet('acceptEdits', 'auto', 'bypassPermissions', 'manual', 'dontAsk', 'plan')]
    [string] $PermissionMode = 'bypassPermissions',

    # Send the child's output to a per-ticket log file instead of this console. The file is written
    # when the ticket ENDS, not as it runs: the streams are drained into memory so a full pipe can
    # never block the child. For live output, run without -Quiet - it goes straight to this console.
    [switch] $Quiet,

    # Print the plan and exit without launching anything.
    [switch] $DryRun,

    # Ask the running instances to stop after the ticket each is on, then exit. With -Instance it
    # stops that one instance; without it, all of them.
    [switch] $Stop,

    # With -Stop: also kill the running children instead of letting them finish the current ticket.
    # The work already written to disk stays - every /spec-all records status and dev-log rows as it
    # goes - but the ticket in flight is left mid-run and its lease is dropped.
    [switch] $Kill,

    # Skip the skip-cache reset this run normally does at start. The cache accumulates skip verdicts
    # (owner-gate, drift, and transient ones like a held code lock or a dirty tree) from every prior
    # /spec-all child, phone and wear instances alike, and honours the transient reasons unchecked
    # until their TTL - so a lock released or a tree cleaned an hour ago still hides that ticket from
    # today's ranking. Resetting at each run start makes every ticket answer for itself again; anything
    # still genuinely blocked gets re-cached within seconds by the first live preview that finds it.
    [switch] $KeepSkipCache,

    [string] $RepoRoot = '',

    [switch] $Help
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')
. (Join-Path $PSScriptRoot '_idle-runs.ps1')
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = Get-SzaProjectRoot }

if ($Help) {
    Show-SzaHelp $PSCommandPath
    exit $LASTEXITCODE
}

$ErrorActionPreference = 'Stop'
Set-Location $RepoRoot

# ---------------------------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------------------------

if ([string]::IsNullOrWhiteSpace($PromptTemplate)) {
    # The profile spells the placeholder {Id}; this script has always accepted {id}. Both work.
    $PromptTemplate = ([string](Get-SzaProfileValue 'runner.promptTemplate')).Replace('{Id}', '{id}')
}
function Get-InstanceSetting {
    <#
        One field of the child invocation, resolved instance first (S2698). The chain is
        runner.instances.<instance>.<field> -> runner.<field>, and the profile's own defaults sit
        under the second of those - so a project that declares no instances map gets exactly what
        it got before this existed, and an instance absent from a non-empty map does too.
    #>
    param([Parameter(Mandatory)][string] $Field)

    $map = Get-SzaProfileValue 'runner.instances'
    if (Test-SzaHasProperty -Object $map -Name $Instance) {
        $entry = $map.$Instance
        if (Test-SzaHasProperty -Object $entry -Name $Field) { return $entry.$Field }
    }
    return (Get-SzaProfileValue ("runner.{0}" -f $Field))
}

function Expand-ChildArgs {
    <#
        The child's argument vector, from the instance's template (S2698). Substitutions are
        {prompt}, {permissionMode} and {model}, applied per element and BEFORE ArgumentList, so
        escaping stays .NET's job - the property that stopped three tickets being lost to
        Start-Process's unquoted join.
    #>
    param(
        [string[]] $Template,
        [string] $Prompt,
        [string] $Mode,
        [string] $Model
    )

    $out = @()
    foreach ($element in $Template) {
        $text = [string]$element
        if ($text -match '\{model\}' -and [string]::IsNullOrWhiteSpace($Model)) {
            # No model chosen: the placeholder's element goes, and so does the flag in front of it.
            # Passing it through as an empty string is NOT the same thing - ArgumentList hands the
            # child a real empty argument, so `--model ""` would reach a CLI that today sees no
            # --model at all, which is exactly what -ModelPolicy default asks for.
            if ($out.Count -gt 0 -and ([string]$out[-1]).StartsWith('-')) {
                $out = @($out | Select-Object -First ($out.Count - 1))
            }
            continue
        }
        $out += $text.Replace('{prompt}', $Prompt).Replace('{permissionMode}', $Mode).Replace('{model}', $Model)
    }
    # A bare return, not `, $out`: the comma hands the caller a one-element wrapper AROUND the
    # vector, so `@(Expand-ChildArgs ..)` would be one argument holding an array and every child
    # would launch with a single stringified Object[]. Every call site already wraps in @().
    return $out
}

$runnerCommand = [string](Get-InstanceSetting -Field 'command')
$runnerArgsTemplate = @(Get-InstanceSetting -Field 'argsTemplate')
$headlessMatch = [string](Get-InstanceSetting -Field 'headlessMatch')
$claudeCmd = Get-Command $runnerCommand -ErrorAction SilentlyContinue
$claude = if ($claudeCmd) { $claudeCmd.Source } else { $null }
if (-not $claude -and $runnerCommand -eq 'claude') {
    # The fallback is a fact about ONE command - where the Claude CLI installs itself when it is not
    # on PATH - so it is gated on that command being the one asked for. Ungated, an instance pointed
    # at another agent whose CLI is missing would silently launch claude instead, and its journal
    # rows would attribute a week of runs to a provider that never ran: the exact comparison the
    # per-instance command exists to make.
    $fallback = Join-Path $env:USERPROFILE '.local\bin\claude.exe'
    if (Test-Path $fallback) { $claude = $fallback }
}
if (-not $claude) {
    # Name the instance and its command, not just "the CLI": a watchdog restarts a fallen instance
    # on a timer, so an instance pointed at a command this machine does not have would otherwise
    # fail identically and silently every interval, and the queue would lose that instance's share
    # of the throughput with nothing on screen saying which of the three stopped working.
    $where = if ($runnerCommand -eq 'claude') { 'on PATH or at ~/.local/bin/claude.exe' } else { 'on PATH' }
    Write-Host ("run-spec-queue: instance '{0}' asks for command '{1}', which was not found {2}." -f $Instance, $runnerCommand, $where) -ForegroundColor Red
    Write-Host "  Fix the command in .sza-profile.json (runner.instances.$Instance.command, or runner.command)." -ForegroundColor Yellow
    exit 2
}

$preflight = (Get-SzaHarnessScript 'spec_catalog/spec-next-preflight.ps1')
$select = (Get-SzaHarnessScript 'spec_catalog/select.ps1')
$skipCache = (Get-SzaHarnessScript 'spec_catalog/skip-cache.ps1')
$leaseScript = (Get-SzaHarnessScript 'locks/ticket-lease.ps1')
foreach ($required in @($preflight, $select)) {
    if (-not (Test-Path $required)) {
        Write-Host "run-spec-queue: required script missing - $required" -ForegroundColor Red
        exit 2
    }
}

$tempDir = Join-Path $RepoRoot (Get-SzaPath 'tempDir' -Relative)
if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }
$stopFileAll = Join-Path $RepoRoot (Get-SzaPath 'queueStopFile' -Relative)
$stopFileMine = "{0}-{1}" -f $stopFileAll, $Instance
$runDir = Join-Path $RepoRoot (Get-SzaPath 'queueRunsDir' -Relative)
if (-not (Test-Path $runDir)) { New-Item -ItemType Directory -Path $runDir | Out-Null }
$journal = Join-Path $runDir ("runs-{0}.jsonl" -f $Instance)

# ---------------------------------------------------------------------------------------------
# Stop mode - write the flag the running loops read, then leave. Nothing else in this script runs.
# ---------------------------------------------------------------------------------------------

if ($Stop) {
    $target = if ($PSBoundParameters.ContainsKey('Instance')) { $stopFileMine } else { $stopFileAll }
    $scope = if ($PSBoundParameters.ContainsKey('Instance')) { "instance '$Instance'" } else { 'every instance' }
    Set-Content -LiteralPath $target -Value ("stop requested {0}" -f (Get-Date -Format 's')) -Encoding UTF8
    Write-Host ("run-spec-queue: stop requested for {0} - {1}" -f $scope, $target) -ForegroundColor Yellow

    # Name what the stop is waiting for. The flag is only read between tickets, so a stop issued
    # during a 40-minute pipeline does nothing visible for 40 minutes - and silence is indistinguishable
    # from a broken command. Whoever asked for the stop is owed the reason it has not happened yet.
    $inFlight = @((Get-SzaAgentProcesses) |
            Where-Object { $_.CommandLine -and $_.CommandLine -match $headlessMatch })
    if ($inFlight.Count -eq 0) {
        Write-Host '  nothing is running - the next start clears this flag and proceeds.' -ForegroundColor DarkGray
    } else {
        Write-Host ''
        Write-Host ("  {0} ticket(s) still in flight - the stop takes effect when each one ENDS:" -f $inFlight.Count) -ForegroundColor Cyan
        foreach ($c in $inFlight) {
            $age = '?'
            try { $age = '{0:N0}' -f ((Get-Date) - $c.CreationDate).TotalMinutes } catch { $age = '?' }
            $ticket = if ($c.CommandLine -match '(S\d{4})') { $Matches[1] } else { '?' }
            Write-Host ("    pid {0,-7} {1,4} min   ticket {2}" -f $c.ProcessId, $age, $ticket) -ForegroundColor Cyan
        }
        Write-Host ''
        Write-Host '  A full pipeline routinely runs 30-60 minutes, so this is a wait, not a hang.' -ForegroundColor DarkGray
        Write-Host "  Watch it:   $(Get-SzaInvocation 'batch/monitor-spec-queue.ps1')" -ForegroundColor DarkGray
        Write-Host '  Stop now:   .\a.ps1 rs -Kill    (abandons the ticket in flight; what it already wrote stands)' -ForegroundColor DarkGray
    }

    if ($Kill) {
        # Only the children this repository's runs started. A claude process serving the operator's
        # own interactive window must not be killed by a queue command.
        $victims = @((Get-SzaAgentProcesses) |
                Where-Object { $_.CommandLine -and $_.CommandLine -match $headlessMatch })
        if ($victims.Count -eq 0) {
            Write-Host '  -Kill: no headless claude child is running.' -ForegroundColor DarkGray
        } else {
            foreach ($v in $victims) {
                Write-Host ("  -Kill: terminating pid {0}" -f $v.ProcessId) -ForegroundColor Red
                & taskkill.exe /PID $v.ProcessId /T /F 2>&1 | Out-Null
            }
            Write-Host '  the ticket in flight is left mid-run; what it already wrote to disk stands.' -ForegroundColor DarkYellow
        }
    }
    exit 0
}

# A stop file left behind by a previous run would stop this one before it began.
#
# The instance's own file is always cleared - starting this instance is an explicit instruction that
# supersedes an older stop aimed at it.
if (Test-Path $stopFileMine) {
    Write-Host "run-spec-queue: clearing this instance's leftover stop file - $stopFileMine" -ForegroundColor Yellow
    Remove-Item $stopFileMine -Force
}

# The shared file needs the opposite care, and getting it wrong strands the runner in two different
# ways. Nothing deletes it: the loop that reads it must leave it in place so the sibling instances
# see it too, so it outlives the run it stopped - and the NEXT run would then exit at its first check
# having done nothing, which reads exactly like a broken script. But blindly deleting it would let a
# freshly started instance cancel a stop that is still draining the other two.
#
# Live children are what tells the two apart: a stop still in progress has processes behind it.
$liveChildren = @((Get-SzaAgentProcesses) |
        Where-Object { $_.CommandLine -and $_.CommandLine -match $headlessMatch })
if (Test-Path $stopFileAll) {
    if ($liveChildren.Count -gt 0) {
        Write-Host "run-spec-queue: a stop is in progress - $($liveChildren.Count) child process(es) are still finishing." -ForegroundColor Red
        Write-Host "  Wait for them to exit (watch with: $(Get-SzaInvocation 'batch/monitor-spec-queue.ps1'))," -ForegroundColor Red
        Write-Host "  then start again. Starting now would cancel the stop for the instances still draining." -ForegroundColor Red
        exit 3
    }
    Write-Host "run-spec-queue: clearing a stop flag left over from a finished run - $stopFileAll" -ForegroundColor Yellow
    Remove-Item $stopFileAll -Force
}

# ---------------------------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------------------------

function Get-TicketStatus {
    param([string] $Id)
    try {
        $raw = & pwsh -NoProfile -File $select -Id $Id -Format json 2>$null | Out-String
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json).status
    } catch {
        return $null
    }
}

function Get-NextQueuedTicket {
    param([string[]] $Exclude)
    # Never name this $args - PowerShell owns that automatic variable inside every function.
    $pfArgs = @('-NoProfile', '-File', $preflight)
    if ($Exclude.Count -gt 0) { $pfArgs += @('-Exclude', ($Exclude -join ',')) }
    $raw = & pwsh @pfArgs 2>$null | Out-String
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    try {
        $payload = $raw | ConvertFrom-Json
    } catch {
        Write-Host "run-spec-queue: preflight returned output that is not JSON - stopping." -ForegroundColor Red
        return 'PARSE_ERROR'
    }
    if (-not $payload.selected) { return $null }
    return $payload.selected
}

function Get-TicketRecord {
    param([string] $Id)
    try {
        $raw = & pwsh -NoProfile -File $select -Id $Id -Format json 2>$null | Out-String
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Select-ModelFor {
    <#
        The whole decision, in one place. It reads only what the catalog already knows - status and
        tier - so choosing a model costs nothing and never opens the spec.
    #>
    param($Ticket)

    if ($ModelPolicy -eq 'default') { return '' }
    if ($ModelPolicy -eq 'fixed') { return $Model }
    if ($null -eq $Ticket) { return $StrongModel }

    $status = [string]$Ticket.status

    # The two sources spell the tier differently and both are legitimate: select.ps1 returns the
    # integer 2, the preflight ranker returns the label "3 - Moderate (ad-hoc)". A plain TryParse
    # succeeds on the first and fails on the second, leaving tier 0 - so every queue-picked ticket
    # silently missed the cheap tier. Take the leading integer from whichever shape arrives.
    $tier = 0
    if ($null -ne $Ticket.tier -and ([string]$Ticket.tier) -match '^\s*(\d+)') {
        $tier = [int]$Matches[1]
    }

    # SHAPE decides before status, and only under -ModelPolicy shape. The order below is the canon's;
    # the three cut lines are the project's (runner.alwaysStrongStatuses, runner.strongTierMin,
    # runner.shapeCheapTierMax in the profile). The justification for the status-first order that
    # follows holds only while the status distinguishes tickets, and for a ticket taken off the
    # queue it does not: all seven decision statuses give the same answer, so tier is the only
    # signal that varies there. Nothing here returns a default - an uncovered ticket falls through
    # to the tiered order below and gets exactly what it gets today.
    if ($ModelPolicy -eq 'shape') {
        if (@(Get-SzaProfileValue 'runner.alwaysStrongStatuses') -contains $status) { return $StrongModel }

        # The code-complete states are tested BEFORE the strong tier, and this order was set by a
        # measurement rather than by taste. Written the other way round - strong tier first - shape
        # upgraded 12 tier-4 tickets sitting in Implemented and BlockNeedUserTest from cheap to
        # strong while moving only 7 down, so the policy whose entire purpose is to reach the cheap
        # model more often cost MORE than the one it replaces. The reason those states are cheap
        # does not weaken with size: the run audits code the tree already carries, and a big change
        # already made is not a big decision still to take.
        if (@(Get-SzaProfileValue 'runner.cheapStatuses') -contains $status) { return $CheapModel }

        $strongTierMin = [int](Get-SzaProfileValue 'runner.strongTierMin')
        if ($strongTierMin -gt 0 -and $tier -ge $strongTierMin) { return $StrongModel }

        # The floor of 1 excludes a blank or zero tier, which is an unstated size rather than a
        # small one - 6 of the 44 open decision-status tickets carried no tier when this was
        # written, and routing them by absence would be routing them by an author's omission.
        $shapeCheapTierMax = [int](Get-SzaProfileValue 'runner.shapeCheapTierMax')
        if ($tier -ge 1 -and $tier -le $shapeCheapTierMax) { return $CheapModel }
    }

    # STATUS decides before tier, because a status names what work is left while a tier only names
    # how big it is. These are the states where the run still has to decide something - design a
    # spec, plan it, write Kotlin, diagnose a failure - plus BlockQuestions, whose whole product is
    # a set of questions put to the owner, where a badly framed question costs a round trip with a
    # human in it.
    # S2402: the three cut lines are the project's (runner.decisionStatuses, runner.cheapStatuses,
    # runner.cheapTierMax in the profile); the order of the tests is the canon's.
    $decisionStatuses = @(Get-SzaProfileValue 'runner.decisionStatuses')
    if ($decisionStatuses -contains $status) { return $StrongModel }

    # Code-complete states: the tree already carries the change and the run is an audit of it,
    # reading and comparing rather than deciding. BlockNeedUserTest is Implemented's twin - what is
    # outstanding there is a human on a device, not a decision this run makes - and it is the
    # largest open state in the catalog (76 of 168 open tickets, measured 2026-08-28).
    if (@(Get-SzaProfileValue 'runner.cheapStatuses') -contains $status) { return $CheapModel }

    # Tier is the fallback for whatever the status list did not settle. The strong band starts at
    # tier 4 by the description above ("a spec at tier 4 and above"), so tiers 1-3 are the cheap
    # band. The cut used to sit at 2, which sent the whole of tier 3 - the queue's modal tier, 52 of
    # 76 BlockNeedUserTest tickets alone - to the strong model against this script's own docstring.
    if ($tier -ge 1 -and $tier -le [int](Get-SzaProfileValue 'runner.cheapTierMax')) { return $CheapModel }

    return $StrongModel
}

function Get-TicketStepMarkCount {
    <#
        How many steps of this ticket's tactical plan are ticked done, or $null when it has no
        tactical folder at all. $null and 0 must stay distinguishable: "no plan" means this ticket
        can never produce the signal and keeps the flat deadline, while "a plan with nothing done
        yet" is a child that may still earn an extension.

        The tick shape is spec_catalog/plan-tick.ps1's own - one writer, one reader, so a change to
        the marker cannot silently stop being observed here.
    #>
    param([string] $Id)
    try {
        $record = Get-TicketRecord -Id $Id
        if ($null -eq $record -or [string]::IsNullOrWhiteSpace([string] $record.file)) { return $null }
        $specFile = Join-Path $RepoRoot ([string] $record.file)
        $folder = $specFile -replace '\.md$', ''
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { return $null }
        $done = 0
        foreach ($file in (Get-ChildItem -LiteralPath $folder -Filter '*.md' -ErrorAction SilentlyContinue)) {
            foreach ($line in @(Get-Content -LiteralPath $file.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)) {
                if ($line -match '^\*\*Status:\*\*\s*`\[x\]`') { $done++ }
            }
        }
        return $done
    } catch {
        # An unreadable plan is not evidence of a stalled child - fall back to the flat deadline.
        return $null
    }
}

function Stop-ProcessTree {
    param([int] $ProcessId)
    # taskkill /T reaches the node and gradle children the CLI spawns; Stop-Process alone leaves them
    # holding BUILD.LOCK, which would stall every later ticket in the run.
    & taskkill.exe /PID $ProcessId /T /F 2>&1 | Out-Null
}

function Get-LeaseStoreDir {
    <#
        The lease directory, resolved exactly the way locks/ticket-lease.ps1 resolves it: the
        TICKET_LEASE_ROOT override first, the repository root as the fallback. Reading it from the
        profile alone would ignore that override, and the runner and the lease library would then be
        watching two different stores while both reported success.
    #>
    $leaseRoot = (Get-SzaEnv 'TICKET_LEASE_ROOT')
    if ([string]::IsNullOrWhiteSpace($leaseRoot)) { $leaseRoot = $RepoRoot }
    return (Join-Path $leaseRoot (Get-SzaPath 'leasesDir' -Relative))
}

function Get-LiveLeaseFor {
    <#
        The live lease record for one ticket, or $null. It goes through ticket-lease.ps1 -Verb Status
        so the sweep, the liveness window and the 'mine' verdict stay the library's - a second opinion
        computed here would have to be kept in step with it for ever.

        An unreadable store returns $null, which launches the child. That is deliberate: "I could not
        read the leases" is not evidence the ticket is free, but stalling the whole queue behind a
        transient is worse than falling back to the child's own claim, which was the only check that
        existed before this one.
    #>
    param([string] $Id)
    if (-not (Test-Path -LiteralPath $leaseScript)) { return $null }
    try {
        $raw = & pwsh -NoProfile -File $leaseScript -Verb Status -Json 2>$null | Out-String
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        $leases = @($raw | ConvertFrom-Json)
        return ($leases | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1)
    } catch {
        return $null
    }
}

function Add-RunRecord {
    <#
        The journal row, written from one place. A run that never launched a child records a row just
        as a finished one does, and a second copy of this shape is how two exits drift into disagreeing
        about what a row means.
    #>
    param(
        [string] $Id,
        [string] $ChildModel,
        [string] $StatusBefore,
        [string] $StatusAfter,
        [bool] $Moved,
        [string] $Outcome,
        $ExitCode,
        [int] $Minutes
    )
    $record = [pscustomobject][ordered]@{
        id           = $Id
        model        = $ChildModel
        # Beside model, because it explains that field and nothing else. The instance already
        # distinguishes the journals by file name, but that answers "who wrote this", while
        # comparing two rules asks "which rule chose the model". The two answers agree only until
        # an instance is re-pointed or a run is launched by hand, and then they disagree silently.
        policy       = $ModelPolicy
        statusBefore = $StatusBefore
        statusAfter  = $StatusAfter
        moved        = $Moved
        outcome      = $Outcome
        exitCode     = $ExitCode
        minutes      = $Minutes
        finishedAt   = (Get-Date).ToString('s')
    }
    $results.Add($record)
    Add-Content -Path $journal -Value (($record | ConvertTo-Json -Compress)) -Encoding UTF8
    return $record
}

function Resolve-RunOutcome {
    <#
        What a finished child actually was, and whether the ticket moved - decided in one place so
        the journal, the summary colour and the idle series cannot read the same run differently.

        S2873. The exit code used to be journalled and never read: $outcome started at 'ok' and only
        three branches ever rewrote it, none of them the ordinary "the child started and failed".
        Such a run fell through to the elapsed-time guess below and was filed as an idle ticket.
        Measured over 985 journal rows on 2026-09-10, 68 of them (6.9%) described a failed child
        under another name - and 10 of those kept 'ok', which IS an idle outcome here, so a run the
        RUNNER failed pushed the ticket towards being passed over by automatic ranking. S1565 was
        held as [idle 2, ok] on the strength of one such row that same morning.

        The order of the rules is the point:

        1. An established verdict is never overwritten. 'timeout', 'claim-lost',
           'claim-lost-before-launch' and 'launch-failed' all observed the child itself, and a killed
           process's exit code is a consequence of the kill rather than a diagnosis of it.
        2. A non-zero exit is 'child-failed'.
        3. Otherwise the pre-existing guess: a child that exited quickly having changed nothing
           usually lost its claim to a parallel instance.

        Moved is false on a lost claim (the sibling working the ticket wrote the status this run
        would otherwise report as its own) and also on an EMPTY StatusAfter: two rows in that same
        journal recorded 'Draft -> "", moved: true' for children killed mid-run, because
        Get-TicketStatus could not read the catalog and '' differs from every real status. An
        unreadable status is a missing reading, not a move - and moved outranks the outcome in every
        consumer, so renaming those rows without this would leave them reading as successes.
    #>
    param(
        [string] $Outcome,
        $ExitCode,
        [string] $StatusBefore,
        [string] $StatusAfter,
        [int] $ElapsedSeconds
    )

    $resolved = $Outcome
    if ($resolved -eq 'ok') {
        if ($null -ne $ExitCode -and [int]$ExitCode -ne 0) {
            $resolved = 'child-failed'
        } elseif ($StatusBefore -eq $StatusAfter -and $ElapsedSeconds -lt 120) {
            $resolved = 'no-progress-or-claim-lost'
        }
    }

    $moved = $true
    if ($resolved -like 'claim-lost*' -or [string]::IsNullOrWhiteSpace($StatusAfter)) {
        $moved = $false
    } else {
        $moved = ($StatusBefore -ne $StatusAfter)
    }

    return [pscustomobject]@{ Outcome = $resolved; Moved = $moved }
}

# ---------------------------------------------------------------------------------------------
# Build the work list
# ---------------------------------------------------------------------------------------------

$explicit = @()
if ($Ids.Trim()) {
    # The @() is load-bearing. A pipeline that yields ONE element returns a scalar string, and
    # indexing a string returns a character - so a single-id run picked "S" out of "S2014" and then
    # looked up a ticket that does not exist. Caught by the smoke test, 2026-08-25.
    $explicit = @($Ids.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

Write-Host ''
Write-Host 'run-spec-queue' -ForegroundColor Cyan
Write-Host ("  cli            : {0}" -f $claude)
Write-Host ("  order          : {0}" -f $(if ($explicit.Count) { "explicit ($($explicit -join ', '))" } else { "$(Get-SzaPath 'releaseQueue' -Relative) via spec-next-preflight.ps1" }))
Write-Host ("  prompt         : {0}" -f $PromptTemplate)
Write-Host ("  permission     : {0}" -f $PermissionMode)
Write-Host ("  model policy   : {0}" -f $(
    switch ($ModelPolicy) {
        'tiered'  { "tiered ($StrongModel, $CheapModel for Implemented and tier 1-2)" }
        'fixed'   { "fixed ($Model)" }
        'default' { 'CLI default' }
    }))
Write-Host ("  timeout/ticket : {0} min" -f $TimeoutMinutes)
Write-Host ("  max tickets    : {0}" -f $(if ($MaxTickets -gt 0) { $MaxTickets } else { 'until the queue is exhausted' }))
Write-Host ("  instance       : {0}" -f $Instance)
Write-Host ("  stop files     : {0}  (all instances)" -f $stopFileAll)
Write-Host ("                   {0}  (this one)" -f $stopFileMine)
Write-Host ''

if ($DryRun) {
    # The dry run answers "what would this launch", so it runs the same pre-launch lease check the
    # real loop does and says which tickets would be skipped for it. Without this the one thing a
    # dry run cannot show is the one thing that decides whether a child starts at all.
    function Write-DryRunLeaseNote {
        param([string] $Id)
        $held = Get-LiveLeaseFor -Id $Id
        if ($null -eq $held) { return }
        if ($held.mine) {
            Write-Host ("      lease held by THIS instance - would launch anyway ('already-mine')." ) -ForegroundColor DarkGray
            return
        }
        Write-Host ("      HELD by session {0} on {1} - would skip, no child launched." -f `
                $held.sessionId, $held.host) -ForegroundColor Yellow
    }

    if ($explicit.Count) {
        $i = 1
        foreach ($id in $explicit) {
            $rec = Get-TicketRecord -Id $id
            Write-Host ("  {0,2}. {1}  (status: {2}, tier {3}) -> model {4}" -f `
                    $i, $id, $rec.status, $rec.tier, (Select-ModelFor -Ticket $rec))
            Write-DryRunLeaseNote -Id $id
            $i++
        }
    } else {
        $next = Get-NextQueuedTicket -Exclude @()
        if ($next -and $next -ne 'PARSE_ERROR') {
            Write-Host ("  next up: {0}  (status: {1}, tier {2}) -> model {3}" -f `
                    $next.id, $next.status, $next.tier, (Select-ModelFor -Ticket $next))
            Write-DryRunLeaseNote -Id ([string]$next.id)
            Write-Host '  the rest is re-ranked after every ticket, so only the head is knowable in advance.'
        } else {
            Write-Host '  nothing eligible.'
        }
    }
    Write-Host ''
    Write-Host 'run-spec-queue: dry run, nothing launched.' -ForegroundColor Yellow
    exit 0
}

# ---------------------------------------------------------------------------------------------
# The loop
# ---------------------------------------------------------------------------------------------

if ($StartDelaySeconds -gt 0) {
    $jitter = Get-Random -Minimum 0 -Maximum ($StartDelaySeconds + 1)
    Write-Host ("run-spec-queue: staggering {0}s before the first ranking." -f $jitter) -ForegroundColor DarkGray
    Start-Sleep -Seconds $jitter
}

# Reset the shared skip-cache so this run's first ranking answers every ticket for itself instead of
# trusting verdicts a sibling instance or an earlier run cached - see -KeepSkipCache above for why.
# Placed after the stagger so a staggered second instance does not immediately erase what the first
# one just re-derived in its own opening seconds.
if (-not $KeepSkipCache) {
    & pwsh -NoProfile -File $skipCache -Action reset | Out-Null
    Write-Host "run-spec-queue: skip-cache reset for this run (-KeepSkipCache to skip)." -ForegroundColor DarkGray
}

$processed = New-Object System.Collections.Generic.List[string]
$results = New-Object System.Collections.Generic.List[object]
$explicitIndex = 0
$ranAny = $false

while ($true) {

    if (Test-Path $stopFileMine) {
        Write-Host ''
        Write-Host 'run-spec-queue: this instance was asked to stop - finishing here.' -ForegroundColor Yellow
        Remove-Item $stopFileMine -Force -ErrorAction SilentlyContinue
        break
    }
    if (Test-Path $stopFileAll) {
        Write-Host ''
        Write-Host 'run-spec-queue: shared stop file found - finishing here.' -ForegroundColor Yellow
        # Deliberately NOT removed: the other instances have to see it too. Whoever wrote it deletes it.
        break
    }

    if ($MaxTickets -gt 0 -and $processed.Count -ge $MaxTickets) {
        Write-Host ''
        Write-Host ("run-spec-queue: reached -MaxTickets {0}." -f $MaxTickets) -ForegroundColor Yellow
        break
    }

    # --- pick the next id -----------------------------------------------------------------
    $id = $null
    $ticket = $null
    if ($explicit.Count) {
        if ($explicitIndex -ge $explicit.Count) { break }
        $id = $explicit[$explicitIndex]
        $explicitIndex++
        $ticket = Get-TicketRecord -Id $id
    } else {
        $ticket = Get-NextQueuedTicket -Exclude $processed.ToArray()
        if ($ticket -eq 'PARSE_ERROR') { break }
        if (-not $ticket) {
            Write-Host ''
            Write-Host 'run-spec-queue: the queue has nothing else this run can pick up.' -ForegroundColor Yellow
            break
        }
        $id = $ticket.id
    }

    $statusBefore = if ($ticket) { [string]$ticket.status } else { Get-TicketStatus -Id $id }
    $childModel = Select-ModelFor -Ticket $ticket

    # --- is it still free? ----------------------------------------------------------------
    # The ranking above read the lease store, but nothing reserves a ticket between that read and
    # the launch below, and the gap is a cold CLI start plus /spec-all stage 0a - tens of seconds,
    # not the "few seconds" this script used to claim. Re-read it here, where the answer is one
    # pwsh call old instead of a whole ranking old.
    #
    # A lease this instance already owns must NOT skip: it is usually what a killed child of ours
    # left behind, and skipping on it would hide the ticket from every later run. The child's own
    # claim answers 'already-mine' and carries on.
    $preLaunchLease = Get-LiveLeaseFor -Id $id
    if ($null -ne $preLaunchLease -and -not $preLaunchLease.mine) {
        Write-Host ''
        Write-Host ("  {0}: held by session {1} on {2} - not launching a child." -f `
                $id, $preLaunchLease.sessionId, $preLaunchLease.host) -ForegroundColor Yellow
        if ($preLaunchLease.reason) {
            Write-Host ("      holder's reason: {0}" -f $preLaunchLease.reason) -ForegroundColor DarkGray
        }
        [void](Add-RunRecord -Id $id -ChildModel $childModel -StatusBefore $statusBefore `
                -StatusAfter $statusBefore -Moved $false -Outcome 'claim-lost-before-launch' `
                -ExitCode $null -Minutes 0)
        $processed.Add($id)
        continue
    }

    $started = Get-Date

    Write-Host ''
    Write-Host ('=' * 78) -ForegroundColor DarkGray
    Write-Host ("  {0}  [{1}]   ticket {2} of {3}" -f $id, $statusBefore, ($processed.Count + 1), $(if ($MaxTickets -gt 0) { $MaxTickets } else { '?' })) -ForegroundColor Cyan
    Write-Host ("  started {0}   model {1}   fresh context - this is a new process" -f `
            $started.ToString('HH:mm:ss'), $(if ($childModel) { $childModel } else { 'CLI default' })) -ForegroundColor DarkGray
    Write-Host ('=' * 78) -ForegroundColor DarkGray

    # --- run it in its own process --------------------------------------------------------
    $prompt = $PromptTemplate.Replace('{id}', $id)
    $childArgs = @(Expand-ChildArgs -Template $runnerArgsTemplate -Prompt $prompt `
            -Mode $PermissionMode -Model $childModel)

    # ProcessStartInfo.ArgumentList, never Start-Process -ArgumentList. Start-Process joins the array
    # into one command line WITHOUT quoting, so an element containing a space is split at the space:
    # '/spec-all S1949' reached the CLI as '-p /spec-all' plus a stray 'S1949', and every child then
    # aborted with "no argument" after a minute of Opus. .NET's ArgumentList escapes each element.
    # Measured 2026-08-25, three tickets in a row lost this way.
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $claude
    foreach ($a in $childArgs) { $psi.ArgumentList.Add([string]$a) }
    $psi.WorkingDirectory = $RepoRoot
    $psi.UseShellExecute = $false

    $logFile = $null
    if ($Quiet) {
        $logFile = Join-Path $runDir ("{0}.log" -f $id)
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        Write-Host ("  output -> {0}" -f $logFile) -ForegroundColor DarkGray
    }

    $outcome = 'ok'
    $exitCode = $null
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)

        # Start draining before waiting. A redirected pipe that fills while nobody reads it blocks
        # the child forever, and the timeout below would then report a hang this script caused.
        $outTask = $null
        $errTask = $null
        if ($Quiet) {
            $outTask = $proc.StandardOutput.ReadToEndAsync()
            $errTask = $proc.StandardError.ReadToEndAsync()
        }

        # --- did this child win the claim? ------------------------------------------------
        # The pre-launch check narrows the race but cannot close it: the child claims its lease tens
        # of seconds after it starts, so a sibling can still take the ticket inside that window. The
        # test is the lease's own claimedAt against this process's start time - a lease claimed
        # BEFORE the child existed cannot be the child's. It needs no knowledge of identity, which is
        # what makes it hold whether or not FMS_AGENT_ID happens to be exported.
        #
        # It is skipped when the pre-launch check already found a lease of our own: that lease was
        # claimed long before this child started and would read as foreign, and the child's claim
        # returns 'already-mine' without rewriting claimedAt, so there is nothing here to observe.
        $claimVerdict = 'none'
        $childExited = $false
        if ($ClaimGraceSeconds -gt 0 -and $null -eq $preLaunchLease) {
            # The process's own start time, not $started: the gap between them is where a sibling's
            # claim would land, and attributing it to the wrong side of the test is the whole bug.
            $childStart = $started
            try { $childStart = $proc.StartTime } catch { $childStart = $started }
            $leasePath = Join-Path (Get-LeaseStoreDir) ("{0}.json" -f $id)
            $pollDeadline = (Get-Date).AddSeconds($ClaimGraceSeconds)
            while ((Get-Date) -lt $pollDeadline) {
                # WaitForExit is the sleep, so a child that exits inside the window is noticed here
                # instead of after the whole grace has been slept away.
                if ($proc.WaitForExit(2000)) { $childExited = $true; break }
                $leaseNow = $null
                try {
                    if (Test-Path -LiteralPath $leasePath) {
                        $leaseNow = Get-Content -LiteralPath $leasePath -Raw -ErrorAction Stop | ConvertFrom-Json
                    }
                } catch {
                    # Mid-write, most likely. The next poll reads it whole.
                    $leaseNow = $null
                }
                if ($null -eq $leaseNow -or -not $leaseNow.claimedAt) { continue }
                $claimedAt = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$leaseNow.claimedAt).LocalDateTime
                $claimVerdict = if ($claimedAt -ge $childStart) { 'own' } else { 'foreign' }
                break
            }
        }

        if ($claimVerdict -eq 'foreign') {
            $outcome = 'claim-lost'
            Write-Host ''
            Write-Host ("  run-spec-queue: {0} was claimed before this child started - a sibling owns it. Killing the process tree." -f $id) -ForegroundColor Red
            Stop-ProcessTree -ProcessId $proc.Id
        } elseif ($childExited) {
            $exitCode = $proc.ExitCode
        } else {
            # The grace window came out of the ticket's own budget, so spend what is left of it,
            # never a fresh full timeout.
            #
            # S2695: the deadline follows the PLAN, not the clock alone. A child that ticks another
            # step off its tactical plan has demonstrably done a unit of work, so its deadline moves
            # to a full -TimeoutMinutes from that moment. The step mark is the only signal used, and
            # deliberately so: the agent chat is written by the lock, lease and status scripts as a
            # side effect, so a spinning child would renew itself on it for ever, and a dev-log row
            # arrives once at the end when there is nothing left to extend. The extension can only
            # ADD time, so a ticket with no plan - or a child that ticks nothing - dies exactly when
            # it did before this.
            $deadline = $started.AddMinutes($TimeoutMinutes)
            $stepMarks = Get-TicketStepMarkCount -Id $id
            $stepMarksAtStart = $stepMarks
            $extensions = 0
            $timedOut = $false
            while ($true) {
                $remainingMs = [int](($deadline - (Get-Date)).TotalMilliseconds)
                if ($remainingMs -le 0) { $timedOut = -not $proc.HasExited; break }
                # Sliced so a new step mark is noticed inside the window rather than after it. A
                # ticket with no tactical folder gives no signal, so it waits in one slice and pays
                # nothing for the polling.
                $sliceMs = if ($null -eq $stepMarks) { $remainingMs } else { [Math]::Min($remainingMs, 60000) }
                if ($proc.WaitForExit($sliceMs)) { break }
                if ($null -eq $stepMarks) { continue }
                $now = Get-TicketStepMarkCount -Id $id
                if ($null -ne $now -and $now -gt $stepMarks) {
                    $stepMarks = $now
                    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
                    $extensions++
                    Write-Host ("  {0}: step {1} of its plan ticked - deadline moved to {2}." -f `
                            $id, $now, $deadline.ToString('HH:mm:ss')) -ForegroundColor DarkGray
                }
            }
            if ($timedOut) {
                $outcome = 'timeout'
                $progress = if ($null -eq $stepMarksAtStart) {
                    'no tactical plan - flat deadline'
                } elseif ($extensions -eq 0) {
                    "no step marked in the whole window (plan at $stepMarksAtStart done)"
                } else {
                    "$extensions extension(s), plan went $stepMarksAtStart -> $stepMarks done"
                }
                Write-Host ''
                Write-Host ("  run-spec-queue: {0} exceeded {1} min - killing the process tree. {2}." -f $id, $TimeoutMinutes, $progress) -ForegroundColor Red
                Stop-ProcessTree -ProcessId $proc.Id
                # A killed child cannot release its ticket lease; drop it so a later run is not refused.
                & pwsh -NoProfile -File (Get-SzaHarnessScript 'locks/ticket-lease.ps1') -Verb Release -Id $id 2>&1 | Out-Null
            } else {
                $exitCode = $proc.ExitCode
            }
        }

        if ($Quiet -and $logFile) {
            try {
                $body = ''
                if ($outTask -and $outTask.IsCompleted) { $body += $outTask.Result }
                if ($errTask -and $errTask.IsCompleted -and $errTask.Result) { $body += "`n--- stderr ---`n" + $errTask.Result }
                [System.IO.File]::WriteAllText($logFile, $body, [System.Text.Encoding]::UTF8)
            } catch {
                Write-Host ("  run-spec-queue: could not write {0} - {1}" -f $logFile, $_.Exception.Message) -ForegroundColor DarkYellow
            }
        }
    } catch {
        $outcome = 'launch-failed'
        Write-Host ("  run-spec-queue: could not launch the child for {0} - {1}" -f $id, $_.Exception.Message) -ForegroundColor Red
    }

    # Release the lease the child claimed, now that its process is gone. /spec-all asks the child to do
    # this itself before its final report, and the child does not reliably get there: S1884 claimed twice,
    # re-claimed at a phase boundary and never released, finishing 'ok' with the lease still held. A
    # cleanup step written in prose at the end of a 25-minute pipeline is not a finally block - this is.
    #
    # It has to be forced. The lease judges liveness by the write time of the owner's transcript, so one
    # that stopped a minute ago still reads as live for another 45 minutes. The parent knows better: it
    # started that process and watched it exit. The cost of leaving it is not cosmetic - the preflight
    # ranker skips a leased ticket, so the ticket that just advanced (the one most ready to continue) is
    # exactly the one locked out; measured with S1884 first in its package and passed over for the fourth.
    #
    # Never on a lost claim. That lease is the sibling's, won fairly seconds before this child was
    # killed for losing it, and forcing it open here would hand the ticket straight to the next
    # ranker while its real owner is still working - the exact outcome the two checks above exist
    # to prevent.
    if ($outcome -ne 'claim-lost' -and (Test-Path -LiteralPath $leaseScript)) {
        try {
            & pwsh -NoProfile -File $leaseScript -Verb Release -Id $id -Force *> $null
            if ($LASTEXITCODE -ne 0) {
                Write-Host ("  run-spec-queue: could not release the lease for {0} - it expires on its own." -f $id) -ForegroundColor DarkYellow
            }
        } catch {
            Write-Host ("  run-spec-queue: lease release for {0} failed - {1}" -f $id, $_.Exception.Message) -ForegroundColor DarkYellow
        }
    }

    $statusAfter = Get-TicketStatus -Id $id
    $elapsedSeconds = [int]((Get-Date) - $started).TotalSeconds
    $elapsed = [int]((Get-Date) - $started).TotalMinutes

    # What the run was, and whether the ticket moved. Both answers come from one function so the
    # journal row, the summary colour and the idle series cannot disagree - see Resolve-RunOutcome
    # for the rules and the measurements behind each of them (S2873).
    #
    # A ticket handed back with the status it started with has no autonomous next step; it stays in
    # $processed either way, so the re-ranking below never offers it again this run.
    $verdict = Resolve-RunOutcome -Outcome $outcome -ExitCode $exitCode `
            -StatusBefore $statusBefore -StatusAfter $statusAfter -ElapsedSeconds $elapsedSeconds
    $outcome = $verdict.Outcome
    $moved = $verdict.Moved
    $ranAny = $true
    $processed.Add($id)

    $runRecord = Add-RunRecord -Id $id -ChildModel $childModel -StatusBefore $statusBefore `
            -StatusAfter $statusAfter -Moved $moved -Outcome $outcome -ExitCode $exitCode `
            -Minutes $elapsed

    # Read AFTER the row is written, and forced fresh, so the series includes the run that just
    # ended. The count is attached to the in-memory record only - the journal is the input to this
    # number, so writing it back into the journal would make the series feed on itself.
    $series = Get-IdleRunSeries -Id $id -Refresh
    Add-Member -InputObject $runRecord -NotePropertyName 'idle' -NotePropertyValue $series.Count -Force

    $colour = if ($moved) { 'Green' } elseif ($outcome -ne 'ok') { 'Red' } else { 'Yellow' }
    Write-Host ''
    Write-Host ("  {0}: {1} -> {2}   ({3}, {4} min)" -f $id, $statusBefore, $statusAfter, $outcome, $elapsed) -ForegroundColor $colour
    if (-not $moved) {
        Write-Host ("  {0} did not move - dropped for the rest of this run." -f $id) -ForegroundColor DarkYellow
    }
    if ($series.Count -ge (Get-IdleRunPolicy).Threshold) {
        Write-Host ("  {0}: {1} run(s) in a row without a status move, last '{2}' - automatic ranking will pass it over until the status moves." -f `
                $id, $series.Count, $series.LastOutcome) -ForegroundColor DarkYellow
        Write-Host ("  it is marked [idle {0}, {1}] in {2}; run it by name to override." -f `
                $series.Count, $series.LastOutcome, (Get-SzaPath 'releaseQueue' -Relative)) -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------------------------

Write-Host ''
Write-Host ('=' * 78) -ForegroundColor DarkGray
Write-Host '  run-spec-queue summary' -ForegroundColor Cyan
Write-Host ('=' * 78) -ForegroundColor DarkGray

if ($results.Count -eq 0) {
    Write-Host '  nothing ran.'
} else {
    $results | Format-Table -AutoSize id, statusBefore, statusAfter, outcome, minutes, idle | Out-String | Write-Host
    $movedCount = ($results | Where-Object { $_.moved }).Count
    Write-Host ("  {0} ticket(s) run, {1} moved, {2} stayed put." -f $results.Count, $movedCount, ($results.Count - $movedCount))
    Write-Host ("  journal: {0}" -f $journal)
}
Write-Host ''

if (-not $ranAny) { exit 3 }
exit 0
