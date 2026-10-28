<#
.SYNOPSIS
    Build / run / clean / publish helper for PQShell (.NET 8 WinForms, VB.NET).
.DESCRIPTION
    Thin wrapper over the dotnet CLI for building, running, and publishing the PQShell
    portfolio control panel.
.PARAMETER Task
    build (default) | run | clean | rebuild | restore | publish
.PARAMETER Configuration
    Debug (default) | Release
.EXAMPLE
    .\build.ps1
.EXAMPLE
    .\build.ps1 run
.EXAMPLE
    .\build.ps1 publish -Configuration Release
#>
[CmdletBinding()]
param(
    [ValidateSet('build', 'run', 'clean', 'rebuild', 'restore', 'publish')]
    [string]$Task = 'build',

    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = $PSScriptRoot
$Solution   = Join-Path $ScriptRoot 'PQShell.slnx'
$Project    = Join-Path $ScriptRoot 'src\PQShell.vbproj'
$PublishDir = Join-Path $ScriptRoot 'tmp\publish'
$DeployDir  = 'C:\GD\tc\SZA\_APP'

function Invoke-Dotnet {
    param([string[]]$DotnetArgs)
    Write-Host "> dotnet $($DotnetArgs -join ' ')" -ForegroundColor Cyan
    & dotnet @DotnetArgs
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet exited with code $LASTEXITCODE"
    }
}

switch ($Task) {
    'restore' {
        Invoke-Dotnet @('restore', $Solution)
    }
    'build' {
        Invoke-Dotnet @('build', $Solution, '-c', $Configuration)
    }
    'rebuild' {
        Invoke-Dotnet @('clean', $Solution, '-c', $Configuration)
        Invoke-Dotnet @('build', $Solution, '-c', $Configuration)
    }
    'clean' {
        Invoke-Dotnet @('clean', $Solution, '-c', $Configuration)
    }
    'run' {
        Invoke-Dotnet @('run', '--project', $Project, '-c', $Configuration)
    }
    'publish' {
        Invoke-Dotnet @(
            'publish', $Project,
            '-c', $Configuration,
            '-r', 'win-x64',
            '--self-contained', 'false',
            '-p:PublishSingleFile=true',
            '-o', $PublishDir
        )
        Write-Host "Published to $PublishDir" -ForegroundColor Green

        $exe = Get-Item (Join-Path $PublishDir 'PQShell.exe') -ErrorAction SilentlyContinue
        if (-not $exe) {
            throw "Publish reported success but PQShell.exe was not found in $PublishDir"
        }
        if (Test-Path $DeployDir) {
            Copy-Item $exe.FullName -Destination (Join-Path $DeployDir 'PQShell.exe') -Force
            Write-Host "Copied PQShell.exe -> $DeployDir" -ForegroundColor Green
        }
    }
}

Write-Host "$Task ($Configuration) OK" -ForegroundColor Green
