# Fast fixture for CANONR-0209: the usage of a codex child, read from its captured output and rollout file, and
# the absence of usage for an output that carries no totals (gemini). Files only, no child process.
#
#   pwsh -NoProfile -File tools/tests/codex-usage.tests.ps1
#
# Exit codes: 0 every check passed; 1 a check failed.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'tools\harness\batch\_pass-usage.ps1')

$script:failed = 0
function Check([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Output "PASS $Name" } else { Write-Output "FAIL $Name"; $script:failed++ }
}

$work = Join-Path $repo ('temp\CANONR-0209\usage-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$day = Join-Path $work '2026\11\26'
$null = New-Item -ItemType Directory -Path $day -Force
try {
    $id = '01a21567-1586-7112-a8e9-e984c96731c6'
    $count = '{{"type":"event_msg","payload":{{"type":"token_count","info":{{"total_token_usage":{{"input_tokens":{0},"cached_input_tokens":{1},"cache_write_input_tokens":0,"output_tokens":{2},"total_tokens":{3}}}}}}}}}'
    [IO.File]::WriteAllLines((Join-Path $day "rollout-2026-11-26T02-00-00-$id.jsonl"), @(
            '{"type":"turn_context","payload":{"model":"gpt-6.2-sol"}}',
            ($count -f 1000, 600, 40, 1040),
            '{"type":"event_msg","payload":{"type":"token_count","info":null}}',
            ($count -f 3000, 2000, 100, 3100),
            ($count -f 3000, 2000, 100, 3100)))

    # Fixture 1: codex output, the answer on stdout quoting another session id before the banner on stderr.
    $codex = "session id: 99999999-0000-0000-0000-000000000000`r`n`n--- stderr ---`nOpenAI Codex v0.171.0`r`n--------`r`nworkdir: P:\x`r`nmodel: gpt-6.2-sol`r`nsession id: $id`r`n--------`r`ntokens used`r`n1,100`r`n"
    $u = Get-CodexPassUsage -LogBody $codex -SessionsRoot $work
    Check ($null -ne $u -and $u.usage.session -eq $id -and $u.usage.model -eq 'gpt-6.2-sol') 'codex session found by the banner'
    Check ($u.usage.input -eq 1000 -and $u.usage.output -eq 100 -and $u.usage.cacheRead -eq 2000 -and $u.usage.cacheWrite -eq 0) 'last cumulative total, cached input kept apart'
    Check ($u.usage.requests -eq 2 -and $u.usage.complete -eq $false -and $null -eq $u.costUsd) 'repeated total counted once; incomplete and unpriced'
    Check ($null -eq (Get-CodexPassUsage -LogBody ($codex -replace $id, '00000000-0000-0000-0000-000000000000') -SessionsRoot $work)) 'absent rollout gives no usage'

    # Fixture 2: gemini print-mode output carries the answer only.
    $gemini = "### Result`n- ``tools/x.ps1`` -> exit 0`nStatus: Implemented`n"
    Check ($null -eq (Get-CodexPassUsage -LogBody $gemini -SessionsRoot $work)) 'output without totals gives no usage'
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:failed -gt 0) { Write-Output "codex-usage: FAIL ($script:failed)"; exit 1 }
Write-Output 'codex-usage: PASS'
exit 0
