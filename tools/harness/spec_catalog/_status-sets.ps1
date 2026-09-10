# Shared lifecycle-status sets for spec_catalog scripts.
#
# Dot-sourced, never invoked: this file sets no preferences, holds no mutable state and
# knows nothing about the catalog journal, so a consumer inherits only these functions.
# Same shape and same reason as `_research-items.ps1` (S1621) - `preview.ps1` sits on the
# `/spec-next` hot path and cannot afford `_lib.ps1`'s `Set-StrictMode -Version Latest`,
# under which its own `$rec.statusNote` read throws on any record without a note.
#
# Consumers: `_lib.ps1` (which re-exports these to the whole spec_catalog CLI) and
# `preview.ps1` (the auto-skip verdict). One definition, one answer - before S1864 the two
# disagreed: `preview.ps1` released a dependent only at `Verified`/`Archived` while this
# library already counted `BlockNeedUserTest` as finished content, so a ticket whose blocker
# had shipped stayed out of the selection for up to seven more days.
#
# Compatible with PowerShell 5.1 and 7+, and safe to load under Set-StrictMode Latest.

. (Join-Path $PSScriptRoot '..\_profile.ps1')
function Test-ReleaseReadyStatus {
    # Ready = the ticket's code is done as far as this release is concerned. Implemented and
    # Verified are self-evident; BlockNeedUserTest counts too, because some flows are very hard
    # to verify and the owner treats a long-pending device check as shipped - if it later turns
    # out broken it simply comes back as fresh work in a later package.
    param([Parameter(Mandatory)][string] $Status)
    return $Status -in @('Implemented', 'Verified', 'BlockNeedUserTest')
}

function Test-BlockerReleasedStatus {
    # Released = this blocker no longer holds its dependents back. That is the release-ready set
    # plus Archived, which is a soft-delete: an archived blocker will never advance, so waiting on
    # it is waiting forever.
    #
    # Why the set is not narrower (S1864): the owner ruling in PLAN/RELEASE_QUEUE.md releases a
    # dependent the moment the blocker reaches BlockNeedUserTest, on the grounds that the code is
    # in the tree by then and only the device pass is left. That reasoning is at least as true of
    # Implemented, and CLAUDE.md section 4 already splits the two release files on exactly this
    # set - so this is that same set, not a second opinion about it.
    #
    # Status ALONE is no longer the whole test - see Test-BlockerReleased below (S2834). This
    # function is kept unchanged for the callers that hold only a status string and have no id to
    # resolve a plan with; a caller that has the blocker's record should ask the combined question.
    param([Parameter(Mandatory)][string] $Status)
    return (Test-ReleaseReadyStatus -Status $Status) -or $Status -eq 'Archived'
}

function Get-TacticalPhaseCounter {
    # The `**Phases:** N / M done` counter from a ticket's tactical INDEX.md, as the string
    # "N/M", or $null when there is no folder, no index or no counter line.
    #
    # Separate from the predicate below only so the two cannot disagree (the S1621 rule): the
    # predicate decides whether a blocker releases and preview.ps1 prints the same numbers in the
    # operator's reason string. Two readers of one line is how a verdict and its explanation
    # start naming different files.
    param(
        # The strategic spec path as the catalog records it, e.g. PLAN/S2662_slug.md. A
        # project-relative path is resolved against the project root rather than the current
        # directory: preview.ps1 is invoked from wherever the caller happens to stand.
        [string] $File
    )

    if (-not $File) { return $null }

    $path = $File
    if (-not [System.IO.Path]::IsPathRooted($path)) {
        try { $path = Join-Path (Get-SzaProjectRoot) $path } catch { return $null }
    }

    # -replace, not ChangeExtension: a slug may carry a dot and ChangeExtension would cut at it.
    $folder = $path -replace '\.md$', ''
    if ($folder -eq $path) { return $null }
    $index = Join-Path $folder 'INDEX.md'
    if (-not (Test-Path -LiteralPath $index)) { return $null }

    $text = Get-Content -LiteralPath $index -Raw -ErrorAction SilentlyContinue
    if (-not $text) { return $null }

    $m = [regex]::Match($text, '(?m)^\*\*Phases:\*\*\s*(\d+)\s*/\s*(\d+)\s*done')
    if (-not $m.Success) { return $null }

    return "$($m.Groups[1].Value)/$($m.Groups[2].Value)"
}

function Test-BlockerPlanComplete {
    # Does this blocker's own tactical plan claim to be finished?
    #
    # The premise S1864 rests on - "the code is in the tree by then" - is a claim about the TREE,
    # and a status cannot make it. A ticket parked at BlockNeedUserTest in the middle of its plan
    # contradicts it outright: measured 2026-09-10 across the FastMediaSorter journal, 14 of the
    # 111 release-ready tickets that own a tactical folder were parked mid-plan, from 0/5 phases
    # done to 8/9, and one of them (S2662 at 0/5) was already releasing a dependent whose phase
    # needed a symbol that phase 02 had not written yet. The dependent's author had noticed and
    # written a prose caveat into his own phase file, which protected exactly that one ticket.
    #
    # The signal is the tactical INDEX.md counter that plan-tick.ps1 maintains and
    # spec-next-preflight.ps1 already reads - no new authoring is asked of any spec. The rejected
    # alternative was a finer dependency grammar (a `Blocker:` token naming a phase or a symbol):
    # it needs new prose in every dependent spec and therefore protects only the ticket whose
    # author remembered to write it, which is the flaw being fixed, not a cure for it.
    #
    # FAIL-OPEN by design. No tactical folder, no INDEX.md, no `**Phases:**` line - release by
    # status, exactly as before. 21 of those same 111 INDEX files carry no counter line, so a
    # fail-closed reading would trade one false release for twenty-one false refusals, and a
    # ticket refused for a missing line in someone else's file has nothing it can do about it.
    param(
        [Parameter(Mandatory)][string] $Id,
        # The blocker's strategic spec path as the catalog records it, e.g. PLAN/S2662_slug.md.
        [string] $File
    )

    $counter = Get-TacticalPhaseCounter -File $File
    if (-not $counter) { return $true }

    $parts = $counter -split '/'
    return ([int]$parts[0] -ge [int]$parts[1])
}

function Test-BlockerReleased {
    # The whole test: has this blocker stopped holding its dependents back?
    #
    # Archived releases unconditionally and is checked FIRST - a soft-deleted ticket will never
    # advance, so its plan's counter is not evidence of anything and waiting on it is waiting
    # forever. Everything else must be release-ready AND carry a finished plan.
    param(
        [Parameter(Mandatory)][string] $Status,
        [Parameter(Mandatory)][string] $Id,
        [string] $File
    )

    if ($Status -eq 'Archived') { return $true }
    if (-not (Test-ReleaseReadyStatus -Status $Status)) { return $false }
    return (Test-BlockerPlanComplete -Id $Id -File $File)
}
