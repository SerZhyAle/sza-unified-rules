#requires -Version 7.0
<#
.SYNOPSIS
    Install the single master "PQ Control Panel" desktop shortcut, and optionally clean up legacy shortcuts.

.DESCRIPTION
    Creates "PQ Control Panel.lnk" on the Desktop pointing to PQShell.exe in C:\GD\tc\SZA\_APP
    (or the local publish build if the deploy folder does not exist).
    With -CleanLegacy, removes the 13+ individual "PQ *.lnk" shortcuts that cluttered the desktop.

.PARAMETER CleanLegacy
    Also remove the old individual "PQ *.lnk" shortcuts from the Desktop.

.PARAMETER Remove
    Remove the "PQ Control Panel.lnk" shortcut.

.PARAMETER DryRun
    Print what would happen and write nothing.

.EXAMPLE
    pwsh -NoProfile -File tools/harness/portfolio/gui/install-gui-shortcut.ps1 -CleanLegacy
#>
[CmdletBinding()]
param(
    [switch]$CleanLegacy,
    [switch]$Remove,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$desktop = [Environment]::GetFolderPath('Desktop')
if (-not $desktop -or -not [IO.Directory]::Exists($desktop)) {
    Write-Error "No desktop directory found."
    exit 2
}

$deployExe = 'C:\GD\tc\SZA\_APP\PQShell.exe'
$localExe = Join-Path $PSScriptRoot 'tmp\publish\PQShell.exe'

$targetExe = if ([IO.File]::Exists($deployExe)) { $deployExe } else { $localExe }

$shortcutPath = Join-Path $desktop 'PQ Control Panel.lnk'

if ($Remove) {
    if ([IO.File]::Exists($shortcutPath)) {
        if ($DryRun) {
            Write-Host "[dry-run] Would remove: $shortcutPath" -ForegroundColor Yellow
        }
        else {
            Remove-Item $shortcutPath -Force
            Write-Host "Removed: $shortcutPath" -ForegroundColor Green
        }
    }
}
else {
    if (-not [IO.File]::Exists($targetExe)) {
        Write-Error "Target executable not found at $targetExe. Please run build.ps1 publish first."
        exit 2
    }

    if ($DryRun) {
        Write-Host "[dry-run] Would create: $shortcutPath -> $targetExe" -ForegroundColor Yellow
    }
    else {
        $ws = New-Object -ComObject WScript.Shell
        $sc = $ws.CreateShortcut($shortcutPath)
        $sc.TargetPath = $targetExe
        $sc.WorkingDirectory = [IO.Path]::GetDirectoryName($targetExe)
        $sc.Description = "PQ Control Panel - Portfolio Queue Shell (VB.NET WinForms)"
        $sc.Save()
        Write-Host "Created shortcut: $shortcutPath -> $targetExe" -ForegroundColor Green
    }
}

if ($CleanLegacy) {
    Write-Host "Scanning for legacy PQ shortcuts on Desktop..." -ForegroundColor Cyan
    $legacyFiles = Get-ChildItem -Path $desktop -Filter "PQ *.lnk" -File | Where-Object { $_.Name -ne 'PQ Control Panel.lnk' }
    foreach ($f in $legacyFiles) {
        if ($DryRun) {
            Write-Host "[dry-run] Would delete legacy shortcut: $($f.Name)" -ForegroundColor Yellow
        }
        else {
            Remove-Item $f.FullName -Force
            Write-Host "Removed legacy shortcut: $($f.Name)" -ForegroundColor Gray
        }
    }
}
