<#
guard-ps1-in-bash.ps1 - Claude Code PreToolUse hook (matcher: Bash), shipped by the sza plugin.

Blocks running a PowerShell script (*.ps1) directly as a Bash command, e.g.
  ./a.ps1 fk      .\build.ps1 -Release      scripts/foo.ps1 -X
Bash cannot execute a .ps1: it tries to interpret the UTF-8 BOM + `<#` comment block, dies with
"syntax error near unexpected token `newline`" - AND a backgrounded task still reports exit 0, so a
failed build or check masquerades as passing. That is the canon's "a green can lie" trap in its purest
form (TESTING_AND_QA.md, the evidence rules), and it is why this is a hook and not advice: the failure
mode is a false PASS, which review does not catch.

A .ps1 must run through the interpreter:
  pwsh -NoProfile -File ./a.ps1 fk        (bare `pwsh` resolves via the Git Bash shim)

Only a .ps1 in COMMAND-HEAD position is blocked. These pass through:
  - reading/searching a .ps1 with a real head:  cat/grep/wc/head ... foo.ps1
  - interpreter invocations:  pwsh -File foo.ps1 ,  pwsh -Command "& { .\a.ps1 }"
    (head is the interpreter; the .ps1 is its argument / inside its -Command string)
The Git Bash shim only makes the `pwsh` command NAME resolvable - it does NOT make `./foo.ps1`
runnable, so a head-position .ps1 is always broken here.

Segmentation is quote-aware: bash separators inside single/double quotes are NOT split, so a `.ps1`
buried in a pwsh -Command string is never mistaken for a head. Heredoc bodies (`<<EOF` .. `EOF`, quoted
or not) are removed before segmentation: their newlines would otherwise split a Python/YAML line
mentioning a .ps1 path into its own segment, where the path lands in head position. That over-block was
observed on a legitimate Python string literal in the reference repo. A quoted token in head position is
also never treated as a .ps1 head, for the same reason.

Canon home: GITHUB_INTERACTION.md section 6 "Bash / tooling safety".

Applies in every repository, not only in canon adopters: the whole portfolio is PowerShell-driven and
the trap is a property of Bash, not of a project's conventions. Escape hatch: set SZA_HOOKS_OFF=1.

Contract:
  exit 2 = block the tool call (stderr is shown to Claude)
  exit 0 = allow
Fail-open on any parse error so a malformed payload never breaks Bash globally.

Exit codes (DEVELOPMENT.md section 15, reachable-exit-code contract):
  0  allow - no .ps1 in command-head position, or the payload could not be judged.
  2  block - a .ps1 in command-head position.
#>

function Allow { exit 0 }
function Deny([string]$msg) { [Console]::Error.WriteLine($msg); exit 2 }

if ($env:SZA_HOOKS_OFF -in @('1', 'true', 'TRUE')) { Allow }

# Split on bash command separators that sit OUTSIDE single/double quotes.
# Separators: | ; & ( ) ` and newline (covers ||, &&, |, ;, &, $( ), subshells).
# { } are intentionally NOT separators - a .ps1 inside a pwsh `& { .. }` block must stay attached to its
# `pwsh` head so it is recognised as an interpreter argument.
# Remove heredoc BODIES, keeping the line that opens them (that line is a real command).
# `<<TAG`, `<<'TAG'`, `<<"TAG"`, `<<-TAG` are all recognised; `<<<` (herestring) is not a heredoc and is
# left alone. An unterminated heredoc swallows the rest of the payload, which is the safe direction:
# fewer segments, so fewer chances to over-block.
function Remove-HeredocBodies([string]$text) {
    $lines = $text -split "`r?`n"
    $out = New-Object System.Collections.Generic.List[string]
    $tag = $null
    foreach ($line in $lines) {
        if ($null -ne $tag) {
            if ($line.Trim() -eq $tag) { $tag = $null }
            continue
        }
        $out.Add($line)
        $m = [regex]::Match($line, '(?<!<)<<-?\s*(?:''([^'']+)''|"([^"]+)"|([A-Za-z_][A-Za-z0-9_]*))(?!<)')
        if ($m.Success) {
            $tag = @($m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value |
                Where-Object { $_ })[0]
        }
    }
    return ($out -join "`n")
}

function Split-UnquotedSegments([string]$text) {
    $segs = New-Object System.Collections.Generic.List[string]
    $sb = New-Object System.Text.StringBuilder
    $inS = $false; $inD = $false
    foreach ($c in $text.ToCharArray()) {
        $ch = [string]$c
        if ($inS) { if ($ch -eq "'") { $inS = $false }; [void]$sb.Append($ch); continue }
        if ($inD) { if ($ch -eq '"') { $inD = $false }; [void]$sb.Append($ch); continue }
        switch ($ch) {
            "'"  { $inS = $true; [void]$sb.Append($ch) }
            '"'  { $inD = $true; [void]$sb.Append($ch) }
            '|'  { [void]$segs.Add($sb.ToString()); [void]$sb.Clear() }
            ';'  { [void]$segs.Add($sb.ToString()); [void]$sb.Clear() }
            '&'  { [void]$segs.Add($sb.ToString()); [void]$sb.Clear() }
            '('  { [void]$segs.Add($sb.ToString()); [void]$sb.Clear() }
            ')'  { [void]$segs.Add($sb.ToString()); [void]$sb.Clear() }
            '`'  { [void]$segs.Add($sb.ToString()); [void]$sb.Clear() }
            "`n" { [void]$segs.Add($sb.ToString()); [void]$sb.Clear() }
            default { [void]$sb.Append($ch) }
        }
    }
    [void]$segs.Add($sb.ToString())
    return $segs
}

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { Allow }
    $cmd = [string](($raw | ConvertFrom-Json).tool_input.command)
} catch {
    # Never break Bash on a malformed hook payload.
    Allow
}

if ([string]::IsNullOrWhiteSpace($cmd)) { Allow }
if ($cmd -notmatch '\.ps1') { Allow }

# Benign leading tokens that precede the real command head.
$prefixTokens = @('sudo', 'time', 'nice', 'command', 'env', 'builtin', 'exec', '\')
# Interpreters that legitimately take a .ps1 as an ARGUMENT (head is the interpreter).
$interpreters = @('pwsh', 'pwsh.exe', 'powershell', 'powershell.exe', 'pwsh-preview')

$scanned = Remove-HeredocBodies $cmd
if ($scanned -notmatch '\.ps1') { Allow }

foreach ($seg in (Split-UnquotedSegments $scanned)) {
    if ([string]::IsNullOrWhiteSpace($seg)) { continue }
    $s = $seg.Trim().TrimStart('(', '{', ' ')
    if ($s -eq '') { continue }

    $tokens = @($s -split '\s+' | Where-Object { $_ -ne '' })
    if ($tokens.Count -eq 0) { continue }

    # Skip leading env-assignments (VAR=val) and benign command prefixes.
    $i = 0
    while ($i -lt $tokens.Count -and ($tokens[$i] -match '^[A-Za-z_]\w*=' -or $prefixTokens -contains $tokens[$i])) { $i++ }
    if ($i -ge $tokens.Count) { continue }

    $rawHead = $tokens[$i]
    # A quoted token in head position is a string literal, not a path bash would exec as a script -
    # blocking it is the over-block this guard must not commit.
    if ($rawHead.StartsWith("'") -or $rawHead.StartsWith('"')) { continue }
    $head = $rawHead.Trim('"', "'")
    if ($head -eq '') { continue }

    # An interpreter head is fine - its .ps1 is an argument, not the executable.
    if ($interpreters -contains $head.ToLowerInvariant()) { continue }

    # A .ps1 in command-head position means Bash is being asked to execute it.
    if ($head -match '(?i)\.ps1$') {
        Deny("Blocked by sza guard-ps1-in-bash (canon GITHUB_INTERACTION.md section 6): '$head' is a PowerShell script run directly as a Bash command. Bash cannot execute a .ps1 - it chokes on the BOM + `<#` block ('syntax error near unexpected token newline') and a backgrounded task still reports exit 0, so a failed build/check looks like it passed. Run it through the interpreter: pwsh -NoProfile -File $head <args>  (bare 'pwsh' resolves via the Git Bash shim; run from the repo root). To READ a .ps1, use the Read tool or put a real command first (grep/head ... $head).")
    }
}

Allow
