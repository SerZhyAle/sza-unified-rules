#requires -Version 7.0
<#
.SYNOPSIS
    Tests for the duplicate-note refusal of memory.ps1 (check, index) and for the empty-adopter list of its audit.

.DESCRIPTION
    Runs exclusively against a temporary scratch claude home (never reads or writes ~/.claude). memory.ps1 is
    called in-process, so the suite starts no child shell.
    Exit codes: 0 all passed; 1 assertion failed.
#>
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$memoryScript = Join-Path $repoRoot 'tools/memory/memory.ps1'
$utf8 = [System.Text.UTF8Encoding]::new($false)

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('sza-memory-duplicate-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $scratch -Force
$script:passed = 0
$script:failed = 0

function Write-Utf8([string]$Path, [string]$Text) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
    [IO.File]::WriteAllText($Path, $Text, $utf8)
}

function Write-Note([string]$Path, [string]$Name, [string]$Body) {
    Write-Utf8 $Path "---`nname: $Name`ndescription: $Name`nmetadata:`n  scope: project`n---`n`n$Body`n"
}

function Test-Case([string]$Name, [scriptblock]$Body) {
    try {
        & $Body
        $script:passed++
        Write-Host "PASS  $Name"
    }
    catch {
        $script:failed++
        Write-Host "FAIL  $Name - $_" -ForegroundColor Red
    }
}

function Assert([bool]$Cond, [string]$Msg) {
    if (-not $Cond) { throw $Msg }
}

function Invoke-Memory([string]$Command, [hashtable]$Arguments) {
    $out = (& $memoryScript $Command @Arguments) -join "`n"
    [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}

$origClaudeDir = $env:CLAUDE_CONFIG_DIR
$origMemRoot = $env:SZA_MEMORY_ROOT

try {
    $claudeHome = Join-Path $scratch 'claude-home'
    $memRoot = Join-Path $claudeHome 'memory'
    $typeDir = Join-Path $memRoot 'types/desk'
    $projMem = Join-Path $claudeHome 'projects/p--demo/memory'
    $env:CLAUDE_CONFIG_DIR = $claudeHome
    $env:SZA_MEMORY_ROOT = $memRoot

    Write-Note (Join-Path $memRoot 'never-undo-with-git.md') 'never-undo-with-git' 'The owner commits only to cut releases.'
    Write-Utf8 (Join-Path $memRoot 'MEMORY.md') "- [never-undo-with-git](never-undo-with-git.md) - kept`n"
    Write-Utf8 (Join-Path $typeDir 'type.json') '{"title":"Desk","match":{"overlay":["A"]}}'
    Write-Note (Join-Path $typeDir 'suspend-the-tree.md') 'suspend-the-tree' 'Suspend every container before a bulk change.'
    Write-Note (Join-Path $typeDir 'short-heading.md') 'short-heading' '# Notes'

    $bySlug = Join-Path $projMem 'never_undo_with_git.md'
    $byLine = Join-Path $projMem 'layout-trap.md'
    $distinct = Join-Path $projMem 'own-fact.md'
    Write-Note $bySlug 'git-is-not-undo' 'Something worded in a different way here.'
    Write-Note $byLine 'layout-trap' '**Suspend every container** before a bulk change!'
    Write-Note $distinct 'own-fact' '# Notes'

    Test-Case '1. check refuses the same slug and names the global note' {
        $r = Invoke-Memory 'check' @{ Path = $bySlug }
        Assert ($r.Code -eq 1) "exit $($r.Code): $($r.Out)"
        Assert ($r.Out -match "same slug as the global note 'never-undo-with-git'") $r.Out
    }

    Test-Case '2. check refuses the same first line and names the type note' {
        $r = Invoke-Memory 'check' @{ Path = $byLine }
        Assert ($r.Code -eq 1) "exit $($r.Code): $($r.Out)"
        Assert ($r.Out -match "same first line as the type:desk note 'suspend-the-tree'") $r.Out
    }

    Test-Case '3. check accepts an own fact, a short shared heading, and a wider note itself' {
        $r = Invoke-Memory 'check' @{ Path = @($distinct, (Join-Path $memRoot 'never-undo-with-git.md')) }
        Assert ($r.Code -eq 0) "exit $($r.Code): $($r.Out)"
        Assert ($r.Out -notmatch 'refused') $r.Out
    }

    Test-Case '4. index leaves a new duplicate out, lists the rest, keeps a listed line' {
        Write-Utf8 (Join-Path $projMem 'MEMORY.md') "- [Old copy](layout-trap.md) - listed before the refusal`n"
        $r = Invoke-Memory 'index' @{ Folder = $projMem }
        Assert ($r.Code -eq 1) "exit $($r.Code): $($r.Out)"
        Assert ($r.Out -match 'never_undo_with_git\.md - same slug') $r.Out
        $index = [IO.File]::ReadAllText((Join-Path $projMem 'MEMORY.md'), $utf8)
        Assert ($index -match 'own-fact\.md') "own note not listed: $index"
        Assert ($index -match 'listed before the refusal') "listed line lost: $index"
        Assert ($index -notmatch 'never_undo_with_git') "duplicate listed: $index"
        $wide = Invoke-Memory 'index' @{ Folder = $typeDir }
        Assert ($wide.Code -eq 0) "type folder index exit $($wide.Code): $($wide.Out)"
    }

    Test-Case '5. audit lists only the adopter with an empty memory folder and more than 5 recent sessions' {
        $repos = @{ busy = 6; quiet = 5; noted = 6; stranger = 6; stale = 6 }
        foreach ($key in $repos.Keys) {
            $repo = Join-Path $scratch "repos/$key"
            $null = New-Item -ItemType Directory -Path (Join-Path $repo '.git') -Force
            if ($key -ne 'stranger') { Write-Utf8 (Join-Path $repo '.sza-canon.json') '{"role":"product"}' }
            $folder = Join-Path $claudeHome "projects/p--$key"
            $line = @{ type = 'user'; cwd = $repo } | ConvertTo-Json -Compress
            foreach ($i in 1..$repos[$key]) {
                $transcript = Join-Path $folder "s$i.jsonl"
                Write-Utf8 $transcript "{`"type`":`"mode`"}`n$line`n"
                if ($key -eq 'stale') { [IO.File]::SetLastWriteTime($transcript, (Get-Date).AddDays(-8)) }
            }
        }
        Write-Note (Join-Path $claudeHome 'projects/p--noted/memory/state/s.md') 's' 'A state note counts.'
        $r = Invoke-Memory 'audit' @{ Json = $true }
        Assert ($r.Code -eq 0) "exit $($r.Code): $($r.Out)"
        $found = @(($r.Out | ConvertFrom-Json).EmptyAdopters)
        Assert ($found.Count -eq 1) "expected one repo, got: $($found | ConvertTo-Json -Compress)"
        Assert ($found[0].Repo -match 'busy$' -and $found[0].Sessions -eq 6) ($found[0] | ConvertTo-Json -Compress)
    }
}
finally {
    if ($null -eq $origClaudeDir) { Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue } else { $env:CLAUDE_CONFIG_DIR = $origClaudeDir }
    if ($null -eq $origMemRoot) { Remove-Item Env:SZA_MEMORY_ROOT -ErrorAction SilentlyContinue } else { $env:SZA_MEMORY_ROOT = $origMemRoot }
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($script:failed -gt 0) {
    Write-Host "memory-duplicate.tests: FAILED ($($script:failed) failed, $($script:passed) passed)" -ForegroundColor Red
    exit 1
}
Write-Host "memory-duplicate.tests: OK ($($script:passed) cases)" -ForegroundColor Green
exit 0
