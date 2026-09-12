[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Id
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')

# Gate for a transition INTO BlockNeedUserTest - see S2324.
#
# Contract:
#   - CLAUDE.md Rule 2 states the debug-probe invariant as an equivalence: a
#     Timber.d("Sxxxx: ..") line exists in source if and only if Sxxxx is in
#     BlockNeedUserTest. The forward half is enforced hard - a probe whose ticket is not
#     in that status is a FAIL in assert-no-ticket-logs.ps1. The reverse half had no gate
#     at the moment it becomes violable, which is this transition.
#   - Measured 2026-09-02: 20 tickets sat in BlockNeedUserTest with no probe, and the set
#     was not a static remainder - it had turned over since 2026-09-01, gaining S1617,
#     S1955 and S1984 in a single day. A backlog that refills needs a gate, not a sweep.
#   - Why nothing caught it: post-change.ps1 hands the tree gate -ChangedFiles under
#     -ScopeToFile, which by S1912's design downgrades the missing-probe half to exit 3,
#     an advisory. The only fatal check left was assert-fast-gates.ps1, project-wide - so
#     it went red for whichever session happened to run it, over debt belonging to twenty
#     other tickets, which that session could not fix. /spec-check's own step 6 meanwhile
#     instructed "add one .. or the ticket-log gate refuses the close" - a refusal that
#     did not exist on any closing path.
#   - Assert-ClosingGates is the one point all three status-writing paths reach
#     (update.ps1, close.ps1, bulk-update.ps1), which is why the gate sits there rather
#     than in a command file that only one pipeline reads.
#   - The order this demands is the order Rule 2 already prescribes: the probe is the last
#     code edit BEFORE the status flip, so it is in the tree by the time this runs.
#   - Two ways to pass, and the refusal text names both. A ticket that changed only
#     documentation, scripts or resources has no executable path to instrument; it belongs
#     in scripts/quality/blockneedusertest-probe-baseline.txt with a stated reason. Refusing
#     those outright would make them unclosable, which is a worse failure than the gap.
#   - "Carries a probe" is decided by scripts/quality/lib/blockneedusertest-probes.ps1, the
#     same code assert-no-ticket-logs.ps1 uses. A second implementation would let this gate
#     refuse a transition the tree gate is content with (the S1621 rule); it is not
#     hypothetical, because a Timber call may span physical lines and a per-line search
#     finds a strictly smaller set.
#
#   - S2934 - and the probe must be one this status can be LEFT with. The shape half of Rule 2
#     ("a probe owns its line, whole") used to be judged only by the consumer's tree gate, after
#     the fact, so the moment a probe was created was the one moment nothing judged whether it
#     could ever be removed; the violation then surfaced on a project-wide run belonging to a
#     session that had not written it. Both questions live in this one checker on purpose: split
#     across two, presence answers PASS on a line shape answers FAIL about, and an operator with
#     two verdicts for one line believes the kinder one. The predicate is probes.ownLineRegex,
#     the same key assert-no-ticket-logs.ps1 reads - the S1621 rule again, one sentence, one
#     definition.
#
# Exit codes: 0 = a probe exists in a shape a bulk delete can drop, or the ticket is excused in
#                 the baseline.
#             1 = no probe, or a probe that shares its line with code - the transition must not
#                 proceed. One code for both because the reaction is the same (fix the source and
#                 re-run); the refusal text names which half fired.
#             2 = bad invocation (malformed id, or an id no record carries), or catalog /
#                 sources unreadable. Kept distinct from 1 because "this ticket does not
#                 exist" and "this ticket forgot its probe" call for opposite reactions, and
#                 exit 1 phrases the refusal as the latter - it would tell the operator to add
#                 a probe for an id that names nothing, or to excuse it in the baseline forever.

. (Join-Path $PSScriptRoot '_lib.ps1')

if ($Id -notmatch '^S\d{4}$') {
    # -ErrorAction Continue, not a bare Write-Error: _lib.ps1 sets $ErrorActionPreference = 'Stop',
    # under which a bare Write-Error throws and the documented `exit 2` is never reached (S1070).
    Write-Error "Invalid -Id '$Id' (must match S####)." -ErrorAction Continue
    exit 2
}

# A well-formed id that names no record is still a bad invocation, not a missing probe. Without
# this the gate answers "add a probe for S9999", which is unactionable, and the caller cannot tell
# a typo from a real refusal - the same "could not look is not found nothing" split the source-root
# check below makes. Matches check-audit-recorded.ps1, the sibling gate in this list.
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
    # "Could not look" is not "found nothing" - a checkout without the modules must not
    # silently certify every ticket as probed.
    Write-Error "No source root to scan under $repoRoot (expected one of: $((Get-SzaProfileValue 'probes.scanRoots') -join ', '))." -ErrorAction Continue
    exit 2
}

$baselinePath = Get-ProbeBaselinePath -RepoRoot $repoRoot
$excused = Get-ExcusedProbeTickets -BaselinePath $baselinePath
if ($excused.Contains($Id)) {
    Write-Output "PASS $Id"
    Write-Output "Excused in blockneedusertest-probe-baseline.txt - no executable path to instrument."
    exit 0
}

$hit = Test-TicketProbeInSource -Id $Id -SourceRoots $sourceRoots -All
if ($hit.Found) {
    # S2934 - the second question, asked of every hit rather than of the first. Until this, the one
    # moment a probe appears was the one moment nothing judged whether it could ever be REMOVED, and
    # the violation surfaced later on a project-wide run belonging to another session. A malformed
    # probe deliberately does not satisfy presence: two checkers would answer PASS and FAIL about the
    # same line, and this checker exists to state the sentence whole - the ticket carries a probe
    # that will survive the bulk delete which ends this status.
    $ownLineRx = [regex]([string](Get-SzaProfileValue 'probes.ownLineRegex'))
    $malformed = @($hit.Hits | Where-Object { -not $ownLineRx.IsMatch($_.LineText) })
    if ($malformed.Count -gt 0) {
        Write-Output "FAIL $Id"
        Write-Output ("- {0} probe(s) of this ticket share a line with code, or wrap across lines:" -f $malformed.Count)
        foreach ($bad in $malformed) {
            $badRel = $bad.File.Substring($repoRoot.Length).TrimStart('\', '/')
            Write-Output ("    {0}:{1}  {2}" -f ($badRel -replace '\\', '/'), $bad.Line, $bad.LineText)
        }
        Write-Output ""
        # Plain concatenation, not -f: the forbidden shapes are mostly braces, and a lone '}' in a
        # .NET format string throws FormatException - so the refusal would crash exactly where it
        # has something to say.
        $callName = [string](Get-SzaProfileValue 'probes.callName')
        Write-Output "A probe owns its line, whole. It is removed in BULK when this ticket leaves"
        Write-Output "BlockNeedUserTest, and a line-wise delete is only safe when dropping the line drops"
        Write-Output "exactly the probe and nothing else. Measured shapes where it did not:"
        Write-Output ("    }.also { " + $callName + "(..) }            - the line is also a block terminator")
        Write-Output ("    ).also { " + $callName + "(..) }            - the line also closes an argument list")
        Write-Output ("    if (cond) " + $callName + "(..)             - the line also carries the condition")
        Write-Output ("    any " + $callName + "( whose arguments continue on the next line")
        Write-Output "Removing such a line broke the build with 'Unresolved reference' several hundred"
        Write-Output "lines from anything the sweep aimed at."
        Write-Output ""
        Write-Output ("Correct shape:  {0}" -f (Get-SzaProbeCallExample -Id $Id -Message '<what ran>'))
        Write-Output "one statement, alone on its own line, ending in ')'."
        exit 1
    }
    $rel = $hit.File.Substring($repoRoot.Length).TrimStart('\', '/')
    Write-Output "PASS $Id"
    Write-Output ("Probe present: {0}:{1}  ({2} in all, each alone on its line)" -f $rel, $hit.Line, $hit.Hits.Count)
    exit 0
}

Write-Output "FAIL $Id"
Write-Output ("- no {1} under {2}, and no row in {3}." -f $Id, (Get-SzaProbeCallExample -Id $Id), ((Get-SzaProfileValue 'probes.scanRoots') -join ' or '), (Get-SzaPath 'probeBaseline' -Relative))
Write-Output ""
Write-Output "BlockNeedUserTest means a human still has to watch this run on a device."
Write-Output "Without the probe the log cannot tell 'the scenario went through the new code'"
Write-Output "from 'the scenario never reached it', so the device pass proves nothing."
Write-Output "Do one of:"
Write-Output ("  1. add one probe at the entry of the flow this ticket changed:  {0}" -f (Get-SzaProbeCallExample -Id $Id -Message '<what ran>'))
Write-Output ("  2. if the ticket changed no executable path (docs, scripts, resources only), add a row")
Write-Output ("     to {1}: `"{0}  <why a probe cannot exist, and what the human reads instead>`"" -f $Id, (Get-SzaPath 'probeBaseline' -Relative))
Write-Output ""
Write-Output "Insert the probe BEFORE flipping the status - that is the order CLAUDE.md Rule 2 already prescribes."
Write-Output ""
Write-Output "Why this is a gate and not a sweep (S2324): measured 2026-09-02, 20 tickets sat"
Write-Output "in BlockNeedUserTest with no probe, and the set had turned over rather than shrunk"
Write-Output "- it gained three in a single day. A backlog that refills needs a gate at the"
Write-Output "moment the invariant becomes violable, which is this transition. Nothing caught it"
Write-Output "before because post-change.ps1 scopes the tree gate and downgrades this half to an"
Write-Output "advisory, leaving the project-wide run as the only fatal one - red for whichever"
Write-Output "session happened to run it, over debt belonging to tickets it could not fix."
exit 1
