# Fast fixture for S0037 (TASK-FLOW 0.20 rules 23 and 46): the built disclosure, transcript usage and its list-price
# estimate, the fold over the launches of one portfolio pass, and the report figures. Files only, no child process.
#
#   pwsh -NoProfile -File tools/tests/portfolio-usage.tests.ps1
#
# Exit codes: 0 every check passed; 1 a check failed.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'tools\harness\batch\_limit-hold.ps1')
. (Join-Path $repo 'tools\harness\batch\_pass-usage.ps1')
. (Join-Path $repo 'tools\harness\portfolio\lib\registry.ps1')
. (Join-Path $repo 'tools\harness\portfolio\lib\loop.ps1')
. (Join-Path $repo 'tools\harness\portfolio\lib\analysis.ps1')

$script:failed = 0
function Check([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Output "PASS $Name" } else { Write-Output "FAIL $Name"; $script:failed++ }
}

$work = Join-Path $repo ('temp\S0037\usage-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $work -Force
try {
    function New-Assistant([string]$Rid, [string]$Model, [int]$In, [int]$Out, [int]$Read, [int]$W1h, [string]$Text = '', [switch]$NoSplit, [string]$Speed = 'standard') {
        $usage = [ordered]@{ input_tokens = $In; output_tokens = $Out; cache_read_input_tokens = $Read; cache_creation_input_tokens = $W1h; speed = $Speed; inference_geo = 'global' }
        if (-not $NoSplit) { $usage.cache_creation = [ordered]@{ ephemeral_5m_input_tokens = 0; ephemeral_1h_input_tokens = $W1h } }
        $content = if ($Text) { @([ordered]@{ type = 'text'; text = $Text }) } else { @([ordered]@{ type = 'thinking'; thinking = '' }) }
        $rec = [ordered]@{ type = 'assistant'; isSidechain = $false; requestId = $Rid; message = [ordered]@{ model = $Model; content = $content; usage = $usage } }
        return ($rec | ConvertTo-Json -Compress -Depth 8)
    }

    # 1. Disclosure: the exact sentence gives built=false; its absence is unknown, never true.
    Check ((Get-PassBuiltFlag -Text 'Done. Not built, not tested until the release.') -eq $false) 'built=false on the disclosure sentence'
    Check ($null -eq (Get-PassBuiltFlag -Text 'Compiled and tested.')) 'no sentence is unknown, not true'
    Check ($null -eq (Get-PassBuiltFlag -Text '')) 'no text is unknown'
    $long = ('x' * 9000) + ' not built, not tested until the release'
    Check ((Get-PassBuiltFlag -Text (Get-PassFinalText -LogBody $long)) -eq $false) 'the log tail carries the disclosure'
    $echo = ' not built, not tested until the release ' + ('x' * 9000)
    Check ($null -eq (Get-PassBuiltFlag -Text (Get-PassFinalText -LogBody $echo))) 'a sentence far from the log end is not read'

    # 2. Transcript usage: duplicates by requestId counted once, a subagent included, the final text read.
    $sid = 'aaaaaaaa-0000-0000-0000-000000000001'
    $main = Join-Path $work "$sid.jsonl"
    $lines = @(
        (New-Assistant 'req_1' 'claude-opus-5-5' 10 100 1000 2000),
        (New-Assistant 'req_1' 'claude-opus-5-5' 10 100 1000 2000),
        '{"type":"user","message":{"content":"x"}}',
        'not json',
        (New-Assistant 'req_2' 'claude-opus-5-5' 5 50 0 0 -Text 'All done - not built, not tested until the release.')
    )
    [IO.File]::WriteAllLines($main, $lines)
    $sub = Join-Path $work "$sid\subagents"
    $null = New-Item -ItemType Directory -Path $sub -Force
    [IO.File]::WriteAllLines((Join-Path $sub 'agent-1.jsonl'), @((New-Assistant 'req_s1' 'claude-haiku-5-5' 1000 10 0 0)))
    $u = Get-PassUsage -TranscriptPath $main -SessionId $sid
    Check ($u.usage.requests -eq 3) "three distinct requests (got $($u.usage.requests))"
    Check ($u.usage.input -eq 1015 -and $u.usage.output -eq 160 -and $u.usage.cacheRead -eq 1000 -and $u.usage.cacheWrite -eq 2000) 'tokens summed once per request, subagent included'
    Check ($u.usage.model -eq 'claude-opus-5-5+claude-haiku-5-5') "model list (got $($u.usage.model))"
    Check ($u.usage.complete -eq $true -and $u.usage.session -eq $sid) 'complete and keyed by session'
    # opus 5.5: 15*4 + 150*20 + 1000*0.2 + 2000*8 = 19260; haiku 5.5: 1000*0.1 + 10*0.5 = 105 -> 19365 / 1e6
    Check ($u.costUsd -eq 0.0194 -and $u.priceAsOf -eq '2026-11-12') "list-price estimate (got $($u.costUsd))"
    Check ((Get-PassBuiltFlag -Text (Get-PassFinalText -TranscriptPath $main)) -eq $false) 'final answer read from the transcript'

    # 3. Unknown price and unknown attribution are absent, never zero.
    $sid2 = 'aaaaaaaa-0000-0000-0000-000000000002'
    $t2 = Join-Path $work "$sid2.jsonl"
    [IO.File]::WriteAllLines($t2, @((New-Assistant 'req_9' 'claude-unknown-9' 1 1 0 0)))
    $u2 = Get-PassUsage -TranscriptPath $t2 -SessionId $sid2
    Check ($null -eq $u2.costUsd -and $null -eq $u2.priceAsOf -and $u2.usage.requests -eq 1) 'unknown model price leaves cost absent'
    $sid3 = 'aaaaaaaa-0000-0000-0000-000000000003'
    $t3 = Join-Path $work "$sid3.jsonl"
    [IO.File]::WriteAllLines($t3, @((New-Assistant '' 'claude-opus-5-5' 1 1 0 0), (New-Assistant 'req_n' 'claude-opus-5-5' 1 1 0 5 -NoSplit)))
    $u3 = Get-PassUsage -TranscriptPath $t3 -SessionId $sid3
    Check ($u3.usage.complete -eq $false -and $null -eq $u3.costUsd) 'missing requestId marks incomplete, no cost'
    $t4 = Join-Path $work 'fast.jsonl'
    [IO.File]::WriteAllLines($t4, @((New-Assistant 'req_f' 'claude-opus-5-5' 1 1 0 0 -Speed 'fast')))
    Check ($null -eq (Get-PassUsage -TranscriptPath $t4).costUsd) 'fast mode is unpriced'
    Check ($null -eq (Get-PassUsage -TranscriptPath (Join-Path $work 'absent.jsonl'))) 'absent transcript gives no usage'
    Check ((Get-PassModelRates (Read-PassPriceSnapshot) 'claude-opus-5-5-20261101').input -eq 4) 'longest model prefix wins'
    $haiku = [ordered]@{ model = 'claude-haiku-5-5'; input = 150000; output = 0; cacheRead = 0; cacheWrite = 0; cacheWrite5m = 0; cacheWrite1h = 0; cacheWriteSplit = $false; speed = 'standard'; geo = 'global' }
    Check ([Math]::Round((Get-PassRequestCost -Snapshot (Read-PassPriceSnapshot) -Request $haiku), 4) -eq 0.075) 'Haiku 5.5 long-prompt rate'

    # 4. The fold over the launches of a pass: a repeated session counted once, a launch without usage incomplete.
    $l1 = [pscustomobject]@{ id = 'S1'; usage = [pscustomobject]$u.usage; costUsd = 0.0194; priceAsOf = '2026-11-12' }
    $l2 = [pscustomobject]@{ id = 'S1'; built = $false; usage = [pscustomobject]@{ model = 'claude-opus-5-5'; input = 1; output = 2; cacheRead = 3; cacheWrite = 4; requests = 1; complete = $true; session = 'other' }; costUsd = 0.0001; priceAsOf = '2026-11-01' }
    $f = Merge-PqPassUsage -Rows @($l1, $l1, $l2)
    Check ($f.built -eq $false) 'built=false when any launch disclosed it'
    Check ($f.usage.requests -eq 4 -and $f.usage.input -eq 1016) "repeated session counted once (requests $($f.usage.requests))"
    Check ($f.costUsd -eq 0.0195 -and $f.priceAsOf -eq '2026-11-01') 'cost summed, oldest price date'
    $f2 = Merge-PqPassUsage -Rows @($l1, [pscustomobject]@{ id = 'S1'; outcome = 'ok' })
    Check ($f2.usage.complete -eq $false -and $null -eq $f2.costUsd -and $null -eq $f2.built) 'a launch without usage makes the pass incomplete and unpriced'
    $f3 = Merge-PqPassUsage -Rows @([pscustomobject]@{ id = 'S1'; outcome = 'ok' })
    Check ($null -eq $f3.usage -and $null -eq $f3.costUsd) 'old rows give no usage'

    # 5. Report figures: closed unbuilt per repository, usage by repository / model / outcome, old rows kept.
    $runs = @(
        [pscustomobject]@{ repo = 'a'; statusAfter = 'Implemented'; built = $false; outcome = 'ok'; model = 'opus'; usage = [pscustomobject]@{ model = 'claude-opus-5-5'; input = 10; output = 20; cacheRead = 0; cacheWrite = 0; requests = 1; complete = $true }; costUsd = 1.5; priceAsOf = '2026-11-12' },
        [pscustomobject]@{ repo = 'a'; statusAfter = 'Verified'; outcome = 'ok'; model = 'gpt' },
        [pscustomobject]@{ repo = 'b'; statusAfter = 'BlockQuestions'; built = $false; outcome = 'no-progress'; usage = [pscustomobject]@{ model = 'claude-opus-5-5'; input = 1; output = 1; cacheRead = 0; cacheWrite = 0; requests = 1; complete = $false } }
    )
    $b = Get-PqBuildFigures $runs
    Check ($b.a.closing -eq 2 -and $b.a.unbuilt -eq 1 -and $b.a.unknown -eq 1 -and -not $b.Contains('b')) 'closed unbuilt counts only closing statuses'
    $g = Get-PqUsageFigures $runs
    Check ($g.total.passes -eq 3 -and $g.total.withUsage -eq 2 -and $g.total.incomplete -eq 1 -and $g.total.priced -eq 1 -and $g.total.unpriced -eq 1 -and $g.total.costUsd -eq 1.5) 'usage totals with unknowns counted'
    Check ($g.byModel['claude-opus-5-5'].passes -eq 2 -and $g.byModel.gpt.withUsage -eq 0 -and $g.byOutcome['no-progress'].input -eq 1 -and $g.byRepo.a.output -eq 20) 'usage by model, outcome and repository'
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:failed -gt 0) { Write-Output "portfolio-usage: FAIL ($script:failed)"; exit 1 }
Write-Output 'portfolio-usage: PASS'
exit 0
