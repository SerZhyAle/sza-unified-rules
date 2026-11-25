#requires -Version 7.0
<#
.SYNOPSIS
    Install or check the shared global "Project rules (every repository)" section for non-Claude agents.

.DESCRIPTION
    Reads the canonical section delimited by <!-- sza-global-rules:start --> and <!-- sza-global-rules:end -->
    from templates/agent-rules.md (single source of truth) and installs or updates ONLY that section inside
    each selected agent's user-level instruction file:
      codex  -> <HomeDir>/.codex/AGENTS.md
      gemini -> <HomeDir>/.gemini/GEMINI.md
      zcode  -> <HomeDir>/.zcode/AGENTS.md
      vibe   -> <HomeDir>/.vibe/AGENTS.md

    All other sections and headings in an existing file are preserved untouched. Opt-in: never invoked
    automatically by deploy.ps1 or check-compliance.ps1. Writes UTF-8 without BOM.

    Exit codes (DEVELOPMENT.md section 15, reachable-exit-code contract):
      0  all targets clean, updated, or dry-run completed
      1  -Check found missing or drifted target(s), or a file write failed
      2  could not verify (missing/unreadable template, missing delimiter markers, or invalid -HomeDir)
#>
[CmdletBinding()]
param(
    [switch] $Check,
    [switch] $DryRun,
    [string] $HomeDir = $HOME,
    [ValidateSet('codex', 'gemini', 'zcode', 'vibe')]
    [string[]] $Targets = @('codex', 'gemini', 'zcode', 'vibe'),
    [string] $TemplatePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'templates/agent-rules.md')
)
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($HomeDir)) {
    Write-Error 'install-agent-rules: -HomeDir is empty - cannot verify' -ErrorAction Continue
    exit 2
}
if (-not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) {
    Write-Error "install-agent-rules: template not found at '$TemplatePath' - cannot verify" -ErrorAction Continue
    exit 2
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$templateText = [IO.File]::ReadAllText($TemplatePath, $utf8NoBom)
$m = [regex]::Match($templateText, '(?s)<!--\s*sza-global-rules:start\s*-->\r?\n(.*?)\r?\n<!--\s*sza-global-rules:end\s*-->')
if (-not $m.Success) {
    Write-Error "install-agent-rules: markers sza-global-rules:start/end not found in '$TemplatePath' - cannot verify" -ErrorAction Continue
    exit 2
}
$canonical = ($m.Groups[1].Value -replace "`r`n", "`n").Trim()
if ($canonical -notmatch '^## Project rules \(every repository\)') {
    Write-Error "install-agent-rules: canonical block does not start with '## Project rules (every repository)' - cannot verify" -ErrorAction Continue
    exit 2
}

$targetRel = [ordered]@{
    codex  = '.codex/AGENTS.md'
    gemini = '.gemini/GEMINI.md'
    zcode  = '.zcode/AGENTS.md'
    vibe   = '.vibe/AGENTS.md'
}

$sectionRe = [regex]::new('(?ms)^## Project rules \(every repository\)[^\n]*\n.*?(?=\n#{1,2} |\z)')
$driftCount = 0
$errorCount = 0
$updatedCount = 0

foreach ($t in ($Targets | Select-Object -Unique)) {
    $filePath = Join-Path $HomeDir $targetRel[$t]
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        $newText = "# Global agent rules`n`n$canonical`n"
        if ($Check) {
            Write-Host ("DRIFT   {0,-6} {1} (missing file)" -f $t, $filePath)
            $driftCount++
        }
        elseif ($DryRun) {
            Write-Host ("CREATE  {0,-6} {1} (dry-run)" -f $t, $filePath)
            $updatedCount++
        }
        else {
            try {
                $parent = Split-Path -Parent $filePath
                if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
                    $null = New-Item -ItemType Directory -Path $parent -Force
                }
                [IO.File]::WriteAllText($filePath, $newText, $utf8NoBom)
                Write-Host ("CREATED {0,-6} {1}" -f $t, $filePath)
                $updatedCount++
            }
            catch {
                Write-Error "install-agent-rules: failed writing '$filePath': $_" -ErrorAction Continue
                $errorCount++
            }
        }
        continue
    }

    $raw = [IO.File]::ReadAllText($filePath, $utf8NoBom)
    $eol = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
    $norm = $raw -replace "`r`n", "`n"

    $match = $sectionRe.Match($norm)
    $status = 'ok'
    $nextNorm = $norm

    if ($match.Success) {
        $existingTrimmed = $match.Value.TrimEnd("`n", ' ', "`t")
        if ($existingTrimmed -ceq $canonical) {
            $status = 'ok'
        }
        else {
            $status = 'drift'
            $prefix = $norm.Substring(0, $match.Index)
            $suffix = $norm.Substring($match.Index + $match.Length)
            if ($suffix.Length -gt 0) {
                $suffix = "`n" + $suffix.TrimStart("`n")
                $nextNorm = $prefix + $canonical + "`n" + $suffix
            }
            else {
                $nextNorm = $prefix + $canonical + "`n"
            }
        }
    }
    else {
        $status = 'missing-section'
        $trimmed = $norm.TrimEnd("`n", ' ', "`t")
        if ([string]::IsNullOrEmpty($trimmed)) {
            $nextNorm = $canonical + "`n"
        }
        else {
            $nextNorm = $trimmed + "`n`n" + $canonical + "`n"
        }
    }

    if ($status -eq 'ok') {
        Write-Host ("OK      {0,-6} {1}" -f $t, $filePath)
        continue
    }

    if ($Check) {
        Write-Host ("DRIFT   {0,-6} {1} ({2})" -f $t, $filePath, $status)
        $driftCount++
    }
    elseif ($DryRun) {
        Write-Host ("UPDATE  {0,-6} {1} ({2}, dry-run)" -f $t, $filePath, $status)
        $updatedCount++
    }
    else {
        try {
            $outText = if ($eol -eq "`r`n") { $nextNorm -replace "`n", "`r`n" } else { $nextNorm }
            [IO.File]::WriteAllText($filePath, $outText, $utf8NoBom)
            Write-Host ("UPDATED {0,-6} {1} ({2})" -f $t, $filePath, $status)
            $updatedCount++
        }
        catch {
            Write-Error "install-agent-rules: failed writing '$filePath': $_" -ErrorAction Continue
            $errorCount++
        }
    }
}

if ($errorCount -gt 0) {
    Write-Host "install-agent-rules: FAILED ($errorCount write error(s))"
    exit 1
}
if ($Check -and $driftCount -gt 0) {
    Write-Host "install-agent-rules: DRIFT ($driftCount of $($Targets.Count) target(s) need update)"
    exit 1
}
Write-Host ("install-agent-rules: OK (mode={0} targets={1} changed={2})" -f $(if ($Check) { 'check' } elseif ($DryRun) { 'dry-run' } else { 'apply' }), $Targets.Count, $updatedCount)
exit 0
