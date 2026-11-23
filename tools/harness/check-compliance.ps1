#requires -Version 7.0
# The gate locates the Git root from the working directory when -RepoRoot is omitted.
$projectRoot = if ($env:SZA_PROJECT_ROOT) { $env:SZA_PROJECT_ROOT } else { (Get-Location).Path }
Push-Location -LiteralPath $projectRoot -ErrorAction Stop
try {
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot '../check-compliance.ps1') @args
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
