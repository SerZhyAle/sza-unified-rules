[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Id
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')

# Gate for transitions INTO a closed status (Implemented / Verified) - see S1606.
#
# Contract:
#   - A closed spec must not carry load-bearing evidence in temp/Sxxxx/. temp/ is
#     declared disposable (CLAUDE.md Rule 1), so a reference there is a promise the
#     repository is not obliged to keep: the file may be swept at any time while the
#     spec keeps saying "Verified". Measured 2026-08-13, 65% of the temp/ paths cited
#     by archived specs already pointed at nothing.
#   - Durable evidence lives in the spec's own directory PLAN/Sxxxx_<slug>/ and is
#     committed, capped at 64 KB per file. Above the cap: reduce to the verdict-bearing
#     extract, or replace the artifact with a reproducing command.
#   - Section 0 is exempt. /spec-draft captures owner/agent text verbatim and its
#     contract forbids editing it; S1606's own capture cites temp/ paths and would
#     otherwise be unfixable without breaking that guarantee.
#   - Archived is deliberately NOT gated: it closes a ticket that already passed this
#     gate, and blocking cleanup would make tidying the catalog harder than leaving it.
#   - S0084: a citation of a file in the spec's own folder (at the spec's current home, outside
#     §0) must name a file that exists. Durable evidence that is cited and absent is as
#     unverifiable as disposable evidence; the relocation step and the rule 70 move are the two
#     writers that can produce it. A glob, a bare directory and the other home's copy are not judged.
#
# Exit codes: 0 = no temp/ evidence and no dangling own-folder citation outside §0. 1 = blockers
# reported. 2 = bad invocation.

. (Join-Path $PSScriptRoot '_lib.ps1')

if (-not (Test-SzaTicketId $Id)) {
    # -ErrorAction Continue, not a bare Write-Error: _lib.ps1 sets $ErrorActionPreference = 'Stop',
    # under which a bare Write-Error throws and the documented `exit 2` is never reached (S1070).
    Write-Error "Invalid -Id '$Id' (must match $(Get-SzaTicketIdDisplay))." -ErrorAction Continue
    exit 2
}

$record = $null
foreach ($r in (Read-Catalog)) { if ($r.id -eq $Id) { $record = $r; break } }
if (-not $record) {
    foreach ($r in (Read-JsonlFile -Path (Get-ArchivePath))) { if ($r.id -eq $Id) { $record = $r; break } }
}
if (-not $record) {
    Write-Error "No record with id '$Id' in the spec catalog." -ErrorAction Continue
    exit 2
}

$repoRoot = (Get-SzaProjectRoot)
# A citation of the per-ticket scratch directory, e.g. temp/S1234/ - built from the profile's
# scratch root and ticket-id grammar so another project's names are judged the same way.
$tempRel = (Get-SzaPath 'tempDir' -Relative).TrimEnd('/')
$scratchCitation = [regex]::Escape($tempRel) + '/' + (Get-SzaTicketIdFragment) + '/'
$specPath = Join-Path $repoRoot ($record.file -replace '/', [IO.Path]::DirectorySeparatorChar)
if (-not (Test-Path -LiteralPath $specPath)) {
    Write-Error "Spec file not found on disk: $specPath" -ErrorAction Continue
    exit 2
}

# The spec file plus its phase files: a tactical plan puts its evidence in the phase
# that produced it, so scanning only the strategic file would miss most citations.
$targets = @($specPath)
$specDir = Join-Path (Split-Path -Parent $specPath) ([IO.Path]::GetFileNameWithoutExtension($specPath))
if (Test-Path -LiteralPath $specDir) {
    foreach ($f in (Get-ChildItem -LiteralPath $specDir -Filter '*.md' -Recurse -File)) {
        $targets += $f.FullName
    }
}

$blockers = New-Object System.Collections.Generic.List[string]
$dangling = New-Object System.Collections.Generic.List[string]

# S0084: a citation of a file in the ticket's own folder must name a file that exists. The scratch rule above stops a
# spec citing disposable evidence; this one stops it citing durable evidence that is not there - the case the
# relocation step (relocate-temp-evidence.ps1) and TASK-FLOW rule 70's move can produce between them, and one no other
# gate caught. Only the folder at the spec's CURRENT home is judged (the citation the relocator writes and the move
# then carries over): a citation of the other directory's copy is neither confirmed nor refused here. A glob or a bare
# directory is not a file citation and is skipped.
$specBaseRel = ((($specPath.Substring($repoRoot.Length).TrimStart('\', '/')) -replace '\\', '/') -replace '\.md$', '')
$ownFolderCitation = [regex]::new('(?<![\w/.\-])' + [regex]::Escape("$specBaseRel/") + '(?<rest>[^\s`''"\)\]\[<>|,;*?]+)')

foreach ($target in $targets) {
    # -Encoding UTF8: spec files are UTF-8 and carry Russian prose. Without it Windows
    # PowerShell decodes them as OEM and the offending line is echoed back as mojibake,
    # which defeats the point of naming the line the owner has to fix.
    $lines = @(Get-Content -LiteralPath $target -Encoding UTF8)
    # §0 is verbatim captured material and is exempt (see header). Only the strategic
    # file carries a §0; phase files are scanned whole.
    $inSectionZero = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^##\s+0\.') { $inSectionZero = $true; continue }
        if ($inSectionZero -and $line -match '^##\s+(?!0\.)') { $inSectionZero = $false }
        if ($inSectionZero) { continue }

        if ($line -match $scratchCitation) {
            $rel = $target.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
            $blockers.Add(('{0}:{1}: {2}' -f $rel, ($i + 1), $line.Trim()))
        }

        foreach ($m in $ownFolderCitation.Matches($line)) {
            # A fragment (file.md#section) and a line suffix (file.txt:12) are not part of the file's name.
            $rest = $m.Groups['rest'].Value -replace '#.*$', ''
            $rest = ($rest.TrimEnd('.', ':') -replace ':\d+(?::\d+)?$', '').TrimEnd('.', ':')
            if (-not $rest -or $rest.EndsWith('/')) { continue }
            $cited = Join-Path $repoRoot ("$specBaseRel/$rest" -replace '/', [IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $cited)) {
                $rel = $target.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
                $dangling.Add(('{0}:{1}: {2}/{3}' -f $rel, ($i + 1), $specBaseRel, $rest))
            }
        }
    }
}

if ($dangling.Count -gt 0) {
    Write-Output "FAIL $Id"
    foreach ($b in $dangling) { Write-Output "- $b" }
    Write-Output ""
    Write-Output "Spec '$Id' cites files in its own folder that do not exist."
    Write-Output "A closed spec must keep its audit trail verifiable. For each path above:"
    Write-Output "  1. restore the file at that path, or"
    Write-Output "  2. correct the citation to the path the file actually has, or"
    Write-Output "  3. replace it with a reproducing command plus its expected result."
    if ($blockers.Count -gt 0) {
        Write-Output ""
        Write-Output "And the scratch citations below:"
        foreach ($b in $blockers) { Write-Output "- $b" }
    }
    exit 1
}

if ($blockers.Count -gt 0) {
    Write-Output "FAIL $Id"
    foreach ($b in $blockers) { Write-Output "- $b" }
    Write-Output ""
    Write-Output "Spec '$Id' cites evidence in $tempRel/, which is disposable."
    Write-Output "A closed spec must keep its audit trail verifiable. For each line above:"
    Write-Output ("  1. move the artifact into {1}/{0}_<slug>/ and cite it there (max 64 KB per file), or" -f $Id, (Get-SzaPath 'specsDir' -Relative))
    Write-Output "  2. reduce it to the verdict-bearing extract and move that, or"
    Write-Output "  3. replace it with a reproducing command plus its expected result."
    Write-Output "A mention that carries no verdict (draft script, .bak, context illustration)"
    Write-Output "can simply be dropped from the closed spec."
    exit 1
}

Write-Output "PASS $Id"
Write-Output ("Scanned {0} file(s); no load-bearing {1}/ evidence outside section 0." -f $targets.Count, $tempRel)
exit 0
