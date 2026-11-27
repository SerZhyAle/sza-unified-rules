<#
session-start.ps1 - inject the canon's hard invariants into the session context.

Fires only when the working directory belongs to a repo that has adopted the canon (an .sza-canon.json
stamp at the repo root). That keeps the injection self-limiting: an unrelated project never pays for it,
and an SZA project always carries the hard invariants.

It also appends the type memory of the session's user (tools/memory/memory.ps1): the index of every
<memory root>/types/<tag>/ whose type.json matches this stamp's overlay, channels, site kind or role. The memory
root is SZA_MEMORY_ROOT, else <claude home>/memory; no folder there means nothing is appended.

When the plugin runs from a cache folder named by its version and a higher version folder sits beside it, one
line asks for a session restart.

Exits 0 with the SessionStart hookSpecificOutput shape, or 0 with no output when the repo is not an
adopter. It can never block a session.
#>
$ErrorActionPreference = 'Stop'

try {
    $raw = [Console]::In.ReadToEnd()
    $cwd = $null
    $isAgy = $false
    if ($raw) {
        try {
            $inObj = $raw | ConvertFrom-Json
            if ($null -ne $inObj) {
                $isAgy = ($null -ne $inObj.PSObject.Properties['hookEventName']) -or ($null -ne $inObj.PSObject.Properties['workspacePaths'])
                if ($null -ne $inObj.PSObject.Properties['cwd']) { $cwd = [string]$inObj.cwd }
                if (-not $cwd -and $null -ne $inObj.PSObject.Properties['workspacePaths'] -and @($inObj.workspacePaths).Count -gt 0) {
                    $cwd = [string]$inObj.workspacePaths[0]
                }
            }
        } catch { $cwd = $null }
    }
    if (-not $cwd) { $cwd = (Get-Location).Path }

    # Walk up to the repo root, stopping at the drive root.
    $dir = $cwd
    $stamp = $null
    while ($dir) {
        $candidate = Join-Path $dir '.sza-canon.json'
        if (Test-Path -LiteralPath $candidate) { $stamp = $candidate; break }
        if (Test-Path -LiteralPath (Join-Path $dir '.git')) { break }
        $parent = Split-Path $dir -Parent
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }

    if (-not $stamp) { exit 0 }

    $pluginRoot = Split-Path $PSScriptRoot -Parent
    $invariants = Join-Path $pluginRoot 'rules/INVARIANTS.md'
    if (-not (Test-Path -LiteralPath $invariants)) {
        $hookDirItem = Get-Item -LiteralPath $PSScriptRoot -Force -ErrorAction SilentlyContinue
        if ($hookDirItem -and $hookDirItem.Target) {
            $realRoot = Split-Path (@($hookDirItem.Target)[0]) -Parent
            $invariants = Join-Path $realRoot 'rules/INVARIANTS.md'
        }
    }
    if (-not (Test-Path -LiteralPath $invariants)) { exit 0 }

    $text = Get-Content -LiteralPath $invariants -Raw

    $overlay = ''
    $model = ''
    $parsed = $null
    try {
        $parsed = Get-Content -LiteralPath $stamp -Raw | ConvertFrom-Json
        if ($parsed.overlay) { $overlay = " Overlay $($parsed.overlay -join ',')." }
        if ($parsed.canon -and $parsed.canon.model) { $model = " Consumption model: $($parsed.canon.model)." }
    }
    catch { }

    # Type memory (tools/memory/memory.ps1): the index of every memory type whose type.json matches this stamp.
    # The global index reaches every session through the user's CLAUDE.md import; a type index has no such
    # route, because it depends on the project, so it rides here. A broken type folder is skipped, never fatal.
    $typeMemory = ''
    try {
        $claudeHome = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude' }
        $memRoot = if ($env:SZA_MEMORY_ROOT) { $env:SZA_MEMORY_ROOT } else { Join-Path $claudeHome 'memory' }
        $typesDir = Join-Path $memRoot 'types'
        if ($parsed -and (Test-Path -LiteralPath $typesDir)) {
            $have = @{ overlay = @($parsed.overlay); channels = @($parsed.channels); site = @($parsed.site.kind); role = @($parsed.role) }
            foreach ($t in Get-ChildItem -LiteralPath $typesDir -Directory | Sort-Object Name) {
                try {
                    $spec = Join-Path $t.FullName 'type.json'
                    $index = Join-Path $t.FullName 'MEMORY.md'
                    if (-not (Test-Path -LiteralPath $spec) -or -not (Test-Path -LiteralPath $index)) { continue }
                    $def = Get-Content -LiteralPath $spec -Raw | ConvertFrom-Json
                    $hit = $false
                    foreach ($key in 'overlay', 'channels', 'site', 'role') {
                        $want = @($def.match.$key)
                        if ($want.Count -and @($want | Where-Object { $have[$key] -contains $_ }).Count) { $hit = $true }
                    }
                    if (-not $hit) { continue }
                    $lines = (Get-Content -LiteralPath $index -Raw -Encoding utf8).TrimEnd()
                    if (-not $lines) { continue }
                    $typeMemory += "`n## Type memory: $($t.Name) - $($def.title)`nFiles in ``$($t.FullName)``; read one before acting on its line.`n$lines`n"
                }
                catch { }
            }
        }
    }
    catch { $typeMemory = '' }

    $header = @"
This repository has adopted the SZA Unified Rules canon.$overlay$model
The full rule set and working skills ship with the ``sza`` plugin.
The lines below are the hard invariants; everything else lives in the reference docs and the skills.

"@

    # A session keeps the plugin version it started with. Installed from the cache, the plugin root is the folder
    # sza/<version>; a higher sibling means this session runs superseded code. Folder names only, to stay fast.
    try {
        $running = $null
        if ([version]::TryParse((Split-Path $pluginRoot -Leaf), [ref]$running)) {
            $newest = $running
            foreach ($d in [IO.Directory]::GetDirectories((Split-Path $pluginRoot -Parent))) {
                $v = $null
                if ([version]::TryParse([IO.Path]::GetFileName($d), [ref]$v) -and $v -gt $newest) { $newest = $v }
            }
            if ($newest -gt $running) { $header += "`nplugin cache is older than installed ${newest}: restart the session`n" }
        }
    }
    catch { }

    $payload = if ($isAgy) {
        [pscustomobject]@{
            injectSteps = @(
                [pscustomobject]@{
                    systemMessage = [pscustomobject]@{
                        systemMessage = $header + $text + $typeMemory
                    }
                }
            )
        }
    } else {
        [pscustomobject]@{
            hookSpecificOutput = [pscustomobject]@{
                hookEventName     = 'SessionStart'
                additionalContext = $header + $text + $typeMemory
            }
        }
    }
    $json = $payload | ConvertTo-Json -Depth 5 -Compress

    # Write the BYTES, not the string: a redirected stdout inherits the console code page, and on a
    # Cyrillic Windows console (866 where this was measured) that maps the canon's own section sign and
    # Cyrillic letters onto single bytes the reader then decodes as UTF-8. The result is a control
    # character inside a JSON string, so the whole injection is discarded with a parse error and the
    # invariants never reach the session - measured 2026-09-18 as 420 discarded injections across 391
    # sessions, all of them silent except the error banner.
    $bytes = (New-Object System.Text.UTF8Encoding $false).GetBytes($json + "`n")
    $stdout = [Console]::OpenStandardOutput()
    $stdout.Write($bytes, 0, $bytes.Length)
    $stdout.Flush()
    exit 0
}
catch {
    Write-Error "sza session-start hook: $_" -ErrorAction Continue
    exit 1
}
