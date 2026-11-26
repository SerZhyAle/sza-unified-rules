#requires -Version 7.0
<#
.SYNOPSIS
    Resolves the argument of /spec-all, /sa, /spec-next and /sn to one project and one reading (S0027): a ticket of a
    named project, the next ticket of a project, a ticket of the current project, or an idea. Read-only.

.DESCRIPTION
    Ticket ids are unique only inside one project, so a skill that is run from one folder and given another
    project's ticket must name the project BEFORE it touches a ticket. This script is that decision, made the same way
    every time. The project lookup is the one pq and spec-quiz use (Read-PqRegistry, repos.json); the current project is
    found the way quiz-list.ps1 finds it (the first .sza-profile.json or .sza-canon.json at or above the folder).

    Ticket mode (/spec-all, /sa), the first reading that matches wins:
      1. "<key>:<id>", one token, <key> a registered project key (exact, case-sensitive)
                         -> kind ticket in that project; an id the project's ledger does not hold is refused
                            ("no such ticket in <key>") and NEVER looked up in the current project.
                            A near-miss is refused too, never captured as an idea: a registered key in another case, a
                            registered key with a space after the colon / words after the token / no id, and an
                            unregistered key whose id part is ticket-shaped (digits, letters+digits, the current
                            project's id pattern, or an id and a slug judged by its id part). Any other text with a
                            colon ("note: ..", "see:docs") is an idea.
      2. a bare token equal to a registered key, no other words
                         -> kind project-next (the next eligible ticket of that project, then stop). When the same
                            token is also the id shape or a slug of the current project, it is ambiguous: refused.
      2b. "<id>_<slug>" as the queue file prints it (also with ".md" or as a path to the spec file)
                         -> kind local-id when the id has the current project's shape, else kind ticket in the one
                            registered project whose own id shape it has. Id and slug must both be in that ledger,
                            else refused. The full id of another project, no slug, is read the same way (the shared
                            default shape ^S\d{4}$ and a legacy shape name no owner). "<key>:<id>_<slug>" is read
                            in step 1.
      3. the current project's own id shape (grammar.ticketIdPattern, default ^S\d{4}$)  -> kind local-id
         "-<number>"     -> kind local-id: the current project's ticket whose id ends in that number, else refused
      4. a slug of the current project's ledger (the whole name)                          -> kind local-slug
      5. anything else                                                                    -> kind idea
         (a lower-case token with a hyphen or underscore that names no slug is refused as an unknown slug, and a
         token shaped like a ticket reference that no project claims is refused too: a bare word by the usual id shape,
         an id and a slug by its id part - a letter-run that holds a digit, a mistyped id included)
    Next mode (/spec-next, /sn): no argument -> project-next in the current project; a bare registered key ->
    project-next there; "<key>:<id>" -> refused (next takes no ticket); anything else -> refused.

    Output: one JSON object on stdout, always (-Json is accepted and changes nothing):
      { kind, project, root, id, slug, reason }
      kind: ticket | project-next | local-id | local-slug | idea | ambiguous | refused
    Exit codes: 0 a resolved reading (ticket, project-next, local-id, local-slug, idea); 2 ambiguous or refused.
    Reads the registry and the ledgers; writes nothing, locks nothing, launches nothing.

.PARAMETER Arg
    The raw argument text of the command.
.PARAMETER Mode
    ticket (default, /spec-all) or next (/spec-next).
.PARAMETER CurrentProject
    The folder the command was typed in; the project is the first profile at or above it. Default: the current location.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string] $Arg = '',
    [ValidateSet('ticket', 'next')] [string] $Mode = 'ticket',
    [string] $CurrentProject = '',
    [switch] $Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/inbox.ps1')   # Read-PqRegistry, ConvertTo-PqPathKey, Read-PqLedgerRows

function Out-Reading([string] $Kind, $Project, $Root, $Id, $Slug, [string] $Reason) {
    $o = [ordered]@{ kind = $Kind; project = $Project; root = $Root; id = $Id; slug = $Slug; reason = $Reason }
    Write-Output (ConvertTo-Json -InputObject $o -Compress)
    if ($Kind -in @('ambiguous', 'refused')) { exit 2 }
    exit 0
}

$text = ([string]$Arg).Trim()
$isToken = ($text.Length -gt 0 -and $text -notmatch '\s')

# ---- the registry (it may be missing: the current project is still answerable) ----
$repos = @()
try {
    $read = Read-PqRegistry
    if ($read.ok) { $repos = @($read.registry.repos) }
}
catch { $repos = @() }
$registered = @($repos | Where-Object { Test-PqKeyValue ([string]$_.key) })

function Get-RegisteredProject([string] $Key) {
    return (@($registered | Where-Object { [string]$_.key -ceq $Key }) | Select-Object -First 1)
}

# ---- the current project, the way quiz-list.ps1 finds it ----
$hereRoot = $null
$start = if ($CurrentProject) { $CurrentProject } else { (Get-Location).Path }
$dir = $start
while ($dir) {
    if ((Test-Path -LiteralPath (Join-Path $dir '.sza-profile.json') -PathType Leaf) -or (Test-Path -LiteralPath (Join-Path $dir '.sza-canon.json') -PathType Leaf)) { $hereRoot = $dir; break }
    $parent = Split-Path -Parent $dir
    if (-not $parent -or $parent -eq $dir) { break }
    $dir = $parent
}
$hereKey = $null
if ($hereRoot) {
    $k = ConvertTo-PqPathKey $hereRoot
    $hit = @($repos | Where-Object { (ConvertTo-PqPathKey ([string]$_.path)) -ceq $k }) | Select-Object -First 1
    $hereKey = if ($hit) { [string]$hit.key } else { Split-Path -Leaf $hereRoot }
}

$defaultIdPattern = '^S\d{4}$'

# One key of a project's profile grammar, or $null when the profile, the object or the key is absent or unreadable.
function Get-Grammar([string] $Root, [string] $Name) {
    $file = [IO.Path]::Combine($Root, '.sza-profile.json')
    if (-not [IO.File]::Exists($file)) { return $null }
    try {
        $p = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($file)) -DateKind String
        return $p.grammar.$Name
    }
    catch { return $null }
}

function Get-IdPattern([string] $Root) {
    $pattern = [string](Get-Grammar $Root 'ticketIdPattern')
    if (-not $pattern) { $pattern = $defaultIdPattern }
    # TASK-FLOW 0.37: the id shapes of the repository before its prefix migration still name its tickets.
    $legacy = @(@(Get-Grammar $Root 'legacyTicketIdPatterns') | Where-Object { $_ } | ForEach-Object { [string]$_ })
    if ($legacy.Count) { $pattern = '(?:' + ((@($pattern) + $legacy) -join ')|(?:') + ')' }
    return $pattern
}

function Test-IdShape([string] $Root, [string] $Token) {
    try { return [regex]::IsMatch($Token, (Get-IdPattern $Root), [Text.RegularExpressions.RegexOptions]::IgnoreCase) } catch { return $false }
}

# The registered projects whose OWN id shape a full id has, so that it names its ticket from any folder. The shared
# default shape says nothing about the owner, and a legacy shape is shared the same way: neither is read here.
function Get-OwningProjects([string] $Id) {
    return @($registered | Where-Object {
            $own = [string](Get-Grammar ([string]$_.path) 'ticketIdPattern')
            if (-not $own -or $own -ceq $defaultIdPattern) { return $false }
            try { return [regex]::IsMatch($Id, $own, [Text.RegularExpressions.RegexOptions]::IgnoreCase) } catch { return $false }
        })
}

# A token written the way the queue file prints a ticket, "<id>_<slug>", also as the spec file's name or a path to it;
# $null for any other shape. The caller decides whether the id part is a ticket id.
function Split-Stem([string] $Token) {
    $stem = ($Token -split '[\\/]')[-1] -replace '\.md$', ''
    if ($stem -notmatch '^([^_:]+)_(.+)$') { return $null }
    return [pscustomobject]@{ id = $Matches[1]; slug = $Matches[2]; stem = $stem }
}

# Whether the id part of an id and a slug is shaped like a ticket id: it starts with a letter and holds a digit, or has the
# current project's id shape. Loose on purpose - a mistyped number, or a letter typed for a digit, still names a ticket and
# is never free text.
function Test-StemIdShaped([string] $Id) {
    if ($Id -match '^[A-Za-z][A-Za-z0-9-]*\d') { return $true }
    return ($hereRoot -and (Test-IdShape $hereRoot $Id))
}

function Read-Rows([string] $Root) {
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return $null }
    try { return @(Read-PqLedgerRows $Root) } catch { return $null }
}

function Find-Slug($Rows, [string] $Token) {
    return (@($Rows | Where-Object { $_.Name -ieq $Token }) | Select-Object -First 1)
}

# The row whose id is the one asked for, else the row that lists it among its former ids (TASK-FLOW 0.37: an old id
# is a name of its ticket; CANONR-0195 G4).
function Find-IdRow($Rows, [string] $Id) {
    $row = @($Rows | Where-Object { $_.Id -ieq $Id }) | Select-Object -First 1
    if ($row) { return $row }
    return (@($Rows | Where-Object { $_.PSObject.Properties['FormerIds'] -and @($_.FormerIds) -icontains $Id }) | Select-Object -First 1)
}

function Find-Number($Rows, [string] $Digits) {
    return @($Rows | Where-Object { $m = [regex]::Match($_.Id, '(\d+)$'); $m.Success -and [int64]$m.Groups[1].Value -eq [int64]$Digits })
}

# One project's ticket for an id, with or without its slug. Both parts must be in the ledger: anything else is refused,
# never captured as an idea and never reduced to the id alone, which could name another ticket.
function Out-LedgerTicket([string] $Kind, [string] $Key, [string] $Root, [string] $Id, $Stem) {
    $rows = Read-Rows $Root
    if ($null -eq $rows) { Out-Reading 'refused' $Key $Root $null $null "project $Key is registered but its folder or ledger cannot be read ($Root)" }
    $row = Find-IdRow $rows $Id
    if (-not $row) { Out-Reading 'refused' $Key $Root $null $null "no such ticket in ${Key}: '$Id' is not in its ledger (a ticket in the archive journal is named by its bare id)" }
    if ($Stem -and $row.Name -ine $Stem.slug -and (($row.File -split '[\\/]')[-1] -replace '\.md$', '') -ine $Stem.stem) {
        Out-Reading 'refused' $Key $Root $null $null "no such ticket in ${Key}: $($row.Id) is '$($row.Name)', not '$($Stem.slug)'"
    }
    Out-Reading $Kind $Key $Root $row.Id $row.Name "ticket $($row.Id) of project $Key"
}

function Get-Keys { if ($registered.Count) { (@($registered | ForEach-Object { [string]$_.key }) -join ', ') } else { 'none registered' } }

$noHere = "no project here - no .sza-profile.json or .sza-canon.json at or above $start; name one as <key>:<id> (registered: $(Get-Keys))"

# ---- next mode ----
if ($Mode -eq 'next') {
    if ($text.Length -eq 0) {
        if (-not $hereRoot) { Out-Reading 'refused' $null $null $null $null $noHere }
        Out-Reading 'project-next' $hereKey $hereRoot $null $null "no argument: the next ticket of the current project $hereKey"
    }
    if ($isToken) {
        $proj = Get-RegisteredProject $text
        if ($proj) { Out-Reading 'project-next' ([string]$proj.key) ([string]$proj.path) $null $null "project key: the next ticket of $($proj.key)" }
        if ($text -match '^([a-z][a-z0-9-]*):\S+$' -and (Get-RegisteredProject $Matches[1])) {
            Out-Reading 'refused' $Matches[1] $null $null $null "/spec-next takes no ticket: '$text' names one - use /spec-all $text, or /spec-next $($Matches[1]) for the next ticket of that project"
        }
    }
    Out-Reading 'refused' $null $null $null $null "/spec-next takes no argument or a project key; '$text' is neither (registered: $(Get-Keys))"
}

# ---- ticket mode ----
if ($text.Length -eq 0) { Out-Reading 'refused' $null $null $null $null 'no ticket and no idea given' }

# 1. <key>:<id>
if ($isToken -and $text -match '^([a-z][a-z0-9-]*):(\S+)$') {
    $key = $Matches[1]; $want = $Matches[2]
    $proj = Get-RegisteredProject $key
    if ($proj) {
        $root = [string]$proj.path
        $stem = Split-Stem $want
        if ($stem -and (Test-IdShape $root $stem.id)) { Out-LedgerTicket 'ticket' $key $root $stem.id $stem }
        $rows = Read-Rows $root
        if ($null -eq $rows) { Out-Reading 'refused' $key $root $null $null "project $key is registered but its folder or ledger cannot be read ($root)" }
        $hits = @(Find-IdRow $rows $want)
        if ($hits.Count -eq 0 -and $want -match '^\d+$') { $hits = @(Find-Number $rows $want) }
        if ($hits.Count -eq 0) { Out-Reading 'refused' $key $root $null $null "no such ticket in ${key}: '$want' is not in its ledger" }
        if ($hits.Count -gt 1) { Out-Reading 'ambiguous' $key $root $null $null "'$want' matches several tickets in ${key} ($(@($hits | ForEach-Object { $_.Id }) -join ', ')); use the full id" }
        Out-Reading 'ticket' $key $root $hits[0].Id $hits[0].Name "ticket $($hits[0].Id) of project $key"
    }
}

# 1b. a near-miss of "<key>:<id>" is never an idea (it would be captured as a Draft in the CURRENT project and worked):
#     a registered key spelled in another case, a registered key with a space after the colon or words after the token,
#     a registered key with no id, and an unregistered key whose id part looks like a ticket id.
$firstWord = ($text -split '\s+')[0]
if ($firstWord -match '^([A-Za-z][A-Za-z0-9_-]*):(.*)$') {
    $nmKey = $Matches[1]; $nmRest = $Matches[2]
    $exact = Get-RegisteredProject $nmKey
    $caseHit = @($registered | Where-Object { [string]$_.key -ieq $nmKey }) | Select-Object -First 1
    if ($exact) {
        # An exact registered key that reached here was not one clean "<key>:<id>" token (that returned above).
        Out-Reading 'refused' $nmKey $null $null $null "malformed project reference '$text': write exactly ${nmKey}:<id> as one word (no space, no words after it); free text may not begin with '${nmKey}:'"
    }
    if ($caseHit) {
        Out-Reading 'refused' ([string]$caseHit.key) $null $null $null "project keys are case-sensitive: '$nmKey' is not registered, '$($caseHit.key)' is - write $($caseHit.key):<id>"
    }
    # An id and a slug after the colon ("<key>:<id>_<slug>", its file name or path) is judged by its id part, and before the
    # path is split below: the split keeps the last folder only, which dropped the key and answered with a ticket of the
    # current project (CANONR-0199). A drive letter is not a key - one letter before the colon, nothing is read after "P:\".
    $nmStem = if ($nmKey.Length -eq 1 -and $nmRest -match '^[\\/]') { $null } else { Split-Stem $nmRest }
    if ($isToken -and $nmRest.Length -gt 0 -and ($nmRest -match '^\d+$' -or $nmRest -match '^[A-Za-z]{1,8}-?\d+$' -or ($hereRoot -and (Test-IdShape $hereRoot $nmRest)) -or ($nmStem -and (Test-StemIdShaped $nmStem.id)))) {
        Out-Reading 'refused' $null $null $null $null "unknown project '$nmKey' in '$text' (registered: $(Get-Keys)); nothing was captured and no ticket of the current project was touched"
    }
}

# 2. a bare registered project key
if ($isToken) {
    $proj = Get-RegisteredProject $text
    if ($proj) {
        if ($hereRoot) {
            $localId = Test-IdShape $hereRoot $text
            $localSlug = $null
            $hereRows = Read-Rows $hereRoot
            if ($null -ne $hereRows) { $localSlug = Find-Slug $hereRows $text }
            if ($localId -or $localSlug) {
                $as = if ($localId) { 'ticket id' } else { "slug of $($localSlug.Id)" }
                Out-Reading 'ambiguous' ([string]$proj.key) ([string]$proj.path) $null $text "ambiguous: '$text' is the registered project $($proj.key) and also a local $as in $hereKey; use $($proj.key):<id> or the slug with its id"
            }
        }
        Out-Reading 'project-next' ([string]$proj.key) ([string]$proj.path) $null $null "project key: the next eligible ticket of $($proj.key), then stop"
    }
}

# 2b. "<id>_<slug>" of this or another project, and the full id of another project: both work from any folder
if ($isToken) {
    $stem = Split-Stem $text
    $id = if ($stem) { $stem.id } else { $text }
    $isLocal = ($hereRoot -and (Test-IdShape $hereRoot $id))
    if ($stem -and $isLocal) { Out-LedgerTicket 'local-id' $hereKey $hereRoot $id $stem }
    if (-not $isLocal) {
        $owners = @(Get-OwningProjects $id)
        if ($owners.Count -gt 1) { Out-Reading 'ambiguous' $null $null $null $null "'$id' is an id shape of several projects ($(@($owners | ForEach-Object { $_.key }) -join ', ')); use <key>:<id>" }
        if ($owners.Count -eq 1) { Out-LedgerTicket 'ticket' ([string]$owners[0].key) ([string]$owners[0].path) $id $stem }
    }
}

# 3-5. local readings need the current project
if (-not $hereRoot) { Out-Reading 'refused' $null $null $null $null $noHere }

# 3a. "-<number>": the current project's ticket with that number
if ($text -match '^-(\d{1,9})$') {
    $digits = $Matches[1]
    $rows = Read-Rows $hereRoot
    if ($null -eq $rows) { Out-Reading 'refused' $hereKey $hereRoot $null $null "the ledger of $hereKey cannot be read ($hereRoot)" }
    $hits = @(Find-Number $rows $digits)
    if ($hits.Count -eq 0) { Out-Reading 'refused' $hereKey $hereRoot $null $null "no such ticket in ${hereKey}: no id in its ledger has the number '$digits'" }
    if ($hits.Count -gt 1) { Out-Reading 'ambiguous' $hereKey $hereRoot $null $null "'$text' matches several tickets in ${hereKey} ($(@($hits | ForEach-Object { $_.Id }) -join ', ')); use the full id" }
    Out-Reading 'local-id' $hereKey $hereRoot $hits[0].Id $hits[0].Name "ticket $($hits[0].Id) of the current project $hereKey"
}

if ($isToken -and (Test-IdShape $hereRoot $text)) {
    $rows = Read-Rows $hereRoot
    $row = if ($null -ne $rows) { Find-IdRow $rows $text } else { $null }
    $id = if ($row) { $row.Id } else { $text }
    $why = if ($row) { "ticket $id of the current project $hereKey" } else { "id shape of $hereKey; the ledger does not hold it yet (spec-preamble reports exit 2)" }
    Out-Reading 'local-id' $hereKey $hereRoot $id $(if ($row) { $row.Name } else { $null }) $why
}

if ($isToken) {
    $rows = Read-Rows $hereRoot
    if ($null -ne $rows) {
        $row = Find-Slug $rows $text
        if ($row) { Out-Reading 'local-slug' $hereKey $hereRoot $row.Id $row.Name "slug of $($row.Id) in the current project $hereKey" }
    }
    if ($text -cmatch '^[a-z0-9]+([-_][a-z0-9]+)+$') {
        Out-Reading 'refused' $hereKey $hereRoot $null $null "unknown slug '$text' in $hereKey (a partial word is not searched; free text is an idea - put it in words)"
    }
    # One word shaped like a ticket reference that no project claims is a mistyped ticket, never an idea. With an id and a slug
    # the id part alone decides, loosely: a mistyped id is a ticket reference too (CANONR-0199).
    $shaped = if ($stem) { Test-StemIdShaped $stem.id } else { $text -match '^[A-Za-z]{1,8}-?\d{4,}(_\S*)?$' }
    if ($shaped) {
        Out-Reading 'refused' $hereKey $hereRoot $null $null "no such ticket: '$text' is shaped like a ticket reference and neither $hereKey nor a registered project claims it"
    }
}

Out-Reading 'idea' $hereKey $hereRoot $null $null "free text: capture as a Draft in the current project $hereKey"
