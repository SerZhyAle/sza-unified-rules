#requires -Version 7.0
<#
.SYNOPSIS
    Who is the calling agent - one resolver, never empty, for every runtime (S2372).

.DESCRIPTION
    Leaf library: sets no preference variables, holds no state in memory, dot-sources nothing. Both
    the lock library (scripts/utils/agent-lock.ps1, through Get-AgentSessionId) and the agent chat
    store read identity from here, so a lock, a queue ticket, a lease and a chat message name the
    same agent - the S2371 divergence appeared exactly where one writer had a fallback and another
    had none.

    The id chain, strongest first:
      1. FMS_AGENT_ID              - explicit project variable; a subagent or a wrapper that wants
                                     its own line sets it (measured 2026-09-02: a subagent inherits
                                     the parent's CLAUDE_CODE_SESSION_ID, so without this it IS the
                                     parent, which is the intended default). A runtime with no
                                     hooks sets THIS one first - see AGENTS.md section 9.1.
      2. CLAUDE_CODE_SESSION_ID    - the runtime's own session id.
      3. host-<name>-<pid>-<ticks> - the first long-lived ancestor process, found by walking past
                                     shells and interpreters (S2408), or - when the walk runs into
                                     a machine-wide process - the ancestor standing directly below
                                     it (S2417). A runtime that spawns a fresh shell per command
                                     has nothing stable below that process, so this is the lowest
                                     level at which one session can still answer with one id.
      4. pid-<PID>                 - process-scoped fallback, reached only when the walk found no
                                     ancestor to adopt at all or FMS_AGENT_HOST_WALK turned it
                                     off; liveness for it degrades to the wall-clock ceiling,
                                     which is still better than a blank owner.

    Every identity carries hostWalk, the outcome of its own walk, because the S2417 investigation
    needed exactly that fact and both failing processes had exited by the time anyone looked.

    Why the walk sits at step 3 and not higher: measured 2026-09-02, one hookless session wrote
    itself as 46 different agents with 46 nicknames in an hour, because every command got a new
    pid. Claude Code is unaffected - its session id is step 2 and still wins. The accepted cost is
    that two chats inside one host process (two Copilot chats in one VS Code window) share one
    identity: one id for two sessions beats forty-five ids for one (strategic ADR-2).

    Exit codes: none - library, dot-sourced only.
#>

# Names that are NEVER the host: the walk continues past them. Shells, terminals and interpreters
# are all started fresh per command by some runtime, so none of them outlives a session.
. (Join-Path $PSScriptRoot '..\_profile.ps1')
$Script:AgentHostPassThroughNames = @(
    'pwsh', 'powershell', 'powershell_ise', 'cmd', 'conhost', 'openconsole', 'windowsterminal',
    'bash', 'sh', 'zsh', 'dash', 'mintty', 'git', 'winpty', 'wsl', 'wslhost', 'busybox',
    'python', 'python3', 'py', 'node', 'npm', 'npx', 'env', 'sudo'
)
# Names that END the walk: adopting a machine-wide process would merge every session on the box
# into a single identity - strictly worse than the pid fallback it replaces (S2408 section 7,
# first risk row). Reaching one means the real host was already passed, so S2417 adopts THAT one
# instead of returning nothing; the machine-wide process itself is still never the identity.
$Script:AgentHostNeverNames = @(
    'explorer', 'services', 'svchost', 'wininit', 'winlogon', 'csrss', 'smss', 'lsass',
    'system', 'idle', 'runtimebroker', 'dllhost', 'taskhostw', 'fontdrvhost', 'sihost'
)
# Bounded: a cycle or a pathologically deep tree must not turn identity resolution into a hang,
# and no real agent host sits twelve interpreters above its own shell.
$Script:AgentHostWalkMaxDepth = 12

function Format-AgentHostIdentityId {
    <#
    .SYNOPSIS
        The id for one host process: host-<slug>-<pid>-<startTicks>.
    .DESCRIPTION
        The slug is sanitised because this value is written into file NAMES unmodified - a queue
        ticket is '0001__<id>.json' and a turn marker is '<DOMAIN>.TURN-<id>.json', neither of
        which sanitises. 'Code - Insiders' therefore has to arrive as 'code-insiders'.
        startTicks is what separates this process from a later one that inherits its pid.
    #>
    param([Parameter(Mandatory)]$Process)

    $slug = (([string]$Process.ProcessName).ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) { $slug = 'host' }
    $ticks = 0
    # StartTime is unreadable for a process of another user or a protected one. Zero disables the
    # start-time comparison rather than failing the walk: an id without it is still stable.
    try { $ticks = [int64]$Process.StartTime.Ticks } catch { $ticks = 0 }
    return ('host-{0}-{1}-{2}' -f $slug, $Process.Id, $ticks)
}

function Resolve-AgentHostWalk {
    <#
    .SYNOPSIS
        Over a chain of ancestor process NAMES, which one is the host and why the walk ended:
        Index (-1 for none) and Outcome.
    .DESCRIPTION
        Pure by design (S2417): names in, a verdict out, so both branches are provable without a
        process tree shaped to order. The two S2408 cases that demanded a long-lived ancestor from
        the tree they happened to run in were red on every runtime that has none, which measures
        the runtime rather than the rule.

        Outcomes: resolved (a non-pass-through ancestor), adopted-below-<name> (the ancestor one
        step under a machine-wide process), no-host-below-<name> (that process is the direct
        parent, so there is nothing under it to adopt), no-host-trail-lost (the chain ran out),
        no-host-depth (the depth bound was reached).
    #>
    param([AllowEmptyCollection()][string[]]$AncestorNames = @())

    $lastPassed = -1
    $limit = [Math]::Min($AncestorNames.Count, $Script:AgentHostWalkMaxDepth)
    for ($i = 0; $i -lt $limit; $i++) {
        $key = ([string]$AncestorNames[$i]).ToLowerInvariant()
        if ($Script:AgentHostNeverNames -contains $key) {
            # Directly under a machine-wide process stands the root of ONE session's tree, not the
            # machine's: three queue runners started from the same explorer give three different
            # roots, so adopting it merges nothing that S2408 kept apart (S2417 section 5).
            if ($lastPassed -ge 0) {
                return [pscustomobject]@{ Index = $lastPassed; Outcome = "adopted-below-$key" }
            }
            return [pscustomobject]@{ Index = -1; Outcome = "no-host-below-$key" }
        }
        if ($Script:AgentHostPassThroughNames -notcontains $key) {
            return [pscustomobject]@{ Index = $i; Outcome = 'resolved' }
        }
        $lastPassed = $i
    }
    # A lost trail and an exhausted depth adopt nothing on purpose: the shell they stopped on lives
    # one command, so a host- id minted from it would claim a lifetime it does not have, and the
    # S2408 case asserting "the host, not this process" would pass while proving nothing.
    if ($AncestorNames.Count -ge $Script:AgentHostWalkMaxDepth) {
        return [pscustomobject]@{ Index = -1; Outcome = 'no-host-depth' }
    }
    return [pscustomobject]@{ Index = -1; Outcome = 'no-host-trail-lost' }
}

function Get-AgentHostAncestorChain {
    <#
    .SYNOPSIS
        This process's ancestors, nearest first, up to and including the one that ends the walk.
    .DESCRIPTION
        Walks Parent, which in pwsh 7 is a property of the process object. Measured on the owner's
        machine 2026-09-02: the whole warm walk averages 0.42 ms, while a SINGLE step through
        Get-CimInstance costs 118 ms - and identity is resolved by every coordination script, so
        the per-step price decides the design (S2408 ADR-1). Collection stops on exactly the
        conditions Resolve-AgentHostWalk decides on, so the number of .Parent reads is what it was
        before S2417 split the two apart.
    #>
    $chain = [System.Collections.Generic.List[object]]::new()
    try {
        $current = Get-Process -Id $PID -ErrorAction Stop
        for ($depth = 0; $depth -lt $Script:AgentHostWalkMaxDepth; $depth++) {
            $parent = $null
            try { $parent = $current.Parent } catch { $parent = $null }
            if ($null -eq $parent) { break }
            $chain.Add($parent)
            $key = ([string]$parent.ProcessName).ToLowerInvariant()
            if ($Script:AgentHostNeverNames -contains $key) { break }
            if ($Script:AgentHostPassThroughNames -notcontains $key) { break }
            $current = $parent
        }
    }
    catch { }
    # Returned unwrapped on purpose: the caller collects with @(..), and the comma operator would
    # hand it ONE element holding the whole array - member access then reads every ancestor at once
    # and the id comes out as 'host-pwsh-bash-System.Object[]-0' (measured 2026-09-03).
    return $chain.ToArray()
}

function Get-AgentHostIdentity {
    <#
    .SYNOPSIS
        The host identity and the outcome of the walk that produced it: Id ($null when none) and
        Outcome (never empty).
    .DESCRIPTION
        FMS_AGENT_HOST_WALK set to 0/off/false/no answers 'disabled' without walking, which is the
        documented escape for a runtime that must not be merged with its neighbours.
    #>
    $walkSwitch = [string](Get-SzaEnv 'AGENT_HOST_WALK')
    if (-not [string]::IsNullOrWhiteSpace($walkSwitch) -and
        $walkSwitch.Trim().ToLowerInvariant() -in @('0', 'off', 'false', 'no')) {
        return [pscustomobject]@{ Id = $null; Outcome = 'disabled' }
    }

    $chain = @(Get-AgentHostAncestorChain)
    $names = @($chain | ForEach-Object { [string]$_.ProcessName })
    $decision = Resolve-AgentHostWalk -AncestorNames $names
    if ($decision.Index -lt 0) {
        return [pscustomobject]@{ Id = $null; Outcome = $decision.Outcome }
    }
    return [pscustomobject]@{
        Id      = (Format-AgentHostIdentityId -Process $chain[$decision.Index])
        Outcome = $decision.Outcome
    }
}

function Get-AgentHostIdentityId {
    <#
    .SYNOPSIS
        Identity of the host ancestor process alone, or $null when the walk found none - the
        companion accessor for a caller that does not want the walk outcome.
    #>
    return (Get-AgentHostIdentity).Id
}

function Test-AgentIdentityProcessAlive {
    <#
    .SYNOPSIS
        Is the process behind a host- or pid- identity still running? False for every other shape.
    .DESCRIPTION
        The keep-signal of strategic ADR-3: it may only turn a liveness verdict LIVE, never stale,
        so a wrong answer costs a record that outlives its owner until the wall-clock ceiling -
        never a lock taken away from someone still editing.

        Two guards against a recycled pid naming the wrong process. A host- id carries the start
        ticks and they must match exactly. A pid- id carries nothing, so the caller passes
        -NotStartedAfter with the moment the record was written: a process that started after the
        record cannot be the process that wrote it. The one-minute grace covers clock granularity
        between the two writes, not a real gap.

        A session-guid owner returns false here and falls through to the clock-based signals,
        which is correct - a guid names no process.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Id,
        [datetime]$NotStartedAfter = [datetime]::MinValue
    )

    if ([string]::IsNullOrWhiteSpace($Id)) { return $false }
    $processId = 0
    $expectedTicks = 0
    if ($Id -match '^pid-(\d+)$') {
        $processId = [int]$Matches[1]
    }
    elseif ($Id.StartsWith('host-')) {
        # Split from the RIGHT: the slug itself may contain digits and hyphens.
        $parts = $Id.Split('-')
        if ($parts.Count -lt 4) { return $false }
        if ($parts[-1] -notmatch '^\d+$' -or $parts[-2] -notmatch '^\d+$') { return $false }
        $processId = [int]$parts[-2]
        $expectedTicks = [int64]$parts[-1]
    }
    else { return $false }

    try {
        $process = Get-Process -Id $processId -ErrorAction Stop
        $started = $null
        try { $started = $process.StartTime } catch { $started = $null }
        if ($expectedTicks -gt 0) {
            if ($null -eq $started -or [int64]$started.Ticks -ne $expectedTicks) { return $false }
        }
        if ($NotStartedAfter -gt [datetime]::MinValue -and $null -ne $started -and
            $started -gt $NotStartedAfter.AddMinutes(1)) { return $false }
        return $true
    }
    catch { return $false }
}

<#
    The NICKNAME (owner ruling 2026-09-02): an id is a uuid or a pid, and the owner reading the
    chat cannot tell two of those apart. So every agent carries a readable name - a random
    adjective-animal pair plus the minute it was taken, e.g. `brisk-otter-0902-2231` - chosen once
    per id on its first identity resolution in a session (the session-start hook, or the first
    script the agent runs) and kept in temp/AGENT-CHAT/names/<id>.json so every later process of
    the same session answers with the same name. FMS_AGENT_NAME overrides it for an agent that
    wants to be called something specific. Never empty: when the registry cannot be written the
    name falls back to the id.

    The human-readable part (runtime, entrypoint, model, instance) may each be unknown but is
    never empty: 'unknown' and '-' are values a reader can print, $null is not.
#>

$Script:AgentNickAdjectives = @(
    'amber', 'bold', 'brisk', 'calm', 'coral', 'crisp', 'eager', 'fleet', 'gentle', 'hardy', 'ivory', 'jade',
    'keen', 'lucid', 'merry', 'nimble', 'olive', 'pearl', 'plucky', 'quiet', 'rapid', 'ruby', 'sharp', 'slate',
    'steady', 'sunny', 'swift', 'tidy', 'vivid', 'warm', 'wise', 'zesty'
)
$Script:AgentNickAnimals = @(
    'badger', 'beaver', 'bison', 'crane', 'dingo', 'eland', 'falcon', 'ferret', 'gecko', 'heron', 'hyrax', 'ibis',
    'impala', 'koala', 'lemur', 'lynx', 'marten', 'moose', 'newt', 'ocelot', 'osprey', 'otter', 'panda', 'quail',
    'raven', 'sable', 'tapir', 'vole', 'walrus', 'wren', 'yak', 'zebra'
)

function Get-AgentIdentityResolution {
    <#
    .SYNOPSIS
        The agent id together with how it was reached: Id and HostWalk, neither ever empty.
    .DESCRIPTION
        HostWalk is 'not-reached' when an environment variable answered and the walk never ran,
        'disabled' when it was turned off, and otherwise the outcome Resolve-AgentHostWalk gave.
    #>
    $explicit = (Get-SzaEnv 'AGENT_ID')
    if (-not [string]::IsNullOrWhiteSpace($explicit)) {
        return [pscustomobject]@{ Id = $explicit.Trim(); HostWalk = 'not-reached' }
    }
    $session = $env:CLAUDE_CODE_SESSION_ID
    if (-not [string]::IsNullOrWhiteSpace($session)) {
        return [pscustomobject]@{ Id = $session.Trim(); HostWalk = 'not-reached' }
    }
    # S2408: below the runtime's own session id, the caller's process is the wrong unit - it dies
    # with the command. The host process above it does not.
    $walk = Get-AgentHostIdentity
    if (-not [string]::IsNullOrWhiteSpace($walk.Id)) {
        return [pscustomobject]@{ Id = $walk.Id; HostWalk = $walk.Outcome }
    }
    return [pscustomobject]@{ Id = "pid-$PID"; HostWalk = $walk.Outcome }
}

function Get-AgentIdentityId {
    <#
    .SYNOPSIS
        The agent id alone - the value every coordination file records as the owner.
    #>
    return (Get-AgentIdentityResolution).Id
}

function Get-AgentIdentityRuntime {
    $explicit = (Get-SzaEnv 'AGENT_RUNTIME')
    if (-not [string]::IsNullOrWhiteSpace($explicit)) { return $explicit.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($env:CLAUDECODE)) { return 'claude-code' }
    if (-not [string]::IsNullOrWhiteSpace($env:GEMINI_CLI)) { return 'gemini' }
    $names = @(Get-ChildItem Env: -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    if (@($names | Where-Object { $_ -like 'CODEX_*' }).Count -gt 0) { return 'codex' }
    if (@($names | Where-Object { $_ -like 'COPILOT_*' }).Count -gt 0) { return 'copilot' }
    return 'unknown'
}

function Get-AgentNameDir {
    <#
    .SYNOPSIS
        Where nicknames live: <chat root>/names. Same root rule as the chat store, without
        depending on it - this leaf is loaded first.
    #>
    $root = (Get-SzaEnv 'AGENT_CHAT_ROOT')
    if ([string]::IsNullOrWhiteSpace($root)) {
        $v = Get-Variable -Name AgentLockRepoRoot -Scope Script -ErrorAction SilentlyContinue
        $repo = if ($null -ne $v -and -not [string]::IsNullOrWhiteSpace([string]$v.Value)) { [string]$v.Value }
                else { (Get-SzaProjectRoot) }
        $root = (Get-SzaPath 'agentChatDir')
    }
    return (Join-Path $root 'names')
}

function New-AgentNickname {
    <#
    .SYNOPSIS
        A fresh random name with the minute it was taken: <adjective>-<animal>-<MMdd>-<HHmm>.
    #>
    $adj = $Script:AgentNickAdjectives[(Get-Random -Maximum $Script:AgentNickAdjectives.Count)]
    $animal = $Script:AgentNickAnimals[(Get-Random -Maximum $Script:AgentNickAnimals.Count)]
    return ('{0}-{1}-{2}' -f $adj, $animal, (Get-Date).ToString('MMdd-HHmm'))
}

function Get-AgentNickname {
    <#
    .SYNOPSIS
        The nickname registered for an id; taken now if none exists (unless -NoCreate), $null when
        none exists and none may be taken.
    #>
    param(
        [Parameter(Mandatory)][string]$Id,
        [switch]$NoCreate
    )
    $safe = ($Id -replace '[^A-Za-z0-9\-]', '-')
    $dir = Get-AgentNameDir
    $path = Join-Path $dir "$safe.json"
    if (Test-Path -LiteralPath $path) {
        try {
            $rec = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $n = [string]$rec.PSObject.Properties['name'].Value
            if (-not [string]::IsNullOrWhiteSpace($n)) { return $n }
        }
        catch { }
    }
    if ($NoCreate) { return $null }
    try {
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $name = New-AgentNickname
        $body = [ordered]@{ id = $Id; name = $name; takenAt = [DateTime]::UtcNow.ToString('o'); pid = $PID } | ConvertTo-Json -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        # CreateNew: two processes of one session resolving their identity at the same instant both
        # try to take a name, and exactly one wins; the other reads the winner's file below.
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
        try { $fs.Write($bytes, 0, $bytes.Length); $fs.Flush() } finally { $fs.Close() }
        return $name
    }
    catch [System.IO.IOException] {
        try {
            $rec = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $n = [string]$rec.PSObject.Properties['name'].Value
            if (-not [string]::IsNullOrWhiteSpace($n)) { return $n }
        }
        catch { }
        return $null
    }
    catch { return $null }
}

function Get-AgentIdentity {
    <#
    .SYNOPSIS
        The whole identity: id, nickname and the human-readable fields, none of them empty.
    #>
    $resolution = Get-AgentIdentityResolution
    $id = $resolution.Id
    $name = (Get-SzaEnv 'AGENT_NAME')
    if ([string]::IsNullOrWhiteSpace($name)) { $name = Get-AgentNickname -Id $id }
    if ([string]::IsNullOrWhiteSpace($name)) { $name = $id }
    $entrypoint = $env:CLAUDE_CODE_ENTRYPOINT
    if ([string]::IsNullOrWhiteSpace($entrypoint)) { $entrypoint = '-' }
    $model = (Get-SzaEnv 'AGENT_MODEL')
    if ([string]::IsNullOrWhiteSpace($model)) { $model = 'unknown' }
    $instance = (Get-SzaEnv 'QUEUE_INSTANCE')
    if ([string]::IsNullOrWhiteSpace($instance)) { $instance = '-' }
    $hostName = $env:COMPUTERNAME
    if ([string]::IsNullOrWhiteSpace($hostName)) { $hostName = [Environment]::MachineName }
    if ([string]::IsNullOrWhiteSpace($hostName)) { $hostName = 'unknown' }
    $parentPid = 0
    try { $parentPid = [int](Get-Process -Id $PID -ErrorAction Stop).Parent.Id } catch { $parentPid = 0 }

    return [pscustomobject]@{
        id         = $id
        name       = $name.Trim()
        runtime    = Get-AgentIdentityRuntime
        entrypoint = $entrypoint.Trim()
        model      = $model.Trim()
        instance   = $instance.Trim()
        host       = $hostName
        pid        = $PID
        parentPid  = $parentPid
        # S2417: the identity object is embedded whole in every chat message, so the outcome of
        # this walk lands in files that outlive the process - which is what the investigation of
        # the failing runtimes had to reconstruct by hand, from processes that had already exited.
        hostWalk   = $resolution.HostWalk
    }
}

function Format-AgentIdentity {
    <#
    .SYNOPSIS
        One printable line: <name> [<id>] (<runtime>/<model>, instance <instance>).
    #>
    param($Identity)
    if ($null -eq $Identity) { $Identity = Get-AgentIdentity }
    return ('{0} [{1}] ({2}/{3}, instance {4})' -f $Identity.name, $Identity.id, $Identity.runtime, $Identity.model, $Identity.instance)
}
