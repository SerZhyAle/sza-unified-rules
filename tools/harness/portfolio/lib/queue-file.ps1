# The owner's queue file, PORTFOLIO_QUEUE.md (TASK-FLOW rules 44 and 64; S0015 QUEUE-FILE.md section 4, R59-R61,
# R66, R67).
#
# Dot-source this file; it defines functions only, sets no preference and prints nothing. State: none.
#
#   Read-PqQueueFile -Path <file> [-KnownRepos <string[]>] [-TicketLookup <sb param($repo,$id)>]
#       @{ rows; held; bad; hash; bom; eol; present }. Never writes, locks or touches the file (FileShare.ReadWrite,
#       FileAccess.Read). rows are the active rows in effective order, held the rows under a hold heading (file
#       order), each @{ package; packageText; repo; id; kind; line; text }: kind 'ticket' for <repo>:<id>, 'head'
#       for <repo> and <repo>:* (id $null); package -1 for the implicit package before the first heading, the
#       integer value of a numbered heading, [long]::MaxValue for '--'; packageText $null, the digits as written,
#       '--' or 'hold'. bad entries are @{ kind; line; text; package; packageText; repo; id; rowKind; held }, kind unknownRepo,
#       unknownTicket, closed, duplicate or unparsable, text cut to 80 characters (the queue.row payload).
#       -KnownRepos absent: every key is known. -TicketLookup absent: every ticket exists and is open; it returns
#       @{ exists; closed } (closed: Verified or Archived). An absent file is an empty queue with present $false.
#
#   Add-PqQueuePin -Path -Ticket <repo:id> [-KnownRepos] [-Log] [-BeforeRename <sb>]
#   Set-PqQueueHold -Path -Target <repo|repo:*|repo:id> [-KnownRepos] [-Log] [-BeforeRename <sb>]
#   Remove-PqQueueHold -Path -Target [-Log] [-BeforeRename <sb>]
#       @{ ok; changed; error; message; hash }. Named errors: QueueFileMissing (only -Init creates the file),
#       QueueChangedOnDisk, UnknownRepoKey, NotHeld (ok $true, changed $false), TargetInvalid, QueueWriteFailed.
#       Every write goes through Write-PqQueueText: one read, the edit, a temp file in the same directory, the
#       re-hash of the target, the rename. The file's BOM and line ending are kept; no other line moves.
#
#   Sort-PqQueueByRank -Path -ProjectOrder <string[]> [-Log] [-BeforeRename <sb>]
#       pq arrange: inside every scheduled package (the implicit one and each numbered one) the rows are put in
#       project order - the keys as given, which pq takes from the registry (Get-PqRepoOrder: rank ascending, equal
#       ranks in array order) - and a project's own rows keep their order. Only row lines move, and only among the row positions of their own package: headings, comments, blank
#       lines and unparsable lines stay where they are; '--' and everything under hold are not touched. An unknown
#       key sorts after every known one. @{ ok; changed; moved; error; message; hash }.
#
#   Initialize-PqQueueFile -Path -Registry [-Log]
#       writes a first file only when none exists (rule 64): the comment header, package 1, one row per registered
#       repository in rank ascending then array order, each '<key>  # role: <role>'. @{ ok; changed; status
#       (written|exists); hash }.
#
#   Get-PqTicketQueuePath -Repo <registry record>
#       a repository's own ticket queue file: its profile's paths.releaseQueue, PLAN/RELEASE_QUEUE.md by default.
#   Read-PqTicketQueueRows -Path <file>
#       that file's ticket rows in file order, each @{ id; token; tail; unscheduled } (token: the id with its slug;
#       tail: changed, status and any note, as written; unscheduled: under its '--'); $null when the file is absent or
#       unreadable.
#   Get-PqQueueSources -Registry
#       [ordered] key -> Read-PqTicketQueueRows of every registered repository, in registry order.
#   Sync-PqQueueFile -Path -Sources <IDictionary> [-Log] [-BeforeRename <sb>]
#       keeps the file the way a repository's plan tool keeps its RELEASE_QUEUE.md: a <repo>:<id> row whose ticket is
#       still in its repository's queue gets that ticket's slug, changed time and status (an owner's # comment stays);
#       a row whose ticket has left that queue (closed, or waiting for the owner's test) is removed; a queued ticket
#       the file names nowhere, active or held, is added at the bottom of the active part, above the hold heading, in
#       Sources order then queue order. No line moves. A repository whose rows are $null, and a key Sources
#       does not name, are left as they are. @{ ok; changed; added; updated; removed; error; message; hash }.
#
# A row may carry its ticket's slug and columns, as the sync writes it: 'fms-web:S0033_contract-sync  26-10-19 11:51
# In Progress'. The id ends at the first '_'; the rest of the line is a comment. The column header line
# 'ticket  changed  status' is skipped.

. (Join-Path $PSScriptRoot 'paths.ps1')
. (Join-Path $PSScriptRoot 'events.ps1')

$script:PqQueueRowPattern = '^(?<repo>[a-z][a-z0-9-]*)(?::(?<id>\*|[^\s:#_]+)(?:_[^\s#]*)?)?$'
$script:PqQueueUnscheduled = [long]::MaxValue
$script:PqQueueTicketWidth = 74
$script:PqDefaultReleaseQueue = $null

function Get-PqQueueHash([byte[]]$Bytes) {
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function ConvertTo-PqQueueCut([string]$Text) {
    if ($Text.Length -le 80) { return $Text }
    return $Text.Substring(0, 80)
}

function Read-PqQueueBytes([string]$Path) {
    $fs = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    try {
        $ms = [IO.MemoryStream]::new()
        $fs.CopyTo($ms)
        return , $ms.ToArray()
    }
    finally { $fs.Dispose() }
}

# Bytes -> @{ lines (no terminators); bom; eol; final (the text ended with a line terminator) }.
function Split-PqQueueText([byte[]]$Bytes) {
    $bom = $Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF
    $offset = if ($bom) { 3 } else { 0 }
    $text = [Text.UTF8Encoding]::new($false).GetString($Bytes, $offset, $Bytes.Length - $offset)
    $eol = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = [regex]::Split($text, '\r?\n')
    $final = $false
    if ($lines.Length -gt 0 -and $lines[$lines.Length - 1] -eq '') {
        $final = $lines.Length -gt 1
        $lines = if ($lines.Length -gt 1) { $lines[0..($lines.Length - 2)] } else { @() }
    }
    return @{ lines = [string[]]@($lines); bom = $bom; eol = $eol; final = $final }
}

# One line: @{ type = skip|heading|hold|row|unparsable; package; packageText; repo; id; kind; token }.
function Get-PqQueueLine([string]$Line) {
    $hash = $Line.IndexOf('#')
    $body = if ($hash -ge 0) { $Line.Substring(0, $hash) } else { $Line }
    $body = $body.Trim()
    if ($body.Length -eq 0) { return @{ type = 'skip' } }
    if ($body -match '^\d+$') {
        $value = [long]0
        if (-not [long]::TryParse($body, [ref]$value) -or $value -ge $script:PqQueueUnscheduled) { $value = $script:PqQueueUnscheduled - 1 }
        return @{ type = 'heading'; package = $value; packageText = $body }
    }
    if ($body -ceq '--') { return @{ type = 'heading'; package = $script:PqQueueUnscheduled; packageText = '--' } }
    if ($body -ieq 'hold') { return @{ type = 'hold' } }
    if ($body -cmatch '^ticket\s+changed\s+status$') { return @{ type = 'skip' } }
    $token = ($body -split '\s+', 2)[0]
    $m = [regex]::Match($token, $script:PqQueueRowPattern)
    if (-not $m.Success) { return @{ type = 'unparsable'; token = $token } }
    $id = if ($m.Groups['id'].Success -and $m.Groups['id'].Value -cne '*') { $m.Groups['id'].Value } else { $null }
    $kind = if ($null -eq $id) { 'head' } else { 'ticket' }
    return @{ type = 'row'; repo = $m.Groups['repo'].Value; id = $id; kind = $kind; token = $token }
}

function Read-PqQueueFile {
    param([Parameter(Mandatory)][string]$Path, [string[]]$KnownRepos, [scriptblock]$TicketLookup)
    $result = @{ rows = @(); held = @(); bad = @(); hash = $null; bom = $false; eol = "`n"; present = $false }
    if (-not [IO.File]::Exists($Path)) { return $result }
    $bytes = Read-PqQueueBytes $Path
    $result.present = $true
    $result.hash = Get-PqQueueHash $bytes
    $split = Split-PqQueueText $bytes
    $result.bom = $split.bom
    $result.eol = $split.eol
    $known = $null
    if ($PSBoundParameters.ContainsKey('KnownRepos')) { $known = [Collections.Generic.HashSet[string]]::new([string[]]@($KnownRepos), [StringComparer]::Ordinal) }
    $rows = [Collections.Generic.List[object]]::new()
    $held = [Collections.Generic.List[object]]::new()
    $bad = [Collections.Generic.List[object]]::new()
    $seenActive = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $seenHeld = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $package = [long]-1
    $packageText = $null
    $inHold = $false
    $lineNo = 0
    $lookupCache = @{}
    foreach ($line in $split.lines) {
        $lineNo++
        $p = Get-PqQueueLine $line
        # if, not switch: continue inside a switch continues the switch, not this loop.
        if ($p.type -eq 'skip') { continue }
        if ($p.type -eq 'heading') { $package = $p.package; $packageText = $p.packageText; $inHold = $false; continue }
        if ($p.type -eq 'hold') { $inHold = $true; continue }
        $pkgText = if ($inHold) { 'hold' } else { $packageText }
        $text = ConvertTo-PqQueueCut $line.Trim()
        if ($p.type -eq 'unparsable') {
            $bad.Add([ordered]@{ kind = 'unparsable'; line = $lineNo; text = $text; package = $package; packageText = $pkgText; repo = $null; id = $null; rowKind = $null; held = $inHold })
            continue
        }
        $row = [ordered]@{ package = $package; packageText = $pkgText; repo = $p.repo; id = $p.id; kind = $p.kind; line = $lineNo; text = $text }
        $badKind = $null
        if ($null -ne $known -and -not $known.Contains($p.repo)) { $badKind = 'unknownRepo' }
        elseif ($null -ne $p.id -and $TicketLookup) {
            $ck = "$($p.repo):$($p.id)"
            if (-not $lookupCache.ContainsKey($ck)) { $lookupCache[$ck] = & $TicketLookup $p.repo $p.id }
            $t = $lookupCache[$ck]
            if ($null -eq $t -or -not $t.exists) { $badKind = 'unknownTicket' }
            elseif ($t.closed) { $badKind = 'closed' }
        }
        if ($null -eq $badKind) {
            $dedup = if ($null -eq $p.id) { $p.repo } else { "$($p.repo):$($p.id)" }
            # Assigned, not taken from an if expression: a collection returned that way is enumerated away.
            $seen = $seenActive
            if ($inHold) { $seen = $seenHeld }
            if (-not $seen.Add($dedup)) { $badKind = 'duplicate' }
        }
        if ($null -ne $badKind) {
            $bad.Add([ordered]@{ kind = $badKind; line = $lineNo; text = $text; package = $package; packageText = $pkgText; repo = $p.repo; id = $p.id; rowKind = $p.kind; held = $inHold })
            continue
        }
        if ($inHold) { $held.Add($row) } else { $rows.Add($row) }
    }
    # Packages ascending by value, then line order; Sort-Object -Stable keeps file order inside equal keys.
    $result.rows = @($rows | Sort-Object -Stable -Property @{ Expression = { $_.package } }, @{ Expression = { $_.line } })
    $result.held = $held.ToArray()
    $result.bad = $bad.ToArray()
    return $result
}

# ---- writers ----

function ConvertTo-PqQueueTarget([string]$Target) {
    if ([string]::IsNullOrWhiteSpace($Target)) { return $null }
    $m = [regex]::Match($Target.Trim(), $script:PqQueueRowPattern)
    if (-not $m.Success) { return $null }
    $id = if ($m.Groups['id'].Success -and $m.Groups['id'].Value -cne '*') { $m.Groups['id'].Value } else { $null }
    return @{ repo = $m.Groups['repo'].Value; id = $id; text = $Target.Trim() }
}

function Test-PqQueueMatch($Parsed, $Target) {
    return $Parsed.type -eq 'row' -and $Parsed.repo -ieq $Target.repo -and (
        ($null -eq $Parsed.id -and $null -eq $Target.id) -or ($null -ne $Parsed.id -and $Parsed.id -ceq $Target.id))
}

# Counts of the active and the held rows of a line array, for queue.edited.
function Get-PqQueueCounts([string[]]$Lines) {
    $rows = 0; $hold = 0; $inHold = $false
    foreach ($l in $Lines) {
        $p = Get-PqQueueLine $l
        switch ($p.type) {
            'heading' { $inHold = $false }
            'hold' { $inHold = $true }
            'row' { if ($inHold) { $hold++ } else { $rows++ } }
        }
    }
    return @{ rows = $rows; hold = $hold }
}

# The one write path of the queue file. $Edit receives a List[string] of the lines and returns $true when it changed
# them, $false for no change, or a string naming an error.
function Write-PqQueueText {
    param([string]$Path, [scriptblock]$Edit, [switch]$Log, [scriptblock]$BeforeRename)
    if (-not [IO.File]::Exists($Path)) { return @{ ok = $false; changed = $false; error = 'QueueFileMissing'; message = "no queue file at $Path; run 'pq queue -Init'"; hash = $null } }
    $bytes = Read-PqQueueBytes $Path
    $before = Get-PqQueueHash $bytes
    $split = Split-PqQueueText $bytes
    $lines = [Collections.Generic.List[string]]::new([string[]]$split.lines)
    $outcome = & $Edit $lines
    if ($outcome -is [string]) { return @{ ok = ($outcome -ceq 'NotHeld'); changed = $false; error = $outcome; message = $null; hash = $before } }
    if (-not $outcome) { return @{ ok = $true; changed = $false; error = $null; message = $null; hash = $before } }
    $text = [string]::Join($split.eol, $lines)
    if ($split.final -or $lines.Count -gt 0) { $text += $split.eol }
    $body = [Text.UTF8Encoding]::new($false).GetBytes($text)
    if ($split.bom) { $body = [byte[]](@(0xEF, 0xBB, 0xBF) + $body) }
    $dir = Split-Path -Parent $Path
    $temp = Join-Path $dir ('.' + (Split-Path -Leaf $Path) + '.' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.tmp')
    try {
        [IO.File]::WriteAllBytes($temp, $body)
        if ($BeforeRename) { $null = & $BeforeRename }
        $now = if ([IO.File]::Exists($Path)) { Get-PqQueueHash (Read-PqQueueBytes $Path) } else { $null }
        if ($now -cne $before) {
            [IO.File]::Delete($temp)
            return @{ ok = $false; changed = $false; error = 'QueueChangedOnDisk'; message = "$Path changed on disk since it was read; nothing written"; hash = $now }
        }
        [IO.File]::Move($temp, $Path, $true)
    }
    catch {
        if ([IO.File]::Exists($temp)) { try { [IO.File]::Delete($temp) } catch { } }
        return @{ ok = $false; changed = $false; error = 'QueueWriteFailed'; message = $_.Exception.Message; hash = $before }
    }
    $hash = Get-PqQueueHash $body
    if ($Log) {
        $c = Get-PqQueueCounts $lines.ToArray()
        if ($null -eq $script:PqDefaultLog) { $null = Open-PqLog -Writer cli }
        $null = Write-PqEvent -Ev 'queue.edited' -D ([ordered]@{ hash = $hash; rows = $c.rows; hold = $c.hold })
    }
    return @{ ok = $true; changed = $true; error = $null; message = $null; hash = $hash }
}

function Test-PqQueueKnown($Target, [string[]]$KnownRepos, [bool]$Given) {
    if (-not $Given) { return $true }
    return @($KnownRepos) -ccontains $Target.repo
}

function Add-PqQueuePin {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Ticket, [string[]]$KnownRepos, [switch]$Log, [scriptblock]$BeforeRename)
    $t = ConvertTo-PqQueueTarget $Ticket
    if ($null -eq $t -or $null -eq $t.id) { return @{ ok = $false; changed = $false; error = 'TargetInvalid'; message = "'$Ticket' is not <repoKey>:<id>"; hash = $null } }
    if (-not [IO.File]::Exists($Path)) { return @{ ok = $false; changed = $false; error = 'QueueFileMissing'; message = "no queue file at $Path; run 'pq queue -Init'"; hash = $null } }
    if (-not (Test-PqQueueKnown $t $KnownRepos $PSBoundParameters.ContainsKey('KnownRepos'))) { return @{ ok = $false; changed = $false; error = 'UnknownRepoKey'; message = "no repository '$($t.repo)' in the registry"; hash = $null } }
    $rowText = "$($t.repo):$($t.id)"
    return (Write-PqQueueText -Path $Path -Log:$Log -BeforeRename $BeforeRename -Edit {
            param($lines)
            # The ticket's own active row, when the file has one, is what moves to the top: no second row appears.
            $inHold = $false
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $p = Get-PqQueueLine $lines[$i]
                if ($p.type -eq 'heading') { $inHold = $false }
                elseif ($p.type -eq 'hold') { $inHold = $true }
                elseif (-not $inHold -and $p.type -eq 'row' -and $null -ne $p.id -and (Test-PqQueueMatch $p $t)) {
                    $rowText = $lines[$i].Trim()
                    $lines.RemoveAt($i)
                    break
                }
            }
            $best = -1; $bestValue = [long]::MaxValue
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $p = Get-PqQueueLine $lines[$i]
                if ($p.type -eq 'heading' -and $p.packageText -cne '--' -and $p.package -lt $bestValue) { $best = $i; $bestValue = $p.package }
            }
            if ($best -ge 0) { $lines.Insert($best + 1, $rowText); return $true }
            $at = $lines.Count
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ((Get-PqQueueLine $lines[$i]).type -ne 'skip') { $at = $i; break }
            }
            $lines.InsertRange($at, [string[]]@('1', $rowText, ''))
            return $true
        })
}

function Set-PqQueueHold {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Target, [string[]]$KnownRepos, [switch]$Log, [scriptblock]$BeforeRename)
    $t = ConvertTo-PqQueueTarget $Target
    if ($null -eq $t) { return @{ ok = $false; changed = $false; error = 'TargetInvalid'; message = "'$Target' is not <repoKey>, <repoKey>:* or <repoKey>:<id>"; hash = $null } }
    if (-not [IO.File]::Exists($Path)) { return @{ ok = $false; changed = $false; error = 'QueueFileMissing'; message = "no queue file at $Path; run 'pq queue -Init'"; hash = $null } }
    if (-not (Test-PqQueueKnown $t $KnownRepos $PSBoundParameters.ContainsKey('KnownRepos'))) { return @{ ok = $false; changed = $false; error = 'UnknownRepoKey'; message = "no repository '$($t.repo)' in the registry"; hash = $null } }
    return (Write-PqQueueText -Path $Path -Log:$Log -BeforeRename $BeforeRename -Edit {
            param($lines)
            $inHold = $false; $holdAt = -1; $moveAt = -1
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $p = Get-PqQueueLine $lines[$i]
                switch ($p.type) {
                    'heading' { $inHold = $false }
                    'hold' { $inHold = $true; if ($holdAt -lt 0) { $holdAt = $i } }
                    'row' {
                        if (Test-PqQueueMatch $p $t) {
                            if ($inHold) { return $false }
                            if ($moveAt -lt 0) { $moveAt = $i }
                        }
                    }
                }
            }
            $line = if ($moveAt -ge 0) { $lines[$moveAt] } else { $t.text }
            if ($moveAt -ge 0) {
                $lines.RemoveAt($moveAt)
                if ($holdAt -gt $moveAt) { $holdAt-- }
            }
            if ($holdAt -ge 0) { $lines.Insert($holdAt + 1, $line) }
            else {
                if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim().Length -gt 0) { $lines.Add('') }
                $lines.Add('hold')
                $lines.Add($line)
            }
            return $true
        })
}

function Remove-PqQueueHold {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Target, [switch]$Log, [scriptblock]$BeforeRename)
    $t = ConvertTo-PqQueueTarget $Target
    if ($null -eq $t) { return @{ ok = $false; changed = $false; error = 'TargetInvalid'; message = "'$Target' is not <repoKey>, <repoKey>:* or <repoKey>:<id>"; hash = $null } }
    return (Write-PqQueueText -Path $Path -Log:$Log -BeforeRename $BeforeRename -Edit {
            param($lines)
            $inHold = $false
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $p = Get-PqQueueLine $lines[$i]
                switch ($p.type) {
                    'heading' { $inHold = $false }
                    'hold' { $inHold = $true }
                    'row' { if ($inHold -and (Test-PqQueueMatch $p $t)) { $lines.RemoveAt($i); return $true } }
                }
            }
            return 'NotHeld'
        })
}

function Sort-PqQueueByRank {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ProjectOrder, [switch]$Log, [scriptblock]$BeforeRename)
    $order = [Collections.Generic.Dictionary[string, int]]::new([StringComparer]::Ordinal)
    foreach ($k in $ProjectOrder) { if (-not $order.ContainsKey($k)) { $order[$k] = $order.Count } }
    $script:PqArrangeMoved = 0
    $r = Write-PqQueueText -Path $Path -Log:$Log -BeforeRename $BeforeRename -Edit {
        param($lines)
        # Row positions per scheduled package, in file order; a heading closes the group, hold and '--' open none.
        $groups = [Collections.Generic.List[object]]::new()
        $current = [Collections.Generic.List[int]]::new()
        $sortable = $true
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $p = Get-PqQueueLine $lines[$i]
            if ($p.type -eq 'heading' -or $p.type -eq 'hold') {
                if ($current.Count -gt 1) { $groups.Add($current) }
                $current = [Collections.Generic.List[int]]::new()
                $sortable = $p.type -eq 'heading' -and $p.packageText -cne '--'
            }
            elseif ($sortable -and $p.type -eq 'row') { $current.Add($i) }
        }
        if ($current.Count -gt 1) { $groups.Add($current) }
        $moved = 0
        foreach ($g in $groups) {
            $j = 0
            $rows = @(foreach ($at in $g) {
                    $key = (Get-PqQueueLine $lines[$at]).repo
                    $rank = if ($order.ContainsKey($key)) { $order[$key] } else { [int]::MaxValue }
                    [pscustomobject]@{ text = $lines[$at]; rank = $rank; pos = $j }
                    $j++
                })
            $sorted = @($rows | Sort-Object -Stable -Property rank, pos)
            for ($k = 0; $k -lt $g.Count; $k++) {
                if ($sorted[$k].pos -ne $k) { $moved++ }
                $lines[$g[$k]] = $sorted[$k].text
            }
        }
        $script:PqArrangeMoved = $moved
        return ($moved -gt 0)
    }
    $r.moved = $script:PqArrangeMoved
    return $r
}

function Initialize-PqQueueFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Registry, [switch]$Log)
    if ([IO.File]::Exists($Path)) { return @{ ok = $true; changed = $false; status = 'exists'; hash = (Get-PqQueueHash (Read-PqQueueBytes $Path)) } }
    $i = 0
    $repos = @(foreach ($r in @($Registry.repos)) {
            $rank = if ($null -ne $r.PSObject.Properties['rank'] -and $null -ne $r.rank) { [long]$r.rank } else { 100 }
            $role = if ($null -ne $r.PSObject.Properties['role'] -and $r.role) { [string]$r.role } else { 'unknown' }
            [pscustomobject]@{ key = [string]$r.key; rank = $rank; index = $i; role = $role }
            $i++
        })
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add("# PORTFOLIO_QUEUE.md - the owner's file.")
    $lines.Add('# The order of the lines IS the priority of the projects: top = most important.')
    $lines.Add("# Written once by 'pq queue -Init'. Edit it by hand; only pq pin, pq hold and pq release change it afterwards.")
    $lines.Add('')
    $lines.Add('1')
    foreach ($r in @($repos | Sort-Object -Stable -Property rank, index)) { $lines.Add("$($r.key)  # role: $($r.role)") }
    $body = [Text.UTF8Encoding]::new($false).GetBytes(([string]::Join("`n", $lines) + "`n"))
    $dir = Split-Path -Parent $Path
    if (-not [IO.Directory]::Exists($dir)) { $null = [IO.Directory]::CreateDirectory($dir) }
    $temp = Join-Path $dir ('.' + (Split-Path -Leaf $Path) + '.' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.tmp')
    try {
        [IO.File]::WriteAllBytes($temp, $body)
        # File.Move without overwrite: a file that appeared meanwhile is never replaced.
        [IO.File]::Move($temp, $Path, $false)
    }
    catch {
        if ([IO.File]::Exists($temp)) { try { [IO.File]::Delete($temp) } catch { } }
        if ([IO.File]::Exists($Path)) { return @{ ok = $true; changed = $false; status = 'exists'; hash = (Get-PqQueueHash (Read-PqQueueBytes $Path)) } }
        return @{ ok = $false; changed = $false; status = 'failed'; error = 'QueueWriteFailed'; message = $_.Exception.Message; hash = $null }
    }
    $hash = Get-PqQueueHash $body
    if ($Log) {
        if ($null -eq $script:PqDefaultLog) { $null = Open-PqLog -Writer cli }
        $null = Write-PqEvent -Ev 'queue.edited' -D ([ordered]@{ hash = $hash; rows = $repos.Count; hold = 0 })
    }
    return @{ ok = $true; changed = $true; status = 'written'; hash = $hash }
}

# ---- the repositories' own ticket queues, and the sync from them ----

# The shipped default of paths.releaseQueue, read from the harness profile in an isolated module (that script caches one
# project root, so it is never dot-sourced here) and kept for the life of the process.
function Get-PqDefaultReleaseQueue {
    if ($null -eq $script:PqDefaultReleaseQueue) {
        $defaults = New-Module -ArgumentList (Join-Path $PSScriptRoot '..\..\_profile.ps1') -ReturnResult -ScriptBlock {
            param($ProfileScript)
            . $ProfileScript
            $script:SzaProfileDefaults
        }
        $script:PqDefaultReleaseQueue = [string]$defaults.paths['releaseQueue']
    }
    return $script:PqDefaultReleaseQueue
}

function Get-PqTicketQueuePath($Repo) {
    $repoPath = [string]$Repo.path
    if ($null -ne $Repo.PSObject.Properties['releaseQueue'] -and $Repo.releaseQueue) {
        $p = [string]$Repo.releaseQueue
        $full = if ([IO.Path]::IsPathFullyQualified($p)) { $p } else { Join-Path $repoPath $p }
        if ([IO.File]::Exists($full)) { return [IO.Path]::GetFullPath($full) }
    }
    $profileFile = Join-Path $repoPath '.sza-profile.json'
    if ([IO.File]::Exists($profileFile)) {
        try {
            $prof = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($profileFile)) -DateKind String
            $paths = $prof.PSObject.Properties['paths']
            if ($null -ne $paths -and $null -ne $paths.Value) {
                $v = $paths.Value.PSObject.Properties['releaseQueue']
                if ($null -ne $v -and $v.Value) {
                    $customRel = [string]$v.Value
                    $full = if ([IO.Path]::IsPathFullyQualified($customRel)) { $customRel } else { Join-Path $repoPath $customRel }
                    if ([IO.File]::Exists($full)) { return [IO.Path]::GetFullPath($full) }
                }
            }
        }
        catch { }
    }
    $candidates = @(
        'PLAN/RELEASE_QUEUE.md',
        'PLAN/release-queue.md',
        'DEV/plan/RELEASE_QUEUE.md',
        'docs/specifications/RELEASE_QUEUE.md',
        'PLAN/INDEX.md',
        'PLAN/spec-catalog.jsonl',
        'PLAN/README.md',
        'tasks/README.md',
        'tasks/INDEX.md'
    )
    foreach ($cand in $candidates) {
        $full = Join-Path $repoPath $cand
        if ([IO.File]::Exists($full)) { return [IO.Path]::GetFullPath($full) }
    }
    $rel = Get-PqDefaultReleaseQueue
    return [IO.Path]::GetFullPath((Join-Path $repoPath $rel))
}

function Read-PqTicketQueueRows([string]$Path) {
    if (-not [IO.File]::Exists($Path)) { return $null }

    if ($Path.EndsWith('.jsonl', [StringComparison]::OrdinalIgnoreCase)) {
        $out = [Collections.Generic.List[object]]::new()
        $closed = @('Verified', 'Archived', 'Implemented', 'Closed')
        try {
            $split = Split-PqQueueText (Read-PqQueueBytes $Path)
            foreach ($line in $split.lines) {
                $t = $line.Trim()
                if (-not $t) { continue }
                try {
                    $obj = ConvertFrom-Json -InputObject $t -DateKind String
                    $id = [string]$obj.id
                    $status = [string]$obj.status
                    if ($status -in $closed) { continue }
                    $token = if ($null -ne $obj.file -and $obj.file) {
                        [IO.Path]::GetFileNameWithoutExtension([string]$obj.file)
                    } elseif ($null -ne $obj.name -and $obj.name) {
                        $slug = ([string]$obj.name).ToLowerInvariant() -replace '[^a-z0-9]+', '-' -replace '^-+|-+$', ''
                        "${id}_$slug"
                    } else { $id }
                    $token = $token -replace '\s+', '_'
                    $updated = if ($null -ne $obj.updated -and $obj.updated) { [string]$obj.updated } else { '' }
                    $tail = if ($updated) { "$updated  $status" } else { $status }
                    $out.Add([ordered]@{ id = $id; token = $token; tail = $tail; unscheduled = $false })
                } catch { }
            }
            return , $out.ToArray()
        } catch { return $null }
    }

    try { $split = Split-PqQueueText (Read-PqQueueBytes $Path) } catch { return $null }
    $out = [Collections.Generic.List[object]]::new()
    $unscheduled = $false
    $hasCurrent = $false
    $hasSection = $false
    $hasUnsupported = $false

    foreach ($line in $split.lines) {
        $t = $line.Trim()
        if ($t -cmatch '^current-next-release:\s*\d+') { $hasCurrent = $true; continue }
        if ($t -ceq '--') { $unscheduled = $true; $hasSection = $true; continue }
        if ($t -cmatch '^\d+$') { $unscheduled = $false; $hasSection = $true; continue }
        if (-not $hasSection) { continue }
        $m = [regex]::Match($t, '^(?<token>(?<id>(?:S\d{4,}|T\d{4,}|[A-Z][A-Z0-9]*-\d+))(?:_\S*)?)(?:\s+(?<tail>.*))?$')
        if (-not $m.Success) {
            if ($t -cmatch '^\S+\s+\d{2}-\d{2}-\d{2}\s+\d{2}:\d{2}\s+') {
                $hasUnsupported = $true
                break
            }
            continue
        }
        $out.Add([ordered]@{ id = $m.Groups['id'].Value; token = $m.Groups['token'].Value; tail = $m.Groups['tail'].Value.Trim(); unscheduled = $unscheduled })
    }

    if ($hasUnsupported) { return $null }
    if ($out.Count -gt 0 -or ($hasCurrent -and $hasSection)) {
        return , $out.ToArray()
    }

    $closedStatuses = @('Verified', 'Archived', 'Implemented', 'Closed', 'Done')
    $dir = Split-Path -Parent $Path
    $parentDir = Split-Path -Parent $dir
    $seenIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $inImplemented = $false

    foreach ($line in $split.lines) {
        $t = $line.Trim()
        if (-not $t) { continue }
        if ($t -ceq '--' -or $t -match '(?i)^##\s*(not scheduled|no package|separate backlog)') { $unscheduled = $true; continue }
        if ($t -match '(?i)^##\s*implemented') { $inImplemented = $true; continue }
        if ($t -match '(?i)^##\s*(release\s*\d+|\d+|[A-Z]\.)') { $unscheduled = $false; $inImplemented = $false; continue }
        if ($inImplemented) { continue }

        if ($t -match '^(?<num>\d+)\s+(?<tok>\d+_\S+)\s+(?<date>\d{4}-\d{2}-\d{2})\s+(?<rest>.*)$') {
            $id = $Matches['num']
            $token = $Matches['tok']
            $rest = $Matches['rest'].Trim()
            $status = ''
            if ($rest -match '^(?<st>[A-Za-z]+(?:\s+[A-Za-z]+)?)') { $status = $Matches['st'] }
            if ($status -in $closedStatuses) { continue }
            if ($seenIds.Add($id)) {
                $tail = "$($Matches['date'])  $rest"
                $out.Add([ordered]@{ id = $id; token = $token; tail = $tail; unscheduled = $unscheduled })
            }
            continue
        }

        if ($t.StartsWith('|') -and $t.EndsWith('|') -and $t -notmatch '^\|\s*[-:\s|]+\s*$' -and $t -notmatch '(?i)\|\s*(order|ticket|id|#)\s*\|') {
            $mLink = [regex]::Match($t, '\[(?<label>[^\]]+)\]\((?<link>[^)]+)\)')
            $id = $null
            $token = $null
            $link = $null

            if ($mLink.Success) {
                $link = $mLink.Groups['link'].Value
                if ($link -match '(?i)(done|archive)/') { continue }
                $token = [IO.Path]::GetFileNameWithoutExtension($link)
                $mId = [regex]::Match($token, '^(?<id>(?:S\d{4,}|T\d{4,}|[A-Z][A-Z0-9]*-\d+|\d{2,}))')
                if ($mId.Success) { $id = $mId.Groups['id'].Value }
                else { $id = $mLink.Groups['label'].Value.Trim() }
            } else {
                $mId = [regex]::Match($t, '\b(?<id>(?:SP-\d+|TASK-\d+|S\d{4,}|T\d{4,}))\b')
                if ($mId.Success) {
                    $id = $mId.Groups['id'].Value
                    $token = $id
                }
            }

            if (-not $id) { continue }

            $status = ''
            if ($t -match '\b(?<st>Draft|Approved|Tactical|In Progress|Partial|Broken|BlockByOtherTask|BlockNeedUserTest|BlockQuestions|BlockExternal|Settled|Implemented|Verified|Archived|Closed|Done)\b') {
                $status = $Matches['st']
            }

            $specPath = $null
            if ($link) {
                $cand = Join-Path $dir $link
                if ([IO.File]::Exists($cand)) { $specPath = $cand }
            }
            if (-not $specPath) {
                $candFiles = @(Get-ChildItem -Path $dir -Filter "$id*.md" -ErrorAction SilentlyContinue)
                if ($candFiles.Count -gt 0) {
                    $specPath = $candFiles[0].FullName
                    $token = [IO.Path]::GetFileNameWithoutExtension($candFiles[0].Name)
                }
            }

            if ($specPath) {
                $firstLines = [IO.File]::ReadAllLines($specPath) | Select-Object -First 20
                foreach ($fl in $firstLines) {
                    if ($fl -match '(?i)\*\*status:\*\*\s*(?<fs>[^\r\n]+)') {
                        $fStatus = $Matches['fs'].Trim()
                        if ($fStatus -match '^(?<w>[A-Za-z]+)') { $status = $Matches['w'] }
                        break
                    }
                }
            }

            if ($status -in $closedStatuses) { continue }
            $token = $token -replace '\s+', '_'
            if ($seenIds.Add($id)) {
                $mtime = if ($specPath) { (Get-Item $specPath).LastWriteTime.ToString('yy-MM-dd HH:mm') } else { '' }
                $tail = if ($mtime -and $status) { "$mtime  $status" } elseif ($status) { $status } else { 'Draft' }
                $out.Add([ordered]@{ id = $id; token = $token; tail = $tail; unscheduled = $unscheduled })
            }
            continue
        }

        if ($t -match '^-\s+\[(?<title>[^\]]+)\]\((?<link>[^)]+)\)') {
            $link = $Matches['link']
            $title = $Matches['title']
            if ($link -match '(?i)(done|archive)/') { continue }

            $specPath = Join-Path $dir $link
            if (-not [IO.File]::Exists($specPath)) {
                $specPath = Join-Path $parentDir $link
            }
            if (-not [IO.File]::Exists($specPath)) { continue }

            $token = [IO.Path]::GetFileNameWithoutExtension($link)
            $id = if ($token -match '^(?<id>(?:S\d{4,}|T\d{4,}|[A-Z][A-Z0-9]*-\d+|\d{2,}))') { $Matches['id'] } else { $token }

            $status = 'Draft'
            $firstLines = [IO.File]::ReadAllLines($specPath) | Select-Object -First 20
            foreach ($fl in $firstLines) {
                if ($fl -match '(?i)\*\*status:\*\*\s*(?<fs>[^\r\n]+)') {
                    $fStatus = $Matches['fs'].Trim()
                    if ($fStatus -match '^(?<w>[A-Za-z]+)') { $status = $Matches['w'] }
                    break
                }
            }

            if ($status -in $closedStatuses) { continue }
            $token = $token -replace '\s+', '_'
            if ($seenIds.Add($id)) {
                $mtime = (Get-Item $specPath).LastWriteTime.ToString('yy-MM-dd HH:mm')
                $tail = "$mtime  $status"
                $out.Add([ordered]@{ id = $id; token = $token; tail = $tail; unscheduled = $unscheduled })
            }
            continue
        }
    }

    $specDirs = @($dir)
    if ((Split-Path -Leaf $dir) -in @('docs', 'DEV')) {
        $candPlan = Join-Path (Split-Path -Parent $dir) 'PLAN'
        if ([IO.Directory]::Exists($candPlan)) { $specDirs += $candPlan }
    }
    foreach ($sd in $specDirs) {
        $candFiles = @(Get-ChildItem -Path $sd -Filter '*.md' -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -notmatch '(?i)^(README|INDEX|TICKET_TEMPLATE|release[-_]queue)\.md$' -and
            $_.FullName -notmatch '[\\/](done|archive)[\\/]'
        })
        foreach ($cf in $candFiles) {
            $fn = [IO.Path]::GetFileNameWithoutExtension($cf.Name)
            $mId = [regex]::Match($fn, '^(?<id>(?:S\d{4,}|T\d{4,}|SP-\d+|TASK-\d+|\d+))(?:[_-]|\b)')
            $cid = if ($mId.Success) { $mId.Groups['id'].Value } else { $fn }
            if ($seenIds.Contains($cid)) { continue }

            $cStatus = 'Draft'
            $firstLines = [IO.File]::ReadAllLines($cf.FullName) | Select-Object -First 20
            $foundStatus = $false
            foreach ($fl in $firstLines) {
                if ($fl -match '(?i)\*\*status:\*\*\s*(?<fs>[^\r\n]+)') {
                    $foundStatus = $true
                    $fStatus = $Matches['fs'].Trim()
                    if ($fStatus -match '^(?<w>[A-Za-z]+)') { $cStatus = $Matches['w'] }
                    break
                }
            }
            if ($foundStatus -or $mId.Success) {
                if ($cStatus -notin $closedStatuses) {
                    if ($seenIds.Add($cid)) {
                        $mtime = $cf.LastWriteTime.ToString('yy-MM-dd HH:mm')
                        $ctok = $fn -replace '\s+', '_'
                        $out.Add([ordered]@{ id = $cid; token = $ctok; tail = "$mtime  $cStatus"; unscheduled = $false })
                    }
                }
            }
        }
    }

    if ($out.Count -eq 0 -and -not ($hasCurrent -and $hasSection)) { return $null }
    return , $out.ToArray()
}

function Get-PqQueueSources($Registry) {
    $sources = [ordered]@{}
    foreach ($r in @($Registry.repos)) { $sources[[string]$r.key] = Read-PqTicketQueueRows (Get-PqTicketQueuePath $r) }
    return $sources
}

# Serialize source reads and projection writes across catalog writers and portfolio workers. Otherwise a
# worker could read an old local queue, wait for a newer status to be published, then overwrite it.
function Sync-PqRegisteredQueues {
    param([string]$Path, $Registry, [string]$Key, [switch]$Log)
    $bytes = [Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($Path).ToLowerInvariant())
    $name = 'sza-pq-sync-' + [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    $mutex = [Threading.Mutex]::new($false, $name)
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne([TimeSpan]::FromSeconds(15)) }
        catch [Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { return @{ ok = $false; error = 'QueueSyncBusy'; message = 'portfolio synchronization timed out' } }
        for ($attempt = 0; $attempt -lt 3; $attempt++) {
            if ($Key) {
                $repo = @($Registry.repos | Where-Object { [string]$_.key -ceq $Key }) | Select-Object -First 1
                if ($null -eq $repo) { return @{ ok = $false; error = 'UnknownRepoKey'; message = "no repository '$Key' in the registry" } }
                $rows = Read-PqTicketQueueRows (Get-PqTicketQueuePath $repo)
                if ($null -eq $rows) { return @{ ok = $false; error = 'TicketQueueUnreadable'; message = "cannot read a complete ticket queue for $Key" } }
                $sources = [ordered]@{}; $sources[$Key] = $rows
            } else { $sources = Get-PqQueueSources $Registry }
            $unreadable = @($sources.Keys | Where-Object { $null -eq $sources[$_] })
            $result = Sync-PqQueueFile -Path $Path -Sources $sources -Log:$Log
            $result.unreadable = $unreadable
            if ($result.ok -or $result.error -cne 'QueueChangedOnDisk') { return $result }
        }
        return $result
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

# One ticket row as the sync writes it: '<repo>:<token>', padded, then the tail, then the owner's comment if any.
function Format-PqQueueTicketLine([string]$Repo, $Row, [string]$Comment) {
    $line = "$($Repo):$($Row.token)"
    if ($Row.tail) { $line = $line.PadRight([Math]::Max($script:PqQueueTicketWidth, $line.Length + 2)) + $Row.tail }
    if ($Comment) { $line += '  ' + $Comment }
    return $line
}

function Sync-PqQueueFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][Collections.IDictionary]$Sources, [switch]$Log, [scriptblock]$BeforeRename)
    $stats = @{ added = 0; updated = 0; removed = 0 }
    $queued = [ordered]@{}
    foreach ($k in $Sources.Keys) {
        if ($null -eq $Sources[$k]) { continue }
        $rows = @($Sources[$k] | Where-Object { $null -ne $_ })
        $map = [ordered]@{}
        foreach ($row in $rows) { if (-not $map.Contains($row.id)) { $map[$row.id] = $row } }
        $queued[[string]$k] = $map
    }
    $r = Write-PqQueueText -Path $Path -Log:$Log -BeforeRename $BeforeRename -Edit {
        param($lines)
        $named = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $changed = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $p = Get-PqQueueLine $lines[$i]
            if ($p.type -ne 'row' -or $null -eq $p.id -or -not $queued.Contains($p.repo)) { continue }
            $map = $queued[$p.repo]
            if (-not $map.Contains($p.id)) {
                $lines.RemoveAt($i); $i--
                $stats.removed++; $changed = $true
                continue
            }
            $null = $named.Add("$($p.repo):$($p.id)")
            $at = $lines[$i].IndexOf('#')
            $comment = if ($at -ge 0) { $lines[$i].Substring($at).TrimEnd() } else { $null }
            $new = Format-PqQueueTicketLine $p.repo $map[$p.id] $comment
            if ($new -cne $lines[$i]) { $lines[$i] = $new; $stats.updated++; $changed = $true }
        }
        $add = [Collections.Generic.List[string]]::new()
        foreach ($k in $queued.Keys) {
            foreach ($id in $queued[$k].Keys) {
                if (-not $named.Contains("${k}:$id")) { $add.Add((Format-PqQueueTicketLine $k $queued[$k][$id] $null)) }
            }
        }
        if ($add.Count -gt 0) {
            # The bottom of the active part: right after its last non-blank line, so the blank lines above hold stay.
            $end = $lines.Count
            for ($i = 0; $i -lt $lines.Count; $i++) { if ((Get-PqQueueLine $lines[$i]).type -eq 'hold') { $end = $i; break } }
            $at = $end
            while ($at -gt 0 -and $lines[$at - 1].Trim().Length -eq 0) { $at-- }
            $lines.InsertRange($at, [string[]]$add.ToArray())
            $stats.added += $add.Count; $changed = $true
        }
        return $changed
    }
    $r.added = $stats.added; $r.updated = $stats.updated; $r.removed = $stats.removed
    return $r
}
