<#
guard-find-command.ps1 - Claude Code PreToolUse hook (matcher: Bash), shipped by the sza plugin.

Blocks a shell `find` that can orphan a whole-disk scan:
  - a disk-wide root start path (/, //, ~, drive root, /c/, //host), OR
  - a find without -maxdepth (unbounded depth).

Canon home: GITHUB_INTERACTION.md section 6 "Bash / tooling safety", which states the rule AND that it
must be enforced by a pre-tool hook rather than trusted as a convention. This file is that enforcement.

Rationale: on Windows/MSYS a dropped or timed-out session leaves the grandchild find.exe running against
the whole disk, flooding OS handles. A rule in a rules file is guidance the model can skip - measured
across this portfolio, gated rules held at ~99% and ungated ones at 1-8% (AI_USAGE.md section 5). This
runs in the harness before bash spawns, so a blocked command never starts a scan.

Applies in every repository, not only in canon adopters: the failure is a property of the operating
system and the harness, not of a project's conventions. Escape hatch: set SZA_HOOKS_OFF=1.

Contract:
  exit 2 = block the tool call (stderr is shown to Claude)
  exit 0 = allow
Fail-open on any parse error so a malformed payload never breaks Bash globally.

Exit codes (DEVELOPMENT.md section 15, reachable-exit-code contract):
  0  allow - not a dangerous find, or the payload could not be judged.
  2  block - disk-wide root start path, or no -maxdepth.
#>

function Allow { exit 0 }
function Deny([string]$msg) { [Console]::Error.WriteLine($msg); exit 2 }

if ($env:SZA_HOOKS_OFF -in @('1', 'true', 'TRUE')) { Allow }

# Split on bash command separators that sit OUTSIDE single/double quotes, so a `find` inside a quoted
# grep pattern (e.g. "guard-find\|find safety") is never mistaken for a command head. { } are not
# separators - a leading `{` is trimmed off the segment below.
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
if ($cmd -notmatch 'find') { Allow }

# Split into pipeline/list/subshell/substitution segments (quote-aware) so a `find` buried in $(...),
# (...) or `...` is still inspected, but a `find` inside a quoted grep pattern like
# "guard-find\|find safety" is NOT mistaken for a command head.
$segments = Split-UnquotedSegments $cmd

# A start path that maps to a disk-wide root (each matched against a single token).
$broadRoot = @(
    '^/$',                # POSIX root
    '^//$',               # UNC / MSYS double-slash root
    '^~/?$',              # home root
    '^[A-Za-z]:[\\/]?$',  # drive root: c:  c:/  c:\
    '^/[A-Za-z]/?$',      # MSYS drive root: /c  /c/
    '^//[^/\s]+/?$'       # UNC host root: //host  //host/
)
$prefixTokens = @('sudo', 'time', 'nice', 'command', 'env', 'builtin', 'exec', '\')

$advice = 'Use the Glob or Grep tool, or the project''s own catalog/index query script where it has one.'

foreach ($seg in $segments) {
    if ([string]::IsNullOrWhiteSpace($seg)) { continue }
    $s = $seg.Trim().TrimStart('(', '{', ' ')
    if ($s -eq '') { continue }

    $tokens = @($s -split '\s+' | Where-Object { $_ -ne '' })
    if ($tokens.Count -eq 0) { continue }

    # Skip leading env-assignments (VAR=val) and benign command prefixes.
    $i = 0
    while ($i -lt $tokens.Count -and ($tokens[$i] -match '^[A-Za-z_]\w*=' -or $prefixTokens -contains $tokens[$i])) { $i++ }
    if ($i -ge $tokens.Count) { continue }

    $head = $tokens[$i]
    if ($head -notmatch '(^|[\\/])find(\.exe)?$') { continue }

    $rest = @(if ($i + 1 -le $tokens.Count - 1) { $tokens[($i + 1)..($tokens.Count - 1)] } else { @() })

    # Disk-wide root start path anywhere in the arguments.
    $broad = $false
    foreach ($t in $rest) {
        $p = $t.Trim('"', "'")
        foreach ($rx in $broadRoot) { if ($p -match $rx) { $broad = $true; break } }
        if ($broad) { break }
    }
    if ($broad) {
        Deny("Blocked by sza guard-find-command (canon GITHUB_INTERACTION.md section 6): find with a disk-wide root path (/, ~, drive root, /c/, //host). On Windows/MSYS an orphaned find.exe from a dropped session keeps scanning the whole disk and floods handles. $advice If you truly need find, give it a concrete non-root start path AND -maxdepth N.")
    }

    # Unbounded depth: no -maxdepth.
    $hasMaxdepth = (($rest -join ' ') -match '(^|\s)-maxdepth(\s|=|$)')
    if (-not $hasMaxdepth) {
        Deny("Blocked by sza guard-find-command (canon GITHUB_INTERACTION.md section 6): find without -maxdepth. An unbounded find can orphan on Windows/MSYS and scan the whole disk, flooding handles. $advice If you truly need find, add -maxdepth N and a concrete start path.")
    }
}

Allow
