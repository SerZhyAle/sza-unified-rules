# What one launched child said about its build and what it used (S0037, TASK-FLOW 0.20 rule 23).
#
# Dot-sourced by run-spec-queue.ps1. Two questions, each answered from files on disk after the child is gone:
#   - did the child's final answer disclose "not built, not tested until the release"? (Get-PassBuiltFlag)
#   - how many tokens did its session and its subagents use, and what is that at list price? (Get-PassUsage)
# Neither ever invents a value: an answer that cannot be read is $null (absent in the journal row), never
# $true, zero or a guess.

$script:PassNotBuiltSentence = 'not built, not tested until the release'

function Get-PassJsonProperty($Object, [string] $Name) {
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-PassFinalText {
    <#
        The child's final answer: the text of the last main-thread assistant record of its transcript, else
        the tail of the -Quiet log. Only the tail of a log is read, because a CLI that echoes its tool output
        (Codex prints the files it reads) would otherwise find the sentence in the skill text it was handed.
    #>
    param([string] $TranscriptPath, [string] $LogBody, [int] $LogTailChars = 4000)
    if ($TranscriptPath -and (Test-Path -LiteralPath $TranscriptPath -PathType Leaf)) {
        $record = Read-TranscriptLastAssistant -Path $TranscriptPath
        $content = Get-PassJsonProperty (Get-PassJsonProperty $record 'message') 'content'
        $parts = @(foreach ($block in @($content)) {
                if ([string](Get-PassJsonProperty $block 'type') -eq 'text') { [string](Get-PassJsonProperty $block 'text') }
            })
        if ($parts.Count -gt 0) { return ($parts -join "`n") }
    }
    if (-not [string]::IsNullOrEmpty($LogBody)) {
        if ($LogBody.Length -gt $LogTailChars) { return $LogBody.Substring($LogBody.Length - $LogTailChars) }
        return $LogBody
    }
    return $null
}

function Get-PassBuiltFlag {
    <# $false when the text holds the disclosure sentence, $null otherwise: a missing sentence proves no build. #>
    param([string] $Text)
    if ([string]::IsNullOrEmpty($Text)) { return $null }
    if ($Text.IndexOf($script:PassNotBuiltSentence, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $false }
    return $null
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
