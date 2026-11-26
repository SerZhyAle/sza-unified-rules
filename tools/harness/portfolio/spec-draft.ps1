#requires -Version 7.0
<#
.SYNOPSIS
    Capture a task into any project as a Draft ticket and report whether the portfolio queue (pq) will work it.

.DESCRIPTION
    The mechanical half of the spec-draft skill, in one call: resolve the project, capture the ticket with the
    owner's words kept byte for byte, then look - read only - at what pq will do with it. The agent chooses the
    slug, the level and the priority; nothing else is left to hand-run.

    Project: -Project is a key from `pq list`, or a folder. Left out, the project is the nearest folder above the
    current one that holds a .sza-profile.json or a .sza-canon.json.

    Plain capture: a project with no .sza-profile.json has no task flow, and the ticket is still captured - as one
    file, PLAN/<id>_<slug>.md, numbered the way the project already numbers its tickets (the most common
    <prefix><digits>_ among the files of PLAN/, PLAN/DONE and PLAN/archive, one past the highest; none found: S0001).
    The project's PLAN/TICKET_TEMPLATE.md is the form when it has one, else the canon's. Nothing else is created: no
    profile, no ledger, no queue row, because a second numbering scheme inside a project that has its own is worse
    than a ticket pq cannot pick up. The report says so (pq=no-task-flow); setting the flow up (task-flow-init) is
    the owner's call. A project with a profile but no ledger is half set up and is refused (exit 2).

    Capture: a project's own scripts/utils/capture-draft.ps1 wins when it has one (it owns its templates and
    attachments - FastMediaSorter_mob_v2 does); otherwise the canon's spec_catalog/capture-draft.ps1, which
    uses the project's PLAN/TICKET_TEMPLATE.md when it has one, else the canon's scaffold form (S0098 - the
    project keeps its own numbering, grammar and archive either way). Both write the ledger row, the spec file and the row in the project's
    ticket queue (PLAN/RELEASE_QUEUE.md): a new ticket lands at the END of the current release package, because
    the order of that file is the owner's plan and no tool reorders it.

    Priority, when -Priority is left out: 95 for a hotfix- slug, 90 for bugfix-, 50 otherwise. It orders the
    ledger; the order of the ticket queue file wins over it. A plain capture has no ledger to hold it and prints
    `priority=-`.

    The portfolio projection is refreshed after capture, including for a project-owned capture tool. Visibility:
      - registered? enabled? on hold in the registry or under `hold` in PORTFOLIO_QUEUE.md? (pq dry-run)
      - the position of the new ticket in the project's own ranking (the picker pq itself asks), and how many
        tickets run before it. pq works a project's head first, so a ticket at position 38 waits for 37.
    A hold, a disabled project or a missing registration is reported as it is. It is the owner's decision and this
    script does not undo it.

    -Pin puts the new ticket at the top of the first numbered package of PORTFOLIO_QUEUE.md (pq pin). It is
    refused for a project pq will not dispatch. A hotfix- slug is an urgent blocker and implies -Pin, so pq works
    it first (-NoPin leaves it in its place); the newest hotfix is the first of them.

    The last line printed is the machine-readable result:
        drafted <key>:<id> file=<path> priority=<n> pq=<verdict> position=<p>/<total>
    verdict: dispatchable, held-by-queue, held, disabled, unregistered, no-task-flow, not-offered, or the
    picker's own reason.

.PARAMETER Project
    A registered key or a folder. Default: the project holding the current folder.

.PARAMETER Slug
    Kebab-case ticket name, [a-z0-9][a-z0-9_-]*, not starting with `spec_`, not ending in `-` or `_` (a bare
    `foo-` names nothing). A bug takes `bugfix-`, an urgent one `hotfix-`. Left out, or just `bugfix-` / `hotfix-`
    (what the New Specification dialog pre-fills), the name is made from the first words of the text, Cyrillic
    transliterated, and printed; a leading slash command (`/spec-draft ..`) and a registered project key right after
    it are not part of the name. A caller that can write a better name passes it.

.PARAMETER TextFile
    UTF-8 file holding the owner's text, written exactly as the owner gave it. The only way in: a command line
    mangles quotes, newlines and encodings.

.PARAMETER Priority
    0..100. Default by slug prefix, see above.

.PARAMETER Complexity
    `<level> - <one-line reason>`, the level a grade 0-9 (`7 pinned` for the owner's own, TASK-FLOW 0.32) or light,
    medium or hard. Omitted: `medium - not assessed at capture`. A bare level (what the New Specification dialog
    sends) is completed with a reason saying the level was picked at capture.

.PARAMETER DedupQuery
    A symptom searched in the catalog first. A hit on a closed ticket stops the capture with exit 3.

.PARAMETER AllowClosedDuplicate
    Capture anyway after a closed hit - the defect really did come back.

.PARAMETER Attach
    Semicolon-separated files to attach, in every project. Each is copied byte for byte into
    <ticket>/attachments/ beside the spec and linked in section 0 right after the request text; an existing file
    is never overwritten. A missing, unreadable, folder or repeated path stops the call before anything is
    created. A project's own capture script that takes -Attach gets the files itself; one that does not gets them
    linked after its capture. A copy or link failure after the ticket exists exits 1 naming the ticket.

.PARAMETER Pin
    Pin the new ticket to the top of PORTFOLIO_QUEUE.md after capture. Implied by a hotfix- slug.

.PARAMETER NoPin
    Do not pin a hotfix- ticket; it stays at the end of its package.

.PARAMETER QueueTimeoutSeconds
    Overall deadline in seconds for post-capture portfolio preview (default 10). If the check
    times out or fails, reports pq=unknown and refuses pinning.

.PARAMETER Projects
    The campaign form: comma-separated registered keys (no folders). The same slug and text are captured into each,
    in the order given; one `pq sync` and one `pq dry-run` follow the last capture; one `drafted` line is printed per
    ticket (position=0/0 - not computed here) and the last line is `campaign <slug>: <n> drafted, <m> failed`. Exit 1
    when a target was not filed. A campaign never pins (-Pin is refused, a hotfix- slug is not pinned), lifts no hold
    and enables nothing. The queue wait is 60 seconds here unless -QueueTimeoutSeconds is given.

.PARAMETER AllEnabled
    The campaign form over every enabled project of the registry, in its order, except the keys in -Skip (comma-
    separated registered keys; -Skip is the alias of -SkipKeys) and any key that contains `sandbox` - a sandbox is
    filed into only when -Projects names it.

.PARAMETER Parent
    <key>:<id> of an existing ticket that waits for the campaign: one `Blocker: <key>:<id>` line per child is written
    into its spec file, before a closing Blocked-tickets or Last-Audit block. Its status is not changed.

.PARAMETER Tracking
    Create one campaign checklist in the registered canon and file children only for repositories with work.
    Use with -Projects or -AllEnabled and exactly one of -NeedsWork or -Check.

.PARAMETER NeedsWork
    Comma-separated keys from the campaign targets. Pass an empty string for a campaign with no child tickets.

.PARAMETER Check
    Path to a PowerShell script to run from each target repository root, with a five-second timeout.
    Exit 0 passes, exit 1 identifies work, other exit codes keep the row open without filing a child.

.PARAMETER TrackingTicket
    Recheck the existing canon checklist identified by <key>:<id>. Supply -Check again.
    This updates checklist rows and exits 1 if any check fails. It never files tickets.

.PARAMETER NoQueueReport
    Capture only: no sync, no queue check, the result line says pq=deferred. The campaign form passes it to its children.

.PARAMETER Help
    Print this help.

.EXAMPLE
    pwsh -NoProfile -File spec-draft.ps1 -Project fms-a -Slug bugfix-grid-crash -TextFile C:\tmp\owner.txt -DedupQuery "grid crash"

.EXAMPLE
    pwsh -NoProfile -File spec-draft.ps1 -Slug export-csv -TextFile owner.txt -Complexity "light - one new menu item" -WhatIf

Exit codes: 0 the ticket exists (or -WhatIf finished); 1 the catalog refused or the spec file could not be
written; 2 bad invocation, an unknown project or a half-set-up task flow; 3 the dedup query hit a closed ticket.
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
    [switch] $NoPin,
    [ValidateRange(1, 300)]
    [int]    $QueueTimeoutSeconds = 10,
    [string] $Projects = '',
    [switch] $AllEnabled,
    [Alias('Skip')]
    [string] $SkipKeys = '',
    [string] $Parent = '',
    [switch] $Tracking,
    [AllowEmptyString()]
    [string] $NeedsWork,
    [string] $Check = '',
    [string] $TrackingTicket = '',
    [switch] $NoQueueReport,
    [switch] $Help
)

if ($Help) {
    Get-Help -Name $PSCommandPath -Detailed | Out-String -Width 120 | Write-Host
    exit 0
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pq = if ($env:SZA_PQ_SCRIPT) { $env:SZA_PQ_SCRIPT } else { Join-Path $PSScriptRoot 'pq.ps1' }
$harness = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pwshExe = (Get-Process -Id $PID).Path
. (Join-Path $PSScriptRoot 'lib/picker.ps1')
. (Join-Path $PSScriptRoot 'lib/ledger-watch.ps1')
. (Join-Path $PSScriptRoot 'lib/campaign-tracking.ps1')
. (Join-Path $harness 'spec_catalog/attachment-capture.ps1')

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

function Invoke-Pq([string[]] $PqArgs, [int] $TimeoutSeconds = 0) {
    $psi = [Diagnostics.ProcessStartInfo]::new($pwshExe)
    $psi.ArgumentList.Add('-NoProfile')
    $psi.ArgumentList.Add('-File')
    $psi.ArgumentList.Add($pq)
    foreach ($a in $PqArgs) { $psi.ArgumentList.Add([string]$a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $PSScriptRoot
    $proc = [Diagnostics.Process]::Start($psi)
    $out = $proc.StandardOutput.ReadToEndAsync()
    $err = $proc.StandardError.ReadToEndAsync()
    $timedOut = $false
    if ($TimeoutSeconds -gt 0) {
        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            $timedOut = $true
            try { $proc.Kill($true) } catch { }
            if ($IsWindows) {
                try { & taskkill.exe /PID $proc.Id /T /F 2>&1 | Out-Null } catch { }
            }
            [void]$proc.WaitForExit(5000)
        }
    }
    else {
        $proc.WaitForExit()
    }
    if ($timedOut) {
        return [pscustomobject]@{ code = 124; text = 'timed out'; timedOut = $true }
    }
    $proc.WaitForExit()
    $all = @($out.Result, $err.Result) | Where-Object { $_ }
    return [pscustomobject]@{ code = $proc.ExitCode; text = ($all -join "`n"); timedOut = $false }
}

# The name a ticket gets when the owner gave none: the first words of the owner's text, Cyrillic transliterated.
# ASCII-only source on purpose - the letters are code points, so the file reads the same under any encoding.
function ConvertTo-SlugFromText([string] $Text, [string[]] $ProjectKeys = @()) {
    # A request typed as a command ("/spec-draft <key> the grid is slow") is named from what follows it: a leading
    # /command token is dropped, and after it one token that is a registered project key (any letter case, '_' read
    # as '-', a trailing ':' or ',' ignored). A key with no command before it is an ordinary word and stays. Only the
    # name is made from the shortened text - the ticket keeps the owner's words whole.
    $cmd = [regex]::Match($Text, '^\s*/[A-Za-z][\w:-]*(?:\s+|$)')
    if ($cmd.Success) {
        $Text = $Text.Substring($cmd.Length)
        $first = [regex]::Match($Text, '^(?<t>\S+)(?:\s+|$)')
        if ($first.Success) {
            $token = $first.Groups['t'].Value.TrimEnd(':', ',').Replace('_', '-')
            if (@($ProjectKeys | Where-Object { $_ -and ([string]$_).Replace('_', '-') -ieq $token }).Count -gt 0) {
                $Text = $Text.Substring($first.Length)
            }
        }
    }
    # U+0430..U+044F in order (a b v g d e zh z i y k l m n o p r s t u f kh ts ch sh shch hard-sign y soft-sign e yu ya)
    $ru = @('a', 'b', 'v', 'g', 'd', 'e', 'zh', 'z', 'i', 'y', 'k', 'l', 'm', 'n', 'o', 'p', 'r', 's', 't', 'u', 'f', 'kh', 'ts', 'ch', 'sh', 'shch', '', 'y', '', 'e', 'yu', 'ya')
    $extra = @{ 0x0451 = 'yo'; 0x0456 = 'i'; 0x0457 = 'yi'; 0x0454 = 'ye'; 0x0491 = 'g' }
    $sb = [Text.StringBuilder]::new()
    foreach ($ch in $Text.ToLowerInvariant().ToCharArray()) {
        $cp = [int]$ch
        if ($cp -ge 0x0430 -and $cp -le 0x044F) { [void]$sb.Append($ru[$cp - 0x0430]) }
        elseif ($extra.ContainsKey($cp)) { [void]$sb.Append($extra[$cp]) }
        elseif (($cp -ge 0x61 -and $cp -le 0x7A) -or ($cp -ge 0x30 -and $cp -le 0x39)) { [void]$sb.Append($ch) }
        else { [void]$sb.Append(' ') }
    }
    # Up to 5 words of 3+ letters (the one- and two-letter ones are prepositions), 50 characters at most.
    $kept = [Collections.Generic.List[string]]::new()
    $len = 0
    foreach ($w in ($sb.ToString() -split ' ' | Where-Object { $_.Length -ge 3 })) {
        if ($kept.Count -ge 5 -or $len + $w.Length + $(if ($kept.Count) { 1 } else { 0 }) -gt 50) { break }
        $kept.Add($w)
        $len += $w.Length + $(if ($kept.Count -gt 1) { 1 } else { 0 })
    }
    if ($kept.Count -eq 0) { return '' }
    return ($kept -join '-')
}

function Get-DraftVerdict([string] $Reason) {
    # The pq verdict for one project, from the reason the dry-run gave for skipping it ('' = not skipped).
    switch ($Reason) {
        ''            { return 'dispatchable' }
        'occupied'    { return 'dispatchable' }
        'heldByQueue' { return 'held-by-queue' }
        'hold'        { return 'held' }
        'disabled'    { return 'disabled' }
        default       { return $Reason }
    }
}

function Resolve-DraftParent([string] $Pair, $Repos) {
    # -Parent <key>:<id> -> @{ pair; file }: the parent's spec file, found through its project's own ledger.
    $m = [regex]::Match($Pair, '^(?<k>[A-Za-z][A-Za-z0-9-]*):(?<i>[A-Za-z][A-Za-z0-9_-]*\d[A-Za-z0-9_-]*)$')
    if (-not $m.Success) { Stop-Draft 2 "invalid -Parent '$Pair' - expected <key>:<id> of an existing ticket" }
    $rec = @($Repos | Where-Object { [string]$_.key -ieq $m.Groups['k'].Value }) | Select-Object -First 1
    if (-not $rec) { Stop-Draft 2 "-Parent names project '$($m.Groups['k'].Value)', which is not registered" }
    $id = $m.Groups['i'].Value
    $snap = $null
    try { $snap = Get-PqLedgerSnapshot -RepoPath ([string]$rec.path) }
    catch { Stop-Draft 2 "-Parent: the ledger of $($rec.key) could not be read: $($_.Exception.Message)" }
    # TASK-FLOW 0.37: an old id names its ticket (CANONR-0195 G4); the blocker is written with the current id.
    if ($snap.ledgerRead -and -not $snap.tickets.Contains($id)) {
        $cur = Resolve-PqSnapshotTicketId $snap $id
        if ($cur) { $id = $cur }
    }
    if (-not $snap.ledgerRead -or -not $snap.tickets.Contains($id)) { Stop-Draft 2 "-Parent: $($rec.key) has no ticket $id in its ledger" }
    if ([string]$snap.tickets[$id].status -ceq 'Archived') { Stop-Draft 2 "-Parent: $($rec.key):$id is archived and cannot wait for anything" }
    $rel = [string]$snap.tickets[$id].file
    $file = if ($rel) { Resolve-PqRepoPathValue $snap.root $rel } else { '' }
    if (-not $file -or -not (Test-Path -LiteralPath $file -PathType Leaf)) { Stop-Draft 2 "-Parent: the spec file of $($rec.key):$id is missing ($rel)" }
    return [pscustomobject]@{ pair = "$($rec.key):$id"; file = $file }
}

function Add-DraftParentBlockers([string] $File, [string[]] $Pairs, [string] $Name) {
    # One `Blocker: <key>:<id>` line per child, inserted before a closing Blocked-tickets or Last-Audit block (they
    # stay last, TASK-FLOW rule 69), else at the end. A pair the spec already names is not written twice. The BOM,
    # the line ending and every byte outside the inserted block are kept. Returns the number of lines written.
    $bytes = [IO.File]::ReadAllBytes($File)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $skipBytes = if ($bom) { 3 } else { 0 }
    $text = [Text.UTF8Encoding]::new($false).GetString($bytes, $skipBytes, $bytes.Length - $skipBytes)
    $new = @($Pairs | Where-Object { $text -notmatch ('(?im)^[ \t]*Blocker:[ \t]*' + [regex]::Escape($_) + '[ \t]*\r?$') })
    if ($new.Count -eq 0) { return 0 }
    $eol = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $closing = [regex]::Match($text, '(?m)^##[ \t]+(?:Blocked tickets[ \t]*\r?$|(?:\d+\.[ \t]*)?Last Audit\b)')
    $at = if ($closing.Success) { $closing.Index } else { $text.Length }
    $before = $text.Substring(0, $at)
    $lead = if ($before.Length -eq 0 -or $before -match '\n\r?\n\z') { '' } elseif ($before.EndsWith("`n")) { $eol } else { $eol + $eol }
    $block = $lead + "Campaign '$Name' - children filed $(Get-Date -Format 'yyyy-MM-dd') by spec-draft.ps1; this ticket waits on each:" + $eol + $eol +
        (@($new | ForEach-Object { "Blocker: $_" }) -join $eol) + $eol + $(if ($closing.Success) { $eol } else { '' })
    [IO.File]::WriteAllText($File, $text.Insert($at, $block), [Text.UTF8Encoding]::new($bom))
    return $new.Count
}

# ---- 1. the invocation, checked before anything is created ----
$hasNeedsWork = $PSBoundParameters.ContainsKey('NeedsWork')
if ($TrackingTicket) {
    $unexpected = @($PSBoundParameters.Keys | Where-Object { $_ -notin @('TrackingTicket', 'Check', 'WhatIf') })
    if (-not $Check -or $unexpected.Count) { Stop-Draft 2 '-TrackingTicket takes only -Check and optionally -WhatIf' }
}
elseif ($Tracking) {
    if (-not ($Projects -or $AllEnabled) -or ($hasNeedsWork -eq [bool]$Check)) {
        Stop-Draft 2 '-Tracking requires campaign targets and exactly one of -NeedsWork or -Check'
    }
}
elseif ($hasNeedsWork -or $Check) { Stop-Draft 2 '-NeedsWork and -Check require tracking mode' }
if ($Check) {
    if ([IO.Path]::GetExtension($Check) -ine '.ps1' -or -not (Test-Path -LiteralPath $Check -PathType Leaf)) {
        Stop-Draft 2 "-Check '$Check' must name an existing PowerShell script"
    }
    $Check = (Resolve-Path -LiteralPath $Check).Path
}
$repos = @()   # the registry, read before the ticket is named: a derived name skips a registered key (section 2 uses it too)
$registry = $null
$list = Invoke-Pq @('list', '-Json')
if ($list.code -eq 0) {
    try {
        $registry = ConvertFrom-Json -InputObject $list.text -DateKind String
        $repos = @(Get-Prop $registry 'repos' @())
    }
    catch { $registry = $null; $repos = @() }
}
if ($Tracking -or $TrackingTicket) {
    $canon = @($repos | Where-Object { (Get-Prop $_ 'role') -ceq 'canon-home' })
    if ($canon.Count -ne 1) { Stop-Draft 2 'tracking requires exactly one registered canon-home repository' }
    $canon = $canon[0]
}
if ($TrackingTicket) {
    if (($TrackingTicket -split ':', 2)[0] -ine $canon.key) { Stop-Draft 2 '-TrackingTicket must name a ticket in the canon' }
    $trackingRef = Resolve-DraftParent $TrackingTicket $repos
    try {
        $checkBody = [IO.File]::ReadAllText($trackingRef.file)
        $checklist = @(Read-CampaignTable $checkBody)
    }
    catch { Stop-Draft 2 $_.Exception.Message }
    if ($WhatIfPreference) {
        Write-Host "spec-draft: -WhatIf - would check $($checklist.Count) row(s) in $($trackingRef.pair)"
        exit 0
    }
    $checkFailed = Update-CampaignChecks $checklist $repos $pwshExe $Check
    try { Write-CampaignTable $trackingRef.file $checklist -ExpectedBody $checkBody }
    catch { Stop-Draft 1 "could not write $($trackingRef.pair): $($_.Exception.Message)" }
    exit $(if ($checkFailed) { 1 } else { 0 })
}
if (-not $TextFile -or -not (Test-Path -LiteralPath $TextFile -PathType Leaf)) {
    Stop-Draft 2 "-TextFile '$TextFile' does not exist - write the owner's words to a UTF-8 file and pass it"
}
$textFull = (Resolve-Path -LiteralPath $TextFile).Path
$ownerText = [IO.File]::ReadAllText($textFull, [Text.Encoding]::UTF8)
if ([string]::IsNullOrWhiteSpace($ownerText)) {
    Stop-Draft 2 'the text is empty - a ticket with no words has nothing to be worked from'
}
$keys = if ($repos.Count) { (@($repos | ForEach-Object { [string]$_.key }) -join ', ') } else { 'none registered' }
# The New Specification dialog pre-fills the slug box with the type prefix and the owner types only the description, so
# no slug at all and a bare bugfix-/hotfix- are both "name it from the text". Any other bare prefix is still refused.
if ($Slug -cmatch '^(?<prefix>(bugfix-|hotfix-)?)$') {
    $named = ConvertTo-SlugFromText $ownerText @($repos | ForEach-Object { [string]$_.key })
    if (-not $named) { $named = 'captured-' + (Get-Date -Format 'yyyyMMdd-HHmmss') }
    $Slug = $Matches['prefix'] + $named
    Write-Host "spec-draft: no ticket name given - named it '$Slug' from the text"
}
if ($Slug -cnotmatch '^[a-z0-9][a-z0-9_-]*$' -or $Slug -match '^spec_') {
    Stop-Draft 2 "invalid -Slug '$Slug' - lowercase [a-z0-9_-], starting alphanumeric, not starting with 'spec_'"
}
if ($Slug -match '[-_]$') {
    Stop-Draft 2 "invalid -Slug '$Slug' - it ends with a separator, so nothing names the ticket after its prefix; write what it is about, e.g. '${Slug}no-full-build-outside-release'"
}
# An urgent blocker goes first: pq works it before everything else, so the pin is not left to a checkbox.
if ($Pin -and $NoPin) { Stop-Draft 2 '-Pin and -NoPin contradict each other' }
if ($Slug -like 'hotfix-*' -and -not $NoPin) { $Pin = $true }
# A bare level is what the New Specification dialog sends; the capture scripts want '<level> - <reason>'.
if ($Complexity -cmatch '^(light|medium|hard|[0-9](?: pinned)?)$') {
    $Complexity = "$Complexity - " + $(if ($Complexity -ceq 'medium') { 'not assessed at capture' } else { 'level picked by the owner at capture' })
}

if (-not ($Projects -or $AllEnabled)) {
    if ($SkipKeys) { Stop-Draft 2 '-Skip only narrows -AllEnabled' }
    if ($Parent) { Stop-Draft 2 '-Parent belongs to the campaign form (-Projects or -AllEnabled)' }
}
else {
    # ---- 1b. the campaign form: the same ticket into several registered projects ----
    # One child of this script per target does the capture; the queue is refreshed and asked ONCE, after the last
    # child. A campaign never pins, lifts no hold and enables nothing: each target is reported as pq finds it.
    if ($Projects -and $AllEnabled) { Stop-Draft 2 '-Projects and -AllEnabled contradict each other' }
    if ($Project) { Stop-Draft 2 '-Project names one target; a campaign takes -Projects or -AllEnabled' }
    if ($SkipKeys -and -not $AllEnabled) { Stop-Draft 2 '-Skip only narrows -AllEnabled' }
    if ($PSBoundParameters.ContainsKey('Pin')) { Stop-Draft 2 'a campaign never pins - put one ticket first afterwards with pq pin <key>:<id>' }
    if ($NoQueueReport) { Stop-Draft 2 '-NoQueueReport is for a single target' }
    $attachFull = ''
    if ($Attach) { try { $attachFull = @(Resolve-DraftAttachments $Attach) -join ';' } catch { Stop-Draft 2 $_.Exception.Message } }
    if ($repos.Count -eq 0) { Stop-Draft 2 'the portfolio registry could not be read or is empty - a campaign needs registered projects (pq list)' }
    $known = @($repos | ForEach-Object { [string]$_.key })
    $keysGiven = @($(if ($AllEnabled) { $SkipKeys } else { $Projects }) -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $unknown = @($keysGiven | Where-Object { $known -inotcontains $_ })
    if ($unknown.Count) { Stop-Draft 2 "unknown project key(s): $($unknown -join ', ') (registered: $($known -join ', '))" }
    $targets = [Collections.Generic.List[string]]::new()
    if ($AllEnabled) {
        foreach ($r in $repos) {
            $k = [string]$r.key
            if ((Get-Prop $r 'enabled' $false) -ne $true -or $keysGiven -icontains $k) { continue }
            if ($k -match 'sandbox') { Write-Host "spec-draft: left out $k - a sandbox is filed into only when -Projects names it"; continue }
            $targets.Add($k)
        }
    }
    else {
        foreach ($n in $keysGiven) { $k = [string](@($known | Where-Object { $_ -ieq $n })[0]); if (-not $targets.Contains($k)) { $targets.Add($k) } }
    }
    if ($targets.Count -eq 0) { Stop-Draft 2 'the campaign has no target - every project was skipped, disabled or a sandbox' }
    $parentRef = if ($Parent) { Resolve-DraftParent $Parent $repos } else { $null }
    $childArgs = @('-NoProfile', '-File', $PSCommandPath, '-Slug', $Slug, '-TextFile', $textFull, '-NoPin', '-NoQueueReport')
    if ($Priority -ge 0) { $childArgs += @('-Priority', "$Priority") }
    if ($Complexity) { $childArgs += @('-Complexity', $Complexity) }
    if ($DedupQuery) { $childArgs += @('-DedupQuery', $DedupQuery) }
    if ($attachFull) { $childArgs += @('-Attach', $attachFull) }
    if ($AllowClosedDuplicate) { $childArgs += '-AllowClosedDuplicate' }
    if ($WhatIfPreference) { $childArgs += '-WhatIf' }
    $rows = [Collections.Generic.List[object]]::new()
    $failed = [Collections.Generic.List[string]]::new()
    $captureTargets = $targets
    $trackingRef = $null
    if ($Tracking) {
        $workKeys = @($NeedsWork -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $outside = @($workKeys | Where-Object { $targets -inotcontains $_ })
        if ($outside.Count) { Stop-Draft 2 "work keys outside the campaign: $($outside -join ', ')" }
        if ($WhatIfPreference) {
            Write-Host "spec-draft: -WhatIf - would capture one checklist in $($canon.key) for $($targets -join ', ')"
            exit 0
        }
        $checklist = @(foreach ($key in $targets) {
            [pscustomobject]@{
                key = $key
                work = if ($Check) { 'unknown' } elseif ($workKeys -icontains $key) { 'yes' } else { 'no' }
                check = 'pending'
                done = 'no'
            }
        })
        if ($Check) {
            [void](Update-CampaignChecks $checklist $repos $pwshExe $Check)
        }
        $captureTargets = @($canon.key) + @($checklist | Where-Object work -eq 'yes' | ForEach-Object key)
    }
    # The catalog writer refreshes the portfolio projection after every insert unless SZA_PQ_NO_PROJECTION is 1; the one
    # `pq sync` below does that for all targets together. The rows are born `campaign` (TASK-FLOW section 10) unless the
    # caller already names a source - a pass keeps `robot`, which the robot-filed cap counts.
    $savedNoProjection = $env:SZA_PQ_NO_PROJECTION
    $savedSource = $env:SZA_TICKET_SOURCE
    $env:SZA_PQ_NO_PROJECTION = '1'
    if (-not $env:SZA_TICKET_SOURCE) { $env:SZA_TICKET_SOURCE = 'campaign' }
    try {
        for ($index = 0; $index -lt $captureTargets.Count; $index++) {
            $k = $captureTargets[$index]
            $isTrackingSpec = $Tracking -and $index -eq 0
            $argsForTarget = $childArgs.Clone()
            if ($isTrackingSpec) { $argsForTarget[4] = "$Slug-tracking" }
            $out = & $pwshExe @argsForTarget '-Project' $k 2>&1
            $code = $LASTEXITCODE
            $hit = $null
            foreach ($l in @($out | ForEach-Object { "$_".TrimEnd() } | Where-Object { $_ })) {
                $m = [regex]::Match($l, '^drafted\s+\S+?:(?<id>\S+)\s+file=(?<file>\S+)\s+priority=(?<pri>\S+)\s+pq=(?<pq>\S+)\s+position=\S+$')
                if ($m.Success) { $hit = $m } else { Write-Host "[$k] $l" }
            }
            if ($isTrackingSpec) {
                if ($code -ne 0 -or -not $hit) { Stop-Draft 1 "the canon tracking capture returned exit $code and no usable ticket" }
                $trackingRef = Resolve-DraftParent "${k}:$($hit.Groups['id'].Value)" $repos
                Write-Host "tracking $($trackingRef.pair) file=$($hit.Groups['file'].Value)"
                try { Write-CampaignTable $trackingRef.file $checklist -Create }
                catch { Stop-Draft 1 "could not write the checklist for $($trackingRef.pair): $($_.Exception.Message)" }
                continue
            }
            if ($code -ne 0) { $failed.Add("$k (exit $code)"); continue }
            if ($hit) {
                $rows.Add([pscustomobject]@{ key = $k; id = $hit.Groups['id'].Value; file = $hit.Groups['file'].Value; pri = $hit.Groups['pri'].Value; pq = $hit.Groups['pq'].Value })
                if ($trackingRef) {
                    $row = $checklist | Where-Object key -ceq $k
                    $row.done = "no (${k}:$($hit.Groups['id'].Value))"
                    try { Write-CampaignTable $trackingRef.file $checklist }
                    catch { Stop-Draft 1 "child ${k}:$($hit.Groups['id'].Value) exists; could not update $($trackingRef.pair): $($_.Exception.Message)" }
                }
            }
            elseif (-not $WhatIfPreference) { $failed.Add("$k (no drafted line)") }
        }
    }
    finally { $env:SZA_PQ_NO_PROJECTION = $savedNoProjection; $env:SZA_TICKET_SOURCE = $savedSource }
    if ($WhatIfPreference) {
        Write-Host "spec-draft: -WhatIf - $($targets.Count) target(s) checked ($($targets -join ', ')); nothing was created"
        exit $(if ($failed.Count) { 1 } else { 0 })
    }
    $queueWait = if ($PSBoundParameters.ContainsKey('QueueTimeoutSeconds')) { $QueueTimeoutSeconds } else { 60 }
    if ($trackingRef -or @($rows | Where-Object { $_.pq -ceq 'deferred' }).Count) {
        $sync = Invoke-Pq @('sync') -TimeoutSeconds $queueWait
        if ($sync.timedOut -or $sync.code -ne 0) { Write-Host "pq: the sync after the campaign reported a problem: $($sync.text.Trim()); repair with pq sync" }
        $dry = Invoke-Pq @('dry-run', '-Json') -TimeoutSeconds $queueWait
        $doc = $null
        if (-not $dry.timedOut -and $dry.code -eq 0) { try { $doc = ConvertFrom-Json -InputObject $dry.text -DateKind String } catch { $doc = $null } }
        if ($null -eq $doc) { Write-Host "pq: the queue check after the campaign failed or timed out (${queueWait}s); every verdict is unknown - run pq dry-run" }
        foreach ($r in $rows) {
            if ($r.pq -cne 'deferred') { continue }
            if ($null -eq $doc) { $r.pq = 'unknown'; continue }
            $skipRow = @(Get-Prop $doc 'skipped' @()) | Where-Object { [string]$_.repo -ceq $r.key } | Select-Object -First 1
            $r.pq = Get-DraftVerdict $(if ($skipRow) { [string]$skipRow.why } else { '' })
        }
    }
    if ($parentRef) {
        $pairs = [string[]]@($rows | Where-Object { $_.pq -cne 'no-task-flow' } | ForEach-Object { "$($_.key):$($_.id)" })
        foreach ($r in @($rows | Where-Object { $_.pq -ceq 'no-task-flow' })) { Write-Host "spec-draft: $($r.key):$($r.id) is a plain file with no ledger - not named as a blocker of $($parentRef.pair)" }
        if ($pairs.Count) {
            try { Write-Host "spec-draft: $(Add-DraftParentBlockers $parentRef.file $pairs $Slug) Blocker line(s) written into $($parentRef.pair) ($($parentRef.file)); its status is not changed" }
            catch { $failed.Add("parent $($parentRef.pair) ($($_.Exception.Message))") }
        }
    }
    foreach ($r in $rows) { Write-Host ("drafted {0}:{1} file={2} priority={3} pq={4} position=0/0" -f $r.key, $r.id, $r.file, $r.pri, $r.pq) }
    if ($Slug -like 'hotfix-*') { Write-Host 'pq: a campaign is not pinned - pq pin <key>:<id> puts one ticket first' }
    if ($failed.Count) {
        $retry = if ($trackingRef) { "file the missing children separately and record them in $($trackingRef.pair)" }
            else { 'once fixed, rerun with -Projects naming only the keys that failed' }
        Write-Host "spec-draft: NOT done - $($failed -join '; '); $retry" -ForegroundColor Red
    }
    Write-Host ("campaign {0}: {1} drafted, {2} failed{3}" -f $Slug, $rows.Count, $failed.Count, $(if ($parentRef) { ", parent $($parentRef.pair)" } else { '' }))
    exit $(if ($failed.Count) { 1 } else { 0 })
}

# ---- 2. the project ----

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
        if ((Test-Path -LiteralPath (Join-Path $dir '.sza-profile.json') -PathType Leaf) -or (Test-Path -LiteralPath (Join-Path $dir '.sza-canon.json') -PathType Leaf)) { $root = $dir; break }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    if (-not $root) { Stop-Draft 2 "no project here - no .sza-profile.json or .sza-canon.json at or above $((Get-Location).Path). Pass -Project <key|path> (registered: $keys)" }
}
if (-not (Test-Path -LiteralPath $root -PathType Container)) { Stop-Draft 2 "project folder '$root' does not exist" }
if (-not $rec) {
    $rootKey = ConvertTo-PathKey $root
    $rec = @($repos | Where-Object { (ConvertTo-PathKey ([string]$_.path)) -ceq $rootKey }) | Select-Object -First 1
}

$profileFile = Join-Path $root '.sza-profile.json'
$attachmentPaths = @()
if ($Attach) {
    try { $attachmentPaths = @(Resolve-DraftAttachments $Attach) }
    catch { Stop-Draft 2 $_.Exception.Message }
}
if (-not (Test-Path -LiteralPath $profileFile -PathType Leaf)) {
    # ---- 2b. no task flow at all: one plain ticket file, numbered the way the project already numbers ----
    # Refusing here sent the owner to a setup they had not asked for. The ticket is captured, but only as a file; no
    # profile, ledger or queue row is written, because a second numbering scheme inside a project that has its own
    # (Streams_Player's SP-NNNN) is worse than a ticket pq cannot pick up. The report says that pq cannot.
    $label = if ($rec) { [string]$rec.key } else { Split-Path -Leaf $root }
    $planRel = [string]$script:PqRepoDefaults.paths.specsDir
    $planDir = Join-Path $root $planRel

    if ($Complexity -match '[\r\n]') { Stop-Draft 2 "invalid -Complexity - the reason is one line; expected '<0-9|light|medium|hard> - <one-line reason>'" }
    if ($Complexity) {
        # A level word, or a grade 0-9 with an optional `pinned` (TASK-FLOW 0.32, S0139) - the same shape capture-draft.ps1 takes.
        $cx = [regex]::Match($Complexity, '^\s*(light|medium|hard|[0-9](?:\s+pinned)?)\s+-\s+(\S.*?)\s*$', 'IgnoreCase')
        if (-not $cx.Success) { Stop-Draft 2 "invalid -Complexity '$Complexity' - expected '<level> - <one-line reason>' with level 0-9 (optionally '<n> pinned'), light, medium or hard" }
        $Complexity = '{0} - {1}' -f ($cx.Groups[1].Value.ToLowerInvariant() -replace '\s+', ' '), $cx.Groups[2].Value
    }
    else { $Complexity = 'medium - not assessed at capture' }

    $ownTemplate = Join-Path $planDir 'TICKET_TEMPLATE.md'
    $templatePath = if (Test-Path -LiteralPath $ownTemplate -PathType Leaf) { $ownTemplate } else { Join-Path $harness 'scaffold/templates/ticket-template.md' }
    $template = [IO.File]::ReadAllText($templatePath)
    if (-not $template.Contains('{{TEXT}}')) { Stop-Draft 2 "the ticket template $templatePath has no {{TEXT}} token, so the owner's words would be lost" }

    # The numbering is read from the tickets already there: PLAN/ and its closed-work folders, files and folders alike
    # (a tactical-plan folder spends its id too). The most common <prefix><digits>_ wins; the next number is one past
    # its highest. Nothing numbered: S0001, the canon's own form.
    function Get-PlainState {
        $archiveName = Split-Path -Leaf ([string]$script:PqRepoDefaults.paths.specArchiveDir)
        $dirs = @()
        if (Test-Path -LiteralPath $planDir -PathType Container) {
            $dirs += $planDir
            $dirs += @(Get-ChildItem -LiteralPath $planDir -Directory -Force | Where-Object { $_.Name -match ('^(done|' + [regex]::Escape($archiveName) + ')$') } | ForEach-Object { $_.FullName })
        }
        $existing = @(foreach ($d in $dirs) {
            foreach ($e in Get-ChildItem -LiteralPath $d -Force) {
                $m = [regex]::Match($e.Name, '^(?<p>[A-Za-z]+-?)(?<n>\d{2,6})_')
                if ($m.Success) { [pscustomobject]@{ prefix = $m.Groups['p'].Value; digits = $m.Groups['n'].Value; item = $e } }
            }
        })
        $prefix = 'S'; $width = 4; $next = 1
        $how = "no numbered tickets in $planRel/ - numbering starts at ${prefix}0001, the canon's form"
        if ($existing.Count) {
            $top = @($existing | Group-Object -Property prefix -CaseSensitive | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'Name' })[0]
            $prefix = [string]$top.Name
            $width = [int](($top.Group | ForEach-Object { $_.digits.Length } | Measure-Object -Maximum).Maximum)
            $highest = [int](($top.Group | ForEach-Object { [int]$_.digits } | Measure-Object -Maximum).Maximum)
            $next = $highest + 1
            $how = "numbering '$prefix' + $width digits, read from $($top.Count) existing ticket name(s), one past $prefix$("$highest".PadLeft($width, '0'))"
        }
        $newId = $prefix + "$next".PadLeft($width, '0')
        return [pscustomobject]@{ existing = $existing; id = $newId; fileRel = "$planRel/${newId}_$Slug.md"; numbering = $how }
    }

    $state = Get-PlainState
    if ($DedupQuery) {
        $hits = [Collections.Generic.List[object]]::new()
        foreach ($t in @($state.existing | Where-Object { $_.item -is [IO.FileInfo] -and $_.item.Extension -ieq '.md' })) {
            $head = @(Get-Content -LiteralPath $t.item.FullName -TotalCount 60 -ErrorAction SilentlyContinue)
            if (("$($t.item.BaseName)`n" + ($head -join "`n")).IndexOf($DedupQuery, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
            $statusLine = @($head | Where-Object { $_ -match '^\*\*Status:\*\*' }) | Select-Object -First 1
            $status = if ($statusLine) { ([string]$statusLine -replace '^\*\*Status:\*\*\s*', '').Trim() } else { '?' }
            $hits.Add([pscustomobject]@{ id = ($t.item.Name -split '_')[0]; name = $t.item.BaseName; status = $status; closed = ($status -match '^(Verified|Archived)\b') })
        }
        foreach ($h in $hits | Select-Object -First 5) { Write-Host ('dedup: {0}  {1,-12} {2}' -f $h.id, $h.status.Substring(0, [Math]::Min(40, $h.status.Length)), $h.name) }
        if ($hits.Count -eq 0) { Write-Host "dedup: no hit for '$DedupQuery'" }
        $closedHit = @($hits | Where-Object { $_.closed }) | Select-Object -First 1
        if ($closedHit -and -not $AllowClosedDuplicate) {
            Write-Host ("capture-draft: {0} is already {1} - the defect behind this symptom is dealt with. Pass -AllowClosedDuplicate if it is a genuine regression." -f $closedHit.id, $closedHit.status) -ForegroundColor Yellow
            exit 3
        }
    }
    if ($WhatIfPreference) {
        Write-Host "spec-draft: -WhatIf - a plain capture would write $($state.fileRel) ($($state.numbering)); nothing was created"
        exit 0
    }

    # Two captures at once must not be handed one number: the numbering and the write sit under a per-project lock.
    $lockHash = [BitConverter]::ToString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes((ConvertTo-PathKey $root)))).Replace('-', '').Substring(0, 16)
    $lock = [Threading.Mutex]::new($false, "Global\sza-spec-draft-$lockHash")
    if (-not $lock.WaitOne(30000)) { $lock.Dispose(); Stop-Draft 1 "another capture holds $root and did not finish in 30 seconds; nothing was created" }
    try {
        $state = Get-PlainState
        $id = $state.id
        $fileRel = $state.fileRel
        $fileFull = Join-Path $root $fileRel
        if (Test-Path -LiteralPath $fileFull) { Stop-Draft 1 "the spec file already exists: $fileFull" }

        $body = $template.Replace('{{ID}}', $id).Replace('{{SLUG}}', $Slug).Replace('{{NAME}}', $Slug).Replace('{{DATE}}', (Get-Date -Format 'yyyy-MM-dd')).Replace('{{COMPLEXITY}}', $Complexity)
        # The template's own line ending; the attachment block below follows it. The owner's words go in after the
        # tokens, so a token inside them is never expanded.
        $eol = if ($body.Contains("`r`n")) { "`r`n" } else { "`n" }
        if (-not (Test-Path -LiteralPath $planDir -PathType Container)) { New-Item -ItemType Directory -Path $planDir -Force | Out-Null }
        try {
            $attachmentBlock = Copy-DraftAttachments -Paths $attachmentPaths -SpecPath $fileFull -Newline $eol
            $body = $body.Replace('{{TEXT}}', ([IO.File]::ReadAllText($textFull, [Text.Encoding]::UTF8) + $attachmentBlock))
            [IO.File]::WriteAllText($fileFull, $body, [Text.UTF8Encoding]::new($false))
        }
        catch { Stop-Draft 1 "could not complete $fileRel or its attachments: $($_.Exception.Message); inspect the ticket folder before retrying" }
    }
    finally { $lock.ReleaseMutex(); $lock.Dispose() }

    Write-Host "spec-draft: captured ${label}:${id} ($fileRel), Draft - a plain file, no ledger; $($state.numbering)"
    Write-Host "pq: NOT dispatched - $label has no task flow (no .sza-profile.json, so no ledger), pq never sees this ticket and it is a plain file for the project's own process. Setting the flow up (task-flow-init) is the owner's call"
    if ($Pin) { Write-Host "pq: pin refused - pq will not dispatch $label (no-task-flow)" }
    if ($Priority -ge 0) { Write-Host "spec-draft: -Priority $Priority is not recorded - there is no ledger to hold it" }
    Write-Host ("drafted {0}:{1} file={2} priority=- pq=no-task-flow position=0/0" -f $label, $id, $fileRel)
    exit 0
}
$profile = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($profileFile)) -DateKind String
$journalRel = [string](Get-Prop (Get-Prop $profile 'paths') 'journal' $script:PqRepoDefaults.paths.journal)
if (-not (Test-Path -LiteralPath (Join-Path $root $journalRel) -PathType Leaf)) {
    Stop-Draft 2 "$root has no ticket ledger at $journalRel - run the task-flow-init skill there first"
}
$grammar = Get-Prop $profile 'grammar'
$idPattern = [string](Get-Prop $grammar 'ticketIdPattern' '^S\d{4}$')
$specTemplate = [string](Get-Prop $grammar 'specFileTemplate' $script:PqRepoDefaults.grammar.specFileTemplate)

# ---- 3. the capture script ----
$own = Join-Path $root (Join-Path 'scripts' (Join-Path 'utils' 'capture-draft.ps1'))
$ownScript = Test-Path -LiteralPath $own -PathType Leaf
$captureScript = if ($ownScript) { $own } else { Join-Path $harness 'spec_catalog/capture-draft.ps1' }
# A capture script without -Attach still gets the files: they are linked after its capture, below.
$attachAfter = $attachmentPaths.Count -gt 0 -and -not (Get-Command -Name $captureScript -CommandType ExternalScript).Parameters.ContainsKey('Attach')
if ($Priority -lt 0) { $Priority = if ($Slug -like 'hotfix-*') { 95 } elseif ($Slug -like 'bugfix-*') { 90 } else { 50 } }

$capture = @('-NoProfile', '-File', $captureScript, '-Slug', $Slug, '-TextFile', $textFull, '-Priority', "$Priority")
if ($Complexity) { $capture += @('-Complexity', $Complexity) }
if ($DedupQuery) { $capture += @('-DedupQuery', $DedupQuery) }
if ($AllowClosedDuplicate) { $capture += '-AllowClosedDuplicate' }
# Resolved paths: the child runs in the project folder, where a relative path would point somewhere else.
if ($attachmentPaths.Count -and -not $attachAfter) { $capture += @('-Attach', ($attachmentPaths -join ';')) }
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
if ($attachAfter) {
    try { Add-DraftAttachmentLinks -Paths $attachmentPaths -SpecPath (Join-Path $root $fileRel) -RequestText ([IO.File]::ReadAllText($textFull, [Text.Encoding]::UTF8)) }
    catch { Stop-Draft 1 "ticket ${id} ($fileRel) was captured but its attachments were not linked: $($_.Exception.Message); copy the files into $([IO.Path]::GetFileNameWithoutExtension($fileRel))/attachments/ beside the spec and link them in section 0 by hand" }
}

if ($NoQueueReport) {
    # The campaign form asks pq once for all its targets; this child only captures.
    $label = if ($rec) { [string]$rec.key } else { Split-Path -Leaf $root }
    Write-Host "spec-draft: captured ${label}:${id} ($fileShown), Draft, priority $Priority"
    Write-Host ("drafted {0}:{1} file={2} priority={3} pq=deferred position=0/0" -f $label, $id, $fileShown, $Priority)
    exit 0
}

# Project-owned capture tools may not use the shared catalog writer. Reconcile their result too.
if ($rec) {
    $sync = Invoke-Pq @('sync', '-Path', $root) -TimeoutSeconds $QueueTimeoutSeconds
    if ($sync.timedOut) {
        Write-Host "pq: sync timed out after capture; repair with pq sync -Path `"$root`""
    }
    elseif ($sync.code -ne 0) {
        Write-Host "pq: sync failed after capture: $($sync.text.Trim()); repair with pq sync -Path `"$root`""
    }
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
    $deadlineSw = [Diagnostics.Stopwatch]::StartNew()
    function Get-PqRemainingSeconds([int]$LimitSec) {
        $rem = ($LimitSec * 1000) - $deadlineSw.ElapsedMilliseconds
        if ($rem -le 0) { return 0 }
        return [Math]::Max(1, [int][Math]::Ceiling($rem / 1000.0))
    }

    $dryRem = Get-PqRemainingSeconds $QueueTimeoutSeconds
    $dry = if ($dryRem -gt 0) {
        Invoke-Pq @('dry-run', '-Json') -TimeoutSeconds $dryRem
    } else {
        [pscustomobject]@{ code = 124; text = 'timed out'; timedOut = $true }
    }

    if ($dry.timedOut) {
        $verdict = 'unknown'
        $notes.Add("pq: queue check timed out after ${QueueTimeoutSeconds}s; eligibility of $label could not be established - run pq dry-run or pq pin manually")
    }
    elseif ($dry.code -ne 0) {
        $verdict = 'unknown'
        $notes.Add("pq: dry-run failed (exit $($dry.code)); eligibility of $label could not be read: $($dry.text.Trim()) - run pq dry-run or pq pin manually")
    }
    else {
        $skip = $null
        try {
            $dryDoc = ConvertFrom-Json -InputObject $dry.text -DateKind String
            $skip = @(Get-Prop $dryDoc 'skipped' @()) | Where-Object { [string]$_.repo -ceq $label } | Select-Object -First 1
        }
        catch { $skip = $null; $dryDoc = $null }

        if ($null -eq $dryDoc) {
            $verdict = 'unknown'
            $notes.Add("pq: dry-run returned invalid JSON; eligibility of $label could not be parsed - run pq dry-run or pq pin manually")
        }
        else {
            $reason = if ($skip) { [string]$skip.why } else { '' }
            $verdict = Get-DraftVerdict $reason
            switch ($verdict) {
                'held-by-queue' { $notes.Add("pq: NOT dispatched - $label sits under 'hold' in PORTFOLIO_QUEUE.md. The ticket waits; lifting the hold is the owner's call (pq release $label)") }
                'held'          { $notes.Add("pq: NOT dispatched - $label is on hold in the registry (pq release $label clears it). The ticket waits; that is the owner's call") }
                'disabled'      { $notes.Add("pq: NOT dispatched - $label is registered but not enabled (enabled=false in repos.json). Enabling is the owner's call") }
                'dispatchable'  { if ($reason -ceq 'occupied') { $notes.Add("pq: a worker is in $label right now; the ticket is taken in a later pass") } }
                default         { $notes.Add("pq: NOT dispatched - the rank skips $label ($reason)") }
            }
        }
    }

    $mode = [string](Get-Prop $rec 'permissionMode' ([string](Get-Prop $registry 'permissionMode' '')))
    if (-not $mode) { $notes.Add("pq: warning - $label has no permissionMode (on its record or at the top of repos.json); pq start refuses unattended work there until one is set") }

    # Position in the project's own ranking: only query if queue check has not timed out or failed.
    if ($verdict -ne 'unknown') {
        $pickRem = Get-PqRemainingSeconds $QueueTimeoutSeconds
        if ($pickRem -le 0) {
            if ($verdict -ceq 'dispatchable') { $verdict = 'unknown' }
            $notes.Add("pq: queue check timed out before reading position - run pq dry-run or pq pin manually")
        }
        else {
            $pick = Invoke-PqPicker -RepoPath $root -TimeoutSeconds $pickRem
            if ($pick.error -ceq 'PickerTimeout') {
                if ($verdict -ceq 'dispatchable') { $verdict = 'unknown' }
                $notes.Add("pq: the picker timed out after ${QueueTimeoutSeconds}s - run pq dry-run or pq pin manually")
            }
            elseif (-not $pick.ok) {
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
        }
    }

    if ($Pin) {
        if ($verdict -ceq 'dispatchable') {
            $pinRem = Get-PqRemainingSeconds $QueueTimeoutSeconds
            if ($pinRem -le 0) {
                $notes.Add("pq: pin refused - queue check timed out (pq=unknown); run pq dry-run or pq pin manually")
            }
            else {
                $pinRun = Invoke-Pq @('pin', "${label}:${id}") -TimeoutSeconds $pinRem
                if ($pinRun.code -eq 0) {
                    $pinned = $true
                    $notes.Add("pq: pinned - ${label}:${id} is first in the first numbered package of PORTFOLIO_QUEUE.md")
                }
                else {
                    $notes.Add("pq: pin failed (exit $($pinRun.code)): $($pinRun.text.Trim())")
                }
            }
        }
        elseif ($verdict -ceq 'unknown') {
            $notes.Add("pq: pin refused - queue check did not confirm dispatchability (pq=unknown); run pq dry-run or pq pin manually")
        }
        else {
            $notes.Add("pq: pin refused - pq will not dispatch $label ($verdict); a pin would not be worked, and lifting that is the owner's call")
        }
    }
    elseif ($Slug -like 'hotfix-*' -and $position -gt 1 -and $verdict -ceq 'dispatchable') {
        $notes.Add("pq: this hotfix is #$position (-NoPin left it in place) - pq pin ${label}:${id} puts it first")
    }
}

Write-Host "spec-draft: captured ${label}:${id} ($fileShown), Draft, priority $Priority"
foreach ($n in $notes) { Write-Host $n }
Write-Host ("drafted {0}:{1} file={2} priority={3} pq={4} position={5}/{6}" -f $label, $id, $fileShown, $Priority, $verdict, $position, $total)
exit 0
