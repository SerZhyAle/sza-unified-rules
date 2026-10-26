#requires -Version 7.0
<#
.SYNOPSIS
    Judge, read-only, whether a change made in this source tree has reached an INSTALLED copy of the canon
    plugin - the replay of RULE-DELIVERY section 7 rung 4.

.DESCRIPTION
    A green test in the source tree proves the source. A consumer runs the plugin cache, and `claude plugin
    update` compares the plugin version and nothing else, so a change shipped without moving it reaches nobody
    while every report says success (RULE-DELIVERY rule 1). This command compares the two trees and replays
    the catalog's reader artifacts against the installed one:

      1. the version pair of each tree (CANON_VERSION and the plugin version derived from it, rule 2) and
         whether it is consistent - a pair that does not derive was written by hand;
      2. the core digest of each tree (rule 3), from the tree's own check-compliance.ps1;
      3. the SHA-256 of every reader file the catalog manifest fingerprints, installed against source;
      4. the file-level difference of tools/, skills/, hooks/, rules/ and templates/, as information;
      5. the reader tests, run FROM this tree with the installed tree as their -SourceRoot.

    DELIVERED needs: the same version, a consistent pair, equal reader files and a passing replay. Everything
    else is NOT DELIVERED, with the reasons named - in particular "the same version but different content",
    which is the unreleased change the plugin version exists to prevent. The output carries the one row rung 4
    asks for: the pair and the digest of both trees. Run it before a deploy (the row is the "before") and
    after `claude plugin update` (the "after").

    Nothing is written, deployed or updated; the installed tree is only read.

.PARAMETER InstalledRoot
    The installed plugin directory. Default: the installPath of `sza@sza-unified-rules` in the plugins file.

.PARAMETER SourceRoot
    The source tree. Default: the repository this script belongs to.

.PARAMETER CatalogRoot
    The contracts catalog (its rule-adoption/vectors/manifest.json lists the reader files, and the reader
    tests replay its artifacts). Default: $env:SZA_CONTRACTS_ROOT, else P:\Contracts.

.PARAMETER PluginsFile
    installed_plugins.json. Default: ~/.claude/plugins/installed_plugins.json.

.PARAMETER IncludeHarness
    Also replay tools/tests/batch-runner.tests.ps1, ledger-rules.tests.ps1 and layout-gate.tests.ps1 against
    the installed tree (about eight minutes).

.EXAMPLE
    pwsh -NoProfile -File tools/tests/verify-delivery.ps1
    pwsh -NoProfile -File tools/tests/verify-delivery.ps1 -IncludeHarness

Exit codes: 0 delivered; 1 not delivered (reasons printed); 2 could not verify (a tree or the catalog is
missing, or the digest could not be read).
#>
[CmdletBinding()]
param(
    [string]$InstalledRoot,
    [string]$SourceRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$CatalogRoot = $(if ($env:SZA_CONTRACTS_ROOT) { $env:SZA_CONTRACTS_ROOT } else { 'P:\Contracts' }),
    [string]$PluginsFile = (Join-Path $HOME '.claude/plugins/installed_plugins.json'),
    [switch]$IncludeHarness
)

$ErrorActionPreference = 'Stop'
$reasons = [System.Collections.Generic.List[string]]::new()

# CRLF read as LF, as in contract-reader.tests.ps1: an installed copy is a git checkout and takes this
# machine's autocrlf setting, while the working tree keeps whatever endings its writers used.
function Get-TextHash([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $normalized = [System.Text.Encoding]::Latin1.GetBytes([System.Text.Encoding]::Latin1.GetString($bytes).Replace("`r`n", "`n"))
    [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($normalized)).Replace('-', '')
}

function Read-Pair([string]$Root) {
    $canonFile = Join-Path $Root 'CANON_VERSION'
    $pluginFile = Join-Path $Root '.claude-plugin/plugin.json'
    foreach ($f in @($canonFile, $pluginFile)) { if (-not (Test-Path -LiteralPath $f)) { throw "Not a canon plugin tree, missing: $f" } }
    $canon = (Get-Content -LiteralPath $canonFile -Raw).Trim()
    $plugin = [string](Get-Content -LiteralPath $pluginFile -Raw | ConvertFrom-Json).version
    # RULE-DELIVERY rule 2: 2026.08.18.1 -> 2026.818.1 (month and day join into one numeric identifier).
    $derived = $null
    if ($canon -match '^(\d{4})\.(\d{2})\.(\d{2})\.(\d+)$') { $derived = '{0}.{1}.{2}' -f $Matches[1], [int]($Matches[2] + $Matches[3]), $Matches[4] }
    [pscustomobject]@{ canon = $canon; plugin = $plugin; derived = $derived; consistent = [bool]($derived -and $derived -eq $plugin) }
}

function Read-Digest([string]$Root) {
    $gate = Join-Path $Root 'tools/check-compliance.ps1'
    if (-not (Test-Path -LiteralPath $gate)) { throw "No digest reader in the tree: $gate" }
    $out = & pwsh -NoProfile -File $gate -PrintDigest 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $out -notmatch 'sha256:[0-9a-f]{64}') { throw "Digest unavailable from ${Root}: $($out.Trim())" }
    $Matches[0]
}

function Get-TreeHashes([string]$Root, [string[]]$Folders) {
    $map = @{}
    foreach ($folder in $Folders) {
        $base = Join-Path $Root $folder
        if (-not (Test-Path -LiteralPath $base)) { continue }
        foreach ($file in (Get-ChildItem -LiteralPath $base -Recurse -File -Force |
                Where-Object { $_.FullName -notmatch '[\\/](__pycache__|temp|node_modules)[\\/]' })) {
            $map[($file.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/')] = $file
        }
    }
    $map
}

try {
    if (-not $InstalledRoot) {
        if (-not (Test-Path -LiteralPath $PluginsFile)) { throw "No installed plugin to read: $PluginsFile" }
        $entry = @((Get-Content -LiteralPath $PluginsFile -Raw | ConvertFrom-Json).plugins.'sza@sza-unified-rules')
        if ($entry.Count -eq 0) { throw 'sza@sza-unified-rules is not installed' }
        $InstalledRoot = [string]$entry[0].installPath
    }
    foreach ($tree in @($InstalledRoot, $SourceRoot)) { if (-not (Test-Path -LiteralPath $tree)) { throw "Tree not found: $tree" } }
    $manifestPath = Join-Path $CatalogRoot 'rule-adoption/vectors/manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Catalog manifest not found: $manifestPath" }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

    $installed = Read-Pair $InstalledRoot
    $source = Read-Pair $SourceRoot
    # The source tree failing to name its own digest is a setup fault (exit 2). The installed tree failing to
    # is a finding: a copy that cannot run its own gate has not been delivered whole.
    $sourceDigest = Read-Digest $SourceRoot
    $installedDigest = 'unreadable'
    try { $installedDigest = Read-Digest $InstalledRoot }
    catch { $reasons.Add("the installed tree cannot compute its own core digest: $(($_.Exception.Message -split "`r?`n")[0])") }

    Write-Output "installed : $InstalledRoot"
    Write-Output "source    : $SourceRoot"
    Write-Output ''
    Write-Output '| tree | CANON_VERSION | plugin version | derives | core digest |'
    Write-Output '| --- | --- | --- | --- | --- |'
    Write-Output "| installed | $($installed.canon) | $($installed.plugin) | $($installed.consistent) | $installedDigest |"
    Write-Output "| source | $($source.canon) | $($source.plugin) | $($source.consistent) | $sourceDigest |"
    Write-Output ''

    if (-not $installed.consistent) { $reasons.Add("installed version pair does not derive (CANON_VERSION $($installed.canon) -> $($installed.derived), plugin $($installed.plugin)): written by hand") }
    if (-not $source.consistent) { $reasons.Add("source version pair does not derive (CANON_VERSION $($source.canon) -> $($source.derived), plugin $($source.plugin)): written by hand") }
    if ($installed.plugin -ne $source.plugin) { $reasons.Add("installed plugin version $($installed.plugin) is not the source's $($source.plugin): the update has not delivered it") }
    if ($installedDigest -ne 'unreadable' -and $installedDigest -ne $sourceDigest) { $reasons.Add('core digests differ: the rule documents the consumer holds are not the source''s') }

    $differing = [System.Collections.Generic.List[string]]::new()
    foreach ($entryFile in $manifest.sources) {
        $path = [string]$entryFile.path
        $srcFile = Join-Path $SourceRoot $path
        $insFile = Join-Path $InstalledRoot $path
        if (-not (Test-Path -LiteralPath $insFile)) { $differing.Add("$path (missing in installed)") }
        elseif ((Get-TextHash $srcFile) -ne (Get-TextHash $insFile)) { $differing.Add("$path (differs)") }
    }
    Write-Output "reader files (catalog manifest, $(@($manifest.sources).Count)): $(@($manifest.sources).Count - $differing.Count) equal, $($differing.Count) not"
    foreach ($d in $differing) { Write-Output "  - $d" }
    if ($differing.Count -gt 0) {
        $reasons.Add("$($differing.Count) reader file(s) differ from the source")
        if ($installed.plugin -eq $source.plugin) { $reasons.Add('the same plugin version carries different content: a change shipped without moving the version reaches nobody (RULE-DELIVERY rule 1)') }
    }

    $folders = @('tools', 'skills', 'hooks', 'rules', 'templates')
    $s = Get-TreeHashes $SourceRoot $folders
    $i = Get-TreeHashes $InstalledRoot $folders
    $missing = @($s.Keys | Where-Object { -not $i.ContainsKey($_) }).Count
    $extra = @($i.Keys | Where-Object { -not $s.ContainsKey($_) }).Count
    $changed = @($s.Keys | Where-Object { $i.ContainsKey($_) -and (Get-TextHash $s[$_].FullName) -ne (Get-TextHash $i[$_].FullName) }).Count
    Write-Output "whole trees ($($folders -join ', ')): $missing file(s) only in source, $extra only in installed, $changed differ"
    Write-Output ''

    $replays = @(@{ name = 'contract-reader'; script = 'contract-reader.tests.ps1'; extra = @('-CatalogRoot', $CatalogRoot) })
    if ($IncludeHarness) {
        $replays += @{ name = 'batch-runner'; script = 'batch-runner.tests.ps1'; extra = @('-CatalogRoot', $CatalogRoot) }
        $replays += @{ name = 'ledger-rules'; script = 'ledger-rules.tests.ps1'; extra = @() }
        $replays += @{ name = 'layout-gate'; script = 'layout-gate.tests.ps1'; extra = @() }
    }
    foreach ($replay in $replays) {
        $script = Join-Path $SourceRoot "tools/tests/$($replay.script)"
        $out = & pwsh -NoProfile -File $script -SourceRoot $InstalledRoot @($replay.extra) 2>&1 | Out-String
        $code = $LASTEXITCODE
        $verdict = (($out -split "`r?`n") | Where-Object { $_ -match 'tests?: ' } | Select-Object -Last 1)
        if (-not $verdict) { $verdict = (($out -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -First 1) }
        Write-Output "replay $($replay.name) against the installed tree: exit $code - $verdict"
        if ($code -ne 0) { $reasons.Add("replay $($replay.name) does not pass against the installed tree (exit $code)") }
    }
    Write-Output ''

    if ($reasons.Count -eq 0) {
        Write-Output 'verify-delivery: DELIVERED'
        exit 0
    }
    Write-Output 'verify-delivery: NOT DELIVERED'
    foreach ($r in $reasons) { Write-Output "  - $r" }
    exit 1
} catch {
    Write-Output $_.Exception.Message
    Write-Output 'verify-delivery: COULD NOT VERIFY'
    exit 2
}
