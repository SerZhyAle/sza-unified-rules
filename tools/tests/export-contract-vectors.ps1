#requires -Version 7.0
<# Generate catalog reader artifacts from the owner implementation. Codes: 0 pass, 1 fail, 2 unavailable. #>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$CatalogRoot)
& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'contract-reader.tests.ps1') `
    -ExportDirectory (Join-Path $CatalogRoot 'rule-adoption/vectors')
exit $LASTEXITCODE
