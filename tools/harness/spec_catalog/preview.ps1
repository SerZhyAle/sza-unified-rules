# preview.ps1 - One-shot Stage 3 metadata extractor for a spec
#
# Replaces this bash boilerplate run on every /spec-next round:
#   head -25 PLAN/Sxxxx_*.md
#   grep -n "^## " PLAN/Sxxxx_*.md
#   ls -la PLAN/ | grep Sxxxx
#   grep "Timber\.d\(.Sxxxx:" type=kt
#   select.ps1 -Id Sxxxx
#   select.ps1 -Id <blocker> (for §10 resolution)
#
# All collapsed into one pwsh invocation, one JSON blob.
#
# Exit codes (S1070):
#   0 - preview emitted.
#   2 - cannot run: malformed -Id, spec absent from the catalog (or the catalog unreadable), or its file missing
#       on disk. There is no code 1: this is an extractor, not a gate - it either
#       produces the payload or cannot.
#
# Usage:
#   pwsh -File scripts/spec_catalog/preview.ps1 -Id Sxxxx
#   pwsh -File scripts/spec_catalog/preview.ps1 -Id Sxxxx -Format json
#
# Output (json):
#   {
#     "id":"S0235", "name":"...", "status":"Draft", "priority":80, "tier":3,
#     "file":"PLAN/S0235_*.md", "created":"...", "updated":"...",
#     "frontmatter": { "Status":"Draft", "Priority":"80", "Tier":"3", ... },
#     "sections": ["## 1. Problem", "## 2. Goals", ...],
#     "tactical_folder": false,
#     "last_audit_present": false,
#     "timber_tags_kt": 0,
#     "auto_skip": null,                  # or "tier-5-epic" / "owner-gate" / "blocker-not-verified"
#                                         # / "blocker-unresolvable" / "blocker-cross-repo" (never research-heavy).
#                                         # "blocker-not-verified" covers TWO shapes since S2834:
#                                         # a blocker below the release-ready set, and a
#                                         # release-ready blocker parked mid-plan - the reason
#                                         # string names its `phases N/M`
#     "auto_skip_reason": null,           # human-readable reason
#     "depends_on": [ {"id":"S0241","status":"Verified","file":"PLAN/S0241_slug.md"}, ... ],
#                                         # sourced from a **Depends on:** line, else from every
#                                         # `Blocker:` / `Блокер:` token in section 10 and in the
#                                         # catalog statusNote. Section 10 prose is NOT scraped (S1482)
#     "research_open_count": 5,      # items whose status line says Open - the closing
#                                    # gate's own definition, shared code (S1621)
#     "research_uncarried_count": 5   # of those, the ones naming no `Carrier: Sxxxx`;
#                                    # exactly what check-open-items-carried.ps1 refuses
#   }
#
# The payload is built by Get-SpecPreview (`_spec-preview.ps1`) and the auto-skip verdict inside it by
# Get-SpecAutoSkip (`_auto-skip.ps1`) - the same two functions spec-next-preflight.ps1 calls in-process, so the
# verdict this command prints and the one the picker walks on cannot disagree (S1621, S2581).

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Id,
    [ValidateSet('table', 'json')]
    [string]$Format = 'json'
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')

$ErrorActionPreference = 'Stop'

if (-not (Test-SzaTicketId $Id)) {
    Write-Error "Invalid -Id '$Id' (must match $(Get-SzaTicketIdDisplay))" -ErrorAction Continue
    exit 2
}

$root = (Get-SzaProjectRoot)

# The payload builder and the shared leaf files it stands on (`_research-items.ps1` S1621, `_status-sets.ps1` S1864,
# `_blocker-links.ps1` S2581, `_owner-gate.ps1` S2921). Deliberately NOT `_lib.ps1` in this scope: that library sets
# Set-StrictMode -Version Latest for the scope it is loaded into.
. (Join-Path $PSScriptRoot '_spec-preview.ps1')

# 1. Resolve the catalog record, from one in-memory read of the catalog that also serves every blocker lookup of the
# verdict. The journals are read through `_lib.ps1` - the same reader and the same paths (SPEC_CATALOG_DIR included)
# select.ps1 used when this step spawned it - loaded inside a script block, so its strict mode ends with the block.
try {
    $journalReader = & {
        . (Join-Path $PSScriptRoot '_lib.ps1')
        $active = Read-JsonlFile -Path (Get-CatalogPath)
        # The archive is read only if a lookup misses the active journal (New-AutoSkipCatalog), after this block
        # has returned - so the loader carries the reader and the path with it rather than naming them.
        $readJsonl = ${function:Read-JsonlFile}
        $archivePath = Get-ArchivePath
        [PSCustomObject]@{
            Active        = $active
            ArchiveLoader = { $archived = & $readJsonl -Path $archivePath; $archived }.GetNewClosure()
        }
    }
    $catalog = New-AutoSkipCatalog -Active $journalReader.Active -ArchiveLoader $journalReader.ArchiveLoader
    $rec = Find-AutoSkipRecord -Catalog $catalog -Id $Id
}
catch {
    Write-Error "Spec catalog unreadable: $($_.Exception.Message)" -ErrorAction Continue
    exit 2
}
if (-not $rec) {
    Write-Error "Spec $Id not found in catalog" -ErrorAction Continue
    exit 2
}

$specPath = Join-Path $root $rec.file
if (-not (Test-Path -LiteralPath $specPath)) {
    Write-Error "Spec file not found on disk: $($rec.file)" -ErrorAction Continue
    exit 2
}

# 2-12. The payload.
$result = Get-SpecPreview -Record $rec -Id $Id -Root $root -SpecPath $specPath -Catalog $catalog

if ($Format -eq 'json') {
    $result | ConvertTo-Json -Depth 6 -Compress
}
else {
    Write-Host "$($result.id) preview" -ForegroundColor Cyan
    Write-Host "  $($result.name)" -ForegroundColor White
    Write-Host "  status: $($result.status) | priority: $($result.priority) | tier: $($result.tier)" -ForegroundColor DarkGray
    Write-Host "  file: $($result.file)" -ForegroundColor DarkGray
    Write-Host "  tactical_folder: $($result.tactical_folder) | last_audit: $($result.last_audit_present) | timber: $($result.timber_tags_kt)" -ForegroundColor DarkGray
    if ($result.depends_on.Count -gt 0) {
        $depStr = ($result.depends_on | ForEach-Object { "$($_.id)($($_.status))" }) -join ', '
        Write-Host "  depends_on: $depStr" -ForegroundColor DarkGray
    }
    Write-Host ("  sections: $($result.sections.Count) (research_open=$($result.research_open_count)" +
        ", uncarried=$($result.research_uncarried_count), owner_gate=$($result.owner_gate))") -ForegroundColor DarkGray
    if ($result.auto_skip) {
        Write-Host "  AUTO-SKIP: $($result.auto_skip) - $($result.auto_skip_reason)" -ForegroundColor Yellow
    }
}

exit 0
