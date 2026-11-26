<#
    What one launched child used (S0037, TASK-FLOW rule 23).

    Dot-sourced by run-spec-queue.ps1. One question, answered from files on disk after the child is gone: how many
    tokens did its session and its subagents use, and what is that at list price? (Get-PassUsage)
    It never invents a value: an answer that cannot be read is $null (absent in the journal row), never zero or a
    guess. The built disclosure of TASK-FLOW 0.20 was withdrawn in 0.36 (S0135): pq report counts what was closed
    without a build from the ledgers. #>

function Get-PassJsonProperty($Object, [string] $Name) {
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Read-PassPriceSnapshot {
    param([string] $Path = (Join-Path $PSScriptRoot 'claude-prices.json'))
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}

function Get-PassModelRates($Snapshot, [string] $Model) {
    # The longest model-id prefix wins, so claude-opus-5-5 is never priced as claude-opus-5.
    if ($null -eq $Snapshot -or [string]::IsNullOrWhiteSpace($Model)) { return $null }
    $best = $null
    foreach ($p in @($Snapshot.models.PSObject.Properties)) {
        if ($Model -eq $p.Name -or $Model.StartsWith($p.Name + '-', [StringComparison]::OrdinalIgnoreCase) -or
            $Model.StartsWith($p.Name + '@', [StringComparison]::OrdinalIgnoreCase)) {
            if ($null -eq $best -or $p.Name.Length -gt $best.Name.Length) { $best = $p }
        }
    }
    if ($null -eq $best) { return $null }
    return $best.Value
}

function Get-PassRequestCost {
    <# List price of one request in USD, or $null when any rate it needs is unknown. #>
    param($Snapshot, $Request)
    $rates = Get-PassModelRates $Snapshot $Request.model
    if ($null -eq $rates) { return $null }
    if ($Request.speed -and $Request.speed -ne 'standard') { return $null }
    $geo = 1.0
    if ($Request.geo -eq 'us') { $geo = [double]$Snapshot.usGeoMultiplier }
    elseif ($Request.geo -and $Request.geo -notin @('global', 'not_available')) { return $null }
    if ($Request.cacheWrite -gt 0 -and -not $Request.cacheWriteSplit) { return $null }
    $promptTokens = $Request.input + $Request.cacheRead + $Request.cacheWrite
    $over = Get-PassJsonProperty $rates 'longPromptOver'
    if ($null -ne $over -and $promptTokens -gt [double]$over) { $rates = $rates.long }
    $usd = ($Request.input * [double]$rates.input + $Request.output * [double]$rates.output +
        $Request.cacheRead * [double]$rates.cacheRead + $Request.cacheWrite5m * [double]$rates.cacheWrite5m +
        $Request.cacheWrite1h * [double]$rates.cacheWrite1h) / 1000000.0
    return $usd * $geo
}

function Get-PassUsage {
    <#
        Token usage of one launched session: its transcript plus every subagent file under
        <session-id>/subagents/, counted once per distinct requestId (the CLI repeats one response's usage on
        each of its content blocks; the largest value seen per field is kept, as tools/mine-agent-transcripts.py
        does). Returns @{ usage; costUsd; priceAsOf }, or $null when there is no transcript to read - the row
        then carries no usage, which reads as unknown.
    #>
    param([string] $TranscriptPath, [string] $SessionId, $Snapshot = (Read-PassPriceSnapshot))
    if (-not $TranscriptPath -or -not (Test-Path -LiteralPath $TranscriptPath -PathType Leaf)) { return $null }
    $files = [Collections.Generic.List[string]]::new()
    $files.Add($TranscriptPath)
    $sessionDir = Join-Path (Split-Path -Parent $TranscriptPath) ([IO.Path]::GetFileNameWithoutExtension($TranscriptPath))
    $subDir = Join-Path $sessionDir 'subagents'
    if (Test-Path -LiteralPath $subDir -PathType Container) {
        foreach ($f in @(Get-ChildItem -LiteralPath $subDir -Filter '*.jsonl' -File -Recurse -ErrorAction SilentlyContinue)) { $files.Add($f.FullName) }
    }

    $complete = $true
    $requests = [ordered]@{}
    foreach ($file in $files) {
        $lines = $null
        try {
            $stream = [IO.File]::Open($file, 'Open', 'Read', 'ReadWrite')
            try { $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8); $lines = $reader.ReadToEnd() -split "`r?`n"; $reader.Dispose() }
            finally { $stream.Dispose() }
        } catch { $complete = $false; continue }
        foreach ($line in $lines) {
            if ($line -notmatch '"usage"' -or $line -notmatch '"type"\s*:\s*"assistant"') { continue }
            $rec = $null
            try { $rec = $line | ConvertFrom-Json -ErrorAction Stop } catch { $complete = $false; continue }
            if ([string](Get-PassJsonProperty $rec 'type') -ne 'assistant') { continue }
            $msg = Get-PassJsonProperty $rec 'message'
            $u = Get-PassJsonProperty $msg 'usage'
            if ($null -eq $u) { continue }
            $model = [string](Get-PassJsonProperty $msg 'model')
            if ($model -eq '<synthetic>') { continue }
            $rid = [string](Get-PassJsonProperty $rec 'requestId')
            if ([string]::IsNullOrWhiteSpace($rid)) { $complete = $false; continue }
            $cc = Get-PassJsonProperty $u 'cache_creation'
            $cur = [ordered]@{
                model           = $model
                input           = [int64](Get-PassJsonProperty $u 'input_tokens')
                output          = [int64](Get-PassJsonProperty $u 'output_tokens')
                cacheRead       = [int64](Get-PassJsonProperty $u 'cache_read_input_tokens')
                cacheWrite      = [int64](Get-PassJsonProperty $u 'cache_creation_input_tokens')
                cacheWrite5m    = [int64](Get-PassJsonProperty $cc 'ephemeral_5m_input_tokens')
                cacheWrite1h    = [int64](Get-PassJsonProperty $cc 'ephemeral_1h_input_tokens')
                cacheWriteSplit = ($null -ne $cc)
                speed           = [string](Get-PassJsonProperty $u 'speed')
                geo             = [string](Get-PassJsonProperty $u 'inference_geo')
            }
            if ($requests.Contains($rid)) {
                $prev = $requests[$rid]
                foreach ($k in @('input', 'output', 'cacheRead', 'cacheWrite', 'cacheWrite5m', 'cacheWrite1h')) {
                    if ($cur[$k] -gt $prev[$k]) { $prev[$k] = $cur[$k] }
                }
                if ($cur.cacheWriteSplit) { $prev.cacheWriteSplit = $true }
            } else {
                $requests[$rid] = $cur
            }
        }
    }

    $sum = [ordered]@{ input = [int64]0; output = [int64]0; cacheRead = [int64]0; cacheWrite = [int64]0 }
    $models = [Collections.Generic.List[string]]::new()
    $cost = 0.0
    $priced = ($null -ne $Snapshot)
    foreach ($r in $requests.Values) {
        foreach ($k in @($sum.Keys)) { $sum[$k] += $r[$k] }
        if ($r.model -and -not $models.Contains($r.model)) { $models.Add($r.model) }
        if ($priced) {
            $c = Get-PassRequestCost -Snapshot $Snapshot -Request $r
            if ($null -eq $c) { $priced = $false } else { $cost += $c }
        }
    }
    $usage = [ordered]@{
        model      = ($models -join '+')
        input      = $sum.input
        output     = $sum.output
        cacheRead  = $sum.cacheRead
        cacheWrite = $sum.cacheWrite
        requests   = $requests.Count
        complete   = $complete
    }
    if ($SessionId) { $usage.session = $SessionId }
    return [ordered]@{
        usage     = $usage
        costUsd   = $(if ($priced -and $complete) { [Math]::Round($cost, 4) } else { $null })
        priceAsOf = $(if ($priced -and $complete) { [string]$Snapshot.priceAsOf } else { $null })
    }
}

function Get-CodexPassUsage {
    <#
        Token usage of one `codex exec` child. The log prints one bare total ("tokens used"), which does not
        split input from output, so the header's session id is read from the captured output and the split comes
        from the last token_count record of that session's rollout file. The rollout carries no request id, so
        the figure is complete=false (rule 23), and there is no price. $null when the output is not codex's or
        the rollout cannot be read: unknown, never zero. Subagent sessions have their own rollouts and are not
        counted.
    #>
    param(
        [string] $LogBody,
        [string] $SessionsRoot = $(Join-Path $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }) 'sessions')
    )
    # Anchored on the banner: the child's own answer and tool output may quote a "session id:" line.
    $header = [regex]::Match([string]$LogBody, '(?m)^OpenAI Codex v[^\n]*\n(?:(?!session id:)[^\n]*\n){0,15}?session id: ([0-9a-fA-F-]{36})\s*$')
    if (-not $header.Success -or -not (Test-Path -LiteralPath $SessionsRoot -PathType Container)) { return $null }
    $id = $header.Groups[1].Value
    $file = @(Get-ChildItem -LiteralPath $SessionsRoot -Filter "rollout-*-$id.jsonl" -File -Recurse -ErrorAction SilentlyContinue) | Select-Object -First 1
    if ($null -eq $file) { return $null }
    $total = $null
    $model = ''
    $seen = [Collections.Generic.HashSet[int64]]::new()
    $stream = [IO.File]::Open($file.FullName, 'Open', 'Read', 'ReadWrite')
    try {
        $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8)
        while ($null -ne ($line = $reader.ReadLine())) {
            if ($line -notmatch '"type"\s*:\s*"(token_count|turn_context)"') { continue }
            try { $rec = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
            $payload = Get-PassJsonProperty $rec 'payload'
            if ([string](Get-PassJsonProperty $rec 'type') -eq 'turn_context') {
                $m = [string](Get-PassJsonProperty $payload 'model')
                if ($m) { $model = $m }
                continue
            }
            $t = Get-PassJsonProperty (Get-PassJsonProperty $payload 'info') 'total_token_usage'
            if ($null -eq $t) { continue }
            $total = $t
            $null = $seen.Add([int64](Get-PassJsonProperty $t 'total_tokens'))
        }
    } finally { $stream.Dispose() }
    if ($null -eq $total) { return $null }
    # Codex counts cached tokens inside input_tokens; this object keeps them apart, as for claude.
    $cacheRead = [int64](Get-PassJsonProperty $total 'cached_input_tokens')
    $cacheWrite = [int64](Get-PassJsonProperty $total 'cache_write_input_tokens')
    $usage = [ordered]@{
        model      = $model
        input      = [Math]::Max([int64]0, [int64](Get-PassJsonProperty $total 'input_tokens') - $cacheRead - $cacheWrite)
        output     = [int64](Get-PassJsonProperty $total 'output_tokens')
        cacheRead  = $cacheRead
        cacheWrite = $cacheWrite
        requests   = $seen.Count
        complete   = $false
        session    = $id
    }
    return [ordered]@{ usage = $usage; costUsd = $null; priceAsOf = $null }
}

function Get-GeminiPassUsage {
    <#
        Token usage of one `agy --print` child. Its output carries the answer only; the counts are on the model
        records of the session transcript, brain/<conversation>/.system_generated/logs/transcript_full.jsonl.
        The runner does not know the conversation id, so the session is the one whose first record is a user
        input made after the launch and naming this ticket and this repository; none, or more than one, is
        unknown. complete=false: helper calls and subagent sessions leave no record there. There is no price.
    #>
    param(
        [string] $TicketId,
        [string] $RepoRoot,
        [datetime] $Since,
        [string] $BrainRoot = $(Join-Path $HOME '.gemini/antigravity-cli/brain')
    )
    if (-not $TicketId -or -not $RepoRoot -or -not (Test-Path -LiteralPath $BrainRoot -PathType Container)) { return $null }
    $from = $Since.ToUniversalTime().AddSeconds(-5)
    $idPattern = '(?<![\w-])' + [regex]::Escape($TicketId) + '(?![\w-])'
    $rootPattern = [regex]::Escape($RepoRoot.Replace('\', '/').TrimEnd('/')) + '(?![\w-])'
    $found = @()
    foreach ($dir in [IO.Directory]::EnumerateDirectories($BrainRoot)) {
        $file = Join-Path $dir '.system_generated/logs/transcript_full.jsonl'
        if (-not [IO.File]::Exists($file) -or [IO.File]::GetLastWriteTimeUtc($file) -lt $from) { continue }
        try {
            $stream = [IO.File]::Open($file, 'Open', 'Read', 'ReadWrite')
            try {
                $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8)
                $first = $reader.ReadLine() | ConvertFrom-Json -ErrorAction Stop
                if ([string](Get-PassJsonProperty $first 'type') -ne 'USER_INPUT') { continue }
                $created = Get-PassJsonProperty $first 'created_at'
                if ($null -eq $created -or ([datetime]$created).ToUniversalTime() -lt $from) { continue }
                $asked = ([string](Get-PassJsonProperty $first 'content')).Replace('\', '/')
                if ($asked -notmatch $idPattern -or $asked -notmatch $rootPattern) { continue }
                $records = [Collections.Generic.List[object]]::new()
                while ($null -ne ($line = $reader.ReadLine())) {
                    if ($line -notmatch '"input_tokens"') { continue }
                    try { $rec = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
                    if ($null -ne (Get-PassJsonProperty $rec 'input_tokens')) { $records.Add($rec) }
                }
                $found += @{ id = Split-Path -Leaf $dir; records = $records }
            } finally { $stream.Dispose() }
        } catch { continue }
    }
    if ($found.Count -ne 1 -or $found[0].records.Count -eq 0) { return $null }
    $sum = [ordered]@{ input = [int64]0; output = [int64]0; cacheRead = [int64]0 }
    $models = [Collections.Generic.List[string]]::new()
    foreach ($rec in $found[0].records) {
        # input_tokens already leaves the cached tokens out, as this object does.
        $sum.input += [int64](Get-PassJsonProperty $rec 'input_tokens')
        $sum.output += [int64](Get-PassJsonProperty $rec 'output_tokens')
        $sum.cacheRead += [int64](Get-PassJsonProperty $rec 'cache_read_tokens')
        $m = [string](Get-PassJsonProperty $rec 'model')
        if ($m -and -not $models.Contains($m)) { $models.Add($m) }
    }
    $usage = [ordered]@{
        model     = ($models -join '+')
        input     = $sum.input
        output    = $sum.output
        cacheRead = $sum.cacheRead
        requests  = $found[0].records.Count
        complete  = $false
        session   = $found[0].id
    }
    return [ordered]@{ usage = $usage; costUsd = $null; priceAsOf = $null }
}
