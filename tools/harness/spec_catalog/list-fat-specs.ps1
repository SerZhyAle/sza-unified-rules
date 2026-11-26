#requires -Version 7.0
<#
.SYNOPSIS
    Report: the spec files of one repository that are larger than a size limit, with their biggest sections.

.DESCRIPTION
    A dry run: it reads the ledger, the archive and the spec files and writes nothing - no status, no file, no moved
    text. A spec is a short working document; per-pass records, audit history and other logs belong in its companion
    folder (<specs>/<id>_<slug>/evidence/), linked from one `Evidence:` line.

.PARAMETER Root
    The repository to read. Default: the project of the current folder.

.PARAMETER OverKB
    A spec file is listed when it is larger than this many KiB (1 KiB = 1024 bytes). Default 40.

.PARAMETER Json
    One JSON object instead of the lines: root, overKB, specs, missing, fat,
    tickets[{id, status, file, bytes, sections[{heading, bytes}]}].

.NOTES
    Exit codes: 0 = the report was written, whatever it found. 2 = -Root is not a folder, or the ledger is unreadable.
#>
[CmdletBinding()]
param(
    [string] $Root,
    [ValidateRange(1, 100000)]
    [int] $OverKB = 40,
    [switch] $Json
)

if ($Root) {
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        Write-Error "-Root is not a folder: $Root" -ErrorAction Continue
        exit 2
    }
    $savedRoot = $env:SZA_PROJECT_ROOT
    $env:SZA_PROJECT_ROOT = (Resolve-Path -LiteralPath $Root).Path
}

try {
    . (Join-Path $PSScriptRoot '..\_profile.ps1')
    . (Join-Path $PSScriptRoot '_lib.ps1')
    . (Join-Path $PSScriptRoot '_spec-size.ps1')

    # Read-Catalog hands its array over as one object, so it is assigned before it is walked.
    try { $rows = Read-Catalog -IncludeArchived }
    catch {
        Write-Error "The ledger could not be read: $($_.Exception.Message)" -ErrorAction Continue
        exit 2
    }

    $specs = 0
    $missing = 0
    $fat = @(foreach ($row in @($rows)) {
        $path = Resolve-SpecPath -PathRef ([string]$row.file)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $missing++; continue }
        $specs++
        if ((Get-Item -LiteralPath $path).Length -le $OverKB * 1024) { continue }
        $report = Get-SpecSizeReport -Path $path
        [pscustomobject]@{
            id = [string]$row.id; status = [string]$row.status; file = [string]$row.file; bytes = $report.Bytes
            sections = @($report.Sections | Select-Object -First 3 |
                ForEach-Object { [pscustomobject]@{ heading = $_.Heading; bytes = $_.Bytes } })
        }
    })
    $fat = @($fat | Sort-Object -Property bytes -Descending)

    $shownRoot = if ($Root) { $env:SZA_PROJECT_ROOT } else { Get-SzaProjectRoot }
    if ($Json) {
        [pscustomobject]@{
            root = $shownRoot; overKB = $OverKB; specs = $specs; missing = $missing; fat = $fat.Count; tickets = $fat
        } | ConvertTo-Json -Depth 5 -Compress
    } else {
        $culture = [Globalization.CultureInfo]::InvariantCulture
        foreach ($t in $fat) {
            Write-Output ([string]::Format($culture, '{0}  {1}  {2:0.0} KB  {3}', $t.id, $t.status, ($t.bytes / 1024), $t.file))
            foreach ($s in $t.sections) {
                Write-Output ([string]::Format($culture, '    {0,7:0.0} KB  {1}', ($s.bytes / 1024), $s.heading))
            }
        }
        $gone = if ($missing) { ", $missing row(s) without a file" } else { '' }
        Write-Output ('list-fat-specs: {0} of {1} spec file(s) above {2} KB{3} ({4})' -f $fat.Count, $specs, $OverKB, $gone, $shownRoot)
    }
}
finally {
    if ($Root) { $env:SZA_PROJECT_ROOT = $savedRoot }
}
exit 0
