# What a context-handoff marker claims, and whether the claim holds.
#
# Dot-sourced by run-spec-queue.ps1, never invoked. Pure functions, no state, no I/O.
#
# WHY IT EXISTS. A child that finds its context large writes `<tempDir>/<id>/context-handoff.json` and ends,
# and the runner relaunches the ticket with a fresh context (spec-to-audit, "Context handoff"). The marker's
# `tokens` is the child's own figure and nothing measured it: a Codex child, which has no reading of its
# context, wrote `tokens: 0` at the end of every pass of one ticket on 2026-11-20 - five handoffs in six
# minutes, each ~50k tokens, each ending at a planning phase boundary with no source edited. The runner took
# every marker at its word, and a handoff is no idle run, so nothing took the ticket out of the loop but the
# cap of 6. A handoff is now a claim ("my context is large"), and it holds only with a figure at or above the
# minimum; a marker without one is an ordinary end of a pass and is judged as such (idle series, drop for
# this run).
#
# Compatible with PowerShell 5.1 and 7+, and safe under Set-StrictMode Latest.

# The least context a child may claim when it hands the ticket over. S4264 measured over 2026-10-08..15 that
# 37.4% of /spec-all requests ran above 300k tokens; 150k is half of that line - below it a fresh context
# saves little and costs a full re-read of the spec, the rules and the files.
$script:ContextHandoffMinTokens = 150000

function ConvertTo-HandoffTokens {
    <#
        The marker's `tokens` as a whole number, or $null when it is no figure. Accepts a JSON number or the
        shapes an agent writes by hand: "51,710", "51 710", "120k", "1.2m". Zero is a figure (a child that
        says it measured nothing); a negative number, text and an absent value are not.
    #>
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal] -or $Value -is [single]) {
        if ($Value -lt 0) { return $null }
        return [long][Math]::Floor([double]$Value)
    }
    $text = ([string]$Value).Trim() -replace '[,\s_]', ''
    if ($text -notmatch '^(?<n>\d+(?:\.\d+)?)(?<u>[kKmM])?$') { return $null }
    $number = [double]::Parse($Matches['n'], [Globalization.CultureInfo]::InvariantCulture)
    $unit = $Matches['u']
    if ($unit -ieq 'k') { $number *= 1000 }
    elseif ($unit -ieq 'm') { $number *= 1000000 }
    return [long][Math]::Floor($number)
}

function Test-ContextHandoffClaim {
    <#
        Does a marker deserve the relaunch? Valid only when its `tokens` is a figure at or above -MinTokens.
        Returns @{ Valid; Tokens; Reason } - Tokens is $null when there is no figure, Reason is empty when valid.
    #>
    param(
        $Handoff,
        [long] $MinTokens = $script:ContextHandoffMinTokens
    )
    $raw = $null
    if ($null -ne $Handoff) {
        $property = $Handoff.PSObject.Properties['tokens']
        if ($null -ne $property) { $raw = $property.Value }
    }
    $tokens = ConvertTo-HandoffTokens $raw
    if ($null -eq $tokens) {
        return [pscustomobject]@{ Valid = $false; Tokens = $null; Reason = 'the marker carries no token figure' }
    }
    if ($tokens -lt $MinTokens) {
        return [pscustomobject]@{ Valid = $false; Tokens = $tokens; Reason = ('{0} tokens is below the {1} a handoff needs' -f $tokens, $MinTokens) }
    }
    return [pscustomobject]@{ Valid = $true; Tokens = $tokens; Reason = '' }
}
