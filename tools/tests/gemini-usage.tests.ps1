# Fast fixture for CANONR-0209: the usage of an agy child, read from the transcript of the session it opened.
# Files only, no child process.
#
#   pwsh -NoProfile -File tools/tests/gemini-usage.tests.ps1
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

$work = Join-Path $repo ('temp\CANONR-0209\gemini-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$since = [datetime]::Now.AddMinutes(-1)

function New-Session([string]$Id, [datetime]$Created, [string]$Prompt, [string[]]$Records) {
    $logs = Join-Path $work "$Id\.system_generated\logs"
    $null = New-Item -ItemType Directory -Path $logs -Force
    $first = [ordered]@{ step_index = 0; type = 'USER_INPUT'; created_at = $Created.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'"); content = $Prompt } | ConvertTo-Json -Compress
    [IO.File]::WriteAllLines((Join-Path $logs 'transcript_full.jsonl'), [string[]](@($first) + $Records))
}
function Get-Usage([string]$Id = 'DEMO-0001', [string]$Root = 'P:\demo') {
    Get-GeminiPassUsage -TicketId $Id -RepoRoot $Root -Since $since -BrainRoot $work
}

try {
    $prompt = '<USER_REQUEST> DEMO-0001 - the ticket is PLAN/DEMO-0001_x.md in P:\demo. </USER_REQUEST>'
    $records = @(
        '{"type":"PLANNER_RESPONSE","model":"gemini-x-high","input_tokens":100,"output_tokens":10,"cache_read_tokens":0}',
        '{"type":"GENERIC","content":"a tool output quoting \"input_tokens\": 999999"}',
        '{"type":"PLANNER_RESPONSE","model":"gemini-x-high","input_tokens":200,"output_tokens":30,"cache_read_tokens":100}')
    New-Session 'own' ([datetime]::Now) $prompt $records
    New-Session 'earlier' $since.AddHours(-1) $prompt $records
    New-Session 'other-repo' ([datetime]::Now) ($prompt -replace 'P:\\demo', 'P:\demo2') $records

    $u = Get-Usage
    Check ($null -ne $u -and $u.usage.session -eq 'own' -and $u.usage.model -eq 'gemini-x-high') 'the session of this launch, ticket and repository'
    Check ($u.usage.input -eq 300 -and $u.usage.output -eq 40 -and $u.usage.cacheRead -eq 100 -and $u.usage.requests -eq 2) 'model records summed, quoted text ignored'
    Check ($u.usage.complete -eq $false -and $null -eq $u.costUsd) 'incomplete and unpriced'
    Check ($null -eq (Get-Usage -Id 'DEMO-0002')) 'no matching session gives no usage'

    New-Session 'twin' ([datetime]::Now) $prompt $records
    Check ($null -eq (Get-Usage)) 'two matching sessions give no usage'

    New-Session 'empty' ([datetime]::Now) ($prompt -replace 'DEMO-0001', 'DEMO-0003') @()
    Check ($null -eq (Get-Usage -Id 'DEMO-0003')) 'a session without token records gives no usage'
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:failed -gt 0) { Write-Output "gemini-usage: FAIL ($script:failed)"; exit 1 }
Write-Output 'gemini-usage: PASS'
exit 0
