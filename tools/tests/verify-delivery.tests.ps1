#requires -Version 7.0
<#
    Controls for tools/tests/verify-delivery.ps1, the replay of RULE-DELIVERY section 7 rung 4. The command is
    only worth running against a real installed plugin if it is known to say DELIVERED for a delivered copy
    and NOT DELIVERED for each way a copy can fail to be one, so this builds stand-in "installed" trees from
    the source tree and checks both. It never touches the real plugin cache and deploys nothing.

    A positive run replays the reader tests (about half a minute each), so the whole suite takes about two
    minutes. Exit codes: 0 all cases passed; 1 an assertion failed; 2 prerequisites/setup unavailable.
#>
[CmdletBinding()]
param(
    [string]$SourceRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$CatalogRoot = $(if ($env:SZA_CONTRACTS_ROOT) { $env:SZA_CONTRACTS_ROOT } else { 'P:\Contracts' })
)

$ErrorActionPreference = 'Stop'
$run = 0
$failed = 0
$scratch = $null
$tool = Join-Path $SourceRoot 'tools/tests/verify-delivery.ps1'

function Assert-That([bool]$Condition, [string]$Reason) { if (-not $Condition) { throw $Reason } }
function Test-Case([string]$Name, [scriptblock]$Body) {
    $script:run++
    try { & $Body; "OK $Name" }
    catch { $script:failed++; "FAIL $Name - $($_.Exception.Message)" }
}
function Invoke-Tool([string]$Installed) {
    $out = & pwsh -NoProfile -File $tool -InstalledRoot $Installed -SourceRoot $SourceRoot -CatalogRoot $CatalogRoot 2>&1 | Out-String
    [pscustomobject]@{ code = $LASTEXITCODE; output = $out.Trim() }
}

# What the tool reads from a plugin tree, copied the way a plugin install would carry it.
function New-Installed([string]$Name) {
    $dest = Join-Path $scratch $Name
    New-Item -ItemType Directory -Path $dest | Out-Null
    foreach ($item in @('.claude-plugin', 'CANON_VERSION', 'rules', 'tools', 'templates', 'skills', 'hooks')) {
        $from = Join-Path $SourceRoot $item
        if (Test-Path -LiteralPath $from) { Copy-Item -LiteralPath $from -Destination (Join-Path $dest $item) -Recurse -Force }
    }
    foreach ($junk in @('tools/__pycache__', 'tools/tests/__pycache__')) {
        $p = Join-Path $dest $junk
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
    }
    return $dest
}
function Convert-ToCrlf([string]$Root) {
    foreach ($file in (Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object { $_.Extension -in @('.ps1', '.md', '.json', '.py', '.tpl', '.txt') -or $_.Name -eq 'CANON_VERSION' })) {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $text = [System.Text.Encoding]::Latin1.GetString($bytes).Replace("`r`n", "`n").Replace("`n", "`r`n")
        [System.IO.File]::WriteAllBytes($file.FullName, [System.Text.Encoding]::Latin1.GetBytes($text))
    }
}

try {
    foreach ($required in @($tool, (Join-Path $SourceRoot 'tools/tests/contract-reader.tests.ps1'), (Join-Path $CatalogRoot 'rule-adoption/vectors/manifest.json'))) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Missing prerequisite: $required" }
    }
    $scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('s0012-delivery-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $scratch | Out-Null

    Test-Case 'a copy identical to the source is DELIVERED and the replay passes' {
        $r = Invoke-Tool (New-Installed 'identical')
        Assert-That ($r.code -eq 0 -and $r.output -match 'verify-delivery: DELIVERED') "exit $($r.code): $($r.output)"
        Assert-That ($r.output -match 'replay contract-reader against the installed tree: exit 0') 'the replay did not run green'
    }

    Test-Case 'a copy whose files all carry CRLF (an autocrlf checkout of the same source) is still DELIVERED' {
        $copy = New-Installed 'crlf'
        Convert-ToCrlf $copy
        $r = Invoke-Tool $copy
        Assert-That ($r.code -eq 0 -and $r.output -match 'verify-delivery: DELIVERED') "exit $($r.code): $($r.output)"
        Assert-That ($r.output -match 'reader files \(catalog manifest, \d+\): (\d+) equal, 0 not') 'line endings made reader files look different'
    }

    Test-Case 'a copy without a reader file is NOT DELIVERED and says it is missing' {
        $copy = New-Installed 'missing'
        Remove-Item -LiteralPath (Join-Path $copy 'tools/lib/schema-carrier.ps1') -Force
        $r = Invoke-Tool $copy
        Assert-That ($r.code -eq 1 -and $r.output -match 'verify-delivery: NOT DELIVERED') "exit $($r.code): $($r.output)"
        Assert-That ($r.output -match 'schema-carrier\.ps1 \(missing in installed\)') 'the missing file is not named'
    }

    Test-Case 'a copy whose reader differs under the SAME version is NOT DELIVERED as an unreleased change' {
        $copy = New-Installed 'same-version'
        Add-Content -LiteralPath (Join-Path $copy 'tools/contract-lag.ps1') -Value '# a change nobody released'
        $r = Invoke-Tool $copy
        Assert-That ($r.code -eq 1 -and $r.output -match 'verify-delivery: NOT DELIVERED') "exit $($r.code): $($r.output)"
        Assert-That ($r.output -match 'same plugin version carries different content') 'the unreleased-change reason is missing'
    }

    Test-Case 'a copy on an older version is NOT DELIVERED and names both versions' {
        $copy = New-Installed 'older'
        Set-Content -LiteralPath (Join-Path $copy 'CANON_VERSION') -Value '2026.10.01.1'
        $pluginFile = Join-Path $copy '.claude-plugin/plugin.json'
        (Get-Content -LiteralPath $pluginFile -Raw) -replace '"version"\s*:\s*"[^"]+"', '"version": "2026.1001.1"' | Set-Content -LiteralPath $pluginFile -Encoding utf8
        $r = Invoke-Tool $copy
        Assert-That ($r.code -eq 1) "exit $($r.code): $($r.output)"
        Assert-That ($r.output -match 'installed plugin version 2026\.1001\.1 is not the source''s') 'the version lag is not reported'
    }

    Test-Case 'a plugin version that does not derive from CANON_VERSION is reported as hand-written' {
        $copy = New-Installed 'hand-edited'
        $pluginFile = Join-Path $copy '.claude-plugin/plugin.json'
        (Get-Content -LiteralPath $pluginFile -Raw) -replace '"version"\s*:\s*"[^"]+"', '"version": "2026.9999.9"' | Set-Content -LiteralPath $pluginFile -Encoding utf8
        $r = Invoke-Tool $copy
        Assert-That ($r.code -eq 1 -and $r.output -match 'does not derive') "exit $($r.code): $($r.output)"
    }

    Test-Case 'a tree that does not exist cannot be verified (exit 2)' {
        $r = Invoke-Tool (Join-Path $scratch 'no-such-tree')
        Assert-That ($r.code -eq 2 -and $r.output -match 'verify-delivery: COULD NOT VERIFY') "exit $($r.code): $($r.output)"
    }

    if ($run -eq 0) { throw 'No test cases executed' }
    $verdict = if ($failed) { 'FAIL' } else { 'PASS' }
    Write-Output "verify-delivery-tests: $verdict (run=$run skipped=0)"
    exit $(if ($failed) { 1 } else { 0 })
} catch {
    Write-Output $_.Exception.Message
    Write-Output "verify-delivery-tests: COULD NOT VERIFY (run=$run skipped=0)"
    exit 2
} finally {
    if ($scratch -and (Test-Path -LiteralPath $scratch)) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
