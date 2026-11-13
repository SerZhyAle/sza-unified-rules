# The preview payload of one spec - what `preview.ps1 -Format json` prints - built in-process.
#
# Dot-sourced, never invoked: this file sets no preferences and holds no mutable state, so a consumer inherits only
# these functions. Safe to load and run under Set-StrictMode Latest, for the reason `_auto-skip.ps1` gives.
#
# Consumers: `preview.ps1` (prints it) and `spec-next-preflight.ps1` (attaches it as `selected`). Before 2026-11-13 the
# preflight obtained the selected ticket's payload from a preview.ps1 child process - one more process start per
# repository per rank. Building it from this one function keeps the payload the same by construction; the preflight
# still passes it through a JSON round trip, so its shape (frontmatter as an object, not a dictionary) is exactly the
# shape it always parsed out of the child's output.

. (Join-Path $PSScriptRoot '_auto-skip.ps1')
. (Join-Path $PSScriptRoot '_research-items.ps1')

function Get-SpecProbeTagCount {
    # Probe tags carrying this id across the project's sources (preview.ps1's `timber_tags_kt`). S2402: roots, file
    # types and the probe shape come from the profile (probes.*). ripgrep when present, `git grep` otherwise.
    param([Parameter(Mandatory)][string] $Id, [Parameter(Mandatory)][string] $Root)
    $timberCount = 0
    Push-Location -LiteralPath $Root
    try {
        $probeRx = (Get-SzaProbeFormRegexForId -Id $Id).ToString() -replace '^\^', ''
        $probeRoots = @((Get-SzaProfileValue 'probes.sourceRoots') | ForEach-Object { [string]$_ } | Where-Object { Test-Path -LiteralPath (Join-Path $Root $_) })
        $probeExts = @((Get-SzaProfileValue 'probes.sourceExtensions') | ForEach-Object { [string]$_ })
        $rgExe = Get-Command rg -ErrorAction SilentlyContinue
        if ($rgExe -and $probeRoots.Count -gt 0) {
            $rgGlobs = @($probeExts | ForEach-Object { @('-g', "*$_") })
            $tags = & rg --no-heading --count-matches @rgGlobs $probeRx @probeRoots 2>$null
            if ($tags) {
                $timberCount = (($tags | ForEach-Object { ($_ -split ':')[-1] }) | Measure-Object -Sum).Sum
            }
        }
        elseif ($probeRoots.Count -gt 0) {
            $pathspecs = @(foreach ($r in $probeRoots) { foreach ($e in $probeExts) { "$r/**/*$e" } })
            $tagFiles = git grep -l -E $probeRx -- @pathspecs 2>$null
            if ($tagFiles) {
                foreach ($f in $tagFiles) {
                    $hits = git grep -c -E $probeRx -- $f 2>$null
                    if ($hits -match ':(\d+)$') {
                        $timberCount += [int]$matches[1]
                    }
                }
            }
        }
    }
    finally {
        Pop-Location
    }
    return $timberCount
}

function Get-SpecPreview {
    # The payload, in preview.ps1's field order. -Record is the spec's catalog record, -Id the id as asked, -Root the
    # project root, -SpecPath the spec file's absolute path, -Catalog what New-AutoSkipCatalog returned (the blocker
    # lookups). Throws on a spec it cannot read; an empty spec file is one.
    param(
        [Parameter(Mandatory)] $Record,
        [Parameter(Mandatory)][string] $Id,
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][string] $SpecPath,
        $Catalog
    )

    # 2. Spec body.
    $specText = Read-AutoSkipSpecText -Path $SpecPath
    if ($null -eq $specText) { throw "Spec file is empty: $(Get-AutoSkipField $Record 'file')" }

    # 3. Frontmatter and key fields (both YAML-block and "**Status:** X" forms).
    $frontmatter = Get-SpecFrontmatter -SpecText $specText

    # 4. Section list.
    $sections = @()
    foreach ($line in ($specText -split "`n")) {
        if ($line -match '^##\s+(.+?)\s*$') {
            $sections += $line.Trim()
        }
    }

    # 5. Tactical folder.
    $tacticalFolder = Test-Path -LiteralPath ($SpecPath -replace '\.md$', '') -PathType Container

    # 6. Last Audit block present? Read through the pattern the closing gate uses (S2298), not a literal
    # '## Last Audit': live specs number their headings, and `## 6. Last Audit` is a real spelling on disk. The flag
    # travels through spec-next-preflight.ps1 into /spec-all step 0a-drift, where "block absent" switches an
    # already-closed ticket into review mode - so a false negative here costs a re-audit of finished work.
    $lastAuditPresent = @(Get-SpecSectionLines -Path $SpecPath -HeadingPattern (Get-AuditSectionHeadingPattern)).Count -gt 0

    # 7. Probe tag count.
    $timberCount = Get-SpecProbeTagCount -Id $Id -Root $Root

    # 8, 10, 11. Blockers, owner gate and the auto-skip verdict - `_auto-skip.ps1`, the one copy of it.
    $verdict = Get-SpecAutoSkip -Record $Record -SpecText $specText -SelfId $Id -Catalog $Catalog -Frontmatter $frontmatter

    # 9. Research item counts, by the closing gate's definition (S1621). An item counts as open iff its status line
    # says so - heading found by text, never by the number 6. The subset naming no carrier ticket is exactly what
    # check-open-items-carried.ps1 refuses (S1607), so research_uncarried_count > 0 predicts a refused close.
    $researchItems = @(Get-ResearchItems -Path $SpecPath)
    $openItems = @($researchItems | Where-Object { $_.IsOpen })
    $researchUncarriedCount = @($openItems | Where-Object { -not $_.Carrier }).Count

    # 12. Compose.
    return [PSCustomObject]@{
        id                       = (Get-AutoSkipField $Record 'id')
        name                     = (Get-AutoSkipField $Record 'name')
        status                   = (Get-AutoSkipField $Record 'status')
        priority                 = (Get-AutoSkipField $Record 'priority')
        tier                     = $verdict.Tier
        file                     = (Get-AutoSkipField $Record 'file')
        created                  = (Get-AutoSkipField $Record 'created')
        updated                  = (Get-AutoSkipField $Record 'updated')
        frontmatter              = $frontmatter
        sections                 = $sections
        tactical_folder          = $tacticalFolder
        last_audit_present       = [bool]$lastAuditPresent
        timber_tags_kt           = $timberCount
        depends_on               = $verdict.DependsOn
        research_open_count      = $openItems.Count
        research_uncarried_count = $researchUncarriedCount
        owner_gate               = $verdict.OwnerGate
        auto_skip                = $verdict.AutoSkip
        auto_skip_reason         = $verdict.AutoSkipReason
    }
}
