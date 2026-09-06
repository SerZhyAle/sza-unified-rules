# Shared resolver for a spec's DIRECTIONAL blocker links.
#
# Dot-sourced, never invoked: this file sets no preferences, holds no mutable state and
# knows nothing about the catalog journal, so a consumer inherits only these functions.
# That is the point of it being separate from `_lib.ps1` - `preview.ps1` sits on the
# `/spec-next` hot path and cannot afford `_lib.ps1`'s `Set-StrictMode -Version Latest`,
# under which its own `$rec.statusNote` read throws on any record without a note (S1621).
#
# Consumers: `preview.ps1` (the auto-skip verdict) and `check-block-note.ps1` (the closing
# gate on entry into BlockByOtherTask, S2581). One resolution, one answer: the gate refuses
# exactly what the picker would later call `blocker-unresolvable`, rather than holding a
# second opinion about it. Before S2581 only the picker knew, and it said so silently and
# late - S1126 sat unselectable for two weeks with its diagnosis reaching nobody.
#
# Compatible with PowerShell 5.1 and 7+, and safe to load under Set-StrictMode Latest.

function Get-BlockerLinks {
    # Resolve the ids this spec is BLOCKED BY. Only sources whose FORM states the direction,
    # because "related to" is not "blocked by" (S1482). Two of them: a `**Depends on:**` line,
    # else every explicit `Blocker:` / `Блокер:` token in the `## 10.` section and in the
    # catalog record's statusNote.
    #
    # Section 10 is deliberately NOT scraped for bare ids. Its heading is "Связи с другими
    # спеками" and it lists consumers, successors and neighbours next to blockers: 98 spec files
    # yield ids there against 15 with a real Depends-on line, so the scrape made a producer look
    # blocked by its own consumers. Direction is not recoverable from that prose either - of the
    # 20 section-10 lines containing "блокир", most use it to DENY a dependency ("не блокирует",
    # "блокирующей зависимости нет", "зависимость снята"), so a keyword filter would invert the
    # arrow exactly where the author took care to say there is none.
    #
    # The token source is S1073's, promoted ahead of the section body and widened: `Matches` not
    # `Match`, so a ticket recording two blockers no longer loses the second, and the same token
    # is honoured in the spec file as well as in the note. Only that token, never every Sxxxx
    # around it: S0426-S0429 each mention two ids (".. Blocker: S0404" plus a passing "for S0429,
    # external OAuth/CASA cost"), so scraping all of them names a sibling as a blocker - the right
    # verdict for the wrong reason.
    #
    # Returns the ids as a plain array, unrolled by the pipeline; a caller that needs a
    # guaranteed collection wraps the call in @(). No `return ,$array` here - that layer
    # survives a pipeline and reaches Where-Object as one object (S2420).
    param(
        [string] $SpecText,
        [string] $StatusNote,
        # Excluded from the result: a spec naming its own id in section 10 is describing
        # itself, and a ticket blocked by itself would deadlock the picker.
        [string] $SelfId
    )

    $text = if ($null -ne $SpecText) { [string]$SpecText } else { '' }
    $note = if ($null -ne $StatusNote) { [string]$StatusNote } else { '' }

    $ids = @()
    $depMatch = [regex]::Match($text, '(?ms)\*\*Depends on:\*\*\s*(.+?)(?:^\*\*|\r?\n##\s|\z)')
    if ($depMatch.Success) {
        $ids = @([regex]::Matches($depMatch.Groups[1].Value, '\bS\d{4}\b') | ForEach-Object { $_.Value })
    }
    else {
        $tokenText = $note
        $sec10Match = [regex]::Match($text, '(?ms)^##\s+10\.[^\n]*\n(.+?)(?:\r?\n##\s|\z)')
        if ($sec10Match.Success) { $tokenText = $sec10Match.Groups[1].Value + "`n" + $tokenText }
        $ids = @([regex]::Matches($tokenText, '(?i)(?:Blocker|Блокер)\s*:\s*\**\s*(S\d{4})') |
            ForEach-Object { $_.Groups[1].Value })
    }

    $ids = @($ids | Sort-Object -Unique)
    if ($SelfId) { $ids = @($ids | Where-Object { $_ -ne $SelfId }) }
    return $ids
}
