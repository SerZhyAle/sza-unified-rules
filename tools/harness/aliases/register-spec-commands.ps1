#requires -Version 7.0
<#
.SYNOPSIS
    Register the spec commands (/spec-quiz /sq /spec-draft /sd /spec-next /sn /spec-all /sa) in a project's
    .claude/commands/ as thin forwarders to the sza plugin skills.

.DESCRIPTION
    A plugin skill is addressed as /sza:<name>; whether the bare /<name> resolves to it is not something the plugin
    controls. A project's own .claude/commands/<name>.md is addressed by its file name, so the bare and the short
    names work in that project - the way FastMediaSorter_mob_v2 has always had them, except that its commands are the
    full pipelines and these are forwarders: each file tells the model to invoke the plugin skill and pass the
    arguments through, so nothing is duplicated and a canon fix reaches every project with the plugin update.

    Eight files per project: the four canonical names and their short forms, all forwarding to the canonical skill
    (sza:spec-quiz, sza:spec-draft, sza:spec-next, sza:spec-all).

    A generated file carries `forwards_to:` in its metadata. That marker is what makes a re-run safe: a file with it is
    rewritten when it differs from the table; a file without it is hand-written (FastMediaSorter_mob_v2's own
    commands) and is never touched - the result line says `kept`. The existing alias generator (generate-command-
    aliases.ps1) identifies its files by `alias_of:` and never sees these.

    Targets:
      -Project k,..   registered keys (repos.json) or folders
      -All            every enabled project in the portfolio registry, minus -Skip
      (none)          the project holding the current folder (nearest .sza-profile.json upward)

    Writes only the eight files named above, only inside the project's commands folder (paths.commandsDir of its
    profile, .claude/commands by default). -Check writes nothing and exits 1
    when a file is missing or stale.

    Text output, one line per project, then:
        register-spec-commands: <n> project(s), wrote <w>, unchanged <u>, kept <k> hand-written[, drift <d>]

    Exit codes: 0 done (or -Check found nothing to do); 1 -Check found a missing or stale file, or a target folder is
    missing; 2 bad invocation (an unknown key, no project at or above the current folder).
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string[]] $Project = @(),
    [switch] $All,
    [string[]] $Skip = @(),
    [switch] $Check,
    [switch] $Help
)

if ($Help) {
    Get-Help -Name $PSCommandPath -Detailed | Out-String -Width 120 | Write-Host
    exit 0
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# `pwsh -File ... -Skip a,b` hands over the one string 'a,b': split here so both spellings work.
$Project = @($Project | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$Skip = @($Skip | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

. (Join-Path $PSScriptRoot '..\portfolio\lib\registry.ps1')
. (Join-Path $PSScriptRoot '..\_profile.ps1')

# The commands folder is the target project's own `paths.commandsDir` (default from the profile library), not a literal
# here. The library resolves one project per process, so its two caches are cleared before each target.
function Get-CommandsDir([string] $ProjectPath) {
    $saved = $env:SZA_PROJECT_ROOT
    try {
        $env:SZA_PROJECT_ROOT = $ProjectPath
        $Script:SzaProjectRootCache = $null
        $Script:SzaProfileCache = $null
        $relative = Get-SzaPath 'commandsDir' -Relative
    }
    catch { $relative = [string]$Script:SzaProfileDefaults.paths.commandsDir }
    finally { $env:SZA_PROJECT_ROOT = $saved }
    return (Join-Path $ProjectPath $relative).Replace('/', [IO.Path]::DirectorySeparatorChar)
}

# name, the skill it forwards to, the menu description, the argument hint.
$table = @(
    @{ Name = 'spec-quiz';  Skill = 'sza:spec-quiz';  Hint = '[<id> | <key>:<id> | <key> | --all] [--dry]'
       Description = 'Clear the tickets that wait for the owner''s answers (BlockQuestions): research, ask as multiple choice, write the answers into the spec, restore the status. Plugin skill. Short form: /sq' }
    @{ Name = 'sq';         Skill = 'sza:spec-quiz';  Hint = 'same arguments as /spec-quiz'
       Description = 'Alias -> /spec-quiz' }
    @{ Name = 'spec-draft'; Skill = 'sza:spec-draft'; Hint = '[<project-key>] <task description>'
       Description = 'Capture a task or a problem as a Draft ticket in a project''s queue, the owner''s words verbatim. Plugin skill. Short form: /sd' }
    @{ Name = 'sd';         Skill = 'sza:spec-draft'; Hint = 'same arguments as /spec-draft'
       Description = 'Alias -> /spec-draft' }
    @{ Name = 'spec-next';  Skill = 'sza:spec-next';  Hint = '(no argument)'
       Description = 'Take the first eligible ticket of this project''s queue, claim it and run it end to end. Plugin skill. Short form: /sn' }
    @{ Name = 'sn';         Skill = 'sza:spec-next';  Hint = 'same arguments as /spec-next'
       Description = 'Alias -> /spec-next' }
    @{ Name = 'spec-all';   Skill = 'sza:spec-all';   Hint = '<Sxxxx | slug | idea text>'
       Description = 'Take one ticket from its current status to the audit: lease, drift, spec, plan, implement, evidence, self-audit. Plugin skill. Short form: /sa' }
    @{ Name = 'sa';         Skill = 'sza:spec-all';   Hint = 'same arguments as /spec-all'
       Description = 'Alias -> /spec-all' }
)

function New-ForwarderBody([hashtable] $Row) {
    # Single-quoted here-string: $ARGUMENTS must reach the file literally.
    $template = @'
---
description: "{DESCRIPTION}"
argument-hint: "{HINT}"
disable-model-invocation: true
metadata:
  forwards_to: {SKILL}
  generated_by: sza aliases/register-spec-commands.ps1
---

`/{NAME}` runs the sza plugin skill `{SKILL}` in this project and carries no behaviour of its own.

Invoke the Skill tool with skill `{SKILL}`, passing `$ARGUMENTS` as its args, and follow that skill exactly. Do
nothing before that call and do not restate this file - the operator typed a shortcut, not a new instruction.

If the Skill tool says `{SKILL}` does not exist, the sza plugin is not installed or is older than this command: say so
in one line and stop. `claude plugin update sza@sza-unified-rules` is the owner's step.
'@
    $text = $template.Replace('{DESCRIPTION}', $Row.Description).Replace('{HINT}', $Row.Hint).Replace('{SKILL}', $Row.Skill).Replace('{NAME}', $Row.Name)
    return ($text -replace "`r`n", "`n")
}

function Stop-Register([int] $Code, [string] $Message) {
    [Console]::Error.WriteLine("register-spec-commands: $Message")
    exit $Code
}

function Find-ProjectUpward([string] $Start) {
    $dir = [IO.DirectoryInfo]::new($Start)
    while ($null -ne $dir) {
        if ([IO.File]::Exists((Join-Path $dir.FullName '.sza-profile.json'))) { return $dir.FullName }
        $dir = $dir.Parent
    }
    return $null
}

# ---- targets: (key, path) pairs ----
$registry = @()
try {
    $read = Read-PqRegistry
    if ($read.ok) { $registry = @($read.registry.repos) }
}
catch { $registry = @() }

$targets = [System.Collections.Generic.List[object]]::new()
$skipKeys = @($Skip | ForEach-Object { $_.ToLowerInvariant() })

if ($All) {
    if ($registry.Count -eq 0) { Stop-Register 2 'no portfolio registry to read for -All.' }
    foreach ($r in $registry) {
        if ($r.PSObject.Properties['enabled'] -and -not $r.enabled) { continue }
        if ($skipKeys -contains ([string]$r.key).ToLowerInvariant()) { continue }
        $targets.Add([pscustomobject]@{ Key = [string]$r.key; Path = [string]$r.path })
    }
}
foreach ($p in $Project) {
    $hit = $registry | Where-Object { [string]$_.key -eq $p } | Select-Object -First 1
    if ($hit) { $targets.Add([pscustomobject]@{ Key = [string]$hit.key; Path = [string]$hit.path }) }
    elseif (Test-Path -LiteralPath $p -PathType Container) { $targets.Add([pscustomobject]@{ Key = (Split-Path -Leaf $p); Path = (Resolve-Path -LiteralPath $p).Path }) }
    else { Stop-Register 2 "unknown project '$p' (not a registered key, not a folder)." }
}
if ($targets.Count -eq 0 -and -not $All) {
    $here = Find-ProjectUpward (Get-Location).Path
    if (-not $here) { Stop-Register 2 'no project at or above the current folder; pass -Project or -All.' }
    $targets.Add([pscustomobject]@{ Key = (Split-Path -Leaf $here); Path = $here })
}

$utf8NoBom = [Text.UTF8Encoding]::new($false)
$totalWrote = 0; $totalSame = 0; $totalKept = 0; $totalDrift = 0; $missing = 0

foreach ($t in $targets) {
    if (-not (Test-Path -LiteralPath $t.Path -PathType Container)) {
        Write-Host ("{0,-14} MISSING folder {1}" -f $t.Key, $t.Path)
        $missing++
        continue
    }
    $dir = Get-CommandsDir $t.Path
    $wrote = 0; $same = 0; $kept = @(); $drift = @()
    foreach ($row in $table) {
        $file = Join-Path $dir "$($row.Name).md"
        $body = New-ForwarderBody $row
        if ([IO.File]::Exists($file)) {
            $current = [IO.File]::ReadAllText($file, $utf8NoBom)
            $head = @($current -split "`n" | Select-Object -First 14)
            if (-not ($head -match '^\s*forwards_to:\s*\S')) { $kept += $row.Name; continue }
            if (($current -replace "`r`n", "`n") -eq $body) { $same++; continue }
        }
        if ($Check) { $drift += $row.Name; continue }
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [IO.File]::WriteAllText($file, $body, $utf8NoBom)
        $wrote++
    }
    $line = "{0,-14} wrote {1}, unchanged {2}" -f $t.Key, $wrote, $same
    if ($kept.Count) { $line += ", kept hand-written: $($kept -join ' ')" }
    if ($drift.Count) { $line += ", DRIFT: $($drift -join ' ')" }
    Write-Host $line
    $totalWrote += $wrote; $totalSame += $same; $totalKept += $kept.Count; $totalDrift += $drift.Count
}

$summary = "register-spec-commands: $($targets.Count) project(s), wrote $totalWrote, unchanged $totalSame, kept $totalKept hand-written"
if ($Check) { $summary += ", drift $totalDrift" }
Write-Host $summary
exit $(if ($totalDrift -gt 0 -or $missing -gt 0) { 1 } else { 0 })
