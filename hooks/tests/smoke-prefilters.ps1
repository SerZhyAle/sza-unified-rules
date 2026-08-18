<#
smoke-prefilters.ps1 - prove the REGISTERED pre-filters still reach the payloads their hooks must judge.

This suite exists because of a real regression, and it is the one the canon had no equivalent of. A hook
is wired behind a bash `case` test so PowerShell is spawned only on a payload that could possibly trip it
(AI_USAGE.md section 3). If that pattern matches nothing, the hook is correct and simply never runs - and
a guard that never runs looks exactly like a guard that was never needed. The observed instance: a
pattern `*[A-Z]-[A-Z]*`, intended to catch `Verb-Noun` cmdlets, matched no real cmdlet at all, because in
`Select-Object` the character before the hyphen is lowercase.

So this suite asserts the PATTERN, not the script: it recovers the literal `case` pattern list out of
hooks.json and runs it under Git Bash - the shell the harness actually uses. Testing under the WSL bash
on PATH would test the wrong shell and prove nothing about the registration.

  pwsh -NoProfile -File hooks/tests/smoke-prefilters.ps1

Exit codes (DEVELOPMENT.md section 15, reachable-exit-code contract):
  0  every payload landed on the side of the filter it must
  1  at least one did not
  2  could not verify (hooks.json unreadable, a pattern not recoverable, or no Git Bash found)
#>
$ErrorActionPreference = 'Stop'

$hooksDir = Split-Path $PSScriptRoot -Parent
$hooksJson = Join-Path $hooksDir 'hooks.json'
$failures = 0

function Cannot-Verify([string]$msg) {
    Write-Error "smoke-prefilters: $msg - cannot verify" -ErrorAction Continue
    exit 2
}

if (-not (Test-Path -LiteralPath $hooksJson)) { Cannot-Verify 'hooks.json is missing' }

# Git Bash specifically. `bash` on PATH may be WSL, which is a different shell with different pattern
# behaviour and a different PATH - asserting there would prove nothing about the live registration.
$bash = $null
foreach ($cand in @(
    (Join-Path $env:ProgramFiles 'Git\bin\bash.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe')
)) {
    if ($cand -and (Test-Path -LiteralPath $cand)) { $bash = $cand; break }
}
if (-not $bash) { Cannot-Verify 'Git Bash (Git\bin\bash.exe) not found' }

try { $registered = Get-Content -LiteralPath $hooksJson -Raw | ConvertFrom-Json }
catch { Cannot-Verify "hooks.json is not valid JSON: $_" }

# Recover the command string of the PreToolUse registration that invokes a given script.
function Get-RegisteredCommand([string]$scriptName) {
    foreach ($group in $registered.hooks.PreToolUse) {
        foreach ($h in $group.hooks) {
            if ($h.command -like "*$scriptName*") { return [string]$h.command }
        }
    }
    return $null
}

# Recover the literal pattern list out of `case "$input" in <PATTERNS>)`.
function Get-CasePattern([string]$command) {
    $m = [regex]::Match($command, 'case\s+"\$input"\s+in\s+(?<pat>[^)]+)\)')
    if (-not $m.Success) { return $null }
    return $m.Groups['pat'].Value.Trim()
}

# Run the recovered pattern under Git Bash against one payload. Returns 'match' or 'nomatch'.
function Test-Pattern([string]$pattern, [string]$payload) {
    $snippet = "input=`"`$1`"`ncase `"`$input`" in $pattern) echo MATCH ;; esac`n"
    $tmp = [System.IO.Path]::GetTempFileName() + '.sh'
    try {
        [System.IO.File]::WriteAllText($tmp, ($snippet -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding $false))
        $out = & $bash $tmp $payload 2>&1
        if (($out -join ' ') -match 'MATCH') { return 'match' }
        return 'nomatch'
    }
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

function Json([string]$command) {
    # Build the payload the way the harness does, so quoting inside the command is escaped as it will be
    # live - the slash-argument cases below depend on exactly that escaping.
    return (@{ tool_name = 'Bash'; tool_input = @{ command = $command } } | ConvertTo-Json -Compress)
}

function Assert-Case([string]$label, [string]$pattern, [string]$payload, [string]$expected) {
    $actual = Test-Pattern $pattern $payload
    if ($actual -eq $expected) {
        Write-Host ("PASS  {0,-52} {1}" -f $label, $actual)
    }
    else {
        Write-Host ("FAIL  {0,-52} expected: {1} | actual: {2}" -f $label, $expected, $actual)
        $script:failures++
    }
}

# ------------------------------------------------------------------ the Bash guard: match => the hook runs

$bashCmd = Get-RegisteredCommand 'guard-bash.ps1'
if (-not $bashCmd) { Cannot-Verify 'no PreToolUse registration invokes guard-bash.ps1' }
$bashPat = Get-CasePattern $bashCmd
if (-not $bashPat) { Cannot-Verify 'could not recover the case pattern from the guard-bash registration' }

Write-Host "--- guard-bash pre-filter (must REACH: a payload the script could refuse) ---"
Write-Host "    pattern: $bashPat"
# One per check the script performs, plus the two cmdlet shapes that broke the original pattern.
Assert-Case 'find, no -maxdepth'            $bashPat (Json 'find . -name x') 'match'
Assert-Case 'find, disk-wide root'          $bashPat (Json 'find / -name x') 'match'
Assert-Case '.ps1 in head position'         $bashPat (Json './a.ps1 fk') 'match'
Assert-Case 'cmdlet after a pipe'           $bashPat (Json 'ls | Select-Object -First 3') 'match'
Assert-Case 'cmdlet in head position'       $bashPat (Json 'Get-ChildItem -Recurse') 'match'
Assert-Case 'cmdlet after a separator'      $bashPat (Json 'cd x; Measure-Object') 'match'
Assert-Case 'ps batching idiom, spaced'     $bashPat (Json '& { cmd1; cmd2 }') 'match'
Assert-Case 'ps batching idiom, tight'      $bashPat (Json '&{ cmd1; cmd2 }') 'match'
Assert-Case 'fragile interpreter'           $bashPat (Json 'node -e 1') 'match'
Assert-Case 'slash arg, double-quoted'      $bashPat (Json 'pwsh -File a.ps1 -Reason "/spec-dev now"') 'match'
Assert-Case 'slash arg, single-quoted'      $bashPat (Json "pwsh -File a.ps1 -Reason '/spec-dev now'") 'match'

Write-Host '--- guard-bash pre-filter (must SKIP: the spawn would be pure overhead) ---'
Assert-Case 'plain git'                     $bashPat (Json 'git status') 'nomatch'
Assert-Case 'plain ls'                      $bashPat (Json 'ls -la') 'nomatch'
Assert-Case 'plain cat'                     $bashPat (Json 'cat CANON_VERSION') 'nomatch'
Assert-Case 'plain echo'                    $bashPat (Json 'echo hello world') 'nomatch'
Assert-Case 'grep with a plain pattern'     $bashPat (Json 'grep -n exit tools/check-rules.ps') 'nomatch'
Assert-Case 'git log'                       $bashPat (Json 'git log --oneline -5') 'nomatch'

# ------------------------------------------------------------------ the Read guard: match => the hook is SKIPPED

$readCmd = Get-RegisteredCommand 'guard-uncapped-read.ps1'
if (-not $readCmd) { Cannot-Verify 'no PreToolUse registration invokes guard-uncapped-read.ps1' }
$readPat = Get-CasePattern $readCmd
if (-not $readPat) { Cannot-Verify 'could not recover the case pattern from the guard-uncapped-read registration' }

# This filter is INVERTED: a match exits 0 early, so `match` here means the hook does NOT run. The
# escape hatch is the thing being asserted, which is why it is tested from this side.
Write-Host '--- guard-uncapped-read pre-filter, inverted (match => hook skipped) ---'
Write-Host "    pattern: $readPat"
$withLimit  = (@{ tool_name = 'Read'; tool_input = @{ file_path = 'x.md'; limit = 50 } } | ConvertTo-Json -Compress)
$withOffset = (@{ tool_name = 'Read'; tool_input = @{ file_path = 'x.md'; offset = 10 } } | ConvertTo-Json -Compress)
$uncapped   = (@{ tool_name = 'Read'; tool_input = @{ file_path = 'x.md' } } | ConvertTo-Json -Compress)
Assert-Case 'explicit limit - hook skipped'   $readPat $withLimit  'match'
Assert-Case 'explicit offset - hook skipped'  $readPat $withOffset 'match'
Assert-Case 'uncapped - hook must run'        $readPat $uncapped   'nomatch'

Write-Host ''
if ($failures -gt 0) {
    Write-Error "smoke-prefilters: $failures case(s) failed" -ErrorAction Continue
    exit 1
}
Write-Host 'smoke-prefilters: OK (20 cases)'
exit 0
