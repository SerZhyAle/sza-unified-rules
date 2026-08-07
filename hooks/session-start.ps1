<#
session-start.ps1 - inject the canon's hard invariants into the session context.

Fires only when the working directory belongs to a repo that has adopted the canon (an .sza-canon.json
stamp at the repo root). That keeps the injection self-limiting: an unrelated project never pays for it,
and an SZA project always carries the twenty lines it must not break.

Exits 0 with the SessionStart hookSpecificOutput shape, or 0 with no output when the repo is not an
adopter. It can never block a session.
#>
$ErrorActionPreference = 'Stop'

try {
    $raw = [Console]::In.ReadToEnd()
    $cwd = $null
    if ($raw) {
        try { $cwd = ($raw | ConvertFrom-Json).cwd } catch { $cwd = $null }
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
    if (-not (Test-Path -LiteralPath $invariants)) { exit 0 }

    $text = Get-Content -LiteralPath $invariants -Raw

    $overlay = ''
    $model = ''
    try {
        $parsed = Get-Content -LiteralPath $stamp -Raw | ConvertFrom-Json
        if ($parsed.overlay) { $overlay = " Overlay $($parsed.overlay -join ',')." }
        if ($parsed.canon -and $parsed.canon.model) { $model = " Consumption model: $($parsed.canon.model)." }
    }
    catch { }

    $header = @"
This repository has adopted the SZA Unified Rules canon.$overlay$model
The full rule set and the working skills ship with the ``sza`` plugin - load a skill rather than the whole
canon: ``release``, ``store-publish``, ``feature-to-site``, ``spec-to-audit``, ``adopt-canon``,
``agent-cost``, ``caveman``. The plugin also enforces five behaviours as hooks rather than as prose, so a
disk-wide ``find``, a ``.ps1`` run as a Bash command, and an uncapped read of a large file are blocked at
the tool call (``hooks/README.md``).
The lines below are the hard invariants; everything else lives in the reference docs and the skills.

"@

    $payload = [pscustomobject]@{
        hookSpecificOutput = [pscustomobject]@{
            hookEventName    = 'SessionStart'
            additionalContext = $header + $text
        }
    }
    $payload | ConvertTo-Json -Depth 5 -Compress
    exit 0
}
catch {
    Write-Error "sza session-start hook: $_" -ErrorAction Continue
    exit 1
}
