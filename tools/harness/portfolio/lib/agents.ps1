# The agent of a pass (TASK-FLOW rules 42 and 48; S0016 R9, R17, R26, R27): the first agent of the owner's agentOrder
# that may take the ticket, and the machine-wide per-agent hold that makes a spent agent wait while the next one works.
#
# Dot-source this file after paths.ps1, registry.ps1, ledger-watch.ps1 and loop.ps1; it defines functions only, sets
# no preference and prints nothing.
#
#   Get-PqTicketLevel -RepoPath <dir> -TicketId <id>
#       light, medium or hard from the spec's `**Complexity:**` line (rule 51, the runner's reader), or '' for none.
#   Get-PqAgentPrompt -Agent <record> -RepoPath <dir>
#       @{ ok; template; why }. slash: template $null (the repository's own runner.promptTemplate, as today). file: a
#       template that tells the agent to open the pipeline's command file, when the repository's template is a slash
#       command and that file exists (a project or user command or skill, or the plugin's own skill for /sza:<skill>);
#       a command the repository does not have falls back to the shared default, the plugin's lifecycle skill. A
#       template that is plain text is used as it is. why noPipelineForm when no command file is found.
#   Get-PqAgentHold -Name <agent> / Test-PqAgentHeld -Hold <hold> -Agent <record>
#       the hold of rule 48 (or $null), and whether it still keeps the agent out. A hold with until in the future holds;
#       one with until $null holds for limitPollMinutes after it was written, then lets one probe pass through.
#   Set-PqAgentHold -Name -Pass -Source -Detector [-Until] / Remove-PqAgentHold -Name
#       write (until only ever moves forward) or clear holds\<agent>.json.
#   Select-PqAgent -Registry <registry> -RepoPath <dir> -Level <level>
#       @{ agent; record; template; fallbacks } for the first agent that passes every test, or with agent $null when
#       none does. fallbacks lists @{ from; why } (limit, maxParallel, levelNotAllowed, noPipelineForm) for each passed over.
#
# Limits of a non-Claude agent are learned only from a fast failure that moved nothing (the `unproven` detector of
# rule 48): the pass runs in the worker's console, so its text is never read. The Claude agent keeps the repository
# runner's own transcript detector and its per-repository hold, unchanged.

$script:PqFastFailureSeconds = 120

function Get-PqTicketLevel {
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][string]$TicketId)
    try {
        $snap = Get-PqLedgerSnapshot -RepoPath $RepoPath
        if (-not $snap.tickets.Contains($TicketId)) { return '' }
        $file = [string]$snap.tickets[$TicketId].file
        if (-not $file) { return '' }
        $spec = Resolve-PqRepoPathValue $snap.root $file
        if (-not [IO.File]::Exists($spec)) { return '' }
        $raw = ''
        foreach ($line in (Get-Content -LiteralPath $spec -TotalCount 40 -Encoding UTF8)) {
            if ($line -match '^\*\*Complexity:\*\*\s*(.+?)\s*$') { $raw = $Matches[1]; break }
        }
        switch -Regex ($raw.ToLowerInvariant()) {
            '^(light|лёгкий|легкий)\b' { return 'light' }
            '^(medium|средний)\b' { return 'medium' }
            '^(hard|сложный)\b' { return 'hard' }
        }
    }
    catch { }
    return ''
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
    return ($written.AddMinutes($poll) -gt $now)
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

function Select-PqAgent {
    param([Parameter(Mandatory)]$Registry, [Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][string]$Level)
    $byName = @{}
    foreach ($a in @($Registry.agents)) { $byName[[string]$a.name] = $a }
    $fallbacks = [Collections.Generic.List[object]]::new()
    foreach ($name in @($Registry.agentOrder)) {
        $a = $byName[[string]$name]
        if ($null -eq $a) { continue }
        if (Test-PqAgentHeld (Get-PqAgentHold $name) $a) { $fallbacks.Add(@{ from = $name; why = 'limit' }); continue }
        $levels = @(Get-PqValue $a 'levels' @('light', 'medium', 'hard'))
        if ($levels -cnotcontains $Level) { $fallbacks.Add(@{ from = $name; why = 'levelNotAllowed' }); continue }
        $max = [int](Get-PqValue $a 'maxParallel' 1)
        if ((Get-PqAgentLiveCount $name) -ge $max) { $fallbacks.Add(@{ from = $name; why = 'maxParallel' }); continue }
        $prompt = Get-PqAgentPrompt -Agent $a -RepoPath $RepoPath
        if (-not $prompt.ok) { $fallbacks.Add(@{ from = $name; why = $prompt.why }); continue }
        return @{ agent = [string]$name; record = $a; template = $prompt.template; fallbacks = $fallbacks }
    }
    return @{ agent = $null; record = $null; template = $null; fallbacks = $fallbacks }
}

# The runner's arguments for a pass of a non-Claude agent: the record (rule 42), its fixed model, and the prompt form.
# The name scopes the runner's own limit hold to this provider, the detector's pattern is how the runner recognises
# this provider's limit in the pass's output (so the output is captured: -Quiet), and env is how a provider reached
# through another CLI's environment (z.ai) is told where to go; a value may name a variable as %NAME%.
function Get-PqAgentPassArgs($Pick) {
    $a = $Pick.record
    $rec = [ordered]@{ name = [string]$a.name; command = [string]$a.command; argsTemplate = @($a.argsTemplate); effort = [string](Get-PqValue $a 'effort' '') }
    if (Test-PqHasKey $a 'headlessMatch') { $rec.headlessMatch = [string]$a.headlessMatch }
    $pattern = [string](Get-PqValue (Get-PqValue $a 'limitDetector') 'pattern' '')
    if ($pattern) { $rec.limitPattern = $pattern }
    $env_ = Get-PqValue $a 'env'
    if ($null -ne $env_) { $rec.env = $env_ }
    $args_ = @('-AgentJson', (ConvertTo-Json -InputObject $rec -Compress -Depth 8), '-ModelPolicy', 'fixed', '-Model', [string]$a.model)
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

# --- The providers the owner chooses between (pq agents; the PQShell "Providers" dialog) ------------------------------
# A provider is an agent record plus how to find its CLI. The owner picks which providers spend tokens and in what
# order; agentOrder in repos.json is that choice, and the worker takes the first one that is not at its limit.
$script:PqProviders = @(
    @{ id = 'openai'; agent = 'codex'; label = 'OpenAI (Codex)'; aliases = @('openai', 'codex', 'gpt', 'chatgpt') }
    @{ id = 'anthropic'; agent = 'claude'; label = 'Anthropic (Claude)'; aliases = @('anthropic', 'claude') }
    @{ id = 'gemini'; agent = 'gemini'; label = 'Google (Gemini)'; aliases = @('gemini', 'google') }
    @{ id = 'zai'; agent = 'zai'; label = 'z.ai (GLM)'; aliases = @('zai', 'glm', 'zcode', 'zhipu') }
)

function Resolve-PqProvider([string]$Name) {
    $n = ($Name.ToLowerInvariant() -replace '[^a-z0-9]', '')
    foreach ($p in $script:PqProviders) { if ($p.aliases -contains $n) { return $p } }
    return $null
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
    }
    return @{ found = $false; command = $null; prefix = @(); note = "no provider '$Id'" }
}

# The shipped record of a provider, built against the CLI found on this machine: @{ ok; record; why }.
function New-PqProviderRecord([string]$Id) {
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
            $rec = [ordered]@{
                name = 'gemini'; command = $cli.command
                # The model slug carries the effort (agy models). Each model has its own quota.
                argsTemplate = @($cli.prefix) + @('--model', '{model}', '--dangerously-skip-permissions', '--print', '{prompt}')
                headlessMatch = '(?i)agy(\.exe)?"?\s.*(-p|--print|--prompt)\b'; promptForm = 'file'
                model = 'gemini-3.8-flash-high'; effort = 'default'; maxParallel = 2; contractFile = 'GEMINI.md'
                # Seen on 2026-10-29: "Individual quota reached. .. Resets in 57h10m24s." (RESOURCE_EXHAUSTED, exit 3).
                limitDetector = [ordered]@{ kind = 'exitText'; pattern = '(?i)quota reached|resource_exhausted|usage limit|rate limit|credits? (are )?(exhausted|exceeded)'; status = 'unproven' }
            }
        }
        'zai' {
            $rec = [ordered]@{
                name = 'zai'; command = 'claude'
                argsTemplate = @('-p', '{prompt}', '--permission-mode', '{permissionMode}', '--model', '{model}')
                headlessMatch = '(?i)\bclaude(\.exe)?\s.*(-p|--print)\b'; promptForm = 'slash'
                env = [ordered]@{ ANTHROPIC_BASE_URL = 'https://api.z.ai/api/anthropic'; ANTHROPIC_AUTH_TOKEN = '%ZAI_API_KEY%'; API_TIMEOUT_MS = '3000000' }
                model = 'opus'; effort = 'default'; maxParallel = 2; contractFile = 'CLAUDE.md'
                limitDetector = [ordered]@{ kind = 'transcript'; pattern = '(?i)usage limit reached|limit (will )?reset|limit exhausted|rate limit reached|insufficient balance|no resource package|package has expired'; status = 'unproven' }
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
    foreach ($p in $script:PqProviders) {
        $cli = Find-PqProviderCli $p.id
        $rec = $byName[$p.agent]
        $hold = Get-PqAgentHold $p.agent
        $rel = Get-PqHoldRelease $hold $rec
        $held = ($null -ne $hold) -and (Test-PqAgentHeld $hold $rec)
        [ordered]@{
            id = $p.id; agent = $p.agent; label = $p.label
            position = ([Array]::IndexOf($order, $p.agent) + 1)
            record = ($null -ne $rec)
            cliFound = [bool]$cli.found; cliNote = [string]$cli.note
            held = [bool]$held
            holdUntil = $(if ($held -and $rel) { $rel.ToString('o') } else { $null })
            holdKind = $(if (-not $held) { $null } elseif (Get-PqValue $hold 'until') { 'resets' } else { 'probe' })
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
        if ($have -contains $p.agent) { continue }
        $new = New-PqProviderRecord $p.id
        if (-not $new.ok) { return @{ ok = $false; changed = $false; error = 'ProviderUnavailable'; message = "$($p.label): $($new.why)" } }
        $records.Add($new.record)
    }
    $names = [string[]]@($picked | ForEach-Object { $_.agent })
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
