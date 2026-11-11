[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Id,
    [Parameter(Mandatory)][string] $NewStatus,
    # The note being WRITTEN, not the one on the record. See the contract note below.
    [string] $StatusNote,
    # Whether the caller passed -StatusNote at all. '' and "omitted" are different intents in
    # update.ps1 (clear vs preserve), and only the mutator can tell them apart.
    #
    # [switch], not [bool]: this file is invoked BOTH in-process by Assert-ClosingGates and as a
    # CLI by its test suite, and `pwsh -File .. -NoteSupplied $false` hands the binder the STRING
    # '$false', which [bool] refuses outright - "Cannot convert value System.String to type
    # System.Boolean". The parameter would then fail to bind at all, so every CLI case returned
    # the binder's exit 1 instead of the documented code, and a suite asserting exit 2 for a
    # malformed id would have been reading a bind error as a verdict. A switch binds from both:
    # present/absent at the command line, `NoteSupplied = $true` through the dispatcher's splat.
    [switch] $NoteSupplied
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')

# Gate for a transition INTO any Block* status - see S2581.
#
# Contract:
#   - CLAUDE.md section 4 has listed this first among the gated transitions since it was
#     written: "every entry INTO a Block* status needs -StatusNote '<reason>', and
#     BlockByOtherTask a literal Blocker: Sxxxx token". The same statement stands in
#     .claude/rules/spec-catalog.md and in AGENTS.md. No gate implemented it. Three documents
#     asserted a mechanical refusal that never came, so a reader deciding "the note is
#     optional, the script will stop me anyway" was never stopped.
#   - Measured 2026-09-05 on the live journal: 301 records, 151 in Block*, and exactly ONE
#     carried no note - S1126. The rule was being obeyed by hand at 99.3%, which is the
#     cheapest possible moment to introduce a gate: it lands green and needs no baseline file.
#   - The one violation was not free. preview.ps1 skipped S1126 as `blocker-unresolvable`
#     from 2026-08-21, and that verdict means "fix the spec", not "wait" - so the ticket was
#     unselectable for two weeks while its own diagnosis reached nobody. This gate moves that
#     message from the picker, where it arrives silently and late, to the write that causes it.
#   - The note it judges is the INCOMING one, passed down from the mutator, never the one on
#     the record. At gate time the journal still holds the previous note, and on a
#     Block* -> Block* transition that note describes a different blocker entirely - so a
#     checker reading the record would validate the text being replaced.
#   - Assert-ClosingGates is the one point every status-writing path reaches, which is why the
#     gate sits there rather than in a mutator. There are two such paths into Block*
#     (update.ps1 and bulk-update.ps1; close.ps1 is limited to Verified/Archived by its
#     ValidateSet and complete.ps1 delegates to it), and S1607 measured what happens when a
#     gate is wired into only one of them: it guards the path used least.
#   - BlockByOtherTask needs more than prose. The blocker id must be readable as a literal
#     `Blocker: Sxxxx` token or a `**Depends on:**` line, because section 10 lists consumers
#     and neighbours beside blockers and as often DENIES the dependency it mentions, so a bare
#     id there cannot state which way the arrow points (S1482). "Carries a directional
#     blocker" is decided by _blocker-links.ps1, the same code preview.ps1's auto-skip uses:
#     a second implementation would let this gate refuse what the picker accepts, or worse
#     accept what the picker later skips - which is the exact failure this ticket exists to end.
#   - S0039: a BlockQuestions note is the question itself. The study behind that ticket measured
#     99 of 461 unattended passes ending in BlockQuestions and found 6 of the 11 tickets waiting
#     at the time were not questions at all - owner actions, a tool defect, a deferred idea -
#     and the quiz that drains this status asks exactly what the note asks. So a transition into
#     BlockQuestions is refused unless the note carries a literal `Q:` token whose text ends in
#     `?`, and the refusal names where a non-question impediment belongs instead: an action only
#     the owner can perform goes to BlockNeedUserTest (the list Sweep mode drains), a tool defect
#     becomes a Draft ticket against that tool, a deferred idea its own Draft. Rows already
#     standing in BlockQuestions without the token are untouched: the gate judges the note being
#     written, never the one on the record.
#
# Exit codes: 0 = a reason was supplied (and, for BlockByOtherTask, a directional blocker
#                 resolves; for BlockQuestions, the note carries the Q: question), or the status
#                 is not a Block* one.
#             1 = no reason, a BlockQuestions note without the Q: token, or no directional
#                 blocker - the transition must not proceed.
#             2 = bad invocation (malformed id, or an id no record carries), or the spec file
#                 needed to resolve the blocker cannot be read. Kept distinct from 1 because
#                 "could not look" and "found nothing" call for opposite reactions: exit 1
#                 phrases the refusal as a missing note, and telling the operator to write one
#                 for an id that names nothing is unactionable.

. (Join-Path $PSScriptRoot '_lib.ps1')

if (-not (Test-SzaTicketId $Id)) {
    # -ErrorAction Continue, not a bare Write-Error: _lib.ps1 sets $ErrorActionPreference = 'Stop',
    # under which a bare Write-Error throws and the documented `exit 2` is never reached (S1070).
    Write-Error "Invalid -Id '$Id' (must match $(Get-SzaTicketIdDisplay))." -ErrorAction Continue
    exit 2
}

# Defensive: the dispatcher already filters by status, but a direct caller must not be told
# to write a note for a transition that does not require one.
if ($NewStatus -notlike 'Block*') { exit 0 }

$record = Find-Record -Id $Id
if (-not $record) {
    Write-Error "No record with id '$Id' in the spec catalog." -ErrorAction Continue
    exit 2
}

$note = if ($NoteSupplied) { [string]$StatusNote } else { '' }

if (-not $NoteSupplied -or [string]::IsNullOrWhiteSpace($note)) {
    Write-Output ""
    Write-Output ("{0} -> {1} carries no reason." -f $Id, $NewStatus)
    Write-Output ""
    Write-Output "A Block* status parks a ticket, and the note is the only record of what it is"
    Write-Output "waiting for. Re-run the transition with the reason:"
    Write-Output ""
    Write-Output ("  update.ps1 -Id {0} -Status {1} -StatusNote '<what blocks it, and what resolves it>'" -f $Id, $NewStatus)
    Write-Output ""
    if ($NewStatus -eq 'BlockNeedUserTest') {
        Write-Output "For BlockNeedUserTest the reason is what the human must observe on the device."
    }
    elseif ($NewStatus -eq 'BlockQuestions') {
        Write-Output "For BlockQuestions the reason is the question itself: a literal 'Q:' token whose"
        Write-Output "text ends in '?', because the quiz that drains this status asks exactly what the"
        Write-Output "note asks (S0039)."
    }
    else {
        Write-Output "Describe the blocker and what would clear it - not merely that one exists."
    }
    Write-Output ""
    Write-Output "Why this is refused rather than reported later (S2581): without the note the ticket"
    Write-Output 'is skipped by the picker as `blocker-unresolvable`, which means "fix the spec", not'
    Write-Output '"wait". Measured 2026-09-05, S1126 sat unselectable that way for two weeks and the'
    Write-Output "diagnosis reached nobody, because it is printed where only the picker looks."
    exit 1
}

if ($NewStatus -eq 'BlockQuestions' -and $note -notmatch '(?i)(?<![a-z])(?:Q:\s*[^?]*\?|DO:\s*\S)') {
    Write-Output ""
    Write-Output ("{0} -> BlockQuestions is not a question or pre-implementation DO: action." -f $Id)
    Write-Output ""
    Write-Output "BlockQuestions is the quiz queue: its note must carry either the question itself as a"
    Write-Output "literal 'Q:' token whose text ends in '?' (S0039) or a pre-implementation owner action"
    Write-Output "as a literal 'DO:' token (S0042), because the quiz that drains this status presents"
    Write-Output "exactly what the note records. This note states an impediment that is not a question:"
    Write-Output ""
    Write-Output ("  {0}" -f $note)
    Write-Output ""
    Write-Output "Where an impediment of that kind belongs instead:"
    Write-Output ""
    Write-Output "  - a pre-implementation owner action    -> BlockQuestions with 'DO: <action>' (and - **DO:** in 3.3)"
    Write-Output "  - post-implementation device test      -> BlockNeedUserTest, the list Sweep mode drains"
    Write-Output "  - a defect in a tool or a script       -> a Draft ticket against that tool"
    Write-Output "                                           (a canon tool gets its draft in the canon)"
    Write-Output "  - an idea deferred, not decided        -> its own Draft, parked"
    Write-Output ""
    Write-Output "Re-run with the question or DO: action, or park the ticket where the impediment is drained:"
    Write-Output ""
    Write-Output ("  update.ps1 -Id {0} -Status BlockQuestions -StatusNote 'Q: <the question this ticket waits on>?'" -f $Id)
    Write-Output ("  update.ps1 -Id {0} -Status BlockQuestions -StatusNote 'DO: <pre-implementation owner action>'" -f $Id)
    Write-Output ""
    Write-Output "A question the pass could answer itself with a researched, reversible recommendation"
    Write-Output "was not for the owner at all: take the recommendation and record it under"
    Write-Output "'### Assumed (unattended, <date>)' in the ticket, with the alternative and 'owner may"
    Write-Output "overrule' (S0039). Questions stay for one-way and outward steps, contract changes,"
    Write-Output "scope, money, and facts only the owner knows."
    exit 1
}

if ($NewStatus -ne 'BlockByOtherTask') { exit 0 }

# BlockByOtherTask additionally needs the blocker to be machine-readable, from the note or
# from the spec file - the same channels preview.ps1 and the portfolio dispatcher resolve.
$specText = ''
try {
    $specPath = Resolve-SpecPath -PathRef ([string]$record.file)
    if (Test-Path -LiteralPath $specPath -PathType Leaf) {
        $specText = [System.IO.File]::ReadAllText($specPath)
    }
    else {
        Write-Error ("Spec file not found for {0}: {1}" -f $Id, $specPath) -ErrorAction Continue
        exit 2
    }
} catch {
    Write-Error ("Cannot read the spec file for {0}: {1}" -f $Id, $_.Exception.Message) -ErrorAction Continue
    exit 2
}

. (Join-Path $PSScriptRoot '_blocker-links.ps1')
$blockers = @(Get-BlockerLinks -SpecText $specText -StatusNote $note -SelfId $Id)
$qualified = @(Get-QualifiedBlockerLinks -SpecText $specText -StatusNote $note)

if ($blockers.Count -eq 0 -and $qualified.Count -eq 0) {
    Write-Output ""
    Write-Output ("{0} -> BlockByOtherTask records no blocker in a directional channel." -f $Id)
    Write-Output ""
    Write-Output "The note is present, but nothing in it or in the spec says WHICH ticket blocks this"
    Write-Output "one in a form the tooling can read. Three channels are accepted:"
    Write-Output ""
    Write-Output ("  1. a local token, in the note or in section 10:      Blocker: Sxxxx")
    Write-Output ("  2. a cross-repo token, in the note or in section 10: Blocker: <repoKey>:<id>")
    Write-Output ("  3. a line in the spec file:                          **Depends on:** Sxxxx")
    Write-Output ""
    Write-Output "Naming the ticket in section 10 prose is not enough. That section records consumers,"
    Write-Output "successors and neighbours beside blockers, and of its lines that mention blocking most"
    Write-Output "DENY the dependency ('не блокирует', 'зависимость снята') - so a bare id there would"
    Write-Output "invert the arrow exactly where the author took care to say there is none (S1482)."
    Write-Output ""
    Write-Output "This is the same resolution preview.ps1 uses, so a transition that passes here cannot"
    Write-Output 'be skipped as `blocker-unresolvable` afterwards.'
    exit 1
}

exit 0
