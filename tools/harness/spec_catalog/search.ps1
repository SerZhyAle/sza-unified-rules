<#
.SYNOPSIS
  Search the spec catalog by free text, status, tag, or type.
.NOTES
  -Query is the canonical free-text parameter shared by the catalog and registry
  query CLIs; -Text / -Search / -Name are accepted as aliases so older callers work.
  -Query matches `name` and `title` only. Dedup by symptom needs the ticket text as well: pass
  -Body to match the spec file too (it reads every candidate file, so it is opt-in), and
  -IncludeArchived to search closed tickets - the archive is skipped by default, so an empty
  default search does not mean "no such ticket". Table output names both limits on a trailing
  line; JSON output keeps its plain array shape for the callers that parse it.
  Exit codes: 0 ok (including zero matches - an empty result is a normal answer).
#>
[CmdletBinding()]
param(
    [Alias('Text','Search','Name')]
    [string] $Query,
    [string] $Status,
    [string] $Tag,
    [string] $Type,
    [switch] $IncludeArchived,
    [switch] $Body,
    [ValidateSet('table','json')]
    [string] $Format = 'table',
    [switch] $Help
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')

if ($Help) {
    Show-SzaHelp $PSCommandPath
    exit $LASTEXITCODE
}

. (Join-Path $PSScriptRoot '_lib.ps1')

$records = Read-Catalog -IncludeArchived:$IncludeArchived

if ($Query) {
    $records = $records | Where-Object {
        if ($_.name -ilike "*$Query*" -or
            ($_.PSObject.Properties.Name -contains 'title' -and $_.title -ilike "*$Query*")) { return $true }
        if (-not $Body -or -not ($_.PSObject.Properties.Name -contains 'file') -or -not $_.file) { return $false }
        $specFile = Resolve-SpecPath -PathRef ([string]$_.file)
        if (-not (Test-Path -LiteralPath $specFile -PathType Leaf)) { return $false }
        return ([IO.File]::ReadAllText($specFile)).IndexOf($Query, [StringComparison]::OrdinalIgnoreCase) -ge 0
    }
}
if ($Status) {
    $records = $records | Where-Object { $_.status -eq $Status }
}
if ($Tag) {
    $records = $records | Where-Object {
        $_.PSObject.Properties.Name -contains 'tags' -and $_.tags -contains $Tag
    }
}
if ($Type) {
    $records = $records | Where-Object {
        $_.PSObject.Properties.Name -contains 'type' -and $_.type -eq $Type
    }
}

switch ($Format) {
    'json' {
        if (-not $records) { Write-Output '[]'; return }
        $records | ConvertTo-Json -Depth 5 -Compress
    }
    default {
        if (-not $records) { Write-Output '(no records)' }
        else {
            $records | Select-Object id, name, status, priority,
                @{ Name = 'title'; Expression = {
                    if ($_.PSObject.Properties.Name -contains 'title') { $_.title } else { '' }
                }} | Format-Table -AutoSize
        }
        # Say what was NOT searched, so an empty answer is not read as "no such ticket".
        $limits = @()
        if ($Query -and -not $Body) { $limits += 'ticket text not searched (pass -Body)' }
        if (-not $IncludeArchived) { $limits += 'archive not searched (pass -IncludeArchived)' }
        if ($limits.Count -gt 0) { Write-Output ('note: ' + ($limits -join '; ')) }
    }
}
