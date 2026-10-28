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
#       command and that file exists; a template that is plain text is used as it is. why noPipelineForm otherwise.
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
    $paths = Get-PqRepoPaths -RepoPath $RepoPath
    $commandFile = Find-PqCommandFile -Template $template -Paths $paths
    # A command the repository does not have falls back to the shared default, as run-spec-queue.ps1 does for Claude.
    if ($template -match '^/' -and -not $commandFile -and $template -cne $default) {
        $template = $default
        $commandFile = Find-PqCommandFile -Template $template -Paths $paths
    }
    $template = $template.Replace('{Id}', '{id}')
    if ($template -notmatch '^/(?<name>[A-Za-z0-9_:-]+)(?<rest>.*)$') { return @{ ok = $true; template = $template; why = $null } }
    $name = $Matches['name']
    $rest = $Matches['rest'].Trim()
    if (-not $commandFile) { return @{ ok = $false; template = $null; why = 'noPipelineForm' } }
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
        if ((Get-PqAgentLiveCount $name) -ge $max) { $fallbacks.Add(@{ from = $name; why = 'maxParallel' 