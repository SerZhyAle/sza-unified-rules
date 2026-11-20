# The live view of a pass (S0016 R53): what the agent is doing right now, read from the session transcript the pass writes
# as it goes - the runner itself buffers an agent's output until the pass ends, so the transcript is the only live source.
#
# Dot-source this file after loop.ps1 and occupancy.ps1; it defines functions only, sets no preference and prints nothing.
#
#   Format-PqTranscriptRecord -Line <json>   zero or more display lines for one transcript record: the agent's words
#                                            (`> text`), a tool it called (`. Read path`), a tool error (`! text`). Cut to
#                                            one line each; anything else gives nothing.
#   Get-PqLiveTarget -Workers <list> -Target <repo:id> -Slot <n>
#                                            the live worker the owner means: by ticket, by slot, or the first one with a pass.
#   Get-PqLiveTranscript -Repo <registry record> -TicketId <id>
#                                            @{ ok; path; session; why } - the lease the runner took for the pass names the
#                                            session, and the session is the transcript's file name.
#   Read-PqTail -Path <file> -Offset <long> -Carry <string>
#                                            @{ lines; offset; carry } the complete records written after Offset.
#   New-PqPassFollower / Step-PqPassFollower
#                                            the same live view inside the worker window (see the block above them).

function Format-PqTranscriptRecord([string]$Line) {
    $out = [Collections.Generic.List[string]]::new()
    $cut = { param($t, $n) $s = ([string]$t -replace '\s+', ' ').Trim(); if ($s.Length -gt $n) { $s.Substring(0, $n - 1) + '..' } else { $s } }
    try { $rec = ConvertFrom-Json -InputObject $Line -DateKind String } catch { return @() }
    $type = [string](Get-PqValue $rec 'type' '')
    $msg = Get-PqValue $rec 'message'
    if ($null -eq $msg) { return @() }
    $content = Get-PqValue $msg 'content'
    if ($content -is [string]) {
        if ($type -ceq 'assistant' -and $content.Trim()) { $out.Add('> ' + (& $cut $content 240)) }
        return @($out)
    }
    foreach ($block in @($content)) {
        $bt = [string](Get-PqValue $block 'type' '')
        if ($type -ceq 'assistant' -and $bt -ceq 'text') {
            $t = [string](Get-PqValue $block 'text' '')
            if ($t.Trim()) { $out.Add('> ' + (& $cut $t 240)) }
        }
        elseif ($type -ceq 'assistant' -and $bt -ceq 'tool_use') {
            $in = Get-PqValue $block 'input'
            $arg = ''
            foreach ($k in @('file_path', 'command', 'pattern', 'path', 'description', 'prompt', 'url')) {
                $v = Get-PqValue $in $k
                if ($v) { $arg = [string]$v; break }
            }
            $out.Add('. ' + [string](Get-PqValue $block 'name' 'tool') + $(if ($arg) { ' ' + (& $cut $arg 120) } else { '' }))
        }
        elseif ($type -ceq 'user' -and $bt -ceq 'tool_result' -and (Get-PqValue $block 'is_error' $false) -eq $true) {
            $c = Get-PqValue $block 'content'
            $text = if ($c -is [string]) { $c } else { (@($c) | ForEach-Object { [string](Get-PqValue $_ 'text' '') }) -join ' ' }
            $out.Add('! ' + (& $cut $text 160))
        }
    }
    return @($out)
}

function Get-PqLiveTarget {
    param($Workers, [string]$Target = '', [int]$Slot = 0)
    $with = @(@($Workers) | Where-Object { $_.key })
    if ($Target) { return ($with | Where-Object { $_.key -ceq $Target } | Select-Object -First 1) }
    if ($Slot -gt 0) { return ($with | Where-Object { $_.slot -eq $Slot } | Select-Object -First 1) }
    return ($with | Select-Object -First 1)
}

function Get-PqLiveTranscript {
    param([Parameter(Mandatory)]$Repo, [Parameter(Mandatory)][string]$TicketId)
    try {
        $paths = Get-PqRepoPaths -RepoPath ([string]$Repo.path)
        $lease = Read-PqState (Join-Path $paths.LeasesDir "$TicketId.json")
        $sid = [string](Get-PqValue $lease 'sessionId' '')
        if (-not $sid) { return @{ ok = $false; path = $null; session = ''; why = 'the pass has not taken its lease yet (or took none)' } }
        $dir = Get-PqTranscriptDir ([string]$Repo.path)
        if ($null -eq $dir) { return @{ ok = $false; path = $null; session = $sid; why = 'no transcript folder for this repository' } }
        $file = Join-Path $dir "$sid.jsonl"
        if (-not [IO.File]::Exists($file)) { return @{ ok = $false; path = $file; session = $sid; why = 'the transcript is not written yet' } }
        return @{ ok = $true; path = $file; session = $sid; why = $null }
    }
    catch { return @{ ok = $false; path = $null; session = ''; why = $_.Exception.Message } }
}

# Codex writes its own session file while it works, `~\.codex\sessions\<yyyy>\<MM>\<dd>\rollout-*.jsonl`. Its first record
# names the working folder (`cwd`) and the originator (`codex_exec` for a headless run), and the prompt in it names the
# ticket, so the file of a pass is found by folder, ticket and start time, not by a session id the runner never learns.
#
#   Format-PqCodexRecord -Line <json>        the same display lines as Format-PqTranscriptRecord, from one rollout record:
#                                            the agent's words (`> text`), a command it ran (`. Shell cmd`), a patch it
#                                            applied (`. Edit path`), a failed command (`! exit code n`).
#   Find-PqCodexRollout -RepoPath -TicketId -Since
#                                            the path of the newest headless rollout of that folder and ticket made at or
#                                            after Since (15 s of slack), or $null.
function Format-PqCodexRecord([string]$Line) {
    $out = [Collections.Generic.List[string]]::new()
    $cut = { param($t, $n) $s = ([string]$t -replace '\s+', ' ').Trim(); if ($s.Length -gt $n) { $s.Substring(0, $n - 1) + '..' } else { $s } }
    $unq = { param($v) try { [string](ConvertFrom-Json -InputObject ('"' + $v + '"')) } catch { [string]$v } }
    try { $rec = ConvertFrom-Json -InputObject $Line -DateKind String } catch { return @() }
    if ([string](Get-PqValue $rec 'type' '') -cne 'response_item') { return @() }
    $p = Get-PqValue $rec 'payload'
    if ($null -eq $p) { return @() }
    $pt = [string](Get-PqValue $p 'type' '')
    if ($pt -ceq 'message') {
        if ([string](Get-PqValue $p 'role' '') -cne 'assistant') { return @() }
        foreach ($b in @(Get-PqValue $p 'content' @())) {
            $t = [string](Get-PqValue $b 'text' '')
            if ($t.Trim()) { $out.Add('> ' + (& $cut $t 240)) }
        }
    }
    elseif ($pt -ceq 'reasoning') {
        foreach ($b in @(Get-PqValue $p 'summary' @())) {
            $t = [string](Get-PqValue $b 'text' '')
            if ($t.Trim()) { $out.Add('~ ' + (& $cut $t 240)) }
        }
    }
    elseif ($pt -cin @('custom_tool_call', 'function_call')) {
        $name = [string](Get-PqValue $p 'name' 'tool')
        $in = [string](Get-PqValue $p 'input' (Get-PqValue $p 'arguments' ''))
        $n = 0
        foreach ($m in [regex]::Matches($in, '\b(?:cmd|command)\s*:\s*"((?:[^"\\]|\\.)*)"')) { $out.Add('. Shell ' + (& $cut (& $unq $m.Groups[1].Value) 120)); $n++ }
        foreach ($m in [regex]::Matches($in, '\b(?:cmd|command)\s*:\s*''((?:[^''\\]|\\.)*)''')) { $out.Add('. Shell ' + (& $cut $m.Groups[1].Value 120)); $n++ }
        foreach ($m in [regex]::Matches($in, '"(?:cmd|command)"\s*:\s*"((?:[^"\\]|\\.)*)"')) { $out.Add('. Shell ' + (& $cut (& $unq $m.Groups[1].Value) 120)); $n++ }
        foreach ($m in [regex]::Matches($in, '"(?:cmd|command)"\s*:\s*\[([^\]]*)\]')) { $out.Add('. Shell ' + (& $cut (& $unq (($m.Groups[1].Value -replace '"\s*,\s*"', ' ') -replace '^\s*"|"\s*$', '')) 120)); $n++ }
        foreach ($m in [regex]::Matches($in, '\*\*\* (Add|Update|Delete) File: ([^\r\n\\"'']+)')) { $out.Add('. Edit ' + (& $cut $m.Groups[2].Value 120)); $n++ }
        if ($n -eq 0) {
            # A script that calls a tool other than a shell (`tools.web__run({..})`) is named by that tool.
            $tm = [regex]::Match($in, 'tools\.([A-Za-z0-9_]+)\((.*)', 'Singleline')
            if ($tm.Success) { $out.Add('. ' + $tm.Groups[1].Value + ' ' + (& $cut $tm.Groups[2].Value 100)) }
            else { $out.Add('. ' + $name + $(if ($in.Trim()) { ' ' + (& $cut $in 100) } else { '' })) }
        }
    }
    elseif ($pt -cin @('custom_tool_call_output', 'function_call_output')) {
        $o = Get-PqValue $p 'output'
        $text = if ($o -is [string]) { $o } else { (@($o) | ForEach-Object { [string](Get-PqValue $_ 'text' '') }) -join ' ' }
        $m = [regex]::Match($text, 'exit_code\\*"\s*:\s*([1-9]\d*)')
        if ($m.Success) { $out.Add('! exit code ' + $m.Groups[1].Value) }
    }
    return @($out)
}

function Find-PqCodexRollout {
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][string]$TicketId, [Parameter(Mandatory)][datetime]$Since)
    $profileDir = $env:USERPROFILE
    if ([string]::IsNullOrWhiteSpace($profileDir)) { $profileDir = [Environment]::GetFolderPath('UserProfile') }
    $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $profileDir '.codex' }
    $base = Join-Path $codexHome 'sessions'
    if (-not [IO.Directory]::Exists($base)) { return $null }
    $sinceUtc = $Since.ToUniversalTime()
    # The day folder is the local or the UTC date, whichever the CLI uses; a pass may also cross midnight.
    $days = [Collections.Generic.HashSet[string]]::new()
    foreach ($t in @($sinceUtc, $sinceUtc.ToLocalTime(), [datetime]::UtcNow, [datetime]::Now)) { [void]$days.Add($t.ToString('yyyy\\MM\\dd')) }
    $want = ([IO.Path]::GetFullPath($RepoPath)).TrimEnd('\')
    $found = [Collections.Generic.List[object]]::new()
    foreach ($d in $days) {
        $dir = Join-Path $base $d
        if (-not [IO.Directory]::Exists($dir)) { continue }
        foreach ($fi in [IO.DirectoryInfo]::new($dir).GetFiles('rollout-*.jsonl')) {
            if ($fi.CreationTimeUtc -lt $sinceUtc.AddSeconds(-15)) { continue }
            try {
                $stream = [IO.File]::Open($fi.FullName, 'Open', 'Read', 'ReadWrite')
                try {
                    $bytes = [byte[]]::new([int][Math]::Min(262144, $stream.Length))
                    $got = $stream.Read($bytes, 0, $bytes.Length)
                }
                finally { $stream.Dispose() }
                $head = [Text.Encoding]::UTF8.GetString($bytes, 0, $got)
                $nl = $head.IndexOf("`n")
                $first = if ($nl -ge 0) { $head.Substring(0, $nl) } else { $head }
                $meta = ConvertFrom-Json -InputObject $first -DateKind String
                $mp = Get-PqValue $meta 'payload'
                if ([string](Get-PqValue $mp 'originator' '') -cne 'codex_exec') { continue }
                $cwd = [string](Get-PqValue $mp 'cwd' '')
                if (-not $cwd -or ([IO.Path]::GetFullPath($cwd)).TrimEnd('\') -ine $want) { continue }
                if ($head.IndexOf($TicketId, [StringComparison]::Ordinal) -lt 0) { continue }
                $found.Add($fi)
            }
            catch { continue }
        }
    }
    if ($found.Count -eq 0) { return $null }
    return @($found | Sort-Object CreationTimeUtc -Descending)[0].FullName
}

# The follower is the built-in form of `pq tail`: the worker window of a pass prints what the agent does while the pass
# runs, so no second window is needed. State is a hashtable the caller keeps between steps.
#
#   New-PqPassFollower -RepoPath <path> -TicketId <id> -Since <datetime> [-Kind claude|codex]
#   Step-PqPassFollower -State <hashtable> [-MaxLines <n>]
#                                            the display lines written since the last step, at most MaxLines (the rest is
#                                            counted in one `(+n more)` line). Kind claude (also z.ai, which is the same CLI)
#                                            reads the session transcript the pass's lease names; a session whose transcript
#                                            existed before the pass began is followed from its end, never replayed, and a new
#                                            session of the same ticket (a context handoff) from its start. Kind codex reads
#                                            the headless rollout file Find-PqCodexRollout finds, from its start, and moves to
#                                            a newer one of the same ticket if the agent starts another. Never throws.
function New-PqPassFollower {
    param([Parameter(Mandatory)][string]$RepoPath, [Parameter(Mandatory)][string]$TicketId, [datetime]$Since = [datetime]::Now, [ValidateSet('claude', 'codex')][string]$Kind = 'claude')
    return @{ kind = $Kind; repo = $RepoPath; ticket = $TicketId; since = $Since.ToUniversalTime(); session = ''; path = ''; offset = [long]0; carry = ''; steps = 0 }
}

function Step-PqPassFollower {
    param([Parameter(Mandatory)]$State, [int]$MaxLines = 30)
    $out = [Collections.Generic.List[string]]::new()
    try {
        if ($State.kind -ceq 'codex') {
            # The file does not exist until the CLI starts, and a second launch of the same ticket makes a newer one.
            if (-not $State.path -or $State.steps % 5 -eq 0) {
                $f = Find-PqCodexRollout -RepoPath $State.repo -TicketId $State.ticket -Since $State.since
                if ($f -and $f -cne $State.path) { $State.path = $f; $State.offset = [long]0; $State.carry = '' }
            }
            $State.steps++
            if (-not $State.path) { return @() }
            $r = Read-PqTail -Path $State.path -Offset $State.offset -Carry $State.carry
            $State.offset = $r.offset
            $State.carry = $r.carry
            foreach ($l in @($r.lines)) { foreach ($d in @(Format-PqCodexRecord $l)) { $out.Add($d) } }
        }
        else {
            $tx = Get-PqLiveTranscript -Repo @{ path = $State.repo } -TicketId $State.ticket
            if (-not $tx.ok) { return @() }
            if ($tx.session -cne $State.session) {
                $info = [IO.FileInfo]::new($tx.path)
                $State.session = $tx.session
                $State.path = $tx.path
                $State.carry = ''
                # A file made before the pass began belongs to an earlier run of this ticket: only what it gains is shown.
                $State.offset = if ($info.CreationTimeUtc -ge $State.since.AddSeconds(-15)) { [long]0 } else { [long]$info.Length }
            }
            $r = Read-PqTail -Path $State.path -Offset $State.offset -Carry $State.carry
            $State.offset = $r.offset
            $State.carry = $r.carry
            foreach ($l in @($r.lines)) { foreach ($d in @(Format-PqTranscriptRecord $l)) { $out.Add($d) } }
        }
    }
    catch { return @() }
    if ($out.Count -gt $MaxLines) {
        $more = $out.Count - $MaxLines
        $out.RemoveRange($MaxLines, $more)
        $out.Add("(+$more more)")
    }
    return @($out)
}

function Read-PqTail {
    param([Parameter(Mandatory)][string]$Path, [long]$Offset = 0, [string]$Carry = '')
    $lines = [Collections.Generic.List[string]]::new()
    $stream = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try {
        if ($Offset -gt $stream.Length) { $Offset = 0; $Carry = '' }
        $null = $stream.Seek($Offset, 'Begin')
        $bytes = [byte[]]::new([Math]::Max(0, $stream.Length - $Offset))
        $read = if ($bytes.Length -gt 0) { $stream.Read($bytes, 0, $bytes.Length) } else { 0 }
        $text = $Carry + [Text.Encoding]::UTF8.GetString($bytes, 0, $read)
        $newOffset = $Offset + $read
    }
    finally { $stream.Dispose() }
    $parts = $text -split "`n"
    # The last part has no line end yet: it is carried to the next read.
    for ($i = 0; $i -lt $parts.Count - 1; $i++) { if ($parts[$i].Trim()) { $lines.Add($parts[$i]) } }
    return @{ lines = @($lines); offset = $newOffset; carry = [string]$parts[$parts.Count - 1] }
}
