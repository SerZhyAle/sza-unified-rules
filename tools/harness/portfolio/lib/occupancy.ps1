# The robot yields to the owner (TASK-FLOW rule 61; S0016 R64, decision D16 of 2026-11-10: the window is 3 minutes).
#
# Dot-source this file after loop.ps1 and picker.ps1; it defines functions only, sets no preference and prints nothing.
#
#   Get-PqTranscriptDir        the folder Claude Code keeps a repository's session transcripts in (~\.claude\projects\<path
#                              with every character that is not a letter or a digit written as '-'>), or $null.
#   Get-PqPassSessions         the session ids the dispatcher's own passes ran under (run\pass-sessions.json).
#   Add-PqPassSessions         remember more of them; the file keeps the newest 200.
#   Get-PqTranscriptOccupiedRepos  the enabled repositories a live manual session holds, by transcript alone.
#   Get-PqRepoOccupancy        is a repository occupied by a live manual session: @{ occupied; by;
#                              holderKind; ageSeconds; freeInSeconds; detail }. Three kinds of evidence are read:
#                                transcript - a session transcript of the repository written within `occupiedMinutes`
#                                             (registry, default 10; the owner set 3) that is not one of the passes' own;
#                                lease      - a live ticket lease whose holder is not a dispatcher pass;
#                                lock       - a live code or build lock of the repository's lock store whose holder is not
#                                             a dispatcher pass (TASK-FLOW rule 61; CANONR-0196 C-G13). In a `concurrent`
#                                             repository only a lock of the ticket itself (-TicketId) counts.
#                              A hold is not read here: the rank already skips a repository on hold.
#                              An unreadable lease listing or lock file is no evidence (it never blocks all work); a transcript folder
#                              that does not exist is no evidence either (an agent that writes none is invisible, rule 61).
#                              -SkipTranscript drops the transcript kind for one call: the loop passes it for the repository
#                              a `pq start -Repo` worker names, where the owner's open session is not waited for (0.40).

function Get-PqTranscriptDir([string]$RepoPath) {
    $profileDir = $env:USERPROFILE
    if ([string]::IsNullOrWhiteSpace($profileDir)) { $profileDir = [Environment]::GetFolderPath('UserProfile') }
    $base = Join-Path (Join-Path $profileDir '.claude') 'projects'
    if (-not [IO.Directory]::Exists($base)) { return $null }
    $dir = Join-Path $base ([regex]::Replace([string]$RepoPath, '[^A-Za-z0-9]', '-'))
    if ([IO.Directory]::Exists($dir)) { return $dir }
    return $null
}

function Get-PqPassSessionsPath { return (Join-Path (Join-Path (Get-PqRoot) 'run') 'pass-sessions.json') }

function Get-PqPassSessions {
    $set = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    try {
        $path = Get-PqPassSessionsPath
        if ([IO.File]::Exists($path)) {
            $doc = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($path)) -DateKind String
            foreach ($item in @($doc)) {
                if ($null -eq $item) { continue }
                foreach ($id in ([string]$item -split '\s+')) {
                    if ($id) { [void]$set.Add($id) }
                }
            }
        }
    }
    catch { }
    return , $set
}

function Add-PqPassSessions([string[]]$Ids) {
    $new = @(@($Ids) | Where-Object { $_ })
    if ($new.Count -eq 0) { return }
    $path = Get-PqPassSessionsPath
    try {
        Invoke-PqStateLock {
            $dir = Split-Path -Parent $path
            if (-not [IO.Directory]::Exists($dir)) { $null = [IO.Directory]::CreateDirectory($dir) }
            $all = [Collections.Generic.List[string]]::new()
            try {
                if ([IO.File]::Exists($path)) {
                    $existing = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($path)) -DateKind String
                    foreach ($item in @($existing)) {
                        if ($null -eq $item) { continue }
                        foreach ($id in ([string]$item -split '\s+')) {
                            if ($id -and -not $all.Contains($id)) { $all.Add($id) }
                        }
                    }
                }
            }
            catch { }
            foreach ($entry in $new) {
                foreach ($id in ([string]$entry -split '\s+')) {
                    if ($id -and -not $all.Contains($id)) { $all.Add($id) }
                }
            }
            $keep = if ($all.Count -gt 200) { $all.GetRange($all.Count - 200, 200) } else { $all }
            $tmp = "$path.$PID.tmp"
            [IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject @($keep) -Compress), [Text.UTF8Encoding]::new($false))
            [IO.File]::Move($tmp, $path, $true)
        }
    }
    catch { }
}

# The holder of a lease is a dispatcher pass when the lease says the runner took it for a pass of its own
# (reason 'run-spec-queue pq<k>', the form Remove-PqKilledPassLease also relies on) or names a session a pass ran under.
function Test-PqLeaseIsPass($Lease, $PassSessions) {
    if ([string](Get-PqValue $Lease 'reason' '') -match '^run-spec-queue pq\d+') { return $true }
    $sid = [string](Get-PqValue $Lease 'sessionId' '')
    return ($sid -and $null -ne $PassSessions -and $PassSessions.Contains($sid))
}

function Test-PqTranscriptIsRobot([string]$FilePath) {
    try {
        if (-not [IO.File]::Exists($FilePath)) { return $false }
        $fs = [IO.File]::Open($FilePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            $buf = [byte[]]::new(1024)
            $read = $fs.Read($buf, 0, 1024)
            if ($read -le 0) { return $false }
            $snippet = [Text.Encoding]::UTF8.GetString($buf, 0, $read)
            return ($snippet.Contains('an unattended queue pass'))
        }
        finally {
            $fs.Dispose()
        }
    }
    catch {
        return $false
    }
}

# The repository's lock store (paths.locksDir of its profile, the canon default 'temp'), resolved against the repository.
function Get-PqRepoLocksDir([string]$RepoPath) {
    $rel = 'temp'
    if ($null -ne (Get-Variable -Name PqRepoDefaults -Scope Script -ErrorAction Ignore)) {
        $d = [string]$script:PqRepoDefaults.paths['locksDir']
        if ($d) { $rel = $d }
    }
    $profileFile = Join-Path $RepoPath '.sza-profile.json'
    if ([IO.File]::Exists($profileFile)) {
        try {
            $p = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($profileFile)) -DateKind String
            $v = $p.paths.locksDir
            if ($v -is [string] -and $v) { $rel = $v }
        }
        catch { }
    }
    if ([IO.Path]::IsPathRooted($rel)) { return $rel }
    return (Join-Path $RepoPath $rel)
}

# A lock's process is alive with the start time the lock recorded. A StartTime the process denies counts as alive, as
# agent-lock.ps1's own status read does; a lock without procStart is judged by the pid alone.
function Test-PqLockProcessAlive([int]$ProcessId, [long]$ProcStart) {
    if ($ProcessId -le 0) { return $false }
    $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $proc) { return $false }
    if ($ProcStart -eq 0) { return $true }
    try { return ($proc.StartTime.Ticks -eq $ProcStart) } catch { return $true }
}

# The pass intervals of one repository (TASK-FLOW rule 61, lock evidence): the live pass of the repository lock
# run\repo-<key>.lock (passStartedAt to now, its runner pid) and the finished passes of runs.jsonl (finishedAt minus
# seconds to finishedAt; finishedAt is local time). Only the last 512 KB of runs.jsonl are read. -> @{ intervals; runners }.
function Get-PqRepoPassIntervals([string]$RepoKey) {
    $intervals = [Collections.Generic.List[object]]::new()
    $runners = [Collections.Generic.List[int]]::new()
    $root = $null
    try { $root = Get-PqRoot } catch { $root = $null }
    if (-not $root) { return @{ intervals = $intervals; runners = $runners } }
    try {
        $lf = Join-Path (Join-Path $root 'run') "repo-$RepoKey.lock"
        if ([IO.File]::Exists($lf)) {
            $st = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($lf)) -DateKind String
            $passPid = [int](Get-PqValue $st 'passPid' 0)
            $since = [string](Get-PqValue $st 'passStartedAt' '')
            if ($passPid -gt 0 -and $since) {
                $start = [DateTimeOffset]::Parse($since, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime
                $proc = Get-Process -Id $passPid -ErrorAction SilentlyContinue
                $same = $false
                if ($null -ne $proc) { try { $same = ([Math]::Abs(($proc.StartTime.ToUniversalTime() - $start).TotalSeconds) -lt 2) } catch { $same = $true } }
                if ($same) {
                    $runners.Add($passPid)
                    $intervals.Add(@{ start = $start; end = [DateTime]::UtcNow })
                }
            }
        }
    }
    catch { }
    try {
        $runs = Join-Path $root 'runs.jsonl'
        if ([IO.File]::Exists($runs)) {
            $fs = [IO.FileStream]::new($runs, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
            try {
                $take = [long][Math]::Min($fs.Length, 524288)
                $null = $fs.Seek(-$take, [IO.SeekOrigin]::End)
                $buf = [byte[]]::new($take)
                $n = 0
                while ($n -lt $take) { $r = $fs.Read($buf, $n, $take - $n); if ($r -le 0) { break }; $n += $r }
                $text = [Text.Encoding]::UTF8.GetString($buf, 0, $n)
            }
            finally { $fs.Dispose() }
            $needle = '"repo":"' + $RepoKey + '"'
            foreach ($line in $text -split "`n") {
                if (-not $line.Contains($needle)) { continue }
                try { $row = ConvertFrom-Json -InputObject $line -DateKind String } catch { continue }
                if ([string]$row.repo -cne $RepoKey) { continue }
                $fin = [DateTime]::MinValue
                if (-not [DateTime]::TryParse([string]$row.finishedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeLocal, [ref]$fin)) { continue }
                $end = $fin.ToUniversalTime()
                $secs = 0.0
                if ($null -ne $row.seconds) { $secs = [double]$row.seconds } elseif ($null -ne $row.minutes) { $secs = [double]$row.minutes * 60 }
                $intervals.Add(@{ start = $end.AddSeconds(-$secs); end = $end })
            }
        }
    }
    catch { }
    return @{ intervals = $intervals; runners = $runners }
}

# The holder of a lock is a dispatcher pass (TASK-FLOW rule 61): its process descends from the runner process of a live
# pass, or its acquiredAt lies inside one of the repository's pass intervals widened by 60 seconds at each end.
function Test-PqLockIsPass([DateTime]$AcquiredUtc, [int]$ProcessId, [bool]$Alive, $Passes) {
    foreach ($iv in @($Passes.intervals)) {
        if ($AcquiredUtc -ge $iv.start.AddSeconds(-60) -and $AcquiredUtc -le $iv.end.AddSeconds(60)) { return $true }
    }
    if (-not $Alive -or @($Passes.runners).Count -eq 0) { return $false }
    try {
        $parent = @{}
        foreach ($p in @(Get-CimInstance -ClassName Win32_Process -Property ProcessId, ParentProcessId -ErrorAction Stop)) {
            $parent[[int]$p.ProcessId] = [int]$p.ParentProcessId
        }
        $at = $ProcessId
        for ($hop = 0; $hop -lt 32 -and $parent.ContainsKey($at); $hop++) {
            if (@($Passes.runners) -contains $at) { return $true }
            $next = $parent[$at]
            if ($next -le 0 -or $next -eq $at) { break }
            $at = $next
        }
        if (@($Passes.runners) -contains $at) { return $true }
    }
    catch { }
    return $false
}

# The first live lock of the repository's lock store whose holder is not a dispatcher pass, as an occupancy result, else
# $null. A lock is live while its process (same start time) is alive or while acquiredAt is younger than
# occupiedMinutes (rule 61). In a concurrent repository only a lock whose reason begins with the ticket's id as a whole
# word counts. Queue folders (<NAME>.QUEUE) and unreadable files are no evidence.
function Get-PqRepoLockOccupancy([string]$RepoPath, [string]$RepoKey, [int]$Minutes, [bool]$Concurrent, [string]$TicketId) {
    if ($Concurrent -and -not $TicketId) { return $null }
    $dir = Get-PqRepoLocksDir $RepoPath
    if (-not [IO.Directory]::Exists($dir)) { return $null }
    $files = @()
    try { $files = @([IO.Directory]::GetFiles($dir, '*.LOCK')) } catch { return $null }
    if ($files.Count -eq 0) { return $null }
    $passes = $null
    $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    foreach ($f in $files) {
        $raw = $null
        try { $raw = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($f)) -DateKind String } catch { continue }
        if ($null -eq $raw -or $raw -isnot [Management.Automation.PSCustomObject]) { continue }
        if ($null -eq $raw.acquiredAt -or $null -eq $raw.lockType) { continue }
        $acq = 0L
        if (-not [long]::TryParse([string]$raw.acquiredAt, [ref]$acq)) { continue }
        $ageSec = [Math]::Max(0, ($nowMs - $acq) / 1000.0)
        $procStart = 0L
        if ($null -ne $raw.procStart) { $null = [long]::TryParse([string]$raw.procStart, [ref]$procStart) }
        $pidValue = 0
        if ($null -ne $raw.pid) { $null = [int]::TryParse([string]$raw.pid, [ref]$pidValue) }
        $alive = Test-PqLockProcessAlive $pidValue $procStart
        if (-not $alive -and $ageSec -ge ($Minutes * 60)) { continue }
        $reason = [string]$raw.reason
        if ($Concurrent -and $reason -notmatch ('^' + [regex]::Escape($TicketId) + '\b')) { continue }
        if ($null -eq $passes) { $passes = Get-PqRepoPassIntervals $RepoKey }
        $acqUtc = [DateTimeOffset]::FromUnixTimeMilliseconds($acq).UtcDateTime
        if (Test-PqLockIsPass $acqUtc $pidValue $alive $passes) { continue }
        $freeIn = if ($alive) { 0 } else { [int][Math]::Ceiling([Math]::Max(0, $Minutes * 60 - $ageSec)) }
        return @{ occupied = $true; by = 'lock'; holderKind = 'manual'; ageSeconds = [int]$ageSec; freeInSeconds = $freeIn
            detail = ([IO.Path]::GetFileName($f) + $(if ($reason) { " $reason" } else { '' })) }
    }
    return $null
}

function Get-PqRepoOccupancy {
    # -SkipTranscript: the repository is the one an owner's `pq start -Repo` names (TASK-FLOW 0.40 section 18), so a session
    # of the owner there is not waited for; the lease evidence below is still read.
    # -NoLock drops the lock kind (the transcript-only pre-mark); -TicketId names the ticket a lock of a concurrent
    # repository must belong to.
    param([Parameter(Mandatory)]$Repo, [Parameter(Mandatory)]$Registry, [string]$HarnessRoot, [switch]$NoLease, [switch]$SkipTranscript,
        [switch]$NoLock, [string]$TicketId)
    $path = [string]$Repo.path
    $minutes = [int](Get-PqValue $Registry 'occupiedMinutes' 10)
    $own = Get-PqPassSessions

    $dir = if ($SkipTranscript) { $null } else { Get-PqTranscriptDir $path }
    if ($null -ne $dir) {
        $newest = $null
        $newestId = ''
        try {
            $cutoff = [DateTime]::UtcNow.AddMinutes(-$minutes)
            foreach ($f in [IO.Directory]::GetFiles($dir, '*.jsonl')) {
                $t = [IO.File]::GetLastWriteTimeUtc($f)
                if ($t -lt $cutoff) { continue }
                $sid = [IO.Path]::GetFileNameWithoutExtension($f)
                if ($own.Contains($sid)) { continue }
                if (Test-PqTranscriptIsRobot $f) { continue }
                if ($null -eq $newest -or $t -gt $newest) { $newest = $t; $newestId = $sid }
            }
        }
        catch { }
        if ($null -ne $newest) {
            $age = ([DateTime]::UtcNow - $newest).TotalMinutes
            if ($age -lt $minutes) {
                # freeInSeconds: a transcript only gets younger, so the repository cannot be free before the window runs out.
                return @{ occupied = $true; by = 'transcript'; holderKind = 'manual'; ageSeconds = [int][Math]::Max(0, $age * 60); freeInSeconds = [int][Math]::Ceiling([Math]::Max(0, ($minutes - $age) * 60)); detail = $newestId }
            }
        }
    }

    if (-not $NoLock) {
        $concurrent = (Get-PqValue $Repo 'concurrent' $false) -eq $true
        $lockOcc = $null
        try { $lockOcc = Get-PqRepoLockOccupancy -RepoPath $path -RepoKey ([string](Get-PqValue $Repo 'key' '')) -Minutes $minutes -Concurrent $concurrent -TicketId $TicketId }
        catch { $lockOcc = $null }
        if ($null -ne $lockOcc) { return $lockOcc }
    }

    if (-not $NoLease) {
        try {
            $script = Join-Path (Get-PqHarnessRoot $HarnessRoot) 'locks\ticket-lease.ps1'
            $r = Invoke-PqRepoChild -RepoPath $path -Script $script -Arguments @('-Verb', 'Status', '-Json') -TimeoutSeconds 60
            if (-not $r.timedOut -and $r.code -eq 0) {
                $parsed = ConvertFrom-PqLastJsonLine ([string]$r.stdout) -Array
                if ($parsed.ok) {
                    foreach ($lease in @($parsed.value)) {
                        if ($null -eq $lease) { continue }
                        $live = [string](Get-PqValue $lease 'liveness' '')
                        if ($live -cnotin @('foreign-live', 'undetermined')) { continue }
                        if (Test-PqLeaseIsPass $lease $own) { continue }
                        $quiet = Get-PqValue $lease 'lastSeenMinutes'
                        $age = if ($null -ne $quiet) { [int]([double]$quiet * 60) } else { 0 }
                        return @{ occupied = $true; by = 'lease'; holderKind = $(if ($live -ceq 'undetermined') { 'unknown' } else { 'manual' }); ageSeconds = $age; freeInSeconds = 0; detail = [string](Get-PqValue $lease 'id' '') }
                    }
                }
            }
        }
        catch { }
    }
    return @{ occupied = $false; by = $null; holderKind = $null; ageSeconds = 0; freeInSeconds = 0; detail = '' }
}

# Every enabled repository a session of the owner holds right now, read from transcripts alone: a directory listing and a
# 1 KB read per repository, no lease listing and so no child process. The loop marks them all before it ranks, so one walk
# of the rank goes past all of them. Without it the rank hands back one occupied repository per walk, a walk costs
# seconds to minutes, and the half-minute mark of the first one has lapsed before the walk for the second one is done.
# Returns an ordered map repository key -> the Get-PqRepoOccupancy result.
function Get-PqTranscriptOccupiedRepos {
    param([Parameter(Mandatory)]$Registry, [string]$HarnessRoot)
    $found = [ordered]@{}
    foreach ($r in @($Registry.repos)) {
        if ((Get-PqValue $r 'enabled' $false) -ne $true) { continue }
        $key = [string](Get-PqValue $r 'key' '')
        if (-not $key) { continue }
        try { $occ = Get-PqRepoOccupancy -Repo $r -Registry $Registry -HarnessRoot $HarnessRoot -NoLease -NoLock }
        catch { continue }
        if ($occ.occupied) { $found[$key] = $occ }
    }
    return $found
}
