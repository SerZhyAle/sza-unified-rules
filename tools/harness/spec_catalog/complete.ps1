[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Id,
    [ValidateSet('Verified','Archived')]
    [string] $Status = 'Verified',
    [switch] $SkipValidate,
    # TASK-FLOW 0.52: the one-line archive reason, handed to close.ps1; required with -Status Archived.
    [Alias('StatusNote')]
    [string] $Reason
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')

# Convert terminating errors (Write-Error, throw, provider errors) into
# the documented `exit 1` so callers can rely on $LASTEXITCODE.
trap {
    Write-Host $_ -ForegroundColor Red
    exit 1
}

. (Join-Path $PSScriptRoot '_lib.ps1')

if (-not (Test-SzaTicketId $Id)) { throw "Invalid -Id '$Id' (must match $(Get-SzaTicketIdDisplay))." }
$Id = Resolve-CatalogId -Id $Id   # TASK-FLOW 0.37: a former id names the renamed ticket

$record = Find-Record -Id $Id
if (-not $record) {
    Write-Error "Record '$Id' not found."
    exit 1
}
if ($record.status -match '^Block') {
    Write-Error "Unblock first: update.ps1 -Id $Id -Status <previous>"
    exit 1
}
if ($record.status -in @('Verified','Archived')) {
    Write-Error "$Id is already $($record.status)."
    exit 1
}

Write-Host "=== complete.ps1 $Id ===" -ForegroundColor Cyan

# 1. Catalog validation
if (-not $SkipValidate) {
    Write-Host "[1/3] catalog validate..." -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'validate.ps1')
    $validateExit = $LASTEXITCODE
    if ($validateExit -ne 0) {
        Write-Warning "validate.ps1 exited $validateExit - check output above. Continue anyway (pre-existing failures are common). Use -SkipValidate to suppress this step."
    } else {
        Write-Host "      OK" -ForegroundColor Green
    }
} else {
    Write-Host "[1/3] catalog validate... SKIPPED" -ForegroundColor DarkGray
}

# 2. Dev-log check
Write-Host "[2/3] dev log check..." -ForegroundColor Cyan
$changelog = [string](Get-SzaProfileValue 'paths.changelog')
if ([string]::IsNullOrWhiteSpace($changelog)) {
    Write-Host 'dev-log: NOT APPLICABLE (paths.changelog is empty; no dev-log is configured)'
} elseif (Test-Path ($changelogPath = Get-SzaPath 'changelog')) {
    $hits = (Select-String -LiteralPath $changelogPath -Pattern ([regex]::Escape($Id)) -SimpleMatch).Count
    if ($hits -eq 0) {
        Write-Warning "No $(Get-SzaPath 'changelog' -Relative) entry found for $Id. Run add_to_dev_log.ps1 before closing."
    } else {
        Write-Host ("      {0} entr{1} found" -f $hits, $(if ($hits -eq 1) {'y'} else {'ies'})) -ForegroundColor Green
    }
} else {
    Write-Warning "$(Get-SzaPath 'changelog' -Relative) not found - skipping dev-log check."
}

# 3. Close
Write-Host "[3/3] closing $Id -> $Status..." -ForegroundColor Cyan
$closeArgs = @{ Id = $Id; Status = $Status }   # splatted by name: an omitted reason stays omitted
if ($PSBoundParameters.ContainsKey('Reason')) { $closeArgs['Reason'] = $Reason }
& (Join-Path $PSScriptRoot 'close.ps1') @closeArgs
exit $LASTEXITCODE
