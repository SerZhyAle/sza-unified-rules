#requires -Version 7.0
<#
.SYNOPSIS
    Create a Draft ticket in one call: the ledger row and its spec file, with the owner's words kept
    byte for byte.

.DESCRIPTION
    insert.ps1 -Slug allocates the id and writes the ledger row, and stops there: the spec file that
    the validator and the next-ticket ranking read does not exist until something writes it, and a
    ledger row without its file is a malformed ticket. This is the missing half - it calls insert.ps1
    (the id is allocated inside the catalog lock, so two concurrent captures cannot be handed the same
    id) and then writes <specs>/<id>_<slug>.md from the project's ticket template.

    The text lands exactly as typed: it is substituted last and with String.Replace, so a `$`, a
    `{{ID}}` token or a regex metacharacter inside it is written as it was given. The file is UTF-8
    without a BOM.

    The template is <specs>/TICKET_TEMPLATE.md, written once by scaffold/init-task-flow.ps1 and then
    owned by the project. Tokens: {{ID}}, {{SLUG}}, {{NAME}}, {{DATE}}, {{TEXT}}.

    If the row was written and the file could not be, the row is left in place and named in the error:
    `delete.ps1 -Id <id> -Confirm` retires it, or the file can be written by hand. Nothing is removed
    silently.

.PARAMETER Slug
    Kebab-case ticket name, [a-z0-9][a-z0-9_-]*, not starting with `spec_`.

.PARAMETER Text
    The owner's text. Exactly one of -Text and -TextFile.

.PARAMETER TextFile
    UTF-8 file holding the owner's text - the safe form for multi-line text or quotes.

.PARAMETER Name
    The ledger name. Defaults to the slug. An active ticket with the same name is refused by the ledger.

.PARAMETER Priority
    0..100, default 50. Order inside the queue file wins over priority; priority orders the rest.

.PARAMETER Tier
    A non-negative integer written to the record; omitted when not given.

.PARAMETER DedupQuery
    A symptom searched in the catalog first, archive included. Up to five hits print as `dedup:` lines
    with their status. A hit that is still open only prints, and the capture goes on: whether it is the
    same ticket is the caller's call. A hit in a CLOSED status stops the capture with exit 3, because the
    defect behind the symptom is already dealt with. The closed set is the profile's
    `grammar.closedStatuses` when it declares one, else Verified and Archived. With -WhatIf nothing is
    created, so the caller can read the hits and decide.

.PARAMETER AllowClosedDuplicate
    Capture anyway after a closed hit - the old defect really did come back, and the new ticket is a
    report rather than a duplicate.

.PARAMETER Help
    Print this help.

.EXAMPLE
    pwsh -NoProfile -File capture-draft.ps1 -Slug login-crash -Text "The app closes when I tap Sign in."
    pwsh -NoProfile -File capture-draft.ps1 -Slug export-csv -TextFile request.txt -Priority 70 -DedupQuery export

Exit codes: 0 the ticket exists (the id is the last line printed); 1 the catalog refused the insert or the
spec file could not be written; 2 bad invocation - slug, text, or the template is missing; 3 refused - the
dedup query hit a closed ticket and -AllowClosedDuplicate was not given.
#>
[CmdletBinding(SupportsShouldProcess, PositionalBinding = $false)]
param(
    [string] $Slug = '',
    [string] $Text,
    [string] $TextFile = '',
    [string] $Name = '',
    [ValidateRange(0, 100)]
    [int]    $Priority = 50,
    [int]    $Tier = -1,
    [string] $DedupQuery = '',
    [switch] $AllowClosedDuplicate,
    [switch] $Help
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')

if ($Help) {
    Show-SzaHelp $PSCommandPath
    exit $LASTEXITCODE
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Stop-BadInvocation([string] $Reason) {
    Write-Host "capture-draft: $Reason" -ForegroundColor Red
    exit 2
}

# Case-sensitive on purpose: -notmatch is case-insensitive in PowerShell, so [a-z] would let `Bad_Slug` through.
if ($Slug -cnotmatch '^[a-z0-9][a-z0-9_-]*$' -or $Slug -match '^spec_') {
    Stop-BadInvocation "invalid -Slug '$Slug' - lowercase [a-z0-9_-], starting alphanumeric, not starting with 'spec_'"
}
$hasText = $PSBoundParameters.ContainsKey('Text')
if ($hasText -eq [bool] $TextFile) { Stop-BadInvocation 'give exactly one of -Text and -TextFile' }
if ($TextFile) {
    if (-not (Test-Path -LiteralPath $TextFile -PathType Leaf)) { Stop-BadInvocation "text file '$TextFile' does not exist" }
    $Text = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $TextFile).Path, [Text.Encoding]::UTF8)
}
if ([string]::IsNullOrWhiteSpace($Text)) { Stop-BadInvocation 'the text is empty - a ticket with no words has nothing to be worked from' }
if (-not $Name) { $Name = $Slug }

$root = Get-SzaProjectRoot
$env:SZA_PROJECT_ROOT = $root                                # the children resolve the same root
$templatePath = Join-Path (Get-SzaPath 'specsDir') 'TICKET_TEMPLATE.md'
if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
    Stop-BadInvocation "no ticket template at $templatePath - run scaffold/init-task-flow.ps1 first"
}
$template = [IO.File]::ReadAllText($templatePath)
$pwshExe = (Get-Process -Id $PID).Path

if ($DedupQuery) {
    $raw = (& $pwshExe -NoProfile -File (Join-Path $PSScriptRoot 'search.ps1') -Query $DedupQuery -IncludeArchived -Format json | Out-String).Trim()
    $found = if ($raw) { @($raw | ConvertFrom-Json) } else { @() }
    foreach ($hit in $found | Select-Object -First 5) { Write-Host ("dedup: {0}  {1,-12} {2}" -f $hit.id, $hit.status, $hit.name) }
    if ($found.Count -eq 0) { Write-Host "dedup: no hit for '$DedupQuery'" }
    # A closed hit means the symptom was already dealt with; the profile may name its own closed set.
    $grammar = Get-SzaProfileValue 'grammar'
    $closedSet = if (Test-SzaHasProperty -Object $grammar -Name 'closedStatuses') { @($grammar.closedStatuses) } else { @('Verified', 'Archived') }
    $closed = @($found | Where-Object { $closedSet -contains $_.status })
    if ($closed.Count -gt 0 -and -not $AllowClosedDuplicate) {
        Write-Host ("capture-draft: {0} is already {1} - the defect behind this symptom is dealt with. Pass -AllowClosedDuplicate if it is a genuine regression." -f $closed[0].id, $closed[0].status) -ForegroundColor Yellow
        exit 3
    }
}

if (-not $PSCmdlet.ShouldProcess("ticket '$Slug'", 'create')) { exit 0 }

$insertArgs = @('-Name', $Name, '-Slug', $Slug, '-Priority', "$Priority")
if ($Tier -ge 0) { $insertArgs += @('-Tier', "$Tier") }
$out = & $pwshExe -NoProfile -File (Join-Path $PSScriptRoot 'insert.ps1') @insertArgs 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host ($out | Out-String).TrimEnd() -ForegroundColor Red
    Write-Host 'capture-draft: the catalog refused the insert; nothing was created.' -ForegroundColor Red
    exit 1
}
$idPattern = Get-SzaProfileValue 'grammar.ticketIdPattern'
$id = @($out | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match $idPattern }) | Select-Object -Last 1
if (-not $id) {
    Write-Host "capture-draft: insert.ps1 exited 0 but printed no ticket id:`n$($out | Out-String)" -ForegroundColor Red
    exit 1
}

$fileRel = ([string](Get-SzaProfileValue 'grammar.specFileTemplate')) -f $id, $Slug
$filePath = Join-Path $root $fileRel
try {
    if (Test-Path -LiteralPath $filePath) { throw "the spec file already exists: $filePath" }
    $body = $template.Replace('{{ID}}', $id).Replace('{{SLUG}}', $Slug).Replace('{{NAME}}', $Name).Replace('{{DATE}}', (Get-Date -Format 'yyyy-MM-dd'))
    $body = $body.Replace('{{TEXT}}', $Text)
    [IO.File]::WriteAllText($filePath, $body, [Text.UTF8Encoding]::new($false))
} catch {
    Write-Host "capture-draft: ledger row $id was written but its spec file was not: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "capture-draft: write $fileRel by hand, or retire the row with delete.ps1 -Id $id -Confirm." -ForegroundColor Red
    exit 1
}
Write-Host "capture-draft: $fileRel"
Write-Output $id
exit 0
