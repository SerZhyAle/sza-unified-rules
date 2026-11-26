<#
.SYNOPSIS
    Give this repository its own ticket prefix, once: new ids become <PREFIX>-####, and every open ticket is renamed.
.DESCRIPTION
    TASK-FLOW 0.37 (rule 2, canon ticket S0152). The one tool-driven change of the id prefix a repository is allowed.
    Inside the ledger lock it:
      1. writes grammar.ticketIdPattern '^<PREFIX>-\d{N}$' into .sza-profile.json and moves the old pattern into
         grammar.legacyTicketIdPatterns (a declared grammar.specFilePattern gets both shapes);
      2. renames every ticket of the old shape whose status is not Verified or Archived: the number is kept
         (S4466 -> FMSAND-4466), the ledger row gets the new id and file and lists the old id in `formerIds`, the
         spec file and its folder are renamed, and every mention of the old file name in the specs is rewritten;
      3. rewrites the old id inside the token lines of the specs (`Blocker:`, `Блокер:`, `Carrier:`, `Blocks:`) and
         inside `statusNote` and `blocked_by` of the ledger rows, the rows of the three plan files and this
         repository's rows of the portfolio queue file;
      4. with -AllRepos, also the `<key>:<old id>` token lines in the specs of every other registered repository;
      5. retags the status-bound debug probes of the renamed tickets in source (probes.scanRoots, the project's probe
         form): the old id inside each probe becomes the new one, because every probe gate matches the current id only
         (CANONR-0158); the dry run lists each probe it would retag;
      6. re-renders the `-IdRegex` default of the scaffold's R0 launcher (r0.ps1 in the root, when it has that line)
         from the new grammar - the new shape and every legacy one - so its queue-file reader keeps finding the
         tickets (CANONR-0157). A repository that migrated before steps 5 and 6 runs the same -Prefix again: the ids are
         already that shape, so only the launcher is re-rendered and the probes of the open tickets that still carry
         one of their `formerIds` are retagged.
    Closed tickets keep their old ids; the burned list is not touched, so the next id continues after the highest old
    number. An old id stays a name of its ticket: the status tool, block-links.ps1 and the portfolio queue resolve it
    through `formerIds`.
    With -Correct (TASK-FLOW 0.39, section 17) the same run changes a prefix that an earlier migration already wrote:
    the owner ordered a different prefix after the repository had migrated. The tickets of the current shape that are
    not Verified or Archived are renamed, the current pattern joins grammar.legacyTicketIdPatterns (the list grows, it
    is never replaced), and `formerIds` gains the id the ticket carried before this run.
    Stop the portfolio robots for this repository before the run: a pass that holds a ticket open keeps its old path.
.PARAMETER Prefix
    The new prefix: six characters, an upper-case letter then upper-case letters or digits (FMSAND, D2HTML).
.PARAMETER DryRun
    Print every change and write nothing.
.PARAMETER AllRepos
    Also rewrite `<key>:<old id>` tokens in the specs of the other repositories of the portfolio registry.
.PARAMETER Correct
    Change a prefix that an earlier migration wrote (the owner's correction). Without it a repository that already
    migrated is refused; with it a repository that has not migrated is refused.
.NOTES
    Exit codes: 0 done (or nothing to do, or a dry run); 1 an error; 2 refused - a bad prefix, a repository that
    already migrated (no -Correct), -Correct on a repository that has not migrated, a prefix the repository carried
    before, an id shape that cannot be renamed, a target file that exists, no profile file, or a newest
    installed sza plugin whose harness predates TASK-FLOW 0.37 (a dry run is not refused for that).
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string] $Prefix,
    [switch] $DryRun,
    [switch] $AllRepos,
    [switch] $Correct,
    [switch] $Help
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')

if ($Help) {
    Show-SzaHelp $PSCommandPath
    exit $LASTEXITCODE
}

trap {
    Write-Host $_ -ForegroundColor Red
    if (Get-Command Exit-CatalogLock -ErrorAction SilentlyContinue) { Exit-CatalogLock }
    exit 1
}

. (Join-Path $PSScriptRoot '_lib.ps1')

function Stop-Rename([string] $Message) {
    Write-Host "rename-prefix: $Message" -ForegroundColor Red
    Exit-CatalogLock
    exit 2
}
function Write-Rp([string] $Text, [string] $Color = 'Gray') { Write-Host "rename-prefix: $Text" -ForegroundColor $Color }

if (-not $Prefix -or $Prefix -cnotmatch '^[A-Z][A-Z0-9]{5}$') {
    Stop-Rename "-Prefix '$Prefix' is not six characters, an upper-case letter then upper-case letters or digits (FMSAND, D2HTML)."
}

$root = Get-SzaProjectRoot
$profileFile = Join-Path $root '.sza-profile.json'
if (-not (Test-Path -LiteralPath $profileFile -PathType Leaf)) { Stop-Rename "$root has no .sza-profile.json; the new id shape is written there." }

# The R0 launcher of the scaffold (init-task-flow.ps1, r0.ps1 in the root) carries the id shape as a rendered literal,
# the default of its -IdRegex parameter; it is re-rendered from the profile's grammar after every change of it
# (CANONR-0157), so its queue-file reader keeps recognising the renamed ids and the old ones beside them.
$launcherFile = Join-Path $root 'r0.ps1'
$launcherLine = [regex]::new('(?m)^(?<head>[ \t]*\[string\][ \t]+\$IdRegex[ \t]*=[ \t]*)''(?:[^'']|'''')*''')
function Update-RpLauncher([switch] $Plan) {
    if (-not (Test-Path -LiteralPath $launcherFile -PathType Leaf)) { return }
    $text = [IO.File]::ReadAllText($launcherFile)
    if (-not $launcherLine.IsMatch($text)) { return }
    $fragment = if ($Plan) { $script:plannedFragment } else { Get-SzaTicketIdFragment }
    $literal = "'" + $fragment.Replace("'", "''") + "'"
    $new = $launcherLine.Replace($text, { param($m) $m.Groups['head'].Value + $literal }, 1)
    if ($new -ceq $text) { return }
    if ($Plan) { Write-Rp "  would set the -IdRegex default of $launcherFile to $literal" 'DarkGray'; return }
    $bytes = [IO.File]::ReadAllBytes($launcherFile)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    [IO.File]::WriteAllText($launcherFile, $new, [Text.UTF8Encoding]::new($bom))
    Write-Rp "the -IdRegex default of $launcherFile is now $literal" 'Green'
}

function Read-RpText([string] $Path) {
    $t = [IO.File]::ReadAllText($Path)
    if ($t.Length -gt 0 -and $t[0] -eq [char]0xFEFF) { $t = $t.Substring(1) }
    return $t
}
function Write-RpText([string] $Path, [string] $Text) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($bom))
}

# The status-bound debug probes carry the ticket id in source, and every probe gate matches the record's current id
# only (CANONR-0158), so a renamed ticket's probes are retagged with its new id: under probes.scanRoots, a call that
# is a probe of an old id by the project's own probe form (the one definition the gates use) gets the old id inside
# that form replaced, and nothing else in the file changes. Returns the number of source files changed.
function Update-RpProbes([hashtable] $Map, [switch] $Plan) {
    if ($Map.Count -eq 0 -or -not [bool](Get-SzaProfileValue 'probes.enabled')) { return 0 }
    . (Get-SzaHarnessScript 'spec_catalog/lib/blockneedusertest-probes.ps1')
    $roots = @(Get-ProbeSourceRoot -RepoRoot $root)
    if ($roots.Count -eq 0) { return 0 }
    $openerRx = Get-TimberOpenerRegex
    $formById = @{}
    foreach ($k in $Map.Keys) { $formById[$k] = Get-TimberProbeFormRegexForId -Id $k }
    $files = 0
    foreach ($file in (Get-ProbeSourceFile -SourceRoots $roots)) {
        $text = Read-RpText $file.FullName
        if ([string]::IsNullOrEmpty($text)) { continue }
        $mentioned = @($Map.Keys | Where-Object { $text.Contains($_) })
        if ($mentioned.Count -eq 0) { continue }
        $edits = [System.Collections.Generic.List[object]]::new()
        foreach ($m in $openerRx.Matches($text)) {
            $span = (Get-SanitizedTimberCallSpan -Content $text -PrefixStart $m.Index -OpenParenIndex ($m.Index + $m.Length - 1)).Span
            foreach ($k in $mentioned) {
                $fm = $formById[$k].Match($span)
                if (-not $fm.Success) { continue }
                $hit = Get-ProbeHitAt -Content $text -Match $m -FullName $file.FullName
                $im = [regex]::Match($fm.Value, '(?<![A-Za-z0-9])' + [regex]::Escape($k) + '(?![A-Za-z0-9])')
                if ($null -ne $hit -and $im.Success) {
                    $edits.Add([pscustomobject]@{ at = $m.Index + $fm.Index + $im.Index; oldId = $k; newId = $Map[$k]; line = $hit.Line })
                }
                break
            }
        }
        if ($edits.Count -eq 0) { continue }
        $files++
        foreach ($e in $edits) {
            $verb = if ($Plan) { 'would retag' } else { 'retagged' }
            Write-Rp ("  {0} the probe {1}:{2}  {3} -> {4}" -f $verb, $file.FullName, $e.line, $e.oldId, $e.newId) $(if ($Plan) { 'DarkGray' } else { 'Gray' })
        }
        if ($Plan) { continue }
        foreach ($e in @($edits | Sort-Object -Property at -Descending)) {
            $text = $text.Substring(0, $e.at) + $e.newId + $text.Substring($e.at + $e.oldId.Length)
        }
        Write-RpText $file.FullName $text
    }
    return $files
}

$old = Get-SzaTicketIdSpec
$newPrefix = $Prefix + '-'
if ($old.prefix -ceq $newPrefix) {
    # A repository that migrated before the launcher was re-rendered, or before the probes were retagged
    # (CANONR-0158), heals both by running the same prefix again: a probe of an open ticket that still carries one of
    # its formerIds gets the current id.
    if (-not $DryRun) { Update-RpLauncher } else { $script:plannedFragment = Get-SzaTicketIdFragment; Update-RpLauncher -Plan }
    $probeMap = @{}
    foreach ($r in (Read-Catalog)) {
        if (@('Verified', 'Archived') -contains [string]$r.status -or -not $r.PSObject.Properties['formerIds']) { continue }
        foreach ($f in @($r.formerIds)) { if ($f -and ([string]$f) -cne [string]$r.id) { $probeMap[[string]$f] = [string]$r.id } }
    }
    $probeFiles = Update-RpProbes -Map $probeMap -Plan:$DryRun
    $tail = if ($probeFiles -gt 0) { "; the probes in $probeFiles source file(s) $(if ($DryRun) { 'would carry' } else { 'now carry' }) the current ids" } else { '' }
    Write-Rp "the ids are already $newPrefix$('#' * $old.width); nothing else to do$tail." 'Green'; exit 0
}

# An attended session runs the harness of the newest installed plugin. One that predates TASK-FLOW 0.37 refuses every
# ledger write once the closed tickets' old ids no longer match the profile, so the migration waits for that release.
if (-not $DryRun) {
    $home_ = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
    $cache = if ($home_) { Join-Path $home_ '.claude/plugins/cache/sza-unified-rules/sza' } else { '' }
    if ($cache -and (Test-Path -LiteralPath $cache -PathType Container)) {
        $newest = Get-ChildItem -LiteralPath $cache -Directory -ErrorAction SilentlyContinue |
            Where-Object { $v = $null; [version]::TryParse($_.Name, [ref]$v) } |
            Sort-Object -Property @{ Expression = { [version]$_.Name }; Descending = $true } | Select-Object -First 1
        $reader = if ($newest) { Join-Path $newest.FullName 'tools/harness/_profile.ps1' } else { '' }
        if (-not $reader -or -not (Test-Path -LiteralPath $reader -PathType Leaf) -or -not ([IO.File]::ReadAllText($reader).Contains('legacyTicketIdPatterns'))) {
            $name = if ($newest) { $newest.Name } else { 'none' }
            Stop-Rename "the installed sza plugin ($name) predates TASK-FLOW 0.37 and would refuse this repository's ledger after the rename; install the canon release that ships rename-prefix.ps1 first (claude plugin update sza@sza-unified-rules)."
        }
    }
}
$legacySpecs = @(Get-SzaLegacyTicketIdSpecs)
if ($legacySpecs.Count -gt 0 -and -not $Correct) {
    Stop-Rename "this repository already moved its prefix once (grammar.legacyTicketIdPatterns is set); TASK-FLOW rule 2 allows one migration. The owner's correction of that prefix runs with -Correct (TASK-FLOW section 17)."
}
if ($Correct -and $legacySpecs.Count -eq 0) {
    Stop-Rename "-Correct changes a prefix that an earlier migration wrote, and this repository has not migrated (grammar.legacyTicketIdPatterns is empty); run without -Correct."
}
foreach ($l in $legacySpecs) {
    if ($l.prefix -ceq $newPrefix) { Stop-Rename "this repository carried the prefix $newPrefix before (grammar.legacyTicketIdPatterns); a correction does not return to it." }
}
$newPattern = '^' + [regex]::Escape($Prefix) + '-\d{' + $old.width + '}$'
$oldCore = ($old.pattern -replace '^\^', '') -replace '\$$', ''
$newCore = ($newPattern -replace '^\^', '') -replace '\$$', ''
$oldIdRegex = [regex]::new('^' + [regex]::Escape($old.prefix) + '(?<n>\d{' + $old.width + '})$', 'IgnoreCase')

# ---------------------------------------------------------------- the registry (read-only), for the portfolio files

$portfolioRoot = if ($env:SZA_PORTFOLIO_ROOT) { $env:SZA_PORTFOLIO_ROOT } else { Join-Path $env:USERPROFILE '.sza\portfolio' }
$registry = @()
$pqOverride = $null
$regFile = Join-Path $portfolioRoot 'repos.json'
if (Test-Path -LiteralPath $regFile -PathType Leaf) {
    try {
        $regDoc = Get-Content -LiteralPath $regFile -Raw | ConvertFrom-Json
        # TASK-FLOW 0.37 B(3): the queue file of rule 44 honours registry paths.portfolioQueue (CANONR-0195 G7).
        $pathsProp = $regDoc.PSObject.Properties['paths']
        if ($pathsProp -and $pathsProp.Value -and $pathsProp.Value.PSObject.Properties['portfolioQueue']) {
            $pqOverride = [string]$pathsProp.Value.portfolioQueue
        }
        foreach ($r in @($regDoc.repos)) {
            if ($r.key -and $r.path) { $registry += [pscustomobject]@{ key = [string]$r.key; path = [string]$r.path } }
        }
    } catch { Write-Rp "the portfolio registry $regFile cannot be read: $($_.Exception.Message)" 'Yellow' }
}
function ConvertTo-RpPathKey([string] $Path) {
    try { return ([IO.Path]::GetFullPath($Path)).TrimEnd('\', '/').ToLowerInvariant() } catch { return $Path.ToLowerInvariant() }
}
$selfKey = $null
foreach ($r in $registry) { if ((ConvertTo-RpPathKey $r.path) -eq (ConvertTo-RpPathKey $root)) { $selfKey = $r.key } }

# TASK-FLOW 0.37 A / 0.39 A: the prefix is unique across the registry of rule 41, current and former prefixes of
# every other registered repository included (CANONR-0195 G6).
function Get-RpRepoPrefixes([string] $RepoPath) {
    $out = @()
    $prof = Join-Path $RepoPath '.sza-profile.json'
    if (-not (Test-Path -LiteralPath $prof -PathType Leaf)) { return $out }
    try { $doc = Get-Content -LiteralPath $prof -Raw | ConvertFrom-Json } catch { return $out }
    $g = $doc.PSObject.Properties['grammar']
    if (-not $g -or -not $g.Value) { return $out }
    $pats = @()
    if ($g.Value.PSObject.Properties['ticketIdPattern']) { $pats += [string]$g.Value.ticketIdPattern }
    if ($g.Value.PSObject.Properties['legacyTicketIdPatterns']) {
        foreach ($l in @($g.Value.legacyTicketIdPatterns)) {
            if ($l -is [string]) { $pats += $l } elseif ($l -and $l.PSObject.Properties['pattern']) { $pats += [string]$l.pattern }
        }
    }
    foreach ($p in $pats) {
        $m = [regex]::Match($p, '^\^?(?<p>[A-Za-z][A-Za-z0-9]*-?)(?:\\d|\[0-9\])')
        if ($m.Success) { $out += $m.Groups['p'].Value }
    }
    return $out
}
foreach ($r in $registry) {
    if ((ConvertTo-RpPathKey $r.path) -eq (ConvertTo-RpPathKey $root)) { continue }
    foreach ($taken in @(Get-RpRepoPrefixes $r.path)) {
        if ($taken -ieq $newPrefix) { Stop-Rename "the prefix $newPrefix is already used by the registered repository '$($r.key)' ($($r.path)); prefixes are unique across the registry (TASK-FLOW section 15 item A)." }
    }
}

# ---------------------------------------------------------------- the plan

Enter-CatalogLock
$records = [System.Collections.Generic.List[object]]::new()
foreach ($r in (Read-Catalog)) { $records.Add($r) }

$closed = @('Verified', 'Archived')
$renames = [System.Collections.Generic.List[object]]::new()
foreach ($r in $records) {
    $m = $oldIdRegex.Match([string]$r.id)
    if (-not $m.Success -or $closed -contains [string]$r.status) { continue }
    $newId = $newPrefix + $m.Groups['n'].Value
    $fileRel = ([string]$r.file) -replace '\\', '/'
    $dirRel = [IO.Path]::GetDirectoryName($fileRel) -replace '\\', '/'
    $oldBase = [IO.Path]::GetFileNameWithoutExtension($fileRel)
    $newBase = if ($oldBase.StartsWith([string]$r.id, [StringComparison]::OrdinalIgnoreCase)) { $newId + $oldBase.Substring(([string]$r.id).Length) } else { $oldBase }
    $newFileRel = if ($dirRel) { "$dirRel/$newBase.md" } else { "$newBase.md" }
    $renames.Add([pscustomobject]@{
            oldId = [string]$r.id; newId = $newId; oldBase = $oldBase; newBase = $newBase
            former = @(if ($r.PSObject.Properties['formerIds']) { @($r.formerIds) | ForEach-Object { [string]$_ } })
            oldFile = Resolve-SpecPath -PathRef $fileRel; newFile = Resolve-SpecPath -PathRef $newFileRel; newFileRel = $newFileRel
            oldDir = Resolve-SpecPath -PathRef $(if ($dirRel) { "$dirRel/$oldBase" } else { $oldBase })
            newDir = Resolve-SpecPath -PathRef $(if ($dirRel) { "$dirRel/$newBase" } else { $newBase })
        })
}
$idMap = @{}
foreach ($x in $renames) { $idMap[$x.oldId.ToUpperInvariant()] = $x.newId }

foreach ($x in $renames) {
    if ($x.oldFile -ne $x.newFile -and (Test-Path -LiteralPath $x.newFile)) { Stop-Rename "$($x.newFile) exists already; nothing was changed." }
    if ((Test-Path -LiteralPath $x.oldDir -PathType Container) -and (Test-Path -LiteralPath $x.newDir)) { Stop-Rename "$($x.newDir) exists already; nothing was changed." }
}

# The profile: the declared spec-file pattern, if any, must carry the old shape so both can be written into it.
$profileDoc = Get-Content -LiteralPath $profileFile -Raw | ConvertFrom-Json -AsHashtable
if (-not $profileDoc.Contains('grammar') -or $null -eq $profileDoc['grammar']) { $profileDoc['grammar'] = [ordered]@{} }
$grammar = $profileDoc['grammar']
$declaredFilePattern = if ($grammar.Contains('specFilePattern')) { [string]$grammar['specFilePattern'] } else { '' }
if ($declaredFilePattern -and -not $declaredFilePattern.Contains($oldCore)) {
    Stop-Rename "grammar.specFilePattern '$declaredFilePattern' does not contain the id shape '$oldCore'; write both shapes into it by hand, then run again."
}

Write-Rp ("{0} -> {1}: {2} open ticket(s) renamed, closed tickets keep their ids{3}" -f $old.display, ($newPrefix + ('#' * $old.width)), $renames.Count, $(if ($DryRun) { ' (dry run)' } else { '' })) 'Cyan'
foreach ($x in $renames) { Write-Rp ("  {0} -> {1}  ({2})" -f $x.oldId, $x.newId, $x.newFileRel) }

# ---------------------------------------------------------------- text rewriting

function Convert-RpIdsInTokenLines([string] $Text, [string] $Qualifier) {
    # Rewrites old ids inside the literal tokens only - the id list right after `Blocker:`/`Блокер:`/`Carrier:`/
    # `Blocks:`, with or without a space (readers take `\s*`). An id later on the same line is prose, a mention,
    # and stays as written (TASK-FLOW 0.37 B(3); CANONR-0195 G8).
    $q = if ($Qualifier) { [regex]::Escape($Qualifier) + ':' } else { '' }
    $one = $q + [regex]::Escape($old.prefix) + '\d{' + $old.width + '}(?![A-Za-z0-9])'
    $tokenLine = [regex]::new('(?i)(?<![A-Za-z])(?:Blocker|Блокер|Carrier|Blocks)\s*:\s*\**\s*' + $one + '(?:\s*(?:,|;|\+|&|and)\s*' + $one + ')*')
    $idRe = [regex]::new($q + '(?<id>' + [regex]::Escape($old.prefix) + '\d{' + $old.width + '})(?![A-Za-z0-9])', 'IgnoreCase')
    return $tokenLine.Replace($Text, {
            param($line)
            $idRe.Replace($line.Value, {
                    param($m)
                    $k = $m.Groups['id'].Value.ToUpperInvariant()
                    if (-not $idMap.ContainsKey($k)) { return $m.Value }
                    return $m.Value.Substring(0, $m.Groups['id'].Index - $m.Index) + $idMap[$k]
                })
        })
}
function Convert-RpSelfTokens([string] $Text) {
    # This repository's own tokens: the bare id, and the id qualified with this repository's key.
    $Text = Convert-RpIdsInTokenLines $Text ''
    if ($selfKey) { $Text = Convert-RpIdsInTokenLines $Text $selfKey }
    return $Text
}
function Convert-RpBaseNames([string] $Text) {
    foreach ($x in $renames) {
        if ($x.oldBase -cne $x.newBase) { $Text = [regex]::Replace($Text, '(?<![A-Za-z0-9_-])' + [regex]::Escape($x.oldBase) + '(?![A-Za-z0-9_-])', $x.newBase) }
    }
    return $Text
}
function Get-RpSpecFiles([string] $RepoRoot, [string[]] $Dirs) {
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($d in $Dirs) {
        if (-not $d) { continue }
        $full = if ([IO.Path]::IsPathRooted($d)) { $d } else { Join-Path $RepoRoot $d }
        if (-not (Test-Path -LiteralPath $full -PathType Container)) { continue }
        foreach ($f in [IO.Directory]::EnumerateFiles($full, '*.md', [IO.SearchOption]::AllDirectories)) { if (-not $out.Contains($f)) { $out.Add($f) } }
    }
    return ,$out.ToArray()
}

$changedFiles = 0
function Update-RpFile([string] $Path, [scriptblock] $Convert) {
    $text = Read-RpText $Path
    $new = & $Convert $text
    if ($new -ceq $text) { return }
    $script:changedFiles++
    if ($DryRun) { Write-Rp "  would rewrite $Path" 'DarkGray'; return }
    Write-RpText $Path $new
}

if ($renames.Count -eq 0 -and $DryRun) { Exit-CatalogLock; exit 0 }

# 1. the profile
$legacy = [System.Collections.Generic.List[string]]::new()
if ($Correct) {
    # The earlier shapes stay valid: the list grows by the pattern that is being replaced.
    foreach ($p in @(Get-SzaProfileValue 'grammar.legacyTicketIdPatterns')) { if ($p -and -not $legacy.Contains([string]$p)) { $legacy.Add([string]$p) } }
}
$legacy.Add($old.pattern)
$grammar['ticketIdPattern'] = $newPattern
$grammar['legacyTicketIdPatterns'] = [string[]]$legacy.ToArray()
if ($declaredFilePattern) { $grammar['specFilePattern'] = $declaredFilePattern.Replace($oldCore, '(?:' + $newCore + '|' + $oldCore + ')') }
if ($DryRun) {
    Write-Rp "  would write grammar.ticketIdPattern '$newPattern' and grammar.legacyTicketIdPatterns ['$($old.pattern)'] into $profileFile" 'DarkGray'
    $plannedCores = @(@($newPattern) + $legacy.ToArray() | ForEach-Object { ($_ -replace '^\^', '') -replace '\$$', '' })
    $script:plannedFragment = if ($plannedCores.Count -eq 1) { $plannedCores[0] } else { '(?:' + ($plannedCores -join '|') + ')' }
    Update-RpLauncher -Plan
} else {
    $json = $profileDoc | ConvertTo-Json -Depth 32
    [IO.File]::WriteAllText($profileFile, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    # The grammar this process validates against is the new one from here on.
    $Script:SzaProfileCache = $null
    $script:FilePattern = [string](Get-SzaProfileValue 'grammar.specFilePattern')
    $script:IdPattern = [string](Get-SzaProfileValue 'grammar.ticketIdPattern')
    Update-RpLauncher
}

# 2. spec files and folders
if (-not $DryRun) {
    foreach ($x in $renames) {
        if ($x.oldFile -ne $x.newFile -and (Test-Path -LiteralPath $x.oldFile -PathType Leaf)) { Move-PathWithRetry -Source $x.oldFile -Destination $x.newFile }
        if ($x.oldDir -ne $x.newDir -and (Test-Path -LiteralPath $x.oldDir -PathType Container)) { Move-PathWithRetry -Source $x.oldDir -Destination $x.newDir -Directory }
    }
}

# 3. every spec of this repository: file names everywhere, ids in the token lines
$specDirs = @([string](Get-SzaProfileValue 'paths.specsDir'), [string](Get-SzaProfileValue 'paths.specArchiveDir'))
foreach ($f in (Get-RpSpecFiles $root $specDirs)) {
    Update-RpFile $f { param($t) Convert-RpSelfTokens (Convert-RpBaseNames $t) }
}
# the three plan files
foreach ($p in @((Get-ReleaseQueuePath), (Get-ReleaseReadyPath), (Get-ReleaseQueueDonePath))) {
    if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) { Update-RpFile $p { param($t) Convert-RpBaseNames $t } }
}
# this repository's rows of the portfolio queue file
$pqFile = if (-not $pqOverride) { Join-Path $portfolioRoot 'PORTFOLIO_QUEUE.md' }
          elseif ([IO.Path]::IsPathFullyQualified($pqOverride)) { $pqOverride }
          else { Join-Path $portfolioRoot $pqOverride }
if ($selfKey -and (Test-Path -LiteralPath $pqFile -PathType Leaf)) {
    Update-RpFile $pqFile {
        param($t)
        foreach ($x in $renames) {
            $t = [regex]::Replace($t, '(?m)^' + [regex]::Escape($selfKey + ':' + $x.oldBase) + '(?![A-Za-z0-9_-])', $selfKey + ':' + $x.newBase)
            $t = [regex]::Replace($t, '(?m)^' + [regex]::Escape($selfKey + ':' + $x.oldId) + '(?![A-Za-z0-9_-])', $selfKey + ':' + $x.newId)
        }
        return $t
    }
}
# 4. other repositories: `<key>:<old id>` in their token lines
if ($AllRepos) {
    if (-not $selfKey) {
        Write-Rp "this repository is not in the portfolio registry $regFile; no other repository names it by key." 'Yellow'
    } else {
        foreach ($r in $registry) {
            if ($r.key -ceq $selfKey -or -not (Test-Path -LiteralPath $r.path -PathType Container)) { continue }
            # The canon defaults come from _profile.ps1's table, the one place they are written.
            $dirs = @([string]$Script:SzaProfileDefaults.paths.specsDir, [string]$Script:SzaProfileDefaults.paths.specArchiveDir)
            $pf = Join-Path $r.path '.sza-profile.json'
            if (Test-Path -LiteralPath $pf -PathType Leaf) {
                try {
                    $pp = (Get-Content -LiteralPath $pf -Raw | ConvertFrom-Json).paths
                    if ($pp) { $dirs = @($dirs + @([string]$pp.specsDir, [string]$pp.specArchiveDir) | Where-Object { $_ } | Select-Object -Unique) }
                } catch { }
            }
            foreach ($f in (Get-RpSpecFiles $r.path $dirs)) {
                Update-RpFile $f { param($t) Convert-RpIdsInTokenLines $t $selfKey }
            }
        }
    }
}

# 5. the status-bound debug probes in source: the old id, and every id the ticket carried before it, become the new id
$probeMap = @{}
foreach ($x in $renames) { foreach ($f in @(@($x.oldId) + $x.former)) { if ($f -and $f -cne $x.newId) { $probeMap[$f] = $x.newId } } }
$script:changedFiles += (Update-RpProbes -Map $probeMap -Plan:$DryRun)

# 6. the ledger rows
if (-not $DryRun -and $renames.Count -gt 0) {
    $byOld = @{}
    foreach ($x in $renames) { $byOld[$x.oldId] = $x }
    foreach ($r in $records) {
        foreach ($field in 'statusNote', 'blocked_by') {
            $p = $r.PSObject.Properties[$field]
            if ($null -eq $p -or $null -eq $p.Value) { continue }
            if ($p.Value -is [string]) { $p.Value = Convert-RpSelfTokens ([string]$p.Value) }
            else { $p.Value = @(@($p.Value) | ForEach-Object { $k = ([string]$_).ToUpperInvariant(); if ($idMap.ContainsKey($k)) { $idMap[$k] } else { $_ } }) }
        }
        if (-not $byOld.ContainsKey([string]$r.id)) { continue }
        $x = $byOld[[string]$r.id]
        $former = @()
        if ($r.PSObject.Properties['formerIds']) { $former = @($r.formerIds) }
        $former = @($former + $x.oldId | Select-Object -Unique)
        if ($r.PSObject.Properties['formerIds']) { $r.formerIds = $former } else { $r | Add-Member -NotePropertyName 'formerIds' -NotePropertyValue $former }
        $r.id = $x.newId
        $r.file = $x.newFileRel
        $r.updated = Get-Now
    }
    Write-Catalog -Records ([object[]]$records.ToArray())
}
Exit-CatalogLock

$verb = if ($DryRun) { 'would change' } else { 'changed' }
Write-Rp ("{0} {1} text file(s); the next new id is {2}" -f $verb, $changedFiles, $(if ($DryRun) { '(after the run)' } else { (New-CatalogId) })) 'Green'
exit 0
