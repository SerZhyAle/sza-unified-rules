<#
fix-house-style.ps1 - the mechanical half of the house text style, applied in place.

Replaces em/en-dashes with a plain hyphen and "..."/ellipsis with ".." in PROSE only. It reuses
check-compliance.ps1's scoping exactly: fenced code blocks, inline code spans and markdown link targets
are left alone, and specs, planning trees, ticket trees, prompt folders and vendored trees are out of
scope because the canon scopes the style rule to prose and user-visible UI, never to code or specs.

The dash pass is safe to run unattended. The ellipsis pass is NOT, because a quoted real UI string or a
CLI placeholder legitimately contains "..." - it is off unless you pass -Ellipsis.

Exit codes: 0 = done (or nothing to do); 2 = internal error.

Usage:
  pwsh -File tools/fix-house-style.ps1 -RepoRoot P:\WINDOWS\CyrFlip -WhatIf
  pwsh -File tools/fix-house-style.ps1 -RepoRoot P:\WINDOWS\CyrFlip
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RepoRoot,
    [switch]$Ellipsis
)

$ErrorActionPreference = 'Stop'

try {
    if (-not $RepoRoot) {
        $top = & git rev-parse --show-toplevel 2>$null
        $RepoRoot = if ($LASTEXITCODE -eq 0 -and $top) { $top.Trim() } else { (Get-Location).Path }
    }
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

    $tracked = @(& git -C $RepoRoot ls-files 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "not a git repository: $RepoRoot" }

    # Identical scope to check-compliance.ps1 SZA-STYLE01.
    $skipRe = '(^|/)(PLAN/|tasks/|docs/specifications/|specs?/|DEV/|dev-notes/|\.claude/|\.agents/|\.github/prompts/|temp/|tmp/|node_modules|packages/|vendor/|third_party/)|THIRD.?PARTY'

    $changedFiles = 0
    $changedDash = 0
    $changedDots = 0

    foreach ($f in ($tracked | Where-Object { $_ -match '\.md$' -and $_ -notmatch $skipRe })) {
        $p = Join-Path $RepoRoot $f
        if (-not (Test-Path -LiteralPath $p)) { continue }

        # Never edit a render target: the next regeneration silently discards the fix, and the defect
        # lives in its source anyway.
        $head = (Get-Content -LiteralPath $p -TotalCount 4 -ErrorAction SilentlyContinue) -join "`n"
        if ($head -match '(?i)mirror.*unified[ _]rules' -or $head -match '(?i)render target') { continue }

        $lines = @(Get-Content -LiteralPath $p)
        $inFence = $false
        $fileDash = 0
        $fileDots = 0

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ($line -match '^\s*```') { $inFence = -not $inFence; continue }
            if ($inFence) { continue }

            # Rebuild the line, editing only the segments that are prose: everything outside inline
            # code spans and outside a markdown link target.
            $rebuilt = [System.Text.StringBuilder]::new()
            $protectRe = '`[^`]*`|\]\([^)]*\)'
            $pos = 0
            foreach ($m in [regex]::Matches($line, $protectRe)) {
                $prose = $line.Substring($pos, $m.Index - $pos)
                $fixed = $prose
                $fixed = $fixed -replace '[\u2013\u2014\u2015]', '-'
                if ($Ellipsis) { $fixed = $fixed -replace '\u2026', '..' -replace '\.{3,}', '..' }
                if ($fixed -ne $prose) {
                    $fileDash += ([regex]::Matches($prose, '[\u2013\u2014\u2015]')).Count
                    if ($Ellipsis) { $fileDots += ([regex]::Matches($prose, '\u2026|\.{3,}')).Count }
                }
                [void]$rebuilt.Append($fixed).Append($m.Value)
                $pos = $m.Index + $m.Length
            }
            $tail = $line.Substring($pos)
            $fixedTail = $tail -replace '[\u2013\u2014\u2015]', '-'
            if ($Ellipsis) { $fixedTail = $fixedTail -replace '\u2026', '..' -replace '\.{3,}', '..' }
            if ($fixedTail -ne $tail) {
                $fileDash += ([regex]::Matches($tail, '[\u2013\u2014\u2015]')).Count
                if ($Ellipsis) { $fileDots += ([regex]::Matches($tail, '\u2026|\.{3,}')).Count }
            }
            [void]$rebuilt.Append($fixedTail)

            $lines[$i] = $rebuilt.ToString()
        }

        if ($fileDash -gt 0 -or $fileDots -gt 0) {
            if ($PSCmdlet.ShouldProcess($f, "fix $fileDash dash(es), $fileDots ellipsis")) {
                # Preserve the file's existing line ending; do not rewrite the whole file's EOLs.
                $raw = [System.IO.File]::ReadAllText($p)
                $eol = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
                $trailing = if ($raw.EndsWith("`n")) { $eol } else { '' }
                [System.IO.File]::WriteAllText($p, ($lines -join $eol) + $trailing, (New-Object System.Text.UTF8Encoding($false)))
            }
            Write-Host "$f - $fileDash dash(es)$(if ($Ellipsis) { ", $fileDots ellipsis" })"
            $changedFiles++
            $changedDash += $fileDash
            $changedDots += $fileDots
        }
    }

    Write-Host "fix-house-style: $changedFiles file(s), $changedDash dash(es)$(if ($Ellipsis) { ", $changedDots ellipsis" })"
    exit 0
}
catch {
    Write-Error "fix-house-style: internal error: $_" -ErrorAction Continue
    exit 2
}
