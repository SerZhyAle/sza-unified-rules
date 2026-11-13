# Shared auto-skip verdict: may the picker hand this spec out automatically, and if not, why not.
#
# Dot-sourced, never invoked: this file sets no preferences and holds no mutable state of its own, so a consumer
# inherits only these functions. Same shape and same reason as `_blocker-links.ps1` and `_status-sets.ps1` (S1621):
# `preview.ps1` cannot afford `_lib.ps1`'s `Set-StrictMode -Version Latest`, while `spec-next-preflight.ps1` runs
# under it - so every read below is written to give one answer under both, and a record field is read through
# Get-AutoSkipField, never as `$rec.statusNote`, which throws under strict mode on every record without a note.
#
# Consumers: `preview.ps1` (prints the verdict as auto_skip / auto_skip_reason) and `spec-next-preflight.ps1` (walks
# its ranked candidates on it). One function, one answer - the S1621 / S2581 rule: two copies of this verdict are the
# divergence those tickets ended. Until 2026-11-13 the preflight learned the verdict by spawning preview.ps1 once per
# candidate, and preview.ps1 spawned select.ps1 per blocker; one rank of the portfolio queue cost 167-190 picker runs
# and 100-170 s, nearly all of it process start-up around a few regular expressions. Now the verdict is computed
# in-process from the spec text and one in-memory read of the catalog (ledger first, archive only on a miss).
#
# Compatible with PowerShell 5.1 and 7+, and safe to load under Set-StrictMode Latest.

. (Join-Path $PSScriptRoot '_status-sets.ps1')
. (Join-Path $PSScriptRoot '_blocker-links.ps1')
. (Join-Path $PSScriptRoot '_owner-gate.ps1')

function Get-AutoSkipField {
    # One field of a catalog record, $null when the record does not carry it.
    param($Record, [Parameter(Mandatory)][string] $Name)
    if ($null -eq $Record) { return $null }
    if ($Record -is [System.Collections.IDictionary]) {
        if ($Record.Contains($Name)) { return $Record[$Name] }
        return $null
    }
    $p = $Record.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function New-AutoSkipCatalog {
    # The catalog as the blocker lookups read it: an id index over the active journal, and the archive journal
    # added on the first miss. That is the order select.ps1 -Id resolves in (Find-Record: the active journal, then
    # the archive), so a blocker present in both resolves to its active record here too. Ids compare
    # case-insensitively, as Find-Record's -eq does; the first record of an id wins, as Find-Record's loop does.
    #
    # -ArchiveLoader is a scriptblock returning the archive records. It runs at most once, and only when an id is
    # not in the active journal: the largest archive in the portfolio is a megabyte of JSON, and most rankings
    # never name an archived blocker.
    param(
        [AllowNull()][AllowEmptyCollection()][object[]] $Active,
        [AllowNull()][AllowEmptyCollection()][object[]] $Archived,
        [scriptblock] $ArchiveLoader
    )
    $catalog = [PSCustomObject]@{
        Index         = @{}
        ArchiveLoaded = $false
        ArchiveLoader = $ArchiveLoader
    }
    Add-AutoSkipCatalogRecords -Catalog $catalog -Records $Active
    if ($null -ne $Archived) {
        Add-AutoSkipCatalogRecords -Catalog $catalog -Records $Archived
        $catalog.ArchiveLoaded = $true
    }
    elseif ($null -eq $ArchiveLoader) {
        $catalog.ArchiveLoaded = $true
    }
    return $catalog
}

function Add-AutoSkipCatalogRecords {
    param([Parameter(Mandatory)] $Catalog, [AllowNull()][AllowEmptyCollection()][object[]] $Records)
    foreach ($r in @($Records)) {
        if ($null -eq $r) { continue }
        $id = [string](Get-AutoSkipField $r 'id')
        if (-not $id -or $Catalog.Index.ContainsKey($id)) { continue }
        $Catalog.Index[$id] = $r
    }
}

function Find-AutoSkipRecord {
    # The catalog record of one id, or $null when neither journal holds it.
    param($Catalog, [Parameter(Mandatory)][string] $Id)
    if ($null -eq $Catalog) { return $null }
    if ($Catalog.Index.ContainsKey($Id)) { return $Catalog.Index[$Id] }
    if (-not $Catalog.ArchiveLoaded) {
        $Catalog.ArchiveLoaded = $true
        # Assigned before use, never wrapped in @(): a loader built on `_lib.ps1`'s Read-JsonlFile returns through
        # `return ,$array`, and the assignment is what takes that wrapper off (S2420).
        $archived = & $Catalog.ArchiveLoader
        Add-AutoSkipCatalogRecords -Catalog $Catalog -Records $archived
        if ($Catalog.Index.ContainsKey($Id)) { return $Catalog.Index[$Id] }
    }
    return $null
}

function Read-AutoSkipSpecText {
    # The spec body. $null for an empty file: the caller treats that as a spec it cannot preview, as preview.ps1
    # always did by failing on it.
    param([Parameter(Mandatory)][string] $Path)
    return (Get-Content -LiteralPath $Path -Raw)
}

function Get-SpecFrontmatter {
    # Key fields from the head of a spec, both forms: a YAML block, and `**Status:** X` header lines (the latter for
    # Status, Priority, Tier and Date, never overriding the YAML). An ordered dictionary.
    param([AllowNull()][AllowEmptyString()][string] $SpecText)
    $frontmatter = [ordered]@{}
    $yamlMatch = [regex]::Match($SpecText, '(?s)^---\s*\n(.*?)\n---\s*\n')
    if ($yamlMatch.Success) {
        foreach ($line in ($yamlMatch.Groups[1].Value -split "`n")) {
            if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*(.+?)\s*$') {
                $frontmatter[$matches[1]] = $matches[2].Trim()
            }
        }
    }
    foreach ($key in 'Status', 'Priority', 'Tier', 'Date') {
        $pattern = "^\*\*$key`:\*\*\s*([^\r\n]+?)\s*$"
        $m = [regex]::Match($SpecText, $pattern, 'Multiline')
        if ($m.Success -and -not $frontmatter.Contains($key)) {
            $frontmatter[$key] = $m.Groups[1].Value.Trim()
        }
    }
    return $frontmatter
}

function Resolve-SpecBlockers {
    # The blockers this spec names in a directional channel, each resolved against the catalog. Only sources whose
    # FORM states the direction, because "related to" is not "blocked by" (S1482); the rules and the two accepted
    # channels live in `_blocker-links.ps1`.
    #
    # One catalog read for every blocker instead of one child process each: a campaign parent listing 137 slices
    # cost 70 s per ranking that way (measured 2026-09-26, 0.5 s per spawn).
    #
    # Returns @{ DependsOn; Qualified }. DependsOn carries `file` because the release test reads the blocker's own
    # tactical plan, not only its status (S2834); a record without the field leaves it $null, which the test reads
    # as "nothing to contradict the status" - the same fail-open as an absent folder. A blocker in neither journal
    # is listed with status '?'.
    param(
        [AllowNull()][AllowEmptyString()][string] $SpecText,
        [AllowNull()][AllowEmptyString()][string] $StatusNote,
        [string] $SelfId,
        $Catalog
    )
    $dependsOn = @()
    foreach ($dep in @(Get-BlockerLinks -SpecText $SpecText -StatusNote $StatusNote -SelfId $SelfId)) {
        $depRec = Find-AutoSkipRecord -Catalog $Catalog -Id $dep
        if ($depRec) {
            $dependsOn += [PSCustomObject]@{
                id     = $dep
                status = (Get-AutoSkipField $depRec 'status')
                file   = (Get-AutoSkipField $depRec 'file')
            }
        }
        else {
            $dependsOn += [PSCustomObject]@{ id = $dep; status = '?'; file = $null }
        }
    }
    return [PSCustomObject]@{
        DependsOn = $dependsOn
        Qualified = @(Get-QualifiedBlockerLinks -SpecText $SpecText -StatusNote $StatusNote)
    }
}

function Get-SpecAutoSkip {
    # The verdict. AutoSkip is $null (offer it) or one of: tier-5-epic, owner-gate, blocker-not-verified,
    # blocker-unresolvable, blocker-cross-repo - never research-heavy (see the note at the end). AutoSkipReason is the
    # human-readable detail. The other fields are the inputs the verdict was reached from, returned so preview.ps1
    # prints exactly what was judged: Frontmatter, Tier, DependsOn, QualifiedBlockers, OwnerGate.
    #
    # -Record is the spec's catalog record (status and statusNote are read from it), -SpecText its body, -SelfId the
    # id as asked (a spec naming itself is not its own blocker), -Catalog what New-AutoSkipCatalog returned.
    # -Frontmatter skips a second parse when the caller already holds Get-SpecFrontmatter's result.
    #
    # Reads $env:SZA_PQ_PICKER: a cross-repository blocker is the portfolio dispatcher's to judge (TASK-FLOW rule 52).
    param(
        [Parameter(Mandatory)] $Record,
        [Parameter(Mandatory)][AllowEmptyString()][string] $SpecText,
        [string] $SelfId,
        $Catalog,
        $Frontmatter
    )
    if ($null -eq $Frontmatter) { $Frontmatter = Get-SpecFrontmatter -SpecText $SpecText }
    if (-not $SelfId) { $SelfId = [string](Get-AutoSkipField $Record 'id') }
    $statusNote = [string](Get-AutoSkipField $Record 'statusNote')
    $links = Resolve-SpecBlockers -SpecText $SpecText -StatusNote $statusNote -SelfId $SelfId -Catalog $Catalog
    $dependsOn = @($links.DependsOn)
    $qualifiedBlockers = @($links.Qualified)

    # S2921: the owner-gate pattern set lives in `_owner-gate.ps1`, read here and by the release-queue writer, so one
    # spec cannot be owner-gated for the picker and ordinary for the plan.
    $ownerGate = Test-OwnerGateText -Text $SpecText

    $autoSkip = $null
    $autoSkipReason = $null
    $tierVal = if ($Frontmatter['Tier']) { $Frontmatter['Tier'] } else { '' }
    $unverifiedBlockers = @($dependsOn | Where-Object {
            -not (Test-BlockerReleased -Status ([string]$_.status) -Id ([string]$_.id) -File ([string]$_.file))
        })
    if ($tierVal -match '^\s*5') {
        $autoSkip = 'tier-5-epic'
        $autoSkipReason = 'Tier 5 epic-container, no code under its id'
    }
    elseif ($ownerGate) {
        $autoSkip = 'owner-gate'
        $autoSkipReason = 'Spec explicitly forbids automatic handoff (§12 owner directive)'
    }
    elseif ($unverifiedBlockers.Count -gt 0) {
        # S1775: directed spec link is truth. A blocker that has not been released excludes the ticket from
        # automatic selection regardless of the DEPENDENT's lifecycle status; that status remains descriptive.
        # S1864 refines only which blocker statuses release: Implemented, Verified, BlockNeedUserTest, Archived - the
        # release-ready set plus the archive, shared through _status-sets.ps1. The reason string keeps its name so
        # operators and the skip cache read the same token.
        #
        # S2834 widened what this ONE code covers rather than adding a second: a release-ready blocker parked in the
        # middle of its own tactical plan is also unreleased, and the phase counter goes into the detail string. A
        # new code would have had to be added to this enumeration, to its consumers, and to /spec-next step 2's list
        # of skips that must NOT be persisted - the exception that exists because `blocker-not-verified` depends on
        # another ticket's state and has to be re-derived every run. The plan test depends on exactly the same thing.
        $autoSkip = 'blocker-not-verified'
        $autoSkipReason = 'Depends on ' + (($unverifiedBlockers | ForEach-Object {
                    $detail = "$($_.id)($($_.status)"
                    if ((Test-ReleaseReadyStatus -Status ([string]$_.status)) -and
                        -not (Test-BlockerPlanComplete -Id ([string]$_.id) -File ([string]$_.file))) {
                        $phases = Get-TacticalPhaseCounter -File ([string]$_.file)
                        $detail += if ($phases) { ", phases $phases" } else { ', mid-plan' }
                    }
                    $detail + ')'
                }) -join ', ')
    }
    elseif ([string](Get-AutoSkipField $Record 'status') -eq 'BlockByOtherTask') {
        # S1073 / S0042: fail-closed when no directional blocker was parsed; hold locally when the only unverified
        # blocker is a cross-repository Blocker: <repoKey>:<id> token so a repository-local picker never releases it
        # early, while delegating to the portfolio dispatcher when SZA_PQ_PICKER=1 (TASK-FLOW rule 52).
        if ($dependsOn.Count -eq 0 -and $qualifiedBlockers.Count -eq 0) {
            $autoSkip = 'blocker-unresolvable'
            $autoSkipReason = 'Status is BlockByOtherTask but no blocker is recorded in a directional ' +
            'channel: a `**Depends on:**` line, or a `Blocker: Sxxxx` / `Blocker: <repoKey>:<id>` token in section 10 or in the ' +
            'statusNote. Naming the ticket in section 10 prose is not enough - that section records ' +
            'neighbours and consumers too, so it cannot state which way the dependency points'
        }
        elseif ($qualifiedBlockers.Count -gt 0 -and $env:SZA_PQ_PICKER -cne '1') {
            $autoSkip = 'blocker-cross-repo'
            $autoSkipReason = 'Depends on cross-repo ' + ($qualifiedBlockers -join ', ')
        }
    }
    # NB: no 'research-heavy' auto-skip. /spec-next drives every Draft/Approved forward until it reaches readiness or
    # hits a REAL human blocker (BlockQuestions/BlockExternal set by /spec-all). The research counts preview.ps1
    # prints stay informational for auto-skip - a heavy research section is not a reason to pre-emptively skip.

    return [PSCustomObject]@{
        AutoSkip          = $autoSkip
        AutoSkipReason    = $autoSkipReason
        Frontmatter       = $Frontmatter
        Tier              = $tierVal
        DependsOn         = $dependsOn
        QualifiedBlockers = $qualifiedBlockers
        OwnerGate         = $ownerGate
    }
}
