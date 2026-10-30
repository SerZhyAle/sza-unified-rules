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
    attachments - FastMediaSorter_mob_v2 does); otherwise the canon's spec_catalog/capture-draft.ps1, which needs
    the project's PLAN/TICKET_TEMPLATE.md. Both write the ledger row, the spec file and the row in the project's
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
    transliterated, and printed; a caller that can write a better name passes it.

.PARAMETER TextFile
    UTF-8 file holding the owner's text, written exactly as the owner gave it. The only way in: a command line
    mangles quotes, newlines and encodings.

.PARAMETER Priority
    0..100. Default by slug prefix, see above.

.PARAMETER Complexity
    `<light|medium|hard> - <one-line reason>`. Omitted: `medium - not assessed at capture`. A bare level (what the
    New Specification dialog sends) is completed with a reason saying the level was picked at capture.

.PARAMETER DedupQuery
    A symptom searched in the catalog first. A hit on a closed ticket stops the capture with exit 3.

.PARAMETER AllowClosedDuplicate
    Capture anyway after a closed hit - the defect really did come back.

.PARAMETER Attach
    Semicolon-separated files to attach. Only a project whose own capture script takes -Attach accepts them;
    the canon's does not, and the call stops before creating anything.

.PARAMETER Pin
    Pin the new ticket to the top of PORTFOLIO_QUEUE.md after capture. Implied by a hotfix- slug.

.PARAMETER NoPin
    Do not pin a hotfix- ticket; it stays at the end of its package.

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
. (Join-Path $PSScriptRoot 'lib/ledger-watch.ps1')

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

# The name a ticket gets when the owner gave none: the first words of the owner's text, Cyrillic transliterated.
# ASCII-only source on purpose - the letters are code points, so the file reads the same under any encoding.
function ConvertTo-SlugFromText([string] $Text) {
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

# ---- 1. the invocation, checked before anything is created ----
if (-not $TextFile -or -not (Test-Path -LiteralPath $TextFile -PathType Leaf)) {
    Stop-Draft 2 "-TextFile '$TextFile' does not exist - write the owner's words to a UTF-8 file and pass it"
}
$textFull = (Resolve-Path -LiteralPath $TextFile).Path
$ownerText = [IO.File]::ReadAllText($textFull, [Text.Encoding]::UTF8)
if ([string]::IsNullOrWhiteSpace($ownerText)) {
    Stop-Draft 2 'the text is empty - a ticket with no words has nothing to be worked from'
}
# The New Specification dialog pre-fills the slug box with the type prefix and the owner types only the description, so
# no slug at all and a bare bugfix-/hotfix- are both "name it from the text". Any other bare prefix is still refused.
if ($Slug -cmatch '^(?<prefix>(bugfix-|hotfix-)?)$') {
    $named = ConvertTo-SlugFromText $ownerText
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
if ($Complexity -cmatch '^(light|medium|hard)$') {
    $Complexity = "$Complexity - " + $(if ($Complexity -ceq 'medium') { 'not assessed at capture' } else { 'level picked by the owner at capture' })
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
if (-not (Test-Path -LiteralPath $profileFile -PathType Leaf)) {
    # ---- 2b. no task flow at all: one plain ticket file, numbered the way the project already numbers ----
    # Refusing here sent the owner to a setup they had not asked for. The ticket is captured, but only as a file; no
    # profile, ledger or queue row is written, because a second numbering scheme inside a project that has its own
    # (Streams_Player's SP-NNNN) is worse than a ticket pq cannot pick up. The report says that pq cannot.
    if ($Attach) { Stop-Draft 2 'a project with no task flow has no capture script that takes attachments; put the content in the text, or attach the file by hand after capture' }
    $label = if ($rec) { [string]$rec.key } else { Split-Path -Leaf $root }
    $planRel = [string]$script:PqRepoDefaults.paths.specsDir
    $planDir = Join-Path $root $planRel

    if ($Complexity -match '[\r\n]') { Stop-Draft 2 "invalid -Complexity - the reason is one line; expected '<light|medium|hard> - <one-line reason>'" }
    if ($Complexity) {
        $cx = [regex]::Match($Complexity, '^\s*(light|medium|hard)\s+-\s+(\S.*?)\s*$', 'IgnoreCase')
        if (-not $cx.Success) { Stop-Draft 2 "invalid -Complexity '$Complexity' - expected '<level> - <one-line reason>' with level light, medium or hard" }
        $Complexity = '{0} - {1}' -f $cx.Groups[1].Value.ToLowerInvariant(), $cx.Groups[2].Value
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
        # A template written before the Complexity token existed: put the line in its header, before the owner's words
        # go in, so neither a token nor a header-like line inside them can be mistaken for the header.
        $eol = if ($body.Contains("`r`n")) { "`r`n" } else { "`n" }
        $tplLines = [Collections.Generic.List[string]]::new([string[]]($body -split '\r?\n'))
        $headLines = [Math]::Min(40, $tplLines.Count)
        $hasComplexity = $false
        for ($i = 0; $i -lt $headLines; $i++) { if ($tplLines[$i] -match '^\*\*Complexity:\*\*') { $hasComplexity = $true; break } }
        if (-not $hasComplexity) {
            $at = -1
            foreach ($anchor in '^\*\*Created:\*\*', '^\*\*Status:\*\*') {
                for ($i = 0; $i -lt $headLines; $i++) { if ($tplLines[$i] -match $anchor) { $at = $i + 1; break } }
                if ($at -ge 0) { break }
            }
            if ($at -lt 0) { $at = [Math]::Min(2, $tplLines.Count) }
            $tplLines.Insert($at, "**Complexity:** $Complexity")
            $body = $tplLines -join $eol
        }
        $body = $body.Replace('{{TEXT}}', [IO.File]::ReadAllText($textFull, [Text.Encoding]::UTF8))

        if (-not (Test-Path -LiteralPath $planDir -PathType Container)) { New-Item -ItemType Directory -Path $planDir -Force | Out-Null }
        [IO.File]::WriteAllText($fileFull, $body, [Text.UTF8Encoding]::new($false))
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
        $notes.Add("pq: this hotfix is #$position (-NoPin left it in place) - pq pin ${label}:${id} puts it first")
    }
}

Write-Host "spec-draft: captured ${label}:${id} ($fileShown), Draft, priority $Priority"
foreach ($n in $notes) { Write-Host $n }
Write-Host ("drafted {0}:{1} file={2} priority={3} pq={4} position={5}/{6}" -f $label, $id, $fileShown, $Priority, $verdict, $position, $total)
exit 0
