#requires -Version 7.0
<#
.SYNOPSIS
    Capture a task into any project as a Draft ticket and report whether the portfolio queue (pq) will work it.

.DESCRIPTION
    The mechanical half of the spec-draft skill, in one call: resolve the project, capture the ticket with the
    owner's words kept byte for byte, then look - read only - at what pq will do with it. The agent chooses the
    slug, the level and the priority; nothing else is left to hand-run.

    Project: -Project is a key from `pq list`, or a folder. Left out, the project is the nearest folder above the
    current one that holds a .sza-profile.json. A project needs a task flow (the profile and its ledger); without
    one the call stops and names task-flow-init.

    Capture: a project's own scripts/utils/capture-draft.ps1 wins when it has one (it owns its templates and
    attachments - FastMediaSorter_mob_v2 does); otherwise the canon's spec_catalog/capture-draft.ps1, which needs
    the project's PLAN/TICKET_TEMPLATE.md. Both write the ledger row, the spec file and the row in the project's
    ticket queue (PLAN/RELEASE_QUEUE.md): a new ticket lands at the END of the current release package, because
    the order of that file is the owner's plan and no tool reorders it.

    Priority, when -Priority is left out: 95 for a hotfix- slug, 90 for bugfix-, 50 otherwise. It orders the
    ledger; the order of the ticket queue file wins over it.

    The portfolio projection is refreshed after capture, including for a project-owned capture tool. Visibility:
      - registered? enabled? on hold in the registry or under `hold` in PORTFOLIO_QUEUE.md? (pq dry-run)
      - the position of the new ticket in the project's own ranking (the picker pq itself asks), and how many
        tickets run before it. pq works a project's head first, so a ticket at position 38 waits for 37.
    A hold, a disabled project or a missing registration is reported as it is. It is the owner's decision and this
    script does not undo it.

    -Pin puts the new ticket at the top of the first numbered package of PORTFOLIO_QUEUE.md (pq pin). It is
    refused for a project pq will not dispatch.

    The last line printed is the machine-readable result:
        drafted <key>:<id> file=<path> priority=<n> pq=<verdict> position=<p>/<total>
    verdict: dispatchable, held-by-queue, held, disabled, unregistered, not-offered, or the picker's own reason.

.PARAMETER Project
    A registered key or a folder. Default: the project holding the current folder.

.PARAMETER Slug
    Kebab-case ticket name, [a-z0-9][a-z0-9_-]*, not starting with `spec_`. A bug takes `bugfix-`, an urgent
    one `hotfix-`.

.PARAMETER TextFile
    UTF-8 file holding the owner's text, written exactly as the owner gave it. The only way in: a command line
    mangles quotes, newlines and encodings.

.PARAMETER Priority
    0..100. Default by slug prefix, see above.

.PARAMETER Complexity
    `<light|medium|hard> - <one-line reason>`. Omitted: `medium - not assessed at capture`.

.PARAMETER DedupQuery
    A symptom searched in the catalog first. A hit on a closed ticket stops the capture with exit 3.

.PARAMETER AllowClosedDuplicate
    Capture anyway after a closed hit - the defect really did come back.

.PARAMETER Attach
    Semicolon-separated files to attach. Only a project whose own capture script takes -Attach accepts them;
    the canon's does not, and the call stops before creating anything.

.PARAMETER Pin
    Pin the new ticket to the top of PORTFOLIO_QUEUE.md after capture.

.PARAMETER Help
    Print this help.

.EXAMPLE
    pwsh -NoProfile -File spec-draft.ps1 -Project fms-a -Slug bugfix-grid-crash -TextFile C:\tmp\owner.txt -DedupQuery "grid crash"

.EXAMPLE
    pwsh -NoProfile -File spec-draft.ps1 -Slug export-csv -TextFile owner.txt -Complexity "light - one new menu item" -WhatIf

Exit codes: 0 the ticket exists (or -WhatIf finished); 1 the catalog refused or the spec file could not be
written; 2 bad invocation, an unknown project or no task flow; 3 the dedup query hit a closed ticket.
#>
[CmdletBinding(SupportsShouldProcess, PositionalBinding = $false)]
param(
    [string] $Project = '',
    [string] $Slug = '',
    [string] $TextFile = '',
    [ValidateRange(-1, 100)]
    [int]    $Priority = -1,
    [string] $Complexity = '',
    [string] $DedupQuery = '',
    [switch] $AllowClosedDuplicate,
    [string] $Attach = '',
    [switch] $Pin,
    [switch] $Help
)

if ($Help) {
    Get-Help -Name $PSCommandPath -Detailed | Out-String -Width 120 | Write-Host
    exit 0
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pq = Join-Path $PSScriptRoot 'pq.ps1'
$harness = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pwshExe = (Get-Process -Id $PID).Path
. (Join-Path $PSScriptRoot 'lib/picker.ps1')

function Stop-Draft([int] $Code, [string] $Message) {
    Write-Host "spec-draft: $Message" -ForegroundColor Red
    exit $Code
}

# Null-safe property read: the registry and the profile leave most keys out, and StrictMode throws on a missing one.
function Get-Prop($Object, [string] $Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

function ConvertTo-PathKey([string] $Path) { return [IO.Path]::GetFullPath($Path).TrimEnd('\', '/').ToLowerInvariant() }

function Invoke-Pq([string[]] $PqArgs) {
    $out = & $pwshExe -NoProfile -File $pq @PqArgs 2>&1
    return [pscustomobject]@{ code = $LASTEXITCODE; text = (($out | ForEach-Object { "$_" }) -join "`n") }
}

# ---- 1. the invocation, checked before anything is created ----
if ($Slug -cnotmatch '^[a-z0-9][a-z0-9_-]*$' -or $Slug -match '^spec_') {
    Stop-Draft 2 "invalid -Slug '$Slug' - lowercase [a-z0-9_-], starting alphanumeric, not starting with 'spec_'"
}
if (-not $TextFile -or -not (Test-Path -LiteralPath $TextFile -PathType Leaf)) {
    Stop-Draft 2 "-TextFile '$TextFile' does not exist - write the owner's words to a UTF-8 file and pass it"
}
$textFull = (Resolve-Path -LiteralPath $TextFile).Path
if ([string]::IsNullOrWhiteSpace([IO.File]::ReadAllText($textFull, [Text.Encoding]::UTF8))) {
    Stop-Draft 2 'the text is empty - a ticket with no words has nothing to be worked from'
}

# ---- 2. the project ----
$repos = @()
$registry = $null
$list = Invoke-Pq @('list', '-Json')
if ($list.code -eq 0) {
    try {
        $registry = ConvertFrom-Json -InputObject $list.text -DateKind String
        $repos = @(Get-Prop $registry 'repos' @())
    }
    catch { $registry = $null; $repos = @() }
}
$keys = if ($repos.Count) { (@($repos | ForEach-Object { [string]$_.key }) -join ', ') } else { 'none registered' }

$rec = $null
$root = $null
if ($Project) {
    $rec = @($repos | Where-Object { [string]$_.key -ieq $Project }) | Select-Object -First 1
    if ($rec) { $root = [string]$rec.path }
    elseif (Test-Path -LiteralPath $Project -PathType Container) { $root = (Resolve-Path -LiteralPath $Project).Path }
    else { Stop-Draft 2 "unknown project '$Project' - neither a registered key nor a folder (registered: $keys)" }
}
else {
    $dir = (Get-Location).Path
    while ($dir) {
        if (Test-Path -LiteralPath (Join-Path $dir '.sza-profile.json') -PathType Leaf) { $root = $dir; break }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    if (-not $root) { Stop-Draft 2 "no project here - no .sza-profile.json at or above $((Get-Location).Path). Pass -Project <key|path> (registered: $keys)" }
}
if (-not (Test-Path -LiteralPath $root -PathType Container)) { Stop-Draft 2 "project folder '$root' does not exist" }
if (-not $rec) {
    $rootKey = ConvertTo-PathKey $root
    $rec = @($repos | Where-Object { (ConvertTo-PathKey ([string]$_.path)) -ceq $rootKey }) | Select-Object -First 1
}

$profileFile = Join-Path $root '.sza-profile.json'
if (-not (Test-Path -LiteralPath $profileFile -PathType Leaf)) {
    Stop-Draft 2 "$root has no .sza-profile.json - its task flow is not set up. Run the task-flow-init skill there first"
}
$profile = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($profileFile)) -DateKind String
$journalRel = [string](Get-Prop (Get-Prop $profile 'paths') 'journal' 'PLAN/spec-catalog.jsonl')
if (-not (Test-Path -LiteralPath (Join-Path $root $journalRel) -PathType Leaf)) {
    Stop-Draft 2 "$root has no ticket ledger at $journalRel - run the task-flow-init skill there first"
}
$grammar = Get-Prop $profile 'grammar'
$idPattern = [string](Get-Prop $grammar 'ticketIdPattern' '^S\d{4}$')
$specTemplate = [string](Get-Prop $grammar 'specFileTemplate' 'PLAN/{0}_{1}.md')

# ---- 3. the capture script ----
$own = Join-Path $root 'scripts/utils/capture-draft.ps1'
$ownScript = Test-Path -LiteralPath $own -PathType Leaf
$captureScript = if ($ownScript) { $own } else { Join-Path $harness 'spec_catalog/capture-draft.ps1' }
if ($Attach) {
    $canAttach = (Get-Command -Name $captureScript -CommandType ExternalScript).Parameters.ContainsKey('Attach')
    if (-not $canAttach) { Stop-Draft 2 'this project has no capture script that takes attachments; put the content in the text, or attach the file by hand after capture' }
}
if ($Priority -lt 0) { $Priority = if ($Slug -like 'hotfix-*') { 95 } elseif ($Slug -like 'bugfix-*') { 90 } else { 50 } }

$capture = @('-NoProfile', '-File', $captureScript, '-Slug', $Slug, '-TextFile', $textFull, '-Priority', "$Priority")
if ($Complexity) { $capture += @('-Complexity', $Complexity) }
if ($DedupQuery) { $capture += @('-DedupQuery', $DedupQuery) }
if ($AllowClosedDuplicate) { $capture += '-AllowClosedDuplicate' }
if ($Attach) { $capture += @('-Attach', $Attach) }
if ($WhatIfPreference) { $capture += '-WhatIf' }

$env:SZA_PROJECT_ROOT = $root
Push-Location -LiteralPath $root
try {
    $out = & $pwshExe @capture 2>&1
    $captureCode = $LASTEXITCODE
}
finally { Pop-Location }
$lines = @($out | ForEach-Object { "$_".TrimEnd() } | Where-Object { $_ })
foreach ($l in $lines) { Write-Host $l }
if ($captureCode -ne 0) { exit $captureCode }
if ($WhatIfPreference) {
    Write-Host "spec-draft: -WhatIf - $(if ($ownScript) { 'the project''s own' } else { 'the canon''s' }) capture ran its dedup report only; nothing was created"
    exit 0
}

$id = $null
for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    $token = ($lines[$i] -split '\s+')[0]
    if ($token -match $idPattern) { $id = $token; break }
}
if (-not $id) { Stop-Draft 1 "the capture exited 0 but printed no ticket id matching $idPattern" }
$fileRel = $specTemplate -f $id, $Slug
$fileShown = if (Test-Path -LiteralPath (Join-Path $root $fileRel) -PathType Leaf) { $fileRel } else { '?' }

# Project-owned capture tools may not use the shared catalog writer. Reconcile their result too.
if ($rec) {
    $sync = Invoke-Pq @('sync', '-Path', $root)
    if ($sync.code -ne 0) { Write-Host "pq: sync failed after capture: $($sync.text.Trim()); repair with pq sync -Path `"$root`"" }
}

# ---- 4. what pq will do with it (read only) ----
$label = if ($rec) { [string]$rec.key } else { Split-Path -Leaf $root }
$verdict = 'unregistered'
$position = 0
$total = 0
$notes = [Collections.Generic.List[string]]::new()
$pinned = $false

if (-not $rec) {
    $notes.Add("pq: NOT registered - $root is not in the portfolio registry, so pq never looks at it. Registering is the owner's call (it picks the permission mode): pwsh -NoProfile -File `"$pq`" register -Path `"$root`" -Enable -PermissionMode <mode>")
}
else {
    $skip = $null
    $dry = Invoke-Pq @('dry-run', '-Json')
    if ($dry.code -eq 0) {
        try {
            $dryDoc = ConvertFrom-Json -InputObject $dry.text -DateKind String
            $skip = @(Get-Prop $dryDoc 'skipped' @()) | Where-Object { [string]$_.repo -ceq $label } | Select-Object -First 1
        }
        catch { $skip = $null }
    }
    else { $notes.Add("pq: dry-run failed (exit $($dry.code)); eligibility of $label could not be read: $($dry.text.Trim())") }

    $reason = if ($skip) { [string]$skip.why } else { '' }
    $verdict = switch ($reason) {
        ''            { 'dispatchable' }
        'occupied'    { 'dispatchable' }
        'heldByQueue' { 'held-by-queue' }
        'hold'        { 'held' }
        'disabled'    { 'disabled' }
        default       { $reason }
    }
    switch ($verdict) {
        'held-by-queue' { $notes.Add("pq: NOT dispatched - $label sits under 'hold' in PORTFOLIO_QUEUE.md. The ticket waits; lifting the hold is the owner's call (pq release $label)") }
        'held'          { $notes.Add("pq: NOT dispatched - $label is on hold in the registry (pq release $label clears it). The ticket waits; that is the owner's call") }
        'disabled'      { $notes.Add("pq: NOT dispatched - $label is registered but not enabled (enabled=false in repos.json). Enabling is the owner's call") }
        'dispatchable'  { if ($reason -ceq 'occupied') { $notes.Add("pq: a worker is in $label right now; the ticket is taken in a later pass") } }
        default         { $notes.Add("pq: NOT dispatched - the rank skips $label ($reason)") }
    }

    $mode = [string](Get-Prop $rec 'permissionMode' ([string](Get-Prop $registry 'permissionMode' '')))
    if (-not $mode) { $notes.Add("pq: warning - $label has no permissionMode (on its record or at the top of repos.json); pq start refuses unattended work there until one is set") }

    # Position in the project's own ranking: the picker pq itself asks, so the figure is the one pq acts on.
    $pick = Invoke-PqPicker -RepoPath $root
    if (-not $pick.ok) {
        $notes.Add("pq: the picker failed for ${label}: $($pick.message)")
        if ($verdict -ceq 'dispatchable') { $verdict = 'picker-failed' }
    }
    else {
        $payload = $pick.payload
        $ranked = @(Get-PqPayloadIds $payload.ranked)
        $total = $ranked.Count
        $at = [array]::IndexOf([string[]]$ranked, $id)
        $head = if ($null -ne $payload.selected) { [string]$payload.selected.id } else { '' }
        if ($at -ge 0) {
            $position = $at + 1
            $ahead = $at
            $note = if ($ahead -eq 0) { "pq: ${label}:${id} is first in its own queue" } else { "pq: ${label}:${id} is #$position of $total in its own queue; $ahead run before it (head: $head), because a new ticket lands at the end of the current package" }
            $notes.Add($note)
        }
        else {
            $why = if ((Get-PqPayloadIds $payload.leased_ids) -ccontains $id) { 'leased' }
            elseif ((Get-PqPayloadIds $payload.excluded_ids) -ccontains $id) { 'excluded' }
            elseif ((Get-PqPayloadIds $payload.malformed) -ccontains $id) { 'malformed' }
            else { Get-PqAutoSkipReason $payload $id }
            if (-not $why) { $why = 'not offered by the project picker' }
            $notes.Add("pq: ${label}:${id} is not ranked in its own queue ($why)")
            if ($verdict -ceq 'dispatchable') { $verdict = 'not-offered' }
        }
    }

    if ($Pin) {
        if ($verdict -ceq 'dispatchable') {
            $pinRun = Invoke-Pq @('pin', "${label}:${id}")
            if ($pinRun.code -eq 0) { $pinned = $true; $notes.Add("pq: pinned - ${label}:${id} is first in the first numbered package of PORTFOLIO_QUEUE.md") }
            else { $notes.Add("pq: pin failed (exit $($pinRun.code)): $($pinRun.text.Trim())") }
        }
        else { $notes.Add("pq: pin refused - pq will not dispatch $label ($verdict); a pin would not be worked, and lifting that is the owner's call") }
    }
    elseif ($Slug -like 'hotfix-*' -and $position -gt 1 -and $verdict -ceq 'dispatchable') {
        $notes.Add("pq: this is a hotfix at #$position - pq pin ${label}:${id} (or re-run with -Pin) puts it first")
    }
}

Write-Host "spec-draft: captured ${label}:${id} ($fileShown), Draft, priority $Priority"
foreach ($n in $notes) { Write-Host $n }
Write-Host ("drafted {0}:{1} file={2} priority={3} pq={4} position={5}/{6}" -f $label, $id, $fileShown, $Priority, $verdict, $position, $total)
exit 0
