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
