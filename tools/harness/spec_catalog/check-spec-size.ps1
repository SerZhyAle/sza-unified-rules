<#
.SYNOPSIS
    Gate: a spec file above 40 KB is handed on only with a link to its evidence log (TASK-FLOW 0.53).

.PARAMETER Id
    Ticket id.

.NOTES
    Assert-ClosingGates runs it on a transition from another status into Implemented, Verified or BlockNeedUserTest. A
    write that keeps the status does not reach it, and Archived is not gated. What counts as an evidence link:
    Find-SpecEvidenceLink in _spec-size.ps1.

    Exit codes:
      0 - the spec file is 40960 bytes or smaller, or it holds an evidence link.
      1 - it is larger and holds none.
      2 - bad invocation (malformed id, or an id no record carries), or catalog / spec unreadable.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Id
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')
. (Join-Path $PSScriptRoot '_lib.ps1')
. (Join-Path $PSScriptRoot '_spec-size.ps1')

if (-not (Test-SzaTicketId $Id)) {
    # -ErrorAction Continue: _lib.ps1 sets 'Stop', under which a bare Write-Error throws and `exit 2` is never reached.
    Write-Error "Invalid -Id '$Id' (must match $(Get-SzaTicketIdDisplay))." -ErrorAction Continue
    exit 2
}

$record = Find-Record -Id $Id
if (-not $record) {
    Write-Error "No record with id '$Id' in the spec catalog." -ErrorAction Continue
    exit 2
}

$specPath = Resolve-SpecPath -PathRef $record.file
if (-not (Test-Path -LiteralPath $specPath -PathType Leaf)) {
    Write-Error "Spec file not found on disk: $specPath" -ErrorAction Continue
    exit 2
}

$bytes = (Get-Item -LiteralPath $specPath).Length
if ($bytes -le $script:SpecSizeLimit) {
    Write-Output "PASS $Id"
    Write-Output "Spec file: $bytes bytes, limit $($script:SpecSizeLimit)."
    exit 0
}

$link = Find-SpecEvidenceLink -Path $specPath
if ($link) {
    Write-Output "PASS $Id"
    Write-Output "Spec file: $bytes bytes, evidence link: $link"
    exit 0
}

$name = [IO.Path]::GetFileNameWithoutExtension($specPath)
Write-Output "FAIL $Id"
Write-Output ("- {0}: {1} bytes, above the limit of {2}, and no evidence link." -f $record.file, $bytes, $script:SpecSizeLimit)
Write-Output ""
Write-Output "A spec stays a short working document (TASK-FLOW 0.53). To pass:"
Write-Output ("  1. move logs, per-pass records and earlier audit blocks into {0}/evidence/log.md, beside the spec;" -f $name)
Write-Output "  2. add this line to the spec:"
Write-Output ("     Evidence: [evidence log]({0}/evidence/log.md)" -f $name)
Write-Output "The link is relative, names an existing file, and holds no '..'. Keep what the next pass needs in the spec."
exit 1
