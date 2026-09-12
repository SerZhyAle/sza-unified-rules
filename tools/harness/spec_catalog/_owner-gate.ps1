# Shared owner-gate detection for spec_catalog scripts.
#
# An owner-gated spec is one the owner starts by hand: its body says so in as many words,
# and no automatic picker, runner or placement may act as if the ticket were ordinary work.
#
# Dot-sourced, never invoked: this file sets no preferences, holds no mutable state beyond a
# read cache keyed by path, and knows nothing about the catalog journal, so a consumer inherits
# only these functions. Same shape and same reason as `_status-sets.ps1` and `_research-items.ps1`
# (S1621) - `preview.ps1` sits on the `/spec-next` hot path and cannot afford `_lib.ps1`'s
# `Set-StrictMode -Version Latest`.
#
# Consumers: `preview.ps1` (the auto-skip verdict) and `_lib.ps1` (where a brand-new release-queue
# row is placed). One definition, one answer - S2921 is what happens without it: the release plan
# ends each package with an owner-gated boundary ticket that is the release line, and the queue
# writer, which had no idea such a row existed, appended every new ticket BELOW it. The row's
# heading then said one package and its position said the next, and six tickets had accumulated
# under that line before anyone read the file closely.
#
# Compatible with PowerShell 5.1 and 7+, and safe to load under Set-StrictMode Latest.

. (Join-Path $PSScriptRoot '..\_profile.ps1')

# Written as a function rather than a variable so a consumer under StrictMode cannot read it
# before this file is loaded, and so the set has exactly one place to grow.
function Get-OwnerGatePattern {
    # Each pattern is a phrase a spec uses to forbid automatic handoff. Two are Russian because
    # the owner writes the directive in the language he plans in; matching is case-insensitive,
    # which is what PowerShell's -match gives by default.
    return @(
        'автоматическая\s+передача\s+отключена',
        'запуск\s+выполняется\s+отдельной\s+командой',
        'owner\s+directive',
        'manual\s+handoff\s+required'
    )
}

function Test-OwnerGateText {
    # The predicate over a spec body already in memory. `preview.ps1` reads the file for six other
    # reasons, so it asks this form and pays for no second read.
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)
    foreach ($pattern in (Get-OwnerGatePattern)) {
        if ($Text -match $pattern) { return $true }
    }
    return $false
}

# Path -> verdict, for the callers that ask about many specs in one run. A spec body does not
# change under a running reconcile, and the alternative is re-reading the same boundary ticket
# once per added row.
$script:OwnerGateVerdictCache = @{}

function Clear-OwnerGateCache {
    $script:OwnerGateVerdictCache = @{}
}

function Test-OwnerGatedSpec {
    # The predicate over a spec FILE. A path that does not resolve answers $false rather than
    # throwing: a queue row whose spec file is missing is a different defect with its own report,
    # and refusing to place the row would turn it into a failed catalog write.
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ($script:OwnerGateVerdictCache.ContainsKey($Path)) { return $script:OwnerGateVerdictCache[$Path] }
    $verdict = $false
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $text = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
        if ($text) { $verdict = Test-OwnerGateText -Text $text }
    }
    $script:OwnerGateVerdictCache[$Path] = $verdict
    return $verdict
}
