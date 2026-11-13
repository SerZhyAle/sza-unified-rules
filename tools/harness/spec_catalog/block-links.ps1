<#
.SYNOPSIS
    The back-link between a blocked ticket and its blockers, and the release of the tickets a blocker holds
    (TASK-FLOW rule 69).

.DESCRIPTION
    A ticket in BlockByOtherTask names its blockers (rule 9 and rule 52). This tool writes the other end of that
    wait into each blocker's spec file, and frees the waiting tickets when their blockers are released, inside one
    repository and across the registered repositories of the portfolio.

    The back-link is one line per waiting ticket under a `## Blocked tickets` heading of the BLOCKER's spec:

        - Blocks: <ref> | was: <status> | since: <yyyy-MM-dd>
        - Blocks: <ref> | was: <status> | since: <yyyy-MM-dd> | released: <yyyy-MM-dd> -> <status>

    <ref> is the waiting ticket's id when both tickets live in one repository, else <repoKey>:<id>. `was` is the
    status the waiting ticket had before it entered the block and is the status it is released to.

    Modes (one per call):

      -Link   -Id <waiting> [-Was <status>]
              Write or refresh the back-link in every blocker the waiting ticket names. update.ps1 and
              bulk-update.ps1 call this after a transition INTO BlockByOtherTask.
      -Release -Id <blocker>
              Check every ticket the blocker's open lines name; release each one whose blockers are all released,
              close the line of each one that is free or no longer blocked. update.ps1, bulk-update.ps1,
              close.ps1 and archive.ps1 call this after every status move of a ticket whose spec has open lines.
      -Check  -Id <waiting> [-Was <status>]
              Release one waiting ticket of THIS repository if nothing holds it any more. A session that removed a
              Blocker: token by hand (the dependency ended for a reason no status shows) runs this.
      -Sweep  [-AllRepos]
              Every BlockByOtherTask ticket of this repository (or of every registered repository): write the
              missing back-links, then -Check it. How tickets blocked before rule 69 join it.

    -DryRun reports what would be written or moved and changes nothing.

    Set SZA_BLOCK_LINKS=0 to switch the automatic calls from the status tools off (the modes still run when
    called directly).

    Exit codes: 0 = done (including nothing to do); 1 = at least one waiting ticket could not be moved or a file
    could not be written - reported, the rest still processed; 2 = bad invocation or unknown ticket.

    Compatible with PowerShell 7+. Prints plain lines; -Check also prints one machine line
    `BLOCKLINKS-RESULT <json>` for the parent -Release that launched it in another repository.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch] $Link,
    [switch] $Release,
    [switch] $Check,
    [switch] $Sweep,
    [string] $Id,
    [string] $Was,
    [switch] $AllRepos,
    [switch] $DryRun,
    [switch] $Help
)

. (Join-Path $PSScriptRoot '..\_profile.ps1')
if ($Help) { Show-SzaHelp $PSCommandPath; exit 0 }

$modes = @($Link, $Release, $Check, $Sweep | Where-Object { $_ })
if ($modes.Count -ne 1) {
    Write-Host 'block-links.ps1: give exactly one of -Link, -Release, -Check, -Sweep (see -Help).' -ForegroundColor Red
    exit 2
}
if (-not $Sweep -and -not $Id) {
    Write-Host 'block-links.ps1: -Id is required for -Link, -Release and -Check.' -ForegroundColor Red
    exit 2
}

. (Join-Path $PSScriptRoot '_lib.ps1')
. (Join-Path $PSScriptRoot '_blocker-links.ps1')

$script:ActiveStatuses = @('Draft', 'Approved', 'Tactical', 'In Progress', 'Partial', 'Broken')
$script:Failures = 0
$script:Today = (Get-Date).ToString('yyyy-MM-dd')
$script:PwshExe = [Environment]::ProcessPath
if (-not $script:PwshExe -or -not (Test-Path -LiteralPath $script:PwshExe)) { $script:PwshExe = 'pwsh' }
$script:SelfRoot = [IO.Path]::GetFullPath((Get-SzaProjectRoot))

function Write-BlLine([string] $Text, [string] $Color = 'Gray') { Write-Host "block-links: $Text" -ForegroundColor $Color }

function Get-BlProp($Object, [string] $Name) {
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

# ---------------------------------------------------------------- the portfolio registry (read-only)

function ConvertTo-BlPathKey([string] $Path) {
    if (-not $Path) { return '' }
    try { $full = [IO.Path]::GetFullPath($Path) } catch { $full = $Path }
    return $full.TrimEnd('\', '/').ToLowerInvariant()
}

$script:Registry = $null
function Get-BlRegistry {
    if ($null -ne $script:Registry) { return $script:Registry }
    $root = if ($env:SZA_PORTFOLIO_ROOT) { $env:SZA_PORTFOLIO_ROOT } else { Join-Path $env:USERPROFILE '.sza\portfolio' }
    $file = Join-Path $root 'repos.json'
    $repos = @()
    if (Test-Path -LiteralPath $file -PathType Leaf) {
        try {
            $doc = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
            foreach ($r in @(Get-BlProp $doc 'repos')) {
                $key = [string](Get-BlProp $r 'key'); $path = [string](Get-BlProp $r 'path')
                if ($key -and $path) { $repos += [pscustomobject]@{ key = $key; path = $path } }
            }
        } catch { Write-BlLine "the portfolio registry $file cannot be read: $($_.Exception.Message)" 'Yellow' }
    }
    $script:Registry = $repos
    return $script:Registry
}

function Get-BlRepoPath([string] $Key) {
    foreach ($r in (Get-BlRegistry)) { if ($r.key -ceq $Key) { return $r.path } }
    return $null
}

function Get-BlKeyForRoot([string] $Root) {
    $want = ConvertTo-BlPathKey $Root
    foreach ($r in (Get-BlRegistry)) { if ((ConvertTo-BlPathKey $r.path) -eq $want) { return $r.key } }
    return $null
}

$script:SelfKey = Get-BlKeyForRoot $script:SelfRoot

# ---------------------------------------------------------------- records of this and of other repositories

# A record of another repository, read straight from its ledger and archive (rule 11) - never through this
# process's profile cache, which belongs to this repository. -> @{ id; status; statusNote; file (absolute) } or $null.
function Read-BlForeignRecord([string] $Root, [string] $TicketId) {
    # The canon defaults come from _profile.ps1's table, the one place they are written.
    $journal = [string]$Script:SzaProfileDefaults.paths.journal
    $archive = [string]$Script:SzaProfileDefaults.paths.journalArchive
    $profileFile = Join-Path $Root '.sza-profile.json'
    if (Test-Path -LiteralPath $profileFile -PathType Leaf) {
        try {
            $p = Get-Content -LiteralPath $profileFile -Raw | ConvertFrom-Json
            $paths = Get-BlProp $p 'paths'
            if ($paths) {
                if (Get-BlProp $paths 'journal') { $journal = [string](Get-BlProp $paths 'journal') }
                if (Get-BlProp $paths 'journalArchive') { $archive = [string](Get-BlProp $paths 'journalArchive') }
            }
        } catch { }
    }
    $needle = '"id":"' + $TicketId + '"'
    foreach ($rel in @($journal, $archive)) {
        $file = if ([IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path $Root $rel }
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        # ReadAllLines: a foreach over ReadLines left by return keeps the foreign ledger open, and the child update.ps1
        # this process starts in that repository is then refused its write.
        foreach ($line in [IO.File]::ReadAllLines($file)) {
            if ($line.IndexOf($needle, [StringComparison]::Ordinal) -lt 0) { continue }
            try { $row = $line | ConvertFrom-Json } catch { continue }
            if ([string](Get-BlProp $row 'id') -cne $TicketId) { continue }
            $f = [string](Get-BlProp $row 'file')
            $abs = if (-not $f) { $null } elseif ([IO.Path]::IsPathRooted($f)) { $f } else { Join-Path $Root ($f -replace '/', '\') }
            return [pscustomobject]@{ id = $TicketId; status = [string](Get-BlProp $row 'status'); statusNote = [string](Get-BlProp $row 'statusNote'); file = $abs }
        }
    }
    return $null
}

function Read-BlLocalRecord([string] $TicketId) {
    $r = Find-Record -Id $TicketId
    if (-not $r) { return $null }
    $f = [string](Get-BlProp $r 'file')
    $abs = if ($f) { Resolve-SpecPath -PathRef $f } else { $null }
    return [pscustomobject]@{ id = $TicketId; status = [string]$r.status; statusNote = [string](Get-BlProp $r 'statusNote'); file = $abs }
}

function Read-BlText([string] $File) {
    if (-not $File -or -not (Test-Path -LiteralPath $File -PathType Leaf)) { return '' }
    try { return [IO.File]::ReadAllText($File) } catch { return '' }
}

# The blockers a waiting ticket names, resolved: @{ ref; key; id; root; record; released; why }.
function Get-BlBlockersOf($Record) {
    $spec = Read-BlText $Record.file
    $out = @()
    foreach ($b in @(Get-BlockerLinks -SpecText $spec -StatusNote $Record.statusNote -SelfId $Record.id)) {
        $rec = Read-BlLocalRecord $b
        $rel = if ($rec) { Test-BlockerReleased -Status $rec.status -Id $b -File $rec.file } else { $false }
        $out += [pscustomobject]@{ ref = $b; key = $script:SelfKey; id = $b; root = $script:SelfRoot; record = $rec; released = [bool]$rel
            why = $(if ($rec) { "$b is $($rec.status)" } else { "$b is in neither the ledger nor the archive" }) }
    }
    foreach ($pair in @(Get-QualifiedBlockerLinks -SpecText $spec -StatusNote $Record.statusNote)) {
        $k, $i = $pair -split ':', 2
        if ($script:SelfKey -and $k -ceq $script:SelfKey) {
            if (@($out | Where-Object { $_.id -ceq $i }).Count -gt 0) { continue }
            $rec = Read-BlLocalRecord $i
            $rel = if ($rec) { Test-BlockerReleased -Status $rec.status -Id $i -File $rec.file } else { $false }
            $out += [pscustomobject]@{ ref = $i; key = $k; id = $i; root = $script:SelfRoot; record = $rec; released = [bool]$rel
                why = $(if ($rec) { "$i is $($rec.status)" } else { "$i is in neither the ledger nor the archive" }) }
            continue
        }
        $root = Get-BlRepoPath $k
        if (-not $root) {
            $out += [pscustomobject]@{ ref = $pair; key = $k; id = $i; root = $null; record = $null; released = $false; why = "no registered repository '$k'" }
            continue
        }
        $rec = Read-BlForeignRecord $root $i
        # Test-BlockerReleased resolves a relative plan path against THIS project; the foreign file is absolute.
        $rel = if ($rec) { Test-BlockerReleased -Status $rec.status -Id $i -File $rec.file } else { $false }
        $out += [pscustomobject]@{ ref = $pair; key = $k; id = $i; root = $root; record = $rec; released = [bool]$rel
            why = $(if ($rec) { "$pair is $($rec.status)" } else { "$pair is in neither its ledger nor its archive" }) }
    }
    return $out
}

# ---------------------------------------------------------------- the section in a blocker's spec

$script:SectionHeading = '## Blocked tickets'
$script:LinePattern = '^(?<indent>[ \t]*)-[ \t]+Blocks:[ \t]*(?<ref>(?:[a-z][a-z0-9-]*:)?[A-Za-z][A-Za-z0-9_-]*\d[A-Za-z0-9_-]*)(?<rest>[^\r\n]*)$'

function Read-BlFile([string] $Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $off = if ($bom) { 3 } else { 0 }
    $text = [Text.UTF8Encoding]::new($false).GetString($bytes, $off, $bytes.Length - $off)
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    return [pscustomobject]@{ text = $text; bom = $bom; nl = $nl }
}

function Write-BlFile([string] $Path, $Doc, [string] $Text) {
    $tmp = "$Path.blocklinks.tmp"
    $bytes = [Text.UTF8Encoding]::new($Doc.bom).GetPreamble() + [Text.UTF8Encoding]::new($false).GetBytes($Text)
    [IO.File]::WriteAllBytes($tmp, [byte[]]$bytes)
    Move-ReplaceFile -Source $tmp -Destination $Path
}

# The section's line range in a list of lines: @{ start (heading index); end (exclusive) } or $null.
function Get-BlSectionRange([string[]] $Lines) {
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^##[ \t]+Blocked tickets[ \t]*$') {
            $end = $Lines.Count
            for ($j = $i + 1; $j -lt $Lines.Count; $j++) { if ($Lines[$j] -match '^#{1,2}[ \t]') { $end = $j; break } }
            return @{ start = $i; end = $end }
        }
    }
    return $null
}

function ConvertFrom-BlLine([string] $Line) {
    $m = [regex]::Match($Line, $script:LinePattern)
    if (-not $m.Success) { return $null }
    $fields = @{}
    foreach ($part in ($m.Groups['rest'].Value -split '\|')) {
        $kv = [regex]::Match($part, '^[ \t]*(?<k>[a-z]+)[ \t]*:[ \t]*(?<v>.*?)[ \t]*$')
        if ($kv.Success) { $fields[$kv.Groups['k'].Value] = $kv.Groups['v'].Value }
    }
    return [pscustomobject]@{ ref = $m.Groups['ref'].Value; was = $fields['was']; since = $fields['since']; released = $fields['released'] }
}

# The open (not released) lines of a blocker's spec.
function Get-BlOpenLines([string] $File) {
    if (-not $File -or -not (Test-Path -LiteralPath $File -PathType Leaf)) { return @() }
    $doc = Read-BlFile $File
    $lines = $doc.text -split '\r?\n'
    $range = Get-BlSectionRange $lines
    if (-not $range) { return @() }
    $out = @()
    for ($i = $range.start + 1; $i -lt $range.end; $i++) {
        $l = ConvertFrom-BlLine $lines[$i]
        if ($l -and -not $l.released) { $out += $l }
    }
    return $out
}

# Add or refresh the open line of $Ref in $File. A known `was` on the old line survives a refresh without one.
function Set-BlBackLink([string] $File, [string] $Ref, [string] $WasStatus) {
    $doc = Read-BlFile $File
    $lines = [Collections.Generic.List[string]]::new([string[]]($doc.text -split '\r?\n'))
    $range = Get-BlSectionRange $lines.ToArray()
    $keepWas = $WasStatus
    $since = $script:Today
    $at = -1
    if ($range) {
        for ($i = $range.start + 1; $i -lt $range.end; $i++) {
            $l = ConvertFrom-BlLine $lines[$i]
            if ($l -and $l.ref -ceq $Ref -and -not $l.released) {
                $at = $i
                if (-not $keepWas -and $l.was) { $keepWas = $l.was }
                if ($l.since) { $since = $l.since }
                break
            }
        }
    }
    $new = "- Blocks: $Ref"
    if ($keepWas) { $new += " | was: $keepWas" }
    $new += " | since: $since"
    if ($at -ge 0) {
        if ($lines[$at] -ceq $new) { return 'unchanged' }
        $lines[$at] = $new
    }
    elseif ($range) {
        # After the last line of the section's list, or after the heading's intro paragraph.
        $insert = $range.end
        while ($insert -gt $range.start + 1 -and -not $lines[$insert - 1].Trim()) { $insert-- }
        $lines.Insert($insert, $new)
    }
    else {
        $block = @(
            $script:SectionHeading,
            '',
            'Tickets waiting on this one (TASK-FLOW rule 69). The status tools write a line when a ticket enters',
            '`BlockByOtherTask` and close it when that ticket is released; a moved status of this ticket triggers the check.',
            '',
            $new,
            ''
        )
        # Before an audit block, which is overwritten at the bottom of the spec; else at the end.
        $audit = -1
        for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^##[ \t]+(?:\d+\.[ \t]*)?Last Audit\b') { $audit = $i; break } }
        if ($audit -ge 0) {
            $lines.InsertRange($audit, [string[]]$block)
        }
        else {
            while ($lines.Count -gt 0 -and -not $lines[$lines.Count - 1].Trim()) { $lines.RemoveAt($lines.Count - 1) }
            $lines.Add('')
            $lines.AddRange([string[]]$block)
        }
    }
    if ($DryRun) { return 'would-write' }
    Write-BlFile $File $doc ($lines -join $doc.nl)
    return 'written'
}

function Close-BlBackLink([string] $File, [string] $Ref, [string] $Result) {
    $doc = Read-BlFile $File
    $lines = $doc.text -split '\r?\n'
    $range = Get-BlSectionRange $lines
    if (-not $range) { return $false }
    $changed = $false
    for ($i = $range.start + 1; $i -lt $range.end; $i++) {
        $l = ConvertFrom-BlLine $lines[$i]
        if ($l -and $l.ref -ceq $Ref -and -not $l.released) {
            $lines[$i] = $lines[$i].TrimEnd() + " | released: $($script:Today) -> $Result"
            $changed = $true
        }
    }
    if ($changed -and -not $DryRun) { Write-BlFile $File $doc ($lines -join $doc.nl) }
    return $changed
}

# ---------------------------------------------------------------- the modes

function Invoke-BlLink([string] $TicketId, [string] $WasStatus) {
    $rec = Read-BlLocalRecord $TicketId
    if (-not $rec) { Write-BlLine "$TicketId is not in this repository's ledger." 'Red'; return 2 }
    if ($WasStatus -and $script:ActiveStatuses -notcontains $WasStatus) { $WasStatus = '' }
    $blockers = @(Get-BlBlockersOf $rec)
    if ($blockers.Count -eq 0) { Write-BlLine "$TicketId names no blocker; nothing to link."; return 0 }
    $rc = 0
    foreach ($b in $blockers) {
        if (-not $b.record -or -not $b.record.file) { Write-BlLine "$TicketId -> $($b.ref): no back-link ($($b.why))." 'Yellow'; continue }
        $local = ($b.root -and (ConvertTo-BlPathKey $b.root) -eq (ConvertTo-BlPathKey $script:SelfRoot))
        if ($local) { $ref = $TicketId }
        elseif ($script:SelfKey) { $ref = "$($script:SelfKey):$TicketId" }
        else { Write-BlLine "$TicketId -> $($b.ref): this repository is not in the portfolio registry, so the other repository cannot name it; no back-link." 'Yellow'; continue }
        try {
            $r = Set-BlBackLink $b.record.file $ref $WasStatus
            Write-BlLine "$($b.ref) <- Blocks: $ref ($r)"
        } catch {
            Write-BlLine "$($b.ref): cannot write the back-link into $($b.record.file): $($_.Exception.Message)" 'Yellow'
            $rc = 1
        }
    }
    return $rc
}

# The status a released ticket returns to when its line carries no `was`: by its tactical plan.
function Get-BlFallbackStatus($Record) {
    $counter = Get-TacticalPhaseCounter -File $Record.file
    if ($counter) {
        $done = [int](($counter -split '/')[0])
        if ($done -gt 0) { return 'In Progress' }
        return 'Tactical'
    }
    if ($Record.file) {
        $folder = $Record.file -replace '\.md$', ''
        if ($folder -ne $Record.file -and (Test-Path -LiteralPath (Join-Path $folder 'INDEX.md'))) { return 'Tactical' }
    }
    return 'Draft'
}

# Release one waiting ticket of THIS repository if nothing holds it. -> @{ state; status; heldBy; message }
#   state: released | held | not-blocked | refused | missing
function Invoke-BlCheck([string] $TicketId, [string] $WasStatus) {
    $rec = Read-BlLocalRecord $TicketId
    if (-not $rec) { return [pscustomobject]@{ state = 'missing'; status = ''; heldBy = @(); message = "$TicketId is not in this repository's ledger or archive" } }
    if ($rec.status -cne 'BlockByOtherTask') { return [pscustomobject]@{ state = 'not-blocked'; status = $rec.status; heldBy = @(); message = "$TicketId is $($rec.status)" } }
    $blockers = @(Get-BlBlockersOf $rec)
    $holding = @($blockers | Where-Object { -not $_.released })
    if ($holding.Count -gt 0) {
        return [pscustomobject]@{ state = 'held'; status = $rec.status; heldBy = @($holding | ForEach-Object { $_.ref }); message = (($holding | ForEach-Object { $_.why }) -join '; ') }
    }
    $target = if ($WasStatus -and $script:ActiveStatuses -contains $WasStatus) { $WasStatus } else { Get-BlFallbackStatus $rec }
    $freedBy = if ($blockers.Count -gt 0) { (($blockers | ForEach-Object { $_.why }) -join ', ') } else { 'no blocker is named any more' }
    if ($DryRun) { return [pscustomobject]@{ state = 'released'; status = $target; heldBy = @(); message = "would move $TicketId BlockByOtherTask -> $target ($freedBy)" } }
    $note = "Released $($script:Today) by TASK-FLOW rule 69: $freedBy."
    $update = Join-Path $PSScriptRoot 'update.ps1'
    $saved = $env:SZA_PROJECT_ROOT
    $refusal = ''
    # The `was` status first; when its gate refuses (an Approved whose spec lost its Owner inputs section), one
    # level down to Draft, which no gate guards - the ticket must become workable, and Draft is where a pass starts.
    foreach ($try in @($target, 'Draft' | Select-Object -Unique)) {
        try {
            $env:SZA_PROJECT_ROOT = $script:SelfRoot
            $out = & $script:PwshExe -NoProfile -File $update -Id $TicketId -Status $try -StatusNote $note 2>&1 | Out-String
            $code = $LASTEXITCODE
        } finally { $env:SZA_PROJECT_ROOT = $saved }
        if ($code -eq 0) {
            $msg = "$TicketId BlockByOtherTask -> $try ($freedBy)"
            if ($refusal) { $msg += "; $target was refused: $refusal" }
            return [pscustomobject]@{ state = 'released'; status = $try; heldBy = @(); message = $msg }
        }
        $refusal = (($out -split '\r?\n') | Where-Object { $_.Trim() } | Select-Object -Last 1)
    }
    return [pscustomobject]@{ state = 'refused'; status = $rec.status; heldBy = @(); message = "update.ps1 refused $TicketId -> ${target}: $refusal" }
}

function Invoke-BlRelease([string] $TicketId) {
    $rec = Read-BlLocalRecord $TicketId
    if (-not $rec) { Write-BlLine "$TicketId is not in this repository's ledger." 'Red'; return 2 }
    $open = @(Get-BlOpenLines $rec.file)
    if ($open.Count -eq 0) { return 0 }
    $rc = 0
    foreach ($l in $open) {
        $k = $null; $i = $l.ref
        if ($l.ref.Contains(':')) { $k, $i = $l.ref -split ':', 2 }
        $local = (-not $k) -or ($script:SelfKey -and $k -ceq $script:SelfKey)
        if ($local) {
            $res = Invoke-BlCheck $i $l.was
        }
        else {
            $root = Get-BlRepoPath $k
            if (-not $root) { Write-BlLine "$($l.ref): no registered repository '$k'; line left open." 'Yellow'; $rc = 1; continue }
            $argv = @('-NoProfile', '-File', $PSCommandPath, '-Check', '-Id', $i)
            if ($l.was) { $argv += @('-Was', $l.was) }
            if ($DryRun) { $argv += '-DryRun' }
            $saved = $env:SZA_PROJECT_ROOT; $savedProfile = $env:SZA_PROFILE_PATH
            try {
                $env:SZA_PROJECT_ROOT = $root; $env:SZA_PROFILE_PATH = $null
                $out = & $script:PwshExe @argv 2>&1 | Out-String
            } finally { $env:SZA_PROJECT_ROOT = $saved; $env:SZA_PROFILE_PATH = $savedProfile }
            $m = [regex]::Match($out, 'BLOCKLINKS-RESULT (\{.*\})')
            if (-not $m.Success) { Write-BlLine "$($l.ref): the check in $root gave no result; line left open. $($out.Trim())" 'Yellow'; $rc = 1; continue }
            $res = $m.Groups[1].Value | ConvertFrom-Json
        }
        switch ($res.state) {
            'released' {
                Write-BlLine "$($l.ref) released: $($res.message)" 'Green'
                if (Close-BlBackLink $rec.file $l.ref $res.status) { }
            }
            'not-blocked' {
                Write-BlLine "$($l.ref) is no longer blocked ($($res.status)); line closed."
                [void](Close-BlBackLink $rec.file $l.ref $res.status)
            }
            'held' { Write-BlLine "$($l.ref) stays blocked: $($res.message)" }
            'refused' { Write-BlLine "$($l.ref) NOT released: $($res.message)" 'Yellow'; $rc = 1 }
            default { Write-BlLine "$($l.ref): $($res.message); line left open." 'Yellow'; $rc = 1 }
        }
    }
    return $rc
}

function Invoke-BlSweep {
    $rc = 0
    # foreach, not a pipeline: Read-Catalog hands back its array as one object.
    $blocked = @(foreach ($r in (Read-Catalog)) { if ([string]$r.status -ceq 'BlockByOtherTask') { $r } })
    if ($blocked.Count -eq 0) { Write-BlLine "no BlockByOtherTask ticket in $($script:SelfRoot)."; return 0 }
    foreach ($r in $blocked) {
        $id = [string]$r.id
        $lr = Invoke-BlLink $id ''
        if ($lr -ne 0) { $rc = 1 }
        $res = Invoke-BlCheck $id ''
        switch ($res.state) {
            'released' {
                Write-BlLine "$id released: $($res.message)" 'Green'
                # Close the lines this ticket's blockers carry for it.
                $self = if ($script:SelfKey) { "$($script:SelfKey):$id" } else { $id }
                foreach ($b in @(Get-BlBlockersOf (Read-BlLocalRecord $id))) {
                    if (-not $b.record -or -not $b.record.file) { continue }
                    $ref = if ($b.root -and (ConvertTo-BlPathKey $b.root) -eq (ConvertTo-BlPathKey $script:SelfRoot)) { $id } else { $self }
                    try { [void](Close-BlBackLink $b.record.file $ref $res.status) } catch { }
                }
            }
            'held' { Write-BlLine "$id stays blocked: $($res.message)" }
            'refused' { Write-BlLine "$id NOT released: $($res.message)" 'Yellow'; $rc = 1 }
            default { Write-BlLine "${id}: $($res.message)" 'Yellow' }
        }
    }
    return $rc
}

# ---------------------------------------------------------------- dispatch

if ($Sweep -and $AllRepos) {
    $rc = 0
    foreach ($r in (Get-BlRegistry)) {
        if (-not (Test-Path -LiteralPath $r.path -PathType Container)) { Write-BlLine "$($r.key): folder missing, skipped." 'Yellow'; continue }
        Write-BlLine "== $($r.key) ($($r.path))" 'Cyan'
        $argv = @('-NoProfile', '-File', $PSCommandPath, '-Sweep')
        if ($DryRun) { $argv += '-DryRun' }
        $saved = $env:SZA_PROJECT_ROOT; $savedProfile = $env:SZA_PROFILE_PATH
        try {
            $env:SZA_PROJECT_ROOT = $r.path; $env:SZA_PROFILE_PATH = $null
            & $script:PwshExe @argv
            if ($LASTEXITCODE -ne 0) { $rc = 1 }
        } finally { $env:SZA_PROJECT_ROOT = $saved; $env:SZA_PROFILE_PATH = $savedProfile }
    }
    exit $rc
}

if ($Link) { exit (Invoke-BlLink $Id $Was) }
if ($Release) { exit (Invoke-BlRelease $Id) }
if ($Sweep) { exit (Invoke-BlSweep) }
if ($Check) {
    $res = Invoke-BlCheck $Id $Was
    $color = switch ($res.state) { 'released' { 'Green' } 'held' { 'Gray' } 'not-blocked' { 'Gray' } default { 'Yellow' } }
    Write-BlLine "$($res.state): $($res.message)" $color
    Write-Output ('BLOCKLINKS-RESULT ' + ($res | ConvertTo-Json -Compress -Depth 4))
    if ($res.state -in @('refused')) { exit 1 }
    if ($res.state -eq 'missing') { exit 2 }
    exit 0
}
