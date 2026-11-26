# What a `## Last Audit` block must hold before a ticket may enter Verified (TASK-FLOW 0.48, section 24).
# Read by check-audit-recorded.ps1 (the gate) and list-thin-verified.ps1 (the report), so the two cannot disagree.
# Dot-source; the functions judge lines and touch no file.

# An executed-check line: a command between backticks and, after the closing backtick, `exit 0` on the same line -
# also spelled `exit code 0`, `exit: 0`, `exit=0`, any letter case. An unticked list item is a check still to run.
$script:SzaExecutedCheckPattern = '(?i)^(?!\s*(?:(?:\d+\.|[-*+])\s+)?\[ \]).*`[^`]+`.*?\bexit(?:\s+code)?\s*[:=]?\s*0\b'

# A line that opens a release item: RELEASE in capitals first on the line, after an optional list marker, check box
# and bold mark. A line that reads only `RELEASE: none` or `RELEASE - 0` says there is none. RELEASE_QUEUE.md and
# RELEASE-LEDGER are names, not items.
$script:SzaReleaseItemPattern = '^\s*(?:(?:\d+\.|[-*+])\s+)?(?:\[[ xX]\]\s*)?(?:\*\*)?RELEASE(?![\w-])(?!(?i:\s*(?:\*\*)?\s*[:-]\s*(?:\*\*)?\s*(?:none|0)\s*\.?\s*$))'

# The tally of the block's `**Counts:**` line.
$script:SzaReleaseCountPattern = '^\s*(?:\*\*)?Counts:(?:\*\*)?.*?\bRELEASE\s+(\d+)'

function Get-AuditEvidence {
    # Lines of one audit block, without its heading. Returns the two figures and what is missing for Verified.
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]] $Lines)

    $executed = @($Lines | Where-Object { $_ -cmatch $script:SzaExecutedCheckPattern }).Count
    $items = @($Lines | Where-Object { $_ -cmatch $script:SzaReleaseItemPattern }).Count
    $counted = 0
    foreach ($line in $Lines) {
        if ($line -cmatch $script:SzaReleaseCountPattern) { $counted = [int]$Matches[1]; break }
    }
    $unrun = [Math]::Max($counted, $items)

    $missing = [System.Collections.Generic.List[string]]::new()
    if ($executed -eq 0) { $missing.Add('no executed-check line: a command between backticks followed by `exit 0`') }
    if ($unrun -gt 0) { $missing.Add("open RELEASE items: $unrun") }
    return [pscustomobject]@{ Executed = $executed; Unrun = $unrun; Missing = $missing.ToArray() }
}
