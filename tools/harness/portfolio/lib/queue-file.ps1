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
#   Initialize-PqQueueFile -Path -Registry [-Log]
#       writes a first file only when none exists (rule 64): the comment header, package 1, one row per registered
#       repository in rank ascending then array order, each '<key>  # role: <role>'. @{ ok; changed; status
#       (written|exists); hash }.

. (Join-Path $PSScriptRoot 'paths.ps1')
. (Join-Path $PSScriptRoot 'events.ps1')

$script:PqQueueRowPattern = '^(?<repo>[a-z][a-z0-9-]*)(?::(?<id>\*|[^\s:#]+))?$'
$script:PqQueueUnscheduled = [long]::MaxValue

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
