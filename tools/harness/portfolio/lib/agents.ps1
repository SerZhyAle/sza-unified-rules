# The agent of a pass (TASK-FLOW rules 42 and 48; S0016 R9, R17, R26, R27): the first agent of the owner's agentOrder
# that may take the ticket, and the machine-wide per-agent hold that makes a spent agent wait while the next one works.
#
# Dot-source this file after paths.ps1, registry.ps1, ledger-watch.ps1 and loop.ps1; it defines functions only, sets
# no preference and prints nothing.
#
#   Get-PqTicketLevel -RepoPath <dir> -TicketId <id>
#       light, medium or hard from the spec's `**Complexity:**` line (rule 51, the runner's reader; a grade 0-9
#       answers its band), or '' for none.
#   Get-PqTicketLevelInfo -RepoPath <dir> -TicketId <id>
#       the same one reading of the line, with the answer named: level, why (declared, noLine, noFile or
#       unrecognised) and captureDefault (the recognised 'medium - not assessed at capture' text). The doctor
#       reports on the why; nothing re-derives the regex a second time.
#   Get-PqAgentPrompt -Agent <record> -RepoPath <dir>
#       @{ ok; template; why }. slash: template $null (the repository's own runner.promptTemplate, as today). file: a
#       template that tells the agent to open the pipeline's command file, when the repository's template is a slash
#       command and that file exists (a project or user command or skill, or the plugin's own skill for /sza:<skill>);
#       a command the repository does not have falls back to the shared default, the plugin's lifecycle skill. A
#       template that is plain text is used as it is. why noPipelineForm when no command file is found.
#   Get-PqAgentHold -Name <agent> / Test-PqAgentHeld -Hold <hold> -Agent <record>
#       the hold of rule 48 (or $null), and whether it still keeps the agent out. A hold with until in the future holds;
#       one with until $null holds for limitPollMinutes after it was written, then lets one probe pass through.
#       While that probe pass is in flight (another live worker of the agent), the agent stays held for everyone else.
#   Test-PqAgentProbeDue -Hold <hold> -Agent <record> / Get-PqPassAgentMax -Pick <pick> / Get-PqProbeResult
#       whether the next pass of the agent is the probe of a poll hold; the agent cap of the assignment (1 for a probe,
#       so two workers never probe at once); and the `agent.probe` result (ok, limit, error) of a pass that was one.
#   Set-PqAgentHold -Name -Pass -Source -Detector [-Until] / Remove-PqAgentHold -Name
#       write (until only ever moves forward) or clear holds\<agent>.json.
#   Select-PqAgent -Registry <registry> -RepoPath <dir> -Level <level>
#       @{ agent; record; template; fallbacks } for the first agent that passes every test, or with agent $null when
#       none does. fallbacks lists @{ from; why } (limit, maxParallel, levelNotAllowed, noPipelineForm) for each passed over.
#
# A limit is read only from the provider's own output: Claude's transcript (the repository runner's detector), another
# provider's pass log by its record's limitDetector pattern. A fast failure with no limit text is an ordinary failed
# pass, never a probable limit (owner, 2026-10-29: the next provider only on a spent limit); S0082 proposes the
# contract's fast-failure sentence, source `fastFailure` and `agent.unproven` reserved.

$script:PqFastFailureSeconds = 120

# One reading of the `**Complexity:**` line (rule 51), with the answer named. The level is the contract's
# three words (the Russian spellings included), and why says how it was reached: declared, noLine (no
# `**Complexity:**` in the header window), noFile (no record, no file named, the file gone, the ledger
# unreadable) or unrecognised (a value the reader does not accept - a Stage 0 rung such as
# "Complex (..)" reads as no declaration, on purpose). captureDefault is true only for the capture text
# 'medium - not assessed at capture': a recognised level under rule 51 that is still not an assessment,
# which S0041 reports separately rather than redefining the recognition.
#
# TASK-FLOW 0.32 (S0139): the value is read by the one parser of the line (spec_catalog/lib/complexity-grade.ps1), so
# a grade 0-9 is recognised too; score is the grade (a word reads as 1, 5 or 8; -1 for none), numeric says the line
# carries a digit, pinned that the owner marked it, spec the spec file's full path ('' when there is none).
. (Join-Path $PSScriptRoot '..\..\spec_catalog\lib\complexity-grade.ps1')
function Get-PqTicketLevelInfo {
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][string]$TicketId)
    $info = [pscustomobject]@{ level = ''; why = 'noLine'; captureDefault = $false; score = -1; numeric = $false; pinned = $false; spec = ''; parallel = $false }
    try {
        $snap = Get-PqLedgerSnapshot -RepoPath $RepoPath
        if (-not $snap.tickets.Contains($TicketId)) { $info.why = 'noFile'; return $info }
        $file = [string]$snap.tickets[$TicketId].file
        if (-not $file) { $info.why = 'noFile'; return $info }
        $spec = Resolve-PqRepoPathValue $snap.root $file
        if (-not [IO.File]::Exists($spec)) { $info.why = 'noFile'; return $info }
        $info.spec = $spec
        $raw = ''
        $head = @(Get-Content -LiteralPath $spec -TotalCount 40 -Encoding UTF8)
        # S0140: the decomposable flag is read whatever the grade line holds.
        $info.parallel = [bool](Get-SzaParallelFlag $head).flagged
        foreach ($line in $head) {
            if ($line -match '^\*\*Complexity:\*\*\s*(.+?)\s*$') { $raw = $Matches[1]; break }
        }
        if (-not $raw) { $info.why = 'noLine'; return $info }
        $g = ConvertFrom-SzaComplexityValue $raw
        if (-not $g.recognised) { $info.why = 'unrecognised'; return $info }
        $info.level = $g.level
        $info.why = 'declared'
        $info.score = $g.score
        $info.numeric = $g.numeric
        $info.pinned = $g.pinned
        if (-not $g.numeric -and $g.level -ceq 'medium' -and $raw -imatch 'not assessed at capture') { $info.captureDefault = $true }
    }
    catch { $info.why = 'noFile' }
    return $info
}

function Get-PqTicketLevel {
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][string]$TicketId)
    return (Get-PqTicketLevelInfo -RepoPath $RepoPath -TicketId $TicketId).level
}

function Get-PqAgentPrompt {
    param([Parameter(Mandatory)]$Agent, [Parameter(Mandatory)][string]$RepoPath)
    if ((Get-PqValue $Agent 'promptForm' 'slash') -cne 'file') { return @{ ok = $true; template = $null; why = $null } }
    $template = $null
    try {
        $profileFile = Join-Path $RepoPath '.sza-profile.json'
        if ([IO.File]::Exists($profileFile)) {
            $p = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($profileFile))
            $runner = Get-PqValue $p 'runner'
            $template = [string](Get-PqValue $runner 'promptTemplate' '')
        }
    }
    catch { return @{ ok = $false; template = $null; why = 'noPipelineForm' } }
    $default = [string]$script:PqRepoDefaults.runner.promptTemplate
    if (-not $template) { $template = $default }
    if ($template -notmatch '^/') { return @{ ok = $true; template = $template.Replace('{Id}', '{id}'); why = $null } }
    $paths = Get-PqRepoPaths -RepoPath $RepoPath
    $commandFile = Find-PqCommandFile -Template $template -Paths $paths
    # A command the repository does not have falls back to the shared default, as run-spec-queue.ps1 does for Claude.
    if (-not $commandFile -and $template -cne $default) {
        $template = $default
        $commandFile = Find-PqCommandFile -Template $template -Paths $paths
    }
    if (-not $commandFile -or $template.Replace('{Id}', '{id}') -notmatch '^/(?<name>[A-Za-z0-9_:-]+)(?<rest>.*)$') {
        return @{ ok = $false; template = $null; why = 'noPipelineForm' }
    }
    $name = $Matches['name']
    $rest = $Matches['rest'].Trim()
    $rel = [IO.Path]::GetRelativePath($paths.Root, $commandFile)
    if ([IO.Path]::IsPathRooted($rel) -or $rel.StartsWith('..')) { $rel = $commandFile }
    $rel = $rel.Replace('\', '/')
    # AGENTS.md section 9 of the origin: an agent without slash commands opens the command file and follows it.
    $text = "You have no slash commands. Open the file $rel and follow its instructions exactly, as the command /$name would, with this argument string: $rest"
    return @{ ok = $true; template = $text; why = $null }
}

# The file behind a /<name> template, or $null: <commandsDir>/<name>.md or .claude/skills/<name>/SKILL.md in the
# repository, then the user's ~/.claude; /sza:<skill> is the plugin's own skills/<skill>/SKILL.md beside this harness.
function Find-PqCommandFile([string]$Template, $Paths) {
    if ($Template -notmatch '^/(?<name>[A-Za-z0-9_:-]+)') { return $null }
    $name = $Matches['name']
    $candidates = if ($name -match '^sza:(?<skill>.+)$') {
        @(Join-Path $PSScriptRoot "..\..\..\..\skills\$($Matches['skill'])\SKILL.md")
    }
    elseif ($name -match ':') { @() }
    else {
        $userDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
        @((Join-Path $Paths.CommandsDir "$name.md"), (Join-Path $Paths.Root ".claude\skills\$name\SKILL.md"),
            (Join-Path $userDir "commands\$name.md"), (Join-Path $userDir "skills\$name\SKILL.md"))
    }
    foreach ($c in $candidates) { if ([IO.File]::Exists($c)) { return [IO.Path]::GetFullPath($c) } }
    return $null
}

function Get-PqAgentHold([Parameter(Mandatory)][string]$Name) {
    $file = Get-PqPath -Kind hold -Agent $Name
    if (-not [IO.File]::Exists($file)) { return $null }
    return (Read-PqState $file)
}

function Test-PqAgentHeld($Hold, $Agent) {
    if ($null -eq $Hold) { return $false }
    $now = [DateTimeOffset]::UtcNow
    $until = Get-PqValue $Hold 'until'
    if ($until) {
        try { return ([DateTimeOffset]::Parse([string]$until) -gt $now) } catch { return $false }
    }
    $written = $null
    try { $written = [DateTimeOffset]::Parse([string](Get-PqValue $Hold 'writtenAt')) } catch { return $false }
    $poll = [int](Get-PqValue $Agent 'limitPollMinutes' 30)
    if ($written.AddMinutes($poll) -gt $now) { return $true }
    # Rule 48: one probe pass decides. Past the poll, a live pass of the agent on another worker is that probe, and the
    # agent stays held for every other worker until it ends (it clears the hold or writes it again).
    $name = [string](Get-PqValue $Hold 'agent' (Get-PqValue $Agent 'name' ''))
    return ($name -and (Get-PqAgentLiveCount $name) -gt 0)
}

# True when the hold is a poll hold (until $null) whose limitPollMinutes have run out: the next pass is its probe.
function Test-PqAgentProbeDue($Hold, $Agent, [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow) {
    if ($null -eq $Hold -or (Get-PqValue $Hold 'until')) { return $false }
    try { $written = [DateTimeOffset]::Parse([string](Get-PqValue $Hold 'writtenAt')) } catch { return $false }
    return ($written.AddMinutes([int](Get-PqValue $Agent 'limitPollMinutes' 30)) -le $Now)
}

# The agent cap the assignment is checked against: 1 while the pass would be a probe, so the assignment's own lock lets
# exactly one worker take it; otherwise the record's maxParallel.
function Get-PqPassAgentMax($Pick) {
    if (Test-PqAgentProbeDue (Get-PqAgentHold ([string]$Pick.agent)) $Pick.record) { return 1 }
    return [int](Get-PqValue $Pick.record 'maxParallel' 1)
}

# The `agent.probe` result of a pass that was a probe: limit when it ended on one, error when it was killed, failed to
# run or ended in a failure outcome, else ok.
function Get-PqProbeResult([int]$Limits, [bool]$Killed, [bool]$Failed, [string]$Outcome) {
    if ($Limits -gt 0) { return 'limit' }
    if ($Killed -or $Failed -or $Outcome -cin @('child-failed', 'launch-failed', 'timeout', 'provider-error')) { return 'error' }
    return 'ok'
}

function Set-PqAgentHold {
    param([Parameter(Mandatory)][string]$Name, [string]$Pass, [string]$Source = 'fastFailure', [string]$Detector = 'unproven', [string]$Until)
    # Resolved before the lock: the lock's body sees Invoke-PqStateLock's own $name, which shadows $Name.
    $file = Get-PqPath -Kind hold -Agent $Name
    $agentName = $Name
    Invoke-PqStateLock {
        $dir = Split-Path -Parent $file
        if (-not [IO.Directory]::Exists($dir)) { $null = [IO.Directory]::CreateDirectory($dir) }
        # Rule 48: until only ever moves forward; $null never replaces a timestamp still in the future.
        $old = Read-PqState $file
        $oldUntil = Get-PqValue $old 'until'
        $newUntil = if ($Until) { $Until } else { $null }
        if ($oldUntil) {
            try {
                $o = [DateTimeOffset]::Parse([string]$oldUntil)
                if ($o -gt [DateTimeOffset]::UtcNow -and (-not $newUntil -or [DateTimeOffset]::Parse($newUntil) -lt $o)) { $newUntil = [string]$oldUntil }
            }
            catch { }
        }
        $obj = [ordered]@{
            agent = $agentName
            until = $newUntil
            source = $Source
            detector = $Detector
            writtenAt = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            pass = $Pass
        }
        $tmp = "$file.$PID.tmp"
        [IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($tmp, $file, $true)
    }
}

function Remove-PqAgentHold([Parameter(Mandatory)][string]$Name) {
    $file = Get-PqPath -Kind hold -Agent $Name
    Invoke-PqStateLock {
        if ([IO.File]::Exists($file)) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue; return $true }
        return $false
    }
}

# Live passes of one agent, from the other workers' state files (this worker is between passes when it asks).
function Get-PqAgentLiveCount([Parameter(Mandatory)][string]$Name) {
    $runDir = Join-Path (Get-PqRoot) 'run'
    if (-not [IO.Directory]::Exists($runDir)) { return 0 }
    $n = 0
    foreach ($wf in [IO.Directory]::GetFiles($runDir, 'worker-*.json')) {
        $s = Read-PqState $wf
        if ((Get-PqValue $s 'pid' 0) -eq $PID) { continue }
        if ((Get-PqValue $s 'agent') -ceq $Name -and (Get-PqValue $s 'ticket') -and (Test-PqStateOwner $s)) { $n++ }
    }
    return $n
}

# The `why` vocabulary of `agent.fallback` (EVENTS.md). Select-PqAgent also records an agent the owner's
# `STOP-agent__<name>` keeps out (why `stopped`) for the console summary; that is the owner's stop, recorded by the
# stop itself, not a fallback test, so the loop writes no `agent.fallback` for it.
$script:PqFallbackWhys = @('limit', 'maxParallel', 'levelNotAllowed', 'aboveCeiling', 'noPipelineForm', 'launchFailed')
function Test-PqFallbackWhy([string]$Why) { return $script:PqFallbackWhys -ccontains $Why }

# The grade a ticket is chosen at (TASK-FLOW 0.32 item C): its own grade, else the grade of its level word, else 5.
function Get-PqSelectScore([int]$Score, [string]$Level) {
    if ($Score -ge 0 -and $Score -le 9) { return $Score }
    $w = Get-SzaComplexityWordScore $Level
    if ($w -ge 0) { return $w }
    return 5
}

# The route of an agent for a grade (TASK-FLOW 0.32 item B): the first row of `routes` whose max is at or above the
# grade, as @{ ok; max; model; effort } (model and effort '' when the row names none). A record without routes has
# the ceiling 9 and a row that changes nothing; a grade above the last row's max answers ok $false (aboveCeiling).
function Get-PqAgentRoute($Agent, [int]$Score) {
    $none = @{ ok = $true; max = 9; model = ''; effort = ''; parallel = ''; routed = $false }
    if ($null -eq $Agent -or -not (Test-PqHasKey $Agent 'routes')) { return $none }
    foreach ($row in @($Agent.routes)) {
        $max = [int](Get-PqValue $row 'max' -1)
        if ($Score -le $max) {
            return @{ ok = $true; max = $max; model = [string](Get-PqValue $row 'model' ''); effort = [string](Get-PqValue $row 'effort' '')
                parallel = [string](Get-PqValue $row 'parallel' ''); routed = $true }
        }
    }
    return @{ ok = $false; max = -1; model = ''; effort = ''; parallel = ''; routed = $true }
}

# The ceiling of an agent: the last row's max, 9 without routes.
function Get-PqAgentCeiling($Agent) {
    if ($null -eq $Agent -or -not (Test-PqHasKey $Agent 'routes')) { return 9 }
    $rows = @($Agent.routes)
    if ($rows.Count -eq 0) { return 9 }
    return [int](Get-PqValue $rows[-1] 'max' 9)
}

# `agent.resume` data for a hold that just ended (rule 48): heldFor is the whole seconds since the hold was last
# written (0 when its time is unreadable); by is `reset` when the hold carried a reset time that has passed, else
# `probe` - the pass that ended without a limit was the probe of a poll hold.
function Get-PqHoldResume($Hold, [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow) {
    $heldFor = 0
    try { $heldFor = [int][Math]::Max(0, [Math]::Floor(($Now - [DateTimeOffset]::Parse([string](Get-PqValue $Hold 'writtenAt'))).TotalSeconds)) } catch { }
    $by = if (Get-PqValue $Hold 'until') { 'reset' } else { 'probe' }
    return [ordered]@{ heldFor = $heldFor; by = $by }
}

function Select-PqAgent {
    # -Skip names agents the owner's `STOP-agent__<name>` keeps out of new work while a pass of it is still running (rule 47).
    # -Score is the ticket's grade (TASK-FLOW 0.32); -1 (the default) tests the grade of -Level's word, 5 without one.
    param([Parameter(Mandatory)]$Registry, [Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][string]$Level, [string[]]$Skip = @(), [int]$Score = -1)
    $score = Get-PqSelectScore $Score $Level
    $byName = @{}
    foreach ($a in @($Registry.agents)) { $byName[[string]$a.name] = $a }
    $fallbacks = [Collections.Generic.List[object]]::new()
    foreach ($name in @($Registry.agentOrder)) {
        $a = $byName[[string]$name]
        if ($null -eq $a) { continue }
        if (@($Skip) -ccontains [string]$name) { $fallbacks.Add(@{ from = $name; why = 'stopped' }); continue }
        if (Test-PqAgentHeld (Get-PqAgentHold $name) $a) { $fallbacks.Add(@{ from = $name; why = 'limit' }); continue }
        $levels = @(Get-PqValue $a 'levels' @('light', 'medium', 'hard'))
        if ($levels -cnotcontains $Level) { $fallbacks.Add(@{ from = $name; why = 'levelNotAllowed' }); continue }
        $route = Get-PqAgentRoute $a $score
        if (-not $route.ok) { $fallbacks.Add(@{ from = $name; why = 'aboveCeiling' }); continue }
        $max = [int](Get-PqValue $a 'maxParallel' 1)
        if ((Get-PqAgentLiveCount $name) -ge $max) { $fallbacks.Add(@{ from = $name; why = 'maxParallel' }); continue }
        $prompt = Get-PqAgentPrompt -Agent $a -RepoPath $RepoPath
        if (-not $prompt.ok) { $fallbacks.Add(@{ from = $name; why = $prompt.why }); continue }
        return @{ agent = [string]$name; record = $a; template = $prompt.template; fallbacks = $fallbacks; route = $route; score = $score }
    }
    return @{ agent = $null; record = $null; template = $null; fallbacks = $fallbacks; route = $null; score = $score }
}

# The model and effort a pick launches with (TASK-FLOW 0.32 item B): the route's, else the record's fixed ones (for
# claude the record names none, so '' - the runner then chooses by the level, as before). @{ model; effort }.
function Get-PqPickLaunch($Pick) {
    $model = ''; $effort = ''
    if ($null -ne $Pick -and $null -ne $Pick.record) {
        $model = [string](Get-PqValue $Pick.record 'model' '')
        $effort = [string](Get-PqValue $Pick.record 'effort' '')
        if ([string]$Pick.agent -ceq 'claude') { $model = ''; $effort = '' }
        $route = $Pick.route
        if ($null -ne $route) {
            if ($route.model) { $model = [string]$route.model }
            if ($route.effort) { $effort = [string]$route.effort }
        }
    }
    return @{ model = $model; effort = $effort }
}

# The runner's arguments for a pass of claude (TASK-FLOW 0.32 item B). A route that names neither model nor effort (or
# no route) launches as before: no arguments, so the dispatcher passes -ModelPolicy shape and the runner maps the
# level through the profile. A route model launches -ModelPolicy fixed with it; a route effort goes in a record that
# names only claude and the effort, which the runner takes ahead of the profile's effortByModel (rule 42 precedence).
#
# -Status: a code-complete ticket (Implemented, BlockNeedUserTest) is an audit of code the tree already carries, and the
# runner's shape policy caps it at the cheap model; a fixed route model would lift that cap, so such a pass launches as
# before (shape) whatever the route.
#
# -Flagged (S0140): the ticket's spec carries the `**Parallel:**` flag. With a route row naming `parallel` and a build
# status (Get-PqClaudeParallel), the pass also gets -Parallel for the runner, which appends the workflow opt-in.
$script:PqClaudeShapeStatuses = @('Implemented', 'BlockNeedUserTest')
$script:PqParallelStatuses = @('Approved', 'Tactical', 'In Progress', 'Partial', 'Broken')

# The parallel axis a claude pass launches with (S0140): the route's `parallel` value when the spec carries the flag
# and the status is a build stage; '' otherwise (an audit, a spec pass, an unflagged ticket, no such route key).
function Get-PqClaudeParallel($Pick, [string]$Status = '', [bool]$Flagged = $false) {
    $route = if ($null -ne $Pick) { $Pick.route } else { $null }
    if ($null -eq $route -or -not $Flagged) { return '' }
    $p = [string](Get-PqValue $route 'parallel' '')
    if (-not $p) { return '' }
    if ($script:PqParallelStatuses -cnotcontains $Status) { return '' }
    return $p
}

function Get-PqClaudePassArgs($Pick, [string]$Status = '', [bool]$Flagged = $false) {
    $route = if ($null -ne $Pick) { $Pick.route } else { $null }
    $parallel = Get-PqClaudeParallel $Pick $Status $Flagged
    if ($parallel -and ($null -eq $route -or (-not $route.model -and -not $route.effort))) {
        $args_ = @('-ModelPolicy', 'shape', '-Parallel', $parallel)
        if ($Pick.template) { $args_ += @('-PromptTemplate', [string]$Pick.template) }
        return [string[]]$args_
    }
    if ($null -eq $route -or (-not $route.model -and -not $route.effort)) { return [string[]]@() }
    if ($Status -and $script:PqClaudeShapeStatuses -ccontains $Status) { return [string[]]@() }
    $args_ = @()
    if ($parallel) { $args_ += @('-Parallel', $parallel) }
    if ($route.effort) {
        $rec = [ordered]@{ name = 'claude'; effort = [string]$route.effort }
        $args_ += @('-AgentJson', (ConvertTo-Json -InputObject $rec -Compress))
    }
    if ($route.model) { $args_ += @('-ModelPolicy', 'fixed', '-Model', [string]$route.model) }
    else { $args_ += @('-ModelPolicy', 'shape') }
    if ($Pick.template) { $args_ += @('-PromptTemplate', [string]$Pick.template) }
    return [string[]]$args_
}

# The runner's arguments for a pass of a non-Claude agent: the record (rule 42), its fixed model, and the prompt form.
# The name scopes the runner's own limit hold to this provider, the detector's pattern is how the runner recognises
# this provider's limit in the pass's output (so the output is captured: -Quiet), and env is how a provider reached
# through another CLI's environment (z.ai) is told where to go; a value may name a variable as %NAME%.
function Get-PqAgentPassArgs($Pick) {
    $a = $Pick.record
    # The route of the pick may name another model and a lower effort for this grade (TASK-FLOW 0.32 item B).
    $launch = Get-PqPickLaunch $Pick
    $rec = [ordered]@{ name = [string]$a.name; command = [string]$a.command; argsTemplate = @($a.argsTemplate); effort = $launch.effort }
    if (Test-PqHasKey $a 'headlessMatch') { $rec.headlessMatch = [string]$a.headlessMatch }
    $pattern = [string](Get-PqValue (Get-PqValue $a 'limitDetector') 'pattern' '')
    if ($pattern) { $rec.limitPattern = $pattern }
    $env_ = Get-PqValue $a 'env'
    if ($null -ne $env_) { $rec.env = $env_ }
    $args_ = @('-AgentJson', (ConvertTo-Json -InputObject $rec -Compress -Depth 8), '-ModelPolicy', 'fixed', '-Model', $launch.model)
    if ($pattern) { $args_ += '-Quiet' }
    if ($Pick.template) { $args_ += @('-PromptTemplate', [string]$Pick.template) }
    return [string[]]$args_
}

# When a hold stops holding: its `until`, else the time it was written plus limitPollMinutes (then one probe pass).
function Get-PqHoldRelease($Hold, $Agent) {
    if ($null -eq $Hold) { return $null }
    try {
        $until = Get-PqValue $Hold 'until'
        if ($until) { return [DateTimeOffset]::Parse([string]$until) }
        $poll = [int](Get-PqValue $Agent 'limitPollMinutes' 30)
        return [DateTimeOffset]::Parse([string](Get-PqValue $Hold 'writtenAt')).AddMinutes($poll)
    }
    catch { return $null }
}

# Why no provider of the order may take a ticket now, for the one line the worker prints: each passed-over provider
# with the time its limit lifts, or the other reason (maxParallel, levelNotAllowed, noPipelineForm).
function Get-PqNoAgentSummary {
    param([Parameter(Mandatory)]$Pick, [Parameter(Mandatory)]$Registry)
    $byName = @{}
    foreach ($a in @($Registry.agents)) { $byName[[string]$a.name] = $a }
    $parts = foreach ($fb in @($Pick.fallbacks)) {
        if ($fb.why -ceq 'limit') {
            $rel = Get-PqHoldRelease (Get-PqAgentHold $fb.from) $byName[[string]$fb.from]
            if ($rel) { "$($fb.from): usage limit, back at $($rel.LocalDateTime.ToString('yyyy-MM-dd HH:mm'))" } else { "$($fb.from): usage limit" }
        }
        elseif ($fb.why -ceq 'aboveCeiling') { "$($fb.from): grade $($Pick.score) above its ceiling $(Get-PqAgentCeiling $byName[[string]$fb.from])" }
        else { "$($fb.from): $($fb.why)" }
    }
    return (@($parts) -join '; ')
}

# What the runner read of a pass that ended on a usage limit: the reset time it wrote to the repository's
# limit-hold[.<agent>].json, as the ISO time the machine-wide hold takes (a minute's margin past it), or $null when the
# limit named no time (the hold then polls). A time already past carries no information and is $null as well.
function Get-PqRunnerLimitUntil {
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][string]$Agent)
    try {
        $paths = Get-PqRepoPaths -RepoPath $RepoPath
        $file = Join-Path $paths.RunsDir $(if ($Agent -ceq 'claude') { 'limit-hold.json' } else { "limit-hold.$Agent.json" })
        if (-not [IO.File]::Exists($file)) { return $null }
        $resets = Get-PqValue (ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($file))) 'resetsAt'
        if ($null -eq $resets) { return $null }
        $n = [int64]$resets
        if ($n -gt 100000000000) { $n = [int64][Math]::Floor($n / 1000) }
        $at = [DateTimeOffset]::FromUnixTimeSeconds($n).AddSeconds(60)
        if ($at -le [DateTimeOffset]::UtcNow) { return $null }
        return $at.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    }
    catch { return $null }
}

# A provider's UTC offset text (`+08:00`, `-05:30`, `3:00`) as a timespan, the one reading the ISO, the dated and the clock
# forms of a limit text share. An empty or unreadable offset returns $null: the clock time is then this machine's own.
function ConvertTo-PqLimitZone {
    param([string]$Offset = '')
    if ($Offset -match '^\s*([+-]?)(\d{1,2}):(\d{2})\s*$') {
        $zone = [timespan]::new([int]$Matches[2], [int]$Matches[3], 0)
        if ($Matches[1] -ceq '-') { $zone = $zone.Negate() }
        return $zone
    }
    return $null
}

# The dated form of a limit that lifts on another day (Codex's weekly limit): "try again at Nov 19th, 2026 11:35 PM".
# The caller hands over a whole pass log, and a log quotes limit texts (source lines, test fixtures), so the form counts
# only when it is the LAST limit-shaped text of the log - the real message ends it - and only when the time lies within
# eight days: a quoted fixture from another year must not park a provider. Anything else returns $null, and the clock
# and span forms are tried as before.
function Get-PqDatedLimitTime {
    param([string]$Text, [string]$Offset = '', [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow)
    $all =[regex]::Matches($Text, '(?i)(?:try again|retry|resets?)\s+(?:at|on)\s+(?<mon>[a-z]{3,9})\.?\s+(?<day>\d{1,2})(?:st|nd|rd|th)?,?\s+(?<year>\d{4}),?\s+(?:at\s+)?(?<time>\d{1,2}:\d{2}(?::\d{2})?\s*(?:[ap]\.?m\.?)?)')
    if ($all.Count -eq 0) { return $null }
    $m = $all[$all.Count - 1]
    $other = [regex]::Matches($Text, '(?i)(?:try again|retry|resets?)\s+(?:at|on)\s+\d{1,2}:\d{2}|resets?\s+in\s+\d')
    if ($other.Count -gt 0 -and $other[$other.Count - 1].Index -gt $m.Index) { return $null }
    $mon = $m.Groups['mon'].Value.Substring(0, 3)
    $timeStr = ((($m.Groups['time'].Value -replace '\.', '') -replace '\s+', '') -replace '(?i)([ap]m)$', ' $1').Trim().ToUpperInvariant()
    $stamp = "$mon $([int]$m.Groups['day'].Value) $($m.Groups['year'].Value) $timeStr"
    $formats = [string[]]@('MMM d yyyy h:mm tt', 'MMM d yyyy h:mm:ss tt', 'MMM d yyyy H:mm', 'MMM d yyyy H:mm:ss')
    $parsed = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($stamp, $formats, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed)) { return $null }
    $zone = ConvertTo-PqLimitZone $Offset
    $at = if ($null -ne $zone) { [DateTimeOffset]::new($parsed, $zone) } else { [DateTimeOffset]::new($parsed) }
    if ($at -gt $Now.AddDays(8)) { return $null }
    return $at
}

# When the limit lifts, read from the text of a limit message (S0016, S0035):
#   `Usage limit reached for 5 hour. Your limit will reset at 2026-11-11 00:34:51`   a clock time, in the provider's zone
#   `You've hit your usage limit. Try again at 2:38 AM.`                             a daily clock time (Codex)
#   `.. or try again at Nov 19th, 2026 11:35 PM.`                                    a dated clock time (Codex, a limit of several days)
#   `Individual quota reached. .. Resets in 57h10m24s.`                              a span from now
# -Offset is the provider's UTC offset for the clock form (`+08:00` for z.ai: its reset time reads 1 h 20 min after the
# call, against 7 h 20 min if it were Kyiv time and 9 h 20 min if UTC, for a five hour window); empty reads it as this
# machine's local time. The result is the ISO UTC time the machine-wide hold takes (a minute's margin past it), or $null
# when the text names no time or names one already past.
function ConvertFrom-PqLimitText {
    param([string]$Text, [string]$Offset = '', [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $at = $null
    # The caller hands over a whole pass log, and a log quotes limit texts (source lines, test fixtures): the real
    # message ends it, so within one form the LAST match counts, never the first. Across forms the order stands
    # as it was - ISO time, dated time, clock time, span - and the span form still reads its first match.
    $isoAll = [regex]::Matches($Text, '(?i)reset(?:s)?\s+(?:at|on)\s+(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}(?::\d{2})?)')
    if ($isoAll.Count -gt 0) {
        $m = $isoAll[$isoAll.Count - 1]
        $stamp = "$($m.Groups[1].Value)T$($m.Groups[2].Value)"
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParse($stamp, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed)) {
            $zone = ConvertTo-PqLimitZone $Offset
            $at = if ($null -ne $zone) { [DateTimeOffset]::new($parsed, $zone) } else { [DateTimeOffset]::new($parsed) }
        }
    }
    elseif ($null -ne ($datedAt = Get-PqDatedLimitTime -Text $Text -Offset $Offset -Now $Now)) {
        $at = $datedAt
    }
    else {
        # S0035: Codex clock time format without date ("try again at 2:38 AM", "resets at 14:38")
        $clockAll = [regex]::Matches($Text, '(?i)(?:try again|retry|resets?)\s+(?:at|on)\s+(?<time>\d{1,2}:\d{2}(?::\d{2})?\s*(?:[ap]\.?m\.?)?)')
        if ($clockAll.Count -gt 0) {
            $mCodex = $clockAll[$clockAll.Count - 1]
            $timeStr = ($mCodex.Groups['time'].Value -replace '\.', '').Trim()
            $parsed = [datetime]::MinValue
            if ([datetime]::TryParse($timeStr, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed)) {
                $zone = ConvertTo-PqLimitZone $Offset
                $localNow = if ($null -ne $zone) { $Now.ToOffset($zone) } else { $Now.ToLocalTime() }
                $targetDate = $localNow.Date
                $candidate = [DateTimeOffset]::new($targetDate.Year, $targetDate.Month, $targetDate.Day, $parsed.Hour, $parsed.Minute, $parsed.Second, $localNow.Offset)
                if ($candidate -le $localNow) {
                    $candidate = $candidate.AddDays(1)
                }
                $at = $candidate
            }
        }
        else {
            $m = [regex]::Match($Text, '(?i)resets?\s+in\s+(?:(\d+)\s*d[a-z]*\s*)?(?:(\d+)\s*h[a-z]*\s*)?(?:(\d+)\s*m[a-z]*\s*)?(?:(\d+)\s*s[a-z]*)?')
            if ($m.Success -and ($m.Groups[1].Success -or $m.Groups[2].Success -or $m.Groups[3].Success -or $m.Groups[4].Success)) {
                $g = { param($i) if ($m.Groups[$i].Success) { [int]$m.Groups[$i].Value } else { 0 } }
                $at = $Now.Add([timespan]::new((& $g 1), (& $g 2), (& $g 3), (& $g 4)))
            }
        }
    }
    if ($null -eq $at) { return $null }
    $at = $at.AddSeconds(60)
    if ($at -le $Now) { return $null }
    return $at.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
}

# S0035: When the primary provider in agentOrder is held with a reset time <= 15 minutes away,
# an In Progress ticket waits for that reset instead of delegating to secondary fallback providers.
function Get-PqPrimaryResetWait {
    param(
        [Parameter(Mandatory)] $Registry,
        [Parameter(Mandatory)][string] $TicketStatus,
        [Parameter(Mandatory)][string] $PickedAgent,
        [DateTimeOffset] $Now = [DateTimeOffset]::UtcNow
    )
    if ($TicketStatus -ne 'In Progress') { return $null }
    $firstAgentName = if ($Registry.agentOrder -and @($Registry.agentOrder).Count -gt 0) { [string]$Registry.agentOrder[0] } else { $null }
    if (-not $firstAgentName -or -not $PickedAgent -or $PickedAgent -ceq $firstAgentName) { return $null }

    $firstHold = Get-PqAgentHold $firstAgentName
    $firstUntil = Get-PqValue $firstHold 'until'
    if (-not $firstUntil) { return $null }
    try {
        $u = [DateTimeOffset]::Parse([string]$firstUntil)
        $diffMin = ($u - $Now).TotalMinutes
        if ($diffMin -gt 0 -and $diffMin -le 15) {
            return [pscustomobject]@{
                Agent       = $firstAgentName
                Until       = $u.UtcDateTime
                UntilIso    = [string]$firstUntil
                DiffMinutes = $diffMin
            }
        }
    } catch { }
    return $null
}

# The reset time in the pass's own log (<runs folder>\<ticket>.<agent>.log or <ticket>.log, written because a record with a limit pattern runs the
# runner -Quiet): for the providers whose limit the runner could not time (resetsAt null). $null when there is none.
function Get-PqLogLimitUntil {
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][string]$TicketId, $Record)
    try {
        $paths = Get-PqRepoPaths -RepoPath $RepoPath
        $agentName = [string](Get-PqValue $Record 'name' '')
        $file = if ($agentName) { Join-Path $paths.RunsDir "$TicketId.$agentName.log" } else { $null }
        if (-not $file -or -not [IO.File]::Exists($file)) {
            $file = Join-Path $paths.RunsDir "$TicketId.log"
        }
        if (-not [IO.File]::Exists($file)) { return $null }
        $offset = [string](Get-PqValue (Get-PqValue $Record 'limitDetector') 'resetOffset' '')
        return (ConvertFrom-PqLimitText -Text ([IO.File]::ReadAllText($file)) -Offset $offset)
    }
    catch { return $null }
}

# --- The providers the owner chooses between (pq agents; the PQShell "Providers" dialog) ------------------------------
# A provider is an agent record plus how to find its CLI. The owner picks which providers spend tokens and in what
# order; agentOrder in repos.json is that choice, and the worker takes the first one that is not at its limit.
$script:PqProviders = @(
    @{ id = 'openai'; agent = 'codex'; label = 'OpenAI (Codex)'; aliases = @('openai', 'codex', 'gpt', 'chatgpt') }
    @{ id = 'anthropic'; agent = 'claude'; label = 'Anthropic (Claude)'; aliases = @('anthropic', 'claude') }
    # `also` names the provider's further records, each a model with its own quota (rule 42 gives a non-Claude agent one
    # fixed model, so a second model is a second record): they follow the first in the order, and the next one takes the
    # ticket only while the earlier is at its limit.
    @{ id = 'gemini'; agent = 'gemini'; also = @('gemini-argon'); label = 'Google (Gemini)'; aliases = @('gemini', 'google') }
    @{ id = 'zai'; agent = 'zai'; label = 'z.ai (GLM)'; aliases = @('zai', 'glm', 'zcode', 'zhipu') }
    # Mistral's own subscription (admin.mistral.ai/subscription), used through the Mistral Vibe VS Code extension: the same
    # GLM-5.3 as z.ai, hosted by Mistral, with its own "Vibe budget".
    @{ id = 'mistral'; agent = 'mistral'; label = 'Mistral (Vibe, GLM)'; aliases = @('mistral', 'vibe', 'mistralvibe') }
)

function Resolve-PqProvider([string]$Name) {
    $n = ($Name.ToLowerInvariant() -replace '[^a-z0-9]', '')
    foreach ($p in $script:PqProviders) { if ($p.aliases -contains $n) { return $p } }
    return $null
}

# The agent records of a provider in the order they take a ticket: its own, then its `also` records.
function Get-PqProviderAgents($Provider) {
    $names = [Collections.Generic.List[string]]::new()
    $names.Add([string]$Provider.agent)
    if ($Provider.ContainsKey('also')) { foreach ($n in $Provider.also) { $names.Add([string]$n) } }
    return [string[]]$names.ToArray()
}

# The JS entry of a globally installed npm CLI. npm's PATH shims are .ps1/.cmd files a process cannot start as
# itself; node can start the script they wrap.
function Find-PqNpmBin([string]$Package, [string]$Bin) {
    foreach ($root in @($(if ($env:APPDATA) { Join-Path $env:APPDATA 'npm\node_modules' }))) {
        $pj = Join-Path $root "$Package\package.json"
        if (-not $root -or -not [IO.File]::Exists($pj)) { continue }
        try {
            $b = (ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($pj))).bin
            $rel = if ($b -is [string]) { $b } else { [string](Get-PqValue $b $Bin) }
            $full = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $pj) $rel))
            if ($rel -and [IO.File]::Exists($full)) { return $full }
        }
        catch { }
    }
    return $null
}

function Find-PqApplication([string]$Name) {
    $c = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    return $null
}

# An environment variable by name: this process first, then the owner's user and machine values. A key set with setx
# after the worker or the panel started is in the registry but not in their environment.
function Get-PqEnvValue([string]$Name) {
    foreach ($scope in 'Process', 'User', 'Machine') {
        $v = [Environment]::GetEnvironmentVariable($Name, $scope)
        if ($v) { return $v }
    }
    return $null
}

# @{ found; command; prefix; note }: command and leading arguments that start the provider's CLI, or why it is not usable.
function Find-PqProviderCli([string]$Id) {
    switch ($Id) {
        'anthropic' {
            if (Find-PqApplication 'claude') { return @{ found = $true; command = 'claude'; prefix = @(); note = '' } }
            return @{ found = $false; command = $null; prefix = @(); note = 'claude is not on PATH' }
        }
        'openai' {
            $js = Find-PqNpmBin '@openai/codex' 'codex'
            if ($js -and (Find-PqApplication 'node')) { return @{ found = $true; command = 'node'; prefix = @($js); note = '' } }
            return @{ found = $false; command = $null; prefix = @(); note = 'Codex CLI not found (npm install -g @openai/codex)' }
        }
        'gemini' {
            # Gemini is Antigravity CLI (agy): Google closed the Gemini CLI to personal Google sign-ins on 2026-06-18
            # ("This client is no longer supported for Gemini Code Assist for individuals").
            $exe = Find-PqApplication 'agy'
            if (-not $exe -and $env:LOCALAPPDATA -and [IO.File]::Exists((Join-Path $env:LOCALAPPDATA 'agy\bin\agy.exe'))) { $exe = Join-Path $env:LOCALAPPDATA 'agy\bin\agy.exe' }
            if (-not $exe) { return @{ found = $false; command = $null; prefix = @(); note = 'Antigravity CLI not found (irm https://antigravity.google/cli/install.ps1 | iex)' } }
            # A pass with no sign-in fails at once with no limit text: an ordinary failed pass, and a night of those
            # drops tickets. agy reuses the Antigravity sign-in; its state folder appears once it has run signed in.
            if (-not ($env:USERPROFILE -and [IO.Directory]::Exists((Join-Path $env:USERPROFILE '.gemini\antigravity-cli')))) { return @{ found = $false; command = $null; prefix = @(); note = 'Antigravity CLI is not signed in: run "agy" once and sign in with Google' } }
            return @{ found = $true; command = $exe; prefix = @(); note = '' }
        }
        'zai' {
            # z.ai's coding plan is reached through Claude Code, pointed at z.ai's Anthropic-compatible endpoint with the
            # owner's API key (docs.z.ai, Claude Code). ZCode's own CLI is not used: it needs the desktop app's runtime.
            if (-not (Find-PqApplication 'claude')) { return @{ found = $false; command = $null; prefix = @(); note = 'claude is not on PATH (z.ai runs through Claude Code)' } }
            if (-not (Get-PqEnvValue 'ZAI_API_KEY')) { return @{ found = $false; command = $null; prefix = @(); note = 'set the user environment variable ZAI_API_KEY to a key from z.ai/manage-apikey' } }
            return @{ found = $true; command = 'claude'; prefix = @(); note = '' }
        }
        'mistral' {
            # Mistral Vibe ships as a VS Code extension whose only binary is vibe-acp.exe (an ACP server, no `vibe -p`);
            # vibe-acp-pass.ps1 beside this folder is the headless client, run by PowerShell. The sign-in is the extension's
            # own Credential Manager entry, so a pass without it would end in a second with no limit text.
            $pwsh = Find-PqApplication 'pwsh'
            if (-not $pwsh) { return @{ found = $false; command = $null; prefix = @(); note = 'pwsh is not on PATH (the Vibe client is a PowerShell script)' } }
            $acp = $null
            foreach ($root in @('.vscode', '.vscode-insiders')) {
                $ext = Join-Path $HOME "$root\extensions"
                if (-not [IO.Directory]::Exists($ext)) { continue }
                foreach ($dir in [IO.Directory]::GetDirectories($ext, 'mistralai.mistral-vibe-code-*')) {
                    $exe = Join-Path $dir 'bin\vibe-acp.exe'
                    if ([IO.File]::Exists($exe) -and (-not $acp -or [IO.File]::GetLastWriteTimeUtc($exe) -gt [IO.File]::GetLastWriteTimeUtc($acp))) { $acp = $exe }
                }
            }
            if (-not $acp) { $acp = Find-PqApplication 'vibe-acp' }
            if (-not $acp) { return @{ found = $false; command = $null; prefix = @(); note = 'Mistral Vibe not found (install the "Mistral Vibe" extension in VS Code)' } }
            if (-not ((& cmdkey.exe /list:ai.mistral.vibe 2>$null) -match 'ai\.mistral\.vibe')) { return @{ found = $false; command = $null; prefix = @(); note = 'Mistral Vibe is not signed in: open the extension in VS Code and sign in' } }
            return @{ found = $true; command = $pwsh; prefix = @(); note = '' }
        }
    }
    return @{ found = $false; command = $null; prefix = @(); note = "no provider '$Id'" }
}

# The shipped record of a provider, built against the CLI found on this machine: @{ ok; record; why }. -Agent names one
# of the provider's `also` records; it is empty for the provider's own.
function New-PqProviderRecord([string]$Id, [string]$Agent = '') {
    $cli = Find-PqProviderCli $Id
    if (-not $cli.found) { return @{ ok = $false; record = $null; why = $cli.note } }
    $common = [ordered]@{ levels = @('light', 'medium', 'hard'); identityVar = 'SZA_AGENT_ID'; halt = 'none'; limitPollMinutes = 30 }
    $rec = $null
    switch ($Id) {
        'anthropic' {
            $rec = [ordered]@{
                name = 'claude'; command = 'claude'
                argsTemplate = @('-p', '{prompt}', '--permission-mode', '{permissionMode}', '--model', '{model}')
                headlessMatch = '(?i)\bclaude(\.exe)?\s.*(-p|--print)\b'; promptForm = 'slash'
                modelByComplexity = [ordered]@{ light = 'haiku'; medium = 'sonnet'; hard = 'opus' }
                maxParallel = 5; contractFile = 'CLAUDE.md'
                limitDetector = [ordered]@{ kind = 'transcript'; status = 'proven' }
            }
        }
        'openai' {
            $rec = [ordered]@{
                name = 'codex'; command = $cli.command
                argsTemplate = @($cli.prefix) + @('exec', '--model', '{model}', '-c', 'model_reasoning_effort="{effort}"', '--dangerously-bypass-approvals-and-sandbox', '{prompt}')
                headlessMatch = '(?i)codex\.js"?\s.*\bexec\b'; promptForm = 'file'
                model = 'gpt-6.1-terra'; effort = 'xhigh'; maxParallel = 2; contractFile = 'AGENTS.md'
                limitDetector = [ordered]@{ kind = 'exitText'; pattern = '(?i)usage limit|rate limit|quota'; status = 'unproven' }
            }
        }
        'gemini' {
            # Hydrogen is Google's model for everyday coding and agent work (fast, cheap, the successor of 3.8 Flash) and
            # takes every ticket; Argon, the deeper and costlier model, is the second record and works only while Hydrogen's
            # quota is spent.
            $isArgon = ($Agent -ceq 'gemini-argon')
            $rec = [ordered]@{
                name = $(if ($isArgon) { 'gemini-argon' } else { 'gemini' }); command = $cli.command
                # The model slug carries the effort (agy models). Each model has its own quota.
                argsTemplate = @($cli.prefix) + @('--model', '{model}', '--dangerously-skip-permissions', '--print', '{prompt}')
                headlessMatch = '(?i)agy(\.exe)?"?\s.*(-p|--print|--prompt)\b'; promptForm = 'file'
                model = $(if ($isArgon) { 'gemini-4-argon-high' } else { 'gemini-4-hydrogen-high' }); effort = 'default'; maxParallel = 2; contractFile = 'GEMINI.md'
                # Seen on 2026-10-29: "Individual quota reached. .. Resets in 57h10m24s." (RESOURCE_EXHAUSTED, exit 3).
                limitDetector = [ordered]@{ kind = 'exitText'; pattern = '(?i)quota reached|resource_exhausted|usage limit|rate limit|credits? (are )?(exhausted|exceeded)'; status = 'unproven' }
            }
        }
        'zai' {
            $rec = [ordered]@{
                name = 'zai'; command = 'claude'
                argsTemplate = @('-p', '{prompt}', '--permission-mode', '{permissionMode}', '--model', '{model}')
                headlessMatch = '(?i)\bclaude(\.exe)?\s.*(-p|--print)\b'; promptForm = 'slash'
                # The model is named, never left to z.ai's server-side mapping of Claude Code's `opus`: that mapping is not
                # disclosed, z.ai echoes the requested name back, so the console, the events log and the session transcript
                # all said `opus` while a GLM model ran. The three aliases are pinned too, so a subagent that asks for
                # `sonnet` or `haiku` is a named GLM model as well. Verified on 2026-11-16 against /v1/models and a live call.
                env = [ordered]@{
                    ANTHROPIC_BASE_URL = 'https://api.z.ai/api/anthropic'; ANTHROPIC_AUTH_TOKEN = '%ZAI_API_KEY%'; API_TIMEOUT_MS = '3000000'
                    ANTHROPIC_DEFAULT_OPUS_MODEL = 'glm-5.3'; ANTHROPIC_DEFAULT_SONNET_MODEL = 'glm-5.3'; ANTHROPIC_DEFAULT_HAIKU_MODEL = 'glm-5.3-flash'
                }
                model = 'glm-5.3'; effort = 'default'; maxParallel = 2; contractFile = 'CLAUDE.md'
                # Seen on 2026-11-10 (a real pass, exit 0, 197 s): "API Error: Request rejected (429) · [1308][Usage limit reached
                # for 5 hour. Your limit will reset at 2026-11-11 00:34:51]". The clock is China time, UTC+8.
                limitDetector = [ordered]@{ kind = 'transcript'; pattern = '(?i)usage limit reached|limit (will )?reset|limit exhausted|rate limit reached|insufficient balance|no resource package|package has expired'; status = 'proven'; resetOffset = '+08:00' }
            }
        }
        'mistral' {
            # {harnessRoot} is resolved by the runner at launch, so the record survives a plugin update. The model is the
            # option value of Vibe's own list (`glm-5-3` is zai-glm-5-3, GLM-5.3 hosted by Mistral); thinking is low or high.
            # The script prints a `[vibe] LIMIT reached:` line when the provider answers 402/429 ("Vibe budget exhausted",
            # seen in ~/.vibe/logs/vibe.log on 2026-09-12 and 2026-09-23); no reset time is given, so a hold is polled.
            $rec = [ordered]@{
                name = 'mistral'; command = $cli.command
                argsTemplate = @('-NoProfile', '-File', '{harnessRoot}\portfolio\vibe-acp-pass.ps1', '-Model', '{model}', '-Thinking', '{effort}', '-Prompt', '{prompt}')
                headlessMatch = '(?i)vibe-acp-pass\.ps1'; promptForm = 'file'
                model = 'glm-5-3'; effort = 'high'; maxParallel = 2; contractFile = 'AGENTS.md'
                limitDetector = [ordered]@{ kind = 'exitText'; pattern = '(?i)\[vibe\] limit reached'; status = 'unproven' }
            }
        }
    }
    foreach ($k in $common.Keys) { if (-not $rec.Contains($k)) { $rec[$k] = $common[$k] } }
    return @{ ok = $true; record = ([pscustomobject]$rec); why = '' }
}

# One row per provider for `pq agents`: where it stands in the order, whether its CLI is usable, and its limit hold.
function Get-PqProviderStatus {
    param([Parameter(Mandatory)]$Registry)
    $order = @($Registry.agentOrder | ForEach-Object { [string]$_ })
    $byName = @{}
    foreach ($a in @($Registry.agents)) { $byName[[string]$a.name] = $a }
    # The place counts providers, not records: a provider's records are one entry of the order.
    $providerOrder = [Collections.Generic.List[string]]::new()
    foreach ($name in $order) {
        foreach ($p in $script:PqProviders) {
            if ((@(Get-PqProviderAgents $p) -ccontains $name) -and -not $providerOrder.Contains([string]$p.id)) { $providerOrder.Add([string]$p.id) }
        }
    }
    foreach ($p in $script:PqProviders) {
        $cli = Find-PqProviderCli $p.id
        $rec = $byName[$p.agent]
        # The provider's tokens are spent only when every one of its records is at its limit; it is back when the
        # first of them is, so the row carries the earliest release among them.
        $members = @(Get-PqProviderAgents $p | Where-Object { $_ -ceq $p.agent -or $byName.ContainsKey($_) })
        $held = $true
        $first = $null
        foreach ($m in $members) {
            $mRec = $byName[$m]
            $mHold = Get-PqAgentHold $m
            if (-not (($null -ne $mHold) -and (Test-PqAgentHeld $mHold $mRec))) { $held = $false; break }
            $mRel = Get-PqHoldRelease $mHold $mRec
            if ($null -eq $first -or ($null -ne $mRel -and ($null -eq $first.rel -or $mRel -lt $first.rel))) { $first = @{ rel = $mRel; hold = $mHold } }
        }
        $rel = $(if ($held -and $first) { $first.rel } else { $null })
        [ordered]@{
            id = $p.id; agent = $p.agent; label = $p.label
            position = ($providerOrder.IndexOf([string]$p.id) + 1)
            record = ($null -ne $rec)
            cliFound = [bool]$cli.found; cliNote = [string]$cli.note
            held = [bool]$held
            holdUntil = $(if ($held -and $rel) { $rel.ToString('o') } else { $null })
            holdKind = $(if (-not $held) { $null } elseif (Get-PqValue $first.hold 'until') { 'resets' } else { 'probe' })
        }
    }
}

# Choose which providers spend tokens and in what order: writes agentOrder in repos.json. A provider without a record
# gets the shipped one (built against the CLI found here); a record the owner already has is never touched.
function Set-PqAgentOrder {
    param([Parameter(Mandatory)][string[]]$Names, [switch]$Log, [string]$RegistryPath)
    if (-not $RegistryPath) { $RegistryPath = Get-PqPath -Kind registry }
    $picked = [Collections.Generic.List[object]]::new()
    foreach ($n in $Names) {
        $p = Resolve-PqProvider $n
        if ($null -eq $p) { return @{ ok = $false; changed = $false; error = 'UnknownProvider'; message = "no provider '$n'; choose from: $(@($script:PqProviders | ForEach-Object { $_.id }) -join ', ')" } }
        if (-not $picked.Contains($p)) { $picked.Add($p) }
    }
    if ($picked.Count -eq 0) { return @{ ok = $false; changed = $false; error = 'AgentOrderEmpty'; message = 'choose at least one provider' } }
    $cur = Read-PqRegistryForWrite $RegistryPath
    if (-not $cur.ok) { return @{ ok = $false; changed = $false; error = $cur.error; message = $cur.message } }
    $doc = $cur.document
    $records = [Collections.Generic.List[object]]::new()
    if (Test-PqHasKey $doc 'agents') { foreach ($a in @($doc.agents)) { $records.Add($a) } }
    else {
        # The registry had no agents: its implicit claude record becomes explicit, as the order now names more than one.
        $claude = New-PqProviderRecord 'anthropic'
        if ($claude.ok) { $records.Add($claude.record) }
    }
    $have = @($records | ForEach-Object { [string](Get-PqValue $_ 'name') })
    foreach ($p in $picked) {
        foreach ($agentName in @(Get-PqProviderAgents $p)) {
            if ($have -contains $agentName) { continue }
            $new = New-PqProviderRecord $p.id $(if ($agentName -cne $p.agent) { $agentName } else { '' })
            if (-not $new.ok) { return @{ ok = $false; changed = $false; error = 'ProviderUnavailable'; message = "$($p.label): $($new.why)" } }
            $records.Add($new.record)
            $have += $agentName
        }
    }
    # A provider's records stay together, its own first: the order is chosen per provider, not per record.
    $names = [string[]]@($picked | ForEach-Object { Get-PqProviderAgents $_ })
    $before = if (Test-PqHasKey $doc 'agentOrder') { (@($doc.agentOrder) -join ',') } else { '' }
    $doc | Add-Member -NotePropertyName agents -NotePropertyValue @($records) -Force
    $doc | Add-Member -NotePropertyName agentOrder -NotePropertyValue $names -Force
    $check = Test-PqRegistry -Registry $doc
    if (-not $check.ok) {
        $first = @($check.errors)[0]
        return @{ ok = $false; changed = $false; error = $first.name; message = "the new order would make the registry invalid: $($first.where) - $($first.message)" }
    }
    $w = Write-PqRegistry -Registry $doc -Path $RegistryPath -ExpectedHash $cur.hash
    if (-not $w.ok) { return @{ ok = $false; changed = $false; error = $w.error; message = $w.message } }
    if ($Log) { $null = Write-PqLibEvent 'registry.changed' ([ordered]@{ by = 'cli'; added = @(); removed = @(); hash = $w.hash }) }
    return @{ ok = $true; changed = ($before -cne ($names -join ',')); error = $null; message = $null }
}

# --- Routes, raters and escalateBy (TASK-FLOW 0.32/0.33; pq agents -Settings / -Apply; the PQShell Routes dialog, S0141) --
# The settings the owner edits beside the provider order: each agent record's `routes`, the registry's `raters` and
# `escalateBy`. Read as one object; written by Set-PqAgentSettings, which touches only the keys it is given and keeps
# every other key of a record (rule 41).

# The provider of an agent record (its label), '' when the record belongs to none.
function Get-PqAgentProviderLabel([string]$AgentName) {
    foreach ($p in $script:PqProviders) { if (@(Get-PqProviderAgents $p) -ccontains $AgentName) { return [string]$p.label } }
    return ''
}

function Get-PqAgentSettings {
    param([Parameter(Mandatory)]$Registry)
    $order = @(@(Get-PqValue $Registry 'agentOrder' @()) | ForEach-Object { [string]$_ })
    $agents = foreach ($a in @(Get-PqValue $Registry 'agents' @())) {
        $name = [string](Get-PqValue $a 'name' '')
        $rows = @(foreach ($row in @(Get-PqValue $a 'routes' @())) {
                $r = [ordered]@{ max = [int](Get-PqValue $row 'max' 0) }
                foreach ($k in @('model', 'effort', 'parallel')) { $v = [string](Get-PqValue $row $k ''); if ($v) { $r[$k] = $v } }
                $r
            })
        [ordered]@{
            name = $name; provider = (Get-PqAgentProviderLabel $name)
            position = ([array]::IndexOf($order, $name) + 1)
            model = [string](Get-PqValue $a 'model' ''); effort = [string](Get-PqValue $a 'effort' '')
            ceiling = (Get-PqAgentCeiling $a); routes = $rows
        }
    }
    $raters = @(foreach ($r in @(Get-PqValue $Registry 'raters' @())) {
            $o = [ordered]@{ name = [string](Get-PqValue $r 'name' ''); command = [string](Get-PqValue $r 'command' ''); model = [string](Get-PqValue $r 'model' '') }
            $t = Get-PqValue $r 'timeoutSeconds'
            if ($null -ne $t) { $o.timeoutSeconds = [int]$t }
            $o.extra = @($r.PSObject.Properties.Name | Where-Object { $_ -cnotin @('name', 'command', 'model', 'timeoutSeconds') })
            $o
        })
    return [ordered]@{
        agents = @($agents); raters = $raters
        escalateBy = [int](Get-PqValue $Registry 'escalateBy' 2); escalateBySet = (Test-PqHasKey $Registry 'escalateBy')
    }
}

# Apply edited settings. $Settings may carry `routes` (an object: agent name -> array of rows; an empty array removes
# the agent's `routes`, so it takes every grade as before), `raters` (an array; empty removes the key, so nothing is
# rated) and `escalateBy` (an integer, or null to remove the key and keep the default 2). A key left out is not touched.
# A route row that keeps the max of an old row keeps that row's other keys; a rater keeps the keys of the old record of
# its name (argsTemplate, env). The result passes Test-PqRegistry or nothing is written. @{ ok; changed; error; message }.
function Set-PqAgentSettings {
    param([Parameter(Mandatory)]$Settings, [switch]$Log, [string]$RegistryPath)
    if (-not $RegistryPath) { $RegistryPath = Get-PqPath -Kind registry }
    $cur = Read-PqRegistryForWrite $RegistryPath
    if (-not $cur.ok) { return @{ ok = $false; changed = $false; error = $cur.error; message = $cur.message } }
    $doc = $cur.document
    $before = ConvertTo-Json -InputObject $doc -Depth 12 -Compress
    $byName = @{}
    foreach ($a in @(Get-PqValue $doc 'agents' @())) { $byName[[string](Get-PqValue $a 'name' '')] = $a }
    $known = @('max', 'model', 'effort', 'parallel')
    if (Test-PqHasKey $Settings 'routes') {
        $routeMap = $Settings.routes
        $pairs = if ($routeMap -is [Collections.IDictionary]) { @($routeMap.Keys | ForEach-Object { [pscustomobject]@{ Name = [string]$_; Value = $routeMap[$_] } }) }
        else { @($routeMap.PSObject.Properties | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Value = $_.Value } }) }
        foreach ($prop in $pairs) {
            $name = [string]$prop.Name
            $a = $byName[$name]
            if ($null -eq $a) { return @{ ok = $false; changed = $false; error = 'UnknownAgent'; message = "no agent record '$name' in the registry" } }
            $old = @(Get-PqValue $a 'routes' @())
            $rows = [Collections.Generic.List[object]]::new()
            foreach ($row in @($prop.Value)) {
                if ($null -eq $row) { continue }
                $r = [ordered]@{}
                $max = Get-PqValue $row 'max'
                $r.max = if ($max -is [string] -and $max -match '^\d+$') { [int]$max } else { $max }
                foreach ($k in @('model', 'effort', 'parallel')) { $v = [string](Get-PqValue $row $k ''); if ($v.Trim()) { $r[$k] = $v.Trim() } }
                $match = @($old | Where-Object { "$(Get-PqValue $_ 'max')" -ceq "$($r.max)" }) | Select-Object -First 1
                if ($null -ne $match) { foreach ($p in $match.PSObject.Properties) { if ($p.Name -cnotin $known) { $r[$p.Name] = $p.Value } } }
                $rows.Add([pscustomobject]$r)
            }
            if ($rows.Count -eq 0) { if (Test-PqHasKey $a 'routes') { $a.PSObject.Properties.Remove('routes') } }
            else { $a | Add-Member -NotePropertyName routes -NotePropertyValue @($rows) -Force }
        }
    }
    if (Test-PqHasKey $Settings 'raters') {
        $oldRaters = @(Get-PqValue $doc 'raters' @())
        $list = [Collections.Generic.List[object]]::new()
        foreach ($r in @($Settings.raters)) {
            if ($null -eq $r) { continue }
            $name = [string](Get-PqValue $r 'name' '')
            $o = [ordered]@{ name = $name; command = [string](Get-PqValue $r 'command' ''); model = [string](Get-PqValue $r 'model' '') }
            $t = Get-PqValue $r 'timeoutSeconds'
            if ($null -ne $t -and "$t" -ne '') { $o.timeoutSeconds = $(if ("$t" -match '^\d+$') { [int]"$t" } else { $t }) }
            $match = @($oldRaters | Where-Object { [string](Get-PqValue $_ 'name' '') -ceq $name }) | Select-Object -First 1
            if ($null -ne $match) { foreach ($p in $match.PSObject.Properties) { if ($p.Name -cnotin @('name', 'command', 'model', 'timeoutSeconds')) { $o[$p.Name] = $p.Value } } }
            $list.Add([pscustomobject]$o)
        }
        if ($list.Count -eq 0) { if (Test-PqHasKey $doc 'raters') { $doc.PSObject.Properties.Remove('raters') } }
        else { $doc | Add-Member -NotePropertyName raters -NotePropertyValue @($list) -Force }
    }
    if (Test-PqHasKey $Settings 'escalateBy') {
        $e = $Settings.escalateBy
        if ($null -eq $e) { if (Test-PqHasKey $doc 'escalateBy') { $doc.PSObject.Properties.Remove('escalateBy') } }
        else { $doc | Add-Member -NotePropertyName escalateBy -NotePropertyValue $(if ("$e" -match '^\d+$') { [int]"$e" } else { $e }) -Force }
    }
    $check = Test-PqRegistry -Registry $doc
    if (-not $check.ok) {
        $first = @($check.errors)[0]
        return @{ ok = $false; changed = $false; error = $first.name; message = "the settings would make the registry invalid: $($first.where) - $($first.message)" }
    }
    $after = ConvertTo-Json -InputObject $doc -Depth 12 -Compress
    if ($after -ceq $before) { return @{ ok = $true; changed = $false; error = $null; message = $null } }
    $w = Write-PqRegistry -Registry $doc -Path $RegistryPath -ExpectedHash $cur.hash
    if (-not $w.ok) { return @{ ok = $false; changed = $false; error = $w.error; message = $w.message } }
    if ($Log) { $null = Write-PqLibEvent 'registry.changed' ([ordered]@{ by = 'cli'; added = @(); removed = @(); hash = $w.hash }) }
    return @{ ok = $true; changed = $true; error = $null; message = $null }
}
