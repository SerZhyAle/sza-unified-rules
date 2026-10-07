#requires -Version 7.0
<#
.SYNOPSIS
    Day 0 of a project's task flow in one call: the stores, the plan files, the ticket template, the
    profile and an R0 launcher rendered from that profile.

.DESCRIPTION
    A project that starts from nothing needs, before its first ticket, the directories the ticket tool
    writes into, the three plan files, a ticket template the gates can read, and a runner. This creates
    exactly those and nothing else, every path read from the project profile so a project that renamed a
    directory gets the renamed one. It never overwrites: a file that already exists is reported as
    `exists` and left alone, and `-Force` is the explicit way to replace the generated ones. It is safe
    to run twice.

    What it writes, relative to -Root:
      .sza-profile.json          only when absent, and minimal: a key nothing reads goes stale unseen
      the specs directory        and its archive directory, and the temp directory
      the ledger, its archive    empty files, so the first read finds a store and not a path error
      and the burned-ids list
      the three plan files       queue (owner order), ready (finished), done (shipped), each a stub the
                                 plan tool accepts
      <specs>/TICKET_TEMPLATE.md the template capture-draft.ps1 fills; carries the approval-gate section
      the R0 launcher            -RunnerPath, default r0.ps1 in the project root; standalone, it needs
                                 neither the harness nor the profile at run time

    It does not create tickets, install the agent, write a pipeline command or touch .gitignore: the
    temp directory holds run journals and leases and should be ignored, which is printed as a hint.

.PARAMETER Root
    The project root. Must exist. Defaults to the current directory.

.PARAMETER ProjectName
    Written to a new profile. Defaults to the root directory's name.

.PARAMETER Prompt
    What R0 tells each child, `{id}` standing for the ticket id. The default points the agent at the
    lifecycle skill; a project that already has a pipeline command passes it here, for example
    `/spec-all {id}`.

.PARAMETER PermissionMode
    The permission mode R0 starts each child with. The default matches the harness's own queue runner.
    It lets an unattended child edit and run anything in the project, so decide it deliberately.

.PARAMETER RunnerPath
    Where the launcher goes, project-relative. Defaults to r0.ps1.

.PARAMETER Force
    Replace the generated files that already exist (the plan files, the template, the launcher). The
    profile and the ledger files are never replaced.

.PARAMETER Help
    Print this help.

.EXAMPLE
    pwsh -NoProfile -File <harness>/scaffold/init-task-flow.ps1 -Root . -WhatIf
    pwsh -NoProfile -File <harness>/scaffold/init-task-flow.ps1 -Root .

Exit codes: 0 done (every line printed is `created`, `exists` or `replaced`); 1 a write failed;
2 the call was wrong (root missing, bad runner path, a profile that does not parse).
#>
[CmdletBinding(SupportsShouldProcess, PositionalBinding = $false)]
param(
    [string] $Root = (Get-Location).Path,
    [string] $ProjectName,
    [string] $Prompt = 'Work ticket {id} through ONE step of the task lifecycle, using the spec-to-audit skill: read the ticket, advance it by exactly one status transition recorded through the harness update script, run the command that proves the step, and stop. Do not start another ticket. If the ticket cannot move, set the matching Block status with a statusNote naming what is missing.',
    [ValidateSet('acceptEdits', 'auto', 'bypassPermissions', 'manual', 'dontAsk', 'plan')]
    [string] $PermissionMode = 'bypassPermissions',
    [string] $RunnerPath = 'r0.ps1',
    [switch] $Force,
    [switch] $Help
)

if ($Help) {
    Get-Help -Name $PSCommandPath -Detailed | Out-String -Width 120 | Write-Host
    exit 0
}

trap {
    Write-Host "init-task-flow: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    Write-Host "init-task-flow: root '$Root' does not exist - create the project directory first." -ForegroundColor Red
    exit 2
}
$Root = (Resolve-Path -LiteralPath $Root).Path
if ([IO.Path]::IsPathRooted($RunnerPath) -or $RunnerPath -match '(^|[\\/])\.\.([\\/]|$)') {
    Write-Host "init-task-flow: -RunnerPath must stay inside the project (got '$RunnerPath')." -ForegroundColor Red
    exit 2
}

# The profile first: every path below comes from it, and a project with none gets the minimal one.
$profilePath = Join-Path $Root '.sza-profile.json'
$lines = [System.Collections.Generic.List[string]]::new()
function Note([string] $State, [string] $What) {
    # Under -WhatIf nothing is written, so a line must not say it was.
    if ($WhatIfPreference -and $State -ne 'exists') { $State = "would $State" }
    $lines.Add(('{0,-14} {1}' -f $State, $What))
}
function Write-Utf8([string] $Path, [string] $Text) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
function Use-Directory([string] $Path) {
    $rel = [IO.Path]::GetRelativePath($Root, $Path).Replace('\', '/')
    if (Test-Path -LiteralPath $Path -PathType Container) { Note 'exists' "$rel/"; return }
    if ($PSCmdlet.ShouldProcess($Path, 'create directory')) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
    Note 'created' "$rel/"
}
function Use-File([string] $Path, [string] $Text, [switch] $Replaceable) {
    $rel = [IO.Path]::GetRelativePath($Root, $Path).Replace('\', '/')
    $present = Test-Path -LiteralPath $Path -PathType Leaf
    if ($present -and -not ($Replaceable -and $Force)) { Note 'exists' $rel; return }
    if ($PSCmdlet.ShouldProcess($Path, 'write file')) { Write-Utf8 $Path $Text }
    Note $(if ($present) { 'replaced' } else { 'created' }) $rel
}
function ConvertTo-Literal([string] $Value) { return "'" + $Value.Replace("'", "''") + "'" }

if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
    if (-not $ProjectName) { $ProjectName = Split-Path -Leaf $Root }
    $minimal = [ordered]@{ version = '1'; projectName = $ProjectName } | ConvertTo-Json
    if ($PSCmdlet.ShouldProcess($profilePath, 'write file')) { Write-Utf8 $profilePath ($minimal + "`n") }
    Note 'created' '.sza-profile.json'
} else {
    Note 'exists' '.sza-profile.json'
}

$env:SZA_PROJECT_ROOT = $Root
. (Join-Path $PSScriptRoot '..\_profile.ps1')
try { $null = Get-SzaProfile } catch {
    Write-Host "init-task-flow: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
if ($WhatIfPreference -and -not (Test-Path -LiteralPath $profilePath)) {
    Write-Host 'init-task-flow: -WhatIf with no profile on disk prints the plan from the defaults; run it for real to create the profile.' -ForegroundColor Yellow
}

# --- the stores
$specsDir   = Get-SzaPath 'specsDir'
$ledger     = Get-SzaPath 'journal'
$ledgerArch = Get-SzaPath 'journalArchive'
$burned     = Get-SzaPath 'burnedIds'
Use-Directory $specsDir
Use-Directory (Get-SzaPath 'specArchiveDir')
Use-Directory (Get-SzaPath 'tempDir')
foreach ($f in @($ledger, $ledgerArch, $burned)) { Use-File $f '' }

# --- the plan files: the shape the plan tool reads (a marker, a column header, a package heading)
$queuePath = Get-SzaPath 'releaseQueue'
$queueRel  = Get-SzaPath 'releaseQueue' -Relative
$queueText = @"
# Release Queue
current-next-release: 1

The owner orders the work here and only here. A bare number opens a package, `--` is work not yet
scheduled, a row is the ticket (id and slug), the time it last changed and its status. Within a package
the runner takes rows in line order. The plan tool adds a row for every new ticket, at the end, and keeps
the status and the time current; it never reorders. Putting the work in the order you want is moving lines.

ticket                                                         changed         status
1

"@
$readyText = @"
# Release Content (ready)

Finished as far as its package is concerned. Written by the plan tool, sorted by nobody.

ticket                                                         changed         status

1

"@
$doneText = @"
# Shipped Release Packages

What actually went out, newest first. Each block is one release package, moved here verbatim from the
queue file by the ship step. This file is written by that step - do not hand-edit it.

"@
Use-File $queuePath $queueText -Replaceable
Use-File (Get-SzaPath 'releaseReady') $readyText -Replaceable
Use-File (Get-SzaPath 'releaseQueueDone') $doneText -Replaceable

# --- the ticket template
$templatesDir = Join-Path $PSScriptRoot 'templates'
Use-File (Join-Path $specsDir 'TICKET_TEMPLATE.md') ([IO.File]::ReadAllText((Join-Path $templatesDir 'ticket-template.md'))) -Replaceable

# --- the R0 launcher, rendered from the profile
$statusVocabulary = @(Get-SzaProfileValue 'grammar.statusVocabulary')
$workStatuses = @($statusVocabulary | Where-Object { $_ -notlike 'Block*' -and $_ -notin @('Verified', 'Archived') })
$runnerFull = Join-Path $Root $RunnerPath
$rootRelative = [IO.Path]::GetRelativePath((Split-Path -Parent $runnerFull), $Root).Replace('\', '/')
$render = [ordered]@{
    rootRelative   = ConvertTo-Literal $rootRelative
    journal        = ConvertTo-Literal (Get-SzaPath 'journal' -Relative)
    queue          = ConvertTo-Literal $queueRel
    runsDir        = ConvertTo-Literal (Get-SzaPath 'queueRunsDir' -Relative)
    stopFile       = ConvertTo-Literal (Get-SzaPath 'queueStopFile' -Relative)
    prompt         = ConvertTo-Literal $Prompt
    permissionMode = ConvertTo-Literal $PermissionMode
    idRegex        = ConvertTo-Literal (Get-SzaTicketIdFragment)
    workStatuses   = ($workStatuses | ForEach-Object { ConvertTo-Literal $_ }) -join ', '
    clearOnStart   = ConvertTo-Literal (Get-SzaPath 'leasesDir' -Relative)
}
$launcher = [IO.File]::ReadAllText((Join-Path $templatesDir 'r0-runner.ps1.tpl'))
foreach ($k in $render.Keys) { $launcher = $launcher.Replace("{{$k}}", $render[$k]) }
if ($launcher -match '\{\{\w+\}\}') { throw "the launcher template has an unfilled placeholder: $($Matches[0])" }
Use-File $runnerFull $launcher -Replaceable

$lines | ForEach-Object { Write-Host $_ }
$runnerRel = [IO.Path]::GetRelativePath($Root, $runnerFull).Replace('\', '/')
$tempRel = Get-SzaPath 'tempDir' -Relative
Write-Host ''
Write-Host 'Next:'
Write-Host "  1. add '$tempRel/' to .gitignore - it holds run journals and leases, which are not source."
Write-Host ('  2. create tickets, one at a time: ' + (Get-SzaInvocation 'spec_catalog/capture-draft.ps1' '-Slug <kebab-slug> -Text "<the owner''s words>"'))
Write-Host ('  3. check the ledger:              ' + (Get-SzaInvocation 'spec_catalog/validate.ps1'))
Write-Host "  4. read the order R0 would use:    pwsh -NoProfile -File ./$runnerRel -DryRun"
Write-Host "  5. run ONE ticket attended:        pwsh -NoProfile -File ./$runnerRel -MaxTickets 1"
exit 0
