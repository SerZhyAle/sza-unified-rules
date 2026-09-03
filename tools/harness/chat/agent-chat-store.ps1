#requires -Version 7.0
<#
.SYNOPSIS
    The agent chat store: two file-per-message streams, their windows and their staleness rule (S2372).

.DESCRIPTION
    Leaf library. Dot-sources agent-identity.ps1 and nothing else, and EXPECTS to be dot-sourced
    from a scope where scripts/utils/agent-lock.ps1 already ran, because the windows come from
    that file's $Script:AgentLockTimings table (ADR-9: the lease window and the chat window
    describe the same session, and two tables about one thing drift apart). agent-lock.ps1
    dot-sources this file itself, so every caller that loads the lock library has the store.

    Two streams, deliberately separate (ADR-1):
      progress/  - what an agent is doing right now. Minutes of life; dozens per ticket. The last
                   message of a session that died is the trace of where it stopped.
      findings/  - a result: a measurement, an answer, an environment state. Hours of life, and
                   the truth is not the clock but the SCOPE - the paths whose change makes the
                   record wrong (ADR-2). A finding is dead when anything in its scope was written
                   after it, when its expiry passed, or when the device it names is gone.

    Storage: <root>/progress/ and <root>/findings/ under temp/AGENT-CHAT (FMS_AGENT_CHAT_ROOT
    overrides it, which is how the suite stays hermetic). One file per message, named
      <yyyyMMddTHHmmssfff>Z_<kind>_<agentId>_<4hex>.json
    so a listing sorted by name is chronological and "the last N from this agent" is a name
    filter with no JSON read. Written through a .tmp and a rename, created with FileMode.CreateNew:
    five processes may write at once and none of them appends to a shared file (§3.2).

    Trust rule (pillar 5): nothing here decides anything. A reader prints; the lock, the queue and
    the lease stay the only truth about ownership, and no verdict that reaches a spec or a gate may
    rest on a finding written by someone else. A finding relieves an agent of doing cheap
    idempotent WORK, never of reporting.

    Every write and every read sweeps first (pillar 5, the TURN-marker precedent): retention for
    progress, expiry for findings, a file cap for both, stale .tmp files.

    Exit codes: none - library, dot-sourced only.
#>

. (Join-Path $PSScriptRoot '..\_profile.ps1')
. (Get-SzaHarnessScript 'locks/agent-identity.ps1')

$Script:AgentChatSchema = 1
$Script:AgentChatKinds = @('session', 'phase', 'lock', 'wait', 'ticket', 'status', 'verdict', 'check', 'build', 'device', 'abandon', 'heartbeat', 'note')
# The one window this file owns: a successful ticket run fits in 90 min (max over 326 journal rows,
# 2026-09-02) and the successor of a dead session arrives no sooner than the lease's 45-min stale
# window, so the last trace must outlive both with margin.
$Script:AgentChatProgressRetentionMinutes = 180
$Script:AgentChatScopeMax = 16
$Script:AgentChatNameRx = '^(?<stamp>\d{8}T\d{9})Z_(?<kind>[a-z]+)_(?<agent>[A-Za-z0-9\-]+)_(?<rand>[0-9a-f]{4})\.json$'

function Get-AgentChatRepoRoot {
    $v = Get-Variable -Name AgentLockRepoRoot -Scope Script -ErrorAction SilentlyContinue
    if ($null -ne $v -and -not [string]::IsNullOrWhiteSpace([string]$v.Value)) { return [string]$v.Value }
    return ((Get-SzaProjectRoot))
}

function Get-AgentChatRoot {
    $override = (Get-SzaEnv 'AGENT_CHAT_ROOT')
    if (-not [string]::IsNullOrWhiteSpace($override)) { return $override }
    return (Get-SzaPath 'agentChatDir')
}

function Get-AgentChatStreamDir {
    param([Parameter(Mandatory)][ValidateSet('progress', 'finding')][string]$Stream)
    $dirName = if ($Stream -eq 'progress') { 'progress' } else { 'findings' }
    $dir = Join-Path (Get-AgentChatRoot) $dirName
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    return $dir
}

function Get-AgentChatWindows {
    <#
    .SYNOPSIS
        Retention, expiry, silence threshold and caps - read from the lock timings table.
    #>
    $timings = Get-Variable -Name AgentLockTimings -Scope Script -ErrorAction SilentlyContinue
    if ($null -eq $timings -or $null -eq $timings.Value -or -not $timings.Value.ContainsKey('SpecTicket')) {
        throw 'agent-chat-store: dot-source locks/agent-lock.ps1 first - the chat windows come from its timings table (S2372 ADR-9).'
    }
    $spec = $timings.Value['SpecTicket']
    $capProgress = 400
    $capFindings = 200
    # Test hook only: the suite shrinks the caps to prove eviction without writing 400 files.
    if ((Get-SzaEnv 'AGENT_CHAT_CAP_PROGRESS') -match '^\d+$') { $capProgress = [int](Get-SzaEnv 'AGENT_CHAT_CAP_PROGRESS') }
    if ((Get-SzaEnv 'AGENT_CHAT_CAP_FINDINGS') -match '^\d+$') { $capFindings = [int](Get-SzaEnv 'AGENT_CHAT_CAP_FINDINGS') }
    return [pscustomobject]@{
        ProgressRetentionMinutes = $Script:AgentChatProgressRetentionMinutes
        FindingTtlMinutes        = [int]$spec.TicketCeilingMinutes
        SilentMinutes            = [int]$spec.SessionStaleMinutes
        ProgressCap              = $capProgress
        FindingCap               = $capFindings
    }
}

function Get-AgentChatProp {
    param($Object, [Parameter(Mandatory)][string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $Default }
    return $p.Value
}

function ConvertTo-AgentChatSafeName {
    param([Parameter(Mandatory)][string]$Value)
    $safe = ($Value -replace '[^A-Za-z0-9\-]', '-')
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'unknown' }
    return $safe
}

function ConvertFrom-AgentChatStamp {
    param([Parameter(Mandatory)][string]$Stamp)
    return [DateTime]::ParseExact($Stamp, 'yyyyMMddTHHmmssfff', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal)
}

function Read-AgentChatFile {
    <#
    .SYNOPSIS
        One message off disk, or $null for an unreadable file or an unknown schema (§3.2).
    #>
    param([Parameter(Mandatory)][string]$Path)
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch { return $null }
    if ([int](Get-AgentChatProp $obj 'schema' 0) -ne $Script:AgentChatSchema) { return $null }
    $atRaw = [string](Get-AgentChatProp $obj 'at' '')
    $at = $null
    try { $at = [DateTime]::Parse($atRaw, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal) } catch { return $null }
    $obj | Add-Member -NotePropertyName 'path' -NotePropertyValue $Path -Force
    $obj | Add-Member -NotePropertyName 'atUtc' -NotePropertyValue $at -Force
    $obj | Add-Member -NotePropertyName 'ageMinutes' -NotePropertyValue ([math]::Round(([DateTime]::UtcNow - $at).TotalMinutes, 1)) -Force
    return $obj
}

function Get-AgentChatFiles {
    param(
        [Parameter(Mandatory)][ValidateSet('progress', 'finding')][string]$Stream,
        [string]$AgentId,
        [string]$Kind
    )
    $dir = Get-AgentChatStreamDir -Stream $Stream
    $files = @(Get-ChildItem -LiteralPath $dir -File -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($f in $files) {
        if ($f.Name -notmatch $Script:AgentChatNameRx) { continue }
        if ($AgentId -and $Matches['agent'] -ne (ConvertTo-AgentChatSafeName $AgentId)) { continue }
        if ($Kind -and $Matches['kind'] -ne $Kind) { continue }
        $out.Add([pscustomobject]@{ File = $f; Stamp = $Matches['stamp']; Kind = $Matches['kind']; Agent = $Matches['agent'] })
    }
    return $out.ToArray()
}

function Invoke-AgentChatSweep {
    <#
    .SYNOPSIS
        Retention, expiry, caps and stale temp files - runs before every write and every read.
    #>
    $w = Get-AgentChatWindows
    $removed = 0
    $nowUtc = [DateTime]::UtcNow

    # Nicknames outlive the progress window on purpose - a session is called the same thing for its
    # whole life - but a name nobody has used for a week belongs to a session that is gone.
    try {
        $nameDir = Get-AgentNameDir
        if (Test-Path -LiteralPath $nameDir) {
            foreach ($nf in @(Get-ChildItem -LiteralPath $nameDir -File -Filter '*.json' -ErrorAction SilentlyContinue)) {
                if (($nowUtc - $nf.LastWriteTimeUtc).TotalDays -gt 7) { Remove-Item -LiteralPath $nf.FullName -Force -ErrorAction SilentlyContinue; $removed++ }
            }
        }
    } catch { }

    foreach ($stream in @('progress', 'finding')) {
        $dir = Get-AgentChatStreamDir -Stream $stream
        foreach ($tmp in @(Get-ChildItem -LiteralPath $dir -File -Filter '*.tmp-*' -ErrorAction SilentlyContinue)) {
            if (($nowUtc - $tmp.LastWriteTimeUtc).TotalMinutes -gt 5) {
                Remove-Item -LiteralPath $tmp.FullName -Force -ErrorAction SilentlyContinue; $removed++
            }
        }
        $entries = @(Get-AgentChatFiles -Stream $stream)   # newest first
        $keep = New-Object System.Collections.Generic.List[object]
        foreach ($e in $entries) {
            $dead = $false
            if ($stream -eq 'progress') {
                $at = ConvertFrom-AgentChatStamp $e.Stamp
                $dead = (($nowUtc - $at).TotalMinutes -gt $w.ProgressRetentionMinutes)
            }
            else {
                $msg = Read-AgentChatFile -Path $e.File.FullName
                if ($null -eq $msg) {
                    # Unknown schema or unreadable: kept, skipped by readers; only age retires it.
                    $at = ConvertFrom-AgentChatStamp $e.Stamp
                    $dead = (($nowUtc - $at).TotalMinutes -gt $w.FindingTtlMinutes)
                }
                else {
                    $exp = [string](Get-AgentChatProp $msg 'expiresAt' '')
                    if ($exp) {
                        try { $dead = ([DateTime]::Parse($exp, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal) -le $nowUtc) } catch { $dead = $true }
                    }
                }
            }
            if ($dead) { Remove-Item -LiteralPath $e.File.FullName -Force -ErrorAction SilentlyContinue; $removed++ }
            else { $keep.Add($e) }
        }
        $cap = if ($stream -eq 'progress') { $w.ProgressCap } else { $w.FindingCap }
        if ($keep.Count -gt $cap) {
            # Entries are newest first, so everything past the cap is the oldest.
            for ($i = $cap; $i -lt $keep.Count; $i++) {
                Remove-Item -LiteralPath $keep[$i].File.FullName -Force -ErrorAction SilentlyContinue; $removed++
            }
        }
    }
    return $removed
}

function ConvertTo-AgentChatScopePath {
    param([Parameter(Mandatory)][string]$Path)
    $root = Get-AgentChatRepoRoot
    $p = $Path.Trim()
    if ([System.IO.Path]::IsPathRooted($p)) {
        $full = [System.IO.Path]::GetFullPath($p)
        $rootFull = [System.IO.Path]::GetFullPath($root).TrimEnd('\', '/')
        if ($full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
            $p = $full.Substring($rootFull.Length).TrimStart('\', '/')
        }
        else { throw "agent-chat-store: scope path is outside the repository: $Path" }
    }
    return ($p -replace '\\', '/').TrimEnd('/')
}

function New-AgentChatMessage {
    <#
    .SYNOPSIS
        Write one message to its stream. Returns the message object with its path.
    .DESCRIPTION
        A finding with neither -Scope nor -TtlMinutes is refused: a record nothing can invalidate
        would be a confident wrong answer forever (strategic §5.1 pillar 4). Throws on refused
        input; the CLI maps that to exit 1.
    #>
    param(
        [ValidateSet('progress', 'finding')][string]$Stream = 'progress',
        [Parameter(Mandatory)][string]$Kind,
        [string]$Ticket = '',
        [string]$Phase = '',
        [string[]]$Domains = @(),
        [string]$Note = '',
        [string]$Topic = '',
        [string]$EvidenceCommand = '',
        [Nullable[int]]$EvidenceExit = $null,
        [string]$EvidenceArtifact = '',
        [string[]]$Scope = @(),
        [Nullable[int]]$TtlMinutes = $null,
        [string]$Device = ''
    )

    if ($Script:AgentChatKinds -notcontains $Kind) {
        throw "agent-chat-store: unknown kind '$Kind' - accepted: $($Script:AgentChatKinds -join ', ')."
    }
    try { [void](Invoke-AgentChatSweep) } catch { }

    $w = Get-AgentChatWindows
    $identity = Get-AgentIdentity
    $nowUtc = [DateTime]::UtcNow
    $body = [ordered]@{
        schema  = $Script:AgentChatSchema
        stream  = $Stream
        at      = $nowUtc.ToString('o')
        agent   = $identity
        kind    = $Kind
        ticket  = $Ticket
        phase   = $Phase
        domains = @($Domains | Where-Object { $_ } | ForEach-Object { "$_" })
        note    = $Note
    }
    if ($Stream -eq 'finding') {
        if ([string]::IsNullOrWhiteSpace($Topic)) { throw 'agent-chat-store: a finding needs -Topic.' }
        $scopeList = @($Scope | Where-Object { $_ } | ForEach-Object { ConvertTo-AgentChatScopePath $_ } | Select-Object -Unique)
        if ($scopeList.Count -gt $Script:AgentChatScopeMax) {
            throw "agent-chat-store: scope carries $($scopeList.Count) paths; the cap is $($Script:AgentChatScopeMax) - name the directories that matter, not the tree."
        }
        if ($scopeList.Count -eq 0 -and $null -eq $TtlMinutes) {
            throw 'agent-chat-store: a finding needs a -Scope (paths whose change makes it wrong) or an explicit -TtlMinutes, or both.'
        }
        $ttl = if ($null -ne $TtlMinutes) { [int]$TtlMinutes } else { [int]$w.FindingTtlMinutes }
        $body.topic = $Topic
        $body.evidence = [ordered]@{ command = $EvidenceCommand; exitCode = $EvidenceExit; artifact = $EvidenceArtifact }
        $body.scope = $scopeList
        $body.ttlMinutes = $ttl
        $body.expiresAt = $nowUtc.AddMinutes($ttl).ToString('o')
        $body.device = $Device
    }

    $dir = Get-AgentChatStreamDir -Stream $Stream
    $json = $body | ConvertTo-Json -Depth 6 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $agentSafe = ConvertTo-AgentChatSafeName $identity.id
    $final = $null
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $rand = -join ((1..4) | ForEach-Object { '0123456789abcdef'[(Get-Random -Maximum 16)] })
        $name = '{0}Z_{1}_{2}_{3}.json' -f $nowUtc.ToString('yyyyMMddTHHmmssfff'), $Kind, $agentSafe, $rand
        $target = Join-Path $dir $name
        $staging = "$target.tmp-$PID"
        try {
            # $fs, not $stream: PowerShell variables are case-insensitive and $Stream is the
            # validated parameter above - assigning a FileStream to it fails the ValidateSet.
            $fs = [System.IO.File]::Open($staging, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
            try { $fs.Write($bytes, 0, $bytes.Length); $fs.Flush() } finally { $fs.Close() }
            Move-Item -LiteralPath $staging -Destination $target -ErrorAction Stop
            $final = $target
            break
        }
        catch {
            # Lost the name race (IOException) or anything else: drop the staging file and retry.
            Remove-Item -LiteralPath $staging -Force -ErrorAction SilentlyContinue
        }
    }
    if ($null -eq $final) { throw "agent-chat-store: could not create a message file under $dir after 3 attempts." }
    return (Read-AgentChatFile -Path $final)
}

function Get-AgentChatMessages {
    <#
    .SYNOPSIS
        Newest-first messages, filtered by agent, kind, ticket, domain or age. Unknown schema and
        unreadable files are skipped, never reported.
    #>
    param(
        [ValidateSet('progress', 'finding', 'all')][string]$Stream = 'progress',
        [string]$AgentId = '',
        [string]$Kind = '',
        [string]$Ticket = '',
        [string]$Domain = '',
        [int]$SinceMinutes = 0,
        [int]$Last = 20,
        [switch]$NoSweep
    )
    if (-not $NoSweep) { try { [void](Invoke-AgentChatSweep) } catch { } }
    $streams = if ($Stream -eq 'all') { @('progress', 'finding') } else { @($Stream) }
    $entries = @()
    foreach ($s in $streams) { $entries += @(Get-AgentChatFiles -Stream $s -AgentId $AgentId -Kind $Kind) }
    $entries = @($entries | Sort-Object { $_.Stamp } -Descending)
    $nowUtc = [DateTime]::UtcNow
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($e in $entries) {
        if ($SinceMinutes -gt 0) {
            $at = ConvertFrom-AgentChatStamp $e.Stamp
            if (($nowUtc - $at).TotalMinutes -gt $SinceMinutes) { break }   # sorted newest first
        }
        $msg = Read-AgentChatFile -Path $e.File.FullName
        if ($null -eq $msg) { continue }
        if ($Ticket -and [string](Get-AgentChatProp $msg 'ticket' '') -ne $Ticket) { continue }
        if ($Domain) {
            $doms = @(Get-AgentChatProp $msg 'domains' @())
            if (@($doms | Where-Object { "$_" -eq $Domain }).Count -eq 0) { continue }
        }
        $out.Add($msg)
        if ($Last -gt 0 -and $out.Count -ge $Last) { break }
    }
    return $out.ToArray()
}

function Get-AgentChatLastSeen {
    <#
    .SYNOPSIS
        UTC time of the agent's newest message in either stream, or $null. File names only.
    #>
    param([Parameter(Mandatory)][string]$AgentId)
    $newest = $null
    foreach ($s in @('progress', 'finding')) {
        $first = @(Get-AgentChatFiles -Stream $s -AgentId $AgentId | Select-Object -First 1)
        if ($first.Count -eq 0) { continue }
        $at = ConvertFrom-AgentChatStamp $first[0].Stamp
        if ($null -eq $newest -or $at -gt $newest) { $newest = $at }
    }
    return $newest
}

function Find-AgentChatAdb {
    foreach ($base in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\Sdk'))) {
        if ([string]::IsNullOrWhiteSpace($base)) { continue }
        $candidate = Join-Path $base 'platform-tools\adb.exe'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Test-AgentChatFindingAlive {
    <#
    .SYNOPSIS
        Alive means: not expired, nothing in its scope written after it, and its device (if any)
        still listed by adb. Any doubt is dead - a confident wrong answer is worse than none.
    #>
    param(
        [Parameter(Mandatory)]$Finding,
        # S2406: a caller judging many findings in one pass hands in a hashtable, and the newest write
        # under each scope path is measured once per pass instead of once per finding - enumerating
        # app_v2/src costs 241 ms, and the monitor page has a 1000 ms budget for the whole snapshot.
        [hashtable]$ScopeCache = $null
    )
    $nowUtc = [DateTime]::UtcNow
    $at = [DateTime](Get-AgentChatProp $Finding 'atUtc' $nowUtc)
    $exp = [string](Get-AgentChatProp $Finding 'expiresAt' '')
    if ($exp) {
        try {
            if ([DateTime]::Parse($exp, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal) -le $nowUtc) {
                return [pscustomobject]@{ Alive = $false; Reason = 'expired' }
            }
        }
        catch { return [pscustomobject]@{ Alive = $false; Reason = 'unreadable expiry' } }
    }
    $root = Get-AgentChatRepoRoot
    foreach ($rel in @(Get-AgentChatProp $Finding 'scope' @())) {
        $full = Join-Path $root ([string]$rel)
        if ($null -ne $ScopeCache -and $ScopeCache.ContainsKey($full)) {
            $latest = $ScopeCache[$full]
        }
        else {
            if (-not (Test-Path -LiteralPath $full)) { return [pscustomobject]@{ Alive = $false; Reason = "scope path gone: $rel" } }
            $item = Get-Item -LiteralPath $full -Force
            $latest = $item.LastWriteTimeUtc
            if ($item.PSIsContainer) {
                $m = Get-ChildItem -LiteralPath $full -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property LastWriteTimeUtc -Maximum
                if ($null -ne $m.Maximum -and $m.Maximum -gt $latest) { $latest = $m.Maximum }
            }
            if ($null -ne $ScopeCache) { $ScopeCache[$full] = $latest }
        }
        if ($null -eq $latest) { return [pscustomobject]@{ Alive = $false; Reason = "scope path gone: $rel" } }
        if ($latest -gt $at) { return [pscustomobject]@{ Alive = $false; Reason = "scope changed: $rel" } }
    }
    $device = [string](Get-AgentChatProp $Finding 'device' '')
    if ($device) {
        $adb = Find-AgentChatAdb
        if (-not $adb) { return [pscustomobject]@{ Alive = $false; Reason = 'adb not found, device unverifiable' } }
        $listed = $false
        try {
            $lines = @(& $adb devices 2>$null)
            $listed = @($lines | Where-Object { $_ -match "^\s*$([regex]::Escape($device))\s+device\b" }).Count -gt 0
        }
        catch { $listed = $false }
        if (-not $listed) { return [pscustomobject]@{ Alive = $false; Reason = "device not listed: $device" } }
    }
    return [pscustomobject]@{ Alive = $true; Reason = 'alive' }
}

function Find-AgentChatFindings {
    <#
    .SYNOPSIS
        Alive findings for a topic (exact or wildcard), newest first, plus dead count and dead findings with reasons.
    #>
    param(
        [Parameter(Mandatory)][string]$Topic,
        [int]$Last = 5
    )
    $all = @(Get-AgentChatMessages -Stream finding -Last 0)
    $alive = New-Object System.Collections.Generic.List[object]
    $deadList = New-Object System.Collections.Generic.List[object]
    $scopeCache = @{}
    foreach ($f in $all) {
        if ([string](Get-AgentChatProp $f 'topic' '') -notlike $Topic) { continue }
        $verdict = Test-AgentChatFindingAlive -Finding $f -ScopeCache $scopeCache
        if ($verdict.Alive) {
            if ($Last -le 0 -or $alive.Count -lt $Last) {
                $f | Add-Member -NotePropertyName 'liveness' -NotePropertyValue $verdict.Reason -Force
                $alive.Add($f)
            }
        }
        else {
            $deadList.Add([pscustomobject]@{
                Finding = $f
                Reason  = $verdict.Reason
            })
        }
    }
    return [pscustomobject]@{
        Alive        = $alive.ToArray()
        Dead         = $deadList.Count
        DeadFindings = $deadList.ToArray()
    }
}

function Get-AgentChatCoveringFinding {
    <#
    .SYNOPSIS
        Newest alive finding for a topic whose evidence command equals the request, optionally from caller's agent only.
    #>
    param(
        [Parameter(Mandatory)][string]$Topic,
        [Parameter(Mandatory)][string]$Request,
        [switch]$OwnAgentOnly
    )
    try {
        $found = Find-AgentChatFindings -Topic $Topic -Last 0
        $myId = if ($OwnAgentOnly) { (Get-AgentIdentity).id } else { '' }
        foreach ($f in $found.Alive) {
            if ($OwnAgentOnly) {
                $agentObj = Get-AgentChatProp $f 'agent'
                $authorId = [string](Get-AgentChatProp $agentObj 'id' '')
                if ($authorId -ne $myId) { continue }
            }
            $ev = Get-AgentChatProp $f 'evidence'
            $cmd = [string](Get-AgentChatProp $ev 'command' '')
            if ($cmd -and [string]::Equals($cmd, $Request, [StringComparison]::Ordinal)) {
                return $f
            }
        }
        return $null
    }
    catch {
        return $null
    }
}

function Get-AgentChatStatus {
    <#
    .SYNOPSIS
        One row per agent seen in the progress stream: its newest message and whether it is silent.
    #>
    $w = Get-AgentChatWindows
    $seen = @{}
    foreach ($m in @(Get-AgentChatMessages -Stream progress -Last 0)) {
        $id = [string](Get-AgentChatProp (Get-AgentChatProp $m 'agent') 'id' '?')
        if ($seen.ContainsKey($id)) { continue }   # newest first, so the first hit is the newest
        $seen[$id] = $m
    }
    $rows = foreach ($id in $seen.Keys) {
        $m = $seen[$id]
        $agent = Get-AgentChatProp $m 'agent'
        [pscustomobject]@{
            id         = $id
            name       = (Get-AgentChatDisplayName -Agent $agent)
            runtime    = [string](Get-AgentChatProp $agent 'runtime' 'unknown')
            model      = [string](Get-AgentChatProp $agent 'model' 'unknown')
            instance   = [string](Get-AgentChatProp $agent 'instance' '-')
            ageMinutes = [double](Get-AgentChatProp $m 'ageMinutes' 0)
            silent     = ([double](Get-AgentChatProp $m 'ageMinutes' 0) -gt $w.SilentMinutes)
            kind       = [string](Get-AgentChatProp $m 'kind' '')
            ticket     = [string](Get-AgentChatProp $m 'ticket' '')
            phase      = [string](Get-AgentChatProp $m 'phase' '')
            note       = [string](Get-AgentChatProp $m 'note' '')
        }
    }
    return @($rows | Sort-Object ageMinutes)
}

function Format-AgentChatAge {
    param([double]$Minutes)
    if ($Minutes -lt 1) { return 'now' }
    $whole = [int][math]::Floor($Minutes)
    if ($whole -lt 60) { return ('{0}m' -f $whole) }
    return ('{0}h{1:00}' -f [int][math]::Floor($whole / 60), ($whole % 60))
}

function Get-AgentChatDisplayName {
    <#
    .SYNOPSIS
        The nickname the owner recognises an agent by: the message's own, else the registry's, else
        the id's first eight characters (a pre-nickname message, or a name file already swept).
    #>
    param($Agent, [string]$Id = '')
    $name = [string](Get-AgentChatProp $Agent 'name' '')
    if (-not $name) {
        $id = if ($Id) { $Id } else { [string](Get-AgentChatProp $Agent 'id' '') }
        if ($id) { try { $name = [string](Get-AgentNickname -Id $id -NoCreate) } catch { $name = '' } }
        if (-not $name) { $name = if ($id.Length -gt 8) { $id.Substring(0, 8) } else { $id } }
    }
    return $name
}

function Format-AgentChatLine {
    <#
    .SYNOPSIS
        One printable line: age, kind, nickname, ticket/phase, note.
    #>
    param([Parameter(Mandatory)]$Message)
    $agent = Get-AgentChatProp $Message 'agent'
    $id = [string](Get-AgentChatProp $agent 'id' '?')
    $short = Get-AgentChatDisplayName -Agent $agent -Id $id
    $ticket = [string](Get-AgentChatProp $Message 'ticket' '')
    $phase = [string](Get-AgentChatProp $Message 'phase' '')
    $where = if ($ticket -and $phase) { "$ticket/$phase" } elseif ($ticket) { $ticket } else { '-' }
    $note = [string](Get-AgentChatProp $Message 'note' '')
    if ([string](Get-AgentChatProp $Message 'stream' '') -eq 'finding') {
        $note = ('[{0}] {1}' -f [string](Get-AgentChatProp $Message 'topic' ''), $note)
    }
    return ('{0,5}  {1,-9} {2,-22} {3,-12} {4}' -f (Format-AgentChatAge ([double](Get-AgentChatProp $Message 'ageMinutes' 0))), [string](Get-AgentChatProp $Message 'kind' ''), $short, $where, $note)
}

function Write-AgentChatContext {
    <#
    .SYNOPSIS
        Print up to N lines of a holder's chat and, optionally, a domain's, for a refusal message.
        Never throws: a chat failure must not alter the verdict it decorates.
    #>
    param(
        [string]$AgentId = '',
        [string]$Domain = '',
        [int]$Last = 3,
        [string]$Prefix = '  chat:'
    )
    try {
        $w = Get-AgentChatWindows
        $printed = 0
        if ($AgentId) {
            foreach ($m in @(Get-AgentChatMessages -Stream all -AgentId $AgentId -Last $Last)) {
                Write-Host ('{0} {1}' -f $Prefix, (Format-AgentChatLine $m)) -ForegroundColor DarkCyan; $printed++
            }
            if ($printed -eq 0) {
                $who = Get-AgentChatDisplayName -Agent $null -Id $AgentId
                Write-Host ('{0} nothing from {1} [{2}] in the last {3} min' -f $Prefix, $who, $AgentId, $w.ProgressRetentionMinutes) -ForegroundColor DarkGray
            }
        }
        if ($Domain) {
            foreach ($m in @(Get-AgentChatMessages -Stream progress -Domain $Domain -Last $Last)) {
                if ($AgentId -and [string](Get-AgentChatProp (Get-AgentChatProp $m 'agent') 'id' '') -eq $AgentId) { continue }
                Write-Host ('{0} {1}' -f $Prefix, (Format-AgentChatLine $m)) -ForegroundColor DarkCyan
            }
        }
    }
    catch {
        Write-Host ('{0} unavailable - {1}' -f $Prefix, $_.Exception.Message) -ForegroundColor DarkGray
    }
}

function Send-AgentChatMessage {
    <#
    .SYNOPSIS
        Best-effort post for writers embedded in other scripts: never throws, returns $true on success.
    #>
    param(
        [Parameter(Mandatory)][string]$Kind,
        [string]$Ticket = '',
        [string]$Phase = '',
        [string[]]$Domains = @(),
        [string]$Note = ''
    )
    try {
        [void](New-AgentChatMessage -Stream progress -Kind $Kind -Ticket $Ticket -Phase $Phase -Domains $Domains -Note $Note)
        return $true
    }
    catch { return $false }
}

function Send-AgentChatFinding {
    <#
    .SYNOPSIS
        Best-effort finding post for writers embedded in other scripts: never throws.
    #>
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Topic,
        [string]$Note = '',
        [string]$Ticket = '',
        [string[]]$Scope = @(),
        [Nullable[int]]$TtlMinutes = $null,
        [string]$Device = '',
        [string]$EvidenceCommand = '',
        [Nullable[int]]$EvidenceExit = $null,
        [string]$EvidenceArtifact = ''
    )
    try {
        [void](New-AgentChatMessage -Stream finding -Kind $Kind -Topic $Topic -Note $Note -Ticket $Ticket -Scope $Scope -TtlMinutes $TtlMinutes -Device $Device -EvidenceCommand $EvidenceCommand -EvidenceExit $EvidenceExit -EvidenceArtifact $EvidenceArtifact)
        return $true
    }
    catch { return $false }
}
