<#
guard-rules-budget.ps1 - Claude Code PreToolUse hook (matcher: Edit|Write), shipped by the sza plugin.

Stops an always-loaded file from growing without a limit, at the moment it grows.

Canon home: AI_USAGE.md section 5, "The always-loaded set has a budget", and section 4 for the memory index.
Measured on the portfolio, 2026-11-25: one repository's rules file had reached 304,000 characters - about
80,000 tokens on every request of every session - because each ticket appended its notes to the one file that
always loads, and nothing looked at it at the time of the write. The compliance gate (SZA-RULES07) judges the
same budget for every agent, but only when somebody runs it.

What it judges, from the size the file would have AFTER the call:
  CLAUDE.md or AGENTS.md at the root of a canon-adopting repository (.sza-canon.json beside it)
      above 40,000 characters and growing   -> refused
      above 20,000 characters and growing   -> allowed, with a notice
  a Claude auto-memory index (MEMORY.md under .claude)
      above 8,000 characters and growing    -> allowed, with a notice (a memory write is never refused)
An edit that does not make the file longer is always allowed, so a file over the limit can be shrunk.

It refuses instead of rewriting because only the author knows which area the text belongs to.
Escape hatch: SZA_HOOKS_OFF=1. Fails open on any parse, path or IO error. Characters, not bytes.

Contract:
  exit 0, no output            = allow
  exit 0, JSON additionalContext = allow with a notice (no permission decision is made)
  exit 2, reason on stderr     = refuse

Exit codes (DEVELOPMENT.md section 15, reachable-exit-code contract): 0 and 2 as above.
#>

$CoreWarn = 20000
$CoreLimit = 40000
$IndexWarn = 8000

function Allow { exit 0 }

if ($env:SZA_HOOKS_OFF -in @('1', 'true', 'TRUE')) { Allow }

try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $tool = [string]$payload.tool_name
    $in = $payload.tool_input
    $path = [string]$in.file_path
    if ($tool -notin @('Edit', 'Write') -or -not $path) { Allow }

    $leaf = [IO.Path]::GetFileName($path)
    $isIndex = $leaf -eq 'MEMORY.md' -and $path -match '[\\/]\.claude[\\/].*memory[\\/]'
    $isCore = $leaf -in @('CLAUDE.md', 'AGENTS.md') -and
        (Test-Path -LiteralPath (Join-Path ([IO.Path]::GetDirectoryName($path)) '.sza-canon.json'))
    if (-not ($isIndex -or $isCore)) { Allow }

    $current = if (Test-Path -LiteralPath $path) { [IO.File]::ReadAllText($path) } else { '' }
    $before = $current.Length
    if ($tool -eq 'Write') {
        $after = ([string]$in.content).Length
    }
    else {
        $old = [string]$in.old_string
        $delta = ([string]$in.new_string).Length - $old.Length
        $count = 1
        if ($in.replace_all -and $old) { $count = [regex]::Matches($current, [regex]::Escape($old)).Count }
        $after = $before + $delta * $count
    }
    if ($after -le $before) { Allow }

    if ($isCore -and $after -gt $CoreLimit) {
        [Console]::Error.WriteLine("REFUSED (sza rules budget): $leaf would grow to $after characters; the hard limit of an always-loaded rules file is $CoreLimit, because every request of every session pays for it. Put the detail into .claude/rules/<area>.md with a paths: list (or into a tracked document) and keep at most one line or one table row here. An edit that does not lengthen the file is allowed. AI_USAGE.md section 5.")
        exit 2
    }

    $note = $null
    if ($isCore -and $after -gt $CoreWarn) {
        $note = "sza rules budget: $leaf is now $after characters, over the $CoreWarn budget (refused above $CoreLimit). Move this detail to .claude/rules/<area>.md with a paths: list and keep one line here. AI_USAGE.md section 5."
    }
    elseif ($isIndex -and $after -gt $IndexWarn) {
        $note = "sza memory budget: this MEMORY.md is now $after characters, over $IndexWarn, and loads in every session. Keep one short line per durable note; move ticket and campaign state into state/ with its line in state/INDEX.md. AI_USAGE.md section 4."
    }
    if ($note) {
        @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; additionalContext = $note } } | ConvertTo-Json -Compress -Depth 4
    }
}
catch {
    Allow
}
exit 0
