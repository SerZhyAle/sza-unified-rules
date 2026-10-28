#requires -Version 7.0
# Refresh one registered project's projection after its local queue has been reconciled.
param([Parameter(Mandatory)][string]$ProjectRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/registry.ps1')
try {
    $registryPath = Get-PqPath -Kind registry
    if (-not [IO.File]::Exists($registryPath)) { exit 0 }
    $read = Read-PqRegistry -Path $registryPath
    if (-not $read.ok) { throw "portfolio registry is unreadable: $registryPath" }
    $key = ConvertTo-PqPathKey ([IO.Path]::GetFullPath($ProjectRoot))
    $repo = @($read.registry.repos | Where-Object { (ConvertTo-PqPathKey ([IO.Path]::GetFullPath([string]$_.path))) -ceq $key }) | Select-Object -First 1
    if ($null -eq $repo) { exit 0 }
    & (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $PSScriptRoot 'pq.ps1') sync -Path $ProjectRoot
    exit $LASTEXITCODE
} catch {
    [Console]::Error.WriteLine("portfolio sync: $($_.Exception.Message)")
    exit 2
}
