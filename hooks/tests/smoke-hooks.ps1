<#
smoke-hooks.ps1 - prove the shipped hooks still refuse what they must and wave through what they must not.

A guard that over-blocks gets turned off, and then nothing is enforced - the same reasoning CLAUDE.md
applies to check-compliance.ps1 checks. So every refusal here is smoked from both sides: payloads it must
refuse and payloads it must allow. The allow cases are the load-bearing ones.

The pre-filters those hooks are REGISTERED behind are a separate suite - hooks/tests/smoke-prefilters.ps1
- because a correct hook behind a pattern that matches nothing never runs at all, and this file cannot
see that.

  pwsh -NoProfile -File hooks/tests/smoke-hooks.ps1

Exit codes (DEVELOPMENT.md section 15, reachable-exit-code contract):
  0  every case matched its expected verdict
  1  at least one did not
  2  could not verify (a hook script is missing)
#>
$ErrorActionPreference = 'Stop'

$hooksDir = Split-Path $PSScriptRoot -Parent
$repoRoot = Split-Path $hooksDir -Parent
$failures = 0
$cases = 0

foreach ($f in @('guard-bash.ps1', 'guard-uncapped-read.ps1', 'on-user-prompt.ps1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $hooksDir $f))) {
        Write-Error "smoke-hooks: $f is missing - cannot verify" -ErrorAction Continue
        exit 2
    }
}

# An advisory hook always exits 0, and so does the read REWRITER - so the exit code alone cannot tell
# "fired" from "stayed silent". -MustContain / -MustBeSilent is what actually tests those cases.
function Invoke-Case {
    param(
        [string]$name,
        [string]$hook,
        [string]$json,
        [int]$expected,
        [string]$MustContain,
        [switch]$MustBeSilent
    )
    $script:cases++
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
        Write-Host ("PASS  {0,-46} exit {1}" -f $name, $code)
    }
    else {
        Write-Host ("FAIL  {0,-46} {1}" -f $name, $why)
        $script:failures++
    }
}

function Bash-Payload([string]$command) {
    return (@{ tool_name = 'Bash'; tool_input = @{ command = $command } } | ConvertTo-Json -Compress)
}

Write-Host '--- guard-bash: REFUSE (canon GITHUB_INTERACTION.md section 6) ---'
Invoke-Case 'find / - disk-wide root'           'guard-bash.ps1' (Bash-Payload 'find / -name x') 2
Invoke-Case 'find . - no -maxdepth'             'guard-bash.ps1' (Bash-Payload 'find . -name x') 2
Invoke-Case '.ps1 in command-head position'     'guard-bash.ps1' (Bash-Payload './a.ps1 fk') 2
Invoke-Case 'cmdlet in head position'           'guard-bash.ps1' (Bash-Payload 'Get-ChildItem -Recurse') 2
Invoke-Case 'cmdlet after a pipe'               'guard-bash.ps1' (Bash-Payload 'ls | Select-Object -First 3') 2
Invoke-Case 'cmdlet after a semicolon'          'guard-bash.ps1' (Bash-Payload 'cd x ; Measure-Object -Line') 2
Invoke-Case 'ps batching idiom at head'         'guard-bash.ps1' (Bash-Payload '& { cmd1; cmd2 }') 2
Invoke-Case 'slash arg naming a command'        'guard-bash.ps1' (Bash-Payload 'pwsh -NoProfile -File ./a.ps1 -Reason "/spec-dev now"') 2

Write-Host '--- guard-bash: ALLOW - the load-bearing half ---'
Invoke-Case 'find with -maxdepth'               'guard-bash.ps1' (Bash-Payload 'find . -maxdepth 2 -name x') 0
Invoke-Case 'find inside a quoted pattern'      'guard-bash.ps1' (Bash-Payload 'grep -n "guard-find" a.md') 0
Invoke-Case 'pwsh -File a.ps1'                  'guard-bash.ps1' (Bash-Payload 'pwsh -NoProfile -File ./a.ps1 fk') 0
Invoke-Case 'grep over a .ps1'                  'guard-bash.ps1' (Bash-Payload 'grep -n exit scripts/foo.ps1') 0
Invoke-Case 'cmdlet name inside quotes'         'guard-bash.ps1' (Bash-Payload 'echo "Select-Object is a cmdlet"') 0
Invoke-Case 'cmdlet name as an argument'        'guard-bash.ps1' (Bash-Payload 'git log --format=Get-Thing') 0
Invoke-Case 'cmdlet inside a heredoc body'      'guard-bash.ps1' (Bash-Payload "cat <<'EOF' > x.md`nGet-ChildItem -Recurse`nEOF") 0
Invoke-Case 'batching routed through pwsh'      'guard-bash.ps1' (Bash-Payload 'pwsh -NoProfile -Command "& { cmd1; cmd2 }"') 0
Invoke-Case 'brace group after &&'              'guard-bash.ps1' (Bash-Payload 'ls -la && { echo ok; }') 0
Invoke-Case 'hyphenated real binary'            'guard-bash.ps1' (Bash-Payload 'docker-compose up -d') 0
Invoke-Case 'capitalized flag, not a cmdlet'    'guard-bash.ps1' (Bash-Payload 'gh pr list --json Number-Title') 0
Invoke-Case 'env-assignment prefix'             'guard-bash.ps1' (Bash-Payload 'MSYS2_ARG_CONV_EXCL=* pwsh -NoProfile -File ./a.ps1') 0
Invoke-Case 'interpreter name inside a path'    'guard-bash.ps1' (Bash-Payload 'ls /c/tools/python/lib') 0
Invoke-Case 'slash arg is an absolute path'     'guard-bash.ps1' (Bash-Payload 'pwsh -NoProfile -Command "cat /usr/bin/tool"') 0
Invoke-Case 'slash arg is /dev/null'            'guard-bash.ps1' (Bash-Payload 'pwsh -NoProfile -Command "x > /dev/null"') 0
Invoke-Case 'slash arg is an MSYS drive root'   'guard-bash.ps1' (Bash-Payload 'pwsh -NoProfile -File ./a.ps1 -Path "/c/temp"') 0
Invoke-Case 'malformed JSON - fails open'       'guard-bash.ps1' '{not json' 0
Invoke-Case 'empty payload - fails open'        'guard-bash.ps1' '' 0

# The interpreter check asks THIS machine, so the expected verdict is computed the same way rather than
# hard-coded: a name that can be made to work (a shim on PATH) must not be refused, which is the canon's
# "prefer making a name work over refusing it". On a machine with a python3 shim and no node, this pair
# asserts both directions at once.
Write-Host '--- guard-bash: interpreter resolution, expectation read off this machine ---'
foreach ($interp in @('python3', 'node')) {
    $resolved = Get-Command -Name $interp -ErrorAction SilentlyContinue
    $expect = if ($resolved) { 0 } else { 2 }
    $label = if ($resolved) { "$interp resolves - allowed" } else { "$interp resolves nowhere - refused" }
    Invoke-Case $label 'guard-bash.ps1' (Bash-Payload "$interp -e 1") $expect
}

Write-Host '--- guard-uncapped-read: REWRITE, not block (canon AI_USAGE.md sections 3 and 5) ---'
$long  = Join-Path $repoRoot 'tools/check-compliance.ps1'   # over the 500-line window
$mid   = Join-Path $repoRoot 'rules/AI_USAGE.md'            # under it - deliberately untouched now
$short = Join-Path $repoRoot 'CANON_VERSION'
function Read-Payload([string]$path, $limit) {
    $ti = @{ file_path = $path }
    if ($null -ne $limit) { $ti['limit'] = $limit }
    return (@{ tool_name = 'Read'; tool_input = $ti } | ConvertTo-Json -Compress)
}
Invoke-Case 'uncapped read over the window'     'guard-uncapped-read.ps1' (Read-Payload $long $null) 0 -MustContain 'updatedInput'
Invoke-Case 'the rewrite names the re-read'     'guard-uncapped-read.ps1' (Read-Payload $long $null) 0 -MustContain 'NOT SHOWN'
Invoke-Case 'the rewrite keeps file_path'       'guard-uncapped-read.ps1' (Read-Payload $long $null) 0 -MustContain 'file_path'
Invoke-Case 'same file with a limit - untouched' 'guard-uncapped-read.ps1' (Read-Payload $long 50) 0 -MustBeSilent
Invoke-Case 'under the window - untouched'      'guard-uncapped-read.ps1' (Read-Payload $mid $null) 0 -MustBeSilent
Invoke-Case 'short file - untouched'            'guard-uncapped-read.ps1' (Read-Payload $short $null) 0 -MustBeSilent
Invoke-Case 'missing file - fails open'         'guard-uncapped-read.ps1' (Read-Payload (Join-Path $repoRoot 'no/such/file.md') $null) 0 -MustBeSilent
Invoke-Case 'malformed JSON - fails open'       'guard-uncapped-read.ps1' '{not json' 0 -MustBeSilent

Write-Host '--- on-user-prompt (canon AI_USAGE.md sections 3 and 5) ---'
# The Cyrillic below is the point of the case: the nudge decodes stdin as UTF-8 explicitly because the
# default reader corrupts it on a cp1251 console, and a silent miss there disables the hook invisibly.
Invoke-Case 'RU micro-task - nudges'            'on-user-prompt.ps1' '{"prompt":"поменяй цвет кнопки","transcript_path":""}' 0 -MustContain 'RUNG CHECK'
Invoke-Case 'micro-task vetoed by real work'    'on-user-prompt.ps1' '{"prompt":"поменяй цвет кнопки, это краш","transcript_path":""}' 0 -MustBeSilent
Invoke-Case 'long brief - past the ceiling'     'on-user-prompt.ps1' ('{"prompt":"' + ('помен' + 'яй цвет кнопки ' * 20) + '","transcript_path":""}') 0 -MustBeSilent
Invoke-Case 'explicit slash command - silent'   'on-user-prompt.ps1' '{"prompt":"/quick fix the label","transcript_path":""}' 0 -MustBeSilent

Write-Host ''
if ($failures -gt 0) {
    Write-Error "smoke-hooks: $failures of $cases case(s) failed" -ErrorAction Continue
    exit 1
}
Write-Host "smoke-hooks: OK ($cases cases)"
exit 0
