<#
.SYNOPSIS
    Validate the ALL_FEATURES inventory (docs/ALL_FEATURES.jsonl) against the schema rules.

.DESCRIPTION
    Parses each JSONL line, checks required fields, flavor enum membership,
    id pattern + uniqueness, spec pattern, status enum, and EN-only ASCII for
    name/description. Prints a per-error report and exits non-zero on any
    violation; exits 0 when clean. An empty file is valid.

    -NoLegal validates docs/ALL_FEATURES_noLegal.jsonl instead.
    -Gate prints nothing on success (exit-code-only) for post-change wiring.

.EXAMPLE
    .\scripts\all_features\validate.ps1
.EXAMPLE
    .\scripts\all_features\validate.ps1 -Gate

.NOTES
    Exit codes:
      0 inventory valid, and the S1934 ungated-dimension ratchet is at or below its baseline - or
        the profile declares no baseline / no feature matrix, so there is no ratchet to run.
      1 a schema rule was violated, the ratchet grew past its baseline, or the baseline is not an integer.
      2 could not verify: the profile DECLARES a baseline or a feature matrix that cannot be read,
        so the ratchet did not run (S2434). Distinct from 0 on purpose - "did not look" is not "clean".
#>
param(
    [switch]$NoLegal,
    [switch]$Gate,
    [switch]$Quiet
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')

$ErrorActionPreference = "Stop"
trap { Write-Error $_; exit 1 }

# S2090: the wear module's own dimension. Deliberately a separate list from the phone's - the watch
# declares two of those six names and nothing says the two sets must move together.
# S2402: the second dimension is declared by the profile; read after _lib.ps1 loads below.
$validStatus = @("active", "removed")
# The dimension field joins the required list once the profile has named it (below).
$required = @("id", "area", "name", "description")

# S1934: the full flavor set. A capability nothing gates cannot be narrower than the app itself,
# so this set - or the row of some matrix flag - is the only shape an ungated record may claim.
# The full dimension set: every value the build system produces. Filled from the profile below.
$allFlavors = @()

function Test-NonAscii([string]$s) {
    foreach ($ch in $s.ToCharArray()) { if ([int][char]$ch -gt 127) { return $true } }
    return $false
}

function Get-FlavorMatrixFlags {
    <#
    .SYNOPSIS
        flag name -> the flavors it is ON in, read from the generated flavor matrix (S1929).
    .DESCRIPTION
        docs/FLAVOR_MATRIX.md is generated from the productFlavors block and is the only permitted
        source for this grid: CLAUDE.md forbids restating it from memory after S1392, where a
        summary in a prompt claimed `lite` had no audio and four documents followed it.

        The column order is read from the table's own header rather than assumed, so the parser
        does not silently transpose if a flavor is ever added or reordered.

        A cell is ON when it carries `[+]`. The trailing asterisk in `[+]*` / `[-]*` means the
        value was inherited from defaultConfig rather than declared by the flavor (see the file's
        own legend) - that is a fact about where the value came from, not about what it is.

        Returns an empty hashtable when the matrix cannot be read; the caller decides what that
        means rather than having a guess made for it here.
    #>
    param([Parameter(Mandatory)][string]$MatrixPath)

    $flags = @{}
    if (-not (Test-Path -LiteralPath $MatrixPath)) { return $flags }

    $columns = @()
    foreach ($line in (Get-Content -LiteralPath $MatrixPath -Encoding UTF8)) {
        if ($line -notmatch '^\s*\|') { continue }
        $cells = @($line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        if ($cells.Count -lt 2) { continue }

        if ($columns.Count -eq 0) {
            # The header is the first table row whose leading cell is the flag column's title.
            if ($cells[0] -eq 'Flag') { $columns = @($cells[1..($cells.Count - 1)]) }
            continue
        }
        if ($cells[0] -match '^:?-{2,}') { continue }   # the alignment row

        $name = $cells[0].Trim('`')
        if ($name -notmatch '^[A-Z][A-Z0-9_]*$') { continue }

        $on = @()
        for ($i = 0; $i -lt $columns.Count -and ($i + 1) -lt $cells.Count; $i++) {
            if ($cells[$i + 1] -like '*[[]+]*') { $on += $columns[$i] }
        }
        $flags[$name] = $on
    }
    return $flags
}

# S2402: root, ledger paths and the dimension come from the profile through _lib.ps1.
. (Join-Path $PSScriptRoot '_lib.ps1')
$repoRoot = (Get-SzaProjectRoot)
$dataFile = Get-FeatureInventoryPath -RepoRoot $repoRoot -NoLegal:$NoLegal
$fileName = Split-Path $dataFile -Leaf
$dimensionName = Get-FeatureDimensionName
$secondary = Get-FeatureSecondaryDimension

$errors = New-Object System.Collections.Generic.List[string]
$unexplained = New-Object System.Collections.Generic.List[string]
$seenIds = @{}
$count = 0

# Read once for the whole file rather than per record - the matrix does not change mid-run.
$matrixRel = [string](Get-SzaProfileValue 'paths.featureMatrix')
$matrixPath = if ($matrixRel) { Join-Path $repoRoot $matrixRel } else { '' }
$matrixLabel = if ($matrixRel) { $matrixRel } else { 'the feature matrix (paths.featureMatrix is unset)' }
$matrixFlags = if ($matrixPath) { Get-FlavorMatrixFlags -MatrixPath $matrixPath } else { @{} }

# The matrix header is the live list; the profile's inventory.dimensions is the fallback where
# the matrix is missing, and a literal here is what went stale when `foss` was declared (S2093).
$validFlavors = @(Get-FeatureDimensionValues -RepoRoot $repoRoot)
$allFlavors = $validFlavors
$validWearFlavors = if ($secondary) { @($secondary.Values) } else { @() }
$required += $dimensionName

if (Test-Path $dataFile) {
    $lineNo = 0
    foreach ($raw in (Get-Content -LiteralPath $dataFile -Encoding UTF8)) {
        $lineNo++
        if ($raw.Trim().Length -eq 0) { continue }
        $count++
        $obj = $null
        try { $obj = $raw | ConvertFrom-Json } catch {
            $errors.Add("L${lineNo}: not valid JSON"); continue
        }
        # Required fields
        foreach ($k in $required) {
            if (-not ($obj.PSObject.Properties.Name -contains $k)) {
                $errors.Add("L${lineNo}: missing required field '$k'")
            }
        }
        # id pattern + uniqueness
        if ($obj.id) {
            if ($obj.id -notmatch '^[a-z0-9]+(?:[-_][a-z0-9]+)*\.[a-z0-9]+(?:[-_][a-z0-9]+)*$') {
                $errors.Add("L${lineNo}: id '$($obj.id)' not kebab '<area>.<feature>'")
            }
            # S0543: the area-prefix must be an area slug, not a spec id (s####). Active records only;
            # 'removed' tombstones keep their frozen historical id.
            $idStatus = if ($obj.PSObject.Properties.Name -contains 'status' -and $obj.status) { "$($obj.status)" } else { "active" }
            if ($idStatus -ne 'removed' -and ($obj.id.Split('.')[0] -match '^s\d{4}$')) {
                $errors.Add("L${lineNo}: id '$($obj.id)' uses a spec id as area prefix; use the area slug")
            }
            if ($seenIds.ContainsKey($obj.id)) {
                $errors.Add("L${lineNo}: duplicate id '$($obj.id)' (first at L$($seenIds[$obj.id]))")
            } else {
                $seenIds[$obj.id] = $lineNo
            }
        }
        # flavors
        if ($obj.$dimensionName) {
            if ($obj.$dimensionName -isnot [array] -or $obj.$dimensionName.Count -eq 0) {
                $errors.Add("L${lineNo}: $dimensionName must be a non-empty array")
            } else {
                foreach ($f in $obj.$dimensionName) {
                    if ($validFlavors -notcontains $f) {
                        $errors.Add("L${lineNo}: invalid $dimensionName value '$f'")
                    }
                }
            }
        }
        # wearFlavors (S2090) - which WATCH build a capability exists in. A separate axis rather than a
        # reinterpretation of `flavors`: that field means "which phone flavor gates this", and the S1934
        # ratchet below counts a set as explained only when it equals the full six or some flag's row.
        # A capability living only in the watch's noLegal build is gated by no phone flavor at all, so
        # under `flavors` alone it would be forced to declare the full six and assert availability
        # everywhere. Absent means "every watch build", so naming both variants is rejected - it claims
        # exactly what absence already claims, and two spellings of one fact drift apart.
        if ($secondary -and $obj.PSObject.Properties.Name -contains $secondary.Name) {
            $wf = $obj.($secondary.Name)
            if ($wf -isnot [array] -or $wf.Count -eq 0) {
                $errors.Add("L${lineNo}: $($secondary.Name) must be a non-empty array when present - omit the key to mean every such build")
            } else {
                foreach ($f in $wf) {
                    if ($validWearFlavors -notcontains $f) {
                        $errors.Add("L${lineNo}: invalid $($secondary.Name) value '$f' - the profile declares $($validWearFlavors -join ', ')")
                    }
                }
                if (@($wf | Sort-Object -Unique).Count -eq $validWearFlavors.Count) {
                    $errors.Add("L${lineNo}: $($secondary.Name) names every value - omit the key instead, which already means that")
                }
            }
        }
        # gate (S1929, conjunction added by S1982) - NOTE: the record's `gate` field is unrelated to
        # this script's -Gate switch, which only silences success output.
        #
        # A record may name the BuildConfig flag its capability lives behind. When it does, its
        # flavors must equal that flag's row in the generated matrix: the field is what makes the
        # claim checkable at all, because nothing in the code says which capability sits behind
        # which flag. When it does not, nothing is claimed and nothing is checked - that silence is
        # an assertion ("behind no flag"), which is why documentation-only records keep their own
        # sets instead of being swept to a runtime flag's.
        #
        # Flags joined by '+' are a conjunction: the capability needs all of them at once, so the
        # expected set is the intersection of their rows. Live-stream casting is the shape it exists
        # for - SUPPORT_STREAMS holds in vr where SUPPORT_CAST does not, SUPPORT_CAST holds in lite
        # and photos where SUPPORT_STREAMS does not, and only the intersection is true of the record.
        # Naming the conjunction is deliberately stricter than recognising its shape: three inventory
        # records happen to carry a set equal to some intersection while having nothing to do with
        # that pairing, so a set alone never says which flags produced it (S1982).
        if ($obj.PSObject.Properties.Name -contains 'gate' -and
            -not [string]::IsNullOrWhiteSpace("$($obj.gate)")) {
            $gateRaw = "$($obj.gate)".Trim()
            $gateTerms = @($gateRaw -split '\+' | ForEach-Object { $_.Trim() })
            $unknownTerms = @($gateTerms | Where-Object { $_ -and -not $matrixFlags.ContainsKey($_) })
            if ($matrixFlags.Count -eq 0) {
                $errors.Add("L${lineNo}: record names gate '$gateRaw' but the flavor matrix could not be read")
            }
            elseif ($gateRaw -cnotmatch '^[A-Z][A-Z0-9_]*(?:\+[A-Z][A-Z0-9_]*)*$') {
                # Case-sensitively, because the matrix lookup below is a PowerShell hashtable and so
                # is not: 'support_cast' would find SUPPORT_CAST's row and pass a check the schema's
                # own pattern rejects, which is the silent switch-off this field exists to prevent.
                $errors.Add("L${lineNo}: gate '$gateRaw' is not a flag name, or flag names joined by '+' (see $(Get-SzaPath 'allFeaturesSchema' -Relative))")
            }
            elseif (@($gateTerms | Sort-Object -Unique).Count -ne $gateTerms.Count) {
                # A repeated term narrows nothing, so it is never what the author meant - it hides a
                # second flag that was mistyped into a copy of the first.
                $errors.Add("L${lineNo}: gate '$gateRaw' repeats a flag; each term must name a different flag")
            }
            elseif ($unknownTerms.Count -gt 0) {
                # An unknown name is an error rather than a skip: a typo would otherwise turn the
                # check off for that record and look exactly like a record that passed.
                $errors.Add("L${lineNo}: gate '$gateRaw' names [$($unknownTerms -join ', ')], not a flag in $matrixLabel")
            }
            else {
                $expectedSet = @($matrixFlags[$gateTerms[0]])
                foreach ($term in $gateTerms) {
                    $row = $matrixFlags[$term]
                    $expectedSet = @($expectedSet | Where-Object { $row -contains $_ })
                }
                $expected = @($expectedSet | Sort-Object)
                $actual = @($obj.$dimensionName | Sort-Object)
                if (($expected -join ',') -ne ($actual -join ',')) {
                    $shape = if ($gateTerms.Count -gt 1) { " (intersection of the named rows)" } else { "" }
                    $errors.Add("L${lineNo}: $dimensionName disagrees with gate '$gateRaw'$shape - expected [$($expected -join ', ')], recorded [$($actual -join ', ')]")
                }
            }
        }
        elseif ($obj.$dimensionName -is [array] -and $obj.$dimensionName.Count -gt 0 -and $matrixFlags.Count -gt 0) {
            # Unexplained flavor set (S1934) - counted, not refused: 242 records predate the rule.
            # An ungated record may claim the full six (nothing narrows it) or exactly some flag's
            # row (that flag narrows it). Anything else names a reach the build does not produce.
            $actualSet = ($obj.$dimensionName | Sort-Object) -join ','
            $explained = ($actualSet -eq (($allFlavors | Sort-Object) -join ','))
            if (-not $explained) {
                foreach ($row in $matrixFlags.Values) {
                    if ((($row | Sort-Object) -join ',') -eq $actualSet) { $explained = $true; break }
                }
            }
            if (-not $explained) { $unexplained.Add("$($obj.id) [$actualSet]") | Out-Null }
        }
        # spec
        if ($obj.PSObject.Properties.Name -contains 'spec' -and $null -ne $obj.spec) {
            if ("$($obj.spec)" -notmatch '^S\d{4}$') {
                $errors.Add("L${lineNo}: spec '$($obj.spec)' not Sxxxx or null")
            }
        }
        # status
        if ($obj.PSObject.Properties.Name -contains 'status' -and $obj.status) {
            if ($validStatus -notcontains $obj.status) {
                $errors.Add("L${lineNo}: invalid status '$($obj.status)'")
            }
        }
        # EN-only
        if ($obj.name -and (Test-NonAscii "$($obj.name)")) {
            $errors.Add("L${lineNo}: non-ASCII in name (EN-only)")
        }
        if ($obj.description -and (Test-NonAscii "$($obj.description)")) {
            $errors.Add("L${lineNo}: non-ASCII in description (EN-only)")
        }
    }
}

if ($errors.Count -gt 0) {
    if (-not $Gate) {
        Write-Host "ALL_FEATURES validation FAILED ($($errors.Count) error(s)) in docs/$fileName" -ForegroundColor Red
        foreach ($e in $errors) { Write-Host "  $e" -ForegroundColor Red }
    }
    exit 1
}

# S1934 ratchet. The public inventory only: the noLegal file has its own contents and no baseline.
#
# S2434 splits two answers this block used to give as one silent SKIPPED at exit 0. "This repository
# declares no ratchet" and "this repository declares one that cannot be read" are opposite states:
# the first is a configuration choice, the second is the gate not running while its caller is told
# PASS. Both a baseline and a matrix are therefore judged twice - declared at all, then reachable -
# and only the undeclared half stays quiet. The refusal prints even under -Gate, because -Gate
# silences SUCCESS, and a check that could not look is not one.
if (-not $NoLegal) {
    $baselineRel = [string](Get-SzaProfileValue 'paths.allFeaturesFlavorsBaseline')
    $baselineFile = if ($baselineRel) { Get-SzaPath 'allFeaturesFlavorsBaseline' } else { '' }
    if (-not $matrixRel) {
        if (-not $Gate) {
            Write-Host "ALL_FEATURES: ungated-$dimensionName ratchet SKIPPED - paths.featureMatrix is unset" -ForegroundColor Yellow
        }
    }
    elseif ($matrixFlags.Count -eq 0) {
        Write-Host "ALL_FEATURES: ungated-$dimensionName ratchet COULD NOT RUN - $matrixLabel is declared but unreadable ($matrixPath)" -ForegroundColor Red
        Write-Host "  Regenerate the matrix, or clear paths.featureMatrix if this repository has no such grid." -ForegroundColor Red
        exit 2
    }
    elseif (-not $baselineRel) {
        if (-not $Gate) {
            Write-Host "ALL_FEATURES: ungated-$dimensionName ratchet SKIPPED - paths.allFeaturesFlavorsBaseline is unset" -ForegroundColor Yellow
        }
    }
    elseif (-not (Test-Path -LiteralPath $baselineFile)) {
        Write-Host "ALL_FEATURES: ungated-$dimensionName ratchet COULD NOT RUN - the profile declares a baseline that does not exist ($baselineFile)" -ForegroundColor Red
        Write-Host "  Create it with the current count, or clear paths.allFeaturesFlavorsBaseline to declare no ratchet." -ForegroundColor Red
        exit 2
    }
    else {
        $baseline = 0
        $baselineRaw = ((Get-Content -LiteralPath $baselineFile -Raw) -replace '\s', '')
        if (-not [int]::TryParse($baselineRaw, [ref]$baseline)) {
            Write-Host "ALL_FEATURES: ungated-$dimensionName baseline is not an integer ($baselineFile)" -ForegroundColor Red
            exit 1
        }
        if ($unexplained.Count -gt $baseline) {
            Write-Host ("ALL_FEATURES: ungated-$dimensionName ratchet FAILED - {0} record(s) claim a reach the build system does not produce, baseline {1}." -f $unexplained.Count, $baseline) -ForegroundColor Red
            Write-Host "  An ungated record carries every $dimensionName value, or exactly one flag's row in $matrixLabel (S1934)." -ForegroundColor Red
            foreach ($u in $unexplained) { Write-Host "  $u" -ForegroundColor Red }
            exit 1
        }
        if ($unexplained.Count -lt $baseline -and -not $Gate) {
            Write-Host ("ALL_FEATURES: ungated-$dimensionName ratchet improved - {0} record(s) against baseline {1}; lower the baseline in {2}." -f $unexplained.Count, $baseline, $baselineFile) -ForegroundColor Yellow
        }
    }
}

if (-not $Gate -and -not $Quiet) {
    Write-Host "ALL_FEATURES validation PASS: $count record(s) in docs/$fileName" -ForegroundColor Green
}
exit 0
