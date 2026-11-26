# The part of a captured pass log a usage limit is read from (TASK-FLOW 0.50).
#
# Dot-sourced, never invoked. One function and one variable, nothing else and no dependency, so the repository
# runner's detector (_limit-hold.ps1) and the portfolio's reset-time reader (portfolio/lib/agents.ps1) share one
# reading of "the end of the log".
#
# Compatible with PowerShell 7+, and safe to load under Set-StrictMode Latest.

# The lines at the end of a captured log that a text detector is matched against.
$script:LimitLogTailLines = 40

function Get-LimitLogTail {
    <#
    .SYNOPSIS
        The last lines of a captured log: the only part a limit and its reset time are read from.
    .DESCRIPTION
        LimitLogTailLines (40) lines from the end, joined by a newline. A provider ends a limited
        pass with its own message, so the message is among them; what the child read and wrote before
        is not. The whole log quotes that - a tool output carries the ticket's text, and "rate limit"
        appears in tickets.
    #>
    param([string] $LogBody)
    $lines = @($LogBody -split "`r?`n")
    # A log that ends with a newline has no empty last line.
    if ($lines.Count -gt 1 -and $lines[-1] -eq '') { $lines = @($lines | Select-Object -SkipLast 1) }
    $take = [Math]::Min($script:LimitLogTailLines, $lines.Count)
    if ($take -lt $lines.Count) { $lines = @($lines | Select-Object -Skip ($lines.Count - $take)) }
    return ($lines -join "`n")
}
