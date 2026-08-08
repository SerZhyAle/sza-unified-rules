<#
smoke-hooks.ps1 - prove the shipped hooks still block what they must and wave through what they must not.

A guard that over-blocks gets turned off, and then nothing is enforced - the same reasoning
CLAUDE.md applies to check-compliance.ps1 checks. So every guard here is smoked from both sides: one
payload it must refuse and one it must allow. The allow cases are the load-bearing ones.

  pwsh -NoProfile -File hooks/tests/smoke-hooks.ps1

Exit codes:
  0  every case matched its expected exit code
  1  at least one case did not
  2  could not verify (a hook script is missing)
#>
$ErrorActionPreference = 'Stop'

$hooksDir = Split-Path $PSScriptRoot -Parent
$repoRoot = Split-Path $hooksDir -Parent
$failures = 0

foreach ($f in @('guard-find-command.ps1', 'guard-ps1-in-bash.ps1', 'guard-uncapped-read.ps1',
                 'guard-fire-and-forget.ps1', 'on-user-prompt.ps1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $hooksDir $f))) {
        Write-Error "smoke-hooks: $f is missing - cannot verify" -ErrorAction Continue
        exit 2
    }
}

# An advisory hook always exits 0, so the exit code alone cannot tell "fired" from "stayed silent" -
# -MustContain / -MustBeSilent is what actually tests those cases.
function Invoke-Case {
    param(
        [string]$name,
        [string]$hook,
        [string]$json,
        [int]$expected,
        [string]$MustContain,
        [switch]$MustBeSilent
    )
    # Write the payload as UTF-8 without a BOM: the rung nudge reads Cyrillic prompts, and piping a
    # PowerShell string through the default encoder corrupts them on a cp1251 console.
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding $false))
        $output = & { Get-Content -LiteralPath $tmp -Raw | pwsh -NoProfile -File (Join-Path $hooksDir $hook) } 2>&1
        $code = $LASTEXITCODE
    }
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }

    $text = ($output -join ' ')
    $why = $null
    if ($code -ne $expected) { $why = "exit expected: $expected | actual: $code" }
    elseif ($MustContain -and $text -notmatch [regex]::Escape($MustContain)) {
        $why = "expected output containing '$MustContain' | actual: " + $(if ($text) { 'other text' } else { 'nothing' })
    }
    elseif ($MustBeSilent -and -not [string]::IsNullOrWhiteSpace($text)) {
        $why = "expected no output | actual: " + (($text -replace '\s+', ' ').Substring(0, [Math]::Min(70, $text.Length)))
    }

    if (-not $why) {
        Write-Host ("PASS  {0,-44} exit {1}" -f $name, $code)
    }
    else {
        Write-Host ("FAIL  {0,-44} {1}" -f $name, $why)
        $script:failures++
    }
}

function Json-Path([string]$p) { $p -replace '\\', '\\' }

Write-Host '--- guard-find-command (canon GITHUB_INTERACTION.md section 6) ---'
Invoke-Case 'find / - disk-wide root'          'guard-find-command.ps1' '{"tool_input":{"command":"find / -name x"}}' 2
Invoke-Case 'find . - no -maxdepth'            'guard-find-command.ps1' '{"tool_input":{"command":"find . -name x"}}' 2
Invoke-Case 'find . -maxdepth 2 - allowed'     'guard-find-command.ps1' '{"tool_input":{"command":"find . -maxdepth 2 -name x"}}' 0
Invoke-Case 'find in a quoted pattern - allowed' 'guard-find-command.ps1' '{"tool_input":{"command":"grep -n \"guard-find\" a.md"}}' 0

Write-Host '--- guard-ps1-in-bash (canon GITHUB_INTERACTION.md section 6) ---'
Invoke-Case '.ps1 in command-head position'    'guard-ps1-in-bash.ps1' '{"tool_input":{"command":"./a.ps1 fk"}}' 2
Invoke-Case 'pwsh -File a.ps1 - allowed'       'guard-ps1-in-bash.ps1' '{"tool_input":{"command":"pwsh -NoProfile -File ./a.ps1 fk"}}' 0
Invoke-Case 'grep over a .ps1 - allowed'       'guard-ps1-in-bash.ps1' '{"tool_input":{"command":"grep -n exit scripts/foo.ps1"}}' 0

Write-Host '--- guard-fire-and-forget (canon AI_USAGE.md section 1) ---'
# The allow cases carry the weight: a long job MUST still be able to background itself, or the guard
# collides head-on with the other half of the same canon bullet and gets switched off.
Invoke-Case 'backgrounded closure facade'      'guard-fire-and-forget.ps1' '{"tool_input":{"command":"pwsh -NoProfile -File scripts/post-change.ps1 -File a.kt -ChangeType Kotlin","run_in_background":true}}' 2
Invoke-Case 'backgrounded fast check'          'guard-fire-and-forget.ps1' '{"tool_input":{"command":"pwsh -NoProfile -File ./a.ps1 fk","run_in_background":true}}' 2
Invoke-Case 'backgrounded catalog mutator'     'guard-fire-and-forget.ps1' '{"tool_input":{"command":"pwsh -NoProfile -File scripts/spec_catalog/update.ps1 -Id S0001 -Status Verified","run_in_background":true}}' 2
Invoke-Case 'same facade in foreground - allowed' 'guard-fire-and-forget.ps1' '{"tool_input":{"command":"pwsh -NoProfile -File scripts/post-change.ps1 -File a.kt -ChangeType Kotlin"}}' 0
Invoke-Case 'backgrounded full build - allowed' 'guard-fire-and-forget.ps1' '{"tool_input":{"command":"pwsh -NoProfile -File ./a.ps1 d","run_in_background":true}}' 0
Invoke-Case 'long job chained with a gate - allowed' 'guard-fire-and-forget.ps1' '{"tool_input":{"command":"pwsh -NoProfile -File ./a.ps1 d && pwsh -NoProfile -File scripts/post-change.ps1 -File a.kt","run_in_background":true}}' 0

Write-Host '--- guard-uncapped-read (canon AI_USAGE.md section 3) ---'
$long = Join-Path $repoRoot 'rules/AI_USAGE.md'
$short = Join-Path $repoRoot 'CANON_VERSION'
Invoke-Case 'uncapped read, 200+ lines'        'guard-uncapped-read.ps1' ('{"tool_input":{"file_path":"' + (Json-Path $long) + '"}}') 2
Invoke-Case 'same file with a limit - allowed' 'guard-uncapped-read.ps1' ('{"tool_input":{"file_path":"' + (Json-Path $long) + '","limit":50}}') 0
Invoke-Case 'uncapped read, short file'        'guard-uncapped-read.ps1' ('{"tool_input":{"file_path":"' + (Json-Path $short) + '"}}') 0

Write-Host '--- on-user-prompt (canon AI_USAGE.md sections 3 and 5) ---'
# The Cyrillic below is the point of the case: the nudge decodes stdin as UTF-8 explicitly because the
# default reader corrupts it on a cp1251 console, and a silent miss there disables the hook invisibly.
Invoke-Case 'RU micro-task - nudges'           'on-user-prompt.ps1' '{"prompt":"поменяй цвет кнопки","transcript_path":""}' 0 -MustContain 'RUNG CHECK'
Invoke-Case 'micro-task vetoed by real work'   'on-user-prompt.ps1' '{"prompt":"поменяй цвет кнопки, это краш","transcript_path":""}' 0 -MustBeSilent
Invoke-Case 'long brief - past the ceiling'    'on-user-prompt.ps1' ('{"prompt":"' + ('помен' + 'яй цвет кнопки ' * 20) + '","transcript_path":""}') 0 -MustBeSilent
Invoke-Case 'explicit slash command - silent'  'on-user-prompt.ps1' '{"prompt":"/quick fix the label","transcript_path":""}' 0 -MustBeSilent

Write-Host ''
if ($failures -gt 0) {
    Write-Error "smoke-hooks: $failures case(s) failed" -ErrorAction Continue
    exit 1
}
Write-Host "smoke-hooks: OK (20 cases)"
exit 0
