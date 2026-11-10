# The robot yields to the owner (TASK-FLOW rule 61; S0016 R64, decision D16 of 2026-11-10: the window is 3 minutes).
#
# Dot-source this file after loop.ps1 and picker.ps1; it defines functions only, sets no preference and prints nothing.
#
#   Get-PqTranscriptDir        the folder Claude Code keeps a repository's session transcripts in (~\.claude\projects\<path
#                              with every character that is not a letter or a digit written as '-'>), or $null.
#   Get-PqPassSessions         the session ids the dispatcher's own passes ran under (run\pass-sessions.json).
#   Add-PqPassSessions         remember more of them; the file keeps the newest 200.
#   Get-PqRepoOccupancy        is a repository that is not `concurrent` occupied by a live manual session: @{ occupied; by;
#                              holderKind; ageSeconds; detail }. Two kinds of evidence are read:
#                                transcript - a session transcript of the repository written within `occupiedMinutes`
#                                             (registry, default 10; the owner set 3) that is not one of the passes' own;
#                                lease      - a live ticket lease whose holder is not a dispatcher pass.
#                              A hold is not read here: the rank already skips a repository on hold.
#                              Not read: code and build locks. The owner's session that holds one writes its transcript
#                              the whole time, and a repository runner's lease is the lease evidence above, so both
#                              owners are already seen; a lock whose holder left no transcript and no lease is the gap.
#                              An unreadable lease listing is no evidence (it never blocks all work); a transcript folder
#                              that does not exist is no evidence either (an agent that writes none is invisible, rule 61).

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
            $doc = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($path)) -DateKind String -NoEnumerate
            foreach ($id in @($doc)) { if ($id) { [void]$set.Add([string]$id) } }
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
                    foreach ($id in @(ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($path)) -DateKind String -NoEnumerate)) { if ($id) { $all.Add([string]$id) } }
                }
            }
            catch { }
            foreach ($id in $new) { if (-not $all.Contains($id)) { $all.Add($id) } }
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

function Get-PqRepoOccupancy {
    param([Parameter(Mandatory)]$Repo, [Parameter(Mandatory)]$Registry, [string]$HarnessRoot, [switch]$NoLease)
    $path = [string]$Repo.path
    $minutes = [int](Get-PqValue $Registry 'occupiedMinutes' 10)
    $own = Get-PqPassSessions

    $dir = Get-PqTranscriptDir $path
    if ($null -ne $dir) {
        $newest = $null
        $newestId = ''
        try {
            foreach ($f in [IO.Directory]::GetFiles($dir, '*.jsonl')) {
                $sid = [IO.Path]::GetFileNameWithoutExtension($f)
                if ($own.Contains($sid)) { continue }
                $t = [IO.File]::GetLastWriteTimeUtc($f)
                if ($null -eq $newest -or $t -gt $newest) { $newest = $t; $newestId = $sid }
            }
        }
        catch { }
        if ($null -ne $newest) {
            $age = ([DateTime]::UtcNow - $newest).TotalMinutes
            if ($age -lt $minutes) {
                return @{ occupied = $true; by = 'transcript'; holderKind = 'manual'; ageSeconds = [int][Math]::Max(0, $age * 60); detail = $newestId }
            }
        }
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
                        return @{ occupied = $true; by = 'lease'; holderKind = $(if ($live -ceq 'undetermined') { 'unknown' } else { 'manual' }); ageSeconds = $age; detail = [string](Get-PqValue $lease 'id' '') }
                    }
                }
            }
        }
        catch { }
    }
    return @{ occupied = $false; by = $null; holderKind = $null; ageSeconds = 0; detail = '' }
}
