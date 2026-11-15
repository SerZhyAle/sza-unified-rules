#requires -Version 7.0
<#
    SZA-CTR04: the product command pointer is required only for a repository with a manifest, and
    must name both discovery interfaces in one agent-rules file. Main and companion manifests count.
    Exit 0 on success, 1 on failure. Fixtures are created under temp/S0074_app-commands-agent-awareness.
#>
$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$base = [IO.Path]::GetFullPath((Join-Path $sourceRoot 'temp/S0074_app-commands-agent-awareness'))
$scratch = Join-Path $base ('awareness-' + [guid]::NewGuid().ToString('N'))
$failures = 0
$cases = 0

function Assert-Gate([string]$Name, [bool]$ExpectFinding, [switch]$Strict) {
    $script:cases++
    $argsList = @('-NoProfile', '-File', (Join-Path $sourceRoot 'tools/check-compliance.ps1'),
        '-RepoRoot', $scratch, '-Only', 'SZA-CTR04', '-Json')
    if ($Strict) { $argsList += '-Strict' }
    $output = & pwsh @argsList 2>&1 | Out-String
    $code = $LASTEXITCODE
    try {
        $report = $output | ConvertFrom-Json -ErrorAction Stop
        $findings = @($report.findings | Where-Object id -eq 'SZA-CTR04')
        $expectedCode = if ($Strict -and $ExpectFinding) { 1 } else { 0 }
        if ($code -ne $expectedCode -or $findings.Count -ne [int]$ExpectFinding) {
            throw "expected exit $expectedCode and $([int]$ExpectFinding) finding(s); got exit $code and $($findings.Count)"
        }
        if ($ExpectFinding -and $findings[0].severity -ne $(if ($Strict) { 'error' } else { 'warn' })) {
            throw "unexpected severity $($findings[0].severity)"
        }
        Write-Host "PASS $Name"
    }
    catch { $script:failures++; Write-Host "FAIL $Name - $($_.Exception.Message)" }
}

try {
    New-Item -ItemType Directory -Path (Join-Path $scratch 'docs') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $scratch 'CLAUDE.md') -Value '# Agent rules' -Encoding utf8
    Assert-Gate 'no manifest needs no command pointer' $false

    Set-Content -LiteralPath (Join-Path $scratch 'docs/cli-commands.json') -Value '{}' -Encoding utf8
    Assert-Gate 'main manifest without pointer warns' $true

    Set-Content -LiteralPath (Join-Path $scratch 'CLAUDE.md') -Value 'Read docs/CLI.md.' -Encoding utf8
    Assert-Gate 'one discovery interface alone warns' $true

    Set-Content -LiteralPath (Join-Path $scratch 'CLAUDE.md') -Value 'Read docs/CLI.md; run app commands --json.' -Encoding utf8
    Assert-Gate 'both discovery interfaces pass' $false

    Remove-Item -LiteralPath (Join-Path $scratch 'docs/cli-commands.json')
    Set-Content -LiteralPath (Join-Path $scratch 'docs/cli-commands.helper.json') -Value '{}' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $scratch 'CLAUDE.md') -Value '# Agent rules' -Encoding utf8
    Assert-Gate 'companion-only manifest warns, strict upgrades it' $true -Strict
}
finally {
    $resolved = [IO.Path]::GetFullPath($scratch)
    if (-not $resolved.StartsWith($base + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "refusing to remove scratch outside $base"
    }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}

Write-Host "app-commands-awareness: $cases case(s), $failures failure(s)"
if ($failures) { exit 1 }
exit 0
