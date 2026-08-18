<#
guard-uncapped-read.ps1 - Claude Code PreToolUse hook (matcher: Read), shipped by the sza plugin.

REWRITES the first uncapped read of a large file instead of refusing it: a Read call carrying neither
`offset` nor `limit`, against a file longer than the window below, is allowed through with an explicit
`limit` injected and a notice attached naming the exact re-read that returns the rest.

Canon home: AI_USAGE.md section 3, "Read a large file with an explicit range, first time" - which names
this as the single largest avoidable context cost and says outright that it is worth enforcing as a hook
rather than stating as a rule. This file is that enforcement.

WHY IT REWRITES AND NO LONGER BLOCKS. The blocking predecessor of this hook fired 381 times in one week
on the reference machine, and 31.8% of those blocks were answered by re-issuing the same read with an
explicit limit of 1500+ - that is, the whole file anyway. No context was saved and a turn was spent. A
block cannot fix and retry; it can only cost the caller a round trip and hope they choose better. That
generalises to every guard whose objection is "your parameters are wrong" rather than "this call must not
happen", and it is written down as a preference order in AI_USAGE.md section 5: correct the input where
the correct input is knowable, refuse only where no correct input exists.

Rationale for guarding it at all, measured on the reference repo: 1,226 uncapped large reads - 10.7% of
all Reads - carried 43.8% of every byte ever read into a context window, and only 21.7% of them had a
Grep or Glob in the preceding three turns. The identical advice already ships in the Read tool schema on
every single turn and gets 22% compliance (AI_USAGE.md section 5).

THE WINDOW. 500 lines, which is the canon's own "large file" line (DEVELOPMENT.md section 3 backs up any
file over 500 LOC before a risky edit; the file-size ceiling is 1500). Below it nothing is rewritten at
all - a 300-line file is not the cost problem, and a no-op rewrite is risk with no benefit. This is a
deliberate recalibration: the predecessor acted at 200 lines because the cost of acting was a whole turn,
and rewriting costs nothing, so the threshold moves to where the cost actually is.

FAILING OPEN MATTERS MORE HERE THAN IN A BLOCKING GUARD. When a rewriting hook errs it corrupts what the
model reads, rather than merely gating a call, so every uncertain path below allows the call untouched.

The escape hatch is unconditional and unchanged: a Read carrying an explicit `limit` or `offset` never
reaches this script (the bash pre-filter in hooks.json exits first), and is never rewritten if it does.

Applies in every repository, not only in canon adopters: the cost is charged by the harness, not by a
project's conventions. Escape hatch for the hook itself: set SZA_HOOKS_OFF=1.

Contract:
  exit 0 with no output       = allow, untouched
  exit 0 with the JSON below  = allow, with `limit` injected and a notice attached
Never exits 2. Fail-open on any parse, path or IO error, so a schema change can never make Read unusable.

  {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow",
   "updatedInput":{<the COMPLETE original input, plus limit>},"additionalContext":"<the notice>"}}

Two mechanics that are easy to get wrong and were established by probe rather than guess: `updatedInput`
is honoured only alongside permissionDecision "allow" and must be a COMPLETE replacement of the tool
input, not just the changed field; and `additionalContext` reaches the model while a
permissionDecisionReason does not - which is why the notice travels in the former.

Exit codes (DEVELOPMENT.md section 15, reachable-exit-code contract):
  0  always - this hook has no failing verdict.

Latency note: the wiring in hooks.json runs a bash pre-filter first and only pipes the payload here when
it carries neither `limit` nor `offset` - starting pwsh costs ~170-250 ms and paying it on every Read was
pure overhead (AI_USAGE.md section 3, "a hook that spawns a shell on every tool call must pre-filter").
The checks below stay authoritative: the pre-filter can only skip a call this script would have allowed.
#>

$WindowLines = 500

function Allow { exit 0 }

if ($env:SZA_HOOKS_OFF -in @('1', 'true', 'TRUE')) { Allow }

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { Allow }
    $payload = $raw | ConvertFrom-Json
    $toolInput = $payload.tool_input
}
catch {
    Allow
}

if ($null -eq $toolInput) { Allow }

$props = @($toolInput.PSObject.Properties.Name)

# An explicit window - either end of it - is the escape hatch. Present means the caller has already
# decided how much of the file it wants.
if ($props -contains 'offset' -and $null -ne $toolInput.offset) { Allow }
if ($props -contains 'limit' -and $null -ne $toolInput.limit) { Allow }

if ($props -notcontains 'file_path') { Allow }
$filePath = [string]$toolInput.file_path
if ([string]::IsNullOrWhiteSpace($filePath)) { Allow }

# A PDF or a notebook is read by page/cell, not by line window, and an image has no lines at all - a
# `limit` injected into one of those would be meaningless at best and corrupting at worst.
$ext = ''
try { $ext = [System.IO.Path]::GetExtension($filePath).ToLower() } catch { Allow }
if ($ext -in @('.pdf', '.ipynb', '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.svg')) { Allow }

$lineCount = 0
try {
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) { Allow }
    # Count without materialising the file as one string - this hook runs on every uncapped Read call and
    # must not itself become the cost it exists to remove.
    $reader = [System.IO.File]::OpenText($filePath)
    try {
        while ($null -ne $reader.ReadLine()) {
            $lineCount++
            if ($lineCount -gt $WindowLines) { break }
        }
    }
    finally { $reader.Dispose() }
}
catch {
    Allow
}

if ($lineCount -le $WindowLines) { Allow }

$name = try { [System.IO.Path]::GetFileName($filePath) } catch { $filePath }

# The COMPLETE input object, not just the changed field: a partial updatedInput would drop file_path and
# leave the Read unrunnable. Rebuild from the original properties, then set the window.
$updated = @{}
foreach ($p in $toolInput.PSObject.Properties) { $updated[$p.Name] = $p.Value }
$updated['limit'] = $WindowLines

$notice = "sza guard-uncapped-read: $name is over $WindowLines lines and this Read carried no 'limit', " +
          "so it was windowed to the first $WindowLines lines - THE REST OF THE FILE IS NOT SHOWN. If " +
          "you were locating something, narrow with one Grep or Glob and re-issue this Read with an " +
          "'offset' and 'limit' covering the region. If you genuinely need the whole file - auditing an " +
          "implementation end to end, reviewing a file at the project's size ceiling - re-issue it once " +
          "with an explicit 'limit' large enough (e.g. 2000) and this hook steps aside; an explicit " +
          "range is ALWAYS allowed, however large. Policy: canon AI_USAGE.md section 3, context hygiene."

# Compress: -Depth guards against a nested tool input being flattened to a type name.
$out = @{
    hookSpecificOutput = @{
        hookEventName    = 'PreToolUse'
        permissionDecision = 'allow'
        updatedInput     = $updated
        additionalContext = $notice
    }
} | ConvertTo-Json -Depth 10 -Compress

[Console]::Out.WriteLine($out)
exit 0
