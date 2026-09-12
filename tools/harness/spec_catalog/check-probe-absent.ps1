[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Id
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')

# Gate for a transition OUT of BlockNeedUserTest - see S2934.
#
# Contract:
#   - CLAUDE.md Rule 2 states the debug-probe invariant as an equivalence: a probe exists in source
#     if and only if its ticket is in BlockNeedUserTest. S2324 gated the entry; this gates the exit,
#     which until now was guarded by nothing at all. Assert-ClosingGates judged $NewStatus only, so
#     BlockNeedUserTest -> In Progress left through its early return with no checker reached - the
#     transition S2531 took, leaving three probes behind.
#   - Why it kept coming back: the leftover probe is visible to everyone and belongs to nobody.
#     Under -ScopeToFile the tree gate prints it as "Outside the changed set - reported, not charged
#     to this run", so another session's closure passes; the project-wide run judges it fatally, so
#     the tree is red for whoever happened to run it. Three clean-ups in five weeks - S2639, S2656,
#     S2929, the last of them six places across three tickets - because the symptom was being fixed.
#   - A refusal, not a deletion. Deleting the probes from here would be a catalog mutator writing
#     source: outside any code-domain lock and outside the closure that judges a source edit. The
#     objection that a refusal strands the ticket is answered by probes.removeCommand, which this
#     refusal prints filled in - the way out is one line, not a search.
#   - The baseline is deliberately NOT consulted. An excused ticket is one with no executable path
#     to instrument, so it has no probe to leave behind and the question does not arise; reading the
#     allow-list here would only let an excused ticket keep a probe it should never have had.
#   - archive.ps1 does not call Assert-ClosingGates and is untouched by this. That is the path the
#     release sweep takes, and it deletes the probes of every ticket it archives and proves it with
#     the tree gate. A hand-written update.ps1 -Status Archived does reach this gate, like any other
#     exit.
#
# Exit codes: 0 = no probe of this ticket remains in source.
#             1 = at least one remains - the transition must not proceed.
#             2 = bad invocation (malformed id, or an id no record carries), or sources unreadable.
#                 Kept distinct from 1 for the reason check-probe-present.ps1 gives: "this ticket
#                 does not exist" and "this ticket left its probes behind" call for opposite
#                 reactions.

. (Join-Path $PSScriptRoot '_lib.ps1')

if ($Id -notmatch '^S\d{4}$') {
    # -ErrorAction Continue, not a bare Write-Error: _lib.ps1 sets $ErrorActionPreference = 'Stop',
    # under which a bare Write-Error throws and the documented `exit 2` is never reached (S1070).
    Write-Error "Invalid -Id '$Id' (must match S####)." -ErrorAction Continue
    exit 2
}

$record = Find-Record -Id $Id
if (-not $record) {
    Write-Error "No record with id '$Id' in the spec catalog." -ErrorAction Continue
    exit 2
}

$probeLib = (Get-SzaHarnessScript 'spec_catalog/lib/blockneedusertest-probes.ps1')
if (-not (Test-Path -LiteralPath $probeLib)) {
    Write-Error "Probe helper not found at $probeLib." -ErrorAction Continue
    exit 2
}
. $probeLib

$repoRoot = (Get-SzaProjectRoot)
$sourceRoots = @(Get-ProbeSourceRoot -RepoRoot $repoRoot)
if ($sourceRoots.Count -eq 0) {
    # "Could not look" is not "found nothing" - a checkout without the modules must not silently
    # certify every ticket as clean, which here would mean certifying that nothing was left behind.
    Write-Error "No source root to scan under $repoRoot (expected one of: $((Get-SzaProfileValue 'probes.scanRoots') -join ', '))." -ErrorAction Continue
    exit 2
}

$hit = Test-TicketProbeInSource -Id $Id -SourceRoots $sourceRoots -All
if (-not $hit.Found) {
    Write-Output "PASS $Id"
    Write-Output "No probe of this ticket remains in source."
    exit 0
}

Write-Output "FAIL $Id"
Write-Output ("- {0} probe(s) of this ticket are still in source:" -f $hit.Hits.Count)
foreach ($h in $hit.Hits) {
    $rel = $h.File.Substring($repoRoot.Length).TrimStart('\', '/')
    Write-Output ("    {0}:{1}  {2}" -f ($rel -replace '\\', '/'), $h.Line, $h.LineText)
}
Write-Output ""
Write-Output "A probe exists in source IF AND ONLY IF its ticket is in BlockNeedUserTest. This"
Write-Output "transition breaks the second half: the ticket is leaving, and the probes are not."
Write-Output "Left behind, they belong to nobody - a scoped closure reports them as someone else's"
Write-Output "and passes, while the project-wide run fails for whichever session happens to run it."
Write-Output ""
$removeCommand = [string](Get-SzaProfileValue 'probes.removeCommand')
if (-not [string]::IsNullOrWhiteSpace($removeCommand)) {
    Write-Output "Clear them, then re-run this transition:"
    Write-Output ("    {0}" -f $removeCommand.Replace('{Id}', $Id))
    Write-Output ""
    Write-Output "The remover refuses a ticket still in BlockNeedUserTest, which this one still is -"
    Write-Output "the status has not been written yet, because this gate runs before the journal."
    Write-Output "That is what the force flag in the command above is for, and the only case it is for."
} else {
    Write-Output ("Delete every {0} line of this ticket from source, then re-run this transition." -f (Get-SzaProbeCallExample -Id $Id))
}
exit 1
