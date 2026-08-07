<#
guard-uncapped-read.ps1 - Claude Code PreToolUse hook (matcher: Read), shipped by the sza plugin.

Blocks the first uncapped read of a large file: a Read call carrying neither `offset` nor `limit`,
against a file longer than 200 lines.

Canon home: AI_USAGE.md section 3, "Read a large file with an explicit range, first time" - which names
this as the single largest avoidable context cost, says outright that it is worth enforcing as a hook
rather than stating as a rule, and requires the escape hatch below. This file is that enforcement.

Rationale, measured on the reference repo: 1,226 such calls - 10.7% of all Reads - carried 43.8% of
every byte ever read into a context window, and only 21.7% of them had a Grep or Glob in the preceding
three turns. The identical advice already ships in the Read tool schema on every single turn and gets 22%
compliance (AI_USAGE.md section 5, "the number that settles rule-or-hook arguments"). That gap between
stated rule and observed behaviour is the whole argument for a hook.

The escape hatch is unconditional by design. Reviewing the doc comments of an affected area, auditing an
implementation end to end (the spec-to-audit skill's self-audit stage), and opening a file that sits
legitimately at the project's size ceiling are all real whole-file reads. Re-issuing the same Read with
an explicit `limit` always passes.

Applies in every repository, not only in canon adopters: the cost is charged by the harness, not by a
project's conventions. Escape hatch for the hook itself: set SZA_HOOKS_OFF=1.

Contract:
  exit 2 = block the tool call (stderr is shown to Claude)
  exit 0 = allow
Fail-open on any parse, path or IO error, so a schema change can never make the Read tool unusable.

Exit codes (DEVELOPMENT.md section 15, reachable-exit-code contract):
  0  allow - not a large uncapped read, or the payload could not be judged.
  2  block - uncapped read of a file over the line threshold.

Latency note: the wiring in hooks.json runs a bash pre-filter first and only pipes the payload here when
it carries neither `limit` nor `offset` - starting pwsh costs ~170-250 ms and paying it on every Read,
including the ~89% that are already capped and would exit at the escape hatch below, was pure overhead
(AI_USAGE.md section 3, "a hook that spawns a shell on every tool call must pre-filter"). The checks
below stay authoritative: the pre-filter can only skip a call this script would allow.
#>

$LineThreshold = 200

function Allow { exit 0 }
function Deny([string]$msg) { [Console]::Error.WriteLine($msg); exit 2 }

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

# A PDF or a notebook is read by page/cell, not by line window, and an image has no lines at all - the
# threshold below would be meaningless for them.
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
            if ($lineCount -gt $LineThreshold) { break }
        }
    }
    finally { $reader.Dispose() }
}
catch {
    Allow
}

if ($lineCount -le $LineThreshold) { Allow }

$name = try { [System.IO.Path]::GetFileName($filePath) } catch { $filePath }

Deny(
    "Blocked by sza guard-uncapped-read: $name is over $LineThreshold lines and this Read has no " +
    "'limit'. Locate the region you need with one Grep or Glob, then issue this same Read once with an " +
    "explicit 'limit' (and 'offset') wide enough to cover it - one narrowing step, then one window. " +
    "A Read carrying an explicit 'limit' is ALWAYS allowed, however large: reviewing the doc comments " +
    "of an affected area, auditing an implementation end to end, and opening a file that sits at the " +
    "project's size ceiling are all legitimate whole-file reads - pass 'limit: 2000' and this hook " +
    "steps aside. Policy: canon AI_USAGE.md section 3, context hygiene."
)
