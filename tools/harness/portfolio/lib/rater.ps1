# The rater and the escalation of a ticket's grade (TASK-FLOW 0.32, new rule 71; canon ticket S0139).
#
# Dot-source this file after events.ps1, registry.ps1 and agents.ps1; it defines functions only, sets no preference and
# prints nothing.
#
#   Test-PqRaterDue -Registry -Info -Key -Tried
#       whether a ticket is to be graded before its pass: the registry carries raters, the line is absent,
#       unrecognised or the capture default, not pinned, the spec file exists, and this worker run has not tried it.
#   Get-PqRaterPrompt -SpecPath [-MaxChars 16000] [-Registry]
#       the shipped prompt (rater/RATER_PROMPT.md) followed by the start of the spec file; with a registry, the ladder of
#       what each grade launches (Get-PqGradeLadderLines) sits before the prompt's closing "The ticket:" line.
#   Get-PqGradeLadderLines -Registry
#       one line per grade 0-9: the first agent of agentOrder whose route takes it, its model, effort and parallel axis.
#   ConvertFrom-PqRaterAnswer -Text
#       @{ ok; score; reason; confidence; why } from the LAST JSON object of the output that names a score (braces
#       inside its strings included): score an integer 0-9, confidence high/medium/low (absent reads medium), low raises
#       the score by one (at most 9).
#   Invoke-PqRaterRecord -Rater -Prompt [-WorkingDirectory]
#       one rater record run: @{ ok; text; why } (why timeout, launchFailed, noAnswer), the prompt on the standard input
#       unless argsTemplate carries {prompt}. timeoutSeconds covers the writing of the prompt and the answer together.
#   Test-PqSpecRatingDue -SpecPath
#       whether the file's line, read now, is still one a rater may write: absent, unrecognised or the capture default.
#   Set-PqSpecComplexity -SpecPath -Line [-AllowPinned]
#       rewrite the `**Complexity:**` header line, or insert it after the header lines; the file's byte-order mark and
#       every line end are kept. A pinned line is never rewritten and a file that is not valid UTF-8 is never touched
#       (returns $false). Returns $true when it wrote.
#   Invoke-PqTicketRating -Registry -Info -RepoKey -TicketId -Log -Run -Worker
#       ask each rater in turn, write the grade and ticket.complexity (by rater), or rater.fail. @{ ok; score; rater }.
#       One worker rates a ticket at a time: a second one waits, and asks nothing when it waited or the line is graded.
#   Test-PqGradeRewritten -Before -After
#       whether a pass changed the ticket's grade itself (two level infos), so the escalation leaves it alone.
#   Get-PqEscalatedScore -Info -Outcome -StatusAfter -By
#       the raised grade after a failed pass, or -1 when nothing is to be raised; a neutral end raises nothing.
#   Invoke-PqTicketEscalation -Registry -Info -Outcome -StatusAfter -RepoKey -TicketId -Log -Run -Pass -Worker -Agent
#       write the raised grade and ticket.complexity (by escalation). Returns the new grade or -1.

$script:PqRaterPromptFile = Join-Path $PSScriptRoot '..\rater\RATER_PROMPT.md'
$script:PqRaterFailureOutcomes = @('child-failed', 'no-progress', 'timeout')
# Ends nothing counts against the ticket (TASK-FLOW 0.44 section 20 item D): no escalation, whatever status they leave.
$script:PqRaterNeutralOutcomes = @('limit-hit', 'launch-failed', 'claim-lost-before-launch', 'provider-error', 'killed', 'halted')
# The arguments of a rater record that names none: Claude Code in print mode with no built-in tool, no MCP server and no
# saved session, the prompt on the standard input (rule 71: the rater is given no tools).
$script:PqRaterDefaultArgs = @('-p', '--model', '{model}', '--tools', '', '--strict-mcp-config', '--no-session-persistence')

function Get-PqRaters($Registry) {
    if ($null -eq $Registry -or -not (Test-PqHasKey $Registry 'raters')) { return @() }
    return @(@($Registry.raters) | Where-Object { $null -ne $_ })
}

function Test-PqRaterDue($Registry, $Info, [string]$Key, $Tried) {
    if (@(Get-PqRaters $Registry).Count -eq 0) { return $false }
    if ($null -eq $Info -or -not $Info.spec) { return $false }
    if ($null -ne $Tried -and $Tried.ContainsKey($Key)) { return $false }
    if ($Info.pinned) { return $false }
    if ($Info.why -cin @('noLine', 'unrecognised')) { return $true }
    return [bool]$Info.captureDefault
}

function Get-PqRaterPrompt([string]$SpecPath, [int]$MaxChars = 16000, $Registry = $null) {
    $head = [IO.File]::ReadAllText($script:PqRaterPromptFile, [Text.Encoding]::UTF8)
    $spec = [IO.File]::ReadAllText($SpecPath, [Text.Encoding]::UTF8)
    # The ticket's own Complexity line is left out, so the rater is not anchored on the capture default or an old grade.
    $spec = [regex]::Replace($spec, '(?m)^\*\*Complexity:\*\*[^\r\n]*\r?\n?', '')
    if ($spec.Length -gt $MaxChars) { $spec = $spec.Substring(0, $MaxChars) + "`n[.. the rest of the file is left out]" }
    $head = $head.TrimEnd()
    $ladder = @(Get-PqGradeLadderLines $Registry)
    if ($ladder.Count -gt 0) {
        # The ladder goes before the closing "The ticket:" line, so the ticket still follows that line directly.
        $cut = $head.LastIndexOf('The ticket:')
        $block = "What each grade launches now (the first provider of the owner's order whose route takes it; a later provider takes over only while the earlier one is at its usage limit):`n`n" +
            ($ladder -join "`n") + "`n`nThe table is there so you see what a grade costs: grade by the anchors above, and a grade one step too high spends a stronger model or a higher effort for nothing."
        if ($cut -ge 0) { $head = $head.Substring(0, $cut).TrimEnd() + "`n`n" + $block + "`n`n" + $head.Substring($cut) }
        else { $head = $head + "`n`n" + $block }
    }
    return ($head + "`n`n" + $spec)
}

# What each grade launches under the registry (rule 71 helper, owner's request 2026-11-20): one line per grade 0-9 naming
# the first agent of agentOrder whose route takes it, with the route's model and effort (the record's when the row names
# none; Claude's empty model is its level map) and the parallel axis a row names. Limit holds are ignored on purpose: the
# grade is written into the spec for good and must not follow a quota that resets in hours. An empty array without a
# registry, an order or any agent.
function Get-PqGradeLadderLines($Registry) {
    if ($null -eq $Registry -or -not (Test-PqHasKey $Registry 'agents')) { return @() }
    $byName = @{}
    foreach ($a in @($Registry.agents)) { if ($null -ne $a) { $byName[[string](Get-PqValue $a 'name' '')] = $a } }
    $order = @(@(Get-PqValue $Registry 'agentOrder' @()) | ForEach-Object { [string]$_ } | Where-Object { $_ -and $byName.ContainsKey($_) })
    if ($order.Count -eq 0) { return @() }
    $lines = [Collections.Generic.List[string]]::new()
    for ($g = 0; $g -le 9; $g++) {
        $text = 'no provider takes it'
        foreach ($name in $order) {
            $a = $byName[$name]
            $route = Get-PqAgentRoute $a $g
            if (-not $route.ok) { continue }
            $model = if ($route.model) { [string]$route.model } elseif ($name -cne 'claude') { [string](Get-PqValue $a 'model' '') } else { '' }
            $effort = if ($route.effort) { [string]$route.effort } elseif ($name -cne 'claude') { [string](Get-PqValue $a 'effort' '') } else { '' }
            $parts = @($name)
            if ($model) { $parts += $model }
            if ($effort -and $effort -cne 'default') { $parts += "effort $effort" }
            $text = $parts -join ' '
            if ($route.parallel) { $text += " + parallel ($($route.parallel)) when the spec carries the Parallel flag" }
            break
        }
        $lines.Add("- $g - $text")
    }
    return $lines.ToArray()
}

# The index of the brace that closes the one at Start, braces inside JSON strings not counted; -1 when none does.
function Find-PqJsonObjectEnd([string]$Text, [int]$Start) {
    $depth = 0
    $inString = $false
    for ($i = $Start; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($inString) {
            if ($c -eq '\') { $i++ }
            elseif ($c -eq '"') { $inString = $false }
        }
        elseif ($c -eq '"') { $inString = $true }
        elseif ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') {
            $depth--
            if ($depth -eq 0) { return $i }
        }
    }
    return -1
}

# The JSON object of the output that has a `score` member of its own and ends last, or $null: an earlier draft loses to
# the final object, and an object nested in a scored one loses to the one around it.
function Find-PqRaterObject([string]$Text) {
    $best = $null
    $bestEnd = -1
    foreach ($m in [regex]::Matches($Text, '\{(?=\s*")')) {
        $end = Find-PqJsonObjectEnd $Text $m.Index
        if ($end -le $bestEnd) { continue }
        $json = $Text.Substring($m.Index, $end - $m.Index + 1)
        if (-not $json.Contains('"score"')) { continue }
        try { $obj = ConvertFrom-Json -InputObject $json -ErrorAction Stop } catch { continue }
        if (@($obj.PSObject.Properties.Name) -cnotcontains 'score') { continue }
        $best = $obj
        $bestEnd = $end
    }
    return $best
}

function ConvertFrom-PqRaterAnswer([string]$Text) {
    $res = @{ ok = $false; score = -1; reason = ''; confidence = ''; why = 'noAnswer' }
    if ([string]::IsNullOrWhiteSpace($Text)) { return $res }
    $obj = Find-PqRaterObject $Text
    if ($null -eq $obj) { $res.why = 'invalid'; return $res }
    $s = $obj.score
    $n = -1
    if ($s -is [int] -or $s -is [long]) { $n = [int]$s }
    elseif ($s -is [string] -and $s -match '^\s*[0-9]\s*$') { $n = [int]$s.Trim() }
    if ($n -lt 0 -or $n -gt 9) { $res.why = 'invalid'; return $res }
    $conf = if ($obj.PSObject.Properties['confidence'] -and $obj.confidence) { ([string]$obj.confidence).Trim().ToLowerInvariant() } else { 'medium' }
    if ($conf -cnotin @('high', 'medium', 'low')) { $res.why = 'invalid'; return $res }
    $reason = if ($obj.PSObject.Properties['reason'] -and $obj.reason) { ([string]$obj.reason -replace '[\r\n\t]+', ' ').Trim() } else { '' }
    if ($reason.Length -gt 160) { $reason = $reason.Substring(0, 157) + '..' }
    if ($conf -ceq 'low' -and $n -lt 9) { $n++ }
    return @{ ok = $true; score = $n; reason = $reason; confidence = $conf; why = '' }
}

function Expand-PqRaterValue([string]$Value) {
    return [regex]::Replace($Value, '%([A-Za-z_][A-Za-z0-9_]*)%', { param($m) [Environment]::GetEnvironmentVariable($m.Groups[1].Value) })
}

function Invoke-PqRaterRecord($Rater, [string]$Prompt, [string]$WorkingDirectory = '') {
    $command = [string](Get-PqValue $Rater 'command' '')
    $model = [string](Get-PqValue $Rater 'model' '')
    $timeout = [int](Get-PqValue $Rater 'timeoutSeconds' 120)
    $template = @(Get-PqValue $Rater 'argsTemplate' $script:PqRaterDefaultArgs)
    $exe = Get-Command $command -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $exe) { return @{ ok = $false; text = ''; why = 'launchFailed' } }
    $viaArg = $false
    $argv = [Collections.Generic.List[string]]::new()
    foreach ($t in $template) {
        $s = [string]$t
        if ($s.Contains('{prompt}')) { $viaArg = $true; $s = $s.Replace('{prompt}', $Prompt) }
        $argv.Add($s.Replace('{model}', $model))
    }
    $psi = [Diagnostics.ProcessStartInfo]::new($exe.Source)
    foreach ($a in $argv) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    if ($WorkingDirectory -and [IO.Directory]::Exists($WorkingDirectory)) { $psi.WorkingDirectory = $WorkingDirectory }
    $env_ = Get-PqValue $Rater 'env'
    if ($null -ne $env_) {
        foreach ($p in $env_.PSObject.Properties) { $psi.Environment[[string]$p.Name] = Expand-PqRaterValue ([string]$p.Value) }
    }
    $proc = $null
    try { $proc = [Diagnostics.Process]::Start($psi) } catch { return @{ ok = $false; text = ''; why = 'launchFailed' } }
    try {
        # One time budget from here: a CLI that never reads its standard input blocks the write once the pipe is full.
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $left = { [int][Math]::Max(0, $timeout * 1000 - $clock.ElapsedMilliseconds) }
        $out = $proc.StandardOutput.ReadToEndAsync()
        $err = $proc.StandardError.ReadToEndAsync()
        $write = $null
        $inTime = $true
        if (-not $viaArg) {
            $bytes = [Text.Encoding]::UTF8.GetBytes($Prompt)
            $write = $proc.StandardInput.BaseStream.WriteAsync($bytes, 0, $bytes.Length)
            $inTime = $write.Wait((& $left))
            if ($inTime) {
                $write = $proc.StandardInput.BaseStream.FlushAsync()
                $inTime = $write.Wait((& $left))
            }
        }
        if ($inTime) {
            $proc.StandardInput.Close()
            $inTime = $proc.WaitForExit((& $left))
        }
        if (-not $inTime) {
            & taskkill.exe /PID $proc.Id /T /F 2>&1 | Out-Null
            # The killed child breaks the pipe, which ends a pending write.
            if ($null -ne $write) { try { $null = $write.Wait(2000) } catch { } }
            return @{ ok = $false; text = ''; why = 'timeout' }
        }
        $proc.WaitForExit()
        $text = [string]$out.Result
        if ($proc.ExitCode -ne 0 -and -not $text.Trim()) { $text = [string]$err.Result; return @{ ok = $false; text = $text; why = 'noAnswer' } }
        return @{ ok = $true; text = $text; why = '' }
    }
    catch { return @{ ok = $false; text = ''; why = 'launchFailed' } }
    finally { if ($null -ne $proc) { try { $proc.Dispose() } catch { } } }
}

function Test-PqSpecRatingDue([string]$SpecPath) {
    try { $lines = [string[]][IO.File]::ReadAllLines($SpecPath, [Text.Encoding]::UTF8) } catch { return $false }
    $hit = Find-SzaComplexityLine $lines
    if ($hit.index -lt 0) { return $true }
    $g = ConvertFrom-SzaComplexityValue $hit.value
    if (-not $g.recognised) { return $true }
    return (-not $g.numeric -and $g.level -ceq 'medium' -and $hit.value -imatch 'not assessed at capture')
}

function Set-PqSpecComplexity([string]$SpecPath, [string]$Line, [switch]$AllowPinned) {
    $bytes = [IO.File]::ReadAllBytes($SpecPath)
    $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $skip = if ($bom) { 3 } else { 0 }
    # Strict decoding: a file in another encoding would lose its non-ASCII characters on the way back.
    try { $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes, $skip, $bytes.Length - $skip) } catch { return $false }
    # The captured separators keep every line's own end: even places hold the lines, odd places the ends.
    $parts = [Collections.Generic.List[string]]::new([string[]][regex]::Split($text, '(\r\n|\n)'))
    $lines = [string[]]@(for ($i = 0; $i -lt $parts.Count; $i += 2) { $parts[$i] })
    $hit = Find-SzaComplexityLine $lines
    if ($hit.index -ge 0) {
        $old = ConvertFrom-SzaComplexityValue $hit.value
        if ($old.pinned -and -not $AllowPinned) { return $false }
        if ($lines[$hit.index] -ceq $Line) { return $false }
        $parts[2 * $hit.index] = $Line
    }
    else {
        # After the header lines: the last `**Label:**` line of the first block that follows the title.
        $at = -1
        $n = [Math]::Min($lines.Count, 40)
        for ($i = 0; $i -lt $n; $i++) {
            if ($lines[$i] -match '^## ') { break }
            if ($lines[$i] -match '^\*\*[^*]+:\*\*') { $at = $i }
        }
        if ($at -lt 0) { $at = 0 }
        $end = 2 * $at + 1
        if ($end -lt $parts.Count) {
            # The new line goes after that line's end and takes the same one.
            $parts.InsertRange($end + 1, [string[]]@($Line, $parts[$end]))
        }
        else {
            $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
            $parts.AddRange([string[]]@($nl, $Line))
        }
    }
    $outText = [string]::Join('', $parts)
    $enc = [Text.UTF8Encoding]::new($bom)
    $tmp = "$SpecPath.rate.tmp"
    [IO.File]::WriteAllText($tmp, $outText, $enc)
    Move-Item -LiteralPath $tmp -Destination $SpecPath -Force
    return $true
}

function Get-PqComplexityDirection([int]$From, [int]$To) {
    if ($From -lt 0) { return 'set' }
    if ($To -gt $From) { return 'raise' }
    if ($To -lt $From) { return 'lower' }
    return 'set'
}

function Get-PqRatingLockName([string]$RepoKey, [string]$TicketId) {
    $key = ((Get-PqRoot) + '|rate|' + $RepoKey + ':' + $TicketId).ToLowerInvariant()
    return 'sza-pq-rate-' + [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($key)))
}

function Invoke-PqTicketRating($Registry, $Info, [string]$RepoKey, [string]$TicketId, $Log, [string]$Run, $Worker) {
    $nothing = @{ ok = $false; score = -1; rater = '' }
    # Longer than the whole chain of raters may take in the worker that holds the lock.
    $waitMs = 30000
    foreach ($r in @(Get-PqRaters $Registry)) { $waitMs += 1000 * [int](Get-PqValue $r 'timeoutSeconds' 120) }
    $mutex = [Threading.Mutex]::new($false, (Get-PqRatingLockName $RepoKey $TicketId))
    $held = $false
    $waited = $false
    try {
        try {
            $held = $mutex.WaitOne(0)
            if (-not $held) { $held = $mutex.WaitOne($waitMs); $waited = $held }
        }
        # The holder died in the middle of its rating: nobody has answered, so this worker asks.
        catch [Threading.AbandonedMutexException] { $held = $true }
        if (-not $held -or $waited -or -not (Test-PqSpecRatingDue $Info.spec)) { return $nothing }
        return Invoke-PqRaterChain $Registry $Info $RepoKey $TicketId $Log $Run $Worker
    }
    finally {
        if ($held) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

# The rating itself, run under the ticket's lock by Invoke-PqTicketRating alone.
function Invoke-PqRaterChain($Registry, $Info, [string]$RepoKey, [string]$TicketId, $Log, [string]$Run, $Worker) {
    $tried = [Collections.Generic.List[string]]::new()
    $lastWhy = 'noAnswer'
    $prompt = $null
    try { $prompt = Get-PqRaterPrompt -SpecPath $Info.spec -Registry $Registry } catch { $prompt = $null }
    if ($null -ne $prompt) {
        foreach ($r in @(Get-PqRaters $Registry)) {
            $rname = [string](Get-PqValue $r 'name' 'rater')
            $tried.Add($rname)
            # A neutral folder, not the repository: the rater reads the prompt, never the project's agent rules or files.
            $run_ = Invoke-PqRaterRecord -Rater $r -Prompt $prompt -WorkingDirectory ([IO.Path]::GetTempPath())
            if (-not $run_.ok) { $lastWhy = $run_.why; continue }
            $ans = ConvertFrom-PqRaterAnswer $run_.text
            if (-not $ans.ok) { $lastWhy = $ans.why; continue }
            $model = [string](Get-PqValue $r 'model' '')
            $reason = if ($ans.reason) { $ans.reason } else { 'no reason given' }
            $line = Format-SzaComplexityLine -Score $ans.score -Reason ("rated by {0} ({1}): {2}" -f $model, $ans.confidence, $reason)
            # Read again: the owner or a pass may have written a grade while the model was answering.
            if (-not (Test-PqSpecRatingDue $Info.spec)) { return @{ ok = $false; score = -1; rater = '' } }
            $wrote = $false
            try { $wrote = Set-PqSpecComplexity -SpecPath $Info.spec -Line $line } catch { $wrote = $false }
            if (-not $wrote) { $lastWhy = 'invalid'; break }
            $d = [ordered]@{}
            if ($Info.level) { $d.from = [string]$Info.level }
            $d.to = Get-SzaComplexityBand $ans.score
            $d.by = 'rater'
            $d.direction = Get-PqComplexityDirection $(if ($Info.numeric) { [int]$Info.score } else { -1 }) $ans.score
            $d.reason = ConvertTo-PqCut $reason 60
            $d.score = $ans.score
            if ($Info.numeric) { $d.fromScore = [int]$Info.score }
            $d.rater = "$rname/$model"
            $d.confidence = $ans.confidence
            $null = Write-PqEvent -Log $Log -Ev 'ticket.complexity' -Run $Run -Repo $RepoKey -Id $TicketId -Worker $Worker -Cx $d.to -D $d
            return @{ ok = $true; score = $ans.score; rater = "$rname/$model" }
        }
    }
    else { $lastWhy = 'launchFailed' }
    $null = Write-PqEvent -Log $Log -Ev 'rater.fail' -Run $Run -Repo $RepoKey -Id $TicketId -Worker $Worker -D ([ordered]@{ repo = $RepoKey; id = $TicketId; why = $lastWhy; tried = @($tried) })
    return @{ ok = $false; score = -1; rater = '' }
}

# The runner writes `no-progress-or-claim-lost` for an unmoved run it cannot tell apart; a reader treats it as
# `no-progress` (TASK-FLOW rule 23).
function ConvertTo-PqEscalationOutcome([string]$Outcome) {
    if ($Outcome -ceq 'no-progress-or-claim-lost') { return 'no-progress' }
    return $Outcome
}

function Test-PqGradeRewritten($Before, $After) {
    if ($null -eq $Before -or $null -eq $After) { return $false }
    return ([int]$Before.score -ne [int]$After.score) -or ([bool]$Before.numeric -ne [bool]$After.numeric)
}

function Get-PqEscalatedScore($Info, [string]$Outcome, [string]$StatusAfter, [int]$By) {
    if ($By -le 0 -or $null -eq $Info) { return -1 }
    if (-not $Info.numeric -or $Info.pinned) { return -1 }
    $Outcome = ConvertTo-PqEscalationOutcome $Outcome
    if ($script:PqRaterNeutralOutcomes -ccontains $Outcome) { return -1 }
    $failed = ($script:PqRaterFailureOutcomes -ccontains $Outcome) -or ($StatusAfter -ceq 'Broken')
    if (-not $failed) { return -1 }
    $to = [Math]::Min(9, [int]$Info.score + $By)
    if ($to -le [int]$Info.score) { return -1 }
    return $to
}

function Invoke-PqTicketEscalation($Registry, $Info, [string]$Outcome, [string]$StatusAfter, [string]$RepoKey, [string]$TicketId, $Log, [string]$Run, [string]$Pass, $Worker, [string]$Agent) {
    $by = [int](Get-PqValue $Registry 'escalateBy' 2)
    $Outcome = ConvertTo-PqEscalationOutcome $Outcome
    $to = Get-PqEscalatedScore -Info $Info -Outcome $Outcome -StatusAfter $StatusAfter -By $by
    if ($to -lt 0 -or -not $Info.spec) { return -1 }
    $hit = Find-SzaComplexityLine ([string[]][IO.File]::ReadAllLines($Info.spec, [Text.Encoding]::UTF8))
    $oldReason = if ($hit.index -ge 0) { [string](ConvertFrom-SzaComplexityValue $hit.value).reason } else { '' }
    $oldReason = $oldReason -replace '^escalated from \d+ after a failed pass \([^)]*\):\s*', ''
    $why = if ($StatusAfter -ceq 'Broken' -and ($script:PqRaterFailureOutcomes -cnotcontains $Outcome)) { 'Broken' } else { $Outcome }
    $line = Format-SzaComplexityLine -Score $to -Reason ("escalated from {0} after a failed pass ({1}): {2}" -f $Info.score, $why, $oldReason)
    $wrote = $false
    try { $wrote = Set-PqSpecComplexity -SpecPath $Info.spec -Line $line } catch { $wrote = $false }
    if (-not $wrote) { return -1 }
    $d = [ordered]@{ from = [string]$Info.level; to = (Get-SzaComplexityBand $to); by = 'escalation'; direction = 'raise'; score = $to; fromScore = [int]$Info.score; outcome = $why }
    $null = Write-PqEvent -Log $Log -Ev 'ticket.complexity' -Run $Run -Repo $RepoKey -Id $TicketId -Pass $Pass -Worker $Worker -Agent $Agent -Cx $d.to -D $d
    return $to
}
